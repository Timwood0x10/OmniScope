; ModuleID = 'csharp_ffi_edge_cases'
source_filename = "csharp_ffi_edge_cases.ll"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

; ============================================================================
; C# P/Invoke and Marshal Edge Cases
; Each function demonstrates a distinct cross-language FFI safety bug.
; ============================================================================

@.str.sensitive = private unnamed_addr constant [15 x i8] c"sensitive data\00", align 1
@.str.nested = private unnamed_addr constant [27 x i8] c"nested pointer target data\00", align 1
@.str.delegate_msg = private unnamed_addr constant [14 x i8] c"callback data\00", align 1
@.str.com_obj = private unnamed_addr constant [11 x i8] c"COM object\00", align 1
@.str.test = private unnamed_addr constant [10 x i8] c"test data\00", align 1

; ============================================================================
; Bug 01: Marshal.AllocHGlobal + free mismatch
; C# uses Marshal.AllocHGlobal (wraps LocalAlloc), C side calls free().
; Different allocators -> heap corruption or crash.
; ============================================================================
define void @cs_01_alloc_mismatch() #0 {
entry:
  %buf = call ptr @Marshal_AllocHGlobal(i64 256)
  %is_null = icmp eq ptr %buf, null
  br i1 %is_null, label %done, label %use

use:
  call void @llvm.memset.p0.i64(ptr align 1 %buf, i8 -85, i64 256, i1 false)
  ; BUG: C free() does not match Marshal.AllocHGlobal (LocalAlloc)
  call void @free(ptr %buf)
  br label %done

done:
  ret void
}

; ============================================================================
; Bug 02: GCHandle not freed
; GCHandle.Alloc pins a managed object so GC cannot move/collect it.
; If GCHandle.Free is never called, the pinned object leaks permanently.
; ============================================================================
define void @cs_02_gchandle_leak() #0 {
entry:
  ; Allocate managed object via runtime
  %obj = call ptr @RhpNewFast(i64 128)
  %is_null = icmp eq ptr %obj, null
  br i1 %is_null, label %done, label %pin

pin:
  ; Pin the object (prevents GC from relocating it)
  %handle = call i32 @GCHandle_Alloc(ptr %obj, i32 3)
  ; Write data into the pinned object
  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %obj, ptr align 1 @.str.sensitive, i64 15, i1 false)
  ; Pass pinned pointer to native code
  call void @native_process_data(ptr %obj, i64 15)
  ; BUG: GCHandle.Free never called -> GC can never collect this object
  br label %done

done:
  ret void
}

; ============================================================================
; Bug 03: P/Invoke callback after delegate collected
; C# delegate is passed as a function pointer to C. The delegate can be
; garbage-collected while C still holds the pointer. Next callback -> crash.
; ============================================================================
define void @cs_03_delegate_collected_callback() #0 {
entry:
  ; Create delegate wrapper (allocates a thunk/trampoline)
  %delegate_thunk = call ptr @Marshal_GetFunctionPointerForDelegate(ptr @managed_callback)
  %is_null = icmp eq ptr %delegate_thunk, null
  br i1 %is_null, label %done, label %pass_to_c

pass_to_c:
  ; Register callback with native code
  call void @native_register_callback(ptr %delegate_thunk)
  ; Force GC -- delegate may be collected because nothing references it strongly
  call void @GC_Collect(i32 2)
  ; BUG: native code will invoke the callback, but the delegate thunk
  ; has been reclaimed by GC -> crash or undefined behavior
  call void @native_trigger_callback()
  br label %done

done:
  ret void
}

; Internal: the managed callback target
define void @managed_callback(i32 %arg) #0 {
entry:
  ret void
}

; ============================================================================
; Bug 04: Marshal.StructureToPtr + nested pointers
; A struct containing a pointer field is marshaled via StructureToPtr.
; After the original managed object is GC'd, the nested pointer dangles.
; ============================================================================
%NestedStruct = type { i64, ptr, i32 }

define void @cs_04_structure_to_ptr_dangling() #0 {
entry:
  ; Allocate the "inner" target that the struct's pointer field references
  %inner = call ptr @Marshal_AllocHGlobal(i64 64)
  %inner_null = icmp eq ptr %inner, null
  br i1 %inner_null, label %done, label %setup

setup:
  ; Fill inner buffer
  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %inner, ptr align 1 @.str.nested, i64 26, i1 false)
  ; Allocate managed struct on GC heap
  %managed_struct = call ptr @RhpNewFast(i64 24)
  %struct_null = icmp eq ptr %managed_struct, null
  br i1 %struct_null, label %free_inner, label %fill_struct

fill_struct:
  ; Set struct fields: field0=42, field1=inner_ptr, field2=99
  %f0_ptr = getelementptr inbounds %NestedStruct, ptr %managed_struct, i32 0, i32 0
  store i64 42, ptr %f0_ptr
  %f1_ptr = getelementptr inbounds %NestedStruct, ptr %managed_struct, i32 0, i32 1
  store ptr %inner, ptr %f1_ptr
  %f2_ptr = getelementptr inbounds %NestedStruct, ptr %managed_struct, i32 0, i32 2
  store i32 99, ptr %f2_ptr
  ; Marshal.StructureToPtr copies struct to native buffer
  %native_buf = call ptr @Marshal_AllocHGlobal(i64 24)
  call void @Marshal_StructureToPtr(ptr %managed_struct, ptr %native_buf, i1 false)
  ; GC collects the managed struct -- the pointer field inside native_buf
  ; now points to memory the GC may reclaim
  call void @GC_Collect(i32 2)
  ; BUG: native_buf still contains a pointer into the (possibly freed) GC heap.
  ; Reading through that pointer is use-after-free.
  %dangling = load ptr, ptr getelementptr inbounds (%NestedStruct, ptr %native_buf, i32 0, i32 1)
  %val = load i8, ptr %dangling
  br label %cleanup

cleanup:
  call void @Marshal_FreeHGlobal(ptr %native_buf)
  br label %free_inner

free_inner:
  call void @Marshal_FreeHGlobal(ptr %inner)
  br label %done

done:
  ret void
}

; ============================================================================
; Bug 05: fixed statement + buffer overflow
; C# `fixed` pins an array in memory and passes a pointer to native code.
; Native code writes beyond the array bounds -> heap corruption.
; ============================================================================
define void @cs_05_fixed_buffer_overflow() #0 {
entry:
  ; Allocate a managed array (10 elements)
  %array = call ptr @RhpNewFast(i64 80)
  %is_null = icmp eq ptr %array, null
  br i1 %is_null, label %done, label %pin

pin:
  ; Pin the array (GC cannot move it)
  %handle = call i32 @GCHandle_Alloc(ptr %array, i32 3)
  ; Native function writes 256 bytes into a buffer only 80 bytes long
  ; BUG: buffer overflow - corrupts heap metadata or adjacent objects
  call void @native_write_overflow(ptr %array, i64 256)
  ; Unpin
  call void @GCHandle_Free(i32 %handle)
  br label %done

done:
  ret void
}

; ============================================================================
; Bug 06: Span<T> passed to native
; A Span is created from stack memory, its internal pointer passed to an
; async native call. When the function returns, the stack frame is reclaimed
; but the native code still uses the pointer -> use-after-scope.
; ============================================================================
define void @cs_06_span_stack_escape() #0 {
entry:
  ; Allocate a buffer on the "stack" (alloca)
  %stack_buf = alloca [128 x i8], align 16
  call void @llvm.memset.p0.i64(ptr align 16 %stack_buf, i8 0, i64 128, i1 false)
  ; Write some data into the stack buffer
  call void @llvm.memcpy.p0.p0.i64(ptr align 16 %stack_buf, ptr align 1 @.str.test, i64 10, i1 false)
  ; Pass the stack pointer to a native async function
  ; BUG: native_async_process may access stack_buf after this function returns
  call void @native_async_process(ptr %stack_buf, i64 128)
  ret void
}

; ============================================================================
; Bug 07: Marshal.GetDelegateForFunctionPtr + wrong calling convention
; A native function pointer is converted to a delegate, but the calling
; convention is wrong (stdcall vs cdecl). Stack is corrupted on return.
; ============================================================================
define void @cs_07_wrong_calling_convention() #0 {
entry:
  ; Get a native function pointer (assumed cdecl on Unix)
  %native_fn = call ptr @native_get_callback_ptr()
  %is_null = icmp eq ptr %native_fn, null
  br i1 %is_null, label %done, label %convert

convert:
  ; Convert to managed delegate (platform may expect different ABI)
  ; BUG: on Windows, if native uses stdell but Marshal assumes cdecl,
  ; the caller and callee disagree on who cleans up the stack -> corruption
  %delegate = call ptr @Marshal_GetDelegateForFunctionPtr(ptr %native_fn, i64 0)
  ; Invoke the delegate with arguments
  %result = call i32 %delegate(i32 42, i32 100, i32 7)
  br label %done

done:
  ret void
}

; ============================================================================
; Bug 08: COM interface + Release not called
; A COM object is obtained via P/Invoke but AddRef/Release lifecycle
; is not managed. Release() is never called -> COM reference leak.
; ============================================================================
define void @cs_08_com_release_leak() #0 {
entry:
  ; Create COM object (AddRef gives us refcount=1)
  %com_obj = call ptr @CoCreateInstance(ptr @.str.com_obj)
  %is_null = icmp eq ptr %com_obj, null
  br i1 %is_null, label %done, label %use

use:
  ; QueryInterface increments refcount to 2
  %iface = call ptr @COM_QueryInterface(ptr %com_obj, i64 1)
  ; Use the interface
  call void @COM_DoWork(ptr %iface)
  ; BUG: neither Release(com_obj) nor Release(iface) is ever called
  ; -> COM object and interface leak permanently
  br label %done

done:
  ret void
}

; ============================================================================
; Bug 09: CancellationToken not propagated to native blocking call
; Managed code has a CancellationToken that should cancel a long-running
; native call, but it is not wired through -> the native call blocks
; forever, leaking the thread.
; ============================================================================
define void @cs_09_cancellation_not_propagated() #0 {
entry:
  ; Create a cancellation token source
  %cts = call ptr @CancellationTokenSource_Create()
  %is_null = icmp eq ptr %cts, null
  br i1 %is_null, label %done, label %start

start:
  ; Get the token from the source
  %token = call ptr @CancellationTokenSource_get_Token(ptr %cts)
  ; Start a native blocking call on a background thread
  ; BUG: token is not passed to native_blocking_io, so there is no way
  ; to cancel it. If the caller wants to shut down, the thread leaks.
  call void @native_blocking_io(i64 -1)
  ; Cancel is requested but native code never checks it
  call void @CancellationTokenSource_Cancel(ptr %cts)
  ; Dispose the CTS
  call void @CancellationTokenSource_Dispose(ptr %cts)
  br label %done

done:
  ret void
}

; ============================================================================
; Bug 10: Marshal.AllocCoTaskMem + free() mismatch
; Memory allocated with AllocCoTaskMem (CoTaskMemAlloc) is freed with
; C's free() instead of CoTaskMemFree -> allocator mismatch.
; ============================================================================
define void @cs_10_cotaskmem_free_mismatch() #0 {
entry:
  ; Allocate via COM task memory allocator
  %buf = call ptr @CoTaskMemAlloc(i64 512)
  %is_null = icmp eq ptr %buf, null
  br i1 %is_null, label %done, label %use

use:
  call void @llvm.memset.p0.i64(ptr align 1 %buf, i8 -1, i64 512, i1 false)
  ; BUG: CoTaskMemAlloc memory freed with free() -- wrong allocator
  call void @free(ptr %buf)
  br label %done

done:
  ret void
}

; ============================================================================
; Safe baseline (no bug): correct AllocHGlobal + FreeHGlobal pair
; ============================================================================
define void @cs_safe_correct_pair() #0 {
entry:
  %buf = call ptr @Marshal_AllocHGlobal(i64 128)
  %is_null = icmp eq ptr %buf, null
  br i1 %is_null, label %done, label %use

use:
  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %buf, ptr align 1 @.str.test, i64 10, i1 false)
  call void @Marshal_FreeHGlobal(ptr %buf)
  br label %done

done:
  ret void
}

; ============================================================================
; External declarations
; ============================================================================

declare ptr @Marshal_AllocHGlobal(i64)
declare void @Marshal_FreeHGlobal(ptr)
declare ptr @CoTaskMemAlloc(i64)
declare void @CoTaskMemFree(ptr)
declare ptr @RhpNewFast(i64)
declare void @free(ptr)
declare i32 @GCHandle_Alloc(ptr, i32)
declare void @GCHandle_Free(i32)
declare ptr @Marshal_GetFunctionPointerForDelegate(ptr)
declare ptr @Marshal_GetDelegateForFunctionPtr(ptr, i64)
declare void @Marshal_StructureToPtr(ptr, ptr, i1)
declare void @GC_Collect(i32)
declare void @native_process_data(ptr, i64)
declare void @native_register_callback(ptr)
declare void @native_trigger_callback()
declare void @native_write_overflow(ptr, i64)
declare void @native_async_process(ptr, i64)
declare ptr @native_get_callback_ptr()
declare ptr @CoCreateInstance(ptr)
declare ptr @COM_QueryInterface(ptr, i64)
declare void @COM_DoWork(ptr)
declare ptr @CancellationTokenSource_Create()
declare ptr @CancellationTokenSource_get_Token(ptr)
declare void @CancellationTokenSource_Cancel(ptr)
declare void @CancellationTokenSource_Dispose(ptr)
declare void @native_blocking_io(i64)

; ============================================================================
; LLVM intrinsics
; ============================================================================

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
!4 = !{!"Homebrew clang version 21.1.8"}
