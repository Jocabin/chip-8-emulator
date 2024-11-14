package emulator

import "core:fmt"
import "core:math/rand"
import "core:mem"
import "core:os"
import rl "vendor:raylib"

RAM_SIZE :: 4096
RAM_START_ADDR :: 0x200

COL_COUNT :: 64
ROW_COUNT :: 32
PIXEL_SIZE :: 20

EXEC_FREQUENCY: f32 : 1 / 60

Chip_Context :: struct {
	memory:               [RAM_SIZE]u8,
	stack:                [16]u16,
	registers:            [16]u8,
	pc, sp:               u16,
	i_reg:                u16,
	delay_reg, sound_reg: u8,
	should_draw:          bool,
	framebuffer:          [COL_COUNT * ROW_COUNT]bool,
	wait_for_key:         bool,
	wait_for_key_reg:     u8,
	keypad:               [16]bool,
}

main :: proc() {
	// track for memory leaks
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	///////////////////////////////////////////////////////////////
	// Chip 8 memory initialization
	///////////////////////////////////////////////////////////////

	ctx: Chip_Context
	args := os.args[1:]

	if len(args) != 1 {
		fmt.eprintln("Usage: ./emulator <rom-name>")
		return
	}

	data, data_read_ok := os.read_entire_file_from_filename(args[0])

	if data_read_ok == false {
		fmt.eprintln("Error reading the rom name")
		return
	}

	if size_of(data) > size_of(ctx.memory) - RAM_START_ADDR {
		fmt.eprintln("Rom file size too big, can't fit in memory")
		return
	}

	copy(ctx.memory[RAM_START_ADDR:], data)
	delete(data)
	ctx.pc = RAM_START_ADDR
	
        // odinfmt:disable
        font_atlas: []u8 = {
                0xF0, 0x90, 0x90, 0x90, 0xF0,   // 0   
                0x20, 0x60, 0x20, 0x20, 0x70,   // 1  
                0xF0, 0x10, 0xF0, 0x80, 0xF0,   // 2 
                0xF0, 0x10, 0xF0, 0x10, 0xF0,   // 3
                0x90, 0x90, 0xF0, 0x10, 0x10,   // 4    
                0xF0, 0x80, 0xF0, 0x10, 0xF0,   // 5
                0xF0, 0x80, 0xF0, 0x90, 0xF0,   // 6
                0xF0, 0x10, 0x20, 0x40, 0x40,   // 7
                0xF0, 0x90, 0xF0, 0x90, 0xF0,   // 8
                0xF0, 0x90, 0xF0, 0x10, 0xF0,   // 9
                0xF0, 0x90, 0xF0, 0x90, 0x90,   // A
                0xE0, 0x90, 0xE0, 0x90, 0xE0,   // B
                0xF0, 0x80, 0x80, 0x80, 0xF0,   // C
                0xE0, 0x90, 0x90, 0x90, 0xE0,   // D
                0xF0, 0x80, 0xF0, 0x80, 0xF0,   // E
                0xF0, 0x80, 0xF0, 0x80, 0x80,   // F
        }
        // odinfmt:enable
	copy(ctx.memory[:], font_atlas)

	///////////////////////////////////////////////////////////////
	// Raylib initialization
	///////////////////////////////////////////////////////////////

	rl.SetConfigFlags({.WINDOW_ALWAYS_RUN, .VSYNC_HINT, .MSAA_4X_HINT})
	rl.InitWindow(COL_COUNT * PIXEL_SIZE, ROW_COUNT * PIXEL_SIZE, "Chip-8 emulator in Odin")
	defer rl.CloseWindow()

	start_t, end_t, elapsed_t: f32

	for !rl.WindowShouldClose() {
		free_all(context.temp_allocator)

		start_t = rl.GetFrameTime()

		// Handling input
		if ctx.wait_for_key {
			for key, index in ctx.keypad {
				if key {
					ctx.registers[ctx.wait_for_key_reg] = u8(index)
					ctx.wait_for_key = false
				}
			}
			return
		}

		// Fetch instructions from memory
		opcode := u16(ctx.memory[ctx.pc]) << 8 | u16(ctx.memory[ctx.pc + 1])
		// if rl.IsKeyPressed(.SPACE) {
		ctx.pc += 2

		// Execute instructions
		emulate_chip(&ctx, opcode)
		// }

		// Draw on the screen
		rl.BeginDrawing()
		if ctx.should_draw {
			rl.ClearBackground(rl.BLACK)
			update_screen(ctx)

			ctx.should_draw = false
		}
		// fmt.printfln("opcode: 0x%04X", opcode)
		// rl.DrawText(rl.TextFormat("opcode: 0x%04X", opcode), 200, 0, 20, rl.RED)
		// rl.DrawText(rl.TextFormat("pc: 0x%04X", ctx.pc), 200, 20, 20, rl.RED)
		// rl.DrawText(rl.TextFormat("sp: 0x%04X", ctx.sp), 200, 40, 20, rl.RED)
		// rl.DrawText(rl.TextFormat("I: 0x%04X", ctx.i_reg), 200, 60, 20, rl.RED)
		// rl.DrawText(rl.TextFormat("regs: %04X", ctx.registers), 200, 80, 20, rl.RED)
		rl.EndDrawing()

		end_t = rl.GetFrameTime()
		elapsed_t = end_t - start_t

		if elapsed_t < EXEC_FREQUENCY {
			rl.WaitTime(f64(EXEC_FREQUENCY - elapsed_t))
		}
	}
}

update_screen :: proc(ctx: Chip_Context) {
	for x: i32; x < COL_COUNT; x += 1 {
		for y: i32; y < ROW_COUNT; y += 1 {
			if ctx.framebuffer[y * COL_COUNT + x] == true {
				pixel := rl.Rectangle {
					f32(x) * PIXEL_SIZE,
					f32(y) * PIXEL_SIZE,
					PIXEL_SIZE,
					PIXEL_SIZE,
				}
				rl.DrawRectangleRec(pixel, rl.WHITE)
			}
		}
	}
}

update_timers :: proc(ctx: ^Chip_Context) {
	if ctx.delay_reg > 0 do ctx.delay_reg -= 1

	if ctx.sound_reg > 0 {
		ctx.sound_reg -= 1
		// todo: play sound
		fmt.println("play sound; ", ctx.sound_reg)
	}
}

emulate_chip :: proc(ctx: ^Chip_Context, opcode: u16) {
	nnn := opcode & 0x0FFF
	kk := u8(opcode & 0x0FF)
	n := u8(opcode & 0x0F)
	x := u8((opcode >> 8) & 0x0F)
	y := u8((opcode >> 4) & 0x0F)

	switch (opcode >> 12) & 0x0F {
	case 0x00:
		if kk == 0xE0 {
			mem.zero_slice(ctx.framebuffer[:])
			ctx.should_draw = true
		} else if kk == 0xEE {
			ctx.sp -= 1
			ctx.pc = ctx.stack[ctx.sp]
		} else do panic("Unimplemented instruction")
	case 0x01:
		ctx.pc = nnn
	case 0x02:
		ctx.stack[ctx.sp] = ctx.pc
		ctx.sp += 1
		ctx.pc = nnn
	case 0x03:
		if ctx.registers[x] == kk do ctx.pc += 2
	case 0x04:
		if ctx.registers[x] != kk do ctx.pc += 2
	case 0x05:
		if ctx.registers[x] == ctx.registers[y] do ctx.pc += 2
	case 0x06:
		ctx.registers[x] = kk
	case 0x07:
		ctx.registers[x] += kk
	case 0x08:
		switch n {
		case 0:
			ctx.registers[x] = ctx.registers[y]
		case 1:
			ctx.registers[x] |= ctx.registers[y]
		case 2:
			ctx.registers[x] &= ctx.registers[y]
		case 3:
			ctx.registers[x] ~= ctx.registers[y]
		case 4:
			ctx.registers[0xF] = (ctx.registers[x] + ctx.registers[y]) > 255 ? 1 : 0
			ctx.registers[x] += ctx.registers[y]
		case 5:
			ctx.registers[0xF] = ctx.registers[x] > ctx.registers[y]
			ctx.registers[x] -= ctx.registers[y]
		case 6:
			ctx.registers[0xF] = ctx.registers[x] & 0x01
			ctx.registers[x] >>= 2
		case 7:
			ctx.registers[0xF] = ctx.registers[y] > ctx.registers[x]
			ctx.registers[x] = ctx.registers[y] - ctx.registers[x]
		case 0xE:
			ctx.registers[0xF] = ctx.registers[x] & 0x80
			ctx.registers[x] <<= 2
		case:
			panic("Unimplemented instruction")
		}
	case 0x09:
		if ctx.registers[x] != ctx.registers[y] do ctx.pc += 2
	case 0x0A:
		ctx.i_reg = nnn
	case 0x0B:
		ctx.pc = nnn + u16(ctx.registers[0])
	case 0x0C:
		rand_n := u8(rand.int_max(256))
		ctx.registers[x] = rand_n & kk
	case 0x0D:
		vx := ctx.registers[x]
		vy := ctx.registers[y]

		ctx.registers[0xF] = 0

		for y := 0; y < int(n); y += 1 {
			b := ctx.memory[int(ctx.i_reg) + y]
			yy := (int(vy) + y) % ROW_COUNT

			for x := 0; x < 8; x += 1 {
				bit := u8(b & 0b1000_0000 > 0 ? 1 : 0)
				b <<= 1

				xx := (int(vx) + x) % COL_COUNT
				screen_bit := ctx.framebuffer[xx + yy * COL_COUNT]

				if screen_bit == true && bit == 1 do ctx.registers[0xf] = 1

				ctx.framebuffer[xx + yy * COL_COUNT] = u8(screen_bit) ~ bit > 0
			}
		}
		ctx.should_draw = true
	case 0x0E:
		if kk == 0x9E {
			if ctx.keypad[ctx.registers[x]] == true do ctx.pc += 2
		} else if kk == 0xA1 {
			if ctx.keypad[ctx.registers[x]] == false do ctx.pc += 2
		} else do panic("Unimplemented instruction")
	case 0x0F:
		switch kk {
		case 0x07:
			ctx.registers[x] = ctx.delay_reg
		case 0x0A:
			ctx.wait_for_key_reg = x
			ctx.wait_for_key = true
		case 0x15:
			ctx.delay_reg = ctx.registers[x]
		case 0x18:
			ctx.sound_reg = ctx.registers[x]
		case 0x1E:
			ctx.i_reg += u16(ctx.registers[x])
		case 0x29:
			ctx.i_reg = u16(ctx.registers[x] * 5)
		case 0x33:
			val := ctx.registers[x]
			ctx.memory[ctx.i_reg + 2] = val % 10
			val /= 10
			ctx.memory[ctx.i_reg + 1] = val % 10
			val /= 10
			ctx.memory[ctx.i_reg] = val % 10
			val /= 10
		case 0x55:
			copy(ctx.memory[ctx.i_reg:ctx.i_reg + u16(x)], ctx.registers[:x])
		case 0x65:
			copy(ctx.registers[:x], ctx.memory[ctx.i_reg:ctx.i_reg + u16(x)])
		}
	}
}
