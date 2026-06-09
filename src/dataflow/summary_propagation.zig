//! Summary-Based Cross-Function Analysis Engine
//!
//! Implements 1-layer deep function summary propagation for detecting
//! cross-function memory leaks without full interprocedural analysis.
//!
//! Design Principles:
//! - Conservative: Unknown functions default to safe (no false positives)
//! - 1-layer depth: Only caller → callee (not callee's callee)
//! - Cached: Avoid redundant analysis of the same function
//! - Extensible: Support for user-registered custom summaries

const std = @import("std");
const log = std.log.scoped(.summary_propagation);

/// Result of analyzing a function call for ownership transfer
pub const LeakAnalysisResult = enum {
    /// Ownership is legitimately transferred to callee (no leak)
    ownership_transferred,
    /// Allocation may escape to global state (suppress report)
    escaped,
    /// Possible leak detected (requires further analysis)
    possible_leak,
    /// Callee function unknown (conservative: don't report)
    unknown_callee,
    /// No allocation involved in this call
    no_alloc,
};

/// Statistics for propagation engine
pub const PropagationStats = struct {
    total_calls_analyzed: u32 = 0,
    ownership_transfers_detected: u32 = 0,
    escapes_detected: u32 = 0,
    possible_leaks_found: u32 = 0,
    cache_hits: u32 = 0,

    pub fn reset(self: *PropagationStats) void {
        self.* = PropagationStats{};
    }
};

/// Function summary describing allocation/free behavior
pub const FunctionSummary = struct {
    allocator: std.mem.Allocator,

    /// Which parameters receive allocations that callee will free
    alloc_params: std.DynamicBitSet,
    /// Which parameters consume ownership (callee takes responsibility)
    free_params: std.DynamicBitSet,
    /// Whether the return value is an owned allocation
    returns_owned: bool,
    /// Whether allocation may escape to global state
    may_escape: bool,
    /// Whether this function is a known deallocator
    is_deallocator: bool,
    /// Confidence level for this summary (0.0 - 1.0)
    confidence: f32,

    pub fn init(allocator: std.mem.Allocator, param_count: usize) !FunctionSummary {
        return FunctionSummary{
            .allocator = allocator,
            .alloc_params = try std.DynamicBitSet.initEmpty(allocator, param_count),
            .free_params = try std.DynamicBitSet.initEmpty(allocator, param_count),
            .returns_owned = false,
            .may_escape = false,
            .is_deallocator = false,
            .confidence = 0.88,
        };
    }

    pub fn deinit(self: *FunctionSummary) void {
        self.alloc_params.deinit();
        self.free_params.deinit();
    }

    /// Mark a parameter as receiving an allocation (callee frees it)
    pub fn markAllocParam(self: *FunctionSummary, idx: usize) void {
        if (idx < self.alloc_params.capacity()) {
            self.alloc_params.set(idx);
        }
    }

    /// Mark a parameter as consuming ownership (caller transfers)
    pub fn markFreeParam(self: *FunctionSummary, idx: usize) void {
        if (idx < self.free_params.capacity()) {
            self.free_params.set(idx);
        }
    }

    /// Check if a parameter receives allocation
    pub fn isAllocParam(self: *FunctionSummary, idx: usize) bool {
        return idx < self.alloc_params.capacity() and self.alloc_params.isSet(idx);
    }

    /// Check if a parameter consumes ownership
    pub fn isFreeParam(self: *const FunctionSummary, idx: usize) bool {
        return idx < self.free_params.capacity() and self.free_params.isSet(idx);
    }
};

/// Summary propagation engine for cross-function leak detection
pub const SummaryPropagation = struct {
    allocator: std.mem.Allocator,
    summaries: std.StringHashMap(FunctionSummary),
    analysis_cache: std.StringHashMap(LeakAnalysisResult),
    stats: PropagationStats,

    pub fn init(allocator: std.mem.Allocator) !SummaryPropagation {
        return SummaryPropagation{
            .allocator = allocator,
            .summaries = std.StringHashMap(FunctionSummary).init(allocator),
            .analysis_cache = std.StringHashMap(LeakAnalysisResult).init(allocator),
            .stats = PropagationStats{},
        };
    }

    pub fn deinit(self: *SummaryPropagation) void {
        var iter = self.summaries.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.summaries.deinit();
        self.analysis_cache.deinit();
    }

    /// Load built-in function summaries for standard libraries
    pub fn loadBuiltins(self: *SummaryPropagation) !void {
        // C Standard Library
        try self.registerAllocator("malloc", 1);
        try self.registerAllocator("calloc", 2);
        try self.registerAllocator("realloc", 2);
        try self.registerAllocator("strdup", 1);
        try self.registerAllocator("strndup", 2);
        try self.registerDeallocator("free", 1, 0);

        // C++ Operators
        try self.registerAllocator("operator new", 1);
        try self.registerDeallocator("operator delete", 1, 0);

        // Python C API
        try self.registerPyAlloc("PyList_New", 1);
        try self.registerPyAlloc("PyDict_New", 0);
        try self.registerPyAlloc("PyTuple_New", 1);
        try self.registerPyAlloc("PyBytes_FromString", 1);
        try self.registerPyAlloc("PyUnicode_FromString", 1);
        try self.registerDeallocator("Py_DECREF", 1, 0);
        try self.registerDeallocator("Py_XDECREF", 1, 0);

        // Rust FFI
        try self.registerRustAlloc("into_raw", 1);
        try self.registerRustDealloc("from_raw", 1);

        // JNI
        try self.registerJniAlloc("NewGlobalRef", 1);
        try self.registerJniDealloc("DeleteGlobalRef", 1, 0);
        try self.registerJniAlloc("NewLocalRef", 1);
        try self.registerJniDealloc("DeleteLocalRef", 1, 0);

        // Go CGo
        try self.registerGoAlloc("C.CString", 1);
        try self.registerGoAlloc("C.CBytes", 1);
        try self.registerGoAlloc("C.malloc", 1);
        try self.registerGoAlloc("C.calloc", 2);
        try self.registerDeallocator("C.free", 1, 0);

        log.info("Loaded {} built-in function summaries", .{self.summaries.count()});
    }

    /// Analyze a function call for potential ownership issues
    ///
    /// Arguments:
    ///   ptr_val - The pointer value being passed/freed
    ///   callee_name - Name of the called function
    ///   arg_idx - Index of the pointer argument (0-based)
    ///
    /// Returns:
    ///   LeakAnalysisResult indicating the ownership status
    pub fn analyzeCall(
        self: *SummaryPropagation,
        _ptr_val: u64,
        callee_name: []const u8,
        arg_idx: usize,
    ) LeakAnalysisResult {
        _ = _ptr_val; // Pointer value available for future enhancements
        self.stats.total_calls_analyzed += 1;

        // Check cache first
        if (self.analysis_cache.get(callee_name)) |cached| {
            self.stats.cache_hits += 1;
            return cached;
        }

        const result = self.analyzeCallInternal(callee_name, arg_idx);

        // Cache result (ignore error - caching is best-effort)
        self.analysis_cache.put(callee_name, result) catch {};

        return result;
    }

    /// Internal analysis logic (1-layer depth only)
    fn analyzeCallInternal(
        self: *SummaryPropagation,
        callee_name: []const u8,
        arg_idx: usize,
    ) LeakAnalysisResult {
        // Look up function in our summary database
        if (self.summaries.get(callee_name)) |summary| {
            // Check if this argument consumes ownership (legitimate transfer)
            if (summary.isFreeParam(arg_idx)) {
                self.stats.ownership_transfers_detected += 1;
                return .ownership_transferred;
            }

            // Check if allocation escapes to global state
            if (summary.may_escape) {
                self.stats.escapes_detected += 1;
                return .escaped;
            }

            // If returns_owned but we're not tracking the return value,
            // it might be a leak depending on context
            if (summary.returns_owned and !summary.isFreeParam(arg_idx)) {
                self.stats.possible_leaks_found += 1;
                return .possible_leak;
            }

            return .no_alloc;
        }

        // Unknown function - conservative approach
        return .unknown_callee;
    }

    /// Register a custom allocator function
    pub fn registerAllocator(
        self: *SummaryPropagation,
        name: []const u8,
        param_count: usize,
    ) !void {
        var summary = try FunctionSummary.init(self.allocator, param_count);
        summary.returns_owned = true;
        summary.confidence = 0.9;
        try self.summaries.put(name, summary);
    }

    /// Register a custom deallocator function
    pub fn registerDeallocator(
        self: *SummaryPropagation,
        name: []const u8,
        param_count: usize,
        free_param_idx: usize,
    ) !void {
        var summary = try FunctionSummary.init(self.allocator, param_count);
        summary.is_deallocator = true;
        summary.markFreeParam(free_param_idx);
        summary.confidence = 0.95;
        try self.summaries.put(name, summary);
    }

    /// Register Python C API allocator
    fn registerPyAlloc(
        self: *SummaryPropagation,
        name: []const u8,
        param_count: usize,
    ) !void {
        var summary = try FunctionSummary.init(self.allocator, param_count);
        summary.returns_owned = true;
        summary.confidence = 0.92;
        try self.summaries.put(name, summary);
    }

    /// Register Rust FFI allocator (into_raw pattern)
    fn registerRustAlloc(
        self: *SummaryPropagation,
        name: []const u8,
        param_count: usize,
    ) !void {
        var summary = try FunctionSummary.init(self.allocator, param_count);
        summary.returns_owned = true;
        summary.may_escape = true; // Raw pointers often escape
        summary.confidence = 0.88;
        try self.summaries.put(name, summary);
    }

    /// Register Rust FFI deallocator (from_raw pattern)
    fn registerRustDealloc(
        self: *SummaryPropagation,
        name: []const u8,
        param_count: usize,
    ) !void {
        var summary = try FunctionSummary.init(self.allocator, param_count);
        summary.is_deallocator = true;
        summary.markFreeParam(0);
        summary.confidence = 0.92;
        try self.summaries.put(name, summary);
    }

    /// Register JNI allocator
    fn registerJniAlloc(
        self: *SummaryPropagation,
        name: []const u8,
        param_count: usize,
    ) !void {
        var summary = try FunctionSummary.init(self.allocator, param_count);
        summary.returns_owned = true;
        summary.confidence = 0.90; // JNI leaks are almost always bugs
        try self.summaries.put(name, summary);
    }

    /// Register JNI deallocator
    fn registerJniDealloc(
        self: *SummaryPropagation,
        name: []const u8,
        param_count: usize,
        free_param_idx: usize,
    ) !void {
        var summary = try FunctionSummary.init(self.allocator, param_count);
        summary.is_deallocator = true;
        summary.markFreeParam(free_param_idx);
        summary.confidence = 0.95;
        try self.summaries.put(name, summary);
    }

    /// Register Go CGo allocator
    fn registerGoAlloc(
        self: *SummaryPropagation,
        name: []const u8,
        param_count: usize,
    ) !void {
        var summary = try FunctionSummary.init(self.allocator, param_count);
        summary.returns_owned = true;
        summary.may_escape = true; // Go defer may free later
        summary.confidence = 0.88;
        try self.summaries.put(name, summary);
    }

    /// Get current statistics
    pub fn getStats(self: *SummaryPropagation) PropagationStats {
        return self.stats;
    }

    /// Reset statistics (useful for batch processing)
    pub fn resetStats(self: *SummaryPropagation) void {
        self.stats.reset();
        self.analysis_cache.clearAndFree();
    }
};

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "summary propagation init and deinit" {
    const testing = std.testing;

    var engine = try SummaryPropagation.init(testing.allocator);
    defer engine.deinit();

    try testing.expectEqual(@as(usize, 0), engine.summaries.count());
}

test "load built-in summaries" {
    const testing = std.testing;

    var engine = try SummaryPropagation.init(testing.allocator);
    defer engine.deinit();

    try engine.loadBuiltins();

    // Should have loaded C, C++, Python, Rust, JNI, Go functions
    try testing.expect(engine.summaries.count() >= 30);

    // Verify specific functions exist
    try testing.expect(engine.summaries.contains("malloc"));
    try testing.expect(engine.summaries.contains("free"));
    try testing.expect(engine.summaries.contains("PyList_New"));
    try testing.expect(engine.summaries.contains("Py_DECREF"));
}

test "analyzeCall - ownership transferred" {
    const testing = std.testing;

    var engine = try SummaryPropagation.init(testing.allocator);
    defer engine.deinit();
    try engine.loadBuiltins();

    // Calling free(ptr) should indicate ownership transfer
    const result = engine.analyzeCall(0x1234, "free", 0);
    try testing.expectEqual(LeakAnalysisResult.ownership_transferred, result);
    try testing.expectEqual(@as(u32, 1), engine.stats.ownership_transfers_detected);
}

test "analyzeCall - possible leak" {
    const testing = std.testing;

    var engine = try SummaryPropagation.init(testing.allocator);
    defer engine.deinit();
    try engine.loadBuiltins();

    // malloc returns owned, but if not freed it's a possible leak
    const result = engine.analyzeCall(0x5678, "malloc", 0);
    // malloc doesn't free params, so this depends on context
    try testing.expect(LeakAnalysisResult.possible_leak == result or
        LeakAnalysisResult.no_alloc == result);
}

test "analyzeCall - unknown callee" {
    const testing = std.testing;

    var engine = try SummaryPropagation.init(testing.allocator);
    defer engine.deinit();
    try engine.loadBuiltins();

    // Unknown function should return conservative result
    const result = engine.analyzeCall(0x9999, "unknown_function_12345", 0);
    try testing.expectEqual(LeakAnalysisResult.unknown_callee, result);
}

test "cache hit optimization" {
    const testing = std.testing;

    var engine = try SummaryPropagation.init(testing.allocator);
    defer engine.deinit();
    try engine.loadBuiltins();

    // First call - cache miss
    _ = engine.analyzeCall(0x111, "free", 0);
    const stats_after_first = engine.getStats();

    // Second call - should hit cache
    _ = engine.analyzeCall(0x222, "free", 0);
    const stats_after_second = engine.getStats();

    // Cache hits should increase
    try testing.expect(stats_after_second.cache_hits > stats_after_first.cache_hits);
}

test "custom function registration" {
    const testing = std.testing;

    var engine = try SummaryPropagation.init(testing.allocator);
    defer engine.deinit();

    // Register custom allocator
    try engine.registerAllocator("my_custom_alloc", 1);
    try testing.expect(engine.summaries.contains("my_custom_alloc"));

    // Register custom deallocator
    try engine.registerDeallocator("my_custom_free", 1, 0);
    try testing.expect(engine.summaries.contains("my_custom_free"));

    // Test custom deallocator
    const result = engine.analyzeCall(0xABC, "my_custom_free", 0);
    try testing.expectEqual(LeakAnalysisResult.ownership_transferred, result);
}

test "statistics reset" {
    const testing = std.testing;

    var engine = try SummaryPropagation.init(testing.allocator);
    defer engine.deinit();
    try engine.loadBuiltins();

    // Perform some analysis
    _ = engine.analyzeCall(0x1, "free", 0);
    _ = engine.analyzeCall(0x2, "malloc", 0);
    _ = engine.analyzeCall(0x3, "unknown", 0);

    try testing.expect(engine.stats.total_calls_analyzed > 0);

    // Reset stats
    engine.resetStats();

    try testing.expectEqual(@as(u32, 0), engine.stats.total_calls_analyzed);
    try testing.expectEqual(@as(u32, 0), engine.stats.cache_hits);
}
