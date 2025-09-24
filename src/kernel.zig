const uart = @import("./uart.zig");
const std = @import("std");

export fn kernel_main(_: u32, _: u32, _: [*]u8) void {
    var i: i32 = -10;
    while (i < 10) : (i += 1) {
        uart.put_number(i32, @intCast(i));
        uart.putc('\n');
    }
    while (true) {}
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("\npanic!!!!!!!!!!!!!\n");
    while (true) {}
}
