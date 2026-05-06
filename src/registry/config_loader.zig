//! Semantic Registry Config Loader
//!
//! Loads custom function semantics from configuration files.
//! This enables project-specific wrapper functions to be recognized.
//!
//! Config file format (JSON):
//! ```json
//! {
//!   "functions": [
//!     {
//!       "pattern": "run_command",
//!       "match_type": "exact",
//!       "kind": "command_exec",
//!       "severity": "critical",
//!       "consumes_ownership": false,
//!       "transfers_ownership": false,
//!       "requires_null_check": false,
//!       "requires_taint_check": true,
//!       "description": "Execute shell command wrapper"
//!     }
//!   ]
//! }
//! ```

const std = @import("std");
const semantic_registry = @import("semantic_registry.zig");
const types = @import("types.zig");

pub const RiskKind = semantic_registry.RiskKind;
pub const Severity = semantic_registry.Severity;
pub const MatchType = semantic_registry.MatchType;
pub const FunctionSemantics = semantic_registry.FunctionSemantics;

/// Re-export FunctionInfo for backward compatibility.
/// New code should import from types.zig directly.
pub const FunctionInfo = types.FunctionInfo;
pub const Tag = types.Tag;
pub const ZoneTag = types.ZoneTag;

/// Error type for config loading operations.
pub const ConfigError = error{
    /// File not found.
    FileNotFound,
    /// Invalid JSON format.
    InvalidJson,
    /// Invalid config structure.
    InvalidConfig,
    /// Unknown risk kind string.
    UnknownRiskKind,
    /// Unknown severity string.
    UnknownSeverity,
    /// Unknown match type string.
    UnknownMatchType,
    /// Memory allocation failed.
    OutOfMemory,
    /// I/O error.
    IoError,
};

/// Parse RiskKind from string.
fn parseRiskKind(str: []const u8) ConfigError!RiskKind {
    const kind_map = .{
        .{ "command_exec", .command_exec },
        .{ "unchecked_copy", .unchecked_copy },
        .{ "format_string", .format_string },
        .{ "allocator", .allocator },
        .{ "deallocator", .deallocator },
        .{ "rust_ownership", .rust_ownership },
        .{ "borrow_escaped", .borrow_escaped },
        .{ "memory_map", .memory_map },
        .{ "file_io", .file_io },
        .{ "network_io", .network_io },
        .{ "go_cgo_alloc", .go_cgo_alloc },
        .{ "zig_allocator", .zig_allocator },
        .{ "cpp_allocator", .cpp_allocator },
        .{ "dynamic_loading", .dynamic_loading },
        .{ "jni", .jni },
        .{ "python_c_api", .python_c_api },
        .{ "signal_handler", .signal_handler },
        .{ "thread_mgmt", .thread_mgmt },
        .{ "process_mgmt", .process_mgmt },
        .{ "static_buffer", .static_buffer },
    };

    inline for (kind_map) |entry| {
        if (std.mem.eql(u8, str, entry.@"0")) {
            return entry.@"1";
        }
    }

    return ConfigError.UnknownRiskKind;
}

/// Parse Severity from string.
fn parseSeverity(str: []const u8) ConfigError!Severity {
    if (std.mem.eql(u8, str, "low")) return .low;
    if (std.mem.eql(u8, str, "medium")) return .medium;
    if (std.mem.eql(u8, str, "high")) return .high;
    if (std.mem.eql(u8, str, "critical")) return .critical;
    return ConfigError.UnknownSeverity;
}

/// Parse MatchType from string.
fn parseMatchType(str: []const u8) ConfigError!MatchType {
    if (std.mem.eql(u8, str, "exact")) return .exact;
    if (std.mem.eql(u8, str, "contains")) return .contains;
    if (std.mem.eql(u8, str, "suffix")) return .suffix;
    return ConfigError.UnknownMatchType;
}

/// A dynamic semantic registry that can be extended at runtime.
/// Combines built-in semantics with custom loaded semantics.
///
/// Performance optimization:
/// - exact_match_map: O(1) HashMap lookup for exact pattern matches
/// - Linear scan fallback: O(N) for contains/suffix patterns
pub const DynamicRegistry = struct {
    allocator: std.mem.Allocator,
    custom_functions: std.ArrayList(FunctionSemantics),
    /// HashMap for O(1) exact match lookups.
    /// Key: pattern string, Value: index into custom_functions.
    exact_match_map: std.StringHashMap(usize),

    /// Create a new dynamic registry.
    /// Returns error.OutOfMemory if HashMap initialization fails.
    pub fn init(allocator: std.mem.Allocator) !DynamicRegistry {
        return .{
            .allocator = allocator,
            .custom_functions = .{},
            .exact_match_map = std.StringHashMap(usize).init(allocator),
        };
    }

    /// Free all resources.
    pub fn deinit(self: *DynamicRegistry) void {
        // Free allocated strings in custom functions
        for (self.custom_functions.items) |sem| {
            self.allocator.free(sem.pattern);
            self.allocator.free(sem.description);
        }
        self.custom_functions.deinit(self.allocator);
        self.exact_match_map.deinit();
    }

    /// Load custom semantics from a JSON config file.
    pub fn loadFromFile(self: *DynamicRegistry, path: []const u8) ConfigError!void {
        const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
            return switch (err) {
                error.FileNotFound => ConfigError.FileNotFound,
                else => ConfigError.IoError,
            };
        };
        defer file.close();

        const content = file.readToEndAlloc(self.allocator, 1024 * 1024) catch {
            return ConfigError.IoError;
        };
        defer self.allocator.free(content);

        try self.loadFromJson(content);
    }

    /// Load custom semantics from a JSON string.
    pub fn loadFromJson(self: *DynamicRegistry, json_content: []const u8) ConfigError!void {
        const parsed = std.json.parseFromSlice(
            struct {
                functions: []const struct {
                    pattern: []const u8,
                    match_type: []const u8,
                    kind: []const u8,
                    severity: []const u8,
                    consumes_ownership: bool,
                    transfers_ownership: bool,
                    requires_null_check: bool,
                    requires_taint_check: bool,
                    description: []const u8,
                },
            },
            self.allocator,
            json_content,
            .{},
        ) catch {
            return ConfigError.InvalidJson;
        };
        defer parsed.deinit();

        const config = parsed.value;

        for (config.functions) |func| {
            const kind = try parseRiskKind(func.kind);
            const severity = try parseSeverity(func.severity);
            const match_type = try parseMatchType(func.match_type);

            // Duplicate strings to own the memory
            const pattern = self.allocator.dupe(u8, func.pattern) catch {
                return ConfigError.OutOfMemory;
            };
            errdefer self.allocator.free(pattern);

            const description = self.allocator.dupe(u8, func.description) catch {
                self.allocator.free(pattern);
                return ConfigError.OutOfMemory;
            };

            const sem = FunctionSemantics{
                .pattern = pattern,
                .match_type = match_type,
                .kind = kind,
                .severity = severity,
                .consumes_ownership = func.consumes_ownership,
                .transfers_ownership = func.transfers_ownership,
                .requires_null_check = func.requires_null_check,
                .requires_taint_check = func.requires_taint_check,
                .description = description,
            };

            self.custom_functions.append(self.allocator, sem) catch {
                self.allocator.free(pattern);
                self.allocator.free(description);
                return ConfigError.OutOfMemory;
            };

            // Update HashMap for O(1) exact match lookup
            if (match_type == .exact) {
                try self.exact_match_map.put(pattern, self.custom_functions.items.len - 1);
            }
        }
    }

    /// Add a custom function semantics directly.
    pub fn addFunction(self: *DynamicRegistry, sem: FunctionSemantics) ConfigError!void {
        // Duplicate strings to own the memory
        const pattern = self.allocator.dupe(u8, sem.pattern) catch {
            return ConfigError.OutOfMemory;
        };
        errdefer self.allocator.free(pattern);

        const description = self.allocator.dupe(u8, sem.description) catch {
            self.allocator.free(pattern);
            return ConfigError.OutOfMemory;
        };

        const idx = self.custom_functions.items.len;
        try self.custom_functions.append(self.allocator, .{
            .pattern = pattern,
            .match_type = sem.match_type,
            .kind = sem.kind,
            .severity = sem.severity,
            .consumes_ownership = sem.consumes_ownership,
            .transfers_ownership = sem.transfers_ownership,
            .requires_null_check = sem.requires_null_check,
            .requires_taint_check = sem.requires_taint_check,
            .description = description,
        });

        // Update HashMap for O(1) exact match lookup
        if (sem.match_type == .exact) {
            try self.exact_match_map.put(pattern, idx);
        }
    }

    /// Lookup function semantics by name (O(1) for exact matches, O(N) for patterns).
    /// Searches custom functions first, then built-in layers.
    pub fn lookup(self: *const DynamicRegistry, func_name: []const u8) ?FunctionSemantics {
        // O(1) HashMap lookup for exact match
        if (self.exact_match_map.get(func_name)) |idx| {
            return self.custom_functions.items[idx];
        }

        // O(N) linear scan for contains/suffix patterns in custom functions
        for (self.custom_functions.items) |sem| {
            if (matchesPattern(func_name, sem.pattern, sem.match_type)) {
                return sem;
            }
        }

        // Fall back to built-in registry (Layer 1 & 2)
        return semantic_registry.SemanticRegistry.lookup(func_name);
    }

    /// Query function info (simplified version with tags and zone).
    /// Returns FunctionInfo for lightweight pass integration.
    ///
    /// This is the preferred method for analysis passes that only need
    /// to check tags (alloc/free/ffi) and zone classification.
    pub fn query(self: *const DynamicRegistry, func_name: []const u8) ?types.FunctionInfo {
        const sem = self.lookup(func_name) orelse return null;

        // Convert FunctionSemantics to FunctionInfo
        var tags_buf: [4]Tag = undefined;
        var tags_len: usize = 0;

        // Map RiskKind to Tag
        if (sem.kind == .allocator or sem.kind == .go_cgo_alloc or sem.kind == .zig_allocator or sem.kind == .cpp_allocator) {
            tags_buf[tags_len] = .alloc;
            tags_len += 1;
        }
        if (sem.kind == .deallocator) {
            tags_buf[tags_len] = .free;
            tags_len += 1;
        }
        if (sem.transfers_ownership) {
            tags_buf[tags_len] = .transfer;
            tags_len += 1;
        }
        if (sem.kind == .dynamic_loading or sem.kind == .jni or sem.kind == .python_c_api) {
            tags_buf[tags_len] = .ffi;
            tags_len += 1;
        }

        // Map kind to ZoneTag
        const zone = switch (sem.kind) {
            .allocator, .deallocator, .static_buffer => .c_heap,
            .rust_ownership => .rust_owned,
            .go_cgo_alloc => .go_pointer,
            .zig_allocator => .ffi, // Zig allocator is FFI boundary
            .dynamic_loading, .jni, .python_c_api => .ffi,
            else => .unknown,
        };

        return .{
            .tags = tags_buf[0..tags_len],
            .zone = zone,
            .kind = sem.kind,
            .severity = sem.severity,
        };
    }

    /// Check if a function name matches a pattern.
    fn matchesPattern(func_name: []const u8, pattern: []const u8, match_type: MatchType) bool {
        return switch (match_type) {
            .exact => std.mem.eql(u8, func_name, pattern),
            .contains => std.mem.indexOf(u8, func_name, pattern) != null,
            .suffix => std.mem.endsWith(u8, func_name, pattern),
        };
    }

    /// Get the count of custom functions.
    pub fn customCount(self: *const DynamicRegistry) usize {
        return self.custom_functions.items.len;
    }

    /// Get total count of known functions (custom + built-in).
    pub fn totalCount(self: *const DynamicRegistry) usize {
        return self.custom_functions.items.len + semantic_registry.SemanticRegistry.totalCount();
    }
};

// Unit tests

test "parseRiskKind" {
    try std.testing.expectEqual(RiskKind.command_exec, try parseRiskKind("command_exec"));
    try std.testing.expectEqual(RiskKind.unchecked_copy, try parseRiskKind("unchecked_copy"));
    try std.testing.expectEqual(RiskKind.allocator, try parseRiskKind("allocator"));
    try std.testing.expectError(ConfigError.UnknownRiskKind, parseRiskKind("unknown"));
}

test "parseSeverity" {
    try std.testing.expectEqual(Severity.low, try parseSeverity("low"));
    try std.testing.expectEqual(Severity.medium, try parseSeverity("medium"));
    try std.testing.expectEqual(Severity.high, try parseSeverity("high"));
    try std.testing.expectEqual(Severity.critical, try parseSeverity("critical"));
    try std.testing.expectError(ConfigError.UnknownSeverity, parseSeverity("unknown"));
}

test "parseMatchType" {
    try std.testing.expectEqual(MatchType.exact, try parseMatchType("exact"));
    try std.testing.expectEqual(MatchType.contains, try parseMatchType("contains"));
    try std.testing.expectEqual(MatchType.suffix, try parseMatchType("suffix"));
    try std.testing.expectError(ConfigError.UnknownMatchType, parseMatchType("unknown"));
}

test "DynamicRegistry - init and deinit" {
    var registry = try DynamicRegistry.init(std.testing.allocator);
    defer registry.deinit();
    try std.testing.expectEqual(@as(usize, 0), registry.customCount());
}

test "DynamicRegistry - loadFromJson" {
    const json =
        \\{
        \\  "functions": [
        \\    {
        \\      "pattern": "run_command",
        \\      "match_type": "exact",
        \\      "kind": "command_exec",
        \\      "severity": "critical",
        \\      "consumes_ownership": false,
        \\      "transfers_ownership": false,
        \\      "requires_null_check": false,
        \\      "requires_taint_check": true,
        \\      "description": "Execute shell command wrapper"
        \\    }
        \\  ]
        \\}
    ;

    var registry = try DynamicRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.loadFromJson(json);
    try std.testing.expectEqual(@as(usize, 1), registry.customCount());

    const sem = registry.lookup("run_command").?;
    try std.testing.expectEqual(RiskKind.command_exec, sem.kind);
    try std.testing.expectEqual(Severity.critical, sem.severity);
    try std.testing.expect(sem.requires_taint_check);
}

test "DynamicRegistry - lookup falls back to built-in" {
    var registry = try DynamicRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Should find built-in function
    const sem = registry.lookup("malloc").?;
    try std.testing.expectEqual(RiskKind.allocator, sem.kind);
}

test "DynamicRegistry - custom overrides built-in" {
    const json =
        \\{
        \\  "functions": [
        \\    {
        \\      "pattern": "malloc",
        \\      "match_type": "exact",
        \\      "kind": "allocator",
        \\      "severity": "critical",
        \\      "consumes_ownership": false,
        \\      "transfers_ownership": true,
        \\      "requires_null_check": true,
        \\      "requires_taint_check": false,
        \\      "description": "Custom malloc wrapper"
        \\    }
        \\  ]
        \\}
    ;

    var registry = try DynamicRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.loadFromJson(json);

    // Custom should override built-in
    const sem = registry.lookup("malloc").?;
    try std.testing.expectEqual(Severity.critical, sem.severity);
    try std.testing.expectEqualStrings("Custom malloc wrapper", sem.description);
}

test "DynamicRegistry - addFunction" {
    var registry = try DynamicRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.addFunction(.{
        .pattern = "my_wrapper",
        .match_type = .exact,
        .kind = .command_exec,
        .severity = .high,
        .consumes_ownership = false,
        .transfers_ownership = false,
        .requires_null_check = false,
        .requires_taint_check = true,
        .description = "My custom wrapper",
    });

    try std.testing.expectEqual(@as(usize, 1), registry.customCount());

    const sem = registry.lookup("my_wrapper").?;
    try std.testing.expectEqual(RiskKind.command_exec, sem.kind);
}
