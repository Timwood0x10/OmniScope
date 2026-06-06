; BUG: c_rust_unsafe_call | ffi_unsafe_call | Rust calls C strcpy via FFI
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @strcpy(ptr, ptr)

define void @_RNvC1x3bad3copy(ptr %dst, ptr %src) {
  %result = call ptr @strcpy(ptr %dst, ptr %src)
  ret void
}