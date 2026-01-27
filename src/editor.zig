//! The editor contains a reference to the terminal and the editor's state.
//!
//! The editor will listen for user input, update it's state, and then output
//! to the terminal.
const std = @import("std");

const Canvas = @import("canvas.zig");
const Char = @import("canvas/char.zig");
const Text = @import("canvas/text.zig");
const LineEdit = @import("canvas/line-edit.zig");
const config = @import("config.zig");
const commands = @import("commands.zig");
const Buffer = @import("editor/buffer.zig");
const Keypress = @import("keypress.zig");
const term = @import("term.zig");
const Texel = @import("texel.zig");

const Editor = @This();

const Private = struct {
    term: term.Term,
    allocator: std.mem.Allocator,
    buffers: std.ArrayList(Buffer),
    window: ?*Buffer,
};

redraw: bool = true,
private: Private,

/// Draws empty text area as rows of `'~'`.
fn drawEmpty(c: *Canvas) void {
    var text = Char{ .width = 1, .height = c.height, .x = 0, .y = 0, .char = '~' };
    text.draw(c);
}

/// Draws splash text.
fn drawSplash(c: *Canvas) void {
    const string: []const u8 = "Noe Editor";
    const position = c.getCentering(string.len, 1);

    var text = Text{ .width = string.len, .height = 1, .x = position[0], .y = position[1], .text = string };
    text.draw(c);
}

/// Wraps the terminal with an editor and initial state.
pub fn init(allocator: std.mem.Allocator, t: term.Term) std.mem.Allocator.Error!Editor {
    return .{ .private = .{
        .allocator = allocator,
        .term = t,
        .buffers = try std.ArrayList(Buffer).initCapacity(allocator, 1),
        .window = null,
    } };
}

pub fn deinit(self: *Editor, allocator: std.mem.Allocator) void {
    for (self.private.buffers.items) |*buffer| {
        buffer.buffer.deinit();
    }
    self.private.buffers.deinit(allocator);
}

/// Draws to terminal and waits for next keypress.
pub fn refresh(self: *Editor) !void {
    // Allocate and create canvas.
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    try self.private.term.getWindowSize();
    const width = self.private.term.width();
    const height = self.private.term.height();
    var canv: Canvas = .{
        .width = width,
        .height = height,
        .buffer = undefined,
    };

    var allocator = gpa.allocator();
    const buffer = try allocator.alloc(Texel, width * height);
    @memset(buffer, .default());
    canv.buffer = buffer;
    defer allocator.free(buffer);

    // Draw to canvas then write to terminal.
    if (self.redraw) {
        drawEmpty(&canv);
        if (self.private.window) |window| {
            const cursor = window.draw(&canv);
            try canv.format(&self.private.term.super.writer.interface);
            try self.private.term.setCursorPosition(cursor[0], cursor[1]);
        } else {
            drawSplash(&canv);
            try canv.format(&self.private.term.super.writer.interface);
        }
    }

    // Wait for next input.
    const char = try self.private.term.takeKeypress();
    if (char) |c| {
        try self.processKeypress(c);
        self.redraw = true;
    }
}

/// For a given keypress, update the editor's state.
pub fn processKeypress(self: *Editor, keypress: Keypress) !void {
    try keypress.command().call(self);
}
