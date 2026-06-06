; BUG: c_python_leak | memory_leak | Python C extension malloc without free
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)

define ptr @PyObject_leaky_op(ptr %self, ptr %args) {
  %p = call ptr @malloc(i64 128)
  store i64 99, ptr %p
  ret ptr %p
}