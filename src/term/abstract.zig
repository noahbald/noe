//! An abstract interface for interacting with a terminal.
//!
//! This type should be used as a field in implementor, and never used directly.
const std = @import("std");

const Keypress = @import("../keypress.zig");

const Term = @This();

stdin: std.fs.File,
stdout: std.fs.File,
reader: std.fs.File.Reader,
writer: std.fs.File.Writer,

/// Creates a terminal handler using the given stdin and stdout references.
pub fn init(buffer: []u8) Term {
    const stdin = std.fs.File.stdin();
    const stdout = std.fs.File.stdout();
    return .{ .stdin = stdin, .stdout = stdout, .reader = stdin.reader(buffer), .writer = stdout.writer(buffer) };
}

/// Resets terminal state upon exit.
pub fn deinit(self: *Term, parent: anytype) !void {
    _ = try self.writer.interface.writeAll("\x1b[2J\x1b[H");
    return parent.disableRawMode();
}

/// Returns a reference to the query's window size.
pub fn getWindowSize(_: *Term) noreturn {
    @compileError("abstract method getWindowSize called");
}

/// Returns the width cached by `getWindowSize`.
pub fn width(_: *Term) u16 {
    @compileError("abstract method width called");
}

/// Returns the height cached by `getWindowSize`.
pub fn height(_: *Term) u16 {
    @compileError("abstract method height called");
}

/// Returns a reference to the query's cursor position.
pub fn getCursorPosition(_: *Term) noreturn {
    @compileError("abstract method getCursorPosition called");
}

/// Sends a signal to the terminal to update the cursor position.
pub fn setCursorPosition(self: *Term, x: u16, y: u16) std.Io.Writer.Error!void {
    _ = try self.writer.interface.print("\x1b[{d};{d}H", .{ y + 1, x + 1 });
    try self.writer.interface.flush();
}

/// Enables raw mode for the terminal, enabling behaviour desired for a TUI.
///
/// This must be followed by a call to `disableRawMode` or `deinit` prior to
/// program exit.
pub fn enableRawMode(self: *Term) !void {
    _ = self;
    @compileError("abstract method enableRawMode called");
}

/// Disables raw mode for the terminal, restoring the user's attributes.
pub fn disableRawMode(self: *Term) !void {
    _ = self;
    @compileError("abstract method disableRawMode called");
}

/// Reads a single byte from stdin.
pub fn takeByte(self: *Term) std.Io.Reader.Error!u8 {
    return self.reader.interface.takeByte();
}

/// Reads a keypress from stdin.
pub fn takeKeypress(self: *Term) !?Keypress {
    const char = self.takeByte() catch |err| {
        switch (err) {
            std.Io.Reader.Error.EndOfStream => return null,
            else => return err,
        }
    };
    if (char == std.ascii.control_code.esc) {
        // Begin of ANSI control sequence.
        // Sequence should be `"\x1b[..."`.
        // If not, return the escape code as is.
        //
        // NOTE: `catch` will likely be caused by keypress stream ending early,
        // so we can return as `'\x1b'` instead.
        const maybeControl = self.takeByte() catch {
            return .rawControl();
        };
        const code = self.takeByte() catch {
            return .rawControl();
        };
        if (maybeControl == '[') {
            if (code >= '0' and code <= '9') {
                const tilde = self.takeByte() catch {
                    return .rawControl();
                };
                if (tilde != '~') {
                    return .rawControl();
                }
            }
            return .{
                .control = true,
                .code = code,
            };
        } else {
            return .rawControl();
        }
    } else {
        return .{
            .control = false,
            .code = char,
        };
    }
}
