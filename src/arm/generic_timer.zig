const uart = @import("uart");
const fdt = @import("fdt");

pub var freq: u32 = undefined;

pub const CntpCtl = packed struct(u32) {
    enable: u1,
    imask: u1,
    istatus: u1,
    reserved: u29
};

pub fn read() CntpCtl {
    return asm volatile(
        "mrc p15, 0, %[val], c14, c2, 1"
        : [val] "=r" (->CntpCtl)
        :
    );
}

pub fn write(val: CntpCtl) void {
    return asm volatile(
        "mcr p15, 0, %[val], c14, c2, 1"
        :
        : [val] "r" (val)
    );
}

pub fn setTval(val: u32) void {
    return asm volatile(
        "mcr p15, 0, %[val], c14, c2, 0"
        :
        : [val] "r" (val)
    );
}

pub fn getStatus() u1 {
    const cntp_ctl = read();
    return cntp_ctl.istatus;
}

pub fn enable() void {
    freq = asm volatile(
        "mrc p15, 0, %[val], c14, c0, 0"
        : [val] "=r" (->u32)
    );

    var cntp_ctl = read();
    cntp_ctl.enable = 1;
    cntp_ctl.imask = 0;
    write(cntp_ctl);
}

pub fn getIntrId(fdt_accessor: *const fdt.Accessor) u10 {
    const timer_node = fdt_accessor.findNode(fdt_accessor.structs.base, "timer") orelse {
        @panic("timer not found\n");
    };
    const interrupts_prop = fdt_accessor.getPropByName(timer_node, "interrupts") orelse {
        @panic("interrupts_prop not present in timer\n");
    };

    const interrupt = fdt.readInterruptProp(interrupts_prop.data, 1);
    return interrupt.toIntrId();
}
