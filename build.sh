rm -rf build
mkdir build

odin build src -out:build/emulator -debug
# ./build/emulator 2> mem_leaks.txt
./build/emulator