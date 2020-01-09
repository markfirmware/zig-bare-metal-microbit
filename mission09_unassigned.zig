export fn mission09_main() noreturn {
    Bss.prepare();
    Exceptions.prepare();
    Timer0.prepare();
    Timer1.prepare();
    Timer2.prepare();
    ClockManagement.prepareHf();
    Uart.prepare();

    cycle_activity.prepare();
    led_matrix_activity.prepare();
    terminal_activity.prepare();

    while (true) {
        cycle_activity.update();
        led_matrix_activity.update();
        terminal_activity.update();
    }
}

const CycleActivity = struct {
    cycle_counter: u32,
    cycle_time: u32,
    last_cycle_start: ?u32,
    max_cycle_time: u32,
    up_time_seconds: u32,
    up_timer: TimeKeeper,

    fn prepare(self: *CycleActivity) void {
        self.cycle_counter = 0;
        self.cycle_time = 0;
        self.last_cycle_start = null;
        self.max_cycle_time = 0;
        self.up_time_seconds = 0;
        self.up_timer.prepare(1000 * 1000);
    }

    fn update(self: *CycleActivity) void {
        self.cycle_counter += 1;
        const new_cycle_start = Timer0.capture();
        if (self.last_cycle_start) |start| {
            self.cycle_time = new_cycle_start -% start;
            self.max_cycle_time = std.math.max(self.cycle_time, self.max_cycle_time);
        }
        self.last_cycle_start = new_cycle_start;
        if (self.up_timer.isFinished()) {
            self.up_timer.reset();
            self.up_time_seconds += 1;
        }
    }
};

const TerminalActivity = struct {
    keyboard_column: u32,
    prev_now: u32,

    fn prepare(self: *TerminalActivity) void {
        self.keyboard_column = 1;
        self.prev_now = cycle_activity.up_time_seconds;
        self.redraw();
    }

    fn redraw(self: *TerminalActivity) void {
        Terminal.clearScreen();
        Terminal.setScrollingRegion(5, 99);
        Terminal.move(5 - 1, 1);
        log("keyboard input will be echoed below:", .{});
    }

    fn update(self: *TerminalActivity) void {
        if (Uart.isReadByteReady()) {
            const byte = Uart.readByte();
            switch (byte) {
                27 => {
                    Uart.writeByteBlocking('$');
                    self.keyboard_column += 1;
                },
                12 => {
                    self.redraw();
                },
                '\r' => {
                    Uart.writeText("\n");
                    self.keyboard_column = 1;
                },
                else => {
                    Uart.writeByteBlocking(byte);
                    self.keyboard_column += 1;
                },
            }
        }
        Uart.update();
        const now = cycle_activity.up_time_seconds;
        if (now >= self.prev_now + 1) {
            Terminal.hideCursor();
            Terminal.move(1, 1);
            Terminal.line("up {:3}s cycle {}us max {}us", .{ cycle_activity.up_time_seconds, cycle_activity.cycle_time, cycle_activity.max_cycle_time });
            Terminal.showCursor();
            Terminal.move(99, self.keyboard_column);
            self.prev_now = now;
        }
    }
};

comptime {
    asm (
        \\.section .text.start.mission09
        \\.globl mission09_vector_table
        \\.balign 0x80
        \\mission09_vector_table:
        \\ .long 0x20004000 // sp top of 16KB ram
        \\ .long mission09_main
        \\ .long mission09_exceptionNumber02
        \\ .long mission09_exceptionNumber03
        \\ .long mission09_exceptionNumber04
        \\ .long mission09_exceptionNumber05
        \\ .long mission09_exceptionNumber06
        \\ .long mission09_exceptionNumber07
        \\ .long mission09_exceptionNumber08
        \\ .long mission09_exceptionNumber09
        \\ .long mission09_exceptionNumber10
        \\ .long mission09_exceptionNumber11
        \\ .long mission09_exceptionNumber12
        \\ .long mission09_exceptionNumber13
        \\ .long mission09_exceptionNumber14
        \\ .long mission09_exceptionNumber15
    );
}

export fn mission09_exceptionNumber01() noreturn {
    lib.exceptionHandler(01);
}

export fn mission09_exceptionNumber02() noreturn {
    lib.exceptionHandler(02);
}

export fn mission09_exceptionNumber03() noreturn {
    lib.exceptionHandler(03);
}

export fn mission09_exceptionNumber04() noreturn {
    lib.exceptionHandler(04);
}

export fn mission09_exceptionNumber05() noreturn {
    lib.exceptionHandler(05);
}

export fn mission09_exceptionNumber06() noreturn {
    lib.exceptionHandler(06);
}

export fn mission09_exceptionNumber07() noreturn {
    lib.exceptionHandler(07);
}

export fn mission09_exceptionNumber08() noreturn {
    lib.exceptionHandler(08);
}

export fn mission09_exceptionNumber09() noreturn {
    lib.exceptionHandler(09);
}

export fn mission09_exceptionNumber10() noreturn {
    lib.exceptionHandler(10);
}

export fn mission09_exceptionNumber11() noreturn {
    lib.exceptionHandler(11);
}

export fn mission09_exceptionNumber12() noreturn {
    lib.exceptionHandler(12);
}

export fn mission09_exceptionNumber13() noreturn {
    lib.exceptionHandler(13);
}

export fn mission09_exceptionNumber14() noreturn {
    lib.exceptionHandler(14);
}

export fn mission09_exceptionNumber15() noreturn {
    lib.exceptionHandler(15);
}

pub fn panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
    lib.panicf("panic(): {}", .{message});
}

const Bss = lib.Bss;
const builtin = @import("builtin");
const ClockManagement = lib.ClockManagement;
const Exceptions = lib.Exceptions;
const LedMatrixActivity = lib.LedMatrixActivity;
const lib = @import("lib00_basics.zig");
const log = Uart.log;
const std = @import("std");
const Terminal = lib.Terminal;
const TimeKeeper = lib.TimeKeeper;
const Timer0 = lib.Timer0;
const Timer1 = lib.Timer1;
const Timer2 = lib.Timer2;
const Uart = lib.Uart;

var cycle_activity: CycleActivity = undefined;
var led_matrix_activity: LedMatrixActivity = undefined;
var terminal_activity: TerminalActivity = undefined;
