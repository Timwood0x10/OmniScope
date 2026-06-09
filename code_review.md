# OmniScope Code Review Report

**Review date:** 2026-06-09
**Scope:** 367 `.zig` files (`src/`, `tests/`, `benches/`)
**Build status:** `zig build` passes (compilation clean)

---

## 🔴 CRITICAL — Dead features / silent broken functionality

**BUG-1: `--config` JSON overrides is a TODO stub**
`src/config/file_config.zig:111` — `loadFromFile()` parses the file but never populates `FileConfig.lang_registry`. `main.zig` even has a comment: `// JSON overrides could be loaded here in the future`. The CLI logs "Loaded configuration" but applies zero overrides. All unit tests for `loadFromJson()` pass but are unreachable in production.

**BUG-2: `run_full_test.sh` fabricates all comparison metrics as zero**
`run_full_test.sh:107` — `safe_grep_count` is called as `safe_grep_count -i 'PATTERN' "$out"`, which passes `-i` as `$1` (treated as filename) and the pattern as `$2` (also a filename). `grep` fails silently (`|| true`), `${cl:=0}` forces count to 0. Every row in phase1/phase2 CSV for `cross_lang`, `ownership`, `danger`, `ffi_type` is a fabricated zero — CI is green with no real signal.

**BUG-3: `src/visual/n.zig` / `src/visual/nzig.zig` do not exist; imports resolve to `graph_visualizer.zig` but it has zero active callers**
- `src/pipeline.zig:24`: `@import("./visual/graph_visualizer.zig").GraphKind`
- `src/ffi_precision.zig:386`: `@import("visual/graph_visualizer.zig").GraphKind`
- `src/pipeline_runner.zig:88`: `@import("./visual/graph_visualizer.zig")`
- `CHANGELOG.md` references `n.zig` — file never existed by that name; renamed to `graph_visualizer.zig` at commit `953c433`.

Global search for `GraphVisualizer` or `graph_visualizer.` outside `src/visual/graph_visualizer.zig` returns **zero results**. The visualizer is wired in (imports resolve, linking succeeds) but never invoked in any analysis flow. Dead code on the hot path.

**BUG-4: `graph_visualizer.zig` module doc-comment references non-existent public API**
Lines 21–28 document:
```zig
var viz = try graph_visualizer.GraphVisualizer.init(allocator);
try viz.exportMemoryGraph(&memory_graph, "omniscope_memory.html");
try viz.exportCallGraph(&call_graph, "omniscope_callgraph.html");
```
The struct exports are `pub const GraphVisualizer` (no module-level namespace `graph_visualizer.`), and the actual methods are `generateMemoryGraph` / `generateCallGraph`, not `exportMemoryGraph` / `exportCallGraph`. Any user following the doc-comment gets a compile error.

---

## 🟠 HIGH — Real bugs that silently corrupt analysis results

**BUG-5: Memory leak in `type_mapping_validator` test helpers**
`src/pass/analysis/ffi/type_mapping_validator.zig:805–833, 844–859`
`defer allocator.free(issues)` captures the variable, not the pointer value. `issues` is reassigned twice per scope, so `validatePointerType`/`validateArrayType` allocates three times but only the last slice is freed — two leaks per scope.

```zig
var issues = validator.validatePointerType(...) catch unreachable;
defer allocator.free(issues);         // captures variable
issues = validator.validatePointerType(...);  // first allocation leaked
issues = validator.validatePointerType(...);  // second allocation leaked
```

**BUG-6: Integer truncation in capacity hint**
`src/pass/analysis/danger_surface.zig:84,87`
```zig
try ffi_set.ensureTotalCapacity(@as(u32, @intCast(ffi_count * 2)));
try ffi_hash_set.ensureTotalCapacity(@as(u32, @intCast(ffi_count * 2)));
```
`ffi_count * 2` overflows silently when cast to `u32`. In large IRs (1M+ functions) this allocates far less than intended, causing OOM or rehash failures. Other files (e.g., `type_mapping_validator.zig`) use `ensureTotalCapacity` without `@intCast` — inconsistency across the codebase.

**BUG-7: `std.mem.span` without null guard in `ffi_analysis.zig:231`**
```zig
const func_name_ptr = c.LLVMGetValueName(func);
if (@intFromPtr(func_name_ptr) == 0) continue;
const func_name = std.mem.span(func_name_ptr);
```
This site is safe. However, the pattern `std.mem.span(name_ptr)` **without a preceding null check** is widespread in `pass/analysis/ffi/`:
- `ffi_boundary.zig:281, 287` — guarded with `if (@intFromPtr(...) != 0)` in the same function, but other branches in the same file do not
- `ffi_call_analyzer.zig:96–102` — `called_name = std.mem.span(called_name_ptr)` where `called_name_ptr` is `c.LLVMGetValueName(called_val)` which can return null
- `ffi_type_mismatch.zig` — multiple unguarded sites
- `ffi_boundary_check.zig:140, 175, 255, 275, 291` — batch of unguarded spans

**BUG-8: Silent diagnostic loss from bulk `catch {}`**
`danger_surface.zig:90–92`, `ptr_lifetime.zig:462,484`, `inline_ir_matrix.zig:2194`, `ffi_type_mismatch.zig:238`, `pipeline.zig:1495` — all silently swallow OOM errors from `addIssue`, `put`, `append`. In OOM scenarios (e.g., large IRs, leaky tests), the user sees zero issues reported with no warning.

**BUG-9: `arena_threadlocal.zig` `initCapacity(0) catch unreachable` with no justification**
`src/common/arena_threadlocal.zig:98, 117` — `std.ArrayList(*Arena).initCapacity(backing_allocator, 0) catch unreachable` will hard-abort if a custom allocator errors on zero-capacity requests. Compare with `src/fact/store.zig:46` which documents the same pattern explicitly. The absence of a comment here suggests copy-paste rather than deliberate design.

**BUG-10: `ptr_lifetime_report.zig:869–870` — silently swallow error followed immediately by crash on the same operation type**
```zig
candidate.addEvidence("Heap pointer returned to caller (potential factory pattern)") catch {};
candidate.addEvidenceFmt("Function: {s}", .{func_name}) catch unreachable;
```
If `addEvidenceFmt` can fail, both should be handled consistently. The adjacent `_ = diag` suppression (line 861) suggests the function's diagnostic strategy is split and unclear.

---

## 🟡 MEDIUM — Dead code / incomplete features

**DEAD-1: `src/whitelists/rust_internal.zig` (282 lines) — completely orphaned**
File headers itself as `//! DEPRECATED` and directs callers to `mangling.isRustInternal()`. Global search for `@import("whitelists/rust_internal")` outside the file itself returns zero. The static table and its internal tests are dead weight.

**DEAD-2: `lookupSourceFile()` built but never called**
`src/config/language_override.zig:193–200` — `source_file_map` is populated from the `--source-lang` CLI flag, but `lookupSourceFile()` is not called by any analysis pass. The TODO at line 193 confirms this. Feature "Scenario 3 (--source-lang)" is fully inert.

**DEAD-3: `isZigSafeCimport` superseded but still re-exported**
`src/pass/analysis/ffi/ffi_zone_check.zig:124` — marked `/// DEPRECATED: Use classifyCSafetyLevel()`, but `ffi_boundary.zig:78` re-exports it as `pub const is_zig_safe_cimport = zone_check.isZigSafeCimport`. The semantics changed from a single `bool` return to a three-tier `CSafetyLevel?` system; downstream callers of the re-export still receive a degraded `true/false` without the richer classification.

**DEAD-4: `SemanticMapper` removal references left behind as migration noise**
- `src/root.zig:334`: `// NOTE: SemanticMapper types removed (dead code, 2026-05-04)`
- `src/lifetime/boundary.zig:29`: `// NOTE: mapper module removed (dead code, 2026-05-04)`
- `tests/main.zig:468,559,579,787`: four `// NOTE: ... Tests removed (2026-05-04)`
- `benches/main.zig:95,212`

No active imports remain, so no compile errors — but these notes accumulate as stale migration documentation that is never cleaned up.

**DEAD-5: `debug_info.zig` `getLanguage()` and `getCompileUnit()` are permanent stubs**
`src/ir/debug_info.zig:191, 220` — blocked by missing LLVM C API accessors. `getLanguage()` always returns `.C`; `getCompileUnit()` always returns `null`. Any pass relying on DWARF CU language for classification is effectively hardcoded to assume C.

**DEAD-6: `isZigInternalFunction` and `isGoInternalFunction` are identical wrappers**
`ffi_zone_check.zig:109–118` — both delegate to `PatternRegistry.isLanguageInternal()` with no behavioral distinction. The naming implies Zig-specific vs Go-specific logic, but neither has any differentiation.

---

## 🔵 LOW — Style / inconsistency / comment accuracy

**ANOMALY-1: Module doc-comment contradicts `n.zig` changelog history**
`CHANGELOG.md` and `CHANGELOG_zh.md` both reference `n.zig` (e.g., "R8-C3 | n.zig | JS panning NaN fix"). The file was renamed to `graph_visualizer.zig` at commit `953c433`. The changelog entry was never updated.

**ANOMALY-2: `semantic_registry.zig:257` — note contradicts lock implementation**
`// NOTE: Not thread-safe — registerHook/runHooks must be called from a single thread` — but the same file uses `std.atomic.Value` with `swap`/`store` for double-checked locking at line 111–112. Either the note is stale or the lock is unnecessary.

**ANOMALY-3: `semantics/noise_filter.zig:55` — `FunctionSurface` count mismatch**
`// NOTE: New code should prefer FunctionSurface (7 values)...` — but `FunctionSurface` has 11+ values (including `notification_receiver`, `runtime_internal`, `rust_drop_glue`, etc.). The stated count of 7 is incorrect.

**ANOMALY-4: Cross-language free detection always receives `.unknown`**
Both call sites of `classifyFreeLanguage` hard-code `caller_lang = .unknown` (documented in `bugs.md` item #12, `cross_lang_dataflow.zig:~1371`). The function's fallback `return caller_lang` was designed to propagate the caller's language for unrecognized custom deallocators — with `.unknown` always passed, this fallback is dead code.

**ANOMALY-5: `memory_graph.zig:301, 379` — `errdefer freeNode` on path that may also `defer`**
`errdefer graph.freeNode(node)` runs on error. If a nested block in the same function also has a `defer` that frees the same node on success, an error after the inner block's success path causes a double-free. No current caller exhibits this, but the risk is structural.

**ANOMALY-6: `export_surface_analyzer.zig:134, 302` — `std.mem.span` without null guard**
`const callee_name = std.mem.span(callee_name_ptr)` — inconsistent with the majority of files that guard with `if (@intFromPtr(name_ptr) != 0)` first.

---

## 📊 Summary Priority Matrix

| # | Priority | Category | File | Lines | Root cause |
|---|----------|----------|------|-------|------------|
| 1 | 🔴 | Dead feature | `file_config.zig` | 111 | TODO stub — JSON overrides silently no-op |
| 2 | 🔴 | Wrong tooling | `run_full_test.sh` | 107 | Arg order inverted — all CI comparison data is 0 |
| 3 | 🔴 | Dead code | `whitelists/rust_internal.zig` | 1 | 282 lines, zero callers |
| 4 | 🔴 | Dead code | `lookupSourceFile()` | 193–200 | Built, never called |
| 5 | 🟠 | Memory leak | `type_mapping_validator.zig` | 805–859 | defer on reassigned variable |
| 6 | 🟠 | Silent truncation | `danger_surface.zig` | 84, 87 | `@intCast(ffi_count * 2)` → u32 |
| 7 | 🟠 | Null deref risk | `ffi_analysis.zig` + siblings | multiple | `std.mem.span` without null guard |
| 8 | 🟠 | Silent failure | multiple files | 6 sites | `addIssue/put catch {}` drops diagnostics |
| 9 | 🟡 | Dead stub | `debug_info.zig` | 191, 220 | Always returns .C / null (LLVM gap) |
| 10 | 🟡 | Inaccurate doc | `graph_visualizer.zig` | 21–28 | References non-existent API names |
| 11 | 🟡 | Stale docs | `CHANGELOG*.md` | — | References `n.zig` which never existed |

---

## 🔑 Recommended fix order

1. **Fix `run_full_test.sh` arg order** (10-line fix, unblocks all CI metrics)
2. **Fix `type_mapping_validator` defer-with-reassignment** (use scoped blocks or `.toOwnedSlice()`+free per call)
3. **Remove or rewire `whitelists/rust_internal.zig`** (282-line deletion)
4. **Add null guards to unguarded `std.mem.span` calls in `pass/analysis/ffi/`**
5. **Replace `catch {}` with `diag.warn` or propagate error** in `danger_surface` and `ptr_lifetime`
6. **Fix `graph_visualizer.zig` doc-comment** to match actual API
7. **Update `CHANGELOG*.md`** to reference `graph_visualizer.zig` instead of `n.zig`
