const std = @import("std");
const mm = @import("mm");
const kglobal = mm.kglobal;
const uart = @import("uart");
const arm = @import("arm");
const fdt = @import("fdt");
const utils = @import("utils");
const mmio = @import("mmio");
const devices = @import("devices");
const interrupts = @import("interrupts.zig");
const scheduler = @import("scheduler.zig");
const syscall = @import("syscall");
const vfs = @import("vfs");
const fs = @import("fs");
pub const ih = @import("interrupt_handlers.zig");

pub const std_options: std.Options = .{
    .page_size_max = mm.page_alloc.PAGE_SIZE,
    .page_size_min = mm.page_alloc.PAGE_SIZE,
};

pub const os = struct {
    pub const heap = struct {
        pub const page_allocator = mm.kbacking_alloc.allocator;
    };
};

fn initProcess() void {
    vfs.mkdir(mm.kalloc, "/initramfs/bin/cool_bins") catch @panic("cannot mkdir cool_bins");

    const f = vfs.open(mm.kalloc, "/initramfs/bin/cool_bins/init", .{.create = 1, .write = 1}) catch {
        @panic("init not found.");
    };
    defer vfs.close(mm.kalloc, f);
    {
        const stat = vfs.stat(f) catch @panic("invalid file");
        uart.print("stat = {c}\n", .{stat});
    }

    const written = vfs.write(f, "cool af data") catch @panic("error while writing to file");
    uart.print("written = {}\n", .{written});

    f.offset = 0;

    {
        const stat = vfs.stat(f) catch @panic("invalid file");
        uart.print("stat = {c}\n", .{stat});
    }

    const written_again = vfs.write(f, "cool af data more more more more more more more data not a factor of 8") catch {
        @panic("error while writing to file");
    };
    uart.print("written_again = {}\n", .{written_again});

    f.offset = 0;

    while(true) {
        var buf = [_]u8{0} ** 8;
        const read = vfs.read(f, &buf) catch |e| switch(e) {
            error.EOF => break,
            else => @panic("error while writing to file")
        };
        uart.print("read = {}\n", .{read});
        uart.print("buf = {c}\n", .{buf});
    }

    vfs.rename(mm.kalloc, f, "a") catch |e| {
        uart.print("{}\n", .{e});
        switch(e) {
            error.OutOfMemory => @panic("outof mem"),
            error.DoesNotExist => @panic("no exist"),
            error.AlreadyExist => @panic("already exist"),
            else => @panic("rename failed")
        }
    };
    {
        const stat = vfs.stat(f) catch @panic("invalid file");
        uart.print("stat = {c}\n", .{stat});
    }
}

pub export fn kernel_main(_: u32, _: u32, fdt_base: [*]const u8) linksection(".text") void {
    _ = ih.irq_handler;

    kglobal.VIRT_OFFSET = @intFromPtr(&kglobal._vkernel_end) - @intFromPtr(&kglobal._early_kernel_end);

    var kvmem = mm.vma.Vma{ .l1 = mm.page_table.physToL1Virt(arm.ttbr.read(1)) };
    uart.setBase(0x09000000);
    mmio.init(&kvmem, fdt_base);

    const mem = fdt.getMemStartSize(fdt_base);
    const kbounds = kglobal.KernelBounds.init(mem.start, mem.size);
    kbounds.print();
    mm.mapFreePagesToKernelL1(&kbounds, &kvmem) catch @panic("error in mapFreePagesToKernelL1");
    kvmem.map(kglobal.VECTOR_TABLE_BASE, @intFromPtr(&kglobal._early_kernel_end), .{ .type = .Section }) catch unreachable;
    mm.unmapIdentityKernel(&kbounds, &kvmem);

    const initramfs_img = kglobal.getInitRamfs(&kbounds);
    
    mm.page_alloc.initGlobal(kbounds.free_region_start, kbounds.free_region_size, kglobal.VIRT_OFFSET);
    initStacks();

    scheduler.init(kvmem);

    vfs.init(mm.kalloc) catch @panic("out of mem");
    const initramfs_ctx = fs.InitRamFs.init(mm.kalloc, initramfs_img) catch @panic("out of mem");
    vfs.dock(mm.kalloc, "initramfs", fs.InitRamFs.fs_ops, initramfs_ctx, .Ram) catch {
        @panic("fs already exists on that name. Unmount it first.");
    };

    initProcess();

    // var cool_task = scheduler.Task.allocTask(mm.kalloc) catch @panic("out of memory");
    // var another_task = scheduler.Task.allocTask(mm.kalloc) catch @panic("out of memory");

    // cool_task.cpu_state = scheduler.idle_task.cpu_state;
    // cool_task.cpu_state.pc = @intFromPtr(&coolTask);
    // cool_task.priority = 30;
    // cool_task.cpu_state.sp = @intFromPtr((mm.kalloc.alloc(u8, 4096) catch @panic("out of memory")).ptr);

    // another_task.cpu_state = scheduler.idle_task.cpu_state;
    // another_task.cpu_state.pc = @intFromPtr(&lame_task);
    // another_task.priority = 30;
    // another_task.cpu_state.sp = @intFromPtr((mm.kalloc.alloc(u8, 4096) catch @panic("out of memory")).ptr);

    // scheduler.add(another_task);
    // scheduler.add(cool_task);

    const fdt_accessor = fdt.Accessor.init(fdt_base);
    interrupts.setup(&fdt_accessor);
    devices.timers.enable(&fdt_accessor);
    interrupts.enable();
    asm volatile("cps #0x10");
    scheduler.idle();
}

fn coolTask() void {
    var sum: usize = 0;
    for(0..10_000) |i| {
        sum += i;
    }
    uart.print("cool_task = {}\n", .{sum});
    while (true) {
        asm volatile("wfi");
    }
}

fn lame_task() void {
    var sum: usize = 0;
    for(0..10_000) |i| {
        sum += i;
    }
    uart.print("lame_task = {}\n", .{sum});
    while (true) {
        asm volatile("wfi");
    }
}

fn initStacks() void {
    const sys_stack = @intFromPtr(&kglobal._sys_stack_top);
    const irq_stack = @intFromPtr(&kglobal._irq_stack_top);
    asm volatile(
        \\ cps #0x12
        \\ mov sp, %[irq_stack]
        \\ cps #0x1f
        \\ mov sp, %[sys_stack]
        \\ cps #0x13
        :
        : [sys_stack] "r" (sys_stack), [irq_stack] "r" (irq_stack)
    );
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.puts("panic: ");
    uart.puts(msg);
    uart.puts("\n");
    while (true) {}
}
