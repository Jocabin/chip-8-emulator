rm -rf build
mkdir build

odin run src -out:build/emulator -debug -- $1