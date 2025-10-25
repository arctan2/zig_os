const uart = @import("uart");
const std = @import("std");
const utils = @import("utils");
const fdt = @import("fdt/fdt.zig");
const virt_kernel = @import("virt_kernel");

export fn kernel_main(_: u32, _: u32, fdt_base: [*]const u8) void {
    uart.setUartBase(0x09000000);
    const fdt_header_base: *fdt.types.FdtHeader = @constCast(@ptrCast(@alignCast(fdt_base)));
    const fdt_header = utils.structBigToNative(fdt.types.FdtHeader, fdt_header_base);

    var accessor = fdt.accessor.Accessor.init(fdt_base, &fdt_header);

    const root_node = accessor.structs.base;
    var address_cells: u32 = 0;
    var size_cells: u32 = 0;

    if(accessor.getPropByName(root_node, "#address-cells")) |prop| {
        address_cells = std.mem.readInt(u32, @ptrCast(prop.data), .big);
    } else {
        @panic("#address-cells not found\n");
    }

    if(accessor.getPropByName(root_node, "#size-cells")) |prop| {
        size_cells = std.mem.readInt(u32, @ptrCast(prop.data), .big);
    } else {
        @panic("#size-cells not found\n");
    }

    if(accessor.getPropByName(root_node, "#size-cells")) |prop| {
        size_cells = std.mem.readInt(u32, @ptrCast(prop.data), .big);
    } else {
        @panic("#size-cells not found\n");
    }

    uart.print("addr_cells: {x}, size_cells: {x}\n", .{address_cells, size_cells});

    if(accessor.findNodeWithProp(root_node, "msi-controller")) |node| {
        if(accessor.findParent(node)) |_| {
        } else {
            uart.print("parent not found\n", void);
        }
        // if(memory_block.getPropByName(&accessor, "reg")) |prop| {
        //     const mem_start = fdt.readRegFromCells(address_cells, prop.data);
        //     const mem_size = fdt.readRegFromCells(size_cells, @ptrCast(prop.data + (@sizeOf(u32) * address_cells)));
        //     virt_kernel.initVirtKernel(mem_start, mem_size) catch {
        //         @panic("error init virt kernel");
        //     };
        // } else {
        //     @panic("reg not found");
        // }
    } else {
        @panic("interrupt controller not found");
    }

    // if(accessor.findNode(root_node, "memory")) |memory_block| {
    //     if(accessor.getPropByName(memory_block, "reg")) |prop| {
    //         const mem_start = fdt.readRegFromCells(address_cells, prop.data);
    //         const mem_size = fdt.readRegFromCells(size_cells, @ptrCast(prop.data + (@sizeOf(u32) * address_cells)));
    //         virt_kernel.initVirtKernel(mem_start, mem_size) catch {
    //             @panic("error init virt kernel");
    //         };
    //     } else {
    //         @panic("reg not found");
    //     }
    // } else {
    //     @panic("memory not found");
    // }

    while (true) {}
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("panic: ");
    uart.puts(msg);
    while (true) {}
}
