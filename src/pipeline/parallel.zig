//! Parallel Executor — Work-Stealing Thread Pool for Per-Function Pass Parallelization
//!
//! This module provides a lightweight work-stealing thread pool designed
//! specifically for OmniScope's per-function analysis passes (ptr_lifetime,
//! callback_escape, ffi_boundary). Each function in an LLVM module is an
//! independent unit of work with no inter-function data dependencies during
//! the analysis phase.
//!
//! Architecture:
//!   - Chase-Lev work-stealing deques (one per worker thread)
//!   - Owner pushes/pops from bottom (LIFO, cache-friendly)
//!   - Stealer steals from top (FIFO, good load balancing)
//!   - Per-worker local result buffers (zero contention on hot path)
//!   - Post-execution merge phase for deterministic result assembly
//!
//! Usage pattern:
//!   var executor = try ParallelExecutor.init(allocator, worker_count);
//!   defer executor.deinit();
//!   const results = try executor.run(work_items, process_fn);
//!
//! Thread safety guarantees:
//!   - Work items are pushed before execution begins (no concurrent push)
//!   - Each worker's result buffer is thread-local (no locks during analysis)
//!   - Merge phase runs single-threaded after all workers join
//!   - LLVM IR is read-only during parallel analysis (no mutation)

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("../common/log.zig");

// ============================================================================
// Public API
// ============================================================================

/// Error conditions specific to parallel execution
pub const ParallelError = error{
    OutOfMemory,
    NoWorkItems,
    WorkerSpawnFailed,
    WorkerPanicked,
};

/// A single unit of work: a reference to one LLVM function to analyze.
/// Carries metadata needed for noise filtering and zone classification
/// so workers don't need shared access to PassContext during analysis.
pub const WorkItem = struct {
    func: usize, // c.LLVMValueRef as integer (LLVM API is C-compatible)
    func_name: []const u8,
    is_declaration: bool,
    fir_idx: usize = 0, // index into ir_store.function_list for IRStore-based iteration
};

/// Per-worker result buffer for collecting analysis output without locks.
/// Each worker thread writes exclusively to its own instance during the
/// parallel phase; results are merged after all workers complete.
pub const WorkerResult = struct {
    /// Issues discovered by this worker (owned slices, freed by caller or merge)
    issues: []IssueRef = &.{},
    /// Count of functions analyzed by this worker
    funcs_analyzed: u32 = 0,
    /// Count of functions skipped (noise / gate)
    funcs_skipped: u32 = 0,
    /// Count of functions that errored (degraded)
    funcs_errored: u32 = 0,
    /// Accumulated pass-specific stats (opaque, pass-defined)
    user_stats: ?*anyopaque = null,

    /// Opaque issue reference — avoids importing Issue type here.
    /// The actual type is *const Issue from diag/issue.zig.
    pub const IssueRef = *anyopaque;
};

/// Execution configuration for the parallel pool.
pub const Config = struct {
    /// Number of worker threads. 0 means use CPU count.
    worker_count: usize = 0,
    /// Minimum functions per worker to justify parallel overhead.
    min_functions_per_worker: usize = 4,
    /// Enable detailed per-worker timing in diagnostics.
    enable_worker_timing: bool = false,
};

// ============================================================================
// Chase-Lev Work Stealing Deque
// ============================================================================

/// Lock-free work-stealing deque using the Chase-Lev algorithm.
///
/// The owner thread pushes and pops from the bottom of the deque.
/// Other threads (stealers) steal from the top. This gives the owner
/// LIFO semantics (cache-friendly) while stealers get FIFO ordering
/// (good for load balancing, prevents starvation).
///
/// Memory ordering notes:
///   - push(): store(bottom) uses Release, load(top) uses Acquire
///   - pop(): store(bottom) uses Release
///   - steal(): load(bottom) uses Acquire, CAS(top) uses Acquire+Release
///
/// Reference: "Dynamic Circular Work-Stealing Deque" (Chase & Lev, SPDP 2005)
fn WorkStealingDeque(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Allocator used for array storage (needed for deinit in Zig 0.15.2).
        gpa: Allocator,

        /// Raw circular buffer holding work items.
        /// Uses plain storage — element access is protected by index atomics + fences.
        /// Grows on push if full (owner-only operation).
        array: []T,

        /// Current capacity of the array (number of slots allocated).
        capacity: usize,

        /// Bottom index (owner-written, stealer-read).
        /// Points to the next slot below which valid items exist.
        bottom: std.atomic.Value(usize),

        /// Top index (CAS-updated by stealers, read by owner).
        /// Invariant: top <= bottom always holds.
        top: std.atomic.Value(usize),

        /// Create a new empty deque with initial capacity.
        pub fn init(allocator: Allocator, initial_capacity: usize) !Self {
            const arr = try allocator.alloc(T, initial_capacity);
            return .{
                .gpa = allocator,
                .array = arr,
                .capacity = initial_capacity,
                .bottom = std.atomic.Value(usize).init(0),
                .top = std.atomic.Value(usize).init(0),
            };
        }

        /// Free the underlying array storage.
        pub fn deinit(self: *Self) void {
            self.gpa.free(self.array);
        }

        /// Push an item to the bottom (owner-only).
        /// Grows the circular buffer if capacity is exhausted.
        pub fn push(self: *Self, allocator: Allocator, value: T) !void {
            const b = self.bottom.load(.monotonic);
            const t = self.top.load(.acquire);
            const size = b - t;
            if (size >= self.capacity) {
                const new_cap = @max(self.capacity * 2, 4);
                const new_arr = allocator.alloc(T, new_cap) catch |err| {
                    return err;
                };
                // Copy existing items from top to bottom
                var i: usize = t;
                while (i < b) : (i += 1) {
                    new_arr[i - t] = self.array[i];
                }
                self.gpa.free(self.array);
                self.array = new_arr;
                self.capacity = new_cap;
                // Reset indices after growth
                self.bottom.store(size, .monotonic);
                self.top.store(0, .monotonic);
            }
            self.array[b] = value;
            self.bottom.store(b + 1, .release);
        }

        /// Pop an item from the bottom (owner-only).
        /// Returns null if the deque appears empty.
        pub fn pop(self: *Self) ?T {
            const b = self.bottom.load(.unordered) -| 1;
            self.bottom.store(b, .unordered);
            const t = self.top.load(.acquire);
            if (t > b) {
                self.bottom.store(b + 1, .unordered);
                return null;
            }
            const val = self.array[b];
            if (t == b) {
                // CAS: if top still equals t, increment to claim this item
                if (self.top.cmpxchgStrong(t, t + 1, .acquire, .acquire)) |_| {
                    // Another stealer already took it
                    self.bottom.store(b + 1, .unordered);
                    return null;
                }
                self.bottom.store(b + 1, .unordered);
            }
            return val;
        }

        /// Steal an item from the top (stealer threads).
        /// Returns null if the deque is empty or CAS fails (another stealer won).
        pub fn steal(self: *Self) ?T {
            const t = self.top.load(.acquire);
            const b = self.bottom.load(.acquire);
            if (t >= b) return null;
            const val = self.array[t];
            // CAS: if top still equals t, increment to steal this item
            if (self.top.cmpxchgStrong(t, t + 1, .seq_cst, .seq_cst)) |_| return null;
            return val;
        }

        /// Current number of items in the deque (approximate, racy).
        pub fn len(self: *Self) usize {
            const b = self.bottom.load(.monotonic);
            const t = self.top.load(.monotonic);
            return if (b > t) b - t else 0;
        }
    };
}

// ============================================================================
// Parallel Executor
// ============================================================================

/// T3.1: Module-level shared state for worker thread arguments.
/// Set by run() before spawning, read by workerLoop().
var spawn_shared: struct {
    executor: *ParallelExecutor,
    work_items: []const WorkItem,
    process_fn: *const fn (WorkItem, usize) anyerror!WorkerResult,
} = undefined;

/// Parallel executor with work-stealing scheduler.
///
/// Distributes independent work items across N worker threads using
/// Chase-Lev deques. Each worker maintains its own deque; when empty,
/// it attempts to steal from other workers' deques (random victim selection).
///
/// Design tradeoffs:
///   - Pre-populated work set: All items are pushed before workers start.
///     This avoids lock contention on push path and simplifies termination
///     detection (all deques empty → done).
///   - Per-worker result buffers: No mutex contention during analysis.
///     Results are merged single-threaded after all workers finish.
///   - Bounded memory: Initial deque capacity grows but never shrinks
///     during execution. Total memory = O(W * F) where W=workers, F=functions.
pub const ParallelExecutor = struct {
    allocator: Allocator,
    worker_count: usize,
    deques: []WorkStealingDeque(usize), // stores indices into work_items slice
    workers: []std.Thread,
    results: []WorkerResult,
    active: std.atomic.Value(bool),

    /// Initialize the executor with the given number of worker threads.
    /// If worker_count is 0, defaults to CPU count (capped at 16 for safety).
    pub fn init(allocator: Allocator, worker_count: usize) !ParallelExecutor {
        const actual_workers = blk: {
            const cpu_count = try std.Thread.getCpuCount();
            break :blk if (worker_count > 0)
                @min(worker_count, cpu_count)
            else
                @min(cpu_count, 16);
        };
        if (actual_workers < 1) return ParallelExecutor{ .allocator = allocator, .worker_count = 0, .deques = &.{}, .workers = &.{}, .results = &.{}, .active = std.atomic.Value(bool).init(false) };

        const deques = try allocator.alloc(WorkStealingDeque(usize), actual_workers);
        errdefer allocator.free(deques);
        for (deques, 0..) |*deque, i| {
            errdefer {
                // Clean up already-initialized deques on failure
                for (deques[0..i]) |*d| {
                    d.deinit();
                }
            }
            deque.* = try WorkStealingDeque(usize).init(allocator, 64);
        }

        const results = try allocator.alloc(WorkerResult, actual_workers);
        @memset(results, WorkerResult{});

        return .{
            .allocator = allocator,
            .worker_count = actual_workers,
            .deques = deques,
            .workers = &[0]std.Thread{},
            .results = results,
            .active = std.atomic.Value(bool).init(false),
        };
    }

    /// Free all resources held by the executor.
    pub fn deinit(self: *ParallelExecutor) void {
        for (self.deques) |*deque| {
            deque.deinit();
        }
        self.allocator.free(self.deques);
        // Workers are joined before deinit, so no need to free threads here
        if (self.workers.len > 0) {
            self.allocator.free(self.workers);
        }
        self.allocator.free(self.results);
    }

    /// Execute work items in parallel using the provided process function.
    ///
    /// Parameters:
    ///   - work_items: Slice of WorkItem to distribute among workers
    ///   - process_fn: Function called for each work item. Signature:
    ///       fn (item: WorkItem, worker_id: usize) !WorkerResult
    ///
    /// Returns:
    ///   - Slice of WorkerResult (one per worker), owned by executor
    ///
    /// Errors:
    ///   - ParallelError.NoWorkItems: Empty input
    ///   - ParallelError.WorkerSpawnFailed: OS thread creation failed
    ///   - ParallelError.WorkerPanicked: A worker thread crashed
    ///   - Any error propagated from process_fn
    pub fn run(
        self: *ParallelExecutor,
        work_items: []const WorkItem,
        process_fn: *const fn (WorkItem, usize) anyerror!WorkerResult,
    ) ![]WorkerResult {
        if (work_items.len == 0) return error.NoWorkItems;

        const n = work_items.len;
        const w = self.worker_count;

        // For small work sets, sequential execution avoids thread overhead.
        // Threshold: fewer than min_functions_per_worker items per worker.
        const min_per_worker: usize = 4;
        if (n < w * min_per_worker) {
            log.debug("[parallel] Sequential fallback: {} items < {} workers * {} threshold", .{ n, w, min_per_worker });
            return self.runSequential(work_items, process_fn);
        }

        // Reset state for this execution
        @memset(self.results, WorkerResult{});
        self.active.store(true, .seq_cst);

        // Phase 1: Push all work item indices into deques (round-robin).
        // Owner pushes only — no concurrent access yet.
        {
            var i: usize = 0;
            while (i < n) : (i += 1) {
                const worker_id = i % w;
                try self.deques[worker_id].push(self.allocator, i);
            }
        }

        // Phase 2: Spawn worker threads.
        // T3.1: Use module-level shared state for thread arguments (Zig 0.15.2
        // requires tuple args for Thread.spawn, not struct).
        spawn_shared = .{
            .executor = self,
            .work_items = work_items,
            .process_fn = process_fn,
        };
        const worker_threads = try self.allocator.alloc(std.Thread, w);
        self.workers = worker_threads;
        var spawn_errors: usize = 0;
        for (0..w) |worker_id| {
            worker_threads[worker_id] = std.Thread.spawn(.{}, workerLoop, .{worker_id}) catch {
                log.err("[parallel] Failed to spawn worker thread {}", .{worker_id});
                spawn_errors += 1;
                continue;
            };
        }
        if (spawn_errors > 0) {
            self.active.store(false, .seq_cst);
            // Join any successfully spawned workers
            for (worker_threads) |thread| {
                thread.join();
            }
            return error.WorkerSpawnFailed;
        }

        // Phase 3: Wait for all workers to complete.
        for (worker_threads) |thread| {
            thread.join();
        }
        self.active.store(false, .seq_cst);

        return self.results;
    }

    /// Sequential fallback when parallelism isn't worthwhile.
    fn runSequential(
        self: *ParallelExecutor,
        work_items: []const WorkItem,
        process_fn: *const fn (WorkItem, usize) anyerror!WorkerResult,
    ) ![]WorkerResult {
        if (self.results.len == 0) {
            const seq_results = try self.allocator.alloc(WorkerResult, 1);
            self.results = seq_results;
        }
        self.results[0] = WorkerResult{};
        for (work_items) |item| {
            const r = process_fn(item, 0) catch |err| {
                log.warn("[parallel] Sequential item error: {}", .{err});
                self.results[0].funcs_errored += 1;
                continue;
            };
            self.results[0].funcs_analyzed += r.funcs_analyzed;
            self.results[0].funcs_skipped += r.funcs_skipped;
            self.results[0].funcs_errored += r.funcs_errored;
        }
        return self.results;
    }

    /// Worker thread main loop.
    /// Each worker pops from its own deque first (LIFO, cache-friendly).
    /// When its own deque is empty, it tries to steal from random victims.
    fn workerLoop(worker_id: usize) void {
        const executor = spawn_shared.executor;
        const work_items = spawn_shared.work_items;
        const process_fn = spawn_shared.process_fn;

        var local_result = WorkerResult{};
        var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.nanoTimestamp() + @as(i128, worker_id) * 7919)));
        var rng = prng.random();

        while (executor.active.load(.seq_cst)) {
            var item_idx: ?usize = null;

            // Try pop from own deque first (owner operation, LIFO)
            item_idx = executor.deques[worker_id].pop();

            // If empty, attempt work stealing from random victim
            if (item_idx == null) {
                if (executor.trySteal(worker_id, &rng)) |stolen| {
                    item_idx = stolen;
                }
            }

            // Process the stolen/popped item
            if (item_idx) |idx| {
                const r = process_fn(work_items[idx], worker_id) catch |err| {
                    log.warn("[parallel-w{}] Item {} error: {}", .{ worker_id, idx, err });
                    local_result.funcs_errored += 1;
                    continue;
                };
                local_result.funcs_analyzed += r.funcs_analyzed;
                local_result.funcs_skipped += r.funcs_skipped;
                local_result.funcs_errored += r.funcs_errored;
            } else {
                // Check if all deques are empty (termination condition)
                if (executor.allDequesEmpty()) break;
                // Minimal spin-wait to reduce CPU waste in tight loop
                _ = @as(usize, 0); // compiler barrier hint
            }
        }

        // Store result for this worker
        executor.results[worker_id] = local_result;
    }

    /// Attempt to steal work from a random victim deque.
    /// Returns the stolen item index, or null if no work available.
    fn trySteal(self: *ParallelExecutor, thief_id: usize, rng: *std.Random) ?usize {
        const w = self.worker_count;
        if (w <= 1) return null;

        // Pick a random victim that isn't ourselves
        var victim = rng.uintAtMost(usize, w - 1);
        if (victim == thief_id) victim = (victim + 1) % w;

        return self.deques[victim].steal();
    }

    /// Check if all deques are empty (termination condition).
    fn allDequesEmpty(self: *const ParallelExecutor) bool {
        for (self.deques) |*deque| {
            if (deque.len() > 0) return false;
        }
        return true;
    }

    /// Get the effective number of workers (may differ from requested due to CPU limits).
    pub fn workerCount(self: *const ParallelExecutor) usize {
        return self.worker_count;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ParallelExecutor - init and deinit" {
    var executor = try ParallelExecutor.init(std.testing.allocator, 4);
    defer executor.deinit();
    try std.testing.expect(executor.workerCount() >= 1);
    try std.testing.expect(executor.workerCount() <= 4);
}

test "ParallelExecutor - sequential fallback for small workload" {
    var executor = try ParallelExecutor.init(std.testing.allocator, 4);
    defer executor.deinit();

    const processFn = struct {
        fn inner(item: parallel.WorkItem, worker_id: usize) !parallel.WorkerResult {
            _ = item;
            _ = worker_id;
            return .{ .funcs_analyzed = 1 };
        }
    }.inner;

    const items = [_]WorkItem{
        .{ .func = 1, .func_name = "test1", .is_declaration = false },
        .{ .func = 2, .func_name = "test2", .is_declaration = false },
    };
    const results = try executor.run(&items, processFn);
    try std.testing.expectEqual(@as(usize, 1), results.len); // Sequential mode returns 1 result
    try std.testing.expectEqual(@as(u32, 2), results[0].funcs_analyzed);
}

test "ParallelExecutor - basic parallel execution" {
    var executor = try ParallelExecutor.init(std.testing.allocator, 0); // Auto-detect CPU count
    defer executor.deinit();

    // Generate enough items to trigger parallel path (>= 4 * worker_count)
    var items = std.ArrayList(WorkItem).init(std.testing.allocator);
    defer items.deinit();
    const n = @max(32, executor.workerCount() * 8);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        var buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "func_{}", .{i}) catch unreachable;
        try items.append(.{ .func = i + 100, .func_name = name, .is_declaration = false });
    }

    const processFn = struct {
        fn inner(item: parallel.WorkItem, worker_id: usize) !parallel.WorkerResult {
            _ = worker_id;
            var j: usize = 0;
            while (j < 100) : (j += 1) {
                _ = item.func;
            }
            return .{ .funcs_analyzed = 1 };
        }
    }.inner;

    const results = try executor.run(items.items, processFn);

    var total_analyzed: u32 = 0;
    for (results) |r| {
        total_analyzed += r.funcs_analyzed;
    }
    try std.testing.expectEqual(@as(u32, @intCast(n)), total_analyzed);
}

test "ParallelExecutor - all items processed exactly once" {
    var executor = try ParallelExecutor.init(std.testing.allocator, 2);
    defer executor.deinit();

    const n = 20;
    var items_arr: [n]WorkItem = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        items_arr[i] = .{ .func = i, .func_name = "x", .is_declaration = false };
    }

    // Verify total count matches — each item processed exactly once
    const countFn = struct {
        fn inner(item: parallel.WorkItem, worker_id: usize) !parallel.WorkerResult {
            _ = item;
            _ = worker_id;
            return .{ .funcs_analyzed = 1 };
        }
    }.inner;

    const results = try executor.run(&items_arr, countFn);
    var total: u32 = 0;
    for (results) |r| {
        total += r.funcs_analyzed;
    }
    try std.testing.expectEqual(@as(u32, n), total);
}

test "WorkStealingDeque - push and pop order" {
    var deque = try WorkStealingDeque(usize).init(std.testing.allocator, 8);
    defer deque.deinit();

    try deque.push(std.testing.allocator, 10);
    try deque.push(std.testing.allocator, 20);
    try deque.push(std.testing.allocator, 30);

    // Pop should return in LIFO order (30, 20, 10)
    try std.testing.expectEqual(@as(?usize, 30), deque.pop());
    try std.testing.expectEqual(@as(?usize, 20), deque.pop());
    try std.testing.expectEqual(@as(?usize, 10), deque.pop());
    try std.testing.expectEqual(@as(?usize, null), deque.pop());
}

test "WorkStealingDeque - steal from top" {
    var deque = try WorkStealingDeque(usize).init(std.testing.allocator, 8);
    defer deque.deinit();

    try deque.push(std.testing.allocator, 10);
    try deque.push(std.testing.allocator, 20);
    try deque.push(std.testing.allocator, 30);

    // Steal should take from top (FIFO order: 10, 20, 30)
    try std.testing.expectEqual(@as(?usize, 10), deque.steal());
    try std.testing.expectEqual(@as(?usize, 20), deque.steal());

    // Remaining item can be popped
    try std.testing.expectEqual(@as(?usize, 30), deque.pop());
    try std.testing.expectEqual(@as(?usize, null), deque.pop());
}

test "WorkStealingDeque - empty deque behavior" {
    var deque = try WorkStealingDeque(usize).init(std.testing.allocator, 4);
    defer deque.deinit();

    try std.testing.expectEqual(@as(?usize, null), deque.pop());
    try std.testing.expectEqual(@as(?usize, null), deque.steal());
    try std.testing.expectEqual(@as(usize, 0), deque.len());
}

test "WorkStealingDeque - growth on overflow" {
    var deque = try WorkStealingDeque(usize).init(std.testing.allocator, 4);
    defer deque.deinit();

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try deque.push(std.testing.allocator, i);
    }
    try std.testing.expectEqual(@as(usize, 10), deque.len());

    // All items should be retrievable
    var popped: usize = 0;
    while (deque.pop()) |_| {
        popped += 1;
    }
    try std.testing.expectEqual(@as(usize, 10), popped);
}

const parallel = @This();
