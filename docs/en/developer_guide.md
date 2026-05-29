# Developer Guide

> "Read the code. No, seriously, read the code."

Last updated: 2026-05-29 | Version: v0.2.0

## Architecture Overview

OmniScope is built around a **pass-based analysis pipeline**. Think of it as a conveyor belt: LLVM IR goes in one end, issues come out the other.

For the full architecture document, see [architecture.md](../architecture.md).

### Tier 1 / Tier 2

- **Tier 1** (pass-through): Pure C/C++ internal operations. We trust the compiler here. These passes build data structures but don't report issues.
- **Tier 2** (graph-driven): FFI/unsafe boundary analysis. This is where the magic happens. All issue reporting goes through `isOnDangerPath()`.

### Core Data Structures

| Structure | Produced By | Consumed By |
|-----------|-------------|-------------|
| `CrossLangEdge` | call-graph | ptr-lifetime, ffi-boundary, callback-escape, danger-surface |
| `MemoryGraph` | ptr-lifetime | danger-surface, free-validation |
| `DangerSurface` markers | danger-surface | ptr-lifetime, callback-escape, free-validation, memory-safety, taint-propagation |

## Adding a New Pass

1. Create `src/pass/analysis/your_pass.zig`
2. Define `pub const deps: []const []const u8` — list the passes your pass depends on
3. Implement `pub fn run(ctx: *PassContext) !void`
4. Register in `src/main.zig` in the pass registration block
5. Add tests in `src/pass/analysis/your_pass.zig` (we like tests)

### Pass Template

```zig
const std = @import("std");
const PassContext = @import("../pass.zig").PassContext;

pub const name = "your-pass";
pub const deps = &[_][]const u8{ "call-graph" }; // declare your dependencies!

pub fn run(ctx: *PassContext) !void {
    // Access shared data:
    // ctx.cross_edges — cross-language call edges
    // ctx.memory_graph — pointer tracking graph
    // ctx.danger_surface_relevant_functions — functions on danger paths
    // ctx.danger_surface_relevant_allocs — allocations on danger paths

    // Report issues:
    // ctx.reportIssue(.{ .kind = .your_issue_kind, ... });
}
```

## Coding Standards

These are non-negotiable:

1. **Declare your deps**: Every pass MUST declare `pub const deps`. Empty deps means "I don't need anything" — if you do need something, say so.
2. **Use `isOnDangerPath`**: All Tier 2 issue reporting MUST go through this gate. No exceptions.
3. **No silent failures**: If something goes wrong, log it. We have a diagnostics system. Use it.
4. **Test your code**: We're at 92% coverage. Let's keep it that way.
5. **One source of truth**: If a function/classification exists in one place, import it. Don't copy-paste. We've been burned by this.

## Project Structure

```
src/
├── common/          # Shared utilities
├── ir/              # LLVM IR wrapper types
├── dataflow/        # Data flow analysis framework
├── semantics/       # Semantic knowledge (allocators, noise filter, memory graph)
├── pass/
│   ├── pass.zig     # PassContext, issue reporting, zone classification
│   ├── pipeline.zig # Pass execution engine
│   ├── analysis/    # Analysis passes (13 total)
│   └── issue/       # Issue validation passes
├── registry/        # Hook registry (into_raw/from_raw pairing)
├── pipeline/        # Pipeline orchestration
├── diag/            # Diagnostics and logging
├── ffi/             # FFI type system
├── lifetime/        # Lifetime tracking
├── output/          # Output formatting (JSON, text)
├── perf/            # Performance profiling
├── fact/            # Fact storage
├── report/          # Report generation
└── visual/          # Visualization helpers
```

## Testing

```bash
# Run all tests
zig build test

# Run specific test
zig build test --filter "ptr_lifetime"

# Run with verbose output
zig build test --filter "noise_reduction" -fsummary
```

## Known Issues

See [architecture.md](../architecture.md#known-issues) for the current list of known bugs and their status.

## Contributing

1. Fork the repo
2. Create a feature branch
3. Write code + tests
4. `zig build test` must pass
5. Submit PR

We review every PR. We're friendly. We might be sarcastic, but we're friendly.
