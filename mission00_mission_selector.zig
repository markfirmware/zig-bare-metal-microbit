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

export fn mission00_main() noreturn {
    const ram: [*]u32 = @intToPtr([*]u32, 0x20000000);
    ram[0x1000 - 1] = @ptrToInt(mission00_panic);
    setBssToZero();
    already_panicking = false;
    missionMenu();
    uart.init();

    cycle_activity.init();
    keyboard_activity.init();
    led_matrix_activity.init();
    status_activity.init();

    missions[0] = .{ .name = "mission selector", .panic = panic, .vector_table = &mission00_vector_table };
    missions[1] = .{ .name = "turn on all leds", .panic = @import("mission01_turn_on_all_leds.zig").panic, .vector_table = &mission01_vector_table };
    missions[2] = .{ .name = "model railroad", .panic = @import("mission02_model_railroad.zig").panic, .vector_table = &mission02_vector_table };
    missions[3] = .{ .name = "unassigned", .panic = @import("mission03_unassigned.zig").panic, .vector_table = &mission03_vector_table };
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
        led_matrix_activity.update();
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

    fn init(self: *CycleActivity) void {
        self.cycle_counter = 0;
        self.cycle_time = 0;
        self.last_cycle_start = null;
        self.last_second_ticks = 0;
        self.max_cycle_time = 0;
        self.up_time_seconds = 0;
        timer0.init();
        timer0.start();
        timer0.begin(5 * 1000);
    }

    fn update(self: *CycleActivity) void {
        self.cycle_counter += 1;
        const new_cycle_start = timer0.capture();
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

    fn init(self: *KeyboardActivity) void {
        self.column = 1;
    }

    fn update(self: *KeyboardActivity) void {
        if (!uart.isReadByteReady()) {
            return;
        }
        const byte = uart.readByte();
        switch (byte) {
            27 => {
                uart.writeByteBlocking('$');
                self.column += 1;
            },
            12, '-' => {
                status_activity.redraw();
            },
            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                missions[byte - '0'].activate();
            },
            '\r' => {
                uart.writeText("\n");
                self.column = 1;
            },
            else => {
                uart.writeByteBlocking(byte);
                self.column += 1;
            },
        }
    }
};

const LedMatrixActivity = struct {
    scan_lines: [3]u32,
    scan_lines_index: u32,

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

    fn init(self: *LedMatrixActivity) void {
        Gpio.registers.direction_set = LedMatrixActivity.all_led_pins_mask;
        for (self.scan_lines) |_, i| {
            self.scan_lines[i] = LedMatrixActivity.row_1 << @truncate(u5, i) | LedMatrixActivity.all_led_cols_mask;
        }
        self.scan_lines_index = 0;
        led_matrix_activity.drawZigIcon();
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
        if (timer0.isFinished()) {
            Gpio.registers.out = Gpio.registers.out & ~LedMatrixActivity.all_led_pins_mask | self.scan_lines[self.scan_lines_index];
            self.scan_lines_index = (self.scan_lines_index + 1) % self.scan_lines.len;
            timer0.reset();
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
    pwm_counter: u32,

    fn init(self: *StatusActivity) void {
        self.prev_now = cycle_activity.up_time_seconds;
        self.pwm_counter = 0;
        self.redraw();
    }

    fn redraw(self: *StatusActivity) void {
        term.move(999, 999);
        // term.reportCursorPosition();
        term.clearScreen();
        term.setScrollingRegion(5, 99);
        term.move(5 - 1, 1);
        log("keyboard input will be echoed below:", .{});
    }

    fn update(self: *StatusActivity) void {
        uart.loadTxd();
        if (Gpio.registers.in & 0x8 != 0) {
            self.pwm_counter += 1;
        }
        const now = cycle_activity.up_time_seconds;
        if (now >= self.prev_now + 1) {
            term.hideCursor();
            term.move(1, 1);
            term.line("up {:3}s cycle {}us max {}us", .{ cycle_activity.up_time_seconds, cycle_activity.cycle_time, cycle_activity.max_cycle_time });
            term.line("gpio.in {x:8}", .{Gpio.registers.in & ~@as(u32, 0x0300fff0)});
            term.line("", .{});
            term.showCursor();
            term.restoreInputLine();
            self.prev_now = now;
            self.pwm_counter = 0;
        }
    }
};

const Gpio = struct {
    const config_registers = io(0x50000700, struct {
        cnf00: u32,
        cnf01: u32,
        cnf02: u32,
        cnf03: u32,
        cnf04: u32,
        cnf05: u32,
        cnf06: u32,
        cnf07: u32,
        cnf08: u32,
        cnf09: u32,
        cnf10: u32,
        cnf11: u32,
        cnf12: u32,
        cnf13: u32,
        cnf14: u32,
        cnf15: u32,
        cnf16: u32,
        cnf17: u32,
        cnf18: u32,
        cnf19: u32,
        cnf20: u32,
        cnf21: u32,
        cnf22: u32,
        cnf23: u32,
        cnf24: u32,
        cnf25: u32,
        cnf26: u32,
        cnf27: u32,
        cnf28: u32,
        cnf30: u32,
        cnf31: u32,
    });

    const registers = io(0x50000504, struct {
        out: u32,
        out_set: u32,
        out_clear: u32,
        in: u32,
        direction: u32,
        direction_set: u32,
        direction_clear: u32,
    });
};

const Terminal = struct {
    fn clearScreen(self: *Terminal) void {
        self.pair(2, 0, "J");
    }

    fn hideCursor(self: *Terminal) void {
        literal("{}", .{Terminal.csi ++ "?25l"});
    }

    fn line(self: *Terminal, comptime format: []const u8, args: var) void {
        literal(format, args);
        self.pair(0, 0, "K");
        literal("{}", .{"\r\n"});
    }

    fn move(self: *Terminal, row: u32, column: u32) void {
        self.pair(row, column, "H");
    }

    fn pair(self: *Terminal, a: u32, b: u32, letter: []const u8) void {
        if (a <= 1 and b <= 1) {
            literal("{}{}", .{ Terminal.csi, letter });
        } else if (b <= 1) {
            literal("{}{}{}", .{ Terminal.csi, a, letter });
        } else if (a <= 1) {
            literal("{};{}{}", .{ Terminal.csi, b, letter });
        } else {
            literal("{}{};{}{}", .{ Terminal.csi, a, b, letter });
        }
    }

    fn reportCursorPosition(self: *Terminal) void {
        literal("{}", .{Terminal.csi ++ "6n"});
    }

    fn restoreCursor(self: *Terminal) void {
        self.pair(0, 0, "u");
    }

    fn restoreInputLine(self: *Terminal) void {
        self.move(99, keyboard_activity.column);
    }

    fn saveCursor(self: *Terminal) void {
        self.pair(0, 0, "s");
    }

    fn setScrollingRegion(self: *Terminal, top: u32, bottom: u32) void {
        self.pair(top, bottom, "r");
    }

    fn showCursor(self: *Terminal) void {
        literal("{}", .{Terminal.csi ++ "?25h"});
    }

    const csi = "\x1b[";
};

fn timerInstance(instance_address: u32, comptime bit_width: u32) type {
    return struct {
        duration: u32,
        start_time: u32,
        last: u32,
        overflow: u32,

        fn begin(self: *Timer, n: u32) void {
            self.duration = n;
            self.reset();
        }

        fn capture(self: *Timer) u32 {
            Timer.capture_tasks.capture0 = 1;
            const now = Timer.capture_compare_registers.cc0;
            if (bit_width == 16 and now < self.last) {
                self.overflow += 1;
            }
            self.last = now;
            return self.overflow << 16 | now;
        }

        fn init(self: *Timer) void {
            self.last = 0;
            self.overflow = 0;
            Timer.registers.mode = 0x0;
            Timer.registers.bit_mode = if (bit_width == 32) @as(u32, 0x3) else 0x0;
            Timer.registers.prescaler = if (bit_width == 32) @as(u32, 4) else 9;
        }

        fn isFinished(self: *Timer) bool {
            const now = self.capture();
            return now -% self.start_time >= self.duration;
        }

        fn reset(self: *Timer) void {
            self.start_time = self.capture();
        }

        fn start(self: *Timer) void {
            Timer.tasks.start = 1;
        }

        const capture_compare_registers = io(instance_address + 0x540, struct {
            cc0: u32,
            cc1: u32,
            cc2: u32,
            cc3: u32,
        });

        const events = io(instance_address + 0x140, struct {
            compare0: u32,
            compare1: u32,
            compare2: u32,
            compare3: u32,
        });

        const short_cuts = io(instance_address + 0x200, struct {
            shorts: u32,
        });

        const capture_tasks = io(instance_address + 0x040, struct {
            capture0: u32,
        });

        const registers = io(instance_address + 0x504, struct {
            mode: u32,
            bit_mode: u32,
            unused0x50c: u32,
            prescaler: u32,
        });

        const Timer = @This();

        const tasks = io(instance_address + 0x000, struct {
            start: u32,
            stop: u32,
            count: u32,
            clear: u32,
        });
    };
}

const Uart = struct {
    tx_busy: bool,
    tx_queue: [3]u8,
    tx_queue_read: usize,
    tx_queue_write: usize,

    fn drainTxQueue(self: *Uart) void {
        while (self.tx_queue_read != self.tx_queue_write) {
            self.loadTxd();
        }
    }

    fn init(self: *Uart) void {
        const uart_rx_pin = 25;
        const uart_tx_pin = 24;
        Gpio.registers.direction_set = 1 << uart_tx_pin;
        Uart.registers.pin_select_rxd = uart_rx_pin;
        Uart.registers.pin_select_txd = uart_tx_pin;
        Uart.registers.enable = 0x04;
        Uart.tasks.start_rx = 1;
        Uart.tasks.start_tx = 1;
        self.tx_busy = false;
        self.tx_queue_read = 0;
        self.tx_queue_write = 0;
    }

    fn isReadByteReady(self: Uart) bool {
        return Uart.events.rx_ready == 1;
    }

    fn literal(self: *Uart, comptime format: []const u8, args: var) void {
        fmt.format({}, NoError, uart_logBytes, format, args) catch |e| switch (e) {};
    }

    fn loadTxd(self: *Uart) void {
        if (self.tx_queue_read != self.tx_queue_write and (!self.tx_busy or Uart.events.tx_ready == 1)) {
            Uart.events.tx_ready = 0;
            Uart.registers.txd = self.tx_queue[self.tx_queue_read];
            self.tx_queue_read = (self.tx_queue_read + 1) % self.tx_queue.len;
            self.tx_busy = true;
        }
    }

    fn log(self: *Uart, comptime format: []const u8, args: var) void {
        self.literal(format ++ "\n", args);
    }

    fn logNow(self: *Uart, comptime format: []const u8, args: var) void {
        self.log(format, args);
        uart.drainTxQueue();
    }

    fn readByte(self: *Uart) u8 {
        Uart.events.rx_ready = 0;
        return @truncate(u8, Uart.registers.rxd);
    }

    fn writeByteBlocking(self: *Uart, byte: u8) void {
        const next = (self.tx_queue_write + 1) % self.tx_queue.len;
        while (next == self.tx_queue_read) {
            self.loadTxd();
        }
        self.tx_queue[self.tx_queue_write] = byte;
        self.tx_queue_write = next;
        self.loadTxd();
    }

    fn writeText(self: *Uart, buffer: []const u8) void {
        for (buffer) |c| {
            switch (c) {
                '\n' => {
                    self.writeByteBlocking('\r');
                    self.writeByteBlocking('\n');
                },
                else => self.writeByteBlocking(c),
            }
        }
    }

    const events = io(0x40002108, struct {
        rx_ready: u32,
        unused0x10c: u32,
        unused0x110: u32,
        unused0x114: u32,
        unused0x118: u32,
        tx_ready: u32,
        unused0x120: u32,
        error_detected: u32,
    });

    const error_registers = io(0x40002480, struct {
        error_source: u32,
    });

    const registers = io(0x40002500, struct {
        enable: u32,
        unused0x504: u32,
        pin_select_rts: u32,
        pin_select_txd: u32,
        pin_select_cts: u32,
        pin_select_rxd: u32,
        rxd: u32,
        txd: u32,
        unused0x520: u32,
        baud_rate: u32,
    });

    const tasks = io(0x40002000, struct {
        start_rx: u32,
        stop_rx: u32,
        start_tx: u32,
        stop_tx: u32,
    });
};

fn delayMicroseconds(n: u32) void {
    const start = timer0.capture();
    while (timer0.capture() -% start < n) {}
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

fn hangf(comptime format: []const u8, args: var) noreturn {
    uart.logNow(format, args);
    while (true) {
        asm volatile ("wfe");
    }
}

fn io(address: u32, comptime StructType: type) *volatile StructType {
    return @intToPtr(*volatile StructType, address);
}

fn missionMenu() void {
    Gpio.config_registers.cnf26 = 0;
    while (Gpio.registers.in & 0x4000000 == 0) {}
}

pub fn mission00_panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
    panicf("main.zig pub fn panic(): {}", .{message});
}

pub fn panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
    const ram: [*]u32 = @intToPtr([*]u32, 0x20000000);
    const mission_panic = @intToPtr(fn ([]const u8, ?*builtin.StackTrace) noreturn, ram[0x1000 - 1]);
    mission_panic(message, trace);
}

fn panicf(comptime format: []const u8, args: var) noreturn {
    @setCold(true);
    if (already_panicking) {
        hangf("\npanicked during kernel panic", .{});
    }
    already_panicking = true;
    log("\npanic: " ++ format, args);
    hangf("panic completed", .{});
}

fn setBssToZero() void {
    @memset(@ptrCast(*volatile [1]u8, &__bss_start), 0, @ptrToInt(&__bss_end) - @ptrToInt(&__bss_start));
}

fn uart_logBytes(context: void, bytes: []const u8) NoError!void {
    uart.writeText(bytes);
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

const builtin = @import("builtin");
const fmt = std.fmt;
const literal = uart.literal;
const log = uart.log;
const math = std.math;
const mem = std.mem;
const name = "zig-bare-metal-microbit";
const NoError = error{};
const release_tag = "0.4";
const std = @import("std");

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

var already_panicking: bool = undefined;
var cycle_activity: CycleActivity = undefined;
var gpio: Gpio = undefined;
var keyboard_activity: KeyboardActivity = undefined;
var led_matrix_activity: LedMatrixActivity = undefined;
var missions: [10]Mission = undefined;
var status_activity: StatusActivity = undefined;
var term: Terminal = undefined;
var timer0: timerInstance(0x40008000, 32) = undefined;
var timer1: timerInstance(0x40009000, 16) = undefined;
var timer2: timerInstance(0x4000a000, 16) = undefined;
var uart: Uart = undefined;
