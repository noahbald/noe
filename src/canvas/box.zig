//! A box filled with the given styles.
const Canvas = @import("../canvas.zig");
const Texel = @import("../texel.zig");

const Box = @This();

width: u16,
height: u16,
x: u16,
y: u16,
/// A style to draw at the bounds of the box.
border: ?Texel.Style,
/// A style to draw within the bounds of the box.
fill: ?Texel.Style,

pub fn draw(self: *Box, canvas: *Canvas) void {
    for (self.x..self.x + self.width) |x| {
        if (x >= canvas.width) break;
        for (self.y..self.y + self.height) |y| {
            if (y >= canvas.height) break;
            if (self.border) |border| {
                canvas.setStyle(x, y, border);
            } else if (self.fill) |fill| {
                canvas.setStyle(x, y, fill);
            }
        }
    }
}
