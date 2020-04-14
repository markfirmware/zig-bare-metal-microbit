fn main() callconv(.C) noreturn {
    Bss.prepare();
    Uart.prepare();
    Timer(0).prepare();
    Timer(1).prepare();
    Timer(2).prepare();
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
        const new_cycle_start = Timer(0).captureAndRead();
        if (up_timer.isFinishedThenReset()) {
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
    var pwm_loop_back_counter: u32 = undefined;

    fn loopBackPercent() u32 {
        return pwm_loop_back_counter * 100 * 1000 / CycleActivity.cycles_per_second / 1000;
    }

    fn prepare() void {
        pwm_loop_back_counter = 0;
        Throttle.prepare();
        button(0).prepare();
        button(1).prepare();
        LedScroller.prepare();
        redraw();
        update();
    }

    fn redraw() void {
        button(0).draw();
        button(1).draw();
    }

    fn releaseSimulatedButtons() void {
        comptime var i: u32 = 0;
        while (i < 2) : (i += 1) {
            if (button(i).is_simulation_pressed) {
                button(i).toggleSimulated();
            }
        }
    }

    fn update() void {
        if (Pins.ring0.read() == 1) {
            pwm_loop_back_counter += 1;
        }
        button(0).update();
        button(0).update();
        LedScroller.update();
    }

    fn button(index: u32) type {
        return struct {
            var down_count: u32 = undefined;
            var elapsed: [2]u32 = undefined;
            var event_time: u32 = undefined;
            var is_pressed: bool = undefined;
            var is_simulation_pressed: bool = undefined;
            var up_count: u32 = undefined;

            fn draw() void {
                Terminal.hideCursor();
                Terminal.move(6, 10 + index * 31);
                if (is_pressed) {
                    Terminal.attribute(44);
                    Uart.writeText(name());
                    Uart.writeText(" down");
                    Terminal.attribute(0);
                } else {
                    Uart.writeText(name());
                    Uart.writeText("     ");
                }
            }

            fn name() []const u8 {
                return if (index == 0) "A" else "B";
            }

            fn prepare() void {
                down_count = 0;
                elapsed[0] = 0x7fffffff;
                elapsed[1] = 0x7fffffff;
                event_time = 0;
                is_pressed = false;
                is_simulation_pressed = false;
                up_count = 0;
                pin().connectInput();
                update();
            }

            fn pin() type {
                return if (index == 0) Pins.buttons.a else Pins.buttons.b;
            }

            fn toggleSimulated() void {
                is_simulation_pressed = !is_simulation_pressed;
                update();
            }

            fn update() void {
                const new = (pin().read() == 0) or is_simulation_pressed;
                if (new != is_pressed) {
                    var now = Timer(0).captureAndRead();
                    const up_or_down = if (new) @as(usize, 1) else 0;
                    elapsed[up_or_down] = math.min(elapsed[up_or_down], now -% event_time);
                    event_time = now;
                    is_pressed = new;
                    draw();
                    TerminalActivity.restoreInputLine();
                    if (is_pressed) {
                        down_count += 1;
                        if (index == 0 and !button(1).is_pressed) {
                            Throttle.movePercent("button A pressed", -5);
                        } else if (index == 1 and !button(0).is_pressed) {
                            Throttle.movePercent("button B pressed", 5);
                        } else {
                            Throttle.setPercent("Both buttons A and B pressed (reset throttle to 0%)", 0);
                        }
                    } else {
                        up_count += 1;
                    }
                }
            }
        };
    }

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
            if (timer.isFinishedThenReset()) {
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
                const right = if (column % 6 == 0) 0 else LedMatrix.getImage(text[index]) >> @truncate(u5, 5 - column % 6);
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
            Pins.ring1.connectIo();
            Pins.ring0.connectInput();
            Ppi.setChannelEventAndTask(0, Timer(1).events.compare[0], Gpiote.tasks.out[0]);
            Ppi.setChannelEventAndTask(1, Timer(1).events.compare[1], Gpiote.tasks.out[0]);
            Timer(1).registers.shorts.write(0x002);
            // Timer(1).setShorts(compare1, clear);
            Timer(1).registers.capture_compare[1].write(pwm_width_ticks_max);
        }

        fn setPercent(message: []const u8, new: i32) void {
            const new_percent = @intCast(u32, math.min(math.max(new, 0), 100));
            if (new_percent != percent) {
                log("{}: throttle changed from {} to {}", .{ message, percent, new_percent });
            } else {
                log("{}: throttle remains at {}%", .{ message, percent });
            }
            percent = new_percent;
            Timer(1).tasks.stop.do();
            const ppi_channels_0_and_1_mask = 1 << 0 | 1 << 1;
            Ppi.registers.channel_enable.clear(ppi_channels_0_and_1_mask);
            Gpiote.registers.config[0].write(.{ .mode = .Disabled });
            Pins.ring1.clear();
            pwm_width_ticks = 0;
            if (percent == 100) {
                Pins.ring1.set();
            } else if (percent > 0) {
                pwm_width_ticks = 1000 * (100 - percent) * pwm_width_ticks_max / (100 * 1000);
                Timer(1).registers.capture_compare[0].write(pwm_width_ticks);
                Pins.ring1.clear();
                Gpiote.registers.config[0].write(.{ .mode = .Task, .psel = Pins.ring1.id, .polarity = .Toggle, .outinit = .Low });
                Ppi.registers.channel_enable.set(ppi_channels_0_and_1_mask);
                Timer(1).tasks.clear.do();
                Timer(1).tasks.start.do();
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
                    ThrottleActivity.button(0).toggleSimulated();
                    ThrottleActivity.button(0).toggleSimulated();
                },
                'b' => {
                    ThrottleActivity.releaseSimulatedButtons();
                    ThrottleActivity.button(1).toggleSimulated();
                    ThrottleActivity.button(1).toggleSimulated();
                },
                'c' => {
                    ThrottleActivity.releaseSimulatedButtons();
                    ThrottleActivity.button(0).toggleSimulated();
                    ThrottleActivity.button(1).toggleSimulated();
                    ThrottleActivity.button(0).toggleSimulated();
                    ThrottleActivity.button(1).toggleSimulated();
                },
                'A' => {
                    ThrottleActivity.button(0).toggleSimulated();
                },
                'B' => {
                    ThrottleActivity.button(1).toggleSimulated();
                },
                3 => {
                    SystemControlBlock.requestSystemReset();
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
            Terminal.line("up {:3}s cycle {}Hz {}us max {}us led max {}us", .{ CycleActivity.up_time_seconds, CycleActivity.cycles_per_second, CycleActivity.cycle_time, CycleActivity.max_cycle_time, LedMatrix.scan_timer.max_elapsed });
            Terminal.line("throttle {:2}% pwm {:2}% cc0 {} raw {}", .{ ThrottleActivity.Throttle.percent, ThrottleActivity.loopBackPercent(), ThrottleActivity.Throttle.pwm_width_ticks, ThrottleActivity.pwm_loop_back_counter });
            Terminal.line("button a up {}us down {}us b up {}us down {}us", .{ ThrottleActivity.button(0).elapsed[0], ThrottleActivity.button(0).elapsed[1], ThrottleActivity.button(1).elapsed[0], ThrottleActivity.button(1).elapsed[1] });
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

const status_display_lines = 6 + 6;

pub const mission_number: u32 = 2;

pub const vector_table linksection(".vector_table") = simpleVectorTable(main);
comptime {
    @export(vector_table, .{ .name = "vector_table_mission2" });
}

usingnamespace @import("lib_basics.zig").typical;
