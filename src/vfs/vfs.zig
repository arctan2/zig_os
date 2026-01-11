const std = @import("std");
const expect = std.testing.expect;
const uart = @import("uart");
const fs = @import("fs");
const utils = @import("utils");
const DListNode = utils.types.DListNode;
const DoubleLinkedList = utils.types.DoubleLinkedList;

var lru_inode: DoubleLinkedList(DListNode(*fs.Inode, "lru_node")) = .{};
var lru_dentry: DoubleLinkedList(DListNode(*fs.Dentry, "lru_node")) = .{};
var inode_cache: std.AutoHashMapUnmanaged(fs.Inode.HashKey, *fs.Inode) = .empty;
var dentry_cache: std.HashMapUnmanaged(fs.Dentry.HashKey, *fs.Dentry, fs.Dentry.HashKey.Context, 80) = .empty;
var dock_points: std.StringHashMapUnmanaged(*fs.DockPoint) = .empty;

pub fn invalidateDentryCache(allocator: std.mem.Allocator) void {
    lru_dentry.clear();
    dentry_cache.deinit(allocator);
    dentry_cache = .empty;
}

pub fn invalidateInodeCache(allocator: std.mem.Allocator) void {
    lru_inode.clear();
    inode_cache.deinit(allocator);
    inode_cache = .empty;
}

pub fn dock(allocator: std.mem.Allocator, name: []const u8, fs_ops: fs.FsOps, fs_ptr: *anyopaque, fs_type: fs.FsType) !void {
    if(dock_points.contains(name)) {
        return error.AlreadyExist;
    }
    const dock_point = try fs.DockPoint.create(allocator, fs_ops, fs_ptr, fs_type); 
    const dock_name = try allocator.dupe(u8, name);
    errdefer allocator.free(dock_name);
    try dock_points.put(allocator, dock_name, dock_point);
}

pub fn undock(allocator: std.mem.Allocator, name: []const u8) !*anyopaque {
    const dock_point = dock_points.get(name) orelse return error.NotFound;
    const f = dock_point.fs_ptr;
    invalidateInodeCache(allocator);
    invalidateDentryCache(allocator);
    if(dock_points.fetchRemove(name)) |kv| {
        allocator.free(kv.key);
    }
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
    try dentry_cache.put(allocator, .{ .parent = parent, .name = dentry.name }, dentry);

    return dentry;
}

fn unlinkLockedDentry(dentry: *fs.Dentry) void {
    const parent = dentry.parent orelse return;
    const pinode = parent.inode orelse return;
    const inode = dentry.inode orelse return;
    const dock_point = inode.dock_point orelse return;

    inode.lock.lock();
    parent.lock.lock();
    pinode.lock.lock();
    defer {
        inode.lock.unlock();
        parent.lock.unlock();
        pinode.lock.unlock();
    }

    dock_point.fs_ops.i_ops.unlink(dock_point.fs_ptr, pinode, dentry.name);
    if(inode.fs_data.link_count > 0) inode.fs_data.link_count -= 1;

    if(dentry.lru_node) |lru| {
        lru_dentry.remove(@constCast(&lru));
    }

    _ = dentry_cache.remove(.{ .parent = parent, .name = dentry.name });
}

fn linkLockedDentry(parent: *fs.Dentry, name: []const u8, inode: *fs.Inode) !void {
    const pinode = parent.inode orelse return;
    const dock_point = inode.dock_point orelse return;

    inode.lock.lock();
    pinode.lock.lock();
    defer {
        inode.lock.unlock();
        pinode.lock.unlock();
    }

    try dock_point.fs_ops.i_ops.link(dock_point.fs_ptr, pinode, name, inode);
    if(inode.fs_data.link_count > 0) inode.fs_data.link_count += 1;
}

fn destroyLockedInode(allocator: std.mem.Allocator, inode: *fs.Inode) void {
    _ = inode_cache.remove(.{ .inode_num = inode.fs_data.inode_num, .dock_point = inode.dock_point });
    if(inode.lru_node) |lru| {
        lru_inode.remove(@constCast(&lru));
    }
    inode.lock.unlock();
    inode.destroy(allocator);
}

fn checkDestroyInodeLocked(allocator: std.mem.Allocator, dentry: *fs.Dentry, comptime call_destroy: bool) void {
    if(dentry.inode) |inode| {
        inode.lock.lock();
        if(inode.ref_count > 0) inode.ref_count -= 1;
        if(inode.ref_count == 0) {
            if(call_destroy) {
                const dock_point = inode.dock_point orelse return;
                dock_point.fs_ops.i_ops.destroy(dock_point.fs_ptr, inode);
            }
            destroyLockedInode(allocator, inode);
        } else {
            inode.lock.unlock();
        }
    }
}

fn iterDestroyLockedDentry(allocator: std.mem.Allocator, dentry: *fs.Dentry) void {
    var cur = dentry;
    while(cur.ref_count == 0 and !std.mem.eql(u8, cur.name, "/")) {
        const next_parent = cur.parent orelse return;
        next_parent.lock.lock();
        next_parent.children.remove(&cur.sibling_node);
        checkDestroyInodeLocked(allocator, cur, false);
        _ = dentry_cache.remove(.{ .parent = next_parent, .name = cur.name });
        cur.lock.unlock();
        cur.destroy(allocator);
        cur = next_parent;
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
                    try i_ops.create(dock_point.fs_ptr, parent_inode, name, .{ .is_dir = 1 });
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

    const parent = dentry.parent orelse return;
    parent.lock.lock();
    parent.children.remove(&dentry.sibling_node);

    checkDestroyInodeLocked(allocator, dentry, true);

    _ = dentry_cache.remove(.{ .parent = parent, .name = dentry.name });
    dentry.lock.unlock();
    dentry.destroy(allocator);
    parent.ref_count -= 1;
    iterDestroyLockedDentry(allocator, parent);
}

pub fn mv(allocator: std.mem.Allocator, from: []const u8, to: []const u8) !void {
    const from_dentry = try openDentry(allocator, from, .{ .read = 0 });

    var names = std.mem.splitSequence(u8, to, "/");
    _ = names.next();
    const dock_point_name = names.next() orelse return error.DoesNotExist;
    const dock_point = dock_points.get(dock_point_name) orelse return error.DoesNotExist;
    const lookup_res = try lookupIter(allocator, &names, dock_point);
    const last_dir_dentry = lookup_res.@"0";
    const last_name = lookup_res.@"1";

    if(last_name) |name| {
        const parent_inode = last_dir_dentry.inode orelse return;
        const i_ops = dock_point.fs_ops.i_ops;
        const fs_ptr = dock_point.fs_ptr;
        _ = i_ops.lookup(fs_ptr, parent_inode, name) catch |e| { 
            switch(e) {
                error.DoesNotExist => {
                    {
                        last_dir_dentry.lock.lock();
                        defer last_dir_dentry.lock.unlock();
                        if(!try last_dir_dentry.isDir()) {
                            return error.IsNotDirectory;
                        }
                    }

                    from_dentry.lock.lock();
                    defer from_dentry.lock.unlock();
                    unlinkLockedDentry(from_dentry);

                    last_dir_dentry.lock.lock();
                    defer last_dir_dentry.lock.unlock();

                    try linkLockedDentry(last_dir_dentry, name, from_dentry.inode.?);
                    last_dir_dentry.ref_count += 1;
                    from_dentry.parent = last_dir_dentry;
                    return;
                },
                else => return e
            }
        };
        return error.AlreadyExist;
    }
    return error.DoesNotExist;
}

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

test "basic create dir, create file, read, write and delete" {
    lru_inode = .{};
    lru_dentry = .{};
    inode_cache = .empty;
    dentry_cache = .empty;
    dock_points = .empty;

    const allocator = std.testing.allocator;
    const buf = [_]u8{};
    const initramfs_ctx = try fs.InitRamFs.init(allocator, &buf);
    try dock(allocator, "my_fs", fs.InitRamFs.fs_ops, initramfs_ctx, .Ram);
    defer {
        const f: *fs.Ramfs = @ptrCast(@alignCast(undock(allocator, "my_fs") catch @panic("undock failed")));
        allocator.destroy(f);
        dentry_cache.deinit(allocator);
        inode_cache.deinit(allocator);
        dock_points.deinit(allocator);
    }

    try mkdir(allocator, "/my_fs/my_dir");
    const f = try open(allocator, "/my_fs/my_dir/my_file.txt", .{.create = 1, .write = 1});
    const my_data = "the coolest data the humanity has ever seen in the entirity of it's existence";
    const written_count = try write(f, my_data);
    try expect(written_count == my_data.len);

    f.offset = 0;

    var read_buf = [_]u8{0} ** my_data.len;
    const read_count = try read(f, &read_buf);
    try expect(read_count == my_data.len);

    try expect(std.mem.eql(u8, &read_buf, my_data));

    close(allocator, f);
    try rm(allocator, "/my_fs/my_dir/my_file.txt");
}

test "loop create dir, create file, read, write and delete" {
    if(!utils.isAllTestMode()) return error.SkipZigTest;
    lru_inode = .{};
    lru_dentry = .{};
    inode_cache = .empty;
    dentry_cache = .empty;
    dock_points = .empty;

    const allocator = std.testing.allocator;
    const buf = [_]u8{};
    const initramfs_ctx = try fs.InitRamFs.init(allocator, &buf);
    try dock(allocator, "my_fs", fs.InitRamFs.fs_ops, initramfs_ctx, .Ram);
    defer {
        const f: *fs.Ramfs = @ptrCast(@alignCast(undock(allocator, "my_fs") catch @panic("undock failed")));
        allocator.destroy(f);
        dentry_cache.deinit(allocator);
        inode_cache.deinit(allocator);
        dock_points.deinit(allocator);
    }

    for (0..100) |i| {
        var dir_name_buf: [256]u8 = undefined;
        const dir_name = try std.fmt.bufPrint(&dir_name_buf, "/my_fs/my_dir_{d}", .{i});
        try mkdir(allocator, dir_name);

        var file_name_buf: [256]u8 = undefined;
        const file_name = try std.fmt.bufPrint(&file_name_buf, "/my_fs/my_dir_{d}/my_file_{d}.txt", .{i, i});
        const f = try open(allocator, file_name, .{.create = 1, .write = 1});

        var data_buf: [256]u8 = undefined;
        const my_data = try std.fmt.bufPrint(&data_buf, "the coolest data {d} the humanity has ever seen in the entirity of it's existence", .{i});
        const written_count = try write(f, my_data);
        try expect(written_count == my_data.len);
        
        f.offset = 0;
        var read_buf = [_]u8{0} ** 256;
        const read_count = try read(f, read_buf[0..my_data.len]);
        try expect(read_count == my_data.len);
        try expect(std.mem.eql(u8, read_buf[0..my_data.len], my_data));

        close(allocator, f);
        try rm(allocator, file_name);
    }
}

test "random loop create dir, create file, read, write and delete" {
    if(!utils.isAllTestMode()) return error.SkipZigTest;
    lru_inode = .{};
    lru_dentry = .{};
    inode_cache = .empty;
    dentry_cache = .empty;
    dock_points = .empty;

    const allocator = std.testing.allocator;
    const buf = [_]u8{};
    const initramfs_ctx = try fs.InitRamFs.init(allocator, &buf);
    try dock(allocator, "my_fs", fs.InitRamFs.fs_ops, initramfs_ctx, .Ram);
    defer {
        const f: *fs.Ramfs = @ptrCast(@alignCast(undock(allocator, "my_fs") catch @panic("undock failed")));
        allocator.destroy(f);
        dentry_cache.deinit(allocator);
        inode_cache.deinit(allocator);
        dock_points.deinit(allocator);
    }

    const depth = 5;
    const dirs_per_level = 5;
    
    var created_paths: std.ArrayList([]const u8) = .empty;
    defer {
        for (created_paths.items) |path| {
            allocator.free(path);
        }
        created_paths.deinit(allocator);
    }

    const CreateTree = struct {
        fn create(
            alloc: std.mem.Allocator,
            paths: *std.ArrayList([]const u8),
            current_path: []const u8,
            current_depth: usize,
            max_depth: usize
        ) !void {
            if (current_depth >= max_depth) {
                var file_path_buf: [512]u8 = undefined;
                const file_path = try std.fmt.bufPrint(&file_path_buf, "{s}/file.txt", .{current_path});
                const file = try open(alloc, file_path, .{.create = 1, .write = 1});

                const data = "awesome test data for recursive generated file";
                const written = try write(file, data);
                try expect(written == data.len);

                file.offset = 0;
                var read_buf: [100]u8 = undefined;
                const read_count = try read(file, read_buf[0..data.len]);
                try expect(read_count == data.len);
                try expect(std.mem.eql(u8, read_buf[0..data.len], data));

                close(alloc, file);
                try paths.append(allocator, try alloc.dupe(u8, file_path));
                return;
            }

            for (1..dirs_per_level + 1) |i| {
                var dir_path_buf: [512]u8 = undefined;
                const dir_path = try std.fmt.bufPrint(&dir_path_buf, "{s}/dir_{d}", .{current_path, i});
                try mkdir(alloc, dir_path);
                try create(alloc, paths, dir_path, current_depth + 1, max_depth);
            }
        }
    };

    try CreateTree.create(allocator, &created_paths, "/my_fs", 0, depth);

    for(created_paths.items) |it| {
        rm(allocator, it) catch {};
    }
}

test "random depth/name loop create dir, create file, read, write and delete" {
    if(!utils.isAllTestMode()) return error.SkipZigTest;
    lru_inode = .{};
    lru_dentry = .{};
    inode_cache = .empty;
    dentry_cache = .empty;
    dock_points = .empty;

    const allocator = std.testing.allocator;
    const buffer = [_]u8{};
    const initramfs_ctx = try fs.InitRamFs.init(allocator, &buffer);
    try dock(allocator, "my_fs", fs.InitRamFs.fs_ops, initramfs_ctx, .Ram);
    defer {
        const f: *fs.Ramfs = @ptrCast(@alignCast(undock(allocator, "my_fs") catch @panic("undock failed")));
        allocator.destroy(f);
        dentry_cache.deinit(allocator);
        inode_cache.deinit(allocator);
        dock_points.deinit(allocator);
    }

    const depth = 10;
    const max_dirs_per_level = 20;
    const num_operations = 1000;

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    const random = prng.random();

    var created_paths: std.ArrayList([]const u8) = .empty;
    defer {
        for (created_paths.items) |path| {
            allocator.free(path);
        }
        created_paths.deinit(allocator);
    }

    const CreateTree = struct {
        fn randomName(rand: std.Random, buf: []u8) []const u8 {
            const len = rand.intRangeAtMost(usize, 5, 12);
            for (0..len) |i| {
                buf[i] = switch (rand.intRangeAtMost(u8, 0, 2)) {
                    0 => rand.intRangeAtMost(u8, 'a', 'z'),
                    1 => rand.intRangeAtMost(u8, 'A', 'Z'),
                    else => rand.intRangeAtMost(u8, '0', '9'),
                };
            }
            return buf[0..len];
        }

        fn create(
            alloc: std.mem.Allocator,
            rand: std.Random,
            paths: *std.ArrayList([]const u8),
            current_path: []const u8,
            current_depth: usize,
            max_depth: usize,
            max_dirs: usize,
        ) !void {
            if (current_depth >= max_depth or paths.items.len >= num_operations) {
                var name_buf: [20]u8 = undefined;
                const file_name = randomName(rand, &name_buf);

                var file_path_buf: [512]u8 = undefined;
                const file_path = try std.fmt.bufPrint(&file_path_buf, "{s}/{s}.txt", .{current_path, file_name});

                const file = try open(alloc, file_path, .{.create = 1, .write = 1});
                const data = "random test data";
                const written = try write(file, data);
                try expect(written == data.len);
                file.offset = 0;
                var read_buf: [100]u8 = undefined;
                const read_count = try read(file, read_buf[0..data.len]);
                try expect(read_count == data.len);
                try expect(std.mem.eql(u8, read_buf[0..data.len], data));
                close(alloc, file);
                try paths.append(alloc, try alloc.dupe(u8, file_path));
                return;
            }

            const num_dirs = rand.intRangeAtMost(usize, 1, max_dirs);
            for (0..num_dirs) |_| {
                if (paths.items.len >= num_operations) break;

                var name_buf: [20]u8 = undefined;
                const dir_name = randomName(rand, &name_buf);

                var dir_path_buf: [512]u8 = undefined;
                const dir_path = try std.fmt.bufPrint(&dir_path_buf, "{s}/{s}", .{current_path, dir_name});

                mkdir(alloc, dir_path) catch |e| {
                    if (e == error.AlreadyExist) continue;
                    return e;
                };

                try create(alloc, rand, paths, dir_path, current_depth + 1, max_depth, max_dirs);
            }
        }
    };

    try CreateTree.create(allocator, random, &created_paths, "/my_fs", 0, depth, max_dirs_per_level);

    for(created_paths.items) |it| {
        rm(allocator, it) catch {};
    }
}

test "mv" {
    lru_inode = .{};
    lru_dentry = .{};
    inode_cache = .empty;
    dentry_cache = .empty;
    dock_points = .empty;

    const allocator = std.testing.allocator;
    const buf = [_]u8{};
    const initramfs_ctx = try fs.InitRamFs.init(allocator, &buf);
    try dock(allocator, "my_fs", fs.InitRamFs.fs_ops, initramfs_ctx, .Ram);
    defer {
        const f: *fs.Ramfs = @ptrCast(@alignCast(undock(allocator, "my_fs") catch @panic("undock failed")));
        allocator.destroy(f);
        dentry_cache.deinit(allocator);
        inode_cache.deinit(allocator);
        dock_points.deinit(allocator);
    }

    try mkdir(allocator, "/my_fs/my_dir");
    try mkdir(allocator, "/my_fs/another_dir");

    const og_name = "/my_fs/my_dir/my_file.txt";
    const new_name = "/my_fs/another_dir/his_file.txt";

    var f = try open(allocator, og_name, .{.create = 1, .write = 1});
    const my_data = "the coolest data the humanity has ever seen in the entirity of it's existence";
    const written_count = try write(f, my_data);
    try expect(written_count == my_data.len);
    close(allocator, f);

    try mv(allocator, og_name, new_name);

    f = try open(allocator, new_name, .{});
    var read_buf = [_]u8{0} ** my_data.len;
    var read_count = try read(f, &read_buf);
    try expect(read_count == my_data.len);
    try expect(std.mem.eql(u8, &read_buf, my_data));
    close(allocator, f);

    const cool_name = "/my_fs/another_dir/cool_f.md";
    try mv(allocator, new_name, cool_name);

    f = try open(allocator, cool_name, .{});
    close(allocator, f);

    var f_error = open(allocator, new_name, .{});
    try expect(f_error == error.DoesNotExist);

    const renamed_cool_name = "/my_fs/another_dir/renamed_cool_name.txt";
    try mv(allocator, cool_name, renamed_cool_name);

    f = try open(allocator, renamed_cool_name, .{});
    read_buf = [_]u8{0} ** my_data.len;
    read_count = try read(f, &read_buf);
    try expect(read_count == my_data.len);
    try expect(std.mem.eql(u8, &read_buf, my_data));
    close(allocator, f);

    f_error = open(allocator, new_name, .{});
    try expect(f_error == error.DoesNotExist);

    const final_rename = "/my_fs/another_dir/final_rename.txt";
    try mv(allocator, renamed_cool_name, final_rename);

    f = try open(allocator, final_rename, .{});
    read_buf = [_]u8{0} ** my_data.len;
    read_count = try read(f, &read_buf);
    try expect(read_count == my_data.len);
    try expect(std.mem.eql(u8, &read_buf, my_data));
    close(allocator, f);

    f_error = open(allocator, renamed_cool_name, .{});
    try expect(f_error == error.DoesNotExist);
}
