const uart = @import("uart");

pub const CPSR = packed struct(u32) {
    M: u5,
    T: u1,
    F: u1,
    I: u1,
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
