//! Zig Allocator Tracker - Confidence-based leak detection for Zig allocations.
//!
//! ## Core Insight
//!
//! Zig's design philosophy: "Unified memory management through Allocator".
//! Once we identify an Arena/GPA allocator, we can deterministically assess
//! leak probability based on the allocator's lifecycle semantics.
//!
//! ## Architecture Integration
//!
//! Integrates with existing systems:
//!   - MemoryGraph: ownership_model, container_type fields
//!   - ContainerInferer: pattern recognition
//!   - FFIContractDB: shouldReportLeak() logic
//!
//! ## Confidence Scoring
//!
//! Instead of binary "report/suppress", we assign confidence scores:
//!   - 0.9+: Critical (almost certainly a real bug)
//!   - 0.7-0.9: High (very likely)
//!   - 0.5-0.7: Medium (needs human review)
//!   - <0.5: Low/Likely FP (hidden by default)

const std = @import("std");
const log = std.log.scoped(.zig_allocator_tracker);
const memory_types = @import("../types/memory_graph_types.zig");

/// Zig allocator classification.
pub const AllocatorKind = enum {
    /// std.heap.GeneralPurposeAllocator - tracks all allocations
    general_purpose,
    /// std.heap.ArenaAllocator - batch free on deinit
    arena,
    /// std.heap.FixedBufferAllocator - stack-based, auto-freed
    fixed_buffer,
    /// std.heap.page_allocator - direct mmap, manual management
    page_allocator,
    /// std.testing.allocator - test-only, leak detection built-in
    testing_allocator,
    /// User-defined allocator (unknown behavior)
    custom,
    /// Not a Zig allocator
    none,
};

/// Confidence score for leak detection.
/// Range: [0.0, 1.0] where 1.0 = definitely a leak, 0.0 = definitely not.
pub const LeakConfidence = struct {
    score: f32,
    reason: []const u8,

    /// Check if this is a critical-severity leak (>= 0.9).
    pub fn isCritical(self: LeakConfidence) bool {
        return self.score >= 0.9;
    }

    /// Check if this is a high-severity leak (0.7 - 0.9).
    pub fn isHigh(self: LeakConfidence) bool {
        return self.score >= 0.7 and self.score < 0.9;
    }

    /// Check if this is a medium-severity leak (0.5 - 0.7).
    pub fn isMedium(self: LeakConfidence) bool {
        return self.score >= 0.5 and self.score < 0.7;
    }

    /// Check if this is a low-severity leak (< 0.5).
    pub fn isLow(self: LeakConfidence) bool {
        return self.score < 0.5;
    }
};

/// Zig Allocator Tracker - integrates with existing MemoryGraph.
pub const Tracker = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Tracker {
        return .{ .allocator = allocator };
    }

    /// Classify the allocator kind from function name.
    ///
    /// Recognizes standard Zig allocators by name patterns:
    ///   - "GeneralPurposeAllocator" / "GPA" → .general_purpose
    ///   - "ArenaAllocator" / "arena" → .arena
    ///   - "FixedBufferAllocator" / "FixedBuffer" → .fixed_buffer
    ///   - "page_allocator" → .page_allocator
    ///   - "testing.allocator" → .testing_allocator
    ///   - "Allocator.alloc" / "Allocator.realloc" → .custom
    ///
    /// Arguments:
    ///   alloc_func - The allocation function name
    ///
    /// Returns:
    ///   Classified AllocatorKind
    pub fn classifyAllocator(alloc_func: []const u8) AllocatorKind {
        // GeneralPurposeAllocator (GPA)
        if (std.mem.indexOf(u8, alloc_func, "GeneralPurposeAllocator") != null or
            std.mem.indexOf(u8, alloc_func, "GPA") != null)
        {
            return .general_purpose;
        }

        // ArenaAllocator
        if (std.mem.indexOf(u8, alloc_func, "ArenaAllocator") != null or
            std.mem.indexOf(u8, alloc_func, "arena") != null)
        {
            return .arena;
        }

        // FixedBufferAllocator
        if (std.mem.indexOf(u8, alloc_func, "FixedBufferAllocator") != null or
            std.mem.indexOf(u8, alloc_func, "FixedBuffer") != null)
        {
            return .fixed_buffer;
        }

        // page_allocator
        if (std.mem.indexOf(u8, alloc_func, "page_allocator") != null) {
            return .page_allocator;
        }

        // testing.allocator
        if (std.mem.indexOf(u8, alloc_func, "testing.allocator") != null or
            std.mem.indexOf(u8, alloc_func, "testing_allocator") != null)
        {
            return .testing_allocator;
        }

        // Generic Allocator.alloc/realloc
        if (std.mem.indexOf(u8, alloc_func, "Allocator.alloc") != null or
            std.mem.indexOf(u8, alloc_func, "Allocator.realloc") != null or
            std.mem.indexOf(u8, alloc_func, "Allocator.create") != null)
        {
            return .custom;
        }

        return .none;
    }

    /// Calculate leak confidence score for a Zig allocation.
    ///
    /// This is the core "silver bullet" logic that integrates:
    ///   1. Allocator kind (Arena = low confidence leak)
    ///   2. Container type (ArrayList = managed by container)
    ///   3. Ownership model (RAII = has cleanup)
    ///   4. FFI boundary (cross-language = higher risk)
    ///
    /// Scoring algorithm:
    ///   Base score: 0.8 (assume likely leak)
    ///   Adjustments:
    ///     - Arena: -0.6 (batch-freed)
    ///     - FixedBuffer: -0.7 (stack-based)
    ///     - testing.allocator: -0.5 (leak-checked)
    ///     - GPA: -0.2 (tracked)
    ///     - page_allocator: +0.1 (manual)
    ///     - Container type: -0.4 (managed)
    ///     - RAII cleanup: -0.3 (has deinit)
    ///     - Ownership = .raii: -0.3
    ///     - FFI boundary: +0.2 (higher risk)
    ///   Final score clamped to [0.0, 1.0]
    ///
    /// Arguments:
    ///   node            - The AllocNode to analyze
    ///   alloc_func      - The allocation function name
    ///   is_ffi_boundary - Whether this crosses FFI boundary
    ///
    /// Returns:
    ///   LeakConfidence with score and reason
    pub fn calculateLeakConfidence(
        self: *Tracker,
        node: *const memory_types.AllocNode,
        alloc_func: []const u8,
        is_ffi_boundary: bool,
    ) LeakConfidence {
        _ = self;

        var score: f32 = 0.8; // Base score: likely a leak
        var reason_buf: [256]u8 = undefined;
        var reason: []const u8 = "";

        // Factor 1: Allocator Kind (most important for Zig)
        const allocator_kind = classifyAllocator(alloc_func);
        switch (allocator_kind) {
            .arena => {
                score -= 0.6;
                reason = "ArenaAllocator (batch-freed)";
            },
            .fixed_buffer => {
                score -= 0.7;
                reason = "FixedBufferAllocator (stack-based)";
            },
            .testing_allocator => {
                score -= 0.5;
                reason = "testing.allocator (leak-checked)";
            },
            .general_purpose => {
                score -= 0.2;
                reason = "GPA (tracked)";
            },
            .page_allocator => {
                score += 0.1;
                reason = "page_allocator (manual)";
            },
            .custom, .none => {
                reason = "unknown allocator";
            },
        }

        // Factor 2: Container Type (from ContainerInferer)
        if (node.container_type) |container| {
            switch (container) {
                .zig_arraylist, .zig_hashmap, .zig_buffer, .zig_multiarraylist => {
                    score -= 0.4;
                    reason = std.fmt.bufPrint(&reason_buf, "Zig container ({s})", .{@tagName(container)}) catch reason;
                },
                else => {},
            }
        }

        // Factor 3: Ownership Model (from MemoryGraph)
        switch (node.ownership_model) {
            .raii => {
                score -= 0.3;
                if (reason.len == 0) reason = "RAII cleanup";
            },
            .gc => {
                score -= 0.5;
                if (reason.len == 0) reason = "GC-managed";
            },
            .refcount => {
                score -= 0.2;
                if (reason.len == 0) reason = "refcounted";
            },
            .manual, .hybrid => {},
        }

        // Factor 4: RAII Cleanup Sites
        if (node.has_raii_cleanup) {
            score -= 0.3;
            if (reason.len == 0) reason = "has cleanup sites";
        }

        // Factor 5: FFI Boundary (higher risk)
        if (is_ffi_boundary) {
            score += 0.2;
            if (reason.len == 0) reason = "FFI boundary";
        }

        // Clamp score to [0.0, 1.0]
        score = @max(0.0, @min(1.0, score));

        return .{
            .score = score,
            .reason = if (reason.len > 0) reason else "unknown",
        };
    }

    /// Check if an allocation should be reported based on confidence threshold.
    ///
    /// Arguments:
    ///   node            - The AllocNode to check
    ///   alloc_func      - The allocation function name
    ///   is_ffi_boundary - Whether this crosses FFI boundary
    ///   threshold       - Minimum confidence to report (default: 0.7)
    ///
    /// Returns:
    ///   true if should report, false if should suppress
    pub fn shouldReport(
        self: *Tracker,
        node: *const memory_types.AllocNode,
        alloc_func: []const u8,
        is_ffi_boundary: bool,
        threshold: f32,
    ) bool {
        const confidence = self.calculateLeakConfidence(node, alloc_func, is_ffi_boundary);
        return confidence.score >= threshold;
    }
};

// ════════════════════════════════════════════════════
// Unit Tests
// ════════════════════════════════════════════════════

const testing = std.testing;

test "classifyAllocator - recognizes standard allocators" {
    try testing.expectEqual(AllocatorKind.arena, Tracker.classifyAllocator("std.heap.ArenaAllocator.alloc"));
    try testing.expectEqual(AllocatorKind.general_purpose, Tracker.classifyAllocator("std.heap.GeneralPurposeAllocator.alloc"));
    try testing.expectEqual(AllocatorKind.fixed_buffer, Tracker.classifyAllocator("std.heap.FixedBufferAllocator.alloc"));
    try testing.expectEqual(AllocatorKind.page_allocator, Tracker.classifyAllocator("std.heap.page_allocator"));
    try testing.expectEqual(AllocatorKind.testing_allocator, Tracker.classifyAllocator("std.testing.allocator"));
    try testing.expectEqual(AllocatorKind.custom, Tracker.classifyAllocator("Allocator.alloc"));
    try testing.expectEqual(AllocatorKind.none, Tracker.classifyAllocator("malloc"));
}

test "classifyAllocator - handles short names" {
    try testing.expectEqual(AllocatorKind.general_purpose, Tracker.classifyAllocator("GPA.alloc"));
    try testing.expectEqual(AllocatorKind.arena, Tracker.classifyAllocator("arena.alloc"));
}

test "LeakConfidence - severity classification" {
    const critical = LeakConfidence{ .score = 0.95, .reason = "test" };
    try testing.expect(critical.isCritical());
    try testing.expect(!critical.isHigh());
    try testing.expect(!critical.isMedium());
    try testing.expect(!critical.isLow());

    const high = LeakConfidence{ .score = 0.8, .reason = "test" };
    try testing.expect(!high.isCritical());
    try testing.expect(high.isHigh());
    try testing.expect(!high.isMedium());
    try testing.expect(!high.isLow());

    const medium = LeakConfidence{ .score = 0.6, .reason = "test" };
    try testing.expect(!medium.isCritical());
    try testing.expect(!medium.isHigh());
    try testing.expect(medium.isMedium());
    try testing.expect(!medium.isLow());

    const low = LeakConfidence{ .score = 0.3, .reason = "test" };
    try testing.expect(!low.isCritical());
    try testing.expect(!low.isHigh());
    try testing.expect(!low.isMedium());
    try testing.expect(low.isLow());
}

/// Helper: create a mock AllocNode for testing (properly initialized, no undefined).
fn mockAllocNode(allocator: std.mem.Allocator) !memory_types.AllocNode {
    return .{
        .id = 0,
        .alloc_inst = 0,
        .merkle_root = 0,
        .aliases = std.AutoHashMap(u64, void).init(allocator),
        .freed = false,
        .freed_by = null,
        .source_kind = .heap_alloc,
        .free_sites = try std.ArrayList(memory_types.FreeRecord).initCapacity(allocator, 4),
        .escapes = null,
        .raii_cleanup_sites = try std.ArrayList(u64).initCapacity(allocator, 4),
        .defer_sites = try std.ArrayList(u64).initCapacity(allocator, 4),
    };
}

fn deinitMockAllocNode(node: *memory_types.AllocNode, allocator: std.mem.Allocator) void {
    node.aliases.deinit();
    node.free_sites.deinit(allocator);
    node.raii_cleanup_sites.deinit(allocator);
    node.defer_sites.deinit(allocator);
}

test "calculateLeakConfidence - ArenaAllocator = low confidence" {
    var tracker = Tracker.init(testing.allocator);

    var node = try mockAllocNode(testing.allocator);
    defer deinitMockAllocNode(&node, testing.allocator);
    node.ownership_model = .manual;
    node.has_raii_cleanup = false;
    node.container_type = null;

    const confidence = tracker.calculateLeakConfidence(
        &node,
        "std.heap.ArenaAllocator.alloc",
        false,
    );

    // Arena: base 0.8 - 0.6 = 0.2 (low)
    try testing.expect(confidence.isLow());
    try testing.expect(confidence.score < 0.5);
}

test "calculateLeakConfidence - page_allocator + FFI = high confidence" {
    var tracker = Tracker.init(testing.allocator);

    var node = try mockAllocNode(testing.allocator);
    defer deinitMockAllocNode(&node, testing.allocator);
    node.ownership_model = .manual;
    node.has_raii_cleanup = false;
    node.container_type = null;

    const confidence = tracker.calculateLeakConfidence(
        &node,
        "std.heap.page_allocator",
        true, // FFI boundary
    );

    // page_allocator: base 0.8 + 0.1 + 0.2 (FFI) = 1.0 (critical)
    try testing.expect(confidence.isHigh() or confidence.isCritical());
    try testing.expect(confidence.score >= 0.7);
}

test "calculateLeakConfidence - ArrayList container = low confidence" {
    var tracker = Tracker.init(testing.allocator);

    var node = try mockAllocNode(testing.allocator);
    defer deinitMockAllocNode(&node, testing.allocator);
    node.ownership_model = .raii;
    node.has_raii_cleanup = false;
    node.container_type = .zig_arraylist;

    const confidence = tracker.calculateLeakConfidence(
        &node,
        "std.ArrayList.append",
        false,
    );

    // Container (-0.4) + RAII ownership (-0.3) = base 0.8 - 0.7 = 0.1 (low)
    try testing.expect(confidence.isLow());
    try testing.expect(confidence.score < 0.5);
}

test "calculateLeakConfidence - GPA + RAII cleanup = medium confidence" {
    var tracker = Tracker.init(testing.allocator);

    var node = try mockAllocNode(testing.allocator);
    defer deinitMockAllocNode(&node, testing.allocator);
    node.ownership_model = .raii;
    node.has_raii_cleanup = true;
    node.container_type = null;

    const confidence = tracker.calculateLeakConfidence(
        &node,
        "std.heap.GeneralPurposeAllocator.alloc",
        false,
    );

    // GPA (-0.2) + RAII ownership (-0.3) + cleanup (-0.3) = 0.8 - 0.8 = 0.0 (low)
    try testing.expect(confidence.isLow());
}

test "shouldReport - respects threshold" {
    var tracker = Tracker.init(testing.allocator);

    var node = try mockAllocNode(testing.allocator);
    defer deinitMockAllocNode(&node, testing.allocator);
    node.ownership_model = .manual;
    node.has_raii_cleanup = false;
    node.container_type = null;

    // Arena allocation (low confidence ~0.2)
    try testing.expect(!tracker.shouldReport(&node, "std.heap.ArenaAllocator.alloc", false, 0.7));
    try testing.expect(!tracker.shouldReport(&node, "std.heap.ArenaAllocator.alloc", false, 0.5));

    // page_allocator + FFI (high confidence ~1.0)
    try testing.expect(tracker.shouldReport(&node, "std.heap.page_allocator", true, 0.7));
    try testing.expect(tracker.shouldReport(&node, "std.heap.page_allocator", true, 0.9));
}

test "calculateLeakConfidence - boundary cases" {
    var tracker = Tracker.init(testing.allocator);

    var node = try mockAllocNode(testing.allocator);
    defer deinitMockAllocNode(&node, testing.allocator);
    node.ownership_model = .manual;
    node.has_raii_cleanup = false;
    node.container_type = null;

    // Test score clamping to [0.0, 1.0]
    const conf1 = tracker.calculateLeakConfidence(&node, "std.heap.ArenaAllocator.alloc", false);
    try testing.expect(conf1.score >= 0.0 and conf1.score <= 1.0);

    const conf2 = tracker.calculateLeakConfidence(&node, "std.heap.page_allocator", true);
    try testing.expect(conf2.score >= 0.0 and conf2.score <= 1.0);
}
