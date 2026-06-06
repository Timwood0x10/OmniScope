; EXPECT: go_safe | no-issues | Go same-language, correct usage
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define void @main.main() {
  ret void
}

define void @runtime.mallocgc(i64 %size, ptr %typ, i1 %needzero) {
  ret ptr null
}