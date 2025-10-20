const std = @import("std");
const uart = @import("uart");
const assembly = @import("assembly.zig");

pub const page_alloc = @import("page_alloc.zig");
const virt_mem_handler = @import("virt_mem_handler.zig");
const VirtMemHandler = @import("virt_mem_handler.zig").VirtMemHandler;

pub extern var _kernel_end: u8;
pub extern var _kernel_start: u8;

pub fn initMemory(mem_start: usize, mem_size: usize) !void {
    // const kernel_start_addr = std.mem.alignForward(usize, @intFromPtr(&_kernel_start), 8);
    const kernel_end_addr = std.mem.alignForward(usize, @intFromPtr(&_kernel_end), page_alloc.PAGE_SIZE);
    const kernel_stack = page_alloc.PAGE_SIZE * 4;
    const kernel_size = kernel_end_addr - mem_start + kernel_stack;

    _ = page_alloc.initGlobal(kernel_end_addr + kernel_stack, mem_size - kernel_size);

    try initMMU();
}

fn initMMU() !void {
    var kernel_virt_mem = try VirtMemHandler.init();

    var cur_phys_addr: usize = 0x4000_0000;

    for(0..4) |i| {
        try kernel_virt_mem.kernelIdentityMapSection(cur_phys_addr, cur_phys_addr);
        try kernel_virt_mem.kernelIdentityMapSection(virt_mem_handler.KERNEL_VIRT_BASE + (0x10_0000 * i), cur_phys_addr);
        cur_phys_addr += 0x10_0000;
    }

    assembly.invalidateTLBUnified();
    assembly.flushAllCaches();
    assembly.enableMMU(@intFromPtr(kernel_virt_mem.l1));
}
