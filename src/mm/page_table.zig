const std = @import("std");
const uart = @import("uart");
const page_alloc = @import("page_alloc.zig");
const kglobal = @import("kglobal.zig");

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

    pub inline fn addr(self: *const SectionEntry) usize {
        return @as(usize, self.section_addr) << 20;
    }

    pub inline fn free(self: *SectionEntry) void {
        page_alloc.freeAddr(self.addr());
    }
};

pub const L2TableAddr = packed struct(usize) {
    type: L1EntryType,
    sbz: u3,
    domain: u4,
    p: u1,
    l2_addr: u22,

    pub inline fn addr(self: *const L2TableAddr) usize {
        return @as(usize, self.l2_addr) << 10;
    }

    pub inline fn toTable(self: *const L2TableAddr) *L2PageTable {
        return @ptrFromInt(self.addr());
    }

    pub inline fn free(self: *L2TableAddr) void {
        self.toTable().drop();
    }
};

pub const L1PageTable = struct {
    entries: [4096]usize,

    pub fn init() !*L1PageTable {
        const self_page = try page_alloc.allocPages(4);
        const self: *L1PageTable = @ptrFromInt(page_alloc.pageToPhys(self_page));
        @memset(&self.entries, 0);
        return self;
    }

    pub inline fn getEntryType(self: *const L1PageTable, idx: usize) L1EntryType {
        return @enumFromInt(self.entries[idx] & 0b11);
    }

    pub inline fn getEntryAs(self: *L1PageTable, comptime T: type, idx: usize) *T {
        return @ptrCast(&self.entries[idx]);
    }

    pub fn free(self: *L1PageTable) void {
        page_alloc.freeAddr(@intFromPtr(self));
    }

    pub fn freeEntries(self: *L1PageTable) void {
        for(0..self.entries.len) |i| {
            const idx: usize = @intCast(i);
            switch(self.getEntryType(idx)) {
                .Section => self.getEntryAs(SectionEntry, idx).free(),
                .L2TablePtr => self.getEntryAs(L2TableAddr, idx).free(),
                else => {}
            }
            self.entries[i] = 0;
        }
    }

    pub fn drop(self: *L1PageTable) void {
        self.freeEntries();
        self.free();
    }

    pub fn print(self: *L1PageTable) void {
        uart.print("--------L1 TABLE ({x})----------\n", .{@intFromPtr(self)});
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
    phys_addr: u20,

    pub inline fn addr(self: *const SmallPage) usize {
        return @as(usize, self.phys_addr) << 12;
    }
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
    phys_addr: usize,

    pub inline fn addr(self: *const LargePage) usize {
        return @as(usize, self.phys_addr) << 16;
    }
};

pub const L2PageTable = struct {
    entries: [256]usize,

    pub fn init() !*L2PageTable {
        const self_page = try page_alloc.allocPages(1);
        const self: *L2PageTable = @ptrFromInt(page_alloc.pageToPhys(self_page));
        @memset(&self.entries, 0);
        return self;
    }

    pub inline fn getEntryType(self: *const L2PageTable, idx: usize) L2EntryType {
        return @enumFromInt(self.entries[idx] & 0b11);
    }

    pub inline fn getEntryAs(self: *L2PageTable, comptime T: type, idx: usize) *T {
        return @ptrCast(@alignCast(&self.entries[idx]));
    }

    pub inline fn drop(self: *L2PageTable) void {
        self.freeEntries();
        self.free();
    }
    
    pub fn free(self: *L2PageTable) void {
        page_alloc.freeAddr(@intFromPtr(self));
    }

    pub fn freeEntries(self: *L2PageTable) void {
        for(0..self.entries.len) |i| {
            const idx: usize = @intCast(i);
            switch(self.getEntryType(idx)) {
                .SmallPage => {
                    const small_page = self.getEntryAs(SmallPage, idx);
                    page_alloc.freeAddr(small_page.addr());
                },
                .LargePage => {
                    const large_page = self.getEntryAs(LargePage, idx);
                    page_alloc.freeAddr(large_page.addr());
                },
                else => {}
            }
        }
    }

    pub fn print(self: *L2PageTable) void {
        uart.print("--------L2 TABLE ({x})----------\n", .{@intFromPtr(self)});
        var i: usize = 0;
        while(i < self.entries.len) : (i += 1) {
            const e = self.entries[i];
            if(e != 0) {
                uart.print("{}({x}): {b} ({x})\n", .{i, i, e, e});
            }
        }
        uart.print("--------L2 TABLE END----------\n", void);
    }
};

pub inline fn physToL1Virt(addr: usize) *L1PageTable {
    return @ptrFromInt(kglobal.physToVirt(addr));
}

pub inline fn physToL2Virt(addr: usize) *L2PageTable {
    return @ptrFromInt(kglobal.physToVirt(addr));
}

