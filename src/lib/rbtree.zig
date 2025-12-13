const std = @import("std");
const utils = @import("utils");
const expect = std.testing.expect;

const Color = enum(u1) {
    Black,
    Red
};

pub fn RBTree(comptime K: type, comptime V: type, comptime Context: type, cmp: *const fn(Context, K, K) std.math.Order) type {
    return struct {
        pub const Node = struct {
            left: ?*Node,
            right: ?*Node,
            parent: ?*Node,
            color: Color,
            key: K,
            value: V,

            pub inline fn is(self: *const Node, color: Color) bool { return self.color == color; }

            pub fn create(allocator: std.mem.Allocator, key: K, value: V, parent: ?*Node) !*Node {
                const n = try allocator.create(Node);
                n.* = .{
                    .parent = parent,
                    .key = key,
                    .value = value,
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
        context: Context,

        pub fn init(context: Context) Self {
            return .{ .root = null, .context = context };
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

        fn setParents(self: *Self, old: *Node, new: *Node, color: Color) void {
            const parent = old.parent;
            new.parent = old.parent;
            new.color = old.color;
            old.parent = new;
            old.color = color;
            self.changeChild(old, new, parent);
        }

        fn insertFix(self: *Self, n: *Node) void {
            var node = n;
            var parent = node.parent;
            var tmp: ?*Node = null;

            while(parent) |_parent| {
                var p = _parent;
                if(p.is(.Black) or p.parent == null) break;
                var grand_parent = p.parent.?;

                tmp = grand_parent.right;
                if(p != tmp) {
                    if(tmp) |t| {
                        //       G            g
                        //      / \          / \
                        //     p   u  -->   P   U
                        //    /            /
                        //   n            n
                        if(t.is(.Red)) {
                            t.color = .Black;
                            p.color = .Black;
                            node = grand_parent;
                            parent = node.parent;
                            node.color = .Red;
                            continue;
                        }
                    }

                    tmp = p.right;
                    if(node == tmp) {
                        //      G             G
                        //     / \           / \
                        //    p   U  -->    n   U
                        //     \           /
                        //      n         p
                        tmp = node.left;
                        p.right = tmp;
                        node.left = p;
                        if(tmp) |t| {
                            t.parent = parent;
                            t.color = .Black;
                        }
                        p.parent = node;
                        p.color = .Red;
                        p = node;
                        tmp = node.right;
                    }


                    //        G           P
                    //       / \         / \
                    //      p   U  -->  n   g
                    //     /                 \
                    //    n                   U

                    grand_parent.left = tmp;
                    p.right = grand_parent;

                    if(tmp) |t| {
                        t.color = .Black;
                        t.parent = grand_parent;
                    }

                    self.setParents(grand_parent, p, .Red);
                    break;
                } else {
                    tmp = grand_parent.left;
                    if(tmp) |t| {
                        //       G            g
                        //      / \          / \
                        //     p   u  -->   P   U
                        //    /            /
                        //   n            n
                        if(t.is(.Red)) {
                            t.color = .Black;
                            p.color = .Black;
                            node = grand_parent;
                            parent = node.parent;
                            node.color = .Red;
                            continue;
                        }
                    }

                    tmp = p.left;
                    if(node == tmp) {
                        //      G             G
                        //     / \           / \
                        //    p   U  -->    n   U
                        //     \           /
                        //      n         p
                        tmp = node.right;
                        p.left = tmp;
                        node.right = p;
                        if(tmp) |t| {
                            t.parent = parent;
                            t.color = .Black;
                        }
                        p.parent = node;
                        p.color = .Red;
                        p = node;
                        tmp = node.left;
                    }


                    //        G           P
                    //       / \         / \
                    //      p   U  -->  n   g
                    //     /                 \
                    //    n                   U

                    grand_parent.right = tmp;
                    p.left = grand_parent;

                    if(tmp) |t| {
                        t.color = .Black;
                        t.parent = grand_parent;
                    }

                    self.setParents(grand_parent, p, .Red);
                    break;
                }
            }
        }

        pub fn printDfs(node: ?*Node, indent: usize) void {
            for(0..indent) |_| std.debug.print("\t", .{});
            if(node) |n| {
                std.debug.print("{c}({})\n", .{@as(u8, if(n.color == .Red) 'R' else 'B'), n.key});
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

        pub fn insert(self: *Self, allocator: std.mem.Allocator, key: K, value: V) error{Duplicate, OutOfMemory}!*Node {
            var parent: ?*Node = null;
            var cur_node = self.root;

            while(cur_node) |cur| {
                parent = cur;
                switch(cmp(self.context, key, cur.key)) {
                    .eq => return error.Duplicate,
                    .gt => cur_node = cur.right,
                    .lt => cur_node = cur.left
                }
            }

            const node = try Node.create(allocator, key, value, parent);

            if(parent) |p| {
                (switch(cmp(self.context, key, p.key)) {
                    .gt => p.right,
                    else => p.left
                }) = node;
                if(p.color == .Red) self.insertFix(node);
            } else {
                self.root = node;
            }
            self.root.?.color = .Black;

            return node;
        }

        pub fn search(self: *const Self, key: K) ?*Node {
            var cur = self.root;

            while(cur) |c| {
                switch(cmp(self.context, key, c.key)) {
                    .eq => return c,
                    .lt => cur = c.left,
                    .gt => cur = c.right
                }
            }

            return null;
        }

        inline fn findMinNode(node: *Node) *Node {
            var cur = node;
            while(true) {
                if(cur.left) |l| cur = l else break;
            }
            return cur;
        }

        fn changeChild(self: *Self, old: *Node, new: ?*Node, parent: ?*Node) void {
            if(parent) |p| {
                (if(p.left == old) p.left else p.right) = new;
            } else {
                self.root = new;
            }
        }

        fn deleteFix(self: *Self, n: *Node) void {
            var parent: ?*Node = n;
            var sibling: ?*Node = null;
            var node: ?*Node = null;
            var tmp1: ?*Node = null;
            var tmp2: ?*Node = null;

            while(parent) |p| {
                sibling = p.right;
                if(node != sibling) {
                    if(sibling.?.is(.Red)) {
                        tmp1 = sibling.?.left;
                        p.right = tmp1;
                        sibling.?.left = p;
                        tmp1.?.parent = p;
                        tmp1.?.color = .Black;
                        self.setParents(p, sibling.?, .Red);
                        sibling = tmp1;
                    }

                    tmp1 = sibling.?.right;
                    if(tmp1 == null or tmp1.?.is(.Black)) {
                        tmp2 = sibling.?.left;
                        if(tmp2 == null or tmp2.?.is(.Black)) {
                            sibling.?.color = .Red;

                            if(p.is(.Red)) {
                                p.color = .Black;
                            } else {
                                node = parent;
                                parent = node.?.parent;
                                if(parent) |_| continue;
                            }

                            break;
                        }

                        tmp1 = tmp2.?.right;
                        sibling.?.left = tmp1;
                        tmp2.?.right = sibling;
                        p.right = tmp2;

                        if(tmp1) |t| {
                            t.parent = sibling;
                            t.color = .Black;
                        }
                        tmp1 = sibling;
                        sibling = tmp2;
                    }

                    tmp2 = sibling.?.left;
                    p.right = tmp2;
                    sibling.?.left = p;

                    tmp1.?.parent = sibling;
                    tmp1.?.color = .Black;
                    if(tmp2) |t| {
                        t.parent = p;
                    }
                    self.setParents(p, sibling.?, .Black);
                    break;
                } else {
                    sibling = p.left;
                    if(sibling.?.is(.Red)) {
                        tmp1 = sibling.?.right;
                        p.left = tmp1;
                        sibling.?.right = p;
                        tmp1.?.parent = p;
                        tmp1.?.color = .Black;
                        self.setParents(p, sibling.?, .Red);
                        sibling = tmp1;
                    }

                    tmp1 = sibling.?.left;
                    if(tmp1 == null or tmp1.?.is(.Black)) {
                        tmp2 = sibling.?.right;
                        if(tmp2 == null or tmp2.?.is(.Black)) {
                            sibling.?.color = .Red;

                            if(p.is(.Red)) {
                                p.color = .Black;
                            } else {
                                node = parent;
                                parent = node.?.parent;
                                if(parent) |_| continue;
                            }

                            break;
                        }

                        tmp1 = tmp2.?.left;
                        sibling.?.right = tmp1;
                        tmp2.?.left = sibling;
                        p.left = tmp2;

                        if(tmp1) |t| {
                            t.parent = sibling;
                            t.color = .Black;
                        }
                        tmp1 = sibling;
                        sibling = tmp2;
                    }

                    tmp2 = sibling.?.right;
                    p.left = tmp2;
                    sibling.?.right = p;

                    tmp1.?.parent = sibling;
                    tmp1.?.color = .Black;
                    if(tmp2) |t| {
                        t.parent = p;
                    }
                    self.setParents(p, sibling.?, .Black);
                    break;
                }
            }
        }

        pub fn remove(self: *Self, key: K) ?*Node {
            const node = self.search(key) orelse return null;
            var rebalance: ?*Node = null;

            if(node.left == null) {
                const right = node.right;
                self.changeChild(node, right, node.parent);

                if(right) |r| {
                    r.parent = node.parent;
                    r.color = node.color;
                } else if(node.is(.Black)) {
                    rebalance = node.parent;
                }
            } else if(node.right == null) {
                const left = node.left.?;
                left.parent = node.parent;
                left.color = node.color;
                self.changeChild(node, left, node.parent);
            } else {
                var successor = node.right.?;
                var tmp = node.right.?.left;
                var parent: ?*Node = null;
                var child2: ?*Node = null;

                if(tmp == null) {
                    parent = successor;
                    child2 = successor.right;
                } else {
                    successor = findMinNode(successor);
                    parent = successor.parent;
                    child2 = successor.right;

                    parent.?.left = child2;
                    successor.right = node.right;
                    node.right.?.parent = successor;
                }

                tmp = node.left;
                successor.left = tmp;
                tmp.?.parent = successor;
                
                tmp = node.parent;
                self.changeChild(node, successor, tmp);

                if(child2) |c| {
                    c.parent = parent;
                    c.color = .Black;
                } else if(successor.is(.Black)) {
                    rebalance = parent;
                }

                successor.parent = node.parent;
                successor.color = node.color;
            }

            if(rebalance) |r| {
                self.deleteFix(r);
            }

            return node;
        }

        pub fn removeDestroy(self: *Self, allocator: std.mem.Allocator, key: K) void {
            if(self.remove(key)) |n| {
                allocator.destroy(n);
            }
        }
    };
}

fn cmpFn(_: void, a: usize, b: usize) std.math.Order {
    if(a == b) return .eq;
    return if(a < b) .lt else .gt;
}

test "basic insert" {
    const allocator = std.testing.allocator;
    var rbtree = RBTree(usize, usize, void, cmpFn).init({});
    defer rbtree.deinit(allocator) catch {};

    for(1..6) |i| {
        _ = try rbtree.insert(allocator, i, i);
    }

    try expect(rbtree.root != null);
    const root = rbtree.root.?;

    try expect(root.key == 2);

    try expect(root.left != null);
    try expect(root.left.?.key == 1);

    try expect(root.right != null);
    try expect(root.right.?.key == 4);

    try expect(root.right.?.left != null);
    try expect(root.right.?.left.?.key == 3);

    try expect(root.right.?.right != null);
    try expect(root.right.?.right.?.key == 5);
}

test "insert loop and deinit" {
    const allocator = std.testing.allocator;
    var rbtree = RBTree(usize, usize, void, cmpFn).init({});
    defer rbtree.deinit(allocator) catch {};

    for(1..103) |i| {
        _ = try rbtree.insert(allocator, i, i);
    }
}

test "delete easy 1" {
    const allocator = std.testing.allocator;
    var rbtree = RBTree(usize, usize, void, cmpFn).init({});
    defer rbtree.deinit(allocator) catch {};

    const to_insert = [_]usize{10, 5, 15, 1};

    for(to_insert) |i| {
        _ = try rbtree.insert(allocator, i, i);
    }
    try expect(rbtree.root != null);

    try expect(rbtree.root.?.key == 10);
    try expect(rbtree.root.?.is(.Black));
    try expect(rbtree.root.?.right.?.is(.Black));
    try expect(rbtree.root.?.left.?.is(.Black));
}

test "delete sibling + far child red" {
    const allocator = std.testing.allocator;
    var rbtree = RBTree(usize, usize, void, cmpFn).init({});
    defer rbtree.deinit(allocator) catch {};

    const to_insert = [_]usize{10, 5, 15, 12, 18, 20};

    for(to_insert) |i| {
        _ = try rbtree.insert(allocator, i, i);
    }
    try expect(rbtree.root != null);
    
    rbtree.removeDestroy(allocator, 5);

    try expect(rbtree.root.?.key == 15);
    try expect(rbtree.root.?.is(.Black));

    try expect(rbtree.root.?.right.?.key == 18);
    try expect(rbtree.root.?.right.?.is(.Black));

    try expect(rbtree.root.?.left.?.key == 10);
    try expect(rbtree.root.?.left.?.is(.Black));

    try expect(rbtree.root.?.left.?.right.?.key == 12);
    try expect(rbtree.root.?.left.?.right.?.is(.Red));

    try expect(rbtree.root.?.right.?.right.?.key == 20);
    try expect(rbtree.root.?.right.?.right.?.is(.Red));
}

test "delete sibling black + near child red" {
    const allocator = std.testing.allocator;
    var rbtree = RBTree(usize, usize, void, cmpFn).init({});
    defer rbtree.deinit(allocator) catch {};

    const to_insert = [_]usize{10, 5, 15, 12, 18};

    for(to_insert) |i| {
        _ = try rbtree.insert(allocator, i, i);
    }
    try expect(rbtree.root != null);
    
    rbtree.removeDestroy(allocator, 5);

    try expect(rbtree.root.?.key == 15);
    try expect(rbtree.root.?.is(.Black));

    try expect(rbtree.root.?.left.?.key == 10);
    try expect(rbtree.root.?.left.?.is(.Black));

    try expect(rbtree.root.?.right.?.key == 18);
    try expect(rbtree.root.?.right.?.is(.Black));

    try expect(rbtree.root.?.left.?.right.?.key == 12);
    try expect(rbtree.root.?.left.?.right.?.is(.Red));
}

test "delete loop" {
    const allocator = std.testing.allocator;
    var rbtree = RBTree(usize, usize, void, cmpFn).init({});
    defer rbtree.deinit(allocator) catch {};

    for(1..100) |i| {
        _ = try rbtree.insert(allocator, i, i);
    }
    try expect(rbtree.root != null);

    for(1..100) |i| {
        rbtree.removeDestroy(allocator, i);
    }

    try expect(rbtree.root == null);
}

test "delete sequence 1" {
    const allocator = std.testing.allocator;
    var rbtree = RBTree(usize, usize, void, cmpFn).init({});
    defer rbtree.deinit(allocator) catch {};

    const to_insert = [_]usize{3, 1, 4};

    for(to_insert) |i| {
        _ = try rbtree.insert(allocator, i, i);
    }
    try expect(rbtree.root != null);
    try expect(rbtree.root.?.key == 3);
    
    for(to_insert) |i| {
        rbtree.removeDestroy(allocator, i);
    }

    try expect(rbtree.root == null);
}

test "delete sequence 2" {
    const allocator = std.testing.allocator;
    var rbtree = RBTree(usize, usize, void, cmpFn).init({});
    defer rbtree.deinit(allocator) catch {};

    const to_insert = [_]usize{ 2, 8, 1, 7, 6, 5, 4, 3 };

    for(to_insert) |i| {
        _ = try rbtree.insert(allocator, i, i);
    }
    try expect(rbtree.root != null);
    
    for(to_insert) |i| {
        rbtree.removeDestroy(allocator, i);
    }

    try expect(rbtree.root == null);
}

fn testWithSeed(seed: usize) !void {
    const allocator = std.testing.allocator;
    var rbtree = RBTree(usize, usize, void, cmpFn).init({});
    defer rbtree.deinit(allocator) catch {};

    var a: [100]usize = undefined;

    for (&a, 0..) |*elem, i| {
        elem.* = i + 1;
    }

    // const seed: u64 = 6;
    var prng = std.Random.DefaultPrng.init(seed);
    var rand = prng.random();

    var i: usize = a.len - 1;

    while (i > 0) : (i -= 1) {
        const j = rand.intRangeLessThan(usize, 0, i + 1);
        const tmp = a[i];
        a[i] = a[j];
        a[j] = tmp;
    }

    for(a) |v| {
        _ = try rbtree.insert(allocator, v, v);
    }

    for(a) |v| {
        rbtree.removeDestroy(allocator, v);
    }

    try expect(rbtree.root == null);
}

test "delete random loop" {
    if(!utils.isAllTestMode()) return;
    for(1..1000) |i| try testWithSeed(i);
}
