const std = @import("std");
const page_alloc = @import("page_alloc.zig");
const kglobal = @import("kglobal.zig");

pub fn testBasicInit(allocator: *std.mem.Allocator) !struct{last_order_chunks_count: usize, memory: []u8, start: usize} {
    const size = (1024 * 1024 * 1024 * 1);
    const memory = try allocator.alloc(u8, size);

    const start = @intFromPtr(@as([*]u8, @ptrCast(memory)));
    const total_pages = @divTrunc(size, page_alloc.PAGE_SIZE);

    _ = page_alloc.initGlobal(start, size, 0);
    return .{ 
        .last_order_chunks_count = total_pages / page_alloc.LAST_ORDER_BLOCK_SIZE,
        .memory = memory,
        .start = start
    };
}

