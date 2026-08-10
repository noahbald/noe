//! An interface for interacting with a Windows terminal, via console.
//!
//! Usable wherever console is usable, i.e. UNIX and WASI platforms.
const std = @import("std");

const Init = @import("./init.zig");

const ansi = @import("../ansi.zig");
const Keypress = @import("../keypress.zig");

const AbstractTerm = @import("abstract.zig");
pub const Position = AbstractTerm.Position;

const Term = @This();
const Private = struct {
    size: Position,
};

const Mode = struct { input: std.os.windows.DWORD = 0, output: std.os.windows.DWORD = 0 };

super: AbstractTerm,
/// Handle for controlling console mode.
mode: Mode,
private: Private,

pub const Error = std.posix.E - error{SUCCESS};

pub fn windowsError(success: std.os.windows.BOOL) Error!void {
    if (success == 0) {
        switch (std.os.windows.GetLastError()) {
            std.os.windows.Win32Error.SUCCESS => {},
            else => |err| return err,
        }
    }
}

/// A reference to the first console mode received.
var initial: ?Mode = null;
pub fn handlePanic() void {
    if (initial) |mode| {
        _ = std.os.windows.kernel32.SetConsoleMode(std.fs.File.stdin().handle, mode.input);
        _ = std.os.windows.kernel32.SetConsoleMode(std.fs.File.stdout().handle, mode.output);
    }
}
fn handleKill(_: std.os.windows.DWORD) callconv(.winapi) std.os.windows.BOOL {
    defer std.process.exit(1);
    handlePanic();
}
fn listenKill() void {
    std.os.windows.kernel32.SetConsoleCtrlHandler(&handleKill, 1);
}

pub const winChanged = true;

pub fn init(self_init: Init, buffer: []u8) !Term {
    const term: AbstractTerm = .init(self_init, buffer);
    var mode: Mode = .{};
    windowsError(std.os.windows.kernel32.GetConsoleMode(term.stdin.handle, &mode.input));
    windowsError(std.os.windows.kernel32.GetConsoleMode(term.stdout.handle, &mode.output));
    // Ensure `deinit` is called on exit by SIGINT. Else the user's
    // terminal will be stuck in raw mode upon exit.
    // WARN: Because of this, `noreturn` statements such as `panic` or `unreachable`
    // without calling `deinit` should be avoided throughout the program.
    if (initial == null) {
        initial = mode;
        listenKill();
    }

    var self: Term = .{ .super = term, .private = .{
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
pub fn getWindowSize(self: *Term) std.posix.UnexpectedError!void {
    var csbi: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;

    windowsError(std.os.windows.kernel32.GetConsoleScreenBufferInfo(self.super.stdout.handle, &csbi)) catch |err| {
        self.private.size = self.super.getWindowSize() catch return err;
        return;
    };
    self.private.size = .{
        .col = @intCast(csbi.srWindow.Right - csbi.srWindow.Left + 1),
        .row = @intCast(csbi.srWindow.Bottom - csbi.srWindow.Top + 1),
    };
}

/// Returns the width cached by `getWindowSize`.
pub fn width(self: *Term) u16 {
    return self.private.size.col - 1;
}

/// Returns the height cached by `getWindowSize`.
pub fn height(self: *Term) u16 {
    return self.private.size.row - 1;
}

/// Returns the column and row of the cursor.
pub fn getCursorPosition(self: *Term) !Position {
    return self.super.getCursorPosition();
}

/// Clears the terminal window
pub fn clear(self: *Term) std.Io.Writer.Error!void {
    try self.super.clear();
}

/// Sends a signal to the terminal to update the cursor position.
pub fn setCursorPosition(self: *Term, x: u16, y: u16) std.Io.Writer.Error!void {
    self.super.setCursorPosition(x, y);
}

const DWOutputMode = struct {
    const ENABLE_PROCESSED_OUTPUT = 0x0001;
    const ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
    const DISABLE_NEWLINE_AUTO_RETURN = 0x0008;
};

const DWInputMode = struct {
    const ENABLE_ECHO_INPUT = 1 << 2;
    const ENABLE_LINE_INPUT = 1 << 1;
    const ENABLE_PROCESSED_INPUT = 1 << 0;
    const ENABLE_VIRTUAL_TERMINAL_INPUT = 1 << 10;
};

/// Enables raw mode for the terminal, enabling behaviour desired for a TUI.
///
/// This must be followed by a call to `disableRawMode` or `deinit` prior to
/// program exit.
pub fn enableRawMode(self: *Term) (std.Io.Writer.Error || std.posix.UnexpectedError)!void {
    // Enable alternate buffer.
    try self.super.writer.interface.writeAll(ansi.ALT_BUFFER_ENABLE);

    self.mode.output |= DWOutputMode.ENABLE_VIRTUAL_TERMINAL_PROCESSING | DWOutputMode.DISABLE_NEWLINE_AUTO_RETURN | DWOutputMode.ENABLE_PROCESSED_OUTPUT;
    self.mode.input |= DWInputMode.ENABLE_VIRTUAL_TERMINAL_INPUT & !(DWInputMode.ENABLE_PROCESSED_INPUT | DWInputMode.ENABLE_LINE_INPUT | DWInputMode.ENABLE_ECHO_INPUT);

    try self.setMode();
}

/// Disables raw mode for the terminal, restoring the user's attributes.
pub fn disableRawMode(self: *Term) (std.Io.Writer.Error || std.posix.TermiosSetError)!void {
    // Reset ANSI.
    try self.super.writer.interface.writeAll(ansi.RESET_MODE);
    // Reset termios state.
    if (initial) |mode| {
        self.mode = mode;
        try self.setMote();
    }
    // Disable alternate buffer.
    try self.super.writer.interface.writeAll(ansi.ALT_BUFFER_DISABLE);
}

fn setMode(self: *const Term) std.posix.UnexpectedError!void {
    try windowsError(std.os.windows.kernel32.SetConsoleMode(self.super.stdout.handle, self.mode.output));
    try windowsError(std.os.windows.kernel32.SetConsoleMode(self.super.stdin.handle, self.mode.input));
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
            @compileError("Windows struct missing abstract method");
        }
    }
}
