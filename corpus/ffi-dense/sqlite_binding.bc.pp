; ModuleID = 'sqlite_binding.c'
source_filename = "sqlite_binding.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

@.str = private unnamed_addr constant [20 x i8] c"SELECT * FROM users\00", align 1
@.str.1 = private unnamed_addr constant [36 x i8] c"INSERT INTO users (name) VALUES (?)\00", align 1
@.str.2 = private unnamed_addr constant [10 x i8] c"test_user\00", align 1
@.str.3 = private unnamed_addr constant [36 x i8] c"SELECT name FROM users WHERE id = ?\00", align 1
@.str.4 = private unnamed_addr constant [18 x i8] c"DELETE FROM users\00", align 1
@.str.5 = private unnamed_addr constant [38 x i8] c"SELECT * FROM users WHERE name = '%s'\00", align 1
@.str.6 = private unnamed_addr constant [31 x i8] c"SELECT name FROM users LIMIT 1\00", align 1
@.str.7 = private unnamed_addr constant [10 x i8] c"User: %s\0A\00", align 1
@.str.8 = private unnamed_addr constant [9 x i8] c":memory:\00", align 1
@.str.9 = private unnamed_addr constant [55 x i8] c"CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)\00", align 1
@.str.10 = private unnamed_addr constant [8 x i8] c"test.db\00", align 1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @leak_database_open(ptr noundef %0) #0 {
  %2 = alloca i32, align 4
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca i32, align 4
  store ptr %0, ptr %3, align 8
  %6 = load ptr, ptr %3, align 8
  %7 = call i32 @sqlite3_open(ptr noundef %6, ptr noundef %4)
  store i32 %7, ptr %5, align 4
  %8 = load i32, ptr %5, align 4
  %9 = icmp ne i32 %8, 0
  br i1 %9, label %10, label %11

10:                                               ; preds = %1
  store i32 -1, ptr %2, align 4
  br label %12

11:                                               ; preds = %1
  store i32 0, ptr %2, align 4
  br label %12

12:                                               ; preds = %11, %10
  %13 = load i32, ptr %2, align 4
  ret i32 %13
}

declare i32 @sqlite3_open(ptr noundef, ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @leak_statement(ptr noundef %0) #0 {
  %2 = alloca i32, align 4
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  %6 = alloca i32, align 4
  store ptr %0, ptr %3, align 8
  store ptr @.str, ptr %5, align 8
  %7 = load ptr, ptr %3, align 8
  %8 = load ptr, ptr %5, align 8
  %9 = call i32 @sqlite3_prepare_v2(ptr noundef %7, ptr noundef %8, i32 noundef -1, ptr noundef %4, ptr noundef null)
  store i32 %9, ptr %6, align 4
  %10 = load i32, ptr %6, align 4
  %11 = icmp ne i32 %10, 0
  br i1 %11, label %12, label %13

12:                                               ; preds = %1
  store i32 -1, ptr %2, align 4
  br label %16

13:                                               ; preds = %1
  %14 = load ptr, ptr %4, align 8
  %15 = call i32 @sqlite3_step(ptr noundef %14)
  store i32 0, ptr %2, align 4
  br label %16

16:                                               ; preds = %13, %12
  %17 = load i32, ptr %2, align 4
  ret i32 %17
}

declare i32 @sqlite3_prepare_v2(ptr noundef, ptr noundef, i32 noundef, ptr noundef, ptr noundef) #1

declare i32 @sqlite3_step(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @bind_dangling_pointer(ptr noundef %0) #0 {
  %2 = alloca ptr, align 8
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  store ptr @.str.1, ptr %4, align 8
  %6 = load ptr, ptr %2, align 8
  %7 = load ptr, ptr %4, align 8
  %8 = call i32 @sqlite3_prepare_v2(ptr noundef %6, ptr noundef %7, i32 noundef -1, ptr noundef %3, ptr noundef null)
  %9 = call ptr @malloc(i64 noundef 20) #5
  store ptr %9, ptr %5, align 8
  %10 = load ptr, ptr %5, align 8
  %11 = load ptr, ptr %5, align 8
  %12 = call i64 @llvm.objectsize.i64.p0(ptr %11, i1 false, i1 true, i1 false)
  %13 = call ptr @__strcpy_chk(ptr noundef %10, ptr noundef @.str.2, i64 noundef %12) #6
  %14 = load ptr, ptr %5, align 8
  call void @free(ptr noundef %14)
  %15 = load ptr, ptr %3, align 8
  %16 = load ptr, ptr %5, align 8
  %17 = call i32 @sqlite3_bind_text(ptr noundef %15, i32 noundef 1, ptr noundef %16, i32 noundef -1, ptr noundef inttoptr (i64 -1 to ptr))
  %18 = load ptr, ptr %3, align 8
  %19 = call i32 @sqlite3_finalize(ptr noundef %18)
  ret i32 0
}

; Function Attrs: allocsize(0)
declare ptr @malloc(i64 noundef) #2

; Function Attrs: nounwind
declare ptr @__strcpy_chk(ptr noundef, ptr noundef, i64 noundef) #3

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.objectsize.i64.p0(ptr, i1 immarg, i1 immarg, i1 immarg) #4

declare void @free(ptr noundef) #1

declare i32 @sqlite3_bind_text(ptr noundef, i32 noundef, ptr noundef, i32 noundef, ptr noundef) #1

declare i32 @sqlite3_finalize(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define ptr @get_user_name_dangling(ptr noundef %0, i32 noundef %1) #0 {
  %3 = alloca ptr, align 8
  %4 = alloca i32, align 4
  %5 = alloca ptr, align 8
  %6 = alloca ptr, align 8
  %7 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store i32 %1, ptr %4, align 4
  store ptr @.str.3, ptr %6, align 8
  %8 = load ptr, ptr %3, align 8
  %9 = load ptr, ptr %6, align 8
  %10 = call i32 @sqlite3_prepare_v2(ptr noundef %8, ptr noundef %9, i32 noundef -1, ptr noundef %5, ptr noundef null)
  %11 = load ptr, ptr %5, align 8
  %12 = load i32, ptr %4, align 4
  %13 = call i32 @sqlite3_bind_int(ptr noundef %11, i32 noundef 1, i32 noundef %12)
  %14 = load ptr, ptr %5, align 8
  %15 = call i32 @sqlite3_step(ptr noundef %14)
  %16 = load ptr, ptr %5, align 8
  %17 = call ptr @sqlite3_column_text(ptr noundef %16, i32 noundef 0)
  store ptr %17, ptr %7, align 8
  %18 = load ptr, ptr %5, align 8
  %19 = call i32 @sqlite3_finalize(ptr noundef %18)
  %20 = load ptr, ptr %7, align 8
  ret ptr %20
}

declare i32 @sqlite3_bind_int(ptr noundef, i32 noundef, i32 noundef) #1

declare ptr @sqlite3_column_text(ptr noundef, i32 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @dangerous_exec(ptr noundef %0) #0 {
  %2 = alloca ptr, align 8
  %3 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  store ptr @.str.4, ptr %3, align 8
  %4 = load ptr, ptr %2, align 8
  %5 = load ptr, ptr %3, align 8
  %6 = call i32 @sqlite3_exec(ptr noundef %4, ptr noundef %5, ptr noundef null, ptr noundef null, ptr noundef null)
  ret i32 0
}

declare i32 @sqlite3_exec(ptr noundef, ptr noundef, ptr noundef, ptr noundef, ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @sql_injection(ptr noundef %0, ptr noundef %1) #0 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca [256 x i8], align 1
  %6 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %7 = getelementptr inbounds [256 x i8], ptr %5, i64 0, i64 0
  %8 = load ptr, ptr %4, align 8
  %9 = call i32 (ptr, i32, i64, ptr, ...) @__sprintf_chk(ptr noundef %7, i32 noundef 0, i64 noundef 256, ptr noundef @.str.5, ptr noundef %8)
  store ptr null, ptr %6, align 8
  %10 = load ptr, ptr %3, align 8
  %11 = getelementptr inbounds [256 x i8], ptr %5, i64 0, i64 0
  %12 = call i32 @sqlite3_exec(ptr noundef %10, ptr noundef %11, ptr noundef null, ptr noundef null, ptr noundef %6)
  %13 = load ptr, ptr %6, align 8
  %14 = icmp ne ptr %13, null
  br i1 %14, label %15, label %17

15:                                               ; preds = %2
  %16 = load ptr, ptr %6, align 8
  call void @sqlite3_free(ptr noundef %16)
  br label %17

17:                                               ; preds = %15, %2
  ret i32 0
}

declare i32 @__sprintf_chk(ptr noundef, i32 noundef, i64 noundef, ptr noundef, ...) #1

declare void @sqlite3_free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @correct_usage(ptr noundef %0) #0 {
  %2 = alloca i32, align 4
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca i32, align 4
  %6 = alloca ptr, align 8
  %7 = alloca ptr, align 8
  %8 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  %9 = load ptr, ptr %3, align 8
  %10 = call i32 @sqlite3_open(ptr noundef %9, ptr noundef %4)
  store i32 %10, ptr %5, align 4
  %11 = load i32, ptr %5, align 4
  %12 = icmp ne i32 %11, 0
  br i1 %12, label %13, label %16

13:                                               ; preds = %1
  %14 = load ptr, ptr %4, align 8
  %15 = call i32 @sqlite3_close(ptr noundef %14)
  store i32 -1, ptr %2, align 4
  br label %39

16:                                               ; preds = %1
  store ptr @.str.6, ptr %7, align 8
  %17 = load ptr, ptr %4, align 8
  %18 = load ptr, ptr %7, align 8
  %19 = call i32 @sqlite3_prepare_v2(ptr noundef %17, ptr noundef %18, i32 noundef -1, ptr noundef %6, ptr noundef null)
  store i32 %19, ptr %5, align 4
  %20 = load i32, ptr %5, align 4
  %21 = icmp ne i32 %20, 0
  br i1 %21, label %22, label %25

22:                                               ; preds = %16
  %23 = load ptr, ptr %4, align 8
  %24 = call i32 @sqlite3_close(ptr noundef %23)
  store i32 -1, ptr %2, align 4
  br label %39

25:                                               ; preds = %16
  %26 = load ptr, ptr %6, align 8
  %27 = call i32 @sqlite3_step(ptr noundef %26)
  %28 = icmp eq i32 %27, 100
  br i1 %28, label %29, label %34

29:                                               ; preds = %25
  %30 = load ptr, ptr %6, align 8
  %31 = call ptr @sqlite3_column_text(ptr noundef %30, i32 noundef 0)
  store ptr %31, ptr %8, align 8
  %32 = load ptr, ptr %8, align 8
  %33 = call i32 (ptr, ...) @printf(ptr noundef @.str.7, ptr noundef %32)
  br label %34

34:                                               ; preds = %29, %25
  %35 = load ptr, ptr %6, align 8
  %36 = call i32 @sqlite3_finalize(ptr noundef %35)
  %37 = load ptr, ptr %4, align 8
  %38 = call i32 @sqlite3_close(ptr noundef %37)
  store i32 0, ptr %2, align 4
  br label %39

39:                                               ; preds = %34, %22, %13
  %40 = load i32, ptr %2, align 4
  ret i32 %40
}

declare i32 @sqlite3_close(ptr noundef) #1

declare i32 @printf(ptr noundef, ...) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @main() #0 {
  %1 = alloca i32, align 4
  %2 = alloca ptr, align 8
  store i32 0, ptr %1, align 4
  %3 = call i32 @sqlite3_open(ptr noundef @.str.8, ptr noundef %2)
  %4 = load ptr, ptr %2, align 8
  %5 = call i32 @sqlite3_exec(ptr noundef %4, ptr noundef @.str.9, ptr noundef null, ptr noundef null, ptr noundef null)
  %6 = call i32 @leak_database_open(ptr noundef @.str.10)
  %7 = load ptr, ptr %2, align 8
  %8 = call i32 @leak_statement(ptr noundef %7)
  %9 = load ptr, ptr %2, align 8
  %10 = call i32 @bind_dangling_pointer(ptr noundef %9)
  %11 = load ptr, ptr %2, align 8
  %12 = call i32 @dangerous_exec(ptr noundef %11)
  %13 = load ptr, ptr %2, align 8
  %14 = call i32 @sqlite3_close(ptr noundef %13)
  ret i32 0
}

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { allocsize(0) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #4 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #5 = { allocsize(0) }
attributes #6 = { nounwind }

!llvm.module.flags = !{!0, !1, !2, !3}
!llvm.ident = !{!4}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 8, !"PIC Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 1}
!3 = !{i32 7, !"frame-pointer", i32 1}
!4 = !{!"Homebrew clang version 21.1.8"}
