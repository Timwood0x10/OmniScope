//! SARIF Output Format
//!
//! This module implements SARIF (Static Analysis Results Interchange Format) v2.1.0 output.
//! SARIF is an OASIS standard for sharing static analysis results.
//!
//! Features:
//! - Full location information (file, line, column)
//! - CWE taxonomy mapping
//! - Code flows for data flow visualization
//! - Related locations for context
//! - Properties for additional metadata

const std = @import("std");

const Issue = @import("../diag/issue.zig").Issue;
const IssueKind = @import("../diag/issue.zig").IssueKind;
const Severity = @import("../diag/issue.zig").Severity;
const Location = @import("../diag/issue.zig").Location;
const TraceEntry = @import("../diag/issue.zig").TraceEntry;

/// SARIF severity level mapping
const SarifLevel = enum {
    none,
    note,
    warning,
    err,

    fn fromSeverity(severity: Severity) SarifLevel {
        return switch (severity) {
            .low => .note,
            .medium => .warning,
            .high => .err,
            .critical => .err,
        };
    }

    fn toString(self: SarifLevel) []const u8 {
        return switch (self) {
            .none => "none",
            .note => "note",
            .warning => "warning",
            .err => "error",
        };
    }
};

/// SARIF output handler
pub const SarifOutput = struct {
    allocator: std.mem.Allocator,
    tool_name: []const u8,
    tool_version: []const u8,
    tool_uri: []const u8,

    /// Create a new SARIF output handler
    pub fn init(allocator: std.mem.Allocator, tool_name: []const u8, tool_version: []const u8) SarifOutput {
        return .{
            .allocator = allocator,
            .tool_name = tool_name,
            .tool_version = tool_version,
            .tool_uri = "https://github.com/omniscope/omniscope",
        };
    }

    /// Create a new SARIF output handler with custom URI
    pub fn initWithUri(allocator: std.mem.Allocator, tool_name: []const u8, tool_version: []const u8, uri: []const u8) SarifOutput {
        return .{
            .allocator = allocator,
            .tool_name = tool_name,
            .tool_version = tool_version,
            .tool_uri = uri,
        };
    }

    /// Generate SARIF JSON from issues
    pub fn generate(self: *SarifOutput, issues: []const Issue) ![]const u8 {
        var json = std.ArrayList(u8).init(self.allocator);
        const writer = json.writer();

        // SARIF header
        try writer.writeAll("{\"version\":\"2.1.0\",");
        try writer.writeAll("\"$schema\":\"https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json\",");
        try writer.writeAll("\"runs\":[");

        // Run entry
        try self.writeRunHeader(writer);
        try writer.writeAll("\"results\":[");

        // Write each issue
        for (issues, 0..) |issue, i| {
            if (i > 0) try writer.writeByte(',');
            try self.writeIssue(writer, issue);
        }

        try writer.writeAll("],");

        // Write rules (taxonomies)
        try writer.writeAll("\"taxonomies\":[");
        try self.writeCWETaxonomy(writer);
        try writer.writeAll("]");

        try writer.writeAll("}]}");

        return json.toOwnedSlice();
    }

    /// Write run header with tool information
    fn writeRunHeader(self: *SarifOutput, writer: anytype) !void {
        try writer.writeAll("{\"tool\":{\"driver\":{");
        try writer.writeAll("\"name\":\"");
        try writeEscapedString(writer, self.tool_name);
        try writer.writeAll("\",\"version\":\"");
        try writeEscapedString(writer, self.tool_version);
        try writer.writeAll("\",\"informationUri\":\"");
        try writeEscapedString(writer, self.tool_uri);
        try writer.writeAll("\",\"rules\":[");

        // Write rule definitions
        const rules = [_]IssueKind{
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
        };

        for (rules, 0..) |kind, i| {
            if (i > 0) try writer.writeByte(',');
            try self.writeRule(writer, kind);
        }

        try writer.writeAll("]}}},");
    }

    /// Write a rule definition
    fn writeRule(self: *SarifOutput, writer: anytype, kind: IssueKind) !void {
        _ = self;
        try writer.writeAll("{\"id\":\"");
        try writeEscapedString(writer, @tagName(kind));
        try writer.writeAll("\",\"shortDescription\":{\"text\":\"");
        try writeEscapedString(writer, kind.toDescription());
        try writer.writeAll("\"},\"fullDescription\":{\"text\":\"");
        try writeEscapedString(writer, kind.toDescription());
        try writer.writeAll("\"},\"defaultConfiguration\":{\"level\":\"");
        const level = SarifLevel.fromSeverity(defaultSeverity(kind));
        try writer.writeAll(level.toString());
        try writer.writeAll("\"},\"relationships\":[{\"target\":{\"id\":\"CWE-");
        try std.fmt.formatInt(kind.toCweId(), 10, .lower, .{}, writer);
        try writer.writeAll("\",\"toolComponent\":{\"name\":\"CWE\"}},\"kinds\":[\"superset\"]}]}");
    }

    /// Write an issue as a SARIF result
    fn writeIssue(self: *SarifOutput, writer: anytype, issue: Issue) !void {
        try writer.writeAll("{\"ruleId\":\"");
        try writeEscapedString(writer, @tagName(issue.kind));
        try writer.writeAll("\",\"level\":\"");
        try writer.writeAll(SarifLevel.fromSeverity(issue.severity).toString());
        try writer.writeAll("\",\"message\":{\"text\":\"");
        try writeEscapedString(writer, issue.message);
        try writer.writeAll("\"}");

        // Write location
        try writer.writeAll(",\"locations\":[");
        try self.writeLocation(writer, issue.location);
        try writer.writeAll("]");

        // Write code flows if trace exists
        if (issue.hasTrace()) {
            try writer.writeAll(",\"codeFlows\":[");
            try self.writeCodeFlow(writer, issue.trace.?);
            try writer.writeAll("]");
        }

        // Write properties
        try writer.writeAll(",\"properties\":{\"confidence\":");
        try std.fmt.formatFloatDecimal(issue.confidence, .{ .precision = 2 }, writer);
        try writer.writeAll("}}");
    }

    /// Write a location object
    fn writeLocation(self: *SarifOutput, writer: anytype, location: Location) !void {
        _ = self;
        try writer.writeAll("{\"physicalLocation\":{");

        // Write artifact location (file)
        if (location.file) |file| {
            try writer.writeAll("\"artifactLocation\":{\"uri\":\"");
            try writeEscapedString(writer, file);
            try writer.writeAll("\"},");
        }

        // Write region (line/column)
        try writer.writeAll("\"region\":{");
        var has_region = false;

        if (location.line) |line| {
            try writer.writeAll("\"startLine\":");
            try std.fmt.formatInt(line, 10, .lower, .{}, writer);
            has_region = true;
        }

        if (location.column) |column| {
            if (has_region) try writer.writeByte(',');
            try writer.writeAll("\"startColumn\":");
            try std.fmt.formatInt(column, 10, .lower, .{}, writer);
            has_region = true;
        }

        if (!has_region) {
            try writer.writeAll("\"startLine\":1");
        }

        try writer.writeAll("}}");

        // Write logical location (function)
        try writer.writeAll(",\"logicalLocations\":[{\"fullyQualifiedName\":\"");
        try writeEscapedString(writer, location.function);
        try writer.writeAll("\"}]}");
    }

    /// Write a code flow for trace visualization
    fn writeCodeFlow(self: *SarifOutput, writer: anytype, trace: []const TraceEntry) !void {
        _ = self;
        try writer.writeAll("{\"threadFlows\":[{\"locations\":[");

        for (trace, 0..) |entry, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.writeAll("{\"location\":{");

            if (entry.location) |loc| {
                try writer.writeAll("\"physicalLocation\":{");
                if (loc.file) |file| {
                    try writer.writeAll("\"artifactLocation\":{\"uri\":\"");
                    try writeEscapedString(writer, file);
                    try writer.writeAll("\"},");
                }
                if (loc.line) |line| {
                    try writer.writeAll("\"region\":{\"startLine\":");
                    try std.fmt.formatInt(line, 10, .lower, .{}, writer);
                    try writer.writeAll("}");
                }
                try writer.writeAll("},");
            }

            try writer.writeAll("\"message\":{\"text\":\"");
            try writeEscapedString(writer, entry.description);
            try writer.writeAll("\"}}}");
        }

        try writer.writeAll("]}]}");
    }

    /// Write CWE taxonomy
    fn writeCWETaxonomy(self: *SarifOutput, writer: anytype) !void {
        _ = self;
        try writer.writeAll("{\"name\":\"CWE\",\"version\":\"4.13\",\"informationUri\":\"https://cwe.mitre.org/data/index.html\"}");
    }

    /// Write SARIF output to file
    pub fn writeToFile(self: *SarifOutput, path: []const u8, issues: []const Issue) !void {
        const json = try self.generate(issues);
        defer self.allocator.free(json);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(json);
    }
};

/// Get default severity for an issue kind
fn defaultSeverity(kind: IssueKind) Severity {
    return switch (kind) {
        .command_injection => .critical,
        .buffer_overflow, .use_after_free, .double_free => .high,
        .format_string, .cross_language_leak, .type_mismatch => .medium,
        .ffi_unsafe_call, .unchecked_return, .malloc_unchecked, .invalid_free => .medium,
        .unknown => .low,
    };
}

/// Write a JSON-escaped string
fn writeEscapedString(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{X:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}

// Unit tests

test "SarifOutput - init" {
    const output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");
    try std.testing.expectEqualStrings("OmniScope", output.tool_name);
    try std.testing.expectEqualStrings("1.0.0", output.tool_version);
}

test "SarifOutput - generate empty" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");
    const issues = [_]Issue{};
    const json = try output.generate(&issues);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"results\":[]") != null);
}

test "SarifOutput - generate with location" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    var loc = Location.init("test_func");
    loc.file = "test.c";
    loc.line = 42;
    loc.column = 5;

    const issue = Issue{
        .kind = .buffer_overflow,
        .message = "Buffer overflow detected",
        .location = loc,
        .severity = .high,
        .confidence = 0.95,
        .ffi_boundary = null,
        .trace = null,
        .owned = false,
    };

    const json = try output.generate(&[_]Issue{issue});
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "buffer_overflow") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "test.c") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"startLine\":42") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"startColumn\":5") != null);
}

test "SarifOutput - CWE taxonomy" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    const issue = Issue{
        .kind = .command_injection,
        .message = "Command injection",
        .location = Location.init("test"),
        .severity = .critical,
        .confidence = 1.0,
        .ffi_boundary = null,
        .trace = null,
        .owned = false,
    };

    const json = try output.generate(&[_]Issue{issue});
    defer std.testing.allocator.free(json);

    // CWE-78 is for command injection
    try std.testing.expect(std.mem.indexOf(u8, json, "CWE-78") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"taxonomies\"") != null);
}

test "SarifOutput - code flows" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    var trace = [_]TraceEntry{
        TraceEntry.init("Pointer allocated here"),
        TraceEntry.init("Pointer passed to function"),
        TraceEntry.init("Pointer freed here"),
    };

    const issue = Issue{
        .kind = .double_free,
        .message = "Double free detected",
        .location = Location.init("test_func"),
        .severity = .high,
        .confidence = 0.9,
        .ffi_boundary = null,
        .trace = &trace,
        .owned = false,
    };

    const json = try output.generate(&[_]Issue{issue});
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"codeFlows\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"threadFlows\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Pointer allocated here") != null);
}

test "SarifOutput - confidence property" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    const issue = Issue{
        .kind = .use_after_free,
        .message = "Use after free",
        .location = Location.init("test"),
        .severity = .high,
        .confidence = 0.75,
        .ffi_boundary = null,
        .trace = null,
        .owned = false,
    };

    const json = try output.generate(&[_]Issue{issue});
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"confidence\":0.75") != null);
}

test "SarifOutput - severity mapping" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    const issues = [_]Issue{
        .{ .kind = .unknown, .message = "Low", .location = Location.init("test"), .severity = .low, .confidence = 0.5, .ffi_boundary = null, .trace = null, .owned = false },
        .{ .kind = .unknown, .message = "Medium", .location = Location.init("test"), .severity = .medium, .confidence = 0.7, .ffi_boundary = null, .trace = null, .owned = false },
        .{ .kind = .unknown, .message = "High", .location = Location.init("test"), .severity = .high, .confidence = 0.9, .ffi_boundary = null, .trace = null, .owned = false },
        .{ .kind = .unknown, .message = "Critical", .location = Location.init("test"), .severity = .critical, .confidence = 1.0, .ffi_boundary = null, .trace = null, .owned = false },
    };

    const json = try output.generate(&issues);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"note\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"warning\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"error\"") != null);
}

test "SarifOutput - write to file" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    const issue = Issue{
        .kind = .buffer_overflow,
        .message = "Test issue",
        .location = Location.init("test_func"),
        .severity = .high,
        .confidence = 1.0,
        .ffi_boundary = null,
        .trace = null,
        .owned = false,
    };

    const temp_file = "test_output.sarif";
    defer {
        std.fs.cwd().deleteFile(temp_file) catch {};
    }

    try output.writeToFile(temp_file, &[_]Issue{issue});

    const file = try std.fs.cwd().openFile(temp_file, .{});
    defer file.close();

    const content = try file.readToEndAlloc(std.testing.allocator, 4096);
    defer std.testing.allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "buffer_overflow") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"version\":\"2.1.0\"") != null);
}

test "writeEscapedString - special characters" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try writeEscapedString(buffer.writer(), "Hello \"World\"\n\t\\Test");
    try std.testing.expectEqualStrings("Hello \\\"World\\\"\\n\\t\\\\Test", buffer.items);
}
