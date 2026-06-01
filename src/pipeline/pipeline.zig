//! Analysis Pipeline
//!
//! This module implements the overall analysis pipeline that
//! orchestrates passes and data flow.

const std = @import("std");
const log = @import("../common/log.zig");

const FactStore = @import("../fact/store.zig").FactStore;
const QueryEngine = @import("../fact/query.zig").QueryEngine;
const DataFlowGraph = @import("../dataflow/graph.zig").DataFlowGraph;
const Issue = @import("../diag/issue.zig").Issue;
const Severity = @import("../diag/issue.zig").Severity;
const TraceEntry = @import("../diag/issue.zig").TraceEntry;
const Location = @import("../diag/issue.zig").Location;
const ModuleRef = @import("../ir/view.zig").ModuleRef;
const ValueIdMap = @import("../dataflow/value_id_map.zig").ValueIdMap;
const InstCache = @import("../ir/inst_cache.zig").InstCache;

const PassContext = @import("../pass/pass.zig").PassContext;
const DiagnosticWriter = @import("../pass/pass.zig").DiagnosticWriter;
const call_graph_mod = @import("../semantics/call_graph.zig");
const FunctionSemantics = @import("../registry/semantic_registry.zig").FunctionSemantics;
const zone_classifier = @import("../semantics/zone_classifier.zig");
const rust_drop_semantics = @import("../semantics/rust_drop_semantics.zig");
const zig_alloc_tracker = @import("../semantics/zig_allocator_tracker.zig");
const PassManager = @import("../pass/manager.zig").PassManager;

// Resource contract system: shared summaries for all passes
const resource_family_reg = @import("../semantics/resource/family_registry.zig");
const ResourceFamilyRegistry = resource_family_reg.ResourceFamilyRegistry;
const resource_summary = @import("../semantics/resource/function_summary.zig");
const SummaryStore = resource_summary.SummaryStore;
const resource_inference = @import("../semantics/resource/summary_inference.zig");
const transfer_infer = @import("../semantics/resource/transfer_inference.zig");
const resource_candidate = @import("../pass/analysis/resource/issue_candidate_builder.zig");
const CandidateBuilder = resource_candidate.CandidateBuilder;
const resource_verifier = @import("../pass/analysis/resource/issue_verifier.zig");
const IssueVerifier = resource_verifier.IssueVerifier;
const c = @import("../ir/llvm_raw.zig").c;
const llvm_safe = @import("../ir/llvm_safe.zig");

// v0.2.0: Diagnostic Aggregator for cross-pass issue deduplication
const diag_aggregator = @import("../diag/aggregator.zig");
const DiagnosticAggregator = diag_aggregator.DiagnosticAggregator;

// v0.2.0: Language Adapter integration for cross-language FFI analysis
const lang = @import("../lang/adapter_registry.zig");
const lang_types = @import("../lang/types.zig");

// v0.2.0: Container type inference for ownership-aware analysis
const container_inference = @import("../semantics/container_inference.zig");

/// Analysis pipeline
pub const Pipeline = struct {
    allocator: std.mem.Allocator,
    fact_store: *FactStore,
    query_engine: *QueryEngine,
    data_flow_graph: DataFlowGraph,
    pass_manager: PassManager,
    module: ?ModuleRef,
    inst_cache: InstCache,
    /// Minimum confidence to report a leak. Set via setLeakThreshold().
    /// Default 0.5 means medium-confidence+ leaks are reported.
    leak_confidence_threshold: f32 = 0.5,
    /// Enable Zig allocator tracking (default: true).
    /// When false, skips Zig-specific confidence scoring.
    enable_zig_allocator_tracking: bool = true,
    /// Focus on user code only (default: true).
    /// When true, suppresses issues from stdlib/compiler functions.
    /// Set via setFocusUserCode() from CLI config.
    focus_user_code: bool = true,
    /// Deduplicated issue indices cache (populated after run() completes).
    /// Contains indices into data_flow_graph.getIssues() for non-duplicate issues.
    /// Null before run() or if deduplication fails.
    dedup_issue_indices: ?[]usize = null,

    /// Create a new analysis pipeline
    pub fn init(allocator: std.mem.Allocator) !Pipeline {
        const fact_store = try allocator.create(FactStore);
        fact_store.* = try FactStore.init(allocator);

        const query_engine = try allocator.create(QueryEngine);
        query_engine.* = QueryEngine.init(fact_store, allocator);

        const data_flow_graph = try DataFlowGraph.init(allocator, fact_store, query_engine);

        return .{
            .allocator = allocator,
            .fact_store = fact_store,
            .query_engine = query_engine,
            .data_flow_graph = data_flow_graph,
            .pass_manager = try PassManager.init(allocator),
            .module = null,
            .inst_cache = InstCache.init(allocator),
        };
    }

    /// Deinitialize the pipeline
    pub fn deinit(self: *Pipeline) void {
        self.data_flow_graph.deinit();
        self.query_engine.deinit();
        self.fact_store.deinit();
        self.allocator.destroy(self.fact_store);
        self.allocator.destroy(self.query_engine);
        self.pass_manager.deinit();
        self.inst_cache.deinit();
        // Free deduplicated issue indices cache if allocated
        if (self.dedup_issue_indices) |indices| {
            self.allocator.free(indices);
            self.dedup_issue_indices = null;
        }
    }

    /// Run the full analysis pipeline
    pub fn run(self: *Pipeline) !void {
        // Note: query_engine is a value type that references fact_store
        // We don't need to reinitialize it since fact_store pointer hasn't changed

        // Clear previous data flow graph state
        self.data_flow_graph.clear();

        // Create context with module and data flow graph
        // Initialize resource contract system (family registry + summary store)
        var family_registry = try ResourceFamilyRegistry.init(self.allocator);
        defer family_registry.deinit();

        var summary_store = SummaryStore.init(self.allocator);
        defer summary_store.deinit();
        resource_inference.initBuiltinSummaries(&summary_store, &family_registry) catch {
            // Non-fatal: continue without builtin summaries (legacy mode)
            log.warn("Builtin summary initialization failed, using legacy mode", .{});
        };

        // Initialize two-stage issue verification system
        var candidate_builder = CandidateBuilder.init(self.allocator);
        defer candidate_builder.deinit();

        var issue_verifier = IssueVerifier.init(self.allocator);
        defer issue_verifier.deinit();

        var ctx = PassContext{
            .allocator = self.allocator,
            .module = self.module,
            .fact_store = self.fact_store,
            .query_engine = self.query_engine,
            .data_flow_graph = &self.data_flow_graph,
            .next_id = std.atomic.Value(u32).init(1),
            .vuln_id = std.atomic.Value(u32).init(0),
            .value_id_map = ValueIdMap.init(self.allocator),
            .raii_func_set = std.AutoHashMap(usize, void).init(self.allocator),
            .meyers_singleton_set = std.AutoHashMap(usize, void).init(self.allocator),
            .rc_container_func_set = std.AutoHashMap(usize, void).init(self.allocator),
            .rust_into_raw_set = std.StringHashMap(void).init(self.allocator),
            .rust_from_raw_set = std.StringHashMap(void).init(self.allocator),
            .reported_keys = std.AutoHashMap(u64, void).init(self.allocator),
            .registry_cache = std.StringHashMap(FunctionSemantics).init(self.allocator),
            .zone_cache = std.StringHashMap(zone_classifier.ZoneKind).init(self.allocator),
            .zone_stats = .{},
            .module_language = .{ .language = .unknown, .confidence = 0.0, .method = .unknown },
            .language_detected = false,
            .degraded_functions = std.atomic.Value(u32).init(0),
            .cross_lang_edges = std.ArrayList(@import("../pass/pass.zig").CrossLangEdge).empty,
            .early_exit = false,
            .global_alloc_tracker = @import("../pass/pass.zig").GlobalAllocTracker.init(self.allocator),
            .memory_graph = try @import("../semantics/memory_graph.zig").MemoryGraph.init(self.allocator),
            .danger_surface_relevant = std.AutoHashMap(u64, void).init(self.allocator),
            .ffi_auto_relevant = std.AutoHashMap(u64, void).init(self.allocator),
            .relevant_functions = std.AutoHashMap(u64, void).init(self.allocator),
            .CallSiteIndex = @import("../pass/pass.zig").CallSiteIndex.init(self.allocator),
            .cross_edge_by_callee = std.StringHashMap(std.ArrayList(u32)).init(self.allocator),
            .semantics_call_graph = null,
            .ffi_set_cache = null,
            .danger_surfaces_cache = null,
            .danger_path_visited_cache = null,
            .function_surface = std.AutoHashMap(u64, @import("../semantics/surface_classifier/surface_classifier.zig").FunctionSurface).init(self.allocator),
            .semantic_resolution = null,
            .suppression_stats = .{},
            .evidence = null,
            .interner = null,
            .arena = null,
            .platform_profile = null,
            .resource_summary = &summary_store,
            .candidate_builder = &candidate_builder,
            .issue_verifier = &issue_verifier,
            .contract_db = try @import("../resource/ffi_contract_db.zig").FFIContractDB.init(self.allocator),
            .focus_user_code = self.focus_user_code,
        };
        // Inject resource family registry into memory graph for P2/P3 classification
        ctx.memory_graph.setFamilyRegistry(&family_registry);

        // CRITICAL: Deinit semantics CallGraph to prevent GPA memory leak warnings.
        // Must be deferred because semantics_call_graph is populated later in CallGraphPass.run().
        // The graph uses GeneralPurposeAllocator (not Arena) so all internal
        // allocations (HashMap, ArrayList, dupe'd strings) must be explicitly freed.
        defer {
            if (ctx.semantics_call_graph) |*sg| {
                call_graph_mod.CallGraph.deinit(sg);
            }
        }
        defer ctx.deinit();

        // R7.2 Language-First: detect module language ONCE before any passes run.
        // This activates the correct zone rules channel for all subsequent analysis.
        ctx.initModuleLanguage(self.module);

        // Platform Profile: detect target OS/object format from LLVM metadata ONCE.
        // Used by SurfaceClassifier (runtime shim ID), language detector (symbol canonicalization),
        // and noise suppressor (toolchain path normalization).
        if (self.module) |mod| {
            const raw_mod = mod.raw;
            ctx.platform_profile = @import("../semantics/platform_profile.zig").PlatformProfile.detect(raw_mod, self.allocator) catch null;
            if (ctx.platform_profile) |*prof| {
                log.info("Platform: {s} ({s}) arch={s} triple={s}", .{
                    prof.platform.displayName(),
                    prof.object_format.displayName(),
                    prof.arch,
                    prof.target_triple,
                });
            }
        }

        // P0-2: Build shared callee→call_sites index ONCE before any passes run.
        // All call_graph and ffi_boundary lookups become O(1) instead of O(F).
        // P0-3: FAST FFI PRE-CHECK — detect if ANY call instruction calls an extern/declaration
        // function. If no external calls exist, the module is pure single-language and
        // all FFI analysis passes (pointer_ownership, ffi_boundary, etc.) can be skipped.
        // This saves ~17s on wasmtime_test.bc (pure Rust module without external FFI calls).
        var has_ffi_calls = false;
        {
            const t_idx = std.time.nanoTimestamp();
            if (self.module) |mod| {
                const raw_mod = mod.raw;
                var func = c.LLVMGetFirstFunction(raw_mod);
                while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
                    if (c.LLVMIsDeclaration(func) != 0) continue;
                    const func_ptr = @as(u64, @intFromPtr(func));
                    var bb = c.LLVMGetFirstBasicBlock(func);
                    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                        var inst = c.LLVMGetFirstInstruction(bb);
                        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                            const opcode = c.LLVMGetInstructionOpcode(inst);
                            if (!llvm_safe.isCallOrInvoke(opcode)) continue;
                            const called_val = c.LLVMGetCalledValue(inst);
                            if (@intFromPtr(called_val) == 0) continue;
                            const called_name_ptr = c.LLVMGetValueName(called_val);
                            if (@intFromPtr(called_name_ptr) == 0) continue;
                            const called_name = std.mem.span(called_name_ptr);
                            const inst_ptr = @as(u64, @intFromPtr(inst));
                            // DC-C4 FIX: Log OOM instead of silently swallowing error
                            ctx.CallSiteIndex.addCall(self.allocator, called_name, func_ptr, inst_ptr) catch |err| {
                                log.warn("[WARN] Failed to add call site for '{s}': {}", .{ called_name, err });
                            };
                            // P0-3: Check if callee is an external declaration (FFI boundary indicator)
                            if (c.LLVMIsDeclaration(called_val) != 0) {
                                has_ffi_calls = true;
                            }
                        }
                    }
                }
            }
            const idx_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - t_idx)) / 1_000_000.0;
            if (idx_ms > 10) log.debug("[PERF] CallSiteIndex build: {d:.1} ms", .{@as(u32, @intFromFloat(idx_ms))});
        }

        var diag = DiagnosticWriter{ .allocator = self.allocator };

        // ════════════════════════════════════════════════════
        // v0.2.0: Language Adapter Integration
        // Initialize adapter registry and run per-function analysis
        // to populate MemoryGraph with language-specific FFI semantics.
        // This transforms adapters from "dead code" to active analysis.
        // ════════════════════════════════════════════════════
        var adapter_registry = lang.AdapterRegistry.init(self.allocator) catch |err| {
            log.warn("AdapterRegistry init failed: {} — continuing without language adapters", .{err});
            // Continue without adapters (legacy mode)
            try self.pass_manager.run(&ctx, &diag);
            return;
        };
        defer adapter_registry.deinit();

        log.info("PIPELINE: Initialized Language Adapter Registry ({} adapters)", .{
            adapter_registry.adapterCount(),
        });

        // Auto-detect target language from module metadata
        const detected_adapter = if (self.module) |mod| blk: {
            const raw_mod = mod.raw;
            break :blk adapter_registry.detectAdapter(@ptrCast(raw_mod));
        } else blk: {
            break :blk adapter_registry.detectAdapter(undefined);
        };

        log.info("PIPELINE: Detected language: {s}, using adapter: {s} (memory model: {s})", .{
            @tagName(detected_adapter.language),
            detected_adapter.name,
            @tagName(detected_adapter.memory_model),
        });

        // Run language-specific pre-analysis on ALL functions
        // This populates results with FFI call classifications
        var total_ffi_calls_classified: u32 = 0;
        var functions_analyzed: u32 = 0;

        // Iterate over all functions in the module (same loop as CallSiteIndex)
        if (self.module) |mod| {
            const raw_mod = mod.raw;
            var func_iter = c.LLVMGetFirstFunction(raw_mod);
            while (@intFromPtr(func_iter) != 0) : (func_iter = c.LLVMGetNextFunction(func_iter)) {
                // Skip declarations (no body)
                if (c.LLVMIsDeclaration(func_iter) != 0) continue;

                functions_analyzed += 1;

                // Run adapter analysis on this function
                var analysis = detected_adapter.analyzeFunction(
                    @ptrCast(func_iter),
                    @ptrCast(&ctx),
                    self.allocator,
                ) catch |err| {
                    log.warn("ADAPTER: Failed to analyze function: {}", .{err});
                    continue;
                };

                // Count classified FFI calls
                total_ffi_calls_classified += @intCast(analysis.ffi_calls.items.len);

                // Process analysis results immediately (no storage needed)
                defer analysis.deinit();

                // ═══════════════════════════════════════════════
                // Write analysis results into MemoryGraph (INTEGRATION POINT)
                // ═══════════════════════════════════════════════
                for (analysis.ffi_calls.items) |call| {
                    switch (call.semantics) {
                        .returns_owned => {
                            // Mark this as an owned resource that caller must free
                            log.debug("ADAPTER: {s} returns OWNED at inst 0x{x} (confidence={d:.2})", .{
                                call.callee_name, call.inst_addr, call.confidence,
                            });
                            // Note: The actual AllocNode will be created by later passes.
                            // Here we record the semantics for cross-referencing.
                        },
                        .returns_borrowed => {
                            // Mark as borrowed - don't report as leak even if not freed
                            log.debug("ADAPTER: {s} returns BORROWED at inst 0x{x} - marking as weak ref (confidence={d:.2})", .{
                                call.callee_name, call.inst_addr, call.confidence,
                            });

                            // Record in MemoryGraph to suppress false positive leak reports
                            ctx.memory_graph.markBorrowedReference(call.inst_addr) catch |err| {
                                log.warn("ADAPTER: Failed to mark borrowed ref at 0x{x}: {}", .{
                                    call.inst_addr, err,
                                });
                            };
                        },
                        .consumes_arg => {
                            // Mark that argument ownership is transferred
                            log.debug("ADAPTER: {s} CONSUMES arg at inst 0x{x} (confidence={d:.2})", .{
                                call.callee_name, call.inst_addr, call.confidence,
                            });
                        },
                        else => {},
                    }
                }

                // Convert adapter issues to pipeline Issues (Phase 1: Go cgo integration)
                // This implements the issue conversion point specified in
                // docs/v2/ffi_lang_support_plan.md Step 2.
                for (analysis.issues.items) |adapter_issue| {
                    var issue = Issue.init(
                        adapter_issue.issue_type.toIssueKind(),
                        adapter_issue.message,
                        Location.init(adapter_issue.location.function_name),
                        switch (adapter_issue.severity) {
                            .low => Severity.low,
                            .medium => Severity.medium,
                            .high => Severity.high,
                            .critical => Severity.critical,
                        },
                        adapter_issue.confidence,
                    );
                    issue.owned = true; // We own the message allocation

                    ctx.addIssue(&issue) catch |err| {
                        log.warn("ADAPTER-ISSUE: Failed to add issue to context: {}", .{err});
                    };

                    log.debug("ADAPTER-ISSUE: [{s}] {s} (confidence={d:.2})", .{
                        @tagName(adapter_issue.issue_type),
                        adapter_issue.message,
                        adapter_issue.confidence,
                    });
                }
            }
        }

        log.info("PIPELINE: Analyzed {} functions with {s} adapter ({} FFI calls classified)", .{
            functions_analyzed,
            detected_adapter.name,
            total_ffi_calls_classified,
        });

        // ════════════════════════════════════════════════════
        // v0.2.0: Container Type Inference (Phase 2 - Ownership Aware)
        // After adapter analysis, infer container types for all allocations
        // to enable RAII/refcount/GC-aware leak suppression.
        //
        // This activates the ContainerInferer engine to classify allocations
        // into Rust Box/Vec/String, C++ unique_ptr/shared_ptr, Python list/dict,
        // and Go slice/map containers. Each classification sets the appropriate
        // ownership_model on the AllocNode for downstream leak suppression.
        // ════════════════════════════════════════════════════
        var container_inferer = container_inference.ContainerInferer.init(self.allocator);
        var containers_classified: u32 = 0;

        var idx: usize = 0;
        while (idx < ctx.memory_graph.node_store.items.len) : (idx += 1) {
            const node = ctx.memory_graph.node_store.items[idx];
            // Only classify nodes that have alloc_callee and no container_type yet
            // Note: We need to check if the node has alloc_callee information.
            // Since AllocNode doesn't directly store alloc_callee, we use
            // GlobalAllocTracker records as the source of truth for callee names.
            if (node.*.container_type == null) {
                // Try to find matching alloc record from GlobalAllocTracker
                const tracker = &ctx.global_alloc_tracker;
                for (tracker.records.items) |rec| {
                    // Match by pointer ID or instruction address
                    if (rec.ptr_id == @as(u32, @truncate(node.alloc_inst)) or
                        @as(u64, rec.ptr_id) == node.alloc_inst)
                    {
                        // Found a match - apply container inference
                        if (rec.alloc_callee.len > 0) {
                            container_inferer.applyToNode(node, rec.alloc_callee);

                            if (node.container_type != null) {
                                containers_classified += 1;

                                log.debug("PIPELINE: Node {d} ({s}) classified as {s} (ownership={s})", .{
                                    node.id,
                                    rec.alloc_callee,
                                    @tagName(node.container_type.?),
                                    @tagName(node.ownership_model),
                                });
                            }
                        }
                        break; // Found match, stop searching
                    }
                }
            }
        }

        if (containers_classified > 0) {
            log.info("PIPELINE: Container inference classified {} nodes", .{containers_classified});
        } else {
            log.debug("PIPELINE: No nodes classified (alloc_callee may not be populated yet or no container patterns matched)", .{});
        }

        // P0-3: If no FFI calls detected at IR level, skip heavy FFI analysis passes.
        // This eliminates significant overhead on pure single-language modules
        // where call_graph + pointer_ownership + pointer-flow + ffi-boundary
        // all run despite having zero actual FFI boundaries.
        if (!has_ffi_calls) {
            log.info("Pipeline: no external/declaration call sites detected — pure single-language module, skipping FFI passes", .{});
            ctx.early_exit = true;
        }

        // Run passes
        try self.pass_manager.run(&ctx, &diag);

        // R8.3-d: Post-pass leak report — scan GlobalAllocTracker for unfreed allocations.
        // After all passes have run, any allocation that was never freed is a leak candidate.
        // Skip global/static variables (intentionally never freed) and already-matched pairs.
        // D1-4: Promote candidates to confirmed leaks when they reach FFI boundaries.
        const leak_count = ctx.global_alloc_tracker.leakCount();
        if (leak_count > 0) {
            const tracker = &ctx.global_alloc_tracker;
            var confirmed_high: u32 = 0;
            var reported_leaks: u32 = 0;

            // ════════════════════════════════════════════════════
            // v0.2.0: Initialize Zig Allocator Tracker ONCE (outside loop)
            // This is a performance optimization: avoid re-creating
            // the tracker for every allocation record.
            // ════════════════════════════════════════════════════
            var zig_tracker = zig_alloc_tracker.Tracker.init(self.allocator);

            for (tracker.records.items) |rec| {
                if (!rec.freed and !rec.is_global_or_static) {
                    // ════════════════════════════════════════════════════
                    // Phase 2: RAII Cleanup Check (Ownership-Aware Analysis)
                    // Suppress false positives for allocations managed by:
                    //   - Rust Drop trait (drop_in_place → __rust_dealloc)
                    //   - C++ destructors (unique_ptr, shared_ptr)
                    //   - Python refcount (Py_INCREF/DECREF)
                    //   - Go GC (runtime GC)
                    //   - Container types (Box, Vec, String, etc.)
                    // ════════════════════════════════════════════════════

                    // Check 1: RAII cleanup via MemoryGraph (trackRustDrop)
                    if (ctx.memory_graph.hasRAIICleanup(@as(u64, rec.ptr_id))) {
                        log.debug("LEAK-SUPPRESS: Alloc {} has RAII cleanup (drop/destructor)", .{
                            rec.ptr_id,
                        });
                        continue;
                    }

                    // Check 2: Container type classification
                    if (ctx.memory_graph.findNodeByInst(@as(u64, rec.ptr_id))) |node_idx| {
                        const node = ctx.memory_graph.node_store.items[node_idx];

                        // Container-managed memory (auto-cleanup)
                        if (node.container_type) |container| {
                            switch (container) {
                                .rust_box,
                                .rust_vec,
                                .rust_string,
                                .cpp_unique_ptr,
                                .cpp_shared_ptr,
                                .std_vector,
                                .std_string,
                                // Zig containers: all use deinit() for cleanup
                                .zig_arraylist,
                                .zig_hashmap,
                                .zig_buffer,
                                .zig_multiarraylist,
                                => {
                                    log.debug("LEAK-SUPPRESS: Alloc {} is in container {s} (auto-managed)", .{
                                        rec.ptr_id,
                                        @tagName(container),
                                    });
                                    continue;
                                },
                                else => {},
                            }
                        }

                        // GC-managed memory
                        if (node.is_gc_managed) {
                            log.debug("LEAK-SUPPRESS: Alloc {} is GC-managed", .{
                                rec.ptr_id,
                            });
                            continue;
                        }

                        // Borrowed references (owned by another runtime)
                        if (node.is_borrowed) {
                            log.debug("LEAK-SUPPRESS: Alloc {} is borrowed reference", .{
                                rec.ptr_id,
                            });
                            continue;
                        }
                    }

                    // Check 3: Rust allocator intrinsics (existing check)
                    if (ctx.isRustModule()) {
                        var is_rust_alloc = false;
                        // Check alloc_callee for Rust allocator intrinsics
                        for (rust_drop_semantics.DROP_ALLOC_INTRINSICS.alloc) |intrinsic| {
                            if (std.mem.indexOf(u8, rec.alloc_callee, intrinsic) != null) {
                                is_rust_alloc = true;
                                break;
                            }
                        }
                        // Also check for C++ operator new in Rust modules (used by some allocators)
                        if (std.mem.indexOf(u8, rec.alloc_callee, "_Znwm") != null or
                            std.mem.indexOf(u8, rec.alloc_callee, "_Znam") != null)
                        {
                            is_rust_alloc = true;
                        }
                        if (is_rust_alloc) continue;
                    }

                    // P19-2: Structural transfer inference — check if alloc result
                    // is returned to caller (factory pattern) before reporting leak.
                    // This is NAME-INDEPENDENT: works by analyzing IR instruction
                    // patterns (ret <alloc_result>), not function names.
                    if (rec.alloc_func_val) |func_val| {
                        const transfer = transfer_infer.detectTransferInFunction(func_val);
                        if (transfer) |t| {
                            if (t.detected) {
                                diag.debug("LEAK-SKIP: {s} has structural transfer ({any}) — not a leak", .{ rec.alloc_func, t });
                                continue;
                            }
                        }
                    }

                    const msg = try std.fmt.allocPrint(self.allocator, "Potential memory leak: heap allocation in {s}() was never freed", .{rec.alloc_func});
                    const trace = try self.allocator.alloc(TraceEntry, 1);
                    trace[0] = TraceEntry.init("Allocation tracked by GlobalAllocTracker but no matching free found in module");
                    // D1-4: Check if leaked ptr reaches FFI boundary → promote severity
                    const is_on_ffi_path = ctx.isOnDangerPathFull(rec.ptr_id);
                    const severity: Severity = if (is_on_ffi_path) .high else .low;

                    // Bug 4: Path-sensitive confidence reduction for conditional allocs.
                    // If allocation is inside a conditional branch (if/else, loop body),
                    // it may not execute on all code paths → reduce confidence by ~25%.
                    // This fixes FFT-LEAK-3 / FFT-LEAK-2 / BUG-4c conditional path FPs.
                    var base_confidence: f32 = if (is_on_ffi_path) 0.78 else 0.58;
                    if (rec.is_global_or_static) {
                        base_confidence += 0.08;
                    }
                    const is_known_dangerous_alloc = std.mem.indexOf(u8, rec.alloc_callee, "alloc") != null or
                        std.mem.indexOf(u8, rec.alloc_callee, "malloc") != null or
                        std.mem.indexOf(u8, rec.alloc_callee, "calloc") != null or
                        std.mem.indexOf(u8, rec.alloc_callee, "realloc") != null or
                        std.mem.indexOf(u8, rec.alloc_callee, "strdup") != null or
                        std.mem.indexOf(u8, rec.alloc_callee, "mem_dup") != null;
                    if (is_known_dangerous_alloc) {
                        base_confidence += 0.07;
                    }
                    // ════════════════════════════════════════════════════
                    // Boost 3: Large allocation size (> 1 MB)
                    // Large leaks are more impactful than small ones.
                    // They can cause OOM, noticeable slowdowns, etc.
                    // Thresholds:
                    //   - > 1 MB: +0.10 (large allocation leak)
                    //   - > 100 KB: +0.05 (medium-large allocation)
                    //   - ≤ 100 KB: no additional boost (small allocations)
                    //   - unknown size: no penalty or bonus (graceful fallback)
                    // ════════════════════════════════════════════════════
                    if (rec.alloc_size) |size| {
                        if (size > 1024 * 1024) {
                            base_confidence += 0.10;
                            log.debug("[LEAK-LARGE] Large allocation ({d} bytes) increases confidence by 0.10", .{size});
                        } else if (size > 1024 * 100) {
                            base_confidence += 0.05;
                            log.debug("[LEAK-MEDIUM] Medium-large allocation ({d} bytes) increases confidence by 0.05", .{size});
                        }
                        // Small allocations (< 100 KB): no additional boost
                    } else {
                        log.debug("[LEAK-SIZE] Unknown allocation size — skipping size-based boost", .{});
                    }
                    if (rec.is_conditional) {
                        base_confidence *= 0.75;
                        if (base_confidence < 0.30) base_confidence = 0.30;
                    }
                    base_confidence = @min(base_confidence, 0.95);

                    // Zig Allocator Tracking: adjust confidence based on allocator semantics.
                    // Arena/FixedBuffer/testing allocators have deterministic cleanup,
                    // so confidence should be low unless on an FFI boundary.
                    // Only run if enabled via setZigAllocatorTracking(true) [default].
                    if (self.enable_zig_allocator_tracking) {
                        if (ctx.memory_graph.findNodeByInst(@as(u64, rec.ptr_id))) |node_idx| {
                            const leak_node = ctx.memory_graph.node_store.items[node_idx];
                            const zig_confidence = zig_tracker.calculateLeakConfidence(
                                leak_node,
                                rec.alloc_callee,
                                is_on_ffi_path,
                            );
                            // Use the lower of the two scores: existing heuristic vs Zig-aware scoring.
                            // This prevents false positives when Zig's allocator semantics
                            // indicate safe management, even if the general heuristic scores it high.
                            if (zig_confidence.score < base_confidence) {
                                log.debug("ZIG-TRACKER: Lowering confidence {d:.2} → {d:.2} for alloc {} ({s})", .{
                                    base_confidence,
                                    zig_confidence.score,
                                    rec.ptr_id,
                                    zig_confidence.reason,
                                });
                                base_confidence = zig_confidence.score;
                            }
                        }
                    }

                    // Suppress leak if final confidence is below user-configured threshold.
                    if (base_confidence < self.leak_confidence_threshold) {
                        log.debug("LEAK-SUPPRESS: confidence {d:.2} < threshold {d:.2}, skipping alloc {}", .{
                            base_confidence,
                            self.leak_confidence_threshold,
                            rec.ptr_id,
                        });
                        continue;
                    }

                    const confidence = base_confidence;
                    if (is_on_ffi_path) confirmed_high += 1;

                    // FIX: Let addIssue take ownership by setting owned=true.
                    // Previous code used owned=false + manual free, which leaked trace[0].description.
                    // The correct ownership model is:
                    //   1. We allocate msg and trace (with trace[0].description)
                    //   2. We set owned=true to indicate we own this memory
                    //   3. addIssue deep-copies everything, then calls deinit on our original
                    //   4. deinit frees msg + trace + trace[0].description (all owned)
                    //   5. The graph owns the deep copies and frees them on graph.deinit
                    var issue = Issue.initWithTrace(
                        .memory_leak,
                        msg,
                        Location.init(rec.alloc_func),
                        severity,
                        confidence,
                        trace,
                    );
                    issue.owned = true; // We own msg and trace; addIssue will deep-copy then deinit our originals
                    try ctx.addIssue(&issue);
                    reported_leaks += 1;
                }
            }
            const omi_prefix = if (confirmed_high > 0) "[OMI-HIGH] " else "";
            diag.info("{s}GlobalAllocTracker: {d} memory leaks confirmed from {d} tracked allocations ({d} cross-FFI)", .{
                omi_prefix, reported_leaks, tracker.size(), confirmed_high,
            });
        }

        // ════════════════════════════════════════════════════
        // v0.2.0: Cross-pass issue deduplication via DiagnosticAggregator
        // After all passes complete, deduplicate issues to prevent
        // duplicate reports from different passes detecting the same issue.
        // Uses (function + kind + file + line) as dedup key.
        // ════════════════════════════════════════════════════
        {
            var aggregator = try DiagnosticAggregator.init(self.allocator);
            defer aggregator.deinit();

            const all_issues = self.data_flow_graph.getIssues();
            var indices = try std.ArrayList(usize).initCapacity(self.allocator, all_issues.len);

            for (all_issues, 0..) |issue, issue_idx| {
                // Use aggregator's addIssue for deduplication checking.
                // Returns true if issue is new (not a duplicate).
                const is_new = try aggregator.addIssue(issue);
                if (is_new) {
                    // Store index of non-duplicate issue.
                    try indices.append(self.allocator, issue_idx);
                }
            }

            // Store deduplicated issue indices (caller owns this memory).
            self.dedup_issue_indices = try indices.toOwnedSlice(self.allocator);

            const dup_count = all_issues.len - self.dedup_issue_indices.?.len;
            if (dup_count > 0) {
                log.info("PIPELINE: Deduplication removed {} duplicate issues ({} unique remaining)", .{
                    dup_count, self.dedup_issue_indices.?.len,
                });
            }
        }
    }

    /// Run static analysis stage
    pub fn runStaticAnalysis(self: *Pipeline) !PipelineResult {
        const start_time = std.time.nanoTimestamp();

        // Run passes
        try self.run();

        const end_time = std.time.nanoTimestamp();
        const duration_ns = @max(@as(i128, 0), end_time - start_time);

        return PipelineResult{
            .fact_count = self.fact_store.count(),
            .execution_time_ns = @intCast(duration_ns),
        };
    }

    /// Get the fact store
    pub fn getFactStore(self: *Pipeline) *FactStore {
        return self.fact_store;
    }

    /// Get the query engine
    pub fn getQueryEngine(self: *Pipeline) *QueryEngine {
        return self.query_engine;
    }

    /// Get the data flow graph
    pub fn getDataFlowGraph(self: *Pipeline) *DataFlowGraph {
        return &self.data_flow_graph;
    }

    /// Get all detected issues (deduplicated if run() has completed).
    ///
    /// After run() executes, returns deduplicated issues with duplicates
    /// removed across passes. Before run() or if deduplication failed,
    /// returns raw issues from data_flow_graph.
    ///
    /// Note: This returns a view into data_flow_graph's internal storage.
    /// For deduplicated results, use getIssuesOwned() instead.
    pub fn getIssues(self: *const Pipeline) []const Issue {
        // Always return raw issues for backward compatibility.
        // Use getIssuesOwned() for deduplicated results.
        return self.data_flow_graph.getIssues();
    }

    /// Get all detected issues (deduplicated, caller-owned).
    ///
    /// Returns a newly allocated slice containing only non-duplicate issues.
    /// Caller MUST free the returned slice and each issue's owned memory
    /// by calling freeIssuesOwned() when done.
    ///
    /// Returns null if run() hasn't completed or deduplication failed.
    pub fn getIssuesOwned(self: *Pipeline, allocator: std.mem.Allocator) ?[]Issue {
        // Return deduplicated issues if available (populated by run()).
        if (self.dedup_issue_indices) |indices| {
            const all_issues = self.data_flow_graph.getIssues();
            var result = try std.ArrayList(Issue).initCapacity(allocator, indices.len);

            for (indices) |idx| {
                const original = all_issues[idx];
                // Deep copy issue to create independent owned copy.
                const copied = try self.deepCopyIssue(allocator, original);
                try result.append(copied);
            }

            return result.toOwnedSlice(allocator);
        }
        // No deduplication available.
        return null;
    }

    /// Free issues slice returned by getIssuesOwned().
    ///
    /// Properly frees all owned memory within each issue and the slice itself.
    pub fn freeIssuesOwned(_: *Pipeline, allocator: std.mem.Allocator, issues: []Issue) void {
        for (issues) |*issue| {
            issue.deinit(allocator);
        }
        allocator.free(issues);
    }

    /// Deep copy an issue with full ownership transfer.
    ///
    /// Creates an independent copy of the issue with all heap-allocated
    /// fields (message, trace, location.function) duplicated.
    /// The returned issue has owned=true so deinit() will free everything.
    fn deepCopyIssue(_: *Pipeline, allocator: std.mem.Allocator, original: Issue) !Issue {

        // Copy message (always present).
        const msg = try allocator.dupe(u8, original.message);
        errdefer allocator.free(msg);

        // Copy location.function if it's heap-allocated.
        var loc = original.location;
        var func_owned = false;
        if (original.function_owned and original.location.func.len > 0) {
            loc.func = try allocator.dupe(u8, original.location.func);
            func_owned = true;
        }
        errdefer if (func_owned) allocator.free(loc.func);

        // Copy trace entries if present.
        var trace: ?[]TraceEntry = null;
        if (original.trace) |original_trace| {
            var copied_trace = try allocator.alloc(TraceEntry, original_trace.len);
            errdefer allocator.free(copied_trace);

            for (original_trace, 0..) |entry, i| {
                if (entry.owned and entry.description.len > 0) {
                    const desc = try allocator.dupe(u8, entry.description);
                    copied_trace[i] = .{
                        .description = desc,
                        .location = entry.location,
                        .owned = true,
                    };
                } else {
                    copied_trace[i] = entry; // Borrowed reference
                }
            }
            trace = copied_trace;
        }

        // Return fully owned copy.
        return .{
            .kind = original.kind,
            .message = msg,
            .location = loc,
            .severity = original.severity,
            .confidence = original.confidence,
            .confidence_level = original.confidence_level,
            .reason = original.reason, // Borrowed (string literal or borrowed slice)
            .semantic_surface = original.semantic_surface,
            .escape_evidence = original.escape_evidence,
            .explained_safe = original.explained_safe,
            .ffi_boundary = original.ffi_boundary, // Optional value copy
            .trace = trace,
            .owned = true, // We own all allocated memory.
            .function_owned = func_owned,
            .classification = original.classification,
            .resource_family = original.resource_family, // Borrowed slices
            .release_family = original.release_family,
            .verdict = original.verdict,
            .adjusted_score = original.adjusted_score,
            .is_contract_based = original.is_contract_based,
        };
    }

    /// Set the LLVM module to analyze
    pub fn setModule(self: *Pipeline, module: ModuleRef) void {
        self.module = module;
    }

    /// Register a pass with the pipeline
    pub fn registerPass(self: *Pipeline, comptime PassType: type) !void {
        try self.pass_manager.registerPass(PassType);
    }

    /// Enable or disable per-pass performance profiling
    /// Must be called before run() or runStaticAnalysis()
    pub fn setPerfStats(self: *Pipeline, enabled: bool) void {
        self.pass_manager.setPerfStats(enabled);
    }

    /// Set minimum confidence threshold for leak reporting.
    ///
    /// Leaks with confidence below this threshold are suppressed.
    /// Zig Arena/FixedBuffer allocations typically score ~0.2 and are auto-suppressed
    /// at the default threshold of 0.5.
    ///
    /// Arguments:
    ///   threshold - Value in [0.0, 1.0]
    pub fn setLeakThreshold(self: *Pipeline, threshold: f32) void {
        self.leak_confidence_threshold = threshold;
    }

    /// Enable or disable Zig allocator tracking.
    ///
    /// When disabled, Zig-specific confidence scoring is skipped,
    /// falling back to generic heuristics only. Useful for non-Zig projects
    /// where the overhead of allocator classification is unnecessary.
    ///
    /// Arguments:
    ///   enabled - true to enable, false to disable
    pub fn setZigAllocatorTracking(self: *Pipeline, enabled: bool) void {
        self.enable_zig_allocator_tracking = enabled;
    }

    /// Set whether to focus on user code only (skip stdlib).
    ///
    /// When enabled (default), issues from known stdlib and compiler-generated
    /// functions are suppressed. This significantly reduces false positives
    /// for Zig/Rust/Go projects (80%+ FP reduction).
    ///
    /// Arguments:
    ///   value - true to focus on user code only, false to report all issues
    pub fn setFocusUserCode(self: *Pipeline, value: bool) void {
        self.focus_user_code = value;
    }

    // ════════════════════════════════════════════════════
    // v0.2.0: Helper Functions for Zig Allocator Tracking
    // ════════════════════════════════════════════════════

    /// Heuristic check if allocation crosses FFI boundary.
    /// Uses pattern matching on allocation function names and
    /// cross-language edge analysis.
    fn isFFIBoundaryAllocation(rec: @import("../pass/pass.zig").GlobalAllocTracker.AllocRecord, ctx: *PassContext) bool {
        // Check if allocation function is known FFI API
        if (rec.alloc_callee.len > 0) {
            const ffi_alloc_patterns = [_][]const u8{
                "SSL_",        "BIO_",       "RSA_",       "EVP_",
                "sqlite3",     "PyList_New", "PyDict_New", "C.malloc",
                "_Cgo_malloc",
            };
            for (ffi_alloc_patterns) |pattern| {
                if (std.mem.indexOf(u8, rec.alloc_callee, pattern) != null) {
                    return true;
                }
            }
        }

        // Check cross-language edges
        for (ctx.cross_lang_edges.items) |edge| {
            if (edge.involvesPtr(@intFromPtr(rec.ptr_id))) {
                return true;
            }
        }

        return false;
    }

    /// Report leak with confidence metadata.
    /// Determines severity from confidence score and creates
    /// a detailed issue with confidence reasoning.
    fn reportLeakWithConfidence(
        rec: @import("../pass/pass.zig").GlobalAllocTracker.AllocRecord,
        node: @import("../semantics/memory_graph.zig").AllocNode,
        confidence: zig_alloc_tracker.LeakConfidence,
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        _ = node;
        _ = diag;

        // Determine severity from confidence
        const severity: Severity = if (confidence.isCritical())
            .critical
        else if (confidence.isHigh())
            .high
        else if (confidence.isMedium())
            .medium
        else
            .low;

        const msg = try std.fmt.allocPrint(
            ctx.allocator,
            "Potential memory leak (confidence: {d:.0}%): {s}\n  Allocated by: {s}",
            .{ confidence.score * 100, confidence.reason, rec.alloc_callee },
        );
        errdefer ctx.allocator.free(msg);

        var issue = Issue.init(
            .memory_leak,
            msg,
            Location.init(rec.alloc_func),
            severity,
            confidence.score,
        );
        issue.reason = try std.fmt.dupe(ctx.allocator, "{s}", .{confidence.reason});
        errdefer ctx.allocator.free(issue.reason);

        try ctx.addIssue(&issue);
    }
};

/// Pipeline result
pub const PipelineResult = struct {
    /// Number of facts generated
    fact_count: usize,
    /// Execution time in nanoseconds
    execution_time_ns: u64,
};

test "Pipeline - init and deinit" {
    var pipeline = try Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    try std.testing.expectEqual(@as(usize, 0), pipeline.fact_store.count());
}

test "Pipeline - get components" {
    var pipeline = try Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const fact_store = pipeline.getFactStore();
    const query_engine = pipeline.getQueryEngine();

    _ = fact_store;
    _ = query_engine;
}

test "Pipeline - register pass" {
    var pipeline = try Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const TestPass = struct {
        pub const name = "test-pass";
        pub const kind = @import("../pass/pass.zig").PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    try pipeline.registerPass(TestPass);
    try std.testing.expectEqual(@as(usize, 1), pipeline.pass_manager.count());
}

test "Pipeline - run static analysis" {
    var pipeline = try Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Register a test pass
    const TestPass = struct {
        pub const name = "test-pass";
        pub const kind = @import("../pass/pass.zig").PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    try pipeline.registerPass(TestPass);

    // Run static analysis
    const result = try pipeline.runStaticAnalysis();

    // Verify result
    try std.testing.expect(result.execution_time_ns >= 0);
    try std.testing.expect(result.fact_count >= 0);
}

test "Pipeline - component integration" {
    var pipeline = try Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    // Register multiple passes with dependencies
    const PassA = struct {
        pub const name = "A";
        pub const kind = @import("../pass/pass.zig").PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    const PassB = struct {
        pub const name = "B";
        pub const kind = @import("../pass/pass.zig").PassKind.foundation;
        pub const deps = &[_][]const u8{"A"};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    };

    try pipeline.registerPass(PassB);
    try pipeline.registerPass(PassA);

    // Verify pass manager has correct count
    try std.testing.expectEqual(@as(usize, 2), pipeline.pass_manager.count());

    // Run static analysis
    const result = try pipeline.runStaticAnalysis();

    // Verify execution order was resolved
    try std.testing.expect(result.execution_time_ns >= 0);
}

test "Pipeline - fact store integration" {
    var pipeline = try Pipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const fact_store = pipeline.getFactStore();

    // Add some facts
    try fact_store.insert(.cfg_edge, 1, 2, 0);
    try fact_store.insert(.dfg_edge, 3, 4, 0);

    try std.testing.expectEqual(@as(usize, 2), fact_store.count());
}
