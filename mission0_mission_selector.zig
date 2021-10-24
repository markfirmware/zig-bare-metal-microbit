export fn mission0_main() noreturn {
    Bss.prepare();
    Exceptions.prepare();
    Mission.prepare();
    Uart.prepare();
    Timer0.prepare();
    Timer1.prepare();
    Timer2.prepare();
    LedMatrix.prepare();

    CycleActivity.prepare();
    KeyboardActivity.prepare();
    StatusActivity.prepare();

    Mission.register(&mission1_vector_table, "turn on all leds without libraries", "mission1_turn_on_all_leds_without_libraries.zig");
    Mission.register(&mission2_vector_table, "model railroad motor pwm controlled by buttons", "mission2_model_railroad_pwm.zig");
    Mission.register(&mission3_vector_table, "sensors - temperature,  orientation", "mission3_sensors.zig");
    log("available missions:", .{});
    for (Mission.missions) |*m, i| {
        log("{}. {s}", .{ i + 1, m.title });
    }

    while (true) {
        CycleActivity.update();
        KeyboardActivity.update();
        StatusActivity.update();
    }
}

const CycleActivity = struct {
    var cycle_counter: u32 = undefined;
    var cycle_time: u32 = undefined;
    var last_cycle_start: ?u32 = undefined;
    var last_second_ticks: u32 = undefined;
    var max_cycle_time: u32 = undefined;
    var up_time_seconds: u32 = undefined;

    fn prepare() void {
        cycle_counter = 0;
        cycle_time = 0;
        last_cycle_start = null;
        last_second_ticks = 0;
        max_cycle_time = 0;
        up_time_seconds = 0;
    }

    fn update() void {
        LedMatrix.update();
        cycle_counter += 1;
        const new_cycle_start = Timer0.capture();
        if (new_cycle_start -% last_second_ticks >= 1000 * 1000) {
            up_time_seconds += 1;
            last_second_ticks = new_cycle_start;
        }
        if (last_cycle_start) |start| {
            cycle_time = new_cycle_start -% start;
            max_cycle_time = math.max(cycle_time, max_cycle_time);
        }
        last_cycle_start = new_cycle_start;
    }
};

const KeyboardActivity = struct {
    var column: u32 = undefined;

    fn prepare() void {
        column = 1;
    }

    fn update() void {
        if (!Uart.isReadByteReady()) {
            return;
        }
        const byte = Uart.readByte();
        switch (byte) {
            3 => {
                SystemControlBlock.requestSystemReset();
            },
            12 => {
                StatusActivity.redraw();
            },
            27 => {
                Uart.writeByteBlocking('$');
                column += 1;
            },
            '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                Mission.missions[byte - '1'].activate();
            },
            '\r' => {
                Uart.writeText("\n");
                column = 1;
            },
            else => {
                Uart.writeByteBlocking(byte);
                column += 1;
            },
        }
    }
};

const StatusActivity = struct {
    var prev_now: u32 = undefined;

    fn prepare() void {
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
        Uart.loadTxd();
        const now = CycleActivity.up_time_seconds;
        if (now >= prev_now + 1) {
            Terminal.hideCursor();
            Terminal.move(1, 1);
            Terminal.line("reset {x} up {:3}s cycle {}us max {}us", .{ Power.registers.reset_reason, CycleActivity.up_time_seconds, CycleActivity.cycle_time, CycleActivity.max_cycle_time });
            Terminal.line("gpio.in {x:8}", .{Gpio.registers.in & ~@as(u32, 0x0300fff0)});
            Terminal.line("", .{});
            Terminal.showCursor();
            restoreInputLine();
            prev_now = now;
        }
    }
};

fn restoreInputLine() void {
    Terminal.move(99, KeyboardActivity.column);
}

const Mission = struct {
    title: []const u8,
    panic: fn ([]const u8, ?*builtin.StackTrace) noreturn,
    vector_table_address: *allowzero u32,

    var missions: []Mission = undefined;
    var missions_buf: [5]Mission = undefined;

    fn activate(self: *Mission) void {
        const reset_sp = @intToPtr(*allowzero u32, @ptrToInt(self.vector_table_address) + 0).*;
        const reset_pc = @intToPtr(*allowzero u32, @ptrToInt(self.vector_table_address) + 4).*;
        asm volatile (
            \\ mov sp,%[reset_sp]
            \\ bx %[reset_pc]
            :
            : [reset_pc] "{r0}" (reset_pc),
              [reset_sp] "{r1}" (reset_sp),
        );
    }

    fn prepare() void {
        missions = missions_buf[0..0];
    }

    fn register(vector_table_address: *allowzero u32, comptime title: []const u8, comptime source_file: []const u8) void {
        missions = missions_buf[0 .. missions.len + 1];
        var m = &missions[missions.len - 1];
        const import = @import(source_file);
        m.title = title;
        m.panic = import.panic;
        m.vector_table_address = vector_table_address;
    }
};

comptime {
    const mission_id = 0;
    asm (typicalVectorTable(mission_id));
}

const release_tag = "0.4";
const status_display_lines = 6 + 5;

extern var mission1_vector_table: u32;
extern var mission2_vector_table: u32;
extern var mission3_vector_table: u32;

usingnamespace @import("lib_basics.zig").typical;
