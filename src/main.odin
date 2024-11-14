package emulator

import "core:fmt"
import "core:math/rand"
import "core:mem"
import rl "vendor:raylib"

RAM_SIZE :: 4096
RAM_START_ADDR :: 512

COL_COUNT :: 64
ROW_COUNT :: 32
PIXEL_SIZE :: 20

Chip_Context :: struct {
	ram:             [RAM_SIZE]u8,
	program_counter: u16,
	registers:       [16]u8,
	i_register:      u16,
	stack:           [16]u16,
	jmp_count:       u8,
	game_counter:    u8,
	sound_counter:   u8,
	framebuffer:     [COL_COUNT * ROW_COUNT]bool,
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

	ctx: Chip_Context
	ctx.program_counter = RAM_START_ADDR

	// for x: i32; x < COL_COUNT; x += 1 {
	// 	for y: i32; y < ROW_COUNT; y += 1 {
	// 		ctx.framebuffer[y * COL_COUNT + x] = true
	// 	}
	// }

	rl.SetConfigFlags({.WINDOW_ALWAYS_RUN, .VSYNC_HINT, .MSAA_4X_HINT})
	rl.SetTargetFPS(60)

	rl.InitWindow(COL_COUNT * PIXEL_SIZE, ROW_COUNT * PIXEL_SIZE, "Chip-8 emulator in Odin")
	defer rl.CloseWindow()

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		defer rl.EndDrawing()

		for x: i32; x < COL_COUNT; x += 1 {
			for y: i32; y < ROW_COUNT; y += 1 {
				if ctx.framebuffer[y * COL_COUNT + x] == true {
					pixel := rl.Rectangle {
						f32(x) * PIXEL_SIZE,
						f32(y) * PIXEL_SIZE,
						PIXEL_SIZE,
						PIXEL_SIZE,
					}
					rl.DrawRectangleRec(pixel, rl.GREEN)
				}
			}
		}}
}
