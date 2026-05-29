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

// ============================================================================
// Tests
// ============================================================================

test "matchPattern - exact match" {
    try std.testing.expect(matchPattern("malloc", "malloc", .exact));
    try std.testing.expect(!matchPattern("malloc_sized", "malloc", .exact));
}

test "matchPattern - prefix match" {
    try std.testing.expect(matchPattern("malloc_sized", "malloc", .prefix));
    try std.testing.expect(!matchPattern("my_malloc", "malloc", .prefix));
}

test "matchPattern - contains match" {
    try std.testing.expect(matchPattern("my_malloc_helper", "malloc", .contains));
    try std.testing.expect(!matchPattern("free", "malloc", .contains));
}

test "escalateSeverity" {
    try std.testing.expectEqual(Severity.medium, escalateSeverity(.low));
    try std.testing.expectEqual(Severity.high, escalateSeverity(.medium));
    try std.testing.expectEqual(Severity.critical, escalateSeverity(.high));
    try std.testing.expectEqual(Severity.critical, escalateSeverity(.critical));
}

test "RuleConfig - shouldSuppress" {
    var config = RuleConfig.init(std.testing.allocator);
    defer config.deinit();

    config.suppression_list = &[_][]const u8{ "test_func", "debug_print" };
    config.custom_patterns = &[_]CustomRule{
        .{
            .name = "Suppress all test functions",
            .pattern = "test_",
            .match_type = .prefix,
            .action = .suppress,
        },
    };

    try std.testing.expect(config.shouldSuppress("test_func"));
    try std.testing.expect(config.shouldSuppress("test_helper"));
    try std.testing.expect(config.shouldSuppress("debug_print"));
    try std.testing.expect(!config.shouldSuppress("malloc"));
}

test "RuleConfig - shouldEscalate" {
    var config = RuleConfig.init(std.testing.allocator);
    defer config.deinit();

    config.escalation_list = &[_][]const u8{"critical_func"};
    config.custom_patterns = &[_]CustomRule{
        .{
            .name = "Escalate security functions",
            .pattern = "security_",
            .match_type = .prefix,
            .action = .escalate,
        },
    };

    try std.testing.expect(config.shouldEscalate("critical_func"));
    try std.testing.expect(config.shouldEscalate("security_check"));
    try std.testing.expect(!config.shouldEscalate("normal_func"));
}

test "RuleConfig - getSeverityOverride" {
    var config = RuleConfig.init(std.testing.allocator);
    defer config.deinit();

    try config.severity_overrides.put("use_after_free", .critical);
    try config.severity_overrides.put("memory_leak", .low);

    try std.testing.expectEqual(Severity.critical, config.getSeverityOverride(.use_after_free));
    try std.testing.expectEqual(Severity.low, config.getSeverityOverride(.memory_leak));
    try std.testing.expectEqual(null, config.getSeverityOverride(.buffer_overflow));
}

test "RuleConfig - applyRules" {
    var config = RuleConfig.init(std.testing.allocator);
    defer config.deinit();

    config.suppression_list = &[_][]const u8{"noise_func"};
    config.escalation_list = &[_][]const u8{"important_func"};
    try config.severity_overrides.put("use_after_free", .critical);

    // Test suppression
    try std.testing.expectEqual(Severity.low, config.applyRules("noise_func", .memory_leak, .medium));

    // Test escalation
    try std.testing.expectEqual(Severity.high, config.applyRules("important_func", .memory_leak, .medium));

    // Test severity override
    try std.testing.expectEqual(Severity.critical, config.applyRules("normal_func", .use_after_free, .medium));

    // Test no override
    try std.testing.expectEqual(Severity.medium, config.applyRules("normal_func", .memory_leak, .medium));
}

test "RuleConfig - parseJsonConfig" {
    const json =
        \\{
        \\  "custom_patterns": [
        \\    {
        \\      "name": "Suppress test functions",
        \\      "pattern": "test_",
        \\      "match_type": "prefix",
        \\      "action": "suppress"
        \\    },
        \\    {
        \\      "name": "Escalate security functions",
        \\      "pattern": "security_",
        \\      "match_type": "prefix",
        \\      "action": "escalate",
        \\      "severity_override": "critical"
        \\    }
        \\  ],
        \\  "severity_overrides": {
        \\    "use_after_free": "critical",
        \\    "memory_leak": "low"
        \\  },
        \\  "suppression_list": ["debug_print", "log_trace"],
        \\  "escalation_list": ["critical_func"],
        \\  "confidence_thresholds": {
        \\    "use_after_free": 0.9,
        \\    "memory_leak": 0.7
        \\  }
        \\}
    ;

    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    // Test custom patterns
    try std.testing.expect(config.custom_patterns.len == 2);
    try std.testing.expectEqualStrings("Suppress test functions", config.custom_patterns[0].name);
    try std.testing.expectEqualStrings("test_", config.custom_patterns[0].pattern);
    try std.testing.expectEqual(MatchType.prefix, config.custom_patterns[0].match_type);
    try std.testing.expectEqual(RuleAction.suppress, config.custom_patterns[0].action);

    // Test severity overrides
    try std.testing.expectEqual(Severity.critical, config.severity_overrides.get("use_after_free"));
    try std.testing.expectEqual(Severity.low, config.severity_overrides.get("memory_leak"));

    // Test suppression list
    try std.testing.expect(config.suppression_list.len == 2);
    try std.testing.expectEqualStrings("debug_print", config.suppression_list[0]);
    try std.testing.expectEqualStrings("log_trace", config.suppression_list[1]);

    // Test escalation list
    try std.testing.expect(config.escalation_list.len == 1);
    try std.testing.expectEqualStrings("critical_func", config.escalation_list[0]);

    // Test confidence thresholds
    try std.testing.expectEqual(@as(f64, 0.9), config.confidence_thresholds.get("use_after_free").?);
    try std.testing.expectEqual(@as(f64, 0.7), config.confidence_thresholds.get("memory_leak").?);
}

test "RuleConfig - applyRules with custom patterns" {
    const json =
        \\{
        \\  "custom_patterns": [
        \\    {
        \\      "name": "Suppress test functions",
        \\      "pattern": "test_",
        \\      "match_type": "prefix",
        \\      "action": "suppress"
        \\    },
        \\    {
        \\      "name": "Escalate security functions",
        \\      "pattern": "security_",
        \\      "match_type": "prefix",
        \\      "action": "escalate",
        \\      "severity_override": "critical"
        \\    }
        \\  ]
        \\}
    ;

    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    // Test suppression via custom pattern
    try std.testing.expectEqual(Severity.low, config.applyRules("test_helper", .memory_leak, .medium));

    // Test escalation via custom pattern
    try std.testing.expectEqual(Severity.critical, config.applyRules("security_check", .memory_leak, .medium));

    // Test no match
    try std.testing.expectEqual(Severity.medium, config.applyRules("normal_func", .memory_leak, .medium));
}

// ============================================================================
// Boundary/Edge Case Tests
// ============================================================================

test "RuleConfig - parseJsonConfig with empty object" {
    // Empty JSON object should create valid empty config
    const json = "{}";
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    // Verify all fields are empty
    try std.testing.expectEqual(@as(usize, 0), config.custom_patterns.len);
    try std.testing.expectEqual(@as(usize, 0), config.severity_overrides.count());
    try std.testing.expectEqual(@as(usize, 0), config.suppression_list.len);
    try std.testing.expectEqual(@as(usize, 0), config.escalation_list.len);
    try std.testing.expectEqual(@as(usize, 0), config.confidence_thresholds.count());
}

test "RuleConfig - parseJsonConfig with empty arrays" {
    // JSON with empty arrays should parse correctly
    const json =
        \\{
        \\  "custom_patterns": [],
        \\  "suppression_list": [],
        \\  "escalation_list": []
        \\}
    ;

    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 0), config.custom_patterns.len);
    try std.testing.expectEqual(@as(usize, 0), config.suppression_list.len);
    try std.testing.expectEqual(@as(usize, 0), config.escalation_list.len);
}

test "RuleConfig - parseJsonConfig with empty objects" {
    // JSON with empty objects for maps should parse correctly
    const json =
        \\{
        \\  "severity_overrides": {},
        \\  "confidence_thresholds": {}
        \\}
    ;

    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 0), config.severity_overrides.count());
    try std.testing.expectEqual(@as(usize, 0), config.confidence_thresholds.count());
}

test "RuleConfig - parseJsonConfig with invalid JSON" {
    // Malformed JSON should return error
    const invalid_json = "{invalid json content";
    const result = RuleConfig.parseJsonConfig(std.testing.allocator, invalid_json);
    try std.testing.expectError(error.SyntaxError, result);
}

test "RuleConfig - parseJsonConfig with non-object root" {
    // JSON array at root level should return InvalidConfig
    const json_array = "[1, 2, 3]";
    const result = RuleConfig.parseJsonConfig(std.testing.allocator, json_array);
    try std.testing.expectError(error.InvalidConfig, result);

    // JSON string at root level should return InvalidConfig
    const json_string = "\"hello\"";
    const result2 = RuleConfig.parseJsonConfig(std.testing.allocator, json_string);
    try std.testing.expectError(error.InvalidConfig, result2);
}

test "RuleConfig - parseJsonConfig with missing required fields in custom pattern" {
    // Custom pattern missing "name" field should return InvalidConfig
    const json_missing_name =
        \\{
        \\  "custom_patterns": [
        \\    {
        \\      "pattern": "test_",
        \\      "match_type": "prefix",
        \\      "action": "suppress"
        \\    }
        \\  ]
        \\}
    ;
    const result = RuleConfig.parseJsonConfig(std.testing.allocator, json_missing_name);
    try std.testing.expectError(error.InvalidConfig, result);

    // Custom pattern missing "pattern" field should return InvalidConfig
    const json_missing_pattern =
        \\{
        \\  "custom_patterns": [
        \\    {
        \\      "name": "Test Rule",
        \\      "match_type": "prefix",
        \\      "action": "suppress"
        \\    }
        \\  ]
        \\}
    ;
    const result2 = RuleConfig.parseJsonConfig(std.testing.allocator, json_missing_pattern);
    try std.testing.expectError(error.InvalidConfig, result2);
}

test "RuleConfig - parseJsonConfig with wrong types in custom pattern" {
    // Custom pattern with wrong type for "name" field should return InvalidConfig
    const json_wrong_name_type =
        \\{
        \\  "custom_patterns": [
        \\    {
        \\      "name": 123,
        \\      "pattern": "test_",
        \\      "match_type": "prefix",
        \\      "action": "suppress"
        \\    }
        \\  ]
        \\}
    ;
    const result = RuleConfig.parseJsonConfig(std.testing.allocator, json_wrong_name_type);
    try std.testing.expectError(error.InvalidConfig, result);

    // Custom pattern with wrong type for "pattern" field should return InvalidConfig
    const json_wrong_pattern_type =
        \\{
        \\  "custom_patterns": [
        \\    {
        \\      "name": "Test Rule",
        \\      "pattern": 123,
        \\      "match_type": "prefix",
        \\      "action": "suppress"
        \\    }
        \\  ]
        \\}
    ;
    const result2 = RuleConfig.parseJsonConfig(std.testing.allocator, json_wrong_pattern_type);
    try std.testing.expectError(error.InvalidConfig, result2);
}

test "RuleConfig - parseJsonConfig with wrong types for arrays" {
    // suppression_list as string instead of array should be ignored (no error)
    const json_wrong_list_type =
        \\{
        \\  "suppression_list": "not_an_array"
        \\}
    ;
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json_wrong_list_type);
    defer config.deinit();
    try std.testing.expectEqual(@as(usize, 0), config.suppression_list.len);

    // escalation_list as number instead of array should be ignored (no error)
    const json_wrong_escalation_type =
        \\{
        \\  "escalation_list": 42
        \\}
    ;
    var config2 = try RuleConfig.parseJsonConfig(std.testing.allocator, json_wrong_escalation_type);
    defer config2.deinit();
    try std.testing.expectEqual(@as(usize, 0), config2.escalation_list.len);
}

test "RuleConfig - parseJsonConfig with wrong types for maps" {
    // severity_overrides as array instead of object should be ignored (no error)
    const json_wrong_overrides_type =
        \\{
        \\  "severity_overrides": ["not_an_object"]
        \\}
    ;
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json_wrong_overrides_type);
    defer config.deinit();
    try std.testing.expectEqual(@as(usize, 0), config.severity_overrides.count());

    // confidence_thresholds as array instead of object should be ignored (no error)
    const json_wrong_thresholds_type =
        \\{
        \\  "confidence_thresholds": [1, 2, 3]
        \\}
    ;
    var config2 = try RuleConfig.parseJsonConfig(std.testing.allocator, json_wrong_thresholds_type);
    defer config2.deinit();
    try std.testing.expectEqual(@as(usize, 0), config2.confidence_thresholds.count());
}

test "matchPattern - empty function name" {
    // Empty function name with empty pattern should match for exact
    try std.testing.expect(matchPattern("", "", .exact));
    // Empty function name with non-empty pattern should not match
    try std.testing.expect(!matchPattern("", "test", .exact));
    try std.testing.expect(!matchPattern("", "test", .prefix));
    try std.testing.expect(!matchPattern("", "test", .contains));
}

test "matchPattern - empty pattern" {
    // Non-empty function name with empty pattern
    // Empty pattern should match as prefix (everything starts with empty string)
    try std.testing.expect(matchPattern("malloc", "", .prefix));
    // Empty pattern should match as contains (everything contains empty string)
    try std.testing.expect(matchPattern("malloc", "", .contains));
    // Empty pattern should not match as exact (unless function name is also empty)
    try std.testing.expect(!matchPattern("malloc", "", .exact));
}

test "matchPattern - both empty" {
    // Both empty should match for all match types
    try std.testing.expect(matchPattern("", "", .exact));
    try std.testing.expect(matchPattern("", "", .prefix));
    try std.testing.expect(matchPattern("", "", .contains));
}

test "matchPattern - regex not implemented" {
    // Regex match type should always return false
    try std.testing.expect(!matchPattern("malloc", "m.*c", .regex));
    try std.testing.expect(!matchPattern("", ".*", .regex));
}

test "escalateSeverity - all levels" {
    // Test escalation from each level
    try std.testing.expectEqual(Severity.medium, escalateSeverity(.low));
    try std.testing.expectEqual(Severity.high, escalateSeverity(.medium));
    try std.testing.expectEqual(Severity.critical, escalateSeverity(.high));
    try std.testing.expectEqual(Severity.critical, escalateSeverity(.critical));
}

test "escalateSeverity - idempotent at critical" {
    // Escalating from critical should remain critical
    var severity = Severity.critical;
    for (0..10) |_| {
        severity = escalateSeverity(severity);
    }
    try std.testing.expectEqual(Severity.critical, severity);
}

test "RuleConfig - shouldSuppress with empty config" {
    var config = RuleConfig.init(std.testing.allocator);
    defer config.deinit();

    // Empty config should not suppress anything
    try std.testing.expect(!config.shouldSuppress("malloc"));
    try std.testing.expect(!config.shouldSuppress(""));
}

test "RuleConfig - shouldEscalate with empty config" {
    var config = RuleConfig.init(std.testing.allocator);
    defer config.deinit();

    // Empty config should not escalate anything
    try std.testing.expect(!config.shouldEscalate("malloc"));
    try std.testing.expect(!config.shouldEscalate(""));
}

test "RuleConfig - applyRules with empty config" {
    var config = RuleConfig.init(std.testing.allocator);
    defer config.deinit();

    // Empty config should return original severity
    try std.testing.expectEqual(Severity.low, config.applyRules("malloc", .memory_leak, .low));
    try std.testing.expectEqual(Severity.medium, config.applyRules("malloc", .memory_leak, .medium));
    try std.testing.expectEqual(Severity.high, config.applyRules("malloc", .memory_leak, .high));
    try std.testing.expectEqual(Severity.critical, config.applyRules("malloc", .memory_leak, .critical));
}

test "RuleConfig - getSeverityOverride for unknown issue kind" {
    var config = RuleConfig.init(std.testing.allocator);
    defer config.deinit();

    // Should return null for unknown issue kinds
    try std.testing.expectEqual(null, config.getSeverityOverride(.unknown));
    try std.testing.expectEqual(null, config.getSeverityOverride(.buffer_overflow));
}

test "RuleConfig - getConfidenceThreshold with empty config" {
    var config = RuleConfig.init(std.testing.allocator);
    defer config.deinit();

    // Empty config should return null for all issue kinds
    try std.testing.expectEqual(null, config.getConfidenceThreshold(.memory_leak));
    try std.testing.expectEqual(null, config.getConfidenceThreshold(.use_after_free));
}

test "RuleConfig - parseJsonConfig with unknown fields" {
    // JSON with unknown fields should parse successfully (unknown fields are ignored)
    const json =
        \\{
        \\  "unknown_field": "value",
        \\  "another_unknown": 42,
        \\  "custom_patterns": []
        \\}
    ;
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 0), config.custom_patterns.len);
}

test "RuleConfig - parseJsonConfig with unknown match type" {
    // Unknown match type should default to exact
    const json =
        \\{
        \\  "custom_patterns": [
        \\    {
        \\      "name": "Test Rule",
        \\      "pattern": "test_",
        \\      "match_type": "unknown_type",
        \\      "action": "suppress"
        \\    }
        \\  ]
        \\}
    ;
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 1), config.custom_patterns.len);
    try std.testing.expectEqual(MatchType.exact, config.custom_patterns[0].match_type);
}

test "RuleConfig - parseJsonConfig with unknown action" {
    // Unknown action should default to suppress
    const json =
        \\{
        \\  "custom_patterns": [
        \\    {
        \\      "name": "Test Rule",
        \\      "pattern": "test_",
        \\      "match_type": "prefix",
        \\      "action": "unknown_action"
        \\    }
        \\  ]
        \\}
    ;
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 1), config.custom_patterns.len);
    try std.testing.expectEqual(RuleAction.suppress, config.custom_patterns[0].action);
}

test "RuleConfig - parseJsonConfig with unknown severity" {
    // Unknown severity value should be ignored (null)
    const json =
        \\{
        \\  "severity_overrides": {
        \\    "memory_leak": "unknown_severity",
        \\    "use_after_free": "critical"
        \\  }
        \\}
    ;
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    // Unknown severity should not be added to map
    try std.testing.expectEqual(null, config.severity_overrides.get("memory_leak"));
    // Known severity should be added
    try std.testing.expectEqual(Severity.critical, config.severity_overrides.get("use_after_free"));
}

test "RuleConfig - parseJsonConfig with non-string severity values" {
    // Severity values that are not strings should be ignored
    const json =
        \\{
        \\  "severity_overrides": {
        \\    "memory_leak": 123,
        \\    "use_after_free": true,
        \\    "buffer_overflow": null
        \\  }
        \\}
    ;
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    // All should be ignored
    try std.testing.expectEqual(@as(usize, 0), config.severity_overrides.count());
}

test "RuleConfig - parseJsonConfig with non-float confidence thresholds" {
    // Confidence thresholds that are not floats should be ignored
    const json =
        \\{
        \\  "confidence_thresholds": {
        \\    "memory_leak": "not_a_float",
        \\    "use_after_free": 42,
        \\    "buffer_overflow": true
        \\  }
        \\}
    ;
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    // All should be ignored (only float values are accepted)
    try std.testing.expectEqual(@as(usize, 0), config.confidence_thresholds.count());
}

test "RuleConfig - parseJsonConfig with mixed valid and invalid items in arrays" {
    // Arrays with mixed valid and invalid items should parse valid ones
    const json =
        \\{
        \\  "suppression_list": ["valid_func", 123, true, "another_valid"],
        \\  "escalation_list": [456, "escalated_func", null, "another_escalated"]
        \\}
    ;
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    // Only string items should be parsed
    try std.testing.expectEqual(@as(usize, 2), config.suppression_list.len);
    try std.testing.expectEqualStrings("valid_func", config.suppression_list[0]);
    try std.testing.expectEqualStrings("another_valid", config.suppression_list[1]);

    try std.testing.expectEqual(@as(usize, 2), config.escalation_list.len);
    try std.testing.expectEqualStrings("escalated_func", config.escalation_list[0]);
    try std.testing.expectEqualStrings("another_escalated", config.escalation_list[1]);
}

test "RuleConfig - parseJsonConfig with mixed valid and invalid custom patterns" {
    // Custom patterns array with mixed valid and invalid objects
    const json =
        \\{
        \\  "custom_patterns": [
        \\    "not_an_object",
        \\    123,
        \\    {
        \\      "name": "Valid Rule",
        \\      "pattern": "test_",
        \\      "match_type": "prefix",
        \\      "action": "suppress"
        \\    },
        \\    true
        \\  ]
        \\}
    ;
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    // Only valid object should be parsed
    try std.testing.expectEqual(@as(usize, 1), config.custom_patterns.len);
    try std.testing.expectEqualStrings("Valid Rule", config.custom_patterns[0].name);
}

test "RuleConfig - parseJsonConfig with optional fields missing" {
    // Custom pattern with only required fields should use defaults
    const json =
        \\{
        \\  "custom_patterns": [
        \\    {
        \\      "name": "Minimal Rule",
        \\      "pattern": "test_"
        \\    }
        \\  ]
        \\}
    ;
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 1), config.custom_patterns.len);
    // Default match_type should be exact
    try std.testing.expectEqual(MatchType.exact, config.custom_patterns[0].match_type);
    // Default action should be suppress
    try std.testing.expectEqual(RuleAction.suppress, config.custom_patterns[0].action);
    // severity_override should be null
    try std.testing.expectEqual(null, config.custom_patterns[0].severity_override);
    // confidence_threshold should be null
    try std.testing.expectEqual(null, config.custom_patterns[0].confidence_threshold);
}

test "RuleConfig - parseJsonConfig with null values for optional fields" {
    // Custom pattern with null values for optional fields should be handled
    const json =
        \\{
        \\  "custom_patterns": [
        \\    {
        \\      "name": "Rule with nulls",
        \\      "pattern": "test_",
        \\      "match_type": null,
        \\      "action": null,
        \\      "severity_override": null,
        \\      "confidence_threshold": null
        \\    }
        \\  ]
        \\}
    ;
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 1), config.custom_patterns.len);
    // null match_type should default to exact
    try std.testing.expectEqual(MatchType.exact, config.custom_patterns[0].match_type);
    // null action should default to suppress
    try std.testing.expectEqual(RuleAction.suppress, config.custom_patterns[0].action);
    // null severity_override should be null
    try std.testing.expectEqual(null, config.custom_patterns[0].severity_override);
    // null confidence_threshold should be null
    try std.testing.expectEqual(null, config.custom_patterns[0].confidence_threshold);
}

test "RuleConfig - parseJsonConfig with wrong types for optional fields" {
    // Custom pattern with wrong types for optional fields should use defaults
    const json =
        \\{
        \\  "custom_patterns": [
        \\    {
        \\      "name": "Rule with wrong types",
        \\      "pattern": "test_",
        \\      "match_type": 123,
        \\      "action": 456,
        \\      "severity_override": 789,
        \\      "confidence_threshold": "not_a_float"
        \\    }
        \\  ]
        \\}
    ;
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 1), config.custom_patterns.len);
    // Wrong type for match_type should default to exact
    try std.testing.expectEqual(MatchType.exact, config.custom_patterns[0].match_type);
    // Wrong type for action should default to suppress
    try std.testing.expectEqual(RuleAction.suppress, config.custom_patterns[0].action);
    // Wrong type for severity_override should be null
    try std.testing.expectEqual(null, config.custom_patterns[0].severity_override);
    // Wrong type for confidence_threshold should be null
    try std.testing.expectEqual(null, config.custom_patterns[0].confidence_threshold);
}

test "RuleConfig - large suppression list" {
    // Test with a large suppression list to ensure no performance issues
    var config = RuleConfig.init(std.testing.allocator);
    defer config.deinit();

    // Create a large suppression list
    var suppression_list = std.ArrayList([]const u8).init(std.testing.allocator);
    defer suppression_list.deinit();

    for (0..1000) |i| {
        const name = try std.fmt.allocPrint(std.testing.allocator, "func_{d}", .{i});
        defer std.testing.allocator.free(name);
        try suppression_list.append(try std.testing.allocator.dupe(u8, name));
    }

    config.suppression_list = try suppression_list.toOwnedSlice();

    // Test that suppression still works correctly
    try std.testing.expect(config.shouldSuppress("func_0"));
    try std.testing.expect(config.shouldSuppress("func_500"));
    try std.testing.expect(config.shouldSuppress("func_999"));
    try std.testing.expect(!config.shouldSuppress("func_1000"));
    try std.testing.expect(!config.shouldSuppress("not_in_list"));

    // Free the suppression list
    for (config.suppression_list) |name| {
        std.testing.allocator.free(name);
    }
    std.testing.allocator.free(config.suppression_list);
}

test "RuleConfig - large escalation list" {
    // Test with a large escalation list to ensure no performance issues
    var config = RuleConfig.init(std.testing.allocator);
    defer config.deinit();

    // Create a large escalation list
    var escalation_list = std.ArrayList([]const u8).init(std.testing.allocator);
    defer escalation_list.deinit();

    for (0..1000) |i| {
        const name = try std.fmt.allocPrint(std.testing.allocator, "escalated_{d}", .{i});
        defer std.testing.allocator.free(name);
        try escalation_list.append(try std.testing.allocator.dupe(u8, name));
    }

    config.escalation_list = try escalation_list.toOwnedSlice();

    // Test that escalation still works correctly
    try std.testing.expect(config.shouldEscalate("escalated_0"));
    try std.testing.expect(config.shouldEscalate("escalated_500"));
    try std.testing.expect(config.shouldEscalate("escalated_999"));
    try std.testing.expect(!config.shouldEscalate("escalated_1000"));
    try std.testing.expect(!config.shouldEscalate("not_in_list"));

    // Free the escalation list
    for (config.escalation_list) |name| {
        std.testing.allocator.free(name);
    }
    std.testing.allocator.free(config.escalation_list);
}

test "RuleConfig - parseJsonConfig with special characters in strings" {
    // JSON with special characters in strings should parse correctly
    const json =
        \\{
        \\  "suppression_list": ["func with spaces", "func\twith\ttabs", "func\nwith\nnewlines"],
        \\  "custom_patterns": [
        \\    {
        \\      "name": "Rule with special chars: @#$%^&*()",
        \\      "pattern": "test_",
        \\      "match_type": "prefix",
        \\      "action": "suppress"
        \\    }
        \\  ]
        \\}
    ;
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 3), config.suppression_list.len);
    try std.testing.expectEqualStrings("func with spaces", config.suppression_list[0]);
    try std.testing.expectEqualStrings("func\twith\ttabs", config.suppression_list[1]);
    try std.testing.expectEqualStrings("func\nwith\nnewlines", config.suppression_list[2]);

    try std.testing.expectEqual(@as(usize, 1), config.custom_patterns.len);
    try std.testing.expectEqualStrings("Rule with special chars: @#$%^&*()", config.custom_patterns[0].name);
}

test "RuleConfig - parseJsonConfig with unicode characters" {
    // JSON with unicode characters should parse correctly
    const json =
        \\{
        \\  "suppression_list": ["函数名", "関数名", "función"],
        \\  "custom_patterns": [
        \\    {
        \\      "name": "Unicode rule: 测试规则",
        \\      "pattern": "test_",
        \\      "match_type": "prefix",
        \\      "action": "suppress"
        \\    }
        \\  ]
        \\}
    ;
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 3), config.suppression_list.len);
    try std.testing.expectEqualStrings("函数名", config.suppression_list[0]);
    try std.testing.expectEqualStrings("関数名", config.suppression_list[1]);
    try std.testing.expectEqualStrings("función", config.suppression_list[2]);

    try std.testing.expectEqual(@as(usize, 1), config.custom_patterns.len);
    try std.testing.expectEqualStrings("Unicode rule: 测试规则", config.custom_patterns[0].name);
}

test "RuleConfig - parseJsonConfig with very long strings" {
    // JSON with very long strings should parse correctly
    const long_pattern = "a" ** 1000; // 1000 character string
    const json =
        \\{
        \\  "custom_patterns": [
        \\    {
        \\      "name": "Rule with long pattern",
        \\      "pattern": "a" ** 1000,
        \\      "match_type": "prefix",
        \\      "action": "suppress"
        \\    }
        \\  ]
        \\}
    ;
    var config = try RuleConfig.parseJsonConfig(std.testing.allocator, json);
    defer config.deinit();

    try std.testing.expectEqual(@as(usize, 1), config.custom_patterns.len);
    try std.testing.expectEqualStrings(long_pattern, config.custom_patterns[0].pattern);
}
