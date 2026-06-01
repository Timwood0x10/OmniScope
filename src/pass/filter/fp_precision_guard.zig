//! FP Precision Guard — 误报防护门
//!
//! Enforces the hard gate from refactoring_plan.md §0.2:
//!   "You CANNOT remove existing FP filtering until MemoryGraph
//!    ownership precision ≥ current FP filtering effect."
//!
//! Provides:
//!   - PrecisionMetrics: FFI-Precision, Recall, F1, FP count
//!   - GateCheck: Automated pass/fail against baseline thresholds
//!   - ABComparison: Baseline vs candidate (registry+hooks) A/B test
//!
//! Usage:
//!   var guard = FPPrecisionGuard.init(allocator);
//!   defer guard.deinit();
//!   const result = try guard.runGateCheck(baseline_metrics, candidate_metrics);
//!   if (!result.passed) {
//!       // Cannot proceed with removal — precision regression detected
//!   }

const std = @import("std");

/// Precision metrics for a single analysis run.
/// Computed from issue output + ground truth (manual audit).
pub const PrecisionMetrics = struct {
    /// Total issues reported by analyzer
    total_issues: u32 = 0,
    /// Issues confirmed as true positives (real bugs)
    true_positives: u32 = 0,
    /// Issues confirmed as false positives (noise)
    false_positives: u32 = 0,
    /// Real bugs missed by analyzer (from manual audit)
    false_negatives: u32 = 0,
    /// Total real bugs in target (ground truth)
    total_actual_bugs: u32 = 0,
    /// Functions analyzed
    functions_analyzed: u32 = 0,
    /// Functions skipped by noise reduction
    functions_skipped: u32 = 0,

    /// FFI-specific precision: TP / (TP + FP) for FFI boundary issues only.
    /// Target: ≥ 88% (refactoring_plan.md §0.2 baseline).
    pub fn ffiPrecision(self: PrecisionMetrics) f32 {
        const tp_plus_fp = @as(f32, @floatFromInt(self.true_positives)) +
            @as(f32, @floatFromInt(self.false_positives));
        if (tp_plus_fp == 0) return 1.0;
        return @as(f32, @floatFromInt(self.true_positives)) / tp_plus_fp;
    }

    /// Overall recall: TP / (TP + FN).
    pub fn recall(self: PrecisionMetrics) f32 {
        const tp_plus_fn = @as(f32, @floatFromInt(self.true_positives)) +
            @as(f32, @floatFromInt(self.false_negatives));
        if (tp_plus_fn == 0) return 1.0;
        return @as(f32, @floatFromInt(self.true_positives)) / tp_plus_fn;
    }

    /// F1 score: harmonic mean of precision and recall.
    pub fn f1Score(self: PrecisionMetrics) f32 {
        const p = self.ffiPrecision();
        const r = self.recall();
        if (p + r == 0) return 0;
        return 2 * p * r / (p + r);
    }

    /// False positive rate: FP / (TP + FP).
    pub fn fpRate(self: PrecisionMetrics) f32 {
        const tp_plus_fp = @as(f32, @floatFromInt(self.true_positives)) +
            @as(f32, @floatFromInt(self.false_positives));
        if (tp_plus_fp == 0) return 0;
        return @as(f32, @floatFromInt(self.false_positives)) / tp_plus_fp;
    }

    /// Noise reduction ratio: (issues_before_filter - issues_after) / issues_before_filter.
    /// Target: ≥ 97% on wasmtime (refactoring_plan.md §0.2 baseline).
    pub fn noiseReductionRatio(self: PrecisionMetrics, issues_before_filter: u32) f32 {
        if (issues_before_filter == 0) return 1.0;
        const reduced = @as(i32, @intCast(issues_before_filter)) - @as(i32, @intCast(self.total_issues));
        if (reduced < 0) return 0;
        return @as(f32, @floatFromInt(reduced)) / @as(f32, @floatFromInt(issues_before_filter));
    }

    /// Skip ratio: functions_skipped / (functions_analyzed + functions_skipped).
    pub fn skipRatio(self: PrecisionMetrics) f32 {
        const total = self.functions_analyzed + self.functions_skipped;
        if (total == 0) return 0;
        return @as(f32, @floatFromInt(self.functions_skipped)) / @as(f32, @floatFromInt(total));
    }

    pub fn format(
        self: PrecisionMetrics,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll("\n╔══════════════════════════════════════╗\n");
        try writer.writeAll("║     FP Precision Metrics              ║\n");
        try writer.writeAll("╠══════════════════════════════════════╣\n");
        try writer.print("║  Total issues:     {d:>8}            ║\n", .{self.total_issues});
        try writer.print("║  True Positives:   {d:>8}            ║\n", .{self.true_positives});
        try writer.print("║  False Positives:  {d:>8}            ║\n", .{self.false_positives});
        try writer.print("║  False Negatives:  {d:>8}            ║\n", .{self.false_negatives});
        try writer.print("║  FFI-Precision:    {d:>8.1}%          ║\n", .{self.ffiPrecision() * 100});
        try writer.print("║  Recall:           {d:>8.1}%          ║\n", .{self.recall() * 100});
        try writer.print("║  F1 Score:         {d:>8.2}           ║\n", .{self.f1Score()});
        try writer.print("║  FP Rate:          {d:>8.1}%          ║\n", .{self.fpRate() * 100});
        try writer.print("║  Funcs analyzed:   {d:>8}            ║\n", .{self.functions_analyzed});
        try writer.print("║  Funcs skipped:    {d:>8}            ║\n", .{self.functions_skipped});
        try writer.writeAll("╚══════════════════════════════════════╝\n");
    }
};

/// Gate thresholds from refactoring_plan.md §0.2.
/// These are HARD minimums — falling below any one blocks removal.
pub const GateThresholds = struct {
    /// Minimum FFI-Precision required (baseline: ~88%)
    min_ffi_precision: f32 = 0.88,
    /// Maximum FP count allowed (baseline: ~0 for FFI-FFI)
    max_fp_count: u32 = 2,
    /// Minimum noise reduction on wasmtime (baseline: 97%)
    min_noise_reduction: f32 = 0.97,
    /// Maximum acceptable precision drop from baseline (absolute)
    max_precision_drop: f32 = 0.03,

    pub fn format(
        self: GateThresholds,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll("\n┌──────────────────────────────────────┐\n");
        try writer.writeAll("│  FP Precision Gate Thresholds        │\n");
        try writer.writeAll("├──────────────────────────────────────┤\n");
        try writer.print("│  Min FFI-Precision:  {d:.0}%           │\n", .{self.min_ffi_precision * 100});
        try writer.print("│  Max FP count:        {d}               │\n", .{self.max_fp_count});
        try writer.print("│  Min noise reduction: {d:.0}%           │\n", .{self.min_noise_reduction * 100});
        try writer.print("│  Max precision drop:  {d:.1}%            │\n", .{self.max_precision_drop * 100});
        try writer.writeAll("└──────────────────────────────────────┘\n");
    }
};

/// Result of a single gate check.
///
/// **Ownership**: `violations` slice is heap-allocated by `runGateCheck()`.
/// Caller MUST free it: `defer guard.allocator.free(result.violations);`
pub const GateResult = struct {
    passed: bool,
    precision_delta: f32,
    fp_count_delta: i32,
    noise_reduction_ratio: f32,
    violations: []const GateViolation,

    pub fn format(
        self: GateResult,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        const status = if (self.passed) "PASS" else "**FAIL**";
        try writer.writeAll("\n╔══════════════════════════════════════╗\n");
        try writer.print("║  Gate Result: {s:<24}    ║\n", .{status});
        try writer.writeAll("╠══════════════════════════════════════╣\n");
        try writer.print("│  Precision delta: {d:+.1}%               │\n", .{self.precision_delta * 100});
        try writer.print("│  FP count delta:  {:+d}                 │\n", .{self.fp_count_delta});
        try writer.print("│  Noise reduction: {d:.1}%                │\n", .{self.noise_reduction_ratio * 100});
        if (self.violations.len > 0) {
            try writer.writeAll("│  Violations:                            │\n");
            for (self.violations) |v| {
                try writer.print("│    - {s}                              │\n", .{v.message});
            }
        } else {
            try writer.writeAll("│  Violations: none                       │\n");
        }
        try writer.writeAll("╚══════════════════════════════════════╝\n");
    }
};

/// A single threshold violation.
pub const GateViolation = struct {
    /// Which threshold was violated
    threshold_name: []const u8,
    /// Human-readable explanation
    message: []const u8,
    /// Actual value vs required value
    actual: f32,
    required: f32,
};

/// FP Precision Guard — enforces §0.2 gate rules.
pub const FPPrecisionGuard = struct {
    allocator: std.mem.Allocator,
    violations_list: std.ArrayList(GateViolation),

    pub fn init(allocator: std.mem.Allocator) error{OutOfMemory}!FPPrecisionGuard {
        return .{
            .allocator = allocator,
            .violations_list = try std.ArrayList(GateViolation).initCapacity(allocator, 4),
        };
    }

    pub fn deinit(self: *FPPrecisionGuard) void {
        self.violations_list.deinit(self.allocator);
    }

    /// Run gate check comparing candidate metrics against baseline.
    ///
    /// Parameters:
    ///   - baseline: Metrics from current (old) FP filtering system
    ///   - candidate: Metrics from new (registry+hooks) system
    ///   - issues_before_filter: Issue count before ANY filtering (for noise ratio)
    ///   - thresholds: Custom thresholds (uses defaults if null)
    ///
    /// Returns:
    ///   - GateResult with pass/fail and violation details
    pub fn runGateCheck(
        self: *FPPrecisionGuard,
        baseline: PrecisionMetrics,
        candidate: PrecisionMetrics,
        issues_before_filter: u32,
        thresholds: ?GateThresholds,
    ) !GateResult {
        const t = thresholds orelse GateThresholds{};
        self.violations_list.clearRetainingCapacity();

        const candidate_precision = candidate.ffiPrecision();
        const baseline_precision = baseline.ffiPrecision();
        const precision_drop = baseline_precision - candidate_precision;

        // Rule 1: FFI-Precision must be ≥ threshold
        if (candidate_precision < t.min_ffi_precision) {
            try self.violations_list.append(self.allocator, .{
                .threshold_name = "min_ffi_precision",
                .message = "FFI-Precision below minimum threshold",
                .actual = candidate_precision,
                .required = t.min_ffi_precision,
            });
        }

        // Rule 2: Precision drop must be ≤ max_precision_drop
        if (precision_drop > t.max_precision_drop) {
            try self.violations_list.append(self.allocator, .{
                .threshold_name = "max_precision_drop",
                .message = "Precision dropped more than allowed from baseline",
                .actual = precision_drop,
                .required = t.max_precision_drop,
            });
        }

        // Rule 3: FP count must not exceed max
        if (candidate.false_positives > t.max_fp_count) {
            try self.violations_list.append(self.allocator, .{
                .threshold_name = "max_fp_count",
                .message = "False positive count exceeds maximum allowed",
                .actual = @floatFromInt(candidate.false_positives),
                .required = @floatFromInt(t.max_fp_count),
            });
        }

        // Rule 4: Noise reduction must meet minimum
        const noise_ratio = candidate.noiseReductionRatio(issues_before_filter);
        if (noise_ratio < t.min_noise_reduction) {
            try self.violations_list.append(self.allocator, .{
                .threshold_name = "min_noise_reduction",
                .message = "Noise reduction ratio below minimum threshold",
                .actual = noise_ratio,
                .required = t.min_noise_reduction,
            });
        }

        const violations_slice = try self.violations_list.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(violations_slice);

        return .{
            .passed = violations_slice.len == 0,
            .precision_delta = candidate_precision - baseline_precision,
            .fp_count_delta = @as(i32, @intCast(candidate.false_positives)) -
                @as(i32, @intCast(baseline.false_positives)),
            .noise_reduction_ratio = noise_ratio,
            .violations = violations_slice,
        };
    }

    /// Quick sanity check: does a single metrics set meet minimum quality bar?
    /// Use this for standalone validation (no A/B comparison needed).
    pub fn meetsMinimumQuality(
        self: *FPPrecisionGuard,
        metrics: PrecisionMetrics,
        thresholds: ?GateThresholds,
    ) !bool {
        _ = self;
        const t = thresholds orelse GateThresholds{};
        return metrics.ffiPrecision() >= t.min_ffi_precision and
            metrics.false_positives <= t.max_fp_count;
    }
};

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "PrecisionMetrics - perfect precision" {
    const m = PrecisionMetrics{
        .true_positives = 10,
        .false_positives = 0,
        .false_negatives = 0,
        .total_actual_bugs = 10,
    };
    try std.testing.expectApproxEqAbs(m.ffiPrecision(), 1.0, 0.001);
    try std.testing.expectApproxEqAbs(m.recall(), 1.0, 0.001);
    try std.testing.expectApproxEqAbs(m.f1Score(), 1.0, 0.001);
    try std.testing.expectApproxEqAbs(m.fpRate(), 0.0, 0.001);
}

test "PrecisionMetrics - typical scenario" {
    const m = PrecisionMetrics{
        .true_positives = 44,
        .false_positives = 6,
        .false_negatives = 12,
        .total_actual_bugs = 56,
        .total_issues = 50,
        .functions_analyzed = 159,
        .functions_skipped = 460,
    };
    try std.testing.expectApproxEqAbs(m.ffiPrecision(), 0.88, 0.01);
    try std.testing.expectApproxEqAbs(m.recall(), 0.786, 0.01);
    try std.testing.expectApproxEqAbs(m.fpRate(), 0.12, 0.01);
    try std.testing.expectApproxEqAbs(m.skipRatio(), 0.743, 0.01);
}

test "PrecisionMetrics - zero division safety" {
    const empty = PrecisionMetrics{};
    try std.testing.expectApproxEqAbs(empty.ffiPrecision(), 1.0, 0.001);
    try std.testing.expectApproxEqAbs(empty.recall(), 1.0, 0.001);
    try std.testing.expectApproxEqAbs(empty.fpRate(), 0.0, 0.001);
}

test "PrecisionMetrics - noiseReductionRatio" {
    const m = PrecisionMetrics{ .total_issues = 9 };
    try std.testing.expectApproxEqAbs(m.noiseReductionRatio(297), 0.9697, 0.001);
    try std.testing.expectApproxEqAbs(m.noiseReductionRatio(0), 1.0, 0.001);
}

test "GateCheck - passes when candidate matches or exceeds baseline" {
    var guard = try FPPrecisionGuard.init(std.testing.allocator);
    defer guard.deinit();

    const baseline = PrecisionMetrics{
        .true_positives = 44,
        .false_positives = 0,
        .false_negatives = 12,
    };

    const candidate = PrecisionMetrics{
        .true_positives = 44,
        .false_positives = 1,
        .false_negatives = 12,
    };

    const result = try guard.runGateCheck(baseline, candidate, 297, null);
    defer guard.allocator.free(result.violations);

    try std.testing.expect(result.passed);
    try std.testing.expect(result.fp_count_delta >= 0);
}

test "GateCheck - fails when precision drops too much" {
    var guard = try FPPrecisionGuard.init(std.testing.allocator);
    defer guard.deinit();

    const baseline = PrecisionMetrics{
        .true_positives = 44,
        .false_positives = 0,
        .false_negatives = 12,
    };

    const candidate = PrecisionMetrics{
        .true_positives = 30,
        .false_positives = 20,
        .false_negatives = 20,
    };

    const result = try guard.runGateCheck(baseline, candidate, 297, null);
    defer guard.allocator.free(result.violations);

    try std.testing.expect(!result.passed);
    try std.testing.expect(result.violations.len > 0);
}

test "GateCheck - fails when FP count exceeds limit" {
    var guard = try FPPrecisionGuard.init(std.testing.allocator);
    defer guard.deinit();

    const baseline = PrecisionMetrics{
        .true_positives = 44,
        .false_positives = 0,
        .false_negatives = 12,
    };

    const candidate = PrecisionMetrics{
        .true_positives = 44,
        .false_positives = 5,
        .false_negatives = 12,
    };

    const custom_thresholds = GateThresholds{ .max_fp_count = 2 };
    const result = try guard.runGateCheck(baseline, candidate, 297, custom_thresholds);
    defer guard.allocator.free(result.violations);

    try std.testing.expect(!result.passed);
}

test "GateCheck - fails when noise reduction insufficient" {
    var guard = try FPPrecisionGuard.init(std.testing.allocator);
    defer guard.deinit();

    const baseline = PrecisionMetrics{
        .true_positives = 44,
        .false_positives = 0,
        .false_negatives = 12,
        .total_issues = 50,
    };

    const candidate = PrecisionMetrics{
        .true_positives = 44,
        .false_positives = 0,
        .false_negatives = 12,
        .total_issues = 200,
    };

    const result = try guard.runGateCheck(baseline, candidate, 297, null);
    defer guard.allocator.free(result.violations);

    try std.testing.expect(!result.passed);

    const noise_ratio = candidate.noiseReductionRatio(297);
    try std.testing.expectApproxEqAbs(noise_ratio, 0.3266, 0.01);
}
