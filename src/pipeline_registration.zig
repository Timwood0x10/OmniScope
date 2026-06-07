//! Pipeline Pass Registration
//!
//! Centralized registration of all analysis passes for the OmniScope pipeline.
//! Separated from pipeline.zig to keep pass registration manageable.

const OmniScope = @import("OmniScope");
const Pipeline = OmniScope.pipeline.Pipeline;

/// Register all passes in the pipeline.
pub fn registerAllPasses(pipeline: *Pipeline) !void {
    try pipeline.registerPass(OmniScope.cross_lang.CFGPass);
    try pipeline.registerPass(OmniScope.cross_lang.DFGPass);
    try pipeline.registerPass(OmniScope.cross_lang.AliasPass);
    try pipeline.registerPass(OmniScope.cross_lang.SurfaceClassifierPass);
    try pipeline.registerPass(OmniScope.cross_lang.SemanticResolverPass);
    try pipeline.registerPass(OmniScope.cross_lang.MallocCheckPass);
    try pipeline.registerPass(OmniScope.cross_lang.BufferOverflowPass);
    try pipeline.registerPass(OmniScope.cross_lang.IntegerOverflowPass);
    try pipeline.registerPass(OmniScope.cross_lang.CallGraphPass);
    try pipeline.registerPass(OmniScope.cross_lang.TaintPropagationPass);
    try pipeline.registerPass(OmniScope.cross_lang.FFIDetectorPass);
    try pipeline.registerPass(OmniScope.cross_lang.FFIBoundaryPass);
    try pipeline.registerPass(OmniScope.cross_lang.FFITypeMismatchPass);
    try pipeline.registerPass(OmniScope.cross_lang.AbiCompatChecker);
    try pipeline.registerPass(OmniScope.cross_lang.FFIBodyCheckPass);
    try pipeline.registerPass(OmniScope.cross_lang.JniLeakDetectorPass);
    try pipeline.registerPass(OmniScope.cross_lang.FFIAnalysisPassWrapper);
    try pipeline.registerPass(OmniScope.cross_lang.FFIUnsafePass);
    try pipeline.registerPass(OmniScope.cross_lang.PtrLifetimePass);
    try pipeline.registerPass(OmniScope.cross_lang.DangerSurfacePass);
    try pipeline.registerPass(OmniScope.cross_lang.PointerOwnershipPass);
    try pipeline.registerPass(OmniScope.cross_lang.CallbackEscapePass);
    try pipeline.registerPass(OmniScope.cross_lang.CallbackLifecycleChecker);
    try pipeline.registerPass(OmniScope.cross_lang.RustFfiAuditor);
    try pipeline.registerPass(OmniScope.cross_lang.CrossLangDataFlowPass);
    try pipeline.registerPass(OmniScope.cross_lang.ReturnCheckPass);
    try pipeline.registerPass(OmniScope.cross_lang.MemorySafetyPass);
    try pipeline.registerPass(OmniScope.cross_lang.FreeValidationPass);
    try pipeline.registerPass(OmniScope.cross_lang.GcSafetyPass);
    try pipeline.registerPass(OmniScope.cross_lang.ErrorPropagationTracer);
    try pipeline.registerPass(OmniScope.cross_lang.LockPass);
    // Phase 5: New FFI detectors
    try pipeline.registerPass(OmniScope.cross_lang.LayoutMismatchPass);
    try pipeline.registerPass(OmniScope.cross_lang.StringSafetyPass);
    try pipeline.registerPass(OmniScope.cross_lang.UnwindBoundaryPass);
}
