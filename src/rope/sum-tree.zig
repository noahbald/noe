const std = @import("std");

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
    return struct {
        /// A function that will be called with each internal node of the sum-tree.
        visitInternal: ?fn (*const SumTree(T).Internal, C) R,
        /// A function that will be called with each leaf node of the sum-tree.
        visitLeaf: ?fn (*const SumTree(T).Leaf, C) R,

        const Self = @This();

        /// Initiates the visitor against the node and all it's descendants.
        pub fn visit(self: *const Self, node: *const SumTree(T), context: C) R {
            switch (node.*) {
                .internal => |*internal| {
                    if (self.visitInternal) |f| {
                        if (E) |_| {
                            try f.?(internal, context);
                        } else {
                            f.?(internal, context);
                        }
                    }
                    for (internal.childTrees.slice()) |child| {
                        if (E) |_| {
                            try self.visit(child, context);
                        } else {
                            self.visit(child, context);
                        }
                    }
                },
                .leaf => |*leaf| {
                    if (self.visitLeaf) |f| {
                        if (E) |_| {
                            try f(leaf, context);
                        } else {
                            f(leaf, context);
                        }
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
            return .{ .d1 = .zero(cx), .d2 = .zero(cx), .d3 = if (D3) |_| .zero(cx) else void{} };
        }

        pub fn clone(self: *const Self) Self {
            return .{ .d1 = self.d1.clone(), .d2 = self.d2.clone(), .d3 = if (D3) |_| self.d3.clone() else void{} };
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

        pub fn find(
            self: *const Self,
            comptime D: type,
            comptime Target: type,
            cx: T.Summary.Context,
            target: *const Target,
            bias: Bias,
        ) struct { D, D, ?*const T } {
            const treeEnd = D.zero(cx).withAddedSummary(&self.summary(), cx);
            const comparison = target.cmpSeekTarget(&treeEnd, cx);
            const isEnd = switch (comparison) {
                .greater => true,
                .equal => bias == .right,
                .less => false,
            };
            if (isEnd) {
                return .{ treeEnd, treeEnd, null };
            }

            var pos: D = .zero(cx);
            if (self.findRecurse(D, Target, false, cx, target, bias, &pos)) |result| {
                return .{ pos, result[1], result[0] };
            } else {
                return .{ pos, pos, null };
            }
        }

        pub fn findRecurse(
            this: *const Self,
            comptime D: type,
            comptime Target: type,
            comptime EXACT: bool,
            cx: T.Summary.Context,
            target: *const Target,
            bias: Bias,
            position: *D,
        ) ?struct { *const T, D } {
            switch (this.*) {
                .internal => |*internal| {
                    var childTrees = internal.childTrees.iter();
                    var childSummaries = internal.childSummaries.iter();
                    while (true) {
                        const childTree = childTrees.next() orelse break;
                        const childSummary = childSummaries.next() orelse break;
                        const childEnd = position.withAddedSummary(childSummary, cx);

                        const comparison = target.cmpSeekTarget(&childEnd, cx);
                        const targetInChild = comparison == .less or (comparison == .equal and bias == .left);
                        if (targetInChild) {
                            return childTree.*.findRecurse(D, Target, false, cx, target, bias, position);
                        }
                        position.* = childEnd;
                    }
                },
                .leaf => |*leaf| {
                    var items = leaf.items.iter();
                    var itemSummaries = leaf.itemSummaries.iter();
                    while (true) {
                        const item = items.next() orelse break;
                        const itemSummary = itemSummaries.next() orelse break;
                        var childEnd = position.clone();
                        childEnd.addSummary(itemSummary, cx);

                        const comparison = target.cmpSeekTarget(&childEnd, cx);
                        const entryFound = if (EXACT) comparison == .equal else comparison == .less or (comparison == .equal and bias == .left);
                        if (entryFound) {
                            return .{ item, childEnd };
                        }
                        position.* = childEnd;
                    }
                },
            }
            return null;
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
                        .summary = T.Summary.zero(context),
                        .items = .init,
                        .itemSummaries = .init,
                    } };

                    try newLeaf.leaf.items.push(item);
                    try newLeaf.leaf.itemSummaries.push(itemSummary);
                    newLeaf.leaf.summary = newLeaf.leaf.summary.add(&itemSummary, context);

                    // Return leaf to be handled by parent
                    return newLeaf;
                },
                .internal => |*internal| {
                    const lastChild = internal.childTrees.lastMut() orelse return Error.EmptyInternal;

                    // Push and handle split
                    if (try lastChild.*.push(gpa, item, context)) |newChild| {
                        // If child can fit into this node, push it
                        if (internal.childTrees.len < TREE_MAX) {
                            try internal.childTrees.push(newChild);
                            try internal.childSummaries.push(newChild.summary());
                            internal.summary = internal.summary.add(&newChild.summary(), context);
                            return null;
                        }
                        // Otherwise, create a new node and propogate to parent
                        const newInternal = try gpa.create(Self);
                        newInternal.* = .{ .internal = .{
                            .height = internal.height,
                            .summary = newChild.summary(),
                            .childSummaries = .init,
                            .childTrees = .init,
                        } };

                        try newInternal.internal.childTrees.push(newChild);
                        try newInternal.internal.childSummaries.push(newChild.summary());

                        return newInternal;
                    } else {
                        // Update our summary to match updated child
                        const lastChildSummary = lastChild.*.summary();
                        const internalLastChildSummary = internal.childSummaries.lastMut().?;
                        const difference = lastChildSummary.sub(internalLastChildSummary, context);

                        internalLastChildSummary.* = lastChildSummary;
                        internal.summary = internal.summary.add(&difference, context);
                        return null;
                    }
                },
            }
        }
    };
}
