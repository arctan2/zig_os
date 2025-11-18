const std = @import("std");
const page_alloc = @import("page_alloc.zig");
const vm_handler = @import("vm_handler.zig");
const kglobal = @import("kglobal.zig");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const testing_utils = @import("testing_utils.zig");

const BackingAllocator = struct {
    fn alloc(_: *anyopaque, len: usize, _: Alignment, _: usize) ?[*]u8 {
        const pages_count = std.mem.alignForward(usize, len, page_alloc.PAGE_SIZE) / page_alloc.PAGE_SIZE;
        const block = page_alloc.allocPages(pages_count) catch {
            // @panic("TODO: handle out of memory(swap tables)");
            return null;
        };
        const phys = page_alloc.pageToPhys(block);

        return @ptrFromInt(kglobal.physToVirt(phys));
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

    fn allocator(self: *BackingAllocator) Allocator {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free
            }
        };
    }
};

var backing_allocator = BackingAllocator{};
pub const allocator = backing_allocator.allocator();

test "alloc and dealloc ints" {
    var testing_allocator = std.testing.allocator;
    const g = try testing_utils.testBasicInit(&testing_allocator);
    defer testing_allocator.free(g.memory);
    var mem = try vm_handler.VMHandler.init();

    const start: usize = g.start;

    for(0..100) |i| {
        const v = (i * page_alloc.SECTION_SIZE) + start;
        try mem.map(v, v, .{.type = .Section});
    }

    var gpa_allocator = std.heap.DebugAllocator(.{}) {
        .backing_allocator = allocator
    };

    const gpa = gpa_allocator.allocator();

    var my_list: std.ArrayList(u32) = .empty;

    for(0..1000) |i| {
        try my_list.append(gpa, i);
    }

    my_list.deinit(gpa);
    mem.l1.free();

    for (0..(page_alloc.MAX_ORDER - 1)) |i| try std.testing.expect(page_alloc.global_page_alloc.free_list[i] == null);
    try std.testing.expect(page_alloc.global_page_alloc.getFreeListLen(270000, page_alloc.MAX_ORDER - 1) == g.last_order_chunks_count);
}

test "alloc and dealloc structs" {
    var testing_allocator = std.testing.allocator;
    const g = try testing_utils.testBasicInit(&testing_allocator);
    defer testing_allocator.free(g.memory);
    var mem = try vm_handler.VMHandler.init();

    const start: usize = g.start;

    for(0..100) |i| {
        const v = (i * page_alloc.SECTION_SIZE) + start;
        try mem.map(v, v, .{.type = .Section});
    }

    var gpa_allocator = std.heap.DebugAllocator(.{}) {
        .backing_allocator = allocator
    };

    const gpa = gpa_allocator.allocator();


    const InsaneStruct = struct {
        f1: u32 = 20,
        f2: u64 = 29,
        f3: u8 = 2
    };

    var my_list = try std.ArrayList(*InsaneStruct).initCapacity(gpa, 100);

    for(0..100) |_| {
        const a = try gpa.create(InsaneStruct);
        my_list.appendAssumeCapacity(a);
    }

    for(my_list.items) |it| {
        gpa.destroy(it);
    }

    my_list.deinit(gpa);
    mem.l1.free();

    for (0..(page_alloc.MAX_ORDER - 1)) |i| try std.testing.expect(page_alloc.global_page_alloc.free_list[i] == null);
    try std.testing.expect(page_alloc.global_page_alloc.getFreeListLen(270000, page_alloc.MAX_ORDER - 1) == g.last_order_chunks_count);
}
