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
        const Context = struct {
            context: C,
            trimStart: usize,
            remainder: usize,
        };
        const Visit = struct {
            pub fn visitLeaf(leaf: *const Tree.Leaf, c: *Context) if (E) |_E| _E!void else void {
                for (leaf.items.slice()) |chunk| {
                    var chunkSlice = chunk.slice();
                    if (c.trimStart > chunkSlice.len) {
                        c.trimStart -= chunkSlice.len;
                        continue;
                    } else if (c.trimStart > 0) {
                        chunkSlice = chunkSlice[c.trimStart..];
                        c.trimStart = 0;
                    }
                    if (c.remainder == 0) {
                        break;
                    } else if (c.remainder < chunkSlice.len) {
                        chunkSlice = chunkSlice[0..c.remainder];
                        c.remainder = 0;
                    } else {
                        c.remainder -= chunkSlice.len;
                    }
                    if (E) |_| {
                        try f(chunkSlice, c.context);
                    } else {
                        f(chunkSlice, c.context);
                    }
                }
            }
        };
        const visitor: Tree.ThisVisitor(*Context, E) = .{
            .visitInternal = null,
            .visitLeaf = Visit.visitLeaf,
        };
        var c: Context = .{
            .context = context,
            .trimStart = self.trimStart,
            .remainder = self.len(),
        };
        return visitor.visit(self.tree, &c);
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
    try std.testing.expectEqual(gpa.deinit(), std.heap.Check.ok);
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
    try std.testing.expectEqual(gpa.deinit(), std.heap.Check.ok);
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
    try std.testing.expectEqual(gpa.deinit(), std.heap.Check.ok);
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
    try std.testing.expectEqual(gpa.deinit(), std.heap.Check.ok);
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
