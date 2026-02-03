//! A line-edit renders a view into a buffer with line-numbers and modal data.
const std = @import("std");

const Buffer = @import("../editor/buffer.zig");
const Canvas = @import("../canvas.zig");
const rope = @import("../rope.zig");
const Chunk = @import("../rope/chunk.zig");
const sumTree = @import("../rope/sum-tree.zig");

const LineEdit = @This();

width: u16,
height: u16,
buffer: *const Buffer,

const GUTTER_SIZE = 4;

pub fn draw(self: *const LineEdit, canvas: *Canvas) [2]u16 {
    const line = self.buffer.scroll;
    const slice = self.buffer.buffer.sliceRows(line, line + @as(usize, self.height));
    var context: DrawVisitorContext = .{
        .canvas = canvas,
        .line = line,
    };
    slice.visit(*DrawVisitorContext, null, drawVisitor, &context);

    const column: u16 = @intCast(@min(
        self.buffer.cursor.column,
        self.buffer.buffer.sliceLine(self.buffer.cursor.row).len(),
    ));
    const row: u16 = @intCast(self.buffer.cursor.row - self.buffer.scroll);
    return .{ GUTTER_SIZE + 1 + column, row };
}
const DrawVisitorContext = struct {
    canvas: *Canvas,
    row: u16 = 0,
    col: u16 = 0,
    line: usize,
};
fn drawVisitor(chunk: []const u8, context: *DrawVisitorContext) void {
    if (context.row > context.canvas.height) return;
    for (chunk) |char| {
        if (context.col == 0) {
            drawGutter(context);
        }

        // Handle crlf
        if (char == '\r') {
            context.col = 0;
            continue;
        } else if (char == '\n') {
            context.col = 0;
            context.row += 1;
            continue;
        }

        // Draw chars
        context.canvas.setChar(context.col + GUTTER_SIZE + 1, context.row, @as(u21, char));
        context.col += 1;
    }
}

fn drawGutter(context: *const DrawVisitorContext) void {
    var gutterText: [GUTTER_SIZE]u8 = undefined;
    var stream = std.Io.Writer.fixed(&gutterText);
    stream.print("{d:>[1]}", .{ context.line + context.row + 1, GUTTER_SIZE }) catch {
        // If line number won't fit, just make do
    };
    for (gutterText, 0..) |gutterChar, i| {
        context.canvas.setChar(i, context.row, @as(u21, gutterChar));
    }
}
