//! A rope is a data-structure that can be efficiently edited, representing a string of u8 bytes.
//!
//! The rope is represented by a sum-tree which provides efficient extraction and navigation of
//! the the tree and it's metadata.
const std = @import("std");

const arrayVec = @import("rope/array-vec.zig");
const Chunk = @import("rope/chunk.zig");
const Point = @import("rope/point.zig");
const sumTree = @import("rope/sum-tree.zig");
const iter = @import("iter.zig");

const Rope = @This();
const SumTree = sumTree.SumTree;
pub const Tree = SumTree(Chunk);

const Error = sumTree.Error || arrayVec.Error || std.mem.Allocator.Error;

/// The sum-tree of the rope's contents, stored as chunks of text.
tree: *Tree,
gpa: std.mem.Allocator,

pub fn init(gpa: std.mem.Allocator) std.mem.Allocator.Error!Rope {
    return .{
        .tree = try .init(gpa, void{}),
        .gpa = gpa,
    };
}

pub fn deinit(self: *Rope) void {
    self.tree.deinit(self.gpa);
}

/// Take a reference to a reader and from it, generates a rope containing the reader's output.
pub fn read(self: *Rope, reader: *std.Io.Reader) (std.Io.Reader.ShortError || Error)!void {
    var buffer: [Chunk.MAX_BASE]u8 = undefined;
    while (true) {
        const bytes = try reader.readSliceShort(&buffer);
        try self.push(buffer[0..bytes]);
        if (bytes < buffer.len) break;
    }
}

pub fn slice(self: *const Rope, start: usize, end: usize) Slice {
    var c = self.cursor(start);
    return c.slice(end);
}

pub fn sliceRows(self: *const Rope, start: usize, end: usize) Slice {
    const startByte = self.pointToOffset(.init(start, 0));
    const endByte = self.pointToOffset(.init(end + 1, 0)) - 1;
    return self.slice(startByte, endByte);
}

pub fn sliceLine(self: *const Rope, line: usize) Slice {
    return self.sliceRows(line, line);
}

/// Pushes the text to the end of the rope and rebalances the tree.
pub fn push(self: *Rope, text: []const u8) Error!void {
    var offset: usize = 0;
    while (offset < text.len) {
        // Split into chunks
        const chunkSize = @min(Chunk.MAX_BASE, text.len - offset);
        const chunkText = text[offset .. offset + chunkSize];
        const chunk: Chunk = try .init(chunkText);
        offset += chunkSize;

        // Push chunk and handle split
        if (try self.tree.push(self.gpa, chunk, {})) |right| {
            const root = try self.gpa.create(Tree);
            const left = self.tree;

            root.* = .{ .internal = .{
                .height = left.height() + 1,
                .summary = left.summary().add(&right.summary(), {}),
                .childSummaries = .init,
                .childTrees = .init,
            } };

            try root.internal.childTrees.push(left);
            try root.internal.childTrees.push(right);
            try root.internal.childSummaries.push(left.summary());
            try root.internal.childSummaries.push(right.summary());

            self.tree = root;
        }
    }
}

/// Mutates the rope by inserting the text at the given offset
pub fn insert(self: *Rope, offset: usize, text: []const u8) Error!void {
    if (offset >= self.len()) {
        return self.push(text);
    } else if (offset == 0) {
        var left = try init(self.gpa);
        errdefer left.deinit();
        try left.push(text);
        std.mem.swap(Tree, self.tree, left.tree); // left is now right
        return;
    }

    var right = try self.split(offset);
    var middle = try init(self.gpa);
    try middle.push(text);

    try self.join(&middle);
    if (right) |*r| {
        try self.join(r);
    }
}

pub fn remove(self: *Rope, offset: usize) Error!void {
    if (offset >= self.len()) return;

    var right = try self.split(offset);
    if (right) |*r| {
        defer r.deinit();
        var rest = try r.split(1);
        if (rest) |*r2| {
            try self.join(r2);
        }
    }
}

/// Splits the rope by mutation at the given offset, popping and returning the remaining rope.
pub fn split(self: *Rope, offset: usize) Error!?Rope {
    var right: Rope = .{ .tree = undefined, .gpa = self.gpa };
    right.tree = try self.splitTree(offset, 0) orelse return null;
    return right;
}
fn splitTree(self: *Rope, offset: usize, baseOffset: usize) Error!?*Tree {
    switch (self.tree.*) {
        .internal => |*internal| {
            // Find split boundary
            var currentOffset = baseOffset;
            var splitIndex: ?usize = null;

            for (internal.childSummaries.slice(), 0..) |sum, i| {
                if (currentOffset + sum.len > offset) {
                    splitIndex = i;
                    break;
                }
                currentOffset += sum.len;
            }
            const i = splitIndex orelse return null;

            // Split boundary point
            var middle: Rope = .{ .tree = undefined, .gpa = self.gpa };
            middle.tree = internal.childTrees.slice()[i];
            const rightStart = try middle.splitTree(offset, currentOffset);
            const hasRemainingChildren = i + 1 < internal.childTrees.slice().len;
            const hasRightContent = rightStart != null or hasRemainingChildren;

            if (hasRightContent) {
                // Build right tree
                var right = try self.gpa.create(Tree);
                errdefer right.deinit(self.gpa);
                right.* = .{ .internal = .{
                    .height = internal.height,
                    .summary = Chunk.Summary.zero(void{}),
                    .childSummaries = .init,
                    .childTrees = .init,
                } };

                if (rightStart) |tree| {
                    try right.internal.childTrees.push(tree);
                    const sum = tree.summary();
                    try right.internal.childSummaries.push(sum);
                    right.internal.summary = sum;
                }
                for (internal.childTrees.slice()[i + 1 ..], internal.childSummaries.slice()[i + 1 ..]) |child, sum| {
                    try right.internal.childTrees.push(child);
                    try right.internal.childSummaries.push(sum);
                    right.internal.summary = right.internal.summary.add(&sum, void{});
                }

                // Slice left tree
                internal.childTrees.len = i + 1;
                internal.childSummaries.len = i + 1;
                internal.summary = Chunk.Summary.zero(void{});
                for (internal.childSummaries.slice()) |sum| {
                    internal.summary = internal.summary.add(&sum, void{});
                }
                return right;
            } else {
                return null;
            }
        },
        .leaf => |*leaf| {
            // Find split boundary
            var currentOffset = baseOffset;
            var splitIndex: ?usize = null;
            var splitText: usize = 0;

            for (leaf.items.slice(), 0..) |chunk, i| {
                if (currentOffset + chunk.text.len > offset) {
                    splitIndex = i;
                    splitText = offset - currentOffset;
                    break;
                }
                currentOffset += chunk.text.len;
            }
            const i = splitIndex orelse return null;

            // Split boundary point
            var middle = leaf.items.slice()[i];
            const rightStart: Chunk = try .init(middle.slice()[splitText..]);

            // Build right tree
            var right = try self.gpa.create(Tree);
            errdefer right.deinit(self.gpa);
            right.* = .{ .leaf = .{
                .summary = rightStart.summary(void{}),
                .items = .init,
                .itemSummaries = .init,
            } };
            try right.leaf.items.push(rightStart);
            try right.leaf.itemSummaries.push(rightStart.summary(void{}));
            for (leaf.items.slice()[i + 1 ..]) |item| {
                try right.leaf.items.push(item);
                const sum = item.summary(void{});
                try right.leaf.itemSummaries.push(sum);
                right.leaf.summary = right.leaf.summary.add(&sum, void{});
            }

            // Slice left tree
            leaf.items.sliceMut()[i] = try .init(middle.text.slice()[0..splitText]);
            leaf.items.len = i + 1;
            leaf.summary = Chunk.Summary.zero(void{});
            for (leaf.items.slice()) |item| {
                leaf.summary = leaf.summary.add(&item.summary(void{}), void{});
            }
            return right;
        },
    }
}

/// Joins another rope to the end of this rope.
pub fn join(self: *Rope, other: *Rope) Error!void {
    if (other.len() == 0) {
        other.deinit();
        return;
    }
    if (self.len() == 0) {
        std.mem.swap(Tree, self.tree, other.tree);
        other.deinit();
        return;
    }
    try self.joinTree(other);
}
fn joinTree(self: *Rope, other: *Rope) Error!void {
    const leftHeight = self.tree.height();
    const rightHeight = other.tree.height();
    if (leftHeight == rightHeight) {
        const parent = try self.gpa.create(Tree);
        errdefer parent.deinit(self.gpa);
        parent.* = .{ .internal = .{
            .height = leftHeight + 1,
            .summary = self.tree.summary().add(&other.tree.summary(), void{}),
            .childSummaries = .init,
            .childTrees = .init,
        } };

        try parent.internal.childTrees.push(self.tree);
        try parent.internal.childTrees.push(other.tree);
        try parent.internal.childSummaries.push(self.summary());
        try parent.internal.childSummaries.push(other.summary());
        self.tree = parent;
    } else if (leftHeight > rightHeight) {
        try self.joinTreeEdge(false, other);
    } else {
        std.mem.swap(Tree, self.tree, other.tree);
        try self.joinTreeEdge(true, other);
    }
    other.tree = undefined;
}
fn joinTreeEdge(self: *Rope, comptime left: bool, other: *Rope) Error!void {
    switch (self.tree.*) {
        .internal => |*internal| {
            const i = if (left) 0 else internal.childTrees.len - 1;
            const child = internal.childTrees.slice()[i];

            const childHeight = child.height();
            const otherHeight = other.tree.height();
            if (childHeight > otherHeight) {
                var childRope: Rope = .{ .tree = child, .gpa = self.gpa };
                try childRope.joinTreeEdge(left, other);

                internal.childSummaries.sliceMut()[i] = child.summary();
                internal.summary = Chunk.Summary.zero(void{});
                for (internal.childSummaries.slice()) |sum| {
                    internal.summary = internal.summary.add(&sum, void{});
                }
            } else if (childHeight == otherHeight) {
                if (left) {
                    try internal.childTrees.insert(0, other.tree);
                    try internal.childSummaries.insert(0, other.summary());
                } else {
                    try internal.childTrees.push(other.tree);
                    try internal.childSummaries.push(other.summary());
                }
                internal.summary = internal.summary.add(&other.summary(), void{});
            } else {
                const parent = try self.gpa.create(Tree);
                errdefer parent.deinit(self.gpa);
                parent.* = .{ .internal = .{
                    .height = self.tree.height() + 1,
                    .summary = other.summary().add(&child.summary(), void{}),
                    .childSummaries = .init,
                    .childTrees = .init,
                } };

                const first = if (left) other.tree else child;
                const second = if (left) child else other.tree;
                try parent.internal.childTrees.push(first);
                try parent.internal.childTrees.push(second);
                try parent.internal.childSummaries.push(first.summary());
                try parent.internal.childSummaries.push(second.summary());

                internal.childTrees.sliceMut()[i] = parent;
                internal.childSummaries.sliceMut()[i] = parent.summary();
                internal.summary = Chunk.Summary.zero(void{});
                for (internal.childSummaries.slice()) |sum| {
                    internal.summary = internal.summary.add(&sum, void{});
                }
            }
        },
        .leaf => {
            const parent = try self.gpa.create(Tree);
            errdefer parent.deinit(self.gpa);

            parent.* = .{ .internal = .{
                .height = @max(self.tree.height(), other.tree.height()) + 1,
                .summary = self.tree.summary().add(&other.tree.summary(), void{}),
                .childSummaries = .init,
                .childTrees = .init,
            } };

            const first = if (left) other.tree else self.tree;
            const second = if (left) self.tree else other.tree;
            try parent.internal.childTrees.push(first);
            try parent.internal.childTrees.push(second);
            try parent.internal.childSummaries.push(first.summary());
            try parent.internal.childSummaries.push(second.summary());

            self.tree = parent;
        },
    }
}

/// Returns the summary of the rope's contents.
pub fn summary(self: *const Rope) Chunk.Summary {
    return self.tree.summary();
}

/// Returns the length of the rope's contents in bytes.
pub fn len(self: *const Rope) usize {
    return self.summary().len;
}

/// Returns the number of newline characters in the rope.
pub fn lines(self: *const Rope) usize {
    return self.summary().lines.row;
}

pub fn pointToOffset(self: *const Rope, point: Point) usize {
    const selfSummary = self.summary();
    if (point.cmp(&selfSummary.lines).gte()) return selfSummary.len;

    const result = self.tree.find(sumTree.Dimensions(Point, Point.USize, null), Point, void{}, &point, .left);
    const start = result[0];
    const item = result[2];
    const overshoot = point.sub(&start.d1);
    return start.d2.inner + if (item) |chunk| chunk.asSlice().pointToOffset(overshoot) else 0;
}

pub fn offsetToPoint(self: *const Rope, offset: usize) Point {
    const sum = self.summary();
    if (offset > sum.len) {
        return sum.lines;
    }
    const target: Point.USize = .{ .inner = offset };
    const result = self.tree.find(sumTree.Dimensions(Point.USize, Point, null), Point.USize, void{}, &target, .left);
    var start = result[0];
    const item = result[2];
    const overshoot = offset - start.d1.inner;
    return start.d2.add(if (item) |chunk| &chunk.asSlice().offsetToPoint(overshoot) else &Point.zero(void{}));
}

/// Writes the contents of the rope to the writer, without flushing it.
pub fn format(self: *const Rope, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    const visitor: Tree.ThisVisitor(*std.Io.Writer, std.Io.Writer.Error) = .{
        .visitInternal = null,
        .visitLeaf = formatVisitor,
    };
    try visitor.visit(self.tree, writer);
}
fn formatVisitor(leaf: *const Tree.Leaf, context: *std.Io.Writer) std.Io.Writer.Error!void {
    for (leaf.items.slice()) |chunk| {
        const s = chunk.slice();
        _ = try context.write(s);
    }
}

/// Allocates and returns a string with the contents of the rope written to the string.
///
/// Deallocates the string upon error.
pub fn toString(
    self: *const Rope,
    gpa: std.mem.Allocator,
) (std.mem.Allocator.Error || std.Io.Writer.Error)![]u8 {
    var buffer = try gpa.alloc(u8, self.len());
    errdefer gpa.free(buffer);
    var stream = std.Io.Writer.fixed(&buffer);
    self.format(&stream);

    return buffer;
}

pub fn cursor(self: *const Rope, offset: usize) Cursor {
    return .{ .rope = self.tree, .offset = offset };
}

pub const Cursor = struct {
    rope: *const Tree,
    offset: usize = 0,

    pub fn slice(self: *Cursor, endOffset: usize) Slice {
        var i: usize = 0;
        var current = self.rope;

        while (true) {
            // Find the shallowest node containing `offset..endOffset`.
            switch (current.*) {
                .internal => |*internal| {
                    var narrowed = false;
                    var start = i;
                    var end = i;
                    for (internal.childTrees.slice(), internal.childSummaries.slice()) |t, s| {
                        end += s.len;
                        if (start < self.offset and end > endOffset) {
                            i = start;
                            current = t;
                            narrowed = true;
                        }
                        start += s.len;
                    }
                    if (!narrowed) {
                        return .{
                            .tree = current,
                            .trimStart = self.offset - start,
                            .trimEnd = end - endOffset,
                        };
                    }
                },
                .leaf => |*leaf| {
                    const end = i + leaf.summary.len;
                    return .{
                        .tree = current,
                        .trimStart = self.offset - i,
                        .trimEnd = end - endOffset,
                    };
                },
            }
        }
    }
};

pub const Slice = struct {
    tree: *const Tree,
    trimStart: usize,
    trimEnd: usize,

    pub fn len(self: *const Slice) usize {
        return self.tree.summary().len -| self.trimStart -| self.trimEnd;
    }

    pub fn visit(
        self: *const Slice,
        comptime C: type,
        comptime E: ?type,
        f: fn ([]const u8, C) if (E) |_E| _E!void else void,
        context: C,
    ) if (E) |_E| _E!void else void {
        return self.visitDirection(false, C, E, f, context);
    }
    pub fn visitReverse(
        self: *const Slice,
        comptime C: type,
        comptime E: ?type,
        f: fn ([]const u8, C) if (E) |_E| _E!void else void,
        context: C,
    ) if (E) |_E| _E!void else void {
        return self.visitDirection(true, C, E, f, context);
    }
    pub fn visitDirection(
        self: *const Slice,
        comptime reverse: bool,
        comptime C: type,
        comptime E: ?type,
        f: fn ([]const u8, C) if (E) |_E| _E!void else void,
        context: C,
    ) if (E) |_E| _E!void else void {
        const Visit = struct {
            const Context = struct {
                context: C,
                trimStart: usize,
                remainder: usize,
            };

            pub fn visitLeaf(leaf: *const Tree.Leaf, c: *Context) if (E) |_E| _E!void else void {
                // Start by finding chunk bounds
                var chunks = leaf.items.slice();
                var firstChunk: usize = 0;
                var lastChunk: usize = chunks.len - 1;
                var trimStart: usize = c.trimStart;
                var trimEnd: usize = c.remainder;
                for (chunks, 0..) |chunk, i| {
                    const chunkSlice = chunk.slice();
                    if (c.trimStart > chunkSlice.len) {
                        c.trimStart -= chunkSlice.len;
                        continue;
                    } else if (c.trimStart > 0) {
                        firstChunk = i;
                        trimStart = c.trimStart;
                        c.trimStart = 0;
                    }
                    if (c.remainder == 0) {
                        lastChunk = i;
                        trimEnd = chunkSlice.len;
                        break;
                    } else if (c.remainder < chunkSlice.len) {
                        lastChunk = i;
                        trimEnd = c.remainder;
                        c.remainder = 0;
                        break;
                    } else {
                        c.remainder -= chunkSlice.len;
                    }
                }
                // Then iterate through chunk bounds in given order
                chunks = chunks[firstChunk .. lastChunk + 1];
                for (0..chunks.len) |i| {
                    const index = if (reverse) chunks.len - i - 1 else i;
                    const chunk = chunks[index];
                    var chunkSlice = chunk.slice();
                    if (index == 0) {
                        chunkSlice = chunkSlice[trimStart..];
                    }
                    if (index == chunks.len - 1) {
                        chunkSlice = chunkSlice[0..trimEnd];
                    }
                    if (E) |_| {
                        try f(chunkSlice, c.context);
                    } else {
                        f(chunkSlice, c.context);
                    }
                }
            }
        };
        const visitor: Tree.ThisVisitor(*Visit.Context, E) = .{
            .visitInternal = null,
            .visitLeaf = Visit.visitLeaf,
        };
        var c: Visit.Context = .{
            .context = context,
            .trimStart = self.trimStart,
            .remainder = self.len(),
        };
        return visitor.visitDirection(reverse, self.tree, &c);
    }

    /// Writes the contents of the rope to the writer, without flushing it.
    pub fn format(self: *const Slice, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try self.visit(*std.Io.Writer, std.Io.Writer.Error, sliceFormatVisitor, writer);
    }
    fn sliceFormatVisitor(chunk: []const u8, context: *std.Io.Writer) std.Io.Writer.Error!void {
        _ = try context.write(chunk);
    }
};

test read {
    // Arrange
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    // input
    const source = "The quick brown fox\njumps\nover\nthe\nlazy\ndog.";
    var reader = std.Io.Reader.fixed(source);
    // output
    var buffer: [44]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var rope: Rope = try .init(alloc);

    // Act
    try rope.read(&reader);

    // Assert
    try writer.print("{f}", .{rope});
    try std.testing.expect(source.len > Chunk.MAX_BASE);
    try std.testing.expectEqualStrings(source, &buffer);
    rope.deinit();
    try std.testing.expectEqual(std.heap.Check.ok, gpa.deinit());
}

test slice {
    // Arrange
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    // input
    const source = "The quick brown fox\njumps\nover\nthe\nlazy\ndog.";
    try std.testing.expect(source.len > Chunk.MAX_BASE);
    var reader = std.Io.Reader.fixed(source);
    // output
    var buffer: [15]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var rope: Rope = try .init(alloc);
    try rope.read(&reader);

    // Act
    const ropeSlice = rope.slice(10, 25);

    // Assert
    try writer.print("{f}", .{ropeSlice});
    try std.testing.expectEqualStrings("brown fox\njumps", &buffer);
    rope.deinit();
    try std.testing.expectEqual(std.heap.Check.ok, gpa.deinit());
}

test sliceRows {
    // Arrange
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    // input
    const source = "The quick brown fox\njumps\nover\nthe\nlazy\ndog.";
    var reader = std.Io.Reader.fixed(source);
    // output
    var buffer: [10]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var rope: Rope = try .init(alloc);
    try rope.read(&reader);

    // Act
    const ropeSlice = rope.sliceRows(1, 2);

    // Assert
    try writer.print("{f}", .{ropeSlice});
    try std.testing.expect(source.len > Chunk.MAX_BASE);
    try std.testing.expectEqualStrings("jumps\nover", &buffer);
    rope.deinit();
    try std.testing.expectEqual(std.heap.Check.ok, gpa.deinit());
}

test sliceLine {
    // Arrange
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    // input
    const source = "The quick brown fox\njumps\nover\nthe\nlazy\ndog.";
    try std.testing.expect(source.len > Chunk.MAX_BASE);
    var reader = std.Io.Reader.fixed(source);
    // output
    var buffer: [5]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var rope: Rope = try .init(alloc);
    try rope.read(&reader);

    // Act
    const ropeSlice = rope.sliceLine(1);

    // Assert
    try writer.print("{f}", .{ropeSlice});
    try std.testing.expectEqualStrings("jumps", &buffer);
    rope.deinit();
    try std.testing.expectEqual(std.heap.Check.ok, gpa.deinit());
}

test pointToOffset {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    // input
    //              0123456789012345678 901234 5678
    //              0:0                  1:0    2:0
    //                                            2:2
    const source = "The quick brown fox\njumps\nover\nthe\nlazy\ndog.";
    // -----------------------------------------^ row 2 (26 chars)
    // -------------------------------------------^ row 2, column 2 (28 chars)
    var reader = std.Io.Reader.fixed(source);

    var rope: Rope = try .init(alloc);
    try rope.read(&reader);
    const offset = rope.pointToOffset(.{ .column = 2, .row = 2 });

    try std.testing.expectEqual(28, offset);
}

test offsetToPoint {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    // input
    //              0123456789012345678 901234 5678
    //              0:0                  1:0    2:0
    //                                            2:2
    const source = "The quick brown fox\njumps\nover\nthe\nlazy\ndog.";
    // -----------------------------------------^ row 2 (26 chars)
    // -------------------------------------------^ row 2, column 2 (28 chars)
    var reader = std.Io.Reader.fixed(source);
    var rope: Rope = try .init(alloc);
    try rope.read(&reader);

    const point = rope.offsetToPoint(28);

    try std.testing.expectEqual(2, point.column);
    try std.testing.expectEqual(2, point.row);
}

test split {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    // input
    //              0123456789012345678 901234 5
    const source = "The quick brown fox\njumps\nover\nthe\nlazy\ndog.";
    var reader = std.Io.Reader.fixed(source);
    // output
    var bufferLeft: [26]u8 = undefined;
    var writerLeft = std.Io.Writer.fixed(&bufferLeft);
    var bufferRight: [18]u8 = undefined;
    var writerRight = std.Io.Writer.fixed(&bufferRight);
    var rope: Rope = try .init(alloc);
    try rope.read(&reader);

    // Act
    var right = (try rope.split(26)).?;

    // Assert
    try writerLeft.print("{f}", .{rope});
    try std.testing.expectEqualStrings("The quick brown fox\njumps\n", &bufferLeft);
    try writerRight.print("{f}", .{right});
    try std.testing.expectEqualStrings("over\nthe\nlazy\ndog.", &bufferRight);
    rope.deinit();
    right.deinit();
    try std.testing.expectEqual(std.heap.Check.ok, gpa.deinit());
}

test join {
    // Arrange
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    // input
    const leftSource = "The quick brown fox\njumps\n";
    const rightSource = "over\nthe\nlazy\ndog.";
    var reader: std.Io.Reader = .fixed(leftSource);
    var leftRope: Rope = try .init(alloc);
    try leftRope.read(&reader);
    reader = .fixed(rightSource);
    var rightRope: Rope = try .init(alloc);
    try rightRope.read(&reader);
    // output
    var buffer: [44]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);

    // Act
    try leftRope.join(&rightRope);

    // Assert
    try writer.print("{f}", .{leftRope});
    try std.testing.expectEqualStrings("The quick brown fox\njumps\nover\nthe\nlazy\ndog.", &buffer);
    leftRope.deinit();
    try std.testing.expectEqual(std.heap.Check.ok, gpa.deinit());
}

test insert {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    // input
    //              0123456789012345678 901234 5
    const source = "The quick brown fox\njumps\nover\nthe\nlazy\ndog.";
    var reader = std.Io.Reader.fixed(source);
    var buffer: [49]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var rope: Rope = try .init(alloc);
    try rope.read(&reader);

    try rope.insert(10, "cool ");

    try writer.print("{f}", .{rope});
    try std.testing.expectEqualStrings("The quick cool brown fox\njumps\nover\nthe\nlazy\ndog.", &buffer);
    rope.deinit();
    try std.testing.expectEqual(std.heap.Check.ok, gpa.deinit());
}

test remove {
    // Arrange
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    // input
    //              01234567890123456789
    const source = "The quick brown fox\njumps\nover\nthe\nlazy\ndog.";
    var reader = std.Io.Reader.fixed(source);
    // output
    var buffer: [43]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var rope: Rope = try .init(alloc);
    try rope.read(&reader);

    // Act
    try rope.remove(19);

    // Assert
    try writer.print("{f}", .{rope});
    try std.testing.expect(source.len > Chunk.MAX_BASE);
    try std.testing.expectEqualStrings("The quick brown foxjumps\nover\nthe\nlazy\ndog.", &buffer);
    rope.deinit();
    try std.testing.expectEqual(std.heap.Check.ok, gpa.deinit());
}
