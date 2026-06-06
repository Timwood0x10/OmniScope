; EXPECT: c_rust_mixed_module | varies | Complex C+Rust mixed module
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)
declare void @free(ptr)

define i32 @c_helper(i32 %x) {
  %r = add i32 %x, 1
  ret i32 %r
}

define void @_RNvC1x3rust3func() {
  %p = call ptr @malloc(i64 64)
  %is_null = icmp eq ptr %p, null
  br i1 %is_null, label %ret, label %use
use:
  store i64 99, ptr %p
  call void @free(ptr %p)
  ret void
ret:
  ret void
}