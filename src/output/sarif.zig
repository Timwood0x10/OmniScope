//! SARIF Output Format
//!
//! This module implements SARIF (Static Analysis Results Interchange Format) output.
//! SARIF is a standard format for sharing static analysis results.

const std = @import("std");
const Diagnostic = @import("../diag/aggregator.zig").Diagnostic;
const DiagnosticKind = @import("../diag/aggregator.zig").DiagnosticKind;
const Severity = @import("../diag/aggregator.zig").Severity;

/// SARIF output handler
pub const SarifOutput = struct {
    allocator: std.mem.Allocator,
    tool_name: []const u8,
    tool_version: []const u8,

    /// Create a new SARIF output handler
    pub fn init(allocator: std.mem.Allocator, tool_name: []const u8, tool_version: []const u8) SarifOutput {
        return .{
            .allocator = allocator,
            .tool_name = tool_name,
            .tool_version = tool_version,
        };
    }

    /// Generate SARIF JSON from diagnostics
    pub fn generate(self: *SarifOutput, diagnostics: []const Diagnostic) ![]const u8 {
        var json = std.ArrayList(u8).init(self.allocator);
        try json.appendSlice("{\"version\":\"2.1.0\",\"$schema\":\"https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json\",\"runs\":[{");

        try json.appendSlice("\"tool\":{\"driver\":{\"name\":\"");
        try json.appendSlice(self.tool_name);
        try json.appendSlice("\",\"version\":\"");
        try json.appendSlice(self.tool_version);
        try json.appendSlice("\",\"information_uri\":\"https://github.com/omniscope/omniscope\"}},\"results\":[");

        for (diagnostics, 0..) |diag, i| {
            if (i > 0) try json.append(',');

            try json.append('{');
            try json.appendSlice("\"ruleId\":\"");
            try json.appendSlice(@tagName(diag.kind));
            try json.appendSlice("\",\"level\":\"");
            try json.appendSlice(switch (diag.severity) {
                .info => "note",
                .warning => "warning",
                .err => "error",
            });
            try json.appendSlice("\",\"message\":{\"text\":\"");
            try json.appendSlice(diag.message);
            try json.appendSlice("\"},\"locations\":[{\"physicalLocation\":{\"region\":{\"startLine\":");
            try std.fmt.formatInt(diag.loc, 10, .lower, .{}, json.writer());
            try json.appendSlice("}}}]}");
        }

        try json.appendSlice("]}]}");
        return json.toOwnedSlice();
    }

    /// Write SARIF output to file
    pub fn writeToFile(self: *SarifOutput, path: []const u8, diagnostics: []const Diagnostic) !void {
        const json = try self.generate(diagnostics);
        defer self.allocator.free(json);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(json);
    }
};

test "SarifOutput - init" {
    const output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");
    try std.testing.expectEqualStrings("OmniScope", output.tool_name);
    try std.testing.expectEqualStrings("1.0.0", output.tool_version);
}

test "SarifOutput - generate empty" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");
    const diagnostics = [_]Diagnostic{};
    const json = try output.generate(&diagnostics);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"results\":[]") != null);
}

test "SarifOutput - generate single" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    const diagnostics = [_]Diagnostic{
        .{
            .kind = .static_issue,
            .severity = .err,
            .loc = 42,
            .message = "Test error diagnostic",
            .confidence = 1.0,
        },
    };

    const json = try output.generate(&diagnostics);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "static_issue") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "error") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Test error diagnostic") != null);
}

test "SarifOutput - write to file" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    const diagnostics = [_]Diagnostic{
        .{
            .kind = .static_issue,
            .severity = .err,
            .loc = 42,
            .message = "Test error diagnostic",
            .confidence = 1.0,
        },
    };

    const temp_file = "test_output.sarif";
    defer {
        std.fs.cwd().deleteFile(temp_file) catch {};
    }

    try output.writeToFile(temp_file, &diagnostics);

    const file = try std.fs.cwd().openFile(temp_file, .{});
    defer file.close();

    const content = try file.readToEndAlloc(std.testing.allocator, 1024);
    defer std.testing.allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "static_issue") != null);
}

test "SarifOutput - severity mapping" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    const diagnostics = [_]Diagnostic{
        .{
            .kind = .static_issue,
            .severity = .info,
            .loc = 1,
            .message = "Info",
            .confidence = 0.5,
        },
        .{
            .kind = .runtime_issue,
            .severity = .warning,
            .loc = 2,
            .message = "Warning",
            .confidence = 0.8,
        },
        .{
            .kind = .anomaly,
            .severity = .err,
            .loc = 3,
            .message = "Error",
            .confidence = 1.0,
        },
    };

    const json = try output.generate(&diagnostics);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"note\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"warning\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"error\"") != null);
}

test "SarifOutput - all diagnostic kinds" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    const diagnostics = [_]Diagnostic{
        .{
            .kind = .static_issue,
            .severity = .err,
            .loc = 1,
            .message = "Static issue",
            .confidence = 1.0,
        },
        .{
            .kind = .runtime_issue,
            .severity = .warning,
            .loc = 2,
            .message = "Runtime issue",
            .confidence = 0.8,
        },
        .{
            .kind = .anomaly,
            .severity = .info,
            .loc = 3,
            .message = "Anomaly",
            .confidence = 0.5,
        },
        .{
            .kind = .performance,
            .severity = .warning,
            .loc = 4,
            .message = "Performance issue",
            .confidence = 0.7,
        },
        .{
            .kind = .security,
            .severity = .err,
            .loc = 5,
            .message = "Security issue",
            .confidence = 1.0,
        },
    };

    const json = try output.generate(&diagnostics);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "static_issue") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "runtime_issue") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "anomaly") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "performance") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "security") != null);
}

test "SarifOutput - location mapping" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    const diagnostics = [_]Diagnostic{
        .{
            .kind = .static_issue,
            .severity = .err,
            .loc = 42,
            .message = "Test",
            .confidence = 1.0,
        },
    };

    const json = try output.generate(&diagnostics);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "startLine\":42") != null);
}
