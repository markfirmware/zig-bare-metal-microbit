#!/bin/bash
set -e

export PATH=~/zig:$PATH

MISSION_NUMBER=${1:-00}
SOURCE=$(ls mission${MISSION_NUMBER}_*.zig)
EXE=${SOURCE%.*}
ARCH=armv6m

echo $SOURCE
echo zig version $(zig version)
zig fmt $SOURCE
zig build-exe -target $ARCH-freestanding-eabihf --linker-script linker.ld $SOURCE
llvm-objdump -x --source $EXE > $EXE.asm.$ARCH
set +e
grep unknown $EXE.asm.$ARCH | grep -v '00 00 00 00'
grep 'q[0-9].*#' $EXE.asm.$ARCH | egrep -v '#(-|)(16|32|48|64|80|96|112|128)'
set -e
ls -lt $EXE
objcopy $EXE -O binary $EXE.bin
ls -lt $EXE.bin
objcopy $EXE -O ihex $EXE.hex
ls -lt $EXE.hex

cp $EXE.hex main.hex
cp main.hex ~/microbit1/
cp main.hex ~/microbit2/
sync
