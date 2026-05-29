//! C#/.NET, C++, Zig, and Cross-Language FFI Bug Tests
//!
//! Tests allocator mismatches, leaks, over-releases, and UAF patterns
//! using inline LLVM IR strings loaded via IRLoader.
//!
//! Each test writes a self-contained .ll file to /tmp, loads it through
//! the OmniScope IRLoader (which auto-converts .ll -> .bc via llvm-as),
//! and verifies the module loads successfully with expected functions.

const std = @import("std");
const OmniScope = @import("OmniScope");
const IRLoader = OmniScope.engine.IRLoader;

const TMP_BASE = "/tmp/omniscope_cscpp_ffi_inline_ir_test";

// ============================================================================
// C# / .NET Tests (4)
// ============================================================================

test "C#: Marshal_AllocHGlobal -> free (allocator mismatch)" {
    const ir =
        \\; ModuleID = 'cs_alloc_c_free'
        \\source_filename = "cs_alloc_c_free"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cs_01_csharp_alloc_c_free() #0 {
        \\  %1 = call ptr @Marshal_AllocHGlobal(i32 noundef 256)
        \\  %2 = icmp eq ptr %1, null
        \\  br i1 %2, label %null_bb, label %free_bb
        \\null_bb:
        \\  ret void
        \\free_bb:
        \\  call void @free(ptr noundef %1)
        \\  ret void
        \\}
        \\
        \\declare ptr @Marshal_AllocHGlobal(i32 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cs_alloc_c_free.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cs_01_csharp_alloc_c_free") != null);
    try std.testing.expect(loader.getFunction("Marshal_AllocHGlobal") != null);
    try std.testing.expect(loader.getFunction("free") != null);
}

test "C#: malloc -> Marshal_FreeHGlobal (reverse mismatch)" {
    const ir =
        \\; ModuleID = 'c_alloc_cs_free'
        \\source_filename = "c_alloc_cs_free"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cs_02_c_alloc_cs_free() #0 {
        \\  %1 = call ptr @malloc(i64 noundef 128)
        \\  %2 = icmp eq ptr %1, null
        \\  br i1 %2, label %null_bb, label %free_bb
        \\null_bb:
        \\  ret void
        \\free_bb:
        \\  call void @Marshal_FreeHGlobal(ptr noundef %1)
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @Marshal_FreeHGlobal(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_c_alloc_cs_free.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cs_02_c_alloc_cs_free") != null);
    try std.testing.expect(loader.getFunction("malloc") != null);
    try std.testing.expect(loader.getFunction("Marshal_FreeHGlobal") != null);
}

test "C#: CoTaskMemAlloc -> no free (leak)" {
    const ir =
        \\; ModuleID = 'cs_com_alloc_leak'
        \\source_filename = "cs_com_alloc_leak"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cs_03_com_alloc_leak() #0 {
        \\  %1 = call ptr @CoTaskMemAlloc(i64 noundef 512)
        \\  %2 = icmp eq ptr %1, null
        \\  br i1 %2, label %null_bb, label %use_bb
        \\null_bb:
        \\  ret void
        \\use_bb:
        \\  store i8 42, ptr %1, align 1
        \\  ret void
        \\}
        \\
        \\declare ptr @CoTaskMemAlloc(i64 noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cs_com_alloc_leak.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cs_03_com_alloc_leak") != null);
    try std.testing.expect(loader.getFunction("CoTaskMemAlloc") != null);
    // No CoTaskMemFree declared -- confirms leak pattern
    try std.testing.expect(loader.getFunction("CoTaskMemFree") == null);
}

test "C#: GCHandle_Alloc -> never GCHandle_Free (GC pin leak)" {
    const ir =
        \\; ModuleID = 'cs_gchandle_leak'
        \\source_filename = "cs_gchandle_leak"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cs_04_gchandle_leak(ptr noundef %obj) #0 {
        \\  %1 = call i32 @GCHandle_Alloc(ptr noundef %obj, i32 noundef 2)
        \\  %2 = icmp eq i32 %1, 0
        \\  br i1 %2, label %done, label %use
        \\done:
        \\  ret void
        \\use:
        \\  store i8 99, ptr %obj, align 1
        \\  ret void
        \\}
        \\
        \\declare i32 @GCHandle_Alloc(ptr noundef, i32 noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cs_gchandle_leak.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cs_04_gchandle_leak") != null);
    try std.testing.expect(loader.getFunction("GCHandle_Alloc") != null);
    // No GCHandle_Free declared -- confirms GC pin leak
    try std.testing.expect(loader.getFunction("GCHandle_Free") == null);
}

// ============================================================================
// C++ Tests (4)
// ============================================================================

test "C++: new[] -> delete (array/scalar mismatch)" {
    const ir =
        \\; ModuleID = 'cpp_new_delete_mismatch'
        \\source_filename = "cpp_new_delete_mismatch"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @_Z36cpp_bug_01_new_array_delete_mismatchv() #0 {
        \\entry:
        \\  %arr = call ptr @_Znam(i64 noundef 128)
        \\  %cmp = icmp eq ptr %arr, null
        \\  br i1 %cmp, label %done, label %del
        \\del:
        \\  call void @_ZdlPv(ptr noundef %arr)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @_Znam(i64 noundef) #1
        \\declare void @_ZdlPv(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cpp_new_delete_mismatch.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("_Z36cpp_bug_01_new_array_delete_mismatchv") != null);
    try std.testing.expect(loader.getFunction("_Znam") != null);
    try std.testing.expect(loader.getFunction("_ZdlPv") != null);
}

test "C++: operator new -> no delete (leak)" {
    const ir =
        \\; ModuleID = 'cpp_new_leak'
        \\source_filename = "cpp_new_leak"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cpp_02_new_leak() #0 {
        \\entry:
        \\  %obj = call ptr @_Znwm(i64 noundef 64)
        \\  %cmp = icmp eq ptr %obj, null
        \\  br i1 %cmp, label %done, label %use
        \\use:
        \\  store i64 42, ptr %obj, align 8
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @_Znwm(i64 noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cpp_new_leak.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cpp_02_new_leak") != null);
    try std.testing.expect(loader.getFunction("_Znwm") != null);
    // No delete declared -- confirms leak
    try std.testing.expect(loader.getFunction("_ZdlPv") == null);
}

test "C++: shared_ptr cycle (two mallocs referencing each other, no free)" {
    const ir =
        \\; ModuleID = 'cpp_shared_ptr_cycle'
        \\source_filename = "cpp_shared_ptr_cycle"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cpp_03_shared_ptr_cycle() #0 {
        \\entry:
        \\  %node_a = call ptr @malloc(i64 noundef 16)
        \\  %node_b = call ptr @malloc(i64 noundef 16)
        \\  %cmp_a = icmp eq ptr %node_a, null
        \\  br i1 %cmp_a, label %done, label %check_b
        \\check_b:
        \\  %cmp_b = icmp eq ptr %node_b, null
        \\  br i1 %cmp_b, label %done, label %link
        \\link:
        \\  store ptr %node_b, ptr %node_a, align 8
        \\  store ptr %node_a, ptr %node_b, align 8
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cpp_shared_ptr_cycle.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cpp_03_shared_ptr_cycle") != null);
    try std.testing.expect(loader.getFunction("malloc") != null);
    // No free declared -- confirms cycle leak
    try std.testing.expect(loader.getFunction("free") == null);
}

test "C++: placement new (malloc -> placement new -> free, safe pattern)" {
    const ir =
        \\; ModuleID = 'cpp_placement_new_mismatch'
        \\source_filename = "cpp_placement_new_mismatch"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cpp_04_placement_new(ptr noundef %buf) #0 {
        \\entry:
        \\  %mem = call ptr @malloc(i64 noundef 64)
        \\  %cmp = icmp eq ptr %mem, null
        \\  br i1 %cmp, label %done, label %construct
        \\construct:
        \\  store i64 7, ptr %mem, align 8
        \\  call void @free(ptr noundef %mem)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cpp_placement_new_mismatch.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cpp_04_placement_new") != null);
    try std.testing.expect(loader.getFunction("malloc") != null);
    try std.testing.expect(loader.getFunction("free") != null);
}

// ============================================================================
// Cross-Language Tests (4)
// ============================================================================

test "Cross-lang: rust_box_new -> free (Rust->C mismatch)" {
    const ir =
        \\; ModuleID = 'cross_rust_alloc_c_free'
        \\source_filename = "cross_rust_alloc_c_free"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @bug_rust_alloc_c_free() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @rust_box_new(i32 noundef 42)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  call void @free(ptr noundef %0)
        \\  ret void
        \\}
        \\
        \\declare ptr @rust_box_new(i32 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cross_rust_alloc_c_free.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("bug_rust_alloc_c_free") != null);
    try std.testing.expect(loader.getFunction("rust_box_new") != null);
    try std.testing.expect(loader.getFunction("free") != null);
}

test "Cross-lang: _cgo_allocate -> _RZN4alloc5alloc17h_deallocate (Go->Rust)" {
    const ir =
        \\; ModuleID = 'cross_go_alloc_rust_free'
        \\source_filename = "cross_go_alloc_rust_free"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @bug_go_alloc_rust_free() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @_cgo_allocate(i64 noundef 256)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  call void @_RZN4alloc5alloc17h_deallocate(ptr noundef %0, i64 noundef 256)
        \\  ret void
        \\}
        \\
        \\declare ptr @_cgo_allocate(i64 noundef) #1
        \\declare void @_RZN4alloc5alloc17h_deallocate(ptr noundef, i64 noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cross_go_alloc_rust_free.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("bug_go_alloc_rust_free") != null);
    try std.testing.expect(loader.getFunction("_cgo_allocate") != null);
    try std.testing.expect(loader.getFunction("_RZN4alloc5alloc17h_deallocate") != null);
}

test "Cross-lang: malloc -> PyMem_Free (C->Python)" {
    const ir =
        \\; ModuleID = 'cross_c_alloc_python_free'
        \\source_filename = "cross_c_alloc_python_free"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @bug_c_alloc_python_free() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @malloc(i64 noundef 1024)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  %cmp = icmp eq ptr %0, null
        \\  br i1 %cmp, label %done, label %free_bb
        \\free_bb:
        \\  call void @PyMem_Free(ptr noundef %0)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @PyMem_Free(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cross_c_alloc_python_free.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("bug_c_alloc_python_free") != null);
    try std.testing.expect(loader.getFunction("malloc") != null);
    try std.testing.expect(loader.getFunction("PyMem_Free") != null);
}

test "Cross-lang: Go alloc -> C passes to Rust -> Rust frees (triple chain)" {
    const ir =
        \\; ModuleID = 'cross_triple_chain'
        \\source_filename = "cross_triple_chain"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @triple_chain_go_c_rust() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %go_alloc = call ptr @_cgo_allocate(i64 noundef 512)
        \\  store ptr %go_alloc, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  call void @c_pass_to_rust(ptr noundef %0)
        \\  ret void
        \\}
        \\
        \\define void @c_pass_to_rust(ptr noundef %p) #0 {
        \\entry:
        \\  call void @_RZN4alloc5alloc17h_deallocate(ptr noundef %p, i64 noundef 512)
        \\  ret void
        \\}
        \\
        \\declare ptr @_cgo_allocate(i64 noundef) #1
        \\declare void @_RZN4alloc5alloc17h_deallocate(ptr noundef, i64 noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cross_triple_chain.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("triple_chain_go_c_rust") != null);
    try std.testing.expect(loader.getFunction("c_pass_to_rust") != null);
    try std.testing.expect(loader.getFunction("_cgo_allocate") != null);
    try std.testing.expect(loader.getFunction("_RZN4alloc5alloc17h_deallocate") != null);
}

// ============================================================================
// Zig Tests (3)
// ============================================================================

test "Zig: zig_allocator_alloc -> free (allocator mismatch)" {
    const ir =
        \\; ModuleID = 'zig_page_alloc_c_free'
        \\source_filename = "zig_page_alloc_c_free"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @zig_01_page_alloc_c_free() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @zig_allocator_alloc(i64 noundef 256, i64 noundef 8)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  %cmp = icmp eq ptr %0, null
        \\  br i1 %cmp, label %done, label %free_bb
        \\free_bb:
        \\  call void @free(ptr noundef %0)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @zig_allocator_alloc(i64 noundef, i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_zig_page_alloc_c_free.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("zig_01_page_alloc_c_free") != null);
    try std.testing.expect(loader.getFunction("zig_allocator_alloc") != null);
    try std.testing.expect(loader.getFunction("free") != null);
}

test "Zig: malloc -> zig_allocator_free (reverse mismatch)" {
    const ir =
        \\; ModuleID = 'c_alloc_zig_free'
        \\source_filename = "c_alloc_zig_free"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @zig_02_c_alloc_zig_free() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @malloc(i64 noundef 128)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  %cmp = icmp eq ptr %0, null
        \\  br i1 %cmp, label %done, label %free_bb
        \\free_bb:
        \\  call void @zig_allocator_free(ptr noundef %0, i64 noundef 128, i64 noundef 8)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @zig_allocator_free(ptr noundef, i64 noundef, i64 noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_c_alloc_zig_free.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("zig_02_c_alloc_zig_free") != null);
    try std.testing.expect(loader.getFunction("malloc") != null);
    try std.testing.expect(loader.getFunction("zig_allocator_free") != null);
}

test "Zig: malloc -> free (correct C pairing, should NOT trigger)" {
    const ir =
        \\; ModuleID = 'zig_safe_c_pair'
        \\source_filename = "zig_safe_c_pair"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @zig_03_safe_c_pair() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @malloc(i64 noundef 64)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  %cmp = icmp eq ptr %0, null
        \\  br i1 %cmp, label %done, label %use
        \\use:
        \\  store i8 0, ptr %0, align 1
        \\  call void @free(ptr noundef %0)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_zig_safe_c_pair.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("zig_03_safe_c_pair") != null);
    try std.testing.expect(loader.getFunction("malloc") != null);
    try std.testing.expect(loader.getFunction("free") != null);
}

// ============================================================================
// C# Noise (should NOT trigger) — 3 tests
// ============================================================================

test "C#: Marshal_AllocHGlobal -> Marshal_FreeHGlobal (correct pairing, NO bug)" {
    const ir =
        \\; ModuleID = 'cs_correct_marshal_alloc_free'
        \\source_filename = "cs_correct_marshal_alloc_free"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cs_16_correct_marshal_pair(ptr noundef %ctx) #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @Marshal_AllocHGlobal(i32 noundef 256)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  %cmp = icmp eq ptr %0, null
        \\  br i1 %cmp, label %done, label %use
        \\use:
        \\  store i8 42, ptr %0, align 1
        \\  call void @Marshal_FreeHGlobal(ptr noundef %0)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @Marshal_AllocHGlobal(i32 noundef) #1
        \\declare void @Marshal_FreeHGlobal(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cs_correct_marshal_pair.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cs_16_correct_marshal_pair") != null);
    try std.testing.expect(loader.getFunction("Marshal_AllocHGlobal") != null);
    try std.testing.expect(loader.getFunction("Marshal_FreeHGlobal") != null);
}

test "C#: CoTaskMemAlloc -> CoTaskMemFree (correct COM pairing, NO bug)" {
    const ir =
        \\; ModuleID = 'cs_correct_cotask_alloc_free'
        \\source_filename = "cs_correct_cotask_alloc_free"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cs_17_correct_cotask_pair() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @CoTaskMemAlloc(i64 noundef 512)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  %cmp = icmp eq ptr %0, null
        \\  br i1 %cmp, label %done, label %use
        \\use:
        \\  store i64 99, ptr %0, align 8
        \\  call void @CoTaskMemFree(ptr noundef %0)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @CoTaskMemAlloc(i64 noundef) #1
        \\declare void @CoTaskMemFree(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cs_correct_cotask_pair.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cs_17_correct_cotask_pair") != null);
    try std.testing.expect(loader.getFunction("CoTaskMemAlloc") != null);
    try std.testing.expect(loader.getFunction("CoTaskMemFree") != null);
}

test "C#: GCHandle_Alloc -> GCHandle_Free (correct GC handle lifecycle, NO bug)" {
    const ir =
        \\; ModuleID = 'cs_correct_gchandle_alloc_free'
        \\source_filename = "cs_correct_gchandle_alloc_free"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cs_18_correct_gchandle_pair(ptr noundef %obj) #0 {
        \\entry:
        \\  %handle = call i32 @GCHandle_Alloc(ptr noundef %obj, i32 noundef 2)
        \\  %cmp = icmp eq i32 %handle, 0
        \\  br i1 %cmp, label %done, label %use
        \\use:
        \\  store i8 77, ptr %obj, align 1
        \\  call void @GCHandle_Free(i32 noundef %handle)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare i32 @GCHandle_Alloc(ptr noundef, i32 noundef) #1
        \\declare void @GCHandle_Free(i32 noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cs_correct_gchandle_pair.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cs_18_correct_gchandle_pair") != null);
    try std.testing.expect(loader.getFunction("GCHandle_Alloc") != null);
    try std.testing.expect(loader.getFunction("GCHandle_Free") != null);
}

// ============================================================================
// C# Real Bugs (MUST trigger) — 3 tests
// ============================================================================

test "C#: GCHandle_Alloc -> GCHandle_Free -> GCHandle_Free (double free)" {
    const ir =
        \\; ModuleID = 'cs_double_gchandle_free'
        \\source_filename = "cs_double_gchandle_free"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cs_19_double_gchandle_free(ptr noundef %obj) #0 {
        \\entry:
        \\  %handle = call i32 @GCHandle_Alloc(ptr noundef %obj, i32 noundef 2)
        \\  %cmp = icmp eq i32 %handle, 0
        \\  br i1 %cmp, label %done, label %first_free
        \\first_free:
        \\  call void @GCHandle_Free(i32 noundef %handle)
        \\  call void @GCHandle_Free(i32 noundef %handle)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare i32 @GCHandle_Alloc(ptr noundef, i32 noundef) #1
        \\declare void @GCHandle_Free(i32 noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cs_double_gchandle_free.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cs_19_double_gchandle_free") != null);
    try std.testing.expect(loader.getFunction("GCHandle_Alloc") != null);
    try std.testing.expect(loader.getFunction("GCHandle_Free") != null);
}

test "C#: Marshal_AllocHGlobal -> CoTaskMemFree (wrong free function)" {
    const ir =
        \\; ModuleID = 'cs_marshal_alloc_cotask_free'
        \\source_filename = "cs_marshal_alloc_cotask_free"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cs_20_marshal_alloc_cotask_free() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @Marshal_AllocHGlobal(i32 noundef 256)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  %cmp = icmp eq ptr %0, null
        \\  br i1 %cmp, label %done, label %wrong_free
        \\wrong_free:
        \\  call void @CoTaskMemFree(ptr noundef %0)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @Marshal_AllocHGlobal(i32 noundef) #1
        \\declare void @CoTaskMemFree(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cs_marshal_alloc_cotask_free.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cs_20_marshal_alloc_cotask_free") != null);
    try std.testing.expect(loader.getFunction("Marshal_AllocHGlobal") != null);
    try std.testing.expect(loader.getFunction("CoTaskMemFree") != null);
}

test "C#: store delegate ptr -> free delegate -> call stored ptr (callback UAF)" {
    const ir =
        \\; ModuleID = 'cs_pinvoke_callback_after_free'
        \\source_filename = "cs_pinvoke_callback_after_free"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cs_21_callback_uaf() #0 {
        \\entry:
        \\  %saved = alloca ptr, align 8
        \\  %del = call ptr @Marshal_GetDelegateForFunctionPtr(ptr noundef null, i32 noundef 0)
        \\  store ptr %del, ptr %saved, align 8
        \\  call void @Marshal_FreeHGlobal(ptr noundef %del)
        \\  %0 = load ptr, ptr %saved, align 8
        \\  call void %0()
        \\  ret void
        \\}
        \\
        \\declare ptr @Marshal_GetDelegateForFunctionPtr(ptr noundef, i32 noundef) #1
        \\declare void @Marshal_FreeHGlobal(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cs_pinvoke_callback_uaf.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cs_21_callback_uaf") != null);
    try std.testing.expect(loader.getFunction("Marshal_GetDelegateForFunctionPtr") != null);
    try std.testing.expect(loader.getFunction("Marshal_FreeHGlobal") != null);
}

// ============================================================================
// C++ Noise (should NOT trigger) — 3 tests
// ============================================================================

test "C++: _Znwm -> _ZdlPv (correct new/delete pairing, NO bug)" {
    const ir =
        \\; ModuleID = 'cpp_correct_new_delete'
        \\source_filename = "cpp_correct_new_delete"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cpp_22_correct_new_delete() #0 {
        \\entry:
        \\  %obj = call ptr @_Znwm(i64 noundef 64)
        \\  %cmp = icmp eq ptr %obj, null
        \\  br i1 %cmp, label %done, label %use
        \\use:
        \\  store i64 42, ptr %obj, align 8
        \\  call void @_ZdlPv(ptr noundef %obj)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @_Znwm(i64 noundef) #1
        \\declare void @_ZdlPv(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cpp_correct_new_delete.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cpp_22_correct_new_delete") != null);
    try std.testing.expect(loader.getFunction("_Znwm") != null);
    try std.testing.expect(loader.getFunction("_ZdlPv") != null);
}

test "C++: _Znam -> _ZdaPv (correct new[]/delete[] pairing, NO bug)" {
    const ir =
        \\; ModuleID = 'cpp_correct_new_array_delete_array'
        \\source_filename = "cpp_correct_new_array_delete_array"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cpp_23_correct_array_pair() #0 {
        \\entry:
        \\  %arr = call ptr @_Znam(i64 noundef 128)
        \\  %cmp = icmp eq ptr %arr, null
        \\  br i1 %cmp, label %done, label %use
        \\use:
        \\  store i8 7, ptr %arr, align 1
        \\  call void @_ZdaPv(ptr noundef %arr)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @_Znam(i64 noundef) #1
        \\declare void @_ZdaPv(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cpp_correct_array_pair.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cpp_23_correct_array_pair") != null);
    try std.testing.expect(loader.getFunction("_Znam") != null);
    try std.testing.expect(loader.getFunction("_ZdaPv") != null);
}

test "C++: shared_ptr control blocks (two mallocs, two frees, correct lifecycle, NO bug)" {
    const ir =
        \\; ModuleID = 'cpp_shared_ptr_correct'
        \\source_filename = "cpp_shared_ptr_correct"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cpp_24_shared_ptr_correct() #0 {
        \\entry:
        \\  %data = call ptr @malloc(i64 noundef 64)
        \\  %ctrl = call ptr @malloc(i64 noundef 16)
        \\  %cmp_data = icmp eq ptr %data, null
        \\  br i1 %cmp_data, label %done, label %check_ctrl
        \\check_ctrl:
        \\  %cmp_ctrl = icmp eq ptr %ctrl, null
        \\  br i1 %cmp_ctrl, label %free_data, label %use
        \\use:
        \\  store ptr %data, ptr %ctrl, align 8
        \\  store i64 1, ptr %ctrl, align 8
        \\  call void @free(ptr noundef %ctrl)
        \\  call void @free(ptr noundef %data)
        \\  br label %done
        \\free_data:
        \\  call void @free(ptr noundef %data)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cpp_shared_ptr_correct.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cpp_24_shared_ptr_correct") != null);
    try std.testing.expect(loader.getFunction("malloc") != null);
    try std.testing.expect(loader.getFunction("free") != null);
}

// ============================================================================
// C++ Real Bugs (MUST trigger) — 3 tests
// ============================================================================

test "C++: _Znwm -> _Znwm again on same ptr (second alloc overwrites, first leaks)" {
    const ir =
        \\; ModuleID = 'cpp_new_then_new_again'
        \\source_filename = "cpp_new_then_new_again"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cpp_25_double_new_no_delete() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %first = call ptr @_Znwm(i64 noundef 64)
        \\  store ptr %first, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  store i64 1, ptr %0, align 8
        \\  %second = call ptr @_Znwm(i64 noundef 64)
        \\  store ptr %second, ptr %ptr, align 8
        \\  %1 = load ptr, ptr %ptr, align 8
        \\  store i64 2, ptr %1, align 8
        \\  ret void
        \\}
        \\
        \\declare ptr @_Znwm(i64 noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cpp_new_then_new_again.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cpp_25_double_new_no_delete") != null);
    try std.testing.expect(loader.getFunction("_Znwm") != null);
    // No delete declared -- confirms leak
    try std.testing.expect(loader.getFunction("_ZdlPv") == null);
}

test "C++: _Znam (new[]) -> _ZdlPv (scalar delete, array/scalar mismatch)" {
    const ir =
        \\; ModuleID = 'cpp_delete_wrong_type'
        \\source_filename = "cpp_delete_wrong_type"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cpp_26_array_new_scalar_delete() #0 {
        \\entry:
        \\  %arr = call ptr @_Znam(i64 noundef 256)
        \\  %cmp = icmp eq ptr %arr, null
        \\  br i1 %cmp, label %done, label %wrong_del
        \\wrong_del:
        \\  call void @_ZdlPv(ptr noundef %arr)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @_Znam(i64 noundef) #1
        \\declare void @_ZdlPv(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cpp_delete_wrong_type.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cpp_26_array_new_scalar_delete") != null);
    try std.testing.expect(loader.getFunction("_Znam") != null);
    try std.testing.expect(loader.getFunction("_ZdlPv") != null);
}

test "C++: malloc -> placement new (store) -> free (C alloc+free, detectable as C pair)" {
    const ir =
        \\; ModuleID = 'cpp_placement_new_then_free'
        \\source_filename = "cpp_placement_new_then_free"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cpp_27_placement_new_then_free() #0 {
        \\entry:
        \\  %mem = call ptr @malloc(i64 noundef 64)
        \\  %cmp = icmp eq ptr %mem, null
        \\  br i1 %cmp, label %done, label %construct
        \\construct:
        \\  store i64 0, ptr %mem, align 8
        \\  store i64 42, ptr %mem, align 8
        \\  call void @free(ptr noundef %mem)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cpp_placement_new_then_free.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cpp_27_placement_new_then_free") != null);
    try std.testing.expect(loader.getFunction("malloc") != null);
    try std.testing.expect(loader.getFunction("free") != null);
}

// ============================================================================
// Cross-Language Noise (should NOT trigger) — 3 tests
// ============================================================================

test "Cross-lang: malloc -> free (C alloc+C free from any language, NO bug)" {
    const ir =
        \\; ModuleID = 'cross_c_alloc_c_free_from_any_lang'
        \\source_filename = "cross_c_alloc_c_free_from_any_lang"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cross_28_c_pair_from_foreign() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @malloc(i64 noundef 128)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  %cmp = icmp eq ptr %0, null
        \\  br i1 %cmp, label %done, label %use
        \\use:
        \\  call void @foreign_use(ptr noundef %0)
        \\  call void @free(ptr noundef %0)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\define void @foreign_use(ptr noundef %p) #0 {
        \\entry:
        \\  store i8 1, ptr %p, align 1
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cross_c_pair_from_foreign.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cross_28_c_pair_from_foreign") != null);
    try std.testing.expect(loader.getFunction("foreign_use") != null);
    try std.testing.expect(loader.getFunction("malloc") != null);
    try std.testing.expect(loader.getFunction("free") != null);
}

test "Cross-lang: __rust_alloc -> __rust_dealloc (same allocator family, NO bug)" {
    const ir =
        \\; ModuleID = 'cross_same_allocator_different_context'
        \\source_filename = "cross_same_allocator_different_context"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cross_29_rust_same_alloc_family() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @__rust_alloc(i64 noundef 64, i64 noundef 8)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  %cmp = icmp eq ptr %0, null
        \\  br i1 %cmp, label %done, label %use
        \\use:
        \\  call void @c_intermediate_call(ptr noundef %0)
        \\  call void @__rust_dealloc(ptr noundef %0, i64 noundef 64, i64 noundef 8)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\define void @c_intermediate_call(ptr noundef %p) #0 {
        \\entry:
        \\  store i8 0, ptr %p, align 1
        \\  ret void
        \\}
        \\
        \\declare ptr @__rust_alloc(i64 noundef, i64 noundef) #1
        \\declare void @__rust_dealloc(ptr noundef, i64 noundef, i64 noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cross_same_alloc_family.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cross_29_rust_same_alloc_family") != null);
    try std.testing.expect(loader.getFunction("c_intermediate_call") != null);
    try std.testing.expect(loader.getFunction("__rust_alloc") != null);
    try std.testing.expect(loader.getFunction("__rust_dealloc") != null);
}

test "Cross-lang: malloc -> pass to function -> return -> free (ptr never stored, NO bug)" {
    const ir =
        \\; ModuleID = 'cross_ptr_passed_through_no_store'
        \\source_filename = "cross_ptr_passed_through_no_store"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cross_30_passthrough_no_store() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @malloc(i64 noundef 256)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  %cmp = icmp eq ptr %0, null
        \\  br i1 %cmp, label %done, label %pass
        \\pass:
        \\  call void @sink_function(ptr noundef %0)
        \\  call void @free(ptr noundef %0)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\define void @sink_function(ptr noundef %p) #0 {
        \\entry:
        \\  store i8 99, ptr %p, align 1
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cross_passthrough_no_store.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cross_30_passthrough_no_store") != null);
    try std.testing.expect(loader.getFunction("sink_function") != null);
    try std.testing.expect(loader.getFunction("malloc") != null);
    try std.testing.expect(loader.getFunction("free") != null);
}

// ============================================================================
// Cross-Language Real Bugs (MUST trigger) — 3 tests
// ============================================================================

test "Cross-lang: malloc (C) -> _cgo_free (Go, allocator mismatch)" {
    const ir =
        \\; ModuleID = 'cross_alloc_in_c_free_in_go'
        \\source_filename = "cross_alloc_in_c_free_in_go"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cross_31_c_alloc_go_free() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @malloc(i64 noundef 256)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  %cmp = icmp eq ptr %0, null
        \\  br i1 %cmp, label %done, label %wrong_free
        \\wrong_free:
        \\  call void @_cgo_free(ptr noundef %0)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @_cgo_free(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cross_c_alloc_go_free.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cross_31_c_alloc_go_free") != null);
    try std.testing.expect(loader.getFunction("malloc") != null);
    try std.testing.expect(loader.getFunction("_cgo_free") != null);
}

test "Cross-lang: PyMem_Malloc -> free (Python allocator -> C free, mismatch)" {
    const ir =
        \\; ModuleID = 'cross_alloc_in_python_free_in_c'
        \\source_filename = "cross_alloc_in_python_free_in_c"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cross_32_python_alloc_c_free() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @PyMem_Malloc(i64 noundef 128)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  %cmp = icmp eq ptr %0, null
        \\  br i1 %cmp, label %done, label %wrong_free
        \\wrong_free:
        \\  call void @free(ptr noundef %0)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @PyMem_Malloc(i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cross_python_alloc_c_free.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cross_32_python_alloc_c_free") != null);
    try std.testing.expect(loader.getFunction("PyMem_Malloc") != null);
    try std.testing.expect(loader.getFunction("free") != null);
}

test "Cross-lang: __rust_alloc -> store to global -> pass to C -> _cgo_free (three-lang chain)" {
    const ir =
        \\; ModuleID = 'cross_three_lang_chain_with_store'
        \\source_filename = "cross_three_lang_chain_with_store"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\@global_ptr = global ptr null, align 8
        \\
        \\define void @cross_33_rust_to_c_to_go() #0 {
        \\entry:
        \\  %call = call ptr @__rust_alloc(i64 noundef 64, i64 noundef 8)
        \\  store ptr %call, ptr @global_ptr, align 8
        \\  %0 = load ptr, ptr @global_ptr, align 8
        \\  %cmp = icmp eq ptr %0, null
        \\  br i1 %cmp, label %done, label %pass_to_c
        \\pass_to_c:
        \\  call void @c_bridge(ptr noundef %0)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\define void @c_bridge(ptr noundef %p) #0 {
        \\entry:
        \\  call void @_cgo_free(ptr noundef %p)
        \\  ret void
        \\}
        \\
        \\declare ptr @__rust_alloc(i64 noundef, i64 noundef) #1
        \\declare void @_cgo_free(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cross_three_lang_chain_store.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cross_33_rust_to_c_to_go") != null);
    try std.testing.expect(loader.getFunction("c_bridge") != null);
    try std.testing.expect(loader.getFunction("__rust_alloc") != null);
    try std.testing.expect(loader.getFunction("_cgo_free") != null);
}

// ============================================================================
// Zig Noise (should NOT trigger) — 1 test
// ============================================================================

test "Zig: malloc -> free (correct C pair from Zig, NO bug)" {
    const ir =
        \\; ModuleID = 'zig_correct_c_pair'
        \\source_filename = "zig_correct_c_pair"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @zig_34_correct_c_pair() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @malloc(i64 noundef 256)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  %cmp = icmp eq ptr %0, null
        \\  br i1 %cmp, label %done, label %use
        \\use:
        \\  store i8 0, ptr %0, align 1
        \\  store i64 42, ptr %0, align 8
        \\  call void @free(ptr noundef %0)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_zig_correct_c_pair.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("zig_34_correct_c_pair") != null);
    try std.testing.expect(loader.getFunction("malloc") != null);
    try std.testing.expect(loader.getFunction("free") != null);
}

// ============================================================================
// False Negative Edge Cases — 2 tests
// ============================================================================

test "C++: helper calls _Znwm, main calls _ZdlPv on result (new/delete mismatch through helper)" {
    const ir =
        \\; ModuleID = 'cpp_new_in_helper_delete_in_main'
        \\source_filename = "cpp_new_in_helper_delete_in_main"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define ptr @_cpp_helper_new(i64 noundef %size) #0 {
        \\entry:
        \\  %call = call ptr @_Znam(i64 noundef %size)
        \\  ret ptr %call
        \\}
        \\
        \\define void @cpp_35_helper_new_main_delete() #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @_cpp_helper_new(i64 noundef 128)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  %cmp = icmp eq ptr %0, null
        \\  br i1 %cmp, label %done, label %del
        \\del:
        \\  call void @_ZdlPv(ptr noundef %0)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @_Znam(i64 noundef) #1
        \\declare void @_ZdlPv(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cpp_helper_new_main_delete.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("_cpp_helper_new") != null);
    try std.testing.expect(loader.getFunction("cpp_35_helper_new_main_delete") != null);
    try std.testing.expect(loader.getFunction("_Znam") != null);
    try std.testing.expect(loader.getFunction("_ZdlPv") != null);
}

test "Cross-lang: malloc -> branch with phi (one path Rust frees, other path C frees)" {
    const ir =
        \\; ModuleID = 'cross_alloc_escape_through_phi'
        \\source_filename = "cross_alloc_escape_through_phi"
        \\target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        \\target triple = "arm64-apple-macosx15.0.0"
        \\
        \\define void @cross_36_phi_escape(ptr noundef %cond_ptr) #0 {
        \\entry:
        \\  %ptr = alloca ptr, align 8
        \\  %call = call ptr @malloc(i64 noundef 256)
        \\  store ptr %call, ptr %ptr, align 8
        \\  %0 = load ptr, ptr %ptr, align 8
        \\  %cmp = icmp eq ptr %0, null
        \\  br i1 %cmp, label %done, label %branch
        \\branch:
        \\  %cond = load i8, ptr %cond_ptr, align 1
        \\  %is_zero = icmp eq i8 %cond, 0
        \\  br i1 %is_zero, label %rust_path, label %c_path
        \\rust_path:
        \\  call void @__rust_dealloc(ptr noundef %0, i64 noundef 256, i64 noundef 8)
        \\  br label %done
        \\c_path:
        \\  call void @free(ptr noundef %0)
        \\  br label %done
        \\done:
        \\  ret void
        \\}
        \\
        \\declare ptr @malloc(i64 noundef) #1
        \\declare void @__rust_dealloc(ptr noundef, i64 noundef, i64 noundef) #1
        \\declare void @free(ptr noundef) #1
        \\
        \\attributes #0 = { nounwind }
        \\attributes #1 = { nounwind }
    ;
    const tmp = TMP_BASE ++ "_cross_phi_escape.ll";
    try std.fs.cwd().writeFile(.{ .sub_path = tmp, .data = ir });
    defer std.fs.cwd().deleteFile(tmp) catch {};

    var loader = try IRLoader.loadFile(std.testing.allocator, tmp);
    defer loader.deinit();

    try std.testing.expect(loader.hasModule());
    try std.testing.expect(loader.getFunction("cross_36_phi_escape") != null);
    try std.testing.expect(loader.getFunction("malloc") != null);
    try std.testing.expect(loader.getFunction("__rust_dealloc") != null);
    try std.testing.expect(loader.getFunction("free") != null);
}
