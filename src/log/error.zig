//! Error System
//!
//! Provides a unified error hierarchy for OmniScope.
//! All modules define their own error sets following the architecture guidelines.

const std = @import("std");

pub const Error = error{
    OutOfMemory,
    FileNotFound,
    InvalidPath,
    PermissionDenied,
};

pub const IRLoadError = error{
    FileNotFound,
    InvalidIR,
    LLVMContextCreationFailed,
    ModuleParseFailed,
    BitcodeParseFailed,
};

pub const IRViewError = error{
    InvalidFunction,
    InvalidBasicBlock,
    InvalidInstruction,
    InvalidType,
    MetadataNotFound,
};

pub const PassError = error{
    DependencyFailed,
    PassNotFound,
    CircularDependency,
    PassExecutionFailed,
};

pub const AnalysisError = error{
    InvalidQuery,
    QueryFailed,
    AnalysisTimeout,
    InsufficientFacts,
};

pub const InstrumentationError = error{
    InvalidPlan,
    IRModificationFailed,
    InstrumentationFailed,
};

pub const RuntimeError = error{
    ProbeFailed,
    RingBufferFull,
    CollectorDisonnected,
    DecodeFailed,
};

pub const ConfigError = error{
    InvalidConfig,
    PluginNotFound,
    PluginInitFailed,
    PluginABIMismatch,
};

test "Error - error sets defined" {
    try std.testing.expectEqual(@as(u16, 4), @typeInfo(Error).ErrorSet.?.len);
}

test "Error - IRLoadError" {
    try std.testing.expectEqual(@as(u16, 5), @typeInfo(IRLoadError).ErrorSet.?.len);
}

test "Error - PassError" {
    try std.testing.expectEqual(@as(u16, 4), @typeInfo(PassError).ErrorSet.?.len);
}
