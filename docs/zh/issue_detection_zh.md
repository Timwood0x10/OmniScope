# 问题检测 (Issue Detection)

## 概述

OmniScope 通过多层分析检测 14 种安全和内存问题。每个问题都包含**置信度等级**和**原因**字段，便于分类处理。

## IssueKind 分类 (v0.1.5)

| IssueKind | 严重程度 | CWE | 置信度 | 描述 |
|-----------|----------|-----|--------|------|
| `memory_leak` | HIGH | 401 | 0.70-0.85 | 分配后无匹配的释放 |
| `use_after_free` | CRITICAL | 416 | 0.80-0.90 | 释放后使用指针 |
| `double_free` | CRITICAL | 415 | 0.85-0.95 | 同一指针释放两次 |
| `invalid_free` | HIGH | 590 | 0.80-0.90 | free() 非堆指针 |
| `borrow_escape` | HIGH | 704 | 0.75-0.85 | as_ptr 结果在 drop 后可能失效 |
| `cross_language_leak` | HIGH | 401 | 0.80-0.90 | Rust 分配被 C free() 释放 |
| `ffi_unsafe_call` | HIGH | 686 | 0.65-0.80 | FFI 调用无验证 |
| `unchecked_return` | MEDIUM | 253 | 0.70-0.80 | 返回值未检查 |
| `type_mismatch` | MEDIUM | 704 | 0.65-0.75 | FFI 类型不匹配 |
| `null_dereference` | CRITICAL | 476 | 0.85 | 可空分配未检查直接使用 |
| `command_injection` | CRITICAL | 78 | 0.75-0.90 | 不可信输入到 shell |
| `format_string` | CRITICAL | 134 | 0.85-0.95 | 用户输入到格式化字符串 |
| `buffer_overflow` | CRITICAL | 119 | 0.75-0.90 | 缓冲区边界违规 |
| `malloc_unchecked` | MEDIUM | 190 | 0.70-0.80 | malloc 结果未检查 |

## 置信度系统

每个问题分配四个置信度等级之一：

| 等级 | 分数范围 | 操作 |
|------|----------|------|
| **HIGH** | ≥ 0.90 | 立即修复 |
| **MEDIUM** | ≥ 0.70 | 需要审查 |
| **HEURISTIC** | ≥ 0.50 | 调查 |
| **EXPERIMENTAL** | < 0.50 | 仅研究 |

## 检测层次

### 层次 1-3: 核心所有权跟踪

位于 `src/pass/analysis/pointer_ownership.zig` (936 行)

- 构建 `alloc_map` (所有分配)
- 构建 `free_map` (所有释放)
- 构建 `flow_graph` (通过 SSA 的可达性)
- 所有权转移检测 (返回值 / 输出参数)

### 层次 4-8: C++ 误报减少

位于 `src/pass/analysis/cpp_fp_reduction.zig` (937 行)

| 层次 | 过滤器 | 消除 |
|------|--------|------|
| L1 | STL 内部 | `_ZSt*`, `std::*` |
| L2 | 特殊成员 | ctor/dtor/copy/move |
| L3 | RAII | unique_ptr/shared_ptr 作用域 |
| L4 | C++ ABI | `_Znwm`, `_ZdlPv`, `_ZdaPv` |
| L5 | 运算符重载 | `operator*`, `operator->` |
| L6 | Meyers 单例 | 静态局部 + 双重检查 |
| L7 | RC 容器 | Ref/Unref/AddRef/Release |
| L8 | Rust FFI 配对 | into_raw/from_raw |

### 层次 9: Rust FFI 审计器

位于 `src/pass/analysis/rust_ffi_auditor.zig` (464 行)

| 规则 | 问题 | 模式 |
|------|------|------|
| R1 | `unpaired_into_raw` | `Box::into_raw()` 无匹配的 `from_raw()` |
| R2 | `borrow_escape` | `as_ptr()` 在局部变量上传递给 FFI |
| R3 | `cross_lang_alloc_mismatch` | `_Znwm` → C `free()` |
| R4 | `unsafe_ffi_call` | `extern "C"` 无验证 |
| R5 | `extern_c_type_mismatch` | extern 声明中的类型不匹配 |
| R6 | `no_mangle_export` | `#[no_mangle]` 无所有权 |

## 输出格式

### 文本 (默认)

```
VULNERABILITY OMI-001 [high] [Confidence: medium]
Type: borrow_escape
Reason: as_ptr() on local String/Vec passed to extern C - may dangle after drop
```

### JSON (稳定 Schema v1)

```json
{
  "id": "OMI-001",
  "kind": "borrow_escape",
  "severity": "high",
  "confidence": "MEDIUM",
  "confidence_score": 0.80,
  "cwe_id": 704,
  "reason": "as_ptr() on local String/Vec passed to extern C",
  "message": "Potential as_ptr borrow escape",
  "location": {"function": "leak_cstring"}
}
```

### SARIF v2.1.0

```json
{
  "ruleId": "borrow_escape",
  "level": "error",
  "message": {
    "text": "Potential as_ptr borrow escape"
  },
  "properties": {
    "confidence": 0.80,
    "confidenceLevel": "MEDIUM",
    "reason": "as_ptr() on local String/Vec passed to extern C",
    "cwe": "CWE-704"
  }
}
```

## 基线结果

| 项目 | 问题数 | 泄漏数 | FFI 风险 | 置信度 |
|------|--------|--------|----------|--------|
| SQLite 3.47.2 | 8 | 0 | 2 | MEDIUM |
| ripgrep 14.1.1 | **0** | 0 | 0 | — |
| rust_sqlite | 6 | 4 | 2 | MEDIUM |
| jsoncpp 1.9.5 | 3 | 0 | 0 | HIGH |

---

**最后更新**: 2026-04-23
**版本**: v0.1.5
