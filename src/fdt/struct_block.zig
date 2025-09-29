const std = @import("std");
const types = @import("types.zig");
const utils = @import("../utils.zig");
const uart = @import("../uart.zig");
const pointer = @import("../pointer.zig");

const Token = enum(u32) {
    begin_node = 0x00000001,
    end_node = 0x00000002,
    prop = 0x00000003,
    nop = 0x00000004,
    end = 0x00000009
};

pub const StructAccessor = struct {
    base: [*]const u8,
    end: [*]const u8,
    cur_ptr: [*]const u8,

    pub fn init(fdt_base: [*]const u8, fdt_header: *const types.FdtHeader) StructAccessor {
        const base = fdt_base + fdt_header.off_dt_struct;
        return StructAccessor{ .base = base, .end = base + fdt_header.size_dt_struct, .cur_ptr = base};
    }

    pub fn nextToken(self: *StructAccessor) ?Token {
        if(pointer.gte([*]const u8, self.cur_ptr, self.end)) return null;

        const cur_ptr = self.cur_ptr;
        self.cur_ptr += 4;

        var tok: Token = undefined;
        const ptr: *const u32 = @ptrCast(@alignCast(cur_ptr));
        tok = @enumFromInt(utils.bigToNative(u32, ptr.*));
        return tok;
    }

    pub fn nextByte(self: *StructAccessor) ?u8 {
        if(pointer.gte([*]const u8, self.cur_ptr, self.end)) return null;
        const cur_ptr = self.cur_ptr;
        self.cur_ptr += 1;
        return cur_ptr[0];
    }
};
