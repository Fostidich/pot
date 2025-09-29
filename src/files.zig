const std = @import("std");
const print = std.debug.print;

const ActiveWithId = struct { pid: i32, name: []const u8 };

var scripts_dir: []const u8 = "";
var active_file: []const u8 = "";

pub fn init(allocator: std.mem.Allocator) !void {
    scripts_dir = try expandHomePath(allocator, "~/.local/pot/scripts/");
    active_file = try expandHomePath(allocator, "~/.local/pot/active");
}

pub fn addProgram(name: []const u8) !void {
    const allocator = std.heap.page_allocator;

    // construct path string
    const file_path = try getScriptFilePath(allocator, name);
    defer allocator.free(file_path);

    // try running nvim, nano otherwise
    var success = try openEditor(allocator, "nvim", file_path);
    if (!success) {
        success = try openEditor(allocator, "nano", file_path);
    }

    // log editor execution result
    if (success) {
        print("Command stored correctly\n", .{});
    } else {
        print("Command may not have been saved\n", .{});
    }
}

pub fn deleteProgram(name: []const u8) !void {
    const allocator = std.heap.page_allocator;

    // construct path string
    const file_path = try getScriptFilePath(allocator, name);
    defer allocator.free(file_path);

    // delete file
    std.fs.cwd().deleteFile(file_path) catch |err| switch (err) {
        error.FileNotFound => {
            print("{s} not found\n", .{name});
            return;
        },
        else => return err,
    };
    print("Deleted\n", .{});
}

pub fn listPrograms() !void {
    const allocator = std.heap.page_allocator;

    // retrieve dir data
    var dir = try std.fs.cwd().openDir(scripts_dir, .{ .iterate = true });
    defer dir.close();
    var it = dir.iterate();

    // match active ones
    var active_procs = try getActivePrograms(allocator);
    defer active_procs.deinit();

    // print entries if normal file
    while (try it.next()) |entry| {
        if (entry.kind == .file and entry.name[0] != '.') {
            if (active_procs.get(entry.name)) |pid| {
                print("active: {s} ({})\n", .{ entry.name, pid });
            } else {
                print("        {s}\n", .{entry.name});
            }
        }
    }
}

pub fn getActivePrograms(allocator: std.mem.Allocator) !std.StringHashMap(i32) {
    // prepare resulting content buffer
    var result = std.StringHashMap(i32).init(allocator);

    // open file
    const file = std.fs.cwd().openFile(active_file, .{}) catch |err| switch (err) {
        error.FileNotFound => return result,
        else => return err,
    };
    defer file.close();

    // prepare temp buffer and file reader
    var buf: [1024]u8 = undefined;
    var reader = file.reader(&buf);
    const r = &reader.interface;

    // read line by line until end of file
    while (true) {
        // get line string
        const line = r.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        // parse and append to result
        const entry = parseActiveLine(line) catch continue;
        try result.put(entry.name, entry.pid);
    }

    // return owned
    return result;
}

fn parseActiveLine(line: []const u8) !ActiveWithId {
    // parse pid and process name
    const first_space = std.mem.indexOfScalar(u8, line, ' ') orelse {
        return error.ActiveProcessParsingFailure;
    };
    const pid_str = line[0..first_space];
    const pid = try std.fmt.parseInt(i32, pid_str, 10);
    const name = line[first_space + 1 ..];

    // build and return entry
    return ActiveWithId{ .pid = pid, .name = name };
}

pub fn addProgramToActives(allocator: std.mem.Allocator, name: []const u8, pid: i32) !void {
    // open file for appending
    var file = std.fs.cwd().openFile(active_file, .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => try std.fs.cwd().createFile(active_file, .{}),
        else => return err,
    };
    defer file.close();

    // get string version of pid
    const pid_str = try std.fmt.allocPrint(allocator, "{}", .{pid});
    defer allocator.free(pid_str);

    // build line to append
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 8);
    defer buffer.deinit(allocator);
    try buffer.appendSlice(allocator, pid_str);
    try buffer.appendSlice(allocator, " ");
    try buffer.appendSlice(allocator, name);
    try buffer.appendSlice(allocator, "\n");
    const line = try buffer.toOwnedSlice(allocator);
    defer allocator.free(line);

    // append to file
    var buf: [1024]u8 = undefined;
    var writer = file.writer(&buf);
    try writer.seekTo(try writer.file.getEndPos());
    const w = &writer.interface;
    try w.print("{s}", .{line});
    try w.flush();
}

pub fn getScriptFilePath(allocator: std.mem.Allocator, filename: []const u8) ![]const u8 {
    // create var size buffer
    var path_buffer = try std.ArrayList(u8).initCapacity(allocator, 16);
    defer path_buffer.deinit(allocator);

    // append dir and filename
    try path_buffer.appendSlice(allocator, scripts_dir);
    try path_buffer.appendSlice(allocator, filename);

    // return owned
    return path_buffer.toOwnedSlice(allocator);
}

pub fn checkFileExists(path: []const u8) !bool {
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer file.close();
    return true;
}

pub inline fn createRequiredDir() !void {
    // create all parent directories
    try std.fs.cwd().makePath(scripts_dir);
}

fn openEditor(allocator: std.mem.Allocator, editor_name: []const u8, file_path: []const u8) !bool {
    // run editor command
    const editor_command = &[_][]const u8{ editor_name, file_path };
    var editor_process = std.process.Child.init(editor_command, allocator);
    try editor_process.spawn();

    // wait for it to finish
    const result = editor_process.wait() catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };

    // print exit result
    return switch (result) {
        .Exited => |code| code == 0,
        else => false,
    };
}

fn expandHomePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    // check that there actually is a tilde to expand at the start
    if (path.len == 0 or path[0] != '~') {
        return error.NoHomeToExpand;
    }

    // get home env var
    const home_dir = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home_dir);

    // construct path string
    var path_buffer = try std.ArrayList(u8).initCapacity(allocator, 16);
    defer path_buffer.deinit(allocator);
    try path_buffer.appendSlice(allocator, home_dir);
    try path_buffer.appendSlice(allocator, path[1..]);

    // return owned
    return path_buffer.toOwnedSlice(allocator);
}
