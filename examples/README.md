# OmniScope Examples

This directory contains example code demonstrating OmniScope's cross-language analysis capabilities.

## Quick Start

```bash
# Build OmniScope
cd /path/to/OmniScope
zig build

# Run examples
./scripts/run_examples.sh list     # List available examples
./scripts/run_examples.sh          # Run all examples
./scripts/run_examples.sh cffi_test  # Run specific example

# Run benchmarks
zig build bench    # Run all benchmarks
./scripts/run_benchmarks.sh        # Alternative: run benchmarks via script
```

## Script Usage

### run_examples.sh

Run analysis examples on sample code:

```bash
./scripts/run_examples.sh [example_name]

# Examples:
./scripts/run_examples.sh              # Run all examples
./scripts/run_examples.sh cffi_test   # C FFI test
./scripts/run_examples.sh logic_bugs   # Logic bug patterns
./scripts/run_examples.sh sample_rust  # Rust patterns (requires rustc)
./scripts/run_examples.sh sample_zig   # Zig patterns (requires zig)
./scripts/run_examples.sh list         # Show all available examples
```

### run_benchmarks.sh

Run performance benchmarks:

```bash
./scripts/run_benchmarks.sh [benchmark_name]

# Benchmarks:
./scripts/run_benchmarks.sh              # Run all benchmarks
./scripts/run_benchmarks.sh fact_store   # FactStore insert/query
./scripts/run_benchmarks.sh taint        # TaintContext operations
./scripts/run_benchmarks.sh ffi          # FFIBoundaryDetector
./scripts/run_benchmarks.sh flow_path     # FlowPath operations
./scripts/run_benchmarks.sh concurrent   # Concurrent FactStore
./scripts/run_benchmarks.sh call_graph   # Call graph building
./scripts/run_benchmarks.sh risk         # RiskLevel classification
./scripts/run_benchmarks.sh list         # Show all benchmarks
```

## Manual Analysis

### Compile and Analyze

```bash
# Analyze a C file
zig build
./zig-out/bin/OmniScope examples/cffi_test.c

# Analyze the Rust+C FFI demo
./zig-out/bin/OmniScope examples/ntt_ffi/combined.bc
```

## Examples

### ntt_ffi - Rust + C FFI Demo

This demonstrates Rust "safety" being bypassed via C FFI.

```
ntt_ffi/
├── src/
│   └── lib.rs           # Rust safe wrapper with sanitization
├── Cargo.toml           # Rust build config
└── c_lib/
    ├── dangerous.h      # C header
    └── dangerous.c      # Vulnerable C implementation
```

**Rust Code (looks safe):**
```rust
pub fn process_input(input: &str) -> Result<(), Error> {
    let sanitized = input.replace(";", "");
    let c_str = CString::new(sanitized).unwrap();
    unsafe { dangerous_process(c_str.as_ptr()); }
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
[ERROR] VULNERABILITY OMI-001
[ERROR] Severity: critical
[ERROR] Path:
  [Sink] dangerous_process()
    └─> system()
  [Source] process_input() - initial taint source
[ERROR] Impact: Arbitrary command execution possible
```

## Compilation Instructions

### Compile C library

```bash
cd examples/ntt_ffi/c_lib
gcc -c -emit-llvm -O0 dangerous.c -o dangerous.bc
ar rcs libdangerous.a dangerous.o
```

### Compile Rust (requires rustc with LLVM backend)

```bash
cd examples/ntt_ffi
rustc --crate-type=lib --emit=llvm-bc src/lib.rs -o lib.rs.bc
```

### Link both IR files

```bash
llvm-link lib.rs.bc dangerous.bc -o combined.bc
```

### Analyze with OmniScope

```bash
./zig-out/bin/OmniScope examples/ntt_ffi/combined.bc
```

## cffi_test.c - Cross-Language Test

Simple C example demonstrating source-to-sink data flow:

- **Source**: `get_input()` - reads from stdin
- **Propagation**: `process_data()`, `transform()`
- **Sink**: `execute_command()` - calls system()

```bash
# Compile
gcc -c -emit-llvm -O0 examples/cffi_test.c -o examples/cffi_test.bc

# Analyze
./zig-out/bin/OmniScope examples/cffi_test.bc
```

## Sample Files

- `sample_rust.rs` - Rust patterns for analysis
- `sample_zig.zig` - Zig IR generation
- `sample_go.go` - Go IR (requires Gollvm)
- `sample_wasm.c` - WebAssembly target
- `logic_bugs.c` - Various logic bug patterns