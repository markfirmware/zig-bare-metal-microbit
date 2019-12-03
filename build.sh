#!/bin/bash
set -e

zig build-exe -target armv6m-freestanding-eabihf --linker-script linker.ld main.zig
ls -lt main
llvm-objcopy-6.0 main -O binary main.bin
ls -lt main.bin
objcopy main -O ihex main.hex
ls -lt main.hex
