const uart = @import("./uart.zig");
const std = @import("std");
const utils = @import("./utils.zig");
const fdt = @import("fdt/fdt.zig");

export fn kernel_main(_: u32, _: u32, fdt_base: [*]const u8) void {
    const fdt_header_base: *fdt.types.FdtHeader = @constCast(@ptrCast(@alignCast(fdt_base)));
    const fdt_header = utils.structBigToNative(fdt.types.FdtHeader, fdt_header_base);

    var accessor = fdt.accessor.Accessor.init(fdt_base, &fdt_header);

    var root_node = fdt.node.FdtNode.init(accessor.structs.base);
    root_node.print(&accessor);

    if(accessor.structs.findNameStartsWith("memory")) |memory_block_ptr| {
        var memory_block = fdt.node.FdtNode.init(memory_block_ptr);
        memory_block.print(&accessor);
    }

    while (true) {}
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("*****************panic!!!!!!!!!!!!!*********************\n");
    while (true) {}
}
