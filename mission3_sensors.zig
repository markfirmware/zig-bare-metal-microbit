export fn mission3_main() noreturn {
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
    Accel.prepare();

    while (true) {
        CycleActivity.update();
        TerminalActivity.update();
    }
}

const Accel = struct {
    fn prepare() void {
        var data_buf: [0x32]u8 = undefined;
        data_buf[orientation_configuration_register] = orientation_configuration_register_mask_enable;
        I2c0.writeBlockingPanic(device_address, &data_buf, orientation_configuration_register, orientation_configuration_register);
        data_buf[control_register1] = control_register1_mask_active;
        I2c0.writeBlockingPanic(device_address, &data_buf, control_register1, control_register1);
    }

    fn update() void {
        var data_buf: [32]u8 = undefined;
        I2c0.readBlockingPanic(device_address, &data_buf, orientation_register, orientation_register);
        const orientation = data_buf[orientation_register];
        if (orientation & orientation_register_mask_changed != 0) {
            literal("orientation: 0x{x} ", .{orientation});
            if (orientation & orientation_register_mask_forward_backward != 0) {
                literal("forward ", .{});
            } else {
                literal("backward ", .{});
            }
            if (orientation & orientation_register_mask_z_lock_out != 0) {
                log("up/down/left/right is unknown", .{});
            } else {
                const direction = (orientation & orientation_register_mask_direction) >> @ctz(u5, orientation_register_mask_direction);
                switch (direction) {
                    0 => { log("up", .{}); },
                    1 => { log("down", .{}); },
                    2 => { log("right", .{}); },
                    3 => { log("left", .{}); },
                    else => { unreachable; },
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
        Terminal.move(99, keyboard_column);
    }

    fn update() void {
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
    const mission_id = 3;
    asm (typicalVectorTable(mission_id));
}

usingnamespace @import("lib_basics.zig").typical;
