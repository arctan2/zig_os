const std = @import("std");
const builtin = @import("builtin");
const utils = @import("utils");
const uart = @import("uart");
const expect = std.testing.expect;

const PageFlag = enum(u8) {
    Reset = 0,
    Allocated = 1 << 0,
    BlockStart = 1 << 1,
    _
};

pub const Page = struct {
    prev: ?*Page,
    next: ?*Page,
    flags: PageFlag,
    order: u8,

    fn setFlag(self: *Page, flag: PageFlag) void {
        self.flags = @enumFromInt(@intFromEnum(self.flags) | @intFromEnum(flag));
    }

    fn unsetFlag(self: *Page, flag: PageFlag) void {
        self.flags = @enumFromInt(@intFromEnum(self.flags) & ~@intFromEnum(flag));
    }

    fn isFlagSet(self: *Page, flag: PageFlag) bool {
        return @as(PageFlag, @enumFromInt(@intFromEnum(self.flags) & @intFromEnum(flag))) == flag;
    }
};

pub const MAX_ORDER = 11;
pub const LAST_ORDER_BLOCK_SIZE = 1 << (MAX_ORDER - 1);
pub const PAGE_SHIFT = 12;
pub const PAGE_SIZE = 1 << PAGE_SHIFT;
pub const SECTION_SIZE = 0x100000;

pub const AllocError = error{
    InvalidValue,
    MemoryFull,
    TooBig
};

pub const PageAllocator = struct {
    base_addr: usize,
    pages: [*]Page,
    free_list: [MAX_ORDER]?*Page,
    total_pages: usize,
    mapped_pages: usize,

    fn pageIdx(self: *PageAllocator, page: *Page) usize {
        return page - self.pages;
    }

    fn physToPage(self: *PageAllocator, phys: usize) ?*Page {
        const idx = (phys - self.base_addr) / PAGE_SIZE;
        if(idx >= self.total_pages) return null;
        return &self.pages[idx];
    }

    fn pageIdxToPhys(self: *PageAllocator, idx: usize) usize {
        return self.base_addr + (idx << PAGE_SHIFT);
    }

    fn pageToPhys(self: *PageAllocator, page: *Page) usize {
        return self.pageIdxToPhys(self.pageIdx(page));
    }

    fn blockSizeOfOrder(_: *PageAllocator, order: u8) usize {
        return @as(usize, 1) << @intCast(order);
    }

    fn blockSizeHalfOfOrder(_: *PageAllocator, order: u8) usize {
        return @as(usize, 1) << @intCast(@subWithOverflow(order, 1).@"0");
    }

    fn getBuddy(self: *PageAllocator, page: *Page) *Page {
        return &self.pages[self.pageIdx(page) ^ (@as(usize, 1) << @intCast(page.order))];
    }

    fn getFreeListLen(self: *PageAllocator, comptime size: usize, order: u8) usize {
        var cur = self.free_list[order];
        var count: usize = 0;

        var visited: [size]*Page = .{@as(*Page, @ptrFromInt(8))}**size;

        a: while(cur) |b| {
            var j: usize = 0;

            while(j < count) : (j += 1) {
                if(visited[j] == b) {
                    if(builtin.is_test) {
                        std.debug.print("man infiinte loop\n", .{});
                        std.debug.print("count = {}\n", .{count});
                    } else {
                        uart.print("man infiinte loop\n", .{});
                        uart.print("count = {}\n", .{count});
                    }
                    break :a;
                }
            }

            visited[count] = b;

            count += 1;
            cur = b.next;
        }

        return count;
    }

    fn splitBlock(self: *PageAllocator, page: *Page, block_size: usize) ?struct{*Page, *Page} {
        const left_pageIdx = self.pageIdx(page);
        const right_pageIdx = left_pageIdx + block_size;
        if(right_pageIdx >= self.total_pages) return null;
        return .{page, &self.pages[right_pageIdx]};
    }

    fn splitLinkSetHeadFlag(self: *PageAllocator, order: u8, block_size: usize) ?struct{*Page, *Page} {
        if(self.free_list[order]) |page| {
            if(self.splitBlock(page, block_size)) |blocks| {
                const left = blocks.@"0";
                const right = blocks.@"1";
                right.next = left.next;
                right.prev = left;
                left.next = right;

                right.flags = .BlockStart;
                left.flags = .BlockStart;
                return .{left, right};
            }
        }
        return null;
    }

    fn pushFreeList(self: *PageAllocator, order: u8, block: *Page) void {
        const head = self.free_list[order];
        if(head) |h| h.prev = block;
        block.next = head;
        self.free_list[order] = block;
    }

    fn removeFromFreeList(self: *PageAllocator, page: *Page, order: u8) void {
        const prev = page.prev;
        const next = page.next;

        page.next = null;
        page.prev = null;

        if(prev) |p| {
            p.next = next;
            if(next) |n| n.prev = p;
        } else {
            self.free_list[order] = next;
            if(next) |n| n.prev = null;
        }
    }

    fn splitIterTillOrder(self: *PageAllocator, order: u8) void {
        var cur_order = order + 1;

        while(cur_order < MAX_ORDER and self.free_list[cur_order] == null) {
            cur_order += 1;
        }

        if(cur_order >= MAX_ORDER) return;

        while(order < cur_order and cur_order > 0) : (cur_order -= 1) {
            // initial
            // [------------]<->[------------]

            // split and link
            // [----]<->[----]<->[-------------]

            // update head of current order and link right to previous order head and make left as head
            // [----]<->[----]
            // [-------------]
            const block_size_half = self.blockSizeHalfOfOrder(cur_order);
            if(self.splitLinkSetHeadFlag(cur_order, block_size_half)) |splitted| {
                const left = splitted.@"0";
                const right = splitted.@"1";
                const prev_order = cur_order - 1;

                // update the current order head and set it's prev to null
                self.free_list[cur_order] = right.next;
                if(self.free_list[cur_order]) |cur_order_head| {
                    cur_order_head.prev = null;
                }

                right.order = prev_order;
                left.order = prev_order;

                self.pushFreeList(prev_order, right);
                self.free_list[prev_order] = left;
            }
        }
    }

    pub fn allocPages(self: *PageAllocator, pages_count: usize) AllocError!*Page {
        const count = std.math.ceilPowerOfTwo(usize, pages_count) catch {
            return AllocError.InvalidValue;
        };

        if(count > 1024) {
            return AllocError.TooBig;
        }

        const order = @ctz(count);

        if(self.free_list[order] == null) {
            self.splitIterTillOrder(order);
        }

        if(self.free_list[order]) |block| {
            self.removeFromFreeList(block, order);
            block.setFlag(.Allocated);
            return block;
        }

        return AllocError.MemoryFull;
    }

    fn isBlockInFreeList(self: *PageAllocator, block: *Page) bool {
        return self.free_list[block.order] == block or block.next != null or block.prev != null;
    }

    // assumes the inital order is NOT MAX_ORDER - 1 and buddy_1.order == buddy_2.order
    fn mergeIterBuddies(self: *PageAllocator, buddy_1: *Page, buddy_2: *Page) *Page {
        var head_block: *Page = if(@intFromPtr(buddy_1) < @intFromPtr(buddy_2)) buddy_1 else buddy_2;
        var buddy = self.getBuddy(head_block);

        while(true) {
            if(self.isBlockInFreeList(head_block)) self.removeFromFreeList(head_block, head_block.order);
            if(self.isBlockInFreeList(buddy)) self.removeFromFreeList(buddy, buddy.order);

            head_block.order = head_block.order + 1;
            buddy.order = head_block.order;
            buddy.flags = .Reset;
            head_block.flags = .BlockStart;

            buddy = self.getBuddy(head_block);

            if(buddy.order == MAX_ORDER - 1 or buddy.isFlagSet(.Allocated) or buddy.order != head_block.order) {
                break;
            }

            head_block = if(@intFromPtr(buddy) < @intFromPtr(head_block)) buddy else head_block;
            buddy = self.getBuddy(head_block);
        }

        return head_block;
    }

    pub fn freeBlock(self: *PageAllocator, block: *Page) void {
        if(!block.isFlagSet(.BlockStart) or !block.isFlagSet(.Allocated)) return;
        const buddy = self.getBuddy(block);
        const buddy_idx = self.pageIdx(buddy);

        if(buddy_idx > self.mapped_pages) {
            @panic("page range out of bounds\n");
        }

        if(buddy_idx == self.mapped_pages) {
            self.pushFreeList(block.order, block);
            return;
        }

        if(!buddy.isFlagSet(.BlockStart)) {
            @panic("buddy flag is not BlockStart. Something has went wrong.");
        }

        block.unsetFlag(.Allocated);

        // just add to free list if freeing last order block directly.
        if(block.order == MAX_ORDER - 1 or buddy.isFlagSet(.Allocated) or buddy.order != block.order) {
            self.pushFreeList(block.order, block);
        } else {
            const merged_block = self.mergeIterBuddies(block, buddy);
            self.pushFreeList(merged_block.order, merged_block);
        }
    }
};

pub var global_page_alloc: PageAllocator = undefined;

pub fn initGlobal(
    start_addr: usize,
    size_bytes: usize
) usize {
    // TODO: handle not-a-power of two total_pages

    const total_pages = @divTrunc(size_bytes, PAGE_SIZE);
    const last_order_chunks_count = total_pages / LAST_ORDER_BLOCK_SIZE;
    const mapped_pages_count = last_order_chunks_count * LAST_ORDER_BLOCK_SIZE;
    const pages_meta_data_size_bytes = total_pages * @sizeOf(Page);
    const free_pages_start = std.mem.alignForward(usize, start_addr + pages_meta_data_size_bytes, SECTION_SIZE);
    const pages_meta_data: [*]Page = @ptrFromInt(start_addr);

    var free_list: [MAX_ORDER]?*Page = .{null} ** MAX_ORDER;
    var i: usize = 0;

    while(i < total_pages) : (i += 1) {
        pages_meta_data[i] = .{.prev = null, .next = null, .flags = .Reset, .order = 0};
    }

if(!builtin.is_test) {
    uart.print(
        \\--------------META DATA-----------------
        \\
        \\kernel_end_aligned = {x},
        \\end_addr = {x},
        \\size_bytes = {},
        \\total_pages = {},
        \\last_order_chunks_count = {},
        \\mapped_pages = {} - {},
        \\unmapped_pages_count = {},
        \\pages_meta_data_size_bytes = {},
        \\free_pages_start = {x},
        \\
        \\--------------META DATA END-----------------
        \\
        , .{
            start_addr,
            start_addr + size_bytes,
            size_bytes,
            total_pages,
            last_order_chunks_count,
            @as(u32, 0), mapped_pages_count - 1,
            total_pages - mapped_pages_count,
            pages_meta_data_size_bytes,
            free_pages_start,
        }
    );
}

    var prev_block = &pages_meta_data[0];
    prev_block.setFlag(.BlockStart);
    prev_block.order = MAX_ORDER - 1;

    for(1..last_order_chunks_count) |idx| {
        const next_block = &pages_meta_data[idx * LAST_ORDER_BLOCK_SIZE];
        prev_block.next = next_block;
        next_block.prev = prev_block;
        next_block.setFlag(.BlockStart);
        next_block.order = MAX_ORDER - 1;
        prev_block = next_block;
    }

    free_list[MAX_ORDER - 1] = &pages_meta_data[0];

    global_page_alloc = .{
        .base_addr = free_pages_start,
        .pages = pages_meta_data,
        .free_list = free_list,
        .total_pages = total_pages,
        .mapped_pages = mapped_pages_count
    };

    return free_pages_start;
}

pub fn allocPages(pages_count: usize) AllocError!*Page {
    return global_page_alloc.allocPages(pages_count);
}

pub fn freeBlock(block: *Page) void {
    global_page_alloc.freeBlock(block);
}

pub fn pageToPhys(block: *Page) usize {
    return global_page_alloc.pageToPhys(block);
}

pub fn physToPage(phys: usize) ?*Page {
    return global_page_alloc.physToPage(phys);
}

test "allocate and deallocate 1 block in every order" {
    const allocator = std.heap.page_allocator;
    const size = (1024 * 1024 * 1024 * 1);

    const memory = try allocator.alloc(u8, size);
    defer allocator.free(memory);

    const start = @intFromPtr(@as([*]u8, @ptrCast(memory)));

    _ = initGlobal(start, size);

    for(0..MAX_ORDER) |i| {
        const page = try global_page_alloc.allocPages(@as(usize, 1) << @intCast(i));
        global_page_alloc.freeBlock(page);
    }

    for(0..(MAX_ORDER - 1)) |i| try std.testing.expect(global_page_alloc.free_list[i] == null);

    try std.testing.expect(@intFromPtr(global_page_alloc.free_list[MAX_ORDER - 1]) == start);
}

test "allocate and deallocate at each order" {
    if(!utils.isAllTestMode()) return error.SkipZigTest;

    const size = (1024 * 1024 * 1024 * 1);
    const allocator = std.testing.allocator;
    const memory = try allocator.alloc(u8, size);
    defer allocator.free(memory);

    var my_list: std.ArrayList(*Page) = .empty;
    defer my_list.deinit(allocator);

    const start = @intFromPtr(@as([*]u8, @ptrCast(memory)));
    const total_pages = @divTrunc(size, PAGE_SIZE);
    const last_order_chunks_count = total_pages / LAST_ORDER_BLOCK_SIZE;

    _ = initGlobal(start, size);

    for(0..MAX_ORDER) |order| {
        const chunk_size = (@as(usize, 1) << @intCast(order));
        const order_chunks_count = total_pages / chunk_size;
        for(0..order_chunks_count) |_| {
            const block = try global_page_alloc.allocPages(chunk_size);
            try my_list.append(allocator, block);
        }

        for(0..MAX_ORDER) |i| try std.testing.expect(global_page_alloc.free_list[i] == null);

        for(my_list.items) |block| {
            global_page_alloc.freeBlock(block);
        }

        for(0..(MAX_ORDER - 1)) |i| try std.testing.expect(global_page_alloc.free_list[i] == null);

        try std.testing.expect(global_page_alloc.getFreeListLen(270000, MAX_ORDER - 1) == last_order_chunks_count);

        my_list.clearRetainingCapacity();
    }

    for(0..(MAX_ORDER - 1)) |i| try std.testing.expect(global_page_alloc.free_list[i] == null);

    try std.testing.expect(global_page_alloc.getFreeListLen(270000, MAX_ORDER - 1) == last_order_chunks_count);
}

test "basic test case free" {
    const size = (1024 * 1024 * 1024 * 1);
    const allocator = std.testing.allocator;
    const memory = try allocator.alloc(u8, size);
    defer allocator.free(memory);

    var my_list: std.ArrayList(*Page) = .empty;
    defer my_list.deinit(allocator);

    const start = @intFromPtr(@as([*]u8, @ptrCast(memory)));
    const total_pages = @divTrunc(size, PAGE_SIZE);
    const last_order_chunks_count = total_pages / LAST_ORDER_BLOCK_SIZE;

    _ = initGlobal(start, size);

    const a = try global_page_alloc.allocPages(512);
    const b = try global_page_alloc.allocPages(512);

    try expect(global_page_alloc.getBuddy(a) == b);
    try expect(global_page_alloc.getBuddy(b) == a);

    try expect(a.isFlagSet(.Allocated));
    try expect(b.isFlagSet(.Allocated));

    try expect(a.order == 9);
    try expect(b.order == 9);

    try expect(a.isFlagSet(.BlockStart));
    try expect(b.isFlagSet(.BlockStart));

    global_page_alloc.freeBlock(b);
    global_page_alloc.freeBlock(a);

    for(0..(MAX_ORDER - 1)) |i| try std.testing.expect(global_page_alloc.free_list[i] == null);
    try std.testing.expect(global_page_alloc.getFreeListLen(270000, MAX_ORDER - 1) == last_order_chunks_count);
}

test "merge test case" {
    if(!utils.isAllTestMode()) return error.SkipZigTest;
    const size = (1024 * 1024 * 1024 * 1);
    const allocator = std.testing.allocator;
    const memory = try allocator.alloc(u8, size);
    defer allocator.free(memory);

    var my_list: std.ArrayList(*Page) = .empty;
    defer my_list.deinit(allocator);

    const start = @intFromPtr(@as([*]u8, @ptrCast(memory)));
    const total_pages = @divTrunc(size, PAGE_SIZE);
    const last_order_chunks_count = total_pages / LAST_ORDER_BLOCK_SIZE;

    _ = initGlobal(start, size);

    const a = try global_page_alloc.allocPages(512);
    const b = try global_page_alloc.allocPages(256);
    const c = try global_page_alloc.allocPages(512);
    const d = try global_page_alloc.allocPages(128);
    const e = try global_page_alloc.allocPages(128);
    const f = try global_page_alloc.allocPages(128);

    global_page_alloc.freeBlock(a);
    global_page_alloc.freeBlock(b);
    global_page_alloc.freeBlock(c);
    global_page_alloc.freeBlock(d);
    global_page_alloc.freeBlock(e);
    global_page_alloc.freeBlock(f);

    for(0..(MAX_ORDER - 1)) |i| try std.testing.expect(global_page_alloc.free_list[i] == null);

    var cur = global_page_alloc.free_list[MAX_ORDER - 1];

    while(cur) |bl| {
        try expect(bl.order == MAX_ORDER - 1);
        cur = bl.next;
    }
    try std.testing.expect(global_page_alloc.getFreeListLen(270000, MAX_ORDER - 1) == last_order_chunks_count);
}

test "random allocate and deallocate" {
    if(!utils.isAllTestMode()) return error.SkipZigTest;
    const size = (1024 * 1024 * 1024 * 1);
    const allocator = std.testing.allocator;
    const memory = try allocator.alloc(u8, size);
    defer allocator.free(memory);

    var my_list: std.ArrayList(*Page) = .empty;
    defer my_list.deinit(allocator);

    const start = @intFromPtr(@as([*]u8, @ptrCast(memory)));
    const total_pages = @divTrunc(size, PAGE_SIZE);
    const last_order_chunks_count = total_pages / LAST_ORDER_BLOCK_SIZE;

    _ = initGlobal(start, size);

    var prng: std.Random.Xoshiro256 = utils.newPrng();
    var rand = prng.random();

    for(0..100) |_| {
        const r = rand.intRangeAtMost(usize, 1, 1024);
        const expected_r = try std.math.ceilPowerOfTwo(usize, r);
        const order = @ctz(expected_r);
        const block = try global_page_alloc.allocPages(r);

        try std.testing.expect(order == block.order);
        try my_list.append(allocator, block);
    }

    for(my_list.items) |block| {
        global_page_alloc.freeBlock(block);
    }

    for(0..(MAX_ORDER - 1)) |i| try std.testing.expect(global_page_alloc.free_list[i] == null);
    try std.testing.expect(global_page_alloc.getFreeListLen(270000, MAX_ORDER - 1) == last_order_chunks_count);
}

test "loop allocate and deallocate" {
    if(!utils.isAllTestMode()) return error.SkipZigTest;
    const size = (1024 * 1024 * 1024 * 1);
    const allocator = std.testing.allocator;
    const memory = try allocator.alloc(u8, size);
    defer allocator.free(memory);

    var my_list: std.ArrayList(*Page) = .empty;
    defer my_list.deinit(allocator);

    const start = @intFromPtr(@as([*]u8, @ptrCast(memory)));
    const total_pages = @divTrunc(size, PAGE_SIZE);
    const last_order_chunks_count = total_pages / LAST_ORDER_BLOCK_SIZE;

    _ = initGlobal(start, size);

    for(0..5) |_| {
        for(0..11) |i| {
            const chunk_size = (@as(usize, 1) << @intCast(i));
            const block = try global_page_alloc.allocPages(chunk_size);
            try my_list.append(allocator, block);
        }
    }

    for(my_list.items) |block| {
        global_page_alloc.freeBlock(block);
    }

    for(0..(MAX_ORDER - 1)) |i| try std.testing.expect(global_page_alloc.free_list[i] == null);
    try std.testing.expect(global_page_alloc.getFreeListLen(270000, MAX_ORDER - 1) == last_order_chunks_count);
}
