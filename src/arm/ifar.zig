pub inline fn read() usize {
    return asm volatile ("mrc p15, 0, %[val], c6, c0, 2"
        : [val] "=r" (-> usize),
    );
}

pub inline fn write(val: usize) void {
    asm volatile ("mcr p15, 0, %[val], c6, c0, 2"
        :
        : [val] "r" (val),
    );
}
