pub fn build(b: *Builder) void {
    const arch = builtin.Arch{ .thumb = builtin.Arch.Arm32.v6m };
    const environ = builtin.Abi.none;
    const exec_name = "main";
    const mode = b.standardReleaseOptions();
    const os = builtin.Os.freestanding;
    const main = b.option([]const u8, "main", "main file") orelse "mission00_mission_selector.zig";
    const want_display = b.option(bool, "display", "graphics display for qemu") orelse false;

    const exe = b.addExecutable(exec_name, main);
    exe.install();
    exe.installRaw("main.img");
    exe.setBuildMode(mode);
    exe.setLinkerScriptPath("linker.ld");
    exe.setTarget(arch, os, environ);

    const run_makehex = b.addSystemCommand(&[_][]const u8{
        "zig", "run", "makehex.zig",
    });
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

const Builder = std.build.Builder;
const builtin = @import("builtin");
const std = @import("std");
