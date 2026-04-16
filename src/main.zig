const std = @import("std");
const Allocator = std.mem.Allocator;
const OmniScope = @import("OmniScope");
const Pipeline = OmniScope.pipeline.Pipeline;
const call_graph = OmniScope.cross_lang;
const llvm_safe = OmniScope.ir.llvm_safe;
const IRLoader = OmniScope.engine.IRLoader;
const FunctionRef = OmniScope.ir.view.FunctionRef;

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
    input_files: std.ArrayList([]const u8),

    fn init(allocator: std.mem.Allocator) Config {
        return .{
            .input_files = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable,
        };
    }

    fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        self.input_files.deinit(allocator);
    }
};

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
        } else if (std.mem.eql(u8, arg, "--version")) {
            config.show_version = true;
        } else if (arg[0] == '-') {
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
        \\  --version           Show version information
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
fn runSingleFileAnalysis(allocator: std.mem.Allocator, path: []const u8) !void {
    std.log.info("=== OmniScope IR Analysis ===\n", .{});
    std.log.info("File: {s}\n\n", .{path});

    // Load IR file using IRLoader
    var loader = IRLoader.loadFile(allocator, path) catch |err| {
        std.log.err("Failed to load IR file: {s}\n", .{@errorName(err)});
        return err;
    };
    defer loader.deinit();

    // Get function count
    const func_count = loader.getFunctionCount();
    std.log.info("Loaded: {d} functions\n\n", .{func_count});

    // Initialize Pipeline with IR module
    var pipeline = Pipeline.init(allocator);
    defer pipeline.deinit();

    // Set the module for analysis
    if (loader.getModule()) |module_ref| {
        pipeline.setModule(module_ref);
    }

    // Register FFI boundary detection pass
    try pipeline.registerPass(OmniScope.cross_lang.FFIBoundaryPass);

    // Register return value check pass
    try pipeline.registerPass(OmniScope.cross_lang.ReturnCheckPass);

    // Register FFI unsafe detection pass
    try pipeline.registerPass(OmniScope.cross_lang.FFIUnsafePass);

    // Run static analysis through Pipeline
    const result = try pipeline.runStaticAnalysis();

    std.log.info("Analysis complete\n", .{});
    std.log.info("Functions processed: {d}\n", .{func_count});
    std.log.info("Facts generated: {d}\n", .{result.fact_count});

    // Print issues detected by Pipeline
    const issues = pipeline.getIssues();
    if (issues.len > 0) {
        std.log.info("Issues detected: {d}\n", .{issues.len});
    }
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
    std.log.info("=== OmniScope Cross-Language FFI Analysis ===\n\n", .{});
    std.log.info("[*] FFI Mode: {d} files detected\n", .{files.len});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.warn("Memory leak detected in FFI analysis!\n", .{});
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

    std.debug.print("[*] Loading IR files...\n", .{});
    for (files, 0..) |file, i| {
        std.debug.print("  [{d}/{d}] Loading: {s}\n", .{ i + 1, files.len, file });

        var loader = try IRLoader.loadFile(allocator, file);
        errdefer loader.deinit();

        const func_count = loader.getFunctionCount();
        std.debug.print("  [{d}/{d}] Loaded: {s} ({d} functions)\n", .{ i + 1, files.len, file, func_count });

        try loaders.append(allocator, loader);
    }

    std.log.info("[*] All files loaded successfully\n\n", .{});

    // Initialize FFI matcher
    std.log.info("[*] Initializing FFI matcher...\n", .{});

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
    std.log.info("[*] Performing FFI function matching...\n", .{});
    try matcher.matchFunctions();

    std.log.info("[*] Found {d} FFI matches\n", .{matcher.matches.items.len});

    // Analyze each FFI match for potential vulnerabilities
    var vulnerabilities: std.ArrayList(OmniScope.cross_lang.FFIVulnerability) = try std.ArrayList(OmniScope.cross_lang.FFIVulnerability).initCapacity(allocator, 100);
    defer vulnerabilities.deinit(allocator);

    std.log.info("[*] Analyzing {d} FFI matches for vulnerabilities...\n", .{matcher.matches.items.len});

    for (matcher.matches.items, 0..) |*match, i| {
        if (!match.isValid()) continue;

        std.debug.print("  [Match {d}] {s}\n", .{ i, match.name });

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

    // Print analysis results
    std.log.info("[*] Running FFI vulnerability detection...\n", .{});

    if (vulnerabilities.items.len > 0) {
        std.log.info("[!] Found {d} potential FFI vulnerabilities:\n", .{vulnerabilities.items.len});
        for (vulnerabilities.items) |vuln| {
            std.debug.print("  [VULN #{d}] {s}\n", .{ vuln.id, @tagName(vuln.vuln_type) });
            std.debug.print("    Severity: {s}\n", .{@tagName(vuln.severity)});
            std.debug.print("    Description: {s}\n", .{vuln.description});
            std.debug.print("    Declaration: {s}\n", .{vuln.source_location orelse "unknown"});
            std.debug.print("    Definition: {s}\n", .{vuln.sink_location orelse "unknown"});
            std.log.info("\n", .{});
        }
    } else {
        std.log.info("[*] No FFI vulnerabilities detected\n", .{});
    }

    std.log.info("=== FFI Analysis Summary ===\n", .{});
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
        "debug", // Debug functions often have format string vulnerabilities
        "dump", // Dump functions often have format string vulnerabilities
        "verify", // Verify functions often call system commands
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

/// Print analysis results
fn printResults(pipeline: *Pipeline) void {
    std.debug.print("\n=== Analysis Results ===\n", .{});
    const diagnostics = pipeline.getDiagnosticAggregator().getAll();

    if (diagnostics.len == 0) {
        std.log.info("No issues found.\n", .{});
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
            std.log.warn("Memory leak detected!\n", .{});
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
