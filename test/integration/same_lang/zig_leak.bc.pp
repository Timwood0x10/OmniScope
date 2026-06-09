; BUG: zig_leak | memory_leak | zig_alloc without free
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @zig_alloc(i64)

define void @zig_leaky() {
  %p = call ptr @zig_alloc(i64 200)
  store i64 99, ptr %p
  ret void
}