; BUG: c_rust_cross_free_reverse | cross_language_free | __rust_alloc + C free
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @__rust_alloc(i64, i64)
declare void @free(ptr)

define void @c_bridge_free() {
  %p = call ptr @__rust_alloc(i64 100, i64 8)
  %is_null = icmp eq ptr %p, null
  br i1 %is_null, label %ret, label %use
use:
  store i64 42, ptr %p
  call void @free(ptr %p)
  ret void
ret:
  ret void
}