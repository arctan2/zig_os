const std = @import("std");
const uart = @import("uart");
const arm = @import("arm");
const mmio = @import("mmio");
const gicv2 = mmio.gicv2;
const scheduler = @import("scheduler");
const timers = @import("devices").timers;
const mm = @import("mm");
const vfs = @import("vfs");

pub export fn reset_handler() void {
    uart.print("reset_hanlder\n", void);
    while(true){}
}

pub export fn irq_handler(irq_sp: usize) usize {
    const irq_cpu_state: *scheduler.CpuState = @ptrFromInt(irq_sp);
    const ack = gicv2.C.ack();
    defer {
        timers.GenericTimer.setTval(10000);
        gicv2.C.endOfIntr(ack.intr_id);
    }

    switch(ack.intr_id) {
        30 => scheduler.tick(irq_cpu_state),
        else => {}
    }

    const sp: *scheduler.CpuState = @ptrFromInt(irq_cpu_state.sp - @sizeOf(scheduler.CpuState));
    sp.* = irq_cpu_state.*;
    return @intFromPtr(sp);
}

pub export fn undef_handler() void {
    const lr = arm.lr.read();
    const spsr = arm.spsr.read();
    uart.print("undef_handler\n", void);
    uart.print("lr = {x}, spsr = {b}\n", .{lr, spsr});
    while(true) {}
}

pub export fn svc_handler() void {
    uart.print("svc_hanlder\n", void);
    while(true) {}
}

pub export fn pabort_handler() void {
    const addr = arm.ifar.read();
    const cur_task = scheduler.global.current_task;
    var task_vma = &cur_task.vma;

    const vma = (task_vma.vma_rbtree.searchLessThanEq(addr) orelse return).value;
    if(addr >= vma.end()) return; // seg fault

    const file = vma.file orelse return;
    const page = mm.page_alloc.allocPages(1) catch @panic("memory full");
    const page_virt = mm.kglobal.physToVirtByKernelOffset(mm.page_alloc.pageToPhys(page));
    const page_buf: []u8 = @as([*]u8, @ptrFromInt(page_virt))[0..mm.page_alloc.PAGE_SIZE];

    @memset(page_buf, 0);

    const page_va = addr & ~(@as(usize, mm.page_alloc.PAGE_SIZE) - 1);
    const buf_off = if(vma.start > page_va) vma.start - page_va else 0;
    const f_off = vma.file_off + (page_va + buf_off - vma.start);

    const read = vfs.readAt(file, f_off, page_buf[buf_off..]) catch {
        mm.page_alloc.freeBlock(page);
        return;
    };

    if(read == 0) {
        mm.page_alloc.freeBlock(page);
        return;
    }

    task_vma.mapAddr(addr, mm.page_alloc.pageToPhys(page), .{ .type = .L2 }, .UserRO) catch @panic("mapAddr failed");

    return;
}

pub export fn dabort_handler() void {
    const addr = arm.dfar.read();
    const status = arm.dfsr.read();
    uart.print("d_addr = {x}, d_status = {b}\n", .{addr, status});
    while(true) {}
}

pub export fn fiq_handler() void {
    uart.print("_fiq_handler\n", void);
    while(true) {}
}

