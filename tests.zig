const std = @import("std");

pub fn runTests(b: *std.Build) void {
    const test_step = b.step("test", "Run unit tests");
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .arm,
        .abi = .eabi,
    });

    const tests_filter: []const []const u8 = &.{ b.option([]const u8, "test_filter", "filter test") orelse "" };

    const utils = b.createModule(.{
        .root_source_file = b.path("src/utils/utils.zig"),
        .target = target,
    });
    
    const vma = b.createModule(.{
        .root_source_file = b.path("./src/mm/mm.zig"),
        .target = target,
        .imports = &.{
            .{.name = "utils", .module = utils},
        }
    });

    const lib = b.createModule(.{
        .root_source_file = b.path("./src/lib/lib.zig"),
        .target = target,
        .imports = &.{
            .{.name = "utils", .module = utils},
        }
    });

    const tests: [2]*std.Build.Step.Compile = .{
        b.addTest(.{ .root_module = vma, .filters = tests_filter }),
        b.addTest(.{ .root_module = lib, .filters = tests_filter }),
    };

    for(tests) |t| {
        const run_unit_tests = b.addRunArtifact(t);
        test_step.dependOn(&run_unit_tests.step);
    }
}
