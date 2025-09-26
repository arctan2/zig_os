const uart = @import("./uart.zig");
const utils = @import("./utils.zig");

pub const FdtHeader = packed struct {
    magic: u32,
    totalsize: u32,
    off_dt_struct: u32,
    off_dt_strings: u32,
    off_mem_rsvmap: u32,
    version: u32,
    last_comp_version: u32,
    boot_cpuid_phys: u32,
    size_dt_strings: u32,
    size_dt_struct: u32,
};

pub const FdtReserveEntry = packed struct {
    address: u64,
    size: u64
};

pub const FdtReserveEntryTraverser = struct {
    cur_ptr: *FdtReserveEntry,
    count: u32,
    cur_count: u32 = 0,

    pub fn init(dtb_base: [*]u8, dtb_header: *FdtHeader) FdtReserveEntryTraverser {
        const start = dtb_base + dtb_header.off_mem_rsvmap;
        const size = @as(u32, @intFromPtr(dtb_base + dtb_header.off_dt_struct)) - @as(u32, @intFromPtr(start));
        const count = size / @sizeOf(u64) * 2;
        const cur_ptr: *FdtReserveEntry = utils.structBigToNative(FdtReserveEntry, start);

        return FdtReserveEntryTraverser{
            .cur_ptr = cur_ptr,
            .count = count
        };
    }

    pub fn next(self: *FdtReserveEntryTraverser) ?*FdtReserveEntry {
        if(self.cur_count == self.count) {
            return null;
        }

        self.cur_count += 1;

        if(self.cur_count == 1) {
            return self.cur_ptr;
        }

        const raw = @as([*]u8, @ptrCast(self.cur_ptr)) + (@sizeOf(u64) * 2);
        self.cur_ptr = utils.structBigToNative(FdtReserveEntry, raw);

        return self.cur_ptr;
    }
};
