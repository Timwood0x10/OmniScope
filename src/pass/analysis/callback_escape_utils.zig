const std = @import("std");
const c = @import("../../ir/llvm_raw.zig").c;

/// Utility functions for CallbackEscapePass.
/// Extracted from callback_escape.zig for code organization.
///
/// This module contains pure detection functions:
/// - Cgo boundary identification (string + LLVM metadata)
/// - Go runtime safety function detection
/// - Callback receiver and signature validation
/// - Language-aware pointer retention checks
pub fn isCgoBoundary(func_name: []const u8) bool {
    const CGO_GLUE_PATTERNS = [_][]const u8{
        "_cgo_",
        "cgocall",
        "crosscall",
    };

    for (CGO_GLUE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) return true;
    }

    const c_dot_idx = std.mem.indexOf(u8, func_name, "C.");
    if (c_dot_idx) |idx| {
        const valid = idx == 0 or
            (idx >= 2 and func_name[idx - 1] == '.');
        if (valid) return true;
    }

    return false;
}

pub fn isCgoBoundaryFromLLVM(func: c.LLVMValueRef) bool {
    if (func == null) return false;

    const func_name_ptr = c.LLVMGetValueName(func);
    if (@intFromPtr(func_name_ptr) == 0) return false;
    const func_name = std.mem.span(func_name_ptr);

    if (c.LLVMIsDeclaration(func) != 0) {
        const linkage = c.LLVMGetLinkage(func);
        if (linkage == c.LLVMExternalWeakLinkage or
            linkage == c.LLVMCommonLinkage)
        {
            return true;
        }
        if (linkage == c.LLVMExternalLinkage) {
            if (isCgoGlueByPattern(func_name)) return true;
        }
        if (linkage == c.LLVMWeakAnyLinkage or
            linkage == c.LLVMWeakODRLinkage or
            linkage == c.LLVMLinkOnceAnyLinkage or
            linkage == c.LLVMLinkOnceODRLinkage)
        {
            if (isCgoGlueByPattern(func_name)) return true;
        }
    } else {
        if (isCgoGlueByPattern(func_name)) return true;

        const section = c.LLVMGetSection(func);
        if (@intFromPtr(section) != 0) {
            const section_name = std.mem.span(section);
            if (std.mem.indexOf(u8, section_name, ".text") != null) {
                if (isCgoGlueByPattern(func_name)) return true;
            }
        }
    }

    return false;
}

fn isCgoGlueByPattern(name: []const u8) bool {
    const CGO_GLUE_PATTERNS = [_][]const u8{
        "_cgo_",
        "cgocall",
        "crosscall",
    };

    for (CGO_GLUE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) return true;
    }
    return false;
}

pub fn isGoSafetyFunction(callee_name: []const u8) bool {
    const GO_RUNTIME_SAFETY_FUNCTIONS = [_][]const u8{
        "runtime.KeepAlive",
        "runtime.KeepAliveN",
        "runtime.SetFinalizer",
    };

    for (GO_RUNTIME_SAFETY_FUNCTIONS) |fn_name| {
        if (std.mem.indexOf(u8, callee_name, fn_name) != null) return true;
    }
    return false;
}

pub fn mayRetainInCLanguageAware(callee_name: []const u8, caller_is_cgo: bool) bool {
    const C_RETAINING_FUNCTIONS = [_][]const u8{
        "pthread_create",  "signal",             "sigaction",
        "atexit",          "on_exit",            "qsort",
        "bsearch",         "pthread_key_create", "SDL_SetEventCallback",
        "glfwSetCallback", "curl_easy_setopt",
    };

    for (C_RETAINING_FUNCTIONS) |fn_name| {
        if (std.mem.indexOf(u8, callee_name, fn_name) != null) return true;
    }

    if (caller_is_cgo) {
        const retaining_prefixes = [_][]const u8{
            "register_", "set_", "add_", "subscribe_",
        };
        for (retaining_prefixes) |prefix| {
            if (std.mem.startsWith(u8, callee_name, prefix)) return true;
        }
    }

    return false;
}

pub fn isCBytesPattern(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "CBytes") != null or
        std.mem.indexOf(u8, name, "C.GoString") != null or
        std.mem.indexOf(u8, name, "C.GoStringN") != null;
}

pub fn isUnsafePtrConversion(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "unsafe.Pointer") != null or
        std.mem.indexOf(u8, name, "uintptr") != null;
}

pub fn isRegisterNativesPattern(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "RegisterNatives") != null;
}

pub fn isPthreadCreatePattern(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "pthread_create") != null;
}

pub fn isCallbackReceiver(name: []const u8) bool {
    const receivers = [_][]const u8{
        "RegisterNatives",  "SetCallback",            "set_callback",
        "pthread_create",   "pthread_setcancelstate", "signal",
        "sigaction",        "SDL_SetEventCallback",   "glfwSetCallback",
        "curl_easy_setopt",
    };
    for (receivers) |r| {
        if (std.mem.indexOf(u8, name, r) != null) return true;
    }
    return false;
}

pub fn validate_callback_signature(func_name: []const u8, callback_arg_type: []const u8) bool {
    if (callback_arg_type.len == 0) return false;
    if (std.mem.indexOf(u8, func_name, "RegisterNatives") != null) {
        if (std.mem.indexOf(u8, callback_arg_type, "JNINativeMethod") != null) return true;
        if (std.mem.indexOf(u8, callback_arg_type, "void") != null and
            std.mem.indexOf(u8, callback_arg_type, "*") != null) return true;
        return false;
    }
    if (std.mem.indexOf(u8, func_name, "pthread_create") != null) {
        if (std.mem.indexOf(u8, callback_arg_type, "void*") != null) return true;
        if (std.mem.indexOf(u8, callback_arg_type, "void") != null and
            std.mem.indexOf(u8, callback_arg_type, "*") != null) return true;
        return false;
    }
    if (std.mem.indexOf(u8, func_name, "signal") != null or
        std.mem.indexOf(u8, func_name, "sigaction") != null)
    {
        if (std.mem.indexOf(u8, callback_arg_type, "void") != null and
            std.mem.indexOf(u8, callback_arg_type, "int") != null) return true;
        return false;
    }
    const generic_patterns = [_][]const u8{
        "atexit",  "qsort",              "bsearch",
        "on_exit", "pthread_key_create",
    };
    for (generic_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) {
            if (callback_arg_type.len > 0 and
                (std.mem.indexOf(u8, callback_arg_type, "void") != null or
                    std.mem.indexOf(u8, callback_arg_type, "*") != null))
            {
                return true;
            }
            return false;
        }
    }
    return false;
}
