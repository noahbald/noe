const Ordering = @import("../ordering.zig").Ordering;
const Chunk = @import("chunk.zig");
const sumTree = @import("sum-tree.zig");

const Point = @This();

row: usize,
column: usize,

pub const Summary = Chunk.Summary;
pub const Context = Summary.Context;

pub fn init(row: usize, column: usize) Point {
    return .{ .row = row, .column = column };
}

pub fn clone(self: *const Point) Point {
    return .{ .row = self.row, .column = self.column };
}

pub fn add(self: *const Point, other: *const Point) Point {
    if (other.row == 0) {
        return .{ .row = self.row, .column = self.column + other.column };
    } else {
        return .{ .row = self.row + other.row, .column = other.column };
    }
}

pub fn sub(self: *const Point, other: *const Point) Point {
    if (self.row == other.row) {
        return .{ .row = 0, .column = self.column - other.column };
    } else {
        return .{ .row = self.row - other.row, .column = self.column };
    }
}

pub fn cmp(self: *const Point, other: *const Point) Ordering {
    return switch (Ordering.cmp(self.row, other.row)) {
        .equal => Ordering.cmp(self.column, other.column),
        else => |ordering| ordering,
    };
}

pub const USize = struct {
    inner: usize = 0,

    pub const Summary = Chunk.Summary;
    pub const Context = void;

    pub fn zero(_: USize.Context) USize {
        return .{};
    }

    pub fn clone(self: *const USize) USize {
        return .{ .inner = self.inner };
    }

    pub fn addSummary(self: *USize, sum: *const USize.Summary, _: USize.Context) void {
        self.inner += sum.len;
    }

    pub fn cmp(self: *const USize, other: *const USize) Ordering {
        return Ordering.cmp(self.inner, other.inner);
    }

    pub fn cmpSeekTarget(self: *const USize, cursorLocation: anytype, _: USize.Context) Ordering {
        return self.cmp(&cursorLocation.d1);
    }
};
pub fn cmpSeekTarget(
    self: *const Point,
    cursorLocation: *const sumTree.Dimensions(Point, USize, null),
    _: Summary.Context,
) Ordering {
    return self.cmp(&cursorLocation.d1);
}

pub fn zero(_: Summary.Context) Point {
    return .{ .row = 0, .column = 0 };
}

pub fn addSummary(self: *Point, summary: *const Summary, _: Summary.Context) void {
    self.* = self.add(&summary.lines);
}
