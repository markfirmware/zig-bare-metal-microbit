export fn mission00_main() noreturn {
    ram_u32[ram_u32.len - 1] = @ptrToInt(mission00_panic);

    Bss.prepare();
    Exceptions.prepare();
    missionMenu();
    Uart.prepare();
    Timer0.prepare();
    Timer1.prepare();
    Timer2.prepare();
    LedMatrix.prepare();

    cycle_activity.prepare();
    keyboard_activity.prepare();
    status_activity.prepare();

    missions[0] = .{ .name = "mission selector", .panic = mission00_panic, .vector_table = &mission00_vector_table };
    missions[1] = .{ .name = "turn on all leds", .panic = @import("mission01_turn_on_all_leds_without_using_any_libraries.zig").panic, .vector_table = &mission01_vector_table };
    missions[2] = .{ .name = "model railroad wip", .panic = @import("mission02_model_railroad_wip.zig").panic, .vector_table = &mission02_vector_table };
    missions[3] = .{ .name = "model railroad button controlled pwm", .panic = @import("mission03_model_railroad_button_controlled_pwm.zig").panic, .vector_table = &mission03_vector_table };
    missions[4] = .{ .name = "unassigned", .panic = @import("mission04_unassigned.zig").panic, .vector_table = &mission04_vector_table };
    missions[5] = .{ .name = "unassigned", .panic = @import("mission05_unassigned.zig").panic, .vector_table = &mission05_vector_table };
    missions[6] = .{ .name = "unassigned", .panic = @import("mission06_unassigned.zig").panic, .vector_table = &mission06_vector_table };
    missions[7] = .{ .name = "unassigned", .panic = @import("mission07_unassigned.zig").panic, .vector_table = &mission07_vector_table };
    missions[8] = .{ .name = "unassigned", .panic = @import("mission08_unassigned.zig").panic, .vector_table = &mission08_vector_table };
    missions[9] = .{ .name = "unassigned", .panic = @import("mission09_unassigned.zig").panic, .vector_table = &mission09_vector_table };
    log("available missions:", .{});
    for (missions) |*m, i| {
        log("{}. {}", .{ i, m.name });
    }

    while (true) {
        cycle_activity.update();
        keyboard_activity.update();
        status_activity.update();
    }
}

const CycleActivity = struct {
    cycle_counter: u32,
    cycle_time: u32,
    last_cycle_start: ?u32,
    last_second_ticks: u32,
    max_cycle_time: u32,
    up_time_seconds: u32,

    fn prepare(self: *CycleActivity) void {
        self.cycle_counter = 0;
        self.cycle_time = 0;
        self.last_cycle_start = null;
        self.last_second_ticks = 0;
        self.max_cycle_time = 0;
        self.up_time_seconds = 0;
    }

    fn update(self: *CycleActivity) void {
        LedMatrix.update();
        self.cycle_counter += 1;
        const new_cycle_start = Timer0.capture();
        if (new_cycle_start -% self.last_second_ticks >= 1000 * 1000) {
            self.up_time_seconds += 1;
            self.last_second_ticks = new_cycle_start;
        }
        if (self.last_cycle_start) |start| {
            self.cycle_time = new_cycle_start -% start;
            self.max_cycle_time = math.max(self.cycle_time, self.max_cycle_time);
        }
        self.last_cycle_start = new_cycle_start;
    }
};

const KeyboardActivity = struct {
    column: u32,

    fn prepare(self: *KeyboardActivity) void {
        self.column = 1;
    }

    fn update(self: *KeyboardActivity) void {
        if (!Uart.isReadByteReady()) {
            return;
        }
        const byte = Uart.readByte();
        switch (byte) {
            27 => {
                Uart.writeByteBlocking('$');
                self.column += 1;
            },
            12 => {
                status_activity.redraw();
            },
            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                missions[byte - '0'].activate();
            },
            '\r' => {
                Uart.writeText("\n");
                self.column = 1;
            },
            else => {
                Uart.writeByteBlocking(byte);
                self.column += 1;
            },
        }
    }
};

const StatusActivity = struct {
    prev_now: u32,

    fn prepare(self: *StatusActivity) void {
        self.prev_now = cycle_activity.up_time_seconds;
        self.redraw();
    }

    fn redraw(self: *StatusActivity) void {
        Terminal.clearScreen();
        Terminal.setScrollingRegion(5, 99);
        Terminal.move(5 - 1, 1);
        log("keyboard input will be echoed below:", .{});
    }

    fn update(self: *StatusActivity) void {
        Uart.loadTxd();
        const now = cycle_activity.up_time_seconds;
        if (now >= self.prev_now + 1) {
            Terminal.hideCursor();
            Terminal.move(1, 1);
            Terminal.line("up {:3}s cycle {}us max {}us", .{ cycle_activity.up_time_seconds, cycle_activity.cycle_time, cycle_activity.max_cycle_time });
            Terminal.line("gpio.in {x:8}", .{Gpio.registers.in & ~@as(u32, 0x0300fff0)});
            Terminal.line("", .{});
            Terminal.showCursor();
            restoreInputLine();
            self.prev_now = now;
        }
    }
};

fn restoreInputLine() void {
    Terminal.move(99, keyboard_activity.column);
}

fn exceptionHandler(exception_number: u32) noreturn {
    panicf("exception number {} ... now idle in arm exception handler", .{exception_number});
}

export fn mission00_exceptionNumber01() noreturn {
    exceptionHandler(01);
}

export fn mission00_exceptionNumber02() noreturn {
    exceptionHandler(02);
}

export fn mission00_exceptionNumber03() noreturn {
    exceptionHandler(03);
}

export fn mission00_exceptionNumber04() noreturn {
    exceptionHandler(04);
}

export fn mission00_exceptionNumber05() noreturn {
    exceptionHandler(05);
}

export fn mission00_exceptionNumber06() noreturn {
    exceptionHandler(06);
}

export fn mission00_exceptionNumber07() noreturn {
    exceptionHandler(07);
}

export fn mission00_exceptionNumber08() noreturn {
    exceptionHandler(08);
}

export fn mission00_exceptionNumber09() noreturn {
    exceptionHandler(09);
}

export fn mission00_exceptionNumber10() noreturn {
    exceptionHandler(10);
}

export fn mission00_exceptionNumber11() noreturn {
    exceptionHandler(11);
}

export fn mission00_exceptionNumber12() noreturn {
    exceptionHandler(12);
}

export fn mission00_exceptionNumber13() noreturn {
    exceptionHandler(13);
}

export fn mission00_exceptionNumber14() noreturn {
    exceptionHandler(14);
}

export fn mission00_exceptionNumber15() noreturn {
    exceptionHandler(15);
}

fn missionMenu() void {
    Gpio.config[@ctz(u32, Gpio.registers_masks.button_a_active_low)] = Gpio.config_masks.input;
    Gpio.config[@ctz(u32, Gpio.registers_masks.button_b_active_low)] = Gpio.config_masks.input;
    while (Gpio.registers.in & Gpio.registers_masks.button_b_active_low == 0) {}
}

pub fn mission00_panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
    panicf("mission00_panic(): {}", .{message});
}

pub fn panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
    const active_mission_panic = @intToPtr(fn ([]const u8, ?*builtin.StackTrace) noreturn, ram_u32[ram_u32.len - 1]);
    active_mission_panic(message, trace);
}

const Mission = struct {
    name: []const u8,
    panic: fn ([]const u8, ?*builtin.StackTrace) noreturn,
    vector_table: *allowzero u32,

    fn activate(self: *Mission) void {
        const reset_vector_table = self.vector_table;
        const reset_sp = @intToPtr(*allowzero u32, @ptrToInt(self.vector_table) + 0).*;
        const reset_pc = @intToPtr(*allowzero u32, @ptrToInt(self.vector_table) + 4).*;
        const vector_table_offset_register: u32 = 0xE000ED08;
        const ram: [*]u32 = @intToPtr([*]u32, 0x20000000);
        ram[0x1000 - 1] = @ptrToInt(self.panic);
        asm volatile (
            \\ mov r4,%[reset_vector_table]
            \\ mov r5,%[vector_table_offset_register]
            \\ str r4,[r5]
            \\ mov sp,%[reset_sp]
            \\ bx %[reset_pc]
            :
            : [vector_table_offset_register] "{r0}" (vector_table_offset_register),
              [reset_vector_table] "{r1}" (reset_vector_table),
              [reset_pc] "{r2}" (reset_pc),
              [reset_sp] "{r3}" (reset_sp)
        );
    }
};

comptime {
    asm (
        \\.section .text.start.mission00
        \\.globl mission00_vector_table
        \\mission00_vector_table:
        \\.balign 0x80
        \\ .long 0x20004000 - 4 // sp top of 16KB ram, one word reserved
        \\ .long mission00_main
        \\ .long mission00_exceptionNumber02
        \\ .long mission00_exceptionNumber03
        \\ .long mission00_exceptionNumber04
        \\ .long mission00_exceptionNumber05
        \\ .long mission00_exceptionNumber06
        \\ .long mission00_exceptionNumber07
        \\ .long mission00_exceptionNumber08
        \\ .long mission00_exceptionNumber09
        \\ .long mission00_exceptionNumber10
        \\ .long mission00_exceptionNumber11
        \\ .long mission00_exceptionNumber12
        \\ .long mission00_exceptionNumber13
        \\ .long mission00_exceptionNumber14
        \\ .long mission00_exceptionNumber15
    );
}

const Bss = lib.Bss;
const builtin = @import("builtin");
const Exceptions = lib.Exceptions;
const Gpio = lib.Gpio;
const LedMatrix = lib.LedMatrix;
const lib = @import("lib00_basics.zig");
const literal = Uart.literal;
const log = Uart.log;
const math = std.math;
const name = "zig-bare-metal-microbit";
const panicf = lib.panicf;
const ram_u32 = lib.ram_u32;
const release_tag = "0.4";
const std = @import("std");
const Terminal = lib.Terminal;
const Timer0 = lib.Timer0;
const Timer1 = lib.Timer1;
const Timer2 = lib.Timer2;
const Uart = lib.Uart;

extern var mission00_vector_table: u32;
extern var mission01_vector_table: u32;
extern var mission02_vector_table: u32;
extern var mission03_vector_table: u32;
extern var mission04_vector_table: u32;
extern var mission05_vector_table: u32;
extern var mission06_vector_table: u32;
extern var mission07_vector_table: u32;
extern var mission08_vector_table: u32;
extern var mission09_vector_table: u32;
extern var __bss_start: u8;
extern var __bss_end: u8;

var cycle_activity: CycleActivity = undefined;
var keyboard_activity: KeyboardActivity = undefined;
var missions: [10]Mission = undefined;
var status_activity: StatusActivity = undefined;
