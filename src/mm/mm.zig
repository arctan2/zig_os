const std = @import("std");
const uart = @import("uart");
const arm = @import("arm");
const fdt = @import("fdt");
const mmio = @import("mmio");
pub const page_table = @import("page_table.zig");
pub const virt_mem_handler = @import("virt_mem_handler.zig");
pub const kernel_global = @import("kernel_global.zig");
pub const page_alloc = @import("page_alloc.zig");

pub fn identityMapKernel(
    kernel_bounds: *const kernel_global.KernelBounds,
    fdt_base: [*]const u8,
    kernel_virt_mem: *virt_mem_handler.VirtMemHandler
) !void {
    kernel_global.KERNEL_VIRT_OFFSET = kernel_global.KERNEL_VIRT_BASE - kernel_bounds.start;

    const kernel_start_addr = std.mem.alignForward(usize, @intFromPtr(&kernel_global._kernel_start), 8);

    for(0..4) |i| {
        const addr = kernel_start_addr + (page_alloc.SECTION_SIZE * i);
        try kernel_virt_mem.kernelMapSection(addr, addr);
    }

    var cur_phys_addr: usize = kernel_start_addr;
    var idx: usize = 0;
    while(cur_phys_addr < kernel_bounds.end) {
        try kernel_virt_mem.kernelMapSection(kernel_global.KERNEL_VIRT_BASE + (page_alloc.SECTION_SIZE * idx), cur_phys_addr);
        cur_phys_addr += page_alloc.SECTION_SIZE;
        idx += 1;
    }

    try kernel_virt_mem.kernelMapSection(kernel_global.VECTOR_TABLE_BASE, kernel_global._kernel_start);
    try kernel_virt_mem.kernelMapSection(kernel_global.physToVirt(@intFromPtr(fdt_base)), @intFromPtr(fdt_base));
}

pub fn transitionToHigherHalf(
    kernel_bounds: *const kernel_global.KernelBounds,
    kernel_virt_mem: *virt_mem_handler.VirtMemHandler,
    higher_half_main: *const fn ([*]const u8) void,
    fdt_base: [*]const u8
) noreturn {
    arm.invalidateTLBUnified();
    arm.flushAllCaches();
    arm.enableMMU(@intFromPtr(kernel_virt_mem.l1));

    kernel_virt_mem.l1 = @as(*page_table.L1PageTable, @ptrFromInt(kernel_global.physToVirt(@intFromPtr(kernel_virt_mem.l1))));

    asm volatile (
        \\add sp, sp, %[offset]
        \\adr r0, relocate_label
        \\add r0, r0, %[offset]
        \\mov pc, r0
        \\relocate_label:
        :
        : [offset] "r" (kernel_global.KERNEL_VIRT_OFFSET), [val] "r" (0)
    );

    for(0..4) |i| {
        arm.invalidateTLBUnified();
        const addr = kernel_bounds.start + (page_alloc.SECTION_SIZE * i);
        kernel_virt_mem.kernelUnmapSection(addr);
    }

    const f = @as(*const fn ([*]const u8) void, @ptrFromInt(kernel_global.physToVirt(@intFromPtr(higher_half_main))));

    f(fdt_base);

    while(true) {}
}

