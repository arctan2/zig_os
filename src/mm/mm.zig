const std = @import("std");
const uart = @import("uart");
const arm = @import("arm");
const fdt = @import("fdt");
const mmio = @import("mmio");
const utils = @import("utils");
pub const page_table = @import("page_table.zig");
pub const virt_mem_handler = @import("virt_mem_handler.zig");
pub const kglobal = @import("kglobal.zig");
pub const page_alloc = @import("page_alloc.zig");

pub fn identityMapKernel(
    kernel_bounds: *const kglobal.KernelBounds,
    kernel_virt_mem: *virt_mem_handler.VirtMemHandler
) !void {
    kglobal.KERNEL_VIRT_OFFSET = kglobal.KERNEL_VIRT_BASE - kernel_bounds.kstart;

    for(0..4) |i| {
        const addr = kernel_bounds.kstart + (page_alloc.SECTION_SIZE * i);
        try kernel_virt_mem.kernelMapSection(addr, addr);
    }
}

fn patchVectorTable(kernel_bounds: *const kglobal.KernelBounds) void {
    const vector_table_addresses: []usize = @as([*]usize, @ptrFromInt(kernel_bounds.kstart + 0x24))[0..7];
    for(0..vector_table_addresses.len) |i| {
        vector_table_addresses[i] = kglobal.physToVirt(vector_table_addresses[i]);
    }
}

pub fn mapToHigherAddress(
    kernel_bounds: *const kglobal.KernelBounds,
    fdt_base: [*]const u8,
    kernel_virt_mem: *virt_mem_handler.VirtMemHandler
) !void {
    const reset_vec = utils.read32(kernel_bounds.kstart);
    const irq_vec = utils.read32(kernel_bounds.kstart + 0x18);

    uart.print("Reset vector: {x}, read_from = {x}\n", .{reset_vec, kernel_bounds.kstart});
    uart.print("IRQ vector: {x}, read_from = {x}\n", .{irq_vec, kernel_bounds.kstart + 0x18});

    const mem_end = kernel_bounds.free_region_start + kernel_bounds.free_region_size;
    var cur_phys_addr: usize = kernel_bounds.kstart;
    var idx: usize = 0;
    while(cur_phys_addr < mem_end) {
        try kernel_virt_mem.kernelMapSection(kglobal.KERNEL_VIRT_BASE + (page_alloc.SECTION_SIZE * idx), cur_phys_addr);
        cur_phys_addr += page_alloc.SECTION_SIZE;
        idx += 1;
    }

    try kernel_virt_mem.kernelMapSection(kglobal.VECTOR_TABLE_BASE, kernel_bounds.kstart);
    patchVectorTable(kernel_bounds);
    try kernel_virt_mem.kernelMapSection(kglobal.physToVirt(@intFromPtr(fdt_base)), @intFromPtr(fdt_base));

    page_alloc.global_page_alloc = @ptrFromInt(kglobal.physToVirt(@intFromPtr(page_alloc.global_page_alloc)));

    uart.print("fdt map : {x} -> {x}\n", .{kglobal.physToVirt(@intFromPtr(fdt_base)), @intFromPtr(fdt_base)});
    uart.print("vector table : {x} -> {x}\n", .{kglobal.VECTOR_TABLE_BASE, kernel_bounds.kstart});

    uart.print("---------------mapping higher addr end---------------------\n\n", void);
}

pub fn transitionToHigherHalf(
    _: *const kglobal.KernelBounds,
    kernel_virt_mem: *virt_mem_handler.VirtMemHandler,
    higher_half_main: *const fn ([*]const u8) void,
    fdt_base: [*]const u8
) noreturn {
    arm.enableMMU(@intFromPtr(kernel_virt_mem.l1));
    kernel_virt_mem.l1 = @as(*page_table.L1PageTable, @ptrFromInt(kglobal.physToVirt(arm.ttbr.read(1))));

    arm.invalidateTLBUnified();
    arm.flushAllCaches();

    asm volatile (
        \\add sp, sp, %[offset]
        \\adr r0, relocate_label
        \\add r0, r0, %[offset]
        \\dsb
        \\isb
        \\mov pc, r0
        \\relocate_label:
        \\isb
        \\nop
        \\nop
        :
        : [offset] "r" (kglobal.KERNEL_VIRT_OFFSET) : .{
            .r0 = true,
            .r1 = true,
            .r12 = true,
            .r13 = true,
            .r14 = true,
            .memory = true,
        }
    );
    // using stack variables in this region is kind of dangerous because sp is kind of messed up so
    // we call the higher half main and let it unmap the identity map

    const f = @as(*const fn ([*]const u8) void, @ptrFromInt(kglobal.physToVirt(@intFromPtr(higher_half_main))));
    f(@ptrFromInt(kglobal.physToVirt(@intFromPtr(fdt_base))));
    while(true) {}
}

