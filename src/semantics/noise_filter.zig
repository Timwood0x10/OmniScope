//! Cross-Language Noise Reduction Engine - Layer 1: Name-based Filter
//!
//! Distinguishes user code from compiler-generated/runtime code
//! by analyzing function name patterns.
//!
//! This is the fastest filter layer with medium accuracy.
//! Use as first-pass before more expensive analysis layers.
//!
//! Reference: plan/lang_ffi_analysis/plan.md - Layer 1: Name-based Filter

const std = @import("std");
const CommonTypes = @import("../common/types.zig");
const ffi_language_classifier = @import("../pass/analysis/ffi_language_classifier.zig");

/// Re-export Severity for backward compatibility.
/// New code should import from common/types.zig directly.
pub const Severity = CommonTypes.Severity;

/// Origin classification for functions.
/// Determines whether a function should be analyzed or suppressed.
/// This is the canonical FunctionOrigin definition used across all noise reduction layers.
pub const FunctionOrigin = enum(u8) {
    /// User-defined code - high priority for analysis.
    user,

    /// Standard library / runtime internal code - suppress by default.
    stdlib,

    /// Compiler-generated glue code (drop glue, shims, etc.) - ignore.
    compiler_generated,

    /// Third-party library code - analyze but lower priority.
    third_party,

    /// Unknown origin - needs further classification.
    unknown,

    pub fn toString(self: FunctionOrigin) []const u8 {
        return switch (self) {
            .user => "USER",
            .stdlib => "STDLIB",
            .compiler_generated => "COMPILER_GEN",
            .third_party => "THIRD_PARTY",
            .unknown => "UNKNOWN",
        };
    }

    /// Should issues from this origin be reported by default?
    pub fn shouldReportByDefault(self: FunctionOrigin) bool {
        return switch (self) {
            .user => true,
            .stdlib => false,
            .compiler_generated => false,
            .third_party => true,
            .unknown => true,
        };
    }
};

/// Risk level for issues based on function origin and issue type.
/// This is the canonical RiskLevel definition used across all noise reduction layers.
pub const RiskLevel = enum(u8) {
    /// Critical - must fix immediately (FFI boundary bugs).
    critical,

    /// High - should fix soon (user unsafe code).
    high,

    /// Medium - investigate when possible.
    medium,

    /// Low - informational only.
    low,

    /// Suppressed - not worth reporting (stdlib noise).
    suppressed,

    pub fn toString(self: RiskLevel) []const u8 {
        return switch (self) {
            .critical => "CRITICAL",
            .high => "HIGH",
            .medium => "MEDIUM",
            .low => "LOW",
            .suppressed => "SUPPRESSED",
        };
    }

    /// Check if this risk level meets a minimum threshold.
    /// Note: lower enum value = higher priority (critical=0 < high=1 < ... < suppressed=4)
    pub fn meetsThreshold(self: RiskLevel, min: RiskLevel) bool {
        return @intFromEnum(self) <= @intFromEnum(min);
    }
};

/// Classification result with origin and risk level.
pub const ClassificationResult = struct {
    origin: FunctionOrigin,
    risk_level: RiskLevel,
    reason: []const u8,
};

// ============================================================================
// Rust Name Patterns
// ============================================================================

/// Rust standard library prefixes to skip.
/// These are compiler-generated or runtime-internal patterns.
const RUST_STDLIB_PREFIXES = [_][]const u8{
    // Core library
    "_ZN4core",
    "_ZN5alloc",
    "_ZN3std",

    // Compiler-generated patterns
    "__rust_",
    "$LT$core", // Generic core types
    "$LT$alloc", // Generic alloc types
    "$LT$std", // Generic std types
};

/// Rust v0 mangling stdlib prefixes (_RNv + crate name).
/// Only _RNv + core/alloc/std is stdlib — user crates like _RNvXs...MyCrate are user code.
const RUST_V0_STDLIB_PREFIXES = [_][]const u8{
    "_RNvN4core",
    "_RNvN5alloc",
    "_RNvN3std",
    "_RNvXsX_N4core",
    "_RNvXsX_N5alloc",
    "_RNvXsX_N3std",
};

/// Rust standard library substrings to skip.
const RUST_STDLIB_SUBSTRINGS = [_][]const u8{
    "core::ptr::drop_in_place",
    "core::panicking::begin_panic",
    "alloc::raw_vec::RawVec",
    "core::panicking::",
    "alloc::alloc::",
    "<alloc::vec::Vec",
    "<core::slice",
    "::fmt::",
};

/// Rust compiler-generated function patterns.
const RUST_COMPILER_PATTERNS = [_][]const u8{
    // Drop glue - P0-3: Suppress compiler-generated destructors
    "drop_in_place",
    "glue_drop",
    "need_drop",
    "drop_glue",

    // Panic infrastructure
    "begin_panic",
    "panic_fmt",
    "panic_bounds_check",

    // Monomorphization artifacts
    "$LT$",
    "$GT$",
    "$u20$",
    "$C$",

    // Shims and compiler internals
    "_ZN17alloc", // alloc internals
    "_ZN4core", // core internals
    "__rust_",
    "impl_drop",
    "impl_clone",

    // Opaque type wrappers
    "opaque_type",
    "dyn_drop",
};

// ============================================================================
// Zig Name Patterns
// ============================================================================

/// Zig standard library prefixes to skip.
const ZIG_STDLIB_PREFIXES = [_][]const u8{
    "std.",
    "zig.",
};

/// Zig standard library substrings to skip.
const ZIG_STDLIB_SUBSTRINGS = [_][]const u8{
    "std.mem.Allocator",
    "std.ArrayList",
    "std.StringArrayHashMap",
    "std.AutoHashMap",
    "std.fmt.allocPrint",
    "std.heap.GeneralPurposeAllocator",
    "array_list",
    "hash_map",
    "start.zig",
    "panic.zig",
};

/// Zig compiler-generated patterns.
const ZIG_COMPILER_PATTERNS = [_][]const u8{
    // Allocator wrappers - P0-3: Suppress compiler allocators
    "GeneralPurposeAllocator",
    "FixedBufferAllocator",
    "ArenaAllocator",
    "ThreadSafeAllocator",

    // Runtime internals
    "zig_start",
    "__zig_launch",
    "start.main",
    "callMain",

    // Compiler-generated safety
    "safety_panic",
    "boundsCheck",
    "sentinelCheck",
    "fieldCheck",
    "overflowCheck",

    // Defer glue
    "__defer",
    "defer_",
};

// ============================================================================
// C++ Name Patterns
// ============================================================================

/// C++ standard library prefixes to skip.
/// Ref: docs/C_CPP_IR_SPEC.md §9.2, §1.2
const CPP_STDLIB_PREFIXES = [_][]const u8{
    // libc++ (macOS default)
    "_ZNSt3__1", // std::__1 namespace (libc++)
    "_ZSt", // std template instantiations
    "_ZNSt", // std namespace mangled
    // libstdc++ (Linux default)
    "_ZNS_", // std:: substitution
    // GNU C++ library
    "std::__",
    "__gnu_cxx",
    "__cxa_",
    // C standard library checked variants (fortified)
    "__sprintf_chk",
    "__strcpy_chk",
    "__printf_chk",
    "__fprintf_chk",
    "__vsnprintf_chk",
    "__memcpy_chk",
    "__memmove_chk",
    "__memset_chk",
};

/// C++ standard library substrings to skip.
/// Ref: docs/C_CPP_IR_SPEC.md §4.4, §9.2
const CPP_STDLIB_SUBSTRINGS = [_][]const u8{
    // Exception handling runtime (IR SPEC §4.4)
    "__cxa_begin_catch",
    "__cxa_end_catch",
    "__cxa_throw",
    "__cxa_rethrow",
    "__cxa_allocate_exception",
    "__cxa_free_exception",
    "__cxa_guard_acquire",
    "__cxa_guard_release",
    "__cxa_guard_abort",
    // STL internals
    "std::_Function_handler",
    "std::_Bind_back",
    // Unwind infrastructure (IR SPEC §4.4)
    "_Unwind_Resume",
    "_Unwind_DeleteException",
    "_Unwind_RaiseException",
};

/// C++ compiler-generated patterns.
/// Ref: docs/C_CPP_IR_SPEC.md §1.2.3, §1.2.4, §5, §8, §9.2
const CPP_COMPILER_PATTERNS = [_][]const u8{
    // Compiler-generated helpers - P0-3: Suppress
    "__clang_call_terminate",
    "__cxa_pure_virtual",
    "__cxa_deleted_virtual",
    "__gxx_personality",

    // STL template internals (already covered by stdlib, but extra safety)
    "_ZSt", // std template instantiations
    "_ZNSt", // std namespace mangled

    // RAII/destructor glue (IR SPEC §1.2.3)
    // Note: _ZN is NOT listed here — it matches all mangled user code.
    // Destructor patterns D0Ev/D1Ev/D2Ev are sufficient for compiler-generated detection.
    "D0Ev", // Deleting destructor
    "D1Ev", // Complete object destructor
    "D2Ev", // Base object destructor

    // VTable and RTTI (IR SPEC §5)
    "_ZTV", // Virtual table
    "_ZTI", // Typeinfo
    "_ZTS", // Typeinfo name
    "_ZTT", // VTT (Virtual Table Table) (IR SPEC §5.5)

    // Guard variables for thread-safe statics (IR SPEC §8.3)
    "_ZGV", // Guard variable prefix

    // Thunks for multiple inheritance (IR SPEC §8.2)
    "_ZTh", // Adjustor thunk (non-virtual)
    "_ZTv", // Virtual call thunk

    // __cxxabiv1 runtime vtables (IR SPEC §5.6)
    "_ZTVN10__cxxabiv1", // C++ ABI runtime vtable
    "_ZTIN10__cxxabiv1", // C++ ABI runtime typeinfo

    // Allocator internals (DC-H14 FIX: Use precise patterns to avoid false positives)
    "_ZN9__gnu_cxx13new_allocator", // GNU new_allocator<T>
    "_ZNSt13__allocated", // std::allocated_ptr (libstdc++)
    "_ZSt15get_new_handlerv", // std::get_new_handler
    "_Znwm", // operator new
    "_ZdlPv", // operator delete
    "_Znam", // operator new[] (IR SPEC §3.2)
    "_ZdaPv", // operator delete[] (IR SPEC §3.2)

    // C runtime/compiler helpers
    "__stack_chk_fail",
    "__libc_start_main",
    "_GLOBAL__",
    "__cxx_global_var_init",
    "__cxa_atexit",
    "__dso_handle",
    "_init",
    "_fini",
    "__tls_init",
};

// ============================================================================
// Go Name Patterns
// ============================================================================

/// Go runtime/cgo prefixes to skip.
const GO_RUNTIME_PREFIXES = [_][]const u8{
    "runtime.",
    "internal/",
};

/// Go cgo generated patterns to skip.
const GO_CGO_PATTERNS = [_][]const u8{
    "_Cfunc_",
    "_cgo_",
    "_cgo_gotypes",
};

/// Go compiler-generated patterns.
const GO_COMPILER_PATTERNS = [_][]const u8{
    "init.",
    "gcWriteBarrier",
    "writeBarrier",
};

// ============================================================================
// Swift Name Patterns
// Ref: docs/SWIFT_IR_SPEC.md
// ============================================================================

/// Swift mangled name prefixes (IR SPEC §1.1).
const SWIFT_MANGLED_PREFIXES = [_][]const u8{
    "$s", // Swift 5+
    "_$s", // Swift 5+ (underscore)
    "$S", // Swift 4.x
    "_$S", // Swift 4.x (underscore)
    "_T0", // Swift 4
    "$e", // Embedded Swift
    "_$e", // Embedded Swift (underscore)
};

/// Swift ARC runtime prefixes to suppress (IR SPEC §2, §14).
const SWIFT_ARC_PREFIXES = [_][]const u8{
    "swift_retain",
    "swift_release",
    "swift_nonatomic_retain",
    "swift_nonatomic_release",
    "swift_unknownObjectRetain",
    "swift_unknownObjectRelease",
    "swift_bridgeObjectRetain",
    "swift_bridgeObjectRelease",
    "swift_errorRetain",
    "swift_errorRelease",
    "swift_weak",
    "swift_unowned",
};

/// Swift compiler runtime prefixes to suppress (IR SPEC §3-7, §11-13).
const SWIFT_COMPILER_PREFIXES = [_][]const u8{
    // Metadata (IR SPEC §4)
    "swift_get",
    "swift_init",
    "swift_checkMetadata",
    "swift_allocateGeneric",
    // Casting (IR SPEC §3)
    "swift_dynamicCast",
    "swift_conformsToProtocol",
    // Witness tables (IR SPEC §5, §6)
    "swift_getWitnessTable",
    "swift_getAssociatedTypeWitness",
    "swift_cvw_",
    // Enum (IR SPEC §7)
    "swift_getEnumTag",
    "swift_storeEnumTag",
    // Concurrency (IR SPEC §11)
    "swift_task",
    "swift_defaultActor",
    "swift_continuation",
    "swift_taskGroup",
    "swift_asyncLet",
    // Exclusivity (IR SPEC §12)
    "swift_beginAccess",
    "swift_endAccess",
    // Registration (IR SPEC §13)
    "swift_once",
    "swift_register",
    // Array/COW (IR SPEC §2.7, §2.8)
    "swift_arrayInit",
    "swift_arrayAssign",
    "swift_arrayDestroy",
    "swift_isUniquelyReferenced",
    "swift_isEscapingClosure",
    // Macro filenames (IR SPEC §1.1)
    "@__swiftmacro_",
};

/// Swift FFI boundary patterns (IR SPEC §9).
const SWIFT_FFI_PATTERNS = [_][]const u8{
    "objc_msgSend",
    "objc_allocWithZone",
    "objc_getClass",
    "object_getClass",
    "sel_registerName",
    "_Block_copy",
    "_Block_release",
    "swift_bridgeObject",
    "swift_unknownObject",
    "swift_allocObject",
    "swift_deallocObject",
};

// ============================================================================
// Python Name Patterns
// Ref: docs/PYTHON_IR_SPEC.md
// ============================================================================

/// Python C API prefixes that indicate FFI boundary (IR SPEC §1, §5).
const PYTHON_CAPI_PREFIXES = [_][]const u8{
    "Py_INCREF",
    "Py_DECREF",
    "Py_XDECREF",
    "Py_XINCREF",
    "Py_NewRef",
    "Py_CLEAR",
    "PyObject_New",
    "PyObject_GC_New",
    "PyInit_",
    "PyArg_ParseTuple",
    "Py_BuildValue",
    "PyCapsule_",
    "PyObject_GetBuffer",
    "PyBuffer_Release",
};

/// Python internal runtime prefixes to suppress (IR SPEC §8, §10).
const PYTHON_RUNTIME_PREFIXES = [_][]const u8{
    "_Py_Dealloc",
    "_PyTrash_",
    "_Py_ForgetReference",
    "_PyReftracerTrack",
    "_PyRuntime",
    "_PyInterpreter",
    "_PyThread",
    "_PyStackRef",
    "_Py_CODEUNIT",
    "_Py_IDENTIFIER",
    "_Py_static_string",
    "_Py_IsImmortal",
    "_Py_IsStaticImmortal",
    "_Py_IMMORTAL",
    "_PyObject_ClearFreeLists",
    "_PyRuntimeState_Init",
    "_PyGC_Init",
};

/// Python GC internals to suppress (IR SPEC §4).
const PYTHON_GC_PATTERNS = [_][]const u8{
    "update_refs",
    "subtract_refs",
    "move_unreachable",
    "_Py_Dealloc",
    "_PyTrash_",
};

// ============================================================================
// Public API
// ============================================================================

/// Classify a function's origin based on its name.
///
/// Arguments:
///   func_name - The LLVM IR function name to classify
///   lang - Optional source language hint
///
/// Returns:
///   ClassificationResult with origin, risk level, and reason
pub fn classifyFunction(func_name: []const u8, lang: ?Language) ClassificationResult {
    if (func_name.len == 0) {
        return .{
            .origin = .unknown,
            .risk_level = .medium,
            .reason = "empty function name",
        };
    }

    // Check for LLVM intrinsics first (language-agnostic)
    if (isLLVMIntrinsic(func_name)) {
        return .{
            .origin = .compiler_generated,
            .risk_level = .suppressed,
            .reason = "LLVM intrinsic",
        };
    }

    // Language-specific classification
    if (lang) |l| {
        return switch (l) {
            .rust => classifyRustFunction(func_name),
            .zig => classifyZigFunction(func_name),
            .go => classifyGoFunction(func_name),
            .cpp => classifyCppFunction(func_name),
            .c => classifyCFunction(func_name),
            .swift => classifySwiftFunction(func_name),
            .python => classifyPythonFunction(func_name),
            else => defaultClassification(func_name),
        };
    }

    // Auto-detect language from patterns
    if (isRustMangledName(func_name)) {
        return classifyRustFunction(func_name);
    }
    if (isSwiftMangledName(func_name)) {
        return classifySwiftFunction(func_name);
    }
    if (isZigFunction(func_name)) {
        return classifyZigFunction(func_name);
    }
    if (isGoFunction(func_name)) {
        return classifyGoFunction(func_name);
    }
    if (isCppMangledName(func_name)) {
        return classifyCppFunction(func_name);
    }
    if (isPythonCExtension(func_name)) {
        return classifyPythonFunction(func_name);
    }

    return defaultClassification(func_name);
}

/// Unified three-layer classification combining name-based, path-based, and
/// behavior-based filters. This is the single entry point all passes should
/// use instead of calling classifyFunction() directly.
///
/// Layer 1 (name-based): Always applied — fastest, medium accuracy.
/// Layer 2 (path-based): Applied when source_location is provided — high accuracy.
/// Layer 3 (behavior):   Applied when behavior_result is provided — highest accuracy.
///
/// Priority: Layer 3 > Layer 2 > Layer 1
/// If a higher layer classifies as stdlib/compiler_generated, that wins.
/// If a higher layer classifies as user, we still trust it over lower layers.
pub fn classifyFunctionFull(
    func_name: []const u8,
    lang: ?Language,
    source_location: ?@import("../ir/debug_info.zig").SourceLocation,
    behavior_result: ?@import("behavior_filter.zig").BehaviorResult,
) ClassificationResult {
    // Layer 1: Name-based (always available)
    var result = classifyFunction(func_name, lang);

    // Layer 2: Path-based (when debug info is available)
    if (source_location) |loc| {
        if (loc.valid()) {
            const path_filter = @import("path_filter.zig");
            const path_result = path_filter.classifyByPath(loc, func_name);
            // Path-based classification overrides name-based for
            // stdlib/compiler_generated because source paths are
            // more reliable than name patterns
            if (path_result.origin == .stdlib or path_result.origin == .compiler_generated) {
                result = .{
                    .origin = path_result.origin,
                    .risk_level = path_result.risk_level,
                    .reason = path_result.reason,
                };
            }
        }
    }

    // Layer 3: Behavior-based (when instruction analysis is available)
    if (behavior_result) |br| {
        if (br.shouldSuppress()) {
            // Behavior filter detected a known runtime pattern
            const origin: FunctionOrigin = switch (br.pattern) {
                .rust_drop_glue, .stl_reallocation => .compiler_generated,
                .zig_allocator_wrapper => .stdlib,
                .ffi_boundary, .user_logic, .unknown => result.origin,
            };
            result = .{
                .origin = origin,
                .risk_level = .suppressed,
                .reason = br.reason,
            };
        }
    }

    return result;
}

/// Convenience: check if a function should be analyzed (not suppressed).
/// Returns true for user/third_party/unknown, false for stdlib/compiler_generated.
pub fn shouldAnalyze(
    func_name: []const u8,
    lang: ?Language,
    source_location: ?@import("../ir/debug_info.zig").SourceLocation,
) bool {
    const result = classifyFunctionFull(func_name, lang, source_location, null);
    return result.origin.shouldReportByDefault();
}

/// Get effective risk level based on origin and issue severity.
///
/// This implements the risk weighting system:
/// - user + dangerous sink = HIGH/CRITICAL
/// - stdlib + leak = SUPPRESSED
/// - compiler_generated + anything = SUPPRESS/IGNORE
pub fn getRiskLevel(origin: FunctionOrigin, base_severity: Severity) RiskLevel {
    return switch (origin) {
        .compiler_generated => switch (base_severity) {
            .critical, .high => .suppressed,
            .medium, .low => .suppressed,
        },
        .stdlib => switch (base_severity) {
            .critical => .low,
            .high => .low,
            .medium => .suppressed,
            .low => .suppressed,
        },
        .third_party => switch (base_severity) {
            .critical => .high,
            .high => .medium,
            .medium => .low,
            .low => .suppressed,
        },
        .user => switch (base_severity) {
            .critical => .critical,
            .high => .high,
            .medium => .medium,
            .low => .low,
        },
        .unknown => switch (base_severity) {
            .critical => .high,
            .high => .medium,
            .medium => .low,
            .low => .suppressed,
        },
    };
}

/// Source language for classification.
pub const Language = enum(u8) {
    rust,
    zig,
    go,
    c,
    cpp,
    swift,
    python,
    unknown,
};

/// Issue severity levels (re-exported from common/types.zig).
/// Use common/types.zig.Severity directly in new code.

// ============================================================================
// Language-Specific Classification Functions
// ============================================================================

/// Classify a Rust function by name patterns.
fn classifyRustFunction(func_name: []const u8) ClassificationResult {
    // Check v0 mangling stdlib prefixes first (most specific for _RNv patterns)
    for (RUST_V0_STDLIB_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "Rust standard library (v0 mangling)",
            };
        }
    }

    // Check stdlib prefixes (legacy C++ mangling)
    for (RUST_STDLIB_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "Rust standard library",
            };
        }
    }

    // Check stdlib substrings
    for (RUST_STDLIB_SUBSTRINGS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "Rust standard library",
            };
        }
    }

    // Check compiler-generated patterns (after stdlib)
    for (RUST_COMPILER_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .compiler_generated,
                .risk_level = .suppressed,
                .reason = "Rust compiler-generated code",
            };
        }
    }

    // Check for __rust_ prefix (compiler internal)
    if (std.mem.startsWith(u8, func_name, "__rust_")) {
        return .{
            .origin = .compiler_generated,
            .risk_level = .suppressed,
            .reason = "Rust compiler internal",
        };
    }

    // Check for FFI-related patterns (extern C, libc calls)
    if (isExternCPattern(func_name)) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "Rust extern C boundary",
        };
    }

    // Default: user code (mangled Rust function)
    if (isRustMangledName(func_name)) {
        return .{
            .origin = .user,
            .risk_level = .medium,
            .reason = "Rust user code",
        };
    }

    return defaultClassification(func_name);
}

/// Classify a Zig function by name patterns.
fn classifyZigFunction(func_name: []const u8) ClassificationResult {
    // Check compiler-generated patterns
    for (ZIG_COMPILER_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .compiler_generated,
                .risk_level = .suppressed,
                .reason = "Zig compiler-generated code",
            };
        }
    }

    // Check stdlib prefixes
    for (ZIG_STDLIB_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) {
            // Allow certain safe stdlib patterns that users commonly use
            if (!isSafeStdlibPattern(func_name)) {
                return .{
                    .origin = .stdlib,
                    .risk_level = .low,
                    .reason = "Zig standard library",
                };
            }
        }
    }

    // Check stdlib substrings
    for (ZIG_STDLIB_SUBSTRINGS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "Zig standard library",
            };
        }
    }

    // Check for FFI patterns (@cImport, extern)
    if (isZigFfiPattern(func_name)) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "Zig FFI boundary",
        };
    }

    return .{
        .origin = .user,
        .risk_level = .medium,
        .reason = "Zig user code",
    };
}

/// Classify a Go function by name patterns.
fn classifyGoFunction(func_name: []const u8) ClassificationResult {
    // Check cgo generated patterns
    for (GO_CGO_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .compiler_generated,
                .risk_level = .suppressed,
                .reason = "Go cgo generated code",
            };
        }
    }

    // Check compiler-generated patterns
    for (GO_COMPILER_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .compiler_generated,
                .risk_level = .suppressed,
                .reason = "Go compiler-generated code",
            };
        }
    }

    // Check runtime prefixes
    for (GO_RUNTIME_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "Go runtime",
            };
        }
    }

    // Check for cgo patterns in user code
    if (isGoFfiPattern(func_name)) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "Go cgo boundary",
        };
    }

    return .{
        .origin = .user,
        .risk_level = .medium,
        .reason = "Go user code",
    };
}

/// Classify a C function by name patterns.
/// Ref: docs/C_CPP_IR_SPEC.md §1.1, §6, §9.1, §9.2
/// C functions appear in IR with plain names (no _Z prefix).
/// We need to distinguish user C code from compiler builtins and runtime internals.
fn classifyCFunction(func_name: []const u8) ClassificationResult {
    // Check if this is a compiler builtin / runtime internal (IR SPEC §6, §9.2)
    if (isCCompilerBuiltin(func_name)) {
        return .{
            .origin = .compiler_generated,
            .risk_level = .suppressed,
            .reason = "C compiler builtin/runtime",
        };
    }

    // Check for C FFI boundary patterns (IR SPEC §1.1, §2.3)
    if (isCFfiPattern(func_name)) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "C FFI boundary function",
        };
    }

    // Check for extern C patterns (cross-language boundary)
    if (isExternCPattern(func_name)) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "C extern boundary",
        };
    }

    // C allocation functions are important FFI boundaries (IR SPEC §3.1)
    if (std.mem.eql(u8, func_name, "malloc") or
        std.mem.eql(u8, func_name, "calloc") or
        std.mem.eql(u8, func_name, "realloc") or
        std.mem.eql(u8, func_name, "free"))
    {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "C allocator - FFI memory boundary (IR SPEC §3.1)",
        };
    }

    return .{
        .origin = .user,
        .risk_level = .medium,
        .reason = "C user code",
    };
}

/// Classify a C++ function by name patterns.
/// Ref: docs/C_CPP_IR_SPEC.md §9.1, §9.2
fn classifyCppFunction(func_name: []const u8) ClassificationResult {
    // Check stdlib prefixes FIRST
    for (CPP_STDLIB_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "C++ standard library",
            };
        }
    }

    // Check stdlib substrings (includes exception handling, unwind, etc.)
    for (CPP_STDLIB_SUBSTRINGS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .stdlib,
                .risk_level = .low,
                .reason = "C++ standard library",
            };
        }
    }

    // Check _ZSt pattern (std template instantiations) as stdlib
    if (std.mem.startsWith(u8, func_name, "_ZSt")) {
        return .{
            .origin = .stdlib,
            .risk_level = .low,
            .reason = "C++ standard library template",
        };
    }

    // Check _ZNSt pattern (std namespace mangled) as stdlib
    if (std.mem.startsWith(u8, func_name, "_ZNSt")) {
        return .{
            .origin = .stdlib,
            .risk_level = .low,
            .reason = "C++ standard library",
        };
    }

    // Check compiler-generated patterns
    for (CPP_COMPILER_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .compiler_generated,
                .risk_level = .suppressed,
                .reason = "C++ compiler-generated code",
            };
        }
    }

    // Check for C++ operator new/delete at FFI boundary (IR SPEC §3.2, §9.3)
    // These are important for cross-language memory safety
    if (std.mem.startsWith(u8, func_name, "_Znw")) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "C++ operator new - FFI memory boundary (IR SPEC §3.2)",
        };
    }
    if (std.mem.startsWith(u8, func_name, "_Zdl")) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "C++ operator delete - FFI memory boundary (IR SPEC §3.2)",
        };
    }
    if (std.mem.startsWith(u8, func_name, "_Zna")) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "C++ operator new[] - FFI memory boundary (IR SPEC §3.2)",
        };
    }
    if (std.mem.startsWith(u8, func_name, "_Zda")) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "C++ operator delete[] - FFI memory boundary (IR SPEC §3.2)",
        };
    }

    // Check for MSVC-mangled names (IR SPEC §1.3)
    if (func_name.len > 0 and func_name[0] == '?') {
        return .{
            .origin = .compiler_generated,
            .risk_level = .suppressed,
            .reason = "MSVC-mangled C++ symbol (IR SPEC §1.3)",
        };
    }

    // Check for extern C patterns
    if (isExternCPattern(func_name)) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "C++ extern C boundary",
        };
    }

    // Check for C FFI library patterns (IR SPEC §1.1, §2.3)
    if (isCFfiPattern(func_name)) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "C FFI boundary (IR SPEC §2.3)",
        };
    }

    return .{
        .origin = .user,
        .risk_level = .medium,
        .reason = "C++ user code",
    };
}

/// Classify a Swift function by name patterns.
/// Ref: docs/SWIFT_IR_SPEC.md §1.1, §2, §9, §14
fn classifySwiftFunction(func_name: []const u8) ClassificationResult {
    // Check ARC runtime prefixes - suppress (IR SPEC §2, §14)
    for (SWIFT_ARC_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) {
            return .{
                .origin = .compiler_generated,
                .risk_level = .suppressed,
                .reason = "Swift ARC runtime",
            };
        }
    }

    // Check compiler runtime prefixes - suppress (IR SPEC §3-7, §11-13)
    for (SWIFT_COMPILER_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) {
            return .{
                .origin = .compiler_generated,
                .risk_level = .suppressed,
                .reason = "Swift compiler runtime",
            };
        }
    }

    // Swift macro filenames - suppress (IR SPEC §1.1)
    if (std.mem.startsWith(u8, func_name, "@__swiftmacro_")) {
        return .{
            .origin = .compiler_generated,
            .risk_level = .suppressed,
            .reason = "Swift macro filename (IR SPEC §1.1)",
        };
    }

    // Allocation/deallocation as FFI boundary (IR SPEC §2.6)
    if (std.mem.startsWith(u8, func_name, "swift_allocObject")) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "Swift allocObject - FFI memory boundary (IR SPEC §2.6)",
        };
    }
    if (std.mem.startsWith(u8, func_name, "swift_dealloc")) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "Swift dealloc - FFI memory boundary (IR SPEC §2.6)",
        };
    }

    // ObjC/FFI boundary patterns (IR SPEC §9)
    for (SWIFT_FFI_PATTERNS) |pattern| {
        if (std.mem.startsWith(u8, func_name, pattern)) {
            return .{
                .origin = .user,
                .risk_level = .high,
                .reason = "Swift ObjC/FFI boundary (IR SPEC §9)",
            };
        }
    }

    // Mangled Swift user symbols (IR SPEC §1.1)
    if (isSwiftMangledName(func_name)) {
        return .{
            .origin = .user,
            .risk_level = .medium,
            .reason = "Swift user code",
        };
    }

    return .{
        .origin = .user,
        .risk_level = .medium,
        .reason = "Swift unclassified",
    };
}

/// Classify a Python C extension function by name patterns.
/// Ref: docs/PYTHON_IR_SPEC.md §1, §5, §8, §10
fn classifyPythonFunction(func_name: []const u8) ClassificationResult {
    // Check runtime internal prefixes - suppress (IR SPEC §8, §10)
    for (PYTHON_RUNTIME_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) {
            return .{
                .origin = .compiler_generated,
                .risk_level = .suppressed,
                .reason = "CPython runtime internal",
            };
        }
    }

    // Check GC internals - suppress (IR SPEC §4)
    for (PYTHON_GC_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .{
                .origin = .compiler_generated,
                .risk_level = .suppressed,
                .reason = "CPython GC internal",
            };
        }
    }

    // Module init functions - FFI boundary (IR SPEC §5)
    if (std.mem.startsWith(u8, func_name, "PyInit_")) {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "Python C extension init (IR SPEC §5)",
        };
    }

    // Reference counting - FFI boundary (IR SPEC §1.2, §10)
    if (std.mem.startsWith(u8, func_name, "Py_INCREF") or
        std.mem.startsWith(u8, func_name, "Py_DECREF") or
        std.mem.startsWith(u8, func_name, "Py_XDECREF") or
        std.mem.startsWith(u8, func_name, "Py_XINCREF"))
    {
        return .{
            .origin = .user,
            .risk_level = .high,
            .reason = "Python refcount boundary (IR SPEC §1.2)",
        };
    }

    // C API FFI boundary (IR SPEC §5, §6, §7)
    for (PYTHON_CAPI_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) {
            return .{
                .origin = .user,
                .risk_level = .high,
                .reason = "Python C API FFI boundary",
            };
        }
    }

    return .{
        .origin = .user,
        .risk_level = .medium,
        .reason = "Python C extension code",
    };
}

/// Default classification for unrecognized patterns.
fn defaultClassification(func_name: []const u8) ClassificationResult {
    // Check for C compiler builtins first (IR SPEC §6, §9.2)
    if (isCCompilerBuiltin(func_name)) {
        return .{
            .origin = .compiler_generated,
            .risk_level = .suppressed,
            .reason = "C compiler builtin/runtime",
        };
    }

    // Heuristic: very long names are likely compiler-generated
    if (func_name.len > 100) {
        return .{
            .origin = .compiler_generated,
            .risk_level = .suppressed,
            .reason = "long name suggests compiler-generated",
        };
    }

    // Heuristic: names starting with _ are often internal
    if (func_name.len > 0 and func_name[0] == '_') {
        return .{
            .origin = .third_party,
            .risk_level = .medium,
            .reason = "underscore prefix, possibly library code",
        };
    }

    return .{
        .origin = .user,
        .risk_level = .medium,
        .reason = "unrecognized pattern, assuming user code",
    };
}

// ============================================================================
// Helper Detection Functions
// ============================================================================

/// Check if name matches LLVM intrinsic pattern.
fn isLLVMIntrinsic(name: []const u8) bool {
    if (std.mem.startsWith(u8, name, "llvm.")) return true;
    return false;
}

/// Check if name looks like a Rust-mangled function.
/// Delegates to ffi_language_classifier.isRustMangledName for consistency.
fn isRustMangledName(name: []const u8) bool {
    return ffi_language_classifier.isRustMangledName(name);
}

/// Check if name looks like a C++-mangled function (_Z...).
fn isCppMangledName(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "_Z")) return false;
    // Exclude Rust mangled names (detected by hash suffix or _R prefix)
    if (isRustMangledName(name)) return false;
    return true;
}

/// Check if this is a Zig function (by naming convention).
fn isZigFunction(name: []const u8) bool {
    if (std.mem.startsWith(u8, name, "std.")) return true;
    // Check for Zig builtin patterns (specific ones, not just @)
    if (std.mem.indexOf(u8, name, "@ptrCast") != null) return true;
    if (std.mem.indexOf(u8, name, "@cImport") != null) return true;
    return false;
}

/// Check if this is a Go function (by naming convention).
fn isGoFunction(name: []const u8) bool {
    // BUG-FIX-6: Removed overly broad "." match that incorrectly
    // classified C++ (std.vector.push_back) and Rust (core.ptr.drop_in_place)
    // functions as Go. Now only matches known Go-specific patterns.
    if (std.mem.startsWith(u8, name, "runtime.")) return true;
    if (std.mem.startsWith(u8, name, "main.")) return true;
    if (std.mem.startsWith(u8, name, "go.")) return true; // go.* prefix
    if (std.mem.indexOf(u8, name, "cgocall") != null) return true; // cgo glue
    if (std.mem.indexOf(u8, name, "crosscall") != null) return true; // crosscall2
    return false;
}

/// Check if name looks like a Swift-mangled function (IR SPEC §1.1).
fn isSwiftMangledName(name: []const u8) bool {
    for (SWIFT_MANGLED_PREFIXES) |prefix| {
        if (std.mem.startsWith(u8, name, prefix)) return true;
    }
    return false;
}

/// Check if name looks like a Python C extension function (IR SPEC §5, §10).
fn isPythonCExtension(name: []const u8) bool {
    // PyInit_ module init is the clearest indicator (IR SPEC §5)
    if (std.mem.startsWith(u8, name, "PyInit_")) return true;
    // Common C API patterns (IR SPEC §1.2, §10)
    if (std.mem.startsWith(u8, name, "Py_INCREF") or
        std.mem.startsWith(u8, name, "Py_DECREF") or
        std.mem.startsWith(u8, name, "Py_XDECREF"))
    {
        return true;
    }
    return false;
}

/// Check for extern C / FFI boundary patterns.
fn isExternCPattern(name: []const u8) bool {
    // libc patterns
    if (std.mem.indexOf(u8, name, "libc::") != null) return true;
    if (std.mem.indexOf(u8, name, "nix::") != null) return true;

    // Raw pointer operations at FFI boundary
    if (std.mem.indexOf(u8, name, "from_raw") != null) return true;
    if (std.mem.indexOf(u8, name, "into_raw") != null) return true;

    // extern "C" indicator
    if (std.mem.indexOf(u8, name, "extern") != null) return true;

    return false;
}

/// Check for Zig FFI patterns.
fn isZigFfiPattern(name: []const u8) bool {
    if (std.mem.indexOf(u8, name, "@cImport") != null) return true;
    if (std.mem.indexOf(u8, name, "@cInclude") != null) return true;
    if (std.mem.indexOf(u8, name, "@ptrCast") != null) return true;
    if (std.mem.indexOf(u8, name, "@intToPtr") != null) return true;
    if (std.mem.indexOf(u8, name, "extern ") != null) return true;
    return false;
}

/// Check for Go cgo patterns.
fn isGoFfiPattern(name: []const u8) bool {
    if (std.mem.indexOf(u8, name, "C.") != null) return true;
    if (std.mem.indexOf(u8, name, "unsafe.Pointer") != null) return true;
    if (std.mem.indexOf(u8, name, "uintptr(") != null) return true;
    return false;
}

/// Check for C FFI boundary patterns (IR SPEC §1.1, §2.3).
/// C functions called from C++ compilation units indicate cross-language boundaries.
fn isCFfiPattern(name: []const u8) bool {
    // Known C library API patterns that are FFI boundaries
    // SQLite (IR SPEC §1.1)
    if (std.mem.startsWith(u8, name, "sqlite3_")) return true;
    // zlib (IR SPEC §1.1)
    if (std.mem.startsWith(u8, name, "inflate")) return true;
    if (std.mem.startsWith(u8, name, "deflate")) return true;
    // OpenSSL (IR SPEC §1.1)
    if (std.mem.startsWith(u8, name, "EVP_")) return true;
    if (std.mem.startsWith(u8, name, "RSA_")) return true;
    if (std.mem.startsWith(u8, name, "BIO_")) return true;
    if (std.mem.startsWith(u8, name, "SSL_")) return true;
    if (std.mem.startsWith(u8, name, "X509_")) return true;
    if (std.mem.startsWith(u8, name, "PEM_")) return true;
    // extern "C" wrappers (IR SPEC §1.4)
    if (std.mem.startsWith(u8, name, "c_")) return true;
    return false;
}

/// Check if a plain C name is a compiler builtin / runtime function
/// that should be suppressed (IR SPEC §6, §9.2).
/// These appear without _Z prefix but are still compiler infrastructure.
fn isCCompilerBuiltin(name: []const u8) bool {
    const builtin_patterns = [_][]const u8{
        // C runtime internals
        "__libc_start_main",
        "__stack_chk_fail",
        "__stack_chk_guard",
        "__cxa_atexit",
        "__dso_handle",
        "_init",
        "_fini",
        "__tls_init",
        // Fortified (checked) library functions - compiler injected
        "__sprintf_chk",
        "__strcpy_chk",
        "__printf_chk",
        "__fprintf_chk",
        "__vsnprintf_chk",
        "__memcpy_chk",
        "__memmove_chk",
        "__memset_chk",
        // Compiler builtin prefixes (IR SPEC §6)
        "__builtin_",
        "__asm_",
    };
    for (builtin_patterns) |pattern| {
        if (std.mem.startsWith(u8, name, pattern)) return true;
        if (std.mem.eql(u8, name, pattern)) return true;
    }
    return false;
}

/// Check if a stdlib pattern is actually safe user-facing API.
/// Some stdlib functions are so commonly used they should be treated as user code.
fn isSafeStdlibPattern(name: []const u8) bool {
    const safe_patterns = [_][]const u8{
        "std.debug.print",
        "std.fs.cwd",
        "std.io.getStdOut",
        "std.io.getStdErr",
    };

    for (safe_patterns) |pattern| {
        if (std.mem.indexOf(u8, name, pattern) != null) {
            return true;
        }
    }
    return false;
}

// ============================================================================
// Statistics
// ============================================================================

/// Statistics for noise filtering results.
pub const FilterStats = struct {
    user_count: u32 = 0,
    stdlib_count: u32 = 0,
    compiler_count: u32 = 0,
    third_party_count: u32 = 0,
    unknown_count: u32 = 0,
    suppressed_issues: u32 = 0,

    pub fn record(self: *FilterStats, result: ClassificationResult) void {
        switch (result.origin) {
            .user => self.user_count += 1,
            .stdlib => self.stdlib_count += 1,
            .compiler_generated => self.compiler_count += 1,
            .third_party => self.third_party_count += 1,
            .unknown => self.unknown_count += 1,
        }

        if (result.risk_level == .suppressed) {
            self.suppressed_issues += 1;
        }
    }

    pub fn total(self: FilterStats) u32 {
        return self.user_count + self.stdlib_count + self.compiler_count +
            self.third_party_count + self.unknown_count;
    }

    pub fn suppressionRatio(self: FilterStats) f64 {
        const t = self.total();
        if (t == 0) return 0.0;
        return @as(f64, @floatFromInt(self.compiler_count + self.stdlib_count)) /
            @as(f64, @floatFromInt(t));
    }
};

// ============================================================================
// Tests
// ============================================================================

test "classifyRustFunction - stdlib detection" {
    const result = classifyRustFunction("_ZN4core3ptr13drop_in_placeE");
    try std.testing.expectEqual(FunctionOrigin.stdlib, result.origin);

    const result2 = classifyRustFunction("_ZN5alloc7raw_vec19RawVecT...");
    try std.testing.expectEqual(FunctionOrigin.stdlib, result2.origin);
}

test "classifyRustFunction - compiler generated" {
    // Use a name that matches drop_in_place pattern (in RUST_COMPILER_PATTERNS)
    const result = classifyRustFunction("some_function_drop_in_place_impl");
    try std.testing.expectEqual(FunctionOrigin.compiler_generated, result.origin);
    try std.testing.expectEqual(RiskLevel.suppressed, result.risk_level);
}

test "classifyRustFunction - user code" {
    const result = classifyRustFunction("_ZN4myapp4main17h1234567890abcdefE");
    try std.testing.expectEqual(FunctionOrigin.user, result.origin);
}

test "classifyRustFunction - extern C boundary" {
    const result = classifyRustFunction("libc::write");
    try std.testing.expectEqual(RiskLevel.high, result.risk_level);
}

test "classifyZigFunction - stdlib detection" {
    const result = classifyZigFunction("std.ArrayList.init");
    try std.testing.expectEqual(FunctionOrigin.stdlib, result.origin);
}

test "classifyZigFunction - user code" {
    const result = classifyZigFunction("myApp.main");
    try std.testing.expectEqual(FunctionOrigin.user, result.origin);
}

test "classifyZigFunction - FFI boundary" {
    const result = classifyZigFunction("myFunc@cImport");
    try std.testing.expectEqual(RiskLevel.high, result.risk_level);
}

test "classifyGoFunction - cgo generated" {
    const result = classifyGoFunction("_cgo_cfunction_wrapper");
    try std.testing.expectEqual(FunctionOrigin.compiler_generated, result.origin);
}

test "classifyGoFunction - runtime" {
    const result = classifyGoFunction("runtime.mallocgc");
    try std.testing.expectEqual(FunctionOrigin.stdlib, result.origin);
}

test "classifyGoFunction - user code" {
    const result = classifyGoFunction("main.processData");
    try std.testing.expectEqual(FunctionOrigin.user, result.origin);
}

test "classifyCppFunction - stdlib" {
    const result = classifyCppFunction("_ZSt3maxIiERKT_S2_S2_");
    try std.testing.expectEqual(FunctionOrigin.stdlib, result.origin);
}

test "classifyCppFunction - compiler generated" {
    // __clang_call_terminate is in CPP_COMPILER_PATTERNS
    const result = classifyCppFunction("some_function___clang_call_terminate_wrapper");
    try std.testing.expectEqual(FunctionOrigin.compiler_generated, result.origin);
}

test "classifyCppFunction - user code" {
    const result = classifyCppFunction("_Z9myProcessv");
    try std.testing.expectEqual(FunctionOrigin.user, result.origin);
}

test "getRiskLevel - user code preserves severity" {
    try std.testing.expectEqual(RiskLevel.critical, getRiskLevel(.user, .critical));
    try std.testing.expectEqual(RiskLevel.high, getRiskLevel(.user, .high));
    try std.testing.expectEqual(RiskLevel.medium, getRiskLevel(.user, .medium));
    try std.testing.expectEqual(RiskLevel.low, getRiskLevel(.user, .low));
}

test "getRiskLevel - compiler generated always suppressed" {
    try std.testing.expectEqual(RiskLevel.suppressed, getRiskLevel(.compiler_generated, .critical));
    try std.testing.expectEqual(RiskLevel.suppressed, getRiskLevel(.compiler_generated, .high));
}

test "getRiskLevel - stdlib downgrades severity" {
    try std.testing.expectEqual(RiskLevel.low, getRiskLevel(.stdlib, .critical));
    try std.testing.expectEqual(RiskLevel.suppressed, getRiskLevel(.stdlib, .medium));
}

test "FilterStats - tracking" {
    var stats = FilterStats{};

    stats.record(.{ .origin = .user, .risk_level = .high, .reason = "" });
    stats.record(.{ .origin = .stdlib, .risk_level = .low, .reason = "" });
    stats.record(.{ .origin = .compiler_generated, .risk_level = .suppressed, .reason = "" });

    try std.testing.expectEqual(@as(u32, 1), stats.user_count);
    try std.testing.expectEqual(@as(u32, 1), stats.stdlib_count);
    try std.testing.expectEqual(@as(u32, 1), stats.compiler_count);
    // Only compiler_generated is suppressed, stdlib is low risk
    try std.testing.expectEqual(@as(u32, 1), stats.suppressed_issues);
}

test "LLVM intrinsic detection" {
    const result = classifyFunction("llvm.sqrt.f32", null);
    try std.testing.expectEqual(FunctionOrigin.compiler_generated, result.origin);
}

test "auto language detection - Rust" {
    const result = classifyFunction("_ZN4myapp4mainE", null);
    try std.testing.expectEqual(FunctionOrigin.user, result.origin);
}

test "auto language detection - C++" {
    const result = classifyFunction("_Z9myProcessv", null);
    try std.testing.expectEqual(FunctionOrigin.user, result.origin);
}

test "_RNv v0 mangling: user crate not classified as stdlib" {
    const result = classifyFunction("_RNvXsX_NtNtCs7MyCrate3ffi4cb_handler", null);
    try std.testing.expectEqual(FunctionOrigin.user, result.origin);
}

test "_RNv v0 mangling: core/alloc/std classified as stdlib" {
    const core = classifyFunction("_RNvXsX_N4core3fmt3Debug", null);
    try std.testing.expectEqual(FunctionOrigin.stdlib, core.origin);
    const alloc = classifyFunction("_RNvXsX_N5alloc3ffi", null);
    try std.testing.expectEqual(FunctionOrigin.stdlib, alloc.origin);
}

test "_ZN not in CPP_COMPILER_PATTERNS indexOf" {
    const result = classifyCppFunction("_ZN4myapp4mainE");
    try std.testing.expectEqual(FunctionOrigin.user, result.origin);
}

test "DC-H14: allocator pattern does not match custom allocators" {
    const testing = std.testing;

    // Should match (std:: allocator patterns)
    try testing.expect(classifyFunction("_ZN9__gnu_cxx13new_allocatorIiE", .cpp).origin == .compiler_generated);
    try testing.expect(classifyFunction("_Znwm", .cpp).origin == .compiler_generated);
    try testing.expect(classifyFunction("_ZdlPv", .cpp).origin == .compiler_generated);

    // Should NOT match (custom allocators)
    const custom_cases = [_][]const u8{
        "my_custom_allocator_init",
        "get_allocator",
        "allocator_pool_create",
        "custom_allocator_dealloc",
    };

    for (custom_cases) |case| {
        const result = classifyFunction(case, .cpp);
        // Custom allocator code should be classified as user code, not suppressed
        try testing.expect(result.origin != .compiler_generated);
    }
}
