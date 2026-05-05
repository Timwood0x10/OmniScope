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

const zone_cls = @import("../../semantics/zone_classifier.zig");
const ZoneKind = zone_cls.ZoneKind;
const Lang = zone_cls.Language;

const FfiLang = @import("../../diag/issue.zig").FFIBoundary.Language;

fn toZoneLanguage(lang: FfiLang) Lang {
    return switch (lang) {
        .c => .c,
        .cpp => .cpp,
        .rust => .rust,
        .zig => .zig,
        .go => .go,
        .swift => .unknown,
        else => .unknown,
    };
}

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

// v0.1.8: New semantic modules
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

    fn init(allocator: std.mem.Allocator) FreeSiteList {
        return .{ .items = &.{}, .len = 0, .capacity = 0, .allocator = allocator };
    }

    fn append(self: *FreeSiteList, record: FreeSiteRecord) !void {
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

    fn deinit(self: *FreeSiteList) void {
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

            // v0.1.8: Three-layer noise reduction (supersedes zone-only check)
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
            if (!full_classification.origin.shouldReportByDefault()) {
                diag.debug("NOISE-SKIP: {s} is {s} — {s}", .{ func_name, full_classification.origin.toString(), full_classification.reason });
                continue;
            }

            // Defense-in-depth: known FP whitelist (v0.1.8 audit verified)
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
            const is_ffi_func = ffi_func_names.contains(func_name);

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

                                        // v0.1.8: Sync dlsym-derived alias with MemoryGraph.
                                        // dlsym result lifecycle is bound to the handle —
                                        // closing the handle invalidates all derived pointers.
                                        if (mg_effective) |mg| {
                                            const inst_ptr = @as(u64, @intFromPtr(inst));
                                            const handle_ptr = @as(u64, @intFromPtr(handle_arg));
                                            mg.trackAlias(inst_ptr, handle_ptr) catch {};
                                        }
                                    }
                                }
                            }
                        }

                        // v0.1.8: Double-free detection via Memory Graph.
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
                                        // Convert back to LLVMValueRef for pointer_map lookup
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
                                    const canon_ref: c.LLVMValueRef = @ptrFromInt(canon_inst);
                                    if (pointer_map.getPtr(canon_ref)) |canon_info| {
                                        if (!canon_info.freed and !canon_info.double_free_detected) {
                                            canon_info.freed = true;
                                        }
                                    }
                                    const fn_name_raw = c.LLVMGetValueName(func);
                                    const fn_name = if (fn_name_raw != null) std.mem.span(fn_name_raw) else "unknown";
                                    _ = global_tracker.markFreed(canon_inst, fn_name);
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
                                const num_ops = c.LLVMGetNumOperands(inst);
                                var arg_i: u32 = 1;
                                while (arg_i < num_ops) : (arg_i += 1) {
                                    const arg = c.LLVMGetOperand(inst, arg_i);
                                    if (@intFromPtr(arg) == 0) continue;
                                    const arg_ptr_val = @as(u64, @intFromPtr(arg));
                                    if (mg.nodes.get(arg_ptr_val) != null or pointer_map.contains(arg)) {
                                        _ = mg.trackCallArg(inst_ptr, callee_name, arg_ptr_val, arg_i - 1) catch {};
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
                        mg.trackAlias(from_hash, to_hash) catch {};
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

            // v0.1.8: Sync alias with MemoryGraph.
            if (mem_graph) |mg| {
                const from_hash = @as(u64, @intFromPtr(dst));
                const to_hash = @as(u64, @intFromPtr(src));
                mg.trackAlias(from_hash, to_hash) catch {};
            }
        }
    }

    fn checkViolations(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        func: c.LLVMValueRef,
        func_name: []const u8,
        bb_id: usize,
        bb_ref: c.LLVMValueRef,
        pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
        mem_graph: ?*memory_graph.MemoryGraph,
        diag: *DiagnosticWriter,
        stats: *LifetimeStats,
        free_sites: *std.AutoHashMap(u64, FreeSiteList),
    ) !void {
        // Null pointer guard — prevent SIGABRT on invalid IR
        if (@intFromPtr(inst) == 0) return;

        const opcode = c.LLVMGetInstructionOpcode(inst);

        if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
            try checkDoubleFreeViolation(ctx, inst, func_name, bb_id, bb_ref, pointer_map, mem_graph, diag, stats, free_sites);
            try checkCallViolation(ctx, inst, func, func_name, bb_id, pointer_map, mem_graph, diag, stats);
        }

        if (opcode == c.LLVMRet) {
            try checkReturnViolation(ctx, inst, func, func_name, pointer_map, mem_graph, diag, stats);
        }

        if (opcode == c.LLVMStore) {
            try checkStoreToGlobal(ctx, inst, func_name, pointer_map, diag, stats);
        }
    }

    /// P0-3: Path-sensitive double-free detection.
    /// Records each free's basic block and checks if two frees of the same
    /// pointer are on mutually exclusive execution paths (sibling blocks
    /// with the same conditional branch predecessor, or RC==0 pattern).
    fn checkDoubleFreeViolation(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        func_name: []const u8,
        bb_id: usize,
        bb_ref: c.LLVMValueRef,
        pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
        mem_graph: ?*memory_graph.MemoryGraph,
        diag: *DiagnosticWriter,
        stats: *LifetimeStats,
        free_sites: *std.AutoHashMap(u64, FreeSiteList),
    ) !void {
        const called = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called) == 0) return;

        const name_ptr = c.LLVMGetValueName(called);
        if (@intFromPtr(name_ptr) == 0) return;

        const callee_name = std.mem.span(name_ptr);

        if (!isFreeFunction(callee_name)) return;

        const ptr_arg = c.LLVMGetOperand(inst, 0);
        const ptr_hash = @as(u64, @intFromPtr(ptr_arg));

        // Record this free site for path-sensitive analysis
        const record = FreeSiteRecord{
            .bb_id = bb_id,
            .bb_ref = bb_ref,
            .free_inst = inst,
        };

        const gop = try free_sites.getOrPut(ptr_hash);
        if (!gop.found_existing) {
            gop.value_ptr.* = FreeSiteList.init(ctx.allocator);
        }
        try gop.value_ptr.append(record);

        // Check if this pointer has been freed before
        const sites = free_sites.get(ptr_hash) orelse return;
        if (sites.len <= 1) return; // First free — no double-free yet

        // P0-3: Path-sensitive check — are the two frees on mutually
        // exclusive paths? If so, this is NOT a real double-free.
        const prev_record = sites.items[sites.len - 2];
        if (areMutuallyExclusive(prev_record.bb_ref, bb_ref)) {
            diag.debug("[SUPPRESSED] Double-free on mutually exclusive paths in {s} (bb {} vs bb {})", .{ func_name, prev_record.bb_id, bb_id });
            return;
        }

        // Check for RC (reference count) pattern.
        // Pattern: load RC -> sub 1 -> cmp 0 -> br; free in RC==0 branch.
        // This is a conditional free, not a double-free.
        if (isRCPatternFree(prev_record.bb_ref) or isRCPatternFree(bb_ref)) {
            diag.debug("[SUPPRESSED] Double-free under RC==0 guard in {s}", .{func_name});
            return;
        }

        // Not on mutually exclusive paths — report as real double-free.
        // Also use MemoryGraph for cross-alias detection.
        if (mem_graph) |mg| {
            const inst_ptr = @as(u64, @intFromPtr(inst));
            const free_lang: Lang = toZoneLanguage(ctx.module_language.language);
            const is_double = mg.trackFree(inst_ptr, ptr_hash, free_lang) catch false;
            if (is_double) {
                if (!ctx.isRelevantAlloc(ptr_hash)) return;
                const msg = try std.fmt.allocPrint(ctx.allocator, "[OMI-HIGH] [DOUBLE_FREE] MemoryGraph detected double-free of pointer in {s}", .{func_name});
                // NOTE: msg memory is owned by Issue (owned=true in initWithTrace).
                // Do NOT free msg here - Issue.deinit() will handle cleanup when needed.
                const trace = try ctx.allocator.alloc(TraceEntry, 1);
                errdefer ctx.allocator.free(trace);
                trace[0] = TraceEntry.init("Double-free detected via MemoryGraph trackFree");
                const issue = Issue.initWithTrace(
                    .double_free,
                    msg,
                    Location.init(func_name),
                    .high,
                    0.90,
                    trace,
                );
                try ctx.addIssue(&issue);
                // NOTE: Issue already contains full diagnostic info.
                // No separate diag.warn needed - would cause duplicate reporting.
                stats.use_after_free_found += 1;
                return;
            }
        }

        // Fallback: pointer_map based detection (same-value double-free only).
        if (pointer_map.get(ptr_arg)) |ptr_info| {
            if (ptr_info.double_free_detected) {
                if (!ctx.isRelevantAlloc(ptr_hash)) return;
                // H3 FIX: Create Issue for fallback path too (consistent with MemoryGraph path)
                const fb_msg = try std.fmt.allocPrint(ctx.allocator, "[OMI-HIGH] [DOUBLE_FREE] {s} freed twice in {s}", .{ ptr_info.source_desc, func_name });
                const fb_trace = try ctx.allocator.alloc(TraceEntry, 1);
                errdefer ctx.allocator.free(fb_trace);
                fb_trace[0] = TraceEntry.init("Double-free detected via pointer_map fallback");
                const fb_issue = Issue.initWithTrace(
                    .double_free,
                    fb_msg,
                    Location.init(func_name),
                    .high,
                    0.80,
                    fb_trace,
                );
                try ctx.addIssue(&fb_issue);
                stats.use_after_free_found += 1;
            }
        }
    }

    /// Check if two basic blocks are mutually exclusive — they are
    /// siblings (same predecessor, different branches of a conditional branch).
    /// In this case, only one of them executes at runtime.
    fn areMutuallyExclusive(bb1: c.LLVMValueRef, bb2: c.LLVMValueRef) bool {
        if (@intFromPtr(bb1) == 0 or @intFromPtr(bb2) == 0) return false;
        if (@intFromPtr(bb1) == @intFromPtr(bb2)) return false;

        // Get predecessors of both blocks
        // If they share a common predecessor that is a conditional branch
        // with exactly 2 successors (bb1 and bb2), they are mutually exclusive.
        const pred1 = getSinglePredecessor(@ptrCast(bb1));
        const pred2 = getSinglePredecessor(@ptrCast(bb2));

        if (@intFromPtr(pred1) == 0 or @intFromPtr(pred2) == 0) return false;
        if (@intFromPtr(pred1) != @intFromPtr(pred2)) return false;

        // Common predecessor — check terminator instruction type
        const term_inst = c.LLVMGetBasicBlockTerminator(@ptrCast(pred1));
        if (@intFromPtr(term_inst) == 0) return false;

        const opcode = c.LLVMGetInstructionOpcode(term_inst);
        const num_successors = c.LLVMGetNumSuccessors(pred1);

        // Case 1: Conditional branch (br i1) with exactly 2 successors
        if (opcode == c.LLVMBr and num_successors == 2) {
            const succ0 = c.LLVMGetSuccessor(pred1, 0);
            const succ1 = c.LLVMGetSuccessor(pred1, 1);

            // Check if the two successors are exactly bb1 and bb2
            const match = (@intFromPtr(succ0) == @intFromPtr(bb1) and @intFromPtr(succ1) == @intFromPtr(bb2)) or
                (@intFromPtr(succ0) == @intFromPtr(bb2) and @intFromPtr(succ1) == @intFromPtr(bb1));
            return match;
        }

        // M4 FIX: Case 2: Switch instruction — all case/default targets are mutually exclusive
        if (opcode == c.LLVMSwitch and num_successors >= 2) {
            var found_bb1 = false;
            var found_bb2 = false;
            var succ_idx: u32 = 0;
            while (succ_idx < num_successors) : (succ_idx += 1) {
                const succ = c.LLVMGetSuccessor(pred1, succ_idx);
                if (@intFromPtr(succ) == @intFromPtr(bb1)) found_bb1 = true;
                if (@intFromPtr(succ) == @intFromPtr(bb2)) found_bb2 = true;
                if (found_bb1 and found_bb2) return true; // Both blocks are switch targets → mutually exclusive
            }
            return false;
        }

        return false;
    }

    /// Get the single predecessor of a basic block.
    /// Returns null if the block has 0 or more than 1 predecessor.
    fn getSinglePredecessor(bb: c.LLVMBasicBlockRef) c.LLVMValueRef {
        // Iterate all instructions in the function to find branches
        // that target this block. This is O(n) but only called when
        // a potential double-free is detected (rare in practice).
        const func = c.LLVMGetBasicBlockParent(bb);
        if (@intFromPtr(func) == 0) return null;

        var result: c.LLVMValueRef = null;
        var cur_bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(cur_bb) != 0) : (cur_bb = c.LLVMGetNextBasicBlock(cur_bb)) {
            const term = c.LLVMGetBasicBlockTerminator(cur_bb);
            if (@intFromPtr(term) == 0) continue;

            const num_succ = c.LLVMGetNumSuccessors(term);
            var i: u32 = 0;
            while (i < num_succ) : (i += 1) {
                const succ = c.LLVMGetSuccessor(term, i);
                if (@intFromPtr(succ) == @intFromPtr(bb)) {
                    // Found a predecessor
                    if (@intFromPtr(result) != 0) {
                        // More than one predecessor — return null
                        return null;
                    }
                    result = @ptrCast(cur_bb);
                }
            }
        }
        return result;
    }

    /// Check if a basic block contains an RC (reference count) pattern
    /// that guards a free. Pattern: load RC -> sub 1 -> cmp eq 0 -> br.
    /// If the free is in the RC==0 branch, it's a conditional free.
    fn isRCPatternFree(bb: c.LLVMValueRef) bool {
        if (@intFromPtr(bb) == 0) return false;

        // Look for the pattern: sub N, 1 followed by icmp eq N-1, 0
        // This is the standard RC decrement + check pattern.
        var inst = c.LLVMGetFirstInstruction(@ptrCast(bb));
        var has_sub_one: bool = false;
        var has_cmp_zero: bool = false;

        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);

            // Pattern: sub N, 1 (RC decrement)
            if (opcode == c.LLVMSub) {
                if (c.LLVMGetNumOperands(inst) >= 2) {
                    const rhs = c.LLVMGetOperand(inst, 1);
                    // Check if RHS is constant 1
                    if (c.LLVMIsAConstantInt(rhs) != null) {
                        const val = c.LLVMConstIntGetZExtValue(rhs);
                        if (val == 1) {
                            has_sub_one = true;
                        }
                    }
                }
            }

            // Pattern: icmp eq, 0 (RC == 0 check)
            if (opcode == c.LLVMICmp) {
                if (c.LLVMGetNumOperands(inst) >= 2) {
                    const rhs = c.LLVMGetOperand(inst, 1);
                    if (c.LLVMIsAConstantInt(rhs) != null) {
                        const val = c.LLVMConstIntGetZExtValue(rhs);
                        if (val == 0) {
                            has_cmp_zero = true;
                        }
                    }
                }
            }
        }

        // Both sub-1 and cmp-0 in the same block or its predecessors
        // indicates an RC pattern guarding this free.
        return has_sub_one and has_cmp_zero;
    }

    fn checkStoreToGlobal(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        func_name: []const u8,
        pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
        diag: *DiagnosticWriter,
        stats: *LifetimeStats,
    ) !void {
        const ptr_operand = c.LLVMGetOperand(inst, 1);
        const value_operand = c.LLVMGetOperand(inst, 0);

        if (ptr_operand == null or value_operand == null) return;

        if (isGlobalVariable(ptr_operand)) {
            if (pointer_map.get(value_operand)) |ptr_info| {
                if (ptr_info.alloc_site == .heap and !ptr_info.escaped) {
                    try reportHeapToGlobal(ctx, func_name, ptr_info, inst, diag);
                    stats.heap_ambiguous_found += 1;
                    if (pointer_map.getPtr(value_operand)) |pi| pi.escaped = true;
                } else if (ptr_info.alloc_site == .stack and !ptr_info.escaped) {
                    try reportStackToGlobal(ctx, func_name, ptr_info, inst, diag);
                    stats.stack_escapes_found += 1;
                    if (pointer_map.getPtr(value_operand)) |pi| pi.escaped = true;
                }
            }
        }
    }

    fn isGlobalVariable(ptr: c.LLVMValueRef) bool {
        if (ptr == null) return false;
        const value_kind = c.LLVMGetValueKind(ptr);
        return value_kind == c.LLVMGlobalVariableValueKind;
    }

    fn checkCallViolation(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        _: c.LLVMValueRef,
        func_name: []const u8,
        _: usize,
        pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
        mem_graph: ?*memory_graph.MemoryGraph,
        diag: *DiagnosticWriter,
        stats: *LifetimeStats,
    ) !void {
        const called = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called) == 0) return;

        const name_ptr = c.LLVMGetValueName(called);
        if (@intFromPtr(name_ptr) == 0) return;

        const callee_name = std.mem.span(name_ptr);

        if (!may_retain_pointer(callee_name)) return;

        // v0.1.6: Cross-function sink detection via MemoryGraph.
        // If the callee function never returns a pointer, it's likely a sink
        // that consumes its arguments rather than forwarding them.
        // Passing a stack pointer to a sink is much safer than passing to
        // a function that might store or return the pointer.
        //
        // Two detection strategies:
        //   1. Defined functions: FuncCounter.returns_pointer (from ret tracking)
        //   2. Declared functions (no body): check call instruction's return type
        if (mem_graph) |mg| {
            const callee_ptr = @as(u64, @intFromPtr(called));
            const callee_counter = mg.getFuncCounter(callee_ptr);

            // For declared functions (no body), infer from call return type.
            // If the call returns void/non-pointer, the callee is a sink.
            const callee_returns_ptr = if (callee_counter.hasHeapOps())
                callee_counter.returns_pointer
            else blk: {
                // Declared function — check call return type directly.
                const ret_type = c.LLVMTypeOf(inst);
                if (@intFromPtr(ret_type) != 0 and
                    c.LLVMGetTypeKind(ret_type) == c.LLVMPointerTypeKind)
                {
                    break :blk true;
                }
                break :blk false;
            };

            if (!callee_returns_ptr) {
                const num_ops = c.LLVMGetNumOperands(inst);
                var i: u32 = 0;
                while (i < num_ops) : (i += 1) {
                    const arg = c.LLVMGetOperand(inst, i);
                    if (pointer_map.get(arg)) |ptr_info| {
                        if (ptr_info.alloc_site == .stack and !ptr_info.escaped) {
                            const is_extern = is_extern_function(callee_name) or
                                (std.mem.indexOf(u8, callee_name, "ffi_") != null);
                            if (is_extern) {
                                try report.reportStackEscape(ctx, func_name, callee_name, ptr_info, inst, diag);
                            } else {
                                diag.debug("[SUPPRESSED] Stack escape to sink function (no pointer return): {s}", .{callee_name});
                            }
                            stats.stack_escapes_found += 1;
                            if (pointer_map.getPtr(arg)) |pi| pi.escaped = true;
                        } else if (ptr_info.freed) {
                            if (!ctx.isRelevantAlloc(@as(u64, @intFromPtr(arg)))) continue;
                            if (ptr_info.resource_type != .none) {
                                try reportResourceUAF(ctx, func_name, callee_name, ptr_info, inst, diag);
                            } else {
                                try reportUseAfterFree(ctx, func_name, callee_name, ptr_info, inst, diag);
                            }
                            stats.use_after_free_found += 1;
                        }
                    }
                }
                return;
            }
        }

        const num_ops = c.LLVMGetNumOperands(inst);
        var i: u32 = 0;
        while (i < num_ops) : (i += 1) {
            const arg = c.LLVMGetOperand(inst, i);
            if (pointer_map.get(arg)) |ptr_info| {
                if (ptr_info.alloc_site == .stack and !ptr_info.escaped) {
                    // Check suppression for callback/hook patterns
                    if (isStackEscapeSuppressed(callee_name, ptr_info)) {
                        diag.debug("[SUPPRESSED] Stack escape in callback/hook: {s}", .{callee_name});
                        stats.stack_escapes_found += 1;
                    } else {
                        try reportStackEscape(ctx, func_name, callee_name, ptr_info, inst, diag);
                        stats.stack_escapes_found += 1;
                    }
                    if (pointer_map.getPtr(arg)) |pi| pi.escaped = true;
                } else if (ptr_info.alloc_site == .heap and !ptr_info.escaped) {
                    // v0.1.6: Heap pointer escaping to FFI is also critical.
                    // A malloc'd buffer passed to an extern retaining function means
                    // the caller must know to free it — classic FFI ownership bug.
                    try reportHeapEscapeToFFI(ctx, func_name, callee_name, ptr_info, inst, diag);
                    stats.heap_ambiguous_found += 1;
                    if (pointer_map.getPtr(arg)) |pi| pi.escaped = true;
                } else if (ptr_info.freed) {
                    if (!ctx.isRelevantAlloc(@as(u64, @intFromPtr(arg)))) continue;
                    if (ptr_info.resource_type != .none) {
                        try reportResourceUAF(ctx, func_name, callee_name, ptr_info, inst, diag);
                    } else {
                        try reportUseAfterFree(ctx, func_name, callee_name, ptr_info, inst, diag);
                    }
                    stats.use_after_free_found += 1;
                }
            }
        }
    }

    fn checkReturnViolation(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        func: c.LLVMValueRef,
        func_name: []const u8,
        pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
        mem_graph: ?*memory_graph.MemoryGraph,
        diag: *DiagnosticWriter,
        stats: *LifetimeStats,
    ) !void {
        const num_ops = c.LLVMGetNumOperands(inst);
        if (num_ops == 0) return;

        if (isCppDestructorOrConstructor(func_name)) {
            return;
        }

        // v0.1.8: Use OutputParamClassifier for precise C API output param detection.
        if (output_param_classifier.OutputParamClassifier.isLikelyOutputParamFunction(func_name)) {
            diag.debug("[SUPPRESSED] C API output parameter pattern: {s} (known output-param family)", .{func_name});
            stats.heap_intentional_transfer += 1;
            return;
        }

        // Fallback: non-pointer return type check (e.g. int-returning functions)
        if (isNonPointerReturnType(inst)) {
            diag.debug("[SUPPRESSED] C API output parameter pattern: {s} returns non-pointer (likely using output params)", .{func_name});
            return;
        }

        const retval = c.LLVMGetOperand(inst, 0);

        // v0.1.9: Use MemoryGraph source kind to filter borrow_escape FP.
        // If the return value is known to come from a heap/resource allocation,
        // it cannot be a borrow_escape (stack address return).
        if (mem_graph) |mg| {
            const retval_ptr = @as(u64, @intFromPtr(retval));
            const source = mg.getSourceKind(retval_ptr);
            if (source == .heap_alloc or source == .resource_alloc) {
                // Return value comes from malloc/calloc/dlopen/etc. — safe.
                diag.debug("[SUPPRESSED] Return value is heap/resource allocation (MemoryGraph): {s}", .{func_name});
                stats.heap_intentional_transfer += 1;
                return;
            }

            // v0.1.9: Alloc/free balance check.
            // If this function has net positive allocations (more allocs than frees),
            // it's likely a factory/constructor that returns heap memory.
            // This is a project-agnostic signal — no whitelists needed.
            const func_ptr = @as(u64, @intFromPtr(func));
            const counter = mg.getFuncCounter(func_ptr);
            if (counter.hasHeapOps() and counter.net() > 0) {
                diag.debug("[SUPPRESSED] Function has net heap allocations ({d} allocs, {d} frees): {s}", .{ counter.allocs, counter.frees, func_name });
                stats.heap_intentional_transfer += 1;
                return;
            }

            // v0.1.6: Check callee's alloc/free balance.
            // Wrapper functions like sqlite3_malloc() delegate to sqlite3Malloc()
            // and return the result. The wrapper itself has net()=0, but the callee
            // has net()>0. This catches the pattern without project-specific whitelists.
            const retval_opcode = c.LLVMGetInstructionOpcode(retval);
            if (retval_opcode == c.LLVMCall or retval_opcode == c.LLVMInvoke) {
                const callee_val = c.LLVMGetCalledValue(retval);
                if (@intFromPtr(callee_val) != 0) {
                    const callee_ptr = @as(u64, @intFromPtr(callee_val));
                    const callee_counter = mg.getFuncCounter(callee_ptr);
                    if (callee_counter.hasHeapOps() and callee_counter.net() > 0) {
                        diag.debug("[SUPPRESSED] Callee has net heap allocations ({d} allocs, {d} frees): {s} -> {s}", .{
                            callee_counter.allocs,
                            callee_counter.frees,
                            func_name,
                            std.mem.span(c.LLVMGetValueName(callee_val)),
                        });
                        stats.heap_intentional_transfer += 1;
                        return;
                    }
                }
            }
        }

        // v0.1.9: Check if retval is a call instruction result from a known allocator.
        // This catches cases where MemoryGraph doesn't track the call (e.g., custom allocators).
        const retval_opcode = c.LLVMGetInstructionOpcode(retval);
        if (retval_opcode == c.LLVMCall or retval_opcode == c.LLVMInvoke) {
            const called_val = c.LLVMGetCalledValue(retval);
            if (@intFromPtr(called_val) != 0) {
                const callee_name_ptr = c.LLVMGetValueName(called_val);
                if (@intFromPtr(callee_name_ptr) != 0) {
                    const callee_name = std.mem.span(callee_name_ptr);
                    // Check AllocatorKB for known allocators.
                    if (getAllocatorKB()) |kb| {
                        if (kb.isAllocator(callee_name)) {
                            diag.debug("[SUPPRESSED] Return value from known allocator {s} in {s}", .{ callee_name, func_name });
                            stats.heap_intentional_transfer += 1;
                            return;
                        }
                    }
                    // Check HEAP_ALLOC_FUNCTIONS.
                    for (HEAP_ALLOC_FUNCTIONS) |alloc_fn| {
                        if (std.mem.indexOf(u8, callee_name, alloc_fn) != null) {
                            diag.debug("[SUPPRESSED] Return value from heap alloc {s} in {s}", .{ callee_name, func_name });
                            stats.heap_intentional_transfer += 1;
                            return;
                        }
                    }
                }
            }
        }

        if (pointer_map.get(retval)) |ptr_info| {
            if (ptr_info.alloc_site == .stack) {
                // v0.1.9: Skip param storage allocas — they are local copies of
                // function parameters, not dangerous stack address returns.
                if (ptr_info.is_param_storage) {
                    diag.debug("[SUPPRESSED] Param storage alloca (not a real stack escape): {s}", .{func_name});
                    stats.heap_intentional_transfer += 1;
                    // v0.1.6: Skip sret allocas — LLVM uses "alloca ptr" as a return
                    // value slot for functions returning pointers. The alloca itself is
                    // on the stack, but it only holds a pointer to heap-allocated memory.
                    // Returning the alloca address is the standard LLVM sret pattern,
                    // not a dangerous stack escape.
                } else if (isSretAlloca(retval, inst, func)) {
                    diag.debug("[SUPPRESSED] Sret alloca (return value slot, not real stack escape): {s}", .{func_name});
                    stats.heap_intentional_transfer += 1;
                } else if (isAllocaReturnSuppressed(func_name, ptr_info)) {
                    diag.debug("[SUPPRESSED] Alloca return in constructor/factory: {s}", .{func_name});
                    stats.heap_intentional_transfer += 1;
                } else {
                    try reportReturnStackAddr(ctx, func_name, ptr_info, inst, diag);
                    stats.return_stack_addr_found += 1;
                }
            } else if (ptr_info.alloc_site == .heap) {
                if (!isIntentionalOwnershipTransfer(func_name)) {
                    // P1-1: Use inter-procedural knowledge to detect acquisition functions.
                    // If this function is a known resource acquisition function (dlopen, malloc,
                    // socket, etc.), the heap return is intentional ownership transfer, not a leak.
                    if (ip_ffi.is_acquisition_function(func_name)) {
                        diag.debug("[SUPPRESSED] Heap return in acquisition function: {s} (ip_ffi detected)", .{func_name});
                        stats.heap_intentional_transfer += 1;
                    } else if (is_lifecycle_bound_return(func_name, ptr_info)) {
                        diag.debug("[MARKED] Lifecycle-bound return: {s} -> {s} (handle-dependent lifetime)", .{ func_name, ptr_info.source_desc });
                        stats.heap_intentional_transfer += 1;
                    } else {
                        try reportReturnHeapPtr(ctx, func_name, ptr_info, inst, diag);
                        stats.heap_ambiguous_found += 1;
                    }
                } else {
                    diag.debug("[SUPPRESSED] Heap return in factory function: {s} (intentional ownership transfer)", .{func_name});
                    stats.heap_intentional_transfer += 1;
                }
            }
        }
    }

    fn is_lifecycle_bound_return(func_name: []const u8, ptr_info: PtrInfo) bool {
        if (ptr_info.resource_type == .none) return false;
        if (ptr_info.resource_type == .dlopen_handle) {
            return std.mem.indexOf(u8, func_name, "dlsym") != null;
        }
        if (ptr_info.resource_type == .mmap_region) {
            return std.mem.indexOf(u8, func_name, "mmap") != null;
        }
        if (ptr_info.resource_type == .file_handle) {
            return std.mem.indexOf(u8, func_name, "fopen") != null;
        }
        if (ptr_info.resource_type == .socket_fd) {
            return std.mem.indexOf(u8, func_name, "socket") != null;
        }
        if (ptr_info.resource_type == .jni_ref) {
            return std.mem.indexOf(u8, func_name, "NewStringUTF") != null or
                std.mem.indexOf(u8, func_name, "NewByteArray") != null;
        }
        if (ptr_info.resource_type == .python_obj) {
            return std.mem.indexOf(u8, func_name, "Py_BuildValue") != null or
                std.mem.indexOf(u8, func_name, "PyTuple_New") != null;
        }
        return false;
    }

    fn isCppDestructorOrConstructor(func_name: []const u8) bool {
        if (func_name.len == 0) return false;
        if (func_name[func_name.len - 1] == 'E') {
            if (std.mem.indexOf(u8, func_name, "C1E") != null or
                std.mem.indexOf(u8, func_name, "C2E") != null or
                std.mem.indexOf(u8, func_name, "D1E") != null or
                std.mem.indexOf(u8, func_name, "D2E") != null)
            {
                return true;
            }
        }
        return false;
    }

    /// Checks if a function returning an alloca pointer should be suppressed.
    /// Many C projects use alloca as temporary workspace in constructor/factory
    /// functions (e.g., sqlite3PExpr, sqlite3SelectNew). The alloca is just an
    /// intermediate buffer — the actual return value points to heap memory that
    /// was copied from the alloca. Reporting these creates massive noise.
    /// Check if a retval is an sret-style alloca (return value slot).
    /// LLVM generates "alloca ptr" as a local slot to hold the return value.
    /// The alloca is on the stack but only holds a pointer to heap memory.
    /// Returning the alloca address is standard LLVM behavior, not a stack escape.
    ///
    /// Detection: retval is an alloca, its allocated type is ptr (not a data buffer),
    /// and the function's return type is also ptr.
    fn isSretAlloca(retval: c.LLVMValueRef, _: c.LLVMValueRef, func: c.LLVMValueRef) bool {
        // retval must be an alloca instruction
        if (c.LLVMGetInstructionOpcode(retval) != c.LLVMAlloca) return false;

        // The alloca's allocated type must be ptr (not i8, [N x i8], etc.)
        const alloca_type = c.LLVMGetAllocatedType(retval);
        if (@intFromPtr(alloca_type) == 0) return false;
        if (c.LLVMGetTypeKind(alloca_type) != c.LLVMPointerTypeKind) return false;

        // The function's return type must also be ptr.
        // Use LLVMGetElementType(LLVMTypeOf(func)) to get the function type,
        // consistent with the rest of the codebase.
        const func_ptr_type = c.LLVMTypeOf(func);
        if (@intFromPtr(func_ptr_type) == 0) return false;
        const func_type = c.LLVMGetElementType(func_ptr_type);
        if (@intFromPtr(func_type) == 0) return false;
        if (c.LLVMGetTypeKind(func_type) != c.LLVMFunctionTypeKind) return false;
        const ret_type = c.LLVMGetReturnType(func_type);
        if (@intFromPtr(ret_type) == 0) return false;
        if (c.LLVMGetTypeKind(ret_type) != c.LLVMPointerTypeKind) return false;

        return true;
    }

    /// Checks if a function returning an alloca pointer should be suppressed.
    /// Many C projects use alloca as temporary workspace in constructor/factory
    /// functions (e.g., sqlite3PExpr, sqlite3SelectNew). The alloca is just an
    /// intermediate buffer — the actual return value points to heap memory that
    /// was copied from the alloca. Reporting these creates massive noise.
    fn isAllocaReturnSuppressed(func_name: []const u8, ptr_info: PtrInfo) bool {
        // Only applies to alloca-sourced pointers.
        if (!std.mem.startsWith(u8, ptr_info.source_desc, "stack")) return false;

        // Constructor/factory naming patterns.
        const factory_suffixes = [_][]const u8{
            "New",  "Create", "Make",  "Alloc", "AllocX",
            "Init", "Open",   "Build", "From",  "Copy",
        };
        for (factory_suffixes) |suffix| {
            if (std.mem.endsWith(u8, func_name, suffix)) return true;
        }

        // Common C API patterns that use alloca internally.
        const factory_substrings = [_][]const u8{
            "Expr",     "Select",   "Token",        "SrcList",     "Name",
            "Trigger",  "CollSeq",  "Vtab",         "Module",
            // Extended factory patterns for C API recognition
                 "Malloc",
            "Alloc",    "Realloc",  "Hash",         "List",        "Table",
            "Cache",    "Pool",
            // Callback/Hook patterns that legitimately take stack addrs
                "Hook",         "Callback",    "Handler",
            "Notifier", "Observer", "busy_handler", "commit_hook", "rollback_hook",
            "wal_hook",
        };
        for (factory_substrings) |sub| {
            if (std.mem.indexOf(u8, func_name, sub) != null) {
                // Only suppress if the function also has a factory-like prefix.
                const factory_prefixes = [_][]const u8{
                    "sqlite3",  "rowSet",    "alloc", "create",
                    "vtab",     "attach",    "token",
                    // Extended prefixes for broader coverage
                    "curl_",
                    "uv_",      "json_",     "xml_",  "ldap_",
                    "avcodec_", "avformat_",
                };
                for (factory_prefixes) |prefix| {
                    if (std.mem.startsWith(u8, func_name, prefix)) return true;
                }
                // Suppress callback/hook patterns regardless of prefix
                if (std.mem.indexOf(u8, func_name, "Hook") != null or
                    std.mem.indexOf(u8, func_name, "Callback") != null or
                    std.mem.indexOf(u8, func_name, "Handler") != null or
                    std.mem.indexOf(u8, func_name, "busy_handler") != null or
                    std.mem.indexOf(u8, func_name, "_hook") != null)
                {
                    return true;
                }
            }
        }

        // Thread creation pattern - pthread_create legitimately takes stack addr
        if (std.mem.indexOf(u8, func_name, "pthread_create") != null) {
            return true;
        }

        return false;
    }

    /// Check if a stack escape should be suppressed.
    /// Callback/hook patterns legitimately receive stack pointers.
    fn isStackEscapeSuppressed(callee_name: []const u8, _: PtrInfo) bool {
        // Callback/Hook patterns that legitimately take stack pointers.
        // Use word-boundary-aware matching to avoid false positives:
        //   - my_handler should NOT match Handler
        //   - myCallback SHOULD match Callback (camelCase convention)
        // Strategy: match if pattern appears at start, end, or after '_'/'.' separator
        const callback_patterns = [_][]const u8{
            "Hook",         "Callback",    "Handler",       "Notifier", "Observer",
            "busy_handler", "commit_hook", "rollback_hook", "wal_hook", "pthread_create",
            "pthread_join",
        };
        for (callback_patterns) |pattern| {
            if (word_boundary.isWordBoundaryMatch(callee_name, pattern)) {
                return true;
            }
        }
        return false;
    }

    /// Checks if a value is a function parameter.
    fn isFuncParam(val: c.LLVMValueRef, func: c.LLVMValueRef) bool {
        const num_params = c.LLVMCountParams(func);
        var i: u32 = 0;
        while (i < num_params) : (i += 1) {
            if (c.LLVMGetParam(func, i) == val) return true;
        }
        return false;
    }

    fn isNonPointerReturnType(ret_inst: c.LLVMValueRef) bool {
        const ret_value = c.LLVMGetOperand(ret_inst, 0);
        if (ret_value == null) return false;
        const value_type = c.LLVMTypeOf(ret_value);
        if (value_type == null) return false;
        return c.LLVMGetTypeKind(value_type) != c.LLVMPointerTypeKind;
    }

    fn isIntentionalOwnershipTransfer(func_name: []const u8) bool {
        const factory_prefixes = [_][]const u8{
            "create", "Create", "CREATE",
            "new",    "New",    "NEW",
            "make",   "Make",   "MAKE",
            "alloc",  "Alloc",  "ALLOC",
            "malloc", "calloc", "realloc",
            "open",   "Open",   "init",
            "Init",   "dup",    "Dup",
            "clone",  "Clone",  "copy",
            "Copy",   "from",   "From",
            "wrap",   "Wrap",   "build",
            "Build",
        };
        for (factory_prefixes) |prefix| {
            if (std.mem.startsWith(u8, func_name, prefix)) return true;
        }
        const factory_suffixes = [_][]const u8{
            "_create", "_new",  "_make", "_alloc",
            "_new_",   "_init", "_ctor", "_construct",
            "_clone",  "_copy", "_dup",  "_from",
        };
        for (factory_suffixes) |suffix| {
            if (std.mem.endsWith(u8, func_name, suffix)) return true;
        }
        return false;
    }

    fn isResourceCloseFunction(fn_name: []const u8) ?ResourceType {
        if (std.mem.indexOf(u8, fn_name, "dlclose") != null) return .dlopen_handle;
        if (std.mem.indexOf(u8, fn_name, "munmap") != null) return .mmap_region;
        if (std.mem.indexOf(u8, fn_name, "fclose") != null) return .file_handle;
        if (isSocketClose(fn_name)) return .socket_fd;
        if (std.mem.indexOf(u8, fn_name, "DeleteGlobalRef") != null or
            std.mem.indexOf(u8, fn_name, "DeleteLocalRef") != null) return .jni_ref;
        if (std.mem.indexOf(u8, fn_name, "Py_DECREF") != null or
            std.mem.indexOf(u8, fn_name, "Py_XDECREF") != null) return .python_obj;
        return null;
    }

    fn isSameOrAlias(a: c.LLVMValueRef, b: c.LLVMValueRef) bool {
        if (@intFromPtr(a) == @intFromPtr(b)) return true;
        if (isDerivedFrom(a, b) or isDerivedFrom(b, a)) return true;
        return false;
    }

    fn isDerivedFrom(value: c.LLVMValueRef, base: c.LLVMValueRef) bool {
        if (@intFromPtr(value) == 0 or @intFromPtr(base) == 0) return false;
        const opcode = c.LLVMGetInstructionOpcode(value);
        if (opcode == c.LLVMBitCast or opcode == c.LLVMPtrToInt or
            opcode == c.LLVMIntToPtr or opcode == c.LLVMAddrSpaceCast)
        {
            const src = c.LLVMGetOperand(value, 0);
            if (@intFromPtr(src) == @intFromPtr(base)) return true;
            if (isDerivedFrom(src, base)) return true;
        }
        if (opcode == c.LLVMGetElementPtr) {
            const ptr_op = c.LLVMGetOperand(value, 0);
            if (@intFromPtr(ptr_op) == @intFromPtr(base)) return true;
            if (isDerivedFrom(ptr_op, base)) return true;
        }
        return false;
    }

    fn isSocketClose(fn_name: []const u8) bool {
        const non_socket_patterns = [_][]const u8{
            "file_",   "document", "database",  "db_",
            "window",  "dir_",     "stream",    "buf_",
            "mem_",    "str_",     "xml_",      "json_",
            "log_",    "config",   "session",   "cache",
            "mutex",   "lock",     "semaphore", "cond_",
            "thread",  "process",  "handle",    "ref_",
            "context", "scope",    "state",     "node",
        };
        for (non_socket_patterns) |np| {
            if (std.mem.indexOf(u8, fn_name, np) != null and
                std.mem.indexOf(u8, fn_name, "close") != null)
            {
                return false;
            }
        }

        const exact_matches = [_][]const u8{
            "close", "::close",
        };
        for (exact_matches) |m| {
            if (std.mem.eql(u8, fn_name, m)) return true;
        }
        const socket_patterns = [_][]const u8{
            "socket_close", "sock_close",  "fd_close",
            "::close(",     "posix_close", "shutdown",
        };
        for (socket_patterns) |p| {
            if (std.mem.indexOf(u8, fn_name, p) != null) return true;
        }
        if (std.mem.endsWith(u8, fn_name, "_close")) {
            const prefix = fn_name[0 .. fn_name.len - 6];
            const socket_prefixes = [_][]const u8{
                "sock",   "fd_",    "conn", "pipe",
                "listen", "accept",
            };
            for (socket_prefixes) |sp| {
                if (std.mem.indexOf(u8, prefix, sp) != null) return true;
            }
        }
        return false;
    }

    fn is_resource_alloc_function(fn_name: []const u8) ?ResourceType {
        if (std.mem.indexOf(u8, fn_name, "dlopen") != null) return .dlopen_handle;
        if (std.mem.indexOf(u8, fn_name, "mmap64") != null or
            std.mem.indexOf(u8, fn_name, "mmap2") != null or
            std.mem.indexOf(u8, fn_name, "mmap") != null) return .mmap_region;
        if (std.mem.indexOf(u8, fn_name, "shm_open") != null) return .mmap_region;
        if (std.mem.indexOf(u8, fn_name, "fopen") != null) return .file_handle;
        if (std.mem.indexOf(u8, fn_name, "socket") != null) return .socket_fd;
        if (std.mem.indexOf(u8, fn_name, "JNI_") != null or
            std.mem.indexOf(u8, fn_name, "Java_") != null) return .jni_ref;
        if (std.mem.startsWith(u8, fn_name, "Py")) return .python_obj;
        return null;
    }

    fn get_resource_type(fn_name: []const u8) ?[]const u8 {
        if (std.mem.indexOf(u8, fn_name, "dlopen") != null or std.mem.indexOf(u8, fn_name, "dlsym") != null) return "dlhandle";
        if (std.mem.indexOf(u8, fn_name, "mmap") != null) return "mmap";
        if (std.mem.indexOf(u8, fn_name, "fopen") != null or std.mem.indexOf(u8, fn_name, "FILE") != null) return "file";
        if (std.mem.indexOf(u8, fn_name, "socket") != null) return "socket";
        if (std.mem.indexOf(u8, fn_name, "JNI") != null) return "jni";
        if (std.mem.indexOf(u8, fn_name, "Py_") != null) return "python";
        return null;
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

// Tests are in ptr_lifetime_test.zig (imported to run tests)
const _tests = @import("ptr_lifetime_test.zig");
