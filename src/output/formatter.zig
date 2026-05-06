//! Output Formatters
//!
//! Provides formatting for analysis results in various formats (JSON, SARIF, text).

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Output format types
pub const OutputFormat = enum {
    /// Plain text format
    text,
    /// JSON format
    json,
    /// SARIF (Static Analysis Results Interchange Format) v2.1.0
    sarif,
};

/// Vulnerability information
pub const Vulnerability = struct {
    /// Unique vulnerability ID
    id: u32,
    /// Vulnerability type (e.g., "command_injection", "sql_injection")
    vuln_type: []const u8,
    /// Severity level (e.g., "critical", "high", "medium", "low")
    severity: []const u8,
    /// Detailed description of the vulnerability
    description: []const u8,
    /// Source location (function/file where vulnerability originates)
    source_location: ?[]const u8,
    /// Sink location (function/file where vulnerability manifests)
    sink_location: ?[]const u8,
    /// CWE ID
    cwe_id: u32,
    /// Line number in source file (if available)
    line: ?u32,
    /// Column number in source file (if available)
    column: ?u32,
};

/// Analysis result summary
pub const AnalysisResult = struct {
    /// List of detected vulnerabilities
    vulnerabilities: []const Vulnerability,
    /// Total number of files analyzed
    total_files: u32 = 0,
    /// Total number of functions analyzed
    total_functions: u32 = 0,
    /// Number of FFI matches found
    ffi_matches: u32 = 0,
    /// Analysis timestamp (Unix timestamp)
    timestamp: u64 = 0,

    /// Initialize AnalysisResult with current timestamp
    pub fn init(allocator: Allocator, vulns: []const Vulnerability) !AnalysisResult {
        _ = allocator;
        const now = std.time.timestamp();
        return .{
            .vulnerabilities = vulns,
            .timestamp = @as(u64, @intCast(now)),
        };
    }

    /// Free allocated resources (no-op for simplified implementation)
    pub fn deinit(self: *AnalysisResult, allocator: Allocator) void {
        _ = self;
        _ = allocator;
        // No-op: vulnerabilities are borrowed references
    }
};

/// Output formatter for analysis results
pub const Formatter = struct {
    allocator: Allocator,

    /// Initialize formatter
    pub fn init(allocator: Allocator) Formatter {
        return .{ .allocator = allocator };
    }

    /// Format analysis result in specified format
    pub fn format(self: *Formatter, fmt: OutputFormat, result: AnalysisResult) ![]u8 {
        return switch (fmt) {
            .text => try self.formatText(result),
            .json => try self.formatJson(result),
            .sarif => try self.formatSarif(result),
        };
    }

    /// Format result as plain text
    fn formatText(self: *Formatter, result: AnalysisResult) ![]u8 {
        var buffer = std.ArrayList(u8).initCapacity(self.allocator, 4096) catch return error.OutOfMemory;
        defer buffer.deinit(self.allocator);

        try buffer.appendSlice(self.allocator, "=== OmniScope Analysis Results ===\n\n");
        try buffer.writer(self.allocator).print("Analysis Summary:\n", .{});
        try buffer.writer(self.allocator).print("  Files analyzed: {d}\n", .{result.total_files});
        try buffer.writer(self.allocator).print("  Functions analyzed: {d}\n", .{result.total_functions});
        try buffer.writer(self.allocator).print("  FFI matches: {d}\n", .{result.ffi_matches});
        try buffer.writer(self.allocator).print("  Vulnerabilities found: {d}\n\n", .{result.vulnerabilities.len});

        if (result.vulnerabilities.len == 0) {
            try buffer.appendSlice(self.allocator, "No vulnerabilities detected.\n");
        } else {
            try buffer.appendSlice(self.allocator, "Vulnerabilities:\n");
            for (result.vulnerabilities, 0..) |vuln, i| {
                try buffer.writer(self.allocator).print("\n  [{d}] {s}\n", .{ i + 1, vuln.vuln_type });
                try buffer.writer(self.allocator).print("      ID: VULN-{d}\n", .{vuln.id});
                try buffer.writer(self.allocator).print("      Severity: {s}\n", .{vuln.severity});
                try buffer.writer(self.allocator).print("      CWE: CWE-{d}\n", .{vuln.cwe_id});
                try buffer.writer(self.allocator).print("      Description: {s}\n", .{vuln.description});
                if (vuln.source_location) |loc| {
                    try buffer.writer(self.allocator).print("      Source: {s}\n", .{loc});
                }
                if (vuln.sink_location) |loc| {
                    try buffer.writer(self.allocator).print("      Sink: {s}\n", .{loc});
                }
                if (vuln.line) |line| {
                    try buffer.writer(self.allocator).print("      Location: Line {d}", .{line});
                    if (vuln.column) |col| {
                        try buffer.writer(self.allocator).print(", Column {d}", .{col});
                    }
                    try buffer.writer(self.allocator).print("\n", .{});
                }
            }
        }

        return buffer.toOwnedSlice(self.allocator);
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
                        try writer.print("\\u{x:0>4}", .{c});
                    } else {
                        try writer.writeByte(c);
                    }
                },
            }
        }
    }

    /// Format result as JSON
    fn formatJson(self: *Formatter, result: AnalysisResult) ![]u8 {
        var buffer = std.ArrayList(u8).initCapacity(self.allocator, 8192) catch return error.OutOfMemory;
        defer buffer.deinit(self.allocator);

        try buffer.appendSlice(self.allocator, "{\n");
        try buffer.writer(self.allocator).print("  \"version\": \"1.0.0\",\n", .{});
        try buffer.writer(self.allocator).print("  \"tool\": \"OmniScope\",\n", .{});
        try buffer.writer(self.allocator).print("  \"timestamp\": {d},\n", .{result.timestamp});
        try buffer.appendSlice(self.allocator, "  \"summary\": {\n");
        try buffer.writer(self.allocator).print("    \"total_files\": {d},\n", .{result.total_files});
        try buffer.writer(self.allocator).print("    \"total_functions\": {d},\n", .{result.total_functions});
        try buffer.writer(self.allocator).print("    \"ffi_matches\": {d},\n", .{result.ffi_matches});
        try buffer.writer(self.allocator).print("    \"vulnerabilities_found\": {d}\n", .{result.vulnerabilities.len});
        try buffer.appendSlice(self.allocator, "  },\n");
        try buffer.appendSlice(self.allocator, "  \"vulnerabilities\": [\n");

        for (result.vulnerabilities, 0..) |vuln, i| {
            if (i > 0) try buffer.appendSlice(self.allocator, ",\n");
            try buffer.appendSlice(self.allocator, "    {\n");
            try buffer.writer(self.allocator).print("      \"id\": \"VULN-{d}\",\n", .{vuln.id});
            try buffer.appendSlice(self.allocator, "      \"type\": \"");
            try self.writeEscapedString(buffer.writer(self.allocator), vuln.vuln_type);
            try buffer.appendSlice(self.allocator, "\",\n");
            try buffer.appendSlice(self.allocator, "      \"severity\": \"");
            try self.writeEscapedString(buffer.writer(self.allocator), vuln.severity);
            try buffer.appendSlice(self.allocator, "\",\n");
            try buffer.writer(self.allocator).print("      \"cwe_id\": {d},\n", .{vuln.cwe_id});
            try buffer.appendSlice(self.allocator, "      \"description\": \"");
            try self.writeEscapedString(buffer.writer(self.allocator), vuln.description);
            try buffer.appendSlice(self.allocator, "\",\n");
            if (vuln.source_location) |loc| {
                try buffer.appendSlice(self.allocator, "      \"source_location\": \"");
                try self.writeEscapedString(buffer.writer(self.allocator), loc);
                try buffer.appendSlice(self.allocator, "\",\n");
            }
            if (vuln.sink_location) |loc| {
                try buffer.appendSlice(self.allocator, ",\n      \"sink_location\": \"");
                try self.writeEscapedString(buffer.writer(self.allocator), loc);
                try buffer.appendSlice(self.allocator, "\"");
            }
            if (vuln.line) |line| {
                try buffer.writer(self.allocator).print(",\n      \"line\": {d}", .{line});
            }
            if (vuln.column) |col| {
                try buffer.writer(self.allocator).print(",\n      \"column\": {d}", .{col});
            }
            try buffer.appendSlice(self.allocator, "\n    }");
        }

        try buffer.appendSlice(self.allocator, "\n  ]\n");
        try buffer.appendSlice(self.allocator, "}\n");

        return buffer.toOwnedSlice(self.allocator);
    }

    /// Format result as SARIF v2.1.0
    fn formatSarif(self: *Formatter, result: AnalysisResult) ![]u8 {
        var buffer = std.ArrayList(u8).initCapacity(self.allocator, 16384) catch return error.OutOfMemory;
        defer buffer.deinit(self.allocator);

        try buffer.appendSlice(self.allocator, "{\n");
        try buffer.appendSlice(self.allocator, "  \"version\": \"2.1.0\",\n");
        try buffer.appendSlice(self.allocator, "  \"$schema\": \"https://json.schemastore.org/sarif-2.1.0.json\",\n");
        try buffer.appendSlice(self.allocator, "  \"runs\": [\n");
        try buffer.appendSlice(self.allocator, "    {\n");
        try buffer.appendSlice(self.allocator, "      \"tool\": {\n");
        try buffer.appendSlice(self.allocator, "        \"driver\": {\n");
        try buffer.appendSlice(self.allocator, "          \"name\": \"OmniScope\",\n");
        try buffer.appendSlice(self.allocator, "          \"version\": \"0.1.8\",\n");
        try buffer.appendSlice(self.allocator, "          \"informationUri\": \"https://github.com/omniscope/omniscope\",\n");
        try buffer.appendSlice(self.allocator, "          \"rules\": []\n");
        try buffer.appendSlice(self.allocator, "        }\n");
        try buffer.appendSlice(self.allocator, "      },\n");
        try buffer.appendSlice(self.allocator, "      \"results\": [\n");

        for (result.vulnerabilities, 0..) |vuln, i| {
            if (i > 0) try buffer.appendSlice(self.allocator, ",\n");
            try buffer.appendSlice(self.allocator, "        {\n");
            try buffer.appendSlice(self.allocator, "          \"ruleId\": \"");
            try self.writeEscapedString(buffer.writer(self.allocator), vuln.vuln_type);
            try buffer.appendSlice(self.allocator, "\",\n");
            try buffer.writer(self.allocator).print("          \"ruleIndex\": {d},\n", .{i});
            try buffer.appendSlice(self.allocator, "          \"level\": \"");
            try self.writeEscapedString(buffer.writer(self.allocator), self.sarifSeverity(vuln.severity));
            try buffer.appendSlice(self.allocator, "\",\n");
            try buffer.appendSlice(self.allocator, "          \"message\": {\n");
            try buffer.writer(self.allocator).print("            \"text\": \"", .{});
            try self.writeEscapedString(buffer.writer(self.allocator), vuln.description);
            try buffer.appendSlice(self.allocator, "\"\n");
            try buffer.appendSlice(self.allocator, "          }");
            if (vuln.source_location != null or vuln.line != null) {
                try buffer.appendSlice(self.allocator, ",\n          \"locations\": [\n");
                try buffer.appendSlice(self.allocator, "            {\n");
                try buffer.appendSlice(self.allocator, "              \"physicalLocation\": {\n");
                try buffer.appendSlice(self.allocator, "                \"artifactLocation\": {\n");
                if (vuln.source_location) |loc| {
                    try buffer.appendSlice(self.allocator, "                  \"uri\": \"");
                    try self.writeEscapedString(buffer.writer(self.allocator), loc);
                    try buffer.appendSlice(self.allocator, "\"\n");
                } else {
                    try buffer.appendSlice(self.allocator, "                  \"uri\": \"unknown\"\n");
                }
                try buffer.appendSlice(self.allocator, "                },\n");
                try buffer.appendSlice(self.allocator, "                \"region\": {\n");
                if (vuln.line) |line| {
                    try buffer.writer(self.allocator).print("                  \"startLine\": {d}\n", .{line});
                } else {
                    try buffer.appendSlice(self.allocator, "                  \"startLine\": 1\n");
                }
                if (vuln.column) |col| {
                    try buffer.writer(self.allocator).print("                  , \"startColumn\": {d}", .{col});
                }
                try buffer.appendSlice(self.allocator, "\n                }\n");
                try buffer.appendSlice(self.allocator, "              }\n");
                try buffer.appendSlice(self.allocator, "            }\n");
                try buffer.appendSlice(self.allocator, "          ]");
            }
            try buffer.appendSlice(self.allocator, "\n        }");
        }

        try buffer.appendSlice(self.allocator, "\n      ]\n");
        try buffer.appendSlice(self.allocator, "    }\n");
        try buffer.appendSlice(self.allocator, "  ]\n");
        try buffer.appendSlice(self.allocator, "}\n");

        return buffer.toOwnedSlice(self.allocator);
    }

    /// Convert severity to SARIF level
    fn sarifSeverity(self: *Formatter, severity: []const u8) []const u8 {
        _ = self;
        if (std.mem.eql(u8, severity, "critical")) return "error";
        if (std.mem.eql(u8, severity, "high")) return "error";
        if (std.mem.eql(u8, severity, "medium")) return "warning";
        return "note";
    }
};

test "Formatter - text format" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);

    const vulns = [_]Vulnerability{
        .{
            .id = 0,
            .vuln_type = "command_injection",
            .severity = "critical",
            .description = "Test vulnerability",
            .source_location = null,
            .sink_location = null,
            .cwe_id = 78,
            .line = null,
            .column = null,
        },
    };

    const result = try AnalysisResult.init(allocator, &vulns);

    const output = try formatter.format(.text, result);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "command_injection") != null);
}

test "Formatter - json format" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);

    const vulns = [_]Vulnerability{
        .{
            .id = 0,
            .vuln_type = "sql_injection",
            .severity = "high",
            .description = "SQL injection vulnerability",
            .source_location = "test.c",
            .sink_location = "mysql_query",
            .cwe_id = 89,
            .line = 42,
            .column = 10,
        },
    };

    const result = try AnalysisResult.init(allocator, &vulns);

    const output = try formatter.format(.json, result);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "\"type\": \"sql_injection\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"cwe_id\": 89") != null);
}

test "Formatter - sarif format" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);

    const vulns = [_]Vulnerability{
        .{
            .id = 0,
            .vuln_type = "xss",
            .severity = "high",
            .description = "Cross-site scripting vulnerability",
            .source_location = "web.c",
            .sink_location = "echo",
            .cwe_id = 79,
            .line = 100,
            .column = 5,
        },
    };

    const result = try AnalysisResult.init(allocator, &vulns);

    const output = try formatter.format(.sarif, result);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "\"version\": \"2.1.0\"") != null);
}

test "Formatter - json complete structure validation" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);

    const vulns = [_]Vulnerability{
        .{
            .id = 1,
            .vuln_type = "command_injection",
            .severity = "critical",
            .description = "Test vulnerability",
            .source_location = "test.rs:10",
            .sink_location = "system()",
            .cwe_id = 78,
            .line = 10,
            .column = 5,
        },
    };

    var result = try AnalysisResult.init(allocator, &vulns);
    result.total_files = 2;
    result.total_functions = 15;
    result.ffi_matches = 3;

    const output = try formatter.format(.json, result);
    defer allocator.free(output);

    // Verify complete JSON structure
    try std.testing.expect(std.mem.indexOf(u8, output, "\"version\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"tool\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"timestamp\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"summary\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"total_files\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"total_functions\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"ffi_matches\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"vulnerabilities_found\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"vulnerabilities\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"id\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"type\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"severity\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"cwe_id\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"description\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"source_location\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"sink_location\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"line\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"column\":") != null);

    // Verify values
    try std.testing.expect(std.mem.indexOf(u8, output, "\"version\": \"1.0.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"tool\": \"OmniScope\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"total_files\": 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"total_functions\": 15") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"ffi_matches\": 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"vulnerabilities_found\": 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"id\": \"VULN-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"type\": \"command_injection\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"severity\": \"critical\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"cwe_id\": 78") != null);
}

test "Formatter - sarif complete structure validation" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);

    const vulns = [_]Vulnerability{
        .{
            .id = 2,
            .vuln_type = "sql_injection",
            .severity = "high",
            .description = "SQL injection vulnerability",
            .source_location = "db.rs:45",
            .sink_location = "mysql_query()",
            .cwe_id = 89,
            .line = 45,
            .column = 12,
        },
    };

    const result = try AnalysisResult.init(allocator, &vulns);

    const output = try formatter.format(.sarif, result);
    defer allocator.free(output);

    // Verify SARIF v2.1.0 required fields
    try std.testing.expect(std.mem.indexOf(u8, output, "\"version\": \"2.1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"$schema\": \"https://json.schemastore.org/sarif-2.1.0.json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"runs\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"tool\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"driver\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"name\": \"OmniScope\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"version\": \"1.0.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"informationUri\": \"https://github.com/omniscope/omniscope\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"results\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"ruleId\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"ruleIndex\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"level\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"message\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"locations\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"physicalLocation\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"artifactLocation\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"uri\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"region\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"startLine\":") != null);

    // Verify specific values
    try std.testing.expect(std.mem.indexOf(u8, output, "\"ruleId\": \"sql_injection\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"ruleIndex\": 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"level\": \"error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"uri\": \"db.rs:45\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"startLine\": 45") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"startColumn\": 12") != null);
}

test "Formatter - multiple vulnerabilities" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);

    const vulns = [_]Vulnerability{
        .{
            .id = 1,
            .vuln_type = "command_injection",
            .severity = "critical",
            .description = "Command injection vulnerability",
            .source_location = "main.rs:10",
            .sink_location = "system()",
            .cwe_id = 78,
            .line = 10,
            .column = 5,
        },
        .{
            .id = 2,
            .vuln_type = "sql_injection",
            .severity = "high",
            .description = "SQL injection vulnerability",
            .source_location = "db.rs:20",
            .sink_location = "mysql_query()",
            .cwe_id = 89,
            .line = 20,
            .column = 10,
        },
        .{
            .id = 3,
            .vuln_type = "xss",
            .severity = "medium",
            .description = "XSS vulnerability",
            .source_location = "web.rs:30",
            .sink_location = "innerHTML",
            .cwe_id = 79,
            .line = 30,
            .column = 15,
        },
    };

    var result = try AnalysisResult.init(allocator, &vulns);
    result.total_files = 3;
    result.total_functions = 50;
    result.ffi_matches = 5;

    // Test JSON output with multiple vulnerabilities
    const json_output = try formatter.format(.json, result);
    defer allocator.free(json_output);

    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"vulnerabilities_found\": 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"id\": \"VULN-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"id\": \"VULN-2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"id\": \"VULN-3\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"type\": \"command_injection\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"type\": \"sql_injection\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"type\": \"xss\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"severity\": \"critical\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"severity\": \"high\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"severity\": \"medium\"") != null);

    // Test SARIF output with multiple vulnerabilities
    const sarif_output = try formatter.format(.sarif, result);
    defer allocator.free(sarif_output);

    try std.testing.expect(std.mem.indexOf(u8, sarif_output, "\"ruleIndex\": 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, sarif_output, "\"ruleIndex\": 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, sarif_output, "\"ruleIndex\": 2") != null);
}

test "Formatter - edge cases: empty vulnerabilities" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);

    const vulns = [_]Vulnerability{};

    var result = try AnalysisResult.init(allocator, &vulns);
    result.total_files = 0;
    result.total_functions = 0;
    result.ffi_matches = 0;

    // Test text output
    const text_output = try formatter.format(.text, result);
    defer allocator.free(text_output);

    try std.testing.expect(std.mem.indexOf(u8, text_output, "Vulnerabilities found: 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_output, "No vulnerabilities detected") != null);

    // Test JSON output
    const json_output = try formatter.format(.json, result);
    defer allocator.free(json_output);

    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"vulnerabilities_found\": 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"vulnerabilities\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "]") != null);

    // Test SARIF output
    const sarif_output = try formatter.format(.sarif, result);
    defer allocator.free(sarif_output);

    try std.testing.expect(std.mem.indexOf(u8, sarif_output, "\"results\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, sarif_output, "]") != null);
}

test "Formatter - edge cases: null locations" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);

    const vulns = [_]Vulnerability{
        .{
            .id = 1,
            .vuln_type = "buffer_overflow",
            .severity = "critical",
            .description = "Buffer overflow without location info",
            .source_location = null,
            .sink_location = null,
            .cwe_id = 120,
            .line = null,
            .column = null,
        },
    };

    const result = try AnalysisResult.init(allocator, &vulns);

    // Test JSON output handles null fields correctly
    const json_output = try formatter.format(.json, result);
    defer allocator.free(json_output);

    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"type\": \"buffer_overflow\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"cwe_id\": 120") != null);

    // Test SARIF output handles null fields correctly
    const sarif_output = try formatter.format(.sarif, result);
    defer allocator.free(sarif_output);

    // When both source_location and line are null, locations are not included
    try std.testing.expect(std.mem.indexOf(u8, sarif_output, "\"ruleId\": \"buffer_overflow\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sarif_output, "\"ruleIndex\": 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, sarif_output, "\"level\": \"error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, sarif_output, "Buffer overflow without location info") != null);
}

test "Formatter - severity level mapping" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);

    // Test critical severity
    const critical_vulns = [_]Vulnerability{
        .{
            .id = 1,
            .vuln_type = "test",
            .severity = "critical",
            .description = "Critical vulnerability",
            .source_location = null,
            .sink_location = null,
            .cwe_id = 1,
            .line = null,
            .column = null,
        },
    };

    var result = try AnalysisResult.init(allocator, &critical_vulns);
    const sarif_critical = try formatter.format(.sarif, result);
    defer allocator.free(sarif_critical);
    try std.testing.expect(std.mem.indexOf(u8, sarif_critical, "\"level\": \"error\"") != null);

    // Test high severity
    const high_vulns = [_]Vulnerability{
        .{
            .id = 2,
            .vuln_type = "test",
            .severity = "high",
            .description = "High vulnerability",
            .source_location = null,
            .sink_location = null,
            .cwe_id = 1,
            .line = null,
            .column = null,
        },
    };

    result = try AnalysisResult.init(allocator, &high_vulns);
    const sarif_high = try formatter.format(.sarif, result);
    defer allocator.free(sarif_high);
    try std.testing.expect(std.mem.indexOf(u8, sarif_high, "\"level\": \"error\"") != null);

    // Test medium severity
    const medium_vulns = [_]Vulnerability{
        .{
            .id = 3,
            .vuln_type = "test",
            .severity = "medium",
            .description = "Medium vulnerability",
            .source_location = null,
            .sink_location = null,
            .cwe_id = 1,
            .line = null,
            .column = null,
        },
    };

    result = try AnalysisResult.init(allocator, &medium_vulns);
    const sarif_medium = try formatter.format(.sarif, result);
    defer allocator.free(sarif_medium);
    try std.testing.expect(std.mem.indexOf(u8, sarif_medium, "\"level\": \"warning\"") != null);

    // Test low severity
    const low_vulns = [_]Vulnerability{
        .{
            .id = 4,
            .vuln_type = "test",
            .severity = "low",
            .description = "Low vulnerability",
            .source_location = null,
            .sink_location = null,
            .cwe_id = 1,
            .line = null,
            .column = null,
        },
    };

    result = try AnalysisResult.init(allocator, &low_vulns);
    const sarif_low = try formatter.format(.sarif, result);
    defer allocator.free(sarif_low);
    try std.testing.expect(std.mem.indexOf(u8, sarif_low, "\"level\": \"note\"") != null);
}

test "Formatter - text format with all fields" {
    const allocator = std.testing.allocator;
    var formatter = Formatter.init(allocator);

    const vulns = [_]Vulnerability{
        .{
            .id = 42,
            .vuln_type = "deserialization",
            .severity = "critical",
            .description = "Unsafe deserialization of untrusted data",
            .source_location = "api/serializer.rs:123",
            .sink_location = "serde_json::from_str()",
            .cwe_id = 502,
            .line = 123,
            .column = 8,
        },
    };

    var result = try AnalysisResult.init(allocator, &vulns);
    result.total_files = 10;
    result.total_functions = 100;
    result.ffi_matches = 15;

    const output = try formatter.format(.text, result);
    defer allocator.free(output);

    // Verify all fields are present in text output
    try std.testing.expect(std.mem.indexOf(u8, output, "=== OmniScope Analysis Results ===") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Analysis Summary:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Files analyzed: 10") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Functions analyzed: 100") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "FFI matches: 15") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Vulnerabilities found: 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[1] deserialization") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ID: VULN-42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Severity: critical") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "CWE: CWE-502") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Description: Unsafe deserialization of untrusted data") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Source: api/serializer.rs:123") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Sink: serde_json::from_str()") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Location: Line 123, Column 8") != null);
}
