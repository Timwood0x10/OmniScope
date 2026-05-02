# OmniScope Architecture &amp; Data Flow

## 1. System Architecture

```mermaid
graph TB
    subgraph Input
        IR["LLVM IR .ll / .bc files"]
        CFG["config/*.json zone rules"]
    end

    subgraph Engine
        Loader["engine/loader.zig IRLoader"]
        View["ir/view.zig ModuleRef"]
    end

    subgraph Pipeline
        PL["pipeline/pipeline.zig"]
        PC["pass/pass.zig PassContext"]
    end

    subgraph PreScan
        LD["language_detector.zig"]
        ZC["zone_classifier.zig"]
        RC["registry_cache HashMap"]
        ZCache["zone_cache HashMap"]
    end

    subgraph PassManager
        PM["pass/manager.zig Topological Sort"]
    end

    subgraph Phase1
        CG["call-graph"]
        FB["ffi-boundary Zone-First Gate"]
        PLT["ptr-lifetime"]
        CE["callback-escape"]
        RC2["return-check"]
        MS["memory-safety"]
        FV["free-validation"]
        FTM["ffi-type-mismatch"]
    end

    subgraph Phase2
        PO["pointer-ownership"]
        FU["ffi-unsafe"]
        FBC["ffi-body-check"]
    end

    subgraph Semantics
        ZC2["zone_classifier"]
        LD2["language_detector"]
        NF["noise_filter"]
        MG["memory_graph"]
    end

    subgraph Registry
        SR["semantic_registry 6 layers"]
        CL["config_loader JSON HashMap"]
        HK["hooks 3 semantic hooks"]
    end

    subgraph DataFlow
        DFG["DataFlowGraph"]
    end

    subgraph FactSystem
        FS["FactStore"]
        QE["QueryEngine"]
    end

    subgraph Output
        AGG["diag/aggregator.zig"]
        CLI["output/cli.zig"]
        JSON2["output/formatter.zig"]
        SARIF["output/sarif.zig"]
        LSP["output/lsp.zig"]
    end

    IR --> Loader --> View --> PL
    CFG --> CL --> SR
    PL --> PC
    PL --> PM
    PM --> Phase1 --> Phase2
    PC --> PreScan
    Phase1 --> FS
    Phase2 --> QE
    QE --> FS
    Phase1 --> DFG
    Phase2 --> DFG
    Phase1 --> AGG --> CLI
    AGG --> JSON2
    AGG --> SARIF
    AGG --> LSP
    Phase1 -.-> Semantics
    Phase1 -.-> Registry
    Phase1 -.-> DataFlow
    Phase1 -.-> FactSystem
```

## 2. Data Flow

```mermaid
flowchart TD
    START([".ll file"]) --> LOAD["IRLoader.load"]
    LOAD --> MODULE["ModuleRef"]
    MODULE --> PIPELINE["Pipeline.run"]
    PIPELINE --> INIT["Init PassContext"]
    INIT --> LANG["detectModuleLanguage"]
    LANG --> PC_LANG["PassContext.module_language"]
    PIPELINE --> PASSES["PassManager.run"]
    PASSES --> FUNC["LLVM Function"]
    FUNC --> ZONECHECK["getOrComputeZone"]
    ZONECHECK --> ZONEGATE{"zone safe or runtime?"}
    ZONEGATE -->|Yes| SKIP1["SKIP"]
    ZONEGATE -->|No| CHANNEL{"channelMode?"}
    CHANNEL -->|skip| SKIP2["SKIP"]
    CHANNEL -->|full| ANALYZE["Run Analysis"]
    ANALYZE --> REGLOOKUP["cachedRegistryLookup"]
    REGLOOKUP --> SEM["FunctionSemantics"]
    SEM --> DETECT["Issue Detection"]
    DETECT --> ISSUE["Issue"]
    ISSUE --> DEDUP{"dedup?"}
    DEDUP -->|Yes| NOREPORT["Skip"]
    DEDUP -->|No| REPORT["addIssue"]
    REPORT --> AGG2["Aggregator"]
    AGG2 --> CLIOUT["CLI"]
    AGG2 --> JSONOUT["JSON"]
    AGG2 --> SARIFOUT["SARIF"]
```

## 3. Zone-First + Language-First Channel Matrix

```mermaid
flowchart TD
    LANGIN["Language Detection"] --> LANGOUT["C / Rust / Go / Zig / Unknown"]
    ZONEIN["Zone Classification"] --> ZONEOUT["safe / runtime / ffi / unsafe / unknown"]
    LANGOUT --> GATE{"Two-Dimensional Gate"}
    ZONEOUT --> GATE
    GATE --> SKIP3["SKIP safe + runtime"]
    GATE --> FULL["FULL ffi + unsafe"]
    GATE --> LIMITED["LIMITED unknown x0.6"]
    FULL --> CC["C: format const + realloc + real escape"]
    FULL --> RR["Rust: into_raw/from_raw + unsafe block"]
    FULL --> GG["Go: cgo KeepAlive + pointer retain"]
    FULL --> ZZ["Zig: cImport boundary"]
    FULL --> UU["Unknown: generic FFI"]
```

## 4. Registry and Hook System

```mermaid
flowchart TB
    Q1["cachedRegistryLookup"] --> Q2{"cache hit?"}
    Q2 -->|Yes| Q5["return FunctionSemantics"]
    Q2 -->|No| Q3["SemanticRegistry.lookup"]
    Q3 --> L1["Layer 1 Exact Match"]
    L1 --> L2["Layer 2 Suffix Match"]
    L2 --> L3["Layer 3 Contains Match"]
    L3 --> L4["Layer 4 Risk Category"]
    L4 --> L5["Layer 5 Language-Specific"]
    L5 --> L6["Layer 6 Dynamic JSON"]
    L6 --> Q4["cache result"]
    Q4 --> Q5
    H1["rustOwnershipHook"] -.-> Q3
    H2["goEscapeHook"] -.-> Q3
    H3["pythonRefcountHook"] -.-> Q3
```

## 5. Noise Reduction Pipeline

```mermaid
flowchart TD
    FN["Function"] --> L1{"L1 Name Filter"}
    L1 -->|compiler| S1["SKIP"]
    L1 -->|user| L2{"L2 Path Filter"}
    L2 -->|test vendor| S2["SKIP"]
    L2 -->|source| L3{"L3 Behavior Filter"}
    L3 -->|trivial| S3["SKIP"]
    L3 -->|real| ZG{"Zone Gate"}
    ZG -->|safe runtime| S4["SKIP"]
    ZG -->|ffi unsafe| A1["Full Analysis"]
    ZG -->|unknown| LIM["Limited x0.6"]
```

## 6. Module Dependency Graph

```mermaid
graph LR
    A["ir/llvm_raw.zig"] --> B["ir/llvm_safe.zig"]
    B --> C["ir/view.zig"]
    D["ir/debug_info.zig"] --> C
    E["common/types.zig"] --> F["diag/issue.zig"]
    E --> G["pass/pass.zig"]
    G --> H["pass/manager.zig"]
    G --> I["semantics/zone_classifier.zig"]
    G --> J["semantics/language_detector.zig"]
    G --> K["registry/semantic_registry.zig"]
    I --> L["semantics/noise_filter.zig"]
    K --> M["registry/config_loader.zig"]
    K --> N["registry/hooks.zig"]
    O["dataflow/graph.zig"] --> P["dataflow/node.zig"]
    P --> Q["dataflow/edge.zig"]
    R["fact/store.zig"] --> S["fact/query.zig"]
    G --> R
    G --> O
    C --> G
```
