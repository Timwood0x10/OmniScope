//! Pointer Ownership — Type Definitions & Common Helpers
//!
//! Extracted from pointer_ownership.zig to reduce file size.
//! Shared types used by pointer_ownership, cpp_fp_reduction, and other passes.

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const llvm_safe = @import("../ir/llvm_safe.zig");
const Language = @import("../diag/issue.zig").FFIBoundary.Language;
const alloc_classifier = @import("../pass/analysis/ptr_lifetime/allocation_classifier.zig");

const graph_algo = @import("../dataflow/graph_algorithms.zig");

pub const AllocType = alloc_classifier.AllocType;
pub const FreeType = alloc_classifier.FreeType;

/// Error type for ownership tracking operations.
pub const OwnershipError = error{
    OutOfMemory,
    NoModule,
    NullPointer,
};

/// Source of an allocation or free site — which data source provided this record.
/// Used to distinguish between MemoryGraph-sourced, GlobalAllocTracker-sourced,
/// and IR-scanned sites for diagnostics and cross-validation.
pub const OwnershipSource = enum(u8) {
    memory_graph,
    global_alloc_tracker,
    ir_scan,
    direct_analysis,
};

/// Mode of ownership transfer between language boundaries.
pub const OwnershipMode = enum(u8) {
    none,
    rust_to_c,
    c_to_rust,
    rust_to_cpp,
    cpp_to_rust,
    internal_transfer,
};

/// Hint for FFI relevance classification of Rust functions.
/// Used by isRustFFIRelevantFunction to categorize why a function was accepted/rejected.
pub const FFIRelevanceHint = enum(u8) {
    not_rust_mangled,
    name_pattern_match,
    direct_extern_call,
    indirect_fn_ptr_call,
    no_ffi_activity,
};

/// Configuration for the PointerOwnershipPass analysis behavior.
pub const OwnershipPassConfig = struct {
    enable_cross_lang_check: bool = true,
    enable_leak_detection: bool = true,
    enable_double_free_check: bool = true,
    enable_uaf_detection: bool = true,
    enable_null_deref_check: bool = true,
    max_bfs_depth: u32 = 256,
    max_aliases_tracked: u32 = 64,
    cache_ffi_relevance: bool = true,
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
/// NOTE: This is the authoritative source for AllocSite definition.
/// Other modules (e.g., callback_escape_types.zig) should reference this type.
pub const AllocSite = struct {
    inst_id: u32,
    func_name: []const u8,
    lang: Language,
    alloc_type: AllocType,
    ptr_value_id: u32,
    bb_id: usize,
    transferred: bool = false,
    stored_to_struct_field: bool = false,
    source: OwnershipSource = .direct_analysis,
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
/// NOTE: This is the authoritative source for FreeSite definition.
/// Other modules (e.g., callback_escape_types.zig) should reference this type.
pub const FreeSite = struct {
    inst_id: u32,
    func_name: []const u8,
    lang: Language,
    free_type: FreeType,
    ptr_value_id: u32,
    bb_id: usize,
    source: OwnershipSource = .direct_analysis,
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
    raii_managed: u32 = 0,
    meyers_singletons: u32 = 0,
    rc_containers: u32 = 0,
    rust_into_raw_funcs: u32 = 0,
    rust_from_raw_funcs: u32 = 0,
    cpp_internal_suppressed: u32 = 0,

    pub fn format(
        self: *const OwnershipStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll("OwnershipStats{ ");
        try writer.print("allocs={}, frees={}, tracked={}, transfers={}, violations={}", .{
            self.alloc_sites,
            self.free_sites,
            self.tracked_pointers,
            self.cross_ffi_transfers,
            self.violations,
        });
        if (self.memory_leaks > 0 or self.double_frees > 0 or self.use_after_frees > 0) {
            try writer.print(" leaks={} df={} uaf={}", .{ self.memory_leaks, self.double_frees, self.use_after_frees });
        }
        try writer.writeAll(" }");
    }
};

// ============================================================================
// Constant Tables & Configuration
// ============================================================================

/// Standard library / runtime function prefixes that do NOT represent
/// real FFI boundary security risk. Used by FFI Relevance Gate.
// TODO: Move to function_catalogs.zig (shared constant catalog) once that module
// is created, to consolidate duplicate constant definitions across the codebase.
pub const stdlib_prefixes = [_][]const u8{
    "malloc",      "calloc",             "realloc",          "free",
    "abort",       "exit",               "printf",           "fprintf",
    "sprintf",     "snprintf",           "puts",             "fputs",
    "memcpy",      "memset",             "memmove",          "memcmp",
    "strlen",      "strcpy",             "strncpy",          "strcmp",
    "__rust_",     "llvm.",              "_Znwm",            "_Znam",
    "_ZdlPv",      "pthread_",           "dlopen",           "dlsym",
    "sigaltstack", "__deregister_frame", "__register_frame",
};

/// Name-based patterns for fast-path Rust FFI relevance detection.
/// Functions containing these substrings are considered FFI-relevant
/// without expensive IR scanning.
pub const ffi_name_patterns = [_][]const u8{
    "_ffi",     "_extern",   "_cinterop", "_bindgen",
    "_foreign", "_abi",      "_marshal",  "_syscall",
    "_invoke",  "_callback", "_native",   "_interop",
};

/// LLVM memory intrinsic names for memory access classification.
// TODO: Move to function_catalogs.zig (shared constant catalog) once that module
// is created, to consolidate duplicate constant definitions across the codebase.
pub const mem_intrinsics = [_][]const u8{
    "llvm.memcpy",        "llvm.memmove", "llvm.memset",
    "llvm.memset.inline",
};

/// Opcode name table for diagnostic messages.
pub const opcode_names = [_][]const u8{
    "load",   "store",   "gep",    "call",   "ret",
    "br",     "switch",  "phi",    "alloca", "extract",
    "insert", "shuffle", "select", "icmp",   "fcmp",
};

// ============================================================================
// Pure Helper Functions (no dependency on PassContext)
// ============================================================================

/// Check if a callee name is a standard library / runtime call
/// that does not represent a real FFI boundary security risk.
pub fn isStdlibCall(callee_name: []const u8) bool {
    for (stdlib_prefixes) |prefix| {
        if (std.mem.startsWith(u8, callee_name, prefix)) return true;
    }
    return false;
}

/// Check if a Rust-mangled function has name-based FFI hints.
/// Returns the matching hint or null if no pattern matched.
pub fn checkFfiNamePatterns(func_name: []const u8) ?FFIRelevanceHint {
    for (ffi_name_patterns) |pat| {
        if (std.mem.indexOf(u8, func_name, pat) != null) return .name_pattern_match;
    }
    return null;
}

/// Check if debug metadata is available in the LLVM module.
/// Used to determine if file/line diagnostics can be produced.
pub fn checkDebugMetadataAvailable(mod: c.LLVMModuleRef) bool {
    var md_node = c.LLVMGetFirstNamedMetadata(mod);
    while (@intFromPtr(md_node) != 0) {
        var name_len: usize = 0;
        const name_ptr = c.LLVMGetNamedMetadataName(md_node, &name_len);
        if (@intFromPtr(name_ptr) != 0) {
            const md_name = name_ptr[0..name_len];
            if (std.mem.startsWith(u8, md_name, "llvm.dbg") or
                std.mem.startsWith(u8, md_name, "!dbg"))
            {
                return true;
            }
        }
        md_node = c.LLVMGetNextNamedMetadata(md_node);
    }
    return false;
}

/// Check if an allocation site involves cross-language (non-C, non-unknown) allocation.
// TODO: Move to function_catalogs.zig (shared function catalog) once that module
// is created, to consolidate duplicate language classification logic.
pub fn isCrossFFIAllocation(alloc_lang: Language) bool {
    return alloc_lang != .unknown and alloc_lang != .c;
}

/// Mark all AllocSite entries whose allocated value can reach target_value_id
/// via reverse flow graph. Uses BFS with visited set for cycle detection.
pub fn markAllocSitesReachingValue(
    allocator: std.mem.Allocator,
    alloc_map: *std.AutoHashMap(u32, *AllocSite),
    reverse_flow: *FlowGraph,
    target_value_id: u32,
) !void {
    var visited = std.AutoHashMap(u32, void).init(allocator);
    defer visited.deinit();

    var bfs_queue = try std.ArrayList(u32).initCapacity(allocator, 32);
    defer bfs_queue.deinit(allocator);
    try bfs_queue.append(allocator, target_value_id);

    while (bfs_queue.items.len > 0) {
        const current = bfs_queue.orderedRemove(0);
        if (visited.contains(current)) continue;
        try visited.put(current, {});

        if (alloc_map.get(current)) |site| {
            site.transferred = true;
        }

        if (reverse_flow.get(current)) |preds| {
            var pred_iter = preds.iterator();
            while (pred_iter.next()) |entry| {
                const pred_id = entry.key_ptr.*;
                if (!visited.contains(pred_id)) {
                    try bfs_queue.append(allocator, pred_id);
                }
            }
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "OwnershipTypes - alloc types" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(AllocType.heap));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(AllocType.rust_box_into_raw));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(AllocType.rust_box_from_raw));
}

test "OwnershipTypes - ownership states" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(OwnershipState.live));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(OwnershipState.ownership_transferred));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(OwnershipState.freed));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(OwnershipState.leaked));
}

test "OwnershipTypes - violation types" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(OwnershipViolationType.cross_lang_free_mismatch));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(OwnershipViolationType.ownership_lost));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(OwnershipViolationType.double_free_risk));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(OwnershipViolationType.rust_drop_after_ffi_transfer));
}

test "OwnershipTypes - ownership source" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(OwnershipSource.memory_graph));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(OwnershipSource.global_alloc_tracker));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(OwnershipSource.ir_scan));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(OwnershipSource.direct_analysis));
}

test "OwnershipTypes - ownership mode" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(OwnershipMode.none));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(OwnershipMode.rust_to_c));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(OwnershipMode.rust_to_cpp));
}

test "OwnershipTypes - isStdlibCall" {
    try std.testing.expect(isStdlibCall("malloc"));
    try std.testing.expect(isStdlibCall("free"));
    try std.testing.expect(isStdlibCall("__rust_dealloc"));
    try std.testing.expect(!isStdlibCall("my_custom_func"));
    try std.testing.expect(!isStdlibCall("ffi_bindgen_wrapper"));
}

// ============================================================================
// Pure Graph Algorithms (no PassContext dependency)
// ============================================================================

/// Check if a Rust-mangled function is FFI-relevant.
/// For Rust-mangled functions (_R* or $*), analyzes if the function:
///   A) Calls an extern/"C" declaration directly
///   B) Uses indirect calls through function pointers (FFI callback pattern)
///   C) Has name suggesting FFI relevance (ffi/extern/bindgen/cinterop)
pub fn isRustFFIRelevantFunction(func: c.LLVMValueRef) bool {
    const func_name_raw = c.LLVMGetValueName(func);
    if (func_name_raw == null) return true;
    const func_name = std.mem.span(func_name_raw);

    const is_rust = (std.mem.indexOf(u8, func_name, "_R") != null or
        std.mem.indexOf(u8, func_name, "$") != null);
    if (!is_rust) return true;

    if (checkFfiNamePatterns(func_name) != null) return true;

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            if (llvm_safe.isCallOrInvoke(c.LLVMGetInstructionOpcode(inst))) {
                const num_ops = c.LLVMGetNumOperands(inst);
                if (num_ops == 0) continue;
                const callee_val = c.LLVMGetOperand(inst, @intCast(num_ops - 1));
                if (@intFromPtr(callee_val) == 0) continue;
                if (c.LLVMIsDeclaration(callee_val) != 0) return true;
                if (c.LLVMIsAFunction(callee_val) == null) return true;
            }
        }
    }
    return false;
}

/// Flow graph type alias for readability.
pub const FlowGraph = std.AutoHashMap(u32, std.AutoHashMap(u32, void));

/// Check if a value can reach another value through the flow graph (DFS).
/// Uses visited set for cycle detection on cyclic graphs.
/// Delegates to graph_algorithms.zig (SSOT).
pub fn canReach(
    flow_graph: *const FlowGraph,
    from: u32,
    to: u32,
    visited: *std.AutoHashMap(u32, void),
) bool {
    return graph_algo.canReach(flow_graph, from, to, visited);
}

/// BFS traversal with cycle detection from from_ptr to find any reachable free site.
/// Enables alloc-free path detection for leak analysis.
/// Returns true if from_ptr can reach any entry in free_map via flow_graph.
/// Delegates to graph_algorithms.zig (SSOT).
pub fn findFreePath(
    from_ptr: u32,
    free_map: *std.AutoHashMap(u32, void),
    flow_graph: *const FlowGraph,
    visited: *std.AutoHashMap(u32, void),
) bool {
    return graph_algo.findFreePath(from_ptr, free_map, flow_graph, visited);
}

/// DFS with cycle detection to check if 'from' can reach any free site.
/// Used by use-after-free detection after a pointer is freed.
/// The 'flow' parameter tracks live aliases — if non-empty, 'from' has live aliases
/// that should also be checked for reachability to free sites.
///
/// CONSERVATIVE STRATEGY: If 'from' has known aliases AND any of those aliases
/// are in the free_map, count it as a potential UAF even without full chain tracking.
/// This catches: ptr_a = alloc(); ptr_b = alias(ptr_a); free(ptr_a); use(ptr_b)
/// Delegates to graph_algorithms.zig (SSOT).
pub fn canReachFree(
    from: u32,
    flow: std.AutoHashMap(u32, void),
    free_map: *std.AutoHashMap(u32, void),
    flow_graph: *const FlowGraph,
    visited: *std.AutoHashMap(u32, void),
) bool {
    return graph_algo.canReachFree(from, flow, free_map, flow_graph, visited);
}

/// Add a forward edge (from → to) to flow_graph and reverse edge to reverse_flow.
/// Skips self-edges. Both maps must use the same allocator.
pub fn addFlowEdge(
    allocator: std.mem.Allocator,
    from: u32,
    to: u32,
    flow_graph: *FlowGraph,
    reverse_flow: ?*FlowGraph,
) !void {
    if (from == to) return;

    const entry = try flow_graph.getOrPut(from);
    if (!entry.found_existing) {
        entry.value_ptr.* = std.AutoHashMap(u32, void).init(allocator);
    }
    try entry.value_ptr.put(to, {});

    if (reverse_flow) |rf| {
        const rf_entry = try rf.getOrPut(to);
        if (!rf_entry.found_existing) {
            rf_entry.value_ptr.* = std.AutoHashMap(u32, void).init(allocator);
        }
        try rf_entry.value_ptr.put(from, {});
    }
}
