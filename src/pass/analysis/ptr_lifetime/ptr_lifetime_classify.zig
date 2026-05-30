const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;

const pt = @import("ptr_lifetime_types.zig");
const ResourceType = pt.ResourceType;
const HEAP_ALLOC_FUNCTIONS = pt.HEAP_ALLOC_FUNCTIONS;
const KNOWN_DEALLOCATORS = pt.KNOWN_DEALLOCATORS;
const Language = @import("../../../semantics/zone_classifier.zig").Language;
const posix_syscalls = @import("../../../semantics/nomicon/posix_syscalls.zig");

/// Function classification and identification utilities for PtrLifetimePass.
/// Extracted from ptr_lifetime.zig to improve code organization.
///
/// This module contains pure functions that classify LLVM function names
/// into categories (alloc/free/resource) based on naming conventions.
/// No state is maintained — all functions are deterministic lookups.
/// Helper: check if haystack contains ANY of the needles (substring match).
fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.mem.indexOf(u8, haystack, needle) != null) return true;
    }
    return false;
}

pub fn isIntentionalOwnershipTransfer(func_name: []const u8) bool {
    const factory_prefixes = [_][]const u8{
        "create", "Create", "CREATE",
        "new",    "New",    "NEW",
        "make",   "Make",   "MAKE",
        "alloc",  "Alloc",  "ALLOC",
        "malloc", "calloc", "realloc",
        "open",   "Open",   "init",
        "Init",   "dup",    "Dup",
        "clone",  "Clone",  "copy",
        "Copy",   "from",   "From",
        "wrap",   "Wrap",   "build",
        "Build",
    };
    for (factory_prefixes) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) return true;
    }
    const factory_suffixes = [_][]const u8{
        "_create", "_new",  "_make", "_alloc",
        "_new_",   "_init", "_ctor", "_construct",
        "_clone",  "_copy", "_dup",  "_from",
    };
    for (factory_suffixes) |suffix| {
        if (std.mem.endsWith(u8, func_name, suffix)) return true;
    }
    return false;
}

/// PERF: Pre-computed exact-match set for common free/dealloc functions.
/// Avoids repeated string comparison overhead on the hot path.
const EXACT_FREE_SET = blk: {
    const entries = [_][]const u8{
        // C standard library
        "free",                  "cfree",      "realloc",        "g_free",           "kfree",           "vfree",
        "c_free",                "c_malloc",
        // Rust global allocator
          "__rust_dealloc", "__rdl_dealloc",    "__rg_dealloc",
        // Go/cgo runtime
           "_cgo_free",
        // Common deallocators
        "dealloc",               "deallocate",
        // Objective-C runtime
        "objc_release",   "objc_autorelease", "CFRelease",       "CGImageRelease",
        "NSDeallocateObject",
        // Python C API
           "PyMem_Free", "PyObject_Free",
        // JNI
         "DeleteLocalRef",   "DeleteGlobalRef",
        // Node.js N-API
        "napi_unref",
        "napi_delete_reference",
    };
    break :blk entries;
};

pub fn isFreeFunction(fn_name: []const u8) bool {
    // PERF: Fast path — exact match for common free/dealloc functions.
    // Uses comptime-defined array for O(N) scan with cheap eql comparisons.
    for (EXACT_FREE_SET) |exact| {
        if (std.mem.eql(u8, fn_name, exact)) return true;
    }
    // Suffix patterns: function must END with these to avoid false positives
    // on names like "free_size", "freestyle", "set_freedom" etc.
    const suffixes = [_][]const u8{
        "_free",    "_dealloc", "_deallocate",
        "_release", "_destroy", "_drop",
        "delete",   "Delete",   "deallocate",
        "Deallocate", "GoFree", // _Cfunc_GoFree pattern
    };
    for (suffixes) |suffix| {
        if (fn_name.len >= suffix.len and
            std.mem.eql(u8, fn_name[fn_name.len - suffix.len ..], suffix))
        {
            return true;
        }
    }
    // C++ operator delete — mangled (Itanium ABI) and unmangled
    if (std.mem.indexOf(u8, fn_name, "operator delete") != null) return true;
    if (containsAny(fn_name, &[_][]const u8{
        "_ZdlPv",  "_ZdaPv",  "_Zdl",  "_Zda",
        "__ZdlPv", "__ZdaPv", "__Zdl", "__Zda",
    }))
        return true;
    return false;
}

/// Classify an allocation function's language/runtime origin.
/// Used by cross_language_free detection to determine alloc_lang mismatch.
pub fn classifyAllocLanguage(fn_name: []const u8) ?[]const u8 {
    // Rust global allocator
    if (containsAny(fn_name, &[_][]const u8{ "__rust_alloc", "__rdl_alloc", "__rg_alloc" }))
        return "rust";
    // C++ operator new — Itanium ABI mangled names.
    // NOTE: _Znwm may also appear in Rust modules (Rust's std::alloc::alloc
    // can compile to _Znwm). Use classifyAllocLanguageEnum with module_lang
    // to disambiguate. Here we conservatively return "cpp".
    if (containsAny(fn_name, &[_][]const u8{
        "_Znwm",  "_Znam",  "_Znw",  "_Zna",
        "__Znwm", "__Znam", "__Znw", "__Zna",
    }))
        return "cpp";
    if (std.mem.indexOf(u8, fn_name, "operator new") != null)
        return "cpp";
    // C standard library
    if (containsAny(fn_name, &[_][]const u8{ "malloc", "calloc", "realloc", "aligned_alloc" }))
        return "c";
    // Go/cgo runtime
    if (containsAny(fn_name, &[_][]const u8{ "_cgo_allocate", "_Cfunc_GoMalloc", "_Cfunc_GoAlloc" }))
        return "go";
    // Go/TinyGo runtime allocators (from TINYGO_IR_SPEC.md)
    // TinyGo uses runtime.alloc/runtime.free as its primary heap interface.
    // Standard Go (gc) uses runtime.newobject for GC-managed allocations.
    // CGo bridge functions use _cgo_* prefixes.
    if (containsAny(fn_name, &[_][]const u8{
        "runtime.alloc",
        "runtime.realloc",
        "runtime.mallocgc",
        "runtime.newobject",
        "runtime.cmalloc",
        "runtime.persistentalloc",
        "tinygo_alloc",
    }))
        return "go";
    // Zig standard library / runtime allocators
    // Zig's heap.PageAllocator, heap.GeneralPoolAllocator, and arena allocators
    // compile to these internal symbols in release builds.
    // Also catches @import("c") wrappers that delegate to Zig allocators.
    if (containsAny(fn_name, &[_][]const u8{
        "zig_alloc",
        "__zig_alloc",
        "PageAllocator.alloc",
        "GeneralPoolAllocator.alloc",
        "ArenaAllocator.alloc",
        "heap.page_allocator",
        "heap.general_pool_allocator",
        "heap.ArenaAllocator",
        "c_allocator",
        "gpa.",
    }))
        return "zig";
    // Objective-C
    if (containsAny(fn_name, &[_][]const u8{ "objc_alloc", "class_createInstance", "NSAllocateObject" }))
        return "objc";
    // Python C API
    if (containsAny(fn_name, &[_][]const u8{ "PyMem_Malloc", "PyObject_Malloc", "PyObject_New", "PyList_New", "PyDict_New" }))
        return "python";
    // JNI
    if (containsAny(fn_name, &[_][]const u8{ "NewGlobalRef", "NewLocalRef", "FindClass" }))
        return "java";
    // Node.js N-API
    if (containsAny(fn_name, &[_][]const u8{ "napi_create_", "napi_get_cb_info" }))
        return "nodejs";
    // C# / .NET — P/Invoke unmanaged memory + COM interop
    // NativeAOT compiles these to their mangled/linked forms.
    // Marshal.AllocHGlobal / Marshal.FreeHGlobal are the primary FFI allocators.
    if (containsAny(fn_name, &[_][]const u8{
        "Marshal_AllocHGlobal", "Marshal_FreeHGlobal",
        "CoTaskMemAlloc",       "CoTaskMemFree",
        "LocalAlloc",           "LocalFree",
        "HeapAlloc",            "HeapFree",
    }))
        return "csharp";
    return null;
}

/// Classify an allocation function's language as a Language enum.
/// Returns the language of the allocator function itself, or null if unknown.
/// Used by ptr_lifetime.zig to set alloc_lang from the actual allocator
/// rather than the module-level language — fixes cross_language_free FP
/// when C++ modules use malloc (C allocator) but alloc_lang was set to .cpp.
///
/// `module_lang` disambiguates _Znwm (C++ operator new vs Rust global alloc):
/// in a Rust module, _Znwm is Rust's std::alloc::alloc; in C++, it's operator new.
pub fn classifyAllocLanguageEnum(fn_name: []const u8, module_lang: ?Language) ?Language {
    // Rust global allocator — always unambiguous
    if (containsAny(fn_name, &[_][]const u8{ "__rust_alloc", "__rdl_alloc", "__rg_alloc" }))
        return .rust;
    // C++ operator new (Itanium ABI mangled) — ambiguous with Rust.
    // Rust's std::alloc::alloc compiles to _Znwm in some configurations.
    // Disambiguate by module language.
    if (containsAny(fn_name, &[_][]const u8{
        "_Znwm",  "_Znam",  "_Znw",  "_Zna",
        "__Znwm", "__Znam", "__Znw", "__Zna",
    })) {
        if (module_lang) |ml| {
            if (ml == .rust) return .rust;
        }
        return .cpp;
    }
    if (std.mem.indexOf(u8, fn_name, "operator new") != null)
        return .cpp;
    // C standard library
    if (containsAny(fn_name, &[_][]const u8{ "malloc", "calloc", "realloc", "aligned_alloc" }))
        return .c;
    // Go/cgo runtime
    if (containsAny(fn_name, &[_][]const u8{ "_cgo_allocate", "_Cfunc_GoMalloc", "_Cfunc_GoAlloc" }))
        return .go;
    // Go/TinyGo runtime allocators
    if (containsAny(fn_name, &[_][]const u8{
        "runtime.alloc",   "runtime.realloc", "runtime.mallocgc", "runtime.newobject",
        "runtime.cmalloc", "tinygo_alloc",
    }))
        return .go;
    // JNIZig standard library / runtime allocators
    // Zig standard library / runtime allocators
    if (containsAny(fn_name, &[_][]const u8{
        "zig_alloc",
        "__zig_alloc",
        "PageAllocator.alloc",
        "heap.page_allocator",
        "c_allocator",
    }))
        return .zig;
    // JNI
    if (containsAny(fn_name, &[_][]const u8{ "NewGlobalRef", "NewLocalRef", "FindClass" }))
        return .java;
    // Python C API
    if (containsAny(fn_name, &[_][]const u8{ "PyMem_Malloc", "PyObject_Malloc", "PyObject_New", "PyList_New", "PyDict_New" }))
        return .python;
    // C# / .NET — P/Invoke unmanaged memory allocators
    if (containsAny(fn_name, &[_][]const u8{
        "Marshal_AllocHGlobal", "CoTaskMemAlloc", "GCHandle_Alloc", "LocalAlloc", "HeapAlloc",
    }))
        return .csharp;
    // Zig synthetic allocator
    if (containsAny(fn_name, &[_][]const u8{ "zig_allocator_alloc", "zig_allocator_free" }))
        return .zig;
    return null;
}

/// Classify a free/dealloc function's language/runtime origin.
pub fn classifyFreeLanguage(fn_name: []const u8) ?[]const u8 {
    // POSIX syscall classification: file/network/process operations are NOT memory frees
    // This prevents false positives like Bun__unlink being classified as a free function
    const syscall_class = posix_syscalls.classifySyscall(fn_name);
    if (syscall_class == .file_operation or syscall_class == .network_operation or syscall_class == .process_operation) {
        return null; // Not a memory free operation
    }

    if (containsAny(fn_name, &[_][]const u8{ "__rust_dealloc", "__rdl_dealloc", "__rg_dealloc" }))
        return "rust";
    // C++ operator delete — Itanium ABI mangled names + unmangled
    if (containsAny(fn_name, &[_][]const u8{
        "_ZdlPv",  "_ZdaPv",  "_Zdl",  "_Zda",
        "__ZdlPv", "__ZdaPv", "__Zdl", "__Zda",
    }))
        return "cpp";
    if (std.mem.indexOf(u8, fn_name, "operator delete") != null)
        return "cpp";
    if (std.mem.eql(u8, fn_name, "free") or containsAny(fn_name, &[_][]const u8{ "cfree", "kfree" }))
        return "c";
    if (containsAny(fn_name, &[_][]const u8{ "_cgo_free", "_Cfunc_GoFree" }))
        return "go";
    // Go/TinyGo runtime deallocators (from TINYGO_IR_SPEC.md)
    // TinyGo: runtime.free is the primary deallocator
    // Standard Go: runtime.GC / runtime.markfinalizer manage lifecycle
    if (containsAny(fn_name, &[_][]const u8{
        "runtime.free",
        "tinygo_free",
    }))
        return "go";
    if (containsAny(fn_name, &[_][]const u8{ "objc_release", "CFRelease", "CGImageRelease" }))
        return "objc";
    if (containsAny(fn_name, &[_][]const u8{ "PyMem_Free", "PyObject_Free", "Py_DECREF" }))
        return "python";
    if (containsAny(fn_name, &[_][]const u8{ "DeleteLocalRef", "DeleteGlobalRef" }))
        return "java";
    // C# / .NET — P/Invoke unmanaged memory free + COM interop
    if (containsAny(fn_name, &[_][]const u8{
        "Marshal_FreeHGlobal", "CoTaskMemFree", "GCHandle_Free", "LocalFree", "HeapFree",
    }))
        return "csharp";
    // Zig synthetic deallocator
    if (containsAny(fn_name, &[_][]const u8{"zig_allocator_free"}))
        return "zig";
    // Zig standard library / runtime deallocators
    // Note: C's "free()" called from Zig code (via @cImport) is NOT
    // classified here — it remains "c" because that's the correct
    // classification for interop scenarios where C allocs and Zig frees via C API.
    //
    // Reason: POSIX attribute cleanup functions contain "destroy" but are
    // NOT Zig deallocators. They clean up pthread attribute objects (stack or
    // struct-embedded), not heap memory. Must exclude BEFORE matching "destroy"
    // to prevent false positives like _pthread_mutexattr_destroy() being
    // classified as a Zig deallocator → cross_language_free CRITICAL FP.
    const posix_attr_cleanup = [_][]const u8{
        "pthread_mutexattr_destroy",
        "pthread_condattr_destroy",
        "pthread_rwlockattr_destroy",
        "_pthread_mutexattr_destroy", // macOS variant
        "_pthread_condattr_destroy",
        "_pthread_rwlockattr_destroy",
    };
    if (containsAny(fn_name, &posix_attr_cleanup)) {
        // Not a Zig deallocator — fall through to return null
    } else if (containsAny(fn_name, &[_][]const u8{
        "__zig_dealloc",
        "zig_free",
        "PageAllocator.free",
        "PageAllocator.rawFree",
        "GeneralPoolAllocator.free",
        "ArenaAllocator.free",
        "heap.page_allocator.free",
        "destroy", // allocator.destroy() in Zig IR
        "rawDestroy",
    }))
        return "zig";
    return null;
}

/// PERF: Pre-computed exact-match set for common resource close functions.
/// Avoids repeated std.mem.indexOf calls on the hot path.
const EXACT_RESOURCE_CLOSE = struct {
    const exact = [_]struct { name: []const u8, rt: ResourceType }{
        .{ .name = "dlclose", .rt = .dlopen_handle },
        .{ .name = "munmap", .rt = .mmap_region },
        .{ .name = "fclose", .rt = .file_handle },
        .{ .name = "DeleteGlobalRef", .rt = .jni_ref },
        .{ .name = "DeleteLocalRef", .rt = .jni_ref },
        .{ .name = "Py_DECREF", .rt = .python_obj },
        .{ .name = "Py_XDECREF", .rt = .python_obj },
    };
};

pub fn isResourceCloseFunction(fn_name: []const u8) ?ResourceType {
    // PERF: Fast path — exact match for common resource close functions.
    // std.mem.eql is cheaper than std.mem.indexOf (no substring scan).
    for (EXACT_RESOURCE_CLOSE.exact) |entry| {
        if (std.mem.eql(u8, fn_name, entry.name)) return entry.rt;
    }
    // Slower path — substring match for prefixed/mangled names.
    if (std.mem.indexOf(u8, fn_name, "dlclose") != null) return .dlopen_handle;
    if (std.mem.indexOf(u8, fn_name, "munmap") != null) return .mmap_region;
    if (std.mem.indexOf(u8, fn_name, "fclose") != null) return .file_handle;
    if (isSocketClose(fn_name)) return .socket_fd;
    if (std.mem.indexOf(u8, fn_name, "DeleteGlobalRef") != null or
        std.mem.indexOf(u8, fn_name, "DeleteLocalRef") != null) return .jni_ref;
    if (std.mem.indexOf(u8, fn_name, "Py_DECREF") != null or
        std.mem.indexOf(u8, fn_name, "Py_XDECREF") != null) return .python_obj;
    return null;
}

pub fn isSameOrAlias(a: c.LLVMValueRef, b: c.LLVMValueRef) bool {
    if (@intFromPtr(a) == @intFromPtr(b)) return true;
    if (isDerivedFrom(a, b) or isDerivedFrom(b, a)) return true;
    return false;
}

pub fn isDerivedFrom(value: c.LLVMValueRef, base: c.LLVMValueRef) bool {
    if (@intFromPtr(value) == 0 or @intFromPtr(base) == 0) return false;
    const opcode = c.LLVMGetInstructionOpcode(value);
    if (opcode == c.LLVMBitCast or opcode == c.LLVMPtrToInt or
        opcode == c.LLVMIntToPtr or opcode == c.LLVMAddrSpaceCast)
    {
        const src = c.LLVMGetOperand(value, 0);
        if (@intFromPtr(src) == @intFromPtr(base)) return true;
        if (isDerivedFrom(src, base)) return true;
    }
    if (opcode == c.LLVMGetElementPtr) {
        const ptr_op = c.LLVMGetOperand(value, 0);
        if (@intFromPtr(ptr_op) == @intFromPtr(base)) return true;
        if (isDerivedFrom(ptr_op, base)) return true;
    }
    return false;
}

pub fn isSocketClose(fn_name: []const u8) bool {
    const non_socket_patterns = [_][]const u8{
        "file_",   "document", "database",  "db_",
        "window",  "dir_",     "stream",    "buf_",
        "mem_",    "str_",     "xml_",      "json_",
        "log_",    "config",   "session",   "cache",
        "mutex",   "lock",     "semaphore", "cond_",
        "thread",  "process",  "handle",    "ref_",
        "context", "scope",    "state",     "node",
    };
    for (non_socket_patterns) |np| {
        if (std.mem.indexOf(u8, fn_name, np) != null and
            std.mem.indexOf(u8, fn_name, "close") != null)
        {
            return false;
        }
    }

    const exact_matches = [_][]const u8{
        "close", "::close",
    };
    for (exact_matches) |m| {
        if (std.mem.eql(u8, fn_name, m)) return true;
    }
    const socket_patterns = [_][]const u8{
        "socket_close", "sock_close",  "fd_close",
        "::close(",     "posix_close", "shutdown",
    };
    for (socket_patterns) |p| {
        if (std.mem.indexOf(u8, fn_name, p) != null) return true;
    }
    if (std.mem.endsWith(u8, fn_name, "_close")) {
        const prefix = fn_name[0 .. fn_name.len - 6];
        const socket_prefixes = [_][]const u8{
            "sock",   "fd_",    "conn", "pipe",
            "listen", "accept",
        };
        for (socket_prefixes) |sp| {
            if (std.mem.indexOf(u8, prefix, sp) != null) return true;
        }
    }
    return false;
}

/// PERF: Pre-computed exact-match set for common resource alloc functions.
/// Avoids repeated std.mem.indexOf calls on the hot path.
const EXACT_RESOURCE_ALLOC = struct {
    /// Exact match entries (O(1) eql check before falling back to indexOf).
    const exact = [_]struct { name: []const u8, rt: ResourceType }{
        .{ .name = "dlopen", .rt = .dlopen_handle },
        .{ .name = "mmap64", .rt = .mmap_region },
        .{ .name = "mmap2", .rt = .mmap_region },
        .{ .name = "mmap", .rt = .mmap_region },
        .{ .name = "shm_open", .rt = .mmap_region },
        .{ .name = "fopen", .rt = .file_handle },
        .{ .name = "socket", .rt = .socket_fd },
    };
};

pub fn is_resource_alloc_function(fn_name: []const u8) ?ResourceType {
    // PERF: Fast path — exact match for common resource allocators.
    // std.mem.eql is cheaper than std.mem.indexOf (no substring scan).
    for (EXACT_RESOURCE_ALLOC.exact) |entry| {
        if (std.mem.eql(u8, fn_name, entry.name)) return entry.rt;
    }
    // Slower path — substring match for prefixed/mangled names.
    if (std.mem.indexOf(u8, fn_name, "dlopen") != null) return .dlopen_handle;
    if (std.mem.indexOf(u8, fn_name, "mmap") != null) return .mmap_region;
    if (std.mem.indexOf(u8, fn_name, "shm_open") != null) return .mmap_region;
    if (std.mem.indexOf(u8, fn_name, "fopen") != null) return .file_handle;
    if (std.mem.indexOf(u8, fn_name, "socket") != null) return .socket_fd;
    if (std.mem.indexOf(u8, fn_name, "JNI_") != null or
        std.mem.indexOf(u8, fn_name, "Java_") != null) return .jni_ref;
    if (std.mem.startsWith(u8, fn_name, "Py")) return .python_obj;
    return null;
}

pub fn get_resource_type(fn_name: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, fn_name, "dlopen") != null or std.mem.indexOf(u8, fn_name, "dlsym") != null) return "dlhandle";
    if (std.mem.indexOf(u8, fn_name, "mmap") != null) return "mmap";
    if (std.mem.indexOf(u8, fn_name, "fopen") != null or std.mem.indexOf(u8, fn_name, "FILE") != null) return "file";
    if (std.mem.indexOf(u8, fn_name, "socket") != null) return "socket";
    if (std.mem.indexOf(u8, fn_name, "JNI") != null) return "jni";
    if (std.mem.indexOf(u8, fn_name, "Py_") != null) return "python";
    return null;
}
