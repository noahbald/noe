pub const Ordering = enum(u2) {
    less = 0,
    equal = 1,
    greater = 2,

    pub fn cmp(a: anytype, b: anytype) Ordering {
        if (a < b) return .less else if (a == b) return .equal else return .greater;
    }

    pub fn gte(self: Ordering) bool {
        return @intFromEnum(self) > 1;
    }

    pub fn lte(self: Ordering) bool {
        return @intFromEnum(self) < 1;
    }

    pub fn is(self: Ordering, other: Ordering) bool {
        return @intFromEnum(self) == @intFromEnum(other);
    }
};
