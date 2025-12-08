const std = @import("std");
const rbtree = @import("rbtree.zig");
pub const RBTree = rbtree.RBTree;

comptime {
    std.testing.refAllDecls(rbtree);
}
