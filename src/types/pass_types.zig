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
const language_detector = @import("../semantics/language_detector.zig");
const ir_evidence = @import("../ir/ir_evidence.zig");
const issue_suppression = @import("../pass/analysis/noise/issue_suppression.zig");
const Issue = @import("../diag/issue.zig").Issue;
const FunctionSemantics = @import("../registry/semantic_registry.zig").FunctionSemantics;
const pc_impl = @import("../pass/pass_context_impl.zig");

const resource_summary_mod = @import("../semantics/resource/function_summary.zig");
pub const SummaryStore = resource_summary_mod.SummaryStore;

const resource_candidate_mod = @import("../pass/analysis/resource/issue_candidate_builder.zig");
pub const CandidateBuilder = resource_candidate_mod.CandidateBuilder;
const resource_verifier_mod = @import("../pass/analysis/resource/issue_verifier.zig");
pub const IssueVerifier = resource_verifier_mod.IssueVerifier;

const contract_db_mod = @import("../resource/ffi_contract_db.zig");
pub const FFIContractDB = contract_db_mod.FFIContractDB;
const language_override = @import("../config/language_override.zig");

const ir_store_mod = @import("../ir/ir_store.zig");
pub const ModuleIRStore = ir_store_mod.ModuleIRStore;

const pass_defs = @import("pass_defs.zig");
pub const PassKind = pass_defs.PassKind;
pub const CrossLangEdge = pass_defs.CrossLangEdge;
pub const CallSiteIndex = pass_defs.CallSiteIndex;
pub const CallSite = pass_defs.CallSite;
pub const GlobalAllocTracker = pass_defs.GlobalAllocTracker;
pub const Colors = pass_defs.Colors;
pub const DiagnosticWriter = pass_defs.DiagnosticWriter;

const lang_types = @import("../lang/language_types.zig");
pub const ChannelMode = lang_types.ChannelMode;

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
    has_ffi_boundary: bool = false,
    suppression_stats: issue_suppression.SuppressionStats,
    semantic_resolution: ?*@import("../semantics/resolution_engine.zig").ResolutionEngine,
    evidence: ?ir_evidence.IREvidence,
    interner: ?StringInterner,
    arena: ?Arena,
    platform_profile: ?@import("../semantics/platform_profile.zig").PlatformProfile,
    resource_summary: ?*SummaryStore,
    candidate_builder: ?*CandidateBuilder,
    issue_verifier: ?*IssueVerifier,
    contract_db: FFIContractDB,
    focus_user_code: bool = true,
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
            .has_ffi_boundary = false,
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
        if (self.evidence) |*ev| ev.deinit();
    }

    pub fn getFunctionSurface(self: *const PassContext, func_ptr: u64) ?surface_classifier.FunctionSurface {
        return pc_impl.getFunctionSurface(self, func_ptr);
    }

    pub fn lookupFunctionLanguage(self: *const PassContext, func_name: []const u8) ?language_override.Language {
        return pc_impl.lookupFunctionLanguage(self, func_name);
    }

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
