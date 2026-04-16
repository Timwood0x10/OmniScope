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
        PassManager --> Instr[InstrumentationStage<br/>pipeline/instrumentation_stage.zig]
        
        Static --> CallGraph[CallGraphPass]
        Static --> Taint[TaintPropagationPass]
        Static --> FFI[FFIBoundaryPass]
        Static --> Sink[SinkTracerPass]
        
        Taint --> FactStore[FactStore<br/>fact/store.zig]
        FFI --> FactStore
        CallGraph --> FactStore
        Sink --> FactStore
        
        FactStore --> QueryEngine[QueryEngine<br/>fact/query.zig]
        
        QueryEngine --> Diag[DiagnosticAggregator<br/>diag/aggregator.zig]
    end
    
    subgraph "Cross-Language Analysis"
        FFI --> FFIMatcher[FFIMatcher<br/>ffi/ffi_matcher.zig]
        FFIMatcher --> FFIDetector[FFIDetector<br/>pass/analysis/ffi_detector.zig]
        FFIDetector --> Vulns[Vulnerability Detection]
    end
    
    Diag --> Output[Output Formatter<br/>output/formatter.zig]
    Vulns --> Output
    
    Output --> Formats[Output Formats]
    Formats --> Text[Text]
    Formats --> JSON[JSON]
    Formats --> SARIF[SARIF]
    
    subgraph "Optional Runtime Analysis"
        Instr --> RuntimeStage[RuntimeStage<br/>pipeline/runtime_stage.zig]
        RuntimeStage --> RingBuffer[Ring Buffer<br/>runtime/rt_lib/ring_buffer.zig]
        RingBuffer --> Collector[Event Collector<br/>runtime/collector.zig]
        Collector --> MergeEngine[MergeEngine<br/>runtime/merge.zig]
        MergeEngine --> Diag
    end
    
    subgraph "Plugin System"
        CLI --> Plugins[PluginLoader<br/>plugin/abi.zig]
        Plugins --> FactStore
        Plugins --> Diag
    end
    
    Text --> Results[Analysis Results]
    JSON --> Results
    SARIF --> Results
    Results --> User
```

## Module Dependencies

```mermaid
graph LR
    subgraph "Core Infrastructure"
        IR[ir/ - LLVM IR Wrappers]
        Engine[engine/ - IR Loading]
        Fact[fact/ - Fact Storage]
    end
    
    subgraph "Analysis Framework"
        Pass[pass/ - Analysis Passes]
        Pipeline[pipeline/ - Pipeline Stages]
        Diag[diag/ - Diagnostics]
    end
    
    subgraph "Cross-Language Analysis"
        FFI[ffi/ - FFI Matching]
        Cross[cross_lang - FFI Detection]
    end
    
    subgraph "Output & Runtime"
        Output[output/ - Result Formatting]
        Runtime[runtime/ - Runtime Data]
    end
    
    subgraph "Extensions"
        Plugin[plugin/ - Plugin System]
        Tracking[tracking/ - Memory Tracking]
    end
    
    IR --> Pass
    IR --> FFI
    Engine --> Pass
    Engine --> FFI
    
    Fact --> Pass
    Fact --> FFI
    Fact --> Cross
    Fact --> Diag
    
    Pass --> Pipeline
    Pass --> Diag
    Pass --> Cross
    
    FFI --> Cross
    Cross --> Diag
    
    Pipeline --> Runtime
    Pipeline --> Output
    
    Diag --> Output
    
    Runtime --> Fact
    Runtime --> Diag
    
    Plugin --> Fact
    Plugin --> Diag
```

## Data Flow

```mermaid
sequenceDiagram
    participant User
    participant CLI as main.zig
    participant Loader as IRLoader
    participant Pass as PassManager
    participant Fact as FactStore
    participant Diag as DiagnosticAggregator
    participant Output as Formatter
    
    User->>CLI: Input file(s)
    CLI->>Loader: Load IR (.bc/.ll)
    Loader-->>CLI: Module loaded
    
    alt Single File Mode
        CLI->>Loader: Direct analysis
        Loader->>Pass: Run basic analysis
    else Multi-File Mode
        CLI->>FFIMatcher: Match FFI functions
        FFIMatcher->>Pass: Analyze cross-language
    end
    
    Pass->>Fact: Store analysis facts
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
- **ir/**: LLVM C API wrappers (raw, safe, view)

### Analysis Core
- **pass/manager.zig**: Pass registration and execution
- **pass/pass.zig**: Pass context and interfaces
- **pass/analysis/**: Specific analysis passes
  - call_graph.zig: Function call graph
  - taint_propagation.zig: Data flow analysis
  - ffi_boundary.zig: FFI boundary detection
  - sink_tracer.zig: Vulnerability sink tracing
  - ffi_detector.zig: FFI vulnerability detection

### Fact System
- **fact/store.zig**: Fact storage and indexing
- **fact/query.zig**: Fact querying engine
- **fact/fact.zig**: Fact type definitions

### Pipeline System
- **pipeline/pipeline.zig**: Main analysis coordinator
- **pipeline/static_stage.zig**: Static analysis stage
- **pipeline/instrumentation_stage.zig**: IR instrumentation
- **pipeline/runtime_stage.zig**: Runtime data collection
- **pipeline/merge_stage.zig**: Static/runtime data merge

### Cross-Language Analysis
- **ffi/ffi_matcher.zig**: Multi-language function matching
- **cross_lang/**: Cross-language vulnerability detection

### Output System
- **output/formatter.zig**: Result formatting (text/JSON/SARIF)

### Runtime Support
- **runtime/collector.zig**: Event collection
- **runtime/merge.zig**: Static/runtime data merge
- **runtime/rt_lib/**: Runtime library for instrumentation

### Extensions
- **plugin/abi.zig**: Plugin loading and ABI
- **tracking/**: Memory tracking utilities
- **diag/aggregator.zig**: Diagnostic collection and reporting

## Key Design Principles

1. **Separation of Concerns**: Each layer has distinct responsibilities
2. **Extensibility**: Plugin system allows custom analysis passes
3. **Performance**: Efficient fact storage and querying
4. **Cross-Language**: Support for multi-language FFI analysis
5. **Modularity**: Components can be used independently or together