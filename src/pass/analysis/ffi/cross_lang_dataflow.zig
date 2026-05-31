//! Cross-Language Data Flow Tracker
//!
//! Tracks pointer/data flow across FFI boundaries to detect:
//! 1. Orphan pointers - allocated but never freed or passed to another language
//! 2. Double-free paths - same pointer has multiple free paths across languages
//!
//! This module uses CrossLangEdge from pass_types.zig to identify FFI crossings
//! and reports issues using IssueKind.cross_language_leak and IssueKind.double_free.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../../ir/llvm_safe.zig");
const log = @import("../../../common/log.zig");
const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;
const CrossLangEdge = @import("../../../types/pass_types.zig").CrossLangEdge;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const IssueSeverity = @import("../../../diag/issue.zig").Severity;
const Location = @import("../../../diag/issue.zig").Location;
const Language = @import("../../../diag/issue.zig").FFIBoundary.Language;
const ffi_contract_db = @import("../../../resource/ffi_contract_db.zig");
const allocator_shim = @import("../../../detectors/allocator_shim.zig");
const rust_whitelist = @import("../../../whitelists/rust_internal.zig");
const escape_analysis = @import("../../../analysis/escape_analysis.zig");
const raii_detector = @import("../../../analysis/raii_detector.zig");

/// Statistics for cross-language data flow analysis
pub const DataFlowStats = struct {
    /// Number of allocations tracked
    alloc_count: u32 = 0,
    /// Number of allocations that cross FFI boundaries
    cross_lang_allocs: u32 = 0,
    /// Number of orphan pointers detected
    orphan_pointers: u32 = 0,
    /// Number of double-free paths detected
    double_free_paths: u32 = 0,
};

/// Represents a pointer allocation that may cross FFI boundaries
pub const CrossLangAlloc = struct {
    /// Unique identifier for the allocation
    id: u32,
    /// Pointer value (LLVM value reference as integer)
    ptr_val: u64,
    /// Language where allocation occurred
    alloc_lang: Language,
    /// Function that performed the allocation
    alloc_func: []const u8,
    /// Callee function that performed the allocation (e.g., malloc, into_raw)
    alloc_callee: []const u8,
    /// Whether this allocation has been freed
    freed: bool = false,
    /// Languages where this pointer has been freed
    free_langs: std.ArrayList(Language),
    /// Functions that freed this pointer
    free_funcs: std.ArrayList([]const u8),
    /// Whether this pointer has been passed to another language
    passed_to_other_lang: bool = false,
    /// Languages this pointer has been passed to
    passed_langs: std.ArrayList(Language),
};

/// Tracks cross-language data flow across FFI boundaries
pub const CrossLangDataFlow = struct {
    pub const name = "cross-lang-dataflow";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "ffi-boundary", "pointer-flow" };

    /// Run the cross-language data flow analysis
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        var contract_db = ffi_contract_db.FFIContractDB.init(ctx.allocator) catch |err| {
            log.warn("CrossLangDataFlow: Failed to init FFIContractDB: {}", .{err});
            return;
        };
        defer contract_db.deinit();

        var esc_analysis = escape_analysis.EscapeAnalysis.init(ctx.allocator);
        defer esc_analysis.deinit();

        var raii = raii_detector.RAIIDetector.init(ctx.allocator) catch |err| {
            log.warn("CrossLangDataFlow: Failed to init RAIIDetector: {}", .{err});
            return;
        };
        defer raii.deinit();

        var stats = DataFlowStats{};
        var allocations = try std.ArrayList(CrossLangAlloc).initCapacity(ctx.allocator, 64);
        defer {
            for (allocations.items) |*alloc| {
                alloc.free_langs.deinit(ctx.allocator);
                alloc.free_funcs.deinit(ctx.allocator);
                alloc.passed_langs.deinit(ctx.allocator);
            }
            allocations.deinit(ctx.allocator);
        }

        const cross_edges = ctx.getCrossLangEdges();
        if (cross_edges.len == 0) {
            diag.info("CrossLangDataFlow: No cross-language edges found, skipping analysis", .{});
            return;
        }

        try analyzeModuleUnified(ctx, &allocations, cross_edges, &stats, diag, &contract_db, &esc_analysis, &raii);

        try detectDoubleFreePaths(ctx, &allocations, &stats, diag);

        // Print FFI Contract DB statistics
        contract_db.printStats();

        diag.info("CrossLangDataFlow: {} allocations tracked, {} cross-lang, {} orphans, {} double-frees", .{
            stats.alloc_count,
            stats.cross_lang_allocs,
            stats.orphan_pointers,
            stats.double_free_paths,
        });
    }

    /// Unified module analysis - single traversal collecting all data
    /// Replaces: trackAllocations + trackFrees + trackPointerPassing + detectOrphanPointers + detectUseAfterFreeAcrossBoundary
    fn analyzeModuleUnified(
        ctx: *PassContext,
        allocations: *std.ArrayList(CrossLangAlloc),
        cross_edges: []const CrossLangEdge,
        stats: *DataFlowStats,
        diag: *DiagnosticWriter,
        db: *ffi_contract_db.FFIContractDB,
        esc_analysis: *escape_analysis.EscapeAnalysis,
        raii: *raii_detector.RAIIDetector,
    ) !void {
        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;

        var next_id: u32 = 1;

        // Build HashMap indices for O(1) lookups
        var alloc_by_ptr = std.AutoHashMap(u64, usize).init(ctx.allocator);
        defer alloc_by_ptr.deinit();

        var edge_map = std.StringHashMap(CrossLangEdge).init(ctx.allocator);
        defer edge_map.deinit();
        for (cross_edges) |edge| {
            if (edge.is_ffi_boundary) {
                try edge_map.put(edge.callee_name, edge);
            }
        }

        var funcs_with_frees = std.StringHashMap(void).init(ctx.allocator);
        defer funcs_with_frees.deinit();

        var freed_alloc_by_ptr = std.AutoHashMap(u64, usize).init(ctx.allocator);
        defer freed_alloc_by_ptr.deinit();

        // Single traversal - collect all data
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;

            const func_name_ptr = c.LLVMGetValueName(func);
            const func_name = if (@intFromPtr(func_name_ptr) != 0)
                std.mem.span(func_name_ptr)
            else
                "unknown";

            const func_lang = ctx.getModuleLanguage().language;

            // Per-function store→load map for free tracking
            var store_map = std.AutoHashMap(u64, u64).init(ctx.allocator);
            defer store_map.deinit();

            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const opcode = c.LLVMGetInstructionOpcode(inst);

                    // Track store→load chains for free matching
                    if (opcode == c.LLVMStore) {
                        const stored_val = c.LLVMGetOperand(inst, 0);
                        const store_addr = c.LLVMGetOperand(inst, 1);
                        if (@intFromPtr(stored_val) != 0 and @intFromPtr(store_addr) != 0) {
                            const stored_val_int = @intFromPtr(stored_val);
                            if (alloc_by_ptr.contains(stored_val_int)) {
                                store_map.put(@intFromPtr(store_addr), stored_val_int) catch {};
                            }
                        }
                    }

                    // Process call/invoke instructions
                    if (llvm_safe.isCallOrInvoke(opcode)) {
                        const called_val = c.LLVMGetCalledValue(inst);
                        if (@intFromPtr(called_val) == 0) continue;

                        const called_name_ptr = c.LLVMGetValueName(called_val);
                        const called_name = if (@intFromPtr(called_name_ptr) != 0)
                            std.mem.span(called_name_ptr)
                        else
                            "";

                        // 1. Track allocations
                        if (isAllocationFunction(called_name)) {
                            const result_val = @intFromPtr(inst);
                            if (result_val != 0) {
                                const alloc_lang = classifyAllocLanguage(called_name, func_lang);
                                const alloc = CrossLangAlloc{
                                    .id = next_id,
                                    .ptr_val = result_val,
                                    .alloc_lang = alloc_lang,
                                    .alloc_func = func_name,
                                    .alloc_callee = called_name,
                                    .free_langs = try std.ArrayList(Language).initCapacity(ctx.allocator, 2),
                                    .free_funcs = try std.ArrayList([]const u8).initCapacity(ctx.allocator, 2),
                                    .passed_langs = try std.ArrayList(Language).initCapacity(ctx.allocator, 2),
                                };
                                try allocations.append(ctx.allocator, alloc);
                                try alloc_by_ptr.put(result_val, allocations.items.len - 1);
                                stats.alloc_count += 1;
                                next_id += 1;
                            }
                        }

                        // 2. Track frees
                        if (isFreeFunction(called_name)) {
                            try funcs_with_frees.put(func_name, {});

                            const num_operands = c.LLVMGetNumOperands(inst);
                            if (num_operands >= 2) {
                                const ptr_arg = c.LLVMGetOperand(inst, 1);
                                var ptr_val = @intFromPtr(ptr_arg);
                                if (ptr_val != 0) {
                                    // Resolve through store→load chain
                                    if (store_map.get(ptr_val)) |original_val| {
                                        ptr_val = original_val;
                                    }

                                    if (alloc_by_ptr.get(ptr_val)) |idx| {
                                        const alloc = &allocations.items[idx];
                                        if (!alloc.freed) {
                                            const free_lang = classifyFreeLanguage(called_name, .unknown);
                                            try alloc.free_langs.append(ctx.allocator, free_lang);
                                            try alloc.free_funcs.append(ctx.allocator, try ctx.allocator.dupe(u8, called_name));
                                            alloc.freed = true;
                                            try freed_alloc_by_ptr.put(ptr_val, idx);
                                        }
                                    }
                                }
                            }
                        }

                        // 3. Track pointer passing across FFI
                        if (edge_map.get(called_name)) |edge| {
                            const num_operands = c.LLVMGetNumOperands(inst);
                            var arg_idx: u32 = 0;
                            while (arg_idx < num_operands) : (arg_idx += 1) {
                                const arg = c.LLVMGetOperand(inst, arg_idx);
                                const arg_val = @intFromPtr(arg);
                                if (arg_val == 0) continue;

                                if (alloc_by_ptr.get(arg_val)) |idx| {
                                    const alloc = &allocations.items[idx];
                                    alloc.passed_to_other_lang = true;
                                    try alloc.passed_langs.append(ctx.allocator, edge.callee_lang);
                                    break;
                                }
                            }
                        }

                        // 4. Detect use-after-free across FFI (inline)
                        const num_operands = c.LLVMGetNumOperands(inst);
                        var arg_idx: u32 = 0;
                        while (arg_idx < num_operands) : (arg_idx += 1) {
                            const arg = c.LLVMGetOperand(inst, arg_idx);
                            const arg_val = @intFromPtr(arg);
                            if (arg_val == 0) continue;

                            if (freed_alloc_by_ptr.get(arg_val)) |idx| {
                                const alloc = &allocations.items[idx];
                                var use_lang = func_lang;

                                if (edge_map.get(called_name)) |edge| {
                                    use_lang = edge.callee_lang;
                                }

                                for (alloc.free_langs.items) |free_lang| {
                                    if (free_lang != use_lang and free_lang != .unknown and use_lang != .unknown) {
                                        const message = try std.fmt.allocPrint(ctx.allocator, "Use-after-free across FFI boundary: pointer freed in {s} used in {s} in function {s}", .{ @tagName(free_lang), @tagName(use_lang), func_name });
                                        defer ctx.allocator.free(message);

                                        const location = Location.init(func_name);
                                        const issue = Issue.init(
                                            .use_after_free,
                                            message,
                                            location,
                                            .critical,
                                            0.95,
                                        );
                                        try ctx.addIssue(&issue);

                                        diag.err("CrossLangDataFlow: Use-after-free across boundary: ptr {} freed in {s} used in {s} in {s}", .{
                                            alloc.id,
                                            @tagName(free_lang),
                                            @tagName(use_lang),
                                            func_name,
                                        });
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 5. Detect orphan pointers (post-processing)
        // FFI Contract DB integration: suppress FP for GC-managed and
        // callee-owned resources; detect alloc/release mismatches.
        for (allocations.items) |alloc| {
            if (alloc.freed) continue;
            if (alloc.passed_to_other_lang) continue;

            // ── ALLOCATOR SHIM SUPPRESSION ──
            // Suppress false positives from allocator vtable functions
            // (mimalloc, jemalloc, system allocators, Rust GlobalAlloc)
            if (allocator_shim.AllocatorShimDetector.isAllocatorShim(alloc.alloc_callee) == .confirmed_shim) {
                log.debug("ALLOCATOR-SHIM-SUPPRESS: {s} is allocator vtable, not a leak", .{
                    alloc.alloc_callee,
                });
                continue;
            }

            // ── RUST INTERNAL WHITELIST SUPPRESSION ──
            // Skip Rust panic/unwind/formatting internals that never return normally
            if (rust_whitelist.RustInternalWhitelist.shouldSkipAnalysis(alloc.alloc_func)) {
                log.debug("RUST-INTERNAL-SKIP: {s} is Rust internal, skipping", .{
                    alloc.alloc_func,
                });
                continue;
            }

            if (funcs_with_frees.contains(alloc.alloc_func)) {
                diag.info("CrossLangDataFlow: Suppressing orphan for {s} in {s} — function calls a free function", .{ alloc.alloc_callee, alloc.alloc_func });
                continue;
            }

            // CONTRACT-DB: Check if this allocation should be reported as leak
            if (!db.shouldReportLeak(alloc.alloc_callee)) {
                const ownership = db.getOwnership(alloc.alloc_callee);
                log.debug("CONTRACT-SUPPRESS: {s} is {s}-managed in {s}, not a leak", .{
                    alloc.alloc_callee,
                    if (ownership) |o| @tagName(o) else "unknown",
                    alloc.alloc_func,
                });
                continue;
            }

            // ── ESCAPE ANALYSIS CHECK ──
            if (esc_analysis.shouldSuppressLeakReport(alloc.ptr_val)) {
                log.debug("ESCAPE-SUPPRESS: Non-escaping alloc 0x{x} (safe)", .{alloc.ptr_val});
                continue;
            }

            // ── RAII CHECK ──
            if (raii.shouldSuppressLeakDueToRAII(&alloc)) {
                log.debug("RAII-SUPPRESS: RAII-managed alloc 0x{x} (auto-cleanup)", .{alloc.ptr_val});
                continue;
            }

            // CONTRACT-DB: If we have free func info, check for pairing mismatch
            if (alloc.free_funcs.items.len > 0) {
                for (alloc.free_funcs.items) |free_func| {
                    const pair_result = db.isValidRelease(alloc.alloc_callee, free_func);
                    if (pair_result == .mismatch) {
                        const expected_releases = db.getExpectedReleases(alloc.alloc_callee);

                        // Build expected releases string for display
                        var expected_buf: [256]u8 = undefined;
                        var expected_fbs = std.io.fixedBufferStream(&expected_buf);
                        const expected_writer = expected_fbs.writer();
                        if (expected_releases) |releases| {
                            for (releases, 0..) |r, i| {
                                if (i > 0) expected_writer.writeAll(", ") catch {};
                                expected_writer.writeAll(r) catch {};
                            }
                        } else {
                            expected_writer.writeAll("unknown") catch {};
                        }

                        const mismatch_msg = try std.fmt.allocPrint(ctx.allocator, "FFI contract mismatch: {s} allocated by {s} but released by {s}. Expected release function(s): {s}", .{ alloc.alloc_func, alloc.alloc_callee, free_func, expected_fbs.getWritten() });
                        defer ctx.allocator.free(mismatch_msg);

                        const location = Location.init(alloc.alloc_func);

                        // Use dedicated contract_mismatch issue kind with high confidence
                        var confidence: f32 = 0.90;

                        // Boost confidence for error-prone libraries (OpenSSL, SQLite)
                        if (db.isErrorProneLib(alloc.alloc_callee)) {
                            confidence = @min(confidence + 0.08, 1.0);
                            log.debug("CONTRACT-BOOST: {s} is error-prone, boosting confidence to {d:.2}", .{
                                alloc.alloc_callee,
                                confidence,
                            });
                        }

                        const issue = Issue.init(
                            .contract_mismatch,
                            mismatch_msg,
                            location,
                            .high,
                            confidence,
                        );
                        try ctx.addIssue(&issue);

                        diag.err("CrossLangDataFlow: CONTRACT-MISMATCH — {s} allocated in {s} but freed by {s} (expected: {s}, confidence: {d:.2})", .{
                            alloc.alloc_callee,
                            alloc.alloc_func,
                            free_func,
                            expected_fbs.getWritten(),
                            confidence,
                        });
                    }
                }
            }

            stats.orphan_pointers += 1;

            // CONTRACT-DB: Check if this is a GC-managed object (suppress leak report)
            if (db.getOwnership(alloc.alloc_callee) == .gc) {
                log.debug("CONTRACT-SUPPRESS-GC: {s} is GC-managed in {s}, suppressing leak report", .{
                    alloc.alloc_callee,
                    alloc.alloc_func,
                });

                // Optionally emit a diagnostic-level message instead of an issue
                diag.info("CrossLangDataFlow: Suppressing leak for GC-managed object: {s} in {s}", .{
                    alloc.alloc_callee,
                    alloc.alloc_func,
                });

                // Skip to next allocation - don't generate issue for GC objects
                continue;
            }

            // Boost confidence for error-prone libraries (OpenSSL, SQLite)
            var confidence = calculateOrphanConfidence(alloc);
            if (db.isErrorProneLib(alloc.alloc_callee)) {
                confidence = @min(confidence + 0.08, 1.0);
                log.debug("CONTRACT-BOOST: {s} is error-prone, boosting orphan confidence to {d:.2}", .{
                    alloc.alloc_callee,
                    confidence,
                });
            }

            const message = try std.fmt.allocPrint(ctx.allocator, "Orphan pointer detected: allocated in {s} ({s}) via {s} but never freed or transferred across FFI boundary", .{ alloc.alloc_func, @tagName(alloc.alloc_lang), alloc.alloc_callee });
            defer ctx.allocator.free(message);

            const location = Location.init(alloc.alloc_func);
            const issue = Issue.init(
                .cross_language_leak,
                message,
                location,
                .high,
                confidence,
            );
            try ctx.addIssue(&issue);

            diag.warn("CrossLangDataFlow: Orphan pointer {} in {s} ({s}) (confidence: {d:.2})", .{
                alloc.id,
                alloc.alloc_func,
                @tagName(alloc.alloc_lang),
                confidence,
            });
        }

        // Update cross-lang stats
        for (allocations.items) |alloc| {
            if (alloc.passed_to_other_lang or alloc.free_langs.items.len > 0) {
                stats.cross_lang_allocs += 1;
            }
        }
    }

    /// Track allocations that may cross FFI boundaries
    fn trackAllocations(
        ctx: *PassContext,
        allocations: *std.ArrayList(CrossLangAlloc),
        stats: *DataFlowStats,
        diag: *DiagnosticWriter,
    ) !void {
        _ = diag;
        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;

        var next_id: u32 = 1;

        // Scan all functions for allocation calls
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;

            const func_name_ptr = c.LLVMGetValueName(func);
            const func_name = if (@intFromPtr(func_name_ptr) != 0)
                std.mem.span(func_name_ptr)
            else
                "unknown";

            // Get function language
            const func_lang = ctx.getModuleLanguage().language;

            // Scan instructions in this function
            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const opcode = c.LLVMGetInstructionOpcode(inst);
                    if (llvm_safe.isCallOrInvoke(opcode)) {
                        const called_val = c.LLVMGetCalledValue(inst);
                        if (@intFromPtr(called_val) == 0) continue;

                        const called_name_ptr = c.LLVMGetValueName(called_val);
                        const called_name = if (@intFromPtr(called_name_ptr) != 0)
                            std.mem.span(called_name_ptr)
                        else
                            "";

                        // Check if this is an allocation function
                        if (isAllocationFunction(called_name)) {
                            // Get the result pointer value
                            const result_val = @intFromPtr(inst);
                            if (result_val == 0) continue;

                            // Determine allocation language based on function name
                            const alloc_lang = classifyAllocLanguage(called_name, func_lang);

                            // Create allocation record
                            const alloc = CrossLangAlloc{
                                .id = next_id,
                                .ptr_val = result_val,
                                .alloc_lang = alloc_lang,
                                .alloc_func = func_name,
                                .alloc_callee = called_name,
                                .free_langs = std.ArrayList(Language).initCapacity(ctx.allocator, 0) catch return error.OutOfMemory,
                                .free_funcs = std.ArrayList([]const u8).initCapacity(ctx.allocator, 0) catch return error.OutOfMemory,
                                .passed_langs = std.ArrayList(Language).initCapacity(ctx.allocator, 0) catch return error.OutOfMemory,
                            };

                            try allocations.append(ctx.allocator, alloc);
                            stats.alloc_count += 1;
                            next_id += 1;

                            // Check if allocation language differs from function language
                            if (alloc_lang != func_lang and alloc_lang != .unknown) {
                                stats.cross_lang_allocs += 1;
                            }
                        }
                    }
                }
            }
        }
    }

    /// Track frees and match them with allocations.
    /// Uses store→load resolution to match pointers that flow through memory.
    fn trackFrees(
        ctx: *PassContext,
        allocations: *std.ArrayList(CrossLangAlloc),
        stats: *DataFlowStats,
        diag: *DiagnosticWriter,
    ) !void {
        _ = stats;
        _ = diag;
        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;

        // Build a set of tracked allocation pointer values for O(1) lookup
        var tracked_ptrs = std.AutoHashMap(u64, usize).init(ctx.allocator);
        defer tracked_ptrs.deinit();
        for (allocations.items, 0..) |alloc, idx| {
            try tracked_ptrs.put(alloc.ptr_val, idx);
        }

        // Scan all functions for free calls, with store→load resolution
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;

            // Per-function store→load map: address → stored value (only for tracked ptrs)
            var store_map = std.AutoHashMap(u64, u64).init(ctx.allocator);
            defer store_map.deinit();

            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const opcode = c.LLVMGetInstructionOpcode(inst);

                    // Track store → load chains for tracked pointers
                    if (opcode == c.LLVMStore) {
                        const stored_val = c.LLVMGetOperand(inst, 0);
                        const store_addr = c.LLVMGetOperand(inst, 1);
                        if (@intFromPtr(stored_val) != 0 and @intFromPtr(store_addr) != 0) {
                            const stored_val_int = @intFromPtr(stored_val);
                            if (tracked_ptrs.contains(stored_val_int)) {
                                store_map.put(@intFromPtr(store_addr), stored_val_int) catch {};
                            }
                        }
                    }

                    if (llvm_safe.isCallOrInvoke(opcode)) {
                        const called_val = c.LLVMGetCalledValue(inst);
                        if (@intFromPtr(called_val) == 0) continue;

                        const called_name_ptr = c.LLVMGetValueName(called_val);
                        const called_name = if (@intFromPtr(called_name_ptr) != 0)
                            std.mem.span(called_name_ptr)
                        else
                            "";

                        // Check if this is a free function
                        if (isFreeFunction(called_name)) {
                            // LLVMGetNumOperands includes callee. Operand layout: [callee, arg0, arg1, ...]
                            // First argument (pointer to free) is at index 1.
                            const num_operands = c.LLVMGetNumOperands(inst);
                            if (num_operands < 2) continue;

                            const ptr_arg = c.LLVMGetOperand(inst, 1);
                            var ptr_val = @intFromPtr(ptr_arg);
                            if (ptr_val == 0) continue;

                            // Resolve through store→load chain
                            if (store_map.get(ptr_val)) |original_val| {
                                ptr_val = original_val;
                            }

                            // Find matching allocation
                            if (tracked_ptrs.get(ptr_val)) |idx| {
                                const alloc = &allocations.items[idx];
                                if (!alloc.freed) {
                                    const free_lang = classifyFreeLanguage(called_name, .unknown);
                                    try alloc.free_langs.append(ctx.allocator, free_lang);
                                    try alloc.free_funcs.append(ctx.allocator, try ctx.allocator.dupe(u8, called_name));
                                    alloc.freed = true;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Track pointers being passed across FFI boundaries
    fn trackPointerPassing(
        ctx: *PassContext,
        allocations: *std.ArrayList(CrossLangAlloc),
        cross_edges: []const CrossLangEdge,
        stats: *DataFlowStats,
        diag: *DiagnosticWriter,
    ) !void {
        _ = stats;
        _ = diag;
        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;

        // Build HashMap index for O(1) allocation lookup by pointer value
        var alloc_by_ptr = std.AutoHashMap(u64, usize).init(ctx.allocator);
        defer alloc_by_ptr.deinit();
        for (allocations.items, 0..) |alloc, idx| {
            try alloc_by_ptr.put(alloc.ptr_val, idx);
        }

        // Build HashMap index for O(1) FFI edge lookup by callee name
        var edge_map = std.StringHashMap(CrossLangEdge).init(ctx.allocator);
        defer edge_map.deinit();
        for (cross_edges) |edge| {
            if (edge.is_ffi_boundary) {
                try edge_map.put(edge.callee_name, edge);
            }
        }

        // Scan all functions for calls that pass pointers across FFI boundaries
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;

            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const opcode = c.LLVMGetInstructionOpcode(inst);
                    if (llvm_safe.isCallOrInvoke(opcode)) {
                        const called_val = c.LLVMGetCalledValue(inst);
                        if (@intFromPtr(called_val) == 0) continue;

                        const called_name_ptr = c.LLVMGetValueName(called_val);
                        const called_name = if (@intFromPtr(called_name_ptr) != 0)
                            std.mem.span(called_name_ptr)
                        else
                            "";

                        // O(1) lookup: check if this call crosses FFI boundary
                        const edge = edge_map.get(called_name) orelse continue;
                        const callee_lang = edge.callee_lang;

                        // Check if any arguments are tracked pointers
                        const num_operands = c.LLVMGetNumOperands(inst);
                        var arg_idx: u32 = 0;
                        while (arg_idx < num_operands) : (arg_idx += 1) {
                            const arg = c.LLVMGetOperand(inst, arg_idx);
                            const arg_val = @intFromPtr(arg);
                            if (arg_val == 0) continue;

                            // O(1) lookup: check if this argument is a tracked allocation
                            if (alloc_by_ptr.get(arg_val)) |idx| {
                                const alloc = &allocations.items[idx];
                                alloc.passed_to_other_lang = true;
                                try alloc.passed_langs.append(ctx.allocator, callee_lang);
                                break;
                            }
                        }
                    }
                }
            }
        }
    }

    /// Detect orphan pointers (allocated but never freed or passed to another language)
    fn detectOrphanPointers(
        ctx: *PassContext,
        allocations: *std.ArrayList(CrossLangAlloc),
        stats: *DataFlowStats,
        diag: *DiagnosticWriter,
    ) !void {
        // Build a set of functions that call free functions.
        // This is used to suppress orphan reports for functions that DO call
        // a free function but the pointer matching failed (e.g., due to
        // store→load cycles or LLVM value identity issues).
        var funcs_with_frees = std.StringHashMap(void).init(ctx.allocator);
        defer funcs_with_frees.deinit();
        {
            const mod = ctx.module.?.raw;
            var func = c.LLVMGetFirstFunction(mod);
            while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
                if (c.LLVMIsDeclaration(func) != 0) continue;
                const func_name_ptr = c.LLVMGetValueName(func);
                const func_name = if (@intFromPtr(func_name_ptr) != 0) std.mem.span(func_name_ptr) else continue;

                var bb = c.LLVMGetFirstBasicBlock(func);
                while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                    var inst = c.LLVMGetFirstInstruction(bb);
                    while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                        const opcode = c.LLVMGetInstructionOpcode(inst);
                        if (!llvm_safe.isCallOrInvoke(opcode)) continue;
                        const called_val = c.LLVMGetCalledValue(inst) orelse continue;
                        const called_name_ptr = c.LLVMGetValueName(called_val);
                        const called_name = if (@intFromPtr(called_name_ptr) != 0) std.mem.span(called_name_ptr) else continue;
                        if (isFreeFunction(called_name)) {
                            try funcs_with_frees.put(func_name, {});
                            break;
                        }
                    }
                    if (funcs_with_frees.contains(func_name)) break;
                }
            }
        }

        for (allocations.items) |alloc| {
            // Skip if already freed
            if (alloc.freed) continue;

            // Skip if passed to another language (ownership transferred)
            if (alloc.passed_to_other_lang) continue;

            // ── ALLOCATOR SHIM SUPPRESSION ──
            if (allocator_shim.AllocatorShimDetector.isAllocatorShim(alloc.alloc_callee) == .confirmed_shim) {
                log.debug("ALLOCATOR-SHIM-SUPPRESS: {s} is allocator vtable, not a leak", .{
                    alloc.alloc_callee,
                });
                continue;
            }

            // ── RUST INTERNAL WHITELIST SUPPRESSION ──
            if (rust_whitelist.RustInternalWhitelist.shouldSkipAnalysis(alloc.alloc_func)) {
                log.debug("RUST-INTERNAL-SKIP: {s} is Rust internal, skipping", .{
                    alloc.alloc_func,
                });
                continue;
            }

            // Heuristic: if the allocation's function also calls a free function,
            // the allocation is likely correctly paired. The pointer matching may
            // have failed due to store→load cycles or LLVM value identity issues.
            // Suppress the orphan report in this case.
            if (funcs_with_frees.contains(alloc.alloc_func)) {
                diag.info("CrossLangDataFlow: Suppressing orphan for {s} in {s} — function calls a free function", .{ alloc.alloc_callee, alloc.alloc_func });
                continue;
            }

            // This is an orphan pointer - allocated but never freed or transferred
            stats.orphan_pointers += 1;

            // Calculate confidence score
            const confidence = calculateOrphanConfidence(alloc);

            // Create issue message
            const message = try std.fmt.allocPrint(ctx.allocator, "Orphan pointer detected: allocated in {s} ({s}) via {s} but never freed or transferred across FFI boundary", .{ alloc.alloc_func, @tagName(alloc.alloc_lang), alloc.alloc_callee });
            defer ctx.allocator.free(message);

            // Report issue with confidence score
            const location = Location.init(alloc.alloc_func);
            const issue = Issue.init(
                .cross_language_leak,
                message,
                location,
                .medium,
                confidence,
            );
            try ctx.addIssue(&issue);

            diag.warn("CrossLangDataFlow: Orphan pointer {} in {s} ({s}) (confidence: {d:.2})", .{
                alloc.id,
                alloc.alloc_func,
                @tagName(alloc.alloc_lang),
                confidence,
            });
        }
    }

    /// Detect double-free paths (same pointer freed multiple times across languages)
    fn detectDoubleFreePaths(
        ctx: *PassContext,
        allocations: *std.ArrayList(CrossLangAlloc),
        stats: *DataFlowStats,
        diag: *DiagnosticWriter,
    ) !void {
        for (allocations.items) |alloc| {
            // Skip if not freed
            if (!alloc.freed) continue;

            // Check if freed multiple times
            if (alloc.free_langs.items.len <= 1) continue;

            // Check if freed in different languages
            var has_different_langs = false;
            if (alloc.free_langs.items.len >= 2) {
                const first_lang = alloc.free_langs.items[0];
                for (alloc.free_langs.items[1..]) |lang| {
                    if (lang != first_lang) {
                        has_different_langs = true;
                        break;
                    }
                }
            }

            if (!has_different_langs) continue;

            // This is a double-free path across languages
            stats.double_free_paths += 1;

            // Create issue message
            const message = try std.fmt.allocPrint(ctx.allocator, "Double-free path detected: pointer allocated in {s} ({s}) freed in multiple languages ({s})", .{ alloc.alloc_func, @tagName(alloc.alloc_lang), formatLanguages(alloc.free_langs.items) });
            defer ctx.allocator.free(message);

            // Report issue
            const location = Location.init(alloc.alloc_func);
            const issue = Issue.init(
                .double_free,
                message,
                location,
                .high,
                0.9,
            );
            try ctx.addIssue(&issue);

            diag.warn("CrossLangDataFlow: Double-free path {} in {s} ({s}) freed in {s}", .{
                alloc.id,
                alloc.alloc_func,
                @tagName(alloc.alloc_lang),
                formatLanguages(alloc.free_langs.items),
            });
        }
    }

    /// Detect use-after-free across FFI boundaries
    /// This detects when a pointer freed in one language is used in another
    fn detectUseAfterFreeAcrossBoundary(
        ctx: *PassContext,
        allocations: *std.ArrayList(CrossLangAlloc),
        cross_edges: []const CrossLangEdge,
        diag: *DiagnosticWriter,
    ) !void {
        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;

        // Build HashMap index for O(1) allocation lookup by pointer value (only freed ones)
        var freed_alloc_by_ptr = std.AutoHashMap(u64, usize).init(ctx.allocator);
        defer freed_alloc_by_ptr.deinit();
        for (allocations.items, 0..) |alloc, idx| {
            if (alloc.freed) {
                try freed_alloc_by_ptr.put(alloc.ptr_val, idx);
            }
        }

        // Build HashMap index for O(1) FFI edge lookup by callee name
        var edge_map = std.StringHashMap(CrossLangEdge).init(ctx.allocator);
        defer edge_map.deinit();
        for (cross_edges) |edge| {
            if (edge.is_ffi_boundary) {
                try edge_map.put(edge.callee_name, edge);
            }
        }

        // Scan all functions for uses of freed pointers
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;

            const func_name_ptr = c.LLVMGetValueName(func);
            const func_name = if (@intFromPtr(func_name_ptr) != 0)
                std.mem.span(func_name_ptr)
            else
                "unknown";

            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const num_operands = c.LLVMGetNumOperands(inst);
                    var arg_idx: u32 = 0;
                    while (arg_idx < num_operands) : (arg_idx += 1) {
                        const arg = c.LLVMGetOperand(inst, arg_idx);
                        const arg_val = @intFromPtr(arg);
                        if (arg_val == 0) continue;

                        // O(1) lookup: check if this argument is a freed allocation
                        if (freed_alloc_by_ptr.get(arg_val)) |idx| {
                            const alloc = &allocations.items[idx];
                            const func_lang = ctx.getModuleLanguage().language;
                            var use_lang = func_lang;

                            // Check if this call crosses FFI boundary
                            const opcode = c.LLVMGetInstructionOpcode(inst);
                            if (llvm_safe.isCallOrInvoke(opcode)) {
                                const called_val = c.LLVMGetCalledValue(inst);
                                if (@intFromPtr(called_val) != 0) {
                                    const called_name_ptr = c.LLVMGetValueName(called_val);
                                    const called_name = if (@intFromPtr(called_name_ptr) != 0)
                                        std.mem.span(called_name_ptr)
                                    else
                                        "";

                                    // O(1) lookup: check if this crosses FFI boundary
                                    if (edge_map.get(called_name)) |edge| {
                                        use_lang = edge.callee_lang;
                                    }
                                }
                            }

                            // Check if any free was in a different language
                            for (alloc.free_langs.items) |free_lang| {
                                if (free_lang != use_lang and free_lang != .unknown and use_lang != .unknown) {
                                    const message = try std.fmt.allocPrint(ctx.allocator, "Use-after-free across FFI boundary: pointer freed in {s} used in {s} in function {s}", .{ @tagName(free_lang), @tagName(use_lang), func_name });
                                    defer ctx.allocator.free(message);

                                    const location = Location.init(func_name);
                                    const issue = Issue.init(
                                        .use_after_free,
                                        message,
                                        location,
                                        .critical,
                                        0.95,
                                    );
                                    try ctx.addIssue(&issue);

                                    diag.err("CrossLangDataFlow: Use-after-free across boundary: ptr {} freed in {s} used in {s} in {s}", .{
                                        alloc.id,
                                        @tagName(free_lang),
                                        @tagName(use_lang),
                                        func_name,
                                    });
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
};

/// Check if a function is an allocation function
fn isAllocationFunction(func_name: []const u8) bool {
    // Common allocation functions across languages
    const alloc_patterns = [_][]const u8{
        // C allocation
        "malloc",
        "calloc",
        "realloc",
        "aligned_alloc",
        "posix_memalign",
        "mmap",
        "malloc_usable_size",
        // Rust allocation
        "into_raw",
        "Box::into_raw",
        "alloc::alloc",
        "__rust_alloc",
        // Zig allocation
        "Allocator.alloc",
        "heap_alloc",
        // C++ allocation (mangled names and operator new)
        "_Znwm",
        "_Znam",
        "new[]",
        "operator new",
        // Python allocation
        "PyMem_Malloc",
        "PyMem_New",
        "PyMem_Realloc",
        "PyMem_Calloc",
        "PyObject_Malloc",
        "PyObject_New",
        // Java/JNI allocation
        "JNI_Malloc",
        "GetByteArrayElements",
        "GetCharArrayElements",
        "GetShortArrayElements",
        "GetIntArrayElements",
        "GetLongArrayElements",
        "GetFloatArrayElements",
        "GetDoubleArrayElements",
        "GetObjectArrayElements",
        "NewByteArray",
        "NewCharArray",
        "NewShortArray",
        "NewIntArray",
        "NewLongArray",
        "NewFloatArray",
        "NewDoubleArray",
        "NewObjectArray",
    };

    for (alloc_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if a function is a free function
fn isFreeFunction(func_name: []const u8) bool {
    // Common free functions across languages
    const free_patterns = [_][]const u8{
        // C deallocation
        "free",
        "munmap",
        // Rust deallocation
        "from_raw",
        "Box::from_raw",
        "drop",
        "drop_in_place",
        "__rust_dealloc",
        // Rust refcount release
        "arc_release",
        "rc_release",
        "_release",
        // Zig deallocation
        "Allocator.free",
        "heap_free",
        // C++ deallocation
        "delete",
        "delete[]",
        "operator delete",
        // Python deallocation
        "PyMem_Free",
        "PyMem_Del",
        "PyMem_Realloc",
        "PyObject_Free",
        "PyObject_Del",
        "Py_DECREF",
        "Py_XDECREF",
        // Java/JNI deallocation
        "JNI_Free",
        "ReleaseByteArrayElements",
        "ReleaseCharArrayElements",
        "ReleaseShortArrayElements",
        "ReleaseIntArrayElements",
        "ReleaseLongArrayElements",
        "ReleaseFloatArrayElements",
        "ReleaseDoubleArrayElements",
        "ReleaseObjectArrayElements",
        "DeleteLocalRef",
        "DeleteGlobalRef",
        "DeleteWeakGlobalRef",
    };

    for (free_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Classify the language of an allocation based on function name
fn classifyAllocLanguage(callee_name: []const u8, caller_lang: Language) Language {
    // Rust allocation patterns
    if (std.mem.indexOf(u8, callee_name, "into_raw") != null or
        std.mem.indexOf(u8, callee_name, "Box::into_raw") != null or
        std.mem.indexOf(u8, callee_name, "__rust_alloc") != null)
    {
        return .rust;
    }

    // Zig allocation patterns
    if (std.mem.indexOf(u8, callee_name, "Allocator.alloc") != null or
        std.mem.indexOf(u8, callee_name, "heap_alloc") != null)
    {
        return .zig;
    }

    // C++ allocation patterns (mangled names and operator new)
    if (std.mem.indexOf(u8, callee_name, "_Znwm") != null or
        std.mem.indexOf(u8, callee_name, "_Znam") != null or
        std.mem.indexOf(u8, callee_name, "operator new") != null)
    {
        return .cpp;
    }

    // Python allocation patterns
    if (std.mem.indexOf(u8, callee_name, "PyMem_") != null or
        std.mem.indexOf(u8, callee_name, "PyObject_") != null or
        std.mem.indexOf(u8, callee_name, "Py_") != null)
    {
        return .python;
    }

    // Java/JNI allocation patterns
    if (std.mem.indexOf(u8, callee_name, "JNI_") != null or
        std.mem.indexOf(u8, callee_name, "Get") != null or
        std.mem.indexOf(u8, callee_name, "New") != null)
    {
        return .java;
    }

    // C allocation patterns (malloc, calloc, etc.)
    if (std.mem.indexOf(u8, callee_name, "malloc") != null or
        std.mem.indexOf(u8, callee_name, "calloc") != null or
        std.mem.indexOf(u8, callee_name, "realloc") != null)
    {
        return .c;
    }

    // Default to caller language if unknown
    return caller_lang;
}

/// Classify the language of a free based on function name
fn classifyFreeLanguage(callee_name: []const u8, caller_lang: Language) Language {
    // Rust deallocation patterns
    if (std.mem.indexOf(u8, callee_name, "from_raw") != null or
        std.mem.indexOf(u8, callee_name, "Box::from_raw") != null or
        std.mem.indexOf(u8, callee_name, "drop") != null or
        std.mem.indexOf(u8, callee_name, "__rust_dealloc") != null)
    {
        return .rust;
    }

    // Zig deallocation patterns
    if (std.mem.indexOf(u8, callee_name, "Allocator.free") != null or
        std.mem.indexOf(u8, callee_name, "heap_free") != null)
    {
        return .zig;
    }

    // C++ deallocation patterns
    if (std.mem.indexOf(u8, callee_name, "delete") != null or
        std.mem.indexOf(u8, callee_name, "operator delete") != null)
    {
        return .cpp;
    }

    // Python deallocation patterns
    if (std.mem.indexOf(u8, callee_name, "PyMem_") != null or
        std.mem.indexOf(u8, callee_name, "PyObject_") != null or
        std.mem.indexOf(u8, callee_name, "Py_DECREF") != null or
        std.mem.indexOf(u8, callee_name, "Py_XDECREF") != null)
    {
        return .python;
    }

    // Java/JNI deallocation patterns
    if (std.mem.indexOf(u8, callee_name, "JNI_") != null or
        std.mem.indexOf(u8, callee_name, "Release") != null or
        std.mem.indexOf(u8, callee_name, "Delete") != null)
    {
        return .java;
    }

    // C deallocation patterns (free, munmap)
    if (std.mem.indexOf(u8, callee_name, "free") != null or
        std.mem.indexOf(u8, callee_name, "munmap") != null)
    {
        return .c;
    }

    // Default to caller language if unknown
    return caller_lang;
}

/// Format a list of languages for display
fn formatLanguages(languages: []const Language) []const u8 {
    // Simple formatting - in real implementation would need to allocate string
    if (languages.len == 0) return "unknown";
    if (languages.len == 1) return @tagName(languages[0]);
    return "multiple languages";
}

/// Check if a function is a known allocation function (for confidence scoring)
fn isKnownAllocFunction(func_name: []const u8) bool {
    const known_alloc_funcs = [_][]const u8{
        "malloc",
        "calloc",
        "realloc",
        "into_raw",
        "__rust_alloc",
        "Allocator.alloc",
        "PyMem_Malloc",
        "PyMem_New",
        "JNI_Malloc",
        "GetByteArrayElements",
    };

    for (known_alloc_funcs) |known_func| {
        if (std.mem.eql(u8, func_name, known_func)) {
            return true;
        }
    }
    return false;
}

/// Calculate confidence score for orphan pointer detection
/// Higher confidence for local variables, lower for globals
fn calculateOrphanConfidence(alloc: CrossLangAlloc) f32 {
    var confidence: f32 = 0.8; // Base confidence

    // Higher confidence if pointer is from a known allocation function
    if (isKnownAllocFunction(alloc.alloc_callee)) {
        confidence += 0.1;
    }

    // Higher confidence if allocation language is known
    if (alloc.alloc_lang != .unknown) {
        confidence += 0.05;
    }

    // Lower confidence if pointer value looks like a global (higher addresses)
    if (alloc.ptr_val > 0x7FFFFFFFFFFF) {
        confidence -= 0.2;
    }

    // Clamp confidence to [0.0, 1.0]
    return std.math.clamp(confidence, 0.0, 1.0);
}

// ============================================================================
// Tests
// ============================================================================

test "isAllocationFunction detects common allocators" {
    try std.testing.expect(isAllocationFunction("malloc"));
    try std.testing.expect(isAllocationFunction("calloc"));
    try std.testing.expect(isAllocationFunction("realloc"));
    try std.testing.expect(isAllocationFunction("into_raw"));
    try std.testing.expect(isAllocationFunction("Box::into_raw"));
    try std.testing.expect(isAllocationFunction("__rust_alloc"));
    try std.testing.expect(isAllocationFunction("Allocator.alloc"));
    try std.testing.expect(isAllocationFunction("new"));
    try std.testing.expect(isAllocationFunction("operator new"));

    // Should not detect non-allocators
    try std.testing.expect(!isAllocationFunction("free"));
    try std.testing.expect(!isAllocationFunction("printf"));
    try std.testing.expect(!isAllocationFunction("strlen"));
}

test "isFreeFunction detects common deallocators" {
    try std.testing.expect(isFreeFunction("free"));
    try std.testing.expect(isFreeFunction("munmap"));
    try std.testing.expect(isFreeFunction("from_raw"));
    try std.testing.expect(isFreeFunction("Box::from_raw"));
    try std.testing.expect(isFreeFunction("drop"));
    try std.testing.expect(isFreeFunction("drop_in_place"));
    try std.testing.expect(isFreeFunction("__rust_dealloc"));
    try std.testing.expect(isFreeFunction("Allocator.free"));
    try std.testing.expect(isFreeFunction("delete"));
    try std.testing.expect(isFreeFunction("operator delete"));

    // Should not detect non-deallocators
    try std.testing.expect(!isFreeFunction("malloc"));
    try std.testing.expect(!isFreeFunction("printf"));
    try std.testing.expect(!isFreeFunction("strlen"));
}

test "classifyAllocLanguage correctly identifies Rust allocations" {
    try std.testing.expect(classifyAllocLanguage("into_raw", .c) == .rust);
    try std.testing.expect(classifyAllocLanguage("Box::into_raw", .c) == .rust);
    try std.testing.expect(classifyAllocLanguage("__rust_alloc", .c) == .rust);
    try std.testing.expect(classifyAllocLanguage("alloc::alloc", .c) == .rust);
}

test "classifyAllocLanguage correctly identifies Zig allocations" {
    try std.testing.expect(classifyAllocLanguage("Allocator.alloc", .c) == .zig);
    try std.testing.expect(classifyAllocLanguage("heap_alloc", .c) == .zig);
}

test "classifyAllocLanguage correctly identifies C++ allocations" {
    try std.testing.expect(classifyAllocLanguage("new", .c) == .cpp);
    try std.testing.expect(classifyAllocLanguage("new[]", .c) == .cpp);
    try std.testing.expect(classifyAllocLanguage("operator new", .c) == .cpp);
}

test "classifyAllocLanguage correctly identifies C allocations" {
    try std.testing.expect(classifyAllocLanguage("malloc", .rust) == .c);
    try std.testing.expect(classifyAllocLanguage("calloc", .rust) == .c);
    try std.testing.expect(classifyAllocLanguage("realloc", .rust) == .c);
}

test "classifyFreeLanguage correctly identifies Rust deallocators" {
    try std.testing.expect(classifyFreeLanguage("from_raw", .c) == .rust);
    try std.testing.expect(classifyFreeLanguage("Box::from_raw", .c) == .rust);
    try std.testing.expect(classifyFreeLanguage("drop", .c) == .rust);
    try std.testing.expect(classifyFreeLanguage("drop_in_place", .c) == .rust);
    try std.testing.expect(classifyFreeLanguage("__rust_dealloc", .c) == .rust);
}

test "classifyFreeLanguage correctly identifies Zig deallocators" {
    try std.testing.expect(classifyFreeLanguage("Allocator.free", .c) == .zig);
    try std.testing.expect(classifyFreeLanguage("heap_free", .c) == .zig);
}

test "classifyFreeLanguage correctly identifies C++ deallocators" {
    try std.testing.expect(classifyFreeLanguage("delete", .rust) == .cpp);
    try std.testing.expect(classifyFreeLanguage("delete[]", .rust) == .cpp);
    try std.testing.expect(classifyFreeLanguage("operator delete", .rust) == .cpp);
}

test "classifyFreeLanguage correctly identifies C deallocators" {
    try std.testing.expect(classifyFreeLanguage("free", .rust) == .c);
    try std.testing.expect(classifyFreeLanguage("munmap", .rust) == .c);
}

test "CrossLangAlloc initialization and cleanup" {
    var alloc = CrossLangAlloc{
        .id = 1,
        .ptr_val = 0x1000,
        .alloc_lang = .rust,
        .alloc_func = "test_func",
        .alloc_callee = "into_raw",
        .free_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .free_funcs = std.ArrayList([]const u8).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .passed_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
    };
    defer {
        alloc.free_langs.deinit(std.testing.allocator);
        alloc.free_funcs.deinit(std.testing.allocator);
        alloc.passed_langs.deinit(std.testing.allocator);
    }

    try std.testing.expect(alloc.id == 1);
    try std.testing.expect(alloc.ptr_val == 0x1000);
    try std.testing.expect(alloc.alloc_lang == .rust);
    try std.testing.expect(!alloc.freed);
    try std.testing.expect(!alloc.passed_to_other_lang);
    try std.testing.expect(alloc.free_langs.items.len == 0);
    try std.testing.expect(alloc.free_funcs.items.len == 0);
    try std.testing.expect(alloc.passed_langs.items.len == 0);
}

test "DataFlowStats initialization" {
    const stats = DataFlowStats{};
    try std.testing.expect(stats.alloc_count == 0);
    try std.testing.expect(stats.cross_lang_allocs == 0);
    try std.testing.expect(stats.orphan_pointers == 0);
    try std.testing.expect(stats.double_free_paths == 0);
}

test "isAllocationFunction detects Python allocators" {
    try std.testing.expect(isAllocationFunction("PyMem_Malloc"));
    try std.testing.expect(isAllocationFunction("PyMem_New"));
    try std.testing.expect(isAllocationFunction("PyMem_Realloc"));
    try std.testing.expect(isAllocationFunction("PyMem_Calloc"));
    try std.testing.expect(isAllocationFunction("PyObject_Malloc"));
    try std.testing.expect(isAllocationFunction("PyObject_New"));
}

test "isAllocationFunction detects Java/JNI allocators" {
    try std.testing.expect(isAllocationFunction("JNI_Malloc"));
    try std.testing.expect(isAllocationFunction("GetByteArrayElements"));
    try std.testing.expect(isAllocationFunction("GetCharArrayElements"));
    try std.testing.expect(isAllocationFunction("GetShortArrayElements"));
    try std.testing.expect(isAllocationFunction("GetIntArrayElements"));
    try std.testing.expect(isAllocationFunction("GetLongArrayElements"));
    try std.testing.expect(isAllocationFunction("GetFloatArrayElements"));
    try std.testing.expect(isAllocationFunction("GetDoubleArrayElements"));
    try std.testing.expect(isAllocationFunction("GetObjectArrayElements"));
    try std.testing.expect(isAllocationFunction("NewByteArray"));
    try std.testing.expect(isAllocationFunction("NewCharArray"));
    try std.testing.expect(isAllocationFunction("NewShortArray"));
    try std.testing.expect(isAllocationFunction("NewIntArray"));
    try std.testing.expect(isAllocationFunction("NewLongArray"));
    try std.testing.expect(isAllocationFunction("NewFloatArray"));
    try std.testing.expect(isAllocationFunction("NewDoubleArray"));
    try std.testing.expect(isAllocationFunction("NewObjectArray"));
}

test "isFreeFunction detects Python deallocators" {
    try std.testing.expect(isFreeFunction("PyMem_Free"));
    try std.testing.expect(isFreeFunction("PyMem_Del"));
    try std.testing.expect(isFreeFunction("PyMem_Realloc"));
    try std.testing.expect(isFreeFunction("PyObject_Free"));
    try std.testing.expect(isFreeFunction("PyObject_Del"));
    try std.testing.expect(isFreeFunction("Py_DECREF"));
    try std.testing.expect(isFreeFunction("Py_XDECREF"));
}

test "isFreeFunction detects Java/JNI deallocators" {
    try std.testing.expect(isFreeFunction("JNI_Free"));
    try std.testing.expect(isFreeFunction("ReleaseByteArrayElements"));
    try std.testing.expect(isFreeFunction("ReleaseCharArrayElements"));
    try std.testing.expect(isFreeFunction("ReleaseShortArrayElements"));
    try std.testing.expect(isFreeFunction("ReleaseIntArrayElements"));
    try std.testing.expect(isFreeFunction("ReleaseLongArrayElements"));
    try std.testing.expect(isFreeFunction("ReleaseFloatArrayElements"));
    try std.testing.expect(isFreeFunction("ReleaseDoubleArrayElements"));
    try std.testing.expect(isFreeFunction("ReleaseObjectArrayElements"));
    try std.testing.expect(isFreeFunction("DeleteLocalRef"));
    try std.testing.expect(isFreeFunction("DeleteGlobalRef"));
    try std.testing.expect(isFreeFunction("DeleteWeakGlobalRef"));
}

test "classifyAllocLanguage correctly identifies Python allocations" {
    try std.testing.expect(classifyAllocLanguage("PyMem_Malloc", .c) == .python);
    try std.testing.expect(classifyAllocLanguage("PyMem_New", .c) == .python);
    try std.testing.expect(classifyAllocLanguage("PyObject_Malloc", .c) == .python);
    try std.testing.expect(classifyAllocLanguage("PyObject_New", .c) == .python);
}

test "classifyAllocLanguage correctly identifies Java/JNI allocations" {
    try std.testing.expect(classifyAllocLanguage("JNI_Malloc", .c) == .java);
    try std.testing.expect(classifyAllocLanguage("GetByteArrayElements", .c) == .java);
    try std.testing.expect(classifyAllocLanguage("NewByteArray", .c) == .java);
    try std.testing.expect(classifyAllocLanguage("NewIntArray", .c) == .java);
}

test "classifyFreeLanguage correctly identifies Python deallocators" {
    try std.testing.expect(classifyFreeLanguage("PyMem_Free", .c) == .python);
    try std.testing.expect(classifyFreeLanguage("PyMem_Del", .c) == .python);
    try std.testing.expect(classifyFreeLanguage("PyObject_Free", .c) == .python);
    try std.testing.expect(classifyFreeLanguage("PyObject_Del", .c) == .python);
    try std.testing.expect(classifyFreeLanguage("Py_DECREF", .c) == .python);
    try std.testing.expect(classifyFreeLanguage("Py_XDECREF", .c) == .python);
}

test "classifyFreeLanguage correctly identifies Java/JNI deallocators" {
    try std.testing.expect(classifyFreeLanguage("JNI_Free", .c) == .java);
    try std.testing.expect(classifyFreeLanguage("ReleaseByteArrayElements", .c) == .java);
    try std.testing.expect(classifyFreeLanguage("DeleteLocalRef", .c) == .java);
    try std.testing.expect(classifyFreeLanguage("DeleteGlobalRef", .c) == .java);
    try std.testing.expect(classifyFreeLanguage("DeleteWeakGlobalRef", .c) == .java);
}

test "isKnownAllocFunction detects known allocation functions" {
    try std.testing.expect(isKnownAllocFunction("malloc"));
    try std.testing.expect(isKnownAllocFunction("calloc"));
    try std.testing.expect(isKnownAllocFunction("realloc"));
    try std.testing.expect(isKnownAllocFunction("into_raw"));
    try std.testing.expect(isKnownAllocFunction("__rust_alloc"));
    try std.testing.expect(isKnownAllocFunction("Allocator.alloc"));
    try std.testing.expect(isKnownAllocFunction("PyMem_Malloc"));
    try std.testing.expect(isKnownAllocFunction("PyMem_New"));
    try std.testing.expect(isKnownAllocFunction("JNI_Malloc"));
    try std.testing.expect(isKnownAllocFunction("GetByteArrayElements"));

    // Should not detect unknown functions
    try std.testing.expect(!isKnownAllocFunction("unknown_func"));
    try std.testing.expect(!isKnownAllocFunction("printf"));
}

test "calculateOrphanConfidence returns appropriate confidence scores" {
    // Test with known allocation function and known language
    const alloc1 = CrossLangAlloc{
        .id = 1,
        .ptr_val = 0x1000,
        .alloc_lang = .rust,
        .alloc_func = "test_func",
        .alloc_callee = "malloc",
        .free_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .free_funcs = std.ArrayList([]const u8).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .passed_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
    };
    defer {
        alloc1.free_langs.deinit(std.testing.allocator);
        alloc1.free_funcs.deinit(std.testing.allocator);
        alloc1.passed_langs.deinit(std.testing.allocator);
    }

    const confidence1 = calculateOrphanConfidence(alloc1);
    try std.testing.expect(confidence1 > 0.8 and confidence1 <= 1.0);

    // Test with unknown allocation function and unknown language
    const alloc2 = CrossLangAlloc{
        .id = 2,
        .ptr_val = 0x1000,
        .alloc_lang = .unknown,
        .alloc_func = "test_func",
        .alloc_callee = "unknown_func",
        .free_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .free_funcs = std.ArrayList([]const u8).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .passed_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
    };
    defer {
        alloc2.free_langs.deinit(std.testing.allocator);
        alloc2.free_funcs.deinit(std.testing.allocator);
        alloc2.passed_langs.deinit(std.testing.allocator);
    }

    const confidence2 = calculateOrphanConfidence(alloc2);
    try std.testing.expect(confidence2 < 0.9);

    // Test with global pointer (higher address)
    const alloc3 = CrossLangAlloc{
        .id = 3,
        .ptr_val = 0x800000000000, // High address indicating global
        .alloc_lang = .rust,
        .alloc_func = "test_func",
        .alloc_callee = "malloc",
        .free_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .free_funcs = std.ArrayList([]const u8).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .passed_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
    };
    defer {
        alloc3.free_langs.deinit(std.testing.allocator);
        alloc3.free_funcs.deinit(std.testing.allocator);
        alloc3.passed_langs.deinit(std.testing.allocator);
    }

    const confidence3 = calculateOrphanConfidence(alloc3);
    try std.testing.expect(confidence3 < 0.9); // Should be lower due to global address
}
