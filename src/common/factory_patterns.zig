//! Factory/Destructor/Transfer Function Detection — Consolidated SSOT
//!
//! Consolidates duplicate detection functions found across the codebase.
//! Provides parameterized versions that accept match strategy.
//!
//! Sources (origin files):
//!   - isFactoryFunction():     types/cpp_fp_helpers.zig (suffix match)
//!                              types/callback_escape_types.zig (substring match)
//!   - isDestructorFunction():  types/callback_escape_types.zig
//!   - isTransferFunction():    types/callback_escape_types.zig

const std = @import("std");

// ============================================================================
// Match Strategy
// ============================================================================

/// Strategy for matching function names against patterns.
pub const MatchStrategy = enum {
    /// Exact equality match.
    exact,
    /// Substring match (contains).
    substring,
    /// Suffix/ends-with match.
    suffix,
    /// Prefix/starts-with match.
    prefix,
};

// ============================================================================
// Pattern Tables
// ============================================================================

/// Factory/constructor function name suffixes (source: cpp_fp_helpers.zig).
pub const FACTORY_SUFFIXES = &[_][]const u8{
    "Create", "create", "New",   "new",   "Alloc", "alloc",
    "Make",   "make",   "Open",  "open",  "Init",  "init",
    "From",   "from",   "State", "state", "Dup",   "dup",
    "Clone",  "clone",
};

/// Factory/constructor function name prefixes (source: cpp_fp_helpers.zig).
pub const FACTORY_PREFIXES = &[_][]const u8{
    "create", "new", "alloc", "make",
};

/// Factory/constructor function name patterns (substring, source: callback_escape_types.zig).
pub const FACTORY_PATTERNS_SUBSTRING = &[_][]const u8{
    "Alloc",  "Create", "New",     "Init", "Open", "Dup",
    "Malloc", "Calloc", "Realloc",
};

/// Destructor/cleanup function name patterns (source: callback_escape_types.zig).
pub const DESTRUCTOR_PATTERNS = &[_][]const u8{
    "Free",   "Destroy",  "Delete",  "Close", "Release", "Cleanup",
    "Finish", "Finalize", "Dispose",
};

/// Transfer function name patterns (source: callback_escape_types.zig).
pub const TRANSFER_PATTERNS = &[_][]const u8{
    "Clone", "Copy", "Move", "Transfer", "Take",
};

// ============================================================================
// Detection Functions
// ============================================================================

/// Check if a function is a factory/constructor that transfers ownership to caller.
/// Uses suffix match strategy (cpp_fp_helpers.zig style) + prefix fallback.
///
/// Parameters:
///   - func_name: The function name to check.
///   - strategy: Match strategy to use (suffix, substring, or prefix).
pub fn isFactoryFunction(func_name: []const u8) bool {
    // Suffix match (cpp_fp_helpers.zig style)
    for (FACTORY_SUFFIXES) |suffix| {
        if (std.mem.endsWith(u8, func_name, suffix)) return true;
    }
    // Prefix match with minimum length check
    for (FACTORY_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix) and func_name.len > prefix.len + 2) {
            return true;
        }
    }
    return false;
}

/// Check if a function is a factory using substring match (callback_escape_types.zig style).
pub fn isFactoryFunctionSubstring(func_name: []const u8) bool {
    for (FACTORY_PATTERNS_SUBSTRING) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if a function is a factory using the specified match strategy.
pub fn isFactoryFunctionWithStrategy(func_name: []const u8, strategy: MatchStrategy) bool {
    return matchAny(func_name, strategy, FACTORY_SUFFIXES);
}

/// Checks if a function is a destructor that consumes ownership from caller.
pub fn isDestructorFunction(func_name: []const u8) bool {
    for (DESTRUCTOR_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Checks if a function is a destructor using the specified match strategy.
pub fn isDestructorFunctionWithStrategy(func_name: []const u8, strategy: MatchStrategy) bool {
    return matchAny(func_name, strategy, DESTRUCTOR_PATTERNS);
}

/// Checks if a function is a transfer function that passes ownership through.
pub fn isTransferFunction(func_name: []const u8) bool {
    for (TRANSFER_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Checks if a function is a transfer function using the specified match strategy.
pub fn isTransferFunctionWithStrategy(func_name: []const u8, strategy: MatchStrategy) bool {
    return matchAny(func_name, strategy, TRANSFER_PATTERNS);
}

// ============================================================================
// Internal Helpers
// ============================================================================

/// Match a function name against a list of patterns using the given strategy.
fn matchAny(func_name: []const u8, strategy: MatchStrategy, patterns: []const []const u8) bool {
    return switch (strategy) {
        .exact => blk: {
            for (patterns) |p| {
                if (std.mem.eql(u8, func_name, p)) return true;
            }
            break :blk false;
        },
        .substring => blk: {
            for (patterns) |p| {
                if (std.mem.indexOf(u8, func_name, p) != null) return true;
            }
            break :blk false;
        },
        .suffix => blk: {
            for (patterns) |p| {
                if (std.mem.endsWith(u8, func_name, p)) return true;
            }
            break :blk false;
        },
        .prefix => blk: {
            for (patterns) |p| {
                if (std.mem.startsWith(u8, func_name, p)) return true;
            }
            break :blk false;
        },
    };
}

// ============================================================================
// Tests
// ============================================================================

test "factory_patterns - isFactoryFunction (suffix)" {
    try std.testing.expect(isFactoryFunction("XXH32_createState"));
    try std.testing.expect(isFactoryFunction("NewStringUTF"));
    try std.testing.expect(isFactoryFunction("malloc_wrapper"));
    try std.testing.expect(!isFactoryFunction("free"));
    try std.testing.expect(!isFactoryFunction("printf"));
}

test "factory_patterns - isFactoryFunctionSubstring" {
    try std.testing.expect(isFactoryFunctionSubstring("CreateWindow"));
    try std.testing.expect(isFactoryFunctionSubstring("AllocX"));
    try std.testing.expect(!isFactoryFunctionSubstring("free"));
}

test "factory_patterns - isDestructorFunction" {
    try std.testing.expect(isDestructorFunction("DestroyWindow"));
    try std.testing.expect(isDestructorFunction("FreeMemory"));
    try std.testing.expect(!isDestructorFunction("malloc"));
}

test "factory_patterns - isTransferFunction" {
    try std.testing.expect(isTransferFunction("TransferOwnership"));
    try std.testing.expect(isTransferFunction("CloneObject"));
    try std.testing.expect(!isTransferFunction("free"));
}
