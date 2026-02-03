//! A chunk is a small set of bytes of a text string.
const builtin = @import("builtin");
const std = @import("std");

const iters = @import("../iter.zig");

const arrayVec = @import("array-vec.zig");
const Point = @import("point.zig");

const ArrayVec = arrayVec.ArrayVec;

const Chunk = @This();

const Bitmap = if (builtin.is_test) u16 else u128;
// const Bitmap = u128;

pub const MAX_BASE = @bitSizeOf(Bitmap);
pub const MIN_BASE = MAX_BASE / 2;

/// Each bit indicates the start of a UTF-8 character.
chars: Bitmap,
/// The sum of the bits if the number of Utf16 code units it would take to represent the text.
charsUtf16: Bitmap,
/// Each bit indicates a `\n` character.
newlines: Bitmap,
/// Each bit indicates a `\t` character.
tabs: Bitmap,
/// The string of bytes.
text: ArrayVec(u8, MAX_BASE),

/// A summary of a string of text.
pub const Summary = struct {
    /// The length in bytes.
    len: usize,
    /// A point one character to the right of the last character's position.
    ///
    /// So the `row` field is the number of lines and `column` is the length of the last line.
    lines: Point,

    pub const Context = void;

    /// Creates a summary matching that of `""`.
    pub fn zero(cx: Context) Summary {
        return .{ .len = 0, .lines = .zero(cx) };
    }

    /// Returns the addition of each field within the summaries.
    pub fn add(self: *const Summary, other: *const Summary, _: Context) Summary {
        return .{
            .len = self.len + other.len,
            .lines = self.lines.add(&other.lines),
        };
    }

    /// Returns the subtraction of the each field within the summaries.
    pub fn sub(self: *const Summary, other: *const Summary, _: Context) Summary {
        return .{
            .len = self.len - other.len,
            .lines = self.lines.sub(&other.lines),
        };
    }
};

pub fn init(text: []const u8) arrayVec.Error!Chunk {
    const CHUNK_SIZE = 8;

    var charsBytes = std.mem.zeroes([MAX_BASE / CHUNK_SIZE]u8);
    var newlinesBytes = std.mem.zeroes([MAX_BASE / CHUNK_SIZE]u8);
    var tabsBytes = std.mem.zeroes([MAX_BASE / CHUNK_SIZE]u8);
    var charsUtf16Bytes = std.mem.zeroes([MAX_BASE / CHUNK_SIZE]u8);

    var chunkIx: u8 = 0;

    var bytes = text;
    while (bytes.len > 0) {
        const chunk = bytes[0..@min(bytes.len, CHUNK_SIZE)];
        bytes = bytes[@min(bytes.len, CHUNK_SIZE)..];

        var chars: u8 = 0;
        var newlines: u8 = 0;
        var tabs: u8 = 0;
        var charsUtf16: u8 = 0;
        for (0.., chunk) |i, b| {
            const ix: u3 = @intCast(i);
            const char: u8 = @intCast(@intFromBool(isUtf8CharBoundary(b)));
            chars |= char << ix;

            const newline: u8 = @intCast(@intFromBool(b == '\n'));
            newlines |= newline << ix;

            const tab: u8 = @intCast(@intFromBool(b == '\t'));
            tabs |= tab << ix;

            const charUtf16: u8 = @intCast(@intFromBool(b >= 240));
            charsUtf16 |= charUtf16 << ix;
        }

        charsBytes[chunkIx] = chars;
        newlinesBytes[chunkIx] = newlines;
        tabsBytes[chunkIx] = tabs;
        charsUtf16Bytes[chunkIx] = charsUtf16;

        chunkIx += 1;
    }

    const chars = std.mem.readInt(Bitmap, &charsBytes, .little);

    return .{
        .text = try .from(text),
        .chars = chars,
        .charsUtf16 = (std.mem.readInt(Bitmap, &charsUtf16Bytes, .little) >> 1) | chars,
        .newlines = (std.mem.readInt(Bitmap, &newlinesBytes, .little)),
        .tabs = (std.mem.readInt(Bitmap, &tabsBytes, .little)),
    };
}

pub fn format(self: *const Chunk, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try std.zig.stringEscape(self.text.slice(), writer);
}

/// Returns the summary of the chunk's contents.
pub fn summary(self: *const Chunk, _: Summary.Context) Summary {
    return self.asSlice().textSummary();
}

/// Returns the contents of the chunk as bytes.
pub fn slice(self: *const Chunk) []const u8 {
    return self.text.slice();
}

pub fn iter(self: *const Chunk) iters.Iter(iters.SliceIter(u8)) {
    return self.text.iter();
}

pub const Slice = struct {
    text: []const u8,
    inner: *const Chunk,

    pub fn textSummary(self: *const Slice) Summary {
        return .{
            .len = self.len(),
            .lines = self.lines(),
        };
    }

    pub fn lines(self: *const Slice) Point {
        const row = @popCount(self.inner.newlines);
        const column = @clz(self.inner.newlines) - (@bitSizeOf(Bitmap) - self.text.len);
        return .{ .row = row, .column = column };
    }

    pub fn len(self: *const Slice) usize {
        return self.text.len;
    }

    pub fn pointToOffset(self: *const Slice, point: Point) usize {
        if (point.row > self.lines().row) {
            return self.len();
        }

        const rowOffsetRange = self.offsetRangeForRow(point.row);
        if (point.column > (rowOffsetRange.end - rowOffsetRange.start)) {
            return rowOffsetRange.end;
        } else {
            return rowOffsetRange.start + point.column;
        }
    }

    pub fn offsetRangeForRow(self: *const Slice, row: usize) struct { start: usize, end: usize } {
        var rowStart: usize = 0;
        if (row > 0) {
            const newlines: u128 = if (builtin.is_test) @intCast(self.inner.newlines) else self.inner.newlines;
            rowStart = nthSetBit(newlines, row) + 1;
        }
        var rowLen: usize = 0;
        if (rowStart != MAX_BASE) {
            rowLen = @min(@ctz(self.inner.newlines >> @truncate(rowStart)), self.text.len - rowStart);
        }
        return .{ .start = rowStart, .end = rowStart + rowLen };
    }
};
pub fn asSlice(self: *const Chunk) Slice {
    return .{
        .text = self.text.slice(),
        .inner = self,
    };
}

fn nthSetBit(v: u128, n: usize) usize {
    const low: u64 = @truncate(v);
    const high: u64 = @truncate(v >> 64);

    const lowCount = @popCount(low);
    if (n > lowCount) {
        return 64 + nthSetBitU64(high, n - lowCount);
    } else {
        return nthSetBitU64(low, n);
    }
}
fn nthSetBitU64(vBase: u64, nBase: u64) u64 {
    // https://zed.dev/blog/zed-decoded-rope-optimizations-part-1
    const v = @bitReverse(vBase);
    var n = nBase;
    var s: u64 = 64;

    const U64_MAX = std.math.maxInt(u64);
    // Parallel bit count intermediates
    const a = v - ((v >> 1) & (U64_MAX / 3));
    const b = (a & (U64_MAX / 5)) + ((a >> 2) & (U64_MAX / 5));
    const c = (b + (b >> 4)) & (U64_MAX / 0x11);
    const d = (c + (c >> 8)) & (U64_MAX / 0x101);

    // Branchless select
    var t = (d >> 32) + (d >> 48);
    s -= ((t -% n) & 256) >> 3;
    n -= t & ((t -% n) >> 8);

    t = (d >> @intCast(s - 16)) & 0xff;
    s -= ((t -% n) & 256) >> 4;
    n -= t & ((t -% n) >> 8);

    t = (c >> @intCast(s - 8)) & 0xf;
    s -= ((t -% n) & 256) >> 5;
    n -= t & ((t -% n) >> 8);

    t = (b >> @intCast(s - 4)) & 0x7;
    s -= ((t -% n) & 256) >> 6;
    n -= t & ((t -% n) >> 8);

    t = (a >> @intCast(s - 2)) & 0x3;
    s -= ((t -% n) & 256) >> 7;
    n -= t & ((t -% n) >> 8);

    t = (v >> @intCast(s - 1)) & 0x1;
    s -= ((t -% n) & 256) >> 8;

    return 65 - s - 1;
}

fn isUtf8CharBoundary(@"u8": u8) bool {
    // This is bit magic equivalent to: b < 128 || b >= 192
    const @"i8": i8 = @intCast(@"u8");
    return @"i8" >= -0x40;
}
