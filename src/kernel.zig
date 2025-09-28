const uart = @import("./uart.zig");
const std = @import("std");
const utils = @import("./utils.zig");
const fdt = @import("fdt/fdt.zig");

export fn kernel_main(_: u32, _: u32, fdt_base: [*]u8) void {
    const fdt_header = utils.structBigToNative(fdt.types.FdtHeader, @as(*fdt.types.FdtHeader, @ptrCast(@alignCast(fdt_base))));
    // var string_accessor = fdt.string_block.StringTraverser.init(fdt_base, &fdt_header);

    uart.print("yo this magic is {} but in hex it's {x}\n", .{fdt_header.magic, fdt_header.magic});

    while (true) {}
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("\npanic!!!!!!!!!!!!!\n");
    while (true) {}
}
