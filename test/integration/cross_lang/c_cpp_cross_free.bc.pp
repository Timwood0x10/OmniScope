; BUG: c_cpp_cross_free | cross_language_free | C malloc + C++ operator delete
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)
declare void @_ZdlPv(ptr)

define void @_Z4badv() {
  %p = call ptr @malloc(i64 100)
  %is_null = icmp eq ptr %p, null
  br i1 %is_null, label %ret, label %use
use:
  store i64 42, ptr %p
  call void @_ZdlPv(ptr %p)
  ret void
ret:
  ret void
}