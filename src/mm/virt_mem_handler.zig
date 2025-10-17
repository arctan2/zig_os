const PageTable = @import("./page_table.zig").PageTable;
const uart = @import("uart");
const page_alloc = @import("page_alloc.zig");
const utils = @import("utils");

const L1PageTable = PageTable(4096);

const VirtAddress = packed struct {
    offset: u12,
    l2: u8,
    l1: u12,
};

const L1EntryType = enum(u2) {
    Fault = 0b00,
    L2TablePtr = 0b01,
    Section = 0b10
};

const MapFlags = enum(u16) {
    L2TablePtr = 1 << 0,
    _,

    fn isFlagSet(flags: MapFlags, flag: MapFlags) bool {
        return (@intFromEnum(flags) & @intFromEnum(flag)) == 1;
    }
};

pub const VirtMemHandler = struct {
    l1: *L1PageTable,

    pub fn init() !VirtMemHandler {
        return .{
            .l1 = try .init(),
        };
    }

    fn setL1EntryType(addr: *usize, flag: L1EntryType) void {
        addr.* = addr.* | @intFromEnum(flag);
    }

    pub fn map(self: *VirtMemHandler, virt: usize, _: usize, flags: MapFlags) !void {
        const virt_addr: VirtAddress align(32) = @bitCast(virt);
        const l1_entry = &self.l1.entries[virt_addr.l1];
        const l1_desc: L1EntryType = @enumFromInt(l1_entry.* & 0b11);

        switch(l1_desc) {
            .Fault => {
                if(MapFlags.isFlagSet(flags, .L2TablePtr)) {
                    const table_page = try page_alloc.allocPages(1);
                    const table_page_phys_addr = page_alloc.pageToPhys(table_page);
                    l1_entry.* = table_page_phys_addr & 0xfffffc00;
                    setL1EntryType(l1_entry, .L2TablePtr);
                } else {
                    const table_page = try page_alloc.allocPages(256);
                    const table_page_phys_addr = page_alloc.pageToPhys(table_page);
                    l1_entry.* = table_page_phys_addr & 0xfff00000;
                    setL1EntryType(l1_entry, .Section);
                }
                uart.print("{b}\n", .{l1_entry.*});
            },
            .L2TablePtr => {
                uart.print("TODO: L2PagePtr", void);
            },
            .Section => {
                uart.print("TODO: Section", void);
            }
        }
    }
};

