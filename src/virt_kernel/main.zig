const std = @import("std");
const mm = @import("mm");
const uart = @import("uart");
const kernel_global = @import("mm").kernel_global;
const arm = @import("arm");
const fdt = @import("fdt");
const utils = @import("utils");
const mmio = @import("mmio");
const _ = @import("interrupt_handlers.zig");

pub fn initVirtKernel(mem_start: usize, mem_size: usize, fdt_base: [*]const u8) !noreturn {
    const kernel_bounds = kernel_global.KernelBounds.init(mem_start, mem_size);

    mm.page_alloc.initGlobal(kernel_bounds.free_region_start, kernel_bounds.free_region_size);
    var kernel_virt_mem = try mm.virt_mem_handler.VirtMemHandler.init();

    try mm.identityMapKernel(&kernel_bounds, fdt_base, &kernel_virt_mem);
    mmio.initVirtMapping(&kernel_virt_mem, fdt_base);
    mm.transitionToHigherHalf(&kernel_bounds, &kernel_virt_mem, &higherHalfMain, fdt_base);
}

fn higherHalfMain(fdt_base_phys: [*]const u8) void {
    const fdt_base_virt: [*]const u8 = @ptrFromInt(kernel_global.physToVirt(@intFromPtr(fdt_base_phys)));
    var fdt_accessor = fdt.Accessor.init(fdt_base_virt);

    const intr_ctl = fdt_accessor.findNodeWithProp(fdt_accessor.structs.base, "interrupt-controller") orelse {
        @panic("interrupt controller not found.\n");
    };

    const sizeAddrCells = fdt_accessor.getAddrSizeCells(fdt_accessor.structs.base) orelse {
        @panic("size addr cells of root node is not present\n");
    };

    const reg = fdt_accessor.getPropByName(intr_ctl, "reg") orelse {
        @panic("reg is not present in interrupt-controller\n");
    };

    const distr_start = fdt.readRegFromCells(sizeAddrCells, reg.data, 0);
    const distr_size = fdt.readRegFromCells(sizeAddrCells, reg.data, 1);
    const cpu_iface_start = fdt.readRegFromCells(sizeAddrCells, reg.data, 2);
    const cpu_iface_size = fdt.readRegFromCells(sizeAddrCells, reg.data, 3);

    uart.print("distr = {x} {x}, cpu_iface = {x} {x}\n", .{distr_start, distr_size, cpu_iface_start, cpu_iface_size});

    enableInterrupts();
}

pub fn enableInterrupts() void {
    var sctlr = arm.sctlr.read();
    sctlr.V = 1;
    arm.sctlr.write(sctlr);
    uart.print("enabled interrupt\n", void);
}

