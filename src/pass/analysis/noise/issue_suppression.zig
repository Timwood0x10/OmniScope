//! Issue Suppression Engine — Main Entry Point
//!
//! Main entry point for determining if an issue should be suppressed.
//! Delegates to specialized modules for pattern matching and safety checks.
//!
//! Architecture:
//!   - suppression_patterns.zig: Pattern G/H matching rules
//!   - memory_safety_guard.zig: isRealMemorySafetyBug() and related guards
//!
//! This module provides the public API (shouldSuppress, shouldSuppressWithProfile)
//! and re-exports types needed by external callers.

const std = @import("std");
const log = @import("../../../common/log.zig");

const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
// Platform profile is consulted when available so platform-specific
// suppression rules (e.g. Windows MSVC CRT) are gated to the matching
// target, instead of being scanned unconditionally on every issue.
const platform_profile_mod = @import("../../../semantics/platform_profile.zig");
pub const PlatformProfile = platform_profile_mod.PlatformProfile;

// Import specialized modules
const suppression_patterns = @import("suppression_patterns.zig");
const memory_safety_guard = @import("memory_safety_guard.zig");

// Re-export public functions from sub-modules for backward compatibility.
// pass_types.zig imports issue_suppression.isStdlibInternalFunction directly.
pub const isStdlibInternalFunction = suppression_patterns.isStdlibInternalFunction;
// Backward compat: isCompilerInternalFunction moved to PatternRegistry.
pub const isCompilerInternalFunction = @import("../../../filter/pattern_registry.zig").PatternRegistry.isCompilerInternal;
// Backward compat: isRealMemorySafetyBug lives in memory_safety_guard.
pub const isRealMemorySafetyBug = memory_safety_guard.isRealMemorySafetyBug;
pub const SuppressionStats = struct {
    drop_chain: usize = 0,
    static_provenance: usize = 0,
    panic_cleanup: usize = 0,
    os_api_usage: usize = 0,
    safe_example: usize = 0,
    defensive_coding: usize = 0,
    stdlib_internal: usize = 0,
    total_suppressed: usize = 0,

    pub fn record(self: *SuppressionStats, pattern: Pattern) void {
        switch (pattern) {
            .drop_chain => self.drop_chain += 1,
            .static_provenance => self.static_provenance += 1,
            .panic_cleanup => self.panic_cleanup += 1,
            .os_api_usage => self.os_api_usage += 1,
            .safe_example => self.safe_example += 1,
            .defensive_coding => self.defensive_coding += 1,
            .stdlib_internal => self.stdlib_internal += 1,
        }
        self.total_suppressed += 1;
    }

    pub fn logSummary(self: SuppressionStats) void {
        if (self.total_suppressed == 0) return;
        std.log.info("[SUPPRESSION] {d} suppressed: drop={d} static={d} panic={d} osapi={d} safe={d} defensive={d} stdlib={d}", .{
            self.total_suppressed,
            self.drop_chain,
            self.static_provenance,
            self.panic_cleanup,
            self.os_api_usage,
            self.safe_example,
            self.defensive_coding,
            self.stdlib_internal,
        });
    }
};

const Pattern = enum { drop_chain, static_provenance, panic_cleanup, os_api_usage, safe_example, defensive_coding, stdlib_internal };

/// ═══════════════════════════════════════════════════════════════
/// DEPRECATED: This module is being replaced by the Resource Contract Graph system.
///
/// Migration path:
///   - Pattern A (Rust Drop Chain) → summary_inference.zig inferDestructorLikeSummary()
///   - Pattern B (C++ destructor) → same as above
///   - Pattern C (Python same-family) → family_registry.zig compareFamilies(.same_family)
///   - Pattern D (Slice-to-ptr bridge) → inferBridgeHelperSummary() + isBridgeHelper()
///   - Pattern E (Py_DECREF conditional) → Effect.conditional_release in SummaryStore
///   - Pattern F (Static lifetime) → inferStaticLifetimeSink() + EscapeKind.static_lifetime
///
/// New code should use CandidateBuilder + IssueVerifier instead of direct suppression.
/// This file will be removed once all call sites are migrated.
/// ═══════════════════════════════════════════════════════════════

// ============================================================================
// Public API
// ============================================================================

/// Check if an issue should be suppressed based on known safe patterns.
///
/// Returns true if the issue matches a proven-safe pattern and should be
/// silently dropped. Returns false if the issue should proceed through
/// normal reporting pipeline.
///
/// Called from PassContext.addIssue() BEFORE dedup, severity adjustment,
/// and output — suppressed issues consume zero resources.
///
/// This is the legacy entry point kept for backward compatibility. It
/// assumes no platform context is available and falls back to
/// platform-agnostic checks. New callers should use
/// [`shouldSuppressWithProfile`].
pub fn shouldSuppress(issue: *const Issue) bool {
    return shouldSuppressWithProfile(issue, null);
}

/// Platform-aware variant of [`shouldSuppress`].
///
/// When a [`PlatformProfile`] is provided, platform-specific suppression
/// patterns are gated to the matching target:
///
///   - Windows MSVC CRT / SEH / typeinfo patterns are only consulted when
///     `profile.platform == .windows`. This avoids spurious matches on
///     Linux/macOS where these symbols would never legitimately appear.
///
/// All non-Windows / generic patterns (Rust drop chain, defensive coding,
/// static provenance, etc.) run unconditionally — they are inherently
/// language-/platform-agnostic and cheap.
pub fn shouldSuppressWithProfile(
    issue: *const Issue,
    profile: ?*const PlatformProfile,
) bool {
    // ════════════════════════════════════════════════════════════
    // GLOBAL GUARD: Real memory safety bugs are NEVER suppressed
    // ════════════════════════════════════════════════════════════
    //
    // Memory safety violations (double_free, use_after_free, invalid_free,
    // memory_leak) and FFI boundary issues (ffi_unsafe_call, cross_language_*)
    // represent GENUINE security vulnerabilities — even when they occur in
    // functions named "safe_*", involve Rust allocators (__rust_dealloc),
    // or mention NonNull types.
    //
    // The suppression patterns below are designed to filter FALSE POSITIVES
    // from intra-procedural detectors that can't see inter-procedural context.
    // They must NOT suppress real bugs that happen to share surface-level
    // characteristics with those false positive patterns.
    if (memory_safety_guard.isRealMemorySafetyBug(issue)) {
        log.debug("[SUPPRESS-PASS] {s} ({s}): Real memory safety bug — exempt from all patterns", .{
            issue.location.func, @tagName(issue.kind),
        });
        return false;
    }

    // P16-3: Patterns A-F deprecated — replaced by Resource Contract Graph system:
    //   - Pattern A (Rust Drop) → summary_inference.zig inferDestructorLikeSummary()
    //   - Pattern B (Static) → family_registry.zig + EscapeKind.static_lifetime
    //   - Pattern C (Panic cleanup) → OwnershipStateSolver.conditional_release
    //   - Pattern D (OS API) → PlatformFilter + FFI boundary classification
    //   - Pattern E (Safe example) → CandidateBuilder scoring (BONUS_FFI_BOUNDARY)
    //   - Pattern F (Defensive coding) → IssueVerifier structural pattern inference
    //
    // Kept as comments for reference until all call sites fully migrated.

    // Pattern G: Stdlib internal function (language runtime / standard library)
    if (suppression_patterns.isStdlibInternalFunction(issue)) {
        log.debug("[SUPPRESS-STDLIB] {s}: Stdlib internal function", .{issue.location.func});
        return true;
    }

    // Pattern H: Platform Runtime / Compiler-Generated Shim
    if (suppression_patterns.isPlatformRuntimeShimGated(issue.location.func, profile)) {
        log.debug("[SUPPRESS-RUNTIME] {s}: Platform runtime shim", .{
            issue.location.func,
        });
        return true;
    }

    return false;
}
