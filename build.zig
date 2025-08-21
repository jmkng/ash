const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scout = b.dependency("scout", .{});
    const scout_module = scout.module("scout");

    const root = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_unit_tests = b.addTest(.{
        .root_module = root,
    });
    lib_unit_tests.root_module.addImport("scout", scout_module);
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    b.installDirectory(.{
        .source_dir = lib_unit_tests.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "doc",
    });
}
