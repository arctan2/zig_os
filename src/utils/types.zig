pub fn ListNode(comptime ContainerT: type, field_name: []const u8) type {
    return struct {
        const Self = @This();
        next: ?*Self,
        prev: ?*Self,

        pub fn container(self: *Self) *ContainerT {
            return @fieldParentPtr(field_name, self);
        }
    };
}

pub fn Queue(comptime ListNodeType: type) type {
    return struct {
        const Q = @This();

        head: ?*ListNodeType,
        tail: ?*ListNodeType,

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

pub const BitMask = packed struct(usize) {
    bits: usize,

    pub fn set(self: *BitMask, number: usize) void {
        self.bits |= (1 << number);
    }

    pub fn clear(self: *BitMask, number: usize) void {
        self.bits &= ~(1 << number);
    }
};
