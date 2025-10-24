const mm = @import("mm");
const uart = @import("uart");
const kernel_global = @import("mm").kernel_global;
const interrupts = @import("interrupts.zig");

pub fn initVirtKernel(mem_start: usize, mem_size: usize) !noreturn {
    try mm.initMMUHigherHalfKernel(mem_start, mem_size, &higherHalfMain);
}

fn higherHalfMain() void {
    interrupts.enableInterrupts();
}
