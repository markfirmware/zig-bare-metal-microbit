#!/bin/bash
set -e

ARCH=armv6m
SOURCE=$(ls mission00*.zig)

echo zig version $(zig version)
zig fmt *.zig
zig build-exe -target $ARCH-freestanding-eabihf --linker-script linker.ld --name main $SOURCE
llvm-objdump -x --source main > asm.$ARCH
#set +e
#grep unknown asm.$ARCH | grep -v '00 00 00 00'
#grep 'q[0-9].*#' asm.$ARCH | egrep -v '#(-|)(16|32|48|64|80|96|112|128)'
#set -e
ls -lt main
llvm-objcopy-6.0 main -O binary main.bin
ls -lt main.bin
objcopy main -O ihex main.hex
ls -lt main.hex
