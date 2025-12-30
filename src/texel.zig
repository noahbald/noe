//! A text element. Analogous to a pixel.
const std = @import("std");

const Grapheme = @import("grapheme.zig");

const Texel = @This();

char: Grapheme.Codepoint,
style: Style,

/// ANSI accent codes.
pub const Accent = enum(u8) {
    None = 0,
    Bold = 1,
    Underline = 2,
    Dimmed = 3,
    Italic = 5,
    Reverse = 7,
};

/// Settable ANSI style codes.
const Style = struct {
    color: ?u16,
    accent: ?Accent,

    /// Format style into an ANSI escape sequence.
    pub fn format(self: Style, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const accent = self.accent orelse .None;
        _ = try writer.write("\x1b[");
        _ = try writer.print("{d}", .{accent});
        if (self.color) |color| {
            _ = try writer.print(";{d}", .{color});
        }
        _ = try writer.writeByte('m');
    }

    pub fn default() Style {
        return .{
            .color = null,
            .accent = null,
        };
    }
};

/// Format texel into a styled character.
pub fn format(self: Texel, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try self.style.format(writer);
    try writer.printUnicodeCodepoint(self.char);
}

/// Returns an unstyled whitespace character.
pub fn default() Texel {
    return .{ .char = ' ', .style = .default() };
}
