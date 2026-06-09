; BUG: c_leak | memory_leak | malloc without free
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)

define i32 @leaky() {
  %p = call ptr @malloc(i64 200)
  store i32 99, ptr %p
  %val = load i32, ptr %p
  ret i32 %val
}