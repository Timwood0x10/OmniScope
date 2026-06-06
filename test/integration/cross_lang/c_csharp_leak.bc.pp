; BUG: c_csharp_leak | memory_leak | C# managed code malloc without free
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)

define void @System_Collections_Leak() {
  %p = call ptr @malloc(i64 200)
  store i64 42, ptr %p
  ret void
}