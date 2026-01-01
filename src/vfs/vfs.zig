const std = @import("std");
const uart = @import("uart");
const fs = @import("fs");
const DListNode = @import("utils").types.DListNode;
const DoubleLinkedListQueue = @import("utils").types.DoubleLinkedListQueue;

const Mode = enum(u8) {
    Read = 1 << 0,
    Write = 1 << 1,
    _
};

const File = struct {
    inode: *fs.Inode,
    offset: usize,
    mode: Mode,
    is_dir: bool,

    pub fn create(allocator: std.mem.Allocator, inode: *fs.Inode, mode: Mode, is_dir: bool) !*File {
        const f = try allocator.create(File);
        f.* = .{
            .inode = inode,
            .offset = 0,
            .mode = mode,
            .is_dir = is_dir
        };
        return f;
    }

    pub inline fn destory(self: *File, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

var lru_inode = DoubleLinkedListQueue(DListNode(*fs.Inode));
var lru_dentry = DoubleLinkedListQueue(DListNode(*fs.Dentry));
var inode_cache: std.AutoHashMap(fs.Inode.HashKey, *fs.Inode) = undefined;
var dentry_cache: std.HashMap(fs.Dentry.HashKey, *fs.Dentry, fs.Dentry.HashKey.Context, 80) = undefined;
var dock_points: std.StringHashMapUnmanaged(*fs.DockPoint) = .empty;

pub fn init(allocator: std.mem.Allocator) !void {
    inode_cache = .init(allocator);
    dentry_cache = .init(allocator);
}

pub fn dock(allocator: std.mem.Allocator, name: []const u8, fs_ops: fs.FsOps, fs_ptr: *anyopaque, fs_type: fs.FsType) !void {
    const d = try allocator.create(fs.DockPoint);
    d.* = .{
        .fs_ops = fs_ops,
        .fs_type = fs_type,
        .fs_ptr = fs_ptr,
        .root_dentry = fs_ops.getRootDentry(fs_ptr),
    };

    d.root_dentry.inode.?.dock_point = d;

    if(dock_points.contains(name)) {
        return;
    }

    try dock_points.put(allocator, name, d);
}

pub fn undock(allocator: std.mem.Allocator, name: []const u8) anyerror!void {
    const d = dock_points.get(name) orelse return error.NotFound;
    _ = dock_points.remove(name);
    try d.fs_ops.deinit(d.fs_ptr);
    if(d.root_dentry.inode) |v| allocator.destroy(v);
    allocator.destroy(d.root_dentry);
}

fn checkCachedOrCreateInode(allocator: std.mem.Allocator, fs_data: fs.FsData, dock_point: *fs.DockPoint) !*fs.Inode {
    if(inode_cache.get(.{ .dock_point = dock_point, .inode_num = fs_data.inode_num })) |inode| {
        return inode;
    }
    return try fs.Inode.create(allocator, dock_point, fs_data);
}

fn lookupIter(allocator: std.mem.Allocator, path_parts: std.mem.SplitIterator(u8, .sequence), dock_point: *fs.DockPoint) !*fs.Dentry {
    var parts = path_parts;
    var cur = dock_point.root_dentry;

    while(parts.next()) |part| {
        if(dentry_cache.get(.{ .parent = cur, .name = part })) |dentry| {
            cur = dentry;
        } else {
            const fs_data = try dock_point.fs_ops.i_ops.lookup(dock_point.fs_ptr, cur.inode.?, part);
            const inode = try checkCachedOrCreateInode(allocator, fs_data, dock_point);
            const dentry = try fs.Dentry.create(allocator, part, cur, inode);
            inode.dock_point = dock_point;
            try inode_cache.put(.{ .inode_num = inode.fs_data.inode_num, .dock_point = inode.dock_point }, inode);
            try dentry_cache.put(.{ .parent = cur, .name = part }, dentry);
            cur.incRef();
            cur = dentry;
        }
    }

    return cur;
}

pub fn open(allocator: std.mem.Allocator, path: []const u8, mode: Mode) error{DoesNotExist, OutOfMemory}!*File {
    var parts = std.mem.splitSequence(u8, path, "/");
    _ = parts.next();
    const dock_point_name = parts.next() orelse return error.DoesNotExist;
    const dock_point = dock_points.get(dock_point_name) orelse return error.DoesNotExist;
    const dentry = try lookupIter(allocator, parts, dock_point);
    const file = try File.create(allocator, dentry.inode.?, mode, false);
    return file;
}

// pub fn close(f: *File) void {
// }
// 
// pub fn rename(f: *File, new_name: []const u8) !void {
// }
// 
// pub fn mkdir(f: *File, path: []const u8) !void {
// }
// 
// pub fn rm(f: *File, path: []const u8) void {
// }
// 
// pub fn read(f: *File, buf: []u8) !usize {
// }
// 
// pub fn write(f: *File, buf: []u8) !usize {
// }
