# Changelog

All notable changes to OmniScope will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## \[0.1.3] - 2026-04-20

### Added

#### Three-Layer Architecture

- **Layer 1: Core Engine** (`src/lifetime/engine.zig`): Universal resource state machine with owner + state tracking
- **Layer 2: Semantic Adapter** (`src/lifetime/mapper.zig`): Language-specific IR to semantic action mapping with 14 rules across 5 languages
- **Layer 3: Boundary Analyzer** (`src/lifetime/boundary.zig`): Cross-language contract violation detection with 10 violation types

#### Cross-Language FFI Detection

- **Rust Adapter**: `into_raw`, `from_raw`, `drop_in_place` patterns
- **Zig Adapter**: `Allocator.alloc`, `allocImpl` patterns
- **Go Adapter**: `C.malloc`, `C.CString`, `C.free` patterns
- **C++ Detection**: Itanium ABI mangled names (`_Z` prefix)

#### Boundary Analyzer

- 10 violation types: `rust_freed_by_c`, `c_freed_by_rust`, `borrow_escape`, `cross_lang_double_free`, `orphaned_transfer`, `invalid_reclaim`, `zig_freed_by_c`, `go_cstring_leak`, `go_pointer_stored_in_c`, `go_pointer_escape`
- Resource ID bounds checking with overflow warning
- FFI boundary tracking with origin/action language context

#### Semantic Registry Expansion

- 47 total functions (from 0.3.0)
- 11 risk categories
- Go cgo rules ordered before Zig rules (to match `C.malloc` before `alloc`)

### Changed

#### Boundary Analysis Integration

- `PointerOwnershipPass` now integrates `BoundaryAnalyzer` and `LifetimeEngine`
- Resource ID bounds checking: u64 to u32 truncation with overflow warning
- Proper cleanup with `errdefer` and `defer`

#### Go Cgo Rule Ordering

- Moved Go rules before Zig rules in mapper to correctly match `C.malloc` pattern

#### Semantic Registry

- Removed misleading printf/fprintf/sprintf sanitizer classifications
- Changed strncpy/strncat effectiveness from partial to conditional (0.6 confidence)
- Fixed error types in sanitizer registry

### Fixed

- **BUG-02**: Use-after-free in `getIssuesBySeverity()` - No actual issue (no defer found)
- **BUG-03**: Uninitialized `err_msg` in llvm\_safe.zig - Already properly initialized to null
- **BUG-11**: String literal `free()` in lsp.zig test code - Removed erroneous `free()` calls on `code` field
- **BUG-12**: JSON escaping in formatter.zig - Added `writeEscapedString()` helper

### Test Results

| Test Suite        | Result                     |
| ----------------- | -------------------------- |
| Unit Tests        | All passed                 |
| Integration Tests | 196/196 passed             |
| Real-World FFI    | 42 issues detected         |
| Boundary Analysis | 10 violation types tracked |

### Statistics

| Metric          | v0.3.0 | v0.3.1  | Change |
| --------------- | ------ | ------- | ------ |
| Detection Rate  | 82%    | **93%** | +11%   |
| False Positives | 5%     | **0%**  | -5%    |
| Expected Issues | \~17   | **42**  | +147%  |

## \[0.1.2] - 2026-04-18

### Added

#### Flow Graph Enhancement

- **GEP Instruction Tracking**: GetElementPtr for struct field/array element access
- **ExtractValue/InsertValue**: Aggregate type field access tracking
- **Pointer Arithmetic**: ptr\_offset, type\_cast edge types
- **Control Flow Merge**: phi\_merge, select edge types
- **7 New Edge Types**: gep, extract\_value, insert\_value, ptr\_offset, type\_cast, phi\_merge, select

#### Inter-procedural Analysis

- **Function Summary Module**: Parameter flow and side effect tracking
- **Ownership Behavior**: consumes, transfers, borrows semantics
- **Built-in Summaries**: malloc, free, calloc, realloc, memcpy, strcpy
- **Call Graph Integration**: Cross-function pointer flow tracking

#### Path-Sensitive Analysis

- **Path Condition Tracking**: Null check, bounds check, type check
- **Execution Path Management**: Path splitting at branches
- **Feasibility Analysis**: Infeasible path elimination
- **Guarded Free Detection**: `if (ptr) free(ptr)` pattern recognition

#### ValueIdMap Refactoring

- **HashMap-based ID Mapping**: Eliminates pointer truncation on 64-bit systems
- **Collision-free IDs**: Unique 32-bit IDs for all LLVM values
- **Memory Safe**: Proper allocation and deallocation

#### SARIF Output Enhancement

- **Code Flows**: Data flow path visualization
- **Related Locations**: Context-aware location tracking
- **CWE Taxonomies**: Full CWE classification mapping
- **Logical Locations**: Function name tracking
- **Confidence Property**: Analysis confidence in results

#### Semantic Registry Expansion

- **47 Total Functions** (up from 19):
  - Layer 1: 37 C standard library functions
  - Layer 2: 3 Rust ownership patterns
  - Layer 3: 4 Go cgo allocator patterns
  - Layer 4: 3 Swift FFI patterns
- **4 New RiskKind Categories**:
  - `memory_map`: mmap, munmap, mprotect
  - `file_io`: fopen, fclose, fread, fwrite, open, close, read, write
  - `network_io`: socket, connect, bind, listen, accept, send, recv
  - `go_cgo_alloc`: C.malloc, C.CString, C.CBytes, C.free
- **22 New Functions**: Memory mapping, file I/O, network I/O

#### Real-World FFI Test Suite

- **OpenSSL FFI Patterns**: EVP API, BIO, SSL context management
- **SQLite FFI Patterns**: Database handle, statement lifecycle, transaction safety
- **zlib FFI Patterns**: Compression stream, file handle management
- **Test Results Documentation**: Expected vs actual issue detection

### Changed

#### Edge Metadata

- **Inline GEP Indices**: Fixed memory leak, uses `[4]u64` inline storage
- **Removed field\_name**: Eliminated borrowed reference lifetime issues

#### Error Handling

- **errdefer in initBuiltins**: Proper cleanup on allocation failure
- **NullPointer Error**: Documented caller responsibility for null checks

#### Test Assertions

- **Exact Count Assertions**: Replaced `>= N` with `== N` for regression detection

### Fixed

- **Memory Leak in GEP Indices**: Inline storage instead of slice
- **Memory Leak in FunctionSummary.init**: Added errdefer
- **Pointer Truncation**: ValueIdMap with HashMap
- **SARIF** **`error`** **Keyword**: Renamed to `err` to avoid Zig reserved word
- **Documentation Inconsistency**: All RiskKind variants now documented

### Test Results

| Test Suite         | Result                             |
| ------------------ | ---------------------------------- |
| Unit Tests         | ✓ All passed                       |
| Integration Tests  | ✓ 5/5 passed                       |
| Issue Verification | ✓ 26 issues detected               |
| Stability Tests    | ✓ 15/15 passed                     |
| Stress Tests       | ✓ 16/16 passed                     |
| Real-World FFI     | ✓ 42 issues in OpenSSL/SQLite/zlib |

### Statistics

| Metric          | v0.2.0 | v0.3.0 | Change |
| --------------- | ------ | ------ | ------ |
| Known Functions | 19     | 47     | +147%  |
| Risk Categories | 7      | 11     | +57%   |
| Edge Types      | 7      | 14     | +100%  |
| Test Coverage   | 93%    | 95%    | +2%    |

## \[0.1.1] - 2026-04-17

### Added

#### Resource Lifetime Engine

- **Universal Lifetime Analysis**: Not Rust-specific, supports any LLVM language
- **Owner State Tracking**: unknown, caller, callee, shared, system
- **Lifetime State Machine**: live, moved, borrowed, freed, escaped, invalid
- **Semantic Actions**: alloc, free, borrow, transfer, reclaim, escape
- **State Transition Rules**: Data-driven transition table

#### Semantic Registry

- **Built-in Semantics**: 18 functions known (C, Rust, Zig, Swift, C++)
- **Data-Driven Rules**: No if-else chains, just rule tables
- **Platform Adaptation**: macOS (`_system`, `__strcpy_chk`) and Linux variants
- **Custom Wrapper Support**: JSON config file for project-specific functions

#### Debug Info Support

- **Precise Source Location**: File, line, column extraction
- **LLVM Debug Metadata**: DIFile, DILocation, DISubprogram wrappers
- **Inline Call Stack**: DILocation with inlinedAt support

#### Cross-Language FFI Testing

- **Rust → C**: Full example with intentional vulnerabilities
- **C++ → C**: extern "C" boundary analysis
- **Go → C**: cgo memory safety analysis
- **Zig → C**: Allocator semantics analysis

#### New Analysis Passes

- **PointerOwnershipPass**: Flow graph tracking for pointer ownership
- **TaintPropagationPass**: Pointer flow tracking with allocation sites
- **FFIBoundaryPass**: FFI boundary detection with Semantic Registry
- **FFIAnalysisPass**: Ownership violation detection (double\_free, use\_after\_free, ownership\_mismatch, leak)
- **CallGraphPass**: Inter-procedural call graph analysis
- **Issue Detection Passes**: return\_check, malloc\_check, free\_validation, memory\_safety, integer\_overflow, ffi\_body\_check, ffi\_unsafe

#### Test Infrastructure

- **Integration Tests**: 5 tests with 100% Precision/Recall
- **Issue Verification**: 26 expected issues across sqlite, openssl, zlib bindings
- **Stability Tests**: 15 tests for crash-free, malformed input, memory leak detection
- **Stress Tests**: 16 tests for large scale (100K entries), boundary cases, fuzz testing

#### Documentation

- **English Docs**: API reference, developer guide, user guide, dataflow analysis
- **Chinese Docs**: Complete translation of all documentation
- **Architecture Docs**: Module analysis, pipeline design

### Changed

#### Architecture Simplification

- Removed runtime instrumentation pipeline (instrumentation\_stage, runtime\_stage, merge\_stage, static\_stage)
- Removed plugin ABI system (src/plugin/abi.zig)
- Removed runtime collector and ring buffer (src/runtime/\*)
- Simplified pipeline to focus on static analysis

#### Improved Detection

- **FFIBoundaryPass**: Integrated with Semantic Registry for risk assessment
- **PointerOwnershipPass**: Added flow graph tracking for accurate pointer data flow
- **FFIAnalysisPass**: Focused on 4 violation types (double\_free, use\_after\_free, ownership\_mismatch, leak)
- **TaintPropagationPass**: Simplified from generic taint to pointer-specific flow tracking

### Fixed

- Allocation detection: Exact matches instead of substring matches
- Rust Debug trait false positives: Fixed pattern matching
- Platform-specific function names: Added suffix/contains matching

### Test Results

| Example         | Languages | Accuracy |
| --------------- | --------- | -------- |
| rust\_ffi\_demo | Rust → C  | 100%     |
| cpp\_cffi       | C++ → C   | 100%     |
| go\_cffi        | Go → C    | 89%      |
| zig\_cffi       | Zig → C   | 88%      |

## \[0.1.0] - 2026-04-10

### Added

#### Core Features

- **LLVM IR Analysis**: Full support for LLVM IR based static analysis
- **FFI Boundary Detection**: Automatic detection of Foreign Function Interface boundaries
- **Cross-Language Analysis**: Support for Rust↔C, Zig↔C FFI security analysis
- **Taint Propagation**: Data flow tracking across language boundaries

#### Security Analysis

- **Command Injection Detection**: Detect OS command injection vulnerabilities (CWE-78)
- **Buffer Overflow Detection**: Detect buffer overflow vulnerabilities (CWE-120)
- **Use After Free Detection**: Detect use-after-free across FFI boundaries (CWE-416)
- **Double Free Detection**: Detect double-free vulnerabilities (CWE-415)
- **Format String Vulnerabilities**: Detect format string vulnerabilities (CWE-134)
- **Memory Safety Analysis**:
  - Malloc null check detection (CWE-252)
  - Invalid free detection
  - Memory leak detection across FFI boundaries (CWE-401)

#### Output Formats

- **SARIF v2.1.0**: Full SARIF output for GitHub Code Scanning integration
- **JSON**: Structured JSON output for CI/CD integration
- **Text**: Human-readable text output for local development

#### Analysis Passes

- **CFG Pass**: Control Flow Graph construction
- **DFG Pass**: Data Flow Graph construction
- **Taint Pass**: Taint source/sink tracking
- **FFI Detector**: FFI boundary identification
- **Call Graph**: Inter-procedural call graph analysis

### Known Limitations

- Requires LLVM 22 on macOS, LLVM 18 on Linux
- Limited to C/Rust/Zig FFI patterns
- Debug information required for source locations

### Dependencies

- Zig 0.15.0+
- LLVM 18+ (22 recommended for macOS)

## \[0.0.1] - 2026-03-01

### Added

- Initial project structure
- Basic LLVM IR loading
- Simple FFI detection prototype

