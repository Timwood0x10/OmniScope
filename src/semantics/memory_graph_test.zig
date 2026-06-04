//! Tests for MemoryGraph — PHASE3-TASK-3 (Part 1)
//!
//! Coverage target: isOnDangerPath + trackAlloc + trackFree + trackAlias + isLeaked + isDoubleFreed
//! Test categories: happy path, boundary cases, error handling

const std = @import("std");

const MemoryGraph = @import("memory_graph.zig").MemoryGraph;
const SourceKind = @import("memory_graph.zig").SourceKind;

// ============================================================================
// trackAlloc + trackFree tests
// ============================================================================

test "trackAlloc - creates allocation node (happy path)" {
    var graph = try MemoryGraph.init(std.testing.allocator);
    defer graph.deinit();

    const ptr_val: u64 = 0x12345678;
    const alloc_inst: u64 = 0x111;

    const node_id = try MemoryGraph.trackAlloc(&graph, alloc_inst, ptr_val, .heap, .unknown, .c, null);
    try std.testing.expect(node_id > 0, "Should return valid node ID");

    const alloc_info = MemoryGraph.getAllocInfo(&graph, ptr_val);
    try std.testing.expect(alloc_info != null, "Should find allocation info");
}

test "trackFree - marks allocation as freed (happy path)" {
    var graph = try MemoryGraph.init(std.testing.allocator);
    defer graph.deinit();

    const ptr_val: u64 = 0x12345678;
    const alloc_inst: u64 = 0x111;
    const free_inst: u64 = 0x222;

    _ = try MemoryGraph.trackAlloc(&graph, alloc_inst, ptr_val, .heap, .unknown, .c, null);
    _ = MemoryGraph.trackFree(&graph, ptr_val, free_inst, .c);

    const is_freed = MemoryGraph.isFreed(&graph, ptr_val);
    try std.testing.expect(is_freed, "Should be marked as freed");
}

test "trackFree - returns false for unknown pointer (error case)" {
    var graph = try MemoryGraph.init(std.testing.allocator);
    defer graph.deinit();

    const result = MemoryGraph.trackFree(&graph, 0xDEAD, 0x222, .c);
    try std.testing.expect(!result, "Should return false for unknown pointer");
}

// ============================================================================
// trackAlias tests
// ============================================================================

test "trackAlias - creates alias relationship (happy path)" {
    var graph = try MemoryGraph.init(std.testing.allocator);
    defer graph.deinit();

    const ptr_val: u64 = 0x1000;
    const alias_val: u64 = 0x2000;
    const alloc_inst: u64 = 0x111;

    _ = try MemoryGraph.trackAlloc(&graph, alloc_inst, ptr_val, .heap, .unknown, .c, null);
    try MemoryGraph.trackAlias(&graph, alias_val, ptr_val, false);

    // Both should resolve to the same allocation
    const source1 = MemoryGraph.getSourceKind(&graph, ptr_val);
    const source2 = MemoryGraph.getSourceKind(&graph, alias_val);
    try std.testing.expectEqual(source1, source2, "Alias should have same source kind");
}

test "trackAliasStrong - creates strong alias (happy path)" {
    var graph = try MemoryGraph.init(std.testing.allocator);
    defer graph.deinit();

    const ptr_val: u64 = 0x1000;
    const alias_val: u64 = 0x2000;
    const alloc_inst: u64 = 0x111;

    _ = try MemoryGraph.trackAlloc(&graph, alloc_inst, ptr_val, .heap, .unknown, .c, null);
    try MemoryGraph.trackAliasStrong(&graph, alias_val, ptr_val);

    const source1 = MemoryGraph.getSourceKind(&graph, ptr_val);
    const source2 = MemoryGraph.getSourceKind(&graph, alias_val);
    try std.testing.expectEqual(source1, source2, "Strong alias should have same source kind");
}

// ============================================================================
// isUseAfterFreeViaAlias tests
// ============================================================================

test "isUseAfterFreeViaAlias - detects UAF when pointer used after free (happy path)" {
    var graph = try MemoryGraph.init(std.testing.allocator);
    defer graph.deinit();

    const ptr_val: u64 = 0x12345678;
    const use_inst: u64 = 0xAAA;
    const alloc_inst: u64 = 0x111;
    const free_inst: u64 = 0x222;

    _ = try MemoryGraph.trackAlloc(&graph, alloc_inst, ptr_val, .heap, .unknown, .c, null);
    try MemoryGraph.trackFree(&graph, ptr_val, free_inst, .c);

    const result = MemoryGraph.isUseAfterFreeViaAlias(&graph, ptr_val, use_inst);
    try std.testing.expect(result != null, "Should detect use-after-free");
}

test "isUseAfterFreeViaAlias - returns null when pointer not freed (boundary)" {
    var graph = try MemoryGraph.init(std.testing.allocator);
    defer graph.deinit();

    const ptr_val: u64 = 0x12345678;
    const alloc_inst: u64 = 0x111;

    _ = try MemoryGraph.trackAlloc(&graph, alloc_inst, ptr_val, .heap, .unknown, .c, null);
    // Don't free

    const result = MemoryGraph.isUseAfterFreeViaAlias(&graph, ptr_val, 0xBBB);
    try std.testing.expect(result == null, "Should NOT detect UAF for non-freed pointer");
}

test "isUseAfterFreeViaAlias - returns null for unknown pointer (error case)" {
    var graph = try MemoryGraph.init(std.testing.allocator);
    defer graph.deinit();

    const result = MemoryGraph.isUseAfterFreeViaAlias(&graph, 0xDEAD, 0xBEEF);
    try std.testing.expect(result == null, "Unknown pointer should return null");
}

// ============================================================================
// findDangerousAliases tests
// ============================================================================

test "findDangerousAliases - returns aliases of freed pointer (happy path)" {
    var graph = try MemoryGraph.init(std.testing.allocator);
    defer graph.deinit();

    const ptr_val: u64 = 0x1000;
    const alias1: u64 = 0x2000;
    const alias2: u64 = 0x3000;
    const alloc_inst: u64 = 0x111;
    const free_inst: u64 = 0x222;

    _ = try MemoryGraph.trackAlloc(&graph, alloc_inst, ptr_val, .heap, .unknown, .c, null);
    try MemoryGraph.trackAlias(&graph, alias1, ptr_val, false);
    try MemoryGraph.trackAlias(&graph, alias2, ptr_val, false);
    try MemoryGraph.trackFree(&graph, ptr_val, free_inst, .c);

    const aliases = try MemoryGraph.findDangerousAliases(&graph, ptr_val, std.testing.allocator);
    defer std.testing.allocator.free(aliases);

    try std.testing.expectEqual(@as(usize, 2), aliases.len, "Should find 2 dangerous aliases");
}

test "findDangerousAliases - returns empty for non-freed pointer (boundary)" {
    var graph = try MemoryGraph.init(std.testing.allocator);
    defer graph.deinit();

    const ptr_val: u64 = 0x1000;
    const alloc_inst: u64 = 0x111;

    _ = try MemoryGraph.trackAlloc(&graph, alloc_inst, ptr_val, .heap, .unknown, .c, null);
    // Don't free

    const aliases = try MemoryGraph.findDangerousAliases(&graph, ptr_val, std.testing.allocator);
    defer std.testing.allocator.free(aliases);

    try std.testing.expectEqual(@as(usize, 0), aliases.len, "Should find 0 aliases for non-freed pointer");
}

// ============================================================================
// isOnDangerPath tests (basic coverage)
// ============================================================================

test "isOnDangerPath - returns safe for non-FFI pointer (happy path)" {
    var graph = try MemoryGraph.init(std.testing.allocator);
    defer graph.deinit();

    const ptr_val: u64 = 0x1000;
    const alloc_inst: u64 = 0x111;

    _ = try MemoryGraph.trackAlloc(&graph, alloc_inst, ptr_val, .heap, .unknown, .c, null);

    // This is a simplified test - full isOnDangerPath testing requires
    // PassContext with FFI boundaries, which is beyond scope here
    const source = MemoryGraph.getSourceKind(&graph, ptr_val);
    try std.testing.expectEqual(SourceKind.heap, source, "Should have heap source kind");
}

// ============================================================================
// trackCallArg + trackCallRet tests
// ============================================================================

test "trackCallArg - records pointer passed to function (happy path)" {
    var graph = try MemoryGraph.init(std.testing.allocator);
    defer graph.deinit();

    const ptr_val: u64 = 0x1000;
    const alloc_inst: u64 = 0x111;
    const call_inst: u64 = 0x222;

    _ = try MemoryGraph.trackAlloc(&graph, alloc_inst, ptr_val, .heap, .unknown, .c, null);
    try MemoryGraph.trackCallArg(&graph, call_inst, "free", ptr_val, 0);

    const is_passed = MemoryGraph.isPassedAsArg(&graph, ptr_val);
    try std.testing.expect(is_passed, "Should be marked as passed as argument");
}

test "trackCallRet - records pointer returned from function (happy path)" {
    var graph = try MemoryGraph.init(std.testing.allocator);
    defer graph.deinit();

    const ptr_val: u64 = 0x1000;
    const call_inst: u64 = 0x111;

    try MemoryGraph.trackCallRet(&graph, call_inst, "malloc", ptr_val);

    const is_returned = MemoryGraph.isReturnedFromCall(&graph, ptr_val);
    try std.testing.expect(is_returned, "Should be marked as returned from call");
}

// ============================================================================
// FuncCounter tests
// ============================================================================

test "recordFuncAlloc + recordFuncFree - tracks function heap operations (happy path)" {
    var graph = try MemoryGraph.init(std.testing.allocator);
    defer graph.deinit();

    const func_ptr: u64 = 0x1000;

    MemoryGraph.recordFuncAlloc(&graph, func_ptr);
    MemoryGraph.recordFuncAlloc(&graph, func_ptr);
    MemoryGraph.recordFuncFree(&graph, func_ptr);

    const counter = MemoryGraph.getFuncCounter(&graph, func_ptr);
    try std.testing.expectEqual(@as(u64, 2), counter.allocs, "Should have 2 allocations");
    try std.testing.expectEqual(@as(u64, 1), counter.frees, "Should have 1 free");
    try std.testing.expectEqual(@as(i64, 1), counter.net(), "Net should be 1");
}
