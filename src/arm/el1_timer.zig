const uart = @import("uart");

pub var cntfrq: u32 = undefined;

pub const CNTP_CTL = packed struct(u32) {
    enable: u1,
    imask: u1,
    istatus: u1,
    reserved: u29
};

pub fn readCNTP_CTL() CNTP_CTL {
    return asm volatile(
        "mrc p15, 0, %[val], c14, c2, 1"
        : [val] "=r" (->CNTP_CTL)
        :
    );
}

pub fn writeCNTP_CTL(val: CNTP_CTL) void {
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

pub fn init() void {
    cntfrq = asm volatile(
        "mrc p15, 0, %[val], c14, c0, 0"
        : [val] "=r" (->u32)
        :
    );

    var cntp_ctl = readCNTP_CTL();
    cntp_ctl.enable = 1;
    writeCNTP_CTL(cntp_ctl);

    uart.print("cntfrq = {}\n", .{cntfrq});
}
