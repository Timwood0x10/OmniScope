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
const ir_evidence = @import("../ir/ir_evidence.zig");
const issue_suppression = @import("../pass/analysis/noise/issue_suppression.zig");
const suppression_patterns = @import("../pass/analysis/noise/suppression_patterns.zig");
const issue_classification = @import("../filter/issue_classification.zig");
const filter_context_mod = @import("../filter/filter_context.zig");
const FilterContext = filter_context_mod.FilterContext;
const Issue = @import("../diag/issue.zig").Issue;
const DiagSeverity = @import("../diag/issue.zig").Severity;
const SemanticSurface = @import("../common/types.zig").SemanticSurface;
const NoiseSeverity = noise_filter.Severity;
const SemanticRegistry = @import("../registry/semantic_registry.zig").SemanticRegistry;
const FunctionSemantics = @import("../registry/semantic_registry.zig").FunctionSemantics;

const resource_summary_mod = @import("../semantics/resource/function_summary.zig");
pub const SummaryStore = resource_summary_mod.SummaryStore;

const resource_candidate_mod = @import("../pass/analysis/resource/issue_candidate_builder.zig");
pub const CandidateBuilder = resource_candidate_mod.CandidateBuilder;
const resource_verifier_mod = @import("../pass/analysis/resource/issue_verifier.zig");
pub const IssueVerifier = resource_verifier_mod.IssueVerifier;

const contract_db_mod = @import("../resource/ffi_contract_db.zig");
pub const FFIContractDB = contract_db_mod.FFIContractDB;

// Language Override Registry for user-specified function language classifications
const language_override = @import("../config/language_override.zig");

const ir_store_mod = @import("../ir/ir_store.zig");
pub const ModuleIRStore = ir_store_mod.ModuleIRStore;

const pc_impl = @import("../pass/pass_context_impl.zig");

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
        /// Allocation size in bytes (if determinable from LLVM IR).
        /// null = size unknown (common for indirect calls or variable-sized allocations).
        /// Used for confidence boost: large leaks (>1MB) are more impactful.
        alloc_size: ?u64 = null,
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

    pub fn insertAlloc(self: *GlobalAllocTracker, ptr_val: u64, func_name: []const u8, callee_name: []const u8, is_global: bool, inst_id: u32, is_conditional: bool, func_val: ?c.LLVMValueRef, alloc_size: ?u64) !void {
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
            .alloc_size = alloc_size,
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

    /// Try to determine the allocation size from an LLVM instruction.
    /// Returns null if size cannot be determined (common for indirect calls
    /// or variable-sized allocations via runtime computation).
    ///
    /// This function is O(1) — it only inspects the immediate operands
    /// of the allocation instruction, no recursive analysis.
    ///
    /// Supported patterns:
    ///   - malloc(const_size) → returns constant
    ///   - calloc(const_count, const_size) → returns count * size
    ///   - _Znwm(const_size) [C++ operator new] → returns constant
    ///   - alloca(const_size) → returns constant
    ///
    /// Unsupported (returns null):
    ///   - Indirect calls through function pointers
    ///   - Size computed from PHI nodes or load instructions
    ///   - Variable-length arrays (VLAs)
    pub fn getAllocationSize(alloc_inst: c.LLVMValueRef) ?u64 {
        if (@intFromPtr(alloc_inst) == 0) return null;

        const opcode = c.LLVMGetInstructionOpcode(alloc_inst);

        // Case 1: Direct call/invoke with constant size operand
        if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
            const num_ops = c.LLVMGetNumOperands(alloc_inst);
            if (num_ops < 2) return null;

            // For malloc(size): last operand before callee is size
            // For calloc(count, size): two size operands
            // For operator new(size): similar to malloc
            // Operand layout: [op0, op1, ..., callee_func]
            // We check the size operand(s) for constants
            const size_op_idx = @as(c_uint, @intCast(num_ops - 2));
            const size_op = c.LLVMGetOperand(alloc_inst, size_op_idx);
            if (@intFromPtr(size_op) == 0) return null;

            // Check if it's a constant integer
            if (c.LLVMIsConstant(size_op) != 0) {
                // Try to get constant value — API varies by LLVM version
                const const_val = c.LLVMConstIntGetZExtValue(size_op);
                return @as(u64, @bitCast(const_val));
            }

            // Case 1b: calloc with two constant operands (count * size)
            if (num_ops >= 3) {
                const count_op = c.LLVMGetOperand(alloc_inst, @as(c_uint, @intCast(num_ops - 3)));
                if (@intFromPtr(count_op) != 0 and c.LLVMIsConstant(count_op) != 0) {
                    const count_val = c.LLVMConstIntGetZExtValue(count_op);
                    const size_val = c.LLVMConstIntGetZExtValue(size_op);
                    return @as(u64, @bitCast(count_val)) * @as(u64, @bitCast(size_val));
                }
            }
        }

        // Case 2: Alloca with known type size
        // Note: LLVMGetTargetData/ABISizeOfType may not be available in all LLVM versions.
        // For stack allocations (alloca), we typically don't track them in GlobalAllocTracker
        // anyway, so returning null here is acceptable.
        if (opcode == c.LLVMAlloca) {
            // Alloca instructions are stack-allocated, not heap-allocated.
            // They are not tracked as potential leaks, so we return null.
            return null;
        }

        // Cannot determine size from available information
        return null;
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

    /// Issue candidate builder for two-stage verification.
    /// Passes generate candidates instead of directly reporting issues.
    /// The verifier then decides whether to promote, downgrade, or suppress.
    candidate_builder: ?*CandidateBuilder,

    /// Issue verifier for two-stage confirmation.
    /// All candidates pass through here before becoming real Issues.
    /// null = legacy mode (direct reporting). Set during pipeline init.
    issue_verifier: ?*IssueVerifier,

    /// FFI Contract Database for library-specific alloc/free validation.
    /// Provides lifecycle rules for common C libraries (OpenSSL, SQLite, etc.).
    /// Used by free_validation pass to detect mismatched alloc/free pairs.
    contract_db: FFIContractDB,

    /// Whether to focus on user code only (skip stdlib).
    /// Set from CLI config via Pipeline.setFocusUserCode().
    /// When true, passes should suppress issues from stdlib functions.
    focus_user_code: bool = true,

    /// Language override registry for user-specified function language classifications.
    /// When non-null, passes can check this registry before auto-detecting languages.
    /// Set from CLI config via Pipeline.setLanguageOverrides().
    language_overrides: ?*language_override.LanguageOverrideRegistry = null,

    ir_store: *ModuleIRStore,

    pub fn init(
        allocator: Allocator,
        module: ?ModuleRef,
        fact_store: *FactStore,
        query_engine: *QueryEngine,
        data_flow_graph: *DataFlowGraph,
        ir_store: *ModuleIRStore,
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
            .memory_graph = try memory_graph_mod.MemoryGraph.initWithCapacity(allocator, .{
                .nodes = 16384,
                .call_arg_by_ptr = 80000,
                .call_arg_by_callee = 4096,
                .call_ret_by_callee = 2048,
                .call_ret_by_ptr = 20480,
                .alias_to_canonical = 16384,
                .weak_aliases = 1024,
                .bb_edges = 512,
                .reachability_cache = 16384,
                .func_counters = 4096,
                .content_sources = 16384,
            }),
            .danger_surface_relevant = blk: {
                var m = std.AutoHashMap(u64, void).init(allocator);
                try m.ensureTotalCapacity(8192);
                break :blk m;
            },
            .ffi_auto_relevant = blk: {
                var m = std.AutoHashMap(u64, void).init(allocator);
                try m.ensureTotalCapacity(8192);
                break :blk m;
            },
            .relevant_functions = blk: {
                var m = std.AutoHashMap(u64, void).init(allocator);
                try m.ensureTotalCapacity(4096);
                break :blk m;
            },
            .CallSiteIndex = CallSiteIndex.init(allocator),
            .cross_edge_by_callee = blk: {
                var m = std.StringHashMap(std.ArrayList(u32)).init(allocator);
                try m.ensureTotalCapacity(1024);
                break :blk m;
            },
            .semantics_call_graph = null,
            .ffi_set_cache = null,
            .danger_surfaces_cache = null,
            .danger_path_visited_cache = null,
            .function_surface = blk: {
                var m = std.AutoHashMap(u64, surface_classifier.FunctionSurface).init(allocator);
                try m.ensureTotalCapacity(4096);
                break :blk m;
            },
            .has_ffi_boundary = true,
            .suppression_stats = .{},
            .semantic_resolution = null,
            .evidence = null,
            .interner = null,
            .arena = null,
            .platform_profile = null,
            .resource_summary = null,
            .candidate_builder = null,
            .issue_verifier = null,
            .contract_db = try FFIContractDB.init(allocator),
            .focus_user_code = true,
            .ir_store = ir_store,
        };
    }

    pub fn getNextId(self: *PassContext) u32 {
        return pc_impl.getNextId(self);
    }

    pub fn getValueId(self: *PassContext, ptr: usize) !u32 {
        return pc_impl.getValueId(self, ptr);
    }

    pub fn getNextVulnId(self: *PassContext) u32 {
        return pc_impl.getNextVulnId(self);
    }

    pub fn recordDegradedFunction(self: *PassContext) void {
        return pc_impl.recordDegradedFunction(self);
    }

    pub fn getDegradedFunctionCount(self: *const PassContext) u32 {
        return pc_impl.getDegradedFunctionCount(self);
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
        return pc_impl.getFunctionSurface(self, func_ptr);
    }

    /// Look up language for a function name from the override registry.
    /// Returns null if not in registry (caller should use auto-detect).
    /// This is the primary entry point for all passes to check user-specified
    /// language classifications before falling back to auto-detection.
    pub fn lookupFunctionLanguage(self: *const PassContext, func_name: []const u8) ?language_override.Language {
        return pc_impl.lookupFunctionLanguage(self, func_name);
    }

    /// Get default language from override config.
    /// Returns null if no default is configured.
    /// Used by language_detector as fallback when auto-detection confidence is low.
    pub fn getDefaultLanguage(self: *const PassContext) ?language_override.Language {
        return pc_impl.getDefaultLanguage(self);
    }

    pub fn shouldAnalyzeFunctionSurface(self: *const PassContext, func_ptr: u64) bool {
        return pc_impl.shouldAnalyzeFunctionSurface(self, func_ptr);
    }

    pub fn shouldAnalyzeFunctionSurfaceByName(self: *PassContext, func_name: []const u8, func_ptr: ?u64) bool {
        return pc_impl.shouldAnalyzeFunctionSurfaceByName(self, func_name, func_ptr);
    }

    pub fn classifyFunctionSurface(
        self: *PassContext,
        func_name: []const u8,
        source_location: ?@import("../ir/debug_info.zig").SourceLocation,
    ) noise_filter.ClassificationResult {
        return pc_impl.classifyFunctionSurface(self, func_name, source_location);
    }

    pub fn setModule(self: *PassContext, module: ModuleRef) void {
        return pc_impl.setModule(self, module);
    }

    pub fn hasModule(self: *const PassContext) bool {
        return pc_impl.hasModule(self);
    }

    pub fn getDataFlowGraph(self: *const PassContext) *DataFlowGraph {
        return pc_impl.getDataFlowGraph(self);
    }

    pub fn addNode(self: *PassContext, node: anytype) !void {
        return pc_impl.addNode(self, node);
    }

    pub fn addEdge(self: *PassContext, edge: anytype) !void {
        return pc_impl.addEdge(self, edge);
    }

    pub fn addFFIBoundary(self: *PassContext, boundary: anytype) !void {
        return pc_impl.addFFIBoundary(self, boundary);
    }

    pub fn addIssue(self: *PassContext, issue: *const Issue) !void {
        return pc_impl.addIssue(self, issue);
    }

    pub fn cachedRegistryLookup(self: *PassContext, func_name: []const u8) ?FunctionSemantics {
        return pc_impl.cachedRegistryLookup(self, func_name);
    }

    pub fn cachedZoneLookup(self: *PassContext, func_name: []const u8) ?zone_classifier.ZoneKind {
        return pc_impl.cachedZoneLookup(self, func_name);
    }

    pub fn cacheZoneResult(self: *PassContext, func_name: []const u8, zone: zone_classifier.ZoneKind) void {
        return pc_impl.cacheZoneResult(self, func_name, zone);
    }

    pub fn getOrComputeZone(self: *PassContext, func: *anyopaque, func_name: []const u8) zone_classifier.ZoneKind {
        return pc_impl.getOrComputeZone(self, func, func_name);
    }

    pub fn shouldAnalyzeZone(zone: zone_classifier.ZoneKind) bool {
        return pc_impl.shouldAnalyzeZone(zone);
    }

    pub fn initModuleLanguage(self: *PassContext, module_ref: ?ModuleRef) void {
        return pc_impl.initModuleLanguage(self, module_ref);
    }

    pub fn getModuleLanguage(self: *const PassContext) language_detector.LanguageProfile {
        return pc_impl.getModuleLanguage(self);
    }

    pub fn isGoModule(self: *const PassContext) bool {
        return pc_impl.isGoModule(self);
    }
    pub fn isRustModule(self: *const PassContext) bool {
        return pc_impl.isRustModule(self);
    }
    pub fn isZigModule(self: *const PassContext) bool {
        return pc_impl.isZigModule(self);
    }
    pub fn isCModule(self: *const PassContext) bool {
        return pc_impl.isCModule(self);
    }
    pub fn isUnknownModule(self: *const PassContext) bool {
        return pc_impl.isUnknownModule(self);
    }

    pub fn channelFFIBoundary(self: *const PassContext) ChannelMode {
        return pc_impl.channelFFIBoundary(self);
    }
    pub fn channelPtrLifetime(self: *const PassContext) ChannelMode {
        return pc_impl.channelPtrLifetime(self);
    }
    pub fn channelCallbackEscape(self: *const PassContext) ChannelMode {
        return pc_impl.channelCallbackEscape(self);
    }
    pub fn channelPointerOwnership(self: *const PassContext) ChannelMode {
        return pc_impl.channelPointerOwnership(self);
    }

    /// R7.2: Channel mode for analysis pass gating.
    pub const ChannelMode = enum {
        full,
        limited,
        skip,
    };

    pub fn getOrComputeZoneByName(self: *PassContext, func_name: []const u8) zone_classifier.ZoneKind {
        return pc_impl.getOrComputeZoneByName(self, func_name);
    }

    pub fn markTainted(self: *PassContext, node_id: u32, source_id: ?u32) !void {
        return pc_impl.markTainted(self, node_id, source_id);
    }

    pub fn isTainted(self: *const PassContext, node_id: u32) bool {
        return pc_impl.isTainted(self, node_id);
    }

    pub fn addCrossLangEdge(self: *PassContext, edge: CrossLangEdge) !void {
        return pc_impl.addCrossLangEdge(self, edge);
    }

    pub fn getCrossLangEdges(self: *const PassContext) []const CrossLangEdge {
        return pc_impl.getCrossLangEdges(self);
    }

    pub fn getCrossEdgeByCallee(self: *const PassContext, callee_name: []const u8) ?*const CrossLangEdge {
        return pc_impl.getCrossEdgeByCallee(self, callee_name);
    }

    pub fn getAllCrossEdgesByCallee(self: *const PassContext, callee_name: []const u8) ?[]const u32 {
        return pc_impl.getAllCrossEdgesByCallee(self, callee_name);
    }

    pub fn isRelevantAlloc(self: *const PassContext, ptr_val: u64) bool {
        return pc_impl.isRelevantAlloc(self, ptr_val);
    }

    pub fn isOnDangerPathFull(self: *PassContext, ptr_val: u64) bool {
        return pc_impl.isOnDangerPathFull(self, ptr_val);
    }

    pub fn markRelevantAlloc(self: *PassContext, ptr_val: u64) !void {
        return pc_impl.markRelevantAlloc(self, ptr_val);
    }

    pub fn markFfiRelevant(self: *PassContext, ptr_val: u64) !void {
        return pc_impl.markFfiRelevant(self, ptr_val);
    }

    pub fn isRelevantFunction(self: *const PassContext, func_ptr: u64) bool {
        return pc_impl.isRelevantFunction(self, func_ptr);
    }

    pub fn markRelevantFunction(self: *PassContext, func_ptr: u64) !void {
        return pc_impl.markRelevantFunction(self, func_ptr);
    }

    pub fn markFunctionFromInst(self: *PassContext, inst_ptr: u64) !void {
        return pc_impl.markFunctionFromInst(self, inst_ptr);
    }

    pub fn internString(self: *PassContext, s: []const u8) ![]const u8 {
        return pc_impl.internString(self, s);
    }

    pub fn enableInterning(self: *PassContext) !void {
        return pc_impl.enableInterning(self);
    }

    pub fn enableArena(self: *PassContext) !void {
        return pc_impl.enableArena(self);
    }

    pub fn arenaAlloc(self: *PassContext) std.mem.Allocator {
        return pc_impl.arenaAlloc(self);
    }

    pub fn resetArena(self: *PassContext) void {
        return pc_impl.resetArena(self);
    }

    pub fn isZigStdlibFunction(self: *const PassContext, func_name: []const u8) bool {
        return pc_impl.isZigStdlibFunction(self, func_name);
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
    return switch (sev) {
        .low => .low,
        .medium => .medium,
        .high => .high,
        .critical => .critical,
    };
}
