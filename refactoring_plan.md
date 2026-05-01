# OmniScope Refactoring Plan: IR + MemoryGraph + ZoneTag

> **One-line design**: IR produces facts, MemoryGraph is the core, JSON provides annotations, a few Hooks patch semantics.
>
> **Core principle**: OmniScope finds bugs where language guarantees stop. It does NOT try to find all bugs.

---

## 0. Immutable Constraints (non-negotiable)

### 0.1 Project identity (carved in stone)

> **OmniScope only cares about cross-language / post-guarantee memory behavior.**

This is the project's reason for existence. It will NOT be changed, extended, or compromised.

| In scope (this is what we do) | Out of scope (this is what we don't) |
|-------------------------------|--------------------------------------|
| Cross-language FFI boundaries | Plain single-language bugs (Clang SA/ASAN job) |
| Memory behavior after language guarantees stop | Integer overflow, format string, SQL injection |
| Ownership transfer across language borders | Weak crypto, password clearing, injection |
| Escape from safe language model (into_raw, pointer→C) | Pure Rust/Zig/Go bugs (their compiler's job) |
| Lifecycle outside compiler control (callback, dlopen, thread) | Full borrow checker / lifetime parameter inference |
| **IR + Graph + Minimal Semantics** | **Large model integration** |
| **Small and hard** | **Large and fuzzy** |
| **Punch through FFI** | **Be a general-purpose analyzer** |

The test: **Can the language still guarantee safety here?** If yes → not our problem. If no → analyze.

### 0.2 FP precision guard (prerequisite for any removal)

> **You CANNOT remove existing FP filtering until MemoryGraph ownership precision ≥ current FP filtering effect.**

This is a hard gate, not a suggestion. Violating it means FP explosion — worse than today.

**Current baseline** (v0.1.6):

| Metric | Value |
|--------|-------|
| FFI-Precision | ~88% |
| FP-FFI count | ~0 |
| wasmtime noise reduction | 297 → 9 issues (-97%) |
| blst skip ratio | 64% |
| wasmtime skip ratio | 74% |

**Gate rule**: Before removing any FP filtering mechanism (e.g., 8-layer C++ filter, intrinsic suppression, drop glue filtering), you MUST prove on the SAME test set that the replacement (zone/tag + MemoryGraph) achieves:

- FFI-Precision ≥ 88%
- FP count ≤ current baseline
- Noise reduction ≥ 97% on wasmtime

**Implementation**: Run A/B comparison at each removal step. If precision drops, keep the old filter and improve MemoryGraph first.

---

## 1. Problem Statement

### 1.1 Language coupling scattered across 10+ files (~800 lines)

| File | Hardcoded lines | Content |
|------|----------------|---------|
| `semantics/zone_classifier.zig` | ~250 | Rust/Zig/Go/C++/C safe/escape/ffi pattern arrays |
| `pass/analysis/ffi_enhancement.zig` | ~200 | Rust 200+ intrinsic risk levels + 5 language detectors |
| `pass/analysis/cpp_fp_reduction.zig` | ~150 | C++ 8-layer FP filter + Rust drop glue + SQLite/Abseil |
| `lifetime/mapper.zig` | ~80 | 22 compile-time semantic mapping rules |
| `lifetime/boundary.zig` | ~50 | Language detection + 2 contract rules |
| `pass/analysis/allocation_classifier.zig` | ~60 | Allocator/deallocator language classification |
| `pass/analysis/callback_escape.zig` | ~40 | Go cgo + C retaining function whitelist |
| `pass/analysis/ffi_language_classifier.zig` | ~100 | JNI/Python C API/C++ ABI detection |
| `pass/analysis/memory_safety.zig` | ~30 | Rust panic/cleanup detection |
| `pass/analysis/free_validation.zig` | ~20 | Rust dealloc + C++ delete detection |

### 1.2 Same logic duplicated in multiple files

- `identifyLanguage()` duplicated in **4 files**
- `isStlInternalFunction()` duplicated in **2 files**
- `isCppAbiInternalFunction()` duplicated in **2 files**
- `isRustDropGlue()` duplicated in **2 files**

### 1.3 Root cause: FP filtering at string level, not semantic level

The 8-layer C++ FP reduction is "symptom patching", not "correct model":
- Rule count grows with project count (STL → libc++ → Abseil → Boost → ...)
- Name-based filtering can mask real bugs (e.g., `free(v.data())` inside STL code)
- Fundamentally conflicts with IR-driven analysis

---

## 2. Target Architecture

```
LLVM IR
   ↓
[ IR Core: loader + raw/safe wrappers ]
   ↓
MemoryGraph + CallGraph        ← first-class citizens
   ↓
[ Core Analysis: language-agnostic ]
   ↓
ZoneTag + Tag + Hook           ← lightweight semantic layer
   ↓
Diagnostics
```

### 2.1 Four core concepts (no more, no less)

#### Concept 1: MemoryGraph (keep and strengthen)

Existing design is correct. Continue using:

- `alloc` → node
- `free` → edge
- `pointer` → flow
- `call` → link

All analysis derives from it:

| Issue | Graph pattern |
|-------|--------------|
| leak | alloc node with no free edge |
| double free | free edge count > 1 |
| use-after-free | use after free edge |
| escape | flow crosses zone boundary |

#### Concept 2: ZoneTag (simplified, but critical)

```zig
/// Minimal zone tag set. Do NOT extend.
pub const ZoneTag = enum {
    Unknown,
    // General
    CHeap,
    // Language-specific semantics (only necessary ones)
    RustOwned,
    PythonRef,
    GoPointer,
    // Boundary
    FFI,
};
```

FFI detection becomes trivial:

```zig
// If caller and callee are in different zones, it's an FFI boundary
if (caller_zone != callee_zone) {
    // This is an FFI boundary — analyze ownership transfer
}
```

#### Concept 3: JSON annotations (label only, no logic)

JSON can ONLY do three things:

| Can do | Cannot do |
|--------|-----------|
| Mark alloc/free | Path logic |
| Mark zone | Ownership inference |
| Mark risk tags | Complex rules |

```json
{
  "language": "c",
  "detect": [
    { "pattern": "malloc", "type": "exact" },
    { "pattern": "free", "type": "exact" }
  ],
  "functions": [
    {
      "pattern": "malloc",
      "tags": ["alloc", "returns_owned"],
      "zone": "CHeap"
    },
    {
      "pattern": "free",
      "tags": ["free"]
    }
  ]
}
```

#### Concept 4: Hook (minimal, strictly controlled)

```zig
/// Semantic hook for language-specific analysis that cannot be expressed in JSON.
/// Only 3 hooks are allowed. No hook = no advanced semantics for that language.
pub const SemanticHook = fn(ctx: *AnalysisContext, node: *MemoryNode) void;
```

| Hook | Language | What it does |
|------|----------|-------------|
| `pythonRefcountHook` | Python | Track Py_INCREF/Py_DECREF pairing |
| `goEscapeHook` | Go | Detect Go pointer escape to C |
| `rustOwnershipHook` | Rust | Track into_raw/from_raw pairing |

**Principle**: Without a hook, a language gets basic zone-based analysis only. Hooks are the escape hatch for semantics that JSON cannot express.

### 2.2 Unified Pass pattern (all passes follow this)

```zig
// BEFORE (language-specific, scattered):
if (isRustFunction(name)) { ... }
if (isCppFunction(name)) { ... }
if (isGoFunction(name)) { ... }

// AFTER (unified, registry-driven):
const info = registry.query(function_name);
if (info.hasTag("alloc")) { ... }
if (info.hasTag("free")) { ... }
if (info.zone == .CHeap) { ... }
```

**Forbidden in passes**:
- Language name strings ("rust", "c", "zig")
- Function name whitelists
- Pattern matching arrays

---

## 3. Registry Design (minimal, no over-engineering)

### 3.1 Core types

```zig
/// Semantic tag for a function. Minimal set — do NOT extend.
pub const Tag = enum {
    Alloc,
    Free,
    Borrow,
    Transfer,
    FFI,
};

/// Function info returned by registry query.
pub const FunctionInfo = struct {
    tags: []const Tag,
    zone: ZoneTag,
};

/// Pattern match type.
pub const MatchType = enum {
    exact,
    prefix,
    suffix,
    contains,
};

/// Single function annotation rule (loaded from JSON).
pub const FunctionRule = struct {
    pattern: []const u8,
    match_type: MatchType,
    tags: []const []const u8,
    zone: ?[]const u8,
};

/// Language detection rule (loaded from JSON).
pub const DetectRule = struct {
    pattern: []const u8,
    match_type: MatchType,
    zone: ZoneTag,
};
```

### 3.2 Registry API

```zig
/// Minimal registry. All passes query through this.
pub const Registry = struct {
    allocator: std.mem.Allocator,
    /// function name → FunctionInfo (pre-built hash map for O(1) lookup)
    func_map: std.StringHashMap(FunctionInfo),
    /// language detection rules (evaluated at load time)
    detect_rules: []const DetectRule,
    /// registered semantic hooks
    hooks: std.ArrayList(SemanticHookEntry),

    /// Query function info. Returns null if no rule matches.
    pub fn query(self: *const Registry, name: []const u8) ?FunctionInfo;

    /// Load rules from JSON file. User rules override built-in rules.
    pub fn loadJson(self: *Registry, path: []const u8) !void;

    /// Register a semantic hook for a specific zone.
    pub fn registerHook(self: *Registry, zone: ZoneTag, hook: SemanticHook) void;

    /// Run all hooks applicable to the given node.
    pub fn runHooks(self: *Registry, ctx: *AnalysisContext, node: *MemoryNode) void;
};
```

### 3.3 JSON format (one file per language)

```json
{
  "language": "rust",
  "detect": [
    { "pattern": "_ZN", "type": "prefix", "zone": "RustOwned" },
    { "pattern": "_R", "type": "prefix", "zone": "RustOwned" }
  ],
  "functions": [
    {
      "pattern": "into_raw",
      "type": "contains",
      "tags": ["transfer", "ffi"],
      "zone": "FFI"
    },
    {
      "pattern": "from_raw",
      "type": "contains",
      "tags": ["alloc"],
      "zone": "RustOwned"
    },
    {
      "pattern": "drop_in_place",
      "type": "contains",
      "tags": ["free"],
      "zone": "RustOwned"
    }
  ]
}
```

```json
{
  "language": "c",
  "detect": [
    { "pattern": "malloc", "type": "exact", "zone": "CHeap" },
    { "pattern": "free", "type": "exact", "zone": "CHeap" }
  ],
  "functions": [
    { "pattern": "malloc", "type": "exact", "tags": ["alloc", "ffi"], "zone": "CHeap" },
    { "pattern": "calloc", "type": "exact", "tags": ["alloc", "ffi"], "zone": "CHeap" },
    { "pattern": "realloc", "type": "exact", "tags": ["alloc", "ffi"], "zone": "CHeap" },
    { "pattern": "free", "type": "exact", "tags": ["free", "ffi"], "zone": "CHeap" },
    { "pattern": "dlopen", "type": "exact", "tags": ["ffi"], "zone": "FFI" },
    { "pattern": "dlsym", "type": "exact", "tags": ["ffi"], "zone": "FFI" }
  ]
}
```

---

## 4. FFI Analysis (rewritten, simple)

### 4.1 FFI boundary detection (one rule)

```zig
// FFI = zone mismatch. That's it.
fn isFFIBoundary(caller: ZoneTag, callee: ZoneTag) bool {
    return caller != callee and
        caller != .Unknown and
        callee != .Unknown;
}
```

### 4.2 FFI issue detection (three categories only)

| Category | Detection | Example |
|----------|-----------|---------|
| **Ownership break** | alloc in zone A → crosses FFI → no matching free | Rust `into_raw` → C uses → nobody calls `from_raw` |
| **Cross-language double free** | Same resource freed in two different zones | Rust `Drop` frees + C `free()` on same pointer |
| **Escape** | Pointer flows from safe zone to CHeap and is stored | Go pointer → C global variable (requires hook) |

### 4.3 What we explicitly do NOT do

- Complex contract systems between language pairs
- Deep path-sensitive analysis across FFI boundaries
- Full borrow checker modeling
- SQL injection / weak crypto / password clearing

**OmniScope finds bugs where language guarantees stop.**

---

## 5. What to Remove / Deprecate (with FP guard)

**⚠️ Every removal below requires passing the FP precision gate (§0.2) FIRST.**

| Item | Action | Reason | FP Guard |
|------|--------|--------|----------|
| Language classifier duplicates (4 copies) | Remove | Replaced by registry `detect` rules | N/A (pure dedup, no behavior change) |
| Complex FFI matcher (`ffi_matcher.zig` multi-module) | Deprecate | Zone mismatch is simpler and more correct | N/A (not in active pipeline) |
| Complex contract system in `boundary.zig` | Remove | Zone mismatch + 3 hooks covers real cases | N/A (only 2 rules, never triggered) |
| `ffi_boundary.zig` (1800+ lines) | Split | Break into zone_classifier + ffi_check + noise_filter | N/A (restructure, not removal) |
| **8-layer C++ FP reduction** | **Remove AFTER guard passes** | Replaced by zone/tag semantic filtering | **Must prove Precision ≥ 88% on wasmtime** |
| **Intrinsic suppression** | **Remove AFTER guard passes** | Move to JSON annotations | **Must prove noise reduction ≥ 97% on wasmtime** |
| **Drop glue filtering** | **Remove AFTER guard passes** | Replaced by RustOwned zone tag | **Must prove FP count ≤ baseline on ring/blst** |

**Removal order matters**: Remove language duplicates first (safe). Then split ffi_boundary.zig (restructure). Then prove MemoryGraph precision ≥ FP filter effect. Only then remove FP filters one by one with A/B testing.

---

## 6. Component Reuse

### 6.1 Reuse as-is (no changes)

| Component | File | Why |
|-----------|------|-----|
| Pass framework | `pass/pass.zig`, `pass/manager.zig` | Comptime interface, topological sort, graceful degradation |
| Pipeline | `pipeline/pipeline.zig` | FactStore + QueryEngine + DataFlowGraph composition |
| Fact system | `fact/` | Universal key-value fact storage |
| DataFlow graph | `dataflow/graph.zig`, `node.zig`, `edge.zig` | Language-agnostic data flow |
| Path condition | `dataflow/path_condition.zig` | Path-sensitive analysis foundation |
| Rule engine | `diag/rule_engine.zig` | Pattern match + action execution |
| SARIF output | `output/sarif.zig` | GitHub Code Scanning compatible |
| Lifetime engine | `lifetime/engine.zig` | State machine is language-agnostic |
| IR loader | `engine/loader.zig` | LLVM IR loading |
| Alias analysis | `pass/analysis/alias.zig` | Pure IR analysis |
| Buffer overflow | `pass/analysis/buffer_overflow.zig` | Pure IR analysis |
| Integer overflow | `pass/analysis/issue/integer_overflow.zig` | Pure IR analysis |
| Malloc check | `pass/analysis/issue/malloc_check.zig` | Pure IR analysis |

### 6.2 Refactor (remove language hardcoding)

| Component | Current | After |
|-----------|---------|-------|
| Zone classifier | 250 lines hardcoded patterns | Registry query |
| FFI enhancement | 200 lines intrinsic hardcoding | JSON annotations |
| CPP FP reduction | 8-layer C++ filter | Zone/tag semantic filter |
| Lifetime mapper | 22 compile-time rules | Registry query |
| Lifetime boundary | 2 contract rules + language detection | Zone mismatch |
| Allocation classifier | Fallback hardcoding | Registry query |
| Callback escape | Go cgo hardcoding | Hook-based |
| Memory safety | Rust panic detection | Registry query |
| Free validation | Rust dealloc detection | Registry query |
| Call graph | LIBC_FUNCTIONS hardcoding | Registry query |
| FFI boundary | 1800-line monolith | Split into 3 focused modules |

### 6.3 New files

| Component | File | Responsibility |
|-----------|------|---------------|
| Unified types | `src/common/types.zig` | Global Location/Severity/IssueKind |
| Registry | `src/registry/registry.zig` | FunctionInfo query + JSON loading + hooks |
| Language rules | `config/languages/*.json` | Per-language annotation files |

---

## 7. Execution Plan (10 days, realistic)

### Phase 1: Foundation (Day 1–3)

**Goal**: Define core types, build minimal registry, validate with existing tests.

| Step | Task | Verify |
|------|------|--------|
| 1.1 | Create `src/common/types.zig` with unified Location/Severity/IssueKind | `zig build check` passes |
| 1.2 | Migrate all modules to use `common/types.zig` | All existing tests pass |
| 1.3 | Extract `identifyLanguage()` into single implementation | 4 duplicate sites removed |
| 1.4 | Define ZoneTag + Tag enums in `src/registry/registry.zig` | Compiles, tests pass |
| 1.5 | Implement minimal Registry: `query()`, `loadJson()` | Unit test: JSON → query → FunctionInfo |

**Success criteria**:
- `zig build check` passes
- All existing tests pass
- Net reduction of 200+ lines (duplicates removed)

### Phase 2: Migrate passes (Day 4–7)

**Goal**: Replace language hardcoding in passes with registry queries.

| Step | Task | Verify |
|------|------|--------|
| 2.1 | Create `config/languages/c.json` with all C patterns | Registry query matches old behavior |
| 2.2 | Create `config/languages/rust.json` with all Rust patterns | Registry query matches old behavior |
| 2.3 | Refactor `allocation_classifier.zig`: remove fallback hardcoding | Tests pass, no language strings in code |
| 2.4 | Refactor `memory_safety.zig`: remove `isRustPanicOrCleanupStr()` | Tests pass |
| 2.5 | Refactor `free_validation.zig`: remove `isRustDeallocFunction()` | Tests pass |
| 2.6 | Refactor `call_graph.zig`: move LIBC_FUNCTIONS to JSON | Tests pass |
| 2.7 | Refactor `lifetime/mapper.zig`: query registry instead of RULES array | Tests pass |
| 2.8 | Refactor `lifetime/boundary.zig`: use zone mismatch for FFI detection | Tests pass |
| 2.9 | Split `ffi_boundary.zig` into zone_classifier + ffi_check + noise_filter | Each file < 500 lines |

**Success criteria**:
- No language name strings in any pass
- No function name whitelists in any pass
- All existing tests pass
- Regression test results unchanged

### Phase 3: Hooks + new languages (Day 8–10)

**Goal**: Implement 3 semantic hooks, add Go/Zig JSON rules, validate.

| Step | Task | Verify |
|------|------|--------|
| 3.1 | Implement hook registration in Registry | Unit test: register + run hook |
| 3.2 | Implement `rustOwnershipHook` (into_raw/from_raw pairing) | Test: paired calls = no issue, unpaired = issue |
| 3.3 | Implement `goEscapeHook` (pointer escape detection) | Test: Go pointer stored in C = issue |
| 3.4 | Implement `pythonRefcountHook` (Py_INCREF/Py_DECREF) | Test: unbalanced refcount = issue |
| 3.5 | Create `config/languages/go.json` | Go cgo patterns annotated |
| 3.6 | Create `config/languages/zig.json` | Zig extern patterns annotated |
| 3.7 | Refactor `callback_escape.zig`: use hooks instead of hardcoding | Tests pass |
| 3.8 | Full regression test on corpus/ | Results >= baseline |
| 3.9 | Performance benchmark | No regression > 5% |

**Success criteria**:
- 3 hooks implemented and tested
- Go/Zig JSON rules created
- Corpus regression tests pass
- Performance within 5% of baseline

---

## 8. Before vs After

### 8.1 Adding a new language

| Step | Before | After |
|------|--------|-------|
| Language detection | Modify 4+ files | Write JSON `detect` rules |
| Zone classification | Modify `zone_classifier.zig` | Write JSON `zone` field |
| Function semantics | Modify `semantic_registry.zig` | Write JSON `functions` |
| Advanced semantics | Not possible | Write a Hook (Zig code) |
| **Total** | **Modify 6+ Zig files** | **Write 1 JSON file** |

### 8.2 Code metrics

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Zig source lines | ~15,000 | ~12,000 | -20% |
| Language-specific hardcoding | ~800 lines | 0 lines | -100% |
| JSON annotation lines | ~100 lines | ~800 lines | +700 lines |
| Duplicate code | ~300 lines | 0 lines | -100% |
| Max file size | 1800+ lines | < 500 lines | -72% |

### 8.3 Architecture quality

| Metric | Before | After |
|--------|--------|-------|
| Add language requires Zig changes? | Yes (6+ files) | **No** |
| Language knowledge centralized? | No (10+ files) | **Yes (JSON files)** |
| Runtime extensible? | Partial (function semantics only) | **Yes (full)** |
| Type system unified? | No (3-4 definitions) | **Yes** |
| FP filtering approach | String-level whitelists | **Semantic zone/tag** |

---

## 9. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| JSON query slower than compile-time constants | 5-10% performance | Pre-build HashMap at load time; cache hot queries |
| Rule migration introduces regressions | Analysis results change | Phase 2 step-by-step with test-after-each |
| JSON cannot express complex semantics | Some language features unsupported | 3 Hooks cover Python/Go/Rust; other languages get basic zone analysis |
| Users struggle with JSON format | Slow adoption | Provide templates; built-in rules as reference |

---

## 10. Key Design Decisions

### 10.1 Why not a "perfect" unified language registry?

The original plan had `LanguageProfile` with 7 sub-fields (detection, zone_rules, function_semantics, ownership_mappings, ffi_contracts, noise_filters, hooks). This is over-engineering:

- Most fields overlap in purpose
- Complex JSON schemas are hard to validate and debug
- The "configuration solves semantics" antipattern

**Decision**: JSON annotates (tags + zone). Hooks handle semantics. Nothing else.

### 10.2 Why only 3 hooks?

Each hook is a maintenance burden. The principle is:

> No hook = basic zone-based analysis (still useful).
> Hook = advanced semantics for that language (better, but costs more).

Python refcount, Go pointer escape, and Rust into_raw/from_raw are the three cases where JSON truly cannot express the semantics. Everything else (alloc/free pairing, zone classification, FFI boundary detection) works with tags alone.

### 10.3 Why remove 8-layer C++ FP reduction? (AFTER guard passes)

The 8 layers are "symptom patching":
- Rule count grows with project count (STL → libc++ → Abseil → Boost → ...)
- Name-based filtering can mask real bugs
- Conflicts with IR-driven analysis

**BUT**: You cannot remove them until MemoryGraph ownership precision ≥ current FP filtering effect (see §0.2). The replacement (zone/tag semantic filtering) must first prove it suppresses noise at least as well on wasmtime/ring/blst.

**Replacement**: Zone/tag semantic filtering. `std::allocator` → CHeap zone. `operator new` → Alloc tag. The analysis engine handles the rest based on MemoryGraph patterns, not name whitelists.

### 10.4 Why is OmniScope's scope limited?

**OmniScope finds bugs where language guarantees stop.**

| In scope | Out of scope |
|----------|-------------|
| Cross-language boundaries | Plain buffer overflow (Clang SA/ASAN) |
| Manual memory management (malloc/free) | Integer overflow |
| Escape from language model (into_raw, pointer→C) | Pure single-language issues |
| Lifecycle outside compiler control (callback, dlopen, thread) | SQL injection, weak crypto |

The test is simple: **Can the language still guarantee safety here?** If yes → not our problem. If no → analyze.
