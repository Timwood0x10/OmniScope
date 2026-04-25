# 更新日志 / Changelog

OmniScope 的所有重要变更都将记录在此文件中。/ All notable changes to OmniScope will be documented in this file.

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)，遵循 [语义化版本](https://semver.org/spec/v2.0.0.html)。

---

## \[0.1.5] - 2026-04-24

### 🔒 安全 — 关键 Bug 修复 / Security — Critical Bug Fixes

**安全审计和代码审查发现并修复了 12 个 Bug。**

#### 高严重度 (6 个)

| Bug ID | 文件 | 问题 | 修复 |
|--------|------|------|------|
| R4-001 | `ffi_analysis.zig:259` | deallocator 检测中 operand 索引错误 | `LLVMGetOperand(inst, 1)` → `LLVMGetOperand(inst, 0)` |
| R4-002 | `call_graph.zig:126` | 间接调用解析中的 off-by-one 错误 | 复杂公式 → `@as(c_uint, @intCast(i))` |
| R4-003 | `memory_pool.zig:169-181` | arena 分配器缺少对齐 | 添加 `alignForward` + offset 计算 |
| NEW-001 | `taint.zig:190,275` | callee 检测错误 | `LLVMGetOperand(inst, 0)` → `LLVMGetCalledValue(inst)` |
| NEW-002 | `lock.zig:161` | callee 检测错误 | `LLVMGetOperand(inst, 0)` → `LLVMGetCalledValue(inst)` |
| NEW-003 | `lock.zig:234` | lock 对象参数错误 | `LLVMGetOperand(inst, 1)` → `LLVMGetOperand(inst, 0)` |

#### 中严重度 (4 个)

| Bug ID | 文件 | 问题 | 修复 |
|--------|------|------|------|
| R4-004 | `formatter.zig:228,230` | SARIF 输出未转义 | 添加 `writeEscapedString()` |
| R4-005 | `main.zig:272-287` | JSON 输出未转义 | 添加 `writeJsonEscaped()` 函数 |
| R4-006 | `ci_integration.zig:315` | 二进制名称拼写错误 | `OmniSope` → `OmniScope` |
| R4-009 | `fact/query.zig:29-109` | 查询方法中的数据竞争 | 添加 mutex 锁 |

#### 低严重度 (2 个)

| Bug ID | 文件 | 问题 | 修复 |
|--------|------|------|------|
| R4-007 | `main.zig:175` | 时间戳可能为负值 | 添加 `@max(0, elapsed)` |
| R4-008 | `security-analysis.yml:62` | 命令注入风险 | `find -print0 \| xargs -0` |

### 影响分析 / Impact Analysis

- **taint.zig / lock.zig 修复**: 污点源/汇检测和锁分析在此修复前完全失效
- **ffi_analysis.zig 修复**: 双重释放检测和所有权不匹配检测现在正常工作
- **call_graph.zig 修复**: 间接调用解析现在正确映射参数

---

### 🎉 新增 — Phase 4: 跨语言噪音过滤引擎 / Phase 4: Cross-Language Noise Reduction Engine

**OmniScope 史上最大单次改进。**

#### 核心功能 / Core Features

- **三层噪音过滤系统** ([noise_reduction.zig](src/pass/analysis/noise_reduction.zig))
  - Layer 1: 基于名称过滤（120+ Rust/Zig/C++ 模式）
  - Layer 2: 基于路径/调试元数据过滤（LLVM DebugInfo API 集成）
  - Layer 3: 基于行为过滤（drop glue / allocator wrapper / STL grow 检测）

- **FunctionOrigin 分类系统 / FunctionOrigin Classification System**
  - 新枚举：`user`, `stdlib`, `compiler_generated`, `third_party`, `unknown`
  - RiskWeight 系统结合来源 + 严重度（critical/high/medium/low/ignored）

- **归因分组输出 / Attribution Summary Output**
  - 单行格式：`"X 问题 → Y 用户代码 (Z FFI HIGH)"`
  - 带来源图标的分类明细（✅📦📚🔧❓）

#### Zig FFI 支持增强 / Zig FFI Support Enhancement

- **`isZigInternalFunction()`** — 40+ 安全内部函数模式
- **`isZigSafeCImport()`** — 20+ 已知安全的 libc 绑定
- **`isZigFFIWorthReporting()`** — 综合风险评估
- 扩展模式库：debug.Dwarf.*, posix.*, fs.File.*, OS 抽象层

#### LLVM 集成 / LLVM Integration

- 在 [llvm_raw.zig](src/ir/llvm_raw.zig) 中添加 `@cInclude("llvm-c/DebugInfo.h")`
- 新增 `extractDebugFilePath()` 函数用于精确源码检测
- 安全内存访问，带边界检查和空终止符验证

#### 测试基础设施 / Test Infrastructure

- 三个新 Zig FFI 测试项目：
  - [zig_video_test.zig](corpus/test_cases/zig/zig_video_test.zig) — 视频处理库模拟
  - [zgui_test.zig](corpus/test_cases/zig/zgui_test.zig) — GUI 库模拟
  - [mach_core_test.zig](corpus/test_cases/zig/mach_core_test.zig) — 游戏引擎模拟
- 完整双语测试报告：[ZIG_FFI_TEST_REPORT.md](corpus/test_cases/ZIG_FFI_TEST_REPORT.md)

### 性能影响 / Performance Impact

| 项目 / Project | 之前 / Before | 之后 / After | 降低率 / Reduction |
|---------------|---------------|--------------|-------------------|
| wasmtime (Rust) | 297 | **9** | **-97%** |
| zig_video (Zig) | 194 | **50** | **-74%** |
| zgui (Zig) | 168 | **24** | **-86%** |
| mach_core (Zig) | 211 | **67** | **-68%** |

### 修改 / Changed

- [BASELINE.md](corpus/real_world/BASELINE.md) 更新到 v0.1.5
- [README.md](README.md) 更新 v0.1.5 亮点
- 创建 [RELEASE_NOTES.md](RELEASE_NOTES.md) 详细发布文档

### 修复 / Fixed

- 修复 `indexOfPath()` 中潜在缓冲区超读，带正确边界检查
- 修复 `extractDebugFilePath()` 中空指针解引用风险，带验证

---

## \[0.4.0] - 2026-04-24（内部发布 / Internal Release）

### 新增 / Added — Phase 4 初始实现

- 三层噪音过滤架构初始设计
- FunctionOrigin 和 RiskWeight 类型定义
- Rust 标准库函数基础名称过滤
- 首次成功测试：wasmtime 297 → 9 问题

*注：这是内部开发里程碑，未公开发布。合并到 v0.1.5 增强版。*

---

## \[0.3.3] - 2026-04-24

### 新增 / Added — Phase 3 完成

- **跨语言类型兼容性** ([ffi_boundary.zig](src/pass/analysis/ffi_boundary.zig))
  - FFI 边界处的指针/整数混淆检测
  - 整数大小不匹配警告（i32 vs i64 ABI 问题）

- **生命周期推断** ([ffi_boundary.zig](src/pass/analysis/ffi_boundary.zig))
  - 返回值生命周期分类（static/owned/borrowed）
  - 悬空指针检测（alloca 传给 FFI）
  - 参数生命周期验证（NULL 安全，inttoptr 风险）

- **Rust Drop Glue 过滤器** ([cpp_fp_reduction.zig](src/pass/analysis/cpp_fp_reduction.zig))
  - `isRustDropGlue()` 消除析构函数 UAF 报告
  - 覆盖 mangled 形式：`_ZN4core3ptr13drop_in_place` 等

### 修改 / Changed

- BASELINE.md 更新到 v0.1.5
- wasmtime: 355 → 297 问题（-16%，来自 drop_in_place 过滤）

---

## \[0.3.1] - 2026-04-23

### 新增 / Added — P1 Phase 2 完成

- **API 契约验证** — NULL guard 检查、无界缓冲区警告、所有权链跟踪
- **Sink 上下文敏感度** — fprintf/sprintf 安全调用者过滤
- **污染源增强** — 从 15 扩展到 35+ 污染源
- **SQLite IR 重新编译** — 43MB / 753K 行 / 3346 函数

---

## \[0.3.0] - 2026-04-23

### 新增 / Added — P0 里程碑完成

- **BB 感知双重释放检测** — 同一 BB = 真实 bug，不同 BB = 多路径清理
- **Rust FFI 相关性过滤器** — `isRustFFIRelevantFunction()`

---

## \[0.2.1] - 2026-04-23

### 新增 / Added — TP/FP 分离

- 源码级验证框架
- Mangled 名称过滤器
- Red Team 测试套件：17 个故意注入的 bug

---

## \[0.2.0] - 2026-04-23

### 新增 / Added — 增强检测能力

- BFS 别名分析的 Double-Free 检测
- 循环泄漏检测启发式（≥3 次分配无释放）
- 格式化字符串漏洞分类
- exec* 家族覆盖（12 个危险函数）

---

## \[0.1.5] - 2026-04-22

### 安全审计修复

- 修复 30+ 个内部审计发现的 bug
- 将子字符串匹配改为精确匹配

---

## \[0.1.4] - 2026-04-22

### 新增 / Added — Phase 3 优化

- 所有权转移推断
- 空 guard 支配性分析
- C++ RAII 感知改进

---

## 版本历史摘要 / Version History Summary

| 版本 / Version | 日期 / Date | 主要功能 / Major Feature | 关键指标 / Key Metric |
|---------------|------------|------------------------|----------------------|
| **v0.1.5** | 2026-04-24 | **Phase 4 噪音过滤** | wasmtime: **9** (-99.8%) |
| v0.1.5 | 2026-04-24 | Phase 3 完成 | wasmtime: 297 |
| v0.1.5 | 2026-04-23 | P1 Phase 2 | wasmtime: 297 |
| v0.1.5 | 2026-04-23 | P0 里程碑 | wasmtime: 355 |
| v0.1.5 | 2026-04-23 | TP/FP 分离 | wasmtime: 357 |
| v0.1.5 | 2026-04-23 | 增强检测 | wasmtime: 4023 |

---

*[CHANGELOG]: https://keepachangelog.com/en/1.0.0/*
*[语义化版本]: https://semver.org/spec/v2.0.0.html*
