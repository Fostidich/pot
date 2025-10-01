const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // create main module
    const root_mod = b.addModule("main", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // create executable
    const exe = b.addExecutable(.{
        .name = "pot",
        .root_module = root_mod,
    });

    b.installArtifact(exe);
}
