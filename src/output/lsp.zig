//! LSP Output Module
//!
//! This module provides LSP (Language Server Protocol) diagnostic conversion,
//! which is used for IDE integration with editors like VS Code, Vim, etc.
//!
//! LSP Specification: https://microsoft.github.io/language-server-protocol/

const std = @import("std");
const Allocator = std.mem.Allocator;

const Diagnostic = @import("../diag/aggregator.zig").Diagnostic;
const DiagnosticKind = @import("../diag/aggregator.zig").DiagnosticKind;
const Severity = @import("../diag/aggregator.zig").Severity;

/// LSP Severity
pub const LSPSeverity = enum(i32) {
    Error = 1,
    warning = 2,
    information = 3,
    hint = 4,
};

/// LSP Position
pub const Position = struct {
    /// Line position in a document (0-indexed)
    line: u32,
    /// Character offset on a line in a document (0-indexed)
    character: u32,
};

/// LSP Range
pub const Range = struct {
    /// The range's start position
    start: Position,
    /// The range's end position
    end: Position,
};

/// LSP Location
pub const Location = struct {
    uri: []const u8,
    range: Range,
};

/// LSP Diagnostic
pub const LSPDiagnostic = struct {
    /// The range at which the message applies
    range: Range,
    /// The diagnostic's severity
    severity: LSPSeverity,
    /// The diagnostic's code
    code: ?[]const u8 = null,
    /// A human-readable string describing the source of this diagnostic
    source: []const u8 = "OmniScope",
    /// The diagnostic's message
    message: []const u8,
    /// Additional metadata about the diagnostic
    tags: ?[]const DiagnosticTag = null,
    /// The diagnostic's related information
    related_information: ?[]const DiagnosticRelatedInformation = null,
};

/// LSP Diagnostic Tag
pub const DiagnosticTag = enum(i32) {
    /// Unused or unnecessary code
    unnecessary = 1,
    /// Deprecated or obsolete code
    deprecated = 2,
};

/// LSP Diagnostic Related Information
pub const DiagnosticRelatedInformation = struct {
    /// The location of this related diagnostic information
    location: Location,
    /// The message of this related diagnostic information
    message: []const u8,
};

/// File Map for LSP location conversion
///
/// This maps location IDs to file URIs and line/column information
pub const FileMap = struct {
    allocator: Allocator,
    entries: std.AutoHashMap(u32, FileMapEntry),

    const FileMapEntry = struct {
        uri: []const u8,
        line: u32,
        column: u32,
    };

    /// Create a new file map
    pub fn init(allocator: Allocator) FileMap {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(u32, FileMapEntry).init(allocator),
        };
    }

    /// Deinitialize the file map
    pub fn deinit(self: *FileMap) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.uri);
        }
        self.entries.deinit();
    }

    /// Add an entry to the file map
    ///
    /// Parameters:
    ///   - loc_id: Location ID
    ///   - uri: File URI
    ///   - line: Line number (0-indexed)
    ///   - column: Column number (0-indexed)
    pub fn add(self: *FileMap, loc_id: u32, uri: []const u8, line: u32, column: u32) !void {
        const uri_copy = try self.allocator.dupe(u8, uri);
        const entry = FileMapEntry{
            .uri = uri_copy,
            .line = line,
            .column = column,
        };
        try self.entries.put(loc_id, entry);
    }

    /// Get an entry from the file map
    ///
    /// Parameters:
    ///   - loc_id: Location ID
    ///
    /// Returns:
    ///   - FileMapEntry if found, null otherwise
    pub fn get(self: *const FileMap, loc_id: u32) ?FileMapEntry {
        return self.entries.get(loc_id);
    }
};

/// LSP Output
pub const LSPOutput = struct {
    allocator: Allocator,
    source_name: []const u8,

    /// Create a new LSP output instance
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///   - source_name: Name of the analysis tool
    pub fn init(allocator: Allocator, source_name: []const u8) LSPOutput {
        return .{
            .allocator = allocator,
            .source_name = source_name,
        };
    }

    /// Convert a diagnostic to LSP format
    ///
    /// Parameters:
    ///   - diag: Diagnostic to convert
    ///   - file_map: File map for location conversion
    ///
    /// Returns:
    ///   - LSP diagnostic
    pub fn convertDiagnostic(
        self: *LSPOutput,
        diag: Diagnostic,
        file_map: FileMap,
    ) !LSPDiagnostic {
        const severity = self.severityToLSP(diag.severity);
        const range = self.locationToRange(diag.loc, file_map);
        const code = self.diagnosticKindToCode(diag.kind);

        return LSPDiagnostic{
            .range = range,
            .severity = severity,
            .code = code,
            .source = self.source_name,
            .message = try self.allocator.dupe(u8, diag.message),
            .tags = null,
            .related_information = null,
        };
    }

    /// Convert multiple diagnostics to LSP format
    ///
    /// Parameters:
    ///   - diagnostics: Array of diagnostics to convert
    ///   - file_map: File map for location conversion
    ///
    /// Returns:
    ///   - Array of LSP diagnostics
    pub fn convertDiagnostics(
        self: *LSPOutput,
        diagnostics: []Diagnostic,
        file_map: FileMap,
    ) ![]LSPDiagnostic {
        const lsp_diagnostics = try self.allocator.alloc(LSPDiagnostic, diagnostics.len);

        for (diagnostics, 0..) |diag, i| {
            lsp_diagnostics[i] = try self.convertDiagnostic(diag, file_map);
        }

        return lsp_diagnostics;
    }

    /// Convert severity to LSP severity
    fn severityToLSP(self: *LSPOutput, severity: Severity) LSPSeverity {
        _ = self;

        return switch (severity) {
            .err => .Error,
            .warning => .warning,
            .info => .information,
        };
    }

    /// Convert location ID to LSP range
    fn locationToRange(self: *LSPOutput, loc_id: u32, file_map: FileMap) Range {
        _ = self;

        if (file_map.get(loc_id)) |entry| {
            return Range{
                .start = Position{
                    .line = entry.line,
                    .character = entry.column,
                },
                .end = Position{
                    .line = entry.line,
                    .character = entry.column + 1, // Assume single character range
                },
            };
        }

        // Default range if location not found
        return Range{
            .start = Position{
                .line = loc_id,
                .character = 0,
            },
            .end = Position{
                .line = loc_id,
                .character = 1,
            },
        };
    }

    /// Convert diagnostic kind to LSP code
    fn diagnosticKindToCode(self: *LSPOutput, kind: DiagnosticKind) ?[]const u8 {
        _ = self;

        return switch (kind) {
            .static_issue => "static-issue",
            .runtime_issue => "runtime-issue",
            .anomaly => "anomaly",
            .performance => "performance-issue",
            .security => "security-issue",
        };
    }

    /// Free LSP diagnostics
    pub fn freeDiagnostics(self: *LSPOutput, diagnostics: []LSPDiagnostic) void {
        for (diagnostics) |diag| {
            if (diag.message.len > 0) {
                self.allocator.free(diag.message);
            }
            if (diag.code) |code| {
                self.allocator.free(code);
            }
        }
        self.allocator.free(diagnostics);
    }
};

test "LSPOutput - init" {
    const output = LSPOutput.init(std.testing.allocator, "OmniScope");
    try std.testing.expectEqualStrings("OmniScope", output.source_name);
}

test "LSPOutput - severity to LSP" {
    const output = LSPOutput.init(std.testing.allocator, "OmniScope");

    try std.testing.expectEqual(LSPSeverity.Error, output.severityToLSP(.err));
    try std.testing.expectEqual(LSPSeverity.warning, output.severityToLSP(.warning));
    try std.testing.expectEqual(LSPSeverity.information, output.severityToLSP(.info));
}

test "LSPOutput - diagnostic kind to code" {
    const output = LSPOutput.init(std.testing.allocator, "OmniScope");

    try std.testing.expectEqualStrings("static-issue", output.diagnosticKindToCode(.static_issue).?);
    try std.testing.expectEqualStrings("runtime-issue", output.diagnosticKindToCode(.runtime_issue).?);
    try std.testing.expectEqualStrings("anomaly", output.diagnosticKindToCode(.anomaly).?);
    try std.testing.expectEqualStrings("performance-issue", output.diagnosticKindToCode(.performance).?);
    try std.testing.expectEqualStrings("security-issue", output.diagnosticKindToCode(.security).?);
}

test "LSPOutput - location to range with file map" {
    const output = LSPOutput.init(std.testing.allocator, "OmniScope");

    var file_map = FileMap.init(std.testing.allocator);
    defer file_map.deinit();

    try file_map.add(42, "file:///test.c", 10, 5);

    const range = output.locationToRange(42, file_map);

    try std.testing.expectEqual(@as(u32, 10), range.start.line);
    try std.testing.expectEqual(@as(u32, 5), range.start.character);
    try std.testing.expectEqual(@as(u32, 10), range.end.line);
    try std.testing.expectEqual(@as(u32, 6), range.end.character);
}

test "LSPOutput - location to range without file map" {
    const output = LSPOutput.init(std.testing.allocator, "OmniScope");

    var file_map = FileMap.init(std.testing.allocator);
    defer file_map.deinit();

    const range = output.locationToRange(42, file_map);

    try std.testing.expectEqual(@as(u32, 42), range.start.line);
    try std.testing.expectEqual(@as(u32, 0), range.start.character);
    try std.testing.expectEqual(@as(u32, 42), range.end.line);
    try std.testing.expectEqual(@as(u32, 1), range.end.character);
}

test "LSPOutput - convert single diagnostic" {
    var output = LSPOutput.init(std.testing.allocator, "OmniScope");

    var file_map = FileMap.init(std.testing.allocator);
    defer file_map.deinit();

    try file_map.add(42, "file:///test.c", 10, 5);

    const diag = Diagnostic{
        .kind = .static_issue,
        .severity = .err,
        .loc = 42,
        .message = "Test error diagnostic",
        .confidence = 1.0,
    };

    const lsp_diag = try output.convertDiagnostic(diag, file_map);
    defer output.allocator.free(lsp_diag.message);
    if (lsp_diag.code) |code| {
        output.allocator.free(code);
    }

    try std.testing.expectEqual(LSPSeverity.Error, lsp_diag.severity);
    try std.testing.expectEqualStrings("Test error diagnostic", lsp_diag.message);
    try std.testing.expectEqualStrings("OmniScope", lsp_diag.source);
}

test "LSPOutput - convert multiple diagnostics" {
    var output = LSPOutput.init(std.testing.allocator, "OmniScope");

    var file_map = FileMap.init(std.testing.allocator);
    defer file_map.deinit();

    try file_map.add(1, "file:///test1.c", 1, 0);
    try file_map.add(2, "file:///test2.c", 2, 0);
    try file_map.add(3, "file:///test3.c", 3, 0);

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

    const lsp_diagnostics = try output.convertDiagnostics(&diagnostics, file_map);
    defer output.freeDiagnostics(lsp_diagnostics);

    try std.testing.expectEqual(@as(usize, 3), lsp_diagnostics.len);
    try std.testing.expectEqual(LSPSeverity.Error, lsp_diagnostics[0].severity);
    try std.testing.expectEqual(LSPSeverity.warning, lsp_diagnostics[1].severity);
    try std.testing.expectEqual(LSPSeverity.information, lsp_diagnostics[2].severity);
}

test "FileMap - init and deinit" {
    var file_map = FileMap.init(std.testing.allocator);
    defer file_map.deinit();

    try std.testing.expectEqual(@as(usize, 0), file_map.entries.count());
}

test "FileMap - add and get" {
    var file_map = FileMap.init(std.testing.allocator);
    defer file_map.deinit();

    try file_map.add(42, "file:///test.c", 10, 5);

    const entry = file_map.get(42).?;
    try std.testing.expectEqualStrings("file:///test.c", entry.uri);
    try std.testing.expectEqual(@as(u32, 10), entry.line);
    try std.testing.expectEqual(@as(u32, 5), entry.column);
}

test "FileMap - get non-existent" {
    var file_map = FileMap.init(std.testing.allocator);
    defer file_map.deinit();

    const entry = file_map.get(999);
    try std.testing.expect(entry == null);
}

test "FileMap - multiple entries" {
    var file_map = FileMap.init(std.testing.allocator);
    defer file_map.deinit();

    try file_map.add(1, "file:///test1.c", 1, 0);
    try file_map.add(2, "file:///test2.c", 2, 0);
    try file_map.add(3, "file:///test3.c", 3, 0);

    try std.testing.expectEqual(@as(usize, 3), file_map.entries.count());

    const entry1 = file_map.get(1).?;
    try std.testing.expectEqualStrings("file:///test1.c", entry1.uri);

    const entry2 = file_map.get(2).?;
    try std.testing.expectEqualStrings("file:///test2.c", entry2.uri);

    const entry3 = file_map.get(3).?;
    try std.testing.expectEqualStrings("file:///test3.c", entry3.uri);
}

test "LSPOutput - free diagnostics" {
    var output = LSPOutput.init(std.testing.allocator, "OmniScope");

    var file_map = FileMap.init(std.testing.allocator);
    defer file_map.deinit();

    try file_map.add(1, "file:///test.c", 1, 0);

    const diagnostics = [_]Diagnostic{
        .{
            .kind = .static_issue,
            .severity = .err,
            .loc = 1,
            .message = "Test",
            .confidence = 1.0,
        },
    };

    const lsp_diagnostics = try output.convertDiagnostics(&diagnostics, file_map);
    output.freeDiagnostics(lsp_diagnostics);

    // Should not crash
}

test "LSPOutput - all diagnostic kinds" {
    var output = LSPOutput.init(std.testing.allocator, "OmniScope");

    var file_map = FileMap.init(std.testing.allocator);
    defer file_map.deinit();

    try file_map.add(1, "file:///test.c", 1, 0);

    const kinds = [_]DiagnosticKind{
        .static_issue,
        .runtime_issue,
        .anomaly,
        .performance,
        .security,
    };

    inline for (kinds) |kind| {
        const diag = Diagnostic{
            .kind = kind,
            .severity = .err,
            .loc = 1,
            .message = "Test",
            .confidence = 1.0,
        };

        const lsp_diag = try output.convertDiagnostic(diag, file_map);
        defer output.allocator.free(lsp_diag.message);
        if (lsp_diag.code) |code| {
            output.allocator.free(code);
        }

        try std.testing.expect(lsp_diag.code != null);
    }
}
