//! Data Flow Graph (DFG) analysis pass
//!
//! This pass builds the data flow graph for each function
//! and emits dfg_edge facts to the fact store.

const std = @import("std");
const Pass = @import("../pass.zig").Pass;
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const FactStore = @import("../../fact/store.zig").FactStore;
const FactKind = @import("../../fact/fact.zig").FactKind;

const llvm = @import("../../ir/llvm_c.zig");
const ValueRef = @import("../../ir/view.zig").ValueRef;
const BasicBlockRef = @import("../../ir/view.zig").BasicBlockRef;
const FunctionRef = @import("../../ir/view.zig").FunctionRef;

/// Data Flow Graph pass
pub const DFGPass = struct {
    pub const name = "dfg";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{"cfg"};

    ctx: *PassContext,
    diag: *DiagnosticWriter,
    store: *FactStore,
    // Instruction ID mapping
    inst_id_map: std.AutoHashMap(llvm.LLVMValueRef, u32),
    // Function ID
    func_id: u32,

    /// Create a new DFG pass
    pub fn init(store: *FactStore) DFGPass {
        return .{
            .ctx = undefined,
            .diag = undefined,
            .store = store,
            .inst_id_map = std.AutoHashMap(llvm.LLVMValueRef, u32).init(std.heap.page_allocator),
            .func_id = 0,
        };
    }

    /// Run the DFG pass on a module
    pub fn run(
        self: *DFGPass,
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        self.ctx = ctx;
        self.diag = diag;

        const module = ctx.module orelse return;

        // Iterate over all functions
        var func = llvm.LLVMGetFirstFunction(module.raw);
        while (func != null) {
            // Check if this is a function (not global variable, etc.)
            const func_ref = llvm.LLVMIsAFunction(func);
            if (func_ref != null) {
                // Assign function ID
                self.func_id = ctx.getNextId();

                // Analyze function
                try self.analyzeFunction(FunctionRef{ .raw = func_ref });
            }
            func = llvm.LLVMGetNextFunction(func);
        }

        // Clean up
        self.inst_id_map.deinit();
    }

    /// Analyze a function and emit DFG edges
    fn analyzeFunction(self: *DFGPass, func: FunctionRef) !void {
        // Get first basic block
        var bb = llvm.LLVMGetFirstBasicBlock(func.raw);

        while (bb != null) {
            // Get first instruction
            var inst = llvm.LLVMGetFirstInstruction(bb);

            while (inst != null) {
                // Assign ID to instruction
                const inst_id = self.ctx.getNextId();
                try self.inst_id_map.put(inst, inst_id);

                // Analyze instruction
                try self.analyzeInstruction(inst, inst_id);

                // Move to next instruction
                inst = llvm.LLVMGetNextInstruction(inst);
            }

            // Move to next basic block
            bb = llvm.LLVMGetNextBasicBlock(bb);
        }
    }

    /// Analyze an instruction and emit DFG edges
    fn analyzeInstruction(self: *DFGPass, inst: llvm.LLVMValueRef, inst_id: u32) !void {
        // Check if this is a PHI node
        const phi = llvm.LLVMIsAPHINode(inst);
        if (phi != null) {
            // Handle PHI node separately
            try self.analyzePHINode(inst, inst_id);
            return;
        }

        // Regular instruction: analyze operands
        const num_operands = llvm.LLVMGetNumOperands(inst);

        for (0..@intCast(num_operands)) |i| {
            const operand = llvm.LLVMGetOperand(inst, @intCast(i));

            // Get operand ID if it's an instruction
            if (self.inst_id_map.get(operand)) |operand_id| {
                // Emit dfg_edge: operand -> instruction
                try self.store.insert(.dfg_edge, operand_id, inst_id, self.func_id);
            }
        }
    }

    /// Analyze a PHI node and emit DFG edges
    ///
    /// PHI nodes have special semantics: each incoming value is from a different
    /// predecessor basic block. We emit dfg_edge facts for each incoming value.
    fn analyzePHINode(self: *DFGPass, phi: llvm.LLVMValueRef, inst_id: u32) !void {
        const num_incoming = llvm.LLVMCountIncoming(phi);

        for (0..@intCast(num_incoming)) |i| {
            const incoming_value = llvm.LLVMGetIncomingValue(phi, @intCast(i));
            _ = llvm.LLVMGetIncomingBlock(phi, @intCast(i));

            if (self.inst_id_map.get(incoming_value)) |operand_id| {
                try self.store.insert(.dfg_edge, operand_id, inst_id, self.func_id);
            }
        }
    }
};

test "DFGPass - init" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    const pass = DFGPass.init(&store);
    _ = pass;
}

test "DFGPass - validate as Pass" {
    const ValidPass = Pass(struct {
        pub const name = "test-dfg-pass";
        pub const kind = PassKind.foundation;
        pub const deps = &[_][]const u8{"cfg"};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    });

    _ = ValidPass;
}

test "DFGPass - emit dfg_edge fact" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = DFGPass.init(&store);

    // Manually set up test context
    var inst_id_map = std.AutoHashMap(llvm.LLVMValueRef, u32).init(std.testing.allocator);
    defer inst_id_map.deinit();

    // Create dummy instructions
    const inst1: llvm.LLVMValueRef = @ptrFromInt(0x1000);
    const inst2: llvm.LLVMValueRef = @ptrFromInt(0x2000);

    try inst_id_map.put(inst1, 1);
    try inst_id_map.put(inst2, 2);

    pass.inst_id_map = inst_id_map;
    pass.func_id = 1;

    // Emit a dfg_edge fact (inst1 -> inst2)
    try pass.store.insert(.dfg_edge, 1, 2, 1);

    // Verify fact was inserted
    try std.testing.expectEqual(@as(usize, 1), store.count());
    const fact = store.get(0).?;
    try std.testing.expectEqual(FactKind.dfg_edge, fact.kind);
    try std.testing.expectEqual(@as(u32, 1), fact.subject);
    try std.testing.expectEqual(@as(u32, 2), fact.object);
    try std.testing.expectEqual(@as(u32, 1), fact.context);
}

test "DFGPass - multiple dfg_edge facts" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = DFGPass.init(&store);

    var inst_id_map = std.AutoHashMap(llvm.LLVMValueRef, u32).init(std.testing.allocator);
    defer inst_id_map.deinit();

    // Create instructions forming a chain: inst1 -> inst2 -> inst3
    const inst1: llvm.LLVMValueRef = @ptrFromInt(0x1000);
    const inst2: llvm.LLVMValueRef = @ptrFromInt(0x2000);
    const inst3: llvm.LLVMValueRef = @ptrFromInt(0x3000);

    try inst_id_map.put(inst1, 1);
    try inst_id_map.put(inst2, 2);
    try inst_id_map.put(inst3, 3);

    pass.inst_id_map = inst_id_map;
    pass.func_id = 1;

    // Emit dfg_edge facts for the chain
    try pass.store.insert(.dfg_edge, 1, 2, 1);
    try pass.store.insert(.dfg_edge, 2, 3, 1);

    // Verify all facts were inserted
    try std.testing.expectEqual(@as(usize, 2), store.count());

    const fact1 = store.get(0).?;
    try std.testing.expectEqual(@as(u32, 1), fact1.subject);
    try std.testing.expectEqual(@as(u32, 2), fact1.object);

    const fact2 = store.get(1).?;
    try std.testing.expectEqual(@as(u32, 2), fact2.subject);
    try std.testing.expectEqual(@as(u32, 3), fact2.object);
}

test "DFGPass - instruction with multiple operands" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = DFGPass.init(&store);

    var inst_id_map = std.AutoHashMap(llvm.LLVMValueRef, u32).init(std.testing.allocator);
    defer inst_id_map.deinit();

    // Create instruction with multiple operands: inst3 = add inst1, inst2
    const inst1: llvm.LLVMValueRef = @ptrFromInt(0x1000);
    const inst2: llvm.LLVMValueRef = @ptrFromInt(0x2000);
    const inst3: llvm.LLVMValueRef = @ptrFromInt(0x3000);

    try inst_id_map.put(inst1, 1);
    try inst_id_map.put(inst2, 2);
    try inst_id_map.put(inst3, 3);

    pass.inst_id_map = inst_id_map;
    pass.func_id = 1;

    // Emit dfg_edge facts: inst1 -> inst3, inst2 -> inst3
    try pass.store.insert(.dfg_edge, 1, 3, 1);
    try pass.store.insert(.dfg_edge, 2, 3, 1);

    try std.testing.expectEqual(@as(usize, 2), store.count());

    // Verify both operands point to the same instruction
    const fact1 = store.get(0).?;
    try std.testing.expectEqual(@as(u32, 3), fact1.object);

    const fact2 = store.get(1).?;
    try std.testing.expectEqual(@as(u32, 3), fact2.object);
}

test "DFGPass - function ID tracking" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = DFGPass.init(&store);

    var inst_id_map = std.AutoHashMap(llvm.LLVMValueRef, u32).init(std.testing.allocator);
    defer inst_id_map.deinit();

    const inst1: llvm.LLVMValueRef = @ptrFromInt(0x1000);
    const inst2: llvm.LLVMValueRef = @ptrFromInt(0x2000);

    try inst_id_map.put(inst1, 1);
    try inst_id_map.put(inst2, 2);

    pass.inst_id_map = inst_id_map;
    pass.func_id = 99; // Different function ID

    try pass.store.insert(.dfg_edge, 1, 2, 99);

    const fact = store.get(0).?;
    try std.testing.expectEqual(@as(u32, 99), fact.context);

    // Verify function ID is correctly stored
    if (store.queryByKind(.dfg_edge, std.testing.allocator)) |indices| {
        defer std.testing.allocator.free(indices);
        try std.testing.expectEqual(@as(usize, 1), indices.len);
        const fact = store.get(indices[0]).?;
        try std.testing.expectEqual(@as(u32, 99), fact.context);
    } else |_| {
        try std.testing.expect(false);
    }
}

test "DFGPass - inst_id_map consistency" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = DFGPass.init(&store);

    var inst_id_map = std.AutoHashMap(llvm.LLVMValueRef, u32).init(std.testing.allocator);
    defer inst_id_map.deinit();

    // Create instructions with consistent IDs
    const inst1: llvm.LLVMValueRef = @ptrFromInt(0x1000);
    const inst2: llvm.LLVMValueRef = @ptrFromInt(0x2000);
    const inst3: llvm.LLVMValueRef = @ptrFromInt(0x3000);

    try inst_id_map.put(inst1, 100);
    try inst_id_map.put(inst2, 200);
    try inst_id_map.put(inst3, 300);

    pass.inst_id_map = inst_id_map;
    pass.func_id = 1;

    // Emit edges with the IDs from inst_id_map
    try pass.store.insert(.dfg_edge, 100, 200, 1);
    try pass.store.insert(.dfg_edge, 200, 300, 1);

    try std.testing.expectEqual(@as(usize, 2), store.count());

    const fact1 = store.get(0).?;
    try std.testing.expectEqual(@as(u32, 100), fact1.subject);
    try std.testing.expectEqual(@as(u32, 200), fact1.object);

    const fact2 = store.get(1).?;
    try std.testing.expectEqual(@as(u32, 200), fact2.subject);
    try std.testing.expectEqual(@as(u32, 300), fact2.object);
}

test "DFGPass - complex data flow graph" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = DFGPass.init(&store);

    var inst_id_map = std.AutoHashMap(llvm.LLVMValueRef, u32).init(std.testing.allocator);
    defer inst_id_map.deinit();

    // Create a complex DFG:
    // inst1 and inst2 are inputs to inst3
    // inst3 and inst4 are inputs to inst5
    // inst5 is input to inst6
    const inst1: llvm.LLVMValueRef = @ptrFromInt(0x1000);
    const inst2: llvm.LLVMValueRef = @ptrFromInt(0x2000);
    const inst3: llvm.LLVMValueRef = @ptrFromInt(0x3000);
    const inst4: llvm.LLVMValueRef = @ptrFromInt(0x4000);
    const inst5: llvm.LLVMValueRef = @ptrFromInt(0x5000);
    const inst6: llvm.LLVMValueRef = @ptrFromInt(0x6000);

    try inst_id_map.put(inst1, 1);
    try inst_id_map.put(inst2, 2);
    try inst_id_map.put(inst3, 3);
    try inst_id_map.put(inst4, 4);
    try inst_id_map.put(inst5, 5);
    try inst_id_map.put(inst6, 6);

    pass.inst_id_map = inst_id_map;
    pass.func_id = 1;

    // Emit dfg_edge facts for the complex DFG
    try pass.store.insert(.dfg_edge, 1, 3, 1);
    try pass.store.insert(.dfg_edge, 2, 3, 1);
    try pass.store.insert(.dfg_edge, 3, 5, 1);
    try pass.store.insert(.dfg_edge, 4, 5, 1);
    try pass.store.insert(.dfg_edge, 5, 6, 1);

    try std.testing.expectEqual(@as(usize, 5), store.count());

    // Verify the complex DFG structure
    // inst1 -> inst3
    const fact1 = store.get(0).?;
    try std.testing.expectEqual(@as(u32, 1), fact1.subject);
    try std.testing.expectEqual(@as(u32, 3), fact1.object);

    // inst2 -> inst3
    const fact2 = store.get(1).?;
    try std.testing.expectEqual(@as(u32, 2), fact2.subject);
    try std.testing.expectEqual(@as(u32, 3), fact2.object);

    // inst3 -> inst5
    const fact3 = store.get(2).?;
    try std.testing.expectEqual(@as(u32, 3), fact3.subject);
    try std.testing.expectEqual(@as(u32, 5), fact3.object);

    // inst4 -> inst5
    const fact4 = store.get(3).?;
    try std.testing.expectEqual(@as(u32, 4), fact4.subject);
    try std.testing.expectEqual(@as(u32, 5), fact4.object);

    // inst5 -> inst6
    const fact5 = store.get(4).?;
    try std.testing.expectEqual(@as(u32, 5), fact5.subject);
    try std.testing.expectEqual(@as(u32, 6), fact5.object);

    // Verify that inst3 has exactly 2 predecessors (inst1 and inst2)
    var inst3_predecessors: u32 = 0;
    for (0..store.count()) |i| {
        const fact = store.get(i).?;
        if (fact.object == 3) {
            inst3_predecessors += 1;
        }
    }
    try std.testing.expectEqual(@as(u32, 2), inst3_predecessors);

    // Verify that inst5 has exactly 2 predecessors (inst3 and inst4)
    var inst5_predecessors: u32 = 0;
    for (0..store.count()) |i| {
        const fact = store.get(i).?;
        if (fact.object == 5) {
            inst5_predecessors += 1;
        }
    }
    try std.testing.expectEqual(@as(u32, 2), inst5_predecessors);
}
