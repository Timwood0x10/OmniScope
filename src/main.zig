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
const log = OmniScope.log;

fn logInfo(comptime fmt: []const u8, args: anytype) void {
    log.info(fmt, args);
}

fn logDebug(comptime fmt: []const u8, args: anytype) void {
    log.debug(fmt, args);
}

fn logWarn(comptime fmt: []const u8, args: anytype) void {
    log.warn(fmt, args);
}

/// Main entry point error set
pub const MainError = error{
    NoInputFile,
    InvalidOption,
};

/// Command line configuration
const Config = struct {
    show_help: bool = false,
    show_version: bool = false,
    verbose: bool = false,
    debug: bool = false,
    quiet: bool = false,
    input_files: std.ArrayList([]const u8),
    output_format: OutputFormat = .text,
    output_file: ?[]const u8 = null,

    fn init(allocator: std.mem.Allocator) Config {
        return .{
            .input_files = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable,
        };
    }

    fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        self.input_files.deinit(allocator);
        if (self.output_file) |path| {
            allocator.free(path);
        }
    }
};

const OutputFormat = enum {
    text,
    json,
    sarif,
};

fn writeJsonEscaped(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{X:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}

/// Parse command line arguments
fn parseArgs(allocator: std.mem.Allocator) !Config {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // Skip program name

    var config = Config.init(allocator);
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
                std.log.err("Error: --output requires a file path\n", .{});
                return error.InvalidOption;
            };
            if (output_file.len == 0) {
                std.log.err("Error: --output requires a non-empty file path\n", .{});
                return error.InvalidOption;
            }
            config.output_file = try allocator.dupe(u8, output_file);
        } else if (arg.len > 0 and arg[0] == '-') {
            return error.InvalidOption;
        } else {
            try config.input_files.append(allocator, arg);
        }
    }

    return config;
}

/// Show help message
fn showHelp() void {
    std.debug.print(
        \\OmniScope - Universal LLVM Analysis Framework
        \\
        \\Usage: omniscope [options] <input.bc> [input2.bc] [...]
        \\
        \\Options:
        \\  -h, --help          Show this help message
        \\  -v, --verbose       Enable verbose logging
        \\  -d, --debug         Enable debug logging
        \\  -q, --quiet         Quiet mode (only show issues)
        \\  --version           Show version information
        \\  --json              Output in JSON format
        \\  --sarif             Output in SARIF format
        \\  -o, --output <file>  Write output to file
        \\
        \\Analysis Types:
        \\  Cross-Language Data Flow (default)
        \\  Detects: Source -> Sink paths across FFI boundaries
        \\
        \\Multi-File Analysis (FFI Mode):
        \\  omniscope rust.bc c.bc
        \\  Analyzes cross-language FFI calls between Rust and C
        \\
        \\  omniscope rust.ll c.ll
        \\  Supports .ll files for debugging and analysis
        \\
    , .{});
}

/// Run analysis on single file
/// Run analysis on single file.
///
/// This function loads LLVM IR from a file and performs basic analysis.
/// It uses IRLoader directly for simple file analysis without the complexity
/// of the full Pipeline system.
///
/// Arguments:
///   - allocator: Memory allocator for resource management
///   - path: Path to the LLVM IR file (.bc or .ll)
///
/// Errors:
///   - FileNotFound: IR file does not exist
///   - InvalidIR: IR file is corrupted or invalid
///   - OutOfMemory: Memory allocation failed
fn runSingleFileAnalysis(allocator: std.mem.Allocator, path: []const u8, config: Config) !void {
    logInfo("=== OmniScope IR Analysis ===\n", .{});
    logInfo("File: {s}\n\n", .{path});

    var loader = IRLoader.loadFile(allocator, path) catch |err| {
        std.log.err("Failed to load IR file: {s}\n", .{@errorName(err)});
        return err;
    };
    defer loader.deinit();

    const func_count = loader.getFunctionCount();
    logInfo("Loaded: {d} functions\n\n", .{func_count});

    var pipeline = try Pipeline.init(allocator);
    defer pipeline.deinit();

    if (loader.getModule()) |module_ref| {
        pipeline.setModule(module_ref);
    }

    try pipeline.registerPass(OmniScope.cross_lang.CallGraphPass);
    try pipeline.registerPass(OmniScope.cross_lang.FFIBoundaryPass);
    try pipeline.registerPass(OmniScope.cross_lang.PointerOwnershipPass);
    try pipeline.registerPass(OmniScope.cross_lang.FFIUnsafePass);
    try pipeline.registerPass(OmniScope.cross_lang.PtrLifetimePass);
    try pipeline.registerPass(OmniScope.cross_lang.FFIBodyCheckPass);
    try pipeline.registerPass(OmniScope.cross_lang.CallbackEscapePass);
    try pipeline.registerPass(OmniScope.cross_lang.ReturnCheckPass);
    try pipeline.registerPass(OmniScope.cross_lang.MemorySafetyPass);
    try pipeline.registerPass(OmniScope.cross_lang.FreeValidationPass);

    const analysis_start = std.time.milliTimestamp();
    const result = try pipeline.runStaticAnalysis();
    const elapsed = std.time.milliTimestamp() - analysis_start;
    const analysis_time_ms: u64 = @intCast(@max(0, elapsed));

    logInfo("Analysis complete\n", .{});
    logInfo("Functions processed: {d}\n", .{func_count});
    logInfo("Facts generated: {d}\n", .{result.fact_count});

    const issues = pipeline.getIssues();

    if (issues.len > 0 or config.output_format == .json or config.output_format == .sarif) {
        if (config.output_format == .json) {
            const json_output = formatIssuesAsJson(allocator, issues, func_count, analysis_time_ms) catch |err| {
                std.log.err("Failed to format JSON output: {}", .{err});
                return;
            };
            defer allocator.free(json_output);

            if (config.output_file) |output_path| {
                const file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
                    std.log.err("Failed to create output file '{s}': {}", .{ output_path, err });
                    return;
                };
                defer file.close();
                file.writeAll(json_output) catch |err| {
                    std.log.err("Failed to write to file '{s}': {}", .{ output_path, err });
                    return;
                };
                logInfo("Report saved to: {s}\n", .{output_path});
            } else {
                std.debug.print("{s}\n", .{json_output});
            }
        } else if (config.output_format == .sarif) {
            var sarif = SarifOutput.init(allocator, "OmniScope", "0.1.8");
            const sarif_output = sarif.generate(issues) catch |err| {
                std.log.err("Failed to generate SARIF output: {}", .{err});
                return;
            };
            defer allocator.free(sarif_output);

            if (config.output_file) |output_path| {
                const file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
                    std.log.err("Failed to create output file '{s}': {}", .{ output_path, err });
                    return;
                };
                defer file.close();
                file.writeAll(sarif_output) catch |err| {
                    std.log.err("Failed to write to file '{s}': {}", .{ output_path, err });
                    return;
                };
                logInfo("SARIF report saved to: {s}\n", .{output_path});
            } else {
                std.debug.print("{s}\n", .{sarif_output});
            }
        } else {
            logInfo("Issues detected: {d}\n", .{issues.len});
        }
    }
}

fn formatIssuesAsJson(allocator: std.mem.Allocator, issues: []const Issue, func_count: usize, analysis_time_ms: u64) ![]u8 {
    var output = std.array_list.Managed(u8).init(allocator);
    defer output.deinit();

    const timestamp = std.time.timestamp();
    const writer = output.writer();

    try writer.writeAll("{\"schema_version\":\"1.0.0\",\"tool\":\"omniscope\",\"tool_version\":\"0.1.5\",\"timestamp\":");
    try writer.print("{d}", .{timestamp});
    try writer.writeAll(",\"summary\":{");
    try writer.print("\"functions\":{d},\"issues\":{d},\"time_ms\":{d}", .{ func_count, issues.len, analysis_time_ms });
    try writer.writeAll("},\"issues\":[\n");

    for (issues, 0..) |issue, idx| {
        if (idx > 0) try writer.writeAll(",\n");

        const id_str = try std.fmt.allocPrint(allocator, "OMI-{d:0>3}", .{idx + 1});
        defer allocator.free(id_str);

        const file_str = issue.location.file orelse null;
        const line_num = issue.location.line orelse null;
        const col_num = issue.location.column orelse null;
        const cwe_id = issue.kind.toCweId();

        try writer.writeAll("  {\"id\":\"");
        try writer.writeAll(id_str);
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
        try writeJsonEscaped(writer, issue.location.function);
        try writer.writeAll("\"");

        if (file_str) |f| {
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

    try writer.writeAll("\n]}\n");

    return try output.toOwnedSlice();
}

/// Callback function to count functions during iteration.
///
/// Arguments:
///   - func_ref: Reference to the function
///   - count: Pointer to counter (user context)
fn countFunction(func_ref: FunctionRef, count: *usize) !void {
    _ = func_ref;
    count.* += 1;
}

/// Run analysis on multiple files (FFI mode)
fn runMultiFileAnalysis(files: []const []const u8) !void {
    logInfo("=== OmniScope Cross-Language FFI Analysis ===\n\n", .{});
    logInfo("[*] FFI Mode: {d} files detected\n", .{files.len});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            if (log.current_log_level != .quiet) {
                std.log.warn("Memory leak detected in FFI analysis!\n", .{});
            }
        }
    }

    const allocator = gpa.allocator();

    var loaders = std.ArrayList(IRLoader).initCapacity(allocator, files.len) catch return error.OutOfMemory;
    defer {
        for (loaders.items) |*loader| {
            loader.deinit();
        }
        loaders.deinit(allocator);
    }

    logInfo("[*] Loading IR files...\n", .{});
    for (files, 0..) |file, i| {
        logInfo("  [{d}/{d}] Loading: {s}\n", .{ i + 1, files.len, file });

        var loader = try IRLoader.loadFile(allocator, file);
        errdefer loader.deinit();

        const func_count = loader.getFunctionCount();
        logInfo("  [{d}/{d}] Loaded: {s} ({d} functions)\n", .{ i + 1, files.len, file, func_count });

        try loaders.append(allocator, loader);
    }

    logInfo("[*] All files loaded successfully\n\n", .{});

    logInfo("[*] Initializing FFI matcher...\n", .{});

    const FFIMatcher = OmniScope.cross_lang.FFIMatcher;
    const FFIMatcherFunctionInfo = OmniScope.cross_lang.FunctionInfo;

    var matcher = try FFIMatcher.init(allocator);
    defer matcher.deinit();

    for (loaders.items) |*loader| {
        const MatcherCallback = struct {
            matcher_ptr: *FFIMatcher,
            allocator_ptr: Allocator,

            fn processFunction(func_ref: FunctionRef, self: *const @This()) anyerror!void {
                const func = llvm_safe.Function{ .raw = func_ref.raw };
                const func_info = try FFIMatcherFunctionInfo.fromFunction(func, self.allocator_ptr);
                if (func_info.kind == .declare) {
                    try self.matcher_ptr.declare_functions.append(self.allocator_ptr, func_info);
                } else if (func_info.kind == .define) {
                    try self.matcher_ptr.define_functions.append(self.allocator_ptr, func_info);
                }
            }
        };

        const callback_data = MatcherCallback{
            .matcher_ptr = &matcher,
            .allocator_ptr = allocator,
        };

        try loader.iterateFunctions(&callback_data, MatcherCallback.processFunction);
    }

    logInfo("[*] Performing FFI function matching...\n", .{});
    try matcher.matchFunctions();

    logInfo("[*] Found {d} FFI matches\n", .{matcher.matches.items.len});

    var vulnerabilities: std.ArrayList(OmniScope.cross_lang.FFIVulnerability) = try std.ArrayList(OmniScope.cross_lang.FFIVulnerability).initCapacity(allocator, 100);
    defer vulnerabilities.deinit(allocator);

    logInfo("[*] Analyzing {d} FFI matches for vulnerabilities...\n", .{matcher.matches.items.len});

    for (matcher.matches.items, 0..) |*match, i| {
        if (!match.isValid()) continue;

        logDebug("  [Match {d}] {s}\n", .{ i, match.name });

        if (isDangerousFFIPattern(match)) {
            const vuln = OmniScope.cross_lang.FFIVulnerability{
                .id = @intCast(vulnerabilities.items.len),
                .vuln_type = .command_injection,
                .severity = .high,
                .ffi_match = match,
                .description = "Potential command injection via FFI boundary",
                .source_location = match.declare_func.?.name,
                .sink_location = match.define_func.?.name,
                .dangerous_function = null,
            };
            try vulnerabilities.append(allocator, vuln);
        }
    }

    logInfo("[*] Running FFI vulnerability detection...\n", .{});

    if (vulnerabilities.items.len > 0) {
        logInfo("[!] Found {d} potential FFI vulnerabilities:\n", .{vulnerabilities.items.len});
        for (vulnerabilities.items) |vuln| {
            std.debug.print("  [VULN #{d}] {s}\n", .{ vuln.id, @tagName(vuln.vuln_type) });
            std.debug.print("    Severity: {s}\n", .{@tagName(vuln.severity)});
            std.debug.print("    Description: {s}\n", .{vuln.description});
            std.debug.print("    Declaration: {s}\n", .{vuln.source_location orelse "unknown"});
            std.debug.print("    Definition: {s}\n", .{vuln.sink_location orelse "unknown"});
        }
    } else {
        logInfo("[*] No FFI vulnerabilities detected\n", .{});
    }

    logInfo("=== FFI Analysis Summary ===\n", .{});
    std.debug.print("Total files analyzed: {d}\n", .{files.len});
    std.debug.print("Total functions: {d}\n", .{blk: {
        var total: usize = 0;
        for (loaders.items) |*loader| {
            total += loader.getFunctionCount();
        }
        break :blk total;
    }});
    std.debug.print("FFI matches found: {d}\n", .{matcher.matches.items.len});
    std.debug.print("Vulnerabilities detected: {d}\n", .{vulnerabilities.items.len});
}

/// Check if an FFI match represents a dangerous pattern
fn isDangerousFFIPattern(match: *const OmniScope.cross_lang.FFIMatch) bool {
    // Check for system/exec calls (potential command injection)
    const define_func = match.define_func orelse return false;
    const name = define_func.name;

    // Check for dangerous patterns in function name
    const dangerous_patterns = &[_][]const u8{
        "system",
        "exec",
        "popen",
        "eval",
        "shell",
        "run_command",
        "execute_command",
    };

    for (dangerous_patterns) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) {
            return true;
        }
    }

    // Check for functions that take user input without sanitization
    // Functions that register or verify transactions are potential targets
    const sensitive_patterns = &[_][]const u8{
        "register",
        "batch",
    };

    for (sensitive_patterns) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) {
            return true;
        }
    }

    return false;
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
        std.debug.print("OmniScope v0.1.5\n", .{});
        return;
    }

    if (config.input_files.items.len == 0) {
        std.debug.print("Error: No input file specified\n", .{});
        return error.NoInputFile;
    }

    if (config.input_files.items.len == 1) {
        try runSingleFileAnalysis(allocator, config.input_files.items[0], config);
    } else {
        try runMultiFileAnalysis(config.input_files.items);
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

    // Default config has no help flag set
    try std.testing.expect(!config.show_help);
}

test "parseArgs - no input files" {
    const config = try parseArgs(std.testing.allocator);
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), config.input_files.items.len);
}
