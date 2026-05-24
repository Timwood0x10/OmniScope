//! Semantic patterns for language-specific pattern recognition.
//!
//! This module provides a registry and matching system for semantic patterns
//! that can be used to identify language-specific constructs like Rust's Drop
//! trait, memory allocation patterns, and other semantic markers.

const std = @import("std");

/// Different types of semantic patterns we can recognize.
///
/// Mirrors SemanticKind: only allocation, release, provenance.
/// drop is folded into release, conversion/call are DFG concerns.
pub const PatternType = enum(u8) {
    /// Memory allocation pattern
    allocation,
    /// Memory release/deallocation pattern (free, drop, delete, etc.)
    release,
    /// Pointer provenance pattern (into_raw, from_raw, etc.)
    provenance,
    /// Unknown pattern type
    unknown,
};

/// A semantic pattern that can be matched against code
pub const SemanticPattern = struct {
    /// Name of the pattern
    name: []const u8,
    /// Description of what this pattern matches
    description: []const u8,
    /// Type of pattern
    pattern_type: PatternType,
    /// Function name patterns to match
    function_patterns: []const []const u8,
    /// Priority for matching (higher = earlier matching)
    priority: u16,
    /// Language this pattern is specific to
    language: []const u8,

    const Self = @This();

    /// Check if a function name matches this pattern
    pub fn matchesFunction(self: *const Self, func_name: []const u8) bool {
        for (self.function_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return true;
            }
        }
        return false;
    }
};

/// Pattern matcher interface
pub const PatternMatcher = struct {
    /// Match a function call against registered patterns.
    /// Returns the first matching pattern (highest priority first).
    pub fn matchFunctionCall(
        patterns: []const SemanticPattern,
        func_name: []const u8,
    ) ?*const SemanticPattern {
        var best_match: ?*const SemanticPattern = null;
        var best_priority: u16 = 0;

        for (patterns) |*pattern| {
            if (pattern.matchesFunction(func_name)) {
                if (pattern.priority > best_priority) {
                    best_match = pattern;
                    best_priority = pattern.priority;
                }
            }
        }
        return best_match;
    }
};

/// Pattern resolver interface
pub const PatternResolver = struct {
    /// Resolve a pattern match to a semantic action
    pub fn resolvePattern(
        pattern: *const SemanticPattern,
        context: anytype,
    ) SemanticAction {
        _ = context;
        return switch (pattern.pattern_type) {
            .allocation => SemanticAction.allocate,
            .release => SemanticAction.release,
            .provenance => SemanticAction.track,
            .unknown => SemanticAction.unknown,
        };
    }
};

/// Semantic actions that can be taken based on pattern matches
pub const SemanticAction = enum(u8) {
    /// Allocate memory
    allocate,
    /// Release memory
    release,
    /// Track pointer provenance
    track,
    /// Unknown action
    unknown,
};

/// Registry for managing semantic patterns
pub const PatternRegistry = struct {
    allocator: std.mem.Allocator,
    patterns: std.ArrayListUnmanaged(SemanticPattern),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .patterns = std.ArrayListUnmanaged(SemanticPattern){},
        };
    }

    pub fn deinit(self: *Self) void {
        self.patterns.deinit(self.allocator);
    }

    /// Register a new pattern
    pub fn registerPattern(
        self: *Self,
        name: []const u8,
        description: []const u8,
        pattern_type: PatternType,
        function_patterns: []const []const u8,
        priority: u16,
        language: []const u8,
    ) !usize {
        const pattern = SemanticPattern{
            .name = name,
            .description = description,
            .pattern_type = pattern_type,
            .function_patterns = function_patterns,
            .priority = priority,
            .language = language,
        };

        try self.patterns.append(self.allocator, pattern);
        return self.patterns.items.len - 1;
    }

    /// Get a pattern by ID
    pub fn getPattern(self: *const Self, id: usize) ?*const SemanticPattern {
        if (id < self.patterns.items.len) {
            return &self.patterns.items[id];
        }
        return null;
    }

    /// Get all patterns
    pub fn getPatterns(self: *const Self) []const SemanticPattern {
        return self.patterns.items;
    }

    /// Find patterns matching a function name
    pub fn findMatchingPatterns(
        self: *const Self,
        func_name: []const u8,
    ) []const SemanticPattern {
        var matches = std.ArrayListUnmanaged(SemanticPattern){};
        defer matches.deinit(self.allocator);

        for (self.patterns.items) |pattern| {
            if (pattern.matchesFunction(func_name)) {
                // For now, just return an empty slice
                break;
            }
        }

        return &.{};
    }
};

/// Utility functions for creating common patterns
pub const PatternUtils = struct {
    /// Create a drop pattern for Rust (folded into release)
    pub fn createRustDropPattern(_allocator: std.mem.Allocator) !SemanticPattern {
        _ = _allocator;
        return SemanticPattern{
            .name = "rust_drop",
            .description = "Rust Drop trait implementation",
            .pattern_type = .release,
            .function_patterns = &[_][]const u8{"drop"},
            .priority = 100,
            .language = "rust",
        };
    }

    /// Create a release pattern
    pub fn createReleasePattern(
        _allocator: std.mem.Allocator,
        name: []const u8,
        function_patterns: []const []const u8,
        language: []const u8,
    ) !SemanticPattern {
        _ = _allocator;
        return SemanticPattern{
            .name = name,
            .description = "Memory release pattern",
            .pattern_type = .release,
            .function_patterns = function_patterns,
            .priority = 90,
            .language = language,
        };
    }

    /// Create an allocation pattern
    pub fn createAllocationPattern(
        _allocator: std.mem.Allocator,
        name: []const u8,
        function_patterns: []const []const u8,
        language: []const u8,
    ) !SemanticPattern {
        _ = _allocator;
        return SemanticPattern{
            .name = name,
            .description = "Memory allocation pattern",
            .pattern_type = .allocation,
            .function_patterns = function_patterns,
            .priority = 90,
            .language = language,
        };
    }

    /// Create a provenance pattern
    pub fn createProvenancePattern(
        _allocator: std.mem.Allocator,
        name: []const u8,
        function_patterns: []const []const u8,
        language: []const u8,
    ) !SemanticPattern {
        _ = _allocator;
        return SemanticPattern{
            .name = name,
            .description = "Pointer provenance pattern",
            .pattern_type = .provenance,
            .function_patterns = function_patterns,
            .priority = 80,
            .language = language,
        };
    }
};

test "Pattern registration" {
    const allocator = std.testing.allocator;

    var registry = PatternRegistry.init(allocator);
    defer registry.deinit();

    const pattern_id = try registry.registerPattern(
        "test_pattern",
        "Test pattern",
        .allocation,
        &[_][]const u8{ "malloc", "calloc" },
        100,
        "c",
    );

    try std.testing.expect(pattern_id == 0);

    const pattern = registry.getPattern(pattern_id);
    try std.testing.expect(pattern != null);
    try std.testing.expect(std.mem.eql(u8, pattern.?.name, "test_pattern"));
    try std.testing.expect(pattern.?.pattern_type == .allocation);
}

test "Pattern matching" {
    const allocator = std.testing.allocator;

    var registry = PatternRegistry.init(allocator);
    defer registry.deinit();

    try registry.registerPattern(
        "malloc_pattern",
        "malloc pattern",
        .allocation,
        &[_][]const u8{"malloc"},
        100,
        "c",
    );

    try registry.registerPattern(
        "free_pattern",
        "free pattern",
        .release,
        &[_][]const u8{"free"},
        90,
        "c",
    );

    // Test pattern matching
    const malloc_pattern = PatternMatcher.matchFunctionCall(
        registry.getPatterns(),
        "malloc",
    );
    try std.testing.expect(malloc_pattern != null);
    try std.testing.expect(malloc_pattern.?.pattern_type == .allocation);

    const free_pattern = PatternMatcher.matchFunctionCall(
        registry.getPatterns(),
        "free",
    );
    try std.testing.expect(free_pattern != null);
    try std.testing.expect(free_pattern.?.pattern_type == .release);
}
