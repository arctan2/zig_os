pub const SystemCtrlReg = packed struct(u32) {
    MMU: u1, // MMU enable (1 = enable MMU)
    A: u1, // Alignment check enable (duplicate naming in some docs)
    DCache: u1, // Data cache enable (same as 6 in older docs — depends on core)
    ______: u1, // Reserved
    SA: u1, // Stack alignment check enable
    _A: u1, // Alignment check enable
    DUnifiedCache: u1, // Data/unified cache enable
    B: u1, // Endianness of data accesses (1 = BE)
    _____: u1, // Reserved
    RR: u1, // Cache replacement policy (duplicated in docs, often same bit as 17)
    ____: u1, // Reserved
    SW: u1, // SWP/SWPB enable (deprecated)
    Z: u1, // Branch prediction enable
    ICache: u1, // Instruction cache enable
    ___: u1, // Reserved
    L4: u1, // ARMv4 compatibility (set 0 for v7)
    V: u1, // Exception vector base (0 = low, 1 = high address)
    _RR: u1, // Round Robin cache replacement
    HA: u1, // Hardware Access flag enable
    WXN: u1, // Write eXecute Never
    UWXN: u1, // Unprivileged Write eXecute Never
    FI: u1, // Fast Interrupts configurable
    U: u1, // Unaligned access enable (1 = allow unaligned access)
    XP: u1, // Extended Page Tables (subpage disabled if 1)
    VE: u1, // Vectors Enable (1 = vectored interrupts)
    __: u1, // Reserved
    EE: u1, // Exception Endianness (1 = BE, 0 = LE)
    NMFI: u1, // Non-maskable FIQ enable
    _: u1, // Reserved
    TRE: u1, // TEX Remap Enable (1 = use TEX remapping)
    AFE: u1, // Access Flag Enable (1 = use AP[1:0] as access flag)
    TE: u1, // Thumb Exception enable (1 = exceptions use Thumb state)
};

pub fn read() SystemCtrlReg {
    return asm volatile ("mrc p15, 0, %[val], c1, c0, 0" : [val] "=r" (->SystemCtrlReg));
}

pub fn write(val: SystemCtrlReg) void {
    asm volatile ("mcr p15, 0, %[val], c1, c0, 0" :: [val] "r" (val));
}
