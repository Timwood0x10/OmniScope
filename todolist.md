# OmniScope v0.1.8 Development Plan — Trust Release

> **Version**: v0.1.8 (Trust Release)
> **Goal**: 提升信任度，而非扩张版图
> **Target Metrics**: FFI accuracy 73% → 85%+, HIGH severity precision 90%+
> **Coding Rules**: Follow `plan/rules/rules.md` strictly (snake\_case, <1000 lines/file, English comments)

***

## Strategic Positioning (from plan/roadmap/RoadMap.md)

> **先做可信的小而强，再做全面的大平台。**
>
> Product tagline: *Detect memory and lifecycle risks at unsafe language boundaries.*
> Alt: *Audit Rust/C/Zig/Go integrations and closed-source native libraries.*

**If only one thing**: Make `omniscope audit sqlite3.c --sarif` work and ship a GitHub demo.
This is worth more than adding 10 more rules.

***

## Philosophy

> v0.1.8 = 提升信任，而不是扩张版图
> 先让用户觉得：**这工具说话靠谱。**

***

## Phase 0 — Technical Debt (Pre-requisites, COMPLETED ✅)

> These were unfinished items from v0.1.7 that must be resolved before v0.1.8 work begins.

### TD-1: P2 返回值逃逸检测 (Return Value Escape Detection) ✅

**Status**: COMPLETED\
**File**: [ffi\_boundary.zig](src/pass/analysis/ffi_boundary.zig#L926-L1025)\
**What**: Implemented `checkReturnValueEscape()` — detects when FFI function return values escape through:

- **Pattern 1**: Store to global variable → cross-function lifetime escape (CWE-416)
- **Pattern 2**: Passed to another FFI/extern function → long-term hold risk (CWE-562)
- **Pattern 3**: Used as callback argument (pthread\_create/signal) → stack outlive (CWE-562)

**Fix applied**: Replaced `std.mem.opt()` (non-existent) with `@intFromPtr() != 0` while-loop pattern matching project convention.

***

### TD-2: classifyFunctionFromLLVM LLVM metadata 路径 ✅

**Status**: COMPLETED\
**File**: [zone\_classifier.zig](src/semantics/zone_classifier.zig#L370-L478)\
**What**: Added Layer 4 to `classifyFunctionFromLLVM()` — `classifyBySubprogramPath()` using `LLVMGetSubprogram` → `LLVMDIScopeGetFile` → `LLVMDIFileGetFilename` to extract source file path from debug metadata.

**Classification priority** (now 5 layers):

1. `LLVMIsDeclaration` → external = library/runtime
2. `LLVMGetLinkage` → internal vs external
3. `LLVMGetIntrinsicID` → compiler intrinsics = safe
4. **NEW**: `classifyBySubprogramPath()` → Rust/Zig/Go/C++ stdlib path detection
5. String-based fallback (`classifyFunction`)

**Path patterns supported**: `/rustc/`, `/zig/lib/std/`, `/go/src/runtime/`, `/usr/include/`, `_cgo_` generated files, etc.

***

### TD-3: pointer\_ownership.zig:221 declaration continue ✅

**Status**: REVIEWED — No change needed (correct behavior)\
**File**: [pointer\_ownership.zig](src/pass/analysis/pointer_ownership.zig#L220-L227)\
**Finding**: The `if (c.LLVMIsDeclaration(func) != 0) continue;` is **correct and intentional**.

- `PointerOwnership` is an **intra-procedural** pass that scans instructions inside function bodies
- Declarations are extern functions with **no body** in this module — nothing to analyze
- Effects of calling declarations are analyzed at call sites within defined caller functions
- Added explanatory comment documenting design intent

***

## P0 — Must Do (Trust Foundation)

### P0-1: Noise Reduction Layer 1

**Problem**: BLST/Wasmtime 报告前 3 条都是 `llvm.threadlocal.*` FP → 用户关工具

**Scope**: Filter compiler-generated LLVM intrinsics that are NOT real FFI issues

**Target patterns to suppress**:

| Pattern                      | Example                                | Reason                                  |
| ---------------------------- | -------------------------------------- | --------------------------------------- |
| `llvm.threadlocal.address.*` | `threadpool::ThreadPool`               | Rust std thread local access            |
| `llvm.lifetime.*`            | any                                    | Lifetime marker intrinsics              |
| `llvm.dbg.*`                 | any                                    | Debug info intrinsics                   |
| `llvm.assume`                | any                                    | Optimization hint                       |
| `llvm.expect.*`              | any                                    | Branch prediction hint                  |
| `llvm.coro.*`                | any                                    | Coroutine intrinsics                    |
| `llvm.gc.*`                  | any                                    | Garbage collection                      |
| Rust stdlib synthetic calls  | `__rust_*`, `sync_channel::`, `mpsc::` | Rust std safe primitives (not real FFI) |

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

**Verify**: Run BLST + Wasmtime, confirm `llvm.threadlocal.*` FP count = 0\
**Expected impact**: BLST FFI issues 3 → 0 (FP eliminated), overall FP rate -55%

***

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
    - Is return value compared to null? → has\_null\_check
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
  - `test "ip_ffi - callback_outlives_stack"` → pthread\_create fn\_ptr from caller

**Verify**: Re-run SQLITE3, expect dlopen FP reduced by \~50% (caller does check)\
**Expected impact**: Overall FFI accuracy 73% → \~80%

***

### P0-3: Severity Re-ranking

**Problem**: Current severity assignment doesn't match real risk

**Current (wrong)**:

- `setsockopt unchecked` = LOW (ok)
- `callback may outlive stack frame` = MEDIUM (too low!)
- `dlclose while symbol pointer alive` = MEDIUM (too low!)

**Target (correct)**:

| Pattern                            | Current | Target         | Rationale                                    |
| ---------------------------------- | ------- | -------------- | -------------------------------------------- |
| dlclose while dlsym ptr alive      | MEDIUM  | **CRITICAL**   | UAF on heap pointer, immediate crash risk    |
| callback escapes to global/pthread | MEDIUM  | **HIGH**       | Use-after-return, data corruption            |
| dlopen NULL not checked            | HIGH    | **HIGH**       | Keep (already correct)                       |
| setsockopt unchecked               | LOW     | **LOW**        | Keep (already correct)                       |
| EVP\_CIPHER\_CTX\_new NULL         | MEDIUM  | **HIGH**       | Crypto key leak, security issue              |
| pthread\_mutex leak                | MEDIUM  | **MEDIUM**     | Keep                                         |
| fork in multithreaded context      | LOW     | **HIGH**       | At-fork handler missing, deadlock/corruption |
| llvm.threadlocal                   | LOW     | **SUPPRESSED** | Not a real issue                             |

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

**Verify**: Run full benchmark, check TOP-5 findings quality metric\
**Expected impact**: First 5 findings precision 60% → 90%+

***

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

| #  | Pattern                     | Kind       | Reason                    | Source Project |
| -- | --------------------------- | ---------- | ------------------------- | -------------- |
| 1  | `llvm.threadlocal.address`  | prefix     | Rust std TLS              | BLST, Wasmtime |
| 2  | `llvm.lifetime.start`       | prefix     | LLVM lifetime marker      | All            |
| 3  | `llvm.lifetime.end`         | prefix     | LLVM lifetime marker      | All            |
| 4  | `llvm.dbg.declare`          | prefix     | Debug info                | All            |
| 5  | `llvm.dbg.value`            | prefix     | Debug info                | All            |
| 6  | `llvm.assume`               | prefix     | Optimizer hint            | All            |
| 7  | `llvm.expect.i32`           | prefix     | Branch prediction         | All            |
| 8  | `llvm.coro.begin`           | prefix     | Coroutine frame           | Wasmtime       |
| 9  | `llvm.coro.end`             | prefix     | Coroutine cleanup         | Wasmtime       |
| 10 | `llvm.gc.root`              | prefix     | GC root                   | Rare           |
| 11 | `uv__socket` + caller-close | contextual | Design choice             | Libuv          |
| 12 | `getsockopt` with r<0 check | contextual | Already checked           | Libuv          |
| 13 | `sqlite3MemMalloc` zone     | contextual | Custom allocator          | SQLite3        |
| 14 | `sync_channel::`            | prefix     | Rust std safe primitive   | BLST           |
| 15 | `mpsc::channel::`           | prefix     | Rust std safe primitive   | BLST           |
| 16 | `Arc::<`                    | prefix     | Rust std shared ownership | BLST           |
| 17 | `Waker::`                   | prefix     | Rust async runtime        | Wasmtime       |
| 18 | `RawVec::`                  | prefix     | Rust Vec internals        | Various        |
| 19 | `__rust_alloc`              | prefix     | Rust global allocator     | All Rust       |
| 20 | `__rust_dealloc`            | prefix     | Rust global deallocator   | All Rust       |

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

**Verify**: Total issue count should drop significantly while TP count unchanged\
**Expected impact**: Overall FP rate 27% → <15%

***

## P1 — Worth Doing

### P1-1: SARIF Output Format

**Why this matters most after P0**:

> Once SARIF supported: GitHub Code Scanning + CI pipeline + enterprise demos\
> Commercial value > Objective-C Runtime

**Implementation plan**:

- [ ] Create new module: `src/output/sarif.zig`
  - File size target: <600 lines
  - Single responsibility: convert Issue\[] to SARIF JSON
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

**Verify**: `omniscope audit sqlite3.ll --sarif` produces valid SARIF\
**Integration target**: GitHub Code Scanning custom ruleset

***

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

**Verify**: Analyze Windows-targeted LLVM IR (if available) or create test case\
**Expected impact**: FFI coverage expands to Windows ecosystem

***

## P2 — Deferred

### P2-1: C Language Series Adaptation for PtrLifetimePass

**Problem**: PtrLifetimePass generates 64-89% false positives on C projects due to C API patterns.

**Status**: **IMPLEMENTED** ✅ (isNonPointerReturnType check)

**Root Cause Analysis**:
- C API `int func(ptr out_param)` pattern: function uses alloca to store output pointer
- PtrLifetimePass incorrectly flags alloca as "returning stack address"
- Rust projects: 95% accuracy | C projects: 27-36% accuracy

**Fix Applied**:
```zig
fn isNonPointerReturnType(ret_inst: c.LLVMValueRef) bool {
    const ret_value = c.LLVMGetOperand(ret_inst, 0);
    if (ret_value == null) return false;
    const value_type = c.LLVMTypeOf(ret_value);
    if (value_type == null) return false;
    return c.LLVMGetTypeKind(value_type) != c.LLVMPointerTypeKind;
}
```

**Results**:
- sqlite3: 2157 → 915 issues (57% reduction)
- curl8: 698 → 277 issues (60% reduction)
- libuv150: 493 → 222 issues (55% reduction)
- wasmtime_test: 407 → 407 (unchanged, Rust code is clean)

**C API Patterns to Handle**:

| Pattern | Example | Current Behavior | Status |
|---------|---------|------------------|--------|
| `int func(ptr out)` | `sqlite3_status64` | Suppressed ✅ | DONE |
| `void func(ptr out)` | `getsockopt` | Suppressed ✅ | DONE |
| `int func(ptr in, ptr out)` | `strerror_r` | Suppressed ✅ | DONE |
| `set_*_ip/_addr/_port` | `set_local_ip` | Suppressed ✅ | DONE |
| `ptr func(ptr ctx)` | Rust closures | Kept detection ✅ | DONE |

**Results**:
- sqlite3: 2157 → 915 issues (57% reduction)
- curl8: 698 → 277 issues (60% reduction)
- libuv150: 493 → 222 issues (55% reduction)
- wasmtime_test: 407 → 407 (unchanged, Rust code is clean)

**Remaining Work**:
- SQLite3 double_free (225): SQLite uses reference counting, not true double-free
- SQLite3 invalid_free (253): SQLite internal memory management patterns
- Rust drop_in_place patterns: May be true issues (need manual review)

**Implementation Status**: ✅ P2-1 MOSTLY COMPLETE
- [x] `isNonPointerReturnType()` - filters C API non-pointer return patterns
- [x] `isOutputParamSetter()` - identifies output parameter setters
- [ ] SQLite3/Rust specific patterns - require domain knowledge to tune

**Next**: P2-2 Universal Pattern Framework for further improvements

***

### P2-2: Universal Pattern Framework

**Goal**: Make PtrLifetimePass work well across all languages (C/C++/Rust/Zig/Go)

**Universal Detection Rules**:

| Rule | Logic | Suppress Condition |
|------|-------|-------------------|
| RETURN_STACK | ret alloca | Function returns non-pointer AND has pointer params |
| BORROW_ESCAPE | alloca passed to FFI | Function is C API pattern OR returns non-pointer |
| STACK_ESCAPE | stack ptr to global | Pointer derived from function parameter |
| PARAM_PTR_RETURN | param ptr returned | C API output parameter pattern |

**Implementation Plan**:

- [ ] Refactor `ptr_lifetime.zig` detection logic:
  - Extract universal detection into separate functions
  - Add suppression condition checking
- [ ] Implement `shouldSuppressBasedOnFunctionSignature(func, return_type, param_types)`:
  - Universal rules that apply to all languages
  - Language-specific overrides possible
- [ ] Implement `isParameterDerivedPointer(ptr, func)`:
  - Check if pointer is derived from function parameter
  - If so, suppress certain warnings (legitimate aliasing)
- [ ] Add suppression logging (debug mode):
  - Log why each detection was suppressed
  - Help users understand tool behavior

**Verify**: Cross-language benchmark (sqlite3 C, abseil C++, wasmtime Rust, gnark Go)
**Expected impact**: All languages achieve 80%+ accuracy

***

### P2-3: Inter-Procedural Lifecycle Analysis (Long-term)

**Goal**: Track pointer lifecycle across function boundaries

**Why this matters**:
- Current: Intra-procedural only → can't see caller's NULL check
- Problem: dlopen returns NULL → caller must check → we can't see this
- Impact: ~20% FP from missing caller context

**Scope (V1 — Lightweight)**:
- ONLY track FFI boundary functions (dlopen, mmap, socket, etc.)
- Do NOT do full call graph construction
- Focus on: NULL checks, ownership transfer, resource pairing

**Implementation Plan**:

- [ ] Create `src/pass/analysis/ip_lifecycle.zig` (<800 lines)
- [ ] Implement `FFICallSite` analysis:
  ```zig
  const FFICallSite = struct {
      caller_func: c.LLVMValueRef,
      call_inst: c.LLVMValueRef,
      callee_name: []const u8,
      has_null_check: bool,
      ownership_direction: enum { to_caller, to_callee },
  };
  ```
- [ ] Implement `analyzeCallerContext(func) []FFICallSite`:
  - For each FFI call in func, check:
    - Return value compared to NULL?
    - Return value stored to global?
    - Return value passed to another FFI?
- [ ] Integrate into `ptr_lifetime.zig`:
  - Before reporting RESOURCE_UAF, check if caller has NULL guard
  - Downgrade to warning if caller checks NULL
- [ ] Tests:
  - `test "ip_lifecycle - dlopen_null_check_detected"`
  - `test "ip_lifecycle - ownership_transfer_tracked"`
  - `test "ip_lifecycle - resource_pair_across_functions"`

**Verify**: SQLite3 dlopen FP reduced by ~50%
**Expected impact**: Overall accuracy 73% → 85%

***

### P2-4: Objective-C Runtime

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

***

## Verification Checklist (per task)

Before marking any task complete:

- [ ] File size < 1000 lines (rules.md §2.1)
- [ ] All comments in English (rules.md §2.3)
- [ ] Code:comment ratio \~7:3 (rules.md §2.3)
- [ ] Functions use snake\_case (project convention, established v0.1.7)
- [ ] Public APIs have doc comments (rules.md §9.1)
- [ ] Tests include happy path + boundary + error path (rules.md §2.4)
- [ ] `zig build` passes
- [ ] Changes are surgical — every line traces to requirement (skills.md §3)
- [ ] No files deleted without permission (rules.md §2.5)
- [ ] Run regression test suite (14 projects + 5 test cases)

***

## Success Metrics (v0.1.8 Targets)

| Metric                       | v0.1.7 (baseline) | v0.1.8 (target)       | How to measure            |
| ---------------------------- | ----------------- | --------------------- | ------------------------- |
| **FFI Accuracy (Rust)**      | ~60%              | **95%+**              | TP/(TP+FP) on wasmtime    |
| **FFI Accuracy (C)**         | ~30%              | **65%+**              | TP/(TP+FP) on sqlite3     |
| **Overall Accuracy**          | ~73%              | **80%+**              | TP/(TP+FP) on benchmark   |
| **HIGH Severity Precision**  | ~60%              | **90%+**              | TP\@HIGH / total\@HIGH    |
| **First 5 Findings Quality** | Mixed             | **All TP or near-TP** | Manual review of top 5    |
| **Findings / KLOC**          | Variable          | **<2.0**              | Total issues / total KLOC |
| **BLST FFI Issues**          | 3 (all FP)        | **0**                 | Noise elimination         |
| **C BORROW_ESCAPE FP Rate**  | ~70%              | **<30%**              | After C API pattern fix    |
| **SARIF Output**             | N/A               | **Supported**         | Functional test           |
| **Build Time**               | Stable            | **No regression**     | zig build time            |

### v0.1.8 Release Gate

All of the above must pass before tagging v0.1.8.

***

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

***

## Future Roadmap (from plan/roadmap/RoadMap.md)

### Phase 2: v0.1.9 — Knowledge Release

**Goal**: 让 OmniScope 开始具备"专家知识库"。

**OmniScope-Signatures.db** — 记录常见 FFI contract：

| Function            | Contract                   |
| ------------------- | -------------------------- |
| `sqlite3_open`      | out-param + nullable       |
| `pthread_create`    | callback escapes           |
| `EVP_*_new`         | must\_free + nullable      |
| `BIO_new`           | must\_free                 |
| `LoadLibrary`       | handle lifecycle           |
| `PyGILState_Ensure` | thread state contract      |
| `JNI FindClass`     | nullable + exception state |

**用户自定义规则（轻量）**:

```
library: vendor_sdk
function: sdk_open
returns: handle
must_call: sdk_close
nullable: true
```

**Target**: Accuracy 88%+, 商业价值 **高**

***

### Phase 3: v0.2.0 — Binary Bridge Release

**Goal**: 进入闭源库 / 供应链安全场景。

**Binary Frontend MVP**: `.so` / `.dll`

- imports / exports
- allocator/free symbols
- dangerous API surface
- callback exports
- dynamic loading graph

**RetDec / Binary Lifting** (优先于 Ghidra 集成):

```
binary → LLVM IR → existing OmniScope passes
```

最大化复用现有资产。

**Usage**: `omniscope audit vendor.dll src/`

**Target**: Accuracy 88%+, 商业价值 **很高**

***

### Phase 4: v0.3.x — Hybrid Deep Analysis

按需触发，而不是默认全开。

**angr Validator** (仅对 HIGH findings):

- integer overflow reachability
- bounds bypass path
- use-after-free path feasibility

**Ghidra Side Evidence** (仅做):

- type hints
- CFG complexity
- hidden free/global writes

**Target**: Accuracy 90%+, 企业级

***

## Metrics Roadmap (Realistic)

| Version | Core Goal   | Accuracy | Commercial Value |
| ------- | ----------- | -------- | ---------------- |
| v0.1.8  | 信任建立        | 85%+     | 中                |
| v0.1.9  | 知识库化        | 88%+     | 高                |
| v0.2.0  | Binary 审计   | 88%+     | 很高               |
| v0.3.x  | Hybrid 深度验证 | 90%+     | 企业级              |

***

## Explicitly Deferred (Do NOT do now)

- **Objective-C Runtime** → v0.3+: 复杂、市场窄、ROI 低
- **全程序复杂数据流框架重写** → 别做，继续围绕 FFI boundary 做定向分析

***

## Development Principle (from RoadMap)

> 你现在已经过了"能不能做出来"的阶段。
> 新的开发计划应该围绕：
>
> **可信度 → 知识库 → Binary 扩张 → Hybrid 深挖**
>
> 而不是继续线性堆 feature。

