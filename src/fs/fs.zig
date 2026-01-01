const std = @import("std");
const SpinLock = @import("atomic").SpinLock;
const DListNode = @import("utils").types.DListNode;
pub const InitRamFs = @import("initramfs.zig");

pub const DockPoint = struct {
    fs_ops: FsOps,
    fs_ptr: *anyopaque,
    fs_type: FsType,
    root_dentry: *Dentry,
};

pub const Dentry = struct {
    name: []const u8,
    parent: ?*Dentry,
    inode: ?*Inode,
    ref_count: usize,
    lock: SpinLock,
    lru_node: ?*DListNode(*Dentry, "lru_node"),

    pub fn create(allocator: std.mem.Allocator, name: []const u8, parent: ?*Dentry, inode: ?*Inode) !*Dentry {
        const dentry = try allocator.create(Dentry);
        dentry.* = .{
            .name = try allocator.dupe(u8, name),
            .parent = parent,
            .inode = inode,
            .ref_count = 0,
            .lock = .{},
            .lru_node = null,
        };
        return dentry;
    }

    pub fn destroy(self: *Dentry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.destroy(self);
    }

    pub fn incRefAtomic(self: *Dentry) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.ref_count += 1;
    }

    pub fn decRefAtomic(self: *Dentry) void {
        self.lock.lock();
        defer self.lock.unlock();
        if(self.ref_count > 0) self.ref_count -= 1;
    }

    pub const HashKey = struct {
        name: []const u8,
        parent: *Dentry,

        pub const Context = struct {
            pub fn hash(_: @This(), key: HashKey) u64 {
                return @as(u64, @intCast(@intFromPtr(key.parent))) + std.hash.Wyhash.hash(0, key.name);
            }

            pub fn eql(_: @This(), a: HashKey, b: HashKey) bool {
                return a.parent == b.parent and std.mem.eql(u8, a.name, b.name);
            }
        };
    };
};

pub const FsData = struct {
    inode_num: usize,
    ptr: *anyopaque
};

pub const Inode = struct {
    fs_data: FsData,
    dock_point: ?*DockPoint,
    ref_count: usize,
    lock: SpinLock,
    lru_node: ?*DListNode(*Inode, "lru_node"),

    pub const HashKey = struct {
        dock_point: ?*DockPoint,
        inode_num: usize
    };

    pub fn create(allocator: std.mem.Allocator, dock_point: ?*DockPoint, fs_data: FsData) !*Inode {
        const inode = try allocator.create(Inode);
        inode.* = .{
            .fs_data = fs_data,
            .dock_point = dock_point,
            .ref_count = 0,
            .lock = .{},
            .lru_node = null
        };
        return inode;
    }

    pub fn incRefAtomic(self: *Inode) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.ref_count += 1;
    }

    pub fn decRefAtomic(self: *Inode) void {
        self.lock.lock();
        defer self.lock.unlock();
        if(self.ref_count > 0) self.ref_count -= 1;
    }

    pub inline fn destroy(self: *Inode, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

pub const FsType = enum(u8) {
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
    lookup: *const fn(ptr: *anyopaque, parent: *Inode, name: []const u8) error{OutOfMemory, DoesNotExist}!FsData,
    create: *const fn(ptr: *anyopaque, parent: *Inode, name: []const u8) INodeOpsError!void,
    destroy: *const fn(ptr: *anyopaque, parent: *Inode, name: []const u8) error{DoesNotExist, OutOfMemory}!void,
    resize: *const fn(ptr: *anyopaque, inode: *Inode, len: usize) error{OutOfMemory}!void,
    rename: *const fn(ptr: *anyopaque, parent: *Inode, old: []const u8, new: []const u8) INodeOpsError!void,
};

pub const FileOps = struct {
    read: *const fn(ptr: *anyopaque, inode: *Inode, offset: usize, buf: []u8) usize,
    write: *const fn(ptr: *anyopaque, inode: *Inode, offset: usize, buf: []const u8) usize,
};

pub const FsOps = struct {
    i_ops: INodeOps,
    f_ops: FileOps,
    getRootDentry: *const fn(ptr: *anyopaque) *Dentry,
    deinit: *const fn(ptr: *anyopaque) anyerror!void
};
