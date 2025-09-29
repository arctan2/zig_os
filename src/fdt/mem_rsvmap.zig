const uart = @import("../uart.zig");
const utils = @import("../utils.zig");
const std = @import("std");
const types = @import("types.zig");

pub const FdtReserveEntryAccessor = struct {
    base: [*]types.FdtReserveEntry,
    max_count: u32,
    cur_count: usize = 0,

    pub fn init(fdt_base: [*]const u8, fdt_header: *const types.FdtHeader) FdtReserveEntryAccessor {
        const start = fdt_base + fdt_header.off_mem_rsvmap;
        const size: u32 = fdt_header.off_dt_struct - fdt_header.off_mem_rsvmap;
        const max_count = size / @sizeOf(types.FdtReserveEntry);
        return FdtReserveEntryAccessor{ .base = @ptrCast(@alignCast(start)), .max_count = max_count };
    }

    fn at(self: *FdtReserveEntryAccessor, idx: usize) ?types.FdtReserveEntry {
        if(idx >= self.max_count) {
            return null;
        }
        const block = utils.structBigToNative(
            types.FdtReserveEntry, 
            &@as([*]types.FdtReserveEntry, @ptrCast(@alignCast(self.base)))[idx]
        );
        return block;
    }

    pub fn next(self: *FdtReserveEntryAccessor) ?types.FdtReserveEntry {
        const block = self.at(self.cur_count);
        self.cur_count += 1;
        return block;
    }
};
