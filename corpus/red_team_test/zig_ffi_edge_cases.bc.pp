; ModuleID = 'zig_ffi_edge_cases'
source_filename = "zig_ffi_edge_cases.ll"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "aarch64-apple-macosx15.0.0"

; ============================================================================
; Zig FFI Edge Cases
; Each function demonstrates a distinct cross-language FFI safety bug
; involving Zig's allocator model, slices, optionals, and error handling.
; ============================================================================

; Zig-style types
%"[]u8" = type { ptr, i64 }
%"[:0]u8" = type { ptr, i64 }
%"?*anyopaque" = type { ptr }
%"!ptr" = type { ptr, i8 }

; Allocator vtable
%Allocator = type { ptr, ptr }

; Error union result
%ErrorUnion = type { ptr, i64 }

@.str.zig_alloc = private unnamed_addr constant [15 x i8] c"zig alloc data\00", align 1
@.str.sentinel = private unnamed_addr constant [20 x i8] c"sentinel terminated\00", align 1
@.str.comptime = private unnamed_addr constant [18 x i8] c"comptime constant\00", align 1
@.str.safe = private unnamed_addr constant [14 x i8] c"safe zig data\00", align 1

; Static (comptime) string -- lives in read-only memory
@comptime_string = private unnamed_addr constant [17 x i8] c"comptime string!\00", align 1

; ============================================================================
; Bug 01: Allocator mismatch (page_allocator vs c free)
; Zig allocates with std.heap.page_allocator (mmap/VirtualAlloc), but
; C code frees with free() -> crash because free() doesn't understand
; page-allocator metadata.
; ============================================================================
define void @zig_01_allocator_mismatch() #0 {
entry:
  ; Zig page_allocator allocates via mmap (rounded up to page size)
  %buf = call ptr @os_mmap(ptr null, i64 4096, i32 3, i32 4098, i32 -1, i64 0)
  %is_null = icmp eq ptr %buf, null
  br i1 %is_null, label %done, label %use

use:
  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %buf, ptr align 1 @.str.zig_alloc, i64 15, i1 false)
  ; Pass to C function
  call void @c_process_buffer(ptr %buf, i64 4096)
  ; BUG: C code calls free() on the mmap'd buffer.
  ; free() does not know about mmap regions -> crash or heap corruption.
  call void @free(ptr %buf)
  br label %done

done:
  ret void
}

; ============================================================================
; Bug 02: Sentinel-terminated slice to C
; Zig [:0]u8 (sentinel-terminated) is passed to C. C writes past the
; sentinel byte, corrupting adjacent memory.
; ============================================================================
define void @zig_02_sentinel_overflow() #0 {
entry:
  ; Allocate a sentinel-terminated buffer (20 bytes + sentinel)
  %buf = call ptr @zig_allocator_alloc(ptr null, i64 21)
  %is_null = icmp eq ptr %buf, null
  br i1 %is_null, label %done, label %fill

fill:
  ; Copy 20 bytes + null terminator
  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %buf, ptr align 1 @.str.sentinel, i64 20, i1 false)
  ; Pass to C as a regular char* -- C does not know about the 20-byte limit
  ; BUG: C writes beyond byte 20, overwriting the sentinel and adjacent heap
  call void @c_write_past_sentinel(ptr %buf, i64 64)
  call void @zig_allocator_free(ptr null, ptr %buf)
  br label %done

done:
  ret void
}

; ============================================================================
; Bug 03: defer + error return in FFI cleanup
; Zig defer calls a C cleanup function. An error return triggers the
; defer, then manual cleanup also runs -> double free.
; ============================================================================
define void @zig_03_defer_error_double_free(i1 %should_fail) #0 {
entry:
  ; Allocate resource
  %res = call ptr @c_alloc_resource(i64 256)
  %is_null = icmp eq ptr %res, null
  br i1 %is_null, label %done, label %check_fail

check_fail:
  ; Use the resource
  call void @c_use_resource(ptr %res)
  br i1 %should_fail, label %error_path, label %success_path

error_path:
  ; Error return triggers Zig's defer block
  ; In Zig IR, defer inlines the cleanup call at each return point
  call void @c_free_resource(ptr %res)
  ; BUG: manual cleanup also runs for the error path
  call void @c_free_resource(ptr %res)
  br label %done

success_path:
  ; Normal return: only defer cleanup runs
  call void @c_free_resource(ptr %res)
  br label %done

done:
  ret void
}

; ============================================================================
; Bug 04: @ptrCast alignment violation
; Zig pointer is @ptrCast to a less-aligned type. C accesses through
; the misaligned pointer -> undefined behavior on strict-alignment archs.
; ============================================================================
define void @zig_04_alignment_violation() #0 {
entry:
  ; Allocate 16-byte aligned buffer
  %buf = call ptr @zig_allocator_alloc(ptr null, i64 32)
  %is_null = icmp eq ptr %buf, null
  br i1 %is_null, label %done, label %setup

setup:
  ; Write some data
  call void @llvm.memset.p0.i64(ptr align 16 %buf, i8 65, i64 32, i1 false)
  ; Get pointer offset by 1 byte (misaligned for i32/i64)
  %misaligned = getelementptr inbounds i8, ptr %buf, i64 1
  ; BUG: @ptrCast misaligned pointer to i32* and pass to C.
  ; C does a 4-byte load from an address not aligned to 4 -> UB on ARM
  call void @c_read_as_i32_array(ptr %misaligned, i64 7)
  call void @zig_allocator_free(ptr null, ptr %buf)
  br label %done

done:
  ret void
}

; ============================================================================
; Bug 05: Optional pointer to C
; Zig ?*T (optional pointer, null when none) is passed to C function
; expecting *T (non-null pointer). C dereferences null -> crash.
; ============================================================================
define void @zig_05_optional_null_deref(i1 %has_value) #0 {
entry:
  br i1 %has_value, label %some, label %none

some:
  %val = call ptr @zig_allocator_alloc(ptr null, i64 64)
  call void @llvm.memset.p0.i64(ptr align 1 %val, i8 42, i64 64, i1 false)
  br label %pass_to_c

none:
  ; Zig optional is null when none
  br label %pass_to_c

pass_to_c:
  %ptr = phi ptr [ %val, %some ], [ null, %none ]
  ; BUG: Zig passes null ?*T directly to C function expecting non-null *T.
  ; C has no null check and dereferences it -> segfault.
  call void @c_dereference_ptr(ptr %ptr)
  br label %done

done:
  ret void
}

; ============================================================================
; Bug 06: comptime-allocated memory to runtime
; A comptime string literal lives in read-only static memory (.rodata).
; If its pointer is passed to C code that calls free() on it -> crash
; because free() cannot release static/read-only memory.
; ============================================================================
define void @zig_06_comptime_static_free() #0 {
entry:
  ; comptime string is a global constant in .rodata
  ; In Zig: const s = "comptime string!"; // pointer to static memory
  %static_ptr = ptrtoint ptr @comptime_string to i64
  %null_check = icmp eq i64 %static_ptr, 0
  br i1 %null_check, label %done, label %pass

pass:
  ; Pass comptime string pointer to C function
  ; BUG: C function calls free() on the static pointer.
  ; free() on .rodata memory -> crash or heap corruption.
  call void @c_may_free_string(ptr @comptime_string)
  br label %done

done:
  ret void
}

; ============================================================================
; Bug 07: Error union + FFI callback
; C callback returns a Zig error union (tagged pointer + error code).
; But C ABI expects a plain pointer. The error tag bits are interpreted
; as pointer bits -> stack corruption or wild pointer.
; ============================================================================
define void @zig_07_error_union_callback() #0 {
entry:
  ; Register Zig function as C callback
  call void @c_register_callback_ptr(ptr @zig_error_union_callback)
  ; Trigger the callback -- C expects a plain pointer return,
  ; but our callback returns an error union
  %result = call ptr @c_invoke_callback()
  ; BUG: if the callback returned an error, %result contains error bits,
  ; not a valid pointer. Dereferencing -> crash.
  %is_null = icmp eq ptr %result, null
  br i1 %is_null, label %done, label %deref

deref:
  %val = load i8, ptr %result
  br label %done

done:
  ret void
}

; Internal: callback that returns error union
; In Zig, error unions are represented as {ptr, error_code} or tagged ptr.
; C expects just a ptr.
define ptr @zig_error_union_callback() #0 {
entry:
  ; Simulate returning an error (error code 1)
  ; In real Zig IR this would be an error return path.
  ; BUG: returns an error-tagged value through a C function pointer
  ; that expects a plain pointer -> ABI mismatch
  %error_val = inttoptr i64 1 to ptr
  ret ptr %error_val
}

; ============================================================================
; Bug 08: slice.ptr + slice.len separated
; Zig slice (ptr + len) is decomposed into two arguments. C function
; only receives the pointer, uses it without knowing the length -> overread.
; ============================================================================
define void @zig_08_slice_len_lost() #0 {
entry:
  ; Allocate a small buffer (32 bytes)
  %buf = call ptr @zig_allocator_alloc(ptr null, i64 32)
  %is_null = icmp eq ptr %buf, null
  br i1 %is_null, label %done, label %fill

fill:
  call void @llvm.memset.p0.i64(ptr align 1 %buf, i8 90, i64 32, i1 false)
  ; Zig passes slice as (ptr, len) pair
  %slice_ptr = ptrtoint ptr %buf to i64
  ; BUG: C function only receives the pointer, not the length.
  ; It reads 256 bytes from a 32-byte buffer -> overread, potential info leak.
  call void @c_read_buffer_unbounded(ptr %buf, i64 256)
  call void @zig_allocator_free(ptr null, ptr %buf)
  br label %done

done:
  ret void
}

; ============================================================================
; Safe baseline: correct Zig allocator free
; ============================================================================
define void @zig_safe_allocator_match() #0 {
entry:
  %buf = call ptr @zig_allocator_alloc(ptr null, i64 128)
  %is_null = icmp eq ptr %buf, null
  br i1 %is_null, label %done, label %use

use:
  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %buf, ptr align 1 @.str.safe, i64 14, i1 false)
  ; Use the same allocator for free
  call void @zig_allocator_free(ptr null, ptr %buf)
  br label %done

done:
  ret void
}

; ============================================================================
; External declarations - Zig runtime / libc
; ============================================================================

declare ptr @os_mmap(ptr, i64, i32, i32, i32, i64)
declare i32 @os_munmap(ptr, i64)
declare ptr @zig_allocator_alloc(ptr, i64)
declare void @zig_allocator_free(ptr, ptr)
declare void @free(ptr)
declare ptr @malloc(i64)

; External declarations - C functions
declare void @c_process_buffer(ptr, i64)
declare void @c_write_past_sentinel(ptr, i64)
declare ptr @c_alloc_resource(i64)
declare void @c_use_resource(ptr)
declare void @c_free_resource(ptr)
declare void @c_read_as_i32_array(ptr, i64)
declare void @c_dereference_ptr(ptr)
declare void @c_may_free_string(ptr)
declare void @c_register_callback_ptr(ptr)
declare ptr @c_invoke_callback()
declare void @c_read_buffer_unbounded(ptr, i64)

; LLVM intrinsics
declare void @llvm.memset.p0.i64(ptr writeonly, i8, i64, i1 immarg)
declare void @llvm.memcpy.p0.p0.i64(ptr writeonly, ptr readonly, i64, i1 immarg)

; ============================================================================
; Function attributes and metadata
; ============================================================================

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" }

!llvm.module.flags = !{!0, !1, !2, !3}
!llvm.ident = !{!4}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 8, !"PIC Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 1}
!3 = !{i32 7, !"frame-pointer", i32 1}
!4 = !{!"zig 0.14.0"}
