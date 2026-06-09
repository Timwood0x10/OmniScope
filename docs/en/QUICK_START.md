# Quick Start

> Version: v0.2.0 | Zig: ≥ 0.15.2 | LLVM: 22

## Install

```bash
brew install zig llvm@22    # macOS
# apt install zig llvm-22   # Linux

git clone https://github.com/your-org/OmniScope.git
cd OmniScope
zig build -Doptimize=ReleaseFast
```

Verify:

```bash
./zig-out/bin/OmniScope --version
```

## First Analysis

```bash
# Single file, text output
./zig-out/bin/OmniScope your_file.ll

# JSON output
./zig-out/bin/OmniScope your_file.bc --json

# SARIF for GitHub Code Scanning
./zig-out/bin/OmniScope your_file.bc --sarif -o results.sarif

# Multiple modules
./zig-out/bin/OmniScope rust_side.bc c_side.bc --json
```

## Useful Filters

```bash
# Boundary issues only, high severity
./zig-out/bin/OmniScope input.bc --boundary-only --min-severity high --json

# Language override for ambiguous symbols
./zig-out/bin/OmniScope input.bc --lang-prefix sqlite3_=c --default-lang rust

# Suppress stdlib/compiler noise
./zig-out/bin/OmniScope input.bc --focus-user-code --json

# Export surface report
./zig-out/bin/OmniScope input.bc --report-surfaces --json
```

## Output Fields

| Field | Meaning |
|-------|---------|
| `kind` | Issue category (e.g. `memory_leak`, `cross_language_free`, `use_after_free`) |
| `severity` | `critical` / `high` / `medium` / `low` |
| `confidence` | `HIGH` / `MEDIUM` / `LOW` / `HEURISTIC` |
| `confidence_score` | 0.0–1.0 numeric value |
| `cwe_id` | CWE mapping |
| `location.function` | Function where evidence was found |
| `message` | Human-readable explanation |

## Reading Results

1. Start with severity and confidence — prioritize `critical`/`high` with `HIGH`/`MEDIUM` confidence.
2. Check whether the issue crosses an FFI boundary.
3. Verify the allocator/deallocator family matches.
4. Low-confidence findings need manual confirmation.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| ModuleParseFailed | IR file may be wrong LLVM version; try `llvm-as-22 input.ll -o input.bc` first |
| OOM on large files | Use ReleaseFast build (`-Doptimize=ReleaseFast`) |
| Too many findings | Use `--boundary-only --min-severity high` or `--focus-user-code` |

## Next Steps

- [Architecture Guide](./architecture.md) — how the pipeline works
- [Modules Guide](./modules.md) — module responsibilities
- [Passes Guide](./passes.md) — pass inventory and behavior
