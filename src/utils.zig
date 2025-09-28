const std = @import("std");

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

