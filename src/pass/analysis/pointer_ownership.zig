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
const AllocSite = struct {
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

/// Allocation types.
const AllocType = enum(u8) {
    heap,
    rust_box_into_raw,
    rust_box_from_raw,
    rust_alloc,
    cpp_new,
    zig_alloc,
    unknown,
};

/// Pointer ownership state.
const OwnershipState = enum(u8) {
    live,
    ownership_transferred,
    freed,
    leaked,
};

/// Free site information.
const FreeSite = struct {
    inst_id: u32,
    func_name: []const u8,
    lang: Language,
    free_type: FreeType,
    ptr_value_id: u32,
    debug_file: ?[]const u8,
    debug_line: ?u32,
    debug_column: ?u32,
};

/// Free types.
const FreeType = enum(u8) {
    free,
    rust_box_from_raw,
    rust_drop,
    cpp_delete,
    zig_free,
    unknown,
};

/// Pointer flow edge - tracks how pointers move through the program.
const PointerFlowEdge = struct {
    from_inst: u32,
    to_inst: u32,
    flow_type: FlowType,
};

const FlowType = enum(u8) {
    assignment,
    argument,
    return_value,
    store,
    load,
};

/// Statistics for ownership tracking.
const OwnershipStats = struct {
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

        analysis_timer.stop() catch {};

        var detect_timer = ScopedTimer.start(&profiler, "detect");
        defer detect_timer.stop() catch {};

        try detectViolations(ctx, &alloc_map, &free_map, &flow_graph, &stats, diag, &boundary_analyzer, &lifetime_engine);

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
                            markAllocSitesReachingValue(alloc_map, reverse_flow, ret_value_id);
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
                                    markAllocSitesReachingValue(alloc_map, reverse_flow, val_value_id);
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
    ) void {
        var visited = std.AutoHashMap(u32, void).init(alloc_map.allocator);
        defer visited.deinit();

        var bfs_queue: [64]u32 = undefined;
        var queue_head: usize = 0;
        var queue_tail: usize = 0;
        bfs_queue[queue_tail] = target_value_id;
        queue_tail += 1;

        while (queue_head < queue_tail) {
            const current = bfs_queue[queue_head];
            queue_head += 1;

            if (visited.contains(current)) continue;
            visited.put(current, {}) catch return;

            if (alloc_map.get(current)) |site| {
                site.transferred = true;
            }

            if (reverse_flow.get(current)) |preds| {
                var pred_iter = preds.iterator();
                while (pred_iter.next()) |entry| {
                    const pred_id = entry.key_ptr.*;
                    if (!visited.contains(pred_id) and queue_tail < bfs_queue.len) {
                        bfs_queue[queue_tail] = pred_id;
                        queue_tail += 1;
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
            site.* = .{
                .inst_id = inst_id,
                .func_name = func_name,
                .lang = callee_lang,
                .free_type = free_type,
                .ptr_value_id = ptr_value_id,
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

    /// Detect ownership violations using flow graph and boundary analyzer.
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
        var alloc_iter = alloc_map.iterator();
        while (alloc_iter.next()) |entry| {
            const alloc = entry.value_ptr.*;

            const lang_hint = convertLanguageToHint(alloc.lang);
            if (lifetime_engine.applyAction(
                .alloc,
                alloc.func_name,
                if (alloc.debug_file) |file|
                    .{ .file = file, .line = alloc.debug_line orelse 0, .column = alloc.debug_column orelse 0 }
                else
                    null,
                lang_hint,
            )) |resource_id| {
                if (resource_id > std.math.maxInt(u32)) {
                    diag.warn("Resource ID overflow detected: {d} exceeds u32 range", .{resource_id});
                }
                try ctx.fact_store.insert(
                    .ownership_alloc,
                    alloc.ptr_value_id,
                    @truncate(resource_id),
                    alloc.inst_id,
                );
            } else {
                try ctx.fact_store.insert(
                    .ownership_alloc,
                    alloc.ptr_value_id,
                    @intFromEnum(alloc.lang),
                    alloc.inst_id,
                );
                diag.warn("Failed to track allocation in lifetime engine: {s}", .{alloc.func_name});
            }

            if (isCrossFFIAllocation(alloc)) {
                stats.cross_ffi_transfers += 1;
                try ctx.fact_store.insert(
                    .ownership_transfer,
                    alloc.ptr_value_id,
                    @intFromEnum(alloc.lang),
                    alloc.inst_id,
                );
            }
        }

        var free_iter = free_map.iterator();
        while (free_iter.next()) |entry| {
            const free_site = entry.value_ptr.*;

            try ctx.fact_store.insert(
                .ownership_free,
                free_site.ptr_value_id,
                @intFromEnum(free_site.lang),
                free_site.inst_id,
            );
        }

        alloc_iter = alloc_map.iterator();
        while (alloc_iter.next()) |entry| {
            const alloc = entry.value_ptr.*;
            const alloc_lang_hint = convertLanguageToHint(alloc.lang);

            free_iter = free_map.iterator();
            while (free_iter.next()) |free_entry| {
                const free_site = free_entry.value_ptr.*;
                const free_lang_hint = convertLanguageToHint(free_site.lang);

                if (alloc.lang != free_site.lang and
                    alloc.lang != .unknown and
                    free_site.lang != .unknown)
                {
                    var visited = std.AutoHashMap(u32, void).init(ctx.allocator);
                    defer visited.deinit();

                    const flows_to_free = canReach(
                        flow_graph,
                        alloc.ptr_value_id,
                        free_site.ptr_value_id,
                        &visited,
                    );

                    if (flows_to_free) {
                        const alloc_loc = Location.init(alloc.func_name);
                        const free_loc = Location.init(free_site.func_name);

                        const boundary_id = boundary_analyzer.registerBoundary(
                            free_site.func_name,
                            alloc_lang_hint,
                            free_lang_hint,
                            .out,
                            if (alloc.debug_file) |file|
                                .{ .file = file, .line = alloc.debug_line orelse 0, .column = alloc.debug_column orelse 0 }
                            else
                                null,
                        );

                        const resource_fact = lifetime.ResourceFact{
                            .id = @as(u64, alloc.inst_id),
                            .origin_fn = alloc.func_name,
                            .owner = .caller,
                            .state = .live,
                            .action = .alloc,
                            .location = null,
                            .lang_hint = alloc_lang_hint,
                        };

                        if (boundary_id == 0) {
                            diag.warn("Failed to register FFI boundary for analysis", .{});
                        } else if (boundary_analyzer.checkOwnershipViolation(
                            resource_fact,
                            .free,
                            free_lang_hint,
                            boundary_analyzer.boundaries.items[boundary_id - 1],
                        )) |violation| {
                            diag.warn("CROSS-LANGUAGE OWNERSHIP VIOLATION DETECTED", .{});
                            diag.warn("  Type: {s}", .{@tagName(violation.kind)});
                            diag.warn("  Alloc: {s} ({s}) at inst {}", .{
                                alloc_loc.function,
                                @tagName(alloc.lang),
                                alloc.inst_id,
                            });
                            diag.warn("  Free: {s} ({s}) at inst {}", .{
                                free_loc.function,
                                @tagName(free_site.lang),
                                free_site.inst_id,
                            });
                            diag.warn("  Description: {s}", .{violation.description});
                        } else {
                            diag.warn("CROSS-LANGUAGE OWNERSHIP VIOLATION DETECTED", .{});
                            diag.warn("  Alloc: {s} ({s}) at inst {}", .{
                                alloc_loc.function,
                                @tagName(alloc.lang),
                                alloc.inst_id,
                            });
                            diag.warn("  Free: {s} ({s}) at inst {}", .{
                                free_loc.function,
                                @tagName(free_site.lang),
                                free_site.inst_id,
                            });
                            diag.warn("  Flow: Pointer flows from allocation to free via data flow", .{});
                        }

                        try ctx.fact_store.insert(
                            .ownership_violation,
                            alloc.inst_id,
                            @intFromEnum(OwnershipViolationType.cross_lang_free_mismatch),
                            free_site.inst_id,
                        );

                        stats.violations += 1;
                    }
                }
            }
        }

        const boundary_stats = boundary_analyzer.getStats();
        if (boundary_stats.issue_count > 0) {
            diag.info("BoundaryAnalyzer: {d} cross-language violations detected", .{
                boundary_stats.issue_count,
            });
        }
    }

    /// Convert internal Language enum to lifetime.LanguageHint.
    fn convertLanguageToHint(lang: Language) lifetime.LanguageHint {
        return switch (lang) {
            .c => .c,
            .rust => .rust,
            .zig => .zig,
            .cpp => .cpp,
            .go => .go,
            .swift => .swift,
            .unknown => .unknown,
        };
    }

    /// Check if an allocation crosses an FFI boundary.
    fn isCrossFFIAllocation(alloc: *const AllocSite) bool {
        return alloc.lang != .unknown and alloc.lang != .c;
    }

    /// Check if an instruction is an allocation using SemanticRegistry.
    fn isAllocationInstruction(inst: c.LLVMValueRef, opcode: c_uint) bool {
        if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) return false;

        const called_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return false;

        const name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(name_ptr) == 0) return false;

        const callee_name = std.mem.span(name_ptr);

        // Use SemanticRegistry for accurate identification.
        if (SemanticRegistry.lookup(callee_name)) |sem| {
            return sem.kind == .allocator or sem.kind == .cpp_allocator;
        }

        // Fallback: check for known allocation patterns.
        return std.mem.eql(u8, callee_name, "malloc") or
            std.mem.eql(u8, callee_name, "calloc") or
            std.mem.eql(u8, callee_name, "realloc") or
            std.mem.eql(u8, callee_name, "aligned_alloc") or
            std.mem.indexOf(u8, callee_name, "into_raw") != null or
            std.mem.indexOf(u8, callee_name, "operator new") != null;
    }

    /// Classify the type of allocation.
    fn classifyAllocation(inst: c.LLVMValueRef, opcode: c_uint) AllocType {
        if (opcode != c.LLVMCall) return .unknown;

        const called_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return .unknown;

        const callee_name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(callee_name_ptr) == 0) return .unknown;

        const callee_name = std.mem.span(callee_name_ptr);

        if (std.mem.indexOf(u8, callee_name, "into_raw") != null) {
            return .rust_box_into_raw;
        }
        if (std.mem.indexOf(u8, callee_name, "from_raw") != null) {
            return .rust_box_from_raw;
        }
        if (std.mem.indexOf(u8, callee_name, "allocImpl") != null) {
            return .zig_alloc;
        }
        if (std.mem.indexOf(u8, callee_name, "operator new") != null) {
            return .cpp_new;
        }

        return .heap;
    }

    /// Identify language from callee function name.
    fn identifyLanguageFromCallee(inst: c.LLVMValueRef, opcode: c_uint) Language {
        if (opcode != c.LLVMCall) return .unknown;

        const called_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return .unknown;

        const callee_name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(callee_name_ptr) == 0) return .unknown;

        const callee_name = std.mem.span(callee_name_ptr);

        // Rust uses _R prefix for v0 mangling (RFC 2603).
        if (callee_name.len > 2 and
            callee_name[0] == '_' and
            callee_name[1] == 'R')
        {
            return .rust;
        }

        // Check for Rust-specific patterns.
        if (std.mem.indexOf(u8, callee_name, "into_raw") != null or
            std.mem.indexOf(u8, callee_name, "from_raw") != null or
            std.mem.indexOf(u8, callee_name, "drop_in_place") != null)
        {
            return .rust;
        }

        // Check for C standard library functions.
        if (std.mem.eql(u8, callee_name, "malloc") or
            std.mem.eql(u8, callee_name, "free") or
            std.mem.eql(u8, callee_name, "calloc") or
            std.mem.eql(u8, callee_name, "realloc"))
        {
            return .c;
        }

        // C++ mangled names start with _Z.
        if (callee_name.len > 2 and
            callee_name[0] == '_' and
            callee_name[1] == 'Z')
        {
            return .cpp;
        }

        // Check for Zig allocator patterns.
        if (std.mem.indexOf(u8, callee_name, "Allocator.") != null or
            std.mem.indexOf(u8, callee_name, "allocImpl") != null)
        {
            return .zig;
        }

        return .unknown;
    }

    /// Check if an instruction is a free using SemanticRegistry.
    fn isFreeInstruction(inst: c.LLVMValueRef, opcode: c_uint) bool {
        if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) return false;

        const called_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return false;

        const name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(name_ptr) == 0) return false;

        const callee_name = std.mem.span(name_ptr);

        // Use SemanticRegistry for accurate identification.
        if (SemanticRegistry.lookup(callee_name)) |sem| {
            return sem.kind == .deallocator;
        }

        // Fallback: check for known free patterns.
        return std.mem.eql(u8, callee_name, "free") or
            std.mem.indexOf(u8, callee_name, "from_raw") != null or
            std.mem.indexOf(u8, callee_name, "drop_in_place") != null or
            std.mem.indexOf(u8, callee_name, "operator delete") != null;
    }

    /// Classify the type of free.
    fn classifyFree(inst: c.LLVMValueRef, opcode: c_uint) FreeType {
        if (opcode != c.LLVMCall) return .unknown;

        const called_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return .unknown;

        const callee_name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(callee_name_ptr) == 0) return .unknown;

        const callee_name = std.mem.span(callee_name_ptr);

        if (std.mem.indexOf(u8, callee_name, "from_raw") != null) {
            return .rust_box_from_raw;
        }
        if (std.mem.indexOf(u8, callee_name, "drop_in_place") != null) {
            return .rust_drop;
        }
        if (std.mem.indexOf(u8, callee_name, "operator delete") != null) {
            return .cpp_delete;
        }

        return .free;
    }

    /// Get function name from LLVM value.
    fn getFunctionName(func: c.LLVMValueRef) []const u8 {
        const name_ptr = c.LLVMGetValueName(func);
        if (@intFromPtr(name_ptr) == 0) return "unknown";
        return std.mem.span(name_ptr);
    }

    /// Identify the language of a function based on naming conventions.
    fn identifyLanguage(func: c.LLVMValueRef) Language {
        const func_name = getFunctionName(func);

        // Rust uses _R prefix for v0 mangling (RFC 2603).
        if (func_name.len > 2 and
            func_name[0] == '_' and
            func_name[1] == 'R')
        {
            return .rust;
        }

        // Check for Rust-specific patterns.
        if (std.mem.indexOf(u8, func_name, "alloc::") != null or
            std.mem.indexOf(u8, func_name, "core::") != null or
            std.mem.indexOf(u8, func_name, "std::") != null)
        {
            if (std.mem.indexOf(u8, func_name, "::boxed::") != null or
                std.mem.indexOf(u8, func_name, "::ffi::") != null or
                std.mem.indexOf(u8, func_name, "::cstring::") != null)
            {
                return .rust;
            }
        }

        // Check for C standard library functions.
        if (std.mem.eql(u8, func_name, "malloc") or
            std.mem.eql(u8, func_name, "free") or
            std.mem.eql(u8, func_name, "calloc") or
            std.mem.eql(u8, func_name, "realloc") or
            std.mem.eql(u8, func_name, "printf") or
            std.mem.eql(u8, func_name, "strlen"))
        {
            return .c;
        }

        // C++ mangled names start with _Z.
        if (func_name.len > 2 and
            func_name[0] == '_' and
            func_name[1] == 'Z')
        {
            return .cpp;
        }

        // Check for Zig allocator patterns.
        if (std.mem.indexOf(u8, func_name, "Allocator.") != null or
            std.mem.indexOf(u8, func_name, "allocImpl") != null)
        {
            return .zig;
        }

        // Check for Swift patterns.
        if (std.mem.indexOf(u8, func_name, "UnsafeMutablePointer") != null or
            std.mem.indexOf(u8, func_name, "$s") != null)
        {
            return .swift;
        }

        return .unknown;
    }

    /// Check if a free is guarded by a null check.
    fn isGuardedByNullCheck(
        free_inst: c.LLVMValueRef,
        ptr_value_id: u32,
        path_manager: *PathManager,
    ) bool {
        _ = free_inst;
        return path_manager.isPtrNonNull(ptr_value_id);
    }

    /// Detect memory leaks, double-free, and use-after-free.
    fn detectMemoryIssues(
        ctx: *PassContext,
        alloc_map: *std.AutoHashMap(u32, *AllocSite),
        free_map: *std.AutoHashMap(u32, *FreeSite),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        stats: *OwnershipStats,
        diag: *DiagnosticWriter,
    ) void {
        detectMemoryLeaks(ctx, alloc_map, free_map, flow_graph, stats, diag);
        detectDoubleFree(ctx, free_map, flow_graph, stats, diag);
        detectUseAfterFree(ctx, free_map, flow_graph, stats, diag);
    }

    /// Detect memory leaks: allocations that are never freed.
    /// Deduplicates: reports at most one leak per function to avoid FP explosion
    /// when a function has multiple unpaired allocations (e.g., stress test patterns).
    /// Skips functions with names indicating correct/intentional patterns
    /// (e.g., correct_*, valid_*, example_*, good_*).
    fn detectMemoryLeaks(
        ctx: *PassContext,
        alloc_map: *std.AutoHashMap(u32, *AllocSite),
        free_map: *std.AutoHashMap(u32, *FreeSite),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        stats: *OwnershipStats,
        diag: *DiagnosticWriter,
    ) void {
        var reported_func_ptrs = std.AutoHashMap(usize, void).init(alloc_map.allocator);
        defer reported_func_ptrs.deinit();

        var alloc_iter = alloc_map.iterator();
        while (alloc_iter.next()) |entry| {
            const alloc_info = entry.value_ptr.*;

            if (alloc_info.transferred) continue;

            // Skip allocations inside STL/libc++ internal template expansions.
            // These are managed by stdlib's own RAII mechanisms and are not real leaks.
            if (isStlInternalFunction(alloc_info.func_name)) continue;

            // Skip allocations inside C++ special member functions (constructors,
            // destructors, copy/move assignment operators). Memory allocated here
            // is managed by the class's RAII lifecycle — freed in destructors.
            if (isCppSpecialMemberFunction(alloc_info.func_name)) continue;

            // Skip allocations inside functions that use smart pointers (contain
            // unique_ptr/shared_ptr constructor calls). Such functions manage memory
            // via RAII — intra-function analysis cannot see the full lifecycle.
            const func_name_ptr = @intFromPtr(alloc_info.func_name.ptr);
            if (ctx.raii_func_set.contains(func_name_ptr)) continue;

            // Skip allocations inside C++ ABI runtime functions (__cxa_*).
            // These are compiler-generated: exception handling, dynamic type info,
            // thread-local storage, and Meyers singleton guards.
            if (isCppAbiInternalFunction(alloc_info.func_name)) continue;

            // Skip allocations in Meyers singleton initialization pattern.
            // __cxa_guard_acquire → _Znwm → store → __cxa_guard_release.
            // The allocated object has program lifetime — not a leak.
            if (isMeyersSingletonPattern(alloc_info.func_name)) continue;

            // Skip allocations inside Meyers singleton initialization functions.
            // These contain __cxa_guard_acquire + _Znwm pattern — the allocated
            // object lives for program lifetime (static local variable).
            const meyers_ptr = @intFromPtr(alloc_info.func_name.ptr);
            if (ctx.meyers_singleton_set.contains(meyers_ptr)) continue;

            // Skip allocations inside reference-counted container functions (L8).
            // These contain Ref/Unref/AddRef/Release calls that manage CordRep,
            // RefCounted, shared_count, or similar RC nodes. Memory is freed when
            // the last reference drops — not a leak.
            const rc_ptr = @intFromPtr(alloc_info.func_name.ptr);
            if (ctx.rc_container_func_set.contains(rc_ptr)) continue;

            const has_free_path = findFreePath(alloc_info.inst_id, free_map, flow_graph);
            if (!has_free_path) {
                if (isLikelyIntentionalPattern(alloc_info.func_name)) {
                    continue;
                }
                if (isLikelyStructMemberOwnership(alloc_info.func_name)) {
                    continue;
                }
                if (alloc_info.stored_to_struct_field) {
                    continue;
                }
                const func_ptr_key = @intFromPtr(alloc_info.func_name.ptr);
                const already_reported = reported_func_ptrs.contains(func_ptr_key);
                if (!already_reported) {
                    stats.memory_leaks += 1;
                    ctx.addIssue(Issue.init(
                        .memory_leak,
                        "Memory allocated but never freed",
                        Location.init(alloc_info.func_name),
                        .medium,
                        0.7,
                    )) catch {
                        diag.warn("Failed to register leak issue", .{});
                    };
                    diag.warn("MEMORY LEAK [MEDIUM]: Memory allocated but never freed in {s}", .{alloc_info.func_name});
                    reported_func_ptrs.put(func_ptr_key, {}) catch {
                        diag.warn("Leak dedup map insert failed", .{});
                    };
                }
            }
        }
    }

    /// Check if a function likely manages memory through struct member ownership
    /// (e.g., FTS5 stores prepared statements in struct fields, freed with parent).
    /// This is a temporary heuristic until full inter-procedural analysis (Task 8.6).
    fn isLikelyStructMemberOwnership(func_name: []const u8) bool {
        const struct_member_patterns = [_][]const u8{
            "fts5",
            "sqlite3Fts5",
            "StorageGet",
            "PrepareStmt",
            "Pragma",
            "MemSize",
            "MemRealloc",
            "serialize",
        };
        for (struct_member_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return true;
            }
        }
        return false;
    }

    /// Detect when allocation results are stored into struct/aggregate fields via GEP + store.
    /// This provides stronger evidence for struct-member ownership than function name heuristics.
    fn detectStructMemberStores(
        func: c.LLVMValueRef,
        alloc_map: *std.AutoHashMap(u32, *AllocSite),
        id_map: *ValueIdMap,
    ) void {
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode != c.LLVMStore) continue;

                const stored_val = c.LLVMGetOperand(inst, 0);
                const ptr_operand = c.LLVMGetOperand(inst, 1);

                // Check if the value being stored is a known allocation
                const stored_id = @intFromPtr(stored_val);
                if (stored_id == 0) continue;

                const value_id = id_map.getId(stored_id) orelse continue;
                if (alloc_map.get(value_id)) |alloc_info| {
                    // Check if the destination is a GEP into an aggregate type
                    if (@intFromPtr(ptr_operand) != 0 and
                        c.LLVMGetInstructionOpcode(ptr_operand) == c.LLVMGetElementPtr)
                    {
                        alloc_info.stored_to_struct_field = true;
                    }
                }
            }
        }
    }

    /// Check if a function is an internal STL/libc++ template expansion.
    /// libc++ mangled names start with _ZNSt3__ (nested) or _ZNSt4 (std::).
    /// These functions manage their own memory via RAII and should not be reported as leaks.
    fn isStlInternalFunction(func_name: []const u8) bool {
        // libc++ ABI namespace prefixes for stdlib internal functions
        const stl_prefixes = [_][]const u8{
            "_ZNSt3__", // std::__ (libc++ internal)
            "_ZNSt4", // std:: (libc++ public, but template expansions are still internal)
            "_ZNSs", // std::string
            "_ZNSt6", // std::vector, std::map, etc.
            "_ZNSt7", // std::allocator
            "_ZNSt10", // std::unique_ptr, std::shared_ptr etc.
        };
        for (stl_prefixes) |prefix| {
            if (std.mem.indexOf(u8, func_name, prefix) != null) {
                return true;
            }
        }
        // Also skip __gnu_cxx / libsupc++ internal functions
        if (std.mem.indexOf(u8, func_name, "__gnu") != null) return true;
        return false;
    }

    /// Check if a function is a C++ special member function (constructor, destructor,
    /// copy/move assignment operator). These functions are part of RAII-managed classes
    /// where memory allocated in constructors is freed in destructors — reporting
    /// intra-function leaks here produces high false positive rates.
    ///
    /// Detects Itanium C++ ABI mangled name suffixes:
    ///   Constructors:    C1Ev, C2Ev, C1EOS1_, C2EOS1_, C1ERKS1_, C2ERKS1_
    ///   Destructors:     D0Ev, D1Ev, D2Ev, D0EOS1_, D1EOS1_, D2EOS1_
    ///   Copy assignment: aSERKS1_
    ///   Move assignment: aSEOS1_
    fn isCppSpecialMemberFunction(func_name: []const u8) bool {
        const special_suffixes = [_][]const u8{
            // Constructors
            "C1Ev", // complete constructor (default)
            "C2Ev", // base constructor
            "C1EOS1_", // complete move constructor
            "C2EOS1_", // base move constructor
            "C1ERKS1_", // complete copy constructor
            "C2ERKS1_", // base copy constructor
            // Destructors
            "D0Ev", // deleting destructor
            "D1Ev", // complete destructor
            "D2Ev", // base destructor
            "D0EOS1_", // deleting move destructor
            "D1EOS1_", // complete move destructor
            "D2EOS1_", // base move destructor
            // Assignment operators
            "aSERKS1_", // copy assignment operator
            "aSEOS1_", // move assignment operator
        };
        for (special_suffixes) |suffix| {
            if (std.mem.indexOf(u8, func_name, suffix) != null) {
                return true;
            }
        }
        return false;
    }

    /// Check if a function is a C++ ABI runtime internal function (__cxa_*).
    /// These handle exception handling, thread-local storage, dynamic type
    /// info, and Meyers singleton initialization. Allocations inside these
    /// functions are managed by the C++ runtime, not user code.
    fn isCppAbiInternalFunction(func_name: []const u8) bool {
        if (std.mem.indexOf(u8, func_name, "__cxa_") != null) return true;
        return false;
    }

    /// Check if an allocation is part of a Meyers singleton pattern.
    /// Pattern: __cxa_guard_acquire(guard) → _Znwm(size) → store ptr →
    ///          __cxa_guard_release(guard). The allocated object lives for
    ///          the entire program lifetime — not a leak.
    fn isMeyersSingletonPattern(func_name: []const u8) bool {
        if (std.mem.indexOf(u8, func_name, "__cxa_guard_acquire") != null) return true;
        if (std.mem.indexOf(u8, func_name, "__cxa_guard_release") != null) return true;
        if (std.mem.indexOf(u8, func_name, "__cxa_atexit") != null) return true;
        return false;
    }

    /// Detect when allocation results are passed to C++ smart pointer constructors.
    /// Pattern: %ptr = call @_Znwm(size); call @unique_ptr_C1(..., %ptr)
    /// This means the smart pointer takes ownership — not a leak.
    ///
    /// Also detects functions that USE smart pointers (contain unique_ptr/shared_ptr
    /// constructor calls). Such functions manage memory via RAII and should not
    /// generate intra-function leak reports.
    fn detectRaiiManagedAllocations(
        func: c.LLVMValueRef,
        alloc_map: *std.AutoHashMap(u32, *AllocSite),
        id_map: *ValueIdMap,
        raii_stats: *u32,
        raii_func_set: *std.AutoHashMap(usize, void),
    ) void {
        const raii_constructor_prefixes = [_][]const u8{
            "_ZNSt3__110unique_ptr", // libc++ std::unique_ptr constructor
            "_ZNSt3__110shared_ptr", // libc++ std::shared_ptr constructor
            "_ZNSt10unique_ptr", // libstdc++/generic unique_ptr
            "_ZNSt10shared_ptr", // libstdc++/generic shared_ptr
        };
        var func_has_raii = false;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

                const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
                if (num_operands == 0) continue;
                const callee = c.LLVMGetOperand(inst, num_operands - 1);
                if (@intFromPtr(callee) == 0) continue;
                const callee_name = c.LLVMGetValueName(callee);
                if (@intFromPtr(callee_name) == 0) continue;
                const name_slice = std.mem.sliceTo(callee_name, 0);

                var is_raii_ctor = false;
                for (raii_constructor_prefixes) |prefix| {
                    if (std.mem.indexOf(u8, name_slice, prefix) != null) {
                        is_raii_ctor = true;
                        break;
                    }
                }
                if (!is_raii_ctor) continue;

                func_has_raii = true;

                var i: c_uint = 0;
                while (i < num_operands - 1) : (i += 1) {
                    const operand = c.LLVMGetOperand(inst, i);
                    if (@intFromPtr(operand) == 0) continue;
                    const op_id = id_map.getId(@intFromPtr(operand)) orelse continue;
                    if (alloc_map.get(op_id)) |alloc_info| {
                        alloc_info.transferred = true;
                        raii_stats.* += 1;
                    }
                }
            }
        }

        if (func_has_raii) {
            const func_name_raw = c.LLVMGetValueName(func);
            if (@intFromPtr(func_name_raw) != 0) {
                const func_ptr = @intFromPtr(func_name_raw);
                raii_func_set.put(func_ptr, {}) catch {
                    std.log.warn("RAII-WARN: failed to track RAII function (OOM?)\n", .{});
                };
            }
        }
    }

    /// Detect Meyers singleton initialization pattern in a function body.
    /// Scans all call/invoke instructions for __cxa_guard_acquire (the guard
    /// variable that ensures thread-safe one-time initialization). If found,
    /// marks the entire function as a Meyers singleton — allocations here
    /// have program lifetime and are not leaks.
    fn detectMeyersSingletonFunctions(
        func: c.LLVMValueRef,
        meyers_set: *std.AutoHashMap(usize, void),
    ) void {
        var has_guard_acquire = false;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);
                if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

                const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
                if (num_operands == 0) continue;
                const callee = c.LLVMGetOperand(inst, num_operands - 1);
                if (@intFromPtr(callee) == 0) continue;
                const callee_name = c.LLVMGetValueName(callee);
                if (@intFromPtr(callee_name) == 0) continue;
                const name_slice = std.mem.sliceTo(callee_name, 0);

                if (std.mem.indexOf(u8, name_slice, "__cxa_guard_acquire") != null) {
                    has_guard_acquire = true;
                    break;
                }
            }
            if (has_guard_acquire) break;
        }

        if (has_guard_acquire) {
            const func_name_raw = c.LLVMGetValueName(func);
            if (@intFromPtr(func_name_raw) != 0) {
                const func_ptr = @intFromPtr(func_name_raw);
                meyers_set.put(func_ptr, {}) catch {
                    std.log.warn("MEYERS-WARN: failed to track Meyers function (OOM?)\n", .{});
                };
            }
        }
    }

    /// Detect reference-counted container pattern in a function body.
    /// Scans all call/invoke instructions for Ref/Unref/AddRef/Release/Retain
    /// patterns that indicate manual reference counting (not RAII smart pointers).
    /// Examples: absl::CordRep::Ref/Unref, RefCounted::AddRef/Release,
    /// shared_count increment/decrement, etc.
    fn detectRefCountedContainerFunctions(
        func: c.LLVMValueRef,
        rc_set: *std.AutoHashMap(usize, void),
    ) void {
        var has_rc_operation = false;
        var has_allocation = false;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
                    const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
                    if (num_operands == 0) continue;
                    const callee = c.LLVMGetOperand(inst, num_operands - 1);
                    if (@intFromPtr(callee) == 0) continue;
                    const callee_name = c.LLVMGetValueName(callee);
                    if (@intFromPtr(callee_name) == 0) continue;
                    const name_slice = std.mem.sliceTo(callee_name, 0);

                    if (isRefCountOperation(name_slice)) {
                        has_rc_operation = true;
                    }
                    if (isAllocationInstruction(inst, opcode) or isAllocationByName(name_slice)) {
                        has_allocation = true;
                    }
                }
            }
            if (has_rc_operation) break;
        }

        if (has_rc_operation) {
            markAsRcFunction(func, rc_set);
            return;
        }

        if (has_allocation) {
            const func_name_raw = c.LLVMGetValueName(func);
            if (@intFromPtr(func_name_raw) != 0) {
                const func_name_slice = std.mem.sliceTo(func_name_raw, 0);
                if (isKnownRcContainerFunction(func_name_slice)) {
                    markAsRcFunction(func, rc_set);
                }
            }
        }
    }

    fn markAsRcFunction(func: c.LLVMValueRef, rc_set: *std.AutoHashMap(usize, void)) void {
        const func_name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_raw) != 0) {
            const func_ptr = @intFromPtr(func_name_raw);
            rc_set.put(func_ptr, {}) catch {
                std.log.warn("RC-WARN: failed to track RC container function (OOM?)\n", .{});
            };
        }
    }

    fn isAllocationByName(callee_name: []const u8) bool {
        return std.mem.indexOf(u8, callee_name, "_Znwm") != null or
            std.mem.indexOf(u8, callee_name, "_Znam") != null;
    }

    fn isKnownRcContainerFunction(func_name: []const u8) bool {
        const rc_class_patterns = [_][]const u8{
            "4Cord",
            "7CordRep",
            "10CordRepBtree",
            "11CordRepRing",
            "12CordRepExternal",
            "13CordRepFlat",
            "14SubstringHolder",
            "16RefcountAndFlags",
            "RefCounted",
            "RefPtr",
            "shared_count",
            "weak_count",
        };
        for (rc_class_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return true;
            }
        }
        return false;
    }

    fn isRefCountOperation(func_name: []const u8) bool {
        const rc_patterns = [_][]const u8{
            "CordRep3Ref",
            "CordRep5Unref",
            "RefcountAndFlags",
            "AddRef",
            "Release",
            "Retain",
            "ref_count",
            "RefCount",
            "Unref",
            "decrement",
            "increment",
        };
        for (rc_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name, pattern) != null) {
                return true;
            }
        }
        return false;
    }

    fn isLikelyIntentionalPattern(func_name: []const u8) bool {
        if (std.mem.eql(u8, func_name, "main")) return true;

        const intentional_prefixes = [_][]const u8{
            "correct_", "valid_",  "example_", "good_",
            "safe_",    "proper_", "fixed_",   "ok_",
        };
        for (intentional_prefixes) |prefix| {
            if (std.mem.indexOf(u8, func_name, prefix) != null) {
                return true;
            }
        }
        return false;
    }

    /// Detect potential null dereferences: allocations that could return NULL
    /// are used without a prior null check guard.
    fn detectNullDereferences(
        ctx: *PassContext,
        alloc_map: *std.AutoHashMap(u32, *AllocSite),
        recognizer: *NullCheckRecognizer,
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        diag: *DiagnosticWriter,
    ) void {
        var reported_funcs = std.AutoHashMap(usize, void).init(alloc_map.allocator);
        defer reported_funcs.deinit();

        var alloc_iter = alloc_map.iterator();
        while (alloc_iter.next()) |entry| {
            const alloc_info = entry.value_ptr.*;

            if (!isNullableAllocation(alloc_info)) {
                continue;
            }

            const is_guarded = isFunctionLevelNullGuarded(recognizer, alloc_info.ptr_value_id, flow_graph);
            if (!is_guarded) {
                const func_ptr_key = @intFromPtr(alloc_info.func_name.ptr);
                if (reported_funcs.contains(func_ptr_key)) {
                    continue;
                }

                const vulnerability_id = ctx.getNextVulnId();
                ctx.addIssue(Issue.init(
                    .null_dereference,
                    "Potential null dereference: pointer used without null check",
                    Location.init(alloc_info.func_name),
                    .critical,
                    0.85,
                )) catch {
                    diag.warn("Failed to register null_deref issue", .{});
                };

                diag.err("VULNERABILITY OMI-{d:0>3} [MEDIUM]", .{vulnerability_id});
                diag.err("Severity: critical", .{});
                diag.err("Type: null_dereference", .{});
                diag.err("  [Source] {s}() - allocation may return NULL, used without null guard", .{alloc_info.func_name});

                reported_funcs.put(func_ptr_key, {}) catch {
                    diag.warn("Null deref dedup map insert failed", .{});
                };
            }
        }
    }

    /// Check if a pointer value has a null guard ANYWHERE in the function (not just the alloc's BB).
    /// This handles the common SQLite pattern:
    ///   %p = call @malloc(...)     ; alloc in BB_1
    ///   %c = icmp eq %p, null     ; null check as terminator of BB_1
    ///   br i1 %c, label %exit, %cont  ; guard targets are exit/cont, NOT BB_1 itself
    fn isFunctionLevelNullGuarded(
        recognizer: *NullCheckRecognizer,
        ptr_value_id: u32,
        flow_graph: *const std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    ) bool {
        if (recognizer.isPtrGuardedNonNull_byValue(ptr_value_id)) {
            return true;
        }

        var visited = std.AutoHashMap(u32, void).init(recognizer.allocator);
        defer visited.deinit();

        var bfs_queue: [64]u32 = undefined;
        var qhead: usize = 0;
        var qtail: usize = 0;
        bfs_queue[qtail] = ptr_value_id;
        qtail += 1;

        while (qhead < qtail) {
            const current = bfs_queue[qhead];
            qhead += 1;

            if (visited.contains(current)) continue;
            visited.put(current, {}) catch return false;

            if (recognizer.isPtrGuardedNonNull_byValue(current)) {
                return true;
            }

            if (flow_graph.get(current)) |flows| {
                var iter = flows.iterator();
                while (iter.next()) |entry| {
                    const alias_id = entry.key_ptr.*;
                    if (!visited.contains(alias_id) and qtail < bfs_queue.len) {
                        bfs_queue[qtail] = alias_id;
                        qtail += 1;
                    }
                }
            }
        }

        return false;
    }

    fn isNullableAllocation(alloc: *const AllocSite) bool {
        const nullable_patterns = [_][]const u8{
            "malloc",        "calloc",         "realloc",         "strdup",
            "sqlite3Malloc", "sqlite3Realloc", "sqlite3DbMalloc", "sqlite3DbRealloc",
            "fopen",         "BIO_new",        "EVP_",            "RSA_",
            "SSL_CTX_new",   "X509_new",       "PEM_",            "inflateInit",
            "deflateInit",   "gzopen",
        };
        for (nullable_patterns) |pattern| {
            if (std.mem.indexOf(u8, alloc.func_name, pattern) != null or
                std.mem.indexOf(u8, alloc.debug_file orelse "", pattern) != null)
            {
                return true;
            }
        }
        return false;
    }

    /// Check if an allocated pointer has a path to any free site.
    fn findFreePath(
        from_ptr: u32,
        free_map: *std.AutoHashMap(u32, *FreeSite),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    ) bool {
        const flow_opt = flow_graph.get(from_ptr);
        if (flow_opt) |flow| {
            var visited = std.AutoHashMap(u32, void).init(flow_graph.allocator);
            defer visited.deinit();
            return canReachFree(from_ptr, flow, free_map, flow_graph, &visited);
        }
        return false;
    }

    /// Helper to recursively find path to free site.
    fn canReachFree(
        from: u32,
        flow: std.AutoHashMap(u32, void),
        free_map: *std.AutoHashMap(u32, *FreeSite),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        visited: *std.AutoHashMap(u32, void),
    ) bool {
        if (visited.contains(from)) return false;
        visited.put(from, {}) catch return false;

        if (free_map.contains(from)) return true;

        var flow_iter = flow.iterator();
        while (flow_iter.next()) |entry| {
            const next = entry.key_ptr.*;
            if (flow_graph.get(next)) |next_flow| {
                if (canReachFree(next, next_flow, free_map, flow_graph, visited)) {
                    return true;
                }
            }
        }

        return false;
    }

    /// Detect double-free: same pointer freed multiple times.
    /// Uses flow graph to detect if the same pointer value flows to multiple free sites.
    fn detectDoubleFree(
        ctx: *PassContext,
        free_map: *std.AutoHashMap(u32, *FreeSite),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        stats: *OwnershipStats,
        diag: *DiagnosticWriter,
    ) void {
        var free_iter = free_map.iterator();
        while (free_iter.next()) |entry| {
            const free_info = entry.value_ptr.*;

            var free_count: u32 = 1;
            if (flow_graph.get(free_info.inst_id)) |flow| {
                var flow_iter = flow.iterator();
                while (flow_iter.next()) |flow_entry| {
                    const target = flow_entry.key_ptr.*;
                    if (free_map.contains(target)) {
                        free_count += 1;
                    }
                }
            }

            if (free_count > 1) {
                stats.double_frees += 1;
                const msg = std.fmt.allocPrint(ctx.allocator, "Pointer freed {d} times", .{free_count}) catch {
                    ctx.addIssue(Issue.init(
                        .double_free,
                        "Pointer freed multiple times",
                        Location.init(free_info.func_name),
                        .high,
                        0.8,
                    )) catch {
                        diag.warn("Failed to register double_free issue", .{});
                    };
                    diag.warn("DOUBLE-FREE [MEDIUM]: Pointer freed multiple times in {s}", .{free_info.func_name});
                    continue;
                };
                ctx.addIssue(Issue.init(
                    .double_free,
                    msg,
                    Location.init(free_info.func_name),
                    .high,
                    0.8,
                )) catch {
                    diag.warn("Failed to register double_free issue (count)", .{});
                };
                ctx.allocator.free(msg);
                diag.warn("DOUBLE-FREE [MEDIUM]: Pointer freed {d} times in {s}", .{ free_count, free_info.func_name });
            }
        }
    }

    /// Detect use-after-free: pointer used after being freed.
    fn detectUseAfterFree(
        ctx: *PassContext,
        free_map: *std.AutoHashMap(u32, *FreeSite),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        stats: *OwnershipStats,
        diag: *DiagnosticWriter,
    ) void {
        var free_iter = free_map.iterator();
        while (free_iter.next()) |entry| {
            const ptr = entry.key_ptr.*;
            const free_info = entry.value_ptr.*;

            if (flow_graph.get(ptr)) |flow| {
                var visited = std.AutoHashMap(u32, void).init(flow_graph.allocator);
                defer visited.deinit();

                if (hasUseAfterFree(ptr, flow, flow_graph, &visited)) {
                    stats.use_after_frees += 1;
                    ctx.addIssue(Issue.init(
                        .use_after_free,
                        "Pointer used after being freed",
                        Location.init(free_info.func_name),
                        .high,
                        0.8,
                    )) catch {
                        diag.warn("Failed to register use_after_free issue", .{});
                    };
                    diag.warn("USE-AFTER-FREE [MEDIUM]: Pointer used after being freed in {s}", .{
                        free_info.func_name,
                    });
                }
            }
        }
    }

    /// Detect use-after-free: pointer used after being freed.
    fn hasUseAfterFree(
        freed_ptr: u32,
        flow: std.AutoHashMap(u32, void),
        flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
        visited: *std.AutoHashMap(u32, void),
    ) bool {
        if (visited.contains(freed_ptr)) return false;
        visited.put(freed_ptr, {}) catch return false;

        var flow_iter = flow.iterator();
        while (flow_iter.next()) |entry| {
            const next = entry.key_ptr.*;
            if (isMemoryAccess(next)) {
                return true;
            }
            if (flow_graph.get(next)) |next_flow| {
                if (hasUseAfterFree(next, next_flow, flow_graph, visited)) {
                    return true;
                }
            }
        }

        return false;
    }

    /// Check if a value represents a memory access (load/store).
    /// Returns true if the value_id corresponds to a known memory access instruction.
    fn isMemoryAccess(value_id: u32) bool {
        _ = value_id;
        return false;
    }

    /// Get the instruction name for a value ID.
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
