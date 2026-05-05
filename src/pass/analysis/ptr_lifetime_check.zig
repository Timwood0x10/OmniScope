const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

const memory_graph = @import("../semantics/memory_graph.zig");
const output_param_classifier = @import("output_param_classifier.zig");

const PassContext = @import("../pass.zig").PassContext;
const DiagnosticWriter = @import("../../diag/diagnostic_writer.zig").DiagnosticWriter;
const Lang = @import("../../semantics/zone_classifier.zig").Lang;
const toZoneLanguage = @import("../../semantics/zone_classifier.zig").toZoneLanguage;

const PtrInfo = @import("ptr_lifetime_types.zig").PtrInfo;
const PtrAllocSite = @import("ptr_lifetime_types.zig").PtrAllocSite;
const FreeSiteRecord = @import("ptr_lifetime_types.zig").FreeSiteRecord;
const FreeSiteList = @import("ptr_lifetime_types.zig").FreeSiteList;
const LifetimeStats = @import("ptr_lifetime_types.zig").LifetimeStats;
const ResourceType = @import("ptr_lifetime_types.zig").ResourceType;
const HEAP_ALLOC_FUNCTIONS = @import("ptr_lifetime_types.zig").HEAP_ALLOC_FUNCTIONS;
const may_retain_pointer = @import("ptr_lifetime_types.zig").may_retain_pointer;
const is_extern_function = @import("ptr_lifetime_types.zig").is_extern_function;
const getAllocatorKB = @import("ptr_lifetime_types.zig").getAllocatorKB;
const isFreeFunction = @import("ptr_lifetime_classify.zig").isFreeFunction;
const report = @import("ptr_lifetime_report.zig");

/// Violation checking logic for PtrLifetimePass.
/// Extracted from ptr_lifetime.zig for code organization.
///
/// This module contains all violation detection functions:
/// - Double-free detection (path-sensitive)
/// - Call violations (stack escape, use-after-free, heap escape)
/// - Return violations (borrow escape, stack address return)
/// - Store-to-global violations
pub fn checkViolations(
    ctx: *PassContext,
    inst: c.LLVMValueRef,
    func: c.LLVMValueRef,
    func_name: []const u8,
    bb_id: usize,
    bb_ref: c.LLVMValueRef,
    pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
    mem_graph: ?*memory_graph.MemoryGraph,
    diag: *DiagnosticWriter,
    stats: *LifetimeStats,
    free_sites: *std.AutoHashMap(u64, FreeSiteList),
) !void {
    if (@intFromPtr(inst) == 0) return;

    const opcode = c.LLVMGetInstructionOpcode(inst);

    if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
        try checkDoubleFreeViolation(ctx, inst, func_name, bb_id, bb_ref, pointer_map, mem_graph, diag, stats, free_sites);
        try checkCallViolation(ctx, inst, func, func_name, bb_id, pointer_map, mem_graph, diag, stats);
    }

    if (opcode == c.LLVMRet) {
        try checkReturnViolation(ctx, inst, func, func_name, pointer_map, mem_graph, diag, stats);
    }

    if (opcode == c.LLVMStore) {
        try checkStoreToGlobal(ctx, inst, func_name, pointer_map, diag, stats);
    }
}

pub fn checkDoubleFreeViolation(
    ctx: *PassContext,
    inst: c.LLVMValueRef,
    func_name: []const u8,
    bb_id: usize,
    bb_ref: c.LLVMValueRef,
    pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
    mem_graph: ?*memory_graph.MemoryGraph,
    diag: *DiagnosticWriter,
    stats: *LifetimeStats,
    free_sites: *std.AutoHashMap(u64, FreeSiteList),
) !void {
    const called = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called) == 0) return;

    const name_ptr = c.LLVMGetValueName(called);
    if (@intFromPtr(name_ptr) == 0) return;

    const callee_name = std.mem.span(name_ptr);

    if (!isFreeFunction(callee_name)) return;

    const ptr_arg = c.LLVMGetOperand(inst, 0);
    const ptr_hash = @as(u64, @intFromPtr(ptr_arg));

    const record = FreeSiteRecord{
        .bb_id = bb_id,
        .bb_ref = bb_ref,
        .free_inst = inst,
    };

    const gop = try free_sites.getOrPut(ptr_hash);
    if (!gop.found_existing) {
        gop.value_ptr.* = FreeSiteList.init(ctx.allocator);
    }
    try gop.value_ptr.append(record);

    const sites = free_sites.get(ptr_hash) orelse return;
    if (sites.len <= 1) return;

    const prev_record = sites.items[sites.len - 2];
    if (areMutuallyExclusive(prev_record.bb_ref, bb_ref)) {
        diag.debug("[SUPPRESSED] Double-free on mutually exclusive paths in {s} (bb {} vs bb {})", .{ func_name, prev_record.bb_id, bb_id });
        return;
    }

    if (isRCPatternFree(prev_record.bb_ref) or isRCPatternFree(bb_ref)) {
        diag.debug("[SUPPRESSED] Double-free under RC==0 guard in {s}", .{func_name});
        return;
    }

    if (mem_graph) |mg| {
        const inst_ptr = @as(u64, @intFromPtr(inst));
        const free_lang: Lang = toZoneLanguage(ctx.module_language.language);
        const is_double = mg.trackFree(inst_ptr, ptr_hash, free_lang) catch false;
        if (is_double) {
            if (!ctx.isRelevantAlloc(ptr_hash)) return;
            diag.warn("[DOUBLE_FREE] MemoryGraph detected double-free of pointer in {s}", .{func_name});
            stats.use_after_free_found += 1;
            return;
        }
    }

    if (pointer_map.get(ptr_arg)) |ptr_info| {
        if (ptr_info.double_free_detected) {
            if (!ctx.isRelevantAlloc(ptr_hash)) return;
            diag.warn("[DOUBLE_FREE] {s} freed twice in {s}", .{ ptr_info.source_desc, func_name });
            stats.use_after_free_found += 1;
        }
    }
}

fn areMutuallyExclusive(bb1: c.LLVMValueRef, bb2: c.LLVMValueRef) bool {
    if (@intFromPtr(bb1) == 0 or @intFromPtr(bb2) == 0) return false;
    if (@intFromPtr(bb1) == @intFromPtr(bb2)) return false;

    const pred1 = getSinglePredecessor(@ptrCast(bb1));
    const pred2 = getSinglePredecessor(@ptrCast(bb2));

    if (@intFromPtr(pred1) == 0 or @intFromPtr(pred2) == 0) return false;
    if (@intFromPtr(pred1) != @intFromPtr(pred2)) return false;

    const num_successors = c.LLVMGetNumSuccessors(pred1);
    if (num_successors != 2) return false;

    const succ0 = c.LLVMGetSuccessor(pred1, 0);
    const succ1 = c.LLVMGetSuccessor(pred1, 1);

    const match = (@intFromPtr(succ0) == @intFromPtr(bb1) and @intFromPtr(succ1) == @intFromPtr(bb2)) or
        (@intFromPtr(succ0) == @intFromPtr(bb2) and @intFromPtr(succ1) == @intFromPtr(bb1));
    return match;
}

fn getSinglePredecessor(bb: c.LLVMBasicBlockRef) c.LLVMValueRef {
    const func = c.LLVMGetBasicBlockParent(bb);
    if (@intFromPtr(func) == 0) return null;

    var result: c.LLVMValueRef = null;
    var cur_bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(cur_bb) != 0) : (cur_bb = c.LLVMGetNextBasicBlock(cur_bb)) {
        const term = c.LLVMGetBasicBlockTerminator(cur_bb);
        if (@intFromPtr(term) == 0) continue;

        const num_succ = c.LLVMGetNumSuccessors(term);
        var i: u32 = 0;
        while (i < num_succ) : (i += 1) {
            const succ = c.LLVMGetSuccessor(term, i);
            if (@intFromPtr(succ) == @intFromPtr(bb)) {
                if (@intFromPtr(result) != 0) {
                    return null;
                }
                result = @ptrCast(cur_bb);
            }
        }
    }
    return result;
}

fn isRCPatternFree(bb: c.LLVMValueRef) bool {
    if (@intFromPtr(bb) == 0) return false;

    var inst = c.LLVMGetFirstInstruction(@ptrCast(bb));
    var has_sub_one: bool = false;
    var has_cmp_zero: bool = false;

    while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
        const opcode = c.LLVMGetInstructionOpcode(inst);

        if (opcode == c.LLVMSub) {
            if (c.LLVMGetNumOperands(inst) >= 2) {
                const rhs = c.LLVMGetOperand(inst, 1);
                if (c.LLVMIsAConstantInt(rhs) != null) {
                    const val = c.LLVMConstIntGetZExtValue(rhs);
                    if (val == 1) {
                        has_sub_one = true;
                    }
                }
            }
        }

        if (opcode == c.LLVMICmp) {
            if (c.LLVMGetNumOperands(inst) >= 2) {
                const rhs = c.LLVMGetOperand(inst, 1);
                if (c.LLVMIsAConstantInt(rhs) != null) {
                    const val = c.LLVMConstIntGetZExtValue(rhs);
                    if (val == 0) {
                        has_cmp_zero = true;
                    }
                }
            }
        }
    }

    return has_sub_one and has_cmp_zero;
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

pub fn checkCallViolation(
    ctx: *PassContext,
    inst: c.LLVMValueRef,
    _: c.LLVMValueRef,
    func_name: []const u8,
    _: usize,
    pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
    mem_graph: ?*memory_graph.MemoryGraph,
    diag: *DiagnosticWriter,
    stats: *LifetimeStats,
) !void {
    const called = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called) == 0) return;

    const name_ptr = c.LLVMGetValueName(called);
    if (@intFromPtr(name_ptr) == 0) return;

    const callee_name = std.mem.span(name_ptr);

    // For stack-escape detection, check ALL extern/FFI calls (not just retaining ones).
    // Passing a stack address to any external function is dangerous — the callee
    // may store it for async use, and the stack frame will be gone when it fires.
    const is_extern = is_extern_function(callee_name);
    const should_check_stack_escape = is_extern or may_retain_pointer(callee_name);

    if (!should_check_stack_escape) return;

    if (mem_graph) |mg| {
        const callee_ptr = @as(u64, @intFromPtr(called));
        const callee_counter = mg.getFuncCounter(callee_ptr);

        const callee_returns_ptr = if (callee_counter.hasHeapOps())
            callee_counter.returns_pointer
        else blk: {
            const ret_type = c.LLVMTypeOf(inst);
            if (@intFromPtr(ret_type) != 0 and
                c.LLVMGetTypeKind(ret_type) == c.LLVMPointerTypeKind)
            {
                break :blk true;
            }
            break :blk false;
        };

        if (!callee_returns_ptr) {
            const num_ops = c.LLVMGetNumOperands(inst);
            var i: u32 = 0;
            while (i < num_ops) : (i += 1) {
                const arg = c.LLVMGetOperand(inst, i);
                if (pointer_map.get(arg)) |ptr_info| {
                    if (ptr_info.alloc_site == .stack and !ptr_info.escaped) {
                        try reportStackEscape(ctx, func_name, callee_name, ptr_info, inst, diag);
                        stats.stack_escapes_found += 1;
                        if (pointer_map.getPtr(arg)) |pi| pi.escaped = true;
                    } else if (ptr_info.freed) {
                        if (!ctx.isRelevantAlloc(@as(u64, @intFromPtr(arg)))) continue;
                        if (ptr_info.resource_type != .none) {
                            try reportResourceUAF(ctx, func_name, callee_name, ptr_info, inst, diag);
                        } else {
                            try reportUseAfterFree(ctx, func_name, callee_name, ptr_info, inst, diag);
                        }
                        stats.use_after_free_found += 1;
                    }
                }
            }
            return;
        }
    }

    const num_ops = c.LLVMGetNumOperands(inst);
    var i: u32 = 0;
    while (i < num_ops) : (i += 1) {
        const arg = c.LLVMGetOperand(inst, i);
        if (pointer_map.get(arg)) |ptr_info| {
            if (ptr_info.alloc_site == .stack and !ptr_info.escaped) {
                if (isStackEscapeSuppressed(callee_name, ptr_info)) {
                    diag.debug("[SUPPRESSED] Stack escape in callback/hook: {s}", .{callee_name});
                    stats.stack_escapes_found += 1;
                } else {
                    try reportStackEscape(ctx, func_name, callee_name, ptr_info, inst, diag);
                    stats.stack_escapes_found += 1;
                }
                if (pointer_map.getPtr(arg)) |pi| pi.escaped = true;
            } else if (ptr_info.alloc_site == .heap and !ptr_info.escaped) {
                try reportHeapEscapeToFFI(ctx, func_name, callee_name, ptr_info, inst, diag);
                stats.heap_ambiguous_found += 1;
                if (pointer_map.getPtr(arg)) |pi| pi.escaped = true;
            } else if (ptr_info.freed) {
                if (!ctx.isRelevantAlloc(@as(u64, @intFromPtr(arg)))) continue;
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

pub fn checkReturnViolation(
    ctx: *PassContext,
    inst: c.LLVMValueRef,
    func: c.LLVMValueRef,
    func_name: []const u8,
    pointer_map: *std.AutoHashMap(c.LLVMValueRef, PtrInfo),
    mem_graph: ?*memory_graph.MemoryGraph,
    diag: *DiagnosticWriter,
    stats: *LifetimeStats,
) !void {
    const num_ops = c.LLVMGetNumOperands(inst);
    if (num_ops == 0) return;

    if (isCppDestructorOrConstructor(func_name)) {
        return;
    }

    if (output_param_classifier.OutputParamClassifier.isLikelyOutputParamFunction(func_name)) {
        diag.debug("[SUPPRESSED] C API output parameter pattern: {s} (known output-param family)", .{func_name});
        stats.heap_intentional_transfer += 1;
        return;
    }

    if (isNonPointerReturnType(inst)) {
        diag.debug("[SUPPRESSED] C API output parameter pattern: {s} returns non-pointer (likely using output params)", .{func_name});
        return;
    }

    const retval = c.LLVMGetOperand(inst, 0);

    if (mem_graph) |mg| {
        const retval_ptr = @as(u64, @intFromPtr(retval));
        const source = mg.getSourceKind(retval_ptr);
        if (source == .heap_alloc or source == .resource_alloc) {
            diag.debug("[SUPPRESSED] Return value is heap/resource allocation (MemoryGraph): {s}", .{func_name});
            stats.heap_intentional_transfer += 1;
            return;
        }

        const func_ptr = @as(u64, @intFromPtr(func));
        const counter = mg.getFuncCounter(func_ptr);
        if (counter.hasHeapOps() and counter.net() > 0) {
            diag.debug("[SUPPRESSED] Function has net heap allocations ({d} allocs, {d} frees): {s}", .{ counter.allocs, counter.frees, func_name });
            stats.heap_intentional_transfer += 1;
            return;
        }

        const retval_opcode = c.LLVMGetInstructionOpcode(retval);
        if (retval_opcode == c.LLVMCall or retval_opcode == c.LLVMInvoke) {
            const callee_val = c.LLVMGetCalledValue(retval);
            if (@intFromPtr(callee_val) != 0) {
                const callee_ptr = @as(u64, @intFromPtr(callee_val));
                const callee_counter = mg.getFuncCounter(callee_ptr);
                if (callee_counter.hasHeapOps() and callee_counter.net() > 0) {
                    diag.debug("[SUPPRESSED] Callee has net heap allocations ({d} allocs, {d} frees): {s} -> {s}", .{
                        callee_counter.allocs,
                        callee_counter.frees,
                        func_name,
                        std.mem.span(c.LLVMGetValueName(callee_val)),
                    });
                    stats.heap_intentional_transfer += 1;
                    return;
                }
            }
        }
    }

    const retval_opcode = c.LLVMGetInstructionOpcode(retval);
    if (retval_opcode == c.LLVMCall or retval_opcode == c.LLVMInvoke) {
        const called_val = c.LLVMGetCalledValue(retval);
        if (@intFromPtr(called_val) != 0) {
            const callee_name_ptr = c.LLVMGetValueName(called_val);
            if (@intFromPtr(callee_name_ptr) != 0) {
                const callee_name = std.mem.span(callee_name_ptr);
                if (getAllocatorKB()) |kb| {
                    if (kb.isAllocator(callee_name)) {
                        diag.debug("[SUPPRESSED] Return value from known allocator {s} in {s}", .{ callee_name, func_name });
                        stats.heap_intentional_transfer += 1;
                        return;
                    }
                }
                for (HEAP_ALLOC_FUNCTIONS) |alloc_fn| {
                    if (std.mem.indexOf(u8, callee_name, alloc_fn) != null) {
                        diag.debug("[SUPPRESSED] Return value from heap alloc {s} in {s}", .{ callee_name, func_name });
                        stats.heap_intentional_transfer += 1;
                        return;
                    }
                }
            }
        }
    }

    if (pointer_map.get(retval)) |ptr_info| {
        if (ptr_info.alloc_site == .stack) {
            if (ptr_info.is_param_storage) {
                diag.debug("[SUPPRESSED] Param storage alloca (not a real stack escape): {s}", .{func_name});
                stats.heap_intentional_transfer += 1;
            } else if (isSretAlloca(retval, inst, func)) {
                diag.debug("[SUPPRESSED] Sret alloca (return value slot, not real stack escape): {s}", .{func_name});
                stats.heap_intentional_transfer += 1;
            } else if (isAllocaReturnSuppressed(func_name, ptr_info)) {
                diag.debug("[SUPPRESSED] Alloca return in constructor/factory: {s}", .{func_name});
                stats.heap_intentional_transfer += 1;
            } else {
                try reportReturnStackAddr(ctx, func_name, ptr_info, inst, diag);
                stats.return_stack_addr_found += 1;
            }
        } else if (ptr_info.alloc_site == .heap) {
            if (!isIntentionalOwnershipTransfer(func_name)) {
                // Note: ip_ffi import would go here in full extraction
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

fn isSretAlloca(retval: c.LLVMValueRef, _: c.LLVMValueRef, func: c.LLVMValueRef) bool {
    if (c.LLVMGetInstructionOpcode(retval) != c.LLVMAlloca) return false;

    const alloca_type = c.LLVMGetAllocatedType(retval);
    if (@intFromPtr(alloca_type) == 0) return false;
    if (c.LLVMGetTypeKind(alloca_type) != c.LLVMPointerTypeKind) return false;

    const func_ptr_type = c.LLVMTypeOf(func);
    if (@intFromPtr(func_ptr_type) == 0) return false;
    const func_type = c.LLVMGetElementType(func_ptr_type);
    if (@intFromPtr(func_type) == 0) return false;
    if (c.LLVMGetTypeKind(func_type) != c.LLVMFunctionTypeKind) return false;
    const ret_type = c.LLVMGetReturnType(func_type);
    if (@intFromPtr(ret_type) == 0) return false;
    if (c.LLVMGetTypeKind(ret_type) != c.LLVMPointerTypeKind) return false;

    return true;
}

fn isAllocaReturnSuppressed(func_name: []const u8, ptr_info: PtrInfo) bool {
    if (!std.mem.startsWith(u8, ptr_info.source_desc, "stack")) return false;

    const factory_suffixes = [_][]const u8{
        "New",  "Create", "Make",  "Alloc", "AllocX",
        "Init", "Open",   "Build", "From",  "Copy",
    };
    for (factory_suffixes) |suffix| {
        if (std.mem.endsWith(u8, func_name, suffix)) return true;
    }

    const factory_substrings = [_][]const u8{
        "Expr",     "Select",   "Token",        "SrcList",     "Name",
        "Trigger",  "CollSeq",  "Vtab",         "Module",      "Malloc",
        "Alloc",    "Realloc",  "Hash",         "List",        "Table",
        "Cache",    "Pool",     "Hook",         "Callback",    "Handler",
        "Notifier", "Observer", "busy_handler", "commit_hook", "rollback_hook",
        "wal_hook",
    };
    for (factory_substrings) |sub| {
        if (std.mem.indexOf(u8, func_name, sub) != null) {
            const factory_prefixes = [_][]const u8{
                "sqlite3",  "rowSet",    "alloc", "create",
                "vtab",     "attach",    "token", "curl_",
                "uv_",      "json_",     "xml_",  "ldap_",
                "avcodec_", "avformat_",
            };
            for (factory_prefixes) |prefix| {
                if (std.mem.startsWith(u8, func_name, prefix)) return true;
            }
            if (std.mem.indexOf(u8, func_name, "Hook") != null or
                std.mem.indexOf(u8, func_name, "Callback") != null or
                std.mem.indexOf(u8, func_name, "Handler") != null or
                std.mem.indexOf(u8, func_name, "busy_handler") != null or
                std.mem.indexOf(u8, func_name, "_hook") != null)
            {
                return true;
            }
        }
    }

    return false;
}

// Stub functions for reporting - these would be defined in the main module or extracted separately
fn reportHeapToGlobal(ctx: *PassContext, func_name: []const u8, ptr_info: PtrInfo, inst: c.LLVMValueRef, diag: *DiagnosticWriter) !void {
    _ = ctx;
    _ = func_name;
    _ = ptr_info;
    _ = inst;
    _ = diag;
}

fn reportStackToGlobal(ctx: *PassContext, func_name: []const u8, ptr_info: PtrInfo, inst: c.LLVMValueRef, diag: *DiagnosticWriter) !void {
    try report.reportStackToGlobal(ctx, func_name, ptr_info, inst, diag);
}

fn reportResourceUAF(ctx: *PassContext, func_name: []const u8, callee_name: []const u8, ptr_info: PtrInfo, inst: c.LLVMValueRef, diag: *DiagnosticWriter) !void {
    try report.reportResourceUAF(ctx, func_name, callee_name, ptr_info, inst, diag);
}

fn reportUseAfterFree(ctx: *PassContext, func_name: []const u8, callee_name: []const u8, ptr_info: PtrInfo, inst: c.LLVMValueRef, diag: *DiagnosticWriter) !void {
    try report.reportUseAfterFree(ctx, func_name, callee_name, ptr_info, inst, diag);
}

fn reportStackEscape(ctx: *PassContext, func_name: []const u8, callee_name: []const u8, ptr_info: PtrInfo, inst: c.LLVMValueRef, diag: *DiagnosticWriter) !void {
    try report.reportStackEscape(ctx, func_name, callee_name, ptr_info, inst, diag);
}

fn reportHeapEscapeToFFI(ctx: *PassContext, func_name: []const u8, callee_name: []const u8, ptr_info: PtrInfo, inst: c.LLVMValueRef, diag: *DiagnosticWriter) !void {
    try report.reportHeapEscapeToFFI(ctx, func_name, callee_name, ptr_info, inst, diag);
}

fn reportReturnStackAddr(ctx: *PassContext, func_name: []const u8, ptr_info: PtrInfo, inst: c.LLVMValueRef, diag: *DiagnosticWriter) !void {
    try report.reportReturnStackAddr(ctx, func_name, ptr_info, inst, diag);
}

fn reportReturnHeapPtr(ctx: *PassContext, func_name: []const u8, ptr_info: PtrInfo, inst: c.LLVMValueRef, diag: *DiagnosticWriter) !void {
    try report.reportReturnHeapPtr(ctx, func_name, ptr_info, inst, diag);
}

fn isStackEscapeSuppressed(callee_name: []const u8, ptr_info: PtrInfo) bool {
    _ = callee_name;
    _ = ptr_info;
    return false;
}

fn isIntentionalOwnershipTransfer(func_name: []const u8) bool {
    _ = func_name;
    return false;
}

fn isNonPointerReturnType(inst: c.LLVMValueRef) bool {
    _ = inst;
    return false;
}
