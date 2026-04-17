# Lock Analysis Pass (锁分析)

## 概述

Lock Analysis Pass 实现锁分析功能，用于检测潜在的死锁场景。该 Pass 识别函数中的锁获取和释放操作，使用 LockGraph 对锁依赖关系进行建模，并使用基于 DFS 的循环检测算法来发现死锁。

## 模块位置

```text
src/pass/analysis/lock.zig
```

## LockPass

锁分析 Pass 结构，负责执行锁分析。

### LockPass 结构定义

```zig
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
};
```

### LockPass 字段说明

- **name**: `const` - Pass 名称 "lock"
- **kind**: `PassKind` - Pass 类型（分析）
- **deps**: `[]const u8` - 依赖的 Pass（cfg, dfg, alias）
- **ctx**: `*PassContext` - Pass 上下文
- **diag**: `*DiagnosticWriter` - 诊断写入器
- **store**: `*FactStore` - 事实存储
- **query**: `QueryEngine` - 查询引擎
- **lock_ops**: `std.ArrayList(LockOperation)` - 锁操作映射
- **lock_id_map**: `std.AutoHashMap(c.LLVMValueRef, u32)` - 锁 ID 映射
- **func_id**: `u32` - 函数 ID
- **next_lock_id**: `u32` - 下一个锁 ID

### LockPass 方法

#### init()

初始化锁分析 Pass。

**参数:**

- `ctx`: Pass 上下文
- `diag`: 诊断写入器
- `store`: 事实存储
- `query`: 查询引擎

**返回值:** 新的 LockPass 实例

```zig
var lock_pass = LockPass.init(ctx, diag, store, query);
defer lock_pass.deinit();
```

#### deinit()

释放锁分析 Pass 资源。

```zig
lock_pass.deinit();
```

#### run()

运行锁分析。

**参数:**

- `func_id`: 要分析的函数 ID

**返回值:** 分析结果或错误

```zig
const result = try lock_pass.run(func_id);
```

## LockOperation

锁操作结构，表示锁的获取或释放操作。

### LockOperation 结构定义

```zig
pub const LockOperation = struct {
    /// Lock ID
    lock_id: u32,
    /// Operation type (acquire or release)
    op_type: LockOpType,
    /// Instruction ID
    inst_id: u32,
    /// Basic block ID
    bb_id: u32,
};
```

### LockOperation 字段说明

- **lock_id**: `u32` - 锁 ID
- **op_type**: `LockOpType` - 操作类型（获取或释放）
- **inst_id**: `u32` - 指令 ID
- **bb_id**: `u32` - 基本块 ID

### LockOpType 枚举

```zig
pub const LockOpType = enum {
    /// Lock acquire operation
    acquire,
    /// Lock release operation
    release,
};
```

## LockGraph

锁图结构，用于建模锁依赖关系和检测循环。

### LockGraph 结构定义

```zig
pub const LockGraph = struct {
    allocator: std.mem.Allocator,
    // Nodes are lock IDs
    nodes: std.ArrayList(u32),
    // Edges represent "acquired after" relationships
    edges: std.ArrayList(LockEdge),
    // Adjacency list for graph traversal
    adjacency: std.AutoHashMap(u32, []const u32),
};
```

### LockGraph 字段说明

- **allocator**: `std.mem.Allocator` - 内存分配器
- **nodes**: `std.ArrayList(u32)` - 节点列表（锁 ID）
- **edges**: `std.ArrayList(LockEdge)` - 边列表（表示"在...之后获取"关系）
- **adjacency**: `std.AutoHashMap(u32, []const u32)` - 邻接表用于图遍历

### LockGraph 方法

#### init()

初始化锁图。

**参数:**

- `allocator`: 内存分配器

**返回值:** 新的 LockGraph 实例

```zig
var lock_graph = LockGraph.init(allocator);
defer lock_graph.deinit();
```

#### deinit()

释放锁图资源。

```zig
lock_graph.deinit();
```

#### addNode()

向图中添加节点（锁）。

**参数:**

- `lock_id`: 锁 ID

```zig
lock_graph.addNode(lock_id);
```

#### addEdge()

向图中添加边（表示获取顺序）。

**参数:**

- `from`: 源锁 ID
- `to`: 目标锁 ID

```zig
lock_graph.addEdge(from_lock, to_lock);
```

#### hasCycle()

检测图中是否存在循环（死锁）。

**返回值:** 如果存在循环返回 true

```zig
if (lock_graph.hasCycle()) {
    // 检测到潜在死锁
}
```

#### hasCycleDFS()

使用 DFS 算法检测循环。

**返回值:** 如果存在循环返回 true

```zig
if (lock_graph.hasCycleDFS()) {
    // 检测到潜在死锁
}
```

## 锁识别

LockPass 识别以下锁相关函数：

### 互斥锁（Mutex）

- `pthread_mutex_lock` - 获取互斥锁
- `pthread_mutex_unlock` - 释放互斥锁
- `pthread_mutex_trylock` - 尝试获取互斥锁

### 读写锁（RWLock）

- `pthread_rwlock_rdlock` - 获取读锁
- `pthread_rwlock_wrlock` - 获取写锁
- `pthread_rwlock_unlock` - 释放读写锁

### 自旋锁（Spinlock）

- `pthread_spin_lock` - 获取自旋锁
- `pthread_spin_unlock` - 释放自旋锁

### isLockOperation()

检查函数是否是锁操作。

**参数:**

- `func_name`: 函数名

**返回值:** 如果是锁操作返回 true

```zig
if (LockPass.isLockOperation("pthread_mutex_lock")) {
    // 这是锁操作
}
```

### isLockAcquire()

检查函数是否是锁获取操作。

**参数:**

- `func_name`: 函数名

**返回值:** 如果是锁获取操作返回 true

```zig
if (LockPass.isLockAcquire("pthread_mutex_lock")) {
    // 这是锁获取操作
}
```

### isLockRelease()

检查函数是否是锁释放操作。

**参数:**

- `func_name`: 函数名

**返回值:** 如果是锁释放操作返回 true

```zig
if (LockPass.isLockRelease("pthread_mutex_unlock")) {
    // 这是锁释放操作
}
```

## getLockId()

为锁对象分配唯一 ID。

**参数:**

- `lock_value`: LLVM 值引用（锁对象）

**返回值:** 锁 ID

```zig
const lock_id = lock_pass.getLockId(lock_value);
```

## 使用示例

### 基本锁分析

```zig
const std = @import("std");
const lock = @import("lock");

pub fn analyzeLocks() !void {
    var lock_pass = LockPass.init(ctx, diag, store, query);
    defer lock_pass.deinit();

    // 分析函数
    const func_id = 1;
    const result = try lock_pass.run(func_id);

    // 检查检测到的死锁
    for (result.deadlocks) |deadlock| {
        std.debug.print("Potential deadlock detected\n");
        for (deadlock.lock_sequence) |lock_id| {
            std.debug.print("  Lock {}\n", .{lock_id});
        }
    }
}
```

### 检查锁操作

```zig
pub fn checkLockOperations() void {
    // 检查锁操作
    if (LockPass.isLockOperation("pthread_mutex_lock")) {
        std.debug.print("pthread_mutex_lock is a lock operation\n");
    }

    // 检查锁获取
    if (LockPass.isLockAcquire("pthread_mutex_lock")) {
        std.debug.print("pthread_mutex_lock is an acquire operation\n");
    }

    // 检查锁释放
    if (LockPass.isLockRelease("pthread_mutex_unlock")) {
        std.debug.print("pthread_mutex_unlock is a release operation\n");
    }
}
```

## 死锁检测算法

LockPass 使用以下算法检测死锁：

1. **锁操作收集**: 遍历函数中的所有指令，识别锁获取和释放操作
2. **锁 ID 分配**: 为每个锁对象分配唯一 ID
3. **依赖图构建**: 构建锁获取顺序图
   - 如果在持有锁 A 的情况下获取锁 B，则添加边 A → B
4. **循环检测**: 使用 DFS 算法检测图中的循环
   - 循环表示潜在的死锁场景

## 检测的问题

LockPass 可以检测以下死锁场景：

- **AB-BA 死锁**: 线程1持有锁A等待锁B，线程2持有锁B等待锁A
- **多锁死锁**: 涉及多个锁的循环等待
- **嵌套锁死锁**: 不一致的锁获取顺序

## 限制

1. **静态分析**: LockPass 是静态分析工具，可能无法检测运行时才出现的死锁
2. **跨函数分析**: 当前实现主要分析单个函数内的锁操作
3. **锁类型**: 主要支持 POSIX 线程锁，其他锁类型可能需要额外配置
4. **误报**: 可能会产生误报，特别是在复杂的控制流中

## 注意事项

1. **依赖关系**: LockPass 依赖于 cfg、dfg 和 alias Pass，必须在这些 Pass 之后运行。
2. **锁顺序**: 始终以一致的顺序获取多个锁可以避免死锁
3. **锁粒度**: 使用细粒度锁可以提高并发性，但增加死锁检测复杂性
4. **超时机制**: 考虑使用带超时的锁获取操作来避免无限等待
5. **代码审查**: 死锁检测工具应与代码审查结合使用
