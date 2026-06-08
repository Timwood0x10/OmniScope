//! Pipeline Runner — Single-file analysis orchestration
//!
//! Higher-level runner that loads a file, runs the pipeline via pipeline.zig,
//! detects languages, formats output, and optionally generates visualizations.

const std = @import("std");
const Allocator = std.mem.Allocator;
const OmniScope = @import("OmniScope");
const IRLoader = OmniScope.engine.IRLoader;
const Issue = OmniScope.diag.Issue;
const log = OmniScope.log;

const Config = OmniScope.config.main_config.Config;
const LanguageDetector = OmniScope.semantics.language_detector;

const pipeline = @import("pipeline.zig");
const ffi_precision = @import("ffi_precision.zig");
const output_formatter = @import("output_formatter.zig");
const c = OmniScope.ir.llvm_raw.c;

pub const AnalyzeResult = pipeline.AnalyzeResult;

pub fn runSingleFileAnalysis(allocator: std.mem.Allocator, path: []const u8, config: Config) !void {
    log.info("=== OmniScope IR Analysis ===\n", .{});
    log.info("File: {s}\n\n", .{path});

    var loader = IRLoader.loadFile(allocator, path) catch |err| {
        log.err("Failed to load IR file: {s}\n", .{@errorName(err)});
        return err;
    };
    defer loader.deinit();

    const source_lang = if (loader.getModule()) |module_ref|
        LanguageDetector.detectModuleLanguage(module_ref.raw, allocator)
    else
        LanguageDetector.LanguageProfile{ .language = .unknown, .confidence = 0.0, .method = .unknown };

    const source_lang_name = output_formatter.languageDisplayName(source_lang.language);
    log.info("[Language] Source: {s} (confidence: {:.1}%)\n", .{ source_lang_name, source_lang.confidence * 100 });
    log.debug("Loaded: {d} functions\n\n", .{loader.getFunctionCount()});

    log.info("[Language] Running FFI analysis for {s} module\n", .{source_lang_name});

    var result = try pipeline.runModulePipeline(allocator, &loader, config);
    defer pipeline.deinitAnalyzeResult(&result);

    const target_lang = output_formatter.detectTargetLanguage(result.issues);
    const target_lang_name = output_formatter.languageDisplayName(target_lang);

    if (source_lang.language == target_lang) {
        log.info("[Language] Same language ({s}) — no cross-language FFI boundary to analyze\n", .{source_lang_name});
    } else {
        log.info("[Language] Analyzing: {s} --> {s}\n", .{ source_lang_name, target_lang_name });
    }

    try output_formatter.emitOutput(allocator, result.issues, result.export_surfaces, result.func_count, result.time_ms, config, source_lang.language, target_lang);

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
            .kind = ffi_precision.issueToGraphKind(issue.kind),
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
