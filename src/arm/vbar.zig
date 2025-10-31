pub fn read() usize {
    return asm volatile (
        \\ mrc p15, 0, %[addr], c12, c0, 0
        : [addr] "=r" (->usize)
    );
}

pub fn write(val: usize) void {
    asm volatile (
        \\ mcr p15, 0, %[addr], c12, c0, 0
        :
        : [addr] "r" (val)
    );
}
