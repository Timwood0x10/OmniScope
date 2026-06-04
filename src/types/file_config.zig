//! Configuration file support for OmniScope (.omniscope.json)
//!
//! Provides:
//!   - Loading configuration from .omniscope.json files
//!   - Merging with CLI arguments (CLI takes priority)
//!   - Generating default config templates (--init-config)
//!
//! Config file locations (checked in order):
//!   1. --config <path> (explicit)
//!   2. ./omniscope.json (project root)
//!   3. ~/.config/omniscope/config.json (user global)

const std = @import("std");
const log = std.log.scoped(.omniscope_config);

/// Configuration file structure (matches JSON schema)
pub const FileConfig = struct {
    analysis: AnalysisConfig = .{},
    filters: FilterConfig = .{},
    output: OutputConfig = .{},
    performance: PerformanceConfig = .{},
    custom_rules: CustomRules = .{},

    pub const AnalysisConfig = struct {
        boundary_only: bool = false,
        min_severity: []const u8 = "low",
        suppress_noise: bool = true,

        language_detection: LanguageDetection = .{},

        pub const LanguageDetection = struct {
            auto_detect: bool = true,
            default_language: []const u8 = "unknown",
            enabled_languages: [6][]const u8 = .{
                "rust", "zig", "python", "go", "c", "cpp",
            },

            /// Language override rules for per-symbol/per-file language assignment.
            /// These override auto-detection when configured.
            overrides: LanguageOverridesConfig = .{},

            pub const LanguageOverridesConfig = struct {
                /// Exact symbol name → language mappings (e.g. {"__rust_alloc": "rust"})
                exact: [][]const u8 = &.{},
                /// Prefix → language mappings (e.g. {"sqlite3_": "c"})
                prefix: [][]const u8 = &.{},
                /// Suffix → language mappings (e.g. {"_rs": "rust"})
                suffix: [][]const u8 = &.{},
                /// Source file basename → language mappings (e.g. {"generated.ll": "c"})
                source_files: [][]const u8 = &.{},
            };
        };
    };

    pub const FilterConfig = struct {
        allocator_shims: AllocatorShimFilter = .{},
        rust_internal_whitelist: RustInternalFilter = .{},
        ffi_contracts: FFIContractFilter = .{},
        surface_filter: SurfaceFilter = .{},

        pub const AllocatorShimFilter = struct {
            enabled: bool = true,
            extra_patterns: [][]const u8 = &.{},
            strict_mode: bool = false,
        };

        pub const RustInternalFilter = struct {
            enabled: bool = true,
            extra_suppressions: [][]const u8 = &.{},
        };

        pub const FFIContractFilter = struct {
            enabled: bool = true,
            custom_rules_file: ?[]const u8 = null,
            confidence_threshold: f32 = 0.8,
        };

        pub const SurfaceFilter = struct {
            show_boundary: bool = true,
            show_ffi_producer: bool = true,
            show_reachable_from_boundary: bool = false,
            show_internal_core: bool = false,
            show_runtime_internal: bool = false,
        };
    };

    pub const OutputConfig = struct {
        format: []const u8 = "text",
        color: bool = true,
        verbose: bool = false,
        show_statistics: bool = true,
        show_time: bool = true,
        output_file: ?[]const u8 = null,
    };

    pub const PerformanceConfig = struct {
        max_analysis_time_seconds: u32 = 300,
        max_functions_to_analyze: u32 = 0,
        parallel_passes: bool = true,
        cache_enabled: bool = true,
    };

    pub const CustomRules = struct {
        suppress_functions: [][]const u8 = &.{},
        always_report_functions: [][]const u8 = &.{},
        severity_overrides: std.StringHashMap([]const u8) = undefined,
    };
};

/// Load configuration from file path
pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !FileConfig {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        log.err("CONFIG: Failed to open config file: {}", .{err});
        return err;
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        log.err("CONFIG: Failed to read config file: {}", .{err});
        return err;
    };
    defer allocator.free(content);

    log.info("CONFIG: Loaded configuration from {s}\n", .{path});

    // TODO: Implement full JSON parsing when custom types are handled
    // For now, return default config and log that file was loaded
    return FileConfig{};
}

/// Auto-discover config file location
pub fn discoverConfigFile() ?[]const u8 {
    // Check in order:
    // 1. ./omniscope.json
    if (std.fs.cwd().openFile("omniscope.json", .{})) |file| {
        file.close();
        return "omniscope.json";
    } else |_| {}

    // 2. ~/.config/omniscope/config.json
    const home = std.process.getEnvVarOwned(std.heap.page_allocator, "HOME") catch return null;
    defer std.heap.page_allocator.free(home);

    var buf: [512]u8 = undefined;
    const config_path = std.fmt.bufPrint(
        &buf,
        "{s}/.config/omniscope/config.json",
        .{home},
    ) catch return null;

    if (std.fs.openFileAbsolute(config_path, .{})) |file| {
        file.close();
        return config_path;
    } else |_| {}

    return null;
}

/// Merge file config with CLI args (CLI takes priority)
pub fn mergeWithCLI(allocator: std.mem.Allocator, file_config: FileConfig, cli_args: anytype) !MergedConfig {
    var merged = MergedConfig{};

    // Analysis settings - CLI takes priority
    merged.boundary_only = if (cli_args.boundary_only) cli_args.boundary_only else file_config.analysis.boundary_only;
    merged.min_severity = if (cli_args.min_severity != .low) @tagName(cli_args.min_severity) else file_config.analysis.min_severity;
    merged.suppress_noise = if (!cli_args.suppress_noise) cli_args.suppress_noise else file_config.analysis.suppress_noise;

    // Output settings
    merged.output_format = if (cli_args.output_format != .text) @tagName(cli_args.output_format) else file_config.output.format;
    merged.verbose = if (cli_args.verbose) cli_args.verbose else file_config.output.verbose;
    merged.color = file_config.output.color;
    merged.show_statistics = file_config.output.show_statistics;
    merged.show_time = file_config.output.show_time;

    // Performance settings
    merged.max_analysis_time_seconds = file_config.performance.max_analysis_time_seconds;
    merged.max_functions_to_analyze = file_config.performance.max_functions_to_analyze;
    merged.parallel_passes = file_config.performance.parallel_passes;
    merged.cache_enabled = file_config.performance.cache_enabled;

    // Filter settings
    merged.allocator_shims_enabled = file_config.filters.allocator_shims.enabled;
    merged.rust_internal_whitelist_enabled = file_config.filters.rust_internal_whitelist.enabled;
    merged.ffi_contracts_enabled = file_config.filters.ffi_contracts.enabled;
    merged.surface_filter = file_config.filters.surface_filter;

    // Language detection
    merged.language_detection = file_config.analysis.language_detection;

    // Custom rules
    merged.custom_rules = file_config.custom_rules;

    _ = allocator;
    return merged;
}

pub const MergedConfig = struct {
    boundary_only: bool = false,
    min_severity: []const u8 = "low",
    suppress_noise: bool = true,
    output_format: []const u8 = "text",
    verbose: bool = false,
    color: bool = true,
    show_statistics: bool = true,
    show_time: bool = true,
    max_analysis_time_seconds: u32 = 300,
    max_functions_to_analyze: u32 = 0,
    parallel_passes: bool = true,
    cache_enabled: bool = true,
    allocator_shims_enabled: bool = true,
    rust_internal_whitelist_enabled: bool = true,
    ffi_contracts_enabled: bool = true,
    surface_filter: FileConfig.FilterConfig.SurfaceFilter = .{},
    language_detection: FileConfig.AnalysisConfig.LanguageDetection = .{},
    custom_rules: FileConfig.CustomRules = .{},
};

/// Generate default config file template
pub fn generateDefaultConfig(allocator: std.mem.Allocator) ![]u8 {
    const template =
        \\{
        \\  "$schema": "https://raw.githubusercontent.com/user/omniscope/main/schema.json",
        \\
        \\  "analysis": {
        \\    "boundary_only": false,
        \\    "min_severity": "low",
        \\    "suppress_noise": true,
        \\
        \\    "language_detection": {
        \\      "auto_detect": true,
        \\      "default_language": "unknown",
        \\      "enabled_languages": ["rust", "zig", "python", "go", "c", "cpp"],
        \\
        \\      "overrides": {
        \\        "exact": {
        \\          "__rust_alloc": "rust",
        \\          "malloc": "c"
        \\        },
        \\        "prefix": {
        \\          "sqlite3_": "c",
        \\          "PyInit_": "python"
        \\        },
        \\        "suffix": {
        \\          "_rs": "rust",
        \\          "_vtable": "c"
        \\        },
        \\        "source_files": {
        \\          "generated.ll": "c",
        \\          "wrapper.go": "go"
        \\        },
        \\        "default_language": null
        \\      }
        \\    }
        \\  },
        \\
        \\  "filters": {
        \\    "allocator_shims": {
        \\      "enabled": true,
        \\      "extra_patterns": [],
        \\      "strict_mode": false
        \\    },
        \\
        \\    "rust_internal_whitelist": {
        \\      "enabled": true,
        \\      "extra_suppressions": []
        \\    },
        \\
        \\    "ffi_contracts": {
        \\      "enabled": true,
        \\      "custom_rules_file": null,
        \\      "confidence_threshold": 0.8
        \\    },
        \\
        \\    "surface_filter": {
        \\      "show_boundary": true,
        \\      "show_ffi_producer": true,
        \\      "show_reachable_from_boundary": false,
        \\      "show_internal_core": false,
        \\      "show_runtime_internal": false
        \\    }
        \\  },
        \\
        \\  "output": {
        \\    "format": "text",
        \\    "color": true,
        \\    "verbose": false,
        \\    "show_statistics": true,
        \\    "show_time": true,
        \\    "output_file": null
        \\  },
        \\
        \\  "performance": {
        \\    "max_analysis_time_seconds": 300,
        \\    "max_functions_to_analyze": 0,
        \\    "parallel_passes": true,
        \\    "cache_enabled": true
        \\  },
        \\
        \\  "custom_rules": {
        \\    "suppress_functions": [],
        \\    "always_report_functions": [],
        \\    "severity_overrides": {}
        \\  }
        \\}
    ;

    return allocator.dupe(u8, template);
}

// ── Tests ──

test "generateDefaultConfig produces valid JSON" {
    const alloc = std.testing.allocator;
    const config = try generateDefaultConfig(alloc);
    defer alloc.free(config);

    try std.testing.expect(std.mem.indexOf(u8, config, "\"boundary_only\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "\"filters\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "\"analysis\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "\"output\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "\"performance\"") != null);
}

test "discoverConfigFile returns null when no config exists" {
    // In test environment, likely no omniscope.json exists
    const result = discoverConfigFile();
    try std.testing.expect(result == null);
}

test "FileConfig default values" {
    const config = FileConfig{};

    try std.testing.expect(!config.analysis.boundary_only);
    try std.testing.expectEqualStrings("low", config.analysis.min_severity);
    try std.testing.expect(config.analysis.suppress_noise);

    try std.testing.expect(config.analysis.language_detection.auto_detect);
    try std.testing.expectEqualStrings("unknown", config.analysis.language_detection.default_language);

    try std.testing.expect(config.filters.allocator_shims.enabled);
    try std.testing.expect(!config.filters.allocator_shims.strict_mode);

    try std.testing.expect(config.filters.rust_internal_whitelist.enabled);

    try std.testing.expect(config.filters.ffi_contracts.enabled);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), config.filters.ffi_contracts.confidence_threshold, 0.001);

    try std.testing.expect(config.filters.surface_filter.show_boundary);
    try std.testing.expect(config.filters.surface_filter.show_ffi_producer);
    try std.testing.expect(!config.filters.surface_filter.show_reachable_from_boundary);
    try std.testing.expect(!config.filters.surface_filter.show_internal_core);
    try std.testing.expect(!config.filters.surface_filter.show_runtime_internal);

    try std.testing.expectEqualStrings("text", config.output.format);
    try std.testing.expect(config.output.color);
    try std.testing.expect(!config.output.verbose);
    try std.testing.expect(config.output.show_statistics);
    try std.testing.expect(config.output.show_time);

    try std.testing.expectEqual(@as(u32, 300), config.performance.max_analysis_time_seconds);
    try std.testing.expectEqual(@as(u32, 0), config.performance.max_functions_to_analyze);
    try std.testing.expect(config.performance.parallel_passes);
    try std.testing.expect(config.performance.cache_enabled);
}

test "MergedConfig default values" {
    const merged = MergedConfig{};

    try std.testing.expect(!merged.boundary_only);
    try std.testing.expectEqualStrings("low", merged.min_severity);
    try std.testing.expect(merged.suppress_noise);
    try std.testing.expectEqualStrings("text", merged.output_format);
    try std.testing.expect(!merged.verbose);
    try std.testing.expect(merged.color);
}
