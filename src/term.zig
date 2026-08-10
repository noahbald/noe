//! An interface for interacting with a terminal.
const builtin = @import("builtin");

pub const Init = @import("./term/init.zig");

/// An interface for interacting with the terminal at a high level.
///
/// Includes methods for reading, writing, and controlling the terminal's state.
pub const Term = switch (builtin.os.tag) {
    .linux, .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos, .freebsd, .netbsd, .dragonfly, .openbsd, .serenity, .haiku, .illumos => @import("term/posix.zig"),
    .windows => @import("term/windows.zig"),
    .wasi, .emscripten => @import("term/wasi.zig"),
    else => |tag| @compileError(@tagName(tag) ++ " not supported."),
};

/// Creates a terminal handler for stdin and stdout.
pub fn init(self_init: anytype, buffer: []u8) !Term {
    return .init(.{ .io = self_init.io }, buffer);
}
