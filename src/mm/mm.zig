const std = @import("std");
const uart = @import("uart");
pub const page_table = @import("page_table.zig");
pub const virt_mem_handler = @import("virt_mem_handler.zig");
pub const kglobal = @import("kglobal.zig");
pub const page_alloc = @import("page_alloc.zig");

pub fn mapFreePagesToKernelL1(kbounds: *const kglobal.KernelBounds, kvmem: *virt_mem_handler.VirtMemHandler) !void {
    const high_kernel_start = @intFromPtr(&kglobal._early_kernel_end);
    const mem_end = kbounds.free_region_start + kbounds.free_region_size;
    
    var cur = std.mem.alignForward(usize, high_kernel_start, page_alloc.SECTION_SIZE);
    while(cur < mem_end) {
        try kvmem.kernelMapSection(cur + @intFromPtr(&kglobal.KERNEL_OFFSET), cur);
        cur += page_alloc.SECTION_SIZE;
    }
}

pub fn unmapIdentityKernel(kbounds: *const kglobal.KernelBounds, kvmem: *virt_mem_handler.VirtMemHandler) void {
    for(0..2) |i| {
        const addr = kbounds.kernel_start_phys + (page_alloc.SECTION_SIZE * i);
        kvmem.kernelUnmapSection(addr);
    }
}
