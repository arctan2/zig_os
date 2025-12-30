const std = @import("std");
const fs = @import("fs.zig");
const Vnode = fs.Vnode;
const Dentry = fs.Dentry;
const uart = @import("uart");

pub const FileNode = struct {
    data: ?[]const u8 = null,
    children: std.StringHashMapUnmanaged(*FileNode) = .empty,

    inline fn init(allocator: std.mem.Allocator) !*FileNode {
        const f = try allocator.create(FileNode);
        f.* = .{};
        return f;
    }
};

root_dentry: *Dentry,
cur_inode_num_counter: usize,

const Self = @This();

pub fn getNextInodeNum(self: *Self) usize {
    self.cur_inode_num_counter += 1;
    return self.cur_inode_num_counter;
}

fn lookup(ptr: *anyopaque, allocator: std.mem.Allocator, parent: *Vnode, name: []const u8) !*Vnode {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const parent_file: *FileNode  = @ptrCast(@alignCast(parent.fs_data));
    
    if(parent_file.children.get(name)) |file| {
        const vnode = try allocator.create(Vnode);
        vnode.* = .{
            .fs_data = file,
            .dock_point_id = 0,
            .inode_num = self.getNextInodeNum(),
            .ref_count = 0,
        };
        return vnode;
    }

    return error.DoesNotExist;
}

fn create(_: *anyopaque, allocator: std.mem.Allocator, parent: *Vnode, name: []const u8) !void {
    const parent_file: *FileNode  = @ptrCast(@alignCast(parent.fs_data));
    if(parent_file.children.contains(name)) {
        return error.AlreadyExist;
    }
    const file = try FileNode.init(allocator);
    try parent_file.children.put(allocator, name, file);
}

fn destroy(_: *anyopaque, _: std.mem.Allocator, parent: *Vnode, name: []const u8) !void {
    const parent_file: *FileNode = @ptrCast(@alignCast(parent.fs_data));
    return if(parent_file.children.remove(name)) {} else error.DoesNotExist;
}

fn rename(_: *anyopaque, allocator: std.mem.Allocator, parent: *Vnode, old: []const u8, new: []const u8) !void {
    const parent_file: *FileNode = @ptrCast(@alignCast(parent.fs_data));
    if(parent_file.children.get(old)) |child| {
        _ = parent_file.children.remove(old);
        try parent_file.children.put(allocator, new, child);
    }
    return error.DoesNotExist;
}

fn getRootDentry(ptr: *anyopaque) *Dentry {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.root_dentry;
}

fn read(ptr: *anyopaque, vnode: *Vnode, offset: usize, buf: []u8) usize {
    const self: *Self = @ptrCast(@alignCast(ptr));
    _ = self;
    _ = vnode;
    _ = offset;
    _ = buf;
    return 0;
}

fn write(ptr: *anyopaque, vnode: *Vnode, offset: usize, buf: []const u8) usize {
    const self: *Self = @ptrCast(@alignCast(ptr));
    _ = self;
    _ = vnode;
    _ = offset;
    _ = buf;
    return 0;
}

pub const fs_ops: fs.FsOps = .{
    .i_ops = .{
        .lookup = lookup,
        .create = create,
        .destroy = destroy,
        .rename = rename
    },
    .f_ops = .{
        .read = read,
        .write = write
    },
    .getRootDentry = getRootDentry
};

pub fn init(allocator: std.mem.Allocator) !*Self {
    const root_dentry = try allocator.create(Dentry);
    const root_vnode = try allocator.create(Vnode);
    const ctx = try allocator.create(Self);
    
    ctx.* = .{
        .cur_inode_num_counter = 0,
        .root_dentry = root_dentry,
    };

    root_vnode.* = .{
        .fs_data = try FileNode.init(allocator),
        .dock_point_id = 0,
        .inode_num = ctx.getNextInodeNum(),
        .ref_count = 0,
    };

    root_dentry.* = .{
        .name = "/",
        .parent = null,
        .vnode = root_vnode,
        .ref_count = 0
    };

    return ctx;
}
