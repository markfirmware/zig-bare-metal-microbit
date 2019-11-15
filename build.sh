#!/bin/bash
set -e

zig build-exe -target armv6m-freestanding-eabihf --linker-script linker.ld main.zig
llvm-objcopy main -O ihex main.bin
