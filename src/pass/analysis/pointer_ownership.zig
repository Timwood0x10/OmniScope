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

/// Error type for ownership tracking operations.
pub const OwnershipError = error{
    OutOfMemory,
    NoModule,
    NullPointer,
};

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
        var _timer = ScopedTimer.start(&profiler, "total");
        defer _timer.stop() catch {};

        if (ctx.module == null) {
            diag.warn("PointerOwnership: No module loaded, skipping", .{});
            return;
        }

        var init_timer = ScopedTimer.start(&profiler, "init");
        defer init_timer.stop() catch {};

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

        init_timer.stop() catch {};

        const mod = ctx.module.?.raw;

        const has_debug_info = checkDebugMetadataAvailable(mod);
        if (!has_debug_info) {
            diag.info("TIP: Rebuild with -g for file/line diagnostics", .{});
        }

        var func = c.LLVMGetFirstFunction(mod);

        var analysis_timer = ScopedTimer.start(&profiler, "analysis");
        defer analysis_timer.stop() catch {};

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;
            if (!isRustFFIRelevantFunction(func)) continue;
            try analyzeFunctionForOwnership(
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
            );
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

        // Third pass: detect struct-member ownership via GEP + store pattern
        {
            var func3 = c.LLVMGetFirstFunction(mod);
            while (@intFromPtr(func3) != 0) : (func3 = c.LLVMGetNextFunction(func3)) {
                if (c.LLVMIsDeclaration(func3) != 0) continue;
                detectStructMemberStores(func3, &alloc_map, &id_map);
            }
        }

        // Fourth pass: detect C++ RAII-managed allocations (smart pointers)
        {
            var raii_count: u32 = 0;
            var func4 = c.LLVMGetFirstFunction(mod);
            while (@intFromPtr(func4) != 0) : (func4 = c.LLVMGetNextFunction(func4)) {
                if (c.LLVMIsDeclaration(func4) != 0) continue;
                detectRaiiManagedAllocations(func4, &alloc_map, &id_map, &raii_count, &ctx.raii_func_set);
            }
            if (raii_count > 0) {
                diag.info("RAII: {d} allocations marked as smart-pointer-managed", .{raii_count});
            }
            if (ctx.raii_func_set.count() > 0) {
                diag.info("RAII: {d} functions identified as RAII-managed (skipped)", .{ctx.raii_func_set.count()});
            }
        }

        // Fifth pass: detect Meyers singleton initialization functions.
        // Pattern: function body contains __cxa_guard_acquire AND _Znwm/_Znam.
        // The allocated object has program lifetime — not a leak.
        {
            var func5 = c.LLVMGetFirstFunction(mod);
            while (@intFromPtr(func5) != 0) : (func5 = c.LLVMGetNextFunction(func5)) {
                if (c.LLVMIsDeclaration(func5) != 0) continue;
                detectMeyersSingletonFunctions(func5, &ctx.meyers_singleton_set);
            }
            if (ctx.meyers_singleton_set.count() > 0) {
                diag.info("Meyers: {d} functions identified as singleton init (skipped)", .{ctx.meyers_singleton_set.count()});
            }
        }

        // Sixth pass: detect reference-counted container functions (L8 filter).
        // Pattern: function body contains Ref/Unref/AddRef/Release/Retain calls
        // that manage CordRep, RefCounted, shared_ptr, or similar RC nodes.
        // Allocations in such functions are freed via refcount drop — not leaks.
        {
            var func6 = c.LLVMGetFirstFunction(mod);
            while (@intFromPtr(func6) != 0) : (func6 = c.LLVMGetNextFunction(func6)) {
                if (c.LLVMIsDeclaration(func6) != 0) continue;
                detectRefCountedContainerFunctions(func6, &ctx.rc_container_func_set);
            }
            if (ctx.rc_container_func_set.count() > 0) {
                diag.info("RC-Container: {d} functions identified as refcount-managed (skipped)", .{ctx.rc_container_func_set.count()});
            }
        }

        // Seventh pass: detect Rust FFI ownership transfer pairing (Task 9.3).
        // Scans for into_raw (ownership OUT) and from_raw (ownership IN) calls.
        // Functions with unpaired into_raw are flagged as potential Rust leaks.
        {
            var func7 = c.LLVMGetFirstFunction(mod);
            while (@intFromPtr(func7) != 0) : (func7 = c.LLVMGetNextFunction(func7)) {
                if (c.LLVMIsDeclaration(func7) != 0) continue;
                detectRustFfiPairingFunctions(func7, &ctx.rust_into_raw_set, &ctx.rust_from_raw_set);
            }
            if (ctx.rust_into_raw_set.count() > 0 or ctx.rust_from_raw_set.count() > 0) {
                diag.info("Rust-FFI: {d} into_raw funcs, {d} from_raw funcs detected", .{
                    ctx.rust_into_raw_set.count(),
                    ctx.rust_from_raw_set.count(),
                });
            }
        }

        // Eighth pass: detect as_ptr borrow escape (Task 9.3c).
        // Identifies when local String/Vec's .as_ptr() result is passed
        // to an extern "C" function — the pointer may dangle after drop.
        {
            var func8 = c.LLVMGetFirstFunction(mod);
            while (@intFromPtr(func8) != 0) : (func8 = c.LLVMGetNextFunction(func8)) {
                if (c.LLVMIsDeclaration(func8) != 0) continue;
                detectAsPtrBorrowEscape(ctx, func8, diag);
            }
        }

        analysis_timer.stop() catch {};

        var detect_timer = ScopedTimer.start(&profiler, "detect");
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
        diag.info("PointerOwnership: Memory pool stats - allocated: {}, reused: {}, in_use: {}", .{
            pool_stats.allocated,
            pool_stats.reused,
            pool_stats.in_use,
        });
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

        try null_check_recognizer.recognizeInFunction(func, id_map);

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

    /// P0-C: Rust-Focused FFI Filtering.
    /// For Rust-mangled functions (_R* or $*), only analyze if the function
    /// touches an FFI boundary (calls extern/"C" function).
    /// This eliminates ~95% of false positives from Rust drop glue,
    /// closure cleanup, and iterator patterns.
    fn isRustFFIRelevantFunction(func: c.LLVMValueRef) bool {
        const func_name_raw = c.LLVMGetValueName(func);
        if (func_name_raw == null) return true;
        const func_name = std.mem.span(func_name_raw);

        const is_rust = (std.mem.indexOf(u8, func_name, "_R") != null or
            std.mem.indexOf(u8, func_name, "$") != null);
        if (!is_rust) return true;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (c.LLVMGetInstructionOpcode(inst) == c.LLVMCall) {
                    const num_ops = c.LLVMGetNumOperands(inst);
                    if (num_ops == 0) continue;
                    const callee_val = c.LLVMGetOperand(inst, @intCast(num_ops - 1));
                    if (@intFromPtr(callee_val) == 0) continue;
                    if (c.LLVMIsDeclaration(callee_val) != 0) return true;
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
            visited.put(current, {}) catch return;

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
        _ = has_debug_info;
        const opcode = c.LLVMGetInstructionOpcode(inst);
        const inst_id = try id_map.getOrPutId(@intFromPtr(inst));

        try buildFlowGraph(allocator, inst, opcode, flow_graph, id_map);

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
                .bb_id = if (@intFromPtr(parent_bb) != 0) @intFromPtr(parent_bb) else 0,
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
                try id_map.getOrPutId(@intFromPtr(ptr_arg))
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
                .bb_id = if (@intFromPtr(parent_bb) != 0) @intFromPtr(parent_bb) else 0,
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
        const inst_id = try id_map.getOrPutId(@intFromPtr(inst));

        switch (opcode) {
            c.LLVMStore => {
                // Store: value -> pointer
                const value = c.LLVMGetOperand(inst, 0);
                const ptr = c.LLVMGetOperand(inst, 1);
                if (@intFromPtr(value) != 0 and @intFromPtr(ptr) != 0) {
                    const value_id = try id_map.getOrPutId(@intFromPtr(value));
                    const ptr_id = try id_map.getOrPutId(@intFromPtr(ptr));
                    try addFlowEdge(allocator, value_id, ptr_id, flow_graph);
                }
            },
            c.LLVMLoad => {
                // Load: pointer -> result
                const ptr = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(ptr) != 0) {
                    const ptr_id = try id_map.getOrPutId(@intFromPtr(ptr));
                    try addFlowEdge(allocator, ptr_id, inst_id, flow_graph);
                }
            },
            c.LLVMBitCast, c.LLVMPtrToInt, c.LLVMIntToPtr => {
                // Cast: operand -> result
                const operand = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(operand) != 0) {
                    const operand_id = try id_map.getOrPutId(@intFromPtr(operand));
                    try addFlowEdge(allocator, operand_id, inst_id, flow_graph);
                }
            },
            c.LLVMCall => {
                // Call: arguments flow to result (for allocation functions)
                // and arguments flow to function (for free functions)
                const num_ops = c.LLVMGetNumOperands(inst);
                var i: u32 = 0;
                while (i < num_ops) : (i += 1) {
                    const op = c.LLVMGetOperand(inst, i);
                    if (@intFromPtr(op) != 0) {
                        const op_id = try id_map.getOrPutId(@intFromPtr(op));
                        // Arguments flow to call result
                        try addFlowEdge(allocator, op_id, inst_id, flow_graph);
                    }
                }
            },
            c.LLVMPHI => {
                // PHI: incoming values -> result
                const num_incoming = c.LLVMCountIncoming(inst);
                var i: u32 = 0;
                while (i < num_incoming) : (i += 1) {
                    const incoming = c.LLVMGetIncomingValue(inst, i);
                    if (@intFromPtr(incoming) != 0) {
                        const incoming_id = try id_map.getOrPutId(@intFromPtr(incoming));
                        try addFlowEdge(allocator, incoming_id, inst_id, flow_graph);
                    }
                }
            },
            c.LLVMSelect => {
                // Select: true_val/false_val -> result
                const true_val = c.LLVMGetOperand(inst, 1);
                const false_val = c.LLVMGetOperand(inst, 2);
                if (@intFromPtr(true_val) != 0) {
                    const true_id = try id_map.getOrPutId(@intFromPtr(true_val));
                    try addFlowEdge(allocator, true_id, inst_id, flow_graph);
                }
                if (@intFromPtr(false_val) != 0) {
                    const false_id = try id_map.getOrPutId(@intFromPtr(false_val));
                    try addFlowEdge(allocator, false_id, inst_id, flow_graph);
                }
            },
            c.LLVMGetElementPtr => {
                // GEP: base pointer -> result (field/element access)
                // The first operand is the base pointer, subsequent are indices
                const base_ptr = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(base_ptr) != 0) {
                    const base_id = try id_map.getOrPutId(@intFromPtr(base_ptr));
                    try addFlowEdge(allocator, base_id, inst_id, flow_graph);
                }
            },
            c.LLVMExtractValue => {
                // ExtractValue: aggregate -> result (extract field)
                const aggregate = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(aggregate) != 0) {
                    const agg_id = try id_map.getOrPutId(@intFromPtr(aggregate));
                    try addFlowEdge(allocator, agg_id, inst_id, flow_graph);
                }
            },
            c.LLVMInsertValue => {
                // InsertValue: aggregate + value -> result
                const aggregate = c.LLVMGetOperand(inst, 0);
                const value = c.LLVMGetOperand(inst, 1);
                if (@intFromPtr(aggregate) != 0) {
                    const agg_id = try id_map.getOrPutId(@intFromPtr(aggregate));
                    try addFlowEdge(allocator, agg_id, inst_id, flow_graph);
                }
                if (@intFromPtr(value) != 0) {
                    const val_id = try id_map.getOrPutId(@intFromPtr(value));
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
        return cpp_fp.identifyLanguage(func);
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
    fn isLikelyIntentionalPattern(func_name: []const u8) bool {
        return cpp_fp.isLikelyIntentionalPattern(func_name);
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
    ) bool {
        _ = from_ptr;
        _ = free_map;
        _ = flow_graph;
        return false;
    }
    fn canReachFree(
        from: u32,
        flow: std.AutoHashMap(u32, void),
        free_map: *std.AutoHashMap(u32, *FreeSite),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        visited: *std.AutoHashMap(u32, void),
    ) bool {
        _ = from;
        _ = flow;
        _ = free_map;
        _ = flow_graph;
        _ = visited;
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
        return cpp_fp.hasUseAfterFree(freed_ptr, flow, flow_graph, visited);
    }
    fn isMemoryAccess(value_id: u32) bool {
        _ = value_id;
        return false;
    }
    fn getInstName(value_id: u32) []const u8 {
        _ = value_id;
        return "";
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
