//! Indirect Call Target Resolution
//!
//! Extracted from ffi_boundary.zig to reduce file size.
//! Provides utilities for resolving indirect call targets through
//! function pointer tracing (JNI/COM/vtable patterns).

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;
const builtin = @import("builtin");
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const ffi_debug = builtin.mode == .Debug;

/// Resolve indirect call target through function pointer tracing.
///
/// LLVM IR pattern for JNI/COM/vtable calls:
///   %gep = getelementptr %struct.T, %struct.T* %ptr, i32 0, i32 <FIELD_IDX>
///   %fn = load <func_type>, <func_type>** %gep
///   call <ret> %fn(args...)   ← called_val is %fn (not a function)
///
/// This function traces back from the called value through load → GEP
/// to identify the struct type and field index, then maps known structs
/// (like JNINativeInterface) to their function names by field position.
///
/// Returns: resolved function name (slice of static buffer), or empty slice if unresolvable.
pub fn resolveIndirectCallTarget(inst: c.LLVMValueRef, diag: *DiagnosticWriter) []const u8 {
    const called_val = c.LLVMGetCalledValue(inst);
    if (@intFromPtr(called_val) == 0) return "";

    // Step 1: called_val should be an instruction (result of load)
    if (c.LLVMIsAInstruction(called_val) == null) {
        if (ffi_debug) {
            const val_name = c.LLVMGetValueName(called_val);
            const name_str = if (@intFromPtr(val_name) != 0) std.mem.span(val_name) else "(null)";
            diag.info("RESOLVE-FAIL: not instruction, name='{s}', isConst={}, isFn={}", .{
                name_str,
                @intFromPtr(c.LLVMIsAConstant(called_val)) != 0,
                @intFromPtr(c.LLVMIsAFunction(called_val)) != 0,
            });
        }
        return "";
    }
    const load_inst = @as(c.LLVMValueRef, @ptrCast(called_val));
    if (ffi_debug) diag.info("RESOLVE-STEP1: passed, is load inst", .{});

    // Step 2: Verify it's a load instruction
    if (c.LLVMGetInstructionOpcode(load_inst) != c.LLVMLoad) {
        if (ffi_debug) diag.info("RESOLVE-FAIL-STEP2: not a load (opcode={})", .{c.LLVMGetInstructionOpcode(load_inst)});
        return "";
    }
    if (ffi_debug) diag.info("RESOLVE-STEP2: passed, is Load", .{});

    // Step 3: Get the pointer operand of the load (should be GEP result)
    const num_ops = c.LLVMGetNumOperands(load_inst);
    if (num_ops < 1) {
        if (ffi_debug) diag.info("RESOLVE-FAIL-STEP3: load has no operands", .{});
        return "";
    }
    const ptr_operand = c.LLVMGetOperand(load_inst, 0);
    if (@intFromPtr(ptr_operand) == 0) {
        if (ffi_debug) diag.info("RESOLVE-FAIL-STEP3: ptr_operand is null", .{});
        return "";
    }
    if (ffi_debug) diag.info("RESOLVE-STEP3: passed, got ptr_operand", .{});

    // Step 4: Verify pointer operand is a GEP instruction
    if (c.LLVMIsAInstruction(ptr_operand) == null) {
        if (ffi_debug) diag.info("RESOLVE-FAIL-STEP4: ptr_operand not instruction", .{});
        return "";
    }
    const gep_inst = @as(c.LLVMValueRef, @ptrCast(ptr_operand));
    if (c.LLVMGetInstructionOpcode(gep_inst) != c.LLVMGetElementPtr) {
        if (ffi_debug) diag.info("RESOLVE-FAIL-STEP4: not GEP (opcode={})", .{c.LLVMGetInstructionOpcode(gep_inst)});
        return "";
    }
    if (ffi_debug) diag.info("RESOLVE-STEP4: passed, is GEP", .{});

    // Step 5: Extract GEP operands — last operand is the field index
    const gep_num_ops = c.LLVMGetNumOperands(gep_inst);
    if (gep_num_ops < 3) {
        if (ffi_debug) diag.info("RESOLVE-FAIL-STEP5: GEP has only {} ops", .{gep_num_ops});
        return "";
    }

    const field_idx_val = c.LLVMGetOperand(gep_inst, @intCast(gep_num_ops - 1));
    if (@intFromPtr(field_idx_val) == 0) {
        if (ffi_debug) diag.info("RESOLVE-FAIL-STEP5: field_idx_val is null", .{});
        return "";
    }
    if (c.LLVMIsAConstantInt(field_idx_val) == null) {
        if (ffi_debug) diag.info("RESOLVE-FAIL-STEP5: field_idx not constant int", .{});
        return "";
    }

    const field_idx = c.LLVMConstIntGetZExtValue(field_idx_val);
    if (ffi_debug) diag.info("RESOLVE-STEP5: passed, field_idx={}", .{field_idx});

    // Step 6: Get the struct type from GEP's base pointer
    const gep_base = c.LLVMGetOperand(gep_inst, 0);
    if (@intFromPtr(gep_base) == 0) {
        if (ffi_debug) diag.info("RESOLVE-FAIL-STEP6: gep_base is null", .{});
        return "";
    }
    const ptr_type = c.LLVMTypeOf(gep_base);
    if (@intFromPtr(ptr_type) == 0) {
        if (ffi_debug) diag.info("RESOLVE-FAIL-STEP6: ptr_type is null", .{});
        return "";
    }
    // DEBUG: Print actual GEP instruction text (debug builds only)
    // NOTE: LLVMPrintValueToString allocates memory that MUST be freed with
    // LLVMDisposeMessage. The defer ensures cleanup on all exit paths.
    const gep_text = c.LLVMPrintValueToString(gep_inst);
    defer c.LLVMDisposeMessage(gep_text);
    if (ffi_debug) diag.info("RESOLVE-DEBUG: GEP text='{s}'", .{std.mem.span(gep_text)});

    // Step 6 (Opaque Pointer workaround):
    // In LLVM 22 with opaque pointers, all pointers are "ptr" and
    // LLVMGetElementType() returns meaningless types (kind=1=Half).
    // Instead, extract the struct NAME from GEP's textual representation:
    //   "%10 = getelementptr inbounds %struct.JNINativeInterface, ptr %9, i32 0, i32 <FIELD>"
    const gep_str = std.mem.span(gep_text);
    const struct_name = extractStructNameFromGEPText(gep_str);
    if (struct_name.len == 0) {
        if (ffi_debug) diag.info("RESOLVE-FAIL-STEP6: could not extract struct name from GEP: '{s}'", .{gep_str});
        return "";
    }
    if (ffi_debug) diag.info("RESOLVE-STEP6: extracted struct='{s}'", .{struct_name});

    // Step 7: Map (struct_name, field_index) → function name
    return mapStructFieldToFunction(struct_name, @intCast(field_idx), diag);
}

/// Extract struct type name from GEP instruction's textual representation.
///
/// LLVM 22 uses opaque pointers, so `LLVMGetElementType()` returns
/// meaningless types. This function parses the GEP text to find the
/// source element type name (e.g., "JNINativeInterface" from "%struct.JNINativeInterface").
///
/// Input example: "  %10 = getelementptr inbounds %struct.JNINativeInterface, ptr %9, i32 0, i32 0"
/// Output: slice pointing to "%struct.JNINativeInterface" within the input
pub fn extractStructNameFromGEPText(gep_text: []const u8) []const u8 {
    // Find "getelementptr" keyword
    const gep_keyword = "getelementptr";
    const gep_start = std.mem.indexOf(u8, gep_text, gep_keyword) orelse return "";
    const after_gep = gep_start + gep_keyword.len;

    // Skip whitespace after "getelementptr"
    var idx = after_gep;
    while (idx < gep_text.len and (gep_text[idx] == ' ' or gep_text[idx] == '\t')) : (idx += 1) {}

    if (idx >= gep_text.len) return "";

    // The next token should be the struct type (e.g., "%struct.JNINativeInterface")
    // It may optionally have "inbounds" before it
    var token_start = idx;
    const inbounds = "inbounds";
    if (idx + inbounds.len < gep_text.len and
        std.mem.eql(u8, gep_text[idx..][0..inbounds.len], inbounds))
    {
        // Skip "inbounds" and following whitespace/comma
        idx += inbounds.len;
        while (idx < gep_text.len and (gep_text[idx] == ' ' or gep_text[idx] == '\t' or gep_text[idx] == ',')) : (idx += 1) {}
        token_start = idx;
    }

    // Extract until comma or end of token
    var token_end = token_start;
    while (token_end < gep_text.len and gep_text[token_end] != ',' and gep_text[token_end] != ' ') : (token_end += 1) {}

    if (token_end <= token_start) return "";

    const type_token = gep_text[token_start..token_end];

    return type_token;
}

/// Map a struct field index to a known function name.
///
/// Currently supports:
/// - JNINativeInterface: maps field indices to JNI function names
///
/// Extension point: add more struct types here as needed (COM vtables,
/// C++ vtables, other FFI interface tables).
pub fn mapStructFieldToFunction(struct_name: []const u8, field_idx: u32, diag: *DiagnosticWriter) []const u8 {
    // JNINativeInterface field layout (from jni.h):
    // Field 0:  FindClass
    // Field 1:  GetMethodID
    // Field 2:  CallVoidMethod
    // Field 3:  GetStringUTFChars
    // Field 4:  ReleaseStringUTFChars
    // Field 5:  NewGlobalRef
    // Field 6:  DeleteGlobalRef
    // Field 7:  AttachCurrentThread
    // Field 8:  GetByteArrayElements
    // Field 9:  ReleaseByteArrayElements
    // Field 10: GetObjectArrayElement
    // Field 11: DeleteLocalRef
    // Field 12: ExceptionCheck
    // Field 13: ExceptionDescribe
    // Field 14: ExceptionClear
    // Field 15: GetArrayLength
    if (std.mem.indexOf(u8, struct_name, "JNINativeInterface") != null) {
        const jni_fields = [_][]const u8{
            "FindClass", // 0
            "GetMethodID", // 1
            "CallVoidMethod", // 2
            "GetStringUTFChars", // 3
            "ReleaseStringUTFChars", // 4
            "NewGlobalRef", // 5
            "DeleteGlobalRef", // 6
            "AttachCurrentThread", // 7
            "GetByteArrayElements", // 8
            "ReleaseByteArrayElements", // 9
            "GetObjectArrayElement", // 10
            "DeleteLocalRef", // 11
            "ExceptionCheck", // 12
            "ExceptionDescribe", // 13
            "ExceptionClear", // 14
            "GetArrayLength", // 15
        };
        if (field_idx < jni_fields.len) {
            if (ffi_debug) diag.info("JNI-FIELD-MAP: JNINativeInterface[{}] → {s}", .{ field_idx, jni_fields[field_idx] });
            return jni_fields[field_idx];
        }
        if (ffi_debug) diag.info("JNI-FIELD-MAP: JNINativeInterface[{}] — unknown field (total: {})", .{ field_idx, jni_fields.len });
    }

    // Unknown struct type — cannot resolve
    return "";
}
