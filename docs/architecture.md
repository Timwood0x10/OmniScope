# OmniScope Architecture

## System Architecture Overview

```mermaid
graph TB
    User[User Input] --> CLI[CLI: main.zig]
    
    CLI --> Single[Single File Analysis]
    CLI --> Multi[Multi-File FFI Analysis]
    
    Single --> Loader[IRLoader<br/>engine/loader.zig]
    Multi --> Loaders[Multiple IRLoaders]
    
    Loader --> IR[LLVM IR<br/>.bc/.ll files]
    Loaders --> IR
    
    IR --> Passes[Analysis Passes]
    
    subgraph "Analysis Core"
        Passes --> PassManager[PassManager<br/>pass/manager.zig]
        PassManager --> Static[StaticStage<br/>pipeline/static_stage.zig]
        
        Static --> CallGraph[CallGraphPass]
        Static --> PointerFlow[PointerFlowPass]
        Static --> FFIBoundary[FFIBoundaryPass]
        Static --> PointerOwnership[PointerOwnershipPass]
        Static --> OwnershipViolation[OwnershipViolationPass]
        
        PointerFlow --> FactStore[FactStore<br/>fact/store.zig]
        FFIBoundary --> FactStore
        CallGraph --> FactStore
        PointerOwnership --> FactStore
        OwnershipViolation --> FactStore
        
        FactStore --> QueryEngine[QueryEngine<br/>fact/query.zig]
        
        QueryEngine --> Diag[DiagnosticAggregator<br/>diag/aggregator.zig]
    end
    
    subgraph "Cross-Language Analysis"
        FFIBoundary --> FFIMatcher[FFIMatcher<br/>ffi/ffi_matcher.zig]
        FFIMatcher --> SemanticRegistry[SemanticRegistry<br/>registry/semantic_registry.zig]
        SemanticRegistry --> OwnershipViolation
    end
    
    Diag --> Output[Output Formatter<br/>output/formatter.zig]
    OwnershipViolation --> Output
    
    Output --> Formats[Output Formats]
    Formats --> Text[Text]
    Formats --> JSON[JSON]
    Formats --> SARIF[SARIF]
    
    subgraph "Lifetime Engine"
        PointerOwnership --> LifetimeEngine[LifetimeEngine<br/>lifetime/engine.zig]
        LifetimeEngine --> SemanticMapper[SemanticMapper<br/>lifetime/mapper.zig]
        SemanticMapper --> SemanticRegistry
    end
    
    Text --> Results[Analysis Results]
    JSON --> Results
    SARIF --> Results
    Results --> User
```

## Module Dependencies

```mermaid
graph LR
    subgraph Core[Core Infrastructure]
        IR[ir/ - LLVM IR Wrappers]
        Engine[engine/ - IR Loading]
        Fact[fact/ - Fact Storage]
        DataFlow[dataflow/ - Data Flow Graph]
    end
    
    subgraph Analysis[Analysis Framework]
        Pass[pass/ - Analysis Passes]
        Pipeline[pipeline/ - Pipeline]
        Diag[diag/ - Diagnostics]
    end
    
    subgraph FFIAnalysis[Cross-Language Analysis]
        FFIMod[ffi/ - FFI Matching]
        Registry[registry/ - Semantic Registry]
        Lifetime[lifetime/ - Lifetime Engine]
    end
    
    subgraph OutputMod[Output & Reporting]
        Output[output/ - Result Formatting]
        Report[report/ - Report Generation]
    end
    
    subgraph TrackMod[Tracking]
        Tracking[tracking/ - Memory Tracking]
    end
    
    IR --> Pass
    IR --> FFIMod
    Engine --> Pass
    Engine --> FFIMod
    
    Fact --> Pass
    Fact --> FFIMod
    Fact --> Diag
    Fact --> DataFlow
    
    DataFlow --> Pass
    
    Pass --> Pipeline
    Pass --> Diag
    
    FFIMod --> Registry
    Registry --> Lifetime
    
    Lifetime --> Pass
    
    Pipeline --> Output
    Diag --> Output
    Diag --> Report
    
    Tracking --> Pass
```

## Data Flow

```mermaid
sequenceDiagram
    participant User
    participant CLI as main.zig
    participant Loader as IRLoader
    participant Pass as PassManager
    participant Fact as FactStore
    participant Registry as SemanticRegistry
    participant Lifetime as LifetimeEngine
    participant Diag as DiagnosticAggregator
    participant Output as Formatter
    
    User->>CLI: Input file(s)
    CLI->>Loader: Load IR (.bc/.ll)
    Loader-->>CLI: Module loaded
    
    CLI->>Pass: Run analysis pipeline
    
    Pass->>Fact: Store call graph facts
    Pass->>Fact: Store pointer flow facts
    Pass->>Registry: Lookup function semantics
    Registry-->>Pass: Function metadata
    
    Pass->>Lifetime: Track ownership
    Lifetime->>Fact: Store ownership facts
    
    Pass->>Diag: Report findings
    Diag->>Output: Format results
    Output-->>CLI: Formatted output
    CLI-->>User: Analysis results
```

## Component Responsibilities

### User Interface Layer
- **main.zig**: CLI entry point, argument parsing, analysis orchestration

### Engine Layer
- **engine/loader.zig**: IR file loading, LLVM context management
- **ir/**: LLVM C API wrappers (raw, safe, view, debug_info, location)

### Analysis Core
- **pass/manager.zig**: Pass registration and execution
- **pass/pass.zig**: Pass context and interfaces
- **pass/foundation/**: Foundation passes (cfg, dfg)
- **pass/analysis/**: Analysis passes
  - call_graph.zig: Function call graph construction
  - taint_propagation.zig: Pointer flow analysis
  - ffi_boundary.zig: FFI boundary detection
  - pointer_ownership.zig: Pointer ownership tracking
  - ffi_analysis.zig: Ownership violation detection
  - flow_path.zig: Data flow path construction
  - issue/: Issue-specific passes (ffi_unsafe, free_validation, memory_safety, etc.)
- **pass/instrumentation/**: Instrumentation planning

### Data Flow
- **dataflow/graph.zig**: Data flow graph construction
- **dataflow/node.zig**: Node representation
- **dataflow/edge.zig**: Edge representation

### Fact System
- **fact/store.zig**: Fact storage and indexing
- **fact/query.zig**: Fact querying engine
- **fact/fact.zig**: Fact type definitions
- **fact/ownership_fact.zig**: Ownership-specific facts

### Semantic Registry
- **registry/semantic_registry.zig**: Function semantic knowledge base
- **registry/config_loader.zig**: Dynamic registry from JSON config

### Lifetime Engine
- **lifetime/engine.zig**: Resource lifetime tracking
- **lifetime/mapper.zig**: Semantic action mapping

### Cross-Language Analysis
- **ffi/ffi_matcher.zig**: Multi-language function matching

### Output System
- **output/formatter.zig**: Result formatting
- **output/cli.zig**: CLI output
- **output/sarif.zig**: SARIF format output
- **output/lsp.zig**: LSP integration

### Reporting
- **report/sarif.zig**: SARIF report generation
- **report/ci_integration.zig**: CI/CD integration

### Diagnostics
- **diag/aggregator.zig**: Diagnostic collection and reporting
- **diag/issue.zig**: Issue type definitions

### Tracking
- **tracking/allocator.zig**: Memory allocation tracking

## Key Design Principles

1. **Separation of Concerns**: Each layer has distinct responsibilities
2. **Data-Driven Analysis**: Semantic registry provides function knowledge
3. **Ownership Focus**: Core analysis tracks pointer ownership, not generic taint
4. **Cross-Language**: Support for multi-language FFI analysis
5. **Modularity**: Components can be used independently or together

## Analysis Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                     Analysis Pipeline                            │
├─────────────────────────────────────────────────────────────────┤
│  1. IR Loading                                                   │
│     └── Parse LLVM IR, build module representation               │
│                                                                  │
│  2. Call Graph Construction                                      │
│     └── Build function call relationships                        │
│                                                                  │
│  3. Pointer Flow Analysis                                        │
│     └── Track pointer values through def-use chains              │
│                                                                  │
│  4. FFI Boundary Detection                                       │
│     └── Identify cross-language function calls                   │
│                                                                  │
│  5. Ownership Tracking                                           │
│     └── Track allocation/free sites and ownership state          │
│                                                                  │
│  6. Violation Detection                                          │
│     └── Detect cross-language ownership mismatches               │
│                                                                  │
│  7. Report Generation                                            │
│     └── Format and output findings                               │
└─────────────────────────────────────────────────────────────────┘
```

## Supported Languages

| Language | Detection | Ownership Tracking | Debug Info |
|----------|-----------|-------------------|------------|
| C | ✅ Full | ✅ Full | ✅ Full |
| C++ | ✅ Full | ✅ Full | ✅ Full |
| Rust | ✅ Full | ✅ Full | ✅ Full |
| Zig | ⚠️ Beta | ⚠️ Beta | ✅ Full |
| Swift | ⚠️ Beta | ⚠️ Beta | ✅ Full |
| Go | ⚠️ Experimental | ⚠️ Experimental | ✅ Full |

## Issue Detection Categories

| Category | Types | Severity |
|----------|-------|----------|
| **Ownership** | Cross-language free mismatch, Double free, Use after free | Critical |
| **Memory** | Leak, Buffer overflow, Dangling pointer | High |
| **Security** | Command injection, Format string, Buffer overflow | Critical |
| **Concurrency** | Data race, Lock order violation | High |
