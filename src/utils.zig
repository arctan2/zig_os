const std = @import("std");

pub fn structBigToNative(comptime T: type, s: *T) *T {
    inline for (std.meta.fields(T)) |field| {
        @field(s, field.name) = std.mem.bigToNative(field.type, @field(s, field.name));
    }
    return s;
}

