# OmniScope Developer Guide

This guide is for developers who want to contribute to OmniScope, create custom passes, or extend the framework.

## Table of Contents

1. [Development Environment Setup](#development-environment-setup)
2. [Code Organization](#code-organization)
3. [Coding Standards](#coding-standards)
4. [Pass Development](#pass-development)
5. [Testing](#testing)
6. [Build System](#build-system)
7. [Debugging](#debugging)
8. [Contribution Guidelines](#contribution-guidelines)
9. [Performance Optimization](#performance-optimization)

---

## Development Environment Setup

### Prerequisites

- **Zig** 0.15.2 or later
- **LLVM** 22.x development libraries
- **Git** for version control
- **Make** for build automation

### IDE/Editor Configuration

#### VSCode

Install these extensions:
- `ziglang.vscode-zig` - Zig language support
- `llvm-vs-code-extensions.vscode-llvm` - LLVM support

**`.vscode/settings.json`**:
```json
{
    "zig.zigPath": "/path/to/zig",
    "zig.buildOnSave": false,
    "zig.formatOnSave": true,
    "zig.checkForUpdate": false
}
```

#### Vim/Neovim

Install the Zig plugin:
```vim
Plug: ziglang/zig.vim
```

Configuration:
```vim
autocmd FileType zig setlocal expandtab
autocmd FileType zig setlocal tabstop=4
autocmd FileType zig setlocal shiftwidth=4
```

### Development Workflow

```bash
# 1. Create a feature branch
git checkout -b feature/my-new-feature

# 2. Make your changes
vim src/pass/analysis/my_pass.zig

# 3. Format your code
make fmt

# 4. Check for errors
make check

# 5. Run tests
make test

# 6. Commit your changes
git add .
git commit -m "feat: add my new feature"

# 7. Push and create PR
git push origin feature/my-new-feature
```

---

## Code Organization

### Directory Structure

```
src/
├── main.zig                  # CLI entry point
├── root.zig                  # Library public API
├── ir/                       # LLVM IR wrappers
│   ├── llvm_raw.zig         # Raw LLVM C API bindings
│   ├── llvm_safe.zig        # Safe wrappers
│   ├── view.zig             # IR view utilities
│   ├── location.zig          # Source location tracking
│   └── debug_info.zig       # Debug information parsing
├── engine/                   # Core engine
│   └── loader.zig           # IR file loading
├── pass/                     # Analysis passes
│   ├── pass.zig             # PassContext + Pass interface
│   ├── manager.zig          # Pass manager
│   ├── foundation/          # Foundation passes
│   │   ├── cfg.zig         # Control flow graph
│   │   └── dfg.zig         # Data flow graph
│   ├── analysis/           # Analysis passes
│   │   ├── pointer_ownership.zig    # Core memory leak/UAF (936 lines)
│   │   ├── allocation_classifier.zig  # AllocType/FreeType (206 lines)
│   │   ├── cpp_fp_reduction.zig       # C++ 8-layer FP filter (937 lines)
│   │   ├── rust_ffi_auditor.zig       # Rust FFI auditor (464 lines) ← v0.1.5
│   │   ├── ffi_detector.zig          # FFI boundary detection
│   │   ├── ffi_analysis.zig          # FFI analysis
│   │   ├── ffi_boundary.zig          # FFI boundary analyzer
│   │   ├── ffi_info.zig              # FFI info registry
│   │   ├── ffi_semantics.zig         # FFI semantic registry
│   │   ├── call_graph.zig            # Call graph + tainted paths
│   │   ├── taint.zig                 # Taint analysis
│   │   ├── taint_propagation.zig     # Taint propagation
│   │   ├── taint_state.zig           # Taint state management
│   │   ├── lock.zig                  # Lock analysis (719 lines)
│   │   ├── alias.zig                 # Alias analysis
│   │   ├── steensgaard.zig           # Steensgaard pointer analysis
│   │   ├── vulnerability_rules.zig  # Vulnerability rule engine
│   │   ├── flow_path.zig             # Data flow path analysis
│   │   └── issue/                    # Issue-specific checkers
│   │       ├── ffi_unsafe.zig        # Unsafe FFI calls
│   │       ├── ffi_body_check.zig    # FFI function body checks
│   │       ├── malloc_check.zig      # malloc validation
│   │       ├── free_validation.zig   # free() validation
│   │       ├── memory_safety.zig     # Memory safety checks
│   │       ├── return_check.zig      # Return value checks
│   │       └── integer_overflow.zig  # Integer overflow
│   └── instrumentation/      # Instrumentation passes
│       └── planner.zig      # Instrumentation planner
├── fact/                     # Fact storage system (SoA layout)
│   ├── fact.zig            # Fact type definitions
│   ├── store.zig            # Fact store
│   ├── query.zig            # Query engine
│   └── ownership_fact.zig   # Ownership facts
├── dataflow/                 # Data flow analysis
│   ├── graph.zig            # DFG construction
│   ├── node.zig             # Data flow nodes
│   ├── edge.zig             # Data flow edges
│   ├── guard_propagation.zig # Guard propagation
│   ├── null_check_guard.zig # Null check analysis
│   ├── path_condition.zig   # Path conditions
│   ├── value_id_map.zig     # Value ID mapping
│   └── function_summary.zig # Function summaries
├── lifetime/                 # Lifetime & boundary analysis
│   ├── engine.zig          # Lifetime engine
│   ├── boundary.zig        # Cross-language boundary analyzer
│   ├── mapper.zig          # Lifetime mapper
│   └── root.zig            # Lifetime module root
├── registry/                 # Semantic registry
│   ├── semantic_registry.zig # Function semantic knowledge base
│   ├── config_loader.zig    # JSON config loader
│   └── sanitizer_registry.zig # Sanitizer registry
├── diag/                     # Diagnostics
│   ├── issue.zig            # Issue types + Confidence system
│   └── aggregator.zig       # Diagnostic aggregation
├── output/                   # Output adapters
│   ├── cli.zig             # CLI output
│   ├── formatter.zig        # Text formatter
│   ├── sarif.zig           # SARIF v2.1.0 output
│   └── lsp.zig             # LSP integration
├── report/                   # Report generation
│   ├── mod.zig             # Report generator
│   ├── sarif.zig           # SARIF report (v2.1.0)
│   └── ci_integration.zig  # CI/CD integration
├── pipeline/                 # Analysis pipeline
│   └── pipeline.zig        # Pipeline orchestration
├── tracking/                 # Memory tracking
│   ├── allocator.zig       # Allocation tracking
│   └── mod.zig             # Tracking module
└── perf/                     # Performance analysis
    ├── profiler.zig         # Profiler
    ├── memory_pool.zig     # Memory pool
    ├── analysis_context.zig # Analysis context
    └── bench_compare.zig    # Benchmark comparison
```

### Module Dependencies

```
main.zig
  └── root.zig
        ├─> ir/
        ├─> engine/
        ├─> pass/
        │     ├─> pass.zig (PassContext)
        │     ├─> analysis/ (pointer_ownership, cpp_fp_reduction, rust_ffi_auditor...)
        │     ├─> foundation/ (cfg, dfg)
        │     └─> manager.zig
        ├─> fact/
        ├─> dataflow/
        ├─> lifetime/
        ├─> registry/
        ├─> diag/ (issue.zig)
        ├─> output/
        ├─> report/
        ├─> pipeline/
        ├─> tracking/
        └─> perf/
```

---

## Coding Standards

### File Naming

- Use `snake_case` for all Zig files
- Keep file names descriptive and concise
- One public type per file when possible

Examples:
- `pass.zig` ✓
- `Pass.zig` ✗
- `fact_store.zig` ✓
- `FactStore.zig` ✗

### Code Style

#### Indentation and Formatting

- Use 4 spaces for indentation (no tabs)
- Maximum line length: 100 characters
- Use `zig fmt` to format code

```bash
# Format all Zig files
make fmt

# Format specific file
zig fmt src/pass/pass.zig
```

#### Naming Conventions

```zig
// Types: PascalCase
const FactStore = struct { ... };
const PassContext = struct { ... };

// Functions: camelCase
pub fn run(ctx: *PassContext) !void { ... }
pub fn insertFact(store: *FactStore, fact: Fact) !void { ... }

// Constants: UPPER_SNAKE_CASE
pub const MAX_FUNCTIONS: usize = 1_000_000;
pub const DEFAULT_TIMEOUT: u64 = 5000;

// Variables: camelCase
var next_id: u32 = 0;
const function_count = loader.getFunctionCount();

// Enums: PascalCase for type, lowercase for values
pub const PassKind = enum {
    foundation,
    analysis,
    plugin,
};

// Error sets: PascalCase
pub const LoaderError = error{
    FileNotFound,
    InvalidIR,
    OutOfMemory,
};
```

#### Comments

- Use `///` for documentation comments
- Use `//!` for module-level documentation
- Use `//` for inline comments
- All comments must be in English

```zig
//! This module provides the Pass interface with comptime validation
//!
//! The Pass system enables modular analysis with compile-time type checking.

/// Represents a single analysis pass
///
/// Passes are the primary unit of analysis in OmniScope.
/// Each pass implements the Pass interface and can declare dependencies.
pub const Pass = struct {
    /// Pass name for identification
    pub const name: []const u8 = "example";

    /// Pass kind classification
    pub const kind: PassKind = .analysis;

    /// Dependencies that must run before this pass
    pub const deps: []const []const u8 = &.{};

    /// Run the pass analysis
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        // Implementation
    }
};
```

#### Error Handling

- Use Zig's error union types (`!T`) for functions that can fail
- Provide descriptive error messages
- Handle errors appropriately

```zig
// Good
pub fn loadFile(allocator: Allocator, path: []const u8) LoaderError!IRLoader {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        log.err("Failed to open file: {} (path: {s})", .{err, path});
        return error.FileNotFound;
    };
    defer file.close();

    // ... rest of implementation
}

// Bad
pub fn loadFile(allocator: Allocator, path: []const u8) !IRLoader {
    // Vague error handling
    if (std.fs.cwd().openFile(path, .{})) |file| {
        defer file.close();
        // ...
    } else |_| {
        return error.Fail;
    }
}
```

#### Memory Management

- Always use explicit allocators
- Follow RAII pattern for resource management
- Clean up resources in `defer` statements

```zig
// Good
pub fn analyze(allocator: Allocator, input: []const u8) !void {
    var store = FactStore.init(allocator);
    defer store.deinit();

    var nodes = std.ArrayList(Node).init(allocator);
    defer nodes.deinit();

    try store.insert(.cfg_edge, 1, 2, 0);
}

// Bad
pub fn analyze(allocator: Allocator, input: []const u8) !void {
    var store = FactStore.init(allocator);
    // Missing defer store.deinit() - memory leak!

    var nodes = std.ArrayList(Node).init(allocator);
    // Missing defer nodes.deinit() - memory leak!
}
```

### Testing Standards

- Write tests for all public functions
- Use descriptive test names
- Test edge cases and error conditions
- Maintain test coverage above 80%

```zig
test "PassContext - getNextId generates unique IDs" {
    var fact_store = FactStore.init(std.testing.allocator);
    defer fact_store.deinit();

    var query_engine = QueryEngine.init(&fact_store);
    var ctx = PassContext.init(
        std.testing.allocator,
        null,
        &fact_store,
        &query_engine,
    );

    const id1 = ctx.getNextId();
    const id2 = ctx.getNextId();
    const id3 = ctx.getNextId();

    try std.testing.expectEqual(@as(u32, 1), id1);
    try std.testing.expectEqual(@as(u32, 2), id2);
    try std.testing.expectEqual(@as(u32, 3), id3);
}

test "PassContext - getNextId handles overflow" {
    // Test edge case
}
```

---

## Pass Development

### Pass Interface

Every pass must implement the following interface:

```zig
pub const MyPass = struct {
    /// Pass name (must be unique)
    pub const name: []const u8 = "my-pass";

    /// Pass kind
    pub const kind: PassKind = PassKind.analysis;

    /// Dependencies (must run before this pass)
    pub const deps: []const []const u8 = &.{ "cfg", "dfg" };

    /// Run the pass
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        // Pass implementation
    }
};

// Validate the pass at compile time
const ValidatedPass = Pass(MyPass);
```

### Pass Kinds

```zig
pub const PassKind = enum {
    foundation,  // Basic analysis passes (CFG, DFG)
    analysis,    // Advanced analysis passes (alias, lock, taint)
    plugin,      // User-defined plugin passes
};
```

### Pass Context

The `PassContext` provides access to analysis resources:

```zig
pub const PassContext = struct {
    allocator: Allocator,              // Memory allocator
    module: ?ModuleRef,                // LLVM module (if loaded)
    fact_store: *FactStore,            // Fact storage
    query_engine: *QueryEngine,        // Query engine
    next_id: std.atomic.Value(u32),    // ID allocator

    // Get a unique ID (thread-safe)
    pub fn getNextId(self: *PassContext) u32 {
        return self.next_id.fetchAdd(1, .seq_cst);
    }

    // Set the IR module
    pub fn setModule(self: *PassContext, module: ModuleRef) void {
        self.module = module;
    }

    // Check if module is loaded
    pub fn hasModule(self: *PassContext) bool {
        return self.module != null;
    }
};
```

### Creating a Foundation Pass

```zig
pub const CFGPass = struct {
    pub const name = "cfg";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        const module = ctx.module orelse return;

        // Iterate over functions
        var func = llvm.LLVMGetFirstFunction(module.raw);
        while (@intFromPtr(func) != 0) : (func = llvm.LLVMGetNextFunction(func)) {
            // Build CFG for each function
            try buildCFG(ctx, func);
        }
    }

    fn buildCFG(ctx: *PassContext, func: llvm.LLVMValueRef) !void {
        // Implementation
    }
};
```

### Creating an Analysis Pass

```zig
pub const AliasPass = struct {
    pub const name = "alias";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{ "cfg", "dfg" };

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        // Query CFG and DFG facts
        const cfg_edges = try ctx.query_engine.queryByKind(.cfg_edge, ctx.allocator);
        defer ctx.allocator.free(cfg_edges);

        // Perform alias analysis
        for (cfg_edges) |edge| {
            try analyzeAlias(ctx, edge);
        }
    }

    fn analyzeAlias(ctx: *PassContext, edge: Fact) !void {
        // Implementation
    }
};
```

### Creating a Plugin Pass

```zig
pub const CustomPluginPass = struct {
    pub const name = "custom-plugin";
    pub const kind = PassKind.plugin;
    pub const deps = &[_][]const u8{ "cfg" };

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        diag.info("Running custom plugin", .{});

        // Custom analysis logic
        const next_id = ctx.getNextId();
        try ctx.fact_store.insert(.custom_fact, next_id, 0, 0);

        diag.info("Plugin completed", .{});
    }
};
```

### Best Practices

1. **Declare Dependencies**: Always declare dependencies to ensure correct execution order
2. **Use Fact Store**: Pass data through the fact store, not directly
3. **Handle Errors**: Properly handle all error conditions
4. **Write Tests**: Create comprehensive tests for each pass
5. **Document**: Provide clear documentation for pass behavior

---

## Testing

### Test Organization

```
tests/
├── integration.zig           # Integration tests
├── e2e_ir_test.zig          # End-to-end IR tests
├── integration_ir_test.zig  # Integration IR tests
└── ir/                      # Test IR files
    ├── test_c_control_flow.c
    ├── test_c_pointers.c
    ├── test_c_threads.c
    ├── test_cpp_classes.cpp
    ├── test_cpp_virtual.cpp
    └── test_rust_patterns.rs
```

### Running Tests

```bash
# Run all tests
make test

# Run specific test file
zig test src/fact/store.zig

# Run integration tests
make integration-test

# Run end-to-end tests
make e2e-test

# Run tests with verbose output
zig test src/pass/pass.zig --summary all
```

### Writing Tests

```zig
test "FactStore - insert and query facts" {
    var store = FactStore.init(std.testing.allocator);
    defer store.deinit();

    // Insert facts
    try store.insert(.cfg_edge, 1, 2, 0);
    try store.insert(.cfg_edge, 2, 3, 1);

    // Query facts
    const facts = try store.queryByKind(.cfg_edge, std.testing.allocator);
    defer std.testing.allocator.free(facts);

    try std.testing.expectEqual(@as(usize, 2), facts.len);
    try std.testing.expectEqual(@as(u32, 1), facts[0].subject);
}

test "IRLoader - load invalid file" {
    const result = IRLoader.loadFile(std.testing.allocator, "nonexistent.bc");
    try std.testing.expectError(error.FileNotFound, result);
}
```

### Test Coverage

To check test coverage:

```bash
# Install kcov (Linux)
sudo apt-get install kcov

# Run tests with coverage
zig build test --enable-coverage

# Generate coverage report
kcov --include-pattern=src/ coverage/ zig-cache/test/...
```

---

## Build System

### Build Configuration

The `build.zig` file defines the build system:

```zig
pub fn build(b: *std.Build) void {
    // Parse options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_lto = b.option(bool, "enable-lto", "Enable LTO") orelse false;

    // Create library module
    const lib_mod = b.addModule("OmniScope", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // Build executable
    const exe = b.addExecutable(.{
        .name = "OmniSope",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "OmniScope", .module = lib_mod },
            },
        }),
    });

    // Add LLVM configuration
    exe.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });
    exe.linkSystemLibrary("LLVM-22");
    exe.addRPath(.{ .cwd_relative = b.pathJoin(&.{ llvm_path, "lib" }) });

    b.installArtifact(exe);
}
```

### Build Steps

```bash
# Available build steps
zig build --help

# Build executable
zig build

# Run tests
zig build test

# Run integration tests
zig build integration-test

# Run end-to-end tests
zig build e2e-test

# Build runtime library
zig build rt

# Verify IR loading
zig build verify-ir

# Run demo
zig build demo
```

### Makefile Targets

```bash
make build      # Build the project
make test       # Run all tests
make check      # Check for compilation errors
make fmt        # Format code
make clean      # Clean build artifacts
make demo       # Run demo
make integration-test  # Run integration tests
make e2e-test   # Run end-to-end tests
```

---

## Debugging

### Using Zig's Built-in Debugger

```bash
# Build with debug symbols
zig build -Doptimize=Debug

# Run with LLDB
lldb ./zig-out/bin/OmniSope
(lldb) b main
(lldb) run input.bc
(lldb) bt
```

### Debug Logging

Enable debug logging:

```bash
./zig-out/bin/OmniSope -d input.bc
```

Add custom debug messages:

```zig
const log = @import("log/log.zig");

pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
    log.debug("my-pass", "Starting analysis", .{});
    log.debug("my-pass", "Module loaded: {}", .{ctx.hasModule()});
    log.debug("my-pass", "Fact count: {}", .{ctx.fact_store.count()});
}
```

### Memory Debugging

Use Valgrind to detect memory leaks:

```bash
# Build with debug symbols
zig build -Doptimize=Debug

# Run with Valgrind
valgrind --leak-check=full ./zig-out/bin/OmniSope input.bc
```

### Common Debugging Techniques

#### Print Debugging

```zig
pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
    std.debug.print("Starting pass\n", .{});
    std.debug.print("Module: {?}\n", .{ctx.module});
    std.debug.print("Fact store size: {}\n", .{ctx.fact_store.count()});
}
```

#### Assertion Debugging

```zig
const assert = @import("log/debug.zig").assert;

pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
    assert(ctx.module != null, "Module must be loaded");
    assert(ctx.fact_store != null, "Fact store must be initialized");
}
```

---

## Contribution Guidelines

### Before Contributing

1. Read this developer guide
2. Review the coding standards
3. Understand the architecture
4. Check existing issues and PRs

### Making Changes

1. **Create a branch**:
```bash
git checkout -b feature/your-feature-name
```

2. **Make your changes**:
   - Follow coding standards
   - Write tests
   - Update documentation

3. **Format and check**:
```bash
make fmt
make check
```

4. **Run tests**:
```bash
make test
```

5. **Commit**:
```bash
git add .
git commit -m "type: description"
```

6. **Push and create PR**:
```bash
git push origin feature/your-feature-name
# Create PR on GitHub
```

### Commit Message Format

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Build process or auxiliary tool changes

Examples:
```
feat(pass): add call graph analysis pass

Implement CFG construction and function call tracking.
Add tests for basic and complex call graphs.

Closes #123
```

```
fix(loader): handle LLVM error messages properly

Fix memory leak where LLVM error messages were not freed
after file loading failures.

Fixes #456
```

### Pull Request Checklist

- [ ] Code follows coding standards
- [ ] Code is formatted (`make fmt`)
- [ ] All tests pass (`make test`)
- [ ] New tests added for new features
- [ ] Documentation updated
- [ ] Commit messages follow format
- [ ] PR description explains changes

---

## Performance Optimization

### Profiling

```bash
# Build with profiling support
zig build -Doptimize=ReleaseFast

# Run with profiler
./zig-out/bin/OmniSope input.bc

# Analyze results
# (platform-specific profiler tools)
```

### Optimization Techniques

#### Use SoA Layout

```zig
// Good - Structure of Arrays
pub const FactStore = struct {
    kinds: []FactKind,
    subjects: []u32,
    objects: []u32,
    contexts: []u32,
};

// Bad - Array of Structures (cache-unfriendly)
pub const FactStore = struct {
    facts: []Fact,  // Fact contains all fields
};
```

#### Minimize Allocations

```zig
// Good - Pre-allocate capacity
var nodes = std.ArrayList(Node).initCapacity(allocator, estimated_count) catch unreachable;

// Bad - Reallocate as needed
var nodes = std.ArrayList(Node).init(allocator);
```

#### Use Comptime

```zig
// Good - Comptime validation
const ValidatedPass = Pass(MyPass);

// Bad - Runtime validation (slower)
if (!isValidPass(MyPass)) {
    return error.InvalidPass;
}
```

### Memory Usage Optimization

```bash
# Monitor memory usage
/usr/bin/time -v ./zig-out/bin/OmniSope input.bc

# Profile with heaptrack (Linux)
heaptrack ./zig-out/bin/OmniSope input.bc
heaptrack_print heaptrack.out.*.gz
```

---

## Additional Resources

- [Zig Documentation](https://ziglang.org/documentation/master/)
- [LLVM Documentation](https://llvm.org/docs/)
- [Architecture Documentation](../plan/improve.md)
- [Bug Report](../plan/bugs_report.md)
- [Coding Guidelines](../plan/zig_coding_guide.md)

---

**Last Updated**: 2026-04-24  
**Version**: v0.1.5