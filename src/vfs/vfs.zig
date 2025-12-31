const std = @import("std");
const uart = @import("uart");
const _fs = @import("fs");
const FsOps = _fs.FsOps;
const FsType = _fs.FsType;
const Vnode = _fs.Vnode;
const Dentry = _fs.Dentry;

const DockPoint = struct {
    fs_ops: FsOps,
    fs_ptr: *anyopaque,
    fs_type: FsType,
    root_dentry: *Dentry,

    pub const HashKey = struct {
        path: []const u8,

        const Context = struct {
            pub fn hash(_: @This(), key: HashKey) u64 {
                return @as(u64, @intCast(@intFromPtr(key.parent))) + std.hash.Wyhash.hash(0, key.name);
            }

            pub fn eql(_: @This(), a: HashKey, b: HashKey) bool {
                return a.parent == b.parent and std.mem.eql(u8, a.name, b.name);
            }
        };
    };
};

const FileHandle = struct {
    vnode: *Vnode,
};

var vnode_cache: std.AutoHashMap(Vnode.HashKey, *Vnode) = undefined;
var dentry_cache: std.HashMap(Dentry.HashKey, *Dentry, Dentry.HashKey.Context, 80) = undefined;
var dock_points: std.StringHashMapUnmanaged(*DockPoint) = .empty;

pub fn init(allocator: std.mem.Allocator) !void {
    vnode_cache = .init(allocator);
    dentry_cache = .init(allocator);
}

pub fn dock(allocator: std.mem.Allocator, name: []const u8, fs_ops: FsOps, fs_ptr: *anyopaque, fs_type: FsType) !void {
    const d = try allocator.create(DockPoint);
    d.* = .{
        .fs_ops = fs_ops,
        .fs_type = fs_type,
        .fs_ptr = fs_ptr,
        .root_dentry = fs_ops.getRootDentry(fs_ptr),
    };

    if(dock_points.contains(name)) {
        return;
    }

    try dock_points.put(allocator, name, d);
}

pub fn undock(allocator: std.mem.Allocator, name: []const u8) anyerror!void {
    const d = dock_points.get(name) orelse return error.NotFound;
    _ = dock_points.remove(name);
    try d.fs_ops.deinit(d.fs_ptr);
    if(d.root_dentry.vnode) |v| allocator.destroy(v);
    allocator.destroy(d.root_dentry);
}

pub fn open(allocator: std.mem.Allocator, _: []const u8) error{NotFound, OutOfMemory}!*FileHandle {
    return try allocator.create(FileHandle);
}

// pub fn close(f: *FileHandle) void {
// }
// 
// pub fn rename(f: *FileHandle, new_name: []const u8) !void {
// }
// 
// pub fn mkdir(f: *FileHandle, path: []const u8) !void {
// }
// 
// pub fn rmdir(f: *FileHandle, path: []const u8) void {
// }
// 
// pub fn read(f: *FileHandle, buf: []u8) !usize {
// }
// 
// pub fn write(f: *FileHandle, buf: []u8) !usize {
// }
