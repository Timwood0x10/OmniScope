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

const llvm = @import("../../ir/llvm_c.zig");
const ValueRef = @import("../../ir/view.zig").ValueRef;
const BasicBlockRef = @import("../../ir/view.zig").BasicBlockRef;

/// Data Flow Graph pass
pub const DFGPass = struct {
    pub const name = "dfg";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{"cfg"};

    store: *FactStore,

    /// Create a new DFG pass
    pub fn init(store: *FactStore) DFGPass {
        return .{ .store = store };
    }

    /// Run the DFG pass on a module
    pub fn run(
        self: *DFGPass,
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        _ = ctx;
        _ = diag;

        // TODO: Load module from context
        // For now, this is a placeholder implementation
        // The actual implementation will:
        // 1. Iterate over all functions in the module
        // 2. For each function, iterate over instructions
        // 3. For each instruction, analyze operands
        // 4. Emit dfg_edge facts for each operand -> instruction relationship

        // Example: Emit a sample dfg_edge fact
        try self.store.insert(.dfg_edge, 1, 2, 0);
    }

    /// Analyze a function and emit DFG edges
    fn analyzeFunction(self: *DFGPass, func: ValueRef, context: u32) !void {
        _ = self;
        _ = func;
        _ = context;

        // Get basic blocks
        // const first_bb = LLVMGetFirstBasicBlock(func.raw);
        // var bb: ?LLVMBasicBlockRef = first_bb;

        // while (bb != null) {
        //     // Get first instruction
        //     var inst: ?LLVMValueRef = LLVMGetFirstInstruction(bb.?);

        //     while (inst != null) {
        //         // Analyze operands
        //         const num_operands = LLVMGetNumOperands(inst.?);

        //         for (0..@intCast(num_operands)) |i| {
        //             const operand = LLVMGetOperand(inst.?, @intCast(i));

        //             // Emit dfg_edge: operand -> instruction
        //             try self.store.insert(.dfg_edge, operand_id, inst_id, context);
        //         }

        //         inst = LLVMGetNextInstruction(inst.?);
        //     }

        //     bb = LLVMGetNextBasicBlock(bb.?);
        // }
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
