//! A recorded keypress input.
const std = @import("std");

const commands = @import("commands.zig");

pub const Keypress = @This();

/// Whether the keypress belongs to a control sequence.
control: bool,
/// The read UTF-8 character.
code: u8,

/// The mappings of an input code to a control point
pub const Control = union(enum) {
    ArrowUp,
    ArrowDown,
    ArrowRight,
    ArrowLeft,
    Home,
    Del,
    End,
    PageUp,
    PageDown,
    _,

    pub fn parse(char: u8) Control {
        return switch (char) {
            'A' => .ArrowUp,
            'B' => .ArrowDown,
            'C' => .ArrowRight,
            'D' => .ArrowLeft,
            '1', '7', 'H' => .Home,
            '3' => .Del,
            '4', '8', 'F' => .End,
            '5' => .PageUp,
            '6' => .PageDown,
            else => ._,
        };
    }
};

/// Returns a keypress of a control escape character, instead of a control sequence
pub fn rawControl() Keypress {
    return .{ .control = false, .code = std.ascii.control_code.esc };
}

/// Returns the command associated with the keypress.
pub fn command(self: Keypress) commands.Static {
    return if (self.control) commands.control(self.code) else commands.char(self.code);
}

/// Returns the value of the character when mapped by the `ctrl` key.
pub fn ctrl_key(c: u8) u8 {
    return c & 0x1f;
}

pub fn is_ctrl_key(self: *const Keypress) bool {
    return ctrl_key(self.code) == self.code;
}

pub fn is_text_control(self: *const Keypress) bool {
    return self.code >= 0x8 and self.code <= 0xd;
}

pub fn is_text(self: *const Keypress) bool {
    return !self.control and (!self.is_ctrl_key() or self.is_text_control());
}
