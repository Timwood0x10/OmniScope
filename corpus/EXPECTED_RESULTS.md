# OmniScope Expected Results (Corpus Benchmark)
#
# This file defines the expected detection results for each corpus test file.
# Used by scripts/benchmark.sh to calculate precision/recall.
#
# Format: ## filename → expected issue counts by severity
#
# Updated: 2026-05-24 (P0-P6 implementation complete)

## red_team_test/go_tinygo_ffi_bugs.bc
- **Total**: 7
- **CRITICAL**: 0
- **HIGH**: 7
  - cross_language_free: 2 (TC7, TC8)
  - invalid_free: 3 (TC2, TC4, TC8)
  - null_dereference: 2 (TC2, TC6, TC7)
- **MEDIUM**: 0
- **LOW**: 0

## red_team_test/csharp_win32_ffi_bugs.bc
- **Total**: 5
- **CRITICAL**: 0
- **HIGH**: 3
  - cross_language_free: 2 (TC1, TC2)
  - invalid_free: 1 (TC4)
- **MEDIUM**: 2
  - memory_leak: 1 (TC6)
  - other: 1 (TC7 partial)
- **LOW**: 0

## red_team_test/zig_cimport_ffi_bugs.bc
- **Total**: 9
- **CRITICAL**: 0
- **HIGH**: 6
  - cross_language_free: 4 (TC1, TC2, TC3, TC4)
  - invalid_free: 2 (TC7 mixed)
- **MEDIUM**: 2
  - memory_leak: 1 (TC6 arena)
  - other: 1 (TC7 partial)
- **LOW**: 1
  - safe_pattern: 1 (TC5 - should be no issue)

## red_team_test/cpp_operator_new_ffi_bugs.bc
- **Total**: 4
- **CRITICAL**: 0
- **HIGH**: 3
  - invalid_free: 3 (TC1, TC3, TC4 - new/delete mismatch)
- **MEDIUM**: 1
  - memory_leak: 1 (TC6 internal leak)
- **LOW**: 0

## red_team_test/rust_multi_lang_ffi_bugs.bc
- **Total**: 20
- **CRITICAL**: 2
  - cross_language_free: 2 (TC3 Rust→C#, TC4 C#→Rust)
- **HIGH**: 9
  - cross_language_free: 5 (TC1, TC2, TC7×3)
  - invalid_free: 2 (TC7 mixed)
  - other: 2
- **MEDIUM**: 5
  - memory_leak: 2
  - other: 3
- **LOW**: 4
  - safe_pattern: 2 (TC5, TC6 ownership transfer)
  - other: 2

## red_team_test/go_cgo_bugs.ll
- **Total**: 9
- **CRITICAL**: 0
- **HIGH**: 3
  - cross_language_free: 3 (C alloc → Go free)
- **MEDIUM**: 4
  - callback_ownership_risk: 1
  - write_to_immutable: 1
  - malloc_unchecked: 1
  - other: 1
- **LOW**: 2
  - null_dereference: 1
  - other: 1

## red_team_test/csharp_ffi_bugs.ll
- **Total**: 2
- **CRITICAL**: 0
- **HIGH**: 1
  - cross_language_free: 1 (C alloc → C# free)
- **MEDIUM**: 1
  - memory_leak: 1
- **LOW**: 0

## red_team_test/rust_ffi_bugs.ll
- **Total**: 12
- **CRITICAL**: 2
  - use_after_free: 1
  - double_free: 1
- **HIGH**: 5
  - buffer_overflow: 1
  - cross_language_free: 2
  - other: 2
- **MEDIUM**: 3
  - memory_leak: 2
  - other: 1
- **LOW**: 2

## red_team_test/cross_lang_free_bugs.ll
- **Total**: 9
- **CRITICAL**: 2
  - cross_language_free: 2 (Rust→C, C→Rust)
- **HIGH**: 4
  - cross_language_free: 2 (Zig↔C)
  - other: 2
- **MEDIUM**: 2
  - callback_ownership_risk: 1
  - other: 1
- **LOW**: 1

---
# FFI-Dense Corpus (Integration Tests)

## ffi-dense/sqlite_binding.c
- **Total**: 6
- **CRITICAL**: 2
- **HIGH**: 3
- **MEDIUM**: 1

## ffi-dense/openssl_wrapper.c
- **Total**: 10
- **CRITICAL**: 0
- **HIGH**: 7
- **MEDIUM**: 3

## ffi-dense/zlib_binding.c
- **Total**: 10
- **CRITICAL**: 3
- **HIGH**: 1
- **MEDIUM**: 5
- **LOW**: 1

---
# Summary Statistics

| Category | Files | Total Issues | CRITICAL | HIGH | MEDIUM | LOW |
|----------|-------|-------------|----------|------|--------|-----|
| P0-P6 New Tests | 5 | 45 | 2 | 28 | 10 | 5 |
| Existing Red Team | 4 | 32 | 4 | 13 | 11 | 4 |
| FFI-Dense Integration | 3 | 26 | 5 | 11 | 9 | 1 |
| **TOTAL** | **12** | **103** | **11** | **52** | **30** | **10** |

### Detection Rate Targets
- **Precision**: ≥ 95% (minimize false positives)
- **Recall**: ≥ 90% (catch known bugs)
- **F1 Score**: ≥ 92%
