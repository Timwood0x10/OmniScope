//! Rule Customization System for OmniScope
//!
//! Allows users to customize detection rules via JSON config files:
//! 1. Custom pattern lists (add/remove function name patterns)
//! 2. Severity overrides for specific issue kinds
//! 3. Suppression rules for specific functions/files
//! 4. Custom confidence thresholds
//!
//! Integration points:
//! - Load config from `config/custom_rules.json`
//! - Integrate with `PatternRegistry` for pattern matching
//! - Integrate with `FilterContext` for suppression decisions

const std = @import("std");
const types = @import("../common/types.zig");

/// Severity levels for issue classification.
pub const Severity = types.Severity;

/// Issue kinds that can be customized.
pub const IssueKind = types.IssueKind;

/// Pattern matching types for custom rules.
pub const MatchType = enum {
    /// Match function names that start with the pattern.
    prefix,
    /// Match function names that contain the pattern.
    contains,
    /// Match function names exactly.
    exact,
    /// Match using regex pattern (future extension).
    regex,
};

/// Actions to take when a custom rule matches.
pub const RuleAction = enum {
    /// Suppress the issue entirely.
    suppress,
    /// Escalate the issue severity.
    escalate,
    /// Downgrade the issue severity.
    downgrade,
    /// Ignore the issue (treat as noise).
    ignore,
};

/// Custom rule definition for function name patterns.
pub const CustomRule = struct {
    /// Human-readable name for the rule.
    name: []const u8,
    /// Pattern to match against function names.
    pattern: []const u8,
    /// How to match the pattern (prefix, contains, exact, regex).
    match_type: MatchType,
    /// Action to take when pattern matches.
    action: RuleAction,
    /// Override severity for matching issues (optional).
    severity_override: ?Severity = null,
    /// Confidence threshold override (optional).
    confidence_threshold: ?f64 = null,
};

/// Configuration for rule customization system.
pub const RuleConfig = struct {
    /// Custom pattern rules for function name matching.
    custom_patterns: []const CustomRule,
    /// Severity overrides for specific issue kinds.
    severity_overrides: std.StringHashMap(Severity),
    /// List of function names to suppress entirely.
    suppression_list: []const []const u8,
    /// List of function names to escalate.
    escalation_list: []const []const u8,
    /// Custom confidence thresholds for issue kinds.
    confidence_thresholds: std.StringHashMap(f64),

    /// Initialize an empty RuleConfig.
    pub fn init(allocator: std.mem.Allocator) RuleConfig {
        return .{
            .custom_patterns = &[_]CustomRule{},
            .severity_overrides = std.StringHashMap(Severity).init(allocator),
            .suppression_list = &[_][]const u8{},
            .escalation_list = &[_][]const u8{},
            .confidence_thresholds = std.StringHashMap(f64).init(allocator),
        };
    }

    /// Deinitialize the RuleConfig and free allocated memory.
    pub fn deinit(self: *RuleConfig) void {
        self.severity_overrides.deinit();
        self.confidence_thresholds.deinit();
    }

    /// Load configuration from a JSON file.
    pub fn loadFromJson(allocator: std.mem.Allocator, file_path: []const u8) !RuleConfig {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
        defer allocator.free(content);

        return try parseJsonConfig(allocator, content);
    }

    /// Parse JSON configuration string into RuleConfig.
    pub fn parseJsonConfig(allocator: std.mem.Allocator, json_content: []const u8) !RuleConfig {
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_content, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.InvalidConfig;

        var config = RuleConfig.init(allocator);
        errdefer config.deinit();

        // Parse custom_patterns array
        if (root.object.get("custom_patterns")) |patterns| {
            if (patterns == .array) {
                config.custom_patterns = try parseCustomPatterns(allocator, patterns.array);
            }
        }

        // Parse severity_overrides object
        if (root.object.get("severity_overrides")) |overrides| {
            if (overrides == .object) {
                var iter = overrides.object.iterator();
                while (iter.next()) |entry| {
                    if (parseSeverity(entry.value_ptr.*)) |sev| {
                        try config.severity_overrides.put(entry.key_ptr.*, sev);
                    }
                }
            }
        }

        // Parse suppression_list array
        if (root.object.get("suppression_list")) |list| {
            if (list == .array) {
                config.suppression_list = try parseStringList(allocator, list.array);
            }
        }

        // Parse escalation_list array
        if (root.object.get("escalation_list")) |list| {
            if (list == .array) {
                config.escalation_list = try parseStringList(allocator, list.array);
            }
        }

        // Parse confidence_thresholds object
        if (root.object.get("confidence_thresholds")) |thresholds| {
            if (thresholds == .object) {
                var iter = thresholds.object.iterator();
                while (iter.next()) |entry| {
                    if (entry.value_ptr.* == .float) {
                        try config.confidence_thresholds.put(entry.key_ptr.*, entry.value_ptr.*.float);
                    }
                }
            }
        }

        return config;
    }

    /// Check if a function name matches any suppression rule.
    pub fn shouldSuppress(self: *const RuleConfig, func_name: []const u8) bool {
        // Check suppression list
        for (self.suppression_list) |suppressed| {
            if (std.mem.eql(u8, func_name, suppressed)) return true;
        }

        // Check custom patterns for suppress action
        for (self.custom_patterns) |rule| {
            if (rule.action == .suppress and matchPattern(func_name, rule.pattern, rule.match_type)) {
                return true;
            }
        }

        return false;
    }

    /// Check if a function name matches any escalation rule.
    pub fn shouldEscalate(self: *const RuleConfig, func_name: []const u8) bool {
        // Check escalation list
        for (self.escalation_list) |escalated| {
            if (std.mem.eql(u8, func_name, escalated)) return true;
        }

        // Check custom patterns for escalate action
        for (self.custom_patterns) |rule| {
            if (rule.action == .escalate and matchPattern(func_name, rule.pattern, rule.match_type)) {
                return true;
            }
        }

        return false;
    }

    /// Get severity override for an issue kind.
    pub fn getSeverityOverride(self: *const RuleConfig, issue_kind: IssueKind) ?Severity {
        const kind_str = @tagName(issue_kind);
        return self.severity_overrides.get(kind_str);
    }

    /// Get confidence threshold override for an issue kind.
    pub fn getConfidenceThreshold(self: *const RuleConfig, issue_kind: IssueKind) ?f64 {
        const kind_str = @tagName(issue_kind);
        return self.confidence_thresholds.get(kind_str);
    }

    /// Apply custom rules to an issue and return modified severity.
    pub fn applyRules(self: *const RuleConfig, func_name: []const u8, issue_kind: IssueKind, original_severity: Severity) Severity {
        // Check for suppression
        if (self.shouldSuppress(func_name)) {
            return .low; // Suppressed issues get lowest severity
        }

        // Check for escalation
        if (self.shouldEscalate(func_name)) {
            return escalateSeverity(original_severity);
        }

        // Check for severity override
        if (self.getSeverityOverride(issue_kind)) |override| {
            return override;
        }

        // Check custom patterns for severity override
        for (self.custom_patterns) |rule| {
            if (matchPattern(func_name, rule.pattern, rule.match_type)) {
                if (rule.severity_override) |override| {
                    return override;
                }
            }
        }

        return original_severity;
    }
};

/// Helper function to match a function name against a pattern.
pub fn matchPattern(func_name: []const u8, pattern: []const u8, match_type: MatchType) bool {
    return switch (match_type) {
        .prefix => std.mem.startsWith(u8, func_name, pattern),
        .contains => std.mem.indexOf(u8, func_name, pattern) != null,
        .exact => std.mem.eql(u8, func_name, pattern),
        .regex => false, // Regex not implemented yet
    };
}

/// Helper function to escalate severity by one level.
fn escalateSeverity(severity: Severity) Severity {
    return switch (severity) {
        .low => .medium,
        .medium => .high,
        .high => .critical,
        .critical => .critical, // Already at max
    };
}

/// Parse JSON array of custom patterns.
fn parseCustomPatterns(allocator: std.mem.Allocator, patterns: std.json.Array) ![]const CustomRule {
    var result = std.ArrayList(CustomRule).init(allocator);
    errdefer result.deinit();

    for (patterns.items) |item| {
        if (item == .object) {
            const rule = try parseCustomRule(item.object);
            try result.append(rule);
        }
    }

    return try result.toOwnedSlice();
}

/// Parse a single custom rule from JSON object.
fn parseCustomRule(obj: std.json.ObjectMap) !CustomRule {
    const name = if (obj.get("name")) |n|
        if (n == .string) n.string else return error.InvalidConfig
    else
        return error.InvalidConfig;

    const pattern = if (obj.get("pattern")) |p|
        if (p == .string) p.string else return error.InvalidConfig
    else
        return error.InvalidConfig;

    const match_type = if (obj.get("match_type")) |m|
        if (m == .string) parseMatchType(m.string) else return error.InvalidConfig
    else
        .exact;

    const action = if (obj.get("action")) |a|
        if (a == .string) parseAction(a.string) else return error.InvalidConfig
    else
        .suppress;

    const severity_override = if (obj.get("severity_override")) |s|
        parseSeverity(s)
    else
        null;

    const confidence_threshold = if (obj.get("confidence_threshold")) |c|
        if (c == .float) c.float else null
    else
        null;

    return .{
        .name = name,
        .pattern = pattern,
        .match_type = match_type,
        .action = action,
        .severity_override = severity_override,
        .confidence_threshold = confidence_threshold,
    };
}

/// Parse match type string to enum.
fn parseMatchType(str: []const u8) MatchType {
    if (std.mem.eql(u8, str, "prefix")) return .prefix;
    if (std.mem.eql(u8, str, "contains")) return .contains;
    if (std.mem.eql(u8, str, "exact")) return .exact;
    if (std.mem.eql(u8, str, "regex")) return .regex;
    return .exact; // Default
}

/// Parse action string to enum.
fn parseAction(str: []const u8) RuleAction {
    if (std.mem.eql(u8, str, "suppress")) return .suppress;
    if (std.mem.eql(u8, str, "escalate")) return .escalate;
    if (std.mem.eql(u8, str, "downgrade")) return .downgrade;
    if (std.mem.eql(u8, str, "ignore")) return .ignore;
    return .suppress; // Default
}

/// Parse severity from JSON value.
fn parseSeverity(value: std.json.Value) ?Severity {
    if (value == .string) {
        const str = value.string;
        if (std.mem.eql(u8, str, "low")) return .low;
        if (std.mem.eql(u8, str, "medium")) return .medium;
        if (std.mem.eql(u8, str, "high")) return .high;
        if (std.mem.eql(u8, str, "critical")) return .critical;
    }
    return null;
}

/// Parse JSON array of strings.
fn parseStringList(allocator: std.mem.Allocator, array: std.json.Array) ![]const []const u8 {
    var result = std.ArrayList([]const u8).init(allocator);
    errdefer result.deinit();

    for (array.items) |item| {
        if (item == .string) {
            try result.append(item.string);
        }
    }

    return try result.toOwnedSlice();
}
