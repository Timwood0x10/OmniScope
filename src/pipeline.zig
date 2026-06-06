//! Pipeline Orchestration — Consolidated from main.zig and pipeline_runner.zig
//!
//! Handles pass registration, pipeline execution, and multi-file analysis.

const std = @import("std");
const Allocator = std.mem.Allocator;
const OmniScope = @import("OmniScope");
const Pipeline = OmniScope.pipeline.Pipeline;
const call_graph = OmniScope.cross_lang;
const llvm_safe = OmniScope.ir.llvm_safe;
const IRLoader = OmniScope.engine.IRLoader;
const FunctionRef = OmniScope.ir.view.FunctionRef;
const Issue = OmniScope.diag.Issue;
const Location = OmniScope.diag.Location;
const Severity = OmniScope.diag.Severity;
const FFIBoundary = OmniScope.diag.FFIBoundary;
const log = OmniScope.log;

const main_config = OmniScope.config.main_config;
const file_config = OmniScope.config.file_config;
const language_override = OmniScope.config.language_override;
const Config = main_config.Config;

const GraphKind = @import("./visual/graph_visualizer.zig").GraphKind;
const LanguageDetector = OmniScope.semantics.language_detector;
const FFI_Language = OmniScope.diag.FFIBoundary.Language;

const ffi_precision = @import("ffi_precision.zig");
const output_formatter = @import("output_formatter.zig");

/// Result of a full pipeline analysis run.
pub const AnalyzeResult = struct {
    issues: []const Issue,
    func_count: usize,
    fact_count: usize,
    time_ms: u64,
    _pipeline: Pipeline,
};

pub const registerAllPasses = @import("pipeline_registration.zig").registerAllPasses;

/// Run the full pipeline on a single module.
pub fn runModulePipeline(allocator: std.mem.Allocator, loader: *IRLoader, config: Config) !AnalyzeResult {
    var pipeline = try Pipeline.init(allocator);
    if (loader.getModule()) |module_ref| {
        pipeline.setModule(module_ref);
    }

    if (config.perf_stats) {
        pipeline.setPerfStats(true);
    }
    pipeline.setLeakThreshold(config.leak_confidence_threshold);
    pipeline.setZigAllocatorTracking(config.enable_zig_allocator_tracking);
    pipeline.setFocusUserCode(config.focus_user_code);

    var lang_registry = try language_override.LanguageOverrideRegistry.init(allocator);
    defer lang_registry.deinit();

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
    lang_registry.sortPrefixRules();
    lang_registry.sortSuffixRules();

    if (config.config_path) |cp| {
        if (file_config.loadFromFile(allocator, cp)) |file_cfg_val| {
            var file_cfg = file_cfg_val;
            defer {
                if (file_cfg.lang_registry) |*reg| reg.deinit();
            }
            if (file_cfg.lang_registry) |*file_reg| {
                var file_exact_iter = file_reg.exact_map.iterator();
                while (file_exact_iter.next()) |entry| {
                    if (!lang_registry.exact_map.contains(entry.key_ptr.*)) {
                        lang_registry.addExact(entry.key_ptr.*, entry.value_ptr.*) catch {};
                    }
                }
                for (file_reg.prefix_rules.items) |rule| {
                    lang_registry.addPrefix(rule.prefix, rule.lang) catch {};
                }
                for (file_reg.suffix_rules.items) |rule| {
                    lang_registry.addSuffix(rule.suffix, rule.lang) catch {};
                }
                var file_sf_iter = file_reg.source_file_map.iterator();
                while (file_sf_iter.next()) |entry| {
                    if (!lang_registry.source_file_map.contains(entry.key_ptr.*)) {
                        lang_registry.addSourceFile(entry.key_ptr.*, entry.value_ptr.*) catch {};
                    }
                }
                if (file_reg.default_lang) |fdef| {
                    if (lang_registry.default_lang == null) {
                        lang_registry.setDefault(fdef);
                    }
                }
                lang_registry.sortPrefixRules();
                lang_registry.sortSuffixRules();
            }
        } else |err| {
            log.warn("CONFIG: Failed to load config file '{s}': {}", .{ cp, err });
        }
    }

    pipeline.setLanguageOverrides(&lang_registry);
    try registerAllPasses(&pipeline);

    const analysis_start = std.time.milliTimestamp();
    const pipeline_result = try pipeline.runStaticAnalysis();
    const elapsed = std.time.milliTimestamp() - analysis_start;
    const time_ms: u64 = @intCast(@max(0, elapsed));

    const issues = pipeline.getIssues();
    const func_count = loader.getFunctionCount();

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

/// Deinitialize an AnalyzeResult, freeing its internal pipeline resources.
pub fn deinitAnalyzeResult(res: *AnalyzeResult) void {
    res._pipeline.deinit();
    res.* = undefined;
}

/// Run analysis across multiple files.
pub fn runMultiFileAnalysis(allocator: std.mem.Allocator, files: []const []const u8, config: Config) !void {
    log.info("=== OmniScope Multi-File Analysis ===\n\n", .{});
    log.info("[*] Files: {d}\n", .{files.len});

    var loaders = try std.ArrayList(IRLoader).initCapacity(allocator, files.len);
    defer {
        for (loaders.items) |*loader| loader.deinit();
        loaders.deinit(allocator);
    }

    var source_languages = try std.ArrayList(FFI_Language).initCapacity(allocator, files.len);
    defer source_languages.deinit(allocator);

    for (files, 0..) |file, i| {
        log.info("  [{d}/{d}] Loading: {s}\n", .{ i + 1, files.len, file });
        var loader = try IRLoader.loadFile(allocator, file);
        errdefer loader.deinit();
        try loaders.append(allocator, loader);

        const lang_profile = if (loader.getModule()) |module_ref|
            LanguageDetector.detectModuleLanguage(module_ref.raw)
        else
            LanguageDetector.LanguageProfile{ .language = .unknown, .confidence = 0.0, .method = .unknown };

        try source_languages.append(allocator, lang_profile.language);
        log.info("  [{d}/{d}] Language: {s} ({:.0}% confidence)\n", .{
            i + 1,                                                       files.len,
            output_formatter.languageDisplayName(lang_profile.language), lang_profile.confidence * 100,
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
        const src_lang = output_formatter.languageDisplayName(source_languages.items[i]);
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

        if (result.issues.len > 0) {
            const target_lang = output_formatter.detectTargetLanguage(result.issues);
            log.info("  [{d}/{d}] Language: {s} --> {s} ({d} issues)\n", .{
                i + 1,             loaders.items.len,
                src_lang,          output_formatter.languageDisplayName(target_lang),
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
            if (ffi_precision.isDangerousFFIPattern(match)) {
                if (ffi_precision.ffiMatchToIssue(match, 1.0)) |issue| {
                    try ffi_issues.append(allocator, issue);
                } else {
                    log.debug("FFI-FILTERED: {s} — did not pass precision filters", .{match.name});
                }
            }
        }
    }

    const ffi_issue_count = ffi_issues.items.len;

    var all_issues_for_lang = try std.ArrayList(Issue).initCapacity(allocator, total_issues + ffi_issue_count);
    defer all_issues_for_lang.deinit(allocator);
    for (results.items) |*r| {
        for (r.issues) |iss| try all_issues_for_lang.append(allocator, iss);
    }
    for (ffi_issues.items) |iss| try all_issues_for_lang.append(allocator, iss);

    const dominant_target = output_formatter.detectTargetLanguage(all_issues_for_lang.items);

    var unique_sources = std.StringHashMap(void).init(allocator);
    defer unique_sources.deinit();
    for (source_languages.items) |lang| {
        const name = output_formatter.languageDisplayName(lang);
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
    log.info("[Language] Target language: {s}\n", .{output_formatter.languageDisplayName(dominant_target)});
    log.info("[Language] Conversion: {d} files analyzed\n", .{files.len});
    log.info("Total functions: {d}\n", .{total_funcs});
    log.info("Total facts: {d}\n", .{total_facts});
    log.info("Total time: {d}ms\n", .{total_time});
    log.info("Pipeline issues: {d}\n", .{total_issues});
    log.info("FFI matches: {d}\n", .{matcher.matches.items.len});
    log.info("FFI vulnerabilities: {d}\n", .{ffi_issue_count});
    log.info("Total issues: {d}\n", .{total_issues + ffi_issue_count});

    var all_slices = try std.ArrayList([]const Issue).initCapacity(allocator, results.items.len + 1);
    defer all_slices.deinit(allocator);
    for (results.items) |*r| all_slices.appendAssumeCapacity(r.issues);
    all_slices.appendAssumeCapacity(ffi_issues.items);

    const combined_count = total_issues + ffi_issue_count;

    if (config.output_format == .json or config.output_format == .sarif) {
        var merged = try std.ArrayList(Issue).initCapacity(allocator, combined_count);
        defer merged.deinit(allocator);
        for (all_slices.items) |slice| {
            for (slice) |iss| try merged.append(allocator, iss);
        }
        try output_formatter.emitOutput(allocator, merged.items, total_funcs, total_time, config, .unknown, dominant_target);
    } else {
        log.info("Issues detected: {d} in pipeline, {d} FFI\n", .{ total_issues, ffi_issue_count });
    }
}

fn countFunction(func_ref: FunctionRef, count: *usize) !void {
    _ = func_ref;
    count.* += 1;
}
