//! C++ False Positive Reduction — Helper Functions
//!
//! Extracted from cpp_fp_reduction.zig to reduce file size.
//! Contains L1-L8 filter functions, RAII/Singleton/RC detection helpers.

const std = @import("std");
const log = @import("../../../common/log.zig");
const c = @import("../../../ir/llvm_raw.zig").c;
const PassContext = @import("../../pass.zig").PassContext;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;
const Issue = @import("../../../diag/issue.zig").Issue;
const Location = @import("../../../diag/issue.zig").Location;
const Confidence = @import("../../../diag/issue.zig").Confidence;
const ownership_types = @import("../../../types/ownership_types.zig");
const AllocSite = ownership_types.AllocSite;
const ValueIdMap = @import("../../../dataflow/value_id_map.zig").ValueIdMap;
const cpp_types = @import("../../../types/cpp_fp_types.zig");

/// Check if a function is an internal STL/libc++ template expansion.
pub fn isStlInternalFunction(func_name: []const u8) bool {
    return @import("../ffi/ffi_utils.zig").isStlInternalFunction(func_name);
}

/// Check if a function is a C++ special member function.
pub fn isCppSpecialMemberFunction(func_name: []const u8) bool {
    const special_suffixes = [_][]const u8{
        "C1Ev",     "C2Ev",    "C1EOS1_", "C2EOS1_", "C1ERKS1_", "C2ERKS1_",
        "D0Ev",     "D1Ev",    "D2Ev",    "D0EOS1_", "D1EOS1_",  "D2EOS1_",
        "aSERKS1_", "aSEOS1_",
    };
    for (special_suffixes) |suffix| {
        if (std.mem.indexOf(u8, func_name, suffix) != null) {
            return true;
        }
    }
    return false;
}

/// P18-FP3: Factory/constructor function pattern detection.
/// Functions whose names indicate they allocate and RETURN ownership to the caller.
/// Examples: XXH32_createState, sqlite3_open, malloc_wrapper, make_object.
/// These functions intentionally don't free — the caller must do it.
pub fn isFactoryFunction(func_name: []const u8) bool {
    return @import("../../../common/factory_patterns.zig").isFactoryFunction(func_name);
}

/// Check if a function is Rust's drop_in_place (destructor glue).
pub fn isRustDropGlue(func_name: []const u8) bool {
    return @import("../ffi/ffi_utils.zig").isRustDropGlue(func_name);
}

/// Check if a value name suggests it's a local Rust String/Vec/slice.
pub fn isLocalRustValue(value_name: []const u8) bool {
    const local_patterns = [_][]const u8{
        ".0",   ".1",   ".2",
        "_",    "self", "temp",
        "buf",  "str",  "slice",
        "data",
    };
    for (local_patterns) |pattern| {
        if (std.mem.indexOf(u8, value_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if a callee name represents a C++ new/new[] allocation.
pub fn isCppNewAllocation(callee: []const u8) bool {
    if (std.mem.indexOf(u8, callee, "_Znwm") != null) return true;
    if (std.mem.indexOf(u8, callee, "_Znam") != null) return true;
    if (std.mem.indexOf(u8, callee, "_Znw") != null) return true;
    if (std.mem.indexOf(u8, callee, "_Zna") != null) return true;
    if (std.mem.indexOf(u8, callee, "operator new") != null) return true;
    return false;
}

/// Check if a function is a C++ ABI internal function.
pub fn isCppAbiInternalFunction(func_name: []const u8) bool {
    return @import("../ffi/ffi_utils.zig").isCppAbiInternalFunction(func_name);
}

/// Check if an allocation is part of a Meyers singleton pattern.
pub fn isMeyersSingletonPattern(func_name: []const u8) bool {
    if (std.mem.indexOf(u8, func_name, "__cxa_guard_acquire") != null) return true;
    if (std.mem.indexOf(u8, func_name, "__cxa_guard_release") != null) return true;
    if (std.mem.indexOf(u8, func_name, "__cxa_atexit") != null) return true;
    return false;
}

/// Check if a function name matches known intentional test patterns.
pub fn is_likely_intentional_pattern(func_name: []const u8) bool {
    if (std.mem.eql(u8, func_name, "main")) return true;
    const intentional_prefixes = [_][]const u8{
        "correct_", "valid_", "example_", "good_",
        "proper_",  "fixed_", "ok_",
    };
    for (intentional_prefixes) |prefix| {
        if (std.mem.indexOf(u8, func_name, prefix) != null) return true;
    }
    return false;
}

/// C++ internal leak gate patterns — STL/runtime/compiler-generated functions
/// that allocate memory internally but manage it without user intervention.
/// These are NOT real leaks and should be suppressed for C++ modules.
const cpp_internal_leak_patterns = [_][]const u8{
    "_ZNSt", // std::* (libc++/libstdc++ mangled)
    "_ZSt", // STL helper functions (std::move, std::forward, etc.)
    "_ZNKSt", // const std::* methods
    "__cxx_", // C++ runtime internals
    "__gxx", // G++ runtime internals
};

/// Check if an allocation site function name matches C++ internal patterns.
/// Used by the C++ Internal Leak Gate to suppress FP reports from
/// STL template expansions and compiler-generated code in C++ modules.
///
/// Patterns matched:
///   - `_ZNSt*`  — libc++/libstdc++ std::* mangled symbols
///   - `_ZSt*`   — STL algorithm/helper functions
///   - `_ZNKSt*` — const member methods on std types
///   - `__cxx_*` — C++ ABI runtime functions
///   - `__gxx*`  — GNU C++ runtime functions
///
/// Returns true if the function should be suppressed by the gate.
pub fn isCppInternalLeakPattern(func_name: []const u8) bool {
    for (cpp_internal_leak_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if a callee name is an allocation by name.
pub fn isAllocationByName(callee_name: []const u8) bool {
    return std.mem.indexOf(u8, callee_name, "_Znwm") != null or
        std.mem.indexOf(u8, callee_name, "_Znam") != null;
}

/// Check if a function is a known reference-counted container function.
pub fn isKnownRcContainerFunction(func_name: []const u8) bool {
    const rc_class_patterns = [_][]const u8{
        "4Cord",             "7CordRep",      "10CordRepBtree",    "11CordRepRing",
        "12CordRepExternal", "13CordRepFlat", "14SubstringHolder", "16RefcountAndFlags",
        "RefCounted",        "RefPtr",        "shared_count",      "weak_count",
        "sqlite3_value",     "sqlite3_str",   "VdbeCursor",        "BtCursor",
        "sqlite3Btree",      "Schema",        "sqlite3_table",     "sqlite3_index",
        "sqlite3_trigger",   "sqlite3_view",  "sqlite3_expr",
    };
    for (rc_class_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a function is a reference count operation.
pub fn isRefCountOperation(func_name: []const u8) bool {
    const rc_patterns = [_][]const u8{
        "CordRep3Ref",       "CordRep5Unref",     "RefcountAndFlags",
        "AddRef",            "Release",           "Retain",
        "ref_count",         "RefCount",          "Unref",
        "decrement",         "increment",         "sqlite3ValueRef",
        "sqlite3BtreeEnter", "sqlite3BtreeLeave",
    };
    for (rc_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }
    return false;
}

/// Check if a function call is Rust's as_ptr() on a local value.
pub fn isRustAsPtrCall(name: []const u8) bool {
    const as_ptr_patterns = [_][]const u8{
        "as_ptr",
        "slice_as_ptr",
    };
    for (as_ptr_patterns) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) return true;
    }
    return false;
}

/// Extract function name from LLVM value reference.
pub fn getFunctionName(func: c.LLVMValueRef) []const u8 {
    return @import("../../../ir/ir_helpers.zig").getFunctionName(func);
}

/// Mark a function as reference-counted.
pub fn markAsRcFunction(func: c.LLVMValueRef, rc_set: *std.AutoHashMap(usize, void)) void {
    const func_name_raw = c.LLVMGetValueName(func);
    if (@intFromPtr(func_name_raw) != 0) {
        const func_ptr = @intFromPtr(func_name_raw);
        rc_set.put(func_ptr, {}) catch {
            log.warn("RC-WARN: failed to track RC container function (OOM?)\n", .{});
        };
    }
}
///
///
/// fe_oa_e8d71d8a8deb220da95dbfeb3ed037de05d3a3f720c0102d
/// Detect RAII-managed allocations (L3/L4).
pub fn detectRaiiManagedAllocations(
    func: c.LLVMValueRef,
    alloc_map: *std.AutoHashMap(u32, *AllocSite),
    id_map: *ValueIdMap,
    raii_stats: *u32,
    raii_func_set: *std.AutoHashMap(usize, void),
) void {
    const raii_constructor_prefixes = [_][]const u8{
        "_ZNSt3__110unique_ptr",
        "_ZNSt3__110shared_ptr",
        "_ZNSt10unique_ptr",
        "_ZNSt10shared_ptr",
    };
    var func_has_raii = false;

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

            const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
            if (num_operands == 0) continue;
            const callee = c.LLVMGetOperand(inst, num_operands - 1);
            if (@intFromPtr(callee) == 0) continue;
            const callee_name = c.LLVMGetValueName(callee);
            if (@intFromPtr(callee_name) == 0) continue;
            const name_slice = std.mem.sliceTo(callee_name, 0);

            var is_raii_ctor = false;
            for (raii_constructor_prefixes) |prefix| {
                if (std.mem.indexOf(u8, name_slice, prefix) != null) {
                    is_raii_ctor = true;
                    break;
                }
            }
            if (!is_raii_ctor) continue;

            func_has_raii = true;

            var i: c_uint = 0;
            while (i < num_operands - 1) : (i += 1) {
                const operand = c.LLVMGetOperand(inst, i);
                if (@intFromPtr(operand) == 0) continue;
                const op_id = id_map.getId(@intFromPtr(operand)) orelse continue;
                if (alloc_map.get(op_id)) |alloc_info| {
                    alloc_info.transferred = true;
                    raii_stats.* += 1;
                }
            }
        }
    }

    if (func_has_raii) {
        const func_name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_raw) != 0) {
            const func_ptr = @intFromPtr(func_name_raw);
            raii_func_set.put(func_ptr, {}) catch {
                log.warn("RAII-WARN: failed to track RAII function (OOM?)\n", .{});
            };
        }
    }
}

/// Detect Meyers singleton initialization pattern (L6).
pub fn detectMeyersSingletonFunctions(
    func: c.LLVMValueRef,
    meyers_set: *std.AutoHashMap(usize, void),
) void {
    var has_guard_acquire = false;

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

            const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
            if (num_operands == 0) continue;
            const callee = c.LLVMGetOperand(inst, num_operands - 1);
            if (@intFromPtr(callee) == 0) continue;
            const callee_name = c.LLVMGetValueName(callee);
            if (@intFromPtr(callee_name) == 0) continue;
            const name_slice = std.mem.sliceTo(callee_name, 0);

            if (std.mem.indexOf(u8, name_slice, "__cxa_guard_acquire") != null) {
                has_guard_acquire = true;
                break;
            }
        }
        if (has_guard_acquire) break;
    }

    if (has_guard_acquire) {
        const func_name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_raw) != 0) {
            const func_ptr = @intFromPtr(func_name_raw);
            meyers_set.put(func_ptr, {}) catch {
                log.warn("MEYERS-WARN: failed to track Meyers function (OOM?)\n", .{});
            };
        }
    }
}

/// Detect reference-counted container pattern (L8).
pub fn detectRefCountedContainerFunctions(
    func: c.LLVMValueRef,
    rc_set: *std.AutoHashMap(usize, void),
    is_alloc_fn: *const fn ([]const u8) bool,
) void {
    var has_rc_operation = false;
    var has_allocation = false;

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);

            if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
                const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
                if (num_operands == 0) continue;
                const callee = c.LLVMGetOperand(inst, num_operands - 1);
                if (@intFromPtr(callee) == 0) continue;
                const callee_name = c.LLVMGetValueName(callee);
                if (@intFromPtr(callee_name) == 0) continue;
                const name_slice = std.mem.sliceTo(callee_name, 0);

                if (isRefCountOperation(name_slice)) {
                    has_rc_operation = true;
                }
                if (is_alloc_fn(name_slice)) {
                    has_allocation = true;
                }
            }
        }
        if (has_rc_operation) break;
    }

    if (has_rc_operation) {
        markAsRcFunction(func, rc_set);
        return;
    }

    if (has_allocation) {
        const func_name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_raw) != 0) {
            const func_name_slice = std.mem.sliceTo(func_name_raw, 0);
            if (isKnownRcContainerFunction(func_name_slice)) {
                markAsRcFunction(func, rc_set);
            }
        }
    }
}

/// Detect as_ptr borrow escape patterns.
pub fn detectAsPtrBorrowEscape(
    ctx: *PassContext,
    func: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) void {
    var reported = std.AutoHashMap(usize, void).init(ctx.allocator);
    defer reported.deinit();

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

            const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
            if (num_operands < 2) continue;

            const callee = c.LLVMGetOperand(inst, num_operands - 1);
            if (@intFromPtr(callee) == 0) continue;
            const callee_name = c.LLVMGetValueName(callee);
            if (@intFromPtr(callee_name) == 0) continue;
            const name_slice = std.mem.sliceTo(callee_name, 0);

            if (!cpp_types.isRustAsPtrCall(name_slice)) continue;

            var i: c_uint = 0;
            while (i < num_operands - 1) : (i += 1) {
                const arg = c.LLVMGetOperand(inst, i);
                if (@intFromPtr(arg) == 0) continue;

                const arg_name = c.LLVMGetValueName(arg);
                if (@intFromPtr(arg_name) == 0) continue;
                const arg_slice = std.mem.span(arg_name);

                const is_local_rust = isLocalRustValue(arg_slice);
                if (!is_local_rust) continue;

                const func_key = @intFromPtr(c.LLVMGetValueName(func));
                if (reported.contains(func_key)) continue;

                const vuln_id = ctx.getNextVulnId();
                const func_name = getFunctionName(func);
                ctx.addIssue(&Issue.initWithReason(
                    .borrow_escape,
                    "Potential as_ptr borrow escape: local Rust value pointer passed to FFI",
                    Location.init(func_name),
                    .high,
                    0.8,
                    "as_ptr() on local String/Vec passed to extern C - pointer may dangle after drop",
                )) catch {
                    diag.warn("Failed to register as_ptr escape issue", .{});
                };
                log.warn("VULNERABILITY OMI-{d:0>3} [{s}] [Confidence: {s}]", .{ vuln_id, @tagName(.high), @tagName(Confidence.fromScore(0.8)) });
                log.warn("Type: borrow_escape", .{});
                log.warn("Reason: as_ptr() on local value passed to FFI - may dangle", .{});

                reported.put(func_key, {}) catch {};
            }
        }
    }
}

// ============================================================================
// Tests — T1.4 C++ Internal Leak Gate
// ============================================================================

test "isCppInternalLeakPattern - _ZNSt (std::vector)" {
    try std.testing.expect(isCppInternalLeakPattern("_ZNSt6vectorC2Ev"));
}

test "isCppInternalLeakPattern - _ZSt (STL helper)" {
    try std.testing.expect(isCppInternalLeakPattern("_ZSt4moveIRSt6stringEONSt16remove_referenceIT_E4typeEOS3_"));
}

test "isCppInternalLeakPattern - _ZNKSt (const std method)" {
    try std.testing.expect(isCppInternalLeakPattern("_ZNKSt6vectorIiSaIiEE4sizeEv"));
}

test "isCppInternalLeakPattern - __cxx_ (C++ runtime)" {
    try std.testing.expect(isCppInternalLeakPattern("__cxx_global_var_init"));
}

test "isCppInternalLeakPattern - __gxx (G++ runtime)" {
    try std.testing.expect(isCppInternalLeakPattern("__gxx_personality_v0"));
}

test "isCppInternalLeakPattern - user code NOT matched" {
    try std.testing.expect(!isCppInternalLeakPattern("my_cpp_function"));
    try std.testing.expect(!isCppInternalLeakPattern("malloc"));
    try std.testing.expect(!isCppInternalLeakPattern("sqlite3Malloc"));
    try std.testing.expect(!isCppInternalLeakPattern("_Z8myFuncv"));
}
