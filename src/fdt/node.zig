const std = @import("std");
const types = @import("types.zig");
const utils = @import("../utils.zig");
const uart = @import("../uart.zig");
const pointer = @import("../pointer.zig");
const fdt_accessor = @import("./fdt_accessor.zig");

pub const FdtNodeProp = struct {
    len: u32,
    nameoff: u32,
    data: [*]const u8,
    
    pub fn fromPtr(ptr: [*]const u8) FdtNodeProp {
        const len: u32 = std.mem.readInt(u32, @ptrCast(ptr), .big);
        const nameoff: u32 = std.mem.readInt(u32, @ptrCast(ptr + 4), .big);
        return .{
            .len = len,
            .nameoff = nameoff,
            .data = ptr + 8
        };
    }

    pub fn printValue(self: *const FdtNodeProp) void {
        var i: usize = 0;

        uart.print("'", void);
        while(i < self.len) : (i += 1) {
            uart.print("{c}", .{self.data[i]});
        } 
        uart.print("' ", void);

        i = 0;
        uart.print("(", void);
        while(i < self.len) : (i += 1) {
            uart.print("{} ", .{self.data[i]});
        }
        uart.print(")\n", void);
    }

    pub fn printName(self: *const FdtNodeProp, accessor: *fdt_accessor.Accessor) void {
        uart.print("'", void);
        accessor.strings.printFromOffset(self.nameoff);
        uart.print("'", void);
    }
};

pub const FdtNode = struct {
    node_start: [*]const u8,
    cur_ptr: [*]const u8,

    pub fn init(node_start: [*]const u8) FdtNode {
        return .{
            .node_start = node_start,
            .cur_ptr = node_start
        };
    }

    pub fn nextProp(self: *FdtNode, accessor: *fdt_accessor.Accessor) ?FdtNodeProp {
        self.cur_ptr = @ptrFromInt(std.mem.alignForward(usize, @intFromPtr(self.cur_ptr), 4));
        while(accessor.structs.asToken(self.cur_ptr)) |tok| {
            switch(tok) {
                .nop, .begin_node => {
                    self.cur_ptr += 4;
                    while(accessor.structs.asByte(self.cur_ptr)) |b| : (self.cur_ptr += 1) {
                        if(b == 0) break;
                    }
                    self.cur_ptr = @ptrFromInt(std.mem.alignForward(usize, @intFromPtr(self.cur_ptr), 4));
                },
                .end_node => break,
                .prop => {
                    self.cur_ptr += 4;
                    const prop = FdtNodeProp.fromPtr(self.cur_ptr);
                    self.cur_ptr += (@sizeOf(u32) * 2) + prop.len;
                    return prop;
                },
                else => {
                    self.cur_ptr += 1;
                    self.cur_ptr = @ptrFromInt(std.mem.alignForward(usize, @intFromPtr(self.cur_ptr), 4));
                }
            }
        }

        return null;
    }

    pub fn reset(self: *FdtNode) void {
        self.cur_ptr = self.node_start;
    }

    pub fn print(self: *FdtNode, accessor: *fdt_accessor.Accessor) void {
        self.reset();

        var ptr = self.node_start + 4;
        while(accessor.structs.asByte(ptr)) |b| : (ptr += 1) {
            if(b == 0) break;
            uart.putc(b);
        }

        uart.puts("{\n");

        while(self.nextProp(accessor)) |prop| {
            uart.putc('\t');
            prop.printName(accessor);
            uart.print(": ", void);
            prop.printValue();
        }
        uart.puts("}\n");
    }
};


