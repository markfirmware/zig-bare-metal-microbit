export fn mission1_main() noreturn {
    turnOnAllLeds();
    while (true) {}
}

pub fn panic(message: []const u8, trace: ?*@import("std").builtin.StackTrace) noreturn {
    while (true) {}
}

fn turnOnAllLeds() void {
    const gpio_direction_set = @intToPtr(*volatile u32, 0x50000518);
    const gpio_out_clear = @intToPtr(*volatile u32, 0x5000050c);
    const gpio_out_set = @intToPtr(*volatile u32, 0x50000508);
    const all_three_led_anode_pins_active_high: u32 = 0xe000;
    const all_nine_led_cathode_pins_active_low: u32 = 0x1ff0;
    gpio_direction_set.* = all_three_led_anode_pins_active_high | all_nine_led_cathode_pins_active_low;
    gpio_out_set.* = all_three_led_anode_pins_active_high;
    gpio_out_clear.* = all_nine_led_cathode_pins_active_low;
}

comptime {
    asm (
        \\.section .text.start.mission1
        \\.globl mission1_vector_table
        \\.balign 0x80
        \\mission1_vector_table:
        \\ .long 0x20004000 // sp top of 16KB ram
        \\ .long mission1_main
    );
}
