//! Diagnostic Aggregator
//!
//! This module aggregates diagnostics from various sources
//! (static analysis, runtime verification, merge engine)
//! and produces unified reports.
//!
//! ## Type Distinction (Important!)
//!
//! This module defines **OutputSeverity** for diagnostic log levels:
//!   - `info` (informational)
//!   - `warning` (potential issue)
//!   - `err` (error condition)
//!
//! This is **DIFFERENT** from `CommonTypes.Severity` (issue severity):
//!   - `.low`, `.medium`, `.high`, `.critical`
//!
//! **Migration Note (2026-05-31):**
//! - Removed deprecated `pub const Severity = OutputSeverity` alias to avoid confusion.
//! - All issue-related code MUST use `CommonTypes.Severity`.
//! - Only diagnostic/logging code should use `OutputSeverity`.

const std = @import("std");

/// Output severity level for diagnostics (logging/display purpose).
///
/// ## Semantic Difference from CommonTypes.Severity
///
/// | OutputSeverity (this file)    | CommonTypes.Severity (issues) |
/// |-------------------------------|-------------------------------|
/// | Log level semantics           | Issue criticality             |
/// | info/warning/err             | low/medium/high/critical      |
/// | For console output formatting | For issue prioritization      |
///
/// Use this for:
/// - Console output formatting
/// - Log message categorization
/// - UI display levels
///
/// Do NOT use for:
/// - Issue severity (use CommonTypes.Severity instead)
/// - Threshold filtering (use Severity.meetsThreshold)
pub const OutputSeverity = enum(u8) {
    /// Information only
    info = 0,
    /// Warning
    warning = 1,
    /// Error
    err = 2,
};

// NOTE: Deprecated alias `pub const Severity = OutputSeverity` removed on 2026-05-31.
// Reason: Caused confusion with CommonTypes.Severity (issue severity levels).
// If you need issue severity, import from common/types.zig instead.

/// Simplified event representation (temporary until runtime/merge.zig is implemented)
pub const MergedEvent = struct {
    tag: u32,
    tid: u32,
    loc: u32,
    arg: u32,
    timestamp: u64,
    confidence: f32,

    pub fn isHighConfidence(self: MergedEvent) bool {
        return self.confidence >= 0.7;
    }
};

/// Simplified anomaly representation
pub const Anomaly = struct {
    loc: u32,
    description: []const u8,
    confidence: f32,
};

/// Free a diagnostics slice returned by getBySeverity or getByKind
///
/// This properly frees both the slice and all messages within.
fn freeDiagnosticsSlice(allocator: std.mem.Allocator, diags: []Diagnostic) void {
    for (diags) |diag| {
        allocator.free(diag.message);
    }
    allocator.free(diags);
}

/// Diagnostic aggregator
pub const DiagnosticAggregator = struct {
    allocator: std.mem.Allocator,
    diagnostics: std.ArrayList(Diagnostic),
    seen_keys: std.AutoHashMap(u64, void),

    /// Create a new diagnostic aggregator
    pub fn init(allocator: std.mem.Allocator) !DiagnosticAggregator {
        return .{
            .allocator = allocator,
            .diagnostics = try std.ArrayList(Diagnostic).initCapacity(allocator, 0),
            .seen_keys = std.AutoHashMap(u64, void).init(allocator),
        };
    }

    /// Deinitialize the aggregator
    pub fn deinit(self: *DiagnosticAggregator) void {
        self.clear();
        self.diagnostics.deinit(self.allocator);
        self.seen_keys.deinit();
    }

    /// Add a diagnostic with cross-pass deduplication
    ///
    /// Uses (function_name + issue_kind) as dedup key to prevent
    /// duplicate reports from different passes detecting the same issue.
    pub fn add(self: *DiagnosticAggregator, diag: Diagnostic) !void {
        const owned_message = try self.allocator.dupe(u8, diag.message);
        try self.diagnostics.append(self.allocator, .{
            .kind = diag.kind,
            .severity = diag.severity,
            .loc = diag.loc,
            .message = owned_message,
            .confidence = diag.confidence,
        });
    }

    /// Add an Issue with cross-pass deduplication and storage.
    ///
    /// Returns `true` if the issue was newly added (not a duplicate), `false` if skipped.
    /// May return error on allocation failure.
    ///
    /// Accepts any struct with at least `.location` and `.kind` fields.
    /// Validates required fields at **compile time** via comptime assertions.
    pub fn addIssue(self: *DiagnosticAggregator, issue: anytype) !bool {
        const T = @TypeOf(issue);

        // Compile-time validation: ensure required fields exist with correct types
        comptime {
            if (!@hasField(T, "location")) {
                @compileError("addIssue requires .location field (struct)");
            }
            if (!@hasField(T, "kind")) {
                @compileError("addIssue requires .kind field (enum)");
            }

            // Validate .kind is an enum type
            const KindType = std.meta.FieldType(T, .kind);
            if (@typeInfo(KindType) != .Enum) {
                @compileError(".kind must be an enum type");
            }

            // Validate .location is a struct type
            const LocType = std.meta.FieldType(T, .location);
            if (@typeInfo(LocType) != .Struct) {
                @compileError(".location must be a struct type");
            }

            // If location has a .function field, validate its type
            if (@hasField(LocType, "function")) {
                const FuncType = std.meta.FieldType(LocType, .function);
                if (FuncType != []const u8) {
                    @compileError(".location.function must be []const u8");
                }
            }
        }

        const LocType = std.meta.FieldType(T, .location);
        const func_name = if (@hasField(LocType, "function"))
            @field(@field(issue, "location"), "function")
        else
            "(unknown)";

        const kind_tag = @tagName(@field(issue, "kind"));

        var hasher = std.hash.Fnv1a_64.init();
        hasher.update(func_name);
        hasher.update(kind_tag);
        const loc = @field(issue, "location");
        if (@hasField(LocType, "file")) {
            if (@field(loc, "file")) |file| hasher.update(file);
        }
        if (@hasField(LocType, "line")) {
            if (@field(loc, "line")) |line| {
                hasher.update(&std.mem.toBytes(line));
            }
        }
        const dedup_key = hasher.final();

        const gop = try self.seen_keys.getOrPut(dedup_key);
        if (gop.found_existing) return false;

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

        // Map issue kind to diagnostic kind (preserve semantic info)
        const diag_kind = mapKindToDiagnostic(kind_tag);

        // Preserve location info when available
        const loc_id: u64 = if (@hasField(@TypeOf(loc), "line"))
            if (@field(loc, "line")) |line| @as(u64, line) else 0
        else
            0;

        try self.add(.{
            .kind = diag_kind,
            .severity = if (conf >= 0.8) .err else if (conf >= 0.5) .warning else .info,
            .loc = loc_id,
            .message = msg,
            .confidence = conf,
        });

        return true;
    }

    fn mapKindToDiagnostic(kind_str: []const u8) DiagnosticKind {
        const security_kinds = [_][]const u8{
            "use_after_free",    "double_free",       "null_dereference",
            "buffer_overflow",   "memory_leak",       "borrow_escape",
            "command_injection", "ffi_unsafe_call",   "integer_overflow",
            "race_condition",    "uninitialized_mem",
        };
        for (security_kinds) |sk| {
            if (std.mem.eql(u8, kind_str, sk)) return .security;
        }
        const perf_kinds = [_][]const u8{ "inefficient_copy", "redundant_alloc" };
        for (perf_kinds) |pk| {
            if (std.mem.eql(u8, kind_str, pk)) return .performance;
        }
        return .static_issue;
    }

    /// Get all diagnostics
    pub fn getAll(self: *const DiagnosticAggregator) []Diagnostic {
        return self.diagnostics.items;
    }

    /// Get diagnostics by severity
    ///
    /// Returns newly allocated slice that caller owns. Caller must free the
    /// returned slice and all messages within.
    pub fn getBySeverity(
        self: *const DiagnosticAggregator,
        severity: OutputSeverity,
        allocator: std.mem.Allocator,
    ) ![]Diagnostic {
        var filtered = try std.ArrayList(Diagnostic).initCapacity(allocator, 0);

        for (self.diagnostics.items) |diag| {
            if (diag.severity == severity) {
                const owned_message = try allocator.dupe(u8, diag.message);
                try filtered.append(allocator, .{
                    .kind = diag.kind,
                    .severity = diag.severity,
                    .loc = diag.loc,
                    .message = owned_message,
                    .confidence = diag.confidence,
                });
            }
        }

        return filtered.toOwnedSlice(allocator);
    }

    /// Get diagnostics by kind
    ///
    /// Returns newly allocated slice that caller owns. Caller must free the
    /// returned slice and all messages within.
    pub fn getByKind(
        self: *const DiagnosticAggregator,
        kind: DiagnosticKind,
        allocator: std.mem.Allocator,
    ) ![]Diagnostic {
        var filtered = try std.ArrayList(Diagnostic).initCapacity(allocator, 0);

        for (self.diagnostics.items) |diag| {
            if (diag.kind == kind) {
                const owned_message = try allocator.dupe(u8, diag.message);
                try filtered.append(allocator, .{
                    .kind = diag.kind,
                    .severity = diag.severity,
                    .loc = diag.loc,
                    .message = owned_message,
                    .confidence = diag.confidence,
                });
            }
        }

        return filtered.toOwnedSlice(allocator);
    }

    /// Aggregate diagnostics from merged events
    pub fn aggregateFromEvents(
        self: *DiagnosticAggregator,
        events: []MergedEvent,
    ) !void {
        for (events) |ev| {
            if (ev.isHighConfidence()) {
                // Generate diagnostic for high-confidence events
                const diag = Diagnostic{
                    .kind = .runtime_issue,
                    .severity = .warning,
                    .loc = ev.loc,
                    .message = try std.fmt.allocPrint(
                        self.allocator,
                        "Runtime event detected at confidence {d:.2}",
                        .{ev.confidence},
                    ),
                    .confidence = ev.confidence,
                };
                try self.diagnostics.append(self.allocator, diag);
            }
        }
    }

    /// Aggregate anomalies
    pub fn aggregateAnomalies(
        self: *DiagnosticAggregator,
        anomalies: []Anomaly,
    ) !void {
        for (anomalies) |anomaly| {
            const severity: OutputSeverity = if (anomaly.confidence >= 0.8)
                OutputSeverity.err
            else if (anomaly.confidence >= 0.5)
                OutputSeverity.warning
            else
                OutputSeverity.info;

            const diag = Diagnostic{
                .kind = .anomaly,
                .severity = severity,
                .loc = anomaly.loc,
                .message = try self.allocator.dupe(u8, anomaly.description),
                .confidence = anomaly.confidence,
            };
            try self.diagnostics.append(self.allocator, diag);
        }
    }

    /// Generate a summary report
    pub fn generateSummary(
        self: *const DiagnosticAggregator,
        allocator: std.mem.Allocator,
    ) !SummaryReport {
        _ = allocator; // Will be used for future expansion
        var error_count: usize = 0;
        var warning_count: usize = 0;
        var info_count: usize = 0;

        for (self.diagnostics.items) |diag| {
            switch (diag.severity) {
                .err => error_count += 1,
                .warning => warning_count += 1,
                .info => info_count += 1,
            }
        }

        return .{
            .total = self.diagnostics.items.len,
            .error_count = error_count,
            .warning_count = warning_count,
            .info_count = info_count,
        };
    }

    /// Clear all diagnostics
    pub fn clear(self: *DiagnosticAggregator) void {
        for (self.diagnostics.items) |diag| {
            self.allocator.free(diag.message);
        }
        self.diagnostics.clearRetainingCapacity();
        self.seen_keys.clearRetainingCapacity();
    }
};

/// Diagnostic kind
pub const DiagnosticKind = enum(u8) {
    /// Static analysis issue
    static_issue,
    /// Runtime issue
    runtime_issue,
    /// Anomaly detected
    anomaly,
    /// Performance issue
    performance,
    /// Security issue
    security,
};

/// Severity level (re-exported from common/types.zig)
/// Use common/types.zig.Severity directly in new code.
/// Diagnostic
pub const Diagnostic = struct {
    /// Diagnostic kind
    kind: DiagnosticKind,
    /// Severity level (OutputSeverity: info/warning/err)
    severity: OutputSeverity,
    /// Location ID
    loc: u32,
    /// Diagnostic message
    message: []const u8,
    /// Confidence score [0.0, 1.0]
    confidence: f32,
};

/// Summary report
pub const SummaryReport = struct {
    /// Total number of diagnostics
    total: usize,
    /// Number of errors
    error_count: usize,
    /// Number of warnings
    warning_count: usize,
    /// Number of info messages
    info_count: usize,
};

test "DiagnosticAggregator - init and deinit" {
    var aggregator = try DiagnosticAggregator.init(std.testing.allocator);
    defer aggregator.deinit();

    try std.testing.expectEqual(@as(usize, 0), aggregator.diagnostics.items.len);
}

test "DiagnosticAggregator - add diagnostic" {
    var aggregator = try DiagnosticAggregator.init(std.testing.allocator);
    defer aggregator.deinit();

    const diag = Diagnostic{
        .kind = .static_issue,
        .severity = .warning,
        .loc = 42,
        .message = "Test diagnostic",
        .confidence = 0.8,
    };

    try aggregator.add(diag);
    try std.testing.expectEqual(@as(usize, 1), aggregator.diagnostics.items.len);
}

test "DiagnosticAggregator - get by severity" {
    var aggregator = try DiagnosticAggregator.init(std.testing.allocator);
    defer aggregator.deinit();

    try aggregator.add(Diagnostic{
        .kind = .static_issue,
        .severity = .err,
        .loc = 1,
        .message = "Error",
        .confidence = 1.0,
    });

    try aggregator.add(Diagnostic{
        .kind = .runtime_issue,
        .severity = .warning,
        .loc = 2,
        .message = "Warning",
        .confidence = 0.8,
    });

    try aggregator.add(Diagnostic{
        .kind = .anomaly,
        .severity = .info,
        .loc = 3,
        .message = "Info",
        .confidence = 0.5,
    });

    const errors = try aggregator.getBySeverity(.err, std.testing.allocator);
    defer freeDiagnosticsSlice(std.testing.allocator, errors);

    try std.testing.expectEqual(@as(usize, 1), errors.len);
}

test "DiagnosticAggregator - get by kind" {
    var aggregator = try DiagnosticAggregator.init(std.testing.allocator);
    defer aggregator.deinit();

    try aggregator.add(Diagnostic{
        .kind = .static_issue,
        .severity = .warning,
        .loc = 1,
        .message = "Static",
        .confidence = 0.8,
    });

    try aggregator.add(Diagnostic{
        .kind = .runtime_issue,
        .severity = .warning,
        .loc = 2,
        .message = "Runtime",
        .confidence = 0.8,
    });

    const static_diags = try aggregator.getByKind(.static_issue, std.testing.allocator);
    defer freeDiagnosticsSlice(std.testing.allocator, static_diags);

    try std.testing.expectEqual(@as(usize, 1), static_diags.len);
}

test "DiagnosticAggregator - aggregate from events" {
    var aggregator = try DiagnosticAggregator.init(std.testing.allocator);
    defer aggregator.deinit();

    var events = [_]MergedEvent{
        .{
            .tag = 1,
            .tid = 1,
            .loc = 1,
            .arg = 1,
            .timestamp = 0,
            .confidence = 0.9, // High confidence
        },
        .{
            .tag = 2,
            .tid = 1,
            .loc = 2,
            .arg = 2,
            .timestamp = 0,
            .confidence = 0.3, // Low confidence
        },
    };

    try aggregator.aggregateFromEvents(&events);

    try std.testing.expectEqual(@as(usize, 1), aggregator.diagnostics.items.len);
}

test "DiagnosticAggregator - generate summary" {
    var aggregator = try DiagnosticAggregator.init(std.testing.allocator);
    defer aggregator.deinit();

    try aggregator.add(Diagnostic{
        .kind = .static_issue,
        .severity = .err,
        .loc = 1,
        .message = "Error",
        .confidence = 1.0,
    });

    try aggregator.add(Diagnostic{
        .kind = .runtime_issue,
        .severity = .warning,
        .loc = 2,
        .message = "Warning",
        .confidence = 0.8,
    });

    try aggregator.add(Diagnostic{
        .kind = .anomaly,
        .severity = .info,
        .loc = 3,
        .message = "Info",
        .confidence = 0.5,
    });

    const summary = try aggregator.generateSummary(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), summary.total);
    try std.testing.expectEqual(@as(usize, 1), summary.error_count);
    try std.testing.expectEqual(@as(usize, 1), summary.warning_count);
    try std.testing.expectEqual(@as(usize, 1), summary.info_count);
}

test "DiagnosticAggregator - clear" {
    var aggregator = try DiagnosticAggregator.init(std.testing.allocator);
    defer aggregator.deinit();

    try aggregator.add(Diagnostic{
        .kind = .static_issue,
        .severity = .warning,
        .loc = 1,
        .message = "Test",
        .confidence = 0.8,
    });

    try std.testing.expectEqual(@as(usize, 1), aggregator.diagnostics.items.len);

    aggregator.clear();

    try std.testing.expectEqual(@as(usize, 0), aggregator.diagnostics.items.len);
}

test "DiagnosticAggregator - multiple diagnostics same severity" {
    var aggregator = try DiagnosticAggregator.init(std.testing.allocator);
    defer aggregator.deinit();

    // Add multiple diagnostics with same severity
    try aggregator.add(Diagnostic{
        .kind = .static_issue,
        .severity = .err,
        .loc = 1,
        .message = "Error 1",
        .confidence = 0.9,
    });

    try aggregator.add(Diagnostic{
        .kind = .runtime_issue,
        .severity = .err,
        .loc = 2,
        .message = "Error 2",
        .confidence = 0.7,
    });

    const errors = try aggregator.getBySeverity(.err, std.testing.allocator);
    defer freeDiagnosticsSlice(std.testing.allocator, errors);
    try std.testing.expectEqual(@as(usize, 2), errors.len);
}

test "DiagnosticAggregator - empty aggregation" {
    var aggregator = try DiagnosticAggregator.init(std.testing.allocator);
    defer aggregator.deinit();

    // Get summary with no diagnostics
    const summary = try aggregator.generateSummary(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), summary.total);
    try std.testing.expectEqual(@as(usize, 0), summary.error_count);
    try std.testing.expectEqual(@as(usize, 0), summary.warning_count);
    try std.testing.expectEqual(@as(usize, 0), summary.info_count);
}

test "DiagnosticAggregator - cross-pass deduplication" {
    var aggregator = try DiagnosticAggregator.init(std.testing.allocator);
    defer aggregator.deinit();

    // Create mock issue with location and kind
    const TestIssue = struct {
        location: struct {
            function: []const u8,
            file: ?[]const u8,
            line: ?u32,
            column: ?u32,
        },
        kind: enum { memory_leak, double_free },
    };

    // First issue should be accepted
    const issue1 = TestIssue{
        .location = .{
            .function = "test_func",
            .file = "test.zig",
            .line = 42,
            .column = null,
        },
        .kind = .memory_leak,
    };
    const result1 = try aggregator.addIssue(issue1);
    try std.testing.expect(result1);

    // Same issue should be rejected (duplicate)
    const issue2 = TestIssue{
        .location = .{
            .function = "test_func",
            .file = "test.zig",
            .line = 42,
            .column = null,
        },
        .kind = .memory_leak,
    };
    const result2 = try aggregator.addIssue(issue2);
    try std.testing.expect(!result2);

    // Different kind should be accepted
    const issue3 = TestIssue{
        .location = .{
            .function = "test_func",
            .file = "test.zig",
            .line = 42,
            .column = null,
        },
        .kind = .double_free,
    };
    const result3 = try aggregator.addIssue(issue3);
    try std.testing.expect(result3);

    // Different function should be accepted
    const issue4 = TestIssue{
        .location = .{
            .function = "other_func",
            .file = "test.zig",
            .line = 42,
            .column = null,
        },
        .kind = .memory_leak,
    };
    const result4 = try aggregator.addIssue(issue4);
    try std.testing.expect(result4);

    // Different line should be accepted
    const issue5 = TestIssue{
        .location = .{
            .function = "test_func",
            .file = "test.zig",
            .line = 100,
            .column = null,
        },
        .kind = .memory_leak,
    };
    const result5 = try aggregator.addIssue(issue5);
    try std.testing.expect(result5);
}

test "DiagnosticAggregator - dedup with null fields" {
    var aggregator = try DiagnosticAggregator.init(std.testing.allocator);
    defer aggregator.deinit();

    const TestIssue = struct {
        location: struct {
            function: []const u8,
            file: ?[]const u8,
            line: ?u32,
            column: ?u32,
        },
        kind: enum { memory_leak },
    };

    // Issue without file/line should still work
    const issue1 = TestIssue{
        .location = .{
            .function = "func_no_loc",
            .file = null,
            .line = null,
            .column = null,
        },
        .kind = .memory_leak,
    };
    const result1 = try aggregator.addIssue(issue1);
    try std.testing.expect(result1);

    // Duplicate without file/line should be rejected
    const issue2 = TestIssue{
        .location = .{
            .function = "func_no_loc",
            .file = null,
            .line = null,
            .column = null,
        },
        .kind = .memory_leak,
    };
    const result2 = try aggregator.addIssue(issue2);
    try std.testing.expect(!result2);
}
