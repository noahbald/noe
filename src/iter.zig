//! A collection of iterator types.
const std = @import("std");

// --- OPAQUE ---
pub fn SliceIter(T: type) type {
    return struct {
        buffer: []const T,
        i: usize = 0,

        const Self = @This();

        pub const Item = *const T;

        pub fn next(self: *Self) ?Item {
            if (self.peek()) |result| {
                self.i += 1;
                return result;
            } else {
                return null;
            }
        }

        pub fn peek(self: *const Self) ?Item {
            if (self.i < self.buffer.len) {
                return &self.buffer[self.i];
            } else {
                return null;
            }
        }

        pub fn len(self: *const Self) usize {
            return if (self.i < self.buffer.len) self.buffer.len - self.i else 0;
        }
    };
}

pub fn ParallelSliceIter(T: type) type {
    return struct {
        inner: SliceIter(T),
        lock: std.Thread.Mutex = .{},

        const Self = @This();

        pub fn parNext(self: *Self) ?.{ T, usize } {
            self.lock.lock();
            const i = self.inner.i;
            const result = self.inner.next();
            self.lock.unlock();
            return .{ result, i };
        }

        pub fn len(self: *const Self) usize {
            return self.inner.len();
        }
    };
}

// --- TRANSPARENT ---
pub fn Map(T: type, R: type, C: type) type {
    return struct {
        inner: T,
        context: C,
        f: fn (T, C) R,

        const Self = @This();

        pub fn next(self: *Self) ?R {
            return self.f(self.inner.next().?, self.context);
        }
    };
}

pub fn Flatten(T: type) type {
    return struct {
        inner: T,
        current: ?T.Item = null,

        const Self = @This();

        pub fn next(self: *Self) ?T.Item.Item {
            if (self.current) |current| {
                if (current) |item| {
                    return item;
                } else {
                    self.current = null;
                    return self.next();
                }
            } else {
                if (self.inner.next()) |current| {
                    self.current = current;
                    return self.next();
                } else {
                    return null;
                }
            }
        }
    };
}

pub fn Take(T: type) type {
    return struct {
        inner: T,
        remainder: usize,

        const Self = @This();

        pub fn next(self: *Self) ?T.Item {
            if (self.remainder == 0) {
                return null;
            } else {
                return self.inner.next();
            }
        }
    };
}

pub fn ParallelMap(T: type, R: type, C: type) type {
    return struct {
        inner: T,
        context: C,
        f: fn (T, C) R,

        const Self = @This();

        pub fn parNext(self: *Self) ?.{ T, usize } {
            const inner = self.inner.parNext().?;
            return .{ self.f(inner[0], self.context), inner[1] };
        }
    };
}

// --- BASE ---
pub fn Iter(T: type) type {
    return struct {
        impl: T,

        const Self = @This();

        /// Advances the iterator and returns the next value.
        ///
        /// Returns `null` once the iterator is finished.
        pub fn next(self: *Self) ?T.Item {
            return self.impl.next();
        }

        /// Advances the iterator by a number of steps, usually without
        /// processing the intermediate values.
        pub fn skip(self: *Self) void {
            self.impl.skip();
        }

        /// Returns the exact remaining length of the iterator.
        ///
        /// This method is optional by implementors, and may result in a compile error
        /// if not provided by the implementor.
        pub fn len(self: *const Self) usize {
            return self.impl.len();
        }

        /// For an iterator of an iterator, returns an iterator over the
        /// nested items.
        pub fn flatten(self: Self) Iter(Flatten(T)) {
            return .{ .impl = .{ .inner = self.impl } };
        }

        /// Takes a function and creates an iterator that calls the function on each element.
        ///
        /// Since closures are unavailable in zig, `mapScope` can be used to provide a scope
        /// or context that's passed to the function.
        pub fn map(self: Self, R: type, f: fn (T, void) R) Map(Self, R, void) {
            return self.mapScope(self, R, f, void);
        }

        /// Takes a function and context and creates an iterator that calls the function on each element.
        ///
        /// The same context will be passed along with each item to the function.
        pub fn mapScope(self: Self, R: type, C: type, f: fn (T, C) R, context: C) Map(Self, R, C) {
            return .{ .inner = self, .f = f, .context = context };
        }

        /// Returns an iterator that will continue to iterate until `n` items
        /// have been yielded.
        pub fn take(self: Self, n: usize) Iter(Take(T)) {
            return .{ .impl = .{ .inner = self.impl, .remainder = n } };
        }
    };
}

pub fn ParallelIter(T: type) type {
    return struct {
        impl: T,
        pool: []std.Thread = undefined,
        poolSize: usize,
        sink: []T = undefined,
        sinkIndex: usize = 0,
        sinkIndexLock: std.Thread.Mutex = .{},

        const Self = @This();

        pub fn init(impl: T) Self {
            const cpuCount = try std.Thread.getCpuCount() catch return .{
                .impl = impl,
                // If cpu-count fails, assume single threaded
                .poolSize = 0,
            };
            const poolSize = (impl.len() + cpuCount - 1) / cpuCount;

            return .{
                .impl = impl,
                .poolSize = poolSize,
            };
        }

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            gpa.free(self.pool);
            gpa.free(self.sink);
        }

        /// Spawn threads to process each element of the iterator
        pub fn fork(self: *Self, gpa: std.mem.Allocator) void {
            self.pool = try gpa.alloc(std.Thread, self.poolSize);
            self.sink = try gpa.alloc(T, self.impl.len());

            if (self.poolSize == 0) {
                return; // Assume threads are unavailable, complete syncronously
            } else {
                for (self.pool) |*thread| {
                    thread.* = try std.Thread.spawn(.{}, threadHandle, .{&self});
                }
            }
        }

        pub fn join(self: *Self) []T {
            if (self.pool.len == 0) {
                // Assume threads are unavailable, complete syncronously
                while (true) {
                    self.handle() orelse break;
                }
            } else {
                for (self.pool) |thread| {
                    thread.join();
                }
            }

            return self.sink;
        }

        fn threadHandle(self: *Self) void {
            for (0..self.poolSize) |_| {
                self.handle() orelse break;
            }
        }
        fn handle(self: *Self) ?void {
            var item: T = undefined;
            var i: usize = undefined;
            item, i = self.impl.parNext().?;
            self.sink[i] = item;
        }
    };
}
