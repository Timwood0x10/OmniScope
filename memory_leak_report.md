# OmniScope Memory Leak Report
> Generated: 2026-06-05

## Summary

**3 confirmed double-free / use-after-free bugs** and **1 confirmed memory leak** identified via static analysis.
No GPA runtime output was collected (bash execution was unavailable for test runs).

---

## GPA Runtime Output

No GPA runtime output — bash execution was unavailable during this analysis. All findings below are from static analysis of the source code.

---

## Confirmed Bugs (Double-Free / Use-After-Free)

### 1. Double-free of `message` in `from_library_borrow` branch

- **File**: `src/pass/analysis/issue/free_validation.zig:826`
- **Root cause**: `Issue.initWithTrace` sets `issue.owned = true`, meaning the `message` pointer is adopted by the issue. `ctx.addIssue(&issue)` → `DataFlowGraph.addIssue` deep-copies the message, then calls `mutable_issue.deinit()` which frees the original `message`. The caller then unconditionally frees `message` again on line 826.
- **Code**:
  ```zig
  // Line 802-826
  const message = try std.fmt.allocPrint(ctx.allocator, "Invalid free: ...", .{...});
  var issue = Issue.initWithTrace(.invalid_free, message, location, .critical, 0.90, trace);
  // issue.owned = true (set by initWithTrace)
  errdefer issue.deinit(ctx.allocator);
  try ctx.addIssue(&issue);     // addIssue -> DataFlowGraph.addIssue -> deinit frees message
  ctx.allocator.free(message);  // BUG: double-free — message already freed by addIssue
  ```
- **All code paths affected**: Whether the issue is suppressed, filtered, or accepted — `addIssue` always calls `deinit` on the owned original before returning.
- **Fix**: Remove line 826 (`ctx.allocator.free(message)`). `Issue.initWithTrace` already captures ownership; `addIssue` will free the original via `deinit`.

---

### 2. Double-free of `msg` and `trace` in `callback_escape.zig`

- **File**: `src/pass/analysis/callback_escape.zig:290,295,299` and `307,312,316`
- **Root cause**: Same pattern as bug #1. `Issue.initWithTrace` adopts `msg` and `trace` (sets `owned=true`). `addIssue` deep-copies them and frees the originals. Then the `defer free(msg)` and `defer free(trace)` fire at end of scope — double-freeing both.
- **Code**:
  ```zig
  // Lines 287-299 (Rust unpaired transfer block)
  const msg = std.fmt.allocPrint(...) catch { return result; };
  defer wctx.ctx_ptr.allocator.free(msg);         // BUG: fires after addIssue already freed msg
  const trace = wctx.ctx_ptr.allocator.alloc(...) catch { ... };
  defer wctx.ctx_ptr.allocator.free(trace);       // BUG: fires after addIssue already freed trace
  var issue = Issue.initWithTrace(.cross_language_leak, msg, ..., trace);
  issue.owned = true;
  wctx.ctx_ptr.addIssue(&issue) catch {};         // frees msg + trace via deinit chain

  // Lines 304-316 (Python DECREF block) — identical pattern
  ```
- **Fix**: Remove both `defer` statements. Since `issue.owned = true` and `initWithTrace` is used, ownership is transferred through `addIssue`. Alternatively, use `Issue.init` with `issue.owned = false` (the correct pattern for `defer`-freed messages) — in that case `addIssue` will clone the message and the defer is safe.

---

### 3. Double-free of `msg` in `jni_leak_detector.zig`

- **File**: `src/pass/analysis/issue/jni_leak_detector.zig:372,391-393`
- **Root cause**: `message` allocated, `defer free(message)` set, `Issue.init(...)` called (sets `owned=false` by default), then `issue.owned = true` is set manually. Because `owned=true`, `addIssue` does NOT re-clone the message in `PassContext.addIssue` (line 766 condition `!final_issue.owned` is false). `DataFlowGraph.addIssue` deep-copies and then frees the original via `deinit`. The `defer` then fires — double-free.
- **Code**:
  ```zig
  // Lines 367-393
  const message = try std.fmt.allocPrint(ctx.allocator, "[OMI-JNI-LEAK] ...", .{...});
  defer ctx.allocator.free(message);  // BUG: fires after addIssue already freed message

  var issue = Issue.init(issue_kind, message, location, severity, 0.85);
  issue.owned = true;                 // adopts message pointer
  try ctx.addIssue(&issue);          // deep-copies + frees original message via deinit
  ```
- **Fix**: Remove the `defer ctx.allocator.free(message)` on line 372. Ownership is transferred by setting `issue.owned = true`. Alternatively, remove `issue.owned = true` and keep the `defer` (the safer pattern for `Issue.init`-based issues).

---

## Confirmed Memory Leaks

### 4. Leaked `expected` and `actual` strings in `abi_compat_checker.zig`

- **File**: `src/pass/analysis/ffi/abi_compat_checker.zig:326-327`, also `591-592`, `609`, `651-652`
- **Root cause**: `AbiMismatchInfo.expected` and `AbiMismatchInfo.actual` are allocated via `allocPrint` for certain mismatch kinds (param count, param type mismatches). The struct is passed by value into `reportAbiMismatch`, which uses these strings only to create new trace strings via `makeTrace`. The originals (`mismatch.expected`, `mismatch.actual`) are never freed — `AbiMismatchInfo` has no `deinit` method and no cleanup path.
- **Code**:
  ```zig
  // Lines 318-330 — check 1 (param count mismatch)
  const mismatch = AbiMismatchInfo{
      .expected = try std.fmt.allocPrint(ctx.allocator, "{d} parameters", .{callee_sig.param_count}),  // LEAK
      .actual   = try std.fmt.allocPrint(ctx.allocator, "{d} parameters", .{caller_sig.param_count}),  // LEAK
      ...
  };
  reportAbiMismatch(ctx, call_inst, mismatch, diag) catch {};
  // mismatch goes out of scope: expected and actual are leaked
  ```
  Same pattern at lines 584-610 (call site analysis) and 644-652 (per-param type mismatches).
- **Note**: Line 343-344 and other `AbiMismatchInfo` instances that use compile-time string literals for `expected`/`actual` are NOT leaks.
- **Fix**: Add a `deinit(allocator)` method to `AbiMismatchInfo` that checks if `expected`/`actual` are heap-allocated (e.g., by tracking an `owned_expected: bool` flag), or restructure the call sites to free after use:
  ```zig
  const expected = try std.fmt.allocPrint(ctx.allocator, "{d} parameters", .{callee_sig.param_count});
  defer ctx.allocator.free(expected);
  const actual = try std.fmt.allocPrint(ctx.allocator, "{d} parameters", .{caller_sig.param_count});
  defer ctx.allocator.free(actual);
  const mismatch = AbiMismatchInfo{ .expected = expected, .actual = actual, ... };
  reportAbiMismatch(ctx, call_inst, mismatch, diag) catch {};
  ```

---

## Suspected Leaks (Static Analysis)

### 5. `cross_issue.message` ownership in `checkFreeCall` cross-lang path

- **File**: `src/pass/analysis/issue/free_validation.zig:625-627`
- **Pattern**: `detectCrossLanguageFree` allocates `cross_issue.message` via `allocPrint`. It is passed to `reportCrossLangFreeIssue` which wraps it in an `Issue.initWithTrace` (owned=true). When the issue is suppressed by `addIssue`, the message is freed via `deinit`. When the issue is accepted, the graph takes ownership. This is **correct** as long as the `errdefer issue.deinit` in `reportCrossLangFreeIssue` (line 1842) handles OOM failures.
- **Confidence**: Low — code looks correct on the happy path. The only risk is if `cross_issue.message` leaks on `try reportCrossLangFreeIssue(...)` failure after message allocation but before the errdefer fires — but the errdefer covers this.
- **Verdict**: Likely false positive. Leaving here for review.

---

## False Positives Dismissed

### `PassContext.deinit` — `contract_db` not explicitly deinited

`contract_db: FFIContractDB` is not called in `PassContext.deinit`. However, `FFIContractDB.deinit()` is a no-op (it just calls `self.* = undefined` — no heap is freed). The `FFIContractDB` uses only compile-time constant data (`builtinLibraries()` returns pointers to static arrays). **Not a leak.**

### `PassContext.deinit` — `evidence: ?ir_evidence.IREvidence` not freed

`IREvidence` is a plain struct of scalar fields with no heap allocations. `EvidenceCollector.deinit()` is explicitly a no-op ("No owned buffers in MVP"). **Not a leak.**

### `registry_cache` and `zone_cache` — `.clearAndFree()` without key freeing

Both `StringHashMap` instances use LLVM-owned function name strings as keys (from `c.LLVMGetValueName`, which are C strings backed by the LLVM module). LLVM owns these strings — they must NOT be freed by Zig. `.clearAndFree()` only frees the backing hash table storage, not the keys. **Correct behavior.**

### `rust_into_raw_set` / `rust_from_raw_set` — `.deinit()` without key freeing

Keys are `fir.name` slices from `FunctionIR`, which are `c.LLVMGetValueName`-backed strings owned by LLVM. Same reasoning as above — these should NOT be freed. **Correct behavior.**

### `cross_edge_by_callee` — keys are shared with `cross_lang_edges`

Keys are `edge.callee_name` pointers — the same memory as in `cross_lang_edges.items[i].callee_name`. These are freed in the edge loop at lines 475-480 before `cross_edge_by_callee.deinit()`. **Correct order.**

### `zig_tracker` in `pipeline.zig:614` — no deinit

`zig_alloc_tracker.Tracker` holds only an allocator reference (`struct { allocator: Allocator }`). No heap allocations. **Not a leak.**

### Double `zig_tracker.calculateLeakConfidence` call per record

`pipeline.zig` calls `calculateLeakConfidence` twice per leak record (lines 707-725 and 817-835). This is a logic bug (confidence adjusted twice) but not a memory leak.

---

## Summary Table

| # | File | Line | Type | Severity |
|---|------|------|------|---------|
| 1 | `src/pass/analysis/issue/free_validation.zig` | 826 | Double-free (message) | High |
| 2 | `src/pass/analysis/callback_escape.zig` | 290, 295 | Double-free (msg + trace) | High |
| 3 | `src/pass/analysis/issue/jni_leak_detector.zig` | 372 | Double-free (message via defer) | High |
| 4 | `src/pass/analysis/ffi/abi_compat_checker.zig` | 326-327, 591-592, 609, 651-652 | Memory leak (expected/actual strings) | Medium |
