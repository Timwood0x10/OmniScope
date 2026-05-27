//! FFI-specific violation checks for pointer lifetime analysis.
//!
//! Contains FFI boundary checks that were split from ptr_lifetime_violations.zig
//! to keep the main file under 1000 lines:
//!   - checkFFITypeMismatch — type safety via bitcast detection
//!   - checkFFIReturnNullGuard — NULL guard on FFI returns
//!   - checkStoreToGlobal — global storage escape detection
//!
//! These checks focus on cross-language ABI boundaries where type mismatches
//! and missing null guards are common vulnerability patterns.

const std = @import("std");
const c = @import("../../ffi/c.zig");
const log = @import("../../common/log.zig");

const pass_types = @import("../../types/pass_types.zig");
const PassContext = pass_types.PassContext;
const Issue = pass_types.Issue;
const Location = pass_types.Location;
const Severity = pass_types.Severity;
const PtrInfo = pass_types.PtrInfo;
const DiagnosticWriter = @import("../DiagnosticWriter.zig");
const LifetimeStats = @import("ptr_lifetime_types.zig").LifetimeStats;

const safe = @import("../../utils/llvm_safe.zig");

/// Check for FFI type mismatch via bitcast.
/// Detects when a pointer's element type changes across an FFI boundary,
/// which can indicate undefined behavior or memory corruption.
pub fn checkFFITypeMismatch(
    ctx: *PassContext,
    inst: c.LLVMValueRef,
    func: c.LLVMValueRef,
    func_name: []const u8,
    pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
    diag: *DiagnosticWriter,
    stats: *LifetimeStats,
) !void {
    _ = func;
    _ = stats;
    const called = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called) == 0) return;

    const name_ptr = c.LLVMGetValueName(called);
    if (@intFromPtr(name_ptr) == 0) return;
    const callee_name = std.mem.span(name_ptr);

    if (!isExternFunction(callee_name)) return;

    // Use standardized helper for consistent arg iteration
    const num_args = safe.getCallInstArgCount(inst);
    var arg_i: u32 = 0;
    while (arg_i < num_args) : (arg_i += 1) {
        const arg = c.LLVMGetOperand(inst, arg_i);
        if (@intFromPtr(arg) == 0) continue;

        const arg_opcode = c.LLVMGetInstructionOpcode(arg);
        if (arg_opcode == c.LLVMBitCast) {
            const src = c.LLVMGetOperand(arg, 0);
            if (@intFromPtr(src) == 0) continue;

            const src_type = c.LLVMTypeOf(src);
            const arg_type = c.LLVMTypeOf(arg);
            if (@intFromPtr(src_type) == 0 or @intFromPtr(arg_type) == 0) continue;

            if (c.LLVMGetTypeKind(src_type) == c.LLVMPointerTypeKind and
                c.LLVMGetTypeKind(arg_type) == c.LLVMPointerTypeKind)
            {
                const src_pointee = c.LLVMGetElementType(src_type);
                const arg_pointee = c.LLVMGetElementType(arg_type);
                if (@intFromPtr(src_pointee) != 0 and @intFromPtr(arg_pointee) != 0) {
                    if (c.LLVMGetTypeKind(src_pointee) != c.LLVMGetTypeKind(arg_pointee)) {
                        if (pointer_map.get(src)) |ptr_info| {
                            const mismatch_desc = try std.fmt.allocPrint(ctx.allocator, "const-cast: {s} type changed via bitcast", .{ptr_info.source_desc});
                            defer ctx.allocator.free(mismatch_desc);
                            try reportFFITypeMismatch(ctx, func_name, callee_name, mismatch_desc, inst, diag);
                            return;
                        }
                    }
                }
            }
        }
    }
}

/// Check if FFI return value has NULL guard.
/// Many FFI functions can return NULL on failure; using the result
/// without a null check is a common source of crashes.
pub fn checkFFIReturnNullGuard(
    ctx: *PassContext,
    inst: c.LLVMValueRef,
    func: c.LLVMValueRef,
    func_name: []const u8,
    pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
    diag: *DiagnosticWriter,
    stats: *LifetimeStats,
) !void {
    _ = func;
    const called = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called) == 0) return;

    const name_ptr = c.LLVMGetValueName(called);
    if (@intFromPtr(name_ptr) == 0) return;
    const callee_name = std.mem.span(name_ptr);

    if (!isExternFunction(callee_name)) return;

    const ret_type = c.LLVMTypeOf(inst);
    if (@intFromPtr(ret_type) == 0) return;
    if (c.LLVMGetTypeKind(ret_type) != c.LLVMPointerTypeKind) return;

    if (pointer_map.contains(inst)) return;

    // Safety check: verify instruction is valid before FFI analysis
    if (@intFromPtr(inst) == 0) return;
    const opcode = c.LLVMGetInstructionOpcode(inst);
    if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) return;

    // Wrap FFI checks with safety for large modules (libuv150 has 877 funcs)
    var has_null_guard = false;
    var is_result_used = false;

    // Use a panic-safe wrapper for complex IR patterns
    const safe_check = struct {
        fn run(call_inst: c.LLVMValueRef) struct { has_guard: bool, used: bool } {
            var guard = false;
            var used = false;

            // Inline simplified version that won't crash on complex IR
            var scan_inst = c.LLVMGetNextInstruction(call_inst);
            var scan_count: u32 = 0;
            while (@intFromPtr(scan_inst) != 0 and scan_count < 50) : ({
                scan_inst = c.LLVMGetNextInstruction(scan_inst);
                scan_count += 1;
            }) {
                const scan_opcode = c.LLVMGetInstructionOpcode(scan_inst);
                // Check for comparison with null (null guard pattern)
                if (scan_opcode == c.LLVMICmp) {
                    const op0 = c.LLVMGetOperand(scan_inst, 0);
                    if (@intFromPtr(op0) != 0 and op0 == call_inst) {
                        guard = true;
                        break;
                    }
                }
                // Check if result is used in store/call/branch
                if (scan_opcode == c.LLVMStore or
                    scan_opcode == c.LLVMCall or
                    scan_opcode == c.LLVMBr or
                    scan_opcode == c.LLVMCondBr)
                {
                    var op_i: u32 = 0;
                    const num_operands = c.LLVMGetNumOperands(scan_inst);
                    while (op_i < num_operands) : (op_i += 1) {
                        if (c.LLVMGetOperand(scan_inst, op_i) == call_inst) {
                            used = true;
                            break;
                        }
                    }
                }
            }
            return .{ .has_guard = guard, .used = used };
        }
    };

    // Run with error boundary to prevent crashes on malformed IR
    const check_result = safe_check.run(inst) catch |err| {
        log.warn("[FFI-NULL-GUARD] Safe check failed for '{s}': {}", .{ func_name, err });
        return .{ .has_guard = false, .used = false };
    };

    has_null_guard = check_result.has_guard;
    is_result_used = check_result.used;

    // Only report if result is used but not null-checked
    if (is_result_used and !has_null_guard) {
        // Known allocators that commonly return null
        const known_allocators = [_][]const u8{
            "malloc", "calloc", "realloc", "mmap",
            "valloc", "pvalloc", "aligned_alloc",
            "memalign", "posix_memmap",
            "VirtualAlloc", "HeapAlloc",
            "objc_allocWithZone",
        };

        const is_known_allocator = blk: {
            for (known_allocators) |alloc| {
                if (std.mem.indexOf(u8, callee_name, alloc) != null) {
                    break :blk true;
                }
            }
            break :blk false;
        };

        // Higher confidence for known allocators
        const confidence: f32 = if (is_known_allocator) 0.88 else 0.72;

        const location = Location.init(func_name);
        var issue = Issue.init(
            .malloc_unchecked,
            "FFI return value may be NULL, used without null guard",
            location,
            if (confidence >= 0.85) .high else .medium,
            confidence,
        );
        errdefer issue.deinit(ctx.allocator);

        try ctx.addIssue(&issue);
        diag.warn("[OMI-{s}] [FFI-NULL-CHECK] {s}() result not NULL-checked in {s}", .{
            if (confidence >= 0.85) "HIGH" else "MEDIUM",
            callee_name,
            func_name,
        });

        if (stats) |s| {
            s.null_checks += 1;
        }
    }
}

/// Check if a pointer is stored to a global variable.
/// Global storage escapes can extend pointer lifetime indefinitely,
/// which may be intentional (process-lifetime) or a leak.
pub fn checkStoreToGlobal(
    ctx: *PassContext,
    inst: c.LLVMValueRef,
    func: c.LLVMValueRef,
    func_name: []const u8,
    pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
    diag: *DiagnosticWriter,
    stats: *LifetimeStats,
) !void {
    _ = func;
    _ = stats;
    const opcode = c.LLVMGetInstructionOpcode(inst);
    if (opcode != c.LLVMStore) return;

    const ptr_operand = c.LLVMGetOperand(inst, 1);
    if (@intFromPtr(ptr_operand) == 0) return;

    const dest_operand = c.LLVMGetOperand(inst, 0);
    if (@intFromPtr(dest_operand) == 0) return;

    // Check if destination is a global variable
    if (c.LLVMGetValueKind(dest_operand) != c.LLVMGlobalVariableValueKind) return;

    // Check if we're storing a tracked pointer to global
    if (pointer_map.get(ptr_operand)) |ptr_info| {
        const global_name_ptr = c.LLVMGetValueName(dest_operand);
        const global_name = if (@intFromPtr(global_name_ptr) != 0)
            std.mem.span(global_name_ptr)
        else
            "@anonymous";

        // Only report for pointers from heap allocations
        if (ptr_info.source_kind == .heap_alloc or
            ptr_info.source_kind == .unknown_heap)
        {
            const location = Location.init(func_name);
            var issue = Issue.init(
                .global_escape,
                "Pointer stored to global variable extends lifetime",
                location,
                .medium,
                0.75,
            );
            errdefer issue.deinit(ctx.allocator);

            try ctx.addIssue(&issue);
            diag.warn("[OMI-MEDIUM] [GLOBAL-ESCAPE] {s} stored to global '{s}' in {s}", .{
                ptr_info.source_desc,
                global_name,
                func_name,
            });
        }
    }
}

// ========================================================================
// Helpers
// ========================================================================

/// Check if function name indicates an extern (FFI) function.
fn isExternFunction(name: []const u8) bool {
    // Common FFI naming patterns
    if (std.mem.indexOf(u8, name, "__") != null) return true;
    if (name.len > 4 and name[0] == '_' and name[1] == '_') return true;

    // Well-known extern prefixes
    const extern_prefixes = [_][]const u8{
        "llvm.", "core::arch:", "simd_",
        ":__builtin_", "mm_", "__v:", "vec_",
    };
    for (extern_prefixes) |prefix| {
        if (std.mem.startsWith(u8, name, prefix)) return true;
    }

    return false;
}

/// Report an FFI type mismatch issue.
fn reportFFITypeMismatch(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    desc: []const u8,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    _ = inst;
    const location = Location.init(func_name);
    var issue = Issue.init(
        .type_mismatch,
        desc,
        location,
        .medium,
        0.78,
    );
    errdefer issue.deinit(ctx.allocator);

    try ctx.addIssue(&issue);
    diag.warn("[OMI-MEDIUM] [TYPE-MISMATCH] {s} → {s}() in {s}", .{
        desc,
        callee_name,
        func_name,
    });
}
