//! Callback Escaping Detector
//!
//! Phase 4.2: Detects Go cgo pointer retention bugs and callback escaping patterns.
//!
//! Key detection targets:
//! - Go pointer passed to C via C.CBytes() without runtime.KeepAlive
//! - unsafe.Pointer conversion that may dangle after GC
//! - C function retaining Go-allocated pointer beyond call scope
//! - Missing C.free / C.malloc pairs in cgo code
//!
//! Reference: /lang_ffi_analysis/go_ffi_fliter.md
//!
//! Example bugs detected:
//!
//!   // Go: pointer retained by C after call
//!   var buf []byte{1, 2, 3}
//!   C.process(C.CBytes(string(buf)))  // C retains pointer, GC may reclaim buf
//!
//!   // Go: missing KeepAlive for escaped pointer
//!   ptr := C.malloc(1024)
//!   defer C.free(ptr)
//!   C.useData(ptr)
//!   // BUG: no runtime.KeepAlive(ptr) - GC could run during C.useData

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const safe = @import("../../ir/llvm_safe.zig"); // Issue2/3: Standardized LLVM helpers
const ir_store_mod = @import("../../ir/ir_store.zig");
// Issue2 FIX: Import helper for standardized CallInst argument counting
const getCallInstArgCount = @import("../../ir/llvm_safe.zig").getCallInstArgCount;

const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const Location = @import("../../diag/issue.zig").Location;
const Issue = @import("../../diag/issue.zig").Issue;
const IssueKind = @import("../../diag/issue.zig").IssueKind;
const Severity = @import("../../diag/issue.zig").Severity;
const TraceEntry = @import("../../diag/issue.zig").TraceEntry;
const zone_classifier = @import("../../semantics/zone_classifier.zig");
const FPWhitelist = @import("../filter/fp_whitelist.zig");
const FPPrecisionGuard = @import("../filter/fp_precision_guard.zig");
comptime {
    _ = FPPrecisionGuard.PrecisionMetrics;
} // Force test discovery
const NoiseReduction = @import("noise/noise_reduction.zig");
const noise_filter = @import("../../semantics/noise_filter.zig");
const DebugInfoUtils = @import("../../ir/debug_info.zig").DebugInfoUtils;
const call_graph_mod = @import("../../semantics/call_graph.zig");

const CandidateBuilder = @import("resource/issue_candidate_builder.zig").CandidateBuilder;
const IssueCandidate = @import("resource/issue_candidate_builder.zig").IssueCandidate;
const IssueVerifier = @import("resource/issue_verifier.zig").IssueVerifier;
const Confidence = @import("callback_escape_report.zig").Confidence;

// : Integrated Hook system for semantic analysis.
// Replaces hardcoded C_RETAINING_FUNCTIONS with centralized patterns + hooks.
const hooks = @import("../../registry/hooks.zig");
const registry = @import("../../registry/semantic_registry.zig").SemanticRegistry;

// T3.1: Parallel execution support for per-function analysis
const parallel = @import("../../pipeline/parallel.zig");
const ptr_types = @import("ptr_lifetime/ptr_lifetime_types.zig");

// Reporting functions (extracted to separate module)
const cb_report = @import("callback_escape_report.zig");

// Re-export types from report module (used by both reporting and analysis code)
pub const CGoCallInfo = cb_report.CGoCallInfo;
pub const CallbackEscapeInfo = cb_report.CallbackEscapeInfo;

// Types and helpers from centralized types module
const cb_types = @import("../../types/callback_escape_types.zig");
pub const EscapeViolation = cb_types.EscapeViolation;
pub const EscapePattern = cb_types.EscapePattern;
pub const EscapeStats = cb_types.EscapeStats;
pub const AllocSiteInfo = cb_types.AllocSiteInfo;
pub const FreeSiteInfo = cb_types.FreeSiteInfo;
const CGO_GLUE_PATTERNS = cb_types.CGO_GLUE_PATTERNS;
const GO_RUNTIME_SAFETY_FUNCTIONS = cb_types.GO_RUNTIME_SAFETY_FUNCTIONS;
const C_RETAINING_FUNCTIONS = cb_types.C_RETAINING_FUNCTIONS;
const CGO_ENHANCED_PATTERNS = cb_types.CGO_ENHANCED_PATTERNS;
const GO_UNSAFE_PATTERNS = cb_types.GO_UNSAFE_PATTERNS;
const isCgoBoundary = cb_types.isCgoBoundary;
const isGoUnsafeOperation = cb_types.isGoUnsafeOperation;
const detectGoMemoryPattern = cb_types.detectGoMemoryPattern;
const hasCgoEvidence = cb_types.hasCgoEvidence;
const isCgoBoundaryByLinkage = cb_types.isCgoBoundaryByLinkage;
const isCgoBoundaryFromLLVM = cb_types.isCgoBoundaryFromLLVM;
const isCgoGlueByPattern = cb_types.isCgoGlueByPattern;
const isGoSafetyFunction = cb_types.isGoSafetyFunction;
const mayRetainInCLanguageAware = cb_types.mayRetainInCLanguageAware;
const isCBytesPattern = cb_types.isCBytesPattern;
const isCBytesEscapeWithDataFlow = cb_types.isCBytesEscapeWithDataFlow;
const isUnsafePtrConversion = cb_types.isUnsafePtrConversion;
const isRegisterNativesPattern = cb_types.isRegisterNativesPattern;
const isPthreadCreatePattern = cb_types.isPthreadCreatePattern;
const isCallbackReceiver = cb_types.isCallbackReceiver;
const validate_callback_signature = cb_types.validate_callback_signature;
const isGlobalVariable = cb_types.isGlobalVariable;
const isLikelyCallbackFunction = cb_types.isLikelyCallbackFunction;
const isGenericCallbackReceiver = cb_types.isGenericCallbackReceiver;
const isFactoryFunction = cb_types.isFactoryFunction;
const isDestructorFunction = cb_types.isDestructorFunction;
const isTransferFunction = cb_types.isTransferFunction;

// Core analysis functions (extracted to reduce file size)
const cb_core = @import("../../types/callback_escape_core.zig");
const scanInstruction = cb_core.scanInstruction;
const scanCallbackEscapes = cb_core.scanCallbackEscapes;
const isBorrowedCallbackArg = cb_core.isBorrowedCallbackArg;
const countMallocFreeSites = cb_core.countMallocFreeSites;

// ============================================================================
// Main Pass
// ============================================================================

/// Callback Escaping Detector Pass
///
/// Analyzes functions for cgo-related pointer lifetime issues:
/// 1. Go pointers passed to C without KeepAlive protection
/// 2. C.CBytes results escaping to retaining functions
/// 3. Unsafe.Pointer conversions at FFI boundaries
/// 4. Malloc/free pairing verification
pub const CallbackEscapePass = struct {
    pub const name = "callback-escape";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "call-graph", "danger-surface" };

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        // R8.2-d: Consume cross-language edges from CallGraphPass.
        const cross_edges = ctx.getCrossLangEdges();
        var go_cgo_edge_count: u32 = 0;
        for (cross_edges) |edge| {
            if (edge.caller_lang == .go and (edge.callee_lang == .c or edge.callee_lang == .cpp)) {
                go_cgo_edge_count += 1;
            }
        }
        if (go_cgo_edge_count > 0) {
            diag.info("CallbackEscape: {d} Go→C/C++ cross-language edges available", .{go_cgo_edge_count});
        }

        const mod = ctx.module.?.raw;
        const first_func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(first_func) == 0) return;

        const noise_config = NoiseReduction.NoiseReductionConfig{ .focus_user_code = true };
        var stats = EscapeStats{};

        try hooks.initHookStates(ctx.allocator);
        defer hooks.deinitHookStates();

        // T3.1: Pre-collect all functions into work items using IRStore.
        // IRStore already excludes declarations — no two-pass counting needed.
        if (ctx.ir_store.function_list.len == 0) return;
        const work_items = try ctx.allocator.alloc(parallel.WorkItem, ctx.ir_store.function_list.len);
        defer ctx.allocator.free(work_items);
        for (ctx.ir_store.function_list, 0..) |fir, idx| {
            work_items[idx] = .{
                .func = @intFromPtr(fir.func),
                .func_name = fir.name,
                .is_declaration = false,
                .fir_idx = idx,
            };
        }

        // T3.1: Mutex protecting shared PassContext state during parallel analysis.
        var analysis_mutex = std.Thread.Mutex{};

        // T3.1: Per-worker local stats
        var worker_stats_arr: [CB_MAX_WORKERS]EscapeStats = undefined;
        var worker_stats_len: usize = 0;

        // T3.1: Worker context for callback escape analysis
        var cb_worker_ctx = CallbackEscapeWorkerContext{
            .ctx_ptr = ctx,
            .diag_ptr = diag,
            .noise_cfg = noise_config,
            .mutex = &analysis_mutex,
            .stats_arr = &worker_stats_arr,
            .stats_len = &worker_stats_len,
        };

        // T3.1: Publish worker context
        cb_context_ptr = &cb_worker_ctx;
        defer cb_context_ptr = null;

        var executor = try parallel.ParallelExecutor.init(ctx.allocator, 0);
        defer executor.deinit();
        _ = try executor.run(work_items, cbEscapeWorkerFn);

        // T3.1: Merge per-worker stats
        for (worker_stats_arr[0..worker_stats_len]) |*ws| {
            stats.total_functions_analyzed += ws.total_functions_analyzed;
            stats.go_cgo_boundaries_found += ws.go_cgo_boundaries_found;
            stats.keepalive_missing += ws.keepalive_missing;
            stats.cbytes_escapes += ws.cbytes_escapes;
            stats.unsafeptr_risks += ws.unsafeptr_risks;
            stats.malloc_leaks += ws.malloc_leaks;
            stats.free_orphans += ws.free_orphans;
        }

        diag.info("CallbackEscape: analyzed {d} funcs, {d} cgo boundaries, {d} issues found", .{
            stats.total_functions_analyzed,
            stats.go_cgo_boundaries_found,
            stats.keepalive_missing + stats.cbytes_escapes + stats.unsafeptr_risks + stats.malloc_leaks + stats.free_orphans,
        });
    }

    /// Extract debug file path from LLVM subprogram metadata.
    /// Used by NoiseReduction Layer 2 (path-based filter).
    /// T3.1: Worker context for callback escape parallel analysis.
    const CB_MAX_WORKERS = 16;
    const CallbackEscapeWorkerContext = struct {
        ctx_ptr: *PassContext,
        diag_ptr: *DiagnosticWriter,
        noise_cfg: NoiseReduction.NoiseReductionConfig,
        mutex: *std.Thread.Mutex,
        stats_arr: *[CB_MAX_WORKERS]EscapeStats,
        stats_len: *usize,
    };

    var cb_context_ptr: ?*CallbackEscapeWorkerContext = null;

    fn getCBWorkerContext() *CallbackEscapeWorkerContext {
        return cb_context_ptr.?;
    }

    fn cbEscapeWorkerFn(item: parallel.WorkItem, worker_id: usize) !parallel.WorkerResult {
        _ = worker_id;
        var result = parallel.WorkerResult{};
        const wctx = getCBWorkerContext();

        // Get IRStore FunctionIR for this function
        const fir = wctx.ctx_ptr.ir_store.function_list[item.fir_idx];
        const func = fir.func;

        // Noise filtering (read-only, no lock needed)
        const debug_file_path = extractDebugFilePath(func);
        const classification = NoiseReduction.classifyFunction(item.func_name, debug_file_path, wctx.noise_cfg);
        if (classification.origin == .compiler_generated) {
            result.funcs_skipped += 1;
            return result;
        }
        if (classification.origin == .stdlib and !wctx.noise_cfg.include_stdlib) {
            result.funcs_skipped += 1;
            return result;
        }
        if (FPWhitelist.is_known_fp(item.func_name) != null) {
            result.funcs_skipped += 1;
            return result;
        }
        if (!wctx.ctx_ptr.isRelevantFunction(@as(u64, item.func))) {
            result.funcs_skipped += 1;
            return result;
        }

        // Per-function local stats
        var fn_stats = EscapeStats{};

        hooks.resetHookStatesForFunction();

        // Core analysis + issue reporting under mutex
        wctx.mutex.lock();
        defer wctx.mutex.unlock();

        analyzeFunction(wctx.ctx_ptr, fir, wctx.diag_ptr, &fn_stats) catch |err| {
            wctx.diag_ptr.warn("CallbackEscape: skipped function due to error: {} ({s})", .{ err, item.func_name });
            wctx.ctx_ptr.recordDegradedFunction();
            result.funcs_errored += 1;
            return result;
        };

        result.funcs_analyzed = 1;

        // Store stats in shared array
        if (wctx.stats_len.* < CB_MAX_WORKERS) {
            wctx.stats_arr[wctx.stats_len.*] = fn_stats;
            wctx.stats_len.* += 1;
        }

        // Hook-based end-of-function checks
        if (hooks.rustUnpairedTransferCount() > 0) {
            const msg = std.fmt.allocPrint(wctx.ctx_ptr.allocator, "Unpaired Rust ownership transfer in {s} (into_raw without matching from_raw)", .{item.func_name}) catch {
                return result;
            };
            defer wctx.ctx_ptr.allocator.free(msg);
            const trace = wctx.ctx_ptr.allocator.alloc(TraceEntry, 1) catch {
                wctx.ctx_ptr.allocator.free(msg);
                return result;
            };
            defer wctx.ctx_ptr.allocator.free(trace);
            trace[0] = TraceEntry.init("Rust into_raw() not paired with from_raw() — potential ownership leak across FFI boundary");
            var issue = Issue.initWithTrace(.cross_language_leak, msg, Location.init(item.func_name), .medium, 0.65, trace);
            issue.owned = true;
            wctx.ctx_ptr.addIssue(&issue) catch {};
        }
        {
            const count = hooks.pythonUnbalancedDecrefCount();
            if (count > 0) {
                const msg = std.fmt.allocPrint(wctx.ctx_ptr.allocator, "{d} unbalanced Py_DECREF(s) in {s}", .{ count, item.func_name }) catch {
                    return result;
                };
                defer wctx.ctx_ptr.allocator.free(msg);
                const trace = wctx.ctx_ptr.allocator.alloc(TraceEntry, 1) catch {
                    wctx.ctx_ptr.allocator.free(msg);
                    return result;
                };
                defer wctx.ctx_ptr.allocator.free(trace);
                trace[0] = TraceEntry.init("Python refcount imbalance — potential use-after-free across FFI boundary");
                var issue = Issue.initWithTrace(.use_after_free, msg, Location.init(item.func_name), .high, 0.80, trace);
                issue.owned = true;
                wctx.ctx_ptr.addIssue(&issue) catch {};
            }
        }
        return result;
    }

    fn extractDebugFilePath(func: c.LLVMValueRef) ?[]const u8 {
        const subprogram = c.LLVMGetSubprogram(func);
        if (@intFromPtr(subprogram) == 0) return null;

        const file_ref = c.LLVMDIScopeGetFile(subprogram);
        if (@intFromPtr(file_ref) == 0) return null;

        var filename_len: c_uint = undefined;
        const filename_ptr = c.LLVMDIFileGetFilename(file_ref, &filename_len);
        if (@intFromPtr(filename_ptr) == 0 or filename_len == 0) return null;

        const max_path_len: c_uint = 4096;
        if (filename_len > max_path_len) return null;
        if (filename_ptr[0] == 0) return null;

        return filename_ptr[0..filename_len];
    }

    fn analyzeFunction(
        ctx: *PassContext,
        fir: *const ir_store_mod.FunctionIR,
        diag: *DiagnosticWriter,
        stats: *EscapeStats,
    ) !void {
        const func = fir.func;
        const func_name = fir.name;

        // R7.2 Language Channel Gate
        const escape_channel = ctx.channelCallbackEscape();
        if (escape_channel == .skip) return;
        diag.debug("LANG-CHANNEL [callback_escape/{s}]: {s}", .{
            @tagName(escape_channel), func_name,
        });

        stats.total_functions_analyzed += 1;

        // INTEGRATION: Three-layer noise filter (name + path)
        const func_loc = DebugInfoUtils.getFunctionLocation(func);
        const classification = ctx.classifyFunctionSurface(func_name, func_loc);
        if (!classification.origin.shouldReportByDefault()) return;

        // R7.2: Use module-level language detection instead of per-function cgo check.
        // isGoModule() is set once at scan entry by Language-First Pipeline.
        // Keep isCgoBoundaryFromLLVM as a secondary refinement for mixed-language modules.
        const is_cgo_boundary = ctx.isGoModule() or isCgoBoundaryFromLLVM(func);
        if (is_cgo_boundary) {
            stats.go_cgo_boundaries_found += 1;
        }

        // Track per-call-site KeepAlive protection.
        // Key: pointer value (u64), Value: void
        // This allows precise tracking of which specific pointers are protected,
        // preventing false negatives when some pointers have KeepAlive but others don't.
        var keepalive_protected = std.AutoHashMap(u64, void).init(ctx.allocator);
        defer keepalive_protected.deinit();
        var alloc_sites: std.ArrayList(AllocSiteInfo) = .{};
        defer {
            for (alloc_sites.items) |site| ctx.allocator.free(site.func_name);
            alloc_sites.deinit(ctx.allocator);
        }
        var free_sites: std.ArrayList(FreeSiteInfo) = .{};
        defer {
            for (free_sites.items) |site| ctx.allocator.free(site.func_name);
            free_sites.deinit(ctx.allocator);
        }
        var cgo_calls: std.ArrayList(CGoCallInfo) = .{};
        defer {
            for (cgo_calls.items) |call| ctx.allocator.free(call.callee_name);
            cgo_calls.deinit(ctx.allocator);
        }
        var callback_escapes: std.ArrayList(CallbackEscapeInfo) = .{};
        defer callback_escapes.deinit(ctx.allocator);

        for (fir.instructions) |inst| {
            try scanInstruction(
                ctx.allocator,
                inst,
                &keepalive_protected,
                &alloc_sites,
                &free_sites,
                &cgo_calls,
                &callback_escapes,
                ctx.isGoModule(),
                ctx.module_language.language,
                ctx.platform_profile,
            );
        }

        if (callback_escapes.items.len == 0) {
            var scanned_escapes = try scanCallbackEscapes(ctx.allocator, func);
            defer scanned_escapes.deinit(ctx.allocator);
            for (scanned_escapes.items) |se| {
                try callback_escapes.append(ctx.allocator, se);
            }
        }

        if (cgo_calls.items.len > 0) {
            stats.go_cgo_boundaries_found += 1;
        }

        if (cgo_calls.items.len > 0) {
            // Per-call-site KeepAlive protection check.
            // Only report missing KeepAlive for pointers that are NOT protected.
            for (cgo_calls.items) |call| {
                // Check if ANY pointer argument to this call has KeepAlive protection.
                // A CGO call is considered "protected" if at least one of its pointer
                // arguments was explicitly passed to runtime.KeepAlive().
                //
                // This handles cases like:
                //   C.useData(ptr1, ptr2)  where only KeepAlive(ptr2) is called
                //   → The call is still considered protected (ptr2 is the critical one)
                var is_this_call_protected = false;
                {
                    // H13 FIX: For CallInst, operand (num_ops-1) is the callee, NOT operand 0.
                    // Issue2 FIX: Use standardized helper to avoid inconsistency across files.
                    const num_args = getCallInstArgCount(call.inst);
                    var arg_i: u32 = 0;
                    while (arg_i < num_args) : (arg_i += 1) {
                        const arg = c.LLVMGetOperand(call.inst, arg_i);
                        if (@intFromPtr(arg) != 0) {
                            const arg_type = c.LLVMTypeOf(arg);
                            if (@intFromPtr(arg_type) != 0 and c.LLVMGetTypeKind(arg_type) == c.LLVMPointerTypeKind) {
                                const ptr_val = @as(u64, @intFromPtr(arg));
                                if (keepalive_protected.contains(ptr_val)) {
                                    is_this_call_protected = true;
                                    // Don't break — continue checking remaining args
                                    // (though we already know it's protected)
                                }
                            }
                        }
                    }
                    // Note: We intentionally check ALL pointer arguments, not just the first.
                    // This ensures comprehensive coverage for multi-pointer CGO calls.
                }

                if (!is_this_call_protected and call.is_pointer_arg and mayRetainInCLanguageAware(call.callee_name, is_cgo_boundary)) {
                    // R8.0: Cross-verify with unified MemoryGraph before reporting.
                    // Only report if the pointer is confirmed to flow into a call edge.
                    const mg = &ctx.memory_graph;
                    var confirmed_by_graph = false;
                    var detected_ptr_val: u64 = 0;
                    // Issue2/3 FIX: Use standardized helper for consistent arg iteration
                    const num_args_keepalive = safe.getCallInstArgCount(call.inst);
                    var arg_k: u32 = 0;
                    while (arg_k < num_args_keepalive) : (arg_k += 1) {
                        const arg = c.LLVMGetOperand(call.inst, arg_k);
                        if (@intFromPtr(arg) == 0) continue;
                        const arg_ptr_val = @as(u64, @intFromPtr(arg));
                        if (mg.isPassedAsArg(arg_ptr_val)) {
                            confirmed_by_graph = true;
                            detected_ptr_val = arg_ptr_val;
                            break;
                        }
                    }
                    if (confirmed_by_graph) {
                        if (!ctx.isRelevantAlloc(detected_ptr_val)) continue;
                        try reportMissingKeepAlive(ctx, func_name, call, diag);
                        stats.keepalive_missing += 1;
                    }
                }
            }
        }

        // CBytes escape detection: if a function calls C.CBytes and may also call
        // a retaining function (like storing to global, registering callback), report escape.
        // True next_call tracking requires call graph analysis for full precision.
        for (cgo_calls.items) |call| {
            if (isCBytesPattern(call.callee_name)) {
                // R7.1-3: Language-aware retention check for CBytes escape
                if (mayRetainInCLanguageAware(func_name, is_cgo_boundary)) {
                    // R8.0 consume: Cross-verify with MemoryGraph — only report
                    // if the CBytes call's pointer arg is tracked as passed to an FFI call.
                    const mg = &ctx.memory_graph;
                    var cgo_ptr_val: u64 = 0;
                    // Issue2/3 FIX: Use standardized helper for consistent arg iteration
                    const cgo_num_args = safe.getCallInstArgCount(call.inst);
                    var arg_i: u32 = 0;
                    while (arg_i < cgo_num_args) : (arg_i += 1) {
                        const arg = c.LLVMGetOperand(call.inst, arg_i);
                        if (@intFromPtr(arg) != 0 and mg.isPassedAsArg(@as(u64, @intFromPtr(arg)))) {
                            cgo_ptr_val = @as(u64, @intFromPtr(arg));
                            break;
                        }
                    }
                    if (cgo_ptr_val != 0) {
                        if (!ctx.isRelevantAlloc(cgo_ptr_val)) continue;
                        // Generate candidate instead of direct reporting
                        var candidate = try cb_report.generateCBytesEscapeCandidate(ctx, func_name, call, diag);
                        defer candidate.deinit();
                        // Verify candidate through IssueVerifier
                        if (ctx.issue_verifier) |verifier| {
                            const result = try verifier.verify(&candidate);
                            if (result.shouldReport()) {
                                const sev: Severity = switch (result.severity) {
                                    .critical => .critical,
                                    .high => .high,
                                    .medium => .medium,
                                    .low => .low,
                                    else => .medium,
                                };
                                // Convert candidate to Issue and add to context
                                const issue = Issue.initWithTrace(
                                    .memory_leak,
                                    candidate.reason orelse "CBytes escape detected",
                                    Location.init(func_name),
                                    sev,
                                    result.adjusted_score,
                                    &[_]TraceEntry{},
                                );
                                try ctx.addIssue(&issue);
                            }
                        } else {
                            // Legacy mode: direct reporting
                            const issue = Issue.initWithTrace(
                                .memory_leak,
                                candidate.reason orelse "CBytes escape detected",
                                Location.init(func_name),
                                .medium,
                                0.65, // med_cbytes_escape confidence
                                &[_]TraceEntry{},
                            );
                            try ctx.addIssue(&issue);
                        }
                        stats.cbytes_escapes += 1;
                    }
                }
            }

            if (isUnsafePtrConversion(call.callee_name)) {
                // Generate candidate instead of direct reporting
                var candidate = try cb_report.generateUnsafePtrRiskCandidate(ctx, func_name, call, diag);
                defer candidate.deinit();
                // Verify candidate through IssueVerifier
                if (ctx.issue_verifier) |verifier| {
                    const result = try verifier.verify(&candidate);
                    if (result.shouldReport()) {
                        const sev2: Severity = switch (result.severity) {
                            .critical => .critical,
                            .high => .high,
                            .medium => .medium,
                            .low => .low,
                            else => .medium,
                        };
                        // Convert candidate to Issue and add to context
                        const issue = Issue.initWithTrace(
                            .borrow_escape,
                            candidate.reason orelse "Unsafe pointer risk detected",
                            Location.init(func_name),
                            sev2,
                            result.adjusted_score,
                            &[_]TraceEntry{},
                        );
                        try ctx.addIssue(&issue);
                    }
                } else {
                    // Legacy mode: direct reporting
                    const issue = Issue.initWithTrace(
                        .borrow_escape,
                        candidate.reason orelse "Unsafe pointer risk detected",
                        Location.init(func_name),
                        .high,
                        0.72, // med_unsafe_ptr confidence
                        &[_]TraceEntry{},
                    );
                    try ctx.addIssue(&issue);
                }
                stats.unsafeptr_risks += 1;
            }
        }

        try checkMallocFreePairing(ctx, func_name, &alloc_sites, &free_sites, diag, stats);

        for (callback_escapes.items) |escape| {
            if (isBorrowedCallbackArg(escape)) {
                const called_val = c.LLVMGetCalledValue(escape.inst);
                const callee_name = if (@intFromPtr(called_val) != 0) blk: {
                    const callee_name_ptr = c.LLVMGetValueName(called_val);
                    break :blk if (@intFromPtr(callee_name_ptr) != 0) std.mem.span(callee_name_ptr) else "unknown";
                } else "unknown";
                diag.debug("[SUPPRESSED] Callback arg is borrowed_only: {s} -> {s}", .{ func_name, callee_name });
                continue;
            }

            if (!std.mem.eql(u8, escape.receiver_name, "global_store")) {
                const cb_type = c.LLVMGetElementType(c.LLVMTypeOf(escape.callback_arg));
                if (@intFromPtr(cb_type) != 0) {
                    const num_params = c.LLVMCountParamTypes(cb_type);
                    if (num_params > 3) {
                        diag.debug("[SUPPRESSED] Callback has >3 params: {s}", .{func_name});
                        continue;
                    }
                    // BUG-FIX-8: LLVMGetStructName returns null for function types.
                    // When type_name is empty, skip signature mismatch check
                    // and proceed to generic callback escape detection.
                    const type_str = c.LLVMGetStructName(cb_type);
                    const type_name = if (@intFromPtr(type_str) != 0)
                        std.mem.span(type_str)
                    else
                        "";
                    if (type_name.len > 0 and !validate_callback_signature(escape.receiver_name, type_name)) {
                        try reportSignatureMismatch(ctx, func_name, escape, diag);
                        stats.callback_escapes += 1;
                        continue;
                    }
                    // Issue1 fix: Debug log when type_name is empty (function type)
                    if (type_name.len == 0) {
                        diag.debug("[CALLBACK] Skipping signature check for function type: {s}", .{func_name});
                    }
                }
            }

            // E2-2c: Indirect escape via alias closure — check if the callback
            // argument's aliases reach FFI boundaries through memory graph.
            try reportCallbackWithAliasCheck(ctx, func_name, escape, diag);
            stats.callback_escapes += 1;
        }
    }

    /// E2-2c: Report callback escape with alias-closure FFI detection.
    /// Extracted from two identical call sites (analyzeFunction + checkCallbackEscape)
    /// to eliminate code duplication. Null-safe: null callback_arg reports with
    /// base confidence (no FFI boost).
    fn reportCallbackWithAliasCheck(
        ctx: *PassContext,
        func_name: []const u8,
        escape: CallbackEscapeInfo,
        diag: *DiagnosticWriter,
    ) !void {
        const indirect_escape = if (@intFromPtr(escape.callback_arg) == 0) false else ctx.isOnDangerPathFull(@intFromPtr(escape.callback_arg));
        try reportGenericCallbackEscape(ctx, func_name, escape, diag, indirect_escape);
    }

    fn checkMallocFreePairing(
        ctx: *PassContext,
        func_name: []const u8,
        alloc_sites: *const std.ArrayList(AllocSiteInfo),
        free_sites: *const std.ArrayList(FreeSiteInfo),
        diag: *DiagnosticWriter,
        stats: *EscapeStats,
    ) !void {
        const pair_result = countMallocFreeSites(alloc_sites, free_sites, func_name);

        if (pair_result.is_pattern_suppressed) {
            diag.debug("[SUPPRESSED] {s}: {d} allocs, {d} frees (ownership pattern)", .{ func_name, pair_result.malloc_count, pair_result.free_count });
            return;
        }

        const mg = &ctx.memory_graph;
        if (pair_result.malloc_count > pair_result.free_count) {
            var has_call_ret_transfer = false;
            for (alloc_sites.items) |site| {
                const ptr_val = @as(u64, @intFromPtr(site.inst_id));
                if (mg.isReturnedFromCall(ptr_val)) {
                    has_call_ret_transfer = true;
                    break;
                }
            }
            if (!has_call_ret_transfer) {
                // Generate candidate instead of direct reporting
                var candidate = try cb_report.generateMallocLeakCandidate(ctx, func_name, pair_result.malloc_count, pair_result.free_count, diag);
                defer candidate.deinit();
                // Verify candidate through IssueVerifier
                if (ctx.issue_verifier) |verifier| {
                    const result = try verifier.verify(&candidate);
                    if (result.shouldReport()) {
                        const sev3: Severity = switch (result.severity) {
                            .critical => .critical,
                            .high => .high,
                            .medium => .medium,
                            .low => .low,
                            else => .medium,
                        };
                        // Convert candidate to Issue and add to context
                        const reason = candidate.reason orelse "Memory leak detected";
                        candidate.reason = null; // Transfer ownership to Issue to avoid double-free
                        const issue = Issue.initWithTrace(
                            .memory_leak,
                            reason,
                            Location.init(func_name),
                            sev3,
                            result.adjusted_score,
                            &[_]TraceEntry{},
                        );
                        try ctx.addIssue(&issue);
                    }
                } else {
                    // Legacy mode: direct reporting
                    const reason = candidate.reason orelse "Memory leak detected";
                    candidate.reason = null; // Transfer ownership to Issue to avoid double-free
                    const issue = Issue.initWithTrace(
                        .memory_leak,
                        reason,
                        Location.init(func_name),
                        .medium,
                        Confidence.med_malloc_leak,
                        &[_]TraceEntry{},
                    );
                    try ctx.addIssue(&issue);
                }
                stats.malloc_leaks += @as(u32, @intCast(pair_result.malloc_count - pair_result.free_count));
            } else {
                diag.debug("[R8.0-SUPPRESSED] {s}: {d} allocs > {d} frees but ptr returned from call", .{ func_name, pair_result.malloc_count, pair_result.free_count });
            }
        }

        if (pair_result.free_count > pair_result.malloc_count) {
            var has_call_arg_source = false;
            for (free_sites.items) |site| {
                const ptr_val = @as(u64, @intFromPtr(site.inst_id));
                if (mg.isPassedAsArg(ptr_val)) {
                    has_call_arg_source = true;
                    break;
                }
            }
            if (!has_call_arg_source) {
                const on_danger = ctx.isOnDangerPathFull(@as(u64, @intFromPtr(func_name.ptr)));
                if (!on_danger) {
                    diag.debug("[R8.0-SUPPRESSED] {s}: {d} frees > {d} allocs but not on danger path", .{ func_name, pair_result.free_count, pair_result.malloc_count });
                } else {
                    try reportFreeOrphan(ctx, func_name, pair_result.malloc_count, pair_result.free_count, diag);
                    stats.free_orphans += @as(u32, @intCast(pair_result.free_count - pair_result.malloc_count));
                }
            } else {
                diag.debug("[R8.0-SUPPRESSED] {s}: {d} frees > {d} allocs but ptr came from call arg", .{ func_name, pair_result.free_count, pair_result.malloc_count });
            }
        }
    }
};

// ============================================================================
// Data Structures — now imported from cb_types
// ============================================================================

// Re-export reporting functions from callback_escape_report.zig
pub const reportMissingKeepAlive = cb_report.reportMissingKeepAlive;
pub const reportCBytesEscape = cb_report.reportCBytesEscape;
pub const reportGenericCallbackEscape = cb_report.reportGenericCallbackEscape;
pub const reportSignatureMismatch = cb_report.reportSignatureMismatch;
pub const reportUnsafePtrRisk = cb_report.reportUnsafePtrRisk;
pub const reportMallocLeak = cb_report.reportMallocLeak;
pub const reportFreeOrphan = cb_report.reportFreeOrphan;
pub const makeTrace = cb_report.makeTrace;

// Tests are in callback_escape_test.zig (imported to run tests)
const _tests = @import("../../types/callback_escape_test.zig");
