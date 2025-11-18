const std = @import("std");
const uart = @import("uart");
const arm = @import("arm");
const mmio = @import("mmio");
const gicv2 = mmio.gicv2;
const utils = @import("utils");
const schedule = @import("schedule.zig");
const dispatch = @import("dispatch.zig");

pub export fn reset_handler() void {
    uart.print("reset_hanlder\n", void);
    while(true){}
}

pub export fn irq_handler(irq_sp: usize) usize {
    const irq_cpu_state: *dispatch.IrqCpuState = @ptrFromInt(irq_sp);
    const ack = gicv2.C.ack();
    // defer gicv2.C.endOfIntr(ack.intr_id);

    switch(ack.intr_id) {
        30 => {
            if(schedule.next()) |task| {
                // context switch to task
                if(task != dispatch.currentTask()) {
                    dispatch.switchTo(task, irq_cpu_state);
                }
            } else {
                uart.print("irq_cpu_state = {x}\n\n", .{irq_cpu_state.*});
                const sp: *dispatch.IrqCpuState = @ptrFromInt(irq_cpu_state.sp_of_intr_task - @sizeOf(dispatch.IrqCpuState));
                sp.* = irq_cpu_state.*;
                return @intFromPtr(sp);
            }
        },
        else => {
        }
    }

    // return irq_cpu_state.sp_of_intr_task;
    return 0;
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

