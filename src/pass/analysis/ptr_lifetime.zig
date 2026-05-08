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
const c = @import("../../ir/llvm_raw.zig").c;
// Issue2 FIX: Import helper for standardized CallInst argument counting
const getCallInstArgCount = @import("../../ir/llvm_safe.zig").getCallInstArgCount;

const zone_cls = @import("../../semantics/zone_classifier.zig");
const ZoneKind = zone_cls.ZoneKind;
const Lang = zone_cls.Language;

const FfiLang = @import("../../diag/issue.zig").FFIBoundary.Language;

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
const hooks = @import("../../registry/hooks.zig");
const NoiseReduction = @import("noise_reduction.zig");
const word_boundary = @import("../../utils/word_boundary.zig");
const noise_filter = @import("../../semantics/noise_filter.zig");
const DebugInfoUtils = @import("../../ir/debug_info.zig").DebugInfoUtils;

// v0.1.7: New semantic modules
const memory_graph = @import("../../semantics/memory_graph.zig");
const call_graph_mod = @import("../../semantics/call_graph.zig");
const allocator_kb = @import("../../semantics/allocator_kb.zig");
const intrinsic_filter = @import("../../semantics/intrinsic_filter.zig");
const output_param_classifier = @import("../../semantics/output_param_classifier.zig");

// P1-1: Inter-procedural FFI analysis for caller context
const ip_ffi = @import("ip_ffi.zig");

// Reporting functions (extracted to separate module)
const report = @import("ptr_lifetime_report.zig");

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

/// Lightweight growable list for FreeSiteRecord (contains opaque C types
/// that prevent std.ArrayList from monomorphizing correctly in Zig 0.15.2).
pub const FreeSiteList = struct {
    items: []FreeSiteRecord,
    len: usize,
    capacity: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FreeSiteList {
        return .{ .items = &.{}, .len = 0, .capacity = 0, .allocator = allocator };
    }

    pub fn append(self: *FreeSiteList, record: FreeSiteRecord) !void {
        if (self.len >= self.capacity) {
            const new_cap = if (self.capacity == 0) 4 else self.capacity * 2;
            const new_items = try self.allocator.alloc(FreeSiteRecord, new_cap);
            @memcpy(new_items[0..self.len], self.items);
            if (self.capacity > 0) self.allocator.free(self.items);
            self.items = new_items;
            self.capacity = new_cap;
        }
        self.items[self.len] = record;
        self.len += 1;
    }

    pub fn deinit(self: *FreeSiteList) void {
        if (self.capacity > 0) self.allocator.free(self.items);
    }
};

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
    pub const deps = &[_][]const u8{ "call-graph", "danger-surface" };

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
        var mem_graph: ?*memory_graph.MemoryGraph = &ctx.memory_graph;

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
            const full_classification = noise_filter.classifyFunctionFull(func_name, null, func_loc, null);
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
        // Optimized: Instead of O(N×A) scan (each node × each alias),
        // build reverse alias index O(E) then propagate O(F) from freed nodes.
        {
            const t0 = std.time.nanoTimestamp();
            var propagated: u32 = 0;

            // Step 1: Build reverse index: canonical_ptr → [aliasing_ptrs]
            // This is O(E) where E = total alias edges.
            var reverse_alias = std.AutoHashMap(u64, std.ArrayList(u64)).init(ctx.allocator);
            defer {
                var ra_iter = reverse_alias.iterator();
                while (ra_iter.next()) |entry| {
                    entry.value_ptr.deinit(ctx.allocator);
                }
                reverse_alias.deinit();
            }

            {
                var alias_iter = mem_graph.?.alias_to_canonical.iterator();
                while (alias_iter.next()) |entry| {
                    const from_ptr = entry.key_ptr.*;
                    const to_ptr = entry.value_ptr.*;
                    const gop = try reverse_alias.getOrPut(to_ptr);
                    if (!gop.found_existing) {
                        gop.value_ptr.* = try std.ArrayList(u64).initCapacity(ctx.allocator, 0);
                    }
                    try gop.value_ptr.append(ctx.allocator, from_ptr);
                }
            }

            // Step 2: Iterate only FREED nodes, propagate to their aliasers.
            // This is O(F × avg_aliases) where F << N typically.
            var node_iter = mem_graph.?.nodes.iterator();
            while (node_iter.next()) |entry| {
                const node = entry.value_ptr.*;
                if (node.freed) {
                    const freed_ptr = entry.key_ptr.*;
                    if (reverse_alias.get(freed_ptr)) |aliasers| {
                        for (aliasers.items) |aliaser_ptr| {
                            if (mem_graph.?.nodes.get(aliaser_ptr)) |aliaser_node| {
                                if (!aliaser_node.freed) {
                                    _ = ctx.global_alloc_tracker.markFreed(aliaser_node.alloc_inst, "R8.3-f-alias-propagation");
                                    // Sync MemoryGraph.freed: propagate from original freed node.
                                    if (mem_graph) |mg| {
                                        const free_inst = node.freed_by orelse aliaser_node.alloc_inst;
                                        _ = mg.trackFree(free_inst, aliaser_ptr, node.alloc_lang) catch {};
                                    }
                                    propagated += 1;
                                }
                            }
                        }
                    }
                }
            }
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

    /// Extract debug file path from LLVM subprogram metadata.
    /// Used by NoiseReduction Layer 2 (path-based filter).
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
        global_tracker: *@import("../pass.zig").GlobalAllocTracker,
        lang: Lang,
        zone: ZoneKind,
        is_ffi_func: bool,
    ) !void {
        const opcode = c.LLVMGetInstructionOpcode(inst);
        const func_ptr = @as(u64, @intFromPtr(func));

        // P0-3c: For non-FFI functions, skip all MemoryGraph writes.
        // MemoryGraph is primarily consumed by DangerSurfacePass for FFI boundary
        // analysis. Non-FFI functions still get full pointer_map + leak tracking
        // via global_alloc_tracker — only the unified graph index is skipped.
        const mg_effective = if (is_ffi_func) mem_graph else null;

        switch (opcode) {
            c.LLVMAlloca => {
                const desc = try std.fmt.allocPrint(allocator, "stack alloca", .{});
                const info = PtrInfo{
                    .alloc_site = .stack,
                    .source_inst = inst,
                    .source_desc = desc,
                    .alloc_bb_id = bb_id,
                    .needs_free = true,
                };
                try putPtrInfo(pointer_map, inst, info, allocator);
                stats.total_pointers_tracked += 1;

                // v0.1.9: Sync alloca with MemoryGraph — mark as stack allocation.
                if (mg_effective) |mg| {
                    const inst_ptr = @as(u64, @intFromPtr(inst));
                    _ = mg.trackAlloc(inst_ptr, inst_ptr, .alloca, zone, lang) catch {};
                }
            },

            c.LLVMCall, c.LLVMInvoke => {
                const called = c.LLVMGetCalledValue(inst);
                if (@intFromPtr(called) != 0) {
                    const name_ptr = c.LLVMGetValueName(called);
                    if (@intFromPtr(name_ptr) != 0) {
                        const callee_name = std.mem.span(name_ptr);

                        for (HEAP_ALLOC_FUNCTIONS) |alloc_fn| {
                            if (std.mem.indexOf(u8, callee_name, alloc_fn) != null) {
                                // R7.1-1: realloc = free(old_ptr) + alloc(new_ptr)
                                // The old pointer (operand 0) is freed by realloc semantics.
                                // Without this, the old ptr stays "alive" in pointer_map,
                                // causing false double_free when the same logical pointer
                                // is later freed (realloc returned the same or different address).
                                if (std.mem.indexOf(u8, callee_name, "realloc") != null) {
                                    // realloc(ptr, size) = free(old_ptr) + alloc(new_ptr)
                                    //
                                    // LLVM IR semantics: old_ptr (operand 0) and inst (the call
                                    // instruction / return value) are ALWAYS different LLVMValueRefs,
                                    // even when realloc returns the same runtime address. Comparing them
                                    // with == compares compiler-internal pointers, not runtime values,
                                    // so `if (old_ptr == inst) return` would never trigger.
                                    //
                                    // Two-entry strategy (intentional):
                                    //   pointer_map[old_ptr] → marked freed (invalidated by realloc)
                                    //   pointer_map[inst]    → tracked as new allocation (what code uses next)
                                    //
                                    // This is correct because:
                                    //   - C standard requires using realloc's RETURN VALUE for subsequent ops
                                    //   - free(realloc_result) matches pointer_map[inst] entry → normal free
                                    //   - If code frees old_ptr directly, that's a REAL bug (double-free)
                                    const old_ptr = c.LLVMGetOperand(inst, 0);
                                    if (@intFromPtr(old_ptr) != 0) {
                                        if (pointer_map.getPtr(old_ptr)) |old_info| {
                                            if (!old_info.freed) {
                                                old_info.freed = true;
                                                const old_ptr_int = @as(u64, @intFromPtr(old_ptr));
                                                const func_name_raw = c.LLVMGetValueName(func);
                                                const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";
                                                _ = global_tracker.markFreed(old_ptr_int, func_name);
                                                // Sync MemoryGraph.freed for Source 1 consistency.
                                                if (mem_graph) |mg| {
                                                    const free_inst: u64 = @intFromPtr(inst);
                                                    _ = mg.trackFree(free_inst, old_ptr_int, lang) catch {};
                                                }
                                                _ = &old_info;
                                            }
                                        }
                                        // If old_ptr not found: silently skip (see Design decision above).
                                    }
                                }

                                const desc = try std.fmt.allocPrint(allocator, "heap via {s}()", .{callee_name});
                                const info = PtrInfo{
                                    .alloc_site = .heap,
                                    .source_inst = inst,
                                    .source_desc = desc,
                                    .alloc_bb_id = bb_id,
                                    .needs_free = true,
                                };
                                try putPtrInfo(pointer_map, inst, info, allocator);
                                stats.total_pointers_tracked += 1;

                                // v0.1.9: Sync with MemoryGraph — mark as heap allocation.
                                if (mg_effective) |mg| {
                                    const inst_ptr = @as(u64, @intFromPtr(inst));
                                    _ = mg.trackAlloc(inst_ptr, inst_ptr, .heap_alloc, zone, lang) catch {};
                                    mg.recordFuncAlloc(func_ptr);
                                }

                                // R8.3-b: Sync to GlobalAllocTracker for cross-function leak detection.
                                {
                                    const inst_ptr_val = @as(u64, @intFromPtr(inst));
                                    const fn_name_raw = c.LLVMGetValueName(func);
                                    const fn_name = if (fn_name_raw != null) std.mem.span(fn_name_raw) else "unknown";
                                    global_tracker.insertAlloc(inst_ptr_val, fn_name, false) catch {};
                                }
                                break;
                            }
                        }

                        // Triple-source heap detection — AllocatorKB check
                        if (getAllocatorKB()) |kb| {
                            if (kb.isAllocator(callee_name)) {
                                const desc = try std.fmt.allocPrint(allocator, "heap via allocator {s}()", .{callee_name});
                                const info = PtrInfo{
                                    .alloc_site = .heap,
                                    .source_inst = inst,
                                    .source_desc = desc,
                                    .alloc_bb_id = bb_id,
                                    .needs_free = true,
                                };
                                try putPtrInfo(pointer_map, inst, info, allocator);
                                stats.total_pointers_tracked += 1;

                                if (mg_effective) |mg| {
                                    const inst_ptr = @as(u64, @intFromPtr(inst));
                                    _ = mg.trackAlloc(inst_ptr, inst_ptr, .heap_alloc, zone, lang) catch {};
                                    mg.recordFuncAlloc(func_ptr);
                                }
                            }
                        }

                        if (is_resource_alloc_function(callee_name)) |res_type| {
                            const desc = try std.fmt.allocPrint(allocator, "resource via {s}()", .{callee_name});
                            const info = PtrInfo{
                                .alloc_site = .heap,
                                .source_inst = inst,
                                .source_desc = desc,
                                .alloc_bb_id = bb_id,
                                .resource_type = res_type,
                                .needs_free = true,
                            };
                            try putPtrInfo(pointer_map, inst, info, allocator);
                            stats.total_pointers_tracked += 1;

                            // v0.1.9: Sync resource allocation with MemoryGraph.
                            if (mg_effective) |mg| {
                                const inst_ptr = @as(u64, @intFromPtr(inst));
                                _ = mg.trackAlloc(inst_ptr, inst_ptr, .resource_alloc, zone, lang) catch {};
                                mg.recordFuncAlloc(func_ptr);
                            }
                        }

                        if (std.mem.indexOf(u8, callee_name, "dlsym") != null) {
                            const num_ops = c.LLVMGetNumOperands(inst);
                            var op_idx: u32 = 0;
                            while (op_idx < @min(num_ops, 2)) : (op_idx += 1) {
                                const handle_arg = c.LLVMGetOperand(inst, op_idx);
                                if (@intFromPtr(handle_arg) == 0) continue;
                                if (pointer_map.get(handle_arg)) |handle_info| {
                                    if (handle_info.resource_type == .dlopen_handle or
                                        handle_info.resource_type == .none)
                                    {
                                        const desc = try std.fmt.allocPrint(allocator, "dlsym-derived pointer from {s}", .{handle_info.source_desc});
                                        const info = PtrInfo{
                                            .alloc_site = .heap,
                                            .source_inst = inst,
                                            .source_desc = desc,
                                            .alloc_bb_id = bb_id,
                                            .derived_from_handle = handle_arg,
                                            .resource_type = handle_info.resource_type,
                                            .needs_free = true,
                                        };
                                        try putPtrInfo(pointer_map, inst, info, allocator);
                                        stats.total_pointers_tracked += 1;

                                        // v0.1.7: Sync dlsym-derived alias with MemoryGraph.
                                        // dlsym result lifecycle is bound to the handle —
                                        // closing the handle invalidates all derived pointers.
                                        if (mg_effective) |mg| {
                                            const inst_ptr = @as(u64, @intFromPtr(inst));
                                            const handle_ptr = @as(u64, @intFromPtr(handle_arg));
                                            mg.trackAliasStrong(inst_ptr, handle_ptr) catch {};
                                        }
                                    }
                                }
                            }
                        }

                        // v0.1.7: Double-free detection via Memory Graph.
                        if (isFreeFunction(callee_name)) {
                            // v0.1.9: Record free for alloc/free balance checking.
                            if (mg_effective) |mg| {
                                mg.recordFuncFree(func_ptr);
                            }
                            const ptr_arg = c.LLVMGetOperand(inst, 0);
                            if (pointer_map.getPtr(ptr_arg)) |ptr_info| {
                                if (ptr_info.freed and !ptr_info.double_free_detected) {
                                    const new_desc = try std.fmt.allocPrint(
                                        allocator,
                                        "DOUBLE_FREE: {s}",
                                        .{ptr_info.source_desc},
                                    );
                                    if (ptr_info.needs_free) {
                                        allocator.free(ptr_info.source_desc);
                                    }
                                    ptr_info.source_desc = new_desc;
                                    ptr_info.needs_free = true;
                                    ptr_info.double_free_detected = true;
                                } else {
                                    ptr_info.freed = true;
                                }
                            }

                            // R8.3-c: Sync to GlobalAllocTracker — mark allocation as freed.
                            {
                                const ptr_val = @as(u64, @intFromPtr(ptr_arg));
                                const fn_name_raw = c.LLVMGetValueName(func);
                                const fn_name = if (fn_name_raw != null) std.mem.span(fn_name_raw) else "unknown";
                                _ = global_tracker.markFreed(ptr_val, fn_name);
                                // CRITICAL FIX (v0.1.7): Also sync MemoryGraph.freed/freed_by.
                                // This eliminates the dual-source workaround in pointer_ownership.zig
                                // where Source 1 (MemoryGraph.freed_by) had 0 coverage because
                                // trackFree() was never called. Now both data structures stay synchronized.
                                if (mem_graph) |mg| {
                                    const free_inst: u64 = @intFromPtr(inst);
                                    _ = mg.trackFree(free_inst, ptr_val, lang) catch {};
                                }
                            }

                            // R8.4-d: Alias-aware free matching — when free(ptr) is called,
                            // check MemoryGraph for aliases of ptr that correspond to tracked
                            // allocations. If an alias was allocated but the alloc record
                            // isn't freed yet, mark it freed now. This prevents false-positive
                            // leak reports where malloc(A) → alias B → free(B), and A's
                            // alloc record was never matched.
                            if (mg_effective) |mg| {
                                const ptr_val = @as(u64, @intFromPtr(ptr_arg));
                                // Case 1: ptr_arg itself is a tracked node — find its aliases
                                if (mg.nodes.get(ptr_val)) |node| {
                                    var alias_iter = node.aliases.iterator();
                                    while (alias_iter.next()) |alias_entry| {
                                        const alias_ptr = alias_entry.key_ptr.*;
                                        // Safety check: verify pointer alignment before conversion
                                        // LLVMValueRef must be pointer-aligned (8 bytes on 64-bit)
                                        if (alias_ptr % @sizeOf(usize) != 0) continue;
                                        const alias_ref: c.LLVMValueRef = @ptrFromInt(alias_ptr);
                                        if (pointer_map.getPtr(alias_ref)) |alias_info| {
                                            if (!alias_info.freed and !alias_info.double_free_detected) {
                                                alias_info.freed = true;
                                            }
                                        }
                                    }
                                }
                                // Case 2: ptr_arg is an alias of some other tracked alloc node.
                                // Use alias_to_canonical index for O(1) lookup instead of O(N) scan.
                                if (mg.alias_to_canonical.get(ptr_val)) |canon_inst| {
                                    // Safety check: verify pointer alignment before conversion
                                    if (canon_inst % @sizeOf(usize) == 0) {
                                        const canon_ref: c.LLVMValueRef = @ptrFromInt(canon_inst);
                                        if (pointer_map.getPtr(canon_ref)) |canon_info| {
                                            if (!canon_info.freed and !canon_info.double_free_detected) {
                                                canon_info.freed = true;
                                            }
                                        }
                                        const fn_name_raw = c.LLVMGetValueName(func);
                                        const fn_name = if (fn_name_raw != null) std.mem.span(fn_name_raw) else "unknown";
                                        _ = global_tracker.markFreed(canon_inst, fn_name);
                                        // Sync MemoryGraph.freed for canonical alias free.
                                        const free_inst_canon: u64 = @intFromPtr(inst);
                                        _ = mg.trackFree(free_inst_canon, canon_inst, lang) catch {};
                                    }
                                }
                            }
                        }

                        if (isResourceCloseFunction(callee_name)) |closed_type| {
                            // v0.1.9: Record free for alloc/free balance checking.
                            if (mg_effective) |mg| {
                                mg.recordFuncFree(func_ptr);
                            }
                            const handle_arg = c.LLVMGetOperand(inst, 0);
                            if (pointer_map.getPtr(handle_arg)) |handle_info| {
                                handle_info.freed = true;
                                var it = pointer_map.iterator();
                                while (it.next()) |entry| {
                                    if (entry.value_ptr.resource_type == closed_type and
                                        entry.value_ptr.derived_from_handle != null)
                                    {
                                        const derived = entry.value_ptr.derived_from_handle.?;
                                        if (isSameOrAlias(derived, handle_arg)) {
                                            entry.value_ptr.freed = true;
                                        }
                                    }
                                }
                            } else {
                                var it = pointer_map.iterator();
                                while (it.next()) |entry| {
                                    if (entry.value_ptr.resource_type == closed_type and
                                        entry.value_ptr.derived_from_handle == null)
                                    {
                                        entry.value_ptr.freed = true;
                                    }
                                }
                            }
                        }

                        // R8.0: Record call edges in MemoryGraph for unified graph queries.
                        // P0-3c: Only track call edges for FFI-relevant functions.
                        if (is_ffi_func) {
                            if (mg_effective) |mg| {
                                const inst_ptr = @as(u64, @intFromPtr(inst));
                                // Issue2 FIX v2: Use standardized helper for CallInst argument count.
                                // OVERFLOW FIX: Removed (arg_i - 1) that caused integer underflow.
                                // After standardization refactor, arg_i now starts at 0 (not 1),
                                // so we pass arg_i directly without subtracting 1.
                                const num_args = getCallInstArgCount(inst);
                                var arg_i: u32 = 0;
                                while (arg_i < num_args) : (arg_i += 1) {
                                    const arg = c.LLVMGetOperand(inst, arg_i);
                                    if (@intFromPtr(arg) == 0) continue;
                                    const arg_ptr_val = @as(u64, @intFromPtr(arg));
                                    if (mg.nodes.get(arg_ptr_val) != null or pointer_map.contains(arg)) {
                                        _ = mg.trackCallArg(inst_ptr, callee_name, arg_ptr_val, arg_i) catch {};
                                    }
                                }
                                if (pointer_map.contains(inst)) {
                                    const ret_ptr_val = @as(u64, @intFromPtr(inst));
                                    _ = mg.trackCallRet(inst_ptr, callee_name, ret_ptr_val) catch {};
                                }
                            } // is_ffi_func: mem_graph
                        } // is_ffi_func
                    }
                }
            },

            c.LLVMLoad => {
                // v0.1.9: Load inherits the content source of the loaded pointer.
                // If %ptr points to an alloca that contains a heap pointer,
                // the loaded value's source is .heap_alloc (not .alloca).
                if (mg_effective) |mg| {
                    const src_ptr = @as(u64, @intFromPtr(c.LLVMGetOperand(inst, 0)));
                    const content_kind = mg.getContentSource(src_ptr);
                    if (content_kind != .unknown) {
                        const inst_ptr = @as(u64, @intFromPtr(inst));
                        _ = mg.trackAlloc(inst_ptr, inst_ptr, content_kind, zone, lang) catch {};
                    }
                }
                try propagateOrigin(inst, c.LLVMGetOperand(inst, 0), pointer_map, allocator, bb_id, mem_graph);

                // After propagateOrigin, check MemoryGraph contentSource.
                // propagateOrigin gives the load result the pointer's own origin
                // (e.g., .stack from alloca), but the CONTENT stored in that
                // alloca may be a heap pointer. Override pointer_map entry
                // when content source is .heap_alloc or .resource_alloc.
                // This fixes RETURN-STACK false positives where load from
                // an alloca that stores a malloc result is misclassified.
                if (mg_effective) |mg| {
                    const src_ptr = @as(u64, @intFromPtr(c.LLVMGetOperand(inst, 0)));
                    const content_kind = mg.getContentSource(src_ptr);
                    if (content_kind == .heap_alloc or content_kind == .resource_alloc) {
                        if (pointer_map.getPtr(inst)) |load_info| {
                            load_info.alloc_site = .heap;
                        }
                    }
                }
            },

            c.LLVMStore => {
                const value = c.LLVMGetOperand(inst, 0);
                const dest = c.LLVMGetOperand(inst, 1);

                // v0.1.9: Mark alloca as param storage if storing a function parameter.
                // Pattern: %arg.addr = alloca i32; store i32 %arg, ptr %arg.addr
                // This alloca is just a local copy of a parameter — safe.
                if (isFuncParam(value, func)) {
                    if (pointer_map.getPtr(dest)) |dest_info| {
                        if (dest_info.alloc_site == .stack) {
                            dest_info.is_param_storage = true;
                        }
                    }
                }
                // Store does NOT change dest's own source — dest is still whatever
                // it was (alloca, heap, etc.). But we record what kind of value
                // was stored INTO dest, so that load can inherit the content's source.
                if (pointer_map.get(value)) |src_info| {
                    // Record content source: dest now contains a value whose
                    // source is src_info.alloc_site.
                    if (mg_effective) |mg| {
                        const dest_ptr = @as(u64, @intFromPtr(dest));
                        const content_kind: memory_graph.SourceKind = switch (src_info.alloc_site) {
                            .heap => .heap_alloc,
                            .stack => .alloca,
                            .global => .unknown,
                            .parameter => .unknown,
                            .constant => .unknown,
                            .unknown => .unknown,
                        };
                        mg.recordContentSource(dest_ptr, content_kind);
                    }

                    // Still propagate via pointer_map for double-free tracking
                    // (alias relationship: dest aliases to value's allocation).
                    var new_info = src_info;
                    const desc = try allocator.dupe(u8, src_info.source_desc);
                    new_info.source_desc = desc;
                    new_info.needs_free = true;
                    try putPtrInfo(pointer_map, dest, new_info, allocator);

                    // Sync alias with MemoryGraph for cross-alias double-free.
                    if (mg_effective) |mg| {
                        const from_hash = @as(u64, @intFromPtr(dest));
                        const to_hash = @as(u64, @intFromPtr(value));
                        mg.trackAliasStrong(from_hash, to_hash) catch {};
                    }
                } else {
                    // v0.1.6: Record content source even when value is not in pointer_map.
                    // This handles stores from global constants, function parameters,
                    // and untracked call results — without this, load inherits the
                    // alloca's .stack source instead of the actual content source.
                    if (mg_effective) |mg| {
                        const dest_ptr = @as(u64, @intFromPtr(dest));
                        const content_kind = inferContentKind(value);
                        if (content_kind != .unknown) {
                            mg.recordContentSource(dest_ptr, content_kind);
                        }
                    }
                }
            },

            c.LLVMGetElementPtr => {
                const src = c.LLVMGetOperand(inst, 0);
                _ = pointer_map.get(src) != null;
                try propagateOrigin(inst, c.LLVMGetOperand(inst, 0), pointer_map, allocator, bb_id, mem_graph);
            },

            // P2-1 fix: Pointer identity conversion instructions must propagate origin
            // to maintain alias chains. Without this:
            //   %p2 = bitcast %p1 → %p2 is NOT tracked as alias of %p1
            //   free(%p2) → double-free detection FAILS (origin lost)
            //
            // These instructions are semantically "no-op" for pointer identity:
            // - LLVMBitCast: %p2 = bitcast i8* %p1 to i32* (type change only)
            // - LLVMPtrToInt: %i = ptrtoint i8* %p1 to i64 (pointer → integer)
            // - LLVMIntToPtr: %p2 = inttoptr i64 %i to i8* (integer → pointer)
            // - LLVMAddrSpaceCast: %p2 = addrspacecast i8* %p1 to i8 addrspace(1)
            c.LLVMBitCast,
            c.LLVMPtrToInt,
            c.LLVMIntToPtr,
            c.LLVMAddrSpaceCast,
            => {
                const src = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(src) != 0) {
                    try propagateOrigin(inst, src, pointer_map, allocator, bb_id, mem_graph);
                }
            },

            // Phi node tracking — merge all incoming values' origins.
            // If any incoming value is .heap, phi is .heap (runtime may take
            // that branch). If all are .stack, phi is .stack. This prevents
            // phi-returning functions from being skipped entirely when
            // pointer_map.get(%phi) returns null.
            c.LLVMPHI => {
                const num_incoming = c.LLVMCountIncoming(inst);
                var merged_site: PtrAllocSite = .constant;
                var found_any: bool = false;
                var best_desc: []const u8 = "phi merge";

                var i: u32 = 0;
                while (i < num_incoming) : (i += 1) {
                    const incoming = c.LLVMGetIncomingValue(inst, i);
                    if (@intFromPtr(incoming) == 0) continue;

                    if (pointer_map.get(incoming)) |incoming_info| {
                        found_any = true;
                        // Priority: heap > parameter > stack > global > constant
                        // If any branch is heap, the phi result could be heap.
                        merged_site = mergeAllocSite(merged_site, incoming_info.alloc_site);
                        if (incoming_info.alloc_site == .heap or
                            incoming_info.alloc_site == .parameter)
                        {
                            best_desc = incoming_info.source_desc;
                        }
                    }
                }

                if (found_any) {
                    const desc = try allocator.dupe(u8, best_desc);
                    const info = PtrInfo{
                        .alloc_site = merged_site,
                        .source_inst = inst,
                        .source_desc = desc,
                        .alloc_bb_id = bb_id,
                        .needs_free = true,
                    };
                    try putPtrInfo(pointer_map, inst, info, allocator);
                }
            },

            // v0.1.6: Track whether this function returns a pointer.
            // Used by checkCallViolation to identify sink functions:
            // functions that don't return pointers are likely consumers,
            // not forwarders, so passing a stack pointer to them is safer.
            c.LLVMRet => {
                if (mg_effective) |mg| {
                    const num_ops = c.LLVMGetNumOperands(inst);
                    if (num_ops > 0) {
                        const ret_val = c.LLVMGetOperand(inst, 0);
                        if (@intFromPtr(ret_val) != 0) {
                            const ret_type = c.LLVMTypeOf(ret_val);
                            if (@intFromPtr(ret_type) != 0 and
                                c.LLVMGetTypeKind(ret_type) == c.LLVMPointerTypeKind)
                            {
                                mg.recordFuncReturns(func_ptr);
                            }
                        }
                    }
                }
            },

            else => {},
        }
    }

    /// Infer the content source kind of a value that is not in pointer_map.
    /// Used by store's else branch to record content_source for values that
    /// pointer_map doesn't track (global constants, function params, etc.).
    fn inferContentKind(value: c.LLVMValueRef) memory_graph.SourceKind {
        // Global variable (e.g., @.str.1027, @g_var)
        if (c.LLVMIsAGlobalValue(value) != null) return .resource_alloc;
        // Function pointer
        if (c.LLVMIsAFunction(value) != null) return .resource_alloc;
        // Constant expression or constant int (null pointer, inttoptr, etc.)
        if (c.LLVMIsAConstant(value) != null) return .resource_alloc;

        // Call/invoke result — the callee may return heap memory.
        const opcode = c.LLVMGetInstructionOpcode(value);
        if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
            const called = c.LLVMGetCalledValue(value);
            if (@intFromPtr(called) != 0) {
                const name_ptr = c.LLVMGetValueName(called);
                if (@intFromPtr(name_ptr) != 0) {
                    const callee_name = std.mem.span(name_ptr);
                    // Check if this is a known allocator function
                    if (getAllocatorKB()) |kb| {
                        if (kb.isAllocator(callee_name)) return .heap_alloc;
                    }
                    // Fallback: check common allocator patterns
                    if (std.mem.indexOf(u8, callee_name, "malloc") != null or
                        std.mem.indexOf(u8, callee_name, "calloc") != null or
                        std.mem.indexOf(u8, callee_name, "realloc") != null)
                    {
                        return .heap_alloc;
                    }
                }
            }
            return .call_result;
        }

        return .unknown;
    }

    fn putPtrInfo(
        map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
        key: c.LLVMValueRef,
        info: PtrInfo,
        allocator: std.mem.Allocator,
    ) !void {
        const gop = try map.getOrPut(key);
        if (gop.found_existing and gop.value_ptr.needs_free) {
            allocator.free(gop.value_ptr.source_desc);
        }
        gop.value_ptr.* = info;
    }

    /// Merge two allocation sites for phi node tracking.
    /// Priority: heap > parameter > stack > global > constant > unknown.
    /// If any incoming branch is heap, the phi result could be heap at runtime.
    fn mergeAllocSite(current: PtrAllocSite, incoming: PtrAllocSite) PtrAllocSite {
        // If either is heap, result is heap (runtime may take that branch)
        if (current == .heap or incoming == .heap) return .heap;
        // Parameter is next priority (could be any origin)
        if (current == .parameter or incoming == .parameter) return .parameter;
        // Stack: both must be stack for result to be stack
        if (current == .stack or incoming == .stack) return .stack;
        // Global
        if (current == .global or incoming == .global) return .global;
        // Constant
        if (current == .constant or incoming == .constant) return .constant;
        return .unknown;
    }

    fn propagateOrigin(
        dst: c.LLVMValueRef,
        src: c.LLVMValueRef,
        pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
        allocator: std.mem.Allocator,
        bb_id: usize,
        mem_graph: ?*memory_graph.MemoryGraph,
    ) !void {
        if (pointer_map.get(src)) |src_info| {
            const desc = try allocator.dupe(u8, src_info.source_desc);
            var new_info = src_info;
            new_info.source_desc = desc;
            new_info.alloc_bb_id = bb_id;
            new_info.needs_free = true;
            try putPtrInfo(pointer_map, dst, new_info, allocator);

            // v0.1.7: Sync alias with MemoryGraph.
            if (mem_graph) |mg| {
                const from_hash = @as(u64, @intFromPtr(dst));
                const to_hash = @as(u64, @intFromPtr(src));
                mg.trackAliasStrong(from_hash, to_hash) catch {};
            }
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
