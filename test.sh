#!/bin/bash
set -e

export PATH=~/zig:$PATH

MISSION_NUMBER=${1:-0}
SOURCE=$(ls mission${MISSION_NUMBER}_*.zig)
ARCH=thumbv6m

echo $SOURCE
echo zig version $(zig version)
zig fmt *.zig
touch symbols.txt
zig build -Dmain=$SOURCE

llvm-objdump -x --source zig-cache/bin/main > main.asm
grep '^00000000.*:$' main.asm | sed 's/^00000000000//' | sed 's/:$//' | grep -v ' [_$]' > symbols.txt
ls -lt symbols.txt
#zig build -Dmain=$SOURCE
ls -l zig-cache/bin/main.img main.hex

#set +e
#grep unknown main.asm | grep -v '00 00 00 00'
#grep 'q[0-9].*#' main.asm | egrep -v '#(-|)(16|32|48|64|80|96|112|128)'
#set -e

cp main.hex ~/microbit1/ # && cp main.hex ~/microbit2/
sync
