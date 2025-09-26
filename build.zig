const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create a root module for the executable
    const root_mod = b.addModule("main", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Use root_module instead of root_source_file
    const exe = b.addExecutable(.{
        .name = "pot",
        .root_module = root_mod,
    });

    b.installArtifact(exe);
}
