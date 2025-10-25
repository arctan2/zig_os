const std = @import("std");
const uart = @import("uart");
const arm = @import("arm");

export fn reset_handler() void {
    uart.print("reset_hanlder\n", void);
}

export fn irq_handler() void {
    uart.print("reset_hanlder\n", void);
}

export fn undef_handler() void {
    uart.print("undef_hanlder\n", void);
}

export fn svc_handler() void {
    uart.print("svc_hanlder\n", void);
}

export fn pabort_handler() void {
    uart.print("_pabort_handler\n", void);
}

export fn dabort_handler() void {
    uart.print("_dabort_handler\n", void);
}

export fn fiq_handler() void {
    uart.print("_fiq_handler\n", void);
}

