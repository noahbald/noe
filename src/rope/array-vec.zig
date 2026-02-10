const std = @import("std");

const iterator = @import("../iter.zig");

pub const Error = error{
    OutOfRange,
};

/// An array vector is a fixed-capacity array.
pub fn ArrayVec(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Private = struct { buffer: [capacity]T = undefined };

        len: usize = 0,
        private: Private = .{},

        const Self = @This();

        pub const init: Self = .{};

        /// Pushes the item to the end of the array and increments the length.
        pub fn push(self: *Self, item: T) Error!void {
            if (self.len >= capacity) return Error.OutOfRange;
            self.private.buffer[self.len] = item;
            self.len += 1;
        }

        /// Inserts the item at the given index, moving all the following
        /// along the vec to make space.
        pub fn insert(self: *Self, index: usize, item: T) Error!void {
            if (self.len >= capacity) return Error.OutOfRange;
            @memcpy(
                self.private.buffer[index + 1 .. self.len + 1],
                self.private.buffer[index..self.len],
            );
            self.private.buffer[index] = item;
        }

        /// Pushes the items to the end of the array and updates the length.
        pub fn extend(self: *Self, items: []const T) Error!void {
            if (self.len + items.len > capacity) return Error.OutOfRange;
            @memcpy(self.private.buffer[self.len .. self.len + items.len], items);
            self.len += items.len;
        }

        pub fn from(items: []const T) Error!Self {
            var result: Self = .init;
            try result.extend(items);
            return result;
        }

        /// Returns a copy of the last element in the array and decrements the length.
        pub fn pop(self: *Self) ?T {
            if (self.len == 0) return null;
            self.len -= 1;
            return self.private.buffer[self.len];
        }

        pub fn iter(self: *const Self) iterator.Iter(iterator.SliceIter(T)) {
            return .{ .impl = .{ .buffer = self.slice() } };
        }

        /// Returns a copy of the element at the given index.
        pub fn get(self: *const Self, index: usize) ?T {
            if (index >= self.len) return null;
            return self.private.buffer[index];
        }

        /// Returns a slice of the underlying array.
        pub fn slice(self: *const Self) []const T {
            return self.private.buffer[0..self.len];
        }

        /// Returns a mutable slice of the underlying array.
        pub fn sliceMut(self: *Self) []T {
            return self.private.buffer[0..self.len];
        }

        /// Returns a copy of the last element of the array.
        pub fn last(self: *const Self) ?T {
            if (self.len == 0) return null;
            return self.private.buffer[self.len - 1];
        }

        /// Returns a mutable reference of the last element of the array.
        pub fn lastMut(self: *Self) ?*T {
            if (self.len == 0) return null;
            return &self.private.buffer[self.len - 1];
        }

        /// Removes all items from the array.
        pub fn clear(self: *Self) void {
            self.len = 0;
        }
    };
}
