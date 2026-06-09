//! Control Flow Graph (CFG) analysis pass
//!
//! This pass builds the control flow graph for each function
//! and emits cfg_edge facts to the fact store.

const std = @import("std");
const Pass = @import("../pass.zig").Pass;
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const FactStore = @import("../../fact/store.zig").FactStore;
const FactKind = @import("../../fact/fact.zig").FactKind;

const c = @import("../../ir/llvm_raw.zig").c;
const ValueRef = @import("../../ir/view.zig").ValueRef;
const BasicBlockRef = @import("../../ir/view.zig").BasicBlockRef;
const FunctionRef = @import("../../ir/view.zig").FunctionRef;

/// Control Flow Graph pass
pub const CFGPass = struct {
    pub const name = "cfg";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{};

    ctx: *PassContext,
    diag: *DiagnosticWriter,
    store: *FactStore,
    // Basic block ID mapping
    bb_id_map: std.AutoHashMap(BasicBlockRef, u32),
    // Function ID
    func_id: u32,

    /// Create a new CFG pass
    pub fn init(allocator: std.mem.Allocator, store: *FactStore) CFGPass {
        return .{
            .ctx = undefined,
            .diag = undefined,
            .store = store,
            .bb_id_map = std.AutoHashMap(BasicBlockRef, u32).init(allocator),
            .func_id = 0,
        };
    }

    /// Deinitialize the pass
    pub fn deinit(self: *CFGPass) void {
        self.bb_id_map.deinit();
    }

    /// Reset internal state for re-analysis
    fn reset(self: *CFGPass, allocator: std.mem.Allocator) void {
        self.bb_id_map.deinit();
        self.bb_id_map = std.AutoHashMap(BasicBlockRef, u32).init(allocator);
        self.func_id = 0;
    }

    /// Run the CFG pass on a module
    pub fn run(
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        var fact_store = try FactStore.init(ctx.allocator);
        defer fact_store.deinit();
        var self = CFGPass.init(ctx.allocator, &fact_store);
        defer self.deinit();

        self.ctx = ctx;
        self.diag = diag;

        // Reset internal state for re-analysis
        self.reset(ctx.allocator);

        const module = ctx.module orelse return;

        // Iterate over all functions
        var func = c.LLVMGetFirstFunction(module.raw);
        while (@intFromPtr(func) != 0) {
            // Check if this is a function (not global variable, etc.)
            const func_ref = c.LLVMIsAFunction(func);
            if (func_ref != null) {
                // Assign function ID
                self.func_id = ctx.getNextId();

                // Function-level error isolation
                self.analyzeFunction(FunctionRef{ .raw = func_ref }) catch |err| {
                    const func_name_raw = c.LLVMGetValueName(func_ref);
                    const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";
                    diag.warn("CFG: skipped function due to error: {} ({s})", .{ err, func_name });
                    func = c.LLVMGetNextFunction(func);
                    continue;
                };
            }
            func = c.LLVMGetNextFunction(func);
        }
    }

    /// Analyze a function and emit CFG edges
    fn analyzeFunction(self: *CFGPass, func: FunctionRef) !void {
        // Get first basic block
        var bb = c.LLVMGetFirstBasicBlock(func.raw);

        while (@intFromPtr(bb) != 0) {
            // Assign ID to basic block (pointer-based for LLVM values)
            const bb_id = self.ctx.getValueId(@intFromPtr(bb)) catch {
                bb = c.LLVMGetNextBasicBlock(bb);
                continue;
            };
            try self.bb_id_map.put(BasicBlockRef{ .raw = bb }, bb_id);

            // Analyze basic block
            try self.analyzeBasicBlock(BasicBlockRef{ .raw = bb }, bb_id);

            // Move to next basic block
            bb = c.LLVMGetNextBasicBlock(bb);
        }
    }

    /// Analyze a basic block and emit CFG edges
    fn analyzeBasicBlock(self: *CFGPass, bb: BasicBlockRef, bb_id: u32) !void {
        // Get terminator instruction
        const terminator = c.LLVMGetBasicBlockTerminator(bb.raw);

        // If no terminator, this is an entry block or malformed block
        if (terminator == null) return;

        // Get opcode
        const opcode = c.LLVMGetInstructionOpcode(terminator);

        // Based on opcode, emit cfg_edge facts
        switch (opcode) {
            c.LLVMBr => {
                // Branch: handle conditional and unconditional
                try self.handleBranch(terminator, bb_id);
            },
            c.LLVMSwitch => {
                // Switch: handle multiple cases
                try self.handleSwitch(terminator, bb_id);
            },
            c.LLVMRet => {
                // Return: no successors
            },
            c.LLVMInvoke, c.LLVMCallBr, c.LLVMIndirectBr => {
                // Complex terminators: handle generically
                try self.handleGenericTerminator(terminator, bb_id);
            },
            else => {
                // Other terminators: no CFG edges
            },
        }
    }

    /// Handle branch instruction
    fn handleBranch(self: *CFGPass, terminator: c.LLVMValueRef, source_bb_id: u32) !void {
        const num_operands = c.LLVMGetNumOperands(terminator);

        if (num_operands == 1) {
            // Unconditional branch: one successor
            const target_bb_val = c.LLVMGetOperand(terminator, 0);
            const target_bb = c.LLVMValueAsBasicBlock(target_bb_val);
            const target_bb_id = self.bb_id_map.get(BasicBlockRef{ .raw = target_bb }) orelse return;
            try self.store.insert(.cfg_edge, source_bb_id, target_bb_id, self.func_id);
        } else if (num_operands == 3) {
            // Conditional branch: two successors (true, false)
            // Operands: [condition, true_bb, false_bb]
            const true_bb_val = c.LLVMGetOperand(terminator, 1);
            const false_bb_val = c.LLVMGetOperand(terminator, 2);
            const true_bb = c.LLVMValueAsBasicBlock(true_bb_val);
            const false_bb = c.LLVMValueAsBasicBlock(false_bb_val);

            if (self.bb_id_map.get(BasicBlockRef{ .raw = true_bb })) |true_bb_id| {
                try self.store.insert(.cfg_edge, source_bb_id, true_bb_id, self.func_id);
            }

            if (self.bb_id_map.get(BasicBlockRef{ .raw = false_bb })) |false_bb_id| {
                try self.store.insert(.cfg_edge, source_bb_id, false_bb_id, self.func_id);
            }
        }
    }

    /// Handle switch instruction
    fn handleSwitch(self: *CFGPass, terminator: c.LLVMValueRef, source_bb_id: u32) !void {
        // Switch has multiple successors: default + each case
        const num_successors = c.LLVMGetNumSuccessors(terminator);

        for (0..@intCast(num_successors)) |i| {
            const successor_bb = c.LLVMGetSuccessor(terminator, @intCast(i));
            const successor_bb_id = self.bb_id_map.get(BasicBlockRef{ .raw = successor_bb }) orelse continue;
            try self.store.insert(.cfg_edge, source_bb_id, successor_bb_id, self.func_id);
        }
    }

    /// Handle generic terminator (invoke, callbr, indirectbr)
    fn handleGenericTerminator(self: *CFGPass, terminator: c.LLVMValueRef, source_bb_id: u32) !void {
        const num_successors = c.LLVMGetNumSuccessors(terminator);

        for (0..@intCast(num_successors)) |i| {
            const successor_bb = c.LLVMGetSuccessor(terminator, @intCast(i));
            const successor_bb_id = self.bb_id_map.get(BasicBlockRef{ .raw = successor_bb }) orelse continue;
            try self.store.insert(.cfg_edge, source_bb_id, successor_bb_id, self.func_id);
        }
    }
};

test "CFGPass - init" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    const pass = CFGPass.init(&store);
    _ = pass;
}

test "CFGPass - validate as Pass" {
    const ValidPass = Pass(struct {
        pub const name = "test-cfg-pass";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    });

    _ = ValidPass;
}

test "CFGPass - emit cfg_edge fact" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = CFGPass.init(&store);

    // Manually set up test context
    var bb_id_map = std.AutoHashMap(c.LLVMBasicBlockRef, u32).init(std.testing.allocator);
    defer bb_id_map.deinit();

    // Create dummy basic blocks
    const bb1: c.LLVMBasicBlockRef = @ptrFromInt(0x1000);
    const bb2: c.LLVMBasicBlockRef = @ptrFromInt(0x2000);

    try bb_id_map.put(bb1, 1);
    try bb_id_map.put(bb2, 2);

    pass.bb_id_map = bb_id_map;
    pass.func_id = 1;

    // Emit a cfg_edge fact
    try pass.store.insert(.cfg_edge, 1, 2, 1);

    // Verify fact was inserted
    try std.testing.expectEqual(@as(usize, 1), store.count());
    const fact = store.get(0).?;
    try std.testing.expectEqual(FactKind.cfg_edge, fact.kind);
    try std.testing.expectEqual(@as(u32, 1), fact.subject);
    try std.testing.expectEqual(@as(u32, 2), fact.object);
    try std.testing.expectEqual(@as(u32, 1), fact.context);
}

test "CFGPass - multiple cfg_edge facts" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = CFGPass.init(&store);

    var bb_id_map = std.AutoHashMap(c.LLVMBasicBlockRef, u32).init(std.testing.allocator);
    defer bb_id_map.deinit();

    // Create multiple basic blocks forming a simple CFG
    const bb1: c.LLVMBasicBlockRef = @ptrFromInt(0x1000);
    const bb2: c.LLVMBasicBlockRef = @ptrFromInt(0x2000);
    const bb3: c.LLVMBasicBlockRef = @ptrFromInt(0x3000);

    try bb_id_map.put(bb1, 1);
    try bb_id_map.put(bb2, 2);
    try bb_id_map.put(bb3, 3);

    pass.bb_id_map = bb_id_map;
    pass.func_id = 1;

    // Emit multiple cfg_edge facts (bb1 -> bb2, bb1 -> bb3, bb2 -> bb3)
    try pass.store.insert(.cfg_edge, 1, 2, 1);
    try pass.store.insert(.cfg_edge, 1, 3, 1);
    try pass.store.insert(.cfg_edge, 2, 3, 1);

    // Verify all facts were inserted
    try std.testing.expectEqual(@as(usize, 3), store.count());

    // Verify facts are in order
    const fact1 = store.get(0).?;
    try std.testing.expectEqual(@as(u32, 1), fact1.subject);
    try std.testing.expectEqual(@as(u32, 2), fact1.object);

    const fact2 = store.get(1).?;
    try std.testing.expectEqual(@as(u32, 1), fact2.subject);
    try std.testing.expectEqual(@as(u32, 3), fact2.object);

    const fact3 = store.get(2).?;
    try std.testing.expectEqual(@as(u32, 2), fact3.subject);
    try std.testing.expectEqual(@as(u32, 3), fact3.object);
}

test "CFGPass - function ID tracking" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = CFGPass.init(&store);

    var bb_id_map = std.AutoHashMap(c.LLVMBasicBlockRef, u32).init(std.testing.allocator);
    defer bb_id_map.deinit();

    const bb1: c.LLVMBasicBlockRef = @ptrFromInt(0x1000);
    const bb2: c.LLVMBasicBlockRef = @ptrFromInt(0x2000);

    try bb_id_map.put(bb1, 1);
    try bb_id_map.put(bb2, 2);

    pass.bb_id_map = bb_id_map;
    pass.func_id = 42; // Different function ID

    try pass.store.insert(.cfg_edge, 1, 2, 42);

    const fact = store.get(0).?;
    try std.testing.expectEqual(@as(u32, 42), fact.context);

    // Verify function ID is correctly stored
    if (store.queryByKind(.cfg_edge, std.testing.allocator)) |indices| {
        defer std.testing.allocator.free(indices);
        try std.testing.expectEqual(@as(usize, 1), indices.len);
        if (store.get(indices[0])) |queried_fact| {
            try std.testing.expectEqual(@as(u32, 42), queried_fact.context);
        } else {
            try std.testing.expect(false);
        }
    } else |_| {
        try std.testing.expect(false);
    }
}

test "CFGPass - bb_id_map consistency" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = CFGPass.init(&store);

    var bb_id_map = std.AutoHashMap(c.LLVMBasicBlockRef, u32).init(std.testing.allocator);
    defer bb_id_map.deinit();

    // Create basic blocks with consistent IDs
    const bb1: c.LLVMBasicBlockRef = @ptrFromInt(0x1000);
    const bb2: c.LLVMBasicBlockRef = @ptrFromInt(0x2000);
    const bb3: c.LLVMBasicBlockRef = @ptrFromInt(0x3000);

    try bb_id_map.put(bb1, 10);
    try bb_id_map.put(bb2, 20);
    try bb_id_map.put(bb3, 30);

    pass.bb_id_map = bb_id_map;
    pass.func_id = 1;

    // Emit edges with the IDs from bb_id_map
    try pass.store.insert(.cfg_edge, 10, 20, 1);
    try pass.store.insert(.cfg_edge, 20, 30, 1);

    try std.testing.expectEqual(@as(usize, 2), store.count());

    const fact1 = store.get(0).?;
    try std.testing.expectEqual(@as(u32, 10), fact1.subject);
    try std.testing.expectEqual(@as(u32, 20), fact1.object);

    const fact2 = store.get(1).?;
    try std.testing.expectEqual(@as(u32, 20), fact2.subject);
    try std.testing.expectEqual(@as(u32, 30), fact2.object);
}
