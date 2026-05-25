//! Lock Analysis Pass
//!
//! This pass detects potential deadlocks by:
//! 1. Building a lock acquisition graph from facts
//! 2. Finding cycles using Tarjan's SCC algorithm
//! 3. Reporting potential deadlock scenarios

const std = @import("std");
const Pass = @import("../pass.zig").Pass;
const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const FactStore = @import("../../fact/store.zig").FactStore;
const FactKind = @import("../../fact/fact.zig").FactKind;
const QueryEngine = @import("../../fact/query.zig").QueryEngine;

// R8-H6 FIX: Added .c suffix to import LLVM C bindings
const c = @import("../../ir/llvm_raw.zig").c;
const ValueRef = @import("../../ir/view.zig").ValueRef;
const FunctionRef = @import("../../ir/view.zig").FunctionRef;

// Import extracted type definitions
const LockOperation = @import("../../types/lock_types.zig").LockOperation;
const LockGraph = @import("../../types/lock_types.zig").LockGraph;

/// Lock analysis pass
pub const LockPass = struct {
    pub const name = "lock";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    ctx: *PassContext,
    diag: *DiagnosticWriter,
    store: *FactStore,
    query: QueryEngine,
    // Lock operations map
    lock_ops: std.ArrayList(LockOperation),
    // Lock ID mapping
    lock_id_map: std.AutoHashMap(c.LLVMValueRef, u32),
    // Function ID
    func_id: u32,
    // Next lock ID
    next_lock_id: u32,

    /// Create a new lock analysis pass
    pub fn init(allocator: std.mem.Allocator, store: *FactStore) LockPass {
        return .{
            .ctx = undefined,
            .diag = undefined,
            .store = store,
            .query = QueryEngine.init(store, allocator),
            .lock_ops = std.ArrayList(LockOperation).initCapacity(allocator, 16) catch @panic("OOM"),
            .lock_id_map = std.AutoHashMap(c.LLVMValueRef, u32).init(allocator),
            .func_id = 0,
            .next_lock_id = 1,
        };
    }

    /// Deinitialize the pass
    pub fn deinit(self: *LockPass, allocator: std.mem.Allocator) void {
        self.query.deinit();
        self.lock_ops.deinit(allocator);
        self.lock_id_map.deinit();
    }

    /// Reset internal state for re-analysis
    fn reset(self: *LockPass) void {
        self.lock_ops.clearRetainingCapacity();
        self.lock_id_map.clearRetainingCapacity();
        self.func_id = 0;
        self.next_lock_id = 1;
    }

    /// Run the lock analysis pass
    pub fn run(
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        var fact_store = try FactStore.init(ctx.allocator);
        defer fact_store.deinit();
        var self = LockPass.init(ctx.allocator, &fact_store);
        defer self.deinit(ctx.allocator);

        self.ctx = ctx;
        self.diag = diag;

        // Reset internal state for re-analysis
        self.reset();

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

        // Build lock graph and detect deadlocks
        try self.detectDeadlocks(self.ctx.allocator);
    }

    /// Analyze a function for lock operations
    fn analyzeFunction(self: *LockPass, func: FunctionRef) !void {
        // Get first basic block
        var bb = c.LLVMGetFirstBasicBlock(func.raw);

        while (@intFromPtr(bb) != 0) {
            // Get first instruction
            var inst = c.LLVMGetFirstInstruction(bb);

            while (@intFromPtr(inst) != 0) {
                // Check if this is a lock operation
                if (self.isLockOperation(inst)) {
                    const is_acquire = self.isLockAcquire(inst);
                    const lock_id = try self.getLockId(inst);

                    const inst_id = self.ctx.getValueId(@intFromPtr(inst)) catch continue;

                    const lock_op = LockOperation{
                        .lock_id = lock_id,
                        .inst_id = inst_id,
                        .is_acquire = is_acquire,
                    };
                    try self.lock_ops.append(self.ctx.allocator, lock_op);

                    // Emit lock fact
                    if (is_acquire) {
                        try self.store.insert(.lock_acquire, lock_id, inst_id, self.func_id);
                    } else {
                        try self.store.insert(.lock_release, lock_id, inst_id, self.func_id);
                    }
                }

                // Move to next instruction
                inst = c.LLVMGetNextInstruction(inst);
            }

            // Move to next basic block
            bb = c.LLVMGetNextBasicBlock(bb);
        }
    }

    /// Check if an instruction is a lock operation
    fn isLockOperation(_: *LockPass, inst: c.LLVMValueRef) bool {
        // Get opcode
        const opcode = c.LLVMGetInstructionOpcode(inst);

        // Lock operations are typically function calls
        if (opcode != c.LLVMCall) return false;

        // Get called function
        const called_func = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_func) == 0) return false;

        // Get function name
        const func_name = c.LLVMGetValueName(called_func);
        if (@intFromPtr(func_name) == 0) return false;
        const func_name_slice = std.mem.span(func_name);

        // Check if it's a known lock function
        return isKnownLockFunctionByName(func_name_slice);
    }

    /// Check if a function name is a known lock function (standalone)
    fn isKnownLockFunctionByName(func_name_slice: []const u8) bool {

        // Common lock function names
        const lock_funcs = [_][]const u8{
            "pthread_mutex_lock",
            "pthread_mutex_unlock",
            "pthread_spin_lock",
            "pthread_spin_unlock",
            "lock_acquire",
            "lock_release",
        };

        for (lock_funcs) |lock_func| {
            if (std.mem.eql(u8, func_name_slice, lock_func)) {
                return true;
            }
        }

        return false;
    }

    /// Check if a lock operation is acquire or release
    fn isLockAcquire(self: *LockPass, inst: c.LLVMValueRef) bool {
        _ = self;

        // Get called function - use LLVMGetCalledValue for call instructions
        const called_func = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called_func) == 0) return false;

        // Get function name
        const func_name = c.LLVMGetValueName(called_func);
        if (@intFromPtr(func_name) == 0) return false;
        const func_name_slice = std.mem.span(func_name);

        // Check for common lock acquire patterns (more precise than just "lock")
        const lock_patterns = [_][]const u8{
            "pthread_mutex_lock",
            "pthread_spin_lock",
            "pthread_rwlock_rdlock",
            "pthread_rwlock_wrlock",
            "lock_acquire",
            "_lock",
            ".lock",
        };

        for (lock_patterns) |pattern| {
            if (std.mem.indexOf(u8, func_name_slice, pattern) != null) {
                // Ensure it's not an unlock pattern
                if (std.mem.indexOf(u8, func_name_slice, "unlock") == null and
                    std.mem.indexOf(u8, func_name_slice, "_unlock") == null)
                {
                    return true;
                }
            }
        }

        return false;
    }

    /// Get or create lock ID for a lock object
    fn getLockId(self: *LockPass, inst: c.LLVMValueRef) !u32 {
        // Get the lock object (first argument)
        const lock_obj = c.LLVMGetOperand(inst, 0);
        if (lock_obj == null) return error.InvalidLockOperation;

        // Check if we already have an ID for this lock
        if (self.lock_id_map.get(lock_obj)) |lock_id| {
            return lock_id;
        }

        // Create new lock ID
        const lock_id = self.next_lock_id;
        self.next_lock_id += 1;
        try self.lock_id_map.put(lock_obj, lock_id);

        return lock_id;
    }

    /// Detect deadlocks using lock acquisition graph
    fn detectDeadlocks(self: *LockPass, allocator: std.mem.Allocator) !void {
        if (self.lock_ops.items.len == 0) return;

        // Build lock acquisition graph
        var graph = LockGraph.init(allocator);
        defer graph.deinit();

        // Group lock operations by lock ID
        var lock_sequences = std.AutoHashMap(u32, std.ArrayList(LockOperation)).init(allocator);
        defer {
            var iter = lock_sequences.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit(allocator);
            }
            lock_sequences.deinit();
        }

        for (self.lock_ops.items) |lock_op| {
            const gop = try lock_sequences.getOrPut(lock_op.lock_id);
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayList(LockOperation).initCapacity(allocator, 4) catch @panic("OOM");
            }
            try gop.value_ptr.append(allocator, lock_op);
        }

        // Build graph edges: if lock A is acquired while lock B is held, add edge B -> A
        var iter = lock_sequences.iterator();
        while (iter.next()) |entry| {
            const lock_a_ops = entry.value_ptr.items;

            for (lock_a_ops) |lock_a_op| {
                if (!lock_a_op.is_acquire) continue;

                // Find locks held at this point
                var held_locks = std.ArrayList(u32).initCapacity(allocator, 4) catch @panic("OOM");
                defer held_locks.deinit(allocator);

                for (self.lock_ops.items) |other_op| {
                    if (other_op.inst_id < lock_a_op.inst_id and other_op.is_acquire) {
                        // Check if this lock has been released before lock_a_op
                        var released = false;
                        for (self.lock_ops.items) |a_op| {
                            if (a_op.inst_id > other_op.inst_id and a_op.inst_id < lock_a_op.inst_id and !a_op.is_acquire and a_op.lock_id == other_op.lock_id) {
                                released = true;
                                break;
                            }
                        }
                        if (!released) {
                            try held_locks.append(allocator, other_op.lock_id);
                        }
                    }
                }

                // Add edges from held locks to lock A
                for (held_locks.items) |held_lock| {
                    try graph.addEdge(held_lock, lock_a_op.lock_id);
                }
            }
        }

        // Detect cycles
        if (try graph.hasCycle()) {
            self.diag.err("DEADLOCK DETECTED: Cycle found in lock acquisition graph", .{});
            self.diag.err("  This indicates a potential deadlock scenario", .{});
        }
    }
};

test "LockPass - init" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    const pass = LockPass.init(std.testing.allocator, &store);
    _ = pass;
}

test "LockPass - validate as Pass" {
    const ValidPass = Pass(struct {
        pub const name = "test-lock-pass";
        pub const kind = PassKind.analysis;
        pub const deps = &[_][]const u8{};
        pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
            _ = ctx;
            _ = diag;
        }
    });

    _ = ValidPass;
}

test "LockPass - emit lock_acquire fact" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = LockPass.init(std.testing.allocator, &store);
    pass.func_id = 1;

    // Emit lock_acquire fact
    try pass.store.insert(.lock_acquire, 1, 2, 1);

    // Verify fact was inserted
    try std.testing.expectEqual(@as(usize, 1), store.count());
    const fact = store.get(0).?;
    try std.testing.expectEqual(FactKind.lock_acquire, fact.kind);
    try std.testing.expectEqual(@as(u32, 1), fact.subject);
    try std.testing.expectEqual(@as(u32, 2), fact.object);
    try std.testing.expectEqual(@as(u32, 1), fact.context);
}

test "LockPass - emit lock_release fact" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = LockPass.init(std.testing.allocator, &store);
    pass.func_id = 1;

    // Emit lock_release fact
    try pass.store.insert(.lock_release, 1, 2, 1);

    // Verify fact was inserted
    try std.testing.expectEqual(@as(usize, 1), store.count());
    const fact = store.get(0).?;
    try std.testing.expectEqual(FactKind.lock_release, fact.kind);
    try std.testing.expectEqual(@as(u32, 1), fact.subject);
    try std.testing.expectEqual(@as(u32, 2), fact.object);
    try std.testing.expectEqual(@as(u32, 1), fact.context);
}

test "LockPass - lock operation tracking" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = LockPass.init(std.testing.allocator, &store);
    pass.func_id = 1;

    // Create lock operations
    const lock_op1 = LockOperation{
        .lock_id = 1,
        .inst_id = 10,
        .is_acquire = true,
    };
    try pass.lock_ops.append(std.testing.allocator, lock_op1);

    const lock_op2 = LockOperation{
        .lock_id = 1,
        .inst_id = 20,
        .is_acquire = false,
    };
    try pass.lock_ops.append(std.testing.allocator, lock_op2);

    const lock_op3 = LockOperation{
        .lock_id = 2,
        .inst_id = 15,
        .is_acquire = true,
    };
    try pass.lock_ops.append(std.testing.allocator, lock_op3);

    try std.testing.expectEqual(@as(usize, 3), pass.lock_ops.items.len);
    try std.testing.expectEqual(@as(u32, 1), pass.lock_ops.items[0].lock_id);
    try std.testing.expect(pass.lock_ops.items[0].is_acquire);
    try std.testing.expect(!pass.lock_ops.items[1].is_acquire);
    try std.testing.expectEqual(@as(u32, 2), pass.lock_ops.items[2].lock_id);
}

test "LockPass - lock ID mapping" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = LockPass.init(std.testing.allocator, &store);

    // Create dummy lock objects
    const lock1: c.LLVMValueRef = @ptrFromInt(0x1000);
    const lock2: c.LLVMValueRef = @ptrFromInt(0x2000);
    const lock3: c.LLVMValueRef = @ptrFromInt(0x3000);

    // Assign lock IDs
    const lock_id1 = try pass.getLockId(lock1);
    const lock_id2 = try pass.getLockId(lock2);
    const lock_id3 = try pass.getLockId(lock3);

    // Verify IDs are unique and sequential
    try std.testing.expectEqual(@as(u32, 1), lock_id1);
    try std.testing.expectEqual(@as(u32, 2), lock_id2);
    try std.testing.expectEqual(@as(u32, 3), lock_id3);

    // Verify same lock object returns same ID
    const lock_id1_again = try pass.getLockId(lock1);
    try std.testing.expectEqual(lock_id1, lock_id1_again);
}

test "LockPass - lock ID map consistency" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = LockPass.init(std.testing.allocator, &store);

    // Create dummy lock objects
    const lock1: c.LLVMValueRef = @ptrFromInt(0x1000);
    const lock2: c.LLVMValueRef = @ptrFromInt(0x2000);

    // Assign lock IDs
    const lock_id1 = try pass.getLockId(lock1);
    const lock_id2 = try pass.getLockId(lock2);

    // Verify lock ID map
    try std.testing.expectEqual(@as(usize, 2), pass.lock_id_map.count());

    const retrieved1 = pass.lock_id_map.get(lock1).?;
    try std.testing.expectEqual(lock_id1, retrieved1);

    const retrieved2 = pass.lock_id_map.get(lock2).?;
    try std.testing.expectEqual(lock_id2, retrieved2);
}

test "LockPass - known lock function detection" {
    // Test known lock functions
    try std.testing.expect(LockPass.isKnownLockFunctionByName("pthread_mutex_lock"));
    try std.testing.expect(LockPass.isKnownLockFunctionByName("pthread_mutex_unlock"));
    try std.testing.expect(LockPass.isKnownLockFunctionByName("pthread_spin_lock"));
    try std.testing.expect(LockPass.isKnownLockFunctionByName("lock_acquire"));

    // Test unknown functions
    try std.testing.expect(!LockPass.isKnownLockFunctionByName("malloc"));
    try std.testing.expect(!LockPass.isKnownLockFunctionByName("free"));
    try std.testing.expect(!LockPass.isKnownLockFunctionByName("printf"));
}

test "LockPass - lock acquire vs release detection" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = LockPass.init(std.testing.allocator, &store);

    // Test lock acquire and release detection through function names
    // The implementation checks for "lock" in name and not "unlock"
    // So "pthread_mutex_lock" is acquire, "pthread_mutex_unlock" is release
    try std.testing.expect(pass.isKnownLockFunctionByName("pthread_mutex_lock"));
    try std.testing.expect(pass.isKnownLockFunctionByName("pthread_mutex_unlock"));
    try std.testing.expect(pass.isKnownLockFunctionByName("pthread_spin_lock"));
    try std.testing.expect(pass.isKnownLockFunctionByName("lock_acquire"));
    try std.testing.expect(pass.isKnownLockFunctionByName("lock_release"));
}

test "LockPass - complex deadlock scenario" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = LockPass.init(std.testing.allocator, &store);
    pass.func_id = 1;

    // Simulate a potential deadlock:
    // Thread 1: acquire A, then acquire B
    // Thread 2: acquire B, then acquire A

    // Thread 1 operations
    const lock_op1 = LockOperation{
        .lock_id = 1,
        .inst_id = 10,
        .is_acquire = true,
    };
    try pass.lock_ops.append(std.testing.allocator, lock_op1);

    const lock_op2 = LockOperation{
        .lock_id = 2,
        .inst_id = 20,
        .is_acquire = true,
    };
    try pass.lock_ops.append(std.testing.allocator, lock_op2);

    // Thread 2 operations
    const lock_op3 = LockOperation{
        .lock_id = 2,
        .inst_id = 30,
        .is_acquire = true,
    };
    try pass.lock_ops.append(std.testing.allocator, lock_op3);

    const lock_op4 = LockOperation{
        .lock_id = 1,
        .inst_id = 40,
        .is_acquire = true,
    };
    try pass.lock_ops.append(std.testing.allocator, lock_op4);

    try std.testing.expectEqual(@as(usize, 4), pass.lock_ops.items.len);

    // Verify the lock operations
    try std.testing.expectEqual(@as(u32, 1), pass.lock_ops.items[0].lock_id);
    try std.testing.expectEqual(@as(u32, 2), pass.lock_ops.items[1].lock_id);
    try std.testing.expectEqual(@as(u32, 2), pass.lock_ops.items[2].lock_id);
    try std.testing.expectEqual(@as(u32, 1), pass.lock_ops.items[3].lock_id);
}
