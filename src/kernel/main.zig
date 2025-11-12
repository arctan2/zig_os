const std = @import("std");
const mm = @import("mm");
const kglobal = mm.kglobal;
const uart = @import("uart");
const arm = @import("arm");
const fdt = @import("fdt");
const utils = @import("utils");
const mmio = @import("mmio");
const devices = @import("devices");
const gicv2 = mmio.gicv2;
const interrupts = @import("interrupts.zig");
pub const ih = @import("interrupt_handlers.zig");
pub const vt = @import("vector_table.zig");

pub const std_options: std.Options = .{
    .page_size_max = mm.page_alloc.PAGE_SIZE,
    .page_size_min = mm.page_alloc.PAGE_SIZE,
};

pub const os = struct {
    pub const heap = struct {
        pub const page_allocator = mm.kbacking_alloc.allocator;
    };
};

pub export fn kernel_main(_: u32, _: u32, fdt_base: [*]const u8) linksection(".text") noreturn {
    _ = ih.irq_handler;
    _ = vt._irq_handler;

    kglobal.VIRT_OFFSET = @intFromPtr(&kglobal._vkernel_end) - @intFromPtr(&kglobal._early_kernel_end);

    var kvmem = mm.vm_handler.VirtMemHandler{ .l1 = mm.page_table.physToL1Virt(arm.ttbr.read(1)) };
    uart.setBase(0x09000000);
    mmio.init(&kvmem, fdt_base);

    const mem = fdt.getMemStartSize(fdt_base);
    const kbounds = kglobal.KernelBounds.init(mem.start, mem.size);

    kbounds.print();

    mm.page_alloc.initGlobal(kbounds.free_region_start, kbounds.free_region_size, kglobal.VIRT_OFFSET);

    mm.mapFreePagesToKernelL1(&kbounds, &kvmem) catch {
        @panic("error in mapFreePagesToKernelL1");
    };

    kvmem.map(kglobal.VECTOR_TABLE_BASE, @intFromPtr(&kglobal._early_kernel_end), .{ .type = .Section }) catch unreachable;
    mm.unmapIdentityKernel(&kbounds, &kvmem);

    const fdt_accessor = fdt.Accessor.init(fdt_base);
    interrupts.setup(&fdt_accessor);
    interrupts.enable();

    while (true) {}
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("panic: ");
    uart.puts(msg);
    while (true) {}
}
