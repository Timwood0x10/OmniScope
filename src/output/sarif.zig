//! SARIF Output Format
//!
//! This module implements SARIF (Static Analysis Results Interchange Format) v2.1.0 output.
//! SARIF is an OASIS standard for sharing static analysis results.

const std = @import("std");

const Issue = @import("../diag/issue.zig").Issue;
const IssueKind = @import("../diag/issue.zig").IssueKind;
const Severity = @import("../diag/issue.zig").Severity;
const Location = @import("../diag/issue.zig").Location;
const TraceEntry = @import("../diag/issue.zig").TraceEntry;

pub const SarifLevel = enum {
    note,
    warning,
    err,

    fn fromSeverity(severity: Severity) SarifLevel {
        return switch (severity) {
            .low => .note,
            .medium => .warning,
            .high, .critical => .err,
        };
    }

    fn toString(self: SarifLevel) []const u8 {
        return switch (self) {
            .note => "note",
            .warning => "warning",
            .err => "error",
        };
    }
};

pub const SarifOutput = struct {
    allocator: std.mem.Allocator,
    tool_name: []const u8,
    tool_version: []const u8,
    tool_uri: []const u8,

    pub fn init(allocator: std.mem.Allocator, tool_name: []const u8, tool_version: []const u8) SarifOutput {
        return initWithUri(allocator, tool_name, tool_version, "https://github.com/omniscope/omniscope");
    }

    pub fn initWithUri(allocator: std.mem.Allocator, tool_name: []const u8, tool_version: []const u8, uri: []const u8) SarifOutput {
        return .{
            .allocator = allocator,
            .tool_name = tool_name,
            .tool_version = tool_version,
            .tool_uri = uri,
        };
    }

    pub fn generate(self: *SarifOutput, issues: []const Issue) ![]const u8 {
        var buf = std.array_list.Managed(u8).init(self.allocator);
        defer buf.deinit();
        const w = buf.writer();

        try w.writeAll("{\"$schema\":");
        try self.writeJsonString(w, "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json");
        try w.writeAll(",\"version\":");
        try self.writeJsonString(w, "2.1.0");
        try w.writeAll(",\"runs\":[{\"tool\":{\"driver\":{\"name\":");
        try self.writeJsonString(w, self.tool_name);
        try w.writeAll(",\"version\":");
        try self.writeJsonString(w, self.tool_version);
        try w.writeAll(",\"informationUri\":");
        try self.writeJsonString(w, self.tool_uri);
        try w.writeAll("}},\"rules\":[");

        const kinds = [_]IssueKind{
            .memory_leak,
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
            .null_dereference,
            .borrow_escape,
            .unknown,
        };
        for (kinds, 0..) |kind, i| {
            if (i > 0) try w.writeAll(",");
            try w.writeAll("{\"id\":");
            try self.writeJsonString(w, @tagName(kind));
            try w.writeAll(",\"name\":");
            try self.writeJsonString(w, @tagName(kind));
            try w.writeAll(",\"shortDescription\":{\"text\":");
            try self.writeJsonString(w, kind.toDescription());
            try w.writeAll("}}");
        }

        try w.writeAll("],\"results\":[");
        for (issues, 0..) |issue, idx| {
            if (idx > 0) try w.writeAll(",");
            const file_str = if (issue.location.file) |f| f else "unknown";
            const line_num = if (issue.location.line > 0) issue.location.line else 1;
            const col_num = if (issue.location.column > 0) issue.location.column else 1;

            try w.writeAll("{\"ruleId\":");
            try self.writeJsonString(w, @tagName(issue.kind));
            try w.writeAll(",\"level\":");
            try self.writeJsonString(w, SarifLevel.fromSeverity(issue.severity).toString());
            try w.writeAll(",\"message\":{\"text\":");
            try self.writeJsonString(w, issue.message);
            try w.writeAll("},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":");
            try self.writeJsonString(w, file_str);
            try w.writeAll("},\"region\":{\"startLine\":");
            try writeUint64(w, line_num);
            try w.writeAll(",\"startColumn\":");
            try writeUint64(w, col_num);
            try w.writeAll("}}}],\"properties\":{\"confidence\":");
            try writeFloat(w, issue.confidence);
            try w.writeAll(",\"confidenceLevel\":");
            try self.writeJsonString(w, issue.confidence_level.toString());
            if (issue.reason.len > 0) {
                try w.writeAll(",\"reason\":");
                try self.writeJsonString(w, issue.reason);
            }
            try w.writeAll("}");

            if (issue.trace) |trace| {
                if (trace.len > 0) {
                    try w.writeAll(",\"codeFlows\":[{\"threadFlows\":[{\"locations\":[");
                    for (trace, 0..) |entry, ei| {
                        if (ei > 0) try w.writeAll(",");
                        try w.writeAll("{\"location\":{\"physicalLocation\":{\"artifactLocation\":{\"uri\":");
                        if (entry.location) |loc| {
                            try self.writeJsonString(w, if (loc.file) |f| f else "unknown");
                            try w.writeAll("},\"region\":{\"startLine\":");
                            try writeUint64(w, if (loc.line > 0) loc.line else 1);
                        } else {
                            try self.writeJsonString(w, "unknown");
                            try w.writeAll("},\"region\":{\"startLine\":1");
                        }
                        try w.writeAll("}}},\"message\":{\"text\":");
                        try self.writeJsonString(w, entry.description);
                        try w.writeAll("}}");
                    }
                    try w.writeAll("]}]}]");
                }
            }
            try w.writeAll("}");
        }

        try w.writeAll("]}]}");

        return try buf.toOwnedSlice();
    }

    fn writeJsonString(self: *SarifOutput, writer: anytype, s: []const u8) !void {
        _ = self;
        try writer.print("{f}", .{std.json.fmt(s, .{})});
    }

    pub fn writeToFile(self: *SarifOutput, path: []const u8, issues: []const Issue) !void {
        const payload = try self.generate(issues);
        defer self.allocator.free(payload);
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(payload);
    }
};

pub const ToolInfo = struct {
    name: []const u8,
    version: []const u8,
    information_uri: []const u8,
};

pub const SarifGenerator = struct {
    allocator: std.mem.Allocator,
    tool_info: ToolInfo,

    pub fn init(allocator: std.mem.Allocator, tool_info: ToolInfo) SarifGenerator {
        return .{ .allocator = allocator, .tool_info = tool_info };
    }

    pub fn generate(self: *SarifGenerator, issues: []const Issue) ![]const u8 {
        var sarif = SarifOutput.init(self.allocator, self.tool_info.name, self.tool_info.version, self.tool_info.information_uri);
        return try sarif.generate(issues);
    }

    pub fn writeToFile(self: *SarifGenerator, path: []const u8, issues: []const Issue) !void {
        var sarif = SarifOutput.init(self.allocator, self.tool_info.name, self.tool_info.version, self.tool_info.information_uri);
        try sarif.writeToFile(path, issues);
    }
};

pub const SarifRule = struct {
    id: []const u8,
    name: []const u8,
    short_description: []const u8,
    default_level: []const u8,
};

pub const SarifResult = struct {
    rule_id: []const u8,
    level: []const u8,
    message: []const u8,
    file: []const u8,
    line: u32,
    column: u32,
};

pub const DEFAULT_TOOL_INFO = ToolInfo{
    .name = "OmniScope",
    .version = "0.1.8",
    .information_uri = "https://github.com/omniscope/omniscope",
};

pub fn generateSarif(allocator: std.mem.Allocator, tool_info: ToolInfo, issues: []const Issue) ![]const u8 {
    var gen = SarifGenerator.init(allocator, tool_info);
    return try gen.generate(issues);
}

pub fn writeSarifToFile(allocator: std.mem.Allocator, path: []const u8, issues: []const Issue, tool_info: ToolInfo) !void {
    var gen = SarifGenerator.init(allocator, tool_info);
    try gen.writeToFile(path, issues);
}

fn defaultSeverity(kind: IssueKind) Severity {
    return switch (kind) {
        .command_injection => .critical,
        .buffer_overflow, .use_after_free, .double_free => .high,
        .format_string, .cross_language_leak, .type_mismatch => .medium,
        .ffi_unsafe_call, .unchecked_return, .malloc_unchecked, .invalid_free => .medium,
        .null_dereference, .borrow_escape => .high,
        .memory_leak => .medium,
        .unknown => .low,
    };
}

fn writeUint64(writer: anytype, v: u64) !void {
    if (v == 0) {
        try writer.writeByte('0');
        return;
    }
    var buf: [20]u8 = undefined;
    var i: usize = 20;
    var val = v;
    while (val > 0) {
        i -= 1;
        buf[i] = @as(u8, @intCast(val % 10)) + '0';
        val /= 10;
    }
    try writer.writeAll(buf[i..]);
}

fn writeFloat(writer: anytype, v: f64) !void {
    var buf: [32]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d}", .{v}) catch return error.OutOfMemory;
    try writer.writeAll(result);
}
