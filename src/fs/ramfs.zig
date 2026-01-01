const std = @import("std");
const fs = @import("fs.zig");
const uart = @import("uart");

pub const FileNode = struct {
    data: ?[]u8 = null,
    inode_num: usize,
    children: std.StringHashMapUnmanaged(*FileNode) = .empty,

    inline fn init(allocator: std.mem.Allocator, inode_num: usize) !*FileNode {
        const f = try allocator.create(FileNode);
        f.* = .{ .inode_num = inode_num };
        return f;
    }
};

root_dentry: fs.Dentry,
cur_inode_num_counter: usize,
allocator: std.mem.Allocator,

const Self = @This();

pub fn getNextInodeNum(self: *Self) usize {
    self.cur_inode_num_counter += 1;
    return self.cur_inode_num_counter;
}

fn lookup(_: *anyopaque, parent: *fs.Inode, name: []const u8) !fs.FsData {
    const parent_file: *FileNode = @ptrCast(@alignCast(parent.fs_data.ptr));

    if(parent_file.children.get(name)) |file| {
        return .{ .ptr = file, .inode_num = file.inode_num };
    }

    return error.DoesNotExist;
}

fn create(ptr: *anyopaque, parent: *fs.Inode, name: []const u8) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const parent_file: *FileNode  = @ptrCast(@alignCast(parent.fs_data.ptr));
    if(parent_file.children.contains(name)) {
        return error.AlreadyExist;
    }
    const file = try FileNode.init(self.allocator, self.getNextInodeNum());
    try parent_file.children.put(self.allocator, name, file);
}

fn destroy(ptr: *anyopaque, parent: *fs.Inode, name: []const u8) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const parent_file: *FileNode = @ptrCast(@alignCast(parent.fs_data.ptr));
    if(parent_file.children.get(name)) |child| {
        try iterativeDestroyFileNode(self.allocator, child);
        _ = parent_file.children.remove(name);
    } else {
        return error.DoesNotExist;
    }
}

fn resize(ptr: *anyopaque, inode: *fs.Inode, len: usize) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const file: *FileNode = @ptrCast(@alignCast(inode.fs_data.ptr));
    if(file.data) |data| {
        file.data = try self.allocator.realloc(data, len);
    } else {
        file.data = try self.allocator.alloc(u8, len);
    }
}

fn rename(ptr: *anyopaque, parent: *fs.Inode, old: []const u8, new: []const u8) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const parent_file: *FileNode = @ptrCast(@alignCast(parent.fs_data.ptr));
    if(parent_file.children.get(old)) |child| {
        _ = parent_file.children.remove(old);
        try parent_file.children.put(self.allocator, new, child);
    }
    return error.DoesNotExist;
}

fn getRootDentry(ptr: *anyopaque) *fs.Dentry {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return &self.root_dentry;
}

fn read(_: *anyopaque, inode: *fs.Inode, offset: usize, buf: []u8) usize {
    const file: *FileNode = @ptrCast(@alignCast(inode.fs_data.ptr));
    if(file.data) |data| {
        const end = @min(offset + buf.len, data.len);
        const count = end - offset;
        @memcpy(buf, data[offset..end]);
        return count;
    }
    return 0;
}

fn write(ptr: *anyopaque, inode: *fs.Inode, offset: usize, buf: []const u8) usize {
    const file: *FileNode = @ptrCast(@alignCast(inode.fs_data.ptr));
    const end = offset + buf.len;
    const count = end - offset;

    if(file.data) |data| {
        if(end > data.len) {
            resize(ptr, inode, end) catch return 0;
        }
    } else {
        resize(ptr, inode, end) catch return 0;
    }
    @memcpy(file.data.?[offset..end], buf);
    return count;
}

fn iterativeDestroyFileNode(allocator: std.mem.Allocator, root_file: *FileNode) !void {
    var stack = try std.ArrayList(*FileNode).initCapacity(allocator, 32);
    defer stack.deinit(allocator);

    try stack.append(allocator, root_file);

    while(stack.pop()) |f| {
        var iter = f.children.iterator();
        while(iter.next()) |entry| {
            try stack.append(allocator, entry.value_ptr.*);
        }
        if(f.data) |data| allocator.free(data);
        allocator.destroy(f);
    }
}

// frees only the FileNode tree, NOT the outer inode or dentry
fn deinit(ptr: *anyopaque) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const root_inode = self.root_dentry.inode orelse return;
    const root_file: *FileNode = @ptrCast(@alignCast(root_inode.fs_data.ptr));
    try iterativeDestroyFileNode(self.allocator, root_file);
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
    const root_inode = try allocator.create(fs.Inode);
    const self = try allocator.create(Self);
    const file = try FileNode.init(allocator, self.getNextInodeNum());

    root_inode.* = .{
        .fs_data = .{
            .ptr = file,
            .inode_num = file.inode_num
        },
        .dock_point = null,
        .ref_count = 0,
    };

    self.* = .{
        .cur_inode_num_counter = 0,
        .root_dentry = .{
            .name = try allocator.dupe(u8, "/"),
            .parent = null,
            .inode = root_inode,
            .ref_count = 0,
            .lock = .{}
        },
        .allocator = allocator
    };

    return self;
}

