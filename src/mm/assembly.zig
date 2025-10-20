inline fn dsb() void {
    asm volatile ("dsb" ::: .{.memory = true});
}

inline fn isb() void {
    asm volatile ("dsb" ::: .{.memory = true});
}

pub fn invalidateTLBUnified() void {
    asm volatile (
        "mrc p15, 0, %[val], c8, c7, 0"
        :
        : [val] "r" (0)
    );
    dsb();
    isb();
}

pub fn invalidateTLBEntry(virt_addr: usize) void {
    asm volatile (
        "mcr p15, 0, %[addr], c8, c7, 1"
        :
        : [addr] "r" (virt_addr)
        : .{.memory = true}
    );
    
    dsb();
    isb();
}

pub fn invalidateICache() void {
    const zero: u32 = 0;
    
    asm volatile (
        "mcr p15, 0, %[val], c7, c5, 0"
        :
        : [val] "r" (zero)
        : .{.memory = true}
    );
    
    dsb();
    isb();
}

pub fn cleanDCache() void {
    const zero: u32 = 0;
    
    asm volatile (
        "mcr p15, 0, %[val], c7, c10, 0"
        :
        : [val] "r" (zero)
        : .{.memory = true}
    );
    
    dsb();
}

pub fn invalidateDCache() void {
    const zero: u32 = 0;
    
    asm volatile (
        "mcr p15, 0, %[val], c7, c6, 0"
        :
        : [val] "r" (zero)
        : .{.memory = true}
    );
    
    dsb();
}

pub fn cleanInvalidateDCache() void {
    const zero: u32 = 0;
    
    asm volatile (
        "mcr p15, 0, %[val], c7, c14, 0"
        :
        : [val] "r" (zero)
        : .{.memory = true}
    );
    
    dsb();
}

fn invalidateBranchPredictor() void {
    const zero: u32 = 0;
    asm volatile (
        "mcr p15, 0, %[val], c7, c5, 6"
        :
        : [val] "r" (zero)
        : .{.memory = true}
    );
}

pub fn flushAllCaches() void {
    cleanInvalidateDCache();
    invalidateICache();
    invalidateBranchPredictor();
    dsb();
    isb();
}

pub fn enableMMU(ttbr: usize) void {
    asm volatile ("mcr p15, 0, %[addr], c2, c0, 0" :: [addr] "r" (ttbr));
    asm volatile ("mcr p15, 0, %[val], c3, c0, 0" :: [val] "r" (0xFFFFFFFF));
    var sctlr: u32 = undefined;
    asm volatile ("mrc p15, 0, %[val], c1, c0, 0" : [val] "=r" (sctlr));
    sctlr |= 0x1;
    asm volatile ("mcr p15, 0, %[val], c1, c0, 0" :: [val] "r" (sctlr));
    asm volatile ("isb");
}

