const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .arm,
        .os_tag = .freestanding,
        .abi = .eabi,
    });

    const exe = b.addExecutable(.{
        .name = "kernel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("./src/kernel.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });

    exe.setLinkerScript(b.path("./src/linker.ld"));
    exe.bundle_compiler_rt = true;
    exe.addAssemblyFile(b.path("./src/start.S"));

    b.installArtifact(exe);
}
