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
const c = @import("../../../ir/llvm_raw.zig").c;
const ptr_types = @import("../ptr_lifetime/ptr_lifetime_types.zig");
const tracking = @import("../ptr_lifetime/value_tracking.zig");

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

/// Auditor type (forward declaration - will be resolved at compile time)
const Auditor = @import("rust_ffi_auditor.zig").RustFfiAuditor;

/// Detect as_ptr borrow escape in function body (Rule 2).
pub fn detectAsPtrEscape(auditor: *Auditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

            const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
            if (num_operands < 2) continue;

            const callee = c.LLVMGetOperand(inst, num_operands - 1);
            if (@intFromPtr(callee) == 0) continue;
            const callee_name = c.LLVMGetValueName(callee);
            if (@intFromPtr(callee_name) == 0) continue;
            const name_slice = std.mem.sliceTo(callee_name, 0);

            if (!isRustAsPtrCall(name_slice)) continue;

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
}

/// Detect cross-language allocation mismatch (Rule 3): Rust _Znwm → C free.
pub fn detectCrossLangMismatch(auditor: *Auditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
    var visited = std.AutoHashMap(usize, void).init(auditor.allocator);
    defer visited.deinit();

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

            const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
            if (num_operands < 2) continue;

            const callee = c.LLVMGetOperand(inst, num_operands - 1);
            if (@intFromPtr(callee) == 0) continue;
            const callee_name = c.LLVMGetValueName(callee);
            if (@intFromPtr(callee_name) == 0) continue;
            const name_slice = std.mem.sliceTo(callee_name, 0);

            if (!isCFreeCall(name_slice)) continue;

            // Get the pointer argument to free() and trace its origin
            const ptr_arg = c.LLVMGetOperand(inst, 0);
            if (@intFromPtr(ptr_arg) == 0) continue;

            // Only report if the pointer can be traced back to a Rust allocator
            if (!ptrOriginatesFromRustAlloc(func, ptr_arg, &visited)) continue;

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
}

/// Detect unsafe FFI calls without validation (Rule 4).
pub fn detectUnsafeFfiCalls(auditor: *Auditor, func: c.LLVMValueRef) !void {
    var has_unsafe_ffi = false;
    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

            const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
            if (num_operands < 2) continue;

            const callee = c.LLVMGetOperand(inst, num_operands - 1);
            if (@intFromPtr(callee) == 0) continue;
            const callee_name = c.LLVMGetValueName(callee);
            if (@intFromPtr(callee_name) == 0) continue;
            const name_slice = std.mem.sliceTo(callee_name, 0);

            if (isExternCCall(name_slice)) {
                has_unsafe_ffi = true;
            }
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
pub fn detectStackEscapeToFFI(auditor: *Auditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

            const called_val = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(called_val) == 0) continue;

            const callee_name_ptr = c.LLVMGetValueName(called_val);
            if (@intFromPtr(callee_name_ptr) == 0) continue;
            const callee_name = std.mem.span(callee_name_ptr);

            // Must be FFI boundary (non-Rust-mangled)
            if (isRustMangledName(callee_name)) continue;
            if (std.mem.startsWith(u8, callee_name, "llvm.")) continue;

            // Skip pure consumption functions (memcpy, printf, etc.)
            if (isPureConsumptionFunction(callee_name)) continue;

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
                const source = auditor.traceValueSource(arg, func);

                switch (source) {
                    .from_code_section, .from_constant => {
                        continue;
                    },
                    .from_alloca, .from_parameter => {},
                    else => continue,
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
}

/// Rule 6: Ownership Transfer Protocol — detect ownership violations.
///
/// Core insight: Instead of trying to find into_raw (which Rust inlines away),
/// directly detect the DATAFLOW pattern where the same pointer value is:
///   (A) passed to an FFI boundary function (ownership transfer OUT), AND
///   (B) later passed to free/dealloc (double-free risk), OR
///   (C) used after the transfer target may have freed it (UAF risk)
pub fn detectOwnershipTransferViolations(auditor: *Auditor, func: c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
    // Collect all pointers passed to FFI boundary calls
    var ffi_transferred_ptrs = std.ArrayList(c.LLVMValueRef).initCapacity(auditor.allocator, 16) catch return;
    defer ffi_transferred_ptrs.deinit(auditor.allocator);

    // Collect all pointers passed to free/dealloc calls
    var freed_ptrs = std.ArrayList(FreeEntry).initCapacity(auditor.allocator, 8) catch return;
    defer freed_ptrs.deinit(auditor.allocator);

    const func_name = getFunctionName(func);

    // Single pass: categorize all call/invoke instructions
    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

            const called_val = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(called_val) == 0) continue;
            const name_ptr = c.LLVMGetValueName(called_val);
            if (@intFromPtr(name_ptr) == 0) continue;
            const callee_name = std.mem.span(name_ptr);

            // Is this an FFI boundary call? (non-Rust-mangled, non-llvm intrinsic)
            const is_ffi_boundary = !isRustMangledName(callee_name) and
                !std.mem.startsWith(u8, callee_name, "llvm.");

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
