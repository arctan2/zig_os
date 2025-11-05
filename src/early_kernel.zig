const std = @import("std");
const mm = @import("mm");
const kglobal = mm.kglobal;
const arm = @import("arm");
const kernel = @import("kernel");

const VirtAddressEarly = packed struct(u32) {
    offset: u12,
    l2_idx: u8,
    l1_idx: u12,
};

const SectionEntryEarly = packed struct(usize) {
    type: enum(u2) {
        Fault = 0b00,
        L2TablePtr = 0b01,
        Section = 0b10
    },
    b: u1,
    c: u1,
    xn: u1,
    domain: u4,
    p: u1,
    ap: u2,
    tex: u3,
    apx: u1,
    s: u1,
    nG: u1,
    zero: u1,
    sbz: u1,
    section_addr: u12,
};

const VirtMemHandlerEarly = struct {
    l1: *struct { entries: [4096]usize }
};

fn kernelMapSection(kmem: *VirtMemHandlerEarly, virt: usize, phys: usize) linksection(".text.boot") void {
    const virt_addr: VirtAddressEarly = @bitCast(virt);
    const l1_idx = virt_addr.l1_idx;
    const entry: *SectionEntryEarly = @ptrCast(&kmem.l1.entries[l1_idx]);
    entry.section_addr = @intCast(phys >> 20);
    entry.type = .Section;
}

export fn early_kernel_main(_: u32, _: u32, fdt_base: [*]const u8) linksection(".text.boot") void {
    var kmem = VirtMemHandlerEarly{ .l1 = @ptrFromInt(@intFromPtr(&kglobal._kernel_l1_page_table_phys)) };

    for(0..kmem.l1.entries.len) |i| {
        kmem.l1.entries[i] = 0;
    }

    for(0..3) |i| {
        const virt = @intFromPtr(&kglobal.VIRT_BASE) + (mm.page_alloc.SECTION_SIZE * i);
        const phys = @intFromPtr(&kglobal._early_kernel_end) + (mm.page_alloc.SECTION_SIZE * i);
        const ident = @intFromPtr(&kglobal.PHYS_BASE) + (mm.page_alloc.SECTION_SIZE * i);
        kernelMapSection(&kmem, ident, ident);
        kernelMapSection(&kmem, virt, phys);
    }

    kernelMapSection(&kmem, @intFromPtr(&kglobal.VIRT_BASE) - mm.page_alloc.SECTION_SIZE, @intFromPtr(&kglobal.PHYS_BASE));

    arm.enableMMU(@intFromPtr(kmem.l1));

    const fdt_virt = @intFromPtr(fdt_base) + @intFromPtr(&kglobal.KERNEL_OFFSET);
    kernelMapSection(&kmem, fdt_virt, @intFromPtr(fdt_base));

    asm volatile(
        \\bl jump_to_kernel_main
        :
        : [fdt] "{r0}" (fdt_virt),
        [stack_top] "{r1}" (@intFromPtr(&kglobal._vstack_top)),
        [entry] "{r2}" (@intFromPtr(&kernel.kernel_main))
        : .{ .r0 = true, .r1 = true, .r2 = true, .memory = true }
    );

    unreachable;
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = msg;
    while (true) {}
}
