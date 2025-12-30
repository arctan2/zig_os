const std = @import("std");
const uart = @import("uart");

pub const CpioNewcHeader = struct {
    magic: [6]u8,
    ino: [8]u8,
    mode: [8]u8,
    uid: [8]u8,
    gid: [8]u8,
    nlink: [8]u8,
    mtime: [8]u8,
    filesize: [8]u8,
    devmajor: [8]u8,
    devminor: [8]u8,
    rdevmajor: [8]u8,
    rdevminor: [8]u8,
    namesize: [8]u8,
    check: [8]u8,

};

pub fn toU64(field: *const [8]u8) u64 {
    var i: u64 = 1;
    var val: u64 = 0;
    var idx: i8 = 7;

    while(idx >= 0) : (idx -= 1) {
        var c: u8 = field[@intCast(idx)];
        c = if(c >= 'A') (c - 'A') + 10 else (c - '0');
        val += c * i;
        i *= 16;
    }

    return val;
}

pub const Entry = struct {
    header: *const CpioNewcHeader,
    file_name: []const u8,
    data: []const u8
};

pub const CpioIterator = struct {
    cur_offset: u64,
    data: []const u8,

    pub fn init(data: []const u8) CpioIterator {
        return .{
            .cur_offset = 0,
            .data = data
        };
    }

    pub fn nextEntry(self: *CpioIterator) ?Entry {
        if(self.cur_offset >= self.data.len) return null;
        const header: *const CpioNewcHeader = @ptrCast(&self.data[@intCast(self.cur_offset)]);

        if(!std.mem.eql(u8, &header.magic, "070701")) return null;

        const name_size = toU64(&header.namesize);
        const file_size = toU64(&header.filesize);

        const name_off: usize = @intCast(self.cur_offset + @sizeOf(CpioNewcHeader));
        const data_off: usize = std.mem.alignForward(usize, name_off + @as(usize, @intCast(name_size)), 4);
        self.cur_offset += std.mem.alignForward(u64, @sizeOf(CpioNewcHeader) + name_size + file_size, 4);
        return .{
            .header = header,
            .file_name = self.data[name_off..name_off + @as(usize, @intCast(name_size))],
            .data = self.data[data_off..data_off + @as(usize, @intCast(file_size))],
        };
    }
};

