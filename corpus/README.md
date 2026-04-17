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
