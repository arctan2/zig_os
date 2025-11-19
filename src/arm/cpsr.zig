const uart = @import("uart");

pub const CPSR = packed struct(u32) {
    Mode: enum(u5) {
        User = 0b10000,
        FIQ = 0b10001,
        IRQ = 0b10010,
        Supervisor = 0b10011,
        Monitor = 0b10110,
        Abort = 0b10111,
        Hyp = 0b11010,
        Undefined = 0b11011,
        System = 0b11111,
    },
    T: u1,
    F: u1,
    I: enum(u1) { Masked = 1, Unmaksed = 0 },
    A: u1,
    E: u1,
    IT: u6,
    GE: u4,
    _: u4,
    J: u1,
    _IT: u2,
    Q: u1,
    V: u1,
    C: u1,
    Z: u1,
    N: u1,
};

pub inline fn read() CPSR {
    return asm volatile(
        "mrs %[val], cpsr"
        : [val] "=r" (->CPSR)
    );
}

pub inline fn write(cpsr: CPSR) void {
    return asm volatile(
        "msr cpsr, %[val]"
        :
        : [val] "r" (cpsr)
    );
}
