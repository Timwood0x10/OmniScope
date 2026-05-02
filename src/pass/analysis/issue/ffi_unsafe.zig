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
        // C setjmp/longjmp — control flow violation at FFI boundary
        "setjmp",      "longjmp",
        "sigsetjmp",   "siglongjmp",
        // Variadic function abuse across FFI boundary
        "vprintf",     "vfprintf",
        "vsprintf",    "vsnprintf",
        "vsscanf",     "vfscanf",
        "execl",       "execle",
        "execlp",      "execvp",
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
        var issue_count: usize = 0;

        if (isDangerous(boundary.function_name)) {
            const vuln_type = classifyVulnerability(boundary.function_name);

            // P1 Task 2.2: Sink Context Sensitivity
            // Downgrade or skip issues where the dangerous call appears in safe contexts.
            if (isLikelySafeContext(boundary, vuln_type)) {
                diag.debug("FFIUnsafe-SKIP: {s} in caller={s} — safe context", .{
                    cleanFunctionName(boundary.function_name),
                    boundary.location.func,
                });
                return 0;
            }

            var confidence = calculateConfidence(boundary.function_name, vuln_type);

            // Apply context-based confidence adjustment
            confidence = adjustConfidenceForContext(boundary, vuln_type, confidence);

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

            try ctx.addIssue(&issue);
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
        // P1-2: setjmp/longjmp — control flow violation (C99 §7.13.2)
        // Variables modified between setjmp/longjmp have indeterminate values.
        // At FFI boundary, this bypasses Rust/Zig destructors and unwind cleanup.
        if (std.mem.indexOf(u8, func_name, "setjmp") != null or
            std.mem.indexOf(u8, func_name, "sigsetjmp") != null or
            std.mem.indexOf(u8, func_name, "longjmp") != null or
            std.mem.indexOf(u8, func_name, "siglongjmp") != null)
        {
            return .ffi_unsafe_call;
        }
        if (std.mem.indexOf(u8, func_name, "system") != null or
            std.mem.indexOf(u8, func_name, "exec") != null)
        {
            return .command_injection;
        }
        // P1-2: Variadic function abuse at FFI boundary
        // v*printf/v*scanf with user-controlled format args = format string / injection
        if (std.mem.indexOf(u8, func_name, "printf") != null or
            std.mem.indexOf(u8, func_name, "fprintf") != null or
            std.mem.indexOf(u8, func_name, "sprintf") != null or
            std.mem.indexOf(u8, func_name, "snprintf") != null or
            std.mem.indexOf(u8, func_name, "vprintf") != null or
            std.mem.indexOf(u8, func_name, "vfprintf") != null or
            std.mem.indexOf(u8, func_name, "vsprintf") != null or
            std.mem.indexOf(u8, func_name, "vsnprintf") != null or
            std.mem.eql(u8, func_name, "syslog"))
        {
            return .format_string;
        }
        // vsscanf/vfscanf — input validation via uncontrolled variadic args
        if (std.mem.indexOf(u8, func_name, "vsscanf") != null or
            std.mem.indexOf(u8, func_name, "vfscanf") != null)
        {
            return .ffi_unsafe_call;
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
            .ffi_unsafe_call => "FFI safety violation - dangerous pattern at language boundary",
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

    /// P1 Task 2.2: Sink Context Sensitivity
    ///
    /// Determine if a dangerous FFI call is likely in a safe context.
    /// Safe contexts include:
    /// - Debug/logging functions (fprintf to stderr for diagnostics)
    /// - Error reporting functions (syslog with fixed format)
    /// - Test/output functions (printf in test harnesses)
    ///
    /// This is a heuristic based on caller function naming conventions.
    fn isLikelySafeContext(boundary: *const FFIBoundary, vuln_type: IssueKind) bool {
        if (vuln_type != .format_string) return false;

        const func_name = boundary.function_name;
        const caller_name = boundary.location.func;

        // Primary: check file path from debug info
        const context_str = if (boundary.location.file) |f| f else caller_name;

        const safe_patterns = [_][]const u8{
            "sqlite3.c", "sqlite3", "sqlite",
            "libuv",     "uv.",     "test_",
            "_test",     "example", "demo",
        };

        for (safe_patterns) |pattern| {
            if (std.mem.indexOf(u8, context_str, pattern) != null) {
                const clean = cleanFunctionName(func_name);
                if (std.mem.indexOf(u8, clean, "fprintf") != null or
                    std.mem.indexOf(u8, clean, "sprintf") != null or
                    std.mem.indexOf(u8, clean, "snprintf") != null)
                {
                    return true;
                }
            }
        }

        // Secondary: known-safe caller function name patterns
        // These are internal/debug/diagnostic functions in well-known libraries
        const safe_caller_prefixes = [_][]const u8{
            "proxy", "conch", "lock", // SQLite internal diagnostics
            "debug", "log", "trace", // Generic logging
            "diag", "dump", "print", // Diagnostic output
            "sqlite3Mem", "sqlite3Db", // SQLite memory wrappers (allocator calls)
            "uv__fs_", "uv__stream_", // libuv internals
        };

        for (safe_caller_prefixes) |prefix| {
            if (std.mem.indexOf(u8, caller_name, prefix) != null) {
                const clean = cleanFunctionName(func_name);
                if (std.mem.indexOf(u8, clean, "fprintf") != null or
                    std.mem.indexOf(u8, clean, "sprintf") != null)
                {
                    return true;
                }
            }
        }

        return false;
    }

    /// Adjust confidence based on calling context.
    /// Reduces confidence for calls that appear in safer contexts.
    fn adjustConfidenceForContext(boundary: *const FFIBoundary, vuln_type: IssueKind, base_confidence: f32) f32 {
        var confidence = base_confidence;

        const context_str = if (boundary.location.file) |f| f else boundary.function_name;

        // Reduce confidence for format-string issues in source files that are
        // known to be well-maintained C libraries (not user-facing input handlers)
        if (vuln_type == .format_string) {
            // SQLite internal diagnostics → very low confidence
            if (std.mem.indexOf(u8, context_str, "sqlite3") != null) {
                confidence *= 0.3; // Downgrade to ~15-25%
            }
            // libuv internal logging
            if (std.mem.indexOf(u8, context_str, "libuv") != null or
                std.mem.indexOf(u8, context_str, "uv.") != null)
            {
                confidence *= 0.4;
            }
        }

        // Cap minimum confidence at 0.05 so we still report but as LOW severity
        if (confidence < 0.05) confidence = 0.05;

        return confidence;
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

test "FFIUnsafePass - P1-2 setjmp/longjmp detection" {
    // P1-2: C control flow violation at FFI boundary
    try std.testing.expect(FFIUnsafePass.isDangerous("setjmp"));
    try std.testing.expect(FFIUnsafePass.isDangerous("longjmp"));
    try std.testing.expect(FFIUnsafePass.isDangerous("sigsetjmp"));
    try std.testing.expect(FFIUnsafePass.isDangerous("siglongjmp"));
    try std.testing.expectEqual(IssueKind.ffi_unsafe_call, FFIUnsafePass.classifyVulnerability("setjmp"));
    try std.testing.expectEqual(IssueKind.ffi_unsafe_call, FFIUnsafePass.classifyVulnerability("longjmp"));
    try std.testing.expectEqual(IssueKind.ffi_unsafe_call, FFIUnsafePass.classifyVulnerability("sigsetjmp"));
    try std.testing.expectEqual(IssueKind.ffi_unsafe_call, FFIUnsafePass.classifyVulnerability("siglongjmp"));
}

test "FFIUnsafePass - P1-2 variadic function detection" {
    // P1-2: Variadic functions across FFI boundary
    try std.testing.expect(FFIUnsafePass.isDangerous("vprintf"));
    try std.testing.expect(FFIUnsafePass.isDangerous("vfprintf"));
    try std.testing.expect(FFIUnsafePass.isDangerous("vsprintf"));
    try std.testing.expect(FFIUnsafePass.isDangerous("vsnprintf"));
    try std.testing.expect(FFIUnsafePass.isDangerous("vsscanf"));
    try std.testing.expect(FFIUnsafePass.isDangerous("vfscanf"));
    // Classification
    try std.testing.expectEqual(IssueKind.format_string, FFIUnsafePass.classifyVulnerability("vprintf"));
    try std.testing.expectEqual(IssueKind.format_string, FFIUnsafePass.classifyVulnerability("vsprintf"));
    try std.testing.expectEqual(IssueKind.ffi_unsafe_call, FFIUnsafePass.classifyVulnerability("vsscanf"));
    try std.testing.expectEqual(IssueKind.ffi_unsafe_call, FFIUnsafePass.classifyVulnerability("vfscanf"));
}
