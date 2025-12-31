const std = @import("std");
pub const InitRamFs = @import("initramfs.zig");

pub const Dentry = struct {
    name: []const u8,
    parent: ?*Dentry,
    vnode: ?*Vnode,
    ref_count: usize,

    pub const HashKey = struct {
        name: []const u8,
        parent: *Dentry,

        pub const Context = struct {
            pub fn hash(_: @This(), key: HashKey) u64 {
                return @as(u64, @intCast(@intFromPtr(key.parent orelse 0))) + std.hash.Wyhash.hash(0, key.name);
            }

            pub fn eql(_: @This(), a: HashKey, b: HashKey) bool {
                return a.parent == b.parent and std.mem.eql(u8, a.name, b.name);
            }
        };
    };
};


pub const Vnode = struct {
    fs_data: *anyopaque,
    dock_point_id: usize,
    inode_num: usize,
    ref_count: usize,

    pub const HashKey = struct {
        super_block_id: usize,
        inode_num: usize
    };
};

pub const FsType = enum(u8) {
    Dir,
    File,
    Device,
    Network,
    Block,
    Ram,
};

pub const INodeOpsError = error {
    OutOfMemory,
    AlreadyExist,
    DoesNotExist
};

pub const INodeOps = struct {
    lookup: *const fn(ptr: *anyopaque, parent: *Vnode, name: []const u8) INodeOpsError!*Vnode,
    create: *const fn(ptr: *anyopaque, parent: *Vnode, name: []const u8) INodeOpsError!void,
    destroy: *const fn(ptr: *anyopaque, parent: *Vnode, name: []const u8) error{DoesNotExist}!void,
    resize: *const fn(ptr: *anyopaque, vnode: *Vnode, len: usize) error{OutOfMemory}!void,
    rename: *const fn(ptr: *anyopaque, parent: *Vnode, old: []const u8, new: []const u8) INodeOpsError!void,
};

pub const FileOps = struct {
    read: *const fn(ptr: *anyopaque, vnode: *Vnode, offset: usize, buf: []u8) usize,
    write: *const fn(ptr: *anyopaque, vnode: *Vnode, offset: usize, buf: []u8) usize,
};

pub const FsOps = struct {
    i_ops: INodeOps,
    f_ops: FileOps,
    getRootDentry: *const fn(ptr: *anyopaque) *Dentry,
    deinit: *const fn(ptr: *anyopaque) anyerror!void
};
