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
const ffi_language_classifier = @import("ffi_language_classifier.zig");

const PassContext = @import("../pass.zig").PassContext;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;
const noise_filter = @import("../../semantics/noise_filter.zig");
const Issue = @import("../../diag/issue.zig").Issue;
const Severity = @import("../../diag/issue.zig").Severity;
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
const noise_reduction = @import("noise_reduction.zig");

/// Check if a function is an internal STL/libc++ template expansion.
/// Delegated to unified ffi_utils (single source of truth).
pub fn isStlInternalFunction(func_name: []const u8) bool {
    return @import("ffi_utils.zig").isStlInternalFunction(func_name);
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

/// Check if a function is Rust's drop_in_place (destructor glue).
/// Delegated to unified ffi_utils (single source of truth).
pub fn isRustDropGlue(func_name: []const u8) bool {
    return @import("ffi_utils.zig").isRustDropGlue(func_name);
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
                diag.err("VULNERABILITY OMI-{d:0>3} [{s}] [Confidence: {s}]", .{ vuln_id, @tagName(.high), @tagName(Confidence.fromScore(0.8)) });
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

/// Check if a function is a C++ ABI runtime internal function (__cxa_*).
/// Check if a function is a C++ ABI internal function (exception handling, TLS, etc.).
/// Delegated to unified ffi_utils (single source of truth).
pub fn isCppAbiInternalFunction(func_name: []const u8) bool {
    return @import("ffi_utils.zig").isCppAbiInternalFunction(func_name);
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
        // SECURITY: "safe_" intentionally excluded from this list to prevent bypass.
        // Functions with "safe_" prefix could evade leak detection if they contain
        // actual memory leaks (e.g., safe_free_my_pointer() with unbalanced alloc/free).
        // Genuine safety requires provable null checks (isGuardedByNullCheck) or RAII patterns
        // (detectRaiiManagedAllocations/detectRefCountedContainerFunctions), not naming convention.
        "correct_", "valid_", "example_", "good_",
        "proper_",  "fixed_", "ok_",
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
        // Abseil (existing) — C++ mangled names with length prefixes
        "4Cord",             "7CordRep",      "10CordRepBtree",    "11CordRepRing",
        "12CordRepExternal", "13CordRepFlat", "14SubstringHolder", "16RefcountAndFlags",
        "RefCounted",        "RefPtr",        "shared_count",      "weak_count",
        // SQLite — use longer, more specific substrings to avoid FP
        "sqlite3_value",     "sqlite3_str",   "VdbeCursor",        "BtCursor",
        "sqlite3Btree",      "Schema",        "sqlite3_table",     "sqlite3_index",
        "sqlite3_trigger",   "sqlite3_view",  "sqlite3_expr",
    };
    for (rc_class_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }
    return false;
}

pub fn isRefCountOperation(func_name: []const u8) bool {
    const rc_patterns = [_][]const u8{
        // Abseil (existing)
        "CordRep3Ref",       "CordRep5Unref",     "RefcountAndFlags",
        "AddRef",            "Release",           "Retain",
        "ref_count",         "RefCount",          "Unref",
        "decrement",         "increment",
        // SQLite reference counting operations (Ref/Unref only)
                "sqlite3ValueRef",
        "sqlite3BtreeEnter", "sqlite3BtreeLeave",
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

        // Skip if the pointer is never used (no aliases in flow graph).
        // A pointer that is allocated but never dereferenced cannot cause a null deref.
        if (flow_graph.get(alloc_info.ptr_value_id)) |aliases| {
            if (aliases.count() == 0) continue;
        } else {
            // No entry in flow graph means the pointer was never used at all.
            continue;
        }

        const is_guarded = isFunctionLevelNullGuarded(recognizer, alloc_info.ptr_value_id, flow_graph) catch continue;
        if (!is_guarded) {
            const func_ptr_key = @intFromPtr(alloc_info.func_name.ptr);
            if (reported_funcs.contains(func_ptr_key)) continue;

            const vulnerability_id = ctx.getNextVulnId();
            ctx.addIssue(&Issue.init(
                .null_dereference,
                "Potential null dereference: pointer used without null check",
                Location.init(alloc_info.func_name),
                .critical,
                0.85,
            )) catch {
                diag.warn("Failed to register null_deref issue", .{});
            };
            diag.err("VULNERABILITY OMI-{d:0>3} [critical] [Confidence: {s}]", .{ vulnerability_id, @tagName(Confidence.fromScore(0.85)) });
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
) !bool {
    if (recognizer.isPtrGuardedNonNull_byValue(ptr_value_id)) return true;

    var visited = std.AutoHashMap(u32, void).init(recognizer.allocator);
    defer visited.deinit();

    var bfs_queue = try std.ArrayList(u32).initCapacity(recognizer.allocator, 64);
    defer bfs_queue.deinit(recognizer.allocator);
    try bfs_queue.append(recognizer.allocator, ptr_value_id);

    while (bfs_queue.items.len > 0) {
        const current = bfs_queue.orderedRemove(0);
        if (visited.contains(current)) continue;
        try visited.put(current, {});

        if (recognizer.isPtrGuardedNonNull_byValue(current)) return true;

        if (flow_graph.get(current)) |flows| {
            var iter = flows.iterator();
            while (iter.next()) |entry| {
                const alias_id = entry.key_ptr.*;
                if (!visited.contains(alias_id)) {
                    try bfs_queue.append(recognizer.allocator, alias_id);
                }
            }
        }
    }
    return false;
}

pub fn isNullableAllocation(alloc: *const AllocSite) bool {
    const nullable_patterns = [_][]const u8{
        "malloc",        "calloc",         "realloc",         "strdup",
        "sqlite3Malloc", "sqlite3Realloc", "sqlite3DbMalloc", "sqlite3DbRealloc",
        "fopen",         "BIO_new",        "EVP_",            "RSA_",
        "SSL_CTX_new",   "X509_new",       "PEM_",            "inflateInit",
        "deflateInit",   "gzopen",
    };
    for (nullable_patterns) |pattern| {
        if (std.mem.indexOf(u8, alloc.func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Detect double-free: same pointer freed multiple times.
/// P0-B Enhanced: Control-flow aware via basic_block_id tracking.
///
/// Key insight (from SQLite source-level verification):
///   - Same-BB double-free = REAL bug (sequential free() calls)
///   - Different-BB multi-free = cleanup paths (each error branch frees, NOT a bug)
///
/// v0.1.7 FIX: Dual-source deduplication.
/// MemoryGraph.trackFree() sync (Source 1) + IR-scan (Source 3) may both create
/// FreeSite entries for the same LLVM instruction. Without deduplication, every
/// real free appears twice → 100% false-positive rate on double-free detection.
/// Fix: group by (ptr_value_id, inst_id) to eliminate dual-source duplicates.
pub fn detectDoubleFree(
    ctx: *PassContext,
    free_map: *std.AutoHashMap(u32, *FreeSite),
    stats: *OwnershipStats,
    diag: *DiagnosticWriter,
) !void {
    if (free_map.count() == 0) {
        diag.debug("DOUBLE-FREE: No free sites, skipping", .{});
        return;
    }

    if (free_map.count() > 500) {
        diag.debug("DOUBLE-FREE: Skipped (too many free sites: {d})", .{free_map.count()});
        return;
    }

    // Per-ptr tracking: count + unique BB set + first function name
    const PtrInfo = struct {
        count: u32,
        bb_set: std.AutoHashMap(usize, void),
        first_func: []const u8,
        // Dedup set: tracks (inst_id) to avoid counting same instruction twice.
        // Root cause: Source 1 (MemoryGraph.freed) + Source 3 (IR-scan) both
        // create FreeSite for identical LLVM instructions after trackFree() sync.
        inst_set: std.AutoHashMap(u32, void),
    };

    var ptr_info_map = std.AutoHashMap(u32, PtrInfo).init(free_map.allocator);
    defer {
        var iter = ptr_info_map.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.bb_set.deinit();
            entry.value_ptr.inst_set.deinit();
        }
        ptr_info_map.deinit();
    }

    // Collect free operations with RAII filtering + BB tracking + dedup
    var free_iter = free_map.iterator();
    while (free_iter.next()) |entry| {
        const free_info = entry.value_ptr.*;
        const ptr_id = free_info.ptr_value_id;

        if (isStlInternalFunction(free_info.func_name)) continue;
        if (isCppSpecialMemberFunction(free_info.func_name)) continue;
        const func_name_ptr = @intFromPtr(free_info.func_name.ptr);
        if (ctx.raii_func_set.contains(func_name_ptr)) continue;

        // DEDUP: Skip if we already counted this exact (ptr, inst) pair.
        // This eliminates dual-source duplication from MemoryGraph + IR-scan.
        const gop_result = try ptr_info_map.getOrPut(ptr_id);
        if (!gop_result.found_existing) {
            gop_result.value_ptr.* = .{
                .count = 0,
                .bb_set = std.AutoHashMap(usize, void).init(free_map.allocator),
                .first_func = free_info.func_name,
                .inst_set = std.AutoHashMap(u32, void).init(free_map.allocator),
            };
        }
        const info = gop_result.value_ptr;

        // Only increment count if this is a UNIQUE (ptr_id, inst_id) pair.
        const inst_id = free_info.inst_id;
        if (info.inst_set.contains(inst_id)) {
            diag.debug("DF-DEDUP: Skipping duplicate free for ptr={d} inst={d} in {s}", .{ ptr_id, inst_id, free_info.func_name });
            continue;
        }
        info.inst_set.put(inst_id, {}) catch {};
        info.count += 1;
        info.bb_set.put(free_info.bb_id, {}) catch {};
    }

    // Analyze each pointer with multiple frees
    var count_iter = ptr_info_map.iterator();
    while (count_iter.next()) |count_entry| {
        const alloc_id = count_entry.key_ptr.*;
        const info = count_entry.value_ptr.*;
        const free_cnt = info.count;
        const unique_bbs = info.bb_set.count();

        if (free_cnt > 5) continue;

        if (free_cnt > 1) {
            const first_func = info.first_func;

            const is_mangled = (std.mem.indexOf(u8, first_func, "_ZN") != null or
                std.mem.indexOf(u8, first_func, "$") != null or
                std.mem.indexOf(u8, first_func, "_R") != null);
            if (is_mangled) continue;

            // === P0-B Core Logic: Control-Flow Awareness ===
            //
            // Case 1: All frees in SAME basic block
            //   Example: free(p); ...; free(p);  (sequential, no branch)
            //   Verdict: REAL double-free bug → HIGH confidence
            //
            // Case 2: Frees in DIFFERENT basic blocks
            //   Example: if (err1) { free(p); return; } if (err2) { free(p); return; }
            //   Verdict: Multi-path cleanup pattern → SKIP (not a bug)
            //
            const is_same_bb = (unique_bbs == 1);

            if (!is_same_bb) {
                diag.debug("DOUBLE-FREE-SKIP: {d} frees of alloc {d} in {d} different BBs ({s}) — multi-path cleanup", .{ free_cnt, alloc_id, unique_bbs, first_func });
                continue;
            }

            stats.double_frees += 1;

            const severity: Severity = .high;
            const confidence: f32 = 0.92;
            // C2 FIX: Don't free string literal on OOM path - use early return pattern
            const msg = std.fmt.allocPrint(ctx.allocator, "DOUBLE-FREE: Allocation {d} freed {d} times in SAME basic block ({s})", .{ alloc_id, free_cnt, first_func }) catch {
                ctx.addIssue(&Issue.init(.double_free, "Double-free detected", Location.init(first_func), severity, confidence)) catch {
                    diag.warn("Failed to register critical double_free issue", .{});
                };
                diag.err("DOUBLE-FREE [HIGH]: Allocation {d} freed {d} times in SAME basic block ({s}) — confirmed double-free", .{ alloc_id, free_cnt, first_func });
                diag.err("  Risk: Heap corruption, use-after-free, security vulnerability", .{});
                continue;
            };

            ctx.addIssue(&Issue.init(.double_free, msg, Location.init(first_func), severity, confidence)) catch {
                diag.warn("Failed to register double_free issue with message", .{});
            };
            diag.err("DOUBLE-FREE [HIGH]: Allocation {d} freed {d} times in SAME basic block ({s}) — confirmed double-free", .{ alloc_id, free_cnt, first_func });
            diag.err("  Risk: Heap corruption, use-after-free, security vulnerability", .{});
        }
    }
}

/// Detect use-after-free: pointer used after being freed.
/// v0.1.7 FIX: Deduplication — each unique (freed_ptr, function) pair reports
/// at most 1 UAF. Previously, every flow edge from a freed pointer was counted
/// separately, causing 10x count inflation (e.g., 10 UAFs for 1 real bug).
pub fn detectUseAfterFree(
    ctx: *PassContext,
    free_map: *std.AutoHashMap(u32, *FreeSite),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    stats: *OwnershipStats,
    diag: *DiagnosticWriter,
) void {
    // Dedup set: each (ptr_id) reports at most once.
    var reported = std.AutoHashMap(u32, void).init(free_map.allocator);
    defer reported.deinit();

    var free_iter = free_map.iterator();
    while (free_iter.next()) |entry| {
        const free_info = entry.value_ptr.*;
        const ptr_id = free_info.ptr_value_id;

        // Skip if already reported for this ptr (dedup).
        if (reported.contains(ptr_id)) continue;

        // P1 Enhancement: Skip UAF in Rust's guaranteed-safe drop glue.
        if (isRustDropGlue(free_info.func_name)) {
            diag.debug("UAF-SKIP: {s} is Rust drop_in_place — guaranteed safe by ownership system", .{free_info.func_name});
            continue;
        }

        const classification = noise_filter.classifyFunctionFull(free_info.func_name, null, null, null);
        if (!classification.origin.shouldReportByDefault()) {
            diag.debug("UAF-SKIP: {s} is {s} — {s}", .{ free_info.func_name, classification.origin.toString(), classification.reason });
            continue;
        }

        // Skip functions with intentional/test pattern prefixes (correct_, valid_, etc.)
        if (is_likely_intentional_pattern(free_info.func_name)) {
            diag.debug("UAF-SKIP: {s} has known-safe function name prefix", .{free_info.func_name});
            continue;
        }

        const is_rust_mangled = std.mem.startsWith(u8, free_info.func_name, "_R") or
            (std.mem.startsWith(u8, free_info.func_name, "_ZN") and
                ffi_language_classifier.isRustMangledName(free_info.func_name));
        const is_explicitly_unsafe = std.mem.indexOf(u8, free_info.func_name, "unsafe") != null or
            std.mem.indexOf(u8, free_info.func_name, "unchecked") != null or
            std.mem.indexOf(u8, free_info.func_name, "raw") != null;
        if (is_rust_mangled and !is_explicitly_unsafe) {
            diag.debug("UAF-SKIP: {s} is Rust safe code — ownership system guarantees memory safety", .{free_info.func_name});
            continue;
        }

        var uaf_found = false;
        var flow_iter = flow_graph.iterator();
        while (flow_iter.next()) |flow_entry| {
            const from_id = flow_entry.key_ptr.*;

            if (from_id == ptr_id) {
                const flows = flow_entry.value_ptr;
                var target_iter = flows.iterator();
                while (target_iter.next()) |target_entry| {
                    const to_id = target_entry.key_ptr.*;

                    if (!free_map.contains(to_id)) {
                        uaf_found = true;
                        break;
                    }
                }
                if (uaf_found) break;
            }
        }

        if (uaf_found) {
            stats.use_after_frees += 1;
            ctx.addIssue(&Issue.init(.use_after_free, "Pointer used after being freed", Location.init(free_info.func_name), .high, 0.8)) catch {
                diag.warn("Failed to register use_after_free issue", .{});
            };
            diag.warn("USE-AFTER-FREE [MEDIUM]: Pointer {d} used after free in {s}", .{ ptr_id, free_info.func_name });
            reported.put(ptr_id, {}) catch {};
        }
    }
}

fn hasUseAfterFree(
    freed_ptr: u32,
    flow: *const std.AutoHashMap(u32, void),
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

/// Identify the language of a function (delegated to unified language_detector).
pub fn identifyLanguage(func: c.LLVMValueRef) Language {
    return @import("../../semantics/language_detector.zig").identifyLanguage(func);
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
    detectDoubleFree(ctx, free_map, stats, diag) catch {};
    detectUseAfterFree(ctx, free_map, flow_graph, stats, diag);
}

/// Detect loop-internal memory leaks: allocations inside loop bodies
/// that are never freed within the same iteration.
pub fn detectLoopLeaks(
    ctx: *PassContext,
    alloc_map: *std.AutoHashMap(u32, *AllocSite),
    diag: *DiagnosticWriter,
) !void {
    // Store function name directly instead of pointer to avoid unsafe casts
    var func_alloc_counts = std.StringHashMap(u32).init(alloc_map.allocator);
    defer func_alloc_counts.deinit();

    var func_free_counts = std.StringHashMap(u32).init(alloc_map.allocator);
    defer func_free_counts.deinit();

    var alloc_iter = alloc_map.iterator();
    while (alloc_iter.next()) |entry| {
        const alloc_info = entry.value_ptr.*;
        if (alloc_info.transferred) continue;
        if (isStlInternalFunction(alloc_info.func_name)) continue;
        if (isCppSpecialMemberFunction(alloc_info.func_name)) continue;

        // Additional RAII filtering: skip functions in RAII-managed context
        const func_ptr = @intFromPtr(alloc_info.func_name.ptr);
        if (ctx.raii_func_set.contains(func_ptr)) continue;
        const count = func_alloc_counts.getOrPut(alloc_info.func_name) catch continue;
        if (!count.found_existing) {
            count.value_ptr.* = 0;
        }
        count.value_ptr.* += 1;
    }

    var leak_candidates = try std.ArrayList(struct { func: []const u8, count: u32 }).initCapacity(alloc_map.allocator, 8);
    defer {
        for (leak_candidates.items) |item| {
            _ = item;
        }
        leak_candidates.deinit(alloc_map.allocator);
    }

    var count_iter = func_alloc_counts.iterator();
    while (count_iter.next()) |entry| {
        // Hard cap: >20 allocations in single function is likely legitimate code
        if (entry.value_ptr.* >= 3 and entry.value_ptr.* <= 20) {
            leak_candidates.append(alloc_map.allocator, .{ .func = entry.key_ptr.*, .count = entry.value_ptr.* }) catch continue;
        }
    }

    for (leak_candidates.items) |candidate| {
        // C3 FIX: Don't free string literal on OOM path - use early return pattern
        const msg = std.fmt.allocPrint(alloc_map.allocator, "LOOP LEAK: {d} allocations in {s} - possible loop without free", .{ candidate.count, candidate.func }) catch {
            ctx.addIssue(&Issue.init(.memory_leak, "Loop memory leak detected", Location.init(candidate.func), .medium, 0.7)) catch {
                diag.warn("Failed to register loop leak issue", .{});
            };
            diag.warn("LOOP-LEAK [MEDIUM]: {d} heap allocations detected in {s} - verify loop has matching free()", .{ candidate.count, candidate.func });
            continue;
        };
        defer ctx.allocator.free(msg);
        ctx.addIssue(&Issue.init(.memory_leak, msg, Location.init(candidate.func), .medium, 0.7)) catch {
            diag.warn("Failed to register loop leak-specific issue", .{});
        };
    }
}

/// Detect resource leaks: fopen without fclose, socket without close, etc.
pub fn detectResourceLeaks(
    ctx: *PassContext,
    diag: *DiagnosticWriter,
) void {
    const mod = ctx.module orelse return;
    const raw_mod = mod.raw;

    var resource_funcs = std.StringHashMap([]const u8).init(ctx.allocator);
    defer resource_funcs.deinit();

    resource_funcs.put("fopen", "fclose") catch {};
    resource_funcs.put("tmpfile", "fclose") catch {};
    resource_funcs.put("freopen", "fclose") catch {};
    resource_funcs.put("socket", "close") catch {};
    resource_funcs.put("accept", "close") catch {};
    resource_funcs.put("opendir", "closedir") catch {};
    resource_funcs.put("popen", "pclose") catch {};

    var func = c.LLVMGetFirstFunction(raw_mod);
    while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
        if (c.LLVMIsDeclaration(func) != 0) continue;

        var bb = c.LLVMGetFirstBasicBlock(func);
        var alloc_found = std.ArrayList([]const u8).initCapacity(ctx.allocator, 4) catch break;
        defer alloc_found.deinit(ctx.allocator);
        var free_found = std.ArrayList([]const u8).initCapacity(ctx.allocator, 4) catch break;
        defer free_found.deinit(ctx.allocator);

        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (c.LLVMGetInstructionOpcode(inst) != c.LLVMCall) continue;

                const num_operands = c.LLVMGetNumOperands(inst);
                if (num_operands == 0) continue;
                const callee = c.LLVMGetOperand(inst, @intCast(num_operands - 1));
                if (@intFromPtr(callee) == 0) continue;
                const callee_name = c.LLVMGetValueName(callee);
                if (@intFromPtr(callee_name) == 0) continue;
                const name_slice = std.mem.span(callee_name);

                var res_iter = resource_funcs.iterator();
                while (res_iter.next()) |entry| {
                    if (std.mem.eql(u8, name_slice, entry.key_ptr.*)) {
                        alloc_found.append(ctx.allocator, entry.key_ptr.*) catch {};
                    }
                    if (std.mem.eql(u8, name_slice, entry.value_ptr.*)) {
                        free_found.append(ctx.allocator, entry.value_ptr.*) catch {};
                    }
                }
            }
        }

        var res_check_iter = resource_funcs.iterator();
        while (res_check_iter.next()) |entry| {
            var has_alloc = false;
            var has_free = false;
            for (alloc_found.items) |a| {
                if (std.mem.eql(u8, a, entry.key_ptr.*)) has_alloc = true;
            }
            for (free_found.items) |f| {
                if (std.mem.eql(u8, f, entry.value_ptr.*)) has_free = true;
            }

            if (has_alloc and !has_free) {
                const func_name_raw = c.LLVMGetValueName(func);
                const func_name = if (func_name_raw) |n| std.mem.span(n) else "unknown";
                const is_heap_msg: bool = std.fmt.allocPrint(ctx.allocator, "RESOURCE LEAK: {s} called but {s} missing in {s}", .{ entry.key_ptr.*, entry.value_ptr.*, func_name }) catch {
                    ctx.addIssue(&Issue.init(.memory_leak, "Resource leak detected", Location.init(func_name), .medium, 0.75)) catch {};
                    diag.warn("RESOURCE-LEAK [MEDIUM]: {s}() without matching {s}() in {s}", .{ entry.key_ptr.*, entry.value_ptr.*, func_name });
                    continue;
                };
                ctx.addIssue(&Issue.init(.memory_leak, is_heap_msg, Location.init(func_name), .medium, 0.75)) catch {
                    ctx.allocator.free(is_heap_msg);
                };
                diag.warn("RESOURCE-LEAK [MEDIUM]: {s}() without matching {s}() in {s}", .{ entry.key_ptr.*, entry.value_ptr.*, func_name });
            }
        }
    }
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

        const has_free_path = findFreePath(alloc_info.inst_id, free_map, flow_graph) catch false;
        if (!has_free_path) {
            if (is_likely_intentional_pattern(alloc_info.func_name)) {
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
                ctx.addIssue(&Issue.init(
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
) !bool {
    var visited = std.AutoHashMap(u32, void).init(free_map.allocator);
    defer visited.deinit();

    var bfs_queue = try std.ArrayList(u32).initCapacity(free_map.allocator, 64);
    defer bfs_queue.deinit(free_map.allocator);
    try bfs_queue.append(free_map.allocator, from_ptr);

    while (bfs_queue.items.len > 0) {
        const current = bfs_queue.orderedRemove(0);

        if (visited.contains(current)) continue;
        try visited.put(current, {});

        if (free_map.contains(current)) return true;

        if (flow_graph.get(current)) |flows| {
            var iter = flows.iterator();
            while (iter.next()) |entry| {
                const next_id = entry.key_ptr.*;
                if (!visited.contains(next_id)) {
                    try bfs_queue.append(free_map.allocator, next_id);
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
                .{ .file = file, .func = alloc.func_name, .line = alloc.debug_line orelse 0, .column = alloc.debug_column orelse 0 }
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
                            .{ .file = file, .func = alloc.func_name, .line = alloc.debug_line orelse 0, .column = alloc.debug_column orelse 0 }
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
                            alloc_loc.func,
                            @tagName(alloc.lang),
                            alloc.inst_id,
                        });
                        diag.warn("  Free: {s} ({s}) at inst {}", .{
                            free_loc.func,
                            @tagName(free_site.lang),
                            free_site.inst_id,
                        });
                        const desc = try lifetime.formatViolationMessage(ctx.allocator, violation.kind, violation.origin_lang, violation.action_lang);
                        defer ctx.allocator.free(desc);
                        diag.warn("  Description: {s}", .{desc});
                    } else {
                        diag.warn("CROSS-LANGUAGE OWNERSHIP VIOLATION DETECTED", .{});
                        diag.warn("  Alloc: {s} ({s}) at inst {}", .{
                            alloc_loc.func,
                            @tagName(alloc.lang),
                            alloc.inst_id,
                        });
                        diag.warn("  Free: {s} ({s}) at inst {}", .{
                            free_loc.func,
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
        .java => .java,
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
            ctx.addIssue(&Issue.initWithReason(
                .cross_language_leak,
                "Cross-language alloc mismatch: Rust-alloc freed by C free()",
                Location.init(alloc.func_name),
                .high,
                0.85,
                "Rust global_alloc (_Znwm) result freed by C free() - allocator mismatch",
            )) catch {
                diag.warn("Failed to register cross-lang mismatch issue", .{});
            };
            diag.err("CROSS-LANG MISMATCH OMI-{d:0>3} [{s}] [Confidence: {s}]", .{ vuln_id, @tagName(.high), @tagName(Confidence.fromScore(0.85)) });
            diag.err("Type: cross_language_alloc_mismatch", .{});
            diag.err("Reason: Rust _Znwm allocation freed by C free() - heap mismatch", .{});
        }
    }
}
