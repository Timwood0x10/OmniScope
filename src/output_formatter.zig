//! Output Formatting — Text, JSON, and SARIF output for OmniScope
//!
//! Extracted from main.zig: emitOutput, formatStructuredReport,
//! formatIssuesAsJson, writeCallGraph, languageDisplayName,
//! detectTargetLanguage.

const std = @import("std");
const Allocator = std.mem.Allocator;
const OmniScope = @import("OmniScope");
const Issue = OmniScope.diag.Issue;
const IssueKind = OmniScope.diag.IssueKind;
const Location = OmniScope.diag.Location;
const Severity = OmniScope.diag.Severity;
const log = OmniScope.log;
const writeJsonEscaped = OmniScope.output.writeJsonEscaped;
const SarifOutput = OmniScope.output.SarifOutput;

const main_config = OmniScope.config.main_config;
const term = main_config.term;
const Config = main_config.Config;

const FFI_Language = OmniScope.diag.FFIBoundary.Language;

const issue_filter = @import("issue_filter.zig");

/// Convert FFI_Language enum to user-friendly display string.
pub fn languageDisplayName(lang: FFI_Language) []const u8 {
    return switch (lang) {
        .c => "C",
        .cpp => "C++",
        .rust => "Rust",
        .zig => "Zig",
        .csharp => "C#",
        .go => "Go",
        .java => "Java",
        .python => "Python",
        .unknown => "Unknown",
    };
}

/// Detect the dominant target language from FFI issues.
pub fn detectTargetLanguage(issues: []const Issue) FFI_Language {
    var lang_counts = [_]usize{0} ** 9;
    for (issues) |issue| {
        if (issue.ffi_boundary) |bnd| {
            const idx = @intFromEnum(bnd.callee_language);
            if (idx < lang_counts.len) {
                lang_counts[idx] += 1;
            }
        }
    }
    var max_count: usize = 0;
    var dominant_lang = FFI_Language.c;
    for (lang_counts, 0..) |count, i| {
        if (count > max_count) {
            max_count = count;
            dominant_lang = @as(FFI_Language, @enumFromInt(i));
        }
    }
    return dominant_lang;
}

pub fn emitOutput(allocator: std.mem.Allocator, issues: []const Issue, func_count: usize, time_ms: u64, config: Config, source_lang: FFI_Language, target_lang: FFI_Language) !void {
    var mutable_issues = try allocator.alloc(Issue, issues.len);
    defer allocator.free(mutable_issues);
    for (issues, 0..) |issue, i| {
        mutable_issues[i] = issue;
    }

    issue_filter.classifySurfaces(mutable_issues);

    const filtered_issues = try issue_filter.filterIssues(allocator, mutable_issues, config);
    defer allocator.free(filtered_issues);

    if (config.output_format == .json) {
        const json_output = formatIssuesAsJson(allocator, filtered_issues, func_count, time_ms) catch |err| {
            log.err("Failed to format JSON output: {}\n", .{err});
            return;
        };
        defer allocator.free(json_output);

        if (config.output_file) |output_path| {
            const file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
                log.err("Failed to create output file '{s}': {}\n", .{ output_path, err });
                return;
            };
            defer file.close();
            file.writeAll(json_output) catch |err| {
                log.err("Failed to write to file '{s}': {}\n", .{ output_path, err });
                return;
            };
            log.info("Report saved to: {s}\n", .{output_path});
        } else {
            _ = try std.posix.write(std.posix.STDOUT_FILENO, json_output);
        }
    } else if (config.output_format == .sarif) {
        var sarif = SarifOutput.init(allocator, "OmniScope", "0.2.0");
        const sarif_output = sarif.generate(filtered_issues) catch |err| {
            log.err("Failed to generate SARIF output: {}\n", .{err});
            return;
        };
        defer allocator.free(sarif_output);

        if (config.output_file) |output_path| {
            const file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
                log.err("Failed to create output file '{s}': {}\n", .{ output_path, err });
                return;
            };
            defer file.close();
            file.writeAll(sarif_output) catch |err| {
                log.err("Failed to write to file '{s}': {}\n", .{ output_path, err });
                return;
            };
            log.info("SARIF report saved to: {s}\n", .{output_path});
        } else {
            _ = try std.posix.write(std.posix.STDOUT_FILENO, sarif_output);
        }
    } else {
        const report = formatStructuredReport(allocator, filtered_issues, func_count, time_ms, source_lang, target_lang) catch |err| {
            log.err("Failed to format report: {}\n", .{err});
            return;
        };
        defer allocator.free(report);
        _ = try std.posix.write(std.posix.STDOUT_FILENO, report);
    }
}

fn formatStructuredReport(allocator: std.mem.Allocator, issues: []const Issue, func_count: usize, time_ms: u64, source_lang: FFI_Language, target_lang: FFI_Language) ![]u8 {
    var buf = std.ArrayList(u8).initCapacity(allocator, 4096) catch return error.OutOfMemory;
    defer buf.deinit(allocator);
    const w = buf.writer(allocator);

    try w.writeAll(term.bold);
    try w.writeAll(term.blue);
    try w.writeAll("═══════════════════════════════════════════════════════════════\n");
    try w.writeAll("  OmniScope — Cross-Language Memory Safety Analysis\n");
    try w.writeAll("═══════════════════════════════════════════════════════════════\n");
    try w.writeAll(term.reset);
    try w.writeAll("\n");

    try w.writeAll(term.bold);
    try w.writeAll(term.magenta);
    try w.writeAll("[Language] ");
    try w.writeAll(term.reset);
    try w.writeAll(term.cyan);
    try w.print("{s}", .{languageDisplayName(source_lang)});
    if (source_lang == target_lang) {
        try w.writeAll(term.reset);
        try w.writeAll(term.dim);
        try w.writeAll(" (no cross-language content)");
    } else {
        try w.writeAll(term.dim);
        try w.writeAll(" --> ");
        try w.writeAll(term.bright_cyan);
        try w.print("{s}", .{languageDisplayName(target_lang)});
    }
    try w.writeAll("\n");
    try w.writeAll(term.reset);
    try w.writeAll("\n");

    try w.writeAll(term.bold);
    try w.writeAll("Coverage\n");
    try w.writeAll(term.reset);
    try w.writeAll("───────────────────────────────────────────────────────────────\n");
    try w.print("  Functions:          {d}\n", .{func_count});
    if (issues.len > 0) {
        try w.writeAll(term.bright_red);
        try w.print("  Issues detected:    {d}", .{issues.len});
        try w.writeAll(term.reset);
        try w.writeAll("\n");
    } else {
        try w.print("  Issues detected:    {d}\n", .{issues.len});
    }

    var actionable: usize = 0;
    var critical_count: usize = 0;
    var high_count: usize = 0;
    var medium_count: usize = 0;
    var low_count: usize = 0;
    var kind_counts = std.EnumMap(IssueKind, usize){};
    for (issues) |issue| {
        const entry = kind_counts.getPtr(issue.kind);
        if (entry) |e| e.* += 1;
        switch (issue.severity) {
            .critical => {
                critical_count += 1;
                actionable += 1;
            },
            .high => {
                high_count += 1;
                actionable += 1;
            },
            .medium => medium_count += 1,
            .low => low_count += 1,
        }
    }
    if (actionable > 0) {
        try w.writeAll(term.yellow);
        try w.print("  Actionable:         {d}", .{actionable});
        try w.writeAll(term.reset);
        try w.writeAll("\n");
    } else {
        try w.print("  Actionable:         {d}\n", .{actionable});
    }
    try w.writeAll("\n");

    if (issues.len == 0) {
        try w.writeAll(term.bold);
        try w.writeAll("Findings\n");
        try w.writeAll(term.reset);
        try w.writeAll("───────────────────────────────────────────────────────────────\n");
        try w.writeAll(term.green);
        try w.writeAll(term.bold);
        try w.writeAll("  ✓ No issues detected.\n");
        try w.writeAll(term.reset);
        try w.writeAll("\n");
    } else {
        try w.writeAll(term.bold);
        try w.writeAll("Findings\n");
        try w.writeAll(term.reset);
        try w.writeAll("───────────────────────────────────────────────────────────────\n");

        var first_kind = true;
        var it = kind_counts.iterator();
        while (it.next()) |entry| {
            if (entry.value.* == 0) continue;
            if (!first_kind) try w.writeAll(", ");
            first_kind = false;
            try w.print("{s}: {d}", .{ @tagName(entry.key), entry.value.* });
        }
        if (!first_kind) try w.writeAll("\n");

        if (critical_count > 0) {
            try w.writeAll(term.bright_red);
            try w.print("  Critical: {d}", .{critical_count});
            try w.writeAll(term.reset);
            try w.writeAll("\n");
        }
        if (high_count > 0) {
            try w.writeAll(term.bright_yellow);
            try w.print("  High:     {d}", .{high_count});
            try w.writeAll(term.reset);
            try w.writeAll("\n");
        }
        if (medium_count > 0) {
            try w.writeAll(term.bright_cyan);
            try w.print("  Medium:   {d}", .{medium_count});
            try w.writeAll(term.reset);
            try w.writeAll("\n");
        }
        if (low_count > 0) {
            try w.writeAll(term.dim);
            try w.print("  Low:      {d}", .{low_count});
            try w.writeAll(term.reset);
            try w.writeAll("\n");
        }
        try w.writeAll("\n");

        for (issues, 0..) |issue, idx| {
            const sev_color = term.colorForSeverity(@intFromEnum(issue.severity));
            const sev_tag = switch (issue.severity) {
                .critical => "CRITICAL",
                .high => "HIGH",
                .medium => "MEDIUM",
                .low => "LOW",
            };

            try w.writeAll(sev_color);
            try w.writeAll(term.bold);
            try w.print("  [{s}] OMI-{d:0>3}", .{ sev_tag, idx + 1 });
            try w.writeAll(term.reset);
            try w.writeAll("\n");

            try w.writeAll(term.dim);
            try w.print("    Type:       ", .{});
            try w.writeAll(term.reset);
            try w.writeAll(term.cyan);
            try w.print("{s}\n", .{@tagName(issue.kind)});
            try w.writeAll(term.reset);

            try w.writeAll(term.dim);
            try w.print("    Confidence: ", .{});
            try w.writeAll(term.reset);
            try w.print("{s} ({d:.0}%)\n", .{ issue.confidence_level.toString(), issue.confidence * 100 });

            try w.writeAll(term.dim);
            try w.print("    Function:   ", .{});
            try w.writeAll(term.reset);
            try w.writeAll(term.white);
            try w.print("{s}\n", .{issue.location.func});
            try w.writeAll(term.reset);

            if (issue.ffi_boundary) |bnd| {
                const caller = @tagName(bnd.caller_language);
                const callee = @tagName(bnd.callee_language);
                const is_unknown = std.mem.eql(u8, caller, "unknown") and std.mem.eql(u8, callee, "unknown");
                if (!is_unknown) {
                    try w.writeAll(term.dim);
                    try w.print("    Language:   ", .{});
                    try w.writeAll(term.reset);
                    try w.writeAll(term.bright_cyan);
                    try w.print("{s}", .{caller});
                    try w.writeAll(term.reset);
                    try w.writeAll(term.dim);
                    try w.writeAll(" → ");
                    try w.writeAll(term.reset);
                    try w.writeAll(term.bright_cyan);
                    try w.print("{s}\n", .{callee});
                    try w.writeAll(term.reset);
                }
            }

            if (issue.reason.len > 0) {
                try w.writeAll(term.dim);
                try w.print("    Reason:     ", .{});
                try w.writeAll(term.reset);
                try w.print("{s}\n", .{issue.reason});
            }
            if (issue.message.len > 0 and !std.mem.eql(u8, issue.message, issue.reason)) {
                try w.writeAll(term.dim);
                try w.print("    Detail:     ", .{});
                try w.writeAll(term.reset);
                try w.print("{s}\n", .{issue.message});
            }

            if (issue.semantic_surface) |surface| {
                try w.writeAll(term.dim);
                try w.print("    Surface:    ", .{});
                const surf_color = switch (surface) {
                    .boundary, .ffi_producer => term.green,
                    .reachable_from_boundary => term.bright_cyan,
                    .internal_core => term.yellow,
                    .runtime_internal, .unknown => term.red,
                };
                try w.writeAll(surf_color);
                try w.print("{s}", .{surface.name()});
                try w.writeAll(term.reset);
                if (issue.escape_evidence) |esc| {
                    try w.writeAll(term.dim);
                    try w.print(" (escape={s})", .{@tagName(esc)});
                }
                try w.writeAll("\n");
                try w.writeAll(term.reset);
            }
            if (issue.explained_safe) {
                try w.writeAll(term.dim);
                try w.print("    Status:     ", .{});
                try w.writeAll(term.green);
                try w.writeAll("explained-safe (downgraded by semantic gating)\n");
                try w.writeAll(term.reset);
            }

            if (issue.severity == .critical or issue.severity == .high) {
                if (issue.trace) |trace| {
                    if (trace.len > 0) {
                        try w.writeAll(term.magenta);
                        try w.writeAll(term.bold);
                        try w.writeAll("    ┌─ Detection Path ──\n");
                        try w.writeAll(term.reset);
                        for (trace, 0..) |entry, step_idx| {
                            const is_last = (step_idx == trace.len - 1);
                            const connector = if (is_last) "└──" else "├──";
                            const arrow = if (is_last) "✗" else "│";
                            try w.writeAll(term.dim);
                            try w.print("    {s} [{d}]", .{ connector, step_idx + 1 });
                            try w.writeAll(term.reset);
                            try w.print(" {s}", .{entry.description});

                            if (entry.location) |loc| {
                                if (loc.file) |fname| {
                                    try w.writeAll(term.dim);
                                    try w.print(" @{s}:{d}", .{ fname, loc.line });
                                } else {
                                    try w.writeAll(term.dim);
                                    try w.print(" @:{d}", .{loc.line});
                                }
                            }
                            if (is_last) {
                                try w.writeAll("  ");
                                try w.writeAll(term.bright_red);
                                try w.writeAll(arrow);
                                try w.writeAll(term.reset);
                            }
                            try w.writeAll("\n");
                        }
                        try w.writeAll(term.magenta);
                        try w.writeAll("    └──────────────────\n");
                        try w.writeAll(term.reset);
                    }
                }

                try writeCallGraph(w, allocator, issue);

                if (issue.ffi_boundary) |bnd| {
                    try w.writeAll(term.magenta);
                    try w.writeAll(term.bold);
                    try w.writeAll("    ┌─ FFI Context ──\n");
                    try w.writeAll(term.reset);
                    try w.writeAll(term.dim);
                    try w.print("      Function:  ", .{});
                    try w.writeAll(term.reset);
                    try w.writeAll(term.white);
                    try w.print("{s}\n", .{bnd.function_name});
                    try w.writeAll(term.reset);
                    try w.writeAll(term.dim);
                    try w.print("      Call:      ", .{});
                    try w.writeAll(term.reset);
                    try w.writeAll(term.cyan);
                    try w.print("{s}", .{@tagName(bnd.caller_language)});
                    try w.writeAll(term.dim);
                    try w.writeAll(" -> ");
                    try w.writeAll(term.reset);
                    try w.writeAll(term.cyan);
                    try w.print("{s}\n", .{@tagName(bnd.callee_language)});
                    try w.writeAll(term.reset);
                    try w.writeAll(term.dim);
                    try w.print("      Kind:      ", .{});
                    try w.writeAll(term.reset);
                    try w.writeAll(term.yellow);
                    try w.print("{s}\n", .{@tagName(bnd.kind)});
                    try w.writeAll(term.reset);
                    if (bnd.location.file) |f| {
                        try w.writeAll(term.dim);
                        try w.print("      Location:  ", .{});
                        try w.writeAll(term.reset);
                        try w.print("{s}:{d}\n", .{ f, bnd.location.line });
                    }
                    try w.writeAll(term.magenta);
                    try w.writeAll("    └────────────────\n");
                    try w.writeAll(term.reset);
                }
            } else if (issue.severity == .medium) {
                if (issue.trace) |trace| {
                    if (trace.len > 0) {
                        try w.writeAll(term.bright_cyan);
                        try w.writeAll("    ── Detection Summary ──\n");
                        try w.writeAll(term.reset);
                        if (trace.len == 1) {
                            try w.print("      {s}\n", .{trace[0].description});
                        } else {
                            try w.writeAll(term.dim);
                            try w.print("      Start: ", .{});
                            try w.writeAll(term.reset);
                            try w.print("{s}\n", .{trace[0].description});
                            try w.writeAll(term.dim);
                            try w.print("      End:   ", .{});
                            try w.writeAll(term.reset);
                            try w.print("{s}\n", .{trace[trace.len - 1].description});
                            if (trace.len > 2) {
                                try w.writeAll(term.dim);
                                try w.print("      (+ {d} more steps, use --debug for full trace)\n", .{trace.len - 2});
                                try w.writeAll(term.reset);
                            }
                        }
                    }
                }
            }

            try w.writeAll("\n");
        }
    }

    try w.writeAll(term.bold);
    try w.writeAll("Summary\n");
    try w.writeAll(term.reset);
    try w.writeAll("───────────────────────────────────────────────────────────────\n");
    if (critical_count > 0) {
        try w.writeAll(term.bright_red);
        try w.writeAll(term.bold);
        try w.print("  ⚠ {d} CRITICAL issue(s) require immediate attention.\n", .{critical_count});
        try w.writeAll(term.reset);
    } else if (high_count > 0) {
        try w.writeAll(term.bright_yellow);
        try w.print("  ⚡ {d} high-severity issue(s) found.\n", .{high_count});
        try w.writeAll(term.reset);
    } else if (medium_count > 0) {
        try w.writeAll(term.bright_cyan);
        try w.print("  ○ {d} medium-severity issue(s) found. Review recommended.\n", .{medium_count});
        try w.writeAll(term.reset);
    } else if (low_count > 0) {
        try w.writeAll(term.dim);
        try w.print("  · {d} low-severity finding(s). No immediate action required.\n", .{low_count});
        try w.writeAll(term.reset);
    } else {
        try w.writeAll(term.green);
        try w.writeAll(term.bold);
        try w.writeAll("  ✓ No issues detected. Analysis clean.\n");
        try w.writeAll(term.reset);
    }
    try w.writeAll(term.dim);
    try w.print("  Analysis time: {d} ms\n", .{time_ms});
    try w.writeAll(term.reset);
    try w.writeAll("  (use --verbose for pipeline metrics, --debug for full trace)\n");
    try w.writeAll("═══════════════════════════════════════════════════════════════\n");

    return buf.toOwnedSlice(allocator);
}

fn formatIssuesAsJson(allocator: std.mem.Allocator, issues: []const Issue, func_count: usize, time_ms: u64) ![]u8 {
    var buf = std.ArrayList(u8).initCapacity(allocator, 2048) catch return error.OutOfMemory;
    defer buf.deinit(allocator);
    const w = buf.writer(allocator);

    try w.writeAll("{\n");
    try w.print("  \"version\": \"0.2.0\",\n", .{});
    try w.print("  \"function_count\": {d},\n", .{func_count});
    try w.print("  \"issue_count\": {d},\n", .{issues.len});
    try w.print("  \"analysis_time_ms\": {d},\n", .{time_ms});
    try w.writeAll("  \"issues\": [\n");

    for (issues, 0..) |issue, idx| {
        try w.writeAll("    {\n");
        try w.print("      \"id\": \"OMI-{d:0>3}\",\n", .{idx + 1});
        try w.print("      \"kind\": \"{s}\",\n", .{@tagName(issue.kind)});
        try w.print("      \"severity\": \"{s}\",\n", .{@tagName(issue.severity)});
        try w.print("      \"confidence\": {d:.2},\n", .{issue.confidence});
        try w.writeAll("      \"location\": {\n");
        try w.print("        \"function\": \"", .{});
        try writeJsonEscaped(w, issue.location.func);
        try w.writeAll("\",\n");
        if (issue.location.file) |f| {
            try w.print("        \"file\": \"", .{});
            try writeJsonEscaped(w, f);
            try w.writeAll("\",\n");
            try w.print("        \"line\": {d}\n", .{issue.location.line});
        } else {
            try w.print("        \"line\": {d}\n", .{issue.location.line});
        }
        try w.writeAll("      },\n");
        try w.writeAll("      \"reason\": \"");
        try writeJsonEscaped(w, issue.reason);
        try w.writeAll("\"");
        const has_message = issue.message.len > 0 and !std.mem.eql(u8, issue.message, issue.reason);
        const has_boundary = issue.ffi_boundary != null;
        if (has_message or has_boundary) {
            try w.writeAll(",");
        }
        try w.writeAll("\n");
        if (has_message) {
            try w.writeAll("      \"message\": \"");
            try writeJsonEscaped(w, issue.message);
            try w.writeAll("\"");
            if (has_boundary) {
                try w.writeAll(",");
            }
            try w.writeAll("\n");
        }
        if (issue.ffi_boundary) |bnd| {
            try w.writeAll("      \"ffi_boundary\": {\n");
            try w.print("        \"function_name\": \"", .{});
            try writeJsonEscaped(w, bnd.function_name);
            try w.writeAll("\",\n");
            try w.print("        \"caller_language\": \"{s}\",\n", .{@tagName(bnd.caller_language)});
            try w.print("        \"callee_language\": \"{s}\",\n", .{@tagName(bnd.callee_language)});
            try w.print("        \"kind\": \"{s}\"\n", .{@tagName(bnd.kind)});
            try w.writeAll("      }\n");
        }
        if (idx < issues.len - 1) {
            try w.writeAll("    },\n");
        } else {
            try w.writeAll("    }\n");
        }
    }

    try w.writeAll("  ]\n");
    try w.writeAll("}\n");

    return buf.toOwnedSlice(allocator);
}

fn writeCallGraph(w: anytype, allocator: std.mem.Allocator, issue: Issue) !void {
    _ = allocator;
    if (issue.trace) |trace| {
        if (trace.len < 2) return;
        try w.writeAll(term.dim);
        try w.writeAll(term.bold);
        try w.writeAll("    ┌─ Call Graph ──\n");
        try w.writeAll(term.reset);
        for (trace, 0..) |entry, idx| {
            const prefix = if (idx == trace.len - 1) "└──" else "├──";
            try w.writeAll(term.dim);
            try w.print("    {s} ", .{prefix});
            try w.writeAll(term.reset);
            try w.print("{s}", .{entry.description});
            if (entry.location) |loc| {
                if (loc.file) |f| {
                    try w.writeAll(term.dim);
                    try w.print(" @{s}:{d}", .{ f, loc.line });
                } else {
                    try w.writeAll(term.dim);
                    try w.print(" @:{d}", .{loc.line});
                }
            }
            try w.writeAll("\n");
        }
        try w.writeAll(term.magenta);
        try w.writeAll("    └─────────────\n");
        try w.writeAll(term.reset);
    }
}
