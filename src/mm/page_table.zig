const std = @import("std");
const uart = @import("uart");
const page_alloc = @import("page_alloc.zig");

const L1EntryType = enum(u2) {
    Fault = 0b00,
    L2TablePtr = 0b01,
    Section = 0b10
};

pub const SectionEntry = packed struct(usize) {
    type: L1EntryType,
    b: u1,
    c: u1,
    xn: u1,
    domain: u4,
    p: u1,
    ap: u2,
    tex: u3,
    apx: u1,
    s: u1,
    nG: u1,
    zero: u1,
    sbz: u1,
    section_addr: u12,
};

pub const L2TableAddr = packed struct(usize) {
    type: L1EntryType,
    sbz: u3,
    domain: u4,
    p: u1,
    l2_addr: u22,
};

pub const L1PageTable = struct {
    entries: [4096]usize,

    pub fn init() !*L1PageTable {
        const self_page = try page_alloc.allocPages(1);
        const self: *L1PageTable = @ptrFromInt(page_alloc.pageToPhys(self_page));
        @memset(&self.entries, 0);
        return self;
    }

    pub inline fn getEntryType(self: *const L1PageTable, idx: u12) L1EntryType {
        return @enumFromInt(@as(u2, @intCast(self.entries[idx])) & 0b11);
    }

    pub inline fn getEntryAs(self: *L1PageTable, comptime T: type, idx: u12) *T {
        return @ptrCast(&self.entries[idx]);
    }

    pub fn freeTable(_: *L1PageTable) void {
    }

    pub fn print(self: *L1PageTable) void {
        uart.print("--------L1 TABLE----------\n", void);
        var i: usize = 0;
        while(i < self.entries.len) : (i += 1) {
            const e = self.entries[i];
            if(e != 0) {
                uart.print("{}({x}): {b} ({x})\n", .{i, i, e, e});
            }
        }
        uart.print("--------L1 TABLE END----------\n", void);
    }
};

const L2EntryType = enum(u2) {
    Fault = 0b00,
    LargePage = 0b01,
    SmallPage = 0b10
};

pub const SmallPage = packed struct {
    type: L2EntryType,
    b: u1,
    c: u1,
    ap: u2,
    sbz: u3,
    apx: u1,
    s: u1,
    nG: u1,
    phys_addr: u20
};

pub const LargePage = packed struct {
    type: L2EntryType,
    b: u1,
    c: u1,
    ap: u2,
    sbz: u3,
    apx: u1,
    s: u1,
    nG: u1,
    tex: u3,
    xn: u1,
    phys_addr: u16
};

pub const L2PageTable = struct {
    entries: [256]usize,

    pub fn init() !*L1PageTable {
        const self_page = try page_alloc.allocPages(1);
        const self: *L1PageTable = @ptrFromInt(page_alloc.pageToPhys(self_page));
        @memset(&self.entries, 0);
        return self;
    }

    pub inline fn getEntryType(self: *const L1PageTable, idx: u8) L1EntryType {
        return @enumFromInt(@as(u2, @intCast(self.entries[idx])) & 0b11);
    }

    // pub fn mapEntry(self: *L2PageTable, idx: u8, addr: u20, flags: L2EntryFlags) void {
    //     const entry = self.getEntry(idx);
    //     entry.* = addr | flags;
    // }

    pub inline fn getEntryAs(self: *L2PageTable, comptime T: type, idx: u8) *T {
        return @ptrCast(&self.entries[idx]);
    }

    pub fn freeTable(_: *L1PageTable) void {
    }

    pub fn print(self: *L2PageTable) void {
        var i: usize = 0;
        for(self.entries) |e| {
            uart.print("{}: {b}\n", .{i, e});
            i += 1;
        }
    }
};
