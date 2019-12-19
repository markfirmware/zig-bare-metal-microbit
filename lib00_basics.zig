pub const Bss = struct {
    pub fn prepare() void {
        @memset(@ptrCast(*volatile [1]u8, &__bss_start), 0, @ptrToInt(&__bss_end) - @ptrToInt(&__bss_start));
    }
};

pub const ClockManagement = struct {
    const events = io(0x40000100, struct {
        hf_clock_started: u32,
        lf_clock_started: u32,
    });

    pub fn prepareHf() void {
        ClockManagement.crystal_registers.frequency_selector = 0xff;
        ClockManagement.tasks.start_hf_clock = 1;
        while (ClockManagement.events.hf_clock_started == 0) {}
    }

    const crystal_registers = io(0x40000550, struct {
        frequency_selector: u32,
    });

    const tasks = io(0x40000000, struct {
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
    const radio = io(0x100000a0, struct {
        device_address_type: u32,
        device_address0: u32,
        device_address1: u32,
    });
};

pub const Gpio = struct {
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

    pub const registers = io(0x50000504, struct {
        out: u32,
        out_set: u32,
        out_clear: u32,
        in: u32,
        direction: u32,
        direction_set: u32,
        direction_clear: u32,
    });
};

pub const Gpiote = struct {
    const config_registers = io(0x40006510, struct {
        config0: u32,
    });

    const tasks = io(0x40006000, struct {
        out0: u32,
    });
};

pub const Ppi = struct {
    const registers = io(0x4001f500, struct {
        channel_enable: u32,
        channel_enable_set: u32,
        channel_enable_clear: u32,
        unused0x50c: u32,
        channel0_event_end_point: u32,
        channel0_task_end_point: u32,
        channel1_event_end_point: u32,
        channel1_task_end_point: u32,
    });
};

pub const Rng = struct {
    pub fn prepare() void {
        Rng.registers.config = 0x1;
        Rng.tasks.start = 1;
    }

    const events = io(0x4000d100, struct {
        value_ready: u32,
    });

    const registers = io(0x4000d504, struct {
        config: u32,
        value: u32,
    });

    const tasks = io(0x4000d000, struct {
        start: u32,
        stop: u32,
    });
};

pub const Terminal = struct {
    pub fn clearScreen() void {
        Terminal.pair(2, 0, "J");
    }

    pub fn hideCursor() void {
        Uart.writeText(Terminal.csi ++ "?25l");
    }

    pub fn line(comptime format: []const u8, args: var) void {
        literal(format, args);
        Terminal.pair(0, 0, "K");
        Uart.writeText("\n");
    }

    pub fn move(row: u32, column: u32) void {
        Terminal.pair(row, column, "H");
    }

    pub fn pair(a: u32, b: u32, letter: []const u8) void {
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

    pub fn reportCursorPosition() void {
        Uart.writeText("{}", .{Terminal.csi ++ "6n"});
    }

    pub fn restoreCursor() void {
        Terminal.pair(0, 0, "u");
    }

    pub fn saveCursor() void {
        Terminal.pair(0, 0, "s");
    }

    pub fn setScrollingRegion(top: u32, bottom: u32) void {
        Terminal.pair(top, bottom, "r");
    }

    pub fn showCursor() void {
        Uart.writeText(Terminal.csi ++ "?25h");
    }

    const csi = "\x1b[";
};

pub const TimeKeeper = struct {
    duration: u32,
    start_time: u32,

    fn capture(self: *TimeKeeper) u32 {
        Timer0.capture_tasks.capture0 = 1;
        return Timer0.capture_compare_registers.cc0;
    }

    fn prepare(self: *TimeKeeper, duration: u32) void {
        self.duration = duration;
        self.reset();
    }

    fn isFinished(self: *TimeKeeper) bool {
        return self.capture() -% self.start_time >= self.duration;
    }

    fn reset(self: *TimeKeeper) void {
        self.start_time = self.capture();
    }
};

pub const Timer0 = TimerInstance(0x40008000);
pub const Timer1 = TimerInstance(0x40009000);
pub const Timer2 = TimerInstance(0x4000a000);

pub fn TimerInstance(instance_address: u32) type {
    return struct {
        pub fn capture() u32 {
            Timer.capture_tasks.capture0 = 1;
            return Timer.capture_compare_registers.cc0;
        }

        pub fn prepare() void {
            Timer.registers.mode = 0x0;
            //panic invalid width
            //panic invalid frequency
            Timer.registers.bit_mode = if (instance_address == 0x40008000) @as(u32, 0x3) else 0x0;
            Timer.registers.prescaler = if (instance_address == 0x40008000) @as(u32, 4) else 9;
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

pub const Uart = struct {
    tx_busy: bool,
    tx_queue: [3]u8,
    tx_queue_read: usize,
    tx_queue_write: usize,

    pub fn drainTxQueue() void {
        while (uart_singleton.tx_queue_read != uart_singleton.tx_queue_write) {
            Uart.loadTxd();
        }
    }

    pub fn prepare() void {
        const uart_rx_pin = 25;
        const uart_tx_pin = 24;
        Gpio.registers.direction_set = 1 << uart_tx_pin;
        Uart.registers.pin_select_rxd = uart_rx_pin;
        Uart.registers.pin_select_txd = uart_tx_pin;
        Uart.registers.enable = 0x04;
        Uart.tasks.start_rx = 1;
        Uart.tasks.start_tx = 1;
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
            Uart.events.tx_ready = 0;
            Uart.registers.txd = uart_singleton.tx_queue[uart_singleton.tx_queue_read];
            uart_singleton.tx_queue_read = (uart_singleton.tx_queue_read + 1) % uart_singleton.tx_queue.len;
            uart_singleton.tx_busy = true;
        }
    }

    pub fn log(comptime format: []const u8, args: var) void {
        Uart.literal(format ++ "\n", args);
    }

    pub fn readByte() u8 {
        Uart.events.rx_ready = 0;
        return @truncate(u8, Uart.registers.rxd);
    }

    pub fn update() void {
        Uart.loadTxd();
    }

    pub fn writeByteBlocking(byte: u8) void {
        const next = (uart_singleton.tx_queue_write + 1) % uart_singleton.tx_queue.len;
        while (next == uart_singleton.tx_queue_read) {
            Uart.loadTxd();
        }
        uart_singleton.tx_queue[uart_singleton.tx_queue_write] = byte;
        uart_singleton.tx_queue_write = next;
        Uart.loadTxd();
    }

    pub fn writeText(buffer: []const u8) void {
        for (buffer) |c| {
            switch (c) {
                '\n' => {
                    Uart.writeByteBlocking('\r');
                    Uart.writeByteBlocking('\n');
                },
                else => Uart.writeByteBlocking(c),
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

pub fn delayMicroseconds(n: u32) void {
    const start = timer0.capture();
    while (timer0.capture() -% start < n) {}
}

pub fn exceptionHandler(exception_number: u32) noreturn {
    panicf("exception number {} ... now idle in arm exception handler", .{exception_number});
}

pub fn hangf(comptime format: []const u8, args: var) noreturn {
    log(format, args);
    Uart.drainTxQueue();
    while (true) {
        asm volatile ("wfe");
    }
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

var uart_singleton: Uart = undefined;

pub var already_panicking: bool = undefined;
