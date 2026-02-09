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
        self.scroll = cursor -| pageHeight;
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
    self.cursor.row = @min(self.buffer.lines(), self.cursor.row + 1);
}
fn MoveWordContext(comptime reverse: bool, comptime follow: bool, comptime long: bool) type {
    return struct {
        i: usize = 0,
        sawNonWord: bool = false,
        sawWord: bool = false,

        pub const Error = error{Done};

        pub fn visit(chunk: []const u8, this: *@This()) Error!void {
            for (0..chunk.len) |i| {
                const index = if (reverse) chunk.len - i - 1 else i;
                const c = chunk[index];
                const isInWord = if (long) c != '\n' and c != ' ' else std.ascii.isAlphanumeric(c);
                if (isInWord) {
                    if (!follow and this.sawNonWord) {
                        this.i += i;
                        return error.Done;
                    }
                    this.sawWord = true;
                } else {
                    if (follow and this.sawNonWord and this.sawWord) {
                        this.i += i;
                        return error.Done;
                    }
                    this.sawNonWord = true;
                }
            }
            this.i += chunk.len;
        }
    };
}
fn moveWord(
    self: *Buffer,
    comptime reverse: bool,
    comptime follow: bool,
    comptime long: bool,
) void {
    const offset = self.buffer.pointToOffset(self.cursor);
    const Context = MoveWordContext(reverse, follow, long);
    var context: Context = .{};
    if (reverse) {
        const slice = self.buffer.slice(0, offset);
        slice.visitReverse(*Context, Context.Error, Context.visit, &context) catch {};
        self.cursor = self.buffer.offsetToPoint(offset - context.i);
    } else {
        const slice = self.buffer.slice(offset, self.buffer.len());
        slice.visit(*Context, Context.Error, Context.visit, &context) catch {};
        if (follow) {
            context.i -= 1;
        }
        self.cursor = self.buffer.offsetToPoint(offset + context.i);
    }
}
pub fn nextWordStart(self: *Buffer, comptime long: bool) void {
    self.moveWord(false, false, long);
}
pub fn prevWordStart(self: *Buffer, comptime long: bool) void {
    self.moveWord(true, true, long);
}
pub fn nextWordEnd(self: *Buffer, comptime long: bool) void {
    self.moveWord(false, true, long);
}
fn FindCharContext(comptime reverse: bool) type {
    return struct {
        i: usize = 0,
        char: u8,

        pub const Error = error{Done};

        pub fn visit(chunk: []const u8, this: *@This()) Error!void {
            for (0..chunk.len) |i| {
                const index = if (reverse) chunk.len - i - 1 else i;
                const c = chunk[index];
                if (c == this.char) {
                    this.i += i;
                    return error.Done;
                }
            }
            this.i += chunk.len;
        }
    };
}
pub fn findChar(self: *Buffer, comptime reverse: bool, comptime till: bool, char: u8) void {
    var offset = self.buffer.pointToOffset(self.cursor);
    const Context = FindCharContext(reverse);
    var context: Context = .{ .char = char };
    if (reverse) {
        if (till) {
            offset -= 1;
        }
        const slice = self.buffer.slice(0, offset);
        slice.visitReverse(*Context, Context.Error, Context.visit, &context) catch {
            if (!till) {
                context.i += 1;
            }
            self.cursor = self.buffer.offsetToPoint(offset - context.i);
        };
    } else {
        offset += 1;
        if (till) {
            offset += 1;
        }
        const slice = self.buffer.slice(offset, self.buffer.len());
        slice.visit(*Context, Context.Error, Context.visit, &context) catch {
            if (till) {
                context.i = context.i -| 1;
            }
            self.cursor = self.buffer.offsetToPoint(offset + context.i);
        };
    }
}
pub fn gotoLine(self: *Buffer, line: usize) void {
    self.cursor.row = line;
    self.cursor.column = 0;
}
pub fn pageUp(self: *Buffer, pageHeight: usize) void {
    self.cursor.row = self.cursor.row -| pageHeight;
    self.scroll = self.scroll -| pageHeight;
}
pub fn pageDown(self: *Buffer, pageHeight: usize) void {
    self.cursor.row = @min(self.buffer.lines(), self.cursor.row + pageHeight);
    self.scroll = @min(self.cursor.row - 1, self.scroll + pageHeight);
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
