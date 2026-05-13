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

const GraphKind = @import("./visual/graph_visualizer.zig").GraphKind;

pub const MainError = error{
    NoInputFile,
    InvalidOption,
};

const Config = struct {
    show_help: bool = false,
    show_version: bool = false,
    verbose: bool = false,
    debug: bool = false,
    quiet: bool = false,
    input_files: std.ArrayList([]const u8),
    output_format: OutputFormat = .text,
    output_file: ?[]const u8 = null,
    visualize: bool = false,
    focus_user_code: bool = false,
    ffi_only: bool = false,
    include_stdlib: bool = false,

    fn init(allocator: std.mem.Allocator) !Config {
        return .{
            .input_files = std.ArrayList([]const u8).initCapacity(allocator, 0) catch return error.OutOfMemory,
        };
    }

    fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        for (self.input_files.items) |file| {
            if (file.len > 0) {
                allocator.free(file);
            }
        }
        self.input_files.deinit(allocator);
        if (self.output_file) |path| {
            if (path.len > 0) {
                allocator.free(path);
            }
        }
    }
};

const OutputFormat = enum {
    text,
    json,
    sarif,
};

const AnalyzeResult = struct {
    issues: []const Issue,
    func_count: usize,
    fact_count: usize,
    time_ms: u64,
    _pipeline: Pipeline,
};

fn parseArgs(allocator: std.mem.Allocator) !Config {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();

    var config = try Config.init(allocator);
    errdefer config.deinit(allocator);

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            config.show_help = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            config.verbose = true;
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--debug")) {
            config.debug = true;
        } else if (std.mem.eql(u8, arg, "-q") or std.mem.eql(u8, arg, "--quiet")) {
            config.quiet = true;
        } else if (std.mem.eql(u8, arg, "--version")) {
            config.show_version = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            config.output_format = .json;
        } else if (std.mem.eql(u8, arg, "--sarif")) {
            config.output_format = .sarif;
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            const output_file = args.next() orelse {
                log.err("Error: --output requires a file path\n", .{});
                return error.InvalidOption;
            };
            if (output_file.len == 0) {
                log.err("Error: --output requires a non-empty file path\n", .{});
                return error.InvalidOption;
            }
            config.output_file = try allocator.dupe(u8, output_file);
        } else if (std.mem.eql(u8, arg, "--visualize") or std.mem.eql(u8, arg, "--viz")) {
            config.visualize = true;
        } else if (std.mem.eql(u8, arg, "--focus-user-code")) {
            config.focus_user_code = true;
        } else if (std.mem.eql(u8, arg, "--ffi-only")) {
            config.ffi_only = true;
        } else if (std.mem.eql(u8, arg, "--include-stdlib")) {
            config.include_stdlib = true;
        } else if (arg.len > 0 and arg[0] == '-') {
            return error.InvalidOption;
        } else {
            const arg_copy = try allocator.dupe(u8, arg);
            try config.input_files.append(allocator, arg_copy);
        }
    }

    return config;
}

fn showHelp() void {
    log.info(
        \\OmniScope - Universal LLVM Analysis Framework
        \\
        \\Usage: omniscope [options] <input.ll/bc> [input2.ll/bc] [...]
        \\
        \\Options:
        \\  -h, --help          Show this help message
        \\  -v, --verbose       Enable verbose logging
        \\  -d, --debug         Enable debug logging
        \\  -q, --quiet         Quiet mode (only show issues)
        \\  --visualize, --viz  Generate HTML visualization
        \\  --focus-user-code   Only report issues from user code
        \\  --ffi-only          Only report FFI boundary issues
        \\  --include-stdlib    Include stdlib issues
        \\  --version           Show version information
        \\  --json              Output in JSON format
        \\  --sarif             Output in SARIF format
        \\  -o, --output <file> Write output to file
        \\
        \\Multi-File Mode (auto-detected when 2+ files given):
        \\  omniscope rust.bc c.bc
        \\  Runs full pipeline on each file + cross-language FFI matching
        \\
    , .{});
}

fn registerAllPasses(pipeline: *Pipeline) !void {
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
    try pipeline.registerPass(OmniScope.cross_lang.BufferOverflowPass);
}

fn runModulePipeline(allocator: std.mem.Allocator, loader: *IRLoader) !AnalyzeResult {
    var pipeline = try Pipeline.init(allocator);
    if (loader.getModule()) |module_ref| {
        pipeline.setModule(module_ref);
    }

    try registerAllPasses(&pipeline);

    const analysis_start = std.time.milliTimestamp();
    const pipeline_result = try pipeline.runStaticAnalysis();
    const elapsed = std.time.milliTimestamp() - analysis_start;
    const time_ms: u64 = @intCast(@max(0, elapsed));

    const issues = pipeline.getIssues();
    const func_count = loader.getFunctionCount();

    // Log results while pipeline is alive
    log.info("Analysis complete\n", .{});
    log.info("Functions processed: {d}\n", .{func_count});
    log.info("Facts generated: {d}\n", .{pipeline_result.fact_count});
    log.info("Time: {d}ms\n", .{time_ms});

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
    if (issues.len == 0 and config.output_format == .text) return;

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
        var sarif = SarifOutput.init(allocator, "OmniScope", "0.1.8");
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
        if (issues.len > 0) {
            log.info("Issues detected: {d}\n", .{issues.len});
        }
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

    log.info("Loaded: {d} functions\n\n", .{loader.getFunctionCount()});

    var result = try runModulePipeline(allocator, &loader);
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

fn ffiMatchToIssue(match: *const call_graph.FFIMatch) Issue {
    const def_name = if (match.define_func) |f| f.name else "unknown";
    const loc = Location.initWithFile("ffi", def_name, 0, 0);
    return Issue.init(.command_injection, "Cross-language FFI vulnerability detected", loc, .high, 0.85);
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
        const result = runModulePipeline(allocator, loader) catch |err| {
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

fn isDangerousFFIPattern(match: *const call_graph.FFIMatch) bool {
    const define_func = match.define_func orelse return false;
    const name = define_func.name;

    const dangerous_patterns = &[_][]const u8{
        "system", "exec", "popen", "eval", "shell",
        "run_command", "execute_command",
    };
    for (dangerous_patterns) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) return true;
    }

    const sensitive_patterns = &[_][]const u8{
        "register", "batch",
    };
    for (sensitive_patterns) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) return true;
    }

    return false;
}

fn issueToGraphKind(kind: IssueKind) GraphKind {
    return switch (kind) {
        .memory_leak => .memory_leak,
        .use_after_free => .use_after_free,
        .double_free => .double_free,
        .cross_language_leak => .cross_language_leak,
        .cross_language_free => .cross_language_free,
        .malloc_unchecked => .malloc_unchecked,
        .null_dereference => .null_dereference,
        .invalid_free => .invalid_free,
        .borrow_escape => .borrow_escape,
        .ffi_unsafe_call => .ffi_unsafe_call,
        .unchecked_return => .unchecked_return,
        .type_mismatch, .ffi_type_mismatch => .type_mismatch,
        .command_injection => .command_injection,
        .buffer_overflow => .buffer_overflow,
        .format_string => .format_string,
        .callback_signature_mismatch => .callback_signature_mismatch,
        .static_buffer_misuse => .static_buffer_misuse,
        .data_race => .other,
        .thread_safety_violation => .other,
        .unknown => .other,
    };
}

fn formatIssuesAsJson(allocator: std.mem.Allocator, issues: []const Issue, func_count: usize, analysis_time_ms: u64) ![]u8 {
    var output = std.array_list.Managed(u8).init(allocator);
    defer output.deinit();

    const timestamp = std.time.timestamp();
    const writer = output.writer();

    try writer.writeAll("{\"schema_version\":\"1.0.0\",\"tool\":\"omniscope\",\"tool_version\":\"0.1.8\",\"timestamp\":");
    try writer.print("{d}", .{timestamp});
    try writer.writeAll(",\"summary\":{");
    try writer.print("\"functions\":{d},\"issues\":{d},\"time_ms\":{d}", .{ func_count, issues.len, analysis_time_ms });
    try writer.writeAll("},\"issues\":[");

    for (issues, 0..) |issue, idx| {
        if (idx > 0) try writer.writeAll(",");

        const line_num = if (issue.location.line > 0) issue.location.line else null;
        const col_num = if (issue.location.column > 0) issue.location.column else null;
        const cwe_id = issue.kind.toCweId();

        try writer.writeAll("{\"id\":\"");
        try writer.print("OMI-{d:0>3}", .{idx + 1});
        try writer.writeAll("\",\"kind\":\"");
        try writer.writeAll(@tagName(issue.kind));
        try writer.writeAll("\",\"severity\":\"");
        try writer.writeAll(@tagName(issue.severity));
        try writer.writeAll("\",\"confidence\":\"");
        try writer.writeAll(issue.confidence_level.toString());
        try writer.writeAll("\",\"confidence_score\":");
        try writer.print("{d:.2}", .{issue.confidence});
        try writer.writeAll(",\"cwe_id\":");
        try writer.print("{d}", .{cwe_id});

        if (issue.reason.len > 0) {
            try writer.writeAll(",\"reason\":\"");
            try writeJsonEscaped(writer, issue.reason);
            try writer.writeAll("\"");
        }

        try writer.writeAll(",\"message\":\"");
        try writeJsonEscaped(writer, issue.message);
        try writer.writeAll("\",\"location\":{");
        try writer.writeAll("\"function\":\"");
        try writeJsonEscaped(writer, issue.location.func);
        try writer.writeAll("\"");

        if (issue.location.file) |f| {
            try writer.writeAll(",\"file\":\"");
            try writeJsonEscaped(writer, f);
            try writer.writeAll("\"");
        }
        if (line_num) |l| {
            try writer.writeAll(",\"line\":");
            try writer.print("{d}", .{l});
        }
        if (col_num) |c| {
            try writer.writeAll(",\"column\":");
            try writer.print("{d}", .{c});
        }

        try writer.writeAll("}}");
    }

    try writer.writeAll("]}\n");

    return try output.toOwnedSlice();
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

    var config = try parseArgs(allocator);
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
        showHelp();
        return;
    }

    if (config.show_version) {
        log.info("OmniScope v0.1.8\n", .{});
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
    const config = try parseArgs(std.testing.allocator);
    defer config.deinit(std.testing.allocator);

    try std.testing.expect(!config.show_help);
}

test "parseArgs - no input files" {
    const config = try parseArgs(std.testing.allocator);
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), config.input_files.items.len);
}
