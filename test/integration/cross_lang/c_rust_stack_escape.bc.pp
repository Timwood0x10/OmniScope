; BUG: c_rust_stack_escape | stack_escape | stack ptr passed to Rust extern
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare void @_RNvC1x3ffi3call(ptr)

define void @c_bridge() {
  %buf = alloca i8, i64 64
  call void @_RNvC1x3ffi3call(ptr %buf)
  ret void
}