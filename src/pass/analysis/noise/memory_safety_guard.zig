//! Memory Safety Guard Functions
//!
//! Core safety checks that prevent suppression of critical bugs.
//! These functions form the "global guard" at the top of shouldSuppress()
//! to ensure genuine memory safety vulnerabilities are never suppressed.
//!
//! Functions covered:
//!   - isRealMemorySafetyBug(): Unified check for critical vulnerability types
//!   - isPureRustInternalDoubleFree(): Rust drop chain FP detection
//!   - isCompilerInternalFunction(): Precise mangled name whitelist
//!   - isCryptoPrimitive() / isTableDrivenFunction(): Semantic helpers

const std = @import("std");
const log = @import("../../../common/log.zig");

const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const issue_classification = @import("../../../filter/issue_classification.zig");
const suppression_patterns = @import("suppression_patterns.zig");
const PatternRegistry = @import("../../../filter/pattern_registry.zig").PatternRegistry;

/// Check if an issue represents a REAL memory safety vulnerability that
/// should NEVER be suppressed by any pattern.
///
/// This is the unified guard placed at the top of shouldSuppress().
/// It covers:
///   - Core memory safety violations (double_free, use_after_free, etc.)
///   - Critical CWE-classified vulnerabilities (null_dereference, buffer_overflow, etc.)
///   - FFI boundary issues (cross-language leaks, unsafe calls)
///   - Ownership/borrow violations (borrow_escape, type_mismatch)
///   - Callback safety issues (callback_ownership_risk, etc.)
///
/// Rationale: These issue kinds represent GENUINE security vulnerabilities.
/// Even when they occur in "safe_*" named functions, involve __rust_dealloc,
/// or mention NonNull types — the detector found a real problem, not a FP.
pub fn isRealMemorySafetyBug(issue: *const Issue) bool {
    // EXCEPTION 1: Stdlib internal functions — only suppress non-critical issue types
    //
    // Even if the issue comes from a known stdlib internal function (Io.Writer.*, debug.*,
    // fs.*, etc.), core memory safety bugs (use_after_free, buffer_overflow, double_free, etc.)
    // should still be reported because they represent genuine security vulnerabilities.
    // Only non-critical issue types (advisory, leak, etc.) are suppressed for stdlib functions.
    if (suppression_patterns.isStdlibInternalFunction(issue)) {
        if (!issue_classification.isNeverSuppressed(issue.kind)) {
            log.debug("[STDLIB-EXEMPT] {s} in {s} -> let Pattern G handle", .{
                @tagName(issue.kind), issue.location.func,
            });
            return false;
        }
    }

    // EXCEPTION 2: Pure-Rust-internal drop chain double_free
    //
    // When a Rust function like format_digest() does String::with_capacity + format!,
    // the IR shows multiple __rust_dealloc calls (one per String allocation).
    // This looks like double_free but is actually Rust's normal Drop trait cleanup.
    if (issue.kind == .double_free) {
        if (isPureRustInternalDoubleFree(issue)) return false;

        // ADDITIONAL GUARD: Even when cross-FFI alias is detected,
        // if the issue is purely internal to a Rust module (mangled caller +
        // _RNv mangled callee + __rust_dealloc), it's still a drop chain FP.
        const func = issue.location.func;
        const msg = issue.message;
        const is_internal_caller = isCompilerInternalFunction(func);
        const has_rnv_callee = std.mem.indexOf(u8, msg, "_RNv") != null;
        const has_rust_dealloc = std.mem.indexOf(u8, msg, "__rust_dealloc") != null;

        if (is_internal_caller and has_rnv_callee and has_rust_dealloc) {
            log.debug("[PURE-RUST-FP-GUARD] double_free in {s} with _RNv+__rust_dealloc -> let Pattern A handle", .{func});
            return false;
        }
    }

    // Delegate to unified classification — single source of truth.
    return issue_classification.isNeverSuppressed(issue.kind);
}

/// Check if a mangled function name belongs to a known compiler-internal
/// or standard-library component that can be safely skipped for double-free
/// analysis.
///
/// Delegates to PatternRegistry.isCompilerInternal (single source of truth).
pub fn isCompilerInternalFunction(func_name: []const u8) bool {
    return PatternRegistry.isCompilerInternal(func_name);
}

/// Detect if a double_free issue is actually a pure Rust internal drop chain
/// false positive, NOT a real memory safety bug.
///
/// Rust's ownership system uses Drop trait for cleanup. When a function creates
/// multiple owned values (e.g., String::with_capacity + format!), each one gets
/// its own __rust_dealloc call when the function returns. To an intra-procedural
/// detector that doesn't model Rust's ownership semantics, this looks like double_free.
fn isPureRustInternalDoubleFree(issue: *const Issue) bool {
    const func = issue.location.func;
    const msg = issue.message;

    // Condition 1: Caller must be a known compiler-internal function
    if (!isCompilerInternalFunction(func)) return false;

    // Condition 2: Must involve Rust global allocator
    const has_rust_dealloc = suppression_patterns.containsAny(msg, &[_][]const u8{
        "__rust_dealloc",
        "__rust_alloc",
        "drop_in_place",
    });
    if (!has_rust_dealloc) return false;

    // Condition 3: No FFI cross-boundary evidence
    const ffi_signals = [_][]const u8{
        "c_hash",    "c_alloc",        "c_free",
        "cross-FFI", "cross_language", "FFI Boundary",
        "FFI call",  "malloc(",        "free(",
        "extern ",
    };
    if (suppression_patterns.containsAny(msg, &ffi_signals)) return false;

    // All conditions met → pure Rust drop chain FP
    log.debug("[PURE-RUST-FP] double_free in {s} classified as Rust drop chain FP", .{func});
    return true;
}

// ============================================================================
// Semantic Helpers (generic, no project-specific names)
// ============================================================================

/// Check if function name indicates a cryptographic primitive.
/// These functions commonly produce alloca-derived pointer FPs because
/// they pass stack buffers to assembly routines or FFI by design.
///
/// Delegates to PatternRegistry.isCryptoPrimitive (single source of truth).
pub fn isCryptoPrimitive(name: []const u8) bool {
    return PatternRegistry.isCryptoPrimitive(name);
}

/// Check if function name suggests table-driven implementation.
/// Table-driven crypto often loads function pointer tables from .text section
/// into stack variables before indirect calls — produces alloca FPs.
///
/// Delegates to PatternRegistry.isTableDriven (single source of truth).
pub fn isTableDrivenFunction(name: []const u8) bool {
    return PatternRegistry.isTableDriven(name);
}
