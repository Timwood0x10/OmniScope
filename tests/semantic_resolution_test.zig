const std = @import("std");
const omniscope = @import("OmniScope");

test "Semantic resolution tree basic functionality" {
    // Test that we can create semantic tree components
    const allocator = std.testing.allocator;

    // Create a semantic tree
    var tree = omniscope.semantics.SemanticTree.init(allocator);
    defer tree.deinit();

    // Create a pattern registry
    var registry = omniscope.semantics.PatternRegistry.init(allocator);
    defer registry.deinit();

    // Test adding a node to the tree
    const node_id = try tree.addNode(.unknown, "test_function", 0x1000, 0x2000);
    try std.testing.expect(node_id == 0);

    // Test adding a resolution
    try tree.addResolution(node_id, .{
        .kind = .release,
        .confidence = 0.95,
        .evidence = "test_data",
        .nomicon_chapter = null,
        .pattern_id = null,
    });

    // Test getting resolutions
    const resolutions = tree.getResolutions(node_id);
    try std.testing.expect(resolutions.len == 1);
    try std.testing.expect(resolutions[0].kind == .release);
    try std.testing.expect(resolutions[0].confidence == 0.95);

    // Test pattern registry
    const pattern_id = try registry.registerPattern("test_pattern", "Test pattern", .allocation, &[_][]const u8{"test"}, 100, "c");
    try std.testing.expect(pattern_id == 0);

    const pattern = registry.getPattern(pattern_id);
    try std.testing.expect(pattern != null);
    try std.testing.expect(std.mem.eql(u8, pattern.?.name, "test_pattern"));
}

test "Resolution engine functionality" {
    const allocator = std.testing.allocator;

    // Create a resolution engine
    var engine = try omniscope.semantics.ResolutionEngine.init(allocator);
    defer engine.deinit();

    // Test processing a function call
    try engine.processFunctionCall("malloc", "test_function", 0x1000, "test.c", 0x2000);

    // Test processing an allocation
    try engine.processAllocation(0x3000, 0x4000, .heap_alloc, .safe, .c);

    // Test getting stats
    const stats = engine.getStats();
    try std.testing.expect(stats.total_nodes == 2); // processFunctionCall + processAllocation
    try std.testing.expect(stats.resolutions_made == 0); // No patterns registered yet
}

test "Memory graph integration" {
    const allocator = std.testing.allocator;

    // Create a memory graph
    var graph = try omniscope.semantics.MemoryGraph.init(allocator);
    defer graph.deinit();

    // Test adding an allocation
    _ = try graph.trackAlloc(
        0x1000,
        0x2000,
        .heap_alloc,
        .safe,
        .c,
        null,
    );

    // Test adding a free
    _ = try graph.trackFree(0x3000, 0x1000, .c, 0);
}

test "Pattern registry functionality" {
    const allocator = std.testing.allocator;

    // Create a pattern registry
    var registry = omniscope.semantics.PatternRegistry.init(allocator);
    defer registry.deinit();

    // Test registering multiple patterns
    const pattern1 = try registry.registerPattern("rust_drop", "Rust Drop trait pattern", .release, &[_][]const u8{"drop"}, 100, "rust");
    const pattern2 = try registry.registerPattern("dealloc", "Memory deallocation pattern", .release, &[_][]const u8{"free"}, 90, "c");

    try std.testing.expect(pattern1 == 0);
    try std.testing.expect(pattern2 == 1);

    // Test getting patterns
    const rust_pattern = registry.getPattern(pattern1);
    try std.testing.expect(rust_pattern != null);
    try std.testing.expect(std.mem.eql(u8, rust_pattern.?.name, "rust_drop"));

    const dealloc_pattern = registry.getPattern(pattern2);
    try std.testing.expect(dealloc_pattern != null);
    try std.testing.expect(std.mem.eql(u8, dealloc_pattern.?.name, "dealloc"));
}
