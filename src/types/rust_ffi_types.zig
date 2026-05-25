//! Rust FFI Auditor — Type Definitions & Common Helpers
//!
//! Extracted from rust_ffi_auditor.zig for modularity.
//! Contains all shared data structures used by the Rust FFI auditor
//! and its detection modules.

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const CommonTypes = @import("../common/types.zig");
const tracking = @import("../pass/analysis/ptr_lifetime/value_tracking.zig");
const Location = @import("../diag/issue.zig").Location;

/// Re-export from value_tracking.zig (T1-T2 unified API)
pub const ValueSource = tracking.ValueSource;
pub const ValueUsage = tracking.ValueUsage;
pub const UsageSet = tracking.UsageSet;

/// Rust FFI issue types specific to this auditor
pub const RustFfiIssueType = enum {
    unpaired_into_raw,
    unpaired_cstring_into_raw,
    as_ptr_borrow_escape,
    cross_lang_alloc_mismatch,
    unsafe_ffi_call,
    extern_c_type_mismatch,
    stack_address_escape,
};

/// Rust FFI audit result for a single function
pub const RustFfiFinding = struct {
    func_name: []const u8,
    issue_type: RustFfiIssueType,
    severity: CommonTypes.Severity,
    confidence: f32,
    reason: []const u8,
    location: Location,
};

/// Internal: tracks a free call encountered during analysis
pub const FreeEntry = struct { val: c.LLVMValueRef, free_name: []const u8 };

/// Audit statistics counters
pub const AuditStats = struct {
    total_functions_analyzed: usize = 0,
    into_raw_funcs: usize = 0,
    from_raw_funcs: usize = 0,
    as_ptr_escapes: usize = 0,
    cross_lang_mismatches: usize = 0,
    unsafe_ffi_calls: usize = 0,
    stack_escapes: usize = 0,
    unpaired_into_raw: usize = 0,
};

// ============================================================================
// Common Helper Functions
// ============================================================================

/// Get a safe UTF-8 function name from an LLVM value reference.
/// Returns a borrowed slice (LLVM-owned memory, do not free).
fn getFunctionName(func: c.LLVMValueRef) []const u8 {
    const name_ptr = c.LLVMGetValueName(func);
    if (@intFromPtr(name_ptr) == 0) return "<unknown>";
    return std.mem.sliceTo(name_ptr, 0);
}

/// Check if a function name matches a Rust allocator pattern.
pub fn isRustAllocator(func_name: []const u8) bool {
    return std.mem.indexOf(u8, func_name, "__rust_alloc") != null or
        std.mem.indexOf(u8, func_name, "__rust_dealloc") != null or
        std.mem.indexOf(u8, func_name, "_Znwm") != null or
        std.mem.indexOf(u8, func_name, "_Znam") != null;
}

/// Check if a function name matches a C standard allocator.
pub fn isCAllocator(func_name: []const u8) bool {
    return std.mem.eql(u8, func_name, "malloc") or
        std.mem.eql(u8, func_name, "calloc") or
        std.mem.eql(u8, func_name, "realloc") or
        std.mem.eql(u8, func_name, "free");
}

/// Check if a function name is a Rust Drop-related function.
pub fn isRustDropGlue(func_name: []const u8) bool {
    return std.mem.indexOf(u8, func_name, "drop_in_place") != null or
        std.mem.indexOf(u8, func_name, "__rust_dealloc") != null or
        std.mem.indexOf(u8, func_name, "alloc::alloc::dealloc") != null or
        std.mem.indexOf(u8, func_name, "panic_in_cleanup") != null;
}

/// Check if a call is to a known safe function (no FFI risk).
pub fn isKnownSafeCall(func_name: []const u8) bool {
    return std.mem.indexOf(u8, func_name, "llvm.") != null or
        std.mem.indexOf(u8, func_name, "__rust_") != null or
        std.mem.eql(u8, func_name, "strlen") or
        std.mem.eql(u8, func_name, "memcmp");
}
