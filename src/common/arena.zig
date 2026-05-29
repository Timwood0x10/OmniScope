//! Bump-pointer Arena Allocator for temporary allocations.
//!
//! This module provides a high-performance arena allocator that uses bump pointer
//! allocation for O(1) allocation and O(1) batch deallocation (reset).
//!
//! Design principles:
//! - All allocations are freed at once when the arena is reset or deinitialized
//! - Block chaining: when current block is exhausted, allocate a new block
//! - Supports Zig's Alignment requirements (u29 log2 format)
//! - No individual free: this is by design to achieve maximum performance
//!
//! Use cases:
//! - Temporary allocations during analysis passes (HashMap nodes, ArrayList elements)
//! - Short-lived data structures that can be bulk-freed
//! - Reducing memory fragmentation from frequent alloc/free cycles
//!
//! Example:
//!
//! ```zig
//! var arena = Arena.init(allocator);
//! defer arena.deinit();
//!
//! const arena_alloc = arenaAllocator(&arena);
//! const data = try arena_alloc.alloc(u8, 1024);
//! // ... use data ...
//! arena.reset(); // frees all allocations at once
//! ```

const std = @import("std");
const log = @import("log.zig");

/// Default block size for new allocations (8 KB).
///
/// Chosen as a balance between:
/// - Large enough to amortize allocation overhead
/// - Small enough to avoid wasting memory on sparse usage
const default_block_size: usize = 8 * 1024;

/// Minimum alignment requirement (matches Zig's minimum).
const min_alignment: u29 = 0; // log2(1) = 0

/// Statistics for arena allocator usage.
///
/// Tracks allocation and deallocation counts, bytes used, and performance metrics.
pub const ArenaStats = struct {
    /// Total number of allocations made through this arena.
    allocation_count: usize = 0,
    /// Total number of resets performed.
    reset_count: usize = 0,
    /// Total number of bytes allocated (including unused space in blocks).
    bytes_allocated: usize = 0,
    /// Total number of bytes actually used by allocations.
    bytes_used: usize = 0,
    /// Number of memory blocks currently allocated.
    block_count: usize = 0,
    /// Size of blocks allocated (in bytes).
    block_size: usize = default_block_size,

    /// Calculate memory utilization ratio (bytes_used / bytes_allocated).
    ///
    /// Returns a value between 0.0 and 1.0, where 1.0 means perfect utilization.
    pub fn utilization(self: *const ArenaStats) f64 {
        if (self.bytes_allocated == 0) return 0.0;
        return @as(f64, @floatFromInt(self.bytes_used)) / @as(f64, @floatFromInt(self.bytes_allocated));
    }

    /// Calculate average allocation size.
    ///
    /// Returns the average bytes per allocation, or 0 if no allocations.
    pub fn averageAllocationSize(self: *const ArenaStats) f64 {
        if (self.allocation_count == 0) return 0.0;
        return @as(f64, @floatFromInt(self.bytes_used)) / @as(f64, @floatFromInt(self.allocation_count));
    }
};

/// Bump-pointer arena allocator for temporary allocations.
///
/// All allocations are freed at once when the arena is reset or deinitialized.
/// Uses linked list of memory blocks with bump pointer allocation within each block.
pub const Arena = struct {
    /// Backing allocator used for block allocation.
    backing_allocator: std.mem.Allocator,
    /// Head of the block linked list (first/oldest block).
    blocks: ?*Block,
    /// Current block being allocated from (tail of the list).
    current_block: ?*Block,
    /// Current offset within the current block (bump pointer).
    current_offset: usize,
    /// Size for newly allocated blocks (default_block_size for first, then user-specified).
    block_size: usize,
    /// Statistics for tracking usage.
    stats: ArenaStats,

    /// Initialize a new arena with the given backing allocator.
    ///
    /// The backing allocator is used only for allocating blocks,
    /// not for individual user allocations.
    ///
    /// Arguments:
    ///   backing_allocator - Allocator to use for block memory
    ///
    /// Returns:
    ///   Initialized Arena ready for use
    pub fn init(backing_allocator: std.mem.Allocator) Arena {
        return .{
            .backing_allocator = backing_allocator,
            .blocks = null,
            .current_block = null,
            .current_offset = 0,
            .block_size = default_block_size,
            .stats = ArenaStats{},
        };
    }

    /// Initialize a new arena with custom block size.
    ///
    /// Use this constructor when you want to control the block size for
    /// performance tuning. Larger blocks reduce allocation overhead but
    /// may waste memory for sparse usage patterns.
    ///
    /// Arguments:
    ///   backing_allocator - Allocator to use for block memory
    ///   block_size - Size for new blocks (must be > 0)
    ///
    /// Returns:
    ///   Initialized Arena ready for use
    pub fn initWithBlockSize(backing_allocator: std.mem.Allocator, block_size: usize) Arena {
        return .{
            .backing_allocator = backing_allocator,
            .blocks = null,
            .current_block = null,
            .current_offset = 0,
            .block_size = @max(block_size, 1024), // Minimum 1KB
            .stats = ArenaStats{ .block_size = @max(block_size, 1024) },
        };
    }

    /// Deinitialize the arena and free all blocks.
    ///
    /// After calling this, the arena must not be used.
    /// All pointers obtained from this arena become invalid.
    pub fn deinit(self: *Arena) void {
        var current = self.blocks;
        while (current) |block| {
            const next = block.next;
            self.backing_allocator.free(block.data);
            self.backing_allocator.destroy(block);
            current = next;
        }
        self.blocks = null;
        self.current_block = null;
        self.current_offset = 0;
        self.stats.block_count = 0;
    }

    /// Allocate `byte_count` bytes aligned to `log_2_alignment`.
    ///
    /// Uses bump pointer allocation within the current block.
    /// Falls back to allocating a new block if current block is exhausted.
    ///
    /// For large allocations (> block_size), allocates a dedicated block
    /// to avoid wasting space in the general-purpose blocks.
    ///
    /// Arguments:
    ///   byte_count - Number of bytes to allocate
    ///   log_2_alignment - Required alignment as log2 value (Zig's format)
    ///
    /// Returns:
    ///   Pointer to allocated memory (caller must not free individually)
    ///
    /// Errors:
    ///   OutOfMemory if block allocation fails
    pub fn alloc(self: *Arena, byte_count: usize, log_2_alignment: u29) ![*]u8 {
        // Use maximum of requested alignment and minimum
        const effective_align = @max(log_2_alignment, @as(u29, 0));
        const alignment = @as(usize, 1) << @as(u6, @intCast(@max(effective_align, 0)));

        // Calculate aligned offset within current block (manual alignment)
        const aligned_offset = (self.current_offset + alignment - 1) & ~(alignment - 1);
        const end_offset = aligned_offset + byte_count;

        // Check if allocation fits in current block
        if (self.current_block) |block| {
            if (end_offset <= block.data.len) {
                const ptr = block.data[aligned_offset..].ptr;
                self.current_offset = end_offset;
                self.stats.allocation_count += 1;
                self.stats.bytes_used += byte_count;
                return ptr;
            }
        }

        // Need a new block - determine size
        const new_block_size = @max(byte_count, self.block_size);

        // Allocate new block using standard allocator (handles alignment internally)
        const block_data = try self.backing_allocator.alloc(u8, new_block_size);

        const new_block = try self.backing_allocator.create(Block);
        new_block.* = .{
            .data = block_data,
            .next = null,
            .alignment = @enumFromInt(effective_align),
        };

        // Link into list
        if (self.current_block) |curr| {
            curr.next = new_block;
        } else {
            // First block
            self.blocks = new_block;
        }
        self.current_block = new_block;
        self.current_offset = byte_count;

        // Update statistics
        self.stats.allocation_count += 1;
        self.stats.bytes_used += byte_count;
        self.stats.bytes_allocated += new_block_size;
        self.stats.block_count += 1;

        log.debug("[arena] allocated new block ({} bytes)", .{new_block_size});

        return block_data.ptr;
    }

    /// Free all allocations but keep the first block.
    ///
    /// Subsequent allocations will reuse the space in the first block.
    /// This is the key optimization: O(1) bulk deallocation.
    ///
    /// Use this between analysis phases to reclaim temporary memory
    /// without deallocating and reallocating blocks.
    pub fn reset(self: *Arena) void {
        // Free all blocks except the first one
        if (self.blocks) |first| {
            var current = first.next;
            while (current) |block| {
                const next = block.next;
                self.backing_allocator.free(block.data);
                self.backing_allocator.destroy(block);
                current = next;
            }
            first.next = null;
        }

        // Reset to first block (or null if no blocks exist)
        self.current_block = self.blocks;
        self.current_offset = 0;

        // Update statistics
        self.stats.reset_count += 1;
        self.stats.bytes_used = 0;
        self.stats.bytes_allocated = if (self.blocks) |b| b.data.len else 0;
        self.stats.block_count = if (self.blocks != null) @as(usize, 1) else @as(usize, 0);

        log.debug("[arena] reset complete", .{});
    }

    /// Get total bytes currently allocated across all blocks.
    ///
    /// Useful for monitoring memory usage and debugging.
    /// Includes both used and unused space in each block.
    ///
    /// Returns:
    ///   Total capacity of all blocks combined
    pub fn totalAllocated(self: *const Arena) usize {
        var total: usize = 0;
        var current = self.blocks;
        while (current) |block| {
            total += block.data.len;
            current = block.next;
        }
        return total;
    }

    /// Get number of bytes currently used (up to bump pointer).
    ///
    /// Does not include unused space in current or previous blocks.
    ///
    /// Returns:
    ///   Sum of used bytes across all blocks
    pub fn totalUsed(self: *const Arena) usize {
        var used: usize = 0;
        var current = self.blocks;
        while (current) |block| {
            if (block == self.current_block) {
                // Current block: count up to offset
                used += self.current_offset;
            } else {
                // Previous blocks: fully used
                used += block.data.len;
            }
            current = block.next;
        }
        return used;
    }

    /// Get current statistics for the arena.
    ///
    /// Returns a snapshot of the arena's usage statistics including
    /// allocation counts, bytes used, and memory utilization.
    pub fn getStats(self: *const Arena) ArenaStats {
        return self.stats;
    }

    /// Reset statistics counters.
    ///
    /// Useful when you want to track statistics for a specific phase
    /// without accumulating counts from previous phases.
    pub fn resetStats(self: *Arena) void {
        self.stats.allocation_count = 0;
        self.stats.reset_count = 0;
        self.stats.bytes_used = 0;
        self.stats.bytes_allocated = self.totalAllocated();
        self.stats.block_count = self.blockCount();
    }

    /// Get the number of memory blocks currently allocated.
    ///
    /// Returns:
    ///   Number of blocks in the arena's linked list
    pub fn blockCount(self: *const Arena) usize {
        var count: usize = 0;
        var current = self.blocks;
        while (current) |block| {
            count += 1;
            current = block.next;
        }
        return count;
    }
};

/// Memory block in the arena's linked list.
///
/// Each block contains a contiguous region of memory that is
/// allocated from the backing allocator and subdivided via bump pointer.
const Block = struct {
    /// The actual memory region.
    data: []u8,
    /// Next block in the linked list (null if last).
    next: ?*Block,
    /// Alignment used when allocating this block (needed for correct free).
    alignment: std.mem.Alignment,
};

/// Thread-local arena allocator for per-thread temporary allocations.
///
/// This implementation provides true thread-local storage using Zig's
/// `threadlocal var` feature. Each thread gets its own independent Arena
/// instance, eliminating contention and allowing parallel allocation.
///
/// Design:
/// - Uses module-level `threadlocal var` for per-thread Arena storage
/// - Lazily initializes thread-local Arena on first access
/// - Tracks all created arenas for cleanup in deinit()
/// - Thread-safe configuration and statistics aggregation
///
/// Use cases:
/// - Multi-threaded analysis passes where each thread needs its own arena
/// - Parallel pattern matching with temporary result collections
/// - Any scenario where thread-local allocation reduces contention
///
/// Example:
///
/// ```zig
/// var thread_arena = ThreadLocalArena.init(allocator);
/// defer thread_arena.deinit();
///
/// // Each thread gets its own arena automatically
/// const arena_alloc = try thread_arena.allocator();
/// var list = std.ArrayList(u32).init(arena_alloc);
/// try list.append(42);
/// // Thread-local arena is automatically freed when thread_arena is deinitialized
/// ```
pub const ThreadLocalArena = struct {
    /// Backing allocator for creating new arenas.
    backing_allocator: std.mem.Allocator,
    /// Default block size for new arenas.
    block_size: usize,
    /// Thread-safe list of all created arenas for cleanup.
    all_arenas: std.ArrayList(*Arena),
    /// Mutex for protecting all_arenas list.
    arenas_mutex: std.Thread.Mutex,
    /// Combined statistics across all threads.
    global_stats: ArenaStats,
    /// Mutex for protecting global_stats updates.
    stats_mutex: std.Thread.Mutex,

    /// Initialize a new thread-local arena.
    ///
    /// Each thread that calls allocator() will get its own Arena instance.
    /// The backing allocator is used to create new arenas when needed.
    ///
    /// Arguments:
    ///   backing_allocator - Allocator to use for creating arenas
    ///
    /// Returns:
    ///   Initialized ThreadLocalArena ready for use
    pub fn init(backing_allocator: std.mem.Allocator) ThreadLocalArena {
        return .{
            .backing_allocator = backing_allocator,
            .block_size = default_block_size,
            .all_arenas = std.ArrayList(*Arena).initCapacity(backing_allocator, 0) catch unreachable,
            .arenas_mutex = .{},
            .global_stats = ArenaStats{},
            .stats_mutex = .{},
        };
    }

    /// Initialize a new thread-local arena with custom block size.
    ///
    /// Arguments:
    ///   backing_allocator - Allocator to use for creating arenas
    ///   block_size - Size for new blocks (must be > 0)
    ///
    /// Returns:
    ///   Initialized ThreadLocalArena ready for use
    pub fn initWithBlockSize(backing_allocator: std.mem.Allocator, block_size: usize) ThreadLocalArena {
        return .{
            .backing_allocator = backing_allocator,
            .block_size = @max(block_size, 1024), // Minimum 1KB
            .all_arenas = std.ArrayList(*Arena).initCapacity(backing_allocator, 0) catch unreachable,
            .arenas_mutex = .{},
            .global_stats = ArenaStats{},
            .stats_mutex = .{},
        };
    }

    /// Deinitialize all thread-local arenas.
    ///
    /// This must be called from the main thread after all worker threads
    /// have finished. After calling this, the ThreadLocalArena must not be used.
    pub fn deinit(self: *ThreadLocalArena) void {
        self.arenas_mutex.lock();
        defer self.arenas_mutex.unlock();

        // Free all tracked arenas
        for (self.all_arenas.items) |arena| {
            arena.deinit();
            self.backing_allocator.destroy(arena);
        }
        self.all_arenas.deinit(self.backing_allocator);

        // Clear thread-local pointer for current thread
        // Note: This only clears for the calling thread. Other threads
        // should have finished before deinit() is called.
        thread_arena_ptr = null;
    }

    /// Get or create an arena for the current thread.
    ///
    /// Returns an Arena that is specific to the calling thread.
    /// If no arena exists for this thread, one is created and tracked.
    ///
    /// Returns:
    ///   Pointer to thread-local Arena
    pub fn getArena(self: *ThreadLocalArena) !*Arena {
        // Check if current thread already has an arena
        if (thread_arena_ptr) |arena| {
            return arena;
        }

        // Create new arena for this thread
        const arena = try self.backing_allocator.create(Arena);
        arena.* = Arena.initWithBlockSize(self.backing_allocator, self.block_size);

        // Store in thread-local storage
        thread_arena_ptr = arena;

        // Track for cleanup
        self.arenas_mutex.lock();
        defer self.arenas_mutex.unlock();
        try self.all_arenas.append(self.backing_allocator, arena);

        return arena;
    }

    /// Get an allocator interface for the current thread's arena.
    ///
    /// This is a convenience method that returns an std.mem.Allocator
    /// backed by the current thread's arena.
    ///
    /// Returns:
    ///   Allocator interface for thread-local arena
    pub fn allocator(self: *ThreadLocalArena) !std.mem.Allocator {
        const arena = try self.getArena();
        return arenaAllocator(arena);
    }

    /// Reset the current thread's arena.
    ///
    /// This is equivalent to calling reset() on the thread-local arena.
    pub fn resetCurrentThread(self: *ThreadLocalArena) void {
        _ = self;
        if (thread_arena_ptr) |arena| {
            arena.reset();
        }
    }

    /// Get combined statistics from all threads.
    ///
    /// Returns a snapshot of the global statistics including
    /// allocation counts and bytes used across all threads.
    pub fn getGlobalStats(self: *ThreadLocalArena) ArenaStats {
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();
        return self.global_stats;
    }

    /// Update global statistics from the current thread's arena.
    ///
    /// This should be called periodically to update the global statistics.
    /// In practice, this is often called during reset() or deinit().
    pub fn updateGlobalStats(self: *ThreadLocalArena) void {
        if (thread_arena_ptr) |arena| {
            const local_stats = arena.getStats();
            self.stats_mutex.lock();
            defer self.stats_mutex.unlock();
            self.global_stats.allocation_count += local_stats.allocation_count;
            self.global_stats.reset_count += local_stats.reset_count;
            self.global_stats.bytes_used += local_stats.bytes_used;
            self.global_stats.bytes_allocated += local_stats.bytes_allocated;
            self.global_stats.block_count += local_stats.block_count;
        }
    }

    /// Clean up the current thread's thread-local arena reference.
    ///
    /// Zig does not support C++-style thread-local destructors, so callers
    /// MUST invoke this method on every worker thread before that thread
    /// exits. Failing to do so leaves a dangling pointer in the
    /// `threadlocal var` that will never be reclaimed.
    ///
    /// After calling this the thread-local pointer is `null`, but the
    /// underlying `Arena` object remains alive (and tracked in `all_arenas`)
    /// until the owning `ThreadLocalArena` is itself deinitialized.
    ///
    /// Typical usage pattern for worker threads:
    ///
    /// ```zig
    /// fn worker(tla: *ThreadLocalArena) void {
    ///     const alloc = tla.allocator() catch return;
    ///     // ... do work ...
    ///     tla.cleanupCurrentThread();   // REQUIRED before thread exit
    /// }
    /// ```
    pub fn cleanupCurrentThread(self: *ThreadLocalArena) void {
        _ = self;
        thread_arena_ptr = null;
    }

    /// Execute `func` inside a scope that guarantees per-thread arena cleanup.
    ///
    /// Obtains (or lazily creates) the thread-local arena, calls `func` with
    /// the resulting `std.mem.Allocator`, and then clears the thread-local
    /// pointer regardless of whether `func` succeeded or returned an error.
    ///
    /// This is the recommended way to use `ThreadLocalArena` when the caller
    /// is a thread-entry function, because the cleanup happens automatically
    /// even in error paths.
    ///
    /// Parameters:
    ///   self   - The `ThreadLocalArena` instance
    ///   func   - A function that accepts `std.mem.Allocator` and returns `!T`
    ///
    /// Returns: The return value of `func`, or the first error it produced.
    ///
    /// Example:
    /// ```zig
    /// fn worker(tla: *ThreadLocalArena) !void {
    ///     try tla.withArena(struct {
    ///         fn run(alloc: std.mem.Allocator) !void {
    ///             var list = std.ArrayList(u8).init(alloc);
    ///             // ... work ...
    ///         }
    ///     }.run);
    ///     // thread-local is automatically cleaned up here
    /// }
    /// ```
    pub fn withArena(self: *ThreadLocalArena, func: *const fn (std.mem.Allocator) anyerror!void) !void {
        const alloc = try self.allocator();
        func(alloc) catch |err| {
            self.cleanupCurrentThread();
            return err;
        };
        self.cleanupCurrentThread();
    }
};

/// Thread-local storage for Arena pointers.
///
/// Each thread gets its own Arena instance stored in this variable.
/// Initialized lazily on first access via ThreadLocalArena.getArena().
threadlocal var thread_arena_ptr: ?*Arena = null;

/// Create an std.mem.Allocator wrapper around an Arena.
///
/// This allows the Arena to be used anywhere a generic allocator is expected,
/// such as with ArrayList, HashMap, or other Zig standard library containers.
///
/// Arguments:
///   arena - Pointer to the Arena to wrap
///
/// Returns:
///   Allocator interface that delegates to the Arena
///
/// Example:
///
/// ```zig
/// var arena = Arena.init(allocator);
/// defer arena.deinit();
///
/// const arena_alloc = arenaAllocator(&arena);
/// var list = std.ArrayList(u32).init(arena_alloc);
/// try list.append(42);
/// // list's memory is managed by the arena
/// ```
pub fn arenaAllocator(arena: *Arena) std.mem.Allocator {
    return .{
        .ptr = arena,
        .vtable = &.{
            .alloc = allocFn,
            .resize = resizeFn,
            .free = freeFn,
            .remap = remapFn,
        },
    };
}

/// Allocation function for the allocator vtable.
fn allocFn(ctx: *anyopaque, n: usize, alignment: std.mem.Alignment, return_address: usize) ?[*]u8 {
    _ = return_address;
    const arena: *Arena = @ptrCast(@alignCast(ctx));
    return arena.alloc(n, @intFromEnum(alignment)) catch return null;
}

/// Resize function for the allocator vtable.
///
/// Arena allocator cannot resize in place (no individual free),
/// so this always returns false to indicate failure.
fn resizeFn(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) bool {
    _ = ctx;
    _ = buf;
    _ = alignment;
    _ = new_len;
    _ = return_address;
    // Arena does not support resizing - allocations are fixed size
    return false;
}

/// Free function for the allocator vtable.
///
/// Arena allocator ignores individual frees - all memory is freed
/// at once during reset() or deinit(). This is by design.
fn freeFn(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, return_address: usize) void {
    _ = ctx;
    _ = buf;
    _ = alignment;
    _ = return_address;
    // Intentional no-op: arena frees all memory at once
}

/// Remap function for the allocator vtable.
/// For arena allocators, remap is not supported (returns null).
fn remapFn(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
    _ = ctx;
    _ = buf;
    _ = alignment;
    _ = new_len;
    _ = return_address;
    // Arena allocators don't support remap
    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "Arena - basic allocation" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    const ptr = try arena.alloc(64, 0); // 1-byte alignment
    // Verify we can write to the allocated memory
    @memset(ptr[0..64], 0xAA);
    try testing.expectEqual(@as(u8, 0xAA), ptr[0]);
    try testing.expectEqual(@as(u8, 0xAA), ptr[63]);
}

test "Arena - multiple allocations" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    // Allocate multiple times
    const ptr1 = try arena.alloc(128, 0);
    const ptr2 = try arena.alloc(256, 0);
    const ptr3 = try arena.alloc(512, 0);

    // All should be valid and distinct
    try testing.expect(ptr1 != ptr2);
    try testing.expect(ptr2 != ptr3);
    try testing.expect(ptr1 != ptr3);

    // Write to each without interference
    @memset(ptr1[0..128], 0x11);
    @memset(ptr2[0..256], 0x22);
    @memset(ptr3[0..512], 0x33);

    try testing.expectEqual(@as(u8, 0x11), ptr1[0]);
    try testing.expectEqual(@as(u8, 0x22), ptr2[0]);
    try testing.expectEqual(@as(u8, 0x33), ptr3[0]);
}

test "Arena - alignment support" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    // Test various alignments (log2 values)
    const align_2 = try arena.alloc(16, 1); // 2-byte alignment
    const align_4 = try arena.alloc(16, 2); // 4-byte alignment
    const align_8 = try arena.alloc(16, 3); // 8-byte alignment
    const align_16 = try arena.alloc(16, 4); // 16-byte alignment

    // Verify alignment
    try testing.expectEqual(@as(usize, 0), @intFromPtr(align_2) % 2);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(align_4) % 4);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(align_8) % 8);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(align_16) % 16);
}

test "Arena - reset and reuse" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    // First round of allocations
    const ptr1 = try arena.alloc(1024, 0);
    @memset(ptr1[0..1024], 0xFF);
    try testing.expectEqual(@as(u8, 0xFF), ptr1[0]);

    // Reset should free all allocations
    arena.reset();

    // Second round - should reuse the same block
    const ptr2 = try arena.alloc(512, 0);
    @memset(ptr2[0..512], 0xBB);
    try testing.expectEqual(@as(u8, 0xBB), ptr2[0]);

    // Verify total allocated hasn't grown significantly (still using first block)
    const total = arena.totalAllocated();
    try testing.expect(total >= 512);
}

test "Arena - large allocation spans block boundary" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    // Default block size is 8KB, request larger allocation
    const large_ptr = try arena.alloc(16 * 1024, 0); // 16KB > default 8KB block

    // Should be able to write to it
    @memset(large_ptr[0 .. 16 * 1024], 0xCC);
    try testing.expectEqual(@as(u8, 0xCC), large_ptr[0]);
    try testing.expectEqual(@as(u8, 0xCC), large_ptr[16 * 1024 - 1]);

    // Total allocated should be at least 16KB
    try testing.expect(arena.totalAllocated() >= 16 * 1024);
}

test "Arena - totalUsed tracking" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqual(@as(usize, 0), arena.totalUsed());

    _ = try arena.alloc(100, 0);
    try testing.expectEqual(@as(usize, 100), arena.totalUsed());

    _ = try arena.alloc(200, 0);
    try testing.expectEqual(@as(usize, 300), arena.totalUsed());
}

test "Arena - statistics tracking" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    // Initial stats
    var stats = arena.getStats();
    try testing.expectEqual(@as(usize, 0), stats.allocation_count);
    try testing.expectEqual(@as(usize, 0), stats.bytes_used);

    // First allocation
    _ = try arena.alloc(100, 0);
    stats = arena.getStats();
    try testing.expectEqual(@as(usize, 1), stats.allocation_count);
    try testing.expectEqual(@as(usize, 100), stats.bytes_used);

    // Second allocation
    _ = try arena.alloc(200, 0);
    stats = arena.getStats();
    try testing.expectEqual(@as(usize, 2), stats.allocation_count);
    try testing.expectEqual(@as(usize, 300), stats.bytes_used);

    // Reset should increment reset_count
    arena.reset();
    stats = arena.getStats();
    try testing.expectEqual(@as(usize, 1), stats.reset_count);
    try testing.expectEqual(@as(usize, 0), stats.bytes_used);
}

test "Arena - statistics utilization" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    // Allocate a small amount
    _ = try arena.alloc(100, 0);
    const stats = arena.getStats();

    // Utilization should be reasonable (not 0)
    const util = stats.utilization();
    try testing.expect(util > 0.0);
    try testing.expect(util <= 1.0);
}

test "Arena - statistics average allocation size" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    _ = try arena.alloc(100, 0);
    _ = try arena.alloc(200, 0);
    _ = try arena.alloc(300, 0);

    const stats = arena.getStats();
    const avg = stats.averageAllocationSize();
    // Average should be (100 + 200 + 300) / 3 = 200
    try testing.expectApproxEqAbs(@as(f64, 200.0), avg, 0.1);
}

test "Arena - initWithBlockSize" {
    const testing = std.testing;

    var arena = Arena.initWithBlockSize(testing.allocator, 4096);
    defer arena.deinit();

    // Should work like normal arena
    const ptr = try arena.alloc(64, 0);
    @memset(ptr[0..64], 0xAA);
    try testing.expectEqual(@as(u8, 0xAA), ptr[0]);

    // Block size should be set
    const stats = arena.getStats();
    try testing.expectEqual(@as(usize, 4096), stats.block_size);
}

test "Arena - resetStats" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    _ = try arena.alloc(100, 0);
    _ = try arena.alloc(200, 0);

    // Reset stats should clear counters
    arena.resetStats();
    const stats = arena.getStats();
    try testing.expectEqual(@as(usize, 0), stats.allocation_count);
    try testing.expectEqual(@as(usize, 0), stats.bytes_used);
}

test "Arena - blockCount" {
    const testing = std.testing;

    var arena = Arena.init(testing.allocator);
    defer arena.deinit();

    // Initially no blocks
    try testing.expectEqual(@as(usize, 0), arena.blockCount());

    // First allocation creates a block
    _ = try arena.alloc(100, 0);
    try testing.expectEqual(@as(usize, 1), arena.blockCount());

    // Large allocation creates another block
    _ = try arena.alloc(16 * 1024, 0); // 16KB > default 8KB block
    try testing.expectEqual(@as(usize, 2), arena.blockCount());
}

test "ArenaStats - empty stats" {
    const testing = std.testing;

    const stats = ArenaStats{};
    try testing.expectEqual(@as(f64, 0.0), stats.utilization());
    try testing.expectEqual(@as(f64, 0.0), stats.averageAllocationSize());
}

test "ThreadLocalArena - basic usage" {
    const testing = std.testing;

    var thread_arena = ThreadLocalArena.init(testing.allocator);
    defer thread_arena.deinit();

    // Get allocator for current thread
    const alloc = try thread_arena.allocator();

    // Use with ArrayList
    var list = std.array_list.Managed(u32).init(alloc);
    defer list.deinit();

    try list.append(42);
    try list.append(100);
    try testing.expectEqual(@as(u32, 42), list.items[0]);
    try testing.expectEqual(@as(u32, 100), list.items[1]);
}

test "ThreadLocalArena - resetCurrentThread" {
    const testing = std.testing;

    var thread_arena = ThreadLocalArena.init(testing.allocator);
    defer thread_arena.deinit();

    // Get arena for current thread
    const arena = try thread_arena.getArena();
    _ = try arena.alloc(100, 0);

    // Reset should clear allocations
    thread_arena.resetCurrentThread();
    const stats = arena.getStats();
    try testing.expectEqual(@as(usize, 0), stats.bytes_used);
}

test "ThreadLocalArena - statistics" {
    const testing = std.testing;

    var thread_arena = ThreadLocalArena.init(testing.allocator);
    defer thread_arena.deinit();

    // Get arena for current thread
    const arena = try thread_arena.getArena();
    _ = try arena.alloc(100, 0);
    _ = try arena.alloc(200, 0);

    // Update global stats
    thread_arena.updateGlobalStats();
    const global_stats = thread_arena.getGlobalStats();
    try testing.expectEqual(@as(usize, 2), global_stats.allocation_count);
    try testing.expectEqual(@as(usize, 300), global_stats.bytes_used);
}

test "ThreadLocalArena - initWithBlockSize" {
    const testing = std.testing;

    var thread_arena = ThreadLocalArena.initWithBlockSize(testing.allocator, 4096);
    defer thread_arena.deinit();

    // Get arena for current thread
    const arena = try thread_arena.getArena();

    // Block size should be set
    const stats = arena.getStats();
    try testing.expectEqual(@as(usize, 4096), stats.block_size);
}

test "Arena - concurrent usage simulation" {
    const testing = std.testing;

    // Simulate multiple threads using their own arenas
    var arena1 = Arena.init(testing.allocator);
    defer arena1.deinit();

    var arena2 = Arena.init(testing.allocator);
    defer arena2.deinit();

    // Both arenas should work independently
    const ptr1 = try arena1.alloc(100, 0);
    const ptr2 = try arena2.alloc(100, 0);

    // Should not interfere with each other
    @memset(ptr1[0..100], 0x11);
    @memset(ptr2[0..100], 0x22);

    try testing.expectEqual(@as(u8, 0x11), ptr1[0]);
    try testing.expectEqual(@as(u8, 0x22), ptr2[0]);

    // Stats should be independent
    const stats1 = arena1.getStats();
    const stats2 = arena2.getStats();
    try testing.expectEqual(@as(usize, 1), stats1.allocation_count);
    try testing.expectEqual(@as(usize, 1), stats2.allocation_count);
}

test "ThreadLocalArena - cleanupCurrentThread" {
    const testing = std.testing;

    var thread_arena = ThreadLocalArena.init(testing.allocator);
    defer thread_arena.deinit();

    // Allocate through the thread-local arena
    const alloc1 = try thread_arena.allocator();
    var list = std.array_list.Managed(u8).init(alloc1);
    try list.append(0xAA);
    try testing.expectEqual(@as(u8, 0xAA), list.items[0]);

    // cleanupCurrentThread clears the thread-local pointer
    thread_arena.cleanupCurrentThread();

    // A subsequent allocator() call should create a fresh arena
    // (the old Arena object is still tracked in all_arenas and will
    // be freed by deinit, but the thread-local pointer is now null).
    const alloc2 = try thread_arena.allocator();
    var list2 = std.array_list.Managed(u8).init(alloc2);
    try list2.append(0xBB);
    try testing.expectEqual(@as(u8, 0xBB), list2.items[0]);
}

test "ThreadLocalArena - withArena success" {
    const testing = std.testing;

    var thread_arena = ThreadLocalArena.init(testing.allocator);
    defer thread_arena.deinit();

    try thread_arena.withArena(testSuccessFn);

    // thread-local pointer should have been cleaned up;
    // a fresh call to getArena should succeed without error.
    _ = try thread_arena.getArena();
}

test "ThreadLocalArena - withArena cleanup on error" {
    const testing = std.testing;

    var thread_arena = ThreadLocalArena.init(testing.allocator);
    defer thread_arena.deinit();

    // First, prime the thread-local arena so the function runs inside it
    _ = try thread_arena.getArena();

    // The function returns an error; cleanup should still happen.
    const result = thread_arena.withArena(testErrorFn);

    try testing.expectError(error.DeliberateTestError, result);

    // Verify cleanup happened: getArena should lazily create a new arena
    // (the thread-local ptr was null after cleanup).
    const arena = try thread_arena.getArena();
    _ = try arena.alloc(8, 0);
}

/// Helper: allocation succeeds and uses the arena.
fn testSuccessFn(alloc: std.mem.Allocator) !void {
    var list = std.array_list.Managed(u32).init(alloc);
    try list.append(123);
    if (list.items[0] != 123) return error.Unexpected;
}

/// Helper: deliberately returns an error.
fn testErrorFn(_: std.mem.Allocator) !void {
    return error.DeliberateTestError;
}
