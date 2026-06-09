; EXPECT: safe_c | no-issues | C same-language, correct null checks and free
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)
declare void @free(ptr)
declare i32 @puts(ptr)

define i32 @safe_malloc_usage() {
  %p = call ptr @malloc(i64 100)
  %is_null = icmp eq ptr %p, null
  br i1 %is_null, label %ret, label %use
use:
  store i32 42, ptr %p
  %val = load i32, ptr %p
  call void @free(ptr %p)
  ret i32 %val
ret:
  ret i32 -1
}