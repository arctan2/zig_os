const uart = @import("uart");
const std = @import("std");
const utils = @import("utils");
const fdt = @import("fdt/fdt.zig");
const mm = @import("mm");
const page_alloc = mm.page_alloc;

export fn kernel_main(_: u32, _: u32, fdt_base: [*]const u8) void {
    uart.setUartBase(0x09000000);
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
            prop.printName();
            uart.print(": ", void);
            prop.printValue();
            uart.print("\n", void);
            const mem_start = fdt.readRegFromCells(address_cells, prop.data);
            const mem_size = fdt.readRegFromCells(size_cells, @ptrCast(prop.data + (@sizeOf(u32) * address_cells)));
            mm.initMemory(mem_start, mem_size) catch {
                @panic("error init mm");
            };
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
