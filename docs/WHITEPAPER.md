# OmniScope: Finding the Bugs That Fall Between Languages

### A Technical Whitepaper for People Who Debug Cross-Language Crashes at 2 AM

**Version**: v0.1.6 | **Date**: 2026-05-04 | **Language**: Zig (LLVM 22)

---

## 1. The Problem (Why We Built This)

Picture this. It's 2 AM. You're on call. PagerDuty just woke you up for the third time this week. You pull up the crash log and stare at this:

```
double free detected in thread 0
  pointer 0x7f3a4c002010
  previously freed at: rust::ffi::Box::into_raw -> c_wrapper::process -> free
  second free at: rust::drop::Drop::drop -> Box::from_raw -> free
```

You ran this in staging a hundred times. Never reproduced. Day one in production? Boom.

The root cause is almost embarrassing in hindsight: Rust handed memory to C via `Box::into_raw()`, C called `free()` on it, but Rust's `Drop` trait didn't get the memo and called `free()` again. Two paths, one pointer, two frees. Classic.

Here's the thing -- **the compiler doesn't care.** Rust's compiler only sees Rust's ownership model. C's compiler only sees C's `malloc`/`free` pairing. Neither one can see across the language boundary. Every line of `unsafe` you write in Rust, the compiler waves through with a wink and a prayer.

This isn't a niche problem. If you're doing GPU compute, systems programming, crypto, WebAssembly runtimes, or basically anything that needs to talk to C from a safe language -- you live in this minefield. The bugs are all at the boundaries, and the boundaries are exactly where every tool goes blind.

### What existing tools get wrong

We tried. Oh, we tried.

| Tool | What we hoped for | What actually happened |
|------|------------------|----------------------|
| **CodeQL** | Multi-language analysis | Analyzes each language separately. Cross-language data flow? Nope. |
| **Clippy** | Lint Rust-side unsafe | Lints Rust. Inside `unsafe` blocks? Total blackout. |
| **Clang SA** | Check C-side memory safety | Checks C. Rust-side pointers crossing in? Invisible. |
| **Miri** | Detect UB at runtime | Great tool, but goes blind at `extern "C"`. No FFI support. |
| **Infer** | Inter-procedural analysis | Single-language only. Cross-boundary? Nope. |
| **CBMC** | Formal verification | C only. Bit-level, not IR-level. Takes minutes to hours. |
| **cargo-audit** | Dependency scanning | Checks crate metadata. Doesn't analyze your FFI code at all. |

The pattern is clear: **all these tools work within a single language's walls.** But the bugs we care about are the ones that escape those walls.

So we built OmniScope. The core idea is dead simple: **analyze at the LLVM IR layer, because no matter what language you write in, it all compiles to the same IR.** At that level, language boundaries don't exist.

---

## 2. Our Approach: Analyze Where Compilers Don't Look

### The key insight

Every language with an LLVM frontend -- C, C++, Rust, Zig, Go (via gccgo/clang) -- compiles down to the same intermediate representation. At the IR level, a Rust `Box::into_raw` and a C `malloc` are both just `call` instructions that return a pointer. The language-specific semantics are gone. The raw data flow is right there, naked and exposed.

This means we can do something no single-language tool can: **see both sides of every FFI boundary simultaneously.**

### Zone Classification: Don't analyze what the compiler already checked

Here's a design principle we arrived at the hard way: **analyzing everything is analyzing nothing.**

Our first prototype analyzed every function in every IR file. We ran it against wasmtime (~400K lines of IR) and got **4,023 issues.** We looked at the first fifty. All false positives. Rust compiler-generated `drop_in_place`, `panic_fmt`, `trait_dispatch` -- at the IR level, they look identical to real memory safety bugs.

A security tool that spits out 4,000 false positives has an effective true positive rate of 0%, because nobody will ever read the output.

So we invented **Zone Classification**. Every function gets classified into one of four zones:

| Zone | Meaning | What we do |
|------|---------|-----------|
| **Safe** | Pure safe Rust, no FFI contact | Skip entirely. Trust the borrow checker. |
| **Runtime Internal** | Language runtime / standard library | Skip. Trust the implementation. |
| **FFI** | Declared `extern "C"` or crosses language boundary | Deep analysis. This is the danger zone. |
| **Unknown** | Insufficient info to classify | Defer until more data arrives. |

The effect was dramatic. On wasmtime, we went from analyzing 987 functions to analyzing 159 -- an 84% reduction -- and from 4,023 noise items to real, actionable findings.

### Tier 1 / Tier 2 architecture

Zone Classification feeds into a two-tier analysis architecture:

**Tier 1 -- Pass-Through (no issues emitted):** These passes operate on pure C/C++ internal code. They build intermediate data structures (call graphs, pointer flow maps, alloc/free pairings) but never report issues. They're the quiet workers.

| Pass | What it builds |
|------|---------------|
| `call-graph` | Function call graph + `CrossLangEdge` entries for every FFI call site |
| `pointer-flow` | Pointer value flow across assignments, parameters, return values |
| `pointer-ownership` | `alloc_map` / `free_map` -- which pointer was allocated where and freed where |
| `return-check` | Ownership transfer validation (caller takes ownership on return) |

**Tier 2 -- Graph-Driven (issues gated by `isOnDangerPath`):** These passes perform the actual FFI and unsafe-boundary analysis. Every single issue they emit goes through one gate:

```zig
fn isOnDangerPath(fn_or_ptr: ID) bool {
    return dangerSurfaceMarkers.contains(fn_or_ptr);
}
```

If a function or pointer isn't on a danger path, the pass silently skips it. One gate. Zero exceptions.

| Pass | What it checks | Consumes |
|------|---------------|----------|
| `ffi-boundary` | FFI call boundary detection | `CrossLangEdge` |
| `ffi-type-mismatch` | Type compatibility across FFI | `CrossLangEdge` |
| `ffi-body-check` | Audit FFI-exposed function bodies | `CrossLangEdge` |
| `ffi-unsafe` | `unsafe` block / `extern "C"` violations | `CrossLangEdge` |
| `ptr-lifetime` | Pointer lifetime across FFI; builds `MemoryGraph` | `CrossLangEdge` + `DangerSurface` |
| `danger-surface` | Marks functions/pointers as danger surfaces | `CrossLangEdge` + `MemoryGraph` |
| `callback-escape` | Callback pointer escapes across FFI | `CrossLangEdge` + `DangerSurface` |
| `memory-safety` | General memory safety on danger paths | `DangerSurface` |
| `free-validation` | Free-site correctness on danger paths | `MemoryGraph` + `DangerSurface` |

### Core data structures

Two shared graphs power the entire Tier 2 analysis:

**CrossLangEdge** -- produced by `call-graph`, consumed by almost everything else. Each entry records: source function, target function, call site location, and the language pair (e.g., Rust->C). This is the map of every place where code crosses a language boundary.

**MemoryGraph** -- produced by `ptr-lifetime`, consumed by `danger-surface` and `free-validation`. It tracks pointer allocation sites, lifetime intervals, and cross-boundary flows. If a Rust-allocated pointer flows into C code and gets freed there, `MemoryGraph` has the full story.

---

## 3. The Pipeline (How It Actually Works)

### 13 passes, topologically sorted

The analysis pipeline runs 13 passes in a strict topological order. Foundation passes (CFG, DFG) run first, then Tier 1 (data gathering), then Tier 2 (issue reporting). Each pass declares its dependencies, and the pipeline refuses to run if there's a cycle.

```
IR Loading
    |
    v
[Foundation: CFG + DFG]
    |
    v
[Tier 1: call-graph -> pointer-flow -> pointer-ownership -> return-check]
    |   produces: CrossLangEdge, flow graphs, alloc/free maps
    v
[Tier 2: ptr-lifetime -> danger-surface -> ffi-* -> callback-escape
         -> memory-safety -> free-validation]
    |   gated by: isOnDangerPath()
    v
[Report: Text / JSON Schema v1 / SARIF v2.1.0]
```

### The critical data flow

Here's the chain that matters most:

```
call-graph --> CrossLangEdge --> ptr-lifetime --> MemoryGraph --> danger-surface --> isOnDangerPath gate
```

`call-graph` finds every FFI call site and records it as a `CrossLangEdge`. `ptr-lifetime` uses those edges to track pointer lifetimes across boundaries, populating `MemoryGraph`. `danger-surface` marks which functions and pointers are actually on danger paths. And then `isOnDangerPath` becomes the bouncer at the door of every Tier 2 pass.

If this chain breaks -- if `CrossLangEdge` is empty, or `MemoryGraph` is incomplete, or `danger-surface` runs too early -- the whole analysis goes quiet. We learned this the hard way (more on that in Section 6).

### Noise reduction: Three layers of filtering

We mentioned the 4,023-to-9 story. Here's how the three layers work:

1. **Name filtering**: Is the function `core::ptr::drop_in_place`? Skip. `std::alloc::__rust_alloc`? Skip. We maintain a registry of 120+ known-safe patterns that look like bugs at the IR level but aren't.

2. **Path filtering**: Using LLVM DebugInfo, we check where the function is defined. `/rustc/library/core/`? Standard library, skip. `zig/lib/std/`? Standard library, skip. If the source path is in a known runtime, we trust it.

3. **Behavior filtering**: Recognize patterns like "allocate new buffer, copy data, free old buffer" as normal `std::vector::push_back()` behavior -- not a memory leak. This is the hardest layer and the one we're still refining.

### Confidence system

Every issue gets a confidence level, because we'd rather be honest about uncertainty than pretend every finding is equally reliable:

| Level | Score | Meaning | What you should do |
|-------|-------|---------|-------------------|
| **HIGH** | >= 0.90 | Direct pattern match, full context | Fix it. Now. |
| **MEDIUM** | >= 0.70 | Heuristic match with supporting evidence | Review it this sprint. |
| **HEURISTIC** | >= 0.50 | Statistical correlation | Investigate when you have time. |
| **EXPERIMENTAL** | < 0.50 | Novel pattern, unvalidated | Research only. File it away. |

Each issue includes a machine-readable `reason` field explaining *why* that confidence was assigned. No black boxes.

---

## 4. What We Found (Real-World Results)

We tested OmniScope against 17 real-world projects. Here's the data.

### Benchmark summary

| Project | Language | Functions | Issues | Ptrs Tracked | FFI Boundaries | Notes |
|---------|----------|-----------|--------|-------------|----------------|-------|
| ring | Rust+C | 278 | 19 | 841 | 4,266 | Safe wrapper, 100% skip |
| wasmtime | Rust | 619 | 44 | 31 | 130 | Detected real CVE-related patterns |
| blst | Rust+C | 267 | 35 | 269 | 1,382 | Rust wrapper + C core |
| curl8 | C | 944 | 114 | 4,948 | 1,499 | Heavy FFI usage |
| sqlite3 | C | 3,250 | 226 | 20,192 | 1,547 | Largest codebase tested |
| zkcrypto | Rust | 287 | **0** | -- | -- | Pure Rust, correctly skipped 100% |
| ripgrep | Rust | 30 | **0** | -- | -- | Clean FFI boundaries |
| rust-sqlite | Rust FFI | 17 | 6 | -- | -- | Active FFI boundary |
| gnark-crypto | Go | 838 | 1 | -- | -- | Experimental Go support |
| jsoncpp | C++ | 1,537 | 3 | -- | -- | After 8-layer C++ FP reduction |
| abseil-cpp | C++ | 193 | 0 | -- | -- | After ref-counted container detection |
| openssl-wrapper | C | 52 | 19 | -- | -- | FFI-dense synthetic |
| zlib-binding | C | 12 | 14 | -- | -- | FFI-dense synthetic |
| sqlite-binding | C | 8 | 4 | -- | -- | FFI-dense synthetic |
| libsodium | C | 10 | 0 | -- | -- | Clean C codebase |
| ark-ff | Rust | 16 | 0 | -- | -- | Small pure Rust |
| wabt_wast2json | C++ | 125 | 2 | -- | -- | WebAssembly toolkit |

### Aggregate numbers

- **548 total issues** across 17 projects
- **27,076 pointers tracked** (across projects with pointer tracking enabled)
- **9,372 FFI boundaries** detected
- **Precision: ~88%** (after manual review of sampled findings)
- **False positive rate: ~14%**

### The numbers we're proud of

**zkcrypto: 0 issues.** This is a pure Rust project with no FFI. OmniScope correctly classified 100% of its functions as Safe Zone and skipped them entirely. Zero noise. This is the "trust the compiler" principle working as designed.

**wasmtime: detected real CVE-related patterns.** We found patterns consistent with [GHSA-4pww-gw9q-vvvh](https://github.com/bytecodealliance/wasmtime/issues/13028) (a sandbox escape vulnerability) in the wasmtime IR. Not because we knew about the CVE -- but because the analysis pipeline flagged the same code path independently.

**Rust FFI TP rate: 0% -> 20%.** In v0.1.5, our Rust FFI detection was... let's be generous and say "aspirational." The true positive rate was 0%. After three phases of bug fixes (14 fixes total), we got it to 20%. That's still not great -- we'll be honest about that -- but it's 20% more than before, and the fixes that got us there were foundational.

### The numbers we're not proud of

**16 out of 20 bugs in `subtle_unsafe_rs` went undetected.** This is a test suite specifically designed to contain subtle unsafe Rust bugs. We caught 4 out of 20. The other 16 require analysis capabilities we don't have yet: size truncation tracking, buffer overflow detection, and type confusion analysis. We're working on it (see Section 8).

---

## 5. The Refactoring Journey (What We Broke and Fixed)

Every project has a "we did something stupid" phase. Oours lasted longer than we'd like to admit. Here are the highlights.

### The greatest hits

**"We filtered out the exact thing we were trying to detect."**

Yes, really. At one point, `__rust_alloc` was in our noise filter. The function that handles Rust's global allocator -- the exact function you need to watch for cross-language allocation mismatches -- we were skipping it. Because at the IR level, allocator calls look "normal" and our noise filter said "this is standard library, skip." We filtered out the signal and kept the noise. Oops.

**7 places registering the same dangerous functions.**

We had `free`, `malloc`, `realloc`, and friends registered as "dangerous functions" in seven different passes. Seven. Each pass maintained its own list. When we needed to add `aligned_alloc`, we had to update seven places. We missed three. Unified it to one registry. Deleted ~200 lines of duplication.

**9 passes with wrong dependency declarations.**

Remember that critical data flow chain? `call-graph -> CrossLangEdge -> ptr-lifetime -> MemoryGraph -> danger-surface -> isOnDangerPath`? Three passes had missing dependency declarations:

- `free-validation` didn't declare a dependency on `danger-surface`, so it could run before danger markers existed. Result: `isOnDangerPath()` returned false for everything. Silent failure.
- `memory-safety` had the same problem.
- `danger-surface` didn't declare a dependency on `ptr-lifetime`, so it could run before `MemoryGraph` was populated. Result: incomplete danger markers, which meant downstream passes got partial data.

These are the kinds of bugs that don't crash -- they just... silently produce wrong results. The worst kind.

### The cleanup tally

| What we did | Impact |
|-------------|--------|
| 14 bug fixes across Phase 1+2+3 | Rust FFI TP rate: 0% -> 20% |
| -700 lines of dead code removed | Codebase: ~2000 -> ~1300 lines of dead code |
| 9 pass dependency declarations fixed | Silent failures eliminated |
| 7 duplicate registrations unified to 1 | Single source of truth for dangerous functions |
| `__rust_alloc` removed from noise filter | Allocator patterns now actually detected |
| 92% test coverage (191 tests) | Up from ~70% |

### Known remaining issues (because honesty matters)

1. **3 passes still have incomplete dependency declarations** -- we fixed 9, but the full audit isn't done yet.
2. **`allocator_kb` is missing Rust's `GlobalAlloc::alloc` trait implementations** -- custom allocator patterns in Rust FFI will produce false negatives.
3. **`allocator_kb` maps `objc_free` incorrectly** -- it maps to `FreeType.free` instead of `FreeType.objc_free`. If you're doing Objective-C interop (bless your heart), this will misclassify things.
4. **Duplicate filter entries in `noise_filter`** -- `std::vector::push_back` and `std::string::c_str` are filtered twice. Minor performance waste, not a correctness issue.

---

## 6. Comparison with Other Tools

We're not the only static analysis tool in the world. We're not even the only *good* one. But we are the only one doing what we do.

| Tool | Input | Cross-Language FFI | IR-Level | Taint Analysis | Ownership Tracking | Open Source | Performance (large project) |
|------|-------|--------------------|----------|----------------|-------------------|-------------|-----------------------------|
| **OmniScope** | LLVM IR | C/C++/Rust/Zig/Go | LLVM IR | Yes | Yes | Apache 2.0 | ~150ms (sqlite3, 3,250 funcs) |
| **CodeQL** | Source/AST | Per-language queries only | No | Yes | Partial | MIT | Minutes (large codebase) |
| **Clang SA** | AST | C/C++ only | No | Yes | Partial | Apache 2.0 | Seconds |
| **Infer** | Source/AST | No | No | Yes | Partial | MIT | Seconds |
| **CBMC** | Source/C | C only | Bit-level | No | Yes | BSD | Minutes to hours |
| **Miri** | MIR | Rust only | No | No | Yes | MIT/Rust | Minutes |
| **cargo-audit** | Crate deps | No | No | No | No | MIT/Apache 2.0 | Seconds |

**Our unique position**: OmniScope is the only static analyzer that performs cross-language FFI analysis at the LLVM IR level. Not source-level heuristics, not per-language queries stitched together -- actual IR-level analysis where language boundaries literally do not exist.

We're also the only tool with Zone Classification (trust the compiler where you can, analyze where you can't) and the only one supporting 5 languages in cross-language FFI analysis.

**What we're NOT**: We're not trying to replace CodeQL for single-language analysis. We're not trying to replace Miri for Rust UB detection. We're not trying to replace Clang SA for C code. We're the tool you run *in addition* to those -- the one that catches the bugs that fall between their cracks.

---

## 7. What's Next

### P0 -- Fix the basics (next release)

- **`allocator_kb` bug fix**: Add Rust's `GlobalAlloc::alloc` trait implementations. Fix the `objc_free` mapping. This is maybe 5 lines of code. We just haven't done it yet. (Shame.)
- **Dependency declaration audit**: Complete the remaining pass dependency fixes. No more silent failures from wrong execution order.

### P1 -- New analysis capabilities

- **Alias chain integration**: Track `ptr_a = ptr_b = malloc(...)` chains properly through the full pipeline. Currently, alias analysis is intra-procedural and doesn't feed into the danger surface computation.
- **Zone gate enhancement**: Make the safe/unsafe/ffi/unknown classification flow-aware, not just function-level. A single function can have both safe and unsafe paths.

### P2 -- Advanced detection

- **MIR-level size truncation**: Detect `usize -> u32` truncation in FFI calls, a common source of silent buffer overflows. This requires analyzing Rust MIR in addition to LLVM IR.
- **Data flow initialization tracking**: Detect use of uninitialized memory across FFI boundaries. Harder than it sounds because LLVM IR's `undef` values are... complicated.

### The real goal

**True positive rate: 20% -> 50%+.**

We're at 20% for Rust FFI detection. That's after going from 0%. The next 30 percentage points will come from P1 and P2 work above. The 16 `subtle_unsafe_rs` bugs we missed? Most of them fall into the P2 categories.

---

## 8. Get Started

### Quick start

```bash
# Build (requires Zig 0.15.2+ and LLVM 18+)
zig build

# Analyze a single IR file
./zig-out/bin/omniscope target.ll

# JSON output for CI integration
./zig-out/bin/omniscope --format json target.ll > report.json

# SARIF output for GitHub Code Scanning
./zig-out/bin/omniscope --format sarif target.ll > results.sarif
```

### Generate LLVM IR from your project

```bash
# C/C++
clang -emit-llvm -g -O1 -c target.c -o target.ll

# Rust
rustc --emit=llvm-ir --crate-type=lib -g target.rs -o target.ll

# Zig
zig build-llvm -femit-llvm-ir target.zig
```

### Further reading

| Document | What it covers |
|----------|---------------|
| [README](../README.md) | Project overview, quick start, feature list |
| [Architecture](./architecture.md) | Tier 1/Tier 2 design, pass dependency graph, data structures |
| [Comprehensive Report](./project_exports/en/COMPREHENSIVE_REPORT.md) | Full 17-project benchmark data |
| [Performance Report](./project_exports/en/PERFORMANCE_IMPROVEMENT.md) | v0.1.5 -> v0.1.6 performance gains |
| [wasmtime Investigation](./investigation_reports/en/wasmtime_source.md) | Real CVE pattern detection deep-dive |
| [FFI-Dense Report](./investigation_reports/en/ffi_dense.md) | 25 real issues found in synthetic FFI code |
| [Letter to Users](./TOUSER/en.md) | The human story behind this project |

---

*OmniScope -- because the boundaries compilers ignore, someone has to watch.*

*Built with Zig. Powered by LLVM IR. Tested against real crash logs at 2 AM.*
