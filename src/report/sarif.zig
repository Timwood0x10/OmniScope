//! SARIF (Static Analysis Results Interchange Format) Output Module
//!
//! This module implements SARIF v2.1.0 output for OmniScope analysis results.
//! SARIF is an OASIS standard format for static analysis results, enabling
//! integration with GitHub Code Scanning, Azure DevOps, and other tools.
//!
//! Reference: https://docs.oasis-open.org/sarif/sarif/v2.1.0/

const std = @import("std");
const Issue = @import("../diag/issue.zig").Issue;
const IssueKind = @import("../diag/issue.zig").IssueKind;
const Severity = @import("../diag/issue.zig").Severity;
const Location = @import("../diag/issue.zig").Location;
const FFIBoundary = @import("../diag/issue.zig").FFIBoundary;

/// SARIF version constant
pub const SARIF_VERSION = "2.1.0";

/// SARIF schema URL
pub const SARIF_SCHEMA = "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json";

/// Tool information for SARIF output
pub const ToolInfo = struct {
    name: []const u8,
    version: []const u8,
    information_uri: []const u8,
};

/// Default tool info for OmniScope
pub const DEFAULT_TOOL_INFO = ToolInfo{
    .name = "OmniScope",
    .version = "0.1.5",
    .information_uri = "https://github.com/omniscope/omniscope",
};

/// SARIF rule definition
///
/// Represents a single rule in the SARIF rule collection.
/// Each rule corresponds to an IssueKind in OmniScope.
pub const SarifRule = struct {
    id: []const u8,
    name: []const u8,
    short_description: []const u8,
    full_description: []const u8,
    help_uri_base: []const u8,
    default_severity: []const u8,
    cwe_id: u32,

    /// Generate rule from IssueKind
    pub fn fromIssueKind(kind: IssueKind) SarifRule {
        const id = kind.toString();
        const cwe_id = kind.toCweId();

        return .{
            .id = id,
            .name = id,
            .short_description = kind.toDescription(),
            .full_description = kind.toDescription(),
            .help_uri_base = "https://cwe.mitre.org/data/definitions/",
            .default_severity = switch (kind) {
                .memory_leak, .command_injection, .buffer_overflow, .use_after_free => "error",
                .double_free, .format_string, .malloc_unchecked, .invalid_free => "error",
                .ffi_unsafe_call, .unchecked_return, .type_mismatch => "warning",
                .cross_language_leak, .null_dereference => "warning",
                .borrow_escape => "error",
                .unknown => "note",
            },
            .cwe_id = cwe_id,
        };
    }

    /// Get full help URI with CWE ID
    pub fn getHelpUri(self: *const SarifRule, allocator: std.mem.Allocator) ![]const u8 {
        if (self.cwe_id == 0) {
            return allocator.dupe(u8, self.help_uri_base);
        }
        return std.fmt.allocPrint(allocator, "{s}{d}.html", .{ self.help_uri_base, self.cwe_id });
    }
};

/// SARIF result representation
///
/// Represents a single analysis result in SARIF format.
pub const SarifResult = struct {
    rule_id: []const u8,
    rule_index: usize,
    level: []const u8,
    message: []const u8,
    locations: []const SarifLocation,
    code_flows: ?[]const SarifCodeFlow,
    related_locations: []const SarifRelatedLocation,
    confidence: f32,

    /// Location in SARIF format
    pub const SarifLocation = struct {
        uri: []const u8,
        start_line: ?u32,
        start_column: ?u32,
        end_line: ?u32,
        end_column: ?u32,
        message: ?[]const u8,
    };

    /// Related location for code flows
    pub const SarifRelatedLocation = struct {
        id: u32,
        uri: []const u8,
        start_line: ?u32,
        start_column: ?u32,
        message: []const u8,
    };

    /// Code flow for tracking taint propagation
    pub const SarifCodeFlow = struct {
        message: []const u8,
        thread_flows: []const SarifThreadFlow,

        pub const SarifThreadFlow = struct {
            locations: []const SarifThreadFlowLocation,

            pub const SarifThreadFlowLocation = struct {
                location: SarifRelatedLocation,
                state: ?[]const u8,
            };
        };
    };
};

/// SARIF report generator
///
/// Generates SARIF v2.1.0 compliant output from OmniScope issues.
pub const SarifGenerator = struct {
    allocator: std.mem.Allocator,
    tool_info: ToolInfo,
    rules: std.AutoHashMap(IssueKind, SarifRule),
    rule_list: std.ArrayList(SarifRule),

    /// Initialize SARIF generator
    pub fn init(allocator: std.mem.Allocator, tool_info: ToolInfo) !SarifGenerator {
        var self = SarifGenerator{
            .allocator = allocator,
            .tool_info = tool_info,
            .rules = std.AutoHashMap(IssueKind, SarifRule).init(allocator),
            .rule_list = try std.ArrayList(SarifRule).initCapacity(allocator, 0),
        };

        try self.initRules();
        return self;
    }

    /// Initialize default rules
    fn initRules(self: *SarifGenerator) !void {
        const kinds = [_]IssueKind{
            .memory_leak,
            .ffi_unsafe_call,
            .unchecked_return,
            .type_mismatch,
            .cross_language_leak,
            .use_after_free,
            .command_injection,
            .buffer_overflow,
            .double_free,
            .format_string,
            .malloc_unchecked,
            .invalid_free,
            .null_dereference,
            .borrow_escape,
        };

        for (kinds) |kind| {
            const rule = SarifRule.fromIssueKind(kind);
            try self.rules.put(kind, rule);
            try self.rule_list.append(self.allocator, rule);
        }
    }

    /// Deinitialize generator
    pub fn deinit(self: *SarifGenerator) void {
        self.rules.deinit();
        self.rule_list.deinit(self.allocator);
    }

    /// Generate SARIF JSON from issues
    pub fn generate(self: *SarifGenerator, issues: []const Issue) ![]const u8 {
        var output = std.ArrayList(u8).initCapacity(self.allocator, 16384) catch return error.OutOfMemory;
        defer output.deinit(self.allocator);

        try self.writeHeader(&output);
        try self.writeRuns(&output, issues);
        try self.writeFooter(&output);

        return output.toOwnedSlice();
    }

    /// Write SARIF header
    fn writeHeader(output: *std.ArrayList(u8)) !void {
        try output.appendSlice("{\n");
        try output.writer().print("  \"version\": \"{s}\",\n", .{SARIF_VERSION});
        try output.writer().print("  \"$schema\": \"{s}\",\n", .{SARIF_SCHEMA});
    }

    /// Write runs section
    fn writeRuns(self: *SarifGenerator, output: *std.ArrayList(u8), issues: []const Issue) !void {
        try output.appendSlice("  \"runs\": [\n");
        try output.appendSlice("    {\n");

        try self.writeTool(&output);
        try output.appendSlice(",\n");
        try writeInvocations(&output);
        try output.appendSlice(",\n");
        try self.writeResults(&output, issues);

        try output.appendSlice("\n    }\n");
        try output.appendSlice("  ]\n");
    }

    /// Write tool section with rules
    fn writeTool(self: *SarifGenerator, output: *std.ArrayList(u8)) !void {
        try output.appendSlice("      \"tool\": {\n");
        try output.appendSlice("        \"driver\": {\n");
        try output.writer().print("          \"name\": \"{s}\",\n", .{self.tool_info.name});
        try output.writer().print("          \"version\": \"{s}\",\n", .{self.tool_info.version});
        try output.writer().print("          \"informationUri\": \"{s}\",\n", .{self.tool_info.information_uri});
        try self.writeRules(output);
        try output.appendSlice("        }\n");
        try output.appendSlice("      }");
    }

    /// Write rules within tool.driver
    fn writeRules(self: *SarifGenerator, output: *std.ArrayList(u8)) !void {
        try output.appendSlice("          \"rules\": [\n");

        for (self.rule_list.items, 0..) |rule, i| {
            if (i > 0) try output.appendSlice(",\n");
            try output.appendSlice("            {\n");
            try output.writer().print("              \"id\": \"{s}\",\n", .{rule.id});
            try output.writer().print("              \"name\": \"{s}\",\n", .{rule.name});
            try output.appendSlice("              \"shortDescription\": {\n");

            if (std.json.stringEncode(self.allocator, rule.short_description)) |escaped| {
                defer self.allocator.free(escaped);
                try output.writer().print("                \"text\": {s}\n", .{escaped});
            } else {
                try output.writer().print("                \"text\": \"{s}\"\n", .{rule.short_description});
            }

            try output.appendSlice("              },\n");
            try output.appendSlice("              \"fullDescription\": {\n");

            if (std.json.stringEncode(self.allocator, rule.full_description)) |escaped| {
                defer self.allocator.free(escaped);
                try output.writer().print("                \"text\": {s}\n", .{escaped});
            } else {
                try output.writer().print("                \"text\": \"{s}\"\n", .{rule.full_description});
            }
            try output.appendSlice("              },\n");
            try output.writer().print("              \"defaultConfiguration\": {{\n", .{});
            try output.writer().print("                \"level\": \"{s}\"\n", .{rule.default_severity});
            try output.appendSlice("              },\n");
            try output.writer().print("              \"helpUri\": \"{s}{d}.html\"\n", .{ rule.help_uri_base, rule.cwe_id });
            try output.appendSlice("            }");
        }

        try output.appendSlice("\n          ]");
    }

    /// Write invocations section (peer of tool and results)
    fn writeInvocations(output: *std.ArrayList(u8)) !void {
        try output.appendSlice("      \"invocations\": [\n");
        try output.appendSlice("        {\n");
        try output.appendSlice("          \"executionSuccessful\": true\n");
        try output.appendSlice("        }\n");
        try output.appendSlice("      ]");
    }

    /// Write results section
    fn writeResults(self: *SarifGenerator, output: *std.ArrayList(u8), issues: []const Issue) !void {
        try output.appendSlice("      \"results\": [\n");

        for (issues, 0..) |issue, i| {
            if (i > 0) try output.appendSlice(",\n");
            try self.writeResult(output, issue, i);
        }

        try output.appendSlice("\n      ]");
    }

    /// Write single result
    fn writeResult(self: *SarifGenerator, output: *std.ArrayList(u8), issue: Issue, index: usize) !void {
        _ = index;
        try output.appendSlice("        {\n");

        try output.writer().print("          \"ruleId\": \"{s}\",\n", .{issue.kind.toString()});
        try output.writer().print("          \"ruleIndex\": {d},\n", .{try self.getRuleIndex(issue.kind)});
        try output.writer().print("          \"level\": \"{s}\",\n", .{self.severityToLevel(issue.severity)});

        try self.writeMessage(output, issue.message);
        try output.appendSlice(",\n");

        try self.writeLocations(output, issue.location);
        try output.appendSlice(",\n");

        try writeProperties(output, issue);

        if (issue.ffi_boundary) |boundary| {
            try output.appendSlice(",\n");
            try self.writeCodeFlows(output, boundary);
        }

        try output.appendSlice("\n        }");
    }

    /// Write message section
    fn writeMessage(self: *SarifGenerator, output: *std.ArrayList(u8), message: []const u8) !void {
        try output.appendSlice("          \"message\": {\n");
        const escaped = std.json.stringEncode(self.allocator, message) catch {
            try output.writer().print("            \"text\": \"{s}\"\n", .{message});
            try output.appendSlice("          }");
            return;
        };
        defer self.allocator.free(escaped);
        try output.writer().print("            \"text\": {s}\n", .{escaped});
        try output.appendSlice("          }");
    }

    /// Write locations section
    fn writeLocations(self: *SarifGenerator, output: *std.ArrayList(u8), location: Location) !void {
        try output.appendSlice("          \"locations\": [\n");
        try output.appendSlice("            {\n");
        try output.appendSlice("              \"physicalLocation\": {\n");
        try output.appendSlice("                \"artifactLocation\": {\n");

        const uri_text = if (location.file) |file|
            file
        else
            location.function;

        const escaped_uri = std.json.stringEncode(self.allocator, uri_text) catch {
            try output.writer().print("                  \"uri\": \"{s}\"\n", .{uri_text});
            try output.appendSlice("                },\n");
            try output.appendSlice("                \"region\": {\n");
            if (location.line) |line| {
                try output.writer().print("                  \"startLine\": {d}", .{line});
                if (location.column) |col| {
                    try output.writer().print(",\n                  \"startColumn\": {d}", .{col});
                }
                try output.appendSlice("\n");
            } else {
                try output.appendSlice("                  \"startLine\": 1\n");
            }
            try output.appendSlice("                }\n");
            try output.appendSlice("              }\n");
            try output.appendSlice("            }\n");
            try output.appendSlice("          }");
            return;
        };
        defer self.allocator.free(escaped_uri);
        try output.writer().print("                  \"uri\": {s}\n", .{escaped_uri});

        try output.appendSlice("                },\n");
        try output.appendSlice("                \"region\": {\n");

        if (location.line) |line| {
            try output.writer().print("                  \"startLine\": {d}", .{line});
            if (location.column) |col| {
                try output.writer().print(",\n                  \"startColumn\": {d}", .{col});
            }
            try output.appendSlice("\n");
        } else {
            try output.appendSlice("                  \"startLine\": 1\n");
        }

        try output.appendSlice("                }\n");
        try output.appendSlice("              }\n");
        try output.appendSlice("            }\n");
        try output.appendSlice("          }");
    }

    /// Write properties section
    fn writeProperties(output: *std.ArrayList(u8), issue: Issue) !void {
        try output.appendSlice("          \"properties\": {\n");
        try output.writer().print("            \"confidence\": {d:.2},\n", .{issue.confidence});
        try output.writer().print("            \"confidenceLevel\": \"{s}\",\n", .{issue.confidence_level.toString()});
        try output.writer().print("            \"severity\": \"{s}\",\n", .{issue.severity.toString()});
        try output.writer().print("            \"cwe\": \"CWE-{d}\"", .{issue.kind.toCweId()});
        if (issue.reason.len > 0) {
            try output.writer().print(",\n            \"reason\": \"", .{});
            for (issue.reason) |c| {
                switch (c) {
                    '"' => try output.writer().writeAll("\\\""),
                    '\\' => try output.writer().writeAll("\\\\"),
                    '\n' => try output.writer().writeAll("\\n"),
                    '\r' => try output.writer().writeAll("\\r"),
                    '\t' => try output.writer().writeAll("\\t"),
                    else => {
                        if (c < 0x20) {
                            try output.writer().print("\\u{X:0>4}", .{c});
                        } else {
                            try output.writer().writeByte(c);
                        }
                    },
                }
            }
            try output.appendSlice("\"");
        }
        try output.appendSlice("\n          }");
    }

    /// Write code flows section
    fn writeCodeFlows(self: *SarifGenerator, output: *std.ArrayList(u8), boundary: FFIBoundary) !void {
        try output.appendSlice("          \"codeFlows\": [\n");
        try output.appendSlice("            {\n");
        try output.appendSlice("              \"message\": {\n");
        try output.appendSlice("                \"text\": \"FFI boundary crossing\"\n");
        try output.appendSlice("              },\n");
        try output.appendSlice("              \"threadFlows\": [\n");
        try output.appendSlice("                {\n");
        try output.appendSlice("                  \"locations\": [\n");

        try self.writeThreadFlowLocation(output, boundary, 0, "FFI boundary");

        try output.appendSlice("                  ]\n");
        try output.appendSlice("                }\n");
        try output.appendSlice("              ]\n");
        try output.appendSlice("            }\n");
        try output.appendSlice("          ]");
    }

    /// Write thread flow location
    fn writeThreadFlowLocation(self: *SarifGenerator, output: *std.ArrayList(u8), boundary: FFIBoundary, step: usize, message: []const u8) !void {
        try output.appendSlice("                    {\n");
        try output.appendSlice("                      \"location\": {\n");
        try output.writer().print("                        \"id\": {d},\n", .{step});
        try output.appendSlice("                        \"physicalLocation\": {\n");
        try output.appendSlice("                          \"artifactLocation\": {\n");

        if (std.json.stringEncode(self.allocator, boundary.function_name)) |escaped| {
            defer self.allocator.free(escaped);
            try output.writer().print("                            \"uri\": {s}\n", .{escaped});
        } else {
            try output.writer().print("                            \"uri\": \"{s}\"\n", .{boundary.function_name});
        }

        try output.appendSlice("                          }\n");
        try output.appendSlice("                        },\n");
        try output.appendSlice("                        \"message\": {\n");

        if (std.json.stringEncode(self.allocator, message)) |escaped| {
            defer self.allocator.free(escaped);
            try output.writer().print("                          \"text\": {s}\n", .{escaped});
        } else {
            try output.writer().print("                          \"text\": \"{s}\"\n", .{message});
        }

        try output.appendSlice("                        }\n");
        try output.appendSlice("                      }\n");
        try output.appendSlice("                    }");
    }

    /// Write footer
    fn writeFooter(self: *SarifGenerator, output: *std.ArrayList(u8)) !void {
        _ = self;
        try output.appendSlice("}\n");
    }

    /// Get rule index for issue kind
    fn getRuleIndex(self: *SarifGenerator, kind: IssueKind) !usize {
        for (self.rule_list.items, 0..) |rule, i| {
            if (std.mem.eql(u8, rule.id, kind.toString())) {
                return i;
            }
        }
        return error.RuleNotFound;
    }

    /// Convert severity to SARIF level
    fn severityToLevel(self: *SarifGenerator, severity: Severity) []const u8 {
        _ = self;
        return switch (severity) {
            .critical, .high => "error",
            .medium => "warning",
            .low => "note",
        };
    }

    /// Write SARIF output to file
    pub fn writeToFile(self: *SarifGenerator, path: []const u8, issues: []const Issue) !void {
        const json = try self.generate(issues);
        defer self.allocator.free(json);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(json);
    }
};

/// Generate SARIF from issues (convenience function)
pub fn generateSarif(allocator: std.mem.Allocator, issues: []const Issue, tool_info: ?ToolInfo) ![]const u8 {
    var generator = try SarifGenerator.init(allocator, tool_info orelse DEFAULT_TOOL_INFO);
    defer generator.deinit();
    return generator.generate(issues);
}

/// Write SARIF to file (convenience function)
pub fn writeSarifToFile(allocator: std.mem.Allocator, path: []const u8, issues: []const Issue, tool_info: ?ToolInfo) !void {
    var generator = try SarifGenerator.init(allocator, tool_info orelse DEFAULT_TOOL_INFO);
    defer generator.deinit();
    return generator.writeToFile(path, issues);
}

// ============================================================================
// Unit Tests
// ============================================================================

test "SarifGenerator - init and deinit" {
    var generator = try SarifGenerator.init(std.testing.allocator, DEFAULT_TOOL_INFO);
    defer generator.deinit();

    try std.testing.expectEqualStrings("OmniScope", generator.tool_info.name);
}

test "SarifGenerator - generate empty" {
    var generator = try SarifGenerator.init(std.testing.allocator, DEFAULT_TOOL_INFO);
    defer generator.deinit();

    const issues = [_]Issue{};
    const json = try generator.generate(&issues);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\": \"2.1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"results\": [") != null);
}

test "SarifGenerator - generate single issue" {
    var generator = try SarifGenerator.init(std.testing.allocator, DEFAULT_TOOL_INFO);
    defer generator.deinit();

    const location = Location.init("test_func");
    const issue = Issue.init(
        .command_injection,
        "Test command injection",
        location,
        .critical,
        0.95,
    );

    const issues = [_]Issue{issue};
    const json = try generator.generate(&issues);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "command_injection") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Test command injection") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"level\": \"error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"confidence\": 0.95") != null);
}

test "SarifGenerator - severity mapping" {
    var generator = try SarifGenerator.init(std.testing.allocator, DEFAULT_TOOL_INFO);
    defer generator.deinit();

    try std.testing.expectEqualStrings("error", generator.severityToLevel(.critical));
    try std.testing.expectEqualStrings("error", generator.severityToLevel(.high));
    try std.testing.expectEqualStrings("warning", generator.severityToLevel(.medium));
    try std.testing.expectEqualStrings("note", generator.severityToLevel(.low));
}

test "SarifGenerator - multiple issues" {
    var generator = try SarifGenerator.init(std.testing.allocator, DEFAULT_TOOL_INFO);
    defer generator.deinit();

    const location = Location.init("test_func");

    const issues = [_]Issue{
        Issue.init(.command_injection, "Command injection", location, .critical, 0.95),
        Issue.init(.buffer_overflow, "Buffer overflow", location, .high, 0.90),
        Issue.init(.type_mismatch, "Type mismatch", location, .medium, 0.80),
    };

    const json = try generator.generate(&issues);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "command_injection") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "buffer_overflow") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "type_mismatch") != null);
}

test "SarifGenerator - location with file" {
    var generator = try SarifGenerator.init(std.testing.allocator, DEFAULT_TOOL_INFO);
    defer generator.deinit();

    const location = Location.initFull("test_func", "test.rs", 42, 10);
    const issue = Issue.init(.use_after_free, "Use after free", location, .high, 0.85);

    const issues = [_]Issue{issue};
    const json = try generator.generate(&issues);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"uri\": \"test.rs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"startLine\": 42") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"startColumn\": 10") != null);
}

test "SarifGenerator - FFI boundary code flow" {
    var generator = try SarifGenerator.init(std.testing.allocator, DEFAULT_TOOL_INFO);
    defer generator.deinit();

    const location = Location.init("ffi_func");
    var issue = Issue.init(.ffi_unsafe_call, "Unsafe FFI call", location, .high, 0.90);

    const boundary = FFIBoundary.init(
        1,
        .rust_to_c,
        .rust,
        .c,
        "external_func",
        location,
    );
    issue.setFFIBoundary(boundary);

    const issues = [_]Issue{issue};
    const json = try generator.generate(&issues);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"codeFlows\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "FFI boundary crossing") != null);
}

test "SarifGenerator - write to file" {
    var generator = try SarifGenerator.init(std.testing.allocator, DEFAULT_TOOL_INFO);
    defer generator.deinit();

    const location = Location.init("test_func");
    const issue = Issue.init(.malloc_unchecked, "Unchecked malloc", location, .high, 0.85);

    const issues = [_]Issue{issue};

    const temp_file = "test_sarif_output.sarif";
    defer {
        std.fs.cwd().deleteFile(temp_file) catch |err| {
            std.log.warn("Failed to delete temp file: {}", .{err});
        };
    }

    try generator.writeToFile(temp_file, &issues);

    const file = try std.fs.cwd().openFile(temp_file, .{});
    defer file.close();

    const content = try file.readToEndAlloc(std.testing.allocator, 10240);
    defer std.testing.allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "malloc_unchecked") != null);
}

test "generateSarif - convenience function" {
    const location = Location.init("test_func");
    const issue = Issue.init(.invalid_free, "Invalid free", location, .medium, 0.75);

    const issues = [_]Issue{issue};

    const json = try generateSarif(std.testing.allocator, &issues, null);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "invalid_free") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"level\": \"warning\"") != null);
}

test "SarifRule - fromIssueKind" {
    const rule = SarifRule.fromIssueKind(.command_injection);

    try std.testing.expectEqualStrings("command_injection", rule.id);
    try std.testing.expectEqual(@as(u32, 78), rule.cwe_id);
    try std.testing.expectEqualStrings("error", rule.default_severity);
}

test "SarifGenerator - CWE mapping" {
    var generator = try SarifGenerator.init(std.testing.allocator, DEFAULT_TOOL_INFO);
    defer generator.deinit();

    const location = Location.init("test_func");
    const issue = Issue.init(.buffer_overflow, "Buffer overflow", location, .critical, 0.95);

    const issues = [_]Issue{issue};
    const json = try generator.generate(&issues);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"cwe\": \"CWE-120\"") != null);
}

test "SarifGenerator - GitHub CodeQL compatible" {
    var generator = try SarifGenerator.init(std.testing.allocator, DEFAULT_TOOL_INFO);
    defer generator.deinit();

    const location = Location.initFull("main", "src/main.rs", 100, 5);
    const issue = Issue.init(.command_injection, "OS command injection via user input", location, .critical, 0.98);

    const issues = [_]Issue{issue};
    const json = try generator.generate(&issues);
    defer std.testing.allocator.free(json);

    // Verify GitHub CodeQL required fields
    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\": \"2.1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"$schema\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"runs\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tool\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"driver\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\": \"OmniScope\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\": \"0.1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"informationUri\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"results\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ruleId\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"level\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"message\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"locations\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"physicalLocation\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"artifactLocation\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"region\":") != null);
}
