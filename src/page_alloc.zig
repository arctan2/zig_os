const std = @import("std");
const uart = @import("uart.zig");

const PageFlag = enum(u8) {
    Reset = 0,
    Allocated = 1 << 0,
};

pub const Page = struct {
    next: ?*Page,
    flags: PageFlag,
    order: u8,
};

pub const MAX_ORDER = 11;
pub const PAGE_SHIFT = 12;
pub const PAGE_SIZE = 1 << PAGE_SHIFT;

pub const AllocError = error{
    InvalidValue,
    MemoryFull,
    TooBig
};

pub const PageAllocator = struct {
    pages: [*]Page,
    free_list: [MAX_ORDER]?*Page,
    total_pages: usize,

    fn page_idx(self: *PageAllocator, page: *Page) usize {
        return page - self.pages;
    }

    fn page_idx_to_phys(self: *PageAllocator, idx: usize) usize {
        return @intFromPtr(self.pages) + (idx << PAGE_SHIFT);
    }

    fn page_to_phys(self: *PageAllocator, page: *Page) usize {
        return self.page_idx_to_phys(self.page_idx(page));
    }

    fn block_size_of_order(_: *PageAllocator, order: u8) usize {
        return @as(usize, 1) << @intCast(order);
    }

    fn block_size_half_of_order(_: *PageAllocator, order: u8) usize {
        return @as(usize, 1) << @intCast(@subWithOverflow(order, 1).@"0");
    }

    fn split_block(self: *PageAllocator, page: *Page, block_size: usize) ?struct{*Page, *Page} {
        const left_page_idx = self.page_idx(page);
        const right_page_idx = left_page_idx + block_size;
        if(right_page_idx >= self.total_pages) return null;
        return .{page, &self.pages[right_page_idx]};
    }

    fn split_and_link_order(self: *PageAllocator, order: u8, block_size: usize) ?struct{*Page, *Page} {
        if(self.free_list[order]) |page| {
            if(self.split_block(page, block_size)) |blocks| {
                const left = blocks.@"0";
                const right = blocks.@"1";
                right.next = left.next;
                left.next = right;
                return .{left, right};
            }
        }
        return null;
    }

    fn remove_link(self: *PageAllocator, page: *Page, order: u8) void {
        if(page.next) |next| {
            self.free_list[order] = next;
        } else {
            self.free_list[order] = null;
        }
        page.next = null;
    }

    fn split_iter_till_order(self: *PageAllocator, order: u8) void {
        var cur_order = order + 1;

        while(cur_order < MAX_ORDER and self.free_list[cur_order] == null) {
            cur_order += 1;
        }

        if(cur_order >= MAX_ORDER) return;

        if(cur_order == MAX_ORDER - 1) {
            const block_size = self.block_size_of_order(cur_order);
            _ = self.split_and_link_order(cur_order, block_size);
        }

        while(order < cur_order and cur_order > 0) : (cur_order -= 1) {
            // initial
            // [------------]->[------------]

            // split and link
            // [----]->[----]->[------------]

            // update head of current order and link right to previous order head and make left as head
            // [----]->[----]
            // [------------]
            const block_size_half = self.block_size_half_of_order(cur_order);
            if(self.split_and_link_order(cur_order, block_size_half)) |splitted| {
                const left = splitted.@"0";
                const right = splitted.@"1";
                const prev_order = cur_order - 1;
                const prev_order_head = self.free_list[prev_order];

                self.free_list[cur_order] = right.next;
                right.order = prev_order;
                left.order = prev_order;
                right.next = prev_order_head;
                self.free_list[prev_order] = left;
            }
        }
    }

    pub fn alloc_pages(self: *PageAllocator, pages_count: usize) AllocError!?*Page {
        const count = std.math.ceilPowerOfTwo(usize, pages_count) catch {
            return AllocError.InvalidValue;
        };

        if(count > 1024) {
            return AllocError.TooBig;
        }

        const order = @ctz(count);

        if(self.free_list[order] == null) {
            self.split_iter_till_order(order);
        }

        if(self.free_list[order]) |block| {
            self.remove_link(block, order);
            block.flags = .Allocated;
            return block;
        }

        return null;
    }

    // pub fn free_page(self: *PageAllocator, page: *Page) void {
    // }
};

pub var global_page_alloc: PageAllocator = undefined;

pub fn init_global(
    start_addr: usize,
    size_bytes: usize
) void {
    // TODO: handle not-a-power of two total_pages

    const pages: [*]Page = @ptrFromInt(start_addr);
    const total_pages = @divTrunc(size_bytes, PAGE_SIZE);
    var free_list: [MAX_ORDER]?*Page = .{null} ** MAX_ORDER;
    var i: usize = 0;

    while(i < total_pages) : (i += 1) {
        pages[i] = .{.next = null, .flags = .Reset, .order = 0};
    }

    pages[0].order = MAX_ORDER - 1;
    free_list[MAX_ORDER - 1] = &pages[0];

    global_page_alloc = .{
        .pages = pages,
        .free_list = free_list,
        .total_pages = total_pages
    };

    const page = global_page_alloc.alloc_pages(8) catch &pages[0];
    uart.print("allocated = {x}\n\n", .{page});

    for(global_page_alloc.free_list) |b| {
        uart.print("{x}\n", .{b});
    }
}

