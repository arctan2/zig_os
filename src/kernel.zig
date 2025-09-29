const uart = @import("./uart.zig");
const std = @import("std");
const utils = @import("./utils.zig");
const fdt = @import("fdt/fdt.zig");

export fn kernel_main(_: u32, _: u32, fdt_base: [*]const u8) void {
    const fdt_header_base: *fdt.types.FdtHeader = @constCast(@ptrCast(@alignCast(fdt_base)));
    const fdt_header = utils.structBigToNative(fdt.types.FdtHeader, fdt_header_base);
    var struct_accessor = fdt.struct_block.StructAccessor.init(fdt_base, &fdt_header);

    uart.print("cur_ptr: {} ", .{struct_accessor.cur_ptr});
    const tok = struct_accessor.nextToken();
    uart.print("{x}\n", .{tok});

    for(0..50) |_| {
        uart.print("cur_ptr: {} ", .{struct_accessor.cur_ptr});
        if(struct_accessor.nextByte()) |b| {
        uart.print("byte: '{x}'\n", .{b});
        }
    }

    while (true) {}
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("\npanic!!!!!!!!!!!!!\n");
    while (true) {}
}
