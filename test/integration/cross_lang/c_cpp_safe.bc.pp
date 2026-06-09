; EXPECT: c_cpp_safe | no-issues | C and C++ mixed, independent alloc/free
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)
declare void @free(ptr)
declare ptr @_Znwm(i64)
declare void @_ZdlPv(ptr)

define i32 @c_function(i32 %x) {
  ret i32 %x
}

; C++ alloc with new, free with delete (same language = safe)
define void @_Z4cppv() {
  %p = call ptr @_Znwm(i64 100)
  %is_null = icmp eq ptr %p, null
  br i1 %is_null, label %ret, label %use
use:
  store i64 42, ptr %p
  call void @_ZdlPv(ptr %p)
  ret void
ret:
  ret void
}