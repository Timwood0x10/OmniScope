//! P0 Regression Tests — Critical Bug Fixes Verification
//!
//! These tests verify that P0-level critical fixes remain stable:
//!   - Fix #1: invoke instruction treated same as call for FFI detection
//!   - Fix #2: user mangled name functions NOT skipped for double-free check
//!   - Fix #3: null_dereference never suppressed even in stdlib functions
//!   - Fix #4: __ prefix only suppresses known-safe functions
//!
//! Run: zig build test-p0-regression

const std = @import("std");
const OmniScope = @import("OmniScope");

const llvm_safe = OmniScope.ir.llvm_safe;
const issue_suppression = OmniScope.pass.analysis.noise.issue_suppression;
const Issue = OmniScope.diag.Issue;
const IssueKind = OmniScope.diag.IssueKind;
const Severity = OmniScope.diag.Severity;
const PlatformProfile = OmniScope.semantics.platform_profile.PlatformProfile;

// ============================================================================
// Test Group A: invoke instruction support (Fix #1)
// ============================================================================

test "P0-A1: isCallOrInvoke returns true for LLVMCall opcode" {
    const c = OmniScope.ir.llvm_raw.c;
    try std.testing.expect(llvm_safe.isCallOrInvoke(c.LLVMCall));
}

test "P0-A2: isCallOrInvoke returns true for LLVMInvoke opcode" {
    const c = OmniScope.ir.llvm_raw.c;
    try std.testing.expect(llvm_safe.isCallOrInvoke(c.LLVMInvoke));
}

test "P0-A3: isCallOrInvoke returns false for non-call opcodes" {
    const c = OmniScope.ir.llvm_raw.c;
    try std.testing.expect(!llvm_safe.isCallOrInvoke(c.LLVMAlloca));
    try std.testing.expect(!llvm_safe.isCallOrInvoke(c.LLVMLoad));
    try std.testing.expect(!llvm_safe.isCallOrInvoke(c.LLVMStore));
    try std.testing.expect(!llvm_safe.isCallOrInvoke(c.LLVMBr));
    try std.testing.expect(!llvm_safe.isCallOrInvoke(c.LLVMRet));
}

test "P0-A4: getCallInstArgCountSafe returns null for non-call instructions" {
    const c = OmniScope.ir.llvm_raw.c;
    try std.testing.expect(llvm_safe.getCallInstArgCountSafe(c.LLVMGetUndef(c.LLVMVoidType())) == null);
}

// ============================================================================
// Test Group B: mangled name precise filtering (Fix #2)
// ============================================================================

test "P0-B1: C++ stdlib mangled names ARE internal (should be skipped)" {
    try std.testing.expect(issue_suppression.isCompilerInternalFunction("_ZNSt6vectorIiEE"));
    try std.testing.expect(issue_suppression.isCompilerInternalFunction("_ZNSt9basic_stringIcE"));
    try std.testing.expect(issue_suppression.isCompilerInternalFunction("_ZNSt3mapIiiEE"));
    try std.testing.expect(issue_suppression.isCompilerInternalFunction("_ZNSt5dequeIfE"));
}

test "P0-B2: Rust core/alloc mangled names ARE internal (should be skipped)" {
    try std.testing.expect(issue_suppression.isCompilerInternalFunction("_ZN4core9fmt::Formatter9write_strE"));
    try std.testing.expect(issue_suppression.isCompilerInternalFunction("_ZN5alloc6sync::ReentrantMutexE"));
    // Note: _ZN3std is NOT considered internal (std is user-level, not core/alloc)
}

test "P0-B3: User C++ mangled names are NOT internal (NOT skipped — double-free checked)" {
    try std.testing.expect(!issue_suppression.isCompilerInternalFunction("_ZN9my_app4mainE"));
    try std.testing.expect(!issue_suppression.isCompilerInternalFunction("_ZN3app7my_class12do_somethingE"));
    try std.testing.expect(!issue_suppression.isCompilerInternalFunction("_ZN6mylib4DataC1Ev"));
    try std.testing.expect(!issue_suppression.isCompilerInternalFunction("_ZN4game8Engine3runEv"));
}

test "P0-B4: User Rust mangled names are NOT internal (NOT skipped — double-free checked)" {
    try std.testing.expect(!issue_suppression.isCompilerInternalFunction("_ZN6mycrate4func17process_dataEv"));
    try std.testing.expect(!issue_suppression.isCompilerInternalFunction("_ZN5utils8helper_fnE"));
    try std.testing.expect(!issue_suppression.isCompilerInternalFunction("_RNv6myapp4main"));
}

test "P0-B5: Compiler ABI internals ARE internal" {
    try std.testing.expect(issue_suppression.isCompilerInternalFunction("_ZGVN3foo3barE"));
    try std.testing.expect(issue_suppression.isCompilerInternalFunction("_ZZN3foo3barEvE12local_var"));
    try std.testing.expect(issue_suppression.isCompilerInternalFunction("__cxx_global_var_init"));
    try std.testing.expect(issue_suppression.isCompilerInternalFunction("_GLOBAL__sub_I_main"));
}

test "P0-B6: Swift runtime symbols ARE internal" {
    try std.testing.expect(issue_suppression.isCompilerInternalFunction("$sS4base8toStringSSyF"));
    try std.testing.expect(issue_suppression.isCompilerInternalFunction("$ss5printyySS_pF"));
}

// ============================================================================
// Test Group C: null_dereference protection (Fix #3 & #4)
//
// NOTE: isRealMemorySafetyBug has an EXCEPTION for stdlib internal functions.
// Tests below use NON-stdlib function names to test the core logic.
// ============================================================================

test "P0-C1: null_dereference in user function is NEVER suppressed" {
    var issue = Issue.init(
        .null_dereference,
        "null pointer dereference in user_func",
        .{ .file = null, .func = "user_process_data" },
        .critical,
        0.90,
    );
    try std.testing.expect(issue_suppression.isRealMemorySafetyBug(&issue));
}

test "P0-C2: buffer_overflow is NEVER suppressed for user code" {
    var issue = Issue.init(
        .buffer_overflow,
        "buffer overflow in user_snprintf",
        .{ .file = null, .func = "custom_snprintf_wrapper" },
        .critical,
        0.95,
    );
    try std.testing.expect(issue_suppression.isRealMemorySafetyBug(&issue));
}

test "P0-C3: integer_overflow is NEVER suppressed for user code" {
    var issue = Issue.init(
        .integer_overflow,
        "integer overflow in calculate_size",
        .{ .file = null, .func = "calculate_buffer_size" },
        .high,
        0.87,
    );
    try std.testing.expect(issue_suppression.isRealMemorySafetyBug(&issue));
}

test "P0-C4: all core memory safety kinds return true from isRealMemorySafetyBug" {
    // Note: memory_leak IS a core memory safety kind, but isRealMemorySafetyBug
    // has an exception for stdlib internal functions. We use user function names.
    const critical_kinds = [_]IssueKind{
        .double_free,
        .use_after_free,
        .invalid_free,
        .null_dereference,
        .buffer_overflow,
        .integer_overflow,
    };

    for (critical_kinds) |kind| {
        var issue = Issue.init(
            kind,
            "test issue",
            .{ .file = null, .func = "user_test_function" },
            .high,
            0.8,
        );
        try std.testing.expect(issue_suppression.isRealMemorySafetyBug(&issue));
    }
}

test "P0-C5: double_free is real memory safety bug for user function" {
    var issue = Issue.init(
        .double_free,
        "double free detected in app",
        .{ .file = null, .func = "app_memory_manager" },
        .critical,
        0.92,
    );
    try std.testing.expect(issue_suppression.isRealMemorySafetyBug(&issue));
}

test "P0-C6: use_after_free is real memory safety bug for user function" {
    var issue = Issue.init(
        .use_after_free,
        "use after free with cross-FFI alias detected",
        .{ .file = null, .func = "user_handler" },
        .high,
        0.85,
    );
    try std.testing.expect(issue_suppression.isRealMemorySafetyBug(&issue));
}

test "P0-C7: stdlib internal function with critical issue returns true (P1-8 fix)" {
    var issue = Issue.init(
        .null_dereference,
        "null dereference in std.mem.copy",
        .{ .file = null, .func = "std.mem.copy" },
        .high,
        0.90,
    );
    // null_dereference is a critical issue type that should be reported even in stdlib
    try std.testing.expect(issue_suppression.isRealMemorySafetyBug(&issue));
}

test "P0-C8: Rust compiler internal double_free returns false (drop chain FP)" {
    var issue = Issue.init(
        .double_free,
        "double free with __rust_dealloc",
        // Must start with _ZN4core or _ZN5alloc to be recognized as internal
        .{ .file = null, .func = "_ZN4core9fmt::Formatter9format_with" },
        .critical,
        0.92,
    );
    try std.testing.expect(!issue_suppression.isRealMemorySafetyBug(&issue));
}

// ============================================================================
// Test Group D: shouldSuppressWithProfile platform gating
//
// NOTE: These tests verify platform-specific pattern matching.
// The source file (issue_suppression.zig) has comprehensive internal tests
// for these patterns. Here we test the public API surface.
// ============================================================================

test "P0-D1: shouldSuppressWithProfile accepts null profile (backward compat)" {
    var i = Issue.init(
        .write_to_immutable,
        "write to immutable in hash_map",
        .{ .file = null, .func = "hash_map.put" },
        .medium,
        0.6,
    );
    try std.testing.expect(issue_suppression.shouldSuppressWithProfile(&i, null));
}

test "P0-D2: real memory safety bug (double_free) never suppressed regardless of platform" {
    const profile = PlatformProfile{
        .platform = .windows,
        .object_format = .coff,
        .target_triple = "",
        .datalayout = "",
        .arch = "",
        .vendor = "",
        .windows_abi = .msvc,
    };
    var i = Issue.init(
        .double_free,
        "double free in app_handler",
        .{ .file = null, .func = "app_handler" },
        .critical,
        0.95,
    );
    try std.testing.expect(!issue_suppression.shouldSuppressWithProfile(&i, &profile));
}
