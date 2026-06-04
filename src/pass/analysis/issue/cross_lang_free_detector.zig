//! Cross-Language Free Detection Module
//!
//! Detects cross-language free mismatches where memory allocated by one
//! language's allocator is freed by a different language's deallocator.
//!
//! This is a critical FFI safety issue - using the wrong deallocator can
//! cause heap corruption, memory leaks, or undefined behavior.
//!
//! Supported language families:
//!   - C standard (malloc/free, calloc, realloc)
//!   - Rust global (__rust_alloc/__rust_dealloc, _RZN...allocate/deallocate)
//!   - C++ operators (operator new/delete)
//!   - Go runtime (runtime.mallocgc, _Cgo_malloc/_Cgo_free)
//!   - Python C API (PyMem_Malloc/PyMem_Free)
//!   - Zig stdlib (ArenaAllocator, GPA, page_allocator)

const std = @import("std");
const log = std.log.scoped(.cross_lang_free);

/// Allocator family classification for cross-language detection.
pub const AllocatorFamily = enum {
    /// C standard library: malloc, calloc, realloc, free, aligned_alloc
    c_standard,
    /// Rust global allocator: __rust_alloc/__rust_dealloc, _RZN...*allocate/*deallocate
    rust_global,
    /// Rust custom allocator: mimalloc, jemalloc wrapped in Rust
    rust_custom,
    /// C++ operator new/operator delete
    cpp_operator,
    /// C++ smart pointers: unique_ptr::release/reset, shared_ptr
    cpp_smart_ptr,
    /// Go runtime: runtime.mallocgc, _Cgo_malloc/_Cgo_free
    go_runtime,
    /// Python C API: PyMem_Malloc/PyMem_Free, PyObject_Malloc/PyObject_Free
    python_capi,
    /// Zig stdlib: ArenaAllocator, GPA, page_allocator, c_allocator
    zig_stdlib,
    /// Unknown user-defined or unrecognized allocator
    custom_unknown,

    pub fn displayName(self: AllocatorFamily) []const u8 {
        return switch (self) {
            .c_standard => "C Standard Library",
            .rust_global => "Rust Global Allocator",
            .rust_custom => "Rust Custom Allocator",
            .cpp_operator => "C++ Operator New/Delete",
            .cpp_smart_ptr => "C++ Smart Pointer",
            .go_runtime => "Go Runtime",
            .python_capi => "Python C API",
            .zig_stdlib => "Zig Standard Library",
            .custom_unknown => "Unknown/Custom",
        };
    }
};

/// Severity levels for cross-language free issues.
pub const SeverityLevel = enum {
    /// High severity: likely to cause issues but may work on some platforms
    high,
    /// Critical severity: almost certainly causes crashes/corruption
    critical,
};

/// Cross-language free mismatch issue details.
pub const CrossLangFreeIssue = struct {
    /// Severity of the issue (high or critical)
    severity: SeverityLevel,
    /// Confidence score (0.0 - 1.0)
    confidence: f32,
    /// Family of the allocation function
    alloc_family: AllocatorFamily,
    /// Family of the free function
    free_family: AllocatorFunction,
    /// Human-readable message describing the issue
    message: []const u8,
};

/// Detailed information about a free/deallocation function.
pub const AllocatorFunction = struct {
    /// Which allocator family this function belongs to
    family: AllocatorFamily,
    /// The original function name (for display)
    func_name: []const u8,
    /// Whether this is an allocation or deallocation function
    kind: enum { alloc, dealloc },
};

/// Classify an allocator/deallocator function into its language family.
/// Uses pattern matching on function names including mangled names.
pub fn classifyAllocatorFamily(func_name: []const u8) AllocatorFamily {
    // Fast path: check for known patterns in order of specificity

    // 1. Rust mangled names (v0 mangling: _R prefix)
    if (isRustMangledName(func_name)) return .rust_global;

    // 2. Rust compiler intrinsics (__rust_*, __rg_*, __rdl_*)
    if (isRustIntrinsic(func_name)) return .rust_global;

    // 3. Go runtime functions
    if (isGoRuntimeFunc(func_name)) return .go_runtime;

    // 4. Python C API functions
    if (PythonCApiFunc(func_name)) return .python_capi;

    // 5. C++ operators
    if (isCppOperator(func_name)) return .cpp_operator;

    // 6. Zig stdlib functions
    if (isZigStdlibFunc(func_name)) return .zig_stdlib;

    // 7. C standard library functions
    if (isCStandardFunc(func_name)) return .c_standard;

    // Default: unknown/custom
    return .custom_unknown;
}

/// Detect cross-language free mismatches.
/// Returns an issue if alloc and free are from different families AND it's unsafe.
/// Returns null if same family or known safe cross-family pattern.
pub fn detectCrossLanguageFree(
    alloc_func: []const u8,
    free_func: []const u8,
    allocator: std.mem.Allocator,
) !?CrossLangFreeIssue {
    const alloc_family = classifyAllocatorFamily(alloc_func);
    const free_family = classifyAllocatorFamily(free_func);

    log.debug("CROSS-LANG-FREE: alloc={s} (family={s}), free={s} (family={s})", .{
        alloc_func,
        @tagName(alloc_family),
        free_func,
        @tagName(free_family),
    });

    // Same family → no cross-language issue
    if (alloc_family == free_family) return null;

    // Check for intentional ownership transfer patterns (e.g., Box::leak → C free())
    // These are legitimate cross-language frees where ownership was explicitly transferred
    const intentional_patterns = [_][]const u8{
        "leak",       "into_raw",           "ManuallyDrop", "forget",
        "donate",     "transfer_ownership", "export_ptr",   "handoff",
        "ffi_export", "c_export",
    };
    for (intentional_patterns) |pattern| {
        if (std.mem.indexOf(u8, alloc_func, pattern) != null) {
            log.debug("CROSS-LANG-FREE: Intentional ownership transfer detected in alloc={s}, skipping", .{alloc_func});
            return null;
        }
    }

    // Check for safe cross-family patterns
    if (isSafeCrossPattern(alloc_family, free_family, free_func)) {
        log.debug("CROSS-LANG-FREE: Safe pattern detected, skipping", .{});
        return null;
    }

    // Calculate confidence based on risk level
    const confidence = calculateCrossLangConfidence(alloc_family, free_family);
    if (confidence < 0.5) return null; // Too uncertain

    // Determine severity based on risk combination
    const severity = determineSeverity(alloc_family, free_family);

    // Generate human-readable message
    const message = try fmtCrossLangMessage(allocator, alloc_func, free_func, alloc_family, free_family);

    return CrossLangFreeIssue{
        .severity = severity,
        .confidence = confidence,
        .alloc_family = alloc_family,
        .free_family = .{
            .family = free_family,
            .func_name = free_func,
            .kind = .dealloc,
        },
        .message = message,
    };
}

// ═══════════════════════════════════════════════════════════════
// Language-specific detection functions
// ═══════════════════════════════════════════════════════════════

/// Check if function name is a Rust mangled name (v0 mangling scheme).
/// Rust v0 mangling uses _R followed by encoding characters.
fn isRustMangledName(func: []const u8) bool {
    // _R prefix indicates Rust v0 mangling (RFC 2603)
    if (std.mem.startsWith(u8, func, "_R")) return true;

    // Legacy _ZN prefix (Rust's old Itanium-like mangling)
    if (std.mem.startsWith(u8, func, "_ZN")) return true;

    // Common Rust stdlib patterns in mangled names
    const rust_mangled_patterns = [_][]const u8{
        "alloc5alloc", // alloc::alloc
        "alloc5dealloc", // alloc::dealloc
        "std3box", // std::box
        "std3string", // std::string
        "std3vec", // std::vec
        "std3rc", // std::rc
        "std3arc", // std::arc
    };

    for (rust_mangled_patterns) |pattern| {
        if (std.mem.indexOf(u8, func, pattern) != null) return true;
    }

    return false;
}

/// Check if function is a Rust compiler intrinsic allocator.
fn isRustIntrinsic(func: []const u8) bool {
    const rust_intrinsics = [_][]const u8{
        "__rust_alloc", // Rust global allocator (alloc)
        "__rust_dealloc", // Rust global allocator (dealloc)
        "__rust_realloc", // Rust global allocator (realloc)
        "__rust_alloc_zeroed", // Rust global allocator (calloc equivalent)
        "__rg_alloc", // Rust global allocator (short form)
        "__rg_dealloc", // Rust global dealloc (short form)
        "__rg_realloc", // Rust global realloc (short form)
        "__rdl_alloc", // Rust dealloc (older name)
        "__rdl_dealloc", // Rust dealloc (older name)
    };

    for (rust_intrinsics) |intrinsic| {
        if (std.mem.eql(u8, func, intrinsic) or
            std.mem.startsWith(u8, func, intrinsic))
        {
            return true;
        }
    }

    return false;
}

/// Check if function is a Go runtime memory function.
fn isGoRuntimeFunc(func: []const u8) bool {
    const go_patterns = [_][]const u8{
        "runtime.mallocgc",
        "runtime.allocm",
        "_Cgo_malloc",
        "_Cgo_free",
        "runtime.persistentalloc",
        "runtime.memmove",
        "runtime.memclrNoHeapPointers",
    };

    for (go_patterns) |pattern| {
        if (std.mem.indexOf(u8, func, pattern) != null) return true;
    }

    // Go package paths often contain "/"
    if (std.mem.indexOf(u8, func, "/") != null) {
        if (std.mem.indexOf(u8, func, "malloc") != null or
            std.mem.indexOf(u8, func, "free") != null)
        {
            return true;
        }
    }

    return false;
}

/// Check if function is a Python C API memory function.
fn PythonCApiFunc(func: []const u8) bool {
    const python_patterns = [_][]const u8{
        "PyMem_Malloc",
        "PyMem_Realloc",
        "PyMem_Free",
        "PyObject_Malloc",
        "PyObject_Realloc",
        "PyObject_Free",
        "_PyObject_Malloc",
        "_PyObject_Free",
    };

    for (python_patterns) |pattern| {
        if (std.mem.eql(u8, func, pattern) or
            std.mem.startsWith(u8, func, pattern))
        {
            return true;
        }
    }

    return false;
}

/// Check if function is a C++ operator new/delete.
fn isCppOperator(func: []const u8) bool {
    // Mangled C++ names
    if (std.mem.indexOf(u8, func, "_Znwm") != null) return true; // operator new
    if (std.mem.indexOf(u8, func, "_ZdlPv") != null) return true; // operator delete
    if (std.mem.indexOf(u8, func, "_Znam") != null) return true; // operator new[]
    if (std.mem.indexOf(u8, func, "_ZdaPv") != null) return true; // operator delete[]
    if (std.mem.indexOf(u8, func, "_Zdl") != null) return true; // operator delete variants

    // Demangled names
    if (std.mem.startsWith(u8, func, "operator new")) return true;
    if (std.mem.startsWith(u8, func, "operator delete")) return true;

    return false;
}

/// Check if function is a Zig stdlib allocator function.
fn isZigStdlibFunc(func: []const u8) bool {
    const zig_patterns = [_][]const u8{
        "ArenaAllocator",
        "GeneralPurposeAllocator",
        "page_allocator",
        "c_allocator",
        ".alloc",
        ".free",
        ".create",
        ".destroy",
        ".init",
        ".deinit",
    };

    for (zig_patterns) |pattern| {
        if (std.mem.indexOf(u8, func, pattern) != null) return true;
    }

    return false;
}

/// Check if function is a C standard library memory function.
fn isCStandardFunc(func: []const u8) bool {
    const c_std_functions = [_][]const u8{
        "malloc",
        "calloc",
        "realloc",
        "free",
        "aligned_alloc",
        "posix_memalign",
        "memalign",
        "valloc",
        "pvalloc",
        "strdup",
        "strndup",
        "reallocarray",
    };

    for (c_std_functions) |c_fn| {
        if (std.mem.eql(u8, func, c_fn)) return true;
    }

    return false;
}

// ═══════════════════════════════════════════════════════════════
// Safety analysis functions
// ═══════════════════════════════════════════════════════════════

/// Check if a cross-family alloc/free pair is a known safe pattern.
/// Some combinations are safe due to language interoperability conventions.
fn isSafeCrossPattern(
    alloc_family: AllocatorFamily,
    free_family: AllocatorFamily,
    free_func: []const u8,
) bool {
    // Rule 1: C malloc → any standard free is usually OK
    // Many languages provide C-compatible wrappers that use the same heap
    if (alloc_family == .c_standard) {
        switch (free_family) {
            .cpp_operator => {
                // C malloc + C++ operator delete is technically UB but widely tolerated
                // Only flag if it's clearly wrong (e.g., new[] with free())
                return true;
            },
            .go_runtime => {
                // Go's CGo can free C-allocated memory with C.free()
                if (std.mem.indexOf(u8, free_func, "free") != null) return true;
            },
            else => {},
        }
    }

    // Rule 2: C++ operator new → C free is sometimes OK in mixed codebases
    // but generally risky - we'll still report it with lower confidence

    // Rule 3: Rust → anything other than Rust is almost always unsafe
    // No safe patterns here - all will be reported

    // Rule 4: Python C API → C free can be OK for simple types
    if (alloc_family == .python_capi and free_family == .c_standard) {
        // PyMem_* allocations can be freed with free() on some implementations
        return true;
    }

    // Rule 5: Go runtime → C free via CGo is explicitly supported
    if (alloc_family == .go_runtime and free_family == .c_standard) {
        if (std.mem.indexOf(u8, free_func, "free") != null) return true;
    }

    return false;
}

/// Calculate confidence score for a cross-language free mismatch.
/// Higher confidence = more likely to be a real bug.
fn calculateCrossLangConfidence(
    alloc_family: AllocatorFamily,
    free_family: AllocatorFamily,
) f32 {
    var confidence: f32 = 0.85; // Start with high base confidence

    // Adjust based on known risky combinations
    switch (alloc_family) {
        .rust_global => {
            // Rust allocator freed by non-Rust is very dangerous
            switch (free_family) {
                .c_standard => confidence = 0.98, // Almost certainly a bug
                .cpp_operator => confidence = 0.95,
                .go_runtime => confidence = 0.90,
                .python_capi => confidence = 0.92,
                else => {},
            }
        },
        .c_standard => {
            // C malloc freed by non-C is also bad but more common
            switch (free_family) {
                .rust_global => confidence = 0.97, // Very dangerous
                .go_runtime => confidence = 0.75, // Might be intentional CGo
                .python_capi => confidence = 0.80, // Might be intentional embedding
                else => {},
            }
        },
        .go_runtime => {
            switch (free_family) {
                .rust_global => confidence = 0.93,
                .c_standard => confidence = 0.60, // Often intentional CGo
                else => {},
            }
        },
        .python_capi => {
            switch (free_family) {
                .rust_global => confidence = 0.94,
                .c_standard => confidence = 0.65, // Sometimes OK
                else => {},
            }
        },
        else => {},
    }

    return confidence;
}

/// Determine severity based on which families are mismatched.
fn determineSeverity(
    alloc_family: AllocatorFamily,
    free_family: AllocatorFamily,
) SeverityLevel {
    // Critical combinations that almost always cause crashes/corruption
    const critical_combinations = [4][2]AllocatorFamily{
        .{ .rust_global, .c_standard },
        .{ .c_standard, .rust_global },
        .{ .rust_global, .cpp_operator },
        .{ .cpp_operator, .rust_global },
    };

    for (critical_combinations) |combo| {
        if ((alloc_family == combo[0] and free_family == combo[1]) or
            (alloc_family == combo[1] and free_family == combo[0]))
        {
            return .critical;
        }
    }

    // All other mismatches are high severity
    return .high;
}

/// Format a human-readable error message for cross-language free mismatch.
fn fmtCrossLangMessage(
    allocator: std.mem.Allocator,
    alloc_func: []const u8,
    free_func: []const u8,
    alloc_family: AllocatorFamily,
    free_family: AllocatorFamily,
) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        \\Cross-language free mismatch: memory allocated by '{s}' ({s}) was freed using '{s}' ({s}).
        \\This is undefined behavior - different runtimes may use different heaps.
        \\Use the correct deallocator for the allocation source.
    , .{
        alloc_func,
        alloc_family.displayName(),
        free_func,
        free_family.displayName(),
    });
}

// ═══════════════════════════════════════════════════════════════
// Test helpers (exported for unit testing)
// ═══════════════════════════════════════════════════════════════

/// Quick check if two function names are from different allocator families.
/// Convenience wrapper for simple cases.
pub fn isCrossLanguageMismatch(alloc_func: []const u8, free_func: []const u8) bool {
    const alloc_fam = classifyAllocatorFamily(alloc_func);
    const free_fam = classifyAllocatorFamily(free_func);

    if (alloc_fam == free_fam) return false;
    if (alloc_fam == .custom_unknown or free_fam == .custom_unknown) return false;

    return !isSafeCrossPattern(alloc_fam, free_fam, free_func);
}

test "classifyAllocatorFamily - C standard" {
    try std.testing.expectEqual(AllocatorFamily.c_standard, classifyAllocatorFamily("malloc"));
    try std.testing.expectEqual(AllocatorFamily.c_standard, classifyAllocatorFamily("free"));
    try std.testing.expectEqual(AllocatorFamily.c_standard, classifyAllocatorFamily("calloc"));
    try std.testing.expectEqual(AllocatorFamily.c_standard, classifyAllocatorFamily("realloc"));
}

test "classifyAllocatorFamily - Rust global" {
    try std.testing.expectEqual(AllocatorFamily.rust_global, classifyAllocatorFamily("__rust_alloc"));
    try std.testing.expectEqual(AllocatorFamily.rust_global, classifyAllocatorFamily("__rust_dealloc"));
    try std.testing.expectEqual(AllocatorFamily.rust_global, classifyAllocatorFamily("_RZN4alloc5alloc17h_allocate"));
    try std.testing.expectEqual(AllocatorFamily.rust_global, classifyAllocatorFamily("_RZN4alloc5alloc17h_deallocate"));
    try std.testing.expectEqual(AllocatorFamily.rust_global, classifyAllocatorFamily("__rg_alloc"));
    try std.testing.expectEqual(AllocatorFamily.rust_global, classifyAllocatorFamily("__rg_dealloc"));
}

test "classifyAllocatorFamily - C++ operators" {
    try std.testing.expectEqual(AllocatorFamily.cpp_operator, classifyAllocatorFamily("_Znwm"));
    try std.testing.expectEqual(AllocatorFamily.cpp_operator, classifyAllocatorFamily("_ZdlPv"));
    try std.testing.expectEqual(AllocatorFamily.cpp_operator, classifyAllocatorFamily("operator new"));
    try std.testing.expectEqual(AllocatorFamily.cpp_operator, classifyAllocatorFamily("operator delete"));
}

test "detectCrossLanguageFree - Rust alloc + C free" {
    const testing_allocator = std.testing.allocator;
    const result = try detectCrossLanguageFree(
        "_RZN4alloc5alloc17h_allocate",
        "free",
        testing_allocator,
    );
    try std.testing.expect(result != null);
    try std.testing.expectEqual(AllocatorFamily.rust_global, result.?.alloc_family);
    try std.testing.expectEqual(AllocatorFamily.c_standard, result.?.free_family.family);
    try std.testing.expect(result.?.confidence > 0.9);
    testing_allocator.free(result.?.message);
}

test "detectCrossLanguageFree - C alloc + Rust free" {
    const testing_allocator = std.testing.allocator;
    const result = try detectCrossLanguageFree(
        "malloc",
        "_RZN4alloc5alloc17h_deallocate",
        testing_allocator,
    );
    try std.testing.expect(result != null);
    try std.testing.expectEqual(AllocatorFamily.c_standard, result.?.alloc_family);
    try std.testing.expectEqual(AllocatorFamily.rust_global, result.?.free_family.family);
    testing_allocator.free(result.?.message);
}

test "detectCrossLanguageFree - Same family (should return null)" {
    const testing_allocator = std.testing.allocator;
    const result = try detectCrossLanguageFree(
        "malloc",
        "free",
        testing_allocator,
    );
    try std.testing.expect(result == null);
}

test "isCrossLanguageMismatch - basic cases" {
    try std.testing.expect(isCrossLanguageMismatch("_RZN4alloc5alloc17h_allocate", "free"));
    try std.testing.expect(isCrossLanguageMismatch("malloc", "__rust_dealloc"));
    try std.testing.expect(!isCrossLanguageMismatch("malloc", "free"));
    try std.testing.expect(!isCrossLanguageMismatch("__rust_alloc", "__rust_dealloc"));
}
