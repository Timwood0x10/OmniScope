//! C++ False Positive Reduction Types
//!
//! Extracted from cpp_fp_reduction.zig per rules.md line limit (≤1000 lines).
//! Contains type definitions, constants, helper structs, and pure functions
//! for C++ false positive reduction analysis.
//!
//! Log prefix: [cpp-fp-types]

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const llvm_safe = @import("../ir/llvm_safe.zig");
const Language = @import("../diag/issue.zig").FFIBoundary.Language;
const lifetime = @import("../lifetime/root.zig");
const ValueIdMap = @import("../dataflow/value_id_map.zig").ValueIdMap;
const PathManager = @import("../dataflow/path_condition.zig").PathManager;
const identifyLanguages = @import("../semantics/language_detector.zig").identifyLanguage;

// ==================== Constants ====================

/// Patterns for nullable allocations (may return NULL).
pub const nullable_patterns = [_][]const u8{
    "malloc",        "calloc",         "realloc",         "strdup",
    "sqlite3Malloc", "sqlite3Realloc", "sqlite3DbMalloc", "sqlite3DbRealloc",
    "fopen",         "BIO_new",        "EVP_",            "RSA_",
    "SSL_CTX_new",   "X509_new",       "PEM_",            "inflateInit",
    "deflateInit",   "gzopen",
};

/// Patterns for struct member ownership detection.
pub const struct_member_patterns = [_][]const u8{
    "fts5",
    "sqlite3Fts5",
    "StorageGet",
    "PrepareStmt",
    "Pragma",
    "MemSize",
    "MemRealloc",
    "serialize",
};

/// Patterns for Rust into_raw (ownership transfer OUT) calls.
pub const into_raw_patterns = [_][]const u8{
    "into_raw",
    "8into_raw",
    "Box.*into_raw",
    "CString.*into_raw",
    "Vec.*leak",
};

/// Patterns for Rust from_raw (ownership transfer IN) calls.
pub const from_raw_patterns = [_][]const u8{
    "from_raw",
    "8from_raw",
    "Box.*from_raw",
    "CString.*from_raw",
    "from_raw_parts",
};

/// Patterns for Rust as_ptr (borrow escape) calls.
pub const as_ptr_patterns = [_][]const u8{
    "as_ptr",
    "as_mut_ptr",
    "slice::as_ptr",
};

/// Resource allocation/deallocation pairs for leak detection.
pub const resource_pairs = [_]struct { []const u8, []const u8 }{
    .{ "fopen", "fclose" },
    .{ "tmpfile", "fclose" },
    .{ "freopen", "fclose" },
    .{ "socket", "close" },
    .{ "accept", "close" },
    .{ "opendir", "closedir" },
    .{ "popen", "pclose" },
};

// ==================== Helper Structs ====================

/// Per-pointer tracking info for double-free detection.
/// Tracks count, unique basic block set, first function name,
/// and dedup set to avoid counting same instruction twice.
pub const PtrInfo = struct {
    count: u32,
    bb_set: std.AutoHashMap(usize, void),
    first_func: []const u8,
    /// Dedup set: tracks (inst_id) to avoid counting same instruction twice.
    /// Root cause: Source 1 (MemoryGraph.freed) + Source 3 (IR-scan) both
    /// create FreeSite for identical LLVM instructions after trackFree() sync.
    inst_set: std.AutoHashMap(u32, void),

    pub fn init(allocator: std.mem.Allocator, func_name: []const u8) !PtrInfo {
        return .{
            .count = 0,
            .bb_set = std.AutoHashMap(usize, void).init(allocator),
            .first_func = func_name,
            .inst_set = std.AutoHashMap(u32, void).init(allocator),
        };
    }

    pub fn deinit(self: *PtrInfo) void {
        self.bb_set.deinit();
        self.inst_set.deinit();
    }
};

// ==================== Pure Functions ====================

/// Check if an allocation can return NULL.
pub fn isNullableAllocation(func_name: []const u8) bool {
    for (nullable_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

// ==================== Leak Detection Helpers ====================

/// Detect loop-internal memory leaks: allocations inside loop bodies
/// that are never freed within the same iteration.
pub fn detectLoopLeaks(
    ctx: *const @import("../pass/pass.zig").PassContext,
    alloc_map: *std.AutoHashMap(u32, *const @import("./ownership_types.zig").AllocSite),
    diag: *const @import("../pass/pass.zig").DiagnosticWriter,
) !void {
    const Issue = @import("../diag/issue.zig").Issue;
    const Location = @import("../diag/issue.zig").Location;

    var func_alloc_counts = std.StringHashMap(u32).init(alloc_map.allocator);
    defer func_alloc_counts.deinit();

    var func_free_counts = std.StringHashMap(u32).init(alloc_map.allocator);
    defer func_free_counts.deinit();

    var alloc_iter = alloc_map.iterator();
    while (alloc_iter.next()) |entry| {
        const alloc_info = entry.value_ptr.*;
        if (alloc_info.transferred) continue;
        // Note: isStlInternalFunction and isCppSpecialMemberFunction are imported from cpp_fp_helpers
        const helpers = @import("../pass/analysis/noise/cpp_fp_helpers.zig");
        if (helpers.isStlInternalFunction(alloc_info.func_name)) continue;
        if (helpers.isCppSpecialMemberFunction(alloc_info.func_name)) continue;

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
    ctx: *const @import("../pass/pass.zig").PassContext,
    diag: *const @import("../pass/pass.zig").DiagnosticWriter,
) void {
    const Issue = @import("../diag/issue.zig").Issue;
    const Location = @import("../diag/issue.zig").Location;
    const cpp_helpers = @import("../pass/analysis/noise/cpp_fp_helpers.zig");
    const isCppInternalLeakPattern = cpp_helpers.isCppInternalLeakPattern;

    const mod = ctx.module orelse return;
    const raw_mod = mod.raw;

    var resource_funcs = std.StringHashMap([]const u8).init(ctx.allocator);
    defer resource_funcs.deinit();

    for (resource_pairs) |pair| {
        resource_funcs.put(pair[0], pair[1]) catch {};
    }

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
                if (!llvm_safe.isCallOrInvoke(c.LLVMGetInstructionOpcode(inst))) continue;

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

                // T1.4 C++ Internal Leak Gate: suppress resource leak reports
                // from STL/internal functions in C++ modules
                const is_cpp_module = ctx.module_language.language == .cpp or
                    ctx.module_language.language == .unknown;
                if (is_cpp_module and isCppInternalLeakPattern(func_name)) {
                    diag.debug("CPP-LEAK-GATE: suppressed resource leak in {s} (C++ STL internal)", .{func_name});
                    continue;
                }

                const is_heap_msg: []const u8 = std.fmt.allocPrint(ctx.allocator, "RESOURCE LEAK: {s} called but {s} missing in {s}", .{ entry.key_ptr.*, entry.value_ptr.*, func_name }) catch {
                    ctx.addIssue(&Issue.init(.memory_leak, "Resource leak detected", Location.init(func_name), .medium, 0.75)) catch {};
                    diag.warn("RESOURCE-LEAK [MEDIUM]: {s}() without matching {s}() in {s}", .{ entry.key_ptr.*, entry.value_ptr.*, func_name });
                    continue;
                };
                ctx.addIssue(&Issue.init(.memory_leak, is_heap_msg, Location.init(func_name), .medium, 0.75)) catch {
                    ctx.allocator.free(is_heap_msg);
                    continue;
                };
                ctx.allocator.free(is_heap_msg);
                diag.warn("RESOURCE-LEAK [MEDIUM]: {s}() without matching {s}() in {s}", .{ entry.key_ptr.*, entry.value_ptr.*, func_name });
            }
        }
    }
}

/// Extract function name from LLVM value reference.
pub const getFunctionName = @import("../ir/ir_helpers.zig").getFunctionName;

/// Identify the language of a function (delegated to unified language_detector).
pub fn identifyLanguage(func: c.LLVMValueRef) Language {
    return identifyLanguages(func);
}

/// Check if a free is guarded by a null check.
pub fn isGuardedByNullCheck(
    free_inst: c.LLVMValueRef,
    ptr_value_id: u32,
    path_manager: *const PathManager,
) bool {
    _ = free_inst;
    return path_manager.isPtrNonNull(ptr_value_id);
}

/// Check if a function likely manages memory through struct member ownership.
pub fn isLikelyStructMemberOwnership(func_name: []const u8) bool {
    for (struct_member_patterns) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Convert internal Language enum to lifetime.LanguageHint.
pub fn convertLanguageToHint(lang: Language) lifetime.LanguageHint {
    return switch (lang) {
        .c => .c,
        .rust => .rust,
        .zig => .zig,
        .cpp => .cpp,
        .go => .go,
        .csharp => .csharp,
        .java => .java,
        .python => .python,
        .unknown => .unknown,
    };
}

/// Check if a value can reach another value through the flow graph.
pub const canReach = @import("../dataflow/graph_algorithms.zig").canReach;

/// Check if a callee name is a Rust into_raw (ownership transfer OUT) call.
pub fn isRustIntoRawCall(callee_name: []const u8) bool {
    for (into_raw_patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if a callee name is a Rust from_raw (ownership transfer IN) call.
pub fn isRustFromRawCall(callee_name: []const u8) bool {
    for (from_raw_patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Check if a callee name is a Rust as_ptr (borrow escape) call.
// TODO: Move to shared module (e.g., ir_helpers.zig) when consolidating duplicate
// Rust pattern detection functions across the codebase.
pub fn isRustAsPtrCall(callee_name: []const u8) bool {
    for (as_ptr_patterns) |pattern| {
        if (std.mem.indexOf(u8, callee_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

// ==================== Detection Helper Functions ====================

/// Detect when allocation results are stored into struct/aggregate fields via GEP + store.
pub fn detectStructMemberStores(
    func: c.LLVMValueRef,
    alloc_map: *std.AutoHashMap(u32, *@import("./ownership_types.zig").AllocSite),
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

/// Detect Rust FFI ownership transfer patterns in function bodies.
/// Accepts pre-categorized calls[] from IR Store — no BB/inst traversal.
pub fn detectRustFfiPairingFunctions(
    calls: []const c.LLVMValueRef,
    func_name: []const u8,
    into_raw_set: *std.StringHashMap(void),
    from_raw_set: *std.StringHashMap(void),
) void {
    var has_into_raw = false;
    var has_from_raw = false;

    for (calls) |inst| {
        const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
        if (num_operands == 0) continue;
        const callee = c.LLVMGetOperand(inst, num_operands - 1);
        if (@intFromPtr(callee) == 0) continue;
        const callee_name = c.LLVMGetValueName(callee);
        if (@intFromPtr(callee_name) == 0) continue;
        const name_slice = std.mem.sliceTo(callee_name, 0);

        if (isRustIntoRawCall(name_slice)) has_into_raw = true;
        if (isRustFromRawCall(name_slice)) has_from_raw = true;
        if (has_into_raw and has_from_raw) break;
    }

    if (has_into_raw) into_raw_set.put(func_name, {}) catch {};
    if (has_from_raw) from_raw_set.put(func_name, {}) catch {};
}

// ==================== Flow Graph Helpers ====================

/// Check if allocation result can reach any free site through the flow graph.
// TODO: Delegate to graph_algorithms.zig once the function signature is unified.
// The shared version (dataflow/graph_algorithms.zig) uses *std.AutoHashMap(u32, void)
// for free_map, while this version uses *std.AutoHashMap(u32, *const FreeSite).
pub fn findFreePath(
    from_ptr: u32,
    free_map: *std.AutoHashMap(u32, *const @import("./ownership_types.zig").FreeSite),
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

/// Check if freed pointer has use-after-free in flow graph.
pub fn hasUseAfterFree(
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
