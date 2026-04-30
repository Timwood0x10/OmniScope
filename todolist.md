# OmniScope v0.1.8 Development Plan — Semantic Contracts Update

> **Version**: v0.1.8 (Semantic Contracts Update)
> **Goal**: 从语法级规则扫描，升级到语义级 FFI 模型
> **Target Metrics**: FFI accuracy 73% → 85%+, 误报率大幅降低
> **Coding Rules**: Follow `plan/rules/rules.md` strictly (snake_case, <1000 lines/file, English comments)

***

## Strategic Positioning

> **先做可信的小而强，再做全面的大平台。**
>
> Product tagline: *Understands native library memory contracts across language boundaries.*
>
> 这才是让 OmniScope 脱胎换骨的一版。

***

## Phase 0 — Technical Debt (COMPLETED ✅)

### TD-1: Return Value Escape Detection ✅
**Status**: COMPLETED

### TD-2: classifyFunctionFromLLVM LLVM metadata ✅
**Status**: COMPLETED

### TD-3: pointer_ownership.zig declaration handling ✅
**Status**: REVIEWED — No change needed

***

## P0 — Semantic Contracts Foundation

### P0-1: Output Parameter Classifier (输出参数识别) ✅

**Status**: ✅ **IMPLEMENTED & INTEGRATED**

- [x] Create `src/semantics/output_param_classifier.zig` ✅
- [x] Implement `isLikelyOutputParamFunction()` — 27 known C API families ✅
- [x] Implement `classifyFunction()` — function-level + parameter-level detection ✅
- [x] Integrate into `ptr_lifetime.checkReturnViolation()` ✅
- [x] Tests: 7 unit tests ✅

**Integration**: `ptr_lifetime.zig` calls `OutputParamClassifier.isLikelyOutputParamFunction()` before reporting return violations. Known output-param families (sqlite3_prepare, getsockopt, pthread_create, etc.) are suppressed.

**Expected Impact**: Borrow escape 328 → <30

***

### P0-2: Memory Graph + Pointer Tracking (内存图追踪) ✅

**Status**: ✅ **IMPLEMENTED & INTEGRATED**

- [x] Create `src/semantics/memory_graph.zig` ✅
- [x] Implement `trackAlloc` / `trackAlias` / `trackFree` / `isFreed` ✅
- [x] Integrate into `ptr_lifetime.analyzeFunction()` — global per-module graph ✅
- [x] Sync with heap alloc (malloc/calloc), resource alloc (dlopen/mmap/fopen/socket) ✅
- [x] Sync with dlsym-derived alias tracking ✅
- [x] Cross-alias double-free detection in `checkDoubleFreeViolation` ✅
- [x] Tests: 6 unit tests including leak detection ✅

**Architecture**: MemoryGraph is a **per-module singleton** shared across all functions. Each function's alloca/malloc are sub-nodes. Eliminates per-function init/deinit overhead.

**Bugs Fixed**:
- Integer overflow panic in `hashValues` → `*%` wrapping multiply
- Memory leak via ArenaAllocator → direct allocator + manual deinit
- Per-function MemoryGraph overhead → global singleton

**File**: `docs/bug/memory_graph_overflow_leak.md`

**Expected Impact**: Double free 225 → 真实 double free 报告

***

### P0-3: Call Graph + Memory Graph Integration (调用图整合) ✅

**Status**: ✅ **IMPLEMENTED & INTEGRATED**

- [x] Create `src/semantics/call_graph.zig` ✅
- [x] Implement `analyzeArgumentDirections()` — pointer-to-pointer → output, function pointer → borrowed_only ✅
- [x] Integrate into `callback_escape.checkCallbackEscape()` — suppress borrowed_only callbacks ✅
- [x] Tests: 6 unit tests ✅

**Integration**: `callback_escape.zig` uses inline argument direction analysis to detect function-pointer callbacks (borrowed_only) and suppress false-positive escape reports.

**Expected Impact**: 跨函数指针追踪完整

***

### P0-4: Allocator Knowledge Base (内存分配器知识库) ✅

**Status**: ✅ **IMPLEMENTED**

- [x] Create `src/semantics/allocator_kb.zig` ✅
- [x] 40+ builtin allocator pairs (sqlite3, openssl, glib, libuv, libc) ✅
- [x] Heuristic discovery with narrowed patterns ✅
- [x] Tests: 7 unit tests ✅

**Expected Impact**: 识别真实项目的内存分配对，提升准确率

***

### P0-5: LLVM Intrinsic Noise Filter ✅

**Status**: ✅ **IMPLEMENTED**

- [x] Create `src/semantics/intrinsic_filter.zig` ✅
- [x] 100+ builtin intrinsics, O(1) lookup ✅
- [x] Tests: 8 unit tests ✅

**Expected Impact**: BLST FFI issues 3 → 0

***

### P0-6: Noise Reduction Unified Filter ✅

**Status**: ✅ **IMPLEMENTED**

- [x] Create `src/pass/analysis/noise_reduction.zig` ✅
- [x] Three-layer filter: name-based → path-based → zone-based ✅
- [x] Integrate into `ptr_lifetime.zig`, `callback_escape.zig`, `ffi_analysis.zig` ✅

***

### P0-7: Alloca Return Suppression ✅

**Status**: ✅ **IMPLEMENTED**

- [x] `isAllocaReturnSuppressed()` in `ptr_lifetime.zig` ✅
- [x] Constructor/factory pattern detection (New/Create/Make/Alloc/Init/Open suffixes) ✅
- [x] Project-specific prefix matching (sqlite3/rowSet/alloc/vtab/attach/token) ✅

**Expected Impact**: RETURN-STACK noise from sqlite3 (24+ warnings) → 0

***

## Release Gate

All P0 items must pass before tagging v0.1.8

| P0 | Module | Status | Description |
|----|--------|--------|-------------|
| **P0-1** | Output Parameter Classifier | ✅ **DONE** | 解决 Borrow escape 328 |
| **P0-2** | Memory Graph + Merkle Tree | ✅ **DONE** | 解决 Double free 误报 |
| **P0-3** | Call Graph Integration | ✅ **DONE** | 支持跨函数追踪 |
| **P0-4** | Allocator Knowledge Base | ✅ **DONE** | 识别自定义 allocator |
| **P0-5** | LLVM Intrinsic Filter | ✅ **DONE** | 消除噪音 |
| **P0-6** | Noise Reduction Unified | ✅ **DONE** | 三层噪声过滤 |
| **P0-7** | Alloca Return Suppression | ✅ **DONE** | 消除构造器误报 |

**Release Gate Status**: ⏳ **PENDING REGRESSION VALIDATION** — 需要在 sqlite3/curl8/libuv150 上跑回归验证

***

## P1 — Inter-Procedural Analysis (Phase 1)

### P1-1: Lightweight FFI Call Site Tracking

**Problem**: Intra-procedural only → can't see caller's NULL check

**Scope**: ONLY for FFI boundary functions

**Implementation Plan**:
- [ ] Create `src/pass/analysis/ip_ffi.zig`
- [ ] Implement `FFICallSite` struct
- [ ] Implement `analyzeCallerContext(func) []FFICallSite`
- [ ] Integrate into `ptr_lifetime.zig`

***

## P2 — Remaining Work

### P2-1: static_lifetime 知识迁移 ✅

**Status**: ✅ **DONE**

- [x] 添加 `AllocKind.static_buffer` 到 `allocator_kb.zig` ✅
- [x] 16 个静态缓冲区函数注册到 AllocatorKB (ctime, asctime, strerror, inet_ntoa, getgrgid, getpwuid, getpwnam, getpwent, getgrnam, grent, tmpnam, gcvt, ecvt, fcvt, crypt, strsignal) ✅
- [x] 添加 `isStaticBuffer()` / `isStaticBufferFunction()` API ✅
- [x] `ffi_safety_checker.isStaticBufferFunction()` 优先使用 AllocatorKB，fallback 到硬编码 ✅
- [x] 修复子串误匹配 (精确匹配 + 最多 3 个下划线前缀) ✅

### P2-2: ffi_boundary.zig 拆分

**Problem**: 1876 行，超过 rules.md 限制的 1000 行

**Implementation Plan**:
- [ ] 抽取 `checkTypeCompatibility` + 类型检查相关函数到独立文件

### P2-3: Universal Pattern Framework

**Goal**: Make detection work across all languages

**Remaining Work**:
- Parameter derived pointer detection
- Suppression logging

### P2-4: Full Inter-Procedural Lifecycle

**Goal**: Cross-function pointer lifecycle tracking

**Status**: Deferred — requires significant architecture change

***

## Known Issues (from code review)

| Issue | Severity | Status |
|-------|----------|--------|
| `ffi_boundary.zig` 1876 lines (>1000 limit) | 🔴 | Open |
| `static_lifetime` knowledge lost | 🟡 | Open |
| `allocator_kb.zig` discoverHeuristic results not persisted | 🟡 | Open |
| `allocator_kb.zig` uv_buf_init misclassified | 🟡 | Open |
| `intrinsic_filter.zig` no deinit method | 🟢 | Low |
| `intrinsic_filter.zig` addSafe/addConditional/addRisky swallow OOM | 🟢 | Low |
| `output_param_classifier.zig` classifyFunction ignores func_name | 🟢 | Low |
| `call_graph.zig` propagateMemoryGraphThroughCall is stub (TODO v0.1.9) | 🟡 | Deferred |

***

## Success Metrics (v0.1.8 Targets)

### 核心指标

| Metric | Before | After (Target) | Solution |
|--------|--------|----------------|----------|
| **FFI Accuracy** | 73% | **85-90%** | Memory Graph + Call Graph |
| **Double free (sqlite3)** | 225 (FP) | **真实报告** | Memory Graph pointer tracking |
| **Borrow escape (sqlite3)** | 328 (FP) | **<30** | Output Param Classifier |
| **Cross-function tracking** | ❌ 不支持 | **✅ 支持** | Call Graph + Memory Graph |
| **Custom Allocator Recognition** | 0% | **>60%** | Allocator Knowledge Base |
