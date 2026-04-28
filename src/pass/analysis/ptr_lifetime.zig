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

/// Check if a callee name looks like an extern/FFI function.
pub fn isExternFunction(name: []const u8) bool {
    if (name.len == 0) return false;

    for (FFI_RETAINING_FUNCTIONS) |func| {
        if (std.mem.indexOf(u8, name, func) != null) return true;
    }

    for (CALLBACK_TAKING_FUNCTIONS) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) return true;
    }

    return false;
}

/// Check if a function may store/retain its pointer argument.
pub fn mayRetainPointer(callee_name: []const u8) bool {
    if (isExternFunction(callee_name)) return true;

    const retaining_patterns = [_][]const u8{
        "register_", "set_",  "add_",   "insert_", "push_",
        "store_",    "save_", "cache_", "copy_",
    };

    for (retaining_patterns) |pat| {
        if (std.mem.startsWith(u8, callee_name, pat)) return true;
    }

    return false;
}

// ============================================================================
// Allocation Site Detection
// ============================================================================

/// Heap allocation functions.
const HEAP_ALLOC_FUNCTIONS = &[_][]const u8{
    "malloc",         "calloc",   "realloc",   "aligned_alloc",
    "valloc",         "pvalloc",  "memalign",  "operator new",
    "operator new[]", "into_raw", "allocImpl",
};

/// Classify the allocation site of a pointer value.
pub fn classifyPtrOrigin(
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

        var stats = LifetimeStats{};

        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            try analyzeFunction(ctx, func, diag, &stats);
        }

        diag.info("PtrLifetime: analyzed {} funcs, tracked {} ptrs, found {} violations", .{
            stats.total_functions_analyzed,
            stats.total_pointers_tracked,
            stats.stack_escapes_found + stats.return_stack_addr_found + stats.use_after_free_found + stats.heap_ambiguous_found,
        });
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
                                };
                                try putPtrInfo(pointer_map, inst, info, allocator);
                                stats.total_pointers_tracked += 1;
                                break;
                            }
                        }

                        if (isFreeFunction(callee_name)) {
                            const ptr_arg = c.LLVMGetOperand(inst, 0);
                            if (pointer_map.getPtr(ptr_arg)) |ptr_info| {
                                ptr_info.freed = true;
                            }
                        }
                    }
                }
            },

            c.LLVMLoad => {
                try propagateOrigin(inst, c.LLVMGetOperand(inst, 0), pointer_map, allocator, bb_id);
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
        if (gop.found_existing) {
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
        return value_kind == c.LLVMGlobalVariableValueKind or
            c.LLVMIsAGlobalVar(ptr) != 0;
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

        if (!mayRetainPointer(callee_name)) return;

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
                    try reportUseAfterFree(ctx, func_name, callee_name, ptr_info, inst, diag);
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

        const retval = c.LLVMGetOperand(inst, 0);
        if (pointer_map.get(retval)) |ptr_info| {
            if (ptr_info.alloc_site == .stack) {
                try reportReturnStackAddr(ctx, func_name, ptr_info, inst, diag);
                stats.return_stack_addr_found += 1;
            } else if (ptr_info.alloc_site == .heap) {
                if (!isIntentionalOwnershipTransfer(func_name)) {
                    try reportReturnHeapPtr(ctx, func_name, ptr_info, inst, diag);
                    stats.heap_ambiguous_found += 1;
                } else {
                    diag.debug("[SUPPRESSED] Heap return in factory function: {s} (intentional ownership transfer)", .{func_name});
                    stats.heap_intentional_transfer += 1;
                }
            }
        }
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

test "isExternFunction - known patterns" {
    try std.testing.expect(isExternFunction("register_callback"));
    try std.testing.expect(isExternFunction("c_callback"));
    try std.testing.expect(isExternFunction("pthread_create"));
    try std.testing.expect(isExternFunction("signal"));
    try std.testing.expect(!isExternFunction("my_func"));
    try std.testing.expect(!isExternFunction("printf"));
}

test "mayRetainPointer - retaining patterns" {
    try std.testing.expect(mayRetainPointer("register_handler"));
    try std.testing.expect(mayRetainPointer("set_callback"));
    try std.testing.expect(mayRetainPointer("add_observer"));
    try std.testing.expect(mayRetainPointer("store_data"));
    try std.testing.expect(!mayRetainPointer("memcpy"));
    try std.testing.expect(!mayRetainPointer("printf"));
    try std.testing.expect(!mayRetainPointer("free"));
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

test "classifyPtrOrigin - pattern matching" {
    try std.testing.expect(classifyPtrOrigin(null, c.LLVMAlloca, null, std.testing.allocator) != null);
}

test "isFreeFunction - detection" {
    try std.testing.expect(PtrLifetimePass.isFreeFunction("free"));
    try std.testing.expect(PtrLifetimePass.isFreeFunction("dealloc"));
    try std.testing.expect(PtrLifetimePass.isFreeFunction("operator delete"));
    try std.testing.expect(!PtrLifetimePass.isFreeFunction("malloc"));
    try std.testing.expect(!PtrLifetimePass.isFreeFunction("printf"));
}
