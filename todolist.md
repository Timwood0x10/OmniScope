# OmniScope Development Roadmap

**Version**: v0.1.5 → v0.2.0
**Updated**: 2026-04-25
**Positioning**: Multi-Language Unsafe/FFI Boundary Static Analyzer

***

编码风格严格按照：./plan/rules/\*.md 禁止自我发挥。

## Core Principle

> **Analyze only where language guarantees stop.**

OmniScope scans where modern languages become unsafe:

- Rust `unsafe {}`, Zig `extern`, Go `cgo`, C++ ABI boundaries.

***

## Completed Phases

### Phase 1: Zone Classifier ✅

| Task                                                                   | Status |
| ---------------------------------------------------------------------- | ------ |
| Create `src/semantics/zone_classifier.zig`                             | Done   |
| Define `ZoneKind` enum (safe, unsafe, ffi, runtime\_internal, unknown) | Done   |
| Implement Rust safe/escape pattern recognition                         | Done   |
| Implement Zig safe/escape pattern recognition                          | Done   |
| Implement Go safe/escape pattern recognition                           | Done   |
| Implement C++ safe/escape pattern recognition                          | Done   |
| Implement `ZoneStats` statistics                                       | Done   |
| Unit tests                                                             | Done   |

**Verify**: `zig build test` passed

### Phase 2: Pipeline Integration ✅

| Task                                                      | Status |
| --------------------------------------------------------- | ------ |
| Modify `PassContext` to support Zone filtering            | Done   |
| Skip Safe Zone and Runtime Internal functions in analysis | Done   |
| Add Zone statistics output to CLI                         | Done   |
| Log level control (`--quiet` / `--verbose` / `--debug`)   | Done   |

**Verify Results**:

| Project  | Functions Analyzed      | Skip Ratio | Issues Found |
| -------- | ----------------------- | ---------- | ------------ |
| ring     | 278 total, 0 analyzed   | **100%**   | 0            |
| blst     | 267 total, 96 analyzed  | **64%**    | 48           |
| wasmtime | 619 total, 159 analyzed | **74%**    | 96           |

***

## Active Development Phases

### Phase 3: Cross-Language Noise Reduction Engine

**Goal**: Reduce false positives by distinguishing user code from compiler-generated/runtime code.

**Reference**: `plan/lang_ffi_analysis/plan.md`

#### 3.1 Layer 1: Name-based Filter (Fastest)

**File**: `src/semantics/noise_filter.zig`

| Language | Skip Patterns                                                                                 | Match Patterns                              |
| -------- | --------------------------------------------------------------------------------------------- | ------------------------------------------- |
| **Rust** | `core::`, `alloc::`, `std::`, `panic_`, `drop_in_place`, `RawVec`, `Vec<`, `slice::`, `fmt::` | `_ZN4core`, `_ZN5alloc`, `_RNv`, `$LT$core` |
| **Zig**  | `std.`, `mem.Allocator`, `array_list`, `hash_map`, `fmt.`, `heap.`                            | -                                           |
| **C++**  | `std::`, `__gnu_cxx::__`, `__cxa_`, `__clang_call_terminate`                                  | -                                           |
| **Go**   | `runtime.`, `_Cfunc_`, `_cgo_`                                                                | -                                           |

**Tasks**:

- [ ] Create `FunctionOrigin` enum (user, stdlib, compiler\_generated, third\_party)
- [ ] Implement name-based filter for each language
- [ ] Add risk weighting system
- [ ] Unit tests for each language filter

**Verify**: `make test-unit && make check`

#### 3.2 Layer 2: Path/Debug Metadata Filter (Most Accurate)

**File**: `src/semantics/path_filter.zig`

LLVM IR contains source location via debug metadata:

```llvm
!DIFile(filename: "/rustc/.../library/core/src/ptr/mod.rs")
!DIFile(filename: ".../zig/lib/std/array_list.zig")
```

**Filter Rules**:

| Language | Suppress Paths                                               |
| -------- | ------------------------------------------------------------ |
| **Rust** | `/rustc/`, `library/core/`, `library/std/`, `cargo/registry` |
| **Zig**  | `zig/lib/std/`                                               |
| **C++**  | `/usr/include/c++/`, `/libc++/`                              |

**Tasks**:

- [ ] Parse LLVM debug metadata (`!DIFile`)
- [ ] Extract source path from metadata
- [ ] Classify function origin based on path
- [ ] Handle cases without debug info (fallback to Layer 1)
- [ ] Unit tests with real .ll files

**Verify**: `make test-int && make check`

#### 3.3 Layer 3: Behavior Filter (Smartest)

**File**: `src/semantics/behavior_filter.zig`

Detect runtime patterns by analyzing instruction sequences:

| Pattern               | Instructions                            | Classification               |
| --------------------- | --------------------------------------- | ---------------------------- |
| Rust drop glue        | `free + memset + branch + panic`        | `compiler_generated_cleanup` |
| Zig allocator wrapper | `call alloc + store len + return slice` | `allocator_adapter`          |
| STL vector grow       | `malloc -> memcpy -> free old buffer`   | `reallocation`               |

**Tasks**:

- [ ] Implement drop glue detection (Rust)
- [ ] Implement allocator wrapper detection (Zig)
- [ ] Implement STL pattern detection (C++)
- [ ] Combine with Layer 1+2 results
- [ ] Unit tests with synthetic patterns

**Verify**: `make test-unit && make check`

#### 3.4 Output: Attribution Grouping

**File**: `src/pass/report/attribution.zig`

Transform output format:

```
Before: 191 issues
After:
  191 issues
  ├── 162 from Zig stdlib (suppressed)
  ├── 21 user code medium risk
  └── 8 FFI boundary high risk
```

**Tasks**:

- [ ] Group issues by `FunctionOrigin`
- [ ] Apply suppression rules
- [ ] Format grouped output
- [ ] CLI option `--focus-user-code`
- [ ] CLI option `--ffi-only`
- [ ] CLI option `--include-stdlib`
- [ ] Integration tests

**Verify**: `make test-int && make e2e-test`

***

### Phase 4: Escape Zone Deep Analysis

**Goal**: Deep analysis of Escape Zone functions to find real bugs.

**Reference**: `plan/lang_ffi_analysis/*.md`

#### 4.1 Raw Pointer Lifetime Tracker

**File**: `src/pass/analysis/ptr_lifetime.zig`

Track raw pointer lifecycle in unsafe code:

```rust
// Detect: stack pointer escapes to C callback
unsafe {
    let ptr = &local_var;
    c_callback(ptr);  // BUG: pointer outlives callback
}
```

**Analysis Points**:

- Allocation site (stack vs heap)
- Transfer to FFI boundary
- Use after potential free
- Return from function scope

**Tasks**:

- [ ] Build pointer allocation map
- [ ] Track pointer flow through instructions
- [ ] Detect escape to extern function
- [ ] Detect use-after-scope
- [ ] Unit tests with known patterns

**Verify**: `make test-unit && make check`

#### 4.2 Callback Escaping Detector

**File**: `src/pass/analysis/callback_escape.zig`

Detect Go cgo pointer retention bugs:

```go
// Detect: Go pointer retained by C after call
var buf []byte{1, 2, 3}
C.process(C.CBytes(string(buf)))  // C retains pointer
// Go GC may reclaim buf while C still uses it
```

**Reference**: `plan/lang_ffi_analysis/go_ffi_fliter.md`

**Key Patterns**:

- `import "C"` detection
- `C.xxx` call identification
- `unsafe.Pointer` conversion tracking
- GC lifetime mismatch detection

**Tasks**:

- [ ] Identify cgo boundary functions
- [ ] Track Go -> C pointer transfers
- [ ] Detect missing `runtime.KeepAlive`
- [ ] Detect missing `C.free` / `C.malloc` pairs
- [ ] Unit tests with corpus/ffi-dense examples

**Verify**: `make test-int && make check`

#### 4.3 ABI Mismatch Detector

**File**: `src/pass/analysis/abi_mismatch.zig`

Detect packed struct ABI issues:

```zig
// Detect: packed struct ABI mismatch
const Packed = packed struct { a: u32, b: u8 };
extern fn c_func(p: Packed) void;  // C expects different layout
```

**Reference**: `plan/lang_ffi_analysis/zig_ffi_filter.md`

**Check Items**:

- Packed struct passed across FFI
- Alignment mismatch between caller/callee
- Endianness issues in cross-platform code
- Variadic argument type mismatches

**Tasks**:

- [ ] Detect packed struct in extern calls
- [ ] Check alignment compatibility
- [ ] Warn on potentially unsafe ABI usage
- [ ] Unit tests with Zig FFI examples

**Verify**: `make test-unit && make check`

#### 4.4 Thread Crossing Detector

**File**: `src/pass/analysis/thread_crossing.zig`

Detect thread safety violations at FFI boundary:

```cpp
// Detect: exception crosses C boundary
extern "C" void cpp_callback() {
    throw std::runtime_error("error");  // Undefined behavior!
}
```

**Check Items**:

- Exception crossing C boundary
- Shared state without synchronization
- Callback invoked from wrong thread
- Lock order inversion across FFI

**Tasks**:

- [ ] Detect exception propagation to extern
- [ ] Track shared mutable state
- [ ] Detect lock acquisition in callbacks
- [ ] Unit tests with threading patterns

**Verify**: `make test-stability && make check`

***

### Phase 5: Multi-Language FFI Analysis Enhancement

**Goal**: Enhance language-specific FFI detection using research from `plan/lang_ffi_analysis/`.

#### 5.1 Rust FFI Enhancement

**Reference**: `plan/lang_ffi_analysis/rust_ffi_filter.md`

**Enhancements**:

- [ ] Intrinsic classification (200+ intrinsics categorized)
- [ ] Extern C function detection via Linkage + CallingConvention
- [ ] User function filtering via InstanceKind
- [ ] Drop glue suppression
- [ ] Monomorphization noise reduction

**Priority Intrinsics to Track**:

| Category    | Examples                                             | Risk Level |
| ----------- | ---------------------------------------------------- | ---------- |
| Memory ops  | `copy`, `copy_nonoverlapping`, `volatile_load/store` | HIGH       |
| Pointer ops | `offset`, `arith_offset`, `ptr_mask`                 | HIGH       |
| Type cast   | `transmute`, `transmute_unchecked`                   | HIGH       |
| Varargs     | `va_arg`, `va_copy`, `va_start/end`                  | MEDIUM     |
| Exception   | `catch_unwind`                                       | MEDIUM     |

**Verify**: `make test-int && make check`

#### 5.2 Go FFI Enhancement

**Reference**: `plan/lang_ffi_analysis/go_ffi_fliter.md`

**Enhancements**:

- [ ] `import "C"` detection via AST patterns
- [ ] `C.xxx` call identification
- [ ] `//export` directive handling
- [ ] CGo glue code filtering (`_cgo_gotypes.go`)
- [ ] `#cgo nocallback/noescape` directive support

**Key Source Locations** (from Go source):

- `src/cmd/cgo/ast.go:64-116` - import "C" parsing
- `src/cmd/cgo/ast.go:224-265` - C.xxx reference collection
- `src/cmd/cgo/out.go:34-306` - Glue code generation

**Verify**: `make test-int && make check`

#### 5.3 Zig FFI Enhancement

**Reference**: `plan/lang_ffi_analysis/zig_ffi_filter.md`

**Enhancements**:

- [ ] Extern function detection via `InternPool.Key.Extern`
- [ ] User function classification via Nav status
- [ ] Exported function tracking
- [ ] `@cImport` / `@cInclude` scope analysis
- [ ] Packed struct ABI warning

**Key IR Identifiers**:

- `Nav.status == .@"extern"` -> External C function
- `Nav.analysis != null` -> User defined function
- `Inst.Tag.runtime_nav_ptr` -> Runtime extern access

**Verify**: `make test-unit && make check`

#### 5.4 Java JNI Support (Future)

**Reference**: `plan/lang_ffi_analysis/java_ffi_filter.md`

**Planned Features**:

- [ ] Native method detection via `JVM_ACC_NATIVE` flag
- [ ] JNI naming rule validation (`Java_Package_Class_Method`)
- [ ] JNI internal function filtering (`JNI_*`, `JVM_*`)
- [ ] Special native method table lookup
- [ ] Resource leak detection (GetStringUTFChars without Release)

**Note**: Requires class file parser or bytecode input support.

**Verify**: TBD

***

### Phase 6: Regression Testing & Quality Gate

**Goal**: Ensure all changes maintain quality standards.

#### 6.1 Regression Test Suite

| Project        | Test Command         | Expected Result            |
| -------------- | -------------------- | -------------------------- |
| blst           | `make test-blst`     | Issues < 10, FP rate < 20% |
| ring           | `make test-ring`     | Issues < 5, FP rate < 20%  |
| wasmtime       | `make test-wasmtime` | Real bugs detected         |
| zlib-binding   | `make test-zlib`     | All leaks detected         |
| sqlite-binding | `make test-sqlite`   | All UAFs detected          |

**Tasks**:

- [ ] Create regression test scripts for each project
- [ ] Baseline issue counts
- [ ] Automated comparison against baseline
- [ ] Update investigation reports

**Verify**: `make test-all && make check`

#### 6.2 Performance Benchmarks

| Metric              | Current  | Target        |
| ------------------- | -------- | ------------- |
| blst analysis time  | 836ms    | < 500ms       |
| ring analysis time  | 269ms    | < 200ms       |
| Memory usage        | baseline | < 2x baseline |
| False positive rate | \~50%    | < 20%         |

**Tasks**:

- [ ] Run `make bench-perf` before/after each phase
- [ ] Profile hot paths
- [ ] Optimize bottlenecks
- [ ] Document performance changes

**Verify**: `make bench-perf && make bench-compare`

#### 6.3 Stability Tests

**Tasks**:

- [ ] Run `make test-stability` (crash-free, malformed input)
- [ ] Run `make test-stress` (large scale, boundary, fuzz)
- [ ] Run `make test-e2e` (end-to-end pipeline)
- [ ] Fix any crashes or panics found

**Verify**: `make test-stability && make test-stress && make e2e-test`

***

## Future Phases (Post-v0.2.0)

### Phase 7: SARIF Output & IDE Integration

- [ ] Standardized SARIF output format
- [ ] VS Code extension
- [ ] GitHub Code Scanning integration
- [ ] CI/CD pipeline integration

### Phase 8: Web Dashboard

- [ ] Analysis result visualization
- [ ] Trend tracking across versions
- [ ] Team collaboration features

### Phase 9: Enterprise Features

- [ ] Custom rule engine
- [ ] Team policy configuration
- [ ] SSO integration
- [ ] Audit logging

***

## Coding Standards (Mandatory)

All development must follow:

1. **File size limit**: Single files must not exceed 1000 lines
2. **Code simplicity**: Prefer straightforward solutions, avoid unnecessary abstractions
3. **Comments**: All comments in English, code-to-comment ratio \~7:3
4. **Testing**: Every function needs happy path, boundary, and error path tests
5. **Naming**: TitleCase for types, camelCase for functions, snake\_case for variables
6. **No shadowing**: Use descriptive names instead
7. **Surgical changes**: Touch only what you must, match existing style

**Before committing**:

```bash
make fmt      # zig fmt .
make check    # Type check
make test     # Run all tests
make bench    # Performance benchmarks
```

***

## Verify Commands Summary

| Command               | Purpose                | Run When               |
| --------------------- | ---------------------- | ---------------------- |
| `make fmt`            | Format code            | Before every commit    |
| `make check`          | Type check             | Before every commit    |
| `make build`          | Build project          | After any code change  |
| `make test-unit`      | Unit tests             | After any logic change |
| `make test-int`       | Integration tests      | After pass changes     |
| `make test-stability` | Stability tests        | Before release         |
| `make test-stress`    | Stress tests           | Before release         |
| `make bench-perf`     | Performance benchmarks | After optimization     |
| `make test-all`       | Full test suite        | Before merge           |

***

## Success Criteria

> **Will this bug crash in production, and is it hard to catch with ASAN?**

If yes, OmniScope should detect it.

**Target Metrics** (end of Phase 6):

| Metric                  | Target                   |
| ----------------------- | ------------------------ |
| False Positive Rate     | < 20%                    |
| Real Bug Detection Rate | > 80%                    |
| Analysis Time (blst)    | < 500ms                  |
| Noise Reduction         | > 90% (from 297 to < 30) |

