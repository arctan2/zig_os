pub fn ListNode(comptime ContainerT: type, field_name: []const u8) type {
    return struct {
        const Self = @This();
        next: ?*Self,

        pub fn container(self: *Self) *ContainerT {
            return @fieldParentPtr(field_name, self);
        }
    };
}

pub fn DListNode(comptime ContainerT: type, field_name: []const u8) type {
    return struct {
        const Self = @This();
        next: ?*Self = null,
        prev: ?*Self = null,

        pub fn container(self: *Self) *ContainerT {
            return @fieldParentPtr(field_name, self);
        }
    };
}

pub fn DoubleLinkedList(comptime ListNodeType: type) type {
    return struct {
        const List = @This();

        const Iterator = struct {
            const Iter = @This();
            cur: ?*ListNodeType = null,

            pub fn init(cur: ?*ListNodeType) Iter {
                return .{
                    .cur = cur
                };
            }

            pub fn next(self: *Iter) ?*ListNodeType {
                if(self.cur) |cur| {
                    self.cur = cur.next; 
                    return cur;
                }
                return null;
            }
        };

        head: ?*ListNodeType = null,
        tail: ?*ListNodeType = null,
        size: usize = 0,

        pub inline fn isEmpty(self: *List) bool {
            return self.size == 0;
        }

        fn decSize(self: *List) void {
            if(self.size > 0) self.size -= 1;
        }

        pub inline fn clear(self: *List) void {
            self.head = null;
            self.tail = null;
        }

        pub fn push(self: *List, node: *ListNodeType) void {
            defer self.size += 1;
            if(self.tail) |t| {
                t.next = node;
                node.prev = t;
                self.tail = node;
            } else {
                self.head = node;
                self.tail = node;
            }
        }

        pub fn pop_front(self: *List) ?*ListNodeType {
            if(self.head) |h| {
                defer self.decSize();
                if(h == self.tail.?) {
                    self.head = null;
                    self.tail = null;
                } else {
                    self.head = h.next;
                    if(self.head) |head| head.prev = null;
                }

                return h;
            }

            return null;
        }

        pub fn pop(self: *List) ?*ListNodeType {
            if(self.tail) |t| {
                defer self.decSize();
                if(t == self.head.?) {
                    self.head = null;
                    self.tail = null;
                } else {
                    const prev = t.prev.?;
                    t.prev = null;
                    prev.next = null;
                    self.tail = prev;
                }

                return t;
            }

            return null;
        }

        pub fn remove(self: *List, node: *ListNodeType) void {
            if(node.prev) |p| {
                defer self.decSize();
                p.next = node.next;
                (if(p.next) |next| next.prev else self.tail) = p;
            } else {
                _ = self.pop_front();
            }
        }

        pub fn iterator(self: *List) Iterator {
            return .init(self.head);
        }
    };
}

pub fn Queue(comptime ListNodeType: type) type {
    return struct {
        const Self = @This();

        head: ?*ListNodeType,
        tail: ?*ListNodeType,

        pub fn default() Self {
            return .{
                .head = null,
                .tail = null
            };
        }

        pub inline fn isEmpty(self: *Self) bool {
            return self.head == null;
        }

        pub fn enqueue(self: *Self, node: *ListNodeType) void {
            if(self.tail) |t| {
                t.next = node;
                self.tail = node;
            } else {
                self.head = node;
                self.tail = node;
            }
        }

        pub fn dequeue(self: *Self) ?*ListNodeType {
            if(self.head) |h| {
                if(h == self.tail.?) {
                    self.head = null;
                    self.tail = null;
                } else {
                    self.head = h.next;
                }

                return h;
            }

            return null;
        }

        pub fn insertFront(self: *Self, node: *ListNodeType) void {
            node.next = self.head;
            self.head = node;
            if(self.tail == null) self.tail = node;
        }

        pub fn remove(self: *Self, node: *ListNodeType) void {
            var cur = self.head;
            var prev: ?*ListNodeType = null;

            while(cur) |c| {
                if(c == node) break;
                prev = c;
                cur = c.next;
            }

            if(prev) |p| {
                if(cur) |c| p.next = c.next;
                if(p.next == null) self.tail = p;
            } else {
                _ = self.dequeue();
            }
        }
    };
}

pub const Bitmask = packed struct(usize) {
    bits: usize,

    pub fn default() Bitmask {
        return .{
            .bits = 0
        };
    }

    pub inline fn countZeros(self: *Bitmask) usize {
        return @ctz(self.bits);
    }

    pub inline fn set(self: *Bitmask, number: usize) void {
        self.bits |= (@as(usize, 1) << @intCast(number));
    }

    pub inline fn clear(self: *Bitmask, number: usize) void {
        self.bits &= ~(@as(usize, 1) << @intCast(number));
    }
};
