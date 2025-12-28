const std = @import("std");

/// An abstract interface for interacting with a terminal.
///
/// This type should be used as a field in implementor, and never used directly.
pub const Term = struct {
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

    /// Enables raw mode for the terminal, enabling behaviour desired for a TUI.
    ///
    /// This must be followed by `disableRawMode` prior to program exit.
    pub fn enableRawMode(self: *Term) std.posix.TermiosSetError!void {
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
};
