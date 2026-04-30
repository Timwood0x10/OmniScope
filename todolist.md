# OmniScope v0.2.1 Development Plan — FFI/Unsafe 专项优化

> **Version**: v0.2.1 (FFI/Unsafe Specialization)
> **Core Positioning**: unsafe/FFI 边界专项分析器（90%+ 内容），通用分析（<15%）
> **Goal**: FFI 边界检测准确率从 ~35% 提升到 70%+，跨语言所有权追踪完整实现
> **Coding Rules**: Follow `plan/rules/rules.md` strictly (snake_case, <1000 lines/file, English comments)

---

## 项目定位澄清

### OmniScope 是什么？

**FFI/Unsafe 边界专项安全分析器**，不是通用静态分析器。

| 分析类型 | 占比 | 重点 |
|---------|------|------|
| **FFI 边界分析** | 70% | 跨语言调用、类型不匹配、所有权转移 |
| **Unsafe 代码分析** | 20% | unsafe 块、裸指针、手动内存管理 |
| **通用内存安全** | 10% | double-free、use-after-free、leak |

### 核心能力

1. **跨语言 FFI 边界检测**（核心价值）
   - Rust ↔ C 边界：所有权转移、生命周期不匹配
   - Go cgo 边界：指针逃逸、GC 不安全
   - Zig ↔ C 边界：对齐、调用约定
   - Python C API：引用计数、GIL

2. **Unsafe 代码审计**
   - Rust unsafe 块：裸指针解引用、未检查的数组访问
   - C 内联汇编：约束违规
   - 手动内存管理：malloc/free 配对

3. **跨语言所有权追踪**（已实现基础）
   - 工厂/析构模式识别
   - 输出参数模式
   - 引用计数模式

---

## v0.2.0 已完成优化

### ✅ 跨函数所有权追踪基础

**实现**:
- `propagateMemoryGraphThroughCall()` - 跨函数别名传播
- `classifyArgDirectionByName()` - 6 种参数方向模式
- `isOutputParam()` - 输出参数识别
- `checkMallocFreePairing()` - 工厂/析构模式识别

**效果**:
- FREE-ORPHAN: 225 → 0 (100% 消除)
- 模式抑制: 2000+ 自动

### ✅ 内存图增强检测

**新增方法**:
- `isUseAfterFreeViaAlias()` - 别名 UAF 检测
- `findDangerousAliases()` - 危险别名查找
- `validateOwnershipTransfer()` - 所有权转移验证
- `analyzeLifecycle()` - 资源生命周期追踪

---

## P0 — FFI 边界分析强化（核心价值，优先级最高）

### P0-1: 跨语言类型不匹配检测

**问题**: FFI 边界最常见的 bug 是类型不匹配，但当前检测不足。

**目标**: 检测以下 FFI 类型不匹配：

| 语言对 | 常见问题 | 检测方法 |
|--------|---------|---------|
| Rust ↔ C | `usize` vs `size_t`（32/64 位差异） | 类型大小检查 |
| Go cgo | Go 指针 → C（GC 不安全） | `runtime.KeepAlive` 检查 |
| Python C API | `PyObject*` 引用计数错误 | INC/DEC 配对检查 |
| Zig ↔ C | 对齐不匹配 | `@alignOf` vs C alignment |

**实现**:
- [ ] `src/pass/analysis/ffi_type_mismatch.zig` — 新文件
- [ ] `checkTypeMismatch(caller_type, callee_type, lang_boundary)` — 类型兼容性检查
- [ ] `detectGoPointerEscape()` — Go cgo 指针逃逸
- [ ] `detectPythonRefcountMismatch()` — Python 引用计数不匹配
- [ ] 集成到 `ffi_boundary.zig` 的边界检测流程

**预期效果**: FFI 类型不匹配检测准确率 60%+

### P0-2: 跨语言所有权转移验证

**问题**: 当前只追踪 C 内部的所有权，跨语言边界未处理。

**目标**: 完整追踪跨语言所有权转移：

```
Rust: let ptr = unsafe { C.malloc(size) };
      ↓ FFI 边界（所有权转移）
C:    void* malloc(size_t size);
      ↓ 返回值
Rust: 需要手动 free，但编译器不知道
```

**实现**:
- [ ] `src/pass/analysis/cross_lang_ownership.zig` — 新文件
- [ ] `trackFFIOwnershipTransfer(call_site, from_lang, to_lang)` — 跨语言所有权追踪
- [ ] `validateRustToC(ptr, call)` — Rust → C 所有权验证
- [ ] `validateCToRust(ptr, call)` — C → Rust 所有权验证
- [ ] 集成到 `propagateMemoryGraphThroughCall()`

**预期效果**: 跨语言所有权 bug 检测准确率 50%+

### P0-3: FFI 调用约定不匹配

**问题**: 不同语言/平台的调用约定差异导致 bug。

**目标**: 检测调用约定不匹配：

| 问题 | 示例 | 检测 |
|------|------|------|
| 栈不平衡 | Rust `extern "C"` vs C `__stdcall` | 栈对齐检查 |
| 寄存器约定 | System V ABI vs Windows x64 | 参数传递检查 |
| 返回值位置 | sret vs 寄存器返回 | 返回值类型检查 |

**实现**:
- [ ] `src/pass/analysis/abi_mismatch.zig` — 扩展现有文件
- [ ] `detectCallingConvMismatch(caller_conv, callee_conv)` — 调用约定检查
- [ ] `checkStackAlignment(call_site)` — 栈对齐检查
- [ ] 集成到 `ffi_boundary.zig`

**预期效果**: ABI 不匹配检测准确率 70%+

---

## P1 — Unsafe 代码审计强化（占比 20%）

### P1-1: Rust unsafe 块深度分析

**问题**: 当前对 Rust unsafe 块的分析较浅。

**目标**: 深度分析 unsafe 块内的危险操作：

```rust
unsafe {
    // 1. 裸指针解引用 - 可能空指针
    let x = *ptr;
    
    // 2. 未检查的数组访问 - 可能越界
    let y = arr[i];
    
    // 3. FFI 调用 - 可能违反契约
    C.function(ptr);
}
```

**实现**:
- [ ] `src/pass/analysis/rust_unsafe_audit.zig` — 新文件
- [ ] `detectRawPointerDeref(inst)` — 裸指针解引用检查
- [ ] `detectUncheckedArrayAccess(inst)` — 未检查数组访问
- [ ] `validateFFIContract(call)` — FFI 契约验证
- [ ] 集成到 `ptr_lifetime.zig`

**预期效果**: Rust unsafe 块 bug 检测准确率 80%+

### P1-2: C 内联汇编约束检查

**问题**: 内联汇编的约束违规可能导致 UB。

**目标**: 检测内联汇编约束问题：

```c
asm volatile ("mov %0, %1" 
    : "=r"(output)    // 输出约束
    : "r"(input)      // 输入约束
    : "memory"        // clobber
);
```

**实现**:
- [ ] `src/pass/analysis/inline_asm_check.zig` — 新文件
- [ ] `validateAsmConstraints(asm_inst)` — 约束验证
- [ ] `detectClobberViolation(asm_inst)` — clobber 违规检测
- [ ] 集成到 `ffi_boundary.zig`

**预期效果**: 内联汇编 bug 检测准确率 60%+

---

## P2 — 跨函数追踪激活（基础设施）

### P2-1: 激活 propagateMemoryGraphThroughCall

**问题**: 已实现但未实际调用。

**实现**:
- [ ] 在 `callback_escape.zig` 中构建 CallGraph
- [ ] 对每个调用边调用 `propagateMemoryGraphThroughCall()`
- [ ] 验证跨函数别名传播正确性
- [ ] 性能测试：sqlite3 分析时间 < 10s

**预期效果**: 跨函数追踪真正生效

### P2-2: 调用图构建优化

**问题**: 当前调用图构建效率低。

**实现**:
- [ ] 单次遍历构建完整调用图
- [ ] 缓存间接调用解析结果
- [ ] 增量更新支持
- [ ] 性能目标：10000 函数 < 1s

**预期效果**: 調用图构建速度 5-10x 提升

---

## P3 — 性能优化（保持快速）

### P3-1: 内存池优化

**实现**:
- [ ] `src/perf/memory_pool.zig` — 扩展现有文件
- [ ] 为 AllocNode、CallNode 等使用内存池
- [ ] 减少分配次数 80%+
- [ ] 性能目标：分配开销 < 5%

**预期效果**: 性能提升 20-30%

### P3-2: 并行分析

**实现**:
- [ ] 函数级并行分析（不同函数可并行）
- [ ] 线程安全的 Issue 收集
- [ ] 性能目标：4 核 2-3x 提升

**预期效果**: 性能提升 2-4x（多核）

---

## P4 — 模式库替代白名单（可维护性）

### P4-1: 扩展模式库

**当前模式**:
- 工厂函数：Alloc, Create, New, Init, Open
- 析构函数：Free, Destroy, Close, Release
- 转移函数：Clone, Copy, Move

**新增模式**:
- [ ] 引用计数：Ref, Retain, AddRef ↔ Unref, Release, DecRef
- [ ] 锁操作：Lock, Acquire ↔ Unlock, Release
- [ ] 文件操作：Open, Fopen ↔ Close, Fclose
- [ ] 线程操作：Create, Spawn ↔ Join, Detach

**实现**:
- [ ] `src/semantics/pattern_library.zig` — 新文件
- [ ] 统一模式匹配接口
- [ ] 可扩展模式注册

**预期效果**: 白名单依赖减少 80%+

### P4-2: 置信度系统

**实现**:
- [ ] `src/semantics/confidence.zig` — 新文件
- [ ] `computeConfidence(issue, context)` — 置信度计算
- [ ] 多因子加权评分
- [ ] 阈值过滤（默认 0.7）

**预期效果**: 误报率降低 50%+

---

## 预期效果

| 指标 | v0.2.0 | v0.2.1 目标 |
|------|--------|------------|
| **FFI 边界检测准确率** | ~35% | **70%+** |
| **Unsafe 代码检测准确率** | ~40% | **80%+** |
| **跨语言所有权追踪** | 基础实现 | **完整实现** |
| **总 Issues 准确率** | ~35% | **60%+** |
| **分析性能（sqlite3）** | 9.5s | **< 5s** |
| **白名单依赖** | 高 | **低（模式库替代）** |

---

## 编码规范检查清单

每次提交前检查：

- [ ] 文件 < 1000 行
- [ ] 注释全英文，code:comment ≈ 7:3
- [ ] camelCase 函数名，snake_case 变量名，TitleCase 类型名
- [ ] 4 空格缩进
- [ ] 公开 API 有 doc comment
- [ ] 测试覆盖 happy path + boundary + error path
- [ ] `zig fmt` 格式化
- [ ] `zig build test` 通过
- [ ] 不删除文件（rules.md 2.5）
- [ ] **FFI/Unsafe 分析占比 > 85%**

---

## 关键原则

1. **专注 FFI/Unsafe**：90%+ 的开发精力放在 FFI 边界和 unsafe 代码分析
2. **跨语言优先**：跨语言 bug 是编译器盲区，是我们的核心价值
3. **模式 > 白名单**：用模式识别替代白名单，提高可扩展性
4. **性能可控**：保持快速分析，大型项目 < 10s
5. **可解释性**：每个警告都有明确原因，不搞黑盒 ML

---

## 下一步行动

**本周目标**（P0-1）：
1. 实现 `ffi_type_mismatch.zig`
2. 检测 Rust ↔ C 类型不匹配
3. 检测 Go cgo 指针逃逸
4. 测试：用 Rust FFI 测试用例验证

**下周目标**（P0-2）：
1. 实现 `cross_lang_ownership.zig`
2. 跨语言所有权追踪
3. 集成到现有分析流程
