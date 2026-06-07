//! Integration tests for UnwindBoundaryPass — panic/unwind across FFI boundaries.
//!
//! Tests use inline LLVM IR strings loaded via IRLoader and then analyzed
//! by UnwindBoundaryPass directly (not through the full pipeline).
//!
//! Test scenarios:
//!   1. Rust extern "C" fn calling __rust_start_panic → should warn
//!   2. C++ extern "C" fn calling __cxa_throw → should warn
//!   3. Rust fn (no extern) calling panic — no FFI boundary → should NOT warn
//!   4. longjmp in non-C function → should warn
//!   5. C function calling C++ method that throws → should warn

const std = @import("std");
const OmniScope = @import("OmniScope");
const IRLoader = OmniScope.engine.IRLoader;
const Pipeline = OmniScope.pipeline.Pipeline;
const UnwindBoundaryPass = OmniScope.cross_lang.UnwindBoundaryPass;

/// Common LLVM IR preamble.
const LLVM_PREAMBLE =
    \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
    \\target triple = "arm64-apple-macosx15.0.0"
    \\
;

/// Test 1: Rust extern "C" function that panics — should be flagged.
const RUST_EXTERN_PANIC =
    LLVM_PREAMBLE ++
    \\define void @rust_extern_panic() {
    \\  call void @__rust_start_panic()
    \\  unreachable
    \\}
    \\declare void @__rust_start_panic()
    ;

/// Test 2: C++ extern "C" function that throws — should be flagged.
const CPP_EXTERN_THROW =
    LLVM_PREAMBLE ++
    \\define void @cpp_extern_throw() {
    \\  %ex = call ptr @__cxa_allocate_exception(i64 4)
    \\  call void @__cxa_throw(ptr %ex, ptr null, ptr null)
    \\  unreachable
    \\}
    \\declare ptr @__cxa_allocate_exception(i64)
    \\declare void @__cxa_throw(ptr, ptr, ptr)
    ;

/// Test 3: Rust function (no extern) calling panic — same-language, should NOT flag.
const RUST_INTERNAL_PANIC =
    LLVM_PREAMBLE ++
    \\define void @_RNvC1x3internal_panic() {
    \\  call void @_ZN4core9panicking5panic17h1234567890abcdefE()
    \\  unreachable
    \\}
    \\declare void @_ZN4core9panicking5panic17h1234567890abcdefE()
    ;

/// Test 4: longjmp in a function with C calling convention — pure C, should NOT flag.
const C_LONGJMP =
    LLVM_PREAMBLE ++
    \\define void @c_longjmp_test(ptr %env, i32 %val) {
    \\  call void @longjmp(ptr %env, i32 %val)
    \\  unreachable
    \\}
    \\declare void @longjmp(ptr, i32)
    ;

/// Test 5: longjmp in a Rust function — non-C context, should flag.
const RUST_LONGJMP =
    LLVM_PREAMBLE ++
    \\define void @_RNvC1x3rust_longjmp(ptr %env) {
    \\  call void @longjmp(ptr %env, i32 1)
    \\  unreachable
    \\}
    \\declare void @longjmp(ptr, i32)
    ;

/// Test 6: C function calling C++ virtual method that may throw.
const C_CALLS_CPP_THROW =
    LLVM_PREAMBLE ++
    \\define void @c_calls_cpp_throw(ptr %obj) {
    \\  %vtable = load ptr, ptr %obj
    \\  %method = load ptr, ptr %vtable
    \\  call void %method(ptr %obj)
    \\  ret void
    \\}
    ;

/// Test 7: Zig extern function calling panic — should flag.
const ZIG_EXTERN_PANIC =
    LLVM_PREAMBLE ++
    \\define void @zig_extern_panic() {
    \\  call void @__zig_panic(ptr @.str, i64 12)
    \\  unreachable
    \\}
    \\@.str = private unnamed_addr constant [13 x i8] c"panic message"
    \\declare void @__zig_panic(ptr, i64)
    ;

/// Load IR and run UnwindBoundaryPass, returning issue count.
/// Uses Pipeline (not direct PassContext) for proper issue collection.
fn runPassOnIR(allocator: std.mem.Allocator, ir: []const u8) !usize {
    const tmp_path = "/tmp/omniscope_unwind_test.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp_path, .data = ir });
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    var loader = try IRLoader.loadFile(allocator, tmp_path);
    defer loader.deinit();

    var pipeline = try Pipeline.init(allocator);
    defer pipeline.deinit();

    try pipeline.registerPass(UnwindBoundaryPass);

    const module = loader.getModule() orelse return error.NoModule;
    pipeline.setModule(module);
    try pipeline.run();

    return pipeline.getIssues().len;
}

// ============================================================================
// Tests
// ============================================================================

test "UnwindBoundary - Rust extern panic should warn" {
    const count = try runPassOnIR(std.testing.allocator, RUST_EXTERN_PANIC);
    try std.testing.expect(count > 0);
}

test "UnwindBoundary - C++ extern throw should warn" {
    const count = try runPassOnIR(std.testing.allocator, CPP_EXTERN_THROW);
    try std.testing.expect(count > 0);
}

test "UnwindBoundary - Rust internal panic should not warn (same language)" {
    const count = try runPassOnIR(std.testing.allocator, RUST_INTERNAL_PANIC);
    try std.testing.expectEqual(@as(usize, 0), count);
}

test "UnwindBoundary - C longjmp should not warn (pure C)" {
    const count = try runPassOnIR(std.testing.allocator, C_LONGJMP);
    try std.testing.expectEqual(@as(usize, 0), count);
}

test "UnwindBoundary - Rust longjmp should warn (non-C context)" {
    const count = try runPassOnIR(std.testing.allocator, RUST_LONGJMP);
    try std.testing.expect(count > 0);
}

test "UnwindBoundary - Zig extern panic should warn" {
    const count = try runPassOnIR(std.testing.allocator, ZIG_EXTERN_PANIC);
    try std.testing.expect(count > 0);
}

test "UnwindBoundary - C calls C++ virtual method may throw" {
    const count = try runPassOnIR(std.testing.allocator, C_CALLS_CPP_THROW);
    try std.testing.expectEqual(@as(usize, 0), count);
}

test "UnwindBoundary - pass name matches expected" {
    try std.testing.expectEqualStrings("unwind-boundary", UnwindBoundaryPass.name);
}
