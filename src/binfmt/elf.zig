const std = @import("std");
const fs = @import("fs");
const vfs = @import("vfs");
const vma = @import("mm").vma;
const uart = @import("uart");

const Self = @This();


fn getArchElfHeader() type {
    const ElfAddr = u32;
    const ElfOff = u32;
    const EI_NIDENT = 16;

    const EI = enum(usize) {
        CLASS = 4,
        DATA = 5,
        VERSION = 6,
        PAD = 7,
        NIDENT = 16, // Size of e_ident[]
    };

    const ELF_MAG = [_]u8{ 0x7f, 'E', 'L', 'F' };
    const ELF_CLASS = enum(usize){ NONE = 0, _32 = 1, _64 = 2 };
    const ELF_DATA = enum(usize) { NONE = 0, LSB = 1, MSB = 2 };

    const SupportedMachines = enum(u16) {
        ARM32 = 40
    };


    return extern struct {
        e_ident: [EI_NIDENT]u8,
        e_type: u16,
        e_machine: u16,
        e_version: u32,
        e_entry: ElfAddr,
        e_phoff: ElfOff,
        e_shoff: ElfOff,
        e_flags: u32,
        e_ehsize: u16,
        e_phentsize: u16,
        e_phnum: u16,
        e_shentsize: u16,
        e_shnum: u16,
        e_shstrndx: u16,

        fn validate(self: *ElfHeader) !void {
            for(0..ELF_MAG.len) |i| if(self.e_ident[i] != ELF_MAG[i]) return error.InvalidHeader;
            if(self.e_ident[@intFromEnum(EI.CLASS)] != @intFromEnum(ELF_CLASS._32)) return error.UnsupportedClass;
            if(self.e_ident[@intFromEnum(EI.VERSION)] != 1) return error.UnsupportedVersion;
            if(self.e_ident[@intFromEnum(EI.DATA)] != @intFromEnum(ELF_DATA.LSB)) return error.UnsupportedData;
            if(self.e_machine != @intFromEnum(SupportedMachines.ARM32)) return error.UnsupportedMachine;
        }
    };
}

pub const ElfHeader = getArchElfHeader();

file: *fs.File,
header: *ElfHeader,

pub fn init(allocator: std.mem.Allocator, file: *fs.File) !Self {
    const header: *ElfHeader = try allocator.create(ElfHeader);
    errdefer allocator.destroy(header);

    file.offset = 0;
    const read_count = try vfs.read(file, std.mem.asBytes(header));
    if(read_count != @sizeOf(ElfHeader)) return error.InvalidFile;

    try header.validate();

    return .{
        .file = file,
        .header = header
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.destroy(self.header);
}

// pub fn loadSegments(self: *Self, vaddr_space: *vma.VirtAddrSpace) !void {
// }

