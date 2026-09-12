const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{ 
        .name = "z-weather-cli", 
        .root_source_file = .{ .path = "src/main.zig" }, 
        .target = target, 
        .optimize = optimize 
    });

    b.installFile(exe.getEmittedBin(), ".");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(exe.step);
    const run_step = b.step("run", "Run the app", run_cmd);
    b.main.dependOn(run_step);
}