# OmniScope Security Audit Report

> Audit Date: 2026-04-20 · Scope: All 47 Zig source files in src/ · Version: Latest

---

## 1. Executive Summary

| Item | Detail |
|------|--------|
| Project | OmniScope |
| Description | LLVM IR-based cross-language FFI static security analysis framework |
| Language | Zig |
| External Dependency | LLVM 21 (LLVM-C API) |
| Files Audited | 47 .zig source files |
| Bugs Found | 12 (1 Critical / 3 High / 4 Medium / 4 Low) |
| Overall Score | 7.5 / 10 |

---

## 2. Bug List

### BUG-01 [Critical] FactStore::insert() errdefer causes SoA data misalignment

- **File**: `src/fact/store.zig` lines 58-64
- **Category**: Data corruption / Logic error

**Issue**: `insert()` appends elements to four SoA arrays sequentially, registering an `errdefer` after each to rollback on failure. Zig's `errdefer` is stack-based (last registered executes first). When an intermediate step fails, already-succeeded arrays are correctly popped, but the **failed array is also popped** (removing its last valid element), causing the four SoA columns to have inconsistent lengths.

```zig
try self.kinds.append(self.allocator, kind);    // succeeds
errdefer _ = self.kinds.pop();                   // errdefer #3
try self.subj.append(self.allocator, subject);   // if this fails...
errdefer _ = self.subj.pop();                    // subj has no new element, pops previous one!
```

**Impact**: All subsequent `get(index)` calls return misaligned data. Analysis results become completely unreliable.

**Fix**: Save original lengths at function entry, truncate on failure:
```zig
const orig_len = self.kinds.items.len;
try self.kinds.append(self.allocator, kind);
try self.subj.append(self.allocator, subject);
try self.obj.append(self.allocator, object);
try self.ctx.append(self.allocator, context);
// On failure: truncate all arrays to orig_len
```

---

### BUG-02 [High] taint_propagation.zig GEP branch unreachable

- **File**: `src/pass/analysis/taint_propagation.zig` lines 479-508
- **Category**: Logic error

**Issue**: The `c.LLVMGetElementPtr` branch is placed **after** the `else => {}` branch. In Zig, `else` captures all unmatched cases, so GEP instructions always fall into the else branch. The specialized GEP depth decay logic never executes.

**Impact**: Taint propagation through GEP instructions lacks depth decay calculation, overestimating taint confidence through multi-level pointer dereferences.

**Fix**: Move `c.LLVMGetElementPtr` branch before the `else` branch.

---

### BUG-03 [High] pointer_ownership.zig boundary_id=0 causes array out-of-bounds

- **File**: `src/pass/analysis/pointer_ownership.zig` lines 626-651
- **Category**: Memory safety (out-of-bounds access)

**Issue**: `registerBoundary()` returns `0` on OOM (boundary.zig line 169). The caller uses `boundary_id - 1` as an array index. When `boundary_id=0`, `0 - 1` underflows to `usize::MAX`, causing an out-of-bounds array access.

```zig
const boundary_id = boundary_analyzer.registerBoundary(...);  // may return 0
boundary_analyzer.boundaries.items[boundary_id - 1]           // underflow!
```

**Impact**: Program crash or undefined behavior.

**Fix**: Check `boundary_id == 0` before array access, or change `registerBoundary` to return an error code.

---

### BUG-04 [High] taint_propagation.zig pointer truncation causes Value ID collision

- **File**: `src/pass/analysis/taint_propagation.zig` lines 444, 458, 476, 483, 485, 492, 504
- **Category**: Type safety / Logic error

**Issue**: Uses `@truncate(@intFromPtr(inst))` to truncate 64-bit LLVM pointers to `u32` as taint keys. The project has `ValueIdMap` specifically designed for this mapping, but this file doesn't use it.

**Impact**: On large LLVM IR modules, two different values with the same low 32 bits will collide, causing false positives or missed detections.

**Fix**: Use `ValueIdMap` consistently across all files.

---

### BUG-05 [Medium] call_graph.zig classifyRisk/isSink mismatch with tests

- **File**: `src/pass/analysis/call_graph.zig` lines 330-355
- **Category**: Logic error

**Issues**:
1. `classifyRisk` uses exact match, but tests expect substring match (`"__libc_system"` should return critical)
2. `isSink` uses exact match, but tests expect `"__strcpy_chk"` to match
3. `contains()` helper function is defined but never used

**Impact**: Related tests will fail. Sink detection coverage is insufficient.

**Fix**: Unify matching strategy (recommend using `contains()` for substring matching), update tests.

---

### BUG-06 [Medium] profiler.zig summary() not thread-safe

- **File**: `src/perf/profiler.zig` lines 177-195
- **Category**: Concurrency safety

**Issue**: `summary()` uses a `struct`-level `var` static buffer. Concurrent calls will cause data races. Code comment notes "not thread-safe".

**Impact**: No impact in current single-threaded usage. Will be a problem in multi-threaded scenarios.

**Fix**: Accept a caller-provided buffer, or protect with a mutex.

---

### BUG-07 [Medium] graph.zig getIssuesBySeverity ownership inconsistency

- **File**: `src/dataflow/graph.zig` lines 379-402
- **Category**: API design flaw

**Issue**: `getIssuesBySeverity()` allocates new memory via `allocator.alloc()` and returns it to the caller, while other getters return borrowed slices. Callers may forget to free the returned memory. Cannot distinguish "no matches" from "OOM".

**Fix**: Unify API conventions, or return an iterator/slice view.

---

### BUG-08 [Low] pipeline.zig nanosecond timestamp truncation

- **File**: `src/pipeline/pipeline.zig` line 91
- **Category**: Type safety

**Issue**: `@intCast` truncates `i128` nanosecond timestamp to `u64`. Would overflow after ~584 years. No practical impact.

---

### BUG-09 [Low] main.zig vulnerability ID silent truncation

- **File**: `src/main.zig` line 262
- **Category**: Type safety

**Issue**: `@intCast` truncates `usize` to vulnerability ID type. Would overflow after ~4.2 billion vulnerabilities. No practical impact.

---

### BUG-10 [Low] call_graph.zig contains() dead code

- **File**: `src/pass/analysis/call_graph.zig` lines 358-360
- **Category**: Dead code

**Issue**: `contains()` function is defined but never called. Likely a refactoring leftover.

**Fix**: Remove or use to replace exact matching in `classifyRisk`/`isSink`.

---

### BUG-11 [Medium] ffi_analysis.zig pointer truncation

- **File**: `src/pass/analysis/ffi_analysis.zig` lines 207, 251
- **Category**: Type safety

**Issue**: Same pattern as BUG-04. `@truncate(@intFromPtr(inst))` truncates to u64. No impact on 64-bit systems, potential collision on 32-bit.

**Fix**: Use `ValueIdMap` consistently.

---

### BUG-12 [Low] taint_state.zig initCapacity(0) catch unreachable

- **File**: `src/pass/analysis/taint_state.zig` line 121
- **Category**: Error handling

**Issue**: `initCapacity(allocator, 0) catch unreachable` — `initCapacity(0)` almost never fails, but `catch unreachable` is not best practice.

**Fix**: Use `init(allocator)` or handle the error gracefully.

---

## 3. Severity Distribution

| Severity | Count | Bug IDs |
|----------|-------|---------|
| Critical | 1 | BUG-01 |
| High | 3 | BUG-02, BUG-03, BUG-04 |
| Medium | 4 | BUG-05, BUG-06, BUG-07, BUG-11 |
| Low | 4 | BUG-08, BUG-09, BUG-10, BUG-12 |

---

## 4. Fix Priority

| Priority | Bug | Reason |
|----------|-----|--------|
| P0 Immediate | BUG-01 | FactStore data corruption, all analysis results unreliable |
| P1 Soon | BUG-03 | Array out-of-bounds, program crash |
| P1 Soon | BUG-02 | GEP branch unreachable, taint analysis precision degraded |
| P2 Planned | BUG-04, BUG-11 | Pointer truncation, collisions on large IR |
| P2 Planned | BUG-05 | Tests don't match implementation |
| P3 Later | BUG-06 ~ BUG-12 | API design, dead code, defensive programming |

---

## 5. Code Quality Assessment

### Strengths

1. **Excellent architecture**: Pass-based analysis with topological sort dependency management, well-decoupled modules
2. **SoA data layout**: FactStore uses Structure of Arrays for cache-friendliness
3. **comptime type safety**: Pass interface validated at compile time, zero runtime overhead
4. **Data-driven design**: SemanticMapper uses rule tables, easily extensible
5. **Comprehensive testing**: Nearly every module has unit tests
6. **Proper resource management**: Most modules correctly implement init/deinit with defer/errdefer
7. **Safe LLVM-C wrapping**: Raw LLVM-C API safely wrapped via llvm_safe.zig
8. **Multi-format output**: Text/JSON/SARIF formats, SARIF compliant with v2.1.0
9. **Extensible registry**: SemanticRegistry with 4-layer lookup mechanism
10. **Path-sensitive analysis**: path_condition.zig implements null check tracking

### Weaknesses

1. **errdefer stack behavior misunderstanding**: BUG-01 is the most severe issue
2. **switch branch ordering error**: BUG-02 is a typical refactoring leftover
3. **Tests out of sync with implementation**: BUG-05 has multiple mismatched test cases
4. **Systematic pointer truncation**: Multiple files repeat the same issue; ValueIdMap exists but isn't used consistently
5. **Inconsistent API ownership conventions**: Some methods return owned memory, others return borrowed slices

---

## 6. Conclusion

OmniScope has excellent overall architecture design and above-average code quality for its category. Of the 12 bugs found, BUG-01 (FactStore data corruption) is the only Critical issue requiring immediate fix. BUG-02 and BUG-03 are High severity and should be addressed soon. The remaining Medium/Low issues can be fixed in subsequent iterations.

The project performs well in memory safety, type safety, and error handling. The main issues are concentrated on Zig language feature usage details (errdefer stack behavior, switch branch ordering) and API design consistency.
