const std = @import("std");

const Editor = @import("../editor.zig");
const Rope = @import("../rope.zig");

pub const Error = error{ PathKindError, ReadError, RopeError } || std.mem.Allocator.Error;

/// The list of editor commands that require no arguments.
///
/// These commands can be assigned to keys or typed.
pub const Dynamic = union(enum) {
    Open,

    pub fn call(self: Dynamic, editor: *Editor, args: []u8) !void {
        return switch (self) {
            .Open => open(editor, args),
        };
    }
};

pub fn open(editor: *Editor, args: []const u8) Error!void {
    const cwd = std.fs.cwd().realpathAlloc(editor.private.allocator, ".") catch return Error.ReadError;
    const path = std.fs.cwd().realpathAlloc(editor.private.allocator, args) catch return Error.ReadError;
    const displayPath = if (std.mem.startsWith(u8, path, cwd)) path[cwd.len + 1 ..] else path;
    editor.private.allocator.free(cwd);
    const file = std.fs.openFileAbsolute(path, .{}) catch return Error.ReadError;
    const stat = file.stat() catch return Error.ReadError;

    switch (stat.kind) {
        // TODO: Follow symlink
        .sym_link => return Error.PathKindError,
        // TODO: display file browser
        .directory => return Error.PathKindError,
        .file => {
            defer file.close();

            var buffer: [1024]u8 = undefined;
            var reader = file.reader(&buffer);
            var rope = try Rope.init(editor.private.allocator);
            rope.read(&reader.interface) catch return Error.RopeError;

            try editor.private.buffers.append(editor.private.allocator, .{ .buffer = rope, .path = displayPath });
            editor.private.window = &editor.private.buffers.items[editor.private.buffers.items.len - 1];
        },
        else => return Error.PathKindError,
    }
}
