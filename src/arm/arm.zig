pub const sctlr = @import("sctlr.zig");
pub const ttbr = @import("ttbr.zig");
pub const uart = @import("uart");

pub inline fn dsb() void {
    asm volatile ("dsb");
}

pub inline fn isb() void {
    asm volatile ("isb");
}

pub fn invalidateTLBUnified() void {
    asm volatile ("mcr p15, 0, %[val], c8, c7, 0"
        :
        : [val] "r" (0),
    );
    dsb();
    isb();
}

pub fn invalidateTLBEntry(virt_addr: usize) void {
    asm volatile ("mcr p15, 0, %[addr], c8, c7, 1"
        :
        : [addr] "r" (virt_addr),
    );

    dsb();
    isb();
}

pub fn invalidateICache() void {
    asm volatile ("mcr p15, 0, %[val], c7, c5, 0"
        :
        : [val] "r" (0),
    );

    dsb();
    isb();
}

pub fn cleanDCache() void {
    asm volatile ("mcr p15, 0, %[val], c7, c10, 0"
        :
        : [val] "r" (0),
    );

    dsb();
}

pub fn invalidateDCache() void {
    asm volatile ("mcr p15, 0, %[val], c7, c6, 0"
        :
        : [val] "r" (0),
    );

    dsb();
}

pub fn cleanInvalidateDCache() void {
    asm volatile ("mcr p15, 0, %[val], c7, c14, 0"
        :
        : [val] "r" (0),
    );

    dsb();
}

fn invalidateBranchPredictor() void {
    asm volatile ("mcr p15, 0, %[val], c7, c5, 6"
        :
        : [val] "r" (0),
    );
}

pub fn flushAllCaches() void {
    cleanInvalidateDCache();
    invalidateICache();
    invalidateBranchPredictor();
    dsb();
    isb();
}

pub fn enableMMU(ttbr1: usize) void {
    var ttbcr = ttbr.readTTBCR();
    var reg = sctlr.read();

    ttbcr.N = 2;
    ttbr.writeTTBCR(ttbcr);
    ttbr.write(1, ttbr1);
    ttbr.writeDomain(0xFFFFFFFF);
    reg.MMU = 1;
    sctlr.write(reg);
    isb();
}
