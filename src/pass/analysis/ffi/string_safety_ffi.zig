//! String FFI Safety Detector
//!
//! Detects when non-C language strings, which may contain embedded null bytes,
//! are passed to C functions. C functions treat null bytes as string terminators,
//! causing silent truncation that can lead to security bypasses.
//!
//! Detection scenarios:
//! 1. Rust &str/String -> C const char*: Rust strings allow embedded nulls
//! 2. Go string -> C char*: Go strings allow embedded nulls
//! 3. Zig []const u8 -> C [*c]const u8: Zig slices may contain embedded nulls
//! 4. Safe patterns (CString::new, explicit null-termination) are excluded

const std = @import("std");

const PassContext = @import("../../pass.zig").PassContext;
const PassKind = @import("../../pass.zig").PassKind;
const DiagnosticWriter = @import("../../pass.zig").DiagnosticWriter;

const Location = @import("../../../diag/issue.zig").Location;
const Issue = @import("../../../diag/issue.zig").Issue;
const IssueKind = @import("../../../diag/issue.zig").IssueKind;
const Severity = @import("../../../diag/issue.zig").Severity;

const c = @import("../../../ir/llvm_raw.zig").c;
const llvm_safe = @import("../../../ir/llvm_safe.zig");

/// Supported source languages for non-C string safety analysis
const SourceLang = enum {
    rust,
    go,
    zig,
};

/// String safety FFI detection pass
///
/// Strategy: For each function in the module, detect its source language
/// from the function name. If it is Rust, Go, or Zig, scan all call
/// instructions. When the callee is a C library function that receives
/// pointer arguments, emit a diagnostic about possible string truncation.
/// Known safe patterns (CString::new, explicit null-termination) are
/// excluded from reporting.
pub const StringSafetyPass = struct {
    pub const name = "string_safety_ffi";
    pub const kind = PassKind.analysis;
    pub const deps = &[_][]const u8{};

    /// Known C library functions that operate on string pointers.
    /// These functions treat null bytes as terminators and will truncate
    /// strings containing embedded nulls from non-C languages.
    const c_string_funcs = &[_][]const u8{
        "printf",
        "fprintf",
        "sprintf",
        "snprintf",
        "vprintf",
        "vfprintf",
        "vsprintf",
        "vsnprintf",
        // String inspection
        "strlen",
        "strcmp",
        "strncmp",
        "strstr",
        "strchr",
        "strrchr",
        "strspn",
        "strcspn",
        // String copy/concatenation
        "strcpy",
        "strncpy",
        "strcat",
        "strncat",
        "strdup",
        "strndup",
        // Output
        "puts",
        "fputs",
        "putchar",
        // Input
        "gets",
        "fgets",
        "scanf",
        "fscanf",
        "sscanf",
    };

    /// Known safe function name patterns that explicitly null-terminate.
    /// Callers using these patterns have already handled the null-termination
    /// requirement, so no truncation risk exists.
    const safe_patterns = &[_][]const u8{
        "CString",
        "into_raw",
        "from_raw",
        "null_terminat",
        "c_str",
        "as_c_str",
        "to_c_str",
        "with_c_str",
    };

    /// Non-C language function name prefix patterns.
    /// Rust uses _RN mangling, Go uses main.*, Zig uses zig_ prefix.
    const rust_prefix = "_RNvC";
    const rust_prefix_alt = "_RN";
    const go_prefix = "main.";
    const zig_prefix = "zig_";

    /// Detect source language from function name using naming conventions.
    fn detectSourceLang(func_name: []const u8) ?SourceLang {
        if (func_name.len == 0) return null;
        if (std.mem.startsWith(u8, func_name, rust_prefix) or
            std.mem.startsWith(u8, func_name, rust_prefix_alt)) return .rust;
        if (std.mem.startsWith(u8, func_name, go_prefix)) return .go;
        if (std.mem.startsWith(u8, func_name, zig_prefix)) return .zig;
        return null;
    }

    /// Check if a callee name matches a known C string function.
    fn isCStringFunc(callee_name: []const u8) bool {
        for (c_string_funcs) |c_name| {
            if (std.mem.eql(u8, callee_name, c_name)) return true;
        }
        return false;
    }

    /// Check if the callee is a general C function (not mangled).
    fn isPlainCFunc(callee_name: []const u8) bool {
        // Skip LLVM intrinsics
        if (std.mem.startsWith(u8, callee_name, "llvm.")) return false;
        // Skip mangled names (C++ _Z, Rust _R)
        if (callee_name.len > 0 and callee_name[0] == '_') return false;
        return true;
    }

    /// Check if a call instruction targets a known safe pattern
    /// such as CString::new or explicit null-termination.
    fn isSafeCallee(callee_name: []const u8) bool {
        for (safe_patterns) |pattern| {
            if (std.mem.indexOf(u8, callee_name, pattern) != null) return true;
        }
        return false;
    }

    /// Check if an LLVM value has a pointer type.
    fn isPointerType(val: c.LLVMValueRef) bool {
        if (@intFromPtr(val) == 0) return false;
        const type_ref = c.LLVMTypeOf(val);
        if (@intFromPtr(type_ref) == 0) return false;
        return c.LLVMGetTypeKind(type_ref) == c.LLVMPointerTypeKind;
    }

    /// Run the string safety detection pass.
    ///
    /// Iterates all functions in the module, identifies non-C callers
    /// (Rust, Go, Zig), and scans for calls to C functions with pointer
    /// arguments that may contain embedded null bytes.
    pub fn run(ctx: *PassContext, diag: *DiagnosticWriter) !void {
        const module = ctx.module orelse {
            diag.debug("StringSafety: no module loaded", .{});
            return;
        };

        var issue_count: u32 = 0;

        // Iterate all functions defined in the module
        var func = c.LLVMGetFirstFunction(module.raw);
        while (@intFromPtr(func) != 0) : (func = c.LLVMGetNextFunction(func)) {
            const name_ptr = c.LLVMGetValueName(func);
            if (@intFromPtr(name_ptr) == 0) continue;
            const func_name = std.mem.span(name_ptr);

            // Detect the caller's source language
            const source_lang = detectSourceLang(func_name) orelse continue;

            // Skip C and C++ functions — they use null-terminated strings natively
            // and the truncation risk does not apply.
            const lang_tag = @tagName(source_lang);

            // Scan all instructions in this function body
            var bb = c.LLVMGetFirstBasicBlock(func);
            while (@intFromPtr(bb) != 0) : (bb = c.LLVMGetNextBasicBlock(bb)) {
                var inst = c.LLVMGetFirstInstruction(bb);
                while (@intFromPtr(inst) != 0) : (inst = c.LLVMGetNextInstruction(inst)) {
                    const opcode = c.LLVMGetInstructionOpcode(inst);
                    if (!llvm_safe.isCallOrInvoke(opcode)) continue;

                    const called_val = c.LLVMGetCalledValue(inst);
                    if (@intFromPtr(called_val) == 0) continue;
                    const callee_name_ptr = c.LLVMGetValueName(called_val);
                    if (@intFromPtr(callee_name_ptr) == 0) continue;
                    const callee_name = std.mem.span(callee_name_ptr);

                    // Skip known safe patterns (CString::new, etc.)
                    if (isSafeCallee(callee_name)) continue;

                    // Determine if callee is a C function
                    const is_c_func = isCStringFunc(callee_name) or isPlainCFunc(callee_name);
                    if (!is_c_func) continue;

                    // Check if any argument is a pointer type (potential string)
                    const num_args = c.LLVMGetNumArgOperands(inst);
                    var has_ptr_arg = false;
                    var i: c_uint = 0;
                    while (i < num_args) : (i += 1) {
                        const arg = c.LLVMGetOperand(inst, i);
                        if (isPointerType(arg)) {
                            has_ptr_arg = true;
                            break;
                        }
                    }
                    if (!has_ptr_arg) continue;

                    // Found a potential string truncation risk
                    issue_count += 1;

                    const loc = Location.init(func_name);

                    const message = try std.fmt.allocPrint(
                        ctx.allocator,
                        "String FFI safety: '{s}' ({s}) passes pointer to C '{s}' — embedded null bytes cause truncation",
                        .{ func_name, lang_tag, callee_name },
                    );

                    var issue = Issue.init(
                        .ffi_unsafe_call,
                        message,
                        loc,
                        .medium,
                        0.85,
                    );
                    issue.classification = .ffi_boundary;
                    try ctx.addIssue(&issue);
                    ctx.allocator.free(message);
                }
            }
        }

        if (issue_count > 0) {
            diag.info("StringSafety: found {d} potential string truncation risk(s)", .{issue_count});
        } else {
            diag.debug("StringSafety: no issues detected", .{});
        }
    }
};
