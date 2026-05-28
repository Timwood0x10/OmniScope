//! C/C++ Language Zone Classification
//!
//! Classifies C and C++ functions into safe/unsafe/ffi zones.
//! Handles C++ STL internals (_ZNSt*, _ZSt*), operator new/delete,
//! libc functions, SemanticRegistry lookup, and C FFI patterns.

const std = @import("std");

const zone_types = @import("../types/zone_types.zig");
const ZoneKind = zone_types.ZoneKind;
pub const CPP_SAFE_PATTERNS = zone_types.CPP_SAFE_PATTERNS;
pub const CPP_ESCAPE_PATTERNS = zone_types.CPP_ESCAPE_PATTERNS;
pub const C_ESCAPE_PATTERNS = zone_types.C_ESCAPE_PATTERNS;

/// Check if function name is a C++ STL internal helper (_ZNSt*).
pub fn isCppStlInternal(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "_ZNSt")) {
        return true;
    }

    if (std.mem.startsWith(u8, func_name, "_ZSt")) {
        return true;
    }

    return false;
}

/// Check if function is C++ operator new/delete (RAII-managed memory).
pub fn isCppOperatorNewDelete(func_name: []const u8) bool {
    const operators = [_][]const u8{
        "_Znwm",
        "_Znam",
        "_ZdlPv",
        "_ZdaPv",
        "_ZnwmRKSt9nothrow_t",
        "_ZnamRKSt9nothrow_t",
    };

    for (operators) |op| {
        if (std.mem.startsWith(u8, func_name, op)) {
            return true;
        }
    }

    return false;
}

/// Check if function is a known libc/C standard library function.
pub fn isLibcFunction(func_name: []const u8) bool {
    const libc_prefixes = [_][]const u8{
        "memcpy",  "memmove",  "memset", "memcmp",  "memchr",
        "strcpy",  "strncpy",  "strcat", "strncat", "strlen",
        "strcmp",  "strncmp",  "strchr", "strrchr", "strstr",
        "sprintf", "snprintf", "printf", "fprintf", "vprintf",
        "atoi",    "atol",     "atof",   "strtol",  "strtod",
        "strtoul", "abs",      "labs",   "fabs",    "ceil",
        "floor",   "round",    "qsort",  "bsearch",
    };

    for (libc_prefixes) |prefix| {
        if (std.mem.startsWith(u8, func_name, prefix)) {
            return true;
        }
    }

    return false;
}

/// Check if function name looks like runtime internal code.
pub fn isLikelyRuntimeInternal(name: []const u8) bool {
    const rust_stdlib_patterns = [_][]const u8{
        "_ZN4core",      "_ZN5alloc", "_ZN3std",
        "llvm.",         "__rust_",   "__cg",
        "drop_in_place", "panic_",
    };

    for (rust_stdlib_patterns) |pat| {
        if (std.mem.startsWith(u8, name, pat)) return true;
    }

    const rust_alloc_substrings = [_][]const u8{
        "__rust_dealloc", "__rust_alloc", "__rust_realloc", "__rust_alloc_zeroed",
        "__rdl_dealloc",  "__rdl_alloc",  "__rdl_realloc",  "__rg_dealloc",
        "__rg_alloc",     "__rg_realloc",
    };
    for (rust_alloc_substrings) |pat| {
        if (std.mem.indexOf(u8, name, pat) != null) return true;
    }

    const go_runtime_patterns = [_][]const u8{
        "runtime.",            "_cgo_",              "crosscall2",
        "__go_",               "__gcc_",             "runtime.gc",
        "runtime.mallocgc",    "runtime.scanobject", "runtime.markroot",
        "runtime.sweep",       "runtime.scanstack",  "runtime.schedule",
        "runtime.park",        "runtime.wake",       "runtime.stopm",
        "runtime.startm",      "runtime.handoffp",   "runtime.chan",
        "runtime.select",      "runtime.interface",  "runtime.assertI2I",
        "runtime.assertE2I",   "runtime.convI2E",    "runtime.mapaccess",
        "runtime.mapassign",   "runtime.mapdelete",  "runtime.mapiter",
        "runtime.newproc",     "runtime.goexit",     "runtime.systemstack",
        "runtime.morestack",   "runtime.lessstack",  "runtime.defer",
        "runtime.deferreturn", "reflect.",
    };

    for (go_runtime_patterns) |pat| {
        if (std.mem.startsWith(u8, name, pat)) return true;
    }

    const cc_stdlib_patterns = [_][]const u8{
        "__gnu_cxx",              "__cxa_",
        "__clang_call_terminate", "llvm.",
    };

    for (cc_stdlib_patterns) |pat| {
        if (std.mem.indexOf(u8, name, pat) != null) return true;
    }

    return false;
}

/// Classify a C++ function.
pub fn classifyCppFunction(func_name: []const u8) ZoneKind {
    const SemanticRegistry = @import("../registry/semantic_registry.zig").SemanticRegistry;

    for (CPP_ESCAPE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .unsafe;
        }
    }

    for (CPP_SAFE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .safe;
        }
    }

    for (C_ESCAPE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .ffi;
        }
    }

    if (std.mem.indexOf(u8, func_name, "extern \"C\"") != null) {
        return .ffi;
    }

    if (SemanticRegistry.lookup(func_name)) |sem| {
        switch (sem.kind) {
            .command_exec,
            .unchecked_copy,
            .format_string,
            .memory_map,
            .dynamic_loading,
            .jni,
            .python_c_api,
            .allocator,
            .deallocator,
            .network_io,
            .file_io,
            .signal_handler,
            .thread_mgmt,
            .process_mgmt,
            .rust_ownership,
            .borrow_escaped,
            .go_cgo_alloc,
            .zig_allocator,
            .cpp_allocator,
            .static_buffer,
            => return .ffi,
        }
    }

    return .unknown;
}

test "isLikelyRuntimeInternal - Rust stdlib" {
    try std.testing.expect(isLikelyRuntimeInternal("_ZN4core3ptr13drop_in_place"));
    try std.testing.expect(isLikelyRuntimeInternal("_ZN5alloc6raw_vec17RawVec"));
    try std.testing.expect(isLikelyRuntimeInternal("_ZN3std3fmt9Arguments"));
    try std.testing.expect(isLikelyRuntimeInternal("llvm.memcpy.p0i8.p0i8.i64"));
    try std.testing.expect(!isLikelyRuntimeInternal("_ZN4my_crate3foo3bar"));
}

test "isLikelyRuntimeInternal - Go runtime" {
    try std.testing.expect(isLikelyRuntimeInternal("runtime.mallocgc"));
    try std.testing.expect(isLikelyRuntimeInternal("_cgo_12345"));
    try std.testing.expect(isLikelyRuntimeInternal("crosscall2"));
    try std.testing.expect(!isLikelyRuntimeInternal("main.main"));
}

test "isLikelyRuntimeInternal - C/C++ stdlib" {
    try std.testing.expect(isLikelyRuntimeInternal("__gnu_cxx::__enable_if"));
    try std.testing.expect(isLikelyRuntimeInternal("__cxa_begin_catch"));
    try std.testing.expect(isLikelyRuntimeInternal("__clang_call_terminate"));
    try std.testing.expect(!isLikelyRuntimeInternal("my_function"));
}

test "classifyCppFunction - CPP_ESCAPE_PATTERNS" {
    try std.testing.expectEqual(ZoneKind.unsafe, classifyCppFunction("reinterpret_cast<int*>"));
    try std.testing.expectEqual(ZoneKind.unsafe, classifyCppFunction("const_cast<int*>"));
    try std.testing.expectEqual(ZoneKind.unsafe, classifyCppFunction("static_cast<void*>"));
    try std.testing.expectEqual(ZoneKind.unsafe, classifyCppFunction("std::thread"));
    try std.testing.expectEqual(ZoneKind.unsafe, classifyCppFunction("CreateThread"));
}

test "classifyCppFunction - CPP_SAFE_PATTERNS" {
    try std.testing.expectEqual(ZoneKind.safe, classifyCppFunction("std::vector<int>::push_back"));
    try std.testing.expectEqual(ZoneKind.safe, classifyCppFunction("std::string::c_str"));
    try std.testing.expectEqual(ZoneKind.safe, classifyCppFunction("std::unique_ptr::get"));
    try std.testing.expectEqual(ZoneKind.safe, classifyCppFunction("std::shared_ptr::clone"));
    try std.testing.expectEqual(ZoneKind.safe, classifyCppFunction("std::map::insert"));
}

test "classifyCppFunction - extern C" {
    try std.testing.expectEqual(ZoneKind.ffi, classifyCppFunction("extern \"C\" my_func"));
    try std.testing.expectEqual(ZoneKind.ffi, classifyCppFunction("extern \"C\" void foo()"));
}

test "classifyCppFunction - unknown" {
    try std.testing.expectEqual(ZoneKind.unknown, classifyCppFunction("my_custom_function"));
    try std.testing.expectEqual(ZoneKind.unknown, classifyCppFunction("some_internal_func"));
}

test "isCppStlInternal - detects STL mangled names" {
    try std.testing.expect(isCppStlInternal("_ZNSt6vectorIiEE9push_backERKi"));
    try std.testing.expect(isCppStlInternal("_ZNSt7basic_stringIcSt11char_traitsIcESaIcEE5c_strEv"));
    try std.testing.expect(isCppStlInternal("_ZNSt3mapIiiSt4lessIiSaIiEE6insertERKi"));
    try std.testing.expect(isCppStlInternal("_ZSt4sortIPiEvT_S3_"));
    try std.testing.expect(isCppStlInternal("_ZSt3maxIiET_RKS1_S1_"));
    try std.testing.expect(!isCppStlInternal("_Z9my_funcv"));
    try std.testing.expect(!isCppStlInternal("_ZN4user6class3fooEv"));
}

test "isCppOperatorNewDelete - detects memory operators" {
    try std.testing.expect(isCppOperatorNewDelete("_Znwm"));
    try std.testing.expect(isCppOperatorNewDelete("_Znam"));
    try std.testing.expect(isCppOperatorNewDelete("_ZdlPv"));
    try std.testing.expect(isCppOperatorNewDelete("_ZdaPv"));
    try std.testing.expect(!isCppOperatorNewDelete("_Z9my_funcv"));
    try std.testing.expect(!isCppOperatorNewDelete("malloc"));
}

test "isLibcFunction - detects known libc functions" {
    try std.testing.expect(isLibcFunction("memcpy"));
    try std.testing.expect(isLibcFunction("strlen"));
    try std.testing.expect(isLibcFunction("strcpy"));
    try std.testing.expect(isLibcFunction("fabs"));
    try std.testing.expect(isLibcFunction("ceil"));
    try std.testing.expect(isLibcFunction("qsort"));
    try std.testing.expect(isLibcFunction("atoi"));
    try std.testing.expect(!isLibcFunction("my_custom_function"));
    try std.testing.expect(!isLibcFunction("pthread_create"));
}

test "Go runtime internal symbols detected by isLikelyRuntimeInternal" {
    const go_runtime_test_cases = [_][]const u8{
        "runtime.gcStart",     "runtime.mallocgc",   "runtime.scanobject",
        "runtime.schedule",    "runtime.park0",      "runtime.wakep",
        "runtime.chansend1",   "runtime.selectgo",   "runtime.assertI2I",
        "runtime.convI2E",     "runtime.mapaccess1", "runtime.mapassign",
        "runtime.newproc",     "runtime.goexit",     "runtime.systemstack",
        "runtime.deferreturn", "reflect.MakeFunc",
    };

    for (go_runtime_test_cases) |sym| {
        try std.testing.expect(isLikelyRuntimeInternal(sym));
    }
}
