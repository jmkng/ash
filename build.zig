const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scout = b.dependency("scout", .{});
    const scout_module = scout.module("scout");

    const ziglyph = b.dependency("ziglyph", .{
        .optimize = optimize,
        .target = target,
    });

    //const root = b.createModule(.{
    //    .root_source_file = b.path("src/root.zig"),
    //    .target = target,
    //    .optimize = optimize,
    //});
    //root.addImport("scout", scout_module);
    //root.addImport("ziglyph", ziglyph.module("ziglyph"));

    const default_test_filters = b.option([]const []const u8, "test-filter", "Skip tests that do not match any filter") orelse &[0][]const u8{};

    //const lib_unit_tests = b.addTest(.{
    //    .root_module = root,
    //    .filters = default_test_filters,
    //});

    //const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    //const test_step = b.step("test", "Run unit tests");
    //test_step.dependOn(&run_lib_unit_tests.step);

    // Additional steps for testing specific systems.
    const lexer_module = b.createModule(.{
        .root_source_file = b.path("src/lex.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexer_module.addImport("scout", scout_module);
    lexer_module.addImport("ziglyph", ziglyph.module("ziglyph"));
    const lexer_unit_tests = b.addTest(.{
        .root_module = lexer_module,
        .filters = default_test_filters,
    });
    const run_lexer_unit_tests = b.addRunArtifact(lexer_unit_tests);
    const lexer_test_step = b.step("test-lexer", "Run Lexer unit tests");
    lexer_test_step.dependOn(&run_lexer_unit_tests.step);

    //const install_docs_dir = b.addInstallDirectory(.{
    //    .source_dir = lib_unit_tests.getEmittedDocs(),
    //    .install_dir = .prefix,
    //    .install_subdir = "doc",
    //});

    //const docs_step = b.step("docs", "Copy documentation artifacts to prefix path");
    //docs_step.dependOn(&install_docs_dir.step);
}
