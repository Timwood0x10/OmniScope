const std = @import("std");
const types = @import("types.zig");

pub const jni_functions = [_]types.FunctionSemantics{
    .{ .pattern = "JNI_OnLoad", .match_type = .exact, .kind = .jni, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "JNI library load - verify VM version, register native methods" },
    .{ .pattern = "JNI_OnUnload", .match_type = .exact, .kind = .jni, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "JNI library unload - cleanup global references" },
    .{ .pattern = "FindClass", .match_type = .exact, .kind = .jni, .severity = .high, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Find Java class - returns local ref, check for NULL" },
    .{ .pattern = "GetMethodID", .match_type = .exact, .kind = .jni, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Get JNI method ID - returns NULL on error, cache for performance" },
    .{ .pattern = "GetStaticMethodID", .match_type = .exact, .kind = .jni, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Get JNI static method ID - returns NULL on error" },
    .{ .pattern = "GetFieldID", .match_type = .exact, .kind = .jni, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Get JNI field ID - returns NULL on error" },
    .{ .pattern = "GetStaticFieldID", .match_type = .exact, .kind = .jni, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Get JNI static field ID - returns NULL on error" },
    .{ .pattern = "CallVoidMethod", .match_type = .exact, .kind = .jni, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Call JNI void method - check ExceptionCheck after call" },
    .{ .pattern = "CallIntMethod", .match_type = .exact, .kind = .jni, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Call JNI int method - check ExceptionCheck after call" },
    .{ .pattern = "CallObjectMethod", .match_type = .exact, .kind = .jni, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = false, .requires_taint_check = false, .description = "Call JNI object method - returns local ref, check ExceptionCheck" },
    .{ .pattern = "CallStaticVoidMethod", .match_type = .exact, .kind = .jni, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Call JNI static void method - check ExceptionCheck after call" },
    .{ .pattern = "NewStringUTF", .match_type = .exact, .kind = .jni, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Create Java String from UTF-8 - returns local ref, check for NULL" },
    .{ .pattern = "GetStringUTFChars", .match_type = .exact, .kind = .jni, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Get UTF-8 chars from Java String - must ReleaseStringUTFChars" },
    .{ .pattern = "ReleaseStringUTFChars", .match_type = .exact, .kind = .jni, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Release UTF-8 chars - paired with GetStringUTFChars" },
    .{ .pattern = "NewByteArray", .match_type = .exact, .kind = .jni, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Create Java byte array - returns local ref, check for NULL" },
    .{ .pattern = "GetByteArrayElements", .match_type = .exact, .kind = .jni, .severity = .medium, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Get byte array elements - must ReleaseByteArrayElements" },
    .{ .pattern = "ReleaseByteArrayElements", .match_type = .exact, .kind = .jni, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Release byte array elements - paired with GetByteArrayElements" },
    .{ .pattern = "NewGlobalRef", .match_type = .exact, .kind = .jni, .severity = .high, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Create global ref - must DeleteGlobalRef to avoid leak" },
    .{ .pattern = "DeleteGlobalRef", .match_type = .exact, .kind = .jni, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Delete global ref - paired with NewGlobalRef, use-after-free if used after" },
    .{ .pattern = "NewLocalRef", .match_type = .exact, .kind = .jni, .severity = .medium, .consumes_ownership = false, .transfers_ownership = true, .requires_null_check = true, .requires_taint_check = false, .description = "Create local ref - auto-freed when native method returns" },
    .{ .pattern = "DeleteLocalRef", .match_type = .exact, .kind = .jni, .severity = .medium, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Delete local ref - optional, auto-freed anyway" },
    .{ .pattern = "AttachCurrentThread", .match_type = .exact, .kind = .jni, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Attach thread to JVM - must DetachCurrentThread on exit" },
    .{ .pattern = "DetachCurrentThread", .match_type = .exact, .kind = .jni, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Detach thread from JVM - paired with AttachCurrentThread" },
    .{ .pattern = "RegisterNatives", .match_type = .exact, .kind = .jni, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = true, .requires_taint_check = false, .description = "Register native methods - signature mismatch causes crashes" },
    .{ .pattern = "ExceptionCheck", .match_type = .exact, .kind = .jni, .severity = .high, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Check for pending exception - must be called after JNI calls" },
    .{ .pattern = "ExceptionDescribe", .match_type = .exact, .kind = .jni, .severity = .low, .consumes_ownership = false, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Print exception description - debugging aid" },
    .{ .pattern = "ExceptionClear", .match_type = .exact, .kind = .jni, .severity = .high, .consumes_ownership = true, .transfers_ownership = false, .requires_null_check = false, .requires_taint_check = false, .description = "Clear pending exception - must be called before new JNI calls" },
};

test "jni_reg: function count" {
    try std.testing.expectEqual(@as(usize, 27), jni_functions.len);
}

test "jni_reg: key functions exist" {
    inline for (jni_functions) |entry| {
        const name = @as([]const u8, entry.pattern);
        if (std.mem.eql(u8, name, "NewGlobalRef")) {
            try std.testing.expectEqual(@as(bool, true), entry.transfers_ownership);
            try std.testing.expectEqual(@as(bool, false), entry.consumes_ownership);
        }
        if (std.mem.eql(u8, name, "DeleteGlobalRef")) {
            try std.testing.expectEqual(@as(bool, true), entry.consumes_ownership);
            try std.testing.expectEqual(@as(bool, false), entry.transfers_ownership);
        }
        if (std.mem.eql(u8, name, "JNI_OnLoad")) {
            try std.testing.expectEqual(types.Severity.high, entry.severity);
        }
    }
}
