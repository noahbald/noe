//! An interface for interacting with a POSIX terminal, via termios.
//!
//! Usable wherever termios is usable, i.e. UNIX and WASI platforms.
const std = @import("std");

const Keypress = @import("../keypress.zig");

const AbstractTerm = @import("abstract.zig");
pub const Position = AbstractTerm.Position;

const Term = @This();
const Private = struct {
    size: Position,
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
pub fn handlePanic() void {
    const stdin = std.fs.File.stdin();
    const stdout = std.fs.File.stdout();
    var buffer: [1024]u8 = undefined;
    var writer = stdout.writer(&buffer);
    _disableRawMode(&writer.interface, stdin) catch {};
}
fn handleKill(_: c_int) callconv(.c) void {
    defer std.process.exit(1);
    handlePanic();
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

pub var winChanged: bool = false;
fn handleWinChange(_: c_int) callconv(.c) void {
    winChanged = true;
}
fn listenWinChange() void {
    const sa: std.posix.Sigaction = .{
        .handler = .{ .handler = &handleWinChange },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.WINCH, &sa, null);
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
    listenWinChange();

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

/// Caches the result of a cursor position query.
pub fn getWindowSize(self: *Term) Error!void {
    defer winChanged = false;
    var size: std.posix.winsize = undefined;
    // Call IO Control Get Window Size
    posixError(std.posix.system.ioctl(self.super.stdout.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&size))) catch |err| {
        // Some systems may not allow `IOCGWINSZ` queries,
        // we can instead move the cursor to a large offset and
        // query where the cursor lands.
        self.private.size = self.super.getWindowSize() catch return err;
        return;
    };
    self.private.size = .{ .col = size.col, .row = size.row };
}

/// Returns the width cached by `getWindowSize`.
pub fn width(self: *Term) u16 {
    return self.private.size.col - 1;
}

/// Returns the height cached by `getWindowSize`.
pub fn height(self: *Term) u16 {
    return self.private.size.row;
}

/// Returns the cursor position.
/// The `col` and `row` values will match the cursor position and
/// not the true window size.
pub fn getCursorPosition(self: *Term) !Position {
    return self.super.getCursorPosition();
}

/// Clears the terminal window
pub fn clear(self: *Term) std.Io.Writer.Error!void {
    try self.super.clear();
}

/// Sends a signal to the terminal to update the cursor position.
pub fn setCursorPosition(self: *Term, x: u16, y: u16) std.Io.Writer.Error!void {
    try self.super.setCursorPosition(x, y);
}

/// Enables raw mode for the terminal, enabling behaviour desired for a TUI.
///
/// This must be followed by a call to `disableRawMode` or `deinit` prior to
/// program exit.
pub fn enableRawMode(self: *Term) (std.Io.Writer.Error || std.posix.TermiosSetError)!void {
    // Enable alternate buffer.
    _ = try self.super.writer.interface.write("\x1b[?1049h");
    try self.super.writer.interface.flush();
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
    try _disableRawMode(&self.super.writer.interface, self.super.stdin);
}
fn _disableRawMode(stdout: *std.Io.Writer, stdin: std.fs.File) (std.Io.Writer.Error || std.posix.TermiosSetError)!void {
    // Reset ANSI.
    try stdout.writeAll("\x1b[0m");
    // Reset termios state.
    if (initial) |termios| {
        try std.posix.tcsetattr(stdin.handle, .FLUSH, termios);
    }
    // Disable alternate buffer.
    _ = try stdout.write("\x1b[?1049l");
    try stdout.flush();
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
        if (std.meta.hasMethod(AbstractTerm, decl.name) and !std.meta.hasMethod(Term, decl.name)) {
            @compileLog(decl.name);
            @compileError("Posix struct missing abstract method");
        }
    }
}
