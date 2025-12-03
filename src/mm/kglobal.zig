const std = @import("std");
const builtin = @import("builtin");
const uart = @import("uart");
const page_alloc = @import("page_alloc.zig");

pub var VIRT_OFFSET: usize = 0;
pub const MMIO_BASE = 0xF0000000;
pub const VECTOR_TABLE_BASE: usize = 0xFFF00000;

pub extern const KERNEL_OFFSET: u8;
pub extern const PHYS_BASE: u8;
pub extern const VIRT_BASE: u8;
pub extern const _early_kernel_start: u8;
pub extern const _early_kernel_end: u8;
pub extern const _vkernel_start: u8;
pub extern const _vkernel_end: u8;
pub extern const _vstack_top: u8;
pub extern const _irq_stack_top: u8;
pub extern const _sys_stack_top: u8;
pub extern const _pabort_stack_top: u8;
pub extern const _kernel_l1_page_table_phys: u8;

pub const KernelBounds = struct {
    kernel_start_phys: usize,
    kernel_size_phys: usize,
    free_region_start: usize,
    free_region_size: usize,

    pub fn init(mem_start: usize, mem_size: usize) KernelBounds {
        const vkernel_size = @intFromPtr(&_vkernel_end) - @intFromPtr(&_vkernel_start);
        const early_kernel_size = @intFromPtr(&_early_kernel_end) - @intFromPtr(&_early_kernel_start);
        const kernel_size_phys = early_kernel_size + vkernel_size;
        const mem_end = mem_start + mem_size;
        const free_region_start = mem_start + kernel_size_phys;

        return .{
            .kernel_start_phys = @intFromPtr(&PHYS_BASE),
            .kernel_size_phys = kernel_size_phys,
            .free_region_start = free_region_start,
            .free_region_size = mem_end - free_region_start,
        };
    }

    pub fn print(self: *const KernelBounds) void {
        uart.print(
            \\KernelBounds{{
            \\  kernel_start_phys = {x},
            \\  kernel_size_phys = {x},
            \\  free_region_start = {x},
            \\  free_region_size = {x},
            \\}
            \\
        , .{
            self.kernel_start_phys,
            self.kernel_size_phys,
            self.free_region_start,
            self.free_region_size,
        });
    }
};


comptime {
    const FAKE_OFF: usize = 0;
    if (builtin.is_test) {
        @export(&FAKE_OFF, .{
            .name = "KERNEL_OFFSET",
            .linkage = .strong,
        });
    }
}

pub inline fn physToVirtByKernelOffset(phys: usize) usize {
    if (builtin.is_test) {
        return phys;
    }
    return phys + @intFromPtr(&KERNEL_OFFSET);
}

pub inline fn virtToPhysByKernelOffset(virt: usize) usize {
    if (builtin.is_test) {
        return virt;
    }
    return virt - @intFromPtr(&KERNEL_OFFSET);
}

pub inline fn physToVirtByVirtOffset(phys: usize) usize {
    if (builtin.is_test) {
        return phys;
    }
    return phys + VIRT_OFFSET;
}

pub inline fn virtToPhysByVirtOffset(virt: usize) usize {
    if (builtin.is_test) {
        return virt;
    }
    return virt - VIRT_OFFSET;
}
