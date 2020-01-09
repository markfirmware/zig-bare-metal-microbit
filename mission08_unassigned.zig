export fn mission08_main() noreturn {
    Bss.prepare();
    Exceptions.prepare();
    Timer0.prepare();
    Timer1.prepare();
    Timer2.prepare();
    LedMatrix.prepare();
    ClockManagement.prepareHf();
    Uart.prepare();

    cycle_activity.prepare();
    terminal_activity.prepare();

    while (true) {
        cycle_activity.update();
        terminal_activity.update();
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
        if (self.last_cycle_start) |start| {
            self.cycle_time = new_cycle_start -% start;
            self.max_cycle_time = std.math.max(self.cycle_time, self.max_cycle_time);
        }
        self.last_cycle_start = new_cycle_start;
        if (self.up_timer.isFinished()) {
            self.up_timer.reset();
            self.up_time_seconds += 1;
        }
    }
};

const TerminalActivity = struct {
    keyboard_column: u32,
    prev_now: u32,

    fn prepare(self: *TerminalActivity) void {
        self.keyboard_column = 1;
        self.prev_now = cycle_activity.up_time_seconds;
        self.redraw();
    }

    fn redraw(self: *TerminalActivity) void {
        Terminal.clearScreen();
        Terminal.setScrollingRegion(5, 99);
        Terminal.move(5 - 1, 1);
        log("keyboard input will be echoed below:", .{});
    }

    fn update(self: *TerminalActivity) void {
        if (Uart.isReadByteReady()) {
            const byte = Uart.readByte();
            switch (byte) {
                27 => {
                    Uart.writeByteBlocking('$');
                    self.keyboard_column += 1;
                },
                12 => {
                    self.redraw();
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
            Terminal.line("up {:3}s cycle {}us max {}us", .{ cycle_activity.up_time_seconds, cycle_activity.cycle_time, cycle_activity.max_cycle_time });
            Terminal.showCursor();
            Terminal.move(99, self.keyboard_column);
            self.prev_now = now;
        }
    }
};

comptime {
    asm (
        \\.section .text.start.mission08
        \\.globl mission08_vector_table
        \\.balign 0x80
        \\mission08_vector_table:
        \\ .long 0x20004000 // sp top of 16KB ram
        \\ .long mission08_main
        \\ .long lib00_exceptionNumber02
        \\ .long lib00_exceptionNumber03
        \\ .long lib00_exceptionNumber04
        \\ .long lib00_exceptionNumber05
        \\ .long lib00_exceptionNumber06
        \\ .long lib00_exceptionNumber07
        \\ .long lib00_exceptionNumber08
        \\ .long lib00_exceptionNumber09
        \\ .long lib00_exceptionNumber10
        \\ .long lib00_exceptionNumber11
        \\ .long lib00_exceptionNumber12
        \\ .long lib00_exceptionNumber13
        \\ .long lib00_exceptionNumber14
        \\ .long lib00_exceptionNumber15
    );
}

const builtin = @import("builtin");
const std = @import("std");

pub const panic = lib00_panic;

usingnamespace @import("lib00_basics.zig");

var cycle_activity: CycleActivity = undefined;
var terminal_activity: TerminalActivity = undefined;
