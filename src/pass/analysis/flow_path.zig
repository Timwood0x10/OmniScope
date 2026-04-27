//! Flow Path Analysis
//!
//! Defines risk levels, flow steps, flow paths, and vulnerability reports
//! for tracking data flow from sources to sinks.

const std = @import("std");
const Allocator = std.mem.Allocator;
const TaintState = @import("./taint_state.zig").TaintState;

/// Risk level for vulnerabilities
pub const RiskLevel = enum(u8) {
    /// Low risk - minor issues
    low = 0,
    /// Medium risk - potential issues that should be investigated
    medium = 1,
    /// High risk - significant vulnerabilities
    high = 2,
    /// Critical risk - severe vulnerabilities requiring immediate attention
    critical = 3,
};

/// Source location in the IR
pub const Location = struct {
    /// File name (if available)
    file: ?[]const u8,
    /// Line number
    line: u32,
    /// Column number
    column: u32,
};

/// Flow step in the data flow path
pub const FlowStep = struct {
    /// Unique identifier for this step
    id: u32,
    /// Function name at this step
    func_name: []const u8,
    /// Source location
    location: Location,
    /// Taint state at this step
    taint_state: TaintState,
    /// Confidence score
    confidence: f32,
};

/// Complete flow path from source to sink
pub const FlowPath = struct {
    /// Ordered list of steps in the path
    steps: std.ArrayList(FlowStep),
    /// Allocator for memory management
    allocator: Allocator,
    /// Risk severity of this path
    risk_level: RiskLevel,
    /// Whether this path crosses a language boundary
    is_cross_language: bool,
    /// Source function name
    source_func: []const u8,
    /// Sink function name
    sink_func: []const u8,

    /// Initialize an empty flow path.
    pub fn init(allocator: Allocator) !FlowPath {
        return .{
            .steps = try std.ArrayList(FlowStep).initCapacity(allocator, 0),
            .allocator = allocator,
            .risk_level = .low,
            .is_cross_language = false,
            .source_func = "",
            .sink_func = "",
        };
    }

    /// Deinitialize the flow path
    pub fn deinit(self: *FlowPath) void {
        self.steps.deinit();
    }

    /// Add a step to the path
    pub fn addStep(self: *FlowPath, step: FlowStep) !void {
        try self.steps.append(self.allocator, step);
    }

    /// Get the length of the path
    pub fn length(self: *const FlowPath) usize {
        return self.steps.items.len;
    }

    /// Check if the path is empty
    pub fn isEmpty(self: *const FlowPath) bool {
        return self.steps.items.len == 0;
    }
};

/// Vulnerability report
pub const VulnerabilityReport = struct {
    /// Unique identifier for this report
    id: u32,
    /// Risk severity
    risk_level: RiskLevel,
    /// Source function name
    source_func: []const u8,
    /// Sink function name
    sink_func: []const u8,
    /// Complete flow path
    flow_path: FlowPath,
    /// Description of the vulnerability
    description: []const u8,
    /// Recommendation for fixing
    recommendation: []const u8,

    /// Create a formatted summary
    pub fn formatSummary(self: *const VulnerabilityReport, allocator: Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        errdefer buffer.deinit();

        const writer = buffer.writer();
        try writer.print("Vulnerability OMI-{d:0>3}\n", .{self.id});
        try writer.print("Severity: {s}\n", .{@tagName(self.risk_level)});
        try writer.print("Source: {s}\n", .{self.source_func});
        try writer.print("Sink: {s}\n", .{self.sink_func});
        try writer.print("Cross-language: {}\n", .{self.flow_path.is_cross_language});
        try writer.print("Path length: {} steps\n", .{self.flow_path.length()});

        return buffer.toOwnedSlice();
    }
};

/// Vulnerability report builder
pub const VulnerabilityReportBuilder = struct {
    id: u32,
    risk_level: RiskLevel,
    source_func: []const u8,
    sink_func: []const u8,
    flow_path: FlowPath,
    description: []const u8,
    recommendation: []const u8,

    /// Create a new builder
    pub fn init(id: u32, allocator: Allocator) !VulnerabilityReportBuilder {
        return .{
            .id = id,
            .risk_level = .medium,
            .source_func = "",
            .sink_func = "",
            .flow_path = try FlowPath.init(allocator),
            .description = "",
            .recommendation = "",
        };
    }

    /// Set risk level
    pub fn withRisk(self: *VulnerabilityReportBuilder, level: RiskLevel) *VulnerabilityReportBuilder {
        self.risk_level = level;
        return self;
    }

    /// Set source function
    pub fn withSource(self: *VulnerabilityReportBuilder, func: []const u8) *VulnerabilityReportBuilder {
        self.source_func = func;
        return self;
    }

    /// Set sink function
    pub fn withSink(self: *VulnerabilityReportBuilder, func: []const u8) *VulnerabilityReportBuilder {
        self.sink_func = func;
        return self;
    }

    /// Set flow path
    pub fn withFlowPath(self: *VulnerabilityReportBuilder, path: FlowPath) *VulnerabilityReportBuilder {
        self.flow_path = path;
        return self;
    }

    /// Set description
    pub fn withDescription(self: *VulnerabilityReportBuilder, desc: []const u8) *VulnerabilityReportBuilder {
        self.description = desc;
        return self;
    }

    /// Set recommendation
    pub fn withRecommendation(self: *VulnerabilityReportBuilder, rec: []const u8) *VulnerabilityReportBuilder {
        self.recommendation = rec;
        return self;
    }

    /// Build the report
    /// Consumes the builder to avoid double ownership of FlowPath
    pub fn build(self: VulnerabilityReportBuilder) VulnerabilityReport {
        return .{
            .id = self.id,
            .risk_level = self.risk_level,
            .source_func = self.source_func,
            .sink_func = self.sink_func,
            .flow_path = self.flow_path,
            .description = self.description,
            .recommendation = self.recommendation,
        };
    }
};

test "RiskLevel - all variants" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(RiskLevel.low));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(RiskLevel.medium));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(RiskLevel.high));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(RiskLevel.critical));
}

test "Location - structure" {
    const loc = Location{
        .file = "test.c",
        .line = 42,
        .column = 10,
    };
    try std.testing.expectEqualStrings("test.c", loc.file.?);
    try std.testing.expectEqual(@as(u32, 42), loc.line);
    try std.testing.expectEqual(@as(u32, 10), loc.column);
}

test "Location - null file" {
    const loc = Location{
        .file = null,
        .line = 1,
        .column = 1,
    };
    try std.testing.expect(loc.file == null);
}

test "FlowStep - structure" {
    const step = FlowStep{
        .id = 1,
        .func_name = "test_func",
        .location = .{ .file = null, .line = 0, .column = 0 },
        .taint_state = .tainted,
        .confidence = 0.95,
    };
    try std.testing.expectEqual(@as(u32, 1), step.id);
    try std.testing.expectEqualStrings("test_func", step.func_name);
    try std.testing.expectEqual(TaintState.tainted, step.taint_state);
}

test "FlowPath - empty path" {
    const path = try FlowPath.init(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), path.length());
    try std.testing.expect(path.isEmpty());
}

test "FlowPath - add step" {
    var path = try FlowPath.init(std.testing.allocator);
    defer path.deinit();

    const step = FlowStep{
        .id = 1,
        .func_name = "test",
        .location = .{ .file = null, .line = 0, .column = 0 },
        .taint_state = .source,
        .confidence = 1.0,
    };

    try path.addStep(step);
    try std.testing.expectEqual(@as(usize, 1), path.length());
    try std.testing.expect(!path.isEmpty());
}

test "FlowPath - multiple steps" {
    var path = try FlowPath.init(std.testing.allocator);
    defer path.deinit();

    const step1 = FlowStep{
        .id = 1,
        .func_name = "source",
        .location = .{ .file = null, .line = 0, .column = 0 },
        .taint_state = .source,
        .confidence = 1.0,
    };

    const step2 = FlowStep{
        .id = 2,
        .func_name = "intermediate",
        .location = .{ .file = null, .line = 0, .column = 0 },
        .taint_state = .tainted,
        .confidence = 0.9,
    };

    try path.addStep(step1);
    try path.addStep(step2);
    try std.testing.expectEqual(@as(usize, 2), path.length());
}

test "VulnerabilityReport - structure" {
    const report = VulnerabilityReport{
        .id = 1,
        .risk_level = .critical,
        .source_func = "read_input",
        .sink_func = "system",
        .flow_path = try FlowPath.init(std.testing.allocator),
        .description = "Command injection",
        .recommendation = "Sanitize input",
    };

    try std.testing.expectEqual(@as(u32, 1), report.id);
    try std.testing.expectEqual(RiskLevel.critical, report.risk_level);
    try std.testing.expectEqualStrings("read_input", report.source_func);
    try std.testing.expectEqualStrings("system", report.sink_func);
}

test "VulnerabilityReportBuilder - build report" {
    var builder = try VulnerabilityReportBuilder.init(1, std.testing.allocator);
    defer builder.flow_path.deinit();
    _ = builder.withRisk(.high);
    _ = builder.withSource("source_func");
    _ = builder.withSink("sink_func");
    _ = builder.withDescription("Test vulnerability");
    _ = builder.withRecommendation("Fix it");

    const report = builder.build();
    try std.testing.expectEqual(@as(u32, 1), report.id);
    try std.testing.expectEqual(RiskLevel.high, report.risk_level);
    try std.testing.expectEqualStrings("source_func", report.source_func);
    try std.testing.expectEqualStrings("sink_func", report.sink_func);
}

test "VulnerabilityReport - formatSummary" {
    const report = VulnerabilityReport{
        .id = 42,
        .risk_level = .critical,
        .source_func = "read",
        .sink_func = "system",
        .flow_path = try FlowPath.init(std.testing.allocator),
        .description = "Test",
        .recommendation = "Fix",
    };

    const summary = try report.formatSummary(std.testing.allocator);
    defer std.testing.allocator.free(summary);

    try std.testing.expect(std.mem.indexOf(u8, summary, "OMI-042") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "critical") != null);
}

test "RiskLevel - ordering" {
    try std.testing.expect(@intFromEnum(RiskLevel.low) < @intFromEnum(RiskLevel.medium));
    try std.testing.expect(@intFromEnum(RiskLevel.medium) < @intFromEnum(RiskLevel.high));
    try std.testing.expect(@intFromEnum(RiskLevel.high) < @intFromEnum(RiskLevel.critical));
}

test "FlowPath - cross language flag" {
    var path = try FlowPath.init(std.testing.allocator);
    defer path.deinit();

    path.is_cross_language = true;
    try std.testing.expect(path.is_cross_language);
}

test "FlowStep - confidence range" {
    const step = FlowStep{
        .id = 1,
        .func_name = "test",
        .location = .{ .file = null, .line = 0, .column = 0 },
        .taint_state = .tainted,
        .confidence = 0.5,
    };

    try std.testing.expect(step.confidence >= 0.0 and step.confidence <= 1.0);
}
