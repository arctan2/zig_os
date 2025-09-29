const uart = @import("../uart.zig");

pub const FdtReserveEntry = packed struct {
    address: u64,
    size: u64,
};

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

    pub fn print(self: *const FdtHeader) void {
        uart.print(
            \\{{
            \\    magic: {x},
            \\    totalsize: {},
            \\    off_dt_struct: {},
            \\    off_dt_strings: {},
            \\    off_mem_rsvmap: {},
            \\    version: {},
            \\    last_comp_version: {},
            \\    boot_cpuid_phys: {},
            \\    size_dt_strings: {},
            \\    size_dt_struct: {},
            \\}
        , .{
            self.magic,
            self.totalsize,
            self.off_dt_struct,
            self.off_dt_strings,
            self.off_mem_rsvmap,
            self.version,
            self.last_comp_version,
            self.boot_cpuid_phys,
            self.size_dt_strings,
            self.size_dt_struct,
        });
    }
};

