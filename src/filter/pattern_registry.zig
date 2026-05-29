//! Pattern Registry — Single Source of Truth for Function Name Matching
//!
//! Consolidates ~565 patterns from 4 source files into comptime arrays
//! with zero runtime overhead. Original source files preserved (callers exist).
//!
//! Query functions: isStdlibInternal, isRuntimeShim, classifyCSafety,
//!   classifyZone, isLLVMIntrinsic, isCompilerInternal, isIntentionalPattern,
//!   isDangerousCFunction, isLanguageInternal, isCryptoPrimitive, isTableDriven,
//!   isStdlibPath, isFFIPattern, layer1NoiseFilter.
//!
//! Matching: prefix (startsWith), contains (indexOf), exact (eql).

const std = @import("std");

/// Three-tier C function safety classification for @cImport bindings.
pub const CSafetyLevel = enum {
    dangerous, // Always warn — system, strcpy, gets, etc.
    conditional, // Warn if suspicious args — malloc, memcpy, etc.
    safe, // No warning — strlen, strcmp, etc.
};

/// Zone classification result for function name matching.
pub const ZoneClassification = enum {
    safe, // Language guarantees — skip analysis.
    escape, // Explicit safety escape — focus analysis.
    unknown, // No pattern matched — caller decides.
};

pub const PatternRegistry = struct {
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
        "$",
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
        "__builtin_",        "__memcpy_chk",    "__memmove_chk",
        "__memset_chk",      "__strcpy_chk",    "__strcat_chk",
        "__strncpy_chk",     "__sprintf_chk",   "__snprintf_chk",
        "__printf_chk",      "__fprintf_chk",   "__vprintf_chk",
        "__vfprintf_chk",    "__stack_chk_fail", "__stack_chk_guard",
        "__cxa_",            "__gxx_personality", "__llvm_",
        "__sanitizer_",      "__ubsan_",        "__asan_",
        "__msan_",           "__tsan_",
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
        "_RNv",                        "$LT$core",
        "$LT$alloc",                   "_$LT$",
        "_GT$",                        "real_drop_in_place",
        "size_hint",                   "reserve_total",
        "Error3new",                   "Error8downcast",
        "error5error",                 "error6vtable",
        "object_reallocate_boxed",     "object_drop",
        "$u7b$u7b$closure$u7d$u7d$",   "anyhow5error",
    };

    pub const zig_noise_patterns = [_][]const u8{
        "std.",                  "std.debug",      "std.mem",
        "std.fmt",              "std.heap",       "std.fs",
        "std.io",               "std.os",         "std.posix",
        "std.ascii",            "std.base64",     "std.hash",
        "std.array_list",       "std.bit_set",    "std.builtin",
        "std.crypto",           "std.compress",   "std.random",
        "mem.Allocator",        "GeneralPurposeAllocator",
        "ArenaAllocator",       "page_allocator", "c_allocator",
        "raw_c_allocator",      "FixedBufferAllocator",
        "zig_assert_fail",      "zig_panic",      "zig_oq",
        "zig_write",            "zig_generic_resolve",
        "debug.Dwarf",          "debug.Info",     "debug.Segment",
        "debug.LineInfo",       "posix.",         "posix_getenv",
        "posix_environ",        "fs.File",        "fs.Dir",
        "fs.Path",              "fs.cwd",         "fs.openFile",
        "fs.access",            "fs.realpath",    "fs.makeAbsolute",
        "fs.canonicalize",      "start.zig",      "panic.zig",
        "builtin.zig",          "__zig_",         "__anon_",
        "(anonymous namespace)", "@typeInfo",      "is_named_enum_value",
        "__zig_switch_target",  "__zig_error_name", "__zig_resolve_enum_name",
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
    // Query Functions
    /// Check if a function is a stdlib/internal function (Pattern G).
    /// Covers Zig/Rust/C++ stdlib prefixes and compiler builtins.
    pub fn isStdlibInternal(func_name: []const u8) bool {
        if (func_name.len == 0) return false;
        for (zig_stdlib_prefixes) |p| {
            if (startsWith(func_name, p)) return true;
        }
        for (rust_stdlib_prefixes) |p| {
            if (startsWith(func_name, p)) return true;
        }
        for (cpp_stdlib_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (compiler_builtins) |p| {
            if (startsWith(func_name, p)) return true;
        }
        return false;
    }

    /// Check if a function is a platform runtime / compiler shim (Pattern H).
    /// Platform-agnostic — callers gate Windows patterns via isWindowsMsvcRuntime.
    pub fn isRuntimeShim(func_name: []const u8) bool {
        return isGenericRuntimeShim(func_name) or isWindowsMsvcRuntime(func_name);
    }

    /// Cross-platform runtime shim patterns (no Windows-specific checks).
    pub fn isGenericRuntimeShim(func_name: []const u8) bool {
        for (cpp_alloc_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (cpp_abi_prefixes) |p| {
            if (startsWith(func_name, p)) return true;
        }
        for (objc_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (swift_patterns) |p| {
            if (startsWith(func_name, p)) return true;
        }
        for (go_runtime_patterns) |p| {
            if (startsWith(func_name, p)) return true;
        }
        for (rust_runtime_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (zig_runtime_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        if (startsWith(func_name, "llvm.")) return true;
        for (sanitizer_prefixes) |p| {
            if (startsWith(func_name, p)) return true;
        }
        if (std.mem.indexOf(u8, func_name, "__stack_chk") != null) return true;
        for (dl_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        return false;
    }

    /// Windows MSVC CRT / runtime patterns. Only consult on Windows targets.
    pub fn isWindowsMsvcRuntime(func_name: []const u8) bool {
        for (seh_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (crt_init_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (msvc_security) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (tls_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        if (func_name.len > 0 and func_name[0] == '?') {
            if (std.mem.indexOf(u8, func_name, "?_type_info@") != null) return true;
            if (std.mem.indexOf(u8, func_name, "??_R") != null) return true;
            if (std.mem.indexOf(u8, func_name, "??_7") != null) return true;
        }
        return false;
    }

    /// Classify C function safety level for @cImport bindings.
    /// Returns null for unknown functions (conservative: analyze).
    pub fn classifyCSafety(func_name: []const u8) ?CSafetyLevel {
        for (c_import_blacklist) |p| {
            if (std.mem.eql(u8, func_name, p)) return .dangerous;
        }
        for (c_import_conditional) |p| {
            if (std.mem.eql(u8, func_name, p)) return .conditional;
        }
        for (c_import_safe) |p| {
            if (std.mem.eql(u8, func_name, p)) return .safe;
        }
        return null;
    }

    /// Classify function zone for a specific language.
    /// Checks safe patterns first (skip), then escape triggers (focus).
    pub fn classifyZone(func_name: []const u8, comptime lang: enum { rust, zig, go, cpp, c }) ZoneClassification {
        return switch (lang) {
            .rust => {
                for (rust_safe_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .safe;
                }
                for (rust_escape_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .escape;
                }
                return .unknown;
            },
            .zig => {
                for (zig_safe_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .safe;
                }
                for (zig_escape_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .escape;
                }
                return .unknown;
            },
            .go => {
                for (go_safe_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .safe;
                }
                for (go_escape_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .escape;
                }
                return .unknown;
            },
            .cpp => {
                for (cpp_safe_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .safe;
                }
                for (cpp_escape_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .escape;
                }
                return .unknown;
            },
            .c => {
                for (c_escape_patterns) |p| {
                    if (std.mem.indexOf(u8, func_name, p) != null) return .escape;
                }
                return .unknown;
            },
        };
    }

    /// Check if a function is an LLVM intrinsic or Rust synthetic noise.
    /// Any "llvm.*" is noise. Rust synthetic (channels, smart ptrs, iterators) too.
    pub fn isLLVMIntrinsic(func_name: []const u8) bool {
        if (startsWith(func_name, "llvm.")) {
            for (llvm_intrinsic_prefixes) |prefix| {
                if (startsWith(func_name, prefix)) return true;
            }
            return true; // Catch-all for unrecognized llvm.* intrinsics
        }
        for (rust_synthetic_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        return false;
    }

    /// Check if a mangled name is compiler-internal (precise whitelist).
    /// Patterns: _ZNSt (C++ std), _ZN4core (Rust), $ss/$sS (Swift), etc.
    pub fn isCompilerInternal(func_name: []const u8) bool {
        for (compiler_internal_patterns) |pattern| {
            if (startsWith(func_name, pattern)) return true;
        }
        return false;
    }

    /// Check if function name indicates intentional safe/test code.
    /// Matches safe_*, test_*, demo_*, bench_*, mock_* and substrings
    /// like "intentional", "known_safe".
    pub fn isIntentionalPattern(func_name: []const u8) bool {
        for (intentional_prefixes) |prefix| {
            if (startsWith(func_name, prefix)) return true;
        }
        for (intentional_substrings) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        return false;
    }

    /// Check if a C function is in the absolute blacklist.
    /// CWE-120, CWE-134, CWE-787 — always dangerous.
    pub fn isDangerousCFunction(func_name: []const u8) bool {
        for (dangerous_c_functions) |p| {
            if (std.mem.eql(u8, func_name, p)) return true;
        }
        return false;
    }

    /// Check if a function is a Zig/Go internal runtime function (safe, skip FFI).
    pub fn isLanguageInternal(func_name: []const u8) bool {
        for (zig_internal_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        if (std.mem.indexOf(u8, func_name, "__zig") != null) return true;
        if (std.mem.indexOf(u8, func_name, "(anonymous namespace)") != null) return true;
        if (std.mem.indexOf(u8, func_name, "generic(") != null or
            std.mem.indexOf(u8, func_name, "__anon_") != null) return true;
        for (go_internal_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (go_runtime_extra) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        return false;
    }

    /// Check if a function name indicates a cryptographic primitive.
    /// Covers ciphers, hashes, public key, MAC/KDF.
    pub fn isCryptoPrimitive(func_name: []const u8) bool {
        for (cipher_names) |n| {
            if (std.mem.indexOf(u8, func_name, n) != null) return true;
        }
        for (hash_names) |n| {
            if (std.mem.indexOf(u8, func_name, n) != null) return true;
        }
        for (pk_names) |n| {
            if (std.mem.indexOf(u8, func_name, n) != null) return true;
        }
        for (mac_names) |n| {
            if (std.mem.indexOf(u8, func_name, n) != null) return true;
        }
        return false;
    }

    /// Check if a function name suggests table-driven implementation.
    /// Table-driven crypto loads function pointer tables from .text — alloca FPs.
    pub fn isTableDriven(func_name: []const u8) bool {
        for (table_signals) |signal| {
            if (std.mem.indexOf(u8, func_name, signal) != null) return true;
        }
        return false;
    }

    /// Check if a debug file path indicates stdlib/compiler origin.
    /// Matches Rust, Zig, C++ path prefixes (case-insensitive for Windows).
    pub fn isStdlibPath(file_path: []const u8) bool {
        for (rust_stdlib_paths) |prefix| {
            if (indexOfPath(file_path, prefix)) return true;
        }
        for (zig_stdlib_paths) |prefix| {
            if (indexOfPath(file_path, prefix)) return true;
        }
        for (cpp_stdlib_paths) |prefix| {
            if (indexOfPath(file_path, prefix)) return true;
        }
        return false;
    }

    /// Check if a function name matches any FFI language pattern (Rust/Zig/Go).
    pub fn isFFIPattern(func_name: []const u8) bool {
        for (rust_ffi_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (zig_ffi_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        for (go_ffi_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return true;
        }
        return false;
    }

    /// Layer 1 noise filter: check if function name matches stdlib/compiler.
    /// Returns reason string if should be filtered, null if should analyze.
    pub fn layer1NoiseFilter(func_name: []const u8) ?[]const u8 {
        if (isLLVMIntrinsic(func_name)) return "LLVM intrinsic (compiler-generated)";
        for (rust_noise_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return "Rust stdlib/compiler pattern";
        }
        for (zig_noise_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return "Zig stdlib/internal pattern";
        }
        for (cpp_noise_patterns) |p| {
            if (std.mem.indexOf(u8, func_name, p) != null) return "C++ STL/compiler pattern";
        }
        return null;
    }
    // Internal Helpers
    fn startsWith(haystack: []const u8, needle: []const u8) bool {
        if (haystack.len < needle.len) return false;
        return std.mem.eql(u8, haystack[0..needle.len], needle);
    }

    fn indexOfPath(haystack: []const u8, needle: []const u8) bool {
        if (haystack.len == 0 or needle.len == 0) return false;
        if (needle.len > haystack.len) return false;
        if (std.mem.indexOf(u8, haystack, needle) != null) return true;
        // Case-insensitive fallback for Windows paths
        var i: usize = 0;
        const max_start = haystack.len - needle.len;
        while (i <= max_start) : (i += 1) {
            var match = true;
            for (needle, 0..) |needle_char, j| {
                if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(needle_char)) {
                    match = false;
                    break;
                }
            }
            if (match) return true;
        }
        return false;
    }
};
const P = PatternRegistry;

test "isStdlibInternal: Zig/Rust/C++ stdlib and builtins" {
    // Zig
    try std.testing.expect(P.isStdlibInternal("debug.Dwarf"));
    try std.testing.expect(P.isStdlibInternal("hash_map.getOrPut"));
    try std.testing.expect(P.isStdlibInternal("std.mem.copy"));
    try std.testing.expect(P.isStdlibInternal("Io.Writer.writeAll"));
    try std.testing.expect(!P.isStdlibInternal("my_function"));
    // Rust
    try std.testing.expect(P.isStdlibInternal("core::fmt::write"));
    try std.testing.expect(P.isStdlibInternal("alloc::vec::Vec::new"));
    try std.testing.expect(!P.isStdlibInternal("mylib::core::func"));
    // Compiler builtins
    try std.testing.expect(P.isStdlibInternal("__builtin_memcpy"));
    try std.testing.expect(P.isStdlibInternal("__cxa_throw"));
    try std.testing.expect(P.isStdlibInternal("__asan_report_load1"));
    try std.testing.expect(!P.isStdlibInternal("__cinit__"));
    try std.testing.expect(!P.isStdlibInternal("__custom_helper"));
}

test "isRuntimeShim: C++/ObjC/Swift/Go/Rust/Zig/MSVC runtimes" {
    // C++ allocators
    try std.testing.expect(P.isRuntimeShim("_Znwm"));
    try std.testing.expect(P.isRuntimeShim("operator new"));
    // ObjC/Swift
    try std.testing.expect(P.isRuntimeShim("objc_msgSend"));
    try std.testing.expect(P.isRuntimeShim("swift_retain"));
    // Go/Rust/Zig
    try std.testing.expect(P.isRuntimeShim("runtime.gc"));
    try std.testing.expect(P.isRuntimeShim("__rust_dealloc"));
    try std.testing.expect(P.isRuntimeShim("__zig_probe_stack"));
    // LLVM intrinsics
    try std.testing.expect(P.isRuntimeShim("llvm.lifetime.start.p0i8"));
    // Windows MSVC
    try std.testing.expect(P.isRuntimeShim("__except_handler4"));
    try std.testing.expect(P.isRuntimeShim("_initterm"));
    try std.testing.expect(P.isRuntimeShim("__security_check_cookie"));
}

test "isGenericRuntimeShim: excludes Windows patterns" {
    try std.testing.expect(P.isGenericRuntimeShim("_Znwm"));
    try std.testing.expect(P.isGenericRuntimeShim("objc_msgSend"));
    try std.testing.expect(!P.isGenericRuntimeShim("__except_handler4"));
    try std.testing.expect(!P.isGenericRuntimeShim("_initterm"));
    try std.testing.expect(!P.isGenericRuntimeShim("__security_check_cookie"));
}
test "isWindowsMsvcRuntime: SEH/CRT/security/RTTI" {
    try std.testing.expect(P.isWindowsMsvcRuntime("__except_handler4"));
    try std.testing.expect(P.isWindowsMsvcRuntime("___CxxFrameHandler3"));
    try std.testing.expect(P.isWindowsMsvcRuntime("_initterm"));
    try std.testing.expect(P.isWindowsMsvcRuntime("__security_check_cookie"));
    try std.testing.expect(P.isWindowsMsvcRuntime("TlsCallback_0"));
    try std.testing.expect(P.isWindowsMsvcRuntime("?_type_info@Foo@@"));
    try std.testing.expect(!P.isWindowsMsvcRuntime("my_function"));
}
test "classifyCSafety: three-tier classification" {
    // Layer 1: Dangerous
    try std.testing.expectEqual(CSafetyLevel.dangerous, P.classifyCSafety("system").?);
    try std.testing.expectEqual(CSafetyLevel.dangerous, P.classifyCSafety("strcpy").?);
    try std.testing.expectEqual(CSafetyLevel.dangerous, P.classifyCSafety("printf").?);
    // Layer 2: Conditional
    try std.testing.expectEqual(CSafetyLevel.conditional, P.classifyCSafety("malloc").?);
    try std.testing.expectEqual(CSafetyLevel.conditional, P.classifyCSafety("memcpy").?);
    // Layer 3: Safe
    try std.testing.expectEqual(CSafetyLevel.safe, P.classifyCSafety("strlen").?);
    try std.testing.expectEqual(CSafetyLevel.safe, P.classifyCSafety("sqrt").?);
    // Unknown
    try std.testing.expectEqual(@as(?CSafetyLevel, null), P.classifyCSafety("sqlite3_open"));
}

test "classifyZone: all five languages" {
    // Rust
    try std.testing.expectEqual(ZoneClassification.safe, P.classifyZone("std::vec::Vec", .rust));
    try std.testing.expectEqual(ZoneClassification.safe, P.classifyZone("__rust_alloc", .rust));
    try std.testing.expectEqual(ZoneClassification.escape, P.classifyZone("std::mem::transmute", .rust));
    try std.testing.expectEqual(ZoneClassification.unknown, P.classifyZone("my_function", .rust));
    // Zig
    try std.testing.expectEqual(ZoneClassification.safe, P.classifyZone("std.ArrayList", .zig));
    try std.testing.expectEqual(ZoneClassification.escape, P.classifyZone("@ptrCast", .zig));
    // Go
    try std.testing.expectEqual(ZoneClassification.safe, P.classifyZone("runtime.gopark", .go));
    try std.testing.expectEqual(ZoneClassification.escape, P.classifyZone("unsafe.Pointer", .go));
    // C++
    try std.testing.expectEqual(ZoneClassification.safe, P.classifyZone("std::vector<int>", .cpp));
    try std.testing.expectEqual(ZoneClassification.escape, P.classifyZone("reinterpret_cast", .cpp));
    // C
    try std.testing.expectEqual(ZoneClassification.escape, P.classifyZone("dlopen", .c));
    try std.testing.expectEqual(ZoneClassification.unknown, P.classifyZone("strlen", .c));
}

test "isLLVMIntrinsic: intrinsics, Rust synthetic, and real FFI" {
    // LLVM intrinsics
    try std.testing.expect(P.isLLVMIntrinsic("llvm.threadlocal.address"));
    try std.testing.expect(P.isLLVMIntrinsic("llvm.lifetime.start.p0i8"));
    try std.testing.expect(P.isLLVMIntrinsic("llvm.dbg.declare"));
    try std.testing.expect(P.isLLVMIntrinsic("llvm.unknown.intrinsic"));
    // Rust synthetic
    try std.testing.expect(P.isLLVMIntrinsic("sync_channel::channel"));
    try std.testing.expect(P.isLLVMIntrinsic("Waker::wake"));
    try std.testing.expect(P.isLLVMIntrinsic("Arc::<T>::clone"));
    try std.testing.expect(!P.isLLVMIntrinsic("__rust_alloc"));
    try std.testing.expect(!P.isLLVMIntrinsic("__rust_dealloc"));
    // Real FFI NOT filtered
    try std.testing.expect(!P.isLLVMIntrinsic("dlopen"));
    try std.testing.expect(!P.isLLVMIntrinsic("malloc"));
    try std.testing.expect(!P.isLLVMIntrinsic("my_function"));
}

test "isCompilerInternal: C++ std, Rust core/alloc, Swift, and user functions" {
    try std.testing.expect(P.isCompilerInternal("_ZNSt6vectorIiEE"));
    try std.testing.expect(P.isCompilerInternal("_ZN4core9fmt::Formatter"));
    try std.testing.expect(P.isCompilerInternal("_ZN5alloc6sync::ReentrantMutexE"));
    try std.testing.expect(P.isCompilerInternal("__cxx_global_var_init"));
    try std.testing.expect(P.isCompilerInternal("$sS4base8toString"));
    // User functions NOT matched
    try std.testing.expect(!P.isCompilerInternal("_ZN9my_app4mainE"));
    try std.testing.expect(!P.isCompilerInternal("user_function"));
}

test "isIntentionalPattern: prefixes and substrings" {
    try std.testing.expect(P.isIntentionalPattern("test_malloc"));
    try std.testing.expect(P.isIntentionalPattern("safe_example"));
    try std.testing.expect(P.isIntentionalPattern("demo_ffi"));
    try std.testing.expect(P.isIntentionalPattern("bench_alloc"));
    try std.testing.expect(P.isIntentionalPattern("test_intentional_usage"));
    try std.testing.expect(P.isIntentionalPattern("known_safe_pattern"));
    try std.testing.expect(!P.isIntentionalPattern("my_function"));
}

test "isDangerousCFunction: buffer overflow, command injection, format string" {
    try std.testing.expect(P.isDangerousCFunction("strcpy"));
    try std.testing.expect(P.isDangerousCFunction("system"));
    try std.testing.expect(P.isDangerousCFunction("gets"));
    try std.testing.expect(P.isDangerousCFunction("printf"));
    try std.testing.expect(!P.isDangerousCFunction("memcpy"));
    try std.testing.expect(!P.isDangerousCFunction("strlen"));
}
test "isLanguageInternal: Zig and Go internals" {
    // Zig
    try std.testing.expect(P.isLanguageInternal("zig_assert_fail"));
    try std.testing.expect(P.isLanguageInternal("__zig_bug"));
    try std.testing.expect(P.isLanguageInternal("some_function(generic(T))"));
    try std.testing.expect(!P.isLanguageInternal("user_function"));
    // Go
    try std.testing.expect(P.isLanguageInternal("runtime.gopark"));
    try std.testing.expect(P.isLanguageInternal("runtime.morestack"));
    try std.testing.expect(P.isLanguageInternal("typedmemmove"));
    try std.testing.expect(!P.isLanguageInternal("my_go_func"));
}
test "isCryptoPrimitive: cipher, hash, PK, MAC" {
    try std.testing.expect(P.isCryptoPrimitive("aes_encrypt_block"));
    try std.testing.expect(P.isCryptoPrimitive("sha256_update"));
    try std.testing.expect(P.isCryptoPrimitive("ecdsa_sign"));
    try std.testing.expect(P.isCryptoPrimitive("hmac_sha256"));
    try std.testing.expect(!P.isCryptoPrimitive("my_function"));
}

test "isTableDriven: table/lookup/vtable/dispatch" {
    try std.testing.expect(P.isTableDriven("aes_lookup_table"));
    try std.testing.expect(P.isTableDriven("crypto_dispatch"));
    try std.testing.expect(P.isTableDriven("hw_accelerated"));
    try std.testing.expect(!P.isTableDriven("my_function"));
}
test "isStdlibPath: Rust/Zig/C++ paths including Windows" {
    try std.testing.expect(P.isStdlibPath("/rustc/abc/library/core/src/fmt/mod.rs"));
    try std.testing.expect(P.isStdlibPath("/home/user/zig/lib/std/mem.zig"));
    try std.testing.expect(P.isStdlibPath("/usr/include/c++/13/vector"));
    try std.testing.expect(P.isStdlibPath("C:\\Users\\zig\\lib\\std\\mem.zig"));
    try std.testing.expect(!P.isStdlibPath("/home/user/myproject/src/main.zig"));
}

test "isFFIPattern: Rust/Zig/Go FFI indicators" {
    try std.testing.expect(P.isFFIPattern("extern"));
    try std.testing.expect(P.isFFIPattern("C.free"));
    try std.testing.expect(P.isFFIPattern("_cgo_allocate"));
    try std.testing.expect(P.isFFIPattern("__zig"));
    try std.testing.expect(!P.isFFIPattern("my_function"));
}
test "layer1NoiseFilter: LLVM/Rust/Zig/C++ noise" {
    try std.testing.expect(P.layer1NoiseFilter("llvm.threadlocal.address") != null);
    try std.testing.expect(P.layer1NoiseFilter("core::fmt::write") != null);
    try std.testing.expect(P.layer1NoiseFilter("std.mem.copy") != null);
    try std.testing.expect(P.layer1NoiseFilter("std::vector::push_back") != null);
    try std.testing.expect(P.layer1NoiseFilter("dlopen") == null);
    try std.testing.expect(P.layer1NoiseFilter("my_function") == null);
}
test "pattern count: registry has ~560 consolidated patterns" {
    const total =
        P.llvm_intrinsic_prefixes.len + P.rust_synthetic_patterns.len +
        P.rust_safe_patterns.len + P.rust_escape_patterns.len +
        P.zig_safe_patterns.len + P.zig_escape_patterns.len +
        P.go_safe_patterns.len + P.go_escape_patterns.len +
        P.cpp_safe_patterns.len + P.cpp_escape_patterns.len +
        P.c_escape_patterns.len +
        P.c_import_blacklist.len + P.c_import_conditional.len + P.c_import_safe.len +
        P.dangerous_c_functions.len +
        P.zig_internal_patterns.len + P.go_internal_patterns.len + P.go_runtime_extra.len +
        P.rust_ffi_patterns.len + P.zig_ffi_patterns.len + P.go_ffi_patterns.len +
        P.intentional_prefixes.len + P.intentional_substrings.len +
        P.zig_stdlib_prefixes.len + P.rust_stdlib_prefixes.len + P.cpp_stdlib_patterns.len +
        P.compiler_builtins.len +
        P.cpp_alloc_patterns.len + P.cpp_abi_prefixes.len +
        P.objc_patterns.len + P.swift_patterns.len +
        P.go_runtime_patterns.len + P.rust_runtime_patterns.len + P.zig_runtime_patterns.len +
        P.sanitizer_prefixes.len + P.dl_patterns.len +
        P.seh_patterns.len + P.crt_init_patterns.len + P.msvc_security.len + P.tls_patterns.len +
        P.cipher_names.len + P.hash_names.len + P.pk_names.len + P.mac_names.len +
        P.table_signals.len + P.compiler_internal_patterns.len +
        P.rust_stdlib_paths.len + P.zig_stdlib_paths.len + P.cpp_stdlib_paths.len +
        P.rust_noise_patterns.len + P.zig_noise_patterns.len + P.cpp_noise_patterns.len;
    try std.testing.expect(total > 500);
    try std.testing.expect(total < 650);
}
