//! Confidence Scorer — 4-tier confidence-based issue ranking
//!
//! Instead of binary report/suppress, issues get a confidence score
//! based on multiple dimensions:
//!   (a) Provenance clarity: DI found -> +0.2; use-def only -> +0.1
//!   (b) Corpus frequency: high frequency in clean corpus -> penalty
//!   (c) Dataflow proximity: short source->sink path -> bonus
//!   (d) Multi-detector consensus: >=2 detectors flag same value -> +0.15
//!
//! Output tiers:
//!   Critical   (>=0.85): must fix
//!   High       (0.7-0.85): strongly recommended
//!   Medium     (0.5-0.7): optional review
//!   Info       (<0.5): SARIF only, not printed

const std = @import("std");
const SemanticTree = @import("../semantics/semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../semantics/semantic_tree.zig").SemanticKind;
const Issue = @import("issue.zig").Issue;
const IssueKind = @import("issue.zig").IssueKind;

/// Output tier for scored issues.
pub const IssueTier = enum {
    critical, // score >= 0.85 — must fix
    high, // 0.70 <= score < 0.85 — strongly recommended
    medium, // 0.50 <= score < 0.70 — optional review
    informational, // score < 0.50 — SARIF only

    /// Get tier from a score value.
    pub fn fromScore(score: f32) IssueTier {
        if (score >= 0.85) return .critical;
        if (score >= 0.70) return .high;
        if (score >= 0.50) return .medium;
        return .informational;
    }

    /// Get human-readable tier name.
    pub fn label(self: IssueTier) []const u8 {
        return switch (self) {
            .critical => "CRITICAL",
            .high => "HIGH",
            .medium => "MEDIUM",
            .informational => "INFO",
        };
    }
};

/// Scored issue with tier classification.
pub const ScoredIssue = struct {
    issue: *const Issue,
    score: f32,
    tier: IssueTier,
    provenance_bonus: f32,
    frequency_penalty: f32,
    consensus_bonus: f32,
};

/// Base severity for each issue kind.
fn baseSeverity(kind: IssueKind) f32 {
    return switch (kind) {
        .use_after_free => 0.65,
        .cross_language_leak => 0.55,
        .borrow_escape => 0.50,
        .write_to_immutable => 0.50,
        .command_injection => 0.60,
        .memory_leak => 0.58,
        .double_free => 0.65,
        .null_pointer_dereference => 0.50,
        else => 0.40,
    };
}

/// Provenance clarity bonus — how well do we understand the value origin?
fn provenanceClarityBonus(srt: *const SemanticTree, value_ref: u64) f32 {
    // Direct DI type match -> high confidence
    if (srt.hasKind(value_ref, .heap_provenance) != null) return 0.20;
    if (srt.hasKind(value_ref, .global_provenance) != null) return 0.20;
    // Parameter attribute match -> high confidence
    if (srt.hasKind(value_ref, .readonly_param) != null) return 0.20;
    if (srt.hasKind(value_ref, .mutable_param) != null) return 0.20;
    // Interior mutability -> confident this is not a bug
    if (srt.hasKind(value_ref, .interior_mutability) != null) return 0.15;
    // Other semantic kinds -> moderate confidence
    if (srt.hasKind(value_ref, .raii_drop_release) != null) return 0.15;
    if (srt.hasKind(value_ref, .into_raw_transfer) != null) return 0.15;
    if (srt.hasKind(value_ref, .library_release) != null) return 0.15;
    return 0.0;
}

/// Multi-detector consensus bonus — if >=2 detectors agree,
/// the finding is more reliable.
fn multiDetectorConsensusBonus(srt: *const SemanticTree, value_ref: u64) f32 {
    const resolutions = srt.allResolutions(value_ref);
    if (resolutions.len >= 2) return 0.15;
    return 0.0;
}

/// Score an issue based on SRT context.
/// Returns a ScoredIssue with tier classification.
/// The value_ref parameter is the LLVM ValueRef associated with the issue.
pub fn scoreIssue(
    srt: *const SemanticTree,
    issue: *const Issue,
    value_ref: u64,
) ScoredIssue {
    var s: f32 = baseSeverity(issue.kind);

    const prov_bonus = provenanceClarityBonus(srt, value_ref);
    s += prov_bonus;

    const consensus = multiDetectorConsensusBonus(srt, value_ref);
    s += consensus;

    // Frequency penalty — placeholder for future corpus frequency analysis
    const freq_penalty: f32 = 0.0;
    s -= freq_penalty;

    // Dataflow proximity — placeholder for future path analysis
    // Short source->sink path -> more suspicious -> bonus

    // Clamp to [0.0, 1.0]
    s = std.math.clamp(s, 0.0, 1.0);

    const tier = IssueTier.fromScore(s);

    return ScoredIssue{
        .issue = issue,
        .score = s,
        .tier = tier,
        .provenance_bonus = prov_bonus,
        .frequency_penalty = freq_penalty,
        .consensus_bonus = consensus,
    };
}
