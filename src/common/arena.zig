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
pub const default_block_size: usize = 8 * 1024;

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
