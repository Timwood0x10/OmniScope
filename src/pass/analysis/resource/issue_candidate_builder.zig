//! Issue Candidate Builder — Generates candidates instead of direct reports.
//!
//! Instead of passes directly calling `ctx.addIssue()`, they now generate
//! IssueCandidate objects. The Verifier (issue_verifier.zig) then decides
//! whether to promote, downgrade, or suppress each candidate.
//!
//! This two-stage approach (build → verify → report) is the core of
//! precision improvement: no more pattern-match → immediate report.

const std = @import("std");

// ============================================================================
// IssueKind — All known issue kinds
// ============================================================================

/// Classification of potential issues found during analysis.
/// These are candidates — not yet confirmed as real bugs.
pub const IssueKind = enum(u8) {
    /// Resource allocated but never freed/transferred/escaped.
    leak,
    /// Resource freed by wrong-family deallocator.
    cross_family_free,
    /// Resource used after being released (UAF / double-free).
    use_after_release,
    /// Resource freed twice (double free).
    double_release,
    /// Borrowed pointer incorrectly treated as owned or escaped unsafely.
    borrow_escape,
    /// Pointer passed to callback that may outlive resource lifetime.
    callback_escape,
    /// Pointer passed to spawned thread with lifetime risk.
    thread_escape,
    /// Function semantics unknown — needs user model for accurate analysis.
    needs_model,
    /// Informational diagnostic (not a bug).
    diagnostic,
};

pub fn issueKindName(kind: IssueKind) []const u8 {
    return switch (kind) {
        .leak => "leak",
        .cross_family_free => "cross_family_free",
        .use_after_release => "use_after_release",
        .double_release => "double_release",
        .borrow_escape => "borrow_escape",
        .callback_escape => "callback_escape",
        .thread_escape => "thread_escape",
        .needs_model => "needs_model",
        .diagnostic => "diagnostic",
    };
}

// ============================================================================
// IssueCandidate — One candidate issue
// ============================================================================

/// A potential issue that has been detected but not yet verified.
/// Carries all evidence needed for the verifier to make a decision.
pub const IssueCandidate = struct {
    /// What kind of issue this is.
    kind: IssueKind,
    /// Raw risk score [0.0, 1.0] before verification adjustment.
    raw_score: f32,
    /// Allocation pointer value (key into contract graph).
    alloc_ptr: u64,
    /// Function name where the issue was detected.
    func_name: []const u8,
    /// Instruction address of the triggering operation.
    inst_addr: u64,
    /// Callee function name if issue is at a call site.
    callee_name: ?[]const u8 = null,
    /// Allocation family (if known).
    alloc_family: ?[]const u8 = null,
    /// Release/deallocation family (if applicable).
    release_family: ?[]const u8 = null,
    /// Current ownership state of the resource.
    current_state: ?[]const u8 = null,
    /// Escape kind if resource has escape records.
    escape_kind: ?[]const u8 = null,
    /// Whether this is on an FFI danger path.
    is_on_ffi_path: bool = false,
    /// Distance from nearest FFI boundary.
    ffi_boundary_distance: u8 = 255,
    /// Evidence items explaining why this candidate was generated.
    evidence: std.ArrayList([]const u8),
    /// Human-readable reason summary.
    reason: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, kind: IssueKind, score: f32) IssueCandidate {
        return .{
            .kind = kind,
            .raw_score = score,
            .alloc_ptr = 0,
            .func_name = "",
            .inst_addr = 0,
            .evidence = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *IssueCandidate) void {
        self.evidence.deinit();
    }

    /// Add an evidence item to this candidate.
    pub fn addEvidence(self: *IssueCandidate, item: []const u8) !void {
        try self.evidence.append(item);
    }
};

// ============================================================================
// CandidateBuilder — Factory for creating candidates
// ============================================================================

/// Creates IssueCandidate objects from analysis findings.
/// Passes call into this builder rather than directly reporting issues.
pub const CandidateBuilder = struct {
    allocator: std.mem.Allocator,
    /// All generated candidates.
    candidates: std.ArrayList(IssueCandidate),

    pub fn init(allocator: std.mem.Allocator) CandidateBuilder {
        return .{
            .allocator = allocator,
            .candidates = std.ArrayList(IssueCandidate).init(allocator),
        };
    }

    pub fn deinit(self: *CandidateBuilder) void {
        for (self.candidates.items) |*c| {
            c.deinit();
        }
        self.candidates.deinit();
    }

    // ========================================================================
    // P8-3: Cross-family free candidate
    // ========================================================================

    /// Generate a cross_family_free candidate when alloc and release families mismatch.
    pub fn buildCrossFamilyFree(
        self: *CandidateBuilder,
        func_name: []const u8,
        callee_name: []const u8,
        alloc_ptr: u64,
        alloc_fam: []const u8,
        release_fam: []const u8,
        inst_addr: u64,
    ) !*IssueCandidate {
        var c = IssueCandidate.init(self.allocator, .cross_family_free, 0.85);
        c.func_name = func_name;
        c.callee_name = callee_name;
        c.alloc_ptr = alloc_ptr;
        c.alloc_family = alloc_fam;
        c.release_family = release_fam;
        c.inst_addr = inst_addr;
        try c.addEvidence("Family mismatch detected");
        try c.addEvidence(try std.fmt.allocPrint(
            self.allocator,
            "alloc_family={s} release_family={s}",
            .{ alloc_fam, release_fam },
        ));
        c.reason = try std.fmt.allocPrint(
            self.allocator,
            "{s} freed by {s}-family deallocator in {s}",
            .{ alloc_fam, release_fam, callee_name },
        );
        try self.candidates.append(c);
        return &self.candidates.items[self.candidates.items.len - 1];
    }

    // ========================================================================
    // P8-4: Use-after-release candidate
    // ========================================================================

    /// Generate a use_after_release candidate when a freed resource is used.
    pub fn buildUseAfterRelease(
        self: *CandidateBuilder,
        func_name: []const u8,
        alloc_ptr: u64,
        release_callee: []const u8,
        use_inst_addr: u64,
    ) !*IssueCandidate {
        var c = IssueCandidate.init(self.allocator, .use_after_release, 0.9);
        c.func_name = func_name;
        c.callee_name = release_callee;
        c.alloc_ptr = alloc_ptr;
        c.inst_addr = use_inst_addr;
        c.current_state = "released";
        try c.addEvidence("Resource accessed after release");
        try c.addEvidence(try std.fmt.allocPrint(
            self.allocator,
            "released by {s}",
            .{release_callee},
        ));
        c.reason = try std.fmt.allocPrint(
            self.allocator,
            "Use after release by {s} in {s}",
            .{ release_callee, func_name },
        );
        try self.candidates.append(c);
        return &self.candidates.items[self.candidates.items.len - 1];
    }

    // ========================================================================
    // P8-5: Conditional leak candidate
    // ========================================================================

    /// Generate a leak candidate for an unfreed allocation.
    pub fn buildLeak(
        self: *CandidateBuilder,
        func_name: []const u8,
        alloc_ptr: u64,
        alloc_inst_addr: u64,
        alloc_fam: ?[]const u8,
        confidence: f32,
        has_valid_escape: bool,
    ) !*IssueCandidate {
        var score = confidence;
        if (has_valid_escape) score -= 0.3;

        var c = IssueCandidate.init(self.allocator, .leak, score);
        c.func_name = func_name;
        c.alloc_ptr = alloc_ptr;
        c.inst_addr = alloc_inst_addr;
        c.alloc_family = alloc_fam;
        c.current_state = "owned";
        try c.addEvidence("Resource allocated but not freed");
        if (alloc_fam) |f| {
            try c.addEvidence(try std.fmt.allocPrint(
                self.allocator,
                "family={s}",
                .{f},
            ));
        }
        if (has_valid_escape) {
            try c.addEvidence("Has valid escape (may be intentional transfer)");
            c.escape_kind = "valid_escape";
        }
        c.reason = try std.fmt.allocPrint(
            self.allocator,
            "Potential memory leak in {s}{s}",
            .{
                func_name,
                if (has_valid_escape) " (has valid escape)" else "",
            },
        );
        try self.candidates.append(c);
        return &self.candidates.items[self.candidates.items.len - 1];
    }

    // ========================================================================
    // P8-6: Borrow/callback/thread escape candidate
    // ========================================================================

    /// Generate a borrow_escape or callback_escape candidate.
    pub fn buildEscapeCandidate(
        self: *CandidateBuilder,
        kind: IssueKind,
        func_name: []const u8,
        callee_name: []const u8,
        ptr_val: u64,
        inst_addr: u64,
        escape_kind_name: []const u8,
    ) !*IssueCandidate {
        const base_score: f32 = switch (kind) {
            .callback_escape => 0.7,
            .thread_escape => 0.72,
            .borrow_escape => 0.75,
            else => 0.6,
        };

        var c = IssueCandidate.init(self.allocator, kind, base_score);
        c.func_name = func_name;
        c.callee_name = callee_name;
        c.alloc_ptr = ptr_val;
        c.inst_addr = inst_addr;
        c.escape_kind = escape_kind_name;
        try c.addEvidence(try std.fmt.allocPrint(
            self.allocator,
            "Pointer escapes via {s}",
            .{escape_kind_name},
        ));
        c.reason = try std.fmt.allocPrint(
            self.allocator,
            "{s} escape via {s}() in {s}",
            .{
                issueKindName(kind), callee_name, func_name,
            },
        );
        try self.candidates.append(c);
        return &self.candidates.items[self.candidates.items.len - 1];
    }

    // ========================================================================
    // P8-7: Needs-model diagnostic candidate
    // ========================================================================

    /// Generate a diagnostic candidate for unknown/unmodeled functions.
    pub fn buildNeedsModel(
        self: *CandidateBuilder,
        func_name: []const u8,
        unknown_callee: []const u8,
        ptr_val: u64,
        inst_addr: u64,
    ) !*IssueCandidate {
        var c = IssueCandidate.init(self.allocator, .needs_model, 0.35);
        c.func_name = func_name;
        c.callee_name = unknown_callee;
        c.alloc_ptr = ptr_val;
        c.inst_addr = inst_addr;
        try c.addEvidence("Unknown function semantics");
        try c.addEvidence(try std.fmt.allocPrint(
            self.allocator,
            "Callee '{s}' not in registry",
            .{unknown_callee},
        ));
        c.reason = try std.fmt.allocPrint(
            self.allocator,
            "Unknown: '{s}' in {s} — consider adding to semantic model",
            .{
                unknown_callee, func_name,
            },
        );
        try self.candidates.append(c);
        return &self.candidates.items[self.candidates.items.len - 1];
    }

    // ========================================================================
    // Query API
    // ========================================================================

    /// Get total number of candidates built.
    pub fn count(self: *const CandidateBuilder) usize {
        return self.candidates.items.len;
    }

    /// Iterate over all candidates.
    pub fn iterate(self: *CandidateBuilder, context: anytype, comptime visitor_fn: fn (context: @TypeOf(context), cand: *IssueCandidate) bool) void {
        for (self.candidates.items) |*c| {
            if (!visitor_fn(context, c)) break;
        }
    }

    /// Take ownership of all candidates (for transfer to verifier).
    pub fn takeCandidates(self: *CandidateBuilder) std.ArrayList(IssueCandidate) {
        var result = std.ArrayList(IssueCandidate).init(self.allocator);
        for (self.candidates.items) |c| {
            result.append(c) catch {};
        }
        self.candidates.clearRetainingCapacity();
        return result;
    }
};
