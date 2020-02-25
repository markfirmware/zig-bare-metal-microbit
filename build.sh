#!/bin/bash
set -e

ARCH=thumbv6m
SOURCE=$(ls mission0*.zig)

echo zig version $(zig version)
zig fmt *.zig
touch symbols.txt
zig build
llvm-objdump-6.0 --source zig-cache/bin/main > main.asm
grep '^00000000.*:$' main.asm | sed 's/^00000000//' > symbols.txt
zig build

#llvm-objdump -x --source main > asm.$ARCH
#set +e
#grep unknown asm.$ARCH | grep -v '00 00 00 00'
#grep 'q[0-9].*#' asm.$ARCH | egrep -v '#(-|)(16|32|48|64|80|96|112|128)'
#set -e

ls -l main.hex zig-cache/bin/main.img symbols.txt
