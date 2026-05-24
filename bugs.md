# OmniScope Code Review

> Generated: 2026-05-24  
> Scope: Dead code, potential bugs, and technical debt across `src/`  
> Approach: Each dead-code item includes a call-path trace before the final verdict  
> **Verified**: 2026-05-24 — All claims checked against actual source code

---

## Dead Code

### ✅ DC-1: Unused `ptr_types` import in `noise_reduction.zig` — **CONFIRMED**

**File:** `src/pass/analysis/noise_reduction.zig:16`  

**Verification:** `grep 'ptr_types\.'` → only match is line 228 (inside a code comment). Zero runtime references.

**Action:** Remove line 16 import and clean up comment on L228.

---

### ❌ DC-2: `semantic_registry.zig.bak` — **ALREADY DELETED**

**Status:** File does not exist. Already cleaned up in prior session. No action needed.

---

### ⚠️ DC-3: `main.rs` is broken and unreferenced — **CONFIRMED (low priority)**

**File:** `src/main.rs` — exists, contains `#[link(name = "crypto_lib", kind = "static")]`

**Verification:** 
- Not referenced by any build target (`build.zig`, `Makefile`)
- Only appears as test strings in `path_filter.zig` and `debug_origin.zig` (4 matches, all test cases using "main.rs" as example filename)
- The `crypto_lib.a` link would fail if compiled

**Verdict:** Dead example code. Safe to delete, but low priority since it doesn't affect compilation.

---

### ✅ DC-4: `tracking/mod.zig` exports nothing — **CONFIRMED**

**File:** `src/tracking/mod.zig` (8 lines)  
**Re-export site:** `src/root.zig:51` — `pub const tracking = @import("tracking/mod.zig");` still present

**Verification:** File is deprecation stub only. root.zig still exports it.

**Action:** Delete file + remove root.zig L50-51 export.

---

## Potential Bugs

### ❌ BUG-1: Format string mismatch in `pass/manager.zig:216` — **FALSE POSITIVE**

**Claimed:** Unclosed single-quote in format string prints garbage.

**Actual code (L216):**
```zig
diag.info("[PERF] Pass '{s}: {d} ms", .{ pass_name, @as(u32, @intFromFloat(elapsed_ms)) });
```

**Analysis:** In Zig format strings, `'` is a literal character (not a format specifier). The output `[PERF] Pass 'my_func: 42 ms` is intentional quoting around the pass name. This is NOT a bug — it's a cosmetic choice.

**Verdict:** ❌ **NOT A BUG.** No action needed.

---

### ✅ BUG-2: `IRLoader.loadFile` discards parsed module result — **CONFIRMED**

**File:** `src/engine/loader.zig:56`  

```zig
_ = safe_loader.loadFile(path) catch |err| {   // success path discarded
    log.warn("Failed to load file: {}", .{err});
    return switch (err) { ... };
};
```

**Impact:** On successful parse, the `LoadedModule` result is discarded. `getModule()` returns `null`. Single-file analysis produces zero issues silently.

**Fix priority:** Medium — silent data loss but no crash.

---

### ✅ BUG-3: `dedupKey` double-hashes `loc.func` — **CONFIRMED**

**File:** `src/pass/pass.zig:745-753`  

```zig
const func_name = @field(issue, "location").func;  // L747
hasher.update(func_name);                        // L750 ← first hash
...
const loc = @field(issue, "location");            // L752
hasher.update(loc.func);                         // L753 ← second hash of SAME field
```

`func_name` and `loc.func` are identical (both = `issue.location.func`). Hashes same bytes twice. Dedup correctness preserved (still unique), but wastes cycles and is fragile.

**Fix:** Remove either L750 or L753.

---

### ⚠️ BUG-4: `MemoryGraph.reset()` inner HashMap handling — **PARTIAL (exaggerated)**

**File:** `src/semantics/memory_graph.zig:695-699`  

**Claimed:** Inner HashMap bucket arrays leaked by `clearRetainingCapacity()`.

**Actual code:**
```zig
var bb_edge_iter = graph.bb_edges.iterator();
while (bb_edge_iter.next()) |entry| {
    entry.value_ptr.deinit();         // frees key/value pairs
}
graph.bb_edges.clearRetainingCapacity(); // retains outer bucket array
```

**Analysis:** The pattern (deinit inner → clearRetainingCapacity outer) is **correct for reset-then-reuse semantics**. `clearRetainingCapacity()` intentionally keeps bucket allocation to avoid rehash on next fill. This is standard Zig HashMap usage for reset patterns. The "leak" claim is technically true (buckets not freed until `deinit()`) but this is by design, not a bug. Memory is bounded and released at final `deinit()`.

**Verdict:** ⚠️ **NOT A BUG** — working as designed. Description exaggerates impact. No action needed unless memory profiling shows actual pressure.

---

### ✅ BUG-5: `GlobalAllocTracker.markFreed` silently swallows OOM — **CONFIRMED**

**File:** `src/pass/pass.zig:177`  

```zig
const free_name_owned = self.allocator.dupe(u8, func_name) catch return true;
```

On OOM: returns `true` (already-freed semantic), `rec.freed` stays `false`, `rec.free_func` never set. Caller interprets as double-free instead of OOM.

**Severity:** Low (OOM extremely rare), but violates fail-fast principle.

---

## Technical Debt

### 🟠 TD-1: Dual `Severity` type — **CONFIRMED**

`common/types.zig` defines canonical `Severity`. `noise_filter.zig` re-exports it. `diagToNoiseSeverity()` in `pass.zig` is a runtime mapping that's a no-op today but fragile if enum ordering changes.

**Recommendation:** Single source of truth — import from `common/types.zig` only.

---

### 🟠 TD-2: `ptr_lifetime_types.zig` God-module — **CONFIRMED**

583-line file imported by 13+ modules across the lifetime analysis subsystem. Centralized type hub creates cross-dependencies.

**Note:** DC-1 above (removing unused `ptr_types` from noise_reduction.zig) is a first step toward reducing this coupling.

---

### 🟡 TD-3: `MemoryGraph.shouldSkipAnalysis` no-op stub — **CONFIRMED**

`src/semantics/memory_graph.zig:603-608` — unconditionally returns `false`.

**Recommendation:** Either implement or use `@compileError` to prevent silent behavior change on future integration.

---

### 🟡 TD-4: `dedupKey` comment ambiguity — **CONFIRMED (cosmetic)**

Comment at `pass.zig:660` says "CRITICAL issues bypass dedup" but guards lines 659-663. Intent matches code, but comment placement is slightly misleading for readers scanning vertically.

---

## Summary Table

| # | Type | File | Verdict | Action |
|---|------|------|---------|--------|
| DC-1 | Dead code | `noise_reduction.zig:16` | ✅ CONFIRMED | Delete import |
| DC-2 | Dead code | `semantic_registry.zig.bak` | ❌ ALREADY GONE | None |
| DC-3 | Dead code | `src/main.rs` | ⚠️ CONFIRMED | Low-priority delete |
| DC-4 | Dead code | `tracking/mod.zig` + `root.zig:51` | ✅ CONFIRMED | Delete both |
| BUG-1 | Bug | `manager.zig:216` | ❌ FALSE | None |
| BUG-2 | Bug | `loader.zig:56` | ✅ CONFIRMED | Fix: capture return |
| BUG-3 | Bug | `pass.zig:750,753` | ✅ CONFIRMED | Fix: remove dup hash |
| BUG-4 | Bug | `memory_graph.zig:695-699` | ⚠️ NOT A BUG | None |
| BUG-5 | Bug | `pass.zig:177` | ✅ CONFIRMED | Fix: propagate error |
| TD-1 | Debt | Severity dual type | ✅ CONFIRMED | Future cleanup |
| TD-2 | Debt | ptr_lifetime_types.zig | ✅ CONFIRMED | Future refactor |
| TD-3 | Debt | shouldSkipAnalysis stub | ✅ CONFIRMED | Implement or compileError |
| TD-4 | Debt | dedupKey comment | ✅ CONFIRMED | Cosmetic fix |

**Stats:** 4 confirmed dead code items (1 already gone), 4 bugs (1 FP, 1 exaggerated), 4 tech debt items
