const std = @import("std");

const term = @import("term.zig");

pub const version: std.SemanticVersion = .{ .major = 0, .minor = 0, .patch = 0 };

/// Initialize state and start the text editor.
pub fn run(path: ?[:0]const u8) !void {
    _ = path;
    var buffer: [1024]u8 = undefined;
    var handle: term.Term = try .init(&buffer);

    try handle.enableRawMode();
    defer handle.disableRawMode() catch |e| {
        std.log.warn("Failed to disable raw mode: {}", .{e});
    };

    while (true) {
        const char = handle.takeByte() catch |err| {
            switch (err) {
                std.Io.Reader.Error.EndOfStream => continue,
                else => return err,
            }
        };
        if (char == 'q') break;

        if (std.ascii.isControl(char)) {
            try handle.super.writer.interface.print("{d}\r\n", .{char});
        } else {
            try handle.super.writer.interface.print("{d} ('{c}')\r\n", .{ char, char });
        }
        try handle.super.writer.interface.flush();
    }
}
