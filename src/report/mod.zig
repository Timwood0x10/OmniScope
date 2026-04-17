//! Security Report Module
//!
//! This module generates structured security analysis reports in the format
//! specified by OmniScope's development plan.
//!
//! Supported Output Formats:
//! - Text: Human-readable console output
//! - SARIF: Static Analysis Results Interchange Format v2.1.0
//!
//! SARIF is an OASIS standard format for static analysis results, enabling
//! integration with GitHub Code Scanning, Azure DevOps, and other tools.

const std = @import("std");

// Re-export SARIF module
pub const sarif = @import("sarif.zig");
pub const SarifGenerator = sarif.SarifGenerator;
pub const SarifRule = sarif.SarifRule;
pub const SarifResult = sarif.SarifResult;
pub const ToolInfo = sarif.ToolInfo;
pub const DEFAULT_TOOL_INFO = sarif.DEFAULT_TOOL_INFO;
pub const generateSarif = sarif.generateSarif;
pub const writeSarifToFile = sarif.writeSarifToFile;

// Re-export CI integration module
pub const ci = @import("ci_integration.zig");
pub const CIConfig = ci.CIConfig;
pub const CIRunner = ci.CIRunner;
pub const CIResult = ci.CIResult;
pub const CIPlatform = ci.CIPlatform;
pub const generateGitHubWorkflow = ci.generateGitHubWorkflow;

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
        errdefer output.deinit();

        try self.writeHeader(&output, report);
        try self.writeVulnerabilities(&output, report);
        try self.writeSummary(&output, report);

        return output.toOwnedSlice();
    }

    fn writeHeader(self: *ReportGenerator, output: *std.ArrayList(u8), report: SecurityReport) !void {
        try output.appendSlice("=== OmniScope Security Analysis Report ===\n");
        try output.writer().print(
            "Timestamp: {s}\n",
            .{self.formatTimestamp(report.timestamp)},
        );
        try output.writer().print(
            "Module: {s}\n",
            .{report.stats.module_name},
        );
        try output.writer().print(
            "Functions: {d} | Edges: {d} | Sources: {d} | Sinks: {d}\n",
            .{
                report.stats.function_count,
                report.stats.edge_count,
                report.stats.source_count,
                report.stats.sink_count,
            },
        );
        try output.appendSlice("\n");
    }

    fn writeVulnerabilities(self: *ReportGenerator, output: *std.ArrayList(u8), report: SecurityReport) !void {
        for (report.vulnerabilities) |vuln| {
            try writeVulnerabilitySeparator(output, vuln.severity);
            try output.writer().print(
                "Vulnerability ID:   {s}\n",
                .{vuln.id},
            );
            try output.writer().print(
                "Severity:           {s}\n",
                .{@tagName(vuln.severity)},
            );
            try output.writer().print(
                "Confidence:         {s} ({d:.2})\n",
                .{ self.confidenceLabel(vuln.confidence), vuln.confidence },
            );

            try output.appendSlice("\nPath:\n");
            try writePath(output, vuln.path, vuln.ffi_direction);

            if (vuln.impact.len > 0) {
                try output.appendSlice("\nImpact:\n");
                for (vuln.impact) |impact_line| {
                    try output.writer().print(
                        "  - {s}\n",
                        .{impact_line},
                    );
                }
            }

            if (vuln.is_cross_language) {
                try output.appendSlice("\nCross-Language: YES");
                if (vuln.ffi_direction) |dir| {
                    try output.writer().print(" ({s})", .{dir});
                }
                try output.appendSlice("\n");
            }

            try output.appendSlice("\n");
        }
    }

    fn writeVulnerabilitySeparator(output: *std.ArrayList(u8), severity: ReportSeverity) !void {
        const line = "------------------------------------------------------------------------";
        try output.appendSlice(line);
        try output.appendSlice("\n");
        try output.writer().print(
            "[{s}] {s}\n",
            .{ @tagName(severity).toUpper(), "Vulnerability Detected" },
        );
        try output.appendSlice(line);
        try output.appendSlice("\n");
    }

    fn writePath(
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
                try output.writer().print(
                    "{s}[{s}]{s} - {s}\n",
                    .{ prefix, step_type_str, if (ffi_direction) |d| d else "", step.description },
                );
            } else {
                try output.writer().print(
                    "{s}[{s}] {s} - {s}\n",
                    .{ prefix, step_type_str, step.func_name, step.description },
                );
            }
        }
    }

    fn writeSummary(output: *std.ArrayList(u8), report: SecurityReport) !void {
        const line = "------------------------------------------------------------------------";
        try output.appendSlice(line);
        try output.appendSlice("\n");
        try output.appendSlice("SUMMARY\n");
        try output.appendSlice(line);
        try output.appendSlice("\n");

        try output.writer().print(
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

        try output.writer().print(
            "Critical Issues:       {d}\n",
            .{critical_count},
        );
        try output.writer().print(
            "High Issues:          {d}\n",
            .{high_count},
        );
        try output.writer().print(
            "Medium Issues:        {d}\n",
            .{medium_count},
        );
        try output.writer().print(
            "Low Issues:           {d}\n",
            .{low_count},
        );

        try output.appendSlice("\n");
        try output.writer().print(
            "FFI Boundaries Crossed: {d}\n",
            .{report.ffi_boundaries_crossed},
        );

        if (report.ffi_boundaries_crossed > 0) {
            try output.appendSlice("Cross-Language Flow:    YES\n");
        } else {
            try output.appendSlice("Cross-Language Flow:    NO\n");
        }
    }

    fn formatTimestamp(self: *ReportGenerator, timestamp: i64) []const u8 {
        // Convert Unix timestamp to readable format
        // timestamp is in seconds since Unix epoch
        // Ensure timestamp is within valid range for i32 (Epoch.seconds type)
        const seconds = if (timestamp >= 0 and timestamp <= std.math.maxInt(i32))
            @intCast(timestamp)
        else
            0; // Fallback to epoch if out of range

        const epoch = std.time.epoch.Epoch{ .seconds = seconds };
        const year_day = epoch.getYearDay();
        const month_day = year_day.calculateMonthDay();

        const hours_minutes = epoch.getDayMinutes();
        const secs = epoch.getDaySeconds() % 60;

        // Use stack-allocated buffer to avoid memory leak
        var buffer: [32]u8 = undefined;
        const formatted = std.fmt.bufPrint(
            &buffer,
            "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}",
            .{
                year_day.year,
                month_day.month.numeric(),
                month_day.day_index + 1,
                hours_minutes.hours,
                hours_minutes.minutes,
                secs,
            },
        ) catch "1970-01-01 00:00:00";

        // Allocate on heap to return []const u8 (caller must free this)
        return self.allocator.dupe(u8, formatted) catch "1970-01-01 00:00:00";
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
