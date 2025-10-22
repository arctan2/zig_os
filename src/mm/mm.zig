const std = @import("std");
const uart = @import("uart");
const assembly = @import("assembly.zig");
const page_table = @import("page_table.zig");
const kernel_global = @import("kernel_global.zig");
const virt_mem_handler = @import("virt_mem_handler.zig");

pub const page_alloc = @import("page_alloc.zig");

pub fn initMemory(mem_start: usize, mem_size: usize) !void {
    const kernel_end_addr = std.mem.alignForward(usize, @intFromPtr(&kernel_global._kernel_end), page_alloc.PAGE_SIZE);
    const kernel_stack = page_alloc.PAGE_SIZE * 4;
    const kernel_size = kernel_end_addr - mem_start + kernel_stack;

    kernel_global.KERNEL_VIRT_OFFSET = kernel_global.KERNEL_VIRT_BASE - mem_start;

    _ = page_alloc.initGlobal(kernel_end_addr + kernel_stack, mem_size - kernel_size);

    try initMMU(mem_start + mem_size);
}

fn initMMU(mem_end: usize) !void {
    const kernel_start_addr = std.mem.alignForward(usize, @intFromPtr(&kernel_global._kernel_start), 8);
    var kernel_virt_mem = try virt_mem_handler.VirtMemHandler.init();

    for(0..4) |i| {
        const addr = kernel_start_addr + (0x10_0000 * i);
        try kernel_virt_mem.kernelMapSection(addr, addr);
    }

    var cur_phys_addr: usize = kernel_start_addr;
    var idx: usize = 0;
    while(cur_phys_addr < mem_end) {
        try kernel_virt_mem.kernelMapSection(kernel_global.KERNEL_VIRT_BASE + (0x10_0000 * idx), cur_phys_addr);
        cur_phys_addr += 0x10_0000;
        idx += 1;
    }

    const newUartBase = kernel_global.MMIO_BASE + uart.getUartBase();
    try kernel_virt_mem.kernelMapSection(newUartBase, uart.getUartBase());
    uart.setUartBase(newUartBase);

    assembly.invalidateTLBUnified();
    assembly.flushAllCaches();
    assembly.enableMMU(@intFromPtr(kernel_virt_mem.l1));

    kernel_virt_mem.l1 = @as(*page_table.L1PageTable, @ptrFromInt(kernel_global.physToVirt(@intFromPtr(kernel_virt_mem.l1))));

    const a: usize = asm volatile ("mov %[a], pc" : [a] "=r" (->usize));
    uart.print("before = {x}, KERNEL_VIRT_OFFSET = {x}\n", .{a, kernel_global.KERNEL_VIRT_OFFSET});

    asm volatile (
        \\add sp, sp, %[offset]
        \\mov r0, pc
        \\add r0, r0, %[offset]
        \\add r0, r0, #8
        \\mov pc, r0
        :
        : [offset] "r" (kernel_global.KERNEL_VIRT_OFFSET)
    );

    assembly.invalidateTLBUnified();

    for(0..4) |i| {
        const addr = kernel_start_addr + (0x10_0000 * i);
        uart.print("unmapping {x}\n", .{addr});
        kernel_virt_mem.kernelUnmapSection(addr);
    }

    uart.print("man unmapped and we good.\n", void);
}

