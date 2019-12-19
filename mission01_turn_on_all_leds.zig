export fn mission01_main() noreturn {
    turnOnAllLeds();
    while (true) {}
}

fn turnOnAllLeds() void {
    const all_led_rows_mask: u32 = 0xe000;
    const all_led_cols_mask: u32 = 0x1ff0;
    const all_led_pins_mask = all_led_rows_mask | all_led_cols_mask;
    const gpio_direction_set = @intToPtr(*volatile u32, 0x50000518);
    const gpio_out_clear = @intToPtr(*volatile u32, 0x5000050c);
    const gpio_out_set = @intToPtr(*volatile u32, 0x50000508);
    gpio_direction_set.* = all_led_pins_mask;
    gpio_out_set.* = all_led_rows_mask;
    gpio_out_clear.* = all_led_cols_mask;
}

pub fn panic(message: []const u8, trace: ?*@import("builtin").StackTrace) noreturn {
    while (true) {}
}

comptime {
    asm (
        \\.section .text.start.mission01
        \\.globl mission01_vector_table
        \\.balign 0x80
        \\mission01_vector_table:
        \\ .long 0x20004000 - 4 // sp top of 16KB ram, 4 bytes reserved for mission control
        \\ .long mission01_main
    );
}
