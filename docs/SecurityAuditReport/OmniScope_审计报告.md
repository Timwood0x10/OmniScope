The user wants me to output the audit report directly in the conversation, not to a file. They don't want me to write any files. Let me just output the report content directly.
好，以下是完整审计报告：

---

# OmniScope 安全审计报告

| 项目 | 信息 |
|------|------|
| **项目名称** | OmniScope |
| **项目类型** | LLVM IR 跨语言 FFI 静态安全分析框架 |
| **实现语言** | Zig |
| **审计日期** | 2026-04-20 |
| **审计范围** | `src/` 全部源文件 |
| **审计方法** | 人工代码审计 |

## 1. 审计概览

| 严重等级 | 数量 |
|----------|------|
| 🔴 严重 (Critical) | 2 |
| 🔴 高危 (High) | 12 |
| 🟠 中危 (Medium) | 10 |
| 🟡 低危 (Low) | 8 |
| **合计** | **32** |

---

## 2. 严重漏洞 (Critical)

### OS-C01：`ffi_boundary.zig` — 返回栈内存悬垂指针

- **行号**：462-463
- `demangleRustName` 中 `var buf: [128]u8 = undefined` 是栈变量，`bufPrint` 返回指向它的切片，函数返回后 `buf` 已销毁。调用者拿到的是**无效栈内存**，未定义行为。
- **修复**：改用 `allocator.allocPrint` 或调用者提供缓冲区。

### OS-C02：`taint_state.zig` — 调用不存在的方法 `getOrCreateId`

- **行号**：79, 86
- `ValueIdMap` 中方法名是 `getOrPutId`，但代码调用的是 `getOrCreateId`。**编译错误**。
- **修复**：改为 `getOrPutId`。

---

## 3. 高危漏洞 (High)

### OS-H01：`ffi_analysis.zig` — 指令指针 vs 数据指针匹配错误
- **行号**：213, 256, 281-331
- 用 `@intFromPtr(inst)`（call 指令地址）做 HashMap 键匹配分配/释放，但分配和释放是不同的 call 指令，指针永远不同。`detectDoubleFree` 和 `detectOwnershipMismatch` 基本失效。
- **修复**：追踪 `malloc`/`free` 的参数（实际数据指针），而非 call 指令地址。

### OS-H02：`taint.zig` — `getOrPut` 使用方式错误导致死代码
- **行号**：300-311, 340-353, 382-394
- `getOrPut` 返回的不是 optional，`if` 始终匹配，else 分支是死代码。新 key 的 taint sources 不会被初始化。
- **修复**：用 `entry.found_existing` 判断。

### OS-H03：`graph.zig` — 对编译期常量切片调用 `free` 导致 UB
- **行号**：129-131, 93-96
- `addNode` 存入 `&[_]u32{}`，`deinit` 中 `allocator.free()` 释放编译期常量，未定义行为。
- **修复**：用 `allocator.alloc(u32, 0)` 或改用 `ArrayList`。

### OS-H04：`cfg.zig` — `LLVMValueRef` 与 `LLVMBasicBlockRef` 类型混淆
- **行号**：146-147, 152-153
- `LLVMGetOperand` 返回 `LLVMValueRef`，但用作 `LLVMBasicBlockRef` 类型的 HashMap 键。
- **修复**：用 `LLVMValueAsBasicBlock()` 转换。

### OS-H05：`ffi_detector.zig` — UAF 检测获取错误操作数
- **行号**：496
- LLVM Call 指令的 operand 0 是被调用函数，不是第一个参数。`free(ptr)` 的 `ptr` 是 operand 1。
- **修复**：改为 `LLVMGetOperand(inst, 1)`。

### OS-H06：`ffi_detector.zig` — 漏洞 ID 重复
- **行号**：232
- `vulnerability_count` 只在外层循环递增，同一 FFI match 的多个漏洞获得相同 ID。
- **修复**：每个漏洞创建后立即递增。

### OS-H07：`flow_path.zig` — 浅拷贝导致双重释放
- **行号**：188-198
- `build()` 值拷贝返回含 `ArrayList` 的结构体，共享底层缓冲区，双重 deinit 会 double-free。
- **修复**：重新设计为转移所有权。

### OS-H08：`alias.zig` — 指针截断 u64→u32
- **行号**：284
- `type_cache` 值类型是 `u32`，`@intFromPtr` 返回 `usize`，高 32 位被截断，不同类型映射到相同 ID。
- **修复**：值类型改为 `usize`。

### OS-H09：`lock.zig` — 死锁检测逻辑错误
- **行号**：288-302
- 内层循环遍历锁 A 的操作序列，但应遍历 `other_op.lock_id` 对应的序列。
- **修复**：遍历正确的锁操作序列。

### OS-H10：`taint_propagation.zig` — 访问非公开字段
- **行号**：543-565
- `storeResults` 直接访问 `TaintContext.value_taint`，若未标记 `pub` 则编译错误。
- **修复**：在 `TaintContext` 上提供公开迭代器方法。

### OS-H11：`memory_pool.zig` — ArenaAllocator 对齐 bug
- **行号**：155-176
- `allocator.alloc(u8, ...)` 只保证 1 字节对齐，但调用者可能请求更高对齐，`@alignCast` 在 release 模式下 UB。
- **修复**：使用 `alignedAlloc`。

### OS-H12：`value_id_map.zig` — ID 溢出无检查
- **行号**：51-52
- `u32` 类型的 `next_id += 1` 在 42 亿时静默回绕到 0，导致 ID 重复。
- **修复**：用 `@addWithOverflow` 或改为 `usize`。

---

## 4. 中危漏洞 (Medium)

| 编号 | 文件 | 行号 | 描述 |
|------|------|------|------|
| OS-M01 | `vulnerability_rules.zig` | 62-67, 112-114, 125-128, 166-169 | 子串匹配 + 不当规则导致大量误报（XSS 规则含标准 I/O 函数、整数溢出规则含运算符） |
| OS-M02 | `pointer_ownership.zig` | 563 | u64 静默截断为 u32 |
| OS-M03 | `pointer_ownership.zig` | 520 | OOM 时可达性分析返回假阴性 |
| OS-M04 | `manager.zig` | 150 | Kahn 算法 `orderedRemove(0)` 导致 O(n²) |
| OS-M05 | `ffi_boundary.zig` | 80-90 | `"extern"` 和 `"c_"` 模式过于宽泛 |
| OS-M06 | `semantic_registry.zig` | 787-815 | fallback 与注册表匹配策略不一致 |
| OS-M07 | `function_summary.zig` | 181-183 | `lookup` 返回值副本可能导致 double-free |
| OS-M08 | `fact/query.zig` | 29-109 | O(n) 线性扫描性能问题 |
| OS-M09 | `call_graph.zig` | 249 | 污点传播迭代上限仅 8 |
| OS-M10 | `pointer_ownership.zig` | 648, 654 | `boundary_id` API 歧义，0 既表示失败也可能是有效索引 |

---

## 5. 低危漏洞 (Low)

| 编号 | 文件 | 描述 |
|------|------|------|
| OS-L01 | 多文件 | `catch unreachable` 反模式（`store.zig` 已标注为设计决策） |
| OS-L02 | `main.zig:312-341` | 危险模式匹配过于宽泛 |
| OS-L03 | `graph.zig:393-394` | 空切片内存所有权不一致 |
| OS-L04 | `taint.zig:46-47` | `deinit()` 可能缺少 allocator 参数 |
| OS-L05 | `pointer_ownership.zig:197,227,234` | 定时器双重停止 |
| OS-L06 | `ffi_detector.zig:134-138` | `deinit` 未释放所有内存 |
| OS-L07 | `aggregator.zig:149,174` | 绕过 `add()` 直接 append |
| OS-L08 | `memory_pool.zig:164` | `len + alignment` 潜在整数溢出 |

---

## 6. 修复优先级

| 优先级 | 编号 | 描述 |
|--------|------|------|
| P0 | OS-C01 | 返回栈内存悬垂指针 |
| P0 | OS-C02 | `getOrCreateId` → `getOrPutId` |
| P0 | OS-H03 | 编译期常量切片 `free` 导致 UB |
| P0 | OS-H04 | LLVM 类型混淆 |
| P1 | OS-H01 | 指令指针 vs 数据指针 |
| P1 | OS-H02 | `getOrPut` 死代码 |
| P1 | OS-H05 | UAF 检测错误操作数 |
| P1 | OS-H07 | 浅拷贝双重释放 |
| P1 | OS-H08 | 指针截断 |
| P1 | OS-H11 | Arena 对齐 bug |
| P2 | OS-H06, H09, H10, H12 | ID 重复/死锁逻辑/字段访问/ID 溢出 |
| P2 | OS-M01~M10 | 中危漏洞 |
| P3 | OS-L01~L08 | 低危漏洞 |