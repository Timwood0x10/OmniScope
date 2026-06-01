# Developer Guide

> "Welcome to the codebase. Try not to break anything. (You will.)"
>
> **⚠️ Realistic Statement**: This document reflects the real state of v0.2.0, including known limitations and development guidelines.
>
> Version: v0.2.0 | Last updated: 2026-06-01 | Corresponding code: VERSION 0.2.0, LLVM 22

## Getting Started

### Prerequisites

| Tool | Minimum Version | Recommended Version | Notes |
|------|----------------|---------------------|-------|
| Zig | 0.13.x | 0.14.0-dev (latest) | Language runtime |
| Clang/LLVM | 18+ | 22 (current) | IR generation + C API |
| CMake | 3.20+ | Latest | Build system |
| Python | 3.10+ | 3.12 | Test scripts |
| Git | 2.30+ | Latest | Version control |

### First-Time Setup

```bash
git clone https://github.com/your-org/OmniScope.git
cd OmniScope

# Install dependencies
brew install zig llvm cmake python3  # macOS
# apt install zig llvm cmake python3 # Linux

# Build
zig build -Doptimize=ReleaseFast

# Run tests
zig build test
```

### Project Structure Overview

```
OmniScope/
├── src/
│   ├── main.zig              # Entry point
│   ├── config.zig            # Configuration management
│   ├── error.zig             # Error handling
│   ├── pass/
│   │   ├── foundation/       # CFG, DFG passes
│   │   └── analysis/         # All analysis passes
│   ├── pattern/              # SRT detectors (R-0~R-7)
│   ├── semantic/             # Semantic tree & registry
│   ├── gate/                 # Issue Gate logic
│   ├── confidence/           # Confidence Scorer
│   ├── output/               # Text/JSON/SARIF output
│   └── util/                 # Utilities
├── tests/
│   ├── unit/                 # Unit tests
│   ├── integration/          # Integration tests
│   ├── redteam/              # Red team test set
│   └── benchmarks/           # Performance tests
├── docs/
│   ├── en/                   # English documentation
│   └── zh/                   # Chinese documentation
└── build.zig                 # Build configuration
```

---

## Development Workflow

### Code Style Guidelines

**Zig code conventions**:

1. **Naming**:
   - Types: `PascalCase` (`MemoryGraph`, `CrossLangEdge`)
   - Functions: `camelCase` (`buildCallGraph`, `detectFFIBoundary`)
   - Constants: `UPPER_SNAKE_CASE` (`MAX_FUNCTIONS`, `DEFAULT_CONFIDENCE`)
   - Local variables: `camelCase` or short names (`ptr`, `fn_id`, `bb`)

2. **Error Handling**:
   ```zig
   // ✅ Good: Use error union
   const result = try someOperation();
   // or
   const result = someOperation() catch |err| {
       log.err("Operation failed: {}", .{err});
       return err;
   };

   // ❌ Bad: Ignore errors
   _ = someOperation();  // Silent failure!
   ```

3. **Memory Management**:
   ```zig
   // ✅ Good: Use allocator explicitly
   var map = std.AutoHashMap(u32, Value).init(allocator);
   defer map.deinit();

   // ❌ Bad: Use GPA without cleanup
   var gpa = std.heap.GeneralPurposeAllocator(.{}){};
   _ = gpa;  // Never check leaks!
   ```

4. **Testing**:
   ```zig
   test "description of what is being tested" {
       // Arrange
       const input = ...;

       // Act
       const result = functionUnderTest(input);

       // Assert
       try testing.expectEqual(expected, result);
       try testing.expect(result.isValid());
   }
   ```

### Testing Strategy

#### Test Suite Overview (16 Categories)

| Category | Location | Count | Purpose |
|----------|----------|-------|---------|
| **Unit Tests** | `tests/unit/` | ~340+ | Single function/module verification |
| **Integration Tests** | `tests/integration/` | ~50+ | End-to-end pipeline verification |
| **Red Team Tests** | `tests/redteam/` | ~40+ | Real-world FFI bug detection |
| **Performance Tests** | `tests/benchmarks/` | ~15+ | Performance regression prevention |
| **SRT Detector Tests** | `tests/unit/srt_*` | ~80+ | Individual detector accuracy |
| **Gate Logic Tests** | `tests/unit/gate_*.zig` | ~25+ | Issue Gate verdict correctness |
| **Confidence Tests** | `tests/unit/confidence*.zig` | ~18+ | Confidence score calculation |
| **Output Format Tests** | `tests/integration/output*` | ~12+ | JSON/SARIF format validation |
| **Multi-language Tests** | `tests/integration/lang_*` | ~35+ | Cross-language support verification |
| **Regression Tests** | `tests/regression/` | ~67+ | Prevent re-introduction of fixed bugs |
| **Fuzzing Tests** | `tests/fuzz/` | ~5+ | Crash/failure detection |
| **Edge Case Tests** | `tests/edge_cases/` | ~30+ | Boundary condition handling |
| **Large Project Tests** | `tests/large_projects/` | ~8+ | Scalability verification |
| **CI Pipeline Tests** | `.github/workflows/` | ~10+ | CI/CD integration |
| **Documentation Tests** | `tests/docs/` | ~5+ | Documentation consistency |
| **Type System Tests** | `tests/types/` | ~8+ | Type safety verification |

**Total**: ~750+ test cases (v0.2.0)

#### Test Coverage Status (Updated)

| Module | Coverage % | Notes |
|--------|-----------|-------|
| **Foundation Passes** | ~95% | cfg, dfg well-tested |
| **Tier 1 Passes** | ~90% | call-graph, pointer-flow, pointer-ownership, return-check |
| **Tier 2 Passes** | ~85% | ptr-lifetime, danger-surface, ffi-boundary, etc. |
| **SRT Detectors** | ~80% | R-0~R-7 individual coverage varies |
| **Issue Gate** | ~85% | 10 Verdict types all covered |
| **Confidence Scorer** | ~80% | 4-tier scoring covered |
| **Output Formats** | ~90% | Text, JSON, SARIF validated |
| **Multi-language Support** | ~60% | Go/Zig/Python/Java lower than C/C++/Rust |
| **Error Handling** | ~70% | Error paths need more coverage |
| **Performance-critical paths** | ~65% | Hot loops need profiling-guided tests |

**Overall estimated coverage**: ~82% (lines), ~78% (branches)

> **Note**: Coverage data based on `zig build test --coverage` output and manual estimation. May have ±5% margin of error.

### How to Add a New Detector

Adding a new SRT Pattern Detector requires the following steps:

#### Step 1: Create Detector File

Create a new file in `src/pattern/` directory:

```zig
// src/pattern/my_new_detector.zig
const std = @import("std");
const SemanticKind = @import("../semantic/semantic_kind.zig").SemanticKind;
const PatternDetector = @import("pattern_detector.zig").PatternDetector;

pub const MyNewDetector = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MyNewDetector {
        return .{ .allocator = allocator };
    }

    pub fn detect(
        self: *MyNewDetector,
        instruction: *const Instruction,
        context: *DetectContext,
    ) ?SemanticKind {
        // Your detection logic here
        // Return Some(SemanticKind) if pattern matches
        // Return None if no match
    }
};
```

#### Step 2: Register in PatternManager

Edit `src/pattern/pattern_manager.zig`, add to detector list:

```zig
pub const ALL_DETECTORS = &[_]type{
    ParamAttrDetector,      // R-0
    ProvenanceClassifier,   // R-1
    InteriorMutabilityDet,  // R-2
    RAIIReleaseDet,         // R-3
    SyscallClassifier,      // R-4
    LangDetector,           // R-5
    IntoRawTransfer,        // R-6
    LibraryRelease,         // R-7
    MyNewDetector,          // ← Add here
};
```

#### Step 3: Add Unit Tests

Create test file `tests/unit/srt_my_new_detector.zig`:

```zig
const std = @import("std");
const testing = std.testing;

test "MyNewDetector detects pattern X" {
    // Test case 1: Should detect
    // ...
}

test "MyNewDetector ignores non-matching patterns" {
    // Test case 2: Should not detect
    // ...
}
```

#### Step 4: Update Documentation

Update:
1. [docs/en/architecture.md](docs/en/architecture.md) - Add detector to table
2. [docs/en/modules.md](docs/en/modules.md) - Update module description
3. CHANGELOG.md - Record new feature

#### Step 5: Verify FP Suppression Effect

Run before/after comparison:

```bash
# Before adding detector
./OmniScope test_data/before.ll --json > before.json

# After adding detector
./OmniScope test_data/after.ll --json > after.json

# Compare issue counts
python scripts/compare_results.py before.json after.json
```

Expected results:
- **True Positives (TP)**: Should increase or stay same
- **False Positives (FP)**: Should decrease significantly (>50% reduction ideal)
- **TP Rate**: Should maintain ≥90%

### Debugging Tips

#### Common Issues & Solutions

| Problem | Possible Cause | Solution |
|---------|---------------|----------|
| **Analysis produces no issues** | Input file has no FFI boundaries; or Tier 2 suppressed by `isOnDangerPath()` | Check if file contains `extern "C"` / `#[no_mangle]`; view verbose logs |
| **Too many false positives** | Using `-O0` compilation; or language support is Experimental; or SRT not working | Switch to `-O1/-O2`; limit analysis scope; check SRT logs |
| **Crash during analysis** | LLVM IR version incompatible; or very large files (>100K functions) | Use LLVM 15+ for compilation; split modules; use ReleaseFast build |
| **Memory usage too high** | Debug mode enabled; or MemoryGraph too large for project size | Switch to ReleaseFast; increase swap space; limit analysis scope |
| **Test failures after update** | Breaking change in API; or test expectations outdated | Check CHANGELOG for breaking changes; update test expectations |

#### Useful Debug Commands

```bash
# Verbose output (show SRT decisions)
./OmniScope target.ll --verbose --log-level=debug

# Show only HIGH confidence issues
./Omniscope target.ll --min-confidence=high

# Output to file with full details
./OmniScope target.ll --json --sarif -o results/

# Profile performance
zig build -Doptimize=ReleaseFast && time ./OmniScope large_project.ll

# Run single test
zig test src/pass/analysis/ptr_lifetime.zig --test-filter "test_name"

# Run all SRT detector tests
zig build test --test-filter "srt_"

# Run red team tests only
zig build test --test-filter "redteam"
```

---

## Contribution Guidelines (Updated)

### Commit Message Format

Follow Conventional Commits:

```
<type>(<scope>): <subject>

<body>

<footer>
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code refactoring (no behavior change)
- `test`: Adding/updating tests
- `docs`: Documentation changes
- `perf`: Performance improvement
- `chore`: Maintenance tasks

Examples:
```
feat(srt): add R-8 ParamSource detector

Implement parameter source detection to distinguish function parameters
from local variables, reducing ~120 FP from borrow_escape.

Closes #123

fix(gate): correct Verdict.CONFLICTED priority

CONFLICTED was incorrectly treated as ALLOW, causing some legitimate
issues to be suppressed.

Fixes #124

perf(ptr-lifetime): optimize MemoryGraph construction

Use pre-allocated HashMap to reduce rehashing overhead.
Improves large-project performance by ~15%.
```

### Pull Request Process

1. Fork and create feature branch (`git checkout -b feat/new-detector`)
2. Write/update tests (ensure they pass)
3. Update documentation if needed
4. Submit PR with clear description
5. Address review comments
6. Maintain CI green status
7. Wait for maintainer approval and merge

### Code Review Checklist

When reviewing PRs, please verify:

- [ ] Code follows style guidelines
- [ ] New features have corresponding tests
- [ ] Documentation updated (code comments + docs)
- [ ] No regression in existing tests
- [ ] Performance impact assessed (for hot path changes)
- [ ] Error handling complete
- [ ] No new security vulnerabilities introduced
- [ ] CHANGELOG entry added (for user-visible changes)

---

## Architecture Decision Records (ADRs)

### ADR-001: Choose Zig as Implementation Language

**Status**: Accepted
**Date**: 2026-03-01
**Decision**: Use Zig as primary implementation language

Rationale:
1. Direct LLVM C API binding (Zig's `@cImport`)
2. Manual memory control (important for static analysis tools)
3. No hidden allocations (unlike Rust's implicit cloning)
4. Comptime metaprogramming (useful for code generation)

Trade-offs:
- Smaller ecosystem than Rust/Go
- Steeper learning curve for team members
- Fewer libraries available

### ADR-002: Three-Tier Pass Architecture

**Status**: Accepted
**Date**: 2026-03-15
**Decision**: Implement Foundation → Tier 1 → Tier 2 pass hierarchy

Rationale:
1. Clear separation of concerns
2. Enables parallel execution within tiers
3. Data flow explicit through shared structures

Alternatives considered:
- Monolithic single-pass (rejected: unmaintainable)
- Plugin architecture (rejected: over-engineering for current scope)

### ADR-003: SRT-Based False Positive Suppression

**Status**: Accepted
**Date**: 2026-05-20
**Decision**: Implement Semantic Resolution Tree for FP suppression

Rationale:
1. v0.1.x had unacceptably high FP rate (~1966/test suite)
2. Need semantic-level understanding beyond pattern matching
3. Tree structure allows compositional reasoning

Measured results (v0.2.0):
- FP reduced by **94%** (1966 → <110 on test suite)
- TP rate maintained at **≥90%**
- Analysis overhead increased **<5%**

---

## Known Limitations & Technical Debt

### Current Technical Debt

| Area | Description | Priority | Effort | Planned Fix |
|------|-------------|----------|--------|-------------|
| **Pass dependency bugs** | 3 incomplete dependency declarations (BUG-DEP-001~003) | P2 | Small | v0.2.1 |
| **Test coverage gaps** | Multi-language support ~60%, error handling ~70% | P1 | Medium | v0.3.0 |
| **Performance bottlenecks** | LLVM IR parsing 30-40% of total time | P2 | Large | v1.0+ |
| **Documentation inconsistencies** | Some code comments out-of-sync with docs | P3 | Small | Ongoing |
| **Windows support** | Basic tests only, limited platform coverage | P2 | Large | Community help needed |
| **Error messages quality** | Some errors lack actionable guidance | P2 | Medium | v0.2.1 |

### Known Bugs (Unfixed)

See [docs/en/architecture.md](architecture.md) section "🐛 Known Issues List" for complete list of 9 known bugs with Bug IDs and severity levels.

Key unfixed bugs:
- BUG-REG-001: Missing Rust GlobalAlloc entries (P1)
- BUG-FP-001~003: FP suppression edge cases (P2)
- BUG-MISC-001~003: Memory/performance/platform limitations (P2-P3)

### Areas Needing Improvement

1. **Inter-procedural analysis depth**
   - Current: Function summaries for alloc/free pairs
   - Needed: Full context-sensitive inter-procedural analysis
   - Impact: Would reduce false negatives in complex scenarios

2. **Indirect call resolution**
   - Current: Heuristic name matching + type analysis
   - Needed: Points-to analysis or VTA
   - Impact: Would improve virtual dispatch detection accuracy

3. **Language-specific optimizations**
   - Current: Generic detectors work across languages
   - Needed: Language-tuned detectors for idiomatic patterns
   - Impact: Would improve precision for each language

---

## Resources & References

### Internal Documentation

- [Architecture Document](architecture.md) - System architecture overview
- [Module Reference](modules.md) - Detailed module descriptions
- [Pass Reference](passes.md) - Pass-by-pass documentation
- [CHANGELOG](../../CHANGELOG.md) - Version history

### External Resources

- [LLVM Language Reference](https://llvm.org/docs/LangRef.html) - IR format specification
- [Zig Standard Library](https://ziglang.org/documentation/master/std/) - Zig APIs
- [CWE Mitre](https://cwe.mitre.org/) - Common weakness enumeration
- [SARIF Specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/) - Output format spec

### Community

- GitHub Discussions: [Link]
- Discord/Slack: [Link] (if applicable)
- Mailing list: [Link] (if applicable)

---

**Document maintenance info**:
- Last updated: 2026-06-01
- Maintainer: OmniScope core team
- Review cycle: Monthly or before each release
- Next planned update: After v0.2.1 release
