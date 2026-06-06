; EXPECT: zig_safe | no-issues | Zig same-language, correct alloc/free
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @zig_alloc(i64)
declare void @zig_free(ptr)

define void @zig_safe_usage() {
  %p = call ptr @zig_alloc(i64 100)
  %is_null = icmp eq ptr %p, null
  br i1 %is_null, label %ret, label %use
use:
  store i64 42, ptr %p
  call void @zig_free(ptr %p)
  ret void
ret:
  ret void
}