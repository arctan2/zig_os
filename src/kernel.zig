const uart = @import("./uart.zig");
const std = @import("std");
const utils = @import("./utils.zig");
const fdt = @import("fdt/fdt.zig");

export fn kernel_main(_: u32, _: u32, fdt_base: [*]const u8) void {
    const fdt_header_base: *fdt.types.FdtHeader = @constCast(@ptrCast(@alignCast(fdt_base)));
    const fdt_header = utils.structBigToNative(fdt.types.FdtHeader, fdt_header_base);
    var struct_accessor = fdt.struct_block.StructAccessor.init(fdt_base, &fdt_header);

    // var string_accessor = fdt.string_block.StringAccessor.init(fdt_base, &fdt_header);

    // while(string_accessor.next()) |s| {
    //     const ptr = s.@"0";
    //     const size = s.@"1";
    //     var i: usize = 0;
    //     while(i < size) : (i += 1) {
    //         uart.putc(ptr[i]);
    //     }
    //     uart.putc('\n');
    // }

    if(struct_accessor.findNameStartsWith("memory")) |memory_block_ptr| {
        var memory_block = fdt.struct_block.Node.init(memory_block_ptr);
        if(memory_block.nextProp(&struct_accessor)) |prop| {
            uart.print("len: {}, nameoff: {x}\n", .{prop.len, prop.nameoff});
        } else {
            uart.print("no memory block props\n", void);
        }
    } else {
        uart.print("memory block not found\n", void);
    }

    while (true) {}
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("*****************panic!!!!!!!!!!!!!*********************\n");
    while (true) {}
}
