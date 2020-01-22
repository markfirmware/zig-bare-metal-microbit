export fn mission05_main() noreturn {
    Bss.prepare();
    Exceptions.prepare();
    Timer0.prepare();
    Timer1.prepare();
    Timer2.prepare();
    LedMatrix.prepare();
    ClockManagement.prepareHf();
    Uart.prepare();

    CycleActivity.prepare();
    TerminalActivity.prepare();

    while (true) {
        CycleActivity.update();
        TerminalActivity.update();
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
        }
    }
};

const TerminalActivity = struct {
    var keyboard_column: u32 = undefined;
    var prev_now: u32 = undefined;

    fn prepare() void {
        keyboard_column = 1;
        prev_now = CycleActivity.up_time_seconds;
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
                27 => {
                    Uart.writeByteBlocking('$');
                    keyboard_column += 1;
                },
                12 => {
                    redraw();
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
            Terminal.line("up {:3}s cycle {}us max {}us", .{ CycleActivity.up_time_seconds, CycleActivity.cycle_time, CycleActivity.max_cycle_time });
            Terminal.showCursor();
            Terminal.move(99, keyboard_column);
            prev_now = now;
        }
    }
};

comptime {
    asm (typicalVectorTable(mission));
}

const mission = 5;

usingnamespace @import("use00_typical_mission.zig").typical;
