# OmniScope Examples

This directory contains examples demonstrating OmniScope's cross-language data flow analysis capabilities, organized into production-grade demos and functional tests.

## Directory Structure

```
examples/
├── demos/                    # Production-grade cross-language vulnerability demos
│   ├── crypto_key_manager/   # Rust+C cryptography library (buffer overflow, command injection)
│   └── web_command_injection/ # Go+C HTTP server (network parser vulnerabilities)
├── tests/                    # Functional test cases
│   ├── basic_patterns/       # Basic vulnerability patterns (buffer overflow, use-after-free)
│   └── edge_cases/           # Complex scenarios (logic bugs, crypto bugs)
└── README.md
```

## Quick Start

```bash
# Build OmniScope
cd /path/to/OmniScope
zig build

# Run demos (requires compiler for each language)
./zig-out/bin/OmniScope examples/demos/crypto_key_manager/combined.bc
./zig-out/bin/OmniScope examples/demos/web_command_injection/combined.bc

# Run tests
./zig-out/bin/OmniScope examples/tests/basic_patterns/cffi_test.bc
./zig-out/bin/OmniScope examples/tests/edge_cases/logic_bugs.bc
```

## Production Demos

### crypto_key_manager - Rust+C Cryptography

**Scenario**: A key management service that uses Rust for memory safety, but delegates cryptographic operations to a legacy C library via FFI. The C library has critical vulnerabilities.

**Vulnerabilities**:
- Buffer overflow in `set_global_key()` (C layer)
- Command injection in `execute_crypto_command()` (C layer)
- Weak key derivation (C layer ignores Rust parameters)

**Build**:
```bash
cd examples/demos/crypto_key_manager
gcc -c -emit-llvm -O0 -g c_vulnerable_layer.c -o c_vulnerable_layer.bc
rustc --crate-type=lib --emit=llvm-bc -O0 rust_safe_layer.rs -o rust_safe_layer.bc
llvm-link rust_safe_layer.bc c_vulnerable_layer.bc -o combined.bc
./zig-out/bin/OmniScope combined.bc
```

**Expected Output**: OmniScope detects taint propagation from Rust input validation through FFI boundary to C vulnerabilities.

### web_command_injection - Go+C HTTP Server

**Scenario**: A production web service built with Go that uses a high-performance C protocol parser via CGO. The Go layer validates input, but the C parser has vulnerabilities.

**Vulnerabilities**:
- Buffer overflow in `parse_http_request()` (C layer)
- Command injection in `execute_parsed_command()` (C layer)
- Buffer overflow in `parse_dns_query()` (C layer)

**Build**:
```bash
cd examples/demos/web_command_injection
gcc -c -emit-llvm -O0 -g c_parser.c -o c_parser.bc
gollvm -S -emit-llvm -O0 go_http_server.go -o go_http_server.ll
llvm-as go_http_server.ll -o go_http_server.bc
llvm-link go_http_server.bc c_parser.bc -o combined.bc
./zig-out/bin/OmniScope combined.bc
```

**Expected Output**: OmniScope detects network taint propagation from Go input validation through CGO boundary to C vulnerabilities.

## Functional Tests

### basic_patterns/

Test cases for fundamental vulnerability patterns:

- **cffi_test.c** - Cross-language FFI test (source → propagation → sink)
- **sample_analysis.c** - Memory safety issues (buffer overflow, memory leak, use-after-free)
- **sample_rust.rs** - Rust-specific patterns for analysis
- **sample_zig.zig** - Zig IR generation and analysis
- **sample_go.go** - Go IR analysis (requires Gollvm)
- **sample_wasm.c** - WebAssembly target
- **ntt.c** - Number theoretic transform patterns

### edge_cases/

Complex scenarios and logic bugs:

- **logic_bugs.c** - Various logic bug patterns:
  - NTT butterfly operation bug (wrong mathematical operation)
  - Integer overflow in coefficient multiplication
  - Conditional logic bug (wrong comparison operator)
  - Off-by-one errors in loop termination
  - Weak PRNG seed (predictable instead of secure)

## Building Examples

### C Examples

```bash
gcc -c -emit-llvm -O0 -g <source.c> -o <output.bc>
```

### Rust Examples

```bash
rustc --crate-type=lib --emit=llvm-bc -O0 <source.rs> -o <output.bc>
```

### Go Examples

```bash
# Using gollvm
gollvm -S -emit-llvm -O0 <source.go> -o <output.ll>
llvm-as <output.ll> -o <output.bc>
```

### Zig Examples

```bash
zig build-obj --emit=llvm-ir -O0 <source.zig> -o <output.ll>
llvm-as <output.ll> -o <output.bc>
```

## Running OmniScope

### Basic Usage

```bash
./zig-out/bin/OmniScope <path-to-bitcode-file>
```

### Expected Output Format

```
=== OmniScope Cross-Language Data Flow Analysis ===

[*] Loading IR: <file.bc>
[*] IR loaded: <n> functions

[*] Registering analysis passes...
[*] Running analysis...

[ERROR] VULNERABILITY OMI-001
[ERROR] Severity: <critical|medium|low>
[ERROR] Path:
[ERROR]   [Sink] <function>()
[ERROR]     └─> <intermediate functions>
[ERROR]   [Source] <function>() - initial taint source
[ERROR] Impact: <vulnerability description>

=== Analysis Results ===
<n> issues found.
```

## Key Concepts Demonstrated

### 1. Cross-Language Taint Propagation

OmniScope tracks data flow across language boundaries:
- **Rust → C**: Via FFI bindings
- **Go → C**: Via CGO
- **Zig → C**: Via @cImport

### 2. FFI Boundary Detection

OmniScope identifies where control crosses language boundaries:
```
[INFO] FFI Boundary detected: Rust → C
[INFO] Taint propagates across language boundary
```

### 3. Vulnerability Patterns

- **Buffer Overflow**: Unsafe string operations in C
- **Command Injection**: Unsanitized input in system() calls
- **Memory Safety**: Use-after-free, double-free, leaks
- **Logic Bugs**: Wrong comparisons, off-by-one errors

## Real-World Parallels

These demos mirror actual production systems:

| Demo | Real-World Systems |
|------|-------------------|
| crypto_key_manager | OpenSSL wrappers in Rust/Go, Cloudflare TLS |
| web_command_injection | Nginx/Apache parsers, CDN packet processing |
| basic_patterns | Legacy codebases, embedded systems |
| edge_cases | Mathematical libraries, crypto implementations |

## Best Practices for Analysis

1. **Always analyze the combined IR**: Link all language components together
2. **Enable debug symbols**: Use `-g` flag during compilation
3. **Optimization level**: Use `-O0` for analysis to preserve code structure
4. **Check FFI boundaries**: Pay special attention to cross-language calls
5. **Validate findings**: Cross-reference OmniScope output with code review

## Troubleshooting

### "IR loaded: 0 functions"
- Ensure the bitcode file is valid: `llvm-dis <file.bc>`
- Check that symbols are exported: `nm <file.bc>`

### "No issues found" (but vulnerabilities exist)
- Verify optimization level is `-O0`
- Check that FFI functions are visible in IR
- Ensure source functions have proper LLVM metadata

### FFI Boundary Not Detected
- Verify FFI functions are not inlined
- Check that extern "C" / CGO directives are present
- Ensure function signatures match across languages

## Contributing

When adding new examples:

1. Place production demos in `demos/`
2. Place test cases in `tests/basic_patterns/` or `tests/edge_cases/`
3. Include a README explaining the vulnerability
4. Provide build instructions for all languages
5. Document expected OmniScope output
6. Test on multiple LLVM IR versions

## References

- [FFI Best Practices](https://doc.rust-lang.org/nomicon/ffi.html)
- [CGO Documentation](https://pkg.go.dev/cmd/cgo)
- [LLVM IR Reference](https://llvm.org/docs/LangRef.html)
- [CWE Top 25](https://cwe.mitre.org/top25/)