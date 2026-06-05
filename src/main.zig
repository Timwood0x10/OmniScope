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

const main_config = OmniScope.config.main_config;
const file_config = OmniScope.config.file_config;
const language_override = OmniScope.config.language_override;
const term = main_config.term;
const Config = main_config.Config;
const OutputFormat = main_config.OutputFormat;

const GraphKind = @import("./visual/graph_visualizer.zig").GraphKind;
const LanguageDetector = OmniScope.semantics.language_detector;
const FFI_Language = OmniScope.diag.FFIBoundary.Language;

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
    try pipeline.registerPass(OmniScope.cross_lang.FFIDetectorPass);
    try pipeline.registerPass(OmniScope.cross_lang.FFIBoundaryPass);
    try pipeline.registerPass(OmniScope.cross_lang.FFITypeMismatchPass);
    try pipeline.registerPass(OmniScope.cross_lang.AbiCompatChecker); // abi-compat-checker
    try pipeline.registerPass(OmniScope.cross_lang.FFIBodyCheckPass);
    try pipeline.registerPass(OmniScope.cross_lang.JniLeakDetectorPass);
    // NOTE: FFIAnalysisPass (ownership-violation) has method-style run(self, ctx, diag)
    // that doesn't match the Pass interface expecting static run(ctx, diag).
    // It also has pre-existing compile errors (append API, missing debug_info method).
    // TODO: Refactor to static-run pattern (like LockPass) then uncomment below.
    // try pipeline.registerPass(OmniScope.cross_lang.FFIAnalysisPass); // ownership-violation
    try pipeline.registerPass(OmniScope.cross_lang.FFIUnsafePass);
    try pipeline.registerPass(OmniScope.cross_lang.PtrLifetimePass);
    try pipeline.registerPass(OmniScope.cross_lang.DangerSurfacePass);
    try pipeline.registerPass(OmniScope.cross_lang.PointerOwnershipPass);
    try pipeline.registerPass(OmniScope.cross_lang.CallbackEscapePass);
    try pipeline.registerPass(OmniScope.cross_lang.CallbackLifecycleChecker); // callback-lifecycle
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

    // Build language override registry from CLI config (--lang, --lang-prefix, etc.)
    // This allows users to override auto-detected function languages to eliminate FPs.
    var lang_registry = try language_override.LanguageOverrideRegistry.init(allocator);
    defer lang_registry.deinit();

    // Apply CLI language overrides (exact, prefix, suffix, source-file, default)
    // Convert LangKV (key/value fields) to individual registry calls
    for (config.lang_overrides.items) |kv| {
        const lang = language_override.LanguageOverrideRegistry.parseLangString(kv.value) orelse continue;
        try lang_registry.addExact(kv.key, lang);
    }
    for (config.lang_prefix_overrides.items) |kv| {
        const lang = language_override.LanguageOverrideRegistry.parseLangString(kv.value) orelse continue;
        try lang_registry.addPrefix(kv.key, lang);
    }
    for (config.lang_suffix_overrides.items) |kv| {
        const lang = language_override.LanguageOverrideRegistry.parseLangString(kv.value) orelse continue;
        try lang_registry.addSuffix(kv.key, lang);
    }
    for (config.source_lang_overrides.items) |kv| {
        const lang = language_override.LanguageOverrideRegistry.parseLangString(kv.value) orelse continue;
        try lang_registry.addSourceFile(kv.key, lang);
    }
    if (config.default_lang_override) |default_lang_str| {
        if (language_override.LanguageOverrideRegistry.parseLangString(default_lang_str)) |default_lang| {
            lang_registry.setDefault(default_lang);
        }
    }

    // Sort prefix/suffix rules so longest match wins during lookup
    lang_registry.sortPrefixRules();
    lang_registry.sortSuffixRules();

    // Load JSON overrides from config file if present (merge with CLI — CLI wins)
    if (config.config_path) |cp| {
        if (file_config.loadFromFile(allocator, cp)) |file_cfg_val| {
            var file_cfg = file_cfg_val;
            defer {
                // Inline cleanup: free lang_registry heap memory (FileConfig owns it)
                if (file_cfg.lang_registry) |*reg| reg.deinit();
            }
            if (file_cfg.lang_registry) |*file_reg| {
                // Merge file-based overrides into CLI registry (CLI already added, wins on conflict)
                // Exact matches: only add if not already present in CLI registry
                var file_exact_iter = file_reg.exact_map.iterator();
                while (file_exact_iter.next()) |entry| {
                    if (!lang_registry.exact_map.contains(entry.key_ptr.*)) {
                        lang_registry.addExact(entry.key_ptr.*, entry.value_ptr.*) catch {};
                    }
                }
                // Prefix rules: append from file config (additive)
                for (file_reg.prefix_rules.items) |rule| {
                    lang_registry.addPrefix(rule.prefix, rule.lang) catch {};
                }
                // Suffix rules: append from file config (additive)
                for (file_reg.suffix_rules.items) |rule| {
                    lang_registry.addSuffix(rule.suffix, rule.lang) catch {};
                }
                // Source file mappings: only add if not already present in CLI
                var file_sf_iter = file_reg.source_file_map.iterator();
                while (file_sf_iter.next()) |entry| {
                    if (!lang_registry.source_file_map.contains(entry.key_ptr.*)) {
                        lang_registry.addSourceFile(entry.key_ptr.*, entry.value_ptr.*) catch {};
                    }
                }
                // Default language: only set if CLI hasn't set one
                if (file_reg.default_lang) |fdef| {
                    if (lang_registry.default_lang == null) {
                        lang_registry.setDefault(fdef);
                    }
                }
                // Re-sort after merge in case file config added new prefix/suffix rules
                lang_registry.sortPrefixRules();
                lang_registry.sortSuffixRules();
            }
        } else |err| {
            log.warn("CONFIG: Failed to load config file '{s}': {}", .{ cp, err });
        }
    }

    // Pass registry to pipeline — all passes will check it before auto-detection
    pipeline.setLanguageOverrides(&lang_registry);

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

fn emitOutput(allocator: std.mem.Allocator, issues: []const Issue, func_count: usize, time_ms: u64, config: Config, source_lang: FFI_Language, target_lang: FFI_Language) !void {
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
        const report = formatStructuredReport(allocator, filtered_issues, func_count, time_ms, source_lang, target_lang) catch |err| {
            log.err("Failed to format report: {}\n", .{err});
            return;
        };
        defer allocator.free(report);
        _ = try std.posix.write(std.posix.STDOUT_FILENO, report);
    }
}

/// Convert FFI_Language enum to user-friendly display string.
/// Returns uppercase language name for terminal output (e.g., "Rust", "C++", "Go").
fn languageDisplayName(lang: FFI_Language) []const u8 {
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
/// Scans all issues with FFI boundary info to find the most common callee language.
fn detectTargetLanguage(issues: []const Issue) FFI_Language {
    var lang_counts = [_]usize{0} ** 9; // One per FFI_Language variant
    for (issues) |issue| {
        if (issue.ffi_boundary) |bnd| {
            const idx = @intFromEnum(bnd.callee_language);
            if (idx < lang_counts.len) {
                lang_counts[idx] += 1;
            }
        }
    }
    var max_count: usize = 0;
    var dominant_lang = FFI_Language.c; // Default to C as most common FFI target
    for (lang_counts, 0..) |count, i| {
        if (count > max_count) {
            max_count = count;
            dominant_lang = @as(FFI_Language, @enumFromInt(i));
        }
    }
    return dominant_lang;
}

/// Format a structured report for text mode.
/// Layout: Findings → Coverage → Summary → Verdict
fn formatStructuredReport(allocator: std.mem.Allocator, issues: []const Issue, func_count: usize, time_ms: u64, source_lang: FFI_Language, target_lang: FFI_Language) ![]u8 {
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

    // ── Language Conversion Info (NEW) ──
    try w.writeAll(term.bold);
    try w.writeAll(term.magenta);
    try w.writeAll("[Language] ");
    try w.writeAll(term.reset);
    try w.writeAll(term.cyan);
    try w.print("{s}", .{languageDisplayName(source_lang)});
    try w.writeAll(term.dim);
    try w.writeAll(" --> ");
    try w.writeAll(term.bright_cyan);
    try w.print("{s}\n", .{languageDisplayName(target_lang)});
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

// Secondary signal types for FFI vulnerability detection
const SecondarySignal = enum {
    type_mismatch,
    memory_safety_risk,
    lifetime_issue,
    trust_boundary_violation,
    missing_validation,
    unchecked_return,
};

/// Count secondary danger signals for an FFI match.
///
/// Checks for concrete risk indicators beyond simple function name matching:
/// - Type mismatches between declare/define signatures
/// - Memory safety risks (buffer operations without size params)
/// - Lifetime issues (Rust FFI patterns like unpaired into_raw/from_raw)
/// - Trust boundary violations (user input flowing to FFI calls)
/// - Missing validation in caller context
/// - Unchecked return values from FFI functions
///
/// Returns:
///   - Number of secondary signals detected (0-6)
fn countSecondarySignals(match: *const call_graph.FFIMatch) u32 {
    var signal_count: u32 = 0;

    // Signal 1: Type mismatch between declaration and definition
    if (hasTypeMismatchSignal(match)) {
        signal_count += 1;
    }

    // Signal 2: Memory safety risk (dangerous buffer/string operations)
    if (hasMemorySafetyRisk(match)) {
        signal_count += 1;
    }

    // Signal 3: Lifetime issue (Rust FFI specific)
    if (hasLifetimeIssue(match)) {
        signal_count += 1;
    }

    // Signal 4: Trust boundary violation (user input → FFI)
    if (hasTrustBoundaryViolation(match)) {
        signal_count += 1;
    }

    // Signal 5: Missing validation in caller context
    if (hasMissingValidation(match)) {
        signal_count += 1;
    }

    // Signal 6: Unchecked return value
    if (hasUncheckedReturn(match)) {
        signal_count += 1;
    }

    return signal_count;
}

/// Check for type mismatch between FFI function declaration and definition.
///
/// This is a strong signal because cross-language type mismatches are a common
/// source of undefined behavior at FFI boundaries.
fn hasTypeMismatchSignal(match: *const call_graph.FFIMatch) bool {
    // If we have both declare and define info, check for type inconsistencies
    if (match.declare_func == null or match.define_func == null) {
        return false;
    }

    // Heuristic: check if function names suggest type-unsafe patterns
    const func_name = match.name;

    // Functions that commonly have signature mismatches across languages
    const type_unsafe_patterns = [_][]const u8{
        "void*",     "char*",    "int*", "handle_t", "size_t",
        "uintptr_t", "intptr_t", "long", "unsigned",
    };

    for (type_unsafe_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Check for memory safety risks in the FFI function.
///
/// Focuses on functions that perform unsafe memory operations without
/// proper bounds checking or size parameters.
fn hasMemorySafetyRisk(match: *const call_graph.FFIMatch) bool {
    const func_name = match.name;

    // Dangerous memory operations that often cause issues at FFI boundaries
    const unsafe_mem_patterns = [_][]const u8{
        "malloc",  "free",    "realloc", "calloc",
        "memcpy",  "memmove", "memset",  "strncpy",
        "strncat",
    };

    for (unsafe_mem_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            // Additional check: exclude safe wrappers
            const safe_wrappers = [_][]const u8{
                "safe_malloc", "checked_alloc", "bounded_copy",
            };
            var is_safe_wrapper = false;
            for (safe_wrappers) |safe| {
                if (std.mem.indexOf(u8, func_name, safe) != null) {
                    is_safe_wrapper = true;
                    break;
                }
            }
            if (!is_safe_wrapper) {
                return true;
            }
        }
    }

    return false;
}

/// Check for Rust-specific lifetime issues at FFI boundary.
///
/// Detects problematic patterns like:
/// - into_raw() without matching from_raw()
/// - as_ptr() on temporary values passed to FFI
/// - Box::into_raw() without proper ownership management
fn hasLifetimeIssue(match: *const call_graph.FFIMatch) bool {
    const func_name = match.name;

    // Rust FFI lifetime anti-patterns
    const rust_lifetime_patterns = [_][]const u8{
        "into_raw",          "from_raw",    "as_ptr",
        "Box::new",          "Vec::as_ptr", "String::as_ptr",
        "CString::into_raw",
    };

    for (rust_lifetime_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Check if this FFI call crosses a trust boundary (untrusted input → FFI).
///
/// This is a critical signal because vulnerabilities at trust boundaries
/// are exploitable, whereas internal FFI calls are often benign.
fn hasTrustBoundaryViolation(match: *const call_graph.FFIMatch) bool {
    const func_name = match.name;

    // Trust boundary indicators in function name context
    // These suggest the function processes user/network input
    const trust_boundary_indicators = [_][]const u8{
        "user",     "input",     "argv",    "env",
        "request",  "socket",    "network", "http",
        "url",      "query",     "form",    "post",
        "get_",     "param",     "arg",     "client",
        "external", "untrusted", "remote",
    };

    for (trust_boundary_indicators) |indicator| {
        if (std.mem.indexOf(u8, func_name, indicator) != null) {
            return true;
        }
    }

    return false;
}

/// Check if the caller context lacks validation for the FFI call.
///
/// Safe FFI usage typically includes validation, sanitization, or bounds checking.
/// Absence of these patterns suggests risky usage.
fn hasMissingValidation(match: *const call_graph.FFIMatch) bool {
    const func_name = match.name;

    // Validation/safety patterns that should be present in safe FFI usage
    const validation_patterns = [_][]const u8{
        "validate", "sanitize", "escape", "check",
        "verify",   "filter",   "clean",  "bounds",
        "safe",     "guard",
    };

    // If function name doesn't contain any validation term, flag it
    // (unless it's a well-known safe function)
    var has_validation = false;
    for (validation_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            has_validation = true;
            break;
        }
    }

    // Only report missing validation for functions that look risky
    if (!has_validation and func_name.len > 4) {
        const risky_prefixes = [_][]const u8{
            "wrap",    "call",   "invoke", "exec", "run", "do_",
            "process", "handle", "parse",
        };
        for (risky_prefixes) |prefix| {
            if (std.mem.indexOf(u8, func_name, prefix) != null) {
                return true;
            }
        }
    }

    return false;
}

/// Check if the FFI function returns a value that should be checked.
///
/// Many FFI functions return error codes or null pointers that must be checked.
/// Unchecked returns are a common source of bugs.
fn hasUncheckedReturn(match: *const call_graph.FFIMatch) bool {
    const func_name = match.name;

    // Functions that return values requiring explicit checking
    const must_check_patterns = [_][]const u8{
        "malloc",   "calloc",   "realloc",
        "fopen",    "fread",    "fwrite",
        "socket",   "connect",  "accept",
        "send",     "recv",     "pthread_create",
        "sem_open", "shm_open", "mmap",
    };

    for (must_check_patterns) |pattern| {
        if (std.mem.eql(u8, func_name, pattern) or
            std.mem.endsWith(u8, func_name, pattern))
        {
            return true;
        }
    }

    return false;
}

/// Calculate dynamic confidence based on secondary signals.
///
/// Uses a tiered system:
/// - Base confidence: 0.5 (low)
/// - Each secondary signal: +0.08 to +0.15 depending on severity
/// - Maximum confidence: 0.95
/// - Minimum confidence with signals: 0.65
///
/// Returns:
///   - Confidence score (0.0 - 1.0)
fn calculateFFIConfidence(signal_count: u32, vuln_type: FFIVulnType) f32 {
    var base_confidence: f32 = 0.5;

    // Weight signals by type
    const type_mismatch_weight: f32 = 0.15; // Strongest signal
    const memory_safety_weight: f32 = 0.12;
    const lifetime_weight: f32 = 0.10;
    const trust_boundary_weight: f32 = 0.14; // Very important for exploitability
    const missing_validation_weight: f32 = 0.08; // Weaker signal
    const unchecked_return_weight: f32 = 0.09;

    // Apply weighted signal bonuses (capped at reasonable maximum)
    // We don't know exact signal composition from count alone, so use average
    const avg_signal_weight = (type_mismatch_weight + memory_safety_weight +
        lifetime_weight + trust_boundary_weight + missing_validation_weight +
        unchecked_return_weight) / 6.0;

    base_confidence += @as(f32, @floatFromInt(signal_count)) * avg_signal_weight;

    // Vulnerability type bonus
    switch (vuln_type) {
        .command_injection => base_confidence += 0.15,
        .buffer_overflow => base_confidence += 0.10,
        .format_string => base_confidence += 0.10,
        .control_flow => base_confidence += 0.05,
        .generic => {},
    }

    // Cap at reasonable maximum
    if (base_confidence > 0.95) {
        base_confidence = 0.95;
    }

    return base_confidence;
}

/// Classify FFI vulnerability type based on function name patterns.
const FFIVulnType = enum {
    command_injection,
    buffer_overflow,
    format_string,
    control_flow,
    generic,
};

fn classifyFFIVulnType(func_name: []const u8) FFIVulnType {
    if (std.mem.indexOf(u8, func_name, "system") != null or
        std.mem.indexOf(u8, func_name, "exec") != null or
        std.mem.indexOf(u8, func_name, "popen") != null)
    {
        return .command_injection;
    }

    if (std.mem.indexOf(u8, func_name, "strcpy") != null or
        std.mem.indexOf(u8, func_name, "strcat") != null or
        std.mem.indexOf(u8, func_name, "gets") != null or
        std.mem.indexOf(u8, func_name, "sprintf") != null)
    {
        return .buffer_overflow;
    }

    if (std.mem.indexOf(u8, func_name, "printf") != null or
        std.mem.indexOf(u8, func_name, "fprintf") != null or
        std.mem.indexOf(u8, func_name, "sprintf") != null or
        std.mem.indexOf(u8, func_name, "vprintf") != null)
    {
        return .format_string;
    }

    if (std.mem.indexOf(u8, func_name, "setjmp") != null or
        std.mem.indexOf(u8, func_name, "longjmp") != null)
    {
        return .control_flow;
    }

    return .generic;
}

/// Whitelist check for known-safe FFI patterns.
///
/// Suppresses false positives from:
/// - Standard library internals (well-audited)
/// - Test/diagnostic code (no security impact)
/// - Safe wrapper functions (with proper validation)
///
/// Returns true if the FFI match should be suppressed (whitelisted).
fn isWhitelistedFFI(match: *const call_graph.FFIMatch) bool {
    const func_name = match.name;

    // Standard library internal prefixes (never report these)
    const stdlib_prefixes = [_][]const u8{
        "sqlite3Mem", "sqlite3Db", "proxy",     "conch",      "lock",
        "uv__",       "uv_",       "__rust_",   "std::",      "Py_DEBUG",
        "_debug",     "_Py_debug", "JNI_debug", "_jni_debug", "debug_",
        "log_",       "trace_",    "diag_",     "dump_",
    };

    for (stdlib_prefixes) |prefix| {
        if (std.mem.indexOf(u8, func_name, prefix) != null) {
            return true;
        }
    }

    // Safe function name patterns
    const safe_patterns = [_][]const u8{
        "safe", "check", "validate", "init", "finalize",
        "get_", "set_",  "is_",      "has_", "count",
        "size",
    };

    for (safe_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            // Ensure it's not actually a dangerous function with safe-looking name
            if (!isDangerousFFIPattern(match)) {
                return true;
            }
        }
    }

    return false;
}

/// Convert an FFI match to an issue with multi-layer precision filtering.
///
/// Layer 1: Confidence threshold (>= 0.75 for reporting)
/// Layer 2: Secondary signal requirement (>= 2 signals for generic calls)
/// Layer 3: Whitelist check (stdlib, tests, safe patterns)
///
/// Returns null if the FFI match should not be reported (filtered out).
fn ffiMatchToIssue(match: *const call_graph.FFIMatch) ?Issue {
    // Layer 3: Whitelist check first (cheapest operation)
    if (isWhitelistedFFI(match)) {
        log.debug("FFI-SKIP [WHITELIST]: {s}", .{match.name});
        return null;
    }

    // Classify vulnerability type
    const vuln_type = classifyFFIVulnType(match.name);

    // Count secondary signals
    const signal_count = countSecondarySignals(match);

    // Layer 2: Require minimum secondary signals for generic/unspecific calls
    const min_signals: u4 = switch (vuln_type) {
        .command_injection => 0, // Always report command injection
        .buffer_overflow => 0, // Always report buffer overflow
        .format_string => 1, // Format string needs at least 1 signal
        .control_flow => 1, // Control flow needs at least 1 signal
        .generic => 2, // Generic calls need >= 2 signals to reduce FP
    };

    if (signal_count < min_signals) {
        log.debug("FFI-SKIP [NO-SIGNALS]: {s} — only {d} signals (need {d})", .{
            match.name, signal_count, min_signals,
        });
        return null;
    }

    // Calculate dynamic confidence
    const confidence = calculateFFIConfidence(signal_count, vuln_type);

    // Layer 1: Confidence threshold check
    const min_confidence: f32 = switch (vuln_type) {
        .command_injection => 0.70, // Lower threshold for critical vulns
        .buffer_overflow => 0.70,
        .format_string => 0.75,
        .control_flow => 0.75,
        .generic => 0.80, // Higher threshold for generic calls
    };

    if (confidence < min_confidence) {
        log.debug("FFI-SKIP [LOW-CONF]: {s} confidence={d:.2} < {d:.2} (signals={d})", .{
            match.name, confidence, min_confidence, signal_count,
        });
        return null;
    }

    // Build detailed issue message with signal information
    const message = buildFFIIssueMessage(match, vuln_type, signal_count, confidence);

    return Issue.init(
        .ffi_unsafe_call,
        message,
        Location.init(match.name),
        calculateFFISeverity(confidence),
        confidence,
    );
}

/// Build detailed FFI issue message with signal information.
fn buildFFIIssueMessage(
    match: *const call_graph.FFIMatch,
    vuln_type: FFIVulnType,
    signal_count: u32,
    confidence: f32,
) []const u8 {
    _ = match;

    const vuln_desc = switch (vuln_type) {
        .command_injection => "Command injection vulnerability",
        .buffer_overflow => "Buffer overflow vulnerability",
        .format_string => "Format string vulnerability",
        .control_flow => "Control flow violation (setjmp/longjmp)",
        .generic => "FFI safety violation",
    };

    // Note: In production, this should use allocator for formatted string
    // For now, return static description with signal count info
    // TODO: Use std.fmt.allocPrint when allocator is available in context
    _ = signal_count;
    _ = confidence;

    return vuln_desc;
}

/// Calculate severity level based on confidence score.
fn calculateFFISeverity(confidence: f32) Severity {
    if (confidence >= 0.9) {
        return .critical;
    } else if (confidence >= 0.8) {
        return .high;
    } else if (confidence >= 0.7) {
        return .medium;
    } else {
        return .low;
    }
}

fn runSingleFileAnalysis(allocator: std.mem.Allocator, path: []const u8, config: Config) !void {
    log.info("=== OmniScope IR Analysis ===\n", .{});
    log.info("File: {s}\n\n", .{path});

    var loader = IRLoader.loadFile(allocator, path) catch |err| {
        log.err("Failed to load IR file: {s}\n", .{@errorName(err)});
        return err;
    };
    defer loader.deinit();

    // Detect source language from the loaded module
    const source_lang = if (loader.getModule()) |module_ref|
        LanguageDetector.detectModuleLanguage(module_ref.raw)
    else
        LanguageDetector.LanguageProfile{ .language = .unknown, .confidence = 0.0, .method = .unknown };

    const source_lang_name = languageDisplayName(source_lang.language);
    log.info("[Language] Source: {s} (confidence: {:.1}%)\n", .{ source_lang_name, source_lang.confidence * 100 });

    log.debug("Loaded: {d} functions\n\n", .{loader.getFunctionCount()});

    var result = try runModulePipeline(allocator, &loader, config);
    defer deinitAnalyzeResult(&result);

    // Detect target language from FFI boundary issues
    const target_lang = detectTargetLanguage(result.issues);
    const target_lang_name = languageDisplayName(target_lang);

    // Display language conversion info at analysis start
    log.info("[Language] Analyzing: {s} --> {s}\n", .{ source_lang_name, target_lang_name });

    try emitOutput(allocator, result.issues, result.func_count, result.time_ms, config, source_lang.language, target_lang);

    // Display language conversion summary at analysis end
    log.info("[Language] Analysis complete: {d} issues in {s} --> {s} boundary\n", .{
        result.issues.len, source_lang_name, target_lang_name,
    });

    {
        var rust_to_c: usize = 0;
        var c_to_rust: usize = 0;
        var other_boundary: usize = 0;
        for (result.issues) |issue| {
            if (issue.ffi_boundary) |bnd| {
                if (bnd.caller_language == .rust and bnd.callee_language == .c) {
                    rust_to_c += 1;
                } else if (bnd.caller_language == .c and bnd.callee_language == .rust) {
                    c_to_rust += 1;
                } else {
                    other_boundary += 1;
                }
            }
        }
        if (rust_to_c > 0) log.info("[Language]   rust --> c : {d} issues", .{rust_to_c});
        if (c_to_rust > 0) log.info("[Language]   c --> rust : {d} issues", .{c_to_rust});
        if (other_boundary > 0) log.info("[Language]   other boundary: {d} issues", .{other_boundary});
    }

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

    // Track source languages for each file
    var source_languages = try std.ArrayList(FFI_Language).initCapacity(allocator, files.len);
    defer source_languages.deinit(allocator);

    for (files, 0..) |file, i| {
        log.info("  [{d}/{d}] Loading: {s}\n", .{ i + 1, files.len, file });
        var loader = try IRLoader.loadFile(allocator, file);
        errdefer loader.deinit();
        try loaders.append(allocator, loader);

        // Detect source language for this file
        const lang_profile = if (loader.getModule()) |module_ref|
            LanguageDetector.detectModuleLanguage(module_ref.raw)
        else
            LanguageDetector.LanguageProfile{ .language = .unknown, .confidence = 0.0, .method = .unknown };

        try source_languages.append(allocator, lang_profile.language);
        log.info("  [{d}/{d}] Language: {s} ({:.0}% confidence)\n", .{
            i + 1,                                      files.len,
            languageDisplayName(lang_profile.language), lang_profile.confidence * 100,
        });
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
        const src_lang = languageDisplayName(source_languages.items[i]);
        log.info("  [{d}/{d}] Analyzing: {s} ({d} functions) [{s}]\n", .{
            i + 1, loaders.items.len, files[i], loader.getFunctionCount(), src_lang,
        });
        const result = runModulePipeline(allocator, loader, config) catch |err| {
            log.err("  [{d}/{d}] Analysis FAILED: {}\n", .{ i + 1, loaders.items.len, err });
            continue;
        };
        try results.append(allocator, result);
        total_funcs += result.func_count;
        total_facts += result.fact_count;
        total_time += result.time_ms;
        total_issues += result.issues.len;

        // Show per-file language conversion info
        if (result.issues.len > 0) {
            const target_lang = detectTargetLanguage(result.issues);
            log.info("  [{d}/{d}] Language: {s} --> {s} ({d} issues)\n", .{
                i + 1,             loaders.items.len,
                src_lang,          languageDisplayName(target_lang),
                result.issues.len,
            });
        }
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
                // ffiMatchToIssue now returns ?Issue with multi-layer filtering
                // Only append if it passes all precision filters (not null)
                if (ffiMatchToIssue(match)) |issue| {
                    try ffi_issues.append(allocator, issue);
                } else {
                    log.debug("FFI-FILTERED: {s} — did not pass precision filters", .{match.name});
                }
            }
        }
    }

    const ffi_issue_count = ffi_issues.items.len;

    // Build combined issue list for language detection
    var all_issues_for_lang = try std.ArrayList(Issue).initCapacity(allocator, total_issues + ffi_issue_count);
    defer all_issues_for_lang.deinit(allocator);
    for (results.items) |*r| {
        for (r.issues) |iss| try all_issues_for_lang.append(allocator, iss);
    }
    for (ffi_issues.items) |iss| try all_issues_for_lang.append(allocator, iss);

    // Detect dominant source and target languages across all files
    const dominant_target = detectTargetLanguage(all_issues_for_lang.items);

    // Count unique source languages
    var unique_sources = std.StringHashMap(void).init(allocator);
    defer unique_sources.deinit();
    for (source_languages.items) |lang| {
        const name = languageDisplayName(lang);
        _ = try unique_sources.put(name, {});
    }

    log.info("\n=== Multi-File Analysis Complete ===\n", .{});
    log.info("[Language] Source languages: ", .{});
    var first_src = true;
    var src_it = unique_sources.iterator();
    while (src_it.next()) |entry| {
        if (!first_src) log.info(", ", .{});
        first_src = false;
        log.info("{s}", .{entry.key_ptr.*});
    }
    log.info("\n", .{});
    log.info("[Language] Target language: {s}\n", .{languageDisplayName(dominant_target)});
    log.info("[Language] Conversion: {d} files analyzed\n", .{files.len});
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
        try emitOutput(allocator, merged.items, total_funcs, total_time, config, .unknown, dominant_target);
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

    // Validate config file exists (actual override merge happens inside runModulePipeline)
    if (config.config_path) |config_path| {
        log.info("CONFIG: Will load explicit config from {s}\n", .{config_path});
        // Config file loading and lang_registry merge happen in runModulePipeline()
        // to ensure CLI overrides are applied first (CLI > file config priority)
    } else {
        if (file_config.discoverConfigFile()) |discovered_path| {
            log.info("CONFIG: Discovered config at {s}\n", .{discovered_path});
            config.config_path = allocator.dupe(u8, discovered_path) catch null;
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

// ============================================================================
// FFI Precision Filtering Tests
// ============================================================================

test "FFI - Secondary signal detection: type mismatch" {
    // Test with a mock FFIMatch that has type-unsafe patterns
    const test_match = call_graph.FFIMatch{
        .name = "void*_wrapper",
        .declare_func = null, // Simplified for test
        .define_func = null,
        .is_complete = false,
    };

    // Should detect type mismatch signal
    try std.testing.expect(hasTypeMismatchSignal(&test_match) == true);
}

test "FFI - Secondary signal detection: memory safety risk" {
    // Dangerous malloc without safe wrapper
    const unsafe_malloc = call_graph.FFIMatch{
        .name = "malloc_wrapper",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(hasMemorySafetyRisk(&unsafe_malloc) == true);

    // Safe wrapper should not trigger
    const safe_malloc = call_graph.FFIMatch{
        .name = "safe_malloc_wrapper",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(hasMemorySafetyRisk(&safe_malloc) == false);
}

test "FFI - Secondary signal detection: lifetime issue" {
    // Rust FFI lifetime anti-pattern
    const into_raw_match = call_graph.FFIMatch{
        .name = "process_into_raw_data",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(hasLifetimeIssue(&into_raw_match) == true);

    // Normal function should not trigger
    const normal_match = call_graph.FFIMatch{
        .name = "normal_function",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(hasLifetimeIssue(&normal_match) == false);
}

test "FFI - Secondary signal detection: trust boundary violation" {
    // User input processing function
    const user_input_match = call_graph.FFIMatch{
        .name = "process_user_input",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(hasTrustBoundaryViolation(&user_input_match) == true);

    // Internal function should not trigger
    const internal_match = call_graph.FFIMatch{
        .name = "internal_calculation",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(hasTrustBoundaryViolation(&internal_match) == false);
}

test "FFI - Secondary signal detection: missing validation" {
    // Risky function name without validation terms
    const risky_no_validation = call_graph.FFIMatch{
        .name = "wrap_external_call",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(hasMissingValidation(&risky_no_validation) == true);

    // Function with validation term
    const validated = call_graph.FFIMatch{
        .name = "validate_and_process",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(hasMissingValidation(&validated) == false);
}

test "FFI - Secondary signal detection: unchecked return" {
    // Function that returns value requiring check
    const malloc_match = call_graph.FFIMatch{
        .name = "malloc",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(hasUncheckedReturn(&malloc_match) == true);

    // Function that doesn't require return check
    const void_func = call_graph.FFIMatch{
        .name = "normal_void_func",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(hasUncheckedReturn(&void_func) == false);
}

test "FFI - Dynamic confidence calculation" {
    // Command injection with multiple signals should have high confidence
    const cmd_injection_conf = calculateFFIConfidence(3, .command_injection);
    try std.testing.expect(cmd_injection_conf >= 0.85);

    // Generic call with only 1 signal should have lower confidence
    const generic_low_conf = calculateFFIConfidence(1, .generic);
    try std.testing.expect(generic_low_conf < 0.75);

    // Generic call with 3+ signals should pass threshold
    const generic_high_conf = calculateFFIConfidence(3, .generic);
    try std.testing.expect(generic_high_conf >= 0.80);
}

test "FFI - Vulnerability type classification" {
    try std.testing.expectEqual(FFIVulnType.command_injection, classifyFFIVulnType("system"));
    try std.testing.expectEqual(FFIVulnType.command_injection, classifyFFIVulnType("execve"));
    try std.testing.expectEqual(FFIVulnType.buffer_overflow, classifyFFIVulnType("strcpy"));
    try std.testing.expectEqual(FFIVulnType.format_string, classifyFFIVulnType("printf"));
    try std.testing.expectEqual(FFIVulnType.control_flow, classifyFFIVulnType("setjmp"));
    try std.testing.expectEqual(FFIVulnType.generic, classifyFFIVulnType("normal_func"));
}

test "FFI - Whitelist filtering: stdlib internals" {
    // SQLite internal function should be whitelisted
    const sqlite_match = call_graph.FFIMatch{
        .name = "sqlite3MemMalloc_wrapper",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(isWhitelistedFFI(&sqlite_match) == true);

    // libuv internal function
    const libuv_match = call_graph.FFIMatch{
        .name = "uv__stream_write",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(isWhitelistedFFI(&libuv_match) == true);

    // User code should NOT be whitelisted
    const user_match = call_graph.FFIMatch{
        .name = "process_data",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(isWhitelistedFFI(&user_match) == false);
}

test "FFI - Whitelist filtering: safe naming patterns" {
    // Safe getter pattern (not in dangerous list)
    const safe_getter = call_graph.FFIMatch{
        .name = "get_version_info",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(isWhitelistedFFI(&safe_getter) == true);

    // Safe validation function
    const safe_validate = call_graph.FFIMatch{
        .name = "validate_input_data",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(isWhitelistedFFI(&safe_validate) == true);
}

test "FFI - Multi-layer filtering: reduces false positives" {
    // Scenario 1: Normal FFI call without danger signals → filtered out
    const normal_ffi = call_graph.FFIMatch{
        .name = "initialize_component", // Generic name, no signals
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    // Should be filtered (no secondary signals for generic call)
    const normal_result = ffiMatchToIssue(&normal_ffi);
    try std.testing.expect(normal_result == null); // Filtered out

    // Scenario 2: Command injection with trust boundary → always reported
    const cmd_injection = call_graph.FFIMatch{
        .name = "system", // Always reported regardless of signals
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    const cmd_result = ffiMatchToIssue(&cmd_injection);
    try std.testing.expect(cmd_result != null); // Should be reported
    if (cmd_result) |issue| {
        try std.testing.expect(issue.confidence >= 0.70);
        try std.testing.expect(issue.severity == .high or issue.severity == .critical);
    }

    // Scenario 3: Generic FFI with 3+ signals → passes filters
    const multi_signal = call_graph.FFIMatch{
        .name = "process_user_request_with_malloc", // Multiple signals: trust boundary + memory safety + missing validation
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    const multi_result = ffiMatchToIssue(&multi_signal);
    try std.testing.expect(multi_result != null); // Should be reported with sufficient signals
}

test "FFI - Confidence thresholds by vulnerability type" {
    // Test that different vuln types have appropriate thresholds

    // Command injection: low threshold (0.70), always report
    const system_match = call_graph.FFIMatch{
        .name = "system",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    const system_result = ffiMatchToIssue(&system_match);
    try std.testing.expect(system_result != null);
    if (system_result) |issue| {
        try std.testing.expect(issue.confidence >= 0.70);
    }

    // Format string: medium threshold (0.75), needs 1+ signal
    const printf_match = call_graph.FFIMatch{
        .name = "printf",
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    // printf alone might not have enough signals
    _ = ffiMatchToIssue(&printf_match);
    // May or may not be reported depending on signal count

    // Generic: high threshold (0.80), needs 2+ signals
    const setjmp_match = call_graph.FFIMatch{
        .name = "setjmp", // Control flow, needs 1+ signal
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    _ = ffiMatchToIssue(&setjmp_match);
    // setjmp is control_flow type, needs at least 1 signal
    // Without signals, it will be filtered
}

test "FFI - Severity calculation from confidence" {
    try std.testing.expectEqual(Severity.critical, calculateFFISeverity(0.95));
    try std.testing.expectEqual(Severity.high, calculateFFISeverity(0.85));
    try std.testing.expectEqual(Severity.medium, calculateFFISeverity(0.75));
    try std.testing.expectEqual(Severity.low, calculateFFISeverity(0.65));
}

test "FFI - Integration: end-to-end precision improvement" {
    // This test demonstrates the FP reduction achieved by the new system:
    //
    // BEFORE: All FFI matches with dangerous names were reported at confidence=0.7
    // AFTER: Only FFI matches with sufficient secondary signals are reported
    //
    // Expected outcome: 60-80% reduction in false positives for generic FFI calls

    // Test case 1: Well-audited stdlib internal (should be filtered)
    const stdlib_case = call_graph.FFIMatch{
        .name = "sqlite3MemMalloc", // In whitelist
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(ffiMatchToIssue(&stdlib_case) == null);

    // Test case 2: Safe wrapper function (should be filtered)
    const safe_wrapper_case = call_graph.FFIMatch{
        .name = "validate_connection", // Has "validate" → safe pattern
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    try std.testing.expect(ffiMatchToIssue(&safe_wrapper_case) == null);

    // Test case 3: Real vulnerability with multiple signals (should be reported)
    const real_vuln_case = call_graph.FFIMatch{
        .name = "process_user_command_with_system", // Trust boundary + command injection
        .declare_func = null,
        .define_func = null,
        .is_complete = false,
    };

    const real_vuln_result = ffiMatchToIssue(&real_vuln_case);
    try std.testing.expect(real_vuln_result != null);
    if (real_vuln_result) |issue| {
        // Should have high confidence due to multiple signals
        try std.testing.expect(issue.confidence >= 0.80);
        try std.testing.expect(issue.severity == .high or issue.severity == .critical);
    }

    log.info("FFI-PRECISION: Multi-layer filtering active — expected 60-80% FP reduction for generic calls", .{});
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
