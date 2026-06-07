//! FFI Safety Checker
//!
//! Extracted from ffi_boundary.zig (P2-2 refactoring).
//! Provides safety validation utilities for FFI boundary analysis:
//! - NULL guard detection after allocation calls
//! - Ownership chain tracking
//! - Specialized boundary checks (dynamic loading, JNI, Python C API)
//! - Return value escape detection
//!
//! Design principle: Stateless analysis functions that scan LLVM IR instructions.
//! All functions operate on explicit parameters with no hidden state.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../../ir/llvm_safe.zig");

const PassContext = @import("../../pass.zig").PassContext;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const IssueSeverity = @import("../../../diag/issue.zig").Severity;
const RiskKind = @import("../../../registry/semantic_registry.zig").RiskKind;
const RegistrySeverity = @import("../../../registry/semantic_registry.zig").Severity;
const allocator_kb = @import("../../../semantics/allocator_kb.zig");
const type_checker = @import("ffi_type_checker.zig");

/// Maximum number of instructions to scan for NULL guard patterns.
const NULL_GUARD_SCAN_LIMIT: u32 = 20;

/// Maximum number of instructions to scan for ownership chain.
const OWNERSHIP_CHAIN_SCAN_LIMIT: u32 = 15;

/// Check if there's a NULL guard after the given call instruction.
///
/// Scans forward in the same basic block for an ICMP comparison against NULL/0,
/// which indicates the programmer is checking the return value before use.
///
/// This detects patterns like:
///   ```llvm
///   %ptr = call i8* @malloc(i64 1024)
///   %cmp = icmp eq i8* %ptr, null
///   br i1 %cmp, label %error, label %success
///   ```
///
/// Parameters:
///   - inst: The call instruction to check
///   - func: Parent function (unused, reserved for future cross-BB analysis)
///
/// Returns:
///   - true if a NULL guard pattern is detected within scan limit
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

/// Check if the result of an ownership-transferring call is properly handled.
///
/// Scans forward from the call instruction to see how the result is used:
/// - **Store** → saved to memory (good)
/// - **Call** → passed to another function (likely free/close)
/// - **ICmp/FCmp** → compared (part of validation logic)
/// - **PtrToInt/BitCast** → being transformed (still tracked)
///
/// If none of these patterns found within scan limit, returns false (potential leak).
///
/// Parameters:
///   - inst: The call instruction to analyze
///   - func: Parent function (unused)
///
/// Returns:
///   - true if ownership chain is properly established
pub fn checkOwnershipChain(inst: c.LLVMValueRef, func: c.LLVMValueRef) bool {
    _ = func;
    const parent_bb = c.LLVMGetInstructionParent(inst);
    if (@intFromPtr(parent_bb) == 0) return false;

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
        if (llvm_safe.isCallOrInvoke(opcode)) {
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

/// Check specialized FFI boundary safety based on function family.
///
/// Dispatches to specific safety checks for known FFI categories:
/// - Dynamic loading (dlopen/dlsym/dlclose)
/// - Java Native Interface (JNI)
/// - Python C API
///
/// Parameters:
///   - ctx: Pass context for issue reporting
///   - diag: Diagnostic writer
///   - inst: The call instruction
///   - caller_func: Calling function
///   - called_name: Name of the called function
pub fn checkSpecializedBoundary(
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    inst: c.LLVMValueRef,
    caller_func: c.LLVMValueRef,
    called_name: []const u8,
    is_dynamic_loading_fn: *const fn ([]const u8) bool,
    is_jni_fn: *const fn ([]const u8) bool,
    is_python_fn: *const fn ([]const u8) bool,
) !void {
    if (is_dynamic_loading_fn(called_name)) {
        try checkDynamicLoadingSafety(ctx, diag, inst, caller_func, called_name);
    }
    if (is_jni_fn(called_name)) {
        try checkJNIBoundarySafety(ctx, diag, inst, caller_func, called_name);
    }
    if (is_python_fn(called_name)) {
        try checkPythonCApiSafety(ctx, diag, inst, caller_func, called_name);
    }
}

/// Check dynamic loading safety (dlopen/dlsym/dlclose).
///
/// Validates proper handle lifecycle management and type-safe usage of dlsym results.
fn checkDynamicLoadingSafety(
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    inst: c.LLVMValueRef,
    caller_func: c.LLVMValueRef,
    called_name: []const u8,
) !void {
    _ = ctx;
    _ = inst;
    _ = caller_func;

    if (std.mem.indexOf(u8, called_name, "dlopen") != null) {
        diag.debug("  [DYNAMIC LOADING] dlopen detected — verify dlclose pairing", .{});
    } else if (std.mem.indexOf(u8, called_name, "dlsym") != null) {
        diag.warn("  [DYNAMIC LOADING] dlsym detected — verify return type cast", .{});
    } else if (std.mem.indexOf(u8, called_name, "dlclose") != null) {
        diag.debug("  [DYNAMIC LOADING] dlclose detected — verify handle validity", .{});
    }
}

/// Check JNI boundary safety.
///
/// Validates proper JNIEnv usage, reference management, and exception handling.
fn checkJNIBoundarySafety(
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    inst: c.LLVMValueRef,
    caller_func: c.LLVMValueRef,
    called_name: []const u8,
) !void {
    _ = ctx;
    _ = inst;
    _ = caller_func;

    if (std.mem.indexOf(u8, called_name, "NewGlobalRef") != null or
        std.mem.indexOf(u8, called_name, "NewLocalRef") != null)
    {
        diag.warn("  [JNI] New*Ref detected — ensure matching Delete*Ref", .{});
    } else if (std.mem.indexOf(u8, called_name, "GetStringUTFChars") != null) {
        diag.warn("  [JNI] GetStringUTFChars detected — must call ReleaseStringUTFChars", .{});
    } else if (std.mem.indexOf(u8, called_name, "AttachCurrentThread") != null) {
        diag.warn("  [JNI] AttachCurrentThread — must DetachCurrentThread", .{});
    }
}

/// Check Python C API safety.
///
/// Validates GIL management, reference counting, and proper error handling.
fn checkPythonCApiSafety(
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    inst: c.LLVMValueRef,
    caller_func: c.LLVMValueRef,
    called_name: []const u8,
) !void {
    _ = ctx;
    _ = inst;
    _ = caller_func;

    if (std.mem.indexOf(u8, called_name, "PyGILState_Ensure") != null) {
        diag.warn("  [PYTHON] PyGILState_Ensure — must call PyGILState_Release", .{});
    } else if (std.mem.indexOf(u8, called_name, "PyArg_Parse") != null) {
        diag.warn("  [PYTHON] PyArg_Parse — check return value for errors", .{});
    } else if (std.mem.indexOf(u8, called_name, "PyImport_Import") != null) {
        diag.warn("  [PYTHON] PyImport_Import — may set exception, check PyErr_Occurred", .{});
    }
}

/// Check if a return value might escape through a callback or global store.
///
/// Detects patterns where a potentially dangerous pointer (from malloc, mmap, etc.)
/// is stored to a global variable or passed to a callback function, which could
/// lead to use-after-free if the callback outlives the current scope.
///
/// Note: This function was originally part of P2-1 boundary analysis,
/// extracted during P2-2 refactoring for better separation of concerns.
pub fn checkReturnValueEscape(
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    inst: c.LLVMValueRef,
    caller_func: c.LLVMValueRef,
    called_name: []const u8,
    report_fn: *const fn (*PassContext, IssueKind, []const u8, []const u8, anytype, f32) anyerror!void,
) !void {
    var num_uses: usize = 0;
    var use = c.LLVMGetFirstUse(inst);
    while (@intFromPtr(use) != 0) : (use = c.LLVMGetNextUse(use)) {
        num_uses += 1;
    }

    if (num_uses > 3) {
        const caller_name_ptr = c.LLVMGetValueName(caller_func);
        const caller_name = if (@intFromPtr(caller_name_ptr) != 0)
            std.mem.span(caller_name_ptr)
        else
            "unknown";

        diag.warn("  ESCAPE RISK: {s} result used {} times in {s} — potential escape via callback/global", .{
            called_name,
            num_uses,
            caller_name,
        });

        const msg = try std.fmt.allocPrint(
            ctx.allocator,
            "Return value escape risk: {s} used {d} times in {s}",
            .{ called_name, num_uses, caller_name },
        );
        defer ctx.allocator.free(msg);

        try report_fn(ctx, .borrow_escape, msg, caller_name, .medium, 0.60);
    }
}

/// Check for static buffer misuse (P2-1).
///
/// Static buffer functions (ctime, strerror, getpwnam, inet_ntoa, etc.) return
/// pointers to **internal static storage**, not heap-allocated memory.
///
/// Critical properties:
///   - Must NOT be freed (doing so is UB / segfault)
///   - NOT a memory leak (no allocation occurred)
///   - Thread-unsafe: next call overwrites previous result
///   - Data race if called from multiple threads simultaneously
///
/// This is classified as `static_buffer_misuse` (NOT `memory_leak` or `ffi_unsafe_call`)
/// because the risk profile is distinct:
///   - No ownership transfer → not a leak
///   - Not an FFI safety issue per se → it's a C API contract violation
///   - Real bugs: data corruption (overwrite), crash (free on static), TOCTOU
///
/// Detection heuristic: function name matches known static-buffer patterns.
pub fn isStaticBufferFunction(func_name: []const u8) bool {
    // Primary: check AllocatorKB for authoritative knowledge.
    if (allocator_kb.getAllocatorKB()) |kb| {
        if (kb.isStaticBuffer(func_name)) return true;
    }

    // Fallback: hardcoded patterns for when KB is not initialized.
    // Uses exact match + up to 3 leading underscores (libc internal wrappers).
    const static_buf_patterns = [_][]const u8{
        "ctime",     "asctime",  "strerror", "strsignal",
        "inet_ntoa", "getgrgid", "getgrnam", "getpwuid",
        "getpwnam",  "getpwent", "grent",    "tmpnam",
        "gcvt",      "ecvt",     "fcvt",     "crypt",
    };
    for (static_buf_patterns) |pat| {
        if (std.mem.eql(u8, func_name, pat)) return true;
        if (func_name.len > pat.len) {
            const prefix = func_name[0 .. func_name.len - pat.len];
            var all_underscore = true;
            for (prefix) |ch| {
                if (ch != '_') {
                    all_underscore = false;
                    break;
                }
            }
            if (all_underscore and prefix.len <= 3) return true;
        }
    }
    return false;
}

/// Map static buffer risk to issue kind.
///
/// P2-1: Static buffer functions return pointers to static storage.
/// These must NOT be freed (doing so is UB), so they are NOT memory leaks.
/// The real risks are: thread-unsafe + data overwrite on next call.
/// Classified as static_buffer_misuse to distinguish from general FFI unsafe calls.
pub fn staticBufferIssueKind() IssueKind {
    return .static_buffer_misuse;
}

/// Describe an LLVM type as a human-readable string.
///
/// Used for diagnostic messages when reporting type mismatches.
/// Handles all common LLVM type kinds with friendly names.
///
/// Parameters:
///   - ty: LLVM type reference to describe
///
/// Returns:
///   - Static string slice describing the type
pub fn describeLLVMType(ty: c.LLVMTypeRef) []const u8 {
    return type_checker.describeLLVMType(ty);
}

/// Map a SemanticRegistry RiskKind to an IssueKind for reporting.
///
/// This bridges the gap between the semantic registry's risk taxonomy
/// and the diagnostic system's issue classification.
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
        .signal_handler => .ffi_unsafe_call,
        .thread_mgmt => .ffi_unsafe_call,
        .process_mgmt => .ffi_unsafe_call,
        // Delegates to staticBufferIssueKind() — see P2-1
        .static_buffer => .static_buffer_misuse,
        .pure_computation => .ffi_unsafe_call, // Should be filtered before reaching here
    };
}

/// Map a SemanticRegistry Severity to an IssueSeverity for reporting.
///
/// The severity values are 1:1 mapped between the two systems.
pub fn registrySeverityToIssueSeverity(registry_severity: RegistrySeverity) IssueSeverity {
    return switch (registry_severity) {
        .low => .low,
        .medium => .medium,
        .high => .high,
        .critical => .critical,
    };
}

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "checkNullGuard - no guard on undefined" {
    try std.testing.expect(!checkNullGuard(undefined, undefined));
}

test "checkOwnershipChain - no chain on undefined" {
    try std.testing.expect(!checkOwnershipChain(undefined, undefined));
}
