//! C++ False Positive Reduction System
//!
//! 8-layer filter system to eliminate false positives in C++ analysis:
//! L1: STL internal function filter
//! L2: C++ special member function filter
//! L3: RAII smart pointer detection
//! L4: RAII function set tracking
//! L5: C++ ABI runtime filter
//! L6: Meyers singleton detection
//! L7: C++ operator FFI filter
//! L8: Reference-counted container detection
//!
//! Also contains leak/null-deref/UAF/double-free detection passes.
//! Extracted from pointer_ownership.zig per rules.md line limit (≤1000 lines).

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const ffi_language_classifier = @import("../ffi/ffi_language_classifier.zig");

const PassContext = @import("../../../pass/pass.zig").PassContext;
const DiagnosticWriter = @import("../../../pass/pass.zig").DiagnosticWriter;
const noise_filter = @import("../../../semantics/noise_filter.zig");
const Issue = @import("../../../diag/issue.zig").Issue;
const Severity = @import("../../../diag/issue.zig").Severity;
const Confidence = @import("../../../diag/issue.zig").Confidence;
const Location = @import("../../../diag/issue.zig").Location;
const Language = @import("../../../diag/issue.zig").FFIBoundary.Language;
const FactKind = @import("../../../fact/fact.zig").FactKind;
const SemanticRegistry = @import("../../../registry/semantic_registry.zig").SemanticRegistry;
const ownership_types = @import("../../../types/ownership_types.zig");
const AllocSite = ownership_types.AllocSite;
const FreeSite = ownership_types.FreeSite;
const OwnershipStats = ownership_types.OwnershipStats;
const OwnershipState = ownership_types.OwnershipState;
const OwnershipViolationType = ownership_types.OwnershipViolationType;
const ValueIdMap = @import("../../../dataflow/value_id_map.zig").ValueIdMap;
const NullCheckRecognizer = @import("../../../dataflow/null_check_guard.zig").NullCheckRecognizer;
const PathManager = @import("../../../dataflow/path_condition.zig").PathManager;
const lifetime = @import("../../../lifetime/root.zig");
const noise_reduction = @import("noise_reduction.zig");

// Helpers from centralized types module
const cpp_helpers = @import("cpp_fp_helpers.zig");

// Extracted types and pure functions
const cpp_types = @import("../../../types/cpp_fp_types.zig");

// Extracted detection functions (double-free + memory leak)
const cpp_detect = @import("cpp_fp_detect.zig");

const isStlInternalFunction = cpp_helpers.isStlInternalFunction;
const isCppSpecialMemberFunction = cpp_helpers.isCppSpecialMemberFunction;
const isRustDropGlue = cpp_helpers.isRustDropGlue;
pub const detectAsPtrBorrowEscape = cpp_helpers.detectAsPtrBorrowEscape;
const isLocalRustValue = cpp_helpers.isLocalRustValue;
const isCppNewAllocation = cpp_helpers.isCppNewAllocation;
const isCppAbiInternalFunction = cpp_helpers.isCppAbiInternalFunction;
const isMeyersSingletonPattern = cpp_helpers.isMeyersSingletonPattern;
const is_likely_intentional_pattern = cpp_helpers.is_likely_intentional_pattern;
const ptr_lifetime_utils = @import("../ptr_lifetime/ptr_lifetime_utils.zig");
const isIntentionalOwnershipTransfer = ptr_lifetime_utils.isIntentionalOwnershipTransfer;
pub const isAllocationByName = cpp_helpers.isAllocationByName;
const isKnownRcContainerFunction = cpp_helpers.isKnownRcContainerFunction;
const isRefCountOperation = cpp_helpers.isRefCountOperation;
const markAsRcFunction = cpp_helpers.markAsRcFunction;
pub const detectRaiiManagedAllocations = cpp_helpers.detectRaiiManagedAllocations;
pub const detectMeyersSingletonFunctions = cpp_helpers.detectMeyersSingletonFunctions;
pub const detectRefCountedContainerFunctions = cpp_helpers.detectRefCountedContainerFunctions;

// Re-exported from cpp_fp_types.zig
const isNullableAllocation = cpp_types.isNullableAllocation;
pub const getFunctionName = cpp_types.getFunctionName;
const identifyLanguage = cpp_types.identifyLanguage;
const isGuardedByNullCheck = cpp_types.isGuardedByNullCheck;
const isLikelyStructMemberOwnership = cpp_types.isLikelyStructMemberOwnership;
const convertLanguageToHint = cpp_types.convertLanguageToHint;
const isCrossFFIAllocation = ownership_types.isCrossFFIAllocation;
const canReach = @import("../../../dataflow/graph_algorithms.zig").canReach;
const isRustIntoRawCall = cpp_types.isRustIntoRawCall;
const isRustFromRawCall = cpp_types.isRustFromRawCall;
const isRustAsPtrCall = @import("../rust_ffi/rust_ffi_helpers.zig").isRustAsPtrCall;
const PtrInfo = cpp_types.PtrInfo;
pub const detectStructMemberStores = cpp_types.detectStructMemberStores;
pub const detectRustFfiPairingFunctions = cpp_types.detectRustFfiPairingFunctions;
const findFreePath = cpp_types.findFreePath;
const hasUseAfterFree = cpp_types.hasUseAfterFree;
const detectLoopLeaks = cpp_types.detectLoopLeaks;
const detectResourceLeaks = cpp_types.detectResourceLeaks;

// Re-exported from cpp_fp_detect.zig
pub const detectDoubleFree = cpp_detect.detectDoubleFree;
pub const detectMemoryLeaks = cpp_detect.detectMemoryLeaks;

/// Precise compiler-internal function detection for UAF suppression.
///
/// IMPORTANT: This is a PRECISE whitelist — only confirmed internal
/// patterns are matched. User functions (even when mangled) must NOT
/// be matched to avoid skipping real UAF bugs in user code.
///
/// See: issue_suppression.zig isCompilerInternalFunction() for the
/// canonical implementation and detailed rationale.
fn isCompilerInternalFunctionForUAF(func_name: []const u8) bool {
    const internal_patterns = [_][]const u8{
        // C++ standard library internals
        "_ZNSt", // std::
        "_ZN9__gnu_cxx", // __gnu_cxx::

        // Rust core/alloc internals (standard library only)
        "_ZN4core", // core::
        "_ZN5alloc", // alloc::

        // Rust v0 mangling for standard library
        "_RN4core", // _RNvC<crate>4core...
        "_RN5alloc", // _RNvC<crate>5alloc...

        // Global initialization guards (Itanium ABI)
        "_ZGV",
        "_ZZ",

        // Compiler builtins and intrinsics (always safe)
        "__rust_",
        "__rdl_",
        "__rg_",
        "__cxx_",

        // Global constructors/destructors
        "_GLOBAL__",

        // Swift runtime
        "$ss",
        "$sS",
    };

    for (internal_patterns) |pattern| {
        if (std.mem.startsWith(u8, func_name, pattern)) return true;
    }

    return false;
}

pub fn detectNullDereferences(
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

        if (!isNullableAllocation(alloc_info.func_name)) continue;

        // Skip if the pointer is never used (no aliases in flow graph).
        // A pointer that is allocated but never dereferenced cannot cause a null deref.
        if (flow_graph.get(alloc_info.ptr_value_id)) |aliases| {
            if (aliases.count() == 0) continue;
        } else {
            // No entry in flow graph means the pointer was never used at all.
            continue;
        }

        const is_guarded = isFunctionLevelNullGuarded(recognizer, alloc_info.ptr_value_id, flow_graph) catch continue;
        if (!is_guarded) {
            const func_ptr_key = @intFromPtr(alloc_info.func_name.ptr);
            if (reported_funcs.contains(func_ptr_key)) continue;

            const vulnerability_id = ctx.getNextVulnId();
            ctx.addIssue(&Issue.init(
                .null_dereference,
                "Potential null dereference: pointer used without null check",
                Location.init(alloc_info.func_name),
                .critical,
                0.85,
            )) catch {
                diag.warn("Failed to register null_deref issue", .{});
            };
            diag.err("VULNERABILITY OMI-{d:0>3} [critical] [Confidence: {s}]", .{ vulnerability_id, @tagName(Confidence.fromScore(0.85)) });
            diag.err("Type: null_dereference", .{});
            diag.err("Reason: allocation may return NULL, used without null guard", .{});

            reported_funcs.put(func_ptr_key, {}) catch {
                diag.warn("Null dedup map insert failed", .{});
            };
        }
    }
}

pub fn isFunctionLevelNullGuarded(
    recognizer: *NullCheckRecognizer,
    ptr_value_id: u32,
    flow_graph: *const std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
) !bool {
    if (recognizer.isPtrGuardedNonNull_byValue(ptr_value_id)) return true;

    var visited = std.AutoHashMap(u32, void).init(recognizer.allocator);
    defer visited.deinit();

    var bfs_queue = try std.ArrayList(u32).initCapacity(recognizer.allocator, 64);
    defer bfs_queue.deinit(recognizer.allocator);
    try bfs_queue.append(recognizer.allocator, ptr_value_id);

    while (bfs_queue.items.len > 0) {
        const current = bfs_queue.orderedRemove(0);
        if (visited.contains(current)) continue;
        try visited.put(current, {});

        if (recognizer.isPtrGuardedNonNull_byValue(current)) return true;

        if (flow_graph.get(current)) |flows| {
            var iter = flows.iterator();
            while (iter.next()) |entry| {
                const alias_id = entry.key_ptr.*;
                if (!visited.contains(alias_id)) {
                    try bfs_queue.append(recognizer.allocator, alias_id);
                }
            }
        }
    }
    return false;
}

/// Detect use-after-free: pointer used after being freed.
/// v0.1.7 FIX: Deduplication — each unique (freed_ptr, function) pair reports
/// at most 1 UAF. Previously, every flow edge from a freed pointer was counted
/// separately, causing 10x count inflation (e.g., 10 UAFs for 1 real bug).
///
/// Three-tier detection approach:
/// - Tier 1: Danger path detection (existing) - FFI boundaries, cross-language
/// - Tier 2: Language-internal patterns (new) - Raw pointer misuse within same function
pub fn detectUseAfterFree(
    ctx: *PassContext,
    free_map: *std.AutoHashMap(u32, *FreeSite),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    stats: *OwnershipStats,
    diag: *DiagnosticWriter,
) void {
    // Dedup set: each (ptr_id) reports at most once.
    var reported = std.AutoHashMap(u32, void).init(free_map.allocator);
    defer reported.deinit();

    var free_iter = free_map.iterator();
    while (free_iter.next()) |entry| {
        const free_info = entry.value_ptr.*;
        const ptr_id = free_info.ptr_value_id;

        // Skip if already reported for this ptr (dedup).
        if (reported.contains(ptr_id)) continue;

        // P1 Enhancement: Skip UAF in Rust's guaranteed-safe drop glue.
        if (isRustDropGlue(free_info.func_name)) {
            diag.debug("UAF-SKIP: {s} is Rust drop_in_place — guaranteed safe by ownership system", .{free_info.func_name});
            continue;
        }

        // SRT (Semantic Resolution Tree) filter:
        // If the function containing the free is semantically resolved as a release
        // (e.g., drop_in_place, __rust_dealloc), the subsequent use is part of the
        // language's normal destructor sequence — not a real UAF. Skip it.
        if (ctx.semantic_resolution) |engine| {
            if (engine.isSemanticallyRelease(free_info.func_name)) {
                diag.debug("UAF-SKIP: {s} is semantically resolved as release — language-guaranteed destructor", .{free_info.func_name});
                continue;
            }
        }

        const classification = ctx.classifyFunctionSurface(free_info.func_name, null);
        if (!classification.origin.shouldReportByDefault()) {
            diag.debug("UAF-SKIP: {s} is {s} — {s}", .{ free_info.func_name, classification.origin.toString(), classification.reason });
            continue;
        }

        // Skip functions with intentional/test pattern prefixes (correct_, valid_, etc.)
        if (is_likely_intentional_pattern(free_info.func_name)) {
            diag.debug("UAF-SKIP: {s} has known-safe function name prefix", .{free_info.func_name});
            continue;
        }

        const is_rust_mangled = std.mem.startsWith(u8, free_info.func_name, "_R") or
            (std.mem.startsWith(u8, free_info.func_name, "_ZN") and
                ffi_language_classifier.isRustMangledName(free_info.func_name));
        const is_explicitly_unsafe = std.mem.indexOf(u8, free_info.func_name, "unsafe") != null or
            std.mem.indexOf(u8, free_info.func_name, "unchecked") != null or
            std.mem.indexOf(u8, free_info.func_name, "raw") != null;
        if (is_rust_mangled and !is_explicitly_unsafe) {
            diag.debug("UAF-SKIP: {s} is Rust safe code — ownership system guarantees memory safety", .{free_info.func_name});
            continue;
        }

        // ── Tier 1: Danger path detection (existing logic) ──
        // P2 FIX: Use MemoryGraph.isOnDangerPath to filter out UAF reports
        // for pointers that are NOT on FFI/unsafe danger paths.
        // Pure C/C++ internal UAF (same-language, no FFI boundary) is a
        // generic bug, not an FFI/unsafe vulnerability. The flow_graph
        // generates too many false edges from memcpy/store operations
        // that don't represent actual pointer reuse after free.
        // Only report UAF when the freed pointer was on a danger path
        // (cross-language lifecycle, FFI arg/ret, unsafe zone alloc).
        const mg_danger = ctx.isOnDangerPathFull(@as(u64, ptr_id));

        var uaf_found = false;
        var flow_iter = flow_graph.iterator();
        while (flow_iter.next()) |flow_entry| {
            const from_id = flow_entry.key_ptr.*;

            if (from_id == ptr_id) {
                const flows = flow_entry.value_ptr;
                var target_iter = flows.iterator();
                while (target_iter.next()) |target_entry| {
                    const to_id = target_entry.key_ptr.*;

                    if (!free_map.contains(to_id)) {
                        uaf_found = true;
                        break;
                    }
                }
                if (uaf_found) break;
            }
        }

        if (uaf_found) {
            // Determine confidence based on tier
            var confidence: f32 = 0.8; // Base confidence for Tier 1

            if (!mg_danger) {
                // ── Tier 2: Language-internal UAF (lower confidence) ──
                // Non-danger path UAF still detected but with reduced confidence
                // to balance detection coverage vs false positive rate
                confidence *= 0.6; // Reduce from 0.8 to 0.48

                // Boost confidence for high-risk patterns
                if (isHighRiskInternalUAF(free_info.func_name)) {
                    confidence += 0.25; // Boost to 0.73
                }

                // Additional boost for explicit free-then-use in same function
                if (isSameFunctionFreeThenUse(ptr_id, free_map, flow_graph)) {
                    confidence += 0.15; // Boost to ~0.88 for clear pattern A
                }

                diag.debug("UAF-TIER2: ptr {d} internal UAF with confidence {:.2}", .{ ptr_id, confidence });
            }

            // Only report if confidence meets threshold (0.75+)
            if (confidence >= 0.75) {
                stats.use_after_frees += 1;
                const severity: Severity = if (mg_danger) .high else .medium;
                ctx.addIssue(&Issue.init(.use_after_free, "Pointer used after being freed", Location.init(free_info.func_name), severity, confidence)) catch {
                    diag.warn("Failed to register use_after_free issue", .{});
                };
                diag.warn("USE-AFTER-FREE [{s}]: Pointer {d} used after free in {s} (confidence: {d:.2})", .{ @tagName(severity), ptr_id, free_info.func_name, confidence });
                reported.put(ptr_id, {}) catch {};
            } else {
                diag.debug("UAF-SKIP: ptr {d} confidence too low ({:.2} < 0.75)", .{ ptr_id, confidence });
            }
        }
    }
}

/// Check if this function shows high-risk internal UAF patterns.
/// Functions with names suggesting manual memory management or raw pointer usage
/// get a confidence boost.
pub fn isHighRiskInternalUAF(func_name: []const u8) bool {
    const risky_patterns = [_][]const u8{
        "raw_",     "unsafe_", "unchecked_", "manual_",
        "c_style_", "legacy_",
    };

    for (risky_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Check if there's a clear free-then-use pattern in the same function (Pattern A).
/// This detects simple cases where programmer forgot about the free:
///   ptr = malloc(...); ... free(ptr); ... use(ptr);
fn isSameFunctionFreeThenUse(
    ptr_id: u32,
    _: *std.AutoHashMap(u32, *FreeSite),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
) bool {
    // Check if the freed pointer has direct uses (not just aliases)
    if (flow_graph.get(ptr_id)) |flows| {
        // If pointer has multiple outgoing flows after being freed,
        // it's likely used directly (Pattern A)
        return flows.count() > 0;
    }

    return false;
}

/// Detect memory leaks, double-free, and use-after-free.
pub fn detectMemoryIssues(
    ctx: *PassContext,
    alloc_map: *std.AutoHashMap(u32, *AllocSite),
    free_map: *std.AutoHashMap(u32, *FreeSite),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    stats: *OwnershipStats,
    diag: *DiagnosticWriter,
) void {
    detectMemoryLeaks(ctx, alloc_map, free_map, flow_graph, stats, diag);
    detectDoubleFree(ctx, free_map, stats, diag) catch {};
    detectUseAfterFree(ctx, free_map, flow_graph, stats, diag);
}

/// Detect ownership violations using flow graph and boundary analyzer.
pub fn detectViolations(
    ctx: *PassContext,
    alloc_map: *std.AutoHashMap(u32, *AllocSite),
    free_map: *std.AutoHashMap(u32, *FreeSite),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    stats: *OwnershipStats,
    diag: *DiagnosticWriter,
    boundary_analyzer: *lifetime.BoundaryAnalyzer,
    lifetime_engine: *lifetime.LifetimeEngine,
) !void {
    var alloc_iter = alloc_map.iterator();
    while (alloc_iter.next()) |entry| {
        const alloc = entry.value_ptr.*;

        const lang_hint = convertLanguageToHint(alloc.lang);
        if (lifetime_engine.applyAction(
            .alloc,
            alloc.func_name,
            if (alloc.debug_file) |file|
                .{ .file = file, .func = alloc.func_name, .line = alloc.debug_line orelse 0, .column = alloc.debug_column orelse 0 }
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

        if (isCrossFFIAllocation(alloc.lang)) {
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
                            .{ .file = file, .func = alloc.func_name, .line = alloc.debug_line orelse 0, .column = alloc.debug_column orelse 0 }
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
                    } else if (isIntentionalOwnershipTransfer(alloc.func_name)) {
                        // Suppress FP: intentional ownership transfer (e.g., Box::leak → C free)
                        diag.info("[SUPPRESSED] Ownership violation in {s}: intentional ownership transfer detected", .{alloc.func_name});
                        continue; // Skip fact_store insert + stats increment below
                    } else if (boundary_analyzer.checkOwnershipViolation(
                        resource_fact,
                        .free,
                        free_lang_hint,
                        boundary_analyzer.boundaries.items[boundary_id - 1],
                    )) |violation| {
                        diag.warn("CROSS-LANGUAGE OWNERSHIP VIOLATION DETECTED", .{});
                        diag.warn("  Type: {s}", .{@tagName(violation.kind)});
                        diag.warn("  Alloc: {s} ({s}) at inst {}", .{
                            alloc_loc.func,
                            @tagName(alloc.lang),
                            alloc.inst_id,
                        });
                        diag.warn("  Free: {s} ({s}) at inst {}", .{
                            free_loc.func,
                            @tagName(free_site.lang),
                            free_site.inst_id,
                        });
                        const desc = try lifetime.formatViolationMessage(ctx.allocator, violation.kind, violation.origin_lang, violation.action_lang);
                        defer ctx.allocator.free(desc);
                        diag.warn("  Description: {s}", .{desc});
                    } else {
                        diag.warn("CROSS-LANGUAGE OWNERSHIP VIOLATION DETECTED", .{});
                        diag.warn("  Alloc: {s} ({s}) at inst {}", .{
                            alloc_loc.func,
                            @tagName(alloc.lang),
                            alloc.inst_id,
                        });
                        diag.warn("  Free: {s} ({s}) at inst {}", .{
                            free_loc.func,
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

// ==================== Rust FFI Pair Detection (Task 9.3) ====================

/// Detect cross-language allocation/deallocation mismatches (Task 9.3d).
/// Pattern 1: Rust global alloc (_Znwm/__rust_alloc) result freed by C free()
/// Pattern 2: C malloc() result reclaimed by Box::from_raw (correct but worth noting)
///
/// fix: Also detect Rust-alloc/C-free when the alloc is classified as .cpp
/// (because _Znwm is shared between Rust and C++ — in a Rust module, _Znwm is Rust).
/// Uses module language from PassContext to disambiguate.
pub fn detectCrossLangAllocMismatch(
    ctx: *PassContext,
    alloc_map: *std.AutoHashMap(u32, *AllocSite),
    free_map: *std.AutoHashMap(u32, *FreeSite),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    diag: *DiagnosticWriter,
) void {
    // Determine if _Znwm (classified as .cpp) should be treated as Rust.
    // This happens when the module language is Rust — Rust's std::alloc::alloc
    // compiles to _Znwm at LLVM IR level.
    const module_lang = ctx.module_language.language;
    const rust_alloc_via_cpp = (module_lang == .rust);

    var alloc_iter = alloc_map.iterator();
    while (alloc_iter.next()) |entry| {
        const alloc = entry.value_ptr.*;

        // Accept alloc if it's explicitly .rust, or if it's .cpp in a Rust module
        // (where _Znwm is actually Rust's global allocator, not C++ operator new).
        const is_rust_alloc = alloc.lang == .rust or
            (alloc.lang == .cpp and rust_alloc_via_cpp);
        if (!is_rust_alloc) continue;

        var free_iter = free_map.iterator();
        while (free_iter.next()) |free_entry| {
            const free_site = free_entry.value_ptr.*;

            if (free_site.lang != .c) continue;
            if (free_site.free_type != .free) continue;

            var visited = std.AutoHashMap(u32, void).init(ctx.allocator);
            defer visited.deinit();

            const flows_to_free = canReach(flow_graph, alloc.ptr_value_id, free_site.ptr_value_id, &visited);
            if (!flows_to_free) continue;

            // Suppress FP: intentional ownership transfer (e.g., Box::leak → C free)
            if (isIntentionalOwnershipTransfer(alloc.func_name)) {
                diag.info("[SUPPRESSED] Cross-lang alloc mismatch in {s}: intentional ownership transfer", .{alloc.func_name});
                continue;
            }

            const vuln_id = ctx.getNextVulnId();
            ctx.addIssue(&Issue.initWithReason(
                .cross_language_leak,
                "Cross-language alloc mismatch: Rust-alloc freed by C free()",
                Location.init(alloc.func_name),
                .high,
                0.85,
                "Rust global_alloc (_Znwm) result freed by C free() - allocator mismatch",
            )) catch {
                diag.warn("Failed to register cross-lang mismatch issue", .{});
            };
            diag.err("CROSS-LANG MISMATCH OMI-{d:0>3} [{s}] [Confidence: {s}]", .{ vuln_id, @tagName(.high), @tagName(Confidence.fromScore(0.85)) });
            diag.err("Type: cross_language_alloc_mismatch", .{});
            diag.err("Reason: Rust _Znwm allocation freed by C free() - heap mismatch", .{});
        }
    }
}

// ============================================================================
// Tests: Precise compiler-internal function detection
// ============================================================================

test "isCompilerInternalFunctionForUAF - compiler internal functions are detected" {
    // C++ standard library
    try std.testing.expect(isCompilerInternalFunctionForUAF("_ZNSt6vectorIiEE9push_backERKi"));
    try std.testing.expect(isCompilerInternalFunctionForUAF("_ZNSt9basic_stringIcE"));

    // Rust core/alloc internals
    try std.testing.expect(isCompilerInternalFunctionForUAF("_ZN4core3ptr13drop_in_place17hE"));
    try std.testing.expect(isCompilerInternalFunctionForUAF("_ZN5alloc6sync::ReentrantMutexE"));
    try std.testing.expect(isCompilerInternalFunctionForUAF("_RN4core3fmt::Formatter"));

    // Compiler intrinsics
    try std.testing.expect(isCompilerInternalFunctionForUAF("__rust_alloc"));
    try std.testing.expect(isCompilerInternalFunctionForUAF("__rdl_dealloc"));

    // Itanium ABI internals
    try std.testing.expect(isCompilerInternalFunctionForUAF("_ZGVN3foo3barE"));
    try std.testing.expect(isCompilerInternalFunctionForUAF("_GLOBAL__sub_I_main"));
}

test "isCompilerInternalFunctionForUAF - user mangled functions are NOT detected" {
    // User C++ class methods should NOT be matched
    try std.testing.expect(!isCompilerInternalFunctionForUAF("_ZN9my_app4mainE"));
    try std.testing.expect(!isCompilerInternalFunctionForUAF("_ZN3app7my_class12do_somethingE"));
    try std.testing.expect(!isCompilerInternalFunctionForUAF("_ZN6mylib4DataC1Ev"));

    // User Rust pub fn should NOT be matched
    try std.testing.expect(!isCompilerInternalFunctionForUAF("_ZN6mycrate4func17process_dataEv"));
    try std.testing.expect(!isCompilerInternalFunctionForUAF("_RNv6mycrate4func")); // Rust v0 user code

    // Non-mangled user functions
    try std.testing.expect(!isCompilerInternalFunctionForUAF("my_function"));
    try std.testing.expect(!isCompilerInternalFunctionForUAF("main"));
    try std.testing.expect(!isCompilerInternalFunctionForUAF("handle_request"));
}
