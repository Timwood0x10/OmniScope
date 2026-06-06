; BUG: c_stack_escape | stack_escape | alloca passed to external function
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare void @external_func(ptr)

define void @bad_stack_escape() {
  %buf = alloca i8, i64 64
  call void @external_func(ptr %buf)
  ret void
}