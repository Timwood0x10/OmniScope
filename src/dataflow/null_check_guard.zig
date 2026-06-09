//! NULL Check Guard Recognition
//!
//! Recognizes the pattern: `icmp eq/ne ptr null` + `br` to identify
//! null pointer checks that guard certain code paths.
//!
//! This enables path-sensitive analysis where:
//! - true branch (null): pointer is null
//! - false branch (non-null): pointer is non-null

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const PathCondition = @import("path_condition.zig").PathCondition;
const ValueIdMap = @import("value_id_map.zig").ValueIdMap;

const Allocator = std.mem.Allocator;

pub const NullCheckGuard = struct {
    value_id: u32,
    cmp_result_id: u32,
    is_not_null_branch: bool,
    branch_bb_id: usize,
    other_bb_id: usize,
};

pub const NullCheckRecognizer = struct {
    allocator: Allocator,
    guards: std.ArrayList(NullCheckGuard),

    pub fn init(allocator: Allocator) NullCheckRecognizer {
        return .{
            .allocator = allocator,
            .guards = std.ArrayList(NullCheckGuard).initCapacity(allocator, 8) catch @panic("OOM"),
        };
    }

    pub fn deinit(self: *NullCheckRecognizer) void {
        self.guards.deinit(self.allocator);
    }

    pub fn recognizeInFunction(self: *NullCheckRecognizer, func: c.LLVMValueRef, id_map: *ValueIdMap) !void {
        if (func == null) return;

        // Pass 1: collect all store instructions (alloca/global → stored value)
        var stores = std.AutoHashMap(c.LLVMValueRef, c.LLVMValueRef).init(self.allocator);
        defer stores.deinit();

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                if (c.LLVMGetInstructionOpcode(inst) == c.LLVMStore) {
                    const val = c.LLVMGetOperand(inst, 0); // value being stored
                    const ptr = c.LLVMGetOperand(inst, 1); // pointer to store to
                    if (val != null and ptr != null) {
                        try stores.put(ptr, val);
                    }
                }
            }
        }

        // Pass 2: recognize null check guards
        bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            try self.recognizeInBasicBlock(bb, id_map, &stores);
        }
    }

    pub fn recognizeInBasicBlock(self: *NullCheckRecognizer, bb: c.LLVMBasicBlockRef, id_map: *ValueIdMap, stores: *const std.AutoHashMap(c.LLVMValueRef, c.LLVMValueRef)) !void {
        const terminator = c.LLVMGetBasicBlockTerminator(bb);
        if (terminator == null) return;

        const term_opcode = c.LLVMGetInstructionOpcode(terminator);
        if (term_opcode != c.LLVMBr) return;

        const num_operands = c.LLVMGetNumOperands(terminator);
        if (num_operands != 3) return;

        const cond_value = c.LLVMGetOperand(terminator, 0);
        if (cond_value == null) return;

        const cond_instr = c.LLVMIsAInstruction(cond_value);
        if (cond_instr == null) return;

        const cond_opcode = c.LLVMGetInstructionOpcode(cond_instr);
        if (cond_opcode != c.LLVMICmp) return;

        const predicate = c.LLVMGetICmpPredicate(cond_instr);
        const is_eq = (predicate == c.LLVMIntEQ);
        const is_ne = (predicate == c.LLVMIntNE);
        if (!is_eq and !is_ne) return;

        const op0 = c.LLVMGetOperand(cond_instr, 0);
        const op1 = c.LLVMGetOperand(cond_instr, 1);

        var ptr_value: c.LLVMValueRef = undefined;
        if (c.LLVMIsNull(op0) != 0) {
            ptr_value = op1;
        } else if (c.LLVMIsNull(op1) != 0) {
            ptr_value = op0;
        } else {
            return;
        }

        const ptr_id = try id_map.getOrPutId(@intFromPtr(ptr_value));

        const true_bb = c.LLVMGetOperand(terminator, 1);
        const false_bb = c.LLVMGetOperand(terminator, 2);

        const cmp_result_id = try id_map.getOrPutId(@intFromPtr(cond_instr));

        try self.guards.append(self.allocator, .{
            .value_id = ptr_id,
            .cmp_result_id = cmp_result_id,
            .is_not_null_branch = is_ne,
            .branch_bb_id = @intFromPtr(true_bb),
            .other_bb_id = @intFromPtr(false_bb),
        });

        // Handle store/load chain: if ptr_value comes from a Load instruction,
        // trace back through stores and register a guard for the stored value too.
        if (c.LLVMGetInstructionOpcode(ptr_value) == c.LLVMLoad) {
            const loaded_ptr = c.LLVMGetOperand(ptr_value, 0);
            if (loaded_ptr != null) {
                // Look up alloca/global in the stores map to find the original stored value
                if (stores.get(loaded_ptr)) |stored_val| {
                    const stored_val_id = try id_map.getOrPutId(@intFromPtr(stored_val));
                    // Only add if not already guarded (avoid duplicate entries)
                    var already_guarded = false;
                    for (self.guards.items) |g| {
                        if (g.value_id == stored_val_id) {
                            already_guarded = true;
                            break;
                        }
                    }
                    if (!already_guarded) {
                        try self.guards.append(self.allocator, .{
                            .value_id = stored_val_id,
                            .cmp_result_id = cmp_result_id,
                            .is_not_null_branch = is_ne,
                            .branch_bb_id = @intFromPtr(true_bb),
                            .other_bb_id = @intFromPtr(false_bb),
                        });
                    }
                }
            }
        }
    }

    pub fn getGuardForBlock(self: *NullCheckRecognizer, bb_id: usize) ?NullCheckGuard {
        for (self.guards.items) |guard| {
            if (guard.branch_bb_id == bb_id or guard.other_bb_id == bb_id) {
                return guard;
            }
        }
        return null;
    }

    pub fn isPtrGuardedNonNull(self: *NullCheckRecognizer, bb_id: usize, ptr_id: u32) bool {
        const guard = self.getGuardForBlock(bb_id) orelse return false;
        if (guard.value_id != ptr_id) return false;
        if (guard.branch_bb_id == bb_id) {
            return guard.is_not_null_branch;
        } else {
            return !guard.is_not_null_branch;
        }
    }

    pub fn isPtrGuardedNull(self: *NullCheckRecognizer, bb_id: usize, ptr_id: u32) bool {
        const guard = self.getGuardForBlock(bb_id) orelse return false;
        if (guard.value_id != ptr_id) return false;
        if (guard.branch_bb_id == bb_id) {
            return !guard.is_not_null_branch;
        } else {
            return guard.is_not_null_branch;
        }
    }

    /// Check if ANY null guard in the function covers this pointer value.
    /// Unlike isPtrGuardedNonNull (which checks a specific BB), this checks
    /// all guards regardless of their branch target.
    pub fn isPtrGuardedNonNull_byValue(self: *NullCheckRecognizer, value_id: u32) bool {
        for (self.guards.items) |guard| {
            if (guard.value_id == value_id) {
                return true;
            }
        }
        return false;
    }
};

test "NullCheckRecognizer - init and deinit" {
    var recognizer = NullCheckRecognizer.init(std.testing.allocator);
    defer recognizer.deinit();
    try std.testing.expectEqual(@as(usize, 0), recognizer.guards.items.len);
}

test "NullCheckRecognizer - empty function analysis" {
    var recognizer = NullCheckRecognizer.init(std.testing.allocator);
    defer recognizer.deinit();

    var id_map = ValueIdMap.init(std.testing.allocator);
    defer id_map.deinit();

    try recognizer.recognizeInFunction(null, &id_map);
    try std.testing.expectEqual(@as(usize, 0), recognizer.guards.items.len);
}

test "NullCheckGuard - struct fields" {
    const guard = NullCheckGuard{
        .value_id = 42,
        .cmp_result_id = 43,
        .is_not_null_branch = true,
        .branch_bb_id = 100,
        .other_bb_id = 200,
    };

    try std.testing.expectEqual(@as(u32, 42), guard.value_id);
    try std.testing.expectEqual(@as(u32, 43), guard.cmp_result_id);
    try std.testing.expect(guard.is_not_null_branch);
    try std.testing.expectEqual(@as(usize, 100), guard.branch_bb_id);
    try std.testing.expectEqual(@as(usize, 200), guard.other_bb_id);
}

test "NullCheckRecognizer - isPtrGuardedNonNull without guards" {
    var recognizer = NullCheckRecognizer.init(std.testing.allocator);
    defer recognizer.deinit();

    try std.testing.expect(!recognizer.isPtrGuardedNonNull(100, 42));
    try std.testing.expect(!recognizer.isPtrGuardedNull(100, 42));
}
