const uart = @import("uart");
const std = @import("std");
const utils = @import("utils");
const fdt = @import("fdt");
const virt_kernel = @import("virt_kernel");

export fn kernel_main(_: u32, _: u32, fdt_base: [*]const u8) void {
    uart.setBase(0x09000000);

    virt_kernel.initVirtKernel(fdt_base) catch {
        @panic("error init virt kernel");
    };

    while (true) {}
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("panic: ");
    uart.puts(msg);
    while (true) {}
}
