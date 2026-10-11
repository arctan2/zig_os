const std = @import("std");
const mm = @import("mm");
const uart = @import("uart");
const vfs = @import("vfs");
const binfmt = @import("binfmt");
const scheduler = @import("scheduler");

pub fn createElf(allocator: std.mem.Allocator, file_name: []const u8, kernel_l1: *mm.page_table.L1PageTable) !*scheduler.Task {
    const f = try vfs.open(allocator, file_name, .{ .read = 1 });
    defer vfs.close(allocator, f);

    var elf = try binfmt.elf.init(allocator, f);
    defer elf.deinit(allocator);

    const task = try scheduler.Task.allocTask(mm.kalloc, kernel_l1);
    try elf.loadPTLoads(allocator, &task.vma);

    _ = try task.vma.mmap(allocator, 0xbfffffff, 1024 * 64, .stack, null, 0);

    task.cpu_state = scheduler.idle_task.cpu_state;
    task.cpu_state.pc = elf.header.e_entry;
    task.priority = 30;

    return task;
}

