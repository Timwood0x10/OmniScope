// ============================================================================
// Memory Relations — Zero-Copy Single-Pass Memory Tracking
// ============================================================================
//
// Design Goals:
//   1. TRUE single-pass: build relations AND validate in one scan
//   2. MS-level performance: zero string copies, pre-allocated, O(1) ops
//   3. Minimal false positives: multi-layer validation with context
//
// Key Optimizations:
//   - Use u64 hash as key (no string allocation)
//   - Pre-allocate HashMaps based on module size
//   - Inline validation during scan (no post-processing)
//   - Fast-path for common patterns (alloc/free matching)
//
// Architecture:
//   Scan each function once → simultaneously:
//     1. Record call edges in call_graph
//     2. Track alloc/free counts per function
//     3. Validate free calls against known allocs (cross-function)
//     4. Report issues immediately (no second pass)
//
// ============================================================================

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const FuzzyMatcher = @import("memory_graph.zig").FuzzyMatcher;

/// Hash a string slice to u64 for zero-copy key storage
fn hashString(s: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(s);
    return hasher.final();
}

pub const PointerOrigin = struct {
    alloc_func_hash: u64,
    confidence: f32 = 1.0,
};

pub const FuncMemoryStats = struct {
    alloc_count: u32 = 0,
    free_count: u32 = 0,
    has_alloc_in_callees: bool = false,
};

pub const MemoryRelations = struct {
    allocator: std.mem.Allocator,

    /// Call graph: caller_hash → list of callee hashes
    call_graph: std.AutoHashMap(u64, std.ArrayList(u64)),

    /// Pointer origins: ptr_value → which func created it (by hash)
    origins: std.AutoHashMap(u64, PointerOrigin),

    /// Per-function memory stats: func_hash → stats
    func_stats: std.AutoHashMap(u64, FuncMemoryStats),

    /// Reverse lookup: ptr_value → func_hash that owns it
    ptr_owner: std.AutoHashMap(u64, u64),

    /// String interning table: hash → original string (for debug/output only)
    string_table: std.AutoHashMap(u64, []const u8),

    pub fn init(allocator: std.mem.Allocator, estimated_funcs: usize) !MemoryRelations {
        const capacity = @max(estimated_funcs, 256);

        var self = MemoryRelations{
            .allocator = allocator,
            .call_graph = std.AutoHashMap(u64, std.ArrayList(u64)).init(allocator),
            .origins = std.AutoHashMap(u64, PointerOrigin).init(allocator),
            .func_stats = std.AutoHashMap(u64, FuncMemoryStats).init(allocator),
            .ptr_owner = std.AutoHashMap(u64, u64).init(allocator),
            .string_table = std.AutoHashMap(u64, []const u8).init(allocator),
        };

        try self.call_graph.ensureTotalCapacity(@intCast(capacity));
        try self.origins.ensureTotalCapacity(@intCast(capacity * 4));
        try self.func_stats.ensureTotalCapacity(@intCast(capacity));
        try self.ptr_owner.ensureTotalCapacity(@intCast(capacity * 4));
        try self.string_table.ensureTotalCapacity(@intCast(capacity * 2));

        return self;
    }

    pub fn deinit(self: *MemoryRelations) void {
        var cg_iter = self.call_graph.iterator();
        while (cg_iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.call_graph.deinit();

        self.origins.deinit();
        self.func_stats.deinit();
        self.ptr_owner.deinit();

        var st_iter = self.string_table.iterator();
        while (st_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.string_table.deinit();
    }

    /// Intern a string (store once, return hash). Used for output/debug only.
    pub fn internString(self: *MemoryRelations, s: []const u8) !u64 {
        const h = hashString(s);
        const gop = try self.string_table.getOrPut(h);
        if (!gop.found_existing) {
            gop.value_ptr.* = try self.allocator.dupe(u8, s);
        }
        return h;
    }

    /// Get interned string back from hash (for error messages)
    pub fn getString(self: *MemoryRelations, h: u64) ?[]const u8 {
        return self.string_table.get(h);
    }

    /// Record a call edge: caller → callee
    pub fn recordCall(self: *MemoryRelations, caller_hash: u64, callee_hash: u64) !void {
        const gop = try self.call_graph.getOrPut(caller_hash);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList(u64).empty;
        }
        try gop.value_ptr.append(self.allocator, callee_hash);
    }

    /// Record an alloc operation in a function
    pub fn recordAlloc(self: *MemoryRelations, func_hash: u64, ptr_value: u64) !void {
        var gop = try self.func_stats.getOrPut(func_hash);
        if (!gop.found_existing) {
            gop.value_ptr.* = FuncMemoryStats{};
        }
        gop.value_ptr.alloc_count += 1;

        if (!self.origins.contains(ptr_value)) {
            try self.origins.put(ptr_value, .{ .alloc_func_hash = func_hash });
            try self.ptr_owner.put(ptr_value, func_hash);
        }
    }

    /// Record a free operation in a function
    pub fn recordFree(self: *MemoryRelations, func_hash: u64) !void {
        var gop = try self.func_stats.getOrPut(func_hash);
        if (!gop.found_existing) {
            gop.value_ptr.* = FuncMemoryStats{};
        }
        gop.value_ptr.free_count += 1;
    }

    /// Check if a free call is valid (single-pass inline validation)
    ///
    /// Validation layers (fast to slow):
    ///   1. Fast path: ptr has known origin from same func → VALID
    ///   2. Medium path: ptr owner has alloc_count > 0 → LIKELY VALID
    ///   3. Slow path: check callee chain for allocs → CONTEXTUAL
    ///   4. Fallback: fuzzy name matching → HEURISTIC
    ///
    /// Returns: (is_valid, confidence, reason)
    pub fn validateFree(
        self: *MemoryRelations,
        free_func_hash: u64,
        ptr_value: u64,
        free_func_name: []const u8,
    ) struct { is_valid: bool, confidence: f32, reason: u8 } {
        const origin = self.origins.get(ptr_value);

        if (origin) |o| {
            if (o.alloc_func_hash == free_func_hash) {
                return .{ .is_valid = true, .confidence = 0.98, .reason = 1 };
            }
            const owner_stats = self.func_stats.get(o.alloc_func_hash);
            if (owner_stats != null and owner_stats.?.alloc_count > 0) {
                return .{ .is_valid = true, .confidence = 0.85, .reason = 2 };
            }
        }

        const owner_hash = self.ptr_owner.get(ptr_value);
        if (owner_hash) |h| {
            const stats = self.func_stats.get(h);
            if (stats != null and stats.?.alloc_count > 0) {
                if (self.hasAllocInCalleeChain(h)) {
                    return .{ .is_valid = true, .confidence = 0.75, .reason = 3 };
                }
            }
        }

        // R8-H11 FIX: Recognizing a function as free should confirm validity, not invalidate it
        if (FuzzyMatcher.classify(free_func_name) == .free) {
            return .{ .is_valid = true, .confidence = 0.6, .reason = 4 };
        }

        return .{ .is_valid = false, .confidence = 0.5, .reason = 0 };
    }

    /// Check if any function in the call chain has allocations (iterative DFS)
    pub fn hasAllocInCalleeChain(self: *MemoryRelations, func_hash: u64) bool {
        var visited = std.AutoHashMap(u64, void).init(self.allocator);
        defer visited.deinit();

        var stack: [64]u64 = undefined;
        var stack_len: usize = 0;

        stack[stack_len] = func_hash;
        stack_len += 1;

        while (stack_len > 0) {
            stack_len -= 1;
            const current = stack[stack_len];

            if (visited.contains(current)) continue;
            visited.put(current, {}) catch {};

            const stats = self.func_stats.get(current);
            if (stats != null and stats.?.alloc_count > 0) {
                return true;
            }

            const callees = self.call_graph.get(current);
            if (callees) |list| {
                for (list.items) |callee| {
                    if (stack_len < stack.len) {
                        stack[stack_len] = callee;
                        stack_len += 1;
                    }
                }
            }
        }

        return false;
    }

    /// Get alloc count for a function
    pub fn getAllocCount(self: *MemoryRelations, func_hash: u64) u32 {
        if (self.func_stats.get(func_hash)) |s| {
            return s.alloc_count;
        }
        return 0;
    }

    /// Get free count for a function
    pub fn getFreeCount(self: *MemoryRelations, func_hash: u64) u32 {
        if (self.func_stats.get(func_hash)) |s| {
            return s.free_count;
        }
        return 0;
    }
};
