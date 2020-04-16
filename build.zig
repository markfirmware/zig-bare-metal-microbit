pub fn build(b: *Builder) !void {
    const exec_name = "main";
    const mode = b.standardReleaseOptions();
    const main_program = b.option([]const u8, "main", "main file") orelse "mission0_mission_selector.zig";
    const want_display = b.option(bool, "display", "graphics display for qemu") orelse false;
    const exe = b.addExecutable(exec_name, main_program);
    exe.install();
    exe.installRaw("main.img");
    exe.setBuildMode(mode);
    exe.setLinkerScriptPath("linker.ld");
    exe.setTarget(model.target);
    exe.link_function_sections = true;

    const run_makehex = addCustom(b, MakeHexStep{ .input_name = "zig-cache/bin/main.img", .output_name = "main.hex" });
    run_makehex.step.dependOn(&exe.step);

    const qemu = b.step("qemu", "run in qemu");
    const run_qemu = b.addSystemCommand(&[_][]const u8{
        "qemu-system-arm",
        "-kernel",
        "zig-cache/bin/main.img",
        "-M",
        "microbit",
        "-serial",
        "stdio",
        "-display",
        if (want_display) "gtk" else "xnone",
    });
    qemu.dependOn(&run_qemu.step);
    run_qemu.step.dependOn(&exe.step);

    b.default_step.dependOn(&run_makehex.step);
}

pub const model = struct {
    pub const flash = MemoryRegion{ .start = 0, .size = 256 * 1024 };
    pub const initial_sp = @intToPtr(fn () callconv(.C) noreturn, ram.start + ram.size);
    pub const number_of_peripherals = 32;
    pub const options = struct {
        pub const low_frequency_crystal = false;
        pub const systick_timer = false;
        pub const vector_table_relocation_register = false;
    };
    pub const ram = MemoryRegion{ .start = 0x20000000, .size = 16 * 1024 };
    pub const target = std.zig.CrossTarget{
        .cpu_arch = .thumb,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = &std.Target.arm.cpu.cortex_m0 },
    };
    const MemoryRegion = struct {
        start: u32,
        size: u32,
    };
};

const MakeHexStep = struct {
    step: std.build.Step = undefined,
    input_name: []const u8,
    output_name: []const u8,

    pub fn make(step: *std.build.Step) anyerror!void {
        const self = @fieldParentPtr(MakeHexStep, "step", step);
        const cwd = fs.cwd();
        const image = try cwd.openFile(self.input_name, fs.File.OpenFlags{});
        defer image.close();
        const hex = try cwd.createFile(self.output_name, fs.File.CreateFlags{});
        defer hex.close();
        var offset: usize = 0;
        var read_buf: [model.flash.size]u8 = undefined;
        while (true) {
            var n = try image.read(&read_buf);
            if (n == 0) {
                break;
            }
            while (offset < n) {
                if (offset % 0x10000 == 0) {
                    try writeHexRecord(hex, 0, 0x04, &[_]u8{ @truncate(u8, offset >> 24), @truncate(u8, offset >> 16) });
                }
                const i = std.math.min(hex_record_len, n - offset);
                try writeHexRecord(hex, offset % 0x10000, 0x00, read_buf[offset .. offset + i]);
                offset += i;
            }
        }
        try writeHexRecord(hex, 0, 0x01, &[_]u8{});
    }
    fn writeHexRecord(file: fs.File, offset: usize, code: u8, bytes: []u8) !void {
        var record_buf: [1 + 2 + 1 + hex_record_len + 1]u8 = undefined;
        var record: []u8 = record_buf[0 .. 1 + 2 + 1 + bytes.len + 1];
        record[0] = @truncate(u8, bytes.len);
        record[1] = @truncate(u8, offset >> 8);
        record[2] = @truncate(u8, offset >> 0);
        record[3] = code;
        for (bytes) |b, i| {
            record[4 + i] = b;
        }
        var checksum: u8 = 0;
        for (record[0 .. record.len - 1]) |b| {
            checksum = checksum -% b;
        }
        record[record.len - 1] = checksum;
        var line_buf: [1 + record_buf.len * 2 + 1]u8 = undefined;
        _ = try file.write(try std.fmt.bufPrint(&line_buf, ":{X}\n", .{record}));
    }
    const hex_record_len = 32;
};

const Builder = std.build.Builder;
const fs = std.fs;
const std = @import("std");
const Step = std.build.Step;

pub fn addCustom(self: *Builder, customStep: var) *@TypeOf(customStep) {
    var allocated = self.allocator.create(@TypeOf(customStep)) catch unreachable;
    allocated.* = customStep;
    allocated.*.step = Step.init(@typeName(@TypeOf(customStep)), self.allocator, @TypeOf(customStep).make);
    return allocated;
}
