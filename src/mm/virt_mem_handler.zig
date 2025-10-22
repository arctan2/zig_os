const page_table = @import("./page_table.zig");
const uart = @import("uart");
const page_alloc = @import("page_alloc.zig");
const utils = @import("utils");
const kernel_global = @import("kernel_global.zig");

const VirtAddress = packed struct {
    offset: u12,
    l2_idx: u8,
    l1_idx: u12,
};

pub const MapFlags = packed struct {
    is_l2_table_ptr: u1,
};

pub const VirtMemHandler = struct {
    l1: *page_table.L1PageTable,

    pub fn init() !VirtMemHandler {
        return .{
            .l1 = try .init(),
        };
    }

    pub fn kernelMapSection(self: *VirtMemHandler, virt: usize, phys: usize) !void {
        const virt_addr: VirtAddress align(32) = @bitCast(virt);
        const entry = self.l1.getEntryAs(page_table.SectionEntry, virt_addr.l1_idx);
        entry.section_addr = @intCast(phys >> 20);
        entry.type = .Section;
    }

    pub fn kernelUnmapSection(self: *VirtMemHandler, virt: usize) void {
        const virt_addr: VirtAddress align(32) = @bitCast(virt);
        self.l1.entries[virt_addr.l1_idx] = 0;
    }

    // for these to work properly the page allocator base address must be aligned to 1MB
    pub fn map(self: *VirtMemHandler, virt: usize, phys: usize, flags: MapFlags) !void {
        const virt_addr: VirtAddress align(32) = @bitCast(virt);
        const entry_type = self.l1.getEntryType(virt_addr.l1_idx);

        switch(entry_type) {
            .Fault => {
                if(flags.is_l2_table_ptr == 1) {
                    const l1_entry = self.l1.getEntryAs(page_table.L2TableAddr, virt_addr.l1_idx);
                    const l2_table_page = try page_alloc.allocPages(1);
                    const l2_table_phys_addr = page_alloc.pageToPhys(l2_table_page);
                    const l2_table: *page_table.L2PageTable = @ptrFromInt(kernel_global.physToVirt(l2_table_phys_addr));
                    const l2_entry = l2_table.getEntryAs(page_table.SmallPage, virt_addr.l2_idx);

                    if(l2_entry.type != .Fault) {
                        return;
                    }

                    l1_entry.l2_addr = @intCast(l2_table_phys_addr >> 12);
                    l1_entry.type = .L2TablePtr;
                    l2_entry.phys_addr = @intCast(phys >> 12);
                    l2_entry.type = .SmallPage;
                } else {
                    const entry = self.l1.getEntryAs(page_table.SectionEntry, virt_addr.l1_idx);
                    const section_page = try page_alloc.allocPages(256);
                    const section_phys_addr = kernel_global.physToVirt(page_alloc.pageToPhys(section_page));
                    entry.section_addr = @intCast(section_phys_addr >> 20);
                    entry.type = .Section;
                }
                self.l1.print();
            },
            .L2TablePtr => {
                const l1_entry = self.l1.getEntryAs(page_table.L2TableAddr, virt_addr.l1_idx);
                const l2_table_phys_addr = page_alloc.pageToPhys(l1_entry.l2_addr);
                const l2_table: *page_table.L2PageTable = @ptrFromInt(kernel_global.physToVirt(l2_table_phys_addr));
                const l2_entry = l2_table.getEntryAs(page_table.SmallPage, virt_addr.l2_idx);

                if(l2_entry.type != .Fault) {
                    return;
                }

                l2_entry.phys_addr = @intCast(phys >> 12);
                l2_entry.type = .SmallPage;
            },
            else => {
            }
        }
    }
};

