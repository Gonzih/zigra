const std = @import("std");

const examples = [_]Program{
    .{
        .name = "hello",
        .path = "examples/hello/main.zig",
        .desc = "Hello world",
    },
};

pub fn buildExamples(b: *std.build.Builder, mode: std.builtin.Mode) void {
    const target = b.standardTargetOptions(.{});
    const examples_step = b.step("examples", "Builds all the examples");

    for (examples) |ex| {
        const exe = b.addExecutable(ex.name, ex.path);
        const exe_step = &exe.step;

        exe.setBuildMode(mode);
        exe.setTarget(target);
        exe.install();
        exe.use_stage1 = ex.fstage1;

        exe.addPackage(std.build.Pkg{
            .name = "zigra",
            .source = std.build.FileSource.relative("src/main.zig"),
        });

        const run_cmd = exe.run();
        const run_step = b.step(ex.name, ex.desc);
        const artifact_step = &b.addInstallArtifact(exe).step;
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        run_step.dependOn(artifact_step);
        run_step.dependOn(&run_cmd.step);
        examples_step.dependOn(exe_step);
        examples_step.dependOn(artifact_step);
    }
}

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    buildExamples(b, mode);

    const lib = b.addStaticLibrary("zigra", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    const main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}

const Program = struct {
    name: []const u8,
    path: []const u8,
    desc: []const u8,
    fstage1: bool = false,
};
