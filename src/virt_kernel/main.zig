const std = @import("std");
const mm = @import("mm");
const kglobal = mm.kglobal;
const uart = @import("uart");
const arm = @import("arm");
const fdt = @import("fdt");
const utils = @import("utils");
const mmio = @import("mmio");
const devices = @import("devices");
const ih = @import("interrupt_handlers.zig");
const vt = @import("vector_table.zig");

pub fn initVirtKernel(fdt_base: [*]const u8) !noreturn {
    const mem = fdt.getMemStartSize(fdt_base);
    const kernel_bounds = kglobal.KernelBounds.init(mem.start, mem.size);

    kernel_bounds.print();

    mm.page_alloc.initGlobal(kernel_bounds.free_region_start, kernel_bounds.free_region_size);
    var kernel_virt_mem = try mm.virt_mem_handler.VirtMemHandler.init();

    try mm.identityMapKernel(&kernel_bounds, &kernel_virt_mem);
    try mm.mapToHigherAddress(&kernel_bounds, fdt_base, &kernel_virt_mem);
    mmio.initVirtMapping(&kernel_virt_mem, fdt_base);
    mm.transitionToHigherHalf(&kernel_bounds, &kernel_virt_mem, &higherHalfMain, fdt_base);
}

fn higherHalfMain(fdt_base: [*]const u8) void {
    // force zig to actually include the files
    // removing this is causing the vector tables to not exist in
    // the compiled binary currently
    _ = ih.irq_handler;
    _ = vt._irq_handler;
    uart.print("global_page_alloc = {x}\n", .{@intFromPtr(mm.page_alloc.global_page_alloc)});

    const mem = fdt.getMemStartSize(fdt_base);
    const kernel_bounds = kglobal.KernelBounds.init(mem.start, mem.size);
    const fdt_accessor = fdt.Accessor.init(fdt_base);
    setupInterrupts(&fdt_accessor);
    removeIdentityKernelMap(&kernel_bounds);
    enableInterrupts();
    while(true) {}
}

fn removeIdentityKernelMap(kernel_bounds: *const kglobal.KernelBounds) void {
    const l1: *mm.page_table.L1PageTable = @ptrFromInt(kglobal.physToVirt(arm.ttbr.read(1)));
    var virt_t = mm.virt_mem_handler.VirtMemHandler{.l1 = l1};

    for(0..4) |i| {
        const addr = kernel_bounds.kstart + (mm.page_alloc.SECTION_SIZE * i);
        virt_t.kernelUnmapSection(addr);
    }
}

fn setupInterrupts(fdt_accessor: *const fdt.Accessor) void {
    arm.vbar.write(kglobal.VECTOR_TABLE_BASE);

    mmio.gicv2.D.init();
    mmio.gicv2.C.init();

    devices.timers.setup(fdt_accessor);
    arm.generic_timer.setTval(arm.generic_timer.cntfrq);
}

fn enableInterrupts() void {
    asm volatile("cpsie i");

    devices.timers.enable();

    arm.isr.read().print();

    uart.print("interrupts on\n", void);
}

