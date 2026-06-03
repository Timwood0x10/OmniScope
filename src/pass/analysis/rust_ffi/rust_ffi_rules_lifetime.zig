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
const ir_store_mod = @import("../../../ir/ir_store.zig");
const ModuleIRStore = ir_store_mod.ModuleIRStore;
const FunctionIR = ir_store_mod.FunctionIR;
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
/// Uses pre-categorized `fir.geps` and `fir.calls` plus `fir.inst_index` for
/// O(1) position lookups, instead of the previous O(geps × insts) double scan.
pub fn detectAsPtrDangling(auditor: *Auditor, func: c.LLVMValueRef, insts: []const c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter, fir: *const FunctionIR) !void {
    _ = insts;
    // AsPtrEntry tracks one as_ptr-like extraction
    const AsPtrEntry = struct {
        as_ptr_value: c.LLVMValueRef,
        parent_aggregate: c.LLVMValueRef,
        extraction_inst: c.LLVMValueRef,
    };

    var as_ptrs = std.ArrayList(AsPtrEntry).initCapacity(auditor.allocator, 16) catch return;
    defer as_ptrs.deinit(auditor.allocator);

    const func_name = getFunctionName(func);

    // Pass 1: collect candidate as_ptr extractions from fir.geps only
    // (no need to scan all instructions — opcode-filtered upfront).
    for (fir.geps) |inst| {
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

    if (as_ptrs.items.len == 0) return;

    // Pass 2: single linear scan over fir.calls to find drops on each parent.
    // We cache the drop position (in instruction-order via fir.inst_index)
    // for each as_ptr entry, so the use-after check is just an integer compare.
    const MaxAsPtrs: usize = 32;
    const n = @min(as_ptrs.items.len, MaxAsPtrs);

    var drop_idx: [MaxAsPtrs]?u32 = .{null} ** MaxAsPtrs;
    var last_use_idx: [MaxAsPtrs]?u32 = .{null} ** MaxAsPtrs;

    // Drop scan: only calls/invokes can be drops, so iterate fir.calls.
    for (fir.calls) |inst_i| {
        const called_val = c.LLVMGetCalledValue(inst_i);
        if (@intFromPtr(called_val) == 0) continue;
        const callee_name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(callee_name_ptr) == 0) continue;
        const callee_name = std.mem.span(callee_name_ptr);

        const drop_class = rust_drop_semantics.classifyDropCall(callee_name);
        const is_drop = drop_class == .is_drop_glue or
            drop_class == .is_dealloc_in_drop_chain or
            drop_class == .is_manual_free;
        if (!is_drop) continue;

        const call_idx = fir.indexOf(inst_i) orelse continue;

        // Check each as_ptr entry against this drop call's arguments
        const num_args = c.LLVMGetNumArgOperands(inst_i);
        var arg_j: u32 = 0;
        while (arg_j < num_args) : (arg_j += 1) {
            const arg = c.LLVMGetOperand(inst_i, arg_j);
            if (@intFromPtr(arg) == 0) continue;
            const arg_base = getBaseValue(arg) orelse continue;

            for (as_ptrs.items[0..n], 0..) |entry, k| {
                const parent_base = getBaseValue(entry.parent_aggregate) orelse continue;
                if (arg_base != parent_base) continue;
                // Earliest drop position — only update if not set or call earlier
                if (drop_idx[k]) |existing| {
                    if (call_idx < existing) drop_idx[k] = call_idx;
                } else {
                    drop_idx[k] = call_idx;
                }
            }
        }
    }

    // Use scan: walk all instructions once, tracking the latest use position
    // per as_ptr entry. instructionUsesValue is O(operands) per inst — cheap.
    for (fir.instructions, 0..) |inst_i, idx_usize| {
        const idx: u32 = @intCast(idx_usize);
        for (as_ptrs.items[0..n], 0..) |entry, k| {
            if (instructionUsesValue(inst_i, entry.as_ptr_value)) {
                last_use_idx[k] = idx;
            }
        }
    }

    // Pass 3: report any as_ptr whose last use comes after the parent drop.
    for (as_ptrs.items[0..n], 0..) |_, k| {
        const d = drop_idx[k] orelse continue;
        const u = last_use_idx[k] orelse continue;
        if (u <= d) continue;

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
            .{ d, u },
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
/// Uses fir.stores (pre-filtered Store only) instead of full insts[] for 10x reduction.
pub fn detectCallbackOwnershipRisk(auditor: *Auditor, func: c.LLVMValueRef, insts: []const c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter, fir: *const FunctionIR) !void {
    _ = insts;
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

    for (fir.stores) |inst| {
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
            const source = auditor.traceValueSource(value, func, fir);
            if (source != .from_parameter) continue;

            // Verify global is used for indirect calls (behavioral confirmation)
            if (!isGlobalUsedForIndirectCall(global_name, ctx.ir_store)) continue;

            try reportCallbackRisk(auditor, ctx, diag, func_name, global_name, "global", 0.85);
        }

        // ── Mode B: Store to alloca (local callback variable) — NEW ──
        if (c.LLVMGetInstructionOpcode(dest) == c.LLVMAlloca) {
            const value = c.LLVMGetOperand(inst, 0);
            if (@intFromPtr(value) == 0) continue;

            const source = auditor.traceValueSource(value, func, fir);
            if (source != .from_parameter) continue;

            // Check if this alloca's loaded value is ever used as call target
            const usages = auditor.traceValueUsage(value, func, fir);
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
/// Uses IR Store pre-categorized calls[] — eliminates full module BB/inst traversal.
pub fn isGlobalUsedForIndirectCall(global_name: []const u8, ir_store: *const ModuleIRStore) bool {
    for (ir_store.function_list) |fir| {
        // fir.calls[] contains only Call/Invoke instructions — no opcode check needed
        for (fir.calls) |inst| {
            const callee = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(callee) == 0) continue;

            // Indirect call: callee is not a direct function reference
            if (c.LLVMIsAFunction(callee) == null) {
                if (isValueFromGlobal(callee, global_name)) return true;
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
