; BUG: c_go_cgo_unsafe | ffi_unsafe_call | CGo calls C strcpy
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @strcpy(ptr, ptr)

define void @main.cgo_bridge(ptr %dst, ptr %src) {
  %r = call ptr @strcpy(ptr %dst, ptr %src)
  ret void
}