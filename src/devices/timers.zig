const arm = @import("arm");
const fdt = @import("fdt");
const uart = @import("uart");
const gicv2 = @import("mmio").gicv2;

pub const GenericTimer = arm.generic_timer;

pub fn setup(fdt_accessor: *const fdt.Accessor) void {
    const intr_id = GenericTimer.getIntrId(fdt_accessor);
    gicv2.D.setPriority(intr_id, 0);
    gicv2.D.configure(intr_id, .Level);
    gicv2.D.enableIrq(intr_id);

    uart.print("intr_id = {}\n", .{@as(usize, intr_id)});
}

pub fn enable() void {
    GenericTimer.enable();
}
