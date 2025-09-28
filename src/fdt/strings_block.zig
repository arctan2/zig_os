const std = @import("std");
const types = @import("types.zig");

pub const StringAccessor = struct {
    base: [*]u8,
    max_size: u64,
    cur_ptr: [*]u8,

    pub fn init(fdt_base: [*]u8, fdt_header: *const types.FdtHeader) StringAccessor {
        const base = fdt_base + fdt_header.off_dt_strings;
        return StringAccessor{ .base = base, .cur_ptr = base, .max_size = fdt_header.size_dt_strings };
    }

    pub fn next(self: *StringAccessor) ?struct{ [*]u8, usize } {
        const cur_pos = @as(usize, self.cur_ptr - self.base);
        if(cur_pos >= self.max_size) return null;
        const cur = self.cur_ptr;

        while(self.cur_ptr[0] != 0) {
            self.cur_ptr += 1;
        }

        self.cur_ptr += 1;

        return .{cur, self.cur_ptr - cur};
    }
};

