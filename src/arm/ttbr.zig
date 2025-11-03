pub const TTBCR = packed struct(u32) {
    N: u3,
    not_used: u29,
};

pub inline fn read(comptime number: u1) linksection(".text.boot") usize {
    if(number == 1) {
        return asm volatile ("mrc p15, 0, %[val], c2, c0, 1" : [val] "=r" (->usize));
    } else {
        return asm volatile ("mrc p15, 0, %[val], c2, c0, 0" : [val] "=r" (->usize));
    }
}

pub inline fn write(comptime number: u1, val: usize) linksection(".text.boot") void {
    if(number == 1) {
        asm volatile ("mcr p15, 0, %[val], c2, c0, 1" :: [val] "r" (val));
    } else {
        asm volatile ("mcr p15, 0, %[val], c2, c0, 0" :: [val] "r" (val));
    }
}

pub inline fn writeDomain(val: usize) linksection(".text.boot") void {
    asm volatile ("mcr p15, 0, %[val], c3, c0, 0" :: [val] "r" (val));
}

pub inline fn readTTBCR() linksection(".text.boot") TTBCR {
    return asm volatile ("mrc p15, 0, %[val], c2, c0, 2" : [val] "=r" (->TTBCR));
}

pub inline fn writeTTBCR(ttbcr: TTBCR) linksection(".text.boot") void {
    asm volatile ("mcr p15, 0, %[val], c2, c0, 2" :: [val] "r" (ttbcr));
}
