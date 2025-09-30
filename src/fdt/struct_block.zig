const std = @import("std");
const types = @import("types.zig");
const utils = @import("../utils.zig");
const uart = @import("../uart.zig");
const pointer = @import("../pointer.zig");

const Token = enum(u32) {
    begin_node = 0x1,
    end_node = 0x2,
    prop = 0x3,
    nop = 0x4,
    end = 0x9,
    _
};

pub const NodeProp = struct {
    len: u32,
    nameoff: u32
};

pub const Node = struct {
    node_start: [*]const u8,
    cur_ptr: [*]const u8,

    pub fn init(node_start: [*]const u8) Node {
        return .{
            .node_start = node_start,
            .cur_ptr = node_start
        };
    }

    pub fn nextProp(self: *Node, struct_accessor: *StructAccessor) ?NodeProp {
        self.cur_ptr = @ptrFromInt(std.mem.alignForward(usize, @intFromPtr(self.cur_ptr), 4));
        while(struct_accessor.asToken(self.cur_ptr)) |tok| {
            switch(tok) {
                .nop, .begin_node => {
                    self.cur_ptr += 4;
                    while(struct_accessor.asByte(self.cur_ptr)) |b| : (self.cur_ptr += 1) {
                        if(b == 0) break;
                    }
                    self.cur_ptr = @ptrFromInt(std.mem.alignForward(usize, @intFromPtr(self.cur_ptr), 4));
                },
                .end_node => break,
                .prop => {
                    self.cur_ptr += 4;
                    const ptr: *NodeProp = @constCast(@ptrCast(@alignCast(self.cur_ptr)));
                    return utils.structBigToNative(NodeProp, ptr);
                },
                else => {
                    self.cur_ptr += 1;
                }
            }
        }

        return null;
    }
};

pub const StructAccessor = struct {
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

