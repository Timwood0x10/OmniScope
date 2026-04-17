# Changelog

All notable changes to OmniScope will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-04-17

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

#### CI/CD Integration
- **GitHub Actions**: Complete workflow for automated security analysis
- **GitHub Code Scanning**: Native integration with GitHub Security
- **CI Runner**: Programmatic API for CI/CD pipeline integration

#### Analysis Passes
- **CFG Pass**: Control Flow Graph construction
- **DFG Pass**: Data Flow Graph construction
- **Taint Pass**: Taint source/sink tracking
- **Lock Pass**: Deadlock detection analysis
- **FFI Detector**: FFI boundary identification
- **FFI Semantics**: FFI function semantics database
- **Call Graph**: Inter-procedural call graph analysis

### Technical Details

#### Architecture
- **Pass Manager**: Dependency-aware pass execution system
- **Fact Store**: Unified fact storage and querying
- **Diagnostic Aggregator**: Centralized issue reporting
- **IR View**: Safe LLVM IR abstraction layer

#### Memory Management
- Proper ownership semantics for Issue and TraceEntry
- Memory leak fixes in HashMap operations
- Safe string handling with owned/borrowed distinction

#### Testing
- 112 unit tests passing
- Integration tests with real LLVM IR
- End-to-end pipeline tests

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
