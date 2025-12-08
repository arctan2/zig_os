const std = @import("std");

pub const Cmp = enum {
    Eq,
    Gt,
    Lt
};

pub fn RBTree(comptime T: type, cmp: *const fn(*const T, *const T) Cmp) type {
    return struct {
        const Color = enum(u1) {
            Black,
            Red
        };

        pub const Node = struct {
            left: ?*Node,
            right: ?*Node,
            parent: ?*Node,
            color: Color,
            data: T,

            pub inline fn is(self: *const Node, color: Color) bool { return self.color == color; }

            pub fn create(allocator: std.mem.Allocator, data: T, parent: ?*Node) !*Node {
                const n = try allocator.create(Node);
                n.* = .{
                    .parent = parent,
                    .data = data,
                    .color = .Red,
                    .left = null,
                    .right = null,
                };
                return n;
            }

            pub fn destroy(self: *Node, allocator: std.mem.Allocator) void {
                allocator.destroy(self);
            }
        };

        const Self = @This();

        root: ?*Node,

        pub fn init() Self {
            return .{ .root = null };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) !void {
            if(self.root == null) return;

            var stack = std.ArrayList(*Node).empty;
            defer stack.deinit(allocator);
            try stack.append(allocator, self.root.?);

            while(stack.pop()) |n| {
                if(n.left) |l| try stack.append(allocator, l);
                if(n.right) |r| try stack.append(allocator, r);
                n.destroy(allocator);
            }
        }

        //    n               c
        //     \             / \
        //      c   ---->   n   b
        //     / \           \
        //    a   b           a
        fn rotateLeft(self: *Self, node: *Node) void {
            const child = node.right.?;
            node.right = child.left;
            if(node.right) |a| a.parent = node;
            child.parent = node.parent;

            if(child.parent) |p| {
                (if(p.left == node) p.left else p.right) = child;
            } else {
                self.root = child;
            }
            node.parent = child;
            child.left = node;
        }

        //        n               c
        //       /               / \
        //      c   ---->       a   n
        //     / \                 /
        //    a   b               b
        fn rotateRight(self: *Self, node: *Node) void {
            const child = node.left.?;
            node.left = child.right;
            if(node.left) |b| b.parent = node;
            child.parent = node.parent;

            if(child.parent) |p| {
                (if(p.left == node) p.left else p.right) = child;
            } else {
                self.root = child;
            }
            node.parent = child;
            child.right = node;
        }

        fn insertFix(self: *Self, n: *Node) void {
            var node = n;
            var parent = node.parent;

            while(parent) |_parent| {
                var p = _parent;
                if(p.is(.Black) or p.parent == null) break;
                var grand_parent = p.parent.?;
                var uncle = grand_parent.right;

                if(p != uncle) {
                    if(uncle) |u| {
                        //       G            g
                        //      / \          / \
                        //     p   u  -->   P   U
                        //    /            /
                        //   n            n
                        if(u.is(.Red)) {
                            u.color = .Black;
                            p.color = .Black;
                            node = grand_parent;
                            parent = grand_parent.parent;
                            grand_parent.color = .Red;
                            continue;
                        }
                    }

                    if(p.right == node) {
                        //      G             G
                        //     / \           / \
                        //    p   U  -->    n   U
                        //     \           /
                        //      n         p
                        self.rotateLeft(p);
                        p = n;
                    }


                    //        G           P
                    //       / \         / \
                    //      p   U  -->  n   g
                    //     /                 \
                    //    n                   U

                    self.rotateRight(grand_parent);
                    grand_parent.color = .Red;
                    p.color = .Black;
                    break;
                } else {
                    uncle = grand_parent.left;
                    if(uncle) |u| {
                        //       G            g
                        //      / \          / \
                        //     u   p  -->   U   P
                        //          \            \
                        //           n            n
                        if(u.is(.Red)) {
                            u.color = .Black;
                            p.color = .Black;
                            node = grand_parent;
                            parent = grand_parent.parent;
                            grand_parent.color = .Red;
                            continue;
                        }
                    }

                    if(p.left == node) {
                        //      G             G
                        //     / \           / \
                        //    U   p  -->    U   n
                        //       /               \
                        //      n                 p
                        self.rotateRight(p);
                        p = n;
                    }


                    //        G           P
                    //       / \         / \
                    //      U   p  -->  g   n
                    //           \     /
                    //            n   U     

                    self.rotateLeft(grand_parent);
                    grand_parent.color = .Red;
                    p.color = .Black;
                    break;
                }
            }
        }

        pub fn printDfs(node: ?*Node, indent: usize) void {
            for(0..indent) |_| std.debug.print("\t", .{});
            if(node) |n| {
                std.debug.print("{c}({})\n", .{@as(u8, if(n.color == .Red) 'R' else 'B'), n.data});
                if(n.left == null and n.right == null) return;
                printDfs(n.left, indent + 1);
                printDfs(n.right, indent + 1);
            } else {
                std.debug.print("nil\n", .{});
            }
        }

        pub fn printDebug(self: *Self) void {
            if (self.root) |r| {
                printDfs(r, 0);
            } else {
                std.debug.print("(empty tree)\n", .{});
            }
        }

        pub fn insert(self: *Self, allocator: std.mem.Allocator, data: T) error{Duplicate, OutOfMemory}!void {
            var parent: ?*Node = null;
            var cur_node = self.root;

            while(cur_node) |cur| {
                parent = cur;
                switch(cmp(&data, &cur.data)) {
                    .Eq => return error.Duplicate,
                    .Gt => cur_node = cur.right,
                    .Lt => cur_node = cur.left
                }
            }

            const node = try Node.create(allocator, data, parent);

            if(parent) |p| {
                (switch(cmp(&data, &p.data)) { .Gt => p.right, else => p.left }) = node;
                if(p.color == .Red) self.insertFix(node);
            } else {
                self.root = node;
            }
            self.root.?.color = .Black;
        }
    };
}

fn cmpFn(a: *const usize, b: *const usize) Cmp {
    if(a.* == b.*) return .Eq;
    return if(a.* < b.*) .Lt else .Gt;
}

test "basic insert" {
    const allocator = std.testing.allocator;
    var rbtree = RBTree(usize, cmpFn).init();
    defer rbtree.deinit(allocator) catch {};

    for(1..6) |i| {
        try rbtree.insert(allocator, i);
    }

    const expect = std.testing.expect;

    try expect(rbtree.root != null);
    const root = rbtree.root.?;

    try expect(root.data == 2);

    try expect(root.left != null);
    try expect(root.left.?.data == 1);

    try expect(root.right != null);
    try expect(root.right.?.data == 4);

    try expect(root.right.?.left != null);
    try expect(root.right.?.left.?.data == 3);

    try expect(root.right.?.right != null);
    try expect(root.right.?.right.?.data == 5);
}
