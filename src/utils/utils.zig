const std = @import("std");
pub const ptr = @import("./ptr.zig");

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
