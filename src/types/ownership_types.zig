//! Pointer Ownership — Type Definitions & Common Helpers
//!
//! Extracted from pointer_ownership.zig to reduce file size.
//! Shared types used by pointer_ownership, cpp_fp_reduction, and other passes.

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const Language = @import("../diag/issue.zig").FFIBoundary.Language;
const alloc_classifier = @import("../pass/analysis/ptr_lifetime/allocation_classifier.zig");

pub const AllocType = alloc_classifier.AllocType;
pub const FreeType = alloc_classifier.FreeType;

/// Error type for ownership tracking operations.
pub const OwnershipError = error{
    OutOfMemory,
    NoModule,
    NullPointer,
};

/// Truncate u64 LLVM instruction ID to u32 for use in HashMap keys.
/// LLVM instruction IDs can exceed u32 range in large modules, but we use
/// the truncated value as a hash key rather than an exact identifier.
/// Collisions are possible but rare and acceptable for analysis purposes.
pub fn truncateInstId(inst_id: u64) u32 {
    return @as(u32, @truncate(inst_id));
}

/// Resolve LLVM instruction pointer (u64) back to its containing function name.
/// MemoryGraph stores instruction pointers as u64; this recovers the function name
/// via LLVM's instruction→basic block→function chain.
pub fn resolveInstFuncName(inst: u64) []const u8 {
    if (inst == 0) return "memory_graph";
    const inst_ref: c.LLVMValueRef = @ptrFromInt(inst);
    const bb = c.LLVMGetInstructionParent(inst_ref);
    if (@intFromPtr(bb) == 0) return "memory_graph";
    const func = c.LLVMGetBasicBlockParent(bb);
    if (@intFromPtr(func) == 0) return "memory_graph";
    const name = c.LLVMGetValueName(func);
    if (@intFromPtr(name) == 0) return "memory_graph";
    return std.mem.span(name);
}

/// Ownership violation types detected by this pass.
pub const OwnershipViolationType = enum(u8) {
    cross_lang_free_mismatch,
    ownership_lost,
    double_free_risk,
    rust_drop_after_ffi_transfer,
    memory_leak,
    use_after_free,
    null_dereference,
};

/// Allocation site information.
pub const AllocSite = struct {
    inst_id: u32,
    func_name: []const u8,
    lang: Language,
    alloc_type: AllocType,
    ptr_value_id: u32,
    bb_id: usize,
    transferred: bool = false,
    stored_to_struct_field: bool = false,
    debug_file: ?[]const u8,
    debug_line: ?u32,
    debug_column: ?u32,
};

/// Pointer ownership state.
pub const OwnershipState = enum(u8) {
    live,
    ownership_transferred,
    freed,
    leaked,
};

/// Free site information.
pub const FreeSite = struct {
    inst_id: u32,
    func_name: []const u8,
    lang: Language,
    free_type: FreeType,
    ptr_value_id: u32,
    bb_id: usize,
    debug_file: ?[]const u8,
    debug_line: ?u32,
    debug_column: ?u32,
};

/// Pointer flow edge - tracks how pointers move through the program.
pub const PointerFlowEdge = struct {
    from_inst: u32,
    to_inst: u32,
    flow_type: FlowType,
};

pub const FlowType = enum(u8) {
    assignment,
    argument,
    return_value,
    store,
    load,
};

/// Statistics for ownership tracking.
pub const OwnershipStats = struct {
    alloc_sites: u32 = 0,
    free_sites: u32 = 0,
    tracked_pointers: u32 = 0,
    cross_ffi_transfers: u32 = 0,
    violations: u32 = 0,
    memory_leaks: u32 = 0,
    double_frees: u32 = 0,
    use_after_frees: u32 = 0,
};
