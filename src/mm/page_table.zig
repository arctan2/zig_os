const uart = @import("uart");
const page_alloc = @import("page_alloc.zig");

pub fn PageTable(comptime size: usize) type {
    return struct {
        const Self = @This();

        entries: [size]usize,

        pub fn init() !*Self {
            const self_page = try page_alloc.allocPages(1);
            const self: *Self = @ptrFromInt(page_alloc.pageToPhys(self_page));
            @memset(&self.entries, 0);
            return self;
        }
    };
}

