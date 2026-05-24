//! Resolution engine for semantic analysis.
//!
//! This module provides the core resolution engine that coordinates
//! the semantic tree, pattern registry, and memory graph to
//! perform semantic analysis across different languages.

const std = @import("std");
const semantic_tree = @import("semantic_tree.zig");
const semantic_patterns = @import("semantic_patterns.zig");
const memory_graph_mod = @import("memory_graph.zig");

const SemanticTree = semantic_tree.SemanticTree;
const SemanticKind = semantic_tree.SemanticKind;
const Resolution = semantic_tree.Resolution;
const PatternRegistry = semantic_patterns.PatternRegistry;
const SemanticPattern = semantic_patterns.SemanticPattern;
const PatternMatcher = semantic_patterns.PatternMatcher;
const PatternResolver = semantic_patterns.PatternResolver;
const MemoryGraph = memory_graph_mod.MemoryGraph;
const SourceKind = memory_graph_mod.SourceKind;
const Language = memory_graph_mod.Language;
const ZoneKind = memory_graph_mod.ZoneKind;

/// Engine statistics
pub const EngineStats = struct {
    /// Total number of nodes processed
    total_nodes: usize,
    /// Number of resolutions made
    resolutions_made: usize,
    /// Number of patterns applied
    patterns_applied: usize,
    /// Number of memory allocations tracked
    allocations_tracked: usize,
    /// Number of memory frees tracked
    frees_tracked: usize,
};

/// Resolution engine - coordinates semantic analysis
pub const ResolutionEngine = struct {
    allocator: std.mem.Allocator,
    semantic_tree: SemanticTree,
    pattern_registry: PatternRegistry,
    memory_graph: *MemoryGraph,
    owns_memory_graph: bool,
    stats: EngineStats,
    /// Maps caller function name → SemanticKind for that function.
    /// When a function contains a call to a semantically-resolved callee
    /// (e.g., drop_in_place → release), the caller itself gets tagged.
    /// This enables downstream passes to skip entire functions that are
    /// semantically known destructors (e.g., Rust Drop glue functions).
    caller_semantics: std.StringHashMap(SemanticKind),

    const Self = @This();

    /// Initialize a new resolution engine with its own memory graph
    pub fn init(allocator: std.mem.Allocator) !Self {
        const mg = try allocator.create(MemoryGraph);
        errdefer allocator.destroy(mg);
        mg.* = try MemoryGraph.init(allocator);
        return Self{
            .allocator = allocator,
            .semantic_tree = SemanticTree.init(allocator),
            .pattern_registry = PatternRegistry.init(allocator),
            .memory_graph = mg,
            .owns_memory_graph = true,
            .stats = EngineStats{
                .total_nodes = 0,
                .resolutions_made = 0,
                .patterns_applied = 0,
                .allocations_tracked = 0,
                .frees_tracked = 0,
            },
            .caller_semantics = std.StringHashMap(SemanticKind).init(allocator),
        };
    }

    /// Initialize a resolution engine wrapping an existing memory graph
    pub fn initWithExistingGraph(allocator: std.mem.Allocator, mg: *MemoryGraph) Self {
        return Self{
            .allocator = allocator,
            .semantic_tree = SemanticTree.init(allocator),
            .pattern_registry = PatternRegistry.init(allocator),
            .memory_graph = mg,
            .owns_memory_graph = false,
            .stats = EngineStats{
                .total_nodes = 0,
                .resolutions_made = 0,
                .patterns_applied = 0,
                .allocations_tracked = 0,
                .frees_tracked = 0,
            },
            .caller_semantics = std.StringHashMap(SemanticKind).init(allocator),
        };
    }

    /// Deinitialize the resolution engine
    pub fn deinit(self: *Self) void {
        self.semantic_tree.deinit();
        self.pattern_registry.deinit();
        // Free caller_semantics keys (they were dupe'd from allocator)
        var cs_iter = self.caller_semantics.keyIterator();
        while (cs_iter.next()) |key_ptr| {
            self.allocator.free(key_ptr.*);
        }
        self.caller_semantics.deinit();
        if (self.owns_memory_graph) {
            self.memory_graph.deinit();
            self.allocator.destroy(self.memory_graph);
        }
    }

    /// Register a pattern in the engine
    pub fn registerPattern(
        self: *Self,
        name: []const u8,
        description: []const u8,
        pattern_type: semantic_patterns.PatternType,
        function_patterns: []const []const u8,
        priority: u16,
        language: []const u8,
    ) !usize {
        return try self.pattern_registry.registerPattern(
            name,
            description,
            pattern_type,
            function_patterns,
            priority,
            language,
        );
    }

    /// Process a function call.
    /// Only adds a semantic tree node if the call matches an allocation,
    /// release, or provenance pattern. Unmatched calls are ignored —
    /// SRT only needs to answer "can this value be explained away?"
    ///
    /// `caller_name`: the function containing the call instruction.
    /// `callee_name`: the function being called (e.g., "drop_in_place").
    /// When a pattern matches, the caller is tagged with the semantic kind
    /// so downstream passes can skip the entire caller function.
    pub fn processFunctionCall(
        self: *Self,
        callee_name: []const u8,
        caller_name: []const u8,
        caller_inst: u64,
        _source_file: []const u8,
        line: u32,
    ) !void {
        _ = _source_file;

        // Match against patterns — only record if it's allocation/release/provenance
        const patterns = self.pattern_registry.getPatterns();
        if (PatternMatcher.matchFunctionCall(patterns, callee_name)) |matched_pattern| {
            const kind = convertPatternTypeToSemanticKind(matched_pattern.pattern_type);
            const node_id = try self.semantic_tree.addNode(
                kind,
                callee_name,
                caller_inst,
                line,
            );
            try self.applyPattern(node_id, matched_pattern);
            self.stats.patterns_applied += 1;
            self.stats.resolutions_made += 1;

            // Tag the caller function with this semantic kind.
            // If already tagged, keep the higher-priority kind:
            //   release > allocation > provenance > unknown
            // (release means the function is a destructor — strongest skip signal)
            const gop = try self.caller_semantics.getOrPut(caller_name);
            if (!gop.found_existing) {
                gop.key_ptr.* = try self.allocator.dupe(u8, caller_name);
                gop.value_ptr.* = kind;
            } else {
                // Update if new kind has higher priority (release is highest)
                const existing = gop.value_ptr.*;
                if (kind == .release or (kind == .allocation and existing != .release)) {
                    gop.value_ptr.* = kind;
                }
            }
        }

        self.stats.total_nodes += 1;
    }

    /// Process a memory allocation using the original MemoryGraph API
    pub fn processAllocation(
        self: *Self,
        alloc_inst: u64,
        ret_value: u64,
        kind: SourceKind,
        zone: ZoneKind,
        lang: Language,
    ) !void {
        _ = try self.memory_graph.trackAlloc(
            alloc_inst,
            ret_value,
            kind,
            zone,
            lang,
        );

        // Add to semantic tree
        _ = try self.semantic_tree.addNode(
            .allocation,
            "alloc",
            alloc_inst,
            0, // line
        );

        self.stats.allocations_tracked += 1;
        self.stats.total_nodes += 1;
    }

    /// Process a memory free using the original MemoryGraph API
    pub fn processFree(
        self: *Self,
        free_inst: u64,
        ptr_val: u64,
        lang: Language,
        bb_id: u32,
    ) !void {
        _ = try self.memory_graph.trackFree(
            free_inst,
            ptr_val,
            lang,
            bb_id,
        );

        // Add to semantic tree
        _ = try self.semantic_tree.addNode(
            .release,
            "free",
            free_inst,
            0, // line
        );

        self.stats.frees_tracked += 1;
        self.stats.total_nodes += 1;
    }

    /// Apply a pattern to a node
    fn applyPattern(
        self: *Self,
        node_id: usize,
        pattern: *const SemanticPattern,
    ) !void {
        const resolution = Resolution{
            .kind = convertPatternTypeToSemanticKind(pattern.pattern_type),
            .confidence = 0.9,
            .data = pattern.description,
            .pattern_id = null,
        };

        try self.semantic_tree.addResolution(node_id, resolution);
        self.stats.resolutions_made += 1;
    }

    /// Get engine statistics
    pub fn getStats(self: *const Self) EngineStats {
        return self.stats;
    }

    /// Check if analysis should be skipped for a pointer
    pub fn shouldSkipAnalysis(self: *const Self, ptr_value: u64) bool {
        return self.memory_graph.shouldSkipAnalysis(ptr_value);
    }

    /// Get the semantic tree
    pub fn getSemanticTree(self: *const Self) *const SemanticTree {
        return &self.semantic_tree;
    }

    /// Get the pattern registry
    pub fn getPatternRegistry(self: *const Self) *const PatternRegistry {
        return &self.pattern_registry;
    }

    /// Get the memory graph
    pub fn getMemoryGraph(self: *const Self) *const MemoryGraph {
        return self.memory_graph;
    }

    /// Check if a function name has been semantically resolved as a specific kind.
    /// Returns the SemanticKind if the function was tagged as a caller of a
    /// semantically-resolved callee, null otherwise.
    ///
    /// This is the primary query interface for downstream passes:
    ///   - If isSemanticallyResolved("_ZN...drop...", .release) → skip double_free/UAF reports
    ///   - If isSemanticallyResolved("_ZN...alloc...", .allocation) → known allocation, not a leak
    ///   - If isSemanticallyResolved("_ZN...from_raw...", .provenance) → ownership transfer, not a bug
    pub fn isSemanticallyResolved(self: *const Self, func_name: []const u8, kind: SemanticKind) ?SemanticKind {
        // Query caller_semantics: was this function tagged because it calls
        // a semantically-resolved callee?
        if (self.caller_semantics.get(func_name)) |resolved_kind| {
            if (resolved_kind == kind) return resolved_kind;
        }

        // Fallback: check pattern registry for direct callee match.
        // This handles the case where the function IS the semantically-resolved
        // function (e.g., the function name contains "drop_in_place").
        const patterns = self.pattern_registry.getPatterns();
        if (PatternMatcher.matchFunctionCall(patterns, func_name)) |matched_pattern| {
            const resolved_kind = convertPatternTypeToSemanticKind(matched_pattern.pattern_type);
            if (resolved_kind == kind) return resolved_kind;
        }

        return null;
    }

    /// Check if a function name is resolved as a release operation (drop, free, delete, etc.)
    /// Convenience wrapper — the most common query for filtering false positives.
    pub fn isSemanticallyRelease(self: *const Self, func_name: []const u8) bool {
        return self.isSemanticallyResolved(func_name, .release) != null;
    }

    /// Check if a function name is resolved as an allocation operation
    pub fn isSemanticallyAllocation(self: *const Self, func_name: []const u8) bool {
        return self.isSemanticallyResolved(func_name, .allocation) != null;
    }
};

/// Helper to convert PatternType to SemanticKind
fn convertPatternTypeToSemanticKind(pattern_type: semantic_patterns.PatternType) SemanticKind {
    return switch (pattern_type) {
        .allocation => .allocation,
        .release => .release,
        .provenance => .provenance,
        .unknown => .unknown,
    };
}

test "Resolution engine basic functionality" {
    const allocator = std.testing.allocator;

    var engine = try ResolutionEngine.init(allocator);
    defer engine.deinit();

    // Register a pattern
    _ = try engine.registerPattern(
        "test_pattern",
        "Test pattern",
        semantic_patterns.PatternType.allocation,
        &[_][]const u8{"malloc"},
        100,
        "c",
    );

    // Process a function call
    try engine.processFunctionCall("malloc", "test_caller", 0x1000, "test.c", 10);

    // Process an allocation
    try engine.processAllocation(
        0x1000,
        0x2000,
        .heap_alloc,
        .unknown,
        .c,
    );

    // Process a free
    _ = try engine.processFree(
        0x1001,
        0x2000,
        .c,
        0,
    );

    // Check stats
    const stats = engine.getStats();
    try std.testing.expect(stats.total_nodes >= 3);
    try std.testing.expect(stats.allocations_tracked >= 1);
    try std.testing.expect(stats.frees_tracked >= 1);
}

test "Pattern matching and resolution" {
    const allocator = std.testing.allocator;

    var engine = try ResolutionEngine.init(allocator);
    defer engine.deinit();

    // Register patterns
    _ = try engine.registerPattern(
        "malloc_pattern",
        "malloc allocation pattern",
        semantic_patterns.PatternType.allocation,
        &[_][]const u8{"malloc"},
        100,
        "c",
    );

    _ = try engine.registerPattern(
        "free_pattern",
        "free release pattern",
        semantic_patterns.PatternType.release,
        &[_][]const u8{"free"},
        90,
        "c",
    );

    // Process function calls
    try engine.processFunctionCall("malloc", "test_caller", 0x1000, "test.c", 10);
    try engine.processFunctionCall("free", "test_caller", 0x1001, "test.c", 11);

    // Check that patterns were applied
    const stats = engine.getStats();
    try std.testing.expect(stats.patterns_applied >= 2);

    // Check semantic tree
    const tree = engine.getSemanticTree();
    const nodes = tree.getNodes();
    try std.testing.expect(nodes.len >= 2);
}
