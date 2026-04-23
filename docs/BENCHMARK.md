# OmniScope Benchmark Specification

## Version: 1.0
## Last Updated: 2026-04-21

***

## Table of Contents

1. [Overview](#overview)
2. [Test Environment](#test-environment)
3. [False Positive Policy](#false-positive-policy)
4. [Test Dataset Sources](#test-dataset-sources)
5. [Known vs Unknown Function](#known-vs-unknown-function)
6. [Correct Detection Standard](#correct-detection-standard)
7. [Performance Targets](#performance-targets)
8. [Metric Definitions](#metric-definitions)
9. [Benchmark Categories](#benchmark-categories)
10. [CI Integration](#ci-integration)

***

## Overview

This document defines the benchmark conditions, dataset sources, and evaluation criteria for OmniScope's static analysis capabilities.

OmniScope is a cross-language FFI/unsafe boundary analyzer built on LLVM IR. It detects ownership violations, memory safety issues, and semantic mismatches across C, Rust, C++, Go, Zig, and Swift boundaries.

**Core Analysis Capabilities:**

| Capability | Description |
|------------|-------------|
| Ownership Tracking | alloc/free/transfer/reclaim lifecycle |
| Cross-Language Detection | Mismatched alloc/free across language boundaries |
| Null Check Guard | Path-sensitive null/non-null propagation |
| Points-To Analysis | Steensgaard flow-insensitive alias analysis |
| Type-Based Devirtualization | Indirect call resolution via signature matching |
| Semantic Registry | 131 functions across 6 language layers |

***

## Test Environment

### Hardware Baseline

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 2 cores, 2.0 GHz | 4+ cores, 3.0+ GHz |
| RAM | 4 GB | 8+ GB |
| Disk | SSD (any) | NVMe preferred |

### Software Requirements

| Component | Version |
|-----------|---------|
| Zig | 0.13.0+ |
| LLVM/Clang | 22.x |
| Operating System | macOS / Linux / Windows (via WSL2) |

### Build Configuration

```bash
# Benchmark must use ReleaseFast optimization
zig build bench-perf -Doptimize=ReleaseFast

# Unit/integration tests use Debug mode
zig build test-all
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `OMNISCOPE_BENCH_ITERATIONS` | Override benchmark iteration count | auto-scaled |
| `OMNISCOPE_BENCH_WARMUP` | Warmup iterations before measurement | 10 |
| `OMNISCOPE_CORPUS_PATH` | Custom corpus directory | `corpus/` |

***

## False Positive Policy

### Principle: Zero Tolerance for False Positives on Known Patterns

OmniScope adopts a **conservative reporting strategy**: it is acceptable to miss real issues (false negatives), but unacceptable to report non-existent issues (false positives) on well-defined test patterns.

### Definition of False Positive

A **false positive** occurs when OmniScope reports an issue that does not exist according to the ground truth defined in `corpus/EXPECTED_RESULTS.md`.

**Ground Truth Authority:** Each test file in `corpus/` has a corresponding entry in `EXPECTED_RESULTS.md` listing all expected issues with:
- Function name
- Issue type
- Severity level
- Human-verified description

### False Positive Rate Target

| Metric | Target | Rationale |
|--------|--------|-----------|
| FP Rate (known patterns) | **0%** | Every reported issue must be verifiable |
| FN Rate (known patterns) | < 5% | Acceptable to miss edge cases |
| FP Rate (unknown code) | N/A | Conservative mode minimizes FPs by design |

### False Positive Classification

| Category | Handling | Example |
|----------|----------|---------|
| **True Positive** | Correctly detected | `malloc` without `free` → leak |
| **False Positive** | Must be fixed | Reporting leak when `free` exists in same function |
| **False Negative** | Acceptable (< 5%) | Missing leak across complex control flow |
| **Benign Report** | Document as expected | Warning on defensive null check patterns |

### How to Handle Disputed Reports

If a detection is disputed:
1. Check if the pattern matches a known benign idiom (e.g., RAII, arena allocators)
2. Verify against `EXPECTED_RESULTS.md` ground truth
3. If truly a false positive, fix the analysis pass
4. If the test case is ambiguous, update `EXPECTED_RESULTS.md` with rationale

***

## Analysis Scope

### Critical: OmniScope is NOT a General-Purpose Bug Finder

OmniScope is an **FFI/Unsafe Boundary Analyzer** focused on cross-language memory safety issues.
It is **not** designed to detect buffer overflows, format string vulnerabilities, cryptographic weaknesses, or general logic errors.

### Why Scope Matters for Benchmark Metrics

Consider a real-world codebase with **1000 bugs total**:
- 980 are generic bugs (logic errors, typos, API misuse)
- 20 are FFI/unsafe/memory-safety bugs (leaks, UAF, double-free, cross-lang mismatch)

If OmniScope detects 15 of those 20 FFI bugs and reports 0 false positives:

| Calculation Method | Precision | Recall | F1 | Meaning |
|--------------------|-----------|--------|-----|---------|
| ❌ Against ALL 1000 bugs | 1.5% (15/1000) | 1.5% | 1.5% | **Misleading — looks useless** |
| ✅ Against 20 FFI bugs only | **100%** (15/15) | **75%** (15/20) | **85.7%** | **Accurate — reflects actual capability** |

**OmniScope benchmark metrics are calculated ONLY against in-scope issues.**

### In-Scope Issue Types (What OmniScope Detects)

| Category | Detection Mechanism | Example |
|----------|---------------------|---------|
| **leak** | Ownership tracking: alloc without free/reclaim | `malloc` without `free`, `sqlite3_open` without `close` |
| **cross_lang_free_mismatch** | Cross-language ownership violation | Rust `Box::into_raw` freed by C `free`, C++ `new` freed by C `free` |
| **use_after_free** | Lifetime state lattice + null check guards | Using pointer after `free()` / `sqlite3_finalize()` |
| **double_free** | Resource ID deduplication + lifetime tracking | Calling `free()` twice on same pointer |
| **borrow_escape** | FFI boundary escape analysis | `&str.as_ptr()` returned across FFI boundary without lifetime guarantee |
| **null_dereference** | Null check guard recognition + CFG propagation | Dereferencing pointer that could be NULL at FFI boundary |
| **dangling_pointer** | Post-free pointer usage detection | Returning pointer invalidated by cleanup operation |

**Total In-Scope Issues in Corpus: 115 out of 136 (84.6%)**

### Out-of-Scope Issue Types (Not OmniScope's Responsibility)

| Category | Why Out-of-Scope | Would Require |
|----------|-----------------|---------------|
| buffer_overflow | Needs bounds analysis pass | Value-range analysis |
| format_string | Needs format string analysis | Taint tracking + format parsing |
| boundary_error | Needs bounds checking | Interval arithmetic |
| unsafe_operation | Generic unsafe pattern | Pattern expansion |
| unchecked_return | Return value not checked | Error path analysis |
| injection (SQL/etc.) | Injection vulnerability | Taint analysis |
| weak_crypto | Cryptographic weakness | Crypto pattern database |
| sensitive_data | Data exposure in memory | Data flow tracking |
| uninit_memory | Uninitialized memory use | Def-use analysis |
| invalid_param | Invalid parameter value | Constraint solving |

**Total Out-of-Scope Issues in Corpus: 21 out of 136 (15.4%)**

### How Scope is Enforced in Benchmark

1. Each issue in `corpus/EXPECTED_RESULTS.md` has a **Scope column**: `✅ in-scope` or `❌ out-of-scope`
2. `scripts/benchmark.sh` parses this column and **only counts in-scope issues** as ground truth
3. The summary report explicitly states: *"In-Scope Expected: N (out-of-scope excluded)"*
4. JSON output includes `scope_filter: "in-scope-only"` field

***

## Test Dataset Sources

### Corpus Structure

```
corpus/
├── small/              # Quick validation (~100 lines each)
│   ├── rust_ffi_simple.rs       # Rust Box/CString ownership
│   ├── zig_ffi_simple.zig       # Zig Allocator patterns
│   ├── go_ffi_simple.go         # Go cgo allocation
│   └── cpp_ffi_simple.cpp       # C++ new/delete + smart pointers
│
├── medium/             # Boundary and edge cases (~500 lines)
│   └── boundary_test.c           # 20 issues: null, overflow, double-free
│
├── large/              # Stress testing (~2000 lines)
│   └── stress_patterns.c         # 70 issues: repetitive FFI patterns
│
└── ffi-dense/          # Real-world library bindings
    ├── sqlite_binding.c           # SQLite3 API misuse (6 issues)
    ├── openssl_wrapper.c          # OpenSSL crypto API (10 issues)
    ├── zlib_binding.c             # zlib compression API (10 issues)
    └── rust_sqlite_ffi.rs         # Rust→SQLite cross-lang (7 issues)
```

### Dataset Statistics

| Directory | Files | Functions | IR Lines | Expected Issues |
|-----------|-------|-----------|----------|-----------------|
| small/ | 4 | ~20 | ~400 | 13 |
| medium/ | 1 | ~25 | ~500 | 20 |
| large/ | 1 | ~80 | ~2000 | 70 |
| ffi-dense/ | 4 | ~50 | ~1500 | 33 |
| **Total** | **10** | **~175** | **~4400** | **136** |

### Issue Type Distribution

| Issue Type | Count | Severity Range |
|------------|-------|----------------|
| leak | 67 | high |
| cross_lang_free_mismatch | 27 | high |
| buffer_overflow | 3 | critical |
| use_after_free | 4 | critical |
| double_free | 2 | critical |
| format_string | 4 | high |
| borrow_escape | 3 | critical |
| null_dereference | 2 | critical |
| boundary_error | 4 | high |
| Other | 20 | low-critical |

### Real-World Examples (`examples/real_world/`)

| Library | Binding Language | Pattern Focus |
|---------|------------------|---------------|
| OpenSSL | C | EVP_CIPHER_CTX, BIO, RSA lifecycle |
| SQLite | C | sqlite3_open/prepare/finalize/close |
| zlib | C | inflateInit/deflateEnd, gzopen/gzclose |

### Compilation Standards

All corpus files must be compiled with:

```bash
clang -S -emit-llvm -O0 -fno-discard-value-names -g source.c -o output.ll
```

Key flags:
- `-O0`: No optimization (preserve all IR instructions)
- `-fno-discard-value-names`: Keep variable names for readability
- `-g`: Include debug info for DWARF-based language detection

***

## Known vs Unknown Function

### Definition

**Known Function:** A function registered in `src/registry/semantic_registry.zig` with a defined `RiskKind` and semantic behavior. Currently **131 functions** across 6 layers:

| Layer | Language | Count | Example Functions |
|-------|----------|-------|-------------------|
| 1 | C (stdlib) | 37 | malloc, free, calloc, realloc, strdup |
| 2 | C (POSIX) | 3 | mmap, munmap, dlopen |
| 3 | Rust | 4 | Box::into_raw, Box::from_raw, CString::into_raw |
| 4 | Go/Swift | 8 | C.malloc, C.free, UnsafeMutablePointer |
| 5 | Zig | 25 | GeneralPurposeAllocator.alloc, Allocator.free |
| 6 | C++ | 54 | operator new, make_unique, shared_ptr |

**Unknown Function:** Any function not in the registry. Handled via conservative heuristics:
- Name-based pattern matching (e.g., `_R` prefix → Rust, `_Z` prefix → C++)
- DWARF debug info fallback (when available)
- Default: treat as potential transfer point

### Detection Behavior Difference

| Aspect | Known Function | Unknown Function |
|--------|---------------|-----------------|
| Ownership inference | Precise (alloc/free/transfer) | Conservative (assume transfer) |
| Cross-language check | Full mismatch detection | Name-pattern based only |
| Severity assignment | Registry-defined | Default high |
| Performance cost | O(1) hash lookup | O(n) name scanning |

### Why This Distinction Matters

Benchmark results must separately report:
1. **Detection rate on known functions** — measures registry coverage quality
2. **Detection rate on unknown functions** — measures heuristic robustness
3. **False positive rate on both categories** — measures precision

### Ground Truth Annotation Rules

When writing test cases for benchmarking:

```c
// KNOWN: malloc is Layer 1 (C stdlib) -> precise tracking
void *p = malloc(1024);     // Detected as alloc
// ... no free(p) ...        // Detected as leak (TP)

// UNKNOWN: custom_alloc is NOT in registry -> conservative
void *q = custom_alloc(256); // Detected as potential alloc (heuristic)
// May produce FP or FN depending on naming pattern match
```

***

## Correct Detection Standard

### What Constitutes "Correct Detection"

An issue is **correctly detected** if ALL of the following hold:

1. **Issue Exists**: The reported issue is present in the source code per ground truth
2. **Location Accurate**: The reported function/location matches the actual bug location
3. **Type Correct**: The issue type matches the expected classification
4. **Severity Reasonable**: Severity is within one level of expected (e.g., high vs medium OK; low vs critical NOT OK)

### Detection Scoring Formula

```
Precision = TP / (TP + FP)
Recall    = TP / (TP + FN)
F1 Score  = 2 * Precision * Recall / (Precision + Recall)
```

Where:
- **TP (True Positive)**: Issue correctly detected and matches ground truth
- **FP (False Positive)**: Issue reported but not in ground truth
- **FN (False Negative)**: Issue in ground truth but not detected

### Per-Category Targets

| Category | Precision | Recall | F1 |
|----------|-----------|--------|-----|
| Memory Leaks | >= 95% | >= 90% | >= 0.92 |
| Cross-Language Mismatch | >= 98% | >= 85% | >= 0.91 |
| Use-After-Free | >= 90% | >= 80% | >= 0.85 |
| Buffer Overflow | >= 95% | >= 75% | >= 0.84 |
| Double Free | >= 95% | >= 90% | >= 0.92 |
| Overall (Phase 4 Final) | **>= 95%** | **>= 88%** | **>= 0.91** |

### Phase-Based Targets (Current: Phase 1 → Phase 4)

OmniScope uses **phase-gated targets** to allow incremental improvement without constant CI failures.

| Phase | Tasks | Precision | Recall | F1 | Status |
|-------|-------|-----------|--------|-----|--------|
| **Phase 1** | Baseline (6.1-6.3 complete) | >= 50% | >= 60% | >= 0.55 | ✅ **P=64%, R=70%, F1=67%** |
| **Phase 2** | 7.1+7.2+7.3+7.4+7.5 (Fix counting, reduce FP, expand registry, null guard) | >= 82% | >= 85% | >= 0.87 | ✅ **P=83%, R=93%, F1=88%** |
| **Phase 3** | 7.6 (small corpus coverage) + unified report format | >= 92% | >= 90% | >= 0.91 | ⬜ Next |
| **Phase 4** | Full EXPECTED completeness + architecture cleanup | **>= 95%** | **>= 88%** | **>= 0.91** | ⬜ Final |

### Severity Mapping Standard

| Ground Truth | Reported | Verdict |
|--------------|----------|---------|
| critical | critical | ✅ Exact |
| critical | high | ⚠️ Acceptable (1-level diff) |
| high | medium | ⚠️ Acceptable (1-level diff) |
| high | low | ❌ Unacceptable (>1-level diff) |
| medium | critical | ❌ Unacceptable (over-reporting) |

### Edge Case Handling

| Scenario | Expected Behavior |
|----------|-------------------|
| Macro-expanded code | Detect at expanded IR level |
| Inlined functions | Track through inlined scope |
| Optimized-away variables | Skip (no IR to analyze) |
| External declarations | Analyze conservatively |
| Variadic functions | Use parameter count heuristic |
| Function pointers | Use points-to + devirtualization |

***

## Performance Targets

### Latency Targets (Per Operation)

| Operation | Target Latency | Measurement Method |
|-----------|---------------|-------------------|
| Registry Lookup (known) | < 100 ns | Hash map hit |
| Registry Lookup (unknown) | < 1 μs | Full scan fallback |
| Engine Alloc/Free cycle | < 5 μs | Single resource lifecycle |
| Engine Leak Detection (100 resources) | < 100 μs | Batch scan |
| CFG Traversal (per function) | < 10 μs | Basic block walk |
| Points-To Analysis (per function) | < 50 μs | Constraint solve |
| NULL Guard Recognition (per BB) | < 1 μs | Pattern match |
| Full Pipeline (small file) | < 10 ms | End-to-end analysis |
| Full Pipeline (medium file) | < 100 ms | End-to-end analysis |
| Full Pipeline (large file) | < 1 s | End-to-end analysis |

### Memory Targets

| Scale | IR Lines | Target Peak Memory |
|-------|----------|-------------------|
| Small | < 500 | < 50 MB |
| Medium | < 5,000 | < 200 MB |
| Large | < 50,000 | < 1 GB |
| Stress | < 500,000 | < 4 GB |

### Scalability Requirement

Analysis time must scale **linearly** (or better) with input size:

```
T(n) <= O(n) where n = number of LLVM instructions

Acceptable: T(2n) <= 2.5 * T(n)  (sub-linear overhead allowed)
Unacceptable: T(2n) > 4 * T(n)  (super-linear = bug)
```

### Throughput Targets

| Metric | Target |
|--------|--------|
| Instructions analyzed/sec | > 1M ops/sec (ReleaseFast) |
| Functions analyzed/sec | > 10K funcs/sec |
| Corpus throughput (all files) | < 5 s total |

***

## Metric Definitions

### Primary Metrics

| Metric | Formula | Unit |
|--------|---------|------|
| Precision | TP / (TP + FP) | ratio (0-1) |
| Recall | TP / (TP + FN) | ratio (0-1) |
| F1 Score | 2*P*R / (P+R) | ratio (0-1) |
| False Positive Rate | FP / (FP + TN) | ratio (0-1) |
| Analysis Throughput | IR_lines / time_sec | lines/sec |
| Memory Efficiency | peak_memory_kb / IR_lines | KB/line |

### Secondary Metrics

| Metric | Description |
|--------|-------------|
| Per-issue-type breakdown | Precision/recall per issue category |
| Per-language breakdown | Detection rate per source language |
| Per-severity breakdown | Accuracy per severity level |
| Time distribution | % time in each pipeline stage |

### Reporting Format

All benchmark outputs use JSON:

```json
{
  "benchmark_id": "omniscope-20260421-001",
  "timestamp": "2026-04-21T00:00:00Z",
  "environment": {
    "os": "macOS",
    "cpu": "Apple M2",
    "zig_version": "0.13.0",
    "llvm_version": "22",
    "build_mode": "ReleaseFast"
  },
  "results": {
    "precision": 0.96,
    "recall": 0.91,
    "f1_score": 0.935,
    "false_positive_rate": 0.02,
    "analysis_time_ms": {
      "small": 8.5,
      "medium": 72.3,
      "large": 850.0
    },
    "memory_mb": {
      "small": 12.0,
      "medium": 45.0,
      "large": 380.0
    },
    "per_issue_type": {
      "leak": {"tp": 65, "fp": 0, "fn": 2},
      "cross_lang_free_mismatch": {"tp": 26, "fp": 0, "fn": 1}
    }
  }
}
```

***

## Benchmark Categories

### Category 1: Micro-Benchmarks (`benches/main.zig`)

Purpose: Measure individual component performance.

| Benchmark | Iterations | Target |
|-----------|-----------|--------|
| Engine Init | 10,000 | < 1 μs |
| Engine Alloc | 10,000 | < 5 μs |
| Engine Full Cycle | 10,000 | < 5 μs |
| Engine Detect Leaks (100) | 100 | < 100 μs |
| Registry Lookup (known) | 100,000 | < 100 ns |
| Registry Lookup (unknown) | 100,000 | < 1 μs |
| Mapper MapFunction (C) | 100,000 | < 10 ns |
| Mapper MapFunction (Rust) | 100,000 | < 50 ns |

Run with: `make bench`

### Category 2: Corpus Detection Rate (`scripts/benchmark.sh`)

Purpose: Measure end-to-end detection accuracy on test corpus.

Process:
1. Compile all corpus files to LLVM IR
2. Run OmniScope analysis on each file
3. Compare output against `EXPECTED_RESULTS.md`
4. Calculate precision/recall/F1

Run with: `make benchmark` (after implementation)

### Category 3: Scalability Tests (`tests/benchmark/`)

Purpose: Verify linear scaling with input size.

| Test | Input Size | Max Time | Max Memory |
|------|-----------|----------|------------|
| Linear growth (10x) | 100 → 1000 → 10000 funcs | 10x time | 10x memory |
| Memory stability | 1000 funcs × 10 runs | variance < 5% | no growth |
| Stress test | 500K IR lines | < 30 s | < 4 GB |

***

## CI Integration

### Required Benchmarks (Every PR)

| Benchmark | Threshold | Failure Action |
|-----------|-----------|----------------|
| Unit tests | 100% pass | Block merge |
| Integration tests | 100% pass | Block merge |
| Detection rate (small corpus) | F1 >= 0.90 | Warn |
| Detection rate (full corpus) | F1 >= 0.88 | Warn |
| Performance regression | < 20% degradation | Warn |
| Memory regression | < 20% increase | Warn |

### Optional Benchmarks (Nightly)

| Benchmark | Frequency | Purpose |
|-----------|-----------|---------|
| Large corpus analysis | Daily | Catch scaling bugs |
| Full performance suite | Weekly | Track long-term trends |
| Memory leak detection | Weekly | Verify no memory leaks in tool itself |

### Regression Thresholds

If any metric degrades beyond the threshold, CI must flag it:

| Metric | Warning Threshold | Critical Threshold |
|--------|-------------------|-------------------|
| F1 Score | < 0.88 (from 0.91) | < 0.85 |
| Analysis time | > 20% slower | > 50% slower |
| Memory usage | > 20% more | > 50% more |
| New false positives | Any FP on known patterns | Block merge |

### Benchmark Output Artifacts

Each CI run produces:
1. `benchmark-results.json` — Machine-readable metrics
2. `benchmark-summary.txt` — Human-readable summary
3. `benchmark-diff.json` — Delta from previous run (if baseline exists)

***

## Appendix: Running Benchmarks

### Quick Start

```bash
# 1. Run micro-benchmarks (component-level timing)
make bench

# 2. Build test corpus
make corpus-ir

# 3. Run detection rate benchmark
make benchmark

# 4. Run full benchmark suite (after Task 6.2/6.3)
make benchmark-full
```

### Adding New Test Cases

1. Create source file in appropriate `corpus/` subdirectory
2. Compile to LLVM IR with standard flags
3. Add expected issues to `corpus/EXPECTED_RESULTS.md`
4. Update statistics tables in this document
5. Run `make benchmark` to verify detection rate

### Interpreting Results

| Result Pattern | Diagnosis | Action |
|---------------|-----------|--------|
| High precision, low recall | Too conservative | Add more patterns/heuristics |
| Low precision, high recall | Too aggressive | Fix false positive sources |
| Both low | Fundamental issue | Review analysis algorithm |
| Super-linear time growth | Scaling bug | Profile and optimize |
| Memory growing with runs | Memory leak | Fix allocator cleanup |
