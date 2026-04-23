# OmniScope v0.1.5

## Cross-Language FFI Static Analyzer — Rust FFI Auditor + Product-Quality Tooling

### What's New

**Rust FFI Auditor (Independent Module)**

- **`rust_ffi_auditor.zig`**: 464-line dedicated module for Rust↔C boundary analysis
- **6 detection rules**:
  - R1: Unpaired `Box::into_raw()` / `CString::into_raw()` (ownership leak)
  - R2: `as_ptr` borrow escape (dangling pointer after local drop)
  - R3: Cross-lang alloc mismatch (Rust `_Znwm` → C `free()`)
  - R4: Unsafe FFI calls without validation
  - R5: `extern "C"` type mismatch detection
  - R6: `#[no_mangle]` export ownership compliance
- **Structured audit report** with `generateReport()` for formatted output
- **7 unit tests** covering all detection helpers

**Stable JSON Schema v1**

- Machine-parseable output with stable field names:
  - `schema_version`, `tool_version`, `timestamp`
  - Per-issue: `id` (OMI-NNN), `cwe_id`, `reason`, `confidence_level`
- CLI: `--json file.ll > output.json`

**SARIF v2.1.0 Full Upgrade**

- Version: 0.1.0 → **0.1.5**
- **14 rule definitions** (all IssueKind variants)
- Properties include: `confidence`, `confidenceLevel`, `reason`, `cwe`
- GitHub Code Scanning compatible

**Confidence System with Reason Field**

- 4 levels: HIGH (≥0.90) / MEDIUM (≥0.70) / HEURISTIC (≥0.50) / EXPERIMENTAL (<0.50)
- Every issue includes machine-readable `reason` explaining confidence assignment
- Output format: `VULNERABILITY OMI-NNN [SEV] [Confidence: LEVEL]`

**Real-World Validation (10 projects, 6,441 functions)**

| Project          | Language | Functions | Issues  | Leaks | Time  |
| ---------------- | -------- | --------- | ------- | ----- | ----- |
| SQLite 3.47.2    | C        | 3,237     | 8       | **0** | 5.8s  |
| libcurl 8.14.0   | C        | 68        | 1       | **0** | 0.05s |
| libuv 1.50.0     | C        | 145       | 1       | **0** | 0.07s |
| jsoncpp 1.9.5    | C++      | 1,537     | 3       | **0** | 1.4s  |
| abseil-cpp       | C++      | 193       | 9       | **0** | 0.37s |
| ripgrep 14.1.1   | **Rust** | 75        | **0** ✅ | —     | 0.04s |
| rust\_sqlite     | **Rust** | 135       | 6       | 4     | 0.09s |
| openssl\_wrapper | C        | 52        | 19      | 7     | 0.03s |
| wasmtime\_test   | **Rust** | 974       | 1       | **0** | 2.5s  |
| wabt\_wast2json  | **C++**  | 125       | 2       | 1     | 0.07s |

### Key Results vs v0.1.4

| Metric              | v0.1.4          | v0.2.0                          | Change          |
| ------------------- | --------------- | ------------------------------- | --------------- |
| Languages supported | C/C++           | **C/C++/Rust**                  | +Rust           |
| Real-world projects | 8               | **10**                          | +WABT+Wasmtime  |
| Total functions     | \~5,500         | **6,441**                       | +17%            |
| Output formats      | Text/JSON/SARIF | **Stable JSON v1 + SARIF v2.1** | Schema locked   |
| Confidence system   | Basic score     | **4-level + reason field**      | Enhanced        |
| Report format       | Inconsistent    | **Unified OMI-NNN format**      | Standardized    |
| Code organization   | 1985-line file  | **3 files ≤1000 lines each**    | Rules compliant |

### Architecture

```
Layer 3: Boundary Analyzer (Ownership/Lifetime)
    ↓
Layer 2: Semantic Adapter (8-Layer FP Filter + Confidence)
    ↓
Layer 1: Core Engine (IR Loading/Pass Pipeline/Fact Store)
```

New modules in v0.2.0:

- `rust_ffi_auditor.zig` — Independent Rust FFI analysis module
- `allocation_classifier.zig` — AllocType/FreeType classification (split from pointer\_ownership)
- `cpp_fp_reduction.zig` — C++ 8-layer filter (split from pointer\_ownership)

### Changes

#### Memory Safety Verification

- **Full audit of 100+ allocation points** across 25+ source files
- **PassContext.deinit()** at 6 call sites (GPA zero leak confirmed)
- All HashMap/ArrayList properly paired init/deinit

#### Bug Fixes

- SARIF module crash: Fixed missing `SarifOutput` type resolution
- Unified 4 output points to consistent format

### Supported Platforms

- **macOS**: LLVM 22 (Apple M-series) ✅ Tested
- **Linux**: LLVM 18+ ✅ Expected
- **Compiler**: Zig 0.13.0+
- **LLVM IR**: Compatible with clang++ (C/C++) and rustc 1.95+ (Rust)

### Installation

```bash
# From source
git clone https://github.com/omniscope/omniscope.git
cd omniscope
zig build --release ./zig-out/bin/omniscope

# Analyze a file
./zig-out/bin/omniscope target.ll
./zig-out/bin/omniscope --json target.ll > results.json
./zig-out/bin/omniscope --sarif -o results.sarif target.ll
```

### Documentation

- [Technical Whitepaper](docs/WHITEPAPER.md) — Architecture, benchmarks, roadmap
- [README](README.md) — Quick start, architecture diagrams, project results
- [Developer Guide](docs/en/developer_guide.md) — Coding standards, contribution guide
- [API Reference](docs/en/api_reference.md) — Public API documentation

### Known Limitations

- Inter-procedural analysis planned for v0.3
- Path-sensitive phi-node merge planned for v0.4
- Go/Swift/Kotlin IR support not yet available

