# Cross-Language Data Flow Analysis - Development Plan (v4)

## Overview

This document defines the implementation plan for cross-language data flow analysis in OmniScope. The feature tracks how data flows across FFI (Foreign Function Interface) boundaries, detecting security issues like command injection.

## Goals

1. Track taint propagation across function and language boundaries (forward direction)
2. Detect Source → Sink paths involving multiple languages
3. Provide a minimal but functional demo showing cross-language issues

## Non-Goals (Explicitly Excluded)

- Pointer analysis
- Alias analysis
- Precise argument mapping (ArgMap)
- Borrow semantics tracking
- Automatic FFI inference
- DSL / query language
- Complete CodeQL replacement

## Architecture

### Core Components

```
IR Module
    │
    ├── CallGraph Pass (builds function call relationships)
    │
    ├── TaintPropagation Pass (forward taint propagation with taintedBy)
    │
    ├── FFIBoundary Pass (marks cross-language transitions)
    │
    └── SinkTracer Pass (follows taintedBy chain, no DFS)
```

## Key Corrections

### Critical Bug Fix: Taint Propagation Direction

**WRONG**:
```
callee tainted → caller tainted  // ❌ WRONG
```

**CORRECT**:
```
caller → callee (forward)
```

### taintedBy Limitation (Documented)

`taintedBy: ?u32` can only store ONE source.

**Decision**: Accept this limitation. Document as "non-exhaustive" for v1.

```
A → B
C → B

B can only record one taintedBy source in v1.
```

### CallGraph Needs Reverse Edges

For efficient taint propagation, we need both:
- `calls: []u32` - who this function calls
- `callers: []u32` - who calls this function

**Reason**: Without `callers`, taint propagation would be O(N²).

### Sink Detection: Fuzzy Matching

```zig
fn isSink(name: []const u8) bool {
    return contains(name, "system") or
           contains(name, "exec") or
           contains(name, "popen");
}
```

**Reason**: LLVM IR may mangle names: `system` → `@system` → `@__libc_system`

## Data Structures

### FunctionKind

```zig
pub const FunctionKind = enum {
    internal,
    libc,
    external_unknown,
};
```

**Classification Rules**:
- `name ∈ LIBC` → `libc`
- `is_declaration AND name ∉ LIBC` → `external_unknown`
- otherwise → `internal`

### FunctionNode

```zig
pub const FunctionNode = struct {
    id: u32,
    name: []const u8,
    kind: FunctionKind,
    calls: []u32,   // Functions this calls
    callers: []u32, // Functions that call this (for efficient propagation)
    isTainted: bool,
    taintedBy: ?u32, // First source of taint (non-exhaustive in v1)
};
```

### FlowPath

```zig
pub const FlowPath = struct {
    steps: []const FlowStep,
    isCrossLanguage: bool,
    risk: RiskLevel,
};
```

### FlowStep

```zig
pub const FlowStep = struct {
    funcName: []const u8,
};
```

### RiskLevel

```zig
pub const RiskLevel = enum {
    medium,
    critical,
};
```

**Classification**:
- `sink contains "system" OR "exec"` → `critical`
- otherwise → `medium`

## Implementation Phases

### Phase 1: Call Graph Construction

**Files**:
- `src/pass/analysis/call_graph.zig` (new)

**API**:

```zig
pub const CallGraphPass = struct {
    pub const name = "call-graph";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext) !void {
        // Iterate all functions in IR
        // For each call instruction, record the edge
        // Build both `calls` and `callers` arrays
        // Classify FunctionKind (internal/libc/external_unknown)
    }
};
```

**LibC Functions**:

```zig
pub const LIBC_FUNCTIONS = &[_][]const u8{
    "malloc", "free", "calloc", "realloc",
    "read", "write", "open", "close",
    "system", "exec", "popen",
    "strlen", "strcpy", "strncpy", "sprintf", "snprintf",
    "gets", "fgets", "scanf", "getenv", "getline",
};
```

**Debug Output**:
```
[CallGraph]
A → B
B → C
```

### Phase 2: Taint Propagation (Forward)

**Files**:
- `src/pass/analysis/taint_propagation.zig` (new)

**Algorithm**:

```zig
// Step 1: Mark initial sources
for each function F:
    for each call C in F:
        if isSource(C.callee.name):
            F.isTainted = true
            F.taintedBy = C.callee.id

// Step 2: Forward propagation (use callers for efficiency)
repeat until stable:
    for each function F where F.isTainted:
        for each caller C in F.callers:
            if !C.isTainted:
                C.isTainted = true
                C.taintedBy = F.id
```

**Source Functions**:

```zig
pub const SOURCE_FUNCTIONS = &[_][]const u8{
    "read", "recv", "gets", "scanf",
    "main",  // Entry point as source
};
```

**Debug Output**:
```
function dangerous is tainted by main
```

### Phase 3: FFI Boundary Detection

**Files**:
- `src/pass/analysis/ffi_boundary.zig` (new)

**API**:

```zig
pub const FFIBoundaryPass = struct {
    pub const name = "ffi-boundary";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{"taint-propagation"};

    pub fn run(ctx: *PassContext) !void {
        // Check each tainted function's calls
        // If callee.kind == external_unknown → FFI boundary
        // If callee.kind == libc → normal call (not FFI)
    }
};
```

**Acceptance Criteria**:
- Only `external_unknown` edges are marked as FFI
- `libc` calls are NOT marked as FFI

### Phase 4: Sink Tracing (No DFS, Follow Chain)

**Files**:
- `src/pass/analysis/sink_tracer.zig` (new)

**Algorithm** (O(n), no DFS):

```zig
fn tracePath(funcId: u32) FlowPath {
    var steps: []FlowStep = &.{};
    var current = funcId;

    while (current != null) {
        const node = nodes[current];
        steps.append(.{ .funcName = node.name });

        if (node.taintedBy) |src| {
            if (isFFIEdge(src, current)) {
                steps.append(.{ .funcName = "[FFI Boundary]" });
            }
        }

        current = node.taintedBy;
    }

    return reverse(steps);
}

fn isSink(name: []const u8) bool {
    return contains(name, "system") or
           contains(name, "exec") or
           contains(name, "popen");
}

fn isFFIEdge(callerId: u32, calleeId: u32) bool {
    const callee = nodes[calleeId];
    return callee.kind == .external_unknown;
}
```

**Sink Functions** (fuzzy matching):

```zig
// Use contains() for fuzzy matching
// "system", "__libc_system", etc. all match
```

**Output Format**:

```
[Flow #1] CRITICAL
Source: main()
  → dangerous()
  → [FFI Boundary]
  → system()

Risk: Command Injection
Cross-Language: YES
```

### Phase 5: Integration and Demo

**Demo Files**:
- `examples/cross_lang/c_lib.c`
- `examples/cross_lang/rust_wrapper/src/main.rs`
- `examples/cross_lang/build.sh`

**Demo Scenario**:

```c
// c_lib.c
void dangerous(char* cmd) {
    system(cmd);  // SINK
}
```

```rust
// rust_wrapper
extern "C" {
    fn dangerous(cmd: *const i8);
}

fn main() {  // SOURCE (entry point)
    let input = "ls";
    let c_str = std::ffi::CString::new(input).unwrap();
    unsafe {
        dangerous(c_str.as_ptr());  // Taint propagates
    }
}
```

**Expected Output**:

```
[Flow #1] CRITICAL
Source: main() [Rust]
  → dangerous() [FFI: external_unknown]
  → system() [C]

Risk: Command Injection
Cross-Language: YES
```

## File Structure

```
src/
    pass/
        analysis/
            call_graph.zig           (new, ~200 lines)
            taint_propagation.zig     (new, ~200 lines)
            ffi_boundary.zig          (new, ~150 lines)
            sink_tracer.zig           (new, ~200 lines)
            mod.zig                   (update exports)

tests/
    cross_lang_flow_test.zig   (new)
```

## Coding Standards Compliance

All code follows `plan/zig_coding_guide.md`:

| Rule | Compliance |
|------|------------|
| Single file < 1000 lines | Each module < 250 lines |
| camelCase for functions | `buildCallGraph()`, `propagateTaintForward()` |
| PascalCase for types | `CallGraph`, `FlowPath`, `FunctionKind` |
| SCREAMING_SNAKE for consts | `LIBC_FUNCTIONS`, `MAX_DEPTH` |
| English comments | All public API documented |
| Error sets per module | `CallGraphError`, `TaintError`, etc. |

## Testing Plan

### Unit Tests

| Module | Test Cases |
|--------|------------|
| call_graph.zig | Empty IR, single function, multiple calls, FunctionKind, callers array |
| taint_propagation.zig | No taint, source only, forward propagation via callers, depth limit |
| ffi_boundary.zig | No boundary, libc (NOT FFI), external_unknown (IS FFI) |
| sink_tracer.zig | No sink, fuzzy match, follow taintedBy chain, cross-lang path |

### Integration Test

```zig
test "Cross-Lang: Command Injection Detection" {
    // Load IR with Rust calling C system()
    // Run: call-graph → taint-propagation → ffi-boundary → sink-tracer
    // Verify flow path: main → dangerous → system
    // Verify risk is CRITICAL
    // Verify cross-language flag is set
}
```

## Acceptance Criteria

1. `zig build` compiles without errors
2. `make check` shows 0 errors
3. `zig build test` passes all tests
4. Demo shows: `main() → dangerous() → system()`
5. Output shows risk level (CRITICAL) and cross-language flag (YES)

## Timeline

| Phase | Description | Lines (est) |
|-------|-------------|-------------|
| 1 | Call Graph + callers array | ~200 |
| 2 | Taint Propagation (forward via callers) | ~200 |
| 3 | FFI Boundary (external_unknown only) | ~150 |
| 4 | Sink Tracer (follow chain, fuzzy match) | ~200 |
| 5 | Integration + Demo | ~100 |

**Total**: ~850 lines of new code

## Implementation Order (per improve.md)

```
Step 0: Debug output - verify IR parsing works
Step 1: CallGraph - output "func main calls dangerous"
Step 2: TaintPropagation - output "function dangerous is tainted by main"
Step 3: SinkTracer - output "main → dangerous → system"
Step 4: FFI Boundary - output with "Cross-Language: YES"
```

## Key Differences Summary

| Aspect | Decision |
|--------|----------|
| Taint Direction | caller → callee (forward) |
| taintedBy | Single source only (documented as non-exhaustive) |
| Reverse Edges | `callers: []u32` added for O(n) propagation |
| Sink Matching | Fuzzy matching via `contains()` |
| FFI Definition | only `external_unknown` |
| Source | read, recv, gets, scanf, **main** |

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| taintedBy limitation | Document as non-exhaustive, acceptable for v1 |
| O(N²) propagation | Added `callers` array for efficiency |
| Name mangling | Fuzzy matching for sinks |
| False negatives | Focus on high-risk paths (system/exec) first |
