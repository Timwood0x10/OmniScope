const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Terminal ANSI Colors — auto-disabled when stdout is not a TTY
// ============================================================================

pub const term = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const white = "\x1b[37m";
    pub const bright_black = "\x1b[90m";
    pub const bright_red = "\x1b[91m";
    pub const bright_yellow = "\x1b[93m";
    pub const bright_cyan = "\x1b[96m";

    pub fn colorForSeverity(sev: u8) []const u8 {
        return switch (sev) {
            2 => bright_red,
            3 => bright_yellow,
            1 => bright_cyan,
            0 => bright_black,
            else => reset,
        };
    }
};

pub const MainError = error{
    NoInputFile,
    InvalidOption,
};

/// Local severity enum for CLI argument parsing.
/// Avoids importing from common/types.zig to prevent module conflicts.
pub const Severity = enum {
    low,
    medium,
    high,
    critical,

    pub fn parse(name: []const u8) ?Severity {
        if (std.mem.eql(u8, name, "low")) return .low;
        if (std.mem.eql(u8, name, "medium")) return .medium;
        if (std.mem.eql(u8, name, "high")) return .high;
        if (std.mem.eql(u8, name, "critical")) return .critical;
        return null;
    }

    pub fn toCommonSeverity(self: Severity) u8 {
        return switch (self) {
            .low => 0,
            .medium => 1,
            .high => 2,
            .critical => 3,
        };
    }
};

pub const Config = struct {
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
    perf_stats: bool = false, // Enable per-pass performance profiling (wall time, RSS, allocations)
    perf_json_path: ?[]const u8 = null, // Export performance data to JSON file (implies --perf-stats)
    debug_resource_contract: bool = false, // Enable resource contract debugging (implies --debug)

    /// Only report issues on FFI boundaries (ignore internal code noise)
    boundary_only: bool = false,
    /// Minimum severity to report (low, medium, high, critical)
    min_severity: Severity = .low,
    /// Suppress known-safe patterns (allocator shims, rust internals, GC managed)
    suppress_noise: bool = true,

    pub fn init(allocator: Allocator) !Config {
        return .{
            .input_files = std.ArrayList([]const u8).initCapacity(allocator, 0) catch return error.OutOfMemory,
        };
    }

    pub fn deinit(self: *Config, allocator: Allocator) void {
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
        if (self.perf_json_path) |path| {
            if (path.len > 0) {
                allocator.free(path);
            }
        }
    }
};

pub const OutputFormat = enum {
    text,
    json,
    sarif,
};

/// Generic analyze result — avoids importing Issue/Location from diag module.
/// Caller should construct proper result types.
pub const AnalyzeResult = struct {
    func_count: usize,
    fact_count: usize,
    time_ms: u64,
};

pub fn parseArgs(allocator: Allocator) !Config {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    var config = try Config.init(allocator);
    errdefer config.deinit(allocator);

    _ = args.next();

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
                return error.InvalidOption;
            };
            if (output_file.len == 0) {
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
        } else if (std.mem.eql(u8, arg, "--perf-stats")) {
            config.perf_stats = true;
        } else if (std.mem.eql(u8, arg, "--perf-json")) {
            const json_path = args.next() orelse {
                return error.InvalidOption;
            };
            if (json_path.len == 0) {
                return error.InvalidOption;
            }
            config.perf_json_path = try allocator.dupe(u8, json_path);
            config.perf_stats = true; // --perf-json implies --perf-stats
        } else if (std.mem.eql(u8, arg, "--debug-resource-contract")) {
            config.debug_resource_contract = true;
            config.debug = true; // implicitly enable debug
        } else if (arg.len > 0 and arg[0] == '-') {
            return error.InvalidOption;
        } else {
            const arg_copy = try allocator.dupe(u8, arg);
            errdefer allocator.free(arg_copy);
            try config.input_files.append(allocator, arg_copy);
        }
    }

    return config;
}

pub fn showHelp() void {
    const help_text =
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
        \\  --perf-stats                      Enable per-pass performance profiling (time, RSS, allocations)
        \\  --perf-json <path>                 Export performance data to JSON file (implies --perf-stats)
        \\  --debug-resource-contract         Enable resource contract debugging (implies --debug)
        \\  --version           Show version information
        \\  --json              Output in JSON format
        \\  --sarif             Output in SARIF format
        \\  -o, --output <file> Write output to file
        \\
        \\Multi-File Mode (auto-detected when 2+ files given):
        \\  omniscope rust.bc c.bc
        \\  Runs full pipeline on each file + cross-language FFI matching
        \\
    ;
    std.log.info("{s}", .{help_text});
}

// ============================================================================
// Tests
// ============================================================================

test "Severity - parse valid values" {
    try std.testing.expectEqual(Severity.low, Severity.parse("low").?);
    try std.testing.expectEqual(Severity.medium, Severity.parse("medium").?);
    try std.testing.expectEqual(Severity.high, Severity.parse("high").?);
    try std.testing.expectEqual(Severity.critical, Severity.parse("critical").?);
}

test "Severity - parse invalid values" {
    try std.testing.expect(Severity.parse("invalid") == null);
    try std.testing.expect(Severity.parse("") == null);
    try std.testing.expect(Severity.parse("LOW") == null); // case-sensitive
    try std.testing.expect(Severity.parse("Low") == null); // case-sensitive
}

test "Severity - toCommonSeverity conversion" {
    try std.testing.expectEqual(@as(u8, 0), Severity.low.toCommonSeverity());
    try std.testing.expectEqual(@as(u8, 1), Severity.medium.toCommonSeverity());
    try std.testing.expectEqual(@as(u8, 2), Severity.high.toCommonSeverity());
    try std.testing.expectEqual(@as(u8, 3), Severity.critical.toCommonSeverity());
}
