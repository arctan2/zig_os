const uart = @import("uart");
const mm = @import("mm");
const fdt = @import("fdt");
const kglobal = mm.kglobal;
pub const gicv2 = @import("gicv2.zig");

const UART_BASE = kglobal.MMIO_BASE;
const GIC_BASE = kglobal.MMIO_BASE + mm.page_alloc.SECTION_SIZE;

pub fn init(kvmem: *mm.virt_mem_handler.VirtMemHandler, fdt_base: [*]const u8) void {
    try kvmem.kernelMapSection(UART_BASE, uart.getUartBase());
    uart.setBase(UART_BASE);

    initGicv2(kvmem, fdt_base);
}

fn initGicv2(kvmem: *mm.virt_mem_handler.VirtMemHandler, fdt_base: [*]const u8) void {
    const fdt_accessor = fdt.Accessor.init(fdt_base);

    const intr_ctl = fdt_accessor.findNodeWithProp(fdt_accessor.structs.base, "interrupt-controller") orelse {
        @panic("interrupt controller not found.\n");
    };

    const addr_size_cells = fdt_accessor.getAddrSizeCells(fdt_accessor.structs.base).?;

    const reg = fdt_accessor.getPropByName(intr_ctl, "reg") orelse {
        @panic("reg is not present in interrupt-controller\n");
    };

    const distr_start = fdt.readRegFromCells(addr_size_cells, reg.data, 0);
    const distr_size = fdt.readRegFromCells(addr_size_cells, reg.data, 1);
    const cpu_iface_start = fdt.readRegFromCells(addr_size_cells, reg.data, 2);

    try kvmem.kernelMapSection(GIC_BASE, @min(distr_start, cpu_iface_start));

    gicv2.D.setBase(GIC_BASE);
    gicv2.C.setBase(GIC_BASE + distr_size);
}
