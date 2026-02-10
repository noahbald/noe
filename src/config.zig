//! Contains all configuration items that a user may want to modify. Includes the following:
//!
//! - Keyboard controls
const std = @import("std");

const Keypress = @import("keypress.zig");
const ctrl_key = Keypress.ctrl_key;

/// The set of assigned keyboard characters.
pub const Char = enum(u8) {
    // Movement
    CursorLeft = 'h',
    CursorDown = 'j',
    CursorUp = 'k',
    CursorRight = 'l',
    NextWordStart = 'w',
    PrevWordStart = 'b',
    NextWordEnd = 'e',
    NextLongWordStart = 'W',
    PrevLongWordStart = 'B',
    NextLongWordEnd = 'E',
    FindTillNextChar = 't',
    FindNextChar = 'f',
    FindTillPrevChar = 'T',
    FindPrevChar = 'F',
    GotoLine = 'G',
    Quit = ctrl_key('q'),
    PageUp = ctrl_key('u'),
    PageDown = ctrl_key('d'),

    // Changes
    InsertMode = 'i',
    NormalMode = std.ascii.control_code.esc,
    _,
};

/// The set of assigned keyboard control points.
pub const Control = enum(u4) { CursorUp = @intFromEnum(Keypress.Control.ArrowUp), CursorDown = @intFromEnum(Keypress.Control.ArrowDown), CursorRight = @intFromEnum(Keypress.Control.ArrowRight), CursorLeft = @intFromEnum(Keypress.Control.ArrowLeft), PageUp = @intFromEnum(Keypress.Control.PageUp), PageDown = @intFromEnum(Keypress.Control.PageDown), GotoLineStart = @intFromEnum(Keypress.Control.Home), GotoLineEnd = @intFromEnum(Keypress.Control.End), _ };
