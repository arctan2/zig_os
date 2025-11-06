const uart = @import("uart");
pub const sctlr = @import("sctlr.zig");
pub const ttbr = @import("ttbr.zig");
pub const generic_timer = @import("generic_timer.zig");
pub const vbar = @import("vbar.zig");
pub const isr = @import("isr.zig");

pub inline fn dsb() void {
    asm volatile ("dsb");
}

pub inline fn isb() void {
    asm volatile ("isb");
}

pub inline fn invalidateTLBUnified() void {
    asm volatile ("mcr p15, 0, %[val], c8, c7, 0"
        :
        : [val] "r" (0),
    );
    dsb();
    isb();
}

pub inline fn invalidateTLBEntry(virt_addr: usize) void {
    asm volatile ("mcr p15, 0, %[addr], c8, c7, 1"
        :
        : [addr] "r" (virt_addr),
    );

    dsb();
    isb();
}

pub inline fn invalidateICache() void {
    asm volatile ("mcr p15, 0, %[val], c7, c5, 0"
        :
        : [val] "r" (0),
    );

    dsb();
    isb();
}

pub inline fn cleanDCache() void {
    asm volatile ("mcr p15, 0, %[val], c7, c10, 0"
        :
        : [val] "r" (0),
    );

    dsb();
}

pub inline fn invalidateDCache() void {
    asm volatile ("mcr p15, 0, %[val], c7, c6, 0"
        :
        : [val] "r" (0),
    );

    dsb();
}

pub inline fn cleanInvalidateDCache() void {
    asm volatile ("mcr p15, 0, %[val], c7, c14, 0"
        :
        : [val] "r" (0),
    );

    dsb();
}

pub inline fn invalidateBranchPredictor() void {
    asm volatile ("mcr p15, 0, %[val], c7, c5, 6"
        :
        : [val] "r" (0),
    );
}

pub inline fn flushAllCaches() void {
    cleanInvalidateDCache();
    invalidateICache();
    invalidateBranchPredictor();
    dsb();
    isb();
}

pub fn curCpuNumber() u8 {
    return @intCast(asm volatile("mrc p15, 0, %[val], c0, c0, 5" : [val] "=r" (->u32)) & 0xFF);
}

