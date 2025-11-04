pub const TTBCR = packed struct(u32) {
    N: u3,
    not_used: u29,
};

pub inline fn read(comptime number: u1) usize {
    if(number == 1) {
        return asm volatile ("mrc p15, 0, %[val], c2, c0, 1" : [val] "=r" (->usize));
    } else {
        return asm volatile ("mrc p15, 0, %[val], c2, c0, 0" : [val] "=r" (->usize));
    }
}

pub inline fn write(comptime number: u1, val: usize) void {
    if(number == 1) {
        asm volatile ("mcr p15, 0, %[val], c2, c0, 1" :: [val] "r" (val));
    } else {
        asm volatile ("mcr p15, 0, %[val], c2, c0, 0" :: [val] "r" (val));
    }
}

pub inline fn writeDomain(val: usize) void {
    asm volatile ("mcr p15, 0, %[val], c3, c0, 0" :: [val] "r" (val));
}

pub inline fn readTTBCR() TTBCR {
    return asm volatile ("mrc p15, 0, %[val], c2, c0, 2" : [val] "=r" (->TTBCR));
}

pub inline fn writeTTBCR(ttbcr: TTBCR) void {
    asm volatile ("mcr p15, 0, %[val], c2, c0, 2" :: [val] "r" (ttbcr));
}
