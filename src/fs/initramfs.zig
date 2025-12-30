const std = @import("std");
const fs = @import("fs.zig");
const Vnode = fs.Vnode;
const Dentry = fs.Dentry;
const uart = @import("uart");
const Tmpfs = @import("tmpfs.zig");
const cpio = @import("cpio.zig");

pub const fs_ops: fs.FsOps = Tmpfs.fs_ops;

fn insertToTmpfs(tmpfs: *Tmpfs, allocator: std.mem.Allocator, _: *const cpio.Entry, filename: []const u8) void {
    var parts = std.mem.splitSequence(u8, filename, "/");
    var cur_parent: Vnode = .{
        .fs_data = tmpfs.root_dentry.vnode.?.fs_data,
        .dock_point_id = 0,
        .inode_num = 0,
        .ref_count = 0,
    };

    while(parts.next()) |part| {
        Tmpfs.fs_ops.i_ops.create(tmpfs, allocator, &cur_parent, part) catch |e| switch (e) {
            error.OutOfMemory => @panic("out of memory."),
            else => {}
        };
        const parent_file: *Tmpfs.FileNode = @ptrCast(@alignCast(cur_parent.fs_data));
        cur_parent.fs_data = parent_file.children.get(part) orelse {
            @panic("something seriously went wrong with tmpfs implementation.");
        };
    }
}

pub fn init(allocator: std.mem.Allocator, data: []const u8) !*Tmpfs {
    const tmpfs = try Tmpfs.init(allocator);
    var cpio_iter = cpio.CpioIterator.init(data);

    while(cpio_iter.nextEntry()) |entry| {
        const null_term_trimmed = entry.file_name[0..(entry.file_name.len - 1)];
        if(std.mem.eql(u8, null_term_trimmed, "TRAILER!!!")) break;
        insertToTmpfs(tmpfs, allocator, &entry, null_term_trimmed);
    }

    return tmpfs;
}
