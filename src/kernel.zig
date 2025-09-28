const uart = @import("./uart.zig");
const std = @import("std");
const utils = @import("./utils.zig");
const fdt_types = @import("fdt/fdt.zig").types;
const fdt = @import("fdt/fdt.zig");

export fn kernel_main(_: u32, _: u32, fdt_base: [*]u8) void {
    const fdt_header = utils.structBigToNative(fdt_types.FdtHeader, @as(*fdt_types.FdtHeader, @ptrCast(@alignCast(fdt_base))));

    var fdt_mem_rsv_trav = fdt.mem_rsvmap.FdtReserveEntryTraverser.init(fdt_base, &fdt_header);

    while(fdt_mem_rsv_trav.next()) |block| {
        uart.put_hex(u64, block.address);
        uart.putc('\n');
        uart.put_hex(u64, block.size);
        uart.putc('\n');
    }

    while (true) {}
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("\npanic!!!!!!!!!!!!!\n");
    while (true) {}
}
