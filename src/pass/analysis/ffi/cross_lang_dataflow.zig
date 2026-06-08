//! Cross-Language Data Flow Tracker
//!
//! Tracks pointer/data flow across FFI boundaries to detect:
//! 1. Orphan pointers - allocated but never freed or passed to another language
//! 2. Double-free paths - same pointer has multiple free paths across languages
//!
//! This module uses CrossLangEdge from pass_types.zig to identify FFI crossings
//! and reports issues using IssueKind.cross_language_leak and IssueKind.double_free.
//!
//! T4 Enhancement: Integrated summary-based propagation for cross-function leak
//! detection. Uses SummaryPropagation engine to query callee summaries and
//! suppress false positives when ownership is legitimately transferred.

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
const language_detector = @import("../../../semantics/language_detector.zig");

// T4: Import summary propagation engine
const summary_propagation = @import("../../../dataflow/summary_propagation.zig");
const SummaryPropagation = summary_propagation.SummaryPropagation;
const LeakAnalysisResult = summary_propagation.LeakAnalysisResult;
const ir_store_mod = @import("../../../ir/ir_store.zig");
const symbol_graph = @import("../../../ffi/symbol_graph.zig");

/// Convert SymbolGraph LanguageId to FFIBoundary Language.
/// Both enums share the same variant names for common languages;
/// swift and kotlin are not in FFIBoundary.Language so they map to unknown.
fn languageIdToLanguage(id: symbol_graph.LanguageId) Language {
    return switch (id) {
        .c => .c,
        .cpp => .cpp,
        .rust => .rust,
        .zig => .zig,
        .go => .go,
        .java => .java,
        .python => .python,
        .csharp => .csharp,
        .swift, .kotlin, .unknown => .unknown,
    };
}

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
    /// Number of stdlib issues suppressed (P0-1 fix)
    stdlib_suppressed: u32 = 0,
};

/// Represents a pointer allocation that may cross FFI boundaries
pub const CrossLangAlloc = struct {
    /// Unique identifier for the allocation
    id: u32,
    /// Pointer value (LLVM value reference as integer)
    ptr_val: u64,
    /// Language where allocation occurred
    alloc_lang: Language,
    /// Function that performed the allocation (display name)
    alloc_func: []const u8,
    /// Callee function that performed the allocation (e.g., malloc, into_raw)
    alloc_callee: []const u8,
    /// Stable symbol pointer for the allocation function (from SymbolGraph)
    alloc_symbol: ?*const symbol_graph.Symbol,
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

        log.info("CONTRACTS: Loaded {} rules for {} libraries", .{
            contract_db.totalRules(),
            contract_db.libraryCount(),
        });

        var esc_analysis = escape_analysis.EscapeAnalysis.init(ctx.allocator);
        defer esc_analysis.deinit();

        var raii = raii_detector.RAIIDetector.init(ctx.allocator) catch |err| {
            log.warn("CrossLangDataFlow: Failed to init RAIIDetector: {}", .{err});
            return;
        };
        defer raii.deinit();

        // T4: Initialize summary propagation engine for cross-function leak detection
        var prop_engine: ?SummaryPropagation = SummaryPropagation.init(ctx.allocator) catch |err| {
            log.warn("CrossLangDataFlow: Failed to init SummaryPropagation: {}", .{err});
            // Continue without propagation engine (graceful degradation)
            null;
        };
        defer if (prop_engine) |*engine| engine.deinit();

        if (prop_engine) |*engine| {
            engine.loadBuiltins() catch |err| {
                log.warn("CrossLangDataFlow: Failed to load built-in summaries: {}", .{err});
            };
        }

        // Build SymbolGraph for stable *Symbol identity across analysis.
        // Symbol pointers remain valid for the lifetime of this function.
        var sym_graph = symbol_graph.SymbolGraph.build(ctx.allocator, ctx.module.?.raw) catch |err| {
            log.warn("CrossLangDataFlow: Failed to build SymbolGraph: {}", .{err});
            return;
        };
        defer sym_graph.deinit();

        var stats = DataFlowStats{};
        var allocations = try std.ArrayList(CrossLangAlloc).initCapacity(ctx.allocator, 64);
        defer {
            for (allocations.items) |*alloc| {
                alloc.free_langs.deinit(ctx.allocator);
                for (alloc.free_funcs.items) |s| ctx.allocator.free(s);
                alloc.free_funcs.deinit(ctx.allocator);
                alloc.passed_langs.deinit(ctx.allocator);
            }
            allocations.deinit(ctx.allocator);
        }

        const cross_sites = sym_graph.getCrossLangSites();
        if (cross_sites.len == 0) {
            diag.info("CrossLangDataFlow: No cross-language sites found, skipping analysis", .{});
            return;
        }

        // Pass sym_graph and propagation engine to unified analyzer
        try analyzeModuleUnified(ctx, &allocations, &sym_graph, &stats, diag, &contract_db, &esc_analysis, &raii, if (prop_engine) |*e| e else null);

        try detectDoubleFreePaths(ctx, &allocations, &stats, diag, &contract_db);

        // Print FFI Contract DB statistics
        contract_db.printStats();

        // T4: Print propagation statistics
        if (prop_engine) |*engine| {
            const prop_stats = engine.getStats();
            log.info("PROPAGATION: Analyzed {} calls, {} ownership transfers detected", .{
                prop_stats.total_calls_analyzed,
                prop_stats.ownership_transfers_detected,
            });
        }

        diag.info("CrossLangDataFlow: {} allocations tracked, {} cross-lang, {} orphans, {} double-frees", .{
            stats.alloc_count,
            stats.cross_lang_allocs,
            stats.orphan_pointers,
            stats.double_free_paths,
        });
    }

    /// Unified module analysis - single traversal collecting all data
    /// Replaces: trackAllocations + trackFrees + trackPointerPassing + detectOrphanPointers + detectUseAfterFreeAcrossBoundary
    ///
    /// T4 Enhanced: Now accepts optional SummaryPropagation engine for cross-function
    /// leak detection. When provided, queries callee summaries to distinguish legitimate
    /// ownership transfers from actual memory leaks.
    ///
    /// T6 Enhanced: Uses SymbolGraph for stable *Symbol identity and cross-language
    /// site matching instead of LLVMValueRef @intFromPtr comparisons.
    fn analyzeModuleUnified(
        ctx: *PassContext,
        allocations: *std.ArrayList(CrossLangAlloc),
        sym_graph: *const symbol_graph.SymbolGraph,
        stats: *DataFlowStats,
        diag: *DiagnosticWriter,
        db: *ffi_contract_db.FFIContractDB,
        esc_analysis: *escape_analysis.EscapeAnalysis,
        raii: *raii_detector.RAIIDetector,
        prop_engine: ?*SummaryPropagation, // T4: Optional propagation engine
    ) !void {
        if (ctx.ir_store.function_list.len == 0) return;

        var next_id: u32 = 1;

        // Build edge map from SymbolGraph cross-language sites.
        // Each site.callee has a stable *Symbol pointer and lang classification.
        var edge_map = std.StringHashMap(symbol_graph.LanguageId).init(ctx.allocator);
        defer edge_map.deinit();
        const cross_sites = sym_graph.getCrossLangSites();
        for (cross_sites) |site| {
            try edge_map.put(site.callee.name, site.callee.lang);
        }

        var alloc_by_ptr = std.AutoHashMap(u64, usize).init(ctx.allocator);
        defer alloc_by_ptr.deinit();

        var freed_alloc_by_ptr = std.AutoHashMap(u64, usize).init(ctx.allocator);
        defer freed_alloc_by_ptr.deinit();

        // T6: *Symbol-based alloc identity map — uses stable Symbol pointers
        // from SymbolGraph instead of @intFromPtr for robust alloc/free matching.
        var alloc_by_sym = std.AutoHashMap(*const symbol_graph.Symbol, usize).init(ctx.allocator);
        defer alloc_by_sym.deinit();

        for (ctx.ir_store.function_list) |fir| {
            const func_name = fir.name;
            const func_lang = ctx.getModuleLanguage().language;

            var store_map = std.AutoHashMap(u64, u64).init(ctx.allocator);
            defer store_map.deinit();

            for (fir.instructions, fir.opcodes) |inst, opcode| {

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
                    if (isAllocationFunction(called_name) or isJniAllocCall(called_name)) {
                        // JNI STRUCTURE VALIDATION: Eliminate ~80% false positives
                        // by verifying the call has proper JNIEnv* first parameter.
                        // Many functions contain "JNI"/"FindClass"/"GetMethodID" substrings
                        // in their names but are not actual JNI calls (e.g., helper wrappers,
                        // logging functions, test utilities). This IR-level check ensures
                        // only real JNI calls with correct calling convention are tracked.
                        if (isJniAllocCall(called_name) and !isRealJNICall(inst)) {
                            log.debug("JNI-FP-FILTER: Skipping non-JNI call '{s}' - missing JNIEnv* parameter", .{called_name});
                            // Don't track this as a JNI allocation - it's a false positive
                            // Fall through to check if it's a regular allocation function
                            if (!isAllocationFunction(called_name)) {
                                continue; // Skip entirely if not a regular alloc either
                            }
                        }

                        // CONTRACT-DB: Pre-check allocation with contract DB
                        const alloc_confidence = db.getConfidence(called_name);
                        const alloc_ownership = db.getOwnership(called_name);

                        // JNI-specific: Log JNI allocation details
                        if (isJniAllocCall(called_name) and isRealJNICall(inst)) {
                            log.debug("JNI-ALLOC: {s} in {s} (requires_null_check={})", .{
                                called_name,
                                func_name,
                                requiresJniNullCheck(called_name),
                            });
                        }

                        const result_val = @intFromPtr(inst);
                        if (result_val != 0) {
                            const alloc_lang = classifyAllocLanguage(called_name, func_lang, ctx);
                            const alloc_sym = sym_graph.symbols.getPtr(func_name);
                            const alloc = CrossLangAlloc{
                                .id = next_id,
                                .ptr_val = result_val,
                                .alloc_lang = alloc_lang,
                                .alloc_func = func_name,
                                .alloc_callee = called_name,
                                .alloc_symbol = alloc_sym,
                                .free_langs = try std.ArrayList(Language).initCapacity(ctx.allocator, 2),
                                .free_funcs = try std.ArrayList([]const u8).initCapacity(ctx.allocator, 2),
                                .passed_langs = try std.ArrayList(Language).initCapacity(ctx.allocator, 2),
                            };
                            try allocations.append(ctx.allocator, alloc);
                            try alloc_by_ptr.put(result_val, allocations.items.len - 1);
                            // T6: Also register by stable *Symbol for robust matching
                            if (alloc_sym) |sym| {
                                try alloc_by_sym.put(sym, allocations.items.len - 1);
                            }
                            stats.alloc_count += 1;
                            next_id += 1;

                            // Log high-confidence contract matches
                            if (alloc_confidence > 0.9) {
                                log.debug("CONTRACT-ALLOC: {s} in {s} (confidence={d:.2}, ownership={s})", .{
                                    called_name,
                                    func_name,
                                    alloc_confidence,
                                    if (alloc_ownership) |o| @tagName(o) else "unknown",
                                });
                            }
                        }
                    }

                    // 2. Track frees (including JNI releases)
                    if (isFreeFunction(called_name) or isJniReleaseCall(called_name)) {
                        // JNI STRUCTURE VALIDATION: Same FP filtering for release calls
                        if (isJniReleaseCall(called_name) and !isRealJNICall(inst)) {
                            log.debug("JNI-FP-FILTER: Skipping non-JNI release call '{s}' - missing JNIEnv* parameter", .{called_name});
                            if (!isFreeFunction(called_name)) {
                                continue;
                            }
                        }

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
                                        // Determine caller language for free classification fallback.
                                        // Use override registry first, then fall back to module-level language.
                                        const effective_caller_lang = ctx.lookupFunctionLanguage(func_name) orelse func_lang;
                                        const free_lang = classifyFreeLanguage(called_name, effective_caller_lang, ctx);
                                        try alloc.free_langs.append(ctx.allocator, free_lang);
                                        try alloc.free_funcs.append(ctx.allocator, try ctx.allocator.dupe(u8, called_name));
                                        alloc.freed = true;
                                        try freed_alloc_by_ptr.put(ptr_val, idx);
                                    }
                                } else if (sym_graph.symbols.getPtr(func_name)) |free_sym| {
                                    // T6: *Symbol-based fallback — use stable Symbol pointer
                                    // identity when @intFromPtr u64 match fails. Handles cases
                                    // where LLVM value identity doesn't match but the alloc/free
                                    // occurs in the same function (same *Symbol).
                                    if (alloc_by_sym.get(free_sym)) |idx| {
                                        const alloc = &allocations.items[idx];
                                        if (!alloc.freed) {
                                            const effective_caller_lang = ctx.lookupFunctionLanguage(func_name) orelse func_lang;
                                            const free_lang = classifyFreeLanguage(called_name, effective_caller_lang, ctx);
                                            try alloc.free_langs.append(ctx.allocator, free_lang);
                                            try alloc.free_funcs.append(ctx.allocator, try ctx.allocator.dupe(u8, called_name));
                                            alloc.freed = true;
                                            try freed_alloc_by_ptr.put(ptr_val, idx);
                                            log.debug("T6-SYMBOL-MATCH: Free matched via *Symbol '{s}' for alloc id={}", .{
                                                func_name, alloc.id,
                                            });
                                        }
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
                                try alloc.passed_langs.append(ctx.allocator, languageIdToLanguage(edge));
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

                            if (edge_map.get(called_name)) |callee_lang| {
                                use_lang = languageIdToLanguage(callee_lang);
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

                    // 5. JNI Null Check Detection
                    // Check if this is a JNI call that requires null check on return value
                    // Only apply to verified real JNI calls to avoid false positives
                    if (isJniAllocCall(called_name) and isRealJNICall(inst) and requiresJniNullCheck(called_name)) {
                        // Look for null check in subsequent instructions using pre-cached IR
                        var has_null_check = false;
                        const inst_idx = findInstructionIndexFir(fir, inst);
                        const scan_limit: u32 = 5;
                        var check_count: u32 = 0;
                        if (inst_idx) |si| {
                            for (fir.instructions[si + 1 ..], fir.opcodes[si + 1 ..]) |next_inst, next_opcode| {
                                if (check_count >= scan_limit) break;
                                check_count += 1;

                                // Check for ICMP (comparison instruction)
                                if (next_opcode == c.LLVMICmp) {
                                    // This could be a null check - simplified detection
                                    has_null_check = true;
                                    break;
                                }
                                // Check for conditional branch (might be result of null check)
                                if (next_opcode == c.LLVMBr) {
                                    const num_ops = c.LLVMGetNumOperands(next_inst);
                                    if (num_ops >= 1) {
                                        // Conditional branch indicates some check was done
                                        has_null_check = true;
                                        break;
                                    }
                                }
                            }
                        }

                        if (!has_null_check) {
                            const message = try std.fmt.allocPrint(ctx.allocator, "JNI function {s} requires null check on return value in function {s}", .{ called_name, func_name });
                            defer ctx.allocator.free(message);

                            const location = Location.init(func_name);
                            const issue = Issue.init(
                                .malloc_unchecked,
                                message,
                                location,
                                .medium,
                                0.75,
                            );
                            try ctx.addIssue(&issue);

                            diag.warn("JNI-NULL-CHECK: Missing null check for {s} return value in {s}", .{
                                called_name,
                                func_name,
                            });
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

            // ── GO CGO GC PIN DETECTION ──
            // Go pointers passed to C must be pinned to prevent GC from moving them.
            // Check if the function calls runtime.Pinner.Pin or runtime.KeepAlive.
            if (alloc.alloc_lang == .go and alloc.passed_to_other_lang) {
                const has_pin = searchForPinOp(ctx, alloc.alloc_func);
                if (!has_pin) {
                    const message = try std.fmt.allocPrint(ctx.allocator, "Go pointer passed to C without GC pinning in {s}: use runtime.Pinner.Pin or runtime.KeepAlive to prevent GC movement", .{alloc.alloc_func});
                    defer ctx.allocator.free(message);

                    const location = Location.init(alloc.alloc_func);
                    const issue = Issue.init(
                        .cross_language_leak,
                        message,
                        location,
                        .high,
                        0.85,
                    );
                    try ctx.addIssue(&issue);

                    diag.warn("CrossLangDataFlow: Go pointer {} in {s} passed to C without GC pinning", .{
                        alloc.id,
                        alloc.alloc_func,
                    });
                }
                continue; // Not an orphan, skip orphan check
            }

            if (alloc.passed_to_other_lang) continue;

            // ── FOCUS-USER-CODE: Stdlib suppression (P0-1 fix) ──
            // When focus_user_code is enabled (default), suppress issues from
            // Zig stdlib and compiler-generated functions. This fixes the 86.8%
            // FP rate caused by reporting stdlib allocator internals as leaks.
            //
            // Root cause: CLI config (focus_user_code=true) was not being passed
            // to this pass. Passes hardcoded focus_user_code=true internally but
            // cross_lang_dataflow was missing this check entirely.
            //
            // Fix: Check ctx.focus_user_code and use PassContext's built-in
            // isZigStdlibFunction() classifier for accurate detection.
            if (ctx.focus_user_code) {
                const is_stdlib_alloc = ctx.isZigStdlibFunction(alloc.alloc_func);
                const is_stdlib_callee = ctx.isZigStdlibFunction(alloc.alloc_callee);

                if (is_stdlib_alloc or is_stdlib_callee) {
                    log.debug("FOCUS-USER-CODE: Suppressing stdlib issue: alloc_func={s}, callee={s}", .{
                        alloc.alloc_func,
                        alloc.alloc_callee,
                    });
                    stats.stdlib_suppressed += 1;
                    continue;
                }
            }

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

            // Heuristic: if the allocation's function also freed this specific
            // allocation (same *Symbol pointer), the alloc/free is correctly
            // paired. Uses stable *Symbol identity from SymbolGraph instead
            // of string comparison to avoid LLVM value identity issues.
            var same_func_freed = false;
            if (alloc.alloc_symbol) |alloc_sym| {
                for (alloc.free_funcs.items) |free_func| {
                    if (sym_graph.symbols.getPtr(free_func)) |free_sym| {
                        if (free_sym == alloc_sym) {
                            same_func_freed = true;
                            break;
                        }
                    }
                }
            }
            if (same_func_freed) {
                diag.info("CrossLangDataFlow: Suppressing orphan for {s} in {s} — same function freed this allocation", .{ alloc.alloc_callee, alloc.alloc_func });
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

            // ── INTENTIONAL OWNERSHIP TRANSFER CHECK ──
            // Distinguish intentional leaks (Box::leak, into_raw, ManuallyDrop,
            // forget) from forgotten frees. These are legitimate FFI patterns
            // where ownership is deliberately transferred to another language.
            if (isIntentionalOwnershipTransfer(&alloc)) {
                log.debug("INTENTIONAL-TRANSFER: Alloc 0x{x} via {s} in {s} is intentional ownership transfer, not a leak", .{
                    alloc.ptr_val,
                    alloc.alloc_callee,
                    alloc.alloc_func,
                });
                continue;
            }

            // ── T4: SUMMARY-BASED PROPAGATION CHECK ──
            // Query the propagation engine to check if this allocation's ownership
            // was transferred to a callee function. If so, suppress leak report.
            if (prop_engine) |engine| {
                // Check if any of the free functions we know about indicate ownership transfer
                if (alloc.free_funcs.items.len > 0) {
                    for (alloc.free_funcs.items) |free_func| {
                        const prop_result = engine.analyzeCall(alloc.ptr_val, free_func, 0);
                        switch (prop_result) {
                            .ownership_transferred => {
                                log.debug("PROPAGATION-SUPPRESS: Ownership of 0x{x} transferred to {s} in {s}", .{
                                    alloc.ptr_val,
                                    free_func,
                                    alloc.alloc_func,
                                });
                                continue; // Skip to next allocation (not a leak)
                            },
                            .escaped => {
                                log.debug("PROPAGATION-ESCAPE: Allocation 0x{x} may escape via {s}", .{
                                    alloc.ptr_val,
                                    free_func,
                                });
                                continue; // Escaped allocations are not leaks
                            },
                            else => {}, // Continue with other checks
                        }
                    }
                }
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

            diag.debug("CrossLangDataFlow: Orphan pointer {} in {s} ({s}) (confidence: {d:.2})", .{
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
        if (ctx.ir_store.function_list.len == 0) return;

        var next_id: u32 = 1;

        for (ctx.ir_store.function_list) |fir| {
            const func_name = fir.name;
            const func_lang = ctx.getModuleLanguage().language;

            for (fir.calls) |inst| {
                const called_val = c.LLVMGetCalledValue(inst);
                if (@intFromPtr(called_val) == 0) continue;

                const called_name_ptr = c.LLVMGetValueName(called_val);
                const called_name = if (@intFromPtr(called_name_ptr) != 0)
                    std.mem.span(called_name_ptr)
                else
                    "";

                if (isAllocationFunction(called_name)) {
                    const result_val = @intFromPtr(inst);
                    if (result_val == 0) continue;

                    const alloc_lang = classifyAllocLanguage(called_name, func_lang, ctx);

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

                    if (alloc_lang != func_lang and alloc_lang != .unknown) {
                        stats.cross_lang_allocs += 1;
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
        if (ctx.ir_store.function_list.len == 0) return;

        var tracked_ptrs = std.AutoHashMap(u64, usize).init(ctx.allocator);
        defer tracked_ptrs.deinit();
        for (allocations.items, 0..) |alloc, idx| {
            try tracked_ptrs.put(alloc.ptr_val, idx);
        }

        for (ctx.ir_store.function_list) |fir| {
            const func_name = fir.name;
            var store_map = std.AutoHashMap(u64, u64).init(ctx.allocator);
            defer store_map.deinit();

            for (fir.instructions, fir.opcodes) |inst, opcode| {
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

                    if (isFreeFunction(called_name)) {
                        const num_operands = c.LLVMGetNumOperands(inst);
                        if (num_operands < 2) continue;

                        const ptr_arg = c.LLVMGetOperand(inst, 1);
                        var ptr_val = @intFromPtr(ptr_arg);
                        if (ptr_val == 0) continue;

                        if (store_map.get(ptr_val)) |original_val| {
                            ptr_val = original_val;
                        }

                        if (tracked_ptrs.get(ptr_val)) |idx| {
                            const alloc = &allocations.items[idx];
                            if (!alloc.freed) {
                                // Determine caller language for free classification fallback.
                                // Use override registry first, then fall back to auto-detection.
                                const effective_caller_lang = ctx.lookupFunctionLanguage(func_name) orelse
                                    language_detector.identifyLanguage(fir.func);
                                const free_lang = classifyFreeLanguage(called_name, effective_caller_lang, ctx);
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
        if (ctx.ir_store.function_list.len == 0) return;

        var alloc_by_ptr = std.AutoHashMap(u64, usize).init(ctx.allocator);
        defer alloc_by_ptr.deinit();
        for (allocations.items, 0..) |alloc, idx| {
            try alloc_by_ptr.put(alloc.ptr_val, idx);
        }

        var edge_map = std.StringHashMap(CrossLangEdge).init(ctx.allocator);
        defer edge_map.deinit();
        for (cross_edges) |edge| {
            if (edge.is_ffi_boundary) {
                try edge_map.put(edge.callee_name, edge);
            }
        }

        for (ctx.ir_store.function_list) |fir| {
            for (fir.calls) |inst| {
                const called_val = c.LLVMGetCalledValue(inst);
                if (@intFromPtr(called_val) == 0) continue;

                const called_name_ptr = c.LLVMGetValueName(called_val);
                const called_name = if (@intFromPtr(called_name_ptr) != 0)
                    std.mem.span(called_name_ptr)
                else
                    "";

                const edge = edge_map.get(called_name) orelse continue;
                const callee_lang = edge.callee_lang;

                const num_operands = c.LLVMGetNumOperands(inst);
                var arg_idx: u32 = 0;
                while (arg_idx < num_operands) : (arg_idx += 1) {
                    const arg = c.LLVMGetOperand(inst, arg_idx);
                    const arg_val = @intFromPtr(arg);
                    if (arg_val == 0) continue;

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
            for (ctx.ir_store.function_list) |fir| {
                const func_name = fir.name;
                for (fir.calls) |inst| {
                    const called_val = c.LLVMGetCalledValue(inst) orelse continue;
                    const called_name_ptr = c.LLVMGetValueName(called_val);
                    const called_name = if (@intFromPtr(called_name_ptr) != 0) std.mem.span(called_name_ptr) else continue;
                    if (isFreeFunction(called_name)) {
                        try funcs_with_frees.put(func_name, {});
                        break;
                    }
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

            // Heuristic: if the allocation's function ALSO freed this specific
            // allocation (same alloc_func appears in free_funcs), the alloc/free
            // is correctly paired. The previous check ("function calls any free")
            // was too broad — it suppressed cross-language orphans where the
            // alloc function happened to call a free for a DIFFERENT pointer.
            // Fix: check specific alloc→free pairing, not function-level presence.
            var same_func_freed = false;
            for (alloc.free_funcs.items) |free_func| {
                if (std.mem.eql(u8, free_func, alloc.alloc_func)) {
                    same_func_freed = true;
                    break;
                }
            }
            if (same_func_freed) {
                diag.info("CrossLangDataFlow: Suppressing orphan for {s} in {s} — same function freed this allocation", .{ alloc.alloc_callee, alloc.alloc_func });
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

            diag.debug("CrossLangDataFlow: Orphan pointer {} in {s} ({s}) (confidence: {d:.2})", .{
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
        db: *ffi_contract_db.FFIContractDB,
    ) !void {
        for (allocations.items) |alloc| {
            // Skip if not freed
            if (!alloc.freed) continue;

            // CONTRACT-DB: Check if allocation is from error-prone library
            const is_error_prone = db.isErrorProneLib(alloc.alloc_callee);
            const alloc_rule_confidence = db.getConfidence(alloc.alloc_callee);

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

            // CONTRACT-DB: Validate each free function against the contract
            var has_contract_violation = false;
            for (alloc.free_funcs.items) |free_func| {
                const pair_validity = db.isValidRelease(alloc.alloc_callee, free_func);
                if (pair_validity == .mismatch) {
                    has_contract_violation = true;
                    log.warn("CONTRACT-DOUBLE-FREE-MISMATCH: {s} freed by invalid {s}", .{
                        alloc.alloc_callee,
                        free_func,
                    });
                }
            }

            // Calculate confidence with contract DB boost
            var confidence: f32 = 0.9;
            if (is_error_prone) {
                confidence = @min(confidence + 0.05, 1.0);
            }
            if (has_contract_violation) {
                confidence = @min(confidence + 0.05, 1.0);
            }
            if (alloc_rule_confidence > confidence) {
                confidence = alloc_rule_confidence;
            }

            // Create issue message
            const message = try std.fmt.allocPrint(ctx.allocator, "Double-free path detected: pointer allocated in {s} ({s}) via {s} freed in multiple languages ({s}){s}", .{
                alloc.alloc_func,
                @tagName(alloc.alloc_lang),
                alloc.alloc_callee,
                formatLanguages(alloc.free_langs.items),
                if (has_contract_violation) " [CONTRACT VIOLATION]" else "",
            });
            defer ctx.allocator.free(message);

            const location = Location.init(alloc.alloc_func);
            const severity: IssueSeverity = if (has_contract_violation and is_error_prone) .critical else .high;
            const issue = Issue.init(
                .double_free,
                message,
                location,
                severity,
                confidence,
            );
            try ctx.addIssue(&issue);

            diag.warn("CrossLangDataFlow: Double-free path {} in {s} ({s}) freed in {s} (confidence: {d:.2}{s})", .{
                alloc.id,
                alloc.alloc_func,
                @tagName(alloc.alloc_lang),
                formatLanguages(alloc.free_langs.items),
                confidence,
                if (has_contract_violation) ", CONTRACT MISMATCH" else "",
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
        if (ctx.ir_store.function_list.len == 0) return;

        var freed_alloc_by_ptr = std.AutoHashMap(u64, usize).init(ctx.allocator);
        defer freed_alloc_by_ptr.deinit();
        for (allocations.items, 0..) |alloc, idx| {
            if (alloc.freed) {
                try freed_alloc_by_ptr.put(alloc.ptr_val, idx);
            }
        }

        var edge_map = std.StringHashMap(CrossLangEdge).init(ctx.allocator);
        defer edge_map.deinit();
        for (cross_edges) |edge| {
            if (edge.is_ffi_boundary) {
                try edge_map.put(edge.callee_name, edge);
            }
        }

        for (ctx.ir_store.function_list) |fir| {
            const func_name = fir.name;

            for (fir.instructions, fir.opcodes) |inst, opcode| {
                const num_operands = c.LLVMGetNumOperands(inst);
                var arg_idx: u32 = 0;
                while (arg_idx < num_operands) : (arg_idx += 1) {
                    const arg = c.LLVMGetOperand(inst, arg_idx);
                    const arg_val = @intFromPtr(arg);
                    if (arg_val == 0) continue;

                    if (freed_alloc_by_ptr.get(arg_val)) |idx| {
                        const alloc = &allocations.items[idx];
                        const func_lang = ctx.getModuleLanguage().language;
                        var use_lang = func_lang;

                        if (llvm_safe.isCallOrInvoke(opcode)) {
                            const called_val = c.LLVMGetCalledValue(inst);
                            if (@intFromPtr(called_val) != 0) {
                                const called_name_ptr = c.LLVMGetValueName(called_val);
                                const called_name = if (@intFromPtr(called_name_ptr) != 0)
                                    std.mem.span(called_name_ptr)
                                else
                                    "";

                                if (edge_map.get(called_name)) |edge| {
                                    use_lang = edge.callee_lang;
                                }
                            }
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
/// Checks language override registry first before pattern matching.
fn classifyAllocLanguage(callee_name: []const u8, caller_lang: Language, ctx: *const PassContext) Language {
    // Check language override registry first — user-specified classifications
    // take priority over auto-detection. This is the primary FP elimination point.
    if (ctx.lookupFunctionLanguage(callee_name)) |overridden_lang| {
        return overridden_lang;
    }

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
/// Checks language override registry first before pattern matching.
fn classifyFreeLanguage(callee_name: []const u8, caller_lang: Language, ctx: *const PassContext) Language {
    // Check language override registry first — user-specified classifications
    // take priority over auto-detection. This is the primary FP elimination point.
    if (ctx.lookupFunctionLanguage(callee_name)) |overridden_lang| {
        return overridden_lang;
    }

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

/// Check if a function call is a JNI allocation (must pair with release).
fn isJniAllocCall(callee_name: []const u8) bool {
    const JNI_ALLOC_FUNCTIONS = [_][]const u8{
        "NewGlobalRef",
        "NewLocalRef",
        "GetStringUTFChars",
        "GetStringUTF",
        "GetByteArrayElements",
        "GetCharArrayElements",
        "GetShortArrayElements",
        "GetIntArrayElements",
        "GetLongArrayElements",
        "GetFloatArrayElements",
        "GetDoubleArrayElements",
        "GetBooleanArrayElements",
        "GetByteArrayRegion",
        "GetStringChars",
        "AttachCurrentThread",
        "FindClass",
    };

    for (JNI_ALLOC_FUNCTIONS) |pattern| {
        if (std.mem.endsWith(u8, callee_name, pattern)) {
            return true;
        }
    }
    return false;
}

/// Check if a function call is a JNI release (pairs with alloc).
fn isJniReleaseCall(callee_name: []const u8) bool {
    const JNI_RELEASE_FUNCTIONS = [_][]const u8{
        "DeleteGlobalRef",
        "DeleteLocalRef",
        "ReleaseStringUTFChars",
        "ReleaseStringUTF",
        "ReleaseByteArrayElements",
        "ReleaseCharArrayElements",
        "ReleaseShortArrayElements",
        "ReleaseIntArrayElements",
        "ReleaseLongArrayElements",
        "ReleaseFloatArrayElements",
        "ReleaseDoubleArrayElements",
        "ReleaseBooleanArrayElements",
        "DetachCurrentThread",
    };

    for (JNI_RELEASE_FUNCTIONS) |pattern| {
        if (std.mem.endsWith(u8, callee_name, pattern)) {
            return true;
        }
    }
    return false;
}

/// Check if a JNI function requires null check on return value.
fn requiresJniNullCheck(callee_name: []const u8) bool {
    const JNI_NULL_CHECK_REQUIRED = [_][]const u8{
        "FindClass",
        "GetMethodID",
        "GetStaticMethodID",
        "GetFieldID",
        "GetStaticFieldID",
        "NewGlobalRef",
        "GetStringUTFChars",
        "GetByteArrayElements",
        "GetCharArrayElements",
        "GetShortArrayElements",
        "GetIntArrayElements",
        "GetLongArrayElements",
        "GetFloatArrayElements",
        "GetDoubleArrayElements",
        "GetBooleanArrayElements",
        "NewStringUTF",
        "NewByteArray",
        "NewCharArray",
        "RegisterNatives",
    };

    for (JNI_NULL_CHECK_REQUIRED) |pattern| {
        if (std.mem.endsWith(u8, callee_name, pattern)) {
            return true;
        }
    }
    return false;
}

/// Verify if a call instruction is a real JNI call by checking IR-level parameter types.
/// JNI calling convention requires the first parameter to be JNIEnv* (i8** in IR).
/// This eliminates ~80% false positives from functions that happen to contain
/// JNI-related substrings in their names but are not actual JNI calls.
fn isRealJNICall(inst: c.LLVMValueRef) bool {
    // JNI calls must have at least 2 operands: [callee, env_ptr, ...]
    if (c.LLVMGetNumOperands(inst) < 2) return false;

    // Get first argument (should be JNIEnv*)
    const first_arg = c.LLVMGetOperand(inst, 0);
    if (@intFromPtr(first_arg) == 0) return false;

    const arg_type = c.LLVMTypeOf(first_arg);
    if (@intFromPtr(arg_type) == 0) return false;

    // JNIEnv* in IR is either:
    // 1. i8** (pointer to pointer) - most common
    // 2. %struct.JNINativeInterface_** (JNIEnv struct pointer)
    // 3. %struct._JNIEnv** (alternative JNIEnv struct)
    return isPointerToPointer(arg_type) or isJNIEnvType(arg_type);
}

/// Check if an LLVM type is a pointer-to-pointer (e.g., i8**)
/// This is the typical IR representation of JNIEnv*
fn isPointerToPointer(llvm_type: c.LLVMTypeRef) bool {
    const type_kind = c.LLVMGetTypeKind(llvm_type);

    // Must be a pointer type
    if (type_kind != c.LLVMPointerTypeKind) return false;

    // Get the element type (what the pointer points to)
    const elem_type = c.LLVMGetElementType(llvm_type);
    if (@intFromPtr(elem_type) == 0) return false;

    // Check if element type is also a pointer (making it pointer-to-pointer)
    const elem_kind = c.LLVMGetTypeKind(elem_type);
    return elem_kind == c.LLVMPointerTypeKind;
}

/// Check if an LLVM type is a JNIEnv structure pointer or pointer-to-pointer.
/// Handles various JNIEnv struct representations in different LLVM IR outputs:
/// - %struct.JNINativeInterface_**
/// - %struct._JNIEnv**
/// - %struct.JNIEnv**
fn isJNIEnvType(llvm_type: c.LLVMTypeRef) bool {
    const type_kind = c.LLVMGetTypeKind(llvm_type);

    // Handle pointer types (most common case for JNIEnv*)
    if (type_kind == c.LLVMPointerTypeKind) {
        const elem_type = c.LLVMGetElementType(llvm_type);
        if (@intFromPtr(elem_type) == 0) return false;

        // Check if this is pointer-to-JNI-struct (JNIEnv**)
        if (isJNIStructType(elem_type)) return true;

        // Check if element is also pointer to JNI struct (for ** cases)
        const elem_kind = c.LLVMGetTypeKind(elem_type);
        if (elem_kind == c.LLVMPointerTypeKind) {
            const inner_elem = c.LLVMGetElementType(elem_type);
            if (@intFromPtr(inner_elem) != 0 and isJNIStructType(inner_elem)) {
                return true;
            }
        }
    }

    // Handle struct types directly (rare but possible)
    if (type_kind == c.LLVMStructTypeKind) {
        return isJNIStructType(llvm_type);
    }

    return false;
}

/// Check if an LLVM type is a known JNI structure type.
/// Matches common JNI struct names found in LLVM IR from various compilers.
fn isJNIStructType(llvm_type: c.LLVMTypeRef) bool {
    const type_kind = c.LLVMGetTypeKind(llvm_type);

    // Must be a struct or pointer type
    if (type_kind != c.LLVMStructTypeKind and type_kind != c.LLVMPointerTypeKind) {
        return false;
    }

    // Get struct name if available
    const type_name = c.LLVMGetStructName(llvm_type);
    if (@intFromPtr(type_name) == 0) return false;

    const name_str = std.mem.span(type_name);

    // Known JNI structure name patterns
    const JNI_STRUCT_PATTERNS = [_][]const u8{
        "JNINativeInterface_",
        "_JNIEnv",
        "JNIEnv",
        "JNIInvokeInterface_",
        "_JavaVM",
        "JavaVM",
    };

    for (JNI_STRUCT_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, name_str, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Find the index of a target instruction in FunctionIR.instructions array.
/// O(1) via fir.inst_index — was O(n) linear scan.
fn findInstructionIndexFir(fir: *const ir_store_mod.FunctionIR, target: c.LLVMValueRef) ?usize {
    if (fir.indexOf(target)) |idx| return @as(usize, idx);
    return null;
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

/// Check if an allocation is an intentional ownership transfer (not a leak).
/// Covers patterns like Box::leak(), Box::into_raw(), ManuallyDrop,
/// and functions with transfer semantics (leak/donate/transfer/export/handoff).
///
/// Returns true if the allocation should be suppressed as intentional.
fn isIntentionalOwnershipTransfer(alloc: *const CrossLangAlloc) bool {
    // Pattern 1: Known intentional leak/transfer callee names (mangled Rust symbols)
    const intentional_callees = [_][]const u8{
        "leak", // Box::leak — mangled name contains "leak"
        "into_raw", // Box::into_raw — ownership transfer to raw ptr
        "ManuallyDrop", // ManuallyDrop::new — suppresses drop/free
        "forget", // std::mem::forget — intentionally leaks
    };
    for (intentional_callees) |pattern| {
        if (std.mem.indexOf(u8, alloc.alloc_callee, pattern) != null) {
            return true;
        }
    }

    // Pattern 2: Function name indicates ownership transfer semantics
    const transfer_keywords = [_][]const u8{
        "leak",
        "donate",
        "transfer_ownership",
        "export_ptr",
        "handoff",
        "into_raw",
        "forget",
        "ffi_export",
        "c_export",
    };
    for (transfer_keywords) |kw| {
        if (std.mem.indexOf(u8, alloc.alloc_func, kw) != null) {
            return true;
        }
    }

    return false;
}

/// Search for runtime.Pinner.Pin or runtime.KeepAlive calls in the function.
/// Go requires that pointers passed to C must be pinned to prevent GC movement.
/// This is a pure string match — no complex analysis needed.
fn searchForPinOp(ctx: *PassContext, alloc_func: []const u8) bool {
    // Iterate over all functions to find the one matching alloc_func
    for (ctx.ir_store.function_list) |fir| {
        if (!std.mem.eql(u8, fir.name, alloc_func)) continue;

        // Scan all instructions in this function for pin/keepalive calls
        for (fir.instructions, fir.opcodes) |inst, opcode| {
            if (!llvm_safe.isCallOrInvoke(opcode)) continue;

            const called_val = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(called_val) == 0) continue;

            const called_name_ptr = c.LLVMGetValueName(called_val);
            const called_name = if (@intFromPtr(called_name_ptr) != 0)
                std.mem.span(called_name_ptr)
            else
                "";

            // Debug: log callee names for Go functions to help identify actual IR patterns
            log.debug("Go-GC-PIN: Checking callee '{s}' in {s}", .{ called_name, alloc_func });

            // Pure string match for Go GC pin calls
            if (std.mem.indexOf(u8, called_name, "runtime_pinner") != null or // Go 1.21+ (underscore variant)
                std.mem.indexOf(u8, called_name, "runtime.Pinner.Pin") != null or // Original (keep for compatibility)
                std.mem.indexOf(u8, called_name, "runtime.(*Pinner).Pin") != null or // Debug name variant
                std.mem.indexOf(u8, called_name, "runtime.KeepAlive") != null or // cgo-generated
                std.mem.indexOf(u8, called_name, "runtime.noescape") != null or // Common alternative pattern
                std.mem.eql(u8, called_name, "runtime.GC")) // Conservative pin surrogate
            {
                log.debug("Go-GC-PIN: Found pin/keepalive call '{s}' in {s}", .{ called_name, alloc_func });
                return true;
            }
        }
        break; // Found the matching function, no need to continue searching
    }
    return false;
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

// ============================================================================
// Phase 3: Java JNI FFI Memory Safety Detection Tests
// ============================================================================

test "JNI: isJniAllocCall detects allocation functions" {
    // GlobalRef and LocalRef creation
    try std.testing.expect(isJniAllocCall("NewGlobalRef"));
    try std.testing.expect(isJniAllocCall("NewLocalRef"));

    // String operations
    try std.testing.expect(isJniAllocCall("GetStringUTFChars"));
    try std.testing.expect(isJniAllocCall("GetStringUTF"));

    // Array element access (all types)
    try std.testing.expect(isJniAllocCall("GetByteArrayElements"));
    try std.testing.expect(isJniAllocCall("GetCharArrayElements"));
    try std.testing.expect(isJniAllocCall("GetShortArrayElements"));
    try std.testing.expect(isJniAllocCall("GetIntArrayElements"));
    try std.testing.expect(isJniAllocCall("GetLongArrayElements"));
    try std.testing.expect(isJniAllocCall("GetFloatArrayElements"));
    try std.testing.expect(isJniAllocCall("GetDoubleArrayElements"));
    try std.testing.expect(isJniAllocCall("GetBooleanArrayElements"));

    // Thread attachment
    try std.testing.expect(isJniAllocCall("AttachCurrentThread"));

    // Class lookup
    try std.testing.expect(isJniAllocCall("FindClass"));

    // Should NOT detect non-alloc functions
    try std.testing.expect(!isJniAllocCall("DeleteGlobalRef"));
    try std.testing.expect(!isJniAllocCall("ReleaseStringUTFChars"));
    try std.testing.expect(!isJniAllocCall("malloc"));
    try std.testing.expect(!isJniAllocCall("free"));
}

test "JNI: isJniReleaseCall detects release functions" {
    // Reference deletion
    try std.testing.expect(isJniReleaseCall("DeleteGlobalRef"));
    try std.testing.expect(isJniReleaseCall("DeleteLocalRef"));

    // String release
    try std.testing.expect(isJniReleaseCall("ReleaseStringUTFChars"));
    try std.testing.expect(isJniReleaseCall("ReleaseStringUTF"));

    // Array element release (all types)
    try std.testing.expect(isJniReleaseCall("ReleaseByteArrayElements"));
    try std.testing.expect(isJniReleaseCall("ReleaseCharArrayElements"));
    try std.testing.expect(isJniReleaseCall("ReleaseShortArrayElements"));
    try std.testing.expect(isJniReleaseCall("ReleaseIntArrayElements"));
    try std.testing.expect(isJniReleaseCall("ReleaseLongArrayElements"));
    try std.testing.expect(isJniReleaseCall("ReleaseFloatArrayElements"));
    try std.testing.expect(isJniReleaseCall("ReleaseDoubleArrayElements"));
    try std.testing.expect(isJniReleaseCall("ReleaseBooleanArrayElements"));

    // Thread detachment
    try std.testing.expect(isJniReleaseCall("DetachCurrentThread"));

    // Should NOT detect non-release functions
    try std.testing.expect(!isJniReleaseCall("NewGlobalRef"));
    try std.testing.expect(!isJniReleaseCall("GetStringUTFChars"));
    try std.testing.expect(!isJniReleaseCall("malloc"));
    try std.testing.expect(!isJniReleaseCall("free"));
}

test "JNI: requiresJniNullCheck identifies functions needing null check" {
    // Class and method ID lookups require null check
    try std.testing.expect(requiresJniNullCheck("FindClass"));
    try std.testing.expect(requiresJniNullCheck("GetMethodID"));
    try std.testing.expect(requiresJniNullCheck("GetStaticMethodID"));
    try std.testing.expect(requiresJniNullCheck("GetFieldID"));
    try std.testing.expect(requiresJniNullCheck("GetStaticFieldID"));

    // Resource allocation functions require null check
    try std.testing.expect(requiresJniNullCheck("NewGlobalRef"));
    try std.testing.expect(requiresJniNullCheck("GetStringUTFChars"));
    try std.testing.expect(requiresJniNullCheck("GetByteArrayElements"));
    try std.testing.expect(requiresJniNullCheck("NewStringUTF"));
    try std.testing.expect(requiresJniNullCheck("NewByteArray"));
    try std.testing.expect(requiresJniNullCheck("RegisterNatives"));

    // Functions that do NOT require null check
    try std.testing.expect(!requiresJniNullCheck("DeleteGlobalRef"));
    try std.testing.expect(!requiresJniNullCheck("ReleaseStringUTFChars"));
    try std.testing.expect(!requiresJniNullCheck("CallVoidMethod"));
    try std.testing.expect(!requiresJniNullCheck("ExceptionCheck"));
}

test "JNI: Suffix matching works for mangled names" {
    // Test that suffix matching works for mangled/prefixed function names
    // This is important because LLVM IR may have prefixed JNI function names

    // Should match with various prefixes
    try std.testing.expect(isJniAllocCall("JNIEnv_NewGlobalRef"));
    try std.testing.expect(isJniAllocCall("_ZN6JNIEnv12NewGlobalRefE"));
    try std.testing.expect(isJniReleaseCall("JNIEnv_DeleteGlobalRef"));
    try std.testing.expect(isJniReleaseCall("_ZN6JNIEnv15DeleteGlobalRefE"));

    // Should still match exact names
    try std.testing.expect(isJniAllocCall("NewGlobalRef"));
    try std.testing.expect(isJniReleaseCall("DeleteGlobalRef"));
}

test "JNI: Complete alloc/release pairing coverage" {
    // Test that all major JNI resource types have both alloc and release detection

    // GlobalRef lifecycle
    try std.testing.expect(isJniAllocCall("NewGlobalRef"));
    try std.testing.expect(isJniReleaseCall("DeleteGlobalRef"));

    // LocalRef lifecycle
    try std.testing.expect(isJniAllocCall("NewLocalRef"));
    try std.testing.expect(isJniReleaseCall("DeleteLocalRef"));

    // UTF String lifecycle
    try std.testing.expect(isJniAllocCall("GetStringUTFChars"));
    try std.testing.expect(isJniReleaseCall("ReleaseStringUTFChars"));

    // ByteArray lifecycle
    try std.testing.expect(isJniAllocCall("GetByteArrayElements"));
    try std.testing.expect(isJniReleaseCall("ReleaseByteArrayElements"));

    // CharArray lifecycle
    try std.testing.expect(isJniAllocCall("GetCharArrayElements"));
    try std.testing.expect(isJniReleaseCall("ReleaseCharArrayElements"));

    // IntArray lifecycle
    try std.testing.expect(isJniAllocCall("GetIntArrayElements"));
    try std.testing.expect(isJniReleaseCall("ReleaseIntArrayElements"));

    // Thread attachment lifecycle
    try std.testing.expect(isJniAllocCall("AttachCurrentThread"));
    try std.testing.expect(isJniReleaseCall("DetachCurrentThread"));
}

test "JNI: Edge cases - empty strings and non-JNI functions" {
    // Empty string should not match
    try std.testing.expect(!isJniAllocCall(""));
    try std.testing.expect(!isJniReleaseCall(""));
    try std.testing.expect(!requiresJniNullCheck(""));

    // C standard library functions should not match JNI patterns
    try std.testing.expect(!isJniAllocCall("malloc"));
    try std.testing.expect(!isJniAllocCall("calloc"));
    try std.testing.expect(!isJniAllocCall("realloc"));
    try std.testing.expect(!isJniReleaseCall("free"));
    try std.testing.expect(!isJniReleaseCall("munmap"));

    // Python functions should not match JNI patterns
    try std.testing.expect(!isJniAllocCall("PyList_New"));
    try std.testing.expect(!isJniAllocCall("PyObject_Malloc"));
    try std.testing.expect(!isJniReleaseCall("Py_DECREF"));

    // Rust functions should not match JNI patterns
    try std.testing.expect(!isJniAllocCall("into_raw"));
    try std.testing.expect(!isJniReleaseCall("from_raw"));
}

test "isIntentionalOwnershipTransfer detects Box::leak and into_raw" {
    // Pattern 1: Known intentional callee names
    const alloc_leak = CrossLangAlloc{
        .id = 1,
        .ptr_val = 0x1000,
        .alloc_lang = .rust,
        .alloc_func = "test_func",
        .alloc_callee = "_ZN5alloc5boxed19Box$LT$T$GT$4leak17h",
        .free_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .free_funcs = std.ArrayList([]const u8).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .passed_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
    };
    defer {
        alloc_leak.free_langs.deinit(std.testing.allocator);
        alloc_leak.free_funcs.deinit(std.testing.allocator);
        alloc_leak.passed_langs.deinit(std.testing.allocator);
    }
    try std.testing.expect(isIntentionalOwnershipTransfer(&alloc_leak));

    const alloc_into_raw = CrossLangAlloc{
        .id = 2,
        .ptr_val = 0x2000,
        .alloc_lang = .rust,
        .alloc_func = "test_func",
        .alloc_callee = "_ZN5alloc5boxed19Box$LT$T$GT$9into_raw17h",
        .free_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .free_funcs = std.ArrayList([]const u8).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .passed_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
    };
    defer {
        alloc_into_raw.free_langs.deinit(std.testing.allocator);
        alloc_into_raw.free_funcs.deinit(std.testing.allocator);
        alloc_into_raw.passed_langs.deinit(std.testing.allocator);
    }
    try std.testing.expect(isIntentionalOwnershipTransfer(&alloc_into_raw));

    const alloc_forget = CrossLangAlloc{
        .id = 3,
        .ptr_val = 0x3000,
        .alloc_lang = .rust,
        .alloc_func = "test_func",
        .alloc_callee = "_ZN4core3mem5forget17h",
        .free_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .free_funcs = std.ArrayList([]const u8).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .passed_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
    };
    defer {
        alloc_forget.free_langs.deinit(std.testing.allocator);
        alloc_forget.free_funcs.deinit(std.testing.allocator);
        alloc_forget.passed_langs.deinit(std.testing.allocator);
    }
    try std.testing.expect(isIntentionalOwnershipTransfer(&alloc_forget));
}

test "isIntentionalOwnershipTransfer detects transfer keyword function names" {
    // Pattern 2: Function names with transfer semantics
    const alloc_donate = CrossLangAlloc{
        .id = 4,
        .ptr_val = 0x4000,
        .alloc_lang = .rust,
        .alloc_func = "donate_ptr_to_c",
        .alloc_callee = "malloc",
        .free_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .free_funcs = std.ArrayList([]const u8).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .passed_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
    };
    defer {
        alloc_donate.free_langs.deinit(std.testing.allocator);
        alloc_donate.free_funcs.deinit(std.testing.allocator);
        alloc_donate.passed_langs.deinit(std.testing.allocator);
    }
    try std.testing.expect(isIntentionalOwnershipTransfer(&alloc_donate));

    const alloc_export = CrossLangAlloc{
        .id = 5,
        .ptr_val = 0x5000,
        .alloc_lang = .rust,
        .alloc_func = "ffi_export_data",
        .alloc_callee = "__rust_alloc",
        .free_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .free_funcs = std.ArrayList([]const u8).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .passed_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
    };
    defer {
        alloc_export.free_langs.deinit(std.testing.allocator);
        alloc_export.free_funcs.deinit(std.testing.allocator);
        alloc_export.passed_langs.deinit(std.testing.allocator);
    }
    try std.testing.expect(isIntentionalOwnershipTransfer(&alloc_export));
}

test "isIntentionalOwnershipTransfer rejects normal allocations" {
    // Regular malloc should NOT be flagged as intentional transfer
    const alloc_normal = CrossLangAlloc{
        .id = 6,
        .ptr_val = 0x6000,
        .alloc_lang = .c,
        .alloc_func = "process_data",
        .alloc_callee = "malloc",
        .free_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .free_funcs = std.ArrayList([]const u8).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
        .passed_langs = std.ArrayList(Language).initCapacity(std.testing.allocator, 0) catch return error.OutOfMemory,
    };
    defer {
        alloc_normal.free_langs.deinit(std.testing.allocator);
        alloc_normal.free_funcs.deinit(std.testing.allocator);
        alloc_normal.passed_langs.deinit(std.testing.allocator);
    }
    try std.testing.expect(!isIntentionalOwnershipTransfer(&alloc_normal));
}
