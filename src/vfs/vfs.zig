const std = @import("std");
const uart = @import("uart");
const fs = @import("fs");
const DListNode = @import("utils").types.DListNode;
const DoubleLinkedList = @import("utils").types.DoubleLinkedList;

var lru_inode: DoubleLinkedList(DListNode(*fs.Inode, "lru_node")) = .{};
var lru_dentry: DoubleLinkedList(DListNode(*fs.Dentry, "lru_node")) = .{};
var inode_cache: std.AutoHashMapUnmanaged(fs.Inode.HashKey, *fs.Inode) = .empty;
var dentry_cache: std.HashMapUnmanaged(fs.Dentry.HashKey, *fs.Dentry, fs.Dentry.HashKey.Context, 80) = .empty;
var dock_points: std.StringHashMapUnmanaged(*fs.DockPoint) = .empty;

pub fn dock(allocator: std.mem.Allocator, name: []const u8, fs_ops: fs.FsOps, fs_ptr: *anyopaque, fs_type: fs.FsType) !void {
    if(dock_points.contains(name)) {
        return error.AlreadyExist;
    }
    const dock_point = try fs.DockPoint.create(allocator, fs_ops, fs_ptr, fs_type); 
    try dock_points.put(allocator, name, dock_point);
}

pub fn undock(allocator: std.mem.Allocator, name: []const u8) !*anyopaque {
    const dock_point = dock_points.get(name) orelse return error.NotFound;
    const f = dock_point.fs_ptr;
    _ = dock_points.remove(name);
    try dock_point.destroy(allocator);
    return f;
}

fn checkCachedOrCreateInode(allocator: std.mem.Allocator, fs_data: fs.FsData, dock_point: *fs.DockPoint) !*fs.Inode {
    if(inode_cache.get(.{ .dock_point = dock_point, .inode_num = fs_data.inode_num })) |inode| {
        if(inode.lru_node) |lru| {
            inode.lock.lock();
            defer inode.lock.unlock();
            lru_inode.remove(@constCast(&lru));
            inode.lru_node = null;
        }
        return inode;
    }
    return try fs.Inode.create(allocator, dock_point, fs_data);
}

fn createCachedDentryIfNotExist(
    allocator: std.mem.Allocator,
    fs_data: fs.FsData,
    dock_point: *fs.DockPoint,
    name: []const u8,
    parent: *fs.Dentry
) !*fs.Dentry {
    if(dentry_cache.get(.{ .parent = parent, .name = name })) |dentry| {
        return dentry;
    }

    const inode = try checkCachedOrCreateInode(allocator, fs_data, dock_point);
    const dentry = try fs.Dentry.create(allocator, name, parent, inode);

    parent.addChild(dentry);

    inode.dock_point = dock_point;
    inode.incRefAtomic();

    try inode_cache.put(allocator, .{ .inode_num = inode.fs_data.inode_num, .dock_point = inode.dock_point }, inode);
    try dentry_cache.put(allocator, .{ .parent = parent, .name = name }, dentry);

    return dentry;
}

fn unlinkLockedDentry(dentry: *fs.Dentry) void {
    const parent = dentry.parent orelse return;
    const pinode = parent.inode orelse return;
    const inode = dentry.inode orelse return;
    const dock_point = inode.dock_point orelse return;

    inode.lock.lock();
    defer inode.lock.unlock();

    dock_point.fs_ops.i_ops.unlink(dock_point.fs_ptr, pinode, dentry.name);
    if(inode.fs_data.link_count > 0) inode.fs_data.link_count -= 1;

    if(dentry.lru_node) |lru| {
        lru_dentry.remove(@constCast(&lru));
    }

    _ = dentry_cache.remove(.{ .parent = parent, .name = dentry.name });
}

fn destroyLockedInode(allocator: std.mem.Allocator, inode: *fs.Inode) void {
    _ = inode_cache.remove(.{ .inode_num = inode.fs_data.inode_num, .dock_point = inode.dock_point });

    const dock_point = inode.dock_point orelse return;
    if(inode.lru_node) |lru| {
        lru_inode.remove(@constCast(&lru));
    }
    dock_point.fs_ops.i_ops.destroy(dock_point.fs_ptr, inode);
    inode.lock.unlock();
    inode.destroy(allocator);
}

fn iterDestroyLockedDentry(allocator: std.mem.Allocator, dentry: *fs.Dentry) void {
    var cur = dentry;
    while(cur.ref_count == 0) {
        const next_parent = cur.parent;

        if(cur.inode) |inode| {
            inode.lock.lock();
            if(inode.ref_count > 0) inode.ref_count -= 1;
            if(inode.ref_count == 0) {
                destroyLockedInode(allocator, inode);
            } else {
                inode.lock.unlock();
            }
        }

        cur.lock.unlock();
        cur.destroy(allocator);
        cur = next_parent orelse return;
        cur.lock.lock();
        cur.ref_count -= 1;
    }
    cur.lock.unlock();
}

// doesn't increment the any dentry's ref_count, it only increments parent dentry's ref_count when it creates child dentry
// it consume the last entry in the path_names
// but it just returns the { (last - 1)th name dentry, the last name }
// Example: `/dock_pt_name/dir/file` -> { `dir`'s dentry, `file` }
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
            cur = try createCachedDentryIfNotExist(allocator, fs_data, dock_point, name, cur);
        }
    }

    return .{cur, null};
}

// doesn't increment the ref count of dentry.
// it's the responsibility of caller
fn openDentry(allocator: std.mem.Allocator, path: []const u8, mode: fs.File.Mode) !*fs.Dentry {
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
        return try createCachedDentryIfNotExist(allocator, fs_data, dock_point, name, last_dir_dentry);
    }
    return error.DoesNotExist;
}

pub fn open(allocator: std.mem.Allocator, path: []const u8, mode: fs.File.Mode) !*fs.File {
    const dentry = try openDentry(allocator, path, mode);
    return try fs.File.create(allocator, dentry, mode);
}

pub fn close(allocator: std.mem.Allocator, f: *fs.File) void {
    const dentry = f.dentry;
    f.destory(allocator);

    dentry.lock.lock();

    if(dentry.ref_count > 0) {
        dentry.createLruNode();
        lru_dentry.push(&dentry.lru_node.?);
        dentry.lock.unlock();
        return;
    }

    var should_destroy = true;
    if(dentry.inode) |inode| {
        inode.lock.lock();
        defer inode.lock.unlock();
        if(inode.fs_data.link_count > 0) {
            should_destroy = false;
        }
    }

    if(should_destroy) {
        iterDestroyLockedDentry(allocator, dentry);
    } else {
        dentry.lock.unlock();
    }
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
                    _ = try createCachedDentryIfNotExist(allocator, fs_data, dock_point, name, last_dir_dentry);
                    return;
                },
                else => return e
            }
        };
        return error.AlreadyExist;
    }
    return error.DoesNotExist;
}

pub fn rm(allocator: std.mem.Allocator, path: []const u8) !void {
    const dentry = try openDentry(allocator, path, .{ .create = 0, .read = 0, .write = 0 });
    if(try dentry.isDir()) {
        @panic("have to handle dir rm");
    }
    dentry.lock.lock();
    unlinkLockedDentry(dentry);
    iterDestroyLockedDentry(allocator, dentry);
}

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
    return try f.dentry.stat();
}

test "basic" {
    const allocator = std.testing.allocator;

    const initramfs_img = @embedFile("./test_asset/initramfs_img.cpio");
    const initramfs_ctx = try fs.InitRamFs.init(allocator, initramfs_img);
    try dock(allocator, "initramfs", fs.InitRamFs.fs_ops, initramfs_ctx, .Ram);

    defer {
        const f: *fs.Ramfs = @ptrCast(@alignCast(undock(allocator, "initramfs") catch @panic("undock failed")));
        allocator.destroy(f);
        dentry_cache.deinit(allocator);
        inode_cache.deinit(allocator);
        dock_points.deinit(allocator);
    }

}
