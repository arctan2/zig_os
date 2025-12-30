const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .arm,
        .os_tag = .freestanding,
        .abi = .eabi,
    });

    const isDebugModeOptimize = false;

    const init = b.createModule(.{
        .root_source_file = b.path("init.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
        .imports = &.{
        }
    });

    const exe = b.addExecutable(.{
        .name = "init",
        .root_module = init
    });

    exe.bundle_compiler_rt = true;

    b.installArtifact(exe);

    const art = b.addInstallArtifact(exe, .{});

    const CPIO = "initramfs_img.cpio";

    const cpio = b.addSystemCommand(&.{"sh", "-c", "find ./bin -depth -print0 | cpio -oH newc -0v > " ++ CPIO});
    cpio.setCwd(b.path("./zig-out"));
    cpio.step.dependOn(&art.step);
    b.getInstallStep().dependOn(&cpio.step);

    const objcopy = b.addSystemCommand(&.{"sh", "-c", "arm-linux-gnueabi-objcopy -I binary -O elf32-littlearm -B arm " ++ CPIO ++ " initramfs.o"});
    objcopy.setCwd(b.path("./zig-out"));
    objcopy.step.dependOn(&cpio.step);
    b.getInstallStep().dependOn(&objcopy.step);
}
