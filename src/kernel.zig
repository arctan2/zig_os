const uart = @import("./uart.zig");
const std = @import("std");

const FdtHeader = packed struct {
    magic: u32,
    totalsize: u32,
    off_dt_struct: u32,
    off_dt_strings: u32,
    off_mem_rsvmap: u32,
    version: u32,
    last_comp_version: u32,
    boot_cpuid_phys: u32,
    size_dt_strings: u32,
    size_dt_struct: u32,
};

fn fixEndian(comptime T: type, _struct: *T) void {
    inline for (std.meta.fields(@TypeOf(_struct.*))) |f| {
        @field(_struct, f.name) = std.mem.readInt(
            @TypeOf(@field(_struct, f.name)), @ptrCast(&@field(_struct, f.name)), .big
        );
    }
}

export fn kernel_main(_: u32, _: u32, dtb: *FdtHeader) void {
    fixEndian(FdtHeader, dtb);
    uart.put_hex(u32, dtb.magic);
    while (true) {}
}

pub fn panic(_: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("\npanic!!!!!!!!!!!!!\n");
    while (true) {}
}
