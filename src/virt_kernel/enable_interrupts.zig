const arm = @import("arm");
const fdt = @import("fdt");
const uart = @import("uart");

pub fn timer(fdt_accessor: *const fdt.Accessor) void {
    const timer_node = fdt_accessor.findNode(fdt_accessor.structs.base, "timer") orelse {
        @panic("timer not found\n");
    };
    const interrupts_prop = fdt_accessor.getPropByName(timer_node, "interrupts") orelse {
        @panic("interrupts_prop not present in timer\n");
    };

    const interrupt = fdt.readInterruptProp(interrupts_prop.data, 1);

    uart.print("{x} {x} {x}\n", .{interrupt.intr_type, interrupt.irq_number, interrupt.flags});
}
