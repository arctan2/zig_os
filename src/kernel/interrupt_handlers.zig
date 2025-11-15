const std = @import("std");
const uart = @import("uart");
const arm = @import("arm");
const mmio = @import("mmio");
const gicv2 = mmio.gicv2;

const State = extern struct {
    registers: [13]usize,
    lr: usize,
    lr_irq: usize,
    spsr_irq: usize,
};

pub export fn reset_handler() void {
    uart.print("reset_hanlder\n", void);
}

pub export fn irq_handler(ptr: usize) void {
    const _irq_handler_sp: *State = @ptrFromInt(ptr);
    const ack = gicv2.C.ack();
    // defer gicv2.C.endOfIntr(ack.intr_id);

    uart.print("interrupt irq id = {}\n", .{ack.intr_id});
    uart.print("sp = {x}, &ack = {x}\n", .{ _irq_handler_sp, @intFromPtr(&ack) });

    uart.print("lr_irq = {x}\n", .{_irq_handler_sp.*});
}

pub export fn undef_handler() void {
    uart.print("undef_hanlder\n", void);
}

pub export fn svc_handler() void {
    uart.print("svc_hanlder\n", void);
}

pub export fn pabort_handler() void {
    uart.print("_pabort_handler\n", void);
}

pub export fn dabort_handler() void {
    uart.print("_dabort_handler\n", void);
}

pub export fn fiq_handler() void {
    uart.print("_fiq_handler\n", void);
}

