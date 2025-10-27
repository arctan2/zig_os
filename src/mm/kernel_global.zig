const std = @import("std");
const page_alloc = @import("page_alloc.zig");
pub const KERNEL_VIRT_BASE = 0xC0000000;
pub var KERNEL_VIRT_OFFSET: usize = 0;
pub const MMIO_BASE = 0xF0000000;
pub const VECTOR_TABLE_BASE = 0xFFFF0000;

pub extern var _kernel_end: u8;
pub extern var _kernel_start: u8;

pub const KernelBounds = struct {
    start: usize,
    end: usize,
    free_region_start: usize,
    free_region_size: usize,
    size: usize,

    pub fn init(mem_start: usize, mem_size: usize) KernelBounds {
        const kernel_end_addr = std.mem.alignForward(usize, @intFromPtr(&_kernel_end), page_alloc.PAGE_SIZE);
        const kernel_stack = page_alloc.PAGE_SIZE * 4;
        const kernel_size = kernel_end_addr - mem_start + kernel_stack;
        return .{
            .start = mem_start,
            .end = kernel_end_addr,
            .free_region_start = kernel_end_addr + kernel_stack,
            .free_region_size = mem_size - kernel_size,
            .size = kernel_size,
        };
    }
};

pub fn physToVirt(phys: usize) usize {
    return phys + KERNEL_VIRT_OFFSET;
}

pub fn virtToPhys(virt: usize) usize {
    return virt - KERNEL_VIRT_OFFSET;
}
