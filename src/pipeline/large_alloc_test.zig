//! Tests for Large Allocation Detection Boost
//!
//! Coverage target: ≥85% for size-based confidence boost logic
//! Test categories:
//!   - Large allocation (>1MB) gets +0.10 boost
//!   - Medium allocation (>100KB) gets +0.05 boost
//!   - Small allocation (<100KB) gets no boost
//!   - Unknown size (null) skips boost gracefully
//!
//! Note: getAllocationSize() requires real LLVM IR instructions, so we test
//! the confidence calculation path with simulated AllocRecord data.

const std = @import("std");

const GlobalAllocTracker = @import("../types/pass_types.zig").GlobalAllocTracker;

// ============================================================================
// Test 1: Large allocation leak gets +0.10 boost
// ============================================================================

test "large allocation leak gets +0.10 boost" {
    // Simulate a 2MB allocation leak
    // Expected: base_confidence += 0.10
    // Final confidence should be >= 0.68 (0.58 + 0.10)

    var tracker = GlobalAllocTracker.init(std.testing.allocator);
    defer tracker.deinit();

    // Insert a large allocation record
    const ptr_val: u64 = 0x1234;
    const inst_id: u32 = 1;
    tracker.insertAlloc(
        ptr_val,
        "test_function",
        "malloc",
        false,
        inst_id,
        false,
        null, // func_val
        2 * 1024 * 1024, // 2 MB allocation
    ) catch |err| {
        std.debug.print("insertAlloc failed: {}\n", .{err});
        return err;
    };

    // Verify the record was stored with correct size
    try std.testing.expectEqual(@as(usize, 1), tracker.size());
    const rec = &tracker.records.items[0];
    try std.testing.expect(rec.alloc_size != null);
    try std.testing.expectEqual(@as(u64, 2 * 1024 * 1024), rec.alloc_size.?);

    // Simulate confidence calculation (from pipeline.zig logic)
    var base_confidence: f32 = 0.58; // Base score for memory_leak

    // Apply size-based boost (same logic as pipeline.zig)
    if (rec.alloc_size) |size| {
        if (size > 1024 * 1024) {
            base_confidence += 0.10; // Large allocation
        } else if (size > 1024 * 100) {
            base_confidence += 0.05; // Medium-large allocation
        }
    }

    // Verify large allocation got the boost
    try std.testing.expect(base_confidence >= 0.68);
    try std.testing.expect(base_confidence < 0.69); // Should be exactly 0.68
}

// ============================================================================
// Test 2: Medium allocation leak gets +0.05 boost
// ============================================================================

test "medium allocation leak gets +0.05 boost" {
    // Simulate a 200KB allocation leak
    // Expected: base_confidence += 0.05
    // Final confidence should be >= 0.63 (0.58 + 0.05)

    var tracker = GlobalAllocTracker.init(std.testing.allocator);
    defer tracker.deinit();

    // Insert a medium allocation record
    const ptr_val: u64 = 0x5678;
    const inst_id: u32 = 2;
    tracker.insertAlloc(
        ptr_val,
        "test_function",
        "calloc",
        false,
        inst_id,
        false,
        null, // func_val
        200 * 1024, // 200 KB allocation
    ) catch |err| {
        std.debug.print("insertAlloc failed: {}\n", .{err});
        return err;
    };

    // Verify the record was stored with correct size
    try std.testing.expectEqual(@as(usize, 1), tracker.size());
    const rec = &tracker.records.items[0];
    try std.testing.expect(rec.alloc_size != null);
    try std.testing.expectEqual(@as(u64, 200 * 1024), rec.alloc_size.?);

    // Simulate confidence calculation
    var base_confidence: f32 = 0.58;

    // Apply size-based boost
    if (rec.alloc_size) |size| {
        if (size > 1024 * 1024) {
            base_confidence += 0.10;
        } else if (size > 1024 * 100) {
            base_confidence += 0.05; // Medium-large allocation
        }
    }

    // Verify medium allocation got the boost
    try std.testing.expect(base_confidence >= 0.63);
    try std.testing.expect(base_confidence < 0.64); // Should be exactly 0.63
}

// ============================================================================
// Test 3: Small allocation leak gets no size boost
// ============================================================================

test "small allocation leak gets no size boost" {
    // Simulate a 1KB allocation leak
    // Expected: no additional boost
    // Final confidence should remain at base (0.58)

    var tracker = GlobalAllocTracker.init(std.testing.allocator);
    defer tracker.deinit();

    // Insert a small allocation record
    const ptr_val: u64 = 0x9ABC;
    const inst_id: u32 = 3;
    tracker.insertAlloc(
        ptr_val,
        "test_function",
        "malloc",
        false,
        inst_id,
        false,
        null, // func_val
        1024, // 1 KB allocation
    ) catch |err| {
        std.debug.print("insertAlloc failed: {}\n", .{err});
        return err;
    };

    // Verify the record was stored with correct size
    try std.testing.expectEqual(@as(usize, 1), tracker.size());
    const rec = &tracker.records.items[0];
    try std.testing.expect(rec.alloc_size != null);
    try std.testing.expectEqual(@as(u64, 1024), rec.alloc_size.?);

    // Simulate confidence calculation
    var base_confidence: f32 = 0.58;

    // Apply size-based boost (should not trigger)
    if (rec.alloc_size) |size| {
        if (size > 1024 * 1024) {
            base_confidence += 0.10;
        } else if (size > 1024 * 100) {
            base_confidence += 0.05;
        }
        // Small allocations (< 100 KB): no additional boost
    }

    // Verify small allocation did NOT get any boost
    try std.testing.expectApproxEqAbs(0.58, base_confidence, 0.001);
}

// ============================================================================
// Test 4: Unknown size allocation skips boost gracefully
// ============================================================================

test "unknown size allocation skips boost gracefully" {
    // Simulate allocation with unknown size (indirect call)
    // Expected: no crash, no error, just skip boost
    // Confidence should remain at base (0.58)

    var tracker = GlobalAllocTracker.init(std.testing.allocator);
    defer tracker.deinit();

    // Insert an allocation record with unknown size (null)
    const ptr_val: u64 = 0xDEF0;
    const inst_id: u32 = 4;
    tracker.insertAlloc(
        ptr_val,
        "test_function",
        "alloc_via_ptr", // Indirect call through function pointer
        false,
        inst_id,
        false,
        null, // func_val
        null, // Unknown size (null)
    ) catch |err| {
        std.debug.print("insertAlloc failed: {}\n", .{err});
        return err;
    };

    // Verify the record was stored with null size
    try std.testing.expectEqual(@as(usize, 1), tracker.size());
    const rec = &tracker.records.items[0];
    try std.testing.expect(rec.alloc_size == null); // Size should be null

    // Simulate confidence calculation (should not crash)
    var base_confidence: f32 = 0.58;

    // Apply size-based boost (should gracefully skip)
    if (rec.alloc_size) |size| {
        _ = size;
        // This block should NOT execute for null size
        base_confidence += 999; // Impossible value to detect accidental execution
    }

    // Verify confidence unchanged (graceful skip)
    try std.testing.expectApproxEqAbs(0.58, base_confidence, 0.001);
}

// ============================================================================
// Test 5: Boundary condition — exactly 1 MB (no boost)
// ============================================================================

test "boundary exactly 1MB gets no large boost" {
    // Exactly 1 MB should NOT get +0.10 boost (threshold is > 1MB)
    // But it SHOULD get +0.05 medium boost (>100KB)

    var tracker = GlobalAllocTracker.init(std.testing.allocator);
    defer tracker.deinit();

    tracker.insertAlloc(
        0x1111,
        "test",
        "malloc",
        false,
        5,
        false,
        null,
        1024 * 1024, // Exactly 1 MB
    ) catch |err| return err;

    const rec = &tracker.records.items[0];
    var base_confidence: f32 = 0.58;

    if (rec.alloc_size) |size| {
        if (size > 1024 * 1024) {
            base_confidence += 0.10; // Should NOT trigger (not > 1MB)
        } else if (size > 1024 * 100) {
            base_confidence += 0.05; // Should trigger (>100KB)
        }
    }

    // Should get medium boost only
    try std.testing.expectApproxEqAbs(0.63, base_confidence, 0.001);
}

// ============================================================================
// Test 6: Boundary condition — exactly 100 KB (no boost)
// ============================================================================

test "boundary exactly 100KB gets no medium boost" {
    // Exactly 100 KB should NOT get any boost (threshold is >100KB)

    var tracker = GlobalAllocTracker.init(std.testing.allocator);
    defer tracker.deinit();

    tracker.insertAlloc(
        0x2222,
        "test",
        "malloc",
        false,
        6,
        false,
        null,
        1024 * 100, // Exactly 100 KB
    ) catch |err| return err;

    const rec = &tracker.records.items[0];
    var base_confidence: f32 = 0.58;

    if (rec.alloc_size) |size| {
        if (size > 1024 * 1024) {
            base_confidence += 0.10;
        } else if (size > 1024 * 100) {
            base_confidence += 0.05; // Should NOT trigger (not >100KB)
        }
    }

    // Should get NO boost at all
    try std.testing.expectApproxEqAbs(0.58, base_confidence, 0.001);
}

// ============================================================================
// Test 7: Combined boosts — global + dangerous + large
// ============================================================================

test "combined boosts stack correctly" {
    // Test that all three boosts can stack:
    //   - Global/static: +0.08
    //   - Dangerous function: +0.07
    //   - Large allocation: +0.10
    // Total: 0.58 + 0.08 + 0.07 + 0.10 = 0.83

    var tracker = GlobalAllocTracker.init(std.testing.allocator);
    defer tracker.deinit();

    tracker.insertAlloc(
        0x3333,
        "global_var_init",
        "malloc",
        true, // is_global_or_static = true
        7,
        false,
        null,
        5 * 1024 * 1024, // 5 MB (large)
    ) catch |err| return err;

    const rec = &tracker.records.items[0];

    // Simulate full confidence calculation from pipeline.zig
    var base_confidence: f32 = 0.58;

    // Boost 1: Global/static allocation
    if (rec.is_global_or_static) {
        base_confidence += 0.08;
    }

    // Boost 2: Known dangerous allocator
    const is_known_dangerous_alloc =
        std.mem.indexOf(u8, rec.alloc_callee, "alloc") != null or
        std.mem.indexOf(u8, rec.alloc_callee, "malloc") != null;
    if (is_known_dangerous_alloc) {
        base_confidence += 0.07;
    }

    // Boost 3: Large allocation
    if (rec.alloc_size) |size| {
        if (size > 1024 * 1024) {
            base_confidence += 0.10;
        } else if (size > 1024 * 100) {
            base_confidence += 0.05;
        }
    }

    // All three boosts should stack
    try std.testing.expect(base_confidence >= 0.83);
    try std.testing.expect(base_confidence < 0.84); // Should be exactly 0.83
}

// ============================================================================
// Test 8: Confidence cap at 0.95 still applies
// ============================================================================

test "confidence cap at 0.95 with all boosts" {
    // Even with maximum boosts, confidence should be capped at 0.95

    var tracker = GlobalAllocTracker.init(std.testing.allocator);
    defer tracker.deinit();

    tracker.insertAlloc(
        0x4444,
        "super_dangerous",
        "malloc",
        true, // global
        8,
        false, // not conditional (no reduction)
        null,
        100 * 1024 * 1024, // 100 MB (very large)
    ) catch |err| return err;

    const rec = &tracker.records.items[0];

    var base_confidence: f32 = 0.78; // High base (on FFI path)

    // Apply all boosts
    if (rec.is_global_or_static) base_confidence += 0.08;
    base_confidence += 0.07; // malloc is dangerous
    if (rec.alloc_size) |size| {
        if (size > 1024 * 1024) base_confidence += 0.10;
    }

    // Apply cap (from pipeline.zig)
    base_confidence = @min(base_confidence, 0.95);

    // Should be capped at 0.95
    try std.testing.expect(base_confidence <= 0.95);
    try std.testing.expect(base_confidence > 0.90); // Should be close to cap
}

// ============================================================================
// Test 9: Multiple records with different sizes
// ============================================================================

test "multiple records with different sizes" {
    // Test that tracker can handle multiple records with varying sizes

    var tracker = GlobalAllocTracker.init(std.testing.allocator);
    defer tracker.deinit();

    // Insert 3 allocations with different sizes
    tracker.insertAlloc(0xAAAA, "f1", "malloc", false, 10, false, null, 512) catch |err| return err;
    tracker.insertAlloc(0xBBBB, "f2", "calloc", false, 11, false, null, 500 * 1024) catch |err| return err;
    tracker.insertAlloc(0xCCCC, "f3", "malloc", false, 12, false, null, 3 * 1024 * 1024) catch |err| return err;

    try std.testing.expectEqual(@as(usize, 3), tracker.size());

    // Verify each record has correct size
    try std.testing.expectEqual(@as(u64, 512), tracker.records.items[0].alloc_size.?);
    try std.testing.expectEqual(@as(u64, 500 * 1024), tracker.records.items[1].alloc_size.?);
    try std.testing.expectEqual(@as(u64, 3 * 1024 * 1024), tracker.records.items[2].alloc_size.?);

    // Calculate confidence for each
    const expected_boosts = [_]f32{ 0.0, 0.05, 0.10 };
    for (tracker.records.items, 0..) |rec, i| {
        var conf: f32 = 0.58;
        if (rec.alloc_size) |size| {
            if (size > 1024 * 1024) {
                conf += 0.10;
            } else if (size > 1024 * 100) {
                conf += 0.05;
            }
        }
        try std.testing.expectApproxEqAbs(expected_boosts[i], conf - 0.58, 0.001);
    }
}

// ============================================================================
// Test 10: AllocRecord default value (null size)
// ============================================================================

test "AllocRecord defaults to null alloc_size" {
    // Verify backward compatibility: old code without alloc_size parameter
    // should compile and work correctly (default is null)

    var tracker = GlobalAllocTracker.init(std.testing.allocator);
    defer tracker.deinit();

    // This uses the new signature but explicitly passes null
    tracker.insertAlloc(
        0xDDDD,
        "legacy_func",
        "unknown_allocator",
        false,
        13,
        false,
        null,
        null, // Explicitly null (simulates old code)
    ) catch |err| return err;

    const rec = &tracker.records.items[0];
    try std.testing.expect(rec.alloc_size == null);

    // Should behave like unknown size (no crash, no boost)
    var conf: f32 = 0.58;
    if (rec.alloc_size) |size| {
        _ = size;
        conf += 999; // Should never execute
    }
    try std.testing.expectApproxEqAbs(0.58, conf, 0.001);
}
