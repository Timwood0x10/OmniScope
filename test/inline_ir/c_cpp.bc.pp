target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i32 @c_function(i32 %x) {
  ret i32 %x
}

define i32 @_Z3fooi(i32 %x) {
  ret i32 %x
}

define i8* @__cxa_allocate_exception(i64 %size) {
  ret i8* null
}