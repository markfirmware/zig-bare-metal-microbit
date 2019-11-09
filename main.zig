export fn main() noreturn {
    setBssToZero();

    const all_rows_mask = 0xe000;
    const all_cols_mask = 0x1ff0;
    const all_pins_mask = all_rows_mask | all_cols_mask;
    gpio.direction_set = all_pins_mask;

    var selected_row: u32 = undefined;
    var selected_col: u32 = undefined;

    selected_row = 2;
    selected_col = 3;

    const selected_row_mask = @as(u32, 1) << @truncate(u5, selected_row + 13 - 1);
    const selected_col_mask = @as(u32, 1) << @truncate(u5, selected_col + 4 - 1);
    const pins_state = selected_row_mask | selected_col_mask ^ all_cols_mask;
    gpio.out_set = pins_state;
    gpio.out_clear = pins_state ^ all_pins_mask;

    while (true) {
    }
}

const GpioRegisters = struct {
    out: u32,
    out_set: u32,
    out_clear: u32,
    in: u32,
    direction: u32,
    direction_set: u32,
    direction_clear: u32,
};

fn exceptionHandler(entry_number: u32) noreturn {
    hang("now idle in arm exception handler");
}

pub fn panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
    panicf("main.zig pub fn panic(): {}", message);
}

var already_panicking: bool = false;
fn panicf(comptime fmt: []const u8, args: ...) noreturn {
    @setCold(true);
    if (already_panicking) {
        hang("\npanicked during kernel panic");
    }
    already_panicking = true;

//  log("\npanic: " ++ fmt, args);
    hang("panic completed");
}

fn hang(comptime format: []const u8, args: ...) noreturn {
//  log(format, args);
    while (true) {
//      wfe();
    }
}

// The linker will make the address of these global variables equal
// to the value we are interested in. The memory at the address
// could alias any uninitialized global variable in the kernel.
extern var __bss_start: u8;
extern var __bss_end: u8;

fn setBssToZero() void {
    @memset(@ptrCast(*volatile [1]u8, &__bss_start), 0, @ptrToInt(&__bss_end) - @ptrToInt(&__bss_start));
}

fn io(comptime StructType: type, address: u32) *volatile StructType {
    return @intToPtr(*volatile StructType, address);
}

comptime {
    asm(
        \\.section .text.boot // .text.boot to keep this in the first portion of the binary
        \\.globl _start
        \\_start:
        \\ .long 0x20004000 // sp top of 16KB ram
        \\ .long main
        \\ .long exceptionNumber01
        \\ .long exceptionNumber02
        \\ .long exceptionNumber03
        \\ .long exceptionNumber04
        \\ .long exceptionNumber05
        \\ .long exceptionNumber06
        \\ .long exceptionNumber07
        \\ .long exceptionNumber08
        \\ .long exceptionNumber09
        \\ .long exceptionNumber10
        \\ .long exceptionNumber11
        \\ .long exceptionNumber12
        \\ .long exceptionNumber13
        \\ .long exceptionNumber14
        \\ .long exceptionNumber15
    );
}

export fn exceptionNumber01() noreturn {
    exceptionHandler(01);
}

export fn exceptionNumber02() noreturn {
    exceptionHandler(02);
}

export fn exceptionNumber03() noreturn {
    exceptionHandler(03);
}

export fn exceptionNumber04() noreturn {
    exceptionHandler(04);
}

export fn exceptionNumber05() noreturn {
    exceptionHandler(05);
}

export fn exceptionNumber06() noreturn {
    exceptionHandler(06);
}

export fn exceptionNumber07() noreturn {
    exceptionHandler(07);
}

export fn exceptionNumber08() noreturn {
    exceptionHandler(08);
}

export fn exceptionNumber09() noreturn {
    exceptionHandler(09);
}

export fn exceptionNumber10() noreturn {
    exceptionHandler(10);
}

export fn exceptionNumber11() noreturn {
    exceptionHandler(11);
}

export fn exceptionNumber12() noreturn {
    exceptionHandler(12);
}

export fn exceptionNumber13() noreturn {
    exceptionHandler(13);
}

export fn exceptionNumber14() noreturn {
    exceptionHandler(14);
}

export fn exceptionNumber15() noreturn {
    exceptionHandler(15);
}

const builtin = @import("builtin");
const button_a_pin = 17;
const button_b_pin = 26;
const gpio = io(GpioRegisters, 0x50000504);
const name = "zig-bare-metal-microbit";
const release_tag = "0.1";
const std = @import("std");
