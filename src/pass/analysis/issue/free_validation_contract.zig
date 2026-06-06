//! Free Validation — FFI Contract Database Validation
//!
//! Extracted from free_validation.zig: validateWithContractDB,
//! inferAllocFuncName, validateWithContractDBFromSource, extractAllocFuncName,
//! extractAllocFuncNameForCrossLang.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const PassContext = @import("../../pass.zig").PassContext;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;
const report = @import("free_validation_report.zig");
const mg_types = @import("../../../types/memory_graph_types.zig");
const AllocNode = mg_types.AllocNode;
const FFIContractDB = @import("../../../resource/ffi_contract_db.zig").FFIContractDB;

/// Validate alloc/free pair using FFI Contract Database.
///
/// Checks whether the release function is correct for the allocation
/// according to library-specific lifecycle rules (e.g., SSL_new → SSL_free).
///
/// Returns:
///   - `true`  → mismatch bug detected (wrong release function)
///   - `false` → valid pair (correct release function)
///   - `null`  → no contract info available (continue to next layer)
pub fn validateWithContractDB(
    db: *FFIContractDB,
    node: *const AllocNode,
    callee_name: []const u8,
    ctx: *PassContext,
    caller_func: c.LLVMValueRef,
    ptr_arg: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !?bool {
    const alloc_func_name = inferAllocFuncName(node) orelse return null;

    std.log.scoped(.free_validation).debug("CONTRACT-DB: Checking pair {s} -> {s}", .{ alloc_func_name, callee_name });

    const result = db.isValidRelease(alloc_func_name, callee_name);

    switch (result) {
        .valid_pair => {
            std.log.scoped(.free_validation).debug("CONTRACT-DB: Valid pair confirmed: {s} -> {s}", .{
                alloc_func_name, callee_name,
            });
            const mg = @import("free_validation_mg.zig");
            mg.markAsFreed(ctx, @intFromPtr(ptr_arg), callee_name);
            return false;
        },
        .mismatch => {
            std.log.scoped(.free_validation).warn("CONTRACT-DB: MISMATCH! alloc={s} but free={s}", .{
                alloc_func_name, callee_name,
            });
            try report.reportMismatchIssue(ctx, caller_func, callee_name, ptr_arg, node, alloc_func_name, db, diag);
            return true;
        },
        .unknown_alloc, .unknown_release => {
            std.log.scoped(.free_validation).debug("CONTRACT-DB: No contract info for {s}, continuing...", .{
                alloc_func_name,
            });
            return null;
        },
    }
}

/// Infer the allocation function name from an AllocNode.
pub fn inferAllocFuncName(node: *const AllocNode) ?[]const u8 {
    if (node.alloc_family) |family| {
        return switch (family) {
            .c_heap => "malloc",
            .c_mmap => "mmap",
            .c_aligned => "aligned_alloc",
            .cpp_new_scalar => "operator new",
            .cpp_new_array => "operator new[]",
            .rust_global => "__rust_alloc",
            .rust_box => "__rust_alloc",
            else => null,
        };
    }
    return null;
}

/// Validate alloc/free pair using FFI Contract Database based on source_desc.
/// This is the source_desc-based complement to validateWithContractDB (which uses AllocNode).
///
/// Returns:
///   - `true`  → mismatch bug detected (wrong release function)
///   - `false` → valid pair (correct release function)
///   - `null`  → no contract info available (continue to next layer)
pub fn validateWithContractDBFromSource(
    ctx: *PassContext,
    source_desc: []const u8,
    callee_name: []const u8,
    caller_func: c.LLVMValueRef,
    free_inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !?bool {
    const alloc_func = extractAllocFuncName(source_desc) orelse return null;

    std.log.scoped(.free_validation).debug("CONTRACT-DB-SOURCE: Checking pair {s} -> {s} at inst 0x{x} (from source_desc: '{s}')", .{
        alloc_func, callee_name, @intFromPtr(free_inst), source_desc,
    });

    const result = ctx.contract_db.isValidRelease(alloc_func, callee_name);

    switch (result) {
        .valid_pair => {
            std.log.scoped(.free_validation).debug("CONTRACT-DB-SOURCE: ✓ Valid pair: {s} -> {s}", .{
                alloc_func, callee_name,
            });
            return false;
        },
        .mismatch => {
            std.log.scoped(.free_validation).warn("CONTRACT-DB-SOURCE: ✗ MISMATCH! alloc={s} but free={s}", .{
                alloc_func, callee_name,
            });
            const expected = ctx.contract_db.getExpectedReleases(alloc_func);
            if (expected) |expected_frees| {
                try report.reportCrossAllocatorMismatch(ctx, caller_func, alloc_func, callee_name, expected_frees, diag);
            } else {
                const fallback_expected = &[_][]const u8{"see library documentation"};
                try report.reportCrossAllocatorMismatch(ctx, caller_func, alloc_func, callee_name, fallback_expected, diag);
            }
            return true;
        },
        .unknown_alloc, .unknown_release => {
            std.log.scoped(.free_validation).debug("CONTRACT-DB-SOURCE: No contract info for {s}, using heuristics", .{
                alloc_func,
            });
            if (!ctx.contract_db.shouldReportLeak(alloc_func)) {
                std.log.scoped(.free_validation).debug("CONTRACT-DB-SOURCE: Suppressing leak check for GC-managed: {s}", .{
                    alloc_func,
                });
                return false;
            }
            return null;
        },
    }
}

/// Extract the allocator function name from origin info description.
pub fn extractAllocFuncName(source_desc: []const u8) ?[]const u8 {
    // Pattern 1: Find "by XXXX()"
    if (std.mem.indexOf(u8, source_desc, "by ")) |start| {
        const after_by = source_desc[start + 3 ..];
        if (std.mem.indexOf(u8, after_by, "()")) |end| {
            return after_by[0..end];
        }
    }
    // Pattern 2: Find "via XXXX()"
    if (std.mem.indexOf(u8, source_desc, "via ")) |start| {
        const after_via = source_desc[start + 4 ..];
        if (std.mem.indexOf(u8, after_via, "()")) |end| {
            return after_via[0..end];
        }
    }
    // Pattern 3: Find "from XXXX()"
    if (std.mem.indexOf(u8, source_desc, "from ")) |start| {
        const after_from = source_desc[start + 5 ..];
        const trimmed = if (std.mem.indexOf(u8, after_from, "call ")) |call_start|
            after_from[call_start + 5 ..]
        else
            after_from;
        if (std.mem.indexOf(u8, trimmed, "()")) |end| {
            if (end > 0 and end < 64) {
                return trimmed[0..end];
            }
        }
    }
    // Pattern 4: Direct function name at start
    if (std.mem.indexOf(u8, source_desc, "(")) |end| {
        if (end > 0 and end < 64) {
            const candidate = source_desc[0..end];
            const first_char = candidate[0];
            if ((first_char >= 'a' and first_char <= 'z') or
                first_char == '_' or
                (first_char >= 'A' and first_char <= 'Z' and end > 2))
            {
                return candidate;
            }
        }
    }
    return null;
}

/// Extract allocation function name for cross-language detection.
/// Similar to extractAllocFuncName but optimized for cross-language patterns.
pub fn extractAllocFuncNameForCrossLang(source_desc: []const u8) ?[]const u8 {
    // Pattern 1: "from XXXX()" - most common format
    if (std.mem.indexOf(u8, source_desc, "from ")) |start| {
        const after_from = source_desc[start + 5 ..];
        const trimmed = if (std.mem.indexOf(u8, after_from, "call ")) |call_start|
            after_from[call_start + 5 ..]
        else
            after_from;
        if (std.mem.indexOf(u8, trimmed, "()")) |end| {
            if (end > 0 and end < 128) {
                return trimmed[0..end];
            }
        }
    }
    // Pattern 2: Direct function name with known Rust/C++ patterns
    if (std.mem.indexOf(u8, source_desc, "()")) |end| {
        if (end > 3 and end < 128) {
            const candidate = source_desc[0..end];
            const first_char = candidate[0];
            if ((first_char >= 'a' and first_char <= 'z') or first_char == '_' or
                (first_char >= 'A' and first_char <= 'Z'))
            {
                return candidate;
            }
        }
    }
    return null;
}
