pub inline fn read() usize {
    return asm volatile ("mov %[val], lr"
        : [val] "=r" (-> usize),
    );
}
