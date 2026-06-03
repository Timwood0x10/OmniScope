# OmniScope Performance Diagnosis — wasmtime_test.bc (202s)

## Executive Summary

OmniScope v0.1.8 takes **202s** to analyze `wasmtime_test.bc` (17 MB, 4654 functions, 458K instructions), outputting 4135 issues (only 9 unique after dedup). The target budget is 55s. **The IR Store is implemented but unused by any analysis pass**, causing massive redundant IR traversal. The single largest bottleneck is `rust-ffi-filter` at **137.8s (69% of total time)**.

---

## 1. IR Store Implementation Status

**Status: ✅ Implemented, ❌ Not consumed**

`ModuleIRStore` (`src/ir/ir_store.zig`, 259 lines) is fully implemented with:

| Feature | Status |
|---------|--------|
| `FunctionIR` struct with pre-categorized instruction buckets | ✅ |
| `ModuleIRStore` with O(1) function lookup via `StringHashMap` | ✅ |
| Single O(n) traversal via `collect()` | ✅ |
| Pre-categorized arrays: calls, stores, loads, allocas, returns, geps, bitcasts | ✅ |
| Global variable collection with name index | ✅ |
| `findFunction()` O(1) lookup | ✅ |

**Collection is working**: Pipeline log confirms `[IRStore] Collected 4654 functions, 458418 total instructions` in ~19ms.

**But zero passes use it.** Grep for `ctx.ir_store` or `ir_store` inside `src/pass/` returns **no results**. Every pass still iterates `LLVMGetFirstFunction → LLVMGetNextFunction → LLVMGetFirstBasicBlock → LLVMGetNextBasicBlock → LLVMGetFirstInstruction → LLVMGetNextInstruction` from scratch.

---

## 2. Per-Pass Performance Breakdown (wasmtime_test.bc)

Sorted by time (descending):

| Pass | Time (ms) | % of Total | Key Issue |
|------|-----------|------------|-----------|
| **rust-ffi-filter** | **137,775** | **69.0%** | Full module re-traversal per rule; no IR Store usage |
| **pointer-ownership** | 13,937 | 7.0% | Re-traverses all functions |
| **SemanticResolver** | 12,348 | 6.2% | Re-traverses all functions |
| **ptr-lifetime** | 7,810 | 3.9% | Per-function BB/inst traversal |
| **error-propagation-tracer** | 6,977 | 3.5% | Module-level re-scan |
| **pointer-flow** | 6,206 | 3.1% | Module-level re-scan |
| **call-graph** | 3,713 | 1.9% | Module-level re-scan |
| **cross-lang-dataflow** | 3,397 | 1.7% | 12 separate function iteration loops |
| **ffi-boundary** | 2,760 | 1.4% | Parallel but still traverses IR directly |
| **ffi-type-mismatch** | 706 | 0.4% | Module-level re-scan |
| **free-validation** | 725 | 0.4% | Module-level re-scan |
| **return-check** | 907 | 0.5% | Module-level re-scan |
| **dfg** | 570 | 0.3% | Module-level re-scan |
| **alias** | 671 | 0.3% | Module-level re-scan |
| **cfg** | 75 | <0.1% | Fast (structural only) |
| All others | ~900 | <0.5% | Various |
| **Pipeline overhead (leak analysis, dedup, etc.)** | ~6,500 | 3.2% | Pipeline.zig leak loop |
| **TOTAL** | **~199,670** | **100%** | |

---

## 3. Root Cause Analysis

### 3.1 Critical: `rust-ffi-filter` — 137.8s (69%)

This single pass accounts for the majority of execution time. Root causes:

1. **Full module re-traversal**: `audit()` calls `LLVMGetFirstFunction → LLVMGetNextFunction` iterating all 4654 functions, despite `has_ffi_calls` already being computed in the pipeline.

2. **Per-function instruction re-collection**: `auditFunction()` builds `all_insts` from scratch via BB/inst traversal, **even though `FunctionIR` already has pre-categorized `calls[]`, `stores[]`, `loads[]`, etc.** in the IR Store.

3. **Single consolidated traversal, but still raw LLVM API**: `auditFunction()` already consolidates into 1 BB/inst sweep (down from 6-8 per-rule sweeps in an earlier version — see comment at auditor.zig:153). Rules receive the pre-built `insts` slice; `rules_basic.zig` makes zero independent `LLVMGetFirstBasicBlock` calls. However there are still **10 BB traversal sites** across `rust_ffi/` (auditor + lifetime + helpers), and the `all_insts` ArrayList allocation + LLVM FFI calls per function remain expensive compared to IR Store pre-categorized arrays.

4. **No parallelism**: Unlike `ffi-boundary` which uses the work-stealing thread pool, `rust-ffi-filter` is purely sequential.

5. **`all_insts` collection is unconditional**: The BB/inst collection at `auditor.zig:162-170` runs for **every function**, regardless of `is_rust`. Rules 4/5/8/9/10 (universal FFI rules at lines 215-232) always run, so the collection cannot be trivially gated. However, IR Store's pre-categorized `calls[]`/`stores[]` arrays would eliminate this traversal entirely. Note: `is_rust_module` correctly short-circuits calling `hasRustFfiPatterns()` — that path is fine. `hasRustFfiPatterns()` itself has two O(1) fast paths (set-count check, name-mangling check) before falling back to a full BB/inst scan (Check 2, `auditor.zig:293-316`).

### 3.2 Major: IR Store Not Consumed by Any Pass

The IR Store (`ModuleIRStore`) provides:

- `functions`: StringHashMap → O(1) function lookup by name
- `function_list`: Pre-built array of all `*FunctionIR`
- Each `FunctionIR` has: `calls[]`, `stores[]`, `loads[]`, `allocas[]`, `returns[]`, `geps[]`, `bitcasts[]`

**If passes consumed IR Store instead of raw LLVM C API iteration:**

| Current | With IR Store | Speedup |
|---------|---------------|---------|
| `LLVMGetInstructionOpcode()` per inst (FFI call) | Pre-categorized `calls[]` array | 8-10x for call-focused passes |
| 3+ passes each iterate all instructions | Single pre-categorized traversal | 3x+ for overlapping passes |
| `LLVMGetCalledValue()` + `LLVMGetValueName()` per call | `FunctionIR.getCalleeName()` | Eliminates 2 FFI calls per call site |

### 3.3 Moderate: Language Detection Misclassification

The pipeline detected `wasmtime_test.bc` as **Python** (!) instead of Rust:

```
PIPELINE: Detected language: python, using adapter: python (memory model: refcount)
```

This means:
- Python adapter runs on 1551 functions (33% of module) doing useless work
- GC safety check is skipped (`GcSafetyPass: skipping non-GC language module (rust)`) — but it was classified as Python, not Rust
- Rust-specific optimizations in the pipeline may not activate properly

### 3.4 Moderate: Deduplication Ineffective — 4126/4135 Duplicates

After all passes complete, only **9 out of 4135 issues** are unique. This means:

- 99.8% of reported issues are duplicates
- Massive wasted time generating and processing duplicates
- The noise is primarily from `rust-ffi-filter` generating thousands of identical `ffi_unsafe_call` findings

### 3.5 Minor: Time Budget System Exists But Doesn't Enforce

The pipeline has a 55s budget but takes 199.67s. The budget checks only trigger *during* specific loops (CallSiteIndex build, adapter analysis, container inference, leak analysis) — they don't affect the pass manager execution at all. Once `pass_manager.run()` starts, all 25 passes run to completion regardless of budget.

---

## 4. IR Store Architecture Assessment

### 4.1 What IR Store Already Provides

```zig
pub const FunctionIR = struct {
    func: c.LLVMValueRef,
    name: []const u8,
    instructions: []c.LLVMValueRef,  // All instructions
    calls: []c.LLVMValueRef,          // Pre-filtered: Call/Invoke only
    stores: []c.LLVMValueRef,         // Pre-filtered: Store only
    loads: []c.LLVMValueRef,          // Pre-filtered: Load only
    allocas: []c.LLVMValueRef,        // Pre-filtered: Alloca only
    returns: []c.LLVMValueRef,        // Pre-filtered: Ret only
    geps: []c.LLVMValueRef,           // Pre-filtered: GEP only
    bitcasts: []c.LLVMValueRef,       // Pre-filtered: BitCast only
    opcodes: []c_uint,                // Parallel to instructions[]
};

pub const ModuleIRStore = struct {
    functions: StringHashMap(*FunctionIR),  // O(1) lookup by name
    function_list: []*FunctionIR,           // Ordered iteration
    globals: []c.LLVMValueRef,              // All globals
    global_names: StringHashMap(usize),     // O(1) lookup
    function_count: usize,
    total_instruction_count: usize,
};
```

### 4.2 What IR Store is Missing (for full pass migration)

| Missing Feature | Needed By | Impact |
|-----------------|-----------|--------|
| `phis[]` array | CFG/DFG passes | Medium — would skip phi-filtering in each pass |
| `icmps[]` array | Taint propagation, buffer overflow | Low — small subset |
| `switches[]` / `br` classification | CFG pass | Low — only 1 pass |
| `select[]` array | Taint propagation | Low |
| BB structure (predecessors/successors) | CFG/DFG/alias | Medium — currently each pass builds this |
| Def-use chains | Pointer ownership, taint | High — currently O(n²) per function |
| Call graph (callee→caller index) | Multiple passes | High — currently rebuilt by CallGraphPass |

### 4.3 PassContext Field

`PassContext` already has `ir_store: *ModuleIRStore` field (in `src/types/pass_types.zig:344`), so no plumbing changes are needed. Every pass already has access — they just don't use it.

---

## 5. Optimization Recommendations (Priority Order)

### P0: Make rust-ffi-filter use IR Store — Expected: 137.8s → ~15s

**The single highest-impact change.**

Current `auditFunction()` does:
```zig
// Current: Re-traverse BB/inst for every function
var bb = c.LLVMGetFirstBasicBlock(func);
while (...) : (bb = c.LLVMGetNextBasicBlock(bb)) {
    var inst = c.LLVMGetFirstInstruction(bb);
    while (...) : (inst = c.LLVMGetNextInstruction(inst)) {
        all_insts.append(self.allocator, inst) catch {};
    }
}
```

With IR Store:
```zig
// Proposed: Use pre-categorized instruction arrays
const fir = ctx.ir_store.findFunction(func_name) orelse return;
// fir.calls[] already contains only Call/Invoke instructions
// fir.stores[] already contains only Store instructions
// No BB/inst traversal needed at all
```

**Specific changes:**

1. `audit()` → iterate `ctx.ir_store.function_list` instead of `LLVMGetFirstFunction`
2. `auditFunction()` → use `fir.calls[]` instead of `all_insts` + `LLVMGetInstructionOpcode` filtering
3. `basic_rules.detectAsPtrEscape()` → use `fir.calls[]` + `fir.stores[]`
4. `basic_rules.detectCrossLangMismatch()` → use `fir.calls[]`
5. `lifetime_rules.detectAsPtrDangling()` → use `fir.loads[]` + `fir.stores[]` + `fir.calls[]`
6. `advanced_rules.detectUseAfterFree()` → use `fir.loads[]` + `fir.calls[]`
7. Skip `all_insts` ArrayList construction entirely

**Expected speedup**: ~10x for this pass (eliminates BB/inst traversal + redundant opcode classification + ArrayList allocation per function × 4654 functions).

### P1: Add parallelism to rust-ffi-filter — Expected: ~15s → ~3-5s

Currently sequential. Following the `ffi-boundary` pattern:

1. Pre-collect work items from `ctx.ir_store.function_list`
2. Use `ParallelExecutor` with `ffi_parallel`-style worker context
3. Each worker processes a function independently using IR Store data

**Note**: `FunctionIR` data is read-only during analysis (safe for parallel access). Only `addIssue()` and finding collection need mutex protection.

### P2: Migrate top-5 passes to IR Store — Expected: ~30s → ~10s

| Pass | Current (ms) | Estimated with IR Store |
|------|-------------|------------------------|
| pointer-ownership | 13,937 | ~2,000 |
| SemanticResolver | 12,348 | ~2,500 |
| ptr-lifetime | 7,810 | ~1,500 |
| error-propagation-tracer | 6,977 | ~1,200 |
| pointer-flow | 6,206 | ~1,000 |

These passes all share the same pattern: iterate all functions → iterate all instructions → filter by opcode. With IR Store, they can:

- Use `fir.calls[]` directly for call-site analysis
- Use `fir.stores[]` + `fir.loads[]` for pointer tracking
- Use `fir.allocas[]` for allocation analysis
- Skip the LLVM C API FFI overhead entirely

### P3: Fix language detection — Expected: Correct adapter selection

`wasmtime_test.bc` is a Rust project but detected as Python. This causes:

- Python adapter to run uselessly on 1551 functions
- Incorrect memory model assumptions (refcount vs ownership)
- Potential missed Rust-specific analysis

Investigate `adapter_registry.detectAdapter()` — likely relying on symbol patterns that match Python C API patterns in wasmtime's test harness.

### P4: Add intra-pass deduplication — Expected: 4135 → ~50 issues

Currently deduplication only happens post-pipeline. Add per-pass dedup keys:

1. `rust-ffi-filter` should dedup `(func_name, issue_type)` within its own run
2. Each pass should check `reported_keys` before adding issues
3. This reduces work for downstream deduplication and output formatting

### P5: Enforce time budget in PassManager — Expected: Graceful degradation

Add budget checks to `PassManager.run()`:

```zig
for (self.resolved_order.?) |idx| {
    if (pipeline_elapsed > time_budget_ns) {
        log.warn("Skipping remaining passes due to budget exhaustion");
        break;
    }
    // ... run pass
}
```

Requires passing pipeline start time to PassManager (currently not available).

### P6: Extend IR Store with missing categories — Expected: Enable more pass migrations

Add to `FunctionIR`:
- `phis: []c.LLVMValueRef` — for CFG/DFG passes
- `icmps: []c.LLVMValueRef` — for taint/buffer overflow
- `invokes: []c.LLVMValueRef` — separate from calls for exception handling analysis

Add to `ModuleIRStore`:
- `call_graph: CallGraph` — pre-built callee→caller index
- `bb_adjacency: BBAdjacency` — pre-built predecessor/successor lists

---

## 6. Expected Total Speedup

| Phase | Time (s) | Cumulative |
|-------|----------|------------|
| Current | 199.7 | — |
| After P0 (IR Store for rust-ffi-filter) | ~77 | 2.6x |
| After P1 (Parallel rust-ffi-filter) | ~65 | 3.1x |
| After P2 (Top-5 passes use IR Store) | ~35 | 5.7x |
| After P3-P6 (Detection + dedup + budget) | ~25-30 | ~7x |

**Target: <30s for wasmtime_test.bc** (within the 55s budget with margin).

---

## 7. Key Files Reference

| File | Lines | Role |
|------|-------|------|
| `src/ir/ir_store.zig` | 259 | IR Store implementation (FunctionIR + ModuleIRStore) |
| `src/pipeline/pipeline.zig` | 1,335 | Pipeline orchestrator, IR Store collection, leak analysis |
| `src/pass/manager.zig` | 545 | Pass registration, dependency resolution, execution |
| `src/pass/analysis/rust_ffi/rust_ffi_auditor.zig` | 694 | **69% of runtime** — needs IR Store migration |
| `src/pass/analysis/rust_ffi/rust_ffi_rules_basic.zig` | 655 | Rule implementations (receives `insts` slice, no own BB/inst traversal) |
| `src/pass/analysis/rust_ffi/rust_ffi_rules_lifetime.zig` | 394 | Lifetime rules |
| `src/pass/analysis/rust_ffi/rust_ffi_rules_advanced.zig` | 816 | Advanced rules |
| `src/types/pass_types.zig` | 1,333 | PassContext with `ir_store` field (already plumbed) |
| `src/ir/inst_cache.zig` | 244 | Per-instruction opcode cache (partial mitigation) |
| `src/pipeline/parallel.zig` | 629 | Work-stealing thread pool (exists, not used by rust-ffi) |
| `src/pass/analysis/ffi/ffi_parallel.zig` | 87 | Parallel FFI worker (template for rust-ffi parallelism) |

---

*Diagnosis generated: 2026-06-02 22:07 CST*
