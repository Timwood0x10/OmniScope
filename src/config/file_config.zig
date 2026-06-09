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
const language_override = @import("language_override.zig");

/// Configuration file structure (matches JSON schema)
pub const FileConfig = struct {
    analysis: AnalysisConfig = .{},
    filters: FilterConfig = .{},
    output: OutputConfig = .{},
    performance: PerformanceConfig = .{},
    custom_rules: CustomRules = .{},

    /// Populated language override registry from config file.
    /// Null if no overrides section was present or loading failed.
    lang_registry: ?language_override.LanguageOverrideRegistry = null,

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

    /// Release all owned memory in this config.
    ///
    /// Must be called when the config is no longer needed, especially when
    /// lang_registry was populated from a JSON config file (owns heap memory).
    pub fn deinit(self: *FileConfig) void {
        if (self.lang_registry) |*reg| {
            reg.deinit();
            self.lang_registry = null;
        }
    }
};

/// Load configuration from file path.
///
/// Parses the full JSON structure including language detection overrides.
/// The returned FileConfig.lang_registry contains the populated override rules.
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

    var config = FileConfig{};

    // Parse the full JSON document using dynamic Value type
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{
        .allocate = .alloc_always,
    }) catch |err| {
        log.warn("CONFIG: JSON parse error in {s}: {}. Using default config.", .{ path, err });
        return config;
    };
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return config;

    // Extract analysis settings
    if (root.object.get("analysis")) |analysis_obj| {
        if (analysis_obj == .object) {
            config.analysis = parseAnalysisConfig(analysis_obj.object);
        }
    }

    // Extract filter settings
    if (root.object.get("filters")) |filter_obj| {
        if (filter_obj == .object) {
            config.filters = parseFilterConfig(filter_obj.object);
        }
    }

    // Extract output settings
    if (root.object.get("output")) |output_obj| {
        if (output_obj == .object) {
            config.output = parseOutputConfig(output_obj.object);
        }
    }

    // Extract performance settings
    if (root.object.get("performance")) |perf_obj| {
        if (perf_obj == .object) {
            config.performance = parsePerformanceConfig(perf_obj.object);
        }
    }

    // Extract language detection overrides into registry
    if (root.object.get("analysis")) |analysis_obj| {
        if (analysis_obj == .object) {
            if (analysis_obj.object.get("language_detection")) |ld_obj| {
                if (ld_obj == .object) {
                    if (ld_obj.object.get("overrides")) |overrides_obj| {
                        if (overrides_obj == .object) {
                            var registry = try language_override.LanguageOverrideRegistry.init(allocator);

                            // Parse exact matches from JSON object
                            if (overrides_obj.object.get("exact")) |exact_obj| {
                                if (exact_obj == .object) {
                                    var iter = exact_obj.object.iterator();
                                    while (iter.next()) |entry| {
                                        if (entry.value_ptr.* == .string) {
                                            const lang = language_override.LanguageOverrideRegistry.parseLangString((entry.value_ptr.*).string) orelse continue;
                                            try registry.addExact(entry.key_ptr.*, lang);
                                        }
                                    }
                                }
                            }

                            // Parse prefix rules
                            if (overrides_obj.object.get("prefix")) |prefix_obj| {
                                if (prefix_obj == .object) {
                                    var iter = prefix_obj.object.iterator();
                                    while (iter.next()) |entry| {
                                        if (entry.value_ptr.* == .string) {
                                            const lang = language_override.LanguageOverrideRegistry.parseLangString((entry.value_ptr.*).string) orelse continue;
                                            try registry.addPrefix(entry.key_ptr.*, lang);
                                        }
                                    }
                                    registry.sortPrefixRules();
                                }
                            }

                            // Parse suffix rules
                            if (overrides_obj.object.get("suffix")) |suffix_obj| {
                                if (suffix_obj == .object) {
                                    var iter = suffix_obj.object.iterator();
                                    while (iter.next()) |entry| {
                                        if (entry.value_ptr.* == .string) {
                                            const lang = language_override.LanguageOverrideRegistry.parseLangString((entry.value_ptr.*).string) orelse continue;
                                            try registry.addSuffix(entry.key_ptr.*, lang);
                                        }
                                    }
                                    registry.sortSuffixRules();
                                }
                            }

                            // Parse source file mappings
                            if (overrides_obj.object.get("source_files")) |sf_obj| {
                                if (sf_obj == .object) {
                                    var iter = sf_obj.object.iterator();
                                    while (iter.next()) |entry| {
                                        if (entry.value_ptr.* == .string) {
                                            const lang = language_override.LanguageOverrideRegistry.parseLangString((entry.value_ptr.*).string) orelse continue;
                                            try registry.addSourceFile(entry.key_ptr.*, lang);
                                        }
                                    }
                                }
                            }

                            config.lang_registry = registry;
                        }
                    }

                    // Also check top-level default_language in language_detection
                    if (ld_obj.object.get("default_language")) |dl_val| {
                        if (dl_val == .string) {
                            if (config.lang_registry) |*reg| {
                                if (language_override.LanguageOverrideRegistry.parseLangString(dl_val.string)) |lang| {
                                    reg.setDefault(lang);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    return config;
}

/// Parse analysis configuration section from JSON object.
fn parseAnalysisConfig(obj: std.json.ObjectMap) FileConfig.AnalysisConfig {
    var boundary_only = false;
    var min_severity: []const u8 = "low";
    var suppress_noise = true;
    var auto_detect = true;
    var default_language: []const u8 = "unknown";

    if (obj.get("boundary_only")) |v| {
        if (v == .bool) boundary_only = v.bool;
    }
    if (obj.get("min_severity")) |v| {
        if (v == .string) min_severity = v.string;
    }
    if (obj.get("suppress_noise")) |v| {
        if (v == .bool) suppress_noise = v.bool;
    }

    if (obj.get("language_detection")) |ld| {
        if (ld == .object) {
            if (ld.object.get("auto_detect")) |v| {
                if (v == .bool) auto_detect = v.bool;
            }
            if (ld.object.get("default_language")) |v| {
                if (v == .string) default_language = v.string;
            }
        }
    }

    return .{
        .boundary_only = boundary_only,
        .min_severity = min_severity,
        .suppress_noise = suppress_noise,
        .language_detection = .{
            .auto_detect = auto_detect,
            .default_language = default_language,
        },
    };
}

/// Parse filter configuration section from JSON object.
fn parseFilterConfig(obj: std.json.ObjectMap) FileConfig.FilterConfig {
    var as_enabled = true;
    var as_strict_mode = false;
    var rw_enabled = true;
    var fc_enabled = true;
    var fc_threshold: f32 = 0.8;
    var sf_boundary = true;
    var sf_ffi_producer = true;
    var sf_reachable = false;
    var sf_internal_core = false;
    var sf_runtime_internal = false;

    if (obj.get("allocator_shims")) |as_val| {
        if (as_val == .object) {
            if (as_val.object.get("enabled")) |v| {
                if (v == .bool) as_enabled = v.bool;
            }
            if (as_val.object.get("strict_mode")) |v| {
                if (v == .bool) as_strict_mode = v.bool;
            }
        }
    }

    if (obj.get("rust_internal_whitelist")) |rw| {
        if (rw == .object) {
            if (rw.object.get("enabled")) |v| {
                if (v == .bool) rw_enabled = v.bool;
            }
        }
    }

    if (obj.get("ffi_contracts")) |fc| {
        if (fc == .object) {
            if (fc.object.get("enabled")) |v| {
                if (v == .bool) fc_enabled = v.bool;
            }
            if (fc.object.get("confidence_threshold")) |v| {
                if (v == .float or v == .integer) {
                    fc_threshold = @as(f32, @floatCast(v.float));
                }
            }
        }
    }

    if (obj.get("surface_filter")) |sf| {
        if (sf == .object) {
            if (sf.object.get("show_boundary")) |v| {
                if (v == .bool) sf_boundary = v.bool;
            }
            if (sf.object.get("show_ffi_producer")) |v| {
                if (v == .bool) sf_ffi_producer = v.bool;
            }
            if (sf.object.get("show_reachable_from_boundary")) |v| {
                if (v == .bool) sf_reachable = v.bool;
            }
            if (sf.object.get("show_internal_core")) |v| {
                if (v == .bool) sf_internal_core = v.bool;
            }
            if (sf.object.get("show_runtime_internal")) |v| {
                if (v == .bool) sf_runtime_internal = v.bool;
            }
        }
    }

    return .{
        .allocator_shims = .{ .enabled = as_enabled, .extra_patterns = &.{}, .strict_mode = as_strict_mode },
        .rust_internal_whitelist = .{ .enabled = rw_enabled, .extra_suppressions = &.{} },
        .ffi_contracts = .{ .enabled = fc_enabled, .custom_rules_file = null, .confidence_threshold = fc_threshold },
        .surface_filter = .{
            .show_boundary = sf_boundary,
            .show_ffi_producer = sf_ffi_producer,
            .show_reachable_from_boundary = sf_reachable,
            .show_internal_core = sf_internal_core,
            .show_runtime_internal = sf_runtime_internal,
        },
    };
}

/// Parse output configuration section from JSON object.
fn parseOutputConfig(obj: std.json.ObjectMap) FileConfig.OutputConfig {
    var format: []const u8 = "text";
    var color = true;
    var verbose = false;
    var show_stats = true;
    var show_time = true;

    if (obj.get("format")) |v| {
        if (v == .string) format = v.string;
    }
    if (obj.get("color")) |v| {
        if (v == .bool) color = v.bool;
    }
    if (obj.get("verbose")) |v| {
        if (v == .bool) verbose = v.bool;
    }
    if (obj.get("show_statistics")) |v| {
        if (v == .bool) show_stats = v.bool;
    }
    if (obj.get("show_time")) |v| {
        if (v == .bool) show_time = v.bool;
    }

    return .{
        .format = format,
        .color = color,
        .verbose = verbose,
        .show_statistics = show_stats,
        .show_time = show_time,
        .output_file = null,
    };
}

/// Parse performance configuration section from JSON object.
fn parsePerformanceConfig(obj: std.json.ObjectMap) FileConfig.PerformanceConfig {
    var max_time: u32 = 300;
    var max_funcs: u32 = 0;
    var parallel = true;
    var cache = true;

    if (obj.get("max_analysis_time_seconds")) |v| {
        if (v == .integer) max_time = @as(u32, @intCast(v.integer));
    }
    if (obj.get("max_functions_to_analyze")) |v| {
        if (v == .integer) max_funcs = @as(u32, @intCast(v.integer));
    }
    if (obj.get("parallel_passes")) |v| {
        if (v == .bool) parallel = v.bool;
    }
    if (obj.get("cache_enabled")) |v| {
        if (v == .bool) cache = v.bool;
    }

    return .{
        .max_analysis_time_seconds = max_time,
        .max_functions_to_analyze = max_funcs,
        .parallel_passes = parallel,
        .cache_enabled = cache,
    };
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
