const config = @import("config.zig");
pub const Static = @import("commands/static.zig").Static;
const Keypress = @import("keypress.zig");

/// Returns the configured command assigned to an input character.
pub fn char(c: u8) Static {
    const code: config.Char = @enumFromInt(c);
    return switch (code) {
        .CursorLeft => .CursorLeft,
        .CursorDown => .CursorDown,
        .CursorUp => .CursorUp,
        .CursorRight => .CursorRight,
        .Quit => .Quit,
        .PageUp => .PageUp,
        .PageDown => .PageDown,
        _ => .Noop,
    };
}

/// Returns the configured command assigned to an input control point.
pub fn control(c: u8) Static {
    const key: Keypress.Control = .parse(c);
    const code: config.Control = @enumFromInt(@intFromEnum(key));
    return switch (code) {
        .CursorLeft => .CursorLeft,
        .CursorDown => .CursorDown,
        .CursorUp => .CursorUp,
        .CursorRight => .CursorRight,
        .PageUp => .PageUp,
        .PageDown => .PageDown,
        .GotoLineStart => .GotoLineStart,
        .GotoLineEnd => .GotoLineEnd,
        _ => .Noop,
    };
}
