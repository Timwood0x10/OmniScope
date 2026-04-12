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
