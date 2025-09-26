const uart = @import("./uart.zig");
const std = @import("std");
const utils = @import("./utils.zig");
const dtb = @import("./dtb.zig");

export fn kernel_main(_: u32, _: u32, dtb_base: [*]u8) void {
    const dtb_header = utils.structBigToNative(dtb.FdtHeader, @as(*dtb.FdtHeader, @ptrCast(@alignCast(dtb_base))));
    var fdt_mem_rsvmap_traverser = dtb.FdtReserveEntryTraverser.init(dtb_base, dtb_header);
    
    while(fdt_mem_rsvmap_traverser.next()) |entry| {
        uart.put_hex(u64, entry.address);
        uart.putc('\n');
        uart.put_number(u64, entry.size);
        uart.putc('\n');
    }

    while (true) {}
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("\npanic!!!!!!!!!!!!!\n");
    while (true) {}
}
