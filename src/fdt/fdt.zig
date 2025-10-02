pub const std = @import("std");
pub const types = @import("types.zig");
pub const mem_rsvmap = @import("mem_rsvmap.zig");
pub const accessor = @import("./fdt_accessor.zig");
pub const node = @import("node.zig");

pub inline fn readRegFromCells(cells: u32, ptr: [*]const u8) usize {
    return @intCast(switch(cells) {
        0x1 => std.mem.readInt(u32, @ptrCast(ptr), .big),
        0x2 => std.mem.readInt(u64, @ptrCast(ptr), .big),
        0x3 => std.mem.readInt(u128, @ptrCast(ptr), .big),
        else => 0
    });
}

