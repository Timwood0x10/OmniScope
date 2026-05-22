# OmniScope Bug Report & Technical Debt

**Date**: 2026-05-22
**Version**: v0.1.9 (dev branch)
**Scope**: Full codebase review (~35,000 lines, 80+ Zig source files)

---

## Part 1: Bugs (Must Fix)

### P0 — Semantic Bug: integer_overflow maps to wrong IssueKind

**File**: `src/pass/analysis/issue/integer_overflow.zig:86`

```zig
const issue = Issue.init(
    .buffer_overflow, // WRONG — should be .integer_overflow
    message,
    location,
    .medium,
    confidence,
);
```

`IssueKind` (defined in `src/common/types.zig:151`) has no `integer_overflow` variant. The code uses `.buffer_overflow` as a workaround, producing **misleading CWE IDs in SARIF/JSON output** (CWE-120 instead of CWE-190).

**Fix**: Add `integer_overflow` to `IssueKind` enum, add it to `toString()`, `toCweId()`, and `toDescription()`.

---

### P1 — Memory Leak: call_graph.zig ptr_args_owned not errdefer-protected

**File**: `src/pass/analysis/call_graph.zig:529-561`

```zig
var ptr_args_list = std.ArrayList(u32).initCapacity(ctx.allocator, 8) catch return;
//     ^^^ if OOM here → caller_name_owned and callee_name_owned leak (errdefer won't fire on explicit return)

const ptr_args_owned = try ptr_args_list.toOwnedSlice(ctx.allocator);
//     ^^^ allocated, no errdefer

try ctx.addCrossLangEdge(cross_edge);
//     ^^^ if this fails → ptr_args_owned leaks
```

Two leak paths:
1. `catch return` on line 529 bypasses errdefers for `caller_name_owned`/`callee_name_owned`
2. No errdefer protecting `ptr_args_owned` before `addCrossLangEdge`

**Fix**: Change `catch return` to `catch |e| return e` (propagates error, fires errdefers). Add `errdefer ctx.allocator.free(ptr_args_owned)` after `toOwnedSlice`.

---

### P2 — Inconsistent LLVM opcode comparison in ffi_detector.zig

**File**: `src/pass/analysis/ffi_detector.zig` lines 443, 482, 555

Still uses `@enumFromInt(opcode)` pattern while `malloc_check.zig` and `lock.zig` were correctly fixed to use direct `c.LLVMCall` comparison. Not a runtime bug but inconsistent — `@enumFromInt` can panic if the opcode value is not a valid enum variant.

---

## Part 2: Technical Debt (Verified Against Current Codebase)

Original report: `code_review_technical_debt.md` (2025-01). Each item re-verified on 2026-05-22.

### CRITICAL (5 items — all verified)

| ID | File | Verified | Issue |
|----|------|----------|-------|
| C1 | pointer_ownership.zig:411-613 | **EXISTS** | 8 separate full-module function traversals. Each `while (func)` loop iterates all functions independently. |
| C2 | pointer_ownership.zig:247-409 | **EXISTS** | 3 data sources merged: MemoryGraph + GlobalAllocTracker + IR scan. Lines 408 confirms: `"Pre-populated from MemoryGraph + GlobalAllocTracker + IR-scan"`. |
| C3 | memory_graph.zig:805-871 | **EXISTS** | `isLeaked`/`isDoubleFreed` have O(N*M) nested loops over `arg_indices × call_rets.items`. Existing `call_ret_by_ptr`/`call_ret_by_callee` indexes are **not used** in these hot paths. |
| C4 | memory_graph.zig:178-183 | **PARTIAL** | 6 fields (not 5): 2 primary ArrayLists + 4 secondary indexes. Indexes are used by some paths (`getCallArgsForPtr`) but bypassed by C3's hot paths. |
| C5 | zone_classifier.zig:348-385 | **EXISTS** | `classifyFunction` has zero caching. Pure function (same input → same output), called per-function, always does linear string scanning. |

### HIGH (13 items — all verified)

| ID | File | Verified | Issue |
|----|------|----------|-------|
| H1 | pass.zig:192-279 | **EXISTS** | PassContext has 29 fields (not 30+). God object pattern. |
| H2 | pass.zig:459-549 | **EXISTS** | `addIssue` is 91 lines. Handles priority, dedup, severity, classification in one function. |
| H3 | ffi_boundary.zig:221-473 | **EXISTS** | `checkCallForFFI` is 253 lines. 12 distinct responsibilities in one function. |
| H4 | memory_graph.zig:296 | **EXISTS** | Each `AllocNode` allocates its own `AutoHashMap(u64, void)` for aliases. |
| H5 | memory_graph.zig:910-922 | **PARTIAL** | FFI set rebuilt once per top-level `isOnDangerPath` call (mitigated for recursive calls via parameter passing, but not cached across separate top-level calls). |
| H6 | memory_graph.zig:957-964 | **EXISTS** | Alias closure recursion has `visited` set (no infinite loop) but no memoization across top-level calls. |
| H7 | call_graph.zig:384-448 | **EXISTS** | `getFFIBoundaryReachableFunctions` builds reverse adjacency map from scratch every call. |
| H8 | call_graph.zig:672-744 | **EXISTS** | `classifyArgDirectionByName` defines 4 pattern arrays on every invocation, no memoization. |
| H9 | zone_classifier + ffi_noise_filter | **PARTIAL** | Overlapping concepts (both check `__cxa_*`, safe libc patterns) but different specific patterns. Not exact duplication. |
| H10 | main.zig:65-71 | **EXISTS** | `AnalyzeResult` embeds `Pipeline` by value. Bitwise copy on return. |
| H11 | main.zig:359-363 | **EXISTS** | Defer logic is 4 lines (not complex), but `deinitAnalyzeResult` exists separately and is unused — inconsistency. |
| H12 | main.zig:118-119 | **EXISTS** | `arg_copy` allocated by `dupe`, then `append` called without errdefer. If append fails → leak. |
| H13 | log.zig:10 | **EXISTS** | `pub var current_log_level` — global mutable, no atomic/mutex. Data race in multi-threaded context. |

### MEDIUM (14 items — all verified)

| ID | File | Verified | Issue |
|----|------|----------|-------|
| M1 | ptr_lifetime.zig:219-344 | **EXISTS** | 4 sequential noise-reduction filters per function (NoiseReduction, reevaluate, classifyFull, FPWhitelist). |
| M2 | ptr_lifetime.zig:129-155 | **EXISTS** | `FreeSiteList` is hand-rolled ArrayList (manual growth, capacity, allocator). |
| M3 | ptr_lifetime.zig:363-419 | **EXISTS** | `reverse_alias` HashMap rebuilt from scratch each call, no caching. |
| M4 | ptr_lifetime.zig:497-502 | **EXISTS** | Hardcoded `1000` (basic blocks) and `50000` (instructions) limits, no named constants. |
| M5 | danger_surface.zig:150-170 | **EXISTS** | `traceAliasClosure` recursive, has `visited` set but no depth limit. Acyclic deep chains → stack overflow. |
| M6 | danger_surface.zig:172-180 | **EXISTS** | `markFunctionFromInst` duplicated: standalone function + PassContext method doing the same LLVM parent-block traversal. |
| M7 | ffi_boundary.zig:277-278 | **EXISTS** | `indirect_name_owned` memory management with 8+ early-return paths. |
| M8 | ffi_boundary.zig:647-752 | **EXISTS** | `resolveIndirectCallTarget` is 106 lines with 7 sequential steps. |
| M9 | pointer_ownership.zig:500-531 | **EXISTS** | `reverse_flow` HashMap-of-HashMaps built inline, used once, disposed. |
| M10 | pass.zig:624-632 | **EXISTS** | `getOrComputeZone` takes `*anyopaque` — type erasure workaround for LLVM value ref. |
| M11 | build.zig:193-294 | **EXISTS** | 7 test step blocks follow identical pattern (addModule → addTest → addRunArtifact). |
| M12 | build.zig:4-18 | **EXISTS** | Hardcoded LLVM paths (`/opt/homebrew/opt/llvm`, `/usr/lib/llvm-22`) and version `"22"`. |
| M13 | types.zig:30-105 | **EXISTS** | `Location` has no `deinit`/`free`/`clone` methods. Callers must manually manage string lifetimes. |
| M14 | types.zig:319-336 | **EXISTS** | `fromScore`/`defaultScore` use hardcoded floats (`0.9`, `0.7`, `0.5`, `0.95`, `0.75`, `0.55`, `0.35`). |

### LOW (10 items — 9 verified, 1 removed)

| ID | File | Verified | Issue |
|----|------|----------|-------|
| L1 | main.zig:179-180 | **EXISTS** | 2 commented-out pass registrations (ABIMismatchPass, ThreadCrossingPass). |
| L2 | main.zig:571-574 | **EXISTS** | `countFunction` defined but never called — dead code. |
| L3 | main.zig:624-645 | **EXISTS** | 3 test functions, 2 are effectively identical (both call `parseArgs` with no args). |
| L4 | main.zig:608 | **EXISTS** | Version inconsistency: `--version` prints `0.1.8`, SARIF/JSON output `0.1.9`. |
| L5 | build.zig:9-11 | **EXISTS** | `.linux` and `else` branches return identical value `"/usr/lib/llvm-22"`. Redundant arm. |
| L6 | root.zig:168-177 | **EXISTS** | Same module path `@import("pass/analysis/noise_reduction.zig")` repeated 10 times instead of once. |
| L7 | log.zig:18-35 | **EXISTS** | `[INFO]`/`[DEBUG]`/`[WARN]`/`[ERROR]` prefixes duplicate the `std.log.info/debug/warn/err` level. |
| L8 | semantics/call_graph.zig:315 | **PARTIAL** | `max_depth=10` hardcoded in `ptr_lifetime.zig:282`, not in `call_graph.zig` itself. No named constant. |
| L9 | zone_classifier.zig:341-346 | **REMOVED** | Comment accurately describes implementation. No mismatch. |
| L10 | noise_filter.zig:775-807 | **EXISTS** | `isRustMangledName` delegates to `ffi_language_classifier` (fixed), but `isCppMangledName`/`isZigFunction`/`isGoFunction` still have independent implementations. |

---

## Part 3: Summary

| Severity | Count | Status |
|----------|-------|--------|
| P0 (Bug) | 1 | integer_overflow → wrong CWE in SARIF output |
| P1 (Bug) | 1 | call_graph.zig ptr_args memory leak on error path |
| P2 (Bug) | 1 | ffi_detector.zig inconsistent opcode comparison |
| CRITICAL | 5 | Performance: 8× traversal, O(N²) loops, no caching |
| HIGH | 13 | Architecture: god object, long functions, memory leaks |
| MEDIUM | 14 | Code quality: duplication, hardcoded values, complexity |
| LOW | 9 | Cleanup: dead code, version mismatch, style |
| **Total** | **44** | |

### False Positives Removed

| ID | Original Claim | Reason |
|----|---------------|--------|
| L9 | isAlphaNumeric comment/implementation mismatch | Comment accurately describes the code |

### Items Corrected from Original Report

| ID | Original | Corrected |
|----|----------|-----------|
| C4 | "5 redundant indexes" | 6 fields (2 primary + 4 secondary), partially used |
| H1 | "30+ fields" | 29 fields |
| H5 | "重复构建FFI集合" | Mitigated: rebuilt once per top-level call, not per recursive call |
| H11 | "defer释放逻辑复杂" | 4 lines, not complex. But `deinitAnalyzeResult` unused — inconsistency |

---

## Part 4: Priority Fix Order

### Immediate (blocks v0.1.9 release)
1. **P0**: Add `integer_overflow` to `IssueKind`
2. **P1**: Add errdefer for `ptr_args_owned` in call_graph.zig
3. **L4**: Fix version string `0.1.8` → `0.1.9` in main.zig:608

### Short-term (performance, high impact)
4. **C3**: Use existing `call_ret_by_ptr` index in `isLeaked`/`isDoubleFreed` (eliminate O(N²))
5. **C5**: Add HashMap cache for `zone_classifier.classifyFunction`
6. **C1**: Merge 8 traversals into single-pass visitor pattern

### Medium-term (architecture)
7. **H12**: Add errdefer for `arg_copy` in main.zig
8. **M5**: Add depth limit to `traceAliasClosure`
9. **H13**: Make `current_log_level` atomic or remove (single-threaded tool)
10. **L2**: Delete dead `countFunction`
