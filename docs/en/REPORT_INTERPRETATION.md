# How to Interpret OmniScope Reports

This guide explains how to read OmniScope findings and map them back to source code. It focuses on the 0.2.0 report model, where semantic resolution and surface classification provide more context for FFI security triage.

## Triage workflow

1. **Start with severity**: fix `critical` and `high` first.
2. **Check confidence**: prioritize `HIGH` and `MEDIUM`; manually confirm `LOW`.
3. **Read the issue kind**: decide whether it is ownership, lifetime, type, taint, or concurrency related.
4. **Inspect the function name**: demangle or map it to source when needed.
5. **Verify the boundary**: confirm that ownership or data crosses a language/runtime boundary.
6. **Confirm allocator family**: allocator and deallocator must belong to the same runtime family.

## Core fields

| Field | Meaning | How to use it |
|-------|---------|---------------|
| `kind` | Issue category, such as `borrow_escape`, `memory_leak`, `cross_lang_free_mismatch` | Identifies the bug class and likely fix pattern |
| `severity` | `critical`, `high`, `medium`, or `low` | Drives remediation priority |
| `confidence` | `HIGH`, `MEDIUM`, or `LOW` | Indicates how much manual validation is needed |
| `confidence_score` | Numeric confidence from 0.0 to 1.0 | Useful for CI thresholds and report diffs |
| `cwe_id` | CWE mapping | Helps integrate with security review and SARIF tooling |
| `location.function` | Function containing the evidence | Starting point for source/IR navigation |
| `message` | Human-readable explanation | Summarizes the detected ownership or boundary problem |

## Severity and confidence

| Severity | Typical meaning | Example |
|----------|-----------------|---------|
| `critical` | Likely exploitable undefined behavior or memory corruption | stack pointer escaping to FFI, use-after-free |
| `high` | Cross-runtime ownership violation or strong memory-safety risk | Rust allocation freed by C `free()` |
| `medium` | Needs review; may be a real leak or ownership loss | owned pointer crosses FFI and is never released |
| `low` | Informational or weak heuristic | suspicious but incomplete boundary evidence |

| Confidence | Interpretation | Triage action |
|------------|----------------|---------------|
| `HIGH` | Strong syntactic and semantic evidence | Treat as actionable unless source disproves it |
| `MEDIUM` | Likely bug, but context may matter | Inspect source and allocator ownership |
| `LOW` | Heuristic signal | Use as review guidance, not an automatic blocker |

## Example 1: Rust allocation freed by C

Source example: `corpus/red_team_test/rust_ffi_bugs.c`

```c
void rust_01_alloc_c_free(void) {
    void* ptr = _RZN4alloc5alloc17h_allocate(128);
    strcpy((char*)ptr, "allocated in Rust");
    free(ptr);  /* BUG: C free() on Rust-allocated memory */
}
```

How to interpret the finding:

- `kind`: usually `cross_lang_free_mismatch`, `cross_language_free`, or a related ownership issue.
- `severity`: normally `high` because the pointer is allocated by Rust and released by the C allocator family.
- `location.function`: `rust_01_alloc_c_free` tells you the source function containing the mismatch.
- Evidence to check: allocation symbol resembles Rust allocator output, while the sink is C `free()`.
- Fix direction: expose a Rust-owned release API, or ensure C only returns the pointer to Rust for deallocation.

The important question is not “does this pointer get freed?” but “does the same runtime that allocated it also free it?”

## Example 2: `Box::into_raw` passed to C and freed incorrectly

Source example: `corpus/red_team_test/rust_ffi_bugs.c`

```c
void rust_03_box_raw_c_free(void) {
    void* boxed = _RZN3std3box8into_rawE(NULL);
    free(boxed);  /* BUG: should use Box::from_raw to reclaim */
}
```

How to interpret the finding:

- `Box::into_raw` intentionally transfers a raw pointer out of Rust's type system.
- C `free()` does not run Rust drop glue and may use the wrong allocator.
- A valid design usually provides a paired Rust function that calls `Box::from_raw` once.
- If a report also mentions double free, check whether both C and Rust believe they own the pointer.

Recommended review questions:

- Is there exactly one documented owner after `Box::into_raw`?
- Is there exactly one deallocation path?
- Is that deallocation path implemented in Rust, not plain C `free()`?

## Example 3: C allocation freed by Rust

Source example: `corpus/red_team_test/rust_ffi_bugs.c`

```c
void rust_02_c_alloc_rust_free(void) {
    void* ptr = malloc(256);
    strcpy((char*)ptr, "allocated in C");
    _RZN4alloc5alloc17h_deallocate(ptr);  /* BUG: Rust free on C memory */
}
```

How to interpret the finding:

- The allocation site belongs to C (`malloc`).
- The deallocation site belongs to Rust allocator semantics.
- Even when both allocators use the same system heap on one platform, this is not portable or contract-safe.
- The fix is to release with the matching C API or wrap the pointer in a Rust type with a custom C deallocator.

## Example 4: Dangling reference stored across FFI

Source example: `corpus/red_team_test/rust_ffi_bugs.c`

```c
static void* g_stored_rust_ref = NULL;

void rust_04_store_rust_ref(void) {
    void* rust_obj = _RZN4alloc5alloc17h_allocate(64);
    g_stored_rust_ref = rust_obj;
    _RZN4alloc5alloc17h_deallocate(rust_obj);
    memset(g_stored_rust_ref, 0, 64);  /* UAF */
}
```

How to interpret the finding:

- A pointer crosses into longer-lived C storage (`g_stored_rust_ref`).
- The original runtime deallocates the object.
- Later use through the stored pointer becomes use-after-free.
- Surface classification helps distinguish this from ordinary local pointer flow because the pointer escapes into global state.

Fix patterns include copying data, using reference-counted ownership with clear release rules, or requiring C to unregister the pointer before Rust frees it.

## Example 5: Real project-style FFI wrappers

Source examples: `examples/real_world/sqlite_ffi.c`, `examples/real_world/openssl_ffi.c`, `examples/real_world/zlib_ffi.c`

These files model common wrapper mistakes: unchecked allocation, missing cleanup on error paths, and mismatched ownership contracts. When reading a report for these examples:

- Treat wrapper entry points as boundary functions.
- Identify whether a returned pointer is owned, borrowed, or only valid until the next call.
- Check all early returns for cleanup.
- Verify whether library-specific deallocators are required instead of generic `free()`.

## Reading mangled function names

Reports may contain mangled names because OmniScope works at LLVM IR level.

| Prefix or pattern | Likely source | Meaning |
|-------------------|---------------|---------|
| `_Z...` | C++ Itanium ABI | C++ function or operator symbol |
| `_R...` or Rust legacy `_ZN...` | Rust | Rust function, allocator, drop glue, or std/alloc symbol |
| `Py...` | CPython | Python C API or extension boundary |
| `Java_...` or JNI types | Java/JNI | Native method or JNI helper |
| `runtime.*`, `_Cgo_*` | Go/TinyGo | Runtime or CGo boundary |

When the function name looks like runtime/compiler internals, check whether the report explains why it still matters. In 0.2.0, semantic resolution and surface classification are designed to suppress pure runtime noise and keep user-relevant boundary evidence.

## CI usage

For automated gating:

```bash
./zig-out/bin/OmniScope target.bc --json > report.json
./zig-out/bin/OmniScope target.bc --sarif > results.sarif
```

Suggested default policy:

- Fail builds on `critical` findings with `HIGH` or `MEDIUM` confidence.
- Warn on `high` findings until the project has a stable baseline.
- Store JSON reports to compare issue counts and confidence changes across releases.
- Upload SARIF when using GitHub Code Scanning.

## False-positive review checklist

Before suppressing a finding, verify:

- The reported function is truly compiler/runtime internal, not user wrapper code.
- The allocator and deallocator are intentionally compatible on all supported platforms.
- Ownership transfer is documented and enforced by API design.
- The pointer does not escape into global state, callbacks, background threads, or delayed cleanup.
- The report is not pointing at an error path that normal tests rarely execute.

Suppress only after documenting the ownership contract. Most FFI bugs are contract bugs, not local syntax bugs.
