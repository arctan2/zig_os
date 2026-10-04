const std = @import("std");
const uart = @import("uart");
const atomic = @import("atomic");
pub const page_table = @import("page_table.zig");
pub const vma = @import("vma.zig");
pub const kglobal = @import("kglobal.zig");
pub const page_alloc = @import("page_alloc.zig");
const gpa = @import("gpa.zig");

pub const kbacking_alloc = @import("kbacking_alloc.zig");
var gpa_allocator = gpa.DebugAllocator(.{ .safety = false, .MutexType = atomic.SpinLock }) {
    .backing_allocator = kbacking_alloc.allocator
};
pub const kalloc = gpa_allocator.allocator();

pub fn mapFreePagesToKernelL1(kbounds: *const kglobal.KernelBounds, kvma: *vma.VirtAddrSpace) !void {
    const high_kernel_start = @intFromPtr(&kglobal._early_kernel_start);
    const mem_end = kbounds.free_region_start + kbounds.free_region_size;
    
    var cur = std.mem.alignForward(usize, high_kernel_start, page_alloc.SECTION_SIZE);
    while(cur < mem_end) {
        try kvma.mapAddr(cur + @intFromPtr(&kglobal.KERNEL_OFFSET), cur, .{ .type = .Section }, .KernelRW);
        cur += page_alloc.SECTION_SIZE;
    }
}

pub fn setKernelTextPermissions(kbounds: *const kglobal.KernelBounds, kvma: *vma.VirtAddrSpace, fdt_base: usize) void {
    const total_pages = @divTrunc(kbounds.free_region_size, page_alloc.PAGE_SIZE);
    const pages_meta_data_size_bytes = total_pages * @sizeOf(page_alloc.Page);
    const pages_meta_end = std.mem.alignForward(
        usize, kglobal.physToVirtByKernelOffset(kbounds.free_region_start) + pages_meta_data_size_bytes + kbounds.kernel_size_phys, page_alloc.SECTION_SIZE
    );
    const start = kglobal.getEarlyKernelStartVirt();
    const end = pages_meta_end >> 20;

    kvma.l1
        .getEntryAs(page_table.SectionEntry, fdt_base >> page_table.SectionEntry.ADDR_SHIFT)
        .setPermissions(.KernelRW);

    for(start..end + 1) |i| {
        const entry = kvma.l1.getEntryAs(page_table.SectionEntry, i);
        entry.setPermissions(.KernelRW);
    }
}

pub fn unmapIdentityKernel(kbounds: *const kglobal.KernelBounds, kvma: *vma.VirtAddrSpace) void {
    const addr = kbounds.kernel_start_phys;
    kvma.unmapAddr(addr);
}

comptime {
    std.testing.refAllDecls(vma);
    std.testing.refAllDecls(kbacking_alloc);
}
