//! Callback Escape — Type Definitions, Constants & Helper Functions
//!
//! Extracted from callback_escape.zig to reduce file size.
//! Contains type definitions, pattern constants, and standalone detection functions.

const std = @import("std");
const c = @import("../ir/llvm_raw.zig").c;
const word_boundary = @import("../utils/word_boundary.zig");
const PassContext = @import("../pass/pass.zig").PassContext;
const PrefixTrie = @import("../common/prefix_trie.zig").PrefixTrie;

/// Types of callback escaping violations detected.
pub const EscapeViolation = enum(u8) {
    /// Go pointer passed to C without KeepAlive guard
    go_pointer_no_keepalive,
    /// C.CBytes result passed to retaining function
    cbytes_escape,
    /// unsafe.Pointer used across FFI boundary without lifetime guarantee
    unsafeptr_dangling_risk,
    /// malloc without corresponding free (leak)
    malloc_without_free,
    /// free without matching malloc (double-free risk)
    free_without_malloc,
};

/// Classification of a detected escape pattern.
pub const EscapePattern = struct {
    violation_type: EscapeViolation,
    confidence: f32,
    func_name: []const u8,
    callee_name: []const u8,
    description: []const u8,
};

/// Statistics for the callback escape detector.
pub const EscapeStats = struct {
    total_functions_analyzed: u32 = 0,
    go_cgo_boundaries_found: u32 = 0,
    keepalive_missing: u32 = 0,
    cbytes_escapes: u32 = 0,
    unsafeptr_risks: u32 = 0,
    malloc_leaks: u32 = 0,
    free_orphans: u32 = 0,
    callback_escapes: u32 = 0,
};

/// Allocation site info for internal tracking.
pub const AllocSiteInfo = struct {
    inst_id: c.LLVMValueRef,
    func_name: []const u8,
};

/// Free site info for internal tracking.
pub const FreeSiteInfo = struct {
    inst_id: c.LLVMValueRef,
    func_name: []const u8,
};

// ============================================================================
// Pattern Constants
// ============================================================================

/// Functions that indicate cgo glue code (compiler-generated).
pub const CGO_GLUE_PATTERNS = &[_][]const u8{
    "_cgo_",
    "_Cfunc_",
    "_cgo_gotypes",
    "crosscall2",
};

/// Known Go runtime functions related to cgo safety.
pub const GO_RUNTIME_SAFETY_FUNCTIONS = &[_][]const u8{
    "runtime.KeepAlive",
    "runtime_Pin",
    "runtime_Unpin",
    "runtime_cgocall",
};

/// C standard library functions that unconditionally retain pointers (escape analysis).
pub const C_RETAINING_FUNCTIONS = &[_][]const u8{
    "pthread_create",          "signal",           "sigaction",
    "atexit",                  "on_exit",          "SDL_SetEventCallback",
    "glfwSetCallback",         "curl_easy_setopt", "RegisterNatives",
    "PyCapsule_SetDestructor", "dlopen",
};

/// Enhanced Go cgo boundary patterns (v0.1.8)
pub const CGO_ENHANCED_PATTERNS = &[_][]const u8{
    // Standard cgo glue (compiler-generated)
    "_cgo_",
    "_Cfunc_",
    "_cgo_gotypes",
    "crosscall2",

    // Go runtime cgo support
    "runtime_cgocall",
    "runtime_iscgo",
    "_cgo_runtime_cgocall",

    // Common Go package prefixes
    "golang_org.",
    "google.golang.org.",
    "github.com/",

    // Go-specific FFI patterns
    "__cgocallback",
    "cgoexp_",
    "_cgo_exp_",

    // JNI/Python interop via cgo
    "Java_", // cgo-JNI bridge
    "PyInit_", // cgo-Python bridge
    "Cython_", // cgo-Cython bridge
};

/// Go unsafe package patterns
pub const GO_UNSAFE_PATTERNS = &[_][]const u8{
    "unsafe.Pointer",
    "unsafe.String",
    "unsafe.Slice",
    "unsafe.SliceData",
    "unsafe.StringData",
    "Add",
    "Alignof",
    "Offsetof",
    "Sizeof",
};

// ============================================================================
// Comptime Trie Instances — replace linear scans with O(n) single-pass matching
// ============================================================================

/// Pre-built trie for CGO_ENHANCED_PATTERNS + CGO_GLUE_PATTERNS (used in isCgoBoundary)
pub const cgo_boundary_trie = PrefixTrie.init(CGO_ENHANCED_PATTERNS, .substring);

/// Pre-built trie for CGO_GLUE_PATTERNS only (used in isCgoGlueByPattern)
pub const cgo_glue_trie = PrefixTrie.init(CGO_GLUE_PATTERNS, .substring);

/// Pre-built trie for GO_UNSAFE_PATTERNS (used in isGoUnsafeOperation)
pub const go_unsafe_trie = PrefixTrie.init(GO_UNSAFE_PATTERNS, .substring);

/// Pre-built trie for GO_RUNTIME_SAFETY_FUNCTIONS (used in isGoSafetyFunction)
pub const go_safety_trie = PrefixTrie.init(GO_RUNTIME_SAFETY_FUNCTIONS, .substring);

/// Pre-built trie for C_RETAINING_FUNCTIONS (used in mayRetainInCLanguageAware, isGenericCallbackReceiver)
pub const c_retaining_trie = PrefixTrie.init(C_RETAINING_FUNCTIONS, .substring);

/// Pre-built trie for callback receiver patterns (used in isCallbackReceiver)
pub const callback_receiver_trie = PrefixTrie.init(&[_][]const u8{
    "RegisterNatives",  "SetCallback",            "set_callback",
    "pthread_create",   "pthread_setcancelstate", "signal",
    "sigaction",        "SDL_SetEventCallback",   "glfwSetCallback",
    "curl_easy_setopt",
}, .substring);

/// Pre-built trie for VOID_CALLBACK_PATTERNS (used in isLikelyCallbackFunction)
pub const void_callback_trie = PrefixTrie.init(VOID_CALLBACK_PATTERNS, .substring);

/// Pre-built trie for FACTORY_PATTERNS (used in isFactoryFunction)
pub const factory_trie = PrefixTrie.init(FACTORY_PATTERNS, .substring);

/// Pre-built trie for DESTRUCTOR_PATTERNS (used in isDestructorFunction)
pub const destructor_trie = PrefixTrie.init(DESTRUCTOR_PATTERNS, .substring);

/// Pre-built trie for TRANSFER_PATTERNS (used in isTransferFunction)
pub const transfer_trie = PrefixTrie.init(TRANSFER_PATTERNS, .substring);

// ============================================================================
// Detection Functions
// ============================================================================

/// Check if a function name indicates cgo boundary code.
pub fn isCgoBoundary(func_name: []const u8) bool {
    // Use trie for O(n) single-pass scan instead of O(n*m) linear scan
    if (cgo_boundary_trie.contains(func_name)) return true;

    // Cgo "C." prefix matching with stricter rules to avoid false positives:
    const c_dot_idx = std.mem.indexOf(u8, func_name, "C.");
    if (c_dot_idx) |idx| {
        const valid = idx == 0 or
            (idx >= 2 and func_name[idx - 1] == '.');
        if (valid) return true;
    }

    return false;
}

/// Check if instruction involves Go unsafe operations
pub fn isGoUnsafeOperation(inst: c.LLVMValueRef) bool {
    if (inst == null) return false;
    const called_val = c.LLVMGetCalledValue(inst);
    if (called_val == null) return false;
    const callee_name_ptr = c.LLVMGetValueName(called_val);
    if (callee_name_ptr == null) return false;
    const callee_name = std.mem.span(callee_name_ptr);
    if (callee_name.len == 0) return false;
    // Use trie for O(n) scan instead of linear loop
    return go_unsafe_trie.contains(callee_name);
}

/// Detect Go-specific memory management patterns
pub fn detectGoMemoryPattern(func_name: []const u8) enum {
    safe,
    keepalive_guarded,
    missing_keepalive,
    manual_c_memory,
    mixed,
} {
    if (std.mem.indexOf(u8, func_name, "KeepAlive") != null)
        return .keepalive_guarded;
    const has_malloc = std.mem.indexOf(u8, func_name, "C.malloc") != null or
        std.mem.indexOf(u8, func_name, "C.calloc") != null;
    const has_free = std.mem.indexOf(u8, func_name, "C.free") != null;
    if (has_malloc and has_free) return .manual_c_memory;
    if (has_malloc or has_free) return .mixed;
    return .safe;
}

/// Check if a function name provides Go-specific cgo evidence.
pub fn hasCgoEvidence(func_name: []const u8) bool {
    return isCgoGlueByPattern(func_name) or
        std.mem.indexOf(u8, func_name, "_cgo_") != null or
        std.mem.indexOf(u8, func_name, "__cgocallback") != null;
}

/// Unified CGO boundary detection by LLVM linkage type and name evidence.
pub fn isCgoBoundaryByLinkage(linkage: c.LLVMLinkage, func_name: []const u8) bool {
    const is_cgo_linkage = (linkage == c.LLVMExternalWeakLinkage or
        linkage == c.LLVMCommonLinkage or
        linkage == c.LLVMExternalLinkage or
        linkage == c.LLVMWeakAnyLinkage or
        linkage == c.LLVMWeakODRLinkage or
        linkage == c.LLVMLinkOnceAnyLinkage or
        linkage == c.LLVMLinkOnceODRLinkage);
    return is_cgo_linkage and hasCgoEvidence(func_name);
}

/// Check if a function is a cgo boundary using LLVM metadata.
pub fn isCgoBoundaryFromLLVM(func: c.LLVMValueRef) bool {
    if (func == null) return false;
    const func_name_ptr = c.LLVMGetValueName(func);
    if (@intFromPtr(func_name_ptr) == 0) return false;
    const func_name = std.mem.span(func_name_ptr);
    if (c.LLVMIsDeclaration(func) != 0) {
        const linkage = c.LLVMGetLinkage(func);
        if (isCgoBoundaryByLinkage(linkage, func_name)) return true;
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

/// Check if name matches cgo glue patterns.
pub fn isCgoGlueByPattern(name: []const u8) bool {
    // Use trie for CGO_GLUE_PATTERNS
    if (cgo_glue_trie.contains(name)) return true;
    // Additional single-pattern checks (not in original pattern array)
    if (std.mem.indexOf(u8, name, "cgocall") != null) return true;
    if (std.mem.startsWith(u8, name, "crosscall")) return true;
    return false;
}

/// Check if a function is a Go runtime safety function.
pub fn isGoSafetyFunction(callee_name: []const u8) bool {
    // Use trie for O(n) scan
    return go_safety_trie.contains(callee_name);
}

/// Language-aware pointer retention check.
pub fn mayRetainInCLanguageAware(callee_name: []const u8, caller_is_cgo: bool) bool {
    // Use trie for C_RETAINING_FUNCTIONS
    if (c_retaining_trie.contains(callee_name)) return true;
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

/// Detect C.CBytes pattern in function names.
pub fn isCBytesPattern(name: []const u8) bool {
    return word_boundary.isWordBoundaryMatch(name, "C.CBytes") or
        word_boundary.isWordBoundaryMatch(name, "C.GoString") or
        word_boundary.isWordBoundaryMatch(name, "C.GoStringN");
}

/// Enhanced CBytes escape detection with data flow analysis.
pub fn isCBytesEscapeWithDataFlow(
    callee_name: []const u8,
    ptr_val: u64,
    ctx: *const PassContext,
) bool {
    if (!isCBytesPattern(callee_name)) return false;
    const mg = &ctx.memory_graph;
    if (mg.isPassedAsArg(ptr_val)) return true;
    if (mg.isStoredToGlobal(ptr_val)) return true;
    return false;
}

/// Detect unsafe.Pointer conversion pattern.
pub fn isUnsafePtrConversion(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "unsafe.Pointer") != null or
        std.mem.indexOf(u8, name, "uintptr") != null;
}

/// Detect JNI RegisterNatives pattern.
pub fn isRegisterNativesPattern(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "RegisterNatives") != null;
}

/// Detect pthread_create pattern.
pub fn isPthreadCreatePattern(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "pthread_create") != null;
}

/// Check if function is a known callback receiver.
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

/// Validate callback function pointer has compatible signature.
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

// ============================================================================
// LLVM Helper Functions
// ============================================================================

/// Check if an LLVM value is a global variable.
pub fn isGlobalVariable(ptr: c.LLVMValueRef) bool {
    if (@intFromPtr(ptr) == 0) return false;
    return c.LLVMGetValueKind(ptr) == c.LLVMGlobalVariableValueKind;
}

/// Known function patterns that accept void-returning callbacks.
pub const VOID_CALLBACK_PATTERNS = &[_][]const u8{
    "atexit",         "qsort",              "bsearch", "signal", "sigaction",
    "pthread_create", "pthread_key_create",
};

/// Check if a function type looks like a callback function based on signature.
pub fn isLikelyCallbackFunction(fn_type: c.LLVMTypeRef, receiver_name: []const u8) bool {
    if (@intFromPtr(fn_type) == 0) return false;

    const num_params = c.LLVMCountParamTypes(fn_type);
    if (num_params == 0) return false;

    const ret_type = c.LLVMGetReturnType(fn_type);
    if (@intFromPtr(ret_type) == 0) return false;

    for (VOID_CALLBACK_PATTERNS) |p| {
        if (std.mem.indexOf(u8, receiver_name, p) != null) return true;
    }

    if (c.LLVMGetTypeKind(ret_type) == c.LLVMVoidTypeKind or
        c.LLVMGetTypeKind(ret_type) == c.LLVMIntegerTypeKind or
        c.LLVMGetTypeKind(ret_type) == c.LLVMPointerTypeKind)
    {
        return true;
    }

    return false;
}

/// Check if a function name is a known generic callback receiver.
pub fn isGenericCallbackReceiver(receiver: []const u8) bool {
    for (C_RETAINING_FUNCTIONS) |pattern| {
        if (std.mem.indexOf(u8, receiver, pattern) != null) return true;
    }
    return false;
}

// ============================================================================
// Ownership Pattern Detection Functions
// ============================================================================

/// Factory/constructor function name patterns (ownership transfer to caller).
pub const FACTORY_PATTERNS = &[_][]const u8{
    "Alloc",  "Create", "New",     "Init", "Open", "Dup",
    "Malloc", "Calloc", "Realloc",
};

/// Destructor/cleanup function name patterns (ownership consume from caller).
pub const DESTRUCTOR_PATTERNS = &[_][]const u8{
    "Free",   "Destroy",  "Delete",  "Close", "Release", "Cleanup",
    "Finish", "Finalize", "Dispose",
};

/// Transfer function name patterns (ownership pass-through).
pub const TRANSFER_PATTERNS = &[_][]const u8{
    "Clone", "Copy", "Move", "Transfer", "Take",
};

/// Checks if a function is a factory/constructor that transfers ownership to caller.
pub fn isFactoryFunction(func_name: []const u8) bool {
    for (FACTORY_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Checks if a function is a destructor that consumes ownership from caller.
pub fn isDestructorFunction(func_name: []const u8) bool {
    for (DESTRUCTOR_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}

/// Checks if a function is a transfer function that passes ownership through.
pub fn isTransferFunction(func_name: []const u8) bool {
    for (TRANSFER_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return true;
        }
    }
    return false;
}
