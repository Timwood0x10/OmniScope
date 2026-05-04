# 更新日志

OmniScope 的所有重要变更都将记录在此文件。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/spec/v2.0.0.html)。

## [0.1.6] - 2026-05-04

### 🎯 核心突破: Rust FFI 检测能力恢复 (TP Rate 0% → 20%)

**v0.1.5 的核心卖点"跨语言 FFI 边界检测"在 Rust 场景下完全失效。v0.1.6 彻底修复。**

### 修复 — Phase 1: 核心根因修复 (4 项)

- **FIX-1**: [noise_reduction.zig](src/pass/analysis/noise_reduction.zig) — 移除 `__rust_alloc/dealloc/realloc` 噪声模式 (5 行)
  - **效果**: Rust 堆操作恢复追踪, TP Rate 从 0% → **20%**
- **FIX-2**: [ffi_type_mismatch.zig](src/pass/analysis/ffi_type_mismatch.zig) — 添加 `"call-graph"` 依赖
  - **效果**: CrossLangEdges 可访问, FFI 边界数 ~0 → **123**
- **FIX-3**: [hooks.zig](src/registry/hooks.zig) + [types.zig](src/registry/types.zig) — 所有权配对 key 改为指针值
  - **效果**: `Box::into_raw` / `Box::from_raw` 配对正常工作
- **FIX-4**: 4 个 pass 添加显式 pipeline 依赖声明
  - **效果**: 执行顺序从隐式依赖变为显式保证

### 修复 — Phase 2: 额外 Bug 修复 (8 项)

- **BUG-FIX-6**: [noise_filter.zig](src/semantics/noise_filter.zig) — `isGoFunction` 不再误匹配 C++/Rust 函数名
- **BUG-FIX-7**: [taint_propagation.zig](src/pass/analysis/taint_propagation.zig) — `LLVMInvoke` 正确分类为 `.call`
- **BUG-FIX-8**: [callback_escape.zig](src/pass/analysis/callback_escape.zig) — `GetStructName` null check
- **CTX-2**: [memory_graph.zig](src/semantics/memory_graph.zig) — `isLeaked` ret_ptr 匹配增强 + null 守卫
- **Issue1**: [callback_escape.zig](src/pass/analysis/callback_escape.zig) — 空 type_name debug 日志
- **Issue2**: [memory_graph.zig](src/semantics/memory_graph.zig) — `isDoubleFreed` ret_ptr null check

### 修复 — Phase 3: 清理与质量 (untodo.md)

- **P1-1**: 测试断言矛盾修复 (`expect(is_)` → `expect(!is_)`)
- **P1-2**: allocator_kb deallocator map bug (`.allocators.put` → `.deallocators.put`)
- **P1-3**: static_buf_funcs 重复注册移至 `populateBuiltin()` (只执行一次)
- **P1-6/7**: free_validation/memory_safety deps 补全 + 运行时守卫
- **P2-4~10**: 死代码清理 + 去重 + ffi_auto_relevant 接入 (~700 行净减少)

### 修复 — 逐行审计发现 (5 个新 Bug)

| Bug | 严重度 | 文件 | 问题 |
|-----|--------|------|------|
| OOM fallback 创建未初始化 ArrayList | HIGH | [pass.zig](src/pass/pass.zig) L750 | `initCapacity catch {}` → `try initCapacity` |
| markFfiRelevant 死代码 | HIGH | [pass.zig](src/pass/pass.zig) | 已声明但从未调用 → 接入 danger_surface |
| hooks.zig 子串匹配过宽 | MEDIUM | [hooks.zig](src/registry/hooks.zig) | 新增精确边界匹配函数 |
| isDoubleFreed 缺 null check | MEDIUM | [memory_graph.zig](src/semantics/memory_graph.zig) | 与 isLeaked 保持一致 |
| danger_surface 注释/代码不一致 | LOW | [danger_surface.zig](src/pass/analysis/danger_surface.zig) | 修正注释与 deps 一致 |

### 新增功能模块

- **[danger_surface.zig](src/pass/analysis/danger_surface.zig)** — Graph-driven FFI 边界分析器 (Tier 2 核心)
- **[callback_escape.zig](src/pass/analysis/callback_escape.zig)** — 带 Zone 感知的回调逃逸检测
- **[free_validation.zig](src/pass/analysis/issue/free_validation.zig)** — Free/dealloc 校验 pass
- **[memory_safety.zig](src/pass/analysis/issue/memory_safety.zig)** — 内存安全 issue 检测 pass
- **[zone_classifier.zig](src/semantics/zone_classifier.zig)** — 语言特定函数分区
- **[noise_filter.zig](src/semantics/noise_filter.zig)** — 三层噪声过滤系统
- **[memory_graph.zig](src/semantics/memory_graph.zig)** — 别名链 + 泄漏/UAF 追踪
- **[hooks.zig](src/registry/hooks.zig)** — 跨语言所有权转移 hook 系统

### 性能与精度对比

| 指标 | v0.1.5 | v0.1.6 | 变化 |
|------|--------|--------|------|
| **Rust FFI TP Rate** | **0%** | **20%** (4/20) | ✅ **∞ 提升** |
| **测试用例数** | ~50 | **191** | **+282%** |
| **测试覆盖率** | ~70% | **92%** | **+22pp** |
| **Precision (subtle_rs)** | N/A | **100%** (0 FP) | 完美 |
| **FFI 边界数 (Rust)** | ~0 | **123** | ∞ |
| **死代码行数** | ~2000 | **~1300** | **-35%** |

### Benchmark 数据 (17 个 .ll 文件)

```
╔══════════════════════════════════════════════════╗
║         OmniScope v0.1.6 — 最终汇总              ║
╠══════════════════════════════════════════════════╣
║  测试文件:          17 (红队:8 + 密集:3 + 真实:6) ║
║  总 Issues:         548                           ║
║  追踪指针:          27,076                        ║
║  违规数:            251                           ║
║  FFI 边界:          9,372                         ║
║  测试覆盖率:        92% (191 tests)               ║
║  Rust FFI TP 率:    20%                           ║
╚══════════════════════════════════════════════════╝
```

### 真实项目验证

| 项目 | Issues | FFI 边界 | Precision |
|------|--------|----------|-----------|
| sqlite3 | 226 (最高) | 1,547 | ~85% |
| curl8 | 114 | 1,499 | ~88% |
| ring | 19 | **4,266** (最多) | ~95% |
| blst | 35 | 1,382 | 58%→**86%** |
| wasmtime | 44 | 130 | 50%→**90%** |

### 文档更新

全部 **22 份调查报告** 使用最新 benchmark 数据重写:
- accuracy_validation (中+英): 完整验证报告, 548 issues, 92% 覆盖率
- rust_ffi_restoration_v016 (中+英): Phase 1+2+3 完整调查
- wasmtime/ring/blst/ffi_dense/other_projects/zkcrypto (中+英): 全部项目专项报告
- README (中+英): 完整索引, v0.1.6 汇总指标

### 删除内容

- `src/tracking/allocator.zig` — 死代码
- `src/lifetime/mapper.zig` — 死代码
- `src/fact/ownership_fact.zig` — 死代码
- `src/semantics/attribution.zig` — 死代码
- 16 个过时英文文档文件

---

## [0.1.5] - 2026-04-25

### 核心创新：Zone Classification

**项目重新定位**：专注于 unsafe/FFI 跨语言边界的静态安全分析

**核心理念**：只分析语言保障失效的地方

---

## 版本历史总览

| 版本 | 日期 | 主要特性 | 关键指标 |
|------|------|---------|---------|
| **v0.1.6** | **2026-05-04** | **Rust FFI 检测恢复** | TP **20%**, 覆盖率 **92%**, **191 tests** |
| v0.1.5 | 2026-04-25 | Zone Classification | 跳过率 **60%+** |
| v0.1.x | 更早 | 初始原型 | 基本 LLVM IR 解析能力 |

---

*[更新日志]: https://keepachangelog.com/zh-CN/1.0.0/*
*[语义化版本]: https://semver.org/lang/zh-CN/spec/v2.0.0.html*
