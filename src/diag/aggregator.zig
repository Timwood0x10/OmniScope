//! Diagnostic Aggregator
//!
//! This module aggregates diagnostics from various sources
//! (static analysis, runtime verification, merge engine)
//! and produces unified reports.

const std = @import("std");
const MergedEvent = @import("../runtime/merge.zig").MergedEvent;
const Anomaly = @import("../runtime/merge.zig").Anomaly;

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

    /// Create a new diagnostic aggregator
    pub fn init(allocator: std.mem.Allocator) DiagnosticAggregator {
        return .{
            .allocator = allocator,
            .diagnostics = std.ArrayList(Diagnostic).initCapacity(allocator, 0) catch unreachable,
        };
    }

    /// Deinitialize the aggregator
    pub fn deinit(self: *DiagnosticAggregator) void {
        self.clear();
        self.diagnostics.deinit(self.allocator);
    }

    /// Add a diagnostic
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
        severity: Severity,
        allocator: std.mem.Allocator,
    ) ![]Diagnostic {
        var filtered = std.ArrayList(Diagnostic).initCapacity(allocator, 0) catch unreachable;

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
        var filtered = std.ArrayList(Diagnostic).initCapacity(allocator, 0) catch unreachable;

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
            const severity: Severity = if (anomaly.confidence >= 0.8)
                Severity.err
            else if (anomaly.confidence >= 0.5)
                Severity.warning
            else
                Severity.info;

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

/// Severity level
pub const Severity = enum(u8) {
    /// Information only
    info = 0,
    /// Warning
    warning = 1,
    /// Error
    err = 2,
};

/// Diagnostic
pub const Diagnostic = struct {
    /// Diagnostic kind
    kind: DiagnosticKind,
    /// Severity level
    severity: Severity,
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
    var aggregator = DiagnosticAggregator.init(std.testing.allocator);
    defer aggregator.deinit();

    try std.testing.expectEqual(@as(usize, 0), aggregator.diagnostics.items.len);
}

test "DiagnosticAggregator - add diagnostic" {
    var aggregator = DiagnosticAggregator.init(std.testing.allocator);
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
    var aggregator = DiagnosticAggregator.init(std.testing.allocator);
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
    var aggregator = DiagnosticAggregator.init(std.testing.allocator);
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
    var aggregator = DiagnosticAggregator.init(std.testing.allocator);
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
    var aggregator = DiagnosticAggregator.init(std.testing.allocator);
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
    var aggregator = DiagnosticAggregator.init(std.testing.allocator);
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
