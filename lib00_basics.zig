pub const Bss = struct {
    pub fn prepare() void {
        @memset(@ptrCast([*]u8, &__bss_start), 0, @ptrToInt(&__bss_end) - @ptrToInt(&__bss_start));
    }
};

pub const ClockManagement = struct {
    pub fn prepareHf() void {
        crystal_registers.frequency_selector = 0xff;
        tasks.start_hf_clock = 1;
        while (events.hf_clock_started == 0) {}
    }

    pub const events = mmio(0x40000100, extern struct {
        hf_clock_started: u32,
        lf_clock_started: u32,
    });

    pub const crystal_registers = mmio(0x40000550, extern struct {
        frequency_selector: u32,
    });

    pub const tasks = mmio(0x40000000, extern struct {
        start_hf_clock: u32,
        stop_hf_clock: u32,
        start_lf_clock: u32,
        stop_lf_clock: u32,
    });
};

pub const Exceptions = struct {
    var already_panicking: bool = undefined;

    pub fn prepare() void {
        already_panicking = false;
    }

    pub fn handle(exception_number: u32) noreturn {
        panicf("exception number {} ... now idle in arm exception handler", .{exception_number});
}
};

pub const Ficr = struct {
    pub const radio = mmio(0x100000a0, extern struct {
        device_address_type: u32,
        device_address0: u32,
        device_address1: u32,
    });
};

pub const Gpio = struct {
    pub const config = mmio(0x50000700, [32]u32);

    pub const config_masks = struct {
        pub const input = 0x0;
        pub const output = 0x1;
    };

    pub const led_anode_number_and_cathode_number_indexed_by_y_then_x = [5][5][2]u32{
        .{ .{ 1, 1 }, .{ 2, 4 }, .{ 1, 2 }, .{ 2, 5 }, .{ 1, 3 } },
        .{ .{ 3, 4 }, .{ 3, 5 }, .{ 3, 6 }, .{ 3, 7 }, .{ 3, 8 } },
        .{ .{ 2, 2 }, .{ 1, 9 }, .{ 2, 3 }, .{ 3, 9 }, .{ 2, 1 } },
        .{ .{ 1, 8 }, .{ 1, 7 }, .{ 1, 6 }, .{ 1, 5 }, .{ 1, 4 } },
        .{ .{ 3, 3 }, .{ 2, 7 }, .{ 3, 1 }, .{ 2, 6 }, .{ 3, 2 } },
    };

    pub const registers = mmio(0x50000504, extern struct {
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
        pub const nine_led_cathodes_active_low: u32 = 0x1ff << 4;
        pub const ring0: u32 = 1 << 3;
        pub const ring1: u32 = 1 << 2;
        pub const ring2: u32 = 1 << 1;
        pub const three_led_anodes: u32 = 0x7 << 13;
        pub const uart_rx = 1 << 25;
        pub const uart_tx = 1 << 24;
    };
};

pub const Gpiote = struct {
    pub const config = mmio(0x40006510, [4]u32);

    pub const config_masks = struct {
        pub const disable = 0x0;
    };

    pub const tasks = struct {
        pub const out = mmio(0x40006000, [4]u32);
    };
};

pub const LedMatrix = struct {
    pub var max_elapsed: u32 = undefined;
    pub var image: u32 = undefined;
    var scan_lines: [3]u32 = undefined;
    var scan_lines_index: u32 = undefined;
    var scan_timer: TimeKeeper = undefined;

    pub fn prepare() void {
        image = 0;
        max_elapsed = 0;
        Gpio.registers.direction_set = Gpio.registers_masks.three_led_anodes | Gpio.registers_masks.nine_led_cathodes_active_low;
        for (scan_lines) |*scan_line| {
            scan_line.* = 0;
        }
        scan_lines_index = 0;
        putChar('Z');
        scan_timer.prepare(3 * 1000);
    }

    pub fn putChar(byte: u8) void {
        putImage(getImage(byte));
    }

    pub fn putImage(new_image: u32) void {
        image = new_image;
        var mask: u32 = 0x1;
        var y: i32 = 4;
        while (y >= 0) : (y -= 1) {
            var x: i32 = 4;
            while (x >= 0) : (x -= 1) {
                putPixel(@intCast(u32, x), @intCast(u32, y), if (image & mask != 0) @as(u32, 1) else 0);
                mask <<= 1;
            }
        }
    }

    fn putPixel(x: u32, y: u32, v: u32) void {
        const anode_number_and_cathode_number  = Gpio.led_anode_number_and_cathode_number_indexed_by_y_then_x[y][x];
        const selected_scan_line_index = anode_number_and_cathode_number[0] - 1;
        const col_mask = @as(u32, 0x10) << @truncate(u5, anode_number_and_cathode_number[1] - 1);
        scan_lines[selected_scan_line_index] = scan_lines[selected_scan_line_index] & ~col_mask | v * col_mask;
    }

    pub fn update() void {
        if (scan_timer.isFinished()) {
            const elapsed = scan_timer.elapsed();
            if (elapsed > max_elapsed) {
                max_elapsed = elapsed;
            }
            scan_timer.reset();
            const keep = Gpio.registers.out & ~(Gpio.registers_masks.three_led_anodes | Gpio.registers_masks.nine_led_cathodes_active_low);
            const row_pins = @as(u32, 0x2000) << @truncate(u5, scan_lines_index);
            const col_pins = ~scan_lines[scan_lines_index] & Gpio.registers_masks.nine_led_cathodes_active_low;
            Gpio.registers.out = keep | row_pins | col_pins;
            scan_lines_index = (scan_lines_index + 1) % scan_lines.len;
        }
    }

    pub fn getImage(byte: u8) u32 {
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
    pub fn setChannelEventAndTask(channel: u32, event: *volatile u32, task: *volatile u32) void {
        channels[channel].event_end_point = @ptrToInt(event);
        channels[channel].task_end_point = @ptrToInt(task);
    }

    pub const registers = mmio(0x4001f500, extern struct {
        channel_enable: u32,
        channel_enable_set: u32,
        channel_enable_clear: u32,
    });

    const channels = mmio(0x4001f510, [16]struct {
        event_end_point: u32,
        task_end_point: u32,
    });
};

pub const Radio = struct {
    pub const events = mmio(0x40001100, extern struct {
        ready: u32,
        address_completed: u32,
        payload_completed: u32,
        packet_completed: u32,
        disabled: u32,
    });

    pub const registers = mmio(0x40001504, struct {
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

    pub const rx_registers = mmio(0x40001400, extern struct {
        crc_status: u32,
        unused0x404: u32,
        unused0x408: u32,
        rx_crc: u32,
    });

    pub const short_cuts = mmio(0x40001200, extern struct {
        shorts: u32,
    });

    pub const tasks = mmio(0x40001000, extern struct {
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

    pub const events = mmio(0x4000d100, extern struct {
        value_ready: u32,
    });

    pub const registers = mmio(0x4000d504, extern struct {
        config: u32,
        value: u32,
    });

    pub const tasks = mmio(0x4000d000, extern struct {
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

        pub const capture_compare_registers = mmio(instance_address + 0x540, [4]u32);

        pub const capture_tasks = mmio(instance_address + 0x040, [4]u32);

        pub const events = struct {
            pub const compare = mmio(instance_address + 0x140, [4]u32);
        };

        pub const registers = mmio(instance_address + 0x504, extern struct {
            mode: u32,
            bit_mode: u32,
            unused0x50c: u32,
            prescaler: u32,
        });

        pub const short_cuts = mmio(instance_address + 0x200, extern struct {
            shorts: u32,
        });

        pub const tasks = mmio(instance_address + 0x000, extern struct {
            start: u32,
            stop: u32,
            count: u32,
            clear: u32,
        });
    };
}

pub const Uart = struct {
    var tx_busy: bool = undefined;
    var tx_queue: [3]u8 = undefined;
    var tx_queue_read: usize = undefined;
    var tx_queue_write: usize = undefined;
    var updater: ?fn () void = undefined;

    pub fn drainTxQueue() void {
        while (tx_queue_read != tx_queue_write) {
            loadTxd();
        }
    }

    pub fn prepare() void {
        updater = null;
        Gpio.registers.direction_set = Gpio.registers_masks.uart_tx;
        registers.pin_select_rxd = @ctz(u32, Gpio.registers_masks.uart_rx);
        registers.pin_select_txd = @ctz(u32, Gpio.registers_masks.uart_tx);
        registers.enable = 0x04;
        tasks.start_rx = 1;
        tasks.start_tx = 1;
        tx_busy = false;
        tx_queue_read = 0;
        tx_queue_write = 0;
    }

    pub fn isReadByteReady() bool {
        return Uart.events.rx_ready == 1;
    }

    pub fn literal(comptime format: []const u8, args: var) void {
        fmt.format({}, error{}, uart_logBytes, format, args) catch |e| switch (e) {};
    }

    pub fn loadTxd() void {
        if (tx_queue_read != tx_queue_write and (!tx_busy or Uart.events.tx_ready == 1)) {
            events.tx_ready = 0;
            registers.txd = tx_queue[tx_queue_read];
            tx_queue_read = (tx_queue_read + 1) % tx_queue.len;
            tx_busy = true;
            if (updater) |an_updater| {
                an_updater();
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

    pub fn setUpdater(new_updater: fn () void) void {
        updater = new_updater;
    }

    pub fn update() void {
        loadTxd();
    }

    pub fn writeByteBlocking(byte: u8) void {
        const next = (tx_queue_write + 1) % tx_queue.len;
        while (next == tx_queue_read) {
            loadTxd();
        }
        tx_queue[tx_queue_write] = byte;
        tx_queue_write = next;
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

    const events = mmio(0x40002108, extern struct {
        rx_ready: u32,
        unused0x10c: u32,
        unused0x110: u32,
        unused0x114: u32,
        unused0x118: u32,
        tx_ready: u32,
        unused0x120: u32,
        error_detected: u32,
    });

    const error_registers = mmio(0x40002480, extern struct {
        error_source: u32,
    });

    const registers = mmio(0x40002500, extern struct {
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

    const tasks = mmio(0x40002000, extern struct {
        start_rx: u32,
        stop_rx: u32,
        start_tx: u32,
        stop_tx: u32,
    });
};

pub fn hangf(comptime format: []const u8, args: var) noreturn {
    log(format, args);
    Uart.drainTxQueue();
    while (true) {}
}

pub fn mmio(address: u32, comptime mmio_type: type) *volatile mmio_type {
    return @intToPtr(*volatile mmio_type, address);
}

pub fn panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
    panicf("panic(): {}", .{message});
}

pub fn panicf(comptime format: []const u8, args: var) noreturn {
    @setCold(true);
    if (Exceptions.already_panicking) {
        hangf("\npanicked during panic", .{});
    }
    Exceptions.already_panicking = true;
    log("\npanic: " ++ format, args);
    hangf("panic completed", .{});
}

pub fn typicalVectorTable(comptime mission_index: u32) []const u8 {
    var buf: [2]u8 = undefined;
    const mission_string = std.fmt.bufPrint(&buf, "{:2}", .{mission_index}) catch |_| panicf("", .{});
    for (mission_string) |*space| {
        if (space.* == ' ') {
            space.* = '0';
        } else {
            break;
        }
    }
    return ".section .text.start.mission" ++ mission_string ++ "\n" ++
        ".globl mission" ++ mission_string ++ "_vector_table\n" ++
        ".balign 0x80\n" ++
        "mission" ++ mission_string ++ "_vector_table:\n" ++
        " .long 0x20004000 - 4 // sp top of 16KB ram\n" ++
        " .long mission" ++ mission_string ++ "_main\n" ++
        \\ .long lib00_exceptionNumber02
        \\ .long lib00_exceptionNumber03
        \\ .long lib00_exceptionNumber04
        \\ .long lib00_exceptionNumber05
        \\ .long lib00_exceptionNumber06
        \\ .long lib00_exceptionNumber07
        \\ .long lib00_exceptionNumber08
        \\ .long lib00_exceptionNumber09
        \\ .long lib00_exceptionNumber10
        \\ .long lib00_exceptionNumber11
        \\ .long lib00_exceptionNumber12
        \\ .long lib00_exceptionNumber13
        \\ .long lib00_exceptionNumber14
        \\ .long lib00_exceptionNumber15
    ;
}

fn uart_logBytes(context: void, bytes: []const u8) error{}!void {
    Uart.writeText(bytes);
}

export fn lib00_exceptionNumber01() noreturn {
    Exceptions.handle(01);
}

export fn lib00_exceptionNumber02() noreturn {
    Exceptions.handle(02);
}

export fn lib00_exceptionNumber03() noreturn {
    Exceptions.handle(03);
}

export fn lib00_exceptionNumber04() noreturn {
    Exceptions.handle(04);
}

export fn lib00_exceptionNumber05() noreturn {
    Exceptions.handle(05);
}

export fn lib00_exceptionNumber06() noreturn {
    Exceptions.handle(06);
}

export fn lib00_exceptionNumber07() noreturn {
    Exceptions.handle(07);
}

export fn lib00_exceptionNumber08() noreturn {
    Exceptions.handle(08);
}

export fn lib00_exceptionNumber09() noreturn {
    Exceptions.handle(09);
}

export fn lib00_exceptionNumber10() noreturn {
    Exceptions.handle(10);
}

export fn lib00_exceptionNumber11() noreturn {
    Exceptions.handle(11);
}

export fn lib00_exceptionNumber12() noreturn {
    Exceptions.handle(12);
}

export fn lib00_exceptionNumber13() noreturn {
    Exceptions.handle(13);
}

export fn lib00_exceptionNumber14() noreturn {
    Exceptions.handle(14);
}

export fn lib00_exceptionNumber15() noreturn {
    Exceptions.handle(15);
}

const builtin = @import("builtin");
const fmt = std.fmt;
const literal = Uart.literal;
const std = @import("std");

extern var __bss_start: u8;
extern var __bss_end: u8;

pub const log = Uart.log;
pub const ram_u32 = @intToPtr(*volatile [4096]u32, 0x20000000);
pub const Timer0 = TimerInstance(0x40008000);
pub const Timer1 = TimerInstance(0x40009000);
pub const Timer2 = TimerInstance(0x4000a000);
