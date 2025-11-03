const uart = @import("uart");
const mm = @import("mm");
const fdt = @import("fdt");
const kglobal = mm.kglobal;
pub const gicv2 = @import("gicv2.zig");

const UART_BASE = kglobal.MMIO_BASE;
const GIC_BASE = kglobal.MMIO_BASE + mm.page_alloc.SECTION_SIZE;

pub fn initVirtMapping(_: *mm.virt_mem_handler.VirtMemHandler, _: [*]const u8) void {
    // const fdt_accessor = fdt.Accessor.init(fdt_base);

    // const intr_ctl = fdt_accessor.findNodeWithProp(fdt_accessor.structs.base, "interrupt-controller") orelse {
    //     @panic("interrupt controller not found.\n");
    // };

    // const addr_size_cells = fdt_accessor.getAddrSizeCells(fdt_accessor.structs.base).?;

    // const reg = fdt_accessor.getPropByName(intr_ctl, "reg") orelse {
    //     @panic("reg is not present in interrupt-controller\n");
    // };

    // const distr_start = fdt.readRegFromCells(addr_size_cells, reg.data, 0);
    // const distr_size = fdt.readRegFromCells(addr_size_cells, reg.data, 1);
    // const cpu_iface_start = fdt.readRegFromCells(addr_size_cells, reg.data, 2);

    // try kernel_virt_mem.kernelMapSection(GIC_BASE, @min(distr_start, cpu_iface_start));
    // try kernel_virt_mem.kernelMapSection(UART_BASE, uart.getUartBase());

    // gicv2.D.setBase(GIC_BASE);
    // gicv2.C.setBase(GIC_BASE + distr_size);

    uart.setBase(UART_BASE);
}
