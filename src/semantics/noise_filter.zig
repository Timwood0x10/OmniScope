//! Cross-Language Noise Reduction Engine — Report-Side Risk Weighting
//!
//! This module provides risk-level assignment for detected issues based on
//! function origin classification. Surface classification (which determines
//! whether a function should be analyzed) is handled by the SurfaceClassifier
//! subsystem in src/semantics/surface_classifier/.
//!
//! Key types:
//!   - FunctionOrigin: legacy 5-value origin enum (for report-level compat)
//!   - FunctionSurface: new 7-value surface enum (from surface_classifier)
//!   - RiskLevel: issue priority (critical → suppressed)
//!   - getRiskLevel(): maps origin × severity → risk level
//!   - ClassificationResult: origin + risk + reason tuple
//!   - FilterStats: counting statistics for classification results

const std = @import("std");
const CommonTypes = @import("../common/types.zig");

// ============================================================================
// Re-exports from SurfaceClassifier
// ============================================================================

/// Re-export FunctionSurface from the canonical surface_classifier module.
/// New code should use FunctionSurface directly instead of FunctionOrigin.
pub const FunctionSurface = @import("surface_classifier/surface_classifier.zig").FunctionSurface;

/// Convert FunctionSurface to FunctionOrigin for backward compatibility.
/// Maps the newer 7-value surface classification to the legacy 5-value origin.
pub fn functionSurfaceToOrigin(surf: FunctionSurface) FunctionOrigin {
    return switch (surf) {
        .user_code => .user,
        .dependency => .third_party,
        .boundary => .user,
        .standard_library => .stdlib,
        .compiler_generated => .compiler_generated,
        .runtime => .stdlib,
        .unknown => .unknown,
    };
}

// ============================================================================
// Re-exports
// ============================================================================

/// Re-export Severity for backward compatibility.
/// New code should import from common/types.zig directly.
pub const Severity = CommonTypes.Severity;

// ============================================================================
// Core Types
// ============================================================================

/// Origin classification for functions.
/// Determines whether a function should be analyzed or suppressed.
/// NOTE: New code should prefer FunctionSurface (7 values) over FunctionOrigin (5 values).
pub const FunctionOrigin = enum(u8) {
    /// User-defined code - high priority for analysis.
    user,

    /// Standard library / runtime internal code - suppress by default.
    stdlib,

    /// Compiler-generated glue code (drop glue, shims, etc.) - ignore.
    compiler_generated,

    /// Third-party library code - analyze but lower priority.
    third_party,

    /// Unknown origin - needs further classification.
    unknown,

    pub fn toString(self: FunctionOrigin) []const u8 {
        return switch (self) {
            .user => "USER",
            .stdlib => "STDLIB",
            .compiler_generated => "COMPILER_GEN",
            .third_party => "THIRD_PARTY",
            .unknown => "UNKNOWN",
        };
    }

    /// Should issues from this origin be reported by default?
    pub fn shouldReportByDefault(self: FunctionOrigin) bool {
        return switch (self) {
            .user => true,
            .stdlib => false,
            .compiler_generated => false,
            .third_party => true,
            .unknown => true,
        };
    }
};

/// Risk level for issues based on function origin and issue type.
/// This is the canonical RiskLevel definition used across all noise reduction layers.
pub const RiskLevel = enum(u8) {
    /// Critical - must fix immediately (FFI boundary bugs).
    critical,

    /// High - should fix soon (user unsafe code).
    high,

    /// Medium - investigate when possible.
    medium,

    /// Low - informational only.
    low,

    /// Suppressed - not worth reporting (stdlib noise).
    suppressed,

    pub fn toString(self: RiskLevel) []const u8 {
        return switch (self) {
            .critical => "CRITICAL",
            .high => "HIGH",
            .medium => "MEDIUM",
            .low => "LOW",
            .suppressed => "SUPPRESSED",
        };
    }

    /// Check if this risk level meets a minimum threshold.
    /// Note: lower enum value = higher priority (critical=0 < high=1 < ... < suppressed=4)
    pub fn meetsThreshold(self: RiskLevel, min: RiskLevel) bool {
        return @intFromEnum(self) <= @intFromEnum(min);
    }
};

/// Classification result with origin and risk level.
pub const ClassificationResult = struct {
    origin: FunctionOrigin,
    risk_level: RiskLevel,
    reason: []const u8,
};

/// Source language for classification.
pub const Language = enum(u8) {
    rust,
    zig,
    go,
    c,
    cpp,
    csharp,
    python,
    java,
    unknown,
};

// ============================================================================
// Risk Weighting
// ============================================================================

/// Get effective risk level based on origin and issue severity.
///
/// This implements the risk weighting system:
/// - user + dangerous sink = HIGH/CRITICAL
/// - stdlib + leak = SUPPRESSED
/// - compiler_generated + anything = SUPPRESS/IGNORE
pub fn getRiskLevel(origin: FunctionOrigin, base_severity: Severity) RiskLevel {
    return switch (origin) {
        .compiler_generated => switch (base_severity) {
            .critical, .high => .suppressed,
            .medium, .low => .suppressed,
        },
        .stdlib => switch (base_severity) {
            .critical => .low,
            .high => .low,
            .medium => .suppressed,
            .low => .suppressed,
        },
        .third_party => switch (base_severity) {
            .critical => .high,
            .high => .medium,
            .medium => .low,
            .low => .suppressed,
        },
        .user => switch (base_severity) {
            .critical => .critical,
            .high => .high,
            .medium => .medium,
            .low => .low,
        },
        .unknown => switch (base_severity) {
            .critical => .high,
            .high => .medium,
            .medium => .low,
            .low => .suppressed,
        },
    };
}

// ============================================================================
// Statistics
// ============================================================================

/// Statistics for noise filtering results.
pub const FilterStats = struct {
    user_count: u32 = 0,
    stdlib_count: u32 = 0,
    compiler_count: u32 = 0,
    third_party_count: u32 = 0,
    unknown_count: u32 = 0,
    suppressed_issues: u32 = 0,

    pub fn record(self: *FilterStats, result: ClassificationResult) void {
        switch (result.origin) {
            .user => self.user_count += 1,
            .stdlib => self.stdlib_count += 1,
            .compiler_generated => self.compiler_count += 1,
            .third_party => self.third_party_count += 1,
            .unknown => self.unknown_count += 1,
        }

        if (result.risk_level == .suppressed) {
            self.suppressed_issues += 1;
        }
    }

    pub fn total(self: FilterStats) u32 {
        return self.user_count + self.stdlib_count + self.compiler_count +
            self.third_party_count + self.unknown_count;
    }

    pub fn suppressionRatio(self: FilterStats) f64 {
        const t = self.total();
        if (t == 0) return 0.0;
        return @as(f64, @floatFromInt(self.compiler_count + self.stdlib_count)) /
            @as(f64, @floatFromInt(t));
    }
};

// ============================================================================
// Tests
// ============================================================================

test "getRiskLevel - user code preserves severity" {
    try std.testing.expectEqual(RiskLevel.critical, getRiskLevel(.user, .critical));
    try std.testing.expectEqual(RiskLevel.high, getRiskLevel(.user, .high));
    try std.testing.expectEqual(RiskLevel.medium, getRiskLevel(.user, .medium));
    try std.testing.expectEqual(RiskLevel.low, getRiskLevel(.user, .low));
}

test "getRiskLevel - compiler generated always suppressed" {
    try std.testing.expectEqual(RiskLevel.suppressed, getRiskLevel(.compiler_generated, .critical));
    try std.testing.expectEqual(RiskLevel.suppressed, getRiskLevel(.compiler_generated, .medium));
}

test "getRiskLevel - stdlib downgrades severity" {
    try std.testing.expectEqual(RiskLevel.low, getRiskLevel(.stdlib, .critical));
    try std.testing.expectEqual(RiskLevel.suppressed, getRiskLevel(.stdlib, .medium));
}

test "FilterStats - tracking" {
    var stats = FilterStats{};
    stats.record(.{ .origin = .user, .risk_level = .high, .reason = "test" });
    stats.record(.{ .origin = .stdlib, .risk_level = .suppressed, .reason = "test" });
    stats.record(.{ .origin = .compiler_generated, .risk_level = .suppressed, .reason = "test" });
    try std.testing.expectEqual(@as(u32, 1), stats.user_count);
    try std.testing.expectEqual(@as(u32, 1), stats.stdlib_count);
    try std.testing.expectEqual(@as(u32, 2), stats.suppressed_issues);
    try std.testing.expectEqual(@as(u32, 3), stats.total());
}

test "functionSurfaceToOrigin - mapping" {
    try std.testing.expectEqual(FunctionOrigin.user, functionSurfaceToOrigin(.user_code));
    try std.testing.expectEqual(FunctionOrigin.third_party, functionSurfaceToOrigin(.dependency));
    try std.testing.expectEqual(FunctionOrigin.user, functionSurfaceToOrigin(.boundary));
    try std.testing.expectEqual(FunctionOrigin.stdlib, functionSurfaceToOrigin(.standard_library));
    try std.testing.expectEqual(FunctionOrigin.compiler_generated, functionSurfaceToOrigin(.compiler_generated));
    try std.testing.expectEqual(FunctionOrigin.stdlib, functionSurfaceToOrigin(.runtime));
    try std.testing.expectEqual(FunctionOrigin.unknown, functionSurfaceToOrigin(.unknown));
}

test "FunctionSurface.shouldAnalyze - boundary and unknown preserved" {
    // These are critical: boundary and unknown must never be suppressed
    try std.testing.expect(FunctionSurface.boundary.shouldAnalyze());
    try std.testing.expect(FunctionSurface.unknown.shouldAnalyze());
}

test "FunctionSurface.shouldAnalyze - runtime and stdlib skipped" {
    try std.testing.expect(!FunctionSurface.runtime.shouldAnalyze());
    try std.testing.expect(!FunctionSurface.standard_library.shouldAnalyze());
    try std.testing.expect(!FunctionSurface.compiler_generated.shouldAnalyze());
}

test "functionSurfaceToOrigin + getRiskLevel - boundary treated as user" {
    // Boundary surfaces should get user-level risk (not suppressed)
    const origin = functionSurfaceToOrigin(.boundary);
    try std.testing.expectEqual(FunctionOrigin.user, origin);
    try std.testing.expectEqual(RiskLevel.critical, getRiskLevel(origin, .critical));
    try std.testing.expectEqual(RiskLevel.high, getRiskLevel(origin, .high));
}

test "functionSurfaceToOrigin + getRiskLevel - dependency treated as third_party" {
    const origin = functionSurfaceToOrigin(.dependency);
    try std.testing.expectEqual(FunctionOrigin.third_party, origin);
    try std.testing.expectEqual(RiskLevel.high, getRiskLevel(origin, .critical));
    try std.testing.expectEqual(RiskLevel.medium, getRiskLevel(origin, .high));
}

test "functionSurfaceToOrigin + getRiskLevel - runtime treated as stdlib" {
    const origin = functionSurfaceToOrigin(.runtime);
    try std.testing.expectEqual(FunctionOrigin.stdlib, origin);
    try std.testing.expectEqual(RiskLevel.low, getRiskLevel(origin, .critical));
    try std.testing.expectEqual(RiskLevel.suppressed, getRiskLevel(origin, .medium));
}
