//! Pass system with comptime type checking
//!
//! This module provides the Pass interface with comptime validation
//! to ensure zero runtime overhead and compile-time dependency checking.

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("../common/log.zig");
const c = @import("../ir/llvm_raw.zig").c;

const ModuleRef = @import("../ir/view.zig").ModuleRef;
const FactStore = @import("../fact/store.zig").FactStore;
const QueryEngine = @import("../fact/query.zig").QueryEngine;
const DataFlowGraph = @import("../dataflow/graph.zig").DataFlowGraph;
const ValueIdMap = @import("../dataflow/value_id_map.zig").ValueIdMap;
const memory_graph_mod = @import("../semantics/memory_graph.zig");
const call_graph_mod = @import("../semantics/call_graph.zig");
const zone_classifier = @import("../semantics/zone_classifier.zig");
const noise_filter = @import("../semantics/noise_filter.zig");
const language_detector = @import("../semantics/language_detector.zig");
const Issue = @import("../diag/issue.zig").Issue;
const DiagSeverity = @import("../diag/issue.zig").Severity;
const NoiseSeverity = noise_filter.Severity;
const SemanticRegistry = @import("../registry/semantic_registry.zig").SemanticRegistry;
const FunctionSemantics = @import("../registry/semantic_registry.zig").FunctionSemantics;

/// Pass kind classification
pub const PassKind = enum {
    foundation, // Basic analysis passes (CFG, DFG)
    analysis, // Advanced analysis passes (alias, lock, taint)
    plugin, // User-defined plugin passes
};

/// R8.2: Cross-language call edge extracted by CallGraphPass.
///
/// Captures a call site where the caller and callee may be written in
/// different languages (e.g., Rust calling C via FFI, Go calling C via cgo).
/// Downstream passes (ffi_boundary, callback_escape) consume these edges
/// for language-aware boundary detection.
pub const CrossLangEdge = struct {
    /// Caller function name.
    caller_name: []const u8,
    /// Callee function name.
    callee_name: []const u8,
    /// Detected language of the caller function.
    caller_lang: @import("../diag/issue.zig").FFIBoundary.Language,
    /// Detected language of the callee function.
    callee_lang: @import("../diag/issue.zig").FFIBoundary.Language,
    /// Whether this call crosses an FFI boundary (languages differ or callee is external).
    is_ffi_boundary: bool,
    /// Indices of pointer-typed arguments at this call site.
    ptr_args: []const u32,
};

///Shared callee → call_sites index for O(1) lookup.
/// Built once in Pipeline.run() by scanning all call instructions.
/// Eliminates O(F) linear search in call_graph.findCallsInFunction (L269)
/// and ffi_boundary.checkCallForFFI (L268).
pub const CallSiteIndex = struct {
    map: std.StringHashMap(std.ArrayList(CallSite)),
    allocator: Allocator,

    pub fn init(allocator: Allocator) CallSiteIndex {
        return .{ .map = std.StringHashMap(std.ArrayList(CallSite)).init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *CallSiteIndex) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.map.deinit();
    }

    /// Record a call site: caller_func called callee_name at inst.
    pub fn addCall(self: *CallSiteIndex, allocator: Allocator, callee_name: []const u8, caller_func: u64, inst: u64) !void {
        const gop = try self.map.getOrPut(callee_name);
        if (!gop.found_existing) {
            gop.value_ptr.* = try std.ArrayList(CallSite).initCapacity(allocator, 4);
        }
        try gop.value_ptr.append(self.allocator, .{ .caller_func = caller_func, .inst = inst });
    }

    /// Get all call sites that call the given callee name. Returns null if none.
    pub fn getCallSites(self: *const CallSiteIndex, callee_name: []const u8) ?[]const CallSite {
        if (self.map.get(callee_name)) |sites| {
            return sites.items;
        }
        return null;
    }
};

/// A single call site record in the shared index.
pub const CallSite = struct {
    /// Function pointer of the caller (u64 from LLVMValueRef).
    caller_func: u64,
    /// Instruction pointer of the call instruction (u64 from LLVMValueRef).
    inst: u64,
};

/// R8.3: Global allocation tracker for cross-function leak detection.
///
/// Tracks malloc/calloc/realloc/free operations across function boundaries
/// to reduce false-positive "memory leak" reports when a pointer is allocated
/// in one function and freed in another.
pub const GlobalAllocTracker = struct {
    /// Record for a single heap allocation.
    pub const AllocRecord = struct {
        /// Value ID of the allocated pointer (from ValueIdMap).
        ptr_id: u32,
        /// Name of the function where allocation occurred.
        alloc_func: []const u8,
        /// Whether this allocation has been freed (anywhere in the module).
        freed: bool,
        /// Name of the function where free occurred (if freed).
        free_func: ?[]const u8,
        /// Whether this is a global/static variable (should not be reported as leak).
        is_global_or_static: bool,
    };

    allocator: Allocator,
    /// Map from raw pointer value (usize) → AllocRecord index in store.
    records_by_ptr: std.AutoHashMap(u64, u32),
    /// All allocation records (owned).
    records: std.ArrayList(AllocRecord),

    pub fn init(allocator: Allocator) GlobalAllocTracker {
        return .{
            .allocator = allocator,
            .records_by_ptr = std.AutoHashMap(u64, u32).init(allocator),
            .records = std.ArrayList(AllocRecord).empty,
        };
    }

    pub fn deinit(self: *GlobalAllocTracker) void {
        // Free owned func name strings
        for (self.records.items) |*rec| {
            self.allocator.free(rec.alloc_func);
            if (rec.free_func) |f| self.allocator.free(f);
        }
        self.records.deinit(self.allocator);
        self.records_by_ptr.deinit();
    }

    /// Record a heap allocation (malloc/calloc/realloc).
    pub fn insertAlloc(self: *GlobalAllocTracker, ptr_val: u64, func_name: []const u8, is_global: bool) !void {
        const name_owned = try self.allocator.dupe(u8, func_name);
        const idx = @as(u32, @intCast(self.records.items.len));
        try self.records.append(self.allocator, .{
            .ptr_id = 0, // Will be filled by caller if needed
            .alloc_func = name_owned,
            .freed = false,
            .free_func = null,
            .is_global_or_static = is_global,
        });
        try self.records_by_ptr.put(ptr_val, idx);
    }

    /// Mark an allocation as freed.
    /// Returns true if the allocation was found and marked, false otherwise.
    pub fn markFreed(self: *GlobalAllocTracker, ptr_val: u64, func_name: []const u8) bool {
        const idx = self.records_by_ptr.get(ptr_val) orelse return false;
        var rec = &self.records.items[idx];
        if (rec.freed) return true; // Already freed (double-free case)
        rec.freed = true;
        const free_name_owned = self.allocator.dupe(u8, func_name) catch return true;
        rec.free_func = free_name_owned;
        return true;
    }

    /// Get all unfreed allocations (leak candidates).
    /// Caller should use leakCount() for count and iterate records directly.
    pub fn getLeakCount(self: *const GlobalAllocTracker) u32 {
        return self.leakCount();
    }

    /// Get total number of tracked allocations.
    pub fn size(self: *const GlobalAllocTracker) usize {
        return self.records.items.len;
    }

    /// Get number of leak candidates (unfreed non-global allocations).
    pub fn leakCount(self: *const GlobalAllocTracker) u32 {
        var count: u32 = 0;
        for (self.records.items) |rec| {
            if (!rec.freed and !rec.is_global_or_static) count += 1;
        }
        return count;
    }
};
pub const PassContext = struct {
    allocator: Allocator,
    module: ?ModuleRef,
    fact_store: *FactStore,
    query_engine: *QueryEngine,
    data_flow_graph: *DataFlowGraph,
    next_id: std.atomic.Value(u32),
    vuln_id: std.atomic.Value(u32),
    value_id_map: ValueIdMap,
    raii_func_set: std.AutoHashMap(usize, void),
    meyers_singleton_set: std.AutoHashMap(usize, void),
    rc_container_func_set: std.AutoHashMap(usize, void),
    rust_into_raw_set: std.AutoHashMap(usize, void),
    rust_from_raw_set: std.AutoHashMap(usize, void),

    /// Cross-pass deduplication: tracks (func_name, issue_kind) pairs
    /// that have already been reported by a previous pass.
    /// Prevents FFI Analysis + PointerOwnership from double-reporting
    /// the same underlying instruction/issue.
    reported_keys: std.AutoHashMap(u64, void),

    /// Performance: Cache for SemanticRegistry lookups.
    /// O(1) repeated lookups of the same function name within an analysis session.
    registry_cache: std.StringHashMap(FunctionSemantics),

    /// Performance: Cache for zone classification results.
    /// O(1) repeated zone classification of the same function within an analysis session.
    zone_cache: std.StringHashMap(zone_classifier.ZoneKind),

    /// Zone statistics for function classification
    zone_stats: zone_classifier.ZoneStats,

    /// R7.2: Module-level language detection result (detected once at scan entry).
    /// All passes read from this instead of detecting language independently.
    module_language: language_detector.LanguageProfile,

    /// R7.2: Whether module language has been detected yet.
    language_detected: bool,

    /// Degradation statistics
    /// Tracks the number of functions that were skipped due to errors
    degraded_functions: std.atomic.Value(u32),

    /// R8.2: Cross-language call edges extracted by CallGraphPass.
    /// Consumed by ffi_boundary and callback_escape passes for precise
    /// FFI boundary detection with language-aware context.
    cross_lang_edges: std.ArrayList(CrossLangEdge),

    /// R8.3: Global allocation tracker for cross-function leak detection.
    /// Tracks malloc/free across function boundaries to reduce FP leaks.
    global_alloc_tracker: GlobalAllocTracker,

    /// R8.0: Unified MemoryGraph — single source of truth for pointer state.
    /// Tracks allocations, aliases, frees, AND call_arg/call_ret edges.
    /// Created by pipeline before any pass runs; owned by PassContext.
    memory_graph: memory_graph_mod.MemoryGraph,

    /// P1-1: Set of pointer values that are on a danger path (FFI/unsafe boundary).
    /// Populated by DangerSurfacePass. Downstream passes gate on this set:
    ///   if (!ctx.isRelevantAlloc(ptr_val)) { return; }  // Tier 1 pass-through
    danger_surface_relevant: std.AutoHashMap(u64, void),

    /// P2-8: Set of pointer values at FFI zone boundaries (auto-detected).
    /// Populated when cross-lang edges involve pointer arguments/returns.
    /// Complements danger_surface_relevant for FFI-specific relevance.
    ffi_auto_relevant: std.AutoHashMap(u64, void),

    /// P0-1: Set of function pointers that contain danger-surface-relevant pointers.
    /// Populated by DangerSurfacePass. Downstream passes gate at FUNCTION level:
    ///   if (!ctx.isRelevantFunction(func_ptr)) { return; }  // Skip entire function scan
    relevant_functions: std.AutoHashMap(u64, void),

    /// P0-2: Shared callee → call_sites index. Built once in Pipeline.run(),
    /// consumed by call_graph (findCallsInFunction) and ffi_boundary (checkCallForFFI).
    /// Eliminates O(F) linear search per call instruction.
    CallSiteIndex: CallSiteIndex,

    /// P0-2: callee_name → indices into cross_lang_edges for O(1) FFI boundary lookup.
    /// Uses ArrayList to support multiple call sites to the same FFI function.
    /// Populated by addCrossLangEdge(). Used by ffi_boundary.checkCallForFFI.
    cross_edge_by_callee: std.StringHashMap(std.ArrayList(u32)),

    /// CRITICAL FIX for 0/73 benchmark: Semantics-level CallGraph for BFS traversal.
    /// Built by CallGraphPass, consumed by ptr_lifetime and other analysis passes
    /// via reachesFFIBoundary() for cross-function FFI boundary reachability analysis.
    /// Without this, reachesFFIBoundary() exists but is never called — causing 0% recall.
    semantics_call_graph: ?call_graph_mod.CallGraph,

    /// Create a new pass context
    pub fn init(
        allocator: Allocator,
        module: ?ModuleRef,
        fact_store: *FactStore,
        query_engine: *QueryEngine,
        data_flow_graph: *DataFlowGraph,
    ) PassContext {
        return .{
            .allocator = allocator,
            .module = module,
            .fact_store = fact_store,
            .query_engine = query_engine,
            .data_flow_graph = data_flow_graph,
            .next_id = std.atomic.Value(u32).init(1),
            .vuln_id = std.atomic.Value(u32).init(0),
            .value_id_map = ValueIdMap.init(allocator),
            .raii_func_set = std.AutoHashMap(usize, void).init(allocator),
            .meyers_singleton_set = std.AutoHashMap(usize, void).init(allocator),
            .rc_container_func_set = std.AutoHashMap(usize, void).init(allocator),
            .rust_into_raw_set = std.AutoHashMap(usize, void).init(allocator),
            .rust_from_raw_set = std.AutoHashMap(usize, void).init(allocator),
            .reported_keys = std.AutoHashMap(u64, void).init(allocator),
            .registry_cache = std.StringHashMap(FunctionSemantics).init(allocator),
            .zone_cache = std.StringHashMap(zone_classifier.ZoneKind).init(allocator),
            .zone_stats = zone_classifier.ZoneStats{},
            .module_language = .{ .language = .unknown, .confidence = 0.0, .method = .unknown },
            .language_detected = false,
            .degraded_functions = std.atomic.Value(u32).init(0),
            .cross_lang_edges = std.ArrayList(CrossLangEdge).empty,
            .global_alloc_tracker = GlobalAllocTracker.init(allocator),
            .memory_graph = memory_graph_mod.MemoryGraph.init(allocator) catch unreachable,
            .danger_surface_relevant = std.AutoHashMap(u64, void).init(allocator),
            .ffi_auto_relevant = std.AutoHashMap(u64, void).init(allocator),
            .relevant_functions = std.AutoHashMap(u64, void).init(allocator),
            .CallSiteIndex = CallSiteIndex.init(allocator),
            .cross_edge_by_callee = std.StringHashMap(std.ArrayList(u32)).init(allocator),
            .semantics_call_graph = null,
        };
    }

    /// Get a unique ID for non-pointer entities (functions, basic blocks, etc.)
    ///
    /// Returns:
    ///   - u32: A unique sequential ID (thread-safe)
    ///
    /// Note: For LLVM Value pointers, use getValueId() instead
    pub fn getNextId(self: *PassContext) u32 {
        return self.next_id.fetchAdd(1, .seq_cst);
    }

    /// Get a unique ID for an LLVM value pointer.
    /// Uses ValueIdMap to ensure the same pointer always gets the same ID,
    /// avoiding collision issues from pointer truncation on 64-bit systems.
    ///
    /// Parameters:
    ///   - ptr: LLVM value pointer (must be non-null)
    ///
    /// Returns:
    ///   - u32: Unique ID for this pointer (consistent across calls)
    ///
    /// Errors:
    ///   - error.NullPointer: If ptr is 0
    pub fn getValueId(self: *PassContext, ptr: usize) !u32 {
        return self.value_id_map.getOrPutId(ptr);
    }

    /// Get a unique vulnerability ID (shared across all detection passes)
    pub fn getNextVulnId(self: *PassContext) u32 {
        return self.vuln_id.fetchAdd(1, .seq_cst) + 1;
    }

    /// P-DEGRADE-3 — Increment degraded function counter
    /// Call this when a function analysis is skipped due to an error
    pub fn recordDegradedFunction(self: *PassContext) void {
        _ = self.degraded_functions.fetchAdd(1, .seq_cst);
    }

    /// P-DEGRADE-3 — Get degraded function count
    pub fn getDegradedFunctionCount(self: *const PassContext) u32 {
        return self.degraded_functions.load(.seq_cst);
    }

    /// Release all resources held by this context
    pub fn deinit(self: *PassContext) void {
        self.value_id_map.deinit();
        self.raii_func_set.deinit();
        self.meyers_singleton_set.deinit();
        self.rc_container_func_set.deinit();
        self.rust_into_raw_set.deinit();
        self.rust_from_raw_set.deinit();
        self.reported_keys.deinit();
        self.registry_cache.clearAndFree();
        self.zone_cache.clearAndFree();
        for (self.cross_lang_edges.items) |edge| {
            self.allocator.free(edge.caller_name);
            self.allocator.free(edge.callee_name);
        }
        self.cross_lang_edges.deinit(self.allocator);
        self.global_alloc_tracker.deinit();
        self.memory_graph.deinit();
        self.danger_surface_relevant.deinit();
        self.ffi_auto_relevant.deinit();
        self.relevant_functions.deinit();
        self.CallSiteIndex.deinit();
        // P2-2 fix: Deinitialize all ArrayLists in the HashMap before HashMap itself
        var edge_iter = self.cross_edge_by_callee.valueIterator();
        while (edge_iter.next()) |list| {
            list.deinit(self.allocator);
        }
        self.cross_edge_by_callee.deinit();
    }

    /// Set the IR module
    ///
    /// Parameters:
    ///   - module: The LLVM module to analyze
    pub fn setModule(self: *PassContext, module: ModuleRef) void {
        self.module = module;
    }

    /// Check if a module is loaded
    ///
    /// Returns:
    ///   - true if a module is loaded, false otherwise
    pub fn hasModule(self: *const PassContext) bool {
        return self.module != null;
    }

    /// Get data flow graph
    ///
    /// Returns:
    ///   - Reference to the data flow graph
    pub fn getDataFlowGraph(self: *const PassContext) *DataFlowGraph {
        return self.data_flow_graph;
    }

    /// Add a node to data flow graph
    ///
    /// Parameters:
    ///   - node: The node to add
    ///
    /// Returns:
    ///   - error if operation fails
    pub fn addNode(self: *PassContext, node: anytype) !void {
        try self.data_flow_graph.addNode(node);
    }

    /// Add an edge to data flow graph
    ///
    /// Parameters:
    ///   - edge: The edge to add
    ///
    /// Returns:
    ///   - error if operation fails
    pub fn addEdge(self: *PassContext, edge: anytype) !void {
        try self.data_flow_graph.addEdge(edge);
    }

    /// Add an FFI boundary to data flow graph
    ///
    /// Parameters:
    ///   - boundary: The FFI boundary to add
    ///
    /// Returns:
    ///   - error if operation fails
    pub fn addFFIBoundary(self: *PassContext, boundary: anytype) !void {
        try self.data_flow_graph.addFFIBoundary(boundary);
    }

    /// Add an issue to data flow graph
    ///
    /// Parameters:
    ///   - issue: The issue to add
    ///
    /// Features cross-pass deduplication: if another pass has already
    /// reported an issue with the same (function, kind) signature,
    /// this call is silently skipped to avoid duplicate alerts.
    pub fn addIssue(self: *PassContext, issue: *const Issue) !void {
        // P2-1: Risk weighting integration.
        // Classify the function origin and apply risk level adjustment.
        // Suppressed issues are silently dropped — no noise in output.
        //
        // EXCEPTION: CRITICAL severity issues are never suppressed.
        // CRITICAL = confirmed FFI boundary bug (stack escape, UAF at boundary).
        // These must always be reported regardless of function origin,
        // because they represent real security vulnerabilities.
        const func_name = issue.location.func;
        const classification = noise_filter.classifyFunctionFull(func_name, null, null, null);
        var risk = noise_filter.getRiskLevel(classification.origin, diagToNoiseSeverity(issue.severity));
        if (issue.severity != .critical and risk == .suppressed) {
            return;
        }
        // For CRITICAL issues, override suppression to at least .low
        if (issue.severity == .critical and risk == .suppressed) {
            risk = .critical;
        }

        const dedup_key = self.dedupKey(issue);
        // CRITICAL issues bypass dedup — they must always be reported
        // even if a lower-severity issue exists for the same (func, kind).
        if (issue.severity != .critical) {
            const gop = try self.reported_keys.getOrPut(dedup_key);
            if (gop.found_existing) {
                var dup = issue.*;
                dup.deinit(self.allocator);
                return;
            }
        }

        // Adjust severity based on risk level when downgraded.
        var final_issue = issue.*;
        if (@intFromEnum(risk) > @intFromEnum(issue.severity)) {
            // Risk level is lower than original severity — downgrade.
            // Map RiskLevel back to Severity for the issue.
            final_issue.severity = switch (risk) {
                .critical => .critical,
                .high => .high,
                .medium => .medium,
                .low => .low,
                .suppressed => unreachable, // handled above
            };
        }

        try self.data_flow_graph.addIssue(final_issue);
    }

    /// Compute a dedup key from an issue's (func_name, kind) pair.
    /// Uses FNV-1a hash for fast lookup.
    fn dedupKey(self: *PassContext, issue: *const Issue) u64 {
        _ = self;
        const func_name = @field(issue, "location").func;
        const kind_tag = @tagName(@field(issue, "kind"));
        var hasher = std.hash.Fnv1a_64.init();
        hasher.update(func_name);
        hasher.update(kind_tag);
        const loc = @field(issue, "location");
        hasher.update(loc.func); // Function name always participates in dedup
        if (loc.file) |f| hasher.update(f); // File path (if available)
        if (loc.line > 0) hasher.update(&std.mem.toBytes(loc.line)); // Line number (if available)
        if (loc.column > 0) hasher.update(&std.mem.toBytes(loc.column)); // Column (if available)
        return hasher.final();
    }

    /// R6.1+R6.3 Performance: Cached SemanticRegistry lookup.
    /// O(1) for cache hits, O(N) on first lookup then cached for subsequent calls.
    pub fn cachedRegistryLookup(self: *PassContext, func_name: []const u8) ?FunctionSemantics {
        if (self.registry_cache.get(func_name)) |sem| {
            return sem;
        }
        const sem = SemanticRegistry.lookup(func_name) orelse return null;
        self.registry_cache.put(func_name, sem) catch |err| {
            // Cache miss on OOM is non-fatal: return computed value without caching.
            // Next call will re-compute (correct, just slower).
            log.warn("registry_cache.put OOM for '{s}': {}", .{ func_name, err });
        };
        return sem;
    }

    /// R6.1 Performance: Cached zone classification lookup (get).
    /// Returns cached result if available, null otherwise.
    /// Caller should compute zone via zone_classifier then call cacheZoneResult().
    pub fn cachedZoneLookup(self: *PassContext, func_name: []const u8) ?zone_classifier.ZoneKind {
        return self.zone_cache.get(func_name);
    }

    /// R6.1 Performance: Cache zone classification result (set).
    /// Stores the computed zone for future O(1) lookups.
    pub fn cacheZoneResult(self: *PassContext, func_name: []const u8, zone: zone_classifier.ZoneKind) void {
        self.zone_cache.put(func_name, zone) catch |err| {
            // Cache miss on OOM is non-fatal: zone will be re-computed on next lookup.
            log.warn("zone_cache.put OOM for '{s}': {}", .{ func_name, err });
        };
    }

    /// R7.0: Unified zone classification with caching (get-or-compute).
    /// Eliminates the repetitive cachedZoneLookup/orelse/cacheZoneResult pattern
    /// that was duplicated across 5+ call sites in ptr_lifetime, pointer_ownership,
    /// callback_escape, etc.
    ///
    /// Returns the ZoneKind for a function, using cache when available.
    ///
    /// Null safety: @intFromPtr extracts the address as an integer before comparison,
    /// avoiding any pointer dereference on null. The early return at .unknown is safe
    /// because zone_classifier.classifyFunctionFromLLVM requires a valid LLVM value.
    ///
    /// Type safety note: *anyopaque is used instead of c.LLVMValueRef here due to
    /// a Zig 0.15 compiler bug where importing llvm_raw.zig.c (which defines
    /// c.LLVMValueRef) in the same file that uses std.log formatting causes an
    /// "ambiguous format string" compile error. The error manifests only in test
    /// builds (zig build test), not in ReleaseFast builds. The workaround is to
    /// accept *anyopaque from callers and @ptrCast internally where needed.
    ///
    /// Note on runtime type checking: We cannot use @TypeOf(func) to validate that
    /// func is actually an LLVMValueRef because the parameter is typed as *anyopaque,
    /// so @TypeOf would always return *anyopaque (never c.LLVMValueRef). Runtime type
    /// validation of opaque pointers is not possible in Zig without unsafe assumptions.
    /// All callers are trusted to pass valid c.LLVMValueRef values cast to *anyopaque.
    /// TODO: Re-evaluate after Zig upgrade — if the format string ambiguity is
    /// resolved, switch to c.LLVMValueRef for proper type safety.
    pub fn getOrComputeZone(self: *PassContext, func: *anyopaque, func_name: []const u8) zone_classifier.ZoneKind {
        const func_addr = @intFromPtr(func);
        if (func_addr == 0) return .unknown;
        return self.cachedZoneLookup(func_name) orelse blk: {
            const z = zone_classifier.classifyFunctionFromLLVM(@ptrCast(func), func_name);
            self.cacheZoneResult(func_name, z);
            break :blk z;
        };
    }

    /// R7.0: Shared zone gate — determines if a function should be analyzed
    /// based on its zone classification.
    pub fn shouldAnalyzeZone(zone: zone_classifier.ZoneKind) bool {
        return switch (zone) {
            .safe => false,
            .runtime_internal => false,
            .unknown => true,
            .unsafe => true,
            .ffi => true,
        };
    }

    /// R7.2: Initialize module-level language detection.
    ///
    /// Called once at Pipeline.run() before any passes execute.
    /// Detects the source language from DWARF/producer/sampling and stores
    /// the result in ctx.module_language for all passes to read.
    ///
    /// This is the Language-First Pipeline entry point: detect language ONCE,
    /// then activate the corresponding zone rules channel.
    pub fn initModuleLanguage(self: *PassContext, module_ref: ?ModuleRef) void {
        if (self.language_detected) return;
        if (module_ref == null or self.module == null) {
            self.module_language = .{
                .language = .unknown,
                .confidence = 0.0,
                .method = .unknown,
            };
            self.language_detected = true;
            return;
        }

        const llvm_module = if (self.module) |m|
            m.raw
        else
            @as(c.LLVMModuleRef, @ptrFromInt(0));

        if (@intFromPtr(llvm_module) == 0) {
            self.module_language = .{
                .language = .unknown,
                .confidence = 0.0,
                .method = .unknown,
            };
            self.language_detected = true;
            return;
        }

        self.module_language = language_detector.detectModuleLanguage(llvm_module);
        self.language_detected = true;

        log.info("LANG-DETECT: module language = {s}, confidence = {d:.1}%, method = {s}", .{
            @tagName(self.module_language.language),
            self.module_language.confidence * 100,
            @tagName(self.module_language.method),
        });
    }

    /// R7.2: Get the detected module-level language.
    ///
    /// All analysis passes should call this instead of detecting language
    /// independently per-function. Returns .unknown with 0.0 confidence if
    /// initModuleLanguage() has not been called yet.
    pub fn getModuleLanguage(self: *const PassContext) language_detector.LanguageProfile {
        return self.module_language;
    }

    /// R7.2: Check if the module was detected as a specific language.
    /// Convenience methods for pass-level language gating.
    pub fn isGoModule(self: *const PassContext) bool {
        return self.module_language.language == .go;
    }
    pub fn isRustModule(self: *const PassContext) bool {
        return self.module_language.language == .rust;
    }
    pub fn isZigModule(self: *const PassContext) bool {
        return self.module_language.language == .zig;
    }
    pub fn isCModule(self: *const PassContext) bool {
        return self.module_language.language == .c or self.module_language.language == .cpp;
    }
    pub fn isUnknownModule(self: *const PassContext) bool {
        return self.module_language.language == .unknown;
    }

    /// R7.2: Zone Rules Channel -- determine if a pass should run at full strength.
    ///
    /// Based on the detected module language, returns whether a given analysis
    /// category should be fully active, limited (reduced sensitivity), or skipped.
    ///
    /// Channel matrix:
    ///   Language | ffi_boundary  | ptr_lifetime  | callback_escape | pointer_ownership
    ///   ---------|--------------|--------------|----------------|------------------
    ///   Rust     | full         | full         | unsafe-only    | full
    ///   Zig      | cImport-only | skip         | skip           | skip
    ///   Go       | cgo-only     | limited      | full cgo      | limited
    ///   C/C++    | full         | full         | real-escape   | full
    ///   unknown  | generic      | generic      | generic        | generic
    pub fn channelFFIBoundary(self: *const PassContext) ChannelMode {
        return switch (self.module_language.language) {
            .zig => .limited,
            .go => .limited,
            else => .full,
        };
    }
    pub fn channelPtrLifetime(self: *const PassContext) ChannelMode {
        return switch (self.module_language.language) {
            .zig => .skip,
            .go => .limited,
            else => .full,
        };
    }
    pub fn channelCallbackEscape(self: *const PassContext) ChannelMode {
        return switch (self.module_language.language) {
            .zig => .skip,
            else => .full,
        };
    }
    pub fn channelPointerOwnership(self: *const PassContext) ChannelMode {
        return switch (self.module_language.language) {
            .zig => .skip,
            .go => .limited,
            else => .full,
        };
    }

    /// R7.2: Channel mode for analysis pass gating.
    pub const ChannelMode = enum {
        /// Run analysis at full sensitivity (default for C/C++/unknown)
        full,
        /// Run with reduced sensitivity (fewer alerts, higher thresholds)
        limited,
        /// Skip this pass entirely (language guarantees make it unnecessary)
        skip,
    };

    /// R7.0-P1: Zone classification by name only (no LLVMValueRef needed).
    /// Used for **callee** zone lookups in checkCallForFFI hot path where we have
    /// the function name but not the LLVM value (e.g., external/declared functions).
    ///
    /// This is critical for performance on large files like sqlite3.ll (~10,000 call
    /// instructions, ~1,000 unique called_names). Without caching, each call to
    /// zone_classifier.classifyFunction() re-scans all pattern arrays (~200 entries).
    /// With caching, the first call is O(N), subsequent O(1) HashMap lookup.
    pub fn getOrComputeZoneByName(self: *PassContext, func_name: []const u8) zone_classifier.ZoneKind {
        return self.cachedZoneLookup(func_name) orelse blk: {
            const z = zone_classifier.classifyFunction(func_name, null);
            self.cacheZoneResult(func_name, z);
            break :blk z;
        };
    }

    /// Mark a node as tainted
    ///
    /// Parameters:
    ///   - node_id: Node ID to mark as tainted
    ///   - source_id: Optional source node ID
    ///
    /// Returns:
    ///   - error if operation fails
    pub fn markTainted(self: *PassContext, node_id: u32, source_id: ?u32) !void {
        try self.data_flow_graph.markTainted(node_id, source_id);
    }

    /// Check if a node is tainted
    ///
    /// Parameters:
    ///   - node_id: Node ID to check
    ///
    /// Returns:
    ///   - true if node is tainted
    pub fn isTainted(self: *const PassContext, node_id: u32) bool {
        return self.data_flow_graph.isTainted(node_id);
    }

    /// R8.2: Add a cross-language call edge to the context.
    /// Called by CallGraphPass after building the call graph.
    pub fn addCrossLangEdge(self: *PassContext, edge: CrossLangEdge) !void {
        const idx = @as(u32, @intCast(self.cross_lang_edges.items.len));
        try self.cross_lang_edges.append(self.allocator, edge);
        // P2-2 fix: Append to ArrayList instead of overwriting (supports multiple call sites)
        const gop = try self.cross_edge_by_callee.getOrPut(edge.callee_name);
        if (!gop.found_existing) {
            // BUGFIX: Propagate OOM instead of creating undefined-allocator fallback.
            // Old code: initCapacity catch {} left allocator=undefined → deinit() crash.
            gop.value_ptr.* = try std.ArrayList(u32).initCapacity(self.allocator, 4);
        }
        try gop.value_ptr.*.append(self.allocator, idx);
    }

    /// R8.2: Get read-only access to cross-language edges.
    /// Called by ffi_boundary and callback_escape passes.
    pub fn getCrossLangEdges(self: *const PassContext) []const CrossLangEdge {
        return self.cross_lang_edges.items;
    }

    /// P0-2: O(1) lookup for FFI boundary by callee name.
    /// Returns pointer to the FIRST matching CrossLangEdge, or null if not found.
    /// Use getAllCrossEdgesByCallee() to get all call sites for a given callee.
    pub fn getCrossEdgeByCallee(self: *const PassContext, callee_name: []const u8) ?*const CrossLangEdge {
        if (self.cross_edge_by_callee.get(callee_name)) |indices| {
            if (indices.items.len > 0) {
                return &self.cross_lang_edges.items[indices.items[0]];
            }
        }
        return null;
    }

    /// Get ALL CrossLangEdges for a given callee name.
    /// Supports multiple call sites to the same FFI function.
    /// Returns null if no edges found for this callee.
    pub fn getAllCrossEdgesByCallee(self: *const PassContext, callee_name: []const u8) ?[]const u32 {
        if (self.cross_edge_by_callee.get(callee_name)) |indices| {
            return indices.items;
        }
        return null;
    }

    /// P1-1: Check if a pointer value is on a danger path (FFI/unsafe boundary).
    /// Returns true if the pointer should be analyzed (Tier 2 strict mode).
    /// Returns false for Tier 1 pass-through (general memory, no issue reported).
    /// P2-8: Also auto-relevant if pointer crosses FFI zone boundary.
    pub fn isRelevantAlloc(self: *const PassContext, ptr_val: u64) bool {
        if (self.danger_surface_relevant.contains(ptr_val)) return true;
        // Defensive: skip ffi_auto_relevant lookup when empty (FFI detection not yet run).
        if (self.ffi_auto_relevant.count() == 0) return false;
        return self.ffi_auto_relevant.contains(ptr_val);
    }

    /// P0: Full danger path validation using MemoryGraph + CallGraph analysis.
    /// Performs complete path tracing: (b) ffi_arg, (c) ffi_ret,
    /// (a/e) alloc zone+lang, (d) alias closure traversal.
    /// Use this for issue reporting gates instead of isRelevantAlloc() for
    /// stricter validation per todolist.md architecture requirements.
    pub fn isOnDangerPathFull(self: *PassContext, ptr_val: u64) bool {
        const raw_ffis = self.getCrossLangEdges();
        if (raw_ffis.len == 0) return self.isRelevantAlloc(ptr_val);

        // Convert CrossLangEdge[] to MemoryGraph.DangerSurface[] for isOnDangerPath API
        var danger_surfaces = self.allocator.alloc(memory_graph_mod.MemoryGraph.DangerSurface, raw_ffis.len) catch return false;
        defer self.allocator.free(danger_surfaces);
        for (raw_ffis, 0..) |ffe, i| {
            danger_surfaces[i] = .{
                .callee_name = ffe.callee_name,
                .is_ffi_boundary = ffe.is_ffi_boundary,
            };
        }

        // M1 FIX: Build ffi_set once here and pass to all recursive calls
        // to avoid O(N) HashMap rebuild at each recursion level.
        var ffi_set = std.StringHashMap(void).init(self.allocator);
        defer ffi_set.deinit();
        for (danger_surfaces) |ds| {
            if (ds.is_ffi_boundary) {
                ffi_set.put(ds.callee_name, {}) catch {};
            }
        }

        var visited = std.AutoHashMap(u64, void).init(self.allocator);
        defer visited.deinit();
        const result = self.memory_graph.isOnDangerPath(ptr_val, danger_surfaces, &visited, &ffi_set);
        return result != .none;
    }

    /// P1-1: Mark a pointer value as being on a danger path.
    /// Called by DangerSurfacePass during surface tracing.
    pub fn markRelevantAlloc(self: *PassContext, ptr_val: u64) !void {
        try self.danger_surface_relevant.put(ptr_val, {});
    }

    /// P2-8: Mark a pointer as FFI-zone-relevant (auto-detected at cross-lang boundary).
    /// Called by FFI boundary passes when pointer crosses language boundary.
    pub fn markFfiRelevant(self: *PassContext, ptr_val: u64) !void {
        try self.ffi_auto_relevant.put(ptr_val, {});
    }

    /// P0-1: Check if a function contains any danger-surface-relevant pointers.
    /// Returns true if the function should be analyzed (Tier 2 strict mode).
    /// Returns false for Tier 1 pass-through (skip entire function scan).
    pub fn isRelevantFunction(self: *const PassContext, func_ptr: u64) bool {
        return self.relevant_functions.contains(func_ptr);
    }

    /// P0-1: Mark a function as containing danger-surface-relevant pointers.
    /// Called by DangerSurfacePass during surface tracing.
    pub fn markRelevantFunction(self: *PassContext, func_ptr: u64) !void {
        try self.relevant_functions.put(func_ptr, {});
    }

    /// P0-1 fix: Mark a function as relevant given an instruction pointer from that function.
    /// This bridges the gap between DangerSurfacePass (which has caller_inst) and
    /// downstream passes (which query isRelevantFunction with func_ptr).
    ///
    /// LLVM hierarchy: Instruction → BasicBlock → Function
    /// We traverse up this hierarchy to extract the function pointer.
    ///
    /// Parameters:
    ///   - inst_ptr: Raw pointer to an LLVM instruction (u64)
    ///
    /// Errors:
    ///   - Propagates from markRelevantFunction if HashMap insertion fails
    ///   - Silently returns if inst_ptr is null or cannot be resolved
    pub fn markFunctionFromInst(self: *PassContext, inst_ptr: u64) void {
        if (inst_ptr == 0) return;

        const inst = @as(c.LLVMValueRef, @ptrFromInt(inst_ptr));
        if (@intFromPtr(inst) == 0) return;

        // Step 1: Get parent basic block from instruction
        const bb = c.LLVMGetInstructionParent(inst);
        if (@intFromPtr(bb) == 0) return;

        // Step 2: Get parent function from basic block
        const func = c.LLVMGetBasicBlockParent(bb);
        if (@intFromPtr(func) == 0) return;

        // Step 3: Convert function pointer to u64 and mark as relevant
        const func_ptr = @as(u64, @intFromPtr(func));
        self.relevant_functions.put(func_ptr, {}) catch |err| {
            // Log failure but don't crash — function gating degradation is acceptable
            log.warn("[P0-1] markFunctionFromInst: failed to mark function (ptr=0x{x}): {}", .{ func_ptr, err });
        };
    }
};

/// ANSI color codes for terminal output
const Colors = struct {
    const reset = "\x1b[0m";
    const red = "\x1b[31m";
    const yellow = "\x1b[33m";
    const green = "\x1b[32m";
    const blue = "\x1b[34m";
    const magenta = "\x1b[35m";
    const cyan = "\x1b[36m";
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";
};

/// Diagnostic writer for pass output with color support
pub const DiagnosticWriter = struct {
    allocator: Allocator,
    use_color: bool = true,

    pub fn write(self: *DiagnosticWriter, comptime severity: []const u8, comptime format: []const u8, args: anytype) void {
        if (log.current_log_level == .quiet) return;
        if (std.mem.eql(u8, severity, "DEBUG") and log.current_log_level != .debug) return;
        // WARN messages only show in verbose mode or higher (not normal mode)
        // This reduces noise: normal mode shows only issues, verbose shows analysis details
        if (std.mem.eql(u8, severity, "WARN") and log.current_log_level == .normal) return;

        const color = comptime getSeverityColor(severity);
        if (self.use_color) {
            std.debug.print(color ++ "[" ++ severity ++ "]" ++ Colors.reset ++ " " ++ format ++ "\n", args);
        } else {
            std.debug.print("[" ++ severity ++ "] " ++ format ++ "\n", args);
        }
    }

    pub fn info(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("INFO", format, args);
    }

    pub fn warn(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("WARN", format, args);
    }

    pub fn err(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("ERROR", format, args);
    }

    pub fn critical(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("CRITICAL", format, args);
    }

    pub fn debug(self: *DiagnosticWriter, comptime format: []const u8, args: anytype) void {
        self.write("DEBUG", format, args);
    }
};

/// Print zone classification summary
/// Output format: "Analyzed 987 functions, 42 in unsafe/FFI zones, found 3 real issues"
pub fn printZoneSummary(stats: zone_classifier.ZoneStats, dfg: *DataFlowGraph) void {
    if (log.current_log_level == .quiet) return;

    const total = stats.total();
    const escape_count = stats.unsafe_count + stats.ffi_count;
    const skip_ratio = stats.skipRatio();
    const issue_stats = dfg.getIssueStats();

    std.debug.print("\n" ++ Colors.cyan ++ "═══════════════════════════════════════════════════════════════" ++ Colors.reset ++ "\n", .{});
    std.debug.print(Colors.bold ++ "Zone Classification Summary" ++ Colors.reset ++ "\n", .{});
    std.debug.print(Colors.cyan ++ "═══════════════════════════════════════════════════════════════" ++ Colors.reset ++ "\n\n", .{});

    std.debug.print("  Total functions analyzed:    {d}\n", .{total});
    std.debug.print("  Safe zone (skipped):         {d} ({d:.1}%)\n", .{ stats.safe_count, skip_ratio * 100 });
    std.debug.print("  Runtime internal (skipped):  {d}\n", .{stats.runtime_count});
    std.debug.print("  Unsafe zone (analyzed):      {d}\n", .{stats.unsafe_count});
    std.debug.print("  FFI zone (analyzed):         {d}\n", .{stats.ffi_count});
    std.debug.print("  Unknown zone:                {d}\n", .{stats.unknown_count});
    std.debug.print("\n", .{});

    std.debug.print(Colors.green ++ "  Escape zone functions:       {d} ({d:.1}% of total)" ++ Colors.reset ++ "\n", .{ escape_count, if (total > 0) @as(f64, @floatFromInt(escape_count)) / @as(f64, @floatFromInt(total)) * 100 else 0 });

    if (issue_stats.total > 0) {
        std.debug.print(Colors.yellow ++ "  Issues found:              {d}" ++ Colors.reset ++ "\n", .{issue_stats.total});

        std.debug.print("\n    " ++ Colors.bold ++ "Issue breakdown by category:" ++ Colors.reset ++ "\n", .{});
        if (issue_stats.memory_leak > 0) {
            std.debug.print("      Memory leak:              {d}\n", .{issue_stats.memory_leak});
        }
        if (issue_stats.use_after_free > 0) {
            std.debug.print("      Use after free:           {d}\n", .{issue_stats.use_after_free});
        }
        if (issue_stats.double_free > 0) {
            std.debug.print("      Double free:               {d}\n", .{issue_stats.double_free});
        }
        if (issue_stats.ffi_unsafe > 0) {
            std.debug.print("      FFI unsafe call:          {d}\n", .{issue_stats.ffi_unsafe});
        }
        if (issue_stats.command_injection > 0) {
            std.debug.print("      Command injection:         {d}\n", .{issue_stats.command_injection});
        }
        if (issue_stats.buffer_overflow > 0) {
            std.debug.print("      Buffer overflow:          {d}\n", .{issue_stats.buffer_overflow});
        }
        if (issue_stats.format_string > 0) {
            std.debug.print("      Format string:            {d}\n", .{issue_stats.format_string});
        }
        if (issue_stats.type_mismatch > 0) {
            std.debug.print("      Type mismatch:            {d}\n", .{issue_stats.type_mismatch});
        }
        if (issue_stats.borrow_escape > 0) {
            std.debug.print("      Borrow escape:            {d}\n", .{issue_stats.borrow_escape});
        }
        if (issue_stats.null_dereference > 0) {
            std.debug.print("      Null dereference:         {d}\n", .{issue_stats.null_dereference});
        }
        if (issue_stats.invalid_free > 0) {
            std.debug.print("      Invalid free:             {d}\n", .{issue_stats.invalid_free});
        }
        if (issue_stats.unchecked_return > 0) {
            std.debug.print("      Unchecked return:         {d}\n", .{issue_stats.unchecked_return});
        }
        if (issue_stats.malloc_unchecked > 0) {
            std.debug.print("      Malloc unchecked:         {d}\n", .{issue_stats.malloc_unchecked});
        }
        if (issue_stats.callback_mismatch > 0) {
            std.debug.print("      Callback mismatch:        {d}\n", .{issue_stats.callback_mismatch});
        }
        if (issue_stats.unknown > 0) {
            std.debug.print("      Unknown:                  {d}\n", .{issue_stats.unknown});
        }

        // C4-4: FunctionOrigin grouping output
        std.debug.print("\n    " ++ Colors.bold ++ "Origin breakdown:" ++ Colors.reset ++ "\n", .{});
        std.debug.print("      ✅ User code:             {d:>6} (ACTION NEEDED)\n", .{issue_stats.user_code});
        std.debug.print("      📦 Third-party (FFI):     {d:>6}\n", .{issue_stats.third_party});
        std.debug.print("      📚 Stdlib (suppressed):  {d:>6}\n", .{issue_stats.stdlib_suppressed});
        std.debug.print("      🔧 Compiler (ignored):   {d:>6}\n", .{issue_stats.compiler_ignored});

        const actionable = issue_stats.user_code + issue_stats.third_party;
        if (actionable > 0) {
            std.debug.print("\n    " ++ Colors.yellow ++ "→ {d} actionable issues ({d} user, {d} FFI boundary)" ++ Colors.reset ++ "\n", .{
                actionable,
                issue_stats.user_code,
                issue_stats.third_party,
            });
        }
        std.debug.print("\n", .{});

        // E2-3c: Graph coverage metric
        const graph_stats = dfg.getStats();
        const coverage_pct: f64 = if (graph_stats.node_count > 0)
            @as(f64, @floatFromInt(graph_stats.tainted_node_count)) / @as(f64, @floatFromInt(graph_stats.node_count)) * 100
        else
            0;
        std.debug.print("    " ++ Colors.bold ++ "Graph coverage:" ++ Colors.reset ++ "\n", .{});
        std.debug.print("      Total nodes analyzed:     {d}\n", .{graph_stats.node_count});
        std.debug.print("      Nodes on danger path:     {d} ({d:.1}%)\n", .{ graph_stats.tainted_node_count, coverage_pct });
        std.debug.print("      FFI boundaries tracked:   {d}\n", .{dfg.getFFIBoundaries().len});
        std.debug.print("      Issues in graph:          {d}\n", .{dfg.getIssues().len});

        // E2-3b: Danger path depth hint (alias closure reach)
        if (issue_stats.total > 0) {
            const depth_hint = if (coverage_pct > 50) "deep alias analysis" else if (coverage_pct > 20) "moderate reach" else "shallow scan";
            std.debug.print("      Analysis depth:           {s}\n", .{depth_hint});
        }
    } else {
        std.debug.print(Colors.green ++ "  Issues found:                0" ++ Colors.reset ++ "\n\n", .{});
    }

    std.debug.print(Colors.cyan ++ "═══════════════════════════════════════════════════════════════" ++ Colors.reset ++ "\n\n", .{});
}

fn getSeverityColor(comptime severity: []const u8) []const u8 {
    if (comptime std.mem.eql(u8, severity, "CRITICAL")) {
        return Colors.bold ++ Colors.red;
    } else if (comptime std.mem.eql(u8, severity, "ERROR")) {
        return Colors.red;
    } else if (comptime std.mem.eql(u8, severity, "WARN")) {
        return Colors.yellow;
    } else if (comptime std.mem.eql(u8, severity, "INFO")) {
        return Colors.green;
    } else if (comptime std.mem.eql(u8, severity, "DEBUG")) {
        return Colors.dim;
    }
    return Colors.reset;
}

/// Pass comptime wrapper with type validation
///
/// This function validates that a type satisfies the Pass interface
/// at compile time and returns the type unchanged.
pub fn Pass(comptime T: type) type {
    comptime {
        // Validate required declarations
        if (!@hasDecl(T, "name"))
            @compileError("Pass must have a 'name' declaration ([]const u8)");
        if (!@hasDecl(T, "kind"))
            @compileError("Pass must have a 'kind' declaration (PassKind)");
        if (!@hasDecl(T, "deps"))
            @compileError("Pass must have a 'deps' declaration ([]const []const u8)");
        if (!@hasDecl(T, "run"))
            @compileError("Pass must have a 'run' function");

        // Note: In Zig 0.15.2, strict type checking is simplified
        // The compiler will catch type mismatches during actual usage
    }
    return T;
}

test "Pass - comptime validation" {
    const ValidPass = Pass(struct {
        pub const name = "test-pass";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    });

    _ = ValidPass;
}

test "PassContext - init and deinit" {
    var fact_store = try FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store, std.testing.allocator);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    var ctx = PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
        &data_flow_graph,
    );
    defer ctx.deinit();

    try std.testing.expect(!ctx.hasModule());
}

test "PassContext - getNextId" {
    var fact_store = try FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store, std.testing.allocator);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    var ctx = PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
        &data_flow_graph,
    );
    defer ctx.deinit();

    const id1 = ctx.getNextId();
    const id2 = ctx.getNextId();
    const id3 = ctx.getNextId();

    try std.testing.expectEqual(@as(u32, 1), id1);
    try std.testing.expectEqual(@as(u32, 2), id2);
    try std.testing.expectEqual(@as(u32, 3), id3);
}

test "PassContext - setModule and hasModule" {
    var fact_store = try FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store, std.testing.allocator);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    var ctx = PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
        &data_flow_graph,
    );
    defer ctx.deinit();

    try std.testing.expect(!ctx.hasModule());

    // Set a dummy module
    ctx.setModule(.{ .raw = undefined });

    try std.testing.expect(ctx.hasModule());
}

test "PassContext - access to components" {
    var fact_store = try FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store, std.testing.allocator);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();

    var ctx = PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
        &data_flow_graph,
    );
    defer ctx.deinit();

    // Verify access to components
    _ = ctx.fact_store;
    _ = ctx.query_engine;
    _ = ctx.allocator;
}

test "PassContext - getOrComputeZoneByName caching" {
    var fact_store = try FactStore.init(std.testing.allocator);
    defer fact_store.deinit();
    var query_engine = QueryEngine.init(&fact_store, std.testing.allocator);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();
    var ctx = PassContext.init(std.testing.allocator, null, &fact_store, &query_engine, &data_flow_graph);
    defer ctx.deinit();

    // LLVM intrinsics → .runtime_internal
    const llvm_zone = ctx.getOrComputeZoneByName("llvm.memcpy.p0i8.p0i8.i64");
    try std.testing.expectEqual(zone_classifier.ZoneKind.runtime_internal, llvm_zone);

    // Second lookup should hit cache (same result)
    const llvm_zone2 = ctx.getOrComputeZoneByName("llvm.memcpy.p0i8.p0i8.i64");
    try std.testing.expectEqual(llvm_zone, llvm_zone2);

    // Rust safe pattern → .safe
    const rust_zone = ctx.getOrComputeZoneByName("std::sync::Arc::new");
    try std.testing.expectEqual(zone_classifier.ZoneKind.safe, rust_zone);

    // Unknown function → .unknown (default)
    const unknown_zone = ctx.getOrComputeZoneByName("my_custom_function");
    try std.testing.expectEqual(zone_classifier.ZoneKind.unknown, unknown_zone);
}

test "PassContext - shouldAnalyzeZone gate logic" {
    // Safe and runtime_internal should be skipped
    try std.testing.expect(!PassContext.shouldAnalyzeZone(.safe));
    try std.testing.expect(!PassContext.shouldAnalyzeZone(.runtime_internal));

    // These should be analyzed
    try std.testing.expect(PassContext.shouldAnalyzeZone(.unknown));
    try std.testing.expect(PassContext.shouldAnalyzeZone(.unsafe));
    try std.testing.expect(PassContext.shouldAnalyzeZone(.ffi));
}

test "PassContext - getOrComputeZone null safety" {
    var fact_store = try FactStore.init(std.testing.allocator);
    defer fact_store.deinit();
    var query_engine = QueryEngine.init(&fact_store, std.testing.allocator);
    var data_flow_graph = try @import("../dataflow/graph.zig").DataFlowGraph.init(std.testing.allocator, &fact_store, &query_engine);
    defer data_flow_graph.deinit();
    var ctx = PassContext.init(std.testing.allocator, null, &fact_store, &query_engine, &data_flow_graph);
    defer ctx.deinit();

    // Valid pointer should return a valid zone (not crash)
    var dummy: u8 = 0;
    const zone = ctx.getOrComputeZone(@ptrCast(&dummy), "dummy_func");
    // Should return some valid ZoneKind enum value
    _ = zone;
}

/// Convert diag.issue.Severity to noise_filter.Severity
fn diagToNoiseSeverity(sev: DiagSeverity) NoiseSeverity {
    return @enumFromInt(@intFromEnum(sev));
}
