const std = @import("std");
pub const ptr = @import("ptr.zig");
pub const types = @import("types.zig");

pub fn bigToNative(comptime T: type, s: T) T {
    return std.mem.bigToNative(T, s);
}

pub fn structBigToNative(comptime T: type, s: *const T) T {
    var newStruct = std.mem.zeroes(T);
    inline for (std.meta.fields(T)) |field| {
        @field(newStruct, field.name) = bigToNative(field.type, @field(s, field.name));
    }
    return newStruct;
}

pub fn isAllTestMode() bool {
    return std.process.hasEnvVar(std.testing.allocator, "all") catch false;
}

pub fn newPrng() std.Random.Xoshiro256 {
    return std.Random.Xoshiro256.init(@intCast(std.time.nanoTimestamp()));
}

pub fn read32(reg: u32) u32 {
    return @as(*volatile u32, @ptrFromInt(reg)).*;
}

pub fn write32(reg: u32, val: u32) void {
    @as(*volatile u32, @ptrFromInt(reg)).* = val;
}

pub fn read8(reg: u32) u8 {
    return @as(*volatile u8, @ptrFromInt(reg)).*;
}

pub fn write8(reg: u32, val: u8) void {
    @as(*volatile u8, @ptrFromInt(reg)).* = val;
}

