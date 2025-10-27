const std = @import("std");

pub inline fn lt(comptime T: type, l: T, r: T) bool {
    const op1: usize = @intFromPtr(l);
    const op2: usize = @intFromPtr(r);
    return op1 < op2;
}

pub inline fn gt(comptime T: type, l: T, r: T) bool {
    const op1: usize = @intFromPtr(l);
    const op2: usize = @intFromPtr(r);
    return op1 > op2;
}

pub inline fn gte(comptime T: type, l: T, r: T) bool {
    const op1: usize = @intFromPtr(l);
    const op2: usize = @intFromPtr(r);
    return op1 >= op2;
}

pub inline fn lte(comptime T: type, l: T, r: T) bool {
    const op1: usize = @intFromPtr(l);
    const op2: usize = @intFromPtr(r);
    return op1 <= op2;
}

pub inline fn eq(comptime T: type, l: T, r: T) bool {
    const op1: usize = @intFromPtr(l);
    const op2: usize = @intFromPtr(r);
    return op1 == op2;
}

pub inline fn align4(ptr: [*]const u8) [*]const u8 {
    return @ptrFromInt(std.mem.alignForward(usize, @intFromPtr(ptr), 4));
}
