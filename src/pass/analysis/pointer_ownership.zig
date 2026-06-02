//! Pointer Ownership Tracking Pass — tracks pointer ownership across FFI boundaries.
//! Detects: cross-language free mismatch, ownership loss, double free risks.
//! v0.3: Memory pool, profiling, BoundaryAnalyzer integration.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../ir/llvm_safe.zig");

const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const Issue = @import("../../diag/issue.zig").Issue;
const Location = @import("../../diag/issue.zig").Location;
const Language = @import("../../diag/issue.zig").FFIBoundary.Language;
const FactKind = @import("../../fact/fact.zig").FactKind;
const SemanticRegistry = @import("../../registry/semantic_registry.zig").SemanticRegistry;
const RiskKind = @import("../../registry/semantic_registry.zig").RiskKind;
const SummaryRegistry = @import("../../dataflow/function_summary.zig").SummaryRegistry;
const PathManager = @import("../../dataflow/path_condition.zig").PathManager;
const PathCondition = @import("../../dataflow/path_condition.zig").PathCondition;
const ValueIdMap = @import("../../dataflow/value_id_map.zig").ValueIdMap;
const MemoryPool = @import("../../perf/memory_pool.zig").MemoryPool;
const Profiler = @import("../../perf/profiler.zig").Profiler;
const ScopedTimer = @import("../../perf/profiler.zig").ScopedTimer;
const lifetime = @import("../../lifetime/root.zig");
const NullCheckRecognizer = @import("../../dataflow/null_check_guard.zig").NullCheckRecognizer;

const alloc_classifier = @import("ptr_lifetime/allocation_classifier.zig");
const cpp_fp = @import("noise/cpp_fp_reduction.zig");
const zone_classifier = @import("../../semantics/zone_classifier.zig");
const noise_filter = @import("../../semantics/noise_filter.zig");
const DebugInfoUtils = @import("../../ir/debug_info.zig").DebugInfoUtils;
const hooks = @import("../../registry/hooks.zig");

const types = @import("../../types/ownership_types.zig");
pub const OwnershipError = types.OwnershipError;
pub const OwnershipViolationType = types.OwnershipViolationType;
pub const AllocSite = types.AllocSite;
pub const OwnershipState = types.OwnershipState;
pub const FreeSite = types.FreeSite;
pub const PointerFlowEdge = types.PointerFlowEdge;
pub const FlowType = types.FlowType;
pub const OwnershipStats = types.OwnershipStats;
pub const OwnershipSource = types.OwnershipSource;
pub const OwnershipMode = types.OwnershipMode;
pub const FFIRelevanceHint = types.FFIRelevanceHint;
pub const OwnershipPassConfig = types.OwnershipPassConfig;
const truncateInstId = types.truncateInstId;
const resolveInstFuncName = types.resolveInstFuncName;
const AllocType = types.AllocType;
const FreeType = types.FreeType;
const isStdlibCall = types.isStdlibCall;
const checkFfiNamePatterns = types.checkFfiNamePatterns;
const canReach = types.canReach;
const findFreePath = types.findFreePath;
const canReachFree = types.canReachFree;
const addFlowEdge = types.addFlowEdge;
const checkDebugMetadataAvailable = types.checkDebugMetadataAvailable;
const markAllocSitesReachingValue = types.markAllocSitesReachingValue;
const isRustFFIRelevantFunction = types.isRustFFIRelevantFunction;

/// Analysis methods extracted to ownership_analysis.zig
const analysis = @import("../../types/ownership_analysis.zig");
const analyzeFunctionForOwnership = analysis.analyzeFunctionForOwnership;
const checkOwnershipTransferForFunction = analysis.checkOwnershipTransferForFunction;
const analyzeInstructionForOwnership = analysis.analyzeInstructionForOwnership;
const buildFlowGraph = analysis.buildFlowGraph;
/// Pointer ownership tracking pass.
pub const PointerOwnershipPass = struct {
    pub const name = "pointer-ownership";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{"ffi-boundary"};

    /// Run ownership tracking analysis.
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) OwnershipError!void {
        var profiler = Profiler.init(ctx.allocator);
        defer {
            profiler.report();
            var buffer: [256]u8 = undefined;
            diag.info("PointerOwnership: {s}", .{profiler.summary(&buffer) catch "N/A"});
            profiler.deinit();
        }
        var _timer: ?ScopedTimer = ScopedTimer.start(&profiler, "total") catch null;
        defer {
            if (_timer) |*t| t.stop() catch {};
        }

        // R7.2 Language Channel Gate
        const own_channel = ctx.channelPointerOwnership();
        if (own_channel == .skip) {
            diag.debug("LANG-SKIP [pointer_ownership]: module is {s}", .{
                @tagName(ctx.getModuleLanguage().language),
            });
            return;
        }
        // FFI Relevance Gate: skip if all cross-lang edges are stdlib calls (~17s saved on pure Rust)
        {
            const cross_edges = ctx.getCrossLangEdges();
            if (cross_edges.len > 0) {
                var has_real_ffi = false;
                for (cross_edges) |edge| {
                    if (!isStdlibCall(edge.callee_name)) {
                        has_real_ffi = true;
                        break;
                    }
                }
                if (!has_real_ffi) {
                    diag.info("PointerOwnership: all {} cross-lang edges are stdlib calls — skipping full analysis", .{cross_edges.len});
                    return;
                }
            }
        }
        if (ctx.module == null) {
            diag.warn("PointerOwnership: No module loaded, skipping", .{});
            return;
        }
        var init_timer: ?ScopedTimer = ScopedTimer.start(&profiler, "init") catch null;
        defer {
            if (init_timer) |*t| t.stop() catch {};
        }

        var id_map = ValueIdMap.init(ctx.allocator);
        defer id_map.deinit();

        var summary_registry = SummaryRegistry.init(ctx.allocator);
        defer summary_registry.deinit();
        summary_registry.initBuiltins() catch {
            diag.warn("PointerOwnership: Failed to init function summaries", .{});
        };

        var alloc_pool = try MemoryPool(AllocSite).init(ctx.allocator);
        defer alloc_pool.deinit();

        var free_pool = try MemoryPool(FreeSite).init(ctx.allocator);
        defer free_pool.deinit();
        var stats = OwnershipStats{};
        var alloc_map = std.AutoHashMap(u32, *AllocSite).init(ctx.allocator);
        defer alloc_map.deinit();
        var free_map = std.AutoHashMap(u32, *FreeSite).init(ctx.allocator);
        defer free_map.deinit();
        var flow_graph = std.AutoHashMap(u32, std.AutoHashMap(u32, void)).init(ctx.allocator);
        defer {
            var iter = flow_graph.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            flow_graph.deinit();
        }

        // OPT #1: Build reverse_flow incrementally during main pass
        var reverse_flow = std.AutoHashMap(u32, std.AutoHashMap(u32, void)).init(ctx.allocator);
        defer {
            var rf_iter = reverse_flow.iterator();
            while (rf_iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            reverse_flow.deinit();
        }
        var boundary_analyzer = lifetime.BoundaryAnalyzer.init(ctx.allocator);
        errdefer boundary_analyzer.deinit();
        defer boundary_analyzer.deinit();
        var lifetime_engine = lifetime.LifetimeEngine.init(ctx.allocator);
        errdefer lifetime_engine.deinit();
        defer lifetime_engine.deinit();
        var null_check_recognizer = NullCheckRecognizer.init(ctx.allocator);
        defer null_check_recognizer.deinit();
        // OPT #2: Cache for isRustFFIRelevantFunction (pure function, LLVM IR immutable)
        var ffi_relevant_cache = std.AutoHashMap(usize, bool).init(ctx.allocator);
        defer ffi_relevant_cache.deinit();
        const mod = ctx.module.?.raw;
        const has_debug_info = checkDebugMetadataAvailable(mod);
        if (!has_debug_info) {
            diag.info("TIP: Rebuild with -g for file/line diagnostics", .{});
        }
        // Pre-populate alloc_map/free_map from 3 data sources:
        // Source 1: MemoryGraph.nodes, Source 2: GlobalAllocTracker.records, Source 3: IR scan
        {
            var mg_freed_count: usize = 0;
            var mg_unfreed_count: usize = 0;

            // Source 1: MemoryGraph — all allocation sites (both freed and unfreed)
            var mg_iter = ctx.memory_graph.nodes.iterator();
            while (mg_iter.next()) |entry| {
                const node = entry.value_ptr.*;

                if (!node.freed) {
                    // UNFREED ALLOCATION — potential leak or valid lifetime
                    mg_unfreed_count += 1;
                    const site = try alloc_pool.alloc();
                    const inst_id_safe = truncateInstId(node.alloc_inst);
                    site.* = .{
                        .inst_id = inst_id_safe,
                        .func_name = resolveInstFuncName(node.alloc_inst),
                        .lang = node.alloc_lang,
                        .alloc_type = .heap, // Default: heap allocation
                        .ptr_value_id = inst_id_safe,
                        .bb_id = 0, // N/A for MemoryGraph-sourced
                        .transferred = (node.zone == .ffi), // Mark FFI transfers
                        .stored_to_struct_field = false,
                        .source = .memory_graph,
                        .debug_file = null,
                        .debug_line = null,
                        .debug_column = null,
                    };
                    try alloc_map.put(inst_id_safe, site);
                    stats.alloc_sites += 1;
                } else if (node.freed_by) |free_inst| {
                    // FREED ALLOCATION (from MemoryGraph — now populated by ptr_lifetime.zig mg.trackFree())
                    mg_freed_count += 1;
                    const fsite = try free_pool.alloc();
                    const freed_inst_id_safe = truncateInstId(free_inst);
                    const alloc_inst_id_safe = truncateInstId(node.alloc_inst);
                    fsite.* = .{
                        .inst_id = freed_inst_id_safe,
                        .func_name = resolveInstFuncName(node.alloc_inst), // was "memory_graph"
                        .lang = node.free_lang orelse node.alloc_lang,
                        .free_type = .free, // Default: standard free
                        .ptr_value_id = alloc_inst_id_safe,
                        .bb_id = 0, // N/A for MemoryGraph-sourced
                        .source = .memory_graph,
                        .debug_file = null,
                        .debug_line = null,
                        .debug_column = null,
                    };
                    try free_map.put(freed_inst_id_safe, fsite);
                    stats.free_sites += 1;
                }
            }

            // Source 1 diagnostics: report MemoryGraph population split
            diag.info("PointerOwnership: Source 1 (MemoryGraph) — {d} unfreed + {d} freed = {d} total nodes", .{
                mg_unfreed_count, mg_freed_count, mg_unfreed_count + mg_freed_count,
            });

            // Source 2: GlobalAllocTracker — supplementary free tracking (per-ptr_id granularity)
            {
                const total_recs = ctx.global_alloc_tracker.records.items.len;
                var gat_freed_count: usize = 0;
                for (ctx.global_alloc_tracker.records.items) |rec| {
                    if (rec.freed) gat_freed_count += 1;
                }
                diag.info("PointerOwnership: Source 2 (GlobalAllocTracker) — {d} records, {d} freed", .{ total_recs, gat_freed_count });
            }
            for (ctx.global_alloc_tracker.records.items) |rec| {
                if (rec.freed) {
                    const free_name = rec.free_func orelse "unknown";
                    const fsite = try free_pool.alloc();
                    // GAT doesn't track free_inst; use 0 as sentinel, ptr_id as key
                    const gat_ptr_id: u32 = @truncate(rec.ptr_id);
                    fsite.* = .{
                        .inst_id = 0, // Sentinel: GAT doesn't track free instruction address
                        .func_name = free_name,
                        .lang = .unknown,
                        .free_type = .free,
                        .ptr_value_id = gat_ptr_id,
                        .bb_id = 0,
                        .source = .global_alloc_tracker,
                        .debug_file = null,
                        .debug_line = null,
                        .debug_column = null,
                    };
                    // Key by ptr_value_id (consistent with Source 1 which keys by freed ptr)
                    if (!free_map.contains(gat_ptr_id)) {
                        try free_map.put(gat_ptr_id, fsite);
                        stats.free_sites += 1;
                    }
                }
            }

            diag.info("PointerOwnership: Pre-populated from MemoryGraph + GlobalAllocTracker — {d} allocs, {d} frees", .{ stats.alloc_sites, stats.free_sites });
        }

        var func = c.LLVMGetFirstFunction(mod);

        var analysis_timer = ScopedTimer.start(&profiler, "analysis") catch |err| {
            diag.debug("PointerOwnership: Failed to start analysis timer: {}", .{err});
            return;
        };
        defer analysis_timer.stop() catch {};

        // Phase R5.3: Initialize Hook system for ownership transfer tracking.
        try hooks.initHookStates(ctx.allocator);
        defer hooks.deinitHookStates();

        // C1: Single-pass detection (was 8 separate traversals, ~5-8× faster)
        var raii_count: u32 = 0;

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            const func_name_raw = c.LLVMGetValueName(func);
            const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";

            const zone = ctx.getOrComputeZone(@ptrCast(func), func_name);
            ctx.zone_stats.record(zone);

            // Skip declarations (extern functions without bodies in this module).
            // PointerOwnership is an intra-procedural pass that scans instructions
            // inside function bodies (alloc/store/load/call/GEP). Declarations have
            // no body to analyze — their effects are handled at call sites within
            // defined (non-declaration) caller functions. Zone classification is
            // recorded above for accurate statistics before skipping.
            if (c.LLVMIsDeclaration(func) != 0) continue;

            // R7.0: Shared zone gate (single source of truth, also used by ffi_boundary).
            if (!PassContext.shouldAnalyzeZone(zone)) {
                diag.debug("ZONE-SKIP [{s}]: {s}", .{ @tagName(zone), func_name });
                continue;
            }

            // INTEGRATION: Use three-layer noise filter (name + path + behavior)
            // Layer 2 uses debug info from the function's source location
            const func_loc = DebugInfoUtils.getFunctionLocation(func);
            const classification = ctx.classifyFunctionSurface(func_name, func_loc);
            if (!classification.origin.shouldReportByDefault()) {
                diag.debug("NOISE-SKIP: {s} is {s} — {s}", .{ func_name, classification.origin.toString(), classification.reason });
                continue;
            }

            // OPT #2: Use cached isRustFFIRelevantFunction result
            const func_ptr = @as(usize, @intFromPtr(func));
            const is_ffi_relevant = if (ffi_relevant_cache.get(func_ptr)) |cached| cached else blk: {
                const result = isRustFFIRelevantFunction(func);
                ffi_relevant_cache.put(func_ptr, result) catch {};
                break :blk result;
            };
            if (!is_ffi_relevant) continue;

            // SRT: Skip Rust Drop/destructor functions (guaranteed safe by Rust ownership)
            if (ctx.semantic_resolution) |engine| {
                if (engine.isSemanticallyRelease(func_name)) {
                    diag.debug("SRT-SKIP: {s} is semantically resolved as release — Rust Drop/destructor, skipping analysis", .{func_name});
                    continue;
                }
            } else {
                diag.info("SRT-DEBUG: ctx.semantic_resolution is NULL for func {s}", .{func_name});
            }

            if (!ctx.isRelevantFunction(@as(u64, @intFromPtr(func)))) {
                // Fallback: analyze .unknown/.ffi zone functions anyway
                const is_fallback_zone = (zone == .unknown or zone == .ffi);
                if (!is_fallback_zone) {
                    diag.debug("RELEVANT-SKIP [{s}]: {s}", .{ @tagName(zone), func_name });
                    continue;
                }
            }

            // Phase R5.3: Reset hook state per function scope
            hooks.resetHookStatesForFunction();

            // Function-level error isolation
            analyzeFunctionForOwnership(
                ctx.allocator,
                func,
                &alloc_map,
                &free_map,
                &flow_graph,
                &reverse_flow,
                &stats,
                has_debug_info,
                &id_map,
                &alloc_pool,
                &free_pool,
                &null_check_recognizer,
            ) catch |err| {
                diag.warn("PointerOwnership: skipped function due to error: {} ({s})", .{ err, func_name });
                ctx.recordDegradedFunction();
                continue;
            };

            // Phase R5.3: Check hook state for end-of-function ownership issues.
            if (hooks.rustUnpairedTransferCount() > 0) {
                diag.warn("PointerOwnership: Unpaired Rust ownership transfer in {s} — potential cross-language leak", .{func_name});
                stats.cross_ffi_transfers += 1;
            }
            if (hooks.pythonUnbalancedDecrefCount() > 0) {
                diag.warn("PointerOwnership: {} unbalanced Py_DECREF(s) in {s}", .{ hooks.pythonUnbalancedDecrefCount(), func_name });
                stats.use_after_frees += @intCast(hooks.pythonUnbalancedDecrefCount());
            }

            // C1 FIX: Perform all detection tasks in single traversal (eliminate 7 redundant passes)
            detectStructMemberStores(func, &alloc_map, &id_map);
            detectRaiiManagedAllocations(func, &alloc_map, &id_map, &raii_count, &ctx.raii_func_set);
            detectMeyersSingletonFunctions(func, &ctx.meyers_singleton_set);
            detectRefCountedContainerFunctions(func, &ctx.rc_container_func_set);
            detectRustFfiPairingFunctions(func, &ctx.rust_into_raw_set, &ctx.rust_from_raw_set);
            detectAsPtrBorrowEscape(ctx, func, diag);

            checkOwnershipTransferForFunction(func, &alloc_map, &reverse_flow, &id_map);
        }

        // C1 FIX: Report detection results (previously in separate passes 4-8)
        if (raii_count > 0) {
            diag.info("RAII: {d} allocations marked as smart-pointer-managed", .{raii_count});
        }
        if (ctx.raii_func_set.count() > 0) {
            diag.info("RAII: {d} functions identified as RAII-managed (skipped)", .{ctx.raii_func_set.count()});
        }
        if (ctx.meyers_singleton_set.count() > 0) {
            diag.info("Meyers: {d} functions identified as singleton init (skipped)", .{ctx.meyers_singleton_set.count()});
        }
        if (ctx.rc_container_func_set.count() > 0) {
            diag.info("RC-Container: {d} functions identified as refcount-managed (skipped)", .{ctx.rc_container_func_set.count()});
        }
        if (ctx.rust_into_raw_set.count() > 0 or ctx.rust_from_raw_set.count() > 0) {
            diag.info("Rust-FFI: {d} into_raw funcs, {d} from_raw funcs detected", .{
                ctx.rust_into_raw_set.count(),
                ctx.rust_from_raw_set.count(),
            });
        }

        var detect_timer = ScopedTimer.start(&profiler, "detect") catch |err| {
            diag.debug("PointerOwnership: Failed to start detect timer: {}", .{err});
            return;
        };
        defer detect_timer.stop() catch {};

        try detectViolations(ctx, &alloc_map, &free_map, &flow_graph, &stats, diag, &boundary_analyzer, &lifetime_engine);

        detectCrossLangAllocMismatch(ctx, &alloc_map, &free_map, &flow_graph, diag);
        detectMemoryIssues(ctx, &alloc_map, &free_map, &flow_graph, &stats, diag);
        detectNullDereferences(ctx, &alloc_map, &null_check_recognizer, &flow_graph, diag);

        if (stats.memory_leaks > 0) {
            diag.info("PointerOwnership: Found {d} memory leaks (formalized as issues)", .{stats.memory_leaks});
        }
        if (stats.double_frees > 0) {
            diag.info("PointerOwnership: Found {d} double-free issues (formalized as issues)", .{stats.double_frees});
        }
        if (stats.use_after_frees > 0) {
            diag.info("PointerOwnership: Found {d} use-after-free issues (formalized as issues)", .{stats.use_after_frees});
        }

        detect_timer.stop() catch {};

        diag.info("PointerOwnership: Found {d} allocations, {d} frees, {d} tracked pointers", .{
            stats.alloc_sites,
            stats.free_sites,
            stats.tracked_pointers,
        });

        if (stats.cross_ffi_transfers > 0) {
            diag.info("PointerOwnership: {d} cross-FFI ownership transfers detected", .{
                stats.cross_ffi_transfers,
            });
        }

        if (stats.violations > 0) {
            diag.err("PointerOwnership: Found {d} ownership violations", .{stats.violations});
        } else {
            diag.info("PointerOwnership: No cross-language ownership violations detected", .{});
            diag.info("  (Checks for Rust-alloc/C-free or C-alloc/Rust-free mismatches)", .{});
        }

        const pool_stats = alloc_pool.stats();
        diag.info("PointerOwnership: Memory pool stats - allocated: {d}, reused: {d}, in_use: {d}", .{
            pool_stats.allocated,
            pool_stats.reused,
            pool_stats.in_use,
        });

        @import("../pass.zig").printZoneSummary(ctx.zone_stats, ctx.data_flow_graph);
    }

    /// Add flow edge → types.addFlowEdge.
    /// canReach → types.canReach.

    // --- Detection & classification delegates (cpp_fp_reduction + alloc_classifier) ---
    fn detectViolations(ctx: *PassContext, am: *std.AutoHashMap(u32, *AllocSite), fm: *std.AutoHashMap(u32, *FreeSite), fg: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)), st: *OwnershipStats, dg: *DiagnosticWriter, ba: *lifetime.BoundaryAnalyzer, le: *lifetime.LifetimeEngine) OwnershipError!void {
        return cpp_fp.detectViolations(ctx, am, fm, fg, st, dg, ba, le);
    }
    fn convertLanguageToHint(lang: Language) lifetime.LanguageHint {
        return alloc_classifier.convertLanguageToHint(lang);
    }
    fn isCrossFFIAllocation(alloc: *const AllocSite) bool {
        return types.isCrossFFIAllocation(alloc.lang);
    }
    fn isAllocationInstruction(inst: c.LLVMValueRef, op: c_uint) bool {
        return analysis.isAllocationInstruction(inst, op);
    }
    fn classifyAllocation(inst: c.LLVMValueRef, op: c_uint) AllocType {
        return analysis.classifyAllocation(inst, op);
    }
    fn identifyLanguageFromCallee(inst: c.LLVMValueRef, op: c_uint) Language {
        return analysis.identifyLanguageFromCallee(inst, op);
    }
    fn isFreeInstruction(inst: c.LLVMValueRef, op: c_uint) bool {
        return analysis.isFreeInstruction(inst, op);
    }
    fn classifyFree(inst: c.LLVMValueRef, op: c_uint) FreeType {
        return analysis.classifyFree(inst, op);
    }
    fn getFunctionName(func: c.LLVMValueRef) []const u8 {
        return analysis.getFunctionName(func);
    }
    fn identifyLanguage(func: c.LLVMValueRef) Language {
        return @import("../../semantics/language_detector.zig").identifyLanguage(func);
    }
    fn isGuardedByNullCheck(fi: c.LLVMValueRef, pvid: u32, pm: *PathManager) bool {
        return cpp_fp.isGuardedByNullCheck(fi, pvid, pm);
    }
    fn detectMemoryIssues(ctx: *PassContext, am: *std.AutoHashMap(u32, *AllocSite), fm: *std.AutoHashMap(u32, *FreeSite), fg: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)), st: *OwnershipStats, dg: *DiagnosticWriter) void {
        cpp_fp.detectMemoryIssues(ctx, am, fm, fg, st, dg);
    }
    fn detectMemoryLeaks(ctx: *PassContext, am: *std.AutoHashMap(u32, *AllocSite), fm: *std.AutoHashMap(u32, *FreeSite), fg: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)), st: *OwnershipStats, dg: *DiagnosticWriter) void {
        cpp_fp.detectMemoryLeaks(ctx, am, fm, fg, st, dg);
    }
    fn isLikelyStructMemberOwnership(fn_: []const u8) bool {
        return cpp_fp.isLikelyStructMemberOwnership(fn_);
    }
    fn detectStructMemberStores(func: c.LLVMValueRef, am: *std.AutoHashMap(u32, *AllocSite), idm: *ValueIdMap) void {
        cpp_fp.detectStructMemberStores(func, am, idm);
    }
    fn isStlInternalFunction(fn_: []const u8) bool {
        return cpp_fp.isStlInternalFunction(fn_);
    }
    fn isCppSpecialMemberFunction(fn_: []const u8) bool {
        return cpp_fp.isCppSpecialMemberFunction(fn_);
    }
    fn isCppAbiInternalFunction(fn_: []const u8) bool {
        return cpp_fp.isCppAbiInternalFunction(fn_);
    }
    fn isMeyersSingletonPattern(fn_: []const u8) bool {
        return cpp_fp.isMeyersSingletonPattern(fn_);
    }
    fn is_likely_intentional_pattern(fn_: []const u8) bool {
        return cpp_fp.is_likely_intentional_pattern(fn_);
    }
    fn detectRaiiManagedAllocations(func: c.LLVMValueRef, am: *std.AutoHashMap(u32, *AllocSite), idm: *ValueIdMap, rs: *u32, rfs: *std.AutoHashMap(usize, void)) void {
        cpp_fp.detectRaiiManagedAllocations(func, am, idm, rs, rfs);
    }
    fn detectMeyersSingletonFunctions(func: c.LLVMValueRef, ms: *std.AutoHashMap(usize, void)) void {
        cpp_fp.detectMeyersSingletonFunctions(func, ms);
    }
    fn detectRefCountedContainerFunctions(func: c.LLVMValueRef, rcs: *std.AutoHashMap(usize, void)) void {
        cpp_fp.detectRefCountedContainerFunctions(func, rcs, cpp_fp.isAllocationByName);
    }
    fn detectRustFfiPairingFunctions(func: c.LLVMValueRef, irs: *std.StringHashMap(void), frs: *std.StringHashMap(void)) void {
        cpp_fp.detectRustFfiPairingFunctions(func, irs, frs);
    }
    fn isAllocationByName(cn: []const u8) bool {
        return cpp_fp.isAllocationByName(cn);
    }
    fn detectNullDereferences(ctx: *PassContext, am: *std.AutoHashMap(u32, *AllocSite), ncr: *NullCheckRecognizer, fg: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)), d: *DiagnosticWriter) void {
        cpp_fp.detectNullDereferences(ctx, am, ncr, fg, d);
    }
    fn detectAsPtrBorrowEscape(ctx: *PassContext, func: c.LLVMValueRef, d: *DiagnosticWriter) void {
        cpp_fp.detectAsPtrBorrowEscape(ctx, func, d);
    }
    fn detectCrossLangAllocMismatch(ctx: *PassContext, am: *std.AutoHashMap(u32, *AllocSite), fm: *std.AutoHashMap(u32, *FreeSite), fg: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)), d: *DiagnosticWriter) void {
        cpp_fp.detectCrossLangAllocMismatch(ctx, am, fm, fg, d);
    }
    fn isNullableAllocation(a: *const AllocSite) bool {
        return cpp_fp.isNullableAllocation(a);
    }
    fn detectDoubleFree(ctx: *PassContext, fm: *std.AutoHashMap(u32, *FreeSite), fg: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)), st: *OwnershipStats, d: *DiagnosticWriter) void {
        cpp_fp.detectDoubleFree(ctx, fm, fg, st, d);
    }
    fn detectUseAfterFree(ctx: *PassContext, fm: *std.AutoHashMap(u32, *FreeSite), fg: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)), st: *OwnershipStats, d: *DiagnosticWriter) void {
        cpp_fp.detectUseAfterFree(ctx, fm, fg, st, d);
    }
    fn hasUseAfterFree(fp: u32, flow: std.AutoHashMap(u32, void), fg: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)), v: *std.AutoHashMap(u32, void)) bool {
        return cpp_fp.hasUseAfterFree(fp, &flow, fg, v);
    }
};
