; BUG: zig_null_deref | null_dereference | zig_alloc used without null check
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @zig_alloc(i64)

define void @zig_bad_usage() {
  %p = call ptr @zig_alloc(i64 100)
  store i64 42, ptr %p
  ret void
}