#!/bin/bash
set -e

ARCH=thumbv6m
SOURCE=$(ls mission00*.zig)

echo zig version $(zig version)
touch sumbols.txt
zig fmt *.zig
zig build

#llvm-objdump -x --source main > asm.$ARCH
#set +e
#grep unknown asm.$ARCH | grep -v '00 00 00 00'
#grep 'q[0-9].*#' asm.$ARCH | egrep -v '#(-|)(16|32|48|64|80|96|112|128)'
#set -e

ls -lt main.hex zig-cache/bin/main.img
