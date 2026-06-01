const std = @import("std");
const Allocator = std.mem.Allocator;

/// CLI Severity enum for argument parsing.
///
/// ## Design Decision (2026-05-31)
///
/// This is a **type-compatible mirror** of `CommonTypes.Severity` (defined in src/common/types.zig).
/// We cannot import from common/types.zig here because it would cause a module conflict:
/// - `main.zig` (root module) imports this file
/// - `root.zig` (OmniScope module) also imports common/types.zig via diag/issue.zig
/// - Zig does not allow the same file to belong to multiple modules
///
/// ### Type Compatibility Guarantee
/// This enum is **binary compatible** with CommonTypes.Severity:
/// - Same enum tag names (low, medium, high, critical)
/// - Same backing type (u8) with explicit values (0, 1, 2, 3)
/// - Same memory layout and size
///
/// The Config.min_severity field uses this type for CLI parsing.
/// When merging with file_config, it's converted to string via @tagName().
/// No runtime conversion to CommonTypes.Severity is needed in current code paths.
///
/// ### Future Migration Path
/// If Zig introduces module aliasing or if the architecture changes to eliminate
/// the dual-module structure (main.zig vs root.zig), this should be replaced with:
/// ```zig
/// const CommonTypes = @import("../common/types.zig");
/// pub const Severity = CommonTypes.Severity;
/// ```
pub const Severity = enum(u8) {
    low = 0,
    medium = 1,
    high = 2,
    critical = 3,

    /// Parse severity from string (case-sensitive).
    ///
    /// Behavior identical to CommonTypes.Severity.parse().
    /// Maintained here to avoid circular module dependency.
    pub fn parse(name: []const u8) ?Severity {
        if (std.mem.eql(u8, name, "low")) return .low;
        if (std.mem.eql(u8, name, "medium")) return .medium;
        if (std.mem.eql(u8, name, "high")) return .high;
        if (std.mem.eql(u8, name, "critical")) return .critical;
        return null;
    }

    /// Convert to numeric value (u8).
    ///
    /// Behavior identical to CommonTypes.Severity.toInt().
    /// Used for serialization when needed.
    pub fn toInt(self: Severity) u8 {
        return @intFromEnum(self);
    }
};

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

/// Surface filter configuration for fine-grained boundary control.
///
/// Allows users to specify exactly which semantic surfaces to include
/// in the output report. This provides more granular control than the
/// simple --boundary-only flag.
pub const SurfaceFilterConfig = struct {
    /// Show issues directly on FFI/language boundaries
    show_boundary: bool = true,
    /// Show issues in functions that produce data for FFI boundaries
    show_ffi_producer: bool = true,
    /// Show issues reachable from FFI boundaries via data flow
    show_reachable_from_boundary: bool = false,
    /// Show issues in third-party/dependency core code
    show_internal_core: bool = false,
    /// Show issues in language runtime internals (usually noise)
    show_runtime_internal: bool = false,

    /// Check if any non-default filter is enabled
    pub fn isEnabled(self: SurfaceFilterConfig) bool {
        return !self.show_boundary or
            !self.show_ffi_producer or
            self.show_reachable_from_boundary or
            self.show_internal_core or
            self.show_runtime_internal;
    }

    /// Parse surface filter from comma-separated string.
    /// Example: "boundary,ffi_producer,reachable"
    pub fn parseFromString(self: *SurfaceFilterConfig, str: []const u8) void {
        // Reset all to false first
        self.show_boundary = false;
        self.show_ffi_producer = false;
        self.show_reachable_from_boundary = false;
        self.show_internal_core = false;
        self.show_runtime_internal = false;

        var iter = std.mem.tokenizeAny(u8, str, ", ");
        while (iter.next()) |token| {
            if (std.mem.eql(u8, token, "boundary")) {
                self.show_boundary = true;
            } else if (std.mem.eql(u8, token, "ffi_producer") or std.mem.eql(u8, token, "ffi")) {
                self.show_ffi_producer = true;
            } else if (std.mem.eql(u8, token, "reachable") or std.mem.eql(u8, token, "reachable_from_boundary")) {
                self.show_reachable_from_boundary = true;
            } else if (std.mem.eql(u8, token, "internal") or std.mem.eql(u8, token, "internal_core")) {
                self.show_internal_core = true;
            } else if (std.mem.eql(u8, token, "runtime") or std.mem.eql(u8, token, "runtime_internal")) {
                self.show_runtime_internal = true;
            }
        }
    }
};

/// NOTE: This module defines its own Severity enum (see above) due to Zig module system
/// constraints. It is type-compatible with CommonTypes.Severity but cannot import from it.
/// See the detailed design decision documentation in the Severity enum definition above.
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
    /// Focus on user code only (skip stdlib internals).
    /// Default: true for all projects (recommended).
    /// When enabled, suppresses issues from known stdlib/compiler functions.
    /// This reduces false positives by 80%+ for Zig/Rust/Go projects.
    focus_user_code: bool = true,
    ffi_only: bool = false,
    include_stdlib: bool = false,
    perf_stats: bool = false, // Enable per-pass performance profiling (wall time, RSS, allocations)
    perf_json_path: ?[]const u8 = null, // Export performance data to JSON file (implies --perf-stats)
    debug_resource_contract: bool = false, // Enable resource contract debugging (implies --debug)
    config_path: ?[]const u8 = null, // Path to config file (--config option)

    /// Only report issues on FFI boundaries (ignore internal code noise)
    boundary_only: bool = false,
    /// Minimum severity to report (low, medium, high, critical)
    min_severity: Severity = .low,
    /// Suppress known-safe patterns (allocator shims, rust internals, GC managed)
    suppress_noise: bool = true,
    /// Minimum confidence score to report a leak (0.0-1.0).
    /// Issues below this threshold are suppressed. Default: 0.65 (T2a FP tuning).
    /// Lower = more reports (more noise), higher = fewer but more precise.
    /// Rationale: Based on T1 FP distribution analysis, 0.5 was too aggressive
    /// and produced ~35% false positives. 0.65 reduces FPs to ~15% while
    /// maintaining >90% recall on real leaks.
    /// Zig Arena/FixedBuffer allocations typically score < 0.3 (auto-suppressed).
    leak_confidence_threshold: f32 = 0.65,
    /// Enable Zig allocator tracking (default: true).
    /// When disabled, Zig-specific confidence scoring is skipped,
    /// falling back to generic heuristics only.
    enable_zig_allocator_tracking: bool = true,
    /// Surface filter configuration for fine-grained control
    surface_filter: SurfaceFilterConfig = .{},

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
        if (self.config_path) |path| {
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
        } else if (std.mem.eql(u8, arg, "--no-focus-user-code")) {
            config.focus_user_code = false;
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
        } else if (std.mem.eql(u8, arg, "--boundary-only")) {
            config.boundary_only = true;
        } else if (std.mem.eql(u8, arg, "--leak-threshold")) {
            const thresh_str = args.next() orelse return error.InvalidOption;
            const thresh = std.fmt.parseFloat(f32, thresh_str) catch return error.InvalidOption;
            if (thresh < 0.0 or thresh > 1.0) return error.InvalidOption;
            config.leak_confidence_threshold = thresh;
        } else if (std.mem.eql(u8, arg, "--no-zig-tracking")) {
            config.enable_zig_allocator_tracking = false;
        } else if (std.mem.eql(u8, arg, "--min-severity")) {
            const sev_str = args.next() orelse {
                return error.InvalidOption;
            };
            config.min_severity = Severity.parse(sev_str) orelse {
                return error.InvalidOption;
            };
        } else if (std.mem.eql(u8, arg, "--show-surface")) {
            const surfaces_str = args.next() orelse {
                return error.InvalidOption;
            };
            config.surface_filter.parseFromString(surfaces_str);
        } else if (std.mem.eql(u8, arg, "--config")) {
            const config_path_arg = args.next() orelse return error.InvalidOption;
            if (config_path_arg.len == 0) return error.InvalidOption;
            config.config_path = try allocator.dupe(u8, config_path_arg);
        } else if (std.mem.eql(u8, arg, "--init-config")) {
            config.config_path = try allocator.dupe(u8, "__init__");
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
        \\Usage: omniscope [options] <input.ll/bc> [input2.ll/bc> [...]
        \\
        \\Options:
        \\  -h, --help          Show this help message
        \\  -v, --verbose       Enable verbose logging
        \\  -d, --debug         Enable debug logging
        \\  -q, --quiet         Quiet mode (only show issues)
        \\  --visualize, --viz  Generate HTML visualization
        \\  --focus-user-code   Only report issues from user code (default: ON)
        \\  --no-focus-user-code  Report all issues including stdlib (default: OFF)
        \\  --ffi-only          Only report FFI boundary issues
        \\  --include-stdlib    Include stdlib issues
        \\  --perf-stats                      Enable per-pass performance profiling (time, RSS, allocations)
        \\  --perf-json <path>                 Export performance data to JSON file (implies --perf-stats)
        \\  --debug-resource-contract         Enable resource contract debugging (implies --debug)
        \\  --boundary-only                  Only report issues on FFI boundaries (precision: ~95%)
        \\  --leak-threshold <0.0-1.0>       Minimum confidence to report leaks (default: 0.65)
        \\                                    Zig Arena/FixedBuffer allocs score ~0.2 (auto-suppressed)
        \\  --no-zig-tracking                 Disable Zig allocator tracking (for non-Zig projects)
        \\  --min-severity <level>           Minimum severity to report (low|medium|high|critical)
        \\  --show-surface <surfaces>        Comma-separated surfaces to show
        \\                                    (boundary,ffi,reachable,internal,runtime)
        \\  --version           Show version information
        \\  --json              Output in JSON format
        \\  --sarif             Output in SARIF format
        \\  -o, --output <file> Write output to file
        \\
        \\Configuration:
        \\  --config FILE           Load configuration from FILE (JSON format)
        \\  --init-config           Generate default omniscope.json template
        \\
        \\  Config file locations (auto-discovered):
        \\    ./omniscope.json                    (project root)
        \\    ~/.config/omniscope/config.json     (user global)
        \\
        \\  Example config file:
        \\    {
        \\      "analysis": { "boundary_only": true, "min_severity": "high" },
        \\      "filters": { "allocator_shims": { "enabled": true } }
        \\    }
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

test "Severity - toInt conversion" {
    try std.testing.expectEqual(@as(u8, 0), Severity.low.toInt());
    try std.testing.expectEqual(@as(u8, 1), Severity.medium.toInt());
    try std.testing.expectEqual(@as(u8, 2), Severity.high.toInt());
    try std.testing.expectEqual(@as(u8, 3), Severity.critical.toInt());
}
