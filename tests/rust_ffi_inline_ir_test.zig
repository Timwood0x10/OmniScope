//! Rust FFI Bugs and Compiler Noise Pattern Tests
//!
//! Tests cross-allocator mismatch bugs and Rust compiler noise patterns
//! using inline LLVM IR strings loaded through IRLoader.
//!
//! Part 1: Rust FFI Bugs (should be flagged by analysis passes)
//!   1. rust_alloc_c_free       - Rust allocator -> C free (cross-allocator mismatch)
//!   2. c_alloc_rust_dealloc    - C malloc -> Rust deallocator (reverse mismatch)
//!   3. box_into_raw_c_double_free - Box::into_raw + C free + Rust drop (double free)
//!   4. string_into_raw_leak    - String::into_raw with no from_raw (leak)
//!   5. vec_leak_realloc_mismatch - Rust vec + C realloc + C free (allocator mismatch)
//!   6. alias_escape_double_write - Two pointers to same Rust alloc, write through both
//!
//! Part 2: Rust Compiler Noise (should NOT be flagged)
//!   7. rust_drop_glue_noise    - __rust_alloc + __rust_dealloc (correct internal pairing)
//!   8. rust_panic_unwind_noise - Unwind path with rust_begin_unwind (compiler noise)
//!   9. rust_realloc_internal   - __rust_realloc on __rust_alloc'd memory (same family)
//!  10. safe_rust_ffi_no_bug    - malloc + free (correct C pairing, no cross-lang issue)

const std = @import("std");
const OmniScope = @import("OmniScope");
const IRLoader = OmniScope.engine.IRLoader;
const Pipeline = OmniScope.pipeline.Pipeline;
const SymbolGraph = OmniScope.cross_lang.SymbolGraph;

// ============================================================================
// Part 1: Rust FFI Bugs
// ============================================================================

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

test "Rust FFI bug: Rust alloc -> C free (cross-allocator mismatch)" {
    // Scenario: Rust's allocator produces a pointer, C's free() releases it.
    // This is a cross-allocator mismatch because Rust and C use different
    // allocator implementations (Rust's jemalloc/system vs C's glibc malloc).
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @rust_01_alloc_c_free() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @_RZN4alloc5alloc17h_allocate(i64 noundef 128)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  call void @free(ptr noundef %0)
        \\  ret void
        \\}
        \\
        \\declare ptr @_RZN4alloc5alloc17h_allocate(i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_alloc_c_free.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define (rust_01_alloc_c_free) + 2 declares (_RZN4alloc5alloc17h_allocate, free)
    try std.testing.expectEqual(@as(usize, 3), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_01_alloc_c_free") != null);
    try std.testing.expect(loader.getFunction("_RZN4alloc5alloc17h_allocate") != null);
    try std.testing.expect(loader.getFunction("free") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_alloc_c_free.ll", ir);
    try std.testing.expect(issue_count > 0);
}

test "Rust FFI bug: C alloc -> Rust dealloc (reverse mismatch)" {
    // Scenario: C's malloc() produces a pointer, Rust's deallocator releases it.
    // Reverse of test 1 — same cross-allocator mismatch from the other direction.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @c_alloc_rust_dealloc() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @malloc(i64 noundef 128)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  call void @_RZN4alloc5alloc17h_deallocate(ptr noundef %0, i64 noundef 128, i64 noundef 8)
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @_RZN4alloc5alloc17h_deallocate(ptr noundef, i64 noundef, i64 noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_c_alloc_rust_dealloc.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 2 declares (malloc, _RZN4alloc5alloc17h_deallocate)
    try std.testing.expectEqual(@as(usize, 3), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("c_alloc_rust_dealloc") != null);
    try std.testing.expect(loader.getFunction("malloc") != null);
    try std.testing.expect(loader.getFunction("_RZN4alloc5alloc17h_deallocate") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_c_alloc_rust_dealloc.ll", ir);
    try std.testing.expect(issue_count > 0);
}

test "Rust FFI bug: Box::into_raw then C free then Rust drop (double free)" {
    // Scenario: Box::into_raw() transfers ownership to a raw pointer stored in
    // a global. C code calls free() on it, then Rust code calls drop on the same
    // pointer — both attempt to free the same allocation.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\@global_box_ptr = global ptr null, align 8
        \\
        \\define void @box_into_raw_c_double_free() #0 {
        \\entry:
        \\  %box = call ptr @rust_box_new(i64 noundef 64)
        \\  store ptr %box, ptr @global_box_ptr, align 8
        \\  %0 = load ptr, ptr @global_box_ptr, align 8
        \\  call void @free(ptr noundef %0)
        \\  %1 = load ptr, ptr @global_box_ptr, align 8
        \\  call void @rust_box_drop(ptr noundef %1)
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_box_new(i64 noundef) #1
        \\declare void @rust_box_drop(ptr noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_box_into_raw_double_free.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 3 declares (rust_box_new, rust_box_drop, free)
    try std.testing.expectEqual(@as(usize, 4), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("box_into_raw_c_double_free") != null);
    try std.testing.expect(loader.getFunction("rust_box_new") != null);
    try std.testing.expect(loader.getFunction("rust_box_drop") != null);
    try std.testing.expect(loader.getFunction("free") != null);
    // Global should be visible through the module
    try std.testing.expect(loader.getModule() != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_box_into_raw_double_free.ll", ir);
    try std.testing.expect(issue_count > 0);
}

test "Rust FFI bug: String::into_raw with no from_raw (memory leak)" {
    // Scenario: Rust String is converted to a raw pointer via into_raw(),
    // but neither free() nor rust_string_from_raw() is ever called.
    // The raw pointer is abandoned — a memory leak.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\@.str = private unnamed_addr constant [6 x i8] c"hello\00", align 1
        \\
        \\define void @string_into_raw_leak() #0 {
        \\entry:
        \\  %s = call ptr @rust_string_new(ptr noundef @.str, i64 noundef 5)
        \\  %raw = call ptr @rust_string_into_raw(ptr noundef %s)
        \\  ; raw pointer is never freed or passed back to rust_string_from_raw
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_string_new(ptr noundef, i64 noundef) #1
        \\declare ptr @rust_string_into_raw(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_string_into_raw_leak.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 2 declares (rust_string_new, rust_string_into_raw)
    try std.testing.expectEqual(@as(usize, 3), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("string_into_raw_leak") != null);
    try std.testing.expect(loader.getFunction("rust_string_new") != null);
    try std.testing.expect(loader.getFunction("rust_string_into_raw") != null);
    // free should NOT be in the module — it was never declared or called
    try std.testing.expect(loader.getFunction("free") == null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_string_into_raw_leak.ll", ir);
    try std.testing.expect(issue_count > 0);
}

test "Rust FFI bug: Vec leak + C realloc + C free (allocator mismatch)" {
    // Scenario: Rust's vec_leak() returns a pointer from Rust's allocator.
    // C's realloc() attempts to resize it (wrong allocator!), then C's free()
    // releases the result (also wrong allocator!). Double mismatch.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @vec_leak_realloc_mismatch() #0 {
        \\entry:
        \\  %v = call ptr @rust_vec_leak(i64 noundef 10, i64 noundef 4)
        \\  %reallocated = call ptr @realloc(ptr noundef %v, i64 noundef 256)
        \\  call void @free(ptr noundef %reallocated)
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_vec_leak(i64 noundef, i64 noundef) #1
        \\declare ptr @realloc(ptr noundef, i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_vec_leak_realloc_mismatch.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 3 declares (rust_vec_leak, realloc, free)
    try std.testing.expectEqual(@as(usize, 4), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("vec_leak_realloc_mismatch") != null);
    try std.testing.expect(loader.getFunction("rust_vec_leak") != null);
    try std.testing.expect(loader.getFunction("realloc") != null);
    try std.testing.expect(loader.getFunction("free") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_vec_leak_realloc_mismatch.ll", ir);
    try std.testing.expect(issue_count > 0);
}

test "Rust FFI bug: alias escape with double write (aliasing violation)" {
    // Scenario: A single Rust allocation is aliased through two pointers.
    // Both pointers write to the same memory, violating Rust's aliasing
    // guarantees (only one &mut T may exist at a time).
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @alias_escape_double_write() #0 {
        \\entry:
        \\  %p1 = alloca ptr, align 8
        \\  %p2 = alloca ptr, align 8
        \\  %alloc = call ptr @_RZN4alloc5alloc17h_allocate(i64 noundef 256)
        \\  store ptr %alloc, ptr %p1, align 8
        \\  %0 = load ptr, ptr %p1, align 8
        \\  store ptr %0, ptr %p2, align 8
        \\  ; Write through p1
        \\  %1 = load ptr, ptr %p1, align 8
        \\  store i32 42, ptr %1, align 4
        \\  ; Write through p2 — same memory location!
        \\  %2 = load ptr, ptr %p2, align 8
        \\  store i32 99, ptr %2, align 4
        \\  ret void
        \\}
        \\
        \\declare ptr @_RZN4alloc5alloc17h_allocate(i64 noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_alias_escape_double_write.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 1 declare (_RZN4alloc5alloc17h_allocate)
    try std.testing.expectEqual(@as(usize, 2), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("alias_escape_double_write") != null);
    try std.testing.expect(loader.getFunction("_RZN4alloc5alloc17h_allocate") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_alias_escape_double_write.ll", ir);
    try std.testing.expect(issue_count > 0);
}

// ============================================================================
// Part 2: Rust Compiler Noise (should NOT be flagged as bugs)
// ============================================================================

test "Rust noise: drop glue with correct internal alloc/dealloc pairing" {
    // Scenario: A function uses __rust_alloc and __rust_dealloc — both from
    // Rust's internal allocator. This is correct pairing and should NOT be
    // flagged as a cross-allocator bug. This pattern appears in compiler-
    // generated drop glue.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @rust_drop_glue_noise() #0 {
        \\entry:
        \\  %ptr = call ptr @__rust_alloc(i64 noundef 128, i64 noundef 8)
        \\  call void @__rust_dealloc(ptr noundef %ptr, i64 noundef 128, i64 noundef 8)
        \\  ret void
        \\}
        \\
        \\declare ptr @__rust_alloc(i64 noundef, i64 noundef) #1
        \\declare void @__rust_dealloc(ptr noundef, i64 noundef, i64 noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_drop_glue_noise.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 2 declares (__rust_alloc, __rust_dealloc)
    try std.testing.expectEqual(@as(usize, 3), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_drop_glue_noise") != null);
    try std.testing.expect(loader.getFunction("__rust_alloc") != null);
    try std.testing.expect(loader.getFunction("__rust_dealloc") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_drop_glue_noise.ll", ir);
    try std.testing.expect(issue_count == 0);
}

test "Rust noise: panic unwind path with rust_begin_unwind" {
    // Scenario: A function allocates with __rust_alloc, checks for null,
    // and branches to an unwind path that calls rust_begin_unwind. The
    // normal path properly deallocates. Unwind paths are compiler-generated
    // noise and should not be flagged as bugs.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @rust_panic_unwind_noise() #0 {
        \\entry:
        \\  %ptr = call ptr @__rust_alloc(i64 noundef 64, i64 noundef 8)
        \\  %is_null = icmp eq ptr %ptr, null
        \\  br i1 %is_null, label %unwind, label %normal
        \\
        \\normal:
        \\  call void @__rust_dealloc(ptr noundef %ptr, i64 noundef 64, i64 noundef 8)
        \\  ret void
        \\
        \\unwind:
        \\  call void @rust_begin_unwind(ptr noundef null)
        \\  unreachable
        \\}
        \\
        \\declare ptr @__rust_alloc(i64 noundef, i64 noundef) #1
        \\declare void @__rust_dealloc(ptr noundef, i64 noundef, i64 noundef) #1
        \\declare void @rust_begin_unwind(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_panic_unwind_noise.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 3 declares (__rust_alloc, __rust_dealloc, rust_begin_unwind)
    try std.testing.expectEqual(@as(usize, 4), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_panic_unwind_noise") != null);
    try std.testing.expect(loader.getFunction("__rust_alloc") != null);
    try std.testing.expect(loader.getFunction("__rust_dealloc") != null);
    try std.testing.expect(loader.getFunction("rust_begin_unwind") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_panic_unwind_noise.ll", ir);
    try std.testing.expect(issue_count == 0);
}

test "Rust noise: __rust_realloc on __rust_alloc'd memory (same allocator family)" {
    // Scenario: Memory allocated with __rust_alloc is resized with
    // __rust_realloc and freed with __rust_dealloc. All three belong to
    // Rust's internal allocator family — this is NOT a cross-allocator bug.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @rust_realloc_internal() #0 {
        \\entry:
        \\  %ptr = call ptr @__rust_alloc(i64 noundef 128, i64 noundef 8)
        \\  %new_ptr = call ptr @__rust_realloc(ptr noundef %ptr, i64 noundef 128, i64 noundef 8, i64 noundef 256)
        \\  call void @__rust_dealloc(ptr noundef %new_ptr, i64 noundef 256, i64 noundef 8)
        \\  ret void
        \\}
        \\
        \\declare ptr @__rust_alloc(i64 noundef, i64 noundef) #1
        \\declare void @__rust_dealloc(ptr noundef, i64 noundef, i64 noundef) #1
        \\declare ptr @__rust_realloc(ptr noundef, i64 noundef, i64 noundef, i64 noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_realloc_internal.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 3 declares (__rust_alloc, __rust_dealloc, __rust_realloc)
    try std.testing.expectEqual(@as(usize, 4), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_realloc_internal") != null);
    try std.testing.expect(loader.getFunction("__rust_alloc") != null);
    try std.testing.expect(loader.getFunction("__rust_dealloc") != null);
    try std.testing.expect(loader.getFunction("__rust_realloc") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_realloc_internal.ll", ir);
    try std.testing.expect(issue_count == 0);
}

test "Rust noise: safe FFI with malloc -> free (correct C pairing, no bug)" {
    // Scenario: A function uses C's malloc() and free() — both from the same
    // allocator. There is no cross-language mismatch. This is a safe FFI
    // pattern that should NOT be flagged.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @safe_rust_ffi_no_bug() #0 {
        \\entry:
        \\  %ptr = call ptr @malloc(i64 noundef 128)
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

    const tmp = "/tmp/omniscope_safe_rust_ffi_no_bug.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 2 declares (malloc, free)
    try std.testing.expectEqual(@as(usize, 3), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("safe_rust_ffi_no_bug") != null);
    try std.testing.expect(loader.getFunction("malloc") != null);
    try std.testing.expect(loader.getFunction("free") != null);
    // No Rust allocator functions should be present
    try std.testing.expect(loader.getFunction("__rust_alloc") == null);
    try std.testing.expect(loader.getFunction("_RZN4alloc5alloc17h_allocate") == null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_safe_rust_ffi_no_bug.ll", ir);
    try std.testing.expect(issue_count == 0);
}

// ============================================================================
// Part 3: Additional Noise Patterns (should NOT be flagged as bugs)
// ============================================================================

test "Rust noise: Box new + use + drop (correct ownership lifecycle)" {
    // Scenario: rust_box_new allocates a Box, the caller writes into it, then
    // rust_box_drop is called to free it. This is the standard Rust ownership
    // lifecycle — alloc, use, drop — and should NOT be flagged as a bug.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @rust_box_new_drop_correct() #0 {
        \\entry:
        \\  %box = call ptr @rust_box_new(i64 noundef 64)
        \\  store i32 42, ptr %box, align 4
        \\  call void @rust_box_drop(ptr noundef %box)
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_box_new(i64 noundef) #1
        \\declare void @rust_box_drop(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_test_11.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 2 declares (rust_box_new, rust_box_drop)
    try std.testing.expectEqual(@as(usize, 3), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_box_new_drop_correct") != null);
    try std.testing.expect(loader.getFunction("rust_box_new") != null);
    try std.testing.expect(loader.getFunction("rust_box_drop") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_test_11.ll", ir);
    try std.testing.expect(issue_count == 0);
}

test "Rust noise: Arc clone + release cycle (correct refcount pattern)" {
    // Scenario: An Arc is created, cloned to get a second reference, then both
    // references are released (each calling rust_arc_release). The refcount goes
    // from 1 → 2 → 1 → 0. This is correct Arc usage and NOT a bug.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @rust_arc_clone_release_cycle() #0 {
        \\entry:
        \\  %arc = call ptr @rust_box_new(i64 noundef 64)
        \\  %clone = call ptr @rust_arc_clone(ptr noundef %arc)
        \\  call void @rust_arc_release(ptr noundef %clone)
        \\  call void @rust_arc_release(ptr noundef %arc)
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_box_new(i64 noundef) #1
        \\declare ptr @rust_arc_clone(ptr noundef) #1
        \\declare void @rust_arc_release(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_test_12.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 3 declares (rust_box_new, rust_arc_clone, rust_arc_release)
    try std.testing.expectEqual(@as(usize, 4), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_arc_clone_release_cycle") != null);
    try std.testing.expect(loader.getFunction("rust_box_new") != null);
    try std.testing.expect(loader.getFunction("rust_arc_clone") != null);
    try std.testing.expect(loader.getFunction("rust_arc_release") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_test_12.ll", ir);
    try std.testing.expect(issue_count == 0);
}

test "Rust noise: Vec push + pop + drop (correct Vec lifecycle)" {
    // Scenario: A Vec is created with capacity, an element is pushed, popped
    // back out, and then the Vec is dropped. This is a complete, correct Vec
    // lifecycle and should NOT be flagged as a bug.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @rust_vec_push_pop_correct() #0 {
        \\entry:
        \\  %v = call ptr @rust_vec_with_capacity(i64 noundef 10, i64 noundef 4)
        \\  call void @rust_vec_push(ptr noundef %v, i32 noundef 42)
        \\  %val = call i32 @rust_vec_pop(ptr noundef %v)
        \\  call void @rust_vec_drop(ptr noundef %v)
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_vec_with_capacity(i64 noundef, i64 noundef) #1
        \\declare void @rust_vec_push(ptr noundef, i32 noundef) #1
        \\declare i32 @rust_vec_pop(ptr noundef) #1
        \\declare void @rust_vec_drop(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_test_13.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 4 declares (rust_vec_with_capacity, rust_vec_push, rust_vec_pop, rust_vec_drop)
    try std.testing.expectEqual(@as(usize, 5), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_vec_push_pop_correct") != null);
    try std.testing.expect(loader.getFunction("rust_vec_with_capacity") != null);
    try std.testing.expect(loader.getFunction("rust_vec_push") != null);
    try std.testing.expect(loader.getFunction("rust_vec_pop") != null);
    try std.testing.expect(loader.getFunction("rust_vec_drop") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_test_13.ll", ir);
    try std.testing.expect(issue_count == 0);
}

test "Rust noise: Cow clone then free (Cow owns cloned data)" {
    // Scenario: rust_cow_clone produces an owned copy of the data. The caller
    // uses it and then calls free() on it. The cloned Cow owns its data, so
    // free() is the correct way to release the C-allocated copy. NOT a bug.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @rust_cow_clone_free() #0 {
        \\entry:
        \\  %cow = call ptr @rust_cow_clone(ptr noundef null)
        \\  store i32 7, ptr %cow, align 4
        \\  call void @free(ptr noundef %cow)
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_cow_clone(ptr noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_test_14.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 2 declares (rust_cow_clone, free)
    try std.testing.expectEqual(@as(usize, 3), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_cow_clone_free") != null);
    try std.testing.expect(loader.getFunction("rust_cow_clone") != null);
    try std.testing.expect(loader.getFunction("free") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_test_14.ll", ir);
    try std.testing.expect(issue_count == 0);
}

test "Rust noise: HashMap insert + remove + drop (correct HashMap lifecycle)" {
    // Scenario: A HashMap is created, a key-value pair is inserted, the pair is
    // removed, and the map is dropped. This is a complete, correct HashMap
    // lifecycle and should NOT be flagged as a bug.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @rust_hashmap_insert_remove() #0 {
        \\entry:
        \\  %map = call ptr @rust_hashmap_new(i64 noundef 16)
        \\  call void @rust_hashmap_insert(ptr noundef %map, i64 noundef 1, i64 noundef 100)
        \\  call void @rust_hashmap_remove(ptr noundef %map, i64 noundef 1)
        \\  call void @rust_hashmap_drop(ptr noundef %map)
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_hashmap_new(i64 noundef) #1
        \\declare void @rust_hashmap_insert(ptr noundef, i64 noundef, i64 noundef) #1
        \\declare void @rust_hashmap_remove(ptr noundef, i64 noundef) #1
        \\declare void @rust_hashmap_drop(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_test_15.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 4 declares (rust_hashmap_new, rust_hashmap_insert, rust_hashmap_remove, rust_hashmap_drop)
    try std.testing.expectEqual(@as(usize, 5), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_hashmap_insert_remove") != null);
    try std.testing.expect(loader.getFunction("rust_hashmap_new") != null);
    try std.testing.expect(loader.getFunction("rust_hashmap_insert") != null);
    try std.testing.expect(loader.getFunction("rust_hashmap_remove") != null);
    try std.testing.expect(loader.getFunction("rust_hashmap_drop") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_test_15.ll", ir);
    try std.testing.expect(issue_count == 0);
}

test "Rust noise: Mutex lock + unlock + drop (correct Mutex usage)" {
    // Scenario: A Mutex is created, locked, the inner value is accessed, then
    // unlocked, and finally the Mutex is dropped. This is the standard Mutex
    // guard pattern and should NOT be flagged as a bug.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @rust_mutex_lock_unlock() #0 {
        \\entry:
        \\  %m = call ptr @rust_mutex_new(i64 noundef 4)
        \\  call void @rust_mutex_lock(ptr noundef %m)
        \\  store i32 99, ptr %m, align 4
        \\  call void @rust_mutex_unlock(ptr noundef %m)
        \\  call void @rust_mutex_drop(ptr noundef %m)
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_mutex_new(i64 noundef) #1
        \\declare void @rust_mutex_lock(ptr noundef) #1
        \\declare void @rust_mutex_unlock(ptr noundef) #1
        \\declare void @rust_mutex_drop(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_test_16.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 4 declares (rust_mutex_new, rust_mutex_lock, rust_mutex_unlock, rust_mutex_drop)
    try std.testing.expectEqual(@as(usize, 5), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_mutex_lock_unlock") != null);
    try std.testing.expect(loader.getFunction("rust_mutex_new") != null);
    try std.testing.expect(loader.getFunction("rust_mutex_lock") != null);
    try std.testing.expect(loader.getFunction("rust_mutex_unlock") != null);
    try std.testing.expect(loader.getFunction("rust_mutex_drop") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_test_16.ll", ir);
    try std.testing.expect(issue_count == 0);
}

test "Rust noise: Channel send + recv + drop (correct channel lifecycle)" {
    // Scenario: A channel is created, a message is sent, received, and the
    // channel is dropped. This is a complete, correct channel lifecycle and
    // should NOT be flagged as a bug.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @rust_channel_send_recv_drop() #0 {
        \\entry:
        \\  %ch = call ptr @rust_channel_new(i64 noundef 64)
        \\  call void @rust_channel_send(ptr noundef %ch, i64 noundef 42)
        \\  %val = call i64 @rust_channel_recv(ptr noundef %ch)
        \\  call void @rust_channel_drop(ptr noundef %ch)
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_channel_new(i64 noundef) #1
        \\declare void @rust_channel_send(ptr noundef, i64 noundef) #1
        \\declare i64 @rust_channel_recv(ptr noundef) #1
        \\declare void @rust_channel_drop(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_test_17.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 4 declares (rust_channel_new, rust_channel_send, rust_channel_recv, rust_channel_drop)
    try std.testing.expectEqual(@as(usize, 5), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_channel_send_recv_drop") != null);
    try std.testing.expect(loader.getFunction("rust_channel_new") != null);
    try std.testing.expect(loader.getFunction("rust_channel_send") != null);
    try std.testing.expect(loader.getFunction("rust_channel_recv") != null);
    try std.testing.expect(loader.getFunction("rust_channel_drop") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_test_17.ll", ir);
    try std.testing.expect(issue_count == 0);
}

// ============================================================================
// Part 4: Real Bugs That MUST Trigger
// ============================================================================

test "Rust bug: Arc release without prior clone (refcount underflow)" {
    // Scenario: A Box is allocated, then rust_arc_release is called on it
    // without a prior rust_arc_clone. This decrements a refcount that was
    // never incremented, causing a refcount underflow and potential UAF.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @rust_arc_release_without_clone() #0 {
        \\entry:
        \\  %box = call ptr @rust_box_new(i64 noundef 64)
        \\  call void @rust_arc_release(ptr noundef %box)
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_box_new(i64 noundef) #1
        \\declare void @rust_arc_release(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_test_18.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 2 declares (rust_box_new, rust_arc_release)
    try std.testing.expectEqual(@as(usize, 3), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_arc_release_without_clone") != null);
    try std.testing.expect(loader.getFunction("rust_box_new") != null);
    try std.testing.expect(loader.getFunction("rust_arc_release") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_test_18.ll", ir);
    try std.testing.expect(issue_count > 0);
}

test "Rust bug: double Box drop (double free)" {
    // Scenario: A Box is allocated, then rust_box_drop is called twice on the
    // same pointer. The second drop frees already-freed memory — a classic
    // double free.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @rust_double_box_drop() #0 {
        \\entry:
        \\  %box = call ptr @rust_box_new(i64 noundef 64)
        \\  call void @rust_box_drop(ptr noundef %box)
        \\  call void @rust_box_drop(ptr noundef %box)
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_box_new(i64 noundef) #1
        \\declare void @rust_box_drop(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_test_19.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 2 declares (rust_box_new, rust_box_drop)
    try std.testing.expectEqual(@as(usize, 3), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_double_box_drop") != null);
    try std.testing.expect(loader.getFunction("rust_box_new") != null);
    try std.testing.expect(loader.getFunction("rust_box_drop") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_test_19.ll", ir);
    try std.testing.expect(issue_count > 0);
}

test "Rust bug: Vec leak then C free on inner pointer (allocator mismatch)" {
    // Scenario: rust_vec_with_capacity creates a Vec with Rust's allocator.
    // rust_vec_as_ptr extracts the raw data pointer. free() from C's allocator
    // is called on that pointer — cross-allocator mismatch. The Vec still
    // thinks it owns the memory too, so this is also a use-after-free risk.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @rust_vec_leak_then_c_free() #0 {
        \\entry:
        \\  %v = call ptr @rust_vec_with_capacity(i64 noundef 10, i64 noundef 4)
        \\  %ptr = call ptr @rust_vec_as_ptr(ptr noundef %v)
        \\  call void @free(ptr noundef %ptr)
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_vec_with_capacity(i64 noundef, i64 noundef) #1
        \\declare ptr @rust_vec_as_ptr(ptr noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_test_20.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 3 declares (rust_vec_with_capacity, rust_vec_as_ptr, free)
    try std.testing.expectEqual(@as(usize, 4), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_vec_leak_then_c_free") != null);
    try std.testing.expect(loader.getFunction("rust_vec_with_capacity") != null);
    try std.testing.expect(loader.getFunction("rust_vec_as_ptr") != null);
    try std.testing.expect(loader.getFunction("free") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_test_20.ll", ir);
    try std.testing.expect(issue_count > 0);
}

test "Rust bug: poisoned mutex access (lock after panic unwind)" {
    // Scenario: Thread 1 creates a Mutex, locks it, then panics via
    // rust_begin_unwind (unreachable). Thread 2 reads the Mutex from a global,
    // locks it, and accesses the inner value. The Mutex is poisoned — the
    // inner value may be in an inconsistent state.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\@poisoned_mutex = global ptr null, align 8
        \\
        \\define void @thread1_poison() #0 {
        \\entry:
        \\  %m = call ptr @rust_mutex_new(i64 noundef 4)
        \\  store ptr %m, ptr @poisoned_mutex, align 8
        \\  call void @rust_mutex_lock(ptr noundef %m)
        \\  call void @rust_begin_unwind(ptr noundef null)
        \\  unreachable
        \\}
        \\
        \\define void @thread2_poisoned_access() #0 {
        \\entry:
        \\  %m = load ptr, ptr @poisoned_mutex, align 8
        \\  call void @rust_mutex_lock(ptr noundef %m)
        \\  %val = load i32, ptr %m, align 4
        \\  call void @rust_mutex_unlock(ptr noundef %m)
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_mutex_new(i64 noundef) #1
        \\declare void @rust_mutex_lock(ptr noundef) #1
        \\declare void @rust_mutex_unlock(ptr noundef) #1
        \\declare void @rust_begin_unwind(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_test_21.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 2 defines + 4 declares (rust_mutex_new, rust_mutex_lock, rust_mutex_unlock, rust_begin_unwind)
    try std.testing.expectEqual(@as(usize, 6), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("thread1_poison") != null);
    try std.testing.expect(loader.getFunction("thread2_poisoned_access") != null);
    try std.testing.expect(loader.getFunction("rust_mutex_new") != null);
    try std.testing.expect(loader.getFunction("rust_mutex_lock") != null);
    try std.testing.expect(loader.getFunction("rust_mutex_unlock") != null);
    try std.testing.expect(loader.getFunction("rust_begin_unwind") != null);
    try std.testing.expect(loader.getModule() != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_test_21.ll", ir);
    try std.testing.expect(issue_count > 0);
}

test "Rust bug: inttoptr to raw pointer then free (invalid free)" {
    // Scenario: An arbitrary integer is cast to a pointer via inttoptr, then
    // free() is called on it. The pointer never came from any allocator —
    // this is an invalid free that will crash or corrupt the heap.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @rust_raw_ptr_from_int_then_free() #0 {
        \\entry:
        \\  %ptr = inttoptr i64 268435456 to ptr
        \\  call void @free(ptr noundef %ptr)
        \\  ret void
        \\}
        \\
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_test_22.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 1 declare (free)
    try std.testing.expectEqual(@as(usize, 2), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_raw_ptr_from_int_then_free") != null);
    try std.testing.expect(loader.getFunction("free") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_test_22.ll", ir);
    try std.testing.expect(issue_count > 0);
}

// ============================================================================
// Part 5: False Negative Edge Cases (tricky, easy to miss)
// ============================================================================

test "Rust edge case: cross-allocator through helper function call chain" {
    // Scenario: A helper function @rust_helper_alloc calls @__rust_alloc and
    // returns the pointer. The main function calls the helper, then calls
    // free() on the result. The cross-allocator mismatch goes through an
    // intermediate function — tests if the tool can trace through call chains.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define ptr @rust_helper_alloc(i64 %size) #0 {
        \\entry:
        \\  %ptr = call ptr @__rust_alloc(i64 noundef %size, i64 noundef 8)
        \\  ret ptr %ptr
        \\}
        \\
        \\define void @rust_alloc_through_helper() #0 {
        \\entry:
        \\  %ptr = call ptr @rust_helper_alloc(i64 noundef 128)
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

    const tmp = "/tmp/omniscope_rust_test_23.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 2 defines + 2 declares (__rust_alloc, free)
    try std.testing.expectEqual(@as(usize, 4), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_helper_alloc") != null);
    try std.testing.expect(loader.getFunction("rust_alloc_through_helper") != null);
    try std.testing.expect(loader.getFunction("__rust_alloc") != null);
    try std.testing.expect(loader.getFunction("free") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_test_23.ll", ir);
    try std.testing.expect(issue_count > 0);
}

test "Rust edge case: conditional double free through both branches" {
    // Scenario: A Box is allocated, then a branch splits execution. Both the
    // then-branch and the else-branch call rust_box_drop on the same pointer.
    // At runtime only one path executes, but statically both paths contain the
    // drop. Tests if the tool handles branches correctly and does not miss the
    // double free just because it is on separate control flow paths.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @rust_conditional_double_free(i1 %cond) #0 {
        \\entry:
        \\  %box = call ptr @rust_box_new(i64 noundef 64)
        \\  br i1 %cond, label %then, label %else
        \\
        \\then:
        \\  call void @rust_box_drop(ptr noundef %box)
        \\  br label %merge
        \\
        \\else:
        \\  call void @rust_box_drop(ptr noundef %box)
        \\  br label %merge
        \\
        \\merge:
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_box_new(i64 noundef) #1
        \\declare void @rust_box_drop(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_test_24.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 2 declares (rust_box_new, rust_box_drop)
    try std.testing.expectEqual(@as(usize, 3), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_conditional_double_free") != null);
    try std.testing.expect(loader.getFunction("rust_box_new") != null);
    try std.testing.expect(loader.getFunction("rust_box_drop") != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_test_24.ll", ir);
    try std.testing.expect(issue_count > 0);
}

test "Rust edge case: alloc in loop then free all with C free (cross-allocator)" {
    // Scenario: A loop allocates memory with __rust_alloc each iteration and
    // stores the pointers in a global array. After the loop, a second loop
    // frees all pointers with C's free(). Every single allocation has a
    // cross-allocator mismatch — tests if the tool handles loop patterns.
    const ir =
        \\; ModuleID = 'test'
        \\source_filename = "test"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\@ptr_array = global [4 x ptr] zeroinitializer, align 8
        \\
        \\define void @rust_alloc_in_loop_free_after() #0 {
        \\entry:
        \\  br label %loop
        \\
        \\loop:
        \\  %i = phi i64 [ 0, %entry ], [ %i.next, %loop ]
        \\  %ptr = call ptr @__rust_alloc(i64 noundef 64, i64 noundef 8)
        \\  %gep = getelementptr inbounds [4 x ptr], ptr @ptr_array, i64 0, i64 %i
        \\  store ptr %ptr, ptr %gep, align 8
        \\  %i.next = add nuw nsw i64 %i, 1
        \\  %cmp = icmp ult i64 %i.next, 4
        \\  br i1 %cmp, label %loop, label %cleanup
        \\
        \\cleanup:
        \\  br label %free_loop
        \\
        \\free_loop:
        \\  %j = phi i64 [ 0, %cleanup ], [ %j.next, %free_loop ]
        \\  %gep2 = getelementptr inbounds [4 x ptr], ptr @ptr_array, i64 0, i64 %j
        \\  %p = load ptr, ptr %gep2, align 8
        \\  call void @free(ptr noundef %p)
        \\  %j.next = add nuw nsw i64 %j, 1
        \\  %cmp2 = icmp ult i64 %j.next, 4
        \\  br i1 %cmp2, label %free_loop, label %done
        \\
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @__rust_alloc(i64 noundef, i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { noinline nounwind optnone ssp uwtable(sync) }
        \\attributes #1 = { nounwind }
    ;

    const tmp = "/tmp/omniscope_rust_test_25.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    // 1 define + 2 declares (__rust_alloc, free)
    try std.testing.expectEqual(@as(usize, 3), loader.getFunctionCount());
    try std.testing.expect(loader.getFunction("rust_alloc_in_loop_free_after") != null);
    try std.testing.expect(loader.getFunction("__rust_alloc") != null);
    try std.testing.expect(loader.getFunction("free") != null);
    try std.testing.expect(loader.getModule() != null);

    const issue_count = try analyzeIR(std.testing.allocator, "/tmp/omniscope_rust_test_25.ll", ir);
    try std.testing.expect(issue_count > 0);
}

// ============================================================================
// Diagnostic Test: SymbolGraph cross-language call detection in rust_hash.ll
// ============================================================================

test "DIAG: SymbolGraph detects both calls in rust_hash.ll pattern" {
    const ir =
        \\; ModuleID = 'rust_hash_test'
        \\source_filename = "rust_hash_test"
        \\target datalayout = "e-m:o-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx11.0.0"
        \\
        \\define i32 @rust_hash_compute(ptr %data, i64 %len, ptr %out) {
        \\  %_result = tail call i32 @c_hash(ptr %data, i64 %len, ptr %out)
        \\  ret i32 0
        \\}
        \\
        \\define i32 @rust_fft_forward(ptr %real, ptr %imag, i64 %n) {
        \\  %3 = tail call i32 @c_fft_forward(ptr %real, ptr %imag, i64 %n)
        \\  ret i32 %3
        \\}
        \\
        \\declare i32 @c_hash(ptr, i64, ptr)
        \\declare i32 @c_fft_forward(ptr, ptr, i64)
    ;

    const tmp = "/tmp/omniscope_rust_hash_diag.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    const module = loader.getModule() orelse return error.NoModule;

    var graph = try SymbolGraph.build(std.testing.allocator, module.raw);
    defer graph.deinit();

    const cross_sites = graph.getCrossLangSites();

    // Both cross-language calls must be detected
    try std.testing.expectEqual(@as(usize, 2), cross_sites.len);

    var found_hash = false;
    var found_fft = false;
    for (cross_sites) |site| {
        if (std.mem.eql(u8, site.caller.name, "rust_hash_compute") and
            std.mem.eql(u8, site.callee.name, "c_hash"))
        {
            found_hash = true;
        }
        if (std.mem.eql(u8, site.caller.name, "rust_fft_forward") and
            std.mem.eql(u8, site.callee.name, "c_fft_forward"))
        {
            found_fft = true;
        }
    }

    try std.testing.expect(found_hash);
    try std.testing.expect(found_fft);
}
