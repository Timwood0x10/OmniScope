; BUG: c_use_after_free | use_after_free | free then deref
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)
declare void @free(ptr)

define i32 @use_after_free() {
  %p = call ptr @malloc(i64 100)
  store i32 42, ptr %p
  call void @free(ptr %p)
  %val = load i32, ptr %p
  ret i32 %val
}