; BUG: python_leak | memory_leak | Python C API malloc without free
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)

define ptr @PyObject_Leaky(ptr %obj) {
  %p = call ptr @malloc(i64 256)
  store i64 42, ptr %p
  ret ptr %p
}