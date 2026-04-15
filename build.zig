const std = @import("std");

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
        "Path to LLVM installation (default: /opt/homebrew/Cellar/llvm/22.1.3)",
    ) orelse "/opt/homebrew/Cellar/llvm/22.1.3";

    const llvm_version = b.option(
        []const u8,
        "llvm-version",
        "LLVM version to link against (default: 22)",
    ) orelse "22";

    // Create library module for OmniScope
    const lib_mod = b.addModule("OmniScope", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // Add LLVM include path to all steps
    lib_mod.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "include" }) });

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

    // Add LLVM include path
    exe.root_module.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "include" }) });

    // Add LLVM library path and link LLVM library
    exe.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("z");

    // Link LLVM library with version suffix
    const llvm_lib_name = b.fmt("LLVM-{s}", .{llvm_version});
    exe.linkSystemLibrary(llvm_lib_name);

    // Add rpath for runtime library loading
    exe.addRPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });

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
    verify_exe.root_module.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "include" }) });
    verify_exe.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });
    verify_exe.linkSystemLibrary("c");
    verify_exe.linkSystemLibrary("z");
    verify_exe.linkSystemLibrary(llvm_lib_name);
    verify_exe.addRPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });
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
    demo_exe.root_module.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "include" }) });
    demo_exe.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });
    demo_exe.linkSystemLibrary("c");
    demo_exe.linkSystemLibrary("z");
    demo_exe.linkSystemLibrary(llvm_lib_name);
    demo_exe.addRPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });
    const demo_cmd = b.addRunArtifact(demo_exe);
    demo_step.dependOn(&demo_cmd.step);

    // Benchmark step
    const bench_step = b.step("bench", "Run benchmarks");
    const bench_exe = b.addExecutable(.{
        .name = "benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("./benchs/benchmark.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "OmniScope", .module = lib_mod },
            },
        }),
    });
    bench_exe.root_module.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "include" }) });
    bench_exe.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });
    bench_exe.linkSystemLibrary("c");
    bench_exe.linkSystemLibrary("z");
    bench_exe.linkSystemLibrary(llvm_lib_name);
    bench_exe.addRPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });
    const bench_cmd = b.addRunArtifact(bench_exe);
    bench_step.dependOn(&bench_cmd.step);

    // Benchmark data compilation step
    const bench_compile_step = b.step("bench-compile", "Compile real code for benchmarking");

    // Create output directory
    const mkdir_cmd = b.addSystemCommand(&[_][]const u8{ "mkdir", "-p", "zig-out/bench_data" });
    bench_compile_step.dependOn(&mkdir_cmd.step);

    // Compile sample_analysis.c to LLVM IR
    const compile_sample_analysis = b.addSystemCommand(&[_][]const u8{ "clang", "-S", "-emit-llvm", "-O1", "-o", "zig-out/bench_data/sample_analysis.ll", "examples/sample_analysis.c" });
    compile_sample_analysis.step.dependOn(&mkdir_cmd.step);
    bench_compile_step.dependOn(&compile_sample_analysis.step);

    // Compile logic_bugs.c to LLVM IR
    const compile_logic_bugs = b.addSystemCommand(&[_][]const u8{ "clang", "-S", "-emit-llvm", "-O1", "-o", "zig-out/bench_data/logic_bugs.ll", "examples/logic_bugs.c" });
    compile_logic_bugs.step.dependOn(&mkdir_cmd.step);
    bench_compile_step.dependOn(&compile_logic_bugs.step);

    // Compile ntt.c to LLVM IR
    const compile_ntt = b.addSystemCommand(&[_][]const u8{ "clang", "-S", "-emit-llvm", "-O1", "-o", "zig-out/bench_data/ntt.ll", "examples/ntt.c" });
    compile_ntt.step.dependOn(&mkdir_cmd.step);
    bench_compile_step.dependOn(&compile_ntt.step);

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

    // Add LLVM configuration to tests
    lib_tests.root_module.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "include" }) });
    lib_tests.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });
    lib_tests.linkSystemLibrary("c");
    lib_tests.linkSystemLibrary("z");
    lib_tests.linkSystemLibrary(llvm_lib_name);

    // Add rpath for runtime library loading
    lib_tests.addRPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });

    if (enable_lto) {
        lib_tests.want_lto = true;
    }

    const run_lib_tests = b.addRunArtifact(lib_tests);
    run_lib_tests.step.dependOn(b.getInstallStep());
    test_step.dependOn(&run_lib_tests.step);

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
    integration_tests.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });
    integration_tests.linkSystemLibrary("c");
    integration_tests.linkSystemLibrary("z");
    integration_tests.linkSystemLibrary(llvm_lib_name);
    integration_tests.addRPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });
    if (enable_lto) {
        integration_tests.want_lto = true;
    }
    const run_integration_tests = b.addRunArtifact(integration_tests);
    run_integration_tests.step.dependOn(b.getInstallStep());
    integration_test_step.dependOn(&run_integration_tests.step);

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
    e2e_tests.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });
    e2e_tests.linkSystemLibrary("c");
    e2e_tests.linkSystemLibrary("z");
    e2e_tests.linkSystemLibrary(llvm_lib_name);
    e2e_tests.addRPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });
    if (enable_lto) {
        e2e_tests.want_lto = true;
    }
    const run_e2e_tests = b.addRunArtifact(e2e_tests);
    run_e2e_tests.step.dependOn(b.getInstallStep());
    e2e_test_step.dependOn(&run_e2e_tests.step);

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

    // Help information
    const help_step = b.step("help", "Show build options");
    help_step.dependOn(&b.addSystemCommand(&.{
        b.graph.zig_exe,
        "build",
        "--help",
    }).step);
}
