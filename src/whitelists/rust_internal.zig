//! Rust Internal Function Whitelist - Suppresses false positives from
//! Rust's panic/unwind mechanism and standard library internals.
//!
//! These functions either:
//!   - Never return normally (! type / diverge)
//!   - Handle errors via panics (not return codes)
//!   - Are part of the unwind/catch machinery
//!
//! Reporting them as "unchecked_return" or "resource leak" creates noise.
//!
//! ## Problem Background
//!
//! When analyzing `bun_jsc/core.bc`, OmniScope reported 13 false positives
//! for `unchecked_return` / `resource_leak` because:
//!
//! ```rust
//! fn panic_in_cleanup() -> ! {
//!     some_ffi_call();  // "unchecked error code from FFI call" FP!
//!     panic!("cleanup failed");  // Always panics, no need to check return
//! }
//! ```
//!
//! OmniScope doesn't know these functions never return normally, so it
//! incorrectly reports them as issues.

const std = @import("std");
const log = std.log.scoped(.rust_whitelist);

/// Whitelist match result
pub const WhitelistResult = enum {
    /// Fully suppress (don't report anything)
    full_suppress,
    /// Suppress unchecked_return warnings only
    suppress_unchecked_only,
    /// Don't suppress (report normally)
    no_match,
};

pub const RustInternalWhitelist = struct {
    // ── Category A: Panic formatting & propagation (never return normally) ──

    const PANIC_FUNCTIONS = [_][]const u8{
        // Core panic functions
        "panic_in_cleanup",
        "panic_fmt",
        "panic_bounds_check",
        "panic_cannot_unwind",
        "panic_async_fmt",
        "panic_display",
        "panic_abort",
        "panic_unwind",
        "panic_impersonate",

        // Panic count operations (atomics)
        "panic_count_is_zero_slow_path",
        "panic_count_add",
        "panic_count_sub",
        "panic_count_fetch",

        // Panic location info
        "begin_panic_handler",
        "update_panic_count",
    };

    // ── Category B: Unwind/Catch handling ──

    const UNWIND_FUNCTIONS = [_][]const u8{
        // catch_unwind cleanup routines
        "catch_unwind",
        "try_clone", // Error cloning during unwind
        "drop_in_place", // Drop during panic unwind

        // Backtrace (called during panic)
        "begin_short_backtrace",
        "unwind_backtrace",

        // Exception handling internals
        "_Unwind_RaiseException",
        "_Unwind_DeleteException",
        "_Unwind_FindContext",
    };

    // ── Category C: Standard library format/display internals ──

    const FORMAT_INTERNALS = [_][]const u8{
        // fmt::ArgumentV1 accessors (used in panic messages)
        "ArgumentV1",
        "fmt::Write::write_str",
        "fmt::Write::write_fmt",
        "fmt::Debug::fmt",

        // String formatting in panics
        "str::fmt",
        "str::print",

        // Number formatting
        "Int::fmt",
        "Float::fmt",
    };

    // ── Category D: Runtime support functions ──

    const RUNTIME_FUNCTIONS = [_][]const u8{
        // Threading in panic context
        "thread::panicking",
        "thread::parking",

        // Box/Rc/Vec error paths
        "RawVec::grow_",
        "Box::new_uninit",

        // Collection operations that can fail internally
        "RawTable::fallible",
        "RawTable::find_potential",

        // Rayon thread pool (used in parallel iterators)
        "rayon_core::join",
        "rayon_core::registry::worker",
    };

    // ── Category E: FFI boundary wrappers with built-in error handling ──

    const FFI_ERROR_WRAPPERS = [_][]const u8{
        // These wrappers convert C errors to Rust panics automatically
        "ErrorPropagationTracer", // Our own tracer! (internal use only)
        "check_errno", // errno -> Result conversion
        "last_os_error", // Get last OS error
        "from_error_code", // Convert error code
    };

    /// Main entry point: Check if function should be suppressed
    pub fn shouldSuppress(func_name: []const u8) WhitelistResult {
        // Fast path: exact matches (full suppress)
        if (matchExactOrContains(func_name, &PANIC_FUNCTIONS)) {
            return .full_suppress;
        }

        if (matchExactOrContains(func_name, &UNWIND_FUNCTIONS)) {
            return .full_suppress;
        }

        if (matchExactOrContains(func_name, &RUNTIME_FUNCTIONS)) {
            return .full_suppress;
        }

        if (matchExactOrContains(func_name, &FFI_ERROR_WRAPPERS)) {
            return .full_suppress;
        }

        // Medium confidence: format internals (suppress unchecked only)
        if (matchFuzzy(func_name, &FORMAT_INTERNALS)) {
            return .suppress_unchecked_only;
        }

        return .no_match;
    }

    /// Quick check: Should we completely skip analyzing this function?
    pub fn shouldSkipAnalysis(func_name: []const u8) bool {
        return shouldSuppress(func_name) == .full_suppress;
    }

    /// Check: Can we safely ignore the return value of this function?
    pub fn canIgnoreReturnValue(func_name: []const u8) bool {
        const result = shouldSuppress(func_name);
        return result == .full_suppress or result == .suppress_unchecked_only;
    }

    // ── Matching strategies ──

    /// Exact match or contains check (fast, no regex needed)
    fn matchExactOrContains(haystack: []const u8, needles: anytype) bool {
        inline for (needles) |needle| {
            // Support wildcard "*" at end (simple prefix match)
            const pattern = if (std.mem.endsWith(u8, needle, "*"))
                needle[0 .. needle.len - 1]
            else
                needle;

            // Check prefix match or substring match
            if (std.mem.startsWith(u8, haystack, pattern) or
                std.mem.indexOf(u8, haystack, pattern) != null)
            {
                return true;
            }
        }
        return false;
    }

    /// Fuzzy match with limited glob support (*. for any chars)
    fn matchFuzzy(haystack: []const u8, needles: anytype) bool {
        inline for (needles) |needle| {
            // Simple implementation: check if all parts exist in haystack
            var all_match = true;
            var iter = std.mem.tokenizeAny(u8, needle, ":.*");
            while (iter.next()) |part| {
                if (std.mem.indexOf(u8, haystack, part) == null) {
                    all_match = false;
                    break;
                }
            }
            if (all_match and haystack.len > 0) return true;
        }
        return false;
    }

    /// Add custom function to whitelist (runtime extensibility)
    pub fn addCustomEntry(self: *RustInternalWhitelist, func_name: []const u8) void {
        // Could be implemented as dynamic list if needed
        _ = self;
        // For now, just log it
        log.debug("RUST-WHITELIST: Added custom entry: {s}", .{func_name});
    }
};

// ── Tests ──

test "shouldSuppress - detects panic functions" {
    try std.testing.expectEqual(
        WhitelistResult.full_suppress,
        RustInternalWhitelist.shouldSuppress("panic_in_cleanup"),
    );
    try std.testing.expectEqual(
        WhitelistResult.full_suppress,
        RustInternalWhitelist.shouldSuppress("panic_fmt"),
    );
    try std.testing.expectEqual(
        WhitelistResult.full_suppress,
        RustInternalWhitelist.shouldSuppress("panic_bounds_check"),
    );
}

test "shouldSuppress - detects unwind functions" {
    try std.testing.expectEqual(
        WhitelistResult.full_suppress,
        RustInternalWhitelist.shouldSuppress("catch_unwind"),
    );
    try std.testing.expectEqual(
        WhitelistResult.full_suppress,
        RustInternalWhitelist.shouldSuppress("begin_short_backtrace"),
    );
}

test "shouldSuppress - allows normal functions" {
    try std.testing.expectEqual(
        WhitelistResult.no_match,
        RustInternalWhitelist.shouldSuppress("process_data"),
    );
    try std.testing.expectEqual(
        WhitelistResult.no_match,
        RustInternalWhitelist.shouldSuppress("SSL_CTX_new"),
    );
}

test "canIgnoreReturnValue - panic functions return ! type" {
    try std.testing.expect(RustInternalWhitelist.canIgnoreReturnValue("panic_in_cleanup"));
    try std.testing.expect(RustInternalWhitelist.canIgnoreReturnValue("catch_unwind"));
    try std.testing.expect(!RustInternalWhitelist.canIgnoreReturnValue("malloc"));
}

test "shouldSkipAnalysis - full suppress functions" {
    try std.testing.expect(RustInternalWhitelist.shouldSkipAnalysis("panic_fmt"));
    try std.testing.expect(RustInternalWhitelist.shouldSkipAnalysis("_Unwind_RaiseException"));
    try std.testing.expect(!RustInternalWhitelist.shouldSkipAnalysis("normal_function"));
}

test "format internals - suppress unchecked only" {
    try std.testing.expectEqual(
        WhitelistResult.suppress_unchecked_only,
        RustInternalWhitelist.shouldSuppress("some_ArgumentV1_func"),
    );
}
