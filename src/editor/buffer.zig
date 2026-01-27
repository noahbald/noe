const std = @import("std");

const Canvas = @import("../canvas.zig");
const LineEdit = @import("../canvas/line-edit.zig");
const Rope = @import("../rope.zig");
const Point = @import("../rope/point.zig");

const Buffer = @This();

const Row = struct { chars: []u8 };

/// The contents of the buffer
buffer: Rope,
/// The file path for the buffer
path: []u8,
/// The number of lines scrolled
scroll: usize = 0,
/// The position of the cursor in the buffer's contents
cursor: Point = .init(0, 0),

const SCROLL_THRESHOLD = 2;

pub fn rebalanceScroll(self: *Buffer, pageHeight: u16) void {
    const cursor = self.cursor.row;
    const top = self.scroll + SCROLL_THRESHOLD;
    const bottom = self.scroll + pageHeight - SCROLL_THRESHOLD;

    if (SCROLL_THRESHOLD > pageHeight) {
        self.scroll = cursor -| 1;
    } else if (cursor < top) {
        self.scroll = self.cursor.row -| SCROLL_THRESHOLD;
    } else if (cursor > bottom) {
        self.scroll = (cursor + SCROLL_THRESHOLD) -| pageHeight;
    }
}
pub fn cursorLeft(self: *Buffer) void {
    if (self.cursor.column > 0) {
        self.cursor.column -= 1;
    } else if (self.cursor.row > 0) {
        self.cursor.row -= 1;
        self.cursor.column = self.buffer.sliceLine(self.cursor.row).len();
    }
}
pub fn cursorRight(self: *Buffer) void {
    const bufferLen = self.buffer.len();
    const lineLen = self.buffer.sliceLine(self.cursor.row).len();
    if (self.cursor.column < lineLen) {
        self.cursor.column += 1;
    } else if (self.cursor.row < bufferLen) {
        self.cursor.column = 0;
        self.cursor.row += 1;
    }
}
pub fn cursorUp(self: *Buffer) void {
    self.cursor.row = self.cursor.row -| 1;
}
pub fn cursorDown(self: *Buffer) void {
    self.cursor.row = @min(self.buffer.len(), self.cursor.row + 1);
}
pub fn pageUp(self: *Buffer, pageHeight: usize) void {
    self.cursor.row = self.cursor.row -| pageHeight;
    self.scroll = self.scroll -| pageHeight;
}
pub fn pageDown(self: *Buffer, pageHeight: usize) void {
    self.cursor.row = @min(self.buffer.summary().lines.row, self.cursor.row + pageHeight);
    self.scroll = @min(self.cursor.row, self.scroll + pageHeight);
}
pub fn gotoLineStart(self: *Buffer) void {
    self.cursor.column = 0;
}
pub fn gotoLineEnd(self: *Buffer) void {
    self.cursor.column = self.buffer.sliceLine(self.cursor.row).len();
}

/// Draws the editing context of the buffer to canvas, returning the x, y position of the
/// primary cursor on the canvas.
pub fn draw(self: *const Buffer, c: *Canvas) [2]u16 {
    var lineEdit: LineEdit = .{ .width = c.width, .height = c.height, .buffer = self };
    return lineEdit.draw(c);
}
