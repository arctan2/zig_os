const std = @import("std");
const uart = @import("uart");
const arm = @import("arm");
const mmio = @import("mmio");
const gicv2 = mmio.gicv2;

pub export fn reset_handler() void {
    uart.print("reset_hanlder\n", void);
}

pub export fn irq_handler() void {
    const ack = gicv2.C.ack();
    // defer gicv2.C.endOfIntr(ack.intr_id);

    uart.print("interrupt irq id = {}\n", .{ack.intr_id});
}

pub export fn undef_handler() void {
    uart.print("undef_hanlder\n", void);
    while(true) {}
}

pub export fn svc_handler() void {
    uart.print("svc_hanlder\n", void);
    while(true) {}
}

pub export fn pabort_handler() void {
    uart.print("_pabort_handler\n", void);
    while(true) {}
}

pub export fn dabort_handler() void {
    uart.print("_dabort_handler\n", void);
    while(true) {}
}

pub export fn fiq_handler() void {
    uart.print("_fiq_handler\n", void);
    while(true) {}
}

