pub const Dfsr = enum(usize) {
    TranslateFaultSection = 0b00101,
    TranslateFaultPage = 0b00111,
    PermissionFaultSection = 0b01101,
    PermissionFaultPage = 0b01111,
    _
};

pub inline fn read() usize {
    return asm volatile ("mrc p15, 0, %[val], c5, c0, 0"
        : [val] "=r" (-> usize),
    );
}

pub inline fn write(val: usize) void {
    asm volatile ("mcr p15, 0, %[val], c5, c0, 0"
        :
        : [val] "r" (val),
    );
}
