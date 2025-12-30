//! An interface for interacting with a terminal.
const builtin = @import("builtin");

/// An interface for interacting with the terminal at a high level.
///
/// Includes methods for reading, writing, and controlling the terminal's state.
pub const Term = switch (builtin.os.tag) {
    .linux, .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .netbsd, .dragonfly, .openbsd, .serenity, .haiku, .solaris, .illumos, .emscripten, .wasi => @import("term/posix.zig"),
    // TODO: .windows
    else => |tag| @compileError(@tagName(tag) ++ " not supported."),
};

/// Creates a terminal handler for stdin and stdout.
pub fn init(buffer: []u8) !Term {
    return .init(buffer);
}
