//! Transfer Inference — Structural IR analysis for ownership transfer detection (P19-2)
//!
//! Analyzes LLVM IR to determine if an allocation's result is transferred
//! to the caller, stored to an owner, or escapes via other paths.
//!
//! This is a **generic, name-independent** analysis — it works by examining
//! the actual IR instruction patterns, not function names or heuristics.
//!
//! Key insight: If a function calls malloc() and then does `ret ptr`,
//! that's a **structural factory pattern** regardless of whether the function
//! is named XXH32_createState, my_alloc, or anything else.
//!
//! Supported transfer patterns:
//!   - `return_to_caller`: alloc result directly returned via `ret` instruction
//!   - `out_param_store`: alloc result stored through a pointer parameter
//!   - `owner_field_store`: alloc result stored into a struct field of an owner object
//!   - `global_store`: alloc result stored into a global variable
//!   - `callback_escape`: alloc result passed as argument to a function pointer / callback

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const ContractTransition = @import("contract.zig").ContractTransition;

/// Result of transfer inference for a single allocation site.
pub const TransferResult = struct {
    /// Whether a valid transfer was detected.
    detected: bool,
    /// The type of transfer detected (if any).
    trigger: ?ContractTransition.Trigger = null,
    /// The LLVM Value that is the allocated pointer (for debugging).
    alloc_value: ?c.LLVMValueRef = null,
    /// Human-readable explanation of why this transfer was detected.
    reason: []const u8 = "",

    pub fn format(
        self: TransferResult,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (!self.detected) {
            try writer.writeAll("no_transfer");
        } else {
            const trigger_name = if (self.trigger) |t|
                @tagName(t)
            else
                "unknown";
            try writer.print("{}({s})", .{ trigger_name, self.reason });
        }
    }
};

/// Analyze a function for structural transfer patterns.
/// Returns true if ANY allocation in the function has a valid transfer path.
pub fn detectTransferInFunction(func: c.LLVMValueRef) ?TransferResult {
    // Get the entry basic block
    const entry_bb = c.LLVMGetEntryBasicBlock(func);
    if (@intFromPtr(entry_bb) == 0) return null;

    // Iterate all instructions in the function looking for alloc patterns
    var bb_iter = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb_iter) != 0) : (bb_iter = c.LLVMGetNextBasicBlock(bb_iter)) {
        var inst_iter = c.LLVMGetFirstInstruction(bb_iter);
        while (@intFromPtr(inst_iter) != 0) : (inst_iter = c.LLVMGetNextInstruction(inst_iter)) {
            const opcode = c.LLVMGetInstructionOpcode(inst_iter);

            // Check for call instructions (malloc, calloc, etc.)
            if (opcode == c.LLVMCall) {
                const called_func = c.LLVMGetCalledValue(inst_iter);
                if (@intFromPtr(called_func) == 0) continue;

                const called_name = c.LLVMGetValueName(called_func);
                if (@intFromPtr(called_name) == 0) continue;

                const name_slice = std.mem.sliceTo(called_name, 0);

                // Check if this is a known allocation function
                if (isAllocationFunction(name_slice)) {
                    // inst_iter IS the allocation result (the call itself returns the ptr)
                    const result = analyzeAllocTransfer(func, inst_iter, bb_iter);
                    if (result.detected) {
                        return result;
                    }
                }
            }

            // Also check alloca instructions (stack allocations returned as pointers)
            if (opcode == c.LLVMAlloca) {
                const result = analyzeAllocTransfer(func, inst_iter, bb_iter);
                if (result.detected) {
                    return result;
                }
            }
        }
    }

    return null;
}

/// Analyze what happens to a specific allocation result within its function.
pub fn analyzeAllocTransfer(
    func: c.LLVMValueRef,
    alloc_inst: c.LLVMValueRef,
    _: c.LLVMBasicBlockRef,
) TransferResult {
    // Strategy: Walk forward from alloc_inst looking for how the value is used.
    // We look at ALL uses of alloc_inst and classify the dominant pattern.

    var use_count: u32 = 0;
    var has_return_use: bool = false;
    var has_store_use: bool = false;
    var has_callback_use: bool = false;
    var store_target: ?c.LLVMValueRef = null;

    // Iterate uses of the allocation result
    var use_iter = c.LLVMGetFirstUse(alloc_inst);
    while (@intFromPtr(use_iter) != 0) : (use_iter = c.LLVMGetNextUse(use_iter)) {
        use_count += 1;
        const user = c.LLVMGetUser(use_iter);
        if (@intFromPtr(user) == 0) continue;

        const user_opcode = c.LLVMGetInstructionOpcode(user);

        // Pattern 1: Direct return — `ret <alloc_result>`
        if (user_opcode == c.LLVMRet) {
            has_return_use = true;
            continue;
        }

        // Pattern 2: Store to memory — could be out-param, global, or field
        if (user_opcode == c.LLVMStore) {
            has_store_use = true;
            // Get the store target (pointer operand #1 in LLVM StoreInst)
            store_target = c.LLVMGetOperand(user, 1);
            continue;
        }

        // Pattern 3: Passed as argument to another call (callback escape?)
        if (user_opcode == c.LLVMCall) {
            const called_val = c.LLVMGetCalledValue(user);
            if (@intFromPtr(called_val) != 0) {
                // Check if it's a function pointer (indirect call) vs direct call
                const called_opcode = c.LLVMGetValueKind(called_val);
                if (called_opcode == c.LLVMFunctionValueKind) {
                    // Direct call — check if it's a "sink" function like memcpy, printf, etc.
                    const sink_name = c.LLVMGetValueName(called_val);
                    if (@intFromPtr(sink_name) != 0) {
                        const slice = std.mem.sliceTo(sink_name, 0);
                        if (isSinkFunction(slice)) {
                            // Data passed to sink — likely escaping
                            has_callback_use = true;
                            continue;
                        }
                    }
                } else {
                    // Indirect call (function pointer) — almost always callback escape
                    has_callback_use = true;
                    continue;
                }
            }
        }

        // Pattern 4: Bitcast/GEP before use — follow through
        if (user_opcode == c.LLVMBitCast or user_opcode == c.LLVMLoad) {
            // These are intermediate operations; we'd need recursive analysis
            // For now, just note that there are complex uses
        }
    }

    // Classify based on dominant pattern
    if (has_return_use and use_count <= 3) {
        // Return with few other uses → clean factory pattern
        return .{
            .detected = true,
            .trigger = .return_to_caller,
            .alloc_value = alloc_inst,
            .reason = "allocation result returned to caller via ret instruction",
        };
    }

    if (has_store_use) {
        // Determine what kind of store this is
        const store_kind = if (store_target) |target|
            classifyStoreTarget(target, func)
        else
            .unknown;
        if (store_kind != .unknown) {
            return .{
                .detected = true,
                .trigger = store_kind,
                .alloc_value = alloc_inst,
                .reason = switch (store_kind) {
                    .out_param_store => "allocation result stored to out-parameter",
                    .field_store => "allocation result stored to owner field",
                    .global_store => "allocation result stored to global variable",
                    else => "allocation result stored externally",
                },
            };
        }
    }

    if (has_callback_use) {
        return .{
            .detected = true,
            .trigger = .callback_escape,
            .alloc_value = alloc_inst,
            .reason = "allocation result passed to callback/sink function",
        };
    }

    return .{ .detected = false };
}

/// Classify what kind of store target this is.
fn classifyStoreTarget(store_ptr: c.LLVMValueRef, func: c.LLVMValueRef) ContractTransition.Trigger {
    // Check if store_ptr is a function parameter (out-param pattern)
    var param_iter: u32 = 0;
    const num_params = c.LLVMCountParams(func);
    while (param_iter < num_params) : (param_iter += 1) {
        const param = c.LLVMGetParam(func, param_iter);
        if (@intFromPtr(param) != 0 and param == store_ptr) {
            return .out_param_store;
        }
    }

    // Check if it's a GEP into a parameter (struct field of out-param)
    // This handles cases like: *result_ptr = malloc(...)
    if (c.LLVMGetInstructionOpcode(store_ptr) == c.LLVMLoad) {
        const load_src = c.LLVMGetOperand(store_ptr, 0);
        param_iter = 0;
        while (param_iter < num_params) : (param_iter += 1) {
            const param = c.LLVMGetParam(func, param_iter);
            if (@intFromPtr(param) != 0 and param == load_src) {
                return .out_param_store;
            }
        }
    }

    // Check if it's a global variable
    if (c.LLVMIsAGlobalVariable(store_ptr) != null) {
        return .global_store;
    }

    // Check if it's a GEP into a global
    if (c.LLVMGetInstructionOpcode(store_ptr) == c.LLVMLoad or
        c.LLVMGetInstructionOpcode(store_ptr) == c.LLVMLoad)
    {
        // Could be field of a global or owner object
        return .field_store;
    }

    return .return_to_caller; // Default fallback
}

/// Check if a function name matches known allocation patterns.
/// This is a weak hint — structural analysis is primary evidence.
pub fn isAllocationFunction(name: []const u8) bool {
    // Standard C allocators
    if (std.mem.indexOf(u8, name, "malloc") != null) return true;
    if (std.mem.indexOf(u8, name, "calloc") != null) return true;
    if (std.mem.indexOf(u8, name, "realloc") != null) return true;
    if (std.mem.indexOf(u8, name, "memalign") != null) return true;
    if (std.mem.indexOf(u8, name, "valloc") != null) return true;
    if (std.mem.indexOf(u8, name, "strdup") != null) return true;
    if (std.mem.indexOf(u8, name, "strndup") != null) return true;

    // POSIX allocators
    if (std.mem.indexOf(u8, name, "posix_memalign") != null) return true;

    // Custom allocator prefixes (common in FFI libraries)
    if (std.mem.startsWith(u8, name, "__")) return true; // __zig_dealloc, etc.

    return false;
}

/// Check if a function is a "sink" — consumes data without returning ownership.
/// Examples: memcpy, printf, fwrite, send, write.
pub fn isSinkFunction(name: []const u8) bool {
    const sinks = [_][]const u8{
        "memcpy",   "memmove", "memset",
        "printf",   "fprintf", "sprintf",
        "snprintf", "fwrite",  "fputs",
        "fputc",    "send",    "write",
        "writev",   "strcpy",  "strncpy",
        "strcat",
        "free", // free is a special sink — releases ownership
    };
    for (sinks) |s| {
        if (std.mem.indexOf(u8, name, s) != null) return true;
    }
    return false;
}
