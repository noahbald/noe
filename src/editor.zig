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
    repeat: usize = 0,
};

const Mode = union(enum) {
    Normal,
    Insert,
    Select,
    Pending: commands.Static,

    pub fn format(self: Mode, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        _ = try switch (self) {
            .Normal => writer.write("NORMAL"),
            .Insert => writer.write("INSERT"),
            .Select => writer.write("SELECT"),
            .Pending => |command| return writer.print("PENDING({f})", .{command}),
        };
    }
};

redraw: bool = true,
status: ?[]const u8 = null,
mode: Mode = .Normal,
private: Private,

var debugStatus: [512]u8 = undefined;
var debugStatusLen: usize = 0;
pub fn debug(
    comptime format: []const u8,
    args: anytype,
) void {
    var stream = std.Io.Writer.Discarding.init(&debugStatus);
    nosuspend stream.writer.print("debug: " ++ format, args) catch return;
    stream.writer.flush() catch return;
    debugStatusLen = stream.fullCount();
}

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
    } else if (debugStatusLen > 0) {
        const text = Text{ .text = debugStatus[0..debugStatusLen], .width = c.width, .height = 1 };
        text.draw(c);
        return;
    }

    // LTR
    var buffer: [32]u8 = undefined;
    var discarding: std.Io.Writer.Discarding = .init(&buffer);
    discarding.writer.print(" {f}", .{self.mode}) catch {};
    var width = discarding.fullCount();
    const mode = Text{ .text = buffer[0..width], .width = @intCast(width), .height = 1 };
    mode.draw(c);
    var x = @as(u16, @intCast(width)) + 1;

    const path = Text{ .text = window.path, .width = @intCast(window.path.len), .height = 1, .x = x };
    path.draw(c);
    x += @as(u16, @intCast(path.width)) + 1;

    // RTL
    buffer = undefined;
    const linesPercentage = @as(f32, @floatFromInt(window.scroll)) / @as(f32, @floatFromInt(window.buffer.lines()));
    discarding = .init(&buffer);
    discarding.writer.print("{d}%", .{@round(100 * linesPercentage)}) catch {};
    width = discarding.fullCount();
    x = c.width - @as(u16, @intCast(width)) - 1;
    const lines = Text{ .text = buffer[0..width], .width = @intCast(width), .height = 1, .x = x };
    lines.draw(c);

    buffer = undefined;
    discarding = .init(&buffer);
    discarding.writer.print("{d}:{d}", .{ window.cursor.column, window.cursor.row }) catch {};
    width = discarding.fullCount();
    x -= @as(u16, @intCast(width)) + 1;
    const cursor = Text{ .text = buffer[0..width], .width = @intCast(width), .height = 1, .x = x };
    cursor.draw(c);

    if (self.private.repeat > 0) {
        buffer = undefined;
        discarding = .init(&buffer);
        discarding.writer.print("{d}", .{self.private.repeat}) catch {};
        width = discarding.fullCount();
        x -= @as(u16, @intCast(width)) + 1;
        const repeat = Text{ .text = buffer[0..width], .width = @intCast(width), .height = 1, .x = x };
        repeat.draw(c);
    }
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

    const winChanged = term.Term.winChanged;
    if (winChanged) {
        try self.private.term.getWindowSize();
    }
    const width = self.private.term.width();
    const height = self.private.term.height();

    var allocator = gpa.allocator();
    const buffer = try allocator.alloc(Texel, width * height);
    @memset(buffer, .default());
    var canv: Canvas = .init(width, height, buffer);
    defer allocator.free(buffer);

    // Draw to canvas then write to terminal.
    if (winChanged) {
        self.redraw = true;
        try self.private.term.clear();
    }
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

        // TODO: calls to rebalanceScroll should dynamically consider the window's rendered position
        const WINDOW_PADDING = 2;
        self.private.window.?.rebalanceScroll(self.private.term.height() - WINDOW_PADDING);
    }
}

/// For a given keypress, update the editor's state.
pub fn processKeypress(self: *Editor, keypress: Keypress) !void {
    switch (self.mode) {
        .Pending => |command| {
            self.mode = .Normal;
            if (keypress.is_text()) {
                return command.settlePending(self, keypress.code);
            }
        },
        .Insert => {
            if (keypress.is_text()) {
                debug("TODO: Insert text", .{});
                return;
            }
        },
        else => {},
    }
    // Fallback to NORMAL/SELECT behaviour
    if (self.mode == .Normal or self.mode == .Select) {
        // Record numbers to repeat
        if (!keypress.control and keypress.code >= '0' and keypress.code <= '9') {
            self.private.repeat = (self.private.repeat * 10) + (keypress.code - '0');
            return;
        }
    }
    const command = keypress.command();
    for (0..@max(self.private.repeat, 1)) |_| {
        try command.call(self);
    }
    self.private.repeat = 0;
}
