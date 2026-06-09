; BUG: c_rust_leak | memory_leak | C malloc never freed in Rust context
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)

define void @rust_bridge() {
  %p = call ptr @malloc(i64 256)
  store i64 42, ptr %p
  ret void
}