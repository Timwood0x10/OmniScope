# OmniScope Security Audit Report

> **Audit Date**: 2026-04-23 · **Scope**: All Zig source files in `src/` + CI/CD workflows + Build system · **Version**: 0.1.5 · **Method**: Manual code audit

---

## 1. Executive Summary

| Item | Detail |
|------|--------|
| **Project** | OmniScope |
| **Description** | LLVM IR-based cross-language FFI static security analysis framework |
| **Primary Language** | Zig (0.15.2+) |
| **External Dependency** | LLVM 21/22 (LLVM-C API) |
| **Files Audited** | 73+ Zig source files + 3 CI/CD workflows + build.zig |
| **Issues Found** | 52 (1 Critical / 18 High / 21 Medium / 12 Low) |
| **Overall Score** | 6.5 / 10 |

---

## 2. Issue Summary

### Severity Distribution

| Severity | Count | Percentage |
|----------|-------|------------|
| 🔴 Critical | 1 | 1.9% |
| 🔴 High | 18 | 34.6% |
| 🟠 Medium | 21 | 40.4% |
| 🟡 Low | 12 | 23.1% |
| **Total** | **52** | 100% |

### Distribution by Category

| Category | Count |
|----------|-------|
| Memory Safety (buffer overflow, UAF, double-free) | 12 |
| Logic Errors (analysis correctness) | 14 |
| Output Injection (unescaped JSON/SARIF) | 6 |
| Resource Management (memory leaks, dangling pointers) | 8 |
| CI/CD Security | 6 |
| Error Handling (catch unreachable, swallowed errors) | 4 |
| Type Safety (pointer truncation, integer overflow) | 2 |

---

## 3. Critical Issues

### BUG-001 [Critical] ffi_detector.zig — Type error causes three vulnerability detectors to be completely non-functional

- **File**: `src/pass/analysis/ffi_detector.zig` line 437
- **Category**: Type Safety / Compilation Error

**Description**: `callsDangerousFunction` passes a `FunctionInfo` (Zig struct) directly to `c.LLVMGetFirstBasicBlock(func)`, which expects `c.LLVMValueRef` (`*const opaque{}`). Zig does not allow implicit conversion from a struct to a pointer type. In contrast, line 476 in the same file (`hasUseAfterFreePattern`) correctly uses `func.func.raw`.

```zig
// Buggy code (line 437)
const bb = c.LLVMGetFirstBasicBlock(func);  // func is FunctionInfo, not LLVMValueRef

// Correct code (line 476)
const bb = c.LLVMGetFirstBasicBlock(func.func.raw);  // correctly unwrapped
```

**Impact**: `detectCommandInjection`, `detectBufferOverflow`, and `detectFormatString` all call `callsDangerousFunction`. Therefore, **command injection, buffer overflow, and format string vulnerability detection are completely non-functional**.

**Fix**: Change `func` to `func.func.raw`.

---

## 4. High Issues

### BUG-002 [High] memory_pool.zig — free_node_pool resize causes dangling pointers in free_list

- **File**: `src/perf/memory_pool.zig` lines 62-98
- **Category**: Memory Safety / Dangling Pointer

**Description**: After `alloc()` removes a node from the free list, `free()` appends the node to `free_node_pool` (an ArrayList) and stores a pointer to that node in the `free_list` linked list. When `free_node_pool`'s internal buffer is reallocated due to `append`, all previously stored pointers in `free_list` become dangling. Subsequent `alloc()` calls that traverse `free_list` will dereference dangling pointers.

**Impact**: Undefined behavior — potential crashes or data corruption. This is the most severe memory safety bug in the project.

**Fix**: Use indices instead of pointers for the free list linkage, or rebuild the free_list chain when ArrayList reallocates.

---

### BUG-003 [High] memory_pool.zig — Double-free pollutes free list

- **File**: `src/perf/memory_pool.zig` lines 92-98
- **Category**: Memory Safety / Double-Free

**Description**: `free()` does not verify whether `item` already exists in the free list or whether the pointer belongs to this memory pool. Double-freeing the same pointer causes: cycles/duplicates in the free list; `total_freed` exceeding `total_allocated` causing `in_use` statistic underflow; subsequent `alloc()` returning memory that is still in use.

**Impact**: Data races and memory corruption.

**Fix**: Add duplicate-free checks and pointer ownership validation in `free()`.

---

### BUG-004 [High] memory_pool.zig — ArenaAllocator integer overflow

- **File**: `src/perf/memory_pool.zig` line 164
- **Category**: Integer Overflow

**Description**: `alloc_size = @max(len + alignment, block_size)` — `len + alignment` can overflow when `len` approaches `usize` max, resulting in an undersized buffer allocation.

**Fix**: Use `@addWithOverflow` or `std.math.add` for overflow-checked arithmetic.

---

### BUG-005 [High] pointer_ownership.zig — Fixed-size BFS queue causes incomplete analysis

- **File**: `src/pass/analysis/pointer_ownership.zig` lines 533-561
- **Category**: Logic Error / Analysis Completeness

**Description**: `markAllocSitesReachingValue()` uses a fixed-size BFS queue `bfs_queue: [64]u32`. When the path depth in the reverse dataflow graph exceeds 64 nodes, the queue overflows and BFS terminates prematurely, silently dropping nodes beyond capacity.

**Impact**: For large LLVM IR modules with deep pointer propagation chains, ownership transfer analysis will be incomplete. Allocation sites that should be marked `transferred = true` will be missed, causing memory leak false positives.

**Fix**: Use a dynamically allocated queue.

---

### BUG-006 [High] alias.zig — getTypeId pointer truncation corrupts TBAA grouping

- **File**: `src/pass/analysis/alias.zig` lines 268-270
- **Category**: Type Safety / Pointer Truncation

**Description**: `getTypeId` uses `@intFromPtr(type_ref)` to truncate a 64-bit `c.LLVMTypeRef` to `u32`. On 64-bit systems, the upper 32 bits are discarded, so different LLVM types may receive the same type_id.

**Impact**: Unrelated pointers may be grouped into the same TBAA group, producing incorrect alias relationships — unrelated pointers reported as may-alias.

**Fix**: Use `AutoHashMap` directly with `LLVMTypeRef` as key, or use `u64` as type_id.

---

### BUG-007 [High] call_graph.zig — Unsigned integer underflow in indirect call resolution

- **File**: `src/pass/analysis/call_graph.zig` line 115
- **Category**: Integer Underflow / Out-of-Bounds Access

**Description**: Operand index calculation in `resolveIndirectCall`: `num_operands - param_count + i`. If `num_operands < param_count` (e.g., default arguments), the unsigned `c_uint` subtraction underflows to a huge value, causing out-of-bounds access via `LLVMGetOperand`.

**Impact**: Out-of-bounds memory access or panic for certain LLVM IR inputs.

**Fix**: Add a `num_operands > param_count` precondition check.

---

### BUG-008 [High] call_graph.zig — Pointer equality comparison for LLVM types

- **File**: `src/pass/analysis/call_graph.zig` lines 107-108
- **Category**: Logic Error

**Description**: `resolveIndirectCall` uses `==` to compare two `c.LLVMTypeRef` (pointer values) instead of comparing the type structures themselves. Two LLVM types with identical structure but different addresses will be incorrectly considered unequal.

**Impact**: Indirect call resolution produces incorrect candidate sets, resulting in inaccurate call graphs.

**Fix**: Use `LLVMGetTypeKind` or structural type comparison.

---

### BUG-009 [High] graph.zig — getIssuesBySeverity ownership inconsistency causes memory leak

- **File**: `src/dataflow/graph.zig` lines 384-418
- **Category**: Resource Leak

**Description**: `getIssuesBySeverity()` allocates new message strings via `dupe` but sets `owned = false`. Callers invoking `Issue.deinit()` will not free the message, causing memory leaks. Additionally, partial data is returned on OOM.

**Fix**: Set `owned = true` or use a different ownership model.

---

### BUG-010 [High] graph.zig — Dangling pointers in HashMap after clear()

- **File**: `src/dataflow/graph.zig` lines 492-517
- **Category**: Memory Safety

**Description**: `clear()` frees edge index memory, but `clearRetainingCapacity()` may leave dangling value pointers in the HashMap. Accessing the HashMap between `clear()` and repopulation will dereference freed memory.

**Fix**: Ensure correct clear semantics, or use `clearAndFree`-style operations after clear.

---

### BUG-011 [High] taint_state.zig — TOCTOU race condition

- **File**: `src/pass/analysis/taint_state.zig` lines 90-125
- **Category**: Thread Safety

**Description**: `setValueTaint()` and `getValueTaint()` each independently acquire and release the mutex. `handleInstruction()` functions call `getValueTaint()` then `setValueTaint()` for the same instruction, with the lock released between the two calls — a classic TOCTOU race condition.

**Impact**: Taint state may be lost or overwritten under multi-threaded scenarios. Current single-threaded usage is unaffected, but this will become a serious issue when parallel analysis is introduced.

**Fix**: Provide compound operation interfaces that complete read-modify-write within a single lock acquisition.

---

### BUG-012 [High] ffi_boundary.zig — demangleRustName parser lacks malformed input protection

- **File**: `src/pass/analysis/ffi_boundary.zig` lines 459-523
- **Category**: Input Validation

**Description**: `demangleRustName` manually parses `_ZN...E` symbol names. Length parsing `len = len * 10 + ...` has no overflow check, and `pos + len` bounds are not validated. Malformed LLVM IR modules may cause out-of-bounds reads or infinite loops.

**Impact**: Out-of-bounds reads or DoS when processing maliciously crafted LLVM IR.

**Fix**: Add comprehensive bounds checking and maximum length limits.

---

### BUG-013 [High] cpp_fp_reduction.zig — Fixed-size BFS queues cause incomplete detection (two instances)

- **File**: `src/pass/analysis/cpp_fp_reduction.zig` lines 438-441, 754-756
- **Category**: Logic Error

**Description**: Both `isFunctionLevelNullGuarded` and `findFreePath` use fixed-size `bfs_queue: [64]u32`. For large dataflow graphs, the 64-node limit causes incomplete search.

**Impact**: Null check protection assessment and free path search are incomplete, producing false positives.

**Fix**: Use dynamically allocated queues.

---

### BUG-014 [High] ffi_detector.zig — LLVMGetValueName return value not null-checked

- **File**: `src/pass/analysis/ffi_detector.zig` lines 486-487
- **Category**: Null Pointer Dereference

**Description**: In `hasUseAfterFreePattern`, the return value of `c.LLVMGetValueName(called_func)` is passed directly to `std.mem.span` without null checking.

**Impact**: Runtime panic for certain LLVM IR inputs.

**Fix**: Add null check before `std.mem.span`.

---

### BUG-015 [High] output/sarif.zig — Rule description not escaped (JSON injection)

- **File**: `src/output/sarif.zig` lines 105-107
- **Category**: Output Injection / JSON Injection

**Description**: In `generate()`, the string returned by `rule.toDescription()` is inserted directly into JSON via `{s}` without calling `writeEscapedString`.

**Impact**: Generates invalid SARIF JSON, potentially causing downstream tools like GitHub Code Scanning to fail parsing or produce security bypasses.

**Fix**: Use `writeEscapedString` for all dynamic strings.

---

### BUG-016 [High] output/formatter.zig — Multiple unescaped fields in SARIF/JSON output

- **File**: `src/output/formatter.zig` lines 171-172, 224-228, 236
- **Category**: Output Injection / JSON Injection

**Description**: In `formatSarif()`, fields like `vuln.description`, `vuln.vuln_type`, and `vuln.source_location` are inserted directly into JSON via `{s}` without escaping. Notably, `formatJson()` in the same file correctly uses `writeEscapedString` for `description`, indicating this is an oversight.

**Impact**: Vulnerability descriptions containing JSON special characters will generate invalid output.

**Fix**: Consistently use `writeEscapedString`.

---

### BUG-017 [High] report/sarif.zig — reason field not escaped

- **File**: `src/report/sarif.zig` line 387
- **Category**: Output Injection / JSON Injection

**Description**: In `writeProperties()`, `issue.reason` (a free-text field) is inserted directly into JSON via `{s}` without escaping.

**Impact**: If `issue.reason` contains double quotes or backslashes, it will corrupt the SARIF JSON structure.

**Fix**: Use `std.json.stringEncode` for escaping.

---

### BUG-018 [High] CI/CD — Release workflow lacks binary signing and checksums

- **File**: `.github/workflows/release.yml` lines 189-200
- **Category**: CI/CD Security / Supply Chain

**Description**: The release workflow uploads compiled binaries directly to GitHub Release without SHA256 checksums, code signatures (GPG/cosign), or SBOM (Software Bill of Materials).

**Impact**: Users cannot verify the integrity or provenance of released binaries, creating supply chain attack risk.

**Fix**: Add `sha256sum` generation, GPG signing, and SBOM generation steps.

---

### BUG-019 [High] CI/CD — Security analysis workflow errors silently ignored

- **File**: `.github/workflows/security-analysis.yml` line 62
- **Category**: CI/CD Security

**Description**: The security analysis command uses `2>/dev/null || echo "Analysis completed with warnings"` to discard all error output. Additionally, line 59 contains a typo in the executable name (`OmniSope` instead of `OmniScope`), causing the security analysis step to never actually run.

**Impact**: Security analysis failures go undetected, potentially marking insecure projects as safe. The security analysis workflow is effectively non-functional.

**Fix**: Correct the typo, remove `2>/dev/null`, and use `set -euo pipefail`.

---

## 5. Medium Issues

### BUG-020 [Medium] fact/store.zig — init/queryByKind use catch unreachable

- **File**: `src/fact/store.zig` lines 31-34, 99
- **Description**: 5 `initCapacity` calls use `catch unreachable`, causing immediate process termination on OOM.
- **Fix**: Use graceful error propagation for query paths.

### BUG-021 [Medium] fact/store.zig — count()/get() not holding lock

- **File**: `src/fact/store.zig` lines 78-91
- **Description**: Read methods don't hold the mutex, potentially reading inconsistent state under concurrency.
- **Fix**: Add locking in `count()` and `get()`.

### BUG-022 [Medium] pointer_ownership.zig — Multiple critical methods are empty stubs

- **File**: `src/pass/analysis/pointer_ownership.zig` lines 910-933
- **Description**: `findFreePath()`, `canReachFree()`, `isMemoryAccess()` always return `false`.
- **Fix**: Implement full logic or remove dead code paths.

### BUG-023 [Medium] pointer_ownership.zig — ScopedTimer double stop

- **File**: `src/pass/analysis/pointer_ownership.zig` lines 139-211
- **Description**: `init_timer` and `analysis_timer` have both `defer stop()` and manual `stop()` calls, recording the same timer twice.
- **Fix**: Remove duplicate `stop()` calls.

### BUG-024 [Medium] taint_propagation.zig — GEP depth factor premature truncation

- **File**: `src/pass/analysis/taint_propagation.zig` line 512
- **Description**: When `num_indices >= 6`, `depth_factor` goes negative, truncating all deep GEP confidences to the same minimum.
- **Fix**: Adjust `GEP_DEPTH_CONFIDENCE_FACTOR` or use logarithmic decay.

### BUG-025 [Medium] taint_state.zig — getTaintedValues ownership API error-prone

- **File**: `src/pass/analysis/taint_state.zig` lines 138-153
- **Description**: Accepts an external allocator but documentation doesn't clarify that callers must use the same allocator to free the return value.
- **Fix**: Add documentation or switch to internal allocator.

### BUG-026 [Medium] profiler.zig — record() OOM leaves key pointing to non-heap memory

- **File**: `src/perf/profiler.zig` lines 91-108
- **Description**: If `getOrPut` succeeds but `dupe` fails (OOM), the HashMap entry is inserted but the key points to a temporary string. `deinit()` will attempt to free non-heap memory.
- **Fix**: Use errdefer to clean up inserted entries.

### BUG-027 [Medium] profiler.zig — Timer.start()/elapsedNs() use catch unreachable

- **File**: `src/perf/profiler.zig` lines 16-17, 22-23
- **Description**: High-precision timer unavailability triggers panic.
- **Fix**: Return errors or use fallback timing mechanisms.

### BUG-028 [Medium] graph.zig — addEdge() memory leak on OOM

- **File**: `src/dataflow/graph.zig` lines 165-179
- **Description**: When `put` fails, newly allocated lists are not freed.
- **Fix**: Add errdefer to free newly allocated lists.

### BUG-029 [Medium] graph.zig — deinit() doesn't free Issue trace entries

- **File**: `src/dataflow/graph.zig` lines 83-107
- **Description**: `deinit()` only frees `message`, doesn't call `Issue.deinit()`, potentially leaking owned trace entries.
- **Fix**: Call `Issue.deinit()` or iterate to free all owned fields.

### BUG-030 [Medium] ffi_analysis.zig — detectOwnershipMismatch cartesian product false positives

- **File**: `src/pass/analysis/ffi_analysis.zig` lines 323-326
- **Description**: Performs cartesian product comparison on all alloc-free pairs without checking dataflow connectivity.
- **Fix**: Add dataflow connectivity checks.

### BUG-031 [Medium] ffi_boundary.zig — identifyLanguage substring matching misclassification

- **File**: `src/pass/analysis/ffi_boundary.zig` lines 396-422
- **Description**: `indexOf` matching is too broad; `"extern"` matches both Rust and Zig patterns.
- **Fix**: Use more precise regex or word boundary matching.

### BUG-032 [Medium] guard_propagation.zig — Null check constraint may be inverted

- **File**: `src/dataflow/guard_propagation.zig` lines 76-87
- **Description**: Assumes `true_bb_id` corresponds to null condition, but the condition form (`p == NULL` vs `p != NULL`) may be reversed.
- **Fix**: Determine semantic direction based on ICmp predicate.

### BUG-033 [Medium] guard_propagation.zig — Value pointer truncated to u32

- **File**: `src/dataflow/guard_propagation.zig` lines 114, 124
- **Description**: `@intFromPtr(value)` truncated to `u32`, losing upper 32 bits on 64-bit systems.
- **Fix**: Use `u64` or `usize` as value_id.

### BUG-034 [Medium] steensgaard.zig — Indirect constraint handling incomplete

- **File**: `src/pass/analysis/steensgaard.zig` lines 244-256
- **Description**: For indirect constraints `*p = q`, only `unite(p, q)` is performed without processing p's points-to set.
- **Fix**: Iterate over p's points-to set and merge each element.

### BUG-035 [Medium] steensgaard.zig — handleAlloca virtual object ID collision risk

- **File**: `src/pass/analysis/steensgaard.zig` lines 103-105
- **Description**: Uses `@intFromPtr(inst) + 1` as virtual object ID, with theoretical collision risk.
- **Fix**: Use a separate incrementing ID counter.

### BUG-036 [Medium] call_graph.zig — propagateTaint iteration limit too low

- **File**: `src/pass/analysis/call_graph.zig` lines 315-345
- **Description**: Fixed iteration limit of 8; taint propagation incomplete for deep call chains.
- **Fix**: Use a worklist algorithm instead of fixed iterations.

### BUG-037 [Medium] call_graph.zig — classifyRisk/isSink substring over-matching

- **File**: `src/pass/analysis/call_graph.zig` lines 400-406
- **Description**: Safe functions like `system_call`, `mysystem` are incorrectly flagged as dangerous sinks.
- **Fix**: Use exact matching or whitelist mechanisms.

### BUG-038 [Medium] cpp_fp_reduction.zig — detectUseAfterFree logic direction error

- **File**: `src/pass/analysis/cpp_fp_reduction.zig` lines 527-558
- **Description**: Checks "whether freed pointer flows to another free point" instead of "whether freed pointer is used after free".
- **Fix**: Check for load/store/call operations after free.

### BUG-039 [Medium] report/mod.zig — formatTimestamp returns static string on OOM

- **File**: `src/report/mod.zig` lines 300-301
- **Description**: `allocator.dupe()` failure returns a compile-time constant string; caller's `free()` causes UB.
- **Fix**: Return error instead of static string on OOM.

### BUG-040 [Medium] report/mod.zig — generate() swallows OOM error

- **File**: `src/report/mod.zig` line 99
- **Description**: `initCapacity` failure returns empty string `""`; caller cannot distinguish error from empty report.
- **Fix**: Propagate the error.

---

## 6. Low Issues

| ID | File | Description |
|----|------|-------------|
| BUG-041 | `fact/store.zig` | `count()`/`get()` not holding lock, data race (no impact in current single-threaded usage) |
| BUG-042 | `pointer_ownership.zig` | `param_value_ids` array size 32 but only 16 used |
| BUG-043 | `pointer_ownership.zig` | `summary_registry.initBuiltins()` error swallowed |
| BUG-044 | `taint_propagation.zig` | `source_count`/`inst_count` are u32, may overflow on large IR |
| BUG-045 | `profiler.zig` | `ScopedTimer.start()` borrows caller string, API error-prone |
| BUG-046 | `graph.zig` | FFI boundary ID `usize + 1` truncated to `u32` |
| BUG-047 | `ffi_analysis.zig` | `@intCast(i)` usize to u32 may truncate |
| BUG-048 | `ffi_boundary.zig` | `isCppAbiInternalFunction` exact match loop is redundant |
| BUG-049 | `alias.zig` | `mayAliasByType` function declared but never called (dead code) |
| BUG-050 | `cpp_fp_reduction.zig` | `isLikelyIntentionalPattern` can be bypassed via naming conventions |
| BUG-051 | `tracking/allocator.zig` | `resize` shrink doesn't update `free_count`, leak detection inaccurate |
| BUG-052 | `output/lsp.zig` | `FileMap.add` doesn't free old URI on duplicate loc_id |

---

## 7. CI/CD Security Assessment

### 7.1 curl | bash Supply Chain Risk

- **Files**: `.github/workflows/ci.yml` line 29, `release.yml` line 39
- **Issue**: `curl -sSL https://www.zvm.app/install.sh | bash` without checksum or PGP signature verification
- **Recommendation**: Pin install script version, add integrity verification

### 7.2 Deprecated apt-key and HTTP Repository

- **Files**: `.github/workflows/ci.yml` lines 39-41, `release.yml` lines 49-51
- **Issue**: Uses deprecated `apt-key add`, and LLVM repository URL uses HTTP
- **Recommendation**: Migrate to `/etc/apt/keyrings/` approach, use HTTPS URLs

### 7.3 Release Workflow Overly Permissive

- **File**: `.github/workflows/release.yml` lines 9-10
- **Issue**: `contents: write` without scope restriction
- **Recommendation**: Follow least-privilege principle, restrict to release operations

### 7.4 Inconsistent Zig Versions Across Workflows

- **Files**: Three CI workflows
- **Issue**: `security-analysis.yml` uses `0.15.0`, others use `0.15.2`
- **Recommendation**: Unify Zig version across all workflows

### 7.5 Security Scorecard is a No-Op

- **File**: `.github/workflows/security-analysis.yml` lines 139-163
- **Issue**: Only prints static text, doesn't execute any actual security scoring
- **Recommendation**: Integrate real tools like OpenSSF Scorecard

---

## 8. Fix Priority

| Priority | Count | Description |
|----------|-------|-------------|
| **P0 Immediate** | 4 | Compilation error(1) + dangling pointer(1) + double-free(1) + integer overflow(1) |
| **P1 Soon** | 14 | Analysis logic errors(8) + JSON injection(3) + CI/CD security(3) |
| **P2 Planned** | 21 | False positives/negatives, resource management, error handling |
| **P3 Later** | 13 | Performance, code quality, dead code |

---

## 9. Code Quality Assessment

### Strengths

1. **Excellent Architecture**: Pass-based analysis framework with topological sort dependency management and well-decoupled modules
2. **comptime Type Safety**: Pass interfaces validated at compile time, zero runtime overhead
3. **SoA Data Layout**: FactStore uses Structure of Arrays for cache-friendly access patterns
4. **Data-Driven Design**: SemanticMapper uses rule tables, easily extensible
5. **Comprehensive Testing**: Unit tests, integration tests, stability tests, stress tests, E2E tests
6. **Safe LLVM-C Wrapping**: Raw LLVM-C API safely wrapped via llvm_safe.zig
7. **Multi-Format Output**: Text/JSON/SARIF formats, SARIF compliant with v2.1.0
8. **Extensible Registry**: SemanticRegistry with 4-layer lookup mechanism

### Weaknesses

1. **Concentrated Memory Safety Issues**: memory_pool.zig has dangling pointer and double-free bugs — the highest priority module to fix
2. **Inconsistent JSON/SARIF Output Escaping**: Multiple missing string escapes affecting downstream security tools
3. **Fixed-Size Buffers**: BFS queues hardcoded to 64-element limits, causing incomplete analysis on large IR
4. **Widespread Pointer Truncation**: Multiple locations truncate 64-bit pointers to u32, creating ID collision risk on large modules
5. **Weak CI/CD Security**: Missing binary signatures, curl|bash usage, non-functional security analysis workflow
6. **Inconsistent Error Handling**: Mix of catch unreachable and swallowed errors

---

## 10. Conclusion

OmniScope has excellent overall architecture design and above-average code quality for its category. This audit identified 52 issues: 1 Critical (compilation error rendering three vulnerability detectors non-functional), 18 High (concentrated in memory safety, analysis logic correctness, and output injection).

**Top Priority Fixes**:
1. Dangling pointer and double-free in `memory_pool.zig` (BUG-002, BUG-003)
2. Type error in `ffi_detector.zig` (BUG-001)
3. JSON/SARIF output injection issues (BUG-015, BUG-016, BUG-017)
4. Non-functional security analysis CI workflow (BUG-019)

The project performs well in memory safety, type safety, and error handling overall. The main issues are concentrated in specific modules' boundary condition handling and CI/CD security configuration. We recommend fixing P0 and P1 issues first, following the priority order outlined in Section 8.
