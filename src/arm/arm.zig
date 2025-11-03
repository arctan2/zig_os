const uart = @import("uart");
pub const sctlr = @import("sctlr.zig");
pub const ttbr = @import("ttbr.zig");
pub const generic_timer = @import("generic_timer.zig");
pub const vbar = @import("vbar.zig");
pub const isr = @import("isr.zig");

pub inline fn dsb() linksection(".text.boot") void {
    asm volatile ("dsb");
}

pub inline fn isb() linksection(".text.boot") void {
    asm volatile ("isb");
}

pub inline fn invalidateTLBUnified() linksection(".text.boot") void {
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

pub inline fn invalidateICache() linksection(".text.boot") void {
    asm volatile ("mcr p15, 0, %[val], c7, c5, 0"
        :
        : [val] "r" (0),
    );

    dsb();
    isb();
}

pub inline fn cleanDCache() linksection(".text.boot") void {
    asm volatile ("mcr p15, 0, %[val], c7, c10, 0"
        :
        : [val] "r" (0),
    );

    dsb();
}

pub inline fn invalidateDCache() linksection(".text.boot") void {
    asm volatile ("mcr p15, 0, %[val], c7, c6, 0"
        :
        : [val] "r" (0),
    );

    dsb();
}

pub inline fn cleanInvalidateDCache() linksection(".text.boot") void {
    asm volatile ("mcr p15, 0, %[val], c7, c14, 0"
        :
        : [val] "r" (0),
    );

    dsb();
}

pub inline fn invalidateBranchPredictor() linksection(".text.boot") void {
    asm volatile ("mcr p15, 0, %[val], c7, c5, 6"
        :
        : [val] "r" (0),
    );
}

pub fn flushAllCaches() linksection(".text.boot") void {
    cleanInvalidateDCache();
    invalidateICache();
    invalidateBranchPredictor();
    dsb();
    isb();
}

pub fn curCpuNumber() u8 {
    return @intCast(asm volatile("mrc p15, 0, %[val], c0, c0, 5" : [val] "=r" (->u32)) & 0xFF);
}

pub inline fn enableMMU(ttbr1: usize) linksection(".text.boot") void {
    ttbr.write(1, ttbr1);
    ttbr.write(0, ttbr1);

    // var ttbcr = ttbr.readTTBCR();
    var reg = sctlr.read();
    // ttbcr.N = 2;
    // ttbr.writeTTBCR(ttbcr);
    ttbr.writeDomain(0xFFFFFFFF);

    reg.MMU = 1;
    reg.ICache = 0;
    reg.DUnifiedCache = 0;
    reg.DCache = 0;
    reg.Z = 0;
    sctlr.write(reg);

    invalidateTLBUnified();
    invalidateBranchPredictor();
    flushAllCaches();

    asm volatile ("dsb");
    asm volatile ("isb");
}
