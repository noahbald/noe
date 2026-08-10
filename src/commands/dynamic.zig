const std = @import("std");

const Editor = @import("../editor.zig");
const Rope = @import("../rope.zig");
const Chunk = @import("../rope/chunk.zig");

pub const Error = error{ PathKindError, ReadError, RopeError } || std.mem.Allocator.Error;

/// The list of editor commands that require no arguments.
///
/// These commands can be assigned to keys or typed.
pub const Dynamic = union(enum) {
    Open,

    pub fn call(self: Dynamic, editor: *Editor, args: []const u8) !void {
        return switch (self) {
            .Open => open(editor, args),
        };
    }
};

pub fn open(editor: *Editor, args: []const u8) Error!void {
    const io = editor.i.io;
    const gpa = editor.i.gpa;

    const cwd = std.Io.Dir.cwd().realPathFileAlloc(io, ".", gpa) catch return Error.ReadError;
    const path = std.Io.Dir.cwd().realPathFileAlloc(io, args, gpa) catch return Error.ReadError;
    const displayPath = if (std.mem.startsWith(u8, path, cwd)) path[cwd.len + 1 ..] else path;
    gpa.free(cwd);

    const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return Error.ReadError;
    defer file.close(io);
    const stat = file.stat(io) catch return Error.ReadError;

    switch (stat.kind) {
        // TODO: Follow symlink
        .sym_link => return Error.PathKindError,
        // TODO: display file browser
        .directory => return Error.PathKindError,
        .file => {
            var buffer: [Chunk.MAX_BASE]u8 = undefined;
            var reader = file.reader(io, &buffer);
            var rope = try Rope.init(editor.i);
            errdefer rope.deinit();
            rope.read(&reader.interface) catch return Error.RopeError;

            try editor.private.buffers.append(gpa, .{ .buffer = rope, .path = displayPath });
            editor.private.window = &editor.private.buffers.items[editor.private.buffers.items.len - 1];
        },
        else => return Error.PathKindError,
    }
}
