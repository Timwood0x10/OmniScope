//! Control Flow Sensitive Analysis
//!
//! Identifies mutually exclusive branches to reduce false positives.
//! Key insight from investigation reports:
//! - mbedtls: if (cert == NULL) { free(ptr); } else { use(ptr); }
//!   These branches are mutually exclusive, not a UAF.
//!
//! This module implements:
//! 1. Branch condition extraction
//! 2. Mutually exclusive branch detection
//! 3. Path-sensitive memory access tracking

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

/// Represents a branch condition in the CFG.
pub const BranchCondition = struct {
    /// The basic block containing the branch.
    block: c.LLVMBasicBlockRef,
    /// The condition instruction (icmp).
    condition: c.LLVMValueRef,
    /// True branch target.
    true_block: c.LLVMBasicBlockRef,
    /// False branch target.
    false_block: c.LLVMBasicBlockRef,
};

/// Represents a memory access within a branch.
pub const BranchMemoryAccess = struct {
    /// The basic block where access occurs.
    block: c.LLVMBasicBlockRef,
    /// The pointer being accessed.
    ptr_id: u32,
    /// Access type: load, store, or free.
    access_type: enum(u8) { load, store, free },
    /// Which branch this access belongs to.
    branch_taken: ?bool,
};

/// Result of analyzing mutually exclusive branches.
pub const MutualExclusionResult = struct {
    /// Pairs of blocks that are mutually exclusive.
    exclusive_pairs: std.ArrayList(struct { a: c.LLVMBasicBlockRef, b: c.LLVMBasicBlockRef }),
    /// Blocks that are reachable from true branch.
    true_reachable: std.AutoHashMap(c.LLVMBasicBlockRef, void),
    /// Blocks that are reachable from false branch.
    false_reachable: std.AutoHashMap(c.LLVMBasicBlockRef, void),
};

/// Check if two basic blocks are mutually exclusive.
///
/// Two blocks are mutually exclusive if:
/// 1. They have a common immediate predecessor
/// 2. That predecessor ends with a conditional branch
/// 3. Each block is reachable from a different branch
///
/// Arguments:
///   allocator - Memory allocator
///   block_a - First basic block
///   block_b - Second basic block
///
/// Returns:
///   true if the blocks are mutually exclusive
pub fn areMutuallyExclusive(
    allocator: std.mem.Allocator,
    block_a: c.LLVMBasicBlockRef,
    block_b: c.LLVMBasicBlockRef,
) bool {
    if (@intFromPtr(block_a) == 0 or @intFromPtr(block_b) == 0) return false;
    if (block_a == block_b) return false;

    var preds_a = std.ArrayList(c.LLVMBasicBlockRef).init(allocator);
    defer preds_a.deinit();
    var preds_b = std.ArrayList(c.LLVMBasicBlockRef).init(allocator);
    defer preds_b.deinit();

    collectPredecessors(block_a, &preds_a);
    collectPredecessors(block_b, &preds_b);

    for (preds_a.items) |pred_a| {
        for (preds_b.items) |pred_b| {
            if (pred_a == pred_b) {
                if (endsWithConditionalBranch(pred_a)) {
                    const term = c.LLVMGetBasicBlockTerminator(pred_a);
                    if (@intFromPtr(term) != 0 and c.LLVMIsABranchInst(term) != null) {
                        if (c.LLVMGetNumOperands(term) == 3) {
                            const true_block = c.LLVMGetOperand(term, 2);
                            const false_block = c.LLVMGetOperand(term, 1);
                            if ((true_block == block_a and false_block == block_b) or
                                (true_block == block_b and false_block == block_a))
                            {
                                return true;
                            }
                        }
                    }
                }
            }
        }
    }

    return false;
}

/// Collect all predecessors of a basic block.
fn collectPredecessors(
    block: c.LLVMBasicBlockRef,
    preds: *std.ArrayList(c.LLVMBasicBlockRef),
) void {
    if (@intFromPtr(block) == 0) return;

    const func = c.LLVMGetBasicBlockParent(block);
    if (@intFromPtr(func) == 0) return;

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        const term = c.LLVMGetBasicBlockTerminator(bb);
        if (@intFromPtr(term) != 0 and c.LLVMIsABranchInst(term) != null) {
            const num_ops = c.LLVMGetNumOperands(term);
            var i: c_uint = 0;
            while (i < num_ops) : (i += 1) {
                const op = c.LLVMGetOperand(term, i);
                if (c.LLVMIsABasicBlock(op) != null) {
                    if (op == block) {
                        preds.append(bb) catch {};
                        break;
                    }
                }
            }
        }
    }
}

/// Check if a basic block ends with a conditional branch.
fn endsWithConditionalBranch(block: c.LLVMBasicBlockRef) bool {
    if (@intFromPtr(block) == 0) return false;

    const term = c.LLVMGetBasicBlockTerminator(block);
    if (@intFromPtr(term) == 0) return false;

    if (c.LLVMIsABranchInst(term) == null) return false;

    return c.LLVMGetNumOperands(term) == 3;
}

/// Analyze a function for mutually exclusive branches.
///
/// Arguments:
///   allocator - Memory allocator
///   func - The function to analyze
///
/// Returns:
///   MutualExclusionResult with all exclusive pairs
pub fn analyzeMutualExclusion(
    allocator: std.mem.Allocator,
    func: c.LLVMValueRef,
) MutualExclusionResult {
    var result = MutualExclusionResult{
        .exclusive_pairs = std.ArrayList(struct { a: c.LLVMBasicBlockRef, b: c.LLVMBasicBlockRef }).init(allocator),
        .true_reachable = std.AutoHashMap(c.LLVMBasicBlockRef, void).init(allocator),
        .false_reachable = std.AutoHashMap(c.LLVMBasicBlockRef, void).init(allocator),
    };

    var blocks = std.ArrayList(c.LLVMBasicBlockRef).init(allocator);
    defer blocks.deinit();

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        blocks.append(bb) catch {};
    }

    for (blocks.items, 0..) |block_a, i| {
        for (blocks.items[i + 1 ..]) |block_b| {
            if (areMutuallyExclusive(allocator, block_a, block_b)) {
                result.exclusive_pairs.append(.{ .a = block_a, .b = block_b }) catch {};
            }
        }
    }

    return result;
}

/// Check if a memory access is safe due to mutual exclusion.
///
/// If a free occurs in one branch and an access in another,
/// and those branches are mutually exclusive, it's safe.
///
/// Arguments:
///   allocator - Memory allocator
///   free_block - Block containing the free
///   access_block - Block containing the access
///
/// Returns:
///   true if the access is safe due to mutual exclusion
pub fn isSafeDueToMutualExclusion(
    allocator: std.mem.Allocator,
    free_block: c.LLVMBasicBlockRef,
    access_block: c.LLVMBasicBlockRef,
) bool {
    return areMutuallyExclusive(allocator, free_block, access_block);
}

/// Detect if-else pattern with early return.
///
/// Pattern:
///   if (condition) {
///       free(ptr);
///       return;
///   }
///   use(ptr);  // Safe because if we reach here, ptr is not freed
///
/// Arguments:
///   free_block - Block containing the free
///
/// Returns:
///   true if this is an early-return pattern
pub fn isEarlyReturnPattern(
    free_block: c.LLVMBasicBlockRef,
) bool {
    if (@intFromPtr(free_block) == 0) return false;

    const term = c.LLVMGetBasicBlockTerminator(free_block);
    if (@intFromPtr(term) == 0) return false;

    if (c.LLVMIsAReturnInst(term) != null) {
        return true;
    }

    if (c.LLVMIsABranchInst(term) != null) {
        const num_ops = c.LLVMGetNumOperands(term);
        if (num_ops == 1) {
            const succ = c.LLVMGetOperand(term, 0);
            if (c.LLVMIsABasicBlock(succ) != null) {
                const succ_term = c.LLVMGetBasicBlockTerminator(succ);
                if (@intFromPtr(succ_term) != 0 and c.LLVMIsAReturnInst(succ_term) != null) {
                    return true;
                }
            }
        }
    }

    return false;
}

/// Detect cleanup-on-error pattern.
///
/// Pattern:
///   if (error) {
///       free(ptr);
///       goto cleanup;
///   }
///   use(ptr);  // Safe because we only free on error path
///
/// Arguments:
///   free_block - Block containing the free
///
/// Returns:
///   true if this is a cleanup-on-error pattern
pub fn isCleanupOnErrorPattern(
    free_block: c.LLVMBasicBlockRef,
) bool {
    if (@intFromPtr(free_block) == 0) return false;

    const block_name_ptr = c.LLVMGetBasicBlockName(free_block);
    if (@intFromPtr(block_name_ptr) != 0) {
        const block_name = std.mem.span(block_name_ptr);
        const error_patterns = [_][]const u8{
            "err",
            "error",
            "cleanup",
            "fail",
            "exit",
            "catch",
        };

        for (error_patterns) |pattern| {
            if (std.mem.indexOf(u8, block_name, pattern) != null) {
                return true;
            }
        }
    }

    return false;
}

/// Comprehensive check for safe control flow patterns.
///
/// Arguments:
///   allocator - Memory allocator
///   free_block - Block containing the free
///   access_block - Block containing the access
///
/// Returns:
///   true if the access is safe due to control flow
pub fn isSafeControlFlowPattern(
    allocator: std.mem.Allocator,
    free_block: c.LLVMBasicBlockRef,
    access_block: c.LLVMBasicBlockRef,
) bool {
    if (areMutuallyExclusive(allocator, free_block, access_block)) {
        return true;
    }

    if (isEarlyReturnPattern(free_block)) {
        return true;
    }

    if (isCleanupOnErrorPattern(free_block)) {
        return true;
    }

    return false;
}

test "areMutuallyExclusive - same block" {
    const allocator = std.testing.allocator;
    try std.testing.expect(!areMutuallyExclusive(allocator, null, null));
}

test "isEarlyReturnPattern - null block" {
    try std.testing.expect(!isEarlyReturnPattern(null));
}

test "isCleanupOnErrorPattern - null block" {
    try std.testing.expect(!isCleanupOnErrorPattern(null));
}
