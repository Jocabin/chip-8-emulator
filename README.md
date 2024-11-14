# Odin project template

## How to build and run

Rename all the occurences of `emulator` in the template by your app name.

`./build.sh` will build with debug informations, and then run the program.

## Informations

At the begining of the `src/main.odin` file, you will notice a block of code. This is for tracking bad frees and unfree allocations. All errors printed to `stderr` will finish in the `mem_leaks.txt` file.

With that, you can retrieve all memories allocations in this file.

This template contain all necessary files for LSP, formating and debuging to use with Visual Studio Code, in case you need it.

Don't forget to add `mem_leaks.txt` in your `.gitignore`!
