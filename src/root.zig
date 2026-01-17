const std = @import("std");

const Term = @import("term.zig");
const Editor = @import("editor.zig");
const commands = @import("commands/dynamic.zig");

pub const version: std.SemanticVersion = .{ .major = 0, .minor = 0, .patch = 0 };

pub const std_options: std.Options = .{
    .fmt_max_depth = 10,
};

/// Initialize state and start the text editor.
pub fn run(path: ?[]const u8) !void {
    var buffer: [1024]u8 = undefined;
    var terminal = try Term.init(&buffer);
    defer terminal.deinit() catch |e| {
        // WARN: This should be the ONLY `noreturn` in the program!
        std.debug.panic("Failed to disable raw mode: {}", .{e});
    };

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var editor: Editor = try .init(allocator, terminal);
    defer {
        editor.deinit(allocator);
        std.debug.assert(gpa.deinit() != .leak);
    }

    if (path) |argPath| {
        try commands.open(&editor, argPath);
    }
    try terminal.enableRawMode();
    while (true) {
        try editor.refresh();
    }
}
