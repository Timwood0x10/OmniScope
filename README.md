# OmniScope

```shell
    `....                                `.. ..
  `..    `..                         `.`..    `..
`..        `..`... `.. `.. `.. `..      `..         `...   `..    `. `..     `..
`..        `.. `..  `.  `.. `..  `..`..   `..     `..    `..  `.. `.  `..  `.   `..
`..        `.. `..  `.  `.. `..  `..`..      `.. `..    `..    `..`.   `..`..... `..
  `..     `..  `..  `.  `.. `..  `..`..`..    `.. `..    `..  `.. `.. `.. `.
    `....     `...  `.  `..`...  `..`..  `.. ..     `...   `..    `..       `....
                                                                   `..
```

**Cross-Language FFI & Memory Safety Static Analyzer**

The only static analysis tool that detects memory safety vulnerabilities **across language boundaries** at the LLVM IR level.

Supports **C / C++ / Rust / Zig / Go**. Finds what compilers miss.

[English](./README.md) | [简体中文](./README_zh.md)

***

## What is OmniScope?

OmniScope is a specialized static analyzer focused on **FFI (Foreign Function Interface) boundaries** — where code from one language calls code from another. These boundaries are blind spots for every compiler:

- Rust's borrow checker stops at `extern "C"` functions
- C compiler cannot track Rust ownership semantics
- Go's runtime has no visibility into C memory management
- **OmniScope fills this gap** by analyzing LLVM IR — a language-independent intermediate representation

### Core Innovation: Zone Classification

OmniScope doesn't analyze everything equally. It classifies code into three zones:

| Zone                 | Meaning                              | Action                      |
| -------------------- | ------------------------------------ | --------------------------- |
| **Safe Zone**        | Code with language safety guarantees | Skip (trust compiler)       |
| **Runtime Internal** | Standard library / runtime code      | Skip (trust official impl.) |
| **Unknown Zone**     | FFI / unsafe / cross-language code   | Deep analysis               |

**Result**: 64% of code skipped, 100% focus on dangerous areas.

```
Before: "Found 185 UAFs"  →  ❌ Many false positives
After:  "Analyzed 267 funcs, skipped 171 (64%), found 48 issues"  ✅ Clear & credible
```

***

## Why It Matters

```mermaid
graph LR
    subgraph Rust["Rust Compiler"]
        R1["Ownership Check"]
        R2["Borrow Check"]
    end

    subgraph C["C Compiler"]
        C1["No Memory Safety Check"]
    end

    subgraph Blind["Blind Spots"]
        B1["FFI Boundary"]
        B2["unsafe Block"]
    end

    R1 --> B1
    R2 --> B1
    C1 --> B1
    B1 --> B2
```

**Real production crash at 2 AM**:

```
double free detected in thread 0
  pointer 0x7f3a4c002010
  previously freed at: rust::ffi::Box::into_raw -> c_wrapper::process -> free
  second free at: rust::drop::Drop::drop -> Box::from_raw -> free
```

Rust handed memory to C via `Box::into_raw()`, C called `free()`, but Rust's `Drop` trait didn't know and freed it again. **Compilers don't check across language boundaries.**

> *Full story*: [To Everyone Who's Been Burned by FFI](./docs/TOUSER/en.md)

***

## Key Features

### Detection Capabilities (20 Issue Types)

| Category          | Issues                                                      | Examples                                                  |
| ----------------- | ----------------------------------------------------------- | --------------------------------------------------------- |
| **Memory Safety** | leak, UAF, double-free, null-deref, buffer-overflow         | `malloc()` without `free()`, use after `free()`           |
| **FFI Security**  | borrow\_escape, cross-language-free/leak, JNI type mismatch | Rust `Box` freed by C, stack pointer escapes to FFI       |
| **Data Flow**     | tainted-path-to-sink, command-injection, format-string      | User input reaches `system()`, unsanitized `%s` in printf |
| **Concurrency**   | data-race, thread-safety-violation                          | Shared state without locks                                |

### Unique Capabilities

- **5-Language Support**: C, C++, Rust, Zig, Go (only tool with this coverage)
- **LLVM IR Level Analysis**: Language-agnostic, works on compiled output
- **Rust FFI Specialized**: Detects `Box::into_raw`/`Box::from_raw` mismatches, `&mut *ptr` escape patterns
- **SARIF Output**: Direct integration with GitHub Code Scanning
- **Zero False Positive Mode**: Configurable confidence thresholds

***

## Architecture

```mermaid
flowchart LR
    subgraph Source["Source Code"]
        Rust[Rust]
        Cpp[C/C++]
        Zig[Zig]
        Go[Go]
    end

    subgraph Compile["Compilation"]
        C1[clang -emit-llvm]
        C2[rustc --emit=llvm-ir]
        C3[zig build-llvm]
    end

    subgraph Analysis["OmniScope"]
        A1[Zone Classification]
        A2[Memory Safety Analysis]
        A3[FFI Boundary Detection]
    end

    Rust --> C2
    Cpp --> C1
    Zig --> C3
    Go --> C1
    C1 & C2 & C3 --> |.ll/.bc| A1 --> A2 --> A3
```

### Two-Tier Analysis Pipeline

```mermaid
flowchart TD
    Start[Input LLVM IR] --> Parse[Parse Functions/Blocks/Instructions]
    Parse --> Zone{Zone Classification}
    
    Zone -->|Safe Zone| Skip1[Skip - Trust Compiler]
    Zone -->|Runtime Internal| Skip2[Skip - Trust Official Impl.]
    Zone -->|Unknown Zone| Analyze[Deep Analysis]
    
    Analyze --> Own[Ownership Tracking]
    Own --> FFI[FFI Boundary Detection]
    FFI --> Taint[Taint Propagation]
    Taint --> Filter[Noise Filtering]
    Filter --> Report[Generate Report JSON/SARIF]
    
    Skip1 --> Report
    Skip2 --> Report
```

**Tier 1 (Pass-Through)**: Pure safe code → Zone Classification marks as Safe Zone → Skipped entirely

**Tier 2 (Graph-Driven)**: FFI/unsafe code → Full pipeline runs → Ownership tracking + FFI detection + Taint propagation

*Full details*: [Architecture Documentation](./docs/architecture.md)

***

## Quick Start

### Prerequisites

| Tool | Version | Install                                                                    |
| ---- | ------- | -------------------------------------------------------------------------- |
| Zig  | 0.15+   | [ziglang.org/download](https://ziglang.org/download) or `brew install zig` |
| LLVM | 18～22   | `brew install llvm@22` (recommended for .ll files)                         |

### Build & Run

```bash
# Clone
git clone https://github.com/your-org/OmniScope.git
cd OmniScope

# Build (Debug mode for development)
zig build -Ddebug-safe

# Or build ReleaseFast for production
zig build -Drelease-fast

# Analyze a single file
./zig-out/bin/OmniScope target.ll

# JSON output (for CI/CD integration)
./zig-out/bin/OmniScope target.ll --json > report.json

# SARIF output (for GitHub Code Scanning)
./zig-out/bin/OmniScope target.ll --sarif > results.sarif
```

### Example: Analyze Rust FFI Library

```bash
# Convert .ll to .bc (if needed)
/opt/homebrew/opt/llvm@22/bin/llvm-as corpus/ring.ll -o /tmp/ring.bc

# Run analysis
./zig-out/bin/OmniScope /tmp/ring.bc --json

# Expected output:
#   functions: 410
#   issues: 16 (including 4 borrow_escape)
#   FFI boundaries: 4,252
#   Time: ~2 seconds
```

### Batch Analysis (All Corpus Files)

```bash
# Run comprehensive analysis on all test files
./scripts/full_corpus_analysis_final.sh

# Results saved to: outputs/full_analysis_v017_final/
# Summary: 40/42 files analyzed (95.2% success rate), 586 issues found
```

*Detailed tutorial*: [Quick Start Guide (10 min)](./docs/QUICK_START.md)

***

## Real-World Validation

Tested on **42 real-world projects** (v0.1.7 final, LLVM 22):

| Project            | Language | Functions | Issues  | FFI Boundaries | Success |
| ------------------ | -------- | --------- | ------- | -------------- | ------- |
| **sqlite3**        | C        | 3,346     | **136** | 1,717          | ✅       |
| **curl8**          | C        | 1,245     | **49**  | 1,567          | ✅       |
| **jsoncpp195**     | C++      | 2,070     | **5**   | 482            | ✅       |
| **wasmtime\_test** | Rust     | 987       | **45**  | 129            | ✅       |
| **blst**           | Rust+C   | 416       | **51**  | 1,446          | ✅       |
| **ring**           | Rust+C   | 410       | **16**  | 4,252          | ✅       |
| **abseil2024**     | C++      | 1,124     | **1**   | 422            | ✅       |
| **gnark\_test**    | Go       | 916       | **4**   | 5,221          | ✅       |
| ...                | ...      | ...       | ...     | ...            | ...     |

**Total**: 16,986 functions analyzed, **586 issues** detected, **63,554 FFI boundaries** identified

**Success Rate**: 95.2% (40/42 files), 0 crashes (memory leaks fixed)

*Full verification report*: [Verification Report v0.1.7](./docs/investigation_reports/en/FULL_VERIFICATION_V017.md) (**A- grade**, ABCDE rating: 89.4/100)

***

## Performance

| Metric                  | Value                                  | Notes                                     |
| ----------------------- | -------------------------------------- | ----------------------------------------- |
| **Analysis Speed**      | \~150ms per 1K functions (ReleaseFast) | sqlite3 (3.3K funcs): \~12s               |
| **Memory Usage**        | \~120MB per 1K functions (Release)     | Debug mode: \~400MB                       |
| **Success Rate**        | 95.2% (40/42 files)                    | LLVM 22 compatible                        |
| **False Positive Rate** | \~9% overall                           | Red team tests: 0 FP on critical patterns |
| **Test Coverage**       | 343/343 passing                        | All bug fixes verified                    |

| File Scale         | Debug Mode | ReleaseFast |
| ------------------ | ---------- | ----------- |
| <100 functions     | <1s        | <200ms      |
| 100-500 functions  | 1-5s       | <1s         |
| 500-3000 functions | 5-20s      | 1-5s        |
| >3000 functions    | 20s+       | 5-15s       |

***

## Comparison

| Tool          | Input           | Cross-Language FFI    | IR-Level      | Taint Analysis | Ownership Tracking | Open Source    | Performance        |
| ------------- | --------------- | --------------------- | ------------- | -------------- | ------------------ | -------------- | ------------------ |
| **OmniScope** | **LLVM IR**     | **✅ (5 languages)**   | **✅**         | **✅**          | **✅**              | **Apache 2.0** | **\~150ms/Kfuncs** |
| CodeQL        | Source/AST      | ⚠️ (per-lang queries) | ❌             | ✅              | ⚠️                 | MIT            | \~minutes          |
| Clang SA      | AST             | ❌ (C/C++ only)        | ❌             | ✅              | ⚠️                 | Apache 2.0     | \~seconds          |
| Infer         | Source/AST      | ❌                     | ❌             | ✅              | ⚠️                 | MIT            | \~seconds          |
| CBMC          | Source/C        | ❌ (C only)            | ❌ (bit-level) | ❌              | ✅                  | BSD            | \~minutes-hours    |
| Miri          | MIR (Rust only) | ❌                     | ❌             | ❌              | ✅                  | MIT/Rust       | \~minutes          |

**Key Differentiators**:

1. ✅ **Only tool** focused on **cross-language FFI boundaries**
2. ✅ **Only tool** analyzing at **LLVM IR level** (language-agnostic)
3. ✅ **Only tool** with **Zone Classification** (smart filtering)
4. ✅ **Only tool** supporting **5 languages** in unified analysis

***

## Documentation

### Getting Started (Recommended Reading Order)

| Document                                            | For             | Time   |
| --------------------------------------------------- | --------------- | ------ |
| **[Quick Start Guide](./docs/QUICK_START.md)** ⭐    | New users       | 10 min |
| **[API Reference](./docs/API_REFERENCE.md)**        | Integrators     | 30 min |
| **[Examples](./docs/EXAMPLES.md)**                  | Practical usage | 15 min |
| **[Architecture](./docs/architecture.md)**          | Architects      | 20 min |
| **[Developer Guide](./docs/en/developer_guide.md)** | Contributors    | 15 min |

### Reports & Benchmarks

| Document                                                                                  | Content                                               |
| ----------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| **[Full Verification v0.1.7](./docs/investigation_reports/en/FULL_VERIFICATION_V017.md)** | Complete validation + **ABCDE rating: A-** (89.4/100) |
| **[Test Report](./docs/TEST_REPORT_v017.md)**                                             | 343/343 tests passing                                 |
| **[Benchmark Report](./docs/BENCHMARK.md)**                                               | Performance data                                      |

### Concept Papers

| Document                                                            | Topic                     |
| ------------------------------------------------------------------- | ------------------------- |
| **[White Paper](./docs/WHITEPAPER.md)**                             | Technical deep-dive       |
| **[Zone Classification Philosophy](./docs/ZONE_CLASSIFICATION.md)** | Core innovation explained |
| **[Letter to Users](./docs/TOUSER/en.md)**                          | Why this project exists   |

### Multi-Language Support

- 🇺🇸 English: This README + `docs/en/`
- 🇨🇳 简体中文: [README\_zh.md](./README_zh.md) + `docs/zh/`

***

## Limitations

1. Requires LLVM IR input (`clang -emit-llvm` or `rustc --emit=llvm-ir`)
2. Debug info (`-g`) recommended for source location mapping
3. Indirect calls via function pointers resolved heuristically
4. Primarily intra-procedural analysis (ownership tracking supports inter-procedural)
5. Some exotic FFI patterns may require custom rules

---

## Contributing

We welcome contributions! See [Developer Guide](./docs/en/developer_guide.md) for:

- Development environment setup
- Code style guidelines (Zig idioms)
- Testing requirements (343 tests must pass)
- Pull request process

**Current Test Status**: ✅ 343/343 passing

***

## Acknowledgements

Special thanks to [@icehawk-hyb](https://github.com/icehawk-hyb) for serving as technical advisor and providing critical guidance on cross-language security analysis.

***

## License

[Apache 2.0](./LICENSE)

***

## Citation

If you use OmniScope in research, please cite:

```bibtex
@tool{omniscope,
  title = {OmniScope: Cross-Language FFI and Memory Safety Static Analyzer},
  author = {TimWood},
  year = {2026},
  url = {https://github.com/Timwood0x10/OmniScope}
}
```

