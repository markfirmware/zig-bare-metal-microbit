const Key = union(enum) {
    Home: void,
    End: void,
    Up: void,
    Down: void,
    Left: void,
    Right: void,
    F: u8,
    U8: u8,
    Seq: Args,
    fn ctrl(byte: u8) Key {
        return Key{ .U8 = byte & 0x3f };
    }
    fn f(n: u8) Key {
        return Key{ .F = n };
    }
    fn k(byte: u8) Key {
        return Key{ .U8 = byte };
    }
    const Args = struct {
        args: [3]?u32 = undefined,
        len: u8 = 0,
        terminator: u8 = undefined,
        fn add(self: *Args, n: ?u32) void {
            self.args[self.len] = n;
            self.len += 1;
        }
        pub fn format(self: Args, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: var) !void {
            var i: u32 = 0;
            while (i < self.len) : (i += 1) {
                if (self.args[i]) |x| {
                    try out_stream.print("{}", .{x});
                } else {
                    try out_stream.print("null", .{});
                }
                if (i < self.len - 1) {
                    try out_stream.print(";", .{});
                }
            }
            const s = [_]u8{self.terminator};
            try out_stream.print("{}", .{s});
        }
    };
    const Esc = k(27);
};

fn main() callconv(.C) noreturn {
    Bss.prepare();
    Exceptions.prepare();
    Mission.prepare();
    Uart.prepare();
    Timers[0].prepare();
    LedMatrix.prepare();

    CycleActivity.prepare();
    KeyboardActivity.prepare();
    StatusActivity.prepare();

    Mission.register("turn on all leds without libraries", "mission1_turn_on_all_leds_without_libraries.zig");
    Mission.register("model railroad motor pwm controlled by buttons", "mission2_model_railroad_pwm.zig");
    Mission.register("sensors - temperature,  orientation", "mission3_sensors.zig");
    log("available missions:", .{});
    for (Mission.missions) |*m, i| {
        log("{}. {}", .{ i + 1, m.title });
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
        const new_cycle_start = Timers[0].captureAndRead();
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
    var escape: []u8 = undefined;
    var escape_buf: [20]u8 = undefined;
    var escape_elapsed_time: u32 = undefined;
    var escape_ready: bool = undefined;
    var max: u32 = undefined;
    var pending: ?u8 = undefined;

    fn getEscape() ?[]u8 {
        if (escape_ready) {
            escape_ready = false;
            return escape;
        } else {
            return null;
        }
    }

    fn waitEscape() []u8 {
        const start = Timers[0].captureAndRead();
        while (true) {
            Uart.loadTxd();
            if (getEscape()) |e| {
                return e;
            }
            update();
            if (Timers[0].captureAndRead() -% start >= 10 * 1000) {
                return "";
            }
        }
    }

    fn prepare() void {
        column = 1;
        escape_ready = false;
        pending = null;
    }

    fn receiveEscape() void {
        escape = "";
        var start = Timers[0].captureAndRead();
        var last = start;
        max = 0;
        var now: u32 = undefined;
        while (!escape_ready) {
            now = Timers[0].captureAndRead();
            if (Uart.isReadByteReady()) {
                const byte = Uart.readByte();
                max = math.max(max, now -% last);
                last = now;
                if (byte == 27) {
                    if (escape.len == 0) {
                        setPending(27);
                    } else {
                        log("escape interrupted {} {} {}us {}us", .{ escape.len, escape, now -% start, max });
                    }
                    escape = "";
                } else {
                    escape = escape_buf[0 .. escape.len + 1];
                    escape[escape.len - 1] = byte;
                    if (byte != 'O' and (byte == '~' or byte >= 'a' and byte <= 'z' or byte >= 'A' and byte <= 'Z')) {
                        escape_ready = true;
                    }
                }
            } else {
                LedMatrix.update();
            }
            if (now -% last >= 2 * 1000) {
                escape_ready = true;
            }
        }
        escape_elapsed_time = now -% start;
    }

    fn setPending(b: u8) void {
        if (pending) |p| {
            log("overrun discarded key {}", .{p});
        } else {
            pending = b;
        }
    }

    fn update() void {
        if (escape_ready or !(Uart.isReadByteReady() or pending != null)) {
            return;
        }
        var byte: u8 = undefined;
        if (pending) |b| {
            byte = b;
            pending = null;
        } else {
            byte = Uart.readByte();
        }
        switch (byte) {
            3 => {
                SystemControlBlock.requestSystemReset();
            },
            12 => {
                StatusActivity.redraw();
            },
            27 => {
                receiveEscape();
            },
            'b' => {
                LedMatrix.putImage(0x01ffffff);
            },
            'd' => {
                LedMatrix.putImage(0x00000000);
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
    var height: u32 = undefined;
    var prev_now: u32 = undefined;
    var width: u32 = undefined;

    fn getCursorPositionBlocking() []u8 {
        Terminal.requestCursorPosition();
        return KeyboardActivity.waitEscape();
    }

    fn parseEscape(escape: []u8) ?Key {
        var key: ?Key = null;
        if (escape.len == 2 and escape[0] == 'O') {
            if (escape[1] >= 'P' and escape[1] <= 'S') {
                key = Key.f(escape[1] - 'P' + 1);
            }
        } else if (escape.len == 2 and escape[0] == '[') {
            switch (escape[1]) {
                'A' => {
                    key = Key.Up;
                },
                'B' => {
                    key = Key.Down;
                },
                'C' => {
                    key = Key.Right;
                },
                'D' => {
                    key = Key.Left;
                },
                else => {},
            }
        } else if (escape.len >= 2 and escape[0] == '[') {
            var args = Key.Args{};
            var number: ?u32 = null;
            var i: u32 = 1;
            while (i < escape.len and args.len < args.args.len) : (i += 1) {
                const c = escape[i];
                if (c >= '0' and c <= '9') {
                    var j = i + 1;
                    while (j < escape.len and escape[j] >= '0' and escape[j] <= '9') : (j += 1) {}
                    number = std.fmt.parseUnsigned(u32, escape[i..j], 10) catch unreachable;
                    i = j - 1;
                } else if (c == ';') {
                    args.add(number);
                    number = null;
                } else if (i == escape.len - 1 and (c == '~' or c >= 'a' and c <= 'z' or c >= 'A' and c <= 'Z')) {
                    args.add(number);
                    args.terminator = c;
                    key = Key{ .Seq = args };
                    break;
                } else {
                    break;
                }
            }
        }
        if (key == null) {
            log("escape <{}> {}us {}us", .{ escape, KeyboardActivity.escape_elapsed_time, KeyboardActivity.max });
        }
        return key;
    }

    fn prepare() void {
        prev_now = CycleActivity.up_time_seconds;
        height = 0;
        width = 0;
        updateScreenSize();
    }

    fn redraw() void {
        Terminal.clearScreen();
        Terminal.setScrollingRegion(5, 99);
        Terminal.move(5 - 1, 1);
        log("keyboard input will be echoed below:", .{});
    }

    fn update() void {
        Uart.loadTxd();
        if (KeyboardActivity.getEscape()) |escape| {
            const key = parseEscape(escape);
            log("{}", .{key});
        }
        const now = CycleActivity.up_time_seconds;
        if (now >= prev_now + 1) {
            Terminal.hideCursor();
            updateScreenSize();
            Terminal.move(1, 1);
            Terminal.line("up {:3}s cycle {}us max {}us", .{ CycleActivity.up_time_seconds, CycleActivity.cycle_time, CycleActivity.max_cycle_time });
            Terminal.line("screen {}x{}", .{ width, height });
            Terminal.line("", .{});
            Terminal.showCursor();
            restoreInputLine();
            prev_now = now;
        }
    }

    fn updateScreenSize() void {
        Terminal.move(999, 999);
        if (parseEscape(getCursorPositionBlocking())) |size| {
            if (size.Seq.terminator == 'R' and (size.Seq.args[0].? != height or size.Seq.args[1].? != width)) {
                width = size.Seq.args[1].?;
                height = size.Seq.args[0].?;
                redraw();
            }
        }
    }
};

fn restoreInputLine() void {
    Terminal.move(99, KeyboardActivity.column);
}

const Mission = struct {
    title: []const u8,
    panic: fn ([]const u8, ?*builtin.StackTrace) noreturn,
    vector_table_address: *allowzero const u32,

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
              [reset_sp] "{r1}" (reset_sp)
        );
    }

    fn prepare() void {
        missions = missions_buf[0..0];
    }

    fn register(comptime title: []const u8, comptime source_file: []const u8) void {
        missions = missions_buf[0 .. missions.len + 1];
        var m = &missions[missions.len - 1];
        const import = @import(source_file);
        m.title = title;
        m.panic = import.panic;
        m.vector_table_address = @ptrCast(*allowzero const u32, &import.vector_table);
    }
};

const release_tag = "0.4";
const status_display_lines = 6 + 5;

pub const mission_number: u32 = 0;

pub const vector_table linksection(".vector_table.primary") = simpleVectorTable(main);
comptime {
    @export(vector_table, .{ .name = "vector_table_mission0" });
}

usingnamespace @import("lib_basics.zig").typical;
