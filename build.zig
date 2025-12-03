const std = @import("std");
const tests = @import("tests.zig");

fn runCommands(b: *std.Build) void {
    // const dtb = "./device_trees/kernel.dtb";
    const kernel_bin = "zig-out/bin/kernel";

    const run_command = [_][]const u8 {
        "qemu-system-arm",
        "-M", "virt,gic-version=2",
        "-cpu", "cortex-a7",
        "-nographic",
        "-m", "512",
        "-kernel", kernel_bin,
    };

    const run = b.addSystemCommand(&run_command);
    run.step.dependOn(b.getInstallStep());
    b.step("run", "run kernel in QEMU").dependOn(&run.step);

    const drun = b.addSystemCommand(&(run_command ++ .{"-s", "-S"}));
    drun.step.dependOn(b.getInstallStep());
    b.step("drun", "run in qemu for gdb").dependOn(&drun.step);

    const gdb = b.addSystemCommand(&.{"gdb-multiarch", "zig-out/bin/kernel", "-tui", "-x", "init.gdb"});
    gdb.step.dependOn(b.getInstallStep());
    b.step("gdb", "run gdb").dependOn(&gdb.step);

    const objdump_input = b.option([]const u8, "dump_to", "objdump to file") orelse "dump.S";
    const objdump = b.addSystemCommand(&.{"arm-linux-gnueabihf-objdump", "-d", "./zig-out/bin/kernel"});
    const dump_file = objdump.captureStdOut();
    const install_dump = b.addInstallFile(dump_file, objdump_input);
    objdump.step.dependOn(b.getInstallStep());
    b.step("objdump", "generate disassembly dump").dependOn(&install_dump.step);

    const objcopy = b.addSystemCommand(&.{"zig", "objcopy", "-O", "binary", "zig-out/bin/kernel", "zig-out/bin/kernel.bin"});
    objcopy.step.dependOn(b.getInstallStep());
    b.step("objcopy", "objcopy to binary file").dependOn(&objcopy.step);
}

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .arm,
        .os_tag = .freestanding,
        .abi = .eabi,
    });

    const isDebugModeOptimize = true;

    const mmio = b.createModule(.{
        .root_source_file = b.path("src/mmio/mmio.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
    });

    const uart = b.createModule(.{
        .root_source_file = b.path("src/mmio/uart.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
        .imports = &.{
            .{.name = "mmio", .module = mmio},
        }
    });

    const utils = b.createModule(.{
        .root_source_file = b.path("src/utils/utils.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
    });

    const atomic = b.createModule(.{
        .root_source_file = b.path("src/atomic/atomic.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
        .imports = &.{
        }
    });

    const fdt = b.createModule(.{
        .root_source_file = b.path("src/fdt/fdt.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
        .imports = &.{
            .{.name = "utils", .module = utils},
            .{.name = "uart", .module = uart},
        }
    });

    const arm = b.createModule(.{
        .root_source_file = b.path("src/arm/arm.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
        .imports = &.{
            .{.name = "uart", .module = uart},
            .{.name = "fdt", .module = fdt},
        }
    });

    const mm = b.createModule(.{
        .root_source_file = b.path("src/mm/mm.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
        .imports = &.{
            .{.name = "utils", .module = utils},
            .{.name = "uart", .module = uart},
            .{.name = "arm", .module = arm},
            .{.name = "fdt", .module = fdt},
            .{.name = "atomic", .module = atomic},
        }
    });

    mmio.addImport("mm", mm);
    mmio.addImport("uart", uart);
    mmio.addImport("fdt", fdt);
    mmio.addImport("utils", utils);

    const devices = b.createModule(.{
        .root_source_file = b.path("src/devices/devices.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
        .imports = &.{
            .{.name = "utils", .module = utils},
            .{.name = "uart", .module = uart},
            .{.name = "arm", .module = arm},
            .{.name = "fdt", .module = fdt},
            .{.name = "mmio", .module = mmio},
        }
    });

    const fs = b.createModule(.{
        .root_source_file = b.path("src/fs/fs.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
        .imports = &.{
            .{.name = "utils", .module = utils},
            .{.name = "uart", .module = uart},
        }
    });

    const vfs = b.createModule(.{
        .root_source_file = b.path("src/vfs/vfs.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
        .imports = &.{
            .{.name = "utils", .module = utils},
            .{.name = "uart", .module = uart},
            .{.name = "fs", .module = fs},
        }
    });

    const syscall = b.createModule(.{
        .root_source_file = b.path("src/kernel/syscall/syscall.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
        .imports = &.{
            .{.name = "utils", .module = utils},
            .{.name = "uart", .module = uart},
            .{.name = "arm", .module = arm},
            .{.name = "fdt", .module = fdt},
            .{.name = "mmio", .module = mmio},
        }
    });

    const kernel = b.createModule(.{
        .root_source_file = b.path("src/kernel/main.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
        .imports = &.{
            .{.name = "uart", .module = uart},
            .{.name = "mm", .module = mm},
            .{.name = "arm", .module = arm},
            .{.name = "fdt", .module = fdt},
            .{.name = "utils", .module = utils},
            .{.name = "mmio", .module = mmio},
            .{.name = "devices", .module = devices},
            .{.name = "syscall", .module = syscall},
            .{.name = "vfs", .module = vfs},
            .{.name = "fs", .module = fs},
        }
    });

    kernel.addObjectFile(b.path("./ramdisk/zig-out/initramfs.o"));

    const exe = b.addExecutable(.{
        .name = "kernel",
        .root_module = kernel
    });

    exe.setLinkerScript(b.path("./linker.ld"));
    exe.bundle_compiler_rt = true;
    exe.addAssemblyFile(b.path("./src/asm/vector_table.S"));
    exe.addAssemblyFile(b.path("./src/asm/start.S"));
    exe.addAssemblyFile(b.path("./src/asm/early_kernel.S"));

    b.installArtifact(exe);

    tests.runTests(b);
    runCommands(b);
}

