const uart = @import("./uart.zig");
const std = @import("std");
const utils = @import("./utils.zig");
const fdt = @import("fdt/fdt.zig");

export fn kernel_main(_: u32, _: u32, fdt_base: [*]const u8) void {
    const fdt_header_base: *fdt.types.FdtHeader = @constCast(@ptrCast(@alignCast(fdt_base)));
    const fdt_header = utils.structBigToNative(fdt.types.FdtHeader, fdt_header_base);

    var accessor = fdt.accessor.Accessor.init(fdt_base, &fdt_header);

    var root_node = fdt.node.FdtNode.init(accessor.structs.base);
    var address_cells: u32 = 0;
    var size_cells: u32 = 0;

    root_node.print(&accessor);

    if(root_node.getPropByName(&accessor, "#address-cells")) |prop| {
        address_cells = std.mem.readInt(u32, @ptrCast(prop.data), .big);
    } else {
        uart.print("#address-cells found\n", void);
    }

    if(root_node.getPropByName(&accessor, "#size-cells")) |prop| {
        size_cells = std.mem.readInt(u32, @ptrCast(prop.data), .big);
    } else {
        uart.print("#size-cells found\n", void);
    }

    uart.print("a: {x}, s: {x}\n", .{address_cells, size_cells});

    if(accessor.structs.findNameStartsWith("memory")) |memory_block_ptr| {
        var memory_block = fdt.node.FdtNode.init(memory_block_ptr);
        memory_block.print(&accessor);
        if(memory_block.getPropByName(&accessor, "reg")) |prop| {
            prop.printName();
            uart.print(": ", void);
            const mem_start = fdt.readRegFromCells(address_cells, prop.data);
            const mem_size = fdt.readRegFromCells(size_cells, @ptrCast(prop.data + (@sizeOf(u32) * address_cells)));
            uart.print("{x}, {x}", .{mem_start, mem_size});
        } else {
            uart.print("reg not found\n", void);
        }
    } else {
        uart.print("memory not found\n", void);
    }

    while (true) {}
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("*****************panic!!!!!!!!!!!!!*********************\n");
    while (true) {}
}
