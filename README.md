# OmniScope

**LLVM IR Static Analysis Framework**

OmniScope is a static analysis tool for LLVM IR, focused on cross-language security vulnerability detection through FFI boundaries.

## Key Innovations

- **Fact Graph Architecture**: Structure-of-Arrays (SoA) fact storage enables efficient inter-pass communication
- **Cross-Language FFI Analysis**: Tracks data flow across Rust ↔ C, Zig ↔ C, and other FFI boundaries
- **Zero-Cost Abstractions**: Leverages Zig's comptime features to eliminate runtime overhead
- **Strict Communication Boundaries**: Passes communicate only through the fact store, ensuring isolation

## Quick Start

### Prerequisites

- Zig 0.15.2+
- LLVM 18+ (macOS: `brew install llvm`)

### Build

```bash
zig build
```

### Run Analysis

```bash
# Analyze a single LLVM IR file
./zig-out/bin/OmniSope target.bc

# Analyze multiple files (FFI mode)
./zig-out/bin/OmniSope rust.ll c.ll

# JSON output
./zig-out/bin/OmniSope --json target.bc
```

## Detected Vulnerabilities

| Vulnerability Type | Issue Kind | Severity |
|-------------------|------------|----------|
| Command Injection | `command_injection` | Critical |
| Buffer Overflow | `buffer_overflow` | High |
| Double Free | `double_free` | High |
| Unchecked Malloc | `malloc_unchecked` | High |
| Invalid Free | `invalid_free` | High |
| FFI Unsafe Call | `ffi_unsafe_call` | Medium |
| Integer Overflow | `integer_overflow` | Medium |
| Format String | `format_string` | Medium |

## Example: Killer Demo

```bash
cd examples/rust_ffi_demo
make ir        # Generate LLVM IR
make analyze   # Run OmniScope
```

### Sample Detection Results

```
[INFO] FreeValidation: Analyzed functions, found 3 invalid free calls
[INFO] MallocCheck: Analyzed functions, found 1 unchecked allocations
[INFO] FFIUnsafe: Analyzed 79 boundaries, found 7 issues
[INFO] IntegerOverflow: Analyzed functions, found 8 potential overflows

info: Issues detected: 20
```

## Architecture

```
src/
├── pass/                    # Pass system
│   ├── analysis/            # Analysis passes
│   └── manager.zig
├── dataflow/               # Data flow graph
├── ffi/                    # FFI boundary detection
├── fact/                   # Fact store (SoA layout)
├── diag/                   # Issue definitions
└── ir/                     # LLVM wrappers
```

## Pass Development Guide

### Creating a New Pass

1. Create a new file in `src/pass/analysis/issue/`
2. Implement the Pass interface:

```zig
pub const MyPass = struct {
    pub const name = "my-pass";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        // Analysis logic
        const issue = Issue.init(
            .unknown,
            try std.fmt.allocPrint(ctx.allocator, "Issue found", .{}),
            Location.init("func"),
            .medium,
            0.8,
        );
        try ctx.addIssue(issue);
    }
};
```

3. Register in `pass/manager.zig`

### Pass Dependencies

```zig
pub const deps = &[_][]const u8{ "ffi-boundary", "call-graph" };
```

## Output Formats

### Human-Readable

```
[WARN] Integer overflow detected in function: process_data
[WARN] Unchecked malloc result in function: dangerous_alloc
[INFO] Issues detected: 20
```

### JSON

```json
{
  "issue": "malloc_unchecked",
  "message": "malloc() result used without null check",
  "severity": "high",
  "confidence": 0.85,
  "location": "dangerous_alloc",
  "trace": [
    {
      "step": 1,
      "description": "Allocation function called without null check"
    },
    {
      "step": 2,
      "description": "Allocation via malloc() returns nullable pointer"
    }
  ]
}
```

## Limitations

- Requires compiled LLVM IR
- Primarily intra-procedural analysis
- Debug information improves location reporting

## Contributing

Contributions are welcome! Please ensure:

1. Follow the coding conventions in `plan/rules.md`
2. Add tests
3. Run `zig build test` to ensure all tests pass

## License

MIT License
