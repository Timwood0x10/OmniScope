# OmniScope User Guide

This guide provides comprehensive instructions for installing, configuring, and using OmniScope for LLVM IR analysis.

## Table of Contents

1. [Installation](#installation)
2. [Quick Start](#quick-start)
3. [Configuration](#configuration)
4. [Command Line Usage](#command-line-usage)
5. [Library Usage](#library-usage)
6. [Common Workflows](#common-workflows)
7. [Troubleshooting](#troubleshooting)
8. [Examples](#examples)

---

## Installation

### Prerequisites

Before installing OmniScope, ensure you have the following prerequisites:

- **Zig** version 0.15.2 or later
  - Download from [ziglang.org](https://ziglang.org/download/)
  - Verify installation: `zig version`

- **LLVM** development libraries
  - Version 22.x recommended
  - On macOS with Homebrew: `brew install llvm@22`
  - On Ubuntu/Debian: `sudo apt-get install llvm-22-dev`
  - On Fedora: `sudo dnf install llvm22-devel`

### Building from Source

1. Clone the repository:
```bash
git clone <repository-url>
cd OmniSope
```

2. Configure build options:
```bash
# Default build
zig build

# With custom LLVM path
zig build -Dllvm-path=/path/to/llvm

# With optimizations
zig build -Doptimize=ReleaseFast

# With LTO enabled
zig build -Denable-lto=true
```

3. Build the project:
```bash
make build
```

4. Install (optional):
```bash
zig build install
```

### Verifying Installation

Run the verification test to ensure everything is working:
```bash
zig build verify-ir
```

---

## Quick Start

### Your First Analysis

Create a simple C program and compile it to LLVM IR:

```c
// hello.c
#include <stdio.h>

int main() {
    printf("Hello, World!\n");
    return 0;
}
```

Compile to bitcode:
```bash
clang -c -emit-llvm hello.c -o hello.bc
```

Analyze with OmniScope:
```bash
./zig-out/bin/OmniSope hello.bc
```

Expected output:
```
=== OmniScope Cross-Language Data Flow Analysis ===

[*] Loading IR: hello.bc
[*] IR loaded: 1 functions

[*] Registering analysis passes...
[*] Running analysis...

=== Analysis Results ===
No issues found.
```

### Understanding the Output

OmniScope provides several types of output:

- **INFO**: Informational messages about the analysis process
- **WARN**: Potential issues that should be reviewed
- **ERROR**: Definite problems detected

The output includes:
- Number of functions analyzed
- Passes executed
- Issues found (if any)

---

## Configuration

### Build Configuration

Configure OmniScope at build time using options:

```bash
# Specify LLVM installation path
zig build -Dllvm-path=/opt/homebrew/Cellar/llvm/22.1.3

# Enable Link Time Optimization
zig build -Denable-lto=true

# Set optimization level
zig build -Doptimize=Debug
zig build -Doptimize=ReleaseSafe
zig build -Doptimize=ReleaseFast
zig build -Doptimize=ReleaseSmall

# Target specific platform
zig build -Dtarget=x86_64-linux-gnu
zig build -Dtarget=aarch64-macos
```

### Runtime Configuration

OmniScope can be configured at runtime through command-line arguments:

```bash
# Enable verbose logging
./zig-out/bin/OmniSope -v input.bc

# Enable debug logging
./zig-out/bin/OmniSope -d input.bc

# Show help
./zig-out/bin/OmniSope --help

# Show version
./zig-out/bin/OmniSope --version
```

---

## Command Line Usage

### Basic Syntax

```bash
OmniSope [options] <input-file>
```

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-v, --verbose` | Enable verbose logging |
| `-d, --debug` | Enable debug logging |
| `--version` | Show version information |

### Examples

**Basic analysis:**
```bash
./zig-out/bin/OmniSope program.bc
```

**Verbose output:**
```bash
./zig-out/bin/OmniSope -v program.bc
```

**Debug mode:**
```bash
./zig-out/bin/OmniSope -d program.bc
```

---

## Library Usage

### Initializing OmniScope

```zig
const std = @import("std");
const OmniScope = @import("OmniScope");

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize fact store
    var store = OmniScope.fact.FactStore.init(allocator);
    defer store.deinit();

    // Initialize query engine
    var engine = OmniScope.fact.QueryEngine.init(&store);
}
```

### Loading LLVM IR

```zig
const engine = @import("OmniScope").engine;

// Load a bitcode file
var loader = try engine.IRLoader.loadFile(allocator, "input.bc");
defer loader.deinit();

// Check if module is loaded
if (loader.hasModule()) {
    std.debug.print("Module loaded successfully\n", .{});
}

// Get function count
const func_count = loader.getFunctionCount();
std.debug.print("Found {} functions\n", .{func_count});
```

### Working with Passes

```zig
const pass = @import("OmniScope").pass;

// Create pass context
var ctx = pass.PassContext.init(
    allocator,
    loader.getModule(),
    &store,
    &engine,
);

// Create diagnostic writer
var diag = pass.DiagnosticWriter{ .allocator = allocator };

// Run a pass
var result = OmniScope.cross_lang.CallGraphPass.run(&ctx, &diag) catch |err| {
    std.debug.print("Pass failed: {}\n", .{err});
    return err;
};
```

### Querying Facts

```zig
const fact = @import("OmniScope").fact;

// Query by fact kind
const cfg_edges = try engine.queryByKind(.cfg_edge, allocator);
defer allocator.free(cfg_edges);

// Query by subject
const related_facts = try engine.queryBySubject(123, allocator);
defer allocator.free(related_facts);

// Query by object
const aliases = try engine.queryByObject(456, allocator);
defer allocator.free(aliases);
```

---

## Common Workflows

### Workflow 1: Cross-Language Data Flow Analysis

Detect data flow from sources to sinks across FFI boundaries:

```bash
# Analyze a program with FFI calls
./zig-out/bin/OmniSope cross_lang_program.bc

# Expected output shows:
# - Function classifications (internal, libc, external_unknown)
# - FFI boundary crossings
# - Tainted data flow paths
# - Sink calls that receive tainted data
```

### Workflow 2: Memory Safety Analysis

Check for memory safety issues:

```zig
// Custom pass for memory safety
const MemorySafetyPass = struct {
    pub const name = "memory-safety";
    pub const kind = pass.PassKind.analysis;
    pub const deps = &[_][]const u8{"cfg", "alias"};

    pub fn run(ctx: *pass.PassContext, diag: *pass.DiagnosticWriter) !void {
        // Check for use-after-free
        // Check for double-free
        // Check for memory leaks
    }
};
```

### Workflow 3: Concurrency Analysis

Detect potential race conditions and deadlocks:

```zig
const ConcurrencyPass = struct {
    pub const name = "concurrency";
    pub const kind = pass.PassKind.analysis;
    pub const deps = &[_][]const u8{"cfg", "lock"};

    pub fn run(ctx: *pass.PassContext, diag: *pass.DiagnosticWriter) !void {
        // Analyze lock usage
        // Detect potential deadlocks
        // Check for data races
    }
};
```

### Workflow 4: Security Vulnerability Detection

Find security vulnerabilities:

```bash
# Analyze for common vulnerabilities
./zig-out/bin/OmniSope -v security_critical.bc

# Look for:
# - Buffer overflows
# - Integer overflows
# - Format string vulnerabilities
# - Use of dangerous functions
```

---

## Troubleshooting

### Common Issues

#### Issue: LLVM Library Not Found

**Error:**
```
error: Unable to find LLVM library
```

**Solution:**
```bash
# Specify LLVM path explicitly
zig build -Dllvm-path=/path/to/llvm

# Or set environment variable
export LLVM_DIR=/path/to/llvm
```

#### Issue: Undefined LLVM Symbols

**Error:**
```
Undefined symbols: "_LLVMContextCreate", ...
```

**Solution:**
```bash
# Ensure LLVM libraries are linked correctly
# Check library path
ls $LLVM_DIR/lib/libLLVM-22.dylib

# Rebuild with correct path
zig build -Dllvm-path=$LLVM_DIR
```

#### Issue: Memory Leak Detected

**Error:**
```
Warning: Memory leak detected!
```

**Solution:**
```zig
// Update main.zig to check for memory leaks
defer {
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        std.debug.print("Warning: Memory leak detected!\n", .{});
    }
};
```

#### Issue: Pass Execution Fails

**Error:**
```
Pass failed: InvalidIR
```

**Solution:**
```bash
# Verify the input file is valid LLVM IR
llvm-dis input.bc -o input.ll
# Check input.ll for errors

# Re-compile with correct flags
clang -c -emit-llvm -O0 -g input.c -o input.bc
```

### Debug Mode

Enable debug logging for detailed information:

```bash
./zig-out/bin/OmniSope -d input.bc 2> debug.log
```

### Getting Help

If you encounter issues not covered here:

1. Check the [GitHub Issues](https://github.com/your-repo/issues)
2. Review the [Architecture Documentation](../plan/improve.md)
3. Consult the [Developer Guide](developer_guide.md)

---

## Examples

### Example 1: Simple C Program Analysis

```c
// simple.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    char* buffer = malloc(100);
    if (buffer) {
        strcpy(buffer, "Hello");
        printf("%s\n", buffer);
        free(buffer);
    }
    return 0;
}
```

Compile and analyze:
```bash
clang -c -emit-llvm simple.c -o simple.bc
./zig-out/bin/OmniSope simple.bc
```

### Example 2: Cross-Language Program

```c
// cross_lang.c
#include <stdio.h>
#include <stdlib.h>

// External function (Rust/Go/etc.)
extern void external_process(char* data);

int main() {
    char* input = malloc(256);
    if (!input) return 1;

    read(0, input, 256);
    external_process(input);

    free(input);
    return 0;
}
```

Compile and analyze:
```bash
clang -c -emit-llvm cross_lang.c -o cross_lang.bc
./zig-out/bin/OmniSope -v cross_lang.bc
```

### Example 3: Custom Pass in Zig

```zig
// my_custom_pass.zig
const std = @import("std");
const Pass = @import("OmniScope").pass.Pass;
const PassContext = @import("OmniScope").pass.PassContext;
const DiagnosticWriter = @import("OmniScope").pass.DiagnosticWriter;

pub const MyCustomPass = struct {
    pub const name = "my-custom-pass";
    pub const kind = Pass.PassKind.analysis;
    pub const deps = &[_][]const u8{"cfg"};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        diag.info("Starting custom analysis", .{});

        if (!ctx.hasModule()) {
            diag.err("No module loaded", .{});
            return error.NoModule;
        }

        // Custom analysis logic here
        const next_id = ctx.getNextId();
        diag.info("Allocated ID: {}", .{next_id});

        diag.info("Custom analysis complete", .{});
    }
};

const ValidatedPass = Pass(MyCustomPass);
```

---

## Advanced Topics

### Performance Optimization

For large projects:

```bash
# Enable LTO for better performance
zig build -Denable-lto=true -Doptimize=ReleaseFast

# Use release mode for production analysis
./zig-out/bin/OmniSope large_project.bc
```

### Batch Processing

Analyze multiple files:

```bash
#!/bin/bash
for file in *.bc; do
    echo "Analyzing $file..."
    ./zig-out/bin/OmniSope "$file" > "results/${file%.bc}.txt" 2>&1
done
```

### Integration with CI/CD

GitHub Actions example:

```yaml
name: OmniScope Analysis

on: [push, pull_request]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install Zig
        uses: goto-bus-stop/setup-zig@v1
      - name: Install LLVM
        run: sudo apt-get install llvm-22-dev
      - name: Build OmniScope
        run: make build
      - name: Run Analysis
        run: make test
```

---

## Additional Resources

- [Architecture Documentation](../plan/improve.md)
- [Developer Guide](developer_guide.md)
- [API Reference](api_reference.md)
- [Bug Report](../plan/bugs_report.md)
- [Coding Guidelines](../plan/zig_coding_guide.md)

---

## Support

For questions, issues, or contributions:

- GitHub Issues: [repository-url]/issues
- Discussions: [repository-url]/discussions
- Documentation: [repository-url]/wiki

---

**Last Updated**: 2026-04-14  
**Version**: 1.0.0