const builtin = @import("builtin");

/// An interface for interacting with the terminal at a high level.
///
/// Includes methods for reading, writing, and controlling the terminal's state.
pub const Term = switch (builtin.os.tag) {
    .linux, .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .netbsd, .dragonfly, .openbsd, .serenity, .haiku, .solaris, .illumos, .emscripten, .wasi => @import("term/posix.zig").Term,
    else => |tag| @compileError(@tagName(tag) ++ " not supported."),
};
