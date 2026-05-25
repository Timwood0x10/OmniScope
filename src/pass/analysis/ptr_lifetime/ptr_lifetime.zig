//! Raw Pointer Lifetime Tracker
//!
//!  Tracks raw pointer lifecycle in escape zone functions to detect:
//! - Stack pointer escapes to FFI callback (dangling pointer after return)
//! - Use-after-scope (pointer used after its allocation scope ends)
//! - Return of stack-local address (undefined behavior)
//! - Heap pointer passed to extern without ownership transfer
//!
//! Design principle: Intra-procedural analysis with def-use chain tracking.
//! Based on IR facts only, no inter-procedural alias analysis required.
//!
//! Reference: plan/lang_ffi_analysis/plan.md - Escape Zone Deep Analysis
//!
//! Example bugs detected:
//!
//!   // Rust: stack pointer escapes to C callback
//!   unsafe {
//!       let buf = [0u8; 256];
//!       c_callback(buf.as_ptr());  // BUG: buf deallocated when scope exits
//!   }
//!
//!   // Zig: returning stack address
//!   fn getBuffer() [*]const u8 {
//!       var buf: [64]u8 = undefined;
//!       return &buf;  // BUG: stack memory invalidated on return
//!   }

const std = @import("std");
const isFreeFunction = @import("ptr_lifetime_classify.zig").isFreeFunction;
const classifyAllocLanguageEnum = @import("ptr_lifetime_classify.zig").classifyAllocLanguageEnum;
const c = @import("../../../ir/llvm_raw.zig").c;
// Issue2 FIX: Import helper for standardized CallInst argument counting
const getCallInstArgCount = @import("../../../ir/llvm_safe.zig").getCallInstArgCount;

const zone_cls = @import("../../../semantics/zone_classifier.zig");
const ZoneKind = zone_cls.ZoneKind;
const Lang = zone_cls.Language;

const FfiLang = @import("../../../diag/issue.zig").FFIBoundary.Language;

// Import utility functions from separate module (code organization)
const ptr_utils = @import("ptr_lifetime_utils.zig");
const toZoneLanguage = ptr_utils.toZoneLanguage;
const isCppDestructorOrConstructor = ptr_utils.isCppDestructorOrConstructor;
const isIntentionalOwnershipTransfer = ptr_utils.isIntentionalOwnershipTransfer;
const isResourceCloseFunction = ptr_utils.isResourceCloseFunction;
const isSocketClose = ptr_utils.isSocketClose;
const isRustBorrowPattern = ptr_utils.isRustBorrowPattern;
const is_resource_alloc_function = ptr_utils.is_resource_alloc_function;
const get_resource_type = ptr_utils.get_resource_type;
const isDerivedFrom = ptr_utils.isDerivedFrom;

const violations = @import("ptr_lifetime_violations.zig");
// NOTE: checkReturnViolation defined locally was removed (duplicate)
const checkViolations = violations.checkViolations;
const checkStoreToGlobal = violations.checkStoreToGlobal;
const checkCrossLanguageFree = violations.checkCrossLanguageFree;
const checkFFIReturnNullGuard = violations.checkFFIReturnNullGuard;
const checkFFITypeMismatch = violations.checkFFITypeMismatch;
const isSameOrAlias = ptr_utils.isSameOrAlias;
const isGlobalVariable = ptr_utils.isGlobalVariable;
const isFuncParam = ptr_utils.isFuncParam;
const isNonPointerReturnType = ptr_utils.isNonPointerReturnType;
const isRCPatternFree = ptr_utils.isRCPatternFree;
const getSinglePredecessor = ptr_utils.getSinglePredecessor;
const areMutuallyExclusive = ptr_utils.areMutuallyExclusive;

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;
const zone_classifier = @import("../../../semantics/zone_classifier.zig");
const FPWhitelist = @import("../../filter/fp_whitelist.zig");
const FPPrecisionGuard = @import("../../filter/fp_precision_guard.zig");
const hooks = @import("../../../registry/hooks.zig");
const NoiseReduction = @import("../noise/noise_reduction.zig");
const word_boundary = @import("../../../utils/word_boundary.zig");
const noise_filter = @import("../../../semantics/noise_filter.zig");
const DebugInfoUtils = @import("../../../ir/debug_info.zig").DebugInfoUtils;

// v0.1.7: New semantic modules
const memory_graph = @import("../../../semantics/memory_graph.zig");
const call_graph_mod = @import("../../../semantics/call_graph.zig");
const allocator_kb = @import("../../../semantics/allocator_kb.zig");
const intrinsic_filter = @import("../../../semantics/intrinsic_filter.zig");
const output_param_classifier = @import("../../../semantics/output_param_classifier.zig");

// P1-1: Inter-procedural FFI analysis for caller context
const ip_ffi = @import("../ip_ffi.zig");

// Reporting functions (extracted to separate module)
const report = @import("ptr_lifetime_report.zig");

// Core helper functions (extracted to reduce main file size)
const core = @import("ptr_lifetime_helpers.zig");
const extractDebugFilePath = core.extractDebugFilePath;
const inferContentKind = core.inferContentKind;
const putPtrInfo = core.putPtrInfo;
const mergeAllocSite = core.mergeAllocSite;
const propagateOrigin = core.propagateOrigin;
const propagateCrossFunctionFreedStatus = core.propagateCrossFunctionFreedStatus;

// Instruction tracking handlers (extracted from trackInstruction switch)
const track = @import("ptr_lifetime_track.zig");
const TrackContext = track.TrackContext;

// Type definitions, constants, and utilities shared across analysis passes.
// All PtrAllocSite/LifetimeViolation/PtrInfo/etc. come from here.
const ptr_types = @import("ptr_lifetime_types.zig");

pub const PtrAllocSite = ptr_types.PtrAllocSite;
pub const LifetimeViolation = ptr_types.LifetimeViolation;
pub const PtrInfo = ptr_types.PtrInfo;
pub const ResourceType = ptr_types.ResourceType;
pub const FreeSiteRecord = ptr_types.FreeSiteRecord;
pub const LifetimeAnalysisResult = ptr_types.LifetimeAnalysisResult;
pub const LifetimeStats = ptr_types.LifetimeStats;
pub const KNOWN_DEALLOCATORS = ptr_types.KNOWN_DEALLOCATORS;
pub const HEAP_ALLOC_FUNCTIONS = ptr_types.HEAP_ALLOC_FUNCTIONS;

pub const is_extern_function = ptr_types.is_extern_function;
pub const is_known_deallocator = ptr_types.is_known_deallocator;
pub const is_intentional_free = ptr_types.is_intentional_free;
pub const may_retain_pointer = ptr_types.may_retain_pointer;
pub const isIntrinsicNoise = ptr_types.isIntrinsicNoise;
pub const getAllocatorKB = ptr_types.getAllocatorKB;
pub const isHeapAllocFunction = ptr_types.isHeapAllocFunction;
pub const isKnownDeallocFunction = ptr_types.isKnownDeallocFunction;
pub const classify_ptr_origin = ptr_types.classify_ptr_origin;

// P2-2: Project-level allocator pair detection (auto-pairing for custom allocators)
pub const isProjectAllocFunction = ptr_types.isProjectAllocFunction;
pub const isProjectFreeFunction = ptr_types.isProjectFreeFunction;
pub const areAllocatorPair = ptr_types.areAllocatorPair;

// Re-export FreeSiteList from types (definition moved to ptr_lifetime_types.zig)
pub const FreeSiteList = ptr_types.FreeSiteList;

// ============================================================================
// Main Pass
// ============================================================================

/// Raw Pointer Lifetime Tracker Pass
///
/// Analyzes escape zone functions for pointer lifetime violations:
/// 1. Stack pointers escaping to FFI boundaries
/// 2. Stack addresses returned from functions
/// 3. Use-after-free patterns
/// 4. Ambiguous heap ownership across FFI
pub const PtrLifetimePass = struct {
    pub const name = "ptr-lifetime";
    pub const kind = PassKind.analysis;
    // v0.1.9: Removed danger-surface dependency to break circular dependency.
    // Execution order: call-graph → ptr-lifetime → danger-surface → ffi_boundary.
    // ptr-lifetime populates MemoryGraph; danger-surface consumes it.
    // Noise reduction using isRelevantFunction() still works via Phase 0 fallback
    // in danger-surface (marks relevant functions from CrossLangEdge before ptr-lifetime).
    pub const deps = &[_][]const u8{"call-graph"};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        // R7.2 Language Channel Gate
        const lifetime_channel = ctx.channelPtrLifetime();
        if (lifetime_channel == .skip) {
            diag.debug("LANG-SKIP [ptr_lifetime]: module is {s}", .{
                @tagName(ctx.getModuleLanguage().language),
            });
            return;
        }
        diag.debug("LANG-CHANNEL [ptr_lifetime/{s}]: analysis active", .{
            @tagName(lifetime_channel),
        });

        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;

        const noise_config = NoiseReduction.NoiseReductionConfig{ .focus_user_code = true };
        var stats = LifetimeStats{};

        // R8.0: Use shared MemoryGraph from PassContext (unified pointer state).
        const mem_graph: ?*memory_graph.MemoryGraph = &ctx.memory_graph;

        // Phase R5.1: Initialize Hook system for Rust ownership tracking.
        try hooks.initHookStates(ctx.allocator);
        defer hooks.deinitHookStates();

        const t_total = std.time.nanoTimestamp();
        var t_analyze: i128 = 0;
        var t_postprocess: i128 = 0;
        var t_track_all: i128 = 0;
        var t_check_all: i128 = 0;
        var funcs_analyzed: u32 = 0;

        // P0-3c: Build FFI function name set from cross_lang_edges (already populated
        // by FFIBoundaryPass which runs BEFORE ptr_lifetime). Functions not in this
        // set can skip expensive call-edge tracking in trackInstruction.
        var ffi_func_names = std.StringHashMap(void).init(ctx.allocator);
        defer ffi_func_names.deinit();
        for (ctx.cross_lang_edges.items) |edge| {
            try ffi_func_names.put(edge.callee_name, {});
            try ffi_func_names.put(edge.caller_name, {});
        }

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) {
                const func_name_raw = c.LLVMGetValueName(func);
                const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";
                const zone = ctx.getOrComputeZone(@ptrCast(func), func_name);
                ctx.zone_stats.record(zone);
                continue;
            }

            const func_name_raw = c.LLVMGetValueName(func);
            const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";

            const zone = ctx.getOrComputeZone(@ptrCast(func), func_name);
            ctx.zone_stats.record(zone);

            // v0.1.7: Three-layer noise reduction (supersedes zone-only check)
            const debug_file_path = extractDebugFilePath(func);
            var classification = NoiseReduction.classifyFunction(func_name, debug_file_path, noise_config);
            // E2-2e: Stdl functions on FFI danger path should not be suppressed
            const func_ptr_val: u64 = @intFromPtr(func);
            classification = NoiseReduction.reevaluateWithDangerPath(classification, ctx.isRelevantFunction(func_ptr_val));
            if (classification.origin == .compiler_generated) continue;
            if (classification.origin == .stdlib and !noise_config.include_stdlib) continue;

            // INTEGRATION: Three-layer noise filter (name + path + behavior)
            const func_loc = DebugInfoUtils.getFunctionLocation(func);
            const full_classification = ctx.classifyFunctionSurface(func_name, func_loc);
            // P0-2: Relax noise filter for Rust FFI callback functions.
            // Rust callbacks (e.g., rs_ffi_*_cb) may be classified as third_party
            // or have suppressed risk, but they are critical for FFI boundary analysis.
            // Only skip compiler_generated code; stdlib/third_party may have FFI callbacks.
            if (full_classification.origin == .compiler_generated) continue;
            if (full_classification.origin == .stdlib and !noise_config.include_stdlib) continue;
            if (full_classification.origin == .third_party) {
                const func_ptr_val_tmp: u64 = @intFromPtr(func);
                if (!ctx.isRelevantFunction(func_ptr_val_tmp)) continue;
            }

            // Defense-in-depth: known FP whitelist (v0.1.7 audit verified)
            if (FPWhitelist.is_known_fp(func_name) != null) continue;

            // NOTE: Function-level isRelevantFunction() gate intentionally NOT applied here.
            // While ptr_lifetime populates MemoryGraph (trackAlloc/trackCallArg/trackAlias),
            // it is NOT the sole producer — other passes also write to MemoryGraph.
            // The real reason for no gate here is PERFORMANCE: skipping functions would
            // reduce leak/double-free detection coverage. The ffi_func_names gate below
            // provides a balanced compromise — skip expensive call-edge indexing for
            // non-FFI functions while retaining full alloc/free tracking on all code.
            //
            // P0-3c: Use ffi_func_names (from cross_lang_edges, already populated by
            // FFIBoundaryPass which runs BEFORE ptr_lifetime) to skip expensive
            // call-edge tracking (trackCallArg/trackCallRet) for non-FFI functions.
            // Full alloc/free/alias tracking still applies to ALL functions.
            //
            // CRITICAL FIX for 0/73 benchmark: Also use CallGraph BFS traversal to
            // detect functions that INDIRECTLY reach FFI boundaries. A wrapper function
            // like my_process_data() may not be in cross_lang_edges itself, but if it
            // calls C.save_to_file() transitively, it needs full MemoryGraph tracking
            // to detect pointer leaks across the FFI boundary.
            var is_ffi_func = ffi_func_names.contains(func_name);
            if (!is_ffi_func) {
                if (ctx.semantics_call_graph) |*sg| {
                    if (sg.getNodeByName(func_name)) |node_id| {
                        if (call_graph_mod.CallGraph.reachesFFIBoundary(sg, node_id, 10)) {
                            is_ffi_func = true;
                        }
                    }
                }
            }

            // Phase R5.1: Reset hook state per function scope
            hooks.resetHookStatesForFunction();

            // P2-3 — Single-function error isolation
            {
                const t0 = std.time.nanoTimestamp();
                var t_track_fn: i128 = 0;
                var t_check_fn: i128 = 0;
                analyzeFunction(ctx, func, diag, &stats, mem_graph, &t_track_fn, &t_check_fn, is_ffi_func) catch |err| {
                    diag.warn("PtrLifetime: skipped function due to error: {} ({s})", .{ err, func_name });
                    ctx.recordDegradedFunction();
                    continue;
                };
                t_analyze += std.time.nanoTimestamp() - t0;
                t_track_all += t_track_fn;
                t_check_all += t_check_fn;
                funcs_analyzed += 1;
            }

            // Phase R5.1: Check hook state for end-of-function issues.
            if (hooks.rustUnpairedTransferCount() > 0) {
                const msg = try std.fmt.allocPrint(ctx.allocator, "Unpaired Rust ownership transfer in {s} (into_raw without matching from_raw)", .{func_name});
                defer ctx.allocator.free(msg);
                const trace = try ctx.allocator.alloc(TraceEntry, 1);
                errdefer ctx.allocator.free(trace);
                trace[0] = TraceEntry.init("Rust into_raw() not paired with from_raw() — potential ownership leak");
                const issue = Issue.initWithTrace(
                    .cross_language_leak,
                    msg,
                    Location.init(func_name),
                    .medium,
                    0.65,
                    trace,
                );
                try ctx.addIssue(&issue);
            }
            {
                const count = hooks.pythonUnbalancedDecrefCount();
                if (count > 0) {
                    const msg = try std.fmt.allocPrint(ctx.allocator, "{d} unbalanced Py_DECREF(s) in {s}", .{ count, func_name });
                    defer ctx.allocator.free(msg);
                    const trace = try ctx.allocator.alloc(TraceEntry, 1);
                    errdefer ctx.allocator.free(trace);
                    trace[0] = TraceEntry.init("Python refcount imbalance — potential use-after-free");
                    const issue = Issue.initWithTrace(
                        .use_after_free,
                        msg,
                        Location.init(func_name),
                        .high,
                        0.80,
                        trace,
                    );
                    try ctx.addIssue(&issue);
                }
            }
        }

        const total_violations = stats.stack_escapes_found + stats.return_stack_addr_found + stats.use_after_free_found + stats.heap_ambiguous_found;
        if (total_violations > 0) {
            diag.info("[OMI-HIGH] PtrLifetime: analyzed {} funcs, tracked {} ptrs, found {} violations", .{
                stats.total_functions_analyzed,
                stats.total_pointers_tracked,
                total_violations,
            });
        } else {
            diag.debug("PtrLifetime: analyzed {} funcs, tracked {} ptrs, no violations found", .{
                stats.total_functions_analyzed,
                stats.total_pointers_tracked,
            });
        }

        // R8.3-f: Post-analysis cross-function freed status propagation.
        {
            const t0 = std.time.nanoTimestamp();
            const propagated = try propagateCrossFunctionFreedStatus(ctx.allocator, mem_graph.?, &ctx.global_alloc_tracker, toZoneLanguage(ctx.module_language.language));
            t_postprocess = std.time.nanoTimestamp() - t0;
            if (propagated > 0) {
                diag.info("[R8.3-f] Cross-function alias propagation: {} allocations marked freed via alias chain", .{propagated});
            }
        }

        const t_end = std.time.nanoTimestamp();
        const total_ms: f64 = @as(f64, @floatFromInt(t_end - t_total)) / 1_000_000.0;
        const post_ms: f64 = @as(f64, @floatFromInt(t_postprocess)) / 1_000_000.0;
        const track_ms: f64 = @as(f64, @floatFromInt(t_track_all)) / 1_000_000.0;
        const check_ms: f64 = @as(f64, @floatFromInt(t_check_all)) / 1_000_000.0;
        if (total_ms > 10) {
            diag.info("[PERF-DETAIL] PtrLifetime: {d:.0}ms total (track={d:.0}ms, check={d:.0}ms, postprocess={d:.0}ms) for {d} funcs", .{ total_ms, track_ms, check_ms, post_ms, funcs_analyzed });
        }
    }

    fn analyzeFunction(
        ctx: *PassContext,
        func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
        stats: *LifetimeStats,
        mem_graph: ?*memory_graph.MemoryGraph,
        t_track: *i128,
        t_check: *i128,
        is_ffi_func: bool,
    ) !void {
        const func_name_ptr = c.LLVMGetValueName(func);
        const func_name = if (@intFromPtr(func_name_ptr) != 0)
            std.mem.span(func_name_ptr)
        else
            "unknown";

        stats.total_functions_analyzed += 1;

        var pointer_map = std.AutoHashMap(c.LLVMValueRef, PtrInfo).init(ctx.allocator);

        var free_sites = std.AutoHashMap(u64, FreeSiteList).init(ctx.allocator);

        defer {
            var iter = pointer_map.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.needs_free) {
                    ctx.allocator.free(entry.value_ptr.source_desc);
                }
            }
            pointer_map.deinit();

            var fs_iter = free_sites.iterator();
            while (fs_iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            free_sites.deinit();
        }

        var bb_id: usize = 0;
        var total_insts: usize = 0;

        const conv_lang: Lang = toZoneLanguage(ctx.module_language.language);
        const func_zone = ctx.getOrComputeZone(@ptrCast(func), func_name);

        // P2: Build BB control-flow graph for path-sensitive double-free analysis.
        // Extract successor edges from each BB's terminator instruction.
        if (mem_graph) |mg| {
            var cfg_bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(cfg_bb) != 0) : (cfg_bb = c.LLVMGetNextBasicBlock(cfg_bb)) {
                const cfg_bb_id: u32 = @truncate(@intFromPtr(cfg_bb));
                const term_inst = c.LLVMGetBasicBlockTerminator(cfg_bb);
                if (@intFromPtr(term_inst) != 0) {
                    const num_succ = c.LLVMGetNumSuccessors(term_inst);
                    var si: u32 = 0;
                    while (si < num_succ) : (si += 1) {
                        const succ_bb = c.LLVMGetSuccessor(term_inst, si);
                        if (@intFromPtr(succ_bb) != 0) {
                            const succ_bb_id: u32 = @truncate(@intFromPtr(succ_bb));
                            mg.addBBEdge(cfg_bb_id, succ_bb_id) catch {};
                        }
                    }
                }
            }
        }

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            if (bb_id >= 1000) break;
            var inst = c.LLVMGetFirstInstruction(bb);
            const bb_ref: c.LLVMValueRef = @ptrCast(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                total_insts += 1;
                if (total_insts > 50000) return;
                {
                    const t0 = std.time.nanoTimestamp();
                    try trackInstruction(ctx.allocator, inst, func, bb_id, &pointer_map, mem_graph, stats, &ctx.global_alloc_tracker, conv_lang, func_zone, is_ffi_func);
                    t_track.* += std.time.nanoTimestamp() - t0;
                }
                {
                    const t0 = std.time.nanoTimestamp();
                    const opcode = c.LLVMGetInstructionOpcode(inst);
                    if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
                        _ = c.LLVMGetCalledValue(inst);
                    }
                    try checkViolations(ctx, inst, func, func_name, bb_id, bb_ref, &pointer_map, mem_graph, diag, stats, &free_sites);
                    t_check.* += std.time.nanoTimestamp() - t0;
                }
            }
            bb_id += 1;
        }
    }

    fn trackInstruction(
        allocator: std.mem.Allocator,
        inst: c.LLVMValueRef,
        func: c.LLVMValueRef,
        bb_id: usize,
        pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
        mem_graph: ?*memory_graph.MemoryGraph,
        stats: *LifetimeStats,
        global_tracker: *@import("../../pass.zig").GlobalAllocTracker,
        lang: Lang,
        zone: ZoneKind,
        is_ffi_func: bool,
    ) !void {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        var ctx = TrackContext{
            .allocator = allocator,
            .inst = inst,
            .func = func,
            .bb_id = bb_id,
            .pointer_map = pointer_map,
            .mem_graph = mem_graph,
            .stats = stats,
            .global_tracker = global_tracker,
            .lang = lang,
            .zone = zone,
            .is_ffi_func = is_ffi_func,
        };

        switch (opcode) {
            c.LLVMAlloca => try track.handleAlloca(&ctx),
            c.LLVMCall, c.LLVMInvoke => try track.handleCallInvoke(&ctx),
            c.LLVMLoad => try track.handleLoad(&ctx),
            c.LLVMStore => try track.handleStore(&ctx),
            c.LLVMGetElementPtr => try track.handleGetElementPtr(&ctx),
            c.LLVMBitCast, c.LLVMPtrToInt, c.LLVMIntToPtr, c.LLVMAddrSpaceCast => try track.handleBitCastAndConversions(&ctx),
            c.LLVMPHI => try track.handlePhi(&ctx),
            c.LLVMRet => track.handleRet(&ctx),
            else => {},
        }
    }
};

// Re-export reporting functions from ptr_lifetime_report.zig
pub const reportStackEscape = report.reportStackEscape;
pub const reportReturnStackAddr = report.reportReturnStackAddr;
pub const reportReturnHeapPtr = report.reportReturnHeapPtr;
pub const reportHeapToGlobal = report.reportHeapToGlobal;
pub const reportStackToGlobal = report.reportStackToGlobal;
pub const reportUseAfterFree = report.reportUseAfterFree;
pub const reportResourceUAF = report.reportResourceUAF;
pub const reportHeapAmbiguous = report.reportHeapAmbiguous;
pub const makeTrace = report.makeTrace;
pub const reportHeapEscapeToFFI = report.reportHeapEscapeToFFI;
pub const reportFFINullGuardMissing = report.reportFFINullGuardMissing;
pub const reportBorrowEscapeFFI = report.reportBorrowEscapeFFI;
pub const reportCrossLanguageFree = report.reportCrossLanguageFree;
pub const reportFFITypeMismatch = report.reportFFITypeMismatch;

// Tests are in ptr_lifetime_test.zig (imported to run tests)
const _tests = @import("ptr_lifetime_test.zig");
