const std = @import("std");
const uart = @import("uart");
const page_alloc = @import("page_alloc.zig");
pub const KERNEL_VIRT_BASE = 0xC0000000;
pub var KERNEL_VIRT_OFFSET: usize = 0;
pub const MMIO_BASE = 0xF0000000;
pub const VECTOR_TABLE_BASE: usize = 0xFFF00000;

pub extern var _kernel_end: u8;
pub extern var _kernel_start: u8;

pub const KernelBounds = struct {
    kstart: usize,
    kend_no_stack: usize,
    free_region_start: usize,
    free_region_size: usize,
    ksize_with_stack: usize,

    pub fn init(mem_start: usize, mem_size: usize) KernelBounds {
        const kernel_end_addr = std.mem.alignForward(usize, @intFromPtr(&_kernel_end), page_alloc.PAGE_SIZE);
        const kernel_stack = page_alloc.PAGE_SIZE * 4;
        const kernel_size = kernel_end_addr - mem_start + kernel_stack;
        return .{
            .kstart = mem_start,
            .kend_no_stack = kernel_end_addr,
            .free_region_start = kernel_end_addr + kernel_stack,
            .free_region_size = mem_size - kernel_size,
            .ksize_with_stack = kernel_size,
        };
    }

    pub fn print(self: *const KernelBounds) void {
        uart.print(
            \\KernelBounds{{
            \\  kstart = {x},
            \\  kend_no_stack = {x},
            \\  free_region_start = {x},
            \\  free_region_size = {x},
            \\  ksize_with_stack = {x}
            \\}
            \\
        , .{
            self.kstart,
            self.kend_no_stack,
            self.free_region_start,
            self.free_region_size,
            self.ksize_with_stack,
        });
    }
};

pub fn physToVirt(phys: usize) usize {
    return phys + KERNEL_VIRT_OFFSET;
}

pub fn virtToPhys(virt: usize) usize {
    return virt - KERNEL_VIRT_OFFSET;
}
