# OmniScope Development Plan

## Project Overview

OmniScope is a research-oriented LLVM analysis tool focused on cross-language data flow tracking and FFI boundary security.

**Core Value Proposition:**
- Tracks data flow across Rust ↔ C boundaries
- Detects vulnerabilities invisible to single-language analyzers

**Current Architecture (v3):**
- `call-graph`: Builds function call relationships
- `taint-propagation`: Forward propagation of tainted data
- `ffi-boundary`: Identifies cross-language transitions
- `sink-tracer`: Reconstructs source-to-sink paths

---

## Phase 1: Demo Enhancement (Priority: HIGHEST)

### 1.1 Security Report Output Format

Replace debug-style output with structured security reports.

**Target Output Format:**
```
=== OmniScope Security Analysis Report ===
Timestamp: 2024-01-15 10:30:00
Module: examples/ntt.bc
Functions: 30 | Edges: 45 | Sources: 3 | Sinks: 7

------------------------------------------------------------------------
[CRITICAL] Command Injection Path Detected
------------------------------------------------------------------------
Vulnerability ID:   OMI-001
Severity:           CRITICAL
Confidence:         HIGH (0.92)

Path:
  [Source]     main() - user input entry
    └─> [Tainted] debug_output()
         └─> [FFI Boundary: internal → external_unknown]
              └─> [Sink] _system() - arbitrary command execution

Impact:
  - Attacker can execute arbitrary shell commands
  - Potential for full system compromise

------------------------------------------------------------------------
[WARN] Format String Vulnerability
------------------------------------------------------------------------
Vulnerability ID:   OMI-002
Severity:           HIGH
Confidence:         MEDIUM (0.78)

Path:
  [Source]     process_coefficients() - file input
    └─> [Tainted] debug_output()
         └─> [Sink] __snprintf_chk() - format string injection

------------------------------------------------------------------------
SUMMARY
------------------------------------------------------------------------
Total Paths Analyzed:  127
Critical Issues:       1
High Issues:          1
Medium Issues:        0
Low Issues:           0

FFI Boundaries Crossed: 3
Cross-Language Flow:    YES (Rust → C via external_unknown)
```

**Files to Modify:**
- `src/pass/analysis/call_graph.zig` - Replace `std.debug.print` with report builder
- `src/pass/analysis/sink_tracer.zig` - Generate structured FlowPath objects
- `src/report/mod.zig` (NEW) - Report generation and formatting

### 1.2 Killer Demo: Rust + C FFI

Create a demo that demonstrates Rust "safety" being bypassed via C FFI.

**Demo Structure:**

```
examples/rust_ffi_demo/
├── src/
│   ├── lib.rs           # Rust safe wrapper with sanitization
│   ├── ffi_bindings.rs  # FFI declarations
│   └── main.rs          # Entry point
└── c_lib/
    ├── dangerous.h      # C header
    └── dangerous.c      # Vulnerable C implementation
```

**Rust Code (looks safe):**
```rust
pub fn process_input(input: &str) -> Result<(), Error> {
    // Sanitization - removes semicolons
    let sanitized = input.replace(";", "");

    // Still unsafe! The C library will call system()
    let c_str = CString::new(sanitized).unwrap();
    unsafe {
        dangerous_process(c_str.as_ptr());
    }
    Ok(())
}
```

**C Code (actually dangerous):**
```c
void dangerous_process(char* input) {
    char buf[64];
    strcpy(buf, input);  // Buffer overflow
    system(buf);          // Command injection
}
```

**Expected OmniScope Output:**
```
[CRITICAL] Cross-Language Data Flow to Sink
Path:
  [Rust] main() → process_input()
    └─> [Rust] sanitized replacement (ineffective)
         └─> [FFI Boundary: Rust → C]
              └─> [C] dangerous_process()
                   └─> [C] strcpy() - buffer overflow
                   └─> [C] system() - command injection

Cross-Language: YES (Rust → C)
Risk: Remote Code Execution
```

### 1.3 Compilation Instructions

Add to `examples/README.md`:
```bash
# Compile C library
cd examples/rust_ffi_demo/c_lib
gcc -c -emit-llvm -O0 dangerous.c -o dangerous.bc
ar rcs libdangerous.a dangerous.o

# Compile Rust (requires rustc with LLVM backend)
rustc --crate-type=lib --emit=llvm-bc src/lib.rs -o lib.rs.bc

# Link both IR files
llvm-link lib.rs.bc dangerous.bc -o combined.bc

# Analyze with OmniScope
./zig-out/bin/OmniSope combined.bc
```

---

## Phase 2: Pass Stabilization (Priority: HIGH)

### 2.1 CallGraph Pass Verification

**Current Issues to Fix:**
- [x] `findCallsInFunction`: Uses `LLVMIsACallInst` correctly
- [x] Node/Edge memory management with `defer`
- [ ] Missing edges: Direct function calls via function pointers
- [ ] Indirect calls: `invoke` instructions in exception handling

**Test Requirements:**
```zig
test "CallGraph - all functions discovered" {
    // Load known IR file
    // Verify all expected functions present
    // Verify no phantom functions
}

test "CallGraph - complete edge detection" {
    // For each known call site in C source
    // Verify edge exists in graph
}
```

### 2.2 Taint Propagation Verification

**Current Behavior:**
- Sources: `main`, `read`, `gets`, `scanf`, `getenv`
- Propagation: Forward (caller → callee)
- Limit: 8 iterations to prevent infinite loops

**Edge Cases:**
- [ ] Recursive functions (should not infinite loop)
- [ ] Mutual recursion (A→B→A→B...)
- [ ] Unreachable code paths
- [ ] Function pointer callbacks

**Test Requirements:**
```zig
test "TaintPropagation - recursive function termination" {
    // Create IR with recursive calls
    // Verify propagation terminates after max_iterations
    // Verify no stack overflow
}

test "TaintPropagation - mutual recursion" {
    // A calls B, B calls A
    // Verify both marked tainted after propagation
}
```

### 2.3 FFIBoundary Pass Verification

**Definition:**
- FFI Boundary = `external_unknown` (not libc)
- libc functions are trusted

**Test Requirements:**
```zig
test "FFIBoundary - libc not marked as FFI" {
    // malloc, free, system should NOT be FFI boundaries
    // system is libc, not external_unknown
}

test "FFIBoundary - external functions marked correctly" {
    // Custom C functions linked at runtime
    // Should be marked as external_unknown → FFI boundary
}
```

### 2.4 SinkTracer Pass Verification

**Current Implementation:**
- Uses `edges` and `taintedBy` for path reconstruction
- Classifies risk as `medium` or `critical`

**Missing Features:**
- [ ] Full path output with all intermediate nodes
- [ ] Cross-language indicator in output
- [ ] Confidence score calculation

---

## Phase 3: Test Quality (Priority: HIGH)

Per `zig_coding_guide.md` Section VIII: Tests must detect hidden bugs.

### 3.1 Unit Test Requirements

**Current Status:** Minimal tests exist

**Required Tests:**

```zig
test "CallGraph.Node - field access" {
    const node = Node{
        .id = 1,
        .name = "test_func",
        .kind = .internal,
        .isExternal = false,
        .isTainted = false,
        .taintedBy = null,
    };
    try std.testing.expectEqual(@as(u32, 1), node.id);
    try std.testing.expectEqualStrings("test_func", node.name);
}

test "TaintPropagation - source identification" {
    // Verify main is identified as source
    // Verify taintedBy is null for sources
}

test "SinkTracer - path reconstruction" {
    // Create known graph structure
    // Verify path from sink to source is correct
    // Verify all intermediate nodes present
}

test "FFIBoundary - edge classification" {
    // external_unknown → FFI boundary
    // libc → NOT FFI boundary
    // internal → NOT FFI boundary
}
```

### 3.2 Integration Tests

**Location:** `tests/cross_lang_test.zig`

**Requirements:**
- Load real LLVM IR files
- Verify complete analysis pipeline
- Check output format matches specification

---

## Phase 4: Documentation (Priority: MEDIUM)

### 4.1 README.md Structure

```
OmniScope
=========

Universal LLVM Analysis Framework for Cross-Language Security

⚠️ Research Project - Not Production Ready

Features
--------
- Cross-language data flow tracking
- FFI boundary detection
- Source-to-sink path analysis

Quick Start
-----------
$ zig build
$ ./zig-out/bin/OmniSope examples/ntt.bc

Architecture
------------
- PassManager: Orchestrates analysis passes
- PassContext: Shared analysis state
- Pass: Individual analysis algorithms

Passes
------
1. CallGraph: Builds function call graph
2. TaintPropagation: Tracks tainted data flow
3. FFIBoundary: Identifies cross-language boundaries
4. SinkTracer: Reconstructs vulnerability paths

Limitations
-----------
- No pointer/alias analysis
- Taint is coarse-grained (function-level)
- FFI boundary detection is heuristic-based
- Not a replacement for Clang Static Analyzer

What OmniScope Does Uniquely
----------------------------
→ Tracks data flow across Rust ↔ C boundaries
→ Detects vulnerabilities invisible to single-language analyzers
```

### 4.2 Code Documentation

Per `zig_coding_guide.md` Section IX: All public API must have English documentation.

**Required Comments:**
```zig
/// Detect FFI boundaries in the call graph.
///
/// An FFI boundary is detected when:
/// - Callee is external_unknown (not libc)
/// - Caller and callee are in different modules
///
/// Parameters:
///   - graph: Call graph to analyze
///
/// Returns:
///   - ArrayList of FFI edges found
pub fn detectFFIBoundaries(graph: *CallGraph) ![]const FFIEdge { ... }
```

---

## Phase 5: Code Quality (Priority: MEDIUM)

### 5.1 File Line Count Compliance

Per `zig_coding_guide.md`: Files must not exceed 1000 lines.

**Current Files Needing Review:**
- `src/pass/analysis/call_graph.zig` - ~400 lines (OK)
- `src/pass/analysis/sink_tracer.zig` - ~200 lines (OK)
- `src/pass/analysis/ffi_boundary.zig` - ~100 lines (OK)
- `src/pass/analysis/taint_propagation.zig` - ~150 lines (OK)

### 5.2 Naming Convention Compliance

| Element | Convention | Current | Status |
|---------|-----------|---------|--------|
| Structs | PascalCase | `CallGraphPass` | ✅ |
| Functions | camelCase | `detectFFIBoundaries` | ✅ |
| Constants | SCREAMING_SNAKE | `MAX_ITERATIONS` | ✅ |
| Fields | camelCase | `isTainted` | ✅ |

### 5.3 Format and Check

Per `zig_coding_guide.md`:
```bash
# Before any commit/change
zig fmt src/
zig build 2>&1 | grep -E "error:"

# Run tests
zig build test
```

---

## Priority Order

```
P0 (Critical):
├── 1.1 Output format upgrade (security reports)
├── 1.2 Rust + C FFI demo
└── 2.x Pass stabilization tests

P1 (Important):
├── 3.x Test quality improvements
└── 4.1 README.md documentation

P2 (Nice to Have):
├── 4.2 Code documentation comments
├── 5.x Code quality compliance
└── 5.1 File line count check
```

---

## Anti-Patterns to Avoid

Per `zig_coding_guide.md` Section XII:

❌ **Do NOT add:**
- Pointer analysis
- DSL for query language
- More language support
- More Pass types
- "Completeness" features

❌ **Do NOT in Pass code:**
- Cache computed values in IR layer
- Direct Pass-to-Pass communication
- Uncontrolled runtime instrumentation
- Expose internal APIs to plugins

✅ **DO:**
- Write detection-focused tests
- Improve output clarity
- Stabilize existing passes
- Document limitations

---

## Success Criteria

The project is "complete" when:

1. ✅ Killer demo shows Rust safety bypass via C FFI
2. ✅ Output is structured security report format
3. ✅ All 4 passes have passing unit tests
4. ✅ Integration tests verify real IR analysis
5. ✅ README clearly explains value proposition
6. ✅ Limitations are honestly documented

---

## References

- `plan/improve.md` - Project strategy
- `plan/zig_coding_guide.md` - Coding standards
- `plan/dev_cross_lang_flow.md` - Technical design