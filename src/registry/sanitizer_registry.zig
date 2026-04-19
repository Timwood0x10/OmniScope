//! Sanitizer Functions Registry
//!
//! This module identifies functions that can "sanitize" or "cleanse" tainted data,
//! reducing false positives in taint analysis.
//!
//! Categories of sanitizers:
//! - Input validators: functions that validate input and return safe values
//! - Escape functions: functions that escape dangerous characters
//! - Type converters: functions that safely convert types
//! - Bounds checkers: functions that enforce length constraints
//!
//! When tainted data passes through a sanitizer, the taint can be:
//! - Completely removed (full sanitizer)
//! - Reduced in confidence (partial sanitizer)
//! - Transformed to a different taint kind

const std = @import("std");

/// Sanitizer effectiveness level
pub const SanitizerEffectiveness = enum {
    /// Completely removes taint (e.g., proper input validation)
    full,
    /// Significantly reduces risk (e.g., HTML escaping for XSS)
    high,
    /// Partially reduces risk (e.g., length check without content validation)
    partial,
    /// Context-dependent (e.g., works for some attack types but not others)
    conditional,
};

/// Sanitizer category
pub const SanitizerCategory = enum {
    /// Input validation (e.g., isdigit, isalpha)
    input_validation,
    /// Character escaping (e.g., htmlspecialchars, sqlite3_escape)
    escaping,
    /// Bounds checking (e.g., strncpy with proper size)
    bounds_check,
    /// Type conversion with validation (e.g., strtol with error check)
    type_conversion,
    /// Memory safety (e.g., memcpy_s, strcpy_s)
    memory_safe,
    /// Null terminator enforcement
    null_terminate,
};

/// Sanitizer function information
pub const SanitizerInfo = struct {
    name: []const u8,
    category: SanitizerCategory,
    effectiveness: SanitizerEffectiveness,
    /// Confidence multiplier after sanitization (0.0 = full removal, 1.0 = no effect)
    confidence_factor: f32,
    /// CWEs this sanitizer helps prevent
    mitigated_cwes: []const u32,
    /// Whether sanitizer requires correct usage (e.g., proper buffer size)
    requires_correct_usage: bool,
};

/// Known sanitizer functions
const SANITIZER_FUNCTIONS = [_]SanitizerInfo{
    // Input validation
    .{
        .name = "isdigit",
        .category = .input_validation,
        .effectiveness = .conditional,
        .confidence_factor = 0.3,
        .mitigated_cwes = &.{ 78, 88 },
        .requires_correct_usage = false,
    },
    .{
        .name = "isalpha",
        .category = .input_validation,
        .effectiveness = .conditional,
        .confidence_factor = 0.3,
        .mitigated_cwes = &.{ 78, 88 },
        .requires_correct_usage = false,
    },
    .{
        .name = "isalnum",
        .category = .input_validation,
        .effectiveness = .conditional,
        .confidence_factor = 0.3,
        .mitigated_cwes = &.{ 78, 88 },
        .requires_correct_usage = false,
    },
    .{
        .name = "isprint",
        .category = .input_validation,
        .effectiveness = .conditional,
        .confidence_factor = 0.4,
        .mitigated_cwes = &.{ 78, 88 },
        .requires_correct_usage = false,
    },

    // Bounds checking
    .{
        .name = "strncpy",
        .category = .bounds_check,
        .effectiveness = .conditional,
        .confidence_factor = 0.6,
        .mitigated_cwes = &.{ 120, 119 },
        .requires_correct_usage = true,
    },
    .{
        .name = "strncat",
        .category = .bounds_check,
        .effectiveness = .conditional,
        .confidence_factor = 0.6,
        .mitigated_cwes = &.{ 120, 119 },
        .requires_correct_usage = true,
    },
    .{
        .name = "snprintf",
        .category = .bounds_check,
        .effectiveness = .high,
        .confidence_factor = 0.2,
        .mitigated_cwes = &.{ 120, 119, 678 },
        .requires_correct_usage = true,
    },
    .{
        .name = "vsnprintf",
        .category = .bounds_check,
        .effectiveness = .high,
        .confidence_factor = 0.2,
        .mitigated_cwes = &.{ 120, 119, 678 },
        .requires_correct_usage = true,
    },

    // Memory safe variants (C11 Annex K)
    .{
        .name = "memcpy_s",
        .category = .memory_safe,
        .effectiveness = .high,
        .confidence_factor = 0.15,
        .mitigated_cwes = &.{ 120, 119 },
        .requires_correct_usage = false,
    },
    .{
        .name = "strcpy_s",
        .category = .memory_safe,
        .effectiveness = .high,
        .confidence_factor = 0.15,
        .mitigated_cwes = &.{ 120, 119 },
        .requires_correct_usage = false,
    },
    .{
        .name = "strcat_s",
        .category = .memory_safe,
        .effectiveness = .high,
        .confidence_factor = 0.15,
        .mitigated_cwes = &.{ 120, 119 },
        .requires_correct_usage = false,
    },
    .{
        .name = "strerror_s",
        .category = .memory_safe,
        .effectiveness = .high,
        .confidence_factor = 0.15,
        .mitigated_cwes = &.{ 120, 119 },
        .requires_correct_usage = false,
    },

    // Type conversion with validation
    .{
        .name = "strtol",
        .category = .type_conversion,
        .effectiveness = .conditional,
        .confidence_factor = 0.35,
        .mitigated_cwes = &.{78},
        .requires_correct_usage = true,
    },
    .{
        .name = "strtoul",
        .category = .type_conversion,
        .effectiveness = .conditional,
        .confidence_factor = 0.35,
        .mitigated_cwes = &.{78},
        .requires_correct_usage = true,
    },
    .{
        .name = "strtod",
        .category = .type_conversion,
        .effectiveness = .conditional,
        .confidence_factor = 0.35,
        .mitigated_cwes = &.{78},
        .requires_correct_usage = true,
    },
    .{
        .name = "strtof",
        .category = .type_conversion,
        .effectiveness = .conditional,
        .confidence_factor = 0.35,
        .mitigated_cwes = &.{78},
        .requires_correct_usage = true,
    },

    // Null terminator enforcement
    .{
        .name = "strnlen",
        .category = .null_terminate,
        .effectiveness = .partial,
        .confidence_factor = 0.5,
        .mitigated_cwes = &.{ 120, 119 },
        .requires_correct_usage = true,
    },
};

/// Error type for sanitizer registry operations.
pub const SanitizerRegistryError = error{
    OutOfMemory,
};

/// Sanitizer registry for taint analysis
pub const SanitizerRegistry = struct {
    /// Lookup table for sanitizer functions
    sanitizers: std.StringHashMap(SanitizerInfo),
    /// Whether the registry has been initialized
    initialized: bool,

    /// Initialize the registry with the given allocator.
    ///
    /// Arguments:
    ///   - allocator: Memory allocator for the registry
    ///
    /// Errors:
    ///   - OutOfMemory: Failed to allocate memory for the registry
    ///
    /// Example:
    ///   ```zig
    ///   var registry = try SanitizerRegistry.init(allocator);
    ///   defer registry.deinit();
    ///   ```
    pub fn init(allocator: std.mem.Allocator) SanitizerRegistryError!SanitizerRegistry {
        var registry = SanitizerRegistry{
            .sanitizers = std.StringHashMap(SanitizerInfo).init(allocator),
            .initialized = false,
        };

        for (SANITIZER_FUNCTIONS) |info| {
            registry.sanitizers.put(info.name, info) catch |err| {
                std.log.err("SanitizerRegistry: Failed to register sanitizer '{s}': {}", .{ info.name, err });
                return err;
            };
        }

        registry.initialized = true;
        return registry;
    }

    /// Free resources
    pub fn deinit(self: *SanitizerRegistry) void {
        if (self.initialized) {
            self.sanitizers.deinit();
            self.initialized = false;
        }
    }

    /// Check if the registry is properly initialized
    pub fn isInitialized(self: *const SanitizerRegistry) bool {
        return self.initialized;
    }

    /// Look up a sanitizer by function name
    pub fn lookup(self: *const SanitizerRegistry, func_name: []const u8) ?SanitizerInfo {
        return self.sanitizers.get(func_name);
    }

    /// Check if a function is a sanitizer
    pub fn isSanitizer(self: *const SanitizerRegistry, func_name: []const u8) bool {
        return self.sanitizers.contains(func_name);
    }

    /// Get the confidence factor for a sanitizer
    /// Returns 1.0 if not a sanitizer (no effect)
    pub fn getConfidenceFactor(self: *const SanitizerRegistry, func_name: []const u8) f32 {
        if (self.lookup(func_name)) |info| {
            return info.confidence_factor;
        }
        return 1.0;
    }

    /// Check if sanitizer mitigates a specific CWE
    pub fn mitigatesCWE(self: *const SanitizerRegistry, func_name: []const u8, cwe: u32) bool {
        if (self.lookup(func_name)) |info| {
            for (info.mitigated_cwes) |mitigated| {
                if (mitigated == cwe) return true;
            }
        }
        return false;
    }

    /// Get all sanitizers that mitigate a specific CWE
    pub fn getSanitizersForCWE(self: *const SanitizerRegistry, allocator: std.mem.Allocator, cwe: u32) ![][]const u8 {
        var result = try std.ArrayList([]const u8).initCapacity(allocator, 0);

        var iter = self.sanitizers.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.mitigated_cwes) |mitigated| {
                if (mitigated == cwe) {
                    try result.append(allocator, entry.key_ptr.*);
                    break;
                }
            }
        }

        return result.toOwnedSlice(allocator);
    }

    /// Check if a sanitizer fully removes taint
    pub fn isFullSanitizer(self: *const SanitizerRegistry, func_name: []const u8) bool {
        if (self.lookup(func_name)) |info| {
            return info.effectiveness == .full;
        }
        return false;
    }

    /// Get sanitizer effectiveness description
    pub fn getEffectivenessDesc(self: *const SanitizerRegistry, func_name: []const u8) []const u8 {
        if (self.lookup(func_name)) |info| {
            return switch (info.effectiveness) {
                .full => "fully removes taint",
                .high => "significantly reduces risk",
                .partial => "partially reduces risk",
                .conditional => "context-dependent effectiveness",
            };
        }
        return "not a sanitizer";
    }
};

// Unit tests
test "SanitizerRegistry - init and deinit" {
    var registry = try SanitizerRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expect(registry.sanitizers.count() > 0);
}

test "SanitizerRegistry - lookup" {
    var registry = try SanitizerRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const info = registry.lookup("strncpy");
    try std.testing.expect(info != null);
    try std.testing.expectEqual(SanitizerCategory.bounds_check, info.?.category);
    try std.testing.expectEqual(SanitizerEffectiveness.partial, info.?.effectiveness);
}

test "SanitizerRegistry - isSanitizer" {
    var registry = try SanitizerRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expect(registry.isSanitizer("strncpy"));
    try std.testing.expect(registry.isSanitizer("snprintf"));
    try std.testing.expect(!registry.isSanitizer("strcpy"));
    try std.testing.expect(!registry.isSanitizer("unknown_func"));
}

test "SanitizerRegistry - getConfidenceFactor" {
    var registry = try SanitizerRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expectEqual(@as(f32, 0.4), registry.getConfidenceFactor("strncpy"));
    try std.testing.expectEqual(@as(f32, 1.0), registry.getConfidenceFactor("unknown_func"));
}

test "SanitizerRegistry - mitigatesCWE" {
    var registry = try SanitizerRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expect(registry.mitigatesCWE("strncpy", 120));
    try std.testing.expect(registry.mitigatesCWE("snprintf", 119));
    try std.testing.expect(!registry.mitigatesCWE("strncpy", 134));
}

test "SanitizerRegistry - getSanitizersForCWE" {
    var registry = try SanitizerRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const sanitizers = try registry.getSanitizersForCWE(std.testing.allocator, 120);
    defer std.testing.allocator.free(sanitizers);

    try std.testing.expect(sanitizers.len > 0);
}
