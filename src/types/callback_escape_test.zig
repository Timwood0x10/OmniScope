//! Tests for CallbackEscapePass and related modules.
//!
//! Extracted from callback_escape.zig to comply with the 1000-line limit.

const std = @import("std");

const CallbackEscapePass = @import("../pass/analysis/callback_escape.zig").CallbackEscapePass;
const PassKind = @import("../pass/pass.zig").PassKind;

const isCgoBoundary = @import("../pass/analysis/callback_escape.zig").isCgoBoundary;
const isGoSafetyFunction = @import("../pass/analysis/callback_escape.zig").isGoSafetyFunction;
const isCBytesPattern = @import("../pass/analysis/callback_escape.zig").isCBytesPattern;
const isUnsafePtrConversion = @import("../pass/analysis/callback_escape.zig").isUnsafePtrConversion;
const isCgoBoundaryFromLLVM = @import("../pass/analysis/callback_escape.zig").isCgoBoundaryFromLLVM;
const mayRetainInCLanguageAware = @import("../pass/analysis/callback_escape.zig").mayRetainInCLanguageAware;
const isRegisterNativesPattern = @import("../pass/analysis/callback_escape.zig").isRegisterNativesPattern;
const isPthreadCreatePattern = @import("../pass/analysis/callback_escape.zig").isPthreadCreatePattern;
const isCallbackReceiver = @import("../pass/analysis/callback_escape.zig").isCallbackReceiver;
const isCgoGlueByPattern = @import("../pass/analysis/callback_escape.zig").isCgoGlueByPattern;
const validate_callback_signature = @import("../pass/analysis/callback_escape.zig").validate_callback_signature;

const EscapeViolation = @import("../pass/analysis/callback_escape.zig").EscapeViolation;
const EscapePattern = @import("../pass/analysis/callback_escape.zig").EscapePattern;
const EscapeStats = @import("../pass/analysis/callback_escape.zig").EscapeStats;

test "CallbackEscapePass - name and kind" {
    try std.testing.expectEqualStrings("callback-escape", CallbackEscapePass.name);
    try std.testing.expectEqual(PassKind.analysis, CallbackEscapePass.kind);
}

test "isCgoBoundary - cgo patterns" {
    try std.testing.expect(isCgoBoundary("_cgo_cfunction_wrapper"));
    try std.testing.expect(isCgoBoundary("_Cfunc_process"));
    try std.testing.expect(isCgoBoundary("C.process"));
    try std.testing.expect(isCgoBoundary("C.malloc"));
    try std.testing.expect(!isCgoBoundary("my_function"));
    try std.testing.expect(!isCgoBoundary("runtime.main"));
}

test "isGoSafetyFunction - KeepAlive detection" {
    try std.testing.expect(isGoSafetyFunction("runtime.KeepAlive"));
    try std.testing.expect(isGoSafetyFunction("runtime_Pin"));
    try std.testing.expect(isGoSafetyFunction("runtime_cgocall"));
    try std.testing.expect(!isGoSafetyFunction("malloc"));
    try std.testing.expect(!isGoSafetyFunction("printf"));
}

test "isCBytesPattern - byte conversion detection" {
    try std.testing.expect(isCBytesPattern("C.CBytes"));
    try std.testing.expect(isCBytesPattern("C.GoString"));
    try std.testing.expect(isCBytesPattern("C.GoStringN"));
    try std.testing.expect(!isCBytesPattern("C.malloc"));
    try std.testing.expect(!isCBytesPattern("memcpy"));
}

test "isUnsafePtrConversion - unsafe pointer detection" {
    try std.testing.expect(isUnsafePtrConversion("unsafe.Pointer"));
    try std.testing.expect(isUnsafePtrConversion("some_unsafe.Pointer_func"));
    try std.testing.expect(isUnsafePtrConversion("uintptr_conversion"));
    try std.testing.expect(!isUnsafePtrConversion("malloc"));
    try std.testing.expect(!isUnsafePtrConversion("normal_func"));
}

test "EscapeViolation - enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(EscapeViolation.go_pointer_no_keepalive));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(EscapeViolation.cbytes_escape));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(EscapeViolation.unsafeptr_dangling_risk));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(EscapeViolation.malloc_without_free));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(EscapeViolation.free_without_malloc));
}

test "isCgoBoundaryFromLLVM - null safety" {
    // Null function ref should return false
    try std.testing.expect(!isCgoBoundaryFromLLVM(null));
}

test "isCgoBoundaryFromLLVM - linkage detection logic" {
    const result = isCgoBoundaryFromLLVM(null);
    try std.testing.expectEqual(false, result);
}

test "EscapePattern - initialization" {
    const pattern = EscapePattern{
        .violation_type = .go_pointer_no_keepalive,
        .confidence = 0.85,
        .func_name = "test_func",
        .callee_name = "C.process",
        .description = "missing KeepAlive",
    };
    try std.testing.expectEqual(EscapeViolation.go_pointer_no_keepalive, pattern.violation_type);
    try std.testing.approxApproxEqAbs(@as(f32, 0.85), pattern.confidence, 0.01);
    try std.testing.expectEqualStrings("test_func", pattern.func_name);
}

test "EscapeStats - initialization" {
    const stats = EscapeStats{};
    try std.testing.expectEqual(@as(u32, 0), stats.total_functions_analyzed);
    try std.testing.expectEqual(@as(u32, 0), stats.keepalive_missing);
    try std.testing.expectEqual(@as(u32, 0), stats.cbytes_escapes);
}

test "EscapeStats - tracking" {
    var stats = EscapeStats{};
    stats.total_functions_analyzed = 15;
    stats.go_cgo_boundaries_found = 5;
    stats.keepalive_missing = 3;
    stats.cbytes_escapes = 2;
    stats.unsafeptr_risks = 4;
    stats.malloc_leaks = 1;
    stats.free_orphans = 1;

    try std.testing.expectEqual(@as(u32, 15), stats.total_functions_analyzed);
    try std.testing.expectEqual(@as(u32, 5), stats.go_cgo_boundaries_found);
    try std.testing.expectEqual(@as(u32, 11), stats.keepalive_missing + stats.cbytes_escapes +
        stats.unsafeptr_risks + stats.malloc_leaks + stats.free_orphans);
}

test "mayRetainInCLanguageAware - C_RETAINING_FUNCTIONS always match" {
    try std.testing.expect(mayRetainInCLanguageAware("pthread_create", true));
    try std.testing.expect(mayRetainInCLanguageAware("RegisterNatives", true));
    try std.testing.expect(mayRetainInCLanguageAware("PyCapsule_SetDestructor", true));
    try std.testing.expect(mayRetainInCLanguageAware("signal", true));
    try std.testing.expect(mayRetainInCLanguageAware("SDL_SetCallback", true));
    try std.testing.expect(!mayRetainInCLanguageAware("malloc", true));
    try std.testing.expect(!mayRetainInCLanguageAware("free", true));
}

test "isRegisterNativesPattern - JNI callback" {
    try std.testing.expect(isRegisterNativesPattern("RegisterNatives"));
    try std.testing.expect(isRegisterNativesPattern("RegisterNativesHook"));
    try std.testing.expect(!isRegisterNativesPattern("malloc"));
}

test "isPthreadCreatePattern - thread callback" {
    try std.testing.expect(isPthreadCreatePattern("pthread_create"));
    try std.testing.expect(!isPthreadCreatePattern("pthread_join"));
}

test "isCallbackReceiver - known receivers" {
    try std.testing.expect(isCallbackReceiver("RegisterNatives"));
    try std.testing.expect(isCallbackReceiver("SetCallback"));
    try std.testing.expect(isCallbackReceiver("pthread_create"));
    try std.testing.expect(isCallbackReceiver("signal"));
    try std.testing.expect(isCallbackReceiver("SDL_SetEventCallback"));
    try std.testing.expect(!isCallbackReceiver("malloc"));
    try std.testing.expect(!isCallbackReceiver("free"));
}

test "isCgoGlueByPattern - cgo glue detection" {
    try std.testing.expect(isCgoGlueByPattern("_cgo_123abc"));
    try std.testing.expect(isCgoGlueByPattern("crosscall2"));
    try std.testing.expect(isCgoGlueByPattern("runtime.cgocall"));
    try std.testing.expect(isCgoGlueByPattern("_Cfunc_abc123"));
    try std.testing.expect(isCgoGlueByPattern("_cgo_gotypes_init"));
    try std.testing.expect(!isCgoGlueByPattern("my_c_function"));
    try std.testing.expect(!isCgoGlueByPattern("cgo_wrapper_user"));
    try std.testing.expect(!isCgoGlueByPattern("printf"));
}

test "validate_callback_signature - JNI patterns" {
    try std.testing.expect(validate_callback_signature("RegisterNatives", "JNINativeMethod*"));
    try std.testing.expect(validate_callback_signature("RegisterNatives", "void*"));
    try std.testing.expect(!validate_callback_signature("RegisterNatives", "int"));
    try std.testing.expect(validate_callback_signature("pthread_create", "void*"));
    try std.testing.expect(validate_callback_signature("signal", "void, int"));
    try std.testing.expect(!validate_callback_signature("signal", "int, int"));
}

test "validate_callback_signature - boundary cases" {
    try std.testing.expect(!validate_callback_signature("pthread_create", ""));
    try std.testing.expect(!validate_callback_signature("unknown_func", "void*"));
    try std.testing.expect(validate_callback_signature("atexit", "void*"));
    try std.testing.expect(validate_callback_signature("qsort", "void*"));
    try std.testing.expect(validate_callback_signature("bsearch", "void*"));
    try std.testing.expect(validate_callback_signature("pthread_key_create", "void*"));
    try std.testing.expect(validate_callback_signature("sigaction", "void, int"));
    try std.testing.expect(validate_callback_signature("on_exit", "void, int"));
}

// R8.0-P1-8: isCgoBoundary strict "C." prefix matching (no FP on AC.BMethod etc.)
test "isCgoBoundary - strict C. prefix matching" {
    try std.testing.expect(isCgoBoundary("C.add"));
    try std.testing.expect(isCgoBoundary("C.malloc"));
    try std.testing.expect(isCgoBoundary("main.C.function"));

    try std.testing.expect(!isCgoBoundary("AC.BMethod"));
    try std.testing.expect(!isCgoBoundary("MC.function"));
    try std.testing.expect(!isCgoBoundary("OCSocket"));
    try std.testing.expect(!isCgoBoundary("MAC.address"));
    try std.testing.expect(!isCgoBoundary("myFunction_C_helper"));
}
