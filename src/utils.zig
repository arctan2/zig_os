const std = @import("std");

pub fn structBigToNative(comptime T: type, s: *const T) T {
    var newStruct = std.mem.zeroes(T);
    inline for (std.meta.fields(T)) |field| {
        @field(newStruct, field.name) = std.mem.bigToNative(field.type, @field(s, field.name));
    }
    return newStruct;
}

