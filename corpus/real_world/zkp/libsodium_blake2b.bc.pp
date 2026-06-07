; ModuleID = 'src/libsodium/crypto_generichash/blake2b/ref/blake2b-ref.c'
source_filename = "src/libsodium/crypto_generichash/blake2b/ref/blake2b-ref.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

%struct.blake2b_state = type <{ [8 x i64], [2 x i64], [2 x i64], [256 x i8], i64, i8 }>

@__func__._sodium_blake2b_final = private unnamed_addr constant [22 x i8] c"_sodium_blake2b_final\00", align 1
@.str = private unnamed_addr constant [14 x i8] c"blake2b-ref.c\00", align 1
@.str.1 = private unnamed_addr constant [32 x i8] c"S->buflen <= BLAKE2B_BLOCKBYTES\00", align 1
@blake2b_IV = internal unnamed_addr constant [8 x i64] [i64 7640891576956012808, i64 -4942790177534073029, i64 4354685564936845355, i64 -6534734903238641935, i64 5840696475078001361, i64 -7276294671716946913, i64 2270897969802886507, i64 6620516959819538809], align 8

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define noundef i32 @_sodium_blake2b_init_param(ptr noundef initializes((0, 64)) %0, ptr noundef readonly captures(none) %1) local_unnamed_addr #0 {
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) @blake2b_IV, i64 64, i1 false), !tbaa !5
  %3 = getelementptr inbounds nuw i8, ptr %0, i64 64
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(297) %3, i8 noundef 0, i64 noundef 297, i1 noundef false) #10
  %4 = load i64, ptr %1, align 1
  %5 = xor i64 %4, 7640891576956012808
  store i64 %5, ptr %0, align 1, !tbaa !5
  %6 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %7 = load i64, ptr %6, align 1
  %8 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %9 = xor i64 %7, -4942790177534073029
  store i64 %9, ptr %8, align 1, !tbaa !5
  %10 = getelementptr inbounds nuw i8, ptr %1, i64 16
  %11 = load i64, ptr %10, align 1
  %12 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %13 = xor i64 %11, 4354685564936845355
  store i64 %13, ptr %12, align 1, !tbaa !5
  %14 = getelementptr inbounds nuw i8, ptr %1, i64 24
  %15 = load i64, ptr %14, align 1
  %16 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %17 = xor i64 %15, -6534734903238641935
  store i64 %17, ptr %16, align 1, !tbaa !5
  %18 = getelementptr inbounds nuw i8, ptr %1, i64 32
  %19 = load i64, ptr %18, align 1
  %20 = getelementptr inbounds nuw i8, ptr %0, i64 32
  %21 = xor i64 %19, 5840696475078001361
  store i64 %21, ptr %20, align 1, !tbaa !5
  %22 = getelementptr inbounds nuw i8, ptr %1, i64 40
  %23 = load i64, ptr %22, align 1
  %24 = getelementptr inbounds nuw i8, ptr %0, i64 40
  %25 = xor i64 %23, -7276294671716946913
  store i64 %25, ptr %24, align 1, !tbaa !5
  %26 = getelementptr inbounds nuw i8, ptr %1, i64 48
  %27 = load i64, ptr %26, align 1
  %28 = getelementptr inbounds nuw i8, ptr %0, i64 48
  %29 = xor i64 %27, 2270897969802886507
  store i64 %29, ptr %28, align 1, !tbaa !5
  %30 = getelementptr inbounds nuw i8, ptr %1, i64 56
  %31 = load i64, ptr %30, align 1
  %32 = getelementptr inbounds nuw i8, ptr %0, i64 56
  %33 = xor i64 %31, 6620516959819538809
  store i64 %33, ptr %32, align 1, !tbaa !5
  ret i32 0
}

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr captures(none)) #1

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr captures(none)) #1

; Function Attrs: nounwind ssp uwtable(sync)
define noundef i32 @_sodium_blake2b_init(ptr noundef %0, i8 noundef zeroext %1) local_unnamed_addr #2 {
  %3 = add i8 %1, -65
  %4 = icmp ult i8 %3, -64
  br i1 %4, label %5, label %6

5:                                                ; preds = %2
  tail call void @sodium_misuse() #11
  unreachable

6:                                                ; preds = %2
  %7 = zext nneg i8 %1 to i64
  %8 = getelementptr inbounds nuw i8, ptr %0, i64 64
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(297) %8, i8 noundef 0, i64 noundef 297, i1 noundef false) #10
  %9 = xor i64 %7, 7640891576939301128
  store i64 %9, ptr %0, align 1, !tbaa !5
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 8
  store <2 x i64> <i64 -4942790177534073029, i64 4354685564936845355>, ptr %10, align 1, !tbaa !5
  %11 = getelementptr inbounds nuw i8, ptr %0, i64 24
  store <2 x i64> <i64 -6534734903238641935, i64 5840696475078001361>, ptr %11, align 1, !tbaa !5
  %12 = getelementptr inbounds nuw i8, ptr %0, i64 40
  store <2 x i64> <i64 -7276294671716946913, i64 2270897969802886507>, ptr %12, align 1, !tbaa !5
  %13 = getelementptr inbounds nuw i8, ptr %0, i64 56
  store i64 6620516959819538809, ptr %13, align 1, !tbaa !5
  ret i32 0
}

; Function Attrs: noreturn
declare void @sodium_misuse() local_unnamed_addr #3

; Function Attrs: mustprogress nocallback nofree nounwind willreturn memory(argmem: write)
declare void @llvm.memset.p0.i64(ptr writeonly captures(none), i8, i64, i1 immarg) #4

; Function Attrs: nounwind ssp uwtable(sync)
define noundef i32 @_sodium_blake2b_init_salt_personal(ptr noundef %0, i8 noundef zeroext %1, ptr noundef readonly captures(address_is_null) %2, ptr noundef readonly captures(address_is_null) %3) local_unnamed_addr #2 {
  %5 = add i8 %1, -65
  %6 = icmp ult i8 %5, -64
  br i1 %6, label %7, label %8

7:                                                ; preds = %4
  tail call void @sodium_misuse() #11
  unreachable

8:                                                ; preds = %4
  %9 = icmp eq ptr %2, null
  br i1 %9, label %13, label %10

10:                                               ; preds = %8
  %11 = load <2 x i64>, ptr %2, align 1
  %12 = xor <2 x i64> %11, <i64 5840696475078001361, i64 -7276294671716946913>
  br label %13

13:                                               ; preds = %8, %10
  %14 = phi <2 x i64> [ %12, %10 ], [ <i64 5840696475078001361, i64 -7276294671716946913>, %8 ]
  %15 = icmp eq ptr %3, null
  br i1 %15, label %19, label %16

16:                                               ; preds = %13
  %17 = load <2 x i64>, ptr %3, align 1
  %18 = xor <2 x i64> %17, <i64 2270897969802886507, i64 6620516959819538809>
  br label %19

19:                                               ; preds = %13, %16
  %20 = phi <2 x i64> [ %18, %16 ], [ <i64 2270897969802886507, i64 6620516959819538809>, %13 ]
  %21 = zext nneg i8 %1 to i64
  %22 = getelementptr inbounds nuw i8, ptr %0, i64 64
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(297) %22, i8 noundef 0, i64 noundef 297, i1 noundef false) #10
  %23 = xor i64 %21, 7640891576939301128
  store i64 %23, ptr %0, align 1, !tbaa !5
  %24 = getelementptr inbounds nuw i8, ptr %0, i64 8
  store <2 x i64> <i64 -4942790177534073029, i64 4354685564936845355>, ptr %24, align 1, !tbaa !5
  %25 = getelementptr inbounds nuw i8, ptr %0, i64 24
  store i64 -6534734903238641935, ptr %25, align 1, !tbaa !5
  %26 = getelementptr inbounds nuw i8, ptr %0, i64 32
  store <2 x i64> %14, ptr %26, align 1, !tbaa !5
  %27 = getelementptr inbounds nuw i8, ptr %0, i64 48
  store <2 x i64> %20, ptr %27, align 1, !tbaa !5
  ret i32 0
}

; Function Attrs: nounwind ssp uwtable(sync)
define noundef i32 @_sodium_blake2b_init_key(ptr noundef %0, i8 noundef zeroext %1, ptr noundef readonly captures(address_is_null) %2, i8 noundef zeroext %3) local_unnamed_addr #2 {
  %5 = alloca [128 x i8], align 1
  %6 = add i8 %1, -65
  %7 = icmp ult i8 %6, -64
  br i1 %7, label %8, label %9

8:                                                ; preds = %4
  tail call void @sodium_misuse() #11
  unreachable

9:                                                ; preds = %4
  %10 = icmp eq ptr %2, null
  %11 = add i8 %3, -65
  %12 = icmp ult i8 %11, -64
  %13 = or i1 %10, %12
  br i1 %13, label %14, label %15

14:                                               ; preds = %9
  tail call void @sodium_misuse() #11
  unreachable

15:                                               ; preds = %9
  %16 = zext nneg i8 %1 to i64
  %17 = zext nneg i8 %3 to i64
  %18 = shl nuw nsw i64 %17, 8
  %19 = or disjoint i64 %18, %16
  %20 = getelementptr inbounds nuw i8, ptr %0, i64 64
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(297) %20, i8 noundef 0, i64 noundef 297, i1 noundef false) #10
  %21 = xor i64 %19, 7640891576939301128
  store i64 %21, ptr %0, align 1, !tbaa !5
  %22 = getelementptr inbounds nuw i8, ptr %0, i64 8
  store <2 x i64> <i64 -4942790177534073029, i64 4354685564936845355>, ptr %22, align 1, !tbaa !5
  %23 = getelementptr inbounds nuw i8, ptr %0, i64 24
  store <2 x i64> <i64 -6534734903238641935, i64 5840696475078001361>, ptr %23, align 1, !tbaa !5
  %24 = getelementptr inbounds nuw i8, ptr %0, i64 40
  store <2 x i64> <i64 -7276294671716946913, i64 2270897969802886507>, ptr %24, align 1, !tbaa !5
  %25 = getelementptr inbounds nuw i8, ptr %0, i64 56
  store i64 6620516959819538809, ptr %25, align 1, !tbaa !5
  call void @llvm.lifetime.start.p0(i64 128, ptr nonnull %5) #10
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(128) %5, i8 0, i64 128, i1 false)
  %26 = call ptr @__memcpy_chk(ptr noundef nonnull %5, ptr noundef nonnull %2, i64 noundef %17, i64 noundef 128) #10
  %27 = getelementptr inbounds nuw i8, ptr %0, i64 352
  %28 = getelementptr inbounds nuw i8, ptr %0, i64 96
  %29 = getelementptr inbounds nuw i8, ptr %0, i64 72
  %30 = getelementptr inbounds nuw i8, ptr %0, i64 224
  %31 = load i64, ptr %27, align 1, !tbaa !9
  %32 = sub i64 256, %31
  %33 = icmp ult i64 %32, 128
  br i1 %33, label %41, label %34

34:                                               ; preds = %41, %15
  %35 = phi i64 [ %31, %15 ], [ %57, %41 ]
  %36 = phi ptr [ %5, %15 ], [ %59, %41 ]
  %37 = phi i64 [ 128, %15 ], [ %58, %41 ]
  %38 = getelementptr inbounds nuw i8, ptr %28, i64 %35
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %38, ptr noundef align 1 %36, i64 noundef %37, i1 noundef false) #10
  %39 = load i64, ptr %27, align 1, !tbaa !9
  %40 = add i64 %39, %37
  store i64 %40, ptr %27, align 1, !tbaa !9
  call void @sodium_memzero(ptr noundef nonnull %5, i64 noundef 128) #10
  call void @llvm.lifetime.end.p0(i64 128, ptr nonnull %5) #10
  ret i32 0

41:                                               ; preds = %15, %41
  %42 = phi i64 [ %60, %41 ], [ %32, %15 ]
  %43 = phi i64 [ %58, %41 ], [ 128, %15 ]
  %44 = phi ptr [ %59, %41 ], [ %5, %15 ]
  %45 = phi i64 [ %57, %41 ], [ %31, %15 ]
  %46 = getelementptr inbounds nuw i8, ptr %28, i64 %45
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %46, ptr noundef align 1 %44, i64 noundef %42, i1 noundef false) #10
  %47 = load i64, ptr %27, align 1, !tbaa !9
  %48 = add i64 %47, %42
  store i64 %48, ptr %27, align 1, !tbaa !9
  %49 = load i64, ptr %20, align 1, !tbaa !5
  %50 = add i64 %49, 128
  store i64 %50, ptr %20, align 1, !tbaa !5
  %51 = icmp ugt i64 %49, -129
  %52 = zext i1 %51 to i64
  %53 = load i64, ptr %29, align 1, !tbaa !5
  %54 = add i64 %53, %52
  store i64 %54, ptr %29, align 1, !tbaa !5
  %55 = call i32 @_sodium_blake2b_compress_ref(ptr noundef nonnull %0, ptr noundef nonnull %28) #10
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(128) %28, ptr noundef nonnull align 1 dereferenceable(128) %30, i64 noundef 128, i1 noundef false) #10
  %56 = load i64, ptr %27, align 1, !tbaa !9
  %57 = add i64 %56, -128
  %58 = sub nuw i64 %43, %42
  store i64 %57, ptr %27, align 1, !tbaa !9
  %59 = getelementptr inbounds nuw i8, ptr %44, i64 %42
  %60 = sub i64 384, %56
  %61 = icmp ugt i64 %58, %60
  br i1 %61, label %41, label %34
}

; Function Attrs: nocallback nofree nounwind memory(argmem: readwrite)
declare ptr @__memcpy_chk(ptr noalias noundef writeonly, ptr noalias noundef readonly captures(none), i64 noundef, i64 noundef) local_unnamed_addr #5

; Function Attrs: nounwind ssp uwtable(sync)
define noundef i32 @_sodium_blake2b_update(ptr noundef %0, ptr noundef readonly captures(none) %1, i64 noundef %2) local_unnamed_addr #2 {
  %4 = icmp eq i64 %2, 0
  br i1 %4, label %37, label %5

5:                                                ; preds = %3
  %6 = getelementptr inbounds nuw i8, ptr %0, i64 352
  %7 = getelementptr inbounds nuw i8, ptr %0, i64 96
  %8 = getelementptr inbounds nuw i8, ptr %0, i64 64
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 72
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 224
  %11 = load i64, ptr %6, align 1, !tbaa !9
  br label %12

12:                                               ; preds = %5, %22
  %13 = phi i64 [ %11, %5 ], [ %33, %22 ]
  %14 = phi ptr [ %1, %5 ], [ %35, %22 ]
  %15 = phi i64 [ %2, %5 ], [ %34, %22 ]
  %16 = sub i64 256, %13
  %17 = icmp ugt i64 %15, %16
  %18 = getelementptr inbounds nuw i8, ptr %7, i64 %13
  br i1 %17, label %22, label %19

19:                                               ; preds = %12
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %18, ptr noundef align 1 %14, i64 noundef %15, i1 noundef false) #10
  %20 = load i64, ptr %6, align 1, !tbaa !9
  %21 = add i64 %20, %15
  store i64 %21, ptr %6, align 1, !tbaa !9
  br label %37

22:                                               ; preds = %12
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %18, ptr noundef align 1 %14, i64 noundef %16, i1 noundef false) #10
  %23 = load i64, ptr %6, align 1, !tbaa !9
  %24 = add i64 %23, %16
  store i64 %24, ptr %6, align 1, !tbaa !9
  %25 = load i64, ptr %8, align 1, !tbaa !5
  %26 = add i64 %25, 128
  store i64 %26, ptr %8, align 1, !tbaa !5
  %27 = icmp ugt i64 %25, -129
  %28 = zext i1 %27 to i64
  %29 = load i64, ptr %9, align 1, !tbaa !5
  %30 = add i64 %29, %28
  store i64 %30, ptr %9, align 1, !tbaa !5
  %31 = tail call i32 @_sodium_blake2b_compress_ref(ptr noundef nonnull %0, ptr noundef nonnull %7) #10
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(128) %7, ptr noundef nonnull align 1 dereferenceable(128) %10, i64 noundef 128, i1 noundef false) #10
  %32 = load i64, ptr %6, align 1, !tbaa !9
  %33 = add i64 %32, -128
  %34 = sub nuw i64 %15, %16
  store i64 %33, ptr %6, align 1, !tbaa !9
  %35 = getelementptr inbounds nuw i8, ptr %14, i64 %16
  %36 = icmp eq i64 %34, 0
  br i1 %36, label %37, label %12, !llvm.loop !12

37:                                               ; preds = %22, %19, %3
  ret i32 0
}

declare void @sodium_memzero(ptr noundef, i64 noundef) local_unnamed_addr #6

; Function Attrs: nounwind ssp uwtable(sync)
define noundef i32 @_sodium_blake2b_init_key_salt_personal(ptr noundef %0, i8 noundef zeroext %1, ptr noundef readonly captures(address_is_null) %2, i8 noundef zeroext %3, ptr noundef readonly captures(address_is_null) %4, ptr noundef readonly captures(address_is_null) %5) local_unnamed_addr #2 {
  %7 = alloca [128 x i8], align 1
  %8 = add i8 %1, -65
  %9 = icmp ult i8 %8, -64
  br i1 %9, label %10, label %11

10:                                               ; preds = %6
  tail call void @sodium_misuse() #11
  unreachable

11:                                               ; preds = %6
  %12 = icmp eq ptr %2, null
  %13 = add i8 %3, -65
  %14 = icmp ult i8 %13, -64
  %15 = or i1 %12, %14
  br i1 %15, label %16, label %17

16:                                               ; preds = %11
  tail call void @sodium_misuse() #11
  unreachable

17:                                               ; preds = %11
  %18 = zext nneg i8 %1 to i64
  %19 = zext nneg i8 %3 to i64
  %20 = shl nuw nsw i64 %19, 8
  %21 = or disjoint i64 %20, %18
  %22 = icmp eq ptr %4, null
  br i1 %22, label %26, label %23

23:                                               ; preds = %17
  %24 = load <2 x i64>, ptr %4, align 1
  %25 = xor <2 x i64> %24, <i64 5840696475078001361, i64 -7276294671716946913>
  br label %26

26:                                               ; preds = %17, %23
  %27 = phi <2 x i64> [ %25, %23 ], [ <i64 5840696475078001361, i64 -7276294671716946913>, %17 ]
  %28 = icmp eq ptr %5, null
  br i1 %28, label %32, label %29

29:                                               ; preds = %26
  %30 = load <2 x i64>, ptr %5, align 1
  %31 = xor <2 x i64> %30, <i64 2270897969802886507, i64 6620516959819538809>
  br label %32

32:                                               ; preds = %26, %29
  %33 = phi <2 x i64> [ %31, %29 ], [ <i64 2270897969802886507, i64 6620516959819538809>, %26 ]
  %34 = getelementptr inbounds nuw i8, ptr %0, i64 64
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(297) %34, i8 noundef 0, i64 noundef 297, i1 noundef false) #10
  %35 = xor i64 %21, 7640891576939301128
  store i64 %35, ptr %0, align 1, !tbaa !5
  %36 = getelementptr inbounds nuw i8, ptr %0, i64 8
  store <2 x i64> <i64 -4942790177534073029, i64 4354685564936845355>, ptr %36, align 1, !tbaa !5
  %37 = getelementptr inbounds nuw i8, ptr %0, i64 24
  store i64 -6534734903238641935, ptr %37, align 1, !tbaa !5
  %38 = getelementptr inbounds nuw i8, ptr %0, i64 32
  store <2 x i64> %27, ptr %38, align 1, !tbaa !5
  %39 = getelementptr inbounds nuw i8, ptr %0, i64 48
  store <2 x i64> %33, ptr %39, align 1, !tbaa !5
  call void @llvm.lifetime.start.p0(i64 128, ptr nonnull %7) #10
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(128) %7, i8 0, i64 128, i1 false)
  %40 = call ptr @__memcpy_chk(ptr noundef nonnull %7, ptr noundef nonnull %2, i64 noundef %19, i64 noundef 128) #10
  %41 = getelementptr inbounds nuw i8, ptr %0, i64 352
  %42 = getelementptr inbounds nuw i8, ptr %0, i64 96
  %43 = getelementptr inbounds nuw i8, ptr %0, i64 72
  %44 = getelementptr inbounds nuw i8, ptr %0, i64 224
  %45 = load i64, ptr %41, align 1, !tbaa !9
  %46 = sub i64 256, %45
  %47 = icmp ult i64 %46, 128
  br i1 %47, label %55, label %48

48:                                               ; preds = %55, %32
  %49 = phi i64 [ %45, %32 ], [ %71, %55 ]
  %50 = phi ptr [ %7, %32 ], [ %73, %55 ]
  %51 = phi i64 [ 128, %32 ], [ %72, %55 ]
  %52 = getelementptr inbounds nuw i8, ptr %42, i64 %49
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %52, ptr noundef align 1 %50, i64 noundef %51, i1 noundef false) #10
  %53 = load i64, ptr %41, align 1, !tbaa !9
  %54 = add i64 %53, %51
  store i64 %54, ptr %41, align 1, !tbaa !9
  call void @sodium_memzero(ptr noundef nonnull %7, i64 noundef 128) #10
  call void @llvm.lifetime.end.p0(i64 128, ptr nonnull %7) #10
  ret i32 0

55:                                               ; preds = %32, %55
  %56 = phi i64 [ %74, %55 ], [ %46, %32 ]
  %57 = phi i64 [ %72, %55 ], [ 128, %32 ]
  %58 = phi ptr [ %73, %55 ], [ %7, %32 ]
  %59 = phi i64 [ %71, %55 ], [ %45, %32 ]
  %60 = getelementptr inbounds nuw i8, ptr %42, i64 %59
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %60, ptr noundef align 1 %58, i64 noundef %56, i1 noundef false) #10
  %61 = load i64, ptr %41, align 1, !tbaa !9
  %62 = add i64 %61, %56
  store i64 %62, ptr %41, align 1, !tbaa !9
  %63 = load i64, ptr %34, align 1, !tbaa !5
  %64 = add i64 %63, 128
  store i64 %64, ptr %34, align 1, !tbaa !5
  %65 = icmp ugt i64 %63, -129
  %66 = zext i1 %65 to i64
  %67 = load i64, ptr %43, align 1, !tbaa !5
  %68 = add i64 %67, %66
  store i64 %68, ptr %43, align 1, !tbaa !5
  %69 = call i32 @_sodium_blake2b_compress_ref(ptr noundef nonnull %0, ptr noundef nonnull %42) #10
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(128) %42, ptr noundef nonnull align 1 dereferenceable(128) %44, i64 noundef 128, i1 noundef false) #10
  %70 = load i64, ptr %41, align 1, !tbaa !9
  %71 = add i64 %70, -128
  %72 = sub nuw i64 %57, %56
  store i64 %71, ptr %41, align 1, !tbaa !9
  %73 = getelementptr inbounds nuw i8, ptr %58, i64 %56
  %74 = sub i64 384, %70
  %75 = icmp ugt i64 %72, %74
  br i1 %75, label %55, label %48
}

; Function Attrs: nounwind ssp uwtable(sync)
define range(i32 -1, 1) i32 @_sodium_blake2b_final(ptr noundef %0, ptr noundef %1, i8 noundef zeroext %2) local_unnamed_addr #2 {
  %4 = alloca [64 x i8], align 1
  call void @llvm.lifetime.start.p0(i64 64, ptr nonnull %4)
  %5 = add i8 %2, -65
  %6 = icmp ult i8 %5, -64
  br i1 %6, label %7, label %8

7:                                                ; preds = %3
  tail call void @sodium_misuse() #11
  unreachable

8:                                                ; preds = %3
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 80
  %10 = load i64, ptr %9, align 1, !tbaa !5
  %11 = icmp eq i64 %10, 0
  br i1 %11, label %12, label %253

12:                                               ; preds = %8
  %13 = getelementptr inbounds nuw i8, ptr %0, i64 352
  %14 = load i64, ptr %13, align 1, !tbaa !9
  %15 = icmp ugt i64 %14, 128
  br i1 %15, label %16, label %34

16:                                               ; preds = %12
  %17 = getelementptr inbounds nuw i8, ptr %0, i64 64
  %18 = load i64, ptr %17, align 1, !tbaa !5
  %19 = add i64 %18, 128
  store i64 %19, ptr %17, align 1, !tbaa !5
  %20 = icmp ugt i64 %18, -129
  %21 = zext i1 %20 to i64
  %22 = getelementptr inbounds nuw i8, ptr %0, i64 72
  %23 = load i64, ptr %22, align 1, !tbaa !5
  %24 = add i64 %23, %21
  store i64 %24, ptr %22, align 1, !tbaa !5
  %25 = getelementptr inbounds nuw i8, ptr %0, i64 96
  %26 = tail call i32 @_sodium_blake2b_compress_ref(ptr noundef nonnull %0, ptr noundef nonnull %25) #10
  %27 = load i64, ptr %13, align 1, !tbaa !9
  %28 = add i64 %27, -128
  store i64 %28, ptr %13, align 1, !tbaa !9
  %29 = icmp ugt i64 %28, 128
  br i1 %29, label %30, label %31, !prof !14

30:                                               ; preds = %16
  tail call void @__assert_rtn(ptr noundef nonnull @__func__._sodium_blake2b_final, ptr noundef nonnull @.str, i32 noundef 306, ptr noundef nonnull @.str.1) #12
  unreachable

31:                                               ; preds = %16
  %32 = getelementptr inbounds nuw i8, ptr %0, i64 224
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %25, ptr noundef nonnull align 1 %32, i64 noundef %28, i1 noundef false) #10
  %33 = load i64, ptr %13, align 1, !tbaa !9
  br label %34

34:                                               ; preds = %31, %12
  %35 = phi i64 [ %33, %31 ], [ %14, %12 ]
  %36 = getelementptr inbounds nuw i8, ptr %0, i64 64
  %37 = load i64, ptr %36, align 1, !tbaa !5
  %38 = add i64 %37, %35
  store i64 %38, ptr %36, align 1, !tbaa !5
  %39 = icmp ult i64 %38, %35
  %40 = zext i1 %39 to i64
  %41 = getelementptr inbounds nuw i8, ptr %0, i64 72
  %42 = load i64, ptr %41, align 1, !tbaa !5
  %43 = add i64 %42, %40
  store i64 %43, ptr %41, align 1, !tbaa !5
  %44 = getelementptr inbounds nuw i8, ptr %0, i64 360
  %45 = load i8, ptr %44, align 1, !tbaa !15
  %46 = icmp eq i8 %45, 0
  br i1 %46, label %49, label %47

47:                                               ; preds = %34
  %48 = getelementptr inbounds nuw i8, ptr %0, i64 88
  store i64 -1, ptr %48, align 1, !tbaa !5
  br label %49

49:                                               ; preds = %34, %47
  store i64 -1, ptr %9, align 1, !tbaa !5
  %50 = getelementptr inbounds nuw i8, ptr %0, i64 96
  %51 = getelementptr inbounds nuw i8, ptr %50, i64 %35
  %52 = sub i64 256, %35
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 %51, i8 noundef 0, i64 noundef %52, i1 noundef false) #10
  %53 = tail call i32 @_sodium_blake2b_compress_ref(ptr noundef nonnull %0, ptr noundef nonnull %50) #10
  %54 = load i64, ptr %0, align 1, !tbaa !5
  %55 = trunc i64 %54 to i8
  store i8 %55, ptr %4, align 1, !tbaa !16
  %56 = lshr i64 %54, 8
  %57 = trunc i64 %56 to i8
  %58 = getelementptr inbounds nuw i8, ptr %4, i64 1
  store i8 %57, ptr %58, align 1, !tbaa !16
  %59 = lshr i64 %54, 16
  %60 = trunc i64 %59 to i8
  %61 = getelementptr inbounds nuw i8, ptr %4, i64 2
  store i8 %60, ptr %61, align 1, !tbaa !16
  %62 = lshr i64 %54, 24
  %63 = trunc i64 %62 to i8
  %64 = getelementptr inbounds nuw i8, ptr %4, i64 3
  store i8 %63, ptr %64, align 1, !tbaa !16
  %65 = lshr i64 %54, 32
  %66 = trunc i64 %65 to i8
  %67 = getelementptr inbounds nuw i8, ptr %4, i64 4
  store i8 %66, ptr %67, align 1, !tbaa !16
  %68 = lshr i64 %54, 40
  %69 = trunc i64 %68 to i8
  %70 = getelementptr inbounds nuw i8, ptr %4, i64 5
  store i8 %69, ptr %70, align 1, !tbaa !16
  %71 = lshr i64 %54, 48
  %72 = trunc i64 %71 to i8
  %73 = getelementptr inbounds nuw i8, ptr %4, i64 6
  store i8 %72, ptr %73, align 1, !tbaa !16
  %74 = lshr i64 %54, 56
  %75 = trunc nuw i64 %74 to i8
  %76 = getelementptr inbounds nuw i8, ptr %4, i64 7
  store i8 %75, ptr %76, align 1, !tbaa !16
  %77 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %78 = load i64, ptr %77, align 1, !tbaa !5
  %79 = trunc i64 %78 to i8
  %80 = getelementptr inbounds nuw i8, ptr %4, i64 8
  store i8 %79, ptr %80, align 1, !tbaa !16
  %81 = lshr i64 %78, 8
  %82 = trunc i64 %81 to i8
  %83 = getelementptr inbounds nuw i8, ptr %4, i64 9
  store i8 %82, ptr %83, align 1, !tbaa !16
  %84 = lshr i64 %78, 16
  %85 = trunc i64 %84 to i8
  %86 = getelementptr inbounds nuw i8, ptr %4, i64 10
  store i8 %85, ptr %86, align 1, !tbaa !16
  %87 = lshr i64 %78, 24
  %88 = trunc i64 %87 to i8
  %89 = getelementptr inbounds nuw i8, ptr %4, i64 11
  store i8 %88, ptr %89, align 1, !tbaa !16
  %90 = lshr i64 %78, 32
  %91 = trunc i64 %90 to i8
  %92 = getelementptr inbounds nuw i8, ptr %4, i64 12
  store i8 %91, ptr %92, align 1, !tbaa !16
  %93 = lshr i64 %78, 40
  %94 = trunc i64 %93 to i8
  %95 = getelementptr inbounds nuw i8, ptr %4, i64 13
  store i8 %94, ptr %95, align 1, !tbaa !16
  %96 = lshr i64 %78, 48
  %97 = trunc i64 %96 to i8
  %98 = getelementptr inbounds nuw i8, ptr %4, i64 14
  store i8 %97, ptr %98, align 1, !tbaa !16
  %99 = lshr i64 %78, 56
  %100 = trunc nuw i64 %99 to i8
  %101 = getelementptr inbounds nuw i8, ptr %4, i64 15
  store i8 %100, ptr %101, align 1, !tbaa !16
  %102 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %103 = load i64, ptr %102, align 1, !tbaa !5
  %104 = trunc i64 %103 to i8
  %105 = getelementptr inbounds nuw i8, ptr %4, i64 16
  store i8 %104, ptr %105, align 1, !tbaa !16
  %106 = lshr i64 %103, 8
  %107 = trunc i64 %106 to i8
  %108 = getelementptr inbounds nuw i8, ptr %4, i64 17
  store i8 %107, ptr %108, align 1, !tbaa !16
  %109 = lshr i64 %103, 16
  %110 = trunc i64 %109 to i8
  %111 = getelementptr inbounds nuw i8, ptr %4, i64 18
  store i8 %110, ptr %111, align 1, !tbaa !16
  %112 = lshr i64 %103, 24
  %113 = trunc i64 %112 to i8
  %114 = getelementptr inbounds nuw i8, ptr %4, i64 19
  store i8 %113, ptr %114, align 1, !tbaa !16
  %115 = lshr i64 %103, 32
  %116 = trunc i64 %115 to i8
  %117 = getelementptr inbounds nuw i8, ptr %4, i64 20
  store i8 %116, ptr %117, align 1, !tbaa !16
  %118 = lshr i64 %103, 40
  %119 = trunc i64 %118 to i8
  %120 = getelementptr inbounds nuw i8, ptr %4, i64 21
  store i8 %119, ptr %120, align 1, !tbaa !16
  %121 = lshr i64 %103, 48
  %122 = trunc i64 %121 to i8
  %123 = getelementptr inbounds nuw i8, ptr %4, i64 22
  store i8 %122, ptr %123, align 1, !tbaa !16
  %124 = lshr i64 %103, 56
  %125 = trunc nuw i64 %124 to i8
  %126 = getelementptr inbounds nuw i8, ptr %4, i64 23
  store i8 %125, ptr %126, align 1, !tbaa !16
  %127 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %128 = load i64, ptr %127, align 1, !tbaa !5
  %129 = trunc i64 %128 to i8
  %130 = getelementptr inbounds nuw i8, ptr %4, i64 24
  store i8 %129, ptr %130, align 1, !tbaa !16
  %131 = lshr i64 %128, 8
  %132 = trunc i64 %131 to i8
  %133 = getelementptr inbounds nuw i8, ptr %4, i64 25
  store i8 %132, ptr %133, align 1, !tbaa !16
  %134 = lshr i64 %128, 16
  %135 = trunc i64 %134 to i8
  %136 = getelementptr inbounds nuw i8, ptr %4, i64 26
  store i8 %135, ptr %136, align 1, !tbaa !16
  %137 = lshr i64 %128, 24
  %138 = trunc i64 %137 to i8
  %139 = getelementptr inbounds nuw i8, ptr %4, i64 27
  store i8 %138, ptr %139, align 1, !tbaa !16
  %140 = lshr i64 %128, 32
  %141 = trunc i64 %140 to i8
  %142 = getelementptr inbounds nuw i8, ptr %4, i64 28
  store i8 %141, ptr %142, align 1, !tbaa !16
  %143 = lshr i64 %128, 40
  %144 = trunc i64 %143 to i8
  %145 = getelementptr inbounds nuw i8, ptr %4, i64 29
  store i8 %144, ptr %145, align 1, !tbaa !16
  %146 = lshr i64 %128, 48
  %147 = trunc i64 %146 to i8
  %148 = getelementptr inbounds nuw i8, ptr %4, i64 30
  store i8 %147, ptr %148, align 1, !tbaa !16
  %149 = lshr i64 %128, 56
  %150 = trunc nuw i64 %149 to i8
  %151 = getelementptr inbounds nuw i8, ptr %4, i64 31
  store i8 %150, ptr %151, align 1, !tbaa !16
  %152 = getelementptr inbounds nuw i8, ptr %0, i64 32
  %153 = load i64, ptr %152, align 1, !tbaa !5
  %154 = trunc i64 %153 to i8
  %155 = getelementptr inbounds nuw i8, ptr %4, i64 32
  store i8 %154, ptr %155, align 1, !tbaa !16
  %156 = lshr i64 %153, 8
  %157 = trunc i64 %156 to i8
  %158 = getelementptr inbounds nuw i8, ptr %4, i64 33
  store i8 %157, ptr %158, align 1, !tbaa !16
  %159 = lshr i64 %153, 16
  %160 = trunc i64 %159 to i8
  %161 = getelementptr inbounds nuw i8, ptr %4, i64 34
  store i8 %160, ptr %161, align 1, !tbaa !16
  %162 = lshr i64 %153, 24
  %163 = trunc i64 %162 to i8
  %164 = getelementptr inbounds nuw i8, ptr %4, i64 35
  store i8 %163, ptr %164, align 1, !tbaa !16
  %165 = lshr i64 %153, 32
  %166 = trunc i64 %165 to i8
  %167 = getelementptr inbounds nuw i8, ptr %4, i64 36
  store i8 %166, ptr %167, align 1, !tbaa !16
  %168 = lshr i64 %153, 40
  %169 = trunc i64 %168 to i8
  %170 = getelementptr inbounds nuw i8, ptr %4, i64 37
  store i8 %169, ptr %170, align 1, !tbaa !16
  %171 = lshr i64 %153, 48
  %172 = trunc i64 %171 to i8
  %173 = getelementptr inbounds nuw i8, ptr %4, i64 38
  store i8 %172, ptr %173, align 1, !tbaa !16
  %174 = lshr i64 %153, 56
  %175 = trunc nuw i64 %174 to i8
  %176 = getelementptr inbounds nuw i8, ptr %4, i64 39
  store i8 %175, ptr %176, align 1, !tbaa !16
  %177 = getelementptr inbounds nuw i8, ptr %0, i64 40
  %178 = load i64, ptr %177, align 1, !tbaa !5
  %179 = trunc i64 %178 to i8
  %180 = getelementptr inbounds nuw i8, ptr %4, i64 40
  store i8 %179, ptr %180, align 1, !tbaa !16
  %181 = lshr i64 %178, 8
  %182 = trunc i64 %181 to i8
  %183 = getelementptr inbounds nuw i8, ptr %4, i64 41
  store i8 %182, ptr %183, align 1, !tbaa !16
  %184 = lshr i64 %178, 16
  %185 = trunc i64 %184 to i8
  %186 = getelementptr inbounds nuw i8, ptr %4, i64 42
  store i8 %185, ptr %186, align 1, !tbaa !16
  %187 = lshr i64 %178, 24
  %188 = trunc i64 %187 to i8
  %189 = getelementptr inbounds nuw i8, ptr %4, i64 43
  store i8 %188, ptr %189, align 1, !tbaa !16
  %190 = lshr i64 %178, 32
  %191 = trunc i64 %190 to i8
  %192 = getelementptr inbounds nuw i8, ptr %4, i64 44
  store i8 %191, ptr %192, align 1, !tbaa !16
  %193 = lshr i64 %178, 40
  %194 = trunc i64 %193 to i8
  %195 = getelementptr inbounds nuw i8, ptr %4, i64 45
  store i8 %194, ptr %195, align 1, !tbaa !16
  %196 = lshr i64 %178, 48
  %197 = trunc i64 %196 to i8
  %198 = getelementptr inbounds nuw i8, ptr %4, i64 46
  store i8 %197, ptr %198, align 1, !tbaa !16
  %199 = lshr i64 %178, 56
  %200 = trunc nuw i64 %199 to i8
  %201 = getelementptr inbounds nuw i8, ptr %4, i64 47
  store i8 %200, ptr %201, align 1, !tbaa !16
  %202 = getelementptr inbounds nuw i8, ptr %0, i64 48
  %203 = load i64, ptr %202, align 1, !tbaa !5
  %204 = trunc i64 %203 to i8
  %205 = getelementptr inbounds nuw i8, ptr %4, i64 48
  store i8 %204, ptr %205, align 1, !tbaa !16
  %206 = lshr i64 %203, 8
  %207 = trunc i64 %206 to i8
  %208 = getelementptr inbounds nuw i8, ptr %4, i64 49
  store i8 %207, ptr %208, align 1, !tbaa !16
  %209 = lshr i64 %203, 16
  %210 = trunc i64 %209 to i8
  %211 = getelementptr inbounds nuw i8, ptr %4, i64 50
  store i8 %210, ptr %211, align 1, !tbaa !16
  %212 = lshr i64 %203, 24
  %213 = trunc i64 %212 to i8
  %214 = getelementptr inbounds nuw i8, ptr %4, i64 51
  store i8 %213, ptr %214, align 1, !tbaa !16
  %215 = lshr i64 %203, 32
  %216 = trunc i64 %215 to i8
  %217 = getelementptr inbounds nuw i8, ptr %4, i64 52
  store i8 %216, ptr %217, align 1, !tbaa !16
  %218 = lshr i64 %203, 40
  %219 = trunc i64 %218 to i8
  %220 = getelementptr inbounds nuw i8, ptr %4, i64 53
  store i8 %219, ptr %220, align 1, !tbaa !16
  %221 = lshr i64 %203, 48
  %222 = trunc i64 %221 to i8
  %223 = getelementptr inbounds nuw i8, ptr %4, i64 54
  store i8 %222, ptr %223, align 1, !tbaa !16
  %224 = lshr i64 %203, 56
  %225 = trunc nuw i64 %224 to i8
  %226 = getelementptr inbounds nuw i8, ptr %4, i64 55
  store i8 %225, ptr %226, align 1, !tbaa !16
  %227 = getelementptr inbounds nuw i8, ptr %0, i64 56
  %228 = load i64, ptr %227, align 1, !tbaa !5
  %229 = trunc i64 %228 to i8
  %230 = getelementptr inbounds nuw i8, ptr %4, i64 56
  store i8 %229, ptr %230, align 1, !tbaa !16
  %231 = lshr i64 %228, 8
  %232 = trunc i64 %231 to i8
  %233 = getelementptr inbounds nuw i8, ptr %4, i64 57
  store i8 %232, ptr %233, align 1, !tbaa !16
  %234 = lshr i64 %228, 16
  %235 = trunc i64 %234 to i8
  %236 = getelementptr inbounds nuw i8, ptr %4, i64 58
  store i8 %235, ptr %236, align 1, !tbaa !16
  %237 = lshr i64 %228, 24
  %238 = trunc i64 %237 to i8
  %239 = getelementptr inbounds nuw i8, ptr %4, i64 59
  store i8 %238, ptr %239, align 1, !tbaa !16
  %240 = lshr i64 %228, 32
  %241 = trunc i64 %240 to i8
  %242 = getelementptr inbounds nuw i8, ptr %4, i64 60
  store i8 %241, ptr %242, align 1, !tbaa !16
  %243 = lshr i64 %228, 40
  %244 = trunc i64 %243 to i8
  %245 = getelementptr inbounds nuw i8, ptr %4, i64 61
  store i8 %244, ptr %245, align 1, !tbaa !16
  %246 = lshr i64 %228, 48
  %247 = trunc i64 %246 to i8
  %248 = getelementptr inbounds nuw i8, ptr %4, i64 62
  store i8 %247, ptr %248, align 1, !tbaa !16
  %249 = lshr i64 %228, 56
  %250 = trunc nuw i64 %249 to i8
  %251 = getelementptr inbounds nuw i8, ptr %4, i64 63
  store i8 %250, ptr %251, align 1, !tbaa !16
  %252 = zext nneg i8 %2 to i64
  call void @llvm.memcpy.p0.p0.i64(ptr noundef align 1 %1, ptr noundef nonnull align 1 %4, i64 noundef %252, i1 noundef false) #10
  tail call void @sodium_memzero(ptr noundef nonnull %0, i64 noundef 64) #10
  tail call void @sodium_memzero(ptr noundef nonnull %50, i64 noundef 256) #10
  br label %253

253:                                              ; preds = %8, %49
  %254 = phi i32 [ 0, %49 ], [ -1, %8 ]
  call void @llvm.lifetime.end.p0(i64 64, ptr nonnull %4)
  ret i32 %254
}

; Function Attrs: cold noreturn
declare void @__assert_rtn(ptr noundef, ptr noundef, i32 noundef, ptr noundef) local_unnamed_addr #7

; Function Attrs: nounwind ssp uwtable(sync)
define noundef i32 @_sodium_blake2b(ptr noundef %0, ptr noundef readonly captures(address_is_null) %1, ptr noundef readonly captures(address_is_null) %2, i8 noundef zeroext %3, i64 noundef %4, i8 noundef zeroext %5) local_unnamed_addr #2 {
  %7 = alloca [1 x %struct.blake2b_state], align 64
  call void @llvm.lifetime.start.p0(i64 361, ptr nonnull %7) #10
  %8 = icmp eq ptr %1, null
  %9 = icmp ne i64 %4, 0
  %10 = and i1 %8, %9
  br i1 %10, label %11, label %12

11:                                               ; preds = %6
  tail call void @sodium_misuse() #11
  unreachable

12:                                               ; preds = %6
  %13 = icmp eq ptr %0, null
  br i1 %13, label %14, label %15

14:                                               ; preds = %12
  tail call void @sodium_misuse() #11
  unreachable

15:                                               ; preds = %12
  %16 = add i8 %3, -65
  %17 = icmp ult i8 %16, -64
  br i1 %17, label %18, label %19

18:                                               ; preds = %15
  tail call void @sodium_misuse() #11
  unreachable

19:                                               ; preds = %15
  %20 = icmp eq ptr %2, null
  %21 = icmp ne i8 %5, 0
  %22 = and i1 %20, %21
  br i1 %22, label %23, label %24

23:                                               ; preds = %19
  tail call void @sodium_misuse() #11
  unreachable

24:                                               ; preds = %19
  %25 = icmp ugt i8 %5, 64
  br i1 %25, label %26, label %27

26:                                               ; preds = %24
  tail call void @sodium_misuse() #11
  unreachable

27:                                               ; preds = %24
  br i1 %21, label %28, label %30

28:                                               ; preds = %27
  %29 = call i32 @_sodium_blake2b_init_key(ptr noundef nonnull %7, i8 noundef zeroext %3, ptr noundef %2, i8 noundef zeroext %5)
  br label %38

30:                                               ; preds = %27
  %31 = zext nneg i8 %3 to i64
  %32 = getelementptr inbounds nuw i8, ptr %7, i64 64
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 64 dereferenceable(297) %32, i8 noundef 0, i64 noundef 297, i1 noundef false) #10
  %33 = xor i64 %31, 7640891576939301128
  store i64 %33, ptr %7, align 64, !tbaa !5
  %34 = getelementptr inbounds nuw i8, ptr %7, i64 8
  store <2 x i64> <i64 -4942790177534073029, i64 4354685564936845355>, ptr %34, align 8, !tbaa !5
  %35 = getelementptr inbounds nuw i8, ptr %7, i64 24
  store <2 x i64> <i64 -6534734903238641935, i64 5840696475078001361>, ptr %35, align 8, !tbaa !5
  %36 = getelementptr inbounds nuw i8, ptr %7, i64 40
  store <2 x i64> <i64 -7276294671716946913, i64 2270897969802886507>, ptr %36, align 8, !tbaa !5
  %37 = getelementptr inbounds nuw i8, ptr %7, i64 56
  store i64 6620516959819538809, ptr %37, align 8, !tbaa !5
  br label %38

38:                                               ; preds = %30, %28
  %39 = call i32 @_sodium_blake2b_update(ptr noundef nonnull %7, ptr noundef %1, i64 noundef %4)
  %40 = call i32 @_sodium_blake2b_final(ptr noundef nonnull %7, ptr noundef nonnull %0, i8 noundef zeroext %3)
  call void @llvm.lifetime.end.p0(i64 361, ptr nonnull %7) #10
  ret i32 0
}

; Function Attrs: nounwind ssp uwtable(sync)
define noundef i32 @_sodium_blake2b_salt_personal(ptr noundef %0, ptr noundef readonly captures(address_is_null) %1, ptr noundef readonly captures(address_is_null) %2, i8 noundef zeroext %3, i64 noundef %4, i8 noundef zeroext %5, ptr noundef readonly captures(address_is_null) %6, ptr noundef readonly captures(address_is_null) %7) local_unnamed_addr #2 {
  %9 = alloca [1 x %struct.blake2b_state], align 64
  call void @llvm.lifetime.start.p0(i64 361, ptr nonnull %9) #10
  %10 = icmp eq ptr %1, null
  %11 = icmp ne i64 %4, 0
  %12 = and i1 %10, %11
  br i1 %12, label %13, label %14

13:                                               ; preds = %8
  tail call void @sodium_misuse() #11
  unreachable

14:                                               ; preds = %8
  %15 = icmp eq ptr %0, null
  br i1 %15, label %16, label %17

16:                                               ; preds = %14
  tail call void @sodium_misuse() #11
  unreachable

17:                                               ; preds = %14
  %18 = add i8 %3, -65
  %19 = icmp ult i8 %18, -64
  br i1 %19, label %20, label %21

20:                                               ; preds = %17
  tail call void @sodium_misuse() #11
  unreachable

21:                                               ; preds = %17
  %22 = icmp eq ptr %2, null
  %23 = icmp ne i8 %5, 0
  %24 = and i1 %22, %23
  br i1 %24, label %25, label %26

25:                                               ; preds = %21
  tail call void @sodium_misuse() #11
  unreachable

26:                                               ; preds = %21
  %27 = icmp ugt i8 %5, 64
  br i1 %27, label %28, label %29

28:                                               ; preds = %26
  tail call void @sodium_misuse() #11
  unreachable

29:                                               ; preds = %26
  br i1 %23, label %30, label %32

30:                                               ; preds = %29
  %31 = call i32 @_sodium_blake2b_init_key_salt_personal(ptr noundef nonnull %9, i8 noundef zeroext %3, ptr noundef %2, i8 noundef zeroext %5, ptr noundef %6, ptr noundef %7)
  br label %52

32:                                               ; preds = %29
  %33 = icmp eq ptr %6, null
  br i1 %33, label %37, label %34

34:                                               ; preds = %32
  %35 = load <2 x i64>, ptr %6, align 1
  %36 = xor <2 x i64> %35, <i64 5840696475078001361, i64 -7276294671716946913>
  br label %37

37:                                               ; preds = %34, %32
  %38 = phi <2 x i64> [ %36, %34 ], [ <i64 5840696475078001361, i64 -7276294671716946913>, %32 ]
  %39 = icmp eq ptr %7, null
  br i1 %39, label %43, label %40

40:                                               ; preds = %37
  %41 = load <2 x i64>, ptr %7, align 1
  %42 = xor <2 x i64> %41, <i64 2270897969802886507, i64 6620516959819538809>
  br label %43

43:                                               ; preds = %37, %40
  %44 = phi <2 x i64> [ %42, %40 ], [ <i64 2270897969802886507, i64 6620516959819538809>, %37 ]
  %45 = zext nneg i8 %3 to i64
  %46 = getelementptr inbounds nuw i8, ptr %9, i64 64
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 64 dereferenceable(297) %46, i8 noundef 0, i64 noundef 297, i1 noundef false) #10
  %47 = xor i64 %45, 7640891576939301128
  store i64 %47, ptr %9, align 64, !tbaa !5
  %48 = getelementptr inbounds nuw i8, ptr %9, i64 8
  store <2 x i64> <i64 -4942790177534073029, i64 4354685564936845355>, ptr %48, align 8, !tbaa !5
  %49 = getelementptr inbounds nuw i8, ptr %9, i64 24
  store i64 -6534734903238641935, ptr %49, align 8, !tbaa !5
  %50 = getelementptr inbounds nuw i8, ptr %9, i64 32
  store <2 x i64> %38, ptr %50, align 32, !tbaa !5
  %51 = getelementptr inbounds nuw i8, ptr %9, i64 48
  store <2 x i64> %44, ptr %51, align 16, !tbaa !5
  br label %52

52:                                               ; preds = %43, %30
  %53 = call i32 @_sodium_blake2b_update(ptr noundef nonnull %9, ptr noundef %1, i64 noundef %4)
  %54 = call i32 @_sodium_blake2b_final(ptr noundef nonnull %9, ptr noundef nonnull %0, i8 noundef zeroext %3)
  call void @llvm.lifetime.end.p0(i64 361, ptr nonnull %9) #10
  ret i32 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(none) uwtable(sync)
define noundef i32 @_sodium_blake2b_pick_best_implementation() local_unnamed_addr #8 {
  ret i32 0
}

declare i32 @_sodium_blake2b_compress_ref(ptr noundef, ptr noundef) local_unnamed_addr #6

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias writeonly captures(none), ptr noalias readonly captures(none), i64, i1 immarg) #9

attributes #0 = { nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #2 = { nounwind ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { noreturn "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #4 = { mustprogress nocallback nofree nounwind willreturn memory(argmem: write) }
attributes #5 = { nocallback nofree nounwind memory(argmem: readwrite) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #6 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #7 = { cold noreturn "disable-tail-calls"="true" "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #8 = { mustprogress nofree norecurse nosync nounwind ssp willreturn memory(none) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #9 = { nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #10 = { nounwind }
attributes #11 = { noreturn nounwind }
attributes #12 = { cold noreturn nounwind }

!llvm.module.flags = !{!0, !1, !2, !3}
!llvm.ident = !{!4}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 8, !"PIC Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 1}
!3 = !{i32 7, !"frame-pointer", i32 1}
!4 = !{!"Homebrew clang version 21.1.8"}
!5 = !{!6, !6, i64 0}
!6 = !{!"long long", !7, i64 0}
!7 = !{!"omnipotent char", !8, i64 0}
!8 = !{!"Simple C/C++ TBAA"}
!9 = !{!10, !11, i64 352}
!10 = !{!"blake2b_state", !7, i64 0, !7, i64 64, !7, i64 80, !7, i64 96, !11, i64 352, !7, i64 360}
!11 = !{!"long", !7, i64 0}
!12 = distinct !{!12, !13}
!13 = !{!"llvm.loop.mustprogress"}
!14 = !{!"branch_weights", !"expected", i32 1, i32 2000}
!15 = !{!10, !7, i64 360}
!16 = !{!7, !7, i64 0}
