//! Event-driven Detector Interface for SemanticResolver
//!
//! This module defines the standard interface that all semantic detectors
//! must implement to participate in the unified single-pass traversal.
//!
//! ## Design Principles
//!
//! **Event-driven architecture**: Instead of each detector independently
//! traversing the entire function's basic blocks and instructions, detectors
//! now subscribe to specific instruction-level events. The UnifiedDetectorHub
//! performs a single traversal and dispatches events to all subscribed detectors.
//!
//! ## Interface Contract
//!
//! Each detector implements a subset of these event handlers:
//!   - Instruction-level: onCall, onBitcast, onLoad, onStore, onAlloca, onGEP, onRet
//!   - Function-level: onFunctionEnter, onFunctionExit
//!   - Module-level: onModuleEnter, onModuleComplete
//!
//! Detectors only implement the handlers they need; unneeded handlers are null.

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const log = @import("../common/log.zig");
const DiagnosticWriter = @import("../pass/pass.zig").DiagnosticWriter;
const SemanticTree = @import("./semantic_tree.zig").SemanticTree;
const FunctionIR = @import("../ir/ir_store.zig").FunctionIR;
const ModuleIRStore = @import("../ir/ir_store.zig").ModuleIRStore;

/// Shared context passed to all detectors during event processing.
///
/// Provides access to pre-computed data from IR Store and shared state
/// that detectors may need (e.g., SemanticTree for recording resolutions).
pub const DetectorContext = struct {
    /// LLVM module reference (for API calls not yet cached in IR Store).
    module: c.LLVMModuleRef,
    /// Current function being processed.
    func: c.LLVMValueRef,
    /// Pre-collected IR data for current function (zero-cost lookups).
    fir: *FunctionIR,
    /// Module-level IR store (for cross-function queries).
    ir_store: *ModuleIRStore,
    /// Semantic tree for recording resolution results.
    srt: *SemanticTree,
    /// Diagnostic writer for reporting issues.
    diag: *DiagnosticWriter,
    /// Memory allocator for temporary allocations.
    allocator: std.mem.Allocator,

    /// Initialize a new detector context.
    pub fn init(
        module: c.LLVMModuleRef,
        func: c.LLVMValueRef,
        fir: *FunctionIR,
        store: *ModuleIRStore,
        tree: *SemanticTree,
        diagnostic: *DiagnosticWriter,
        alloc: std.mem.Allocator,
    ) DetectorContext {
        return .{
            .module = module,
            .func = func,
            .fir = fir,
            .ir_store = store,
            .srt = tree,
            .diag = diagnostic,
            .allocator = alloc,
        };
    }
};

/// Type alias for instruction event handler functions.
pub const InstructionHandler = *const fn (ctx: *DetectorContext, inst: c.LLVMValueRef) anyerror!void;

/// Type alias for call event handler functions (with callee name).
pub const CallHandler = *const fn (ctx: *DetectorContext, inst: c.LLVMValueRef, callee_name: ?[]const u8) anyerror!void;

/// Type alias for function-level event handler functions.
pub const FunctionHandler = *const fn (ctx: *DetectorContext) anyerror!void;

/// Event handler types for instruction-level events.
///
/// These are the core events dispatched during the single-pass traversal.
/// Each handler receives the instruction value and optional pre-computed data.
pub const InstructionHandlers = struct {
    /// Handle a call/invoke instruction.
    onCall: ?CallHandler = null,

    /// Handle a bitcast instruction.
    onBitcast: ?InstructionHandler = null,

    /// Handle a load instruction.
    onLoad: ?InstructionHandler = null,

    /// Handle a store instruction.
    onStore: ?InstructionHandler = null,

    /// Handle an alloca instruction.
    onAlloca: ?InstructionHandler = null,

    /// Handle a getelementptr instruction.
    onGEP: ?InstructionHandler = null,

    /// Handle a return instruction.
    onRet: ?InstructionHandler = null,

    /// Handle a ptrtoint or inttoptr instruction.
    onPtrIntConversion: ?InstructionHandler = null,

    /// Handle a PHI node instruction.
    onPHI: ?InstructionHandler = null,
};

/// Event handler types for function-level events.
///
/// These handlers are called once per function, before/after instruction traversal.
pub const FunctionHandlers = struct {
    /// Called when entering a new function (before instruction loop).
    onFunctionEnter: ?FunctionHandler = null,

    /// Called when leaving a function (after instruction loop completes).
    onFunctionExit: ?FunctionHandler = null,
};

/// Event handler types for module-level events.
///
/// These handlers are called once per module, before/after all functions.
pub const ModuleHandlers = struct {
    /// Called at the start of module processing (before any functions).
    onModuleEnter: ?FunctionHandler = null,

    /// Called after all functions have been processed.
    onModuleComplete: ?FunctionHandler = null,
};

/// Complete detector interface combining all event handler types.
///
/// A detector implementation should fill in only the handlers it needs;
/// unused handlers remain null and are skipped by the dispatcher.
pub const DetectorInterface = struct {
    /// Instruction-level event handlers.
    instruction: InstructionHandlers = .{},
    /// Function-level event handlers.
    function: FunctionHandlers = .{},
    /// Module-level event handlers.
    module: ModuleHandlers = .{},

    /// Check if this detector has any active handlers.
    pub fn isActive(self: *const DetectorInterface) bool {
        return self.instruction.onCall != null or
            self.instruction.onBitcast != null or
            self.instruction.onLoad != null or
            self.instruction.onStore != null or
            self.instruction.onAlloca != null or
            self.instruction.onGEP != null or
            self.instruction.onRet != null or
            self.instruction.onPtrIntConversion != null or
            self.instruction.onPHI != null or
            self.function.onFunctionEnter != null or
            self.function.onFunctionExit != null or
            self.module.onModuleEnter != null or
            self.module.onModuleComplete != null;
    }
};

/// Statistics tracking for a single detector execution.
///
/// Used for performance monitoring and debugging.
pub const DetectorStats = struct {
    /// Number of times this detector was invoked (total event calls).
    total_calls: u64 = 0,
    /// Number of errors encountered (non-fatal, logged as warnings).
    error_count: u64 = 0,
    /// Number of resolutions recorded to SRT.
    resolutions_made: u64 = 0,

    /// Reset all statistics counters.
    pub fn reset(self: *DetectorStats) void {
        self.total_calls = 0;
        self.error_count = 0;
        self.resolutions_made = 0;
    }
};
