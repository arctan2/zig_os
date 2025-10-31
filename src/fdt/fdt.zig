pub const std = @import("std");
pub const types = @import("types.zig");
pub const mem_rsvmap = @import("mem_rsvmap.zig");

const utils = @import("utils");
const uart = @import("uart");

const AddrSizeCells = struct { addr: u32, size: u32 };

pub const InterruptProp = struct { 
    intr_type: enum(u32) { SPI = 0, PPI = 1, SGI = 2 },
    irq_number: u32,
    flags: u32,

    pub fn toIntrId(self: *const InterruptProp) u10 {
        return @intCast(self.irq_number + switch(self.intr_type) {
            .SGI => @as(u10, 0),
            .PPI => @as(u10, 16),
            .SPI => @as(u10, 32),
        });
    }
};

pub fn readRegFromCells(addr_size_cells: AddrSizeCells, ptr: [*]const u8, idx: usize) usize {
    const p: [*]const u8 = @ptrCast(ptr + (idx * (@sizeOf(u32) * addr_size_cells.addr)));
    return @intCast(switch (addr_size_cells.size) {
        0x1 => std.mem.readInt(u32, @ptrCast(p), .big),
        0x2 => std.mem.readInt(u64, @ptrCast(p), .big),
        0x3 => std.mem.readInt(u128, @ptrCast(p), .big),
        else => 0,
    });
}

pub fn readInterruptProp(ptr: [*]const u8, idx: usize) InterruptProp {
    const p: [*]const u8 = @ptrCast(ptr + (idx * @sizeOf(u32) * 3));
    const intr_type = std.mem.readInt(u32, @ptrCast(p), .big);
    const irq_number = std.mem.readInt(u32, @ptrCast(p + @sizeOf(u32)), .big);
    const flags = std.mem.readInt(u32, @ptrCast(p + (@sizeOf(u32) * 2)), .big);
    return .{ .intr_type = @enumFromInt(intr_type), .irq_number = irq_number, .flags = flags };
}

pub fn getMemStartSize(fdt_base: [*]const u8) struct { start: usize, size: usize } {
    const fdt_accessor = Accessor.init(fdt_base);
    const root_node = fdt_accessor.structs.base;
    const addr_size_cells = fdt_accessor.getAddrSizeCells(root_node) orelse {
        @panic("size addr cells of root node is not present");
    };

    const memory_block = fdt_accessor.findNode(root_node, "memory") orelse {
        @panic("memory not found");
    };
    const reg = fdt_accessor.getPropByName(memory_block, "reg") orelse {
        @panic("reg not found");
    };

    const mem_start = readRegFromCells(addr_size_cells, reg.data, 0);
    const mem_size = readRegFromCells(addr_size_cells, reg.data, 1);

    return .{ .start = mem_start, .size = mem_size };
}

pub const FdtNodeProp = struct {
    name_addr: [*]const u8,
    len: u32,
    data: [*]const u8,

    pub fn fromPtr(ptr: [*]const u8, accessor: *const Accessor) FdtNodeProp {
        const len: u32 = std.mem.readInt(u32, @ptrCast(ptr), .big);
        const nameoff: u32 = std.mem.readInt(u32, @ptrCast(ptr + 4), .big);
        if (accessor.stringAddrFromOffset(nameoff)) |addr| {
            return .{ .len = len, .name_addr = addr, .data = ptr + 8 };
        } else {
            @panic("invalid strings block access.");
        }
    }

    pub fn printValue(self: *const FdtNodeProp) void {
        var i: usize = 0;

        if (('a' <= self.data[i] and self.data[i] <= 'z') or
            ('A' <= self.data[i] and self.data[i] <= 'Z'))
        {
            uart.print("'", void);
            while (i < self.len) : (i += 1) {
                uart.print("{c}", .{self.data[i]});
            }
            uart.print("' ", void);
        } else {
            i = 0;
            uart.print("<", void);
            while (i < self.len) : (i += 1) {
                uart.print("{x} ", .{self.data[i]});
            }
            uart.print(">", void);
        }
    }

    pub fn isNameStartsWith(self: *const FdtNodeProp, name: []const u8) bool {
        var i: usize = 0;
        while (i < name.len) : (i += 1) {
            if (self.name_addr[i] != name[i]) return false;
        }
        return true;
    }

    pub fn isNameEquals(self: *const FdtNodeProp, name: []const u8) bool {
        var i: usize = 0;
        while (i < name.len) : (i += 1) {
            if (self.name_addr[i] != name[i]) return false;
        }
        return self.name_addr[i] == 0;
    }

    pub fn printName(self: *const FdtNodeProp) void {
        uart.print("'", void);
        var i: usize = 0;
        while (self.name_addr[i] != 0) : (i += 1) {
            uart.putc(self.name_addr[i]);
        }
        uart.print("'", void);
    }
};

pub const FdtNode = [*]const u8;

const Token = enum(u32) { begin_node = 0x1, end_node = 0x2, prop = 0x3, nop = 0x4, end = 0x9, _ };

pub const Accessor = struct {
    structs: struct { base: [*]const u8, end: [*]const u8 },
    strings: struct { base: [*]const u8, end: [*]const u8 },

    pub fn parseHeader(fdt_base: [*]const u8) types.FdtHeader {
        const fdt_header_base: *types.FdtHeader = @constCast(@ptrCast(@alignCast(fdt_base)));
        return utils.structBigToNative(types.FdtHeader, fdt_header_base);
    }

    pub fn init(fdt_base: [*]const u8) Accessor {
        const fdt_header = Accessor.parseHeader(fdt_base);
        return .{
            .structs = .{ .base = fdt_base + fdt_header.off_dt_struct, .end = fdt_base + fdt_header.off_dt_struct + fdt_header.size_dt_struct },
            .strings = .{ .base = fdt_base + fdt_header.off_dt_strings, .end = fdt_base + fdt_header.off_dt_strings + fdt_header.size_dt_strings },
        };
    }

    pub fn getAddrSizeCells(self: *const Accessor, node: FdtNode) ?AddrSizeCells {
        var address_cells: u32 = 0;
        var size_cells: u32 = 0;

        if (self.getPropByName(node, "#address-cells")) |prop| {
            address_cells = std.mem.readInt(u32, @ptrCast(prop.data), .big);
        } else {
            return null;
        }

        if (self.getPropByName(node, "#size-cells")) |prop| {
            size_cells = std.mem.readInt(u32, @ptrCast(prop.data), .big);
        } else {
            return null;
        }

        return .{ .addr = address_cells, .size = size_cells };
    }

    pub fn asToken(self: *const Accessor, cur_ptr: [*]const u8) ?Token {
        if (utils.ptr.gte([*]const u8, cur_ptr, self.structs.end)) return null;
        var tok: Token = undefined;
        const ptr: *const u32 = @ptrCast(@alignCast(cur_ptr));
        tok = @enumFromInt(utils.bigToNative(u32, ptr.*));
        return tok;
    }

    pub fn asByte(self: *const Accessor, cur_ptr: [*]const u8) ?u8 {
        if (utils.ptr.gte([*]const u8, cur_ptr, self.structs.end)) return null;
        return cur_ptr[0];
    }

    pub fn stringAddrFromOffset(self: *const Accessor, offset: usize) ?[*]const u8 {
        const ptr = self.strings.base + offset;
        if (utils.ptr.gte([*]const u8, ptr, self.strings.end)) return null;
        return ptr;
    }

    pub fn printStringFromOffset(self: *const Accessor, offset: usize) void {
        if (self.getAddrFromOffset(offset)) |ptr| {
            var i: usize = 0;
            while (ptr[i] != 0) : (i += 1) {
                uart.putc(ptr[i]);
            }
        } else {
            uart.print("null", void);
        }
    }

    pub fn getPropByName(self: *const Accessor, node: FdtNode, name: []const u8) ?FdtNodeProp {
        var cur_ptr: [*]const u8 = utils.ptr.align4(node + 4);

        while (self.asToken(cur_ptr)) |tok| : (cur_ptr = utils.ptr.align4(cur_ptr)) {
            switch (tok) {
                .nop => {
                    cur_ptr += 4;
                    while (self.asByte(cur_ptr)) |b| : (cur_ptr += 1) {
                        if (b == 0) break;
                    }
                },
                .end_node, .end, .begin_node => break,
                .prop => {
                    cur_ptr += 4;
                    const prop = FdtNodeProp.fromPtr(cur_ptr, self);
                    cur_ptr += (@sizeOf(u32) * 2) + prop.len;

                    if (prop.isNameEquals(name)) {
                        return prop;
                    }
                },
                else => {
                    cur_ptr += 1;
                },
            }
        }

        return null;
    }

    pub fn findNodeWithProp(self: *const Accessor, node: FdtNode, name: []const u8) ?FdtNode {
        var cur_ptr: [*]const u8 = utils.ptr.align4(node);

        while (self.asToken(cur_ptr)) |tok| : (cur_ptr = utils.ptr.align4(cur_ptr + 4)) {
            switch (tok) {
                .begin_node => {
                    if (self.getPropByName(cur_ptr, name)) |_| {
                        return cur_ptr;
                    }
                },
                else => {},
            }
        }

        return null;
    }

    pub const FindParentResult = union(enum) { Found: ?FdtNode, EndNode: [*]const u8, NotFound: void };

    fn findParentRecursive(self: *const Accessor, cur_node: FdtNode, node: FdtNode) FindParentResult {
        var cur_ptr: [*]const u8 = cur_node;

        cur_ptr += 4;
        while (self.asByte(cur_ptr)) |b| : (cur_ptr += 1) {
            if (b == 0) break;
        }

        cur_ptr = utils.ptr.align4(cur_ptr);

        while (self.asToken(cur_ptr)) |tok| : (cur_ptr = utils.ptr.align4(cur_ptr)) {
            switch (tok) {
                .nop => cur_ptr += 4,
                .begin_node => {
                    if (cur_ptr == node) {
                        return .{ .Found = cur_node };
                    } else {
                        const result = self.findParentRecursive(cur_ptr, node);
                        switch (result) {
                            .EndNode => |end| cur_ptr = end + 4,
                            else => return result,
                        }
                    }
                },
                .prop => {
                    cur_ptr += 4;
                    const prop = FdtNodeProp.fromPtr(cur_ptr, self);
                    cur_ptr += (@sizeOf(u32) * 2) + prop.len;
                },
                .end => {
                    return .NotFound;
                },
                .end_node => {
                    return FindParentResult{ .EndNode = cur_ptr };
                },
                else => {
                    cur_ptr += 1;
                },
            }
        }

        return .NotFound;
    }

    pub fn findParent(self: *const Accessor, node: FdtNode) ?FdtNode {
        if (self.structs.base == node) return null;
        return switch (self.findParentRecursive(self.structs.base, node)) {
            .Found => |n| n,
            else => null,
        };
    }

    pub fn findNode(self: *const Accessor, node: FdtNode, starts_with: []const u8) ?FdtNode {
        var cur_ptr: [*]const u8 = utils.ptr.align4(node);

        while (self.asToken(cur_ptr)) |tok| : (cur_ptr = utils.ptr.align4(cur_ptr + 4)) {
            switch (tok) {
                .begin_node => {
                    const start = cur_ptr;
                    cur_ptr += 4;
                    for (starts_with) |c| {
                        if (self.asByte(cur_ptr)) |b| {
                            if (b == 0 or b != c) break;
                            cur_ptr += 1;
                        } else {
                            break;
                        }
                    }

                    // str.len + 4 because I'm using start as FDT_BEGIN_NODE address which is u32
                    if ((cur_ptr - start) == (starts_with.len + 4)) {
                        return start;
                    }
                },
                else => {},
            }
        }

        return null;
    }

    pub fn printNode(self: *const Accessor, node: FdtNode) void {
        var cur_ptr = node;
        var indent: usize = 0;
        var depth: usize = 0;

        while (self.asToken(cur_ptr)) |tok| : (cur_ptr = utils.ptr.align4(cur_ptr)) {
            switch (tok) {
                .nop, .begin_node => {
                    cur_ptr += 4;
                    indent += 1;
                    for (0..(indent - 1)) |_| uart.putc('\t');
                    while (self.asByte(cur_ptr)) |b| : (cur_ptr += 1) {
                        uart.print("{c}", .{b});
                        if (b == 0) break;
                    }
                    uart.print("{{\n", void);
                    depth += 1;
                },
                .end_node => {
                    indent -= 1;
                    depth -= 1;
                    for (0..indent) |_| uart.putc('\t');
                    uart.print("}\n", void);
                    cur_ptr += 1;
                    if (depth == 0) return;
                },
                .end => {
                    break;
                },
                .prop => {
                    cur_ptr += 4;
                    const prop = FdtNodeProp.fromPtr(cur_ptr, self);
                    cur_ptr += (@sizeOf(u32) * 2) + prop.len;

                    for (0..indent) |_| uart.putc('\t');

                    prop.printName();
                    uart.print(": ", void);
                    prop.printValue();
                    uart.print("\n", void);
                },
                else => {
                    cur_ptr += 1;
                },
            }
        }
    }
};
