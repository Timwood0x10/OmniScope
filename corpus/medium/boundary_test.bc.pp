; ModuleID = 'boundary_test.c'
source_filename = "boundary_test.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

%struct.Node = type { ptr, ptr }

@.str = private unnamed_addr constant [12 x i8] c"safe string\00", align 1
@.str.1 = private unnamed_addr constant [2 x i8] c"a\00", align 1
@.str.2 = private unnamed_addr constant [37 x i8] c"very long string that might overflow\00", align 1
@global_ffi_ptr = global ptr null, align 8

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @null_ptr_ffi_boundary() #0 {
  %1 = alloca ptr, align 8
  store ptr null, ptr %1, align 8
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %1)
  %2 = load ptr, ptr %1, align 8
  %3 = icmp ne ptr %2, null
  br i1 %3, label %4, label %6

4:                                                ; preds = %0
  %5 = load ptr, ptr %1, align 8
  call void @_RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr noundef %5)
  br label %6

6:                                                ; preds = %4, %0
  ret void
}

declare void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef) #1

declare void @_RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @zero_size_alloc() #0 {
  %1 = alloca ptr, align 8
  call void @zig_allocator_allocImpl(ptr noundef %1, i64 noundef 0)
  %2 = load ptr, ptr %1, align 8
  %3 = icmp ne ptr %2, null
  br i1 %3, label %4, label %6

4:                                                ; preds = %0
  %5 = load ptr, ptr %1, align 8
  call void @zig_allocator_freeImpl(ptr noundef %5)
  br label %6

6:                                                ; preds = %4, %0
  ret void
}

declare void @zig_allocator_allocImpl(ptr noundef, i64 noundef) #1

declare void @zig_allocator_freeImpl(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @max_size_alloc() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca i64, align 8
  store i64 -1, ptr %2, align 8
  %3 = load i64, ptr %2, align 8
  call void @zig_allocator_allocImpl(ptr noundef %1, i64 noundef %3)
  %4 = load ptr, ptr %1, align 8
  %5 = icmp ne ptr %4, null
  br i1 %5, label %6, label %8

6:                                                ; preds = %0
  %7 = load ptr, ptr %1, align 8
  call void @zig_allocator_freeImpl(ptr noundef %7)
  br label %8

8:                                                ; preds = %6, %0
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @negative_size_alloc() #0 {
  %1 = alloca ptr, align 8
  call void @zig_allocator_allocImpl(ptr noundef %1, i64 noundef -1)
  %2 = load ptr, ptr %1, align 8
  %3 = icmp ne ptr %2, null
  br i1 %3, label %4, label %6

4:                                                ; preds = %0
  %5 = load ptr, ptr %1, align 8
  call void @zig_allocator_freeImpl(ptr noundef %5)
  br label %6

6:                                                ; preds = %4, %0
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @buffer_near_overflow() #0 {
  %1 = alloca ptr, align 8
  %2 = call ptr @malloc(i64 noundef 100) #7
  store ptr %2, ptr %1, align 8
  %3 = load ptr, ptr %1, align 8
  %4 = icmp eq ptr %3, null
  br i1 %4, label %5, label %6

5:                                                ; preds = %0
  br label %18

6:                                                ; preds = %0
  %7 = load ptr, ptr %1, align 8
  %8 = load ptr, ptr %1, align 8
  %9 = call i64 @llvm.objectsize.i64.p0(ptr %8, i1 false, i1 true, i1 false)
  %10 = call ptr @__strcpy_chk(ptr noundef %7, ptr noundef @.str, i64 noundef %9) #8
  %11 = load ptr, ptr %1, align 8
  %12 = load ptr, ptr %1, align 8
  %13 = call i64 @llvm.objectsize.i64.p0(ptr %12, i1 false, i1 true, i1 false)
  %14 = call ptr @__strncpy_chk(ptr noundef %11, ptr noundef @.str.1, i64 noundef 99, i64 noundef %13) #8
  %15 = load ptr, ptr %1, align 8
  %16 = getelementptr inbounds i8, ptr %15, i64 99
  store i8 0, ptr %16, align 1
  %17 = load ptr, ptr %1, align 8
  call void @free(ptr noundef %17)
  br label %18

18:                                               ; preds = %6, %5
  ret void
}

; Function Attrs: allocsize(0)
declare ptr @malloc(i64 noundef) #2

; Function Attrs: nounwind
declare ptr @__strcpy_chk(ptr noundef, ptr noundef, i64 noundef) #3

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.objectsize.i64.p0(ptr, i1 immarg, i1 immarg, i1 immarg) #4

; Function Attrs: nounwind
declare ptr @__strncpy_chk(ptr noundef, ptr noundef, i64 noundef, i64 noundef) #3

declare void @free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @buffer_at_overflow() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca [101 x i8], align 1
  %3 = call ptr @malloc(i64 noundef 100) #7
  store ptr %3, ptr %1, align 8
  %4 = load ptr, ptr %1, align 8
  %5 = icmp eq ptr %4, null
  br i1 %5, label %6, label %7

6:                                                ; preds = %0
  br label %16

7:                                                ; preds = %0
  %8 = getelementptr inbounds [101 x i8], ptr %2, i64 0, i64 0
  call void @llvm.memset.p0.i64(ptr align 1 %8, i8 65, i64 100, i1 false)
  %9 = getelementptr inbounds [101 x i8], ptr %2, i64 0, i64 100
  store i8 0, ptr %9, align 1
  %10 = load ptr, ptr %1, align 8
  %11 = getelementptr inbounds [101 x i8], ptr %2, i64 0, i64 0
  %12 = load ptr, ptr %1, align 8
  %13 = call i64 @llvm.objectsize.i64.p0(ptr %12, i1 false, i1 true, i1 false)
  %14 = call ptr @__strcpy_chk(ptr noundef %10, ptr noundef %11, i64 noundef %13) #8
  %15 = load ptr, ptr %1, align 8
  call void @free(ptr noundef %15)
  br label %16

16:                                               ; preds = %7, %6
  ret void
}

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: write)
declare void @llvm.memset.p0.i64(ptr writeonly captures(none), i8, i64, i1 immarg) #5

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define ptr @create_circular_ownership() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca ptr, align 8
  %3 = alloca ptr, align 8
  %4 = call ptr @malloc(i64 noundef 16) #7
  store ptr %4, ptr %2, align 8
  %5 = call ptr @malloc(i64 noundef 16) #7
  store ptr %5, ptr %3, align 8
  %6 = load ptr, ptr %2, align 8
  %7 = icmp eq ptr %6, null
  br i1 %7, label %11, label %8

8:                                                ; preds = %0
  %9 = load ptr, ptr %3, align 8
  %10 = icmp eq ptr %9, null
  br i1 %10, label %11, label %22

11:                                               ; preds = %8, %0
  %12 = load ptr, ptr %2, align 8
  %13 = icmp ne ptr %12, null
  br i1 %13, label %14, label %16

14:                                               ; preds = %11
  %15 = load ptr, ptr %2, align 8
  call void @free(ptr noundef %15)
  br label %16

16:                                               ; preds = %14, %11
  %17 = load ptr, ptr %3, align 8
  %18 = icmp ne ptr %17, null
  br i1 %18, label %19, label %21

19:                                               ; preds = %16
  %20 = load ptr, ptr %3, align 8
  call void @free(ptr noundef %20)
  br label %21

21:                                               ; preds = %19, %16
  store ptr null, ptr %1, align 8
  br label %34

22:                                               ; preds = %8
  %23 = load ptr, ptr %2, align 8
  %24 = getelementptr inbounds nuw %struct.Node, ptr %23, i32 0, i32 1
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %24)
  %25 = load ptr, ptr %3, align 8
  %26 = getelementptr inbounds nuw %struct.Node, ptr %25, i32 0, i32 1
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %26)
  %27 = load ptr, ptr %3, align 8
  %28 = load ptr, ptr %2, align 8
  %29 = getelementptr inbounds nuw %struct.Node, ptr %28, i32 0, i32 0
  store ptr %27, ptr %29, align 8
  %30 = load ptr, ptr %2, align 8
  %31 = load ptr, ptr %3, align 8
  %32 = getelementptr inbounds nuw %struct.Node, ptr %31, i32 0, i32 0
  store ptr %30, ptr %32, align 8
  %33 = load ptr, ptr %2, align 8
  store ptr %33, ptr %1, align 8
  br label %34

34:                                               ; preds = %22, %21
  %35 = load ptr, ptr %1, align 8
  ret ptr %35
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @ffi_double_free() #0 {
  %1 = alloca ptr, align 8
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %1)
  %2 = load ptr, ptr %1, align 8
  %3 = icmp ne ptr %2, null
  br i1 %3, label %4, label %7

4:                                                ; preds = %0
  %5 = load ptr, ptr %1, align 8
  call void @_RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr noundef %5)
  %6 = load ptr, ptr %1, align 8
  call void @_RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr noundef %6)
  br label %7

7:                                                ; preds = %4, %0
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @ffi_use_after_free() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca ptr, align 8
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %1)
  %3 = load ptr, ptr %1, align 8
  %4 = icmp ne ptr %3, null
  br i1 %4, label %5, label %9

5:                                                ; preds = %0
  %6 = load ptr, ptr %1, align 8
  call void @_RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr noundef %6)
  %7 = load ptr, ptr %1, align 8
  store ptr %7, ptr %2, align 8
  %8 = load ptr, ptr %2, align 8
  br label %9

9:                                                ; preds = %5, %0
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @ownership_transfer_to_null() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca ptr, align 8
  store ptr null, ptr %2, align 8
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %1)
  %3 = load ptr, ptr %2, align 8
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %3)
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @ffi_in_error_path(i32 noundef %0) #0 {
  %2 = alloca i32, align 4
  %3 = alloca i32, align 4
  %4 = alloca ptr, align 8
  store i32 %0, ptr %3, align 4
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %4)
  %5 = load i32, ptr %3, align 4
  %6 = icmp ne i32 %5, 0
  br i1 %6, label %7, label %8

7:                                                ; preds = %1
  store i32 -1, ptr %2, align 4
  br label %10

8:                                                ; preds = %1
  %9 = load ptr, ptr %4, align 8
  call void @_RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr noundef %9)
  store i32 0, ptr %2, align 4
  br label %10

10:                                               ; preds = %8, %7
  %11 = load i32, ptr %2, align 4
  ret i32 %11
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @nested_ffi_partial_cleanup() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca ptr, align 8
  %3 = alloca ptr, align 8
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %1)
  call void @zig_allocator_allocImpl(ptr noundef %2, i64 noundef 64)
  call void @_cgo_allocate(ptr noundef %3, i64 noundef 64)
  %4 = load ptr, ptr %1, align 8
  %5 = icmp ne ptr %4, null
  br i1 %5, label %6, label %8

6:                                                ; preds = %0
  %7 = load ptr, ptr %1, align 8
  call void @_RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr noundef %7)
  br label %8

8:                                                ; preds = %6, %0
  ret void
}

declare void @_cgo_allocate(ptr noundef, i64 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @ffi_loop_early_exit(i32 noundef %0, i32 noundef %1) #0 {
  %3 = alloca i32, align 4
  %4 = alloca i32, align 4
  %5 = alloca i32, align 4
  %6 = alloca ptr, align 8
  store i32 %0, ptr %3, align 4
  store i32 %1, ptr %4, align 4
  store i32 0, ptr %5, align 4
  br label %7

7:                                                ; preds = %22, %2
  %8 = load i32, ptr %5, align 4
  %9 = load i32, ptr %3, align 4
  %10 = icmp slt i32 %8, %9
  br i1 %10, label %11, label %25

11:                                               ; preds = %7
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %6)
  %12 = load i32, ptr %5, align 4
  %13 = load i32, ptr %4, align 4
  %14 = icmp eq i32 %12, %13
  br i1 %14, label %15, label %16

15:                                               ; preds = %11
  br label %25

16:                                               ; preds = %11
  %17 = load ptr, ptr %6, align 8
  %18 = icmp ne ptr %17, null
  br i1 %18, label %19, label %21

19:                                               ; preds = %16
  %20 = load ptr, ptr %6, align 8
  call void @_RZN4core4drop9drop_in_place17hba3a1b2c3d4e5f6g(ptr noundef %20)
  br label %21

21:                                               ; preds = %19, %16
  br label %22

22:                                               ; preds = %21
  %23 = load i32, ptr %5, align 4
  %24 = add nsw i32 %23, 1
  store i32 %24, ptr %5, align 4
  br label %7, !llvm.loop !5

25:                                               ; preds = %15, %7
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @mixed_allocation_sources() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca ptr, align 8
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %1)
  call void @zig_allocator_allocImpl(ptr noundef %2, i64 noundef 64)
  call void @_cgo_allocate(ptr noundef %3, i64 noundef 64)
  %5 = call ptr @malloc(i64 noundef 64) #7
  store ptr %5, ptr %4, align 8
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @ffi_format_string() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca ptr, align 8
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %1)
  %3 = load ptr, ptr %1, align 8
  store ptr %3, ptr %2, align 8
  %4 = load ptr, ptr %2, align 8
  %5 = call i32 (ptr, ...) @printf(ptr noundef %4)
  ret void
}

declare i32 @printf(ptr noundef, ...) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @ffi_buffer_overflow() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca ptr, align 8
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %1)
  %3 = load ptr, ptr %1, align 8
  store ptr %3, ptr %2, align 8
  %4 = load ptr, ptr %2, align 8
  %5 = icmp ne ptr %4, null
  br i1 %5, label %6, label %11

6:                                                ; preds = %0
  %7 = load ptr, ptr %2, align 8
  %8 = load ptr, ptr %2, align 8
  %9 = call i64 @llvm.objectsize.i64.p0(ptr %8, i1 false, i1 true, i1 false)
  %10 = call ptr @__strcpy_chk(ptr noundef %7, ptr noundef @.str.2, i64 noundef %9) #8
  br label %11

11:                                               ; preds = %6, %0
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @allocation_size_overflow() #0 {
  %1 = alloca i64, align 8
  %2 = alloca ptr, align 8
  store i64 4611686018427387903, ptr %1, align 8
  %3 = load i64, ptr %1, align 8
  %4 = mul i64 %3, 4
  %5 = call ptr @malloc(i64 noundef %4) #7
  store ptr %5, ptr %2, align 8
  %6 = load ptr, ptr %2, align 8
  %7 = icmp ne ptr %6, null
  br i1 %7, label %8, label %10

8:                                                ; preds = %0
  %9 = load ptr, ptr %2, align 8
  call void @free(ptr noundef %9)
  br label %10

10:                                               ; preds = %8, %0
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @ffi_realloc() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca ptr, align 8
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %1)
  %3 = load ptr, ptr %1, align 8
  %4 = icmp ne ptr %3, null
  br i1 %4, label %5, label %9

5:                                                ; preds = %0
  %6 = load ptr, ptr %1, align 8
  %7 = call ptr @realloc(ptr noundef %6, i64 noundef 128) #9
  store ptr %7, ptr %2, align 8
  %8 = load ptr, ptr %2, align 8
  br label %9

9:                                                ; preds = %5, %0
  ret void
}

; Function Attrs: allocsize(1)
declare ptr @realloc(ptr noundef, i64 noundef) #6

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define ptr @ffi_ptr_escape() #0 {
  %1 = alloca ptr, align 8
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %1)
  %2 = load ptr, ptr %1, align 8
  ret ptr %2
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @store_ffi_ptr_global() #0 {
  %1 = alloca ptr, align 8
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %1)
  %2 = load ptr, ptr %1, align 8
  store ptr %2, ptr @global_ffi_ptr, align 8
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @concurrent_ffi_allocs() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca ptr, align 8
  %3 = alloca ptr, align 8
  call void @_RZN4alloc5alloc17hba3a1b2c3d4e5f6g(ptr noundef %1)
  call void @zig_allocator_allocImpl(ptr noundef %2, i64 noundef 64)
  call void @_cgo_allocate(ptr noundef %3, i64 noundef 64)
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @main() #0 {
  %1 = alloca i32, align 4
  %2 = alloca ptr, align 8
  store i32 0, ptr %1, align 4
  call void @null_ptr_ffi_boundary()
  call void @zero_size_alloc()
  call void @max_size_alloc()
  call void @negative_size_alloc()
  call void @buffer_near_overflow()
  call void @buffer_at_overflow()
  %3 = call ptr @create_circular_ownership()
  store ptr %3, ptr %2, align 8
  %4 = load ptr, ptr %2, align 8
  %5 = icmp ne ptr %4, null
  br i1 %5, label %6, label %8

6:                                                ; preds = %0
  %7 = load ptr, ptr %2, align 8
  call void @free(ptr noundef %7)
  br label %8

8:                                                ; preds = %6, %0
  call void @ffi_double_free()
  call void @ffi_use_after_free()
  call void @ownership_transfer_to_null()
  %9 = call i32 @ffi_in_error_path(i32 noundef 1)
  call void @nested_ffi_partial_cleanup()
  call void @ffi_loop_early_exit(i32 noundef 10, i32 noundef 5)
  call void @mixed_allocation_sources()
  call void @ffi_format_string()
  call void @ffi_buffer_overflow()
  call void @allocation_size_overflow()
  call void @ffi_realloc()
  %10 = call ptr @ffi_ptr_escape()
  call void @store_ffi_ptr_global()
  call void @concurrent_ffi_allocs()
  ret i32 0
}

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { allocsize(0) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #4 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #5 = { nocallback nofree nounwind willreturn memory(argmem: write) }
attributes #6 = { allocsize(1) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #7 = { allocsize(0) }
attributes #8 = { nounwind }
attributes #9 = { allocsize(1) }

!llvm.module.flags = !{!0, !1, !2, !3}
!llvm.ident = !{!4}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 8, !"PIC Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 1}
!3 = !{i32 7, !"frame-pointer", i32 1}
!4 = !{!"Homebrew clang version 21.1.8"}
!5 = distinct !{!5, !6}
!6 = !{!"llvm.loop.mustprogress"}
