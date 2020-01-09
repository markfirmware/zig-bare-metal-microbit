export fn mission03_main() noreturn {
    Bss.prepare();
    Uart.prepare();
    Timer0.prepare();
    Timer1.prepare();
    Timer2.prepare();

    cycle_activity.prepare();
    led_matrix_activity.prepare();
    terminal_activity.prepare();
    throttle_activity.prepare();

    Uart.setUpdater(updateLedMatrix);

    while (true) {
        cycle_activity.update();
        led_matrix_activity.update();
        terminal_activity.update();
        throttle_activity.update();
    }
}

const CycleActivity = struct {
    cycle_counter: u32,
    cycle_time: u32,
    cycles_per_second: u32,
    last_cycle_counter: u32,
    last_cycle_start: ?u32,
    max_cycle_time: u32,
    up_time_seconds: u32,
    up_timer: TimeKeeper,

    fn prepare(self: *CycleActivity) void {
        self.cycle_counter = 0;
        self.cycle_time = 0;
        self.cycles_per_second = 1;
        self.last_cycle_counter = 0;
        self.last_cycle_start = null;
        self.max_cycle_time = 0;
        self.up_time_seconds = 0;
        self.up_timer.prepare(1000 * 1000);
    }

    fn update(self: *CycleActivity) void {
        self.cycle_counter += 1;
        const new_cycle_start = Timer0.capture();
        if (self.up_timer.isFinished()) {
            self.up_timer.reset();
            self.up_time_seconds += 1;
            self.cycles_per_second = self.cycle_counter -% self.last_cycle_counter;
            self.last_cycle_counter = self.cycle_counter;
        }
        if (self.last_cycle_start) |start| {
            self.cycle_time = new_cycle_start -% start;
            self.max_cycle_time = math.max(self.cycle_time, self.max_cycle_time);
        }
        self.last_cycle_start = new_cycle_start;
    }
};

const ThrottleActivity = struct {
    buttons: [2]Button,
    pwm_counter: u32,
    led_scroller: LedScroller,
    throttle: Throttle,

    fn prepare(self: *ThrottleActivity) void {
        self.pwm_counter = 0;
        self.throttle.prepare();
        for (self.buttons) |*b, i| {
            b.prepare(i);
        }
        self.led_scroller.prepare();
        self.redraw();
        self.update();
    }

    fn redraw(self: *ThrottleActivity) void {
        for (self.buttons) |*b| {
            b.draw();
        }
    }

    fn update(self: *ThrottleActivity) void {
        if (Gpio.registers.in & Gpio.registers_masks.ring0 != 0) {
            self.pwm_counter += 1;
        }
        for (self.buttons) |*button| {
            button.update();
        }
        self.led_scroller.update();
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

        fn toggle(self: *Button) void {
            self.is_simulation_pressed = !self.is_simulation_pressed;
            self.update();
        }

        fn update(self: *Button) void {
            const new = Gpio.registers.in & self.mask == 0 or self.is_simulation_pressed;
            if (new != self.is_pressed) {
                self.is_pressed = new;
                self.draw();
                restoreInputLine();
                if (self.is_pressed) {
                    self.down_count += 1;
                    if (self.index == 0 and !throttle_activity.buttons[1].is_pressed) {
                        throttle_activity.throttle.movePercent("button A pressed", -5);
                    } else if (self.index == 1 and !throttle_activity.buttons[0].is_pressed) {
                        throttle_activity.throttle.movePercent("button B pressed", 5);
                    } else {
                        throttle_activity.throttle.setPercent("Both buttons A and B pressed (reset throttle to 0%)", 0);
                    }
                } else {
                    self.up_count += 1;
                }
            }
        }
    };

    const LedScroller = struct {
        column: u32,
        text: []u8,
        text_buf: [text_len_max]u8,
        const text_len_max = 4;
        percent: u32,
        timer: TimeKeeper,

        fn prepare(self: *LedScroller) void {
            self.column = 0;
            self.text = self.text_buf[0..0];
            self.timer.prepare(100 * 1000);
        }

        fn update(self: *LedScroller) void {
            if (self.timer.isFinished()) {
                self.timer.reset();
                var index = self.column / 6;
                if (self.column % 6 == 0) {
                    if (index == self.text.len) {
                        const percent = throttle_activity.throttle.percent;
                        if (self.text.len == 0 or percent != self.percent) {
                            self.percent = percent;
                            self.text = self.text_buf[0..2];
                            self.text[0] = ' ';
                            if (percent < 10) {
                                self.text[1] = '0' + @truncate(u8, percent % 10);
                            } else if (percent < 100) {
                                self.text = self.text_buf[0..3];
                                self.text[1] = '0' + @truncate(u8, percent / 10);
                                self.text[2] = '0' + @truncate(u8, percent % 10);
                            } else {
                                self.text = self.text_buf[0..4];
                                self.text[1] = '1';
                                self.text[2] = '0';
                                self.text[3] = '0';
                            }
                            if (percent == 0) {
                                log("scrolling '0' just once", .{});
                            } else {
                                log("scrolling '{}' repeatedly", .{self.text});
                            }
                        } else if (percent == 0) {
                            return;
                        }
                        self.column = 0;
                        index = 0;
                    }
                }
                const mask: u32 = 0b1111011110111101111011110;
                const right = if (self.column % 6 == 0) 0 else led_matrix_activity.getImage(self.text[index]) >> @truncate(u5, (5 - self.column % 6));
                led_matrix_activity.putImage(led_matrix_activity.currentImage() << 1 & mask | (right & ~mask));
                self.column += 1;
            }
        }
    };

    const Throttle = struct {
        pwm_out_of_312: u32,
        percent: u32,

        fn movePercent(self: *Throttle, message: []const u8, delta: i32) void {
            self.setPercent(message, @intCast(i32, self.percent) + delta);
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

        fn setPercent(self: *Throttle, message: []const u8, new: i32) void {
            const percent = @intCast(u32, math.min(math.max(new, 0), 100));
            if (percent != self.percent) {
                log("{}: throttle changed from {} to {}", .{ message, self.percent, percent });
            } else {
                log("{}: throttle remains at {}%", .{ message, self.percent });
            }
            self.percent = percent;
            Timer1.tasks.stop = 1;
            const ppi_channels_0_and_1_mask = 1 << 0 | 1 << 1;
            Ppi.registers.channel_enable_clear = ppi_channels_0_and_1_mask;
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
                Ppi.registers.channel_enable_set = ppi_channels_0_and_1_mask;
                Timer1.tasks.clear = 1;
                Timer1.tasks.start = 1;
            }
        }
    };
};

const TerminalActivity = struct {
    keyboard_column: u32,
    prev_led_image: u32,
    prev_now: u32,

    fn prepare(self: *TerminalActivity) void {
        self.keyboard_column = 1;
        self.prev_led_image = 0;
        self.prev_now = cycle_activity.up_time_seconds;
        self.redraw();
    }

    fn redraw(self: *TerminalActivity) void {
        Terminal.clearScreen();
        Terminal.setScrollingRegion(status_display_lines, 99);
        Terminal.move(status_display_lines - 1, 1);
        log("keyboard input will be echoed below:", .{});
        restoreInputLine();
    }

    fn update(self: *TerminalActivity) void {
        if (Uart.isReadByteReady()) {
            const byte = Uart.readByte();
            switch (byte) {
                27 => {
                    Uart.writeByteBlocking('$');
                    self.keyboard_column += 1;
                },
                'a' => {
                    throttle_activity.buttons[0].toggle();
                    throttle_activity.buttons[0].toggle();
                },
                'b' => {
                    throttle_activity.buttons[1].toggle();
                    throttle_activity.buttons[1].toggle();
                },
                'c' => {
                    throttle_activity.buttons[0].toggle();
                    throttle_activity.buttons[1].toggle();
                    throttle_activity.buttons[0].toggle();
                    throttle_activity.buttons[1].toggle();
                },
                'A' => {
                    throttle_activity.buttons[0].toggle();
                },
                'B' => {
                    throttle_activity.buttons[1].toggle();
                },
                12 => {
                    self.keyboard_column = 1;
                    terminal_activity.prev_led_image = 0;
                    terminal_activity.redraw();
                    throttle_activity.redraw();
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
            Terminal.line("up {:3}s cycle {}Hz {}us max {}us led max {}us", .{ cycle_activity.up_time_seconds, cycle_activity.cycles_per_second, cycle_activity.cycle_time, cycle_activity.max_cycle_time, led_matrix_activity.maxElapsed() });
            Terminal.line("throttle {:2}% pwm {:2}% cc0 {} raw {}", .{ throttle_activity.throttle.percent, throttle_activity.pwm_counter * 100 * 1000 / cycle_activity.cycles_per_second / 1000, throttle_activity.throttle.pwm_out_of_312, throttle_activity.pwm_counter });
            Terminal.showCursor();
            restoreInputLine();
            self.prev_now = now;
            throttle_activity.pwm_counter = 0;
        } else if (led_matrix_activity.currentImage() != self.prev_led_image) {
            Terminal.hideCursor();
            Terminal.attribute(33);
            var mask: u32 = 0x1;
            var y: i32 = 4;
            while (y >= 0) : (y -= 1) {
                var x: i32 = 4;
                while (x >= 0) : (x -= 1) {
                    const v = led_matrix_activity.currentImage() & mask;
                    if (v != self.prev_led_image & mask) {
                        Terminal.move(@intCast(u32, 4 + y), @intCast(u32, 21 + 2 * x));
                        Uart.writeText(if (v != 0) "[]" else "  ");
                    }
                    mask <<= 1;
                }
            }
            self.prev_led_image = led_matrix_activity.currentImage();
            Terminal.attribute(0);
            restoreInputLine();
        }
    }
};

fn exceptionHandler(exception_number: u32) noreturn {
    panicf("exception number {} ... now idle in arm exception handler", .{exception_number});
}

export fn mission03_exceptionNumber01() noreturn {
    exceptionHandler(01);
}

export fn mission03_exceptionNumber02() noreturn {
    exceptionHandler(02);
}

export fn mission03_exceptionNumber03() noreturn {
    exceptionHandler(03);
}

export fn mission03_exceptionNumber04() noreturn {
    exceptionHandler(04);
}

export fn mission03_exceptionNumber05() noreturn {
    exceptionHandler(05);
}

export fn mission03_exceptionNumber06() noreturn {
    exceptionHandler(06);
}

export fn mission03_exceptionNumber07() noreturn {
    exceptionHandler(07);
}

export fn mission03_exceptionNumber08() noreturn {
    exceptionHandler(08);
}

export fn mission03_exceptionNumber09() noreturn {
    exceptionHandler(09);
}

export fn mission03_exceptionNumber10() noreturn {
    exceptionHandler(10);
}

export fn mission03_exceptionNumber11() noreturn {
    exceptionHandler(11);
}

export fn mission03_exceptionNumber12() noreturn {
    exceptionHandler(12);
}

export fn mission03_exceptionNumber13() noreturn {
    exceptionHandler(13);
}

export fn mission03_exceptionNumber14() noreturn {
    exceptionHandler(14);
}

export fn mission03_exceptionNumber15() noreturn {
    exceptionHandler(15);
}

fn restoreInputLine() void {
    Terminal.move(999, terminal_activity.keyboard_column);
}

fn updateLedMatrix() void {
    led_matrix_activity.update();
}

comptime {
    asm (
        \\.section .text.start.mission03
        \\.globl mission03_vector_table
        \\.balign 0x80
        \\mission03_vector_table:
        \\ .long 0x20004000 - 4 // sp top of 16KB ram
        \\ .long mission03_main
        \\ .long mission03_exceptionNumber02
        \\ .long mission03_exceptionNumber03
        \\ .long mission03_exceptionNumber04
        \\ .long mission03_exceptionNumber05
        \\ .long mission03_exceptionNumber06
        \\ .long mission03_exceptionNumber07
        \\ .long mission03_exceptionNumber08
        \\ .long mission03_exceptionNumber09
        \\ .long mission03_exceptionNumber10
        \\ .long mission03_exceptionNumber11
        \\ .long mission03_exceptionNumber12
        \\ .long mission03_exceptionNumber13
        \\ .long mission03_exceptionNumber14
        \\ .long mission03_exceptionNumber15
    );
}

const Bss = lib.Bss;
const builtin = @import("builtin");
const Gpio = lib.Gpio;
const Gpiote = lib.Gpiote;
const lib = @import("lib00_basics.zig");
const log = Uart.log;
const math = std.math;
const mem = std.mem;
const LedMatrixActivity = lib.LedMatrixActivity;
const panicf = lib.panicf;
const Ppi = lib.Ppi;
const std = @import("std");
const status_display_lines = 6 + 5;
const Terminal = lib.Terminal;
const TimeKeeper = lib.TimeKeeper;
const Timer0 = lib.Timer0;
const Timer1 = lib.Timer1;
const Timer2 = lib.Timer2;
const Uart = lib.Uart;

pub const panic = lib.panic;

var cycle_activity: CycleActivity = undefined;
var led_matrix_activity: LedMatrixActivity = undefined;
var terminal_activity: TerminalActivity = undefined;
var throttle_activity: ThrottleActivity = undefined;
