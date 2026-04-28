//! SARIF (Static Analysis Results Interchange Format) Output
//!
//! Phase 7: Standardized output for IDE integration.
//!
//! Supports:
//! - VS Code SARIF Viewer extension
//! - GitHub Code Scanning
//! - Azure DevOps
//! - Any SARIF-compatible tool
//!
//! Reference: https://docs.oasis-open.org/sarif/sarif/v2.1.0/

const std = @import("std");
const Issue = @import("issue.zig").Issue;
const Diagnostic = @import("aggregator.zig").Diagnostic;

/// SARIF severity level mapping.
pub const SarifLevel = enum {
    err,
    warning,
    note,
    none,

    pub fn fromSeverity(sev: u8) SarifLevel {
        return switch (sev) {
            0, 1 => .err,
            2 => .warning,
            3 => .note,
            else => .none,
        };
    }

    pub fn toJson(self: SarifLevel) []const u8 {
        return switch (self) {
            .err => "\"error\"",
            .warning => "\"warning\"",
            .note => "\"note\"",
            .none => "\"none\"",
        };
    }
};

/// SARIF result kind classification.
pub const SarifKind = enum {
    memory_safety,
    concurrency,
    security,
    performance,
    correctness,

    pub fn fromIssueKind(kind_str: []const u8) SarifKind {
        const memory_kinds = [_][]const u8{
            "use_after_free",    "double_free",  "null_dereference",
            "buffer_overflow",   "memory_leak",  "borrow_escape",
            "uninitialized_mem", "stack_buffer",
        };
        for (memory_kinds) |k| {
            if (std.mem.eql(u8, kind_str, k)) return .memory_safety;
        }
        const security_kinds = [_][]const u8{
            "command_injection", "ffi_unsafe_call", "integer_overflow",
        };
        for (security_kinds) |k| {
            if (std.mem.eql(u8, kind_str, k)) return .security;
        }
        if (std.mem.indexOf(u8, kind_str, "race") != null) return .concurrency;
        if (std.mem.indexOf(u8, kind_str, "inefficient") != null or
            std.mem.indexOf(u8, kind_str, "redundant") != null) return .performance;
        return .correctness;
    }

    pub fn toRuleId(self: SarifKind) []const u8 {
        return switch (self) {
            .memory_safety => "omniscope/memory-safety",
            .concurrency => "omniscope/concurrency",
            .security => "omniscope/security",
            .performance => "omniscope/performance",
            .correctness => "omniscope/correctness",
        };
    }
};

/// SARIF v2.1.0 writer.
pub const SarifWriter = struct {
    allocator: std.mem.Allocator,
    tool_name: []const u8,
    results: std.ArrayList(SarifResult),

    const SarifResult = struct {
        rule_id: []const u8,
        level: SarifKind,
        message: []const u8,
        file: ?[]const u8,
        line: ?u32,
        column: ?u32,
        confidence: f32,
    };

    pub fn init(allocator: std.mem.Allocator, tool_name: []const u8) SarifWriter {
        return .{
            .allocator = allocator,
            .tool_name = tool_name,
            .results = std.ArrayList(SarifResult).init(allocator),
        };
    }

    pub fn deinit(self: *SarifWriter) void {
        for (self.results.items) |r| {
            self.allocator.free(r.rule_id);
            self.allocator.free(r.message);
            if (r.file) |f| self.allocator.free(f);
        }
        self.results.deinit();
    }

    /// Add an issue as a SARIF result.
    pub fn addIssue(self: *SarifWriter, issue: anytype) !void {
        const T = @TypeOf(issue);
        const kind_tag = if (@hasField(T, "kind"))
            @tagName(@field(issue, "kind"))
        else
            "unknown";

        const msg = if (@hasField(T, "message"))
            @field(issue, "message")
        else if (@hasField(T, "description"))
            @field(issue, "description")
        else
            "(no message)";

        const conf: f32 = if (@hasField(T, "confidence"))
            @field(issue, "confidence")
        else
            0.5;

        var file: ?[]const u8 = null;
        var line: ?u32 = null;
        if (@hasField(T, "location")) {
            const loc = @field(issue, "location");
            if (@hasField(@TypeOf(loc), "file")) {
                if (@field(loc, "file")) |f| {
                    file = try self.allocator.dupe(u8, f);
                }
            }
            if (@hasField(@TypeOf(loc), "line")) {
                if (@field(loc, "line")) |l| {
                    line = l;
                }
            }
        }

        const rule_id = try self.allocator.dupe(u8, SarifKind.fromIssueKind(kind_tag).toRuleId());
        const msg_copy = try self.allocator.dupe(u8, msg);

        try self.results.append(.{
            .rule_id = rule_id,
            .level = SarifKind.fromIssueKind(kind_tag),
            .message = msg_copy,
            .file = file,
            .line = line,
            .column = null,
            .confidence = conf,
        });
    }

    /// Add all diagnostics from aggregator.
    pub fn addDiagnostics(self: *SarifWriter, diags: []const Diagnostic) !void {
        for (diags) |d| {
            const level = switch (d.severity) {
                .err => SarifKind.security,
                .warning => SarifKind.correctness,
                .info => SarifKind.performance,
                .debug => SarifKind.correctness,
            };
            const rule_id = try self.allocator.dupe(u8, level.toRuleId());
            const msg = try self.allocator.dupe(u8, d.message);
            try self.results.append(.{
                .rule_id = rule_id,
                .level = level,
                .message = msg,
                .file = null,
                .line = null,
                .column = null,
                .confidence = d.confidence,
            });
        }
    }

    /// Generate SARIF JSON output.
    pub fn generate(self: *const SarifWriter) ![]u8 {
        var out = std.ArrayList(u8).init(self.allocator);
        defer out.deinit();

        const writer = out.writer();

        try writer.writeAll("{\n");
        try writer.writeAll("  \"$schema\": \"https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json\",\n");
        try writer.writeAll("  \"version\": \"2.1.0\",\n");

        // $schema and version are required; we'll include them inline above

        // Tool component
        try writer.writeAll("  \"runs\": [\n");
        try writer.writeAll("    {\n");
        try writer.print("      \"tool\": {{\n", .{});
        try writer.print("        \"driver\": {{\n", .{});
        try writer.print("          \"name\": \"{s}\",\n", .{self.tool_name});
        try writer.print("          \"version\": \"0.1.6\",\n", .{});
        try writer.print("          \"informationUri\": \"https://github.com/omniscope/omniscope\",\n", .{});
        try writer.print("          \"rules\": [\n", .{});

        // Rules
        var rules_written: usize = 0;
        const kinds = [_]SarifKind{ .memory_safety, .security, .concurrency, .performance, .correctness };
        for (kinds) |kind| {
            const has_results = for (self.results.items) |r| {
                if (r.level == kind) break true;
            } else false;
            if (!has_results) continue;

            if (rules_written > 0) try writer.writeAll(",\n");
            rules_written += 1;
            try writer.print("            {{\n", .{});
            try writer.print("              \"id\": \"{s}\",\n", .{kind.toRuleId()});
            try writer.print("              \"shortDescription\": {{\n", .{});
            try writer.print("                \"text\": \"OmniScope {s} issue\"\n", .{@tagName(kind)});
            try writer.print("              }},\n", .{});
            try writer.print("              \"fullDescription\": {{\n", .{});
            try writer.print("                \"text\": \"Detected by OmniScope FFI/Unsafe boundary analyzer\"\n", .{});
            try writer.print("              }},\n", .{});
            try writer.print("              \"defaultConfiguration\": {{\n", .{});
            try writer.print("                \"level\": \"{s}\"\n", .{switch (kind) {
                .memory_safety, .security => "error",
                .concurrency, .correctness => "warning",
                .performance => "note",
            }});
            try writer.print("              }}\n", .{});
            try writer.writeAll("            }");
        }
        try writer.writeAll("\n          ]\n");
        try writer.writeAll("        }\n");
        try writer.writeAll("      }\n");
        try writer.writeAll("    },\n");

        // Results
        try writer.writeAll("      \"results\": [\n");
        for (self.results.items, 0..) |result, i| {
            if (i > 0) try writer.writeAll(",\n");
            try writer.writeAll("        {\n");
            try writer.print("          \"ruleId\": \"{s}\",\n", .{result.rule_id});
            try writer.print("          \"level\": \"{s}\",\n", .{switch (result.level) {
                .memory_safety, .security => "error",
                .concurrency, .correctness => "warning",
                .performance => "note",
            }});
            try writer.writeAll("          \"message\": {\n");
            const escaped_msg = try self.escapeJsonString(result.message);
            defer self.allocator.free(escaped_msg);
            try writer.print("            \"text\": \"{s}\"\n", .{escaped_msg});
            try writer.writeAll("          },\n");

            // Locations
            if (result.file != null or result.line != null) {
                try writer.writeAll("          \"locations\": [\n");
                try writer.writeAll("            {\n");
                try writer.writeAll("              \"physicalLocation\": {\n");
                try writer.writeAll("                \"artifactLocation\": {\n");
                if (result.file) |f| {
                    try writer.print("                  \"uri\": \"file://{s}\"\n", .{f});
                } else {
                    try writer.writeAll("                  \"uri\": \"unknown\"\n");
                }
                try writer.writeAll("                },\n");
                if (result.line) |l| {
                    try writer.print("                \"region\": {{\n                  \"startLine\": {d}\n                }}\n", .{l});
                } else {
                    try writer.writeAll("                \"region\": {}\n");
                }
                try writer.writeAll("              }\n");
                try writer.writeAll("            }\n");
                try writer.writeAll("          ],\n");
            }

            // Properties (confidence)
            try writer.writeAll("          \"properties\": {\n");
            try writer.print("            \"confidence\": {d:.2}\n", .{result.confidence});
            try writer.writeAll("          }\n");
            try writer.writeAll("        }");
        }
        try writer.writeAll("\n      ]\n");
        try writer.writeAll("    }\n");
        try writer.writeAll("  ]\n");
        try writer.writeAll("}\n");

        return try self.allocator.dupe(u8, out.items);
    }

    /// Write SARIF to file.
    pub fn writeToFile(self: *const SarifWriter, path: []const u8) !void {
        const content = try self.generate();
        defer self.allocator.free(content);

        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();
        try file.writeAll(content);
    }

    fn escapeJsonString(self: *const SarifWriter, s: []const u8) ![]const u8 {
        var out = std.ArrayList(u8).init(self.allocator);
        errdefer out.deinit();
        const w = out.writer();

        for (s) |c| {
            switch (c) {
                '"' => try w.writeAll("\\\""),
                '\\' => try w.writeAll("\\\\"),
                '\n' => try w.writeAll("\\n"),
                '\r' => try w.writeAll("\\r"),
                '\t' => try w.writeAll("\\t"),
                0x00...0x1F => try w.print("\\u{X:0>4}", .{c}),
                else => try w.writeByte(c),
            }
        }
        return try out.toOwnedSlice();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "SarifWriter - basic functionality" {
    var writer = SarifWriter.init(std.testing.allocator, "OmniScope");
    defer writer.deinit();

    const TestIssue = struct {
        location: struct { function: []const u8, file: ?[]const u8, line: ?u32, column: ?u32 },
        kind: enum { memory_leak, use_after_free },
        message: []const u8,
        confidence: f32,
    };

    try writer.addIssue(TestIssue{
        .location = .{ .function = "test_func", .file = "test.c", .line = 42, .column = null },
        .kind = .memory_leak,
        .message = "Memory leak detected",
        .confidence = 0.85,
    });

    try writer.addIssue(TestIssue{
        .location = .{ .function = "other_func", .file = null, .line = null, .column = null },
        .kind = .use_after_free,
        .message = "Use after free",
        .confidence = 0.92,
    });

    try std.testing.expectEqual(@as(usize, 2), writer.results.items.len);

    const sarif_json = try writer.generate();
    defer std.testing.allocator.free(sarif_json);

    try std.testing.expect(sarif_json.len > 0);
    // Verify key SARIF fields present
    try std.testing.expect(std.mem.indexOf(u8, sarif_json, "$schema") != null);
    try std.testing.expect(std.mem.indexOf(u8, sarif_json, "sarif-2.1") != null);
    try std.testing.expect(std.mem.indexOf(u8, sarif_json, "OmniScope") != null);
}

test "SarifLevel - fromSeverity" {
    try std.testing.expectEqual(SarifLevel.err, SarifLevel.fromSeverity(0));
    try std.testing.expectEqual(SarifLevel.err, SarifLevel.fromSeverity(1));
    try std.testing.expectEqual(SarifLevel.warning, SarifLevel.fromSeverity(2));
    try std.testing.expectEqual(SarifLevel.note, SarifLevel.fromSeverity(3));
    try std.testing.expectEqual(SarifLevel.none, SarifLevel.fromSeverity(99));
}

test "SarifKind - fromIssueKind" {
    try std.testing.expectEqual(SarifKind.memory_safety, SarifKind.fromIssueKind("use_after_free"));
    try std.testing.expectEqual(SarifKind.memory_safety, SarifKind.fromIssueKind("memory_leak"));
    try std.testing.expectEqual(SarifKind.security, SarifKind.fromIssueKind("command_injection"));
    try std.testing.expectEqual(SarifKind.concurrency, SarifKind.fromIssueKind("race_condition"));
    try std.testing.expectEqual(SarifKind.performance, SarifKind.fromIssueKind("inefficient_copy"));
    try std.testing.expectEqual(SarifKind.correctness, SarifKind.fromIssueKind("buffer_overflow"));
}

test "SarifKind - toRuleId" {
    try std.testing.expectEqualStrings("omniscope/memory-safety", SarifKind.memory_safety.toRuleId());
    try std.testing.expectEqualStrings("omniscope/security", SarifKind.security.toRuleId());
    try std.testing.expectEqualStrings("omniscope/concurrency", SarifKind.concurrency.toRuleId());
    try std.testing.expectEqualStrings("omniscope/performance", SarifKind.performance.toRuleId());
    try std.testing.expectEqualStrings("omniscope/correctness", SarifKind.correctness.toRuleId());
}
