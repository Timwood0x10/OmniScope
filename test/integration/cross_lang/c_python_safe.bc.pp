; EXPECT: c_python_safe | no-issues | C+Python, no cross-language issues
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)
declare void @free(ptr)

define void @PyInit_myext() {
  ret void
}

define ptr @PyObject_safe_op(ptr %self, ptr %args) {
  %p = call ptr @malloc(i64 64)
  %is_null = icmp eq ptr %p, null
  br i1 %is_null, label %ret, label %use
use:
  store i64 42, ptr %p
  call void @free(ptr %p)
  ret ptr null
ret:
  ret ptr null
}