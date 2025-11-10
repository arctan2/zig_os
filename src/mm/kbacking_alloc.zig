const std = @import("std");
const page_alloc = @import("page_alloc.zig");
const kglobal = @import("kglobal.zig");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

const BackingAllocator = struct {
    fn alloc(_: *anyopaque, len: usize, _: Alignment, _: usize) ?[*]u8 {
        const pages_count = std.mem.alignForward(usize, len, page_alloc.PAGE_SIZE) / page_alloc.PAGE_SIZE;
        const block = page_alloc.allocPages(pages_count) catch {
            @panic("TODO: handle out of memory(swap tables)");
        };

        return @ptrFromInt(kglobal.physToVirt(page_alloc.pageToPhys(block)));
    }

    fn resize(_: *anyopaque, _: []u8, _: Alignment, _: usize, _: usize) bool {
        return false;
    }

    fn remap(_: *anyopaque, _: []u8, _: Alignment, _: usize, _: usize) ?[*]u8 {
        return null;
    }

    fn free(_: *anyopaque, memory: []u8, _: Alignment, _: usize) void {
        page_alloc.freeAddr(kglobal.virtToPhys(@intFromPtr(memory.ptr)));
    }
};

const backing_allocator = BackingAllocator{};

pub const allocator = Allocator{
    .ptr = &backing_allocator,
    .vtable = &.{
        .alloc = &backing_allocator.alloc,
        .resize = &backing_allocator.resize,
        .remap = &backing_allocator.remap,
        .free = &backing_allocator.free
    }
};
