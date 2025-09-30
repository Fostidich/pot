const std = @import("std");
const print = std.debug.print;
const posix = std.posix;
const builtin = @import("builtin");

const files = @import("files.zig");

pub fn startProgram(name: []const u8) !void {
    const allocator = std.heap.page_allocator;

    // get script file
    const script_path = try files.getScriptFilePath(allocator, name);
    defer allocator.free(script_path);
    const file_exists = try files.checkFileExists(script_path);
    if (!file_exists) {
        print("{s} not found\n", .{name});
        return;
    }

    // check not already active
    var active_procs = try files.getActivePrograms(allocator);
    defer active_procs.deinit();
    if (active_procs.get(name)) |pid| {
        print("{s} already active ({})\n", .{ name, pid });
        return;
    }

    // fork and start process
    const pid = try spawnDetached(allocator, script_path);

    // return if child, store pid if parent
    if (pid == 0) {
        return;
    } else {
        print("{s} started\n", .{name});
        try files.addProgramToActives(allocator, name, pid);
    }
}

pub fn stopProgram(name: []const u8) !void {
    const allocator = std.heap.page_allocator;

    // get process pid if active
    var active_procs = try files.getActivePrograms(allocator);
    defer active_procs.deinit();
    const pid = active_procs.get(name) orelse {
        print("{s} not active\n", .{name});
        return;
    };

    // kill process session
    try posix.kill(-pid, 9);
    print("{s} stopped\n", .{name});

    // remove from the active files
    _ = active_procs.remove(name);
    try files.overrideActivePrograms(allocator, active_procs);
}

fn spawnDetached(allocator: std.mem.Allocator, path: []const u8) !i32 {
    // fork process and make the parent return
    const pid = try posix.fork();
    if (pid != 0) {
        // return session leader pid
        return pid;
    }

    // make process session leader
    _ = try posix.setsid();

    // detach from terminal
    const dev_null = try std.fs.cwd().openFile("/dev/null", .{ .mode = .read_write });
    defer dev_null.close();
    try posix.dup2(dev_null.handle, posix.STDIN_FILENO);
    try posix.dup2(dev_null.handle, posix.STDOUT_FILENO);
    try posix.dup2(dev_null.handle, posix.STDERR_FILENO);

    // start script command
    const shell_path = switch (builtin.os.tag) {
        .macos => "/bin/zsh",
        else => "/bin/bash",
    };
    const args = &[_][]const u8{
        shell_path,
        path,
    };
    var proc = std.process.Child.init(args, allocator);
    try proc.spawn();

    // should return 0 as child
    return pid;
}
