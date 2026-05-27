//! Pass type definitions extracted from pass.zig
//!
//! This module contains all core type definitions for the Pass system:
//! - PassKind: Pass classification enum
//! - CrossLangEdge: Cross-language call edge
//! - CallSiteIndex/CallSite: Shared call site index
//! - GlobalAllocTracker: Cross-function allocation tracker
//! - PassContext: Main analysis context (largest struct)
//! - ChannelMode: Analysis channel gating
//! - DiagnosticWriter: Colored diagnostic output

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("../common/log.zig");
const c = @import("../ir/llvm_raw.zig").c;
const PrefixTrie = @import("../common/prefix_trie.zig").PrefixTrie;
const StringInterner = @import("../common/string_interner.zig").StringInterner;
const Arena = @import("../common/arena.zig").Arena;

const ModuleRef = @import("../ir/view.zig").ModuleRef;
const FactStore = @import("../fact/store.zig").FactStore;
const QueryEngine = @import("../fact/query.zig").QueryEngine;
const DataFlowGraph = @import("../dataflow/graph.zig").DataFlowGraph;
const ValueIdMap = @import("../dataflow/value_id_map.zig").ValueIdMap;
const memory_graph_mod = @import("../semantics/memory_graph.zig");
const call_graph_mod = @import("../semantics/call_graph.zig");
const zone_classifier = @import("../semantics/zone_classifier.zig");
const noise_filter = @import("../semantics/noise_filter.zig");
const surface_classifier = @import("../semantics/surface_classifier/surface_classifier.zig");
// Import name-based heuristic classifier for origin fallback
const ffi_enhancement = @import("../pass/analysis/ffi/ffi_enhancement.zig");
const language_detector = @import("../semantics/language_detector.zig");
const ir_evidence = @import("./ir_evidence.zig");
const issue_suppression = @import("../pass/analysis/noise/issue_suppression.zig");
const Issue = @import("../diag/issue.zig").Issue;
const DiagSeverity = @import("../diag/issue.zig").Severity;
const NoiseSeverity = noise_filter.Severity;
const SemanticRegistry = @import("../registry/semantic_registry.zig").SemanticRegistry;
const FunctionSemantics = @import("../registry/semantic_registry.zig").FunctionSemantics;

const resource_summary_mod = @import("../semantics/resource/function_summary.zig");
pub const SummaryStore = resource_summary_mod.SummaryStore;

/// Pass kind classification
pub const PassKind = enum {
    foundation,
    analysis,
    plugin,
};

/// R8.2: Cross-language call edge extracted by CallGraphPass.
pub const CrossLangEdge = struct {
    caller_name: []const u8,
    callee_name: []const u8,
    caller_lang: @import("../diag/issue.zig").FFIBoundary.Language,
    callee_lang: @import("../diag/issue.zig").FFIBoundary.Language,
    is_ffi_boundary: bool,
    ptr_args: []const u32,
};

/// Shared callee → call_sites index for O(1) lookup.
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

    pub fn addCall(self: *CallSiteIndex, allocator: Allocator, callee_name: []const u8, caller_func: u64, inst: u64) !void {
        const gop = try self.map.getOrPut(callee_name);
        if (!gop.found_existing) {
            gop.value_ptr.* = try std.ArrayList(CallSite).initCapacity(allocator, 4);
        }
        try gop.value_ptr.append(self.allocator, .{ .caller_func = caller_func, .inst = inst });
    }

    pub fn getCallSites(self: *const CallSiteIndex, callee_name: []const u8) ?[]const CallSite {
        if (self.map.get(callee_name)) |sites| {
            return sites.items;
        }
        return null;
    }
};

/// A single call site record in the shared index.
pub const CallSite = struct {
    caller_func: u64,
    inst: u64,
};

/// R8.3: Global allocation tracker for cross-function leak detection.
pub const GlobalAllocTracker = struct {
    pub const AllocRecord = struct {
        ptr_id: u32,
        alloc_func: []const u8,
        /// P19-2: LLVM function value for structural transfer inference
        alloc_func_val: ?c.LLVMValueRef = null,
        alloc_callee: []const u8,
        freed: bool,
        free_func: ?[]const u8,
        is_global_or_static: bool,
        /// Bug 4: Whether this allocation is inside a conditional branch.
        /// If true, reduces leak report confidence (may not execute on all paths).
        is_conditional: bool = false,
    };

    allocator: Allocator,
    records_by_ptr: std.AutoHashMap(u64, u32),
    records: std.ArrayList(AllocRecord),

    pub fn init(allocator: Allocator) GlobalAllocTracker {
        return .{
            .allocator = allocator,
            .records_by_ptr = std.AutoHashMap(u64, u32).init(allocator),
            .records = std.ArrayList(AllocRecord).empty,
        };
    }

    pub fn deinit(self: *GlobalAllocTracker) void {
        for (self.records.items) |*rec| {
            self.allocator.free(rec.alloc_func);
            if (rec.alloc_callee.len > 0) self.allocator.free(rec.alloc_callee);
            if (rec.free_func) |f| self.allocator.free(f);
        }
        self.records.deinit(self.allocator);
        self.records_by_ptr.deinit();
    }

    pub fn insertAlloc(self: *GlobalAllocTracker, ptr_val: u64, func_name: []const u8, callee_name: []const u8, is_global: bool, inst_id: u32, is_conditional: bool, func_val: ?c.LLVMValueRef) !void {
        const name_owned = try self.allocator.dupe(u8, func_name);
        const callee_owned = if (callee_name.len > 0) try self.allocator.dupe(u8, callee_name) else &[_]u8{};
        const idx = @as(u32, @intCast(self.records.items.len));
        try self.records.append(self.allocator, .{
            .ptr_id = inst_id,
            .alloc_func = name_owned,
            .alloc_func_val = func_val,
            .alloc_callee = callee_owned,
            .freed = false,
            .free_func = null,
            .is_global_or_static = is_global,
            .is_conditional = is_conditional,
        });
        try self.records_by_ptr.put(ptr_val, idx);
    }

    pub fn markFreed(self: *GlobalAllocTracker, ptr_val: u64, func_name: []const u8) bool {
        const idx = self.records_by_ptr.get(ptr_val) orelse return false;
        var rec = &self.records.items[idx];
        if (rec.freed) return true;
        rec.freed = true;
        const free_name_owned = self.allocator.dupe(u8, func_name) catch return true;
        rec.free_func = free_name_owned;
        return true;
    }

    pub fn getLeakCount(self: *const GlobalAllocTracker) u32 {
        return self.leakCount();
    }

    pub fn size(self: *const GlobalAllocTracker) usize {
        return self.records.items.len;
    }

    pub fn leakCount(self: *const GlobalAllocTracker) u32 {
        var count: u32 = 0;
        for (self.records.items) |rec| {
            if (!rec.freed and !rec.is_global_or_static) count += 1;
        }
        return count;
    }
};

/// Main pass context - holds all analysis state and provides unified API
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
    rust_into_raw_set: std.StringHashMap(void),
    rust_from_raw_set: std.StringHashMap(void),

    reported_keys: std.AutoHashMap(u64, void),
    registry_cache: std.StringHashMap(FunctionSemantics),
    zone_cache: std.StringHashMap(zone_classifier.ZoneKind),
    zone_stats: zone_classifier.ZoneStats,
    module_language: language_detector.LanguageProfile,
    language_detected: bool,
    degraded_functions: std.atomic.Value(u32),
    cross_lang_edges: std.ArrayList(CrossLangEdge),
    early_exit: bool,
    global_alloc_tracker: GlobalAllocTracker,
    memory_graph: memory_graph_mod.MemoryGraph,
    danger_surface_relevant: std.AutoHashMap(u64, void),
    ffi_auto_relevant: std.AutoHashMap(u64, void),
    relevant_functions: std.AutoHashMap(u64, void),
    CallSiteIndex: CallSiteIndex,
    cross_edge_by_callee: std.StringHashMap(std.ArrayList(u32)),
    semantics_call_graph: ?call_graph_mod.CallGraph,
    ffi_set_cache: ?std.StringHashMap(void),
    danger_surfaces_cache: ?[]memory_graph_mod.DangerSurface,
    danger_path_visited_cache: ?std.AutoHashMap(u64, void),
    function_surface: std.AutoHashMap(u64, surface_classifier.FunctionSurface),
    has_ffi_boundary: bool = true,
    suppression_stats: issue_suppression.SuppressionStats,
    semantic_resolution: ?*@import("../semantics/resolution_engine.zig").ResolutionEngine,
    evidence: ?ir_evidence.IREvidence,
    interner: ?StringInterner,
    arena: ?Arena,
    /// Detected platform profile from LLVM module metadata.
    /// Populated during pipeline initialization, read-only thereafter.
    /// Used by SurfaceClassifier, language detector, and noise suppressor.
    platform_profile: ?@import("../semantics/platform_profile.zig").PlatformProfile,
    /// Resource function summary store for shared callee semantics.
    /// All heavy passes (memory_graph, ptr_lifetime, ffi_boundary) read
    /// from this single source instead of independently classifying callees.
    /// null = legacy mode (per-pass guessing). Set during pipeline init.
    resource_summary: ?*SummaryStore,

    pub fn init(
        allocator: Allocator,
        module: ?ModuleRef,
        fact_store: *FactStore,
        query_engine: *QueryEngine,
        data_flow_graph: *DataFlowGraph,
    ) !PassContext {
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
            .rust_into_raw_set = std.StringHashMap(void).init(allocator),
            .rust_from_raw_set = std.StringHashMap(void).init(allocator),
            .reported_keys = std.AutoHashMap(u64, void).init(allocator),
            .registry_cache = std.StringHashMap(FunctionSemantics).init(allocator),
            .zone_cache = std.StringHashMap(zone_classifier.ZoneKind).init(allocator),
            .zone_stats = zone_classifier.ZoneStats{},
            .module_language = .{ .language = .unknown, .confidence = 0.0, .method = .unknown },
            .language_detected = false,
            .degraded_functions = std.atomic.Value(u32).init(0),
            .cross_lang_edges = std.ArrayList(CrossLangEdge).empty,
            .early_exit = false,
            .global_alloc_tracker = GlobalAllocTracker.init(allocator),
            .memory_graph = try memory_graph_mod.MemoryGraph.init(allocator),
            .danger_surface_relevant = std.AutoHashMap(u64, void).init(allocator),
            .ffi_auto_relevant = std.AutoHashMap(u64, void).init(allocator),
            .relevant_functions = std.AutoHashMap(u64, void).init(allocator),
            .CallSiteIndex = CallSiteIndex.init(allocator),
            .cross_edge_by_callee = std.StringHashMap(std.ArrayList(u32)).init(allocator),
            .semantics_call_graph = null,
            .ffi_set_cache = null,
            .danger_surfaces_cache = null,
            .danger_path_visited_cache = null,
            .function_surface = std.AutoHashMap(u64, surface_classifier.FunctionSurface).init(allocator),
            .has_ffi_boundary = true,
            .suppression_stats = .{},
            .semantic_resolution = null,
            .evidence = null,
            .interner = null,
            .arena = null,
            .platform_profile = null,
            .resource_summary = null,
        };
    }

    pub fn getNextId(self: *PassContext) u32 {
        return self.next_id.fetchAdd(1, .seq_cst);
    }

    pub fn getValueId(self: *PassContext, ptr: usize) !u32 {
        return self.value_id_map.getOrPutId(ptr);
    }

    pub fn getNextVulnId(self: *PassContext) u32 {
        return self.vuln_id.fetchAdd(1, .seq_cst) + 1;
    }

    pub fn recordDegradedFunction(self: *PassContext) void {
        _ = self.degraded_functions.fetchAdd(1, .seq_cst);
    }

    pub fn getDegradedFunctionCount(self: *const PassContext) u32 {
        return self.degraded_functions.load(.seq_cst);
    }

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
            self.allocator.free(edge.ptr_args);
        }
        self.cross_lang_edges.deinit(self.allocator);
        self.global_alloc_tracker.deinit();
        self.memory_graph.deinit();
        self.danger_surface_relevant.deinit();
        self.ffi_auto_relevant.deinit();
        self.relevant_functions.deinit();
        self.CallSiteIndex.deinit();
        var edge_iter = self.cross_edge_by_callee.valueIterator();
        while (edge_iter.next()) |list| {
            list.deinit(self.allocator);
        }
        self.cross_edge_by_callee.deinit();
        if (self.ffi_set_cache) |*cache| {
            cache.deinit();
        }
        if (self.danger_surfaces_cache) |surfaces| {
            self.allocator.free(surfaces);
        }
        if (self.danger_path_visited_cache) |*cache| {
            cache.deinit();
        }
        self.function_surface.deinit();
        if (self.platform_profile) |*profile| {
            profile.deinit(self.allocator);
        }
        if (self.semantic_resolution) |engine| {
            engine.deinit();
            self.allocator.destroy(engine);
        }
        if (self.interner) |*intr| {
            intr.deinit();
        }
        if (self.arena) |*a| {
            a.deinit();
        }
    }

    pub fn getFunctionSurface(self: *const PassContext, func_ptr: u64) ?surface_classifier.FunctionSurface {
        return self.function_surface.get(func_ptr);
    }

    pub fn shouldAnalyzeFunctionSurface(self: *const PassContext, func_ptr: u64) bool {
        const surf = self.getFunctionSurface(func_ptr) orelse return true;
        return surf.shouldAnalyze();
    }

    pub fn shouldAnalyzeFunctionSurfaceByName(self: *PassContext, func_name: []const u8, func_ptr: ?u64) bool {
        if (func_ptr) |ptr| {
            if (self.function_surface.get(ptr)) |surf| {
                return surf.shouldAnalyze();
            }
        }
        if (self.module) |mod| {
            const raw_mod = mod.raw;
            const func = c.LLVMGetNamedFunction(raw_mod, func_name.ptr);
            if (@intFromPtr(func) != 0) {
                const ptr = @as(u64, @intFromPtr(func));
                if (self.function_surface.get(ptr)) |surf| {
                    return surf.shouldAnalyze();
                }
            }
        }
        return true;
    }

    pub fn classifyFunctionSurface(
        self: *PassContext,
        func_name: []const u8,
        source_location: ?@import("../ir/debug_info.zig").SourceLocation,
    ) noise_filter.ClassificationResult {
        _ = source_location;

        if (isZigStdlibFunction(func_name)) {
            return .{
                .origin = .stdlib,
                .risk_level = noise_filter.getRiskLevel(.stdlib, .medium),
                .reason = "Zig standard library (prefix match)",
            };
        }

        if (self.module) |mod| {
            const raw_mod = mod.raw;
            const func = c.LLVMGetNamedFunction(raw_mod, func_name.ptr);
            if (@intFromPtr(func) != 0) {
                const ptr = @as(u64, @intFromPtr(func));
                if (self.function_surface.get(ptr)) |surf| {
                    const nf_origin = noise_filter.functionSurfaceToOrigin(surf);
                    return .{
                        .origin = nf_origin,
                        .risk_level = noise_filter.getRiskLevel(nf_origin, .medium),
                        .reason = "surface-classifier cache",
                    };
                }
            }
        }

        // P16-3: Name-based heuristic fallback — reduces unknown from ~60% to <20%
        // When surface classifier cache misses (common in test corpus without debug info),
        // use naming convention heuristics to classify function origin.
        // This prevents over-aggressive severity downgrade for user code.
        const fn_origin_heuristic = ffi_enhancement.classifyFunctionOrigin(func_name);
        const fn_origin: noise_filter.FunctionOrigin = switch (fn_origin_heuristic) {
            .user => .user,
            .stdlib => .stdlib,
            .compiler_generated => .compiler_generated,
            .third_party => .third_party,
            .unknown => .unknown,
        };
        if (fn_origin != .unknown) {
            return .{
                .origin = fn_origin,
                .risk_level = noise_filter.getRiskLevel(fn_origin, .medium),
                .reason = "name-based heuristic fallback",
            };
        }

        // Final fallback: still unknown, but with improved reason
        return .{
            .origin = .unknown,
            .risk_level = .medium,
            .reason = "unclassified (no cache hit, no name pattern match)",
        };
    }

    pub fn setModule(self: *PassContext, module: ModuleRef) void {
        self.module = module;
    }

    pub fn hasModule(self: *const PassContext) bool {
        return self.module != null;
    }

    pub fn getDataFlowGraph(self: *const PassContext) *DataFlowGraph {
        return self.data_flow_graph;
    }

    pub fn addNode(self: *PassContext, node: anytype) !void {
        try self.data_flow_graph.addNode(node);
    }

    pub fn addEdge(self: *PassContext, edge: anytype) !void {
        try self.data_flow_graph.addEdge(edge);
    }

    pub fn addFFIBoundary(self: *PassContext, boundary: anytype) !void {
        try self.data_flow_graph.addFFIBoundary(boundary);
    }

    pub fn addIssue(self: *PassContext, issue: *const Issue) !void {
        // Pass the cached platform profile to suppression so platform-specific
        // patterns (e.g. Windows MSVC CRT) are only consulted when relevant.
        const profile_ptr = if (self.platform_profile) |*p| p else null;
        if (issue_suppression.shouldSuppressWithProfile(issue, profile_ptr)) {
            // Record which pattern caused suppression for accurate stats
            // Patterns A-F deprecated — only Pattern G (stdlib_internal) remains
            if (issue_suppression.isStdlibInternalFunction(issue)) {
                self.suppression_stats.record(.stdlib_internal);
            } else {
                self.suppression_stats.record(.drop_chain);
            }
            if (issue.owned) {
                var mutable_issue = issue.*;
                mutable_issue.deinit(self.allocator);
            }
            return;
        }

        const on_danger_path = if (issue.ffi_boundary) |_| true else false;

        const func_name = issue.location.func;
        const classification = self.classifyFunctionSurface(func_name, null);
        var risk = noise_filter.getRiskLevel(classification.origin, diagToNoiseSeverity(issue.severity));

        // FFI boundary issues should NOT be suppressed by noise filter
        // FFI cross-ABI calls are inherently security-relevant regardless of function origin
        // Core memory safety bugs should also bypass risk suppression — a double_free
        // or use_after_free in an unknown-origin function is still a real vulnerability.
        const is_ffi_issue = switch (issue.kind) {
            // FFI boundary issues
            .ffi_unsafe_call,
            .ffi_type_mismatch,
            .type_mismatch,
            .cross_language_leak,
            .cross_language_free,
            .borrow_escape,
            => true,

            // Core memory safety — never risk-suppressed
            .double_free,
            .use_after_free,
            .invalid_free,
            .memory_leak,
            => true,

            else => on_danger_path,
        };

        if (!is_ffi_issue and issue.severity != .critical and risk == .suppressed) {
            if (issue.owned) {
                var mutable_issue = issue.*;
                mutable_issue.deinit(self.allocator);
            }
            return;
        }
        if (is_ffi_issue and risk == .suppressed) {
            risk = .low; // Upgrade suppressed → low for FFI issues
        }
        if (issue.severity == .critical and risk == .suppressed) {
            risk = .critical;
        }

        const dedup_key = self.dedupKey(issue);
        if (issue.severity != .critical) {
            const gop = try self.reported_keys.getOrPut(dedup_key);
            if (gop.found_existing) {
                if (issue.owned) {
                    var mutable_issue = issue.*;
                    mutable_issue.deinit(self.allocator);
                }
                return;
            }
        }

        var final_issue = issue.*;
        const risk_severity: DiagSeverity = switch (risk) {
            .critical => .critical,
            .high => .high,
            .medium => .medium,
            .low => .low,
            .suppressed => .low,
        };

        // P16-1: Core memory safety bugs should NEVER be downgraded by noise filter.
        // These are real vulnerabilities regardless of function origin classification.
        //
        // P16-3: .memory_leak intentionally EXCLUDED from this whitelist.
        // Rationale: Leaks are probabilistic (not deterministic like UAF/DF).
        // Many leaks are FPs (global vars, long-lived objects, intentional caching).
        // Including .memory_leak would inflate severity of uncertain findings,
        // reducing precision without improving recall for real bugs.
        // See P15_DIFF_REPORT.md TC9 analysis for details.
        const is_core_memory_safety_bug = switch (issue.kind) {
            .use_after_free,
            .double_free,
            .invalid_free,
            .null_dereference,
            .buffer_overflow,
            .cross_language_free,
            .cross_language_leak,
            // NOTE: .memory_leak removed — handled by normal downgrade path
            => true,
            else => false,
        };

        // P16-11/P16-12: Anti-collapse — prevent "severity cliff" where
        // .critical drops directly to .low. Enforce gradual step-down (max 1 level).
        //
        // Motivation: When origin = "unknown" (common in test corpus),
        // noise_filter returns risk = .low for ALL issue kinds. Without this:
        //   - ffi_unsafe_call (.critical) → .low (loses critical info)
        //   - borrow_escape (.high) → .low (over-suppression)
        //
        // With stepDown + max():
        //   - (.critical, risk=.low) → max(.low, stepDown(.critical)=.high) = .high ✅
        //   - (.high, risk=.low) → max(.low, stepDown(.high)=.medium) = .medium ✅
        const stepped_severity: DiagSeverity = switch (issue.severity) {
            .critical => .high,
            .high => .medium,
            .medium => .low,
            .low => .low,
        };

        // P16-12: severityMax — return the more severe of two severities
        const final_severity: DiagSeverity = blk: {
            const rank_a: u3 = switch (risk_severity) {
                .critical => 3,
                .high => 2,
                .medium => 1,
                .low => 0,
            };
            const rank_b: u3 = switch (stepped_severity) {
                .critical => 3,
                .high => 2,
                .medium => 1,
                .low => 0,
            };
            break :blk if (rank_a >= rank_b) risk_severity else stepped_severity;
        };

        const should_downgrade = !is_core_memory_safety_bug and switch (issue.severity) {
            .critical => risk_severity != .critical,
            .high => risk_severity == .medium or risk_severity == .low,
            .medium => risk_severity == .low,
            .low => false,
        };

        // P16-13: Apply anti-collapse — use max(risk, stepDown(original))
        // This ensures severity drops by at most ONE level per downgrade trigger.
        if (should_downgrade) {
            final_issue.severity = final_severity;
        }

        const is_ffi_kind = switch (issue.kind) {
            .ffi_unsafe_call,
            .ffi_type_mismatch,
            .type_mismatch,
            .cross_language_leak,
            .cross_language_free,
            .borrow_escape,
            => true,
            else => false,
        };
        final_issue.classification = if (is_ffi_kind or on_danger_path) .ffi_boundary else .local_only;

        if (!final_issue.owned) {
            const cloned_msg = try self.allocator.dupe(u8, final_issue.message);
            final_issue.message = cloned_msg;
            final_issue.owned = true;
        }
        try self.data_flow_graph.addIssue(final_issue);
    }

    fn dedupKey(self: *PassContext, issue: *const Issue) u64 {
        _ = self;
        const loc = @field(issue, "location");
        const kind_tag = @tagName(@field(issue, "kind"));
        var hasher = std.hash.Fnv1a_64.init();
        hasher.update(loc.func);
        hasher.update(kind_tag);
        if (loc.file) |f| hasher.update(f);
        if (loc.line > 0) hasher.update(&std.mem.toBytes(loc.line));
        if (loc.column > 0) hasher.update(&std.mem.toBytes(loc.column));
        return hasher.final();
    }

    pub fn cachedRegistryLookup(self: *PassContext, func_name: []const u8) ?FunctionSemantics {
        if (self.registry_cache.get(func_name)) |sem| {
            return sem;
        }
        const sem = SemanticRegistry.lookup(func_name) orelse return null;
        self.registry_cache.put(func_name, sem) catch |err| {
            log.warn("[pass-types] registry_cache.put OOM for '{s}': {}", .{ func_name, err });
        };
        return sem;
    }

    pub fn cachedZoneLookup(self: *PassContext, func_name: []const u8) ?zone_classifier.ZoneKind {
        return self.zone_cache.get(func_name);
    }

    pub fn cacheZoneResult(self: *PassContext, func_name: []const u8, zone: zone_classifier.ZoneKind) void {
        self.zone_cache.put(func_name, zone) catch |err| {
            log.warn("[pass-types] zone_cache.put OOM for '{s}': {}", .{ func_name, err });
        };
    }

    pub fn getOrComputeZone(self: *PassContext, func: *anyopaque, func_name: []const u8) zone_classifier.ZoneKind {
        const func_addr = @intFromPtr(func);
        if (func_addr == 0) return .unknown;
        return self.cachedZoneLookup(func_name) orelse blk: {
            const z = zone_classifier.classifyFunctionFromLLVM(@ptrCast(func), func_name);
            self.cacheZoneResult(func_name, z);
            break :blk z;
        };
    }

    pub fn shouldAnalyzeZone(zone: zone_classifier.ZoneKind) bool {
        return switch (zone) {
            .safe => false,
            .runtime_internal => false,
            .unknown => true,
            .unsafe => true,
            .ffi => true,
        };
    }

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

        if (self.evidence == null) {
            var evidence_collector = ir_evidence.EvidenceCollector.init(self.allocator, llvm_module) catch |err| {
                log.warn("[pass-types] Evidence collection failed: {}", .{err});
                return;
            };
            defer evidence_collector.deinit();
            self.evidence = evidence_collector.getEvidence().*;
        }

        log.debug("[pass-types] LANG-DETECT: module language = {s}, confidence = {d:.1}%, method = {s}", .{
            @tagName(self.module_language.language),
            self.module_language.confidence * 100,
            @tagName(self.module_language.method),
        });
    }

    pub fn getModuleLanguage(self: *const PassContext) language_detector.LanguageProfile {
        return self.module_language;
    }

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

    pub fn channelFFIBoundary(self: *const PassContext) ChannelMode {
        return switch (self.module_language.language) {
            .zig => .limited,
            .go => .limited,
            else => .full,
        };
    }
    pub fn channelPtrLifetime(self: *const PassContext) ChannelMode {
        return switch (self.module_language.language) {
            .zig => .limited,
            .go => .limited,
            else => .full,
        };
    }
    pub fn channelCallbackEscape(self: *const PassContext) ChannelMode {
        return switch (self.module_language.language) {
            .zig => .limited,
            else => .full,
        };
    }
    pub fn channelPointerOwnership(self: *const PassContext) ChannelMode {
        return switch (self.module_language.language) {
            .zig => .limited,
            .go => .limited,
            else => .full,
        };
    }

    /// R7.2: Channel mode for analysis pass gating.
    pub const ChannelMode = enum {
        full,
        limited,
        skip,
    };

    pub fn getOrComputeZoneByName(self: *PassContext, func_name: []const u8) zone_classifier.ZoneKind {
        return self.cachedZoneLookup(func_name) orelse blk: {
            const z = zone_classifier.classifyFunction(func_name, null);
            self.cacheZoneResult(func_name, z);
            break :blk z;
        };
    }

    pub fn markTainted(self: *PassContext, node_id: u32, source_id: ?u32) !void {
        try self.data_flow_graph.markTainted(node_id, source_id);
    }

    pub fn isTainted(self: *const PassContext, node_id: u32) bool {
        return self.data_flow_graph.isTainted(node_id);
    }

    pub fn addCrossLangEdge(self: *PassContext, edge: CrossLangEdge) !void {
        const idx = @as(u32, @intCast(self.cross_lang_edges.items.len));
        try self.cross_lang_edges.append(self.allocator, edge);
        const gop = try self.cross_edge_by_callee.getOrPut(edge.callee_name);
        if (!gop.found_existing) {
            gop.value_ptr.* = try std.ArrayList(u32).initCapacity(self.allocator, 4);
        }
        try gop.value_ptr.*.append(self.allocator, idx);
    }

    pub fn getCrossLangEdges(self: *const PassContext) []const CrossLangEdge {
        return self.cross_lang_edges.items;
    }

    pub fn getCrossEdgeByCallee(self: *const PassContext, callee_name: []const u8) ?*const CrossLangEdge {
        if (self.cross_edge_by_callee.get(callee_name)) |indices| {
            if (indices.items.len > 0) {
                return &self.cross_lang_edges.items[indices.items[0]];
            }
        }
        return null;
    }

    pub fn getAllCrossEdgesByCallee(self: *const PassContext, callee_name: []const u8) ?[]const u32 {
        if (self.cross_edge_by_callee.get(callee_name)) |indices| {
            return indices.items;
        }
        return null;
    }

    pub fn isRelevantAlloc(self: *const PassContext, ptr_val: u64) bool {
        if (self.danger_surface_relevant.contains(ptr_val)) return true;
        if (self.ffi_auto_relevant.count() == 0) return false;
        return self.ffi_auto_relevant.contains(ptr_val);
    }

    pub fn isOnDangerPathFull(self: *PassContext, ptr_val: u64) bool {
        const raw_ffis = self.getCrossLangEdges();
        if (raw_ffis.len == 0) return self.isRelevantAlloc(ptr_val);

        if (self.ffi_set_cache == null) {
            var ffi_set = std.StringHashMap(void).init(self.allocator);
            for (raw_ffis) |ffe| {
                if (ffe.is_ffi_boundary) {
                    ffi_set.put(ffe.callee_name, {}) catch {
                        ffi_set.deinit();
                        return false;
                    };
                }
            }
            self.ffi_set_cache = ffi_set;
        }

        if (self.danger_surfaces_cache == null) {
            const surfaces = self.allocator.alloc(memory_graph_mod.DangerSurface, raw_ffis.len) catch return false;
            for (raw_ffis, 0..) |ffe, i| {
                surfaces[i] = .{
                    .callee_name = ffe.callee_name,
                    .is_ffi_boundary = ffe.is_ffi_boundary,
                };
            }
            self.danger_surfaces_cache = surfaces;
        }

        if (self.danger_path_visited_cache == null) {
            self.danger_path_visited_cache = std.AutoHashMap(u64, void).init(self.allocator);
        }
        self.danger_path_visited_cache.?.clearRetainingCapacity();

        const result = self.memory_graph.isOnDangerPath(ptr_val, self.danger_surfaces_cache.?, &self.danger_path_visited_cache.?, &self.ffi_set_cache.?);
        return result != .none;
    }

    pub fn markRelevantAlloc(self: *PassContext, ptr_val: u64) !void {
        try self.danger_surface_relevant.put(ptr_val, {});
    }

    pub fn markFfiRelevant(self: *PassContext, ptr_val: u64) !void {
        try self.ffi_auto_relevant.put(ptr_val, {});
    }

    pub fn isRelevantFunction(self: *const PassContext, func_ptr: u64) bool {
        return self.relevant_functions.contains(func_ptr);
    }

    pub fn markRelevantFunction(self: *PassContext, func_ptr: u64) !void {
        try self.relevant_functions.put(func_ptr, {});
    }

    pub fn markFunctionFromInst(self: *PassContext, inst_ptr: u64) !void {
        if (inst_ptr == 0) return;

        const inst = @as(c.LLVMValueRef, @ptrFromInt(inst_ptr));
        if (@intFromPtr(inst) == 0) return;

        const bb = c.LLVMGetInstructionParent(inst);
        if (@intFromPtr(bb) == 0) return;

        const func = c.LLVMGetBasicBlockParent(bb);
        if (@intFromPtr(func) == 0) return;

        const func_ptr = @as(u64, @intFromPtr(func));
        try self.relevant_functions.put(func_ptr, {});
    }

    /// Intern a string using the optional string interner.
    ///
    /// If the interner is initialized (non-null), returns the canonical
    /// deduplicated copy. Otherwise returns a freshly allocated copy.
    ///
    /// Arguments:
    ///   s - String slice to intern
    ///
    /// Returns:
    ///   Owned string slice (caller must not free directly)
    ///
    /// Errors:
    ///   OutOfMemory if allocation fails
    pub fn internString(self: *PassContext, s: []const u8) ![]const u8 {
        if (self.interner) |*intr| {
            return intr.intern(s);
        }
        return self.allocator.dupe(u8, s);
    }

    /// Enable string interning for this context.
    ///
    /// Initializes the internal StringInterner if not already done.
    /// After calling this, internString() will deduplicate strings.
    pub fn enableInterning(self: *PassContext) !void {
        if (self.interner == null) {
            self.interner = StringInterner.init(self.allocator);
        }
    }

    /// Enable arena allocator for this context.
    ///
    /// Initializes the internal Arena if not already done.
    /// After calling this, arenaAlloc() returns a fast bump-pointer allocator
    /// suitable for temporary allocations during analysis passes.
    ///
    /// Use cases:
    /// - Temporary HashMap nodes during single-pass analysis
    /// - ArrayList elements that are bulk-freed at pass end
    /// - Any short-lived data that can be freed all at once
    ///
    /// Example:
    ///
    /// ```zig
    /// try ctx.enableArena();
    /// const alloc = ctx.arenaAlloc();
    /// var temp_list = std.ArrayList(u32).init(alloc);
    /// ```
    pub fn enableArena(self: *PassContext) !void {
        if (self.arena == null) {
            self.arena = Arena.init(self.allocator);
        }
    }

    /// Get the arena allocator if enabled, or fallback to the default allocator.
    ///
    /// Returns a std.mem.Allocator that can be used for temporary allocations.
    /// If the arena is not initialized, falls back to the context's main allocator.
    ///
    /// Returns:
    ///   Allocator interface (arena if enabled, otherwise default allocator)
    ///
    /// Note:
    ///   When using the returned allocator, memory is managed by the arena
    ///   and will be freed on reset/deinit. Do not call allocator.free() on
    ///   pointers obtained from this allocator.
    pub fn arenaAlloc(self: *PassContext) std.mem.Allocator {
        if (self.arena) |*a| {
            return @import("../common/arena.zig").arenaAllocator(a);
        }
        return self.allocator;
    }
};

/// ANSI color codes for terminal output
pub const Colors = struct {
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
        if (std.mem.eql(u8, severity, "INFO") and log.current_log_level == .normal) return;
        if (log.current_log_level == .normal) return;

        const color = comptime getSeverityColor(severity);
        if (self.use_color) {
            std.log.info(color ++ "[" ++ severity ++ "]" ++ Colors.reset ++ " " ++ format ++ "\n", args);
        } else {
            std.log.info("[" ++ severity ++ "] " ++ format ++ "\n", args);
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

fn diagToNoiseSeverity(sev: DiagSeverity) NoiseSeverity {
    return @enumFromInt(@intFromEnum(sev));
}

fn isZigStdlibFunction(func_name: []const u8) bool {
    const stdlib_prefixes = [_][]const u8{
        "debug.",
        "heap.",
        "mem.",
        "fmt.",
        "io.",
        "posix.",
        "hash_map.",
        "array_hash_map.",
        "array_list.",
        "bitmap.",
        "crypto.",
        "log.",
        "time.",
        "fs.",
        "net.",
        "process.",
        "async.",
        "event_loop.",
        "unicode",
        "math.",
        "random",
        "compress",
        "hmac",
        "aead",
        "aes",
    };
    const trie = comptime PrefixTrie.init(&stdlib_prefixes, .substring);
    return trie.contains(func_name);
}
