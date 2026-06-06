//! Free Validation — Pure Predicates (no PassContext needed)
//!
//! Pure functions for checking allocator/free function names, origins,
//! and safety predicates. Extracted from free_validation.zig to reduce
//! the God Struct pattern.

const std = @import("std");
const rust_drop_semantics = @import("../../../semantics/rust_drop_semantics.zig");
const ptr_types = @import("../ptr_lifetime/ptr_lifetime_types.zig");
const classify = @import("../ptr_lifetime/ptr_lifetime_classify.zig");
const ValueOrigin = @import("../ffi/ffi_semantics.zig").ValueOrigin;
const mg_types = @import("../../../types/memory_graph_types.zig");
const AllocNode = mg_types.AllocNode;
const FamilyId = mg_types.FamilyId;

/// Memory deallocation functions — basic memory deallocators for free validation.
/// NOTE: This is distinct from ptr_types.KNOWN_DEALLOCATORS.free_functions which
/// covers library-specific cleanup (sqlite3_free, curl_easy_cleanup, etc.).
pub const FREE_FUNCTIONS = &[_][]const u8{
    "free",           "dealloc",       "deallocate",   "operator delete", "operator delete[]",
    // Rust global deallocator intrinsics (substring-matched via isFreeFunction)
    "__rust_dealloc", "__rdl_dealloc", "__rg_dealloc",
};

/// Memory allocation functions — delegated to ptr_types (single source of truth).
pub const ALLOC_FUNCTIONS = ptr_types.HEAP_ALLOC_FUNCTIONS;

/// Check if function is a free function.
/// Uses exact match + endsWith to avoid FP like 'my_custom_free' matching 'free'.
pub fn isFreeFunction(func_name: []const u8) bool {
    return classify.isFreeFunction(func_name);
}

/// Check if function is an allocation function.
/// Delegates to ptr_types.isHeapAllocFunction (unified function catalog).
pub fn isAllocFunction(func_name: []const u8) bool {
    return ptr_types.isHeapAllocFunction(func_name);
}

/// Match strategy: exact equality OR suffix match.
/// Prevents substring FP (e.g., 'my_custom_free' ≠ 'free')
/// while still catching mangled names like '_ZN...freeEv'.
pub fn functionNameMatches(func_name: []const u8, pattern: []const u8) bool {
    if (std.mem.eql(u8, func_name, pattern)) return true;
    if (std.mem.endsWith(u8, func_name, pattern)) return true;
    return false;
}

/// Check if function is a Rust deallocation function.
/// Only matches actual Rust dealloc intrinsics (NOT general drop glue).
/// Drop glue includes destructors that don't necessarily deallocate memory.
pub fn isRustDeallocFunction(func_name: []const u8) bool {
    const rust_dealloc_patterns = [_][]const u8{
        "__rustc__rustc_dealloc",
        "__rust_dealloc",
    };
    for (rust_dealloc_patterns) |p| {
        if (std.mem.indexOf(u8, func_name, p) != null) return true;
    }
    return false;
}

/// Check if a function name is a Rust allocator call.
///
/// Covers four categories so that cross-language free detection has complete
/// visibility into all Rust allocation sources:
///   - Stable ABI:  __rust_alloc, __rust_alloc_zeroed, __rust_realloc
///   - Legacy ABI:  __rdl_alloc, __rdl_alloc_zeroed, __rg_alloc, __rg_alloc_zeroed
///   - v0 mangling: _R*...alloc... (Rust's modern name mangling)
///   - Itanium:     _ZN*...alloc... (older Rust, before v0 migration)
pub fn isRustAllocCall(func_name: []const u8) bool {
    // Stable Rust allocator ABI
    if (std.mem.eql(u8, func_name, "__rust_alloc") or
        std.mem.eql(u8, func_name, "__rust_alloc_zeroed") or
        std.mem.eql(u8, func_name, "__rust_realloc") or
        std.mem.eql(u8, func_name, "__rdl_alloc") or
        std.mem.eql(u8, func_name, "__rdl_alloc_zeroed") or
        std.mem.eql(u8, func_name, "__rg_alloc") or
        std.mem.eql(u8, func_name, "__rg_alloc_zeroed"))
    {
        return true;
    }
    // Rust v0 mangled names start with _R and contain alloc/allocate
    if (func_name.len > 4 and func_name[0] == '_' and func_name[1] == 'R') {
        const alloc_patterns = [_][]const u8{ "alloc", "allocate", "global_alloc" };
        for (alloc_patterns) |pat| {
            if (std.mem.indexOf(u8, func_name, pat) != null) {
                return true;
            }
        }
    }
    // Itanium-style (_ZN) Rust mangled names containing alloc patterns
    if (std.mem.startsWith(u8, func_name, "_ZN")) {
        const zn_alloc_patterns = [_][]const u8{ "alloc", "allocate", "global_alloc" };
        for (zn_alloc_patterns) |pat| {
            if (std.mem.indexOf(u8, func_name, pat) != null) {
                return true;
            }
        }
    }
    return false;
}

/// Check if a function name is a C++ operator new (mangled).
pub fn isCppNewCall(func_name: []const u8) bool {
    const cpp_new_patterns = [_][]const u8{
        "_Znwm", // operator new(unsigned long)
        "_Znam", // operator new[](unsigned long)
        "_ZnwmSt11align_val_t", // aligned new
        "_ZnamSt11align_val_t", // aligned new[]
    };
    for (cpp_new_patterns) |pat| {
        if (std.mem.indexOf(u8, func_name, pat) != null) {
            return true;
        }
    }
    return false;
}

/// Check if callee is an FFI boundary function (non-Rust-mangled name).
pub fn isFFIBoundaryCall(func_name: []const u8) bool {
    if (func_name.len < 2) return false;

    // Rust-internal functions: _ZN (legacy), _RNv / _R (v0 mangling)
    const rust_prefixes = [_][]const u8{ "_ZN", "_RNv", "_R" };
    for (rust_prefixes) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) return false;
    }

    // LLVM intrinsics
    if (std.mem.startsWith(u8, func_name, "llvm.")) return false;

    // Rust compiler intrinsics (__rust_alloc, __rust_dealloc, etc.)
    if (std.mem.startsWith(u8, func_name, "__rust_")) return false;
    if (std.mem.startsWith(u8, func_name, "__rdl_")) return false;
    if (std.mem.startsWith(u8, func_name, "__rg_")) return false;

    // Standard C library alloc/free functions — these are NOT FFI boundaries.
    const libc_functions = [_][]const u8{
        "malloc",        "calloc",         "realloc",  "free",
        "aligned_alloc", "posix_memalign", "memalign", "pvalloc",
        "valloc",        "strdup",         "strndup",
    };
    for (libc_functions) |libc_fn| {
        if (std.mem.eql(u8, func_name, libc_fn)) return false;
    }

    // C++ operator new/delete — same-language runtime, not FFI boundary
    if (std.mem.startsWith(u8, func_name, "operator new")) return false;
    if (std.mem.startsWith(u8, func_name, "operator delete")) return false;

    // Common C runtime wrappers that are NOT cross-language boundaries
    if (std.mem.startsWith(u8, func_name, "memcpy")) return false;
    if (std.mem.startsWith(u8, func_name, "memset")) return false;
    if (std.mem.startsWith(u8, func_name, "memmove")) return false;
    if (std.mem.startsWith(u8, func_name, "__cxa_")) return false;
    if (std.mem.startsWith(u8, func_name, "_Unwind_")) return false;

    return true;
}

/// Check if a free call crosses allocator boundaries.
/// Returns true when memory from one runtime's allocator is freed
/// by a different runtime's deallocator — almost always a bug.
pub fn isCrossAllocatorFree(alloc_origin: ValueOrigin, source_desc: []const u8, free_func: []const u8) bool {
    const is_rust_free = isRustDeallocFunction(free_func);
    const is_c_free = std.mem.eql(u8, free_func, "free") or
        std.mem.eql(u8, free_func, "kfree") or
        std.mem.eql(u8, free_func, "g_free");

    if (alloc_origin == .from_malloc) {
        const is_rust_alloc = std.mem.indexOf(u8, source_desc, "__rust_alloc") != null or
            std.mem.indexOf(u8, source_desc, "__rdl_alloc") != null or
            std.mem.indexOf(u8, source_desc, "__rg_alloc") != null;
        if (is_rust_alloc and is_c_free) return true;
        if (!is_rust_alloc and is_rust_free) return true;
    }

    if (alloc_origin == .from_ffi_call) {
        const is_rust_source = std.mem.indexOf(u8, source_desc, "__rust") != null or
            std.mem.indexOf(u8, source_desc, "_ZN") != null;
        if (is_rust_source and is_c_free) return true;
    }

    return false;
}

/// Check if the pointer may originate from Rust's into_raw() call.
pub fn isPossibleIntoRawOutput(source_desc: []const u8) bool {
    const into_raw_patterns = [_][]const u8{
        "into_raw",      "into_raw_parts",
        "Box::into_raw",
    };
    for (into_raw_patterns) |pat| {
        if (std.mem.indexOf(u8, source_desc, pat) != null) return true;
    }
    return false;
}

/// Determine if a free/dealloc call is safe in its FFI context.
/// Centralizes Rust ownership model awareness: when Rust code uses
/// __rust_dealloc on a pointer from Box::into_raw(), it's intentional
/// ownership reclamation — not a bug.
///
/// SECURITY POLICY (2026-05-05 tightened):
/// For C/C++: Established conventions allow broader trust (global statics, well-known wrappers).
/// For Rust/Zig: Stricter — these languages have ownership systems; if code bypasses them
/// via FFI, we require explicit safety proof (null checks, RAII, refcount), not assumptions.
pub fn isFreeSafe(free_func: []const u8, origin: ValueOrigin, source_desc: []const u8) bool {
    // Rust Drop Semantics: drop glue and drop-chain deallocs are
    // compiler-generated implicit destructors — NOT bugs.
    if (rust_drop_semantics.isImplicitDropFree(free_func, true, false, null)) return true;
    // Rust dealloc on param: normal ownership transfer (caller owns → callee frees)
    if (origin == .from_param and isRustDeallocFunction(free_func)) return true;
    // into_raw + matching Rust dealloc: correct ownership reclamation
    if (source_desc.len > 0 and isPossibleIntoRawOutput(source_desc) and isRustDeallocFunction(free_func)) return true;
    // FFI-sourced pointer freed by known safe wrappers only.
    if (origin == .from_ffi_call and !isRustDeallocFunction(free_func) and
        !std.mem.eql(u8, free_func, "free"))
    {
        const known_safe_wrappers = [_][]const u8{
            "g_free",        "CFRelease",            "CFAutorelease",
            "PyObject_Free", "PyMem_Free",           "cudaFree",
            "vkFreeMemory",  "ID3D12Device_Release", "VirtualFree",
            "HeapFree",      "munmap",               "mmap_free",
            "objc_release",  "NSDeallocateObject",   "CoTaskMemFree",
            "SysFreeString",
        };
        for (known_safe_wrappers) |wrapper| {
            if (std.mem.eql(u8, free_func, wrapper)) return true;
        }
    }
    // All other origins (.from_global, .unknown, etc.) default to unsafe.
    return false;
}

/// Check if this free call represents a valid Rust ownership transfer.
pub fn isRustOwnershipTransfer(node: *const AllocNode, callee_name: []const u8) bool {
    // Pattern 1: Mangled Rust names containing drop/Dealloc
    if (std.mem.indexOf(u8, callee_name, "_ZN") != null) {
        if (std.mem.indexOf(u8, callee_name, "drop") != null or
            std.mem.indexOf(u8, callee_name, "Dealloc") != null)
        {
            if (node.alloc_lang == .rust or node.alloc_family == .rust_global or node.alloc_family == .rust_box) {
                return true;
            }
        }
    }

    // Pattern 2: Known safe Rust deallocation patterns
    const rust_safe_patterns = [_][]const u8{
        "__rust_dealloc",
        "__rdl_dealloc",
        "__rg_dealloc",
    };
    for (rust_safe_patterns) |p| {
        if (std.mem.indexOf(u8, callee_name, p) != null) {
            return node.alloc_lang == .rust or
                node.alloc_family == .rust_global or
                node.alloc_family == .rust_box;
        }
    }

    // Pattern 3: Rust global allocator dealloc on Rust-allocated memory
    if (node.alloc_family == .rust_global or node.alloc_family == .rust_box) {
        if (std.mem.indexOf(u8, callee_name, "__rust") != null or
            std.mem.indexOf(u8, callee_name, "_ZN") != null)
        {
            return true;
        }
    }

    return false;
}

/// Detect cross-allocator free bugs: freeing memory with wrong allocator.
pub fn isCrossAllocatorMismatch(node: *const AllocNode, callee_name: []const u8) bool {
    const alloc_family = node.alloc_family orelse return false;

    // C/C++ allocator freed by Rust deallocator
    if (alloc_family == .c_heap or alloc_family == .c_mmap or alloc_family == .c_aligned or
        alloc_family == .cpp_new_scalar or alloc_family == .cpp_new_array)
    {
        if (std.mem.indexOf(u8, callee_name, "__rust_dealloc") != null or
            std.mem.indexOf(u8, callee_name, "__rdl_dealloc") != null or
            std.mem.indexOf(u8, callee_name, "__rg_dealloc") != null or
            std.mem.startsWith(u8, callee_name, "_ZN"))
        {
            return true;
        }
    }

    // Rust allocator freed by C/C++ free
    if (alloc_family == .rust_global or alloc_family == .rust_box) {
        if (std.mem.eql(u8, callee_name, "free") or
            std.mem.eql(u8, callee_name, "kfree") or
            std.mem.eql(u8, callee_name, "g_free") or
            std.mem.startsWith(u8, callee_name, "operator delete"))
        {
            return true;
        }
    }

    return false;
}

/// Check if this is a borrowed reference or refcounted object.
pub fn isBorrowedOrRefcount(node: *const AllocNode) bool {
    // Check ownership model
    if (node.ownership_model == .refcount) {
        return true;
    }
    // Check if GC-managed (GC objects shouldn't be manually freed)
    if (node.is_gc_managed) {
        return true;
    }
    // Check container type for smart containers that manage their own memory
    if (node.container_type) |ct| {
        return switch (ct) {
            .rust_box, .rust_vec, .rust_string => true,
            .cpp_unique_ptr, .cpp_shared_ptr, .std_vector, .std_string => true,
            .python_list, .python_dict => true,
            .go_slice, .go_map => true,
            .csharp_handle => true,
            .zig_arraylist, .zig_hashmap, .zig_buffer, .zig_multiarraylist => true,
            .unknown => false,
        };
    }
    return false;
}

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "isFreeFunction" {
    try std.testing.expect(isFreeFunction("free"));
    try std.testing.expect(isFreeFunction("dealloc"));
    try std.testing.expect(!isFreeFunction("malloc"));
    try std.testing.expect(!isFreeFunction("printf"));
}

test "isAllocFunction" {
    try std.testing.expect(isAllocFunction("malloc"));
    try std.testing.expect(isAllocFunction("calloc"));
    try std.testing.expect(!isAllocFunction("free"));
    try std.testing.expect(!isAllocFunction("printf"));
}

test "isRustAllocCall extended coverage" {
    // Stable ABI
    try std.testing.expect(isRustAllocCall("__rust_alloc"));
    try std.testing.expect(isRustAllocCall("__rust_alloc_zeroed"));
    try std.testing.expect(isRustAllocCall("__rust_realloc"));
    // Legacy (__rdl_ / __rg_)
    try std.testing.expect(isRustAllocCall("__rdl_alloc"));
    try std.testing.expect(isRustAllocCall("__rdl_alloc_zeroed"));
    try std.testing.expect(isRustAllocCall("__rg_alloc"));
    try std.testing.expect(isRustAllocCall("__rg_alloc_zeroed"));
    // v0 mangling (_R prefix)
    try std.testing.expect(isRustAllocCall("_RNvNtCsi3aA3my_lib4core4foo5allocE"));
    // Itanium (_ZN prefix)
    try std.testing.expect(isRustAllocCall("_ZN4alloc5allocE"));
    try std.testing.expect(isRustAllocCall("_ZN3std2io5allocateE"));
    // Negative cases
    try std.testing.expect(!isRustAllocCall("_ZN3foo3barE"));
    try std.testing.expect(!isRustAllocCall("malloc"));
    try std.testing.expect(!isRustAllocCall("free"));
}
