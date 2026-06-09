; EXPECT: python_safe | no-issues | Python same-language, correct usage
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)
declare void @free(ptr)

define void @PyInit_myextension() {
  ret void
}

define ptr @PyObject_GetAttr(ptr %obj, ptr %name) {
  %p = call ptr @malloc(i64 64)
  %is_null = icmp eq ptr %p, null
  br i1 %is_null, label %error, label %ok
ok:
  call void @free(ptr %p)
  ret ptr %p
error:
  ret ptr null
}