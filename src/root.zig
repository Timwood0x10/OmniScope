//! OmniScope library root
//!
//! This is the public API entry point for the OmniScope library.

// Export IR layer
pub const ir = struct {
    pub const llvm_raw = @import("ir/llvm_raw.zig");
    pub const llvm_safe = @import("ir/llvm_safe.zig");
    pub const view = @import("ir/view.zig");
    pub const location = @import("ir/location.zig");
    pub const debug_info = @import("ir/debug_info.zig");
};

// Export pass system
pub const pass = struct {
    pub const Pass = @import("pass/pass.zig").Pass;
    pub const PassContext = @import("pass/pass.zig").PassContext;
    pub const DiagnosticWriter = @import("pass/pass.zig").DiagnosticWriter;
    pub const PassKind = @import("pass/pass.zig").PassKind;
    pub const PassManager = @import("pass/manager.zig").PassManager;
};

// Export fact system
pub const fact = struct {
    pub const Fact = @import("fact/fact.zig").Fact;
    pub const FactKind = @import("fact/fact.zig").FactKind;
    pub const FactStore = @import("fact/store.zig").FactStore;
    pub const QueryEngine = @import("fact/query.zig").QueryEngine;
};

// Export diag system
pub const diag = struct {
    pub const Issue = @import("diag/issue.zig").Issue;
    pub const IssueKind = @import("diag/issue.zig").IssueKind;
    pub const Severity = @import("diag/issue.zig").Severity;
    pub const Location = @import("diag/issue.zig").Location;
    pub const FFIBoundary = @import("diag/issue.zig").FFIBoundary;
};

// Export dataflow system
pub const dataflow = struct {
    pub const DataFlowGraph = @import("dataflow/graph.zig").DataFlowGraph;
    pub const DataNode = @import("dataflow/node.zig").DataNode;
    pub const DataEdge = @import("dataflow/edge.zig").DataEdge;
    pub const ValueType = @import("dataflow/node.zig").ValueType;
    pub const EdgeType = @import("dataflow/edge.zig").EdgeType;
};

// Export tracking utilities
pub const tracking = @import("tracking/mod.zig");

// Export pipeline system
pub const pipeline = struct {
    pub const Pipeline = @import("pipeline/pipeline.zig").Pipeline;
    pub const PipelineResult = @import("pipeline/pipeline.zig").PipelineResult;
};

// Export engine
pub const engine = struct {
    pub const IRLoader = @import("engine/loader.zig").IRLoader;
    pub const LoaderError = @import("engine/loader.zig").LoaderError;
};

// Export cross-language analysis
pub const cross_lang = struct {
    pub const FunctionKind = @import("pass/analysis/call_graph.zig").FunctionKind;
    pub const Node = @import("pass/analysis/call_graph.zig").Node;
    pub const Edge = @import("pass/analysis/call_graph.zig").Edge;
    pub const LIBC_FUNCTIONS = @import("pass/analysis/call_graph.zig").LIBC_FUNCTIONS;
    pub const SOURCE_FUNCTIONS = @import("pass/analysis/call_graph.zig").SOURCE_FUNCTIONS;
    pub const SINK_PATTERNS = @import("pass/analysis/call_graph.zig").SINK_PATTERNS;
    pub const CallGraphPass = @import("pass/analysis/call_graph.zig").CallGraphPass;
    pub const TaintPropagationPass = @import("pass/analysis/taint_propagation.zig").TaintPropagationPass;
    pub const FFIBoundaryPass = @import("pass/analysis/ffi_boundary.zig").FFIBoundaryPass;
    pub const PointerOwnershipPass = @import("pass/analysis/pointer_ownership.zig").PointerOwnershipPass;
    pub const OwnershipError = @import("pass/analysis/pointer_ownership.zig").OwnershipError;
    pub const TaintError = @import("pass/analysis/taint_propagation.zig").TaintError;
    pub const FFIBoundaryError = @import("pass/analysis/ffi_boundary.zig").FFIBoundaryError;

    pub const TaintState = @import("pass/analysis/taint_state.zig").TaintState;
    pub const TaintInfo = @import("pass/analysis/taint_state.zig").TaintInfo;
    pub const TaintContext = @import("pass/analysis/taint_state.zig").TaintContext;

    pub const FFIDetector = @import("pass/analysis/ffi_detector.zig").FFIDetector;
    pub const getCWEID = @import("pass/analysis/ffi_detector.zig").getCWEID;
    pub const FFIVulnerability = @import("pass/analysis/ffi_detector.zig").FFIVulnerability;
    pub const FFIVulnerabilityType = @import("pass/analysis/ffi_detector.zig").FFIVulnerabilityType;
    pub const FFISeverity = @import("pass/analysis/ffi_detector.zig").FFISeverity;

    pub const FFIMatcher = @import("ffi/ffi_matcher.zig").FFIMatcher;
    pub const FunctionInfo = @import("ffi/ffi_matcher.zig").FunctionInfo;
    pub const FFIMatch = @import("ffi/ffi_matcher.zig").FFIMatch;
    pub const FFIMatcherError = @import("ffi/ffi_matcher.zig").FFIMatcherError;
    pub const FFIFunctionKind = @import("ffi/ffi_matcher.zig").FunctionKind;

    pub const FFIKind = @import("pass/analysis/ffi_info.zig").FFIKind;
    pub const FFIBoundaryInfo = @import("pass/analysis/ffi_info.zig").FFIBoundaryInfo;
    pub const FFIBoundaryDetector = @import("pass/analysis/ffi_info.zig").FFIBoundaryDetector;

    pub const RiskLevel = @import("pass/analysis/flow_path.zig").RiskLevel;
    pub const FlowStep = @import("pass/analysis/flow_path.zig").FlowStep;
    pub const FlowPath = @import("pass/analysis/flow_path.zig").FlowPath;
    pub const VulnerabilityReport = @import("pass/analysis/flow_path.zig").VulnerabilityReport;

    pub const classifyRiskLevel = @import("pass/analysis/flow_path.zig").classifyRiskLevel;
    pub const isDangerousSink = @import("registry/semantic_registry.zig").SemanticRegistry.isDangerousSink;

    pub const FFIUnsafePass = @import("pass/analysis/issue/ffi_unsafe.zig").FFIUnsafePass;
    pub const FFIAnalysisPass = @import("pass/analysis/ffi_analysis.zig").FFIAnalysisPass;
    pub const FFIAnalysisResult = @import("pass/analysis/ffi_analysis.zig").FFIAnalysisResult;
    pub const FFIAnalysisVulnerability = @import("pass/analysis/ffi_analysis.zig").FFIAnalysisVulnerability;
    pub const FFIAnalysisError = @import("pass/analysis/ffi_analysis.zig").FFIAnalysisError;
};

// Export registry system
pub const registry = struct {
    pub const SemanticRegistry = @import("registry/semantic_registry.zig").SemanticRegistry;
    pub const RiskKind = @import("registry/semantic_registry.zig").RiskKind;
    pub const Severity = @import("registry/semantic_registry.zig").Severity;
    pub const FunctionSemantics = @import("registry/semantic_registry.zig").FunctionSemantics;
    pub const MatchType = @import("registry/semantic_registry.zig").MatchType;
    pub const DynamicRegistry = @import("registry/config_loader.zig").DynamicRegistry;
    pub const ConfigError = @import("registry/config_loader.zig").ConfigError;
};

// Export lifetime engine
pub const lifetime = struct {
    pub const Owner = @import("lifetime/engine.zig").Owner;
    pub const LifetimeState = @import("lifetime/engine.zig").LifetimeState;
    pub const SemanticAction = @import("lifetime/engine.zig").SemanticAction;
    pub const ResourceFact = @import("lifetime/engine.zig").ResourceFact;
    pub const IssueType = @import("lifetime/engine.zig").IssueType;
    pub const Issue = @import("lifetime/engine.zig").Issue;
    pub const LifetimeEngine = @import("lifetime/engine.zig").LifetimeEngine;
    pub const EngineStats = @import("lifetime/engine.zig").EngineStats;
    pub const TransitionRule = @import("lifetime/engine.zig").TransitionRule;
    pub const TRANSITION_RULES = @import("lifetime/engine.zig").TRANSITION_RULES;
    pub const SemanticMapper = @import("lifetime/mapper.zig").SemanticMapper;
    pub const MappedAction = @import("lifetime/mapper.zig").MappedAction;
    pub const Rule = @import("lifetime/mapper.zig").Rule;
    pub const RULES = @import("lifetime/mapper.zig").RULES;
    pub const MatchType = @import("lifetime/mapper.zig").MatchType;
    pub const LanguageHint = @import("lifetime/engine.zig").LanguageHint;
    pub const SourceLocation = @import("lifetime/engine.zig").SourceLocation;
    pub const BoundaryAnalyzer = @import("lifetime/boundary.zig").BoundaryAnalyzer;
    pub const FFIBoundary = @import("lifetime/boundary.zig").FFIBoundary;
    pub const BoundaryViolation = @import("lifetime/boundary.zig").BoundaryViolation;
    pub const BoundaryIssue = @import("lifetime/boundary.zig").BoundaryIssue;
    pub const BoundaryDirection = @import("lifetime/boundary.zig").BoundaryDirection;
    pub const AnalyzerStats = @import("lifetime/boundary.zig").AnalyzerStats;
    pub const detectLanguage = @import("lifetime/boundary.zig").detectLanguage;
};

// Export output system
pub const output = struct {
    pub const Formatter = @import("output/formatter.zig").Formatter;
    pub const OutputFormat = @import("output/formatter.zig").OutputFormat;
    pub const AnalysisResult = @import("output/formatter.zig").AnalysisResult;
    pub const Vulnerability = @import("output/formatter.zig").Vulnerability;
};

// Simple test to verify test system works
test "root.zig - module import test" {
    // Verify that all modules can be imported
    _ = ir.llvm_raw;
    _ = ir.llvm_safe;
    _ = ir.view;
    _ = ir.location;
    _ = pass.Pass;
    _ = pass.PassContext;
    _ = pass.DiagnosticWriter;
    _ = pass.PassKind;
    _ = pass.PassManager;
    _ = fact.Fact;
    _ = fact.FactKind;
    _ = fact.FactStore;
    _ = fact.QueryEngine;
    _ = pipeline.Pipeline;
    _ = pipeline.PipelineResult;
    _ = engine.IRLoader;
    _ = engine.LoaderError;
}
