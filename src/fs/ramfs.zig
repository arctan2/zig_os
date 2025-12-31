const std = @import("std");
const fs = @import("fs.zig");
const Vnode = fs.Vnode;
const Dentry = fs.Dentry;
const uart = @import("uart");

pub const FileNode = struct {
    data: ?[]u8 = null,
    children: std.StringHashMapUnmanaged(*FileNode) = .empty,

    inline fn init(allocator: std.mem.Allocator) !*FileNode {
        const f = try allocator.create(FileNode);
        f.* = .{};
        return f;
    }
};

root_dentry: *Dentry,
cur_inode_num_counter: usize,
allocator: std.mem.Allocator,

const Self = @This();

pub fn getNextInodeNum(self: *Self) usize {
    self.cur_inode_num_counter += 1;
    return self.cur_inode_num_counter;
}

fn lookup(ptr: *anyopaque, parent: *Vnode, name: []const u8) !*Vnode {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const parent_file: *FileNode  = @ptrCast(@alignCast(parent.fs_data));
    
    if(parent_file.children.get(name)) |file| {
        const vnode = try self.allocator.create(Vnode);
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

fn create(ptr: *anyopaque, parent: *Vnode, name: []const u8) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const parent_file: *FileNode  = @ptrCast(@alignCast(parent.fs_data));
    if(parent_file.children.contains(name)) {
        return error.AlreadyExist;
    }
    const file = try FileNode.init(self.allocator);
    try parent_file.children.put(self.allocator, name, file);
}

fn destroy(_: *anyopaque, parent: *Vnode, name: []const u8) !void {
    const parent_file: *FileNode = @ptrCast(@alignCast(parent.fs_data));
    return if(parent_file.children.remove(name)) {} else error.DoesNotExist;
}

fn resize(ptr: *anyopaque, vnode: *Vnode, len: usize) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const file: *FileNode = @ptrCast(@alignCast(vnode.fs_data));
    if(file.data) |data| {
        file.data = try self.allocator.realloc(data, len);
    } else {
        file.data = try self.allocator.alloc(u8, len);
    }
}

fn rename(ptr: *anyopaque, parent: *Vnode, old: []const u8, new: []const u8) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const parent_file: *FileNode = @ptrCast(@alignCast(parent.fs_data));
    if(parent_file.children.get(old)) |child| {
        _ = parent_file.children.remove(old);
        try parent_file.children.put(self.allocator, new, child);
    }
    return error.DoesNotExist;
}

fn getRootDentry(ptr: *anyopaque) *Dentry {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.root_dentry;
}

fn read(_: *anyopaque, vnode: *Vnode, offset: usize, buf: []u8) usize {
    const file: *FileNode = @ptrCast(@alignCast(vnode.fs_data));
    if(file.data) |data| {
        const end = @min(offset + buf.len, data.len);
        const count = end - offset;
        @memcpy(buf, data[offset..end]);
        return count;
    }
    return 0;
}

fn write(ptr: *anyopaque, vnode: *Vnode, offset: usize, buf: []const u8) usize {
    const file: *FileNode = @ptrCast(@alignCast(vnode.fs_data));
    const end = offset + buf.len;
    const count = end - offset;

    if(file.data) |data| {
        if(end > data.len) {
            resize(ptr, vnode, end) catch return 0;
        }
    } else {
        resize(ptr, vnode, end) catch return 0;
    }
    @memcpy(file.data.?[offset..end], buf);
    return count;
}

fn deinit(ptr: *anyopaque) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const root_vnode = self.root_dentry.vnode orelse return;
    var stack = try std.ArrayList(*FileNode).initCapacity(self.allocator, 32);
    defer stack.deinit(self.allocator);

    const root_file: *FileNode = @ptrCast(@alignCast(root_vnode.fs_data));

    try stack.append(self.allocator, root_file);

    while(stack.pop()) |f| {
        var iter = f.children.valueIterator();
        while(iter.next()) |val| try stack.append(self.allocator, val.*);
        if(f.data) |data| self.allocator.free(data);
        self.allocator.destroy(f);
    }
}

pub const fs_ops: fs.FsOps = .{
    .i_ops = .{
        .lookup = lookup,
        .create = create,
        .destroy = destroy,
        .resize = resize,
        .rename = rename
    },
    .f_ops = .{
        .read = read,
        .write = write
    },
    .getRootDentry = getRootDentry,
    .deinit = deinit
};

pub fn initManaged(allocator: std.mem.Allocator) !*Self {
    const root_dentry = try allocator.create(Dentry);
    const root_vnode = try allocator.create(Vnode);
    const self = try allocator.create(Self);
    
    self.* = .{
        .cur_inode_num_counter = 0,
        .root_dentry = root_dentry,
        .allocator = allocator
    };

    root_vnode.* = .{
        .fs_data = try FileNode.init(allocator),
        .dock_point_id = 0,
        .inode_num = self.getNextInodeNum(),
        .ref_count = 0,
    };

    root_dentry.* = .{
        .name = "/",
        .parent = null,
        .vnode = root_vnode,
        .ref_count = 0
    };

    return self;
}

