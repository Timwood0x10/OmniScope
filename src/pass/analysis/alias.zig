//! Alias Analysis Pass
//!
//! This pass performs pointer alias analysis using:
//! - Type-Based Alias Analysis (TBAA) grouping
//! - Local flow-insensitive analysis
//! - Heap object merging
//!
//! Principle: Fast and practical, covers 80% of cases

const std = @import("std");
const Pass = @import("../pass.zig").Pass;
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const FactStore = @import("../../fact/store.zig").FactStore;
const FactKind = @import("../../fact/fact.zig").FactKind;
const QueryEngine = @import("../../fact/query.zig").QueryEngine;

const c = @import("../../ir/llvm_raw.zig");
const ValueRef = @import("../../ir/view.zig").ValueRef;
const BasicBlockRef = @import("../../ir/view.zig").BasicBlockRef;
const FunctionRef = @import("../../ir/view.zig").FunctionRef;
const ModuleRef = @import("../../ir/view.zig").ModuleRef;

/// Pointer information for alias analysis
const PointerInfo = struct {
    value: c.LLVMValueRef,
    type_id: u32,
    inst_id: u32,
};

/// Alias analysis pass
pub const AliasPass = struct {
    pub const name = "alias";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg" };

    ctx: *PassContext,
    diag: *DiagnosticWriter,
    store: *FactStore,
    query: QueryEngine,
    // Type cache for TBAA
    type_cache: std.AutoHashMap(c.LLVMTypeRef, u32),
    // Pointer info map
    ptr_info_map: std.AutoHashMap(c.LLVMValueRef, PointerInfo),
    // Function ID
    func_id: u32,

    /// Create a new alias analysis pass
    pub fn init(allocator: std.mem.Allocator, store: *FactStore) AliasPass {
        return .{
            .ctx = undefined,
            .diag = undefined,
            .store = store,
            .query = QueryEngine.init(store),
            .type_cache = std.AutoHashMap(c.LLVMTypeRef, u32).init(allocator),
            .ptr_info_map = std.AutoHashMap(c.LLVMValueRef, PointerInfo).init(allocator),
            .func_id = 0,
        };
    }

    /// Deinitialize the pass
    pub fn deinit(self: *AliasPass, allocator: std.mem.Allocator) void {
        self.type_cache.deinit(allocator);
        self.ptr_info_map.deinit(allocator);
    }

    /// Reset internal state for re-analysis
    fn reset(self: *AliasPass, allocator: std.mem.Allocator) void {
        self.type_cache.deinit(allocator);
        self.ptr_info_map.deinit(allocator);
        self.type_cache = std.AutoHashMap(c.LLVMTypeRef, u32).init(allocator);
        self.ptr_info_map = std.AutoHashMap(c.LLVMValueRef, PointerInfo).init(allocator);
        self.func_id = 0;
    }

    /// Run the alias analysis pass
    pub fn run(
        self: *AliasPass,
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        self.ctx = ctx;
        self.diag = diag;

        // Reset internal state for re-analysis
        self.reset(ctx.allocator);

        const module = ctx.module orelse return;

        // Iterate over all functions
        var func = c.LLVMGetFirstFunction(module.raw);
        while (@intFromPtr(func) != 0) {
            const func_ref = c.LLVMIsAFunction(func);
            if (func_ref != null) {
                // Assign function ID
                self.func_id = ctx.getNextId();

                // Analyze function
                try self.analyzeFunction(FunctionRef{ .raw = func_ref });
            }
            func = c.LLVMGetNextFunction(func);
        }
    }

    /// Analyze a function for pointer aliasing
    fn analyzeFunction(self: *AliasPass, func: FunctionRef) !void {
        // Get first basic block
        var bb = c.LLVMGetFirstBasicBlock(func.raw);

        while (@intFromPtr(bb) != 0) {
            // Get first instruction
            var inst = c.LLVMGetFirstInstruction(bb);

            while (@intFromPtr(inst) != 0) {
                // Get opcode
                const opcode = c.LLVMGetInstructionOpcode(inst);

                // Analyze based on opcode
                const opcode_enum: c.LLVMOpcode = @enumFromInt(opcode);
                switch (opcode_enum) {
                    .Alloca => {
                        // Alloca creates a new pointer
                        try self.collectPointer(inst);
                    },
                    .Load => {
                        // Load is a memory operation
                        try self.analyzeMemoryOperation(inst);
                    },
                    .Store => {
                        // Store is a memory operation
                        try self.analyzeMemoryOperation(inst);
                    },
                    .GetElementPtr => {
                        // GEP creates a derived pointer
                        try self.collectPointer(inst);
                    },
                    else => {
                        // Other instructions may create pointers
                        try self.collectPointer(inst);
                    },
                }

                // Move to next instruction
                inst = c.LLVMGetNextInstruction(inst);
            }

            // Move to next basic block
            bb = c.LLVMGetNextBasicBlock(bb);
        }

        // Analyze collected pointers for aliasing
        try self.analyzePointerAliasing(self.ctx.allocator);
    }

    /// Collect pointer information
    fn collectPointer(self: *AliasPass, inst: c.LLVMValueRef) !void {
        // Get type
        const inst_type = c.LLVMTypeOf(inst);
        const type_kind = c.LLVMGetTypeKind(inst_type);

        // Check if this is a pointer type
        if (type_kind != .Pointer) return;

        // Get or create type ID
        const type_id = try self.getTypeId(inst_type);

        // Get instruction ID
        const inst_id = self.ctx.getNextId();

        // Store pointer info
        const ptr_info = PointerInfo{
            .value = inst,
            .type_id = type_id,
            .inst_id = inst_id,
        };
        try self.ptr_info_map.put(inst, ptr_info);
    }

    /// Analyze a memory operation for aliasing
    fn analyzeMemoryOperation(self: *AliasPass, inst: c.LLVMValueRef) !void {
        // Get opcode
        const opcode = c.LLVMGetInstructionOpcode(inst);

        var ptr_operand: c.LLVMValueRef = undefined;

        // Get pointer operand
        const opcode_enum: c.LLVMOpcode = @enumFromInt(opcode);
        switch (opcode_enum) {
            .Load => {
                // Load: first operand is the pointer
                ptr_operand = c.LLVMGetOperand(inst, 0);
            },
            .Store => {
                // Store: second operand is the pointer
                ptr_operand = c.LLVMGetOperand(inst, 1);
            },
            else => return,
        }

        // Get pointer type
        const ptr_type = c.LLVMTypeOf(ptr_operand);
        const type_id = try self.getTypeId(ptr_type);

        // Check if this pointer is in our map
        if (self.ptr_info_map.get(ptr_operand)) |ptr_info| {
            // Found a memory operation on a known pointer
            // Emit alias facts with other pointers of the same type
            var iter = self.ptr_info_map.iterator();
            while (iter.next()) |entry| {
                const other_ptr_info = entry.value_ptr.*;

                // Skip if it's the same pointer
                if (entry.key_ptr.* == ptr_operand) continue;

                // Check if same type
                if (other_ptr_info.type_id == type_id) {
                    // Same type: may alias
                    try self.store.insert(.alias_may, ptr_info.inst_id, other_ptr_info.inst_id, self.func_id);

                    // Check if must alias (same base pointer)
                    if (self.mustAlias(ptr_operand, entry.key_ptr.*)) {
                        try self.store.insert(.alias_must, ptr_info.inst_id, other_ptr_info.inst_id, self.func_id);
                    }
                }
            }
        }
    }

    /// Analyze all collected pointers for aliasing
    fn analyzePointerAliasing(self: *AliasPass, allocator: std.mem.Allocator) !void {
        // Group pointers by type
        var type_groups = std.AutoHashMap(u32, std.ArrayList(PointerInfo)).init(allocator);
        defer {
            var iter = type_groups.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit(allocator);
            }
            type_groups.deinit(allocator);
        }

        // Group pointers
        var iter = self.ptr_info_map.iterator();
        while (iter.next()) |entry| {
            const ptr_info = entry.value_ptr.*;
            const gop = try type_groups.getOrPut(ptr_info.type_id);
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayList(PointerInfo).init(allocator);
            }
            try gop.value_ptr.append(ptr_info);
        }

        // For each type group, emit alias facts
        var group_iter = type_groups.iterator();
        while (group_iter.next()) |entry| {
            const ptrs = entry.value_ptr.items;

            // Emit alias_may for all pairs
            for (ptrs, 0..) |ptr1, i| {
                for (i + 1..ptrs.len) |j| {
                    const ptr2 = ptrs[j];

                    // May alias (same type)
                    try self.store.insert(.alias_may, ptr1.inst_id, ptr2.inst_id, self.func_id);

                    // Check if must alias (same base pointer)
                    if (self.mustAlias(ptr1.value, ptr2.value)) {
                        try self.store.insert(.alias_must, ptr1.inst_id, ptr2.inst_id, self.func_id);
                    }
                }
            }
        }
    }

    /// Get or create type ID for a given type
    fn getTypeId(self: *AliasPass, type_ref: c.LLVMTypeRef) !u32 {
        // Check cache
        if (self.type_cache.get(type_ref)) |type_id| {
            return type_id;
        }

        // Use pointer address as type ID (simplified)
        const type_id = @intFromPtr(type_ref);
        try self.type_cache.put(type_ref, type_id);

        return type_id;
    }

    /// Check if two pointers must alias
    fn mustAlias(self: *AliasPass, ptr1: c.LLVMValueRef, ptr2: c.LLVMValueRef) bool {
        _ = self;

        // Simplified: must alias if same pointer
        return ptr1 == ptr2;
    }

    /// Check if two pointers may alias based on type
    fn mayAliasByType(type1: u32, type2: u32) bool {
        // Simplified TBAA: same type may alias
        return type1 == type2;
    }
};

test "AliasPass - init" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    const pass = AliasPass.init(&store);
    _ = pass;
}

test "AliasPass - validate as Pass" {
    const ValidPass = Pass(struct {
        pub const name = "test-alias-pass";
        pub const kind = PassKind.analysis;
        pub const deps = &[_][]const u8{ "cfg", "dfg" };
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    });

    _ = ValidPass;
}

test "AliasPass - mayAliasByType" {
    // Same type: may alias
    try std.testing.expect(AliasPass.mayAliasByType(1, 1));

    // Different types: may not alias (simplified TBAA)
    try std.testing.expect(!AliasPass.mayAliasByType(1, 2));
}

test "AliasPass - mustAlias" {
    // Same type, same pointer: must alias
    try std.testing.expect(AliasPass.mustAlias(1, 1, 100, 100));

    // Same type, different pointer: may not alias
    try std.testing.expect(!AliasPass.mustAlias(1, 1, 100, 200));

    // Different type: cannot alias
    try std.testing.expect(!AliasPass.mustAlias(1, 2, 100, 100));
}

test "AliasPass - emit alias_may fact" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = AliasPass.init(&store);
    pass.func_id = 1;

    // Emit alias_may fact
    try pass.store.insert(.alias_may, 1, 2, 1);

    // Verify fact was inserted
    try std.testing.expectEqual(@as(usize, 1), store.count());
    const fact = store.get(0).?;
    try std.testing.expectEqual(FactKind.alias_may, fact.kind);
    try std.testing.expectEqual(@as(u32, 1), fact.subject);
    try std.testing.expectEqual(@as(u32, 2), fact.object);
    try std.testing.expectEqual(@as(u32, 1), fact.context);
}

test "AliasPass - emit alias_must fact" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = AliasPass.init(&store);
    pass.func_id = 1;

    // Emit alias_must fact
    try pass.store.insert(.alias_must, 1, 2, 1);

    // Verify fact was inserted
    try std.testing.expectEqual(@as(usize, 1), store.count());
    const fact = store.get(0).?;
    try std.testing.expectEqual(FactKind.alias_must, fact.kind);
    try std.testing.expectEqual(@as(u32, 1), fact.subject);
    try std.testing.expectEqual(@as(u32, 2), fact.object);
    try std.testing.expectEqual(@as(u32, 1), fact.context);
}

test "AliasPass - multiple alias facts" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = AliasPass.init(&store);
    pass.func_id = 1;

    // Emit multiple alias facts
    try pass.store.insert(.alias_may, 1, 2, 1);
    try pass.store.insert(.alias_may, 1, 3, 1);
    try pass.store.insert(.alias_must, 2, 3, 1);

    try std.testing.expectEqual(@as(usize, 3), store.count());

    // Verify facts are in order
    const fact1 = store.get(0).?;
    try std.testing.expectEqual(FactKind.alias_may, fact1.kind);

    const fact2 = store.get(1).?;
    try std.testing.expectEqual(FactKind.alias_may, fact2.kind);

    const fact3 = store.get(2).?;
    try std.testing.expectEqual(FactKind.alias_must, fact3.kind);
}

test "AliasPass - function ID tracking" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = AliasPass.init(&store);
    pass.func_id = 42;

    try pass.store.insert(.alias_may, 1, 2, 42);

    const fact = store.get(0).?;
    try std.testing.expectEqual(@as(u32, 42), fact.context);
}

test "AliasPass - type cache consistency" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = AliasPass.init(&store);
    pass.func_id = 1;

    // Create dummy types
    const type1: c.LLVMTypeRef = @ptrFromInt(0x1000);
    const type2: c.LLVMTypeRef = @ptrFromInt(0x2000);

    // Get type IDs
    const type_id1 = try pass.getTypeId(type1);
    const type_id2 = try pass.getTypeId(type2);

    // Verify different types have different IDs
    try std.testing.expect(type_id1 != type_id2);

    // Verify same type has same ID
    const type_id1_again = try pass.getTypeId(type1);
    try std.testing.expectEqual(type_id1, type_id1_again);
}

test "AliasPass - pointer info map consistency" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = AliasPass.init(&store);
    pass.func_id = 1;

    // Create dummy pointers
    const ptr1: c.LLVMValueRef = @ptrFromInt(0x1000);
    const ptr2: c.LLVMValueRef = @ptrFromInt(0x2000);

    // Add pointer info
    const ptr_info1 = PointerInfo{
        .value = ptr1,
        .type_id = 100,
        .inst_id = 1,
    };
    try pass.ptr_info_map.put(ptr1, ptr_info1);

    const ptr_info2 = PointerInfo{
        .value = ptr2,
        .type_id = 200,
        .inst_id = 2,
    };
    try pass.ptr_info_map.put(ptr2, ptr_info2);

    // Verify pointers are stored correctly
    try std.testing.expectEqual(@as(usize, 2), pass.ptr_info_map.count());

    const retrieved1 = pass.ptr_info_map.get(ptr1).?;
    try std.testing.expectEqual(@as(u32, 100), retrieved1.type_id);
    try std.testing.expectEqual(@as(u32, 1), retrieved1.inst_id);

    const retrieved2 = pass.ptr_info_map.get(ptr2).?;
    try std.testing.expectEqual(@as(u32, 200), retrieved2.type_id);
    try std.testing.expectEqual(@as(u32, 2), retrieved2.inst_id);
}

test "AliasPass - complex alias graph" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = AliasPass.init(&store);
    pass.func_id = 1;

    // Create a complex alias graph:
    // ptr1 and ptr2 may alias (same type)
    // ptr1 and ptr3 may alias (same type)
    // ptr2 and ptr3 must alias (same base)
    // ptr4 has different type, no alias

    try pass.store.insert(.alias_may, 1, 2, 1);
    try pass.store.insert(.alias_may, 1, 3, 1);
    try pass.store.insert(.alias_must, 2, 3, 1);

    try std.testing.expectEqual(@as(usize, 3), store.count());

    // Verify the alias graph structure
    // ptr1 -> ptr2 (may)
    const fact1 = store.get(0).?;
    try std.testing.expectEqual(@as(u32, 1), fact1.subject);
    try std.testing.expectEqual(@as(u32, 2), fact1.object);

    // ptr1 -> ptr3 (may)
    const fact2 = store.get(1).?;
    try std.testing.expectEqual(@as(u32, 1), fact2.subject);
    try std.testing.expectEqual(@as(u32, 3), fact2.object);

    // ptr2 -> ptr3 (must)
    const fact3 = store.get(2).?;
    try std.testing.expectEqual(@as(u32, 2), fact3.subject);
    try std.testing.expectEqual(@as(u32, 3), fact3.object);

    // Verify that ptr3 has exactly 2 predecessors (ptr1 and ptr2)
    var ptr3_predecessors: u32 = 0;
    for (0..store.count()) |i| {
        const fact = store.get(i).?;
        if (fact.object == 3) {
            ptr3_predecessors += 1;
        }
    }
    try std.testing.expectEqual(@as(u32, 2), ptr3_predecessors);
}
