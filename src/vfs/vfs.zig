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

fn createCachedDentry(
    allocator: std.mem.Allocator,
    fs_data: fs.FsData,
    dock_point: *fs.DockPoint,
    name: []const u8,
    parent: *fs.Dentry
) !*fs.Dentry {
    const inode = try checkCachedOrCreateInode(allocator, fs_data, dock_point);
    const dentry = try fs.Dentry.create(allocator, name, parent, inode);

    inode.dock_point = dock_point;
    inode.incRefAtomic();

    try inode_cache.put(.{ .inode_num = inode.fs_data.inode_num, .dock_point = inode.dock_point }, inode);
    try dentry_cache.put(.{ .parent = parent, .name = name }, dentry);

    parent.incRefAtomic();

    return dentry;
}

// doesn't increment the last dentry's ref_count, it only increments parent dentry's ref_count when it creates child dentry
// it doesn't go to last entry in the path_names
// so it just returns the (last - 1)th name dentry + the last name
// Example: `/dock_pt_name/dir/file` -> `dir`'s dentry + `file`
fn lookupIter(
    allocator: std.mem.Allocator,
    path_names: *std.mem.SplitIterator(u8, .sequence),
    dock_point: *fs.DockPoint
) !struct{*fs.Dentry, ?[]const u8} {
    var cur = dock_point.root_dentry;

    while(path_names.next()) |name| {
        if(path_names.peek() == null) {
            return .{cur, name};
        }

        if(dentry_cache.get(.{ .parent = cur, .name = name })) |dentry| {
            cur = dentry;
        } else {
            const fs_data = try dock_point.fs_ops.i_ops.lookup(dock_point.fs_ptr, cur.inode.?, name);
            cur = try createCachedDentry(allocator, fs_data, dock_point, name, cur);
        }
    }

    return .{cur, null};
}

pub fn open(allocator: std.mem.Allocator, path: []const u8, mode: fs.File.Mode) !*fs.File {
    var names = std.mem.splitSequence(u8, path, "/");
    _ = names.next();
    const dock_point_name = names.next() orelse return error.DoesNotExist;
    const dock_point = dock_points.get(dock_point_name) orelse return error.DoesNotExist;
    const lookup_res = try lookupIter(allocator, &names, dock_point);
    const last_dir_dentry = lookup_res.@"0";
    const last_name = lookup_res.@"1";

    if(last_name) |name| {
        const parent_inode = last_dir_dentry.inode.?;
        const i_ops = dock_point.fs_ops.i_ops;
        const fs_ptr = dock_point.fs_ptr;
        const fs_data = i_ops.lookup(fs_ptr, parent_inode, name) catch |e| blk: { 
            switch(e) {
                error.DoesNotExist => {
                    if(mode.create == 1) {
                        try i_ops.create(dock_point.fs_ptr, last_dir_dentry.inode.?, name, .{});
                        break :blk try i_ops.lookup(fs_ptr, parent_inode, name);
                    } else {
                        return e;
                    }
                },
                else => return e
            }
        };
        const dentry = try createCachedDentry(allocator, fs_data, dock_point, name, last_dir_dentry);
        return fs.File.create(allocator, dentry, mode);
    }
    return error.DoesNotExist;
}

pub fn close(allocator: std.mem.Allocator, f: *fs.File) void {
    f.destory(allocator);
}

pub fn rename(allocator: std.mem.Allocator, f: *fs.File, new_name: []const u8) !void {
    const dentry = f.dentry;
    const inode = dentry.inode orelse return error.InvalidFile;
    const dock_point = inode.dock_point orelse return error.InvalidFile;
    if(dentry.parent) |parent| {
        if(parent.inode) |pinode| {
            try dock_point.fs_ops.i_ops.rename(dock_point.fs_ptr, pinode, dentry.name, new_name);
        }
        if(dentry.name.len != new_name.len) {
            dentry.name = try allocator.realloc(dentry.name, new_name.len);
        }
        @memcpy(dentry.name, new_name);
    } else {
        return error.InvalidFile;
    }
}

pub fn mkdir(allocator: std.mem.Allocator, path: []const u8) !void {
    var names = std.mem.splitSequence(u8, path, "/");
    _ = names.next();
    const dock_point_name = names.next() orelse return error.DoesNotExist;
    const dock_point = dock_points.get(dock_point_name) orelse return error.DoesNotExist;
    const lookup_res = try lookupIter(allocator, &names, dock_point);
    const last_dir_dentry = lookup_res.@"0";
    const last_name = lookup_res.@"1";

    if(last_name) |name| {
        const parent_inode = last_dir_dentry.inode.?;
        const i_ops = dock_point.fs_ops.i_ops;
        const fs_ptr = dock_point.fs_ptr;
        _ = i_ops.lookup(fs_ptr, parent_inode, name) catch |e| { 
            switch(e) {
                error.DoesNotExist => {
                    try i_ops.create(dock_point.fs_ptr, last_dir_dentry.inode.?, name, .{ .is_dir = 1 });
                    const fs_data = try i_ops.lookup(fs_ptr, parent_inode, name);
                    _ = try createCachedDentry(allocator, fs_data, dock_point, name, last_dir_dentry);
                    return;
                },
                else => return e
            }
        };
        return error.AlreadyExist;
    }
    return error.DoesNotExist;
}

// pub fn rm(f: *File, path: []const u8) void {
// }
// 
// pub fn mv(f: *File, path: []const u8) void {
// }

pub fn read(f: *fs.File, buf: []u8) !usize {
    const dentry = f.dentry;
    const inode = dentry.inode orelse return error.InvalidFile;
    const dock_point = inode.dock_point orelse return error.InvalidFile;

    if(f.mode.read == 0) {
        return error.NoRead;
    }

    const count = try dock_point.fs_ops.f_ops.read(dock_point.fs_ptr, inode, f.offset, buf);
    f.offset += count;
    return count;
}

pub fn write(f: *fs.File, buf: []const u8) !usize {
    const dentry = f.dentry;
    const inode = dentry.inode orelse return error.InvalidFile;
    const dock_point = inode.dock_point orelse return error.InvalidFile;

    if(f.mode.write == 0) {
        return error.NoWrite;
    }

    const count = try dock_point.fs_ops.f_ops.write(dock_point.fs_ptr, inode, f.offset, buf);
    f.offset += count;
    return count;
}

pub fn stat(f: *fs.File) !fs.Stat {
    const dentry = f.dentry;
    const inode = dentry.inode orelse return error.InvalidFile;
    const dock_point = inode.dock_point orelse return error.InvalidFile;
    return dock_point.fs_ops.i_ops.stat(dock_point.fs_ptr, inode, dentry.name);
}
