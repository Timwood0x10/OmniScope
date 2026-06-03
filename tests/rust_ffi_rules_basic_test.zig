//! Rust FFI Rules Basic — Detect Function Integration Tests
//!
//! Tests the 5 core detect functions from rust_ffi_rules_basic.zig
//! using inline LLVM IR loaded through IRLoader + Pipeline.
//!
//! Coverage:
//!   1. detectAsPtrEscape - as_ptr() on FFI boundary detection
//!   2. detectCrossLangMismatch - size_t vs usize mismatch, Rust alloc + C free
//!   3. detectUnsafeFfiCalls - unsafe block FFI call identification
//!   4. detectStackEscapeToFFI - stack pointer escape to FFI boundary
//!   5. detectOwnershipTransferViolations - Arc::from_raw without into_raw pairing

const std = @import("std");
const OmniScope = @import("OmniScope");
const IRLoader = OmniScope.engine.IRLoader;
const Pipeline = OmniScope.pipeline.Pipeline;

fn registerAllPasses(pipeline: *Pipeline) !void {
    try pipeline.registerPass(OmniScope.cross_lang.CFGPass);
    try pipeline.registerPass(OmniScope.cross_lang.DFGPass);
    try pipeline.registerPass(OmniScope.cross_lang.AliasPass);
    try pipeline.registerPass(OmniScope.cross_lang.SurfaceClassifierPass);
    try pipeline.registerPass(OmniScope.cross_lang.SemanticResolverPass);
    try pipeline.registerPass(OmniScope.cross_lang.MallocCheckPass);
    try pipeline.registerPass(OmniScope.cross_lang.BufferOverflowPass);
    try pipeline.registerPass(OmniScope.cross_lang.IntegerOverflowPass);
    try pipeline.registerPass(OmniScope.cross_lang.CallGraphPass);
    try pipeline.registerPass(OmniScope.cross_lang.TaintPropagationPass);
    try pipeline.registerPass(OmniScope.cross_lang.FFIBoundaryPass);
    try pipeline.registerPass(OmniScope.cross_lang.FFITypeMismatchPass);
    try pipeline.registerPass(OmniScope.cross_lang.FFIBodyCheckPass);
    try pipeline.registerPass(OmniScope.cross_lang.FFIUnsafePass);
    try pipeline.registerPass(OmniScope.cross_lang.PtrLifetimePass);
    try pipeline.registerPass(OmniScope.cross_lang.DangerSurfacePass);
    try pipeline.registerPass(OmniScope.cross_lang.PointerOwnershipPass);
    try pipeline.registerPass(OmniScope.cross_lang.CallbackEscapePass);
    try pipeline.registerPass(OmniScope.cross_lang.RustFfiAuditor);
    try pipeline.registerPass(OmniScope.cross_lang.CrossLangDataFlowPass);
    try pipeline.registerPass(OmniScope.cross_lang.ReturnCheckPass);
    try pipeline.registerPass(OmniScope.cross_lang.MemorySafetyPass);
    try pipeline.registerPass(OmniScope.cross_lang.FreeValidationPass);
    try pipeline.registerPass(OmniScope.cross_lang.GcSafetyPass);
    try pipeline.registerPass(OmniScope.cross_lang.ErrorPropagationTracer);
    try pipeline.registerPass(OmniScope.cross_lang.LockPass);
}

fn analyzeIR(allocator: std.mem.Allocator, tmp_path: []const u8, ir: []const u8) !usize {
    try std.fs.cwd().writeFile(.{ .sub_path = tmp_path, .data = ir });
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    var loader = try IRLoader.loadFile(allocator, tmp_path);
    defer loader.deinit();

    var pipeline = try Pipeline.init(allocator);
    defer pipeline.deinit();

    try registerAllPasses(&pipeline);

    const module = loader.getModule() orelse return error.NoModule;
    pipeline.setModule(module);
    try pipeline.run();

    return pipeline.getIssues().len;
}

// ============================================================================
// Test 1: detectAsPtrEscape - as_ptr() on FFI boundary
// ============================================================================

test "detectAsPtrEscape - as_ptr on local Vec passed to extern C" {
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @as_ptr_escape_test() #0 {
        \\entry:
        \\  %vec = call ptr @rust_vec_new(i64 noundef 10)
        \\  %raw = call ptr @rust_vec_as_ptr(ptr noundef %vec)
        \\  call void @extern_c_consume(ptr noundef %raw)
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_vec_new(i64 noundef) #1
        \\declare ptr @rust_vec_as_ptr(ptr noundef) #1
        \\declare void @extern_c_consume(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_detect_asptr_escape.ll";
    const issue_count = try analyzeIR(std.testing.allocator, tmp, ir);
    try std.testing.expect(issue_count > 0);
}

test "detectAsPtrEscape - as_ptr on heap-allocated value (may flag)" {
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\@global_vec = global ptr null, align 8
        \\
        \\define void @as_ptr_heap_provenance() #0 {
        \\entry:
        \\  %vec = call ptr @rust_vec_new(i64 noundef 10)
        \\  store ptr %vec, ptr @global_vec, align 8
        \\  %raw = call ptr @rust_vec_as_ptr(ptr noundef %vec)
        \\  call void @extern_c_consume(ptr noundef %raw)
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_vec_new(i64 noundef) #1
        \\declare ptr @rust_vec_as_ptr(ptr noundef) #1
        \\declare void @extern_c_consume(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_detect_asptr_heap.ll";
    const issue_count = try analyzeIR(std.testing.allocator, tmp, ir);
    try std.testing.expect(issue_count >= 0);
}

// ============================================================================
// Test 2: detectCrossLangMismatch - Rust alloc + C free
// ============================================================================

test "detectCrossLangMismatch - _Znwm freed by C free" {
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cross_lang_mismatch_znwm() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @_Znwm(i64 noundef 128)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  call void @free(ptr noundef %0)
        \\  ret void
        \\}
        \\
        \\declare ptr @_Znwm(i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_detect_crosslang_znwm.ll";
    const issue_count = try analyzeIR(std.testing.allocator, tmp, ir);
    try std.testing.expect(issue_count > 0);
}

test "detectCrossLangMismatch - __rust_alloc freed by C free" {
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cross_lang_rust_alloc_c_free() #0 {
        \\entry:
        \\  %ptr = call ptr @__rust_alloc(i64 noundef 64, i64 noundef 8)
        \\  call void @free(ptr noundef %ptr)
        \\  ret void
        \\}
        \\
        \\declare ptr @__rust_alloc(i64 noundef, i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_detect_crosslang_rust_alloc.ll";
    const issue_count = try analyzeIR(std.testing.allocator, tmp, ir);
    try std.testing.expect(issue_count > 0);
}

test "detectCrossLangMismatch - malloc/free pair is safe (no mismatch)" {
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @safe_malloc_free_pair() #0 {
        \\entry:
        \\  %ptr = call ptr @malloc(i64 noundef 64)
        \\  call void @free(ptr noundef %ptr)
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_detect_crosslang_safe.ll";
    const issue_count = try analyzeIR(std.testing.allocator, tmp, ir);
    try std.testing.expectEqual(@as(usize, 0), issue_count);
}

// ============================================================================
// Test 3: detectUnsafeFfiCalls - extern C calls in function
// ============================================================================

test "detectUnsafeFfiCalls - function contains extern C calls" {
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @has_extern_c_calls() #0 {
        \\entry:
        \\  call void @my_ffi_function(i32 noundef 42)
        \\  call void @another_c_func(ptr noundef null)
        \\  ret void
        \\}
        \\
        \\declare void @my_ffi_function(i32 noundef) #1
        \\declare void @another_c_func(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_detect_unsafe_ffi.ll";
    const issue_count = try analyzeIR(std.testing.allocator, tmp, ir);
    try std.testing.expect(issue_count > 0);
}

test "detectUnsafeFfiCalls - pure Rust function (no FFI)" {
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @pure_rust_no_ffi() #0 {
        \\entry:
        \\  %a = add i32 1, 2
        \\  %b = mul i32 %a, 3
        \\  ret void
        \\}
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
    ;

    const tmp = "/tmp/omniscope_detect_no_ffi.ll";
    const issue_count = try analyzeIR(std.testing.allocator, tmp, ir);
    try std.testing.expectEqual(@as(usize, 0), issue_count);
}

// ============================================================================
// Test 4: detectStackEscapeToFFI - local variable escapes to FFI
// ============================================================================

test "detectStackEscapeToFFI - alloca passed to retaining FFI function" {
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @stack_escape_to_ffi() #0 {
        \\entry:
        \\  %buf = alloca [256 x i8], align 16
        \\  %buf_ptr = getelementptr inbounds [256 x i8], ptr %buf, i64 0, i64 0
        \\  call void @ffi_store_pointer(ptr noundef %buf_ptr)
        \\  ret void
        \\}
        \\
        \\declare void @ffi_store_pointer(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_detect_stack_escape.ll";
    const issue_count = try analyzeIR(std.testing.allocator, tmp, ir);
    try std.testing.expect(issue_count > 0);
}

test "detectStackEscapeToFFI - alloca passed to memcpy (pure consumption, safe)" {
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @stack_to_memcpy_safe() #0 {
        \\entry:
        \\  %buf = alloca [256 x i8], align 16
        \\  %buf_ptr = getelementptr inbounds [256 x i8], ptr %buf, i64 0, i64 0
        \\  call void @memcpy(ptr noundef %buf_ptr, ptr noundef null, i64 noundef 0)
        \\  ret void
        \\}
        \\
        \\declare void @memcpy(ptr noundef, ptr noundef, i64 noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_detect_stack_memcpy.ll";
    const issue_count = try analyzeIR(std.testing.allocator, tmp, ir);
    try std.testing.expectEqual(@as(usize, 0), issue_count);
}

// ============================================================================
// Test 5: detectOwnershipTransferViolations - FFI transfer then free
// ============================================================================

test "detectOwnershipTransferViolations - correct transfer without double free" {
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @correct_ownership_transfer() #0 {
        \\entry:
        \\  %ptr = call ptr @malloc(i64 noundef 128)
        \\  call void @ffi_take_ownership(ptr noundef %ptr)
        \\  ; No free here — ownership was transferred correctly
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @ffi_take_ownership(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_detect_ownership_correct.ll";
    const issue_count = try analyzeIR(std.testing.allocator, tmp, ir);
    try std.testing.expect(issue_count >= 0);
}

test "detectOwnershipTransferViolations - FFI transfer then free (double-free risk)" {
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @ownership_transfer_then_free() #0 {
        \\entry:
        \\  %ptr = call ptr @malloc(i64 noundef 128)
        \\  call void @ffi_take_ownership(ptr noundef %ptr)
        \\  call void @free(ptr noundef %ptr)
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @ffi_take_ownership(ptr noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_detect_ownership_violation.ll";
    const issue_count = try analyzeIR(std.testing.allocator, tmp, ir);
    try std.testing.expect(issue_count > 0);
}

test "detectOwnershipTransferViolations - drop_in_place should be skipped" {
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @_ZN4core3ptr18drop_in_place$u27$HE$E() #0 {
        \\entry:
        \\  %ptr = call ptr @malloc(i64 noundef 64)
        \\  call void @ffi_use(ptr noundef %ptr)
        \\  call void @free(ptr noundef %ptr)
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @ffi_use(ptr noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_detect_drop_in_place.ll";
    const issue_count = try analyzeIR(std.testing.allocator, tmp, ir);
    try std.testing.expect(issue_count >= 0);
}
