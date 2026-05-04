# v0.1.6

## Added

- **Tier 1 / Tier 2 dual-pass architecture** — Zone-first layered analysis: Safe Zone gets lightweight stats-only pass; Unknown Zone + FFI boundaries get full graph-driven analysis ([danger_surface.zig](src/pass/analysis/danger_surface.zig))
- **MemoryGraph alias chain tracker** — Cross-function pointer alias propagation with `traceAliasClosure()`, `isLeaked()`, `isDoubleFreed()`, `isUseAfterFree()` ([memory_graph.zig](src/semantics/memory_graph.zig))
- **Three-layer noise reduction** — Language Classifier → Noise Filter → Behavior Filter pipeline ([noise_filter.zig](src/semantics/noise_filter.zig) + [noise_reduction.zig](src/pass/analysis/noise_reduction.zig))
- **Rust FFI ownership hook system** — Auto-detects `Box::into_raw`/`Box::from_raw`/`CString::into_raw` transfer patterns with pointer-value-based pairing verification ([hooks.zig](src/registry/hooks.zig))
- **Zone Classifier** — Language-specific function zoning (Rust 94%+ skip rate for ring, Go 74% for wasmtime) ([zone_classifier.zig](src/semantics/zone_classifier.zig))
- **FFI auto-relevant marking** — `markFfiRelevant()` API with defensive short-circuit in `isRelevantAlloc()` ([pass.zig](src/pass/pass.zig))

## New Passes

| Pass | What it does |
|------|-------------|
| **DangerSurfacePass** | Graph-driven FFI boundary detection, O(E×avg_args) replacing O(N×B) full scan |
| **CallbackEscapePass** | Callback function escape detection with zone awareness |
| **FreeValidationPass** | Free/dealloc matching validation against AllocatorKB |
| **MemorySafetyPass** | Memory safety issue aggregation (leak, UAF, double-free) |
| **NoiseReductionPass** | Three-layer noise filtering (refactored from v0.1.5) |

## Changed

- **PtrLifetimePass** — deps now `["call-graph", "danger-surface"]`; `isFreeFunction` unified into [ptr_lifetime_classify.zig](src/pass/analysis/ptr_lifetime_classify.zig)
- **FFIBoundaryPass** — deps now `["call-graph", "danger-surface"]`; integrated with CrossLangEdges
- **TaintPropagationPass** — `LLVMInvoke` correctly classified as `.call` (was `.control_flow`)
- **CallGraphPass** — now outputs CrossLangEdge data for downstream passes
- **AllocatorKB** — deallocator map bug fixed (P1-2); static buffer funcs registered once in `populateBuiltin()` instead of per-call (P1-3); builtin pairs reduced from 28→16

## Fixed

- **FIX-1**: `__rust_alloc`/`__rust_dealloc`/`__rust_realloc` incorrectly classified as noise — **Rust FFI TP Rate restored from 0% → 20%**
- **FIX-2**: CrossLangEdges not accessible from ffi_type_mismatch pass — FFI boundary count 0 → 123
- **FIX-3**: hooks.zig used instruction address as ownership pairing key — `into_raw`/`from_raw` never matched; now uses pointer value
- **FIX-4**: Four analysis passes had empty dependency arrays — execution order was fragile; all now explicitly declared
- **BUG-FIX-6**: `isGoFunction()` over-matched C++ (`std::vector::push_back`) and Rust (`core::ptr::drop_in_place`) functions as Go
- **BUG-FIX-7**: `LLVMInvoke` misclassified as `.control_flow` instead of `.call`
- **BUG-FIX-8**: `GetStructName()` null dereference in callback_escape when type has no struct name
- **Audit**: OOM fallback in PassContext created ArrayList with undefined allocator (crash on deinit)
- **Audit**: `markFfiRelevant()` was declared but never called — `ffi_auto_relevant` HashMap was always empty; now wired into danger_surface at 4 call sites
- **Audit**: hooks.zig substring matching too broad — `into_raw` would match `not_into_raw_helper`; replaced with method-boundary-aware matching

## Numbers

```
                    v0.1.5    v0.1.6
Rust FFI TP Rate      0%       20%
Test cases           ~50      191
Coverage              ~70%     92%
Precision (subtle)    N/A      100% (0 FP)
Dead code             ~2000    ~1300 lines (-35%)
Avg exec time (large) ~40ms    ~36ms

17 .ll files benchmarked:
  548 issues detected · 27,076 pointers tracked · 9,372 FFI boundaries · 251 violations
```

## Compatibility

No breaking changes.
