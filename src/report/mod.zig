//! Security Report Module
//!
//! This module generates structured security analysis reports in the format
//! specified by OmniScope's development plan.
//!
//! Output Format:
//! ```text
//! === OmniScope Security Analysis Report ===
//! Timestamp: 2024-01-15 10:30:00
//! Module: examples/ntt.bc
//! Functions: 30 | Edges: 45 | Sources: 3 | Sinks: 7
//!
//! ------------------------------------------------------------------------
//! [CRITICAL] Command Injection Path Detected
//! ------------------------------------------------------------------------
//! Vulnerability ID:   OMI-001
//! Severity:           CRITICAL
//! Confidence:         HIGH (0.92)
//!
//! Path:
//!   [Source]     main() - user input entry
//!     └─> [Tainted] debug_output()
//!          └─> [FFI Boundary: internal → external_unknown]
//!               └─> [Sink] _system() - arbitrary command execution
//!
//! Impact:
//!   - Attacker can execute arbitrary shell commands
//!   - Potential for full system compromise
//! ```

const std = @import("std");

/// Report severity levels
pub const ReportSeverity = enum {
    critical,
    high,
    medium,
    low,
};

/// Step type in a vulnerability path
pub const PathStepType = enum {
    source,
    tainted,
    ffi_boundary,
    sink,
};

/// A single step in a vulnerability path
pub const VulnerabilityPathStep = struct {
    step_type: PathStepType,
    func_name: []const u8,
    description: []const u8,
};

/// A detected vulnerability
pub const Vulnerability = struct {
    id: []const u8,
    severity: ReportSeverity,
    confidence: f32,
    title: []const u8,
    path: []const VulnerabilityPathStep,
    impact: []const []const u8,
    is_cross_language: bool,
    ffi_direction: ?[]const u8,
};

/// Statistics about the analyzed module
pub const ModuleStats = struct {
    function_count: usize,
    edge_count: usize,
    source_count: usize,
    sink_count: usize,
    module_name: []const u8,
};

/// The complete security analysis report
pub const SecurityReport = struct {
    timestamp: i64,
    stats: ModuleStats,
    vulnerabilities: []const Vulnerability,
    total_paths_analyzed: usize,
    ffi_boundaries_crossed: usize,
};

/// Report generator
pub const ReportGenerator = struct {
    allocator: std.mem.Allocator,
    vulnerability_counter: u32,

    pub fn init(allocator: std.mem.Allocator) ReportGenerator {
        return .{
            .allocator = allocator,
            .vulnerability_counter = 0,
        };
    }

    pub fn generate(self: *ReportGenerator, report: SecurityReport) ![]const u8 {
        var output = std.ArrayList(u8).initCapacity(self.allocator, 4096) catch return "";
        errdefer output.deinit(self.allocator);

        try self.writeHeader(&output, report);
        try self.writeVulnerabilities(&output, report);
        try self.writeSummary(&output, report);

        return output.toOwnedSlice(self.allocator);
    }

    fn writeHeader(self: *ReportGenerator, output: *std.ArrayList(u8), report: SecurityReport) !void {
        try output.appendSlice(self.allocator, "=== OmniScope Security Analysis Report ===\n");
        try output.writer(self.allocator).print(
            "Timestamp: {s}\n",
            .{self.formatTimestamp(report.timestamp)},
        );
        try output.writer(self.allocator).print(
            "Module: {s}\n",
            .{report.stats.module_name},
        );
        try output.writer(self.allocator).print(
            "Functions: {d} | Edges: {d} | Sources: {d} | Sinks: {d}\n",
            .{
                report.stats.function_count,
                report.stats.edge_count,
                report.stats.source_count,
                report.stats.sink_count,
            },
        );
        try output.appendSlice(self.allocator, "\n");
    }

    fn writeVulnerabilities(self: *ReportGenerator, output: *std.ArrayList(u8), report: SecurityReport) !void {
        for (report.vulnerabilities) |vuln| {
            try self.writeVulnerabilitySeparator(output, vuln.severity);
            try output.writer(self.allocator).print(
                "Vulnerability ID:   {s}\n",
                .{vuln.id},
            );
            try output.writer(self.allocator).print(
                "Severity:           {s}\n",
                .{@tagName(vuln.severity)},
            );
            try output.writer(self.allocator).print(
                "Confidence:         {s} ({d:.2})\n",
                .{ self.confidenceLabel(vuln.confidence), vuln.confidence },
            );

            try output.appendSlice(self.allocator, "\nPath:\n");
            try self.writePath(output, vuln.path, vuln.ffi_direction);

            if (vuln.impact.len > 0) {
                try output.appendSlice(self.allocator, "\nImpact:\n");
                for (vuln.impact) |impact_line| {
                    try output.writer(self.allocator).print(
                        "  - {s}\n",
                        .{impact_line},
                    );
                }
            }

            if (vuln.is_cross_language) {
                try output.appendSlice(self.allocator, "\nCross-Language: YES");
                if (vuln.ffi_direction) |dir| {
                    try output.writer(self.allocator).print(" ({s})", .{dir});
                }
                try output.appendSlice(self.allocator, "\n");
            }

            try output.appendSlice(self.allocator, "\n");
        }
    }

    fn writeVulnerabilitySeparator(self: *ReportGenerator, output: *std.ArrayList(u8), severity: ReportSeverity) !void {
        const line = "------------------------------------------------------------------------";
        try output.appendSlice(self.allocator, line);
        try output.appendSlice(self.allocator, "\n");
        try output.writer(self.allocator).print(
            "[{s}] {s}\n",
            .{ @tagName(severity).toUpper(), "Vulnerability Detected" },
        );
        try output.appendSlice(self.allocator, line);
        try output.appendSlice(self.allocator, "\n");
    }

    fn writePath(
        self: *ReportGenerator,
        output: *std.ArrayList(u8),
        path: []const VulnerabilityPathStep,
        ffi_direction: ?[]const u8,
    ) !void {
        for (path, 0..) |step, idx| {
            const prefix = if (idx == 0) "  [Source]     " else "    └─> ";
            const step_type_str = switch (step.step_type) {
                .source => "Source",
                .tainted => "Tainted",
                .ffi_boundary => "FFI Boundary",
                .sink => "Sink",
            };

            if (step.step_type == .ffi_boundary) {
                try output.writer(self.allocator).print(
                    "{s}[{s}]{s} - {s}\n",
                    .{ prefix, step_type_str, if (ffi_direction) |d| d else "", step.description },
                );
            } else {
                try output.writer(self.allocator).print(
                    "{s}[{s}] {s} - {s}\n",
                    .{ prefix, step_type_str, step.func_name, step.description },
                );
            }
        }
    }

    fn writeSummary(self: *ReportGenerator, output: *std.ArrayList(u8), report: SecurityReport) !void {
        const line = "------------------------------------------------------------------------";
        try output.appendSlice(self.allocator, line);
        try output.appendSlice(self.allocator, "\n");
        try output.appendSlice(self.allocator, "SUMMARY\n");
        try output.appendSlice(self.allocator, line);
        try output.appendSlice(self.allocator, "\n");

        try output.writer(self.allocator).print(
            "Total Paths Analyzed:  {d}\n",
            .{report.total_paths_analyzed},
        );

        var critical_count: usize = 0;
        var high_count: usize = 0;
        var medium_count: usize = 0;
        var low_count: usize = 0;

        for (report.vulnerabilities) |vuln| {
            switch (vuln.severity) {
                .critical => critical_count += 1,
                .high => high_count += 1,
                .medium => medium_count += 1,
                .low => low_count += 1,
            }
        }

        try output.writer(self.allocator).print(
            "Critical Issues:       {d}\n",
            .{critical_count},
        );
        try output.writer(self.allocator).print(
            "High Issues:          {d}\n",
            .{high_count},
        );
        try output.writer(self.allocator).print(
            "Medium Issues:        {d}\n",
            .{medium_count},
        );
        try output.writer(self.allocator).print(
            "Low Issues:           {d}\n",
            .{low_count},
        );

        try output.appendSlice(self.allocator, "\n");
        try output.writer(self.allocator).print(
            "FFI Boundaries Crossed: {d}\n",
            .{report.ffi_boundaries_crossed},
        );

        if (report.ffi_boundaries_crossed > 0) {
            try output.appendSlice(self.allocator, "Cross-Language Flow:    YES\n");
        } else {
            try output.appendSlice(self.allocator, "Cross-Language Flow:    NO\n");
        }
    }

    fn formatTimestamp(self: *ReportGenerator, timestamp: i64) []const u8 {
        // Convert Unix timestamp to readable format
        // timestamp is in seconds since Unix epoch
        const epoch = std.time.epoch.Epoch{ .seconds = @intCast(timestamp) };
        const year_day = epoch.getYearDay();
        const month_day = year_day.calculateMonthDay();

        const hours_minutes = epoch.getDayMinutes();
        const seconds = epoch.getDaySeconds() % 60;

        // Format: YYYY-MM-DD HH:MM:SS
        const formatted = std.fmt.allocPrint(
            self.allocator,
            "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}",
            .{
                year_day.year,
                month_day.month.numeric(),
                month_day.day_index + 1,
                hours_minutes.hours,
                hours_minutes.minutes,
                seconds,
            },
        ) catch "1970-01-01 00:00:00";

        return formatted;
    }

    fn confidenceLabel(self: *ReportGenerator, confidence: f32) []const u8 {
        _ = self;
        if (confidence >= 0.9) return "HIGH";
        if (confidence >= 0.7) return "MEDIUM";
        return "LOW";
    }

    pub fn createVulnerabilityId(self: *ReportGenerator) []const u8 {
        self.vulnerability_counter += 1;
        return std.fmt.allocPrint(self.allocator, "OMI-{d:0>3}", .{self.vulnerability_counter}) catch "OMI-001";
    }
};

test "ReportGenerator - init" {
    const gen = ReportGenerator.init(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 0), gen.vulnerability_counter);
}

test "ReportGenerator - createVulnerabilityId" {
    var gen = ReportGenerator.init(std.testing.allocator);
    const id1 = gen.createVulnerabilityId();
    const id2 = gen.createVulnerabilityId();
    try std.testing.expectEqualStrings("OMI-001", id1);
    try std.testing.expectEqualStrings("OMI-002", id2);
}

test "ReportSeverity - tagName" {
    try std.testing.expectEqualStrings("critical", @tagName(ReportSeverity.critical));
    try std.testing.expectEqualStrings("high", @tagName(ReportSeverity.high));
}

test "PathStepType - tagName" {
    try std.testing.expectEqualStrings("source", @tagName(PathStepType.source));
    try std.testing.expectEqualStrings("tainted", @tagName(PathStepType.tainted));
    try std.testing.expectEqualStrings("ffi_boundary", @tagName(PathStepType.ffi_boundary));
    try std.testing.expectEqualStrings("sink", @tagName(PathStepType.sink));
}
