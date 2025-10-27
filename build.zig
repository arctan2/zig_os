const std = @import("std");

fn runTests(b: *std.Build) void {
    const test_step = b.step("test", "Run unit tests");

    const utils = b.createModule(.{
        .root_source_file = b.path("src/utils/utils.zig"),
        .target = b.resolveTargetQuery(.{}),
    });
    
    const mm = b.createModule(.{
        .root_source_file = b.path("./src/mm/page_alloc.zig"),
        .target = b.resolveTargetQuery(.{}),
        .imports = &.{
            .{.name = "utils", .module = utils},
        }
    });

    const unit_tests = b.addTest(.{
        .root_module = mm,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);
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
        .root_source_file = b.path("src/uart/uart.zig"),
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

    const arm = b.createModule(.{
        .root_source_file = b.path("src/arm/arm.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
        .imports = &.{
            .{.name = "uart", .module = uart},
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

    const mm = b.createModule(.{
        .root_source_file = b.path("src/mm/mm.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
        .imports = &.{
            .{.name = "utils", .module = utils},
            .{.name = "uart", .module = uart},
            .{.name = "arm", .module = arm},
            .{.name = "fdt", .module = fdt},
        }
    });

    mmio.addImport("mm", mm);
    mmio.addImport("uart", uart);
    mmio.addImport("fdt", fdt);

    const virt_kernel = b.createModule(.{
        .root_source_file = b.path("src/virt_kernel/main.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
        .imports = &.{
            .{.name = "uart", .module = uart},
            .{.name = "mm", .module = mm},
            .{.name = "arm", .module = arm},
            .{.name = "fdt", .module = fdt},
            .{.name = "utils", .module = utils},
            .{.name = "mmio", .module = mmio},
        }
    });

    const root_module = b.createModule(.{
        .root_source_file = b.path("./src/kernel.zig"),
        .target = target,
        .optimize = if(isDebugModeOptimize) .Debug else .ReleaseSafe,
        .imports = &.{
            .{.name = "utils", .module = utils},
            .{.name = "uart", .module = uart},
            .{.name = "virt_kernel", .module = virt_kernel},
            .{.name = "fdt", .module = fdt},
        }
    });

    const exe = b.addExecutable(.{
        .name = "kernel",
        .root_module = root_module
    });

    exe.setLinkerScript(b.path("./src/linker.ld"));
    exe.bundle_compiler_rt = true;
    exe.addAssemblyFile(b.path("./src/start.S"));

    const exe_gdb = b.addExecutable(.{
        .name = "kernel_gdb",
        .root_module = root_module
    });

    exe_gdb.setLinkerScript(b.path("./src/linker_gdb.ld"));
    exe_gdb.bundle_compiler_rt = true;

    b.installArtifact(exe);
    b.installArtifact(exe_gdb);

    runTests(b);
}
