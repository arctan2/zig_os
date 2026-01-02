const std = @import("std");
const fs = @import("fs.zig");
const uart = @import("uart");
const Ramfs = @import("ramfs.zig");
const cpio = @import("cpio.zig");

pub const fs_ops: fs.FsOps = Ramfs.fs_ops;

fn insertToRamfs(ramfs: *Ramfs, entry: *const cpio.Entry, filename: []const u8) void {
    var parts = std.mem.splitSequence(u8, filename, "/");
    var cur_parent: fs.Inode = .{
        .fs_data = ramfs.root_dentry.inode.?.fs_data,
        .dock_point = null,
        .ref_count = 0,
        .lock = .{},
        .lru_node = null
    };

    const mode_int = cpio.toU64(&entry.header.mode) catch return;
    const is_dir: u1 = if((mode_int & @as(u64, 0xF000)) == 0x4000) 1 else 0;

    while(parts.next()) |part| {
        if(parts.peek() == null) {
            Ramfs.fs_ops.i_ops.create(ramfs, &cur_parent, part, .{ .is_dir = is_dir, .w = 1, .x = 0 }) catch |e| switch (e) {
                error.OutOfMemory => @panic("out of memory."),
                else => {}
            };
        } else {
            Ramfs.fs_ops.i_ops.create(ramfs, &cur_parent, part, .{ .is_dir = 1, .w = 1, .x = 0 }) catch |e| switch (e) {
                error.OutOfMemory => @panic("out of memory."),
                else => {}
            };
        }
        const parent_file: *Ramfs.FileNode = @ptrCast(@alignCast(cur_parent.fs_data.ptr));
        cur_parent.fs_data.ptr = parent_file.children.get(part) orelse {
            @panic("something seriously went wrong with tmpfs implementation.");
        };
    }

    if(is_dir == 0) {
        const written = Ramfs.fs_ops.f_ops.write(ramfs, &cur_parent, 0, @constCast(entry.data)) catch @panic("cannot write");
        if(entry.data.len != written) {
            @panic("out of memory");
        }
    }
}

pub fn init(allocator: std.mem.Allocator, data: []const u8) !*Ramfs {
    const ramfs = try Ramfs.initManaged(allocator);
    var cpio_iter = cpio.CpioIterator.init(data);

    while(cpio_iter.nextEntry()) |entry| {
        const null_term_trimmed = entry.file_name[0..(entry.file_name.len - 1)];
        if(std.mem.eql(u8, null_term_trimmed, "TRAILER!!!")) break;
        insertToRamfs(ramfs, &entry, null_term_trimmed);
    }

    return ramfs;
}
