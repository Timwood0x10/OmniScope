//! OmniScope — Cross-Language Memory Safety Analysis
//!
//! Entry point: parses config, initializes GPA, dispatches to pipeline runner.

const std = @import("std");
const OmniScope = @import("OmniScope");
const log = OmniScope.log;
const main_config = OmniScope.config.main_config;
const file_config = OmniScope.config.file_config;
const Config = main_config.Config;

const pipeline_runner = @import("pipeline_runner.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            if (log.current_log_level != .quiet) {
                log.warn("Memory leak detected!\n", .{});
            }
        }
    }

    const allocator = gpa.allocator();

    OmniScope.semantics.initZoneCache(allocator);
    defer OmniScope.semantics.deinitZoneCache();

    var config = try main_config.parseArgs(allocator);
    defer config.deinit(allocator);

    if (config.config_path) |path| {
        if (std.mem.eql(u8, path, "__init__")) {
            const default_config = try file_config.generateDefaultConfig(allocator);
            defer allocator.free(default_config);

            const out_path = "omniscope.json";
            const file = std.fs.cwd().createFile(out_path, .{}) catch |err| {
                log.err("Failed to create config file '{s}': {}\n", .{ out_path, err });
                return err;
            };
            defer file.close();

            file.writeAll(default_config) catch |err| {
                log.err("Failed to write config file: {}\n", .{err});
                return err;
            };

            log.info("Generated default config: {s}\n", .{out_path});
            return;
        }
    }

    if (config.config_path) |config_path| {
        log.info("CONFIG: Will load explicit config from {s}\n", .{config_path});
    } else {
        if (file_config.discoverConfigFile()) |discovered_path| {
            log.info("CONFIG: Discovered config at {s}\n", .{discovered_path});
            config.config_path = allocator.dupe(u8, discovered_path) catch null;
        }
    }

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
        main_config.showHelp();
        return;
    }

    if (config.show_version) {
        log.info("OmniScope v0.1.9\n", .{});
        return;
    }

    if (config.input_files.items.len == 0) {
        log.info("Error: No input file specified\n", .{});
        return error.NoInputFile;
    }

    if (config.input_files.items.len == 1) {
        try pipeline_runner.runSingleFileAnalysis(allocator, config.input_files.items[0], config);
    } else {
        try pipeline_runner.runMultiFileAnalysis(allocator, config.input_files.items, config);
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
    const config = try main_config.parseArgs(std.testing.allocator);
    defer config.deinit(std.testing.allocator);

    try std.testing.expect(!config.show_help);
}

test "parseArgs - no input files" {
    const config = try main_config.parseArgs(std.testing.allocator);
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), config.input_files.items.len);
}
