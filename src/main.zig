const std = @import("std");
const print = std.debug.print;

const files = @import("files.zig");
const commands = @import("commands.zig");

const Command = enum {
    unknown,
    help,
    version,
    set,
    delete,
    start,
    stop,
    list,
};

const version = "1.1";

pub fn main() void {
    const allocator = std.heap.page_allocator;

    // init files module
    files.init(allocator) catch |err| abort(err);
    files.createRequiredDir() catch |err| abort(err);

    // retrieve args
    const args = std.process.argsAlloc(allocator) catch |err| abort(err);
    defer std.process.argsFree(allocator, args);

    // parse command
    const command = if (args.len <= 1) Command.list else std.meta.stringToEnum(Command, args[1]) orelse .unknown;

    // switch commands
    switch (command) {
        .unknown => print(
            \\Unknown command: {s}
            \\Use "pot help" for a list of available commands
            \\
        , .{args[1]}),
        .help => print(
            \\Use "pot" followed by one of the following commands
            \\
            \\  pot help            Show this very panel
            \\  pot version         Show version
            \\  pot set <name>      Set a new program
            \\  pot delete <name>   Delete a program
            \\  pot start <name>    Start a program
            \\  pot stop <name>     Stop a running program
            \\  pot                 Show all programs
            \\
            \\
        , .{}),
        .version => print(
            \\Version: {s}
            \\
        , .{version}),
        .set => commandWithName(args, commands.setProgram),
        .delete => commandWithName(args, commands.deleteProgram),
        .start => commandWithName(args, commands.startProgram),
        .stop => commandWithName(args, commands.stopProgram),
        .list => commands.listPrograms() catch |err| abort(err),
    }
}

inline fn commandWithName(args: []const []const u8, command: fn ([]const u8) anyerror!void) void {
    if (args.len > 2) {
        command(args[2]) catch |err| abort(err);
    } else {
        print(
            \\No program name provided
            \\Usage: "pot {s} <name>"
            \\
        , .{args[1]});
    }
}

inline fn abort(err: anyerror) noreturn {
    std.debug.print("Error: {}\n", .{err});
    std.process.exit(1);
}
