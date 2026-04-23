//! FFI Unsafe Detection Pass
//!
//! Enhanced FFI security analysis combining FFIMatcher and Pipeline

const std = @import("std");

const PassContext = @import("../../../pass/pass.zig").PassContext;
const PassKind = @import("../../../pass/pass.zig").PassKind;
const DiagnosticWriter = @import("../../../pass/pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const FFIBoundary = @import("../../../diag/issue.zig").FFIBoundary;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;

/// FFI unsafe detection pass
pub const FFIUnsafePass = struct {
    pub const name = "ffi-unsafe";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"ffi-boundary"};

    const DangerousPatterns = &[_][]const u8{
        "system",      "popen",
        "exec",        "execve",
        "execvp",      "execv",
        "execl",       "execlp",
        "execle",      "fexecve",
        "posix_spawn", "posix_spawnp",
        "malloc",      "free",
        "realloc",     "calloc",
        "strcpy",      "strcat",
        "gets",        "sprintf",
    };

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const ffi_boundaries = ctx.data_flow_graph.getFFIBoundaries();
        if (ffi_boundaries.len == 0) {
            diag.info("FFIUnsafe: No FFI boundaries to analyze", .{});
            return;
        }

        var issue_count: usize = 0;
        for (ffi_boundaries) |boundary| {
            issue_count += try analyzeBoundary(ctx, &boundary, diag);
        }

        diag.info("FFIUnsafe: Analyzed {} boundaries, found {} issues", .{
            ffi_boundaries.len, issue_count,
        });
    }

    fn analyzeBoundary(ctx: *PassContext, boundary: *const FFIBoundary, diag: *DiagnosticWriter) !usize {
        _ = diag;
        var issue_count: usize = 0;

        if (isDangerous(boundary.function_name)) {
            const vuln_type = classifyVulnerability(boundary.function_name);
            const confidence = calculateConfidence(boundary.function_name, vuln_type);

            const clean_name = cleanFunctionName(boundary.function_name);
            const issue_message = try std.fmt.allocPrint(
                ctx.allocator,
                "Unsafe FFI call to '{s}' - {s} (confidence: {d:.2}%)",
                .{ clean_name, getVulnerabilityDesc(vuln_type), confidence * 100.0 },
            );

            const issue = Issue.init(
                vuln_type,
                issue_message,
                boundary.location,
                calculateSeverity(confidence),
                confidence,
            );

            try ctx.addIssue(issue);
            ctx.allocator.free(issue_message);
            issue_count += 1;
        }

        return issue_count;
    }

    pub fn isDangerous(func_name: []const u8) bool {
        const clean = if (func_name.len > 0 and func_name[0] < 32) func_name[1..] else func_name;
        for (DangerousPatterns) |pattern| {
            if (std.mem.eql(u8, clean, pattern)) {
                return true;
            }
        }
        return false;
    }

    pub fn classifyVulnerability(func_name: []const u8) IssueKind {
        if (std.mem.indexOf(u8, func_name, "system") != null or
            std.mem.indexOf(u8, func_name, "exec") != null)
        {
            return .command_injection;
        }
        if (std.mem.eql(u8, func_name, "printf") or
            std.mem.eql(u8, func_name, "fprintf") or
            std.mem.eql(u8, func_name, "sprintf") or
            std.mem.eql(u8, func_name, "snprintf") or
            std.mem.eql(u8, func_name, "vprintf") or
            std.mem.eql(u8, func_name, "vfprintf") or
            std.mem.eql(u8, func_name, "syslog"))
        {
            return .format_string;
        }
        if (std.mem.indexOf(u8, func_name, "strcpy") != null or
            std.mem.indexOf(u8, func_name, "gets") != null)
        {
            return .buffer_overflow;
        }
        return .ffi_unsafe_call;
    }

    fn getVulnerabilityDesc(vuln_type: IssueKind) []const u8 {
        return switch (vuln_type) {
            .command_injection => "Command injection vulnerability",
            .format_string => "Format string vulnerability - user-controlled format string",
            .buffer_overflow => "Buffer overflow vulnerability",
            else => "General FFI safety issue",
        };
    }

    /// Calculate confidence score for a vulnerability detection
    ///
    /// Factors considered:
    /// - Exact match vs partial match (exact = higher confidence)
    /// - Vulnerability type (command injection = highest confidence)
    /// - Function name specificity
    ///
    /// Returns:
    ///   - Confidence score (0.0 - 1.0)
    fn calculateConfidence(func_name: []const u8, vuln_type: IssueKind) f32 {
        var base_confidence: f32 = 0.5; // Base confidence

        // Exact match bonus
        for (DangerousPatterns) |pattern| {
            if (std.mem.eql(u8, func_name, pattern)) {
                base_confidence += 0.3; // Exact match = +30%
                break;
            }
        }

        // Vulnerability type bonus
        switch (vuln_type) {
            .command_injection => base_confidence += 0.15, // Command injection = +15%
            .buffer_overflow => base_confidence += 0.10, // Buffer overflow = +10%
            else => {},
        }

        // Function specificity bonus (longer names are more specific)
        if (func_name.len > 10) {
            base_confidence += 0.05; // Specific function name = +5%
        }

        // Cap at 1.0
        if (base_confidence > 1.0) {
            base_confidence = 1.0;
        }

        return base_confidence;
    }

    /// Calculate severity level based on confidence
    ///
    /// Parameters:
    ///   - confidence: Confidence score (0.0 - 1.0)
    ///
    /// Returns:
    ///   - Severity level
    fn calculateSeverity(confidence: f32) Severity {
        if (confidence >= 0.9) {
            return .critical;
        } else if (confidence >= 0.7) {
            return .high;
        } else if (confidence >= 0.5) {
            return .medium;
        } else {
            return .low;
        }
    }

    fn cleanFunctionName(func_name: []const u8) []const u8 {
        if (func_name.len > 0 and func_name[0] < 32) {
            return func_name[1..];
        }
        return func_name;
    }
};

test "FFIUnsafePass - dangerous detection" {
    try std.testing.expect(FFIUnsafePass.isDangerous("system"));
    try std.testing.expect(FFIUnsafePass.isDangerous("malloc"));
    try std.testing.expect(!FFIUnsafePass.isDangerous("safe_func"));
}

test "FFIUnsafePass - vulnerability classification" {
    try std.testing.expectEqual(IssueKind.command_injection, FFIUnsafePass.classifyVulnerability("system"));
    try std.testing.expectEqual(IssueKind.buffer_overflow, FFIUnsafePass.classifyVulnerability("strcpy"));
}
