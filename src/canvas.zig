//! A canvas represents the sets of texel points within a terminal window.
//!
//! The canvas can be freely drawn too, before finally being written to stdout.
const std = @import("std");

const Grapheme = @import("grapheme.zig");
const term = @import("term.zig");
const Texel = @import("texel.zig");

const Canvas = @This();

/// The list of text elements contained within the canvas as a flattened 2D buffer.
buffer: []Texel,
/// The length of each row in `buffer`.
width: u16,
/// The number of rows in `buffer`.
height: u16,

pub fn format(self: Canvas, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    // Hide cursor, then reposition cursor
    _ = try writer.writeAll("\x1b[?25l\x1b[H");

    for (self.buffer, 0..) |texel, i| {
        if (i != 0 and i % self.width == 0) {
            // At the end of a row, write ANSI clear for the remainder of the line, then a newline.
            _ = try writer.write("\x1b[K");
            if (i < self.buffer.len - 1) {
                _ = try writer.write("\r\n");
            }
        }
        try texel.format(writer);
    }

    // Reposition cursor, then show cursor
    _ = try writer.writeAll("\x1b[?25h");
}

/// Returns the `[x, y]` value of the canvas's midpoint.
pub fn getCenter(self: *Canvas) [2]u16 {
    return .{ self.width / 2, self.height / 2 };
}

/// Returns the `[x, y]` value of the canvas's midpoint, offset by the width and height.
pub fn getCentering(self: *Canvas, width: u16, height: u16) [2]u16 {
    const position = self.getCenter();
    return .{ position[0] - (width / 2), position[1] - (height / 2) };
}

/// Returns the texel at the given position.
pub fn getTexel(self: *Canvas, x: usize, y: usize) ?*Texel {
    if (x >= self.width) return null;
    if (y >= self.height) return null;
    return &self.buffer[(y * self.width) + x];
}

/// Sets the character at the given position.
pub fn setChar(self: *Canvas, x: usize, y: usize, char: Grapheme.Codepoint) void {
    if (self.getTexel(x, y)) |texel| {
        texel.char = char;
    }
}

/// Sets the style at the given position.
pub fn setStyle(self: *Canvas, x: usize, y: usize, style: Texel.Style) void {
    if (self.getTexel(x, y)) |grapheme| {
        grapheme.style = style;
    }
}
