; EXPECT: c_zig_safe | no-issues | C+Zig mixed, no cross-language issues
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

declare ptr @malloc(i64)
declare void @free(ptr)

define i32 @c_func(i32 %x) {
  %r = add i32 %x, 1
  ret i32 %r
}

define void @zig_safe() {
  ret void
}