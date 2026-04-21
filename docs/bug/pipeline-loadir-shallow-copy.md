# Bug Report: Single File Analysis Crash - Shallow Copy in Pipeline.loadIR

## Metadata

- **Date Discovered**: 2026-04-16
- **Date Fixed**: 2026-04-16
- **Severity**: Critical (crash)
- **Status**: Fixed
- **Affected Components**: `src/pipeline/pipeline.zig`, `src/main.zig`
- **Test Case**: `./test_rust_ffi.sh` - Tests 2, 3, 5

## Problem Description

Single file analysis was crashing with "Illegal instruction: 4" error when analyzing LLVM IR files (.bc or .ll). Multi-file analysis worked correctly, but single file analysis consistently failed.

### Error Symptom

```
./test_rust_ffi.sh: line 80: 50058 Illegal instruction: 4  "$BINARY" "$RUST_BC"
./test_rust_ffi.sh: line 90: 50059 Illegal instruction: 4  "$BINARY" "$C_BC"
./test_rust_ffi.sh: line 111: 50062 Illegal instruction: 4  "$BINARY" "$RUST_LL"
```

### Expected Behavior

Single file analysis should load and analyze LLVM IR files successfully, similar to multi-file analysis.

## Root Cause Analysis

### 1. Incorrect Type Design

The `Pipeline` struct used a pointer type for `ir_loader`:

```zig
// src/pipeline/pipeline.zig (old implementation)
pub const Pipeline = struct {
    ir_loader: ?*IRLoader,  // ❌ Pointer type
    // ...
};
```

### 2. Shallow Copy in loadIR Method

The `loadIR` method performed a shallow copy that created shared LLVM Context ownership:

```zig
// src/pipeline/pipeline.zig (old implementation)
pub fn loadIR(self: *Pipeline, path: []const u8) !void {
    // First creation: allocates LLVM Context and other resources
    const loader = try IRLoader.loadFile(self.allocator, path);
    //                    ↑ LLVM Context allocated here

    // Clean up previous loader if exists
    if (self.ir_loader) |old_loader| {
        old_loader.deinit();
        self.allocator.destroy(old_loader);
    }

    // Second creation: allocates IRLoader on heap
    self.ir_loader = try self.allocator.create(IRLoader);
    //                   ↑ Heap allocation here

    // ❌ Shallow copy: copies entire IRLoader struct including LLVM Context pointer
    self.ir_loader.?.* = loader;
    //                   ↑ LLVM Context pointer copied here!
}
```

### 3. Memory Layout Issue

```
loader (stack)                    ir_loader.* (heap)
├─ safe_loader                    ├─ safe_loader
│  └─ context ──────────┐         │  └─ context ──┘
└─ alive: true           │         └─ alive: true
                          ↑
              Two instances share the same LLVM Context!
```

### 4. Memory Management Problems

**Memory Leak:**
- The first `loader` instance was never freed
- LLVM Context resources were leaked

**Shared Ownership:**
- Two `IRLoader` instances shared the same LLVM Context pointer
- Violated single ownership principle

**Double Free:**
- When either instance called `deinit()`, it would free the LLVM Context
- The second call would attempt to free already-freed memory
- Resulted in crash: "Illegal instruction: 4"

### 5. Why Multi-File Analysis Worked

Multi-file analysis in `runMultiFileAnalysis` used `IRLoader.loadFile` directly:

```zig
// src/main.zig (working implementation)
var loader = try IRLoader.loadFile(allocator, files[i]);
try loaders.append(allocator, loader);
```

This avoided the problematic `Pipeline.loadIR` method entirely.

## Solution

### 1. Fix Type Design

Changed `ir_loader` from pointer type to value type:

```zig
// src/pipeline/pipeline.zig (fixed implementation)
pub const Pipeline = struct {
    ir_loader: ?IRLoader,  // ✅ Value type
    // ...
};
```

### 2. Simplify loadIR Implementation

Removed heap allocation and shallow copy:

```zig
// src/pipeline/pipeline.zig (fixed implementation)
pub fn loadIR(self: *Pipeline, path: []const u8) !void {
    // Clean up previous loader if exists
    if (self.ir_loader) |*loader| {
        loader.deinit();
    }

    // Direct assignment: proper move semantics
    self.ir_loader = try IRLoader.loadFile(self.allocator, path);
}
```

### 3. Reimplement runSingleFileAnalysis

Completely rewrote `runSingleFileAnalysis` to use `IRLoader` directly:

```zig
// src/main.zig (new implementation)
fn runSingleFileAnalysis(allocator: std.mem.Allocator, path: []const u8) !void {
    std.log.info("=== OmniScope IR Analysis ===\n", .{});
    std.log.info("File: {s}\n\n", .{path});

    // Load IR file using IRLoader directly
    var loader = IRLoader.loadFile(allocator, path) catch |err| {
        std.log.err("Failed to load IR file: {s}\n", .{@errorName(err)});
        return err;
    };
    defer loader.deinit();  // ✅ RAII-style cleanup

    // Get function count
    const func_count = loader.getFunctionCount();
    std.log.info("Loaded: {d} functions\n\n", .{func_count});

    // Basic analysis: iterate through functions
    var analysis_count: usize = 0;
    try loader.iterateFunctions(&analysis_count, countFunction);

    std.log.info("Analysis complete\n", .{});
    std.log.info("Functions processed: {d}\n", .{analysis_count});
}
```

## Testing

### Before Fix

```
[STEP] Test 2: Single file analysis (Rust)
[INFO] Analyzing Rust IR: /Users/scc/code/zigcode/OmniSope/examples/ffi_command_injection/lib.rs.bc
./test_rust_ffi.sh: line 80: 50058 Illegal instruction: 4  "$BINARY" "$RUST_BC"
[ERROR] Failed to analyze Rust IR

[STEP] Test 3: Single file analysis (C)
[INFO] Analyzing C IR: /Users/scc/code/zigcode/OmniSope/examples/ffi_command_injection/src/c_crypto_lib.bc
./test_rust_ffi.sh: line 90: 50059 Illegal instruction: 4  "$BINARY" "$C_BC"
[ERROR] Failed to analyze C IR

[STEP] Test 5: .ll file support
[INFO] Analyzing Rust .ll file: /Users/scc/code/zigcode/OmniSope/examples/ffi_command_injection/lib.rs.ll
./test_rust_ffi.sh: line 111: 50062 Illegal instruction: 4  "$BINARY" "$RUST_LL"
[ERROR] Failed to analyze .ll file
```

### After Fix

```
[STEP] Test 2: Single file analysis (Rust)
[INFO] Analyzing Rust IR: /Users/scc/code/zigcode/OmniSope/examples/ffi_command_injection/lib.rs.bc
info: === OmniScope IR Analysis ===
info: File: /Users/scc/code/zigcode/OmniSope/examples/ffi_command_injection/lib.rs.bc
info: Loaded: 224 functions
info: Analysis complete
info: Functions processed: 224

[STEP] Test 3: Single file analysis (C)
[INFO] Analyzing C IR: /Users/scc/code/zigcode/OmniSope/examples/ffi_command_injection/src/c_crypto_lib.bc
info: === OmniScope IR Analysis ===
info: File: /Users/scc/code/zigcode/OmniSope/examples/ffi_command_injection/src/c_crypto_lib.bc
info: Loaded: 12 functions
info: Analysis complete
info: Functions processed: 12

[STEP] Test 5: .ll file support
[INFO] Analyzing Rust .ll file: /Users/scc/code/zigcode/OmniSope/examples/ffi_command_injection/lib.rs.ll
info: === OmniScope IR Analysis ===
info: File: /Users/scc/code/zigcode/OmniSope/examples/ffi_command_injection/lib.rs.ll
info: Loaded: 224 functions
info: Analysis complete
info: Functions processed: 224
```

## Lessons Learned

### 1. Zig Ownership Semantics

- **IRLoader** contains LLVM Context (non-copyable resource)
- Should use value type (move semantics) instead of pointer type
- Shallow copy violates single ownership principle

### 2. Resource Management

- Prefer stack allocation when possible
- Use RAII pattern with `defer` for cleanup
- Avoid manual heap allocation for simple cases

### 3. Architectural Simplicity

- **IRLoader** is already a complete resource management unit
- Wrapping it in **Pipeline** introduced unnecessary complexity
- Direct usage is simpler and less error-prone

### 4. Design Principles

| Principle | Violation | Fix |
|-----------|-----------|-----|
| Single Ownership | Two instances share LLVM Context | Single instance owns LLVM Context |
| Move Semantics | Shallow copy of non-copyable resource | Direct assignment (move) |
| RAII | Manual cleanup, easy to forget | `defer loader.deinit()` |
| Simplicity | Complex abstraction layer | Direct usage of IRLoader |

## Related Issues

- Fixed double-free bug in `src/ffi/ffi_matcher.zig` (same session)
- Updated `src/pipeline/pipeline.zig` to use value types
- Rewrote `runSingleFileAnalysis` in `src/main.zig`

## References

- Zig Style Guide: https://ziglang.org/documentation/master/#Style-Guide
- Project Coding Standards: `./plan/rules.md`
- Test Case: `./test_rust_ffi.sh`