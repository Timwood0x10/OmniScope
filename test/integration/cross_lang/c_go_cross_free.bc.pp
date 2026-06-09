; BUG: c_go_cross_free | cross_language_free | C malloc + Go CGo free
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)
declare void @_Cgo_free(ptr)

define void @c_cgo_call() {
  %p = call ptr @malloc(i64 64)
  %is_null = icmp eq ptr %p, null
  br i1 %is_null, label %ret, label %use
use:
  store i64 42, ptr %p
  call void @_Cgo_free(ptr %p)
  ret void
ret:
  ret void
}