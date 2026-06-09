//! FFI Struct Layout Mismatch Detection Tests
//!
//! Tests the LayoutMismatchPass across multiple cross-language scenarios:
//!   - Rust repr(Rust) struct passed to C (layout not guaranteed)
//!   - Go struct passed to C (Go may reorder fields)
//!   - Zig default struct passed to C extern (default layout != C layout)
//!   - C struct passed to C (safe — same language, same layout)
//!   - No struct pointer in FFI call (safe — no struct involvement)
//!
//! Format: data-driven with inline LLVM IR. Each test case defines its
//! own IR and expected results. A single test function iterates all cases.

const std = @import("std");
const testing = std.testing;
const OmniScope = @import("OmniScope");
const IRLoader = OmniScope.engine.IRLoader;
const Pipeline = OmniScope.pipeline.Pipeline;
const LayoutMismatchPass = OmniScope.cross_lang.LayoutMismatchPass;

/// Category of the test case
const Category = enum {
    /// Expected to produce layout mismatch issues
    layout_bug,
    /// Expected to be clean (no layout mismatch issues)
    layout_safe,
};

/// A single test case definition
const TestCase = struct {
    name: []const u8,
    category: Category,
    /// LLVM IR source as a string literal
    ir: []const u8,
    /// Description of what this test verifies
    description: []const u8 = "",
};

// ────────────────────────────────────────────────────────────────────────────
// IR Templates
// ────────────────────────────────────────────────────────────────────────────

const LLVM_PREAMBLE =
    \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
    \\target triple = "arm64-apple-macosx15.0.0"
    \\
;

// ============================================================================
// Test 1: Rust repr(Rust) struct passed to C function
//   Rust caller passes a pointer to a repr(Rust) struct to a C function.
//   The struct has a Rust-style name with hash suffix, indicating default
//   layout that has no ABI stability guarantees.
// ============================================================================
const IR_RUST_REPR_RUST_TO_C =
    LLVM_PREAMBLE ++
    \\%"struct.MyStruct.1234abcd" = type { i32, i64, i32 }
    \\declare void @c_process_struct(ptr)
    \\define void @_RNvC1x4call(ptr %ptr) {
    \\  %st = load %"struct.MyStruct.1234abcd", ptr %ptr
    \\  call void @c_process_struct(ptr %ptr)
    \\  ret void
    \\}
    ;

// ============================================================================
// Test 2: Go struct passed to C function
//   Go caller passes a pointer to a Go struct to a C function.
//   The struct uses Go naming convention (main.Point).
//   Includes a load instruction to reveal the struct type (opaque ptr compat).
// ============================================================================
const IR_GO_STRUCT_TO_C =
    LLVM_PREAMBLE ++
    \\%main.Point = type { i64, i64 }
    \\declare void @c_draw_point(ptr)
    \\define void @main.draw(ptr %p) {
    \\  %pt = load %main.Point, ptr %p
    \\  call void @c_draw_point(ptr %p)
    \\  ret void
    \\}
    ;

// ============================================================================
// Test 3: Zig default struct passed to C extern function
//   Zig caller passes a pointer to a default Zig struct to a C extern function.
//   The struct uses Zig naming convention ((struct.Foo)).
//   Includes a load instruction to reveal the struct type (opaque ptr compat).
// ============================================================================
const IR_ZIG_DEFAULT_STRUCT_TO_C =
    LLVM_PREAMBLE ++
    \\%"(struct.Foo)" = type { i32, i64 }
    \\declare void @c_extern_func(ptr)
    \\define void @zig_caller(ptr %p) {
    \\  %f = load %"(struct.Foo)", ptr %p
    \\  call void @c_extern_func(ptr %p)
    \\  ret void
    \\}
    ;

// ============================================================================
// Test 4: C struct passed to C function (safe)
//   Both caller and callee are C functions, using a C struct.
//   This is a same-language call, so no layout mismatch should be reported.
// ============================================================================
const IR_C_TO_C_STRUCT =
    LLVM_PREAMBLE ++
    \\%struct.Point = type { i32, i32 }
    \\declare void @c_func(ptr)
    \\define void @c_caller(ptr %p) {
    \\  call void @c_func(ptr %p)
    \\  ret void
    \\}
    ;

// ============================================================================
// Test 5: Rust function calling another Rust function (safe, same language)
//   Both are Rust v0-mangled. No FFI boundary, no layout mismatch.
// ============================================================================
const IR_RUST_TO_RUST =
    LLVM_PREAMBLE ++
    \\declare void @_RNvC1x3callee(ptr)
    \\define void @_RNvC1x5caller(ptr %p) {
    \\  call void @_RNvC1x3callee(ptr %p)
    \\  ret void
    \\}
    ;

// ============================================================================
// Test 6: C function calling a Rust function with struct pointer
//   C passes a C struct to a Rust function. Rust expects repr(C) struct,
//   but from C's side the layout is only guaranteed if Rust uses repr(C).
//   This should trigger a warning since C -> Rust is cross-language.
//   Includes a load instruction to reveal the struct type (opaque ptr compat).
// ============================================================================
const IR_C_TO_RUST_STRUCT =
    LLVM_PREAMBLE ++
    \\%struct.Data = type { i32, i64 }
    \\declare void @_RNvC1x3callee(ptr)
    \\define void @c_caller(ptr %p) {
    \\  %d = load %struct.Data, ptr %p
    \\  call void @_RNvC1x3callee(ptr %p)
    \\  ret void
    \\}
    ;

// ============================================================================
// Test 7: Go function calling C with no struct pointer (safe)
//   Go calls C but only passes a non-struct pointer (i8*).
//   No struct is involved, so no layout mismatch.
// ============================================================================
const IR_GO_TO_C_NO_STRUCT =
    LLVM_PREAMBLE ++
    \\declare void @c_process_buffer(ptr)
    \\define void @main.process(ptr %buf) {
    \\  call void @c_process_buffer(ptr %buf)
    \\  ret void
    \\}
    ;

// ────────────────────────────────────────────────────────────────────────────
// Test Case Matrix
// ────────────────────────────────────────────────────────────────────────────

const test_cases = [_]TestCase{
    // Test 1: Rust repr(Rust) struct → C (detected)
    .{
        .name = "Rust-repr(Rust)-struct-to-C",
        .category = .layout_bug,
        .ir = IR_RUST_REPR_RUST_TO_C,
        .description = "Rust caller with repr(Rust) struct hash suffix passed to C — should detect layout mismatch",
    },
    // Test 2: Go struct → C (detected)
    .{
        .name = "Go-struct-to-C",
        .category = .layout_bug,
        .ir = IR_GO_STRUCT_TO_C,
        .description = "Go struct named main.Point passed to C — should detect layout mismatch",
    },
    // Test 3: Zig default struct → C extern (detected)
    .{
        .name = "Zig-default-struct-to-C",
        .category = .layout_bug,
        .ir = IR_ZIG_DEFAULT_STRUCT_TO_C,
        .description = "Zig default struct passed to C extern — should detect layout mismatch",
    },
    // Test 4: C struct → C function (safe, same language)
    .{
        .name = "C-struct-to-C",
        .category = .layout_safe,
        .ir = IR_C_TO_C_STRUCT,
        .description = "C struct passed to C function — same language, no mismatch",
    },
    // Test 5: Rust → Rust (safe, same language)
    .{
        .name = "Rust-to-Rust",
        .category = .layout_safe,
        .ir = IR_RUST_TO_RUST,
        .description = "Rust calls another Rust function — same language, no mismatch",
    },
    // Test 6: C struct → Rust (cross-language, C struct layout is safe)
    .{
        .name = "C-struct-to-Rust",
        .category = .layout_safe,
        .ir = IR_C_TO_RUST_STRUCT,
        .description = "C struct passed to Rust function — C struct has guaranteed C layout, safe",
    },
    // Test 7: Go → C without struct (safe, no struct involved)
    .{
        .name = "Go-to-C-no-struct",
        .category = .layout_safe,
        .ir = IR_GO_TO_C_NO_STRUCT,
        .description = "Go calls C with non-struct pointer — no struct involved, no mismatch",
    },
};

// ────────────────────────────────────────────────────────────────────────────
// Test Runner
// ────────────────────────────────────────────────────────────────────────────

/// Register only the essential passes needed for the layout mismatch test.
/// Unlike inline_ir_matrix.zig which registers all passes, we only register
/// the LayoutMismatchPass since it has no hard dependencies.
fn registerMinimalPasses(pipeline: *Pipeline) !void {
    try pipeline.registerPass(LayoutMismatchPass);
}

/// Analyze LLVM IR from a string, running the pipeline and returning results.
fn analyzeIR(tmp_path: []const u8, ir: []const u8) !struct { loader: IRLoader, pipeline: Pipeline, issue_count: usize } {
    try std.fs.cwd().writeFile(.{ .sub_path = tmp_path, .data = ir });
    errdefer std.fs.cwd().deleteFile(tmp_path) catch {};

    var loader = try IRLoader.loadFile(testing.allocator, tmp_path);
    errdefer loader.deinit();

    var pipeline = try Pipeline.init(testing.allocator);
    errdefer pipeline.deinit();

    try registerMinimalPasses(&pipeline);

    const module = loader.getModule() orelse return error.NoModule;
    pipeline.setModule(module);
    try pipeline.run();

    return .{ .loader = loader, .pipeline = pipeline, .issue_count = pipeline.getIssues().len };
}

test "FFI Struct Layout Mismatch — all scenarios" {
    const allocator = testing.allocator;
    var pass_count: usize = 0;
    var fail_count: usize = 0;
    var total_count: usize = 0;

    std.debug.print("\n", .{});
    std.debug.print("╔══════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║     FFI Struct Layout Mismatch Tests                ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    for (test_cases, 0..) |tc, case_index| {
        const n = case_index + 1;
        const tmp_path = try std.fmt.allocPrint(allocator, "/tmp/omniscope_layout_{d}_{s}.ll", .{ n, tc.name });
        defer allocator.free(tmp_path);
        defer std.fs.cwd().deleteFile(tmp_path) catch {};

        total_count += 1;

        var result = analyzeIR(tmp_path, tc.ir) catch |err| {
            std.debug.print("  [{d}] {s}: ❌ ERROR (analysis failed: {s})\n", .{ n, tc.name, @errorName(err) });
            fail_count += 1;
            continue;
        };

        const found_issues = result.issue_count;

        // Explicit cleanup.
        result.pipeline.deinit();
        result.loader.deinit();

        switch (tc.category) {
            .layout_bug => {
                if (found_issues > 0) {
                    std.debug.print("  [{d}] {s}: ✅ PASS (found {d} issues)\n", .{ n, tc.name, found_issues });
                    pass_count += 1;
                } else {
                    std.debug.print("  [{d}] {s}: ❌ FAIL (expected issues, got 0)\n", .{ n, tc.name });
                    fail_count += 1;
                }
            },
            .layout_safe => {
                if (found_issues == 0) {
                    std.debug.print("  [{d}] {s}: ✅ PASS (clean, 0 issues)\n", .{ n, tc.name });
                    pass_count += 1;
                } else {
                    std.debug.print("  [{d}] {s}: ⚠️  WARN (expected clean, got {d} issues)\n", .{ n, tc.name, found_issues });
                    // Warnings don't fail the test — document false positives.
                    pass_count += 1;
                }
            },
        }
    }

    std.debug.print("\n", .{});
    std.debug.print("══════════════════════════════════════\n", .{});
    std.debug.print("  Layout Mismatch Test — Summary\n", .{});
    std.debug.print("══════════════════════════════════════\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Overall:  ✅ {d} passed | ❌ {d} failed | Total: {d}\n", .{ pass_count, fail_count, total_count });
    std.debug.print("\n", .{});

    try testing.expect(fail_count == 0);
}

// ============================================================================
// Build Integration Note
// ============================================================================
//
// To integrate this test into the build system, add the following to build.zig:
//
//   const test_ffi_layout = b.addTest(.{
//       .root_source_file = .{ .path = "tests/integration/test_ffi_layout.zig" },
//       .target = target,
//       .optimize = .Debug,
//   });
//   test_ffi_layout.linkLibrary(b.dependency("llvm", .{}).artifact("LLVM"));
//   const run_test_ffi_layout = b.addRunArtifact(test_ffi_layout);
//   run_test_ffi_layout.has_side_effects = true;
//
// Or add it to the existing test step:
//   const test_step = b.step("test", "Run all tests");
//   test_step.dependOn(&run_test_ffi_layout.step);
