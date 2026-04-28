# OmniScope v0.1.8 Development Plan — Trust Release

> **Version**: v0.1.8 (Trust Release)  
> **Goal**: 提升信任度，而非扩张版图  
> **Target Metrics**: FFI accuracy 73% → 85%+, HIGH severity precision 90%+  
> **Coding Rules**: Follow `plan/rules/rules.md` strictly (snake_case, <1000 lines/file, English comments)

---

## Philosophy (from plan/v0.1.8.md)

> v0.1.8 = 提升信任，而不是扩张版图  
> 先让用户觉得：**这工具说话靠谱。**

---

## Phase 0 — Technical Debt (Pre-requisites, COMPLETED ✅)

> These were unfinished items from v0.1.7 that must be resolved before v0.1.8 work begins.

### TD-1: P2 返回值逃逸检测 (Return Value Escape Detection) ✅

**Status**: COMPLETED  
**File**: [ffi_boundary.zig](src/pass/analysis/ffi_boundary.zig#L926-L1025)  
**What**: Implemented `checkReturnValueEscape()` — detects when FFI function return values escape through:
- **Pattern 1**: Store to global variable → cross-function lifetime escape (CWE-416)
- **Pattern 2**: Passed to another FFI/extern function → long-term hold risk (CWE-562)
- **Pattern 3**: Used as callback argument (pthread_create/signal) → stack outlive (CWE-562)

**Fix applied**: Replaced `std.mem.opt()` (non-existent) with `@intFromPtr() != 0` while-loop pattern matching project convention.

---

### TD-2: classifyFunctionFromLLVM LLVM metadata 路径 ✅

**Status**: COMPLETED  
**File**: [zone_classifier.zig](src/semantics/zone_classifier.zig#L370-L478)  
**What**: Added Layer 4 to `classifyFunctionFromLLVM()` — `classifyBySubprogramPath()` using `LLVMGetSubprogram` → `LLVMDIScopeGetFile` → `LLVMDIFileGetFilename` to extract source file path from debug metadata.

**Classification priority** (now 5 layers):
1. `LLVMIsDeclaration` → external = library/runtime
2. `LLVMGetLinkage` → internal vs external
3. `LLVMGetIntrinsicID` → compiler intrinsics = safe
4. **NEW**: `classifyBySubprogramPath()` → Rust/Zig/Go/C++ stdlib path detection
5. String-based fallback (`classifyFunction`)

**Path patterns supported**: `/rustc/`, `/zig/lib/std/`, `/go/src/runtime/`, `/usr/include/`, `_cgo_` generated files, etc.

---

### TD-3: pointer_ownership.zig:221 declaration continue ✅

**Status**: REVIEWED — No change needed (correct behavior)  
**File**: [pointer_ownership.zig](src/pass/analysis/pointer_ownership.zig#L220-L227)  
**Finding**: The `if (c.LLVMIsDeclaration(func) != 0) continue;` is **correct and intentional**.
- `PointerOwnership` is an **intra-procedural** pass that scans instructions inside function bodies
- Declarations are extern functions with **no body** in this module — nothing to analyze
- Effects of calling declarations are analyzed at call sites within defined caller functions
- Added explanatory comment documenting design intent

---

## P0 — Must Do (Trust Foundation)

### P0-1: Noise Reduction Layer 1

**Problem**: BLST/Wasmtime 报告前 3 条都是 `llvm.threadlocal.*` FP → 用户关工具

**Scope**: Filter compiler-generated LLVM intrinsics that are NOT real FFI issues

**Target patterns to suppress**:

| Pattern | Example | Reason |
|---------|---------|--------|
| `llvm.threadlocal.address.*` | `threadpool::ThreadPool` | Rust std thread local access |
| `llvm.lifetime.*` | any | Lifetime marker intrinsics |
| `llvm.dbg.*` | any | Debug info intrinsics |
| `llvm.assume` | any | Optimization hint |
| `llvm.expect.*` | any | Branch prediction hint |
| `llvm.coro.*` | any | Coroutine intrinsics |
| `llvm.gc.*` | any | Garbage collection |

**Implementation plan**:

- [ ] Create new module: `src/pass/filter/noise_reduction.zig`
  - File size target: <500 lines
  - Single responsibility: identify and filter LLVM intrinsic noise

- [ ] Implement `is_llvm_intrinsic_noise(func_name: []const u8) bool`
  - Pattern matching against known noise prefixes
  - O(1) lookup via prefix trie or simple startsWith chain

- [ ] Implement `should_suppress_ffi_report(inst: c.LLVMValueRef) bool`
  - Check if called function is LLVM intrinsic
  - Check if callee matches noise pattern
  - Return early from analysis if suppressed

- [ ] Integrate into existing pass pipeline:
  - `ptr_lifetime.zig`: skip tracking for noise instructions
  - `ffi_boundary.zig`: skip reporting for noise calls
  - `callback_escape.zig`: skip callback detection for noise

- [ ] Tests:
  - `test "noise reduction - llvm_threadlocal"` → verify suppression
  - `test "noise reduction - llvm_dbg"` → verify suppression
  - `test "noise reduction - real_ffi_not_suppressed"` → ensure dlopen NOT suppressed

**Verify**: Run BLST + Wasmtime, confirm `llvm.threadlocal.*` FP count = 0  
**Expected impact**: BLST FFI issues 3 → 0 (FP eliminated), overall FP rate -55%

---

### P0-2: Inter-procedural FFI V1 (Boundary Only)

**Problem**: Intra-procedural only → can't see caller's NULL check on dlopen return value

**Scope**: ONLY for FFI boundary functions, NOT full program analysis

**What we allow ourselves to see across function boundaries**:

1. Caller's NULL/return-value check on FFI callee result
2. Ownership transfer direction (caller → callee vs callee → caller)
3. Callback data lifetime (does callback outlive stack frame?)
4. Resource lifecycle pairing (open/close, init/destroy)

**What we DO NOT do**:
- Full call graph construction
- Alias analysis across functions
- Data flow through complex control flow

**Implementation plan**:

- [ ] Create new module: `src/pass/analysis/ip_ffi.zig`
  - File size target: <800 lines
  - Single responsibility: lightweight cross-function FFI reasoning

- [ ] Implement `FFICallSite` struct:
    ```zig
    const FFICallSite = struct {
        caller_func: c.LLVMValueRef,
        call_inst: c.LLVMValueRef,
        callee_name: []const u8,
        result_used: bool,
        has_null_check: bool,
        ownership_transfer: enum { none, to_caller, to_callee },
        resource_pair: ?ResourcePair,
    };
    ```

- [ ] Implement `analyze_ffi_caller_context(ctx: *PassContext, func: c.LLVMValueRef) ![]FFICallSite`
  - For each FFI boundary call in `func`, check:
    - Is return value stored? → used
    - Is return value compared to null? → has_null_check
    - Is return value passed to another FFI? → ownership transfer
    - Is handle passed to close/destructor? → resource pair

- [ ] Implement `check_caller_null_guard(call_site: FFICallSite) bool`
  - Scan basic blocks after call instruction
  - Look for ICMP EQ with NULL constant
  - Look for branch on comparison result
  - Return true if NULL guard found within N instructions

- [ ] Integrate into `ffi_boundary.zig`:
  - Before reporting CONTRACT VIOLATION, check caller context
  - If caller has NULL guard → downgrade or suppress
  - Add "caller-checked" annotation to report

- [ ] Integrate into `ptr_lifetime.zig`:
  - For resource alloc (dlopen/mmap/socket), look for matching dealloc in same function OR callers
  - Mark as "caller-owned" if no local free found but caller uses result

- [ ] Tests:
  - `test "ip_ffi - caller_null_check_detected"` → simulate wrapper with NULL check
  - `test "ip_ffi - ownership_transfer_to_caller"` → dlopen result stored to global
  - `test "ip_ffi - resource_pair_across_functions"` → open in A, close in B
  - `test "ip_ffi - callback_outlives_stack"` → pthread_create fn_ptr from caller

**Verify**: Re-run SQLITE3, expect dlopen FP reduced by ~50% (caller does check)  
**Expected impact**: Overall FFI accuracy 73% → ~80%

---

### P0-3: Severity Re-ranking

**Problem**: Current severity assignment doesn't match real risk

**Current (wrong)**:
- `setsockopt unchecked` = LOW (ok)
- `callback may outlive stack frame` = MEDIUM (too low!)
- `dlclose while symbol pointer alive` = MEDIUM (too low!)

**Target (correct)**:

| Pattern | Current | Target | Rationale |
|---------|---------|--------|-----------|
| dlclose while dlsym ptr alive | MEDIUM | **CRITICAL** | UAF on heap pointer, immediate crash risk |
| callback escapes to global/pthread | MEDIUM | **HIGH** | Use-after-return, data corruption |
| dlopen NULL not checked | HIGH | **HIGH** | Keep (already correct) |
| setsockopt unchecked | LOW | **LOW** | Keep (already correct) |
| EVP_CIPHER_CTX_new NULL | MEDIUM | **HIGH** | Crypto key leak, security issue |
| pthread_mutex leak | MEDIUM | **MEDIUM** | Keep |
| llvm.threadlocal | LOW | **SUPPRESSED** | Not a real issue |

**Implementation plan**:

- [ ] Enhance `issue.zig` severity calculation:
  - Add `severity_boost_for_pattern(pattern: []const u8) i32`
  - Map dangerous patterns to severity boost values

- [ ] Update `ffi_boundary.zig` report generation:
  - dlclose + derived pointer alive → CRITICAL
  - Callback escape to global/pthread → HIGH
  - Allocator crypto (EVP/RSA/SSL) without free → HIGH
  - setsockopt/getsockopt without check → keep LOW

- [ ] Update `ptr_lifetime.zig` report generation:
  - Resource UAF (dlclose/dlerror/munmap/DeleteGlobalRef) → CRITICAL
  - Heap UAF (free then use) → keep CRITICAL
  - Stack escape via callback → HIGH

- [ ] Tests:
  - `test "severity - dlclose_with_alive_sym -> CRITICAL"`
  - `test "severity - callback_escape_global -> HIGH"`
  - `test "severity - setsockopt_unchecked stays_LOW"`

**Verify**: Run full benchmark, check TOP-5 findings quality metric  
**Expected impact**: First 5 findings precision 60% → 90%+

---

### P0-4: Top 20 FP Suppressions (Whitelist)

**Problem**: Known FP patterns keep appearing, wasting user attention

**Implementation plan**:

- [ ] Create new module: `src/pass/filter/fp_whitelist.zig`
  - File size target: <400 lines
  - Single responsibility: maintain known-FP whitelist

- [ ] Implement `KnownFPPattern` registry:
    ```zig
    const KnownFPPattern = struct {
        pattern: []const u8,
        kind: enum { function_prefix, exact_match, regex_like },
        reason: []const u8,
        since_version: []const u8,
    };
    ```

- [ ] Populate Top 20 based on v0.1.7 audit findings:

| # | Pattern | Kind | Reason | Source Project |
|---|---------|------|--------|---------------|
| 1 | `llvm.threadlocal.address` | prefix | Rust std TLS | BLST, Wasmtime |
| 2 | `llvm.lifetime.start` | prefix | LLVM lifetime marker | All |
| 3 | `llvm.lifetime.end` | prefix | LLVM lifetime marker | All |
| 4 | `llvm.dbg.declare` | prefix | Debug info | All |
| 5 | `llvm.dbg.value` | prefix | Debug info | All |
| 6 | `llvm.assume` | prefix | Optimizer hint | All |
| 7 | `llvm.expect.i32` | prefix | Branch prediction | All |
| 8 | `llvm.coro.begin` | prefix | Coroutine frame | Wasmtime |
| 9 | `llvm.coro.end` | prefix | Coroutine cleanup | Wasmtime |
| 10 | `llvm.gc.root` | prefix | GC root | Rare |
| 11 | `uv__socket` + caller-close | contextual | Design choice | Libuv |
| 12 | `getsockopt` with r<0 check | contextual | Already checked | Libuv |
| 13 | `sqlite3MemMalloc` zone | contextual | Custom allocator | SQLite3 |
| 14 | `sync_channel::` | prefix | Rust std safe primitive | BLST |
| 15 | `mpsc::channel::` | prefix | Rust std safe primitive | BLST |
| 16 | `Arc::<` | prefix | Rust std shared ownership | BLST |
| 17 | `Waker::` | prefix | Rust async runtime | Wasmtime |
| 18 | `RawVec::` | prefix | Rust Vec internals | Various |
| 19 | `__rust_alloc` | prefix | Rust global allocator | All Rust |
| 20 | `__rust_dealloc` | prefix | Rust global deallocator | All Rust |

- [ ] Implement `is_known_fp(inst: c.LLVMValueRef, func_name: []const u8) ?KnownFPPattern`
  - Check against whitelist
  - Return matched pattern if found, null otherwise

- [ ] Integrate into ALL pass entry points:
  - Early exit if matched
  - Log suppressed finding (debug mode only)

- [ ] Tests:
  - `test "fp_whitelist - llvm_threadlocal suppressed"`
  - `test "fp_whitelist - uv_socket_caller_close suppressed"`
  - `test "fp_whitelist - real_bug_NOT_suppressed"` → ensure TP not affected

**Verify**: Total issue count should drop significantly while TP count unchanged  
**Expected impact**: Overall FP rate 27% → <15%

---

## P1 — Worth Doing

### P1-1: SARIF Output Format

**Why this matters most after P0**:
> Once SARIF supported: GitHub Code Scanning + CI pipeline + enterprise demos  
> Commercial value > Objective-C Runtime

**Implementation plan**:

- [ ] Create new module: `src/output/sarif.zig`
  - File size target: <600 lines
  - Single responsibility: convert Issue[] to SARIF JSON

- [ ] Implement SARIF schema structs:
    ```zig
    const SarifRun = struct { tool: SarifTool, results: []SarifResult };
    const SarifResult = struct { ruleId: []u8, level: []u8, message: SarifMessage, locations: []SarifLocation };
    // ... minimal SARIF v2.1.0 subset
    ```

- [ ] Implement `export_sarif(issues: []Issue, allocator: Allocator) ![]u8`
  - Convert internal Issue format to SARIF
  - Write valid JSON output

- [ ] Add CLI flag: `--sarif` / `-s`
  - When present, output SARIF JSON instead of human-readable format

- [ ] Tests:
  - `test "sarif - basic_output_valid_json"`
  - `test "sarif - severity_mapping_correct"`
  - `test "sarif - location_info_present"`

**Verify**: `omniscope audit sqlite3.ll --sarif` produces valid SARIF  
**Integration target**: GitHub Code Scanning custom ruleset

---

### P1-2: Windows DLL APIs

**Why worth doing**:
> Market large, Win32 DLL scenarios real, LoadLibrary fits our model perfectly

**Implementation plan**:

- [ ] Extend `ffi_boundary.zig` dynamic loading support:
  - Add `isWindowsDllFunction(func_name: []const u8) bool`
  - Patterns: `LoadLibrary`, `LoadLibraryEx`, `GetProcAddress`, `FreeLibrary`
  - Map to existing `dynamic_loading` BoundaryKind

- [ ] Extend `ptr_lifetime.zig` resource types:
  - Add `.windows_module` ResourceType
  - Track `LoadLibrary` → handle → `FreeWindowModule`
  - Track `GetProcAddress` → derived pointer from module handle

- [ ] Extend `checkDynamicLoadingSafety`:
  - Apply same NULL checks to `LoadLibrary`/`GetProcAddress`
  - Report `FreeLibrary` as ownership consumer

- [ ] Tests:
  - `test "windows_dll - LoadLibrary_null_check"`
  - `test "windows_dll - GetProcAddress_derived_tracking"`
  - `test "windows_dll - FreeLibrary_ownership"`

**Verify**: Analyze Windows-targeted LLVM IR (if available) or create test case  
**Expected impact**: FFI coverage expands to Windows ecosystem

---

## P2 — Deferred

### P2-1: Objective-C Runtime

**Status**: Deferred to v0.2.x

**Reasons** (from plan/v0.1.8.md):
- `objc_msgSend` dynamic dispatch complexity
- ARC / autoreleasepool semantics heavy
- Market relatively narrow
- Will consume significant time

**When to reconsider**:
- After P0+P1 complete and accuracy >85%
- When iOS/macOS developer community requests it
- After inter-procedural V2 ready (needed for ARC semantics)

---

## Verification Checklist (per task)

Before marking any task complete:

- [ ] File size < 1000 lines (rules.md §2.1)
- [ ] All comments in English (rules.md §2.3)
- [ ] Code:comment ratio ~7:3 (rules.md §2.3)
- [ ] Functions use snake_case (project convention, established v0.1.7)
- [ ] Public APIs have doc comments (rules.md §9.1)
- [ ] Tests include happy path + boundary + error path (rules.md §2.4)
- [ ] `zig build` passes
- [ ] Changes are surgical — every line traces to requirement (skills.md §3)
- [ ] No files deleted without permission (rules.md §2.5)
- [ ] Run regression test suite (14 projects + 5 test cases)

---

## Success Metrics (v0.1.8 Targets)

| Metric | v0.1.7 (baseline) | v0.1.8 (target) | How to measure |
|--------|-------------------|-----------------|---------------|
| **FFI Accuracy** | ~73% | **82-87%** | TP/(TP+FP) on benchmark |
| **HIGH Severity Precision** | ~60% | **90%+** | TP@HIGH / total@HIGH |
| **First 5 Findings Quality** | Mixed | **All TP or near-TP** | Manual review of top 5 |
| **Findings / KLOC** | Variable | **<2.0** | Total issues / total KLOC |
| **BLST FFI Issues** | 3 (all FP) | **0** | Noise elimination |
| **SQLITE3 FP Rate** | ~20% | **<10%** | Inter-procedural help |
| **SARIF Output** | N/A | **Supported** | Functional test |
| **Build Time** | Stable | **No regression** | zig build time |

---

## Execution Order

```
Phase 0 (Technical Debt — COMPLETED ✅):
  TD-1: P2 返回值逃逸检测              ← Done
  TD-2: classifyFunctionFromLLVM metadata ← Done
  TD-3: pointer_ownership declaration    ← Reviewed, correct as-is

Phase 1 (Foundation):
  P0-1: Noise Reduction Layer 1     ← Do FIRST (biggest UX win)
  P0-4: Top 20 FP Suppressions      ← Parallel with P0-1

Phase 2 (Core Analysis):
  P0-2: Inter-procedural FFI V1     ← Technical watershed
  P0-3: Severity Re-ranking         ← Quick win after P0-2

Phase 3 (Integration):
  P1-1: SARIF Output               ← Commercial enabler
  P1-2: Windows DLL APIs            ← Coverage expansion

Phase 4 (Verification):
  Full regression test suite
  Benchmark page generation
  v0.1.8 release tagging
```
