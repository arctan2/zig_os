const fs = @import("fs.zig");
const VNode = fs.VNode;

pub const Context = struct {
    data: []const u8
};

ctx: Context,

fn lookup(ptr: *anyopaque, path: []const u8) ?*VNode {
    const self: *Context = @ptrCast(@alignCast(ptr));
    _ = self;
    _ = path;
    _ = path;
    return null;
}

fn create(ptr: *anyopaque, path: []const u8) ?*VNode {
    const self: *Context = @ptrCast(@alignCast(ptr));
    _ = self;
    _ = path;
    return null;
}

fn rename(ptr: *anyopaque, vnode: *VNode, name: []const u8) void {
    const self: *Context = @ptrCast(@alignCast(ptr));
    _ = self;
    _ = vnode;
    _ = name;
}

fn mkdir(ptr: *anyopaque, path: []const u8) ?*VNode {
    const self: *Context = @ptrCast(@alignCast(ptr));
    _ = self;
    _ = path;
    _ = path;
    return null;
}

fn rmdir(ptr: *anyopaque, path: []const u8) void {
    const self: *Context = @ptrCast(@alignCast(ptr));
    _ = self;
    _ = path;
}

fn read(ptr: *anyopaque, vnode: *VNode) []u8 {
    const self: *Context = @ptrCast(@alignCast(ptr));
    _ = self;
    _ = vnode;
    return &.{};
}

fn write(ptr: *anyopaque, vnode: *VNode, bytes: []u8) void {
    const self: *Context = @ptrCast(@alignCast(ptr));
    _ = self;
    _ = vnode;
    _ = bytes;
}

pub const fs_ops: fs.FsOps = .{
    .i_ops = .{
        .lookup = lookup,
        .create = create,
        .mkdir = mkdir,
        .rmdir = rmdir,
        .rename = rename
    },
    .f_ops = .{
        .read = read,
        .write = write
    }
};

const Self = @This();

pub fn init(data: []const u8) Self {
    return .{
        .ctx = .{
            .data = data
        }
    };
}
