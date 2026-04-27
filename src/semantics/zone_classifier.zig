//! Zone Classification for Multi-Language Unsafe Boundary Analysis
//!
//! Core principle: Analyze only where language guarantees stop.
//!
//! Safe Zone (default trusted):
//! - Rust: safe fn, Vec/String normal use, borrow checker constraints
//! - Zig: normal slice/allocator idiom, defer/errdefer paths
//! - Go: non-cgo, normal GC objects
//! - C++: RAII container internals
//!
//! Escape Zone (focus analysis):
//! - Rust: unsafe block, extern "C", raw pointer, transmute
//! - Zig: @ptrCast, @intToPtr, @cImport, extern fn
//! - Go: cgo, unsafe.Pointer, uintptr tricks
//! - C++: extern C, reinterpret_cast, manual malloc/free

const std = @import("std");

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
};

/// Rust escape triggers - focus analysis.
pub const RUST_ESCAPE_PATTERNS = [_][]const u8{
    // Unsafe blocks
    "unsafe",

    // FFI
    "extern \"C\"",
    "extern \"system\"",
    "libc::",
    "nix::",

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

    // Allocator wrappers
    "alloc",
    "free",
    "resize",

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
    // Extern C
    "extern \"C\"",

    // Dangerous casts
    "reinterpret_cast",
    "const_cast",
    "static_cast<void*",

    // Manual memory
    "malloc(",
    "free(",
    "new ",
    "delete ",
    "realloc(",

    // Thread callback
    "pthread_create",
    "std::thread",
    "CreateThread",
};

/// Classify a function name into zone kind.
///
/// Arguments:
///   func_name - The function name to classify
///   lang - The source language (if known)
///
/// Returns:
///   ZoneKind classification
pub fn classifyFunction(func_name: []const u8, lang: ?Language) ZoneKind {
    if (func_name.len == 0) return .unknown;

    // Check language-specific patterns
    if (lang) |l| {
        return switch (l) {
            .rust => classifyRustFunction(func_name),
            .zig => classifyZigFunction(func_name),
            .go => classifyGoFunction(func_name),
            .cpp, .c => classifyCppFunction(func_name),
            else => .unknown,
        };
    }

    // Auto-detect language from patterns
    if (isRustFunction(func_name)) return classifyRustFunction(func_name);
    if (isZigFunction(func_name)) return classifyZigFunction(func_name);
    if (isGoFunction(func_name)) return classifyGoFunction(func_name);
    if (isCppFunction(func_name)) return classifyCppFunction(func_name);

    return .unknown;
}

/// Source language for classification.
pub const Language = enum(u8) {
    rust,
    zig,
    go,
    c,
    cpp,
    unknown,
};

/// Classify a Rust function.
fn classifyRustFunction(func_name: []const u8) ZoneKind {
    // Check escape triggers first
    for (RUST_ESCAPE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .unsafe;
        }
    }

    // Check for runtime internal (core/alloc/std stdlib)
    if (std.mem.startsWith(u8, func_name, "_ZN4core") or
        std.mem.startsWith(u8, func_name, "_ZN5alloc") or
        std.mem.startsWith(u8, func_name, "_ZN3std"))
    {
        return .runtime_internal;
    }

    // Check safe patterns
    for (RUST_SAFE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .safe;
        }
    }

    // Check for extern C
    if (std.mem.indexOf(u8, func_name, "extern") != null) {
        return .ffi;
    }

    // Default: user Rust code is safe (trust Rust's borrow checker)
    if (std.mem.startsWith(u8, func_name, "_ZN") or
        std.mem.startsWith(u8, func_name, "_R"))
    {
        return .safe;
    }

    return .unknown;
}

/// Classify a Zig function.
fn classifyZigFunction(func_name: []const u8) ZoneKind {
    for (ZIG_ESCAPE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .unsafe;
        }
    }

    for (ZIG_SAFE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .safe;
        }
    }

    if (std.mem.indexOf(u8, func_name, "extern") != null) {
        return .ffi;
    }

    return .unknown;
}

/// Classify a Go function.
fn classifyGoFunction(func_name: []const u8) ZoneKind {
    for (GO_ESCAPE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .unsafe;
        }
    }

    for (GO_SAFE_PATTERNS) |pattern| {
        if (std.mem.indexOf(u8, func_name, pattern) != null) {
            return .safe;
        }
    }

    if (std.mem.indexOf(u8, func_name, "C.") != null) {
        return .ffi;
    }

    return .unknown;
}

/// Classify a C++ function.
fn classifyCppFunction(func_name: []const u8) ZoneKind {
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

    if (std.mem.indexOf(u8, func_name, "extern \"C\"") != null) {
        return .ffi;
    }

    return .unknown;
}

/// Detect if function is Rust.
fn isRustFunction(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "_ZN4core")) return true;
    if (std.mem.startsWith(u8, func_name, "_ZN5alloc")) return true;
    if (std.mem.startsWith(u8, func_name, "_ZN3std")) return true;
    if (std.mem.startsWith(u8, func_name, "_ZN4ring")) return true;
    if (std.mem.startsWith(u8, func_name, "_R")) return true;
    if (std.mem.indexOf(u8, func_name, "$u20$") != null) return true;
    if (std.mem.indexOf(u8, func_name, "$LT$") != null) return true;
    if (std.mem.indexOf(u8, func_name, "$GT$") != null) return true;
    if (std.mem.indexOf(u8, func_name, "$C$") != null) return true;
    if (std.mem.indexOf(u8, func_name, "std::") != null) return true;
    if (std.mem.indexOf(u8, func_name, "core::") != null) return true;
    if (std.mem.indexOf(u8, func_name, "alloc::") != null) return true;
    return false;
}

/// Detect if function is Zig.
fn isZigFunction(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "std.")) return true;
    // Only match Zig builtins (@ptrCast, @intToPtr, etc.), not LLVM globals
    if (std.mem.indexOf(u8, func_name, "@ptrCast") != null) return true;
    if (std.mem.indexOf(u8, func_name, "@alignCast") != null) return true;
    if (std.mem.indexOf(u8, func_name, "@intToPtr") != null) return true;
    if (std.mem.indexOf(u8, func_name, "@ptrToInt") != null) return true;
    if (std.mem.indexOf(u8, func_name, "@cImport") != null) return true;
    if (std.mem.indexOf(u8, func_name, "@cInclude") != null) return true;
    if (std.mem.indexOf(u8, func_name, "@bitCast") != null) return true;
    return false;
}

/// Detect if function is Go.
fn isGoFunction(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "runtime.")) return true;
    if (std.mem.startsWith(u8, func_name, "main.")) return true;
    if (std.mem.indexOf(u8, func_name, "C.") != null) return true;
    return false;
}

/// Detect if function is C++.
fn isCppFunction(func_name: []const u8) bool {
    if (std.mem.startsWith(u8, func_name, "_Z")) return true;
    if (std.mem.indexOf(u8, func_name, "std::") != null) return true;
    return false;
}

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

test "classifyRustFunction - safe patterns" {
    try std.testing.expectEqual(ZoneKind.safe, classifyRustFunction("std::vec::Vec::push"));
    try std.testing.expectEqual(ZoneKind.safe, classifyRustFunction("std::sync::Arc::clone"));
    try std.testing.expectEqual(ZoneKind.runtime_internal, classifyRustFunction("_ZN4core3ptr13drop_in_place"));
    try std.testing.expectEqual(ZoneKind.safe, classifyRustFunction("_ZN4ring3rsa7keypair7KeyPair8from_der"));
}

test "classifyRustFunction - escape patterns" {
    try std.testing.expectEqual(ZoneKind.unsafe, classifyRustFunction("std::mem::transmute"));
    try std.testing.expectEqual(ZoneKind.unsafe, classifyRustFunction("as_ptr"));
}

test "ZoneStats" {
    var stats = ZoneStats{};
    stats.record(.safe);
    stats.record(.safe);
    stats.record(.unsafe);
    stats.record(.runtime_internal);

    try std.testing.expectEqual(@as(u32, 4), stats.total());
    try std.testing.expectEqual(@as(u32, 2), stats.safe_count);
    try std.testing.expectEqual(@as(f64, 0.75), stats.skipRatio());
}
