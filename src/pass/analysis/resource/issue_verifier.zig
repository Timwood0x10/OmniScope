//! Issue Verifier — Two-stage confirmation for all reported issues.
//!
//! Every candidate from CandidateBuilder passes through here before becoming
//! a real Issue. The verifier applies multiple checks:
//!   1. Family verification (same/compatible/mismatch)
//!   2. Escape verification (valid disposal?)
//!   3. Destructor verification (RAII path exists?)
//!   4. Path verification (concrete UAF path?)
//!   5. FFI priority weighting
//!   6. Scoring and threshold classification
//!
//! Output is a VerifiedVerdict that determines SARIF output strategy.

const std = @import("std");

const candidate_mod = @import("issue_candidate_builder.zig");
pub const IssueCandidate = candidate_mod.IssueCandidate;
pub const IssueKind = candidate_mod.IssueKind;
pub const issueKindName = candidate_mod.issueKindName;

const contract = @import("../../../semantics/resource/contract.zig");
pub const ViolationSeverity = contract.ViolationSeverity;
const effect = @import("../../../semantics/resource/effect.zig");
pub const Confidence = effect.Confidence;

// ============================================================================
// VerifiedVerdict — Final decision on a candidate
// ============================================================================

/// The verdict after full verification of a candidate issue.
/// This determines whether and how the issue is reported.
pub const VerifiedVerdict = enum(u8) {
    /// High-confidence real bug — always output to SARIF.
    confirmed_issue,
    /// Likely a bug but some uncertainty — output to SARIF with note.
    probable_issue,
    /// Low confidence — only output with --debug flag.
    diagnostic,
    /// Explained as safe behavior — never output as issue.
    explained_safe,
    /// Could not determine — skip entirely.
    skipped,
};

/// Detailed verdict with score and explanation.
pub const VerificationResult = struct {
    /// Final verdict classification.
    verdict: VerifiedVerdict,
    /// Adjusted score after all verifications [0.0, 1.0].
    adjusted_score: f32,
    /// Severity level for reporting.
    severity: ViolationSeverity,
    /// Human-readable explanation of the decision.
    explanation: []const u8,
    /// Which verifier(s) influenced this decision (for traceability).
    influencing_verifiers: ?[]const VerifierId,

    pub fn shouldReport(self: *const VerificationResult) bool {
        return switch (self.verdict) {
            .confirmed_issue, .probable_issue => true,
            .diagnostic, .explained_safe, .skipped => false,
        };
    }

    pub fn shouldReportInDebugMode(self: *const VerificationResult) bool {
        return switch (self.verdict) {
            .confirmed_issue, .probable_issue, .diagnostic => true,
            .explained_safe, .skipped => false,
        };
    }
};

/// Identifiers for each verifier pass (for evidence trail).
pub const VerifierId = enum(u8) {
    family_verifier,
    escape_verifier,
    destructor_verifier,
    path_verifier,
    ffi_priority_verifier,
    scoring_verifier,
};

// ============================================================================
// Scoring Parameters (P8-17 ~ P8-20)
// ============================================================================

/// Centralized risk scoring parameters.
/// All thresholds and weights are defined here so they can be tuned
/// without touching individual verifier logic.
pub const ScoringParams = struct {
    // Thresholds (P8-20) — P15 relaxed to restore CRITICAL/HIGH detection
    pub const CONFIRMED_THRESHOLD: f32 = 0.75;
    pub const PROBABLE_THRESHOLD: f32 = 0.55;
    pub const DIAGNOSTIC_THRESHOLD: f32 = 0.35;

    // Bonus scores (P8-18)
    pub const BONUS_CONCRETE_PATH: f32 = 0.12;
    pub const BONUS_FAMILY_MISMATCH: f32 = 0.15; // Increased from 0.10
    pub const BONUS_OWNERSHIP_VIOLATION: f32 = 0.12; // Increased from 0.10
    pub const BONUS_FFI_BOUNDARY: f32 = 0.10; // Increased from 0.08
    pub const BONUS_CROSS_RUNTIME: f32 = 0.10; // Increased from 0.08
    pub const BONUS_USE_AFTER_RELEASE: f32 = 0.18; // Increased from 0.15
    pub const BONUS_DOUBLE_RELEASE: f32 = 0.18; // Increased from 0.15

    // Penalty scores (P8-19) — Reduced to avoid over-suppression
    pub const PENALTY_VALID_ESCAPE: f32 = 0.15; // Reduced from 0.25
    pub const PENALTY_VALID_DESTRUCTOR: f32 = 0.12; // Reduced from 0.20
    pub const PENALTY_SAME_FAMILY: f32 = 0.10; // Reduced from 0.15
    pub const PENALTY_RUNTIME_INTERNAL: f32 = 0.08; // Reduced from 0.10
    pub const PENALTY_UNKNOWN_EVIDENCE: f32 = 0.08; // Reduced from 0.12
    pub const PENALTY_LIFETIME_RISK_ESCAPE: f32 = 0.03; // Reduced from 0.05
};

// ============================================================================
// IssueVerifier — Main verification engine
// ============================================================================

/// Verifies issue candidates and produces final verdicts.
/// This is the single point where all reporting decisions are made.
pub const IssueVerifier = struct {
    allocator: std.mem.Allocator,
    /// All verification results.
    results: std.ArrayList(VerificationResult),
    /// Count of each verdict type.
    stats: Stats,

    const Stats = struct {
        confirmed: u32 = 0,
        probable: u32 = 0,
        diagnostic: u32 = 0,
        explained: u32 = 0,
        skipped: u32 = 0,
    };

    pub fn init(allocator: std.mem.Allocator) IssueVerifier {
        return .{
            .allocator = allocator,
            .results = .{ .items = &[_]VerificationResult{}, .capacity = 0 },
            .stats = .{},
        };
    }

    pub fn deinit(self: *IssueVerifier) void {
        self.results.deinit(self.allocator);
    }

    /// Verify a single candidate and produce a verdict.
    pub fn verify(self: *IssueVerifier, candidate: *const IssueCandidate) !VerificationResult {
        var score = candidate.raw_score;
        var severity: ViolationSeverity = .medium;
        var influencers = std.ArrayList(VerifierId){ .items = &[_]VerifierId{}, .capacity = 0 };
        defer influencers.deinit(self.allocator);

        // P8-10: Family verifier
        score = self.applyFamilyVerifier(candidate, score, &influencers);

        // P8-11: Escape verifier
        score = self.applyEscapeVerifier(candidate, score, &influencers);

        // P8-12: Destructor verifier
        score = self.applyDestructorVerifier(candidate, score, &influencers);

        // P8-14: FFI priority verifier
        score = self.applyFFIPriorityVerifier(candidate, score, &severity, &influencers);

        // Clamp score to [0.0, 1.0]
        if (score < 0.0) score = 0.0;
        if (score > 1.0) score = 1.0;

        // Determine verdict from score (P8-16)
        const verdict = scoreToVerdict(score);
        const explanation = self.buildExplanation(candidate, verdict, score);

        const result = VerificationResult{
            .verdict = verdict,
            .adjusted_score = score,
            .severity = severity,
            .explanation = explanation,
            .influencing_verifiers = &[_]VerifierId{},
        };

        // Update stats
        switch (verdict) {
            .confirmed_issue => self.stats.confirmed += 1,
            .probable_issue => self.stats.probable += 1,
            .diagnostic => self.stats.diagnostic += 1,
            .explained_safe => self.stats.explained += 1,
            .skipped => self.stats.skipped += 1,
        }

        try self.results.append(self.allocator, result);
        return result;
    }

    // ========================================================================
    // Individual verifiers
    // ========================================================================

    /// P8-10: Family verifier — same/compatible family explains as safe.
    fn applyFamilyVerifier(self: *IssueVerifier, cand: *const IssueCandidate, score: f32, influencers: *std.ArrayList(VerifierId)) f32 {

        // If both families present and same/compatible → explain safe
        if (cand.alloc_family != null and cand.release_family != null) {
            const af = cand.alloc_family.?;
            const rf = cand.release_family.?;
            if (std.mem.eql(u8, af, rf)) {
                influencers.append(self.allocator, .family_verifier) catch {};
                return @max(0.0, score - ScoringParams.PENALTY_SAME_FAMILY);
            }
            // Mismatch → bonus (this IS interesting)
            influencers.append(self.allocator, .family_verifier) catch {};
            return @min(1.0, score + ScoringParams.BONUS_FAMILY_MISMATCH);
        }

        // Unknown one side → penalty
        if (cand.alloc_family == null or cand.release_family == null) {
            influencers.append(self.allocator, .family_verifier) catch {};
            return @max(0.0, score - ScoringParams.PENALTY_UNKNOWN_EVIDENCE);
        }

        return score;
    }

    /// P8-11: Escape verifier — valid escapes downgrade or suppress.
    fn applyEscapeVerifier(self: *IssueVerifier, cand: *const IssueCandidate, score: f32, influencers: *std.ArrayList(VerifierId)) f32 {
        if (cand.escape_kind) |ek| {
            if (std.mem.indexOf(u8, ek, "valid") != null) {
                // Has valid escape → significant downgrade
                influencers.append(self.allocator, .escape_verifier) catch {};
                return @max(0.0, score - ScoringParams.PENALTY_VALID_ESCAPE);
            }
            if (std.mem.indexOf(u8, ek, "callback") != null or
                std.mem.indexOf(u8, ek, "thread") != null)
            {
                // Lifetime risk escape → small penalty
                influencers.append(self.allocator, .escape_verifier) catch {};
                return @max(0.0, score - ScoringParams.PENALTY_LIFETIME_RISK_ESCAPE);
            }
        }

        return score;
    }

    /// P8-12: Destructor verifier — RAII path exists?
    fn applyDestructorVerifier(self: *IssueVerifier, cand: *const IssueCandidate, score: f32, influencers: *std.ArrayList(VerifierId)) f32 {

        // Check evidence for destructor/drop/cleanup mentions
        for (cand.evidence.items) |ev| {
            if (std.mem.indexOf(u8, ev, "destructor") != null or
                std.mem.indexOf(u8, ev, "Drop") != null or
                std.mem.indexOf(u8, ev, "RAII") != null)
            {
                influencers.append(self.allocator, .destructor_verifier) catch {};
                return @max(0.0, score - ScoringParams.PENALTY_VALID_DESTRUCTOR);
            }
        }

        return score;
    }

    /// P8-14: FFI priority verifier — boundary issues get weight boost.
    fn applyFFIPriorityVerifier(self: *IssueVerifier, cand: *const IssueCandidate, score: f32, severity: *ViolationSeverity, influencers: *std.ArrayList(VerifierId)) f32 {
        if (cand.is_on_ffi_path) {
            influencers.append(self.allocator, .ffi_priority_verifier) catch {};
            const bonus = ScoringParams.BONUS_FFI_BOUNDARY *
                @as(f32, @floatFromInt(255 - cand.ffi_boundary_distance)) / 255.0;
            if (bonus > 0.03) {
                severity.* = .high;
            }
            return @min(1.0, score + bonus);
        }

        return score;
    }

    // ========================================================================
    // Helpers
    // ========================================================================

    fn scoreToVerdict(score: f32) VerifiedVerdict {
        if (score >= ScoringParams.CONFIRMED_THRESHOLD) return .confirmed_issue;
        if (score >= ScoringParams.PROBABLE_THRESHOLD) return .probable_issue;
        if (score >= ScoringParams.DIAGNOSTIC_THRESHOLD) return .diagnostic;
        return .explained_safe;
    }

    fn buildExplanation(_: *IssueVerifier, cand: *const IssueCandidate, _: VerifiedVerdict, _: f32) []const u8 {
        return cand.reason orelse switch (cand.kind) {
            .leak => "Memory leak detected",
            .cross_family_free => "Cross-family free detected",
            .use_after_release => "Use-after-release detected",
            .double_release => "Double release detected",
            .borrow_escape => "Borrow escape detected",
            .callback_escape => "Callback escape detected",
            .thread_escape => "Thread escape detected",
            .needs_model => "Function semantics unknown",
            .diagnostic => "Diagnostic information",
            .unchecked_return => "Unchecked return value from FFI function",
            .ffi_type_mismatch => "FFI type mismatch detected",
        };
    }

    /// Get statistics on verification results.
    pub fn getStats(self: *const IssueVerifier) Stats {
        return self.stats;
    }

    /// Total number of verified candidates.
    pub fn count(self: *const IssueVerifier) usize {
        return self.results.items.len;
    }
};
