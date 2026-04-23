//! Steensgaard Points-To Analysis
//!
//! Implements a flow-insensitive, context-insensitive points-to analysis
//! based on Steensgaard's algorithm using union-find.
//!
//! Key concepts:
//! - Address-taken variables: variables that have their address taken (&x)
//! - Points-to relations: p = &q means p points to q
//! - Indirect assignment: *p = q means p's points-to set includes q
//!
//! Algorithm:
//! 1. ConstraintGen: Generate constraints from LLVM IR instructions
//! 2. UnionFind: Merge equivalence classes based on constraints
//! 3. PointsTo: Compute points-to sets from merged classes

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;
const ValueIdMap = @import("../../dataflow/value_id_map.zig").ValueIdMap;

const Allocator = std.mem.Allocator;

pub const Constraint = struct {
    lhs: u32,
    rhs: u32,
    kind: ConstraintKind,
};

pub const ConstraintKind = enum(u8) {
    address_of,
    assign,
    indirect,
};

pub const ConstraintGen = struct {
    allocator: Allocator,
    constraints: std.ArrayList(Constraint),

    pub fn init(allocator: Allocator) ConstraintGen {
        return .{
            .allocator = allocator,
            .constraints = std.ArrayList(Constraint).init(allocator),
        };
    }

    pub fn deinit(self: *ConstraintGen) void {
        self.constraints.deinit();
    }

    pub fn generate(self: *ConstraintGen, func: c.LLVMValueRef, id_map: *ValueIdMap) !void {
        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                try self.generateFromInstruction(inst, id_map);
            }
        }
    }

    fn generateFromInstruction(self: *ConstraintGen, inst: c.LLVMValueRef, id_map: *ValueIdMap) !void {
        const opcode = c.LLVMGetInstructionOpcode(inst);
        const opcode_enum: c.LLVMOpcode = @enumFromInt(opcode);

        switch (opcode_enum) {
            .Store => try self.handleStore(inst, id_map),
            .Load => try self.handleLoad(inst, id_map),
            .Alloca => try self.handleAlloca(inst, id_map),
            .GetElementPtr => try self.handleGEP(inst, id_map),
            .BitCast, .PtrToInt, .IntToPtr => try self.handleCast(inst, id_map),
            .Call => try self.handleCall(inst, id_map),
            else => {},
        }
    }

    fn handleStore(self: *ConstraintGen, inst: c.LLVMValueRef, id_map: *ValueIdMap) !void {
        const num_ops = c.LLVMGetNumOperands(inst);
        if (num_ops < 2) return;

        const value = c.LLVMGetOperand(inst, 0);
        const ptr = c.LLVMGetOperand(inst, 1);

        if (value == null or ptr == null) return;

        const value_id = try id_map.getOrPutId(@intFromPtr(value));
        const ptr_id = try id_map.getOrPutId(@intFromPtr(ptr));

        try self.constraints.append(.{ .lhs = ptr_id, .rhs = value_id, .kind = .indirect });
    }

    fn handleLoad(self: *ConstraintGen, inst: c.LLVMValueRef, id_map: *ValueIdMap) !void {
        const num_ops = c.LLVMGetNumOperands(inst);
        if (num_ops < 1) return;

        const ptr = c.LLVMGetOperand(inst, 0);
        if (ptr == null) return;

        const ptr_id = try id_map.getOrPutId(@intFromPtr(ptr));
        const result_id = try id_map.getOrPutId(@intFromPtr(inst));

        try self.constraints.append(.{ .lhs = result_id, .rhs = ptr_id, .kind = .assign });
    }

    fn handleAlloca(self: *ConstraintGen, inst: c.LLVMValueRef, id_map: *ValueIdMap) !void {
        const result_id = try id_map.getOrPutId(@intFromPtr(inst));
        const alloca_id = try id_map.getOrPutId(@intFromPtr(inst) + 1);
        try self.constraints.append(.{ .lhs = result_id, .rhs = alloca_id, .kind = .address_of });
    }

    fn handleGEP(self: *ConstraintGen, inst: c.LLVMValueRef, id_map: *ValueIdMap) !void {
        const num_ops = c.LLVMGetNumOperands(inst);
        if (num_ops < 1) return;

        const ptr = c.LLVMGetOperand(inst, 0);
        if (ptr == null) return;

        const ptr_id = try id_map.getOrPutId(@intFromPtr(ptr));
        const result_id = try id_map.getOrPutId(@intFromPtr(inst));

        try self.constraints.append(.{ .lhs = result_id, .rhs = ptr_id, .kind = .assign });
    }

    fn handleCast(self: *ConstraintGen, inst: c.LLVMValueRef, id_map: *ValueIdMap) !void {
        const num_ops = c.LLVMGetNumOperands(inst);
        if (num_ops < 1) return;

        const val = c.LLVMGetOperand(inst, 0);
        if (val == null) return;

        const val_id = try id_map.getOrPutId(@intFromPtr(val));
        const result_id = try id_map.getOrPutId(@intFromPtr(inst));

        try self.constraints.append(.{ .lhs = result_id, .rhs = val_id, .kind = .assign });
    }

    fn handleCall(self: *ConstraintGen, inst: c.LLVMValueRef, id_map: *ValueIdMap) !void {
        const called_func = c.LLVMGetCalledFunction(inst);
        if (called_func == null) return;

        const num_args = c.LLVMGetNumOperands(inst);
        const result_id = try id_map.getOrPutId(@intFromPtr(inst));

        const callee = c.LLVMGetOperand(inst, num_args - 1);
        if (callee == null) return;
        const callee_id = try id_map.getOrPutId(@intFromPtr(callee));

        for (0..num_args - 1) |i| {
            const arg = c.LLVMGetOperand(inst, @intCast(i));
            if (arg == null) continue;
            const arg_id = try id_map.getOrPutId(@intFromPtr(arg));
            try self.constraints.append(.{ .lhs = callee_id, .rhs = arg_id, .kind = .indirect });
        }

        try self.constraints.append(.{ .lhs = result_id, .rhs = callee_id, .kind = .assign });
    }
};

pub const UnionFind = struct {
    parent: std.AutoHashMap(u32, u32),
    rank: std.AutoHashMap(u32, u8),

    pub fn init(allocator: Allocator) UnionFind {
        return .{
            .parent = std.AutoHashMap(u32, u32).init(allocator),
            .rank = std.AutoHashMap(u32, u8).init(allocator),
        };
    }

    pub fn deinit(self: *UnionFind) void {
        self.parent.deinit();
        self.rank.deinit();
    }

    pub fn makeSet(self: *UnionFind, x: u32) !void {
        if (!self.parent.contains(x)) {
            try self.parent.put(x, x);
            try self.rank.put(x, 0);
        }
    }

    pub fn find(self: *UnionFind, x: u32) u32 {
        if (self.parent.get(x)) |p| {
            if (p == x) {
                return x;
            }
            const root = self.find(p);
            self.parent.put(x, root) catch {}; // Path compression best-effort; failure only affects perf
            return root;
        }
        return x;
    }

    pub fn unite(self: *UnionFind, x: u32, y: u32) !void {
        const root_x = self.find(x);
        const root_y = self.find(y);

        if (root_x == root_y) return;

        const rank_x = self.rank.get(root_x) orelse 0;
        const rank_y = self.rank.get(root_y) orelse 0;

        if (rank_x < rank_y) {
            try self.parent.put(root_x, root_y);
        } else if (rank_x > rank_y) {
            try self.parent.put(root_y, root_x);
        } else {
            try self.parent.put(root_y, root_x);
            const new_rank = rank_x + 1;
            self.rank.put(root_x, new_rank) catch {}; // Rank update best-effort; failure only degrades tree balance
        }
    }
};

pub const PointsToAnalysis = struct {
    allocator: Allocator,
    union_find: UnionFind,
    points_to: std.AutoHashMap(u32, std.AutoHashMap(u32, void)),
    address_taken: std.AutoHashMap(u32, void),

    pub fn init(allocator: Allocator) PointsToAnalysis {
        return .{
            .allocator = allocator,
            .union_find = UnionFind.init(allocator),
            .points_to = std.AutoHashMap(u32, std.AutoHashMap(u32, void)).init(allocator),
            .address_taken = std.AutoHashMap(u32, void).init(allocator),
        };
    }

    pub fn deinit(self: *PointsToAnalysis) void {
        self.union_find.deinit();

        var iter = self.points_to.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.points_to.deinit();

        self.address_taken.deinit();
    }

    pub fn analyze(self: *PointsToAnalysis, constraints: []const Constraint) !void {
        for (constraints) |constraint| {
            try self.union_find.makeSet(constraint.lhs);
            try self.union_find.makeSet(constraint.rhs);

            switch (constraint.kind) {
                .address_of => {
                    try self.address_taken.put(constraint.rhs, {});
                    try self.addPointsTo(constraint.lhs, constraint.rhs);
                },
                .assign => {
                    try self.union_find.unite(constraint.lhs, constraint.rhs);
                },
                .indirect => {
                    try self.union_find.unite(constraint.lhs, constraint.rhs);
                },
            }
        }
    }

    fn addPointsTo(self: *PointsToAnalysis, pointer: u32, target: u32) !void {
        const entry = try self.points_to.getOrPut(pointer);
        if (!entry.found_existing) {
            entry.value_ptr.* = std.AutoHashMap(u32, void).init(self.allocator);
        }
        try entry.value_ptr.*.put(target, {});
    }

    pub fn getPointsTo(self: *const PointsToAnalysis, pointer: u32) []const u32 {
        const root = self.union_find.find(pointer);
        if (self.points_to.get(root)) |set| {
            return set.keys();
        }
        return &[_]u32{};
    }

    pub fn mayAlias(self: *PointsToAnalysis, p: u32, q: u32) bool {
        const root_p = self.union_find.find(p);
        const root_q = self.union_find.find(q);
        return root_p == root_q;
    }
};

test "UnionFind - makeSet, find, unite" {
    var uf = UnionFind.init(std.testing.allocator);
    defer uf.deinit();

    try uf.makeSet(1);
    try uf.makeSet(2);
    try uf.makeSet(3);

    try std.testing.expectEqual(@as(u32, 1), uf.find(1));
    try std.testing.expectEqual(@as(u32, 2), uf.find(2));

    try uf.unite(1, 2);
    try std.testing.expectEqual(uf.find(1), uf.find(2));

    try uf.unite(2, 3);
    try std.testing.expectEqual(uf.find(1), uf.find(3));
}

test "UnionFind - path compression" {
    var uf = UnionFind.init(std.testing.allocator);
    defer uf.deinit();

    try uf.makeSet(1);
    try uf.makeSet(2);
    try uf.makeSet(3);

    try uf.unite(1, 2);
    try uf.unite(2, 3);

    _ = uf.find(1);
    _ = uf.find(2);

    try std.testing.expectEqual(@as(u32, 1), uf.find(1));
}

test "PointsToAnalysis - init and deinit" {
    var analysis = PointsToAnalysis.init(std.testing.allocator);
    defer analysis.deinit();
    try std.testing.expectEqual(@as(usize, 0), analysis.points_to.count());
}

test "PointsToAnalysis - address_of constraint" {
    var analysis = PointsToAnalysis.init(std.testing.allocator);
    defer analysis.deinit();

    const constraints = [_]Constraint{
        .{ .lhs = 1, .rhs = 1, .kind = .address_of },
    };

    try analysis.analyze(&constraints);
    try std.testing.expectEqual(@as(usize, 1), analysis.address_taken.count());
}

test "ConstraintGen - init and deinit" {
    var gen = ConstraintGen.init(std.testing.allocator);
    defer gen.deinit();
    try std.testing.expectEqual(@as(usize, 0), gen.constraints.items.len);
}
