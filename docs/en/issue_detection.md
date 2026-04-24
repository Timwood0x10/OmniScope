# Issue Detection

## Overview

OmniScope detects 14 types of security and memory safety issues through multi-layer analysis. Every issue includes a **Confidence Level** and **Reason** field for triage.

## IssueKind Taxonomy (v0.1.5)

| IssueKind | Severity | CWE | Confidence | Description |
|-----------|----------|-----|------------|-------------|
| `memory_leak` | HIGH | 401 | 0.70-0.85 | Allocation without matching free |
| `use_after_free` | CRITICAL | 416 | 0.80-0.90 | Pointer used after deallocation |
| `double_free` | CRITICAL | 415 | 0.85-0.95 | Same pointer freed twice |
| `invalid_free` | HIGH | 590 | 0.80-0.90 | free() on non-heap pointer |
| `borrow_escape` | HIGH | 704 | 0.75-0.85 | as_ptr result may dangle after drop |
| `cross_language_leak` | HIGH | 401 | 0.80-0.90 | Rust-alloc freed by C free() |
| `ffi_unsafe_call` | HIGH | 686 | 0.65-0.80 | FFI call without validation |
| `unchecked_return` | MEDIUM | 253 | 0.70-0.80 | Return value not checked |
| `type_mismatch` | MEDIUM | 704 | 0.65-0.75 | FFI type mismatch |
| `null_dereference` | CRITICAL | 476 | 0.85 | Nullable allocation used without guard |
| `command_injection` | CRITICAL | 78 | 0.75-0.90 | Untrusted input to shell |
| `format_string` | CRITICAL | 134 | 0.85-0.95 | User input to format string |
| `buffer_overflow` | CRITICAL | 119 | 0.75-0.90 | Buffer boundary violation |
| `malloc_unchecked` | MEDIUM | 190 | 0.70-0.80 | malloc result not checked |

## Confidence System

Every issue is assigned one of four confidence levels:

| Level | Score Range | Action |
|-------|------------|--------|
| **HIGH** | ≥ 0.90 | Fix immediately |
| **MEDIUM** | ≥ 0.70 | Review required |
| **HEURISTIC** | ≥ 0.50 | Investigate |
| **EXPERIMENTAL** | < 0.50 | Research only |

### Confidence Assignment Examples

```zig
// HIGH confidence: Direct pattern match with full context
Issue.initWithReason(
    .double_free,
    "Double free detected",
    location,
    .critical,
    0.95,
    "Same pointer freed twice in same function with no intervening allocation",
)

// MEDIUM confidence: Heuristic match
Issue.initWithReason(
    .ffi_unsafe_call,
    "Unsafe FFI call detected",
    location,
    .high,
    0.75,
    "extern \"C\" function called with potentially untrusted pointer",
)
```

## Detection Layers

### Layer 1-3: Core Ownership Tracking

Located in `src/pass/analysis/pointer_ownership.zig` (936 lines)

- Build `alloc_map` (all allocations)
- Build `free_map` (all deallocations)
- Build `flow_graph` (reachability via SSA)
- Ownership transfer detection (return-value / output-param)

### Layer 4-8: C++ False Positive Reduction

Located in `src/pass/analysis/cpp_fp_reduction.zig` (937 lines)

| Layer | Filter | Eliminates |
|-------|--------|------------|
| L1 | STL internal | `_ZSt*`, `std::*` |
| L2 | Special members | ctor/dtor/copy/move |
| L3 | RAII | unique_ptr/shared_ptr scope |
| L4 | C++ ABI | `_Znwm`, `_ZdlPv`, `_ZdaPv` |
| L5 | Operator overload | `operator*`, `operator->` |
| L6 | Meyers singleton | Static local + double-check |
| L7 | RC containers | Ref/Unref/AddRef/Release |
| L8 | Rust FFI pairing | into_raw/from_raw |

### Layer 9: Rust FFI Auditor

Located in `src/pass/analysis/rust_ffi_auditor.zig` (464 lines)

| Rule | Issue | Pattern |
|------|-------|---------|
| R1 | `unpaired_into_raw` | `Box::into_raw()` without matching `from_raw()` |
| R2 | `borrow_escape` | `as_ptr()` on local passed to FFI |
| R3 | `cross_lang_alloc_mismatch` | `_Znwm` → C `free()` |
| R4 | `unsafe_ffi_call` | `extern "C"` without validation |
| R5 | `extern_c_type_mismatch` | Type mismatch in extern decl |
| R6 | `no_mangle_export` | `#[no_mangle]` without ownership |

## Output Formats

### Text (Default)
```
VULNERABILITY OMI-001 [high] [Confidence: medium]
Type: borrow_escape
Reason: as_ptr() on local String/Vec passed to extern C - may dangle after drop
```

### JSON (Stable Schema v1)
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

## Baseline Results (v0.1.5)

| Project | Issues | TP | FP Rate | Notes |
|---------|--------|-----|---------|-------|
| SQLite 3.47.2 | **0** | 0 | 0% | ✅ Clean |
| libcurl 8.14.0 | **0** | 0 | 0% | ✅ Clean |
| libuv 1.50.0 | **3** | 0 | 0% | ✅ INFO only |
| abseil-cpp | **0** | 0 | 0% | ✅ Clean |
| ripgrep 14.1.1 | **0** | 0 | 0% | ✅ Clean |
| wasmtime (Rust) | **9** | ~7 | ~22% | ✅ Real FFI only |
| rust_sqlite | **88** | ~8 | ~91% | Mixed |
| Red Team | **5** | 5 | 0% | ✅ 29% hit rate |

**Note**: Phase 4 Noise Reduction Engine reduced Rust FP rate from 98% to ~22%.

---

**Last Updated**: 2026-04-24
**Version**: v0.1.5
