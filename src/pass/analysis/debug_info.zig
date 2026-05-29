//! Debug Info Helpers for LLVM IR Metadata Analysis
//!
//! Provides utilities for extracting type names and structural information
//! from LLVM Debug Info metadata. Falls back to safe defaults when
//! metadata is unavailable or incompatible with the current LLVM version.
//!
//! Design: All functions return optional values (?T) to gracefully handle
//! missing or malformed debug info without crashing.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

/// Check if a value has debug metadata attached.
pub fn hasDebugMetadata(value: c.LLVMValueRef) bool {
    if (@intFromPtr(value) == 0) return false;
    const meta = c.LLVMGetMetadata(value, 0);
    return @intFromPtr(meta) != 0;
}

/// Extract field name from DI member type metadata.
///
/// Uses LLVMGetValueName as a fallback when direct DI string extraction
/// is not available (LLVM version compatibility).
pub fn getDIFieldName(di_type: c.LLVMValueRef) ?[]const u8 {
    if (@intFromPtr(di_type) == 0) return null;

    // Try to get name via LLVMGetValueName (works for named metadata nodes)
    const name_ptr = c.LLVMGetValueName(di_type);
    if (@intFromPtr(name_ptr) != 0) {
        const name = std.mem.sliceTo(name_ptr, 0);
        if (name.len > 0) return name;
    }

    // Fallback: try operand-based extraction (LLVM-version agnostic)
    const num_operands = c.LLVMGetNumOperands(di_type);
    if (num_operands >= 3) {
        const name_node = c.LLVMGetOperand(di_type, 2);
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

/// Extract type/struct name from DI type metadata.
///
/// Walks up the DI type hierarchy (up to 4 levels) looking for a
/// type name. Returns null if no name is found or metadata is unavailable.
pub fn getDITypeName(di_type: c.LLVMValueRef) ?[]const u8 {
    if (@intFromPtr(di_type) == 0) return null;

    var current = di_type;
    var depth: u32 = 0;

    while (depth < 4 and @intFromPtr(current) != 0) : (depth += 1) {
        // Try direct name first
        const name_ptr = c.LLVMGetValueName(current);
        if (@intFromPtr(name_ptr) != 0) {
            const type_name = std.mem.sliceTo(name_ptr, 0);
            if (type_name.len > 0) return type_name;
        }

        // Try operand-based extraction
        const num_ops = c.LLVMGetNumOperands(current);
        if (num_ops >= 3) {
            const name_node = c.LLVMGetOperand(current, 2);
            if (@intFromPtr(name_node) != 0) {
                const node_name = c.LLVMGetValueName(name_node);
                if (@intFromPtr(node_name) != 0) {
                    const name = std.mem.sliceTo(node_name, 0);
                    if (name.len > 0) return name;
                }
            }
        }

        // Walk to base type (operand 1)
        if (num_ops >= 2) {
            current = c.LLVMGetOperand(current, 1);
        } else {
            break;
        }
    }

    return null;
}

/// Get struct name from a GEP instruction using debug metadata.
/// Falls back to heuristic if no debug info available.
pub fn getStructNameForGEP(gep: c.LLVMValueRef) ?[]const u8 {
    if (@intFromPtr(gep) == 0) return null;

    // Try debug metadata first
    const meta = c.LLVMGetMetadata(gep, 0);
    if (@intFromPtr(meta) != 0) {
        // Extract type info from metadata
        const meta_name = c.LLVMGetValueName(meta);
        if (@intFromPtr(meta_name) != 0) {
            const name = std.mem.sliceTo(meta_name, 0);
            if (name.len > 0) return name;
        }
    }

    // Fallback: try to infer from GEP structure type
    const src_type = c.LLVMTypeOf(c.LLVMGetOperand(gep, 0));
    if (@intFromPtr(src_type) != 0) {
        const type_name = c.LLVMGetStructName(src_type);
        if (@intFromPtr(type_name) != 0) {
            const name = std.mem.sliceTo(type_name, 0);
            if (name.len > 0) return name;
        }
    }

    return null;
}

/// Get base type from a DI composite type (for chain walking).
///
/// Returns the base type of a derived type (pointer, reference, typedef),
/// or null if not applicable or unavailable.
pub fn getDIBaseType(di_type: c.LLVMValueRef) c.LLVMValueRef {
    if (@intFromPtr(di_type) == 0) return @ptrFromInt(@as(usize, 0));

    const num_ops = c.LLVMGetNumOperands(di_type);
    // Base type is typically operand 1 in DI derived types
    if (num_ops >= 2) {
        return c.LLVMGetOperand(di_type, 1);
    }

    return @ptrFromInt(@as(usize, 0));
}

/// Check if a DI metadata node represents an AMDString (string constant).
///
/// This is a lightweight check that doesn't rely on LLVMIsAMDString
/// which may have compatibility issues across LLVM versions.
pub fn isAMDStringNode(node: c.LLVMValueRef) bool {
    if (@intFromPtr(node) == 0) return false;

    // Try to get the string value - if it works, it's likely an AMDString
    const str_val = c.LLVMGetValueName(node);
    if (@intFromPtr(str_val) != 0) {
        return true;
    }

    return false;
}
