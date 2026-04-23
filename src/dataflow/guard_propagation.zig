//! CFG-Based Null Check Guard Propagation
//!
//! This module propagates null check constraints through the CFG to enable
//! path-sensitive lifetime analysis.
//!
//! Key insight: When we have `if (p == NULL) { ... } else { ... }`:
//! - In true branch: p is guaranteed null
//! - In false branch: p is guaranteed non-null
//!
//! This information propagates through phi nodes when control flow merges.

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const NullCheckRecognizer = @import("null_check_guard.zig").NullCheckRecognizer;
const ValueIdMap = @import("value_id_map.zig").ValueIdMap;
const lifetime = @import("../lifetime/root.zig");

const Allocator = std.mem.Allocator;

pub const PtrConstraint = struct {
    ptr_id: u32,
    state: lifetime.LifetimeState,
};

pub const GuardPropagation = struct {
    allocator: Allocator,
    constraint_maps: std.AutoHashMap(usize, std.ArrayList(PtrConstraint)),
    bb_null_ptrs: std.AutoHashMap(usize, std.AutoHashMap(u32, void)),
    bb_non_null_ptrs: std.AutoHashMap(usize, std.AutoHashMap(u32, void)),

    pub fn init(allocator: Allocator) GuardPropagation {
        return .{
            .allocator = allocator,
            .constraint_maps = std.AutoHashMap(usize, std.ArrayList(PtrConstraint)).init(allocator),
            .bb_null_ptrs = std.AutoHashMap(usize, std.AutoHashMap(u32, void)).init(allocator),
            .bb_non_null_ptrs = std.AutoHashMap(usize, std.AutoHashMap(u32, void)).init(allocator),
        };
    }

    pub fn deinit(self: *GuardPropagation) void {
        var maps_iter = self.constraint_maps.iterator();
        while (maps_iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.constraint_maps.deinit();

        var null_iter = self.bb_null_ptrs.iterator();
        while (null_iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.bb_null_ptrs.deinit();

        var non_null_iter = self.bb_non_null_ptrs.iterator();
        while (non_null_iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.bb_non_null_ptrs.deinit();
    }

    pub fn propagate(self: *GuardPropagation, func: c.LLVMValueRef, recognizer: *NullCheckRecognizer) !void {
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            const bb_id = @intFromPtr(bb);
            try self.propagateFromBasicBlock(bb, bb_id, recognizer);
        }

        try self.propagateThroughPhis(func);
    }

    fn propagateFromBasicBlock(
        self: *GuardPropagation,
        bb: c.LLVMBasicBlockRef,
        bb_id: usize,
        recognizer: *NullCheckRecognizer,
    ) !void {
        if (recognizer.getGuardForBlock(@intFromPtr(bb))) |guard| {
            const true_bb_id = guard.branch_bb_id;
            const false_bb_id = guard.other_bb_id;

            if (true_bb_id == bb_id) {
                try self.addNullPtr(true_bb_id, guard.value_id);
                try self.addNonNullPtr(false_bb_id, guard.value_id);
            } else {
                try self.addNonNullPtr(true_bb_id, guard.value_id);
                try self.addNullPtr(false_bb_id, guard.value_id);
            }
        }
    }

    fn propagateThroughPhis(self: *GuardPropagation, func: c.LLVMValueRef) !void {
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            const bb_id = @intFromPtr(bb);
            try self.propagatePhiConstraints(bb, bb_id);
        }
    }

    fn propagatePhiConstraints(self: *GuardPropagation, bb: c.LLVMBasicBlockRef, bb_id: usize) !void {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            if (opcode != c.LLVMPHI) continue;

            const num_preds = c.LLVMCountIncoming(inst);
            var has_null = false;
            var has_non_null = false;

            var pred_idx: u32 = 0;
            while (pred_idx < num_preds) : (pred_idx += 1) {
                const pred_bb = c.LLVMGetIncomingBlock(inst, pred_idx);
                const pred_bb_id = @intFromPtr(pred_bb);

                const value = c.LLVMGetIncomingValue(inst, pred_idx);
                const value_id: u32 = @truncate(@intFromPtr(value));

                if (self.isPtrNullAtBlock(pred_bb_id, value_id)) {
                    has_null = true;
                }
                if (self.isPtrNonNullAtBlock(pred_bb_id, value_id)) {
                    has_non_null = true;
                }
            }

            const result_id: u32 = @truncate(@intFromPtr(inst));
            if (has_null and has_non_null) {
                try self.mergeConstraint(bb_id, result_id, .unknown);
            } else if (has_null) {
                try self.mergeConstraint(bb_id, result_id, .freed);
            } else if (has_non_null) {
                try self.mergeConstraint(bb_id, result_id, .live);
            }
        }
    }

    fn mergeConstraint(self: *GuardPropagation, bb_id: usize, ptr_id: u32, state: lifetime.LifetimeState) !void {
        switch (state) {
            .freed => try self.addNullPtr(bb_id, ptr_id),
            .live => try self.addNonNullPtr(bb_id, ptr_id),
            else => {},
        }
    }

    fn addNullPtr(self: *GuardPropagation, bb_id: usize, ptr_id: u32) !void {
        const entry = try self.bb_null_ptrs.getOrPut(bb_id);
        if (!entry.found_existing) {
            entry.value_ptr.* = std.AutoHashMap(u32, void).init(self.allocator);
        }
        try entry.value_ptr.*.put(ptr_id, {});
    }

    fn addNonNullPtr(self: *GuardPropagation, bb_id: usize, ptr_id: u32) !void {
        const entry = try self.bb_non_null_ptrs.getOrPut(bb_id);
        if (!entry.found_existing) {
            entry.value_ptr.* = std.AutoHashMap(u32, void).init(self.allocator);
        }
        try entry.value_ptr.*.put(ptr_id, {});
    }

    pub fn isPtrNullAtBlock(self: *GuardPropagation, bb_id: usize, ptr_id: u32) bool {
        if (self.bb_null_ptrs.get(bb_id)) |null_ptrs| {
            return null_ptrs.contains(ptr_id);
        }
        return false;
    }

    pub fn isPtrNonNullAtBlock(self: *GuardPropagation, bb_id: usize, ptr_id: u32) bool {
        if (self.bb_non_null_ptrs.get(bb_id)) |non_null_ptrs| {
            return non_null_ptrs.contains(ptr_id);
        }
        return false;
    }

    pub fn getPtrStateAtBlock(self: *GuardPropagation, bb_id: usize, ptr_id: u32) lifetime.LifetimeState {
        if (self.isPtrNullAtBlock(bb_id, ptr_id)) {
            return .freed;
        }
        if (self.isPtrNonNullAtBlock(bb_id, ptr_id)) {
            return .live;
        }
        return .unknown;
    }
};

test "GuardPropagation - init and deinit" {
    var propagation = GuardPropagation.init(std.testing.allocator);
    defer propagation.deinit();
    try std.testing.expectEqual(@as(usize, 0), propagation.bb_null_ptrs.count());
}

test "GuardPropagation - add and query null ptr" {
    var propagation = GuardPropagation.init(std.testing.allocator);
    defer propagation.deinit();

    try propagation.addNullPtr(100, 42);
    try std.testing.expect(propagation.isPtrNullAtBlock(100, 42));
    try std.testing.expect(!propagation.isPtrNonNullAtBlock(100, 42));
    try std.testing.expectEqual(lifetime.LifetimeState.freed, propagation.getPtrStateAtBlock(100, 42));
}

test "GuardPropagation - add and query non-null ptr" {
    var propagation = GuardPropagation.init(std.testing.allocator);
    defer propagation.deinit();

    try propagation.addNonNullPtr(100, 42);
    try std.testing.expect(propagation.isPtrNonNullAtBlock(100, 42));
    try std.testing.expect(!propagation.isPtrNullAtBlock(100, 42));
    try std.testing.expectEqual(lifetime.LifetimeState.live, propagation.getPtrStateAtBlock(100, 42));
}

test "GuardPropagation - unknown state for untracked ptr" {
    var propagation = GuardPropagation.init(std.testing.allocator);
    defer propagation.deinit();

    try std.testing.expectEqual(lifetime.LifetimeState.unknown, propagation.getPtrStateAtBlock(100, 42));
}
