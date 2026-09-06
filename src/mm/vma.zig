const std = @import("std");
const uart = @import("uart");
const utils = @import("utils");
const lib = @import("lib");
const kglobal = @import("kglobal.zig");
const page_alloc = @import("page_alloc.zig");
const page_table = @import("./page_table.zig");
const testing_utils = @import("testing_utils.zig");
const fs = @import("fs");

pub const VirtAddress = packed struct(u32) {
    offset: u12,
    l2_idx: u8,
    l1_idx: u12,
};

pub const MapFlags = struct {
    type: enum { Section, L2 },
};

const VirtAllocationNode = lib.list.DListNode(VirtAllocation, "list_node");

pub const VirtAllocation = struct {
    pub const Type = enum {
        stack,
        heap,
        segment,
        other,
        kernel,
    };

    start: usize,
    size: usize,
    file: ?*fs.File,
    file_off: usize,
    list_node: VirtAllocationNode,
    type: Type,

    pub fn cmpFn(_: void, a: usize, b: usize) std.math.Order {
        if(a == b) return .eq;
        return if(a < b) .lt else .gt;
    }

    pub fn end(self: *const VirtAllocation) usize {
        return self.start + self.size;
    }
};

pub const VirtAddrSpace = struct {
    const Self = @This();
    vma_list: lib.list.DoubleLinkedList(VirtAllocationNode) = .{},
    vma_rbtree: lib.RBTree(usize, *VirtAllocation, void, VirtAllocation.cmpFn) = .init({}),
    l1: *page_table.L1PageTable,

    pub fn init(kernel_l1: *page_table.L1PageTable) !VirtAddrSpace {
        return .{
            .l1 = try .init(kernel_l1),
        };
    }

    // for these to work properly the page allocator base address must be aligned to 1MB.
    // It only maps the virt to phys. So phys should be a valid page start address and it is
    // the responsibility of the caller.
    // IT DOES NOT DO ALLOCATIONS FOR THE ACTUAL PAGES. IT IS DONE BY THE CALLER
    // It only does allocations for the page table itself.
    pub fn mapAddr(self: *VirtAddrSpace, virt: usize, phys: usize, flags: MapFlags) !void {
        const virt_addr: VirtAddress = @bitCast(virt);
        const entry_type = self.l1.getEntryType(virt_addr.l1_idx);

        switch (entry_type) {
            .Fault => {
                if (flags.type == .L2) {
                    const l1_entry = self.l1.getEntryAs(page_table.L2TableAddr, virt_addr.l1_idx);
                    const l2_table = try page_table.L2PageTable.init();
                    const l2_entry = l2_table.getEntryAs(page_table.SmallPage, virt_addr.l2_idx);

                    l1_entry.l2_addr = @intCast(@intFromPtr(l2_table) >> 10);
                    l1_entry.type = .L2TablePtr;
                    l2_entry.phys_addr = @intCast(phys >> 12);
                    l2_entry.type = .SmallPage;
                } else {
                    const entry = self.l1.getEntryAs(page_table.SectionEntry, virt_addr.l1_idx);
                    entry.section_addr = @intCast(phys >> 20);
                    entry.type = .Section;
                }
            },
            .L2TablePtr => {
                const l1_entry = self.l1.getEntryAs(page_table.L2TableAddr, virt_addr.l1_idx);
                const l2_table = l1_entry.toTable();
                const l2_entry = l2_table.getEntryAs(page_table.SmallPage, virt_addr.l2_idx);
                if (l2_entry.type != .Fault) {
                    return;
                }

                l2_entry.phys_addr = @intCast(phys >> 12);
                l2_entry.type = .SmallPage;
            },
            else => {},
        }
    }

    pub fn unmapAddr(self: *VirtAddrSpace, virt: usize) void {
        const virt_addr: VirtAddress = @bitCast(virt);
        const entry_type = self.l1.getEntryType(virt_addr.l1_idx);

        switch (entry_type) {
            .Section => {
                self.l1.entries[virt_addr.l1_idx] = 0;
            },
            .L2TablePtr => {
                // TODO: delete the L2 table if empty and free it. And also make the L1 table entry of the
                // corresponding address 0 if L2 table is deleted.
                const l1_entry = self.l1.getEntryAs(page_table.L2TableAddr, virt_addr.l1_idx);
                const l2_table_phys_addr = l1_entry.addr();
                const l2_table = page_table.physToL2Virt(l2_table_phys_addr);
                l2_table.entries[virt_addr.l2_idx] = 0;
            },
            else => {},
        }
    }

    pub fn mmap(
        self: *VirtAddrSpace,
        allocator: std.mem.Allocator,
        start: usize,
        size: usize,
        alloc_type: VirtAllocation.Type,
        file: ?*fs.File
    ) !*VirtAllocation {
        if(size == 0) return error.InvalidSize;
        const end = std.math.add(usize, start, size) catch return error.InvalidRange;
        const prev = self.vma_rbtree.searchLessThan(start);
        const next_ll_node = if(prev) |p| p.value.list_node.next else if(self.vma_list.head) |h| if(h.container().start > start) h else null else null;

        var can_merge_left = false;
        var can_merge_right = false;

        if(prev) |p| {
            if(p.value.end() > start) return error.AlreadyMapped;
            can_merge_left = p.value.end() == start and p.value.type == alloc_type and p.value.file == file;
        }

        if(next_ll_node) |n| {
            const a = n.container();
            if(end > a.start) return error.AlreadyMapped;
            can_merge_right = a.start == end and a.type == alloc_type and a.file == file;
        }

        if(can_merge_left and can_merge_right) {
            const p = prev.?.value;
            const n = next_ll_node.?.container();
            p.size += size + n.size;

            self.vma_list.remove(&n.list_node);
            self.vma_rbtree.removeDestroy(allocator, n.start);
            allocator.destroy(n);
            return p;
        }

        if(can_merge_left) {
            const p = prev.?.value;
            p.size += size;
            return p;
        }

        if(can_merge_right) {
            const n = next_ll_node.?.container();
            n.start = start;
            n.size += size;
            return n;
        }

        const new = try allocator.create(VirtAllocation);
        new.* = .{
            .start = start,
            .size = size,
            .file = file,
            .file_off = 0,
            .list_node = .{
                .prev = null,
                .next = null,
            },
            .type = alloc_type,
        };

        if (prev) |p| {
            self.vma_list.insertAfter(&p.value.list_node, &new.list_node);
        } else if (next_ll_node) |n| {
            self.vma_list.insertBefore(n, &new.list_node);
        } else {
            self.vma_list.push(&new.list_node);
        }

        _ = try self.vma_rbtree.insert(allocator, start, new);

        return new;
    }
};

test "alloc and dealloc ~1GB l1 entries" {
    // if(!utils.isAllTestMode()) return error.SkipZigTest;
    var allocator = std.testing.allocator;
    const g = try testing_utils.testBasicInit(&allocator);
    defer allocator.free(g.memory);

    const arr: [4096]usize = [_]usize{0} ** 4096;
    var l1: page_table.L1PageTable = .{ .entries = arr };
    var mem = try VirtAddrSpace.init(&l1);

    for(0..1020) |i| {
        const cur: usize = i * page_alloc.SECTION_SIZE;
        const block = try page_alloc.allocPages(256);
        try mem.mapAddr(cur, page_alloc.pageToPhys(block), .{ .type = .Section });
    }

    mem.l1.drop();

    for (0..(page_alloc.MAX_ORDER - 1)) |i| try std.testing.expect(page_alloc.global_page_alloc.free_list[i] == null);
    try std.testing.expect(page_alloc.global_page_alloc.getFreeListLen(270000, page_alloc.MAX_ORDER - 1) == g.last_order_chunks_count);
}

test "map and unmap few individual pages" {
    var allocator = std.testing.allocator;
    const g = try testing_utils.testBasicInit(&allocator);
    defer allocator.free(g.memory);

    const arr: [4096]usize = [_]usize{0} ** 4096;
    var l1: page_table.L1PageTable = .{ .entries = arr };
    var mem = try VirtAddrSpace.init(&l1);

    var my_list: std.ArrayList(*page_alloc.Page) = .empty;
    defer my_list.deinit(allocator);

    const virt_base: usize = 0xE0000000;
    var cur_virt = virt_base;

    for(0..100) |_| {
        const page = try page_alloc.allocPages(1);
        try my_list.append(allocator, page);
        try mem.mapAddr(cur_virt, page_alloc.pageToPhys(page), .{ .type = .L2 });
        cur_virt += page_alloc.PAGE_SIZE;
    }

    for(my_list.items) |it| {
        mem.unmapAddr(page_alloc.pageToPhys(it));
        page_alloc.freeBlock(it);
    }

    const virt_addr: VirtAddress = @bitCast(virt_base);
    const l1_entry = mem.l1.getEntryAs(page_table.L2TableAddr, virt_addr.l1_idx);
    const l2_table_phys_addr = l1_entry.addr();
    page_alloc.freeAddr(l2_table_phys_addr);
    page_alloc.freeAddr(@intFromPtr(mem.l1));

    mem.l1.drop();

    for (0..(page_alloc.MAX_ORDER - 1)) |i| try std.testing.expect(page_alloc.global_page_alloc.free_list[i] == null);
    try std.testing.expect(page_alloc.global_page_alloc.getFreeListLen(270000, page_alloc.MAX_ORDER - 1) == g.last_order_chunks_count);
}

fn freeAllVmas(allocator: std.mem.Allocator, mem: *VirtAddrSpace) void {
    var cur = mem.vma_list.head;
    while (cur) |node| {
        cur = node.next;
        allocator.destroy(node.container());
    }
}

test "mmap: basic insert with no neighbors" {
    var allocator = std.testing.allocator;
    const g = try testing_utils.testBasicInit(&allocator);
    defer allocator.free(g.memory);

    const arr: [4096]usize = [_]usize{0} ** 4096;
    var l1: page_table.L1PageTable = .{ .entries = arr };
    var mem = try VirtAddrSpace.init(&l1);

    defer freeAllVmas(allocator, &mem);
    defer mem.l1.drop();

    const vma = try mem.mmap(allocator, 0x1000, 0x1000, .heap, null);

    try std.testing.expect(vma.start == 0x1000);
    try std.testing.expect(vma.size == 0x1000);
    try std.testing.expect(vma.end() == 0x2000);
    try std.testing.expect(mem.vma_list.head.?.container() == vma);
    try std.testing.expect(mem.vma_list.tail.?.container() == vma);

    try mem.vma_rbtree.deinit(allocator);
}

test "mmap: zero size returns error" {
    var allocator = std.testing.allocator;
    const g = try testing_utils.testBasicInit(&allocator);
    defer allocator.free(g.memory);

    const arr: [4096]usize = [_]usize{0} ** 4096;
    var l1: page_table.L1PageTable = .{ .entries = arr };
    var mem = try VirtAddrSpace.init(&l1);
    defer freeAllVmas(allocator, &mem);
    defer mem.l1.drop();

    try std.testing.expectError(error.InvalidSize, mem.mmap(allocator, 0x1000, 0, .heap, null));
    try mem.vma_rbtree.deinit(allocator);
}

test "mmap: start+size overflow returns error" {
    var allocator = std.testing.allocator;
    const g = try testing_utils.testBasicInit(&allocator);
    defer allocator.free(g.memory);

    const arr: [4096]usize = [_]usize{0} ** 4096;
    var l1: page_table.L1PageTable = .{ .entries = arr };
    var mem = try VirtAddrSpace.init(&l1);
    defer freeAllVmas(allocator, &mem);
    defer mem.l1.drop();

    try std.testing.expectError(error.InvalidRange, mem.mmap(allocator, std.math.maxInt(usize) - 0x10, 0x1000, .heap, null));
    try mem.vma_rbtree.deinit(allocator);
}

test "mmap: overlap with existing vma returns error" {
    var allocator = std.testing.allocator;
    const g = try testing_utils.testBasicInit(&allocator);
    defer allocator.free(g.memory);

    const arr: [4096]usize = [_]usize{0} ** 4096;
    var l1: page_table.L1PageTable = .{ .entries = arr };
    var mem = try VirtAddrSpace.init(&l1);
    defer freeAllVmas(allocator, &mem);
    defer mem.l1.drop();

    _ = try mem.mmap(allocator, 0x1000, 0x2000, .heap, null); // [0x1000, 0x3000)

    // overlaps from the left
    try std.testing.expectError(error.AlreadyMapped, mem.mmap(allocator, 0x500, 0x1000, .heap, null));
    // overlaps from the right
    try std.testing.expectError(error.AlreadyMapped, mem.mmap(allocator, 0x2500, 0x1000, .heap, null));
    // fully contained
    try std.testing.expectError(error.AlreadyMapped, mem.mmap(allocator, 0x1500, 0x500, .heap, null));
    // exact same range
    try std.testing.expectError(error.AlreadyMapped, mem.mmap(allocator, 0x1000, 0x2000, .heap, null));

    try mem.vma_rbtree.deinit(allocator);
}

test "mmap: merges with left neighbor of same type and file" {
    var allocator = std.testing.allocator;
    const g = try testing_utils.testBasicInit(&allocator);
    defer allocator.free(g.memory);

    const arr: [4096]usize = [_]usize{0} ** 4096;
    var l1: page_table.L1PageTable = .{ .entries = arr };
    var mem = try VirtAddrSpace.init(&l1);
    defer freeAllVmas(allocator, &mem);
    defer mem.l1.drop();

    const first = try mem.mmap(allocator, 0x1000, 0x1000, .heap, null); // [0x1000, 0x2000)
    const merged = try mem.mmap(allocator, 0x2000, 0x1000, .heap, null); // [0x2000, 0x3000)

    try std.testing.expect(merged == first);
    try std.testing.expect(merged.start == 0x1000);
    try std.testing.expect(merged.size == 0x2000);
    try std.testing.expect(mem.vma_list.head.?.container() == merged);
    try std.testing.expect(mem.vma_list.tail.?.container() == merged);

    try mem.vma_rbtree.deinit(allocator);
}

test "mmap: merges with right neighbor of same type and file" {
    var allocator = std.testing.allocator;
    const g = try testing_utils.testBasicInit(&allocator);
    defer allocator.free(g.memory);

    const arr: [4096]usize = [_]usize{0} ** 4096;
    var l1: page_table.L1PageTable = .{ .entries = arr };
    var mem = try VirtAddrSpace.init(&l1);
    defer freeAllVmas(allocator, &mem);
    defer mem.l1.drop();

    const right = try mem.mmap(allocator, 0x2000, 0x1000, .heap, null); // [0x2000, 0x3000)
    const merged = try mem.mmap(allocator, 0x1000, 0x1000, .heap, null); // [0x1000, 0x2000)

    try std.testing.expect(merged == right);
    try std.testing.expect(merged.start == 0x1000);
    try std.testing.expect(merged.size == 0x2000);
    try std.testing.expect(mem.vma_list.head.?.container() == merged);
    try std.testing.expect(mem.vma_list.tail.?.container() == merged);

    try mem.vma_rbtree.deinit(allocator);
}

test "mmap: merges with both neighbors when bridging a gap" {
    var allocator = std.testing.allocator;
    const g = try testing_utils.testBasicInit(&allocator);
    defer allocator.free(g.memory);

    const arr: [4096]usize = [_]usize{0} ** 4096;
    var l1: page_table.L1PageTable = .{ .entries = arr };
    var mem = try VirtAddrSpace.init(&l1);
    defer freeAllVmas(allocator, &mem);
    defer mem.l1.drop();

    const left = try mem.mmap(allocator, 0x1000, 0x1000, .heap, null);  // [0x1000, 0x2000)
    _ = try mem.mmap(allocator, 0x3000, 0x1000, .heap, null);           // [0x3000, 0x4000)
    const merged = try mem.mmap(allocator, 0x2000, 0x1000, .heap, null); // bridges the gap -> [0x1000, 0x4000)

    try std.testing.expect(merged == left);
    try std.testing.expect(merged.start == 0x1000);
    try std.testing.expect(merged.size == 0x3000);
    try std.testing.expect(merged.end() == 0x4000);
    try std.testing.expect(mem.vma_list.head.?.container() == merged);
    try std.testing.expect(mem.vma_list.tail.?.container() == merged);
    try std.testing.expect(merged.list_node.next == null);

    try std.testing.expect(mem.vma_rbtree.search(0x3000) == null);

    try mem.vma_rbtree.deinit(allocator);
}

test "mmap: does not merge across different alloc types" {
    var allocator = std.testing.allocator;
    const g = try testing_utils.testBasicInit(&allocator);
    defer allocator.free(g.memory);

    const arr: [4096]usize = [_]usize{0} ** 4096;
    var l1: page_table.L1PageTable = .{ .entries = arr };
    var mem = try VirtAddrSpace.init(&l1);
    defer freeAllVmas(allocator, &mem);
    defer mem.l1.drop();

    _ = try mem.mmap(allocator, 0x1000, 0x1000, .heap, null);     // [0x1000, 0x2000)
    const second = try mem.mmap(allocator, 0x2000, 0x1000, .stack, null); // adjacent but different type

    try std.testing.expect(second.start == 0x2000);
    try std.testing.expect(second.size == 0x1000);
    try std.testing.expect(mem.vma_list.head.?.container() != second);
    try std.testing.expect(mem.vma_list.tail.?.container() == second);

    try mem.vma_rbtree.deinit(allocator);
}

test "mmap: does not merge across different files" {
    var allocator = std.testing.allocator;
    const g = try testing_utils.testBasicInit(&allocator);
    defer allocator.free(g.memory);

    const arr: [4096]usize = [_]usize{0} ** 4096;
    var l1: page_table.L1PageTable = .{ .entries = arr };
    var mem = try VirtAddrSpace.init(&l1);
    defer freeAllVmas(allocator, &mem);
    defer mem.l1.drop();

    var file_a: fs.File = undefined;
    var file_b: fs.File = undefined;

    _ = try mem.mmap(allocator, 0x1000, 0x1000, .other, &file_a);     // [0x1000, 0x2000)
    const second = try mem.mmap(allocator, 0x2000, 0x1000, .other, &file_b); // adjacent, different file

    try std.testing.expect(second.start == 0x2000);
    try std.testing.expect(second.size == 0x1000);
    try std.testing.expect(mem.vma_list.head.?.container() != second);
    try std.testing.expect(mem.vma_list.tail.?.container() == second);

    try mem.vma_rbtree.deinit(allocator);
}

test "mmap: inserting between two disjoint non-adjacent vmas" {
    var allocator = std.testing.allocator;
    const g = try testing_utils.testBasicInit(&allocator);
    defer allocator.free(g.memory);

    const arr: [4096]usize = [_]usize{0} ** 4096;
    var l1: page_table.L1PageTable = .{ .entries = arr };
    var mem = try VirtAddrSpace.init(&l1);
    defer freeAllVmas(allocator, &mem);
    defer mem.l1.drop();

    const left = try mem.mmap(allocator, 0x1000, 0x1000, .heap, null);  // [0x1000, 0x2000)
    const right = try mem.mmap(allocator, 0x4000, 0x1000, .heap, null); // [0x4000, 0x5000), gap before it
    const mid = try mem.mmap(allocator, 0x2500, 0x500, .heap, null);    // [0x2500, 0x3000), no adjacency

    try std.testing.expect(mid.start == 0x2500);
    try std.testing.expect(mid.size == 0x500);

    // order in the linked list should be left -> mid -> right
    try std.testing.expect(mem.vma_list.head.?.container() == left);
    try std.testing.expect(left.list_node.next.?.container() == mid);
    try std.testing.expect(mid.list_node.next.?.container() == right);
    try std.testing.expect(mem.vma_list.tail.?.container() == right);

    try mem.vma_rbtree.deinit(allocator);
}

test "mmap: multiple mmaps fully merge into a single vma" {
    var allocator = std.testing.allocator;
    const g = try testing_utils.testBasicInit(&allocator);
    defer allocator.free(g.memory);

    const arr: [4096]usize = [_]usize{0} ** 4096;
    var l1: page_table.L1PageTable = .{ .entries = arr };
    var mem = try VirtAddrSpace.init(&l1);
    defer freeAllVmas(allocator, &mem);
    defer mem.l1.drop();

    var last: *VirtAllocation = undefined;
    for (0..10) |i| {
        last = try mem.mmap(allocator, 0x1000 * (i + 1), 0x1000, .segment, null);
    }

    try std.testing.expect(mem.vma_list.head.?.container() == last);
    try std.testing.expect(mem.vma_list.tail.?.container() == last);
    try std.testing.expect(last.start == 0x1000);
    try std.testing.expect(last.size == 0xa000);
    try std.testing.expect(last.end() == 0xb000);

    try mem.vma_rbtree.deinit(allocator);
}
