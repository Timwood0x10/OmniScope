const std = @import("std");
const Allocator = std.mem.Allocator;
const OmniScope = @import("OmniScope");
const Pipeline = OmniScope.pipeline.Pipeline;
const call_graph = OmniScope.cross_lang;
const llvm_safe = OmniScope.ir.llvm_safe;
const IRLoader = OmniScope.engine.IRLoader;
const FunctionRef = OmniScope.ir.view.FunctionRef;
const OutputFormatter = OmniScope.output.Formatter;
const OutputFormat = OmniScope.output.OutputFormat;
const AnalysisResult = OmniScope.output.AnalysisResult;
const Vulnerability = OmniScope.output.Vulnerability;

/// Main entry point error set
pub const MainError = error{
    NoInputFile,
    InvalidOption,
    InvalidOutputFormat,
};

/// Command line configuration
const Config = struct {
    show_help: bool = false,
    show_version: bool = false,
    verbose: bool = false,
    quiet: bool = false,
    debug: bool = false,
    input_files: std.ArrayList([]const u8),
    output_format: OutputFormat = .text,
    output_file: ?[]const u8 = null,

    fn init(allocator: std.mem.Allocator) !Config {
        return .{
            .input_files = try std.ArrayList([]const u8).initCapacity(allocator, 0),
        };
    }

    fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        self.input_files.deinit(allocator);
        if (self.output_file) |file| {
            allocator.free(file);
            self.output_file = null;
        }
    }
};

/// Parse command line arguments
fn parseArgs(allocator: std.mem.Allocator) !Config {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // Skip program name

    var config = try Config.init(allocator);
    errdefer config.deinit(allocator);

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            config.show_help = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            config.verbose = true;
        } else if (std.mem.eql(u8, arg, "-q") or std.mem.eql(u8, arg, "--quiet")) {
            config.quiet = true;
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--debug")) {
            config.debug = true;
        } else if (std.mem.eql(u8, arg, "--version")) {
            config.show_version = true;
        } else if (std.mem.eql(u8, arg, "--output-format")) {
            const format_str = args.next() orelse return error.InvalidOutputFormat;
            config.output_format = try parseOutputFormat(format_str);
        } else if (std.mem.eql(u8, arg, "--output-file")) {
            const file_path = args.next() orelse return error.InvalidOption;
            config.output_file = try allocator.dupe(u8, file_path);
        } else if (arg[0] == '-') {
            return error.InvalidOption;
        } else {
            try config.input_files.append(allocator, arg);
        }
    }

    return config;
}

/// Parse output format string
fn parseOutputFormat(format_str: []const u8) !OutputFormat {
    if (std.mem.eql(u8, format_str, "json")) {
        return .json;
    } else if (std.mem.eql(u8, format_str, "sarif")) {
        return .sarif;
    } else if (std.mem.eql(u8, format_str, "text")) {
        return .text;
    } else {
        return error.InvalidOutputFormat;
    }
}

/// Show help message
fn showHelp() void {
    std.debug.print(
        \\OmniScope - Universal LLVM Analysis Framework
        \\
        \\Usage: omniscope [options] <input.bc> [input2.bc] [...]
        \\
        \\Options:
        \\  -h, --help              Show this help message
        \\  -v, --verbose           Enable verbose logging
        \\  -d, --debug             Enable debug logging
        \\  --version               Show version information
        \\  --output-format <fmt>   Output format: json, sarif, text (default)
        \\  --output-file <file>    Write output to file
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
        \\Output Formats:
        \\  text (default)  - Human-readable text output
        \\  json           - Machine-readable JSON format
        \\  sarif          - Static Analysis Results Interchange Format
    , .{});
}

/// Run analysis on single file
fn runSingleFileAnalysis(allocator: std.mem.Allocator, path: []const u8) !void {
    std.debug.print("=== OmniScope Cross-Language Data Flow Analysis ===\n\n", .{});

    var pipeline = Pipeline.init(allocator);
    defer pipeline.deinit();

    std.debug.print("[*] Loading IR: {s}\n", .{path});
    pipeline.loadIR(path) catch |err| {
        std.debug.print("[!] Failed to load IR: {}\n", .{err});
        return err;
    };

    if (pipeline.getIRLoader()) |l| {
        std.debug.print("[*] IR loaded: {d} functions\n\n", .{l.getFunctionCount()});
    }

    std.debug.print("[*] Registering analysis passes...\n", .{});
    try pipeline.registerPass(call_graph.CallGraphPass);

    std.debug.print("[*] Running analysis...\n\n", .{});
    _ = pipeline.runStaticAnalysis() catch |err| {
        std.debug.print("[!] Analysis failed: {}\n", .{err});
        return err;
    };

    printResults(&pipeline);
}

/// Run analysis on multiple files (FFI mode)
fn runMultiFileAnalysis(files: []const []const u8, config: *const Config) !void {
    const suppress_progress = config.quiet or (config.output_format != .text and config.output_file == null);

    if (!suppress_progress) {
        std.debug.print("=== OmniScope Cross-Language FFI Analysis ===\n\n", .{});
        std.debug.print("[*] FFI Mode: {d} files detected\n", .{files.len});
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            OmniScope.log.warn("main", "Memory leak detected in FFI analysis!\n", .{});
        }
    }

    const allocator = gpa.allocator();

    // Load all files
    var loaders = std.ArrayList(IRLoader).initCapacity(allocator, files.len) catch return error.OutOfMemory;
    defer {
        for (loaders.items) |*loader| {
            loader.deinit();
        }
        loaders.deinit(allocator);
    }

    if (!suppress_progress) {
        std.debug.print("[*] Loading IR files...\n", .{});
        for (files, 0..) |file, i| {
            std.debug.print("  [{d}/{d}] Loading: {s}\n", .{ i + 1, files.len, file });

            var loader = try IRLoader.loadFile(allocator, file);
            errdefer loader.deinit();

            const func_count = loader.getFunctionCount();
            std.debug.print("  [{d}/{d}] Loaded: {s} ({d} functions)\n", .{ i + 1, files.len, file, func_count });

            try loaders.append(allocator, loader);
        }

        std.debug.print("[*] All files loaded successfully\n\n", .{});
    } else {
        for (files, 0..) |_, i| {
            var loader = try IRLoader.loadFile(allocator, files[i]);
            errdefer loader.deinit();
            try loaders.append(allocator, loader);
        }
    }

    // Initialize FFI matcher
    if (!suppress_progress) std.debug.print("[*] Initializing FFI matcher...\n", .{});

    // Import FFI components from OmniScope module
    const FFIMatcher = OmniScope.cross_lang.FFIMatcher;
    const FFIMatcherFunctionInfo = OmniScope.cross_lang.FunctionInfo;

    var matcher = try FFIMatcher.init(allocator);
    defer matcher.deinit();

    // Add functions from each loader to the matcher
    for (loaders.items) |*loader| {
        // Create callback that captures matcher
        const MatcherCallback = struct {
            matcher_ptr: *FFIMatcher,
            allocator_ptr: Allocator,

            fn processFunction(func_ref: FunctionRef, self: *const @This()) anyerror!void {
                const func = llvm_safe.Function{ .raw = func_ref.raw };
                const func_info = try FFIMatcherFunctionInfo.fromFunction(func, self.allocator_ptr);
                // Add to matcher based on function kind
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

    // Perform FFI matching
    if (!suppress_progress) std.debug.print("[*] Performing FFI function matching...\n", .{});
    try matcher.matchFunctions();

    if (!suppress_progress) std.debug.print("[*] Found {d} FFI matches\n", .{matcher.matches.items.len});

    // Analyze each FFI match for potential vulnerabilities
    var vulnerabilities: std.ArrayList(OmniScope.cross_lang.FFIVulnerability) = try std.ArrayList(OmniScope.cross_lang.FFIVulnerability).initCapacity(allocator, 100);
    defer vulnerabilities.deinit(allocator);

    if (!suppress_progress) std.debug.print("[*] Analyzing {d} FFI matches for vulnerabilities...\n", .{matcher.matches.items.len});

    for (matcher.matches.items, 0..) |*match, i| {
        if (!match.isValid()) continue;

        if (!suppress_progress) std.debug.print("  [Match {d}] {s}\n", .{ i, match.name });

        // Check for dangerous patterns
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

    // Format and output results
    if (!suppress_progress) {
        std.debug.print("\n[*] Running FFI vulnerability detection...\n", .{});
    }

    if (config.output_format == .text) {
        if (vulnerabilities.items.len > 0) {
            std.debug.print("[!] Found {d} potential FFI vulnerabilities:\n", .{vulnerabilities.items.len});
            for (vulnerabilities.items) |vuln| {
                std.debug.print("  [VULN #{d}] {s}\n", .{ vuln.id, @tagName(vuln.vuln_type) });
                std.debug.print("    Severity: {s}\n", .{@tagName(vuln.severity)});
                std.debug.print("    Description: {s}\n", .{vuln.description});
                std.debug.print("    Declaration: {s}\n", .{vuln.source_location orelse "unknown"});
                std.debug.print("    Definition: {s}\n", .{vuln.sink_location orelse "unknown"});
                std.debug.print("\n", .{});
            }
        } else {
            std.debug.print("[*] No FFI vulnerabilities detected\n", .{});
        }

        std.debug.print("=== FFI Analysis Summary ===\n", .{});
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
    } else {
        // Convert FFIVulnerability to Vulnerability for output formatting
        var output_vulns = std.ArrayList(Vulnerability).initCapacity(allocator, vulnerabilities.items.len) catch return error.OutOfMemory;
        defer output_vulns.deinit(allocator);

        for (vulnerabilities.items) |vuln| {
            try output_vulns.append(allocator, .{
                .id = vuln.id,
                .vuln_type = @tagName(vuln.vuln_type),
                .severity = @tagName(vuln.severity),
                .description = vuln.description,
                .source_location = vuln.source_location,
                .sink_location = vuln.sink_location,
                .cwe_id = OmniScope.cross_lang.getCWEID(vuln.vuln_type),
                .line = null,
                .column = null,
            });
        }

        var result = try AnalysisResult.init(allocator, output_vulns.items);
        defer result.deinit(allocator);

        result.total_files = @as(u32, @intCast(files.len));
        result.total_functions = @as(u32, @intCast(blk: {
            var total: usize = 0;
            for (loaders.items) |*loader| {
                total += loader.getFunctionCount();
            }
            break :blk total;
        }));
        result.ffi_matches = @as(u32, @intCast(matcher.matches.items.len));

        var formatter = OutputFormatter.init(allocator);
        const formatted_output = try formatter.format(config.output_format, result);
        defer allocator.free(formatted_output);

        if (config.output_file) |file_path| {
            // Write to file
            const file = try std.fs.cwd().createFile(file_path, .{});
            defer file.close();

            try file.writeAll(formatted_output);
            std.debug.print("Results written to: {s}\n", .{file_path});
        } else {
            // Write to stdout
            std.debug.print("{s}\n", .{formatted_output});
        }
    }
}

/// Check if an FFI match represents a dangerous pattern
fn isDangerousFFIPattern(match: *const OmniScope.cross_lang.FFIMatch) bool {
    // Check for system/exec calls (potential command injection)
    const define_func = match.define_func orelse return false;
    const name = define_func.name;

    // Use exact match for dangerous function names
    // These are known dangerous functions that should be flagged
    const dangerous_functions = &[_][]const u8{
        "system",
        "exec",
        "popen",
        "eval",
        "shell",
        // C standard library dangerous functions
        "gets",
        "strcpy",
        "strcat",
        "sprintf",
        "vsprintf",
        "scanf",
        "fscanf",
        "sscanf",
        "getenv",
    };

    for (dangerous_functions) |func_name| {
        if (std.mem.eql(u8, name, func_name)) {
            return true;
        }
    }

    return false;
}

/// Print analysis results
fn printResults(pipeline: *Pipeline) void {
    std.debug.print("\n=== Analysis Results ===\n", .{});
    const diagnostics = pipeline.getDiagnosticAggregator().getAll();

    if (diagnostics.len == 0) {
        std.debug.print("No issues found.\n", .{});
    } else {
        for (diagnostics) |diag| {
            std.debug.print("[{s}] {s}\n", .{
                @tagName(diag.severity),
                diag.message,
            });
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            OmniScope.log.warn("main", "Memory leak detected!\n", .{});
        }
    }

    const allocator = gpa.allocator();

    var config = try parseArgs(allocator);
    defer config.deinit(allocator);

    if (config.show_help) {
        showHelp();
        return;
    }

    if (config.show_version) {
        std.debug.print("OmniScope v1.0.0\n", .{});
        return;
    }

    if (config.input_files.items.len == 0) {
        std.debug.print("Error: No input file specified\n", .{});
        return error.NoInputFile;
    }

    if (config.input_files.items.len == 1) {
        try runSingleFileAnalysis(allocator, config.input_files.items[0]);
    } else {
        try runMultiFileAnalysis(config.input_files.items, &config);
    }
}

test "Config - init and deinit" {
    var config = try Config.init(std.testing.allocator);
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
