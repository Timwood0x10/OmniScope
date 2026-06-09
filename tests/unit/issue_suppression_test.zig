//! Comprehensive tests for issue suppression logic.
//!
//! Covers:
//!   - P0 regression tests (stdlib UAF/DF/IF not suppressed)
//!   - P1 regression tests (libc dangerous functions blocked)
//!   - Pattern G/H matching (stdlib internal, platform runtime)
//!   - Memory safety guard behavior (isRealMemorySafetyBug, etc.)
//!   - Compiler internal function detection (mangled name whitelist)
//!   - Platform-aware suppression (Windows MSVC gating)
//!   - Edge cases and boundary conditions
//!
//! Run: zig build test-issue-suppression

const std = @import("std");
const OmniScope = @import("OmniScope");

const suppression = OmniScope.pass.analysis.noise.issue_suppression;
const patterns = OmniScope.pass.analysis.noise.suppression_patterns;
const guard = OmniScope.pass.analysis.noise.memory_safety_guard;

const Issue = OmniScope.diag.Issue;
const IssueKind = OmniScope.diag.IssueKind;
const PlatformProfile = suppression.PlatformProfile;
const platform_profile_mod = OmniScope.semantics.platform_profile;

// ============================================================================
// Helper: build a minimal PlatformProfile for tests (no allocation).
// ============================================================================

fn makeTestProfile(
    platform: platform_profile_mod.PlatformKind,
    object_format: platform_profile_mod.ObjectFormat,
    abi: platform_profile_mod.WindowsAbi,
) PlatformProfile {
    return PlatformProfile{
        .platform = platform,
        .object_format = object_format,
        .target_triple = "",
        .datalayout = "",
        .arch = "",
        .vendor = "",
        .windows_abi = abi,
    };
}

// ============================================================================
// shouldSuppressWithProfile — platform-gated suppression tests
// ============================================================================

test "shouldSuppressWithProfile — null profile preserves legacy behavior" {
    // The legacy entry point must behave identically when null is passed.
    // We use a Windows MSVC runtime name to exercise the platform branch.
    var i = Issue.init(
        .memory_leak,
        "leak in __except_handler4",
        .{ .file = null, .func = "__except_handler4" },
        .high,
        0.8,
    );
    try std.testing.expectEqual(
        suppression.shouldSuppress(&i),
        suppression.shouldSuppressWithProfile(&i, null),
    );
}

test "shouldSuppressWithProfile — Windows MSVC pattern fires on Windows" {
    // On a Windows MSVC target, the MSVC CRT pattern set should be consulted
    // and suppress the issue.
    const profile = makeTestProfile(.windows, .coff, .msvc);
    var i = Issue.init(
        .memory_leak,
        "leak in __except_handler4",
        .{ .file = null, .func = "__except_handler4" },
        .high,
        0.8,
    );
    try std.testing.expect(suppression.shouldSuppressWithProfile(&i, &profile));
}

test "shouldSuppressWithProfile — Windows MSVC pattern skipped on Linux" {
    // The same SEH-named symbol on Linux is almost certainly NOT the
    // Windows runtime, so the platform-gated path must skip the MSVC scan.
    //
    // We must pick a name that ONLY matches Windows MSVC patterns and does
    // not collide with any generic (cross-platform) runtime pattern.
    const profile = makeTestProfile(.linux, .elf, .unknown);
    var i = Issue.init(
        .memory_leak,
        "leak in __except_handler4",
        .{ .file = null, .func = "__except_handler4" },
        .high,
        0.8,
    );
    try std.testing.expect(!suppression.shouldSuppressWithProfile(&i, &profile));
}

test "shouldSuppressWithProfile — generic patterns work on every platform" {
    // C++ allocator `_Znwm` is cross-platform; it should suppress on both
    // Linux and Windows profiles regardless of MSVC gating.
    const linux_profile = makeTestProfile(.linux, .elf, .unknown);
    const win_profile = makeTestProfile(.windows, .coff, .msvc);
    var i = Issue.init(
        .memory_leak,
        "leak in _Znwm",
        .{ .file = null, .func = "_Znwm" },
        .high,
        0.8,
    );
    try std.testing.expect(suppression.shouldSuppressWithProfile(&i, &linux_profile));
    try std.testing.expect(suppression.shouldSuppressWithProfile(&i, &win_profile));
}

test "shouldSuppressWithProfile — real memory bug never suppressed regardless of profile" {
    // The global guard must keep priority — a genuine double-free in a user
    // function should pass through even on a Windows MSVC profile.
    const profile = makeTestProfile(.windows, .coff, .msvc);
    var i = Issue.init(
        .double_free,
        "double free in app_handler",
        .{ .file = null, .func = "app_handler" },
        .critical,
        0.95,
    );
    try std.testing.expect(!suppression.shouldSuppressWithProfile(&i, &profile));
}

// ============================================================================
// FIX #3: Precise compiler-internal function detection (mangled name whitelist)
// ============================================================================

test "isCompilerInternalFunction - C++ std library patterns are internal" {
    try std.testing.expect(guard.isCompilerInternalFunction("_ZNSt6vectorIiEE"));
    try std.testing.expect(guard.isCompilerInternalFunction("_ZNSt9basic_stringIcE"));
    try std.testing.expect(guard.isCompilerInternalFunction("_ZNSt3mapIiiEE"));
}

test "isCompilerInternalFunction - Rust stdlib patterns are internal" {
    try std.testing.expect(guard.isCompilerInternalFunction("_ZN4core9fmt::Formatter9write_strE"));
    try std.testing.expect(guard.isCompilerInternalFunction("_ZN5alloc6sync::ReentrantMutexE"));
    try std.testing.expect(guard.isCompilerInternalFunction("_ZN3std2io5stdio6printlnE"));
}

test "isCompilerInternalFunction - compiler ABI internals are internal" {
    try std.testing.expect(guard.isCompilerInternalFunction("_ZGVN3foo3barE"));
    try std.testing.expect(guard.isCompilerInternalFunction("_ZZN3foo3barEvE12local_var"));
    try std.testing.expect(guard.isCompilerInternalFunction("__cxx_global_var_init"));
    try std.testing.expect(guard.isCompilerInternalFunction("_GLOBAL__sub_I_main"));
}

test "isCompilerInternalFunction - Swift runtime symbols are internal" {
    try std.testing.expect(guard.isCompilerInternalFunction("$sS4base8toStringSSyF"));
    try std.testing.expect(guard.isCompilerInternalFunction("$ss5printyySS_pF"));
}

test "isCompilerInternalFunction - user mangled functions are NOT internal (FIX #3)" {
    // User C++ class methods should NOT be skipped
    try std.testing.expect(!guard.isCompilerInternalFunction("_ZN9my_app4mainE"));
    try std.testing.expect(!guard.isCompilerInternalFunction("_ZN3app7my_class12do_somethingE"));
    try std.testing.expect(!guard.isCompilerInternalFunction("_ZN6mylib4DataC1Ev"));

    // User Rust pub fn should NOT be skipped
    try std.testing.expect(!guard.isCompilerInternalFunction("_ZN6mycrate4func17process_dataEv"));
    try std.testing.expect(!guard.isCompilerInternalFunction("_ZN5utils8helper_fnE"));

    // Non-mangled functions are never internal
    try std.testing.expect(!guard.isCompilerInternalFunction("user_function"));
    try std.testing.expect(!guard.isCompilerInternalFunction("main"));
    try std.testing.expect(!guard.isCompilerInternalFunction("handle_request"));
}

// ============================================================================
// FIX #4: null_dereference and other critical types never suppressed
// ============================================================================

test "isRealMemorySafetyBug - null_dereference is never suppressed (FIX #4)" {
    // null_dereference in stdlib function → must return true (never suppressed)
    var i = Issue.init(
        .null_dereference,
        "null pointer dereference in std.mem.copy",
        .{ .file = null, .func = "std.mem.copy" },
        .high,
        0.9,
    );
    try std.testing.expect(guard.isRealMemorySafetyBug(&i));

    // null_dereference in os.mmap → must return true
    i = Issue.init(
        .null_dereference,
        "null dereference in os.mmap",
        .{ .file = null, .func = "os.mmap" },
        .high,
        0.85,
    );
    try std.testing.expect(guard.isRealMemorySafetyBug(&i));

    // null_dereference in user function → must return true
    i = Issue.init(
        .null_dereference,
        "null dereference in process_data",
        .{ .file = null, .func = "process_data" },
        .high,
        0.88,
    );
    try std.testing.expect(guard.isRealMemorySafetyBug(&i));
}

test "isRealMemorySafetyBug - buffer_overflow is never suppressed (FIX #4)" {
    var i = Issue.init(
        .buffer_overflow,
        "buffer overflow in snprintf",
        .{ .file = null, .func = "snprintf" },
        .critical,
        0.95,
    );
    try std.testing.expect(guard.isRealMemorySafetyBug(&i));
}

test "isRealMemorySafetyBug - integer_overflow is never suppressed (FIX #4)" {
    var i = Issue.init(
        .integer_overflow,
        "integer overflow in calculate_size",
        .{ .file = null, .func = "calculate_size" },
        .high,
        0.87,
    );
    try std.testing.expect(guard.isRealMemorySafetyBug(&i));
}

test "isRealMemorySafetyBug - core memory safety types always return true" {
    // NOTE: memory_leak is categorized as .leak (not .core_memory_safety)
    // because leaks are deterministic but have probabilistic impact.
    // See issue_classification.zig categorize() for details.
    const critical_kinds = [_]IssueKind{
        .double_free,      .use_after_free,  .invalid_free,
        .null_dereference, .buffer_overflow, .integer_overflow,
    };

    for (critical_kinds) |kind| {
        var i = Issue.init(
            kind,
            "test issue",
            .{ .file = null, .func = "test_func" },
            .high,
            0.8,
        );
        try std.testing.expect(guard.isRealMemorySafetyBug(&i));
    }

    // Verify memory_leak is NOT classified as core memory safety (by design)
    var leak_issue = Issue.init(
        .memory_leak,
        "leak in test_func",
        .{ .file = null, .func = "test_func" },
        .high,
        0.8,
    );
    try std.testing.expect(!guard.isRealMemorySafetyBug(&leak_issue));
}

// ============================================================================
// FIX #P2: Precise double-underscore prefix whitelist
// ============================================================================

test "isStdlibInternalFunction - compiler builtins are suppressed (safe)" {
    // LLVM intrinsics — should be suppressed
    var issue_llvm = Issue.init(
        .callback_ownership_risk,
        "risk in __llvm_gcda_start_file",
        .{ .file = null, .func = "__llvm_gcda_start_file" },
        .high,
        0.7,
    );
    try std.testing.expect(patterns.isStdlibInternalFunction(&issue_llvm));

    // Sanitizer runtime — should be suppressed
    var issue_asan = Issue.init(
        .callback_ownership_risk,
        "risk in __asan_report_load1",
        .{ .file = null, .func = "__asan_report_load1" },
        .high,
        0.7,
    );
    try std.testing.expect(patterns.isStdlibInternalFunction(&issue_asan));

    // C++ ABI runtime — should be suppressed
    var issue_cxa = Issue.init(
        .callback_ownership_risk,
        "risk in __cxa_throw",
        .{ .file = null, .func = "__cxa_throw" },
        .high,
        0.7,
    );
    try std.testing.expect(patterns.isStdlibInternalFunction(&issue_cxa));

    // GCC builtin — should be suppressed
    var issue_builtin = Issue.init(
        .callback_ownership_risk,
        "risk in __builtin_memcpy",
        .{ .file = null, .func = "__builtin_memcpy" },
        .high,
        0.7,
    );
    try std.testing.expect(patterns.isStdlibInternalFunction(&issue_builtin));
}

test "isStdlibInternalFunction - user dunder functions are NOT suppressed (FIX #P2)" {
    // Python/Cython lifecycle functions — should NOT be suppressed
    var issue_cinit = Issue.init(
        .callback_ownership_risk,
        "risk in __cinit__",
        .{ .file = null, .func = "__cinit__" },
        .high,
        0.7,
    );
    try std.testing.expect(!patterns.isStdlibInternalFunction(&issue_cinit));

    var issue_dealloc = Issue.init(
        .callback_ownership_risk,
        "risk in __dealloc__",
        .{ .file = null, .func = "__dealloc__" },
        .high,
        0.7,
    );
    try std.testing.expect(!patterns.isStdlibInternalFunction(&issue_dealloc));

    // Python module init — should NOT be suppressed
    var issue_init_mod = Issue.init(
        .callback_ownership_risk,
        "risk in __init_module",
        .{ .file = null, .func = "__init_module" },
        .high,
        0.7,
    );
    try std.testing.expect(!patterns.isStdlibInternalFunction(&issue_init_mod));

    // User-defined lifecycle — should NOT be suppressed
    var issue_init = Issue.init(
        .callback_ownership_risk,
        "risk in __init",
        .{ .file = null, .func = "__init" },
        .high,
        0.7,
    );
    try std.testing.expect(!patterns.isStdlibInternalFunction(&issue_init));

    var issue_finalize = Issue.init(
        .callback_ownership_risk,
        "risk in __finalize",
        .{ .file = null, .func = "__finalize" },
        .high,
        0.7,
    );
    try std.testing.expect(!patterns.isStdlibInternalFunction(&issue_finalize));

    // Custom user function with __ prefix — should NOT be suppressed
    var issue_custom = Issue.init(
        .callback_ownership_risk,
        "risk in __custom_helper",
        .{ .file = null, .func = "__custom_helper" },
        .high,
        0.7,
    );
    try std.testing.expect(!patterns.isStdlibInternalFunction(&issue_custom));
}
