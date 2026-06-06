; BUG: go_null_deref | null_dereference | CGo malloc used without null check
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)

define void @main.callback() {
  %p = call ptr @malloc(i64 64)
  store i64 42, ptr %p
  ret void
}