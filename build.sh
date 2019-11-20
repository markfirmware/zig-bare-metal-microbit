#!/bin/bash
set -e

zig build-exe -target armv6m-freestanding-eabihf --linker-script linker.ld main.zig
ls -lt main
llvm-objcopy-6.0 main -O binary main.bin
ls -lt main.bin
srec_cat main.bin -Binary -Output main.hex -Intel
ls -lt main.hex
