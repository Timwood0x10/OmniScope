//! Rules 9-10: Advanced FFI Safety Detection
//!
//! This module implements advanced Rust FFI safety rules:
//!   - Rule 9: Write to immutable (store through pointer from const-qualified struct field)
//!   - Rule 10: Use after free (post-free pointer use within same function)
//!
//! Plus tracing, GEP, DI metadata, and UAF helper functions.
//!
//! All functions are standalone (not methods) and take auditor as first parameter.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const tracking = @import("../ptr_lifetime/value_tracking.zig");

const PassContext = @import("../../pass.zig").PassContext;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;
const Issue = @import("../../../diag/issue.zig").Issue;
const Location = @import("../../../diag/issue.zig").Location;
const TraceEntry = @import("../../../diag/issue.zig").TraceEntry;

const rust_ffi_helpers = @import("rust_ffi_helpers.zig");
const getFunctionName = rust_ffi_helpers.getFunctionName;

const SemanticKind = @import("../../../semantics/semantic_tree.zig").SemanticKind;

// Import enhanced drop glue detector
const drop_glue = @import("../../../semantics/patterns/drop_glue.zig");

/// Auditor type
const Auditor = @import("rust_ffi_auditor.zig").RustFfiAuditor;

// Import helpers from other modules
const lifetime = @import("rust_ffi_rules_lifetime.zig");
const hasStructDebugMetadata = lifetime.hasStructDebugMetadata;
const instructionUsesValue = lifetime.instructionUsesValue;

// ============================================================================
// Rule 9: Write to Immutable Detection
// ============================================================================

/// Rule 9: Detect write-to-immutable violations.
/// `insts` is the pre-collected instruction list from auditFunction (no re-traversal).
pub fn detectWriteToImmutable(auditor: *Auditor, func: c.LLVMValueRef, insts: []const c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
    const func_name = getFunctionName(func);

    // Pass 1: Collect all struct field pointers loaded in this function
    const MaxFieldPtrs: usize = 32;
    var field_ptr_count: usize = 0;
    var struct_field_ptrs: [MaxFieldPtrs]c.LLVMValueRef = undefined;

    for (insts) |inst| {
        if (c.LLVMGetInstructionOpcode(inst) != c.LLVMLoad) continue;

        const load_src = c.LLVMGetOperand(inst, 0);
        if (@intFromPtr(load_src) == 0) continue;
        if (c.LLVMGetInstructionOpcode(load_src) != c.LLVMGetElementPtr) continue;

        const gep_base = c.LLVMGetOperand(load_src, 0);
        if (@intFromPtr(gep_base) == 0) continue;

        const num_gep_operands = c.LLVMGetNumOperands(load_src);
        const is_struct_gep = num_gep_operands >= 3;

        const has_dbg_metadata = hasStructDebugMetadata(load_src);

        if (!is_struct_gep and !has_dbg_metadata) continue;

        if (field_ptr_count < MaxFieldPtrs) {
            struct_field_ptrs[field_ptr_count] = inst;
            field_ptr_count += 1;
        }
    }

    if (field_ptr_count == 0) return;

    // Pass 2: Check each store instruction for writes through struct field pointers
    for (insts) |inst| {
        if (c.LLVMGetInstructionOpcode(inst) != c.LLVMStore) continue;

        const dest_ptr = c.LLVMGetOperand(inst, 1);
        if (@intFromPtr(dest_ptr) == 0) continue;

        for (struct_field_ptrs[0..field_ptr_count]) |field_load| {
            if (ptrTracesTo(dest_ptr, field_load)) {
                // SRT query: trace through def-use chain to check interior mutability
                // If the value is derived from UnsafeCell, this is legal interior mutability
                if (ctx.semantic_resolution) |resolution_engine| {
                    const srt = resolution_engine.getSemanticTree();
                    if (srt.*.traceToInteriorMutability(dest_ptr, 8)) {
                        // Interior mutability via UnsafeCell — legal write
                        continue;
                    }

                    // R-0: Check if dest traces back to a mutable_param (&mut T).
                    // In LLVM IR: Rust's &mut T → NO readonly attribute.
                    // Writing to a pointer derived from &mut T is legal.
                    // Only writing to readonly_param (&T) is a true immutable violation.
                    if (isFromMutableParamSRT(dest_ptr, func, srt)) {
                        // Base is from &mut T — legal write, skip
                        continue;
                    }
                }

                // Check if the base pointer is from a readonly parameter.
                // In Rust: &T → readonly, &mut T → NOT readonly.
                // If the base is NOT from a readonly param, the write is legal (&mut T).
                const gep_base = c.LLVMGetOperand(field_load, 0);
                if (@intFromPtr(gep_base) != 0 and !isFromReadonlyParam(gep_base, func)) {
                    // Base is from &mut T — legal write, skip
                    continue;
                }

                const struct_name = getStructNameForValue(field_load) orelse "unknown_struct";

                const trace = try auditor.allocator.alloc(TraceEntry, 4);
                errdefer auditor.allocator.free(trace);
                trace[0] = TraceEntry.init("Write through pointer loaded from struct field");
                trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(auditor.allocator, "Struct: {s} — field pointer used as write destination", .{struct_name}));
                trace[2] = TraceEntry.init("Writing to memory via struct field pointer may violate immutability");
                trace[3] = TraceEntry.init("Original data owner may assume field content is read-only");

                const message = try std.fmt.allocPrint(
                    auditor.allocator,
                    "Write to immutable memory via struct '{s}' field pointer — potential violation of immutability contract (CWE-757)",
                    .{struct_name},
                );

                var issue = Issue.initWithTrace(
                    .write_to_immutable,
                    message,
                    Location.init(func_name),
                    .high,
                    0.85,
                    trace,
                );
                errdefer issue.deinit(auditor.allocator);

                try ctx.addIssue(&issue);
                diag.warn("[OMI-HIGH] [WRITE-IMMUTABLE] struct '{s}' in {s}", .{ struct_name, func_name });
                break;
            }
        }
    }
}

// ============================================================================
// Tracing Helpers
// ============================================================================

/// Check if `user_value` ultimately derives from `source_value`.
pub fn ptrTracesTo(user_value: c.LLVMValueRef, source_value: c.LLVMValueRef) bool {
    return tracking.valueTracesTo(user_value, source_value);
}

/// Check if a value is derived from a function parameter that has `readonly` attribute.
/// In LLVM IR: Rust's &T (shared reference) → readonly, &mut T (mutable reference) → no readonly.
/// Returns true ONLY if the value traces to a readonly parameter.
/// Returns false if: (a) not a parameter, (b) parameter is NOT readonly, or (c) can't determine.
///
/// This is the key heuristic: if the store destination is from a non-readonly param,
/// the write is to &mut T and is legal (not a write_to_immutable violation).
pub fn isFromReadonlyParam(value: c.LLVMValueRef, enclosing_func: c.LLVMValueRef) bool {
    // Walk back through GEP/Load/BitCast to find the origin
    var current = value;
    var depth: u32 = 0;
    while (depth < 8) : (depth += 1) {
        // Check if current is a function argument
        if (@intFromPtr(c.LLVMIsAArgument(current)) != 0) {
            // Find parameter index by iterating
            const num_params = c.LLVMCountParams(enclosing_func);
            var pi: u32 = 0;
            while (pi < num_params) : (pi += 1) {
                if (c.LLVMGetParam(enclosing_func, pi) == current) {
                    return hasReadonlyAttribute(enclosing_func, pi);
                }
            }
            return false;
        }
        // Not an instruction — can't trace further
        if (@intFromPtr(c.LLVMIsAInstruction(current)) == 0) return false;
        const opcode = c.LLVMGetInstructionOpcode(current);
        // Follow GEP base, Load source, BitCast operand
        if (opcode == c.LLVMGetElementPtr or opcode == c.LLVMLoad or
            opcode == c.LLVMBitCast or opcode == c.LLVMIntToPtr)
        {
            current = c.LLVMGetOperand(current, 0);
            if (@intFromPtr(current) == 0) return false;
            continue;
        }
        // PHI: check if ANY incoming value is from readonly param
        if (opcode == c.LLVMPHI) {
            const num = c.LLVMCountIncoming(current);
            var i: u32 = 0;
            while (i < num) : (i += 1) {
                const incoming = c.LLVMGetIncomingValue(current, i);
                if (@intFromPtr(incoming) != 0 and isFromReadonlyParam(incoming, enclosing_func)) {
                    return true;
                }
            }
            return false;
        }
        // Call/Invoke: check if callee has readonly return (unlikely but possible)
        if (opcode == c.LLVMCall or opcode == c.LLVMInvoke) {
            // For now, assume calls don't return readonly pointers
            return false;
        }
        break;
    }
    return false;
}

/// Check if a function parameter has the `readonly` attribute.
/// Uses LLVM's attribute API to check for the "readonly" enum attribute at the given param index.
fn hasReadonlyAttribute(func: c.LLVMValueRef, param_idx: u32) bool {
    // LLVM 22: check for "readonly" string attribute at parameter index
    const readonly_name: [*:0]const u8 = "readonly";
    return c.LLVMGetAttributeCountAtIndex(func, param_idx) > 0 and
        c.LLVMGetStringAttributeAtIndex(func, param_idx, readonly_name, 8) != null;
}

/// R-0: Check if a value traces back to a mutable_param via SRT.
/// Uses the Semantic Resolution Tree populated by param_attr.zig detector.
/// If the value comes from a function parameter WITHOUT readonly attribute,
/// it's &mut T — a legal mutable write destination.
///
/// This is the primary FP suppression path for write_to_immutable:
/// In Rust, &mut T does NOT get the `readonly` LLVM attribute.
/// Only &T gets `readonly`. So if the param is mutable_param, the
/// write is to &mut T and is completely legal.
fn isFromMutableParamSRT(value: c.LLVMValueRef, enclosing_func: c.LLVMValueRef, srt: anytype) bool {
    var current = value;
    var depth: u32 = 0;
    while (depth < 8) : (depth += 1) {
        // Check SRT for mutable_param resolution
        const ref = @intFromPtr(current);
        if (srt.hasKind(ref, .mutable_param) != null) return true;

        // If we hit a readonly param, it's NOT mutable
        if (srt.hasKind(ref, .readonly_param) != null) return false;

        // Check if current is a function argument (may not be in SRT yet)
        if (@intFromPtr(c.LLVMIsAArgument(current)) != 0) {
            // Fall back to direct LLVM attribute check
            const num_params = c.LLVMCountParams(enclosing_func);
            var pi: u32 = 0;
            while (pi < num_params) : (pi += 1) {
                if (c.LLVMGetParam(enclosing_func, pi) == current) {
                    // If NOT readonly → it's mutable
                    return !hasReadonlyAttribute(enclosing_func, pi);
                }
            }
            return false;
        }

        // Not an instruction — can't trace further
        if (@intFromPtr(c.LLVMIsAInstruction(current)) == 0) return false;
        const opcode = c.LLVMGetInstructionOpcode(current);

        // Follow GEP base, Load source, BitCast operand
        if (opcode == c.LLVMGetElementPtr or opcode == c.LLVMLoad or
            opcode == c.LLVMBitCast or opcode == c.LLVMIntToPtr)
        {
            current = c.LLVMGetOperand(current, 0);
            if (@intFromPtr(current) == 0) return false;
            continue;
        }
        // PHI: check if ANY incoming value is from mutable param
        if (opcode == c.LLVMPHI) {
            const num = c.LLVMCountIncoming(current);
            var i: u32 = 0;
            while (i < num) : (i += 1) {
                const incoming = c.LLVMGetIncomingValue(current, i);
                if (@intFromPtr(incoming) != 0 and isFromMutableParamSRT(incoming, enclosing_func, srt)) {
                    return true;
                }
            }
            return false;
        }
        break;
    }
    return false;
}

/// Try to extract struct name from a value (GEP or load from GEP).
pub fn getStructNameForValue(val: c.LLVMValueRef) ?[]const u8 {
    var target = val;
    if (c.LLVMGetInstructionOpcode(val) == c.LLVMLoad) {
        const src = c.LLVMGetOperand(val, 0);
        if (@intFromPtr(src) != 0) target = src;
    }

    if (c.LLVMGetInstructionOpcode(target) == c.LLVMGetElementPtr) {
        return getStructNameFromGEP(target);
    }
    return null;
}

/// Result of tracing a pointer back to its struct field origin.
pub const ConstFieldInfo = struct {
    field_name: []const u8,
    struct_name: []const u8,
};

/// Trace a pointer value back to see if it was loaded from a const-qualified struct field.
pub fn traceConstFieldLoad(auditor: *Auditor, ptr_val: c.LLVMValueRef) ?ConstFieldInfo {
    const opcode = c.LLVMGetInstructionOpcode(ptr_val);

    if (opcode == c.LLVMGetElementPtr) {
        if (traceGepToConstField(ptr_val)) |info| return info;

        const base = c.LLVMGetOperand(ptr_val, 0);
        if (@intFromPtr(base) == 0) return null;

        const base_opcode = c.LLVMGetInstructionOpcode(base);

        switch (base_opcode) {
            c.LLVMLoad => {
                const alloca_ptr = c.LLVMGetOperand(base, 0);
                if (@intFromPtr(alloca_ptr) != 0) {
                    const stored_val = findStoreToAlloca(alloca_ptr);
                    if (@intFromPtr(stored_val) != 0) {
                        if (traceConstFieldLoad(auditor, stored_val)) |info| return info;
                    }
                }
            },
            c.LLVMGetElementPtr => {
                if (traceConstFieldLoad(auditor, base)) |info| return info;
            },
            else => {},
        }

        return traceConstFieldLoad(auditor, base);
    }

    if (opcode == c.LLVMLoad) {
        const src = c.LLVMGetOperand(ptr_val, 0);
        if (@intFromPtr(src) != 0) {
            return traceConstFieldLoad(auditor, src);
        }
    }

    return null;
}

/// Scan the basic block containing an alloca to find what value was stored into it.
pub fn findStoreToAlloca(alloca_val: c.LLVMValueRef) c.LLVMValueRef {
    const parent_bb = c.LLVMGetInstructionParent(alloca_val);
    if (@intFromPtr(parent_bb) == 0) {
        const null_val: c.LLVMValueRef = @ptrFromInt(0);
        return null_val;
    }

    var inst = c.LLVMGetFirstInstruction(parent_bb);
    while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
        if (c.LLVMGetInstructionOpcode(inst) != c.LLVMStore) continue;
        if (c.LLVMGetOperand(inst, 1) != alloca_val) continue;
        return c.LLVMGetOperand(inst, 0);
    }

    const null_val: c.LLVMValueRef = @ptrFromInt(0);
    return null_val;
}

/// Check if a GEP instruction indexes into a struct field.
pub fn traceGepToConstField(gep_inst: c.LLVMValueRef) ?ConstFieldInfo {
    if (c.LLVMGetInstructionOpcode(gep_inst) != c.LLVMGetElementPtr) return null;

    const base_ptr = c.LLVMGetOperand(gep_inst, 0);
    if (@intFromPtr(base_ptr) == 0) return null;

    const base_type = c.LLVMTypeOf(base_ptr);
    if (@intFromPtr(base_type) == 0) return null;

    var elem_type = base_type;
    if (c.LLVMGetTypeKind(elem_type) == c.LLVMPointerTypeKind) {
        elem_type = c.LLVMGetElementType(elem_type);
    }
    if (@intFromPtr(elem_type) == 0) return null;

    if (c.LLVMGetTypeKind(elem_type) == c.LLVMStructTypeKind) {
        const struct_name = getStructNameFromGEP(gep_inst) orelse "unknown_struct";
        return ConstFieldInfo{
            .field_name = "data",
            .struct_name = struct_name,
        };
    }

    if (c.LLVMGetInstructionOpcode(base_ptr) == c.LLVMLoad) {
        const load_src = c.LLVMGetOperand(base_ptr, 0);
        if (@intFromPtr(load_src) != 0 and
            c.LLVMGetInstructionOpcode(load_src) == c.LLVMGetElementPtr)
        {
            const inner_name = getStructNameFromGEP(load_src) orelse "unknown_struct";
            return ConstFieldInfo{
                .field_name = "data",
                .struct_name = inner_name,
            };
        }
    }

    return null;
}

// ============================================================================
// GEP Helpers
// ============================================================================

/// Try to extract struct name from a GEP instruction's base type.
pub fn getStructNameFromGEP(gep: c.LLVMValueRef) ?[]const u8 {
    const base = c.LLVMGetOperand(gep, 0);
    if (@intFromPtr(base) == 0) return null;
    const base_type = c.LLVMTypeOf(base);
    if (@intFromPtr(base_type) == 0) return null;

    if (c.LLVMGetTypeKind(base_type) == c.LLVMPointerTypeKind) {
        const elem = c.LLVMGetElementType(base_type);
        if (@intFromPtr(elem) != 0 and c.LLVMGetTypeKind(elem) == c.LLVMStructTypeKind) {
            const name_ptr = c.LLVMGetStructName(elem);
            if (@intFromPtr(name_ptr) != 0) {
                return std.mem.span(name_ptr);
            }
        }
    }
    return null;
}

/// Get the field index from a struct GEP instruction.
pub fn getGepFieldIndex(gep: c.LLVMValueRef) u32 {
    const num_operands = c.LLVMGetNumOperands(gep);
    if (num_operands >= 3) {
        const idx_val = c.LLVMGetOperand(gep, 2);
        if (@intFromPtr(idx_val) != 0 and c.LLVMIsAConstantInt(idx_val) != null) {
            return 0;
        }
    }
    return 0;
}

// ============================================================================
// Rule 10: Use After Free Detection
// ============================================================================

/// Rule 10: Detect use-after-free within a single function.
/// `insts` is the pre-collected instruction list from auditFunction (no re-traversal).
pub fn detectUseAfterFree(auditor: *Auditor, func: c.LLVMValueRef, insts: []const c.LLVMValueRef, ctx: *PassContext, diag: *DiagnosticWriter) !void {
    const func_name = getFunctionName(func);

    // P0 FIX: Run enhanced drop glue detection BEFORE UAF analysis
    // This ensures all RAII patterns are marked in SRT and won't generate FP
    if (ctx.semantic_resolution) |resolution_engine| {
        const srt = resolution_engine.getSemanticTree();
        const module = c.LLVMGetGlobalParent(func);
        if (@intFromPtr(module) != 0) {
            drop_glue.detectAll(module, srt) catch {};
        }
    }

    const MaxFreed: usize = 16;
    var freed_count: usize = 0;
    var freed_ptrs: [MaxFreed]struct {
        ptr_val: c.LLVMValueRef,
        free_inst: c.LLVMValueRef,
        free_func_name: []const u8,
    } = undefined;

    for (insts) |inst| {
        const opcode = c.LLVMGetInstructionOpcode(inst);
        if (opcode != c.LLVMCall and opcode != c.LLVMInvoke) continue;

        const called = c.LLVMGetCalledValue(inst);
        if (@intFromPtr(called) == 0) continue;
        if (c.LLVMIsAFunction(called) != null) continue;

        const callee_name_ptr = c.LLVMGetValueName(called);
        if (@intFromPtr(callee_name_ptr) == 0) continue;
        const callee_name = std.mem.span(callee_name_ptr);

        if (!isDeallocator(callee_name)) continue;

        const inst_ref = @intFromPtr(inst);
        if (ctx.semantic_resolution) |resolution_engine| {
            const srt = resolution_engine.getSemanticTree();
            if (srt.hasKind(inst_ref, .raii_drop_release) != null) continue;
            if (srt.hasKind(inst_ref, .file_operation) != null) continue;
            if (srt.hasKind(inst_ref, .network_operation) != null) continue;
        }

        const freed_ptr = c.LLVMGetOperand(inst, 0);
        if (@intFromPtr(freed_ptr) == 0) continue;

        if (freed_count < MaxFreed) {
            freed_ptrs[freed_count] = .{
                .ptr_val = freed_ptr,
                .free_inst = inst,
                .free_func_name = callee_name,
            };
            freed_count += 1;
        }
    }

    if (freed_count == 0) return;

    const MaxFreedGlobals: usize = 8;
    var freed_global_count: usize = 0;
    var freed_globals: [MaxFreedGlobals]struct {
        global_val: c.LLVMValueRef,
        global_name_buf: [256]u8,
        global_name_len: usize,
        free_func_name: []const u8,
        store_inst: c.LLVMValueRef,
    } = undefined;

    for (insts) |inst| {
        const opcode = c.LLVMGetInstructionOpcode(inst);
        if (opcode != c.LLVMStore) continue;

        const stored_val = c.LLVMGetOperand(inst, 0);
        const dest = c.LLVMGetOperand(inst, 1);
        if (@intFromPtr(dest) == 0 or @intFromPtr(stored_val) == 0) continue;

        if (c.LLVMIsAGlobalValue(dest) == null) continue;

        for (freed_ptrs[0..freed_count]) |fp| {
            if (instructionComesBeforeOrEqual(inst, fp.free_inst)) continue;

            if (ptrTracesTo(stored_val, fp.ptr_val)) {
                if (freed_global_count < MaxFreedGlobals) {
                    const gname_ptr = c.LLVMGetValueName(dest);
                    const gname = if (@intFromPtr(gname_ptr) != 0)
                        std.mem.span(gname_ptr)
                    else
                        "@anonymous";
                    const gname_len = @min(gname.len, 255);

                    var gname_buf: [256]u8 = undefined;
                    @memcpy(gname_buf[0..gname_len], gname[0..gname_len]);

                    freed_globals[freed_global_count] = .{
                        .global_val = dest,
                        .global_name_buf = gname_buf,
                        .global_name_len = gname_len,
                        .free_func_name = fp.free_func_name,
                        .store_inst = inst,
                    };
                    freed_global_count += 1;
                }
                break;
            }
        }
    }

    for (insts) |inst| {
        for (freed_ptrs[0..freed_count]) |fp| {
            if (instructionComesBeforeOrEqual(inst, fp.free_inst)) continue;
            if (instructionUsesValue(inst, fp.ptr_val)) {
                if (ctx.semantic_resolution) |resolution_engine| {
                    const srt = resolution_engine.getSemanticTree();
                    if (srt.hasKind(@intFromPtr(fp.free_inst), .raii_drop_release) != null) continue;
                }
                try reportUafIssue(auditor, func, ctx, diag, func_name, fp.free_func_name, inst, "direct", null);
                break;
            }
        }

        const opcode = c.LLVMGetInstructionOpcode(inst);
        if (opcode == c.LLVMLoad) {
            const load_src = c.LLVMGetOperand(inst, 0);
            if (@intFromPtr(load_src) != 0) {
                for (freed_globals[0..freed_global_count]) |fg| {
                    if (load_src != fg.global_val) continue;
                    if (instructionComesBeforeOrEqual(inst, fg.store_inst)) continue;
                    const gname = fg.global_name_buf[0..fg.global_name_len];
                    try reportUafIssue(auditor, func, ctx, diag, func_name, fg.free_func_name, inst, "global_alias", gname);
                    break;
                }
            }
        }

        if (freed_global_count > 0) {
            for (freed_globals[0..freed_global_count]) |fg| {
                if (instructionComesBeforeOrEqual(inst, fg.store_inst)) continue;
                if (inst == fg.store_inst) continue;
                if (instructionUsesLoadedFromGlobal(inst, fg.global_val, func)) {
                    const gname = fg.global_name_buf[0..fg.global_name_len];
                    try reportUafIssue(auditor, func, ctx, diag, func_name, fg.free_func_name, inst, "global_alias_use", gname);
                    break;
                }
            }
        }
    }
}

/// Report a single UAF finding with appropriate trace and message.
fn reportUafIssue(
    auditor: *Auditor,
    func: c.LLVMValueRef,
    ctx: *PassContext,
    diag: *DiagnosticWriter,
    func_name: []const u8,
    free_func_name: []const u8,
    use_inst: c.LLVMValueRef,
    mode: []const u8,
    global_name: ?[]const u8,
) !void {
    _ = func;

    // R-3: Skip UAF in Rust drop_in_place functions — these are
    // compiler-generated destructors where use-after-free patterns
    // are part of normal RAII cleanup, not real bugs.
    if (isDropContext(func_name)) {
        diag.debug("UAF-SKIP [R-3]: {s} is drop_in_place context — RAII destructor", .{func_name});
        return;
    }

    const opcode = c.LLVMGetInstructionOpcode(use_inst);
    const op_desc = switch (opcode) {
        c.LLVMStore => "store through freed pointer",
        c.LLVMLoad => "load from freed pointer",
        c.LLVMCall, c.LLVMInvoke => "call with freed pointer as argument",
        else => "use of freed pointer",
    };

    const trace = try auditor.allocator.alloc(TraceEntry, 4);
    errdefer auditor.allocator.free(trace);

    if (std.mem.eql(u8, mode, "direct")) {
        trace[0] = TraceEntry.init("Memory freed by deallocation function");
        trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(auditor.allocator, "Free: {s}()", .{free_func_name}));
        trace[2] = TraceEntry.init("Subsequent instruction uses the freed pointer directly");
        trace[3] = TraceEntry.init("Pointer is no longer valid — undefined behavior");

        const message = try std.fmt.allocPrint(
            auditor.allocator,
            "Use after free: pointer freed by {s}() is later used for {s} (CWE-416)",
            .{ free_func_name, op_desc },
        );

        var issue = Issue.initWithTrace(
            .use_after_free,
            message,
            Location.init(func_name),
            .critical,
            0.90,
            trace,
        );
        errdefer issue.deinit(auditor.allocator);
        try ctx.addIssue(&issue);
        diag.critical("[OMI-CRITICAL] [UAF] {s}() -> {s} in {s}", .{ free_func_name, op_desc, func_name });
    } else {
        const gn = global_name orelse "@unknown";
        trace[0] = TraceEntry.init("Memory freed by deallocation function");
        trace[1] = TraceEntry.initOwned(try std.fmt.allocPrint(auditor.allocator, "Free: {s}()", .{free_func_name}));
        trace[2] = TraceEntry.initOwned(try std.fmt.allocPrint(auditor.allocator, "Freed pointer stored to global {s}", .{gn}));
        trace[3] = TraceEntry.init("Load from global yields dangling pointer — use-after-free via global alias (CWE-416)");

        const message = try std.fmt.allocPrint(
            auditor.allocator,
            "Use after free (global alias): pointer freed by {s}() stored to {s}, later loaded and used for {s} (CWE-416)",
            .{ free_func_name, gn, op_desc },
        );

        var issue = Issue.initWithTrace(
            .use_after_free,
            message,
            Location.init(func_name),
            .critical,
            0.88,
            trace,
        );
        errdefer issue.deinit(auditor.allocator);
        try ctx.addIssue(&issue);
        diag.critical("[OMI-CRITICAL] [UAF-GLOBAL] {s}() -> @{s} -> {s} in {s}", .{ free_func_name, gn, op_desc, func_name });
    }
}

// ============================================================================
// UAF Helpers
// ============================================================================

/// Check if `inst` uses a value that was loaded from `target_global`.
pub fn instructionUsesLoadedFromGlobal(
    inst: c.LLVMValueRef,
    target_global: c.LLVMValueRef,
    func: c.LLVMValueRef,
) bool {
    _ = func;
    return tracking.instructionUsesLoadedFromGlobal(inst, target_global);
}

/// Check if a function name matches known deallocator patterns across languages.
pub fn isDeallocator(func_name: []const u8) bool {
    return tracking.isDeallocator(func_name);
}

/// R-3: Check if function is a Rust drop context (drop_in_place / destructor).
/// UAF patterns in these functions are compiler-generated RAII cleanup, not bugs.
///
/// Enhanced version using drop_glue detector for comprehensive pattern matching.
fn isDropContext(func_name: []const u8) bool {
    // Use enhanced detection from drop_glue module
    return drop_glue.isDropInPlaceContext(func_name);
}

/// Check if instruction A comes before (or at) instruction B in the same basic block.
pub fn instructionComesBeforeOrEqual(a: c.LLVMValueRef, b: c.LLVMValueRef) bool {
    const bb_a = c.LLVMGetInstructionParent(a);
    const bb_b = c.LLVMGetInstructionParent(b);
    if (@intFromPtr(bb_a) == 0 or @intFromPtr(bb_b) == 0) return false;
    if (bb_a != bb_b) return false;

    var inst = c.LLVMGetFirstInstruction(bb_a);
    var found_b = false;
    while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
        if (inst == b) found_b = true;
        if (inst == a) return found_b;
    }
    return false;
}

// ============================================================================
// DI Metadata Helpers
// ============================================================================

/// Check if a DIType represents a const-qualified struct member.
pub fn isConstQualifiedMember(di_type: c.LLVMValueRef) bool {
    if (@intFromPtr(di_type) == 0) return false;

    const tag = c.LLVMGetMetadataKind(di_type);

    if (tag == c.LLVMDWARFTypeEnumTag or
        (tag == 0 and isDITag(di_type, c.LLVMDWARFConstTypeTag)))
    {
        return true;
    }

    var current = di_type;
    var depth: u32 = 0;
    while (depth < 4 and @intFromPtr(current) != 0) : (depth += 1) {
        const base = getDIBaseType(current);
        if (@intFromPtr(base) == 0) break;

        const base_tag = c.LLVMGetMetadataKind(base);
        if (base_tag == c.LLVMDWARFTypeEnumTag or
            (base_tag == 0 and isDITag(base, c.LLVMDWARFConstTypeTag)))
        {
            return true;
        }
        current = base;
    }

    return false;
}

/// Get the base type of a DIType node.
pub fn getDIBaseType(di_type: c.LLVMValueRef) c.LLVMValueRef {
    const num_operands = c.LLVMGetNumOperands(di_type);
    if (num_operands >= 2) {
        return c.LLVMGetOperand(di_type, 1);
    }
    const null_val: c.LLVMValueRef = @ptrFromInt(0);
    return null_val;
}

/// Check if a DI metadata node has a specific DWARF tag.
pub fn isDITag(node: c.LLVMValueRef, expected_tag: c_uint) bool {
    const num_operands = c.LLVMGetNumOperands(node);
    if (num_operands < 1) return false;
    const tag_val = c.LLVMGetOperand(node, 0);
    if (@intFromPtr(tag_val) == 0) return false;

    if (c.LLVMIsAConstantInt(tag_val) != null) {
        _ = expected_tag;
        return false;
    }
    return false;
}

/// Extract field name from DI member type metadata.
pub fn getDIFieldName(di_type: c.LLVMValueRef) ?[]const u8 {
    const num_operands = c.LLVMGetNumOperands(di_type);
    if (num_operands >= 3) {
        const name_node = c.LLVMGetOperand(di_type, 2);
        if (@intFromPtr(name_node) != 0 and c.LLVMIsAMDString(name_node) != 0) {
            const name_ptr = c.LLVMGetAMDString(name_node);
            if (@intFromPtr(name_ptr) != 0) {
                return std.mem.span(name_ptr);
            }
        }
    }
    return null;
}

/// Extract type/struct name from DI type metadata.
pub fn getDITypeName(di_type: c.LLVMValueRef) ?[]const u8 {
    var current = di_type;
    var depth: u32 = 0;
    while (depth < 4 and @intFromPtr(current) != 0) : (depth += 1) {
        const num_ops = c.LLVMGetNumOperands(current);
        if (num_ops >= 3) {
            const name_node = c.LLVMGetOperand(current, 2);
            if (@intFromPtr(name_node) != 0 and c.LLVMIsAMDString(name_node) != 0) {
                const name_ptr = c.LLVMGetAMDString(name_node);
                if (@intFromPtr(name_ptr) != 0) {
                    const type_name = std.mem.span(name_ptr);
                    if (type_name.len > 0) return type_name;
                }
            }
        }
        if (num_ops >= 2) {
            current = c.LLVMGetOperand(current, 1);
        } else {
            break;
        }
    }
    return null;
}
