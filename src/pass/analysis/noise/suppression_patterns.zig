//! Suppression Pattern Definitions (G/H)
//!
//! Defines pattern matching rules for identifying and suppressing
//! false positives in different language runtimes and platform-specific code.
//!
//! Patterns covered:
//!   - Pattern G: Stdlib internal functions (Zig/Rust/C++/compiler builtins)
//!   - Pattern H: Platform runtime shims (C++/ObjC/Swift/Rust/Go/Zig/LLVM/sanitizer)
//!
//! All patterns match on function name prefixes and substrings that indicate
//! compiler-generated or runtime-provided code (NOT user code).
//!
//! Delegates to PatternRegistry (single source of truth) for all pattern data.

const std = @import("std");

const Issue = @import("../../../diag/issue.zig").Issue;
const PlatformProfile = @import("../../../semantics/platform_profile.zig").PlatformProfile;
const PatternRegistry = @import("../../../filter/pattern_registry.zig").PatternRegistry;

// ============================================================================
// Pattern G: Stdlib Internal Function
// ============================================================================

/// Detect if an issue originates from a language standard library or
/// compiler runtime internal function.
///
/// These functions are NOT user code — they are part of the language's
/// trusted computing base and should not appear in security reports.
///
/// Delegates to PatternRegistry.isStdlibInternal (single source of truth).
pub fn isStdlibInternalFunction(issue: *const Issue) bool {
    const func = issue.location.func;
    if (func.len == 0) return false;
    return PatternRegistry.isStdlibInternal(func);
}

// ============================================================================
// Pattern H: Platform Runtime / Compiler-Generated Shim
// ============================================================================

/// Check if function name matches a known platform runtime / compiler-generated shim.
///
/// This complements isStdlibInternalFunction() by catching platform-specific
/// runtime functions that don't match stdlib naming conventions but are still
/// not user code.
///
/// Delegates to PatternRegistry.isRuntimeShim (single source of truth).
pub fn isPlatformRuntimeShim(func_name: []const u8) bool {
    return PatternRegistry.isRuntimeShim(func_name);
}

/// Platform-aware variant of [`isPlatformRuntimeShim`].
///
/// Runs all generic runtime checks unconditionally, but only consults
/// the Windows MSVC CRT pattern set when `profile` indicates a Windows
/// target. A null profile preserves the legacy "scan everything"
/// behavior so the function remains drop-in safe.
pub fn isPlatformRuntimeShimGated(
    func_name: []const u8,
    profile: ?*const PlatformProfile,
) bool {
    // Generic cross-platform runtime patterns are always evaluated.
    if (PatternRegistry.isGenericRuntimeShim(func_name)) return true;

    // Windows MSVC CRT is only meaningful on Windows.
    const consult_windows = if (profile) |p|
        p.platform == .windows
    else
        true; // Null profile -> preserve legacy unconditional behavior.

    if (consult_windows and PatternRegistry.isWindowsMsvcRuntime(func_name)) return true;

    return false;
}

// ============================================================================
// String Helper Functions
// ============================================================================

/// Check if haystack starts with needle.
pub fn startsWith(haystack: []const u8, needle: []const u8) bool {
    if (haystack.len < needle.len) return false;
    return std.mem.eql(u8, haystack[0..needle.len], needle);
}

/// Check if haystack ends with needle.
pub fn endsWith(haystack: []const u8, needle: []const u8) bool {
    if (haystack.len < needle.len) return false;
    return std.mem.eql(u8, haystack[haystack.len - needle.len ..], needle);
}

/// Helper: check if haystack contains ANY of the needles.
pub fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.mem.indexOf(u8, haystack, needle) != null) return true;
    }
    return false;
}
