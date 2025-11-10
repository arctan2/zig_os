const std = @import("std");
const uart = @import("uart");
const utils = @import("utils");
const kglobal = @import("kglobal.zig");
pub const page_alloc = @import("page_alloc.zig");
pub const page_table = @import("./page_table.zig");

pub const VirtAddress = packed struct(u32) {
    offset: u12,
    l2_idx: u8,
    l1_idx: u12,
};

pub const MapFlags = struct {
    type: enum { Section, L2 },
};

pub const VirtMemHandler = struct {
    l1: *page_table.L1PageTable,

    pub fn init() !VirtMemHandler {
        return .{
            .l1 = try .init(),
        };
    }

    pub fn kernelMapSection(self: *VirtMemHandler, virt: usize, phys: usize) !void {
        const virt_addr: VirtAddress = @bitCast(virt);
        const entry: *page_table.SectionEntry = @ptrCast(&self.l1.entries[virt_addr.l1_idx]);
        entry.section_addr = @intCast(phys >> 20);
        entry.type = .Section;
    }

    pub fn kernelUnmapSection(self: *VirtMemHandler, virt: usize) void {
        const virt_addr: VirtAddress = @bitCast(virt);
        self.l1.entries[virt_addr.l1_idx] = 0;
    }

    // for these to work properly the page allocator base address must be aligned to 1MB.
    // It only maps the virt to phys. So phys should be a valid page start address and it is
    // the responsibility of the caller.
    // It only does allocations for the page table itself.
    pub fn map(self: *VirtMemHandler, virt: usize, phys: usize, flags: MapFlags) !void {
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
                    const section_page = try page_alloc.allocPages(256);
                    const section_phys_addr = page_alloc.pageToPhys(section_page);
                    entry.section_addr = @intCast(section_phys_addr >> 20);
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

    pub fn unmap(self: *VirtMemHandler, virt: usize) void {
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
};

fn testBasicInit(allocator: *std.mem.Allocator) !struct{last_order_chunks_count: usize, memory: []u8} {
    const size = (1024 * 1024 * 1024 * 1);
    const memory = try allocator.alloc(u8, size);

    const start = @intFromPtr(@as([*]u8, @ptrCast(memory)));
    const total_pages = @divTrunc(size, page_alloc.PAGE_SIZE);

    _ = page_alloc.initGlobal(start, size, 0);
    return .{ .last_order_chunks_count = total_pages / page_alloc.LAST_ORDER_BLOCK_SIZE, .memory = memory };
}

test "alloc and dealloc ~1GB l1 entries" {
    // if(!utils.isAllTestMode()) return error.SkipZigTest;
    var allocator = std.testing.allocator;
    const g = try testBasicInit(&allocator);
    defer allocator.free(g.memory);

    var mem = try VirtMemHandler.init();

    for(0..1020) |i| {
        const cur: usize = i * page_alloc.SECTION_SIZE;
        try mem.map(cur, cur, .{ .type = .Section });
    }

    mem.l1.drop();
    mem.l1.drop();

    for (0..(page_alloc.MAX_ORDER - 1)) |i| try std.testing.expect(page_alloc.global_page_alloc.free_list[i] == null);
    try std.testing.expect(page_alloc.global_page_alloc.getFreeListLen(270000, page_alloc.MAX_ORDER - 1) == g.last_order_chunks_count);
}

test "map and unmap few individual pages" {
    var allocator = std.testing.allocator;
    const g = try testBasicInit(&allocator);
    defer allocator.free(g.memory);

    var mem = try VirtMemHandler.init();

    var my_list: std.ArrayList(*page_alloc.Page) = .empty;
    defer my_list.deinit(allocator);

    const virt_base: usize = 0xE0000000;
    var cur_virt = virt_base;

    for(0..100) |_| {
        const page = try page_alloc.allocPages(1);
        try my_list.append(allocator, page);
        try mem.map(cur_virt, page_alloc.pageToPhys(page), .{ .type = .L2 });
        cur_virt += page_alloc.PAGE_SIZE;
    }

    for(my_list.items) |it| {
        mem.unmap(page_alloc.pageToPhys(it));
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
