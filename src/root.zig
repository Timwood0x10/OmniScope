//! OmniScope library root
//!
//! This is the public API entry point for the OmniScope library.

// Export IR layer
pub const ir = struct {
    pub const llvm_c = @import("ir/llvm_c.zig");
    pub const view = @import("ir/view.zig");
    pub const location = @import("ir/location.zig");
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
};

// Export engine
pub const engine = struct {
    pub const IRLoader = @import("engine/loader.zig").IRLoader;
    pub const LoaderError = @import("engine/loader.zig").LoaderError;
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
