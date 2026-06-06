; BUG: rust_null_deref | null_dereference | __rust_alloc used without null check
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @__rust_alloc(i64, i64)

define void @_RNvC1x3bad3alloc() {
  %p = call ptr @__rust_alloc(i64 100, i64 8)
  store i64 42, ptr %p
  ret void
}