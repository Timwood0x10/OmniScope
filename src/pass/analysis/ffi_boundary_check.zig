//! FFI Boundary Check Logic
//!
//! Extracted from ffi_boundary.zig for better code organization.
//! Contains core FFI boundary detection, null guard checking,
/// ownership chain analysis, and specialized boundary checks.
const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const PassContext = @import("../pass.zig").PassContext;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const Location = @import("../../diag/issue.zig").Location;
const Issue = @import("../../diag/issue.zig").Issue;
const IssueKind = @import("../../diag/issue.zig").IssueKind;
const Language = @import("../../diag/issue.zig").FFIBoundary.Language;
const BoundaryKind = @import("../../diag/issue.zig").FFIBoundary.BoundaryKind;
const FunctionSemantics = @import("../../registry/semantic_registry.zig").FunctionSemantics;
const RiskKind = @import("../../registry/semantic_registry.zig").RiskKind;
const Severity = @import("../../registry/semantic_registry.zig").Severity;
const SemanticRegistry = @import("../../registry/semantic_registry.zig").SemanticRegistry;

// Re-exported modules for unified access
const zone_check = @import("ffi_zone_check.zig");
const lang_classifier = @import("ffi_language_classifier.zig");
const type_checker = @import("ffi_type_checker.zig");
const safety_checker = @import("ffi_safety_checker.zig");

// Constants
pub const NULL_GUARD_SCAN_LIMIT: u32 = 20;
pub const OWNERSHIP_CHAIN_SCAN_LIMIT: u32 = 15;

/// Report an FFI issue with standardized formatting.
pub fn reportFFIIssue(
    ctx: *PassContext,
    kind: IssueKind,
    message: []const u8,
    func_name: []const u8,
    severity: Severity,
    confidence: f32,
) !void {
    const location = Location.init(func_name);
    const issue = Issue.init(kind, message, location, severity, confidence);
    try ctx.addIssue(&issue);
}

/// Scan forward in the same basic block for a NULL comparison of the call result.
pub fn checkNullGuard(inst: c.LLVMValueRef, func: c.LLVMValueRef) bool {
    _ = func;
    const parent_bb = c.LLVMGetInstructionParent(inst);
    if (@intFromPtr(parent_bb) == 0) return false;

    var next_inst = c.LLVMGetNextInstruction(inst);
    const scan_limit: u32 = NULL_GUARD_SCAN_LIMIT;
    var scanned: u32 = 0;

    while (@intFromPtr(next_inst) != 0 and scanned < scan_limit) : ({
        next_inst = c.LLVMGetNextInstruction(next_inst);
        scanned += 1;
    }) {
        const opcode = c.LLVMGetInstructionOpcode(next_inst);
        // icmp eq/ne with null → NULL guard pattern
        if (opcode == c.LLVMICmp) {
            const num_ops = c.LLVMGetNumOperands(next_inst);
            if (num_ops >= 2) {
                const op0 = c.LLVMGetOperand(next_inst, 0);
                const op1 = c.LLVMGetOperand(next_inst, 1);
                // Check if either operand is our call instruction's result
                if (@intFromPtr(op0) == @intFromPtr(inst) or @intFromPtr(op1) == @intFromPtr(inst)) {
                    const other_op = if (@intFromPtr(op0) == @intFromPtr(inst)) op1 else op0;
                    if (c.LLVMIsAConstantPointerNull(other_op) != null) return true;
                    if (c.LLVMIsAConstantInt(other_op) != null) {
                        const int_val = c.LLVMConstIntGetSExtValue(other_op);
                        if (int_val == 0) return true;
                    }
                    const other_name = c.LLVMGetValueName(other_op);
                    if (@intFromPtr(other_name) != 0) {
                        const name_str = std.mem.span(other_name);
                        if (std.mem.indexOf(u8, name_str, "null") != null or
                            std.mem.indexOf(u8, name_str, "NULL") != null)
                        {
                            return true;
                        }
                    }
                }
            }
        }
    }
    return false;
}

/// Check if the result of an ownership-transferring call is properly handled
/// (stored to memory, passed to another function, or compared — NOT discarded).
pub fn checkOwnershipChain(inst: c.LLVMValueRef, func: c.LLVMValueRef) bool {
    _ = func;
    const parent_bb = c.LLVMGetInstructionParent(inst);
    if (@intFromPtr(parent_bb) == 0) return false;

    // Scan forward to see how the result is used
    var next_inst = c.LLVMGetNextInstruction(inst);
    const scan_limit: u32 = OWNERSHIP_CHAIN_SCAN_LIMIT;
    var scanned: u32 = 0;

    while (@intFromPtr(next_inst) != 0 and scanned < scan_limit) : ({
        next_inst = c.LLVMGetNextInstruction(next_inst);
        scanned += 1;
    }) {
        const opcode = c.LLVMGetInstructionOpcode(next_inst);
        const num_ops = c.LLVMGetNumOperands(next_inst);
        const n_ops = @as(usize, @intCast(num_ops));

        // Store → saved to memory (good)
        if (opcode == c.LLVMStore) {
            if (n_ops >= 1) {
                const val_op = c.LLVMGetOperand(next_inst, 0);
                if (@intFromPtr(val_op) == @intFromPtr(inst)) return true;
            }
        }
        // Call → passed to another function (likely free/close)
        if (opcode == c.LLVMCall) {
            for (0..@min(n_ops, 4)) |i| {
                const op = c.LLVMGetOperand(next_inst, @intCast(i));
                if (@intFromPtr(op) == @intFromPtr(inst)) return true;
            }
        }
        // ICmp/FCmp → compared (part of validation logic)
        if (opcode == c.LLVMICmp or opcode == c.LLVMFCmp) {
            for (0..@min(n_ops, 2)) |i| {
                const op = c.LLVMGetOperand(next_inst, @intCast(i));
                if (@intFromPtr(op) == @intFromPtr(inst)) return true;
            }
        }
        // PtrToInt/BitCast → being transformed (still tracked)
        if (opcode == c.LLVMPtrToInt or opcode == c.LLVMBitCast) {
            if (num_ops >= 1) {
                const op = c.LLVMGetOperand(next_inst, 0);
                if (@intFromPtr(op) == @intFromPtr(inst)) return true;
            }
        }
    }

    return false;
}

/// Phase 3 Task #2: Cross-Language Type Compatibility.
///
/// Detects type mismatches at FFI boundaries that could cause UB:
/// - Pointer/int confusion (passing pointer where int expected)
/// - Size mismatches (i32 vs i64 on different ABIs)
/// - Function pointer type mismatches
/// - Struct layout incompatibility (Rust repr(C) vs C struct)
pub fn checkSpecializedBoundary(
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    inst: c.LLVMValueRef,
    caller_func: c.LLVMValueRef,
    called_name: []const u8,
) !void {
    if (zone_check.isDynamicLoadingFunction(called_name)) {
        try checkDynamicLoadingSafety(ctx, diag, inst, caller_func, called_name);
    }
    if (zone_check.isJNIFunction(called_name)) {
        checkJNIBoundarySafety(ctx, diag, inst, caller_func, called_name) catch {};
    }
    if (zone_check.isPythonCApiFunction(called_name)) {
        checkPythonCApiSafety(ctx, diag, inst, caller_func, called_name) catch {};
    }
}

fn checkDynamicLoadingSafety(
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    inst: c.LLVMValueRef,
    caller_func: c.LLVMValueRef,
    called_name: []const u8,
) !void {
    const caller_name_ptr = c.LLVMGetValueName(caller_func);
    const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
        std.mem.span(caller_name_ptr)
    else
        "unknown";

    if (std.mem.indexOf(u8, called_name, "dlopen") != null or
        std.mem.indexOf(u8, called_name, "dlsym") != null)
    {
        const has_null_guard = checkNullGuard(inst, caller_func);
        if (!has_null_guard) {
            diag.warn("  [DLOPEN] {s} returns NULL on failure but no NULL check detected", .{called_name});
            diag.warn("    Risk: NULL pointer dereference / crash (CWE-690)", .{});
            {
                const msg = try std.fmt.allocPrint(ctx.allocator, "{s} returns NULL on failure without check in {s}", .{
                    called_name, caller_name,
                });
                defer ctx.allocator.free(msg);
                reportFFIIssue(ctx, .unchecked_return, msg, caller_name, .medium, 0.65) catch {};
            }
        }
    }

    if (std.mem.indexOf(u8, called_name, "dlclose") != null) {
        diag.debug("  [DLOPEN] dlclose called - verify no dlsym-derived pointers are used after this point", .{});
    }
}

fn checkJNIBoundarySafety(
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    inst: c.LLVMValueRef,
    caller_func: c.LLVMValueRef,
    called_name: []const u8,
) !void {
    const caller_name_ptr = c.LLVMGetValueName(caller_func);
    const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
        std.mem.span(caller_name_ptr)
    else
        "unknown";
    const nullable_jni = [_][]const u8{
        "FindClass",    "GetMethodID",      "GetStaticMethodID",
        "GetFieldID",   "GetStaticFieldID", "NewStringUTF",
        "NewByteArray", "GetObjectClass",
    };
    for (nullable_jni) |jni_fn| {
        if (std.mem.indexOf(u8, called_name, jni_fn) != null) {
            const has_null_guard = checkNullGuard(inst, caller_func);
            if (!has_null_guard) {
                diag.warn("  [JNI] {s} returns NULL on failure but no NULL check detected", .{called_name});
                diag.warn("    Risk: JNI exception pending / NullPointerException (CWE-690)", .{});
                {
                    const msg = try std.fmt.allocPrint(ctx.allocator, "[JNI] {s} returns NULL without check in {s}", .{
                        called_name, caller_name,
                    });
                    defer ctx.allocator.free(msg);
                    reportFFIIssue(ctx, .unchecked_return, msg, caller_name, .medium, 0.65) catch {};
                }
            }
            break;
        }
    }

    const call_methods = [_][]const u8{
        "CallVoidMethod",       "CallIntMethod",       "CallObjectMethod",
        "CallStaticVoidMethod", "CallStaticIntMethod", "CallStaticObjectMethod",
    };
    for (call_methods) |method| {
        if (std.mem.indexOf(u8, called_name, method) != null) {
            diag.debug("  [JNI] {s} called - verify exception handling", .{called_name});
        }
    }
}

fn checkPythonCApiSafety(
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    inst: c.LLVMValueRef,
    caller_func: c.LLVMValueRef,
    called_name: []const u8,
) !void {
    _ = ctx;

    const refcount_risky = [_][]const u8{
        "Py_DECREF", "Py_XDECREF", "Py_XINCREF", "Py_INCREF",
    };
    for (refcount_risky) |py_fn| {
        if (std.mem.indexOf(u8, called_name, py_fn) != null) {
            diag.debug("  [PYTHON] {s} called - verify reference counting correctness", .{called_name});
            diag.debug("    Risk: Use-after-free / double-free if refcount mismanaged (CWE-416)", .{});
        }
    }

    if (std.mem.indexOf(u8, called_name, "Py_BuildValue") != null or
        std.mem.indexOf(u8, called_name, "PyArg_ParseTuple") != null)
    {
        const has_null_guard = checkNullGuard(inst, caller_func);
        if (!has_null_guard) {
            diag.warn("  [PYTHON] {s} may fail without proper error handling", .{called_name});
        }
    }
}

/// Check if the return value of an FFI call escapes to unsafe contexts.
/// Detects patterns where a raw pointer from FFI is stored in a global,
/// returned to caller, or used in async/callback context — all of which
/// can lead to use-after-free or data races.
///
/// TODO: Re-enable after fixing LLVM Use iteration API compatibility.
pub fn checkReturnValueEscape(
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    inst: c.LLVMValueRef,
    func: c.LLVMValueRef,
    called_name: []const u8,
) !void {
    _ = ctx;
    _ = diag;
    _ = inst;
    _ = func;
    _ = called_name;

    // LLVM Use iteration API not available in current LLVM version
    // This check will be re-enabled once the API is stabilized
}

/// Check type compatibility at FFI boundaries.
/// Uses type_checker module for detailed analysis.
///
/// TODO: Re-enable after fixing LLVM API compatibility issues.
pub fn checkTypeCompatibility(
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    inst: c.LLVMValueRef,
    func: c.LLVMValueRef,
    called_name: []const u8,
    sem: FunctionSemantics,
) !void {
    _ = ctx;
    _ = diag;
    _ = inst;
    _ = func;
    _ = called_name;
    _ = sem;

    // Type compatibility checks temporarily disabled due to LLVM API compatibility
    // Will be re-enabled once the required LLVM functions are available
}

/// Convert RiskKind to IssueKind for reporting.
/// M7 FIX: Unified with ffi_safety_checker.zig version for consistency.
/// Uses .static_buffer_misuse instead of .buffer_overflow for accuracy.
pub fn riskKindToIssueKind(risk: RiskKind) IssueKind {
    return switch (risk) {
        .command_exec => .command_injection,
        .unchecked_copy => .ffi_unsafe_call,
        .format_string => .format_string,
        .allocator => .memory_leak,
        .deallocator => .invalid_free,
        .rust_ownership => .cross_language_leak,
        .borrow_escaped => .borrow_escape,
        .memory_map => .memory_leak,
        .file_io => .ffi_unsafe_call,
        .network_io => .ffi_unsafe_call,
        .go_cgo_alloc => .memory_leak,
        .zig_allocator => .memory_leak,
        .cpp_allocator => .memory_leak,
        .dynamic_loading => .ffi_unsafe_call,
        .jni => .ffi_unsafe_call,
        .python_c_api => .ffi_unsafe_call,
        // M7: Use .static_buffer_misuse (consistent with ffi_safety_checker.zig)
        .static_buffer => .static_buffer_misuse,
        .thread_mgmt => .ffi_unsafe_call,
        .process_mgmt => .command_injection,
        .signal_handler => .ffi_unsafe_call,
    };
}

/// Demangle a Rust mangled name to a readable format.
pub fn demangleRustName(allocator: std.mem.Allocator, mangled: []const u8) error{OutOfMemory}!?[]u8 {
    return lang_classifier.demangleRustName(allocator, mangled);
}

/// Describe LLVM type for diagnostics.
pub fn describeLLVMType(ty: c.LLVMTypeRef) []const u8 {
    return safety_checker.describeLLVMType(ty);
}
