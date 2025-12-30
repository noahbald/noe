//! A box filled with the given char.
const Canvas = @import("../canvas.zig");

const Char = @This();

width: u16,
height: u16,
x: u16,
y: u16,
char: u21,

pub fn draw(self: *Char, canvas: *Canvas) void {
    for (self.x..self.x + self.width) |x| {
        for (self.y..self.y + self.height) |y| {
            canvas.setChar(x, y, self.char);
        }
    }
}
