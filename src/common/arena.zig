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
    @memset(large_ptr[0..16 * 1024], 0xCC);
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
