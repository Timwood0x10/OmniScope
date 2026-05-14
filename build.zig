const std = @import("std");

/// Get the default LLVM path for the current OS
fn getDefaultLLVMPath() []const u8 {
    const os = @import("builtin").os.tag;

    return switch (os) {
        .macos => "/opt/homebrew/opt/llvm",
        .linux => "/usr/lib/llvm-22",
        .windows => "C:\\Program Files\\LLVM",
        else => "/usr/lib/llvm-22",
    };
}

/// Get the default LLVM version for the current OS
fn getDefaultLLVMVersion() []const u8 {
    return "22";
}

/// Configure a Step.Compile with LLVM include/library/rpath/link settings.
fn configureLLVM(b: *std.Build, compile: *std.Build.Step.Compile, llvm_path: []const u8, llvm_version: []const u8) void {
    const lib_name = b.fmt("LLVM-{s}", .{llvm_version});
    const include = b.pathJoin(&.{ llvm_path, "include" });
    const lib = b.pathJoin(&.{ llvm_path, "lib" });
    compile.root_module.addIncludePath(.{ .cwd_relative = include });
    compile.root_module.addLibraryPath(.{ .cwd_relative = lib });
    compile.root_module.linkSystemLibrary("c", .{});
    compile.root_module.linkSystemLibrary("z", .{});
    compile.root_module.linkSystemLibrary(lib_name, .{});
    compile.root_module.addRPath(.{ .cwd_relative = lib });
}

/// Build configuration for OmniScope
pub fn build(b: *std.Build) void {
    // Parse build options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_lto = b.option(
        bool,
        "enable-lto",
        "Enable Link Time Optimization (default: false)",
    ) orelse false;

    // LLVM configuration
    const llvm_path = b.option(
        []const u8,
        "llvm-path",
        b.fmt("Path to LLVM installation (default: auto-detect based on OS: {s})", .{getDefaultLLVMPath()}),
    ) orelse getDefaultLLVMPath();

    const llvm_version = b.option(
        []const u8,
        "llvm-version",
        b.fmt("LLVM version to link against (default: {s})", .{getDefaultLLVMVersion()}),
    ) orelse getDefaultLLVMVersion();

    // Create library module for OmniScope
    const lib_mod = b.addModule("OmniScope", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    lib_mod.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "include" }) });

    // Build main executable
    const exe = b.addExecutable(.{
        .name = "OmniScope",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "OmniScope", .module = lib_mod },
            },
        }),
    });

    configureLLVM(b, exe, llvm_path, llvm_version);

    // Apply LTO if enabled
    if (enable_lto) {
        exe.want_lto = true;
    }

    b.installArtifact(exe);

    // Verification step for IR loading
    const verify_step = b.step("verify-ir", "Verify IR loading functionality");
    const verify_exe = b.addExecutable(.{
        .name = "verify_ir_loading",
        .root_module = b.createModule(.{
            .root_source_file = b.path("verify_ir_loading.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "OmniScope", .module = lib_mod },
            },
        }),
    });
    configureLLVM(b, verify_exe, llvm_path, llvm_version);
    const verify_cmd = b.addRunArtifact(verify_exe);
    verify_step.dependOn(&verify_cmd.step);

    // Demo step
    const demo_step = b.step("demo", "Run the analysis demo");
    const demo_exe = b.addExecutable(.{
        .name = "demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/demo_analysis.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "OmniScope", .module = lib_mod },
            },
        }),
    });
    configureLLVM(b, demo_exe, llvm_path, llvm_version);
    const demo_cmd = b.addRunArtifact(demo_exe);
    demo_step.dependOn(&demo_cmd.step);

    // Run step
    const run_step = b.step("run", "Run the application");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Test step - test the library module with proper output
    const test_step = b.step("test", "Run all tests");
    const lib_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    configureLLVM(b, lib_tests, llvm_path, llvm_version);

    if (enable_lto) {
        lib_tests.want_lto = true;
    }

    const run_lib_tests = b.addRunArtifact(lib_tests);
    run_lib_tests.step.dependOn(b.getInstallStep());
    test_step.dependOn(&run_lib_tests.step);

    // Unit tests step
    const unit_test_step = b.step("unit-test", "Run unit tests");
    const unit_test_mod = b.addModule("unit_test", .{
        .root_source_file = b.path("tests/main.zig"),
        .target = target,
    });
    unit_test_mod.addImport("OmniScope", lib_mod);
    const unit_tests = b.addTest(.{
        .root_module = unit_test_mod,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    unit_test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_unit_tests.step);

    // Benchmark step
    const bench_perf_step = b.step("bench-perf", "Run performance benchmarks");
    const bench_mod = b.addModule("bench", .{
        .root_source_file = b.path("benches/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench_mod.addImport("OmniScope", lib_mod);
    const bench_tests = b.addTest(.{
        .root_module = bench_mod,
    });
    const run_bench_tests = b.addRunArtifact(bench_tests);
    bench_perf_step.dependOn(&run_bench_tests.step);

    // Alias 'bench' to 'bench-perf' for convenience
    const bench_step = b.step("bench", "Run performance benchmarks (alias for bench-perf)");
    bench_step.dependOn(bench_perf_step);

    // Benchmark comparison step
    const bench_compare_step = b.step("bench-compare", "Run performance comparison benchmarks");
    const bench_compare_mod = b.addModule("bench_compare", .{
        .root_source_file = b.path("src/perf/bench_compare.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench_compare_mod.addImport("OmniScope", lib_mod);
    const bench_compare_exe = b.addExecutable(.{
        .name = "bench-compare",
        .root_module = bench_compare_mod,
    });
    const bench_compare_run = b.addRunArtifact(bench_compare_exe);
    bench_compare_step.dependOn(&bench_compare_run.step);

    // Integration tests step
    const integration_test_step = b.step("integration-test", "Run integration tests with real IR files");
    const integration_test_mod = b.addModule("integration_test", .{
        .root_source_file = b.path("tests/integration_ir_test.zig"),
        .target = target,
    });
    integration_test_mod.addImport("OmniScope", lib_mod);
    integration_test_mod.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "include" }) });
    const integration_tests = b.addTest(.{
        .root_module = integration_test_mod,
    });
    configureLLVM(b, integration_tests, llvm_path, llvm_version);
    if (enable_lto) {
        integration_tests.want_lto = true;
    }
    const run_integration_tests = b.addRunArtifact(integration_tests);
    run_integration_tests.step.dependOn(b.getInstallStep());
    integration_test_step.dependOn(&run_integration_tests.step);

    // Test integration step (new integration test suite)
    const test_integration_step = b.step("test-integration", "Run integration test suite");
    const test_integration_mod = b.addModule("test_integration", .{
        .root_source_file = b.path("tests/integration/main.zig"),
        .target = target,
    });
    test_integration_mod.addImport("OmniScope", lib_mod);
    const test_integration_tests = b.addTest(.{
        .root_module = test_integration_mod,
    });
    const run_test_integration_tests = b.addRunArtifact(test_integration_tests);
    test_integration_step.dependOn(&run_test_integration_tests.step);

    // Issue verification tests step
    const issue_verify_step = b.step("test-issues", "Run issue verification tests");
    const issue_verify_mod = b.addModule("issue_verify", .{
        .root_source_file = b.path("tests/integration/issue_verification.zig"),
        .target = target,
    });
    issue_verify_mod.addImport("OmniScope", lib_mod);
    const issue_verify_tests = b.addTest(.{
        .root_module = issue_verify_mod,
    });
    const run_issue_verify_tests = b.addRunArtifact(issue_verify_tests);
    issue_verify_step.dependOn(&run_issue_verify_tests.step);

    // Stability tests step
    const stability_test_step = b.step("test-stability", "Run stability tests (crash-free, malformed input)");
    const stability_test_mod = b.addModule("stability_test", .{
        .root_source_file = b.path("tests/stability/main.zig"),
        .target = target,
    });
    stability_test_mod.addImport("OmniScope", lib_mod);
    const stability_tests = b.addTest(.{
        .root_module = stability_test_mod,
    });
    const run_stability_tests = b.addRunArtifact(stability_tests);
    stability_test_step.dependOn(&run_stability_tests.step);

    // Stress tests step
    const stress_test_step = b.step("test-stress", "Run stress tests (large scale, boundary, fuzz)");
    const stress_test_mod = b.addModule("stress_test", .{
        .root_source_file = b.path("tests/stress/main.zig"),
        .target = target,
    });
    stress_test_mod.addImport("OmniScope", lib_mod);
    const stress_tests = b.addTest(.{
        .root_module = stress_test_mod,
    });
    const run_stress_tests = b.addRunArtifact(stress_tests);
    stress_test_step.dependOn(&run_stress_tests.step);

    // E2E tests step
    const e2e_test_step = b.step("e2e-test", "Run end-to-end tests with real IR and Pipeline");
    const e2e_test_mod = b.addModule("e2e_test", .{
        .root_source_file = b.path("tests/e2e_ir_test.zig"),
        .target = target,
    });
    e2e_test_mod.addImport("OmniScope", lib_mod);
    e2e_test_mod.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "include" }) });
    const e2e_tests = b.addTest(.{
        .root_module = e2e_test_mod,
    });
    configureLLVM(b, e2e_tests, llvm_path, llvm_version);
    if (enable_lto) {
        e2e_tests.want_lto = true;
    }
    const run_e2e_tests = b.addRunArtifact(e2e_tests);
    run_e2e_tests.step.dependOn(b.getInstallStep());
    e2e_test_step.dependOn(&run_e2e_tests.step);

    // Benchmark performance tests step
    const bench_test_step = b.step("test-benchmark", "Run performance benchmark tests (latency, memory, throughput)");
    const bench_test_mod = b.addModule("bench_test", .{
        .root_source_file = b.path("tests/benchmark/main.zig"),
        .target = target,
    });
    bench_test_mod.addImport("OmniScope", lib_mod);
    const bench_perf_tests = b.addTest(.{
        .root_module = bench_test_mod,
    });
    const run_bench_perf_tests = b.addRunArtifact(bench_perf_tests);
    bench_test_step.dependOn(&run_bench_perf_tests.step);

    // Help information
    const help_step = b.step("help", "Show build options");
    help_step.dependOn(&b.addSystemCommand(&.{
        b.graph.zig_exe,
        "build",
        "--help",
    }).step);

    // Check step - type check without linking
    const check_step = b.step("check", "Type check the project");
    const check_exe = b.addExecutable(.{
        .name = "check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "OmniScope", .module = lib_mod },
            },
        }),
    });
    check_exe.root_module.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "include" }) });
    check_step.dependOn(&check_exe.step);
}
