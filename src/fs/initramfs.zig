const std = @import("std");
const fs = @import("fs.zig");
const Vnode = fs.Vnode;
const Dentry = fs.Dentry;
const uart = @import("uart");
const Ramfs = @import("ramfs.zig");
const cpio = @import("cpio.zig");

pub const fs_ops: fs.FsOps = Ramfs.fs_ops;

fn insertToRamfs(ramfs: *Ramfs, entry: *const cpio.Entry, filename: []const u8) void {
    var parts = std.mem.splitSequence(u8, filename, "/");
    var cur_parent: Vnode = .{
        .fs_data = ramfs.root_dentry.vnode.?.fs_data,
        .dock_point_id = 0,
        .inode_num = 0,
        .ref_count = 0,
    };

    while(parts.next()) |part| {
        Ramfs.fs_ops.i_ops.create(ramfs, &cur_parent, part) catch |e| switch (e) {
            error.OutOfMemory => @panic("out of memory."),
            else => {}
        };
        const parent_file: *Ramfs.FileNode = @ptrCast(@alignCast(cur_parent.fs_data));
        cur_parent.fs_data = parent_file.children.get(part) orelse {
            @panic("something seriously went wrong with tmpfs implementation.");
        };
    }

    if(entry.data.len != Ramfs.fs_ops.f_ops.write(ramfs, &cur_parent, 0, @constCast(entry.data))) {
        @panic("out of memory");
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
