export fn mission04_main() noreturn {
    // Wdt.registers.counter_reset_value = 3 * 32768;
    Wdt.tasks.start = 1;
    Bss.prepare();
    Exceptions.prepare();
    Uart.prepare();

    Timer0.prepare();
    Timer1.prepare();
    Timer2.prepare();
    LedMatrix.prepare();
    ClockManagement.prepareHf();

    CycleActivity.prepare();
    TerminalActivity.prepare();

    I2c0.prepare();
    // scanI2c();
    // lightSensor();

    Accel.prepare();

    while (true) {
        Wdt.reload_request_registers.reload_request[0] = 0x6e524635;
        // magnet();
        CycleActivity.update();
        TerminalActivity.update();
    }
}

fn lightSensor() noreturn {
    var wait: TimeKeeper = undefined;
    wait.prepare(2 * 1000 * 1000);

    Gpio.registers.direction_set = Gpio.registers_masks.three_led_anodes | Gpio.registers_masks.nine_led_cathodes_active_low;
    Gpio.registers.out_clear = Gpio.registers_masks.three_led_anodes | Gpio.registers_masks.nine_led_cathodes_active_low;

    while (true) {
        Wdt.reload_request_registers.reload_request[0] = 0x6e524635;
        var col: u32 = 1;
        while (col <= 3) : (col += 1) {
            literal("col{} ", .{col});
            Gpio.registers.out_clear = Gpio.registers_masks.three_led_anodes | Gpio.registers_masks.nine_led_cathodes_active_low;
            const column_mask = @as(u32, 0x10) << @truncate(u5, col - 1);
            Gpio.registers.out_set = column_mask;
            Gpio.registers.direction_clear = column_mask;

            var ain: u32 = 5;
            while (ain <= 7) : (ain += 1) {
                Adc.registers.enable = 0;
                Adc.registers.config = 2 | (2 << @ctz(u32, Adc.registers_config_masks.inpsel) | (@as(u32, 1) << @truncate(u5, ain)) << @ctz(u32, Adc.registers_config_masks.psel));
                Adc.registers.enable = 1;

                Adc.tasks.start = 1;
                while (Adc.busy_registers.busy != 0) {}
                literal("ain{} {} ", .{ ain, Adc.registers.result });
            }
            log("", .{});
        }
        wait.wait();
    }
}

const Accel = struct {
    var self_test_enabled = false;

    fn readBlocking(data: []u8, first: u32, last: u32) void {
        if (I2c0.readBlocking(device, first, data[first .. last + 1])) |_| {
            log("accel 0x{x}-0x{x}: 0x{x}", .{ 0x100 | first, 0x100 | last, data[first .. last + 1] });
        } else |err| {
            if (err == error.I2cErrorSourceRegister and I2c0.errorsrc_registers.errorsrc == 2) {
                I2c0.errorsrc_registers.errorsrc = 2;
                log("accel read 0x{x} address nack", .{device});
            } else {
                panicf("accel read 0x{x} {} errorsrc 0x{x}", .{ device, err, I2c0.errorsrc_registers.errorsrc });
            }
        }
    }

    fn toggleSelfTest() void {
        self_test_enabled = !self_test_enabled;
        var data_buf: [0x32]u8 = undefined;
        data_buf[0x2b] = if (self_test_enabled) 0x80 else 0x00;
        writeBlocking(&data_buf, 0x2b, 0x2b);
    }

    fn writeBlocking(data: []u8, first: u32, last: u32) void {
        if (I2c0.writeBlocking(device, first, data[first .. last + 1])) |_| {} else |err| {
            if (err == error.I2cErrorSourceRegister and I2c0.errorsrc_registers.errorsrc == 2) {
                I2c0.errorsrc_registers.errorsrc = 2;
                log("accel write 0x{x} address nack", .{device});
            } else {
                panicf("accel write 0x{x} {} errorsrc 0x{x}", .{ device, err, I2c0.errorsrc_registers.errorsrc });
            }
        }
    }

    fn prepare() void {
        var data_buf: [0x32]u8 = undefined;
        readBlocking(&data_buf, 0x0b, 0x0b);
        data_buf[0x2a] = 0x01;
        writeBlocking(&data_buf, 0x2a, 0x2a);
        data_buf[0x11] = 0x40;
        writeBlocking(&data_buf, 0x11, 0x11);
    }

    fn update() void {
        var data_buf: [0x32]u8 = undefined;
        readBlocking(&data_buf, 0x00, 0x06);
        // readBlocking(&data_buf, 0x0b, 0x0e);
        readBlocking(&data_buf, 0x0b, 0x0b);
        readBlocking(&data_buf, 0x10, 0x10);
        readBlocking(&data_buf, 0x15, 0x15);
        readBlocking(&data_buf, 0x2a, 0x2a);
        readBlocking(&data_buf, 0x2b, 0x2b);
        // readBlocking(&data_buf, 0x0c, 0x0c);
        // readBlocking(&data_buf, 0x0d, 0x0d);
        // readBlocking(&data_buf, 0x0e, 0x0e);
        // readBlocking(&data_buf, 0x10, 0x18);
        // readBlocking(&data_buf, 0x29, 0x31);
    }

    const device = 0x1d;
};

fn magnet() void {
    var i2c_address: u32 = 0x1e;
    while (i2c_address == 0x1e) : (i2c_address += 1) {
        var data_buf: [0]u8 = undefined;
        if (I2c0.readBlocking(i2c_address, 0x00, &data_buf)) |_| {
            log("i2c address {x} data {x}", .{ i2c_address, &data_buf });
        } else |err| {
            if (err == error.I2cErrorSourceRegister and I2c0.errorsrc_registers.errorsrc == 2) {
                I2c0.errorsrc_registers.errorsrc = 2;
                log("address nack {x}", .{i2c_address});
            } else {
                panicf("i2c address {x} scan {} {}", .{ i2c_address, err, I2c0.errorsrc_registers.errorsrc });
            }
        }
    }
}

fn scanI2c() void {
    var wait: TimeKeeper = undefined;
    wait.prepare(100 * 1000);
    var i2c_address: u32 = 0;
    while (i2c_address <= 127) : (i2c_address += 1) {
        var data_buf: [1]u8 = undefined;
        if (I2c0.readBlocking(i2c_address, 0, &data_buf)) |_| {
            log("i2c_address {x} data {x}", .{ i2c_address, data_buf[0] });
        } else |err| {
            if (err == error.I2cErrorSourceRegister and I2c0.errorsrc_registers.errorsrc == 2) {
                I2c0.errorsrc_registers.errorsrc = 2;
            } else {
                panicf("i2c scan address {x} {} {}", .{ i2c_address, err, I2c0.errorsrc_registers.errorsrc });
            }
        }
        // wait.wait();
    }
}

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
        LedMatrix.update();
        cycle_counter += 1;
        const new_cycle_start = Timer0.capture();
        if (last_cycle_start) |start| {
            cycle_time = new_cycle_start -% start;
            max_cycle_time = math.max(cycle_time, max_cycle_time);
        }
        last_cycle_start = new_cycle_start;
        if (up_timer.isFinished()) {
            up_timer.reset();
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
        Temperature.tasks.start = 1;
        redraw();
    }

    fn redraw() void {
        Terminal.clearScreen();
        Terminal.setScrollingRegion(5, 99);
        Terminal.move(5 - 1, 1);
        log("keyboard input will be echoed below:", .{});
    }

    fn update() void {
        if (Uart.isReadByteReady()) {
            const byte = Uart.readByte();
            switch (byte) {
                12 => {
                    redraw();
                },
                27 => {
                    Uart.writeByteBlocking('$');
                    keyboard_column += 1;
                },
                't' => {
                    Accel.toggleSelfTest();
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
        if (Temperature.events.data_ready != 0) {
            Temperature.events.data_ready = 0;
            temperature = Temperature.registers.temperature;
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

comptime {
    asm (typicalVectorTable(mission));
}

const mission = 4;

usingnamespace @import("use00_typical_mission.zig").typical;
