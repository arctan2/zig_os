const std = @import("std");
pub const InitRamFs = @import("initramfs.zig");

pub const FsType = enum(u32) {
    Dir,
    File,
    Device,
    Network,
    Block,
};

pub const INodeOps = struct {
    lookup: *const fn(ptr: *anyopaque, path: []const u8) ?*VNode,
    create: *const fn(ptr: *anyopaque, path: []const u8) ?*VNode,
    rename: *const fn(ptr: *anyopaque, vnode: *VNode, name: []const u8) void,
    mkdir: *const fn(ptr: *anyopaque, path: []const u8) ?*VNode,
    rmdir: *const fn(ptr: *anyopaque, path: []const u8) void,
};

pub const FileOps = struct {
    read: *const fn(ptr: *anyopaque, vnode: *VNode) []u8,
    write: *const fn(ptr: *anyopaque, vnode: *VNode, bytes: []u8) void,
};

pub const FsOps = struct {
    i_ops: INodeOps,
    f_ops: FileOps
};

pub const VNode = struct {
    fs_data: *anyopaque,
    fs_type: FsType,
    fs: *FsOps,
    fs_id: usize,
    inode_num: usize,
    ref_count: usize,

    pub const HashKey = struct {
        fs_id: usize,
        inode_num: usize
    };
};

