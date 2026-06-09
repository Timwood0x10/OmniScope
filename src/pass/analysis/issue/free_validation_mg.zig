//! Free Validation — MemoryGraph-based Validation
//!
//! Extracted from free_validation.zig: validateFreeWithMemoryGraph (6-layer
//! validation pipeline) and related helpers.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const PassContext = @import("../../pass.zig").PassContext;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;
const contract = @import("free_validation_contract.zig");
const report = @import("free_validation_report.zig");
const safety = @import("free_validation_safety.zig");
const mg_types = @import("../../../types/memory_graph_types.zig");
const AllocNode = mg_types.AllocNode;
const FamilyId = mg_types.FamilyId;

/// Enhanced MemoryGraph-based ownership validation for free calls.
/// Eliminates false positives by querying MemoryGraph and FFIContractDB
/// to verify alloc/free matching before reporting issues.
///
/// Detection layers (in order):
///   1. FFIContractDB: Is this alloc/free pair valid per library contracts?
///   2. Double-free: Has this pointer already been freed?
///   3. Borrowed ref: Is this a borrowed pointer that shouldn't be freed?
///   4. Same-family: Are alloc and free from the same allocator family?
///   5. Rust ownership: Is this a valid Rust ownership transfer pattern?
///   6. Cross-allocator mismatch: REAL bug - wrong allocator for free
///
/// Returns:
///   - `true`  → bug detected (caller should report and return true)
///   - `false` → safe release (valid free, no issue)
///   - `null`  → cannot determine (caller should fallback to legacy logic)
pub fn validateFreeWithMemoryGraph(
    ctx: *PassContext,
    ptr_arg: c.LLVMValueRef,
    callee_name: []const u8,
    caller_func: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !?bool {
    const ptr_val: u64 = @intFromPtr(ptr_arg);

    // Use findCanonicalAlloc to handle aliases (ownership transfers, FFI boundaries)
    const node = ctx.memory_graph.findCanonicalAlloc(ptr_val) orelse return null;

    std.log.scoped(.free_validation).debug("FREE_VALIDATION: Checking free of ptr 0x{x} ({s}), alloc_node id={d}, family={s}", .{
        ptr_val,
        callee_name,
        node.id,
        if (node.alloc_family) |f| @tagName(f) else "null",
    });

    // Layer 1: FFIContractDB validation
    {
        const pair_validity = try contract.validateWithContractDB(&ctx.contract_db, node, callee_name, ctx, caller_func, ptr_arg, diag);
        if (pair_validity) |result| {
            return result;
        }
    }

    // Layer 2: Double-free detection using enhanced analysis with FP reduction
    if (node.freed) {
        std.log.scoped(.free_validation).warn("FREE_VALIDATION: Potential DOUBLE-FREE! ptr 0x{x} already freed at 0x{x}", .{
            ptr_val,
            node.freed_by orelse 0,
        });

        const df_analysis = ctx.memory_graph.analyzeDoubleFreeWithConfidence(ptr_val);

        if (df_analysis.is_double_free) {
            const conf_percent = @as(u32, @intFromFloat(df_analysis.confidence * 100.0));
            std.log.scoped(.free_validation).warn("FREE_VALIDATION: DOUBLE-FREE CONFIRMED (confidence={d}%%): {s}", .{
                conf_percent,
                df_analysis.reason,
            });
            try report.reportDoubleFreeIssue(ctx, caller_func, callee_name, ptr_arg, node, diag);
            return true;
        } else if (df_analysis.confidence > 0.3 and df_analysis.confidence < 0.6) {
            std.log.scoped(.free_validation).debug("FREE_VALIDATION: Suspected double-free suppressed (confidence={d:.1}): {s}", .{
                df_analysis.confidence,
                df_analysis.reason,
            });
            return false;
        } else {
            std.log.scoped(.free_validation).debug("FREE_VALIDATION: Not a double-free: {s}", .{df_analysis.reason});
            return false;
        }
    }

    // Layer 3: Borrowed/refcount check
    if (safety.isBorrowedOrRefcount(node)) {
        std.log.scoped(.free_validation).debug("FREE_VALIDATION: Skipping borrowed/refcount ptr (likely DECREF, not real free)", .{});
        return false;
    }

    // Layer 4: Same-family check
    const alloc_family = node.alloc_family orelse .invalid;
    const free_family = classifyReleaseFamilyByName(ctx, callee_name);

    if (alloc_family == free_family and alloc_family != .invalid) {
        std.log.scoped(.free_validation).debug("MG-SAME-FAMILY: {s} matches alloc family {s}, safe", .{
            callee_name, @tagName(alloc_family),
        });
        markAsFreed(ctx, ptr_val, callee_name);
        return false;
    }

    // Layer 5: Rust ownership transfer patterns
    if (safety.isRustOwnershipTransfer(node, callee_name)) {
        std.log.scoped(.free_validation).debug("MG-RUST-OWNERSHIP: {s} on Rust-allocated ptr, safe", .{callee_name});
        markAsFreed(ctx, ptr_val, callee_name);
        return false;
    }

    // Layer 6: Cross-allocator mismatch = REAL bug
    if (safety.isCrossAllocatorMismatch(node, callee_name)) {
        try report.reportCrossAllocatorFree(ctx, caller_func, callee_name, ptr_arg, node, diag);
        return true;
    }

    return null;
}

/// Classify the release family of a free/dealloc function by name.
/// Looks up the callee name in the family registry and returns the FamilyId.
/// Returns .invalid if the function is not a known deallocator.
pub fn classifyReleaseFamilyByName(ctx: *PassContext, callee_name: []const u8) FamilyId {
    const registry = ctx.memory_graph.family_registry orelse return .invalid;
    const op = registry.lookupRelease(callee_name, null) orelse return .invalid;
    return op.family;
}

/// Mark a pointer as freed in MemoryGraph for future double-free detection.
/// This updates the AllocNode state so subsequent frees can be detected.
pub fn markAsFreed(ctx: *PassContext, ptr_val: u64, free_callee: []const u8) void {
    _ = ctx.memory_graph.trackFree(
        ptr_val,
        ptr_val,
        if (std.mem.indexOf(u8, free_callee, "__rust") != null) .rust else .c,
        0,
    ) catch |err| {
        std.log.scoped(.free_validation).warn("FREE_VALIDATION: Failed to track free in MemoryGraph: {}", .{err});
    };
}
