export fn mission08_main() noreturn {
    Bss.prepare();
    Exceptions.prepare();
    Timer0.prepare();
    Timer1.prepare();
    Timer2.prepare();
    ClockManagement.prepareHf();
    Uart.prepare();

    cycle_activity.prepare();
    keyboard_activity.prepare();
    led_matrix_activity.prepare();
    status_activity.prepare();

    while (true) {
        cycle_activity.update();
        keyboard_activity.update();
        led_matrix_activity.update();
        status_activity.update();
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
            12, '-' => {
                status_activity.redraw();
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

const LedMatrixActivity = struct {
    scan_lines: [3]u32,
    scan_lines_index: u32,
    scan_timer: TimeKeeper,

    fn drawZigIcon(self: *LedMatrixActivity) void {
        self.setPixel(0, 0, 1);
        self.setPixel(1, 0, 1);
        self.setPixel(2, 0, 1);
        self.setPixel(3, 0, 1);
        self.setPixel(4, 0, 1);
        self.setPixel(3, 1, 1);
        self.setPixel(2, 2, 1);
        self.setPixel(1, 3, 1);
        self.setPixel(0, 4, 1);
        self.setPixel(1, 4, 1);
        self.setPixel(2, 4, 1);
        self.setPixel(3, 4, 1);
        self.setPixel(4, 4, 1);
    }

    fn prepare(self: *LedMatrixActivity) void {
        Gpio.registers.direction_set = LedMatrixActivity.all_led_pins_mask;
        for (self.scan_lines) |_, i| {
            self.scan_lines[i] = LedMatrixActivity.row_1 << @truncate(u5, i) | LedMatrixActivity.all_led_cols_mask;
        }
        self.scan_lines_index = 0;
        led_matrix_activity.drawZigIcon();
        self.scan_timer.prepare(5 * 1000);
    }

    fn setPixel(self: *LedMatrixActivity, x: u32, y: u32, v: u32) void {
        const n = 5 * y + x;
        const full_mask = led_pins_masks[n];
        const col_mask = full_mask & LedMatrixActivity.all_led_cols_mask;
        const row_mask = full_mask & LedMatrixActivity.all_led_rows_mask;
        const selected_scan_line_index = if (row_mask == LedMatrixActivity.row_1) @as(u32, 0) else if (row_mask == LedMatrixActivity.row_2) @as(u32, 1) else 2;
        self.scan_lines[selected_scan_line_index] = self.scan_lines[selected_scan_line_index] & ~col_mask | if (v == 0) col_mask else 0;
    }

    fn update(self: *LedMatrixActivity) void {
        if (self.scan_timer.isFinished()) {
            self.scan_timer.reset();
            Gpio.registers.out = Gpio.registers.out & ~LedMatrixActivity.all_led_pins_mask | self.scan_lines[self.scan_lines_index];
            self.scan_lines_index = (self.scan_lines_index + 1) % self.scan_lines.len;
        }
    }

    const all_led_rows_mask: u32 = 0xe000;
    const all_led_cols_mask: u32 = 0x1ff0;
    const all_led_pins_mask = LedMatrixActivity.all_led_rows_mask | LedMatrixActivity.all_led_cols_mask;
    const col_1 = 0x0010;
    const col_2 = 0x0020;
    const col_3 = 0x0040;
    const col_4 = 0x0080;
    const col_5 = 0x0100;
    const col_6 = 0x0200;
    const col_7 = 0x0400;
    const col_8 = 0x0800;
    const col_9 = 0x1000;
    const led_pins_masks = [_]u32{
        LedMatrixActivity.row_1 | LedMatrixActivity.col_1,
        LedMatrixActivity.row_2 | LedMatrixActivity.col_4,
        LedMatrixActivity.row_1 | LedMatrixActivity.col_2,
        LedMatrixActivity.row_2 | LedMatrixActivity.col_5,
        LedMatrixActivity.row_1 | LedMatrixActivity.col_3,

        LedMatrixActivity.row_3 | LedMatrixActivity.col_4,
        LedMatrixActivity.row_3 | LedMatrixActivity.col_5,
        LedMatrixActivity.row_3 | LedMatrixActivity.col_6,
        LedMatrixActivity.row_3 | LedMatrixActivity.col_7,
        LedMatrixActivity.row_3 | LedMatrixActivity.col_8,

        LedMatrixActivity.row_2 | LedMatrixActivity.col_2,
        LedMatrixActivity.row_1 | LedMatrixActivity.col_9,
        LedMatrixActivity.row_2 | LedMatrixActivity.col_3,
        LedMatrixActivity.row_3 | LedMatrixActivity.col_9,
        LedMatrixActivity.row_2 | LedMatrixActivity.col_1,

        LedMatrixActivity.row_1 | LedMatrixActivity.col_8,
        LedMatrixActivity.row_1 | LedMatrixActivity.col_7,
        LedMatrixActivity.row_1 | LedMatrixActivity.col_6,
        LedMatrixActivity.row_1 | LedMatrixActivity.col_5,
        LedMatrixActivity.row_1 | LedMatrixActivity.col_4,

        LedMatrixActivity.row_3 | LedMatrixActivity.col_3,
        LedMatrixActivity.row_2 | LedMatrixActivity.col_7,
        LedMatrixActivity.row_3 | LedMatrixActivity.col_1,
        LedMatrixActivity.row_2 | LedMatrixActivity.col_6,
        LedMatrixActivity.row_3 | LedMatrixActivity.col_2,
    };
    const row_1: u32 = 0x2000;
    const row_2 = 0x4000;
    const row_3 = 0x8000;
};

const StatusActivity = struct {
    prev_now: u32,

    fn prepare(self: *StatusActivity) void {
        self.prev_now = cycle_activity.up_time_seconds;
        self.redraw();
    }

    fn redraw(self: *StatusActivity) void {
        lib.Terminal.move(999, 999);
        // Terminal.reportCursorPosition();
        Terminal.clearScreen();
        Terminal.setScrollingRegion(5, 99);
        Terminal.move(5 - 1, 1);
        log("keyboard input will be echoed below:", .{});
    }

    fn update(self: *StatusActivity) void {
        Uart.update();
        const now = cycle_activity.up_time_seconds;
        if (now >= self.prev_now + 1) {
            Terminal.hideCursor();
            Terminal.move(1, 1);
            Terminal.line("up {:3}s cycle {}us max {}us", .{ cycle_activity.up_time_seconds, cycle_activity.cycle_time, cycle_activity.max_cycle_time });
            Terminal.showCursor();
            Terminal.move(99, keyboard_activity.column);
            self.prev_now = now;
        }
    }
};

comptime {
    asm (
        \\.section .text.start.mission08
        \\.globl mission08_vector_table
        \\.balign 0x80
        \\mission08_vector_table:
        \\ .long 0x20004000 // sp top of 16KB ram
        \\ .long mission08_main
        \\ .long mission08_exceptionNumber02
        \\ .long mission08_exceptionNumber03
        \\ .long mission08_exceptionNumber04
        \\ .long mission08_exceptionNumber05
        \\ .long mission08_exceptionNumber06
        \\ .long mission08_exceptionNumber07
        \\ .long mission08_exceptionNumber08
        \\ .long mission08_exceptionNumber09
        \\ .long mission08_exceptionNumber10
        \\ .long mission08_exceptionNumber11
        \\ .long mission08_exceptionNumber12
        \\ .long mission08_exceptionNumber13
        \\ .long mission08_exceptionNumber14
        \\ .long mission08_exceptionNumber15
    );
}

export fn mission08_exceptionNumber01() noreturn {
    lib.exceptionHandler(01);
}

export fn mission08_exceptionNumber02() noreturn {
    lib.exceptionHandler(02);
}

export fn mission08_exceptionNumber03() noreturn {
    lib.exceptionHandler(03);
}

export fn mission08_exceptionNumber04() noreturn {
    lib.exceptionHandler(04);
}

export fn mission08_exceptionNumber05() noreturn {
    lib.exceptionHandler(05);
}

export fn mission08_exceptionNumber06() noreturn {
    lib.exceptionHandler(06);
}

export fn mission08_exceptionNumber07() noreturn {
    lib.exceptionHandler(07);
}

export fn mission08_exceptionNumber08() noreturn {
    lib.exceptionHandler(08);
}

export fn mission08_exceptionNumber09() noreturn {
    lib.exceptionHandler(09);
}

export fn mission08_exceptionNumber10() noreturn {
    lib.exceptionHandler(10);
}

export fn mission08_exceptionNumber11() noreturn {
    lib.exceptionHandler(11);
}

export fn mission08_exceptionNumber12() noreturn {
    lib.exceptionHandler(12);
}

export fn mission08_exceptionNumber13() noreturn {
    lib.exceptionHandler(13);
}

export fn mission08_exceptionNumber14() noreturn {
    lib.exceptionHandler(14);
}

export fn mission08_exceptionNumber15() noreturn {
    lib.exceptionHandler(15);
}

pub fn panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
    lib.panicf("panic(): {}", .{message});
}

const Bss = lib.Bss;
const builtin = @import("builtin");
const ClockManagement = lib.ClockManagement;
const Exceptions = lib.Exceptions;
const Gpio = lib.Gpio;
const lib = @import("lib00_basics.zig");
const literal = Uart.literal;
const log = Uart.log;
const std = @import("std");
const Terminal = lib.Terminal;
const TimeKeeper = lib.TimeKeeper;
const Timer0 = lib.Timer0;
const Timer1 = lib.Timer1;
const Timer2 = lib.Timer2;
const Uart = lib.Uart;

var cycle_activity: CycleActivity = undefined;
var keyboard_activity: KeyboardActivity = undefined;
var led_matrix_activity: LedMatrixActivity = undefined;
var status_activity: StatusActivity = undefined;
