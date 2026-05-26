//! Callback Escape — Core Analysis Functions
//!
//! Extracted from callback_escape.zig to reduce file size.
//! Contains instruction scanning, callback escape detection, and malloc/free pairing logic.
//!
//! Log prefix: [callback-escape-core]

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const safe = @import("../ir/llvm_safe.zig");
const word_boundary = @import("../utils/word_boundary.zig");
const lang_classifier = @import("../pass/analysis/ffi/ffi_language_classifier.zig");

const Language = @import("../diag/issue.zig").FFIBoundary.Language;
const PlatformProfile = @import("../semantics/platform_profile.zig").PlatformProfile;

const cb_types = @import("./callback_escape_types.zig");
const AllocSiteInfo = cb_types.AllocSiteInfo;
const FreeSiteInfo = cb_types.FreeSiteInfo;
const CGoCallInfo = @import("../pass/analysis/callback_escape_report.zig").CGoCallInfo;
const CallbackEscapeInfo = @import("../pass/analysis/callback_escape_report.zig").CallbackEscapeInfo;

const isGoSafetyFunction = cb_types.isGoSafetyFunction;
const isCBytesPattern = cb_types.isCBytesPattern;
const isUnsafePtrConversion = cb_types.isUnsafePtrConversion;
const isGenericCallbackReceiver = cb_types.isGenericCallbackReceiver;
const isLikelyCallbackFunction = cb_types.isLikelyCallbackFunction;
const isGlobalVariable = cb_types.isGlobalVariable;
const isFactoryFunction = cb_types.isFactoryFunction;
const isDestructorFunction = cb_types.isDestructorFunction;
const isTransferFunction = cb_types.isTransferFunction;

pub const log_prefix = "[callback-escape-core]";

// ============================================================================
// Instruction Scanning
// ============================================================================

/// Scan a single LLVM instruction for callback escape patterns.
///
/// Populates tracking collections:
/// - keepalive_protected: pointers guarded by runtime.KeepAlive
/// - alloc_sites: malloc/calloc allocation sites
/// - free_sites: free() call sites
/// - cgo_calls: C.CBytes / unsafe.Pointer FFI boundary calls
/// - callback_escapes: detected callback escape candidates
pub fn scanInstruction(
    allocator: std.mem.Allocator,
    inst: c.LLVMValueRef,
    keepalive_protected: *std.AutoHashMap(u64, void),
    alloc_sites: *std.ArrayList(AllocSiteInfo),
    free_sites: *std.ArrayList(FreeSiteInfo),
    cgo_calls: *std.ArrayList(CGoCallInfo),
    callback_escapes: *std.ArrayList(CallbackEscapeInfo),
    is_go_module: bool,
    module_lang: Language,
    platform_profile: ?PlatformProfile,
) !void {
    const opcode = c.LLVMGetInstructionOpcode(inst);

    if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
        const called = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called) == 0) return;

        const name_ptr = c.LLVMGetValueName(called);
        if (@intFromPtr(name_ptr) == 0) return;
        const callee_name = std.mem.span(name_ptr);

        if (isGoSafetyFunction(callee_name)) {
            if (c.LLVMGetNumOperands(inst) >= 2) {
                const protected_ptr = c.LLVMGetOperand(inst, 1);
                if (@intFromPtr(protected_ptr) != 0) {
                    const ptr_val = @as(u64, @intFromPtr(protected_ptr));
                    try keepalive_protected.put(ptr_val, {});
                }
            }
        }

        if (is_go_module or
            word_boundary.isWordBoundaryMatch(callee_name, "malloc") or
            word_boundary.isWordBoundaryMatch(callee_name, "calloc"))
        {
            try alloc_sites.append(allocator, .{
                .inst_id = inst,
                .func_name = try allocator.dupe(u8, callee_name),
            });
        }

        if (word_boundary.isWordBoundaryMatch(callee_name, "free")) {
            try free_sites.append(allocator, .{
                .inst_id = inst,
                .func_name = try allocator.dupe(u8, callee_name),
            });
        }

        if (is_go_module or
            isCBytesPattern(callee_name) or
            isUnsafePtrConversion(callee_name))
        {
            const num_ops = c.LLVMGetNumOperands(inst);
            var has_ptr_arg = false;
            var i: u32 = 0;
            while (i < num_ops) : (i += 1) {
                const op = c.LLVMGetOperand(inst, i);
                if (@intFromPtr(op) != 0) {
                    const op_type = c.LLVMTypeOf(op);
                    if (@intFromPtr(op_type) == 0) continue;
                    const type_kind = c.LLVMGetTypeKind(op_type);
                    if (type_kind == c.LLVMPointerTypeKind) {
                        has_ptr_arg = true;
                        break;
                    }
                }
            }

            try cgo_calls.append(allocator, .{
                .inst = inst,
                .callee_name = try allocator.dupe(u8, callee_name),
                .is_pointer_arg = has_ptr_arg,
            });
        }
    }

    if (opcode == c.LLVMAlloca) {
        var alloca_use = c.LLVMGetFirstUse(inst);
        while (@intFromPtr(alloca_use) != 0) : (alloca_use = c.LLVMGetNextUse(alloca_use)) {
            const user = c.LLVMGetUser(alloca_use);
            if (@intFromPtr(user) == 0) continue;
            const user_opcode = c.LLVMGetInstructionOpcode(user);
            if (user_opcode == c.LLVMCall or user_opcode == c.LLVMInvoke) {
                const called_val = c.LLVMGetCalledValue(user);
                if (@intFromPtr(called_val) == 0) continue;
                const called_name_ptr = c.LLVMGetValueName(called_val);
                if (@intFromPtr(called_name_ptr) == 0) continue;
                const called_name = std.mem.span(called_name_ptr);
                // Use platform-aware classification (Bug 2 fix: Zig vs Go disambiguation)
                const callee_lang = lang_classifier.identifyCalleeLanguageWithContext(
                    called_name,
                    module_lang,
                    platform_profile,
                );
                if (callee_lang != .unknown) {
                    try callback_escapes.append(allocator, .{
                        .inst = user,
                        .receiver_name = called_name,
                        .callback_arg = inst,
                    });
                }
            }
        }
    }
}

// ============================================================================
// Callback Escape Scanning
// ============================================================================

/// Scan basic blocks for callback escape patterns.
///
/// Detects two patterns:
/// 1. Call/Invoke to generic callback receivers with function pointer args
/// 2. Store of function pointers to global variables
///
/// This unifies the duplicated scanning logic previously in both
/// analyzeFunction() and checkCallbackEscape().
pub fn scanCallbackEscapes(
    allocator: std.mem.Allocator,
    func: c.LLVMValueRef,
) !std.ArrayList(CallbackEscapeInfo) {
    var callback_escapes: std.ArrayList(CallbackEscapeInfo) = .{};
    errdefer callback_escapes.deinit(allocator);

    var bb = c.LLVMGetFirstBasicBlock(func);
    while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
        var inst = c.LLVMGetFirstInstruction(bb);
        while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
            const opcode = c.LLVMGetInstructionOpcode(inst);

            if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
                const called = c.LLVMGetCalledValue(inst);
                if (@intFromPtr(called) == 0) continue;
                const name_ptr = c.LLVMGetValueName(called);
                if (@intFromPtr(name_ptr) == 0) continue;
                const callee_name = std.mem.span(name_ptr);

                if (isGenericCallbackReceiver(callee_name)) {
                    const num_ops = c.LLVMGetNumOperands(inst);
                    var i: u32 = 0;
                    while (i < num_ops) : (i += 1) {
                        const arg = c.LLVMGetOperand(inst, i);
                        if (@intFromPtr(arg) != 0) {
                            const arg_type = c.LLVMTypeOf(arg);
                            if (@intFromPtr(arg_type) == 0) continue;
                            if (c.LLVMGetTypeKind(arg_type) == c.LLVMPointerTypeKind) {
                                const elem_type = c.LLVMGetElementType(arg_type);
                                if (@intFromPtr(elem_type) != 0 and
                                    c.LLVMGetTypeKind(elem_type) == c.LLVMFunctionTypeKind)
                                {
                                    if (isLikelyCallbackFunction(elem_type, callee_name)) {
                                        try callback_escapes.append(allocator, .{
                                            .inst = inst,
                                            .receiver_name = callee_name,
                                            .callback_arg = arg,
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if (opcode == c.LLVMStore) {
                const value_op = c.LLVMGetOperand(inst, 0);
                if (@intFromPtr(value_op) != 0) {
                    const value_type = c.LLVMTypeOf(value_op);
                    if (@intFromPtr(value_type) == 0) continue;
                    if (c.LLVMGetTypeKind(value_type) == c.LLVMPointerTypeKind) {
                        const elem_type = c.LLVMGetElementType(value_type);
                        if (@intFromPtr(elem_type) != 0 and
                            c.LLVMGetTypeKind(elem_type) == c.LLVMFunctionTypeKind)
                        {
                            const ptr_op = c.LLVMGetOperand(inst, 1);
                            if (@intFromPtr(ptr_op) != 0) {
                                if (isGlobalVariable(ptr_op)) {
                                    try callback_escapes.append(allocator, .{
                                        .inst = inst,
                                        .receiver_name = "global_store",
                                        .callback_arg = value_op,
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    return callback_escapes;
}

/// Check if a callback argument is borrowed (function pointer passed as parameter).
///
/// When a callback argument is classified as "borrowed_only" (e.g., function pointer
/// callback), it's a legitimate pattern, not an escape. This filter eliminates
/// false positives from normal callback usage.
pub fn isBorrowedCallbackArg(escape: CallbackEscapeInfo) bool {
    if (std.mem.eql(u8, escape.receiver_name, "global_store")) return false;

    const called_val = c.LLVMGetCalledValue(escape.inst);
    if (@intFromPtr(called_val) == 0) return false;

    const cb_arg_hash = @as(u64, @intFromPtr(escape.callback_arg));
    const num_ops = c.LLVMGetNumOperands(escape.inst);
    var j: u32 = 0;
    while (j < num_ops) : (j += 1) {
        const arg = c.LLVMGetOperand(escape.inst, j);
        if (@intFromPtr(arg) == 0) continue;
        const arg_hash = @as(u64, @intFromPtr(arg));
        if (arg_hash != cb_arg_hash) continue;

        const arg_type = c.LLVMTypeOf(arg);
        if (@intFromPtr(arg_type) != 0 and
            c.LLVMGetTypeKind(arg_type) == c.LLVMPointerTypeKind)
        {
            const elem_type = c.LLVMGetElementType(arg_type);
            if (@intFromPtr(elem_type) != 0 and
                c.LLVMGetTypeKind(elem_type) == c.LLVMFunctionTypeKind)
            {
                return true;
            }
        }
        break;
    }

    return false;
}

// ============================================================================
// Malloc/Free Pairing Analysis
// ============================================================================

/// Result of malloc/free pairing analysis.
pub const MallocFreePairResult = struct {
    malloc_count: u32 = 0,
    free_count: u32 = 0,
    /// True if the imbalance is explained by ownership transfer pattern
    is_pattern_suppressed: bool = false,
};

/// Count malloc/free calls and check for ownership transfer patterns.
///
/// Returns counts and whether the imbalance should be suppressed due to
/// known ownership patterns (factory/destructor/transfer functions).
pub fn countMallocFreeSites(
    alloc_sites: *const std.ArrayList(AllocSiteInfo),
    free_sites: *const std.ArrayList(FreeSiteInfo),
    func_name: []const u8,
) MallocFreePairResult {
    var result: MallocFreePairResult = .{};

    for (alloc_sites.items) |site| {
        if (word_boundary.isWordBoundaryMatch(site.func_name, "malloc") or
            word_boundary.isWordBoundaryMatch(site.func_name, "calloc") or
            word_boundary.isWordBoundaryMatch(site.func_name, "realloc"))
        {
            result.malloc_count += 1;
        }
    }

    for (free_sites.items) |site| {
        if (word_boundary.isWordBoundaryMatch(site.func_name, "free")) {
            result.free_count += 1;
        }
    }

    if (isFactoryFunction(func_name)) {
        if (result.malloc_count > result.free_count) {
            result.is_pattern_suppressed = true;
        }
    }

    if (isDestructorFunction(func_name)) {
        if (result.free_count > result.malloc_count) {
            result.is_pattern_suppressed = true;
        }
    }

    if (isTransferFunction(func_name)) {
        result.is_pattern_suppressed = true;
    }

    return result;
}
