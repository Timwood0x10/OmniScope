# OmniScope

**Cross-Language FFI & Memory Safety Static Analyzer for C/C++/Rust/Zig**

OmniScope analyzes LLVM IR to detect memory safety issues, FFI boundary violations, and ownership contract breaches across C/C++/Rust/Zig/Go.

## ✨ Latest Release: v0.4.1 (2026-04-24)

### 🎯 What's New in v0.4.1?

**Phase 4: Cross-Language Noise Reduction Engine — The biggest FP reduction ever!**

| Feature | Impact |
|---------|--------|
| **Three-Layer Noise Filter** | Rust wasmtime: **4023 → 9 issues (-99.8%)** |
| **FunctionOrigin Classification** | user / stdlib / compiler_generated / third_party |
| **Layer 1 Name-based Filter** | 120+ patterns for Rust/Zig/C++ stdlib functions |
| **Layer 2 Path-based Filter** | LLVM DebugInfo API for precise source file detection |
| **Layer 3 Behavior Filter** | Drop glue / allocator wrapper / STL grow detection |
| **Attribution Summary Output** | "X issues → Y user code (Z FFI HIGH)" |

### Quick Start

```bash
# Build
zig build

# Analyze an LLVM IR file
./zig-out/bin/OmniScope target.ll

# Output formats: text (default), json, sarif
./zig-out/bin/OmniScope target.ll --format json --output report.json
```

### Requirements

| Tool | Version | Install |
|------|---------|---------|
| Zig | 0.15.2+ | [zvm](https://www.zvm.app) |
| LLVM | 18+ (21 recommended) | `brew install llvm@21` / apt |

### Make Targets

```bash
make build          # Compile
make test-all       # Run all tests (unit + integration + regression + stress)
make benchmark      # Corpus detection rate metrics
make baseline-check # Real-world project regression guard
make red-team-test  # Adversarial test suite (v0.2.1+)
```

## Architecture

### System Overview (3-Layer Design)

```mermaid
graph TB
    subgraph L3["Layer 3: Boundary Analyzer"]
        BA["Boundary Analyzer"]
        BA_desc["Detect cross-language contract violations"]
    end

    subgraph L2["Layer 2: Semantic Adapter"]
        SA["Semantic Adapter"]
        RA["Rust Adapter"]
        CA["C/C++ Adapter"]
        ZA["Zig Adapter"]
        GA["Go Adapter"]
    end

    subgraph L1["Layer 1: Core Engine"]
        CE["Lifetime Engine"]
        CE_desc["Owner + State transitions"]
    end

    RA & CA & ZA & GA --> SA
    SA --> CE
    CE --> BA
```

**Core insight**: Despite language differences, all FFI operations reduce to a small set of actions:

| Action | Meaning |
|--------|---------|
| `alloc` | Allocate resource |
| `free` | Release resource |
| `borrow` | Temporary borrow |
| `transfer` | Ownership transfer |
| `retain` | Increment refcount |
| `release` | Decrement refcount |
| `escape` | Escape to unknown scope |

### Data Flow

```mermaid
flowchart LR
    subgraph Source["Source Code"]
        Rust["Rust (.rs)"]
        Cpp["C/C++ (.c/.cpp)"]
        Zig["Zig (.zig)"]
        Go["Go (.go)"]
    end

    subgraph Compile["Compile to LLVM IR"]
        LLVMRust["clang -emit-llvm"]
        LLVMC["clang -emit-llvm"]
        LLVMZig["zig build-llvm"]
        LLVMGo["go build -gcflags -e"]
    end

    subgraph IR["LLVM IR Input"]
        BC[".ll / .bc files"]
    end

    subgraph OmniScope["OmniScope Analysis Pipeline"]
        Parse["Parse + CFG/DFG"]
        Own["Ownership Tracking<br/>(8-layer FP reduction)"]
        FFI2["FFI Boundary Detection"]
        Null2["Null Dereference Check"]
        Report["Report Generation"]
    end

    subgraph Output2["Output Formats"]
        CLI2["Text / JSON / SARIF / LSP"]
    end

    Rust --> LLVMRust
    Cpp --> LLVMC
    Zig --> LLVMZig
    Go --> LLVMGo
    LLVMRust & LLVMC & LLVMZig & LLVMGo --> BC
    BC --> Parse --> Own --> FFI2 --> Null2 --> Report --> CLI2
```

### 8-Layer C++ FP Reduction System

| Layer | Technique | Target |
|-------|-----------|--------|
| L1 | STL Internal Function Filter | `_ZNSt*` template expansions |
| L2 | C++ Special Member Function Filter | ctor/dtor/copy/move-assign |
| L3 | RAII Smart Pointer Detection | `unique_ptr::C1` / `shared_ptr::C1` |
| L4 | RAII Function Set | Skip entire functions with smart ptrs |
| L5 | C++ ABI Runtime Filter | `__cxa_*` exception/guard/atexit |
| L6 | Meyers Singleton Detection | `__cxa_guard_acquire` pattern |
| L7 | C++ Operator FFI Filter | `_Znwm`/`_ZdlPv` skip in FFI reporting |
| **L8** | **RC Container Detection** | `Ref()`/`Unref()`/CordRep patterns |

## Real-World Validation (v0.4.1)

> **10 production projects, 10,000+ functions analyzed, Phase 4 noise reduction active.**

| Project | Language | Functions | Issues (v0.2.0) | Issues (**v0.4.1**) | Reduction |
|---------|----------|-----------|----------------|-------------------|-----------|
| [abseil-cpp 2024](corpus/real_world/BASELINE.md) | C++ | 193 | ~5 | **0** ✅ | -100% |
| [ripgrep 14.1.1](corpus/real_world/BASELINE.md) | Rust | 75 | ~3 | **0** ✅ | -100% |
| [wasmtime_test](corpus/real_world/BASELINE.md) | Rust | 987 | **4023** | **9** (-99.8%) | **-99.8%** 🎉 |
| [SQLite 3.47.2](corpus/real_world/BASELINE.md) | C | 3346 | ~8 | **37** | +362%* |
| [libcurl 8.14.0](corpus/real_world/BASELINE.md) | C | 68 | ~1 | **29** | +2800%* |
| [libuv 1.50.0](corpus/real_world/BASELINE.md) | C | 145 | ~1 | **30** | +2900%* |
| [rust_sqlite](corpus/real_world/BASELINE.md) | Rust | ~200 | ~21 | **88** | +319%* |
| [jsoncpp 1.9.5](corpus/real_world/BASELINE.md) | C++ | 1537 | ~3 | **35** | +1067%* |
| [openssl_wrapper](corpus/real_world/BASELINE.md) | C | ~50 | ~5 | **99** | +1880%* |
| [wabt_wast2json](corpus/real_world/BASELINE.md) | C++ | ~800 | ~40 | **85** | +113%* |

*\*Note: C/C++ project numbers increased because v0.4.1 added more detection capabilities (Type Compatibility, Lifetime Inference). These are real issues that were previously missed.*

### Corpus Benchmark

| Metric | Value |
|--------|-------|
| Precision (Rust targets) | **~78%** (up from 2%) |
| Recall | **93.2%** |
| F1 Score | **85%+** |

See full details: [`BASELINE.md`](corpus/real_world/BASELINE.md), [`ZIG_FFI_TEST_REPORT.md`](corpus/test_cases/ZIG_FFI_TEST_REPORT.md)

## Detection Capabilities

### Issue Types

| Type | Severity | Example |
|------|----------|---------|
| Memory Leak | MEDIUM | `malloc()` without `free()` |
| Use After Free | HIGH | Dereference after free |
| Double Free | HIGH | Same resource freed twice |
| Null Dereference | MEDIUM | Unchecked nullable allocation |
| Format String | MEDIUM | User-controlled `%s` in printf |
| Command Injection | CRITICAL | `system()` with user input |
| Cross-Language Violation | HIGH | Rust Box freed by C free() |

### Supported Languages & Boundaries

| Boundary | Status | Notes |
|----------|--------|-------|
| C → C | ✅ Stable | Full libc/POSIX registry |
| Rust ↔ C | ✅ **Stable (v0.1.4)** | `into_raw`/`from_raw`, `Box`, `CString` |
| Zig ↔ C | ✅ Stable | `Allocator.alloc` pattern |
| Go → C | ⚠️ Experimental | cgo `C.malloc`/`C.CString` |
| **C++ → C** | **✅ Stable (v0.1.4)** | Itanium ABI, 7-Layer FP reduction |
| Swift → C | 🔜 Planned | `retain`/`release` |

## Project Structure

```
src/
├── pass/analysis/
│   ├── pointer_ownership.zig   # Core: ownership tracking + 8-layer FP reduction
│   └── ffi_boundary.zig       # FFI boundary detection + semantic registry
├── lifetime/                   # Resource state machine (owner + state transitions)
├── registry/                   # 166-function semantic registry (6 layers)
├── pipeline/                   # Pass orchestration (15 analysis passes)
└── output/                     # CLI / JSON / SARIF / LSP formatters
```

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](docs/architecture.md) | System design & module relationships |
| [Developer Guide](docs/en/developer_guide.zig) | Coding conventions & contribution guide |
| [API Reference](docs/en/api_reference.md) | Public API documentation |
| [User Guide](docs/en/user_guide.md) | Usage tutorial & examples |
| [Benchmark Spec](docs/BENCHMARK.md) | Test methodology & phase-gated targets |
| [Baseline](corpus/real_world/BASELINE.md) | Regression rules for 5 real-world projects |
| [Final Report](corpus/real_world/FINAL_EVALUATION_REPORT.md) | English evaluation (cross-project comparison) |
| [最终测评报告](corpus/real_world/FINAL_EVALUATION_REPORT_ZH.md) | Chinese evaluation |
| [Task Plan](plan/task/tasks.md) | Development roadmap (Priority 1–9) |

## CI/CD

```yaml
# GitHub Actions — upload SARIF to Code Scanning
- uses: softprops/action-gh-release@v2
  with:
    body_path: RELEASE_NOTES.md   # Release notes (clean)
    files: dist/OmniScope-*
```

Releases are automated via [`.github/workflows/release.yml`](.github/workflows/release.yml): build Linux + macOS binaries, read [`RELEASE_NOTES.md`](RELEASE_NOTES.md).

## Limitations

1. Requires LLVM IR input (compile with `clang -emit-llvm`)
2. Debug info recommended for source-level locations (`-g` flag)
3. Indirect calls via function pointers use heuristic resolution
4. Primarily intra-procedural analysis (inter-procedural for ownership transfer)

## License

Apache 2.0
