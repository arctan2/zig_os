const std = @import("std");
const fs = @import("fs.zig");
const uart = @import("uart");
const utils = @import("utils");

// TODO: support hard links maybe
// currently it doesn't have concept of links at all
// when you call unlink(parent, name) it simply just removes it from
// directory entry

pub const FileNode = struct {
    data: ?[]u8 = null,
    inode_num: usize,
    file_flags: fs.FileFlags,
    children: std.StringHashMapUnmanaged(*FileNode) = .empty,

    inline fn create(allocator: std.mem.Allocator, inode_num: usize, file_flags: fs.FileFlags) !*FileNode {
        const f = try allocator.create(FileNode);
        f.* = .{ .inode_num = inode_num, .file_flags = file_flags };
        return f;
    }
};

root_dentry: *fs.Dentry,
cur_inode_num_counter: usize = 0,
allocator: std.mem.Allocator,

const Self = @This();

pub fn getNextInodeNum(self: *Self) usize {
    self.cur_inode_num_counter += 1;
    return self.cur_inode_num_counter;
}

fn lookup(_: *anyopaque, parent: *fs.Inode, name: []const u8) !fs.FsData {
    const parent_file: *FileNode = @ptrCast(@alignCast(parent.fs_data.ptr));

    if(parent_file.children.get(name)) |file| {
        return .{ .ptr = file, .inode_num = file.inode_num, .link_count = 1 };
    }

    return error.DoesNotExist;
}

fn create(ptr: *anyopaque, parent: *fs.Inode, name: []const u8, file_flags: fs.FileFlags) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const parent_file: *FileNode  = @ptrCast(@alignCast(parent.fs_data.ptr));

    if(name.len > fs.MAX_FILE_NAME_LEN or utils.isStringNameEmpty(name)) {
        return error.InvalidFileName;
    }

    if(parent_file.children.contains(name)) {
        return error.AlreadyExist;
    }

    const file = try FileNode.create(self.allocator, self.getNextInodeNum(), file_flags);

    const file_name = try self.allocator.dupe(u8, name);
    errdefer self.allocator.free(file_name);

    try parent_file.children.put(self.allocator, file_name, file);
}

// Note: it doesn't care about directories it simply just remove the FileNode of name
// from the children
fn unlink(ptr: *anyopaque, parent: *fs.Inode, name: []const u8) void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const parent_file: *FileNode = @ptrCast(@alignCast(parent.fs_data.ptr));
    if(parent_file.children.fetchRemove(name)) |entry| {
        self.allocator.free(entry.key);
    }
}

fn link(ptr: *anyopaque, parent: *fs.Inode, name: []const u8, inode: *fs.Inode) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const parent_file: *FileNode = @ptrCast(@alignCast(parent.fs_data.ptr));
    const child_file: *FileNode = @ptrCast(@alignCast(inode.fs_data.ptr));
    if(parent_file.children.contains(name)) {
        return error.AlreadyExist;
    }
    const file_name = try self.allocator.dupe(u8, name);
    errdefer self.allocator.free(file_name);
    try parent_file.children.put(self.allocator, file_name, child_file);
}

fn destroy(ptr: *anyopaque, inode: *fs.Inode) void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const file_node: *FileNode = @ptrCast(@alignCast(inode.fs_data.ptr));
    if(file_node.data) |data| self.allocator.free(data);
    self.allocator.destroy(file_node);
}

fn resize(ptr: *anyopaque, inode: *fs.Inode, len: usize) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const file: *FileNode = @ptrCast(@alignCast(inode.fs_data.ptr));

    if(file.file_flags.is_dir == 1) {
        return error.IsDir;
    }
    
    if(file.data) |data| {
        file.data = try self.allocator.realloc(data, len);
    } else {
        file.data = try self.allocator.alloc(u8, len);
    }
}

fn stat(_: *anyopaque, inode: *fs.Inode, name: []const u8) fs.Stat {
    const file: *FileNode = @ptrCast(@alignCast(inode.fs_data.ptr));
    
    if(file.children.count() == 0) {
        if(file.data) |data| {
            return .{ .name = name, .size = data.len, .file_flags = file.file_flags };
        }
    }

    return .{ .name = name, .size = 0, .file_flags = file.file_flags };
}

fn getRootDentry(ptr: *anyopaque) *fs.Dentry {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.root_dentry;
}

fn read(_: *anyopaque, inode: *fs.Inode, offset: usize, buf: []u8) !usize {
    const file: *FileNode = @ptrCast(@alignCast(inode.fs_data.ptr));

    if(file.file_flags.is_dir == 1) {
        return error.IsDir;
    }

    if(file.data) |data| {
        const end = @min(offset + buf.len, data.len);
        const count = end - offset;
        if(count == 0) return error.EOF;
        @memcpy(buf[0..count], data[offset..end]);
        return count;
    }
    return 0;
}

fn write(ptr: *anyopaque, inode: *fs.Inode, offset: usize, buf: []const u8) !usize {
    const file: *FileNode = @ptrCast(@alignCast(inode.fs_data.ptr));

    if(file.file_flags.is_dir == 1) {
        return error.IsDir;
    }

    if(file.file_flags.w == 0) {
        return error.NoWrite;
    }

    const end = offset + buf.len;
    const count = end - offset;

    if(file.data) |data| {
        if(end > data.len) {
            try resize(ptr, inode, end);
        }
    } else {
        try resize(ptr, inode, end);
    }
    @memcpy(file.data.?[offset..end], buf);
    return count;
}

fn iterativeDestroyFileNode(allocator: std.mem.Allocator, root_file: *FileNode) !void {
    var stack = try std.ArrayList(*FileNode).initCapacity(allocator, root_file.children.count());
    defer stack.deinit(allocator);

    var visited: std.AutoHashMapUnmanaged(*FileNode, void) = .empty;
    defer visited.deinit(allocator);
    
    try visited.put(allocator, root_file, {});
    try stack.append(allocator, root_file);

    while(stack.pop()) |f| {
        var iter = f.children.iterator();
        while(iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            if(!visited.contains(entry.value_ptr.*)) {
                try visited.put(allocator, entry.value_ptr.*, {});
                try stack.append(allocator, entry.value_ptr.*);
            }
        }
        if(f.data) |data| allocator.free(data);
        f.children.deinit(allocator);
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
        .link = link,
        .unlink = unlink,
        .create = create,
        .destroy = destroy,
        .resize = resize,
        .stat = stat
    },
    .f_ops = .{
        .read = read,
        .write = write
    },
    .getRootDentry = getRootDentry,
    .deinit = deinit
};

pub fn initManaged(allocator: std.mem.Allocator) !*Self {
    const self = try allocator.create(Self);
    const file = try FileNode.create(allocator, 0, .{.is_dir = 1, .w = 1, .x = 0});
    const root_inode = try fs.Inode.create(allocator, null, .{ .inode_num = file.inode_num, .ptr = file, .link_count = 1 });
    const root_dentry = try fs.Dentry.create(allocator, "/", null, root_inode);

    self.* = .{
        .root_dentry = root_dentry,
        .allocator = allocator
    };

    return self;
}

