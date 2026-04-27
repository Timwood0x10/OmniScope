# OmniScope Architecture

## System Architecture Overview

```mermaid
graph TB
    User[User Input] --> CLI[CLI: main.zig]

    CLI --> Single[Single File Analysis]

    Single --> Loader[IRLoader<br/>engine/loader.zig]

    Loader --> IR[LLVM IR<br/>.ll files]
    IR --> Module[LLVM ModuleRef]

    Module --> Passes[Analysis Passes]

    subgraph "Analysis Core"
        Passes --> PassManager[PassManager<br/>pass/manager.zig]

        PassManager --> Foundation[Foundation Passes]
        Foundation --> CFG[CFGPass<br/>pass/foundation/cfg.zig]
        Foundation --> DFG[DFGPass<br/>pass/foundation/dfg.zig]

        PassManager --> Analysis[Analysis Passes]
        Analysis --> Pointer[PointerOwnershipPass<br/>pass/analysis/pointer_ownership.zig]
        Analysis --> FFI[FFIDetectorPass<br/>pass/analysis/ffi_detector.zig]
        Analysis --> Taint[TaintPass<br/>pass/analysis/taint.zig]
        Analysis --> Call[CallGraphPass<br/>pass/analysis/call_graph.zig]
        Analysis --> Lock[LockAnalysisPass<br/>pass/analysis/lock.zig]
        Analysis --> Alias[AliasAnalysisPass<br/>pass/analysis/alias.zig]
        Analysis --> Steens[SteensgaardPass<br/>pass/analysis/steensgaard.zig]
        Analysis --> RustFfi[RustFfiAuditor<br/>pass/analysis/rust_ffi_auditor.zig]
        Analysis --> CppFp[CppFpReduction<br/>pass/analysis/cpp_fp_reduction.zig]

        Pointer --> Alloc[AllocationClassifier<br/>pass/analysis/allocation_classifier.zig]

        CFG -.-> PassManager
        DFG -.-> PassManager
    end

    subgraph "Lifetime & Boundary"
        Pointer --> LifetimeEngine[LifetimeEngine<br/>lifetime/engine.zig]
        LifetimeEngine --> Boundary[BoundaryAnalyzer<br/>lifetime/boundary.zig]
    end

    subgraph "Semantic Layer"
        Boundary --> Registry[SemanticRegistry<br/>registry/semantic_registry.zig]
        Registry --> Config[ConfigLoader<br/>registry/config_loader.zig]
    end

    subgraph "Data Flow"
        Pointer --> FlowGraph[DataFlowGraph<br/>dataflow/graph.zig]
        FlowGraph --> Guard[GuardPropagation<br/>dataflow/guard_propagation.zig]
        FlowGraph --> NullCheck[NullCheckGuard<br/>dataflow/null_check_guard.zig]
    end

    subgraph "Output"
        Pointer --> Diag[DiagnosticWriter<br/>pass/pass.zig]
        Diag --> Reporter[ReportGenerator<br/>report/mod.zig]
        Reporter --> Formatter[Formatter<br/>output/formatter.zig]
        Reporter --> SARIF[SARIF Output<br/>output/sarif.zig]
        Reporter --> JSON[JSON Output<br/>main.zig]
    end

    Formatter --> Results[Analysis Results]
    SARIF --> Results
    JSON --> Results
    Results --> User
```

## Module Dependencies

```mermaid
graph LR
    subgraph Core["Core Infrastructure"]
        IR["ir/ - LLVM IR Wrappers"]
        ENG["engine/ - IR Loading"]
        FCT["fact/ - Fact Storage"]
        DF["dataflow/ - Data Flow Graph"]
    end

    subgraph Analysis["Analysis Framework"]
        PAS["pass/ - Analysis Passes"]
        PIP["pipeline/ - Pipeline"]
        DIG["diag/ - Diagnostics"]
    end

    subgraph Semantic["Semantic Layer"]
        REG["registry/ - Semantic Registry"]
        LFT["lifetime/ - Lifetime Engine"]
    end

    subgraph Output["Output & Reporting"]
        OUT["output/ - Result Formatting"]
        REP["report/ - Report Generation"]
    end

    subgraph Track["Tracking"]
        TRK["tracking/ - Memory Tracking"]
    end

    IR --> PAS
    ENG --> PAS
    FCT --> PAS
    FCT --> DIG
    PAS --> PIP
    DIG --> OUT
    DIG --> REP
    PIP --> OUT
    REG --> LFT
    LFT --> PAS
    DF --> PAS
    TRK --> PAS
```

## Data Flow

```mermaid
sequenceDiagram
    participant User
    participant CLI as main.zig
    participant Loader as IRLoader
    participant Pass as PassManager
    participant Pointer as PointerOwnership
    participant Registry as SemanticRegistry
    participant Lifetime as LifetimeEngine
    participant Diag as DiagnosticWriter
    participant Output as Formatter

    User->>CLI: Input file(s)
    CLI->>Loader: Load IR (.ll)
    Loader-->>CLI: Module loaded

    CLI->>Pass: Run analysis pipeline

    Pass->>Pointer: Track ownership (alloc→free)
    Pass->>Registry: Lookup function semantics
    Registry-->>Pass: Function metadata (malloc/free/FFI)

    Pass->>Lifetime: Track ownership boundaries
    Lifetime->>Pass: Boundary facts

    Pass->>Diag: Report findings (OMI-NNN)
    Diag->>Output: Format results
    Output-->>CLI: Formatted output
    CLI-->>User: Analysis results
```

## Component Responsibilities

### User Interface Layer
- **main.zig**: CLI entry point, argument parsing (`--json`, `--sarif`, `-o`), analysis orchestration

### Engine Layer
- **engine/loader.zig**: IR file loading, LLVM context management
- **ir/**: LLVM C API wrappers (raw, safe, view, debug_info, location)

### Analysis Framework
- **pass/manager.zig**: Pass registration and execution
- **pass/pass.zig**: PassContext with HashMap sets (raii/meyers/rc/into_raw/from_raw)
- **pipeline/pipeline.zig**: Analysis pipeline orchestration

### Foundation Passes
- **pass/foundation/cfg.zig**: Control flow graph construction
- **pass/foundation/dfg.zig**: Data flow graph construction

### Analysis Passes
- **pass/analysis/pointer_ownership.zig**: Core memory leak/UAF/double-free detection (936 lines)
  - Ownership transfer detection (return-value / output-param patterns)
  - 8-Layer C++ FP reduction delegation
- **pass/analysis/cpp_fp_reduction.zig**: C++ false positive reduction (937 lines)
  - L1-L8: STL/RAII/Meyers/RC container filters
  - L9: Rust FFI pairing (into_raw/from_raw)
- **pass/analysis/allocation_classifier.zig**: AllocType/FreeType classification (206 lines)
  - `AllocType`: malloc/ocaml_alloc/c_alloc/virtual_alloc/rust_alloc/unknown
  - `FreeType`: free/ocaml_free/c_free/virtual_free/rust_alloc/free_unknown
- **pass/analysis/rust_ffi_auditor.zig**: Rust FFI boundary auditor (464 lines) ← **v0.1.5 NEW**
  - R1: Unpaired `Box::into_raw()` / `CString::into_raw()`
  - R2: `as_ptr` borrow escape detection
  - R3: Cross-lang alloc mismatch (_Znwm → C free)
  - R4: Unsafe FFI calls without validation
  - R5: `extern "C"` type mismatch
  - R6: `#[no_mangle]` export ownership
- **pass/analysis/ffi_detector.zig**: FFI boundary detection and vulnerability analysis
- **pass/analysis/call_graph.zig**: Function call graph, tainted path to sink
- **pass/analysis/taint.zig**: Taint propagation analysis
- **pass/analysis/lock.zig**: Lock analysis and deadlock detection
- **pass/analysis/alias.zig**: Alias analysis
- **pass/analysis/steensgaard.zig**: Steensgaard pointer analysis
- **pass/analysis/taint_propagation.zig**: Taint propagation with path manager
- **pass/instrumentation/planner.zig**: Instrumentation planning

### Data Flow
- **dataflow/graph.zig**: Data flow graph construction
- **dataflow/guard_propagation.zig**: Guard propagation
- **dataflow/null_check_guard.zig**: Null check guard analysis

### Fact System
- **fact/store.zig**: Fact storage and indexing
- **fact/query.zig**: Fact querying engine
- **fact/fact.zig**: Fact type definitions

### Semantic Layer
- **registry/semantic_registry.zig**: Function semantic knowledge base (400+ entries)
- **registry/config_loader.zig**: Dynamic registry from JSON config

### Lifetime Engine
- **lifetime/engine.zig**: Resource lifetime tracking
- **lifetime/boundary.zig**: Cross-language boundary analyzer

### Output System
- **output/formatter.zig**: Result formatting (text)
- **output/cli.zig**: CLI output
- **output/sarif.zig**: SARIF v2.1.0 format output (14 rules)
- **output/lsp.zig**: LSP integration
- **report/mod.zig**: Report generation
- **report/sarif.zig**: SARIF report generation (v2.1.0)
- **report/ci_integration.zig**: CI/CD integration

### Diagnostics
- **diag/issue.zig**: Issue type definitions + Confidence system
  - `Confidence`: HIGH/MEDIUM/HEURISTIC/EXPERIMENTAL
  - `IssueKind`: 14 types (memory_leak, borrow_escape, cross_language_leak, etc.)

### Tracking
- **tracking/allocator.zig**: Memory allocation tracking

## Key Design Principles

1. **Separation of Concerns**: Each layer has distinct responsibilities
2. **Data-Driven Analysis**: Semantic registry provides function knowledge
3. **Ownership Focus**: Core analysis tracks pointer ownership, not generic taint
4. **Cross-Language**: Support for multi-language FFI analysis (C/C++/Rust)
5. **Modularity**: Components can be used independently or together
6. **False Positive Reduction**: 9-layer filtering (L1-L8 C++ + L9 Rust FFI)

## Analysis Pipeline

```mermaid
flowchart TB
    subgraph P1[1. IR Loading]
        IR[Parse LLVM IR<br/>Build ModuleRef]
    end

    subgraph P2[2. Foundation Passes]
        CFG[CFGPass<br/>Control Flow]
        DFG[DFGPass<br/>Data Flow]
    end

    subgraph P3[3. Ownership Tracking]
        OT1[3a. Build<br/>alloc_map + free_map]
        OT2[3b. Build<br/>flow_graph]
        OT3[3c. Ownership transfer<br/>detection]
        OT4[3d. Check alloc→free<br/>violations]
        OT1 --> OT2 --> OT3 --> OT4
    end

    subgraph P4[4. C++ FP Reduction]
        L1[L1: STL internal]
        L2[L2: Special member fns]
        L3[L3: RAII allocations]
        L4[L4: C++ ABI internals]
        L5[L5: Operator overload FFI]
        L6[L6: Meyers singleton]
        L7[L7: RC containers]
        L8[L8: Rust FFI pairing]
        L1 & L2 & L3 & L4 & L5 & L6 & L7 & L8
    end

    subgraph P5[5. Rust FFI Auditor]
        R1[R1: into_raw/from_raw]
        R2[R2: as_ptr escape]
        R3[R3: Cross-lang mismatch]
        R4[R4: Unsafe FFI calls]
        R1 & R2 & R3 & R4
    end

    subgraph P6[6. Additional Analyses]
        FFI[FFIDetector<br/>FFI boundaries]
        Taint[Taint propagation<br/>Source→Sink]
        Call[CallGraph<br/>Tainted paths]
        Addr[Lock + Alias +<br/>Steensgaard]
        FFI & Taint & Call & Addr
    end

    subgraph P7[7. Report Generation]
        Text[Text Output]
        JSON[JSON Schema v1]
        SARIF[SARIF v2.1.0]
        Text & JSON & SARIF
    end

    IR --> P2 --> P3 --> P4 --> P5 --> P6 --> P7

    style P1 fill:#e1f5fe
    style P2 fill:#e8f5e8
    style P3 fill:#fff3e0
    style P4 fill:#fce4ec
    style P5 fill:#f3e5f5
    style P6 fill:#e0f7fa
    style P7 fill:#f1f8e9
```

## Supported Languages

| Language | IR Analysis | Ownership Tracking | FFI Boundary |
|----------|-------------|-------------------|--------------|
| C | ✅ Full | ✅ Full | ✅ Full |
| C++ | ✅ Full | ✅ Full | ✅ Full |
| Rust | ✅ Full (LLVM IR) | ✅ Full | ✅ Rust FFI Auditor |
| Zig | ⚠️ Beta | ⚠️ Beta | ⚠️ Beta |
| Go | ⚠️ Experimental | ⚠️ Experimental | ⚠️ Experimental |

## Issue Detection Categories

| Category | IssueKind | Severity | Confidence |
|----------|-----------|----------|------------|
| **Memory** | memory_leak, use_after_free, double_free, invalid_free | Critical/High | 0.70-0.90 |
| **FFI** | ffi_unsafe_call, unchecked_return, type_mismatch | High | 0.65-0.80 |
| **Rust FFI** | borrow_escape, cross_language_leak, unpaired_into_raw | High | 0.75-0.85 |
| **Security** | command_injection, format_string, buffer_overflow | Critical | 0.75-0.90 |
| **Dereference** | null_dereference | Critical | 0.85 |
| **Concurrency** | (via lock.zig) | High | TBD |

## Output Formats

### Text (Default)
```
VULNERABILITY OMI-001 [high] [Confidence: medium]
Type: borrow_escape
Reason: as_ptr() on local String/Vec passed to extern C - may dangle
```

### JSON (Stable Schema v1)
```json
{
  "schema_version": "1.0.0",
  "tool": "omniscope",
  "tool_version": "0.1.5",
  "summary": {"functions": 135, "issues": 6, "time_ms": 91},
  "issues": [{
    "id": "OMI-001",
    "kind": "borrow_escape",
    "severity": "high",
    "confidence": "MEDIUM",
    "confidence_score": 0.80,
    "cwe_id": 704,
    "reason": "as_ptr() on local String/Vec passed to extern C",
    "message": "Potential as_ptr borrow escape",
    "location": {"function": "leak_cstring"}
  }]
}
```

### SARIF v2.1.0
- 14 rule definitions (all IssueKind variants)
- GitHub Code Scanning compatible
- Properties: `confidence`, `confidenceLevel`, `reason`, `cwe`

## File Organization Rules

Per **rules.md §49**: Maximum 1000 lines per `.zig` file

| File | Lines | Status |
|------|-------|--------|
| pointer_ownership.zig | 936 | ✅ ≤1000 |
| cpp_fp_reduction.zig | 937 | ✅ ≤1000 |
| allocation_classifier.zig | 206 | ✅ ≤1000 |
| rust_ffi_auditor.zig | 464 | ✅ ≤1000 |
| ffi_detector.zig | 729 | ✅ ≤1000 |
| lock.zig | 719 | ✅ ≤1000 |
| taint.zig | 708 | ✅ ≤1000 |
