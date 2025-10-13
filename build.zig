const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .arm,
        .os_tag = .freestanding,
        .abi = .eabi,
    });

    const uart = b.createModule(.{
        .root_source_file = b.path("src/uart/uart.zig"),
        .target = target,
        .optimize = .Debug,
        // .optimize = .ReleaseSafe,
    });

    const utils = b.createModule(.{
        .root_source_file = b.path("src/utils/utils.zig"),
        .target = target,
        .optimize = .Debug,
        // .optimize = .ReleaseSafe,
    });

    const mm = b.createModule(.{
        .root_source_file = b.path("src/mm/mm.zig"),
        .target = target,
        .optimize = .Debug,
        // .optimize = .ReleaseSafe,
        .imports = &.{
            .{.name = "utils", .module = utils},
            .{.name = "uart", .module = uart}
        }
    });

    const root_module = b.createModule(.{
        .root_source_file = b.path("./src/kernel.zig"),
        .target = target,
        .optimize = .Debug,
        // .optimize = .ReleaseSafe,
        .imports = &.{
            .{.name = "utils", .module = utils},
            .{.name = "uart", .module = uart},
            .{.name = "mm", .module = mm},
        }
    });

    const exe = b.addExecutable(.{
        .name = "kernel",
        .root_module = root_module
    });

    exe.setLinkerScript(b.path("./src/linker.ld"));
    exe.bundle_compiler_rt = true;
    exe.addAssemblyFile(b.path("./src/start.S"));

    b.installArtifact(exe);
}
