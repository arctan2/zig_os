const mm = @import("mm");
const uart = @import("uart");
const kernel_global = @import("mm").kernel_global;
const arm = @import("arm");
const _ = @import("interrupt_handlers.zig");

pub fn initVirtKernel(mem_start: usize, mem_size: usize) !noreturn {
    try mm.initMMUHigherHalfKernel(mem_start, mem_size, &higherHalfMain);
}

fn higherHalfMain() void {
    enableInterrupts();
}

pub fn enableInterrupts() void {
    var sctlr = arm.sctlr.read();
    sctlr.V = 1;
    arm.sctlr.write(sctlr);

    uart.print("enabled intruupt\n", void);
}

