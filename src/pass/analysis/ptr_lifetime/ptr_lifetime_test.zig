//! Tests for PtrLifetimePass and related modules.
//!
//! Extracted from ptr_lifetime.zig to comply with the 1000-line limit.

const std = @import("std");
const c = @import("../../../ir/llvm_raw.zig").c;

const PtrLifetimePass = @import("ptr_lifetime.zig").PtrLifetimePass;
const PassKind = @import("../../../pass/pass.zig").PassKind;
const PtrAllocSite = @import("ptr_lifetime_types.zig").PtrAllocSite;
const LifetimeViolation = @import("ptr_lifetime_types.zig").LifetimeViolation;
const PtrInfo = @import("ptr_lifetime_types.zig").PtrInfo;
const LifetimeStats = @import("ptr_lifetime_types.zig").LifetimeStats;
const LifetimeAnalysisResult = @import("ptr_lifetime_types.zig").LifetimeAnalysisResult;
const ResourceType = @import("ptr_lifetime_types.zig").ResourceType;

const is_extern_function = @import("ptr_lifetime_types.zig").is_extern_function;
const may_retain_pointer = @import("ptr_lifetime_types.zig").may_retain_pointer;
const classify_ptr_origin = @import("ptr_lifetime_types.zig").classify_ptr_origin;
const is_known_deallocator = @import("ptr_lifetime_types.zig").is_known_deallocator;
const is_intentional_free = @import("ptr_lifetime_types.zig").is_intentional_free;

const isFreeFunction = @import("ptr_lifetime_classify.zig").isFreeFunction;
const isResourceCloseFunction = @import("ptr_lifetime_utils.zig").isResourceCloseFunction;
const get_resource_type = @import("ptr_lifetime_utils.zig").get_resource_type;
const is_resource_alloc_function = @import("ptr_lifetime_utils.zig").is_resource_alloc_function;
const is_lifecycle_bound_return = @import("ptr_lifetime_return_helpers.zig").is_lifecycle_bound_return;

const FfiLang = @import("../../../diag/issue.zig").FFIBoundary.Language;
const Lang = @import("../../../semantics/zone_classifier.zig").Language;
const toZoneLanguage = @import("ptr_lifetime.zig").toZoneLanguage;

test "PtrLifetimePass - name and kind" {
    try std.testing.expectEqualStrings("ptr-lifetime", PtrLifetimePass.name);
    try std.testing.expectEqual(PassKind.analysis, PtrLifetimePass.kind);
}

test "is_extern_function - known patterns" {
    try std.testing.expect(is_extern_function("register_callback"));
    try std.testing.expect(is_extern_function("c_callback"));
    try std.testing.expect(is_extern_function("pthread_create"));
    try std.testing.expect(is_extern_function("signal"));
    try std.testing.expect(!is_extern_function("my_func"));
    try std.testing.expect(!is_extern_function("printf"));
}

test "may_retain_pointer - retaining patterns" {
    try std.testing.expect(may_retain_pointer("register_handler"));
    try std.testing.expect(may_retain_pointer("set_callback"));
    try std.testing.expect(may_retain_pointer("add_observer"));
    try std.testing.expect(may_retain_pointer("store_data"));
    try std.testing.expect(!may_retain_pointer("memcpy"));
    try std.testing.expect(!may_retain_pointer("printf"));
    try std.testing.expect(!may_retain_pointer("free"));
}

test "PtrAllocSite - enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(PtrAllocSite.heap));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(PtrAllocSite.stack));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(PtrAllocSite.parameter));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(PtrAllocSite.global));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(PtrAllocSite.constant));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(PtrAllocSite.unknown));
}

test "LifetimeViolation - enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(LifetimeViolation.stack_escape_to_ffi));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(LifetimeViolation.return_stack_address));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(LifetimeViolation.use_after_free_risk));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(LifetimeViolation.heap_ownership_ambiguous));
}

test "PtrInfo - default fields" {
    const info = PtrInfo{
        .alloc_site = .stack,
        .source_inst = null,
        .source_desc = "test",
    };
    try std.testing.expectEqual(PtrAllocSite.stack, info.alloc_site);
    try std.testing.expect(!info.escaped);
    try std.testing.expect(!info.freed);
    try std.testing.expectEqual(@as(usize, 0), info.alloc_bb_id);
}

test "LifetimeStats - initialization" {
    const stats = LifetimeStats{};
    try std.testing.expectEqual(@as(u32, 0), stats.total_functions_analyzed);
    try std.testing.expectEqual(@as(u32, 0), stats.stack_escapes_found);
    try std.testing.expectEqual(@as(u32, 0), stats.return_stack_addr_found);
}

test "LifetimeStats - tracking" {
    var stats = LifetimeStats{};
    stats.total_functions_analyzed = 10;
    stats.total_pointers_tracked = 25;
    stats.stack_escapes_found = 3;
    stats.return_stack_addr_found = 1;
    stats.use_after_free_found = 2;
    stats.heap_ambiguous_found = 4;

    try std.testing.expectEqual(@as(u32, 10), stats.total_functions_analyzed);
    try std.testing.expectEqual(@as(u32, 25), stats.total_pointers_tracked);
    try std.testing.expectEqual(@as(u32, 3), stats.stack_escapes_found);
    try std.testing.expectEqual(@as(u32, 10), stats.stack_escapes_found + stats.return_stack_addr_found +
        stats.use_after_free_found + stats.heap_ambiguous_found);
}

test "LifetimeAnalysisResult - initialization" {
    const result = LifetimeAnalysisResult{
        .func_name = "test_function",
    };
    try std.testing.expectEqual(@as(u32, 0), result.violation_count);
    try std.testing.expectEqualStrings("test_function", result.func_name);
}

test "classify_ptr_origin - pattern matching" {
    const result = classify_ptr_origin(null, c.LLVMAlloca, null, std.testing.allocator) catch null;
    try std.testing.expect(result != null);
}

test "isFreeFunction - detection" {
    try std.testing.expect(isFreeFunction("free"));
    try std.testing.expect(isFreeFunction("dealloc"));
    try std.testing.expect(isFreeFunction("operator delete"));
    try std.testing.expect(!isFreeFunction("malloc"));
    try std.testing.expect(!isFreeFunction("printf"));
}

test "isResourceCloseFunction - detection" {
    try std.testing.expect(isResourceCloseFunction("dlclose") != null);
    try std.testing.expect(isResourceCloseFunction("munmap") != null);
    try std.testing.expect(isResourceCloseFunction("fclose") != null);
    try std.testing.expect(isResourceCloseFunction("close") != null);
    try std.testing.expect(isResourceCloseFunction("DeleteGlobalRef") != null);
    try std.testing.expect(isResourceCloseFunction("Py_DECREF") != null);
    try std.testing.expect(isResourceCloseFunction("dlopen") == null);
    try std.testing.expect(isResourceCloseFunction("malloc") == null);
    try std.testing.expect(isResourceCloseFunction("printf") == null);
}

test "getResourceType - classification" {
    try std.testing.expectEqualStrings("dlopen handle", get_resource_type("dlopen").?);
    try std.testing.expectEqualStrings("dlopen handle", get_resource_type("dlsym").?);
    try std.testing.expectEqualStrings("mmap region", get_resource_type("mmap").?);
    try std.testing.expectEqualStrings("file handle", get_resource_type("fopen").?);
    try std.testing.expectEqualStrings("socket", get_resource_type("socket").?);
    try std.testing.expectEqual(@as(?[]const u8, null), get_resource_type("JNI_OnLoad"));
    try std.testing.expectEqualStrings("Python object", get_resource_type("Py_BuildValue").?);
    try std.testing.expectEqual(@as(?[]const u8, null), get_resource_type("malloc"));
    try std.testing.expectEqual(@as(?[]const u8, null), get_resource_type("printf"));
}

test "is_resource_alloc_function - returns ResourceType" {
    try std.testing.expectEqual(ResourceType.dlopen_handle, is_resource_alloc_function("dlopen").?);
    try std.testing.expectEqual(ResourceType.mmap_region, is_resource_alloc_function("mmap").?);
    try std.testing.expectEqual(ResourceType.mmap_region, is_resource_alloc_function("mmap64").?);
    try std.testing.expectEqual(ResourceType.mmap_region, is_resource_alloc_function("mmap2").?);
    try std.testing.expectEqual(ResourceType.mmap_region, is_resource_alloc_function("shm_open").?);
    try std.testing.expectEqual(ResourceType.file_handle, is_resource_alloc_function("fopen").?);
    try std.testing.expectEqual(ResourceType.socket_fd, is_resource_alloc_function("socket").?);
    try std.testing.expectEqual(ResourceType.jni_ref, is_resource_alloc_function("JNI_OnLoad").?);
    try std.testing.expectEqual(ResourceType.jni_ref, is_resource_alloc_function("Java_com_example_MyClass").?);
    try std.testing.expectEqual(ResourceType.python_obj, is_resource_alloc_function("Py_BuildValue").?);
    try std.testing.expectEqual(ResourceType.python_obj, is_resource_alloc_function("PyObject_Call").?);
    try std.testing.expectEqual(@as(?ResourceType, null), is_resource_alloc_function("malloc"));
    try std.testing.expectEqual(@as(?ResourceType, null), is_resource_alloc_function("free"));
}

test "ResourceType - enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ResourceType.none));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ResourceType.dlopen_handle));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(ResourceType.mmap_region));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(ResourceType.file_handle));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(ResourceType.socket_fd));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(ResourceType.jni_ref));
    try std.testing.expectEqual(@as(u8, 6), @intFromEnum(ResourceType.python_obj));
}

test "is_lifecycle_bound_return - dlsym" {
    const info = PtrInfo{
        .alloc_site = .heap,
        .source_inst = null,
        .source_desc = "resource via dlsym()",
        .resource_type = .dlopen_handle,
    };
    try std.testing.expect(is_lifecycle_bound_return("dlsym", info));
    try std.testing.expect(!is_lifecycle_bound_return("malloc", info));
}

test "is_lifecycle_bound_return - mmap" {
    const info = PtrInfo{
        .alloc_site = .heap,
        .source_inst = null,
        .source_desc = "resource via mmap()",
        .resource_type = .mmap_region,
    };
    try std.testing.expect(is_lifecycle_bound_return("mmap", info));
    try std.testing.expect(is_lifecycle_bound_return("mmap64", info));
    try std.testing.expect(!is_lifecycle_bound_return("malloc", info));
}

test "is_lifecycle_bound_return - file/socket" {
    const file_info = PtrInfo{
        .alloc_site = .heap,
        .source_inst = null,
        .source_desc = "resource via fopen()",
        .resource_type = .file_handle,
    };
    try std.testing.expect(is_lifecycle_bound_return("fopen", file_info));
    try std.testing.expect(!is_lifecycle_bound_return("open", file_info));

    const sock_info = PtrInfo{
        .alloc_site = .heap,
        .source_inst = null,
        .source_desc = "resource via socket()",
        .resource_type = .socket_fd,
    };
    try std.testing.expect(is_lifecycle_bound_return("socket", sock_info));
    try std.testing.expect(!is_lifecycle_bound_return("accept", sock_info));
}

test "is_known_deallocator - finalize" {
    try std.testing.expect(is_known_deallocator("sqlite3_finalize"));
    try std.testing.expect(is_known_deallocator("mysql_stmt_close"));
    try std.testing.expect(is_known_deallocator("stmt_finalize"));
}

test "is_known_deallocator - close" {
    try std.testing.expect(is_known_deallocator("fclose"));
    try std.testing.expect(is_known_deallocator("close"));
    try std.testing.expect(is_known_deallocator("SSL_shutdown"));
    try std.testing.expect(is_known_deallocator("EVP_CIPHER_CTX_free"));
}

test "is_known_deallocator - free" {
    try std.testing.expect(is_known_deallocator("sqlite3_free"));
    try std.testing.expect(is_known_deallocator("mysql_free_result"));
    try std.testing.expect(is_known_deallocator("PQclear"));
    try std.testing.expect(is_known_deallocator("curl_easy_cleanup"));
}

test "is_known_deallocator - destroy" {
    try std.testing.expect(is_known_deallocator("sqlite3_close"));
    try std.testing.expect(is_known_deallocator("mysql_close"));
    try std.testing.expect(is_known_deallocator("Delete"));
    try std.testing.expect(is_known_deallocator("Release"));
}

test "is_known_deallocator - negative" {
    try std.testing.expect(!is_known_deallocator("malloc"));
    try std.testing.expect(!is_known_deallocator("calloc"));
    try std.testing.expect(!is_known_deallocator("dlopen"));
}

test "is_intentional_free - known deallocators" {
    try std.testing.expect(is_intentional_free("sqlite3_finalize"));
    try std.testing.expect(is_intentional_free("fclose"));
    try std.testing.expect(is_intentional_free("curl_easy_cleanup"));
}

test "is_intentional_free - resource close" {
    try std.testing.expect(is_intentional_free("dlclose"));
    try std.testing.expect(is_intentional_free("munmap"));
    try std.testing.expect(is_intentional_free("DeleteGlobalRef"));
    try std.testing.expect(is_intentional_free("Py_DECREF"));
}

test "is_intentional_free - negative" {
    try std.testing.expect(!is_intentional_free("malloc"));
    try std.testing.expect(!is_intentional_free("dlopen"));
}

test "toZoneLanguage - explicit mapping correctness" {
    try std.testing.expectEqual(Lang.c, toZoneLanguage(FfiLang.c));
    try std.testing.expectEqual(Lang.cpp, toZoneLanguage(FfiLang.cpp));
    try std.testing.expectEqual(Lang.rust, toZoneLanguage(FfiLang.rust));
    try std.testing.expectEqual(Lang.zig, toZoneLanguage(FfiLang.zig));
    try std.testing.expectEqual(Lang.go, toZoneLanguage(FfiLang.go));
    try std.testing.expectEqual(Lang.unknown, toZoneLanguage(FfiLang.csharp));
}

// ============================================================================
// T1.2: LLVM Lifetime Intrinsic Tests
// ============================================================================

const LifetimeMap = @import("ptr_lifetime_types.zig").LifetimeMap;
const LifetimeInterval = @import("ptr_lifetime_types.zig").LifetimeInterval;
const isWithinLifetime = @import("ptr_lifetime_types.zig").isWithinLifetime;
const isAllocaAliveAt = @import("ptr_lifetime_types.zig").isAllocaAliveAt;

test "T1.2 - LifetimeInterval basic structure" {
    const interval = LifetimeInterval{
        .start_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 100))),
        .end_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 200))),
    };
    try std.testing.expect(interval.start_inst == @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 100))));
    try std.testing.expect(interval.end_inst.? == @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 200))));
}

test "T1.2 - isWithinLifetime - instruction inside interval" {
    const interval = LifetimeInterval{
        .start_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 100))),
        .end_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 200))),
    };
    // Instruction at 150 should be within [100, 200)
    try std.testing.expect(isWithinLifetime(interval, @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 150)))));
}

test "T1.2 - isWithinLifetime - instruction before start" {
    const interval = LifetimeInterval{
        .start_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 100))),
        .end_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 200))),
    };
    // Instruction at 50 should NOT be within [100, 200)
    try std.testing.expect(!isWithinLifetime(interval, @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 50)))));
}

test "T1.2 - isWithinLifetime - instruction after end" {
    const interval = LifetimeInterval{
        .start_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 100))),
        .end_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 200))),
    };
    // Instruction at 250 should NOT be within [100, 200) (exclusive end)
    try std.testing.expect(!isWithinLifetime(interval, @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 250)))));
}

test "T1.2 - isWithinLifetime - instruction at start (inclusive)" {
    const interval = LifetimeInterval{
        .start_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 100))),
        .end_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 200))),
    };
    // Instruction at exactly start should be included
    try std.testing.expect(isWithinLifetime(interval, @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 100)))));
}

test "T1.2 - isWithinLifetime - instruction at end (exclusive)" {
    const interval = LifetimeInterval{
        .start_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 100))),
        .end_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 200))),
    };
    // Instruction at exactly end should NOT be included (exclusive)
    try std.testing.expect(!isWithinLifetime(interval, @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 200)))));
}

test "T1.2 - isWithinLifetime - no end instruction (conservative)" {
    const interval = LifetimeInterval{
        .start_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 100))),
        .end_inst = null,
    };
    // When no end instruction, assume still alive for any inst after start
    try std.testing.expect(isWithinLifetime(interval, @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 150)))));
    try std.testing.expect(isWithinLifetime(interval, @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 99999)))));
}

test "T1.2 - isAllocaAliveAt - happy path: alloca alive during escape" {
    var lifetime_map = LifetimeMap.init(std.testing.allocator);
    defer lifetime_map.deinit();

    const alloca_ref: c.LLVMValueRef = @ptrFromInt(@as(usize, 1000));
    const start_inst: c.LLVMValueRef = @ptrFromInt(@as(usize, 2000));
    const end_inst: c.LLVMValueRef = @ptrFromInt(@as(usize, 5000));
    const escape_inst: c.LLVMValueRef = @ptrFromInt(@as(usize, 3000));

    try lifetime_map.put(alloca_ref, LifetimeInterval{
        .start_inst = start_inst,
        .end_inst = end_inst,
    });

    // Escape at 3000 is within [2000, 5000) → should report (alive)
    try std.testing.expect(isAllocaAliveAt(&lifetime_map, alloca_ref, escape_inst));
}

test "T1.2 - isAllocaAliveAt - boundary: escape after lifetime.end" {
    var lifetime_map = LifetimeMap.init(std.testing.allocator);
    defer lifetime_map.deinit();

    const alloca_ref: c.LLVMValueRef = @ptrFromInt(@as(usize, 1000));
    const start_inst: c.LLVMValueRef = @ptrFromInt(@as(usize, 2000));
    const end_inst: c.LLVMValueRef = @ptrFromInt(@as(usize, 5000));
    const escape_inst: c.LLVMValueRef = @ptrFromInt(@as(usize, 6000));

    try lifetime_map.put(alloca_ref, LifetimeInterval{
        .start_inst = start_inst,
        .end_inst = end_inst,
    });

    // Escape at 6000 is AFTER [2000, 5000) → should suppress (dead, FP reduction)
    try std.testing.expect(!isAllocaAliveAt(&lifetime_map, alloca_ref, escape_inst));
}

test "T1.2 - isAllocaAliveAt - old IR: no intrinsic (empty map)" {
    var lifetime_map = LifetimeMap.init(std.testing.allocator);
    defer lifetime_map.deinit();

    const alloca_ref: c.LLVMValueRef = @ptrFromInt(@as(usize, 1000));
    const escape_inst: c.LLVMValueRef = @ptrFromInt(@as(usize, 3000));

    // Empty lifetime_map → returns false → falls back to current logic (no suppression)
    try std.testing.expect(!isAllocaAliveAt(&lifetime_map, alloca_ref, escape_inst));
}

test "T1.2 - isAllocaAliveAt - unknown alloca not in map" {
    var lifetime_map = LifetimeMap.init(std.testing.allocator);
    defer lifetime_map.deinit();

    const known_alloca: c.LLVMValueRef = @ptrFromInt(@as(usize, 1000));
    const unknown_alloca: c.LLVMValueRef = @ptrFromInt(@as(usize, 2000));
    const escape_inst: c.LLVMValueRef = @ptrFromInt(@as(usize, 3000));

    try lifetime_map.put(known_alloca, LifetimeInterval{
        .start_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 2000))),
        .end_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 5000))),
    });

    // Unknown alloca not in map → returns false → no suppression
    try std.testing.expect(!isAllocaAliveAt(&lifetime_map, unknown_alloca, escape_inst));
}

test "T1.2 - LifetimeMap put and get roundtrip" {
    var lifetime_map = LifetimeMap.init(std.testing.allocator);
    defer lifetime_map.deinit();

    const alloca_ref: c.LLVMValueRef = @ptrFromInt(@as(usize, 42));
    const interval = LifetimeInterval{
        .start_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 100))),
        .end_inst = @as(c.LLVMValueRef, @ptrFromInt(@as(usize, 200))),
    };

    try lifetime_map.put(alloca_ref, interval);
    const retrieved = lifetime_map.get(alloca_ref).?;
    try std.testing.expect(retrieved.start_inst == interval.start_inst);
    try std.testing.expect(retrieved.end_inst.? == interval.end_inst.?);
}
