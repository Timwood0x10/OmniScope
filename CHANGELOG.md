# Changelog

All notable changes to OmniScope will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-04-17

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

### Changed

#### Architecture Simplification
- Removed unnecessary passes: SinkTracerPass, ReturnCheckPass, TaintPropagationPass
- Simplified Pass chain: CallGraph → FFIBoundary → PointerOwnership → FFIUnsafe
- Unified Fact types with ownership-specific kinds

#### Improved Detection
- **FFIBoundaryPass**: Integrated with Semantic Registry for risk assessment
- **PointerOwnershipPass**: Added Fact integration for ownership tracking
- **SinkTracerPass**: Uses Semantic Registry for sink classification

### Fixed

- Allocation detection: Exact matches instead of substring matches
- Rust Debug trait false positives: Fixed pattern matching
- Platform-specific function names: Added suffix/contains matching

### Test Results

| Example | Languages | Accuracy |
|---------|-----------|----------|
| rust_ffi_demo | Rust → C | 100% |
| cpp_cffi | C++ → C | 100% |
| go_cffi | Go → C | 89% |
| zig_cffi | Zig → C | 88% |

## [0.1.0] - 2026-04-10

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

## [0.0.1] - 2026-03-01

### Added
- Initial project structure
- Basic LLVM IR loading
- Simple FFI detection prototype
