pub fn build(b: *Builder) void {
    const arch = builtin.Arch{ .thumb = builtin.Arch.Arm32.v6m };
    const environ = builtin.Abi.none;
    const exec_name = "main";
    const mode = b.standardReleaseOptions();
    const os = builtin.Os.freestanding;

    const exe = b.addExecutable(exec_name, "mission00_mission_selector.zig");
    exe.installRaw("main.img");
    exe.setBuildMode(mode);
    exe.setLinkerScriptPath("linker.ld");
    exe.setTarget(arch, os, environ);

    const run_makehex = b.addSystemCommand(&[_][]const u8{
        "zig", "run", "makehex.zig",
    });
    run_makehex.step.dependOn(&exe.step);

    b.default_step.dependOn(&run_makehex.step);
}

const Builder = std.build.Builder;
const builtin = @import("builtin");
const std = @import("std");
