//! A line-edit renders a view into a buffer with line-numbers and modal data.
const std = @import("std");

const Buffer = @import("../editor/buffer.zig");
const Canvas = @import("../canvas.zig");
const rope = @import("../rope.zig");
const arrayVec = @import("../rope/array-vec.zig");
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
    const scrollOffset = self.buffer.buffer.pointToOffset(.init(line, 0));
    const cursorOffset = self.buffer.buffer.pointToOffset(self.buffer.cursor);
    const insertingChunkStart = cursorOffset - scrollOffset + 1;
    var context: DrawVisitorContext = .{
        .canvas = canvas,
        .insertingChunk = self.buffer.insertingChunk.slice(),
        .insertingChunkStart = insertingChunkStart,
        .line = line,
    };
    slice.visit(*DrawVisitorContext, null, drawVisitor, &context);

    return .{ GUTTER_SIZE + 1 + context.cursorCol, context.cursorRow };
}
const DrawVisitorContext = struct {
    canvas: *Canvas,
    insertingChunk: []const u8,
    insertingChunkStart: usize,
    line: usize,
    row: u16 = 0,
    col: u16 = 0,
    cursorRow: u16 = 0,
    cursorCol: u16 = 0,
};
fn drawVisitor(chunk: []const u8, context: *DrawVisitorContext) void {
    if (context.row > context.canvas.height) return;
    drawChunk(chunk, context);
}
fn drawChunk(chunk: []const u8, context: *DrawVisitorContext) void {
    for (chunk) |char| {
        if (context.insertingChunkStart == 1) {
            context.insertingChunkStart -= 1;
            drawChunk(context.insertingChunk, context);
            context.cursorRow = context.row;
            context.cursorCol = context.col;
        }
        if (context.insertingChunkStart > 0) context.insertingChunkStart -= 1;
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
    stream.print("{d:>[1]}", .{
        context.line + context.row + 1,
        GUTTER_SIZE,
    }) catch {
        // If line number won't fit, just make do
    };
    for (gutterText, 0..) |gutterChar, i| {
        context.canvas.setChar(i, context.row, @as(u21, gutterChar));
    }
}
