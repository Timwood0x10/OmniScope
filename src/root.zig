//! OmniScope library root
//!
//! This is the public API entry point for the OmniScope library.

// Export logging system
pub const log = struct {
    pub const LogLevel = @import("log/log.zig").LogLevel;
    pub const LogConfig = @import("log/log.zig").Config;
    pub const init = @import("log/log.zig").init;
    pub const deinit = @import("log/log.zig").deinit;
    pub const debug = @import("log/log.zig").debug;
    pub const info = @import("log/log.zig").info;
    pub const warn = @import("log/log.zig").warn;
    pub const err = @import("log/log.zig").err;
    pub const setLevel = @import("log/log.zig").setLevel;
    pub const getLevel = @import("log/log.zig").getLevel;
    pub const DebugConfig = @import("log/debug.zig").Config;
    pub const debug_init = @import("log/debug.zig").init;
    pub const debug_deinit = @import("log/debug.zig").deinit;
    pub const assert = @import("log/debug.zig").assert;
    pub const panicWithContext = @import("log/debug.zig").panicWithContext;
    pub const notImplemented = @import("log/debug.zig").notImplemented;
    pub const todo = @import("log/debug.zig").todo;
};

// Export error types
pub const errors = struct {
    pub const Error = @import("log/error.zig").Error;
    pub const IRLoadError = @import("log/error.zig").IRLoadError;
    pub const IRViewError = @import("log/error.zig").IRViewError;
    pub const PassError = @import("log/error.zig").PassError;
    pub const AnalysisError = @import("log/error.zig").AnalysisError;
    pub const InstrumentationError = @import("log/error.zig").InstrumentationError;
    pub const RuntimeError = @import("log/error.zig").RuntimeError;
    pub const ConfigError = @import("log/error.zig").ConfigError;
};

// Export IR layer
pub const ir = struct {
    pub const llvm_c = @import("ir/llvm_c.zig");
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
};

// Simple test to verify test system works
test "root.zig - module import test" {
    // Verify that all modules can be imported
    _ = ir.llvm_c;
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
