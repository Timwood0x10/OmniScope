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

// Export tracking utilities
pub const tracking = @import("tracking/mod.zig");

// Export pipeline system
pub const pipeline = struct {
    pub const Stage = @import("pipeline/stage.zig").Stage;
    pub const StageContext = @import("pipeline/stage.zig").StageContext;
    pub const StageResult = @import("pipeline/stage.zig").StageResult;
    pub const StageKind = @import("pipeline/stage.zig").StageKind;
    pub const StaticStage = @import("pipeline/static_stage.zig").StaticStage;
    pub const InstrumentationStage = @import("pipeline/instrumentation_stage.zig").InstrumentationStage;
    pub const RuntimeStage = @import("pipeline/runtime_stage.zig").RuntimeStage;
    pub const MergeStage = @import("pipeline/merge_stage.zig").MergeStage;
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
    pub const SinkTracerPass = @import("pass/analysis/sink_tracer.zig").SinkTracerPass;
    pub const TaintError = @import("pass/analysis/taint_propagation.zig").TaintError;
    pub const FFIBoundaryError = @import("pass/analysis/ffi_boundary.zig").FFIBoundaryError;
    pub const FlowPathError = @import("pass/analysis/sink_tracer.zig").FlowPathError;

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

    pub const classifyRiskLevel = @import("pass/analysis/sink_tracer.zig").classifyRiskLevel;
    pub const isDangerousSink = @import("pass/analysis/sink_tracer.zig").isDangerousSink;
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
    _ = pipeline.Stage;
    _ = pipeline.StageContext;
    _ = pipeline.StageResult;
    _ = pipeline.StageKind;
    _ = pipeline.StaticStage;
    _ = pipeline.InstrumentationStage;
    _ = pipeline.RuntimeStage;
    _ = pipeline.MergeStage;
    _ = engine.IRLoader;
    _ = engine.LoaderError;
}
