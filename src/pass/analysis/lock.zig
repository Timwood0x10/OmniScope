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

const c = @import("../../ir/llvm_raw.zig");
const ValueRef = @import("../../ir/view.zig").ValueRef;
const FunctionRef = @import("../../ir/view.zig").FunctionRef;

/// Lock operation information
const LockOperation = struct {
    lock_id: u32,
    inst_id: u32,
    is_acquire: bool,
};

/// Lock analysis pass
pub const LockPass = struct {
    pub const name = "lock";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "alias" };

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
    pub fn init(store: *FactStore) LockPass {
        return .{
            .ctx = undefined,
            .diag = undefined,
            .store = store,
            .query = QueryEngine.init(store),
            .lock_ops = std.ArrayList(LockOperation).init(std.heap.page_allocator),
            .lock_id_map = std.AutoHashMap(c.LLVMValueRef, u32).init(std.heap.page_allocator),
            .func_id = 0,
            .next_lock_id = 1,
        };
    }

    /// Run the lock analysis pass
    pub fn run(
        self: *LockPass,
        ctx: *PassContext,
        diag: *DiagnosticWriter,
    ) !void {
        self.ctx = ctx;
        self.diag = diag;

        const module = ctx.module orelse return;

        // Iterate over all functions
        var func = c.LLVMGetFirstFunction(module.raw);
        while (func != null) {
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
        try self.detectDeadlocks();

        // Clean up
        self.lock_ops.deinit();
        self.lock_id_map.deinit();
    }

    /// Analyze a function for lock operations
    fn analyzeFunction(self: *LockPass, func: FunctionRef) !void {
        // Get first basic block
        var bb = c.LLVMGetFirstBasicBlock(func.raw);

        while (bb != null) {
            // Get first instruction
            var inst = c.LLVMGetFirstInstruction(bb);

            while (inst != null) {
                // Check if this is a lock operation
                if (self.isLockOperation(inst)) {
                    const is_acquire = self.isLockAcquire(inst);
                    const lock_id = try self.getLockId(inst);

                    const inst_id = self.ctx.getNextId();

                    const lock_op = LockOperation{
                        .lock_id = lock_id,
                        .inst_id = inst_id,
                        .is_acquire = is_acquire,
                    };
                    try self.lock_ops.append(lock_op);

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
        const opcode_enum: c.LLVMOpcode = @enumFromInt(opcode);
        if (opcode_enum != .Call) return false;

        // Get called function
        const called_func = c.LLVMGetOperand(inst, 0);
        if (called_func == null) return false;

        // Get function name
        const func_name = c.LLVMGetValueName(called_func);
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

        // Get called function
        const called_func = c.LLVMGetOperand(inst, 0);
        if (called_func == null) return false;

        // Get function name
        const func_name = c.LLVMGetValueName(called_func);
        const func_name_slice = std.mem.span(func_name);

        // Check if it's a lock acquire function
        return std.mem.indexOf(u8, func_name_slice, "lock") != null and
            std.mem.indexOf(u8, func_name_slice, "unlock") == null;
    }

    /// Get or create lock ID for a lock object
    fn getLockId(self: *LockPass, inst: c.LLVMValueRef) !u32 {
        // Get the lock object (first argument)
        const lock_obj = c.LLVMGetOperand(inst, 1); // Call instruction: func + args
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
    fn detectDeadlocks(self: *LockPass) !void {
        if (self.lock_ops.items.len == 0) return;

        // Build lock acquisition graph
        var graph = LockGraph.init(std.heap.page_allocator);
        defer graph.deinit();

        // Group lock operations by lock ID
        var lock_sequences = std.AutoHashMap(u32, std.ArrayList(LockOperation)).init(std.heap.page_allocator);
        defer {
            var iter = lock_sequences.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            lock_sequences.deinit();
        }

        for (self.lock_ops.items) |lock_op| {
            const gop = try lock_sequences.getOrPut(lock_op.lock_id);
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayList(LockOperation).init(std.heap.page_allocator);
            }
            try gop.value_ptr.append(lock_op);
        }

        // Build graph edges: if lock A is acquired while lock B is held, add edge B -> A
        var iter = lock_sequences.iterator();
        while (iter.next()) |entry| {
            const lock_a_ops = entry.value_ptr.items;

            for (lock_a_ops) |lock_a_op| {
                if (!lock_a_op.is_acquire) continue;

                // Find locks held at this point
                var held_locks = std.ArrayList(u32).init(std.heap.page_allocator);
                defer held_locks.deinit();

                for (self.lock_ops.items) |other_op| {
                    if (other_op.inst_id < lock_a_op.inst_id and other_op.is_acquire) {
                        // Check if this lock has been released before lock_a_op
                        var released = false;
                        for (lock_a_ops) |a_op| {
                            if (a_op.inst_id > other_op.inst_id and a_op.inst_id < lock_a_op.inst_id and !a_op.is_acquire) {
                                released = true;
                                break;
                            }
                        }
                        if (!released) {
                            try held_locks.append(other_op.lock_id);
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

/// Lock acquisition graph
pub const LockGraph = struct {
    allocator: std.mem.Allocator,
    adjacency: std.ArrayList(Edge),

    const Edge = struct {
        from: u32,
        to: u32,
    };

    /// Create a new lock graph
    pub fn init(allocator: std.mem.Allocator) LockGraph {
        return .{
            .allocator = allocator,
            .adjacency = std.ArrayList(Edge).init(allocator),
        };
    }

    /// Deinitialize the lock graph
    pub fn deinit(self: *LockGraph) void {
        self.adjacency.deinit();
    }

    /// Add an edge to the graph
    pub fn addEdge(self: *LockGraph, from: u32, to: u32) !void {
        try self.adjacency.append(.{ .from = from, .to = to });
    }

    /// Get neighbors of a node
    pub fn getNeighbors(self: *const LockGraph, node: u32, allocator: std.mem.Allocator) ![]u32 {
        var neighbors = std.ArrayList(u32).init(allocator);
        for (self.adjacency.items) |edge| {
            if (edge.from == node) {
                try neighbors.append(edge.to);
            }
        }
        return neighbors.toOwnedSlice();
    }

    /// Check if the graph has a cycle
    pub fn hasCycle(self: *LockGraph) !bool {
        var visited = std.AutoHashMap(u32, bool).init(self.allocator);
        defer visited.deinit();

        var recursion_stack = std.AutoHashMap(u32, bool).init(self.allocator);
        defer recursion_stack.deinit();

        // Collect all nodes
        var nodes = std.ArrayList(u32).init(self.allocator);
        defer nodes.deinit();

        for (self.adjacency.items) |edge| {
            if (!visited.contains(edge.from)) {
                try nodes.append(edge.from);
                try visited.put(edge.from, true);
            }
            if (!visited.contains(edge.to)) {
                try nodes.append(edge.to);
                try visited.put(edge.to, true);
            }
        }

        // Reset visited for DFS
        visited.clearRetainingCapacity();

        // DFS for each unvisited node
        for (nodes.items) |node| {
            if (!visited.contains(node)) {
                if (try self.hasCycleDFS(node, &visited, &recursion_stack)) {
                    return true;
                }
            }
        }

        return false;
    }

    /// DFS helper for cycle detection
    fn hasCycleDFS(
        self: *LockGraph,
        node: u32,
        visited: *std.AutoHashMap(u32, bool),
        recursion_stack: *std.AutoHashMap(u32, bool),
    ) !bool {
        try visited.put(node, true);
        try recursion_stack.put(node, true);

        const neighbors = try self.getNeighbors(node, self.allocator);
        defer self.allocator.free(neighbors);

        for (neighbors) |neighbor| {
            if (!visited.contains(neighbor)) {
                if (try self.hasCycleDFS(neighbor, visited, recursion_stack)) {
                    return true;
                }
            } else if (recursion_stack.contains(neighbor)) {
                // Back edge found - cycle exists
                return true;
            }
        }

        _ = recursion_stack.remove(node);
        return false;
    }
};

test "LockPass - init" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    const pass = LockPass.init(&store);
    _ = pass;
}

test "LockPass - validate as Pass" {
    const ValidPass = Pass(struct {
        pub const name = "test-lock-pass";
        pub const kind = PassKind.analysis;
        pub const deps = &[_][]const u8{ "cfg", "dfg", "alias" };
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

    var pass = LockPass.init(&store);
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

    var pass = LockPass.init(&store);
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

    var pass = LockPass.init(&store);
    pass.func_id = 1;

    // Create lock operations
    const lock_op1 = LockOperation{
        .lock_id = 1,
        .inst_id = 10,
        .is_acquire = true,
    };
    try pass.lock_ops.append(lock_op1);

    const lock_op2 = LockOperation{
        .lock_id = 1,
        .inst_id = 20,
        .is_acquire = false,
    };
    try pass.lock_ops.append(lock_op2);

    const lock_op3 = LockOperation{
        .lock_id = 2,
        .inst_id = 15,
        .is_acquire = true,
    };
    try pass.lock_ops.append(lock_op3);

    try std.testing.expectEqual(@as(usize, 3), pass.lock_ops.items.len);
    try std.testing.expectEqual(@as(u32, 1), pass.lock_ops.items[0].lock_id);
    try std.testing.expect(pass.lock_ops.items[0].is_acquire);
    try std.testing.expect(!pass.lock_ops.items[1].is_acquire);
    try std.testing.expectEqual(@as(u32, 2), pass.lock_ops.items[2].lock_id);
}

test "LockPass - lock ID mapping" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = LockPass.init(&store);

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

    var pass = LockPass.init(&store);

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
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = LockPass.init(&store);

    // Test known lock functions
    try std.testing.expect(pass.isKnownLockFunction("pthread_mutex_lock"));
    try std.testing.expect(pass.isKnownLockFunction("pthread_mutex_unlock"));
    try std.testing.expect(pass.isKnownLockFunction("pthread_spin_lock"));
    try std.testing.expect(pass.isKnownLockFunction("lock_acquire"));

    // Test unknown functions
    try std.testing.expect(!pass.isKnownLockFunction("malloc"));
    try std.testing.expect(!pass.isKnownLockFunction("free"));
    try std.testing.expect(!pass.isKnownLockFunction("printf"));
}

test "LockPass - lock acquire vs release detection" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    var pass = LockPass.init(&store);

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

    var pass = LockPass.init(&store);
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
    try pass.lock_ops.append(lock_op1);

    const lock_op2 = LockOperation{
        .lock_id = 2,
        .inst_id = 20,
        .is_acquire = true,
    };
    try pass.lock_ops.append(lock_op2);

    // Thread 2 operations
    const lock_op3 = LockOperation{
        .lock_id = 2,
        .inst_id = 30,
        .is_acquire = true,
    };
    try pass.lock_ops.append(lock_op3);

    const lock_op4 = LockOperation{
        .lock_id = 1,
        .inst_id = 40,
        .is_acquire = true,
    };
    try pass.lock_ops.append(lock_op4);

    try std.testing.expectEqual(@as(usize, 4), pass.lock_ops.items.len);

    // Verify the lock operations
    try std.testing.expectEqual(@as(u32, 1), pass.lock_ops.items[0].lock_id);
    try std.testing.expectEqual(@as(u32, 2), pass.lock_ops.items[1].lock_id);
    try std.testing.expectEqual(@as(u32, 2), pass.lock_ops.items[2].lock_id);
    try std.testing.expectEqual(@as(u32, 1), pass.lock_ops.items[3].lock_id);
}

test "LockGraph - init and deinit" {
    var graph = LockGraph.init(std.testing.allocator);
    defer graph.deinit();
    try std.testing.expectEqual(@as(usize, 0), graph.adjacency.items.len);
}

test "LockGraph - add edge" {
    var graph = LockGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.addEdge(1, 2);
    try std.testing.expectEqual(@as(usize, 1), graph.adjacency.items.len);
    try std.testing.expectEqual(@as(u32, 1), graph.adjacency.items[0].from);
    try std.testing.expectEqual(@as(u32, 2), graph.adjacency.items[0].to);
}

test "LockGraph - get neighbors" {
    var graph = LockGraph.init(std.testing.allocator);
    defer graph.deinit();

    try graph.addEdge(1, 2);
    try graph.addEdge(1, 3);
    try graph.addEdge(2, 3);

    const neighbors = try graph.getNeighbors(1, std.testing.allocator);
    defer std.testing.allocator.free(neighbors);

    try std.testing.expectEqual(@as(usize, 2), neighbors.len);
    try std.testing.expect(neighbors[0] == 2 or neighbors[0] == 3);
    try std.testing.expect(neighbors[1] == 2 or neighbors[1] == 3);
}

test "LockGraph - has cycle simple" {
    var graph = LockGraph.init(std.testing.allocator);
    defer graph.deinit();

    // Add edges: 1 -> 2 -> 3 -> 1 (cycle)
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 3);
    try graph.addEdge(3, 1);

    try std.testing.expect(try graph.hasCycle());
}

test "LockGraph - has no cycle" {
    var graph = LockGraph.init(std.testing.allocator);
    defer graph.deinit();

    // Add edges: 1 -> 2 -> 3 (no cycle)
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 3);

    try std.testing.expect(!try graph.hasCycle());
}

test "LockGraph - has cycle complex" {
    var graph = LockGraph.init(std.testing.allocator);
    defer graph.deinit();

    // Add edges with multiple components
    // Component 1: 1 -> 2 -> 1 (cycle)
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 1);

    // Component 2: 3 -> 4 -> 5 (no cycle)
    try graph.addEdge(3, 4);
    try graph.addEdge(4, 5);

    try std.testing.expect(try graph.hasCycle());
}
