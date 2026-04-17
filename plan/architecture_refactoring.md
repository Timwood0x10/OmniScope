# OmniScope Architecture Refactoring Plan

## Date: 2026-04-16

## Overview
This document outlines the architectural refactoring needed to unify the taint systems and standardize Pass interfaces according to the coding standards in `./plan/rules.md`.

## Issues Identified

### 1. Dual Taint Systems Coexistence

#### Current State
Two separate taint tracking systems exist in the codebase:

**v3 Function-Level System (TaintGraph)**
- Location: `src/pass/analysis/taint.zig`
- Storage: `std.AutoHashMap(u32, bool)` (simple boolean)
- Features:
  - Simple tainted/not-tainted state
  - Source tracking via `taint_sources: std.AutoHashMap(u32, std.ArrayList(u32))`
  - Propagation edges
  - Used primarily in `TaintPass`

**v4 Value-Level System (DataFlowGraph + TaintState)**
- Location: `src/dataflow/graph.zig`, `src/pass/analysis/taint_state.zig`
- Storage: `DataNode.is_tainted: bool` + `TaintContext`
- Features:
  - Fine-grained `TaintState` enum: none, source, tainted, safe
  - Confidence scoring (0.0 - 1.0)
  - Context-aware tracking
  - Used in `FlowStep`, `TaintPropagationPass`, `SinkTracerPass`

#### Problems
1. **Inconsistent APIs**: Different interfaces for similar functionality
2. **Feature Fragmentation**: Advanced features (confidence, state classification) only in v4
3. **Code Duplication**: Similar logic implemented twice
4. **Maintenance Burden**: Need to maintain both systems

#### Solution: Unified Taint Architecture

**Target**: Adopt v4 as the standard system with backward compatibility

**Benefits**:
- Fine-grained state classification (none/source/tainted/safe)
- Confidence scoring for uncertainty quantification
- Better support for flow path analysis
- Cleaner API with single source of truth

**Migration Path**:
1. Extend `DataFlowGraph` to support TaintGraph's source tracking
2. Update `TaintPass` to use v4 system
3. Keep TaintGraph as legacy adapter if needed
4. Remove v3 once migration is complete

### 2. Inconsistent Pass Interfaces

#### Current State

**Simple Passes** (No Resource Management)
```zig
pub const MallocCheckPass = struct {
    pub const name = "malloc-check";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};
    
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        // Implementation
    }
};
```

**Complex Passes** (Resource Management Required)
```zig
pub const CFGPass = struct {
    pub const name = "cfg";
    pub const kind = PassKind.foundation;
    pub const deps = &[_][]const u8{};
    
    bb_id_map: std.AutoHashMap(c.LLVMBasicBlockRef, u32),
    func_id: u32,
    
    pub fn init(allocator: std.mem.Allocator, store: *FactStore) CFGPass {
        // Initialize resources
    }
    
    pub fn deinit(self: *CFGPass, allocator: std.mem.Allocator) void {
        // Clean up resources
    }
    
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        // Implementation
    }
};
```

#### Problems
1. **PassManager Cannot Handle Both**: No mechanism to detect which pattern a Pass uses
2. **Manual Resource Management**: Developers must remember to call deinit
3. **Error-Prone**: Resource leaks if deinit is forgotten
4. **Testing Difficulty**: Different initialization patterns complicate testing

#### Solution: Unified Pass Trait

**New Pass Interface Specification**:
```zig
pub const PassTrait = struct {
    /// Pass name for identification (required)
    pub const name: []const u8 = "pass-name";
    
    /// Pass kind: foundation, analysis, or plugin (required)
    pub const kind: PassKind = PassKind.analysis;
    
    /// Dependency list (pass names this pass depends on) (required)
    pub const deps: []const []const u8 = &[_][]const u8{};
    
    /// Pass-specific context type (optional, defaults to void)
    pub const Context: type = void;
    
    /// Initialize pass context (optional, default is no-op)
    /// 
    /// Returns:
    ///   - Initialized context or error
    pub fn init(ctx: *PassContext) !Context {
        _ = ctx;
        return {};
    }
    
    /// Cleanup pass context (optional, default is no-op)
    pub fn deinit(context: *Context, ctx: *PassContext) void {
        _ = context;
        _ = ctx;
    }
    
    /// Main pass execution logic (required)
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter, context: *Context) !void;
};
```

**Implementation Strategy**:
1. Update `PassManager` to support automatic resource management
2. Refactor complex passes to use new interface
3. Simple passes can keep void Context (no changes needed)
4. Add compile-time validation for interface compliance

## Implementation Plan

### Phase 1: Infrastructure (Week 1)
1. Design unified Pass trait specification
2. Update `PassManager` to handle init/deinit lifecycle
3. Add compile-time validation utilities
4. Create migration guide for existing passes

### Phase 2: Taint System Unification (Week 2)
1. Extend `DataFlowGraph` with source tracking
2. Add confidence scoring to DataNode
3. Migrate `TaintPass` to v4 system
4. Update documentation and examples

### Phase 3: Pass Integration (Week 2-3)
1. Integrate foundation passes (CFG, DFG)
2. Integrate analysis passes (Alias, Taint, Lock)
3. Integrate cross-language passes
4. Update main.zig with proper dependency order

### Phase 4: Testing & Validation (Week 3-4)
1. Add integration tests for all passes
2. Verify 85%+ test coverage
3. Performance benchmarking
4. Documentation updates

## Coding Standards Compliance

All refactoring will follow `./plan/rules.md`:
- ✅ File size ≤ 1000 lines
- ✅ Code-to-comment ratio ≈ 7:3
- ✅ All comments in English
- ✅ Test coverage ≥ 85%
- ✅ Simple, concise API design
- ✅ Follow Zig official standards
- ✅ Use std.log instead of OmniScope.log.*
- ✅ Require LLVM 22

## Success Criteria

1. ✅ Single unified taint system
2. ✅ All passes follow same interface
3. ✅ Automatic resource management
4. ✅ All 17 passes integrated and tested
5. ✅ Zero resource leaks
6. ✅ 85%+ test coverage
7. ✅ No breaking changes to public API
8. ✅ Documentation updated

## Risk Mitigation

1. **Backward Compatibility**: Keep legacy code as deprecated adapters
2. **Performance**: Benchmark before/after to ensure no regression
3. **Test Coverage**: Add comprehensive tests before refactoring
4. **Incremental Migration**: Phase-by-phase rollout with validation

## Notes

- This is a significant refactoring that affects core architecture
- Need careful planning and testing to avoid breaking existing functionality
- Consider creating feature branch for this work
- Regular code reviews to ensure compliance with standards