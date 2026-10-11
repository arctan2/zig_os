const std = @import("std");
const fs = @import("fs");
const vfs = @import("vfs");
const vma = @import("mm").vma;
const uart = @import("uart");

const Self = @This();

fn getArchElfHeader() type {
    const ElfHalf = u16;
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
        e_type: ElfHalf,
        e_machine: ElfHalf,
        e_version: usize,
        e_entry: usize,
        e_phoff: usize,
        e_shoff: usize,
        e_flags: usize,
        e_ehsize: ElfHalf,
        e_phentsize: ElfHalf,
        e_phnum: ElfHalf,
        e_shentsize: ElfHalf,
        e_shnum: ElfHalf,
        e_shstrndx: ElfHalf,

        fn validate(self: *ElfHeader) !void {
            for(0..ELF_MAG.len) |i| if(self.e_ident[i] != ELF_MAG[i]) return error.InvalidHeader;
            if(self.e_ident[@intFromEnum(EI.CLASS)] != @intFromEnum(ELF_CLASS._32)) return error.UnsupportedClass;
            if(self.e_ident[@intFromEnum(EI.VERSION)] != 1) return error.UnsupportedVersion;
            if(self.e_ident[@intFromEnum(EI.DATA)] != @intFromEnum(ELF_DATA.LSB)) return error.UnsupportedData;
            if(self.e_machine != @intFromEnum(SupportedMachines.ARM32)) return error.UnsupportedMachine;
        }
    };
}

const PT = enum(usize) {
    Null = 0,
    Load = 1,
    Dynamic = 2,
    Interp = 3,
    Note = 4,
    Shlib = 5,
    Phdr = 6,
    Loproc = 0x70000000,
    Hiproc = 0x7fffffff,
    _
};

const ElfProgramHeader = extern struct {
    p_type: PT,
    p_offset: usize,
    p_vaddr: usize,
    p_paddr: usize,
    p_filesz: usize,
    p_memsz: usize,
    p_flags: usize,
    p_align: usize,
};

pub const ElfHeader = getArchElfHeader();

file: *fs.File,
header: *ElfHeader,

pub fn init(allocator: std.mem.Allocator, file: *fs.File) !Self {
    const header: *ElfHeader = try allocator.create(ElfHeader);
    errdefer allocator.destroy(header);

    const read_count = try vfs.readAt(file, 0, std.mem.asBytes(header));
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

pub fn loadPTLoads(self: *Self, allocator: std.mem.Allocator, task_vma: *vma.VirtAddrSpace) !void {
    if(self.header.e_phentsize != @as(usize, @sizeOf(ElfProgramHeader))) return error.ProgramHeaderNotSupported;
    if(self.header.e_phoff == 0) return error.NoProgramHeader;

    const ph_list_size_bytes = self.header.e_phnum * self.header.e_phentsize;
    const buf = try allocator.alloc(u8, ph_list_size_bytes);
    defer allocator.free(buf);

    const read = try vfs.readAt(self.file, self.header.e_phoff, buf);
    if(read != ph_list_size_bytes) return error.UnexpectedEndOfFile;

    const ph_list: []ElfProgramHeader = @ptrCast(@alignCast(buf));

    for(ph_list) |p| switch(p.p_type) {
        .Load => _ = try task_vma.mmap(allocator, p.p_vaddr, p.p_memsz, .segment, self.file, p.p_offset),
        else => {}
    };
}

