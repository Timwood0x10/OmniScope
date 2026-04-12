const std = @import("std");

/// Build configuration for OmniScope
///
/// This build script supports the following options:
///   -Doptimize=[Debug|ReleaseSafe|ReleaseFast|ReleaseSmall]
///   -Denable-lto=true (enable Link Time Optimization)
///   -Dtarget=<triple> (target platform)
pub fn build(b: *std.Build) void {
    // Parse build options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_lto = b.option(
        bool,
        "enable-lto",
        "Enable Link Time Optimization (default: false)",
    ) orelse false;

    // Create library module for OmniScope
    const lib_mod = b.addModule("OmniScope", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // Build main executable
    const exe = b.addExecutable(.{
        .name = "OmniSope",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "OmniScope", .module = lib_mod },
            },
        }),
    });

    // Apply LTO if enabled
    if (enable_lto) {
        exe.want_lto = true;
    }

    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run the application");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Test steps
    const lib_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    if (enable_lto) {
        lib_tests.want_lto = true;
    }

    const run_lib_tests = b.addRunArtifact(lib_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Build runtime library as a static library
    const rt_lib = b.addLibrary(.{
        .name = "omniscope_rt",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/runtime/rt_lib/probes.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    if (enable_lto) {
        rt_lib.want_lto = true;
    }

    b.installArtifact(rt_lib);

    // Step to build runtime library
    const build_rt_step = b.step("rt", "Build runtime library");
    build_rt_step.dependOn(&b.addInstallArtifact(rt_lib, .{}).step);

    // Benchmark step (if ReleaseFast)
    if (optimize == .ReleaseFast) {
        const bench_step = b.step("bench", "Run benchmarks");
        const bench_exe = b.addExecutable(.{
            .name = "bench",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = .ReleaseFast,
                .imports = &.{
                    .{ .name = "OmniScope", .module = lib_mod },
                },
            }),
        });

        if (enable_lto) {
            bench_exe.want_lto = true;
        }

        const run_bench = b.addRunArtifact(bench_exe);
        bench_step.dependOn(&run_bench.step);
        run_bench.step.dependOn(b.getInstallStep());
    }

    // Help information
    const help_step = b.step("help", "Show build options");
    help_step.dependOn(&b.addSystemCommand(&.{
        b.graph.zig_exe,
        "build",
        "--help",
    }).step);
}
