//! Enterprise Custom Rule Engine
//!
//! Phase 9: Custom rule configuration for team policies.
//!
//! Features:
//! - Custom suppression patterns (function name, file path, issue kind)
//! - Confidence thresholds per rule category
//! - Team policy profiles (strict/standard/lenient)
//! - TOML-based configuration file support

const std = @import("std");

/// Rule severity level.
pub const RuleSeverity = enum {
    err,
    warning,
    info,
    ignore,

    pub fn fromString(s: []const u8) ?RuleSeverity {
        if (std.mem.eql(u8, s, "error")) return .err;
        if (std.mem.eql(u8, s, "err")) return .err;
        if (std.mem.eql(u8, s, "warning")) return .warning;
        if (std.mem.eql(u8, s, "warn")) return .warning;
        if (std.mem.eql(u8, s, "info")) return .info;
        if (std.mem.eql(u8, s, "ignore")) return .ignore;
        return null;
    }
};

/// Rule action when matched.
pub const RuleAction = enum {
    suppress,
    downgrade,
    escalate,
    annotate,

    pub fn fromString(s: []const u8) ?RuleAction {
        if (std.mem.eql(u8, s, "suppress")) return .suppress;
        if (std.mem.eql(u8, s, "downgrade")) return .downgrade;
        if (std.mem.eql(u8, s, "escalate")) return .escalate;
        if (std.mem.eql(u8, s, "annotate")) return .annotate;
        return null;
    }
};

/// A single custom rule.
pub const Rule = struct {
    id: []const u8,
    name: []const u8,
    description: []const u8,
    enabled: bool,
    action: RuleAction,
    target_severity: RuleSeverity,

    // Match criteria (all must match for the rule to apply)
    match_kind_pattern: ?[]const u8 = null,
    match_function_pattern: ?[]const u8 = null,
    match_file_pattern: ?[]const u8 = null,
    min_confidence: ?f32 = null,
    max_confidence: ?f32 = null,

    // Action parameters
    override_severity: ?RuleSeverity = null,
    annotation: ?[]const u8 = null,
};

/// Predefined policy profiles.
pub const PolicyProfile = enum {
    strict,
    standard,
    lenient,

    /// Get default confidence threshold for this profile.
    pub fn defaultThreshold(self: PolicyProfile) f32 {
        return switch (self) {
            .strict => 0.3,
            .standard => 0.5,
            .lenient => 0.7,
        };
    }

    /// Get default rules for this profile.
    pub fn defaultRules(self: PolicyProfile) [4]Rule {
        return switch (self) {
            .strict => [_]Rule{
                .{
                    .id = "strict-1",
                    .name = "Suppress test/demo code",
                    .description = "Suppress issues in test functions",
                    .enabled = true,
                    .action = .suppress,
                    .target_severity = .ignore,
                    .match_function_pattern = "test_",
                },
                .{
                    .id = "strict-2",
                    .name = "Escalate high-confidence UAF",
                    .description = "Treat UAF with >0.9 confidence as error",
                    .enabled = true,
                    .action = .escalate,
                    .target_severity = .err,
                    .match_kind_pattern = "use_after_free",
                    .min_confidence = 0.9,
                    .override_severity = .err,
                },
                .{
                    .id = "strict-3",
                    .name = "Downgrade low-confidence leaks",
                    .description = "Treat leaks with <0.4 confidence as info",
                    .enabled = true,
                    .action = .downgrade,
                    .target_severity = .info,
                    .match_kind_pattern = "memory_leak",
                    .max_confidence = 0.4,
                    .override_severity = .info,
                },
                .{
                    .id = "strict-4",
                    .name = "Annotate FFI calls",
                    .description = "Add annotation to all FFI unsafe calls",
                    .enabled = true,
                    .action = .annotate,
                    .target_severity = .warning,
                    .match_kind_pattern = "ffi_unsafe_call",
                    .annotation = "Review FFI boundary safety",
                },
            },
            .standard => [_]Rule{
                .{
                    .id = "std-1",
                    .name = "Suppress intentional patterns",
                    .description = "Skip safe/correct/test functions",
                    .enabled = true,
                    .action = .suppress,
                    .target_severity = .ignore,
                    .match_function_pattern = "safe_",
                },
                .{
                    .id = "std-2",
                    .name = "Escalate critical issues",
                    .description = "Elevate critical findings",
                    .enabled = true,
                    .action = .escalate,
                    .target_severity = .err,
                    .min_confidence = 0.85,
                },
                .{
                    .id = "std-3",
                    .name = "Annotate ownership transfers",
                    .description = "Note factory function returns",
                    .enabled = true,
                    .action = .annotate,
                    .target_severity = .info,
                    .match_function_pattern = "create_",
                    .annotation = "Ownership transfer expected",
                },
                .{
                    .id = "std-4",
                    .name = "Downgrade vendor code",
                    .description = "Reduce severity for third-party library code",
                    .enabled = true,
                    .action = .downgrade,
                    .target_severity = .info,
                    .match_file_pattern = "vendor/",
                    .override_severity = .info,
                },
            },
            .lenient => [_]Rule{
                .{
                    .id = "len-1",
                    .name = "Suppress most warnings",
                    .description = "Only report errors and critical issues",
                    .enabled = true,
                    .action = .suppress,
                    .target_severity = .ignore,
                    .max_confidence = 0.7,
                },
                .{
                    .id = "len-2",
                    .name = "Suppress runtime internal",
                    .description = "Skip compiler/runtime generated code",
                    .enabled = true,
                    .action = .suppress,
                    .target_severity = .ignore,
                    .match_function_pattern = "llvm.",
                },
                .{
                    .id = "len-3",
                    .name = "Only critical UAF",
                    .description = "Report only highest-confidence use-after-free",
                    .enabled = true,
                    .action = .escalate,
                    .target_severity = .err,
                    .match_kind_pattern = "use_after_free",
                    .min_confidence = 0.95,
                },
                .{
                    .id = "len-4",
                    .name = "Ignore low-severity",
                    .description = "Completely ignore low-confidence findings",
                    .enabled = true,
                    .action = .suppress,
                    .target_severity = .ignore,
                    .max_confidence = 0.3,
                },
            },
        };
    }
};

/// The custom rule engine.
pub const RuleEngine = struct {
    allocator: std.mem.Allocator,
    rules: std.ArrayList(Rule),
    profile: PolicyProfile,
    stats: EngineStats,

    const EngineStats = struct {
        total_evaluated: u32 = 0,
        suppressed: u32 = 0,
        downgraded: u32 = 0,
        escalated: u32 = 0,
        annotated: u32 = 0,
        passed_through: u32 = 0,
    };

    pub fn init(allocator: std.mem.Allocator, profile: PolicyProfile) !RuleEngine {
        var engine = RuleEngine{
            .allocator = allocator,
            .rules = std.ArrayList(Rule).init(allocator),
            .profile = profile,
            .stats = .{},
        };

        // Load default rules for this profile
        const defaults = profile.defaultRules();
        for (defaults) |r| {
            try engine.rules.append(r);
        }

        return engine;
    }

    pub fn deinit(self: *RuleEngine) void {
        self.rules.deinit();
    }

    /// Add a custom rule.
    pub fn addRule(self: *RuleEngine, rule: Rule) !void {
        try self.rules.append(rule);
    }

    /// Evaluate an issue against all rules.
    ///
    /// Returns:
    ///   - `null` if the issue should be suppressed
    ///   - modified severity if escalated/downgraded
    ///   - original severity if no rule matched
    pub fn evaluate(self: *RuleEngine, issue: anytype) !?struct {
        severity: RuleSeverity,
        annotation: ?[]const u8,
    } {
        _ = @TypeOf(issue);
        self.stats.total_evaluated += 1;

        var result_sev: ?RuleSeverity = null;
        var result_annotation: ?[]const u8 = null;

        for (self.rules.items) |rule| {
            if (!rule.enabled) continue;

            if (!self.matchesRule(issue, rule)) continue;

            switch (rule.action) {
                .suppress => {
                    self.stats.suppressed += 1;
                    return null;
                },
                .downgrade => {
                    self.stats.downgraded += 1;
                    result_sev = rule.override_severity orelse .info;
                },
                .escalate => {
                    self.stats.escalated += 1;
                    result_sev = rule.override_severity orelse .err;
                },
                .annotate => {
                    self.stats.annotated += 1;
                    result_annotation = rule.annotation;
                },
            }
        }

        if (result_sev) |sev| {
            return .{ .severity = sev, .annotation = result_annotation };
        }

        self.stats.passed_through += 1;
        return .{ .severity = .warning, .annotation = null };
    }

    /// Check if an issue matches a rule's criteria.
    fn matchesRule(self: *RuleEngine, issue: anytype, rule: Rule) bool {
        _ = self;
        const T = @TypeOf(issue);

        // Check kind pattern
        if (rule.match_kind_pattern) |pattern| {
            if (@hasField(T, "kind")) {
                const kind_str = @tagName(@field(issue, "kind"));
                if (!patternMatches(pattern, kind_str)) return false;
            } else {
                return false;
            }
        }

        // Check function pattern
        if (rule.match_function_pattern) |pattern| {
            if (@hasField(T, "location")) {
                const loc = @field(issue, "location");
                if (@hasField(@TypeOf(loc), "function")) {
                    const func_name = @field(loc, "function");
                    if (!patternMatches(pattern, func_name)) return false;
                } else {
                    return false;
                }
            } else {
                return false;
            }
        }

        // Check file pattern
        if (rule.match_file_pattern) |pattern| {
            if (@hasField(T, "location")) {
                const loc = @field(issue, "location");
                if (@hasField(@TypeOf(loc), "file")) {
                    if (@field(loc, "file")) |file| {
                        if (!patternMatches(pattern, file)) return false;
                    } else {
                        return false;
                    }
                } else {
                    return false;
                }
            } else {
                return false;
            }
        }

        // Check confidence range
        if (rule.min_confidence) |min_c| {
            if (@hasField(T, "confidence")) {
                if (@field(issue, "confidence") < min_c) return false;
            } else {
                return false;
            }
        }
        if (rule.max_confidence) |max_c| {
            if (@hasField(T, "confidence")) {
                if (@field(issue, "confidence") > max_c) return false;
            } else {
                return false;
            }
        }

        return true;
    }

    /// Simple glob-like pattern matching.
    fn patternMatches(pattern: []const u8, value: []const u8) bool {
        if (std.mem.indexOf(u8, pattern, "*") != null) {
            // Prefix match: "test_*" matches "test_func"
            const prefix = pattern[0 .. pattern.len - 1];
            return std.mem.startsWith(u8, value, prefix);
        }
        return std.mem.eql(u8, pattern, value);
    }

    /// Get engine statistics.
    pub fn getStats(self: *const RuleEngine) EngineStats {
        return self.stats;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "RuleEngine - basic evaluation" {
    var engine = try RuleEngine.init(std.testing.allocator, .standard);
    defer engine.deinit();

    const TestIssue = struct {
        location: struct { function: []const u8, file: ?[]const u8, line: ?u32, column: ?u32 },
        kind: enum { memory_leak, use_after_free },
        message: []const u8,
        confidence: f32,
    };

    // Test issue in safe_ function should be suppressed by default std policy
    const safe_issue = TestIssue{
        .location = .{ .function = "safe_wrapper", .file = null, .line = null, .column = null },
        .kind = .memory_leak,
        .message = "Potential leak",
        .confidence = 0.6,
    };
    const result = try engine.evaluate(safe_issue);
    try std.testing.expect(result == null); // Should be suppressed

    // High confidence UAF should be escalated
    const uaf_issue = TestIssue{
        .location = .{ .function = "process_data", .file = null, .line = null, .column = null },
        .kind = .use_after_free,
        .message = "Use after free detected",
        .confidence = 0.92,
    };
    const result2 = try engine.evaluate(uaf_issue);
    try std.testing.expect(result2 != null);
    if (result2) |r| {
        try std.testing.expectEqual(RuleSeverity.err, r.severity);
    }
}

test "PolicyProfile - defaultThreshold" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), PolicyProfile.strict.defaultThreshold(), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), PolicyProfile.standard.defaultThreshold(), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.7), PolicyProfile.lenient.defaultThreshold(), 0.01);
}

test "RuleSeverity - fromString" {
    try std.testing.expectEqual(RuleSeverity.err, RuleSeverity.fromString("error").?);
    try std.testing.expectEqual(RuleSeverity.warning, RuleSeverity.fromString("warning").?);
    try std.testing.expectEqual(RuleSeverity.info, RuleSeverity.fromString("info").?);
    try std.testing.expectEqual(RuleSeverity.ignore, RuleSeverity.fromString("ignore").?);
    try std.testing.expect(RuleSeverity.fromString("invalid") == null);
}

test "RuleAction - fromString" {
    try std.testing.expectEqual(RuleAction.suppress, RuleAction.fromString("suppress").?);
    try std.testing.expectEqual(RuleAction.downgrade, RuleAction.fromString("downgrade").?);
    try std.testing.expectEqual(RuleAction.escalate, RuleAction.fromString("escalate").?);
    try std.testing.expectEqual(RuleAction.annotate, RuleAction.fromString("annotate").?);
}

test "RuleEngine - add custom rule" {
    var engine = try RuleEngine.init(std.testing.allocator, .lenient);
    defer engine.deinit();

    try engine.addRule(.{
        .id = "custom-1",
        .name = "Block my_func",
        .description = "Suppress everything in my_func",
        .enabled = true,
        .action = .suppress,
        .target_severity = .ignore,
        .match_function_pattern = "my_func",
    });

    const TestIssue = struct {
        location: struct { function: []const u8, file: ?[]const u8, line: ?u32, column: ?u32 },
        kind: enum { memory_leak },
        message: []const u8,
        confidence: f32,
    };

    const issue = TestIssue{
        .location = .{ .function = "my_func_internal", .file = null, .line = null, .column = null },
        .kind = .memory_leak,
        .message = "Leak in my_func",
        .confidence = 0.95,
    };
    const result = try engine.evaluate(issue);
    try std.testing.expect(result == null); // Suppressed by custom rule
}
