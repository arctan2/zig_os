pub const Ifsr = enum(usize) {
    TranslateFaultSection = 0b00101,
    TranslateFaultPage = 0b00111,
    PermissionFaultSection = 0b01101,
    PermissionFaultPage = 0b01111,
    _
};

pub inline fn read() Ifsr {
    return asm volatile ("mrc p15, 0, %[val], c5, c0, 1"
        : [val] "=r" (-> Ifsr),
    );
}

pub inline fn write(val: Ifsr) void {
    asm volatile ("mcr p15, 0, %[val], c5, c0, 1"
        :
        : [val] "r" (val),
    );
}
