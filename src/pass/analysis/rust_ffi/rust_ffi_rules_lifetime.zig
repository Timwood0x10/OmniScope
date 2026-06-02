//! Rules 6-7: Lifetime and Ownership Risk Detection
//!
//! This module implements lifetime-related Rust FFI safety rules:
//!   - Rule 7: as_ptr dangling detection (borrowed pointer used after parent drop)
//!   - Rule 8: Callback ownership risk (function pointer stored to global)
//!
//! Plus global variable analysis helpers.
//!
//! All functions are standalone (not methods) and take auditor as first parameter.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const rust_drop_semantics = @import("../../../semantics/rust_drop_semantics.zig");
const tracking = @import("../ptr_lifetime/value_tracking.zig");

const PassContext = @import("../../pass.zig").PassContext;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;
const Issue = @import("../../../diag/issue.zig").Issue;
const Location = @import("../../../diag/issue.zig").Location;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;

const rust_ffi_helpers = @import("rust_ffi_helpers.zig");
const getFunctionName = rust_ffi_helpers.getFunctionName;

/// Auditor type
const Auditor = @import("rust_ffi_auditor.zig").RustFfiAuditor;

// Import helpers from basic module
const basic = @import("rust_ffi_rules_basic.zig");
const getBaseValue = basic.getBaseValue;

/// Rule 7: Detect as_ptr dangling — borrowed pointer used after parent deallocation.
/// `insts` is the pre-collected instruction list from auditFunction (no re-traversal).
pub fn detectAsPtrDangling(auditor: *Auditor, func: c.LLVMValueRef, insts: []const c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
    // AsPtrEntry tracks one as_ptr-like extraction
    const AsPtrEntry = struct {
        as_ptr_value: c.LLVMValueRef,
        parent_aggregate: c.LLVMValueRef,
        extraction_inst: c.LLVMValueRef,
    };

    var as_ptrs = std.ArrayList(AsPtrEntry).initCapacity(auditor.allocator, 16) catch return;
    defer as_ptrs.deinit(auditor.allocator);

    const func_name = getFunctionName(func);

    // Use pre-collected instruction list (avoids redundant BB/inst traversal).
    for (insts) |inst| {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        // Pattern: GEP extracting field 0 from a struct → likely as_ptr
        if (opcode == c.LLVMGetElementPtr) {
            const result_type = c.LLVMTypeOf(inst);
            if (@intFromPtr(result_type) == 0) continue;
            if (c.LLVMGetTypeKind(result_type) != c.LLVMPointerTypeKind) continue;

            const operand = c.LLVMGetOperand(inst, 0);
            if (@intFromPtr(operand) == 0) continue;
            const operand_type = c.LLVMTypeOf(operand);
            if (@intFromPtr(operand_type) == 0) continue;

            // Parent must be a struct type (Vec = {ptr, len, cap}, String = {ptr, len})
            if (c.LLVMGetTypeKind(operand_type) == c.LLVMStructTypeKind) {
                try as_ptrs.append(auditor.allocator, .{
                    .as_ptr_value = inst,
                    .parent_aggregate = operand,
                    .extraction_inst = inst,
                });
            }
        }
    }

    if (as_ptrs.items.len == 0) return;

    // For each as_ptr, check if parent is dropped before last use of as_ptr result
    for (as_ptrs.items) |entry| {
        var parent_dropped_at: ?usize = null;
        var last_use_at: ?usize = null;

        for (insts, 0..) |inst_i, idx| {
            const opcode = c.LLVMGetInstructionOpcode(inst_i);

            // Check if this instruction drops/deallocates the parent
            if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
                const called_val = c.LLVMGetCalledValue(inst_i);
                if (@intFromPtr(called_val) != 0) {
                    const callee_name_ptr = c.LLVMGetValueName(called_val);
                    if (@intFromPtr(callee_name_ptr) != 0) {
                        const callee_name = std.mem.span(callee_name_ptr);
                        // Is this a drop/dealloc on the parent or something derived from it?
                        const drop_class = rust_drop_semantics.classifyDropCall(callee_name);
                        const is_drop = drop_class == .is_drop_glue or
                            drop_class == .is_dealloc_in_drop_chain or
                            drop_class == .is_manual_free;
                        if (is_drop) {
                            // Check if any argument derives from the parent
                            const num_args = c.LLVMGetNumArgOperands(inst_i);
                            var arg_j: u32 = 0;
                            while (arg_j < num_args) : (arg_j += 1) {
                                const arg = c.LLVMGetOperand(inst_i, arg_j);
                                if (@intFromPtr(arg) == 0) continue;
                                const base = getBaseValue(arg) orelse continue;
                                const parent_base = getBaseValue(entry.parent_aggregate) orelse continue;
                                if (base == parent_base) {
                                    parent_dropped_at = idx;
                                    break;
                                }
                            }
                        }
                    }
                }
            }

            // Check if this instruction uses the as_ptr value (or derived from it)
            if (instructionUsesValue(inst_i, entry.as_ptr_value)) {
                last_use_at = idx;
            }
        }

        // Report if parent was dropped before the last use
        if (parent_dropped_at) |drop_idx| {
            if (last_use_at) |use_idx| {
                if (use_idx > drop_idx) {
                    auditor.stats.as_ptr_escapes += 1;

                    const trace = try auditor.allocator.alloc(TraceEntry, 3);
                    errdefer auditor.allocator.free(trace);

                    trace[0] = TraceEntry.init("Dangling reference via as_ptr after implicit scope-end drop");

                    const desc1 = try std.fmt.allocPrint(
                        auditor.allocator,
                        "Borrowed pointer (as_ptr/GEP field 0) from aggregate still used after parent dropped",
                        .{},
                    );
                    errdefer auditor.allocator.free(desc1);
                    trace[1] = TraceEntry.initOwned(desc1);

                    const desc2 = try std.fmt.allocPrint(
                        auditor.allocator,
                        "Parent dropped at instruction {d}, but pointer used again at instruction {d}",
                        .{ drop_idx, use_idx },
                    );
                    errdefer auditor.allocator.free(desc2);
                    trace[2] = TraceEntry.initOwned(desc2);

                    const msg = try std.fmt.allocPrint(
                        auditor.allocator,
                        "Dangling as_ptr: borrowed pointer used after parent deallocation in {s}",
                        .{func_name},
                    );
                    errdefer auditor.allocator.free(msg);

                    const issue = Issue.initWithTrace(
                        .borrow_escape,
                        msg,
                        Location.init(func_name),
                        .high,
                        0.78,
                        trace,
                    );
                    var mutable_issue = issue;
                    mutable_issue.owned = true;
                    try ctx.addIssue(&mutable_issue);

                    diag.warn(
                        \\FFIAuditor: dangling as_ptr in {s}
                        \\  → borrowed pointer used after parent was dropped
                    , .{func_name});
                }
            }
        }
    }
}

/// Rule 8: Detect callback ownership risk — function pointer parameter stored to global.
///
/// GO-05 pattern: Function pointer from caller is stored to a global variable.
/// When this global is later used for an indirect call, the callback may dangle
/// if the original function/stack frame has been destroyed.
///
/// T4 enhanced: Two detection modes:
///   Mode A (original): store ptr @global where value is from_parameter
///                     and global is used for indirect calls
///   Mode B (new):      any from_parameter value whose usage includes
///                     as_call_target — catches local callback vars too
/// `insts` is the pre-collected instruction list from auditFunction (no re-traversal).
pub fn detectCallbackOwnershipRisk(auditor: *Auditor, func: c.LLVMValueRef, insts: []const c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
    const func_name = getFunctionName(func);

    // Collect all parameter values for Mode B scan
    const MaxParams: usize = 16;
    var param_count: usize = 0;
    var param_vals: [MaxParams]c.LLVMValueRef = undefined;

    const num_params = c.LLVMCountParams(func);
    var pi: c_uint = 0;
    while (pi < num_params and param_count < MaxParams) : (pi += 1) {
        const param = c.LLVMGetParam(func, pi);
        if (@intFromPtr(param) != 0) {
            param_vals[param_count] = param;
            param_count += 1;
        }
    }

    for (insts) |inst| {
        const opcode = c.LLVMGetInstructionOpcode(inst);
        if (opcode != c.LLVMStore) continue;

        // ── Mode A: Store to global variable (original logic) ──
        const dest = c.LLVMGetOperand(inst, 1);
        if (@intFromPtr(dest) == 0) continue;

        if (c.LLVMIsAGlobalValue(dest) != null) {
            const global_name_ptr = c.LLVMGetValueName(dest);
            const global_name = if (@intFromPtr(global_name_ptr) != 0)
                std.mem.span(global_name_ptr)
            else
                "@anonymous_global";

            if (isSafeGlobalStore(global_name)) continue;

            const value = c.LLVMGetOperand(inst, 0);
            if (@intFromPtr(value) == 0) continue;

            const value_type = c.LLVMTypeOf(value);
            if (@intFromPtr(value_type) == 0) continue;
            if (c.LLVMGetTypeKind(value_type) != c.LLVMPointerTypeKind) continue;

            // T4: Use unified traceValueSource instead of isValueFromParameter
            const source = auditor.traceValueSource(value, func);
            if (source != .from_parameter) continue;

            // Verify global is used for indirect calls (behavioral confirmation)
            if (!isGlobalUsedForIndirectCall(global_name, func)) continue;

            try reportCallbackRisk(auditor, ctx, diag, func_name, global_name, "global", 0.85);
        }

        // ── Mode B: Store to alloca (local callback variable) — NEW ──
        if (c.LLVMGetInstructionOpcode(dest) == c.LLVMAlloca) {
            const value = c.LLVMGetOperand(inst, 0);
            if (@intFromPtr(value) == 0) continue;

            const source = auditor.traceValueSource(value, func);
            if (source != .from_parameter) continue;

            // Check if this alloca's loaded value is ever used as call target
            const usages = auditor.traceValueUsage(value, func);
            if (usages) |*u| {
                if (u.contains(.as_call_target)) {
                    try reportCallbackRisk(auditor, ctx, diag, func_name, "@local_callback", "local_alloca", 0.78);
                }
            }
        }
    }
}

/// Report a callback ownership risk finding (shared by Mode A and Mode B).
pub fn reportCallbackRisk(
    auditor: *Auditor,
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    func_name: []const u8,
    storage_name: []const u8,
    storage_kind: []const u8,
    confidence: f32,
) !void {
    const trace = try auditor.allocator.alloc(TraceEntry, 4);
    errdefer auditor.allocator.free(trace);
    trace[0] = TraceEntry.init("Function pointer parameter stored to persistent location");
    trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(auditor.allocator, "Storage: {s} ({s})", .{ storage_name, storage_kind }));
    trace[2] = TraceEntry.init("Callback lifetime controlled by caller — may dangle if caller's scope ends");
    trace[3] = TraceEntry.init("Indirect call via this storage may use-after-return (CWE-825)");

    const message = try std.fmt.allocPrint(
        auditor.allocator,
        "Callback ownership risk: fn param → {s} ({s}) — caller controls lifetime",
        .{ storage_name, storage_kind },
    );

    var issue = Issue.initWithTrace(
        .callback_ownership_risk,
        message,
        Location.init(func_name),
        .high,
        confidence,
        trace,
    );
    errdefer issue.deinit(auditor.allocator);

    try ctx.addIssue(&issue);
    diag.warn("[OMI-HIGH] [CALLBACK-RISK] fn param -> {s} in {s}", .{ storage_name, func_name });
}

// ============================================================================
// Global Variable Helpers
// ============================================================================

/// Check if storing to this global is a known-safe pattern (false positive suppression).
pub fn isSafeGlobalStore(global_name: []const u8) bool {
    const safe_prefixes = [_][]const u8{
        "__sig_", "_ZTV",   "_ZTI",       ".cxx_delet",
        "atexit", "__cxa_", "__pthread_", "_fini",
        "_init",  ".llvm.",
    };
    for (safe_prefixes) |prefix| {
        if (std.mem.indexOf(u8, global_name, prefix) != null) return true;
    }

    const safe_globals = [_][]const u8{
        "environ", "stderr", "stdout", "stdin", "optarg", "errno",
    };
    for (safe_globals) |safe_name| {
        if (std.mem.eql(u8, global_name, safe_name)) return true;
    }
    return false;
}

/// Check if a global variable is used for indirect calls anywhere in the module.
/// This confirms that the global is being treated as a function pointer (callback).
pub fn isGlobalUsedForIndirectCall(global_name: []const u8, current_func: c.LLVMValueRef) bool {
    const module = c.LLVMGetGlobalParent(current_func);
    if (@intFromPtr(module) == 0) return false;

    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                const opcode = c.LLVMGetInstructionOpcode(inst);

                // Check for indirect call (call/invoke with non-function callee)
                if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
                    const callee = c.LLVMGetCalledValue(inst);
                    if (@intFromPtr(callee) == 0) continue;

                    // If callee is not a direct function, it's an indirect call
                    if (c.LLVMIsAFunction(callee) == null) {
                        // Check if this indirect call uses our global
                        if (isValueFromGlobal(callee, global_name)) {
                            return true;
                        }
                    }
                }
            }
        }
    }

    return false;
}

/// Check if a value ultimately originates from a specific global variable.
/// Handles: load @global, or load → bitcast → load chain
pub fn isValueFromGlobal(value: c.LLVMValueRef, global_name: []const u8) bool {
    // Direct: value IS the global
    if (c.LLVMIsAGlobalValue(value) != null) {
        const name_ptr = c.LLVMGetValueName(value);
        if (@intFromPtr(name_ptr) != 0) {
            const val_name = std.mem.span(name_ptr);
            if (std.mem.eql(u8, val_name, global_name)) return true;
        }
    }

    // Indirect: value is a load from the global
    const opcode = c.LLVMGetInstructionOpcode(value);
    if (opcode == c.LLVMLoad) {
        const ptr_op = c.LLVMGetOperand(value, 0);
        if (@intFromPtr(ptr_op) != 0) {
            return isValueFromGlobal(ptr_op, global_name);
        }
    }

    // Through bitcast/GEP
    if (opcode == c.LLVMBitCast or opcode == c.LLVMGetElementPtr) {
        const src = c.LLVMGetOperand(value, 0);
        if (@intFromPtr(src) != 0) {
            return isValueFromGlobal(src, global_name);
        }
    }

    return false;
}

/// T5 helper: Check if an instruction has debug metadata indicating struct type.
pub fn hasStructDebugMetadata(inst: c.LLVMValueRef) bool {
    return tracking.hasStructDebugMetadata(inst);
}

/// Check if an instruction uses (or transitively uses) a given value.
pub fn instructionUsesValue(inst: c.LLVMValueRef, target: c.LLVMValueRef) bool {
    return tracking.instructionUsesValue(inst, target);
}
