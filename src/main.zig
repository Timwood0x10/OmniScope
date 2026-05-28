const std = @import("std");
const Allocator = std.mem.Allocator;
const OmniScope = @import("OmniScope");
const Pipeline = OmniScope.pipeline.Pipeline;
const call_graph = OmniScope.cross_lang;
const llvm_safe = OmniScope.ir.llvm_safe;
const IRLoader = OmniScope.engine.IRLoader;
const FunctionRef = OmniScope.ir.view.FunctionRef;
const SarifOutput = OmniScope.output.SarifOutput;
const Issue = OmniScope.diag.Issue;
const IssueKind = OmniScope.diag.IssueKind;
const Location = OmniScope.diag.Location;
const Severity = OmniScope.diag.Severity;
const log = OmniScope.log;
const writeJsonEscaped = OmniScope.output.writeJsonEscaped;

const main_config = @import("./types/main_config.zig");
const term = main_config.term;
const Config = main_config.Config;
const OutputFormat = main_config.OutputFormat;

const GraphKind = @import("./visual/graph_visualizer.zig").GraphKind;

pub const AnalyzeResult = struct {
    issues: []const Issue,
    func_count: usize,
    fact_count: usize,
    time_ms: u64,
    _pipeline: Pipeline,
};

fn registerAllPasses(pipeline: *Pipeline) !void {
    // Foundation passes (required by analysis passes)
    try pipeline.registerPass(OmniScope.cross_lang.CFGPass);
    try pipeline.registerPass(OmniScope.cross_lang.DFGPass);
    try pipeline.registerPass(OmniScope.cross_lang.AliasPass);

    // Surface classification — runs early to populate function_surface map
    // for all downstream passes to use instead of per-function noise_filter calls.
    try pipeline.registerPass(OmniScope.cross_lang.SurfaceClassifierPass);

    // Semantic resolution pass — applies language-specific patterns to resolve
    // ownership and safety semantics before heavy analysis
    try pipeline.registerPass(OmniScope.cross_lang.SemanticResolverPass);

    // Independent pre-passes (no deps — run before CallGraph for early exit support)
    try pipeline.registerPass(OmniScope.cross_lang.MallocCheckPass);
    try pipeline.registerPass(OmniScope.cross_lang.BufferOverflowPass);
    try pipeline.registerPass(OmniScope.cross_lang.IntegerOverflowPass);

    // Core analysis passes
    try pipeline.registerPass(OmniScope.cross_lang.CallGraphPass);
    try pipeline.registerPass(OmniScope.cross_lang.TaintPropagationPass);
    try pipeline.registerPass(OmniScope.cross_lang.FFIBoundaryPass);
    try pipeline.registerPass(OmniScope.cross_lang.FFITypeMismatchPass);
    try pipeline.registerPass(OmniScope.cross_lang.FFIBodyCheckPass);
    try pipeline.registerPass(OmniScope.cross_lang.FFIUnsafePass);
    try pipeline.registerPass(OmniScope.cross_lang.PtrLifetimePass);
    try pipeline.registerPass(OmniScope.cross_lang.DangerSurfacePass);
    try pipeline.registerPass(OmniScope.cross_lang.PointerOwnershipPass);
    try pipeline.registerPass(OmniScope.cross_lang.CallbackEscapePass);
    try pipeline.registerPass(OmniScope.cross_lang.RustFfiAuditor);
    try pipeline.registerPass(OmniScope.cross_lang.ReturnCheckPass);
    try pipeline.registerPass(OmniScope.cross_lang.MemorySafetyPass);
    try pipeline.registerPass(OmniScope.cross_lang.FreeValidationPass);

    // Additional analysis passes
    // NOTE: ABIMismatchPass, ThreadCrossingPass are not yet fully implemented
    try pipeline.registerPass(OmniScope.cross_lang.LockPass);
    // try pipeline.registerPass(OmniScope.cross_lang.ABIMismatchPass);
    // try pipeline.registerPass(OmniScope.cross_lang.ThreadCrossingPass);
}

fn runModulePipeline(allocator: std.mem.Allocator, loader: *IRLoader, config: Config) !AnalyzeResult {
    var pipeline = try Pipeline.init(allocator);
    if (loader.getModule()) |module_ref| {
        pipeline.setModule(module_ref);
    }

    // Enable per-pass profiling if --perf-stats flag is set
    if (config.perf_stats) {
        pipeline.setPerfStats(true);
    }

    try registerAllPasses(&pipeline);

    const analysis_start = std.time.milliTimestamp();
    const pipeline_result = try pipeline.runStaticAnalysis();
    const elapsed = std.time.milliTimestamp() - analysis_start;
    const time_ms: u64 = @intCast(@max(0, elapsed));

    const issues = pipeline.getIssues();
    const func_count = loader.getFunctionCount();

    // Pipeline telemetry — only in verbose/debug mode
    log.debug("Analysis complete\n", .{});
    log.debug("Functions processed: {d}\n", .{func_count});
    log.debug("Facts generated: {d}\n", .{pipeline_result.fact_count});
    log.debug("Time: {d}ms\n", .{time_ms});

    return AnalyzeResult{
        .issues = issues,
        .func_count = func_count,
        .fact_count = pipeline_result.fact_count,
        .time_ms = time_ms,
        ._pipeline = pipeline,
    };
}

fn deinitAnalyzeResult(res: *AnalyzeResult) void {
    res._pipeline.deinit();
    res.* = undefined;
}

fn emitOutput(allocator: std.mem.Allocator, issues: []const Issue, func_count: usize, time_ms: u64, config: Config) !void {
    if (config.output_format == .json) {
        const json_output = formatIssuesAsJson(allocator, issues, func_count, time_ms) catch |err| {
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
        var sarif = SarifOutput.init(allocator, "OmniScope", "0.1.9");
        const sarif_output = sarif.generate(issues) catch |err| {
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
        // Text mode: emit structured report
        const report = formatStructuredReport(allocator, issues, func_count, time_ms) catch |err| {
            log.err("Failed to format report: {}\n", .{err});
            return;
        };
        defer allocator.free(report);
        _ = try std.posix.write(std.posix.STDOUT_FILENO, report);
    }
}

/// Format a structured report for text mode.
/// Layout: Findings → Coverage → Summary → Verdict
fn formatStructuredReport(allocator: std.mem.Allocator, issues: []const Issue, func_count: usize, time_ms: u64) ![]u8 {
    var buf = std.ArrayList(u8).initCapacity(allocator, 4096) catch return error.OutOfMemory;
    defer buf.deinit(allocator);
    const w = buf.writer(allocator);

    // ── Header (bold + blue title bar) ──
    try w.writeAll(term.bold);
    try w.writeAll(term.blue);
    try w.writeAll("═══════════════════════════════════════════════════════════════\n");
    try w.writeAll("  OmniScope — Cross-Language Memory Safety Analysis\n");
    try w.writeAll("═══════════════════════════════════════════════════════════════\n");
    try w.writeAll(term.reset);
    try w.writeAll("\n");

    // ── Coverage ──
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

    // Count actionable vs suppressed
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

    // ── Findings ──
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

        // Issue category summary
        var first_kind = true;
        var it = kind_counts.iterator();
        while (it.next()) |entry| {
            if (entry.value.* == 0) continue;
            if (!first_kind) try w.writeAll(", ");
            first_kind = false;
            try w.print("{s}: {d}", .{ @tagName(entry.key), entry.value.* });
        }
        if (!first_kind) try w.writeAll("\n");

        // Severity summary (color-coded)
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

        // Individual issues — color-coded rich format
        for (issues, 0..) |issue, idx| {
            const sev_color = term.colorForSeverity(@intFromEnum(issue.severity));
            const sev_tag = switch (issue.severity) {
                .critical => "CRITICAL",
                .high => "HIGH",
                .medium => "MEDIUM",
                .low => "LOW",
            };

            // ── Issue header card ──
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

            // P19-15: Debug resource contract — show surface classification and downgrade reasons
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

            // Rich context for high-confidence issues: detection path + call graph + FFI boundary
            if (issue.severity == .critical or issue.severity == .high) {

                // ── Detection Path (trace entries as numbered steps) ──
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

                            // Location info
                            if (entry.location) |loc| {
                                if (loc.file) |fname| {
                                    try w.writeAll(term.dim);
                                    try w.print(" @{s}:{d}", .{ fname, loc.line });
                                } else {
                                    try w.writeAll(term.dim);
                                    try w.print(" @:{d}", .{loc.line});
                                }
                            }
                            // Mark last step as the bug location
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

                // ── ASCII Call Graph Visualization ──
                try writeCallGraph(w, allocator, issue);

                // ── FFI Boundary Context ──
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
                // MEDIUM: show trace summary (first + last step only)
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

    // ── Verdict (color-coded summary) ──
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
    try w.print("  \"version\": \"0.1.9\",\n", .{});
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

fn issueToGraphKind(kind: IssueKind) GraphKind {
    return switch (kind) {
        .double_free => .double_free,
        .use_after_free => .use_after_free,
        .null_dereference => .null_dereference,
        .memory_leak => .memory_leak,
        .buffer_overflow => .buffer_overflow,
        .integer_overflow => .other,
        .ffi_type_mismatch, .type_mismatch => .type_mismatch,
        .ffi_unsafe_call => .ffi_unsafe_call,
        .borrow_escape => .borrow_escape,
        .callback_signature_mismatch, .callback_ownership_risk => .callback_signature_mismatch,
        .invalid_free => .invalid_free,
        .unchecked_return => .unchecked_return,
        .malloc_unchecked => .malloc_unchecked,
        .cross_language_leak => .cross_language_leak,
        .cross_language_free => .cross_language_free,
        .format_string => .format_string,
        .command_injection => .command_injection,
        .write_to_immutable => .write_to_immutable,
        .static_buffer_misuse => .static_buffer_misuse,
        else => .other,
    };
}

fn isDangerousFFIPattern(match: *const call_graph.FFIMatch) bool {
    _ = match;
    return true;
}

fn ffiMatchToIssue(match: *const call_graph.FFIMatch) Issue {
    return Issue.init(
        .ffi_unsafe_call,
        "Cross-language FFI boundary detected",
        Location.init(match.name),
        .high,
        0.7,
    );
}

fn runSingleFileAnalysis(allocator: std.mem.Allocator, path: []const u8, config: Config) !void {
    log.debug("=== OmniScope IR Analysis ===\n", .{});
    log.debug("File: {s}\n\n", .{path});

    var loader = IRLoader.loadFile(allocator, path) catch |err| {
        log.err("Failed to load IR file: {s}\n", .{@errorName(err)});
        return err;
    };
    defer loader.deinit();

    log.debug("Loaded: {d} functions\n\n", .{loader.getFunctionCount()});

    var result = try runModulePipeline(allocator, &loader, config);
    defer deinitAnalyzeResult(&result);

    try emitOutput(allocator, result.issues, result.func_count, result.time_ms, config);

    if (config.visualize) {
        try generateVisualization(allocator, result.issues, path);
    }
}

fn generateVisualization(allocator: std.mem.Allocator, issues: []const Issue, path: []const u8) !void {
    const graph_visualizer = @import("./visual/graph_visualizer.zig");
    const GraphIssue = graph_visualizer.GraphIssue;

    var viz = try graph_visualizer.GraphVisualizer.init(allocator);
    defer viz.deinit();

    var graph_issues = try allocator.alloc(GraphIssue, issues.len);
    defer allocator.free(graph_issues);
    for (issues, 0..) |issue, i| {
        graph_issues[i] = .{
            .kind = issueToGraphKind(issue.kind),
            .message = issue.message,
            .function = issue.location.func,
            .severity = @tagName(issue.severity),
            .confidence = issue.confidence,
            .line = issue.location.line,
        };
    }

    const base_name = std.fs.path.stem(path);
    const out_dir = try std.fmt.allocPrint(allocator, "output/{s}", .{base_name});
    defer allocator.free(out_dir);

    std.fs.cwd().makePath(out_dir) catch |err| {
        log.err("Failed to create {s}: {s}", .{ out_dir, @errorName(err) });
        return;
    };
    const mem_html = try std.fmt.allocPrint(allocator, "{s}/memory.html", .{out_dir});
    defer allocator.free(mem_html);
    const mem_json = try std.fmt.allocPrint(allocator, "{s}/memory.json", .{out_dir});
    defer allocator.free(mem_json);

    log.info("Generating memory graph: {s}\n", .{mem_html});
    viz.exportIssuesHtml(graph_issues, mem_json, mem_html) catch |err| {
        log.info("Warning: Failed to generate visualization: {s}\n", .{@errorName(err)});
    };
}

fn runMultiFileAnalysis(allocator: std.mem.Allocator, files: []const []const u8, config: Config) !void {
    log.info("=== OmniScope Multi-File Analysis ===\n\n", .{});
    log.info("[*] Files: {d}\n", .{files.len});

    var loaders = try std.ArrayList(IRLoader).initCapacity(allocator, files.len);
    defer {
        for (loaders.items) |*loader| loader.deinit();
        loaders.deinit(allocator);
    }

    for (files, 0..) |file, i| {
        log.info("  [{d}/{d}] Loading: {s}\n", .{ i + 1, files.len, file });
        var loader = try IRLoader.loadFile(allocator, file);
        errdefer loader.deinit();
        try loaders.append(allocator, loader);
    }
    log.info("[*] All files loaded\n\n", .{});

    var results = try std.ArrayList(AnalyzeResult).initCapacity(allocator, files.len);
    defer {
        for (results.items) |*r| r._pipeline.deinit();
        results.deinit(allocator);
    }

    var total_funcs: usize = 0;
    var total_facts: usize = 0;
    var total_time: u64 = 0;
    var total_issues: usize = 0;

    log.info("[*] Running per-file pipelines...\n", .{});
    for (loaders.items, 0..) |*loader, i| {
        log.info("  [{d}/{d}] Analyzing: {s} ({d} functions)\n", .{ i + 1, loaders.items.len, files[i], loader.getFunctionCount() });
        const result = runModulePipeline(allocator, loader, config) catch |err| {
            log.err("  [{d}/{d}] Analysis FAILED: {}\n", .{ i + 1, loaders.items.len, err });
            continue;
        };
        try results.append(allocator, result);
        total_funcs += result.func_count;
        total_facts += result.fact_count;
        total_time += result.time_ms;
        total_issues += result.issues.len;
    }

    log.info("[*] Per-file pipeline complete: {d} issues from {d} files\n\n", .{ total_issues, files.len });

    log.info("[*] Running cross-language FFI matching...\n", .{});
    const FFIMatcher = call_graph.FFIMatcher;
    const FFIMatcherFunctionInfo = call_graph.FunctionInfo;

    var matcher = try FFIMatcher.init(allocator);
    defer matcher.deinit();

    for (loaders.items) |*loader| {
        const CallbackData = struct {
            matcher_ptr: *FFIMatcher,
            allocator_ptr: Allocator,
            fn process(func_ref: FunctionRef, ctx: *const @This()) anyerror!void {
                const func = llvm_safe.Function{ .raw = func_ref.raw };
                const func_info = try FFIMatcherFunctionInfo.fromFunction(func, ctx.allocator_ptr);
                if (func_info.kind == .declare) {
                    try ctx.matcher_ptr.declare_functions.append(ctx.allocator_ptr, func_info);
                } else if (func_info.kind == .define) {
                    try ctx.matcher_ptr.define_functions.append(ctx.allocator_ptr, func_info);
                }
            }
        };
        const ctx = CallbackData{ .matcher_ptr = &matcher, .allocator_ptr = allocator };
        try loader.iterateFunctions(&ctx, CallbackData.process);
    }

    try matcher.matchFunctions();
    log.info("[*] Found {d} FFI matches\n", .{matcher.matches.items.len});

    var ffi_issues = try std.ArrayList(Issue).initCapacity(allocator, matcher.matches.items.len);
    defer ffi_issues.deinit(allocator);

    if (matcher.matches.items.len > 0) {
        log.info("[*] Scanning {d} FFI matches for vulnerabilities...\n", .{matcher.matches.items.len});
        for (matcher.matches.items) |*match| {
            if (!match.isValid()) continue;
            if (isDangerousFFIPattern(match)) {
                try ffi_issues.append(allocator, ffiMatchToIssue(match));
            }
        }
    }

    const ffi_issue_count = ffi_issues.items.len;

    log.info("\n=== Multi-File Analysis Complete ===\n", .{});
    log.info("Total functions: {d}\n", .{total_funcs});
    log.info("Total facts: {d}\n", .{total_facts});
    log.info("Total time: {d}ms\n", .{total_time});
    log.info("Pipeline issues: {d}\n", .{total_issues});
    log.info("FFI matches: {d}\n", .{matcher.matches.items.len});
    log.info("FFI vulnerabilities: {d}\n", .{ffi_issue_count});
    log.info("Total issues: {d}\n", .{total_issues + ffi_issue_count});

    // Build combined issue list for output — collect slices from each pipeline result + ffi_issues
    var all_slices = try std.ArrayList([]const Issue).initCapacity(allocator, results.items.len + 1);
    defer all_slices.deinit(allocator);
    for (results.items) |*r| all_slices.appendAssumeCapacity(r.issues);
    all_slices.appendAssumeCapacity(ffi_issues.items);

    // Calculate total for output
    const combined_count = total_issues + ffi_issue_count;

    // For JSON output, merge all issues into one contiguous slice
    if (config.output_format == .json or config.output_format == .sarif) {
        var merged = try std.ArrayList(Issue).initCapacity(allocator, combined_count);
        defer merged.deinit(allocator);
        for (all_slices.items) |slice| {
            for (slice) |iss| try merged.append(allocator, iss);
        }
        try emitOutput(allocator, merged.items, total_funcs, total_time, config);
    } else {
        // For text output, report per-file issues
        log.info("Issues detected: {d} in pipeline, {d} FFI\n", .{ total_issues, ffi_issue_count });
    }
}

fn countFunction(func_ref: FunctionRef, count: *usize) !void {
    _ = func_ref;
    count.* += 1;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            if (log.current_log_level != .quiet) {
                std.log.warn("Memory leak detected!\n", .{});
            }
        }
    }

    const allocator = gpa.allocator();

    // C5 FIX: Initialize zone_classifier cache
    OmniScope.semantics.initZoneCache(allocator);
    defer OmniScope.semantics.deinitZoneCache();

    var config = try main_config.parseArgs(allocator);
    defer config.deinit(allocator);

    if (config.quiet) {
        log.setLogLevel(.quiet);
    } else if (config.debug) {
        log.setLogLevel(.debug);
    } else if (config.verbose) {
        log.setLogLevel(.verbose);
    } else {
        log.setLogLevel(.normal);
    }

    if (config.show_help) {
        main_config.showHelp();
        return;
    }

    if (config.show_version) {
        log.info("OmniScope v0.1.9\n", .{});
        return;
    }

    if (config.input_files.items.len == 0) {
        log.info("Error: No input file specified\n", .{});
        return error.NoInputFile;
    }

    if (config.input_files.items.len == 1) {
        try runSingleFileAnalysis(allocator, config.input_files.items[0], config);
    } else {
        try runMultiFileAnalysis(allocator, config.input_files.items, config);
    }
}

test "Config - init and deinit" {
    var config = Config.init(std.testing.allocator);
    defer config.deinit(std.testing.allocator);

    try std.testing.expect(!config.show_help);
    try std.testing.expect(!config.show_version);
    try std.testing.expectEqual(@as(usize, 0), config.input_files.items.len);
}

test "parseArgs - help flag" {
    const config = try main_config.parseArgs(std.testing.allocator);
    defer config.deinit(std.testing.allocator);

    try std.testing.expect(!config.show_help);
}

test "parseArgs - no input files" {
    const config = try main_config.parseArgs(std.testing.allocator);
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), config.input_files.items.len);
}
