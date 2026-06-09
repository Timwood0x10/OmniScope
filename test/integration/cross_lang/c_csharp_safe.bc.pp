; EXPECT: c_csharp_safe | no-issues | C+C# mixed, no cross-language issues
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)
declare void @free(ptr)

define void @System_Console_Write(ptr %msg) {
  ret void
}

define void @System_SafeOp() {
  %p = call ptr @malloc(i64 64)
  %is_null = icmp eq ptr %p, null
  br i1 %is_null, label %ret, label %use
use:
  store i64 42, ptr %p
  call void @free(ptr %p)
  ret void
ret:
  ret void
}