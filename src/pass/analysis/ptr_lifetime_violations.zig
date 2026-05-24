//! Violation detection functions for pointer lifetime analysis
//!
//! Extracted from ptr_lifetime.zig to improve code organization.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const safe = @import("../../ir/llvm_safe.zig"); // Issue2: Standardized LLVM helpers

const PassContext = @import("../pass.zig").PassContext;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const memory_graph = @import("../../semantics/memory_graph.zig");
const Issue = @import("../../diag/issue.zig").Issue;
const IssueKind = @import("../../diag/issue.zig").IssueKind;
const Severity = @import("../../diag/issue.zig").Severity;
const Location = @import("../../diag/issue.zig").Location;
const TraceEntry = @import("../../diag/issue.zig").TraceEntry;

const PtrInfo = @import("ptr_lifetime_types.zig").PtrInfo;
const LifetimeStats = @import("ptr_lifetime_types.zig").LifetimeStats;
const FreeSiteRecord = @import("ptr_lifetime_types.zig").FreeSiteRecord;
const FreeSiteList = @import("ptr_lifetime.zig").FreeSiteList;
const ResourceType = @import("ptr_lifetime_types.zig").ResourceType;

const isFreeFunction = @import("ptr_lifetime_classify.zig").isFreeFunction;
const classifyAllocLanguage = @import("ptr_lifetime_classify.zig").classifyAllocLanguage;
const classifyAllocLanguageEnum = @import("ptr_lifetime_classify.zig").classifyAllocLanguageEnum;
const classifyFreeLanguage = @import("ptr_lifetime_classify.zig").classifyFreeLanguage;
const report = @import("ptr_lifetime_report.zig");
const is_extern_function = @import("ptr_lifetime_types.zig").is_extern_function;
const word_boundary = @import("../../utils/word_boundary.zig");

const ptr_utils = @import("ptr_lifetime_utils.zig");
const Lang = ptr_utils.Lang;
const toZoneLanguage = ptr_utils.toZoneLanguage;
const areMutuallyExclusive = ptr_utils.areMutuallyExclusive;
const isRCPatternFree = ptr_utils.isRCPatternFree;
const isGlobalVariable = ptr_utils.isGlobalVariable;
const isRustBorrowPattern = ptr_utils.isRustBorrowPattern;
const isCppDestructorOrConstructor = ptr_utils.isCppDestructorOrConstructor;
const isNonPointerReturnType = ptr_utils.isNonPointerReturnType;
const output_param_classifier = @import("../../semantics/output_param_classifier.zig");
const NoiseReduction = @import("noise_reduction.zig");
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

const ip_ffi = @import("ip_ffi.zig");
const call_graph_mod = @import("../../semantics/call_graph.zig");
const getCallInstArgCount = @import("../../ir/llvm_safe.zig").getCallInstArgCount;
const may_retain_pointer = @import("ptr_lifetime_types.zig").may_retain_pointer;

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

    const ptr_arg = c.LLVMGetOperand(inst, 0);
    if (@intFromPtr(ptr_arg) == 0) return;

    const ptr_hash = @as(u64, @intFromPtr(ptr_arg));

    // Path 1: Memory graph has alloc_lang info
    if (mem_graph) |mg| {
        if (mg.nodes.get(ptr_hash)) |node| {
            const alloc_lang = node.alloc_lang;
            const free_is_rust = std.mem.eql(u8, free_lang.?, "rust");
            const alloc_is_c = alloc_lang == .c or alloc_lang == .cpp;
            const alloc_is_rust = alloc_lang == .rust;

            if (free_is_rust and alloc_is_c) {
                try reportCrossLanguageFree(ctx, func_name, callee_name, "C/C++", "Rust", inst, diag);
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
            if ((free_is_csharp or free_is_cpp) and (alloc_is_c or alloc_is_rust)) {
                try reportCrossLanguageFree(ctx, func_name, callee_name,
                    langToString(alloc_lang), free_lang.?, inst, diag);
                return;
            }

            // Zig cross-language free detection (P5)
            // Case A: Zig allocator memory freed by C's free()
            //   e.g., heap.page_allocator.alloc() followed by C free()
            //   → undefined behavior (different heaps, different ownership)
            const free_is_c = std.mem.eql(u8, free_lang.?, "c");
            const alloc_is_zig = alloc_lang == .zig;
            if (free_is_c and alloc_is_zig) {
                try reportCrossLanguageFree(ctx, func_name, callee_name,
                    "Zig", "C", inst, diag);
                return;
            }
            // Case B: C-allocated memory freed by Zig's own deallocator
            //   e.g., malloc() followed by PageAllocator.free() or destroy()
            //   → C heap pointer managed by Zig runtime = UAF/corruption risk
            const free_is_zig = std.mem.eql(u8, free_lang.?, "zig");
            if (free_is_zig and (alloc_is_c or alloc_is_rust)) {
                try reportCrossLanguageFree(ctx, func_name, callee_name,
                    langToString(alloc_lang), "Zig", inst, diag);
                return;
            }

            // Go/TinyGo cross-language free detection
            // Case A: Go runtime.alloc memory freed by C's free()
            const free_is_go = std.mem.eql(u8, free_lang.?, "go");
            const alloc_is_go = alloc_lang == .go;
            if (free_is_c and alloc_is_go) {
                try reportCrossLanguageFree(ctx, func_name, callee_name,
                    "Go", "C", inst, diag);
                return;
            }
            // Case B: C-allocated memory freed by Go's runtime.free
            if (free_is_go and (alloc_is_c or alloc_is_rust)) {
                try reportCrossLanguageFree(ctx, func_name, callee_name,
                    langToString(alloc_lang), "Go", inst, diag);
                return;
            }

            // Generic cross-language mismatch — compare Language enums,
            // not strings. classifyFreeLanguage returns "c" while
            // langToString(.c) returns "C/C++" — string comparison always
            // fails and causes false positives on every malloc+free pair.
            const free_lang_enum = freeLangToLanguage(free_lang.?);
            if (free_lang_enum != .unknown and alloc_lang != .unknown and
                free_lang_enum != alloc_lang)
            {
                try reportCrossLanguageFree(ctx, func_name, callee_name, langToString(alloc_lang), free_lang.?, inst, diag);
                return;
            }
        }
    }

    // Path 2: Pointer map has source instruction — classify by name
    if (pointer_map.get(ptr_arg)) |ptr_info| {
        if (ptr_info.source_inst) |src_inst| {
            const src_name_ptr = c.LLVMGetValueName(src_inst);
            if (@intFromPtr(src_name_ptr) != 0) {
                const src_name = std.mem.span(src_name_ptr);
                const src_alloc_lang = classifyAllocLanguage(src_name);

                if (src_alloc_lang) |alloc_l| {
                    // P1: Call-site language context for cross-language free detection.
                    // When Zig code calls C's free() via @cImport("libc"), the IR shows
                    // callee as just "free" — same as C code calling free(). But semantically:
                    //   - If alloc was from a ZIG allocator (not malloc) → cross-language bug
                    //   - If alloc was from C (malloc) → legitimate @cImport usage, skip
                    //
                    // Key insight: Use ctx.module_language.language to determine caller's language.
                    const caller_is_zig = ctx.module_language.language == .zig;
                    const free_is_c = std.mem.eql(u8, free_lang.?, "c");
                    const alloc_is_zig = std.mem.eql(u8, alloc_l, "zig");
                    const alloc_is_c = std.mem.eql(u8, alloc_l, "c");

                    if (caller_is_zig and free_is_c) {
                        // Zig module calling C's free()
                        if (alloc_is_zig or (!alloc_is_c and !std.mem.eql(u8, alloc_l, "rust"))) {
                            // Alloc is from Zig allocator (or unknown in Zig context)
                            // → potential cross-language free bug
                            try reportCrossLanguageFree(ctx, func_name, callee_name,
                                "Zig (allocator)", "C (free)", inst, diag);
                            return;
                        }
                        // alloc_is_c: malloc+free via @cImport → legitimate, fall through to normal check
                    }

                    if (!std.mem.eql(u8, alloc_l, free_lang.?)) {
                        try reportCrossLanguageFree(ctx, func_name, callee_name, alloc_l, free_lang.?, inst, diag);
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
fn freeLangToLanguage(free_lang: []const u8) memory_graph.Language {
    if (std.mem.eql(u8, free_lang, "rust")) return .rust;
    if (std.mem.eql(u8, free_lang, "c")) return .c;
    if (std.mem.eql(u8, free_lang, "cpp")) return .c; // C++ uses same heap as C
    if (std.mem.eql(u8, free_lang, "go")) return .go;
    if (std.mem.eql(u8, free_lang, "java")) return .java;
    if (std.mem.eql(u8, free_lang, "python")) return .python;
    if (std.mem.eql(u8, free_lang, "csharp")) return .csharp; // .NET P/Invoke
    if (std.mem.eql(u8, free_lang, "zig")) return .zig; // Zig runtime allocator
    return .unknown;
}

/// Check for FFI type mismatch via bitcast
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
    _ = stats;
    const called = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called) == 0) return;

    const name_ptr = c.LLVMGetValueName(called);
    if (@intFromPtr(name_ptr) == 0) return;
    const callee_name = std.mem.span(name_ptr);

    if (!is_extern_function(callee_name)) return;

    // Issue2 FIX: Use standardized helper for consistent arg iteration
    const num_args = safe.getCallInstArgCount(inst);
    var arg_i: u32 = 0;
    while (arg_i < num_args) : (arg_i += 1) {
        const arg = c.LLVMGetOperand(inst, arg_i);
        if (@intFromPtr(arg) == 0) continue;

        const arg_opcode = c.LLVMGetInstructionOpcode(arg);
        if (arg_opcode == c.LLVMBitCast) {
            const src = c.LLVMGetOperand(arg, 0);
            if (@intFromPtr(src) == 0) return; // continue in callback = return

            const src_type = c.LLVMTypeOf(src);
            const arg_type = c.LLVMTypeOf(arg);
            if (@intFromPtr(src_type) == 0 or @intFromPtr(arg_type) == 0) return;

            if (c.LLVMGetTypeKind(src_type) == c.LLVMPointerTypeKind and
                c.LLVMGetTypeKind(arg_type) == c.LLVMPointerTypeKind)
            {
                const src_pointee = c.LLVMGetElementType(src_type);
                const arg_pointee = c.LLVMGetElementType(arg_type);
                if (@intFromPtr(src_pointee) != 0 and @intFromPtr(arg_pointee) != 0) {
                    if (c.LLVMGetTypeKind(src_pointee) != c.LLVMGetTypeKind(arg_pointee)) {
                        if (pointer_map.get(src)) |ptr_info| {
                            const mismatch_desc = try std.fmt.allocPrint(ctx.allocator, "const-cast: {s} type changed via bitcast", .{ptr_info.source_desc});
                            defer ctx.allocator.free(mismatch_desc);
                            try reportFFITypeMismatch(ctx, func_name, callee_name, mismatch_desc, inst, diag);
                            return;
                        }
                    }
                }
            }
        }
    }
}

/// Check if FFI return value has NULL guard
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
    const called = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called) == 0) return;

    const name_ptr = c.LLVMGetValueName(called);
    if (@intFromPtr(name_ptr) == 0) return;
    const callee_name = std.mem.span(name_ptr);

    if (!is_extern_function(callee_name)) return;

    const ret_type = c.LLVMTypeOf(inst);
    if (@intFromPtr(ret_type) == 0) return;
    if (c.LLVMGetTypeKind(ret_type) != c.LLVMPointerTypeKind) return;

    if (pointer_map.contains(inst)) return;

    // Safety check: verify instruction is valid before FFI analysis
    if (@intFromPtr(inst) == 0) return;
    const opcode = c.LLVMGetInstructionOpcode(inst);
    if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) return;

    // Wrap FFI checks with safety for large modules (libuv150 has 877 funcs)
    var has_null_guard = false;
    var is_result_used = false;

    // Use a panic-safe wrapper for complex IR patterns
    const safe_check = struct {
        fn run(call_inst: c.LLVMValueRef) struct { has_guard: bool, used: bool } {
            var guard = false;
            var used = false;

            // Inline simplified version that won't crash on complex IR
            var scan_inst = c.LLVMGetNextInstruction(call_inst);
            var scanned: u32 = 0;
            const max_scan: u32 = 200; // Limit scan depth for safety

            while (@intFromPtr(scan_inst) != 0 and scanned < max_scan) : ({
                scan_inst = c.LLVMGetNextInstruction(scan_inst);
                scanned += 1;

                if (@intFromPtr(scan_inst) == 0) break;

                const op = c.LLVMGetInstructionOpcode(scan_inst);
                if (op == c.LLVMICmp) {
                    // Found potential null check - set guard and stop scanning
                    guard = true;
                    // Issue2 FIX: Restore break to prevent false positives from continued scanning
                    break;
                }

                // DC-C5 FIX: Check if return value is used (store, call arg, etc.)
                // This runs BEFORE finding the null guard to track usage patterns
                if (op == c.LLVMStore or op == c.LLVMCall or op == c.LLVMInvoke) {
                    used = true;
                }

                // Also check for bitcast/ptrtoint which indicate usage
                if (op == c.LLVMBitCast or op == c.LLVMPtrToInt) {
                    used = true;
                }
            }) {}

            return .{ .has_guard = guard, .used = used };
        }
    }.run;

    const result = safe_check(inst);
    has_null_guard = result.has_guard;
    is_result_used = result.used;

    if (!has_null_guard and is_result_used) {
        try reportFFINullGuardMissing(ctx, func_name, callee_name, inst, diag);
        stats.use_after_free_found += 1;
    }
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

    // v0.1.7: Use OutputParamClassifier for precise C API output param detection.
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
pub fn isSretAlloca(retval: c.LLVMValueRef, _: c.LLVMValueRef, func: c.LLVMValueRef) bool {
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
pub fn isAllocaReturnSuppressed(func_name: []const u8, ptr_info: PtrInfo) bool {
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
/// Callback/hook patterns legitimately receive stack pointer.
pub fn isStackEscapeSuppressed(callee_name: []const u8, _: PtrInfo) bool {
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
) !void {
    if (@intFromPtr(inst) == 0) return;

    const opcode = c.LLVMGetInstructionOpcode(inst);

    if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
        try checkDoubleFreeViolation(ctx, inst, func_name, bb_id, bb_ref, pointer_map, mem_graph, diag, stats, free_sites);
        try checkCallViolation(ctx, inst, func, func_name, bb_id, pointer_map, mem_graph, diag, stats);
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
