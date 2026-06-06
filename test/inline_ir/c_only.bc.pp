target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i32 @c_function(i32 %x, i32 %y) {
  %add = add i32 %x, %y
  ret i32 %add
}

define void @helper(i32* %p) {
  store i32 42, i32* %p
  ret void
}

define i32 @main(i32 %argc, i8** %argv) {
  ret i32 0
}