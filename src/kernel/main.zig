const std = @import("std");
const mm = @import("mm");
const kglobal = mm.kglobal;
const uart = @import("uart");
const arm = @import("arm");
const fdt = @import("fdt");
const utils = @import("utils");
const mmio = @import("mmio");
const devices = @import("devices");
pub const ih = @import("interrupt_handlers.zig");
pub const vt = @import("vector_table.zig");

pub export fn kernel_main(_: u32, _: u32, fdt_base: [*]const u8) linksection(".text") void {
    _ = ih.irq_handler;
    _ = vt._irq_handler;

    kglobal.VIRT_OFFSET = @intFromPtr(&kglobal._vkernel_end) - @intFromPtr(&kglobal._early_kernel_end);

    var kvmem = mm.virt_mem_handler.VirtMemHandler{
        .l1 = @ptrFromInt(arm.ttbr.read(1) + (@intFromPtr(&kglobal._vkernel_start) - @intFromPtr(&kglobal._early_kernel_end)))
    };
    uart.setBase(0x09000000);
    mmio.init(&kvmem, fdt_base);

    uart.print("{x}\n", .{@intFromPtr(kvmem.l1)});

    const mem = fdt.getMemStartSize(fdt_base);
    const kbounds = kglobal.KernelBounds.init(mem.start, mem.size);

    kbounds.print();

    mm.page_alloc.initGlobal(kbounds.free_region_start, kbounds.free_region_size, kglobal.VIRT_OFFSET);

    mm.mapFreePagesToKernelL1(&kbounds, &kvmem) catch {
        @panic("error in mapFreePagesToKernelL1");
    };

    try kvmem.kernelMapSection(kglobal.VECTOR_TABLE_BASE, @intFromPtr(&kglobal._early_kernel_end));
    // mm.unmapIdentityKernel(&kbounds, &kvmem);

    kvmem.l1.print();

    uart.print("yes\n", void);
    const fdt_accessor = fdt.Accessor.init(fdt_base);
    setupInterrupts(&fdt_accessor);
    enableInterrupts();
    while(true) {}
}

fn setupInterrupts(fdt_accessor: *const fdt.Accessor) void {
    arm.vbar.write(kglobal.VECTOR_TABLE_BASE);

    mmio.gicv2.D.init();
    mmio.gicv2.C.init();

    devices.timers.setup(fdt_accessor);
    arm.generic_timer.setTval(100000);
}

fn enableInterrupts() void {
    asm volatile("cpsie i");

    devices.timers.enable();

    arm.isr.read().print();

    uart.print("interrupts on\n", void);
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("panic: ");
    uart.puts(msg);
    while (true) {}
}
