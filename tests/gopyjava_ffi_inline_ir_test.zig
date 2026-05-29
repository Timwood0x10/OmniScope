//! Go CGO, Python C API, and Java JNI FFI Bug Tests
//!
//! Tests cross-language FFI vulnerability patterns using inline LLVM IR strings.
//! Each test writes valid LLVM IR to a temp .ll file, loads it via IRLoader
//! (which auto-converts .ll -> .bc via llvm-as), and verifies the module loads.
//!
//! Bug categories:
//!   - Go CGO (5 tests): cross-allocator, slice escape, callback UAF, string mutation
//!   - Python C API (5 tests): borrowed ref decref, new ref leak, steal ref misuse,
//!     decref-then-use, buffer not released
//!   - Java JNI (5 tests): global ref leak, string not released, local ref overflow,
//!     use-after-release, wrong free

const std = @import("std");
const OmniScope = @import("OmniScope");
const IRLoader = OmniScope.engine.IRLoader;

/// Write inline IR to a temp .ll file, load it, and return the loader.
/// Caller must call deinit() on the returned loader and clean up temp files.
fn loadInlineIR(allocator: std.mem.Allocator, tmp_path: []const u8, ir: []const u8) !IRLoader {
    try std.fs.cwd().writeFile(.{ .sub_path = tmp_path, .data = ir });
    return try IRLoader.loadFile(allocator, tmp_path);
}

// ============================================================================
// Go CGO Tests
// ============================================================================

test "Go CGO 01: _cgo_allocate -> free (cross-allocator)" {
    const ir =
        \\; ModuleID = 'go_cgo_01'
        \\source_filename = "go_cgo_01"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @go_01_go_alloc_c_free() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @_cgo_allocate(i32 noundef 128)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  call void @free(ptr noundef %0)
        \\  ret void
        \\}
        \\
        \\declare ptr @_cgo_allocate(i32 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_01.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_01.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("go_01_go_alloc_c_free") != null);
    try std.testing.expect(loader.getFunctionCount() >= 1);
}

test "Go CGO 02: malloc -> _cgo_free (reverse cross-allocator)" {
    const ir =
        \\; ModuleID = 'go_cgo_02'
        \\source_filename = "go_cgo_02"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @go_02_c_alloc_go_free() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @malloc(i64 noundef 256)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  call void @_cgo_free(ptr noundef %0)
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @_cgo_free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_02.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_02.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("go_02_c_alloc_go_free") != null);
}

test "Go CGO 03: slice.data escapes to C global (dangling pointer)" {
    const ir =
        \\; ModuleID = 'go_cgo_03'
        \\source_filename = "go_cgo_03"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\@escaped_ptr = global ptr null, align 8
        \\
        \\define void @go_03_go_slice_escape() #0 {
        \\entry:
        \\  %data = alloca [64 x i8], align 1
        \\  %data_ptr = getelementptr inbounds [64 x i8], ptr %data, i64 0, i64 0
        \\  ; Pass Go slice backing data to C function that stores it globally
        \\  call void @C_store_in_global(ptr noundef %data_ptr)
        \\  ; Function returns, stack data is invalid, but @escaped_ptr holds dangling ptr
        \\  ret void
        \\}
        \\
        \\declare void @C_store_in_global(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_03.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_03.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("go_03_go_slice_escape") != null);
}

test "Go CGO 04: callback ptr freed then invoked (UAF)" {
    const ir =
        \\; ModuleID = 'go_cgo_04'
        \\source_filename = "go_cgo_04"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @go_04_go_callback_use_after_free() #0 {
        \\entry:
        \\  %cb = alloca ptr, align 8
        \\  ; Allocate memory for a callback function pointer
        \\  %call = call ptr @malloc(i64 noundef 64)
        \\  store ptr %call, ptr %cb, align 8
        \\  ; Free the callback memory
        \\  %0 = load ptr, ptr %cb, align 8
        \\  call void @free(ptr noundef %0)
        \\  ; Use-after-free: invoke the freed callback pointer
        \\  %1 = load ptr, ptr %cb, align 8
        \\  call void %1()
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_04.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_04.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("go_04_go_callback_use_after_free") != null);
}

test "Go CGO 05: C mutates Go string data (immutability violation)" {
    const ir =
        \\; ModuleID = 'go_cgo_05'
        \\source_filename = "go_cgo_05"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @go_05_go_string_mutate(ptr noundef %str_data, i64 noundef %str_len) #0 {
        \\entry:
        \\  %str_data.addr = alloca ptr, align 8
        \\  %str_len.addr = alloca i64, align 8
        \\  store ptr %str_data, ptr %str_data.addr, align 8
        \\  store i64 %str_len, ptr %str_len.addr, align 8
        \\  ; Go string data pointer passed to C, C mutates the buffer
        \\  ; This violates Go's string immutability guarantee
        \\  %0 = load ptr, ptr %str_data.addr, align 8
        \\  %1 = load i64, ptr %str_len.addr, align 8
        \\  call void @C_mutate_buffer(ptr noundef %0, i64 noundef %1)
        \\  ret void
        \\}
        \\
        \\declare void @C_mutate_buffer(ptr noundef, i64 noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_05.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_05.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("go_05_go_string_mutate") != null);
}

// ============================================================================
// Python C API Tests
// ============================================================================

test "Python C API 06: borrowed ref from PyList_GetItem then Py_DECREF (refcount underflow)" {
    const ir =
        \\; ModuleID = 'python_cffi_06'
        \\source_filename = "python_cffi_06"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @py_06_borrowed_ref_decref(ptr noundef %list) #0 {
        \\entry:
        \\  %list.addr = alloca ptr, align 8
        \\  %item = alloca ptr, align 8
        \\  store ptr %list, ptr %list.addr, align 8
        \\  ; PyList_GetItem returns a BORROWED reference (no incref)
        \\  %0 = load ptr, ptr %list.addr, align 8
        \\  %call = call ptr @PyList_GetItem(ptr noundef %0, i64 noundef 0)
        \\  store ptr %call, ptr %item, align 8
        \\  ; Py_DECREF on a borrowed ref causes refcount underflow
        \\  %1 = load ptr, ptr %item, align 8
        \\  call void @Py_DECREF(ptr noundef %1)
        \\  ret void
        \\}
        \\
        \\declare ptr @PyList_GetItem(ptr noundef, i64 noundef) #1
        \\declare void @Py_DECREF(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_06.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_06.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("py_06_borrowed_ref_decref") != null);
}

test "Python C API 07: new ref from PyBytes_FromStringAndSize never decref (leak)" {
    const ir =
        \\; ModuleID = 'python_cffi_07'
        \\source_filename = "python_cffi_07"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @py_07_new_ref_leak(ptr noundef %data, i64 noundef %size) #0 {
        \\entry:
        \\  %data.addr = alloca ptr, align 8
        \\  %size.addr = alloca i64, align 8
        \\  %bytes = alloca ptr, align 8
        \\  store ptr %data, ptr %data.addr, align 8
        \\  store i64 %size, ptr %size.addr, align 8
        \\  ; PyBytes_FromStringAndSize returns a NEW reference
        \\  %0 = load ptr, ptr %data.addr, align 8
        \\  %1 = load i64, ptr %size.addr, align 8
        \\  %call = call ptr @PyBytes_FromStringAndSize(ptr noundef %0, i64 noundef %1)
        \\  store ptr %call, ptr %bytes, align 8
        \\  ; Never decref - reference count leak
        \\  ret void
        \\}
        \\
        \\declare ptr @PyBytes_FromStringAndSize(ptr noundef, i64 noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_07.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_07.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("py_07_new_ref_leak") != null);
}

test "Python C API 08: PyTuple_SetItem steals ref then use stolen ref (UAF)" {
    const ir =
        \\; ModuleID = 'python_cffi_08'
        \\source_filename = "python_cffi_08"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @py_08_steal_ref_misuse(ptr noundef %tuple, ptr noundef %item) #0 {
        \\entry:
        \\  %tuple.addr = alloca ptr, align 8
        \\  %item.addr = alloca ptr, align 8
        \\  store ptr %tuple, ptr %tuple.addr, align 8
        \\  store ptr %item, ptr %item.addr, align 8
        \\  ; PyTuple_SetItem STEALS the reference to %item
        \\  %0 = load ptr, ptr %tuple.addr, align 8
        \\  %1 = load ptr, ptr %item.addr, align 8
        \\  %call = call i32 @PyTuple_SetItem(ptr noundef %0, i64 noundef 0, ptr noundef %1)
        \\  ; Use-after-free: access stolen reference after PyTuple_SetItem took ownership
        \\  %2 = load ptr, ptr %item.addr, align 8
        \\  call void @Py_DECREF(ptr noundef %2)
        \\  ret void
        \\}
        \\
        \\declare i32 @PyTuple_SetItem(ptr noundef, i64 noundef, ptr noundef) #1
        \\declare void @Py_DECREF(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_08.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_08.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("py_08_steal_ref_misuse") != null);
}

test "Python C API 09: Py_DECREF then access object data (UAF)" {
    const ir =
        \\; ModuleID = 'python_cffi_09'
        \\source_filename = "python_cffi_09"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @py_09_decref_then_use(ptr noundef %obj) #0 {
        \\entry:
        \\  %obj.addr = alloca ptr, align 8
        \\  store ptr %obj, ptr %obj.addr, align 8
        \\  ; Decref first (may free the object)
        \\  %0 = load ptr, ptr %obj.addr, align 8
        \\  call void @Py_DECREF(ptr noundef %0)
        \\  ; Then use the object - use-after-free
        \\  %1 = load ptr, ptr %obj.addr, align 8
        \\  %call = call ptr @PyObject_Str(ptr noundef %1)
        \\  ret void
        \\}
        \\
        \\declare void @Py_DECREF(ptr noundef) #1
        \\declare ptr @PyObject_Str(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_09.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_09.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("py_09_decref_then_use") != null);
}

test "Python C API 10: PyObject_GetBuffer without PyBuffer_Release (resource leak)" {
    const ir =
        \\; ModuleID = 'python_cffi_10'
        \\source_filename = "python_cffi_10"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\%struct.Py_buffer = type { ptr, ptr, i64, i32, i32, i32, ptr, ptr, ptr, ptr }
        \\
        \\define i32 @py_10_buffer_not_released(ptr noundef %obj) #0 {
        \\entry:
        \\  %obj.addr = alloca ptr, align 8
        \\  %view = alloca %struct.Py_buffer, align 8
        \\  %retval = alloca i32, align 4
        \\  store ptr %obj, ptr %obj.addr, align 8
        \\  ; Acquire buffer (increments internal reference count)
        \\  %0 = load ptr, ptr %obj.addr, align 8
        \\  %call = call i32 @PyObject_GetBuffer(ptr noundef %0, ptr noundef %view, i32 noundef 0)
        \\  store i32 %call, ptr %retval, align 4
        \\  ; Use buffer data...
        \\  %buf_ptr = getelementptr inbounds %struct.Py_buffer, ptr %view, i32 0, i32 0
        \\  %1 = load ptr, ptr %buf_ptr, align 8
        \\  ; Never call PyBuffer_Release - resource leak
        \\  %2 = load i32, ptr %retval, align 4
        \\  ret i32 %2
        \\}
        \\
        \\declare i32 @PyObject_GetBuffer(ptr noundef, ptr noundef, i32 noundef) #1
        \\declare void @PyBuffer_Release(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_10.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_10.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("py_10_buffer_not_released") != null);
}

// ============================================================================
// Java JNI Tests
// ============================================================================

test "Java JNI 11: NewGlobalRef without DeleteGlobalRef (leak)" {
    const ir =
        \\; ModuleID = 'java_jni_11'
        \\source_filename = "java_jni_11"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @jni_11_global_ref_leak(ptr noundef %env) #0 {
        \\entry:
        \\  %env.addr = alloca ptr, align 8
        \\  %local_obj = alloca ptr, align 8
        \\  %global = alloca ptr, align 8
        \\  store ptr %env, ptr %env.addr, align 8
        \\  store ptr null, ptr %local_obj, align 8
        \\  ; Create a global reference (never released)
        \\  %0 = load ptr, ptr %env.addr, align 8
        \\  %1 = load ptr, ptr %local_obj, align 8
        \\  %call = call ptr @NewGlobalRef(ptr noundef %0, ptr noundef %1)
        \\  store ptr %call, ptr %global, align 8
        \\  ; Never call DeleteGlobalRef - global ref leak
        \\  ret void
        \\}
        \\
        \\declare ptr @NewGlobalRef(ptr noundef, ptr noundef) #1
        \\declare void @DeleteGlobalRef(ptr noundef, ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_11.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_11.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("jni_11_global_ref_leak") != null);
}

test "Java JNI 12: GetStringUTFChars without ReleaseStringUTFChars (leak)" {
    const ir =
        \\; ModuleID = 'java_jni_12'
        \\source_filename = "java_jni_12"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @jni_12_string_not_released(ptr noundef %env, ptr noundef %jstr) #0 {
        \\entry:
        \\  %env.addr = alloca ptr, align 8
        \\  %jstr.addr = alloca ptr, align 8
        \\  %native_str = alloca ptr, align 8
        \\  store ptr %env, ptr %env.addr, align 8
        \\  store ptr %jstr, ptr %jstr.addr, align 8
        \\  ; Get native UTF-8 string from JNI jstring
        \\  %0 = load ptr, ptr %env.addr, align 8
        \\  %1 = load ptr, ptr %jstr.addr, align 8
        \\  %call = call ptr @GetStringUTFChars(ptr noundef %0, ptr noundef %1, ptr noundef null)
        \\  store ptr %call, ptr %native_str, align 8
        \\  ; Use the string data...
        \\  ; Never call ReleaseStringUTFChars - native string leak
        \\  ret void
        \\}
        \\
        \\declare ptr @GetStringUTFChars(ptr noundef, ptr noundef, ptr noundef) #1
        \\declare void @ReleaseStringUTFChars(ptr noundef, ptr noundef, ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_12.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_12.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("jni_12_string_not_released") != null);
}

test "Java JNI 13: loop creating local refs without DeleteLocalRef (table overflow)" {
    const ir =
        \\; ModuleID = 'java_jni_13'
        \\source_filename = "java_jni_13"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @jni_13_local_ref_overflow(ptr noundef %env, ptr noundef %obj) #0 {
        \\entry:
        \\  %env.addr = alloca ptr, align 8
        \\  %obj.addr = alloca ptr, align 8
        \\  %i = alloca i32, align 4
        \\  store ptr %env, ptr %env.addr, align 8
        \\  store ptr %obj, ptr %obj.addr, align 8
        \\  store i32 0, ptr %i, align 4
        \\  br label %loop
        \\
        \\loop:
        \\  %0 = load i32, ptr %i, align 4
        \\  %cmp = icmp slt i32 %0, 10000
        \\  br i1 %cmp, label %body, label %exit
        \\
        \\body:
        \\  %1 = load ptr, ptr %env.addr, align 8
        \\  %2 = load ptr, ptr %obj.addr, align 8
        \\  ; Create local ref without ever deleting - JNI local ref table overflow
        \\  %call = call ptr @NewLocalRef(ptr noundef %1, ptr noundef %2)
        \\  %3 = load i32, ptr %i, align 4
        \\  %inc = add nsw i32 %3, 1
        \\  store i32 %inc, ptr %i, align 4
        \\  br label %loop
        \\
        \\exit:
        \\  ret void
        \\}
        \\
        \\declare ptr @NewLocalRef(ptr noundef, ptr noundef) #1
        \\declare void @DeleteLocalRef(ptr noundef, ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_13.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_13.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("jni_13_local_ref_overflow") != null);
}

test "Java JNI 14: ReleaseStringUTFChars then access string (UAF)" {
    const ir =
        \\; ModuleID = 'java_jni_14'
        \\source_filename = "java_jni_14"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @jni_14_use_after_release(ptr noundef %env, ptr noundef %jstr) #0 {
        \\entry:
        \\  %env.addr = alloca ptr, align 8
        \\  %jstr.addr = alloca ptr, align 8
        \\  %native_str = alloca ptr, align 8
        \\  store ptr %env, ptr %env.addr, align 8
        \\  store ptr %jstr, ptr %jstr.addr, align 8
        \\  ; Get native string
        \\  %0 = load ptr, ptr %env.addr, align 8
        \\  %1 = load ptr, ptr %jstr.addr, align 8
        \\  %call = call ptr @GetStringUTFChars(ptr noundef %0, ptr noundef %1, ptr noundef null)
        \\  store ptr %call, ptr %native_str, align 8
        \\  ; Release the native string
        \\  %2 = load ptr, ptr %env.addr, align 8
        \\  %3 = load ptr, ptr %jstr.addr, align 8
        \\  %4 = load ptr, ptr %native_str, align 8
        \\  call void @ReleaseStringUTFChars(ptr noundef %2, ptr noundef %3, ptr noundef %4)
        \\  ; Use-after-release: access the released native string
        \\  %5 = load ptr, ptr %native_str, align 8
        \\  %len = call i64 @strlen(ptr noundef %5)
        \\  ret void
        \\}
        \\
        \\declare ptr @GetStringUTFChars(ptr noundef, ptr noundef, ptr noundef) #1
        \\declare void @ReleaseStringUTFChars(ptr noundef, ptr noundef, ptr noundef) #1
        \\declare i64 @strlen(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_14.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_14.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("jni_14_use_after_release") != null);
}

test "Java JNI 15: JNI array elements freed with C free() instead of ReleaseByteArrayElements" {
    const ir =
        \\; ModuleID = 'java_jni_15'
        \\source_filename = "java_jni_15"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @jni_15_wrong_free(ptr noundef %env, ptr noundef %jarray) #0 {
        \\entry:
        \\  %env.addr = alloca ptr, align 8
        \\  %jarray.addr = alloca ptr, align 8
        \\  %elems = alloca ptr, align 8
        \\  store ptr %env, ptr %env.addr, align 8
        \\  store ptr %jarray, ptr %jarray.addr, align 8
        \\  ; Get byte array elements via JNI
        \\  %0 = load ptr, ptr %env.addr, align 8
        \\  %1 = load ptr, ptr %jarray.addr, align 8
        \\  %call = call ptr @GetByteArrayElements(ptr noundef %0, ptr noundef %1, ptr noundef null)
        \\  store ptr %call, ptr %elems, align 8
        \\  ; Wrong: use C free() instead of ReleaseByteArrayElements
        \\  ; This corrupts the JVM heap and skips JNI bookkeeping
        \\  %2 = load ptr, ptr %elems, align 8
        \\  call void @free(ptr noundef %2)
        \\  ret void
        \\}
        \\
        \\declare ptr @GetByteArrayElements(ptr noundef, ptr noundef, ptr noundef) #1
        \\declare void @ReleaseByteArrayElements(ptr noundef, ptr noundef, ptr noundef, i32 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_15.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_15.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("jni_15_wrong_free") != null);
}

// ============================================================================
// Go CGO Noise Tests (should NOT trigger)
// ============================================================================

test "Go CGO 16: correct _cgo_allocate -> use -> _cgo_free (NOT a bug)" {
    const ir =
        \\; ModuleID = 'go_cgo_16'
        \\source_filename = "go_cgo_16"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @go_16_cgo_correct_pair() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @_cgo_allocate(i32 noundef 64)
        \\  store ptr %call, ptr %ptr, align 8
        \\  ; Use the allocated memory
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  store i8 42, ptr %0, align 1
        \\  ; Correct: free with _cgo_free (matching allocator)
        \\  %1 = load ptr, ptr %ptr, align 8
        \\  call void @_cgo_free(ptr noundef %1)
        \\  ret void
        \\}
        \\
        \\declare ptr @_cgo_allocate(i32 noundef) #1
        \\declare void @_cgo_free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_16.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_16.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("go_16_cgo_correct_pair") != null);
}

test "Go CGO 17: correct malloc -> use -> free from Go (NOT a bug)" {
    const ir =
        \\; ModuleID = 'go_cgo_17'
        \\source_filename = "go_cgo_17"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @go_17_malloc_free_pair() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @malloc(i64 noundef 128)
        \\  store ptr %call, ptr %ptr, align 8
        \\  ; Use the allocated memory
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  store i8 99, ptr %0, align 1
        \\  ; Correct: C-allocated and C-freed
        \\  %1 = load ptr, ptr %ptr, align 8
        \\  call void @free(ptr noundef %1)
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_17.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_17.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("go_17_malloc_free_pair") != null);
}

test "Go CGO 18: pass ptr to C and back, then _cgo_free (NOT a bug)" {
    const ir =
        \\; ModuleID = 'go_cgo_18'
        \\source_filename = "go_cgo_18"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @go_18_pass_ptr_to_c_and_back() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @_cgo_allocate(i32 noundef 32)
        \\  store ptr %call, ptr %ptr, align 8
        \\  ; Pass ptr to C function, C returns it back
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  %call1 = call ptr @C_process_and_return(ptr noundef %0)
        \\  store ptr %call1, ptr %ptr, align 8
        \\  ; The ptr never escapes; Go frees with matching allocator
        \\  %1 = load ptr, ptr %ptr, align 8
        \\  call void @_cgo_free(ptr noundef %1)
        \\  ret void
        \\}
        \\
        \\declare ptr @_cgo_allocate(i32 noundef) #1
        \\declare void @_cgo_free(ptr noundef) #1
        \\declare ptr @C_process_and_return(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_18.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_18.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("go_18_pass_ptr_to_c_and_back") != null);
}

// ============================================================================
// Go CGO Real Bug Tests (MUST trigger)
// ============================================================================

test "Go CGO 19: double free via _cgo_allocate then _cgo_free twice (BUG)" {
    const ir =
        \\; ModuleID = 'go_cgo_19'
        \\source_filename = "go_cgo_19"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @go_19_double_free() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @_cgo_allocate(i32 noundef 64)
        \\  store ptr %call, ptr %ptr, align 8
        \\  ; First free - correct
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  call void @_cgo_free(ptr noundef %0)
        \\  ; Second free - double free bug
        \\  %1 = load ptr, ptr %ptr, align 8
        \\  call void @_cgo_free(ptr noundef %1)
        \\  ret void
        \\}
        \\
        \\declare ptr @_cgo_allocate(i32 noundef) #1
        \\declare void @_cgo_free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_19.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_19.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("go_19_double_free") != null);
}

test "Go CGO 20: slice data escapes to global then freed (BUG)" {
    const ir =
        \\; ModuleID = 'go_cgo_20'
        \\source_filename = "go_cgo_20"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\@g_stored_ptr = global ptr null, align 8
        \\
        \\define void @go_20_slice_data_to_global() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @_cgo_allocate(i32 noundef 256)
        \\  store ptr %call, ptr %ptr, align 8
        \\  ; Store ptr to global - escapes
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  store ptr %0, ptr @g_stored_ptr, align 8
        \\  ; Free the allocation
        \\  %1 = load ptr, ptr %ptr, align 8
        \\  call void @_cgo_free(ptr noundef %1)
        \\  ; @g_stored_ptr now holds a dangling pointer - use-after-free via global
        \\  ret void
        \\}
        \\
        \\declare ptr @_cgo_allocate(i32 noundef) #1
        \\declare void @_cgo_free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_20.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_20.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("go_20_slice_data_to_global") != null);
}

test "Go CGO 21: callback function ptr freed then called via global (BUG)" {
    const ir =
        \\; ModuleID = 'go_cgo_21'
        \\source_filename = "go_cgo_21"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\@g_callback = global ptr null, align 8
        \\
        \\define void @go_21_callback_freed_then_called() #0 {
        \\entry:
        \\  %cb = alloca ptr, align 8
        \\  %call = call ptr @_cgo_allocate(i32 noundef 64)
        \\  store ptr %call, ptr %cb, align 8
        \\  ; Store callback ptr to global
        \\  %0 = load ptr, ptr %cb, align 8
        \\  store ptr %0, ptr @g_callback, align 8
        \\  ; Free the callback memory
        \\  %1 = load ptr, ptr %cb, align 8
        \\  call void @_cgo_free(ptr noundef %1)
        \\  ; Load freed callback from global and invoke - classic callback UAF
        \\  %2 = load ptr, ptr @g_callback, align 8
        \\  call void %2()
        \\  ret void
        \\}
        \\
        \\declare ptr @_cgo_allocate(i32 noundef) #1
        \\declare void @_cgo_free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_21.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_21.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("go_21_callback_freed_then_called") != null);
}

// ============================================================================
// Python Noise Tests (should NOT trigger)
// ============================================================================

test "Python 22: correct INCREF on borrowed then DECREF (NOT a bug)" {
    const ir =
        \\; ModuleID = 'python_22'
        \\source_filename = "python_22"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @py_22_correct_incref_decref(ptr noundef %list) #0 {
        \\entry:
        \\  %list.addr = alloca ptr, align 8
        \\  %item = alloca ptr, align 8
        \\  store ptr %list, ptr %list.addr, align 8
        \\  ; PyList_GetItem returns a BORROWED reference
        \\  %0 = load ptr, ptr %list.addr, align 8
        \\  %call = call ptr @PyList_GetItem(ptr noundef %0, i64 noundef 0)
        \\  store ptr %call, ptr %item, align 8
        \\  ; INCREF to make it a new owned reference
        \\  %1 = load ptr, ptr %item, align 8
        \\  call void @Py_INCREF(ptr noundef %1)
        \\  ; Use the object...
        \\  %2 = load ptr, ptr %item, align 8
        \\  %str = call ptr @PyObject_Str(ptr noundef %2)
        \\  ; DECREF releases our owned reference - correct
        \\  %3 = load ptr, ptr %item, align 8
        \\  call void @Py_DECREF(ptr noundef %3)
        \\  ret void
        \\}
        \\
        \\declare ptr @PyList_GetItem(ptr noundef, i64 noundef) #1
        \\declare void @Py_INCREF(ptr noundef) #1
        \\declare void @Py_DECREF(ptr noundef) #1
        \\declare ptr @PyObject_Str(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_22.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_22.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("py_22_correct_incref_decref") != null);
}

test "Python 23: new ref from PyBytes_FromStringAndSize then DECREF (NOT a bug)" {
    const ir =
        \\; ModuleID = 'python_23'
        \\source_filename = "python_23"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @py_23_new_ref_then_decref(ptr noundef %data, i64 noundef %size) #0 {
        \\entry:
        \\  %data.addr = alloca ptr, align 8
        \\  %size.addr = alloca i64, align 8
        \\  %bytes = alloca ptr, align 8
        \\  store ptr %data, ptr %data.addr, align 8
        \\  store i64 %size, ptr %size.addr, align 8
        \\  ; PyBytes_FromStringAndSize returns a NEW reference
        \\  %0 = load ptr, ptr %data.addr, align 8
        \\  %1 = load i64, ptr %size.addr, align 8
        \\  %call = call ptr @PyBytes_FromStringAndSize(ptr noundef %0, i64 noundef %1)
        \\  store ptr %call, ptr %bytes, align 8
        \\  ; Use the bytes object...
        \\  %2 = load ptr, ptr %bytes, align 8
        \\  %len = call i64 @PyBytes_Size(ptr noundef %2)
        \\  ; Correct: DECREF the new reference
        \\  %3 = load ptr, ptr %bytes, align 8
        \\  call void @Py_DECREF(ptr noundef %3)
        \\  ret void
        \\}
        \\
        \\declare ptr @PyBytes_FromStringAndSize(ptr noundef, i64 noundef) #1
        \\declare i64 @PyBytes_Size(ptr noundef) #1
        \\declare void @Py_DECREF(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_23.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_23.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("py_23_new_ref_then_decref") != null);
}

test "Python 24: correct buffer get and release (NOT a bug)" {
    const ir =
        \\; ModuleID = 'python_24'
        \\source_filename = "python_24"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\%struct.Py_buffer = type { ptr, ptr, i64, i32, i32, i32, ptr, ptr, ptr, ptr }
        \\
        \\define i32 @py_24_buffer_get_and_release(ptr noundef %obj) #0 {
        \\entry:
        \\  %obj.addr = alloca ptr, align 8
        \\  %view = alloca %struct.Py_buffer, align 8
        \\  %retval = alloca i32, align 4
        \\  store ptr %obj, ptr %obj.addr, align 8
        \\  ; Acquire buffer
        \\  %0 = load ptr, ptr %obj.addr, align 8
        \\  %call = call i32 @PyObject_GetBuffer(ptr noundef %0, ptr noundef %view, i32 noundef 0)
        \\  store i32 %call, ptr %retval, align 4
        \\  ; Use buffer data
        \\  %buf_ptr = getelementptr inbounds %struct.Py_buffer, ptr %view, i32 0, i32 0
        \\  %1 = load ptr, ptr %buf_ptr, align 8
        \\  %2 = load i8, ptr %1, align 1
        \\  ; Correct: release the buffer
        \\  call void @PyBuffer_Release(ptr noundef %view)
        \\  %3 = load i32, ptr %retval, align 4
        \\  ret i32 %3
        \\}
        \\
        \\declare i32 @PyObject_GetBuffer(ptr noundef, ptr noundef, i32 noundef) #1
        \\declare void @PyBuffer_Release(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_24.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_24.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("py_24_buffer_get_and_release") != null);
}

// ============================================================================
// Python Real Bug Tests (MUST trigger)
// ============================================================================

test "Python 25: double DECREF on new ref (BUG)" {
    const ir =
        \\; ModuleID = 'python_25'
        \\source_filename = "python_25"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @py_25_double_decref(ptr noundef %data, i64 noundef %size) #0 {
        \\entry:
        \\  %data.addr = alloca ptr, align 8
        \\  %size.addr = alloca i64, align 8
        \\  %bytes = alloca ptr, align 8
        \\  store ptr %data, ptr %data.addr, align 8
        \\  store i64 %size, ptr %size.addr, align 8
        \\  ; PyBytes_FromStringAndSize returns a NEW reference
        \\  %0 = load ptr, ptr %data.addr, align 8
        \\  %1 = load i64, ptr %size.addr, align 8
        \\  %call = call ptr @PyBytes_FromStringAndSize(ptr noundef %0, i64 noundef %1)
        \\  store ptr %call, ptr %bytes, align 8
        \\  ; First DECREF - correct
        \\  %2 = load ptr, ptr %bytes, align 8
        \\  call void @Py_DECREF(ptr noundef %2)
        \\  ; Second DECREF - double release bug
        \\  %3 = load ptr, ptr %bytes, align 8
        \\  call void @Py_DECREF(ptr noundef %3)
        \\  ret void
        \\}
        \\
        \\declare ptr @PyBytes_FromStringAndSize(ptr noundef, i64 noundef) #1
        \\declare void @Py_DECREF(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_25.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_25.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("py_25_double_decref") != null);
}

test "Python 26: INCREF then PyTuple_SetItem steals ref then DECREF (BUG)" {
    const ir =
        \\; ModuleID = 'python_26'
        \\source_filename = "python_26"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @py_26_incref_steal_fail(ptr noundef %tuple, ptr noundef %item) #0 {
        \\entry:
        \\  %tuple.addr = alloca ptr, align 8
        \\  %item.addr = alloca ptr, align 8
        \\  store ptr %tuple, ptr %tuple.addr, align 8
        \\  store ptr %item, ptr %item.addr, align 8
        \\  ; INCREF to own a reference
        \\  %0 = load ptr, ptr %item.addr, align 8
        \\  call void @Py_INCREF(ptr noundef %0)
        \\  ; PyTuple_SetItem steals the reference
        \\  %1 = load ptr, ptr %tuple.addr, align 8
        \\  %2 = load ptr, ptr %item.addr, align 8
        \\  %call = call i32 @PyTuple_SetItem(ptr noundef %1, i64 noundef 0, ptr noundef %2)
        \\  ; Extra DECREF on stolen reference - over-release
        \\  %3 = load ptr, ptr %item.addr, align 8
        \\  call void @Py_DECREF(ptr noundef %3)
        \\  ret void
        \\}
        \\
        \\declare void @Py_INCREF(ptr noundef) #1
        \\declare i32 @PyTuple_SetItem(ptr noundef, i64 noundef, ptr noundef) #1
        \\declare void @Py_DECREF(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_26.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_26.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("py_26_incref_steal_fail") != null);
}

test "Python 27: DECREF on null pointer (BUG)" {
    const ir =
        \\; ModuleID = 'python_27'
        \\source_filename = "python_27"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @py_27_decref_null() #0 {
        \\entry:
        \\  %obj = alloca ptr, align 8
        \\  ; Load a null pointer
        \\  store ptr null, ptr %obj, align 8
        \\  ; Py_DECREF on null - null deref in refcount macro
        \\  %0 = load ptr, ptr %obj, align 8
        \\  call void @Py_DECREF(ptr noundef %0)
        \\  ret void
        \\}
        \\
        \\declare void @Py_DECREF(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_27.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_27.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("py_27_decref_null") != null);
}

// ============================================================================
// Java Noise Tests (should NOT trigger)
// ============================================================================

test "Java JNI 28: correct local ref lifecycle (NOT a bug)" {
    const ir =
        \\; ModuleID = 'java_jni_28'
        \\source_filename = "java_jni_28"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @jni_28_correct_local_ref(ptr noundef %env, ptr noundef %obj) #0 {
        \\entry:
        \\  %env.addr = alloca ptr, align 8
        \\  %obj.addr = alloca ptr, align 8
        \\  %local = alloca ptr, align 8
        \\  store ptr %env, ptr %env.addr, align 8
        \\  store ptr %obj, ptr %obj.addr, align 8
        \\  ; Create a local reference
        \\  %0 = load ptr, ptr %env.addr, align 8
        \\  %1 = load ptr, ptr %obj.addr, align 8
        \\  %call = call ptr @NewLocalRef(ptr noundef %0, ptr noundef %1)
        \\  store ptr %call, ptr %local, align 8
        \\  ; Use the local ref...
        \\  %2 = load ptr, ptr %env.addr, align 8
        \\  %3 = load ptr, ptr %local, align 8
        \\  %cls = call ptr @GetObjectClass(ptr noundef %2, ptr noundef %3)
        \\  ; Correct: delete the local ref
        \\  %4 = load ptr, ptr %env.addr, align 8
        \\  %5 = load ptr, ptr %local, align 8
        \\  call void @DeleteLocalRef(ptr noundef %4, ptr noundef %5)
        \\  ret void
        \\}
        \\
        \\declare ptr @NewLocalRef(ptr noundef, ptr noundef) #1
        \\declare ptr @GetObjectClass(ptr noundef, ptr noundef) #1
        \\declare void @DeleteLocalRef(ptr noundef, ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_28.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_28.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("jni_28_correct_local_ref") != null);
}

test "Java JNI 29: correct global ref lifecycle (NOT a bug)" {
    const ir =
        \\; ModuleID = 'java_jni_29'
        \\source_filename = "java_jni_29"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @jni_29_correct_global_ref(ptr noundef %env, ptr noundef %obj) #0 {
        \\entry:
        \\  %env.addr = alloca ptr, align 8
        \\  %obj.addr = alloca ptr, align 8
        \\  %global = alloca ptr, align 8
        \\  store ptr %env, ptr %env.addr, align 8
        \\  store ptr %obj, ptr %obj.addr, align 8
        \\  ; Create a global reference
        \\  %0 = load ptr, ptr %env.addr, align 8
        \\  %1 = load ptr, ptr %obj.addr, align 8
        \\  %call = call ptr @NewGlobalRef(ptr noundef %0, ptr noundef %1)
        \\  store ptr %call, ptr %global, align 8
        \\  ; Use the global ref...
        \\  %2 = load ptr, ptr %env.addr, align 8
        \\  %3 = load ptr, ptr %global, align 8
        \\  %cls = call ptr @GetObjectClass(ptr noundef %2, ptr noundef %3)
        \\  ; Correct: delete the global ref
        \\  %4 = load ptr, ptr %env.addr, align 8
        \\  %5 = load ptr, ptr %global, align 8
        \\  call void @DeleteGlobalRef(ptr noundef %4, ptr noundef %5)
        \\  ret void
        \\}
        \\
        \\declare ptr @NewGlobalRef(ptr noundef, ptr noundef) #1
        \\declare ptr @GetObjectClass(ptr noundef, ptr noundef) #1
        \\declare void @DeleteGlobalRef(ptr noundef, ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_29.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_29.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("jni_29_correct_global_ref") != null);
}

test "Java JNI 30: correct GetStringUTFChars then ReleaseStringUTFChars (NOT a bug)" {
    const ir =
        \\; ModuleID = 'java_jni_30'
        \\source_filename = "java_jni_30"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @jni_30_correct_string_release(ptr noundef %env, ptr noundef %jstr) #0 {
        \\entry:
        \\  %env.addr = alloca ptr, align 8
        \\  %jstr.addr = alloca ptr, align 8
        \\  %native_str = alloca ptr, align 8
        \\  store ptr %env, ptr %env.addr, align 8
        \\  store ptr %jstr, ptr %jstr.addr, align 8
        \\  ; Get native string
        \\  %0 = load ptr, ptr %env.addr, align 8
        \\  %1 = load ptr, ptr %jstr.addr, align 8
        \\  %call = call ptr @GetStringUTFChars(ptr noundef %0, ptr noundef %1, ptr noundef null)
        \\  store ptr %call, ptr %native_str, align 8
        \\  ; Use the string...
        \\  %2 = load ptr, ptr %native_str, align 8
        \\  %len = call i64 @strlen(ptr noundef %2)
        \\  ; Correct: release the string
        \\  %3 = load ptr, ptr %env.addr, align 8
        \\  %4 = load ptr, ptr %jstr.addr, align 8
        \\  %5 = load ptr, ptr %native_str, align 8
        \\  call void @ReleaseStringUTFChars(ptr noundef %3, ptr noundef %4, ptr noundef %5)
        \\  ret void
        \\}
        \\
        \\declare ptr @GetStringUTFChars(ptr noundef, ptr noundef, ptr noundef) #1
        \\declare void @ReleaseStringUTFChars(ptr noundef, ptr noundef, ptr noundef) #1
        \\declare i64 @strlen(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_30.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_30.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("jni_30_correct_string_release") != null);
}

// ============================================================================
// Java Real Bug Tests (MUST trigger)
// ============================================================================

test "Java JNI 31: double DeleteGlobalRef (BUG)" {
    const ir =
        \\; ModuleID = 'java_jni_31'
        \\source_filename = "java_jni_31"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @jni_31_double_delete_global(ptr noundef %env, ptr noundef %obj) #0 {
        \\entry:
        \\  %env.addr = alloca ptr, align 8
        \\  %obj.addr = alloca ptr, align 8
        \\  %global = alloca ptr, align 8
        \\  store ptr %env, ptr %env.addr, align 8
        \\  store ptr %obj, ptr %obj.addr, align 8
        \\  ; Create a global reference
        \\  %0 = load ptr, ptr %env.addr, align 8
        \\  %1 = load ptr, ptr %obj.addr, align 8
        \\  %call = call ptr @NewGlobalRef(ptr noundef %0, ptr noundef %1)
        \\  store ptr %call, ptr %global, align 8
        \\  ; First delete - correct
        \\  %2 = load ptr, ptr %env.addr, align 8
        \\  %3 = load ptr, ptr %global, align 8
        \\  call void @DeleteGlobalRef(ptr noundef %2, ptr noundef %3)
        \\  ; Second delete - double delete bug
        \\  %4 = load ptr, ptr %env.addr, align 8
        \\  %5 = load ptr, ptr %global, align 8
        \\  call void @DeleteGlobalRef(ptr noundef %4, ptr noundef %5)
        \\  ret void
        \\}
        \\
        \\declare ptr @NewGlobalRef(ptr noundef, ptr noundef) #1
        \\declare void @DeleteGlobalRef(ptr noundef, ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_31.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_31.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("jni_31_double_delete_global") != null);
}

test "Java JNI 32: use local ref after DeleteLocalRef (BUG)" {
    const ir =
        \\; ModuleID = 'java_jni_32'
        \\source_filename = "java_jni_32"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @jni_32_use_after_delete_local(ptr noundef %env) #0 {
        \\entry:
        \\  %env.addr = alloca ptr, align 8
        \\  %cls = alloca ptr, align 8
        \\  store ptr %env, ptr %env.addr, align 8
        \\  ; Find a class (returns local ref)
        \\  %0 = load ptr, ptr %env.addr, align 8
        \\  %call = call ptr @FindClass(ptr noundef %0, ptr noundef @.str_class)
        \\  store ptr %call, ptr %cls, align 8
        \\  ; Delete the local ref
        \\  %1 = load ptr, ptr %env.addr, align 8
        \\  %2 = load ptr, ptr %cls, align 8
        \\  call void @DeleteLocalRef(ptr noundef %1, ptr noundef %2)
        \\  ; Use-after-delete: call method on deleted ref
        \\  %3 = load ptr, ptr %env.addr, align 8
        \\  %4 = load ptr, ptr %cls, align 8
        \\  %mid = call ptr @GetMethodID(ptr noundef %3, ptr noundef %4, ptr noundef @.str_method, ptr noundef @.str_sig)
        \\  ret void
        \\}
        \\
        \\@.str_class = private unnamed_addr constant [6 x i8] c"class1", align 1
        \\@.str_method = private unnamed_addr constant [5 x i8] c"read\00", align 1
        \\@.str_sig = private unnamed_addr constant [2 x i8] c"()\00", align 1
        \\
        \\declare ptr @FindClass(ptr noundef, ptr noundef) #1
        \\declare void @DeleteLocalRef(ptr noundef, ptr noundef) #1
        \\declare ptr @GetMethodID(ptr noundef, ptr noundef, ptr noundef, ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_32.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_32.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("jni_32_use_after_delete_local") != null);
}

test "Java JNI 33: wrong release method - ReleaseStringUTFChars on byte array (BUG)" {
    const ir =
        \\; ModuleID = 'java_jni_33'
        \\source_filename = "java_jni_33"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @jni_33_wrong_release_method(ptr noundef %env, ptr noundef %jarray) #0 {
        \\entry:
        \\  %env.addr = alloca ptr, align 8
        \\  %jarray.addr = alloca ptr, align 8
        \\  %elems = alloca ptr, align 8
        \\  store ptr %env, ptr %env.addr, align 8
        \\  store ptr %jarray, ptr %jarray.addr, align 8
        \\  ; Get byte array elements (different from string)
        \\  %0 = load ptr, ptr %env.addr, align 8
        \\  %1 = load ptr, ptr %jarray.addr, align 8
        \\  %call = call ptr @GetByteArrayElements(ptr noundef %0, ptr noundef %1, ptr noundef null)
        \\  store ptr %call, ptr %elems, align 8
        \\  ; Wrong release function: ReleaseStringUTFChars instead of ReleaseByteArrayElements
        \\  ; Type mismatch in release method
        \\  %2 = load ptr, ptr %env.addr, align 8
        \\  %3 = load ptr, ptr %elems, align 8
        \\  call void @ReleaseStringUTFChars(ptr noundef %2, ptr noundef null, ptr noundef %3)
        \\  ret void
        \\}
        \\
        \\declare ptr @GetByteArrayElements(ptr noundef, ptr noundef, ptr noundef) #1
        \\declare void @ReleaseStringUTFChars(ptr noundef, ptr noundef, ptr noundef) #1
        \\declare void @ReleaseByteArrayElements(ptr noundef, ptr noundef, ptr noundef, i32 noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_33.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_33.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("jni_33_wrong_release_method") != null);
}

// ============================================================================
// False Negative Edge Case Tests
// ============================================================================

test "Python 34: DECREF through helper function after already decremented (BUG)" {
    const ir =
        \\; ModuleID = 'python_34'
        \\source_filename = "python_34"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\; Helper function that calls Py_DECREF
        \\define void @py_34_helper_decref(ptr noundef %obj) #0 {
        \\entry:
        \\  %obj.addr = alloca ptr, align 8
        \\  store ptr %obj, ptr %obj.addr, align 8
        \\  %0 = load ptr, ptr %obj.addr, align 8
        \\  call void @Py_DECREF(ptr noundef %0)
        \\  ret void
        \\}
        \\
        \\; Main function: decref, then calls helper which decrefs again
        \\define void @py_34_decref_through_helper(ptr noundef %data, i64 noundef %size) #0 {
        \\entry:
        \\  %data.addr = alloca ptr, align 8
        \\  %size.addr = alloca i64, align 8
        \\  %bytes = alloca ptr, align 8
        \\  store ptr %data, ptr %data.addr, align 8
        \\  store i64 %size, ptr %size.addr, align 8
        \\  ; Create new ref
        \\  %0 = load ptr, ptr %data.addr, align 8
        \\  %1 = load i64, ptr %size.addr, align 8
        \\  %call = call ptr @PyBytes_FromStringAndSize(ptr noundef %0, i64 noundef %1)
        \\  store ptr %call, ptr %bytes, align 8
        \\  ; First decref in main
        \\  %2 = load ptr, ptr %bytes, align 8
        \\  call void @Py_DECREF(ptr noundef %2)
        \\  ; Call helper which does another decref - tests call-chain tracking
        \\  %3 = load ptr, ptr %bytes, align 8
        \\  call void @py_34_helper_decref(ptr noundef %3)
        \\  ret void
        \\}
        \\
        \\declare ptr @PyBytes_FromStringAndSize(ptr noundef, i64 noundef) #1
        \\declare void @Py_DECREF(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_34.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_34.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("py_34_decref_through_helper") != null);
    try std.testing.expect(loader.getFunction("py_34_helper_decref") != null);
}

test "Go CGO 35: Go allocates via _cgo_allocate, C bridge frees (BUG)" {
    const ir =
        \\; ModuleID = 'go_cgo_35'
        \\source_filename = "go_cgo_35"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\; C bridge function that frees with C free()
        \\define void @c_bridge_free(ptr noundef %ptr) #0 {
        \\entry:
        \\  %ptr.addr = alloca ptr, align 8
        \\  store ptr %ptr, ptr %ptr.addr, align 8
        \\  %0 = load ptr, ptr %ptr.addr, align 8
        \\  call void @free(ptr noundef %0)
        \\  ret void
        \\}
        \\
        \\; Go function that allocates with _cgo_allocate, passes to C bridge
        \\define void @go_35_alloc_through_c_bridge() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @_cgo_allocate(i32 noundef 128)
        \\  store ptr %call, ptr %ptr, align 8
        \\  ; Pass to C bridge which frees with C free() - cross-allocator bug
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  call void @c_bridge_free(ptr noundef %0)
        \\  ret void
        \\}
        \\
        \\declare ptr @_cgo_allocate(i32 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_35.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_35.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("go_35_alloc_through_c_bridge") != null);
    try std.testing.expect(loader.getFunction("c_bridge_free") != null);
}

test "Java JNI 36: global ref created in func A, deleted in func B and func A (BUG)" {
    const ir =
        \\; ModuleID = 'java_jni_36'
        \\source_filename = "java_jni_36"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\; Function B: receives global ref and deletes it
        \\define void @jni_36_func_b_delete(ptr noundef %env, ptr noundef %global_ref) #0 {
        \\entry:
        \\  %env.addr = alloca ptr, align 8
        \\  %global_ref.addr = alloca ptr, align 8
        \\  store ptr %env, ptr %env.addr, align 8
        \\  store ptr %global_ref, ptr %global_ref.addr, align 8
        \\  ; Delete the global ref
        \\  %0 = load ptr, ptr %env.addr, align 8
        \\  %1 = load ptr, ptr %global_ref.addr, align 8
        \\  call void @DeleteGlobalRef(ptr noundef %0, ptr noundef %1)
        \\  ret void
        \\}
        \\
        \\; Function A: creates global ref, passes to B, then also deletes it
        \\define void @jni_36_ref_passed_between_functions(ptr noundef %env, ptr noundef %obj) #0 {
        \\entry:
        \\  %env.addr = alloca ptr, align 8
        \\  %obj.addr = alloca ptr, align 8
        \\  %global = alloca ptr, align 8
        \\  store ptr %env, ptr %env.addr, align 8
        \\  store ptr %obj, ptr %obj.addr, align 8
        \\  ; Create global reference
        \\  %0 = load ptr, ptr %env.addr, align 8
        \\  %1 = load ptr, ptr %obj.addr, align 8
        \\  %call = call ptr @NewGlobalRef(ptr noundef %0, ptr noundef %1)
        \\  store ptr %call, ptr %global, align 8
        \\  ; Pass to function B which deletes it
        \\  %2 = load ptr, ptr %env.addr, align 8
        \\  %3 = load ptr, ptr %global, align 8
        \\  call void @jni_36_func_b_delete(ptr noundef %2, ptr noundef %3)
        \\  ; Function A also deletes it - double delete across functions
        \\  %4 = load ptr, ptr %env.addr, align 8
        \\  %5 = load ptr, ptr %global, align 8
        \\  call void @DeleteGlobalRef(ptr noundef %4, ptr noundef %5)
        \\  ret void
        \\}
        \\
        \\declare ptr @NewGlobalRef(ptr noundef, ptr noundef) #1
        \\declare void @DeleteGlobalRef(ptr noundef, ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_gopyjava_test_36.ll";
    const tmp_bc = "/tmp/omniscope_gopyjava_test_36.bc";
    defer std.fs.cwd().deleteFile(tmp) catch {};
    defer std.fs.cwd().deleteFile(tmp_bc) catch {};

    var loader = try loadInlineIR(std.testing.allocator, tmp, ir);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("jni_36_ref_passed_between_functions") != null);
    try std.testing.expect(loader.getFunction("jni_36_func_b_delete") != null);
}
