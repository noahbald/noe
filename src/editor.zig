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
status: ?[]const u8 = null,
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

fn drawStatus(self: *const Editor, window: *const Buffer, c: *Canvas) void {
    if (self.status) |status| {
        const text = Text{ .text = status, .width = c.width, .height = 1 };
        text.draw(c);
        return;
    }

    // LTR
    const modeText = " NORMAL";
    const mode = Text{ .text = modeText, .width = modeText.len, .height = 1 };
    mode.draw(c);

    const path = Text{ .text = window.path, .width = @intCast(window.path.len), .height = 1, .x = mode.x + mode.width + 1 };
    path.draw(c);

    // RTL
    var linesText: [32]u8 = undefined;
    const linesPercentage = @as(f32, @floatFromInt(window.scroll)) / @as(f32, @floatFromInt(window.buffer.lines()));
    var discarding: std.Io.Writer.Discarding = .init(&linesText);
    discarding.writer.print("{d}%", .{@round(100 * linesPercentage)}) catch {};
    var width = discarding.fullCount();
    const lines = Text{ .text = linesText[0..discarding.fullCount()], .width = @intCast(discarding.fullCount()), .height = 1, .x = c.width - @as(u16, @intCast(width)) - 1 };
    lines.draw(c);

    var cursorText: [32]u8 = undefined;
    discarding = .init(&cursorText);
    discarding.writer.print("{d}:{d}", .{ window.cursor.column, window.cursor.row }) catch {};
    width = discarding.fullCount();
    const cursor = Text{ .text = cursorText[0..width], .width = @intCast(width), .height = 1, .x = lines.x - @as(u16, @intCast(width)) - 1 };
    cursor.draw(c);
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

    var allocator = gpa.allocator();
    const buffer = try allocator.alloc(Texel, width * height);
    @memset(buffer, .default());
    var canv: Canvas = .init(width, height, buffer);
    defer allocator.free(buffer);

    // Draw to canvas then write to terminal.
    if (self.redraw) {
        drawEmpty(&canv);
        if (self.private.window) |window| {
            var windowCanv: Canvas = canv.view(.{ .height = canv.height - 1 });
            var statusCanv: Canvas = canv.view(.{ .height = 1, .top = canv.height - 1 });
            const cursor = window.draw(&windowCanv);
            self.drawStatus(window, &statusCanv);
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
        self.status = null;
    }
}

/// For a given keypress, update the editor's state.
pub fn processKeypress(self: *Editor, keypress: Keypress) !void {
    try keypress.command().call(self);
}
