//! FFI Boundary Parallel Execution Support
//!
//! T3.1: Worker context and function for parallel per-function analysis
//! of the FFIBoundaryPass. Extracted from ffi_boundary.zig to keep
//! the orchestrator under the 1000-line limit.
//!
//! Architecture:
//!   - FFIBoundaryWorkerContext: Shared state passed to each worker thread
//!   - ffiBoundaryWorkerFn(): Processes one function through the FFI boundary pipeline
//!   - Uses std.Thread.Mutex for protecting shared PassContext state

const std = @import("std");

const parallel = @import("../../../pipeline/parallel.zig");
const PassContext = @import("../../pass.zig").PassContext;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

/// T3.1: Worker context for FFI boundary parallel analysis.
/// Holds pointers to all resources needed during per-function FFI analysis.
pub const FFIBoundaryWorkerContext = struct {
    ctx_ptr: *PassContext,
    diag_ptr: *DiagnosticWriter,
    mutex: *std.Thread.Mutex,
    total_analyzed_out: *u32,
    issues_out: *u32,
};

var ffi_context_ptr: ?*FFIBoundaryWorkerContext = null;

pub fn getFFIWorkerContext() *FFIBoundaryWorkerContext {
    return ffi_context_ptr.?;
}

pub fn setFFIWorkerContext(ctx: *FFIBoundaryWorkerContext) void {
    ffi_context_ptr = ctx;
}

pub fn clearFFIWorkerContext() void {
    ffi_context_ptr = null;
}

/// T3.1: Worker function for parallel FFI boundary analysis.
/// Each invocation processes one WorkItem (one LLVM function) through:
///   1. Relevance gate (isRelevantFunction / JNI/Java/Py exception)
///   2. Zone classification → language channel gate → noise filter
///   3. Call instruction scanning for FFI boundaries
///
/// Thread safety: All shared state accesses are protected by the mutex
/// held in worker_ctx. Lock duration covers the full analyze() call.
pub fn ffiBoundaryWorkerFn(item: parallel.WorkItem, worker_id: usize) !parallel.WorkerResult {
    _ = worker_id;
    var result = parallel.WorkerResult{};
    const wctx = getFFIWorkerContext();

    // P0-2: Function-level gate — skip functions without danger-surface-relevant pointers.
    // EXCEPTION: Always analyze JNI_*/Java_/Py_* functions for FFI boundary detection,
    // even if DangerSurfacePass didn't mark them as relevant (indirect calls via function
    // pointers may not be detected by surface analysis).
    const is_ffi_boundary_func = (std.mem.indexOf(u8, item.func_name, "JNI_") != null or
        std.mem.indexOf(u8, item.func_name, "Java_") != null or
        std.mem.startsWith(u8, item.func_name, "Py_"));

    if (!wctx.ctx_ptr.isRelevantFunction(@as(u64, item.func)) and !is_ffi_boundary_func) {
        result.funcs_skipped += 1;
        return result;
    }

    // Core analysis under mutex (writes to issues, cross_lang_edges, zone_cache)
    wctx.mutex.lock();
    defer wctx.mutex.unlock();

    const fir = wctx.ctx_ptr.ir_store.function_list[item.fir_idx];
    const FFIBoundaryPass = @import("ffi_boundary.zig").FFIBoundaryPass;
    const analyze_result = FFIBoundaryPass.analyze(wctx.ctx_ptr, fir, wctx.diag_ptr) catch |err| {
        wctx.diag_ptr.warn("FFIBoundary: skipped function due to error: {} ({s})", .{ err, item.func_name });
        wctx.ctx_ptr.recordDegradedFunction();
        result.funcs_errored += 1;
        return result;
    };

    result.funcs_analyzed = 1;
    wctx.total_analyzed_out.* += 1;
    wctx.issues_out.* += analyze_result.count;

    return result;
}
