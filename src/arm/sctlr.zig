pub const SystemCtrlReg = packed struct(u32) {
    M: u1, // MMU enable
    A: u1, // Alignment check enable
    C: u1, // Data cache enable
    _b3_10: u8,
    Z: u1, // Branch prediction enable bit. See Example 3.2 and Invalidating and cleaning cache memory.
    I: u1, // Instruction cache enable bit. See Example 3.2 and Invalidating and cleaning cache memory.
    V: u1, // This bit selects the base address of the exception vector table. See The Vector table.
    _b14_20: u7,
    FI: u1, // FIQ configuration enable. See External interrupt requests.
    U: u1, //Indicates use of the alignment model. See Alignment.
    _b23_24: u2,
    EE: u1, // Exception endianness. This defines the value of the CPSR.E bit on entry to an exception. See Endianness.
    _b26: u1,
    NMFI: u1, // Non-maskable FIQ (NMFI) support. See External interrupt requests.
    _b28_29: u2,
    TE: u1, // Thumb exception enable. This controls whether exceptions are taken in ARM or Thumb state.
    _b31: u1
};

pub inline fn read() SystemCtrlReg {
    return asm volatile ("mrc p15, 0, %[val], c1, c0, 0"
        : [val] "=r" (-> SystemCtrlReg),
    );
}

pub inline fn write(val: SystemCtrlReg) void {
    asm volatile ("mcr p15, 0, %[val], c1, c0, 0"
        :
        : [val] "r" (val),
    );
}
