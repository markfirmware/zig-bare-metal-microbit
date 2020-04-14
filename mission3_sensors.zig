const LightSensor = struct {
    var cycle_start: u32 = undefined;
    var low: [3]u32 = undefined;
    var high: [3]u32 = undefined;

    fn prepare() void {
        Pins.leds.anodes.clearAll();
        Pins.leds.cathodes.clearAll();
        Pins.leds.anodes.direction.setAll();
        Pins.leds.cathodes.direction.setAll();
        var i: u32 = 0;
        while (i < low.len) : (i += 1) {
            low[i] = 0x7fffffff;
            high[i] = 0;
        }
        cycle_start = Timer(0).captureAndRead();
    }

    fn update() void {
        const new_cycle_start = Timer(0).captureAndRead();
        if (new_cycle_start -% cycle_start >= 500 * 1000) {
            cycle_start = new_cycle_start;
            var sum: u32 = 0;
            var col: u32 = 1;
            while (col <= 3) : (col += 1) {
                const ain = col + 4;
                const column_mask = @as(u32, 0x10) << @truncate(u5, col - 1);

                Adc.registers.enable.write(0);
                // Adc.registers.config = 2 | (0 << @ctz(u32, Adc.registers_config_masks.refsel)) | (2 << @ctz(u32, Adc.registers_config_masks.inpsel)) | ((@as(u32, 1) << @truncate(u5, ain)) << @ctz(u32, Adc.registers_config_masks.psel));
                Adc.registers.config.write(.{ .resolution = 2, .refsel = 0, .inpsel = 2, .psel = @as(u8, 1) << @truncate(u3, ain) });
                Adc.registers.enable.write(1);

                Gpio.registers.out.set(column_mask);
                TimeKeeper.delay(10 * 1000);
                Gpio.registers.direction.clear(column_mask);
                Adc.tasks.start.do();
                TimeKeeper.delay(5 * 1000);
                assert(Adc.registers.busy.read() == 0);
                // while (Adc.registers.busy.read() != 0) {}
                const result = Adc.registers.result.read();
                if (result < low[col - 1]) {
                    low[col - 1] = result;
                }
                if (result > high[col - 1]) {
                    high[col - 1] = result;
                }
                var percent: u32 = 0;
                const range = high[col - 1] - low[col - 1];
                if (range != 0) {
                    percent = 100 * (high[col - 1] - result) / range;
                }
                format("ain{} {:3}% {}/{}/{} ", .{ ain, percent, low[col - 1], result, high[col - 1] });
                sum += percent;
                Gpio.registers.out.clear(column_mask);
                Gpio.registers.direction.set(column_mask);
            }
            log(" {:3}%", .{sum / 3});
        }
    }
};

const LightSensorJustOne = struct {
    const col: u32 = 1;
    const ain = col + 4;
    const column_mask = @as(u32, 0x10) << @truncate(u5, col - 1);
    var ready = false;

    fn prepare() void {
        Pins.leds.anodes.clearAll();
        Pins.leds.cathodes.clearAll();
        Pins.leds.anodes.directionSetAll();
        Pins.leds.cathodes.directionSetAll();
    }

    fn update() void {
        if (!ready) {
            Adc.registers.enable.write(0);
            Adc.registers.config.write(.{ .resolution = 2, .refsel = 0, .inpsel = 2, .psel = @as(u8, 1) << @truncate(u3, ain) });
            Adc.registers.enable.write(1);
            // ready = true;
            TimeKeeper.delay(5 * 1000);
        }

        Gpio.registers.out.set(column_mask);
        Gpio.registers.direction.clear(column_mask);
        Adc.tasks.start.do();
        // TimeKeeper.delay(5 * 1000);
        while (Adc.busy_registers.busy != 0) {}
        format("ain{} {} ", .{ ain, Adc.registers.result });
        Gpio.registers.out.clear(column_mask);
        Gpio.registers.direction.set(column_mask);
        log("", .{});
    }
};

fn main() callconv(.C) noreturn {
    Bss.prepare();
    Exceptions.prepare();
    Uart.prepare();

    Timer(0).prepare();
    Timer(1).prepare();
    Timer(2).prepare();
    // LedMatrix.prepare();
    ClockManagement.prepareHf();

    CycleActivity.prepare();
    TerminalActivity.prepare();

    I2c(0).prepare();
    Accel.prepare();
    LightSensor.prepare();

    while (true) {
        CycleActivity.update();
        LightSensor.update();
        TerminalActivity.update();
    }
}

const Accel = struct {
    fn prepare() void {
        var data_buf: [0x32]u8 = undefined;
        data_buf[orientation_configuration_register] = orientation_configuration_register_mask_enable;
        I2c(0).writeBlockingPanic(device_address, &data_buf, orientation_configuration_register, orientation_configuration_register);
        data_buf[control_register1] = control_register1_mask_active;
        I2c(0).writeBlockingPanic(device_address, &data_buf, control_register1, control_register1);
    }

    fn update() void {
        var data_buf: [32]u8 = undefined;
        I2c(0).readBlockingPanic(device_address, &data_buf, orientation_register, orientation_register);
        const orientation = data_buf[orientation_register];
        if (orientation & orientation_register_mask_changed != 0) {
            format("orientation: 0x{x} ", .{orientation});
            if (orientation & orientation_register_mask_forward_backward != 0) {
                format("forward ", .{});
            } else {
                format("backward ", .{});
            }
            if (orientation & orientation_register_mask_z_lock_out != 0) {
                log("up/down/left/right is unknown", .{});
            } else {
                const direction = (orientation & orientation_register_mask_direction) >> @ctz(u5, orientation_register_mask_direction);
                switch (direction) {
                    0 => {
                        log("up", .{});
                    },
                    1 => {
                        log("down", .{});
                    },
                    2 => {
                        log("right", .{});
                    },
                    3 => {
                        log("left", .{});
                    },
                    else => {
                        unreachable;
                    },
                }
            }
        }
    }

    const control_register1 = 0x2a;
    const control_register1_mask_active = 0x01;
    const device_address = 0x1d;
    const orientation_register = 0x10;
    const orientation_register_mask_changed = 0x80;
    const orientation_register_mask_direction = 0x06;
    const orientation_register_mask_forward_backward = 0x01;
    const orientation_register_mask_z_lock_out = 0x40;
    const orientation_configuration_register = 0x11;
    const orientation_configuration_register_mask_enable = 0x40;
};

const CycleActivity = struct {
    var cycle_counter: u32 = undefined;
    var cycle_time: u32 = undefined;
    var last_cycle_start: ?u32 = undefined;
    var max_cycle_time: u32 = undefined;
    var up_time_seconds: u32 = undefined;
    var up_timer: TimeKeeper = undefined;

    fn prepare() void {
        cycle_counter = 0;
        cycle_time = 0;
        last_cycle_start = null;
        max_cycle_time = 0;
        up_time_seconds = 0;
        up_timer.prepare(1000 * 1000);
    }

    fn update() void {
        cycle_counter += 1;
        const new_cycle_start = Timer(0).captureAndRead();
        if (last_cycle_start) |start| {
            cycle_time = new_cycle_start -% start;
            max_cycle_time = math.max(cycle_time, max_cycle_time);
        }
        last_cycle_start = new_cycle_start;
        if (up_timer.isFinishedThenReset()) {
            up_time_seconds += 1;
            Accel.update();
        }
    }
};

const TerminalActivity = struct {
    var keyboard_column: u32 = undefined;
    var prev_now: u32 = undefined;
    var temperature: u32 = 0;

    fn prepare() void {
        keyboard_column = 1;
        prev_now = CycleActivity.up_time_seconds;
        Temperature.tasks.start.do();
        redraw();
    }

    fn redraw() void {
        Terminal.clearScreen();
        Terminal.setScrollingRegion(5, 99);
        Terminal.move(5 - 1, 1);
        log("keyboard input will be echoed below:", .{});
        Terminal.move(99, keyboard_column);
    }

    fn update() void {
        // LedMatrix.update();
        if (Uart.isReadByteReady()) {
            const byte = Uart.readByte();
            switch (byte) {
                3 => {
                    SystemControlBlock.requestSystemReset();
                },
                12 => {
                    redraw();
                },
                27 => {
                    Uart.writeByteBlocking('$');
                    keyboard_column += 1;
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
        if (Temperature.events.data_ready.occurred()) {
            Temperature.events.data_ready.clear();
            temperature = Temperature.registers.temperature.read();
        }
        const now = CycleActivity.up_time_seconds;
        if (now >= prev_now + 1) {
            Terminal.hideCursor();
            Terminal.move(1, 1);
            Terminal.line("up {:3}s cycle {}us max {}us {}.{}C", .{ CycleActivity.up_time_seconds, CycleActivity.cycle_time, CycleActivity.max_cycle_time, temperature / 4, temperature % 4 * 25 });
            Terminal.showCursor();
            Terminal.move(99, keyboard_column);
            prev_now = now;
        }
    }
};

const status_display_lines = 6 + 6;

pub const mission_number: u32 = 3;

pub const vector_table linksection(".vector_table") = simpleVectorTable(main);
comptime {
    @export(vector_table, .{ .name = "vector_table_mission3" });
}

usingnamespace @import("lib_basics.zig").typical;
