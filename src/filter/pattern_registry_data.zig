//! Pattern Registry Data — Comptime Pattern Arrays
//!
//! Contains all pattern data arrays used by PatternRegistry.
//! Separated to keep pattern_registry.zig under 1000 lines.
//!
//! These arrays are comptime constants with zero runtime overhead.
//! Organized by domain: LLVM intrinsics, language-specific patterns,
//! C safety classifications, crypto primitives, and noise filters.

const std = @import("std");

/// Pattern data namespace containing all comptime pattern arrays.
pub const PatternData = struct {
    // LLVM Intrinsics & Rust Synthetic (noise_reduction.zig) — prefix/contains match
    pub const llvm_intrinsic_prefixes = [_][]const u8{
        "llvm.threadlocal.address",  "llvm.threadlocal.restore",
        "llvm.lifetime.start",       "llvm.lifetime.end",
        "llvm.dbg.declare",          "llvm.dbg.value",
        "llvm.dbg.label",            "llvm.assume",
        "llvm.expect",               "llvm.smax",
        "llvm.smin",                 "llvm.umax",
        "llvm.umin",                 "llvm.coro.id",
        "llvm.coro.alloc",           "llvm.coro.begin",
        "llvm.coro.size",            "llvm.coro.end",
        "llvm.coro.free",            "llvm.coro.save",
        "llvm.coro.suspend",         "llvm.coro.param",
        "llvm.coro.async.ctx",       "llvm.coro.async.size",
        "llvm.coro.async.addr",      "llvm.coro.async.resume",
        "llvm.coro.async.copy",      "llvm.gc.root",
        "llvm.gcwrite",              "llvm.gcread",
        "llvm.gcresult",             "llvm.eh.typeid.for",
        "llvm.eh.begincatch",        "llvm.eh.endcatch",
        "llvm.eh.selector",          "llvm.eh.exceptionpointer",
        "llvm.eh.unwindinit",        "llvm.eh.unwindsync",
        "llvm.eh.returnaddr",        "llvm.eh.dwarf.cfa",
        "llvm.type.checked.load",    "llvm.type.test",
        "llvm.ptr.mask",             "llvm.vector.reduce.",
        "llvm.experimental.vector.", "llvm.instrumentation.",
        "llvm.localescape",          "llvm.localrecover",
        "llvm.ctlz",                 "llvm.cttz",
        "llvm.ctpop",                "llvm.bitreverse",
    };

    /// Rust safe primitives — channels, smart ptrs, iterators (contains match).
    pub const rust_synthetic_patterns = [_][]const u8{
        "sync_channel::", "mpsc::channel",
        "Waker::",        "RawWaker",
        "Arc::<",         "Rc::<",
        "Weak::<",        "RawVec::",
        "::next",         "::next_back",
        "::iter",         "::into_iter",
        "::from_iter",
    };

    // Zone Safe/Escape Patterns (zone_types.zig) — contains match
    pub const rust_safe_patterns = [_][]const u8{
        "std::vec::Vec",       "std::string::String",
        "std::collections::",  "std::sync::Arc",
        "std::sync::Mutex",    "std::sync::RwLock",
        "std::sync::mpsc",     "std::sync::mpmc",
        "std::cell::RefCell",  "std::cell::Cell",
        "std::rc::Rc",         "std::boxed::Box",
        "std::option::Option", "std::result::Result",
        "drop_in_place",       "clone",
        "into_iter",           "from_iter",
        "sync_channel::",      "Waker::",
        "RawVec::",            "__rust_alloc",
        "__rust_dealloc",
    };

    pub const rust_escape_patterns = [_][]const u8{
        "unsafe",              "extern \"C\"",
        "extern \"system\"",   "libc::",
        "nix::",               "$u20$unsafe",
        "_ZN.*4ffi",           "_ZN.*7extern",
        "*mut ",               "*const ",
        "as_ptr",              "as_mut_ptr",
        "from_raw_parts",      "from_raw_parts_mut",
        "std::mem::transmute", "core::mem::transmute",
        "transmute_copy",      "MaybeUninit",
        "assume_init",         "Pin<",
        "get_unchecked",       "get_unchecked_mut",
        "asm!",                "llvm_asm!",
        "_ffi",                "_extern",
        "_bindgen",            "_cinterop",
        "_marshal",            "_syscall",
        "_invoke",             "_callback",
        "_native",             "_interop",
        // Rust v0 mangling escape markers (more specific than bare "$")
        "$LT$",                "$GT$",
        "$u7b$",               "$u7d$",
        "$u20$",               "$C$",
        "$RF$",                "$BP$",
    };

    pub const zig_safe_patterns = [_][]const u8{
        "std.ArrayList",           "std.StringArrayHashMap",
        "std.AutoHashMap",         "std.mem.split",
        "std.mem.replace",         "std.process",
        ".allocator",              "@as(*std.mem.Allocator",
        "std.heap.page_allocator", "std.heap.GeneralPurposeAllocator",
        "defer",                   "errdefer",
    };

    pub const zig_escape_patterns = [_][]const u8{
        "@ptrCast",      "@alignCast",
        "@intToPtr",     "@ptrToInt",
        "@cImport",      "@cInclude",
        "@cDefine",      "volatile ",
        "packed struct", "@bitCast",
    };

    pub const go_safe_patterns = [_][]const u8{
        "runtime.",    "make(", "new(",
        "append(",     "copy(", "delete(",
        "chan ",       "map[",  "func(",
        "interface{}",
    };

    pub const go_escape_patterns = [_][]const u8{
        "package C",      "C.",            "import \"C\"",
        "unsafe.Pointer", "unsafe.Sizeof", "unsafe.Offsetof",
        "unsafe.Alignof", "uintptr(",      "reflect.",
    };

    pub const cpp_safe_patterns = [_][]const u8{
        "std::vector",        "std::string",
        "std::unique_ptr",    "std::shared_ptr",
        "std::weak_ptr",      "std::map",
        "std::unordered_map", "std::set",
        "make_unique",        "make_shared",
        "get()",              "reset()",
        "release()",
    };

    pub const cpp_escape_patterns = [_][]const u8{
        "reinterpret_cast",  "const_cast",
        "static_cast<void*", "malloc(",
        "free(",             "new ",
        "delete ",           "realloc(",
        "pthread_create",    "std::thread",
        "CreateThread",      "fork(",
        "execvp(",           "execve(",
        "getaddrinfo",       "gethostbyname",
        "setsockopt",        "getsockopt",
    };

    pub const c_escape_patterns = [_][]const u8{
        "dlopen",        "dlsym",   "dlclose",
        "mmap",          "munmap",  "mprotect",
        "Py_",           "JNI_",    "pthread_create",
        "pthread_join",  "signal(", "sigaction(",
        "fork(",         "exec",    "getaddrinfo",
        "gethostbyname",
    };

    // C Safety Three-Tier (ffi_zone_check.zig) — exact match
    /// Layer 1: Never safe — always warn.
    pub const c_import_blacklist = [_][]const u8{
        "system",      "popen",    "execve", "execl",
        "execlp",      "execle",   "execvp", "execv",
        "posix_spawn", "strcpy",   "strcat", "sprintf",
        "gets",        "scanf",    "sscanf", "fscanf",
        "strtok",      "asctime",  "ctime",  "printf",
        "fprintf",     "vsprintf",
    };

    /// Layer 2: Safe only when used correctly.
    pub const c_import_conditional = [_][]const u8{
        "malloc",  "calloc",   "realloc",   "free",
        "memcpy",  "memmove",  "strncpy",   "strncat",
        "fgets",   "fread",    "fwrite",    "fopen",
        "freopen", "snprintf", "vsnprintf",
    };

    /// Layer 3: Presumed safe.
    pub const c_import_safe = [_][]const u8{
        "strlen",   "strcmp",    "strncmp", "memcmp",
        "strchr",   "strrchr",   "strstr",  "memset",
        "atoi",     "atol",      "strtoul", "strtol",
        "strtod",   "exit",      "abort",   "atexit",
        "errno",    "strerror",  "perror",  "getenv",
        "sin",      "cos",       "tan",     "asin",
        "acos",     "atan",      "atan2",   "sinh",
        "cosh",     "tanh",      "log",     "log10",
        "exp",      "pow",       "sqrt",    "fabs",
        "floor",    "ceil",      "round",   "trunc",
        "fmod",     "remainder", "time",    "clock",
        "difftime", "mktime",    "puts",    "putchar",
        "getc",     "ungetc",    "fgetc",   "fputc",
        "fputs",    "feof",      "ferror",  "clearerr",
        "rewind",   "ftell",     "fflush",  "setbuf",
        "setvbuf",  "getpid",    "getppid",
    };

    /// Absolute blacklist — CWE-120/134/787 (exact match).
    pub const dangerous_c_functions = [_][]const u8{
        "strcpy", "strcat",   "sprintf",   "gets",
        "scanf",  "vsprintf", "system",    "popen",
        "execl",  "execle",   "execlp",    "execv",
        "execve", "execvp",   "strtok",    "asctime",
        "ctime",  "gmtime",   "localtime", "bcopy",
        "bzero",  "fprintf",  "printf",    "sscanf",
        "fscanf",
    };

    // Zig/Go Internal (ffi_zone_check.zig) — contains match
    pub const zig_internal_patterns = [_][]const u8{
        "zig_assert_fail",        "zig_panic",
        "zig_oq",                 "zig_write",
        "zig_alloc",              "zig_free",
        "zig_error",              "zig_generic_resolve",
        "zig_monitor_init",       "zig_monitor_lock",
        "zig_monitor_unlock",     "zig_promote_error",
        "zig_demote_error",       "zig_convert_to_error_union",
        "zig_stack_trace",        "zig_debug_safe_truncate",
        "zig_debug_safety_crash", "__zig_bug",
        "__zig_panic_handler",
    };

    /// Broad Zig internal markers (contains match).
    /// These are more general than specific function names above.
    pub const zig_broad_internal_patterns = [_][]const u8{
        "__zig",
        "(anonymous namespace)",
        "generic(",
        "__anon_",
    };

    pub const go_internal_patterns = [_][]const u8{
        "runtime.gopark",     "runtime.goexit",
        "runtime.morestack",  "runtime.mallocgc",
        "runtime.gcStart",    "runtime.gcStop",
        "runtime.makeslice",  "runtime.convT2E",
        "runtime.convE2T",    "runtime.assertE2T",
        "runtime.assertE2T2", "runtime.assertI2T",
        "runtime.assertI2T2", "runtime.panicwrap",
    };

    pub const go_runtime_extra = [_][]const u8{
        "runtime.growslice",            "runtime.memmove",
        "runtime.memclrNoHeapPointers", "runtime.memclrHasPointers",
        "runtime.writeBarrier",         "runtime.gcWriteBarrier",
        "typedmemmove",                 "typedmemclr",
    };

    // FFI Language Patterns (ffi_zone_check.zig) — contains match
    pub const rust_ffi_patterns = [_][]const u8{ "extern", "rust_", "_ZN" };
    pub const zig_ffi_patterns = [_][]const u8{ "extern", "c_", "@cImport", "zig_", "__zig" };
    pub const go_ffi_patterns = [_][]const u8{ "C.", "_cgo_", "_Cfunc_", "crosscall2", "runtime.cgocall" };

    // Intentional/Test Patterns (ffi_zone_check.zig)
    pub const intentional_prefixes = [_][]const u8{
        "safe_",   "correct_", "example_",
        "test_",   "_test",    "demo_",
        "sample_", "bench_",   "fixture_",
        "mock_",   "stub_",    "reference_",
    };

    pub const intentional_substrings = [_][]const u8{
        "intentional", "known_safe", "expected", "deliberate",
    };

    // Stdlib Prefixes — Pattern G (issue_suppression.zig)
    pub const zig_stdlib_prefixes = [_][]const u8{
        "debug.",  "hash_map.", "array_hash_map.",
        "std.",    "builtin.",  "mem.",
        "log.",    "Io.",       "fs.",
        "os.",     "process.",  "Thread.",
        "crypto.", "compress.", "http.",
        "json.",   "ascii.",    "base64.",
        "random.", "time.",     "unicode.",
        "net.",    "async.",
    };

    pub const rust_stdlib_prefixes = [_][]const u8{ "core::", "alloc::", "std::" };

    /// C++ stdlib — contains match (not prefix).
    pub const cpp_stdlib_patterns = [_][]const u8{ "std::__", "__gnu_debug" };

    // Compiler Builtins (issue_suppression.zig) — prefix match
    pub const compiler_builtins = [_][]const u8{
        "__builtin_",     "__memcpy_chk",      "__memmove_chk",
        "__memset_chk",   "__strcpy_chk",      "__strcat_chk",
        "__strncpy_chk",  "__sprintf_chk",     "__snprintf_chk",
        "__printf_chk",   "__fprintf_chk",     "__vprintf_chk",
        "__vfprintf_chk", "__stack_chk_fail",  "__stack_chk_guard",
        "__cxa_",         "__gxx_personality", "__llvm_",
        "__sanitizer_",   "__ubsan_",          "__asan_",
        "__msan_",        "__tsan_",
    };

    // Platform Runtime Shims — Pattern H (issue_suppression.zig)
    /// C++ allocators — Itanium ABI mangled (contains match).
    pub const cpp_alloc_patterns = [_][]const u8{
        "_Znw",         "_Zdl",            "_Zna", "_Zda",
        "operator new", "operator delete",
    };

    /// C++ ABI runtime (prefix match).
    pub const cpp_abi_prefixes = [_][]const u8{
        "__cxa_", "__gxx_personality", "_ZTI", "_ZTS", "_ZTV",
    };

    /// Objective-C runtime (contains match).
    pub const objc_patterns = [_][]const u8{
        "_objc_",        "objc_msgSend", "objc_alloc",
        "objc_release",  "_dispatch_",   "dispatch_async",
        "dispatch_sync",
    };

    /// Swift runtime (prefix match).
    pub const swift_patterns = [_][]const u8{
        "swift_retain", "swift_release", "swift_allocObject",
        "$sS",          "$sSo",
    };

    /// Go runtime (prefix match).
    pub const go_runtime_patterns = [_][]const u8{
        "runtime.",       "runtime.alloc",
        "runtime.free",   "internal/task.",
        "runtime._panic",
    };

    /// Rust runtime (contains match).
    pub const rust_runtime_patterns = [_][]const u8{
        "__rust_alloc",  "__rust_dealloc",
        "drop_in_place", "rust_begin_unwind",
        "rust_panic",
    };

    /// Zig runtime (contains match).
    pub const zig_runtime_patterns = [_][]const u8{
        "__zig_probe_stack", "__zig_tag_name_",
        "reachUnreachable",  "unwrapNull",
    };

    /// Sanitizer runtimes (prefix match).
    pub const sanitizer_prefixes = [_][]const u8{
        "__asan_", "__msan_", "__tsan_", "__ubsan_", "__sanitizer_",
    };

    /// Dynamic linker / CRT (contains match).
    pub const dl_patterns = [_][]const u8{
        "_dyld_",                 "_dl_",
        "__security_init_cookie", "__report_gsfailure",
        "_CRT$",                  ".CRT$",
    };

    // Windows MSVC CRT (issue_suppression.zig) — contains match
    pub const seh_patterns = [_][]const u8{
        "__except_handler",   "___CxxFrameHandler",
        "__CxxFrameHandler3", "__C_specific_handler",
        "__GSHandlerCheck",   "__GSHandlerCheck_Common",
    };

    pub const crt_init_patterns = [_][]const u8{
        "_initterm_e",             "_initterm",
        "_crtInit",                "_crtExit",
        "_CRT_INIT",               "_crt_atexit",
        "_atexit_helper",          "_register_onexit_function",
        "_cinit_compute_numpages",
    };

    pub const msvc_security = [_][]const u8{
        "__security_check_cookie",    "__report_gsfailure",
        "__report_rangecheckfailure", "__report_error",
        "__fail_fast_handler",        "__fastfail",
    };

    pub const tls_patterns = [_][]const u8{
        "TlsCallback_", "__dyn_tls_init", "__tlregdtor",
    };

    // Crypto Primitives (issue_suppression.zig) — contains match
    pub const cipher_names = [_][]const u8{
        "aes_", "AES_", "des_", "DES_", "chacha20", "ChaCha20",
    };
    pub const hash_names = [_][]const u8{
        "sha", "SHA", "md5", "MD5", "digest", "hash_", "blake", "Blake",
    };
    pub const pk_names = [_][]const u8{
        "rsa", "RSA", "ecdsa", "ecdh", "curve25519", "ed25519", "p256", "p384",
    };
    pub const mac_names = [_][]const u8{
        "hmac", "HMAC", "hkdf", "HKDF", "pbkdf", "poly1305",
    };

    // Table-Driven & Compiler Internal (issue_suppression.zig)
    pub const table_signals = [_][]const u8{
        "table", "Table", "lookup", "Lookup", "vtable", "dispatch", "hw_",
    };

    /// Mangled name compiler-internal patterns (prefix match).
    pub const compiler_internal_patterns = [_][]const u8{
        "_ZNSt",     "_ZN4core",
        "_ZN5alloc", "_ZN3std",
        "_ZGV",      "_ZZ",
        "__cxx_",    "_GLOBAL__",
        "$ss",       "$sS",
    };

    // Stdlib Paths (noise_reduction.zig) — contains match
    pub const rust_stdlib_paths = [_][]const u8{
        "/rustc/",           "/library/core/",
        "/library/std/",     "/library/alloc/",
        "/registry/src/",    "/cargo/registry/",
        "/.cargo/registry/",
    };

    pub const zig_stdlib_paths = [_][]const u8{
        "zig/lib/std/",  "zig/std/",
        "/lib/zig/std/", ".zig/lib/std/",
    };

    pub const cpp_stdlib_paths = [_][]const u8{
        "/usr/include/c++/", "/usr/include/g++",
        "/libc++/",          "/libcxx/",
        "/include/c++/",     "/clang/",
    };

    // Noise Filter Patterns (noise_reduction.zig) — contains match
    pub const rust_noise_patterns = [_][]const u8{
        "core::",                      "core.",
        "alloc::",                     "alloc.",
        "std::",                       "std.",
        "panic_",                      "begin_panic",
        "panic_fmt",                   "drop_in_place",
        "_ZN4core3ptr13drop_in_place", "<T as core::ops::drop::Drop>::drop",
        "RawVec",                      "Vec<",
        "slice::",                     "fmt::",
        "string::",                    "_ZN4core",
        "_ZN5alloc",                   "_ZN3std",
        "$LT$core",                    "$LT$alloc",
        "_$LT$",                       "_GT$",
        "real_drop_in_place",          "size_hint",
        "reserve_total",               "Error3new",
        "Error8downcast",              "error5error",
        "error6vtable",                "object_reallocate_boxed",
        "object_drop",                 "$u7b$u7b$closure$u7d$u7d$",
        "anyhow5error",
    };

    pub const zig_noise_patterns = [_][]const u8{
        "std.",                  "std.debug",               "std.mem",
        "std.fmt",               "std.heap",                "std.fs",
        "std.io",                "std.os",                  "std.posix",
        "std.ascii",             "std.base64",              "std.hash",
        "std.array_list",        "std.bit_set",             "std.builtin",
        "std.crypto",            "std.compress",            "std.random",
        "mem.Allocator",         "GeneralPurposeAllocator", "ArenaAllocator",
        "page_allocator",        "c_allocator",             "raw_c_allocator",
        "FixedBufferAllocator",  "zig_assert_fail",         "zig_panic",
        "zig_oq",                "zig_write",               "zig_generic_resolve",
        "debug.Dwarf",           "debug.Info",              "debug.Segment",
        "debug.LineInfo",        "posix.",                  "posix_getenv",
        "posix_environ",         "fs.File",                 "fs.Dir",
        "fs.Path",               "fs.cwd",                  "fs.openFile",
        "fs.access",             "fs.realpath",             "fs.makeAbsolute",
        "fs.canonicalize",       "start.zig",               "panic.zig",
        "builtin.zig",           "__zig_",                  "__anon_",
        "(anonymous namespace)", "@typeInfo",               "is_named_enum_value",
        "__zig_switch_target",   "__zig_error_name",        "__zig_resolve_enum_name",
    };

    pub const cpp_noise_patterns = [_][]const u8{
        "std::",             "__gnu_cxx::",
        "__cxa_",            "__clang_call_terminate",
        "__cxa_begin_catch", "__cxa_end_catch",
        "__cxa_throw",       "std::vector",
        "std::string",       "std::map",
        "basic_string",      "_M_insert",
        "_M_emplace_back",   "type_info",
        "__class_type_info",
    };
};
