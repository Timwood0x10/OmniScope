//! C/C++ FFI Adapter — Handles native C and C++ patterns.
//!
//! This module provides TWO adapter instances:
//!
//!   1. **c_instance** — For plain C code (malloc/free, manual memory)
//!      Memory model: .manual
//!      Key patterns: malloc, calloc, realloc, free, strdup, etc.
//!
//!   2. **cpp_instance** — For C++ code (RAII, smart pointers, STL)
//!      Memory model: .raii
//!      Key patterns: unique_ptr, shared_ptr, STL containers, destructors
//!
//! ## Key C++ Concepts Modeled
//!
//!   - **Smart pointer operations**: unique_ptr::release (potential leak!),
//!     unique_ptr::reset (deletes old), shared_ptr::get (borrow),
//!     shared_ptr::reset (decrements refcount).
//!
//!   - **STL container constructors**: std::vector, std::string etc.
//!     allocate internally and auto-free in destructor. No leak possible
//!     unless you extract raw pointer and lose the container.
//!
//!   - **Destructor patterns**: ~ClassName in Itanium mangling (_ZN...D<ver>Ev)
//!     and MSVC mangling (??1ClassName@@...). These are RAII cleanup sites.
//!
//!   - **Exception handling paths**: invoke instructions + landingpad blocks.
//!     Leaks on exception paths are a major C++ FFI concern because
//!     unwinding skips over cleanup code that runs on normal returns.
//!
//! ## Reference
//!   - Itanium C++ ABI: https://itanium-cxx-abi.org/cxx-abi/abi.html
//!   - C++ IR spec: docs/en/ir-specs/C_CPP_IR_SPEC.md

const std = @import("std");
const adapter_mod = @import("language_adapter.zig");
const types = @import("types.zig");
const FFISemantics = types.FFISemantics;
const Language = types.Language;

// ═══════════════════════════════════════════════════════════════
// Pattern Tables — C (Manual Memory Management)
// ═══════════════════════════════════════════════════════════════

/// Standard C allocation functions — return owned heap pointers.
pub const C_ALLOCATORS = [_][]const u8{
    "malloc",
    "calloc",
    "realloc",
    "reallocarray",
    "aligned_alloc",
    "memalign",
    "posix_memalign",
    "valloc",
    "palloc",
    // String allocators
    "strdup",
    "strndup",
    "wcsdup",
    // POSIX
    "mmap",
    "mmap64",
    "shmget",
};

/// Standard C deallocation functions — consume owned pointers.
pub const C_DEALLOCATORS = [_][]const u8{
    "free",
    "munmap",
    "shmdt",
};

/// Functions that return borrowed pointers (must not free).
///
/// These return pointers to internal or static storage that the caller
/// must not pass to free().
pub const C_BORROWING_FUNCTIONS = [_][]const u8{
    "getenv",
    "setlocale",
    "strerror",
    "ctime",
    "asctime",
    "inet_ntoa",
    "inet_ntop",
    "gai_strerror",
};

/// C++ ABI internal functions (suppress from analysis).
///
/// These are compiler-generated and not real FFI boundaries.
pub const CPP_ABI_INTERNAL = [_][]const u8{
    "__cxa_throw",
    "__cxa_begin_catch",
    "__cxa_end_catch",
    "__cxa_allocate_exception",
    "__cxa_free_exception",
    "__cxa_guard_acquire",
    "__cxa_guard_release",
    "__cxa_guard_abort",
    "__cxa_atexit",
    "__cxa_demangle",
    "__cxa_pure_virtual",
    "__cxa_deleted_virtual",
    "__cxa_finalize",
    "__cxa_thread_atexit",
    "__cxa_tm",
};

// ═══════════════════════════════════════════════════════════════
// Pattern Tables — C++ (RAII / Smart Pointers / STL)
// ═══════════════════════════════════════════════════════════════

/// C++ smart pointer operations and their ownership semantics.
pub const SMART_PTR_OPS = struct {
    /// Operations that release ownership (potential leak if result ignored).
    pub const releases_ownership = [_][]const u8{
        "unique_ptr::release",
        "auto_ptr::release",
    };
    /// Operations that delete old resource and take new one.
    pub const resets = [_][]const u8{
        "unique_ptr::reset",
        "shared_ptr::reset",
        "auto_ptr::reset",
    };
    /// Operations that return raw pointer without releasing ownership (borrowed).
    pub const borrows = [_][]const u8{
        "shared_ptr::get",
        "unique_ptr::get",
        "weak_ptr::lock",
    };
    /// Operations that attempt unique ownership transfer.
    pub const transfers = [_][]const u8{
        "shared_ptr::unique",
    };
};

/// STL container type names used for allocation classification.
///
/// These containers manage their own memory via RAII. When we see
/// construction of these, we know the memory will be freed in destructor.
pub const STL_CONTAINERS = [_][]const u8{
    "std::vector",
    "std::basic_string",
    "std::string",
    "std::map",
    "std::unordered_map",
    "std::set",
    "std::unordered_set",
    "std::array",
    "std::deque",
    "std::list",
    "std::forward_list",
    "std::queue",
    "std::stack",
};

// ═══════════════════════════════════════════════════════════════
// C++ Allocation Type Classification
// ═══════════════════════════════════════════════════════════════

/// Classification of a C++ allocation site's container type.
pub const CppAllocType = enum {
    /// std::vector<T> — contiguous dynamic array with RAII cleanup.
    vector,
    /// std::string / std::basic_string — RAII string with internal buffer.
    string,
    /// std::map / std::unordered_map — associative container with node-based allocation.
    map,
    /// Any other STL container (set, deque, list, etc.).
    stl_container,
    /// std::unique_ptr / std::shared_ptr — smart pointer wrapper.
    smart_ptr,
    /// Raw new/malloc call — manual lifetime management required.
    raw_pointer,
};

// ═══════════════════════════════════════════════════════════════
// Adapter Instances
// ═══════════════════════════════════════════════════════════════

/// Singleton instance for plain C code analysis.
pub const c_instance = adapter_mod.LanguageAdapter{
    .name = "c",
    .language = .c,
    .memory_model = .manual,
    .vtable = .{
        .analyzeFn = cAnalyzeFunction,
        .classifyFn = cClassifyCall,
        .suppressFn = cShouldSuppress,
        .owningPatternsFn = cGetOwningPatterns,
        .borrowingPatternsFn = cGetBorrowingPatterns,
    },
};

/// Singleton instance for C++ code analysis.
pub const cpp_instance = adapter_mod.LanguageAdapter{
    .name = "cpp",
    .language = .cpp,
    .memory_model = .raii,
    .vtable = .{
        .analyzeFn = cppAnalyzeFunction,
        .classifyFn = cppClassifyCall,
        .suppressFn = cppShouldSuppress,
        .owningPatternsFn = cppGetOwningPatterns,
        .borrowingPatternsFn = cppGetBorrowingPatterns,
    },
};

// ═══════════════════════════════════════════════════════════════
// C Adapter Implementation
// ═══════════════════════════════════════════════════════════════

/// Classify a C function call by name.
///
/// Maps standard C library functions to their ownership semantics.
/// This is the baseline classification used when no language-specific
/// adapter matches.
pub fn cClassifyCall(
    self_ptr: *const adapter_mod.LanguageAdapter,
    callee_name: []const u8,
) FFISemantics {
    _ = self_ptr;

    for (C_ALLOCATORS) |f| {
        if (std.mem.eql(u8, callee_name, f)) return .returns_owned;
    }
    for (C_DEALLOCATORS) |f| {
        if (std.mem.eql(u8, callee_name, f)) return .consumes_arg;
    }
    for (C_BORROWING_FUNCTIONS) |f| {
        if (std.mem.eql(u8, callee_name, f)) return .returns_borrowed;
    }

    return .unknown;
}

/// Check if a C function should be suppressed from FFI boundary analysis.
pub fn cShouldSuppress(
    self_ptr: *const adapter_mod.LanguageAdapter,
    func_name: []const u8,
) bool {
    _ = self_ptr;
    // C has few internal functions to suppress — most are real boundaries
    _ = func_name;
    return false;
}

/// Return C allocator pattern list.
pub fn cGetOwningPatterns(self_ptr: *const adapter_mod.LanguageAdapter) []const []const u8 {
    _ = self_ptr;
    return &C_ALLOCATORS;
}

/// Return C borrowing pattern list.
pub fn cGetBorrowingPatterns(self_ptr: *const adapter_mod.LanguageAdapter) []const []const u8 {
    _ = self_ptr;
    return &C_BORROWING_FUNCTIONS;
}

/// Full IR analysis placeholder for C functions.
pub fn cAnalyzeFunction(
    self_ptr: *const adapter_mod.LanguageAdapter,
    func_opaque: *anyopaque,
    ctx: adapter_mod.ContextPtr,
    allocator: std.mem.Allocator,
) !types.AdapterAnalysis {
    _ = func_opaque;
    _ = ctx;

    var result = try types.AdapterAnalysis.init(allocator, self_ptr.language);
    errdefer result.deinit();
    result.confidence = 0.90; // High confidence for C pattern matching
    return result;
}

// ═══════════════════════════════════════════════════════════════
// C++ Adapter Implementation
// ═══════════════════════════════════════════════════════════════

/// Classify a C++ function call by name.
///
/// Extends the C classifier with smart pointer and STL awareness.
/// Mangled names (Itanium _Z* / MSVC ?*) are handled here too.
pub fn cppClassifyCall(
    self_ptr: *const adapter_mod.LanguageAdapter,
    callee_name: []const u8,
) FFISemantics {
    // Delegate to C classifier first (handles plain C names like malloc/free)
    const c_result = cClassifyCall(self_ptr, callee_name);
    if (c_result != .unknown) return c_result;

    // Smart pointer: release → potential leak (returns_owned to caller)
    for (SMART_PTR_OPS.releases_ownership) |f| {
        if (std.mem.indexOf(u8, callee_name, f) != null) return .returns_owned;
    }
    // Smart pointer: reset → consumes old value
    for (SMART_PTR_OPS.resets) |f| {
        if (std.mem.indexOf(u8, callee_name, f) != null) return .consumes_arg;
    }
    // Smart pointer: get → borrowed reference
    for (SMART_PTR_OPS.borrows) |f| {
        if (std.mem.indexOf(u8, callee_name, f) != null) return .returns_borrowed;
    }

    // operator new / operator delete (mangled forms)
    if (isCppOperatorNew(callee_name)) return .returns_owned;
    if (isCppOperatorDelete(callee_name)) return .consumes_arg;

    // Destructor calls (~ClassName) — consume the object
    if (isDestructor(callee_name)) return .consumes_arg;

    return .unknown;
}

/// Suppress C++ ABI internal functions from analysis.
pub fn cppShouldSuppress(
    self_ptr: *const adapter_mod.LanguageAdapter,
    func_name: []const u8,
) bool {
    _ = self_ptr;

    for (CPP_ABI_INTERNAL) |f| {
        if (std.mem.indexOf(u8, func_name, f) != null) return true;
    }

    // Suppress STL template instantiations (compiler-generated)
    if (isStlInternal(func_name)) return true;

    return false;
}

/// Return C++ owning pattern list (includes C allocators + operator new).
pub fn cppGetOwningPatterns(self_ptr: *const adapter_mod.LanguageAdapter) []const []const u8 {
    _ = self_ptr;
    return &C_ALLOCATORS;
}

/// Return C++ borrowing pattern list (smart pointer get + C borrowing).
pub fn cppGetBorrowingPatterns(self_ptr: *const adapter_mod.LanguageAdapter) []const []const u8 {
    _ = self_ptr;
    return &C_BORROWING_FUNCTIONS;
}

/// Full IR analysis placeholder for C++ functions.
pub fn cppAnalyzeFunction(
    self_ptr: *const adapter_mod.LanguageAdapter,
    func_opaque: *anyopaque,
    ctx: adapter_mod.ContextPtr,
    allocator: std.mem.Allocator,
) !types.AdapterAnalysis {
    _ = func_opaque;
    _ = ctx;

    var result = try types.AdapterAnalysis.init(allocator, self_ptr.language);
    errdefer result.deinit();
    result.confidence = 0.85;
    return result;
}

// ═══════════════════════════════════════════════════════════════
// C++ Specific Detection Helpers
// ═══════════════════════════════════════════════════════════════

/// Detect if an instruction is in an exception handling path.
///
/// In LLVM IR, exception paths use `invoke` instead of `call`, and
/// have corresponding `landingpad` blocks. Leaks on these paths are
/// particularly dangerous because they're triggered by exceptional
/// control flow that may be rare during testing.
pub fn isInExceptionPath(inst: *anyopaque) bool {
    _ = inst;
    // In full implementation, this would check:
    //   1. Is opcode == LLVMInvoke?
    //   2. Is parent BB a landingpad block?
    // Placeholder: always false until LLVM integration
    return false;
}

/// Classify a C++ allocation as container type or raw pointer.
///
/// Used by the memory graph to determine whether RAII cleanup applies.
/// Returns null for unrecognized allocations (treated as raw_pointer).
pub fn classifyCppAllocation(func_name: []const u8) ?CppAllocType {
    for (STL_CONTAINERS) |container| {
        if (std.mem.indexOf(u8, func_name, container) != null) {
            if (std.mem.indexOf(u8, func_name, "::vector") != null) return .vector;
            if (std.mem.indexOf(u8, func_name, "string") != null) return .string;
            if (std.mem.indexOf(u8, func_name, "map") != null) return .map;
            return .stl_container;
        }
    }

    // Smart pointer detection
    if (std.mem.indexOf(u8, func_name, "unique_ptr") != null or
        std.mem.indexOf(u8, func_name, "shared_ptr") != null)
    {
        return .smart_ptr;
    }

    return null; // Raw malloc/new or unknown
}

/// Check if a mangled name is a C++ destructor.
///
/// Matches both Itanium (_ZN<name>D<version>Ev) and MSVC (??1<name>@@...)
/// destructor mangling patterns.
pub fn isDestructor(func_name: []const u8) bool {
    // Itanium: _ZN<length><name>D<digits>Ev
    if (func_name.len > 4) {
        // Look for D<digit(s)>Ev pattern near end
        var j = func_name.len;
        while (j > 0) : (j -= 1) {
            if (func_name[j - 1] == 'D' and j < func_name.len) {
                const after_d = func_name[j..];
                if (after_d.len >= 2 and after_d[0] >= '0' and after_d[0] <= '9') {
                    if (std.mem.indexOf(u8, after_d, "Ev") != null) return true;
                }
            }
        }
    }

    // MSVC: ??1<name>@@ (destructor = ??1)
    if (func_name.len > 3 and func_name[0] == '?' and func_name[1] == '?' and func_name[2] == '1') {
        return true;
    }

    return false;
}

/// Check if a function name is a C++ operator new (mangled or unmangled).
pub fn isCppOperatorNew(func_name: []const u8) bool {
    if (std.mem.eql(u8, func_name, "operator new")) return true;
    if (std.mem.eql(u8, func_name, "operator new[]")) return true;
    // Itanium mangled: _Zn[w]*
    if (func_name.len > 2 and func_name[0] == '_' and func_name[1] == 'Z') {
        const rest = func_name[2..];
        if (std.mem.startsWith(u8, rest, "nw") or
            std.mem.startsWith(u8, rest, "na"))
        {
            return true;
        }
    }
    // MSVC mangled: ??2 or ??_U
    if (func_name.len > 2 and func_name[0] == '?' and
        (func_name[1] == '2' or (func_name[1] == '?' and func_name.len > 2 and func_name[2] == '_')))
    {
        return true;
    }
    return false;
}

/// Check if a function name is a C++ operator delete (mangled or unmangled).
pub fn isCppOperatorDelete(func_name: []const u8) bool {
    if (std.mem.eql(u8, func_name, "operator delete")) return true;
    if (std.mem.eql(u8, func_name, "operator delete[]")) return true;
    // Itanium mangled: _Zd[l]*
    if (func_name.len > 2 and func_name[0] == '_' and func_name[1] == 'Z') {
        const rest = func_name[2..];
        if (std.mem.startsWith(u8, rest, "dl") or
            std.mem.startsWith(u8, rest, "da"))
        {
            return true;
        }
    }
    // MSVC mangled: ??3 or ??_V
    if (func_name.len > 2 and func_name[0] == '?' and
        (func_name[1] == '3' or (func_name[1] == '?' and func_name.len > 2 and func_name[2] == '_')))
    {
        return true;
    }
    return false;
}

/// Check if a function name is an STL/libc++ internal template expansion.
///
/// These are compiler-generated implementations of STL templates and should
/// not be treated as user-level FFI boundaries.
pub fn isStlInternal(func_name: []const u8) bool {
    const stl_prefixes = [_][]const u8{
        "_ZNSt",       // std:: in Itanium (libstdc++)
        "_ZN3__",      // __gnu_debug, __gnu_parallel (libstdc++)
        "__gnu_debug",
        "__gnu_parallel",
        "_ZNSs",       // std::string methods
        "_ZNSb",       // std::basic_string methods
    };
    for (stl_prefixes) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) return true;
    }
    return false;
}

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "CppAdapter - C instance classifies allocators" {
    try testing.expectEqual(FFISemantics.returns_owned, c_instance.classifyCall("malloc"));
    try testing.expectEqual(FFISemantics.returns_owned, c_instance.classifyCall("calloc"));
    try testing.expectEqual(FFISemantics.returns_owned, c_instance.classifyCall("realloc"));
    try testing.expectEqual(FFISemantics.returns_owned, c_instance.classifyCall("strdup"));

    try testing.expectEqual(FFISemantics.consumes_arg, c_instance.classifyCall("free"));
}

test "CppAdapter - C instance classifies borrowing" {
    try testing.expectEqual(FFISemantics.returns_borrowed, c_instance.classifyCall("getenv"));
    try testing.expectEqual(FFISemantics.returns_borrowed, c_instance.classifyCall("strerror"));
    try testing.expectEqual(FFISemantics.returns_borrowed, c_instance.classifyCall("ctime"));
}

test "CppAdapter - C instance unknown defaults" {
    try testing.expectEqual(FFISemantics.unknown, c_instance.classifyCall("printf"));
    try testing.expectEqual(FFISemantics.unknown, c_instance.classifyCall("unknown_func"));
}

test "CppAdapter - C++ instance classifies smart pointers" {
    // release → returns ownership to caller (potential leak source!)
    try testing.expectEqual(FFISemantics.returns_owned, cpp_instance.classifyCall("unique_ptr::release"));
    // reset → consumes old value
    try testing.expectEqual(FFISemantics.consumes_arg, cpp_instance.classifyCall("unique_ptr::reset"));
    // get → borrowed reference
    try testing.expectEqual(FFISemantics.returns_borrowed, cpp_instance.classifyCall("shared_ptr::get"));
}

test "CppAdapter - C++ instance delegates to C for libc" {
    try testing.expectEqual(FFISemantics.returns_owned, cpp_instance.classifyCall("malloc"));
    try testing.expectEqual(FFISemantics.consumes_arg, cpp_instance.classifyCall("free"));
}

test "CppAdapter - C++ suppresses ABI internals" {
    try testing.expect(cpp_instance.shouldSuppress("__cxa_throw"));
    try testing.expect(cpp_instance.shouldSuppress("__cxa_begin_catch"));
    try testing.expect(cpp_instance.shouldSuppress("__cxa_allocate_exception"));

    // User code NOT suppressed
    try testing.expect(!cpp_instance.shouldSuppress("my_function"));
    try testing.expect(!cpp_instance.shouldSuppress("malloc"));
}

test "CppAdapter - C++ never suppresses (plain C)" {
    try testing.expect(!c_instance.shouldSuppress("__cxa_throw"));
    try testing.expect(!c_instance.shouldSuppress("anything"));
}

test "CppAdapter - classifyCppAllocation" {
    try testing.expectEqual(CppAllocType.vector, classifyCppAllocation("std::vector<int>::vector").?);
    try testing.expectEqual(CppAllocType.vector, classifyCppAllocation("_ZNSt6vectorIiEEC1Ev").?);
    try testing.expectEqual(CppAllocType.string, classifyCppAllocation("std::string::string").?);
    try testing.expectEqual(CppAllocType.map, classifyCppAllocation("std::map<int,int>::map").?);
    try testing.expectEqual(CppAllocType.stl_container, classifyCppAllocation("std::deque<int>::deque").?);
    try testing.expectEqual(CppAllocType.smart_ptr, classifyCppAllocation("std::unique_ptr<int>::unique_ptr").?);

    // Unknown → null
    try testing.expect(classifyCppAllocation("my_custom_alloc") == null);
    try testing.expect(classifyCppAllocation("malloc") == null);
}

test "CppAdapter - isDestructor detection" {
    // Itanium-mangled destructors contain D<n>E pattern
    try testing.expect(isDestructor("_ZN6MyClassD1Ev")); // ~MyClass()
    try testing.expect(isDestructor("_ZN6MyClassD0Ev")); // ~MyClass() (deleting)
    try testing.expect(isDestructor("_ZNSt6stringD1Ev")); // ~string()

    // MSVC-mangled destructors start with ??1
    try testing.expect(isDestructor("??1MyClass@@UEAA@XZ"));

    // Not destructors
    try testing.expect(!isDestructor("_ZN6MyClass3fooEv")); // MyClass::foo()
    try testing.expect(!isDestructor("malloc"));
    try testing.expect(!isDestructor("normal_function"));
}

test "CppAdapter - operator new/delete detection" {
    // Unmangled
    try testing.expect(isCppOperatorNew("operator new"));
    try testing.expect(isCppOperatorNew("operator new[]"));
    try testing.expect(isCppOperatorDelete("operator delete"));
    try testing.expect(isCppOperatorDelete("operator delete[]"));

    // Not operators
    try testing.expect(!isCppOperatorNew("malloc"));
    try testing.expect(!isCppOperatorDelete("free"));
}

test "CppAdapter - isStlInternal detection" {
    try testing.expect(isStlInternal("_ZNSt6vectorIiEE9push_backERKi"));
    try testing.expect(isStlInternal("_ZN3__14debug"));
    try testing.expect(isStlInternal("__gnu_debug::_Safe_iterator"));

    // Not STL internal
    try testing.expect(!isStlInternal("my_function"));
    try testing.expect(!isStlInternal("malloc"));
}

test "CppAdapter - instance metadata" {
    try testing.expectEqualStrings("c", c_instance.name);
    try testing.expectEqual(Language.c, c_instance.language);
    try testing.expectEqual(types.MemoryModel.manual, c_instance.memory_model);

    try testing.expectEqualStrings("cpp", cpp_instance.name);
    try testing.expectEqual(Language.cpp, cpp_instance.language);
    try testing.expectEqual(types.MemoryModel.raii, cpp_instance.memory_model);
}

test "CppAdapter - pattern lists non-empty" {
    try testing.expect(c_instance.getOwningPatterns().len > 0);
    try testing.expect(c_instance.getBorrowingPatterns().len > 0);
    try testing.expect(cpp_instance.getOwningPatterns().len > 0);
}

const testing = std.testing;
