const uart = @import("./uart.zig");
const std = @import("std");
const utils = @import("./utils.zig");
const fdt = @import("fdt/fdt.zig");
const page_alloc = @import("page_alloc.zig");

extern var _kernel_end: u8;

fn init_mem(mem_start: usize, mem_size: usize) void {
    const kernel_end_addr = @intFromPtr(&_kernel_end);
    const kernel_stack = page_alloc.PAGE_SIZE * 4;
    const kernel_size = kernel_end_addr - mem_start + kernel_stack;
    uart.print("kernel_end = {x}\n", .{kernel_end_addr});
    page_alloc.initGlobal(std.mem.alignForward(usize, kernel_end_addr + kernel_stack, 8), mem_size - kernel_size);
    uart.print("after init: total_pages = {}\n", .{page_alloc.global_page_alloc.total_pages});
}

export fn kernel_main(_: u32, _: u32, fdt_base: [*]const u8) void {

    const fdt_header_base: *fdt.types.FdtHeader = @constCast(@ptrCast(@alignCast(fdt_base)));
    const fdt_header = utils.structBigToNative(fdt.types.FdtHeader, fdt_header_base);

    var accessor = fdt.accessor.Accessor.init(fdt_base, &fdt_header);

    var root_node = fdt.node.FdtNode.init(accessor.structs.base);
    var address_cells: u32 = 0;
    var size_cells: u32 = 0;

    if(root_node.getPropByName(&accessor, "#address-cells")) |prop| {
        address_cells = std.mem.readInt(u32, @ptrCast(prop.data), .big);
    } else {
        @panic("#address-cells not found\n");
    }

    if(root_node.getPropByName(&accessor, "#size-cells")) |prop| {
        size_cells = std.mem.readInt(u32, @ptrCast(prop.data), .big);
    } else {
        @panic("#size-cells not found\n");
    }

    uart.print("addr_cells: {x}, size_cells: {x}\n", .{address_cells, size_cells});

    if(accessor.structs.findNameStartsWith("memory")) |memory_block_ptr| {
        var memory_block = fdt.node.FdtNode.init(memory_block_ptr);
        if(memory_block.getPropByName(&accessor, "reg")) |prop| {
            const mem_start = fdt.readRegFromCells(address_cells, prop.data);
            const mem_size = fdt.readRegFromCells(size_cells, @ptrCast(prop.data + (@sizeOf(u32) * address_cells)));
            init_mem(mem_start, mem_size);
        } else {
            @panic("reg not found");
        }
    } else {
        @panic("memory not found");
    }

    while (true) {}
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("panic: ");
    uart.puts(msg);
    while (true) {}
}
