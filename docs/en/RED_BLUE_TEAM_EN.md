# Red/Blue Team Testing Guide

**Version**: v0.2.0
**Purpose**: Validate OmniScope's detection rate (red team) and false positive rate (blue team) against the `corpus/` test suite.

## Quick Start

```bash
make red-team       # Adversarial: does the tool detect known bugs?
make blue-team      # Defensive: does the tool avoid false alarms?
make corpus-test    # Run both
```

***

## Part 1: Red Team — Adversarial Detection Test

### What It Does

Runs OmniScope against crafted test files in `corpus/red_team_test/` that contain **known bugs** (memory leaks, double frees, use-after-free, FFI boundary violations). Measures **recall** — how many injected bugs the tool actually catches.

### Run Log (Real Output)

```
╔════════════════════════════════════════════════════════════════╗
║                    RED TEAM TEST                              ║
║  Adversarial: detect known bugs in crafted test cases         ║
╚════════════════════════════════════════════════════════════════╝
  ✅ red_team_bugs.ll                         25 issues
  ✅ ffi_boundary_bugs.ll                     18 issues
  ✅ cross_lang_free_bugs.ll                  12 issues
  ✅ cross_lang_free_complete.ll              15 issues
  ✅ subtle_ffi_bugs.ll                        8 issues
  ✅ python_c_api_bugs.ll                     10 issues
  ✅ posix_ffi_bugs.ll                         6 issues
────────────────────────────────────────────────────────
  Red Team: 7 files, 94 total issues detected
  ✅ Detection threshold met
```

### Line-by-Line Interpretation

#### Header

```
╔════════════════════════════════════════════════════════════════╗
║                    RED TEAM TEST                              ║
╚════════════════════════════════════════════════════════════════╝
```

This is the test banner. The Makefile target `red-team` (defined in `Makefile:640`) triggers `build` first, then iterates over `RED_IR_FILES`.

#### Per-File Result

```
  ✅ red_team_bugs.ll                         25 issues
```

| Field | Meaning |
|-------|---------|
| `✅` | File produced ≥1 issue (pass) |
| `❌` | File produced 0 issues (miss — potential regression) |
| `red_team_bugs.ll` | Test file name |
| `25 issues` | Total issues detected by OmniScope |

**How to locate the source**: Each `.ll` file is compiled from a `.c` file in the same directory. For example:

```
corpus/red_team_test/red_team_bugs.c      ← Source code with injected bugs
corpus/red_team_test/red_team_bugs.ll     ← Compiled LLVM IR (what OmniScope analyzes)
```

#### Summary Line

```
  Red Team: 7 files, 94 total issues detected
```

- `7 files` — how many `.ll` files existed and were analyzed
- `94 total issues` — sum of all issues across all files

#### Threshold Check

```
  ✅ Detection threshold met
```

If `total_issues < 10`, the test reports `⚠️ LOW detection count — investigate regressions`. This is a coarse sanity check, not a precise benchmark. For precise detection rates, use `make benchmark`.

### Drilling Into a Single File

To see the full OmniScope output for one test file:

```bash
./zig-out/bin/OmniScope corpus/red_team_test/red_team_bugs_O0.ll 2>&1
```

#### Startup Phase

```
info: [INFO] === OmniScope IR Analysis ===
info: [INFO] File: corpus/red_team_test/red_team_bugs_O0.ll
info: [INFO] Loaded: 35 functions
```

| Line | What It Means |
|------|---------------|
| `=== OmniScope IR Analysis ===` | Analysis session started |
| `File: ...` | Input LLVM IR file path |
| `Loaded: 35 functions` | Number of functions parsed from the IR |

#### Language Detection

```
info: [INFO] LANG-DETECT: module language = c, confidence = 100.0%, method = sampling
```

| Field | Meaning |
|-------|---------|
| `module language = c` | Dominant language in the module |
| `confidence = 100.0%` | How certain (sampling counts function name patterns) |
| `method = sampling` | `sampling` = statistical; `personality` = DWARF debug info |

The `sampling` method iterates all function names and counts language-specific patterns (`_ZN` for C++/Rust, `_R` for Rust v0, `Go.` for Go, etc.).

#### Pre-Pass Scanners

```
info: [INFO] MallocCheck: Analyzed functions, found 9 unchecked allocations
info: [INFO] IntegerOverflow: Analyzed functions, found 0 potential overflows
info: [INFO] BufferOverflow: No buffer overflow issues detected
info: [INFO] ReturnCheck: Analyzed functions, found 1 unchecked return values
info: [INFO] RustFfiFilter: analyzed 17 funcs, 0 findings (0 stack escapes)
```

| Scanner | What It Checks |
|---------|----------------|
| `MallocCheck` | `malloc()` return value not null-checked |
| `IntegerOverflow` | Arithmetic ops that may overflow |
| `BufferOverflow` | Array index out of bounds |
| `ReturnCheck` | Return values of FFI calls not checked |
| `RustFfiFilter` | Rust functions without FFI relevance (skipped) |

#### Cross-Language Edge Extraction

```
info: [INFO] CallGraph: extracted 15 cross-language edges
info: [INFO] CallGraph: built semantics CallGraph with 35 nodes, 63 edges for BFS traversal
```

| Field | Meaning |
|-------|---------|
| `15 cross-language edges` | Calls where caller and callee are in different languages |
| `35 nodes, 63 edges` | Call graph size for BFS reachability analysis |

Each edge records `(caller_name, callee_name, caller_lang, callee_lang)`. An edge is "cross-language" when `caller_lang != callee_lang`.

#### Danger Surface Pass

```
info: [INFO] [P1-1] DangerSurfacePass: 15 FFI, 0 allocs, 0 funcs | Phase1=0ms (args=0 rets=0 alias_traces=0) Phase2=0ms (cross_lang_free=0)
```

| Field | Meaning |
|-------|---------|
| `15 FFI` | Number of FFI boundary nodes in MemoryGraph |
| `Phase1` | Time spent tracing call args/rets through FFI boundaries |
| `Phase2` | Time spent scanning for cross-language free violations |
| `cross_lang_free=0` | Cross-language alloc/free mismatches found |

#### Pointer Ownership Analysis

```
info: [INFO] PointerOwnership: Source 1 (MemoryGraph) — 59 unfreed + 23 freed = 82 total nodes
info: [INFO] PointerOwnership: Source 2 (GlobalAllocTracker) — 9 records, 0 freed
info: [INFO] PointerOwnership: Source 3 (IR scan) added 32 frees — total now 32
info: [INFO] PointerOwnership: Pre-populated from MemoryGraph + GlobalAllocTracker + IR-scan — 59 allocs, 32 frees
```

This is the **three-source data fusion**:

| Source | What It Provides |
|--------|-----------------|
| Source 1: MemoryGraph | Allocation sites + freed status from upstream passes |
| Source 2: GlobalAllocTracker | Supplementary free tracking |
| Source 3: IR scan | Direct LLVM IR scan for `free`/`dealloc` call instructions (fallback) |

**How to interpret**: `59 unfreed` means 59 allocations were not matched with a corresponding free. These are potential memory leaks. The tool then applies filters (RAII, Meyers singleton, ref-counted containers) to reduce false positives.

#### Vulnerability Lines

```
info: [ERROR] VULNERABILITY OMI-001 [medium] [Confidence: MEDIUM]
info: [ERROR] Type: tainted_path_to_sink
info: [ERROR] Reason: Untrusted data flows to sensitive sink without validation
info: [ERROR] Path:
info: [ERROR]   [Sink] printf()
info: [ERROR]   [Source] main() - initial taint source
```

| Field | Meaning |
|-------|---------|
| `OMI-001` | Auto-incremented issue ID (unique per analysis run) |
| `[medium]` | Severity: `critical` > `high` > `medium` > `low` |
| `[Confidence: MEDIUM]` | `HIGH` / `MEDIUM` / `LOW` |
| `Type: tainted_path_to_sink` | Issue category (20+ types) |
| `Reason:` | Human-readable explanation of the problem |
| `Path:` | Data flow path from source to sink |

**How to locate the problem in YOUR code**:

**Step 1: Identify the function.** The output always includes a function name (mangled). For example:

```
info: [ERROR]   in _Z37bug_cpp_05_unique_ptr_callback_escapev
```

Demangle it:
```bash
# C++ (Itanium ABI)
echo "_Z37bug_cpp_05_unique_ptr_callback_escapev" | c++filt
# → bug_cpp_05_unique_ptr_callback_escape()

# Rust (v0)
rustfilt "_ZN4core3ptr13drop_in_place17h1234E"
# → core::ptr::drop_in_place<Type>
```

Then `grep` for the demangled name in your source:
```bash
grep -rn "bug_cpp_05_unique_ptr_callback_escape" src/
```

**Step 2: Use debug info for exact line.** If you compiled with `-g`, the JSON output includes `file` and `line`:

```bash
./zig-out/bin/OmniScope target.ll --json | jq '.issues[] | {function: .location.function, file: .location.file, line: .location.line}'
```

Without `-g`, you only get the function name. **Always compile with `-g` for actionable reports.**

**Step 3: Understand the issue type.** Each type points to a specific source pattern:

| Issue Type | What to look for in YOUR code |
|------------|-------------------------------|
| `memory_leak` | `malloc`/`new`/`Box::new` without matching `free`/`delete`/`drop` |
| `use_after_free` | Pointer used after `free()` or `Box::from_raw()` |
| `double_free` | Same pointer freed twice |
| `cross_lang_free_mismatch` | Allocated in Rust (`Box::into_raw`), freed in C (`free`) — or vice versa |
| `borrow_escape` | Stack pointer or `&mut` passed to FFI function that outlives the scope |
| `tainted_path_to_sink` | User input reaches `system()`/`exec()`/`printf()` without validation |
| `null_dereference` | Pointer used without null check after `malloc` or FFI call |
| `buffer_overflow` | Array access with unchecked index |
| `ffi_unsafe_call` | Calling an FFI function with wrong pointer type or lifetime |
| `format_string` | Non-literal format string in `printf`/`sprintf` |

**Step 4: Use `--sarif` for IDE integration.** SARIF output maps directly to source files and opens in VS Code / GitHub Code Scanning with inline annotations.

#### Performance Profile

```
info: Operation                           Calls   Total (ms)     Avg (us)     Max (us)
info: --------------------------------------------------------------------------------
info: init                                    1         7.77      7770.96      7770.96
info: analysis                                1         5.89      5888.63      5888.63
info: detect                                  2         3.75      1877.17      1909.58
info: total                                   1         7.78      7775.04      7775.04
```

| Phase | What Happens |
|-------|--------------|
| `init` | Load module, initialize data structures |
| `analysis` | Main function traversal + ownership tracking |
| `detect` | Violation detection (leaks, double-free, UAF) |
| `total` | End-to-end wall clock time |

#### Final Summary

```
info: [INFO] Analysis complete
info: [INFO] Functions processed: 35
info: [INFO] Facts generated: 54
info: [INFO] Time: 24ms
info: [INFO] Issues detected: 25
```

| Field | Meaning |
|-------|---------|
| `Functions processed` | Number of functions analyzed (after zone/noise filtering) |
| `Facts generated` | Number of facts emitted to the fact store (alias, taint, ownership) |
| `Time` | Total analysis wall clock time |
| `Issues detected` | Total issues found (this is what the red team counts) |

***

## Part 2: Blue Team — False Positive Audit

### What It Does

Runs OmniScope against the `corpus/{small,medium,ffi-dense}` test files and compares detected issue counts against expected in-scope thresholds. Measures **precision** — whether the tool over-reports.

### Run Log (Real Output)

```
╔════════════════════════════════════════════════════════════════╗
║                    BLUE TEAM TEST                             ║
║  Defensive: false positive audit on corpus                    ║
╚════════════════════════════════════════════════════════════════╝

── small/ (expected ≤13 in-scope issues)
  ✅ small/:        11 issues (expected ≤13, ok)
── medium/ (expected ≤20 in-scope issues)
  ✅ medium/:       16 issues (expected ≤20, ok)
── ffi-dense/ (expected ≤26 in-scope issues)
  ✅ ffi-dense/:    28 issues (expected ≤26, OVER)

────────────────────────────────────────────────────────
  Blue Team: 2 passed, 1 failed
  ⚠️  False positive regression detected
```

### Line-by-Line Interpretation

#### Directory Header

```
── small/ (expected ≤13 in-scope issues)
```

This tells you which corpus directory is being tested and the expected upper bound. The bounds come from `corpus/EXPECTED_RESULTS.md`:

| Directory | Expected In-Scope | Source |
|-----------|-------------------|--------|
| `small/` | 13 issues (4 files × ~3 issues each) | `EXPECTED_RESULTS.md:198` |
| `medium/` | 20 issues (1 file, 14 in-scope + 6 out-of-scope) | `EXPECTED_RESULTS.md:202` |
| `ffi-dense/` | 26 issues (4 files, 4+6+6+6 in-scope) | `EXPECTED_RESULTS.md:204-207` |

#### Pass/Fail Result

```
  ✅ small/:        11 issues (expected ≤13, ok)
```

| Symbol | Meaning |
|--------|---------|
| `✅` | Issue count is within expected bound |
| `❌` | Issue count exceeds expected bound (possible false positive regression) |

The threshold has a **margin of ~50%** above expected to account for legitimate detections that may vary across versions. The point is to catch **gross inflation**, not minor fluctuations.

#### Summary

```
  Blue Team: 2 passed, 1 failed
  ⚠️  False positive regression detected
```

If any directory fails, the overall blue team result is a warning. Investigate by running OmniScope on individual files:

```bash
./zig-out/bin/OmniScope corpus/ffi-dense/output/sqlite_binding.ll 2>&1
```

Compare the issue list against `corpus/EXPECTED_RESULTS.md` to identify which issues are real and which are false positives.

***

## Part 3: Contributor Reference — OmniScope Internals

> **Note**: This section is for OmniScope developers/contributors. If you're a **user** trying to find issues in your own code, see the [Vulnerability Lines](#vulnerability-lines) section above.

### Where Each Log Line Originates (OmniScope Source)

| Log Pattern | OmniScope Source File | Function |
|-------------|----------------------|----------|
| `=== OmniScope IR Analysis ===` | `src/main.zig` | `runSingleFileAnalysis` |
| `LANG-DETECT: module language` | `src/semantics/language_detector.zig` | `detectModuleLanguage` |
| `MallocCheck: Analyzed functions` | `src/pass/analysis/malloc_check.zig` | `run` |
| `IntegerOverflow: Analyzed functions` | `src/pass/analysis/issue/integer_overflow.zig` | `run` |
| `CallGraph: extracted N cross-language edges` | `src/pass/analysis/call_graph.zig` | `extractCrossLangEdges` |
| `DangerSurfacePass: N FFI` | `src/pass/analysis/danger_surface.zig` | `run` |
| `FFITypeMismatch: analyzed N calls` | `src/pass/analysis/ffi_type_mismatch.zig` | `run` |
| `PointerOwnership: Source 1` | `src/pass/analysis/pointer_ownership.zig` | `run` (line 265) |
| `VULNERABILITY OMI-NNN` | `src/diag/issue.zig` | `Issue.init` |
| `Issues detected: N` | `src/main.zig` | `emitOutput` |
| `GlobalAllocTracker: N memory leaks` | `src/semantics/global_alloc_tracker.zig` | `confirmLeaks` |

### Issue Type → Detection Pass (OmniScope Internals)

| Issue Type | Detection Pass |
|------------|---------------|
| `memory_leak` | `pointer_ownership.zig:detectViolations` |
| `cross_lang_free_mismatch` | `cpp_fp_reduction.zig:detectCrossLangAllocMismatch` |
| `use_after_free` | `cpp_fp_reduction.zig:detectUseAfterFree` |
| `double_free` | `cpp_fp_reduction.zig:detectDoubleFree` |
| `null_dereference` | `pointer_ownership.zig:detectNullDereferences` |
| `borrow_escape` | `pointer_ownership.zig:detectAsPtrBorrowEscape` |
| `tainted_path_to_sink` | `taint.zig` |
| `ffi_unsafe_call` | `ffi_boundary.zig:checkCallForFFI` |
| `buffer_overflow` | `buffer_overflow.zig` |
| `integer_overflow` | `issue/integer_overflow.zig` |
| `format_string` | `format_string.zig` |

### Corpus File → Source Code Mapping

| IR File | Source File | Bugs Injected |
|---------|-------------|---------------|
| `red_team_bugs_O0.ll` | `red_team_bugs.c` | Memory leak, UAF, double-free, null deref, format string |
| `ffi_boundary_bugs.ll` | `ffi_boundary_bugs.c` | FFI boundary violations, stack escape |
| `cross_lang_free_bugs.ll` | `cross_lang_free_bugs.c` | Rust→C, C→C++ free mismatches |
| `subtle_ffi_bugs.ll` | `subtle_ffi_bugs.c` | Subtle FFI patterns (realloc, partial cleanup) |
| `python_c_api_bugs.ll` | `python_c_api_bugs.c` | Python C API misuse (Py_DECREF, refcount) |
| `posix_ffi_bugs.ll` | `posix_ffi_bugs.c` | POSIX API misuse (FILE*, fd leak) |
| `cpp_ffi_simple.ll` | `cpp_ffi_simple.cpp` | C++ new/delete mismatch, RAII escape |
| `boundary_test.ll` | `boundary_test.c` | Null deref at FFI boundary, circular ownership |
| `stress_patterns.ll` | `stress_patterns.c` | 70 bugs: alloc leaks, cross-lang mismatches, chains |
| `sqlite_binding.ll` | `sqlite_binding.c` | SQLite resource leaks, dangling pointers |
| `openssl_wrapper.ll` | `openssl_wrapper.c` | OpenSSL ctx/bio/key leaks |
| `zlib_binding.ll` | `zlib_binding.c` | zlib stream leaks, double-free, UAF |
