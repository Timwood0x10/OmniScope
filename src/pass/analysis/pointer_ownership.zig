//! Pointer Ownership Tracking Pass
//!
//! Tracks pointer ownership across FFI boundaries to detect:
//! - Cross-language free mismatch (Rust alloc, C free or vice versa)
//! - Ownership loss when passing pointers across boundaries
//! - Double free risks
//!
//! This pass analyzes LLVM IR to identify allocation and free sites,
//! then tracks ownership state through def-use chains.
//!
//! v0.2 Enhancements:
//! - Inter-procedural analysis via function summaries
//! - Path-sensitive analysis for null check tracking
//!
//! v0.3 Enhancements:
//! - Memory pool for reduced allocation overhead
//! - Profiling for performance analysis
//! - BoundaryAnalyzer integration for cross-language contract checking

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

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

const alloc_classifier = @import("allocation_classifier.zig");
const cpp_fp = @import("cpp_fp_reduction.zig");
const zone_classifier = @import("../../semantics/zone_classifier.zig");
const noise_filter = @import("../../semantics/noise_filter.zig");
const DebugInfoUtils = @import("../../ir/debug_info.zig").DebugInfoUtils;
const hooks = @import("../../registry/hooks.zig");

/// Error type for ownership tracking operations.
pub const OwnershipError = error{
    OutOfMemory,
    NoModule,
    NullPointer,
};

/// Truncate u64 LLVM instruction ID to u32 for use in HashMap keys.
/// LLVM instruction IDs can exceed u32 range in large modules, but we use
/// the truncated value as a hash key rather than an exact identifier.
/// Collisions are possible but rare and acceptable for analysis purposes.
fn truncateInstId(inst_id: u64) u32 {
    return @as(u32, @truncate(inst_id));
}

/// Resolve LLVM instruction pointer (u64) back to its containing function name.
/// MemoryGraph stores instruction pointers as u64; this recovers the function name
/// via LLVM's instruction→basic block→function chain.
fn resolveInstFuncName(inst: u64) []const u8 {
    if (inst == 0) return "memory_graph";
    const inst_ref: c.LLVMValueRef = @ptrFromInt(inst);
    const bb = c.LLVMGetInstructionParent(inst_ref);
    if (@intFromPtr(bb) == 0) return "memory_graph";
    const func = c.LLVMGetBasicBlockParent(bb);
    if (@intFromPtr(func) == 0) return "memory_graph";
    const name = c.LLVMGetValueName(func);
    if (@intFromPtr(name) == 0) return "memory_graph";
    return std.mem.span(name);
}

/// Ownership violation types detected by this pass.
pub const OwnershipViolationType = enum(u8) {
    cross_lang_free_mismatch,
    ownership_lost,
    double_free_risk,
    rust_drop_after_ffi_transfer,
    memory_leak,
    use_after_free,
    null_dereference,
};

/// Allocation site information.
pub const AllocSite = struct {
    inst_id: u32,
    func_name: []const u8,
    lang: Language,
    alloc_type: AllocType,
    ptr_value_id: u32,
    bb_id: usize,
    transferred: bool = false,
    stored_to_struct_field: bool = false,
    debug_file: ?[]const u8,
    debug_line: ?u32,
    debug_column: ?u32,
};

/// Allocation types (from allocation_classifier.zig).
const AllocType = alloc_classifier.AllocType;

/// Pointer ownership state.
pub const OwnershipState = enum(u8) {
    live,
    ownership_transferred,
    freed,
    leaked,
};

/// Free site information.
pub const FreeSite = struct {
    inst_id: u32,
    func_name: []const u8,
    lang: Language,
    free_type: FreeType,
    ptr_value_id: u32,
    bb_id: usize,
    debug_file: ?[]const u8,
    debug_line: ?u32,
    debug_column: ?u32,
};

/// Free types (from allocation_classifier.zig).
const FreeType = alloc_classifier.FreeType;

/// Pointer flow edge - tracks how pointers move through the program.
pub const PointerFlowEdge = struct {
    from_inst: u32,
    to_inst: u32,
    flow_type: FlowType,
};

pub const FlowType = enum(u8) {
    assignment,
    argument,
    return_value,
    store,
    load,
};

/// Statistics for ownership tracking.
pub const OwnershipStats = struct {
    alloc_sites: u32 = 0,
    free_sites: u32 = 0,
    tracked_pointers: u32 = 0,
    cross_ffi_transfers: u32 = 0,
    violations: u32 = 0,
    memory_leaks: u32 = 0,
    double_frees: u32 = 0,
    use_after_frees: u32 = 0,
};

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

        var boundary_analyzer = lifetime.BoundaryAnalyzer.init(ctx.allocator);
        errdefer boundary_analyzer.deinit();
        defer boundary_analyzer.deinit();

        var lifetime_engine = lifetime.LifetimeEngine.init(ctx.allocator);
        errdefer lifetime_engine.deinit();
        defer lifetime_engine.deinit();

        var null_check_recognizer = NullCheckRecognizer.init(ctx.allocator);
        defer null_check_recognizer.deinit();

        const mod = ctx.module.?.raw;

        const has_debug_info = checkDebugMetadataAvailable(mod);
        if (!has_debug_info) {
            diag.info("TIP: Rebuild with -g for file/line diagnostics", .{});
        }

        // CRITICAL FIX (2026-05-05 → 2026-05-06): Pre-populate alloc_map/free_map.
        // Previously, pointer_ownership.zig relied solely on IR scanning + filters,
        // which caused 0 allocations/0 frees because zone gate / noise filter /
        // isRustFFIRelevantFunction blocked ALL functions.
        //
        // v0.1.7 RESOLVED: We use THREE synchronized data sources:
        //   Source 1: MemoryGraph.nodes — allocation sites + freed allocations
        //     (ptr_lifetime.zig now calls mg.trackFree() at 5 sites, populating .freed/.freed_by)
        //   Source 2: GlobalAllocTracker.records — supplementary free tracking
        //     (covers cases where ptr_lifetime.zig's markFired() was called but MG sync missed)
        //   Source 3: IR-level free instruction scan — fallback for any free not caught above
        //
        // Data flow: ptr_lifetime.zig → {MemoryGraph.freed, GlobalAllocTracker.freed} → here
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

            // Source 2: GlobalAllocTracker — supplementary free tracking.
            // RESOLVED (v0.1.7): MemoryGraph.freed_by IS now populated by ptr_lifetime.zig
            // (mg.trackFree() called at 5 sites: alias-propagation×2, realloc, main-free, canonical-alias).
            // However, GlobalAllocTracker remains valuable as a SECONDARY source because:
            //   - It tracks frees at a different granularity (per-ptr_id vs per-instruction)
            //   - It may catch edge cases where IR-scan misses non-standard free patterns
            //   - It provides cross-validation between independent tracking systems
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
                    // This allocation was freed — create FreeSite entry
                    const free_name = rec.free_func orelse "unknown";
                    const fsite = try free_pool.alloc();
                    // NOTE: GlobalAllocTracker.AllocRecord does NOT store free_inst (only ptr_id + free_func).
                    // We use ptr_id as both ptr_value_id (correct: this is the freed pointer) and
                    // as the free_map key (acceptable: GAT's natural key is per-allocation).
                    // For inst_id, we use 0 (sentinel) since the actual free instruction address is
                    // not tracked by GlobalAllocTracker. This is semantically distinct from Source 1/3
                    // which have real instruction-level addresses.
                    const gat_ptr_id: u32 = @truncate(rec.ptr_id);
                    fsite.* = .{
                        .inst_id = 0, // Sentinel: GAT doesn't track free instruction address
                        .func_name = free_name,
                        .lang = .unknown,
                        .free_type = .free,
                        .ptr_value_id = gat_ptr_id,
                        .bb_id = 0,
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

            // Source 3: IR-level free instruction scan (bypasses upstream tracking gaps).
            // CRITICAL FIX (v0.1.7): Both MemoryGraph.freed_by (Source 1) and
            // GlobalAllocTracker.records (Source 2) have near-zero coverage because:
            //   - MemoryGraph.freed_by is never populated by ptr_lifetime.zig
            //   - GlobalAllocTracker only tracks allocations where insertAlloc() was called
            //
            // This source directly scans the LLVM IR for free/dealloc call instructions,
            // giving us accurate free counts independent of any upstream pass's tracking.
            {
                var ir_func = c.LLVMGetFirstFunction(mod);
                while (@intFromPtr(ir_func) != 0) : (ir_func = c.LLVMGetNextFunction(ir_func)) {
                    if (c.LLVMIsDeclaration(ir_func) != 0) continue;
                    var bb = c.LLVMGetFirstBasicBlock(ir_func);
                    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                        var inst = c.LLVMGetFirstInstruction(bb);
                        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                            const opcode = c.LLVMGetInstructionOpcode(inst);
                            if (opcode == c.LLVMCall and isFreeInstruction(inst, opcode)) {
                                const ptr_arg = c.LLVMGetOperand(inst, 0);
                                if (@intFromPtr(ptr_arg) == 0) continue;
                                const ptr_id: u32 = id_map.getOrPutId(@intFromPtr(ptr_arg)) catch continue;
                                const fn_name_raw = c.LLVMGetValueName(ir_func);
                                const fn_name = if (fn_name_raw != null) std.mem.span(fn_name_raw) else "unknown";
                                const fsite = try free_pool.alloc();
                                fsite.* = .{
                                    .inst_id = id_map.getOrPutId(@intFromPtr(inst)) catch ptr_id,
                                    .func_name = fn_name,
                                    .lang = identifyLanguageFromCallee(inst, opcode),
                                    .free_type = classifyFree(inst, opcode),
                                    .ptr_value_id = ptr_id,
                                    .bb_id = id_map.getOrPutId(@intFromPtr(bb)) catch 0,
                                    .debug_file = null,
                                    .debug_line = null,
                                    .debug_column = null,
                                };
                                if (!free_map.contains(ptr_id)) {
                                    try free_map.put(ptr_id, fsite);
                                    stats.free_sites += 1;
                                }
                            }
                        }
                    }
                }
                diag.info("PointerOwnership: Source 3 (IR scan) added {d} frees — total now {d}", .{ stats.free_sites, stats.free_sites });
            }

            diag.info("PointerOwnership: Pre-populated from MemoryGraph + GlobalAllocTracker + IR-scan — {d} allocs, {d} frees", .{ stats.alloc_sites, stats.free_sites });
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

        // C1 FIX: Merge 8 independent traversals into single pass.
        // Previously: 8 separate loops over all functions (8× LLVM C API overhead).
        // Now: Single loop performing all 8 detection tasks per function.
        // Performance improvement: ~5-8× on large modules (1000+ functions).
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
            const classification = noise_filter.classifyFunctionFull(func_name, null, func_loc, null);
            if (!classification.origin.shouldReportByDefault()) {
                diag.debug("NOISE-SKIP: {s} is {s} — {s}", .{ func_name, classification.origin.toString(), classification.reason });
                continue;
            }

            if (!isRustFFIRelevantFunction(func)) continue;

            if (!ctx.isRelevantFunction(@as(u64, @intFromPtr(func)))) {
                // v0.1.7 FIX (break point 5): Fallback for when DangerSurfacePass produced
                // no relevant functions (common in Rust FFI where CrossLangEdge detection
                // missed unmangled wrappers). If the function's zone is .unknown or .ffi,
                // analyze it anyway — these are precisely the functions we need to check.
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
        }

        {
            var reverse_flow = std.AutoHashMap(u32, std.AutoHashMap(u32, void)).init(ctx.allocator);
            defer {
                var rf_iter = reverse_flow.iterator();
                while (rf_iter.next()) |entry| {
                    entry.value_ptr.*.deinit();
                }
                reverse_flow.deinit();
            }

            {
                var fg_iter = flow_graph.iterator();
                while (fg_iter.next()) |entry| {
                    const source_id = entry.key_ptr.*;
                    var dest_iter = entry.value_ptr.*.iterator();
                    while (dest_iter.next()) |dest_entry| {
                        const dest_id = dest_entry.key_ptr.*;
                        const rf_entry = reverse_flow.getOrPut(dest_id) catch continue;
                        if (!rf_entry.found_existing) {
                            rf_entry.value_ptr.* = std.AutoHashMap(u32, void).init(ctx.allocator);
                        }
                        rf_entry.value_ptr.*.put(source_id, {}) catch {};
                    }
                }
            }

            var func2 = c.LLVMGetFirstFunction(mod);
            while (@intFromPtr(func2) != 0) : (func2 = c.LLVMGetNextFunction(func2)) {
                if (c.LLVMIsDeclaration(func2) != 0) continue;
                checkOwnershipTransferForFunction(func2, &alloc_map, &reverse_flow, &id_map);
            }
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

    /// Check if debug metadata is available in the module.
    fn checkDebugMetadataAvailable(mod: c.LLVMModuleRef) bool {
        var md_node = c.LLVMGetFirstNamedMetadata(mod);
        while (@intFromPtr(md_node) != 0) {
            var name_len: usize = 0;
            const name_ptr = c.LLVMGetNamedMetadataName(md_node, &name_len);
            if (@intFromPtr(name_ptr) != 0) {
                const md_name = name_ptr[0..name_len];
                if (std.mem.startsWith(u8, md_name, "llvm.dbg") or
                    std.mem.startsWith(u8, md_name, "!dbg"))
                {
                    return true;
                }
            }
            md_node = c.LLVMGetNextNamedMetadata(md_node);
        }
        return false;
    }

    /// Analyze a function for allocation and free sites.
    fn analyzeFunctionForOwnership(
        allocator: std.mem.Allocator,
        func: c.LLVMValueRef,
        alloc_map: *std.AutoHashMap(u32, *AllocSite),
        free_map: *std.AutoHashMap(u32, *FreeSite),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        stats: *OwnershipStats,
        has_debug_info: bool,
        id_map: *ValueIdMap,
        alloc_pool: *MemoryPool(AllocSite),
        free_pool: *MemoryPool(FreeSite),
        null_check_recognizer: *NullCheckRecognizer,
    ) OwnershipError!void {
        const func_name = getFunctionName(func);

        null_check_recognizer.recognizeInFunction(func, id_map) catch {}; // error set mismatch; best-effort

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                try analyzeInstructionForOwnership(
                    allocator,
                    inst,
                    func_name,
                    alloc_map,
                    free_map,
                    flow_graph,
                    stats,
                    has_debug_info,
                    id_map,
                    alloc_pool,
                    free_pool,
                );
            }
        }
    }

    /// P0-C: Rust-Focused FFI Filtering (v0.1.7 relaxed).
    /// For Rust-mangled functions (_R* or $*), analyze if the function:
    ///   A) Calls an extern/"C" declaration directly (original check)
    ///   B) Uses indirect calls through function pointers (FFI callback pattern)
    ///   C) Has name suggesting FFI relevance (ffi/extern/bindgen/cinterop)
    ///
    /// This eliminates ~90% of false positives from Rust drop glue,
    /// closure cleanup, and iterator patterns while catching indirect FFI.
    fn isRustFFIRelevantFunction(func: c.LLVMValueRef) bool {
        const func_name_raw = c.LLVMGetValueName(func);
        if (func_name_raw == null) return true;
        const func_name = std.mem.span(func_name_raw);

        const is_rust = (std.mem.indexOf(u8, func_name, "_R") != null or
            std.mem.indexOf(u8, func_name, "$") != null);
        if (!is_rust) return true;

        // Fast path: name-based FFI hints (avoids expensive IR scan for obvious cases).
        const ffi_name_patterns = [_][]const u8{
            "_ffi",     "_extern",   "_cinterop", "_bindgen",
            "_foreign", "_abi",      "_marshal",  "_syscall",
            "_invoke",  "_callback", "_native",   "_interop",
        };
        for (ffi_name_patterns) |pat| {
            if (std.mem.indexOf(u8, func_name, pat) != null) return true;
        }

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (c.LLVMGetInstructionOpcode(inst) == c.LLVMCall) {
                    const num_ops = c.LLVMGetNumOperands(inst);
                    if (num_ops == 0) continue;
                    const callee_val = c.LLVMGetOperand(inst, @intCast(num_ops - 1));
                    if (@intFromPtr(callee_val) == 0) continue;
                    // Case A: Direct call to extern declaration.
                    if (c.LLVMIsDeclaration(callee_val) != 0) return true;
                    // Case B: Indirect call through function pointer.
                    // Callee is neither a declaration nor a defined function → it's a value
                    // (function pointer loaded from memory). This is the classic FFI callback pattern:
                    //   %fn_ptr = load void ()*, void ()** @callback
                    //   call void %fn_ptr()  ← callee_val is %fn_ptr, not a function
                    if (c.LLVMIsAFunction(callee_val) == null) return true;
                }
            }
        }
        return false;
    }

    /// Check if allocation results in this function are transferred to the caller
    /// via return value or output parameter. Marks matching AllocSite entries.
    ///
    /// Pattern A (return-value transfer):
    ///   %p = call i8* @malloc(i64 %s)
    ///   ...
    ///   ret i8* %p          ; ownership transferred to caller
    ///
    /// Pattern B (output-param transfer):
    ///   %p = call i8* @malloc(i64 %s)
    ///   ...
    ///   store i8* %p, i8** %arg1  ; ownership transferred via output param
    fn checkOwnershipTransferForFunction(
        func: c.LLVMValueRef,
        alloc_map: *std.AutoHashMap(u32, *AllocSite),
        reverse_flow: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        id_map: *ValueIdMap,
    ) void {
        const num_params = c.LLVMCountParams(func);

        var param_value_ids: [32]u32 = undefined;
        var param_count: usize = 0;
        {
            var i: c_uint = 0;
            while (i < num_params and i < 16) : (i += 1) {
                const param = c.LLVMGetParam(func, i);
                if (@intFromPtr(param) != 0) {
                    param_value_ids[param_count] = id_map.getOrPutId(@intFromPtr(param)) catch continue;
                    param_count += 1;
                }
            }
        }

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                if (opcode == c.LLVMRet) {
                    const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
                    if (num_operands > 0) {
                        const ret_val = c.LLVMGetOperand(inst, 0);
                        if (@intFromPtr(ret_val) != 0) {
                            const ret_value_id = id_map.getOrPutId(@intFromPtr(ret_val)) catch continue;
                            markAllocSitesReachingValue(alloc_map, reverse_flow, ret_value_id) catch {};
                        }
                    }
                }

                if (opcode == c.LLVMStore) {
                    if (c.LLVMGetNumOperands(inst) >= 2) {
                        const store_val = c.LLVMGetOperand(inst, 0);
                        const store_ptr = c.LLVMGetOperand(inst, 1);
                        if (@intFromPtr(store_val) != 0 and @intFromPtr(store_ptr) != 0) {
                            const ptr_value_id = id_map.getOrPutId(@intFromPtr(store_ptr)) catch continue;
                            for (param_value_ids[0..param_count]) |param_id| {
                                if (ptr_value_id == param_id) {
                                    const val_value_id = id_map.getOrPutId(@intFromPtr(store_val)) catch continue;
                                    markAllocSitesReachingValue(alloc_map, reverse_flow, val_value_id) catch {};
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Mark all AllocSite entries whose allocated value can reach the given target value
    /// via the flow graph. Uses REVERSE traversal with pre-built predecessor map.
    fn markAllocSitesReachingValue(
        alloc_map: *std.AutoHashMap(u32, *AllocSite),
        reverse_flow: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        target_value_id: u32,
    ) !void {
        var visited = std.AutoHashMap(u32, void).init(alloc_map.allocator);
        defer visited.deinit();

        var bfs_queue = try std.ArrayList(u32).initCapacity(alloc_map.allocator, 32);
        defer bfs_queue.deinit(alloc_map.allocator);
        try bfs_queue.append(alloc_map.allocator, target_value_id);

        while (bfs_queue.items.len > 0) {
            const current = bfs_queue.orderedRemove(0);

            if (visited.contains(current)) continue;
            // Propagate error instead of silent return - ensures complete traversal
            try visited.put(current, {});

            if (alloc_map.get(current)) |site| {
                site.transferred = true;
            }

            if (reverse_flow.get(current)) |preds| {
                var pred_iter = preds.iterator();
                while (pred_iter.next()) |entry| {
                    const pred_id = entry.key_ptr.*;
                    if (!visited.contains(pred_id)) {
                        try bfs_queue.append(alloc_map.allocator, pred_id);
                    }
                }
            }
        }
    }

    /// Analyze a single instruction for ownership-relevant operations.
    fn analyzeInstructionForOwnership(
        allocator: std.mem.Allocator,
        inst: c.LLVMValueRef,
        func_name: []const u8,
        alloc_map: *std.AutoHashMap(u32, *AllocSite),
        free_map: *std.AutoHashMap(u32, *FreeSite),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        stats: *OwnershipStats,
        has_debug_info: bool,
        id_map: *ValueIdMap,
        alloc_pool: *MemoryPool(AllocSite),
        free_pool: *MemoryPool(FreeSite),
    ) OwnershipError!void {
        const opcode = c.LLVMGetInstructionOpcode(inst);
        const inst_id = id_map.getOrPutId(@intFromPtr(inst)) catch return;
        _ = has_debug_info;

        try buildFlowGraph(allocator, inst, opcode, flow_graph, id_map);

        // Hook dispatch for call instructions (fixes break point 2+3: dead hook code).
        // Previously rustOwnershipHook was never called because analyzeInstructionForOwnership
        // only did alloc/free pattern matching without any hook dispatch path.
        // Now we create a HookContext and invoke the hook system for each LLVMCall.
        if (opcode == c.LLVMCall) {
            const num_ops = c.LLVMGetNumOperands(inst);
            if (num_ops > 0) {
                const callee_val = c.LLVMGetOperand(inst, @intCast(num_ops - 1));
                if (@intFromPtr(callee_val) != 0) {
                    const callee_name_raw = c.LLVMGetValueName(callee_val);
                    const callee_name = if (callee_name_raw != null)
                        std.mem.span(callee_name_raw)
                    else
                        "unknown";

                    // Get first argument pointer value (for into_raw/from_raw pairing).
                    var first_arg_ptr_val: u64 = 0;
                    if (num_ops >= 1) {
                        const arg0 = c.LLVMGetOperand(inst, 0);
                        if (@intFromPtr(arg0) != 0) {
                            first_arg_ptr_val = @as(u64, @intFromPtr(arg0));
                        }
                    }

                    var hook_ctx = @import("../../registry/types.zig").HookContext{
                        .inst = @ptrCast(inst),
                        .callee_name = callee_name,
                        .opcode = opcode,
                        .language = "rust",
                        .first_arg_ptr_val = first_arg_ptr_val,
                    };
                    _ = hooks.rustOwnershipHook(&hook_ctx);
                }
            }
        }

        if (isAllocationInstruction(inst, opcode)) {
            const alloc_type = classifyAllocation(inst, opcode);
            const callee_lang = identifyLanguageFromCallee(inst, opcode);
            const site = try alloc_pool.alloc();
            const parent_bb = c.LLVMGetInstructionParent(inst);
            site.* = .{
                .inst_id = inst_id,
                .func_name = func_name,
                .lang = callee_lang,
                .alloc_type = alloc_type,
                .ptr_value_id = inst_id,
                .bb_id = id_map.getOrPutId(@intFromPtr(parent_bb)) catch inst_id,
                .debug_file = null,
                .debug_line = null,
                .debug_column = null,
            };

            try alloc_map.put(inst_id, site);
            stats.alloc_sites += 1;
            stats.tracked_pointers += 1;
        }

        if (isFreeInstruction(inst, opcode)) {
            const free_type = classifyFree(inst, opcode);
            const callee_lang = identifyLanguageFromCallee(inst, opcode);
            const ptr_arg = c.LLVMGetOperand(inst, 0);
            const ptr_value_id: u32 = if (@intFromPtr(ptr_arg) != 0)
                id_map.getOrPutId(@intFromPtr(ptr_arg)) catch return
            else
                inst_id;

            const site = try free_pool.alloc();
            const parent_bb = c.LLVMGetInstructionParent(inst);
            site.* = .{
                .inst_id = inst_id,
                .func_name = func_name,
                .lang = callee_lang,
                .free_type = free_type,
                .ptr_value_id = ptr_value_id,
                .bb_id = id_map.getOrPutId(@intFromPtr(parent_bb)) catch inst_id,
                .debug_file = null,
                .debug_line = null,
                .debug_column = null,
            };

            try free_map.put(inst_id, site);
            stats.free_sites += 1;
        }
    }

    /// Build a flow graph to track pointer movement through the program.
    fn buildFlowGraph(
        allocator: std.mem.Allocator,
        inst: c.LLVMValueRef,
        opcode: c_uint,
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        id_map: *ValueIdMap,
    ) OwnershipError!void {
        const inst_id = id_map.getOrPutId(@intFromPtr(inst)) catch return;

        switch (opcode) {
            c.LLVMStore => {
                const value = c.LLVMGetOperand(inst, 0);
                const ptr = c.LLVMGetOperand(inst, 1);
                if (@intFromPtr(value) != 0 and @intFromPtr(ptr) != 0) {
                    const value_id = id_map.getOrPutId(@intFromPtr(value)) catch return;
                    const ptr_id = id_map.getOrPutId(@intFromPtr(ptr)) catch return;
                    try addFlowEdge(allocator, value_id, ptr_id, flow_graph);
                }
            },
            c.LLVMLoad => {},
            c.LLVMBitCast, c.LLVMPtrToInt, c.LLVMIntToPtr => {
                const operand = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(operand) != 0) {
                    const operand_id = id_map.getOrPutId(@intFromPtr(operand)) catch return;
                    try addFlowEdge(allocator, operand_id, inst_id, flow_graph);
                }
            },
            c.LLVMCall => {
                const num_ops = c.LLVMGetNumOperands(inst);
                var i: u32 = 0;
                while (i < num_ops) : (i += 1) {
                    const op = c.LLVMGetOperand(inst, i);
                    if (@intFromPtr(op) != 0) {
                        const op_id = id_map.getOrPutId(@intFromPtr(op)) catch continue;
                        try addFlowEdge(allocator, op_id, inst_id, flow_graph);
                    }
                }
            },
            c.LLVMPHI => {
                const num_incoming = c.LLVMCountIncoming(inst);
                var i: u32 = 0;
                while (i < num_incoming) : (i += 1) {
                    const incoming = c.LLVMGetIncomingValue(inst, i);
                    if (@intFromPtr(incoming) != 0) {
                        const incoming_id = id_map.getOrPutId(@intFromPtr(incoming)) catch continue;
                        try addFlowEdge(allocator, incoming_id, inst_id, flow_graph);
                    }
                }
            },
            c.LLVMSelect => {
                const true_val = c.LLVMGetOperand(inst, 1);
                const false_val = c.LLVMGetOperand(inst, 2);
                if (@intFromPtr(true_val) != 0) {
                    const true_id = id_map.getOrPutId(@intFromPtr(true_val)) catch return;
                    try addFlowEdge(allocator, true_id, inst_id, flow_graph);
                }
                if (@intFromPtr(false_val) != 0) {
                    const false_id = id_map.getOrPutId(@intFromPtr(false_val)) catch return;
                    try addFlowEdge(allocator, false_id, inst_id, flow_graph);
                }
            },
            c.LLVMGetElementPtr => {
                const base_ptr = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(base_ptr) != 0) {
                    const base_id = id_map.getOrPutId(@intFromPtr(base_ptr)) catch return;
                    try addFlowEdge(allocator, base_id, inst_id, flow_graph);
                }
            },
            c.LLVMExtractValue => {
                const aggregate = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(aggregate) != 0) {
                    const agg_id = id_map.getOrPutId(@intFromPtr(aggregate)) catch return;
                    try addFlowEdge(allocator, agg_id, inst_id, flow_graph);
                }
            },
            c.LLVMInsertValue => {
                const aggregate = c.LLVMGetOperand(inst, 0);
                const value = c.LLVMGetOperand(inst, 1);
                if (@intFromPtr(aggregate) != 0) {
                    const agg_id = id_map.getOrPutId(@intFromPtr(aggregate)) catch return;
                    try addFlowEdge(allocator, agg_id, inst_id, flow_graph);
                }
                if (@intFromPtr(value) != 0) {
                    const val_id = id_map.getOrPutId(@intFromPtr(value)) catch return;
                    try addFlowEdge(allocator, val_id, inst_id, flow_graph);
                }
            },
            else => {},
        }
    }

    /// Add a flow edge to the graph.
    fn addFlowEdge(
        allocator: std.mem.Allocator,
        from: u32,
        to: u32,
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    ) !void {
        if (from == to) return; // Skip self-edges

        const entry = try flow_graph.getOrPut(from);
        if (!entry.found_existing) {
            entry.value_ptr.* = std.AutoHashMap(u32, void).init(allocator);
        }
        try entry.value_ptr.put(to, {});
    }

    /// Check if a value can reach another value through the flow graph.
    fn canReach(
        flow_graph: *const std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        from: u32,
        to: u32,
        visited: *std.AutoHashMap(u32, void),
    ) bool {
        if (from == to) return true;

        if (visited.contains(from)) return false;
        visited.put(from, {}) catch return false;

        const edges = flow_graph.get(from) orelse return false;
        var iter = edges.iterator();
        while (iter.next()) |entry| {
            if (canReach(flow_graph, entry.key_ptr.*, to, visited)) {
                return true;
            }
        }
        return false;
    }

    // --- Detection passes (delegated to cpp_fp_reduction.zig) ---

    fn detectViolations(
        ctx: *PassContext,
        alloc_map: *std.AutoHashMap(u32, *AllocSite),
        free_map: *std.AutoHashMap(u32, *FreeSite),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        stats: *OwnershipStats,
        diag: *DiagnosticWriter,
        boundary_analyzer: *lifetime.BoundaryAnalyzer,
        lifetime_engine: *lifetime.LifetimeEngine,
    ) OwnershipError!void {
        return cpp_fp.detectViolations(ctx, alloc_map, free_map, flow_graph, stats, diag, boundary_analyzer, lifetime_engine);
    }
    fn convertLanguageToHint(lang: Language) lifetime.LanguageHint {
        return alloc_classifier.convertLanguageToHint(lang);
    }
    fn isCrossFFIAllocation(alloc: *const AllocSite) bool {
        return alloc.lang != .unknown and alloc.lang != .c;
    }
    fn isAllocationInstruction(inst: c.LLVMValueRef, opcode: c_uint) bool {
        return alloc_classifier.isAllocationInstruction(inst, opcode);
    }
    fn classifyAllocation(inst: c.LLVMValueRef, opcode: c_uint) AllocType {
        return alloc_classifier.classifyAllocation(inst, opcode);
    }
    fn identifyLanguageFromCallee(inst: c.LLVMValueRef, opcode: c_uint) Language {
        return alloc_classifier.identifyLanguageFromCallee(inst, opcode);
    }
    fn isFreeInstruction(inst: c.LLVMValueRef, opcode: c_uint) bool {
        return alloc_classifier.isFreeInstruction(inst, opcode);
    }
    fn classifyFree(inst: c.LLVMValueRef, opcode: c_uint) FreeType {
        return alloc_classifier.classifyFree(inst, opcode);
    }
    fn getFunctionName(func: c.LLVMValueRef) []const u8 {
        return cpp_fp.getFunctionName(func);
    }
    fn identifyLanguage(func: c.LLVMValueRef) Language {
        return @import("../../semantics/language_detector.zig").identifyLanguage(func);
    }
    fn isGuardedByNullCheck(free_inst: c.LLVMValueRef, ptr_value_id: u32, path_manager: *PathManager) bool {
        return cpp_fp.isGuardedByNullCheck(free_inst, ptr_value_id, path_manager);
    }
    fn detectMemoryIssues(ctx: *PassContext, alloc_map: *std.AutoHashMap(u32, *AllocSite), free_map: *std.AutoHashMap(u32, *FreeSite), flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)), stats: *OwnershipStats, diag: *DiagnosticWriter) void {
        return cpp_fp.detectMemoryIssues(ctx, alloc_map, free_map, flow_graph, stats, diag);
    }
    fn detectMemoryLeaks(ctx: *PassContext, alloc_map: *std.AutoHashMap(u32, *AllocSite), free_map: *std.AutoHashMap(u32, *FreeSite), flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)), stats: *OwnershipStats, diag: *DiagnosticWriter) void {
        return cpp_fp.detectMemoryLeaks(ctx, alloc_map, free_map, flow_graph, stats, diag);
    }
    fn isLikelyStructMemberOwnership(func_name: []const u8) bool {
        return cpp_fp.isLikelyStructMemberOwnership(func_name);
    }
    fn detectStructMemberStores(func: c.LLVMValueRef, alloc_map: *std.AutoHashMap(u32, *AllocSite), id_map: *ValueIdMap) void {
        return cpp_fp.detectStructMemberStores(func, alloc_map, id_map);
    }

    fn isStlInternalFunction(func_name: []const u8) bool {
        return cpp_fp.isStlInternalFunction(func_name);
    }
    fn isCppSpecialMemberFunction(func_name: []const u8) bool {
        return cpp_fp.isCppSpecialMemberFunction(func_name);
    }
    fn isCppAbiInternalFunction(func_name: []const u8) bool {
        return cpp_fp.isCppAbiInternalFunction(func_name);
    }
    fn isMeyersSingletonPattern(func_name: []const u8) bool {
        return cpp_fp.isMeyersSingletonPattern(func_name);
    }
    fn is_likely_intentional_pattern(func_name: []const u8) bool {
        return cpp_fp.is_likely_intentional_pattern(func_name);
    }
    fn detectRaiiManagedAllocations(
        func: c.LLVMValueRef,
        alloc_map: *std.AutoHashMap(u32, *AllocSite),
        id_map: *ValueIdMap,
        raii_stats: *u32,
        raii_func_set: *std.AutoHashMap(usize, void),
    ) void {
        return cpp_fp.detectRaiiManagedAllocations(func, alloc_map, id_map, raii_stats, raii_func_set);
    }
    fn detectMeyersSingletonFunctions(
        func: c.LLVMValueRef,
        meyers_set: *std.AutoHashMap(usize, void),
    ) void {
        return cpp_fp.detectMeyersSingletonFunctions(func, meyers_set);
    }
    fn detectRefCountedContainerFunctions(
        func: c.LLVMValueRef,
        rc_set: *std.AutoHashMap(usize, void),
    ) void {
        return cpp_fp.detectRefCountedContainerFunctions(func, rc_set, cpp_fp.isAllocationByName);
    }
    fn detectRustFfiPairingFunctions(
        func: c.LLVMValueRef,
        into_raw_set: *std.AutoHashMap(usize, void),
        from_raw_set: *std.AutoHashMap(usize, void),
    ) void {
        return cpp_fp.detectRustFfiPairingFunctions(func, into_raw_set, from_raw_set);
    }
    fn isAllocationByName(callee_name: []const u8) bool {
        return cpp_fp.isAllocationByName(callee_name);
    }
    fn detectNullDereferences(
        ctx: *PassContext,
        alloc_map: *std.AutoHashMap(u32, *AllocSite),
        recognizer: *NullCheckRecognizer,
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        diag: *DiagnosticWriter,
    ) void {
        return cpp_fp.detectNullDereferences(ctx, alloc_map, recognizer, flow_graph, diag);
    }
    fn detectAsPtrBorrowEscape(
        ctx: *PassContext,
        func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
    ) void {
        return cpp_fp.detectAsPtrBorrowEscape(ctx, func, diag);
    }
    fn detectCrossLangAllocMismatch(
        ctx: *PassContext,
        alloc_map: *std.AutoHashMap(u32, *AllocSite),
        free_map: *std.AutoHashMap(u32, *FreeSite),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        diag: *DiagnosticWriter,
    ) void {
        return cpp_fp.detectCrossLangAllocMismatch(ctx, alloc_map, free_map, flow_graph, diag);
    }
    fn isNullableAllocation(alloc: *const AllocSite) bool {
        return cpp_fp.isNullableAllocation(alloc);
    }
    fn findFreePath(
        from_ptr: u32,
        free_map: *std.AutoHashMap(u32, *FreeSite),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        visited: *std.AutoHashMap(u32, void),
    ) bool {
        // BFS traversal with cycle detection from from_ptr to find any reachable free site.
        // This enables alloc-free path detection for leak analysis.
        // CRITICAL FIX: Added visited set to prevent infinite loops on cyclic graphs.
        if (free_map.contains(from_ptr)) return true;
        if (visited.contains(from_ptr)) return false;
        // Graceful degradation: OOM in visited set → skip this path rather than crash.
        // The allocation failure is logged via the error union capture below.
        visited.put(from_ptr, {}) catch return false;

        if (flow_graph.get(from_ptr)) |outgoing| {
            for (outgoing.keys()) |target| {
                if (findFreePath(target, free_map, flow_graph, visited)) return true;
            }
        }
        return false;
    }
    fn canReachFree(
        from: u32,
        flow: std.AutoHashMap(u32, void),
        free_map: *std.AutoHashMap(u32, *FreeSite),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        visited: *std.AutoHashMap(u32, void),
    ) bool {
        // DFS with cycle detection to check if 'from' can reach any free site.
        // Used by use-after-free detection after a pointer is freed.
        // The 'flow' parameter tracks live aliases — if non-empty, 'from' has live aliases
        // that should also be checked for reachability to free sites.
        // CONSERVATIVE STRATEGY: If 'from' has known aliases AND any of those aliases
        // are in the free_map, count it as a potential UAF even without full chain tracking.
        // This catches the common pattern: ptr_a = alloc(); ptr_b = alias(ptr_a); free(ptr_a); use(ptr_b)
        if (flow.count() > 0) {
            // 'from' has live aliases — check if any alias is already freed.
            // If an alias pointer is in free_map, 'from' becomes a dangling pointer (UAF risk).
            var alias_iter = flow.iterator();
            while (alias_iter.next()) |entry| {
                const alias_ptr = entry.key_ptr.*;
                if (free_map.contains(alias_ptr)) return true;
            }
            // Also check: if 'from' itself reaches a free site, all its aliases become dangling.
            // This is the transitive case: free(from) → all aliases of 'from' are now UAF.
        }
        if (free_map.contains(from)) return true;
        if (visited.contains(from)) return false;
        visited.put(from, {}) catch return false;

        if (flow_graph.get(from)) |outgoing| {
            for (outgoing.keys()) |target| {
                if (canReachFree(target, .{}, free_map, flow_graph, visited)) return true;
            }
        }
        return false;
    }
    fn detectDoubleFree(
        ctx: *PassContext,
        free_map: *std.AutoHashMap(u32, *FreeSite),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        stats: *OwnershipStats,
        diag: *DiagnosticWriter,
    ) void {
        return cpp_fp.detectDoubleFree(ctx, free_map, flow_graph, stats, diag);
    }
    fn detectUseAfterFree(
        ctx: *PassContext,
        free_map: *std.AutoHashMap(u32, *FreeSite),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        stats: *OwnershipStats,
        diag: *DiagnosticWriter,
    ) void {
        return cpp_fp.detectUseAfterFree(ctx, free_map, flow_graph, stats, diag);
    }
    fn hasUseAfterFree(
        freed_ptr: u32,
        flow: std.AutoHashMap(u32, void),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        visited: *std.AutoHashMap(u32, void),
    ) bool {
        return cpp_fp.hasUseAfterFree(freed_ptr, &flow, flow_graph, visited);
    }
    fn isMemoryAccess(value_id: u32) bool {
        // Check if value_id corresponds to a memory access instruction.
        // Memory accesses include: Load, Store, GetElementPtr (GEP),
        // and memory intrinsic calls (memcpy, memmove, memset).
        const inst: c.LLVMValueRef = @ptrFromInt(@as(usize, value_id));
        if (@intFromPtr(inst) == 0) return false;

        // Check opcode for load/store/GEP
        const opcode = c.LLVMGetInstructionOpcode(inst);
        return switch (opcode) {
            c.LLVMLoad, c.LLVMStore, c.LLVMGetElementPtr => true,
            else => {
                // Check for memory intrinsics (memcpy, memmove, memset, etc.)
                // NOTE: Only exact LLVM intrinsic names — no variants with spaces.
                // User wrappers like "my_llvm_memcpy" should be detected via allocation_classifier,
                // not here. This prevents false positives from function names containing substrings.
                const intrinsic_name_raw = c.LLVMGetValueName(inst);
                if (intrinsic_name_raw != null) {
                    const intrinsic_name = std.mem.span(intrinsic_name_raw);
                    const mem_intrinsics = [_][]const u8{
                        "llvm.memcpy",        "llvm.memmove", "llvm.memset",
                        "llvm.memset.inline",
                    };
                    for (mem_intrinsics) |intrinsic| {
                        if (std.mem.indexOf(u8, intrinsic_name, intrinsic) != null) return true;
                    }
                }
                return false;
            },
        };
    }
    fn getInstName(value_id: u32) []const u8 {
        // Return the debug/instruction name for a value ID.
        // Used in diagnostic messages to show which instruction is involved.
        const inst: c.LLVMValueRef = @ptrFromInt(@as(usize, value_id));
        if (@intFromPtr(inst) == 0) return "<null>";

        const name_raw = c.LLVMGetValueName(inst);
        if (name_raw != null) {
            return std.mem.span(name_raw);
        }

        // Fallback: generate name from opcode
        const opcode = c.LLVMGetInstructionOpcode(inst);
        const opcode_names = [_][]const u8{
            "load",   "store",   "gep",    "call",   "ret",
            "br",     "switch",  "phi",    "alloca", "extract",
            "insert", "shuffle", "select", "icmp",   "fcmp",
        };
        if (opcode < opcode_names.len) {
            return opcode_names[opcode];
        }
        return "<unknown>";
    }
};

test "PointerOwnership - alloc types" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(AllocType.heap));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(AllocType.rust_box_into_raw));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(AllocType.rust_box_from_raw));
}

test "PointerOwnership - ownership states" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(OwnershipState.live));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(OwnershipState.ownership_transferred));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(OwnershipState.freed));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(OwnershipState.leaked));
}

test "PointerOwnership - violation types" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(OwnershipViolationType.cross_lang_free_mismatch));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(OwnershipViolationType.ownership_lost));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(OwnershipViolationType.double_free_risk));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(OwnershipViolationType.rust_drop_after_ffi_transfer));
}
