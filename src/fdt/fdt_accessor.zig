const std = @import("std");
const types = @import("types.zig");
const utils = @import("../utils.zig");
const uart = @import("../uart.zig");
const pointer = @import("../pointer.zig");

const StringAccessor = struct {
    base: [*]const u8,
    end: [*]const u8,

    pub fn init(fdt_base: [*]const u8, fdt_header: *const types.FdtHeader) StringAccessor {
        const base = fdt_base + fdt_header.off_dt_strings;
        return StringAccessor{ .base = base, .end = base + fdt_header.size_dt_strings };
    }

    pub fn getAddrFromOffset(self: *StringAccessor, offset: usize) ?[*]const u8 {
        const ptr = self.base + offset;
        if(pointer.gte([*]const u8, ptr, self.end)) return null;
        return ptr;
    }

    pub fn printFromOffset(self: *StringAccessor, offset: usize) void {
        if(self.getAddrFromOffset(offset)) |ptr| {
            var i: usize = 0;
            while(ptr[i] != 0) : (i += 1) {
                uart.putc(ptr[i]);
            }
        } else {
            uart.print("null", void);
        }
    }
};

const Token = enum(u32) {
    begin_node = 0x1,
    end_node = 0x2,
    prop = 0x3,
    nop = 0x4,
    end = 0x9,
    _
};

const StructAccessor = struct {
    base: [*]const u8,
    end: [*]const u8,

    pub fn init(fdt_base: [*]const u8, fdt_header: *const types.FdtHeader) StructAccessor {
        const base = fdt_base + fdt_header.off_dt_struct;
        return StructAccessor{ .base = base, .end = base + fdt_header.size_dt_struct };
    }

    pub fn asToken(self: *StructAccessor, cur_ptr: [*]const u8) ?Token {
        if(pointer.gte([*]const u8, cur_ptr, self.end)) return null;
        var tok: Token = undefined;
        const ptr: *const u32 = @ptrCast(@alignCast(cur_ptr));
        tok = @enumFromInt(utils.bigToNative(u32, ptr.*));
        return tok;
    }

    pub fn asByte(self: *StructAccessor, cur_ptr: [*]const u8) ?u8 {
        if(pointer.gte([*]const u8, cur_ptr, self.end)) return null;
        return cur_ptr[0];
    }

    pub fn findNameStartsWith(self: *StructAccessor, str: []const u8) ?[*]const u8 {
        var cur_ptr: [*]const u8 = @ptrFromInt(std.mem.alignForward(usize, @intFromPtr(self.base), 4));
        
        while(self.asToken(cur_ptr)) |tok| :
            (cur_ptr = @ptrFromInt(std.mem.alignForward(usize, @intFromPtr(cur_ptr + 4), 4))) {
            switch(tok) {
                .begin_node => {
                    const start = cur_ptr;
                    cur_ptr += 4;
                    for(str) |c| {
                        if(self.asByte(cur_ptr)) |b| {
                            if(b == 0 or b != c) break;
                            cur_ptr += 1;
                        } else {
                            break;
                        }
                    }

                    // str.len + 4 because I'm using start as FDT_BEGIN_NODE address which is u32
                    if((cur_ptr - start) == (str.len + 4)) {
                        return start;
                    }
                },
                else => {}
            }
        }

        return null;
    }
};

pub const Accessor = struct {
    strings: StringAccessor,
    structs: StructAccessor,

    pub fn init(fdt_base: [*]const u8, fdt_header: *const types.FdtHeader) Accessor {
        return .{
            .strings = .init(fdt_base, fdt_header),
            .structs = .init(fdt_base, fdt_header)
        };
    }
};
