//! Unified FilterContext for the addIssue pipeline.
//!
//! Replaces scattered local variables in pass_types.zig's addIssue() with a
//! single context object that tracks an issue through all filtering layers.
//!
//! Pipeline layers (matching addIssue flow):
//!   Layer 0: category        — issue_classification.categorize()
//!   Layer 2: suppression     — issue_suppression.shouldSuppressWithProfile()
//!   Layer 3: origin          — classifyFunctionSurface()
//!   Layer 4: surface         — inferSemanticSurface()
//!   Layer 5: risk + downgrade — noise_filter.getRiskLevel() + surface gating
//!   Layer 6: severity        — anti-collapse step-down
//!   Layer 8: confidence      — from issue.confidence
//!   Layer 9: verifier        — from issue.verdict
//!   Dedup:   is_duplicate    — caller-managed dedup key check

const std = @import("std");
const types = @import("../common/types.zig");
const issue_mod = @import("../diag/issue.zig");
const issue_classification = @import("issue_classification.zig");
const noise_filter = @import("../semantics/noise_filter.zig");

// Re-export commonly used types for consumer convenience.
pub const IssueKind = types.IssueKind;
pub const Severity = types.Severity;
pub const SemanticSurface = types.SemanticSurface;
pub const IssueCategory = issue_classification.IssueCategory;
pub const FunctionOrigin = noise_filter.FunctionOrigin;
pub const RiskLevel = noise_filter.RiskLevel;
pub const Issue = issue_mod.Issue;

const log = std.log.scoped(.filter_context);

/// Suppression decision from the suppression layer (Layer 2).
pub const SuppressionVerdict = enum {
    /// Issue passes suppression and continues through the pipeline.
    pass,
    /// Issue is suppressed and should be dropped.
    suppress,
};

/// Verifier decision from the two-stage verifier (Layer 9).
pub const VerifierVerdict = enum {
    /// No verifier has run on this issue.
    unverified,
    /// Verifier confirmed the issue is real.
    confirmed,
    /// Verifier flagged the issue as likely a false positive.
    likely_false_positive,
    /// Verifier suppressed the issue entirely.
    suppressed,
};

/// Unified context tracking an issue through the addIssue filtering pipeline.
///
/// Each field corresponds to a decision or classification made at a specific
/// pipeline layer. The caller populates fields as the issue progresses, then
/// calls `shouldReport()` to get the final emit decision.
pub const FilterContext = struct {
    // ── Input fields (from Issue) ──────────────────────────────────────

    /// Issue kind (e.g. .use_after_free, .ffi_unsafe_call).
    issue_kind: IssueKind,
    /// Original severity before any filtering.
    original_severity: Severity,
    /// Function name where the issue was detected.
    func_name: []const u8,
    /// FFI boundary info if the issue is at a cross-language boundary.
    has_ffi_boundary: bool,

    // ── Layer 0: Category ─────────────────────────────────────────────

    /// Authoritative category from issue_classification.categorize().
    category: IssueCategory,

    // ── Layer 2: Suppression ──────────────────────────────────────────

    /// Whether the suppression layer decided to drop this issue.
    suppression_verdict: SuppressionVerdict = .pass,

    // ── Layer 3: Origin ───────────────────────────────────────────────

    /// Function origin classification (user, stdlib, compiler_generated, etc.).
    origin: FunctionOrigin = .unknown,

    // ── Layer 4: Semantic surface ─────────────────────────────────────

    /// Where the issue originates (boundary, internal_core, etc.).
    surface: ?SemanticSurface = null,

    // ── Layer 5: Risk and surface downgrade ───────────────────────────

    /// Risk level from noise_filter.getRiskLevel(origin, severity).
    risk_level: RiskLevel = .medium,
    /// Whether the issue has structural evidence of boundary reachability.
    has_boundary_evidence: bool = false,
    /// Whether the surface/downgrade layer changed the severity.
    was_downgraded: bool = false,
    /// Severity after surface-based downgrade (before noise filter).
    severity_after_surface: Severity = .low,

    // ── Layer 6: Final severity ───────────────────────────────────────

    /// Final severity after noise filter + anti-collapse.
    final_severity: Severity = .low,

    // ── Layer 8: Confidence ───────────────────────────────────────────

    /// Confidence score from the issue (0.0 to 1.0).
    confidence_score: f32 = 0.0,

    // ── Layer 9: Verifier ─────────────────────────────────────────────

    /// Verifier verdict if a two-stage verifier has run.
    verifier_verdict: VerifierVerdict = .unverified,

    // ── Dedup ─────────────────────────────────────────────────────────

    /// Whether this issue was already reported (caller-managed dedup key).
    is_duplicate: bool = false,

    // ── Derived flags ─────────────────────────────────────────────────

    /// Whether this issue kind is never suppressed (core_memory_safety,
    /// ffi_boundary, or security_critical).
    never_suppressed: bool = false,
    /// Whether this issue kind is never downgraded (core_memory_safety
    /// or security_critical).
    never_downgraded: bool = false,

    // ── Public API ────────────────────────────────────────────────────

    /// Initialize a FilterContext from an Issue, computing Layer 0
    /// (category) and derived flags.
    pub fn init(issue: *const Issue) FilterContext {
        const cat = issue_classification.categorize(issue.kind);
        return .{
            .issue_kind = issue.kind,
            .original_severity = issue.severity,
            .func_name = issue.location.func,
            .has_ffi_boundary = issue.ffi_boundary != null,
            .category = cat,
            .confidence_score = issue.confidence,
            .never_suppressed = issue_classification.isNeverSuppressed(issue.kind),
            .never_downgraded = issue_classification.isNeverDowngraded(issue.kind),
        };
    }

    /// Compute risk level from origin and original severity.
    /// Should be called after `origin` is set (Layer 3).
    pub fn computeRisk(self: *FilterContext) void {
        self.risk_level = noise_filter.getRiskLevel(
            self.origin,
            diagToNoiseSeverity(self.original_severity),
        );
    }

    /// Apply surface-based progressive downgrade (Layer 4-5).
    ///
    /// Rules:
    /// - write_to_immutable without boundary evidence: cap at MEDIUM
    /// - invalid_free HIGH without strong evidence: cap at MEDIUM
    /// - non-boundary surface without boundary evidence: cap at MEDIUM
    /// - runtime_internal: cap at LOW (unless never_downgraded)
    pub fn applySurfaceDowngrade(self: *FilterContext) void {
        const surface = self.surface orelse {
            self.severity_after_surface = self.original_severity;
            return;
        };

        var effective = self.original_severity;

        // write_to_immutable: structural evidence gating
        if (self.issue_kind == .write_to_immutable and effective != .low) {
            const has_structural = self.has_boundary_evidence or
                surface == .boundary or surface == .ffi_producer;
            if (!has_structural) {
                effective = .medium;
                log.debug("WRITE-IMMUTABLE-GATE: {s} -> medium (heuristic_only, surface={s})", .{
                    self.func_name, surface.name(),
                });
            }
        }

        // invalid_free HIGH: strong evidence required
        if (self.issue_kind == .invalid_free and effective == .high) {
            const has_strong = self.has_boundary_evidence or
                surface == .boundary or surface == .ffi_producer;
            if (!has_strong and (surface == .internal_core or
                surface == .runtime_internal or surface == .unknown))
            {
                effective = .medium;
                log.debug("INVALID-FREE-GATE: {s} HIGH->MEDIUM (weak provenance, surface={s})", .{
                    self.func_name, surface.name(),
                });
            }
        }

        // Non-boundary surface: HIGH/CRITICAL -> MEDIUM
        if (!self.has_boundary_evidence and !surface.allowsHigh()) {
            if (effective == .critical or effective == .high) {
                log.debug("SURFACE-DOWNGRADE: {s} in [{s}] {s}->{s} (surface={s}, no boundary evidence)", .{
                    @tagName(self.issue_kind),
                    self.func_name,
                    @tagName(effective),
                    @tagName(Severity.medium),
                    surface.name(),
                });
                effective = .medium;
            }
        }

        // runtime_internal: cap at LOW (unless never_downgraded)
        if (surface == .runtime_internal and effective != .low and !self.never_downgraded) {
            effective = .low;
        }

        self.severity_after_surface = effective;
        self.was_downgraded = (effective != self.original_severity);
    }

    /// Apply noise filter suppression and risk-based severity adjustment (Layer 5).
    ///
    /// FFI/core issues bypass risk suppression. Critical issues bypass
    /// risk suppression. Otherwise, suppressed risk drops the issue.
    pub fn applyNoiseFilter(self: *FilterContext) void {
        // Never-suppressed issues bypass risk suppression
        if (self.never_suppressed or self.has_ffi_boundary) {
            if (self.risk_level == .suppressed) {
                self.risk_level = .low;
            }
        } else if (self.original_severity != .critical and self.risk_level == .suppressed) {
            // Non-FFI, non-critical issues are suppressed by risk
            self.suppression_verdict = .suppress;
            self.final_severity = self.severity_after_surface;
            return;
        }

        // Critical issues always bypass risk suppression
        if (self.original_severity == .critical and self.risk_level == .suppressed) {
            self.risk_level = .critical;
        }

        self.computeFinalSeverity();
    }

    /// Compute final severity with anti-collapse step-down (Layer 6).
    ///
    /// Ensures severity drops by at most ONE level per downgrade trigger.
    /// Uses max(risk_severity, stepDown(original)) to prevent severity cliff.
    pub fn computeFinalSeverity(self: *FilterContext) void {
        const risk_sev = riskToSeverity(self.risk_level);

        // Anti-collapse: step down original by at most one level
        const stepped: Severity = switch (self.severity_after_surface) {
            .critical => .high,
            .high => .medium,
            .medium => .low,
            .low => .low,
        };

        // max(risk_severity, stepped_severity)
        const max_sev = severityMax(risk_sev, stepped);

        // Never-downgraded issues keep their original severity
        if (self.never_downgraded) {
            self.final_severity = self.severity_after_surface;
        } else {
            // Apply downgrade only if risk warrants it
            const should_downgrade = switch (self.severity_after_surface) {
                .critical => risk_sev != .critical,
                .high => risk_sev == .medium or risk_sev == .low,
                .medium => risk_sev == .low,
                .low => false,
            };
            self.final_severity = if (should_downgrade) max_sev else self.severity_after_surface;
        }
    }

    /// Final decision: should this issue be reported?
    ///
    /// Returns false if:
    /// - Suppression verdict is .suppress
    /// - Risk level is .suppressed (for non-never-suppressed issues)
    /// - Issue is a duplicate
    pub fn shouldReport(self: *const FilterContext) bool {
        // Layer 2: suppression check
        if (self.suppression_verdict == .suppress) {
            return false;
        }

        // Layer 5: risk-based suppression for non-protected issues
        if (!self.never_suppressed and self.risk_level == .suppressed) {
            return false;
        }

        // Dedup check
        if (self.is_duplicate) {
            return false;
        }

        return true;
    }

    /// Get the final severity after all filtering layers.
    pub fn getFinalSeverity(self: *const FilterContext) Severity {
        return self.final_severity;
    }

    /// Derive the IssueClassification (ffi_boundary vs local_only) from
    /// the issue kind and boundary evidence.
    pub fn deriveClassification(self: *const FilterContext) issue_mod.IssueClassification {
        const is_ffi_kind = switch (self.issue_kind) {
            .ffi_unsafe_call,
            .ffi_type_mismatch,
            .type_mismatch,
            .cross_language_leak,
            .cross_language_free,
            .borrow_escape,
            => true,
            else => false,
        };
        if (is_ffi_kind or self.has_ffi_boundary) {
            return .ffi_boundary;
        }
        return .local_only;
    }

    /// Convert an issue verdict string to a VerifierVerdict enum.
    pub fn parseVerifierVerdict(verdict: ?[]const u8) VerifierVerdict {
        const v = verdict orelse return .unverified;
        if (std.mem.eql(u8, v, "confirmed")) return .confirmed;
        if (std.mem.eql(u8, v, "likely_fp")) return .likely_false_positive;
        if (std.mem.eql(u8, v, "suppressed")) return .suppressed;
        return .unverified;
    }
};

// ── Internal helpers ───────────────────────────────────────────────────

/// Map diag Severity to noise_filter Severity (same enum, different module).
fn diagToNoiseSeverity(sev: Severity) noise_filter.Severity {
    return switch (sev) {
        .low => .low,
        .medium => .medium,
        .high => .high,
        .critical => .critical,
    };
}

/// Map noise_filter.RiskLevel to diag Severity.
fn riskToSeverity(risk: RiskLevel) Severity {
    return switch (risk) {
        .critical => .critical,
        .high => .high,
        .medium => .medium,
        .low => .low,
        .suppressed => .low,
    };
}

/// Return the more severe of two severities.
fn severityMax(a: Severity, b: Severity) Severity {
    if (@intFromEnum(a) >= @intFromEnum(b)) return a;
    return b;
}

// ============================================================================
// Tests
// ============================================================================

test "init computes category and derived flags for core memory safety" {
    const loc = types.Location.init("test_func");
    const issue = Issue.init(.use_after_free, "UAF detected", loc, .high, 0.9);
    const ctx = FilterContext.init(&issue);

    try std.testing.expect(ctx.category == .core_memory_safety);
    try std.testing.expect(ctx.never_suppressed);
    try std.testing.expect(ctx.never_downgraded);
    try std.testing.expectEqual(IssueKind.use_after_free, ctx.issue_kind);
    try std.testing.expectEqual(Severity.high, ctx.original_severity);
}

test "init computes category for ffi boundary issue" {
    const loc = types.Location.init("ffi_call");
    const issue = Issue.init(.ffi_unsafe_call, "unsafe FFI call", loc, .critical, 0.85);
    const ctx = FilterContext.init(&issue);

    try std.testing.expect(ctx.category == .ffi_boundary);
    try std.testing.expect(ctx.never_suppressed);
    try std.testing.expect(!ctx.never_downgraded);
}

test "init computes category for advisory issue" {
    const loc = types.Location.init("check_return");
    const issue = Issue.init(.unchecked_return, "unchecked return", loc, .low, 0.5);
    const ctx = FilterContext.init(&issue);

    try std.testing.expect(ctx.category == .advisory);
    try std.testing.expect(!ctx.never_suppressed);
    try std.testing.expect(!ctx.never_downgraded);
}

test "init computes category for security critical issue" {
    const loc = types.Location.init("exec_cmd");
    const issue = Issue.init(.command_injection, "cmd injection", loc, .critical, 0.95);
    const ctx = FilterContext.init(&issue);

    try std.testing.expect(ctx.category == .security_critical);
    try std.testing.expect(ctx.never_suppressed);
    try std.testing.expect(ctx.never_downgraded);
}

test "init computes category for leak" {
    const loc = types.Location.init("alloc_fn");
    const issue = Issue.init(.memory_leak, "leak detected", loc, .medium, 0.7);
    const ctx = FilterContext.init(&issue);

    try std.testing.expect(ctx.category == .leak);
    try std.testing.expect(!ctx.never_suppressed);
    try std.testing.expect(!ctx.never_downgraded);
}

test "computeRisk maps origin x severity correctly" {
    const loc = types.Location.init("user_func");
    const issue = Issue.init(.memory_leak, "leak", loc, .high, 0.8);
    var ctx = FilterContext.init(&issue);

    ctx.origin = .user;
    ctx.computeRisk();
    try std.testing.expectEqual(RiskLevel.high, ctx.risk_level);

    ctx.origin = .stdlib;
    ctx.computeRisk();
    try std.testing.expectEqual(RiskLevel.low, ctx.risk_level);

    ctx.origin = .compiler_generated;
    ctx.computeRisk();
    try std.testing.expectEqual(RiskLevel.suppressed, ctx.risk_level);
}

test "shouldReport returns true by default" {
    const loc = types.Location.init("func");
    const issue = Issue.init(.memory_leak, "msg", loc, .medium, 0.7);
    const ctx = FilterContext.init(&issue);
    try std.testing.expect(ctx.shouldReport());
}

test "shouldReport returns false when suppressed" {
    const loc = types.Location.init("func");
    const issue = Issue.init(.memory_leak, "msg", loc, .medium, 0.7);
    var ctx = FilterContext.init(&issue);
    ctx.suppression_verdict = .suppress;
    try std.testing.expect(!ctx.shouldReport());
}

test "shouldReport returns false for duplicate" {
    const loc = types.Location.init("func");
    const issue = Issue.init(.memory_leak, "msg", loc, .medium, 0.7);
    var ctx = FilterContext.init(&issue);
    ctx.is_duplicate = true;
    try std.testing.expect(!ctx.shouldReport());
}

test "shouldReport bypasses risk suppression for never-suppressed issues" {
    const loc = types.Location.init("func");
    const issue = Issue.init(.use_after_free, "UAF", loc, .high, 0.9);
    var ctx = FilterContext.init(&issue);
    ctx.risk_level = .suppressed;
    // never_suppressed issues bypass risk suppression
    try std.testing.expect(ctx.shouldReport());
}

test "shouldReport suppresses non-protected issues with suppressed risk" {
    const loc = types.Location.init("func");
    const issue = Issue.init(.unchecked_return, "msg", loc, .low, 0.5);
    var ctx = FilterContext.init(&issue);
    ctx.risk_level = .suppressed;
    try std.testing.expect(!ctx.shouldReport());
}

test "applySurfaceDowngrade caps write_to_immutable at medium without evidence" {
    const loc = types.Location.init("internal_func");
    const issue = Issue.init(.write_to_immutable, "write to const", loc, .high, 0.7);
    var ctx = FilterContext.init(&issue);
    ctx.surface = .internal_core;
    ctx.has_boundary_evidence = false;
    ctx.applySurfaceDowngrade();

    try std.testing.expectEqual(Severity.medium, ctx.severity_after_surface);
    try std.testing.expect(ctx.was_downgraded);
}

test "applySurfaceDowngrade preserves write_to_immutable with boundary evidence" {
    const loc = types.Location.init("ffi_func");
    const issue = Issue.init(.write_to_immutable, "write to const", loc, .high, 0.7);
    var ctx = FilterContext.init(&issue);
    ctx.surface = .boundary;
    ctx.has_boundary_evidence = true;
    ctx.applySurfaceDowngrade();

    try std.testing.expectEqual(Severity.high, ctx.severity_after_surface);
    try std.testing.expect(!ctx.was_downgraded);
}

test "applySurfaceDowngrade caps runtime_internal at low" {
    const loc = types.Location.init("rt_func");
    const issue = Issue.init(.memory_leak, "leak", loc, .high, 0.6);
    var ctx = FilterContext.init(&issue);
    ctx.surface = .runtime_internal;
    ctx.has_boundary_evidence = false;
    ctx.applySurfaceDowngrade();

    try std.testing.expectEqual(Severity.low, ctx.severity_after_surface);
}

test "applySurfaceDowngrade never downgrades core memory safety at runtime_internal" {
    const loc = types.Location.init("rt_func");
    const issue = Issue.init(.use_after_free, "UAF", loc, .high, 0.9);
    var ctx = FilterContext.init(&issue);
    ctx.surface = .runtime_internal;
    ctx.has_boundary_evidence = false;
    ctx.applySurfaceDowngrade();

    // never_downgraded issues keep original severity
    try std.testing.expectEqual(Severity.high, ctx.severity_after_surface);
}

test "computeFinalSeverity applies anti-collapse step-down" {
    const loc = types.Location.init("unknown_func");
    const issue = Issue.init(.memory_leak, "leak", loc, .critical, 0.6);
    var ctx = FilterContext.init(&issue);
    ctx.origin = .unknown;
    ctx.severity_after_surface = .critical;
    ctx.computeRisk();

    // unknown + critical -> risk = high
    try std.testing.expectEqual(RiskLevel.high, ctx.risk_level);
    ctx.computeFinalSeverity();

    // critical should step down to high (not drop to low)
    try std.testing.expectEqual(Severity.high, ctx.final_severity);
}

test "computeFinalSeverity never downgrades core memory safety bugs" {
    const loc = types.Location.init("unknown_func");
    const issue = Issue.init(.double_free, "DF", loc, .critical, 0.9);
    var ctx = FilterContext.init(&issue);
    ctx.origin = .unknown;
    ctx.severity_after_surface = .critical;
    ctx.computeRisk();
    ctx.computeFinalSeverity();

    // never_downgraded: keeps original severity
    try std.testing.expectEqual(Severity.critical, ctx.final_severity);
}

test "applyNoiseFilter upgrades suppressed risk to low for FFI issues" {
    const loc = types.Location.init("ffi_func");
    const issue = Issue.init(.ffi_unsafe_call, "unsafe", loc, .high, 0.8);
    var ctx = FilterContext.init(&issue);
    ctx.origin = .stdlib;
    ctx.computeRisk();
    // stdlib + high -> risk = low (not suppressed), but test suppressed case
    ctx.risk_level = .suppressed;
    ctx.severity_after_surface = .high;
    ctx.applyNoiseFilter();

    try std.testing.expectEqual(RiskLevel.low, ctx.risk_level);
    try std.testing.expect(ctx.shouldReport());
}

test "deriveClassification returns ffi_boundary for FFI issue kinds" {
    const loc = types.Location.init("ffi_func");
    const issue = Issue.init(.cross_language_free, "CLF", loc, .high, 0.85);
    const ctx = FilterContext.init(&issue);

    try std.testing.expectEqual(issue_mod.IssueClassification.ffi_boundary, ctx.deriveClassification());
}

test "deriveClassification returns local_only for non-FFI issue" {
    const loc = types.Location.init("local_func");
    const issue = Issue.init(.memory_leak, "leak", loc, .medium, 0.6);
    const ctx = FilterContext.init(&issue);

    try std.testing.expectEqual(issue_mod.IssueClassification.local_only, ctx.deriveClassification());
}

test "deriveClassification returns ffi_boundary when has_ffi_boundary is true" {
    const loc = types.Location.init("boundary_func");
    var issue = Issue.init(.memory_leak, "leak", loc, .medium, 0.6);
    issue.ffi_boundary = issue_mod.FFIBoundary.init(
        1,
        .rust_to_c,
        .rust,
        .c,
        "boundary_func",
        loc,
    );
    const ctx = FilterContext.init(&issue);

    try std.testing.expectEqual(issue_mod.IssueClassification.ffi_boundary, ctx.deriveClassification());
}

test "parseVerifierVerdict handles null" {
    try std.testing.expectEqual(VerifierVerdict.unverified, FilterContext.parseVerifierVerdict(null));
}

test "parseVerifierVerdict handles known strings" {
    try std.testing.expectEqual(VerifierVerdict.confirmed, FilterContext.parseVerifierVerdict("confirmed"));
    try std.testing.expectEqual(VerifierVerdict.likely_false_positive, FilterContext.parseVerifierVerdict("likely_fp"));
    try std.testing.expectEqual(VerifierVerdict.suppressed, FilterContext.parseVerifierVerdict("suppressed"));
}

test "parseVerifierVerdict returns unverified for unknown string" {
    try std.testing.expectEqual(VerifierVerdict.unverified, FilterContext.parseVerifierVerdict("unknown_verdict"));
}

test "severityMax returns the more severe of two" {
    try std.testing.expectEqual(Severity.critical, severityMax(.critical, .low));
    try std.testing.expectEqual(Severity.high, severityMax(.medium, .high));
    try std.testing.expectEqual(Severity.medium, severityMax(.medium, .medium));
    try std.testing.expectEqual(Severity.low, severityMax(.low, .low));
}

test "riskToSeverity maps correctly" {
    try std.testing.expectEqual(Severity.critical, riskToSeverity(.critical));
    try std.testing.expectEqual(Severity.high, riskToSeverity(.high));
    try std.testing.expectEqual(Severity.medium, riskToSeverity(.medium));
    try std.testing.expectEqual(Severity.low, riskToSeverity(.low));
    try std.testing.expectEqual(Severity.low, riskToSeverity(.suppressed));
}

test "full pipeline: core memory safety issue in unknown origin is never downgraded" {
    const loc = types.Location.init("unknown_alloc");
    const issue = Issue.init(.use_after_free, "UAF in unknown", loc, .critical, 0.9);
    var ctx = FilterContext.init(&issue);

    // Layer 3: unknown origin
    ctx.origin = .unknown;
    ctx.computeRisk();
    // unknown + critical -> risk = high
    try std.testing.expectEqual(RiskLevel.high, ctx.risk_level);

    // Layer 4: surface = unknown
    ctx.surface = .unknown;
    ctx.has_boundary_evidence = false;
    ctx.applySurfaceDowngrade();
    // never_downgraded: keeps critical
    try std.testing.expectEqual(Severity.critical, ctx.severity_after_surface);

    // Layer 5-6: noise filter
    ctx.applyNoiseFilter();
    try std.testing.expectEqual(Severity.critical, ctx.final_severity);

    // Final: should report
    try std.testing.expect(ctx.shouldReport());
    try std.testing.expectEqual(Severity.critical, ctx.getFinalSeverity());
}

test "full pipeline: advisory issue in stdlib gets suppressed by risk" {
    const loc = types.Location.init("std.mem");
    const issue = Issue.init(.unchecked_return, "unchecked", loc, .low, 0.4);
    var ctx = FilterContext.init(&issue);

    ctx.origin = .stdlib;
    ctx.computeRisk();
    // stdlib + low -> suppressed
    try std.testing.expectEqual(RiskLevel.suppressed, ctx.risk_level);

    ctx.applyNoiseFilter();
    try std.testing.expect(!ctx.shouldReport());
}

test "full pipeline: FFI issue in stdlib gets upgraded from suppressed" {
    const loc = types.Location.init("std.c_import");
    const issue = Issue.init(.ffi_type_mismatch, "type mismatch", loc, .high, 0.8);
    var ctx = FilterContext.init(&issue);

    ctx.origin = .stdlib;
    ctx.computeRisk();
    // stdlib + high -> low (not suppressed for this combo)
    ctx.risk_level = .suppressed; // force suppressed for test
    ctx.severity_after_surface = .high;

    ctx.applyNoiseFilter();
    // FFI issues bypass suppression: suppressed -> low
    try std.testing.expectEqual(RiskLevel.low, ctx.risk_level);
    try std.testing.expect(ctx.shouldReport());
}
