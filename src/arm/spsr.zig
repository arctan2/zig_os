pub inline fn read() usize {
    return asm volatile ("mrs %[val], spsr"
        : [val] "=r" (-> usize),
    );
}
