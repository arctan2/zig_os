const uart = @import("uart");
const std = @import("std");
const mm = @import("mm");
// const mmio = @import("mmio");
const arm = @import("arm");

extern const KERNEL_OFFSET: u8;
extern const KERNEL_OFFSET_FROM_BOOT_END: u8;
extern const PHYS_BASE: u8;
extern const VIRT_BASE: u8;
extern const boot_end_phys: u8;
extern const _kernel_end: u8;
extern const _kernel_start: u8;
extern const _stack_top: u8;
extern const kernel_l1_page_table: u8;

fn kernelMapSection(kmem: *mm.virt_mem_handler.VirtMemHandler, virt: usize, phys: usize) linksection(".text.boot") void {
    const virt_addr: mm.virt_mem_handler.VirtAddress = @bitCast(virt);
    const l1_idx = virt_addr.l1_idx;
    const entry: *mm.page_table.SectionEntry = @ptrCast(&kmem.l1.entries[l1_idx]);
    entry.section_addr = @intCast(phys >> 20);
    entry.type = .Section;
}

export fn early_kernel_main(_: u32, _: u32, fdt_base: [*]const u8) linksection(".text.boot") void {
    var kmem = mm.virt_mem_handler.VirtMemHandler{ .l1 = @ptrFromInt(@intFromPtr(&kernel_l1_page_table)) };

    var i: usize = 0;
    while(i < kmem.l1.entries.len) : (i += 1) {
        kmem.l1.entries[i] = 0;
    }

    i = 0;
    while(i < 6) {
        const virt = @intFromPtr(&VIRT_BASE) + (0x10_0000 * i);
        const phys = @intFromPtr(&boot_end_phys) + (0x10_0000 * i);
        const ident = @intFromPtr(&PHYS_BASE) + (0x10_0000 * i);
        kernelMapSection(&kmem, ident, ident);
        kernelMapSection(&kmem, virt, phys);
        i += 1;
    }

    arm.enableMMU(@intFromPtr(kmem.l1));

    const fdt_virt = @intFromPtr(fdt_base) + @intFromPtr(&KERNEL_OFFSET);
    kernelMapSection(&kmem, fdt_virt, @intFromPtr(fdt_base));

    asm volatile(
        \\bl jump_to_kernel_main
        :
        : [fdt] "{r0}" (@intFromPtr(fdt_base) + @intFromPtr(&KERNEL_OFFSET)),
        [stack_top] "{r1}" (@intFromPtr(&_stack_top)),
        [entry] "{r2}" (@intFromPtr(&kernel_main))
        : .{ .r3 = true, .memory = true }
    );

    unreachable;
}

export fn kernel_main(_: u32, _: u32, fdt_base: [*]const u8) linksection(".text") void {
    const a = &fdt_base;

    _ = a;

    // virt_kernel.initVirtKernel(fdt_base) catch {
    //     @panic("error init virt kernel");
    // };

    const j = 20;

    const k = j + 20;
    _ = k;
    // mmio.initVirtMapping(&kmem, fdt_base);
    // uart.setBase(0x09000000);
    // uart.print("brother we cooking\n", void);
    while (true) {}
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("panic: ");
    uart.puts(msg);
    while (true) {}
}
