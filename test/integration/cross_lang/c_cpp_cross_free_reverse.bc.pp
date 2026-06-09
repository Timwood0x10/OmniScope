; BUG: c_cpp_cross_free_reverse | cross_language_free | operator new + C free
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @_Znwm(i64)
declare void @free(ptr)

define void @_Z4bad2() {
  %p = call ptr @_Znwm(i64 100)
  store i64 42, ptr %p
  call void @free(ptr %p)
  ret void
}