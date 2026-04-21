# OmniScope Killer Demo - Cross-Language Security Vulnerabilities

This demo showcases security vulnerabilities that **only appear when analyzing Rust + C code together**.

## The Problem

**Rust developers think their code is safe:**
- Input is "sanitized" (semicolons removed)
- Memory is managed correctly
- No unsafe operations in safe Rust code

**But C code has vulnerabilities:**
- `system()` with user input (command injection)
- `strcpy()` without bounds checking (buffer overflow)
- `malloc()` without null checks

**The gap:** Rust's "sanitization" is ineffective, and C assumes input is already validated.

## Vulnerabilities Demonstrated

### 1. Command Injection (CRITICAL)

```rust
// Rust: "Sanitizes" input by removing semicolons
let sanitized: String = input.chars().filter(|&c| c != ';').collect();
dangerous_process(c_str.as_ptr());  // Calls C function
```

```c
// C: Executes shell command with "sanitized" input
void dangerous_process(const char* input) {
    system(command);  // VULNERABLE!
}
```

**Attack vector:** `ls && rm -rf /` bypasses semicolon filter

### 2. Buffer Overflow (HIGH)

```rust
// Rust: Allocates 64-byte buffer
let mut buffer = [0u8; 64];
dangerous_copy(buffer.as_mut_ptr(), c_str.as_ptr());
```

```c
// C: Uses strcpy without bounds checking
void dangerous_copy(char* dest, const char* src) {
    strcpy(dest, src);  // VULNERABLE!
}
```

**Attack vector:** Input > 64 bytes overflows buffer

### 3. Missing Null Check (MEDIUM)

```c
char* dangerous_alloc(size_t size) {
    char* buffer = malloc(size);
    buffer[0] = '\0';  // CRASH if malloc fails!
    return buffer;
}
```

## Building the Demo

### Prerequisites

- Rust toolchain: `rustup default stable`
- LLVM: `brew install llvm` (macOS) or `apt install llvm` (Linux)
- OmniScope: Built from source

### Build Steps

```bash
# 1. Build the Rust + C project
cd examples/rust_ffi_demo
cargo build

# 2. Generate LLVM IR for Rust code
cargo rustc -- --emit=llvm-ir -o target/rust.ll

# 3. Generate LLVM IR for C code
clang -S -emit-llvm -O0 c_lib/dangerous.c -o target/dangerous.ll

# 4. Link IR files (optional, for combined analysis)
llvm-link target/rust.ll target/dangerous.ll -o target/combined.bc

# 5. Run OmniScope analysis
cd ../..
./zig-out/bin/OmniScope examples/rust_ffi_demo/target/combined.bc
```

### Quick Build (Makefile)

```bash
make demo
```

## Expected OmniScope Output

```
=== OmniScope Security Analysis Report ===
Timestamp: 2026-04-16 10:30:00
Module: combined.bc

------------------------------------------------------------------------
[CRITICAL] Command Injection via FFI
------------------------------------------------------------------------
Vulnerability ID:   OMI-001
Severity:           CRITICAL
Confidence:         0.92

Flow Path:
  [Source] stdin() [Rust]
    └─> process_input() [Rust]
         └─> [FFI Boundary: Rust → C]
              └─> dangerous_process() [C]
                   └─> system() [C] - command execution

Cross-Language: YES (Rust → C)
CWE: CWE-78

------------------------------------------------------------------------
[HIGH] Buffer Overflow via FFI
------------------------------------------------------------------------
Vulnerability ID:   OMI-002
Severity:           HIGH
Confidence:         0.85

Flow Path:
  [Source] stdin() [Rust]
    └─> copy_data() [Rust]
         └─> [FFI Boundary: Rust → C]
              └─> dangerous_copy() [C]
                   └─> strcpy() [C] - unbounded copy

Cross-Language: YES (Rust → C)
CWE: CWE-120

------------------------------------------------------------------------
SUMMARY
------------------------------------------------------------------------
Total Functions Analyzed:    15
Total FFI Boundaries:        3
Vulnerabilities Found:       2
  - Critical:                1
  - High:                    1
  - Medium:                  0
  - Low:                     0

Analysis Time:               0.15s
```

## Why This Matters

**Existing tools miss this:**
- **Clang Static Analyzer**: Only sees C code, assumes Rust input is safe
- **Rust Clippy**: Only sees Rust code, doesn't know C has vulnerabilities
- **CodeQL**: Requires separate queries for each language

**OmniScope's advantage:**
- **Cross-language data flow**: Tracks Rust → C → vulnerability
- **FFI boundary awareness**: Knows where languages meet
- **Unified analysis**: Sees the complete picture

## Running the Demo Interactively

```bash
cd examples/rust_ffi_demo
cargo run

# Try these inputs:
# > ls
# > ls && pwd
# > ls || cat /etc/passwd
# > AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
```

## Key Takeaway

**Security is a property of the whole system, not individual components.**

Rust's memory safety doesn't protect against C vulnerabilities. OmniScope bridges this gap by analyzing cross-language boundaries.

## Files

```
examples/rust_ffi_demo/
├── Cargo.toml              # Rust package config
├── build.rs                # Build script (compiles C)
├── Makefile                # Build automation
├── README.md               # This file
├── src/
│   ├── lib.rs              # Rust library with FFI
│   └── main.rs             # Interactive demo
└── c_lib/
    ├── dangerous.h         # C header with vulnerabilities
    └── dangerous.c         # C implementation
```

## License

MIT License - For educational purposes only. DO NOT use this code in production!
