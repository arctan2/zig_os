const uart = @import("uart");
const mm = @import("mm");
const fdt = @import("fdt");

pub const MMIOMapper = struct {
    cur_addr: usize = mm.kernel_global.MMIO_BASE,

    pub fn nextAddr(self: *MMIOMapper) usize {
        const addr = self.cur_addr;
        self.cur_addr += mm.page_alloc.SECTION_SIZE;
        return addr;
    }
};

pub fn initVirtMapping(kernel_virt_mem: *mm.virt_mem_handler.VirtMemHandler, fdt_base: [*]const u8) void {
    const fdt_accessor = fdt.Accessor.init(fdt_base);
    var mmio_mapper = MMIOMapper{};

    const newUartBase = mmio_mapper.nextAddr() + uart.getUartBase();
    try kernel_virt_mem.kernelMapSection(newUartBase, uart.getUartBase());

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
    const cpu_iface_size = fdt.readRegFromCells(addr_size_cells, reg.data, 3);

    uart.print("{x}, {x}, {x}, {x}\n", .{distr_start, distr_size, cpu_iface_start, cpu_iface_size});

    uart.setUartBase(newUartBase);
}
