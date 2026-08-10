const std = @import("std");

const Editor = @import("editor.zig");
const Term = @import("term.zig");
const commands = @import("commands/dynamic.zig");

pub const version: std.SemanticVersion = .{ .major = 0, .minor = 0, .patch = 0 };

pub const std_options: std.Options = .{
    .fmt_max_depth = 10,
};

pub const panic = std.debug.FullPanic(cleanup);
fn cleanup(msg: []const u8, firstTraceAddr: ?usize) noreturn {
    Term.Term.handlePanic();
    std.debug.simple_panic.call(msg, firstTraceAddr);
}

/// Initialize state and start the text editor.
pub fn run(init: std.process.Init, path: ?[]const u8) !void {
    var buffer: [1024]u8 = undefined;
    var terminal = try Term.init(init, &buffer);
    defer terminal.deinit() catch |e| {
        // WARN: This should be the ONLY `noreturn` in the program!
        std.debug.panic("Failed to disable raw mode: {}", .{e});
    };

    var editor: Editor = try .init(init, terminal);
    defer editor.deinit();
    editor.status = "Welcome to Noe, Press Ctrl-Q to quit";

    if (path) |argPath| {
        try commands.open(&editor, argPath);
    }
    try terminal.enableRawMode();
    while (true) {
        try editor.refresh();
    }
}
