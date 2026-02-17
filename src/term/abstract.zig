//! An abstract interface for interacting with a terminal.
//!
//! This type should be used as a field in implementor, and never used directly.
const std = @import("std");

const ansi = @import("../ansi.zig");
const Keypress = @import("../keypress.zig");

const Term = @This();

stdin: std.fs.File,
stdout: std.fs.File,
reader: std.fs.File.Reader,
writer: std.fs.File.Writer,

pub const Position = struct { col: u16, row: u16 };

/// Creates a terminal handler using the given stdin and stdout references.
pub fn init(buffer: []u8) Term {
    const stdin = std.fs.File.stdin();
    const stdout = std.fs.File.stdout();
    return .{ .stdin = stdin, .stdout = stdout, .reader = stdin.reader(buffer), .writer = stdout.writer(buffer) };
}

/// Resets terminal state upon exit.
pub fn deinit(self: *Term, parent: anytype) !void {
    _ = try self.writer.interface.writeAll(ansi.ERASE_SCREEN ++ ansi.CURSOR_HOME);
    return parent.disableRawMode();
}

/// Returns a reference to the query's window size. By moving and reading the cursor from
/// the farthest possible position.
pub fn getWindowSize(
    self: *Term,
) (std.Io.Writer.Error || std.Io.Reader.StreamError || std.fmt.ParseIntError)!Position {
    try self.writer.interface.writeAll(ansi.cursorMove("999", "999"));
    return try self.getCursorPosition();
}

/// Returns the width cached by `getWindowSize`.
pub fn width(_: *Term) u16 {
    @compileError("abstract method width called");
}

/// Returns the height cached by `getWindowSize`.
pub fn height(_: *Term) u16 {
    @compileError("abstract method height called");
}

/// Clears the terminal window
pub fn clear(self: *Term) std.Io.Writer.Error!void {
    _ = try self.writer.interface.write(ansi.ERASE_SCREEN);
}

/// Returns the column and row of the cursor.
pub fn getCursorPosition(
    self: *Term,
) (std.Io.Writer.Error || std.Io.Reader.StreamError || std.fmt.ParseIntError)!Position {
    _ = try self.writer.interface.write(ansi.CURSOR_REQUEST ++ "\r\n");

    var buffer: [32]u8 = undefined;
    var stream = std.Io.Writer.fixed(&buffer);
    _ = try self.reader.interface.streamDelimiter(&stream, 'R');

    var tokens = std.mem.tokenizeScalar(u8, &buffer, 'R');

    const row = try std.fmt.parseInt(u16, tokens.next().?, 10);
    const col = try std.fmt.parseInt(u16, tokens.next().?, 10);

    return .{ .col = col, .row = row };
}

/// Sends a signal to the terminal to update the cursor position.
pub fn setCursorPosition(self: *Term, x: u16, y: u16) std.Io.Writer.Error!void {
    _ = try self.writer.interface.print(ansi.CURSOR_SET_TEMPLATE, .{ y + 1, x + 1 });
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
