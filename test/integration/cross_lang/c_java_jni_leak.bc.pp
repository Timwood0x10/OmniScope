; BUG: c_java_jni_leak | memory_leak | JNI malloc without free
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)

define void @Java_com_example_test_leak(ptr %env, ptr %obj) {
  %p = call ptr @malloc(i64 256)
  store i64 99, ptr %p
  ret void
}