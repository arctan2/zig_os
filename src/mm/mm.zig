const std = @import("std");

pub const page_alloc = @import("page_alloc.zig");
const VirtMemHandler = @import("virt_mem_handler.zig").VirtMemHandler;

pub extern var _kernel_end: u8;

pub fn initMemory(mem_start: usize, mem_size: usize) !void {
    const kernel_end_addr = std.mem.alignForward(usize, @intFromPtr(&_kernel_end), page_alloc.PAGE_SIZE);
    const kernel_stack = page_alloc.PAGE_SIZE * 4;
    const kernel_size = kernel_end_addr - mem_start + kernel_stack;

    page_alloc.initGlobal(kernel_end_addr + kernel_stack, mem_size - kernel_size);

    var kernel_virt_mem = try VirtMemHandler.init();

    try kernel_virt_mem.map(0x0000_0000, 0x0, @enumFromInt(1));
    try kernel_virt_mem.map(0x2000_0000, 0x2000_0000, @enumFromInt(0));
}

