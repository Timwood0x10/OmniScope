//! Rules 1-5: Basic FFI Safety Detection
//!
//! This module implements the core Rust FFI safety rules:
//!   - Rule 1: into_raw/from_raw pairing check
//!   - Rule 2: as_ptr borrow escape detection
//!   - Rule 3: Cross-language allocation mismatch
//!   - Rule 4: Unsafe block FFI call scan
//!   - Rule 5: Stack address escape to FFI boundary
//!   - Rule 6: Ownership transfer protocol violations
//!
//! Plus foundational helper functions for pointer analysis.
//!
//! All functions are standalone (not methods) and take auditor as first parameter.

const std = @import("std");
const log = @import("../../../common/log.zig");
const c = @import("../../../ir/llvm_raw.zig").c;
const inst_cache_mod = @import("../../../ir/inst_cache.zig");
const InstCache = inst_cache_mod.InstCache;
const ptr_types = @import("../ptr_lifetime/ptr_lifetime_types.zig");
const tracking = @import("../ptr_lifetime/value_tracking.zig");
const ir_store_mod = @import("../../../ir/ir_store.zig");
const FunctionIR = ir_store_mod.FunctionIR;

const types = @import("../../../types/rust_ffi_types.zig");
pub const RustFfiFinding = types.RustFfiFinding;
const FreeEntry = types.FreeEntry;

const PassContext = @import("../../pass.zig").PassContext;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;
const Issue = @import("../../../diag/issue.zig").Issue;
const Location = @import("../../../diag/issue.zig").Location;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;

const rust_ffi_helpers = @import("rust_ffi_helpers.zig");
const getFunctionName = rust_ffi_helpers.getFunctionName;
const isRustAsPtrCall = rust_ffi_helpers.isRustAsPtrCall;
const isCFreeCall = rust_ffi_helpers.isCFreeCall;
const isExternCCall = rust_ffi_helpers.isExternCCall;
const isRustMangledName = rust_ffi_helpers.isRustMangledName;
const mayRetainPointer = rust_ffi_helpers.mayRetainPointer;
const ptrOriginatesFromRustAlloc = rust_ffi_helpers.ptrOriginatesFromRustAlloc;
const isPureConsumptionFunction = rust_ffi_helpers.isPureConsumptionFunction;
const isMemoryManagementFunction = rust_ffi_helpers.isMemoryManagementFunction;

const SemanticKind = @import("../../../semantics/semantic_tree.zig").SemanticKind;
const ptr_lifetime_utils = @import("../ptr_lifetime/ptr_lifetime_utils.zig");
const isIntentionalOwnershipTransfer = ptr_lifetime_utils.isIntentionalOwnershipTransfer;

/// Auditor type (forward declaration - will be resolved at compile time)
const Auditor = @import("rust_ffi_auditor.zig").RustFfiAuditor;

/// Detect as_ptr borrow escape in function body (Rule 2).
pub fn detectAsPtrEscape(auditor: *Auditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter, insts: []const c.LLVMValueRef, inst_cache: *InstCache) !void {
    for (insts) |inst| {
        // PERF: Use InstCache for opcode lookup
        const opcode = inst_cache.getOpcode(inst);
        if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

        // PERF: Use InstCache for operand count and callee name lookup
        const num_operands: c_uint = inst_cache.getNumOperands(inst);
        if (num_operands < 2) continue;

        const callee_name = inst_cache.getCalleeName(inst) orelse continue;
        const name_slice = callee_name;

        if (!isRustAsPtrCall(name_slice)) continue;

        // R-1/R-8: Check SRT for provenance — heap/global pointers are
        // not stack escapes; from_parameter is not a local stack escape.
        // R-8: Function parameters are NOT stack escapes — the caller
        // owns the pointer and is responsible for its lifetime.
        // R-1: Heap provenance (Box/Arc/Vec/String) — pointer from heap
        // allocation passed to FFI is not a borrow escape.
        if (ctx.semantic_resolution) |resolution_engine| {
            const srt = resolution_engine.getSemanticTree();
            // Check the as_ptr return value's provenance
            const inst_ref = @intFromPtr(inst);
            if (srt.hasKind(inst_ref, .heap_provenance) != null) continue;
            if (srt.hasKind(inst_ref, .global_provenance) != null) continue;
            // Trace the as_ptr base pointer back to check provenance
            if (srt.*.traceToHeapProvenance(inst, 8)) continue;
        }

        auditor.stats.as_ptr_escapes += 1;
        const func_name = getFunctionName(func);

        try addFinding(auditor, .{
            .func_name = func_name,
            .issue_type = .as_ptr_borrow_escape,
            .severity = .high,
            .confidence = 0.80,
            .reason = "as_ptr() on local String/Vec passed to extern C - pointer may dangle after drop",
            .location = Location.init(func_name),
        });

        const vuln_id = ctx.getNextVulnId();
        ctx.addIssue(&Issue.initWithReason(
            .borrow_escape,
            "Potential as_ptr borrow escape: local Rust value pointer passed to FFI",
            Location.init(func_name),
            .high,
            0.8,
            "as_ptr() on local String/Vec passed to extern C - pointer may dangle after drop",
        )) catch |err| {
            diag.warn("Failed to register borrow_escape issue: {any}", .{err});
        };
        diag.err("VULNERABILITY OMI-{d:0>3} [high] [Confidence: medium]", .{vuln_id});
        diag.err("Type: borrow_escape", .{});
        diag.err("Reason: as_ptr() on local value passed to FFI - may dangle", .{});
    }
}

/// Detect cross-language allocation mismatch (Rule 3): Rust _Znwm → C free.
/// `stores` is the pre-categorized Store instruction slice from IR Store, used by
/// ptrOriginatesFromRustAlloc to trace allocation origins without BB/inst traversal.
pub fn detectCrossLangMismatch(auditor: *Auditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter, insts: []const c.LLVMValueRef, inst_cache: *InstCache, stores: []const c.LLVMValueRef) !void {
    var visited = std.AutoHashMap(usize, void).init(auditor.allocator);
    defer visited.deinit();

    for (insts) |inst| {
        // PERF: Use InstCache for opcode lookup
        const opcode = inst_cache.getOpcode(inst);
        if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

        // PERF: Use InstCache for operand count and callee name lookup
        const num_operands: c_uint = inst_cache.getNumOperands(inst);
        if (num_operands < 2) continue;

        const callee_name = inst_cache.getCalleeName(inst) orelse continue;

        if (!isCFreeCall(callee_name)) continue;

        // R-6: If the freed pointer came from into_raw, ownership was
        // explicitly transferred — C free() is legal, not a bug.
        // R-7: If the callee is a library allocator release function
        // (e.g., mi_free, sqlite3_finalize), it's not cross-language.
        const inst_ref = @intFromPtr(inst);
        if (ctx.semantic_resolution) |resolution_engine| {
            const srt = resolution_engine.getSemanticTree();
            // R-7: Library allocator release — not cross-language
            if (srt.hasKind(inst_ref, .library_release) != null) continue;
            // R-4: Non-memory syscall (file/net/proc) — not a free
            if (srt.hasKind(inst_ref, .file_operation) != null) continue;
            if (srt.hasKind(inst_ref, .network_operation) != null) continue;
            if (srt.hasKind(inst_ref, .process_operation) != null) continue;
        }

        // Get the pointer argument to free() and trace its origin
        // FIXED: LLVM call instruction: [callee, arg0, arg1, ...], so ptr is at index 1
        const ptr_arg = c.LLVMGetOperand(inst, 1);
        if (@intFromPtr(ptr_arg) == 0) continue;

        // R-6: Check if the pointer came from into_raw (ownership transfer)
        const ptr_ref = @intFromPtr(ptr_arg);
        if (ctx.semantic_resolution) |resolution_engine| {
            const srt = resolution_engine.getSemanticTree();
            if (srt.hasKind(ptr_ref, .into_raw_transfer) != null) {
                // Ownership was transferred via into_raw — C free() is legal
                continue;
            }
        }

        // Only report if the pointer can be traced back to a Rust allocator
        if (!ptrOriginatesFromRustAlloc(stores, ptr_arg, &visited)) continue;

        const func_name = getFunctionName(func);
        auditor.stats.cross_lang_mismatches += 1;

        try addFinding(auditor, .{
            .func_name = func_name,
            .issue_type = .cross_lang_alloc_mismatch,
            .severity = .high,
            .confidence = 0.85,
            .reason = "C free() may be freeing Rust-allocated memory (_Znwm)",
            .location = Location.init(func_name),
        });

        const vuln_id = ctx.getNextVulnId();
        ctx.addIssue(&Issue.initWithReason(
            .cross_language_leak,
            "Cross-language alloc mismatch: Rust-alloc freed by C free()",
            Location.init(func_name),
            .high,
            0.85,
            "Rust _Znwm allocation freed by C free() - heap mismatch",
        )) catch |err| {
            diag.warn("Failed to register cross_language_leak issue: {any}", .{err});
        };
        diag.err("CROSS-LANG MISMATCH OMI-{d:0>3} [high] [Confidence: high]", .{vuln_id});
        diag.err("Type: cross_language_alloc_mismatch", .{});
        diag.err("Reason: Rust _Znwm allocation freed by C free() - heap mismatch", .{});
    }
}

/// Detect unsafe FFI calls without validation (Rule 4).
///
/// Only flags extern "C" calls that are NOT known safe functions.
/// Pure consumption functions (memcpy, strlen, printf, etc.) and
/// memory management functions (malloc, free, realloc) are excluded
/// because they are well-understood libc APIs with no inherent
/// unsafety beyond what the allocator mismatch pass already covers.
pub fn detectUnsafeFfiCalls(auditor: *Auditor, func: c.LLVMValueRef, insts: []const c.LLVMValueRef, inst_cache: *InstCache) !void {
    var has_unsafe_ffi = false;
    for (insts) |inst| {
        // PERF: Use InstCache for opcode lookup
        const opcode = inst_cache.getOpcode(inst);
        if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

        // PERF: Use InstCache for operand count and callee name lookup
        const num_operands: c_uint = inst_cache.getNumOperands(inst);
        if (num_operands < 2) continue;

        const callee_name = inst_cache.getCalleeName(inst) orelse continue;

        if (isExternCCall(callee_name)) {
            // Exclude pure consumption functions (memcpy, strlen, printf, etc.)
            // — these are well-understood libc APIs, not inherently unsafe.
            if (isPureConsumptionFunction(callee_name)) continue;

            // Exclude memory management functions (malloc, free, realloc, etc.)
            // — allocator mismatch is handled by dedicated passes.
            if (isMemoryManagementFunction(callee_name)) continue;

            // Exclude LLVM intrinsics (already filtered by isExternCCall prefix,
            // but double-check for safety)
            if (std.mem.startsWith(u8, callee_name, "llvm.")) continue;

            has_unsafe_ffi = true;
        }
        if (has_unsafe_ffi) break;
    }

    if (has_unsafe_ffi) {
        auditor.stats.unsafe_ffi_calls += 1;
        const func_name = getFunctionName(func);

        try addFinding(auditor, .{
            .func_name = func_name,
            .issue_type = .unsafe_ffi_call,
            .severity = .medium,
            .confidence = 0.60,
            .reason = "Function contains extern \"C\" calls requiring manual review",
            .location = Location.init(func_name),
        });
    }
}

/// Detect stack address escape to FFI boundary (Rule 5):
/// alloca/local variable address passed to FFI boundary that may retain pointer.
pub fn detectStackEscapeToFFI(auditor: *Auditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter, insts: []const c.LLVMValueRef, inst_cache: *InstCache, fir: *const FunctionIR) !void {
    for (insts) |inst| {
        // PERF: Use InstCache for opcode lookup
        const opcode = inst_cache.getOpcode(inst);
        if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

        // PERF: Use InstCache for callee name lookup (avoids 3 FFI calls)
        const callee_name = inst_cache.getCalleeName(inst) orelse continue;

        // Must be FFI boundary (non-Rust-mangled)
        if (isRustMangledName(callee_name)) continue;
        if (std.mem.startsWith(u8, callee_name, "llvm.")) continue;

        // Skip pure consumption functions (memcpy, printf, etc.)
        if (isPureConsumptionFunction(callee_name)) continue;

        // Semantic classification: if callee is a memory manager (deallocator/reallocator),
        // its arguments are semantically heap pointers — not stack escapes.
        // This is language-agnostic semantic abstraction, not a whitelist.
        if (isMemoryManagerCallee(callee_name)) continue;

        // Check each argument for alloca-derived pointers
        const num_args = c.LLVMGetNumArgOperands(inst);
        var arg_i: u32 = 0;
        while (arg_i < num_args) : (arg_i += 1) {
            const arg = c.LLVMGetOperand(inst, arg_i);
            if (@intFromPtr(arg) == 0) continue;

            // Only check pointer-type arguments
            const arg_type = c.LLVMTypeOf(arg);
            if (@intFromPtr(arg_type) == 0) continue;
            if (c.LLVMGetTypeKind(arg_type) != c.LLVMPointerTypeKind) continue;

            // T3: Use unified traceValueSource instead of isDerivedFromAlloca
            const source = auditor.traceValueSource(arg, func, fir);

            switch (source) {
                .from_code_section, .from_constant => {
                    continue;
                },
                .from_alloca => {},
                .from_parameter => {
                    // Parameters are not stack escapes in the current function.
                    // The caller owns the pointer and is responsible for its lifetime.
                    // Only local alloca (stack allocation) is a real stack escape.
                    continue;
                },
                else => continue,
            }

            // SRT query: trace through def-use chain to check heap/global provenance
            // If the value is derived from a heap allocation, this is NOT a stack escape
            if (ctx.semantic_resolution) |resolution_engine| {
                const srt = resolution_engine.getSemanticTree();
                const arg_ref = @intFromPtr(arg);
                log.debug("[SRT-QUERY] Checking arg {d} for heap_provenance in {s}", .{ arg_ref, callee_name });
                if (srt.*.traceToHeapProvenance(arg, 8)) {
                    // Heap origin — not a stack escape
                    log.debug("[SRT-SUPPRESS] heap_provenance traced for arg {d} -> skip", .{arg_ref});
                    continue;
                } else {
                    log.debug("[SRT-NO-MATCH] arg {d} not traced to heap_provenance", .{arg_ref});
                }
            } else {
                log.warn("[SRT-NULL] semantic_resolution is null! SRT not initialized before RustFfiAuditor", .{});
            }

            // Confirm callee may retain the pointer
            if (mayRetainPointer(callee_name)) {
                auditor.stats.stack_escapes += 1;
                const func_name = getFunctionName(func);

                try addFinding(auditor, .{
                    .func_name = func_name,
                    .issue_type = .stack_address_escape,
                    .severity = .high,
                    .confidence = 0.82,
                    .reason = "Stack address (alloca/local) escapes to FFI function that may retain pointer",
                    .location = Location.init(func_name),
                });

                const source_tag = @tagName(source);
                const trace = try auditor.allocator.alloc(TraceEntry, 4);
                errdefer auditor.allocator.free(trace);
                trace[0] = TraceEntry.init("Stack address escapes across FFI boundary");

                const desc1 = try std.fmt.allocPrint(
                    auditor.allocator,
                    "Argument {d} of {s} derived from {s}",
                    .{ arg_i, callee_name, source_tag },
                );
                errdefer auditor.allocator.free(desc1);
                trace[1] = TraceEntry.initOwned(desc1);

                const desc2 = try std.fmt.allocPrint(
                    auditor.allocator,
                    "Callee may store pointer beyond caller's lifetime",
                    .{},
                );
                errdefer auditor.allocator.free(desc2);
                trace[2] = TraceEntry.initOwned(desc2);

                trace[3] = TraceEntry.init("Provenance-aware: only real stack/parameter sources flagged");

                const msg = try std.fmt.allocPrint(
                    auditor.allocator,
                    "Stack address escapes to FFI: {s}() receives {s}-derived pointer",
                    .{ callee_name, source_tag },
                );
                errdefer auditor.allocator.free(msg);

                const issue = Issue.initWithTrace(
                    .borrow_escape,
                    msg,
                    Location.init(func_name),
                    .high,
                    0.82,
                    trace,
                );
                var mutable_issue = issue;
                mutable_issue.owned = true;
                try ctx.addIssue(&mutable_issue);

                diag.warn("FFIAuditor: stack escape in {s} → {s}() arg {d} [{s}", .{ func_name, callee_name, arg_i, source_tag });
            }
        }
    }
}

/// Rule 6: Ownership Transfer Protocol — detect ownership violations.
///
/// Core insight: Instead of trying to find into_raw (which Rust inlines away),
/// directly detect the DATAFLOW pattern where the same pointer value is:
///   (A) passed to an FFI boundary function (ownership transfer OUT), AND
///   (B) later passed to free/dealloc (double-free risk), OR
///   (C) used after the transfer target may have freed it (UAF risk)
pub fn detectOwnershipTransferViolations(auditor: *Auditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter, insts: []const c.LLVMValueRef, inst_cache: *InstCache) !void {
    // Collect all pointers passed to FFI boundary calls
    var ffi_transferred_ptrs = std.ArrayList(c.LLVMValueRef).initCapacity(auditor.allocator, 16) catch return;
    defer ffi_transferred_ptrs.deinit(auditor.allocator);

    // Collect all pointers passed to free/dealloc calls
    var freed_ptrs = std.ArrayList(FreeEntry).initCapacity(auditor.allocator, 8) catch return;
    defer freed_ptrs.deinit(auditor.allocator);

    const func_name = getFunctionName(func);

    // Single pass: categorize all call/invoke instructions
    for (insts) |inst| {
        // PERF: Use InstCache for opcode and callee name lookup
        const opcode = inst_cache.getOpcode(inst);
        if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

        // PERF: Use InstCache for callee name lookup (avoids 3 FFI calls)
        const callee_name = inst_cache.getCalleeName(inst) orelse continue;

        // Is this an FFI boundary call? (non-Rust-mangled, non-llvm intrinsic)
        // Exclude Rust-internal allocator functions (__rust_alloc, __rust_dealloc, etc.)
        // which are not real FFI boundaries even though they lack the _R mangling prefix.
        const is_rust_alloc = std.mem.startsWith(u8, callee_name, "__rust_alloc") or
            std.mem.startsWith(u8, callee_name, "__rust_dealloc") or
            std.mem.startsWith(u8, callee_name, "__rust_realloc");
        const is_ffi_boundary = !isRustMangledName(callee_name) and
            !std.mem.startsWith(u8, callee_name, "llvm.") and
            !is_rust_alloc;

        // Is this a free-like call?
        const is_free_call = isFreeLikeFunction(callee_name);

        if (is_ffi_boundary) {
            // Record pointer-type arguments that were transferred to FFI
            const num_args = c.LLVMGetNumArgOperands(inst);
            var arg_i: u32 = 0;
            while (arg_i < num_args) : (arg_i += 1) {
                const arg = c.LLVMGetOperand(inst, arg_i);
                if (@intFromPtr(arg) == 0) continue;
                const arg_type = c.LLVMTypeOf(arg);
                if (@intFromPtr(arg_type) == 0) continue;
                if (c.LLVMGetTypeKind(arg_type) == c.LLVMPointerTypeKind) {
                    try ffi_transferred_ptrs.append(auditor.allocator, arg);
                }
            }
        }

        if (is_free_call) {
            // Record the freed pointer
            const num_args = c.LLVMGetNumArgOperands(inst);
            if (num_args >= 1) {
                const freed_arg = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(freed_arg) != 0) {
                    // Store callee_name as slice backed by LLVM string (no copy needed — used immediately below)
                    try freed_ptrs.append(auditor.allocator, .{ .val = freed_arg, .free_name = callee_name });
                }
            }
        }
    }

    if (ffi_transferred_ptrs.items.len == 0 or freed_ptrs.items.len == 0) return;

    // Deduplication: track (freed_val, ffi_val) pairs we've already reported
    var reported = std.AutoHashMap(usize, void).init(auditor.allocator);
    defer reported.deinit();

    // Cross-check: does any freed_ptr match (via def-use chain) any ffi_transferred_ptr?
    for (freed_ptrs.items) |free_entry| {
        for (ffi_transferred_ptrs.items) |ffi_ptr| {
            // Strict check: require same base value, not just any alias
            const free_base = getBaseValue(free_entry.val) orelse continue;
            const ffi_base = getBaseValue(ffi_ptr) orelse continue;
            if (free_base != ffi_base) continue;

            // Compute dedup key from pointer addresses
            const key = @as(usize, @intFromPtr(free_entry.val)) * 31 + @as(usize, @intFromPtr(ffi_ptr));
            if (reported.contains(key)) continue;
            try reported.put(key, {});

            // R-3: Skip ownership violations in Rust drop_in_place functions.
            // These are compiler-generated destructors where the dealloc is
            // part of normal RAII cleanup, not a real ownership violation.
            if (std.mem.indexOf(u8, func_name, "drop_in_place") != null or
                std.mem.indexOf(u8, func_name, "::drop") != null)
            {
                continue;
            }

            // R-3: Skip if the free is __rust_dealloc.
            // __rust_dealloc is Rust's global allocator — calling it means
            // Rust still owns the pointer. Even if the pointer was passed to
            // another language (e.g., C callback), __rust_dealloc is the
            // correct way to free __rust_alloc memory. Real cross-lang free
            // uses C free() or a language-specific deallocator.
            if (std.mem.indexOf(u8, free_entry.free_name, "__rust_dealloc") != null) {
                continue;
            }

            // Suppress FP: intentional ownership transfer (e.g., Box::leak → C free)
            if (isIntentionalOwnershipTransfer(func_name)) {
                diag.info("[SUPPRESSED] FFIAuditor: ownership violation in {s}: intentional ownership transfer detected", .{func_name});
                continue;
            }

            auditor.stats.unpaired_into_raw += 1;

            const trace = try auditor.allocator.alloc(TraceEntry, 3);
            errdefer auditor.allocator.free(trace);

            trace[0] = TraceEntry.init("Ownership violation: pointer transferred to FFI then freed");

            const desc1 = try std.fmt.allocPrint(
                auditor.allocator,
                "Pointer was passed to an FFI boundary call (ownership transfer out)",
                .{},
            );
            errdefer auditor.allocator.free(desc1);
            trace[1] = TraceEntry.initOwned(desc1);

            const desc2 = try std.fmt.allocPrint(
                auditor.allocator,
                "Same pointer also passed to {s}() — potential double-free or cross-allocator-free",
                .{free_entry.free_name},
            );
            errdefer auditor.allocator.free(desc2);
            trace[2] = TraceEntry.initOwned(desc2);

            const msg = try std.fmt.allocPrint(
                auditor.allocator,
                "Ownership violation: FFI-transferred pointer freed by {s}()",
                .{free_entry.free_name},
            );
            errdefer auditor.allocator.free(msg);

            const issue = Issue.initWithTrace(
                .use_after_free,
                msg,
                Location.init(func_name),
                .high,
                0.72,
                trace,
            );
            // Mark as owned so DataFlowGraph will free all allocated memory
            var mutable_issue = issue;
            mutable_issue.owned = true;
            try ctx.addIssue(&mutable_issue);

            diag.warn(
                \\FFIAuditor: ownership violation in {s}
                \\  → pointer transferred to FFI, then freed by {s}()
            , .{ func_name, free_entry.free_name });
        }
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Add a finding to the auditor's findings list.
pub fn addFinding(auditor: *Auditor, finding: RustFfiFinding) !void {
    try auditor.findings.append(auditor.allocator, finding);
}

/// Check if two values may alias (be the same pointer or derived from same source).
/// Broader than valueDependsOn — handles bitcast/GEP chains and direct equality.
pub fn valuesMayAlias(a: c.LLVMValueRef, b: c.LLVMValueRef) bool {
    if (@intFromPtr(a) == 0 or @intFromPtr(b) == 0) return false;
    if (a == b) return true;

    // Follow one level of indirection for both
    const a_unwrapped = unwrapSingleLevel(a);
    const b_unwrapped = unwrapSingleLevel(b);

    if (a_unwrapped == b_unwrapped) return true;
    if (a_unwrapped != null and a_unwrapped.? == b) return true;
    if (b_unwrapped != null and b_unwrapped.? == a) return true;

    // Check if both are pointers to globals or allocations
    if (isSameBasePointer(a, b)) return true;

    return false;
}

/// Unwrap one level of bitcast/GEP/ptrtoint/inttoptr
pub fn unwrapSingleLevel(val: c.LLVMValueRef) ?c.LLVMValueRef {
    if (@intFromPtr(val) == 0) return null;
    const opcode = c.LLVMGetInstructionOpcode(val);
    if (opcode == c.LLVMBitCast or opcode == c.LLVMGetElementPtr or
        opcode == c.LLVMPtrToInt or opcode == c.LLVMIntToPtr)
    {
        return c.LLVMGetOperand(val, 0);
    }
    return null;
}

/// Check if two values may point to the same base allocation.
/// Simple heuristic: both derive from the same alloca/global/call result.
pub fn isSameBasePointer(a: c.LLVMValueRef, b: c.LLVMValueRef) bool {
    // If both are from the same call instruction's result
    const a_base = getBaseValue(a);
    const b_base = getBaseValue(b);
    if (a_base) |ab| {
        if (b_base) |bb| return ab == bb;
    }
    return false;
}

/// Get the "base" value of a pointer chain (strip bitcast/GEP).
pub fn getBaseValue(val: c.LLVMValueRef) ?c.LLVMValueRef {
    var current = val;
    var depth: u32 = 0;
    while (depth < 4) : (depth += 1) {
        if (@intFromPtr(current) == 0) return null;
        const opcode = c.LLVMGetInstructionOpcode(current);
        if (opcode == c.LLVMBitCast or opcode == c.LLVMGetElementPtr) {
            current = c.LLVMGetOperand(current, 0);
        } else {
            break;
        }
    }
    return current;
}

/// Find the call instruction that produces the parent value of an instruction.
/// For extractvalue, this means finding the call that produced the aggregate struct.
pub fn findParentCall(inst: c.LLVMValueRef) ?c.LLVMValueRef {
    if (@intFromPtr(inst) == 0) return null;
    const opcode = c.LLVMGetInstructionOpcode(inst);
    if (opcode != c.LLVMExtractValue and opcode != c.LLVMInsertValue) return null;
    const agg = c.LLVMGetOperand(inst, 0);
    if (@intFromPtr(agg) == 0) return null;
    // Only call GetInstructionOpcode on actual instructions
    if (c.LLVMGetValueKind(agg) != c.LLVMInstructionValueKind) return null;
    const agg_opcode = c.LLVMGetInstructionOpcode(agg);
    if (agg_opcode == c.LLVMCall or agg_opcode == c.LLVMInvoke) return agg;
    // Recurse one level for bitcast/insertvalue wrappers
    if (agg_opcode == c.LLVMBitCast) {
        const src = c.LLVMGetOperand(agg, 0);
        if (@intFromPtr(src) != 0 and c.LLVMGetValueKind(src) == c.LLVMInstructionValueKind) {
            const src_opcode = c.LLVMGetInstructionOpcode(src);
            if (src_opcode == c.LLVMCall or src_opcode == c.LLVMInvoke) return src;
        }
    }
    return null;
}

/// Check if function name looks like a free/dealloc (conservative).
/// Uses canonical dealloc pattern list from ptr_types.RUST_ALLOC_INTRINSICS.dealloc_only.
pub fn isFreeLikeFunction(func_name: []const u8) bool {
    const free_patterns = [_][]const u8{
        "free", "dealloc", "deallocate", "operator delete", "operator delete[]",
    };
    for (free_patterns) |pat| {
        if (std.mem.indexOf(u8, func_name, pat) != null) return true;
    }
    for (ptr_types.RUST_ALLOC_INTRINSICS.dealloc_only) |pat| {
        if (std.mem.indexOf(u8, func_name, pat) != null) return true;
    }
    return false;
}

/// Semantic classification: check if callee is a memory manager function.
/// Memory managers (deallocators, reallocators, size queries) semantically
/// require heap-allocated pointers as arguments. Passing a pointer to them
/// is NOT a stack escape — it's the correct usage pattern.
///
/// This is language-agnostic semantic abstraction based on function semantics,
/// not a project-specific whitelist.
fn isMemoryManagerCallee(callee_name: []const u8) bool {
    // Deallocators: free, dealloc, mi_free, etc.
    if (isFreeLikeFunction(callee_name)) return true;

    // Reallocators: realloc, mi_realloc, etc.
    const realloc_patterns = [_][]const u8{
        "realloc", "mi_expand",
    };
    for (realloc_patterns) |pat| {
        if (std.mem.indexOf(u8, callee_name, pat) != null) return true;
    }

    // Memory size queries: malloc_size, mi_usable_size, etc.
    const size_patterns = [_][]const u8{
        "malloc_size", "mi_usable_size", "malloc_good_size",
    };
    for (size_patterns) |pat| {
        if (std.mem.eql(u8, callee_name, pat)) return true;
    }

    // Heap management: mi_heap_destroy, mi_heap_visit_blocks, etc.
    const heap_patterns = [_][]const u8{
        "mi_heap_destroy", "mi_heap_visit", "mi_heap_check",
    };
    for (heap_patterns) |pat| {
        if (std.mem.indexOf(u8, callee_name, pat) != null) return true;
    }

    return false;
}
