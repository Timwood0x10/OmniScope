# Lock Analysis Pass

## Overview

Detects potential deadlocks by building a lock acquisition graph and finding cycles.

## Location

```text
src/pass/analysis/lock.zig
```

## LockPass

```zig
pub const LockPass = struct {
    pub const name = "lock";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg", "alias" };

    ctx: *PassContext,
    diag: *DiagnosticWriter,
    store: *FactStore,
    query: QueryEngine,
    lock_ops: std.ArrayList(LockOperation),
    lock_id_map: std.AutoHashMap(c.LLVMValueRef, u32),
    func_id: u32,
    next_lock_id: u32,
};
```

### Methods

- **init()** - Initialize pass
- **deinit()** - Clean up
- **run(func_id)** - Run analysis

## LockOperation

```zig
pub const LockOperation = struct {
    lock_id: u32,
    op_type: LockOpType,
    inst_id: u32,
    bb_id: u32,
};
```

### LockOpType

- `acquire` - Lock acquire
- `release` - Lock release

## LockGraph

Models lock dependencies and detects cycles.

```zig
pub const LockGraph = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(u32),
    edges: std.ArrayList(LockEdge),
    adjacency: std.AutoHashMap(u32, []const u32),
};
```

### Methods

- **init()** - Initialize graph
- **deinit()** - Clean up
- **addNode(lock_id)** - Add lock node
- **addEdge(from, to)** - Add acquisition order edge
- **hasCycle()** - Detect cycles (deadlocks)
- **hasCycleDFS()** - DFS-based cycle detection

## Lock Functions

### Mutex

- `pthread_mutex_lock`
- `pthread_mutex_unlock`
- `pthread_mutex_trylock`

### RWLock

- `pthread_rwlock_rdlock`
- `pthread_rwlock_wrlock`
- `pthread_rwlock_unlock`

### Spinlock

- `pthread_spin_lock`
- `pthread_spin_unlock`

## Helper Functions

- **isLockOperation(name)** - Check if lock operation
- **isLockAcquire(name)** - Check if acquire
- **isLockRelease(name)** - Check if release
- **getLockId(lock_value)** - Assign unique lock ID

## Algorithm

1. Collect lock operations from function
2. Assign unique IDs to lock objects
3. Build lock acquisition order graph
4. Detect cycles using DFS

## Usage

```zig
var lock_pass = LockPass.init(ctx, diag, store, query);
defer lock_pass.deinit();

const result = try lock_pass.run(func_id);
for (result.deadlocks) |deadlock| {
    std.debug.print("Potential deadlock\n");
}
```

## Detection

- AB-BA deadlocks
- Multi-lock cycles
- Nested lock deadlocks
