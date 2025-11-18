const std = @import("std");
const uart = @import("uart");
const arm = @import("arm");
const mmio = @import("mmio");
const gicv2 = mmio.gicv2;
const utils = @import("utils");
const scheduler = @import("scheduler.zig");
const timers = @import("devices").timers;

pub export fn reset_handler() void {
    uart.print("reset_hanlder\n", void);
    while(true){}
}

pub export fn irq_handler(irq_sp: usize) usize {
    const irq_cpu_state: *scheduler.CpuState = @ptrFromInt(irq_sp);
    const ack = gicv2.C.ack();
    defer {
        timers.GenericTimer.setTval(10000);
        gicv2.C.endOfIntr(ack.intr_id);
    }

    switch(ack.intr_id) {
        30 => scheduler.tick(irq_cpu_state),
        else => {}
    }

    const sp: *scheduler.CpuState = @ptrFromInt(irq_cpu_state.sp - @sizeOf(scheduler.CpuState));
    sp.* = irq_cpu_state.*;
    return @intFromPtr(sp);
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

