//! Thread-local arena allocator for per-thread temporary allocations.
//!
//! This implementation provides true thread-local storage using Zig's
//! `threadlocal var` feature. Each thread gets its own independent Arena
//! instance, eliminating contention and allowing parallel allocation.
//!
//! Separated from arena.zig to keep core Arena implementation and
//! thread-local concerns clean.
//!
//! Design:
//! - Uses module-level `threadlocal var` for per-thread Arena storage
//! - Lazily initializes thread-local Arena on first access
//! - Tracks all created arenas for cleanup in deinit()
//! - Thread-safe configuration and statistics aggregation
//!
//! Use cases:
//! - Multi-threaded analysis passes where each thread needs its own arena
//! - Parallel pattern matching with temporary result collections
//! - Any scenario where thread-local allocation reduces contention
//!
//! Example:
//!
//! ```zig
//! var thread_arena = ThreadLocalArena.init(allocator);
//! defer thread_arena.deinit();
//!
//! // Each thread gets its own arena automatically
//! const arena_alloc = try thread_arena.allocator();
//! var list = std.ArrayList(u32).init(arena_alloc);
//! try list.append(42);
//! // Thread-local arena is automatically freed when thread_arena is deinitialized
//! ```

const std = @import("std");
const arena_mod = @import("arena.zig");
const Arena = arena_mod.Arena;
const ArenaStats = arena_mod.ArenaStats;
const arenaAllocator = arena_mod.arenaAllocator;
const default_block_size = arena_mod.default_block_size;

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
