const std = @import("std");
const mm = @import("mm");
const kglobal = mm.kglobal;
const uart = @import("uart");
const arm = @import("arm");
const fdt = @import("fdt");
const gicv2 = @import("mmio").gicv2;
const devices = @import("devices");

pub fn setup(_: *const fdt.Accessor) void {
    var sctlr = arm.sctlr.read();
    sctlr.V = 0;
    arm.sctlr.write(sctlr);
    arm.vbar.write(kglobal.VECTOR_TABLE_BASE);

    arm.dsb();
    arm.isb();

    gicv2.D.init();
    gicv2.C.init();
}

pub fn enable() void {
    asm volatile ("cpsie i");
    uart.print("interrupts on\n", void);
}

