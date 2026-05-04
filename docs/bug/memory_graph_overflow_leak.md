# MemoryGraph Integer Overflow + Memory Leak (sqlite3 corpus)

- **Date**: 2026-04-29
- **Severity**: P0 (runtime crash + memory leak on large inputs)
- **Affected Module**: `src/semantics/memory_graph.zig`
- **Trigger**: Large LLVM IR files (e.g., sqlite3.ll ~43M)
- **Status**: Fixed

## Bug 1: Integer Overflow Panic

### Symptom

```
thread 87512411 panic: integer overflow
memory_graph.zig:238:21: hashValues
    hash = hash * 0x100000001b3;
```

### Root Cause

`hashValues()` uses FNV-1a multiplication `hash * 0x100000001b3`. In Zig safe mode (default), `*` on integers traps on overflow. FNV-1a is designed for wrapping multiplication (RFC 7049), but Zig's `*` operator does checked multiplication.

### Fix

```zig
// Before (panic on overflow):
hash = hash * 0x100000001b3;

// After (wrapping multiply, compiles to single imul):
hash = hash *% 0x100000001b3;
```

`*%` is Zig's wrapping multiplication operator. It compiles to a single `imul` instruction with zero overhead — identical to C's `uint64_t` multiplication.

### Lesson

When porting hash algorithms from C, always use `*%` (wrapping) instead of `*` (checked). This applies to all non-cryptographic hashes (FNV, Murmur, xxHash, etc.) where overflow is expected behavior.

---

## Bug 2: Memory Leak via ArenaAllocator

### Symptom

```
error(gpa): memory address 0x329b19000 leaked:
  arena_allocator.zig:213:43 in alloc
  hash_map.zig:1478:53 in allocate
  hash_map.zig:1435:29 in grow
```

Dozens of leaked addresses, all originating from `hash_map.zig grow` → `arena_allocator.zig alloc`.

### Root Cause

Two issues:

1. **ArenaAllocator + HashMap grow**: `AllocNode.aliases` is an `AutoHashMap` initialized on the arena. When the HashMap grows, it allocates new backing memory via the arena. On `arena.deinit()`, these sub-allocations are supposed to be freed as part of the arena page. However, Zig 0.15's `GeneralPurposeAllocator` tracks individual allocations and the arena's internal page management can leave sub-page allocations unaccounted for, triggering leak reports.

2. **`edges` realloc from comptime slice**: `trackAlias()` used `arena.allocator().realloc(graph.edges, ...)` where `edges` was initialized as `&.{}` (a comptime-time empty slice). Calling `realloc` on a comptime slice is undefined behavior — the allocator cannot free or resize memory that was never dynamically allocated. Each `trackAlias` call leaked the old slice and allocated a new one.

### Fix

Removed `ArenaAllocator` entirely. Replaced with direct allocator + manual cleanup:

```zig
// Before (leaky):
arena: std.heap.ArenaAllocator,
edges: []PointerEdge,

pub fn deinit(graph: *MemoryGraph) void {
    graph.arena.deinit();  // HashMap sub-allocations not properly tracked
}

// After (clean):
node_store: std.ArrayList(*AllocNode),

pub fn deinit(graph: *MemoryGraph) void {
    for (graph.node_store.items) |node| {
        node.aliases.deinit();
        graph.allocator.destroy(node);
    }
    graph.node_store.deinit(graph.allocator);
    graph.nodes.deinit();
}
```

Also removed the `edges` array entirely — alias relationships are already fully expressed by the `nodes` HashMap (each alias key maps to the same `AllocNode`).

### Lesson

1. **Avoid ArenaAllocator when HashMap grow is involved** — the arena's page-level tracking conflicts with GPA's allocation-level tracking. Use direct `allocator.create/destroy` for precise lifetime management.

2. **Never `realloc` from a comptime slice** — `&.{}` is not a valid heap allocation. Use `ArrayList` instead.

3. **Per-function short-lived objects don't benefit from Arena** — MemoryGraph lives for one function analysis then dies. The arena's batch-free advantage is negligible; the leak-tracking complexity is not worth it.

---

## Regression Test

Added `memory_graph - no memory leaks` test that:
- Creates 100 allocation nodes with cross-aliases
- Frees half of them
- Verifies GPA reports zero leaks on deinit

```zig
test "memory_graph - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked != .ok) @panic("memory leak detected");
    }
    // ... 100 allocs + aliases + 50 frees ...
}
```
