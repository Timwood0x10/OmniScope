; ModuleID = 'swift_ffi_edge_cases'
source_filename = "swift_ffi_edge_cases.ll"
target datalayout = "e-m:o-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

; ============================================================================
; Swift ARC and FFI Edge Cases
; Each function demonstrates a distinct cross-language FFI safety bug
; involving Swift's ARC, concurrency model, or bridging mechanisms.
; ============================================================================

; Swift runtime types
%swift.refcounted = type { ptr, i64 }
%swift.type = type { i64 }
%swift.full_existential_type = type { ptr, %swift.type }
%swift.weak = type { ptr }
%swift.unowned = type { ptr }
%Any = type { [24 x i8], ptr }

; Test object with a value field
%TestObject = type { %swift.refcounted, i64 }

; Opaque C struct used for retain cycle test
%COpaqueStruct = type { ptr, i64, ptr }

@.str.bug01 = private unnamed_addr constant [33 x i8] c"BUG-01: Unmanaged double release\00", align 8
@.str.bug02 = private unnamed_addr constant [31 x i8] c"BUG-02: withUnsafeBytes escape\00", align 8
@.str.bug03 = private unnamed_addr constant [30 x i8] c"BUG-03: fromOpaque wrong type\00", align 8
@.str.bug04 = private unnamed_addr constant [31 x i8] c"BUG-04: autoreleasepool escape\00", align 8
@.str.bug05 = private unnamed_addr constant [18 x i8] c"BUG-05: weak race\00", align 8
@.str.bug06 = private unnamed_addr constant [27 x i8] c"BUG-06: Sendable violation\00", align 8
@.str.bug07 = private unnamed_addr constant [21 x i8] c"BUG-07: retain cycle\00", align 8
@.str.bug08 = private unnamed_addr constant [39 x i8] c"BUG-08: withExtendedLifetime early ret\00", align 8
@.str.bug09 = private unnamed_addr constant [21 x i8] c"BUG-09: array escape\00", align 8
@.str.bug10 = private unnamed_addr constant [28 x i8] c"BUG-10: convention(c) throw\00", align 8
@.str.safe = private unnamed_addr constant [20 x i8] c"safe object release\00", align 8

; Global pointer that escapes closure scope
@g_escaped_ptr = hidden global ptr null, align 8

; ============================================================================
; Bug 01: Unmanaged.passRetained + double release
; Swift retains object for C via Unmanaged.passRetained, but C code also
; calls swift_release -> over-release -> use-after-free or crash.
; ============================================================================
define swiftcc void @swift_01_unmanaged_double_release() #0 {
entry:
  ; Allocate a Swift object (refcount = 1)
  %obj = call noalias ptr @swift_allocObject(ptr null, i64 24, i64 7)
  %refcnt_ptr = getelementptr inbounds %swift.refcounted, ptr %obj, i32 0, i32 1
  store i64 1, ptr %refcnt_ptr
  %value_ptr = getelementptr inbounds %TestObject, ptr %obj, i32 0, i32 1
  store i64 42, ptr %value_ptr

  ; Unmanaged.passRetained retains (refcount -> 2) and gives opaque pointer to C
  %opaque = call ptr @swift_retain(ptr %obj)
  ; C code receives the pointer and (incorrectly) also releases it
  call void @c_release_object(ptr %opaque)
  ; BUG: refcount is now 0 or corrupt. Swift still holds a reference,
  ; but the C release already freed the object.
  ; Swift's ARC release will be a use-after-free.
  call void @swift_release(ptr %obj)
  ret void
}

; ============================================================================
; Bug 02: withUnsafeBytes + escaping pointer
; withUnsafeBytes provides a temporary pointer valid only within the closure.
; If the pointer escapes via a global, it becomes dangling after the closure.
; ============================================================================
define swiftcc void @swift_02_withUnsafeBytes_escape() #0 {
entry:
  ; Create a buffer on the stack
  %stack_buf = alloca [64 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %stack_buf, i8 0, i64 64, i1 false)
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %stack_buf, ptr align 1 @.str.bug02, i64 36, i1 false)

  ; Simulate withUnsafeBytes: pass buffer pointer to a "closure"
  call void @escape_closure_body(ptr %stack_buf)

  ; BUG: @g_escaped_ptr now points into stack_buf.
  ; After this function returns, the stack frame is reclaimed.
  ; Any subsequent read through @g_escaped_ptr is use-after-scope.
  %escaped = load ptr, ptr @g_escaped_ptr
  %byte = load i8, ptr %escaped
  ret void
}

define internal void @escape_closure_body(ptr %ptr) #0 {
entry:
  ; Escapes the pointer to a global (this is the bug)
  store ptr %ptr, ptr @g_escaped_ptr
  ret void
}

; ============================================================================
; Bug 03: Unmanaged.fromOpaque on wrong type
; UnsafeMutableRawPointer is cast to the wrong Swift type via
; Unmanaged.fromOpaque. Reading the object interprets memory incorrectly.
; ============================================================================
%TypeA = type { %swift.refcounted, i64, i64 }
%TypeB = type { %swift.refcounted, i32 }

define swiftcc void @swift_03_fromOpaque_wrong_type() #0 {
entry:
  ; Allocate TypeA (size = 24 bytes)
  %obj_a = call noalias ptr @swift_allocObject(ptr null, i64 32, i64 7)
  %val_a0 = getelementptr inbounds %TypeA, ptr %obj_a, i32 0, i32 1
  store i64 999, ptr %val_a0
  %val_a1 = getelementptr inbounds %TypeA, ptr %obj_a, i32 0, i32 2
  store i64 1000, ptr %val_a1

  ; Get opaque pointer
  %opaque = call ptr @swift_retain(ptr %obj_a)

  ; BUG: cast opaque pointer to TypeB (smaller type, different layout)
  ; Reading typeB.value reads from the wrong offset -> type confusion
  %wrong_type = getelementptr inbounds %TypeB, ptr %opaque, i32 0, i32 1
  %confused_val = load i32, ptr %wrong_type

  call void @swift_release(ptr %obj_a)
  ret void
}

; ============================================================================
; Bug 04: autoreleasepool + escaped object
; Object created inside autoreleasepool block, pointer escapes via global.
; After the pool drains, the object is released -> dangling pointer.
; ============================================================================
define swiftcc void @swift_04_autoreleasepool_escape() #0 {
entry:
  ; Simulate autoreleasepool block
  call void @objc_autoreleasePoolPush()
  ; Create an autoreleased object
  %obj = call ptr @objc_autorelease(ptr @.str.bug04)
  ; BUG: store pointer to autoreleased object in a global
  store ptr %obj, ptr @g_escaped_ptr
  ; End of autoreleasepool -- all autoreleased objects are released
  call void @objc_autoreleasePoolPop()

  ; BUG: @g_escaped_ptr now points to a released object.
  ; Any use is use-after-free.
  %dangling = load ptr, ptr @g_escaped_ptr
  %byte = load i8, ptr %dangling
  ret void
}

; ============================================================================
; Bug 05: swift_weakLoadStrong + race
; Weak reference is loaded (strong ref acquired), but another thread
; releases the object between the load and the use -> use-after-free.
; ============================================================================
define swiftcc void @swift_05_weak_load_race() #0 {
entry:
  ; Allocate object
  %obj = call noalias ptr @swift_allocObject(ptr null, i64 24, i64 7)
  store i64 1, ptr getelementptr inbounds (%swift.refcounted, ptr %obj, i32 0, i32 1)

  ; Initialize weak reference
  %weak_ref = alloca ptr, align 8
  call void @swift_weakInit(ptr %weak_ref, ptr %obj)
  call void @swift_release(ptr %obj)

  ; Load strong reference from weak
  %strong = call ptr @swift_weakLoadStrong(ptr %weak_ref)
  %is_null = icmp eq ptr %strong, null
  br i1 %is_null, label %done, label %use

use:
  ; BUG: between swift_weakLoadStrong and this use, another thread
  ; could release the last strong reference. The strong pointer
  ; we loaded is now dangling. Race window: load -> use.
  %value_ptr = getelementptr inbounds %TestObject, ptr %strong, i32 0, i32 1
  %val = load i64, ptr %value_ptr
  call void @swift_release(ptr %strong)
  br label %done

done:
  call void @swift_weakDestroy(ptr %weak_ref)
  ret void
}

; ============================================================================
; Bug 06: Sendable violation + data race
; A non-Sendable object is shared across concurrency domains via a C
; callback. Both the Swift actor and the C callback thread access it
; concurrently -> data race.
; ============================================================================
define swiftcc void @swift_06_sendable_violation() #0 {
entry:
  ; Allocate a non-thread-safe object
  %obj = call noalias ptr @swift_allocObject(ptr null, i64 24, i64 7)
  store i64 1, ptr getelementptr inbounds (%swift.refcounted, ptr %obj, i32 0, i32 1)
  %value_ptr = getelementptr inbounds %TestObject, ptr %obj, i32 0, i32 1
  store i64 0, ptr %value_ptr

  ; Retain for sharing with C callback
  %retained = call ptr @swift_retain(ptr %obj)

  ; Launch a C thread that will modify the object
  call void @c_spawn_thread_modifying(ptr %retained)

  ; BUG: Swift code also modifies the same non-Sendable object concurrently.
  ; This is a data race: no synchronization between the C thread and here.
  store i64 999, ptr %value_ptr
  %read_back = load i64, ptr %value_ptr

  call void @swift_release(ptr %obj)
  ret void
}

; ============================================================================
; Bug 07: OpaquePointer + retain cycle
; Swift object holds OpaquePointer to C struct. C struct holds a callback
; pointer back to the Swift object. Neither side releases -> cycle/leak.
; ============================================================================
define swiftcc void @swift_07_opaque_retain_cycle() #0 {
entry:
  ; Allocate Swift wrapper object
  %swift_obj = call noalias ptr @swift_allocObject(ptr null, i64 24, i64 7)
  store i64 1, ptr getelementptr inbounds (%swift.refcounted, ptr %swift_obj, i32 0, i32 1)

  ; Allocate C struct
  %c_struct = call ptr @malloc(i64 24)

  ; Swift object holds pointer to C struct (field at offset 16)
  %c_ptr_field = getelementptr inbounds %TestObject, ptr %swift_obj, i32 0, i32 1
  store i64 ptrtoint (ptr %c_struct to i64), ptr %c_ptr_field

  ; C struct holds a callback pointer back to the Swift object
  %cb_field = getelementptr inbounds %COpaqueStruct, ptr %c_struct, i32 0, i32 0
  store ptr %swift_obj, ptr %cb_field
  ; C struct also retains the Swift object
  call ptr @swift_retain(ptr %swift_obj)

  ; BUG: retain cycle: Swift -> C struct -> Swift (strong ref).
  ; Neither side releases. Memory leaks permanently.
  ret void
}

; ============================================================================
; Bug 08: withExtendedLifetime + early return
; withExtendedLifetime is meant to keep an object alive, but an early
; return from the function bypasses it. C still holds a pointer -> UAF.
; ============================================================================
define swiftcc void @swift_08_extended_lifetime_early_return(i1 %should_return) #0 {
entry:
  ; Allocate object
  %obj = call noalias ptr @swift_allocObject(ptr null, i64 24, i64 7)
  store i64 1, ptr getelementptr inbounds (%swift.refcounted, ptr %obj, i32 0, i32 1)
  %value_ptr = getelementptr inbounds %TestObject, ptr %obj, i32 0, i32 1
  store i64 100, ptr %value_ptr

  ; Give pointer to C function
  call void @c_hold_pointer(ptr %obj)

  ; BUG: early return bypasses withExtendedLifetime
  br i1 %should_return, label %early_ret, label %continue

early_ret:
  ; Object may be released here, but C still holds the pointer
  call void @swift_release(ptr %obj)
  ret void

continue:
  ; withExtendedLifetime would normally keep %obj alive here
  ; ... do more work with C using the pointer ...
  call void @c_use_held_pointer()
  call void @swift_release(ptr %obj)
  ret void
}

; ============================================================================
; Bug 09: Bridging + Array lifetime
; Swift Array is bridged to NSArray, pointer to backing storage given to C.
; If the Array is mutated, backing storage is reallocated -> dangling.
; ============================================================================
define swiftcc void @swift_09_bridged_array_escape() #0 {
entry:
  ; Create a Swift Array (backed by contiguous storage)
  %buf = alloca [256 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %buf, i8 0, i64 256, i1 false)
  ; Fill buffer with test data
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %buf, ptr align 1 @.str.bug09, i64 30, i1 false)

  ; Get raw pointer to array's backing storage
  %storage_ptr = ptrtoint ptr %buf to i64
  ; Pass storage pointer to C
  call void @c_process_array_data(ptr %buf, i64 256)

  ; BUG: mutate the Array (append) which may reallocate backing storage
  ; C still holds the old pointer -> dangling after reallocation
  %new_buf = alloca [512 x i8], align 8
  call void @llvm.memset.p0.i64(ptr align 8 %new_buf, i8 0, i64 512, i1 false)
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %new_buf, ptr align 8 %buf, i64 256, i1 false)

  ; C's pointer now points to the old (freed) backing store
  call void @c_read_array_data(ptr %buf, i64 256)
  ret void
}

; ============================================================================
; Bug 10: @convention(c) + Swift error
; A Swift function marked @convention(c) throws an error, but the C ABI
; has no concept of Swift's error protocol. Error result is undefined.
; ============================================================================
define swiftcc void @swift_10_convention_c_throw() #0 {
entry:
  ; Register a @convention(c) function that internally throws
  call void @c_register_callback(ptr @convention_c_may_throw)
  ; Trigger the callback -- if it throws, the C ABI cannot represent the error
  call void @c_trigger_callback()
  ret void
}

; Simulated @convention(c) function that may throw
define i32 @convention_c_may_throw(i32 %input) #1 {
entry:
  %is_error = icmp slt i32 %input, 0
  br i1 %is_error, label %throw_path, label %ok_path

throw_path:
  ; BUG: Swift error thrown through C ABI boundary. C has no mechanism
  ; to receive Swift ErrorProtocol values. The error is lost or
  ; the function returns garbage -> undefined behavior.
  %error = call ptr @swift_allocError(ptr null, ptr null, ptr null, i32 0)
  ret i32 -1

ok_path:
  ret i32 %input
}

; ============================================================================
; Safe baseline: proper ARC management
; ============================================================================
define swiftcc void @swift_safe_arc_management() #0 {
entry:
  %obj = call noalias ptr @swift_allocObject(ptr null, i64 24, i64 7)
  store i64 1, ptr getelementptr inbounds (%swift.refcounted, ptr %obj, i32 0, i32 1)
  %value_ptr = getelementptr inbounds %TestObject, ptr %obj, i32 0, i32 1
  store i64 42, ptr %value_ptr

  ; Retain for C usage
  call ptr @swift_retain(ptr %obj)
  ; C uses it safely
  call void @c_release_object(ptr %obj)
  ; Release our reference
  call void @swift_release(ptr %obj)
  ret void
}

; ============================================================================
; External declarations - Swift runtime
; ============================================================================

declare noalias ptr @swift_allocObject(ptr, i64, i64)
declare ptr @swift_retain(ptr returned)
declare void @swift_release(ptr)
declare void @swift_weakInit(ptr, ptr)
declare void @swift_weakDestroy(ptr)
declare ptr @swift_weakLoadStrong(ptr)
declare void @swift_unownedRetain(ptr)
declare void @swift_unownedRelease(ptr)
declare ptr @swift_allocError(ptr, ptr, ptr, i32)
declare void @swift_bridgeObjectRetain(ptr)
declare void @swift_bridgeObjectRelease(ptr)
declare void @swift_deallocClassInstance(ptr, i64, i64)

; External declarations - Objective-C runtime
declare ptr @objc_autoreleasePoolPush()
declare void @objc_autoreleasePoolPop()
declare ptr @objc_autorelease(ptr)

; External declarations - C functions
declare void @c_release_object(ptr)
declare void @c_hold_pointer(ptr)
declare void @c_use_held_pointer()
declare void @c_spawn_thread_modifying(ptr)
declare void @c_process_array_data(ptr, i64)
declare void @c_read_array_data(ptr, i64)
declare void @c_register_callback(ptr)
declare void @c_trigger_callback()

; External declarations - libc
declare ptr @malloc(i64)
declare void @free(ptr)

; LLVM intrinsics
declare void @llvm.memset.p0.i64(ptr writeonly, i8, i64, i1 immarg)
declare void @llvm.memcpy.p0.p0.i64(ptr writeonly, ptr readonly, i64, i1 immarg)

; ============================================================================
; Function attributes and metadata
; ============================================================================

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" }
attributes #1 = { nounwind ssp "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" }

!llvm.module.flags = !{!0, !1, !2, !3}
!llvm.ident = !{!4}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 8, !"PIC Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 1}
!3 = !{i32 7, !"frame-pointer", i32 1}
!4 = !{!"Apple Swift version 6.0 (swiftlang-6.0.0.9.10 clang-1600.0.26.2)"}
