# User Guide

> "Your code has bugs. We can help you find some of them."

Last updated: 2026-05-04 | Version: v0.1.6

## What OmniScope Does

OmniScope analyzes LLVM IR files to find **cross-language memory safety issues** at FFI boundaries. It detects:

- **Use-after-free**: Memory freed on one side, accessed on the other
- **Double-free**: Memory freed twice (often once per language)
- **Memory leaks**: Allocated but never freed across language boundaries
- **Pointer escape**: Pointers crossing FFI boundaries without proper ownership transfer
- **Type mismatches**: Wrong types passed across FFI calls

## Quick Start

### Prerequisites
- Zig 0.1.5.0+
- An LLVM IR file (`.ll`)

### Build

```bash
git clone https://github.com/your-org/omniscope.git
cd omniscope
zig build
```

### Run

```bash
# Basic analysis
./zig-out/bin/omniscope your_file.ll

# Verbose output
./zig-out/bin/omniscope --verbose your_file.ll

# JSON output (for CI integration)
./zig-out/bin/omniscope --format json your_file.ll > report.json
```

### Generate LLVM IR

You need LLVM IR files to analyze. Here's how to get them:

```bash
# From C/C++
clang -S -emit-llvm -o file.ll file.c

# From Rust
cargo rustc -- --emit=llvm-ir

# From Go (with TinyGo)
tinygo build -emit-llvm -o file.ll

# From Zig
zig build-obj --emit-llvm-ir file.zig
```

## Understanding the Output

### Text Output

```
[ISSUE] DOUBLE_FREE @ function "my_c_free" (line 42)
  Confidence: HIGH
  Pointer: %ptr (allocated at line 38 via malloc)
  First free: line 40 via rust_dealloc
  Second free: line 42 via free
  FFI Boundary: Rust → C
```

### JSON Output

```json
{
  "tool_version 0.1.6",
  "issues": [
    {
      "kind": "DOUBLE_FREE",
      "confidence": "HIGH",
      "function": "my_c_free",
      "line": 42,
      "details": {
        "pointer": "%ptr",
        "first_free": "rust_dealloc",
        "second_free": "free",
        "ffi_boundary": "Rust → C"
      }
    }
  ]
}
```

## Confidence Levels

| Level | Meaning |
|-------|---------|
| HIGH | Confirmed by graph analysis with complete data flow |
| MEDIUM | Strong evidence but incomplete alias tracking |
| HEURISTIC | Pattern-based detection, may have false positives |
| EXPERIMENTAL | New detection path, treat with caution |

## Tips

1. **Start with verbose mode**: `--verbose` shows why each issue was reported
2. **Filter by confidence**: In CI, you might want to only fail on HIGH confidence
3. **Check the FFI boundaries**: If OmniScope reports 0 FFI boundaries, your file might not have cross-language calls
4. **Combine with your language's tools**: OmniScope catches what Clippy/Clang SA miss at FFI boundaries. Use all of them.

## Limitations

- Only analyzes LLVM IR (not source code)
- Best results with FFI-heavy projects (Rust+C, Go+C, etc.)
- Pure Rust/Go/C++ projects with no FFI will show fewer issues (this is correct behavior)
- Size truncation, buffer overflow, and type confusion detection are planned but not yet implemented

## Getting Help

- [Architecture](../architecture.md) — How the analysis pipeline works
- [Developer Guide](developer_guide.md) — Contributing code
- [Investigation Reports](../investigation_reports/zh/README.md) — Real-world analysis examples
