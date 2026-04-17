# Tracking Module

## Overview

The Tracking module provides memory tracking functionality for performance measurement and leak detection. This module wraps standard allocators to record statistics about memory allocations and frees.

## Module Structure

```text
src/tracking/
├── allocator.zig  # Memory tracking allocator implementation
└── mod.zig        # Module entry point
```

## MemoryStats

Memory statistics structure for tracking memory usage.

### MemoryStats Source Code

```zig
/// Memory statistics tracked by the allocator
pub const MemoryStats = struct {
    /// Total bytes allocated
    alloc_bytes: usize = 0,
    /// Number of allocation operations
    alloc_count: usize = 0,
    /// Number of free operations
    free_count: usize = 0,

    /// Reset all statistics to zero
    pub fn reset(self: *MemoryStats) void {
        self.* = .{};
    }

    /// Get the net allocated bytes
    pub fn netAllocated(self: *const MemoryStats) usize {
        return self.alloc_bytes;
    }

    /// Check if allocation count matches free count
    pub fn isLeakFree(self: *const MemoryStats) bool {
        return self.alloc_count == self.free_count;
    }
};
```

### MemoryStats Fields

- **alloc_bytes**: `usize` - Total bytes allocated
- **alloc_count**: `usize` - Number of allocation operations
- **free_count**: `usize` - Number of free operations

### MemoryStats Methods

#### reset()

Resets all statistics to zero.

```zig
stats.reset();
```

#### netAllocated()

Gets the net allocated bytes.

**Returns:** `usize` - Currently allocated bytes

```zig
const bytes = stats.netAllocated();
```

#### isLeakFree()

Checks if allocation count matches free count for leak detection.

**Returns:** `bool` - `true` if there are no leaks

```zig
if (!stats.isLeakFree()) {
    // Memory leak detected
}
```

## TrackedAllocator

Memory tracking allocator that wraps a standard allocator to record statistics.

### TrackedAllocator Source Code

```zig
pub const TrackedAllocator = struct {
    child_allocator: std.mem.Allocator,
    stats: *MemoryStats,

    const Self = @This();

    /// Initialize the tracked allocator
    ///
    /// Parameters:
    ///   - child_allocator: The underlying allocator to wrap
    ///   - stats: Pointer to MemoryStats struct for tracking
    ///
    /// Returns:
    ///   - Initialized TrackedAllocator
    pub fn init(child_allocator: std.mem.Allocator, stats: *MemoryStats) Self {
        return .{
            .child_allocator = child_allocator,
            .stats = stats,
        };
    }

    /// Get the std.mem.Allocator interface
    ///
    /// Returns:
    ///   - Allocator interface that can be used with standard library
    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
                .remap = remap,
            },
        };
    }

    fn alloc(
        self: *Self,
        len: usize,
        ptr_align: u29,
        ret_addr: usize,
    ) ?[*]u8 {
        const result = self.child_allocator.vtable.alloc(self.child_allocator.ptr, len, ptr_align, ret_addr);
        if (result) |ptr| {
            self.stats.alloc_bytes += len;
            self.stats.alloc_count += 1;
        }
        return result;
    }

    fn resize(
        self: *Self,
        buf: []u8,
        buf_align: u29,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        const old_len = buf.len;
        const result = self.child_allocator.vtable.resize(self.child_allocator.ptr, buf, buf_align, new_len, ret_addr);
        if (result) {
            self.stats.alloc_bytes += @as(isize, @intCast(new_len)) - @as(isize, @intCast(old_len));
        }
        return result;
    }

    fn free(
        self: *Self,
        buf: []u8,
        buf_align: u29,
        ret_addr: usize,
    ) void {
        self.stats.free_count += 1;
        // Note: alloc_bytes is not decreased to track total allocated
        self.child_allocator.vtable.free(self.child_allocator.ptr, buf, buf_align, ret_addr);
    }

    fn remap(
        self: *Self,
        old_mem: []u8,
        old_align: u29,
        new_len: usize,
        ret_addr: usize,
    ) ?[*]u8 {
        const old_len = old_mem.len;
        const result = self.child_allocator.vtable.remap(self.child_allocator.ptr, old_mem, old_align, new_len, ret_addr);
        if (result) |ptr| {
            self.stats.alloc_bytes += @as(isize, @intCast(new_len)) - @as(isize, @intCast(old_len));
        }
        return result;
    }
};
```

### TrackedAllocator Fields

- **child_allocator**: `std.mem.Allocator` - Underlying allocator
- **stats**: `*MemoryStats` - Pointer to memory statistics structure

### TrackedAllocator Methods

#### init()

Initializes the tracked allocator.

**Parameters:**

- `child_allocator`: The underlying allocator to wrap
- `stats`: MemoryStats struct pointer for tracking

**Returns:** Initialized TrackedAllocator

```zig
var stats = MemoryStats{};
var tracked_allocator = TrackedAllocator.init(std.heap.page_allocator, &stats);
```

#### allocator()

Gets the standard library allocator interface.

**Returns:** Allocator interface that can be used with standard library

```zig
const allocator = tracked_allocator.allocator();
var list = std.ArrayList(u8).init(allocator);
```

## Usage Examples

### Basic Usage Example

```zig
const std = @import("std");
const tracking = @import("tracking");

pub fn main() !void {
    var stats = tracking.MemoryStats{};
    var tracked_allocator = tracking.TrackedAllocator.init(std.heap.page_allocator, &stats);
    const allocator = tracked_allocator.allocator();

    // Use the tracked allocator
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    try list.append('H');
    try list.append('e');
    try list.append('l');
    try list.append('l');
    try list.append('o');

    // View statistics
    std.debug.print("Allocated bytes: {}\n", .{stats.netAllocated()});
    std.debug.print("Allocation count: {}\n", .{stats.alloc_count});
    std.debug.print("Free count: {}\n", .{stats.free_count});
    std.debug.print("Leak free: {}\n", .{stats.isLeakFree()});
}
```

### Leak Detection Example

```zig
const std = @import("std");
const tracking = @import("tracking");

pub fn testLeakDetection() !void {
    var stats = tracking.MemoryStats{};
    var tracked_allocator = tracking.TrackedAllocator.init(std.testing.allocator, &stats);
    const allocator = tracked_allocator.allocator();

    // Allocate memory without freeing (simulating a leak)
    const leaked = try allocator.alloc(u8, 100);
    _ = leaked;

    // Check for leaks
    if (!stats.isLeakFree()) {
        std.debug.print("Memory leak detected!\n", .{});
        std.debug.print("Allocations: {}, Frees: {}\n", .{stats.alloc_count, stats.free_count});
    }
}
```

### Integration with AutoHashMap Example

```zig
const std = @import("std");
const tracking = @import("tracking");

pub fn testHashMapTracking() !void {
    var stats = tracking.MemoryStats{};
    var tracked_allocator = tracking.TrackedAllocator.init(std.testing.allocator, &stats);
    const allocator = tracked_allocator.allocator();

    var map = std.AutoHashMap(u32, []const u8).init(allocator);
    defer map.deinit();

    try map.put(1, "one");
    try map.put(2, "two");
    try map.put(3, "three");

    std.debug.print("HashMap allocated bytes: {}\n", .{stats.netAllocated()});
}
```

## Notes

1. **Accumulating Statistics**: The `alloc_bytes` field only increases, never decreases. It tracks total allocated bytes. To track currently allocated bytes, you need to maintain additional state.

2. **Thread Safety**: `MemoryStats` itself is not thread-safe. When using in multi-threaded environments, you need to add synchronization mechanisms.

3. **Performance Overhead**: Tracking allocations incurs a slight performance overhead, mainly intended for development and testing phases.

4. **Memory Leak Detection**: `isLeakFree()` only checks if allocation count matches free count. It cannot detect all types of leaks (e.g., circular references).
