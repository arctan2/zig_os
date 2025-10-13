const std = @import("std");
const types = @import("types.zig");
const utils = @import("utils");
const uart = @import("uart");
const pointer = @import("../pointer.zig");
const fdt_accessor = @import("./fdt_accessor.zig");

pub const FdtNodeProp = struct {
    name_addr: [*]const u8,
    len: u32,
    data: [*]const u8,
    
    pub fn fromPtr(ptr: [*]const u8, accessor: *fdt_accessor.Accessor) FdtNodeProp {
        const len: u32 = std.mem.readInt(u32, @ptrCast(ptr), .big);
        const nameoff: u32 = std.mem.readInt(u32, @ptrCast(ptr + 4), .big);
        if(accessor.strings.getAddrFromOffset(nameoff)) |addr| {
            return .{
                .len = len,
                .name_addr = addr,
                .data = ptr + 8
            };
        } else {
            @panic("invalid strings block access.");
        }
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
            uart.print("{x} ", .{self.data[i]});
        }
        uart.print(")", void);
    }

    pub fn printName(self: *const FdtNodeProp) void {
        uart.print("'", void);
        var i: usize = 0;
        while(self.name_addr[i] != 0) : (i += 1) {
            uart.putc(self.name_addr[i]);
        }
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

    pub fn getPropByName(self: *FdtNode, accessor: *fdt_accessor.Accessor, name: []const u8) ?FdtNodeProp {
        var cur_ptr: [*]const u8 = self.cur_ptr;

        while(accessor.structs.asToken(cur_ptr)) |tok| : (cur_ptr = pointer.align4(cur_ptr)) {
            switch(tok) {
                .nop, .begin_node => {
                    cur_ptr += 4;
                    while(accessor.structs.asByte(cur_ptr)) |b| : (cur_ptr += 1) {
                        if(b == 0) break;
                    }
                },
                .end_node => break,
                .prop => {
                    cur_ptr += 4;
                    const prop = FdtNodeProp.fromPtr(cur_ptr, accessor);
                    cur_ptr += (@sizeOf(u32) * 2) + prop.len;
                    
                    var i: usize = 0;
                    while(i < name.len) : (i += 1) {
                        if(prop.name_addr[i] != name[i]) break;
                    } else {
                        return prop;
                    }
                },
                else => {
                    cur_ptr += 1;
                }
            }
        }

        return null;
    }

    pub fn print(self: *FdtNode, accessor: *fdt_accessor.Accessor) void {
        var cur_ptr = self.node_start + 4;
        while(accessor.structs.asByte(cur_ptr)) |b| : (cur_ptr += 1) {
            if(b == 0) break;
            uart.putc(b);
        }

        uart.puts("{\n");

        cur_ptr = pointer.align4(cur_ptr);
        while(accessor.structs.asToken(cur_ptr)) |tok| : (cur_ptr = pointer.align4(cur_ptr)) {
            switch(tok) {
                .nop, .begin_node => {
                    cur_ptr += 4;
                    while(accessor.structs.asByte(cur_ptr)) |b| : (cur_ptr += 1) {
                        if(b == 0) break;
                    }
                },
                .end_node => break,
                .prop => {
                    cur_ptr += 4;
                    const prop = FdtNodeProp.fromPtr(cur_ptr, accessor);
                    cur_ptr += (@sizeOf(u32) * 2) + prop.len;

                    uart.putc('\t');
                    prop.printName();
                    uart.print(": ", void);
                    prop.printValue();
                    uart.print("\n", void);
                },
                else => {
                    cur_ptr += 1;
                }
            }
        }
        uart.puts("}\n");
    }
};

