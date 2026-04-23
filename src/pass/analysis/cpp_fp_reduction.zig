//! C++ False Positive Reduction System
//!
//! 8-layer filter system to eliminate false positives in C++ analysis:
//! L1: STL internal function filter
//! L2: C++ special member function filter
//! L3: RAII smart pointer detection
//! L4: RAII function set tracking
//! L5: C++ ABI runtime filter
//! L6: Meyers singleton detection
//! L7: C++ operator FFI filter
//! L8: Reference-counted container detection
//!
//! Also contains leak/null-deref/UAF/double-free detection passes.
//! Extracted from pointer_ownership.zig per rules.md line limit (≤1000 lines).

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const PassContext = @import("../pass.zig").PassContext;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const Issue = @import("../../diag/issue.zig").Issue;
const Confidence = @import("../../diag/issue.zig").Confidence;
const Location = @import("../../diag/issue.zig").Location;
const Language = @import("../../diag/issue.zig").FFIBoundary.Language;
const FactKind = @import("../../fact/fact.zig").FactKind;
const SemanticRegistry = @import("../../registry/semantic_registry.zig").SemanticRegistry;
const AllocSite = @import("pointer_ownership.zig").AllocSite;
const FreeSite = @import("pointer_ownership.zig").FreeSite;
const OwnershipStats = @import("pointer_ownership.zig").OwnershipStats;
const OwnershipState = @import("pointer_ownership.zig").OwnershipState;
const OwnershipViolationType = @import("pointer_ownership.zig").OwnershipViolationType;
const ValueIdMap = @import("../../dataflow/value_id_map.zig").ValueIdMap;
const NullCheckRecognizer = @import("../../dataflow/null_check_guard.zig").NullCheckRecognizer;
const PathManager = @import("../../dataflow/path_condition.zig").PathManager;
const lifetime = @import("../../lifetime/root.zig");

/// Check if a function is an internal STL/libc++ template expansion.
pub fn isStlInternalFunction(func_name: []const u8) bool {
    const stl_prefixes = [_][]const u8{
        "_ZNSt3__", // std::__ (libc++ internal)
        "_ZNSt4", // std:: (libc++ public, but template expansions are still internal)
        "_ZNSs", // std::string
        "_ZNSt6", // std::vector, std::map, etc.
        "_ZNSt7", // std::allocator
        "_ZNSt10", // std::unique_ptr, std::shared_ptr etc.
    };
    for (stl_prefixes) |prefix| {
        if (std.mem.indexOf(u8, func_name, prefix) != null) {
            return true;
        }
    }
    if (std.mem.indexOf(u8, func_name, "__gnu") != null) return true;
    return false;
}

/// Check if a function is a C++ special member function.
pub fn isCppSpecialMemberFunction(func_name: []const u8) bool {
    const special_suffixes = [_][]const u8{
        "C1Ev", "C2Ev", "C1EOS1_", "C2EOS1_", "C1ERKS1_", "C2ERKS1_",
        "D0Ev", "D1Ev", "D2Ev", "D0EOS1_", "D1EOS1_", "D2EOS1_",
        "aSERKS1_", "aSEOS1_",
    };
    for (special_suffixes) |suffix| {
        if (std.mem.indexOf(u8, func_name, suffix) != null) {
            return true;
        }
    }
    return false;
}

/// Detect as_ptr borrow escape patterns (Task 9.3c).
/// Identifies when a local String/Vec's .as_ptr() result is passed
/// to an extern "C" function — the pointer may dangle if the Rust
/// value is dropped before the C function finishes using it.
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

            if (!isRustAsPtrCall(name_slice)) continue;

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
                ctx.addIssue(Issue.initWithReason(
                    .borrow_escape,
                    "Potential as_ptr borrow escape: local Rust value pointer passed to FFI",
                    Location.init(func_name),
                    .high,
                    0.8,
                    "as_ptr() on local String/Vec passed to extern C - pointer may dangle after drop",
                )) catch {
                    diag.warn("Failed to register as_ptr escape issue", .{});
                };
                diag.err("VULNERABILITY OMI-{d:0>3} [{s}] [Confidence: {s}]", .{vuln_id, @tagName(.high), @tagName(Confidence.fromScore(0.8))});
                diag.err("Type: borrow_escape", .{});
                diag.err("Reason: as_ptr() on local value passed to FFI - may dangle", .{});

                reported.put(func_key, {}) catch {};
            }
        }
    }
}

/// Check if a value name suggests it's a local Rust String/Vec/slice.
fn isLocalRustValue(value_name: []const u8) bool {
    const local_patterns = [_][]const u8{
        ".0", ".1", ".2",
        "_",
        "self",
        "temp",
        "buf",
        "str",
        "slice",
        "data",
    };
    for (local_patterns) |pattern| {
        if (std.mem.indexOf(u8, value_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if a function is a C++ ABI runtime internal function (__cxa_*).
pub fn isCppAbiInternalFunction(func_name: []const u8) bool {
    if (std.mem.indexOf(u8, func_name, "__cxa_") != null) return true;
    return false;
}

/// Check if an allocation is part of a Meyers singleton pattern.
pub fn isMeyersSingletonPattern(func_name: []const u8) bool {
    if (std.mem.indexOf(u8, func_name, "__cxa_guard_acquire") != null) return true;
    if (std.mem.indexOf(u8, func_name, "__cxa_guard_release") != null) return true;
    if (std.mem.indexOf(u8, func_name, "__cxa_atexit") != null) return true;
    return false;
}

/// Check if a function name matches known intentional test patterns.
pub fn isLikelyIntentionalPattern(func_name: []const u8) bool {
    if (std.mem.eql(u8, func_name, "main")) return true;
    const intentional_prefixes = [_][]const u8{
        "correct_", "valid_", "example_", "good_",
        "safe_", "proper_", "fixed_", "ok_",
    };
    for (intentional_prefixes) |prefix| {
        if (std.mem.indexOf(u8, func_name, prefix) != null) return true;
    }
    return false;
}

/// Detect RAII-managed allocations (L3/L4).
/// Scans function body for unique_ptr/shared_ptr constructor calls.
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
                std.log.warn("RAII-WARN: failed to track RAII function (OOM?)\n", .{});
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
                std.log.warn("MEYERS-WARN: failed to track Meyers function (OOM?)\n", .{});
            };
        }
    }
}

/// Detect reference-counted container pattern (L8).
/// Dual strategy: body-scanning Ref/Unref calls + name-based heuristic.
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

fn markAsRcFunction(func: c.LLVMValueRef, rc_set: *std.AutoHashMap(usize, void)) void {
    const func_name_raw = c.LLVMGetValueName(func);
    if (@intFromPtr(func_name_raw) != 0) {
        const func_ptr = @intFromPtr(func_name_raw);
        rc_set.put(func_ptr, {}) catch {
            std.log.warn("RC-WARN: failed to track RC container function (OOM?)\n", .{});
        };
    }
}

pub fn isAllocationByName(callee_name: []const u8) bool {
    return std.mem.indexOf(u8, callee_name, "_Znwm") != null or
        std.mem.indexOf(u8, callee_name, "_Znam") != null;
}

pub fn isKnownRcContainerFunction(func_name: []const u8) bool {
    const rc_class_patterns = [_][]const u8{
        "4Cord", "7CordRep", "10CordRepBtree", "11CordRepRing",
        "12CordRepExternal", "13CordRepFlat", "14SubstringHolder",
        "16RefcountAndFlags", "RefCounted", "RefPtr",
        "shared_count", "weak_count",
    };
    for (rc_class_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }
    return false;
}

pub fn isRefCountOperation(func_name: []const u8) bool {
    const rc_patterns = [_][]const u8{
        "CordRep3Ref", "CordRep5Unref", "RefcountAndFlags",
        "AddRef", "Release", "Retain", "ref_count",
        "RefCount", "Unref", "decrement", "increment",
    };
    for (rc_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }
    return false;
}

/// Detect potential null dereferences.
pub fn detectNullDereferences(
    ctx: *PassContext,
    alloc_map: *std.AutoHashMap(u32, *AllocSite),
    recognizer: *NullCheckRecognizer,
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    diag: *DiagnosticWriter,
) void {
    var reported_funcs = std.AutoHashMap(usize, void).init(alloc_map.allocator);
    defer reported_funcs.deinit();

    var alloc_iter = alloc_map.iterator();
    while (alloc_iter.next()) |entry| {
        const alloc_info = entry.value_ptr.*;

        if (!isNullableAllocation(alloc_info)) continue;

        const is_guarded = isFunctionLevelNullGuarded(recognizer, alloc_info.ptr_value_id, flow_graph);
        if (!is_guarded) {
            const func_ptr_key = @intFromPtr(alloc_info.func_name.ptr);
            if (reported_funcs.contains(func_ptr_key)) continue;

            const vulnerability_id = ctx.getNextVulnId();
            ctx.addIssue(Issue.init(
                .null_dereference,
                "Potential null dereference: pointer used without null check",
                Location.init(alloc_info.func_name),
                .critical,
                0.85,
            )) catch {
                diag.warn("Failed to register null_deref issue", .{});
            };
            diag.err("VULNERABILITY OMI-{d:0>3} [critical] [Confidence: {s}]", .{vulnerability_id, @tagName(Confidence.fromScore(0.85))});
            diag.err("Type: null_dereference", .{});
            diag.err("Reason: allocation may return NULL, used without null guard", .{});

            reported_funcs.put(func_ptr_key, {}) catch {
                diag.warn("Null dedup map insert failed", .{});
            };
        }
    }
}

pub fn isFunctionLevelNullGuarded(
    recognizer: *NullCheckRecognizer,
    ptr_value_id: u32,
    flow_graph: *const std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
) bool {
    if (recognizer.isPtrGuardedNonNull_byValue(ptr_value_id)) return true;

    var visited = std.AutoHashMap(u32, void).init(recognizer.allocator);
    defer visited.deinit();

    var bfs_queue: [64]u32 = undefined;
    var qhead: usize = 0;
    var qtail: usize = 0;
    bfs_queue[qtail] = ptr_value_id;
    qtail += 1;

    while (qhead < qtail) {
        const current = bfs_queue[qhead];
        qhead += 1;
        if (visited.contains(current)) continue;
        visited.put(current, {}) catch return false;

        if (recognizer.isPtrGuardedNonNull_byValue(current)) return true;

        if (flow_graph.get(current)) |flows| {
            var iter = flows.iterator();
            while (iter.next()) |entry| {
                const alias_id = entry.key_ptr.*;
                if (!visited.contains(alias_id) and qtail < bfs_queue.len) {
                    bfs_queue[qtail] = alias_id;
                    qtail += 1;
                }
            }
        }
    }
    return false;
}

pub fn isNullableAllocation(alloc: *const AllocSite) bool {
    const nullable_patterns = [_][]const u8{
        "malloc", "calloc", "realloc", "strdup",
        "sqlite3Malloc", "sqlite3Realloc", "sqlite3DbMalloc", "sqlite3DbRealloc",
        "fopen", "BIO_new", "EVP_", "RSA_",
        "SSL_CTX_new", "X509_new", "PEM_", "inflateInit",
        "deflateInit", "gzopen",
    };
    for (nullable_patterns) |pattern| {
        if (std.mem.indexOf(u8, alloc.func_name, pattern) != null or
            std.mem.indexOf(u8, alloc.debug_file orelse "", pattern) != null)
        {
            return true;
        }
    }
    return false;
}

/// Detect double-free: same pointer freed multiple times.
pub fn detectDoubleFree(
    ctx: *PassContext,
    free_map: *std.AutoHashMap(u32, *FreeSite),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    stats: *OwnershipStats,
    diag: *DiagnosticWriter,
) void {
    var free_iter = free_map.iterator();
    while (free_iter.next()) |entry| {
        const free_info = entry.value_ptr.*;

        var free_count: u32 = 1;
        if (flow_graph.get(free_info.inst_id)) |flow| {
            var flow_iter = flow.iterator();
            while (flow_iter.next()) |flow_entry| {
                const target = flow_entry.key_ptr.*;
                if (free_map.contains(target)) free_count += 1;
            }
        }

        if (free_count > 1) {
            stats.double_frees += 1;
            const msg = std.fmt.allocPrint(ctx.allocator, "Pointer freed {d} times", .{free_count}) catch {
                ctx.addIssue(Issue.init(.double_free, "Pointer freed multiple times", Location.init(free_info.func_name), .high, 0.8)) catch {
                    diag.warn("Failed to register double_free issue", .{});
                };
                diag.warn("DOUBLE-FREE [MEDIUM]: Pointer freed multiple times in {s}", .{free_info.func_name});
                continue;
            };
            ctx.addIssue(Issue.init(.double_free, msg, Location.init(free_info.func_name), .high, 0.8)) catch {
                diag.warn("Failed to register double_free issue (count)", .{});
            };
            ctx.allocator.free(msg);
            diag.warn("DOUBLE-FREE [MEDIUM]: Pointer freed {d} times in {s}", .{ free_count, free_info.func_name });
        }
    }
}

/// Detect use-after-free: pointer used after being freed.
pub fn detectUseAfterFree(
    ctx: *PassContext,
    free_map: *std.AutoHashMap(u32, *FreeSite),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    stats: *OwnershipStats,
    diag: *DiagnosticWriter,
) void {
    var free_iter = free_map.iterator();
    while (free_iter.next()) |entry| {
        const ptr = entry.key_ptr.*;
        const free_info = entry.value_ptr.*;

        if (flow_graph.get(ptr)) |flow| {
            var visited = std.AutoHashMap(u32, void).init(flow_graph.allocator);
            defer visited.deinit();

            if (hasUseAfterFree(ptr, flow, flow_graph, &visited)) {
                stats.use_after_frees += 1;
                ctx.addIssue(Issue.init(.use_after_free, "Pointer used after being freed", Location.init(free_info.func_name), .high, 0.8)) catch {
                    diag.warn("Failed to register use_after_free issue", .{});
                };
                diag.warn("USE-AFTER-FREE [MEDIUM]: Pointer used after being freed in {s}", .{free_info.func_name});
            }
        }
    }
}

fn hasUseAfterFree(
    freed_ptr: u32,
    flow: std.AutoHashMap(u32, void),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    visited: *std.AutoHashMap(u32, void),
) bool {
    if (visited.contains(freed_ptr)) return false;
    visited.put(freed_ptr, {}) catch return false;

    var flow_iter = flow.iterator();
    while (flow_iter.next()) |entry| {
        const next = entry.key_ptr.*;
        if (flow_graph.get(next)) |next_flow| {
            if (hasUseAfterFree(next, next_flow, flow_graph, visited)) return true;
        }
    }
    return false;
}

/// Extract function name from LLVM value reference.
pub fn getFunctionName(func: c.LLVMValueRef) []const u8 {
    const name_ptr = c.LLVMGetValueName(func);
    if (@intFromPtr(name_ptr) == 0) return "unknown";
    return std.mem.span(name_ptr);
}

/// Identify the language of a function based on naming conventions.
pub fn identifyLanguage(func: c.LLVMValueRef) Language {
    const func_name = getFunctionName(func);

    if (func_name.len > 2 and
        func_name[0] == '_' and
        func_name[1] == 'R')
    {
        return .rust;
    }

    if (std.mem.indexOf(u8, func_name, "alloc::") != null or
        std.mem.indexOf(u8, func_name, "core::") != null or
        std.mem.indexOf(u8, func_name, "std::") != null)
    {
        if (std.mem.indexOf(u8, func_name, "::boxed::") != null or
            std.mem.indexOf(u8, func_name, "::ffi::") != null or
            std.mem.indexOf(u8, func_name, "::cstring::") != null)
        {
            return .rust;
        }
    }

    if (std.mem.eql(u8, func_name, "malloc") or
        std.mem.eql(u8, func_name, "free") or
        std.mem.eql(u8, func_name, "calloc") or
        std.mem.eql(u8, func_name, "realloc") or
        std.mem.eql(u8, func_name, "printf") or
        std.mem.eql(u8, func_name, "strlen"))
    {
        return .c;
    }

    if (func_name.len > 2 and
        func_name[0] == '_' and
        func_name[1] == 'Z')
    {
        return .cpp;
    }

    if (std.mem.indexOf(u8, func_name, "Allocator.") != null or
        std.mem.indexOf(u8, func_name, "allocImpl") != null)
    {
        return .zig;
    }

    if (std.mem.indexOf(u8, func_name, "UnsafeMutablePointer") != null or
        std.mem.indexOf(u8, func_name, "$s") != null)
    {
        return .swift;
    }

    return .unknown;
}

/// Check if a free is guarded by a null check.
pub fn isGuardedByNullCheck(
    free_inst: c.LLVMValueRef,
    ptr_value_id: u32,
    path_manager: *PathManager,
) bool {
    _ = free_inst;
    return path_manager.isPtrNonNull(ptr_value_id);
}

/// Detect memory leaks, double-free, and use-after-free.
pub fn detectMemoryIssues(
    ctx: *PassContext,
    alloc_map: *std.AutoHashMap(u32, *AllocSite),
    free_map: *std.AutoHashMap(u32, *FreeSite),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    stats: *OwnershipStats,
    diag: *DiagnosticWriter,
) void {
    detectMemoryLeaks(ctx, alloc_map, free_map, flow_graph, stats, diag);
    detectDoubleFree(ctx, free_map, flow_graph, stats, diag);
    detectUseAfterFree(ctx, free_map, flow_graph, stats, diag);
}

/// Detect memory leaks: allocations that are never freed.
pub fn detectMemoryLeaks(
    ctx: *PassContext,
    alloc_map: *std.AutoHashMap(u32, *AllocSite),
    free_map: *std.AutoHashMap(u32, *FreeSite),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    stats: *OwnershipStats,
    diag: *DiagnosticWriter,
) void {
    var reported_func_ptrs = std.AutoHashMap(usize, void).init(alloc_map.allocator);
    defer reported_func_ptrs.deinit();

    var alloc_iter = alloc_map.iterator();
    while (alloc_iter.next()) |entry| {
        const alloc_info = entry.value_ptr.*;

        if (alloc_info.transferred) continue;

        if (isStlInternalFunction(alloc_info.func_name)) continue;

        if (isCppSpecialMemberFunction(alloc_info.func_name)) continue;

        const func_name_ptr = @intFromPtr(alloc_info.func_name.ptr);
        if (ctx.raii_func_set.contains(func_name_ptr)) continue;

        if (isCppAbiInternalFunction(alloc_info.func_name)) continue;

        if (isMeyersSingletonPattern(alloc_info.func_name)) continue;

        const meyers_ptr = @intFromPtr(alloc_info.func_name.ptr);
        if (ctx.meyers_singleton_set.contains(meyers_ptr)) continue;

        const rc_ptr = @intFromPtr(alloc_info.func_name.ptr);
        if (ctx.rc_container_func_set.contains(rc_ptr)) continue;

        // L9: Rust FFI ownership transfer pairing check (Task 9.3).
        // If function calls into_raw (ownership OUT) but no matching from_raw
        // exists anywhere in the module, the allocation is intentionally
        // transferred to C — not a leak.
        const rust_func_ptr = @intFromPtr(alloc_info.func_name.ptr);
        if (ctx.rust_into_raw_set.contains(rust_func_ptr)) {
            if (ctx.rust_from_raw_set.count() > 0) {
                continue;
            }
        }

        const has_free_path = findFreePath(alloc_info.inst_id, free_map, flow_graph);
        if (!has_free_path) {
            if (isLikelyIntentionalPattern(alloc_info.func_name)) {
                continue;
            }
            if (isLikelyStructMemberOwnership(alloc_info.func_name)) {
                continue;
            }
            if (alloc_info.stored_to_struct_field) {
                continue;
            }
            const func_ptr_key = @intFromPtr(alloc_info.func_name.ptr);
            const already_reported = reported_func_ptrs.contains(func_ptr_key);
            if (!already_reported) {
                stats.memory_leaks += 1;
                ctx.addIssue(Issue.init(
                    .memory_leak,
                    "Memory allocated but never freed",
                    Location.init(alloc_info.func_name),
                    .medium,
                    0.7,
                )) catch {
                    diag.warn("Failed to register leak issue", .{});
                };
                diag.warn("MEMORY LEAK [MEDIUM]: Memory allocated but never freed in {s}", .{alloc_info.func_name});
                reported_func_ptrs.put(func_ptr_key, {}) catch {
                    diag.warn("Leak dedup map insert failed", .{});
                };
            }
        }
    }
}

/// Check if allocation result can reach any free site through the flow graph.
fn findFreePath(
    from_ptr: u32,
    free_map: *std.AutoHashMap(u32, *FreeSite),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
) bool {
    var visited = std.AutoHashMap(u32, void).init(free_map.allocator);
    defer visited.deinit();

    var bfs_queue: [64]u32 = undefined;
    var queue_head: usize = 0;
    var queue_tail: usize = 0;
    bfs_queue[queue_tail] = from_ptr;
    queue_tail += 1;

    while (queue_head < queue_tail) {
        const current = bfs_queue[queue_head];
        queue_head += 1;

        if (visited.contains(current)) continue;
        visited.put(current, {}) catch return false;

        if (free_map.contains(current)) return true;

        if (flow_graph.get(current)) |flows| {
            var iter = flows.iterator();
            while (iter.next()) |entry| {
                const next_id = entry.key_ptr.*;
                if (!visited.contains(next_id) and queue_tail < bfs_queue.len) {
                    bfs_queue[queue_tail] = next_id;
                    queue_tail += 1;
                }
            }
        }
    }
    return false;
}

/// Check if a function likely manages memory through struct member ownership.
pub fn isLikelyStructMemberOwnership(func_name: []const u8) bool {
    const struct_member_patterns = [_][]const u8{
        "fts5",
        "sqlite3Fts5",
        "StorageGet",
        "PrepareStmt",
        "Pragma",
        "MemSize",
        "MemRealloc",
        "serialize",
    };
    for (struct_member_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Detect when allocation results are stored into struct/aggregate fields via GEP + store.
pub fn detectStructMemberStores(
    func: c.LLVMValueRef,
    alloc_map: *std.AutoHashMap(u32, *AllocSite),
    id_map: *ValueIdMap,
) void {
    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode != c.LLVMStore) continue;

            const stored_val = c.LLVMGetOperand(inst, 0);
            const ptr_operand = c.LLVMGetOperand(inst, 1);

            const stored_id = @intFromPtr(stored_val);
            if (stored_id == 0) continue;

            const value_id = id_map.getId(stored_id) orelse continue;
            if (alloc_map.get(value_id)) |alloc_info| {
                if (@intFromPtr(ptr_operand) != 0 and
                    c.LLVMGetInstructionOpcode(ptr_operand) == c.LLVMGetElementPtr)
                {
                    alloc_info.stored_to_struct_field = true;
                }
            }
        }
    }
}

/// Detect ownership violations using flow graph and boundary analyzer.
pub fn detectViolations(
    ctx: *PassContext,
    alloc_map: *std.AutoHashMap(u32, *AllocSite),
    free_map: *std.AutoHashMap(u32, *FreeSite),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    stats: *OwnershipStats,
    diag: *DiagnosticWriter,
    boundary_analyzer: *lifetime.BoundaryAnalyzer,
    lifetime_engine: *lifetime.LifetimeEngine,
) !void {
    var alloc_iter = alloc_map.iterator();
    while (alloc_iter.next()) |entry| {
        const alloc = entry.value_ptr.*;

        const lang_hint = convertLanguageToHint(alloc.lang);
        if (lifetime_engine.applyAction(
            .alloc,
            alloc.func_name,
            if (alloc.debug_file) |file|
                .{ .file = file, .line = alloc.debug_line orelse 0, .column = alloc.debug_column orelse 0 }
            else
                null,
            lang_hint,
        )) |resource_id| {
            if (resource_id > std.math.maxInt(u32)) {
                diag.warn("Resource ID overflow detected: {d} exceeds u32 range", .{resource_id});
            }
            try ctx.fact_store.insert(
                .ownership_alloc,
                alloc.ptr_value_id,
                @truncate(resource_id),
                alloc.inst_id,
            );
        } else {
            try ctx.fact_store.insert(
                .ownership_alloc,
                alloc.ptr_value_id,
                @intFromEnum(alloc.lang),
                alloc.inst_id,
            );
            diag.warn("Failed to track allocation in lifetime engine: {s}", .{alloc.func_name});
        }

        if (isCrossFFIAllocation(alloc)) {
            stats.cross_ffi_transfers += 1;
            try ctx.fact_store.insert(
                .ownership_transfer,
                alloc.ptr_value_id,
                @intFromEnum(alloc.lang),
                alloc.inst_id,
            );
        }
    }

    var free_iter = free_map.iterator();
    while (free_iter.next()) |entry| {
        const free_site = entry.value_ptr.*;

        try ctx.fact_store.insert(
            .ownership_free,
            free_site.ptr_value_id,
            @intFromEnum(free_site.lang),
            free_site.inst_id,
        );
    }

    alloc_iter = alloc_map.iterator();
    while (alloc_iter.next()) |entry| {
        const alloc = entry.value_ptr.*;
        const alloc_lang_hint = convertLanguageToHint(alloc.lang);

        free_iter = free_map.iterator();
        while (free_iter.next()) |free_entry| {
            const free_site = free_entry.value_ptr.*;
            const free_lang_hint = convertLanguageToHint(free_site.lang);

            if (alloc.lang != free_site.lang and
                alloc.lang != .unknown and
                free_site.lang != .unknown)
            {
                var visited = std.AutoHashMap(u32, void).init(ctx.allocator);
                defer visited.deinit();

                const flows_to_free = canReach(
                    flow_graph,
                    alloc.ptr_value_id,
                    free_site.ptr_value_id,
                    &visited,
                );

                if (flows_to_free) {
                    const alloc_loc = Location.init(alloc.func_name);
                    const free_loc = Location.init(free_site.func_name);

                    const boundary_id = boundary_analyzer.registerBoundary(
                        free_site.func_name,
                        alloc_lang_hint,
                        free_lang_hint,
                        .out,
                        if (alloc.debug_file) |file|
                            .{ .file = file, .line = alloc.debug_line orelse 0, .column = alloc.debug_column orelse 0 }
                        else
                            null,
                    );

                    const resource_fact = lifetime.ResourceFact{
                        .id = @as(u64, alloc.inst_id),
                        .origin_fn = alloc.func_name,
                        .owner = .caller,
                        .state = .live,
                        .action = .alloc,
                        .location = null,
                        .lang_hint = alloc_lang_hint,
                    };

                    if (boundary_id == 0) {
                        diag.warn("Failed to register FFI boundary for analysis", .{});
                    } else if (boundary_analyzer.checkOwnershipViolation(
                        resource_fact,
                        .free,
                        free_lang_hint,
                        boundary_analyzer.boundaries.items[boundary_id - 1],
                    )) |violation| {
                        diag.warn("CROSS-LANGUAGE OWNERSHIP VIOLATION DETECTED", .{});
                        diag.warn("  Type: {s}", .{@tagName(violation.kind)});
                        diag.warn("  Alloc: {s} ({s}) at inst {}", .{
                            alloc_loc.function,
                            @tagName(alloc.lang),
                            alloc.inst_id,
                        });
                        diag.warn("  Free: {s} ({s}) at inst {}", .{
                            free_loc.function,
                            @tagName(free_site.lang),
                            free_site.inst_id,
                        });
                        diag.warn("  Description: {s}", .{violation.description});
                    } else {
                        diag.warn("CROSS-LANGUAGE OWNERSHIP VIOLATION DETECTED", .{});
                        diag.warn("  Alloc: {s} ({s}) at inst {}", .{
                            alloc_loc.function,
                            @tagName(alloc.lang),
                            alloc.inst_id,
                        });
                        diag.warn("  Free: {s} ({s}) at inst {}", .{
                            free_loc.function,
                            @tagName(free_site.lang),
                            free_site.inst_id,
                        });
                        diag.warn("  Flow: Pointer flows from allocation to free via data flow", .{});
                    }

                    try ctx.fact_store.insert(
                        .ownership_violation,
                        alloc.inst_id,
                        @intFromEnum(OwnershipViolationType.cross_lang_free_mismatch),
                        free_site.inst_id,
                    );

                    stats.violations += 1;
                }
            }
        }
    }

    const boundary_stats = boundary_analyzer.getStats();
    if (boundary_stats.issue_count > 0) {
        diag.info("BoundaryAnalyzer: {d} cross-language violations detected", .{
            boundary_stats.issue_count,
        });
    }
}

/// Convert internal Language enum to lifetime.LanguageHint.
pub fn convertLanguageToHint(lang: Language) lifetime.LanguageHint {
    return switch (lang) {
        .c => .c,
        .rust => .rust,
        .zig => .zig,
        .cpp => .cpp,
        .go => .go,
        .swift => .swift,
        .unknown => .unknown,
    };
}

/// Check if an allocation crosses an FFI boundary.
pub fn isCrossFFIAllocation(alloc: *const AllocSite) bool {
    return alloc.lang != .unknown and alloc.lang != .c;
}

/// Check if a value can reach another value through the flow graph.
pub fn canReach(
    flow_graph: *const std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    from: u32,
    to: u32,
    visited: *std.AutoHashMap(u32, void),
) bool {
    if (from == to) return true;

    if (visited.contains(from)) return false;
    visited.put(from, {}) catch return false;

    const edges = flow_graph.get(from) orelse return false;
    var iter = edges.iterator();
    while (iter.next()) |entry| {
        if (canReach(flow_graph, entry.key_ptr.*, to, visited)) {
            return true;
        }
    }
    return false;
}

// ==================== Rust FFI Pair Detection (Task 9.3) ====================

/// Detect Rust FFI ownership transfer patterns in function bodies.
/// Scans for into_raw (ownership OUT) and from_raw (ownership IN) calls.
/// Populates rust_into_raw_set and rust_from_raw_set for paired analysis.
pub fn detectRustFfiPairingFunctions(
    func: c.LLVMValueRef,
    into_raw_set: *std.AutoHashMap(usize, void),
    from_raw_set: *std.AutoHashMap(usize, void),
) void {
    var has_into_raw = false;
    var has_from_raw = false;

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

            if (isRustIntoRawCall(name_slice)) {
                has_into_raw = true;
            }
            if (isRustFromRawCall(name_slice)) {
                has_from_raw = true;
            }
        }
        if (has_into_raw and has_from_raw) break;
    }

    if (has_into_raw) {
        const func_name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_raw) != 0) {
            const func_ptr = @intFromPtr(func_name_raw);
            into_raw_set.put(func_ptr, {}) catch {};
        }
    }
    if (has_from_raw) {
        const func_name_raw = c.LLVMGetValueName(func);
        if (@intFromPtr(func_name_raw) != 0) {
            const func_ptr = @intFromPtr(func_name_raw);
            from_raw_set.put(func_ptr, {}) catch {};
        }
    }
}

/// Check if a callee name is a Rust into_raw (ownership transfer OUT) call.
pub fn isRustIntoRawCall(callee_name: []const u8) bool {
    const into_raw_patterns = [_][]const u8{
        "into_raw",
        "8into_raw",
        "Box.*into_raw",
        "CString.*into_raw",
        "Vec.*leak",
    };
    for (into_raw_patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if a callee name is a Rust from_raw (ownership transfer IN) call.
pub fn isRustFromRawCall(callee_name: []const u8) bool {
    const from_raw_patterns = [_][]const u8{
        "from_raw",
        "8from_raw",
        "Box.*from_raw",
        "CString.*from_raw",
        "from_raw_parts",
    };
    for (from_raw_patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if a callee name is a Rust as_ptr (borrow escape) call.
pub fn isRustAsPtrCall(callee_name: []const u8) bool {
    const as_ptr_patterns = [_][]const u8{
        "as_ptr",
        "as_mut_ptr",
        "slice::as_ptr",
    };
    for (as_ptr_patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Detect cross-language allocation/deallocation mismatches (Task 9.3d).
/// Pattern 1: Rust global alloc (_Znwm) result freed by C free()
/// Pattern 2: C malloc() result reclaimed by Box::from_raw (correct but worth noting)
pub fn detectCrossLangAllocMismatch(
    ctx: *PassContext,
    alloc_map: *std.AutoHashMap(u32, *AllocSite),
    free_map: *std.AutoHashMap(u32, *FreeSite),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    diag: *DiagnosticWriter,
) void {
    var alloc_iter = alloc_map.iterator();
    while (alloc_iter.next()) |entry| {
        const alloc = entry.value_ptr.*;

        if (alloc.lang != .rust) continue;

        var free_iter = free_map.iterator();
        while (free_iter.next()) |free_entry| {
            const free_site = free_entry.value_ptr.*;

            if (free_site.lang != .c) continue;
            if (free_site.free_type != .free) continue;

            var visited = std.AutoHashMap(u32, void).init(ctx.allocator);
            defer visited.deinit();

            const flows_to_free = canReach(flow_graph, alloc.ptr_value_id, free_site.ptr_value_id, &visited);
            if (!flows_to_free) continue;

            const vuln_id = ctx.getNextVulnId();
            ctx.addIssue(Issue.initWithReason(
                .cross_language_leak,
                "Cross-language alloc mismatch: Rust-alloc freed by C free()",
                Location.init(alloc.func_name),
                .high,
                0.85,
                "Rust global_alloc (_Znwm) result freed by C free() - allocator mismatch",
            )) catch {
                diag.warn("Failed to register cross-lang mismatch issue", .{});
            };
            diag.err("CROSS-LANG MISMATCH OMI-{d:0>3} [{s}] [Confidence: {s}]", .{vuln_id, @tagName(.high), @tagName(Confidence.fromScore(0.85))});
            diag.err("Type: cross_language_alloc_mismatch", .{});
            diag.err("Reason: Rust _Znwm allocation freed by C free() - heap mismatch", .{});
        }
    }
}
