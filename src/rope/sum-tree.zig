const std = @import("std");
const builtin = @import("builtin");

const iters = @import("../iter.zig");
const Ordering = @import("../ordering.zig").Ordering;
const arrayVec = @import("array-vec.zig");

const ArrayVec = arrayVec.ArrayVec;

pub const TREE_BASE = 6;
pub const TREE_MAX = TREE_BASE * 2;

pub const Error = error{
    EmptyInternal,
};

pub const Bias = enum {
    left,
    right,

    pub const default: Bias = .left;
};

/// A visitor is a type which can travel across the tree in a recursive (i.e. depth-first) fashion.
///
/// An error can provided as a type of "break" or as a legitimate error to prematurely end the
/// visitor.
pub fn Visitor(comptime T: type, comptime C: type, comptime E: ?type) type {
    const R = if (E) |_E| _E!void else void;
    const Noop = struct {
        pub fn visitInternal(_: *const SumTree(T).Internal, _: C) R {}
        pub fn visitLeaf(_: *const SumTree(T).Leaf, _: C) R {}
    };
    return struct {
        /// A function that will be called with each internal node of the sum-tree.
        visitInternal: *const fn (*const SumTree(T).Internal, C) R = Noop.visitInternal,
        /// A function that will be called with each leaf node of the sum-tree.
        visitLeaf: *const fn (*const SumTree(T).Leaf, C) R = Noop.visitLeaf,

        const Self = @This();

        /// Initiates the visitor against the node and all it's descendants.
        pub fn visit(self: *const Self, node: *const SumTree(T), context: C) R {
            return self.visitDirection(false, node, context);
        }
        pub fn visitReverse(self: *const Self, node: *const SumTree(T), context: C) R {
            return self.visitDirection(true, node, context);
        }

        pub fn visitDirection(self: *const Self, comptime reverse: bool, node: *const SumTree(T), context: C) R {
            switch (node.*) {
                .internal => |*internal| {
                    if (E) |_| {
                        try self.visitInternal(internal, context);
                    } else {
                        self.visitInternal(internal, context);
                    }
                    const children = internal.childTrees.slice();
                    for (0..children.len) |i| {
                        const child = if (reverse) children[children.len - i - 1] else children[i];
                        if (E) |_| {
                            try self.visit(child, context);
                        } else {
                            self.visit(child, context);
                        }
                    }
                },
                .leaf => |*leaf| {
                    if (E) |_| {
                        try self.visitLeaf(leaf, context);
                    } else {
                        self.visitLeaf(leaf, context);
                    }
                },
            }
        }
    };
}

pub fn Dimensions(comptime D1: type, comptime D2: type, comptime D3: ?type) type {
    return struct {
        d1: D1,
        d2: D2,
        d3: if (D3) |d| d else void,

        const Self = @This();

        pub fn zero(cx: D1.Context) Self {
            return .{ .d1 = .zero(cx), .d2 = .zero(cx), .d3 = if (D3) |_| .zero(cx) else {} };
        }

        pub fn clone(self: *const Self) Self {
            return .{ .d1 = self.d1.clone(), .d2 = self.d2.clone(), .d3 = if (D3) |_| self.d3.clone() else {} };
        }

        pub fn withAddedSummary(self: Self, summary: *const D1.Summary, cx: D1.Summary.Context) Self {
            var result = self;
            result.addSummary(summary, cx);
            return result;
        }

        pub fn addSummary(self: *Self, summary: *const D1.Summary, cx: D1.Summary.Context) void {
            self.d1.addSummary(summary, cx);
            self.d2.addSummary(summary, cx);
            if (D3) |_| self.d3.addSummary(summary, cx);
        }
    };
}

pub fn Cursor(comptime T: type) type {
    return struct {
        tree: *const SumTree(T),
    };
}

/// A sum-tree is a tree which contains a summary of all it's child nodes, where each child
/// node similarly contains a summary of it's children.
///
/// This provides a data structure that is efficient for navigation by binary searching against
/// the summary's heuristics.
pub fn SumTree(comptime T: type) type {
    return union(enum) {
        pub const Internal = struct {
            height: usize,
            summary: T.Summary,
            childSummaries: ArrayVec(T.Summary, TREE_MAX),
            childTrees: ArrayVec(*SumTree(T), TREE_MAX),
        };
        pub const Leaf = struct {
            summary: T.Summary,
            itemSummaries: ArrayVec(T.Summary, TREE_MAX),
            items: ArrayVec(T, TREE_MAX),

            pub fn iter(self: *const Leaf) iters.Iter(iters.SliceIter(T)) {
                return self.items.iter();
            }
        };

        /// A node that contains child nodes.
        internal: Internal,
        /// A node that contains data.
        leaf: Leaf,

        const Self = @This();

        /// Returns a visitor type with this sum-tree's data.
        pub fn ThisVisitor(comptime C: type, comptime E: ?type) type {
            return Visitor(T, C, E);
        }

        pub fn init(gpa: std.mem.Allocator, context: T.Summary.Context) std.mem.Allocator.Error!*Self {
            const self = try gpa.create(Self);
            self.* = .{ .leaf = .{
                .summary = .zero(context),
                .itemSummaries = .init,
                .items = .init,
            } };
            return self;
        }

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            switch (self.*) {
                .internal => |internal| {
                    for (internal.childTrees.slice()) |child| {
                        child.deinit(gpa);
                    }
                },
                .leaf => {},
            }
            gpa.destroy(self);
        }

        /// Returns a summary of the node and any descendants.
        pub fn summary(self: *const Self) T.Summary {
            return switch (self.*) {
                .internal => |internal| internal.summary,
                .leaf => |leaf| leaf.summary,
            };
        }

        /// Returns the number of generations withing the current node.
        pub fn height(self: *const Self) usize {
            return switch (self.*) {
                .internal => |internal| internal.height,
                .leaf => 0,
            };
        }

        pub fn cursor(self: *const Self) Cursor(T) {
            return .{ .tree = self };
        }

        pub fn FindResult(comptime D: type) type {
            return struct { start: D, end: D, item: ?*const T };
        }
        pub fn find(
            self: *const Self,
            comptime D: type,
            comptime Target: type,
            cx: T.Summary.Context,
            target: *const Target,
            bias: Bias,
        ) FindResult(D) {
            const treeEnd = D.zero(cx).withAddedSummary(&self.summary(), cx);
            const comparison = target.cmpSeekTarget(&treeEnd, cx);
            const isEnd = switch (comparison) {
                .greater => true,
                .equal => bias == .right,
                .less => false,
            };
            if (isEnd) {
                return .{ .start = treeEnd, .end = treeEnd, .item = null };
            }

            var position = D.zero(cx);
            var current = self;

            outer: while (true) {
                switch (current.*) {
                    .internal => |*internal| {
                        const childSummaries = internal.childSummaries.slice();
                        const childTrees = internal.childTrees.slice();
                        for (childSummaries, childTrees) |childSummary, childTree| {
                            const childEnd = position.withAddedSummary(&childSummary, cx);
                            const cmp = target.cmpSeekTarget(&childEnd, cx);
                            const targetInChild = cmp == .less or (cmp == .equal and bias == .left);
                            if (targetInChild) {
                                current = childTree;
                                continue :outer;
                            }
                            position = childEnd;
                        }
                        return .{ .start = position, .end = position, .item = null };
                    },
                    .leaf => |*leaf| {
                        const itemSummaries = leaf.itemSummaries.slice();
                        const items = leaf.items.slice();
                        for (itemSummaries, items) |itemSummary, *item| {
                            const itemEnd = position.withAddedSummary(&itemSummary, cx);
                            const cmp = target.cmpSeekTarget(&itemEnd, cx);
                            const itemFound = cmp == .less or (cmp == .equal and bias == .left);
                            if (itemFound) {
                                return .{ .start = position, .end = itemEnd, .item = item };
                            }
                            position = itemEnd;
                        }
                        return .{ .start = position, .end = position, .item = null };
                    },
                }
            }
        }

        /// Inserts the item to the last possible position within the tree.
        ///
        /// If the item won't fit into the current tree, it will return a
        /// dangling node for the caller to use in rebalancing the tree.
        pub fn push(
            self: *Self,
            gpa: std.mem.Allocator,
            item: T,
            context: T.Summary.Context,
        ) (arrayVec.Error || std.mem.Allocator.Error || Error)!?*Self {
            switch (self.*) {
                .leaf => |*leaf| {
                    const itemSummary = item.summary(context);
                    // If there's room, add it
                    if (leaf.items.len < TREE_MAX) {
                        try leaf.items.push(item);
                        try leaf.itemSummaries.push(itemSummary);
                        leaf.summary = leaf.summary.add(&itemSummary, context);
                        return null;
                    }
                    // Otherwise, split it
                    const newLeaf = try gpa.create(Self);
                    newLeaf.* = .{ .leaf = .{
                        .summary = itemSummary,
                        .items = .init,
                        .itemSummaries = .init,
                    } };

                    try newLeaf.leaf.items.push(item);
                    try newLeaf.leaf.itemSummaries.push(itemSummary);

                    // Return leaf to be handled by parent
                    self.checkInvariants(context);
                    return newLeaf;
                },
                .internal => |*internal| {
                    const lastChild = internal.childTrees.lastMut() orelse return Error.EmptyInternal;

                    // Push and handle split
                    if (try lastChild.*.push(gpa, item, context)) |newChild| {
                        const childSummary = newChild.summary();
                        // If child can fit into this node, push it
                        if (internal.childTrees.len < TREE_MAX) {
                            try internal.childTrees.push(newChild);
                            try internal.childSummaries.push(childSummary);
                            internal.summary = internal.summary.add(&childSummary, context);
                            self.checkInvariants(context);
                            return null;
                        }
                        // Otherwise, create a new node and propogate to parent
                        const newInternal = try gpa.create(Self);
                        newInternal.* = .{ .internal = .{
                            .height = internal.height,
                            .summary = childSummary,
                            .childSummaries = .init,
                            .childTrees = .init,
                        } };

                        try newInternal.internal.childTrees.push(newChild);
                        try newInternal.internal.childSummaries.push(newChild.summary());

                        self.checkInvariants(context);
                        return newInternal;
                    } else {
                        // Update our summary to match updated child
                        const lastChildSummary = lastChild.*.summary();
                        const internalLastChildSummary = internal.childSummaries.lastMut().?;
                        const difference = lastChildSummary.sub(internalLastChildSummary, context);

                        internalLastChildSummary.* = lastChildSummary;
                        internal.summary = internal.summary.add(&difference, context);
                        self.checkInvariants(context);
                        return null;
                    }
                },
            }
        }

        const CheckInvariantsContext = struct {
            cx: T.Summary.Context,

            pub fn visitInternal(internal: *const Internal, cx: *@This()) void {
                var computed = T.Summary.zero(cx.cx);
                for (internal.childSummaries.slice()) |childSummary| {
                    computed = computed.add(&childSummary, cx.cx);
                }
                if (!computed.eq(&internal.summary, cx.cx)) {
                    std.debug.panic(
                        \\Incorrect internal summary!
                        \\    Current: {any}
                        \\    Computed: {any}
                        \\
                    , .{ internal.summary, computed });
                }
                for (internal.childTrees.slice(), internal.childSummaries.slice(), 0..) |child, childSummary, i| {
                    const sum = child.summary();
                    if (!sum.eq(&childSummary, cx.cx)) {
                        std.debug.panic(
                            \\Incorrect child summary at {d}!
                            \\    Current: {any}
                            \\    Computed: {any}
                            \\
                        , .{ i, childSummary, sum });
                    }
                }
            }
            pub fn visitLeaf(leaf: *const Leaf, cx: *@This()) void {
                var computed = T.Summary.zero(cx.cx);
                for (leaf.itemSummaries.slice()) |itemSummary| {
                    computed = computed.add(&itemSummary, cx.cx);
                }
                if (!computed.eq(&leaf.summary, cx.cx)) {
                    std.debug.panic(
                        \\Incorrect leaf summary!
                        \\    Current: {any}
                        \\    Computed: {any}
                        \\
                    , .{ leaf.summary, computed });
                }
                for (leaf.items.slice(), leaf.itemSummaries.slice(), 0..) |item, itemSummary, i| {
                    const sum = item.summary(cx.cx);
                    if (!sum.eq(&itemSummary, cx.cx)) {
                        std.debug.panic(
                            \\Incorrect item summary at {d}!
                            \\    Current: {any}
                            \\    Computed: {any}
                            \\
                        , .{ i, leaf.summary, computed });
                    }
                }
            }
        };
        pub fn checkInvariants(self: *const Self, context: T.Summary.Context) void {
            comptime if (builtin.mode != .debug) return;
            var cx: CheckInvariantsContext = .{ .cx = context };
            const visitor: ThisVisitor(*CheckInvariantsContext, null) = .{
                .visitInternal = CheckInvariantsContext.visitInternal,
                .visitLeaf = CheckInvariantsContext.visitLeaf,
            };

            visitor.visit(self, &cx);
        }
    };
}
