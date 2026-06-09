; EXPECT: rust_safe | no-issues | Rust same-language, correct handling
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @__rust_alloc(i64, i64)
declare void @__rust_dealloc(ptr, i64, i64)

define void @_RNvC1x3safe3alloc() {
  %p = call ptr @__rust_alloc(i64 100, i64 8)
  %is_null = icmp eq ptr %p, null
  br i1 %is_null, label %ret, label %use
use:
  store i64 42, ptr %p
  call void @__rust_dealloc(ptr %p, i64 100, i64 8)
  ret void
ret:
  ret void
}