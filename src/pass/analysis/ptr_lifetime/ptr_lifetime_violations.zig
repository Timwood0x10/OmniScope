//! Violation detection functions for pointer lifetime analysis
//!
//! Extracted from ptr_lifetime.zig to improve code organization.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const log = @import("../../../common/log.zig");
const safe = @import("../../../ir/llvm_safe.zig"); // Issue2: Standardized LLVM helpers

const PassContext = @import("../../../pass/pass.zig").PassContext;
const DiagnosticWriter = @import("../../../pass/pass.zig").DiagnosticWriter;
const memory_graph = @import("../../../semantics/memory_graph.zig");
const family_mod = @import("../../../semantics/resource/family.zig");
const FamilyId = family_mod.FamilyId;
const FamilyMatchResult = family_mod.FamilyMatchResult;
const registry_mod = @import("../../../semantics/resource/family_registry.zig");
const ResourceFamilyRegistry = registry_mod.ResourceFamilyRegistry;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;
const Location = @import("../../../diag/issue.zig").Location;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;

const PtrInfo = @import("ptr_lifetime_types.zig").PtrInfo;
const LifetimeStats = @import("ptr_lifetime_types.zig").LifetimeStats;
const FreeSiteRecord = @import("ptr_lifetime_types.zig").FreeSiteRecord;
const FreeSiteList = @import("ptr_lifetime_types.zig").FreeSiteList;
const ResourceType = @import("ptr_lifetime_types.zig").ResourceType;
const LifetimeMap = @import("ptr_lifetime_types.zig").LifetimeMap;
const isAllocaAliveAt = @import("ptr_lifetime_types.zig").isAllocaAliveAt;

const isFreeFunction = @import("ptr_lifetime_classify.zig").isFreeFunction;
const classifyAllocLanguage = @import("ptr_lifetime_classify.zig").classifyAllocLanguage;
const classifyAllocLanguageEnum = @import("ptr_lifetime_classify.zig").classifyAllocLanguageEnum;
const classifyFreeLanguage = @import("ptr_lifetime_classify.zig").classifyFreeLanguage;

const report = @import("ptr_lifetime_report.zig");
const is_extern_function = @import("ptr_lifetime_types.zig").is_extern_function;
const word_boundary = @import("../../../utils/word_boundary.zig");

const ptr_utils = @import("ptr_lifetime_utils.zig");
const Lang = ptr_utils.Lang;
const toZoneLanguage = ptr_utils.toZoneLanguage;
const areMutuallyExclusive = ptr_utils.areMutuallyExclusive;
const isRCPatternFree = ptr_utils.isRCPatternFree;
const isGlobalVariable = ptr_utils.isGlobalVariable;
const isRustBorrowPattern = ptr_utils.isRustBorrowPattern;
const isCppDestructorOrConstructor = ptr_utils.isCppDestructorOrConstructor;
const isNonPointerReturnType = ptr_utils.isNonPointerReturnType;
const output_param_classifier = @import("../../../semantics/output_param_classifier.zig");
const NoiseReduction = @import("../noise/noise_reduction.zig");
const getAllocatorKB = @import("ptr_lifetime_types.zig").getAllocatorKB;
const HEAP_ALLOC_FUNCTIONS = @import("ptr_lifetime_types.zig").HEAP_ALLOC_FUNCTIONS;
const isIntentionalOwnershipTransfer = ptr_utils.isIntentionalOwnershipTransfer;

const reportHeapToGlobal = report.reportHeapToGlobal;
const reportStackToGlobal = report.reportStackToGlobal;
const reportFFINullGuardMissing = report.reportFFINullGuardMissing;
const reportCrossLanguageFree = report.reportCrossLanguageFree;
const reportFFITypeMismatch = report.reportFFITypeMismatch;
const reportReturnStackAddr = report.reportReturnStackAddr;
const reportReturnHeapPtr = report.reportReturnHeapPtr;
const reportBorrowEscapeFFI = report.reportBorrowEscapeFFI;
const reportUseAfterFree = report.reportUseAfterFree;
const reportStackEscape = report.reportStackEscape;
const reportHeapEscapeToFFI = report.reportHeapEscapeToFFI;
const reportResourceUAF = report.reportResourceUAF;

const ip_ffi = @import("../ip_ffi.zig");
const call_graph_mod = @import("../../../semantics/call_graph.zig");
const getCallInstArgCount = @import("../../../ir/llvm_safe.zig").getCallInstArgCount;
const may_retain_pointer = @import("ptr_lifetime_types.zig").may_retain_pointer;

// P17-2: Split out return violation helpers to keep file < 1000 lines
const return_helpers = @import("ptr_lifetime_return_helpers.zig");

/// Check if a store instruction stores a pointer to a global variable.
pub fn checkStoreToGlobal(
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

const AllocNode = @import("../../../types/memory_graph_types.zig").AllocNode;

/// Find a MemoryGraph node by scanning node_store for matching alloc_inst field.
/// O(N) scan — used only as fallback when findCanonicalAlloc fails.
/// This handles cases where the ptr_arg IS the call instruction itself
/// (same LLVMValueRef), but isn't indexed via the alias map.
fn findNodeByAllocInst(mg: *memory_graph.MemoryGraph, target_inst: u64) ?*AllocNode {
    for (mg.node_store.items) |node| {
        if (node.alloc_inst == target_inst) return node;
    }
    return null;
}

/// Check for cross-language free violations.
///
/// Uses the centralized classifyAllocLanguage/classifyFreeLanguage from
/// ptr_lifetime_classify.zig to support ALL registered allocator patterns
/// (C, Rust, C++, Go/cgo, ObjC, Python, JNI, Node.js) — not just
/// the hardcoded malloc/__rust_dealloc subset.
pub fn checkCrossLanguageFree(
    ctx: *PassContext,
    inst: c.LLVMValueRef,
    func_name: []const u8,
    pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
    mem_graph: ?*memory_graph.MemoryGraph,
    diag: *DiagnosticWriter,
    stats: *LifetimeStats,
) !void {
    _ = stats;
    const called = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called) == 0) return;

    const name_ptr = c.LLVMGetValueName(called);
    if (@intFromPtr(name_ptr) == 0) return;
    const callee_name = std.mem.span(name_ptr);

    // Use centralized classification (supports all languages)
    const free_lang = classifyFreeLanguage(callee_name);
    if (free_lang == null) return; // Not a known free function

    // Get the pointer argument (first argument of the free call).
    // LLVM C API operand layout for "call void @free(ptr %p)":
    //   operand 0 = %p (first argument), operand 1 = @free (callee)
    // Note: LLVMGetCalledValue() returns the callee; operand indices
    // start with arguments, NOT the callee.
    const ptr_arg = c.LLVMGetOperand(inst, 0);
    if (@intFromPtr(ptr_arg) == 0) {
        log.debug("CROSS-LANG-FREE: no ptr_arg for {s}", .{callee_name});
        return;
    }

    const ptr_hash = @as(u64, @intFromPtr(ptr_arg));

    // Path 1: Memory graph has alloc_lang info.
    // Use findCanonicalAlloc to resolve alias chains — the free call's
    // ptr_arg (e.g., %p from a branch) may differ from the malloc call
    // instruction used as the node key. findCanonicalAlloc checks both
    // direct lookup and alias_to_canonical reverse index.
    if (mem_graph) |mg| {
        const node = mg.findCanonicalAlloc(ptr_hash) orelse blk: {
            break :blk findNodeByAllocInst(mg, ptr_hash);
        };
        if (node) |n| {
            const alloc_lang = n.alloc_lang;

            // =================================================================
            // P3: Family-first cross-free判定 (优先于 language-based 分支)
            // 当 alloc_family 和 release_family 都已知时, 使用 family 匹配
            // 替代 alloc_lang != free_lang 作为核心漏洞条件.
            // =================================================================
            if (n.alloc_family != null) {
                if (mg.family_registry) |reg| {
                    const alloc_family = n.alloc_family.?;
                    // Look up release family from callee name
                    const release_op = reg.lookupRelease(callee_name, null);
                    if (release_op) |rop| {
                        const match_result = reg.compareFamilies(alloc_family, rop.family);
                        switch (match_result) {
                            .same_family => {
                                log.debug("FAMILY-MATCH: same_family ({s}+{s}) — valid release in {s}", .{
                                    @tagName(alloc_family), @tagName(rop.family), func_name,
                                });
                                return; // Valid same-family release, not a bug
                            },
                            .compatible_family => {
                                // P15: Don't skip compatible families blindly.
                                // Only skip if BOTH are from the same runtime (e.g., python_object + python_mem).
                                // Cross-runtime compatible (e.g., rust_box + c_heap) should still be reported.
                                const alloc_domain = reg.getFamily(alloc_family).?.lifetime_domain;
                                const release_domain = reg.getFamily(rop.family).?.lifetime_domain;
                                if (alloc_domain == release_domain) {
                                    log.debug("FAMILY-MATCH: compatible_family same-domain ({s}+{s}) — valid release in {s}", .{
                                        @tagName(alloc_family), @tagName(rop.family), func_name,
                                    });
                                    return; // Same-domain compatible is likely valid
                                }
                                // Different-domain compatible → treat as suspicious but not definite mismatch
                                log.debug("FAMILY-MATCH: compatible_family cross-domain ({s}+{s}) → downgrade to cross_family_free in {s}", .{
                                    @tagName(alloc_family), @tagName(rop.family), func_name,
                                });
                                try reportCrossLanguageFree(ctx, func_name, callee_name, @tagName(alloc_family), @tagName(rop.family), inst, diag);
                                return;
                            },
                            .mismatch => {
                                log.debug("FAMILY-MISMATCH: {s} alloc + {s} release → cross_family_free in {s}", .{
                                    @tagName(alloc_family), @tagName(rop.family), func_name,
                                });
                                // Report as cross_family_free with family evidence
                                try reportCrossLanguageFree(ctx, func_name, callee_name, @tagName(alloc_family), @tagName(rop.family), inst, diag);
                                return;
                            },
                            .unknown_alloc, .unknown_release, .unknown_both => {
                                // Family unknown for one side — fall through to legacy language check
                                log.debug("FAMILY-UNKNOWN: match={s} in {s} — fallback to language check", .{
                                    @tagName(match_result), func_name,
                                });
                            },
                        }
                    } else {
                        // Release name not in registry — fall through to legacy check
                        log.debug("FAMILY-NOOP: release '{s}' not in registry in {s}", .{ callee_name, func_name });
                    }
                } // end if (family_registry)
            } // end if (alloc_family != null)
            // End P3 family-first block. Below is legacy language-based fallback.
            // =================================================================

            const free_is_rust = std.mem.eql(u8, free_lang.?, "rust");
            const alloc_is_c = alloc_lang == .c; // C only — NOT cpp
            const alloc_is_rust = alloc_lang == .rust;

            if (free_is_rust and alloc_is_c) {
                try reportCrossLanguageFree(ctx, func_name, callee_name, "C", "Rust", inst, diag);
                return;
            }
            if (!free_is_rust and alloc_is_rust) {
                try reportCrossLanguageFree(ctx, func_name, callee_name, "Rust", free_lang.?, inst, diag);
                return;
            }

            // C# / .NET P/Invoke cross-language free detection
            // Marshal.FreeHGlobal / CoTaskMemFree on non-.NET allocated memory
            const free_is_csharp = std.mem.eql(u8, free_lang.?, "csharp");
            const free_is_cpp = std.mem.eql(u8, free_lang.?, "cpp");
            // IMPORTANT: Only report as cross-language when alloc/free languages DIFFER.
            // Same-language frees (e.g., C++ delete on C++ new) are normal, not bugs.
            if ((free_is_csharp or free_is_cpp) and (alloc_is_c or alloc_is_rust)) {
                try reportCrossLanguageFree(ctx, func_name, callee_name, langToString(alloc_lang), free_lang.?, inst, diag);
                return;
            }

            // Zig cross-language free detection (P5)
            // Case A: Zig allocator memory freed by C's free()
            //   e.g., heap.page_allocator.alloc() followed by C free()
            //   → undefined behavior (different heaps, different ownership)
            const free_is_c = std.mem.eql(u8, free_lang.?, "c");
            const alloc_is_zig = alloc_lang == .zig;
            if (free_is_c and alloc_is_zig) {
                try reportCrossLanguageFree(ctx, func_name, callee_name, "Zig", "C", inst, diag);
                return;
            }
            // Case B: C-allocated memory freed by Zig's own deallocator
            //   e.g., malloc() followed by PageAllocator.free() or destroy()
            //   → C heap pointer managed by Zig runtime = UAF/corruption risk
            const free_is_zig = std.mem.eql(u8, free_lang.?, "zig");
            if (free_is_zig and (alloc_is_c or alloc_is_rust)) {
                try reportCrossLanguageFree(ctx, func_name, callee_name, langToString(alloc_lang), "Zig", inst, diag);
                return;
            }

            // Go/TinyGo cross-language free detection
            // Case A: Go runtime.alloc memory freed by C's free()
            const free_is_go = std.mem.eql(u8, free_lang.?, "go");
            const alloc_is_go = alloc_lang == .go;
            if (free_is_c and alloc_is_go) {
                try reportCrossLanguageFree(ctx, func_name, callee_name, "Go", "C", inst, diag);
                return;
            }
            // Case B: C-allocated memory freed by Go's runtime.free
            if (free_is_go and (alloc_is_c or alloc_is_rust)) {
                try reportCrossLanguageFree(ctx, func_name, callee_name, langToString(alloc_lang), "Go", inst, diag);
                return;
            }

            // Generic cross-language mismatch — compare Language enums,
            // not strings. classifyFreeLanguage returns "c" while
            // langToString(.c) returns "C/C++" — string comparison always
            // fails and causes false positives on every malloc+free pair.
            const free_lang_enum = freeLangToLanguage(free_lang.?);

            // SAME-LANGUAGE MERGE GUARD: When alloc_lang is .unknown (common
            // for cross-function return values like BitReverseTable()), don't
            // report cross_language_free if the CALLER MODULE's language matches
            // the free_lang. This prevents FPs in pure C++ modules where
            // internal allocations flow through helper functions.
            //
            // Example: cpp_fft.FFT() calls BitReverseTable() which returns
            // a new[]'d buffer. The graph node's alloc_lang is .unknown
            // (cross-function return), but both caller and free are C++.
            if (alloc_lang == .unknown) {
                const caller_module_lang = ctx.module_language.language;
                // Use ABI-compatible check: C/C++ share the same heap
                const is_same_language = isAbiCompatibleAllocFree(free_lang_enum, caller_module_lang);
                if (is_same_language) {
                    log.debug("SAME-LANG-MERGE: skipping cross_language_free (alloc=.unknown, free={s}, module={s}) in {s}", .{
                        free_lang.?, @tagName(caller_module_lang), func_name,
                    });
                    // Don't report — same-language operation, just unclear tracking
                } else {
                    try reportCrossLanguageFree(ctx, func_name, callee_name, langToString(alloc_lang), free_lang.?, inst, diag);
                }
                return;
            }

            // BUGFIX: Use isAbiCompatibleAllocFree instead of != comparison.
            // C++ alloc (.cpp) + C++ free (.cpp) now matches correctly.
            // Also handles C alloc + C++ free (same heap/ABI).
            if (free_lang_enum != .unknown and alloc_lang != .unknown and
                !isAbiCompatibleAllocFree(alloc_lang, free_lang_enum))
            {
                try reportCrossLanguageFree(ctx, func_name, callee_name, langToString(alloc_lang), free_lang.?, inst, diag);
                return;
            }
        }
    }

    // Path 2: Pointer map has source instruction — classify by callee name.
    // For call instructions (malloc, __rust_alloc, etc.), classify by the
    // CALLEE name, not the SSA value name (e.g., "p"). LLVMGetValueName on
    // a call instruction returns the SSA name, not the called function.
    const pm_direct: ?PtrInfo = pointer_map.get(ptr_arg);
    var ptr_info_opt: ?PtrInfo = pm_direct;
    if (ptr_info_opt == null) {
        // Fallback: scan pointer_map by value name (bridges LLVMValueRef gap).
        const ptr_name_ptr = c.LLVMGetValueName(ptr_arg);
        if (@intFromPtr(ptr_name_ptr) != 0) {
            const ptr_name = std.mem.span(ptr_name_ptr);
            var pm_iter = pointer_map.iterator();
            while (pm_iter.next()) |entry| {
                const key_name_ptr = c.LLVMGetValueName(entry.key_ptr.*);
                if (@intFromPtr(key_name_ptr) != 0) {
                    const key_name = std.mem.span(key_name_ptr);
                    if (std.mem.eql(u8, ptr_name, key_name)) {
                        ptr_info_opt = entry.value_ptr.*;
                        break;
                    }
                }
            }
        }
    }
    if (ptr_info_opt) |ptr_info| {
        if (ptr_info.source_inst) |src_inst| {
            var src_alloc_lang: ?[]const u8 = null;
            const src_opcode = c.LLVMGetInstructionOpcode(src_inst);
            if (src_opcode == c.LLVMCall or src_opcode == c.LLVMInvoke) {
                const src_called = c.LLVMGetCalledValue(src_inst);
                if (@intFromPtr(src_called) != 0) {
                    const src_called_name_ptr = c.LLVMGetValueName(src_called);
                    if (@intFromPtr(src_called_name_ptr) != 0) {
                        src_alloc_lang = classifyAllocLanguage(std.mem.span(src_called_name_ptr));
                    }
                }
            }
            if (src_alloc_lang == null) {
                const src_name_ptr = c.LLVMGetValueName(src_inst);
                if (@intFromPtr(src_name_ptr) != 0) {
                    src_alloc_lang = classifyAllocLanguage(std.mem.span(src_name_ptr));
                }
            }

            if (src_alloc_lang) |alloc_l| {
                const caller_is_zig = ctx.module_language.language == .zig;
                const free_is_c = std.mem.eql(u8, free_lang.?, "c");
                const alloc_is_zig = std.mem.eql(u8, alloc_l, "zig");
                const alloc_is_c = std.mem.eql(u8, alloc_l, "c");

                if (caller_is_zig and free_is_c) {
                    if (alloc_is_zig or (!alloc_is_c and !std.mem.eql(u8, alloc_l, "rust"))) {
                        try reportCrossLanguageFree(ctx, func_name, callee_name, "Zig (allocator)", "C (free)", inst, diag);
                        return;
                    }
                }

                if (!std.mem.eql(u8, alloc_l, free_lang.?)) {
                    const caller_module_lang = ctx.module_language.language;
                    const free_lang_enum = freeLangToLanguage(free_lang.?);
                    const is_same_language = isAbiCompatibleAllocFree(free_lang_enum, caller_module_lang);

                    if (is_same_language) {
                        log.debug("SAME-LANG-MERGE [PATH2]: skipping cross_language_free (alloc={s}, free={s}, module={s}) in {s}", .{
                            alloc_l, free_lang.?, @tagName(caller_module_lang), func_name,
                        });
                    } else {
                        try reportCrossLanguageFree(ctx, func_name, callee_name, alloc_l, free_lang.?, inst, diag);
                        return;
                    }
                }
            }
        }
    }
}

/// Convert memory_graph.Language enum to string for reporting.
fn langToString(lang: memory_graph.Language) []const u8 {
    return switch (lang) {
        .c => "C/C++",
        .cpp => "C/C++",
        .rust => "Rust",
        .zig => "Zig",
        .csharp => "C#",
        .go => "Go",
        .java => "Java/JNI",
        .python => "Python",
        .unknown => "Unknown",
    };
}

/// Convert free_lang string (from classifyFreeLanguage) to Language enum.
/// Enables enum-vs-enum comparison instead of broken string-vs-string.
///
/// IMPORTANT: C++ ("cpp") maps to .cpp (NOT .c). While C and C++ share
/// the same heap at runtime, we preserve the distinction for accurate
/// diagnostics. Same-language merge guards handle C/C++ equivalence.
fn freeLangToLanguage(free_lang: []const u8) memory_graph.Language {
    if (std.mem.eql(u8, free_lang, "rust")) return .rust;
    if (std.mem.eql(u8, free_lang, "c")) return .c;
    if (std.mem.eql(u8, free_lang, "cpp")) return .cpp; // Keep distinct from .c
    if (std.mem.eql(u8, free_lang, "go")) return .go;
    if (std.mem.eql(u8, free_lang, "java")) return .java;
    if (std.mem.eql(u8, free_lang, "python")) return .python;
    if (std.mem.eql(u8, free_lang, "csharp")) return .csharp;
    if (std.mem.eql(u8, free_lang, "zig")) return .zig;
    return .unknown;
}

/// Check if two languages are ABI-compatible for alloc/free pairing.
/// C and C++ share the same heap and allocator (malloc/free/new/delete
/// are interchangeable within a single module). Rust, Go, Zig each have
/// their own allocators that are NOT interchangeable with C/C++ or each other.
fn isAbiCompatibleAllocFree(alloc_lang: memory_graph.Language, free_lang: memory_graph.Language) bool {
    if (alloc_lang == free_lang) return true;
    // C and C++ share the same ABI/heap — new[]/delete[] pairs are valid
    if ((alloc_lang == .c and free_lang == .cpp) or
        (alloc_lang == .cpp and free_lang == .c)) return true;
    return false;
}

/// Check return violations
pub fn checkReturnViolation(
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

    // v0.2.0: Use OutputParamClassifier for precise C API output param detection.
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

    // v0.2.0: Use MemoryGraph source kind to filter borrow_escape FP.
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

        // v0.2.0: Alloc/free balance check.
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

        // v0.2.0: Check callee's alloc/free balance.
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

    // v0.2.0: Check if retval is a call instruction result from a known allocator.
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
            // v0.2.0: Skip param storage allocas — they are local copies of
            // function parameters, not dangerous stack address returns.
            if (ptr_info.is_param_storage) {
                diag.debug("[SUPPRESSED] Param storage alloca (not a real stack escape): {s}", .{func_name});
                stats.heap_intentional_transfer += 1;
                // v0.2.0: Skip sret allocas — LLVM uses "alloca ptr" as a return
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
                    // Generate candidate instead of direct reporting
                    if (try report.generateReturnHeapPtrCandidate(ctx, func_name, &ptr_info, inst, diag)) |candidate| {
                        defer {
                            var mut_candidate = candidate;
                            mut_candidate.deinit();
                        }
                        // Verify candidate through IssueVerifier
                        if (ctx.issue_verifier) |verifier| {
                            const result = try verifier.verify(&candidate);
                            if (result.shouldReport()) {
                                // Convert ViolationSeverity to Severity
                                const severity: Severity = switch (result.severity) {
                                    .critical => .critical,
                                    .high => .high,
                                    .medium => .medium,
                                    .low => .low,
                                    .diagnostic => .low,
                                    .explained => .low,
                                };
                                // Convert candidate to Issue and add to context
                                const issue = Issue.initWithTrace(
                                    .memory_leak,
                                    candidate.reason orelse "Memory leak detected",
                                    Location.init(func_name),
                                    severity,
                                    result.adjusted_score,
                                    &[_]TraceEntry{},
                                );
                                try ctx.addIssue(&issue);
                            }
                        } else {
                            // Legacy mode: direct reporting
                            const issue = Issue.initWithTrace(
                                .memory_leak,
                                candidate.reason orelse "Memory leak detected",
                                Location.init(func_name),
                                .high,
                                0.72,
                                &[_]TraceEntry{},
                            );
                            try ctx.addIssue(&issue);
                        }
                        stats.heap_ambiguous_found += 1;
                    }
                }
            } else {
                diag.debug("[SUPPRESSED] Heap return in factory function: {s} (intentional ownership transfer)", .{func_name});
                stats.heap_intentional_transfer += 1;
            }
        }
    }
}

// P17-2: Re-export return violation helpers from split file
pub const is_lifecycle_bound_return = return_helpers.is_lifecycle_bound_return;
pub const isSretAlloca = return_helpers.isSretAlloca;
pub const isAllocaReturnSuppressed = return_helpers.isAllocaReturnSuppressed;
pub const isStackEscapeSuppressed = return_helpers.isStackEscapeSuppressed;

/// P0-3: Path-sensitive double-free detection.
/// Records each free's basic block and checks if two frees of the same
/// pointer are on mutually exclusive execution paths (sibling blocks
/// with the same conditional branch predecessor, or RC==0 pattern).
pub fn checkDoubleFreeViolation(
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

    const sites = free_sites.get(ptr_hash) orelse return;
    if (sites.len <= 1) return;

    const prev_record = sites.items[sites.len - 2];
    if (areMutuallyExclusive(prev_record.bb_ref, bb_ref)) {
        diag.debug("[SUPPRESSED] Double-free on mutually exclusive paths in {s} (bb {} vs bb {})", .{ func_name, prev_record.bb_id, bb_id });
        return;
    }

    if (isRCPatternFree(prev_record.bb_ref) or isRCPatternFree(bb_ref)) {
        diag.debug("[SUPPRESSED] Double-free under RC==0 guard in {s}", .{func_name});
        return;
    }

    if (mem_graph) |mg| {
        const inst_ptr = @as(u64, @intFromPtr(inst));
        const free_lang: Lang = toZoneLanguage(ctx.module_language.language);
        const is_double = mg.trackFree(inst_ptr, ptr_hash, free_lang, 0) catch false;
        if (is_double) {
            if (!ctx.isRelevantAlloc(ptr_hash)) return;
            const msg = try std.fmt.allocPrint(ctx.allocator, "[OMI-HIGH] [DOUBLE_FREE] MemoryGraph detected double-free of pointer in {s}", .{func_name});
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
            stats.use_after_free_found += 1;
            return;
        }
    }

    if (pointer_map.get(ptr_arg)) |ptr_info| {
        if (ptr_info.double_free_detected) {
            if (!ctx.isRelevantAlloc(ptr_hash)) return;
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

pub fn checkCallViolation(
    ctx: *PassContext,
    inst: c.LLVMValueRef,
    _: c.LLVMValueRef,
    func_name: []const u8,
    _: usize,
    pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
    mem_graph: ?*memory_graph.MemoryGraph,
    diag: *DiagnosticWriter,
    stats: *LifetimeStats,
    lifetime_map: ?*LifetimeMap,
) !void {
    const called = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called) == 0) return;

    const name_ptr = c.LLVMGetValueName(called);
    if (@intFromPtr(name_ptr) == 0) return;

    const callee_name = std.mem.span(name_ptr);

    if (!may_retain_pointer(callee_name)) return;

    if (mem_graph) |mg| {
        const callee_ptr = @as(u64, @intFromPtr(called));
        const callee_counter = mg.getFuncCounter(callee_ptr);

        const callee_returns_ptr = if (callee_counter.hasHeapOps())
            callee_counter.returns_pointer
        else blk: {
            const ret_type = c.LLVMTypeOf(inst);
            if (@intFromPtr(ret_type) != 0 and
                c.LLVMGetTypeKind(ret_type) == c.LLVMPointerTypeKind)
            {
                break :blk true;
            }
            break :blk false;
        };

        if (!callee_returns_ptr) {
            const num_args = getCallInstArgCount(inst);
            var i: u32 = 0;
            while (i < num_args) : (i += 1) {
                const arg = c.LLVMGetOperand(inst, i);
                if (pointer_map.get(arg)) |ptr_info| {
                    if (ptr_info.alloc_site == .stack and !ptr_info.escaped) {
                        // T1.2: Check if escape occurs outside alloca's lifetime interval
                        if (lifetime_map) |lm| {
                            if (ptr_info.source_inst) |alloca_inst| {
                                if (!isAllocaAliveAt(lm, alloca_inst, inst)) {
                                    log.debug("[ptr-lifetime] SUPPRESSED: Stack escape to {s} occurs outside alloca lifetime (FP reduction)", .{callee_name});
                                    stats.heap_intentional_transfer += 1;
                                    continue;
                                }
                            }
                        }

                        const is_extern = is_extern_function(callee_name);
                        if (is_extern) {
                            if (isRustBorrowPattern(ptr_info.source_desc)) {
                                try reportBorrowEscapeFFI(ctx, func_name, callee_name, ptr_info, inst, diag);
                            } else {
                                try reportStackEscape(ctx, func_name, callee_name, ptr_info, inst, diag, mem_graph);
                            }
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
            const call_graph_ptr: ?*call_graph_mod.CallGraph = if (ctx.semantics_call_graph) |*sg| sg else null;
            const has_cross_func_alias = ip_ffi.detect_cross_func_alias(inst, call_graph_ptr);

            if (ptr_info.alloc_site == .stack and !ptr_info.escaped) {
                // T1.2: Check if escape occurs outside alloca's lifetime interval
                if (lifetime_map) |lm| {
                    if (ptr_info.source_inst) |alloca_inst| {
                        if (!isAllocaAliveAt(lm, alloca_inst, inst)) {
                            log.debug("[ptr-lifetime] SUPPRESSED: Stack escape to {s} occurs outside alloca lifetime (FP reduction)", .{callee_name});
                            stats.heap_intentional_transfer += 1;
                            continue;
                        }
                    }
                }

                if (isStackEscapeSuppressed(callee_name, ptr_info)) {
                    diag.debug("[SUPPRESSED] Stack escape in callback/hook: {s}", .{callee_name});
                    stats.stack_escapes_found += 1;
                } else {
                    const is_extern_callee = is_extern_function(callee_name);
                    const is_borrow = isRustBorrowPattern(ptr_info.source_desc);
                    if (is_extern_callee and is_borrow) {
                        try reportBorrowEscapeFFI(ctx, func_name, callee_name, ptr_info, inst, diag);
                    } else {
                        try reportStackEscape(ctx, func_name, callee_name, ptr_info, inst, diag, mem_graph);
                    }
                    if (has_cross_func_alias) {
                        diag.debug("[ENHANCED] Cross-function alias evidence found for stack escape to {s}", .{callee_name});
                    }
                    stats.stack_escapes_found += 1;
                }
                if (pointer_map.getPtr(arg)) |pi| pi.escaped = true;
            } else if (ptr_info.alloc_site == .heap and !ptr_info.escaped) {
                try reportHeapEscapeToFFI(ctx, func_name, callee_name, ptr_info, inst, diag);
                if (has_cross_func_alias) {
                    diag.debug("[ENHANCED] Cross-function alias evidence for heap escape to {s}", .{callee_name});
                }
                stats.heap_ambiguous_found += 1;
                if (pointer_map.getPtr(arg)) |pi| pi.escaped = true;
            } else if (ptr_info.freed) {
                if (!ctx.isRelevantAlloc(@as(u64, @intFromPtr(arg)))) continue;
                if (ptr_info.resource_type != .none) {
                    try reportResourceUAF(ctx, func_name, callee_name, ptr_info, inst, diag);
                } else {
                    try reportUseAfterFree(ctx, func_name, callee_name, ptr_info, inst, diag);
                }
                if (has_cross_func_alias) {
                    diag.debug("[ENHANCED] Cross-function alias evidence for UAF to {s}", .{callee_name});
                }
                stats.use_after_free_found += 1;
            }
        }
    }
}

/// Check if an FFI call's return value is null-checked before use.
/// Reports if an external function returns a pointer but the caller
/// never checks for null — a common CWE-252/CWE-476 pattern.
pub fn checkFFIReturnNullGuard(
    ctx: *PassContext,
    inst: c.LLVMValueRef,
    func: c.LLVMValueRef,
    func_name: []const u8,
    pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
    diag: *DiagnosticWriter,
    stats: *LifetimeStats,
) !void {
    _ = func;
    _ = pointer_map;
    _ = stats;

    const called = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called) == 0) return;

    const called_name_ptr = c.LLVMGetValueName(called);
    if (@intFromPtr(called_name_ptr) == 0) return;
    const callee_name = std.mem.span(called_name_ptr);

    // Only check external/declaration functions (FFI boundaries)
    const callee_func = c.LLVMIsAFunction(called);
    if (@intFromPtr(callee_func) != 0 and c.LLVMIsDeclaration(callee_func) == 0) return;

    // Only check functions that return a pointer type
    const ret_type = c.LLVMTypeOf(inst);
    if (c.LLVMGetTypeKind(ret_type) != c.LLVMPointerTypeKind) return;

    // Skip known non-null-returning allocators (they always succeed or abort)
    for (&[_][]const u8{ "__rust_alloc", "__rust_alloc_zeroed", "operator new" }) |safe_name| {
        if (std.mem.eql(u8, callee_name, safe_name)) return;
    }

    // Scan next few instructions for a null-check (icmp eq/ne with null)
    var next = c.LLVMGetNextInstruction(inst);
    var scan_count: u32 = 0;
    while (@intFromPtr(next) != 0 and scan_count < 5) : (scan_count += 1) {
        const next_opcode = c.LLVMGetInstructionOpcode(next);
        if (next_opcode == c.LLVMICmp) {
            // Check if comparing the call result with null
            const lhs = c.LLVMGetOperand(next, 0);
            const rhs = c.LLVMGetOperand(next, 1);
            if (@intFromPtr(lhs) == @intFromPtr(inst) or @intFromPtr(rhs) == @intFromPtr(inst)) {
                // Result is being compared — null-check present
                return;
            }
        }
        // If we hit a use of the value (store, call arg, load through it)
        // without a null-check, that's the problem
        if (next_opcode == c.LLVMStore or next_opcode == c.LLVMLoad or
            next_opcode == c.LLVMCall or next_opcode == c.LLVMInvoke)
        {
            // Value used without null-check — report
            try reportFFINullGuardMissing(ctx, func_name, callee_name, inst, diag);
            return;
        }
        next = c.LLVMGetNextInstruction(next);
    }
}

/// Check for type mismatches in FFI call arguments.
/// Detects suspicious bitcasts (e.g., casting between incompatible pointer types)
/// passed to external functions — a common CWE-704 pattern.
pub fn checkFFITypeMismatch(
    ctx: *PassContext,
    inst: c.LLVMValueRef,
    func: c.LLVMValueRef,
    func_name: []const u8,
    pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
    diag: *DiagnosticWriter,
    stats: *LifetimeStats,
) !void {
    _ = func;
    _ = pointer_map;
    _ = stats;

    const called = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called) == 0) return;

    const called_name_ptr = c.LLVMGetValueName(called);
    if (@intFromPtr(called_name_ptr) == 0) return;
    const callee_name = std.mem.span(called_name_ptr);

    // Only check external/declaration functions (FFI boundaries)
    const callee_func = c.LLVMIsAFunction(called);
    if (@intFromPtr(callee_func) != 0 and c.LLVMIsDeclaration(callee_func) == 0) return;

    // Check each argument for suspicious bitcasts
    const num_args = c.LLVMGetNumArgOperands(inst);
    var i: u32 = 0;
    while (i < num_args) : (i += 1) {
        const arg = c.LLVMGetOperand(inst, i);
        if (@intFromPtr(arg) == 0) continue;

        // Check if the argument is a bitcast instruction
        const arg_opcode = c.LLVMGetInstructionOpcode(arg);
        if (arg_opcode != c.LLVMBitCast) continue;

        const src = c.LLVMGetOperand(arg, 0);
        if (@intFromPtr(src) == 0) continue;

        const src_type = c.LLVMTypeOf(src);
        const dst_type = c.LLVMTypeOf(arg);

        // Both must be pointer types for a meaningful check
        if (c.LLVMGetTypeKind(src_type) != c.LLVMPointerTypeKind) continue;
        if (c.LLVMGetTypeKind(dst_type) != c.LLVMPointerTypeKind) continue;

        // Get the element types to check compatibility
        const src_elem = c.LLVMGetElementType(src_type);
        const dst_elem = c.LLVMGetElementType(dst_type);
        const src_kind = c.LLVMGetTypeKind(src_elem);
        const dst_kind = c.LLVMGetTypeKind(dst_elem);

        // Flag cross-kind casts (e.g., struct* → int*, function* → data*)
        if (src_kind != dst_kind and
            src_kind != c.LLVMIntegerTypeKind and
            dst_kind != c.LLVMIntegerTypeKind and
            src_kind != c.LLVMVoidTypeKind and
            dst_kind != c.LLVMVoidTypeKind)
        {
            const mismatch_desc = try std.fmt.allocPrint(
                ctx.allocator,
                "argument {d} bitcast from kind={d} to kind={d} passed to {s}",
                .{ i, src_kind, dst_kind, callee_name },
            );
            defer ctx.allocator.free(mismatch_desc);
            try reportFFITypeMismatch(ctx, func_name, callee_name, mismatch_desc, inst, diag);
            return; // Report at most one mismatch per call
        }
    }
}

pub fn checkViolations(
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
    lifetime_map: ?*LifetimeMap,
) !void {
    if (@intFromPtr(inst) == 0) return;

    const opcode = c.LLVMGetInstructionOpcode(inst);

    if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
        try checkDoubleFreeViolation(ctx, inst, func_name, bb_id, bb_ref, pointer_map, mem_graph, diag, stats, free_sites);
        try checkCallViolation(ctx, inst, func, func_name, bb_id, pointer_map, mem_graph, diag, stats, lifetime_map);
        try checkFFIReturnNullGuard(ctx, inst, func, func_name, pointer_map, diag, stats);
        try checkCrossLanguageFree(ctx, inst, func_name, pointer_map, mem_graph, diag, stats);
        try checkFFITypeMismatch(ctx, inst, func, func_name, pointer_map, diag, stats);
    }

    if (opcode == c.LLVMRet) {
        try checkReturnViolation(ctx, inst, func, func_name, pointer_map, mem_graph, diag, stats);
    }

    if (opcode == c.LLVMStore) {
        try checkStoreToGlobal(ctx, inst, func_name, pointer_map, diag, stats);
    }
}
