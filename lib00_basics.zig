pub const Bss = struct {
    pub fn prepare() void {
        @memset(@ptrCast(*volatile [1]u8, &__bss_start), 0, @ptrToInt(&__bss_end) - @ptrToInt(&__bss_start));
    }
};

pub const ClockManagement = struct {
    pub fn prepareHf() void {
        crystal_registers.frequency_selector = 0xff;
        tasks.start_hf_clock = 1;
        while (events.hf_clock_started == 0) {}
    }

    pub const events = io(0x40000100, struct {
        hf_clock_started: u32,
        lf_clock_started: u32,
    });

    pub const crystal_registers = io(0x40000550, struct {
        frequency_selector: u32,
    });

    pub const tasks = io(0x40000000, struct {
        start_hf_clock: u32,
        stop_hf_clock: u32,
        start_lf_clock: u32,
        stop_lf_clock: u32,
    });
};

pub const Exceptions = struct {
    pub fn prepare() void {
        already_panicking = false;
    }
};

pub const Ficr = struct {
    pub const radio = io(0x100000a0, struct {
        device_address_type: u32,
        device_address0: u32,
        device_address1: u32,
    });
};

pub const Gpio = struct {
    pub const config = io(0x50000700, [32]u32);

    pub const config_masks = struct {
        pub const input = 0x0;
        pub const output = 0x1;
    };

    pub const led_row_driver_number_and_column_selector_number_indexed_by_y_then_x = [5][5][2]u32{
        .{ .{ 1, 1 }, .{ 2, 4 }, .{ 1, 2 }, .{ 2, 5 }, .{ 1, 3 } },
        .{ .{ 3, 4 }, .{ 3, 5 }, .{ 3, 6 }, .{ 3, 7 }, .{ 3, 8 } },
        .{ .{ 2, 2 }, .{ 1, 9 }, .{ 2, 3 }, .{ 3, 9 }, .{ 2, 1 } },
        .{ .{ 1, 8 }, .{ 1, 7 }, .{ 1, 6 }, .{ 1, 5 }, .{ 1, 4 } },
        .{ .{ 3, 3 }, .{ 2, 7 }, .{ 3, 1 }, .{ 2, 6 }, .{ 3, 2 } },
    };

    pub const registers = io(0x50000504, struct {
        out: u32,
        out_set: u32,
        out_clear: u32,
        in: u32,
        direction: u32,
        direction_set: u32,
        direction_clear: u32,
    });

    pub const registers_masks = struct {
        pub const button_a_active_low: u32 = 1 << 17;
        pub const button_b_active_low: u32 = 1 << 26;
        pub const nine_led_column_selectors_active_low: u32 = 0x1ff << 4;
        pub const ring0: u32 = 1 << 3;
        pub const ring1: u32 = 1 << 2;
        pub const ring2: u32 = 1 << 1;
        pub const three_led_row_drivers: u32 = 0x7 << 13;
        pub const uart_rx = 1 << 25;
        pub const uart_tx = 1 << 24;
    };
};

pub const Gpiote = struct {
    pub const config = io(0x40006510, [4]u32);

    pub const config_masks = struct {
        pub const disable = 0x0;
    };

    pub const tasks = struct {
        pub const out = io(0x40006000, [4]u32);
    };
};

pub const LedMatrixActivity = struct {
    image: u32,
    max_elapsed: u32,
    scan_lines: [3]u32,
    scan_lines_index: u32,
    scan_timer: TimeKeeper,

    pub fn currentImage(self: *LedMatrixActivity) u32 {
        return self.image;
    }

    pub fn maxElapsed(self: *LedMatrixActivity) u32 {
        return self.max_elapsed;
    }

    pub fn prepare(self: *LedMatrixActivity) void {
        self.image = 0;
        self.max_elapsed = 0;
        Gpio.registers.direction_set = Gpio.registers_masks.three_led_row_drivers | Gpio.registers_masks.nine_led_column_selectors_active_low;
        for (self.scan_lines) |*scan_line| {
            scan_line.* = 0;
        }
        self.scan_lines_index = 0;
        self.putChar('Z');
        self.scan_timer.prepare(3 * 1000);
    }

    fn putChar(self: *LedMatrixActivity, byte: u8) void {
        self.putImage(self.getImage(byte));
    }

    fn putImage(self: *LedMatrixActivity, image: u32) void {
        self.image = image;
        var mask: u32 = 0x1;
        var y: i32 = 4;
        while (y >= 0) : (y -= 1) {
            var x: i32 = 4;
            while (x >= 0) : (x -= 1) {
                self.putPixel(@intCast(u32, x), @intCast(u32, y), if (image & mask != 0) @as(u32, 1) else 0);
                mask <<= 1;
            }
        }
    }

    fn putPixel(self: *LedMatrixActivity, x: u32, y: u32, v: u32) void {
        const row_driver_number_and_column_selector_number = Gpio.led_row_driver_number_and_column_selector_number_indexed_by_y_then_x[y][x];
        const selected_scan_line_index = row_driver_number_and_column_selector_number[0] - 1;
        const col_mask = @as(u32, 0x10) << @truncate(u5, row_driver_number_and_column_selector_number[1] - 1);
        self.scan_lines[selected_scan_line_index] = self.scan_lines[selected_scan_line_index] & ~col_mask | v * col_mask;
    }

    pub fn update(self: *LedMatrixActivity) void {
        if (self.scan_timer.isFinished()) {
            const elapsed = self.scan_timer.elapsed();
            if (elapsed > self.max_elapsed) {
                self.max_elapsed = elapsed;
            }
            self.scan_timer.reset();
            const keep = Gpio.registers.out & ~(Gpio.registers_masks.three_led_row_drivers | Gpio.registers_masks.nine_led_column_selectors_active_low);
            const row_pins = @as(u32, 0x2000) << @truncate(u5, self.scan_lines_index);
            const col_pins = ~self.scan_lines[self.scan_lines_index] & Gpio.registers_masks.nine_led_column_selectors_active_low;
            Gpio.registers.out = keep | row_pins | col_pins;
            self.scan_lines_index = (self.scan_lines_index + 1) % self.scan_lines.len;
        }
    }

    fn getImage(self: *LedMatrixActivity, byte: u8) u32 {
        return switch (byte) {
            ' ' => 0b0000000000000000000000000,
            '0' => 0b1111110001100011000111111,
            '1' => 0b0010001100001000010001110,
            '2' => 0b1111100001111111000011111,
            '3' => 0b1111100001001110000111111,
            '4' => 0b1000110001111110000100001,
            '5' => 0b1111110000111110000111111,
            '6' => 0b1111110000111111000111111,
            '7' => 0b1111100001000100010001000,
            '8' => 0b1111110001111111000111111,
            '9' => 0b1111110001111110000100001,
            'A' => 0b0111010001111111000110001,
            'B' => 0b1111010001111111000111110,
            'Z' => 0b1111100010001000100011111,
            else => 0b0000000000001000000000000,
        };
    }
};

pub const Ppi = struct {
    pub const registers = io(0x4001f500, struct {
        channel_enable: u32,
        channel_enable_set: u32,
        channel_enable_clear: u32,
    });

    pub const channels = io(0x4001f510, [16]struct {
        event_end_point: u32,
        task_end_point: u32,
    });
};

pub const Radio = struct {
    pub const events = io(0x40001100, struct {
        ready: u32,
        address_completed: u32,
        payload_completed: u32,
        packet_completed: u32,
        disabled: u32,
    });

    pub const registers = io(0x40001504, struct {
        packet_ptr: u32,
        frequency: u32,
        tx_power: u32,
        mode: u32,
        pcnf0: u32,
        pcnf1: u32,
        base0: u32,
        base1: u32,
        prefix0: u32,
        prefix1: u32,
        tx_address: u32,
        rx_addresses: u32,
        crc_config: u32,
        crc_poly: u32,
        crc_init: u32,
        unused0x540: u32,
        unused0x544: u32,
        unused0x548: u32,
        unused0x54c: u32,
        state: u32,
        datawhiteiv: u32,
    });

    pub const rx_registers = io(0x40001400, struct {
        crc_status: u32,
        unused0x404: u32,
        unused0x408: u32,
        rx_crc: u32,
    });

    pub const short_cuts = io(0x40001200, struct {
        shorts: u32,
    });

    pub const tasks = io(0x40001000, struct {
        tx_enable: u32,
        rx_enable: u32,
        start: u32,
        stop: u32,
        disable: u32,
    });
};

pub const Rng = struct {
    pub fn prepare() void {
        registers.config = 0x1;
        tasks.start = 1;
    }

    pub const events = io(0x4000d100, struct {
        value_ready: u32,
    });

    pub const registers = io(0x4000d504, struct {
        config: u32,
        value: u32,
    });

    pub const tasks = io(0x4000d000, struct {
        start: u32,
        stop: u32,
    });
};

pub const Terminal = struct {
    pub fn attribute(n: u32) void {
        pair(n, 0, "m");
    }

    pub fn clearScreen() void {
        pair(2, 0, "J");
    }

    pub fn hideCursor() void {
        Uart.writeText(csi ++ "?25l");
    }

    pub fn line(comptime format: []const u8, args: var) void {
        literal(format, args);
        pair(0, 0, "K");
        Uart.writeText("\n");
    }

    pub fn move(row: u32, column: u32) void {
        pair(row, column, "H");
    }

    pub fn pair(a: u32, b: u32, letter: []const u8) void {
        if (a <= 1 and b <= 1) {
            literal("{}{}", .{ csi, letter });
        } else if (b <= 1) {
            literal("{}{}{}", .{ csi, a, letter });
        } else if (a <= 1) {
            literal("{};{}{}", .{ csi, b, letter });
        } else {
            literal("{}{};{}{}", .{ csi, a, b, letter });
        }
    }

    pub fn reportCursorPosition() void {
        Uart.writeText(csi ++ "6n");
    }

    pub fn restoreCursor() void {
        pair(0, 0, "u");
    }

    pub fn saveCursor() void {
        pair(0, 0, "s");
    }

    pub fn setScrollingRegion(top: u32, bottom: u32) void {
        pair(top, bottom, "r");
    }

    pub fn showCursor() void {
        Uart.writeText(csi ++ "?25h");
    }

    const csi = "\x1b[";
};

pub const TimeKeeper = struct {
    duration: u32,
    start_time: u32,

    fn capture(self: *TimeKeeper) u32 {
        Timer0.capture_tasks[0] = 1;
        return Timer0.capture_compare_registers[0];
    }

    fn elapsed(self: *TimeKeeper) u32 {
        return self.capture() -% self.start_time;
    }

    fn prepare(self: *TimeKeeper, duration: u32) void {
        self.duration = duration;
        self.reset();
    }

    fn isFinished(self: *TimeKeeper) bool {
        return self.elapsed() >= self.duration;
    }

    fn reset(self: *TimeKeeper) void {
        self.start_time = self.capture();
    }
};

pub fn TimerInstance(instance_address: u32) type {
    return struct {
        pub fn capture() u32 {
            capture_tasks[0] = 1;
            return capture_compare_registers[0];
        }

        pub fn prepare() void {
            registers.mode = 0x0;
            registers.bit_mode = if (instance_address == 0x40008000) @as(u32, 0x3) else 0x0;
            registers.prescaler = if (instance_address == 0x40008000) @as(u32, 4) else 9;
            tasks.start = 1;
        }

        pub const capture_compare_registers = io(instance_address + 0x540, [4]u32);

        pub const capture_tasks = io(instance_address + 0x040, [4]u32);

        pub const events = struct {
            pub const compare = io(instance_address + 0x140, [4]u32);
        };

        pub const registers = io(instance_address + 0x504, struct {
            mode: u32,
            bit_mode: u32,
            unused0x50c: u32,
            prescaler: u32,
        });

        pub const short_cuts = io(instance_address + 0x200, struct {
            shorts: u32,
        });

        pub const tasks = io(instance_address + 0x000, struct {
            start: u32,
            stop: u32,
            count: u32,
            clear: u32,
        });
    };
}

pub const Uart = struct {
    tx_busy: bool,
    tx_queue: [3]u8,
    tx_queue_read: usize,
    tx_queue_write: usize,
    updater: ?fn () void,

    pub fn drainTxQueue() void {
        while (uart_singleton.tx_queue_read != uart_singleton.tx_queue_write) {
            loadTxd();
        }
    }

    pub fn prepare() void {
        uart_singleton.updater = null;
        Gpio.registers.direction_set = Gpio.registers_masks.uart_tx;
        registers.pin_select_rxd = @ctz(u32, Gpio.registers_masks.uart_rx);
        registers.pin_select_txd = @ctz(u32, Gpio.registers_masks.uart_tx);
        registers.enable = 0x04;
        tasks.start_rx = 1;
        tasks.start_tx = 1;
        uart_singleton.tx_busy = false;
        uart_singleton.tx_queue_read = 0;
        uart_singleton.tx_queue_write = 0;
    }

    pub fn isReadByteReady() bool {
        return Uart.events.rx_ready == 1;
    }

    pub fn literal(comptime format: []const u8, args: var) void {
        fmt.format({}, error{}, uart_logBytes, format, args) catch |e| switch (e) {};
    }

    pub fn loadTxd() void {
        if (uart_singleton.tx_queue_read != uart_singleton.tx_queue_write and (!uart_singleton.tx_busy or Uart.events.tx_ready == 1)) {
            events.tx_ready = 0;
            registers.txd = uart_singleton.tx_queue[uart_singleton.tx_queue_read];
            uart_singleton.tx_queue_read = (uart_singleton.tx_queue_read + 1) % uart_singleton.tx_queue.len;
            uart_singleton.tx_busy = true;
            if (uart_singleton.updater) |updater| {
                updater();
            }
        }
    }

    pub fn log(comptime format: []const u8, args: var) void {
        literal(format ++ "\n", args);
    }

    pub fn readByte() u8 {
        events.rx_ready = 0;
        return @truncate(u8, Uart.registers.rxd);
    }

    pub fn setUpdater(updater: fn () void) void {
        uart_singleton.updater = updater;
    }

    pub fn update() void {
        loadTxd();
    }

    pub fn writeByteBlocking(byte: u8) void {
        const next = (uart_singleton.tx_queue_write + 1) % uart_singleton.tx_queue.len;
        while (next == uart_singleton.tx_queue_read) {
            loadTxd();
        }
        uart_singleton.tx_queue[uart_singleton.tx_queue_write] = byte;
        uart_singleton.tx_queue_write = next;
        loadTxd();
    }

    pub fn writeText(buffer: []const u8) void {
        for (buffer) |c| {
            switch (c) {
                '\n' => {
                    writeByteBlocking('\r');
                    writeByteBlocking('\n');
                },
                else => writeByteBlocking(c),
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

pub fn exceptionHandler(exception_number: u32) noreturn {
    panicf("exception number {} ... now idle in arm exception handler", .{exception_number});
}

pub fn hangf(comptime format: []const u8, args: var) noreturn {
    log(format, args);
    Uart.drainTxQueue();
    while (true) {}
}

pub fn io(address: u32, comptime StructType: type) *volatile StructType {
    return @intToPtr(*volatile StructType, address);
}

pub fn panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
    panicf("panic(): {}", .{message});
}

pub fn panicf(comptime format: []const u8, args: var) noreturn {
    @setCold(true);
    if (already_panicking) {
        hangf("\npanicked during panic", .{});
    }
    already_panicking = true;
    log("\npanic: " ++ format, args);
    hangf("panic completed", .{});
}

fn uart_logBytes(context: void, bytes: []const u8) error{}!void {
    Uart.writeText(bytes);
}

const builtin = @import("builtin");
const fmt = std.fmt;
const literal = Uart.literal;
const log = Uart.log;
const std = @import("std");

extern var __bss_start: u8;
extern var __bss_end: u8;

pub const ram_u32 = @intToPtr(*[4096]u32, 0x20000000);
pub const Timer0 = TimerInstance(0x40008000);
pub const Timer1 = TimerInstance(0x40009000);
pub const Timer2 = TimerInstance(0x4000a000);

var already_panicking: bool = undefined;
var led_matrix_activity: LedMatrixActivity = undefined;
var uart_singleton: Uart = undefined;
