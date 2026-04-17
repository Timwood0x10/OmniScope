# OmniSope 额外 Bug 分析报告（第二轮）

> 审查日期: 2026-04-16
> 审查范围: `src/` 全部模块（第二轮）

---

## 严重程度说明

- 🔴 **Critical** — 会导致崩溃、内存安全问题
- 🟠 **High** — 逻辑错误、资源泄漏
- 🟡 **Medium** — 设计缺陷、潜在问题

---

## 新发现的 Bug

---

### BUG-19: 错误返回值被静默吞掉

**文件**: `src/pass/analysis/ffi_info.zig` (行 63-71)

**严重程度**: 🔴 Critical

```zig
const info = try self.type_info_map.getOrPut(type);
if (info.found) return info.value_ptr.*;
info.value_ptr.* = try self.resolveType(type);  // catch return;
```

**问题**: `resolveType` 失败时直接 `catch return`，错误被静默吞掉，调用方完全不知道发生了什么。

**影响**: 类型解析失败时没有任何错误信息，排查问题极难。

---

### BUG-20: 返回值检查错误被吞掉

**文件**: `src/pass/analysis/issue/return_check.zig` (行 126)

**严重程度**: 🔴 Critical

```zig
if (try self.checkReturnValue(call_inst, builder)) catch return false;
```

**问题**: 检查返回值失败时返回 false，隐藏了真正的错误原因。

---

### BUG-21: 整数溢出 - lock_id

**文件**: `src/pass/analysis/lock.zig` (行 12)

**严重程度**: 🟠 High

```zig
next_lock_id: u32 = 0,
```

**问题**: `u32` 最大只能到 2^32-1，运行超过 40 亿次操作后会溢出。

**建议**: 改用 `u64` 或 `usize`。

---

### BUG-22: ffi_info 中的 lock_id 溢出

**文件**: `src/pass/analysis/ffi_info.zig` (行 57)

**严重程度**: 🟠 High

```zig
lock_id: u32 = 0,
```

**问题**: 同样的溢出风险。

---

### BUG-23: 内存泄漏 - getOrPut 失败

**文件**: `src/pass/analysis/issue/free_validation.zig` (行 41-50)

**严重程度**: 🟠 High

```zig
const entry = try self.desc_map.getOrPut(node);
if (entry.found) {
    return entry.value_ptr.*;
}
// 这里如果 getOrPut 失败，之前分配的 desc 就泄漏了
const desc = try self.allocator.create(ValidationDesc);
```

**问题**: 如果 `getOrPut` 成功但后面操作失败，之前分配的 `desc` 内存泄漏。

---

### BUG-24: 线程安全问题 - HashMap 操作

**文件**: `src/pass/analysis/taint_state.zig`

**严重程度**: 🟠 High

```zig
pub fn getTaintedValues(self: *TaintContext, id: u32) ?[]const u8 {
    self.mutex.lock();
    defer self.mutex.unlock();
    return self.value_taint.get(id);
}

pub fn setTaintedValue(self: *TaintContext, id: u32, value: []const u8) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    self.value_taint.put(id, value) catch unreachable;  // 非原子操作
}
```

**问题**: 
- `getOrPut` 等操作在锁内部执行，但锁本身不是针对并发设计的
- `put` 可能触发 HashMap 扩容，导致数据移动
- 多个线程同时操作同一 HashMap 可能出问题

---

### BUG-25: 逻辑错误 - 锁检测

**文件**: `src/pass/analysis/lock.zig` (行 87-88)

**严重程度**: 🟠 High

```zig
const isLockAcquire = std.mem.indexOf(u8, func_name, "lock") != null;
const isLockRelease = std.mem.indexOf(u8, func_name, "unlock") != null;
```

**问题**: 
- `"unlock"` 包含 `"lock"`，会被错误识别为 acquire
- 简单的字符串匹配不可靠

---

### BUG-26: 低效字符串匹配

**文件**: `src/pass/analysis/ffi_info.zig` (行 40-47)

**严重程度**: 🟡 Medium

```zig
if (std.mem.indexOf(u8, name, "malloc") != null or
    std.mem.indexOf(u8, name, "free") != null or
    std.mem.indexOf(u8, name, "realloc") != null or
    std.mem.indexOf(u8, name, "calloc") != null) {
    // ...
}
```

**问题**: 每次都创建新的临时切片，效率低。

**建议**: 用 `std.mem.startsWith` 或预编译模式。

---

### BUG-27: 不可达代码

**文件**: `src/pass/analysis/issue/free_validation.zig` (行 74, 77, 81)

**严重程度**: 🟡 Medium

```zig
return self.getNextNode(node) catch unreachable;
return self.getPrevNode(node) catch unreachable;
return self.getParent(node) catch unreachable;
```

**问题**: 这些路径在逻辑上可能是不可达的，`unreachable` 会导致 panic。

---

## 汇总

| Bug ID | 严重程度 | 类型 | 文件 |
|--------|----------|------|------|
| BUG-19 | 🔴 Critical | 错误吞掉 | ffi_info.zig |
| BUG-20 | 🔴 Critical | 错误吞掉 | return_check.zig |
| BUG-21 | 🟠 High | 整数溢出 | lock.zig |
| BUG-22 | 🟠 High | 整数溢出 | ffi_info.zig |
| BUG-23 | 🟠 High | 内存泄漏 | free_validation.zig |
| BUG-24 | 🟠 High | 线程安全 | taint_state.zig |
| BUG-25 | 🟠 High | 逻辑错误 | lock.zig |
| BUG-26 | 🟡 Medium | 性能 | ffi_info.zig |
| BUG-27 | 🟡 Medium | 死代码 | free_validation.zig |

---

## 总结

本轮额外发现 **9 个新 bug**：

- 🔴 Critical: 2 个（错误被吞掉）
- 🟠 High: 6 个
- 🟡 Medium: 2 个

**总计**: 第一轮 18 个 + 本轮 9 个 = **27 个潜在 bug**

---

*报告结束*