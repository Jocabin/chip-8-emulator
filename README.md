# CHIP-8 emulator in Odin

This is my version of the famous [CHIP-8 emulator](https://fr.wikipedia.org/wiki/CHIP-8), written in Odin.

## Build the project

Just run the `./build.sh` script, or build/run the project directly with the Odin compiler.

Dont forget to pass as argument the rom file path.

## Important note

- This emulator pass all tests from [Timendus's CHIP-8 test suite](https://github.com/Timendus/chip8-test-suite).
- This emulator only support CHIP-8 instructions, not Super CHIP-8. I just don't want to implement them.
- I wrote all the code by myself, but since I'm not a genius, there is some instructions (Dxyn 👀) I struggled to implement only by myself. See credits to check all the code I read during my journey.

## Credits

- [Timendus's CHIP-8 test suite](https://github.com/Timendus/chip8-test-suite)
- [Queso Fuego's CHIP-8 Emulator in C](https://github.com/queso-fuego/chip8_emulator_c)
- [Pixel Rift's CHIP-8 Emulator in C](https://github.com/PixelRifts/chip8-sim)