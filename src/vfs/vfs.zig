const std = @import("std");
const _fs = @import("fs");
const FsOps = _fs.FsOps;
const VNode = _fs.VNode;

const DockPoint = struct {
    fs_ops: FsOps,
    fs_ptr: *anyopaque,
    path: []const u8,
};

const FileHandle = struct {
    vnode: *VNode,
};

var dock_points: std.ArrayList(DockPoint) = undefined;
var vnode_cache: std.AutoHashMap(VNode.HashKey, *VNode) = undefined;
var root_fs: ?*DockPoint = null;

pub fn init(allocator: std.mem.Allocator) !void {
    dock_points = try std.ArrayList(DockPoint).initCapacity(allocator, 32);
    vnode_cache = std.AutoHashMap(VNode.HashKey, *VNode).init(allocator);
}

pub fn findDockPointByPathExact(path: []const u8) ?*DockPoint {
    for(dock_points.items) |*d| {
        if(std.mem.eql(u8, d.path, path)) {
            return d;
        }
    }

    return null;
}

pub fn resolveDockPointByPath(path: []const u8) ?*DockPoint {
    var longest: ?*DockPoint = null;
    var longest_len: usize = 0;

    for(dock_points.items) |*d| {
        if(std.mem.startsWith(d.path.ptr, path.ptr)) {
            if(d.path.len > longest_len) {
                longest_len = d.len;
                longest = d;
            }
        }
    }

    return longest orelse root_fs;
}

pub fn dock(path: []const u8, fs_ops: FsOps, fs_ptr: *anyopaque) error{PathAlreadyExist}!void {
    if(findDockPointByPathExact(path)) |_| {
        return error.PathAlreadyExist;
    }
    const d = DockPoint{
        .fs_ops = fs_ops,
        .fs_ptr = fs_ptr,
        .path = path,
    };
    return dock_points.appendBounded(d) catch error.PathAlreadyExist;
}

pub fn undock(path: []const u8) void {
    // TODO: cleanup cache
    for(0..dock_points.len) |i| {
        if(std.mem.eql(u8, path, dock_points.items[i].path)) {
            dock_points.orderedRemove(i);
            break;
        }
    }
}

pub fn makeRoot(path: []const u8, old_root_path: []const u8) error{DockPointNotFound}!void {
    const d = findDockPointByPathExact(path) orelse return .DockPointNotFound;
    if(root_fs) |rfs| {
        rfs.path = old_root_path;
        d.path = "/";
    } else {
        root_fs = d;
    }
}

// pub fn open(path: []const u8) !FileHandle {
// }
// 
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
