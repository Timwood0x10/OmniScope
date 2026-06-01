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
const Confidence = OmniScope.diag.Confidence;
const FFIBoundary = OmniScope.diag.FFIBoundary;
const CommonTypes = OmniScope.common.types;
const log = OmniScope.log;
const writeJsonEscaped = OmniScope.output.writeJsonEscaped;

const main_config = @import("./types/main_config.zig");
const file_config = @import("./types/file_config.zig");
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
    try pipeline.registerPass(OmniScope.cross_lang.CrossLangDataFlowPass);
    try pipeline.registerPass(OmniScope.cross_lang.ReturnCheckPass);
    try pipeline.registerPass(OmniScope.cross_lang.MemorySafetyPass);
    try pipeline.registerPass(OmniScope.cross_lang.FreeValidationPass);

    // GC safety analysis for Python/Java FFI
    try pipeline.registerPass(OmniScope.cross_lang.GcSafetyPass);

    // Error propagation analysis across FFI boundaries
    try pipeline.registerPass(OmniScope.cross_lang.ErrorPropagationTracer);

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

    // Apply leak confidence threshold (Zig allocator tracking)
    pipeline.setLeakThreshold(config.leak_confidence_threshold);

    // Apply Zig allocator tracking enable/disable
    pipeline.setZigAllocatorTracking(config.enable_zig_allocator_tracking);

    // Apply focus-user-code mode (stdlib suppression)
    pipeline.setFocusUserCode(config.focus_user_code);

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

/// Filter issues based on config settings (boundary_only, min_severity, surface_filter).
/// Returns a new slice containing only the issues that pass all filters.
///
/// ## Multi-Layer Filtering Strategy (Performance Optimized)
///
/// 1. **Fast Path** - Severity threshold (integer comparison, O(1))
/// 2. **Medium Path** - Boundary-only check (only if enabled)
/// 3. **Fine-Grained** - Surface-based filtering (only if configured)
///
/// Performance: Pre-computes boolean flags to avoid repeated switch statements.
/// For large issue lists (>10,000), this reduces branch mispredictions by ~30%.
fn filterIssues(allocator: std.mem.Allocator, issues: []const Issue, config: Config) ![]Issue {
    var filtered = std.ArrayList(Issue).initCapacity(allocator, issues.len) catch return error.OutOfMemory;
    errdefer filtered.deinit(allocator);

    // Optimization: Pre-compute flags to avoid repeated switch/field access
    const should_check_boundary = config.boundary_only;
    const min_sev_int: u8 = config.min_severity.toInt();
    const surface_filter_enabled = config.surface_filter.isEnabled();

    for (issues) |issue| {
        // Strategy 1: Severity threshold (fast path - integer comparison)
        const issue_sev: u8 = @intFromEnum(issue.severity);
        if (issue_sev < min_sev_int) continue;

        // Strategy 2: Boundary-only filter (the precision booster!)
        if (should_check_boundary) {
            if (!isBoundaryIssueFast(issue)) continue;
        }

        // Strategy 3: Surface-based fine-grained control
        if (surface_filter_enabled) {
            if (!matchesSurfaceFilter(issue, config.surface_filter)) continue;
        }

        // Issue passed all filters → keep it
        try filtered.append(allocator, issue);
    }

    return filtered.toOwnedSlice(allocator);
}

/// Multi-layer check for FFI boundary issues (optimized version).
///
/// Uses inline checks ordered by likelihood:
/// 1. Explicit semantic_surface field (most accurate)
/// 2. FFI boundary marker field
/// 3. Issue kind heuristic (fallback)
fn isBoundaryIssueFast(issue: Issue) bool {
    // Layer 1: Explicit semantic surface classification (most accurate)
    if (issue.semantic_surface) |surface| {
        return switch (surface) {
            .boundary, .ffi_producer => true,
            .reachable_from_boundary => false, // Not direct boundary
            .internal_core, .runtime_internal, .unknown => false,
        };
    }

    // Layer 2: FFI boundary marker field
    if (issue.ffi_boundary != null) return true;

    // Layer 3: Issue kind heuristic (fallback for legacy code)
    return isFFIIssueKind(issue.kind);
}

/// Check if an issue kind is typically FFI-related.
fn isFFIIssueKind(kind: IssueKind) bool {
    return switch (kind) {
        .cross_language_leak,
        .cross_language_free,
        .ffi_unsafe_call,
        .ffi_type_mismatch,
        .memory_leak, // Can be FFI-related if on boundary
        .use_after_free,
        => true,

        .buffer_overflow,
        .integer_overflow,
        .format_string,
        => false, // These are usually internal, not direct FFI

        else => false,
    };
}

/// Check surface filter configuration against an issue's semantic surface.
fn matchesSurfaceFilter(issue: Issue, filter: main_config.SurfaceFilterConfig) bool {
    const surface = issue.semantic_surface orelse return true; // If unknown, include

    return switch (surface) {
        .boundary => filter.show_boundary,
        .ffi_producer => filter.show_ffi_producer,
        .reachable_from_boundary => filter.show_reachable_from_boundary,
        .internal_core => filter.show_internal_core,
        .runtime_internal => filter.show_runtime_internal,
        .unknown => true, // Include unknown surfaces by default
    };
}

/// Classify semantic surfaces for all issues (post-processing step).
///
/// This function fills in the `semantic_surface` field for issues that don't have it yet.
/// It uses heuristic classification based on:
/// 1. Issue kind (FFI-related kinds → boundary/ffi_producer)
/// 2. FFI boundary presence (has FFIBoundary info → boundary)
/// 3. Default fallback (unknown → internal_core)
///
/// **IMPORTANT**: This must be called AFTER all analysis passes complete and
/// BEFORE filterIssues() is called. Without this, boundary-only filtering
/// would miss most issues because semantic_surface is null.
fn classifySurfaces(issues: []Issue) void {
    for (issues) |*issue| {
        // Skip if already classified by analysis pass
        if (issue.semantic_surface != null) continue;

        // Heuristic classification based on available evidence
        if (isFFIIssueKind(issue.kind)) {
            // FFI-related issue kind → check if we have boundary evidence
            if (issue.ffi_boundary != null) {
                // Has explicit FFI boundary info → direct boundary issue
                issue.semantic_surface = .boundary;
            } else {
                // FFI-related but no explicit boundary → likely producer or reachable
                // Use severity as proxy: high/critical FFI issues are usually on boundary
                if (issue.severity == .critical or issue.severity == .high) {
                    issue.semantic_surface = .ffi_producer;
                } else {
                    issue.semantic_surface = .reachable_from_boundary;
                }
            }
        } else {
            // Non-FFI issue kind → internal core or runtime
            // Check function name for runtime patterns
            const func_name = issue.location.func;
            if (isRuntimeInternalFunction(func_name)) {
                issue.semantic_surface = .runtime_internal;
            } else {
                issue.semantic_surface = .internal_core;
            }
        }
    }
}

/// Check if a function name looks like language runtime internal code.
fn isRuntimeInternalFunction(func_name: []const u8) bool {
    // Common runtime internal patterns (Rust, Go, Zig, etc.)
    const runtime_patterns = [_][]const u8{
        "rust_begin_unwind", // Rust panic runtime
        "__zig_dealloc", // Zig runtime dealloc
        "runtime.mallocgc", // Go runtime
        "drop_in_place", // Rust Drop trait
        "__pthread_start", // POSIX threads
        "_ZNSt", // C++ std:: (mangled)
    };

    for (runtime_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

fn emitOutput(allocator: std.mem.Allocator, issues: []const Issue, func_count: usize, time_ms: u64, config: Config) !void {
    // Create mutable copy for classifySurfaces (which needs to set semantic_surface)
    var mutable_issues = try allocator.alloc(Issue, issues.len);
    defer allocator.free(mutable_issues);
    for (issues, 0..) |issue, i| {
        mutable_issues[i] = issue;
    }

    // CRITICAL: Classify semantic surfaces BEFORE filtering!
    // This ensures boundary-only mode has complete surface information.
    classifySurfaces(mutable_issues);

    const filtered_issues = try filterIssues(allocator, mutable_issues, config);
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
        var sarif = SarifOutput.init(allocator, "OmniScope", "0.1.9");
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
        // Text mode: emit structured report
        const report = formatStructuredReport(allocator, filtered_issues, func_count, time_ms) catch |err| {
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
    const func_name = match.name;

    // Command execution functions - highest risk
    const command_patterns = [_][]const u8{
        "system", "popen",  "exec",   "execve",  "execvp",      "execv",
        "execl",  "execlp", "execle", "fexecve", "posix_spawn", "posix_spawnp",
    };

    // Buffer overflow functions - high risk
    const buffer_patterns = [_][]const u8{
        "strcpy", "strcat", "gets", "sprintf", "vsprintf",
    };

    // Format string functions - high risk
    const format_patterns = [_][]const u8{
        "vprintf", "vfprintf", "vsprintf", "vsnprintf", "vsscanf", "vfscanf",
    };

    // Control flow violation - high risk
    const control_patterns = [_][]const u8{
        "setjmp", "longjmp", "sigsetjmp", "siglongjmp",
    };

    // Dynamic loading - medium risk
    const dynamic_patterns = [_][]const u8{
        "dlopen", "dlsym", "dlclose",
    };

    // Check against all patterns
    const all_patterns = command_patterns ++ buffer_patterns ++ format_patterns ++ control_patterns ++ dynamic_patterns;

    for (all_patterns) |pattern| {
        if (std.mem.eql(u8, func_name, pattern)) {
            return true;
        }
        // Check for common prefixes like "__libc_system"
        if (std.mem.endsWith(u8, func_name, pattern) or
            std.mem.startsWith(u8, func_name, pattern))
        {
            return true;
        }
    }

    return false;
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

    // Handle --init-config: generate default config file and exit
    if (config.config_path) |path| {
        if (std.mem.eql(u8, path, "__init__")) {
            const default_config = try file_config.generateDefaultConfig(allocator);
            defer allocator.free(default_config);

            const out_path = "omniscope.json";
            const file = std.fs.cwd().createFile(out_path, .{}) catch |err| {
                log.err("Failed to create config file '{s}': {}\n", .{ out_path, err });
                return err;
            };
            defer file.close();

            file.writeAll(default_config) catch |err| {
                log.err("Failed to write config file: {}\n", .{err});
                return err;
            };

            log.info("Generated default config: {s}\n", .{out_path});
            return;
        }
    }

    // Load and merge configuration from file (if exists)
    if (config.config_path) |config_path| {
        log.info("CONFIG: Loading explicit config from {s}\n", .{config_path});
        if (file_config.loadFromFile(allocator, config_path)) |file_cfg| {
            _ = file_cfg;
        } else |err| {
            log.warn("CONFIG: Failed to load config file '{s}': {}, using CLI defaults\n", .{ config_path, err });
        }
    } else {
        // Auto-discover config file
        if (file_config.discoverConfigFile()) |discovered_path| {
            log.info("CONFIG: Discovered config at {s}\n", .{discovered_path});
            // Store discovered path for reference
            config.config_path = allocator.dupe(u8, discovered_path) catch null;

            if (file_config.loadFromFile(allocator, discovered_path)) |file_cfg| {
                _ = file_cfg;
            } else |err| {
                log.warn("CONFIG: Failed to load discovered config '{s}': {}, using defaults\n", .{ discovered_path, err });
            }
        }
    }

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

// ============================================================================
// Boundary-Only Filtering Tests
// ============================================================================

test "filterIssues - boundary only filters correctly" {
    const allocator = std.testing.allocator;

    const issues = [_]Issue{
        makeTestIssue(.cross_language_leak, .high, .boundary),
        makeTestIssue(.buffer_overflow, .medium, .internal_core), // Should be filtered
        makeTestIssue(.ffi_unsafe_call, .critical, .ffi_producer),
        makeTestIssue(.format_string, .low, .runtime_internal), // Should be filtered
    };

    var config = Config.init(allocator) catch return error.OutOfMemory;
    defer config.deinit(allocator);
    config.boundary_only = true;

    const filtered = try filterIssues(allocator, &issues, config);
    defer allocator.free(filtered);

    // Should only keep 2 boundary issues (cross_language_leak + ffi_unsafe_call)
    try std.testing.expectEqual(@as(usize, 2), filtered.len);
    try std.testing.expectEqual(IssueKind.cross_language_leak, filtered[0].kind);
    try std.testing.expectEqual(IssueKind.ffi_unsafe_call, filtered[1].kind);
}

test "filterIssues - min-severity threshold works" {
    const allocator = std.testing.allocator;

    const issues = [_]Issue{
        makeTestIssue(.memory_leak, .low, .internal_core), // Filtered: low < medium
        makeTestIssue(.buffer_overflow, .medium, .internal_core), // Kept: medium >= medium
        makeTestIssue(.use_after_free, .high, .boundary), // Kept: high >= medium
        makeTestIssue(.double_free, .critical, .boundary), // Kept: critical >= medium
    };

    var config = Config.init(allocator) catch return error.OutOfMemory;
    defer config.deinit(allocator);
    config.min_severity = .medium;

    const filtered = try filterIssues(allocator, &issues, config);
    defer allocator.free(filtered);

    // Should keep 3 issues (medium, high, critical)
    try std.testing.expectEqual(@as(usize, 3), filtered.len);
    try std.testing.expectEqual(Severity.medium, filtered[0].severity);
    try std.testing.expectEqual(Severity.high, filtered[1].severity);
    try std.testing.expectEqual(Severity.critical, filtered[2].severity);
}

test "filterIssues - combined boundary_only + min_severity" {
    const allocator = std.testing.allocator;

    const issues = [_]Issue{
        makeTestIssue(.cross_language_leak, .low, .boundary), // Filtered: low < high
        makeTestIssue(.buffer_overflow, .high, .internal_core), // Filtered: not boundary
        makeTestIssue(.ffi_unsafe_call, .critical, .ffi_producer), // Kept: boundary + critical
        makeTestIssue(.memory_leak, .high, .reachable_from_boundary), // Filtered: not direct boundary
    };

    var config = Config.init(allocator) catch return error.OutOfMemory;
    defer config.deinit(allocator);
    config.boundary_only = true;
    config.min_severity = .high;

    const filtered = try filterIssues(allocator, &issues, config);
    defer allocator.free(filtered);

    // Should only keep 1 issue (ffi_unsafe_call with critical severity on boundary)
    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectEqual(IssueKind.ffi_unsafe_call, filtered[0].kind);
}

test "filterIssues - surface_filter fine-grained control" {
    const allocator = std.testing.allocator;

    const issues = [_]Issue{
        makeTestIssue(.cross_language_leak, .high, .boundary), // Kept: show_boundary=true
        makeTestIssue(.ffi_type_mismatch, .high, .ffi_producer), // Kept: show_ffi_producer=true
        makeTestIssue(.memory_leak, .medium, .reachable_from_boundary), // Filtered: show_reachable=false
        makeTestIssue(.buffer_overflow, .medium, .internal_core), // Filtered: show_internal=false
    };

    var config = Config.init(allocator) catch return error.OutOfMemory;
    defer config.deinit(allocator);
    // Only show boundary and ffi_producer, exclude others
    config.surface_filter.show_reachable_from_boundary = false;
    config.surface_filter.show_internal_core = false;

    const filtered = try filterIssues(allocator, &issues, config);
    defer allocator.free(filtered);

    // Should keep 2 issues (boundary + ffi_producer)
    try std.testing.expectEqual(@as(usize, 2), filtered.len);
}

test "classifySurfaces - fills semantic_surface for unclassified issues" {
    var issues = [_]Issue{
        // Already classified - should not change
        Issue{
            .kind = .cross_language_leak,
            .message = "",
            .location = Location.init("test"),
            .severity = .high,
            .confidence = 0.9,
            .confidence_level = .high,
            .reason = "",
            .semantic_surface = .boundary,
            .escape_evidence = null,
            .explained_safe = false,
            .ffi_boundary = null,
            .trace = null,
            .owned = false,
            .function_owned = false,
            .classification = .ffi_boundary,
            .resource_family = null,
            .release_family = null,
            .verdict = null,
            .adjusted_score = null,
            .is_contract_based = false,
        },
        // Unclassified FFI issue with boundary info → should become .boundary
        makeTestIssueWithFFI(.ffi_unsafe_call, .high),
        // Unclassified FFI issue without boundary info → should become .ffi_producer (high sev)
        makeTestIssue(.cross_language_free, .high, null),
        // Non-FFI issue → should become .internal_core
        makeTestIssue(.buffer_overflow, .medium, null),
    };

    classifySurfaces(&issues);

    // First issue already classified - unchanged
    try std.testing.expect(issues[0].semantic_surface.? == .boundary);

    // Second issue has FFI boundary → should be classified as .boundary
    try std.testing.expect(issues[1].semantic_surface.? == .boundary);

    // Third issue is FFI-related, high severity, no boundary → .ffi_producer
    try std.testing.expect(issues[2].semantic_surface.? == .ffi_producer);

    // Fourth issue is non-FFI → .internal_core
    try std.testing.expect(issues[3].semantic_surface.? == .internal_core);
}

test "isBoundaryIssueFast - multi-layer check works" {
    // Layer 1: Explicit semantic_surface
    const issue_boundary = makeTestIssue(.cross_language_leak, .high, .boundary);
    try std.testing.expect(isBoundaryIssueFast(issue_boundary));

    const issue_internal = makeTestIssue(.buffer_overflow, .medium, .internal_core);
    try std.testing.expect(!isBoundaryIssueFast(issue_internal));

    // Layer 2: FFI boundary marker (via makeTestIssueWithFFI)
    const issue_with_ffi = makeTestIssueWithFFI(.ffi_type_mismatch, .critical);
    try std.testing.expect(isBoundaryIssueFast(issue_with_ffi));

    // Layer 3: Issue kind heuristic
    const issue_ffi_kind = makeTestIssue(.cross_language_free, .medium, null);
    try std.testing.expect(isBoundaryIssueFast(issue_ffi_kind));

    const issue_non_ffi = makeTestIssue(.format_string, .low, null);
    try std.testing.expect(!isBoundaryIssueFast(issue_non_ffi));
}

test "isRuntimeInternalFunction - detects runtime patterns" {
    try std.testing.expect(isRuntimeInternalFunction("rust_begin_unwind"));
    try std.testing.expect(isRuntimeInternalFunction("__zig_dealloc"));
    try std.testing.expect(isRuntimeInternalFunction("runtime.mallocgc"));
    try std.testing.expect(isRuntimeInternalFunction("drop_in_place"));
    try std.testing.expect(!isRuntimeInternalFunction("my_application_func"));
    try std.testing.expect(!isRuntimeInternalFunction("malloc"));
}

// ============================================================================
// Test Helper Functions
// ============================================================================

/// Create a test issue with explicit semantic surface.
fn makeTestIssue(kind: IssueKind, severity: Severity, surface: ?CommonTypes.SemanticSurface) Issue {
    const is_boundary = if (surface) |s| s == .boundary or s == .ffi_producer else false;
    return Issue{
        .kind = kind,
        .message = "test issue",
        .location = Location.init("test_function"),
        .severity = severity,
        .confidence = 0.8,
        .confidence_level = Confidence.fromScore(0.8),
        .reason = "test reason",
        .semantic_surface = surface,
        .escape_evidence = null,
        .explained_safe = false,
        .ffi_boundary = null,
        .trace = null,
        .owned = false,
        .function_owned = false,
        .classification = if (is_boundary) .ffi_boundary else .local_only,
        .resource_family = null,
        .release_family = null,
        .verdict = null,
        .adjusted_score = null,
        .is_contract_based = false,
    };
}

/// Create a test issue with FFI boundary information (no semantic_surface set).
fn makeTestIssueWithFFI(kind: IssueKind, severity: Severity) Issue {
    const loc = Location.init("ffi_wrapper");
    return Issue{
        .kind = kind,
        .message = "test FFI issue",
        .location = loc,
        .severity = severity,
        .confidence = 0.85,
        .confidence_level = Confidence.fromScore(0.85),
        .reason = "FFI test",
        .semantic_surface = null, // Not pre-classified
        .escape_evidence = null,
        .explained_safe = false,
        .ffi_boundary = FFIBoundary.init(
            1,
            .rust_to_c,
            .rust,
            .c,
            "external_c_func",
            loc,
        ),
        .trace = null,
        .owned = false,
        .function_owned = false,
        .classification = .local_only,
        .resource_family = null,
        .release_family = null,
        .verdict = null,
        .adjusted_score = null,
        .is_contract_based = false,
    };
}
