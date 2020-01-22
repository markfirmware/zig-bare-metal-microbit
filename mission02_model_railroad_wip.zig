export fn mission02_main() noreturn {
    Bss.prepare();
    ClockManagement.prepareHf();
    Uart.prepare();
    Timer0.prepare();
    Timer1.prepare();
    Timer2.prepare();
    LedMatrix.prepare();

    cycle_activity.prepare();
    keyboard_activity.prepare();
    local_button_activity.prepare();
    radio_activity.prepare();
    remote_button_activity.prepare();
    status_activity.prepare();

    while (true) {
        cycle_activity.update();
        keyboard_activity.update();
        local_button_activity.update();
        radio_activity.update();
        remote_button_activity.update();
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
        LedMatrix.update();
        self.cycle_counter += 1;
        const new_cycle_start = Timer0.capture();
        if (self.up_timer.isFinished()) {
            self.up_timer.reset();
            self.up_time_seconds += 1;
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
            'a' => {
                local_button_activity.buttons[0].toggle();
                local_button_activity.buttons[0].toggle();
            },
            'b' => {
                local_button_activity.buttons[1].toggle();
                local_button_activity.buttons[1].toggle();
            },
            'c' => {
                local_button_activity.buttons[0].toggle();
                local_button_activity.buttons[1].toggle();
                local_button_activity.buttons[0].toggle();
                local_button_activity.buttons[1].toggle();
            },
            'A' => {
                local_button_activity.buttons[0].toggle();
            },
            'B' => {
                local_button_activity.buttons[1].toggle();
            },
            'r' => {
                local_button_activity.reset();
                radio_activity.encodeButtons();
            },
            12 => {
                self.column = 1;
                radio_activity.broadcasters = radio_activity.broadcasters_buf[0..0];
                status_activity.prev_led_image = 0;
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

const LocalButtonActivity = struct {
    buttons: [2]LocalButton,
    toggle_history: [22]u8,
    toggle_history_count: u16,
    toggle_history_count_overflowed: bool,
    toggle_history_mask: u8,
    toggle_history_offset: u32,

    fn prepare(self: *LocalButtonActivity) void {
        self.reset();
    }

    fn reset(self: *LocalButtonActivity) void {
        for (self.buttons) |*b, i| {
            b.prepare(i);
        }
        mem.set(u8, &self.toggle_history, 0);
        self.toggle_history_count = 0;
        self.toggle_history_count_overflowed = false;
        self.toggle_history_mask = 0x80;
        self.toggle_history_offset = 0;
        self.update();
    }

    fn update(self: *LocalButtonActivity) void {
        for (self.buttons) |*button| {
            button.update();
        }
    }

    fn updateToggleHistory(self: *LocalButtonActivity, index: u32) void {
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
        const is_pressed = self.buttons[index].is_pressed;
        const letter = if (!self.buttons[0].is_pressed and !self.buttons[1].is_pressed) "Z" else if (!is_pressed) " " else buttonName(index);
        LedMatrix.putChar(letter[0]);
    }

    const LocalButton = struct {
        down_count: u32,
        index: u32,
        is_pressed: bool,
        is_simulation_pressed: bool,
        mask: u32,
        up_count: u32,

        fn prepare(self: *LocalButton, index: u32) void {
            self.down_count = 0;
            self.index = index;
            self.is_pressed = false;
            self.is_simulation_pressed = false;
            self.up_count = 0;
            if (index == 0) {
                self.mask = Gpio.registers_masks.button_a_active_low;
            } else if (index == 1) {
                self.mask = Gpio.registers_masks.button_b_active_low;
            }
            Gpio.config[@ctz(u32, self.mask)] = Gpio.config_masks.input;
            self.update();
        }

        fn toggle(self: *LocalButton) void {
            self.is_simulation_pressed = !self.is_simulation_pressed;
            self.update();
        }

        fn update(self: *LocalButton) void {
            const new = Gpio.registers.in & self.mask == 0 or self.is_simulation_pressed;
            if (new != self.is_pressed) {
                self.is_pressed = new;
                if (self.is_pressed) {
                    self.down_count += 1;
                } else {
                    self.up_count += 1;
                }
                Terminal.attribute(if (self.index == 0) @as(u32, 31) else 32);
                log("local button {} {}", .{ buttonName(self.index), buttonStateString(self.is_pressed) });
                Terminal.attribute(0);
                local_button_activity.updateToggleHistory(self.index);
            }
        }
    };
};

const RadioActivity = struct {
    broadcasters: []Broadcaster,
    broadcasters_buf: [broadcasters_max_len]Broadcaster,
    channel: u32,
    crc_error_count: u32,
    is_receiving: bool,
    rx_count: u32,
    toggle_history_count_published: u16,
    tx_count: u32,
    rx_packet_buffer: [40]u8,
    tx_packet_buffer: [40]u8,

    fn channelToFrequency(self: *RadioActivity, channel: u32) u32 {
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

    fn enable(self: *RadioActivity) void {
        self.channel += 1;
        if (self.channel > 39) {
            self.channel = 37;
        }
        if (self.is_receiving) {
            Radio.registers.packet_ptr = @ptrToInt(&self.rx_packet_buffer);
            Radio.short_cuts.shorts = 0x03;
            Radio.tasks.rx_enable = 1;
        } else {
            if (local_button_activity.toggle_history_count != self.toggle_history_count_published) {
                self.encodeButtons();
            }
            Radio.registers.packet_ptr = @ptrToInt(&self.tx_packet_buffer);
            Radio.short_cuts.shorts = 0x03;
            Radio.tasks.tx_enable = 1;
        }
    }

    fn encodeButtons(self: *RadioActivity) void {
        self.toggle_history_count_published = local_button_activity.toggle_history_count;
        self.tx_packet_buffer[15] = (if (local_button_activity.toggle_history_count_overflowed) @as(u8, 0x1) else 0) | (if (local_button_activity.buttons[0].is_pressed) @as(u8, 0x2) else 0) | (if (local_button_activity.buttons[1].is_pressed) @as(u8, 0x4) else 0);
        self.tx_packet_buffer[16] = @truncate(u8, local_button_activity.toggle_history_count);
        self.tx_packet_buffer[17] = @truncate(u8, (local_button_activity.toggle_history_count & 0xff00) >> 8);
        mem.copy(u8, self.tx_packet_buffer[18..], &local_button_activity.toggle_history);
    }

    fn prepare(self: *RadioActivity) void {
        self.toggle_history_count_published = 0;
        self.broadcasters = self.broadcasters_buf[0..0];
        self.channel = 37;
        Radio.registers.frequency = self.channelToFrequency(self.channel);
        Radio.registers.datawhiteiv = self.channel;
        Radio.registers.crc_config = 0x103;
        Radio.registers.crc_poly = 0x65b;
        Radio.registers.crc_init = 0x555555;
        Radio.registers.mode = 0x3;
        Radio.registers.pcnf0 = 0x00020106;
        Radio.registers.pcnf1 = 0x02030000 | 37;
        const access_address = 0x8e89bed6;
        Radio.registers.prefix0 = access_address >> 24 & 0xff;
        Radio.registers.base0 = access_address << 8 & 0xffffff00;
        Radio.registers.rx_addresses = 0x01;
        Radio.registers.tx_address = 0x0;
        Radio.registers.tx_power = 0;
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

    fn reverseAddress(self: *RadioActivity, address: []u8) void {
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

    fn update(self: *RadioActivity) void {
        if (Radio.events.disabled == 1) {
            Radio.events.disabled = 0;
            defer self.enable();
            if (!self.is_receiving) {
                self.tx_count += 1;
                self.is_receiving = true;
                return;
            }
            if (Radio.rx_registers.crc_status != 1) {
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
            var rest = self.rx_packet_buffer[3 .. 3 + payload_len];
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
                    // log("ble type 0x{x}  len {:2} from {}{x} to {}{x} {x}", pdu_type, payload_len, txrnd, tx_address, rxrnd, rx_address, rest);
                } else {
                    const new_key = [_]u8{ s0, tx_address[0], tx_address[1], tx_address[2], tx_address[3], tx_address[4], tx_address[5] };
                    var found = false;
                    for (self.broadcasters) |*b, i| {
                        if (mem.eql(u8, &new_key, b.key)) {
                            found = true;
                            if (!mem.eql(u8, rest, b.value)) {
                                // log("delta {:2} {x} {:4} {:4} {x}", .{ i + 1, b.key, b.key_count, b.value_count, b.value });
                                b.key_count += 1;
                                b.value_count = 1;
                                b.value = b.buffer[7 .. 7 + rest.len];
                                mem.copy(u8, b.value, rest);
                                // log("      {:2} {x} {:4} {:4} {x}", .{ i + 1, b.key, b.key_count, b.value_count, b.value });
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
                            b.prepare();
                            b.key = b.buffer[0..7];
                            mem.copy(u8, b.key, &new_key);
                            b.key_count = 1;
                            b.value = b.buffer[7 .. 7 + rest.len];
                            mem.copy(u8, b.value, rest);
                            b.value_count = 1;
                        } else {
                            // log("{x} no room {}", new_key, i);
                        }
                    }
                }
            }
        }
    }

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

        fn getToggledButton(self: *Broadcaster) ?RemoteButtonActivity.RemoteButton {
            if (self.isTwoButtonBeacon() and self.toggleHistoryCount() != self.processed_toggle_history_count) {
                const index = if (self.value[9 + self.processed_toggle_history_offset] & self.processed_toggle_history_mask == 0) @as(u32, 0) else 1;
                const is_pressed = !self.buttons_is_pressed[index];
                self.buttons_is_pressed[index] = is_pressed;
                const remote_button = RemoteButtonActivity.RemoteButton.new(index, is_pressed);
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

        fn prepare(self: *Broadcaster) void {
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
    };
};

const RemoteButtonActivity = struct {
    broadcaster_index: u32,
    throttle: Throttle,

    fn prepare(self: *RemoteButtonActivity) void {
        self.broadcaster_index = 0;
        self.throttle.prepare();
    }

    fn update(self: *RemoteButtonActivity) void {
        if (radio_activity.broadcasters.len > 0) {
            self.broadcaster_index += 1;
            if (self.broadcaster_index >= radio_activity.broadcasters.len) {
                self.broadcaster_index = 0;
            }
            const broadcaster = &radio_activity.broadcasters[self.broadcaster_index];
            if (broadcaster.getToggledButton()) |*b| {
                Terminal.attribute(if (b.index == 0) @as(u32, 31) else 32);
                log("remote button {} {}", .{ buttonName(b.index), buttonStateString(b.is_pressed) });
                Terminal.attribute(0);
                if (b.is_pressed) {
                    if (b.index == 0 and !broadcaster.buttons_is_pressed[1]) {
                        if (self.throttle.percent >= 5) {
                            self.throttle.movePercent(-5);
                        }
                    } else if (b.index == 1 and !broadcaster.buttons_is_pressed[0]) {
                        if (self.throttle.percent <= 95) {
                            self.throttle.movePercent(5);
                        }
                    } else {
                        self.throttle.setPercent(0);
                    }
                }
            }
        }
    }

    const RemoteButton = struct {
        index: u32,
        is_pressed: bool,

        fn new(index: u32, is_pressed: bool) RemoteButton {
            var self: RemoteButton = undefined;
            self.index = index;
            self.is_pressed = is_pressed;
            return self;
        }
    };

    const Throttle = struct {
        pwm_out_of_312: u32,
        percent: u32,

        fn movePercent(self: *Throttle, delta: i32) void {
            self.setPercent(@intCast(u32, @intCast(i32, self.percent) + delta));
        }

        fn prepare(self: *Throttle) void {
            self.percent = 0;
            Gpio.config[02] = Gpio.config_masks.output;
            Gpio.config[03] = Gpio.config_masks.input;
            Ppi.setChannelEventAndTask(0, &Timer1.events.compare[0], &Gpiote.tasks.out[0]);
            Ppi.setChannelEventAndTask(1, &Timer1.events.compare[1], &Gpiote.tasks.out[0]);
            Timer1.short_cuts.shorts = 0x002;
            Timer1.capture_compare_registers[1] = 312;
        }

        fn setPercent(self: *Throttle, percent: u32) void {
            if (percent > 100) {
                panicf("attempted throttle {} exceeds 100 percent", .{percent});
            }
            self.percent = percent;
            Timer1.tasks.stop = 1;
            Ppi.registers.channel_enable_clear = 0x3;
            Gpiote.config[0] = Gpiote.config_masks.disable;
            Gpio.registers.out_clear = Gpio.registers_masks.ring1;
            self.pwm_out_of_312 = 0;
            if (percent == 100) {
                Gpio.registers.out_set = Gpio.registers_masks.ring1;
            } else if (percent > 0) {
                self.pwm_out_of_312 = 1000 * (100 - percent) * 312 / (100 * 1000);
                Timer1.capture_compare_registers[0] = self.pwm_out_of_312;
                Gpio.registers.out_clear = Gpio.registers_masks.ring1;
                Gpiote.config[0] = 0x30203;
                Ppi.registers.channel_enable_set = 0x3;
                Timer1.tasks.clear = 1;
                Timer1.tasks.start = 1;
            }
        }
    };
};

const StatusActivity = struct {
    prev_led_image: u32,
    prev_now: u32,
    pwm_counter: u32,

    fn prepare(self: *StatusActivity) void {
        self.prev_led_image = 0;
        self.prev_now = cycle_activity.up_time_seconds;
        self.pwm_counter = 0;
        self.redraw();
    }

    fn redraw(self: *StatusActivity) void {
        Terminal.clearScreen();
        Terminal.setScrollingRegion(status_display_lines, 99);
        Terminal.move(status_display_lines - 1, 1);
        log("keyboard input will be echoed below:", .{});
        restoreInputLine();
    }

    fn update(self: *StatusActivity) void {
        Uart.update();
        if (Gpio.registers.in & Gpio.registers_masks.ring0 != 0) {
            self.pwm_counter += 1;
        }
        const now = cycle_activity.up_time_seconds;
        if (now >= self.prev_now + 1) {
            Terminal.hideCursor();
            Terminal.move(1, 1);
            Terminal.line("up {:3}s cycle {}us max {}us", .{ cycle_activity.up_time_seconds, cycle_activity.cycle_time, cycle_activity.max_cycle_time });
            Terminal.line("gpio.in {x:8} .out {x:8} throttle {:2}% pwm {:2}% cc0 {} raw {}", .{ Gpio.registers.in & ~@as(u32, 0x0300fff0), Gpio.registers.out, remote_button_activity.throttle.percent, self.pwm_counter * 100 * 1000 / 13800 / 1000, remote_button_activity.throttle.pwm_out_of_312, self.pwm_counter });
            Terminal.line("ble tx {} rx ok {} crc errors {} frequency {} addr type {x} 0x{x}{x}", .{ radio_activity.tx_count, radio_activity.rx_count, radio_activity.crc_error_count, Radio.registers.frequency + 2400, Ficr.radio.device_address_type & 1, Ficr.radio.device_address1 & 0xffff, Ficr.radio.device_address0 });

            Terminal.showCursor();
            restoreInputLine();
            self.prev_now = now;
            self.pwm_counter = 0;
        } else if (LedMatrix.image != self.prev_led_image) {
            Terminal.hideCursor();
            Terminal.attribute(33);
            var mask: u32 = 0x1;
            var y: i32 = 4;
            while (y >= 0) : (y -= 1) {
                var x: i32 = 4;
                while (x >= 0) : (x -= 1) {
                    const v = LedMatrix.image & mask;
                    if (v != self.prev_led_image & mask) {
                        Terminal.move(@intCast(u32, 4 + y), @intCast(u32, 1 + 2 * x));
                        Uart.writeText(if (v != 0) "[]" else "  ");
                    }
                    mask <<= 1;
                }
            }
            self.prev_led_image = LedMatrix.image;
            Terminal.attribute(0);
            restoreInputLine();
        }
    }
};

fn buttonName(index: u32) []const u8 {
    return if (index == 0) "A" else "B";
}

fn buttonStateString(is_pressed: bool) []const u8 {
    return if (is_pressed) "pressed "[0..] else "released"[0..];
}

fn exceptionHandler(exception_number: u32) noreturn {
    panicf("exception number {} ... now idle in arm exception handler", .{exception_number});
}

export fn mission02_exceptionNumber01() noreturn {
    exceptionHandler(01);
}

export fn mission02_exceptionNumber02() noreturn {
    exceptionHandler(02);
}

export fn mission02_exceptionNumber03() noreturn {
    exceptionHandler(03);
}

export fn mission02_exceptionNumber04() noreturn {
    exceptionHandler(04);
}

export fn mission02_exceptionNumber05() noreturn {
    exceptionHandler(05);
}

export fn mission02_exceptionNumber06() noreturn {
    exceptionHandler(06);
}

export fn mission02_exceptionNumber07() noreturn {
    exceptionHandler(07);
}

export fn mission02_exceptionNumber08() noreturn {
    exceptionHandler(08);
}

export fn mission02_exceptionNumber09() noreturn {
    exceptionHandler(09);
}

export fn mission02_exceptionNumber10() noreturn {
    exceptionHandler(10);
}

export fn mission02_exceptionNumber11() noreturn {
    exceptionHandler(11);
}

export fn mission02_exceptionNumber12() noreturn {
    exceptionHandler(12);
}

export fn mission02_exceptionNumber13() noreturn {
    exceptionHandler(13);
}

export fn mission02_exceptionNumber14() noreturn {
    exceptionHandler(14);
}

export fn mission02_exceptionNumber15() noreturn {
    exceptionHandler(15);
}

fn restoreInputLine() void {
    Terminal.move(999, keyboard_activity.column);
}

comptime {
    asm (
        \\.section .text.start.mission02
        \\.globl mission02_vector_table
        \\.balign 0x80
        \\mission02_vector_table:
        \\ .long 0x20004000 - 4 // sp top of 16KB ram
        \\ .long mission02_main
        \\ .long mission02_exceptionNumber02
        \\ .long mission02_exceptionNumber03
        \\ .long mission02_exceptionNumber04
        \\ .long mission02_exceptionNumber05
        \\ .long mission02_exceptionNumber06
        \\ .long mission02_exceptionNumber07
        \\ .long mission02_exceptionNumber08
        \\ .long mission02_exceptionNumber09
        \\ .long mission02_exceptionNumber10
        \\ .long mission02_exceptionNumber11
        \\ .long mission02_exceptionNumber12
        \\ .long mission02_exceptionNumber13
        \\ .long mission02_exceptionNumber14
        \\ .long mission02_exceptionNumber15
    );
}

const Bss = lib.Bss;
const broadcasters_max_len = 40;
const builtin = @import("builtin");
const ClockManagement = lib.ClockManagement;
const Ficr = lib.Ficr;
const Gpio = lib.Gpio;
const Gpiote = lib.Gpiote;
const lib = @import("lib00_basics.zig");
const literal = Uart.literal;
const log = Uart.log;
const math = std.math;
const mem = std.mem;
const LedMatrix = lib.LedMatrix;
const panicf = lib.panicf;
const Ppi = lib.Ppi;
const Radio = lib.Radio;
const std = @import("std");
const status_display_lines = 5 + 5;
const Terminal = lib.Terminal;
const TimeKeeper = lib.TimeKeeper;
const Timer0 = lib.Timer0;
const Timer1 = lib.Timer1;
const Timer2 = lib.Timer2;
const Uart = lib.Uart;

pub const panic = lib.panic;

var cycle_activity: CycleActivity = undefined;
var gpio: Gpio = undefined;
var keyboard_activity: KeyboardActivity = undefined;
var local_button_activity: LocalButtonActivity = undefined;
var radio_activity: RadioActivity = undefined;
var remote_button_activity: RemoteButtonActivity = undefined;
var status_activity: StatusActivity = undefined;
