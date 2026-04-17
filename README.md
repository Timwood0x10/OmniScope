# OmniScope

**Cross-Language Static Security Analyzer**

OmniScope is an LLVM IR-based static analysis tool focused on detecting security vulnerabilities across FFI boundaries.

## Key Features

- **Cross-Language Data Flow Analysis**: Track data flow across Rust ↔ C, Zig ↔ C, and other FFI boundaries
- **Security Vulnerability Detection**: Command injection, buffer overflow, memory leaks, double free, and more
- **Traceable Output**: Every vulnerability comes with a complete reasoning path
- **Modular Pass Architecture**: Easy to extend with new detection rules

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
├── pass/
│   ├── analysis/
│   │   ├── issue/           # Vulnerability detection passes
│   │   │   ├── malloc_check.zig
│   │   │   ├── free_validation.zig
│   │   │   ├── memory_safety.zig
│   │   │   ├── ffi_unsafe.zig
│   │   │   └── integer_overflow.zig
│   │   └── ffi_semantics.zig
│   └── manager.zig
├── dataflow/
│   └── graph.zig            # Data flow graph
├── ffi/
│   └── ffi_matcher.zig      # FFI boundary matching
├── diag/
│   └── issue.zig            # Issue definitions
└── pipeline/
    └── pipeline.zig         # Analysis pipeline
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

- Requires compiled LLVM IR (no direct source code analysis)
- Limited inter-procedural analysis (primarily intra-procedural)
- Requires debug information for better location reporting

## Contributing

Contributions are welcome! Please ensure:

1. Follow the coding conventions in `plan/rules.md`
2. Add tests
3. Run `zig build test` to ensure all tests pass

## License

MIT License
