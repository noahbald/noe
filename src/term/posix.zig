const std = @import("std");
const abstract = @import("abstract.zig");

const PosixSignal = error{Received};

/// A reference to the first termios state received.
var initial: ?std.posix.termios = null;
fn handleKill(_: c_int) callconv(.c) void {
    defer std.process.exit(1);
    if (initial) |termios| {
        try std.posix.tcsetattr(std.fs.File.stdin().handle, .FLUSH, termios);
    }
}
fn listenKill() void {
    const sa: std.posix.Sigaction = .{
        .handler = .{ .handler = &handleKill },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &sa, null);
    std.posix.sigaction(std.posix.SIG.TERM, &sa, null);
}

/// An interface for interacting with a POSIX terminal, via termios.
///
/// Usable wherever termios is usable, i.e. UNIX and WASI platforms.
pub const Term = struct {
    super: abstract.Term,
    /// Handle for controlling terminal state.
    termios: std.posix.termios,

    /// Creates a terminal handler using the given stdin and stdout references.
    pub fn init(buffer: []u8) !Term {
        const term: abstract.Term = .init(buffer);
        const termios = try std.posix.tcgetattr(term.stdin.handle);
        if (initial == null) {
            initial = termios;
            listenKill();
        }

        return .{
            .super = term,
            .termios = termios,
        };
    }

    /// Enables raw mode for the terminal, enabling behaviour desired for a TUI.
    ///
    /// This must be followed by `disableRawMode` prior to program exit.
    pub fn enableRawMode(self: *Term) std.posix.TermiosSetError!void {
        // Disable printing of input keys.
        self.termios.lflag.ECHO = false;
        // Disable line-by-line reading; read byte-by-byte.
        self.termios.lflag.ICANON = false;
        // Disable signals `ctrl-c` and `ctrl-z`.
        self.termios.lflag.ISIG = false;
        // Disable signals `ctrl-s` and `ctrl-q`.
        self.termios.iflag.IXON = false;
        // Disable signal `ctrl-v`.
        self.termios.lflag.IEXTEN = false;
        // Disable mapping `ctrl-m` and `enter` to `\n`; read as `\r` instead.
        self.termios.iflag.ICRNL = false;
        // Disable post-processing of `\n` to `\r\n`.
        self.termios.oflag.OPOST = false;
        // Disable signals from break condition.
        self.termios.iflag.BRKINT = false;
        // Disable unnecessary parity checking.
        self.termios.iflag.INPCK = false;
        // Disable stripping UTF-8 to ASCII (i.e. stripping ASCII's 8th parity bit).
        self.termios.iflag.ISTRIP = false;
        // Set character size to 8.
        self.termios.cflag.CSIZE = .CS8;
        // Set minimum bytes needed before `read` will trigger.
        self.termios.cc[@intFromEnum(std.posix.V.MIN)] = 0;
        // Set maximum time needed before `read` will trigger.
        self.termios.cc[@intFromEnum(std.posix.V.TIME)] = 1;
        try std.posix.tcsetattr(self.super.stdin.handle, .FLUSH, self.termios);
    }

    /// Disables raw mode for the terminal, restoring the user's attributes.
    pub fn disableRawMode(self: *Term) !void {
        // Reset ANSI.
        try self.super.writer.interface.writeAll("\x1b[0m");
        // Reset termios state.
        if (initial) |termios| {
            try std.posix.tcsetattr(self.super.stdin.handle, .FLUSH, termios);
        }
    }

    /// Reads a single byte from stdin.
    pub fn takeByte(self: *Term) !u8 {
        return self.super.takeByte();
    }
};

test "inherits abstract" {
    const decls = @typeInfo(abstract.Term).@"struct".decls;
    inline for (decls) |decl| {
        try std.testing.expect(std.meta.hasMethod(Term, decl.name));
    }
}
