export fn main() noreturn {
    setBssToZero();
    ClockManagement.startHfClock();
    uart.init();

    cycle_activity.init();
    keyboard_activity.init();
    led_matrix_activity.init();
    local_button_activity.init();
    radio_activity.init();
    remote_button_activity.init();
    status_activity.init();

    while (true) {
        cycle_activity.update();
        keyboard_activity.update();
        led_matrix_activity.update();
        local_button_activity.update();
        radio_activity.update();
        remote_button_activity.update();
        status_activity.update();
    }
}

fn exceptionHandler(exception_number: u32) noreturn {
    panicf("exception number {} ... now idle in arm exception handler", exception_number);
}

pub fn panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
    panicf("main.zig pub fn panic(): {}", message);
}

var already_panicking: bool = false;
fn panicf(comptime format: []const u8, args: ...) noreturn {
    @setCold(true);
    if (already_panicking) {
        hangf("\npanicked during kernel panic");
    }
    already_panicking = true;

    log("\npanic: " ++ format, args);
    hangf("panic completed");
}

fn hangf(comptime format: []const u8, args: ...) noreturn {
    log(format, args);
    uart.drainTxQueue();
    while (true) {
        asm volatile("wfe");
    }
}

// supplied by linker.ld
extern var __bss_start: u8;
extern var __bss_end: u8;

fn setBssToZero() void {
    @memset(@ptrCast(*volatile [1]u8, &__bss_start), 0, @ptrToInt(&__bss_end) - @ptrToInt(&__bss_start));
}

fn io(address: u32, comptime StructType: type) *volatile StructType {
    return @intToPtr(*volatile StructType, address);
}

const RemoteButtonActivity = struct {
    broadcaster_index: u32,

    fn init(self: *Self) void {
        self.broadcaster_index = 0;
    }

    fn update(self: *Self) void {
        if (radio_activity.broadcasters.len > 0) {
            self.broadcaster_index += 1;
            if (self.broadcaster_index >= radio_activity.broadcasters.len) {
                self.broadcaster_index = 0;
            }
            if (radio_activity.broadcasters[self.broadcaster_index].getToggledButton()) |b| {
                log("button {} {}", b.index, if (b.is_pressed) "pressed" else "released");
            }
        }
    }

    const Self = @This();
};

const RemoteButton = struct {
    index: u32,
    is_pressed: bool,

    fn new(index: u32, is_pressed: bool) Self {
        var self: Self = undefined;
        self.index = index;
        self.is_pressed = is_pressed;
        return self;
    }

    const Self = @This();
};

const LocalButtonActivity = struct {
    buttons: [2]Button,
    toggle_history: [22]u8,
    toggle_history_count: u16,
    toggle_history_count_overflowed: bool,
    toggle_history_mask: u8,
    toggle_history_offset: u32,

    fn init(self: *Self) void {
        for (self.buttons) |*b, i| {
            b.init(i);
        }
        mem.set(u8, &self.toggle_history, 0);
        self.toggle_history_count = 0;
        self.toggle_history_count_overflowed = false;
        self.toggle_history_mask = 0x80;
        self.toggle_history_offset = 0;
        self.update();
    }

    fn update(self: *Self) void {
        for (self.buttons) |*button| {
            button.update();
        }
    }

    fn updateToggleHistory(self: *Self, index: u32) void {
        const masked = self.toggle_history[self.toggle_history_offset] & ~self.toggle_history_mask;
        self.toggle_history[self.toggle_history_offset] = masked | if (index == 0) 0 else self.toggle_history_mask;
        self.toggle_history_mask >>= 1;
        if (self.toggle_history_mask == 0) {
            self.toggle_history_mask = 0x80;
            self.toggle_history_offset = (self.toggle_history_offset + 1) % self.toggle_history.len;
        }
        self.toggle_history_count +%= 1;
        if (self.toggle_history_count == 0) {
           self.toggle_history_count_overflowed = true;
        }
    }

    const Button = struct {
        down_count: u32,
        index: u32,
        is_pressed: bool,
        is_simulation_pressed: bool,
        pin_number: u32,
        up_count: u32,

        fn init(self: *Button, index: u32) void {
            self.down_count = 0;
            self.index = index;
            self.is_simulation_pressed = false;
            self.up_count = 0;
            if (index == 0) {
                self.pin_number = 17;
                Gpio.cnf_registers.cnf17 = 0;
            } else if (index == 1) {
                self.pin_number = 26;
                Gpio.cnf_registers.cnf26 = 0;
            }
            self.update();
        }

        fn update(self: *Button) void {
            const new = Gpio.registers.in & @as(u32, 1) << @truncate(u5, self.pin_number) == 0 or self.is_simulation_pressed;
            if (new != self.is_pressed) {
                self.is_pressed = new;
                if (self.is_pressed) {
                    self.down_count += 1;
                } else {
                    self.up_count += 1;
                }
                local_button_activity.updateToggleHistory(self.index);
            }
        }

        fn string(self: *Button) []u8 {
            return if (self.is_pressed) &"pressed " else &"released";
        }
    };

    const Self = @This();
};

const Uart = struct {
    tx_busy: bool,
    tx_queue: [3]u8,
    tx_queue_read: usize,
    tx_queue_write: usize,

    fn init(self: *Self) void {
        const uart_rx_pin = 25;
        const uart_tx_pin = 24;
        Gpio.registers.direction_set = 1 << uart_tx_pin;
        Self.registers.pin_select_rxd = uart_rx_pin;
        Self.registers.pin_select_txd = uart_tx_pin;
        Self.registers.enable = 0x04;
        Self.tasks.start_rx = 1;
        Self.tasks.start_tx = 1;
        self.tx_busy = false;
        self.tx_queue_read = 0;
        self.tx_queue_write = 0;
    }

    fn isReadByteReady(self: Self) bool {
        return Self.events.rx_ready == 1;
    }

    fn readByte(self: *Self) u8 {
        Self.events.rx_ready = 0;
        return @truncate(u8, Self.registers.rxd);
    }

    fn writeByteBlocking(self: *Self, byte: u8) void {
        const next = (self.tx_queue_write + 1) % self.tx_queue.len;
        while (next == self.tx_queue_read) {
            self.loadTxd();
        }
        self.tx_queue[self.tx_queue_write] = byte;
        self.tx_queue_write = next;
        self.loadTxd();
    }

    fn drainTxQueue(self: *Self) void {
        while (self.tx_queue_read != self.tx_queue_write) {
            self.loadTxd();
        }
    }

    fn loadTxd(self: *Self) void {
        if (self.tx_queue_read != self.tx_queue_write and (!self.tx_busy or Self.events.tx_ready == 1)) {
            Self.events.tx_ready = 0;
            Self.registers.txd = self.tx_queue[self.tx_queue_read];
            self.tx_queue_read = (self.tx_queue_read + 1) % self.tx_queue.len;
            self.tx_busy = true;
        }
    }

    fn writeText(self: *Self, buffer: []const u8) void {
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

    fn literal(self: *Self, comptime format: []const u8, args: ...) void {
        fmt.format({}, NoError, uart_logBytes, format, args) catch |e| switch (e) {};
    }

    fn log(self: *Self, comptime format: []const u8, args: ...) void {
        self.literal(format ++ "\n", args);
    }

    const error_registers = io(0x40002480,
        struct {
            error_source: u32,
        }
    );

    const events = io(0x40002108,
        struct {
            rx_ready: u32,
            unused0x10c: u32,
            unused0x110: u32,
            unused0x114: u32,
            unused0x118: u32,
            tx_ready: u32,
            unused0x120: u32,
            error_detected: u32,
        }
    );

   const registers = io(0x40002500,
        struct {
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
        }
    );

    const Self = @This();

    const tasks = io(0x40002000,
        struct {
            start_rx: u32,
            stop_rx: u32,
            start_tx: u32,
            stop_tx: u32,
        }
    );
};

fn uart_logBytes(context: void, bytes: []const u8) NoError!void {
    uart.writeText(bytes);
}

const Gpio = struct {
    const cnf_registers = io(0x50000700,
        struct {
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
        }
    );

    const registers = io(0x50000504,
        struct {
            out: u32,
            out_set: u32,
            out_clear: u32,
            in: u32,
            direction: u32,
            direction_set: u32,
            direction_clear: u32,
        }
    );
};

const Rng = struct {
    fn init() void {
        Self.registers.config = 0x1;
        Self.tasks.start = 1;
    }

    const events = io(0x4000d100,
        struct {
            value_ready: u32,
        }
    );

    const registers = io(0x4000d504,
        struct {
            config: u32,
            value: u32,
        }
    );

    const tasks = io(0x4000d000,
        struct {
            start: u32,
            stop: u32,
        }
    );
};

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

const Terminal = struct {
    fn restoreInputLine(self: *Self) void {
        self.move(99, keyboard_activity.column);
    }

    fn line(self: *Self, comptime format: []const u8, args: ...) void {
        literal(format, args);
        self.pair(0, 0, "K");
        literal("\r\n");
    }

    fn clearScreen(self: *Self) void {
        self.pair(2, 0, "J");
    }

    fn setScrollingRegion(self: *Self, top: u32, bottom: u32) void {
        self.pair(top, bottom, "r");
    }

    fn move(self: *Self, row: u32, column: u32) void {
        self.pair(row, column, "H");
    }

    fn hideCursor(self: *Self, ) void {
        literal(Self.csi ++ "?25l");
    }

    fn reportCursorPosition(self: *Self) void {
        literal(Self.csi ++ "6n");
    }

    fn showCursor(self: *Self) void {
        literal(Self.csi ++ "?25h");
    }

    fn saveCursor(self: *Self) void {
        self.pair(0, 0, "s");
    }

    fn restoreCursor(self: *Self) void {
        self.pair(0, 0, "u");
    }

    fn pair(self: *Self, a: u32, b: u32, letter: []const u8) void {
        if (a <= 1 and b <= 1) {
            literal("{}{}", Self.csi, letter);
        } else if (b <= 1) {
            literal("{}{}{}", Self.csi, a, letter);
        } else if (a <= 1) {
            literal("{};{}{}", Self.csi, b, letter);
        } else {
            literal("{}{};{}{}", Self.csi, a, b, letter);
        }
    }

    const csi = "\x1b[";
    const Self = @This();
};

const Ficr = struct {
    const radio = io(0x100000a0,
        struct {
            device_address_type: u32,
            device_address0: u32,
            device_address1: u32,
        }
    );
};

const ClockManagement = struct {
    fn startHfClock() void {
        ClockManagement.crystal_registers.frequency_selector = 0xff;
        ClockManagement.tasks.start_hf_clock = 1;
        while (ClockManagement.events.hf_clock_started == 0) {
        }
    }

    const crystal_registers = io(0x40000550,
        struct {
            frequency_selector: u32,
        }
    );
    const events = io(0x40000100,
        struct {
            hf_clock_started: u32,
            lf_clock_started: u32,
        }
    );
    const tasks = io(0x40000000,
        struct {
            start_hf_clock: u32,
            stop_hf_clock: u32,
            start_lf_clock: u32,
            stop_lf_clock: u32,
        }
    );
};

const broadcasters_max_len = 40;
const RadioActivity = struct {
    broadcasters: []Broadcaster,
    broadcasters_buf: [broadcasters_max_len]Broadcaster,
    channel: u32,
    crc_error_count: u32,
    is_receiving: bool,
    rx_count: u32,
    toggle_history_count_published: u16,
    tx_count: u32,
    rx_packet_buffer: [254]u8,
    tx_packet_buffer: [254]u8,

    const Broadcaster = struct {
        key: []u8,
        key_count: u32,
        value: []u8,
        value_count: u32,
        buffer: [1 + 6 + 31]u8,
        buttons_is_pressed: [2]bool,
        processed_toggle_history_count: u16,
        processed_toggle_history_offset: u32,
        processed_toggle_history_mask: u32,

        fn init(self: *Broadcaster) void {
            self.buttons_is_pressed[0] = false;
            self.buttons_is_pressed[1] = false;
            self.processed_toggle_history_count = 0;
            self.processed_toggle_history_offset = 0;
            self.processed_toggle_history_mask = 0x80;
        }

        fn isTwoButtonBeacon(self: *Broadcaster) bool {
            return self.value[0] == 0x1e and self.value[1] == 0xff and self.value[2] == 0xff and self.value[3] == 0xff and self.value[4] == 0x3a and self.value[5] == 0xb9;
        }

        fn toggleHistoryCount(self: *Broadcaster) u16 {
           return @as(u16, self.value[8]) << 8 | self.value[7];
        }

        fn getToggledButton(self: *Broadcaster) ?RemoteButton {
            if (self.isTwoButtonBeacon() and self.toggleHistoryCount() != self.processed_toggle_history_count) {
                const index = if (self.value[9 + self.processed_toggle_history_offset] & self.processed_toggle_history_mask == 0) @as(u32, 0) else 1;
                const is_pressed = !self.buttons_is_pressed[index];
                self.buttons_is_pressed[index] = is_pressed;
                const remote_button = RemoteButton.new(index, is_pressed);
                self.processed_toggle_history_count +%= 1;
                self.processed_toggle_history_mask >>= 1;
                if (self.processed_toggle_history_mask == 0) {
                    self.processed_toggle_history_mask = 0x80;
                    self.processed_toggle_history_offset += 1;
                    if (self.processed_toggle_history_offset == local_button_activity.toggle_history.len) {
                        self.processed_toggle_history_offset = 0;
                    }
                }
                return remote_button;
            } else {
                return null;
            }
        }
    };

    fn init(self: *Self) void {
        self.toggle_history_count_published = 0;
        self.broadcasters = self.broadcasters_buf[0..0];
        self.channel = 37;
        Self.registers.frequency = self.channelToFrequency(self.channel);
        Self.registers.datawhiteiv = self.channel;
        Self.registers.crc_config = 0x103;
        Self.registers.crc_poly = 0x65b;
        Self.registers.crc_init = 0x555555;
        Self.registers.mode = 0x3;
        Self.registers.pcnf0 = 0x00020106;
        Self.registers.pcnf1 = 0x02030000 | 37;
        const access_address = 0x8e89bed6;
        Self.registers.prefix0 = access_address >> 24 & 0xff;
        Self.registers.base0 = access_address << 8 & 0xffffff00;
        Self.registers.rx_addresses = 0x01;
        Self.registers.tx_address = 0x0;
        Self.registers.tx_power = 0;
        self.crc_error_count = 0;
        for (self.tx_packet_buffer) |_, i| {
            self.tx_packet_buffer[i] = 0;
        }
        self.tx_packet_buffer[0] = 0x40;
        self.tx_packet_buffer[1] = 37;
        self.tx_packet_buffer[2] = 0x0;
        self.tx_packet_buffer[3 + 0] = 0x0;
        self.tx_packet_buffer[3 + 1] = 0x0;
        self.tx_packet_buffer[3 + 2] = 0x0;
        self.tx_packet_buffer[3 + 3] = 0x0;
        self.tx_packet_buffer[3 + 4] = 0x0;
        self.tx_packet_buffer[3 + 5] = 0x0;
        self.tx_packet_buffer[3 + 6 + 0] = 0x1e;
        self.tx_packet_buffer[3 + 6 + 1] = 0xff;
        self.tx_packet_buffer[3 + 6 + 2] = 0xff;
        self.tx_packet_buffer[3 + 6 + 3] = 0xff;
        self.tx_packet_buffer[3 + 6 + 4] = 0x3a;
        self.tx_packet_buffer[3 + 6 + 5] = 0xb9;
        self.rx_count = 0;
        self.tx_count = 0;
        self.is_receiving = true;
        self.enable();
    }

    fn enable(self: *Self) void {
        self.channel += 1;
        if (self.channel > 39) {
            self.channel = 37;
        }
        if (self.is_receiving) {
            Self.registers.packet_ptr = @ptrToInt(&self.rx_packet_buffer);
            Self.short_cuts.shorts = 0x03;
            Self.tasks.rx_enable = 1;
        } else {
            if (local_button_activity.toggle_history_count != self.toggle_history_count_published) {
                self.toggle_history_count_published = local_button_activity.toggle_history_count;
                self.tx_packet_buffer[15] = (if (local_button_activity.toggle_history_count_overflowed) @as(u8, 0x1) else 0) | (if (local_button_activity.buttons[0].is_pressed) @as(u8, 0x2) else 0) | (if (local_button_activity.buttons[1].is_pressed) @as(u8, 0x4) else 0);
                self.tx_packet_buffer[16] = @truncate(u8, local_button_activity.toggle_history_count);
                self.tx_packet_buffer[17] = @truncate(u8, (local_button_activity.toggle_history_count & 0xff00) >> 8);
                mem.copy(u8, self.tx_packet_buffer[18..], &local_button_activity.toggle_history);
            }
            Self.registers.packet_ptr = @ptrToInt(&self.tx_packet_buffer);
            Self.short_cuts.shorts = 0x03;
            Self.tasks.tx_enable = 1;
        }
    }

    fn reverseAddress(self: *Self, address: []u8) void {
        var x: u8 = undefined;
        x = address[0];
        address[0] = address[5];
        address[5] = x;
        x = address[1];
        address[1] = address[4];
        address[4] = x;
        x = address[2];
        address[2] = address[3];
        address[3] = x;
    }

    fn channelToFrequency(self: *Self, channel: u32) u32 {
        return if (channel == 37)
            @as(u32, 2)
        else if (channel == 38)
            26
        else if (channel == 39)
            80
        else if (channel <= 10)
            channel * 2 + 4
        else
            channel * 2 + 6;
    }

    fn update(self: *Self) void {
        if (Self.events.disabled == 1) {
            Self.events.disabled = 0;
            defer self.enable();
            if (!self.is_receiving) {
                self.tx_count += 1;
                self.is_receiving = true;
                return;
            }
            if (Self.rx_registers.crc_status != 1) {
                self.crc_error_count += 1;
                return;
            }
            self.rx_count += 1;
            if (self.rx_count % 2 == 0) {
                self.is_receiving = false;
            }
            const s0 = self.rx_packet_buffer[0];
            const pdu_type = s0 & 0xf;
            const payload_len = self.rx_packet_buffer[1];
            if (payload_len > 37) {
                return;
            }
            const s1 = self.rx_packet_buffer[2];
            var rest = self.rx_packet_buffer[3..3 + payload_len];
            if (pdu_type <= 0x6 and rest.len >= 7) {
                const txrnd = if (s0 & 0x40 != 0) "p" else "r";
                var tx_address = rest[0..6];
                self.reverseAddress(tx_address);
                rest = rest[6..];
                if ((pdu_type == 0x1 or pdu_type == 0x3) and rest.len >= 6) {
                    const rxrnd = if (s0 & 0x80 != 0) "p" else "r";
                    const rx_address = rest[0..6];
                    self.reverseAddress(rx_address);
                    rest = rest[6..];
                } else {
                    const new_key = [_]u8{ s0, tx_address[0], tx_address[1], tx_address[2], tx_address[3], tx_address[4], tx_address[5]};
                    var found = false;
                    for (self.broadcasters) |*b, i| {
                        if (mem.eql(u8, &new_key, b.key)) {
                            found = true;
                            if (!mem.eql(u8, rest, b.value)) {
                                b.key_count += 1;
                                b.value_count = 1;
                                b.value = b.buffer[7 .. 7 + rest.len];
                                mem.copy(u8, b.value, rest);
                            } else {
                                b.key_count += 1;
                                b.value_count += 1;
                            }
                            break;
                        }
                    }
                    if (!found) {
                        const i = self.broadcasters.len;
                        if (i < self.broadcasters_buf.len) {
                            self.broadcasters = self.broadcasters_buf[0 .. i + 1];
                            var b = &self.broadcasters[i];   
                            b.init();
                            b.key = b.buffer[0 .. 7];
                            mem.copy(u8, b.key, &new_key);
                            b.key_count = 1;
                            b.value = b.buffer[7 .. 7 + rest.len];
                            mem.copy(u8, b.value, rest);
                            b.value_count = 1;
                        } else {
//                          log("{x} no room {}", new_key, i);
                        }
                    }
                }
            }
        }
    }

    const events = io(0x40001100,
        struct {
            ready: u32,
            address_completed: u32,
            payload_completed: u32,
            packet_completed: u32,
            disabled: u32,
        }
    );

    const registers = io(0x40001504,
        struct {
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
        }
    );

    const rx_registers = io(0x40001400,
        struct {
            crc_status: u32,
            unused0x404: u32,
            unused0x408: u32,
            rx_crc: u32,
        }
    );

    const Self = @This();

    const short_cuts = io(0x40001200,
        struct {
            shorts: u32,
        }
    );

    const tasks = io(0x40001000,
        struct {
            tx_enable: u32,
            rx_enable: u32,
            start: u32,
            stop: u32,
            disable: u32,
        }
    );
};

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
        Timer0.registers.mode = 0x0;
        Timer0.registers.bit_mode = 0x3;
        Timer0.registers.prescaler = 4;
        Timer0.tasks.start = 1;
        timer0.start(5*1000);
    }

    fn update(self: *CycleActivity) void {
        self.cycle_counter += 1;
        const new_cycle_start = timer0.capture();
        if (new_cycle_start -% self.last_second_ticks >= 1000*1000) {
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

const LedMatrixActivity = struct {
    scan_lines: [3]u32,
    scan_lines_index: u32,

    fn drawZigIcon(self: *Self) void {
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

    fn init(self: *Self) void {
        Gpio.registers.direction_set = Self.all_led_pins_mask;
        for (self.scan_lines) |_, i| {
             self.scan_lines[i] = Self.row_1 << @truncate(u5, i) | Self.all_led_cols_mask;
        }
        self.scan_lines_index = 0;
        led_matrix_activity.drawZigIcon();
    }

    fn update(self: *Self) void {
        if (timer0.isFinished()) {
            Gpio.registers.out = Gpio.registers.out & ~Self.all_led_pins_mask | self.scan_lines[self.scan_lines_index];
            self.scan_lines_index = (self.scan_lines_index + 1) % self.scan_lines.len;
            timer0.restart();
        }
    }

    fn setPixel(self: *Self, x: u32, y: u32, v: u32) void {
        const n = 5 * y + x;
        const full_mask = led_pins_masks[n];
        const col_mask = full_mask & Self.all_led_cols_mask;
        const row_mask = full_mask & Self.all_led_rows_mask;
        const selected_scan_line_index = if (row_mask == Self.row_1) @as(u32, 0) else if (row_mask == Self.row_2) @as(u32, 1) else 2;
        self.scan_lines[selected_scan_line_index] = self.scan_lines[selected_scan_line_index] & ~col_mask | if (v == 0) col_mask else 0; 
    }

    const all_led_rows_mask: u32 = 0xe000;
    const all_led_cols_mask: u32 = 0x1ff0;
    const all_led_pins_mask = Self.all_led_rows_mask | Self.all_led_cols_mask;
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
         Self.row_1 | Self.col_1,
         Self.row_2 | Self.col_4,
         Self.row_1 | Self.col_2,
         Self.row_2 | Self.col_5,
         Self.row_1 | Self.col_3,

         Self.row_3 | Self.col_4,
         Self.row_3 | Self.col_5,
         Self.row_3 | Self.col_6,
         Self.row_3 | Self.col_7,
         Self.row_3 | Self.col_8,

         Self.row_2 | Self.col_2,
         Self.row_1 | Self.col_9,
         Self.row_2 | Self.col_3,
         Self.row_3 | Self.col_9,
         Self.row_2 | Self.col_1,

         Self.row_1 | Self.col_8,
         Self.row_1 | Self.col_7,
         Self.row_1 | Self.col_6,
         Self.row_1 | Self.col_5,
         Self.row_1 | Self.col_4,

         Self.row_3 | Self.col_3,
         Self.row_2 | Self.col_7,
         Self.row_3 | Self.col_1,
         Self.row_2 | Self.col_6,
         Self.row_3 | Self.col_2,
    };
    const row_1: u32 = 0x2000;
    const row_2 = 0x4000;
    const row_3 = 0x8000;
    const Self = @This();
};

const KeyboardActivity = struct {
    column: u32,

    fn init(self: *Self) void {
        self.column = 1;
    }

    fn update(self: *Self) void {
        if (!uart.isReadByteReady()) {
            return;
        }
        const byte = uart.readByte();
        switch (byte) {
            27 => {
                uart.writeByteBlocking('$');
                self.column += 1;
            },
            'a' => {
                local_button_activity.buttons[0].is_simulation_pressed = !local_button_activity.buttons[0].is_simulation_pressed;
            },
            'b' => {
                local_button_activity.buttons[1].is_simulation_pressed = !local_button_activity.buttons[1].is_simulation_pressed;
            },
            12, '-' => {
                status_activity.redraw();
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

    const Self = @This();
};

const StatusActivity = struct {
    prev_now: u32,

    fn init(self: *Self) void {
        self.prev_now = cycle_activity.up_time_seconds;
        self.redraw();
    }

    fn redraw(self: *Self) void {
        term.move(999, 999);
        term.clearScreen();
        term.setScrollingRegion(5, 99);
        term.move(5, 1);
        log("keyboard input will be echoed below:");
    }

    fn update (self: *Self) void {
        uart.loadTxd();
        const now = cycle_activity.up_time_seconds;
        if (now >= self.prev_now + 1) {
            term.hideCursor();
            term.move(1, 1);
            term.line("up {:3}s cycle {}us max {}us", cycle_activity.up_time_seconds, cycle_activity.cycle_time, cycle_activity.max_cycle_time);
            term.line("gpio.in {x:8}", Gpio.registers.in & ~@as(u32, 0x0300fff0));
            term.line("ble tx {} rx ok {} crc errors {} frequency {} addr type {x} 0x{x}{x}", radio_activity.tx_count, radio_activity.rx_count, radio_activity.crc_error_count, RadioActivity.registers.frequency + 2400, Ficr.radio.device_address_type & 1, Ficr.radio.device_address1 & 0xffff, Ficr.radio.device_address0);
            term.showCursor();
            term.restoreInputLine();
            self.prev_now = now;
        }
    }

    const Self = @This();
};

const Timer0 = struct {
    duration: u32,
    start_time: u32,

    fn capture(self: *Self) u32 {
        Self.capture_tasks.capture0 = 1;
        return Self.capture_registers.capture_compare0;
    }

    fn restart(self: *Self) void {
        self.start_time = self.capture();
    }

    fn start(self: *Self, n: u32) void {
        self.duration = n;
        self.restart();
    }

    fn isFinished(self: *Self) bool {
        const now = self.capture();
        return now -% self.start_time >= self.duration;
    }

    const capture_registers = io(0x40008540,
        struct {
            capture_compare0: u32,
        }
    );

    const capture_tasks = io(0x40008040,
        struct {
            capture0: u32,
        }
    );

    const registers = io(0x40008504,
        struct {
            mode: u32,
            bit_mode: u32,
            unused0x50c: u32,
            prescaler: u32,
        }
    );

    const Self = @This();

    const tasks = io(0x40008000,
        struct {
            start: u32,
            stop: u32,
            count: u32,
        }
    );
};

var cycle_activity: CycleActivity = undefined;
var gpio: Gpio = undefined;
var keyboard_activity: KeyboardActivity = undefined;
var led_matrix_activity: LedMatrixActivity = undefined;
var local_button_activity: LocalButtonActivity = undefined;
var radio_activity: RadioActivity = undefined;
var remote_button_activity: RemoteButtonActivity = undefined;
var rng: Rng = undefined;
var status_activity: StatusActivity = undefined;
var term: Terminal = undefined;
var timer0: Timer0 = undefined;
var uart: Uart = undefined;

const builtin = @import("builtin");
const fmt = std.fmt;
const literal = uart.literal;
const log = uart.log;
const math = std.math;
const mem = std.mem;
const name = "zig-bare-metal-microbit";
const NoError = error{};
const release_tag = "0.3";
const std = @import("std");
