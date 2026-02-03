//! A text box rendered within the given bounds.
const Canvas = @import("../canvas.zig");

const Text = @This();

width: u16,
height: u16,
x: u16 = 0,
y: u16 = 0,
text: []const u8,

pub fn draw(self: *const Text, canvas: *Canvas) void {
    var i: usize = 0;
    y: for (self.y..self.y + self.height) |y| {
        x: for (self.x..self.x + self.width) |x| {
            if (i >= self.text.len) return;

            const char = self.text[i];
            if (char == '\n') {
                i += 1;
                continue :y;
            } else if ((y > 0) and (x == 0) and (self.text[i - 1] != '\n')) {
                canvas.setChar(x, y, '↪');
                continue :x;
            } else {
                canvas.setChar(x, y, char);
                i += 1;
            }
        }
    }
}
