const std = @import("std");
const uart = @import("uart");
const fs = @import("fs");
const DListNode = @import("utils").types.DListNode;
const DoubleLinkedListQueue = @import("utils").types.DoubleLinkedListQueue;

var lru_inode: DoubleLinkedListQueue(DListNode(*fs.Inode, "lru_node")) = .default();
var lru_dentry: DoubleLinkedListQueue(DListNode(*fs.Dentry, "lru_node")) = .default();
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

pub fn undock(allocator: std.mem.Allocator, name: []const u8) !void {
    const d = dock_points.get(name) orelse return error.NotFound;
    _ = dock_points.remove(name);
    try d.fs_ops.deinit(d.fs_ptr);
    if(d.root_dentry.inode) |v| allocator.destroy(v);
    allocator.destroy(d.root_dentry);
}

fn checkCachedOrCreateInode(allocator: std.mem.Allocator, fs_data: fs.FsData, dock_point: *fs.DockPoint) !*fs.Inode {
    if(inode_cache.get(.{ .dock_point = dock_point, .inode_num = fs_data.inode_num })) |inode| {
        if(inode.lru_node) |lru| {
            inode.lock.lock();
            defer inode.lock.unlock();
            lru_inode.remove(lru);
            allocator.destroy(lru);
            inode.lru_node = null;
        }
        return inode;
    }
    return try fs.Inode.create(allocator, dock_point, fs_data);
}

// doesn't increment the last dentry's ref_count, it only increments parent dentry's ref_count when it creates child dentry
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
            inode.incRefAtomic();

            try inode_cache.put(.{ .inode_num = inode.fs_data.inode_num, .dock_point = inode.dock_point }, inode);
            try dentry_cache.put(.{ .parent = cur, .name = part }, dentry);

            cur.incRefAtomic();
            cur = dentry;
        }
    }

    return cur;
}

pub fn open(allocator: std.mem.Allocator, path: []const u8, mode: fs.File.Mode) !*fs.File {
    var parts = std.mem.splitSequence(u8, path, "/");
    _ = parts.next();
    const dock_point_name = parts.next() orelse return error.DoesNotExist;
    const dock_point = dock_points.get(dock_point_name) orelse return error.DoesNotExist;
    const dentry = try lookupIter(allocator, parts, dock_point);
    const file = try fs.File.create(allocator, dentry, mode);
    return file;
}

pub fn close(allocator: std.mem.Allocator, f: *fs.File) void {
    f.destory(allocator);
}

// pub fn rename(f: *File, new_name: []const u8) !void {
// }
// 
// pub fn mkdir(f: *File, path: []const u8) !void {
// }
// 
// pub fn rm(f: *File, path: []const u8) void {
// }
// 
pub fn read(f: *fs.File, buf: []u8) !usize {
    const dentry = f.dentry;
    const inode = dentry.inode orelse return error.InvalidFile;
    const dock_point = inode.dock_point orelse return error.InvalidFile;
    return try dock_point.fs_ops.f_ops.read(dock_point.fs_ptr, inode, f.offset, buf);
}

pub fn write(f: *fs.File, buf: []const u8) !usize {
    const dentry = f.dentry;
    const inode = dentry.inode orelse return error.InvalidFile;
    const dock_point = inode.dock_point orelse return error.InvalidFile;
    return try dock_point.fs_ops.f_ops.write(dock_point.fs_ptr, inode, f.offset, buf);
}

pub fn stat(f: *fs.File) !fs.Stat {
    const dentry = f.dentry;
    const inode = dentry.inode orelse return error.InvalidFile;
    const dock_point = inode.dock_point orelse return error.InvalidFile;
    return dock_point.fs_ops.i_ops.stat(dock_point.fs_ptr, inode, dentry.name);
}
