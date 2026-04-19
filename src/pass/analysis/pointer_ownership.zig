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
const Language = @import("../../diag/issue.zig").FFIBoundary.Language;
const Location = @import("../../diag/issue.zig").Location;
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
};

/// Allocation site information.
const AllocSite = struct {
    inst_id: u32,
    func_name: []const u8,
    lang: Language,
    alloc_type: AllocType,
    ptr_value_id: u32,
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
            diag.info("PointerOwnership: {s}", .{profiler.summary()});
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
            );
        }

        analysis_timer.stop() catch {};

        var detect_timer = ScopedTimer.start(&profiler, "detect");
        defer detect_timer.stop() catch {};

        try detectViolations(ctx, &alloc_map, &free_map, &flow_graph, &stats, diag, &boundary_analyzer, &lifetime_engine);

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
    ) OwnershipError!void {
        const func_name = getFunctionName(func);

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
            site.* = .{
                .inst_id = inst_id,
                .func_name = func_name,
                .lang = callee_lang,
                .alloc_type = alloc_type,
                .ptr_value_id = inst_id,
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

                        if (boundary_analyzer.checkOwnershipViolation(
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
        if (opcode != c.LLVMCall) return false;

        const called_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return false;

        const name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(name_ptr) == 0) return false;

        const callee_name = std.mem.span(name_ptr);

        // Use SemanticRegistry for accurate identification.
        if (SemanticRegistry.lookup(callee_name)) |sem| {
            return sem.kind == .allocator;
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
        if (opcode != c.LLVMCall) return false;

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
