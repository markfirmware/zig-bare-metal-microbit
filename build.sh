#!/bin/bash

zig build-exe -target armv6m-freestanding-eabihf --linker-script linker.ld main.zig
llvm-objcopy main -O binary main.bin
srec_cat main.bin -Binary -Output main.hex -Intel
