const Rope = @import("../rope.zig");

const Buffer = @This();

const Row = struct { chars: []u8 };

/// The contents of the buffer
buffer: Rope,
/// The file path for the buffer
path: []u8,
/// The number of lines scrolled
scroll: usize = 0,
