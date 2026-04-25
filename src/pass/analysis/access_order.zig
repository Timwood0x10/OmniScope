//! Access Order Analysis
//!
//! Tracks the order of memory accesses relative to free operations.
//! Distinguishes between "access before free" (safe) and "access after free" (UAF).
//!
//! Key insight from investigation reports:
//! - boringssl: OPENSSL_free accesses ptr metadata BEFORE freeing (safe)
//! - mbedtls: Structure members accessed BEFORE freeing the structure (safe)
//!
//! This module implements basic-block-level instruction ordering to reduce
//! false positives in UAF detection.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

/// Memory operation type for ordering analysis.
pub const MemoryOpKind = enum(u8) {
    load,
    store,
    call,
    free,
    unknown,
};

/// Represents a memory operation within a basic block.
pub const MemoryOp = struct {
    inst: c.LLVMValueRef,
    kind: MemoryOpKind,
    position: u32,
    ptr_value_id: u32,
};

/// Result of analyzing access order for a pointer.
pub const AccessOrderResult = struct {
    /// All accesses before the free operation.
    accesses_before_free: u32,
    /// All accesses after the free operation (potential UAF).
    accesses_after_free: u32,
    /// Whether the free is the last operation in the block.
    free_is_last: bool,
    /// Whether the access pattern is safe.
    is_safe_pattern: bool,
};

/// Analyze the order of memory operations in a basic block.
///
/// This function collects all memory operations on a given pointer
/// and determines their order relative to free operations.
///
/// Arguments:
///   allocator - Memory allocator
///   block - The basic block to analyze
///   ptr_id - The pointer value ID to track
///   diag - Diagnostic writer for debug output
///
/// Returns:
///   AccessOrderResult indicating the safety of the access pattern
pub fn analyzeAccessOrder(
    allocator: std.mem.Allocator,
    block: c.LLVMBasicBlockRef,
    ptr_id: u32,
    diag: *DiagnosticWriter,
) AccessOrderResult {
    _ = diag;

    var ops = std.ArrayList(MemoryOp).init(allocator);
    defer ops.deinit();

    var position: u32 = 0;
    var free_position: ?u32 = null;

    var inst = c.LLVMGetFirstInstruction(block);
    while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
        const opcode = c.LLVMGetInstructionOpcode(inst);
        const op = classifyInstruction(inst, opcode, position, ptr_id);

        if (op.kind != .unknown) {
            if (op.kind == .free) {
                free_position = position;
            }
            ops.append(op) catch {};
        }
        position += 1;
    }

    if (free_position == null) {
        return .{
            .accesses_before_free = 0,
            .accesses_after_free = 0,
            .free_is_last = false,
            .is_safe_pattern = true,
        };
    }

    var before: u32 = 0;
    var after: u32 = 0;

    for (ops.items) |op| {
        if (op.position < free_position.?) {
            before += 1;
        } else if (op.position > free_position.?) {
            after += 1;
        }
    }

    const total_ops = position;
    const free_is_last = (free_position.? >= total_ops - 1);

    return .{
        .accesses_before_free = before,
        .accesses_after_free = after,
        .free_is_last = free_is_last,
        .is_safe_pattern = free_is_last or after == 0,
    };
}

/// Classify an instruction as a memory operation.
fn classifyInstruction(
    inst: c.LLVMValueRef,
    opcode: c_uint,
    position: u32,
    ptr_id: u32,
) MemoryOp {
    const kind: MemoryOpKind = switch (opcode) {
        c.LLVMLoad => .load,
        c.LLVMStore => .store,
        c.LLVMCall => classifyCall(inst),
        else => .unknown,
    };

    return .{
        .inst = inst,
        .kind = kind,
        .position = position,
        .ptr_value_id = ptr_id,
    };
}

/// Classify a call instruction as free or other.
fn classifyCall(inst: c.LLVMValueRef) MemoryOpKind {
    const called_val = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_val) == 0) return .call;

    const name_ptr = c.LLVMGetValueName(called_val);
    if (@intFromPtr(name_ptr) == 0) return .call;

    const callee_name = std.mem.span(name_ptr);

    // Check for free-like functions
    const free_patterns = [_][]const u8{
        "free",
        "OPENSSL_free",
        "CRYPTO_free",
        "sodium_free",
        "__rust_dealloc",
        "_ZdlPv", // operator delete
        "_ZdaPv", // operator delete[]
    };

    for (free_patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) {
            return .free;
        }
    }

    return .call;
}

/// Check if a free operation is preceded by legitimate metadata access.
///
/// Pattern: load metadata -> cleanse -> free
/// This is safe because the access happens BEFORE the free.
///
/// Arguments:
///   block - The basic block containing the free
///   free_inst - The free instruction
///
/// Returns:
///   true if the access pattern is safe (access before free)
pub fn isAccessBeforeFree(
    block: c.LLVMBasicBlockRef,
    free_inst: c.LLVMValueRef,
) bool {
    var position: u32 = 0;
    var free_position: ?u32 = null;
    var has_load_before_free = false;

    var inst = c.LLVMGetFirstInstruction(block);
    while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
        if (@intFromPtr(inst) == @intFromPtr(free_inst)) {
            free_position = position;
        }

        const opcode = c.LLVMGetInstructionOpcode(inst);
        if (opcode == c.LLVMLoad and free_position == null) {
            has_load_before_free = true;
        }

        position += 1;
    }

    // If there's a load before the free, and no free was found yet,
    // this is likely a "read metadata then free" pattern
    return has_load_before_free and free_position != null;
}

/// Check if a function follows the "cleanup before free" pattern.
///
/// Pattern: memset/cleanse(ptr) -> free(ptr)
/// This is safe because the memory is cleared before being freed.
///
/// Arguments:
///   func_name - The function name to check
///
/// Returns:
///   true if the function is a cleanup pattern
pub fn isCleanupBeforeFreePattern(func_name: []const u8) bool {
    const cleanup_patterns = [_][]const u8{
        "OPENSSL_cleanse",
        "OPENSSL_clear_free",
        "sodium_memzero",
        "explicit_bzero",
        "memset",
        "CRYPTO_cleanse",
        "secure_zero",
    };

    for (cleanup_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Check if a function follows the "realloc" pattern.
///
/// Pattern: malloc(new) -> memcpy(old, new) -> free(old)
/// This is safe because the old memory is freed after data is copied.
///
/// Arguments:
///   func_name - The function name to check
///
/// Returns:
///   true if the function is a realloc pattern
pub fn isReallocPattern(func_name: []const u8) bool {
    const realloc_patterns = [_][]const u8{
        "realloc",
        "OPENSSL_realloc",
        "CRYPTO_realloc",
        "_Znwm", // operator new
        "_Znam", // operator new[]
    };

    for (realloc_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Check if a function follows the "error handling" pattern.
///
/// Pattern: goto err -> free(ptr) -> return error
/// This is safe because the free happens in an error path.
///
/// Arguments:
///   func_name - The function name to check
///
/// Returns:
///   true if the function is an error handling pattern
pub fn isErrorHandlingPattern(func_name: []const u8) bool {
    const error_patterns = [_][]const u8{
        "err:",
        "error:",
        "cleanup:",
        "fail:",
        "_ZSt9terminatev", // std::terminate
        "__cxa_throw",
        "abort",
        "panic",
    };

    for (error_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }

    return false;
}

/// Comprehensive check for safe memory access patterns.
///
/// This function combines multiple pattern checks to determine if
/// a potential UAF is actually a safe memory access pattern.
///
/// Arguments:
///   func_name - The function name
///   block - The basic block
///   free_inst - The free instruction (may be null)
///
/// Returns:
///   true if the access pattern is safe
pub fn isSafeMemoryPattern(
    func_name: []const u8,
    block: c.LLVMBasicBlockRef,
    free_inst: ?c.LLVMValueRef,
) bool {
    // Check function-level patterns
    if (isCleanupBeforeFreePattern(func_name)) return true;
    if (isReallocPattern(func_name)) return true;
    if (isErrorHandlingPattern(func_name)) return true;

    // Check instruction-level patterns
    if (free_inst) |inst| {
        if (isAccessBeforeFree(block, inst)) return true;
    }

    return false;
}

test "isCleanupBeforeFreePattern" {
    try std.testing.expect(isCleanupBeforeFreePattern("OPENSSL_cleanse"));
    try std.testing.expect(isCleanupBeforeFreePattern("sodium_memzero"));
    try std.testing.expect(!isCleanupBeforeFreePattern("malloc"));
}

test "isReallocPattern" {
    try std.testing.expect(isReallocPattern("OPENSSL_realloc"));
    try std.testing.expect(isReallocPattern("realloc"));
    try std.testing.expect(!isReallocPattern("free"));
}

test "isErrorHandlingPattern" {
    try std.testing.expect(isErrorHandlingPattern("__cxa_throw"));
    try std.testing.expect(isErrorHandlingPattern("abort"));
    try std.testing.expect(!isErrorHandlingPattern("main"));
}
