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
    exe.linkSystemLibrary("LLVM-22");

    // Add rpath for runtime library loading
    exe.addRPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });

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
    lib_tests.linkSystemLibrary("LLVM-22");

    // Add rpath for runtime library loading
    lib_tests.addRPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });

    if (enable_lto) {
        lib_tests.want_lto = true;
    }

    const run_lib_tests = b.addRunArtifact(lib_tests);
    run_lib_tests.step.dependOn(b.getInstallStep());
    test_step.dependOn(&run_lib_tests.step);

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
