# OmniScope v0.2.1 Development Plan — Cross-Language FFI Analysis

> **Version**: v0.2.1 (Cross-Language FFI Analysis)
> **Core Positioning**: 通用 FFI/Unsafe 边界分析器（支持 C/C++/Rust/Go/Zig/Python）
> **Goal**: FFI 边界检测准确率从 ~35% 提升到 70%+，噪音降低 80%+
> **Coding Rules**: Follow `plan/rules/rules.md` strictly (snake_case, <1000 lines/file, English comments)

---

## 核心问题：语言运行时噪音

### 问题分析（来自 plan/lang_ffi_analysis/plan.md）

| 语言 | 项目 | 问题数 | FP率 | 根因 |
|------|------|--------|------|------|
| Rust | wasmtime | 297 | 98% | 编译器生成 glue/drop/monomorphization |
| Zig | 平均 | 191 | 79% | stdlib internals/allocator wrappers |
| C | SQLite/libcurl | 0-3 | 0% | 手写逻辑直白 |

**结论**：现代语言项目不是代码难分析，而是标准库和编译器生成代码太多。

**解决方案**：Cross-Language Noise Reduction Engine

---

## P0 — 跨语言噪音过滤系统（最高优先级）

### P0-1: 三层过滤体系

#### Layer 1: Name-based Filter（最快）

**Rust 过滤规则**：
```
跳过：
- core::, alloc::, std::
- panic_, drop_in_place
- RawVec, Vec<, slice::, fmt::
- _ZN4core, _ZN5alloc, _RNv, $LT$core

重点分析：
- unsafe { ... }
- extern "C"
- libc::
- *mut T, from_raw/into_raw
```

**Zig 过滤规则**：
```
跳过：
- std., mem.Allocator
- array_list, hash_map
- fmt., heap.
- start.zig, panic.zig

重点分析：
- src/, app/, pkg/
- custom allocator
- @cImport, extern fn
```

**C++ 过滤规则**：
```
跳过：
- std::, __gnu_cxx::
- __cxa_, __clang_call_terminate

重点分析：
- extern "C"
- 手写 FFI wrapper
```

**Go 过滤规则**：
```
跳过：
- runtime., internal/
- _cgo_gotypes, _cgo_alloc

重点分析：
- import "C"
- C.xxx 调用
```

**实现**：
- [ ] `src/semantics/noise_filter.zig` — 扩展现有文件
- [ ] `FunctionOrigin` 枚举：user, stdlib, compiler_generated, third_party
- [ ] `classifyFunction(func_name, debug_info)` — 函数分类
- [ ] 集成到所有分析 pass

#### Layer 2: Path/Debug Metadata Filter（最准）

**源码路径过滤**：
```
Rust:
- /rustc/, library/core/, library/std/
- cargo/registry

Zig:
- zig/lib/std/

C++:
- /usr/include/c++/, /libc++/

Go:
- runtime/, internal/
```

**实现**：
- [ ] `src/ir/debug_info.zig` — 扩展 debug info 解析
- [ ] `getSourcePath(inst)` — 获取指令源码路径
- [ ] `isStdlibPath(path)` — 判断是否标准库路径
- [ ] 集成到分析流程

#### Layer 3: Behavior Filter（最智能）

**Rust drop glue 特征**：
```
free + memset + branch + panic path
→ compiler_generated_cleanup
```

**Zig allocator wrapper 特征**：
```
call alloc + store len + return slice
→ allocator_adapter
```

**STL vector grow 特征**：
```
malloc → memcpy → free old buffer
→ reallocation (not leak)
```

**实现**：
- [ ] `src/semantics/behavior_filter.zig` — 新文件
- [ ] `detectDropGlue(func)` — 检测 Rust drop glue
- [ ] `detectAllocatorWrapper(func)` — 检测 Zig allocator wrapper
- [ ] `detectSTLPattern(func)` — 检测 C++ STL 模式

### P0-2: 风险权重系统

```zig
const RiskWeight = struct {
    origin: FunctionOrigin,
    issue_kind: IssueKind,
    weight: f32,
};

// 示例：
// user + dangerous sink = HIGH (weight: 1.0)
// stdlib + leak = SUPPRESSED (weight: 0.1)
// compiler_generated + double_free = IGNORE (weight: 0.0)
```

**实现**：
- [ ] `src/semantics/risk_weight.zig` — 新文件
- [ ] `computeRiskWeight(origin, issue)` — 计算风险权重
- [ ] 集成到 Issue 报告系统

---

## P1 — 跨语言 FFI 类型不匹配检测（已实现基础）

### P1-1: 通用 FFI 边界识别

**支持的语言对**：
- C ↔ C++（extern 声明）
- Rust ↔ C（extern "C"）
- Go ↔ C（cgo）
- Zig ↔ C（extern fn）
- Python ↔ C（C API）

**实现**：
- [x] `src/pass/analysis/ffi_type_mismatch.zig` — 基础框架
- [ ] 扩展支持所有语言对
- [ ] 添加 C++ ABI 不匹配检测
- [ ] 添加 Zig 对齐不匹配检测

### P1-2: 类型不匹配检测

**检测类型**：
- 大小不匹配（usize vs size_t）
- 对齐不匹配（@alignOf vs alignof）
- 符号不匹配（signed vs unsigned）
- ABI 不匹配（name mangling, calling convention）

**实现**：
- [x] 大小不匹配检测
- [ ] 对齐不匹配检测
- [ ] 符号不匹配检测
- [ ] ABI 不匹配检测

---

## P2 — 语言特定 FFI 分析

### P2-1: Rust FFI 分析

**重点检测**（来自 plan/lang_ffi_analysis/rust_ffi_filter.md）：
- unsafe 块内的裸指针操作
- extern "C" 函数的类型安全
- from_raw/into_raw 所有权转移
- libc 调用的参数验证

**Intrinsic 分类**：
- 原子操作类：atomic_xxx
- 内存操作类：copy, write_bytes
- 指针操作类：offset, ptr_offset_from
- 类型信息类：size_of, align_of
- 浮点/整数运算类
- SIMD 向量操作类

**实现**：
- [ ] `src/pass/analysis/rust_ffi_audit.zig` — 新文件
- [ ] `detectUnsafeBlock(func)` — 检测 unsafe 块
- [ ] `validateExternC(call)` — 验证 extern "C" 调用
- [ ] `checkRawPointerOps(inst)` — 检查裸指针操作

### P2-2: Go cgo 分析

**重点检测**（来自 plan/lang_ffi_analysis/go_ffi_fliter.md）：
- import "C" 识别
- C.xxx 调用的类型安全
- Go 指针逃逸（传递给 C 的指针）
- runtime.KeepAlive 缺失

**识别标准**：
- AST 中存在 `*ast.SelectorExpr`，X 为 "C"
- C 函数调用：`*ast.CallExpr`，Fun 为 SelectorExpr

**实现**：
- [ ] `src/pass/analysis/go_cgo_audit.zig` — 新文件
- [ ] `detectCgoCall(call)` — 检测 cgo 调用
- [ ] `checkGoPointerEscape(call)` — 检查 Go 指针逃逸
- [ ] `validateKeepAlive(call)` — 验证 KeepAlive

### P2-3: Zig FFI 分析

**重点检测**（来自 plan/lang_ffi_analysis/zig_ffi_filter.md）：
- @cImport 导入的函数
- extern fn 声明
- 对齐不匹配（@alignOf vs C alignof）
- 自定义 allocator 的正确性

**实现**：
- [ ] `src/pass/analysis/zig_ffi_audit.zig` — 新文件
- [ ] `detectExternFn(func)` — 检测 extern 函数
- [ ] `checkAlignmentMismatch(call)` — 检查对齐不匹配
- [ ] `validateAllocator(alloc)` — 验证 allocator

### P2-4: C/C++ FFI 分析

**重点检测**：
- extern "C" 声明的类型安全
- C++ name mangling 不匹配
- 调用约定不匹配（cdecl vs stdcall）
- ABI 兼容性

**实现**：
- [ ] `src/pass/analysis/cpp_ffi_audit.zig` — 新文件
- [ ] `detectExternC(func)` — 检测 extern "C"
- [ ] `checkNameMangling(func)` — 检查 name mangling
- [ ] `validateCallingConv(call)` — 验证调用约定

### P2-5: Python C API 分析

**重点检测**：
- Py* 函数的引用计数
- PyObject* 的 INC/DEC 配对
- GIL 相关问题

**实现**：
- [ ] `src/pass/analysis/python_capi_audit.zig` — 新文件
- [ ] `checkRefcount(func)` — 检查引用计数
- [ ] `validateGIL(call)` — 验证 GIL

---

## P3 — 输出层优化

### P3-1: 归因分组报告

**当前输出**：
```
191 issues
```

**目标输出**：
```
191 issues
- 162 from Zig stdlib (suppressed)
- 21 user code medium risk
- 8 FFI boundary high risk
```

**实现**：
- [ ] `src/output/attribution.zig` — 新文件
- [ ] `groupByOrigin(issues)` — 按来源分组
- [ ] `formatAttributionReport(groups)` — 格式化归因报告

### P3-2: CLI 参数

```bash
omniscope scan --focus-user-code
omniscope scan --ffi-only
omniscope scan --include-stdlib
```

**实现**：
- [ ] 扩展 CLI 参数解析
- [ ] 添加过滤选项
- [ ] 添加报告格式选项

---

## P4 — 性能优化

### P4-1: 函数分类缓存

**实现**：
- [ ] 缓存函数分类结果
- [ ] 避免重复分析 stdlib 函数
- [ ] 增量更新支持

### P4-2: 并行分析

**实现**：
- [ ] 函数级并行分析
- [ ] 线程安全的 Issue 收集
- [ ] 性能目标：4 核 2-3x 提升

---

## 预期效果

| 指标 | 当前 (v0.2.0) | 目标 (v0.2.1) |
|------|---------------|---------------|
| **Rust FP 率** | 98% | **< 10%** |
| **Zig FP 率** | 79% | **< 20%** |
| **C FP 率** | 0% | **0%** |
| **FFI 边界检测准确率** | ~35% | **70%+** |
| **总 Issues 准确率** | ~35% | **60%+** |
| **分析性能** | 9.5s | **< 5s** |

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

---

## 关键原则

1. **通用性**：支持所有主流语言的 FFI 分析
2. **噪音过滤**：三层过滤体系降低 FP 率 80%+
3. **可扩展**：易于添加新语言支持
4. **可配置**：用户可选择分析范围
5. **可解释**：每个警告都有明确原因和来源

---

## 下一步行动

**本周目标**（P0-1）：
1. 实现三层过滤体系
2. 降低 Rust/Zig FP 率到 < 20%
3. 测试：wasmtime, Zig 项目

**下周目标**（P1-1）：
1. 完善 FFI 类型不匹配检测
2. 支持所有语言对
3. 测试：跨语言项目
