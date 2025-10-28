const std = @import("std");
const mm = @import("mm");
const uart = @import("uart");
const kernel_global = @import("mm").kernel_global;
const arm = @import("arm");
const fdt = @import("fdt");
const utils = @import("utils");
const mmio = @import("mmio");
const enable_interrupts = @import("enable_interrupts.zig");
const _ = @import("interrupt_handlers.zig");

pub fn initVirtKernel(mem_start: usize, mem_size: usize, fdt_base: [*]const u8) !noreturn {
    const kernel_bounds = kernel_global.KernelBounds.init(mem_start, mem_size);

    mm.page_alloc.initGlobal(kernel_bounds.free_region_start, kernel_bounds.free_region_size);
    var kernel_virt_mem = try mm.virt_mem_handler.VirtMemHandler.init();

    try mm.identityMapKernel(&kernel_bounds, &kernel_virt_mem);
    try mm.mapToHigherAddress(&kernel_bounds, fdt_base, &kernel_virt_mem);
    mmio.initVirtMapping(&kernel_virt_mem, fdt_base);
    mm.transitionToHigherHalf(&kernel_bounds, &kernel_virt_mem, &higherHalfMain, fdt_base);
}

fn higherHalfMain(fdt_base: [*]const u8) void {
    const fdt_accessor = fdt.Accessor.init(fdt_base);
    enableInterrupts(&fdt_accessor);
    enableTimers();
}

fn enableInterrupts(fdt_accessor: *const fdt.Accessor) void {
    var sctlr = arm.sctlr.read();
    sctlr.V = 1;
    arm.sctlr.write(sctlr);

    mmio.gic.C.init();
    mmio.gic.D.init();

    enable_interrupts.timer(fdt_accessor);
}

fn enableTimers() void {
    arm.el1_timer.init();
    arm.el1_timer.setTval(625000);
}

