# Tracking 模块

## 概述

Tracking 模块提供内存跟踪功能，用于性能测量和泄漏检测。该模块通过包装标准分配器来记录内存分配和释放的统计信息。

## 模块结构

```text
src/tracking/
├── allocator.zig  # 内存跟踪分配器实现
└── mod.zig        # 模块入口
```

## MemoryStats

内存统计结构，用于跟踪内存使用情况。

### MemoryStats 源代码

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

### MemoryStats 字段说明

- **alloc_bytes**: `usize` - 总分配字节数
- **alloc_count**: `usize` - 分配操作次数
- **free_count**: `usize` - 释放操作次数

### MemoryStats 方法

#### reset()

重置所有统计信息为零。

```zig
stats.reset();
```

#### netAllocated()

获取净分配字节数。

**返回值:** `usize` - 当前分配的字节数

```zig
const bytes = stats.netAllocated();
```

#### isLeakFree()

检查分配计数是否匹配释放计数，用于检测内存泄漏。

**返回值:** `bool` - 如果没有泄漏返回 `true`

```zig
if (!stats.isLeakFree()) {
    // 检测到内存泄漏
}
```

## TrackedAllocator

内存跟踪分配器，包装标准分配器以记录统计信息。

### TrackedAllocator 源代码

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

### TrackedAllocator 字段说明

- **child_allocator**: `std.mem.Allocator` - 底层分配器
- **stats**: `*MemoryStats` - 指向内存统计结构的指针

### TrackedAllocator 方法

#### init()

初始化跟踪分配器。

**参数:**

- `child_allocator`: 要包装的底层分配器
- `stats`: 用于跟踪的 MemoryStats 结构指针

**返回值:** 初始化的 TrackedAllocator

```zig
var stats = MemoryStats{};
var tracked_allocator = TrackedAllocator.init(std.heap.page_allocator, &stats);
```

#### allocator()

获取标准库分配器接口。

**返回值:** 可与标准库一起使用的分配器接口

```zig
const allocator = tracked_allocator.allocator();
var list = std.ArrayList(u8).init(allocator);
```

## 使用示例

### 基本使用示例

```zig
const std = @import("std");
const tracking = @import("tracking");

pub fn main() !void {
    var stats = tracking.MemoryStats{};
    var tracked_allocator = tracking.TrackedAllocator.init(std.heap.page_allocator, &stats);
    const allocator = tracked_allocator.allocator();

    // 使用跟踪分配器
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    try list.append('H');
    try list.append('e');
    try list.append('l');
    try list.append('l');
    try list.append('o');

    // 查看统计信息
    std.debug.print("Allocated bytes: {}\n", .{stats.netAllocated()});
    std.debug.print("Allocation count: {}\n", .{stats.alloc_count});
    std.debug.print("Free count: {}\n", .{stats.free_count});
    std.debug.print("Leak free: {}\n", .{stats.isLeakFree()});
}
```

### 泄漏检测示例

```zig
const std = @import("std");
const tracking = @import("tracking");

pub fn testLeakDetection() !void {
    var stats = tracking.MemoryStats{};
    var tracked_allocator = tracking.TrackedAllocator.init(std.testing.allocator, &stats);
    const allocator = tracked_allocator.allocator();

    // 分配内存但不释放（模拟泄漏）
    const leaked = try allocator.alloc(u8, 100);
    _ = leaked;

    // 检查泄漏
    if (!stats.isLeakFree()) {
        std.debug.print("Memory leak detected!\n", .{});
        std.debug.print("Allocations: {}, Frees: {}\n", .{stats.alloc_count, stats.free_count});
    }
}
```

### 与 AutoHashMap 集成示例

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

## 注意事项

1. **统计信息累积**: `alloc_bytes` 字段只增不减，用于跟踪总分配量。如需跟踪当前分配量，需要额外维护。

2. **线程安全**: `MemoryStats` 本身不是线程安全的。在多线程环境中使用时，需要添加同步机制。

3. **性能开销**: 跟踪分配会带来轻微的性能开销，主要用于开发和测试阶段。

4. **内存泄漏检测**: `isLeakFree()` 只检查分配和释放次数是否匹配，不能检测所有类型的泄漏（如循环引用）。
