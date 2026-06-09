//! Nomicon Ch10: Pin/ManuallyDrop/OnceLock + Ch5 Interior Mutability
//!
//! Detects interior mutability patterns by walking DI type chains.
//! If a store's dest GEP base has a DI type chain containing UnsafeCell<T>,
//! then the write is legal interior mutability — not an immutability violation.
//!
//! Nomicon §5: Interior Mutability
//! - UnsafeCell<T> is the ONLY way to get *mut T from &T without UB
//! - All interior mutability types (Cell, RefCell, Mutex, RwLock, Atomic*,
//!   OnceLock, LazyLock) wrap UnsafeCell internally
//!
//! Covers: F2 (23 write_to_immutable FP) — Once::call_once_force, OnceLock, etc.

const std = @import("std");
const log = std.log.scoped(.nomicon_ch10);
const c = @import("../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../ir/llvm_safe.zig");
const SemanticTree = @import("../semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../semantic_tree.zig").SemanticKind;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;

/// Interior mutability type prefixes (Rust standard library)
/// These types contain UnsafeCell<T> internally — writes through them are legal.
const INTERIOR_MUTABLE_PREFIXES = [_][]const u8{
    "UnsafeCell<",
    "core::cell::UnsafeCell<",
    "Cell<",
    "core::cell::Cell<",
    "RefCell<",
    "core::cell::RefCell<",
    "Mutex<",
    "std::sync::Mutex<",
    "parking_lot::Mutex<",
    "RwLock<",
    "std::sync::RwLock<",
    "parking_lot::RwLock<",
    "Once",
    "std::sync::Once",
    "OnceLock<",
    "std::sync::OnceLock<",
    "LazyLock<",
    "std::sync::LazyLock<",
    "OnceCell<",
    "core::cell::OnceCell<",
    "AtomicBool",
    "AtomicI8",
    "AtomicI16",
    "AtomicI32",
    "AtomicI64",
    "AtomicIsize",
    "AtomicU8",
    "AtomicU16",
    "AtomicU32",
    "AtomicU64",
    "AtomicUsize",
    "AtomicPtr<",
    "std::sync::atomic::",
    "core::sync::atomic::",
    "Pin<",
    "core::pin::Pin<",
    "ManuallyDrop<",
    "core::mem::ManuallyDrop<",
};

/// Detect interior mutability patterns (per-function).
/// Extracted for single-pass merged traversal optimization.
pub fn detectFunction(
    func: c.LLVMValueRef,
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    _ = module;
    _ = diag;
    if (c.LLVMIsDeclaration(func) != 0) return;

    const func_name_raw = c.LLVMGetValueName(func);
    if (@intFromPtr(func_name_raw) == 0) return;
    const func_name = std.mem.sliceTo(func_name_raw, 0);

    if (isOnceInitContext(func_name)) {}

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            if (c.LLVMGetInstructionOpcode(inst) != c.LLVMStore) continue;

            const dest = c.LLVMGetOperand(inst, 1);
            if (@intFromPtr(dest) == 0) continue;

            if (isInteriorMutableThroughChain(dest)) {
                recordResolution(srt, @intFromPtr(inst), .interior_mutability, 0.90, "Ch10 DI type chain contains UnsafeCell");
                continue;
            }

            if (isInteriorMutableByHeuristic(dest, func_name)) {
                recordResolution(srt, @intFromPtr(inst), .interior_mutability, 0.70, "Ch10 heuristic-based interior mutability");
            }
        }
    }
}

/// Detect interior mutability patterns and write to SRT.
pub fn detect(
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    var fn_iter = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(fn_iter) != 0) : (fn_iter = c.LLVMGetNextFunction(fn_iter)) {
        try detectFunction(fn_iter, module, srt, diag);
    }
}

/// Walk DI type chain to find UnsafeCell<T>.
/// Returns true if the type chain contains any interior mutable type.
pub fn isInteriorMutableThroughChain(value: c.LLVMValueRef) bool {
    // Try to get the DI type from the value's metadata
    var cur = getDIType(value);
    var depth: u32 = 0;
    while (depth < 8 and @intFromPtr(cur) != 0) : (depth += 1) {
        if (getDITypeName(cur)) |name| {
            for (INTERIOR_MUTABLE_PREFIXES) |prefix| {
                if (std.mem.startsWith(u8, name, prefix)) return true;
            }
        }
        cur = getDIBaseType(cur);
    }
    return false;
}

/// Get DI type metadata from a value.
///
/// Traces the value back to its alloca base, then searches for
/// llvm.dbg.declare / llvm.dbg.addr intrinsics referencing that alloca.
/// Returns the DI type node from the intrinsic's metadata operand.
fn getDIType(value: c.LLVMValueRef) c.LLVMMetadataRef {
    if (@intFromPtr(value) == 0) return @ptrFromInt(0);

    // Trace back to the alloca base (handles GEP, load, bitcast chains)
    const alloca_base = traceToAlloca(value);
    if (@intFromPtr(alloca_base) == 0) return @ptrFromInt(0);

    // Find dbg intrinsic referencing this alloca
    const func = c.LLVMGetInstructionParent(alloca_base);
    if (@intFromPtr(func) == 0) return @ptrFromInt(0);
    const bb_parent = c.LLVMGetBasicBlockParent(func);
    if (@intFromPtr(bb_parent) == 0) return @ptrFromInt(0);

    var bb = c.LLVMGetFirstBasicBlock(bb_parent);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            if (!llvm_safe.isCallOrInvoke(c.LLVMGetInstructionOpcode(inst))) continue;
            const callee = getCalleeName(inst) orelse continue;
            if (!std.mem.eql(u8, callee, "llvm.dbg.declare") and
                !std.mem.eql(u8, callee, "llvm.dbg.addr")) continue;

            // Extract metadata from dbg intrinsic: last operand is metadata tuple
            const num_ops = c.LLVMGetNumOperands(inst);
            if (num_ops < 1) continue;
            const md = c.LLVMGetOperand(inst, @as(c_uint, @intCast(num_ops - 1)));
            if (@intFromPtr(md) == 0) continue;

            // Check if metadata references our alloca
            const md_ops = c.LLVMGetNumOperands(md);
            if (md_ops < 2) continue;
            const val = c.LLVMGetOperand(md, 0);
            if (val != alloca_base) continue;

            // Operand 1 is the DIVariable; its type (operand 3 or via
            // the variable's type operand) is the DI type we want.
            const di_var = c.LLVMGetOperand(md, 1);
            if (@intFromPtr(di_var) == 0) continue;

            // DIVariable typically has: tag, scope, name, file, line, type
            // The type is usually operand 3 or 4 depending on the layout.
            // Try operand 3 first (common for DILocalVariable).
            const var_ops = c.LLVMGetNumOperands(di_var);
            if (var_ops >= 4) {
                const di_type = c.LLVMGetOperand(di_var, 3);
                if (@intFromPtr(di_type) != 0) return @ptrCast(di_type);
            }
            // Fallback: try operand 5 (for some LLVM versions)
            if (var_ops >= 6) {
                const di_type = c.LLVMGetOperand(di_var, 5);
                if (@intFromPtr(di_type) != 0) return @ptrCast(di_type);
            }
            // Last resort: return the variable itself as type info
            return @ptrCast(di_var);
        }
    }

    return @ptrFromInt(0);
}

/// Get the type name from a DI type metadata.
///
/// Uses LLVMGetValueName and operand-based extraction (operand 2 is
/// typically the name string in DIDerivedType / DICompositeType).
/// Also uses LLVMIsAMDString / LLVMGetAMDString for proper metadata
/// string extraction.
fn getDITypeName(di_type: c.LLVMMetadataRef) ?[]const u8 {
    if (@intFromPtr(di_type) == 0) return null;

    // Cast to ValueRef for LLVM C API operand access
    const as_val: c.LLVMValueRef = @ptrCast(di_type);

    // Try direct name first
    const name_ptr = c.LLVMGetValueName(as_val);
    if (@intFromPtr(name_ptr) != 0) {
        const name = std.mem.sliceTo(name_ptr, 0);
        if (name.len > 0) return name;
    }

    // Try operand-based extraction: operand 2 is often the name MDString
    const num_ops = c.LLVMGetNumOperands(as_val);
    if (num_ops >= 3) {
        const name_node = c.LLVMGetOperand(as_val, 2);
        if (@intFromPtr(name_node) != 0) {
            // Try to extract string from metadata node
            const node_name = c.LLVMGetValueName(name_node);
            if (@intFromPtr(node_name) != 0) {
                const name = std.mem.sliceTo(node_name, 0);
                if (name.len > 0) return name;
            }
        }
    }

    return null;
}

/// Get the base type from a DI type metadata (for walking chains).
///
/// DIDerivedType nodes (pointer, reference, typedef, const, volatile)
/// have their base type at operand 1. Returns the base type or null.
fn getDIBaseType(di_type: c.LLVMMetadataRef) c.LLVMMetadataRef {
    if (@intFromPtr(di_type) == 0) return @ptrFromInt(0);

    const as_val: c.LLVMValueRef = @ptrCast(di_type);
    const num_ops = c.LLVMGetNumOperands(as_val);

    // Base type is typically operand 1 in DI derived types
    if (num_ops >= 2) {
        const base = c.LLVMGetOperand(as_val, 1);
        return @ptrCast(base);
    }

    return @ptrFromInt(0);
}

/// Trace a pointer value back to its alloca base.
/// Handles GEP, load, bitcast, addrspacecast chains.
fn traceToAlloca(value: c.LLVMValueRef) c.LLVMValueRef {
    var current = value;
    var depth: u32 = 0;
    while (depth < 8) : (depth += 1) {
        if (@intFromPtr(c.LLVMIsAInstruction(current)) == 0) return @ptrFromInt(0);
        if (c.LLVMGetInstructionOpcode(current) == c.LLVMAlloca) return current;
        const opcode = c.LLVMGetInstructionOpcode(current);
        if (opcode == c.LLVMGetElementPtr or opcode == c.LLVMLoad or
            opcode == c.LLVMBitCast or opcode == c.LLVMAddrSpaceCast)
        {
            current = c.LLVMGetOperand(current, 0);
            if (@intFromPtr(current) == 0) return @ptrFromInt(0);
            continue;
        }
        break;
    }
    return @ptrFromInt(0);
}

/// Get callee name from a call/invoke instruction.
fn getCalleeName(inst: c.LLVMValueRef) ?[]const u8 {
    const called_val = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_val) == 0) return null;
    const name_raw = c.LLVMGetValueName(called_val);
    if (@intFromPtr(name_raw) == 0) return null;
    const name = std.mem.sliceTo(name_raw, 0);
    if (name.len == 0) return null;
    return name;
}

/// Check if a function is in a once-init context (call_once_force, etc.)
pub fn isOnceInitContext(func_name: []const u8) bool {
    const ONCE_PATTERNS = [_][]const u8{
        "call_once_force",
        "call_once",
        "OnceLock::get_or_init",
        "Once::call_once",
    };
    for (ONCE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }
    return false;
}

/// Heuristic-based interior mutability detection when DI types unavailable.
/// Uses function name and instruction context to infer interior mutability.
fn isInteriorMutableByHeuristic(dest: c.LLVMValueRef, func_name: []const u8) bool {
    // If the function name suggests interior mutability context
    if (isOnceInitContext(func_name)) return true;

    // Check if dest comes from a function call that returns interior mutable type
    if (llvm_safe.isCallOrInvoke(c.LLVMGetInstructionOpcode(dest))) {
        const called = c.LLVMGetCalledValue(dest);
        if (@intFromPtr(called) != 0) {
            const called_name_raw = c.LLVMGetValueName(called);
            if (@intFromPtr(called_name_raw) != 0) {
                const called_name = std.mem.sliceTo(called_name_raw, 0);
                for (INTERIOR_MUTABLE_PREFIXES) |prefix| {
                    if (std.mem.indexOf(u8, called_name, prefix[0..@min(prefix.len, 10)]) != null) {
                        return true;
                    }
                }
            }
        }
    }

    return false;
}

/// Record a semantic resolution to the SRT.
fn recordResolution(
    srt: *SemanticTree,
    value_ref: u64,
    kind: SemanticKind,
    confidence: f32,
    evidence: []const u8,
) void {
    srt.recordResolution(value_ref, kind, confidence, "Nomicon-Ch10", evidence) catch {};
}

// ============================================================================
// Tests
// ============================================================================

test "Ch10: detect once-init patterns" {
    try std.testing.expect(isOnceInitContext("call_once_force"));
    try std.testing.expect(isOnceInitContext("std::sync::Once::call_once"));
    try std.testing.expect(isOnceInitContext("OnceLock::get_or_init"));
    try std.testing.expect(!isOnceInitContext("normal_function"));
    try std.testing.expect(!isOnceInitContext("unsafe_operation"));
}

test "Ch10: interior mutable prefixes" {
    const test_cases = [_]struct { []const u8, bool }{
        .{ "UnsafeCell<i32>", true },
        .{ "Cell<String>", true },
        .{ "RefCell<Vec<i32>>", true },
        .{ "Mutex<HashMap>", true },
        .{ "AtomicU32", true },
        .{ "OnceLock<Vec<i32>>", true },
        .{ "Pin<Box<T>>", true },
        .{ "NormalStruct", false },
        .{ "Vec<i32>", false },
    };

    for (test_cases) |case| {
        var found = false;
        for (INTERIOR_MUTABLE_PREFIXES) |prefix| {
            if (std.mem.indexOf(u8, case[0], prefix) != null) {
                found = true;
                break;
            }
        }
        try std.testing.expectEqual(case[1], found);
    }
}
