const std = @import("std");

const Term = @import("term.zig");
const Editor = @import("editor.zig");

pub const version: std.SemanticVersion = .{ .major = 0, .minor = 0, .patch = 0 };

/// Initialize state and start the text editor.
pub fn run(path: ?[:0]const u8) !void {
    _ = path;
    var buffer: [1024]u8 = undefined;
    var terminal = try Term.init(&buffer);

    try terminal.enableRawMode();
    defer terminal.deinit() catch |e| {
        // WARN: This should be the ONLY `noreturn` in the program!
        std.debug.panic("Failed to disable raw mode: {}", .{e});
    };

    var editor: Editor = .init(terminal);
    while (true) {
        try editor.refresh();
    }
}
