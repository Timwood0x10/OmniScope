const std = @import("std");
const c = @import("llvm_raw.zig").c;

pub const IRStoreError = error{
    InvalidModule,
    OutOfMemory,
};

/// Function-level IR representation with pre-categorized instruction buckets.
///
/// Populated by ModuleIRStore.collect() in a single O(n) traversal.
/// All instruction arrays are owned by this struct (allocated via `allocator`).
pub const FunctionIR = struct {
    func: c.LLVMValueRef,
    name: []const u8,

    instructions: []c.LLVMValueRef,
    calls: []c.LLVMValueRef,
    stores: []c.LLVMValueRef,
    loads: []c.LLVMValueRef,
    allocas: []c.LLVMValueRef,
    returns: []c.LLVMValueRef,
    geps: []c.LLVMValueRef,
    bitcasts: []c.LLVMValueRef,
    opcodes: []c_uint,

    /// Map from LLVMValueRef pointer (@intFromPtr) → index into `instructions[]`.
    /// Built once during collect() — turns linear instruction-position lookups
    /// (findInstructionIndex / instructionComesBeforeOrEqual) into O(1).
    /// Hot path: Rule 10 UAF, error_propagation_tracer, cross_lang_dataflow.
    inst_index: std.AutoHashMapUnmanaged(usize, u32),

    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        func: c.LLVMValueRef,
        name: []const u8,
        instructions: []c.LLVMValueRef,
        calls: []c.LLVMValueRef,
        stores: []c.LLVMValueRef,
        loads: []c.LLVMValueRef,
        allocas: []c.LLVMValueRef,
        returns: []c.LLVMValueRef,
        geps: []c.LLVMValueRef,
        bitcasts: []c.LLVMValueRef,
        opcodes: []c_uint,
        inst_index: std.AutoHashMapUnmanaged(usize, u32),
    ) FunctionIR {
        return .{
            .func = func,
            .name = name,
            .instructions = instructions,
            .calls = calls,
            .stores = stores,
            .loads = loads,
            .allocas = allocas,
            .returns = returns,
            .geps = geps,
            .bitcasts = bitcasts,
            .opcodes = opcodes,
            .inst_index = inst_index,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FunctionIR) void {
        self.allocator.free(self.instructions);
        self.allocator.free(self.calls);
        self.allocator.free(self.stores);
        self.allocator.free(self.loads);
        self.allocator.free(self.allocas);
        self.allocator.free(self.returns);
        self.allocator.free(self.geps);
        self.allocator.free(self.bitcasts);
        self.allocator.free(self.opcodes);
        self.inst_index.deinit(self.allocator);
    }

    /// O(1) lookup: instruction position within this function's `instructions[]`.
    /// Returns null if `inst` doesn't belong to this function.
    pub fn indexOf(self: *const FunctionIR, inst: c.LLVMValueRef) ?u32 {
        return self.inst_index.get(@intFromPtr(inst));
    }

    pub fn getInstructionCount(self: *const FunctionIR) usize {
        return self.instructions.len;
    }

    pub fn getCalleeName(self: *const FunctionIR, call_idx: usize) ?[]const u8 {
        if (call_idx >= self.calls.len) return null;
        return self.getCalleeNameByInst(self.calls[call_idx]);
    }

    pub fn getCalleeNameByInst(self: *const FunctionIR, inst: c.LLVMValueRef) ?[]const u8 {
        _ = self;
        const called_val = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_val) == 0) return null;
        const name_ptr = c.LLVMGetValueName(called_val);
        if (@intFromPtr(name_ptr) == 0) return null;
        return std.mem.span(name_ptr);
    }
};

/// Module-level IR store providing O(1) function lookup and pre-categorized instruction access.
///
/// Built once during pipeline initialization via collect(), shared read-only across all passes.
pub const ModuleIRStore = struct {
    allocator: std.mem.Allocator,
    functions: std.StringHashMap(*FunctionIR),
    function_list: []*FunctionIR,
    globals: []c.LLVMValueRef,
    global_names: std.StringHashMap(usize),
    function_count: usize,
    total_instruction_count: usize,

    pub fn collect(mod: c.LLVMModuleRef, allocator: std.mem.Allocator) IRStoreError!ModuleIRStore {
        if (@intFromPtr(mod) == 0) return IRStoreError.InvalidModule;

        var store = ModuleIRStore{
            .allocator = allocator,
            .functions = std.StringHashMap(*FunctionIR).init(allocator),
            .function_list = &[_]*FunctionIR{},
            .globals = &[_]c.LLVMValueRef{},
            .global_names = std.StringHashMap(usize).init(allocator),
            .function_count = 0,
            .total_instruction_count = 0,
        };
        errdefer store.deinit();

        var func_list = std.ArrayList(*FunctionIR){};
        errdefer {
            for (func_list.items) |fir| {
                fir.deinit();
                allocator.destroy(fir);
            }
            func_list.deinit(allocator);
        }

        var func = c.LLVMGetFirstFunction(mod);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) continue;

            const fir = try collectFunctionIR(allocator, func);
            try func_list.append(allocator, fir);

            const name_ptr = c.LLVMGetValueName(func);
            const name = if (@intFromPtr(name_ptr) != 0)
                std.mem.span(name_ptr)
            else
                "(unnamed)";

            try store.functions.put(name, fir);
            store.total_instruction_count += fir.getInstructionCount();
        }

        store.function_list = try func_list.toOwnedSlice(allocator);
        store.function_count = store.function_list.len;

        try collectGlobals(&store, mod);

        log.debug("[IRStore] Collected {} functions, {} total instructions", .{
            store.function_count,
            store.total_instruction_count,
        });

        return store;
    }

    pub fn deinit(self: *ModuleIRStore) void {
        for (self.function_list) |fir| {
            fir.deinit();
            self.allocator.destroy(fir);
        }
        self.allocator.free(self.function_list);
        self.allocator.free(self.globals);

        var func_iter = self.functions.iterator();
        while (func_iter.next()) |_| {}
        self.functions.deinit();

        var global_iter = self.global_names.iterator();
        while (global_iter.next()) |_| {}
        self.global_names.deinit();
    }

    pub fn findFunction(self: *const ModuleIRStore, name: []const u8) ?*FunctionIR {
        return self.functions.get(name);
    }
};

fn collectFunctionIR(allocator: std.mem.Allocator, func: c.LLVMValueRef) !*FunctionIR {
    const name_ptr = c.LLVMGetValueName(func);
    const name = if (@intFromPtr(name_ptr) != 0)
        std.mem.span(name_ptr)
    else
        "(unnamed)";

    var instructions = std.ArrayList(c.LLVMValueRef).initCapacity(allocator, 0) catch return error.OutOfMemory;
    defer instructions.deinit(allocator);
    var calls = std.ArrayList(c.LLVMValueRef).initCapacity(allocator, 0) catch return error.OutOfMemory;
    defer calls.deinit(allocator);
    var stores = std.ArrayList(c.LLVMValueRef).initCapacity(allocator, 0) catch return error.OutOfMemory;
    defer stores.deinit(allocator);
    var loads = std.ArrayList(c.LLVMValueRef).initCapacity(allocator, 0) catch return error.OutOfMemory;
    defer loads.deinit(allocator);
    var allocas = std.ArrayList(c.LLVMValueRef).initCapacity(allocator, 0) catch return error.OutOfMemory;
    defer allocas.deinit(allocator);
    var returns = std.ArrayList(c.LLVMValueRef).initCapacity(allocator, 0) catch return error.OutOfMemory;
    defer returns.deinit(allocator);
    var geps = std.ArrayList(c.LLVMValueRef).initCapacity(allocator, 0) catch return error.OutOfMemory;
    defer geps.deinit(allocator);
    var bitcasts = std.ArrayList(c.LLVMValueRef).initCapacity(allocator, 0) catch return error.OutOfMemory;
    defer bitcasts.deinit(allocator);
    var opcodes = std.ArrayList(c_uint).initCapacity(allocator, 0) catch return error.OutOfMemory;
    defer opcodes.deinit(allocator);

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);
            try instructions.append(allocator, inst);
            try opcodes.append(allocator, opcode);

            switch (opcode) {
                c.LLVMCall, c.LLVMInvoke => try calls.append(allocator, inst),
                c.LLVMStore => try stores.append(allocator, inst),
                c.LLVMLoad => try loads.append(allocator, inst),
                c.LLVMAlloca => try allocas.append(allocator, inst),
                c.LLVMRet => try returns.append(allocator, inst),
                c.LLVMGetElementPtr => try geps.append(allocator, inst),
                c.LLVMBitCast => try bitcasts.append(allocator, inst),
                else => {},
            }
        }
    }

    const fir = try allocator.create(FunctionIR);
    const insts_slice = try instructions.toOwnedSlice(allocator);

    // Build inst → index map for O(1) position lookups (hot path for
    // Rule 10 UAF and other passes that compare instruction order).
    var inst_index: std.AutoHashMapUnmanaged(usize, u32) = .{};
    try inst_index.ensureTotalCapacity(allocator, @intCast(insts_slice.len));
    for (insts_slice, 0..) |inst, idx| {
        inst_index.putAssumeCapacity(@intFromPtr(inst), @intCast(idx));
    }

    fir.* = FunctionIR.init(
        allocator,
        func,
        name,
        insts_slice,
        try calls.toOwnedSlice(allocator),
        try stores.toOwnedSlice(allocator),
        try loads.toOwnedSlice(allocator),
        try allocas.toOwnedSlice(allocator),
        try returns.toOwnedSlice(allocator),
        try geps.toOwnedSlice(allocator),
        try bitcasts.toOwnedSlice(allocator),
        try opcodes.toOwnedSlice(allocator),
        inst_index,
    );

    return fir;
}

fn collectGlobals(store: *ModuleIRStore, mod: c.LLVMModuleRef) !void {
    var globals_list = std.ArrayList(c.LLVMValueRef).initCapacity(store.allocator, 0) catch return error.OutOfMemory;
    defer globals_list.deinit(store.allocator);

    var global_val = c.LLVMGetFirstGlobal(mod);
    while (@intFromPtr(global_val) != 0) : (global_val = c.LLVMGetNextGlobal(global_val)) {
        try globals_list.append(store.allocator, global_val);
        const name_ptr = c.LLVMGetValueName(global_val);
        if (@intFromPtr(name_ptr) == 0) continue;
        const global_name = std.mem.span(name_ptr);
        try store.global_names.put(global_name, globals_list.items.len - 1);
    }

    store.globals = try globals_list.toOwnedSlice(store.allocator);
}

const log = std.log.scoped(.ir_store);
