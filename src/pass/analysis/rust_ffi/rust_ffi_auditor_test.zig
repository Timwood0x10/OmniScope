//! Tests for RustFFIAuditor extended detection capabilities.
//!
//! Covers core::ffi, libc crate, and FFI boundary classification.

const std = @import("std");

const rust_ffi = @import("rust_ffi_auditor.zig");

const isCoreFfiFunction = rust_ffi.isCoreFfiFunction;
const isLibcFunction = rust_ffi.isLibcFunction;
const isExternCCall = rust_ffi.isExternCCall;
const classifyFfiBoundaryType = rust_ffi.classifyFfiBoundaryType;

// ============================================================================
// Test: isCoreFfiFunction - core::ffi crate detection
// ============================================================================

test "isCoreFfiFunction - CStr and CString patterns" {
    // CStr (from bytes to C string)
    try std.testing.expect(isCoreFfiFunction("CStr.from_bytes_with_nul"));
    try std.testing.expect(isCoreFfiFunction("CStr.from_bytes_with_nul_unchecked"));

    // CString (owned C string)
    try std.testing.expect(isCoreFfiFunction("CString.new"));
    try std.testing.expect(isCoreFfiFunction("CString.into_boxed_c_str"));
}

test "isCoreFfiFunction - c_void, c_char, c_int types" {
    // Primitive type names used in FFI signatures
    try std.testing.expect(isCoreFfiFunction("c_void"));
    try std.testing.expect(isCoreFfiFunction("c_char"));
    try std.testing.expect(isCoreFfiFunction("c_int"));
    try std.testing.expect(isCoreFfiFunction("c_long"));
    try std.testing.expect(isCoreFfiFunction("c_uint"));
    try std.testing.expect(isCoreFfiFunction("c_ulong"));
    try std.testing.expect(isCoreFfiFunction("c_float"));
    try std.testing.expect(isCoreFfiFunction("c_double"));
}

test "isCoreFfiFunction - pointer conversion functions" {
    // Raw pointer conversions (ownership transfer)
    try std.testing.expect(isCoreFfiFunction("from_raw"));
    try std.testing.expect(isCoreFfiFunction("into_raw"));

    // String/pointer accessors
    try std.testing.expect(isCoreFfiFunction("as_ptr"));
    try std.testing.expect(isCoreFfiFunction("to_ptr"));
    try std.testing.expect(isCoreFfiFunction("to_str"));
}

test "isCoreFfiFunction - negative cases" {
    // These should NOT be detected as core::ffi
    try std.testing.expect(!isCoreFfiFunction("malloc"));
    try std.testing.expect(!isCoreFfiFunction("free"));
    try std.testing.expect(!isCoreFfiFunction("printf"));
    try std.testing.expect(!isCoreFfiFunction("my_custom_function"));
    try std.testing.expect(!isCoreFfiFunction("_ZN")); // C++ mangled name
    try std.testing.expect(!isCoreFfiFunction("__rust")); // Rust internal
}

test "isCoreFfiFunction - substring matching" {
    // Should match even if pattern appears in longer name
    try std.testing.expect(isCoreFfiFunction("my_CString_wrapper"));
    try std.testing.expect(isCoreFfiFunction("convert_to_c_int_value"));
    try std.testing.expect(isCoreFfiFunction("get_as_ptr_from_struct"));
}

// ============================================================================
// Test: isLibcFunction - libc crate detection
// ============================================================================

test "isLibcFunction - memory management" {
    // Standard POSIX memory functions
    try std.testing.expect(isLibcFunction("malloc"));
    try std.testing.expect(isLibcFunction("calloc"));
    try std.testing.expect(isLibcFunction("realloc"));
    try std.testing.expect(isLibcFunction("free"));
    try std.testing.expect(isLibcFunction("memalign"));
    try std.testing.expect(isLibcFunction("posix_memalign"));
}

test "isLibcFunction - I/O operations" {
    // File I/O
    try std.testing.expect(isLibcFunction("open"));
    try std.testing.expect(isLibcFunction("read"));
    try std.testing.expect(isLibcFunction("write"));
    try std.testing.expect(isLibcFunction("close"));
    try std.testing.expect(isLibcFunction("fcntl"));
    try std.testing.expect(isLibcFunction("ioctl"));
    try std.testing.expect(isLibcFunction("fstat"));
    try std.testing.expect(isLibcFunction("lseek"));

    // Memory-mapped I/O
    try std.testing.expect(isLibcFunction("mmap"));
    try std.testing.expect(isLibcFunction("munmap"));
}

test "isLibcFunction - threading" {
    // pthreads
    try std.testing.expect(isLibcFunction("pthread_create"));
    try std.testing.expect(isLibcFunction("pthread_join"));
    try std.testing.expect(isLibcFunction("pthread_mutex_lock"));
    try std.testing.expect(isLibcFunction("pthread_mutex_unlock"));
    try std.testing.expect(isLibcFunction("pthread_cond_wait"));
    try std.testing.expect(isLibcFunction("pthread_cond_signal"));
}

test "isLibcFunction - string operations" {
    // C string utilities
    try std.testing.expect(isLibcFunction("strlen"));
    try std.testing.expect(isLibcFunction("strcpy"));
    try std.testing.expect(isLibcFunction("strncpy"));
    try std.testing.expect(isLibcFunction("strcat"));
    try std.testing.expect(isLibcFunction("strncat"));
    try std.testing.expect(isLibcFunction("strcmp"));
    try std.testing.expect(isLibcFunction("strncmp"));
    try std.testing.expect(isLibcFunction("strdup"));
}

test "isLibcFunction - networking" {
    // Socket API
    try std.testing.expect(isLibcFunction("socket"));
    try std.testing.expect(isLibcFunction("bind"));
    try std.testing.expect(isLibcFunction("listen"));
    try std.testing.expect(isLibcFunction("accept"));
    try std.testing.expect(isLibcFunction("connect"));
    try std.testing.expect(isLibcFunction("send"));
    try std.testing.expect(isLibcFunction("recv"));
}

test "isLibcFunction - time and environment" {
    // Time functions
    try std.testing.expect(isLibcFunction("time"));
    try std.testing.expect(isLibcFunction("gettimeofday"));
    try std.testing.expect(isLibcFunction("clock_gettime"));
    try std.testing.expect(isLibcFunction("sleep"));
    try std.testing.expect(isLibcFunction("usleep"));
    try std.testing.expect(isLibcFunction("nanosleep"));

    // Environment
    try std.testing.expect(isLibcFunction("getenv"));
    try std.testing.expect(isLibcFunction("setenv"));
    try std.testing.expect(isLibcFunction("unsetenv"));

    // Error handling
    try std.testing.expect(isLibcFunction("errno"));
    try std.testing.expect(isLibcFunction("strerror"));
    try std.testing.expect(isLibcFunction("perror"));
}

test "isLibcFunction - negative cases" {
    // Non-libc functions should not match
    try std.testing.expect(!isLibcFunction("my_malloc"));
    try std.testing.expect(!isLibcFunction("custom_free"));
    try std.testing.expect(!isLibcFunction("malloc_fast"));
    try std.testing.expect(!isLibcFunction("xmalloc")); // glibc internal
    try std.testing.expect(!isLibcFunction("")); // empty string
}

// ============================================================================
// Test: classifyFfiBoundaryType - FFI boundary classification
// ============================================================================

test "classifyFfiBoundaryType - standard extern C" {
    const result = classifyFfiBoundaryType("malloc", null);
    try std.testing.expectEqual(@as(@typeInfo(@TypeOf(result)).Enum.tag_type, .standard), result);
}

test "classifyFfiBoundaryType - core::ffi utilities" {
    var result = classifyFfiBoundaryType("CStr.from_bytes", null);
    try std.testing.expectEqual(.core_ffi, result);

    result = classifyFfiBoundaryType("into_raw", null);
    try std.testing.expectEqual(.core_ffi, result);

    result = classifyFfiBoundaryType("from_raw", null);
    try std.testing.expectEqual(.core_ffi, result);
}

test "classifyFfiBoundaryType - libc crate wrappers" {
    var result = classifyFfiBoundaryType("pthread_create", null);
    try std.testing.expectEqual(.libc_crate, result);

    result = classifyFfiBoundaryType("socket", null);
    try std.testing.expectEqual(.libc_crate, result);

    result = classifyFfiBoundaryType("mmap", null);
    try std.testing.expectEqual(.libc_crate, result);
}

test "classifyFfiBoundaryType - OS-specific APIs" {
    // Windows APIs
    var result = classifyFfiBoundaryType("CreateFileW", null);
    try std.testing.expectEqual(.os_api, result);

    result = classifyFfiBoundaryType("ReadFile", null);
    try std.testing.expectEqual(.os_api, result);

    // macOS APIs
    result = classifyFfiBoundaryType("CFStringCreateWithCString", null);
    try std.testing.expectEqual(.os_api, result);

    result = classifyFfiBoundaryType("dispatch_async_f", null);
    try std.testing.expectEqual(.os_api, result);

    // Linux APIs
    result = classifyFfiBoundaryType("epoll_create1", null);
    try std.testing.expectEqual(.os_api, result);

    result = classifyFfiBoundaryType("inotify_init1", null);
    try std.testing.expectEqual(.os_api, result);
}

test "classifyFfiBoundaryType - unknown/custom FFI" {
    const result = classifyFfiBoundaryType("my_custom_ffi_func", null);
    try std.testing.expectEqual(.unknown, result);
}

test "classifyFfiBoundaryType - edge cases" {
    // Empty string
    const result_empty = classifyFfiBoundaryType("", null);
    try std.testing.expectEqual(.unknown, result_empty);

    // Rust mangled name
    const result_rust = classifyFfiBoundaryType("_ZN3foo3barE", null);
    try std.testing.expectEqual(.unknown, result_rust);

    // LLVM internal
    const result_llvm = classifyFfiBoundaryType("llvm.dbg.declare", null);
    try std.testing.expectEqual(.unknown, result_llvm);
}

// ============================================================================
// Test: isExternCCall - basic extern detection
// ============================================================================

test "isExternCCall - valid extern C calls" {
    try std.testing.expect(isExternCCall("malloc"));
    try std.testing.expect(isExternCCall("free"));
    try std.testing.expect(isExternCCall("printf"));
    try std.testing.expect(isExternCCall("my_extern_function"));
    try std.testing.expect(isExternCCall("process_data"));
}

test "isExternCCall - invalid calls" {
    // Empty
    try std.testing.expect(!isExternCCall(""));

    // Starts with underscore (internal)
    try std.testing.expect(!isExternCCall("_internal_func"));

    // C++ mangled
    try std.testing.expect(!isExternCCall("_Z3fooi"));

    // Rust mangled
    try std.testing.expect(!isExternCCall("_RNvC"));
}

// ============================================================================
// Test: Accuracy validation - ensure high precision
// ============================================================================

test "Accuracy - core::ffi detection precision" {
    // True positives (should detect)
    const tp_count = 20;
    var tp_detected: u32 = 0;

    const true_positives = [_][]const u8{
        "CStr.from_bytes",
        "CString.new",
        "c_void",
        "c_char",
        "c_int",
        "c_long",
        "from_raw",
        "into_raw",
        "as_ptr",
        "to_ptr",
        "c_uint",
        "c_ulong",
        "c_float",
        "c_double",
        "to_str",
        "from_bytes_with_nul_unchecked",
        "into_boxed_c_str",
        "as_ptr_unchecked",
    };

    for (true_positives) |name| {
        if (isCoreFfiFunction(name)) tp_detected += 1;
    }

    // Should detect all true positives
    try std.testing.expectEqual(tp_count, tp_detected);

    // False positives (should NOT detect)
    const fp_count = 10;
    var fp_false_positive: u32 = 0;

    const false_positives = [_][]const u8{
        "malloc",          "free",     "printf",    "memcpy",
        "my_string",       "char_ptr", "int_value", "_Zmangled",
        "__rust_internal", "",         "main",
    };

    for (false_positives) |name| {
        if (!isCoreFfiFunction(name)) fp_false_positive += 1;
    }

    // Should reject all false positives
    try std.testing.expectEqual(fp_count, fp_false_positive);

    // Calculate precision
    const total_detected = tp_detected + (tp_count - tp_detected) + (fp_count - fp_false_positive);
    const precision: f32 = @as(f32, @floatFromInt(tp_detected)) / @as(f32, @floatFromInt(total_detected));

    // Precision should be >= 95%
    try std.testing.expectGreaterThanOrEqual(precision, 0.95);
}

test "Accuracy - libc function detection precision" {
    // Sample of common libc functions
    const test_functions = [_][]struct { name: []const u8, expected: bool }{
        .{ .name = "malloc", .expected = true },
        .{ .name = "free", .expected = true },
        .{ .name = "pthread_create", .expected = true },
        .{ .name = "socket", .expected = true },
        .{ .name = "strlen", .expected = true },
        .{ .name = "getenv", .expected = true },
        .{ .name = "my_malloc", .expected = false }, // Not exact match
        .{ .name = "xmalloc", .expected = false }, // glibc internal
        .{ .name = "", .expected = false },
        .{ .name = "printf", .expected = false }, // Not in our list
    };

    var correct: u32 = 0;

    for (test_functions) |tf| {
        const result = isLibcFunction(tf.name);
        if (result == tf.expected) correct += 1;
    }

    // All classifications should be correct
    try std.testing.expectEqual(@as(u32, test_functions.len), correct);
}

test "Accuracy - FFI boundary classification coverage" {
    // Test that we can classify various FFI patterns correctly
    const test_cases = [_][]struct {
        name: []const u8,
        expected_kind: @TypeOf(classifyFfiBoundaryType("", null).Enum().tag_type),
    }{
        .{ .name = "malloc", .expected_kind = .standard },
        .{ .name = "CStr.from_bytes", .expected_kind = .core_ffi },
        .{ .name = "pthread_create", .expected_kind = .libc_crate },
        .{ .name = "CreateFileW", .expected_kind = .os_api },
        .{ .name = "unknown_func", .expected_kind = .unknown },
    };

    var correct: u32 = 0;

    for (test_cases) |tc| {
        const result = classifyFfiBoundaryType(tc.name, null);
        if (result == tc.expected_kind) correct += 1;
    }

    // All classifications should be correct (100% accuracy)
    try std.testing.expectEqual(@as(u32, test_cases.len), correct);
}
