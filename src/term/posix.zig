//! An interface for interacting with a POSIX terminal, via termios.
//!
//! Usable wherever termios is usable, i.e. UNIX and WASI platforms.
const std = @import("std");

const canvas = @import("../canvas.zig");
const Keypress = @import("../keypress.zig");

const AbstractTerm = @import("abstract.zig");

const Term = @This();
const Private = struct {
    size: std.posix.winsize,
};

super: AbstractTerm,
/// Handle for controlling terminal state.
termios: std.posix.termios,
private: Private,

pub const PosixError = error{ BadFileDescriptor, InaccessibleMemoryArea, InvalidValue, NotATTY };
pub const Error = (PosixError || std.posix.UnexpectedError);

fn posixError(code: usize) Error!void {
    switch (std.posix.E.init(code)) {
        .SUCCESS => return,
        .BADF => return PosixError.BadFileDescriptor,
        .FAULT => return PosixError.InaccessibleMemoryArea,
        .INVAL => return PosixError.InvalidValue,
        .NOTTY => return PosixError.NotATTY,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

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

/// Creates a terminal handler for stdin and stdout.
pub fn init(buffer: []u8) !Term {
    const term: AbstractTerm = .init(buffer);
    const termios = try std.posix.tcgetattr(term.stdin.handle);
    // Ensure `deinit` is called on exit by SIGINT. Else the user's
    // terminal will be stuck in raw mode upon exit.
    // WARN: Because of this, `noreturn` statements such as `panic` or `unreachable`
    // without calling `deinit` should be avoided throughout the program.
    if (initial == null) {
        initial = termios;
        listenKill();
    }

    var self: Term = .{ .super = term, .termios = termios, .private = .{
        .size = undefined,
    } };
    // Cache initial window size
    try self.getWindowSize();
    return self;
}

/// Resets terminal state upon exit.
pub fn deinit(self: *Term) !void {
    return self.super.deinit(self);
}

/// Returns a reference to `winsize` containing the windows size and
/// cursor position.
///
/// The cursor position may be updated if the raw query fails.
pub fn getWindowSize(self: *Term) !void {
    var size: std.posix.winsize = undefined;
    // Call IO Control Get Window Size
    posixError(std.posix.system.ioctl(self.super.stdout.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&size))) catch |err| {
        // Some systems may not allow `IOCGWINSZ` queries,
        // we can instead move the cursor to a large offset and
        // query where the cursor lands.
        self.super.writer.interface.writeAll("\x1b[999C\x1b[999B") catch {
            return err;
        };
        size = self.getCursorPosition() catch {
            return err;
        };
    };
    self.private.size = size;
}

/// Returns the width cached by `getWindowSize`.
pub fn width(self: *Term) u16 {
    return self.private.size.col - 1;
}

/// Returns the height cached by `getWindowSize`.
pub fn height(self: *Term) u16 {
    return self.private.size.row - 1;
}

/// Returns a reference to `winsize` containing the cursor position.
/// The `col` and `row` values will match the cursor position and
/// not the true window size.
pub fn getCursorPosition(self: *Term) !std.posix.winsize {
    _ = try self.super.writer.interface.write("\x1b[6n\r\n");

    var buffer: [32]u8 = undefined;
    var stream = std.Io.Writer.fixed(&buffer);
    _ = try self.super.reader.interface.streamDelimiter(&stream, 'R');

    var tokens = std.mem.tokenizeScalar(u8, &buffer, 'R');

    const row = try std.fmt.parseInt(u16, tokens.next().?, 10);
    const col = try std.fmt.parseInt(u16, tokens.next().?, 10);

    return .{ .col = col, .row = row, .xpixel = row, .ypixel = col };
}

/// Sends a signal to the terminal to update the cursor position.
pub fn setCursorPosition(self: *Term, x: u16, y: u16) std.Io.Writer.Error!void {
    try self.super.setCursorPosition(x, y);
}

/// Enables raw mode for the terminal, enabling behaviour desired for a TUI.
///
/// This must be followed by a call to `disableRawMode` or `deinit` prior to
/// program exit.
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
pub fn disableRawMode(self: *Term) (std.Io.Writer.Error || std.posix.TermiosSetError)!void {
    // Reset ANSI.
    try self.super.writer.interface.writeAll("\x1b[0m");
    // Reset termios state.
    if (initial) |termios| {
        try std.posix.tcsetattr(self.super.stdin.handle, .FLUSH, termios);
    }
}

/// Reads a single byte from stdin.
pub fn takeByte(self: *Term) std.Io.Reader.Error!u8 {
    return self.super.takeByte();
}

/// Reads a keypress from stdin.
pub fn takeKeypress(self: *Term) !?Keypress {
    return self.super.takeKeypress();
}

comptime {
    const decls = @typeInfo(AbstractTerm).@"struct".decls;
    for (decls) |decl| {
        std.debug.assert(std.meta.hasMethod(Term, decl.name));
    }
}
