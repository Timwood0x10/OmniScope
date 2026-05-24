# OmniScope Code Review

> Generated: 2026-05-24  
> Scope: Dead code, potential bugs, and technical debt across `src/`  
> Approach: Each dead-code item includes a call-path trace before the final verdict

---

## Dead Code

### 🔴 DC-1: Unused `ptr_types` import in `noise_reduction.zig`

**File:** `src/pass/analysis/noise_reduction.zig:16`

```zig
const ptr_types = @import("ptr_lifetime_types.zig");
```

**Call-path check — is `ptr_types.X` referenced anywhere in this file body?**

| Symbol | Used? |
|--------|-------|
| `ptr_types.RUST_ALLOC_INTRINSICS` (line 228 comment) | ❌ comment only |
| `ptr_types.PtrAllocSite` | ❌ not referenced |
| any `ptr_types.*` function call | ❌ none |

The only mention of `ptr_types` is inside a code comment (`// Canonical source: ptr_types.RUST_ALLOC_INTRINSICS.alloc_only`). The actual drop-glue check on line 614 delegates to `ffi_utils.isRustDropGlue`, not `ptr_types`.

This import forces a hard compile-time dependency on a 583-line shared types file for zero runtime benefit. Deleting it changes nothing in the call graph.

✅ **VERDICT: Safe to delete.** Remove line 16 and the comment reference on line 228.

---

### 🔴 DC-2: `semantic_registry.zig.bak` — backup file in source tree

**File:** `src/registry/semantic_registry.zig.bak` (3,713 lines)

**Call-path check — is this file imported by anything in the build?**

* Grepped `semantic_registry.zig.bak` across all `.zig` files → **zero matches**.  
* No `build.zig` step references it.  
* Git history confirms it is a previous-version copy of `semantic_registry.zig`.

A 3,713-line `.bak` file in the working tree bloats the repository and confuses tooling.

✅ **VERDICT: Safe to delete** (after verifying it exists in git history, then removing from working tree). If for any reason it must stay, add it to `.gitignore` to prevent future accidental changes.

---

### 🔴 DC-3: `main.rs` is broken and unreferenced

**File:** `src/main.rs`

```rust
#[link(name = "crypto_lib", kind = "static")]
```

There is no `crypto_lib.a` or `crypto_lib.lib` anywhere in this repo. The file is not referenced by any build target in `build.zig` or `Makefile`. Any `rustc` invocation will hard-link-fail.

**Is this file reachable at all?** No build target, no test target, no import from any Zig file calls into it.

✅ **VERDICT: Safe to delete or isolate.** If considered documentation/example code, strip the `#[link(...)]` attribute to prevent breakage.

---

### 🟡 DC-4: `tracking/mod.zig` exports nothing

**File:** `src/tracking/mod.zig` (8 lines)  
**Re-export site:** `src/root.zig:51`

```zig
pub const tracking = @import("tracking/mod.zig");
```

The file is already a deprecation stub:
```
DEPRECATED (2026-05-04): TrackedAllocator and MemoryStats types have been removed.
Retained for potential future use.
```

The tracked types **are already removed** — only the re-export stub remains. `untodo.md` task **DEAD-14** already acknowledges this cleanup.

✅ **VERDICT: Safe to delete.** Remove `src/tracking/mod.zig` and `root.zig:51`.

---

## Potential Bugs

### 🔴 BUG-1: Format string mismatch in `pass/manager.zig:216` — prints garbage

```zig
// pass/manager.zig:216
diag.info("[PERF] Pass '{s}: {d} ms", .{ pass_name, @as(u32, @intFromFloat(elapsed_ms)) });
```

**Problem:** The format string contains `'{s}:` — the single-quote character `'` opens a literal segment but is never closed with a matching `'`. The actual text rendered will be:

```
[PERF] Pass 'my_module::pass: 17 ms
```

Note the missing closing quote. This is cosmetic but directly visible to users running with `--verbose` / `--debug`.

**Fix:**
```zig
diag.info("[PERF] Pass '{s}': {d} ms", .{ pass_name, @as(u32, @intFromFloat(elapsed_ms)) });
```

---

### 🔴 BUG-2: `IRLoader.loadFile` discards the parsed module result

**File:** `src/engine/loader.zig:54-66`

```zig
_ = safe_loader.loadFile(path) catch |err| {  // ← discards return value
    log.warn("Failed to load file: {}", .{err});
    return switch (err) { ... };
};
```

**Problem:** `safe_loader.loadFile(path)` returns `!llvm_safe.LoadedModule`. On **success**, the value is discarded via `_ = `. The function never propagates the loaded module upward — it constructs an IRLoader with an empty `safe_loader` state and the `alive = true` flag set, yet `getModule()` will return `null` because the module was never stored.

Callers in `main.zig` handle this defensively (they pass the loader to `runModulePipeline` which checks `loader.getModule()` with `if (loader.getModule()) |module_ref|`), so the failure mode is silent: single-file analysis produces zero issues. In multi-file mode (`runMultiFileAnalysis`), the same situation means the per-file pipeline runs against nothing — zero issues per file.

**Fix option A:** Capture the result:
```zig
const loaded = safe_loader.loadFile(path) catch |err| { ... };
// store 'loaded' into the IRLoader struct if tracking is needed
```

**Fix option B:** Early return with an explicit error if the file parsed but yielded nothing:
```zig
const loaded = safe_loader.loadFile(path) catch |err| { ... };
if (loaded.functions.len == 0) return error.EmptyModule;
```

---

### 🟡 BUG-3: `dedupKey` double-hashes `loc.func`

**File:** `src/pass/pass.zig:742-755`

```zig
fn dedupKey(self: *PassContext, issue: *const Issue) u64 {
    const func_name = @field(issue, "location").func;
    ...
    hasher.update(func_name);          // ← first hash of location.func
    ...
    hasher.update(loc.func);           // ← second hash of SAME field
    ...
}
```

`func_name` (line 745) and `loc.func` (line 752) are the **same string** (both read `issue.location.func`). FNV-1a concatenates the bytes of `func_name` twice before mixing with other fields. In practice the hash still produces a valid fingerprinting key (just a slightly off final value) — dedup correctness is preserved. But the duplicate contribution is a latent bug: if `func_name` were ever renamed independently of `loc.func` in a future Zig version, the two reads would diverge and produce silently wrong dedup collisions.

**Fix:** Remove one of the two lines. Keep line 745 or 752, not both.

---

### 🟡 BUG-4: `MemoryGraph.reset()` leaks inner HashMap bucket storage

**File:** `src/semantics/memory_graph.zig:643-701`

`reset()` iterates node destruction (L644-651) then calls `clearRetainingCapacity()` on many HashMaps (L652-699). For `bb_edges` specifically:

```zig
// reset() line 695-699
var bb_edge_iter = graph.bb_edges.iterator();
while (bb_edge_iter.next()) |entry| {
    entry.value_ptr.deinit();         // ← deinits inner HashMap's key/value pairs
}
graph.bb_edges.clearRetainingCapacity();  // ← but KEEPS outer HashMap's bucket array
```

Compare with `deinit()` at lines 288-292 which correctly calls `entry.value_ptr.deinit()` before `graph.bb_edges.deinit()`. The `clearRetainingCapacity()` call intentionally retains capacity, which means the inner HashMaps' **bucket arrays** are never freed in the `reset()` → `deinit()` sequence if `reset()` is called before `deinit()`.

The impact: repeated `reset()` calls before growing `bb_edges` inner maps will leave old bucket arrays in memory. The actual memory freed is bounded by the number of BB pairs hash-folded, but the pattern is a leak nonetheless.

**Fix:** Match `deinit()`: iterate inner HashMaps before the outer `clearRetainingCapacity()`:
```zig
// In reset(), replace bb_edges clearing with:
var bb_iter = graph.bb_edges.iterator();
while (bb_iter.next()) |entry| {
    entry.value_ptr.deinit();        // free inner HashMap buckets
}
graph.bb_edges.clearRetainingCapacity();
graph.alias_to_canonical.clearRetainingCapacity();
```

---

### 🟡 BUG-5: `GlobalAllocTracker.markFreed` silently swallows OOM

**File:** `src/pass/pass.zig:177`

```zig
rec.free_func = self.allocator.dupe(u8, func_name) catch return true;
```

On allocator OOM, the `catch` fires and returns `true` (already freed). The semantic effect is:

1. `freed` stays `false` — the allocation will still appear as a leak  
2. `free_func` is never recorded — diagnostic context is lost  
3. The return value `true` causes the caller to believe the free was double, not first

In practice OOM is extremely rare, so this is low-severity. But the silent masking of the allocator failure violation of the "fail fast" principle.

---

## Technical Debt

### 🟠 TD-1: Dual `Severity` type — one-source-of-truth violated

| File | Exports |
|---|---|
| `common/types.zig` | `pub const Severity = enum(u8) { low, medium, high, critical }` |
| `semantics/noise_filter.zig:47` | `pub const Severity = CommonTypes.Severity` *(re-export)* |
| `pass/pass.zig:1552-1553` | `fn diagToNoiseSeverity` |

`noise_filter.Severity` is a *second constant binding* to the same underlying type, not a type alias (`fn diagToNoiseSeverity` is needed at runtime; it is not a compile-time identity cast). Every module that imports `Severity` from `noise_filter` rather than `common/types` is one hop further from the canonical source.

`diagToNoiseSeverity` itself is a no-op today (both enums have identical field ordering) but the comment on line 684-685 acknowledges fragility:
```zig
// EXPLICIT: Use explicit severity ordering instead of fragile @intFromEnum
```

**Recommended:** Remove the re-export in `noise_filter.zig`, have all consumers import from `common/types.zig`, and delete `diagToNoiseSeverity`.

---

### 🟠 TD-2: `ptr_lifetime_types.zig` is a 583-line shared hub imported 10+ times

**File:** `src/pass/analysis/ptr_lifetime_types.zig`

Imported by: `ptr_lifetime`, `callback_escape`, `call_graph`, `allocation_classifier`, `ffi_language_classifier`, `ffi_utils`, `free_validation`, `rust_ffi_auditor`, `ptr_lifetime_classify`, `ptr_lifetime_utils`, `ptr_lifetime_report`, `ptr_lifetime_violations`, `layer2_reg`.  
Re-exported by `ptr_lifetime.zig:102-125` (23 items).

This is a God-module pattern: one file knows about every type across the entire lifetime analysis subsystem. Refactoring into domain-focused sub-modules would reduce the cross-dependency graph and make individual analysis passes independently testable.

---

### 🟡 TD-3: `MemoryGraph.shouldSkipAnalysis` is a no-op stub

**File:** `src/semantics/memory_graph.zig:603-608`

```zig
pub fn shouldSkipAnalysis(graph: *const MemoryGraph, ptr_val: u64) bool {
    _ = graph;
    _ = ptr_val;
    // Placeholder: will be enhanced when semantic resolution is fully integrated
    return false;
}
```

Unconditionally returns `false`. Every caller pays the function-call cost for no-op work. If semantic resolution is later wired in and this starts returning `true`, callers will silently change behavior without any compile-time signal.

**Recommendation:** Either implement the semantic resolution integration or change to a `@compileError("not yet integrated")` stub so that partial builds fail loudly instead of silently skipping.

---

### 🟡 TD-4: Ruff-relative `dedupKey` comment mismatch — not flagged by linter

The comment in `pass/pass.zig:660` says `CRITICAL issues bypass dedup`, but the actual code path (line 662) uses `issue.severity != .critical` as the condition. Both are equivalent — the comment says "critical BYPASS dedup" and the code says "if NOT critical → do dedup". The intent is the same, but the comment placement on line 660 is technically above a different code block (lines 659-663), making the relationship ambiguous to a reader scanning for the guard condition.

---

## Summary Table

| # | Type | File | Lines | Severity |
|---|------|------|-------|----------|
| DC-1 | Dead code | `pass/analysis/noise_reduction.zig` | 16 | 🔴 |
| DC-2 | Dead code | `registry/semantic_registry.zig.bak` | all | 🔴 |
| DC-3 | Dead code | `main.rs` | 4 | 🔴 |
| DC-4 | Dead code | `tracking/mod.zig` + `root.zig` | 1, 51 | 🟡 |
| BUG-1 | Bug | `pass/manager.zig` | 216 | 🔴 |
| BUG-2 | Bug | `engine/loader.zig` | 54–66 | 🔴 |
| BUG-3 | Bug | `pass/pass.zig` | 745, 752 | 🟡 |
| BUG-4 | Bug | `semantics/memory_graph.zig` | 695–699 | 🟡 |
| BUG-5 | Bug | `pass/pass.zig` | 177 | 🟡 |
| TD-1 | Tech debt | `common/types.zig`, `noise_filter.zig`, `pass/pass.zig` | — | 🟠 |
| TD-2 | Tech debt | `pass/analysis/ptr_lifetime_types.zig` | all | 🟠 |
| TD-3 | Tech debt | `semantics/memory_graph.zig` | 603–608 | 🟡 |
