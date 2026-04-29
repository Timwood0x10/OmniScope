//! Context-Aware Severity Re-ranking Rules
//!
//! Boosts or suppresses issue severity based on runtime context
//! beyond the static registry definition.
//!
//! The registry defines BASE severity. This module applies CONTEXTUAL
//! adjustments based on:
//!   - Dangerous pattern combinations (e.g., dlclose + live pointer)
//!   - Security-sensitive domains (e.g., crypto NULL checks)
//!   - Known noise patterns (e.g., llvm.threadlocal)
//!
//! Reference: plan/v0.1.8.md P0-3

const std = @import("std");

/// Maximum severity value for critical issues.
pub const CRITICAL_BOOST: u8 = 2; // medium(0) → high(1) → critical(2)

/// Check if an issue should have its severity boosted.
///
/// Returns the boosted severity if adjustment applies,
/// null if the base severity should be kept as-is.
pub fn severity_boost_for_pattern(
    base_severity: u8,
    func_name: []const u8,
    issue_type: []const u8,
) ?u8 {
    if (base_severity > 2) return null;
    // ── Pattern 1: dlclose with potentially-live pointers → CRITICAL
    // Use-after-free risk when unloading a library while handles exist
    if (std.mem.indexOf(u8, func_name, "dlclose") != null) {
        // Any dlclose call is potentially dangerous — boost to HIGH minimum
        if (base_severity < 1) return 1;
        // If already has context suggesting UAF, boost to CRITICAL
        if (std.mem.indexOf(u8, issue_type, "use-after-free") != null or
            std.mem.indexOf(u8, issue_type, "alive") != null)
        {
            return CRITICAL_BOOST;
        }
    }

    // ── Pattern 2: Crypto API NULL check failure → HIGH
    // Missing NULL check on crypto allocation = potential key material leak
    const crypto_patterns = [_][]const u8{
        "EVP_", "RSA_", "DSA_", "EC_", "AES_",
        "BIO_", "HMAC_", "SHA", "MD5",
    };
    for (crypto_patterns) |pat| {
        if (std.mem.indexOf(u8, func_name, pat) != null) {
            if (std.mem.indexOf(u8, issue_type, "null") != null and
                base_severity < 1)
            {
                return 1; // MEDIUM → HIGH for crypto
            }
        }
    }

    // ── Pattern 3: Callback escape → HIGH
    // Stack frame outlived by async/callback mechanism
    if (std.mem.indexOf(u8, issue_type, "callback") != null or
        std.mem.indexOf(u8, issue_type, "escape") != null)
    {
        if (base_severity < 1) return 1;
    }

    // ── Pattern 4: Return value escape through FFI boundary → HIGH
    if (std.mem.indexOf(u8, issue_type, "return-value-escape") != null) {
        return 1; // Always HIGH — cross-boundary lifetime violation
    }

    // ── Pattern 5: Resource use-after-free / double-free → CRITICAL
    if (std.mem.indexOf(u8, issue_type, "uaf") != null or
        std.mem.indexOf(u8, issue_type, "double-free") != null)
    {
        return CRITICAL_BOOST;
    }

    // ── Pattern 6: fork in multithreaded context → HIGH
    // At-fork handler missing can cause deadlock/corruption
    if (std.mem.indexOf(u8, func_name, "fork") != null) {
        if (base_severity < 1) return 1;
    }

    return null; // No boost needed
}

/// Check if an issue should be suppressed entirely due to low-severity noise.
///
/// Returns true if the issue should NOT be reported.
pub fn should_suppress_for_noise(func_name: []const u8) bool {
    // llvm.* intrinsics are always suppressed here
    // (primary suppression is in noise_reduction Layer 1)
    if (std.mem.startsWith(u8, func_name, "llvm.")) return true;

    // Thread-local address patterns are never real FFI issues
    if (std.mem.indexOf(u8, func_name, "threadlocal") != null) return true;

    return false;
}

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "severity_boost - dlclose UAF → CRITICAL" {
    const result = severity_boost_for_pattern(1, "dlclose", "use-after-free detected");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(CRITICAL_BOOST, result.?);
}

test "severity_boost - dlclose basic → HIGH" {
    const result = severity_boost_for_pattern(0, "dlclose", "contract violation");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 1), result.?);
}

test "severity_boost - crypto NULL → HIGH" {
    const result = severity_boost_for_pattern(0, "EVP_CIPHER_CTX_new", "null not checked");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 1), result.?);
}

test "severity_boost - callback escape → HIGH" {
    const result = severity_boost_for_pattern(0, "pthread_create", "callback escape");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 1), result.?);
}

test "severity_boost - return-value-escape → HIGH" {
    const result = severity_boost_for_pattern(0, "malloc", "return-value-escape global");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 1), result.?);
}

test "severity_boost - resource UAF → CRITICAL" {
    const result = severity_boost_for_pattern(1, "free", "uaf on handle");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(CRITICAL_BOOST, result.?);
}

test "severity_boost - fork multithreaded → HIGH" {
    const result = severity_boost_for_pattern(0, "fork", "missing at-fork handler");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 1), result.?);
}

test "severity_boost - no boost needed" {
    // Normal function with no special pattern
    const result = severity_boost_for_pattern(1, "printf", "format string");
    try std.testing.expect(result == null);

    // Already CRITICAL stays CRITICAL
    const result2 = severity_boost_for_pattern(2, "dangerous_func", "any issue");
    try std.testing.expect(result2 == null);
}

test "should_suppress_for_noise - llvm intrinsics" {
    try std.testing.expect(should_suppress_for_noise("llvm.threadlocal.address"));
    try std.testing.expect(should_suppress_for_noise("llvm.lifetime.start.p0i8"));

    // Real FFI functions should NOT be suppressed
    try std.testing.expect(!should_suppress_for_noise("dlopen"));
    try std.testing.expect(!should_suppress_for_noise("malloc"));
}
