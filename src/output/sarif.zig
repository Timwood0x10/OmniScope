//! SARIF Output Module
//!
//! This module generates SARIF (Static Analysis Results Interchange Format) output,
//! which is used for IDE integration and standardized reporting.
//!
//! SARIF version: 2.1.0
//! Specification: https://sarifweb.azurewebsites.net/

const std = @import("std");
const Allocator = std.mem.Allocator;

const Diagnostic = @import("../diag/aggregator.zig").Diagnostic;
const DiagnosticKind = @import("../diag/aggregator.zig").DiagnosticKind;
const Severity = @import("../diag/aggregator.zig").Severity;

/// SARIF Output
pub const SarifOutput = struct {
    allocator: Allocator,
    version: []const u8,
    tool_name: []const u8,
    tool_version: []const u8,

    /// Create a new SARIF output instance
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///   - tool_name: Name of the analysis tool
    ///   - tool_version: Version of the analysis tool
    pub fn init(allocator: Allocator, tool_name: []const u8, tool_version: []const u8) SarifOutput {
        return .{
            .allocator = allocator,
            .version = "2.1.0",
            .tool_name = tool_name,
            .tool_version = tool_version,
        };
    }

    /// Generate SARIF output from diagnostics
    ///
    /// Parameters:
    ///   - diagnostics: Array of diagnostics to convert
    ///
    /// Returns:
    ///   - JSON string in SARIF format
    pub fn generate(self: *SarifOutput, diagnostics: []Diagnostic) ![]const u8 {
        // Build SARIF structure
        var log = SarifLog{
            .version = self.version,
            .schema = "https://json.schemastore.org/sarif-2.1.0.json",
            .runs = try self.allocator.alloc(SarifRun, 1),
        };

        // Build run
        log.runs[0] = SarifRun{
            .tool = SarifTool{
                .driver = SarifToolDriver{
                    .name = self.tool_name,
                    .version = self.tool_version,
                    .information_uri = "https://github.com/omniscope/omniscope",
                    .rules = &[_]SarifRule{},
                },
            },
            .results = try self.allocator.alloc(SarifResult, diagnostics.len),
        };

        // Convert diagnostics to SARIF results
        for (diagnostics, 0..) |diag, i| {
            log.runs[0].results[i] = try self.diagnosticToResult(diag);
        }

        // Serialize to JSON
        const json = try std.json.stringifyAlloc(self.allocator, log, .{
            .emit_null_optional_fields = false,
        });

        return json;
    }

    /// Write SARIF output to a file
    ///
    /// Parameters:
    ///   - path: File path to write to
    ///   - diagnostics: Array of diagnostics to convert
    pub fn writeToFile(self: *SarifOutput, path: []const u8, diagnostics: []Diagnostic) !void {
        const json = try self.generate(diagnostics);
        defer self.allocator.free(json);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(json);
    }

    /// Convert a diagnostic to a SARIF result
    fn diagnosticToResult(self: *SarifOutput, diag: Diagnostic) !SarifResult {
        const level = self.severityToLevel(diag.severity);
        const kind = self.diagnosticKindToKind(diag.kind);

        return SarifResult{
            .rule_id = try self.getRuleId(diag.kind),
            .level = level,
            .kind = kind,
            .message = SarifMessage{
                .text = try self.allocator.dupe(u8, diag.message),
            },
            .locations = &[_]SarifLocation{
                .{
                    .physical_location = SarifPhysicalLocation{
                        .artifact_location = SarifArtifactLocation{
                            .uri = "unknown", // TODO: Map location ID to file URI
                        },
                        .region = SarifRegion{
                            .start_line = @intCast(diag.loc),
                        },
                    },
                },
            },
        };
    }

    /// Convert severity to SARIF level
    fn severityToLevel(self: *SarifOutput, severity: Severity) []const u8 {
        _ = self;

        return switch (severity) {
            .err => "error",
            .warning => "warning",
            .info => "note",
        };
    }

    /// Convert diagnostic kind to SARIF kind
    fn diagnosticKindToKind(self: *SarifOutput, kind: DiagnosticKind) []const u8 {
        _ = self;

        return switch (kind) {
            .static_issue => "fail",
            .runtime_issue => "fail",
            .anomaly => "fail",
            .performance => "review",
            .security => "fail",
        };
    }

    /// Get rule ID for a diagnostic kind
    fn getRuleId(self: *SarifOutput, kind: DiagnosticKind) ![]const u8 {
        _ = self;

        return switch (kind) {
            .static_issue => "static-issue",
            .runtime_issue => "runtime-issue",
            .anomaly => "anomaly",
            .performance => "performance-issue",
            .security => "security-issue",
        };
    }
};

/// SARIF Log (root object)
pub const SarifLog = struct {
    version: []const u8,
    schema: []const u8,
    runs: []SarifRun,
};

/// SARIF Run
pub const SarifRun = struct {
    tool: SarifTool,
    results: []SarifResult,
};

/// SARIF Tool
pub const SarifTool = struct {
    driver: SarifToolDriver,
};

/// SARIF Tool Driver
pub const SarifToolDriver = struct {
    name: []const u8,
    version: []const u8,
    information_uri: []const u8,
    rules: []const SarifRule,
};

/// SARIF Rule
pub const SarifRule = struct {
    id: []const u8,
    name: []const u8,
    short_description: ?SarifMessage = null,
    full_description: ?SarifMessage = null,
    help_uri: ?[]const u8 = null,
};

/// SARIF Result
pub const SarifResult = struct {
    rule_id: []const u8,
    level: []const u8,
    kind: []const u8,
    message: SarifMessage,
    locations: []const SarifLocation,
};

/// SARIF Message
pub const SarifMessage = struct {
    text: []const u8,
};

/// SARIF Location
pub const SarifLocation = struct {
    physical_location: SarifPhysicalLocation,
};

/// SARIF Physical Location
pub const SarifPhysicalLocation = struct {
    artifact_location: SarifArtifactLocation,
    region: SarifRegion,
};

/// SARIF Artifact Location
pub const SarifArtifactLocation = struct {
    uri: []const u8,
};

/// SARIF Region
pub const SarifRegion = struct {
    start_line: u32,
    start_column: ?u32 = null,
    end_line: ?u32 = null,
    end_column: ?u32 = null,
};

test "SarifOutput - init" {
    const output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");
    try std.testing.expectEqualStrings("2.1.0", output.version);
    try std.testing.expectEqualStrings("OmniScope", output.tool_name);
    try std.testing.expectEqualStrings("1.0.0", output.tool_version);
}

test "SarifOutput - generate empty diagnostics" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    const diagnostics = [_]Diagnostic{};
    const json = try output.generate(&diagnostics);
    defer std.testing.allocator.free(json);

    // Verify JSON is valid
    const parsed = try std.json.parseFromSlice(SarifLog, std.testing.allocator, json, .{});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.value.runs.len);
    try std.testing.expectEqual(@as(usize, 0), parsed.value.runs[0].results.len);
}

test "SarifOutput - generate single diagnostic" {
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

    // Verify JSON is valid
    const parsed = try std.json.parseFromSlice(SarifLog, std.testing.allocator, json, .{});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.value.runs.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.runs[0].results.len);

    const result = parsed.value.runs[0].results[0];
    try std.testing.expectEqualStrings("error", result.level);
    try std.testing.expectEqualStrings("Test error diagnostic", result.message.text);
}

test "SarifOutput - generate multiple diagnostics" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    const diagnostics = [_]Diagnostic{
        .{
            .kind = .static_issue,
            .severity = .err,
            .loc = 1,
            .message = "Error 1",
            .confidence = 1.0,
        },
        .{
            .kind = .runtime_issue,
            .severity = .warning,
            .loc = 2,
            .message = "Warning 1",
            .confidence = 0.8,
        },
        .{
            .kind = .anomaly,
            .severity = .info,
            .loc = 3,
            .message = "Info 1",
            .confidence = 0.5,
        },
    };

    const json = try output.generate(&diagnostics);
    defer std.testing.allocator.free(json);

    // Verify JSON is valid
    const parsed = try std.json.parseFromSlice(SarifLog, std.testing.allocator, json, .{});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.value.runs.len);
    try std.testing.expectEqual(@as(usize, 3), parsed.value.runs[0].results.len);
}

test "SarifOutput - severity to level conversion" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    try std.testing.expectEqualStrings("error", output.severityToLevel(.err));
    try std.testing.expectEqualStrings("warning", output.severityToLevel(.warning));
    try std.testing.expectEqualStrings("note", output.severityToLevel(.info));
}

test "SarifOutput - diagnostic kind to kind conversion" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    try std.testing.expectEqualStrings("fail", output.diagnosticKindToKind(.static_issue));
    try std.testing.expectEqualStrings("fail", output.diagnosticKindToKind(.runtime_issue));
    try std.testing.expectEqualStrings("fail", output.diagnosticKindToKind(.anomaly));
    try std.testing.expectEqualStrings("review", output.diagnosticKindToKind(.performance));
    try std.testing.expectEqualStrings("fail", output.diagnosticKindToKind(.security));
}

test "SarifOutput - get rule id" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    try std.testing.expectEqualStrings("static-issue", try output.getRuleId(.static_issue));
    try std.testing.expectEqualStrings("runtime-issue", try output.getRuleId(.runtime_issue));
    try std.testing.expectEqualStrings("anomaly", try output.getRuleId(.anomaly));
    try std.testing.expectEqualStrings("performance-issue", try output.getRuleId(.performance));
    try std.testing.expectEqualStrings("security-issue", try output.getRuleId(.security));
}

test "SarifOutput - write to file" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    const diagnostics = [_]Diagnostic{
        .{
            .kind = .static_issue,
            .severity = .err,
            .loc = 42,
            .message = "Test error diagnostic",
            .confidence": 1.0,
        },
    };

    // Write to temporary file
    const temp_file = "test_output.sarif";
    defer {
        std.fs.cwd().deleteFile(temp_file) catch {};
    }

    try output.writeToFile(temp_file, &diagnostics);

    // Verify file exists
    try std.testing.expect(std.fs.cwd().openFile(temp_file, .{}) != null);
}

test "SarifOutput - SARIF version" {
    const output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");
    try std.testing.expectEqualStrings("2.1.0", output.version);
}

test "SarifOutput - SARIF schema" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    const diagnostics = [_]Diagnostic{};
    const json = try output.generate(&diagnostics);
    defer std.testing.allocator.free(json);

    // Verify JSON is valid
    const parsed = try std.json.parseFromSlice(SarifLog, std.testing.allocator, json, .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings(
        "https://json.schemastore.org/sarif-2.1.0.json",
        parsed.value.schema,
    );
}

test "SarifOutput - tool information" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    const diagnostics = [_]Diagnostic{};
    const json = try output.generate(&diagnostics);
    defer std.testing.allocator.free(json);

    // Verify JSON is valid
    const parsed = try std.json.parseFromSlice(SarifLog, std.testing.allocator, json, .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings("OmniScope", parsed.value.runs[0].tool.driver.name);
    try std.testing.expectEqualStrings("1.0.0", parsed.value.runs[0].tool.driver.version);
    try std.testing.expectEqualStrings(
        "https://github.com/omniscope/omniscope",
        parsed.value.runs[0].tool.driver.information_uri,
    );
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
            "message": "Runtime issue",
            "confidence": 0.8,
        },
        .{
            .kind = .anomaly,
            .severity = .info,
            .loc = 3,
            "message": "Anomaly",
            "confidence": 0.5,
        },
        .{
            .kind": .performance,
            .severity": .warning,
            .loc": 4,
            "message": "Performance issue",
            "confidence": 0.7,
        },
        .{
            .kind": .security,
            .severity": .err,
            .loc": 5,
            "message": "Security issue",
            "confidence": 1.0,
        },
    };

    const json = try output.generate(&diagnostics);
    defer std.testing.allocator.free(json);

    // Verify JSON is valid
    const parsed = try std.json.parseFromSlice(SarifLog, std.testing.allocator, json, .{});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 5), parsed.value.runs[0].results.len);
}

test "SarifOutput - location mapping" {
    var output = SarifOutput.init(std.testing.allocator, "OmniScope", "1.0.0");

    const diagnostics = [_]Diagnostic{
        .{
            .kind": .static_issue,
            .severity": .err,
            .loc": 42,
            "message": "Test",
            "confidence": 1.0,
        },
    };

    const json = try output.generate(&diagnostics);
    defer std.testing.allocator.free(json);

    // Verify JSON is valid
    const parsed = try std.json.parseFromSlice(SarifLog, std.testing.allocator, json, .{});
    defer parsed.deinit();

    const result = parsed.value.runs[0].results[0];
    try std.testing.expectEqual(@as(usize, 1), result.locations.len);
    try std.testing.expectEqual(@as(u32, 42), result.locations[0].physical_location.region.start_line);
}