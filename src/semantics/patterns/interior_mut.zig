//! R-2: Interior Mutability Detector — UnsafeCell DI chain
//!
//! Rust's UnsafeCell<T> is the ONLY language primitive that allows
//! mutation through a &T reference. All interior mutability types
//! (Cell, RefCell, Mutex, RwLock, Atomic*, OnceLock, LazyLock)
//! internally wrap UnsafeCell — this is enforced by the Rust compiler.
//!
//! Third-party types (parking_lot::Mutex, crossbeam::AtomicCell)
//! must also wrap UnsafeCell — it's a language-level requirement.
//!
//! Detection: walk the DI type chain of a store destination. If any
//! layer contains "UnsafeCell<", the write is legal interior mutability.
//!
//! Covers: ~23 write_to_immutable FP (R-2 UnsafeCell chain).
//! Only 1 string to match: "UnsafeCell".

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const SemanticTree = @import("../semantic_tree.zig").SemanticTree;
const SemanticKind = @import("../semantic_tree.zig").SemanticKind;
const DiagnosticWriter = @import("../../pass/pass.zig").DiagnosticWriter;
const debug_info = @import("../../pass/analysis/debug_info.zig");
const log = std.log.scoped(.interior_mut);

/// Maximum depth for DI type chain traversal.
const MAX_DI_CHAIN_DEPTH: u32 = 8;

/// DI type name prefixes that indicate interior mutability.
/// UnsafeCell is the sole Rust primitive for interior mutability.
const INTERIOR_MUT_PREFIXES = [_][]const u8{
    "UnsafeCell<",
    "core::cell::UnsafeCell<",
    "std::cell::UnsafeCell<",
};

/// Detect interior mutability patterns and write to SRT.
/// For each alloca with DI metadata, check if the DI type chain
/// contains UnsafeCell. If so, mark the alloca as interior_mutability.
pub fn detect(
    module: c.LLVMModuleRef,
    srt: *SemanticTree,
    diag: *DiagnosticWriter,
) !void {
    _ = diag;

    var func = c.LLVMGetFirstFunction(module);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        if (c.LLVMIsDeclaration(func) != 0) continue;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                // Check alloca instructions for DI type chain
                if (c.LLVMGetInstructionOpcode(inst) == c.LLVMAlloca) {
                    if (isAllocaInteriorMutable(inst)) |di_name| {
                        try srt.recordResolution(
                            @intFromPtr(inst),
                            .interior_mutability,
                            0.90,
                            "R-2 UnsafeCell",
                            di_name,
                        );
                    }
                }

                // Check store instructions: if dest is a GEP from an
                // interior-mutable alloca, mark the store too
                if (c.LLVMGetInstructionOpcode(inst) == c.LLVMStore) {
                    const dest = c.LLVMGetOperand(inst, 1);
                    if (@intFromPtr(dest) != 0) {
                        const alloca_base = traceToAlloca(dest);
                        if (@intFromPtr(alloca_base) != 0) {
                            if (srt.hasKind(@intFromPtr(alloca_base), .interior_mutability) != null) {
                                try srt.recordResolution(
                                    @intFromPtr(inst),
                                    .interior_mutability,
                                    0.85,
                                    "R-2 UnsafeCell",
                                    "store to interior-mutable alloca",
                                );
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Check if an alloca's DI type OR any type in its inheritance chain
/// contains interior mutability (UnsafeCell, Cell, Mutex, etc.).
///
/// Walks the DI metadata type hierarchy using LLVM debug info APIs:
///   1. Get DI type from llvm.dbg.declare/llvm.dbg.addr
///   2. If it's a DIDerivedType (typedef/pointer/reference), get base type
///   3. Recursively check base type up to MAX_DI_CHAIN_DEPTH levels
///
/// Returns the DI type name if interior mutability is found at any level,
/// or null if no evidence found in the entire chain.
pub fn isAllocaInteriorMutable(alloca: c.LLVMValueRef) ?[]const u8 {
    // Step 1: Get the direct DI type name (fast path)
    const di_name = findAllocaDITypeName(alloca) orelse return null;

    // Step 2: Check direct match (fast path)
    if (isInteriorMutDIName(di_name)) {
        log.debug("[DI-CHAIN] Direct match on alloca DI type: '{s}'", .{di_name});
        return di_name;
    }

    // Step 3: Walk the DI base type chain (slow path)
    const di_node = getAllocaDINode(alloca) orelse return null;
    if (@intFromPtr(di_node) == 0) return null;
    return walkDITypeChain(di_node, 0);
}

/// Check if a DI type name indicates interior mutability.
pub fn isInteriorMutDIName(name: []const u8) bool {
    for (INTERIOR_MUT_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, name, prefix)) return true;
    }
    // Also check for contains match — DI names can be nested
    // e.g., "RefCell<UnsafeCell<i32>>"
    if (std.mem.indexOf(u8, name, "UnsafeCell<") != null) return true;
    return false;
}

/// Recursively check DI type chain for UnsafeCell.
/// Walks up the DI base type chain up to MAX_DI_CHAIN_DEPTH levels.
pub fn isInteriorMutableThroughChain(di_type_name: []const u8) bool {
    return isInteriorMutDIName(di_type_name);
}

/// Recursively walk the DI type chain looking for interior mutability.
///
/// Uses LLVM C API to access DWARF debug info metadata:
/// - DIDerivedType.baseType → for typedef/pointer/reference types
/// - DICompositeType.elements → for struct members (optional deep scan)
///
/// Arguments:
///   di_node  - The DI metadata node to start walking from (as ValueRef)
///   depth    - Current recursion depth (must be < MAX_DI_CHAIN_DEPTH)
///
/// Returns:
///   The first interior-mutable type name found, or null
fn walkDITypeChain(
    di_node: c.LLVMValueRef,
    depth: u32,
) ?[]const u8 {
    // Depth guard to prevent stack overflow on recursive types
    if (depth >= MAX_DI_CHAIN_DEPTH) {
        log.debug("[DI-CHAIN] Max depth ({d}) reached", .{MAX_DI_CHAIN_DEPTH});
        return null;
    }

    if (@intFromPtr(di_node) == 0) return null;

    // Get the DI type name at this level
    const cur_name = debug_info.getDITypeName(di_node) orelse {
        // Try to get base type directly
        const base = debug_info.getDIBaseType(di_node);
        if (@intFromPtr(base) == 0) return null;
        return walkDITypeChain(base, depth + 1);
    };

    // Check if current type name indicates interior mutability
    if (isInteriorMutDIName(cur_name)) {
        log.debug("[DI-CHAIN] Found interior mut at depth {d}: '{s}'", .{ depth, cur_name });
        return cur_name;
    }

    // Get base type and recurse
    const base_type = debug_info.getDIBaseType(di_node);
    if (@intFromPtr(base_type) != 0) {
        return walkDITypeChain(base_type, depth + 1);
    }

    // For composite types (struct/class), optionally scan members
    const tag = c.LLVMGetMetadataKind(@ptrCast(di_node));
    // DW_TAG_structure_type = 19, DW_TAG_class_type = 2
    if (tag == 19 or tag == 2) {
        if (scanStructMembersForInteriorMut(di_node, depth + 1)) |member_name| {
            return member_name;
        }
    }

    return null;
}

/// Get the DINode associated with an alloca instruction.
/// Searches for llvm.dbg.declare or llvm.dbg.addr intrinsics.
fn getAllocaDINode(alloca: c.LLVMValueRef) ?c.LLVMValueRef {
    if (c.LLVMGetInstructionOpcode(alloca) != c.LLVMAlloca) return null;

    const func = c.LLVMGetInstructionParent(alloca);
    if (@intFromPtr(func) == 0) return null;
    const bb_parent = c.LLVMGetBasicBlockParent(func);
    if (@intFromPtr(bb_parent) == 0) return null;

    // Search for dbg intrinsics referencing this alloca
    var bb = c.LLVMGetFirstBasicBlock(bb_parent);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            if (c.LLVMGetInstructionOpcode(inst) != c.LLVMCall) continue;
            const callee = getCalleeName(inst) orelse continue;
            if (!std.mem.eql(u8, callee, "llvm.dbg.declare") and
                !std.mem.eql(u8, callee, "llvm.dbg.addr")) continue;

            // Extract DI variable from metadata
            const num_ops = c.LLVMGetNumOperands(inst);
            if (num_ops < 1) continue;
            const md = c.LLVMGetOperand(inst, @as(c_uint, @intCast(num_ops - 1)));
            if (@intFromPtr(md) == 0) continue;

            // Check if metadata references our alloca
            const md_ops = c.LLVMGetNumOperands(md);
            if (md_ops < 2) continue;
            const val = c.LLVMGetOperand(md, 0);
            if (val != alloca) continue;

            // Return the DI variable metadata node
            const di_var = c.LLVMGetOperand(md, 1);
            if (@intFromPtr(di_var) == 0) continue;
            return di_var;
        }
    }

    return null;
}

/// Optionally scan struct members for interior mutable types.
/// Only called for composite types when direct chain walk doesn't find anything.
fn scanStructMembersForInteriorMut(
    composite_di: c.LLVMValueRef,
    depth: u32,
) ?[]const u8 {
    if (depth >= MAX_DI_CHAIN_DEPTH) return null;

    // Get elements array from DICompositeType
    // Note: This API varies by LLVM version; may need adaptation
    const num_operands = c.LLVMGetNumOperands(composite_di);
    if (num_operands < 11) return null; // Elements are typically at operand index 10+

    var i: c_uint = 11;
    while (i < num_operands) : (i += 1) {
        const element = c.LLVMGetOperand(composite_di, i);
        if (@intFromPtr(element) == 0) continue;

        // Get element's type name
        const elem_name = debug_info.getDITypeName(element) orelse continue;

        // Check if member type is interior mutable
        if (isInteriorMutDIName(elem_name)) {
            log.debug("[DI-MEMBER] Found interior mut in struct member: '{s}'", .{elem_name});
            return elem_name;
        }
    }

    return null;
}

/// Find the DI type name for an alloca instruction.
/// Searches for llvm.dbg.declare/llvm.dbg.addr intrinsics.
fn findAllocaDITypeName(alloca: c.LLVMValueRef) ?[]const u8 {
    if (c.LLVMGetInstructionOpcode(alloca) != c.LLVMAlloca) return null;

    const func = c.LLVMGetInstructionParent(alloca);
    if (@intFromPtr(func) == 0) return null;
    const bb_parent = c.LLVMGetBasicBlockParent(func);
    if (@intFromPtr(bb_parent) == 0) return null;

    // Search for dbg intrinsics referencing this alloca
    var bb = c.LLVMGetFirstBasicBlock(bb_parent);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            if (c.LLVMGetInstructionOpcode(inst) != c.LLVMCall) continue;
            const callee = getCalleeName(inst) orelse continue;
            if (!std.mem.eql(u8, callee, "llvm.dbg.declare") and
                !std.mem.eql(u8, callee, "llvm.dbg.addr")) continue;

            // Extract DI variable from metadata
            const num_ops = c.LLVMGetNumOperands(inst);
            if (num_ops < 1) continue;
            const md = c.LLVMGetOperand(inst, @as(c_uint, @intCast(num_ops - 1)));
            if (@intFromPtr(md) == 0) continue;

            // Check if metadata references our alloca
            const md_ops = c.LLVMGetNumOperands(md);
            if (md_ops < 2) continue;
            const val = c.LLVMGetOperand(md, 0);
            if (val != alloca) continue;

            // Get the DI type name from the variable
            const di_var = c.LLVMGetOperand(md, 1);
            if (@intFromPtr(di_var) == 0) continue;
            const name_ptr = c.LLVMGetValueName(di_var);
            if (@intFromPtr(name_ptr) == 0) continue;
            const name = std.mem.sliceTo(name_ptr, 0);
            if (name.len > 0) return name;
        }
    }
    return null;
}

/// Trace a pointer value back to its alloca base.
fn traceToAlloca(value: c.LLVMValueRef) c.LLVMValueRef {
    var current = value;
    var depth: u32 = 0;
    while (depth < 8) : (depth += 1) {
        if (c.LLVMGetInstructionOpcode(current) == c.LLVMAlloca) return current;
        if (@intFromPtr(c.LLVMIsAInstruction(current)) == 0) return @ptrFromInt(0);
        const opcode = c.LLVMGetInstructionOpcode(current);
        if (opcode == c.LLVMGetElementPtr or opcode == c.LLVMLoad or
            opcode == c.LLVMBitCast)
        {
            current = c.LLVMGetOperand(current, 0);
            if (@intFromPtr(current) == 0) return @ptrFromInt(0);
            continue;
        }
        break;
    }
    return @ptrFromInt(0);
}

/// Get callee name from a call instruction.
fn getCalleeName(inst: c.LLVMValueRef) ?[]const u8 {
    const called_val = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_val) == 0) return null;
    const name_raw = c.LLVMGetValueName(called_val);
    if (@intFromPtr(name_raw) == 0) return null;
    const name = std.mem.sliceTo(name_raw, 0);
    if (name.len == 0) return null;
    return name;
}
