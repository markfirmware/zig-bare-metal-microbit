export fn mission03_main() noreturn {
    Bss.prepare();
    Uart.prepare();
    Timer0.prepare();
    Timer1.prepare();
    Timer2.prepare();
    LedMatrix.prepare();

    CycleActivity.prepare();
    TerminalActivity.prepare();
    ThrottleActivity.prepare();

    Uart.setUpdater(LedMatrix.update);

    while (true) {
        CycleActivity.update();
        TerminalActivity.update();
        ThrottleActivity.update();
    }
}

const CycleActivity = struct {
    var cycle_counter: u32 = undefined;
    var cycle_time: u32 = undefined;
    var cycles_per_second: u32 = undefined;
    var last_cycle_counter: u32 = undefined;
    var last_cycle_start: ?u32 = undefined;
    var max_cycle_time: u32 = undefined;
    var up_time_seconds: u32 = undefined;
    var up_timer: TimeKeeper = undefined;

    fn prepare() void {
        cycle_counter = 0;
        cycle_time = 0;
        cycles_per_second = 1;
        last_cycle_counter = 0;
        last_cycle_start = null;
        max_cycle_time = 0;
        up_time_seconds = 0;
        up_timer.prepare(1000 * 1000);
    }

    fn update() void {
        LedMatrix.update();
        cycle_counter += 1;
        const new_cycle_start = Timer0.capture();
        if (up_timer.isFinished()) {
            up_timer.reset();
            up_time_seconds += 1;
            cycles_per_second = cycle_counter -% last_cycle_counter;
            last_cycle_counter = cycle_counter;
        }
        if (last_cycle_start) |start| {
            cycle_time = new_cycle_start -% start;
            max_cycle_time = math.max(cycle_time, max_cycle_time);
        }
        last_cycle_start = new_cycle_start;
    }
};

const ThrottleActivity = struct {
    var buttons: [2]Button = undefined;
    var pwm_loop_back_counter: u32 = undefined;

    fn loopBackPercent() u32 {
        return pwm_loop_back_counter * 100 * 1000 / CycleActivity.cycles_per_second / 1000;
    }

    fn prepare() void {
        pwm_loop_back_counter = 0;
        Throttle.prepare();
        for (buttons) |*b, i| {
            b.prepare(i);
        }
        LedScroller.prepare();
        redraw();
        update();
    }

    fn redraw() void {
        for (buttons) |*b| {
            b.draw();
        }
    }

    fn releaseSimulatedButtons() void {
        for (buttons) |*b| {
            if (b.is_simulation_pressed) {
                b.toggleSimulated();
            }
        }
    }

    fn update() void {
        if (Gpio.registers.in & Gpio.registers_masks.ring0 != 0) {
            pwm_loop_back_counter += 1;
        }
        for (buttons) |*button| {
            button.update();
        }
        LedScroller.update();
    }

    const Button = struct {
        down_count: u32,
        index: u32,
        is_pressed: bool,
        is_simulation_pressed: bool,
        mask: u32,
        up_count: u32,

        fn draw(self: *Button) void {
            Terminal.hideCursor();
            Terminal.move(6, 10 + self.index * 31);
            if (self.is_pressed) {
                Terminal.attribute(44);
                Uart.writeText(self.name());
                Uart.writeText(" down");
                Terminal.attribute(0);
            } else {
                Uart.writeText(self.name());
                Uart.writeText("     ");
            }
        }

        fn name(self: *Button) []const u8 {
            return if (self.index == 0) "A" else "B";
        }

        fn prepare(self: *Button, index: u32) void {
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

        fn toggleSimulated(self: *Button) void {
            self.is_simulation_pressed = !self.is_simulation_pressed;
            self.update();
        }

        fn update(self: *Button) void {
            const new = Gpio.registers.in & self.mask == 0 or self.is_simulation_pressed;
            if (new != self.is_pressed) {
                self.is_pressed = new;
                self.draw();
                TerminalActivity.restoreInputLine();
                if (self.is_pressed) {
                    self.down_count += 1;
                    if (self.index == 0 and !buttons[1].is_pressed) {
                        Throttle.movePercent("button A pressed", -5);
                    } else if (self.index == 1 and !buttons[0].is_pressed) {
                        Throttle.movePercent("button B pressed", 5);
                    } else {
                        Throttle.setPercent("Both buttons A and B pressed (reset throttle to 0%)", 0);
                    }
                } else {
                    self.up_count += 1;
                }
            }
        }
    };

    const LedScroller = struct {
        var column: u32 = undefined;
        var displayed_percent: u32 = undefined;
        var text: []u8 = undefined;
        var text_buf: [text_len_max]u8 = undefined;
        const text_len_max = 4;
        var timer: TimeKeeper = undefined;

        fn prepare() void {
            column = 0;
            text = text_buf[0..0];
            timer.prepare(100 * 1000);
        }

        fn update() void {
            if (timer.isFinished()) {
                timer.reset();
                var index = column / 6;
                if (column % 6 == 0) {
                    if (index == text.len) {
                        if (text.len == 0 or Throttle.percent != displayed_percent) {
                            displayed_percent = Throttle.percent;
                            text = text_buf[0..2];
                            text[0] = ' ';
                            if (displayed_percent < 10) {
                                text[1] = '0' + @truncate(u8, displayed_percent % 10);
                            } else if (displayed_percent < 100) {
                                text = text_buf[0..3];
                                text[1] = '0' + @truncate(u8, displayed_percent / 10);
                                text[2] = '0' + @truncate(u8, displayed_percent % 10);
                            } else {
                                text = text_buf[0..4];
                                text[1] = '1';
                                text[2] = '0';
                                text[3] = '0';
                            }
                            if (displayed_percent == 0) {
                                log("scrolling '0' just once", .{});
                            } else {
                                log("scrolling '{}' repeatedly", .{text});
                            }
                        } else if (displayed_percent == 0) {
                            return;
                        }
                        column = 0;
                        index = 0;
                    }
                }
                const mask: u32 = 0b1111011110111101111011110;
                const right = if (column % 6 == 0) 0 else LedMatrix.getImage(text[index]) >> @truncate(u5, (5 - column % 6));
                LedMatrix.putImage(LedMatrix.image << 1 & mask | (right & ~mask));
                column += 1;
            }
        }
    };

    const Throttle = struct {
        var pwm_width_ticks: u32 = undefined;
        const pwm_width_ticks_max = 312;
        var percent: u32 = undefined;

        fn movePercent(message: []const u8, delta: i32) void {
            setPercent(message, @intCast(i32, percent) + delta);
        }

        fn prepare() void {
            percent = 0;
            Gpio.config[02] = Gpio.config_masks.output;
            Gpio.config[03] = Gpio.config_masks.input;
            Ppi.setChannelEventAndTask(0, &Timer1.events.compare[0], &Gpiote.tasks.out[0]);
            Ppi.setChannelEventAndTask(1, &Timer1.events.compare[1], &Gpiote.tasks.out[0]);
            Timer1.short_cuts.shorts = 0x002;
            Timer1.capture_compare_registers[1] = pwm_width_ticks_max;
        }

        fn setPercent(message: []const u8, new: i32) void {
            const new_percent = @intCast(u32, math.min(math.max(new, 0), 100));
            if (new_percent != percent) {
                log("{}: throttle changed from {} to {}", .{ message, percent, new_percent });
            } else {
                log("{}: throttle remains at {}%", .{ message, percent });
            }
            percent = new_percent;
            Timer1.tasks.stop = 1;
            const ppi_channels_0_and_1_mask = 1 << 0 | 1 << 1;
            Ppi.registers.channel_enable_clear = ppi_channels_0_and_1_mask;
            Gpiote.config[0] = Gpiote.config_masks.disable;
            Gpio.registers.out_clear = Gpio.registers_masks.ring1;
            pwm_width_ticks = 0;
            if (percent == 100) {
                Gpio.registers.out_set = Gpio.registers_masks.ring1;
            } else if (percent > 0) {
                pwm_width_ticks = 1000 * (100 - percent) * pwm_width_ticks_max / (100 * 1000);
                Timer1.capture_compare_registers[0] = pwm_width_ticks;
                Gpio.registers.out_clear = Gpio.registers_masks.ring1;
                Gpiote.config[0] = 0x30203;
                Ppi.registers.channel_enable_set = ppi_channels_0_and_1_mask;
                Timer1.tasks.clear = 1;
                Timer1.tasks.start = 1;
            }
        }
    };
};

const TerminalActivity = struct {
    var keyboard_column: u32 = undefined;
    var prev_led_image: u32 = undefined;
    var prev_now: u32 = undefined;

    fn prepare() void {
        keyboard_column = 1;
        prev_led_image = 0;
        prev_now = CycleActivity.up_time_seconds;
        redraw();
    }

    fn redraw() void {
        Terminal.clearScreen();
        Terminal.setScrollingRegion(status_display_lines, 99);
        Terminal.move(status_display_lines - 1, 1);
        log("keyboard input will be echoed below:", .{});
        restoreInputLine();
    }

    fn restoreInputLine() void {
        Terminal.move(999, TerminalActivity.keyboard_column);
    }

    fn update() void {
        if (Uart.isReadByteReady()) {
            const byte = Uart.readByte();
            switch (byte) {
                27 => {
                    Uart.writeByteBlocking('$');
                    keyboard_column += 1;
                },
                'a' => {
                    ThrottleActivity.releaseSimulatedButtons();
                    ThrottleActivity.buttons[0].toggleSimulated();
                    ThrottleActivity.buttons[0].toggleSimulated();
                },
                'b' => {
                    ThrottleActivity.releaseSimulatedButtons();
                    ThrottleActivity.buttons[1].toggleSimulated();
                    ThrottleActivity.buttons[1].toggleSimulated();
                },
                'c' => {
                    ThrottleActivity.releaseSimulatedButtons();
                    ThrottleActivity.buttons[0].toggleSimulated();
                    ThrottleActivity.buttons[1].toggleSimulated();
                    ThrottleActivity.buttons[0].toggleSimulated();
                    ThrottleActivity.buttons[1].toggleSimulated();
                },
                'A' => {
                    ThrottleActivity.buttons[0].toggleSimulated();
                },
                'B' => {
                    ThrottleActivity.buttons[1].toggleSimulated();
                },
                12 => {
                    keyboard_column = 1;
                    TerminalActivity.prev_led_image = 0;
                    TerminalActivity.redraw();
                    ThrottleActivity.redraw();
                },
                '\r' => {
                    Uart.writeText("\n");
                    keyboard_column = 1;
                },
                else => {
                    Uart.writeByteBlocking(byte);
                    keyboard_column += 1;
                },
            }
        }
        Uart.update();
        const now = CycleActivity.up_time_seconds;
        if (now >= prev_now + 1) {
            Terminal.hideCursor();
            Terminal.move(1, 1);
            Terminal.line("up {:3}s cycle {}Hz {}us max {}us led max {}us", .{ CycleActivity.up_time_seconds, CycleActivity.cycles_per_second, CycleActivity.cycle_time, CycleActivity.max_cycle_time, LedMatrix.max_elapsed });
            Terminal.line("throttle {:2}% pwm {:2}% cc0 {} raw {}", .{ ThrottleActivity.Throttle.percent, ThrottleActivity.loopBackPercent(), ThrottleActivity.Throttle.pwm_width_ticks, ThrottleActivity.pwm_loop_back_counter });
            Terminal.showCursor();
            restoreInputLine();
            prev_now = now;
            ThrottleActivity.pwm_loop_back_counter = 0;
        } else if (LedMatrix.image != prev_led_image) {
            Terminal.hideCursor();
            Terminal.attribute(33);
            var mask: u32 = 0x1;
            var y: i32 = 4;
            while (y >= 0) : (y -= 1) {
                var x: i32 = 4;
                while (x >= 0) : (x -= 1) {
                    const v = LedMatrix.image & mask;
                    if (v != prev_led_image & mask) {
                        Terminal.move(@intCast(u32, 4 + y), @intCast(u32, 21 + 2 * x));
                        Uart.writeText(if (v != 0) "[]" else "  ");
                    }
                    mask <<= 1;
                }
            }
            prev_led_image = LedMatrix.image;
            Terminal.attribute(0);
            restoreInputLine();
        }
    }
};

comptime {
    asm (typicalVectorTable(mission));
}

const mission = 3;
const status_display_lines = 6 + 5;

usingnamespace @import("use00_typical_mission.zig").typical;
