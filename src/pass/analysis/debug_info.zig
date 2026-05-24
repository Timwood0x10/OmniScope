//! Debug Info Helpers for LLVM IR Metadata Analysis
//!
//! Extracted from rust_ffi_auditor.zig. Provides DWARF debug metadata
//! interrogation utilities for struct field inference under opaque pointers.

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

// ============================================================================
// DIType (Debug Info Type) Helpers
// ============================================================================

/// Check if a DIType represents a const-qualified struct member.
/// Walks DIType chain: DW_TAG_member → DW_TAG_pointer_type → DW_TAG_const_type
pub fn isConstQualifiedMember(di_type: c.LLVMValueRef) bool {
    if (@intFromPtr(di_type) == 0) return false;

    const tag = c.LLVMGetMetadataKind(di_type);

    // Direct: DW_TAG_const_type
    if (tag == c.LLVMDWARFTypeEnumTag or
        (tag == 0 and isDITag(di_type, c.LLVMDWARFConstTypeTag)))
    {
        return true;
    }

    // Walk base type chain for pointer → const
    var current = di_type;
    var depth: u32 = 0;
    while (depth < 4 and @intFromPtr(current) != 0) : (depth += 1) {
        const base = getDIBaseType(current);
        if (@intFromPtr(base) == 0) break;

        const base_tag = c.LLVMGetMetadataKind(base);
        if (base_tag == c.LLVMDWARFTypeEnumTag or
            (base_tag == 0 and isDITag(base, c.LLVMDWARFConstTypeTag)))
        {
            return true;
        }
        current = base;
    }

    return false;
}

/// Get the base type of a DIType node.
pub fn getDIBaseType(di_type: c.LLVMValueRef) c.LLVMValueRef {
    const num_operands = c.LLVMGetNumOperands(di_type);
    if (num_operands >= 2) {
        return c.LLVMGetOperand(di_type, 1);
    }
    return @ptrFromInt(0);
}

/// Check if a DI metadata node has a specific DWARF tag.
pub fn isDITag(node: c.LLVMValueRef, expected_tag: c_uint) bool {
    const num_operands = c.LLVMGetNumOperands(node);
    if (num_operands < 1) return false;
    const tag_val = c.LLVMGetOperand(node, 0);
    if (@intFromPtr(tag_val) == 0) return false;
    if (c.LLVMIsAConstantInt(tag_val) != null) {
        _ = expected_tag;
        return false;
    }
    return false;
}

/// Extract field name from DI member type metadata.
pub fn getDIFieldName(di_type: c.LLVMValueRef) ?[]const u8 {
    const num_operands = c.LLVMGetNumOperands(di_type);
    if (num_operands >= 3) {
        const name_node = c.LLVMGetOperand(di_type, 2);
        if (@intFromPtr(name_node) != 0 and c.LLVMIsAMDString(name_node) != 0) {
            const name_ptr = c.LLVMGetAMDString(name_node);
            if (@intFromPtr(name_ptr) != 0) {
                return std.mem.span(name_ptr);
            }
        }
    }
    return null;
}

/// Extract type/struct name from DI type metadata.
pub fn getDITypeName(di_type: c.LLVMValueRef) ?[]const u8 {
    var current = di_type;
    var depth: u32 = 0;
    while (depth < 4 and @intFromPtr(current) != 0) : (depth += 1) {
        const num_ops = c.LLVMGetNumOperands(current);
        if (num_ops >= 3) {
            const name_node = c.LLVMGetOperand(current, 2);
            if (@intFromPtr(name_node) != 0 and c.LLVMIsAMDString(name_node) != 0) {
                const name_ptr = c.LLVMGetAMDString(name_node);
                if (@intFromPtr(name_ptr) != 0) {
                    const type_name = std.mem.span(name_ptr);
                    if (type_name.len > 0) return type_name;
                }
            }
        }
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
        // Walk metadata to find DICompositeType
        const num_ops = c.LLVMGetNumOperands(meta);
        var i: c_uint = 0;
        while (i < num_ops) : (i += 1) {
            const op = c.LLVMGetOperand(meta, i);
            if (@intFromPtr(op) == 0) continue;
            const name = getDITypeName(op);
            if (name) |n| return n;
        }
    }

    // Fallback: try to get name from base value's type
    const base = c.LLVMGetOperand(gep, 0);
    if (@intFromPtr(base) == 0) return null;
    const base_type = c.LLVMTypeOf(base);
    if (@intFromPtr(base_type) == 0) return null;

    // With opaque pointers, we can't reliably get struct name from type alone
    return null;
}
