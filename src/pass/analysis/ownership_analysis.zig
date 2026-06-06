//! Ownership Analysis Methods — Pure analysis functions extracted from PointerOwnershipPass.
//!
//! Contains: function-level analysis, instruction-level analysis,
//! flow graph construction, and ownership transfer checking.
//! These methods have no dependency on PassContext state — they operate
//! purely on LLVM IR and data structures passed as parameters.
//!
//! Log prefix: [ownership-analysis]

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../ir/llvm_safe.zig");
const ir_store_mod = @import("../../ir/ir_store.zig");

const types = @import("../../types/ownership_types.zig");
pub const AllocSite = types.AllocSite;
pub const FreeSite = types.FreeSite;
pub const AllocType = types.AllocType;
pub const FreeType = types.FreeType;
pub const OwnershipStats = types.OwnershipStats;
pub const addFlowEdge = types.addFlowEdge;
pub const markAllocSitesReachingValue = types.markAllocSitesReachingValue;

const ValueIdMap = @import("../../dataflow/value_id_map.zig").ValueIdMap;
const MemoryPool = @import("../../perf/memory_pool.zig").MemoryPool;
const NullCheckRecognizer = @import("../../dataflow/null_check_guard.zig").NullCheckRecognizer;
const alloc_classifier = @import("ptr_lifetime/allocation_classifier.zig");
const cpp_fp = @import("noise/cpp_fp_reduction.zig");
const hooks = @import("../../registry/hooks.zig");
const Language = @import("../../diag/issue.zig").FFIBoundary.Language;

// ============================================================================
// Function-Level Analysis
// ============================================================================

/// Analyze a single function for allocation and free sites.
/// Uses pre-cached IRStore data (fir.instructions + fir.opcodes) instead of
/// LLVM C API traversal for better performance.
///
/// Parameters:
///   - allocator: Memory allocator for HashMap operations
///   - fir: Pre-cached function IR from IRStore
///   - alloc_map: Output map of allocation sites (inst_id → AllocSite)
///   - free_map: Output map of free sites (inst_id → FreeSite)
///   - flow_graph: Output flow graph tracking pointer movement
///   - reverse_flow: Optional reverse flow graph for ownership transfer analysis
///   - stats: Statistics accumulator
///   - has_debug_info: Whether debug metadata is available
///   - id_map: Value ID mapping from LLVM pointers to u32 IDs
///   - alloc_pool: Memory pool for AllocSite allocations
///   - free_pool: Memory pool for FreeSite allocations
///   - null_check_recognizer: Null check pattern recognizer
pub fn analyzeFunctionForOwnership(
    allocator: std.mem.Allocator,
    fir: *const ir_store_mod.FunctionIR,
    alloc_map: *std.AutoHashMap(u32, *AllocSite),
    free_map: *std.AutoHashMap(u32, *FreeSite),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    reverse_flow: ?*std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    stats: *OwnershipStats,
    has_debug_info: bool,
    id_map: *ValueIdMap,
    alloc_pool: *MemoryPool(AllocSite),
    free_pool: *MemoryPool(FreeSite),
    null_check_recognizer: *NullCheckRecognizer,
) !void {
    const func = fir.func;
    const func_name = fir.name;

    null_check_recognizer.recognizeInFunction(func, id_map) catch {};

    for (fir.instructions, fir.opcodes) |inst, opcode| {
        try analyzeInstructionForOwnership(
            allocator,
            inst,
            opcode,
            func_name,
            alloc_map,
            free_map,
            flow_graph,
            reverse_flow,
            stats,
            has_debug_info,
            id_map,
            alloc_pool,
            free_pool,
        );
    }
}

// ============================================================================
// Ownership Transfer Checking
// ============================================================================

/// Check if allocation results are transferred to caller via return/output-param.
/// Uses pre-cached IRStore data (fir.returns[] + fir.stores[]) instead of
/// full C API instruction scan.
///
/// Marks matching AllocSites as .transferred = true.
///
/// Scans the function for:
///   1. Return instructions: marks alloc sites reaching the returned value
///   2. Store instructions to parameters: marks alloc sites stored to output params
///
/// This is used to detect ownership transfer across FFI boundaries — if a Rust
/// allocation is returned to C caller or stored to an output parameter, it
/// indicates ownership transfer that must be tracked for cross-language safety.
pub fn checkOwnershipTransferForFunction(
    fir: *const ir_store_mod.FunctionIR,
    alloc_map: *std.AutoHashMap(u32, *AllocSite),
    reverse_flow: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    id_map: *ValueIdMap,
) void {
    const func = fir.func;
    const num_params = c.LLVMCountParams(func);

    var param_value_ids: [32]u32 = undefined;
    var param_count: usize = 0;
    {
        var i: c_uint = 0;
        while (i < num_params and i < 16) : (i += 1) {
            const param = c.LLVMGetParam(func, i);
            if (@intFromPtr(param) != 0) {
                param_value_ids[param_count] = id_map.getOrPutId(@intFromPtr(param)) catch continue;
                param_count += 1;
            }
        }
    }

    // Use pre-cached returns[] instead of scanning all instructions
    for (fir.returns) |inst| {
        const num_operands: c_uint = @intCast(c.LLVMGetNumOperands(inst));
        if (num_operands > 0) {
            const ret_val = c.LLVMGetOperand(inst, 0);
            if (@intFromPtr(ret_val) != 0) {
                const ret_value_id = id_map.getOrPutId(@intFromPtr(ret_val)) catch continue;
                markAllocSitesReachingValue(alloc_map.allocator, alloc_map, reverse_flow, ret_value_id) catch {};
            }
        }
    }

    // Use pre-cached stores[] instead of scanning all instructions
    for (fir.stores) |inst| {
        if (c.LLVMGetNumOperands(inst) >= 2) {
            const store_val = c.LLVMGetOperand(inst, 0);
            const store_ptr = c.LLVMGetOperand(inst, 1);
            if (@intFromPtr(store_val) != 0 and @intFromPtr(store_ptr) != 0) {
                const ptr_value_id = id_map.getOrPutId(@intFromPtr(store_ptr)) catch continue;
                for (param_value_ids[0..param_count]) |param_id| {
                    if (ptr_value_id == param_id) {
                        const val_value_id = id_map.getOrPutId(@intFromPtr(store_val)) catch continue;
                        markAllocSitesReachingValue(alloc_map.allocator, alloc_map, reverse_flow, val_value_id) catch {};
                        break;
                    }
                }
            }
        }
    }
}

// ============================================================================
// Instruction-Level Analysis
// ============================================================================

/// Analyze a single LLVM instruction for ownership-relevant operations.
///
/// Handles three categories of instructions:
///   1. Flow graph building (store/load/bitcast/call/phi/select/gep/etc.)
///   2. Allocation detection (malloc/calloc/realloc/Rust Box::new/etc.)
///   3. Free detection (free/Rust drop/dealloc/etc.)
///
/// For call instructions, also dispatches to hooks.rustOwnershipHook for
/// Rust FFI ownership transfer tracking (into_raw/from_raw pairing).
pub fn analyzeInstructionForOwnership(
    allocator: std.mem.Allocator,
    inst: c.LLVMValueRef,
    opcode: c_uint,
    func_name: []const u8,
    alloc_map: *std.AutoHashMap(u32, *AllocSite),
    free_map: *std.AutoHashMap(u32, *FreeSite),
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    reverse_flow: ?*std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    stats: *OwnershipStats,
    has_debug_info: bool,
    id_map: *ValueIdMap,
    alloc_pool: *MemoryPool(AllocSite),
    free_pool: *MemoryPool(FreeSite),
) !void {
    const inst_id = id_map.getOrPutId(@intFromPtr(inst)) catch return;
    _ = has_debug_info;

    try buildFlowGraph(allocator, inst, opcode, flow_graph, reverse_flow, id_map);

    // Hook dispatch for call instructions (invokes rustOwnershipHook per LLVMCall)
    if (llvm_safe.isCallOrInvoke(opcode)) {
        const num_ops = c.LLVMGetNumOperands(inst);
        if (num_ops > 0) {
            const callee_val = c.LLVMGetOperand(inst, @intCast(num_ops - 1));
            if (@intFromPtr(callee_val) != 0) {
                const callee_name_raw = c.LLVMGetValueName(callee_val);
                const callee_name = if (callee_name_raw != null)
                    std.mem.span(callee_name_raw)
                else
                    "unknown";

                // Get first argument pointer value (for into_raw/from_raw pairing).
                var first_arg_ptr_val: u64 = 0;
                if (num_ops >= 1) {
                    const arg0 = c.LLVMGetOperand(inst, 0);
                    if (@intFromPtr(arg0) != 0) {
                        first_arg_ptr_val = @as(u64, @intFromPtr(arg0));
                    }
                }

                var hook_ctx = @import("../../registry/types.zig").HookContext{
                    .inst = @ptrCast(inst),
                    .callee_name = callee_name,
                    .opcode = opcode,
                    .language = "rust",
                    .first_arg_ptr_val = first_arg_ptr_val,
                };
                _ = hooks.rustOwnershipHook(&hook_ctx);
            }
        }
    }

    if (isAllocationInstruction(inst, opcode)) {
        const alloc_type = classifyAllocation(inst, opcode);
        const callee_lang = identifyLanguageFromCallee(inst, opcode);
        const site = try alloc_pool.alloc();
        const parent_bb = c.LLVMGetInstructionParent(inst);
        site.* = .{
            .inst_id = inst_id,
            .func_name = func_name,
            .lang = callee_lang,
            .alloc_type = alloc_type,
            .ptr_value_id = inst_id,
            .bb_id = id_map.getOrPutId(@intFromPtr(parent_bb)) catch inst_id,
            .source = .direct_analysis,
            .debug_file = null,
            .debug_line = null,
            .debug_column = null,
        };

        try alloc_map.put(inst_id, site);
        stats.alloc_sites += 1;
        stats.tracked_pointers += 1;
    }

    if (isFreeInstruction(inst, opcode)) {
        const free_type = classifyFree(inst, opcode);
        const callee_lang = identifyLanguageFromCallee(inst, opcode);
        const ptr_arg = c.LLVMGetOperand(inst, 0);
        const ptr_value_id: u32 = if (@intFromPtr(ptr_arg) != 0)
            id_map.getOrPutId(@intFromPtr(ptr_arg)) catch return
        else
            inst_id;

        const site = try free_pool.alloc();
        const parent_bb = c.LLVMGetInstructionParent(inst);
        site.* = .{
            .inst_id = inst_id,
            .func_name = func_name,
            .lang = callee_lang,
            .free_type = free_type,
            .ptr_value_id = ptr_value_id,
            .bb_id = id_map.getOrPutId(@intFromPtr(parent_bb)) catch inst_id,
            .source = .direct_analysis,
            .debug_file = null,
            .debug_line = null,
            .debug_column = null,
        };

        try free_map.put(inst_id, site);
        stats.free_sites += 1;
    }
}

// ============================================================================
// Flow Graph Construction
// ============================================================================

/// Build flow graph edges for a single instruction.
/// Tracks how pointers move through the program via:
///   - Store: value → pointer (pointer assignment)
///   - BitCast/PtrToInt/IntToPtr: operand → result (type conversion)
///   - Call: all operands → result (arguments flow to return value)
///   - PHI: incoming values → phi node (control flow merge)
///   - Select: true/false values → select result (conditional)
///   - GEP: base pointer → result (pointer arithmetic)
///   - ExtractValue: aggregate → result (struct/array access)
///   - InsertValue: aggregate + value → result (struct/array mutation)
///
/// Each edge represents a potential aliasing relationship that must be
/// tracked for ownership analysis (e.g., if ptr_a is freed, all aliases
/// of ptr_a become use-after-free risks).
pub fn buildFlowGraph(
    allocator: std.mem.Allocator,
    inst: c.LLVMValueRef,
    opcode: c_uint,
    flow_graph: *std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    reverse_flow: ?*std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    id_map: *ValueIdMap,
) !void {
    const inst_id = id_map.getOrPutId(@intFromPtr(inst)) catch return;

    switch (opcode) {
        c.LLVMStore => {
            const value = c.LLVMGetOperand(inst, 0);
            const ptr = c.LLVMGetOperand(inst, 1);
            if (@intFromPtr(value) != 0 and @intFromPtr(ptr) != 0) {
                const value_id = id_map.getOrPutId(@intFromPtr(value)) catch return;
                const ptr_id = id_map.getOrPutId(@intFromPtr(ptr)) catch return;
                try addFlowEdge(allocator, value_id, ptr_id, flow_graph, reverse_flow);
            }
        },
        c.LLVMLoad => {},
        c.LLVMBitCast, c.LLVMPtrToInt, c.LLVMIntToPtr => {
            const operand = c.LLVMGetOperand(inst, 0);
            if (@intFromPtr(operand) != 0) {
                const operand_id = id_map.getOrPutId(@intFromPtr(operand)) catch return;
                try addFlowEdge(allocator, operand_id, inst_id, flow_graph, reverse_flow);
            }
        },
        c.LLVMCall, c.LLVMInvoke => {
            const num_ops = c.LLVMGetNumOperands(inst);
            var i: u32 = 0;
            while (i < num_ops) : (i += 1) {
                const op = c.LLVMGetOperand(inst, i);
                if (@intFromPtr(op) != 0) {
                    const op_id = id_map.getOrPutId(@intFromPtr(op)) catch continue;
                    try addFlowEdge(allocator, op_id, inst_id, flow_graph, reverse_flow);
                }
            }
        },
        c.LLVMPHI => {
            const num_incoming = c.LLVMCountIncoming(inst);
            var i: u32 = 0;
            while (i < num_incoming) : (i += 1) {
                const incoming = c.LLVMGetIncomingValue(inst, i);
                if (@intFromPtr(incoming) != 0) {
                    const incoming_id = id_map.getOrPutId(@intFromPtr(incoming)) catch continue;
                    try addFlowEdge(allocator, incoming_id, inst_id, flow_graph, reverse_flow);
                }
            }
        },
        c.LLVMSelect => {
            const true_val = c.LLVMGetOperand(inst, 1);
            const false_val = c.LLVMGetOperand(inst, 2);
            if (@intFromPtr(true_val) != 0) {
                const true_id = id_map.getOrPutId(@intFromPtr(true_val)) catch return;
                try addFlowEdge(allocator, true_id, inst_id, flow_graph, reverse_flow);
            }
            if (@intFromPtr(false_val) != 0) {
                const false_id = id_map.getOrPutId(@intFromPtr(false_val)) catch return;
                try addFlowEdge(allocator, false_id, inst_id, flow_graph, reverse_flow);
            }
        },
        c.LLVMGetElementPtr => {
            const base_ptr = c.LLVMGetOperand(inst, 0);
            if (@intFromPtr(base_ptr) != 0) {
                const base_id = id_map.getOrPutId(@intFromPtr(base_ptr)) catch return;
                try addFlowEdge(allocator, base_id, inst_id, flow_graph, reverse_flow);
            }
        },
        c.LLVMExtractValue => {
            const aggregate = c.LLVMGetOperand(inst, 0);
            if (@intFromPtr(aggregate) != 0) {
                const agg_id = id_map.getOrPutId(@intFromPtr(aggregate)) catch return;
                try addFlowEdge(allocator, agg_id, inst_id, flow_graph, reverse_flow);
            }
        },
        c.LLVMInsertValue => {
            const aggregate = c.LLVMGetOperand(inst, 0);
            const value = c.LLVMGetOperand(inst, 1);
            if (@intFromPtr(aggregate) != 0) {
                const agg_id = id_map.getOrPutId(@intFromPtr(aggregate)) catch return;
                try addFlowEdge(allocator, agg_id, inst_id, flow_graph, reverse_flow);
            }
            if (@intFromPtr(value) != 0) {
                const val_id = id_map.getOrPutId(@intFromPtr(value)) catch return;
                try addFlowEdge(allocator, val_id, inst_id, flow_graph, reverse_flow);
            }
        },
        else => {},
    }
}

// ============================================================================
// Classification Helpers (delegates to alloc_classifier & cpp_fp)
// ============================================================================

/// Check if an instruction is an allocation (malloc/calloc/realloc/Rust alloc).
pub fn isAllocationInstruction(inst: c.LLVMValueRef, op: c_uint) bool {
    return alloc_classifier.isAllocationInstruction(inst, op);
}

/// Classify the type of allocation (heap/rust_box_into_raw/etc.).
pub fn classifyAllocation(inst: c.LLVMValueRef, op: c_uint) AllocType {
    return alloc_classifier.classifyAllocation(inst, op);
}

/// Identify the language of the callee from the instruction.
pub fn identifyLanguageFromCallee(inst: c.LLVMValueRef, op: c_uint) Language {
    return alloc_classifier.identifyLanguageFromCallee(inst, op);
}

/// Check if an instruction is a free operation (free/delete/Rust dealloc).
pub fn isFreeInstruction(inst: c.LLVMValueRef, op: c_uint) bool {
    return alloc_classifier.isFreeInstruction(inst, op);
}

/// Classify the type of free (free/delete/custom).
pub fn classifyFree(inst: c.LLVMValueRef, op: c_uint) FreeType {
    return alloc_classifier.classifyFree(inst, op);
}

/// Get the name of a function from its LLVM value reference.
pub fn getFunctionName(func: c.LLVMValueRef) []const u8 {
    return @import("../../ir/ir_helpers.zig").getFunctionName(func);
}
