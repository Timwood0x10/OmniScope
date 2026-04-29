//! Raw Pointer Lifetime Tracker
//!
//! Phase 4.1: Tracks raw pointer lifecycle in escape zone functions to detect:
//! - Stack pointer escapes to FFI callback (dangling pointer after return)
//! - Use-after-scope (pointer used after its allocation scope ends)
//! - Return of stack-local address (undefined behavior)
//! - Heap pointer passed to extern without ownership transfer
//!
//! Design principle: Intra-procedural analysis with def-use chain tracking.
//! Based on IR facts only, no inter-procedural alias analysis required.
//!
//! Reference: plan/lang_ffi_analysis/plan.md - Escape Zone Deep Analysis
//!
//! Example bugs detected:
//!
//!   // Rust: stack pointer escapes to C callback
//!   unsafe {
//!       let buf = [0u8; 256];
//!       c_callback(buf.as_ptr());  // BUG: buf deallocated when scope exits
//!   }
//!
//!   // Zig: returning stack address
//!   fn getBuffer() [*]const u8 {
//!       var buf: [64]u8 = undefined;
//!       return &buf;  // BUG: stack memory invalidated on return
//!   }

const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const PassContext = @import("../pass.zig").PassContext;
const PassKind = @import("../pass.zig").PassKind;
const DiagnosticWriter = @import("../pass.zig").DiagnosticWriter;

const Location = @import("../../diag/issue.zig").Location;
const Issue = @import("../../diag/issue.zig").Issue;
const IssueKind = @import("../../diag/issue.zig").IssueKind;
const Severity = @import("../../diag/issue.zig").Severity;
const TraceEntry = @import("../../diag/issue.zig").TraceEntry;
const zone_classifier = @import("../../semantics/zone_classifier.zig");
const FPWhitelist = @import("../filter/fp_whitelist.zig");
const NoiseReduction = @import("noise_reduction.zig");

/// Allocation site classification for pointers.
pub const PtrAllocSite = enum(u8) {
    /// Allocated via malloc/calloc/realloc (heap)
    heap,
    /// Address of local variable (alloca instruction)
    stack,
    /// Function parameter (incoming pointer)
    parameter,
    /// Global variable address
    global,
    /// Constant/null value
    constant,
    /// Unknown origin (e.g., function return value)
    unknown,
};

/// Lifetime violation types detected by the tracker.
pub const LifetimeViolation = enum(u8) {
    /// Stack pointer passed to extern function that may outlive it
    stack_escape_to_ffi,
    /// Return of stack-local address
    return_stack_address,
    /// Use of pointer after potential free
    use_after_free_risk,
    /// Heap pointer passed to extern without documented transfer
    heap_ownership_ambiguous,
    /// Resource handle (dlopen) closed while derived pointers may still be in use
    dlhandle_closed_while_active,
    /// Memory mapping (mmap) unmapped while pointers to it may still be used
    mmap_unmapped_while_active,
    /// File handle (fopen) closed while FILE* may still be used
    file_handle_closed_while_active,
    /// Socket closed while socket fd may still be used
    socket_closed_while_active,
    /// JNI local reference deleted while still in use
    jni_local_ref_deleted_while_active,
    /// Python object reference released while still in use
    python_obj_released_while_active,
};

/// Information about a tracked pointer's origin and state.
pub const PtrInfo = struct {
    /// Where this pointer was allocated
    alloc_site: PtrAllocSite,
    /// The instruction that created this pointer (if any)
    source_inst: ?c.LLVMValueRef,
    /// Human-readable description for trace output
    source_desc: []const u8,
    /// Whether this pointer has been passed to an extern call
    escaped: bool = false,
    /// Whether this pointer has been freed
    freed: bool = false,
    /// Basic block where the pointer was allocated (for scope tracking)
    alloc_bb_id: usize = 0,
    /// Resource handle this pointer is derived from (e.g., dlopen handle for dlsym result)
    derived_from_handle: ?c.LLVMValueRef = null,
    /// Type of resource handle if derived
    resource_type: ResourceType = .none,
    /// Whether source_desc was dynamically allocated (for safe free)
    needs_free: bool = false,
};

/// Resource types for lifecycle tracking.
pub const ResourceType = enum(u8) {
    none,
    dlopen_handle,
    mmap_region,
    file_handle,
    socket_fd,
    jni_ref,
    python_obj,
};

/// Analysis result for a single function.
pub const LifetimeAnalysisResult = struct {
    /// Number of violations found
    violation_count: u32 = 0,
    /// Total pointers tracked
    pointers_tracked: u32 = 0,
    /// Functions analyzed
    func_name: []const u8,
};

/// Statistics for the lifetime tracker pass.
pub const LifetimeStats = struct {
    total_functions_analyzed: u32 = 0,
    total_pointers_tracked: u32 = 0,
    stack_escapes_found: u32 = 0,
    return_stack_addr_found: u32 = 0,
    use_after_free_found: u32 = 0,
    heap_ambiguous_found: u32 = 0,
    heap_intentional_transfer: u32 = 0,

    pub fn formatSummary(self: LifetimeStats, writer: anytype) !void {
        try writer.writeAll("\n╔══════════════════════════════════════╗\n");
        try writer.writeAll("║   POINTER LIFETIME TRACKER SUMMARY   ║\n");
        try writer.writeAll("╠══════════════════════════════════════╣\n");
        try writer.print("║  Functions analyzed:     {d:>8}      ║\n", .{self.total_functions_analyzed});
        try writer.print("║  Pointers tracked:       {d:>8}      ║\n", .{self.total_pointers_tracked});
        try writer.print("║  Stack-FFI escapes:      {d:>8}      ║\n", .{self.stack_escapes_found});
        try writer.print("║  Return-stack-address:   {d:>8}      ║\n", .{self.return_stack_addr_found});
        try writer.print("║  Use-after-free risks:   {d:>8}      ║\n", .{self.use_after_free_found});
        try writer.print("║  Heap ownership issues:  {d:>8}      ║\n", .{self.heap_ambiguous_found});
        try writer.print("║  Factory transfers (ok): {d:>8}      ║\n", .{self.heap_intentional_transfer});
        try writer.writeAll("╚══════════════════════════════════════╝\n");
    }
};

// ============================================================================
// Extern Function Detection
// ============================================================================

/// Known FFI boundary functions that may retain pointers.
/// These are functions where passing a stack pointer is dangerous.
const FFI_RETAINING_FUNCTIONS = &[_][]const u8{
    "c_callback",
    "register_callback",
    "set_handler",
    "pthread_create",
    "signal",
    "atexit",
    "on_exit",
    "SDL_SetEventCallback",
    "glfwSetCallback",
    "curl_easy_setopt",
};

/// Functions that commonly take callbacks (their arguments may be stored).
const CALLBACK_TAKING_FUNCTIONS = &[_][]const u8{
    "register",
    "set_callback",
    "add_observer",
    "subscribe",
    "listen_on",
    "handler",
    "hook",
};

/// Known deallocator/finalizer functions that release resources.
/// These are paired with their corresponding allocators to reduce false positives.
pub const KNOWN_DEALLOCATORS = struct {
    pub const finalize_functions = &[_][]const u8{
        "sqlite3_finalize", "sqlite3_step",   "mysql_stmt_close",
        "stmt_finalize",    "query_finalize", "statement_finalize",
    };
    pub const close_functions = &[_][]const u8{
        "fclose",       "close",        "closedir",            "closed", "shutdown",
        "SSL_shutdown", "BIO_free_all", "EVP_CIPHER_CTX_free",
    };
    pub const free_functions = &[_][]const u8{
        "sqlite3_free",      "mysql_free_result",   "PQclear", "nghttp2_session_del",
        "curl_easy_cleanup", "curl_slist_free_all",
    };
    pub const destroy_functions = &[_][]const u8{
        "sqlite3_close", "sqlite3_close_v2", "mysql_close",
        "destroy",       "Delete",           "Release",
        "Free",
    };
};

/// Check if a callee name looks like an extern/FFI function.
pub fn is_extern_function(name: []const u8) bool {
    if (name.len == 0) return false;

    for (FFI_RETAINING_FUNCTIONS) |func| {
        if (std.mem.indexOf(u8, name, func) != null) return true;
    }

    for (CALLBACK_TAKING_FUNCTIONS) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) return true;
    }

    return false;
}

/// Check if function is a known deallocator that releases resources.
/// Used to reduce false positives in leak detection.
pub fn is_known_deallocator(func_name: []const u8) bool {
    inline for (.{ KNOWN_DEALLOCATORS.finalize_functions, KNOWN_DEALLOCATORS.close_functions, KNOWN_DEALLOCATORS.free_functions, KNOWN_DEALLOCATORS.destroy_functions }) |group| {
        for (group) |dealloc| {
            if (std.mem.indexOf(u8, func_name, dealloc) != null) return true;
        }
    }
    return false;
}

fn isResourceCloseFunctionForIntentional(fn_name: []const u8) bool {
    const close_fns = [_][]const u8{
        "dlclose",         "munmap",         "fclose",    "close",
        "DeleteGlobalRef", "DeleteLocalRef", "Py_DECREF", "Py_XDECREF",
    };
    for (close_fns) |close_fn| {
        if (std.mem.indexOf(u8, fn_name, close_fn) != null) return true;
    }
    return false;
}

/// Check if pointer was freed by a known deallocator.
/// Returns true if the free operation was intentional.
pub fn is_intentional_free(func_name: []const u8) bool {
    return is_known_deallocator(func_name) or isResourceCloseFunctionForIntentional(func_name);
}

/// Check if a function may store/retain its pointer argument.
pub fn may_retain_pointer(callee_name: []const u8) bool {
    if (is_extern_function(callee_name)) return true;

    const retaining_patterns = [_][]const u8{
        "register_", "add_",  "insert_", "push_",
        "store_",    "save_", "cache_",  "copy_",
    };

    for (retaining_patterns) |pat| {
        if (std.mem.startsWith(u8, callee_name, pat)) return true;
    }

    if (std.mem.startsWith(u8, callee_name, "set_")) {
        if (isOutputParamSetter(callee_name)) return false;
        return true;
    }

    return false;
}

fn isOutputParamSetter(func_name: []const u8) bool {
    const output_param_patterns = [_][]const u8{
        "_ip",  "_addr", "_port", "_fd",    "_sock",
        "_buf", "_len",  "_size", "_count", "_ptr",
        "_str", "_name", "_path", "_url",
    };
    for (output_param_patterns) |pat| {
        if (std.mem.indexOf(u8, func_name, pat) != null) return true;
    }
    return false;
}

// ============================================================================
// Allocation Site Detection
// ============================================================================

/// Heap allocation functions.
const HEAP_ALLOC_FUNCTIONS = &[_][]const u8{
    "malloc",         "calloc",        "realloc",      "aligned_alloc",
    "valloc",         "pvalloc",       "memalign",     "operator new",
    "operator new[]", "into_raw",      "allocImpl",    "mmap",
    "dlopen",         "fopen",         "socket",       "JNI_OnLoad",
    "Py_Initialize",  "Py_BuildValue", "PyTuple_New",  "PyList_New",
    "PyDict_New",     "NewStringUTF",  "NewByteArray", "NewGlobalRef",
};

/// Classify the allocation site of a pointer value.
pub fn classify_ptr_origin(
    inst: c.LLVMValueRef,
    opcode: c_uint,
    func: c.LLVMValueRef,
    allocator: std.mem.Allocator,
) !?PtrInfo {
    _ = func;
    switch (opcode) {
        c.LLVMAlloca => {
            const desc = try std.fmt.allocPrint(allocator, "stack allocation (alloca)", .{});
            return PtrInfo{
                .alloc_site = .stack,
                .source_inst = inst,
                .source_desc = desc,
                .needs_free = true,
            };
        },
        c.LLVMCall, c.LLVMInvoke => {
            const called = c.LLVMGetCalledValue(inst);
            if (@intFromPtr(called) == 0) return null;

            const name_ptr = c.LLVMGetValueName(called);
            if (@intFromPtr(name_ptr) == 0) return null;

            const callee_name = std.mem.span(name_ptr);

            for (HEAP_ALLOC_FUNCTIONS) |alloc_fn| {
                if (std.mem.indexOf(u8, callee_name, alloc_fn) != null) {
                    const desc = try std.fmt.allocPrint(allocator, "heap allocation via {s}()", .{callee_name});
                    return PtrInfo{
                        .alloc_site = .heap,
                        .source_inst = inst,
                        .source_desc = desc,
                        .needs_free = true,
                    };
                }
            }

            return null;
        },
        else => return null,
    }
}

// ============================================================================
// Main Pass
// ============================================================================

/// Raw Pointer Lifetime Tracker Pass
///
/// Analyzes escape zone functions for pointer lifetime violations:
/// 1. Stack pointers escaping to FFI boundaries
/// 2. Stack addresses returned from functions
/// 3. Use-after-free patterns
/// 4. Ambiguous heap ownership across FFI
pub const PtrLifetimePass = struct {
    pub const name = "ptr-lifetime";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        if (ctx.module == null) return;

        const mod = ctx.module.?.raw;
        var func = c.LLVMGetFirstFunction(mod);
        if (@intFromPtr(func) == 0) return;

        const noise_config = NoiseReduction.NoiseReductionConfig{ .focus_user_code = true };
        var stats = LifetimeStats{};

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            if (c.LLVMIsDeclaration(func) != 0) {
                const func_name_raw = c.LLVMGetValueName(func);
                const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";
                const zone = zone_classifier.classifyFunctionFromLLVM(func, func_name);
                ctx.zone_stats.record(zone);
                continue;
            }

            const func_name_raw = c.LLVMGetValueName(func);
            const func_name = if (func_name_raw != null) std.mem.span(func_name_raw) else "unknown";

            const zone = zone_classifier.classifyFunctionFromLLVM(func, func_name);
            ctx.zone_stats.record(zone);

            // v0.1.8: Three-layer noise reduction (supersedes zone-only check)
            const debug_file_path = extractDebugFilePath(func);
            const classification = NoiseReduction.classifyFunction(func_name, debug_file_path, noise_config);
            if (classification.origin == .compiler_generated) continue;
            if (classification.origin == .stdlib and !noise_config.include_stdlib) continue;

            // Defense-in-depth: known FP whitelist (v0.1.8 audit verified)
            if (FPWhitelist.is_known_fp(func_name) != null) continue;

            try analyzeFunction(ctx, func, diag, &stats);
        }

        diag.info("PtrLifetime: analyzed {} funcs, tracked {} ptrs, found {} violations", .{
            stats.total_functions_analyzed,
            stats.total_pointers_tracked,
            stats.stack_escapes_found + stats.return_stack_addr_found + stats.use_after_free_found + stats.heap_ambiguous_found,
        });
    }

    /// Extract debug file path from LLVM subprogram metadata.
    /// Used by NoiseReduction Layer 2 (path-based filter).
    fn extractDebugFilePath(func: c.LLVMValueRef) ?[]const u8 {
        const subprogram = c.LLVMGetSubprogram(func);
        if (@intFromPtr(subprogram) == 0) return null;

        const file_ref = c.LLVMDIScopeGetFile(subprogram);
        if (@intFromPtr(file_ref) == 0) return null;

        var filename_len: c_uint = undefined;
        const filename_ptr = c.LLVMDIFileGetFilename(file_ref, &filename_len);
        if (@intFromPtr(filename_ptr) == 0 or filename_len == 0) return null;

        const max_path_len: c_uint = 4096;
        if (filename_len > max_path_len) return null;
        if (filename_ptr[0] == 0) return null;

        return filename_ptr[0..filename_len];
    }

    fn analyzeFunction(
        ctx: *PassContext,
        func: c.LLVMValueRef,
        diag: *DiagnosticWriter,
        stats: *LifetimeStats,
    ) !void {
        const func_name_ptr = c.LLVMGetValueName(func);
        const func_name = if (@intFromPtr(func_name_ptr) != 0)
            std.mem.span(func_name_ptr)
        else
            "unknown";

        stats.total_functions_analyzed += 1;

        var pointer_map = std.AutoHashMap(c.LLVMValueRef, PtrInfo).init(ctx.allocator);
        defer {
            var iter = pointer_map.iterator();
            while (iter.next()) |entry| {
                ctx.allocator.free(entry.value_ptr.source_desc);
            }
            pointer_map.deinit();
        }

        var bb_id: usize = 0;

        var bb = c.LLVMGetFirstBasicBlock(func);
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                try trackInstruction(ctx.allocator, inst, func, bb_id, &pointer_map, stats);
            }
            bb_id += 1;
        }

        bb = c.LLVMGetFirstBasicBlock(func);
        bb_id = 0;
        while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
            var inst = c.LLVMGetFirstInstruction(bb);
            while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                try checkViolations(ctx, inst, func, func_name, bb_id, &pointer_map, diag, stats);
            }
            bb_id += 1;
        }
    }

    fn trackInstruction(
        allocator: std.mem.Allocator,
        inst: c.LLVMValueRef,
        _: c.LLVMValueRef,
        bb_id: usize,
        pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
        stats: *LifetimeStats,
    ) !void {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        switch (opcode) {
            c.LLVMAlloca => {
                const desc = try std.fmt.allocPrint(allocator, "stack alloca", .{});
                const info = PtrInfo{
                    .alloc_site = .stack,
                    .source_inst = inst,
                    .source_desc = desc,
                    .alloc_bb_id = bb_id,
                    .needs_free = true,
                };
                try putPtrInfo(pointer_map, inst, info, allocator);
                stats.total_pointers_tracked += 1;
            },

            c.LLVMCall, c.LLVMInvoke => {
                const called = c.LLVMGetCalledValue(inst);
                if (@intFromPtr(called) != 0) {
                    const name_ptr = c.LLVMGetValueName(called);
                    if (@intFromPtr(name_ptr) != 0) {
                        const callee_name = std.mem.span(name_ptr);

                        for (HEAP_ALLOC_FUNCTIONS) |alloc_fn| {
                            if (std.mem.indexOf(u8, callee_name, alloc_fn) != null) {
                                const desc = try std.fmt.allocPrint(allocator, "heap via {s}()", .{callee_name});
                                const info = PtrInfo{
                                    .alloc_site = .heap,
                                    .source_inst = inst,
                                    .source_desc = desc,
                                    .alloc_bb_id = bb_id,
                                    .needs_free = true,
                                };
                                try putPtrInfo(pointer_map, inst, info, allocator);
                                stats.total_pointers_tracked += 1;
                                break;
                            }
                        }

                        if (is_resource_alloc_function(callee_name)) |res_type| {
                            const desc = try std.fmt.allocPrint(allocator, "resource via {s}()", .{callee_name});
                            const info = PtrInfo{
                                .alloc_site = .heap,
                                .source_inst = inst,
                                .source_desc = desc,
                                .alloc_bb_id = bb_id,
                                .resource_type = res_type,
                                .needs_free = true,
                            };
                            try putPtrInfo(pointer_map, inst, info, allocator);
                            stats.total_pointers_tracked += 1;
                        }

                        if (std.mem.indexOf(u8, callee_name, "dlsym") != null) {
                            const num_ops = c.LLVMGetNumOperands(inst);
                            var op_idx: u32 = 0;
                            while (op_idx < @min(num_ops, 2)) : (op_idx += 1) {
                                const handle_arg = c.LLVMGetOperand(inst, op_idx);
                                if (@intFromPtr(handle_arg) == 0) continue;
                                if (pointer_map.get(handle_arg)) |handle_info| {
                                    if (handle_info.resource_type == .dlopen_handle or
                                        handle_info.resource_type == .none)
                                    {
                                        const desc = try std.fmt.allocPrint(allocator, "dlsym-derived pointer from {s}", .{handle_info.source_desc});
                                        const info = PtrInfo{
                                            .alloc_site = .heap,
                                            .source_inst = inst,
                                            .source_desc = desc,
                                            .alloc_bb_id = bb_id,
                                            .derived_from_handle = handle_arg,
                                            .resource_type = handle_info.resource_type,
                                            .needs_free = true,
                                        };
                                        try putPtrInfo(pointer_map, inst, info, allocator);
                                        stats.total_pointers_tracked += 1;
                                    }
                                }
                            }
                        }

                        if (isFreeFunction(callee_name)) {
                            const ptr_arg = c.LLVMGetOperand(inst, 0);
                            if (pointer_map.getPtr(ptr_arg)) |ptr_info| {
                                ptr_info.freed = true;
                            }
                        }

                        if (isResourceCloseFunction(callee_name)) |closed_type| {
                            const handle_arg = c.LLVMGetOperand(inst, 0);
                            if (pointer_map.getPtr(handle_arg)) |handle_info| {
                                handle_info.freed = true;
                                var it = pointer_map.iterator();
                                while (it.next()) |entry| {
                                    if (entry.value_ptr.resource_type == closed_type and
                                        entry.value_ptr.derived_from_handle != null)
                                    {
                                        const derived = entry.value_ptr.derived_from_handle.?;
                                        if (isSameOrAlias(derived, handle_arg)) {
                                            entry.value_ptr.freed = true;
                                        }
                                    }
                                }
                            } else {
                                var it = pointer_map.iterator();
                                while (it.next()) |entry| {
                                    if (entry.value_ptr.resource_type == closed_type and
                                        entry.value_ptr.derived_from_handle == null)
                                    {
                                        entry.value_ptr.freed = true;
                                    }
                                }
                            }
                        }
                    }
                }
            },

            c.LLVMLoad => {
                try propagateOrigin(inst, c.LLVMGetOperand(inst, 0), pointer_map, allocator, bb_id);
            },

            c.LLVMStore => {
                const value = c.LLVMGetOperand(inst, 0);
                const dest = c.LLVMGetOperand(inst, 1);
                if (pointer_map.get(value)) |src_info| {
                    var new_info = src_info;
                    const desc = try allocator.dupe(u8, src_info.source_desc);
                    new_info.source_desc = desc;
                    new_info.needs_free = true;
                    try putPtrInfo(pointer_map, dest, new_info, allocator);
                }
            },

            c.LLVMGetElementPtr => {
                try propagateOrigin(inst, c.LLVMGetOperand(inst, 0), pointer_map, allocator, bb_id);
            },

            c.LLVMBitCast, c.LLVMPtrToInt, c.LLVMIntToPtr => {
                try propagateOrigin(inst, c.LLVMGetOperand(inst, 0), pointer_map, allocator, bb_id);
            },

            else => {},
        }
    }

    fn putPtrInfo(
        map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
        key: c.LLVMValueRef,
        info: PtrInfo,
        allocator: std.mem.Allocator,
    ) !void {
        const gop = try map.getOrPut(key);
        if (gop.found_existing and gop.value_ptr.needs_free) {
            allocator.free(gop.value_ptr.source_desc);
        }
        gop.value_ptr.* = info;
    }

    fn propagateOrigin(
        dst: c.LLVMValueRef,
        src: c.LLVMValueRef,
        pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
        allocator: std.mem.Allocator,
        bb_id: usize,
    ) !void {
        if (pointer_map.get(src)) |src_info| {
            const desc = try allocator.dupe(u8, src_info.source_desc);
            var new_info = src_info;
            new_info.source_desc = desc;
            new_info.alloc_bb_id = bb_id;
            new_info.needs_free = true;
            try putPtrInfo(pointer_map, dst, new_info, allocator);
        }
    }

    fn checkViolations(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        func: c.LLVMValueRef,
        func_name: []const u8,
        bb_id: usize,
        pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
        diag: *DiagnosticWriter,
        stats: *LifetimeStats,
    ) !void {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
            try checkCallViolation(ctx, inst, func, func_name, bb_id, pointer_map, diag, stats);
        }

        if (opcode == c.LLVMRet) {
            try checkReturnViolation(ctx, inst, func, func_name, pointer_map, diag, stats);
        }

        if (opcode == c.LLVMStore) {
            try checkStoreToGlobal(ctx, inst, func_name, pointer_map, diag, stats);
        }
    }

    fn checkStoreToGlobal(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        func_name: []const u8,
        pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
        diag: *DiagnosticWriter,
        stats: *LifetimeStats,
    ) !void {
        const ptr_operand = c.LLVMGetOperand(inst, 1);
        const value_operand = c.LLVMGetOperand(inst, 0);

        if (ptr_operand == null or value_operand == null) return;

        if (isGlobalVariable(ptr_operand)) {
            if (pointer_map.get(value_operand)) |ptr_info| {
                if (ptr_info.alloc_site == .heap and !ptr_info.escaped) {
                    try reportHeapToGlobal(ctx, func_name, ptr_info, inst, diag);
                    stats.heap_ambiguous_found += 1;
                    if (pointer_map.getPtr(value_operand)) |pi| pi.escaped = true;
                } else if (ptr_info.alloc_site == .stack and !ptr_info.escaped) {
                    try reportStackToGlobal(ctx, func_name, ptr_info, inst, diag);
                    stats.stack_escapes_found += 1;
                    if (pointer_map.getPtr(value_operand)) |pi| pi.escaped = true;
                }
            }
        }
    }

    fn isGlobalVariable(ptr: c.LLVMValueRef) bool {
        if (ptr == null) return false;
        const value_kind = c.LLVMGetValueKind(ptr);
        return value_kind == c.LLVMGlobalVariableValueKind;
    }

    fn checkCallViolation(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        _: c.LLVMValueRef,
        func_name: []const u8,
        _: usize,
        pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
        diag: *DiagnosticWriter,
        stats: *LifetimeStats,
    ) !void {
        const called = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called) == 0) return;

        const name_ptr = c.LLVMGetValueName(called);
        if (@intFromPtr(name_ptr) == 0) return;

        const callee_name = std.mem.span(name_ptr);

        if (!may_retain_pointer(callee_name)) return;

        const num_ops = c.LLVMGetNumOperands(inst);
        var i: u32 = 0;
        while (i < num_ops) : (i += 1) {
            const arg = c.LLVMGetOperand(inst, i);
            if (pointer_map.get(arg)) |ptr_info| {
                if (ptr_info.alloc_site == .stack and !ptr_info.escaped) {
                    try reportStackEscape(ctx, func_name, callee_name, ptr_info, inst, diag);
                    stats.stack_escapes_found += 1;
                    if (pointer_map.getPtr(arg)) |pi| pi.escaped = true;
                } else if (ptr_info.alloc_site == .heap and !ptr_info.escaped) {
                    // v0.1.6: Heap pointer escaping to FFI is also critical.
                    // A malloc'd buffer passed to an extern retaining function means
                    // the caller must know to free it — classic FFI ownership bug.
                    try reportHeapEscapeToFFI(ctx, func_name, callee_name, ptr_info, inst, diag);
                    stats.heap_ambiguous_found += 1;
                    if (pointer_map.getPtr(arg)) |pi| pi.escaped = true;
                } else if (ptr_info.freed) {
                    if (ptr_info.resource_type != .none) {
                        try reportResourceUAF(ctx, func_name, callee_name, ptr_info, inst, diag);
                    } else {
                        try reportUseAfterFree(ctx, func_name, callee_name, ptr_info, inst, diag);
                    }
                    stats.use_after_free_found += 1;
                }
            }
        }
    }

    fn checkReturnViolation(
        ctx: *PassContext,
        inst: c.LLVMValueRef,
        _: c.LLVMValueRef,
        func_name: []const u8,
        pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
        diag: *DiagnosticWriter,
        stats: *LifetimeStats,
    ) !void {
        const num_ops = c.LLVMGetNumOperands(inst);
        if (num_ops == 0) return;

        if (isCppDestructorOrConstructor(func_name)) {
            return;
        }

        if (isNonPointerReturnType(inst)) {
            diag.debug("[SUPPRESSED] C API output parameter pattern: {s} returns non-pointer (likely using output params)", .{func_name});
            return;
        }

        const retval = c.LLVMGetOperand(inst, 0);
        if (pointer_map.get(retval)) |ptr_info| {
            if (ptr_info.alloc_site == .stack) {
                try reportReturnStackAddr(ctx, func_name, ptr_info, inst, diag);
                stats.return_stack_addr_found += 1;
            } else if (ptr_info.alloc_site == .heap) {
                if (!isIntentionalOwnershipTransfer(func_name)) {
                    if (is_lifecycle_bound_return(func_name, ptr_info)) {
                        diag.debug("[MARKED] Lifecycle-bound return: {s} -> {s} (handle-dependent lifetime)", .{ func_name, ptr_info.source_desc });
                        stats.heap_intentional_transfer += 1;
                    } else {
                        try reportReturnHeapPtr(ctx, func_name, ptr_info, inst, diag);
                        stats.heap_ambiguous_found += 1;
                    }
                } else {
                    diag.debug("[SUPPRESSED] Heap return in factory function: {s} (intentional ownership transfer)", .{func_name});
                    stats.heap_intentional_transfer += 1;
                }
            }
        }
    }

    fn is_lifecycle_bound_return(func_name: []const u8, ptr_info: PtrInfo) bool {
        if (ptr_info.resource_type == .none) return false;
        if (ptr_info.resource_type == .dlopen_handle) {
            return std.mem.indexOf(u8, func_name, "dlsym") != null;
        }
        if (ptr_info.resource_type == .mmap_region) {
            return std.mem.indexOf(u8, func_name, "mmap") != null;
        }
        if (ptr_info.resource_type == .file_handle) {
            return std.mem.indexOf(u8, func_name, "fopen") != null;
        }
        if (ptr_info.resource_type == .socket_fd) {
            return std.mem.indexOf(u8, func_name, "socket") != null;
        }
        if (ptr_info.resource_type == .jni_ref) {
            return std.mem.indexOf(u8, func_name, "NewStringUTF") != null or
                std.mem.indexOf(u8, func_name, "NewByteArray") != null;
        }
        if (ptr_info.resource_type == .python_obj) {
            return std.mem.indexOf(u8, func_name, "Py_BuildValue") != null or
                std.mem.indexOf(u8, func_name, "PyTuple_New") != null;
        }
        return false;
    }

    fn isCppDestructorOrConstructor(func_name: []const u8) bool {
        if (func_name.len == 0) return false;
        if (func_name[func_name.len - 1] == 'E') {
            if (std.mem.indexOf(u8, func_name, "C1E") != null or
                std.mem.indexOf(u8, func_name, "C2E") != null or
                std.mem.indexOf(u8, func_name, "D1E") != null or
                std.mem.indexOf(u8, func_name, "D2E") != null)
            {
                return true;
            }
        }
        return false;
    }

    fn isNonPointerReturnType(ret_inst: c.LLVMValueRef) bool {
        const ret_value = c.LLVMGetOperand(ret_inst, 0);
        if (ret_value == null) return false;
        const value_type = c.LLVMTypeOf(ret_value);
        if (value_type == null) return false;
        return c.LLVMGetTypeKind(value_type) != c.LLVMPointerTypeKind;
    }

    fn isIntentionalOwnershipTransfer(func_name: []const u8) bool {
        const factory_prefixes = [_][]const u8{
            "create", "Create", "CREATE",
            "new",    "New",    "NEW",
            "make",   "Make",   "MAKE",
            "alloc",  "Alloc",  "ALLOC",
            "malloc", "calloc", "realloc",
            "open",   "Open",   "init",
            "Init",   "dup",    "Dup",
            "clone",  "Clone",  "copy",
            "Copy",   "from",   "From",
            "wrap",   "Wrap",   "build",
            "Build",
        };
        for (factory_prefixes) |prefix| {
            if (std.mem.startsWith(u8, func_name, prefix)) return true;
        }
        const factory_suffixes = [_][]const u8{
            "_create", "_new",  "_make", "_alloc",
            "_new_",   "_init", "_ctor", "_construct",
            "_clone",  "_copy", "_dup",  "_from",
        };
        for (factory_suffixes) |suffix| {
            if (std.mem.endsWith(u8, func_name, suffix)) return true;
        }
        return false;
    }

    fn isFreeFunction(fn_name: []const u8) bool {
        const free_fns = [_][]const u8{ "free", "dealloc", "deallocate", "operator delete" };
        for (free_fns) |free_fn| {
            if (std.mem.indexOf(u8, fn_name, free_fn) != null) return true;
        }
        return false;
    }

    fn isResourceCloseFunction(fn_name: []const u8) ?ResourceType {
        if (std.mem.indexOf(u8, fn_name, "dlclose") != null) return .dlopen_handle;
        if (std.mem.indexOf(u8, fn_name, "munmap") != null) return .mmap_region;
        if (std.mem.indexOf(u8, fn_name, "fclose") != null) return .file_handle;
        if (isSocketClose(fn_name)) return .socket_fd;
        if (std.mem.indexOf(u8, fn_name, "DeleteGlobalRef") != null or
            std.mem.indexOf(u8, fn_name, "DeleteLocalRef") != null) return .jni_ref;
        if (std.mem.indexOf(u8, fn_name, "Py_DECREF") != null or
            std.mem.indexOf(u8, fn_name, "Py_XDECREF") != null) return .python_obj;
        return null;
    }

    fn isSameOrAlias(a: c.LLVMValueRef, b: c.LLVMValueRef) bool {
        if (@intFromPtr(a) == @intFromPtr(b)) return true;
        if (isDerivedFrom(a, b) or isDerivedFrom(b, a)) return true;
        return false;
    }

    fn isDerivedFrom(value: c.LLVMValueRef, base: c.LLVMValueRef) bool {
        if (@intFromPtr(value) == 0 or @intFromPtr(base) == 0) return false;
        const opcode = c.LLVMGetInstructionOpcode(value);
        if (opcode == c.LLVMBitCast or opcode == c.LLVMPtrToInt or
            opcode == c.LLVMIntToPtr or opcode == c.LLVMAddrSpaceCast)
        {
            const src = c.LLVMGetOperand(value, 0);
            if (@intFromPtr(src) == @intFromPtr(base)) return true;
            if (isDerivedFrom(src, base)) return true;
        }
        if (opcode == c.LLVMGetElementPtr) {
            const ptr_op = c.LLVMGetOperand(value, 0);
            if (@intFromPtr(ptr_op) == @intFromPtr(base)) return true;
            if (isDerivedFrom(ptr_op, base)) return true;
        }
        return false;
    }

    fn isSocketClose(fn_name: []const u8) bool {
        const non_socket_patterns = [_][]const u8{
            "file_",   "document", "database",  "db_",
            "window",  "dir_",     "stream",    "buf_",
            "mem_",    "str_",     "xml_",      "json_",
            "log_",    "config",   "session",   "cache",
            "mutex",   "lock",     "semaphore", "cond_",
            "thread",  "process",  "handle",    "ref_",
            "context", "scope",    "state",     "node",
        };
        for (non_socket_patterns) |np| {
            if (std.mem.indexOf(u8, fn_name, np) != null and
                std.mem.indexOf(u8, fn_name, "close") != null)
            {
                return false;
            }
        }

        const exact_matches = [_][]const u8{
            "close", "::close",
        };
        for (exact_matches) |m| {
            if (std.mem.eql(u8, fn_name, m)) return true;
        }
        const socket_patterns = [_][]const u8{
            "socket_close", "sock_close",  "fd_close",
            "::close(",     "posix_close", "shutdown",
        };
        for (socket_patterns) |p| {
            if (std.mem.indexOf(u8, fn_name, p) != null) return true;
        }
        if (std.mem.endsWith(u8, fn_name, "_close")) {
            const prefix = fn_name[0 .. fn_name.len - 6];
            const socket_prefixes = [_][]const u8{
                "sock",   "fd_",    "conn", "pipe",
                "listen", "accept",
            };
            for (socket_prefixes) |sp| {
                if (std.mem.indexOf(u8, prefix, sp) != null) return true;
            }
        }
        return false;
    }

    fn is_resource_alloc_function(fn_name: []const u8) ?ResourceType {
        if (std.mem.indexOf(u8, fn_name, "dlopen") != null) return .dlopen_handle;
        if (std.mem.indexOf(u8, fn_name, "mmap64") != null or
            std.mem.indexOf(u8, fn_name, "mmap2") != null or
            std.mem.indexOf(u8, fn_name, "mmap") != null) return .mmap_region;
        if (std.mem.indexOf(u8, fn_name, "shm_open") != null) return .mmap_region;
        if (std.mem.indexOf(u8, fn_name, "fopen") != null) return .file_handle;
        if (std.mem.indexOf(u8, fn_name, "socket") != null) return .socket_fd;
        if (std.mem.indexOf(u8, fn_name, "JNI_") != null or
            std.mem.indexOf(u8, fn_name, "Java_") != null) return .jni_ref;
        if (std.mem.startsWith(u8, fn_name, "Py")) return .python_obj;
        return null;
    }

    fn get_resource_type(fn_name: []const u8) ?[]const u8 {
        if (std.mem.indexOf(u8, fn_name, "dlopen") != null or std.mem.indexOf(u8, fn_name, "dlsym") != null) return "dlhandle";
        if (std.mem.indexOf(u8, fn_name, "mmap") != null) return "mmap";
        if (std.mem.indexOf(u8, fn_name, "fopen") != null or std.mem.indexOf(u8, fn_name, "FILE") != null) return "file";
        if (std.mem.indexOf(u8, fn_name, "socket") != null) return "socket";
        if (std.mem.indexOf(u8, fn_name, "JNI") != null) return "jni";
        if (std.mem.indexOf(u8, fn_name, "Py_") != null) return "python";
        return null;
    }
};

// ============================================================================
// Reporting
// ============================================================================

fn reportStackEscape(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    ptr_info: PtrInfo,
    _: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Stack pointer passed to FFI boundary function");
    trace[1] = try makeTraceEntry(ctx.allocator, "Pointer origin: {s}", .{ptr_info.source_desc});
    trace[2] = try makeTraceEntry(ctx.allocator, "Passed to {s}() which may retain pointer beyond caller scope", .{callee_name});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Stack pointer ({s}) escapes to FFI function {s}() - pointer invalid after function returns (CWE-562)",
        .{ ptr_info.source_desc, callee_name },
    );

    const issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .critical,
        0.88,
        trace,
    );

    try ctx.addIssue(issue);
    diag.warn("[STACK-ESCAPE] {s} -> {s}() in {s}", .{ ptr_info.source_desc, callee_name, func_name });
}

fn reportReturnStackAddr(
    ctx: *PassContext,
    func_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 2);
    trace[0] = TraceEntry.init("Function returns address of stack-local variable");
    trace[1] = try makeTraceEntry(ctx.allocator, "Pointer origin: {s}", .{ptr_info.source_desc});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Function returns stack-local address ({s}) - dangling pointer after return (CWE-562)",
        .{ptr_info.source_desc},
    );

    const issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .critical,
        0.92,
        trace,
    );

    try ctx.addIssue(issue);
    diag.warn("[RETURN-STACK] {s} returned from {s}", .{ ptr_info.source_desc, func_name });
}

fn reportReturnHeapPtr(
    ctx: *PassContext,
    func_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Function returns heap-allocated pointer");
    trace[1] = try makeTraceEntry(ctx.allocator, "Pointer origin: {s} (caller must free)", .{ptr_info.source_desc});
    trace[2] = TraceEntry.init("Returning heap pointer creates ownership transfer ambiguity - who frees?");

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Function returns heap-allocated pointer ({s}) - caller may not know to free (CWE-401/CWE-662)",
        .{ptr_info.source_desc},
    );

    const issue = Issue.initWithTrace(
        .memory_leak,
        message,
        location,
        .high,
        0.72,
        trace,
    );

    try ctx.addIssue(issue);
    diag.warn("[RETURN-HEAP] {s} returned from {s} - ownership unclear", .{ ptr_info.source_desc, func_name });
}

fn reportHeapToGlobal(
    ctx: *PassContext,
    func_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Heap-allocated pointer stored to global variable");
    trace[1] = try makeTraceEntry(ctx.allocator, "Pointer origin: {s} (global lifetime)", .{ptr_info.source_desc});
    trace[2] = TraceEntry.init("Global storage of heap pointer creates leak risk - when is it freed?");

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Heap pointer ({s}) stored to global in {s} - potential memory leak if never freed (CWE-401)",
        .{ ptr_info.source_desc, func_name },
    );

    const issue = Issue.initWithTrace(
        .memory_leak,
        message,
        location,
        .high,
        0.75,
        trace,
    );

    try ctx.addIssue(issue);
    diag.warn("[HEAP-TO-GLOBAL] {s} -> global in {s}", .{ ptr_info.source_desc, func_name });
}

fn reportStackToGlobal(
    ctx: *PassContext,
    func_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Stack-local pointer stored to global variable");
    trace[1] = try makeTraceEntry(ctx.allocator, "Pointer origin: {s}", .{ptr_info.source_desc});
    trace[2] = TraceEntry.init("Global storage outlives stack frame - dangling pointer after return");

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Stack pointer ({s}) stored to global in {s} - dangling pointer after function returns (CWE-562)",
        .{ ptr_info.source_desc, func_name },
    );

    const issue = Issue.initWithTrace(
        .borrow_escape,
        message,
        location,
        .critical,
        0.90,
        trace,
    );

    try ctx.addIssue(issue);
    diag.warn("[STACK-TO-GLOBAL] {s} -> global in {s}", .{ ptr_info.source_desc, func_name });
}

fn reportUseAfterFree(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Freed pointer passed to function call");
    trace[1] = try makeTraceEntry(ctx.allocator, "Pointer origin: {s} (already freed)", .{ptr_info.source_desc});
    trace[2] = try makeTraceEntry(ctx.allocator, "Use in {s}() after free", .{callee_name});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Freed pointer ({s}) passed to {s}() - potential use-after-free (CWE-416)",
        .{ ptr_info.source_desc, callee_name },
    );

    const issue = Issue.initWithTrace(
        .use_after_free,
        message,
        location,
        .high,
        0.75,
        trace,
    );

    try ctx.addIssue(issue);
    diag.warn("[UAF-RISK] freed ptr -> {s}() in {s}", .{ callee_name, func_name });
}

fn reportResourceUAF(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    _ = inst;
    const location = Location.init(func_name);

    const resource_desc = switch (ptr_info.resource_type) {
        .dlopen_handle => "dlopen handle",
        .mmap_region => "memory mapping",
        .file_handle => "file handle",
        .socket_fd => "socket descriptor",
        .jni_ref => "JNI reference",
        .python_obj => "Python object",
        .none => "resource",
    };

    const violation_desc = switch (ptr_info.resource_type) {
        .dlopen_handle => "dlclose called while dlsym-derived pointers may still be in use",
        .mmap_region => "munmap called while pointers to mapped region may still be in use",
        .file_handle => "fclose called while FILE* may still be used",
        .socket_fd => "close called while socket fd may still be used",
        .jni_ref => "DeleteGlobalRef/DeleteLocalRef called while reference may still be in use",
        .python_obj => "Py_DECREF/Py_XDECREF called while object may still be referenced",
        .none => "resource released while still in use",
    };

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Resource used after release");
    trace[1] = try makeTraceEntry(ctx.allocator, "Resource type: {s}, origin: {s}", .{ resource_desc, ptr_info.source_desc });
    trace[2] = try makeTraceEntry(ctx.allocator, "{s} - passed to {s}()", .{ violation_desc, callee_name });

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Released {s} ({s}) passed to {s}() - potential use-after-release (CWE-416/CWE-908)",
        .{ resource_desc, ptr_info.source_desc, callee_name },
    );

    const issue = Issue.initWithTrace(
        .use_after_free,
        message,
        location,
        .critical,
        0.85,
        trace,
    );

    try ctx.addIssue(issue);
    diag.warn("[RESOURCE-UAF] {s} ({s}) -> {s}() in {s}", .{ resource_desc, ptr_info.source_desc, callee_name, func_name });
}

fn reportHeapAmbiguous(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 3);
    trace[0] = TraceEntry.init("Heap pointer passed to extern without clear ownership transfer");
    trace[1] = try makeTraceEntry(ctx.allocator, "Pointer origin: {s}", .{ptr_info.source_desc});
    trace[2] = try makeTraceEntry(ctx.allocator, "Passed to {s}() - verify ownership contract", .{callee_name});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Heap pointer ({s}) passed to {s}() - verify ownership transfer semantics (CWE-401)",
        .{ ptr_info.source_desc, callee_name },
    );

    const issue = Issue.initWithTrace(
        .memory_leak,
        message,
        location,
        .medium,
        0.60,
        trace,
    );

    try ctx.addIssue(issue);
    diag.warn("[HEAP-OWNERSHIP] {s} -> {s}() in {s}", .{ ptr_info.source_desc, callee_name, func_name });
}

fn makeTraceEntry(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !TraceEntry {
    const desc = try std.fmt.allocPrint(allocator, fmt, args);
    return TraceEntry.initOwned(desc);
}

// ============================================================================
// Tests
// ============================================================================

test "PtrLifetimePass - name and kind" {
    try std.testing.expectEqualStrings("ptr-lifetime", PtrLifetimePass.name);
    try std.testing.expectEqual(PassKind.analysis, PtrLifetimePass.kind);
}

test "is_extern_function - known patterns" {
    try std.testing.expect(is_extern_function("register_callback"));
    try std.testing.expect(is_extern_function("c_callback"));
    try std.testing.expect(is_extern_function("pthread_create"));
    try std.testing.expect(is_extern_function("signal"));
    try std.testing.expect(!is_extern_function("my_func"));
    try std.testing.expect(!is_extern_function("printf"));
}

test "may_retain_pointer - retaining patterns" {
    try std.testing.expect(may_retain_pointer("register_handler"));
    try std.testing.expect(may_retain_pointer("set_callback"));
    try std.testing.expect(may_retain_pointer("add_observer"));
    try std.testing.expect(may_retain_pointer("store_data"));
    try std.testing.expect(!may_retain_pointer("memcpy"));
    try std.testing.expect(!may_retain_pointer("printf"));
    try std.testing.expect(!may_retain_pointer("free"));
}

/// Report heap pointer escaping to FFI boundary.
/// v0.1.6: malloc/calloc results passed to retaining extern functions
/// are critical FFI ownership issues — caller may not know to free them.
fn reportHeapEscapeToFFI(
    ctx: *PassContext,
    func_name: []const u8,
    callee_name: []const u8,
    ptr_info: PtrInfo,
    inst: c.LLVMValueRef,
    diag: *DiagnosticWriter,
) !void {
    _ = inst;
    const location = Location.init(func_name);

    const trace = try ctx.allocator.alloc(TraceEntry, 4);
    trace[0] = TraceEntry.init("Heap-allocated pointer escapes to FFI boundary");
    trace[1] = try makeTraceEntry(ctx.allocator, "Pointer origin: {s} (caller must manage lifetime)", .{ptr_info.source_desc});
    trace[2] = try makeTraceEntry(ctx.allocator, "Passed to retaining FFI function {s}() - ownership transfer unclear", .{callee_name});
    trace[3] = try makeTraceEntry(ctx.allocator, "If no matching free -> leak; if double-freed -> corruption (CWE-401/CWE-662)", .{});

    const message = try std.fmt.allocPrint(
        ctx.allocator,
        "Heap pointer ({s}) escapes to {s}() in {s} - ambiguous ownership transfer",
        .{ ptr_info.source_desc, callee_name, func_name },
    );

    const issue = Issue.initWithTrace(
        .memory_leak,
        message,
        location,
        .high,
        0.78,
        trace,
    );

    try ctx.addIssue(issue);
    diag.warn("[HEAP-ESCAPE-FFI] {s} -> {s}() in {s}", .{ ptr_info.source_desc, callee_name, func_name });
}

test "PtrAllocSite - enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(PtrAllocSite.heap));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(PtrAllocSite.stack));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(PtrAllocSite.parameter));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(PtrAllocSite.global));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(PtrAllocSite.constant));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(PtrAllocSite.unknown));
}

test "LifetimeViolation - enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(LifetimeViolation.stack_escape_to_ffi));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(LifetimeViolation.return_stack_address));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(LifetimeViolation.use_after_free_risk));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(LifetimeViolation.heap_ownership_ambiguous));
}

test "PtrInfo - default fields" {
    const info = PtrInfo{
        .alloc_site = .stack,
        .source_inst = null,
        .source_desc = "test",
    };
    try std.testing.expectEqual(PtrAllocSite.stack, info.alloc_site);
    try std.testing.expect(!info.escaped);
    try std.testing.expect(!info.freed);
    try std.testing.expectEqual(@as(usize, 0), info.alloc_bb_id);
}

test "LifetimeStats - initialization" {
    const stats = LifetimeStats{};
    try std.testing.expectEqual(@as(u32, 0), stats.total_functions_analyzed);
    try std.testing.expectEqual(@as(u32, 0), stats.stack_escapes_found);
    try std.testing.expectEqual(@as(u32, 0), stats.return_stack_addr_found);
}

test "LifetimeStats - tracking" {
    var stats = LifetimeStats{};
    stats.total_functions_analyzed = 10;
    stats.total_pointers_tracked = 25;
    stats.stack_escapes_found = 3;
    stats.return_stack_addr_found = 1;
    stats.use_after_free_found = 2;
    stats.heap_ambiguous_found = 4;

    try std.testing.expectEqual(@as(u32, 10), stats.total_functions_analyzed);
    try std.testing.expectEqual(@as(u32, 25), stats.total_pointers_tracked);
    try std.testing.expectEqual(@as(u32, 3), stats.stack_escapes_found);
    try std.testing.expectEqual(@as(u32, 10), stats.stack_escapes_found + stats.return_stack_addr_found +
        stats.use_after_free_found + stats.heap_ambiguous_found);
}

test "LifetimeAnalysisResult - initialization" {
    const result = LifetimeAnalysisResult{
        .func_name = "test_function",
    };
    try std.testing.expectEqual(@as(u32, 0), result.violation_count);
    try std.testing.expectEqualStrings("test_function", result.func_name);
}

test "classify_ptr_origin - pattern matching" {
    try std.testing.expect(classify_ptr_origin(null, c.LLVMAlloca, null, std.testing.allocator) != null);
}

test "isFreeFunction - detection" {
    try std.testing.expect(PtrLifetimePass.isFreeFunction("free"));
    try std.testing.expect(PtrLifetimePass.isFreeFunction("dealloc"));
    try std.testing.expect(PtrLifetimePass.isFreeFunction("operator delete"));
    try std.testing.expect(!PtrLifetimePass.isFreeFunction("malloc"));
    try std.testing.expect(!PtrLifetimePass.isFreeFunction("printf"));
}

test "isResourceCloseFunction - detection" {
    try std.testing.expect(PtrLifetimePass.isResourceCloseFunction("dlclose"));
    try std.testing.expect(PtrLifetimePass.isResourceCloseFunction("munmap"));
    try std.testing.expect(PtrLifetimePass.isResourceCloseFunction("fclose"));
    try std.testing.expect(PtrLifetimePass.isResourceCloseFunction("close"));
    try std.testing.expect(PtrLifetimePass.isResourceCloseFunction("DeleteGlobalRef"));
    try std.testing.expect(PtrLifetimePass.isResourceCloseFunction("Py_DECREF"));
    try std.testing.expect(!PtrLifetimePass.isResourceCloseFunction("dlopen"));
    try std.testing.expect(!PtrLifetimePass.isResourceCloseFunction("malloc"));
    try std.testing.expect(!PtrLifetimePass.isResourceCloseFunction("printf"));
}

test "getResourceType - classification" {
    try std.testing.expectEqualStrings("dlhandle", PtrLifetimePass.getResourceType("dlopen"));
    try std.testing.expectEqualStrings("dlhandle", PtrLifetimePass.getResourceType("dlsym"));
    try std.testing.expectEqualStrings("mmap", PtrLifetimePass.getResourceType("mmap"));
    try std.testing.expectEqualStrings("file", PtrLifetimePass.getResourceType("fopen"));
    try std.testing.expectEqualStrings("socket", PtrLifetimePass.getResourceType("socket"));
    try std.testing.expectEqualStrings("jni", PtrLifetimePass.getResourceType("JNI_OnLoad"));
    try std.testing.expectEqualStrings("python", PtrLifetimePass.getResourceType("Py_BuildValue"));
    try std.testing.expectEqual(null, PtrLifetimePass.getResourceType("malloc"));
    try std.testing.expectEqual(null, PtrLifetimePass.getResourceType("printf"));
}

test "is_resource_alloc_function - returns ResourceType" {
    try std.testing.expectEqual(ResourceType.dlopen_handle, PtrLifetimePass.is_resource_alloc_function("dlopen"));
    try std.testing.expectEqual(ResourceType.mmap_region, PtrLifetimePass.is_resource_alloc_function("mmap"));
    try std.testing.expectEqual(ResourceType.mmap_region, PtrLifetimePass.is_resource_alloc_function("mmap64"));
    try std.testing.expectEqual(ResourceType.mmap_region, PtrLifetimePass.is_resource_alloc_function("mmap2"));
    try std.testing.expectEqual(ResourceType.mmap_region, PtrLifetimePass.is_resource_alloc_function("shm_open"));
    try std.testing.expectEqual(ResourceType.file_handle, PtrLifetimePass.is_resource_alloc_function("fopen"));
    try std.testing.expectEqual(ResourceType.socket_fd, PtrLifetimePass.is_resource_alloc_function("socket"));
    try std.testing.expectEqual(ResourceType.jni_ref, PtrLifetimePass.is_resource_alloc_function("JNI_OnLoad"));
    try std.testing.expectEqual(ResourceType.jni_ref, PtrLifetimePass.is_resource_alloc_function("Java_com_example_MyClass"));
    try std.testing.expectEqual(ResourceType.python_obj, PtrLifetimePass.is_resource_alloc_function("Py_BuildValue"));
    try std.testing.expectEqual(ResourceType.python_obj, PtrLifetimePass.is_resource_alloc_function("PyObject_Call"));
    try std.testing.expectEqual(null, PtrLifetimePass.is_resource_alloc_function("malloc"));
    try std.testing.expectEqual(null, PtrLifetimePass.is_resource_alloc_function("free"));
}

test "ResourceType - enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ResourceType.none));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ResourceType.dlopen_handle));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(ResourceType.mmap_region));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(ResourceType.file_handle));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(ResourceType.socket_fd));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(ResourceType.jni_ref));
    try std.testing.expectEqual(@as(u8, 6), @intFromEnum(ResourceType.python_obj));
}

test "is_lifecycle_bound_return - dlsym" {
    const info = PtrInfo{
        .alloc_site = .heap,
        .source_inst = null,
        .source_desc = "resource via dlsym()",
        .resource_type = .dlopen_handle,
    };
    try std.testing.expect(PtrLifetimePass.is_lifecycle_bound_return("dlsym", info));
    try std.testing.expect(!PtrLifetimePass.is_lifecycle_bound_return("malloc", info));
}

test "is_lifecycle_bound_return - mmap" {
    const info = PtrInfo{
        .alloc_site = .heap,
        .source_inst = null,
        .source_desc = "resource via mmap()",
        .resource_type = .mmap_region,
    };
    try std.testing.expect(PtrLifetimePass.is_lifecycle_bound_return("mmap", info));
    try std.testing.expect(PtrLifetimePass.is_lifecycle_bound_return("mmap64", info));
    try std.testing.expect(!PtrLifetimePass.is_lifecycle_bound_return("malloc", info));
}

test "is_lifecycle_bound_return - file/socket" {
    const file_info = PtrInfo{
        .alloc_site = .heap,
        .source_inst = null,
        .source_desc = "resource via fopen()",
        .resource_type = .file_handle,
    };
    try std.testing.expect(PtrLifetimePass.is_lifecycle_bound_return("fopen", file_info));
    try std.testing.expect(!PtrLifetimePass.is_lifecycle_bound_return("open", file_info));

    const sock_info = PtrInfo{
        .alloc_site = .heap,
        .source_inst = null,
        .source_desc = "resource via socket()",
        .resource_type = .socket_fd,
    };
    try std.testing.expect(PtrLifetimePass.is_lifecycle_bound_return("socket", sock_info));
    try std.testing.expect(!PtrLifetimePass.is_lifecycle_bound_return("accept", sock_info));
}

test "is_known_deallocator - finalize" {
    try std.testing.expect(PtrLifetimePass.is_known_deallocator("sqlite3_finalize"));
    try std.testing.expect(PtrLifetimePass.is_known_deallocator("mysql_stmt_close"));
    try std.testing.expect(PtrLifetimePass.is_known_deallocator("stmt_finalize"));
}

test "is_known_deallocator - close" {
    try std.testing.expect(PtrLifetimePass.is_known_deallocator("fclose"));
    try std.testing.expect(PtrLifetimePass.is_known_deallocator("close"));
    try std.testing.expect(PtrLifetimePass.is_known_deallocator("SSL_shutdown"));
    try std.testing.expect(PtrLifetimePass.is_known_deallocator("EVP_CIPHER_CTX_free"));
}

test "is_known_deallocator - free" {
    try std.testing.expect(PtrLifetimePass.is_known_deallocator("sqlite3_free"));
    try std.testing.expect(PtrLifetimePass.is_known_deallocator("mysql_free_result"));
    try std.testing.expect(PtrLifetimePass.is_known_deallocator("PQclear"));
    try std.testing.expect(PtrLifetimePass.is_known_deallocator("curl_easy_cleanup"));
}

test "is_known_deallocator - destroy" {
    try std.testing.expect(PtrLifetimePass.is_known_deallocator("sqlite3_close"));
    try std.testing.expect(PtrLifetimePass.is_known_deallocator("mysql_close"));
    try std.testing.expect(PtrLifetimePass.is_known_deallocator("Delete"));
    try std.testing.expect(PtrLifetimePass.is_known_deallocator("Release"));
}

test "is_known_deallocator - negative" {
    try std.testing.expect(!PtrLifetimePass.is_known_deallocator("malloc"));
    try std.testing.expect(!PtrLifetimePass.is_known_deallocator("calloc"));
    try std.testing.expect(!PtrLifetimePass.is_known_deallocator("dlopen"));
}

test "is_intentional_free - known deallocators" {
    try std.testing.expect(PtrLifetimePass.is_intentional_free("sqlite3_finalize"));
    try std.testing.expect(PtrLifetimePass.is_intentional_free("fclose"));
    try std.testing.expect(PtrLifetimePass.is_intentional_free("curl_easy_cleanup"));
}

test "is_intentional_free - resource close" {
    try std.testing.expect(PtrLifetimePass.is_intentional_free("dlclose"));
    try std.testing.expect(PtrLifetimePass.is_intentional_free("munmap"));
    try std.testing.expect(PtrLifetimePass.is_intentional_free("DeleteGlobalRef"));
    try std.testing.expect(PtrLifetimePass.is_intentional_free("Py_DECREF"));
}

test "is_intentional_free - negative" {
    try std.testing.expect(!PtrLifetimePass.is_intentional_free("malloc"));
    try std.testing.expect(!PtrLifetimePass.is_intentional_free("dlopen"));
}
