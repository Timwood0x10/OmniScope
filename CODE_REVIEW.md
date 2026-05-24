# OmniScope Code Review

> **Verified**: 2026-05-24 — All claims checked against actual source code  
> **Metrics verified**: 157 `.zig` source files, ~66,579 lines across `src/`  
> **Fresh review scope**: `src/` tree (dataflow, pass/analysis, registry, semantics, output, engine, ir)

---

## 🔴 Critical Bugs

### CR-BUG-1: Dangling pointer — `getIssuesBySeverity` returns reference to temporary array

**File:** `src/dataflow/graph.zig:458`

```zig
if (count == 0) {
    return &[_]Issue{};   // ❌ Pointer to a temporary stack array
}
```

The pointer returned refers to a temporary array literal allocated on the stack. Once the function returns the pointer is dangling. Any caller that uses the slice after the call reads freed stack memory. Fix: return a caller-owned (or null) slice, or use a sentinel global zero-length array.

### CR-BUG-2: Array-bounds write — `langToIndex(.unknown) = 8` overflows 8-element array

**File:** `src/semantics/language_detector.zig:72, 138`

```zig
var weighted_votes = [_]f32{ 0, 0, 0, 0, 0, 0, 0, 0 }; // 8 slots

fn langToIndex(lang: Language) usize {
    return switch (lang) {
        .unknown => 8,    // ❌ index 8 is past the end of an 8-element array (0..7)
        ...
    };
}
```

`indexToLang` maps index 7 → `.unknown`, but `langToIndex` maps `.unknown` → 8, writing one element past the end of `weighted_votes`. This causes undefined behaviour and will likely panic in release builds. The slot for `.unknown` can also never accumulate votes from any non-unknown incoming result, making it dead regardless.

### CR-BUG-3: `f32` array size/`langToIndex` invariant broken — 9 states vs 8 slots

**File:** `src/semantics/language_detector.zig:72`

The `weighted_votes` array has 8 elements (`rust, go, zig, cpp, c, swift, java, unknown`) but `langToIndex` maps 9 states (adding `.unknown` at index 8). The `_` catch-all in `indexToLang` also maps index 8 → `.unknown`. Even after fixing BUG-2 to put `.unknown` at index 7 (matching `indexToLang`), the voter has 8 votes for 9 states. The `.unknown` vote-origin becomes indeterminable — a logic hole that must be resolved by explicitly choosing: 8 states (drop one slot) or 9 states (add one slot).

---

## 🟠 Potential Bugs

### POT-BUG-1: `getIssuesBySeverity` leaks partial result on OOM during deep copy

**File:** `src/dataflow/graph.zig:461–493`

```zig
const result = try self.allocator.alloc(Issue, count);
...
const message_copy = try self.allocator.dupe(u8, issue.message);
```

If OOM strikes inside the loop, already-allocated `message_copy` / `func_copy` strings leak and the partially-filled `result` is never `deinit()`-ed. There is no `errdefer` inside the loop. The error propagates upward but without a cleanup path for internally allocated entries.

### POT-BUG-2: Silent OOM in FFI set cache — possible false negative on every pointer

**File:** `src/pass/pass.zig:1071`

```zig
ffi_set.put(ffe.callee_name, {}) catch {};
```

If OOM occurs while building `ffi_set_cache`, the affected FFI boundary name is silently dropped. `isOnDangerPathFull` (line 1096) then treats that FFI pointer as non-FFI, producing a false negative. This runs in the hot path for every pointer during analysis.

### POT-BUG-3: `markFunctionFromInst` swallows HashMap OOM — false-negative tier gating

**File:** `src/pass/pass.zig:1154–1157`

```zig
self.relevant_functions.put(func_ptr, {}) catch |err| {
    log.warn("[P0-1] markFunctionFromInst: ...", .{ func_ptr, err });
};
```

`markFunctionFromInst` is documented as "gating degradation is acceptable", but silently failing on OOM means a function that _should_ have been Tier 2-analyzed falls through to the Tier 1 skip path. This is a false negative, not just noisy logging.

### POT-BUG-4: `isIndirect` misclassifies non-func ConstantExpr as indirect call

**File:** `src/pass/analysis/ffi_boundary.zig:293–296`

```zig
const is_indirect = (called_name.len == 0 or
    called_name[0] == '%' or
    c.LLVMIsAFunction(called_val) == null or
    c.LLVMIsAConstantExpr(called_val) != null);
```

`LLVMIsAConstantExpr` matches not only `inttoptr`/`bitcast` function-pointer casts, but also constant `getelementptr`, constant `load`, etc. A constant GEP to a data structure will trigger the GEP-based JNI resolution path (`resolveIndirectCallTarget`), which then returns `""` at lines 754/777. The caller sees an empty name and skips the call as indeterminate.

### POT-BUG-5: Zone-aware severity boost mentioned but not implemented

**File:** `src/pass/analysis/ffi_boundary.zig:428–437`

```zig
const severity = base_severity;   // no zone-based adjustment applied
const confidence: f32 = switch (caller_zone) { ... };
```

The comment says "Zone-aware confidence/severity adjustment" but only confidence is adjusted. The `severity` variable is set to the plain `base_severity` with no zone-specific boost. If a severity boost for `.ffi` / `.unknown` callers was intended, it was never coded.

### POT-BUG-6: `demangleRustName` caps path at 3 components

**File:** `src/pass/analysis/ffi_utils.zig:290–293`

```zig
var components: [3][]const u8 = .{ "", "", "" };
var comp_count: usize = 0;
while (pos < mangled.len and comp_count < 3) { ... }
```

Deep Rust paths such as `core::iter::adapters::Map::new` are truncated to 2 components. Same function-name collisions may result from identical first-two-component Rust paths sharing different leaf structs — leading to incorrect pointer pairing in `rust_ffi_auditor`.

### POT-BUG-7: `surface_classifier_pass` BFS `getOrPut` pattern has unreachable-branches risk

**File:** `src/pass/analysis/surface_classifier_pass.zig:259–263, 299–306`

```zig
const gop = forward_adj.getOrPut(caller_ptr) catch continue;
if (!gop.found_existing) {
    gop.value_ptr.* = std.ArrayList(u64).initCapacity(allocator, 4) catch continue;
}
gop.value_ptr.append(allocator, callee_ptr) catch {};
```

`getOrPut` allocates the key placeholder on OOM via `catch continue` — but then `gop.value_ptr` is unconditionally dereferenced on `append`. If `getOrPut` succeeded but `initCapacity`'s `catch continue` skips past, the same callee will be retried next time – or the entry is left in `forward_adj` with a null list pointer. In Zig 0.15.x this `catch continue` after `initCapacity` passes `gop` by value so the value is live — but if it's later overwritten in a subsequent `getOrPut` the stale entry may be leaked.

### POT-BUG-8: `rust_ffi_auditor` uses pointer-address as HashMap key

**File:** `src/pass/analysis/rust_ffi_auditor.zig:2095, 2101`

```zig
into_raw_set.put(@intFromPtr(func_name_raw), {}) catch {};
from_raw_set.put(@intFromPtr(func_name_raw), {}) catch {};
```

`func_name_raw` is a `[]const u8`. `@intFromPtr` returns the backing address of the string slice header. The same function name with a different backing string allocation produces a different key, so both `into_raw` and `from_raw` entries for the same function coexist in the map. The pairing logic in `hooks.zig:99–128` relies on unique keys per function name, making this a root cause of missed ownership-transfer detections.

---

## 🟡 Dead Code / Orphaned Files

### DEAD-1: `src/registry/semantic_registry.zig.bak` — **STALE BACKUP, 3,713 lines**

**State:** Full copy of `semantic_registry.zig` from before the Severity value migration.  
**Evidence:** Tests at line 3508 assert `low=1, medium=2, high=3, critical=4` while `common/types.zig` defines `low=0, medium=1, high=2, critical=3`.  
**Build impact:** Not referenced by `build.zig`, `Makefile`, or any source file — cutting it out is zero-risk.  
**`bugs.md` error:** Already says "ALREADY GONE" on lines 22, 176 but file still exists on disk.

### DEAD-2: `src/registry/sanitizer_registry.zig` — **ORPHAN FILE**

Does not appear in `semantic_registry.zig:30–40`'s import list. Not imported by any other file. Zero callers.

### DEAD-3: `src/registry/hooks_test.zig` and `layer1_reg_test.zig` — **ORPHAN TEST FILES**

Both missing from `root.zig`'s `test {}` bare block (lines 289–295). Not globbed by `build.zig`. They are never compiled.

### DEAD-4: `src/pass/analysis/callback_escape_test.zig` — **REPLACED BUT NOT REMOVED**

Only `callback_escape_enhanced_test.zig` (line 291 root.zig) is imported by `root.zig`. The plain variant is dead code.

### DEAD-5: `src/pass/analysis/ffi_zone_check.zig` referenced in docstring but not the live import graph

**File:** `src/pass/analysis/ffi_boundary.zig:25`

```zig
const zone_check = @import("ffi_zone_check.zig");
```

The file `ffi_zone_check.zig` exists (323 lines) and is imported by both `ffi_boundary.zig` and `ffi_boundary_check.zig`. Not dead — but the `docs/en/passes.md` reference still points to `ffi_boundary.zig`-only notes rather than the extracted `ffi_zone_check.zig`. Minor doc drift only (`DANGERSURFACE.md line 263` notes its reference in the printf%n section).
