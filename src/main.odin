package emulator

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import rl "vendor:raylib"

RAM_SIZE :: 4096
RAM_START_ADDR :: 0x200

DISPLAY_WIDTH :: 64
DISPLAY_HEIGHT :: 32
PIXEL_SIZE :: 16
TARGET_FPS :: 60
INSTRUCTION_PER_SECOND :: 600
INSTRUCTIONS_PER_FRAME :: INSTRUCTION_PER_SECOND / TARGET_FPS

SAMPLE_RATE :: 44100
SAMPLE_SIZE :: 32
NUM_CHANNELS :: 1
FREQUENCY :: 440.0
AMPLITUDE :: 0.2

Chip_Context :: struct {
	mem:                      [RAM_SIZE]u8,
	stack:                    [16]u16,
	reg_v:                    [16]u8,
	pc, sp:                   u16,
	i_reg:                    u16,
	delay_timer, sound_timer: u8,
	framebuffer:              [DISPLAY_WIDTH * DISPLAY_HEIGHT]bool,
	keypad:                   [16]bool,
}

// todo: fix sound
// todo: fix PONG
// todo: fix keypad NOT HALTING
// todo: validate all test roms
// todo: optimize perfs

main :: proc() {
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

	if size_of(data) > size_of(ctx.mem) - RAM_START_ADDR {
		fmt.eprintln("Rom file size too big, can't fit in mem")
		return
	}

	copy(ctx.mem[RAM_START_ADDR:], data)
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
	copy(ctx.mem[:], font_atlas)

	rl.SetTargetFPS(TARGET_FPS)
	rl.SetTraceLogLevel(.NONE)

	rl.InitWindow(
		DISPLAY_WIDTH * PIXEL_SIZE,
		DISPLAY_HEIGHT * PIXEL_SIZE,
		"Chip-8 emulator in Odin",
	)
	defer rl.CloseWindow()

	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()

	audio_stream := rl.LoadAudioStream(SAMPLE_RATE, SAMPLE_RATE, NUM_CHANNELS)
	defer rl.UnloadAudioStream(audio_stream)

	rl.SetAudioStreamCallback(audio_stream, audio_callback)

	rl.PlayAudioStream(audio_stream)
	defer rl.StopAudioStream(audio_stream)

	for !rl.WindowShouldClose() {
		free_all(context.temp_allocator)

		handle_keys(&ctx)

		rl.BeginDrawing()

		for i in 0 ..< INSTRUCTIONS_PER_FRAME {
			emulate_chip(&ctx)
		}

		if ctx.delay_timer > 0 do ctx.delay_timer -= 1
		if ctx.sound_timer > 0 do ctx.sound_timer -= 1

		if ctx.sound_timer > 0 {
			rl.ResumeAudioStream(audio_stream)
		} else {
			rl.PauseAudioStream(audio_stream)
		}

		update_screen(ctx)

		rl.EndDrawing()
	}
}

update_screen :: proc(ctx: Chip_Context) {
	rl.ClearBackground(rl.BLACK)
	for x: i32; x < DISPLAY_WIDTH; x += 1 {
		for y: i32; y < DISPLAY_HEIGHT; y += 1 {
			if ctx.framebuffer[y * DISPLAY_WIDTH + x] == true {
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

emulate_chip :: proc(ctx: ^Chip_Context) {
	opcode := u16(ctx.mem[ctx.pc]) << 8 | u16(ctx.mem[ctx.pc + 1])

	nnn := opcode & 0x0FFF
	kk := u8(opcode & 0x0FF)
	n := u8(opcode & 0x0F)
	x := u8((opcode >> 8) & 0x0F)
	y := u8((opcode >> 4) & 0x0F)

	ctx.pc += 2

	switch (opcode >> 12) & 0x0F {
	case 0x00:
		if kk == 0xE0 {
			mem.zero_slice(ctx.framebuffer[:])
		} else if kk == 0xEE {
			ctx.sp -= 1
			ctx.pc = ctx.stack[ctx.sp]
			ctx.stack[ctx.sp] = 0
		} else do panic("Unimplemented instruction")
	case 0x01:
		ctx.pc = nnn
	case 0x02:
		ctx.stack[ctx.sp] = ctx.pc
		ctx.sp += 1
		ctx.pc = nnn
	case 0x03:
		if ctx.reg_v[x] == kk do ctx.pc += 2
	case 0x04:
		if ctx.reg_v[x] != kk do ctx.pc += 2
	case 0x05:
		if ctx.reg_v[x] == ctx.reg_v[y] do ctx.pc += 2
	case 0x06:
		ctx.reg_v[x] = kk
	case 0x07:
		ctx.reg_v[x] += kk
	case 0x08:
		switch n {
		case 0:
			ctx.reg_v[x] = ctx.reg_v[y]
		case 1:
			ctx.reg_v[x] |= ctx.reg_v[y]
		case 2:
			ctx.reg_v[x] &= ctx.reg_v[y]
		case 3:
			ctx.reg_v[x] ~= ctx.reg_v[y]
		case 4:
			sum := u16(ctx.reg_v[x]) + u16(ctx.reg_v[y])
			ctx.reg_v[x] = u8(sum)
			ctx.reg_v[0xF] = sum > 255 ? 1 : 0
		case 5:
			ctx.reg_v[x] -= ctx.reg_v[y]
			ctx.reg_v[0xF] = ctx.reg_v[x] > ctx.reg_v[y] ? 1 : 0
		case 6:
			ctx.reg_v[x] >>= 1
			ctx.reg_v[0xF] = ctx.reg_v[x] & 0x1 == 1 ? 1 : 0
		case 7:
			ctx.reg_v[x] = ctx.reg_v[y] - ctx.reg_v[x]
			ctx.reg_v[0xF] = ctx.reg_v[y] > ctx.reg_v[x] ? 1 : 0
		case 0xE:
			ctx.reg_v[x] <<= 1
			ctx.reg_v[0xF] = ctx.reg_v[x] >> 7
		case:
			panic("Unimplemented instruction")
		}
	case 0x09:
		if ctx.reg_v[x] != ctx.reg_v[y] do ctx.pc += 2
	case 0x0A:
		ctx.i_reg = nnn
	case 0x0B:
		ctx.pc = nnn + u16(ctx.reg_v[0])
	case 0x0C:
		ctx.reg_v[x] = u8(rl.GetRandomValue(0, 255)) & kk
	case 0x0D:
		// todo rewrite myself
		vx := ctx.reg_v[x]
		vy := ctx.reg_v[y]

		ctx.reg_v[0xF] = 0

		for y := 0; y < int(n); y += 1 {
			b := ctx.mem[int(ctx.i_reg) + y]
			yy := (int(vy) + y) % DISPLAY_HEIGHT

			for x := 0; x < 8; x += 1 {
				bit := u8(b & 0b1000_0000 > 0 ? 1 : 0)
				b <<= 1

				xx := (int(vx) + x) % DISPLAY_WIDTH
				screen_bit := ctx.framebuffer[xx + yy * DISPLAY_WIDTH]

				if screen_bit == true && bit == 1 do ctx.reg_v[0xf] = 1

				ctx.framebuffer[xx + yy * DISPLAY_WIDTH] = u8(screen_bit) ~ bit > 0
			}
		}
	case 0x0E:
		if kk == 0x9E {
			if ctx.keypad[ctx.reg_v[x]] == true do ctx.pc += 2
		} else if kk == 0xA1 {
			if ctx.keypad[ctx.reg_v[x]] == false do ctx.pc += 2
		} else do panic("Unimplemented instruction")
	case 0x0F:
		switch kk {
		case 0x07:
			ctx.reg_v[x] = ctx.delay_timer
		case 0x0A:
			@(static) any_key_pressed := false
			@(static) key: u8 = 0xFF

			for i := 0; key == 0xFF && i < len(ctx.keypad); i += 1 {
				if ctx.keypad[i] {
					key = u8(i)
					any_key_pressed = true
					break
				}
			}

			if !any_key_pressed do ctx.pc -= 2
			else {
				if (ctx.keypad[key]) do ctx.pc -= 2
				else {
					ctx.reg_v[x] = key
					key = 0xFF
					any_key_pressed = false
				}
			}
		case 0x15:
			ctx.delay_timer = ctx.reg_v[x]
		case 0x18:
			ctx.sound_timer = ctx.reg_v[x]
		case 0x1E:
			ctx.i_reg += u16(ctx.reg_v[x])
		case 0x29:
			ctx.i_reg = u16(ctx.reg_v[x]) * 5
		case 0x33:
			val := ctx.reg_v[x]
			ctx.mem[ctx.i_reg + 2] = val % 10
			val /= 10
			ctx.mem[ctx.i_reg + 1] = val % 10
			val /= 10
			ctx.mem[ctx.i_reg] = val % 10
			val /= 10
		case 0x55:
			for index in 0 ..= x {
				ctx.mem[ctx.i_reg + u16(index)] = ctx.reg_v[index]
			}
		case 0x65:
			for index in 0 ..= x {
				ctx.reg_v[index] = ctx.mem[ctx.i_reg + u16(index)]
			}
		}
	}
}

handle_keys :: proc(ctx: ^Chip_Context) {
	if rl.IsKeyPressed(.ONE) do ctx.keypad[0x1] = true
	if rl.IsKeyPressed(.TWO) do ctx.keypad[0x2] = true
	if rl.IsKeyPressed(.THREE) do ctx.keypad[0x3] = true
	if rl.IsKeyPressed(.FOUR) do ctx.keypad[0xC] = true
	if rl.IsKeyPressed(.Q) do ctx.keypad[0x4] = true
	if rl.IsKeyPressed(.W) do ctx.keypad[0x5] = true
	if rl.IsKeyPressed(.E) do ctx.keypad[0x6] = true
	if rl.IsKeyPressed(.R) do ctx.keypad[0xD] = true
	if rl.IsKeyPressed(.A) do ctx.keypad[0x7] = true
	if rl.IsKeyPressed(.S) do ctx.keypad[0x8] = true
	if rl.IsKeyPressed(.D) do ctx.keypad[0x9] = true
	if rl.IsKeyPressed(.F) do ctx.keypad[0xE] = true
	if rl.IsKeyPressed(.Z) do ctx.keypad[0xA] = true
	if rl.IsKeyPressed(.X) do ctx.keypad[0x0] = true
	if rl.IsKeyPressed(.C) do ctx.keypad[0xB] = true
	if rl.IsKeyPressed(.V) do ctx.keypad[0xF] = true

	if rl.IsKeyReleased(.ONE) do ctx.keypad[0x1] = false
	if rl.IsKeyReleased(.TWO) do ctx.keypad[0x2] = false
	if rl.IsKeyReleased(.THREE) do ctx.keypad[0x3] = false
	if rl.IsKeyReleased(.FOUR) do ctx.keypad[0xC] = false
	if rl.IsKeyReleased(.Q) do ctx.keypad[0x4] = false
	if rl.IsKeyReleased(.W) do ctx.keypad[0x5] = false
	if rl.IsKeyReleased(.E) do ctx.keypad[0x6] = false
	if rl.IsKeyReleased(.R) do ctx.keypad[0xD] = false
	if rl.IsKeyReleased(.A) do ctx.keypad[0x7] = false
	if rl.IsKeyReleased(.S) do ctx.keypad[0x8] = false
	if rl.IsKeyReleased(.D) do ctx.keypad[0x9] = false
	if rl.IsKeyReleased(.F) do ctx.keypad[0xE] = false
	if rl.IsKeyReleased(.Z) do ctx.keypad[0xA] = false
	if rl.IsKeyReleased(.X) do ctx.keypad[0x0] = false
	if rl.IsKeyReleased(.C) do ctx.keypad[0xB] = false
	if rl.IsKeyReleased(.V) do ctx.keypad[0xF] = false
}

audio_callback :: proc "c" (buffer_data: rawptr, frames: u32) {
	samples: []f32 = (cast([^]f32)buffer_data)[:frames]

	for i in 0 ..< frames {
		samples[i] = AMPLITUDE * math.sin_f32(FREQUENCY * 2.0 * (f32(i) / f32(32)) * math.PI)
	}
}
