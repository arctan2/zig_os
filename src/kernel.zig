const uart = @import("uart");
const std = @import("std");
const utils = @import("utils");
const fdt = @import("fdt");
const virt_kernel = @import("virt_kernel");

export fn kernel_main(_: u32, _: u32, fdt_base: [*]const u8) void {
    uart.setUartBase(0x09000000);

    var fdt_accessor = fdt.Accessor.init(fdt_base);

    const root_node = fdt_accessor.structs.base;
    const addr_size_cells = fdt_accessor.getAddrSizeCells(root_node) orelse {
        @panic("size addr cells of root node is not present");
    };

    const memory_block = fdt_accessor.findNode(root_node, "memory") orelse {
        @panic("memory not found");
    };
    const reg = fdt_accessor.getPropByName(memory_block, "reg") orelse {
        @panic("reg not found");
    };

    const mem_start = fdt.readRegFromCells(addr_size_cells, reg.data, 0);
    const mem_size = fdt.readRegFromCells(addr_size_cells, reg.data, 1);
    virt_kernel.initVirtKernel(mem_start, mem_size, fdt_base) catch {
        @panic("error init virt kernel");
    };

    while (true) {}
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("panic: ");
    uart.puts(msg);
    while (true) {}
}
