//! An interface for interacting with a WASI terminal, via ANSI.
//!
//! Usable wherever ANSI is usable, i.e. WASI and POSIX systems.
const std = @import("std");

const Keypress = @import("../keypress.zig");

const AbstractTerm = @import("abstract.zig");
pub const Position = AbstractTerm.Position;

const Term = @This();
const Private = struct {
    size: Position,
};

super: AbstractTerm,
private: Private,

pub fn handlePanic() void {}

/// Creates a terminal handler for stdin and stdout.
pub fn init(buffer: []u8) !Term {
    const term: AbstractTerm = .init(buffer);

    var self: Term = .{ .super = term, .private = .{ .size = undefined } };
    // Cache initial window size
    try self.getWindowSize();
    return self;
}

/// Resets terminal state upon exit.
pub fn deinit(self: *Term) !void {
    return self.super.deinit(self);
}

/// Caches the result of a cursor position query.
pub fn getWindowSize(self: *Term) !void {
    self.private.size = try self.super.getWindowSize();
}

/// Returns the width cached by `getWindowSize`.
pub fn width(self: *Term) u16 {
    return self.private.size.col - 1;
}

/// Returns the height cached by `getWindowSize`.
pub fn height(self: *Term) u16 {
    return self.private.size.row - 1;
}

/// Returns the cursor position.
/// The `col` and `row` values will match the cursor position and
/// not the true window size.
pub fn getCursorPosition(self: *Term) !Position {
    return self.super.getCursorPosition();
}

/// Sends a signal to the terminal to update the cursor position.
pub fn setCursorPosition(self: *Term, x: u16, y: u16) std.Io.Writer.Error!void {
    try self.super.setCursorPosition(x, y);
}

/// This is a no-op in wasi environments.
///
/// Using `/dev/tty` should already have the same effect.
pub fn enableRawMode(_: *Term) void {}

/// Disables raw mode for the terminal, restoring the user's attributes.
pub fn disableRawMode(_: *Term) void {}

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
            @compileError("WASI struct missing abstract method");
        }
    }
}
