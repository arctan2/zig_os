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
        const Q = @This();
        head: ?*ListNodeType = null,
        tail: ?*ListNodeType = null,

        pub inline fn isEmpty(self: *Q) bool {
            return self.head == null;
        }

        pub fn push(self: *Q, node: *ListNodeType) void {
            if(self.tail) |t| {
                t.next = node;
                node.prev = t;
                self.tail = node;
            } else {
                self.head = node;
                self.tail = node;
            }
        }

        pub fn pop_front(self: *Q) ?*ListNodeType {
            if(self.head) |h| {
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

        pub fn pop(self: *Q) ?*ListNodeType {
            if(self.tail) |t| {
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

        pub fn remove(self: *Q, node: *ListNodeType) void {
            if(node.prev) |p| {
                p.next = node.next;
                (if(p.next) |next| next.prev else self.tail) = p;
            } else {
                _ = self.pop_front();
            }
        }
    };
}

pub fn Queue(comptime ListNodeType: type) type {
    return struct {
        const Q = @This();

        head: ?*ListNodeType,
        tail: ?*ListNodeType,

        pub fn default() Q {
            return .{
                .head = null,
                .tail = null
            };
        }

        pub inline fn isEmpty(self: *Q) bool {
            return self.head == null;
        }

        pub fn enqueue(self: *Q, node: *ListNodeType) void {
            if(self.tail) |t| {
                t.next = node;
                self.tail = node;
            } else {
                self.head = node;
                self.tail = node;
            }
        }

        pub fn dequeue(self: *Q) ?*ListNodeType {
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

        pub fn insertFront(self: *Q, node: *ListNodeType) void {
            node.next = self.head;
            self.head = node;
            if(self.tail == null) self.tail = node;
        }

        pub fn remove(self: *Q, node: *ListNodeType) void {
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
