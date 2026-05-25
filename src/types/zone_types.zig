//! Zone Classification — Type Definitions & Pattern Constants
//!
//! Extracted from zone_classifier.zig to reduce file size.
//! Shared types and pattern constants used by zone_classifier and other passes.

const std = @import("std");

const log = std.log.scoped(.zone_types);

/// Zone classification for code regions.
pub const ZoneKind = enum(u8) {
    /// Safe zone - language guarantees apply.
    /// Skip or low priority analysis.
    safe,

    /// Unsafe zone - explicit escape from safety.
    /// High priority analysis.
    unsafe,

    /// FFI boundary - cross-language call.
    /// Critical analysis.
    ffi,

    /// Runtime internal - stdlib/runtime code.
    /// Skip analysis.
    runtime_internal,

    /// Unknown - needs classification.
    unknown,
};

/// Escape trigger for each language.
pub const EscapeTrigger = enum(u8) {
    // Rust escape triggers
    rust_unsafe_block,
    rust_unsafe_fn,
    rust_extern_c,
    rust_raw_pointer,
    rust_transmute,
    rust_maybe_uninit,
    rust_pin_misuse,
    rust_asm,

    // Zig escape triggers
    zig_ptr_cast,
    zig_int_to_ptr,
    zig_c_import,
    zig_extern_fn,
    zig_volatile_ptr,
    zig_packed_abi,

    // Go escape triggers
    go_cgo,
    go_unsafe_pointer,
    go_uintptr_tricks,

    // C++ escape triggers
    cpp_extern_c,
    cpp_reinterpret_cast,
    cpp_manual_alloc,
    cpp_thread_callback,

    // Generic
    unknown,
};

/// Rust safe patterns - skip analysis.
pub const RUST_SAFE_PATTERNS = [_][]const u8{
    // Standard library safe wrappers
    "std::vec::Vec",
    "std::string::String",
    "std::collections::",
    "std::sync::Arc",
    "std::sync::Mutex",
    "std::sync::RwLock",
    "std::sync::mpsc",
    "std::sync::mpmc",
    "std::cell::RefCell",
    "std::cell::Cell",
    "std::rc::Rc",
    "std::boxed::Box",
    "std::option::Option",
    "std::result::Result",

    // Ownership patterns (safe by design)
    "drop_in_place",
    "clone",
    "into_iter",
    "from_iter",

    // R7.0: Migrated from FPWhitelist Category 2 (Rust stdlib safe primitives)
    // These were verified as FPs from BLST/Wasmtime audits — safe by language guarantee.
    "sync_channel::",
    "Waker::",
    "RawVec::",

    // R7.0: Rust global allocator shims (compiler-generated runtime glue)
    "__rust_alloc",
    "__rust_dealloc",
};

/// Rust escape triggers - focus analysis.
pub const RUST_ESCAPE_PATTERNS = [_][]const u8{
    // Unsafe blocks (source-level)
    "unsafe",

    // FFI (source-level — may not match mangled names but kept for demangled paths)
    "extern \"C\"",
    "extern \"system\"",
    "libc::",
    "nix::",

    // Mangled name patterns for unsafe/FFI (LLVM IR level)
    "$u20$unsafe", // Rust mangled: " unsafe" in name
    "_ZN.*4ffi", // C++ mangled: contains "ffi"
    "_ZN.*7extern", // C++ mangled: contains "extern"

    // Raw pointer operations
    "*mut ",
    "*const ",
    "as_ptr",
    "as_mut_ptr",
    "from_raw_parts",
    "from_raw_parts_mut",

    // Transmute
    "std::mem::transmute",
    "core::mem::transmute",
    "transmute_copy",

    // MaybeUninit
    "MaybeUninit",
    "assume_init",

    // Pin
    "Pin<",
    "get_unchecked",
    "get_unchecked_mut",

    // Assembly
    "asm!",
    "llvm_asm!",

    // v0.1.7: Mangled-name level patterns (actually match LLVM IR names).
    // Source-level patterns above rarely match because Rust mangles everything.
    // These patterns target the actual symbols seen in LLVM IR:
    "_ffi", // mymod::_ffi_func
    "_extern", // bindgen-generated wrappers
    "_bindgen", // rust-bindgen output
    "_cinterop", // Zig-style C interop in Rust projects
    "_marshal", // serialization FFI boundary
    "_syscall", // direct syscall invocation
    "_invoke", // indirect call through FFI trampoline
    "_callback", // FFI callback handler
    "_native", // JNI/native interop
    "_interop", // generic interop boundary
    "$", // Rust legacy mangling (often used for FFI shims)
};

/// Zig safe patterns - skip analysis.
pub const ZIG_SAFE_PATTERNS = [_][]const u8{
    // Standard library safe wrappers
    "std.ArrayList",
    "std.StringArrayHashMap",
    "std.AutoHashMap",
    "std.mem.split",
    "std.mem.replace",
    "std.process",

    // Allocator wrappers - DC-C8 FIX: Use word boundary patterns to avoid false positives
    // e.g., "my_custom_allocator_dealloc" should NOT be matched as safe "free"
    ".allocator", // Explicit allocator type
    "@as(*std.mem.Allocator", // Allocator cast pattern
    "std.heap.page_allocator", // Specific safe allocators
    "std.heap.GeneralPurposeAllocator",

    // Defer patterns
    "defer",
    "errdefer",
};

/// Zig escape triggers - focus analysis.
pub const ZIG_ESCAPE_PATTERNS = [_][]const u8{
    // Pointer casts (Zig builtins)
    "@ptrCast",
    "@alignCast",
    "@intToPtr",
    "@ptrToInt",

    // C interop
    "@cImport",
    "@cInclude",
    "@cDefine",

    // Volatile (only with pointer, not standalone)
    "volatile ",

    // Packed ABI
    "packed struct",
    "@bitCast",
};

/// Go safe patterns - skip analysis.
pub const GO_SAFE_PATTERNS = [_][]const u8{
    // Runtime managed
    "runtime.",
    "make(",
    "new(",
    "append(",
    "copy(",
    "delete(",

    // GC managed
    "chan ",
    "map[",
    "func(",
    "interface{}",
};

/// Go escape triggers - focus analysis.
pub const GO_ESCAPE_PATTERNS = [_][]const u8{
    // Cgo
    "package C",
    "C.",
    "import \"C\"",

    // Unsafe
    "unsafe.Pointer",
    "unsafe.Sizeof",
    "unsafe.Offsetof",
    "unsafe.Alignof",

    // Uintptr tricks
    "uintptr(",
    "reflect.",
};

/// C++ safe patterns - skip analysis.
pub const CPP_SAFE_PATTERNS = [_][]const u8{
    // RAII containers
    "std::vector",
    "std::string",
    "std::unique_ptr",
    "std::shared_ptr",
    "std::weak_ptr",
    "std::map",
    "std::unordered_map",
    "std::set",

    // Smart pointer operations
    "make_unique",
    "make_shared",
    "get()",
    "reset()",
    "release()",
};

/// C++ escape triggers - focus analysis.
pub const CPP_ESCAPE_PATTERNS = [_][]const u8{
    // Dangerous casts
    "reinterpret_cast",
    "const_cast",
    "static_cast<void*",

    // Manual memory management
    "malloc(",
    "free(",
    "new ",
    "delete ",
    "realloc(",

    // Thread callback
    "pthread_create",
    "std::thread",
    "CreateThread",

    // Process management (C++ context)
    "fork(",
    "execvp(",
    "execve(",

    // Network I/O (C++ context)
    "getaddrinfo",
    "gethostbyname",
    "setsockopt",
    "getsockopt",
};

/// C escape triggers - focus analysis (C-specific, more precise than C++).
pub const C_ESCAPE_PATTERNS = [_][]const u8{
    // Dynamic loading
    "dlopen",
    "dlsym",
    "dlclose",

    // Memory mapping
    "mmap",
    "munmap",
    "mprotect",

    // Python C API prefix
    "Py_",

    // JNI prefix
    "JNI_",

    // Thread management
    "pthread_create",
    "pthread_join",

    // Signal handling
    "signal(",
    "sigaction(",

    // Process management
    "fork(",
    "exec",

    // Network I/O
    "getaddrinfo",
    "gethostbyname",
};

/// Statistics for zone classification.
pub const ZoneStats = struct {
    safe_count: u32 = 0,
    unsafe_count: u32 = 0,
    ffi_count: u32 = 0,
    runtime_count: u32 = 0,
    unknown_count: u32 = 0,

    pub fn record(self: *ZoneStats, zone: ZoneKind) void {
        switch (zone) {
            .safe => self.safe_count += 1,
            .unsafe => self.unsafe_count += 1,
            .ffi => self.ffi_count += 1,
            .runtime_internal => self.runtime_count += 1,
            .unknown => self.unknown_count += 1,
        }
    }

    pub fn total(self: ZoneStats) u32 {
        return self.safe_count + self.unsafe_count + self.ffi_count + self.runtime_count + self.unknown_count;
    }

    pub fn skipRatio(self: ZoneStats) f64 {
        const t = self.total();
        if (t == 0) return 0.0;
        return @as(f64, @floatFromInt(self.safe_count + self.runtime_count)) / @as(f64, @floatFromInt(t));
    }
};
