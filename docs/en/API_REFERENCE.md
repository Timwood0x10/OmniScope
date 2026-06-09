# OmniScope API Reference

> Version: v0.2.0 | Language: Zig 0.15.2

## 1. Core Data Structures

### 1.1 Issue

**File**: `src/diag/issue.zig`

```zig
pub const Issue = struct {
    id: []const u8,
    kind: Kind,
    severity: Severity,
    confidence: Confidence,
    confidence_score: f64,
    cwe_id: u16,
    message: []const u8,
    location: Location,
    trace: ?[]TraceEntry,
};
```

#### IssueKind (20 types)

| Kind | CWE |
|------|-----|
| `memory_leak` | CWE-401 |
| `use_after_free` | CWE-416 |
| `double_free` | CWE-415 |
| `null_dereference` | CWE-476 |
| `buffer_overflow_risk` | CWE-120 |
| `stack_buffer_overflow` | CWE-121 |
| `invalid_free` | CWE-763 |
| `borrow_escape` | CWE-416 |
| `cross_language_free` | CWE-415 |
| `cross_language_leak` | CWE-401 |
| `ffi_unsafe_call` | CWE-676 |
| `jni_type_mismatch` | CWE-754 |
| `jni_unchecked_return` | CWE-252 |
| `tainted_path_to_sink` | CWE-88 |
| `command_injection` | CWE-78 |
| `format_string` | CWE-134 |
| `unsafe_deserialization` | CWE-502 |
| `ownership_violation` | CWE-401 |
| `data_race` | CWE-362 |
| `thread_safety_violation` | CWE-807 |

#### Severity

| Level | Meaning |
|-------|---------|
| `critical` | Exploitable UB or memory corruption |
| `high` | Likely bug at FFI boundary |
| `medium` | Needs manual confirmation |
| `low` | Diagnostic or heuristic |

#### Confidence

| Level | Threshold |
|-------|-----------|
| `HIGH` | ≥ 0.75 |
| `MEDIUM` | ≥ 0.55 |
| `LOW` | ≥ 0.35 |
| `HEURISTIC` | < 0.35 |

### 1.2 Location

**File**: `src/diag/issue.zig`

```zig
pub const Location = struct {
    function: []const u8,
    file: ?[]const u8,
    line: ?u32,
    column: ?u32,
};
```

### 1.3 FFIBoundary

```zig
pub const FFIBoundary = struct {
    caller_lang: []const u8,
    callee_lang: []const u8,
    caller_function: []const u8,
    callee_function: []const u8,
    boundary_type: BoundaryType,
};
```

## 2. Analysis Engine API

### 2.1 IRLoader

**File**: `src/engine/loader.zig`

```zig
pub const IRLoader = struct {
    pub fn init(allocator: Allocator) IRLoader
    pub fn loadFile(self: *IRLoader, path: []const u8) !void
    pub fn loadBuffer(self: *IRLoader, buf: []const u8) !void
    pub fn getModule(self: *IRLoader) c.LLVMModuleRef
    pub fn getFunctionCount(self: *IRLoader) u32
    pub fn deinit(self: *IRLoader) void
};
```

### 2.2 Pipeline

**File**: `src/pipeline/pipeline.zig`

```zig
pub const Pipeline = struct {
    pub fn init(allocator: Allocator, module: c.LLVMModuleRef, config: Config) !Pipeline
    pub fn run(self: *Pipeline) !PipelineResult
    pub fn deinit(self: *Pipeline) void
};

pub const PipelineResult = struct {
    fact_count: u32,
    issue_count: u32,
    time_ms: u64,
};
```

## 3. Pass System

### 3.1 Pass Interface

**File**: `src/pass/pass.zig`

```zig
pub const Pass = struct {
    name: []const u8,
    kind: PassKind,
    deps: []const []const u8,
    run: fn (*PassContext, *DiagnosticWriter) anyerror!void,
};

pub const PassKind = enum { foundation, analysis, filter };
```

### 3.2 PassContext

**File**: `src/types/pass_types.zig`

Key fields accessible to passes:

| Field | Type | Purpose |
|-------|------|---------|
| `module` | `c.LLVMModuleRef` | LLVM module |
| `ir_store` | `*ModuleIRStore` | Pre-collected functions/instructions |
| `fact_store` | `*FactStore` | Shared fact storage |
| `data_flow_graph` | `*DataFlowGraph` | Data flow graph + issues |
| `memory_graph` | `*MemoryGraph` | Allocation/free/alias model |
| `call_site_index` | `*CallSiteIndex` | Callee → call site mapping |
| `cross_lang_edges` | `*CrossLangEdges` | Cross-language call edges |
| `language_overrides` | `*LanguageOverrideRegistry` | User language overrides |
| `semantic_resolution` | `*SemanticTree` | SRT state |
| `danger_surface_relevant` | `*std.AutoHashMap(u64, void)` | Danger surface markers |
| `ffi_auto_relevant` | `*std.AutoHashMap(u64, void)` | FFI relevance markers |

### 3.3 PassManager

**File**: `src/pass/manager.zig`

```zig
pub const PassManager = struct {
    pub fn register(self: *PassManager, pass: Pass) !void
    pub fn run(self: *PassManager, ctx: *PassContext, writer: *DiagnosticWriter) !void
};
```

## 4. Issue Insertion Path

Passes report issues via `ctx.addIssue()`:

```zig
pub fn addIssue(ctx: *PassContext, issue: Issue) !void
```

This function applies:

1. **Surface classification** — boundary/user/runtime/internal
2. **Issue Gate** — SRT-based suppression (10 verdict types)
3. **FP precision guard** — confidence threshold checks
4. **Deduplication** — same function + same kind + same evidence
5. **Severity adjustment** — surface-aware severity downgrading

## 5. Configuration

### 5.1 CLI Flags

**File**: `src/config/main_config.zig`

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--json` | bool | false | JSON output |
| `--sarif` | bool | false | SARIF output |
| `-o/--output` | string | stdout | Output file path |
| `--boundary-only` | bool | false | Show only boundary issues |
| `--min-severity` | enum | low | Minimum severity filter |
| `--focus-user-code` | bool | true | Suppress stdlib/compiler noise |
| `--leak-threshold` | f64 | 0.0 | Leak confidence threshold |
| `--lang` | string | — | Language override (exact name) |
| `--lang-prefix` | string | — | Language override (prefix) |
| `--default-lang` | string | — | Default language for unknowns |
| `--report-surfaces` | bool | false | Report FFI export surfaces |
| `--config` | string | — | Config file path |
| `--perf-stats` | bool | false | Show per-pass timing |

### 5.2 Language Override

**File**: `src/config/language_override.zig`

```zig
pub const LanguageOverrideRegistry = struct {
    pub fn addExact(self: *Self, name: []const u8, lang: Language) !void
    pub fn addPrefix(self: *Self, prefix: []const u8, lang: Language) !void
    pub fn addSuffix(self: *Self, suffix: []const u8, lang: Language) !void
    pub fn addSourceFile(self: *Self, file: []const u8, lang: Language) !void
    pub fn classify(self: *const Self, name: []const u8) ?Language
};
```

## 6. Output Formats

### 6.1 JSON Schema

```json
{
  "schema_version": "1.0.0",
  "tool": "omniscope",
  "tool_version": "0.2.0",
  "timestamp": 0,
  "summary": {
    "functions": 0,
    "issues": 0,
    "time_ms": 0
  },
  "issues": [
    {
      "id": "OMI-001",
      "kind": "memory_leak",
      "severity": "medium",
      "confidence": "MEDIUM",
      "confidence_score": 0.70,
      "cwe_id": 401,
      "message": "...",
      "location": { "function": "..." },
      "ffi_boundary": null
    }
  ]
}
```

### 6.2 SARIF

**File**: `src/output/sarif.zig`

Follows the SARIF v2.1.0 specification. Each issue maps to a `result` object with:

- `ruleId`: issue kind (e.g. `memory_leak`)
- `level`: mapped from severity
- `message.text`: human-readable description
- `locations[0].physicalLocation.artifactLocation.uri`: source file
- `properties.confidence_score`: numeric confidence
- `properties.cwe_id`: CWE classification
