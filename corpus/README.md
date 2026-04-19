# OmniScope Test Corpus

This directory contains test IR files for benchmarking and integration testing.

## Directory Structure

```
corpus/
├── small/          # ~100 functions, quick tests
├── medium/         # ~1K functions, realistic projects
├── large/          # ~10K+ functions, stress tests
└── ffi-dense/      # FFI-heavy projects (primary target)
```

## Corpus Categories

### Small (Quick Tests)
- `hello.ll` - Minimal program
- `simple_loop.ll` - Basic control flow
- `ffi_basic.ll` - Single FFI call

### Medium (Realistic Projects)
- `rust_ffi_demo.ll` - Rust → C FFI
- `cpp_wrapper.ll` - C++ → C wrapper
- `go_cgo.ll` - Go → C via cgo

### Large (Stress Tests)
- `sqlite_binding.ll` - SQLite FFI binding
- `openssl_wrapper.ll` - OpenSSL wrapper
- `zlib_binding.ll` - zlib binding

### FFI-Dense (Primary Target)
- `rust_box_into_raw.ll` - Ownership transfer
- `rust_cstring_raw.ll` - String FFI
- `zig_allocator_c.ll` - Zig → C allocator
- `swift_unsafe_ptr.ll` - Swift unsafe pointer

## Adding New Test Cases

1. Compile source to LLVM IR:
   ```bash
   clang -S -emit-llvm -O0 -fno-discard-value-names -g source.c -o output.ll
   ```

2. Place in appropriate directory based on function count

3. Add expected results to `tests/integration/`

## Metrics Collected

| Metric | Description |
|--------|-------------|
| Functions | Number of functions in IR |
| Instructions | Total LLVM instructions |
| FFI Calls | Cross-boundary calls detected |
| Issues | Security issues found |
| Analysis Time | Time to analyze (ms) |
| Memory | Peak memory usage (MB) |

---

## Language Detection Limitations

OmniScope's cross-language analysis (e.g., `cross_lang_free_mismatch`, `borrow_escape`, `null_dereference`, `boundary_error`) relies on **function naming conventions** to identify the language of allocation/deallocation calls. If these conventions are not followed, the analysis may fail to detect cross-language violations.

### Required Naming Patterns

| Language | Pattern | Examples |
|----------|---------|----------|
| **Rust** | `_R` prefix (RFC 2603 v0 mangling) or contains `alloc::`, `core::`, `std::` | `_RZN4alloc5alloc17hba3a1b2c3d4e5f6g`, `into_raw`, `from_raw`, `drop_in_place` |
| **C++** | `_Z` prefix (Itanium C++ ABI mangling) or `operator new/delete` | `_Z12cpp_rust_mismatchv`, `operator new`, `operator delete` |
| **Zig** | Contains `Allocator.` or `allocImpl` | `zig_allocator_allocImpl`, `Allocator.alloc` |
| **C** | Standard libc functions | `malloc`, `free`, `calloc`, `realloc`, `printf` |
| **Go (cgo)** | `_cgo_` prefix or `C.` prefix | `_cgo_allocate`, `C.malloc`, `C.free` |

### Why Certain Features May Not Be Detected

1. **cross_lang_free_mismatch**: Requires identifying that an allocation from one language is freed by another. If the callee function name doesn't match the expected pattern, the language is classified as `unknown`, and cross-language mismatches cannot be detected.

2. **borrow_escape**: Requires lifetime analysis and semantic action tracking. This depends on:
   - Correct language identification for semantic registry lookup
   - Debug information (debug line/column) for precise tracking
   - Proper semantic action annotations (alloc, free, borrow, transfer, reclaim, escape)

3. **null_dereference**: Requires:
   - Debug information to track pointer null checks
   - Control flow analysis to determine when pointers might be null
   - Boundary analysis at FFI call sites

4. **boundary_error**: Requires:
   - Size parameter analysis (e.g., zero-size, max-size, negative-size casts)
   - Boundary analyzer integration
   - Semantic registry for identifying boundary-critical functions

### Current Implementation Constraints

- **Language identification is name-based only**: No AST or source-level analysis. If a function doesn't follow naming conventions, it's classified as `unknown`.
- **Debug information dependency**: Precise line/column tracking and some boundary checks require `-g` (debug symbols) during compilation.
- **Callee language detection**: The analysis identifies language from the **callee** function name, not the caller. This means the allocation/deallocation function itself must have the correct naming pattern.
- **No language-specific AST parsing**: OmniScope works on LLVM IR level and cannot access language-specific type systems or semantics beyond what's exposed in the IR.

### Mitigation Strategies

For languages that don't follow standard naming conventions:
- Use wrapper functions with standard naming patterns
- Add custom semantic registry entries for non-standard function names
- Ensure debug information is included (`-g` flag)
- For custom allocators, follow the naming patterns of the target language
