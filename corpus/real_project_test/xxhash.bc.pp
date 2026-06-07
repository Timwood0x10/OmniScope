; ModuleID = '/tmp/xxhash-src/xxhash.c'
source_filename = "/tmp/xxhash-src/xxhash.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

%struct.XXH128_hash_t = type { i64, i64 }

@kSecret = internal constant [192 x i8] c"\B8\FEl9#\A4K\BE|\01\81,\F7!\AD\1C\DE\D4m\E9\83\90\97\DBr@\A4\A4\B7\B3g\1F\CBy\E6N\CC\C0\E5x\82Z\D0}\CC\FFr!\B8\08Ft\F7C$\8E\E05\90\E6\81:&L<(R\BB\91\C3\00\CB\88\D0e\8B\1BS.\A3qdH\97\A2\0D\F9N8\19\EFF\A9\DE\AC\D8\A8\FAv?\E3\9C4?\F9\DC\BB\C7\C7\0BO\1D\8AQ\E0K\CD\B4Y1\C8\9F~\C9\D9xsd\EA\C5\AC\834\D3\EB\C3\C5\81\A0\FF\FA\13c\EB\17\0D\DDQ\B7\F0\DAI\D3\16U&)\D4h\9E+\16\BEX}G\A1\FC\8F\F8\B8\D1z\D01\CEE\CB:\8F\95\16\04(\AF\D7\FB\CA\BBK@~", align 64
@__const.XXH3_hashLong_128b_internal.acc = private unnamed_addr constant [8 x i64] [i64 3266489917, i64 -7046029288634856825, i64 -4417276706812531889, i64 1609587929392839161, i64 -8796714831421723037, i64 2246822519, i64 2870177450012600261, i64 2654435761], align 16

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(none) uwtable(sync)
define noundef i32 @XXH_versionNumber() local_unnamed_addr #0 {
  ret i32 701
}

; Function Attrs: nofree norecurse nosync nounwind ssp memory(argmem: read) uwtable(sync)
define i32 @XXH32(ptr noundef %0, i64 noundef %1, i32 noundef %2) local_unnamed_addr #1 {
  %4 = ptrtoint ptr %0 to i64
  %5 = and i64 %4, 3
  %6 = icmp eq i64 %5, 0
  %7 = icmp ugt i64 %1, 15
  br i1 %6, label %8, label %56

8:                                                ; preds = %3
  br i1 %7, label %9, label %54

9:                                                ; preds = %8
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %11 = getelementptr inbounds i8, ptr %10, i64 -15
  %12 = add i32 %2, 606290984
  %13 = add i32 %2, -2048144777
  %14 = add i32 %2, 1640531535
  br label %15

15:                                               ; preds = %15, %9
  %16 = phi ptr [ %0, %9 ], [ %44, %15 ]
  %17 = phi i32 [ %12, %9 ], [ %25, %15 ]
  %18 = phi i32 [ %13, %9 ], [ %31, %15 ]
  %19 = phi i32 [ %2, %9 ], [ %37, %15 ]
  %20 = phi i32 [ %14, %9 ], [ %43, %15 ]
  %21 = load i32, ptr %16, align 4, !tbaa !5
  %22 = mul i32 %21, -2048144777
  %23 = add i32 %22, %17
  %24 = tail call i32 @llvm.fshl.i32(i32 %23, i32 %23, i32 13)
  %25 = mul i32 %24, -1640531535
  %26 = getelementptr inbounds nuw i8, ptr %16, i64 4
  %27 = load i32, ptr %26, align 4, !tbaa !5
  %28 = mul i32 %27, -2048144777
  %29 = add i32 %28, %18
  %30 = tail call i32 @llvm.fshl.i32(i32 %29, i32 %29, i32 13)
  %31 = mul i32 %30, -1640531535
  %32 = getelementptr inbounds nuw i8, ptr %16, i64 8
  %33 = load i32, ptr %32, align 4, !tbaa !5
  %34 = mul i32 %33, -2048144777
  %35 = add i32 %34, %19
  %36 = tail call i32 @llvm.fshl.i32(i32 %35, i32 %35, i32 13)
  %37 = mul i32 %36, -1640531535
  %38 = getelementptr inbounds nuw i8, ptr %16, i64 12
  %39 = load i32, ptr %38, align 4, !tbaa !5
  %40 = mul i32 %39, -2048144777
  %41 = add i32 %40, %20
  %42 = tail call i32 @llvm.fshl.i32(i32 %41, i32 %41, i32 13)
  %43 = mul i32 %42, -1640531535
  %44 = getelementptr inbounds nuw i8, ptr %16, i64 16
  %45 = icmp ult ptr %44, %11
  br i1 %45, label %15, label %46, !llvm.loop !9

46:                                               ; preds = %15
  %47 = tail call i32 @llvm.fshl.i32(i32 %25, i32 %25, i32 1)
  %48 = tail call i32 @llvm.fshl.i32(i32 %31, i32 %31, i32 7)
  %49 = add i32 %48, %47
  %50 = tail call i32 @llvm.fshl.i32(i32 %37, i32 %37, i32 12)
  %51 = add i32 %49, %50
  %52 = tail call i32 @llvm.fshl.i32(i32 %43, i32 %43, i32 18)
  %53 = add i32 %51, %52
  br label %104

54:                                               ; preds = %8
  %55 = add i32 %2, 374761393
  br label %104

56:                                               ; preds = %3
  br i1 %7, label %57, label %102

57:                                               ; preds = %56
  %58 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %59 = getelementptr inbounds i8, ptr %58, i64 -15
  %60 = add i32 %2, 606290984
  %61 = add i32 %2, -2048144777
  %62 = add i32 %2, 1640531535
  br label %63

63:                                               ; preds = %63, %57
  %64 = phi ptr [ %0, %57 ], [ %92, %63 ]
  %65 = phi i32 [ %60, %57 ], [ %73, %63 ]
  %66 = phi i32 [ %61, %57 ], [ %79, %63 ]
  %67 = phi i32 [ %2, %57 ], [ %85, %63 ]
  %68 = phi i32 [ %62, %57 ], [ %91, %63 ]
  %69 = load i32, ptr %64, align 1
  %70 = mul i32 %69, -2048144777
  %71 = add i32 %70, %65
  %72 = tail call i32 @llvm.fshl.i32(i32 %71, i32 %71, i32 13)
  %73 = mul i32 %72, -1640531535
  %74 = getelementptr inbounds nuw i8, ptr %64, i64 4
  %75 = load i32, ptr %74, align 1
  %76 = mul i32 %75, -2048144777
  %77 = add i32 %76, %66
  %78 = tail call i32 @llvm.fshl.i32(i32 %77, i32 %77, i32 13)
  %79 = mul i32 %78, -1640531535
  %80 = getelementptr inbounds nuw i8, ptr %64, i64 8
  %81 = load i32, ptr %80, align 1
  %82 = mul i32 %81, -2048144777
  %83 = add i32 %82, %67
  %84 = tail call i32 @llvm.fshl.i32(i32 %83, i32 %83, i32 13)
  %85 = mul i32 %84, -1640531535
  %86 = getelementptr inbounds nuw i8, ptr %64, i64 12
  %87 = load i32, ptr %86, align 1
  %88 = mul i32 %87, -2048144777
  %89 = add i32 %88, %68
  %90 = tail call i32 @llvm.fshl.i32(i32 %89, i32 %89, i32 13)
  %91 = mul i32 %90, -1640531535
  %92 = getelementptr inbounds nuw i8, ptr %64, i64 16
  %93 = icmp ult ptr %92, %59
  br i1 %93, label %63, label %94, !llvm.loop !9

94:                                               ; preds = %63
  %95 = tail call i32 @llvm.fshl.i32(i32 %73, i32 %73, i32 1)
  %96 = tail call i32 @llvm.fshl.i32(i32 %79, i32 %79, i32 7)
  %97 = add i32 %96, %95
  %98 = tail call i32 @llvm.fshl.i32(i32 %85, i32 %85, i32 12)
  %99 = add i32 %97, %98
  %100 = tail call i32 @llvm.fshl.i32(i32 %91, i32 %91, i32 18)
  %101 = add i32 %99, %100
  br label %104

102:                                              ; preds = %56
  %103 = add i32 %2, 374761393
  br label %104

104:                                              ; preds = %102, %94, %54, %46
  %105 = phi i32 [ %53, %46 ], [ %55, %54 ], [ %101, %94 ], [ %103, %102 ]
  %106 = phi ptr [ %44, %46 ], [ %0, %54 ], [ %92, %94 ], [ %0, %102 ]
  %107 = trunc i64 %1 to i32
  %108 = add i32 %105, %107
  %109 = and i64 %1, 15
  %110 = tail call fastcc i32 @XXH32_finalize(i32 noundef %108, ptr noundef %106, i64 noundef %109)
  ret i32 %110
}

; Function Attrs: mustprogress nofree nounwind ssp willreturn memory(inaccessiblemem: readwrite) uwtable(sync)
define noalias noundef ptr @XXH32_createState() local_unnamed_addr #2 {
  %1 = tail call noalias noundef dereferenceable_or_null(48) ptr @malloc(i64 noundef 48) #23
  ret ptr %1
}

; Function Attrs: mustprogress nounwind ssp willreturn memory(argmem: readwrite, inaccessiblemem: readwrite) uwtable(sync)
define noundef i32 @XXH32_freeState(ptr noundef captures(none) %0) local_unnamed_addr #3 {
  tail call void @free(ptr noundef %0)
  ret i32 0
}

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define void @XXH32_copyState(ptr noundef %0, ptr noundef readonly captures(none) %1) local_unnamed_addr #4 {
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(48) %0, ptr noundef nonnull align 1 dereferenceable(48) %1, i64 noundef 48, i1 noundef false) #24
  ret void
}

; Function Attrs: nocallback nofree nounwind memory(argmem: readwrite)
declare ptr @__memcpy_chk(ptr noalias noundef writeonly, ptr noalias noundef readonly captures(none), i64 noundef, i64 noundef) local_unnamed_addr #5

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define noundef i32 @XXH32_reset(ptr noundef %0, i32 noundef %1) local_unnamed_addr #4 {
  %3 = alloca { [4 x i32], i32, i32 }, align 8
  call void @llvm.lifetime.start.p0(i64 24, ptr nonnull %3)
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %3, i8 0, i64 24, i1 false)
  %4 = add i32 %1, 606290984
  %5 = add i32 %1, -2048144777
  %6 = add i32 %1, 1640531535
  store i64 0, ptr %0, align 1
  %7 = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i32 %4, ptr %7, align 1
  %8 = getelementptr inbounds nuw i8, ptr %0, i64 12
  store i32 %5, ptr %8, align 1
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 16
  store i32 %1, ptr %9, align 1
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 20
  store i32 %6, ptr %10, align 1
  %11 = getelementptr inbounds nuw i8, ptr %0, i64 24
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(20) %11, ptr noundef nonnull align 8 dereferenceable(20) %3, i64 20, i1 false)
  call void @llvm.lifetime.end.p0(i64 24, ptr nonnull %3)
  ret i32 0
}

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr captures(none)) #6

; Function Attrs: mustprogress nocallback nofree nounwind willreturn memory(argmem: write)
declare void @llvm.memset.p0.i64(ptr writeonly captures(none), i8, i64, i1 immarg) #7

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr captures(none)) #6

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define range(i32 0, 2) i32 @XXH32_update(ptr noundef %0, ptr noundef %1, i64 noundef %2) local_unnamed_addr #4 {
  %4 = icmp eq ptr %1, null
  br i1 %4, label %125, label %5

5:                                                ; preds = %3
  %6 = getelementptr inbounds nuw i8, ptr %1, i64 %2
  %7 = trunc i64 %2 to i32
  %8 = load i32, ptr %0, align 4, !tbaa !12
  %9 = add i32 %8, %7
  store i32 %9, ptr %0, align 4, !tbaa !12
  %10 = icmp ugt i64 %2, 15
  %11 = icmp ugt i32 %9, 15
  %12 = or i1 %10, %11
  %13 = zext i1 %12 to i32
  %14 = getelementptr inbounds nuw i8, ptr %0, i64 4
  %15 = load i32, ptr %14, align 4, !tbaa !14
  %16 = or i32 %15, %13
  store i32 %16, ptr %14, align 4, !tbaa !14
  %17 = getelementptr inbounds nuw i8, ptr %0, i64 40
  %18 = load i32, ptr %17, align 4, !tbaa !15
  %19 = zext i32 %18 to i64
  %20 = add i64 %2, %19
  %21 = icmp ult i64 %20, 16
  br i1 %21, label %22, label %27

22:                                               ; preds = %5
  %23 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %24 = getelementptr inbounds nuw i8, ptr %23, i64 %19
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %24, ptr noundef nonnull readonly align 1 %1, i64 noundef %2, i1 noundef false) #24
  %25 = load i32, ptr %17, align 4, !tbaa !15
  %26 = add i32 %25, %7
  br label %123

27:                                               ; preds = %5
  %28 = icmp eq i32 %18, 0
  br i1 %28, label %69, label %29

29:                                               ; preds = %27
  %30 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %31 = getelementptr inbounds nuw i8, ptr %30, i64 %19
  %32 = sub i32 16, %18
  %33 = zext i32 %32 to i64
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %31, ptr noundef nonnull readonly align 1 %1, i64 noundef %33, i1 noundef false) #24
  %34 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %35 = load i32, ptr %34, align 4, !tbaa !16
  %36 = load i32, ptr %30, align 1
  %37 = mul i32 %36, -2048144777
  %38 = add i32 %37, %35
  %39 = tail call i32 @llvm.fshl.i32(i32 %38, i32 %38, i32 13)
  %40 = mul i32 %39, -1640531535
  store i32 %40, ptr %34, align 4, !tbaa !16
  %41 = getelementptr inbounds nuw i8, ptr %0, i64 28
  %42 = getelementptr inbounds nuw i8, ptr %0, i64 12
  %43 = load i32, ptr %42, align 4, !tbaa !17
  %44 = load i32, ptr %41, align 1
  %45 = mul i32 %44, -2048144777
  %46 = add i32 %45, %43
  %47 = tail call i32 @llvm.fshl.i32(i32 %46, i32 %46, i32 13)
  %48 = mul i32 %47, -1640531535
  store i32 %48, ptr %42, align 4, !tbaa !17
  %49 = getelementptr inbounds nuw i8, ptr %0, i64 32
  %50 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %51 = load i32, ptr %50, align 4, !tbaa !18
  %52 = load i32, ptr %49, align 1
  %53 = mul i32 %52, -2048144777
  %54 = add i32 %53, %51
  %55 = tail call i32 @llvm.fshl.i32(i32 %54, i32 %54, i32 13)
  %56 = mul i32 %55, -1640531535
  store i32 %56, ptr %50, align 4, !tbaa !18
  %57 = getelementptr inbounds nuw i8, ptr %0, i64 36
  %58 = getelementptr inbounds nuw i8, ptr %0, i64 20
  %59 = load i32, ptr %58, align 4, !tbaa !19
  %60 = load i32, ptr %57, align 1
  %61 = mul i32 %60, -2048144777
  %62 = add i32 %61, %59
  %63 = tail call i32 @llvm.fshl.i32(i32 %62, i32 %62, i32 13)
  %64 = mul i32 %63, -1640531535
  store i32 %64, ptr %58, align 4, !tbaa !19
  %65 = load i32, ptr %17, align 4, !tbaa !15
  %66 = sub i32 16, %65
  %67 = zext i32 %66 to i64
  %68 = getelementptr inbounds nuw i8, ptr %1, i64 %67
  store i32 0, ptr %17, align 4, !tbaa !15
  br label %69

69:                                               ; preds = %29, %27
  %70 = phi ptr [ %68, %29 ], [ %1, %27 ]
  %71 = getelementptr inbounds i8, ptr %6, i64 -16
  %72 = icmp ugt ptr %70, %71
  br i1 %72, label %114, label %73

73:                                               ; preds = %69
  %74 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %75 = load i32, ptr %74, align 4, !tbaa !16
  %76 = getelementptr inbounds nuw i8, ptr %0, i64 12
  %77 = load i32, ptr %76, align 4, !tbaa !17
  %78 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %79 = load i32, ptr %78, align 4, !tbaa !18
  %80 = getelementptr inbounds nuw i8, ptr %0, i64 20
  %81 = load i32, ptr %80, align 4, !tbaa !19
  br label %82

82:                                               ; preds = %82, %73
  %83 = phi ptr [ %70, %73 ], [ %111, %82 ]
  %84 = phi i32 [ %75, %73 ], [ %92, %82 ]
  %85 = phi i32 [ %77, %73 ], [ %98, %82 ]
  %86 = phi i32 [ %79, %73 ], [ %104, %82 ]
  %87 = phi i32 [ %81, %73 ], [ %110, %82 ]
  %88 = load i32, ptr %83, align 1
  %89 = mul i32 %88, -2048144777
  %90 = add i32 %89, %84
  %91 = tail call i32 @llvm.fshl.i32(i32 %90, i32 %90, i32 13)
  %92 = mul i32 %91, -1640531535
  %93 = getelementptr inbounds nuw i8, ptr %83, i64 4
  %94 = load i32, ptr %93, align 1
  %95 = mul i32 %94, -2048144777
  %96 = add i32 %95, %85
  %97 = tail call i32 @llvm.fshl.i32(i32 %96, i32 %96, i32 13)
  %98 = mul i32 %97, -1640531535
  %99 = getelementptr inbounds nuw i8, ptr %83, i64 8
  %100 = load i32, ptr %99, align 1
  %101 = mul i32 %100, -2048144777
  %102 = add i32 %101, %86
  %103 = tail call i32 @llvm.fshl.i32(i32 %102, i32 %102, i32 13)
  %104 = mul i32 %103, -1640531535
  %105 = getelementptr inbounds nuw i8, ptr %83, i64 12
  %106 = load i32, ptr %105, align 1
  %107 = mul i32 %106, -2048144777
  %108 = add i32 %107, %87
  %109 = tail call i32 @llvm.fshl.i32(i32 %108, i32 %108, i32 13)
  %110 = mul i32 %109, -1640531535
  %111 = getelementptr inbounds nuw i8, ptr %83, i64 16
  %112 = icmp ugt ptr %111, %71
  br i1 %112, label %113, label %82, !llvm.loop !20

113:                                              ; preds = %82
  store i32 %92, ptr %74, align 4, !tbaa !16
  store i32 %98, ptr %76, align 4, !tbaa !17
  store i32 %104, ptr %78, align 4, !tbaa !18
  store i32 %110, ptr %80, align 4, !tbaa !19
  br label %114

114:                                              ; preds = %113, %69
  %115 = phi ptr [ %111, %113 ], [ %70, %69 ]
  %116 = icmp ult ptr %115, %6
  br i1 %116, label %117, label %125

117:                                              ; preds = %114
  %118 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %119 = ptrtoint ptr %6 to i64
  %120 = ptrtoint ptr %115 to i64
  %121 = sub i64 %119, %120
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %118, ptr noundef nonnull readonly align 1 %115, i64 noundef %121, i1 noundef false) #24
  %122 = trunc i64 %121 to i32
  br label %123

123:                                              ; preds = %117, %22
  %124 = phi i32 [ %26, %22 ], [ %122, %117 ]
  store i32 %124, ptr %17, align 4, !tbaa !15
  br label %125

125:                                              ; preds = %123, %114, %3
  %126 = phi i32 [ 1, %3 ], [ 0, %114 ], [ 0, %123 ]
  ret i32 %126
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(argmem: read) uwtable(sync)
define i32 @XXH32_digest(ptr noundef readonly captures(none) %0) local_unnamed_addr #8 {
  %2 = getelementptr inbounds nuw i8, ptr %0, i64 4
  %3 = load i32, ptr %2, align 4, !tbaa !14
  %4 = icmp eq i32 %3, 0
  br i1 %4, label %21, label %5

5:                                                ; preds = %1
  %6 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %7 = load i32, ptr %6, align 4, !tbaa !16
  %8 = tail call i32 @llvm.fshl.i32(i32 %7, i32 %7, i32 1)
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 12
  %10 = load i32, ptr %9, align 4, !tbaa !17
  %11 = tail call i32 @llvm.fshl.i32(i32 %10, i32 %10, i32 7)
  %12 = add i32 %11, %8
  %13 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %14 = load i32, ptr %13, align 4, !tbaa !18
  %15 = tail call i32 @llvm.fshl.i32(i32 %14, i32 %14, i32 12)
  %16 = add i32 %12, %15
  %17 = getelementptr inbounds nuw i8, ptr %0, i64 20
  %18 = load i32, ptr %17, align 4, !tbaa !19
  %19 = tail call i32 @llvm.fshl.i32(i32 %18, i32 %18, i32 18)
  %20 = add i32 %16, %19
  br label %25

21:                                               ; preds = %1
  %22 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %23 = load i32, ptr %22, align 4, !tbaa !18
  %24 = add i32 %23, 374761393
  br label %25

25:                                               ; preds = %21, %5
  %26 = phi i32 [ %20, %5 ], [ %24, %21 ]
  %27 = load i32, ptr %0, align 4, !tbaa !12
  %28 = add i32 %27, %26
  %29 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %30 = getelementptr inbounds nuw i8, ptr %0, i64 40
  %31 = load i32, ptr %30, align 4, !tbaa !15
  %32 = zext i32 %31 to i64
  %33 = tail call fastcc i32 @XXH32_finalize(i32 noundef %28, ptr noundef nonnull %29, i64 noundef %32)
  ret i32 %33
}

; Function Attrs: mustprogress nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i32 @llvm.fshl.i32(i32, i32, i32) #9

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(argmem: read) uwtable(sync)
define internal fastcc i32 @XXH32_finalize(i32 noundef %0, ptr noundef readonly captures(none) %1, i64 noundef range(i64 0, 4294967296) %2) unnamed_addr #8 {
  %4 = and i64 %2, 15
  switch i64 %4, label %152 [
    i64 12, label %5
    i64 8, label %12
    i64 4, label %21
    i64 13, label %29
    i64 9, label %36
    i64 5, label %45
    i64 14, label %60
    i64 10, label %67
    i64 6, label %76
    i64 15, label %98
    i64 11, label %105
    i64 7, label %114
    i64 3, label %123
    i64 2, label %133
    i64 1, label %143
    i64 0, label %153
  ]

5:                                                ; preds = %3
  %6 = load i32, ptr %1, align 1
  %7 = mul i32 %6, -1028477379
  %8 = add i32 %7, %0
  %9 = getelementptr inbounds nuw i8, ptr %1, i64 4
  %10 = tail call i32 @llvm.fshl.i32(i32 %8, i32 %8, i32 17)
  %11 = mul i32 %10, 668265263
  br label %12

12:                                               ; preds = %3, %5
  %13 = phi i32 [ %11, %5 ], [ %0, %3 ]
  %14 = phi ptr [ %9, %5 ], [ %1, %3 ]
  %15 = load i32, ptr %14, align 1
  %16 = mul i32 %15, -1028477379
  %17 = add i32 %16, %13
  %18 = getelementptr inbounds nuw i8, ptr %14, i64 4
  %19 = tail call i32 @llvm.fshl.i32(i32 %17, i32 %17, i32 17)
  %20 = mul i32 %19, 668265263
  br label %21

21:                                               ; preds = %3, %12
  %22 = phi i32 [ %20, %12 ], [ %0, %3 ]
  %23 = phi ptr [ %18, %12 ], [ %1, %3 ]
  %24 = load i32, ptr %23, align 1
  %25 = mul i32 %24, -1028477379
  %26 = add i32 %25, %22
  %27 = tail call i32 @llvm.fshl.i32(i32 %26, i32 %26, i32 17)
  %28 = mul i32 %27, 668265263
  br label %153

29:                                               ; preds = %3
  %30 = load i32, ptr %1, align 1
  %31 = mul i32 %30, -1028477379
  %32 = add i32 %31, %0
  %33 = getelementptr inbounds nuw i8, ptr %1, i64 4
  %34 = tail call i32 @llvm.fshl.i32(i32 %32, i32 %32, i32 17)
  %35 = mul i32 %34, 668265263
  br label %36

36:                                               ; preds = %3, %29
  %37 = phi i32 [ %35, %29 ], [ %0, %3 ]
  %38 = phi ptr [ %33, %29 ], [ %1, %3 ]
  %39 = load i32, ptr %38, align 1
  %40 = mul i32 %39, -1028477379
  %41 = add i32 %40, %37
  %42 = getelementptr inbounds nuw i8, ptr %38, i64 4
  %43 = tail call i32 @llvm.fshl.i32(i32 %41, i32 %41, i32 17)
  %44 = mul i32 %43, 668265263
  br label %45

45:                                               ; preds = %3, %36
  %46 = phi i32 [ %44, %36 ], [ %0, %3 ]
  %47 = phi ptr [ %42, %36 ], [ %1, %3 ]
  %48 = load i32, ptr %47, align 1
  %49 = mul i32 %48, -1028477379
  %50 = add i32 %49, %46
  %51 = getelementptr inbounds nuw i8, ptr %47, i64 4
  %52 = tail call i32 @llvm.fshl.i32(i32 %50, i32 %50, i32 17)
  %53 = mul i32 %52, 668265263
  %54 = load i8, ptr %51, align 1, !tbaa !21
  %55 = zext i8 %54 to i32
  %56 = mul i32 %55, 374761393
  %57 = add i32 %53, %56
  %58 = tail call i32 @llvm.fshl.i32(i32 %57, i32 %57, i32 11)
  %59 = mul i32 %58, -1640531535
  br label %153

60:                                               ; preds = %3
  %61 = load i32, ptr %1, align 1
  %62 = mul i32 %61, -1028477379
  %63 = add i32 %62, %0
  %64 = getelementptr inbounds nuw i8, ptr %1, i64 4
  %65 = tail call i32 @llvm.fshl.i32(i32 %63, i32 %63, i32 17)
  %66 = mul i32 %65, 668265263
  br label %67

67:                                               ; preds = %3, %60
  %68 = phi i32 [ %66, %60 ], [ %0, %3 ]
  %69 = phi ptr [ %64, %60 ], [ %1, %3 ]
  %70 = load i32, ptr %69, align 1
  %71 = mul i32 %70, -1028477379
  %72 = add i32 %71, %68
  %73 = getelementptr inbounds nuw i8, ptr %69, i64 4
  %74 = tail call i32 @llvm.fshl.i32(i32 %72, i32 %72, i32 17)
  %75 = mul i32 %74, 668265263
  br label %76

76:                                               ; preds = %3, %67
  %77 = phi i32 [ %75, %67 ], [ %0, %3 ]
  %78 = phi ptr [ %73, %67 ], [ %1, %3 ]
  %79 = load i32, ptr %78, align 1
  %80 = mul i32 %79, -1028477379
  %81 = add i32 %80, %77
  %82 = getelementptr inbounds nuw i8, ptr %78, i64 4
  %83 = tail call i32 @llvm.fshl.i32(i32 %81, i32 %81, i32 17)
  %84 = mul i32 %83, 668265263
  %85 = getelementptr inbounds nuw i8, ptr %78, i64 5
  %86 = load i8, ptr %82, align 1, !tbaa !21
  %87 = zext i8 %86 to i32
  %88 = mul i32 %87, 374761393
  %89 = add i32 %84, %88
  %90 = tail call i32 @llvm.fshl.i32(i32 %89, i32 %89, i32 11)
  %91 = mul i32 %90, -1640531535
  %92 = load i8, ptr %85, align 1, !tbaa !21
  %93 = zext i8 %92 to i32
  %94 = mul i32 %93, 374761393
  %95 = add i32 %91, %94
  %96 = tail call i32 @llvm.fshl.i32(i32 %95, i32 %95, i32 11)
  %97 = mul i32 %96, -1640531535
  br label %153

98:                                               ; preds = %3
  %99 = load i32, ptr %1, align 1
  %100 = mul i32 %99, -1028477379
  %101 = add i32 %100, %0
  %102 = getelementptr inbounds nuw i8, ptr %1, i64 4
  %103 = tail call i32 @llvm.fshl.i32(i32 %101, i32 %101, i32 17)
  %104 = mul i32 %103, 668265263
  br label %105

105:                                              ; preds = %3, %98
  %106 = phi i32 [ %104, %98 ], [ %0, %3 ]
  %107 = phi ptr [ %102, %98 ], [ %1, %3 ]
  %108 = load i32, ptr %107, align 1
  %109 = mul i32 %108, -1028477379
  %110 = add i32 %109, %106
  %111 = getelementptr inbounds nuw i8, ptr %107, i64 4
  %112 = tail call i32 @llvm.fshl.i32(i32 %110, i32 %110, i32 17)
  %113 = mul i32 %112, 668265263
  br label %114

114:                                              ; preds = %3, %105
  %115 = phi i32 [ %113, %105 ], [ %0, %3 ]
  %116 = phi ptr [ %111, %105 ], [ %1, %3 ]
  %117 = load i32, ptr %116, align 1
  %118 = mul i32 %117, -1028477379
  %119 = add i32 %118, %115
  %120 = getelementptr inbounds nuw i8, ptr %116, i64 4
  %121 = tail call i32 @llvm.fshl.i32(i32 %119, i32 %119, i32 17)
  %122 = mul i32 %121, 668265263
  br label %123

123:                                              ; preds = %3, %114
  %124 = phi i32 [ %122, %114 ], [ %0, %3 ]
  %125 = phi ptr [ %120, %114 ], [ %1, %3 ]
  %126 = getelementptr inbounds nuw i8, ptr %125, i64 1
  %127 = load i8, ptr %125, align 1, !tbaa !21
  %128 = zext i8 %127 to i32
  %129 = mul i32 %128, 374761393
  %130 = add i32 %129, %124
  %131 = tail call i32 @llvm.fshl.i32(i32 %130, i32 %130, i32 11)
  %132 = mul i32 %131, -1640531535
  br label %133

133:                                              ; preds = %3, %123
  %134 = phi i32 [ %132, %123 ], [ %0, %3 ]
  %135 = phi ptr [ %126, %123 ], [ %1, %3 ]
  %136 = getelementptr inbounds nuw i8, ptr %135, i64 1
  %137 = load i8, ptr %135, align 1, !tbaa !21
  %138 = zext i8 %137 to i32
  %139 = mul i32 %138, 374761393
  %140 = add i32 %139, %134
  %141 = tail call i32 @llvm.fshl.i32(i32 %140, i32 %140, i32 11)
  %142 = mul i32 %141, -1640531535
  br label %143

143:                                              ; preds = %3, %133
  %144 = phi i32 [ %142, %133 ], [ %0, %3 ]
  %145 = phi ptr [ %136, %133 ], [ %1, %3 ]
  %146 = load i8, ptr %145, align 1, !tbaa !21
  %147 = zext i8 %146 to i32
  %148 = mul i32 %147, 374761393
  %149 = add i32 %148, %144
  %150 = tail call i32 @llvm.fshl.i32(i32 %149, i32 %149, i32 11)
  %151 = mul i32 %150, -1640531535
  br label %153

152:                                              ; preds = %3
  unreachable

153:                                              ; preds = %143, %3, %76, %45, %21
  %154 = phi i32 [ %97, %76 ], [ %59, %45 ], [ %28, %21 ], [ %151, %143 ], [ %0, %3 ]
  %155 = lshr i32 %154, 15
  %156 = xor i32 %155, %154
  %157 = mul i32 %156, -2048144777
  %158 = lshr i32 %157, 13
  %159 = xor i32 %158, %157
  %160 = mul i32 %159, -1028477379
  %161 = lshr i32 %160, 16
  %162 = xor i32 %161, %160
  ret i32 %162
}

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define void @XXH32_canonicalFromHash(ptr noundef %0, i32 noundef %1) local_unnamed_addr #4 {
  %3 = tail call noundef i32 @llvm.bswap.i32(i32 %1)
  store i32 %3, ptr %0, align 1
  ret void
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(argmem: read) uwtable(sync)
define noundef i32 @XXH32_hashFromCanonical(ptr noundef readonly captures(none) %0) local_unnamed_addr #8 {
  %2 = load i32, ptr %0, align 1
  %3 = tail call noundef i32 @llvm.bswap.i32(i32 %2)
  ret i32 %3
}

; Function Attrs: nofree norecurse nosync nounwind ssp memory(argmem: read) uwtable(sync)
define i64 @XXH64(ptr noundef %0, i64 noundef %1, i64 noundef %2) local_unnamed_addr #1 {
  %4 = ptrtoint ptr %0 to i64
  %5 = and i64 %4, 7
  %6 = icmp eq i64 %5, 0
  %7 = icmp ugt i64 %1, 31
  br i1 %6, label %8, label %80

8:                                                ; preds = %3
  br i1 %7, label %9, label %78

9:                                                ; preds = %8
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %11 = getelementptr inbounds i8, ptr %10, i64 -32
  %12 = add i64 %2, 6983438078262162902
  %13 = add i64 %2, -4417276706812531889
  %14 = add i64 %2, 7046029288634856825
  br label %15

15:                                               ; preds = %15, %9
  %16 = phi ptr [ %0, %9 ], [ %44, %15 ]
  %17 = phi i64 [ %12, %9 ], [ %25, %15 ]
  %18 = phi i64 [ %13, %9 ], [ %31, %15 ]
  %19 = phi i64 [ %2, %9 ], [ %37, %15 ]
  %20 = phi i64 [ %14, %9 ], [ %43, %15 ]
  %21 = load i64, ptr %16, align 8, !tbaa !22
  %22 = mul i64 %21, -4417276706812531889
  %23 = add i64 %22, %17
  %24 = tail call i64 @llvm.fshl.i64(i64 %23, i64 %23, i64 31)
  %25 = mul i64 %24, -7046029288634856825
  %26 = getelementptr inbounds nuw i8, ptr %16, i64 8
  %27 = load i64, ptr %26, align 8, !tbaa !22
  %28 = mul i64 %27, -4417276706812531889
  %29 = add i64 %28, %18
  %30 = tail call i64 @llvm.fshl.i64(i64 %29, i64 %29, i64 31)
  %31 = mul i64 %30, -7046029288634856825
  %32 = getelementptr inbounds nuw i8, ptr %16, i64 16
  %33 = load i64, ptr %32, align 8, !tbaa !22
  %34 = mul i64 %33, -4417276706812531889
  %35 = add i64 %34, %19
  %36 = tail call i64 @llvm.fshl.i64(i64 %35, i64 %35, i64 31)
  %37 = mul i64 %36, -7046029288634856825
  %38 = getelementptr inbounds nuw i8, ptr %16, i64 24
  %39 = load i64, ptr %38, align 8, !tbaa !22
  %40 = mul i64 %39, -4417276706812531889
  %41 = add i64 %40, %20
  %42 = tail call i64 @llvm.fshl.i64(i64 %41, i64 %41, i64 31)
  %43 = mul i64 %42, -7046029288634856825
  %44 = getelementptr inbounds nuw i8, ptr %16, i64 32
  %45 = icmp ugt ptr %44, %11
  br i1 %45, label %46, label %15, !llvm.loop !24

46:                                               ; preds = %15
  %47 = tail call i64 @llvm.fshl.i64(i64 %25, i64 %25, i64 1)
  %48 = tail call i64 @llvm.fshl.i64(i64 %31, i64 %31, i64 7)
  %49 = add i64 %48, %47
  %50 = tail call i64 @llvm.fshl.i64(i64 %37, i64 %37, i64 12)
  %51 = add i64 %49, %50
  %52 = tail call i64 @llvm.fshl.i64(i64 %43, i64 %43, i64 18)
  %53 = add i64 %51, %52
  %54 = mul i64 %24, -2381459717836149591
  %55 = tail call i64 @llvm.fshl.i64(i64 %54, i64 %54, i64 31)
  %56 = mul i64 %55, -7046029288634856825
  %57 = xor i64 %53, %56
  %58 = mul i64 %57, -7046029288634856825
  %59 = add i64 %58, -8796714831421723037
  %60 = mul i64 %30, -2381459717836149591
  %61 = tail call i64 @llvm.fshl.i64(i64 %60, i64 %60, i64 31)
  %62 = mul i64 %61, -7046029288634856825
  %63 = xor i64 %59, %62
  %64 = mul i64 %63, -7046029288634856825
  %65 = add i64 %64, -8796714831421723037
  %66 = mul i64 %36, -2381459717836149591
  %67 = tail call i64 @llvm.fshl.i64(i64 %66, i64 %66, i64 31)
  %68 = mul i64 %67, -7046029288634856825
  %69 = xor i64 %65, %68
  %70 = mul i64 %69, -7046029288634856825
  %71 = add i64 %70, -8796714831421723037
  %72 = mul i64 %42, -2381459717836149591
  %73 = tail call i64 @llvm.fshl.i64(i64 %72, i64 %72, i64 31)
  %74 = mul i64 %73, -7046029288634856825
  %75 = xor i64 %71, %74
  %76 = mul i64 %75, -7046029288634856825
  %77 = add i64 %76, -8796714831421723037
  br label %152

78:                                               ; preds = %8
  %79 = add i64 %2, 2870177450012600261
  br label %152

80:                                               ; preds = %3
  br i1 %7, label %81, label %150

81:                                               ; preds = %80
  %82 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %83 = getelementptr inbounds i8, ptr %82, i64 -32
  %84 = add i64 %2, 6983438078262162902
  %85 = add i64 %2, -4417276706812531889
  %86 = add i64 %2, 7046029288634856825
  br label %87

87:                                               ; preds = %87, %81
  %88 = phi ptr [ %0, %81 ], [ %116, %87 ]
  %89 = phi i64 [ %84, %81 ], [ %97, %87 ]
  %90 = phi i64 [ %85, %81 ], [ %103, %87 ]
  %91 = phi i64 [ %2, %81 ], [ %109, %87 ]
  %92 = phi i64 [ %86, %81 ], [ %115, %87 ]
  %93 = load i64, ptr %88, align 1
  %94 = mul i64 %93, -4417276706812531889
  %95 = add i64 %94, %89
  %96 = tail call i64 @llvm.fshl.i64(i64 %95, i64 %95, i64 31)
  %97 = mul i64 %96, -7046029288634856825
  %98 = getelementptr inbounds nuw i8, ptr %88, i64 8
  %99 = load i64, ptr %98, align 1
  %100 = mul i64 %99, -4417276706812531889
  %101 = add i64 %100, %90
  %102 = tail call i64 @llvm.fshl.i64(i64 %101, i64 %101, i64 31)
  %103 = mul i64 %102, -7046029288634856825
  %104 = getelementptr inbounds nuw i8, ptr %88, i64 16
  %105 = load i64, ptr %104, align 1
  %106 = mul i64 %105, -4417276706812531889
  %107 = add i64 %106, %91
  %108 = tail call i64 @llvm.fshl.i64(i64 %107, i64 %107, i64 31)
  %109 = mul i64 %108, -7046029288634856825
  %110 = getelementptr inbounds nuw i8, ptr %88, i64 24
  %111 = load i64, ptr %110, align 1
  %112 = mul i64 %111, -4417276706812531889
  %113 = add i64 %112, %92
  %114 = tail call i64 @llvm.fshl.i64(i64 %113, i64 %113, i64 31)
  %115 = mul i64 %114, -7046029288634856825
  %116 = getelementptr inbounds nuw i8, ptr %88, i64 32
  %117 = icmp ugt ptr %116, %83
  br i1 %117, label %118, label %87, !llvm.loop !24

118:                                              ; preds = %87
  %119 = tail call i64 @llvm.fshl.i64(i64 %97, i64 %97, i64 1)
  %120 = tail call i64 @llvm.fshl.i64(i64 %103, i64 %103, i64 7)
  %121 = add i64 %120, %119
  %122 = tail call i64 @llvm.fshl.i64(i64 %109, i64 %109, i64 12)
  %123 = add i64 %121, %122
  %124 = tail call i64 @llvm.fshl.i64(i64 %115, i64 %115, i64 18)
  %125 = add i64 %123, %124
  %126 = mul i64 %96, -2381459717836149591
  %127 = tail call i64 @llvm.fshl.i64(i64 %126, i64 %126, i64 31)
  %128 = mul i64 %127, -7046029288634856825
  %129 = xor i64 %125, %128
  %130 = mul i64 %129, -7046029288634856825
  %131 = add i64 %130, -8796714831421723037
  %132 = mul i64 %102, -2381459717836149591
  %133 = tail call i64 @llvm.fshl.i64(i64 %132, i64 %132, i64 31)
  %134 = mul i64 %133, -7046029288634856825
  %135 = xor i64 %131, %134
  %136 = mul i64 %135, -7046029288634856825
  %137 = add i64 %136, -8796714831421723037
  %138 = mul i64 %108, -2381459717836149591
  %139 = tail call i64 @llvm.fshl.i64(i64 %138, i64 %138, i64 31)
  %140 = mul i64 %139, -7046029288634856825
  %141 = xor i64 %137, %140
  %142 = mul i64 %141, -7046029288634856825
  %143 = add i64 %142, -8796714831421723037
  %144 = mul i64 %114, -2381459717836149591
  %145 = tail call i64 @llvm.fshl.i64(i64 %144, i64 %144, i64 31)
  %146 = mul i64 %145, -7046029288634856825
  %147 = xor i64 %143, %146
  %148 = mul i64 %147, -7046029288634856825
  %149 = add i64 %148, -8796714831421723037
  br label %152

150:                                              ; preds = %80
  %151 = add i64 %2, 2870177450012600261
  br label %152

152:                                              ; preds = %150, %118, %78, %46
  %153 = phi i64 [ %77, %46 ], [ %79, %78 ], [ %149, %118 ], [ %151, %150 ]
  %154 = phi ptr [ %44, %46 ], [ %0, %78 ], [ %116, %118 ], [ %0, %150 ]
  %155 = add i64 %153, %1
  %156 = tail call fastcc i64 @XXH64_finalize(i64 noundef %155, ptr noundef %154, i64 noundef %1)
  ret i64 %156
}

; Function Attrs: mustprogress nofree nounwind ssp willreturn memory(inaccessiblemem: readwrite) uwtable(sync)
define noalias noundef ptr @XXH64_createState() local_unnamed_addr #2 {
  %1 = tail call noalias noundef dereferenceable_or_null(88) ptr @malloc(i64 noundef 88) #23
  ret ptr %1
}

; Function Attrs: mustprogress nounwind ssp willreturn memory(argmem: readwrite, inaccessiblemem: readwrite) uwtable(sync)
define noundef i32 @XXH64_freeState(ptr noundef captures(none) %0) local_unnamed_addr #3 {
  tail call void @free(ptr noundef %0)
  ret i32 0
}

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define void @XXH64_copyState(ptr noundef %0, ptr noundef readonly captures(none) %1) local_unnamed_addr #4 {
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(88) %0, ptr noundef nonnull align 1 dereferenceable(88) %1, i64 noundef 88, i1 noundef false) #24
  ret void
}

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define noundef i32 @XXH64_reset(ptr noundef %0, i64 noundef %1) local_unnamed_addr #4 {
  %3 = alloca { [4 x i64], i32, [2 x i32] }, align 8
  call void @llvm.lifetime.start.p0(i64 48, ptr nonnull %3)
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(48) %3, i8 0, i64 48, i1 false)
  %4 = add i64 %1, 6983438078262162902
  %5 = add i64 %1, -4417276706812531889
  %6 = add i64 %1, 7046029288634856825
  store i64 0, ptr %0, align 1
  %7 = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i64 %4, ptr %7, align 1
  %8 = getelementptr inbounds nuw i8, ptr %0, i64 16
  store i64 %5, ptr %8, align 1
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 24
  store i64 %1, ptr %9, align 1
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 32
  store i64 %6, ptr %10, align 1
  %11 = getelementptr inbounds nuw i8, ptr %0, i64 40
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(40) %11, ptr noundef nonnull align 8 dereferenceable(40) %3, i64 40, i1 false)
  call void @llvm.lifetime.end.p0(i64 48, ptr nonnull %3)
  ret i32 0
}

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define range(i32 0, 2) i32 @XXH64_update(ptr noundef %0, ptr noundef %1, i64 noundef %2) local_unnamed_addr #4 {
  %4 = icmp eq ptr %1, null
  br i1 %4, label %119, label %5

5:                                                ; preds = %3
  %6 = getelementptr inbounds nuw i8, ptr %1, i64 %2
  %7 = load i64, ptr %0, align 8, !tbaa !25
  %8 = add i64 %7, %2
  store i64 %8, ptr %0, align 8, !tbaa !25
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 72
  %10 = load i32, ptr %9, align 8, !tbaa !27
  %11 = zext i32 %10 to i64
  %12 = add i64 %2, %11
  %13 = icmp ult i64 %12, 32
  br i1 %13, label %14, label %20

14:                                               ; preds = %5
  %15 = getelementptr inbounds nuw i8, ptr %0, i64 40
  %16 = getelementptr inbounds nuw i8, ptr %15, i64 %11
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %16, ptr noundef nonnull readonly align 1 %1, i64 noundef %2, i1 noundef false) #24
  %17 = trunc i64 %2 to i32
  %18 = load i32, ptr %9, align 8, !tbaa !27
  %19 = add i32 %18, %17
  br label %117

20:                                               ; preds = %5
  %21 = icmp eq i32 %10, 0
  br i1 %21, label %62, label %22

22:                                               ; preds = %20
  %23 = getelementptr inbounds nuw i8, ptr %0, i64 40
  %24 = getelementptr inbounds nuw i8, ptr %23, i64 %11
  %25 = sub i32 32, %10
  %26 = zext i32 %25 to i64
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %24, ptr noundef nonnull readonly align 1 %1, i64 noundef %26, i1 noundef false) #24
  %27 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %28 = load i64, ptr %27, align 8, !tbaa !28
  %29 = load i64, ptr %23, align 1
  %30 = mul i64 %29, -4417276706812531889
  %31 = add i64 %30, %28
  %32 = tail call i64 @llvm.fshl.i64(i64 %31, i64 %31, i64 31)
  %33 = mul i64 %32, -7046029288634856825
  store i64 %33, ptr %27, align 8, !tbaa !28
  %34 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %35 = load i64, ptr %34, align 8, !tbaa !29
  %36 = getelementptr inbounds nuw i8, ptr %0, i64 48
  %37 = load i64, ptr %36, align 1
  %38 = mul i64 %37, -4417276706812531889
  %39 = add i64 %38, %35
  %40 = tail call i64 @llvm.fshl.i64(i64 %39, i64 %39, i64 31)
  %41 = mul i64 %40, -7046029288634856825
  store i64 %41, ptr %34, align 8, !tbaa !29
  %42 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %43 = load i64, ptr %42, align 8, !tbaa !30
  %44 = getelementptr inbounds nuw i8, ptr %0, i64 56
  %45 = load i64, ptr %44, align 1
  %46 = mul i64 %45, -4417276706812531889
  %47 = add i64 %46, %43
  %48 = tail call i64 @llvm.fshl.i64(i64 %47, i64 %47, i64 31)
  %49 = mul i64 %48, -7046029288634856825
  store i64 %49, ptr %42, align 8, !tbaa !30
  %50 = getelementptr inbounds nuw i8, ptr %0, i64 32
  %51 = load i64, ptr %50, align 8, !tbaa !31
  %52 = getelementptr inbounds nuw i8, ptr %0, i64 64
  %53 = load i64, ptr %52, align 1
  %54 = mul i64 %53, -4417276706812531889
  %55 = add i64 %54, %51
  %56 = tail call i64 @llvm.fshl.i64(i64 %55, i64 %55, i64 31)
  %57 = mul i64 %56, -7046029288634856825
  store i64 %57, ptr %50, align 8, !tbaa !31
  %58 = load i32, ptr %9, align 8, !tbaa !27
  %59 = sub i32 32, %58
  %60 = zext i32 %59 to i64
  %61 = getelementptr inbounds nuw i8, ptr %1, i64 %60
  store i32 0, ptr %9, align 8, !tbaa !27
  br label %62

62:                                               ; preds = %22, %20
  %63 = phi ptr [ %61, %22 ], [ %1, %20 ]
  %64 = getelementptr inbounds nuw i8, ptr %63, i64 32
  %65 = icmp ugt ptr %64, %6
  br i1 %65, label %108, label %66

66:                                               ; preds = %62
  %67 = getelementptr inbounds i8, ptr %6, i64 -32
  %68 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %69 = load i64, ptr %68, align 8, !tbaa !28
  %70 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %71 = load i64, ptr %70, align 8, !tbaa !29
  %72 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %73 = load i64, ptr %72, align 8, !tbaa !30
  %74 = getelementptr inbounds nuw i8, ptr %0, i64 32
  %75 = load i64, ptr %74, align 8, !tbaa !31
  br label %76

76:                                               ; preds = %76, %66
  %77 = phi ptr [ %63, %66 ], [ %105, %76 ]
  %78 = phi i64 [ %69, %66 ], [ %86, %76 ]
  %79 = phi i64 [ %71, %66 ], [ %92, %76 ]
  %80 = phi i64 [ %73, %66 ], [ %98, %76 ]
  %81 = phi i64 [ %75, %66 ], [ %104, %76 ]
  %82 = load i64, ptr %77, align 1
  %83 = mul i64 %82, -4417276706812531889
  %84 = add i64 %83, %78
  %85 = tail call i64 @llvm.fshl.i64(i64 %84, i64 %84, i64 31)
  %86 = mul i64 %85, -7046029288634856825
  %87 = getelementptr inbounds nuw i8, ptr %77, i64 8
  %88 = load i64, ptr %87, align 1
  %89 = mul i64 %88, -4417276706812531889
  %90 = add i64 %89, %79
  %91 = tail call i64 @llvm.fshl.i64(i64 %90, i64 %90, i64 31)
  %92 = mul i64 %91, -7046029288634856825
  %93 = getelementptr inbounds nuw i8, ptr %77, i64 16
  %94 = load i64, ptr %93, align 1
  %95 = mul i64 %94, -4417276706812531889
  %96 = add i64 %95, %80
  %97 = tail call i64 @llvm.fshl.i64(i64 %96, i64 %96, i64 31)
  %98 = mul i64 %97, -7046029288634856825
  %99 = getelementptr inbounds nuw i8, ptr %77, i64 24
  %100 = load i64, ptr %99, align 1
  %101 = mul i64 %100, -4417276706812531889
  %102 = add i64 %101, %81
  %103 = tail call i64 @llvm.fshl.i64(i64 %102, i64 %102, i64 31)
  %104 = mul i64 %103, -7046029288634856825
  %105 = getelementptr inbounds nuw i8, ptr %77, i64 32
  %106 = icmp ugt ptr %105, %67
  br i1 %106, label %107, label %76, !llvm.loop !32

107:                                              ; preds = %76
  store i64 %86, ptr %68, align 8, !tbaa !28
  store i64 %92, ptr %70, align 8, !tbaa !29
  store i64 %98, ptr %72, align 8, !tbaa !30
  store i64 %104, ptr %74, align 8, !tbaa !31
  br label %108

108:                                              ; preds = %107, %62
  %109 = phi ptr [ %105, %107 ], [ %63, %62 ]
  %110 = icmp ult ptr %109, %6
  br i1 %110, label %111, label %119

111:                                              ; preds = %108
  %112 = getelementptr inbounds nuw i8, ptr %0, i64 40
  %113 = ptrtoint ptr %6 to i64
  %114 = ptrtoint ptr %109 to i64
  %115 = sub i64 %113, %114
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %112, ptr noundef nonnull readonly align 1 %109, i64 noundef %115, i1 noundef false) #24
  %116 = trunc i64 %115 to i32
  br label %117

117:                                              ; preds = %111, %14
  %118 = phi i32 [ %19, %14 ], [ %116, %111 ]
  store i32 %118, ptr %9, align 8, !tbaa !27
  br label %119

119:                                              ; preds = %117, %108, %3
  %120 = phi i32 [ 1, %3 ], [ 0, %108 ], [ 0, %117 ]
  ret i32 %120
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(argmem: read) uwtable(sync)
define i64 @XXH64_digest(ptr noundef readonly %0) local_unnamed_addr #8 {
  %2 = load i64, ptr %0, align 8, !tbaa !25
  %3 = icmp ugt i64 %2, 31
  br i1 %3, label %4, label %44

4:                                                ; preds = %1
  %5 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %6 = load i64, ptr %5, align 8, !tbaa !28
  %7 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %8 = load i64, ptr %7, align 8, !tbaa !29
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %10 = load i64, ptr %9, align 8, !tbaa !30
  %11 = getelementptr inbounds nuw i8, ptr %0, i64 32
  %12 = load i64, ptr %11, align 8, !tbaa !31
  %13 = tail call i64 @llvm.fshl.i64(i64 %6, i64 %6, i64 1)
  %14 = tail call i64 @llvm.fshl.i64(i64 %8, i64 %8, i64 7)
  %15 = add i64 %14, %13
  %16 = tail call i64 @llvm.fshl.i64(i64 %10, i64 %10, i64 12)
  %17 = add i64 %15, %16
  %18 = tail call i64 @llvm.fshl.i64(i64 %12, i64 %12, i64 18)
  %19 = add i64 %17, %18
  %20 = mul i64 %6, -4417276706812531889
  %21 = tail call i64 @llvm.fshl.i64(i64 %20, i64 %20, i64 31)
  %22 = mul i64 %21, -7046029288634856825
  %23 = xor i64 %19, %22
  %24 = mul i64 %23, -7046029288634856825
  %25 = add i64 %24, -8796714831421723037
  %26 = mul i64 %8, -4417276706812531889
  %27 = tail call i64 @llvm.fshl.i64(i64 %26, i64 %26, i64 31)
  %28 = mul i64 %27, -7046029288634856825
  %29 = xor i64 %25, %28
  %30 = mul i64 %29, -7046029288634856825
  %31 = add i64 %30, -8796714831421723037
  %32 = mul i64 %10, -4417276706812531889
  %33 = tail call i64 @llvm.fshl.i64(i64 %32, i64 %32, i64 31)
  %34 = mul i64 %33, -7046029288634856825
  %35 = xor i64 %31, %34
  %36 = mul i64 %35, -7046029288634856825
  %37 = add i64 %36, -8796714831421723037
  %38 = mul i64 %12, -4417276706812531889
  %39 = tail call i64 @llvm.fshl.i64(i64 %38, i64 %38, i64 31)
  %40 = mul i64 %39, -7046029288634856825
  %41 = xor i64 %37, %40
  %42 = mul i64 %41, -7046029288634856825
  %43 = add i64 %42, -8796714831421723037
  br label %48

44:                                               ; preds = %1
  %45 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %46 = load i64, ptr %45, align 8, !tbaa !30
  %47 = add i64 %46, 2870177450012600261
  br label %48

48:                                               ; preds = %44, %4
  %49 = phi i64 [ %43, %4 ], [ %47, %44 ]
  %50 = add i64 %49, %2
  %51 = getelementptr inbounds nuw i8, ptr %0, i64 40
  %52 = tail call fastcc i64 @XXH64_finalize(i64 noundef %50, ptr noundef nonnull %51, i64 noundef %2)
  ret i64 %52
}

; Function Attrs: mustprogress nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.fshl.i64(i64, i64, i64) #9

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(argmem: read) uwtable(sync)
define internal fastcc i64 @XXH64_finalize(i64 noundef %0, ptr noundef readonly %1, i64 noundef %2) unnamed_addr #8 {
  %4 = and i64 %2, 31
  switch i64 %4, label %406 [
    i64 24, label %5
    i64 16, label %15
    i64 8, label %27
    i64 28, label %38
    i64 20, label %48
    i64 12, label %60
    i64 4, label %72
    i64 25, label %82
    i64 17, label %92
    i64 9, label %104
    i64 29, label %122
    i64 21, label %132
    i64 13, label %144
    i64 5, label %156
    i64 26, label %173
    i64 18, label %183
    i64 10, label %195
    i64 30, label %220
    i64 22, label %230
    i64 14, label %242
    i64 6, label %254
    i64 27, label %278
    i64 19, label %288
    i64 11, label %300
    i64 31, label %332
    i64 23, label %342
    i64 15, label %354
    i64 7, label %366
    i64 3, label %377
    i64 2, label %387
    i64 1, label %397
    i64 0, label %407
  ]

5:                                                ; preds = %3
  %6 = load i64, ptr %1, align 1
  %7 = mul i64 %6, -4417276706812531889
  %8 = tail call i64 @llvm.fshl.i64(i64 %7, i64 %7, i64 31)
  %9 = mul i64 %8, -7046029288634856825
  %10 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %11 = xor i64 %9, %0
  %12 = tail call i64 @llvm.fshl.i64(i64 %11, i64 %11, i64 27)
  %13 = mul i64 %12, -7046029288634856825
  %14 = add i64 %13, -8796714831421723037
  br label %15

15:                                               ; preds = %3, %5
  %16 = phi ptr [ %10, %5 ], [ %1, %3 ]
  %17 = phi i64 [ %14, %5 ], [ %0, %3 ]
  %18 = load i64, ptr %16, align 1
  %19 = mul i64 %18, -4417276706812531889
  %20 = tail call i64 @llvm.fshl.i64(i64 %19, i64 %19, i64 31)
  %21 = mul i64 %20, -7046029288634856825
  %22 = getelementptr inbounds nuw i8, ptr %16, i64 8
  %23 = xor i64 %21, %17
  %24 = tail call i64 @llvm.fshl.i64(i64 %23, i64 %23, i64 27)
  %25 = mul i64 %24, -7046029288634856825
  %26 = add i64 %25, -8796714831421723037
  br label %27

27:                                               ; preds = %3, %15
  %28 = phi ptr [ %22, %15 ], [ %1, %3 ]
  %29 = phi i64 [ %26, %15 ], [ %0, %3 ]
  %30 = load i64, ptr %28, align 1
  %31 = mul i64 %30, -4417276706812531889
  %32 = tail call i64 @llvm.fshl.i64(i64 %31, i64 %31, i64 31)
  %33 = mul i64 %32, -7046029288634856825
  %34 = xor i64 %33, %29
  %35 = tail call i64 @llvm.fshl.i64(i64 %34, i64 %34, i64 27)
  %36 = mul i64 %35, -7046029288634856825
  %37 = add i64 %36, -8796714831421723037
  br label %407

38:                                               ; preds = %3
  %39 = load i64, ptr %1, align 1
  %40 = mul i64 %39, -4417276706812531889
  %41 = tail call i64 @llvm.fshl.i64(i64 %40, i64 %40, i64 31)
  %42 = mul i64 %41, -7046029288634856825
  %43 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %44 = xor i64 %42, %0
  %45 = tail call i64 @llvm.fshl.i64(i64 %44, i64 %44, i64 27)
  %46 = mul i64 %45, -7046029288634856825
  %47 = add i64 %46, -8796714831421723037
  br label %48

48:                                               ; preds = %3, %38
  %49 = phi ptr [ %43, %38 ], [ %1, %3 ]
  %50 = phi i64 [ %47, %38 ], [ %0, %3 ]
  %51 = load i64, ptr %49, align 1
  %52 = mul i64 %51, -4417276706812531889
  %53 = tail call i64 @llvm.fshl.i64(i64 %52, i64 %52, i64 31)
  %54 = mul i64 %53, -7046029288634856825
  %55 = getelementptr inbounds nuw i8, ptr %49, i64 8
  %56 = xor i64 %54, %50
  %57 = tail call i64 @llvm.fshl.i64(i64 %56, i64 %56, i64 27)
  %58 = mul i64 %57, -7046029288634856825
  %59 = add i64 %58, -8796714831421723037
  br label %60

60:                                               ; preds = %3, %48
  %61 = phi ptr [ %55, %48 ], [ %1, %3 ]
  %62 = phi i64 [ %59, %48 ], [ %0, %3 ]
  %63 = load i64, ptr %61, align 1
  %64 = mul i64 %63, -4417276706812531889
  %65 = tail call i64 @llvm.fshl.i64(i64 %64, i64 %64, i64 31)
  %66 = mul i64 %65, -7046029288634856825
  %67 = getelementptr inbounds nuw i8, ptr %61, i64 8
  %68 = xor i64 %66, %62
  %69 = tail call i64 @llvm.fshl.i64(i64 %68, i64 %68, i64 27)
  %70 = mul i64 %69, -7046029288634856825
  %71 = add i64 %70, -8796714831421723037
  br label %72

72:                                               ; preds = %3, %60
  %73 = phi ptr [ %67, %60 ], [ %1, %3 ]
  %74 = phi i64 [ %71, %60 ], [ %0, %3 ]
  %75 = load i32, ptr %73, align 1
  %76 = zext i32 %75 to i64
  %77 = mul i64 %76, -7046029288634856825
  %78 = xor i64 %77, %74
  %79 = tail call i64 @llvm.fshl.i64(i64 %78, i64 %78, i64 23)
  %80 = mul i64 %79, -4417276706812531889
  %81 = add i64 %80, 1609587929392839161
  br label %407

82:                                               ; preds = %3
  %83 = load i64, ptr %1, align 1
  %84 = mul i64 %83, -4417276706812531889
  %85 = tail call i64 @llvm.fshl.i64(i64 %84, i64 %84, i64 31)
  %86 = mul i64 %85, -7046029288634856825
  %87 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %88 = xor i64 %86, %0
  %89 = tail call i64 @llvm.fshl.i64(i64 %88, i64 %88, i64 27)
  %90 = mul i64 %89, -7046029288634856825
  %91 = add i64 %90, -8796714831421723037
  br label %92

92:                                               ; preds = %3, %82
  %93 = phi ptr [ %87, %82 ], [ %1, %3 ]
  %94 = phi i64 [ %91, %82 ], [ %0, %3 ]
  %95 = load i64, ptr %93, align 1
  %96 = mul i64 %95, -4417276706812531889
  %97 = tail call i64 @llvm.fshl.i64(i64 %96, i64 %96, i64 31)
  %98 = mul i64 %97, -7046029288634856825
  %99 = getelementptr inbounds nuw i8, ptr %93, i64 8
  %100 = xor i64 %98, %94
  %101 = tail call i64 @llvm.fshl.i64(i64 %100, i64 %100, i64 27)
  %102 = mul i64 %101, -7046029288634856825
  %103 = add i64 %102, -8796714831421723037
  br label %104

104:                                              ; preds = %3, %92
  %105 = phi ptr [ %99, %92 ], [ %1, %3 ]
  %106 = phi i64 [ %103, %92 ], [ %0, %3 ]
  %107 = load i64, ptr %105, align 1
  %108 = mul i64 %107, -4417276706812531889
  %109 = tail call i64 @llvm.fshl.i64(i64 %108, i64 %108, i64 31)
  %110 = mul i64 %109, -7046029288634856825
  %111 = getelementptr inbounds nuw i8, ptr %105, i64 8
  %112 = xor i64 %110, %106
  %113 = tail call i64 @llvm.fshl.i64(i64 %112, i64 %112, i64 27)
  %114 = mul i64 %113, -7046029288634856825
  %115 = add i64 %114, -8796714831421723037
  %116 = load i8, ptr %111, align 1, !tbaa !21
  %117 = zext i8 %116 to i64
  %118 = mul i64 %117, 2870177450012600261
  %119 = xor i64 %115, %118
  %120 = tail call i64 @llvm.fshl.i64(i64 %119, i64 %119, i64 11)
  %121 = mul i64 %120, -7046029288634856825
  br label %407

122:                                              ; preds = %3
  %123 = load i64, ptr %1, align 1
  %124 = mul i64 %123, -4417276706812531889
  %125 = tail call i64 @llvm.fshl.i64(i64 %124, i64 %124, i64 31)
  %126 = mul i64 %125, -7046029288634856825
  %127 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %128 = xor i64 %126, %0
  %129 = tail call i64 @llvm.fshl.i64(i64 %128, i64 %128, i64 27)
  %130 = mul i64 %129, -7046029288634856825
  %131 = add i64 %130, -8796714831421723037
  br label %132

132:                                              ; preds = %3, %122
  %133 = phi ptr [ %127, %122 ], [ %1, %3 ]
  %134 = phi i64 [ %131, %122 ], [ %0, %3 ]
  %135 = load i64, ptr %133, align 1
  %136 = mul i64 %135, -4417276706812531889
  %137 = tail call i64 @llvm.fshl.i64(i64 %136, i64 %136, i64 31)
  %138 = mul i64 %137, -7046029288634856825
  %139 = getelementptr inbounds nuw i8, ptr %133, i64 8
  %140 = xor i64 %138, %134
  %141 = tail call i64 @llvm.fshl.i64(i64 %140, i64 %140, i64 27)
  %142 = mul i64 %141, -7046029288634856825
  %143 = add i64 %142, -8796714831421723037
  br label %144

144:                                              ; preds = %3, %132
  %145 = phi ptr [ %139, %132 ], [ %1, %3 ]
  %146 = phi i64 [ %143, %132 ], [ %0, %3 ]
  %147 = load i64, ptr %145, align 1
  %148 = mul i64 %147, -4417276706812531889
  %149 = tail call i64 @llvm.fshl.i64(i64 %148, i64 %148, i64 31)
  %150 = mul i64 %149, -7046029288634856825
  %151 = getelementptr inbounds nuw i8, ptr %145, i64 8
  %152 = xor i64 %150, %146
  %153 = tail call i64 @llvm.fshl.i64(i64 %152, i64 %152, i64 27)
  %154 = mul i64 %153, -7046029288634856825
  %155 = add i64 %154, -8796714831421723037
  br label %156

156:                                              ; preds = %3, %144
  %157 = phi ptr [ %151, %144 ], [ %1, %3 ]
  %158 = phi i64 [ %155, %144 ], [ %0, %3 ]
  %159 = load i32, ptr %157, align 1
  %160 = zext i32 %159 to i64
  %161 = mul i64 %160, -7046029288634856825
  %162 = xor i64 %161, %158
  %163 = getelementptr inbounds nuw i8, ptr %157, i64 4
  %164 = tail call i64 @llvm.fshl.i64(i64 %162, i64 %162, i64 23)
  %165 = mul i64 %164, -4417276706812531889
  %166 = add i64 %165, 1609587929392839161
  %167 = load i8, ptr %163, align 1, !tbaa !21
  %168 = zext i8 %167 to i64
  %169 = mul i64 %168, 2870177450012600261
  %170 = xor i64 %166, %169
  %171 = tail call i64 @llvm.fshl.i64(i64 %170, i64 %170, i64 11)
  %172 = mul i64 %171, -7046029288634856825
  br label %407

173:                                              ; preds = %3
  %174 = load i64, ptr %1, align 1
  %175 = mul i64 %174, -4417276706812531889
  %176 = tail call i64 @llvm.fshl.i64(i64 %175, i64 %175, i64 31)
  %177 = mul i64 %176, -7046029288634856825
  %178 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %179 = xor i64 %177, %0
  %180 = tail call i64 @llvm.fshl.i64(i64 %179, i64 %179, i64 27)
  %181 = mul i64 %180, -7046029288634856825
  %182 = add i64 %181, -8796714831421723037
  br label %183

183:                                              ; preds = %3, %173
  %184 = phi ptr [ %178, %173 ], [ %1, %3 ]
  %185 = phi i64 [ %182, %173 ], [ %0, %3 ]
  %186 = load i64, ptr %184, align 1
  %187 = mul i64 %186, -4417276706812531889
  %188 = tail call i64 @llvm.fshl.i64(i64 %187, i64 %187, i64 31)
  %189 = mul i64 %188, -7046029288634856825
  %190 = getelementptr inbounds nuw i8, ptr %184, i64 8
  %191 = xor i64 %189, %185
  %192 = tail call i64 @llvm.fshl.i64(i64 %191, i64 %191, i64 27)
  %193 = mul i64 %192, -7046029288634856825
  %194 = add i64 %193, -8796714831421723037
  br label %195

195:                                              ; preds = %3, %183
  %196 = phi ptr [ %190, %183 ], [ %1, %3 ]
  %197 = phi i64 [ %194, %183 ], [ %0, %3 ]
  %198 = load i64, ptr %196, align 1
  %199 = mul i64 %198, -4417276706812531889
  %200 = tail call i64 @llvm.fshl.i64(i64 %199, i64 %199, i64 31)
  %201 = mul i64 %200, -7046029288634856825
  %202 = getelementptr inbounds nuw i8, ptr %196, i64 8
  %203 = xor i64 %201, %197
  %204 = tail call i64 @llvm.fshl.i64(i64 %203, i64 %203, i64 27)
  %205 = mul i64 %204, -7046029288634856825
  %206 = add i64 %205, -8796714831421723037
  %207 = getelementptr inbounds nuw i8, ptr %196, i64 9
  %208 = load i8, ptr %202, align 1, !tbaa !21
  %209 = zext i8 %208 to i64
  %210 = mul i64 %209, 2870177450012600261
  %211 = xor i64 %206, %210
  %212 = tail call i64 @llvm.fshl.i64(i64 %211, i64 %211, i64 11)
  %213 = mul i64 %212, -7046029288634856825
  %214 = load i8, ptr %207, align 1, !tbaa !21
  %215 = zext i8 %214 to i64
  %216 = mul i64 %215, 2870177450012600261
  %217 = xor i64 %213, %216
  %218 = tail call i64 @llvm.fshl.i64(i64 %217, i64 %217, i64 11)
  %219 = mul i64 %218, -7046029288634856825
  br label %407

220:                                              ; preds = %3
  %221 = load i64, ptr %1, align 1
  %222 = mul i64 %221, -4417276706812531889
  %223 = tail call i64 @llvm.fshl.i64(i64 %222, i64 %222, i64 31)
  %224 = mul i64 %223, -7046029288634856825
  %225 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %226 = xor i64 %224, %0
  %227 = tail call i64 @llvm.fshl.i64(i64 %226, i64 %226, i64 27)
  %228 = mul i64 %227, -7046029288634856825
  %229 = add i64 %228, -8796714831421723037
  br label %230

230:                                              ; preds = %3, %220
  %231 = phi ptr [ %225, %220 ], [ %1, %3 ]
  %232 = phi i64 [ %229, %220 ], [ %0, %3 ]
  %233 = load i64, ptr %231, align 1
  %234 = mul i64 %233, -4417276706812531889
  %235 = tail call i64 @llvm.fshl.i64(i64 %234, i64 %234, i64 31)
  %236 = mul i64 %235, -7046029288634856825
  %237 = getelementptr inbounds nuw i8, ptr %231, i64 8
  %238 = xor i64 %236, %232
  %239 = tail call i64 @llvm.fshl.i64(i64 %238, i64 %238, i64 27)
  %240 = mul i64 %239, -7046029288634856825
  %241 = add i64 %240, -8796714831421723037
  br label %242

242:                                              ; preds = %3, %230
  %243 = phi ptr [ %237, %230 ], [ %1, %3 ]
  %244 = phi i64 [ %241, %230 ], [ %0, %3 ]
  %245 = load i64, ptr %243, align 1
  %246 = mul i64 %245, -4417276706812531889
  %247 = tail call i64 @llvm.fshl.i64(i64 %246, i64 %246, i64 31)
  %248 = mul i64 %247, -7046029288634856825
  %249 = getelementptr inbounds nuw i8, ptr %243, i64 8
  %250 = xor i64 %248, %244
  %251 = tail call i64 @llvm.fshl.i64(i64 %250, i64 %250, i64 27)
  %252 = mul i64 %251, -7046029288634856825
  %253 = add i64 %252, -8796714831421723037
  br label %254

254:                                              ; preds = %3, %242
  %255 = phi ptr [ %249, %242 ], [ %1, %3 ]
  %256 = phi i64 [ %253, %242 ], [ %0, %3 ]
  %257 = load i32, ptr %255, align 1
  %258 = zext i32 %257 to i64
  %259 = mul i64 %258, -7046029288634856825
  %260 = xor i64 %259, %256
  %261 = getelementptr inbounds nuw i8, ptr %255, i64 4
  %262 = tail call i64 @llvm.fshl.i64(i64 %260, i64 %260, i64 23)
  %263 = mul i64 %262, -4417276706812531889
  %264 = add i64 %263, 1609587929392839161
  %265 = getelementptr inbounds nuw i8, ptr %255, i64 5
  %266 = load i8, ptr %261, align 1, !tbaa !21
  %267 = zext i8 %266 to i64
  %268 = mul i64 %267, 2870177450012600261
  %269 = xor i64 %264, %268
  %270 = tail call i64 @llvm.fshl.i64(i64 %269, i64 %269, i64 11)
  %271 = mul i64 %270, -7046029288634856825
  %272 = load i8, ptr %265, align 1, !tbaa !21
  %273 = zext i8 %272 to i64
  %274 = mul i64 %273, 2870177450012600261
  %275 = xor i64 %271, %274
  %276 = tail call i64 @llvm.fshl.i64(i64 %275, i64 %275, i64 11)
  %277 = mul i64 %276, -7046029288634856825
  br label %407

278:                                              ; preds = %3
  %279 = load i64, ptr %1, align 1
  %280 = mul i64 %279, -4417276706812531889
  %281 = tail call i64 @llvm.fshl.i64(i64 %280, i64 %280, i64 31)
  %282 = mul i64 %281, -7046029288634856825
  %283 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %284 = xor i64 %282, %0
  %285 = tail call i64 @llvm.fshl.i64(i64 %284, i64 %284, i64 27)
  %286 = mul i64 %285, -7046029288634856825
  %287 = add i64 %286, -8796714831421723037
  br label %288

288:                                              ; preds = %3, %278
  %289 = phi ptr [ %283, %278 ], [ %1, %3 ]
  %290 = phi i64 [ %287, %278 ], [ %0, %3 ]
  %291 = load i64, ptr %289, align 1
  %292 = mul i64 %291, -4417276706812531889
  %293 = tail call i64 @llvm.fshl.i64(i64 %292, i64 %292, i64 31)
  %294 = mul i64 %293, -7046029288634856825
  %295 = getelementptr inbounds nuw i8, ptr %289, i64 8
  %296 = xor i64 %294, %290
  %297 = tail call i64 @llvm.fshl.i64(i64 %296, i64 %296, i64 27)
  %298 = mul i64 %297, -7046029288634856825
  %299 = add i64 %298, -8796714831421723037
  br label %300

300:                                              ; preds = %3, %288
  %301 = phi ptr [ %295, %288 ], [ %1, %3 ]
  %302 = phi i64 [ %299, %288 ], [ %0, %3 ]
  %303 = load i64, ptr %301, align 1
  %304 = mul i64 %303, -4417276706812531889
  %305 = tail call i64 @llvm.fshl.i64(i64 %304, i64 %304, i64 31)
  %306 = mul i64 %305, -7046029288634856825
  %307 = getelementptr inbounds nuw i8, ptr %301, i64 8
  %308 = xor i64 %306, %302
  %309 = tail call i64 @llvm.fshl.i64(i64 %308, i64 %308, i64 27)
  %310 = mul i64 %309, -7046029288634856825
  %311 = add i64 %310, -8796714831421723037
  %312 = getelementptr inbounds nuw i8, ptr %301, i64 9
  %313 = load i8, ptr %307, align 1, !tbaa !21
  %314 = zext i8 %313 to i64
  %315 = mul i64 %314, 2870177450012600261
  %316 = xor i64 %311, %315
  %317 = tail call i64 @llvm.fshl.i64(i64 %316, i64 %316, i64 11)
  %318 = mul i64 %317, -7046029288634856825
  %319 = getelementptr inbounds nuw i8, ptr %301, i64 10
  %320 = load i8, ptr %312, align 1, !tbaa !21
  %321 = zext i8 %320 to i64
  %322 = mul i64 %321, 2870177450012600261
  %323 = xor i64 %318, %322
  %324 = tail call i64 @llvm.fshl.i64(i64 %323, i64 %323, i64 11)
  %325 = mul i64 %324, -7046029288634856825
  %326 = load i8, ptr %319, align 1, !tbaa !21
  %327 = zext i8 %326 to i64
  %328 = mul i64 %327, 2870177450012600261
  %329 = xor i64 %325, %328
  %330 = tail call i64 @llvm.fshl.i64(i64 %329, i64 %329, i64 11)
  %331 = mul i64 %330, -7046029288634856825
  br label %407

332:                                              ; preds = %3
  %333 = load i64, ptr %1, align 1
  %334 = mul i64 %333, -4417276706812531889
  %335 = tail call i64 @llvm.fshl.i64(i64 %334, i64 %334, i64 31)
  %336 = mul i64 %335, -7046029288634856825
  %337 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %338 = xor i64 %336, %0
  %339 = tail call i64 @llvm.fshl.i64(i64 %338, i64 %338, i64 27)
  %340 = mul i64 %339, -7046029288634856825
  %341 = add i64 %340, -8796714831421723037
  br label %342

342:                                              ; preds = %3, %332
  %343 = phi ptr [ %337, %332 ], [ %1, %3 ]
  %344 = phi i64 [ %341, %332 ], [ %0, %3 ]
  %345 = load i64, ptr %343, align 1
  %346 = mul i64 %345, -4417276706812531889
  %347 = tail call i64 @llvm.fshl.i64(i64 %346, i64 %346, i64 31)
  %348 = mul i64 %347, -7046029288634856825
  %349 = getelementptr inbounds nuw i8, ptr %343, i64 8
  %350 = xor i64 %348, %344
  %351 = tail call i64 @llvm.fshl.i64(i64 %350, i64 %350, i64 27)
  %352 = mul i64 %351, -7046029288634856825
  %353 = add i64 %352, -8796714831421723037
  br label %354

354:                                              ; preds = %3, %342
  %355 = phi ptr [ %349, %342 ], [ %1, %3 ]
  %356 = phi i64 [ %353, %342 ], [ %0, %3 ]
  %357 = load i64, ptr %355, align 1
  %358 = mul i64 %357, -4417276706812531889
  %359 = tail call i64 @llvm.fshl.i64(i64 %358, i64 %358, i64 31)
  %360 = mul i64 %359, -7046029288634856825
  %361 = getelementptr inbounds nuw i8, ptr %355, i64 8
  %362 = xor i64 %360, %356
  %363 = tail call i64 @llvm.fshl.i64(i64 %362, i64 %362, i64 27)
  %364 = mul i64 %363, -7046029288634856825
  %365 = add i64 %364, -8796714831421723037
  br label %366

366:                                              ; preds = %3, %354
  %367 = phi ptr [ %361, %354 ], [ %1, %3 ]
  %368 = phi i64 [ %365, %354 ], [ %0, %3 ]
  %369 = load i32, ptr %367, align 1
  %370 = zext i32 %369 to i64
  %371 = mul i64 %370, -7046029288634856825
  %372 = xor i64 %371, %368
  %373 = getelementptr inbounds nuw i8, ptr %367, i64 4
  %374 = tail call i64 @llvm.fshl.i64(i64 %372, i64 %372, i64 23)
  %375 = mul i64 %374, -4417276706812531889
  %376 = add i64 %375, 1609587929392839161
  br label %377

377:                                              ; preds = %3, %366
  %378 = phi ptr [ %373, %366 ], [ %1, %3 ]
  %379 = phi i64 [ %376, %366 ], [ %0, %3 ]
  %380 = getelementptr inbounds nuw i8, ptr %378, i64 1
  %381 = load i8, ptr %378, align 1, !tbaa !21
  %382 = zext i8 %381 to i64
  %383 = mul i64 %382, 2870177450012600261
  %384 = xor i64 %383, %379
  %385 = tail call i64 @llvm.fshl.i64(i64 %384, i64 %384, i64 11)
  %386 = mul i64 %385, -7046029288634856825
  br label %387

387:                                              ; preds = %3, %377
  %388 = phi ptr [ %380, %377 ], [ %1, %3 ]
  %389 = phi i64 [ %386, %377 ], [ %0, %3 ]
  %390 = getelementptr inbounds nuw i8, ptr %388, i64 1
  %391 = load i8, ptr %388, align 1, !tbaa !21
  %392 = zext i8 %391 to i64
  %393 = mul i64 %392, 2870177450012600261
  %394 = xor i64 %393, %389
  %395 = tail call i64 @llvm.fshl.i64(i64 %394, i64 %394, i64 11)
  %396 = mul i64 %395, -7046029288634856825
  br label %397

397:                                              ; preds = %3, %387
  %398 = phi ptr [ %390, %387 ], [ %1, %3 ]
  %399 = phi i64 [ %396, %387 ], [ %0, %3 ]
  %400 = load i8, ptr %398, align 1, !tbaa !21
  %401 = zext i8 %400 to i64
  %402 = mul i64 %401, 2870177450012600261
  %403 = xor i64 %402, %399
  %404 = tail call i64 @llvm.fshl.i64(i64 %403, i64 %403, i64 11)
  %405 = mul i64 %404, -7046029288634856825
  br label %407

406:                                              ; preds = %3
  unreachable

407:                                              ; preds = %397, %3, %300, %254, %195, %156, %104, %72, %27
  %408 = phi i64 [ %331, %300 ], [ %277, %254 ], [ %219, %195 ], [ %172, %156 ], [ %121, %104 ], [ %81, %72 ], [ %37, %27 ], [ %405, %397 ], [ %0, %3 ]
  %409 = lshr i64 %408, 33
  %410 = xor i64 %409, %408
  %411 = mul i64 %410, -4417276706812531889
  %412 = lshr i64 %411, 29
  %413 = xor i64 %412, %411
  %414 = mul i64 %413, 1609587929392839161
  %415 = lshr i64 %414, 32
  %416 = xor i64 %415, %414
  ret i64 %416
}

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define void @XXH64_canonicalFromHash(ptr noundef %0, i64 noundef %1) local_unnamed_addr #4 {
  %3 = tail call noundef i64 @llvm.bswap.i64(i64 %1)
  store i64 %3, ptr %0, align 1
  ret void
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(argmem: read) uwtable(sync)
define noundef i64 @XXH64_hashFromCanonical(ptr noundef readonly captures(none) %0) local_unnamed_addr #8 {
  %2 = load i64, ptr %0, align 1
  %3 = tail call noundef i64 @llvm.bswap.i64(i64 %2)
  ret i64 %3
}

; Function Attrs: nofree norecurse nosync nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync)
define i64 @XXH3_64bits(ptr noundef readonly captures(none) %0, i64 noundef %1) local_unnamed_addr #10 {
  %3 = icmp ult i64 %1, 17
  br i1 %3, label %4, label %77

4:                                                ; preds = %2
  %5 = icmp samesign ugt i64 %1, 8
  br i1 %5, label %6, label %27

6:                                                ; preds = %4
  %7 = load i64, ptr %0, align 1
  %8 = xor i64 %7, -4734510112055689544
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %10 = getelementptr inbounds i8, ptr %9, i64 -8
  %11 = load i64, ptr %10, align 1
  %12 = xor i64 %11, 2066345149520216444
  %13 = zext i64 %8 to i128
  %14 = zext i64 %12 to i128
  %15 = mul nuw i128 %14, %13
  %16 = lshr i128 %15, 64
  %17 = xor i128 %16, %15
  %18 = trunc i128 %17 to i64
  %19 = add i64 %8, %1
  %20 = add i64 %19, %12
  %21 = add i64 %20, %18
  %22 = lshr i64 %21, 37
  %23 = xor i64 %22, %21
  %24 = mul i64 %23, 1609587929392839161
  %25 = lshr i64 %24, 32
  %26 = xor i64 %25, %24
  br label %211

27:                                               ; preds = %4
  %28 = icmp samesign ugt i64 %1, 3
  br i1 %28, label %29, label %51

29:                                               ; preds = %27
  %30 = load i32, ptr %0, align 1
  %31 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %32 = getelementptr inbounds i8, ptr %31, i64 -4
  %33 = load i32, ptr %32, align 1
  %34 = zext i32 %30 to i64
  %35 = zext i32 %33 to i64
  %36 = shl nuw i64 %35, 32
  %37 = or disjoint i64 %36, %34
  %38 = xor i64 %37, -4734510112055689544
  %39 = lshr i64 %38, 51
  %40 = xor i64 %39, %38
  %41 = mul i64 %40, 2654435761
  %42 = add i64 %41, %1
  %43 = lshr i64 %42, 47
  %44 = xor i64 %43, %42
  %45 = mul i64 %44, -4417276706812531889
  %46 = lshr i64 %45, 37
  %47 = xor i64 %46, %45
  %48 = mul i64 %47, 1609587929392839161
  %49 = lshr i64 %48, 32
  %50 = xor i64 %49, %48
  br label %211

51:                                               ; preds = %27
  %52 = icmp eq i64 %1, 0
  br i1 %52, label %211, label %53

53:                                               ; preds = %51
  %54 = load i8, ptr %0, align 1, !tbaa !21
  %55 = lshr i64 %1, 1
  %56 = getelementptr inbounds nuw i8, ptr %0, i64 %55
  %57 = load i8, ptr %56, align 1, !tbaa !21
  %58 = getelementptr i8, ptr %0, i64 %1
  %59 = getelementptr i8, ptr %58, i64 -1
  %60 = load i8, ptr %59, align 1, !tbaa !21
  %61 = zext i8 %54 to i64
  %62 = zext i8 %57 to i64
  %63 = shl nuw nsw i64 %62, 8
  %64 = or disjoint i64 %63, %61
  %65 = zext i8 %60 to i64
  %66 = shl nuw nsw i64 %65, 16
  %67 = or disjoint i64 %64, %66
  %68 = shl nuw nsw i64 %1, 24
  %69 = or disjoint i64 %67, %68
  %70 = xor i64 %69, 963444408
  %71 = mul i64 %70, -7046029288634856825
  %72 = lshr i64 %71, 37
  %73 = xor i64 %72, %71
  %74 = mul i64 %73, 1609587929392839161
  %75 = lshr i64 %74, 32
  %76 = xor i64 %75, %74
  br label %211

77:                                               ; preds = %2
  %78 = icmp ult i64 %1, 129
  br i1 %78, label %79, label %205

79:                                               ; preds = %77
  %80 = mul i64 %1, -7046029288634856825
  %81 = icmp samesign ugt i64 %1, 32
  br i1 %81, label %82, label %172

82:                                               ; preds = %79
  %83 = icmp samesign ugt i64 %1, 64
  br i1 %83, label %84, label %143

84:                                               ; preds = %82
  %85 = icmp samesign ugt i64 %1, 96
  br i1 %85, label %86, label %114

86:                                               ; preds = %84
  %87 = getelementptr inbounds nuw i8, ptr %0, i64 48
  %88 = load i64, ptr %87, align 1, !noalias !33
  %89 = getelementptr inbounds nuw i8, ptr %0, i64 56
  %90 = load i64, ptr %89, align 1, !noalias !33
  %91 = xor i64 %88, 4554437623014685352
  %92 = xor i64 %90, 2111919702937427193
  %93 = zext i64 %91 to i128
  %94 = zext i64 %92 to i128
  %95 = mul nuw i128 %94, %93
  %96 = lshr i128 %95, 64
  %97 = xor i128 %96, %95
  %98 = trunc i128 %97 to i64
  %99 = add i64 %80, %98
  %100 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %101 = getelementptr inbounds i8, ptr %100, i64 -64
  %102 = load i64, ptr %101, align 1, !noalias !36
  %103 = getelementptr inbounds i8, ptr %100, i64 -56
  %104 = load i64, ptr %103, align 1, !noalias !36
  %105 = xor i64 %102, 3556072174620004746
  %106 = xor i64 %104, 7238261902898274248
  %107 = zext i64 %105 to i128
  %108 = zext i64 %106 to i128
  %109 = mul nuw i128 %108, %107
  %110 = lshr i128 %109, 64
  %111 = xor i128 %110, %109
  %112 = trunc i128 %111 to i64
  %113 = add i64 %99, %112
  br label %114

114:                                              ; preds = %86, %84
  %115 = phi i64 [ %113, %86 ], [ %80, %84 ]
  %116 = getelementptr inbounds nuw i8, ptr %0, i64 32
  %117 = load i64, ptr %116, align 1, !noalias !39
  %118 = getelementptr inbounds nuw i8, ptr %0, i64 40
  %119 = load i64, ptr %118, align 1, !noalias !39
  %120 = xor i64 %117, -3818837453329782724
  %121 = xor i64 %119, -6688317018830679928
  %122 = zext i64 %120 to i128
  %123 = zext i64 %121 to i128
  %124 = mul nuw i128 %123, %122
  %125 = lshr i128 %124, 64
  %126 = xor i128 %125, %124
  %127 = trunc i128 %126 to i64
  %128 = add i64 %115, %127
  %129 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %130 = getelementptr inbounds i8, ptr %129, i64 -48
  %131 = load i64, ptr %130, align 1, !noalias !42
  %132 = getelementptr inbounds i8, ptr %129, i64 -40
  %133 = load i64, ptr %132, align 1, !noalias !42
  %134 = xor i64 %131, 5690594596133299313
  %135 = xor i64 %133, -2833645246901970632
  %136 = zext i64 %134 to i128
  %137 = zext i64 %135 to i128
  %138 = mul nuw i128 %137, %136
  %139 = lshr i128 %138, 64
  %140 = xor i128 %139, %138
  %141 = trunc i128 %140 to i64
  %142 = add i64 %128, %141
  br label %143

143:                                              ; preds = %114, %82
  %144 = phi i64 [ %142, %114 ], [ %80, %82 ]
  %145 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %146 = load i64, ptr %145, align 1, !noalias !45
  %147 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %148 = load i64, ptr %147, align 1, !noalias !45
  %149 = xor i64 %146, 8711581037947681227
  %150 = xor i64 %148, 2410270004345854594
  %151 = zext i64 %149 to i128
  %152 = zext i64 %150 to i128
  %153 = mul nuw i128 %152, %151
  %154 = lshr i128 %153, 64
  %155 = xor i128 %154, %153
  %156 = trunc i128 %155 to i64
  %157 = add i64 %144, %156
  %158 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %159 = getelementptr inbounds i8, ptr %158, i64 -32
  %160 = load i64, ptr %159, align 1, !noalias !48
  %161 = getelementptr inbounds i8, ptr %158, i64 -24
  %162 = load i64, ptr %161, align 1, !noalias !48
  %163 = xor i64 %160, -8204357891075471176
  %164 = xor i64 %162, 5487137525590930912
  %165 = zext i64 %163 to i128
  %166 = zext i64 %164 to i128
  %167 = mul nuw i128 %166, %165
  %168 = lshr i128 %167, 64
  %169 = xor i128 %168, %167
  %170 = trunc i128 %169 to i64
  %171 = add i64 %157, %170
  br label %172

172:                                              ; preds = %79, %143
  %173 = phi i64 [ %171, %143 ], [ %80, %79 ]
  %174 = load i64, ptr %0, align 1, !noalias !51
  %175 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %176 = load i64, ptr %175, align 1, !noalias !51
  %177 = xor i64 %174, -4734510112055689544
  %178 = xor i64 %176, 2066345149520216444
  %179 = zext i64 %177 to i128
  %180 = zext i64 %178 to i128
  %181 = mul nuw i128 %180, %179
  %182 = lshr i128 %181, 64
  %183 = xor i128 %182, %181
  %184 = trunc i128 %183 to i64
  %185 = add i64 %173, %184
  %186 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %187 = getelementptr inbounds i8, ptr %186, i64 -16
  %188 = load i64, ptr %187, align 1, !noalias !54
  %189 = getelementptr inbounds i8, ptr %186, i64 -8
  %190 = load i64, ptr %189, align 1, !noalias !54
  %191 = xor i64 %188, -2623469361688619810
  %192 = xor i64 %190, 2262974939099578482
  %193 = zext i64 %191 to i128
  %194 = zext i64 %192 to i128
  %195 = mul nuw i128 %194, %193
  %196 = lshr i128 %195, 64
  %197 = xor i128 %196, %195
  %198 = trunc i128 %197 to i64
  %199 = add i64 %185, %198
  %200 = lshr i64 %199, 37
  %201 = xor i64 %200, %199
  %202 = mul i64 %201, 1609587929392839161
  %203 = lshr i64 %202, 32
  %204 = xor i64 %203, %202
  br label %211

205:                                              ; preds = %77
  %206 = icmp ult i64 %1, 241
  br i1 %206, label %207, label %209

207:                                              ; preds = %205
  %208 = tail call fastcc i64 @XXH3_len_129to240_64b(ptr noundef %0, i64 noundef %1, ptr noundef nonnull @kSecret, i64 noundef 0)
  br label %211

209:                                              ; preds = %205
  %210 = tail call fastcc i64 @XXH3_hashLong_64b_defaultSecret(ptr noundef %0, i64 noundef %1)
  br label %211

211:                                              ; preds = %53, %51, %29, %6, %209, %207, %172
  %212 = phi i64 [ %204, %172 ], [ %208, %207 ], [ %210, %209 ], [ %26, %6 ], [ %50, %29 ], [ %76, %53 ], [ 0, %51 ]
  ret i64 %212
}

; Function Attrs: nofree noinline norecurse nosync nounwind ssp memory(argmem: read) uwtable(sync)
define internal fastcc i64 @XXH3_len_129to240_64b(ptr noalias noundef readonly captures(none) %0, i64 noundef range(i64 129, 241) %1, ptr noalias noundef readonly captures(none) %2, i64 noundef %3) unnamed_addr #11 {
  %5 = mul i64 %1, -7046029288634856825
  br label %6

6:                                                ; preds = %4, %6
  %7 = phi i64 [ 0, %4 ], [ %29, %6 ]
  %8 = phi i64 [ %5, %4 ], [ %28, %6 ]
  %9 = shl nuw nsw i64 %7, 4
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 %9
  %11 = getelementptr inbounds nuw i8, ptr %2, i64 %9
  %12 = load i64, ptr %10, align 1, !noalias !57
  %13 = getelementptr inbounds nuw i8, ptr %10, i64 8
  %14 = load i64, ptr %13, align 1, !noalias !57
  %15 = load i64, ptr %11, align 1
  %16 = add i64 %15, %3
  %17 = xor i64 %16, %12
  %18 = getelementptr inbounds nuw i8, ptr %11, i64 8
  %19 = load i64, ptr %18, align 1
  %20 = sub i64 %19, %3
  %21 = xor i64 %20, %14
  %22 = zext i64 %17 to i128
  %23 = zext i64 %21 to i128
  %24 = mul nuw i128 %23, %22
  %25 = lshr i128 %24, 64
  %26 = xor i128 %25, %24
  %27 = trunc i128 %26 to i64
  %28 = add i64 %8, %27
  %29 = add nuw nsw i64 %7, 1
  %30 = icmp eq i64 %29, 8
  br i1 %30, label %31, label %6, !llvm.loop !60

31:                                               ; preds = %6
  %32 = trunc nuw nsw i64 %1 to i32
  %33 = lshr i32 %32, 4
  %34 = lshr i64 %28, 37
  %35 = xor i64 %34, %28
  %36 = mul i64 %35, 1609587929392839161
  %37 = lshr i64 %36, 32
  %38 = xor i64 %37, %36
  %39 = icmp eq i32 %33, 8
  br i1 %39, label %68, label %40

40:                                               ; preds = %31
  %41 = zext nneg i32 %33 to i64
  br label %42

42:                                               ; preds = %40, %42
  %43 = phi i64 [ 8, %40 ], [ %66, %42 ]
  %44 = phi i64 [ %38, %40 ], [ %65, %42 ]
  %45 = shl nsw i64 %43, 4
  %46 = getelementptr inbounds nuw i8, ptr %0, i64 %45
  %47 = getelementptr i8, ptr %2, i64 %45
  %48 = getelementptr i8, ptr %47, i64 -125
  %49 = load i64, ptr %46, align 1, !noalias !61
  %50 = getelementptr inbounds nuw i8, ptr %46, i64 8
  %51 = load i64, ptr %50, align 1, !noalias !61
  %52 = load i64, ptr %48, align 1
  %53 = add i64 %52, %3
  %54 = xor i64 %53, %49
  %55 = getelementptr i8, ptr %47, i64 -117
  %56 = load i64, ptr %55, align 1
  %57 = sub i64 %56, %3
  %58 = xor i64 %57, %51
  %59 = zext i64 %54 to i128
  %60 = zext i64 %58 to i128
  %61 = mul nuw i128 %60, %59
  %62 = lshr i128 %61, 64
  %63 = xor i128 %62, %61
  %64 = trunc i128 %63 to i64
  %65 = add i64 %44, %64
  %66 = add nuw nsw i64 %43, 1
  %67 = icmp eq i64 %66, %41
  br i1 %67, label %68, label %42, !llvm.loop !64

68:                                               ; preds = %42, %31
  %69 = phi i64 [ %38, %31 ], [ %65, %42 ]
  %70 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %71 = getelementptr inbounds i8, ptr %70, i64 -16
  %72 = getelementptr inbounds nuw i8, ptr %2, i64 119
  %73 = load i64, ptr %71, align 1, !noalias !65
  %74 = getelementptr inbounds i8, ptr %70, i64 -8
  %75 = load i64, ptr %74, align 1, !noalias !65
  %76 = load i64, ptr %72, align 1
  %77 = add i64 %76, %3
  %78 = xor i64 %77, %73
  %79 = getelementptr inbounds nuw i8, ptr %2, i64 127
  %80 = load i64, ptr %79, align 1
  %81 = sub i64 %80, %3
  %82 = xor i64 %81, %75
  %83 = zext i64 %78 to i128
  %84 = zext i64 %82 to i128
  %85 = mul nuw i128 %84, %83
  %86 = lshr i128 %85, 64
  %87 = xor i128 %86, %85
  %88 = trunc i128 %87 to i64
  %89 = add i64 %69, %88
  %90 = lshr i64 %89, 37
  %91 = xor i64 %90, %89
  %92 = mul i64 %91, 1609587929392839161
  %93 = lshr i64 %92, 32
  %94 = xor i64 %93, %92
  ret i64 %94
}

; Function Attrs: nofree noinline norecurse nosync nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync)
define internal fastcc i64 @XXH3_hashLong_64b_defaultSecret(ptr noalias noundef readonly captures(none) %0, i64 noundef range(i64 241, 0) %1) unnamed_addr #12 {
  %3 = alloca [8 x i64], align 16
  call void @llvm.lifetime.start.p0(i64 64, ptr nonnull %3) #24, !noalias !68
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(64) %3, ptr noundef nonnull align 16 dereferenceable(64) @__const.XXH3_hashLong_128b_internal.acc, i64 64, i1 false), !noalias !68
  %4 = lshr i64 %1, 10
  %5 = icmp ult i64 %1, 1024
  br i1 %5, label %62, label %6

6:                                                ; preds = %2, %59
  %7 = phi i64 [ %60, %59 ], [ 0, %2 ]
  %8 = shl i64 %7, 10
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 %8
  br label %10

10:                                               ; preds = %6, %36
  %11 = phi i64 [ 0, %6 ], [ %37, %36 ]
  %12 = shl nuw nsw i64 %11, 6
  %13 = getelementptr inbounds nuw i8, ptr %9, i64 %12
  %14 = shl nuw nsw i64 %11, 3
  %15 = getelementptr inbounds nuw i8, ptr @kSecret, i64 %14
  tail call void @llvm.experimental.noalias.scope.decl(metadata !72)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !75)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !77)
  br label %16

16:                                               ; preds = %10, %16
  %17 = phi i64 [ 0, %10 ], [ %34, %16 ]
  %18 = shl nuw nsw i64 %17, 2
  %19 = getelementptr inbounds nuw i32, ptr %13, i64 %18
  %20 = load <4 x i32>, ptr %19, align 4, !alias.scope !75, !noalias !79
  %21 = getelementptr inbounds nuw i32, ptr %15, i64 %18
  %22 = load <4 x i32>, ptr %21, align 8, !alias.scope !77, !noalias !80
  %23 = xor <4 x i32> %22, %20
  %24 = bitcast <4 x i32> %23 to <2 x i64>
  %25 = trunc <2 x i64> %24 to <2 x i32>
  %26 = lshr <2 x i64> %24, splat (i64 32)
  %27 = trunc nuw <2 x i64> %26 to <2 x i32>
  %28 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %17
  %29 = load <2 x i64>, ptr %28, align 16, !tbaa !21, !alias.scope !72, !noalias !81
  %30 = bitcast <4 x i32> %20 to <2 x i64>
  %31 = add <2 x i64> %29, %30
  %32 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %25, <2 x i32> %27)
  %33 = add <2 x i64> %31, %32
  store <2 x i64> %33, ptr %28, align 16, !tbaa !21, !alias.scope !72, !noalias !81
  %34 = add nuw nsw i64 %17, 1
  %35 = icmp eq i64 %34, 4
  br i1 %35, label %36, label %16, !llvm.loop !82

36:                                               ; preds = %16
  %37 = add nuw nsw i64 %11, 1
  %38 = icmp eq i64 %37, 16
  br i1 %38, label %39, label %10, !llvm.loop !83

39:                                               ; preds = %36
  tail call void @llvm.experimental.noalias.scope.decl(metadata !84)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !87)
  br label %40

40:                                               ; preds = %39, %40
  %41 = phi i64 [ 0, %39 ], [ %57, %40 ]
  %42 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %41
  %43 = load <2 x i64>, ptr %42, align 16, !tbaa !21, !alias.scope !84, !noalias !87
  %44 = lshr <2 x i64> %43, splat (i64 47)
  %45 = xor <2 x i64> %44, %43
  %46 = shl nuw nsw i64 %41, 4
  %47 = getelementptr inbounds nuw i8, ptr getelementptr inbounds nuw (i8, ptr @kSecret, i64 128), i64 %46
  %48 = load <4 x i32>, ptr %47, align 16, !alias.scope !87, !noalias !84
  %49 = bitcast <2 x i64> %45 to <4 x i32>
  %50 = xor <4 x i32> %48, %49
  %51 = shufflevector <4 x i32> %50, <4 x i32> poison, <2 x i32> <i32 0, i32 2>
  %52 = shufflevector <4 x i32> %50, <4 x i32> poison, <2 x i32> <i32 1, i32 3>
  %53 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %52, <2 x i32> splat (i32 -1640531535))
  %54 = shl <2 x i64> %53, splat (i64 32)
  %55 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %51, <2 x i32> splat (i32 -1640531535))
  %56 = add <2 x i64> %54, %55
  store <2 x i64> %56, ptr %42, align 16, !tbaa !21, !alias.scope !84, !noalias !87
  %57 = add nuw nsw i64 %41, 1
  %58 = icmp eq i64 %57, 4
  br i1 %58, label %59, label %40, !llvm.loop !89

59:                                               ; preds = %40
  %60 = add nuw nsw i64 %7, 1
  %61 = icmp eq i64 %60, %4
  br i1 %61, label %62, label %6, !llvm.loop !90

62:                                               ; preds = %59, %2
  %63 = and i64 %1, -1024
  %64 = lshr i64 %1, 6
  %65 = and i64 %64, 15
  %66 = getelementptr inbounds nuw i8, ptr %0, i64 %63
  %67 = icmp eq i64 %65, 0
  br i1 %67, label %97, label %68

68:                                               ; preds = %62, %94
  %69 = phi i64 [ %95, %94 ], [ 0, %62 ]
  %70 = shl i64 %69, 6
  %71 = getelementptr inbounds nuw i8, ptr %66, i64 %70
  %72 = shl i64 %69, 3
  %73 = getelementptr inbounds nuw i8, ptr @kSecret, i64 %72
  tail call void @llvm.experimental.noalias.scope.decl(metadata !91)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !94)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !96)
  br label %74

74:                                               ; preds = %68, %74
  %75 = phi i64 [ 0, %68 ], [ %92, %74 ]
  %76 = shl nuw nsw i64 %75, 2
  %77 = getelementptr inbounds nuw i32, ptr %71, i64 %76
  %78 = load <4 x i32>, ptr %77, align 4, !alias.scope !94, !noalias !98
  %79 = getelementptr inbounds nuw i32, ptr %73, i64 %76
  %80 = load <4 x i32>, ptr %79, align 8, !alias.scope !96, !noalias !99
  %81 = xor <4 x i32> %80, %78
  %82 = bitcast <4 x i32> %81 to <2 x i64>
  %83 = trunc <2 x i64> %82 to <2 x i32>
  %84 = lshr <2 x i64> %82, splat (i64 32)
  %85 = trunc nuw <2 x i64> %84 to <2 x i32>
  %86 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %75
  %87 = load <2 x i64>, ptr %86, align 16, !tbaa !21, !alias.scope !91, !noalias !100
  %88 = bitcast <4 x i32> %78 to <2 x i64>
  %89 = add <2 x i64> %87, %88
  %90 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %83, <2 x i32> %85)
  %91 = add <2 x i64> %89, %90
  store <2 x i64> %91, ptr %86, align 16, !tbaa !21, !alias.scope !91, !noalias !100
  %92 = add nuw nsw i64 %75, 1
  %93 = icmp eq i64 %92, 4
  br i1 %93, label %94, label %74, !llvm.loop !82

94:                                               ; preds = %74
  %95 = add nuw nsw i64 %69, 1
  %96 = icmp eq i64 %95, %65
  br i1 %96, label %97, label %68, !llvm.loop !83

97:                                               ; preds = %94, %62
  %98 = and i64 %1, 63
  %99 = icmp eq i64 %98, 0
  br i1 %99, label %123, label %100

100:                                              ; preds = %97
  %101 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %102 = getelementptr inbounds i8, ptr %101, i64 -64
  tail call void @llvm.experimental.noalias.scope.decl(metadata !101)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !104)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !106)
  br label %103

103:                                              ; preds = %100, %103
  %104 = phi i64 [ 0, %100 ], [ %121, %103 ]
  %105 = shl nuw nsw i64 %104, 2
  %106 = getelementptr inbounds nuw i32, ptr %102, i64 %105
  %107 = load <4 x i32>, ptr %106, align 4, !alias.scope !104, !noalias !108
  %108 = getelementptr inbounds nuw i32, ptr getelementptr inbounds nuw (i8, ptr @kSecret, i64 121), i64 %105
  %109 = load <4 x i32>, ptr %108, align 4, !alias.scope !106, !noalias !109
  %110 = xor <4 x i32> %109, %107
  %111 = bitcast <4 x i32> %110 to <2 x i64>
  %112 = trunc <2 x i64> %111 to <2 x i32>
  %113 = lshr <2 x i64> %111, splat (i64 32)
  %114 = trunc nuw <2 x i64> %113 to <2 x i32>
  %115 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %104
  %116 = load <2 x i64>, ptr %115, align 16, !tbaa !21, !alias.scope !101, !noalias !110
  %117 = bitcast <4 x i32> %107 to <2 x i64>
  %118 = add <2 x i64> %116, %117
  %119 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %112, <2 x i32> %114)
  %120 = add <2 x i64> %118, %119
  store <2 x i64> %120, ptr %115, align 16, !tbaa !21, !alias.scope !101, !noalias !110
  %121 = add nuw nsw i64 %104, 1
  %122 = icmp eq i64 %121, 4
  br i1 %122, label %123, label %103, !llvm.loop !82

123:                                              ; preds = %103, %97
  %124 = mul i64 %1, -7046029288634856825
  %125 = load i64, ptr %3, align 16, !tbaa !22, !alias.scope !111, !noalias !116
  %126 = xor i64 %125, 7914194659941938988
  %127 = getelementptr inbounds nuw i8, ptr %3, i64 8
  %128 = load i64, ptr %127, align 8, !tbaa !22, !alias.scope !111, !noalias !116
  %129 = xor i64 %128, -6611157965513653271
  %130 = zext i64 %126 to i128
  %131 = zext i64 %129 to i128
  %132 = mul nuw i128 %131, %130
  %133 = lshr i128 %132, 64
  %134 = xor i128 %133, %132
  %135 = trunc i128 %134 to i64
  %136 = add i64 %124, %135
  %137 = getelementptr inbounds nuw i8, ptr %3, i64 16
  %138 = load i64, ptr %137, align 16, !tbaa !22, !alias.scope !119, !noalias !122
  %139 = xor i64 %138, -1839215637059881052
  %140 = getelementptr inbounds nuw i8, ptr %3, i64 24
  %141 = load i64, ptr %140, align 8, !tbaa !22, !alias.scope !119, !noalias !122
  %142 = xor i64 %141, -3433288310154277810
  %143 = zext i64 %139 to i128
  %144 = zext i64 %142 to i128
  %145 = mul nuw i128 %144, %143
  %146 = lshr i128 %145, 64
  %147 = xor i128 %146, %145
  %148 = trunc i128 %147 to i64
  %149 = add i64 %136, %148
  %150 = getelementptr inbounds nuw i8, ptr %3, i64 32
  %151 = load i64, ptr %150, align 16, !tbaa !22, !alias.scope !124, !noalias !127
  %152 = xor i64 %151, 5046485836271438973
  %153 = getelementptr inbounds nuw i8, ptr %3, i64 40
  %154 = load i64, ptr %153, align 8, !tbaa !22, !alias.scope !124, !noalias !127
  %155 = xor i64 %154, -8055285457383852172
  %156 = zext i64 %152 to i128
  %157 = zext i64 %155 to i128
  %158 = mul nuw i128 %157, %156
  %159 = lshr i128 %158, 64
  %160 = xor i128 %159, %158
  %161 = trunc i128 %160 to i64
  %162 = add i64 %149, %161
  %163 = getelementptr inbounds nuw i8, ptr %3, i64 48
  %164 = load i64, ptr %163, align 16, !tbaa !22, !alias.scope !129, !noalias !132
  %165 = xor i64 %164, 5920048007935066598
  %166 = getelementptr inbounds nuw i8, ptr %3, i64 56
  %167 = load i64, ptr %166, align 8, !tbaa !22, !alias.scope !129, !noalias !132
  %168 = xor i64 %167, 7336514198459093435
  %169 = zext i64 %165 to i128
  %170 = zext i64 %168 to i128
  %171 = mul nuw i128 %170, %169
  %172 = lshr i128 %171, 64
  %173 = xor i128 %172, %171
  %174 = trunc i128 %173 to i64
  %175 = add i64 %162, %174
  %176 = lshr i64 %175, 37
  %177 = xor i64 %176, %175
  %178 = mul i64 %177, 1609587929392839161
  %179 = lshr i64 %178, 32
  %180 = xor i64 %179, %178
  call void @llvm.lifetime.end.p0(i64 64, ptr nonnull %3) #24, !noalias !68
  ret i64 %180
}

; Function Attrs: nofree norecurse nosync nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync)
define i64 @XXH3_64bits_withSecret(ptr noundef readonly captures(none) %0, i64 noundef %1, ptr noundef readonly captures(none) %2, i64 noundef %3) local_unnamed_addr #10 {
  %5 = icmp ult i64 %1, 17
  br i1 %5, label %6, label %85

6:                                                ; preds = %4
  %7 = icmp samesign ugt i64 %1, 8
  br i1 %7, label %8, label %32

8:                                                ; preds = %6
  %9 = load i64, ptr %0, align 1
  %10 = load i64, ptr %2, align 1
  %11 = xor i64 %10, %9
  %12 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %13 = getelementptr inbounds i8, ptr %12, i64 -8
  %14 = load i64, ptr %13, align 1
  %15 = getelementptr inbounds nuw i8, ptr %2, i64 8
  %16 = load i64, ptr %15, align 1
  %17 = xor i64 %16, %14
  %18 = zext i64 %11 to i128
  %19 = zext i64 %17 to i128
  %20 = mul nuw i128 %19, %18
  %21 = lshr i128 %20, 64
  %22 = xor i128 %21, %20
  %23 = trunc i128 %22 to i64
  %24 = add i64 %11, %1
  %25 = add i64 %24, %17
  %26 = add i64 %25, %23
  %27 = lshr i64 %26, 37
  %28 = xor i64 %27, %26
  %29 = mul i64 %28, 1609587929392839161
  %30 = lshr i64 %29, 32
  %31 = xor i64 %30, %29
  br label %250

32:                                               ; preds = %6
  %33 = icmp samesign ugt i64 %1, 3
  br i1 %33, label %34, label %57

34:                                               ; preds = %32
  %35 = load i32, ptr %0, align 1
  %36 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %37 = getelementptr inbounds i8, ptr %36, i64 -4
  %38 = load i32, ptr %37, align 1
  %39 = zext i32 %35 to i64
  %40 = zext i32 %38 to i64
  %41 = shl nuw i64 %40, 32
  %42 = or disjoint i64 %41, %39
  %43 = load i64, ptr %2, align 1
  %44 = xor i64 %42, %43
  %45 = lshr i64 %44, 51
  %46 = xor i64 %45, %44
  %47 = mul i64 %46, 2654435761
  %48 = add i64 %47, %1
  %49 = lshr i64 %48, 47
  %50 = xor i64 %49, %48
  %51 = mul i64 %50, -4417276706812531889
  %52 = lshr i64 %51, 37
  %53 = xor i64 %52, %51
  %54 = mul i64 %53, 1609587929392839161
  %55 = lshr i64 %54, 32
  %56 = xor i64 %55, %54
  br label %250

57:                                               ; preds = %32
  %58 = icmp eq i64 %1, 0
  br i1 %58, label %250, label %59

59:                                               ; preds = %57
  %60 = load i8, ptr %0, align 1, !tbaa !21
  %61 = lshr i64 %1, 1
  %62 = getelementptr inbounds nuw i8, ptr %0, i64 %61
  %63 = load i8, ptr %62, align 1, !tbaa !21
  %64 = getelementptr i8, ptr %0, i64 %1
  %65 = getelementptr i8, ptr %64, i64 -1
  %66 = load i8, ptr %65, align 1, !tbaa !21
  %67 = zext i8 %60 to i64
  %68 = zext i8 %63 to i64
  %69 = shl nuw nsw i64 %68, 8
  %70 = or disjoint i64 %69, %67
  %71 = zext i8 %66 to i64
  %72 = shl nuw nsw i64 %71, 16
  %73 = or disjoint i64 %70, %72
  %74 = shl nuw nsw i64 %1, 24
  %75 = or disjoint i64 %73, %74
  %76 = load i32, ptr %2, align 1
  %77 = zext i32 %76 to i64
  %78 = xor i64 %75, %77
  %79 = mul i64 %78, -7046029288634856825
  %80 = lshr i64 %79, 37
  %81 = xor i64 %80, %79
  %82 = mul i64 %81, 1609587929392839161
  %83 = lshr i64 %82, 32
  %84 = xor i64 %83, %82
  br label %250

85:                                               ; preds = %4
  %86 = icmp ult i64 %1, 129
  br i1 %86, label %87, label %244

87:                                               ; preds = %85
  %88 = mul i64 %1, -7046029288634856825
  %89 = icmp samesign ugt i64 %1, 32
  br i1 %89, label %90, label %204

90:                                               ; preds = %87
  %91 = icmp samesign ugt i64 %1, 64
  br i1 %91, label %92, label %167

92:                                               ; preds = %90
  %93 = icmp samesign ugt i64 %1, 96
  br i1 %93, label %94, label %130

94:                                               ; preds = %92
  %95 = getelementptr inbounds nuw i8, ptr %0, i64 48
  %96 = getelementptr inbounds nuw i8, ptr %2, i64 96
  %97 = load i64, ptr %95, align 1, !noalias !134
  %98 = getelementptr inbounds nuw i8, ptr %0, i64 56
  %99 = load i64, ptr %98, align 1, !noalias !134
  %100 = load i64, ptr %96, align 1
  %101 = xor i64 %100, %97
  %102 = getelementptr inbounds nuw i8, ptr %2, i64 104
  %103 = load i64, ptr %102, align 1
  %104 = xor i64 %103, %99
  %105 = zext i64 %101 to i128
  %106 = zext i64 %104 to i128
  %107 = mul nuw i128 %106, %105
  %108 = lshr i128 %107, 64
  %109 = xor i128 %108, %107
  %110 = trunc i128 %109 to i64
  %111 = add i64 %88, %110
  %112 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %113 = getelementptr inbounds i8, ptr %112, i64 -64
  %114 = getelementptr inbounds nuw i8, ptr %2, i64 112
  %115 = load i64, ptr %113, align 1, !noalias !137
  %116 = getelementptr inbounds i8, ptr %112, i64 -56
  %117 = load i64, ptr %116, align 1, !noalias !137
  %118 = load i64, ptr %114, align 1
  %119 = xor i64 %118, %115
  %120 = getelementptr inbounds nuw i8, ptr %2, i64 120
  %121 = load i64, ptr %120, align 1
  %122 = xor i64 %121, %117
  %123 = zext i64 %119 to i128
  %124 = zext i64 %122 to i128
  %125 = mul nuw i128 %124, %123
  %126 = lshr i128 %125, 64
  %127 = xor i128 %126, %125
  %128 = trunc i128 %127 to i64
  %129 = add i64 %111, %128
  br label %130

130:                                              ; preds = %94, %92
  %131 = phi i64 [ %129, %94 ], [ %88, %92 ]
  %132 = getelementptr inbounds nuw i8, ptr %0, i64 32
  %133 = getelementptr inbounds nuw i8, ptr %2, i64 64
  %134 = load i64, ptr %132, align 1, !noalias !140
  %135 = getelementptr inbounds nuw i8, ptr %0, i64 40
  %136 = load i64, ptr %135, align 1, !noalias !140
  %137 = load i64, ptr %133, align 1
  %138 = xor i64 %137, %134
  %139 = getelementptr inbounds nuw i8, ptr %2, i64 72
  %140 = load i64, ptr %139, align 1
  %141 = xor i64 %140, %136
  %142 = zext i64 %138 to i128
  %143 = zext i64 %141 to i128
  %144 = mul nuw i128 %143, %142
  %145 = lshr i128 %144, 64
  %146 = xor i128 %145, %144
  %147 = trunc i128 %146 to i64
  %148 = add i64 %131, %147
  %149 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %150 = getelementptr inbounds i8, ptr %149, i64 -48
  %151 = getelementptr inbounds nuw i8, ptr %2, i64 80
  %152 = load i64, ptr %150, align 1, !noalias !143
  %153 = getelementptr inbounds i8, ptr %149, i64 -40
  %154 = load i64, ptr %153, align 1, !noalias !143
  %155 = load i64, ptr %151, align 1
  %156 = xor i64 %155, %152
  %157 = getelementptr inbounds nuw i8, ptr %2, i64 88
  %158 = load i64, ptr %157, align 1
  %159 = xor i64 %158, %154
  %160 = zext i64 %156 to i128
  %161 = zext i64 %159 to i128
  %162 = mul nuw i128 %161, %160
  %163 = lshr i128 %162, 64
  %164 = xor i128 %163, %162
  %165 = trunc i128 %164 to i64
  %166 = add i64 %148, %165
  br label %167

167:                                              ; preds = %130, %90
  %168 = phi i64 [ %166, %130 ], [ %88, %90 ]
  %169 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %170 = getelementptr inbounds nuw i8, ptr %2, i64 32
  %171 = load i64, ptr %169, align 1, !noalias !146
  %172 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %173 = load i64, ptr %172, align 1, !noalias !146
  %174 = load i64, ptr %170, align 1
  %175 = xor i64 %174, %171
  %176 = getelementptr inbounds nuw i8, ptr %2, i64 40
  %177 = load i64, ptr %176, align 1
  %178 = xor i64 %177, %173
  %179 = zext i64 %175 to i128
  %180 = zext i64 %178 to i128
  %181 = mul nuw i128 %180, %179
  %182 = lshr i128 %181, 64
  %183 = xor i128 %182, %181
  %184 = trunc i128 %183 to i64
  %185 = add i64 %168, %184
  %186 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %187 = getelementptr inbounds i8, ptr %186, i64 -32
  %188 = getelementptr inbounds nuw i8, ptr %2, i64 48
  %189 = load i64, ptr %187, align 1, !noalias !149
  %190 = getelementptr inbounds i8, ptr %186, i64 -24
  %191 = load i64, ptr %190, align 1, !noalias !149
  %192 = load i64, ptr %188, align 1
  %193 = xor i64 %192, %189
  %194 = getelementptr inbounds nuw i8, ptr %2, i64 56
  %195 = load i64, ptr %194, align 1
  %196 = xor i64 %195, %191
  %197 = zext i64 %193 to i128
  %198 = zext i64 %196 to i128
  %199 = mul nuw i128 %198, %197
  %200 = lshr i128 %199, 64
  %201 = xor i128 %200, %199
  %202 = trunc i128 %201 to i64
  %203 = add i64 %185, %202
  br label %204

204:                                              ; preds = %87, %167
  %205 = phi i64 [ %203, %167 ], [ %88, %87 ]
  %206 = load i64, ptr %0, align 1, !noalias !152
  %207 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %208 = load i64, ptr %207, align 1, !noalias !152
  %209 = load i64, ptr %2, align 1
  %210 = xor i64 %209, %206
  %211 = getelementptr inbounds nuw i8, ptr %2, i64 8
  %212 = load i64, ptr %211, align 1
  %213 = xor i64 %212, %208
  %214 = zext i64 %210 to i128
  %215 = zext i64 %213 to i128
  %216 = mul nuw i128 %215, %214
  %217 = lshr i128 %216, 64
  %218 = xor i128 %217, %216
  %219 = trunc i128 %218 to i64
  %220 = add i64 %205, %219
  %221 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %222 = getelementptr inbounds i8, ptr %221, i64 -16
  %223 = getelementptr inbounds nuw i8, ptr %2, i64 16
  %224 = load i64, ptr %222, align 1, !noalias !155
  %225 = getelementptr inbounds i8, ptr %221, i64 -8
  %226 = load i64, ptr %225, align 1, !noalias !155
  %227 = load i64, ptr %223, align 1
  %228 = xor i64 %227, %224
  %229 = getelementptr inbounds nuw i8, ptr %2, i64 24
  %230 = load i64, ptr %229, align 1
  %231 = xor i64 %230, %226
  %232 = zext i64 %228 to i128
  %233 = zext i64 %231 to i128
  %234 = mul nuw i128 %233, %232
  %235 = lshr i128 %234, 64
  %236 = xor i128 %235, %234
  %237 = trunc i128 %236 to i64
  %238 = add i64 %220, %237
  %239 = lshr i64 %238, 37
  %240 = xor i64 %239, %238
  %241 = mul i64 %240, 1609587929392839161
  %242 = lshr i64 %241, 32
  %243 = xor i64 %242, %241
  br label %250

244:                                              ; preds = %85
  %245 = icmp ult i64 %1, 241
  br i1 %245, label %246, label %248

246:                                              ; preds = %244
  %247 = tail call fastcc i64 @XXH3_len_129to240_64b(ptr noundef %0, i64 noundef %1, ptr noundef %2, i64 noundef 0)
  br label %250

248:                                              ; preds = %244
  %249 = tail call fastcc i64 @XXH3_hashLong_64b_withSecret(ptr noundef %0, i64 noundef %1, ptr noundef %2, i64 noundef %3)
  br label %250

250:                                              ; preds = %59, %57, %34, %8, %248, %246, %204
  %251 = phi i64 [ %243, %204 ], [ %247, %246 ], [ %249, %248 ], [ %31, %8 ], [ %56, %34 ], [ %84, %59 ], [ 0, %57 ]
  ret i64 %251
}

; Function Attrs: nofree noinline norecurse nosync nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync)
define internal fastcc i64 @XXH3_hashLong_64b_withSecret(ptr noalias noundef readonly captures(none) %0, i64 noundef range(i64 241, 0) %1, ptr noalias noundef readonly captures(none) %2, i64 noundef %3) unnamed_addr #12 {
  %5 = alloca [8 x i64], align 16
  call void @llvm.lifetime.start.p0(i64 64, ptr nonnull %5) #24, !noalias !158
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(64) %5, ptr noundef nonnull align 16 dereferenceable(64) @__const.XXH3_hashLong_128b_internal.acc, i64 64, i1 false), !noalias !158
  %6 = add i64 %3, -64
  %7 = lshr i64 %6, 3
  %8 = shl i64 %7, 6
  %9 = udiv i64 %1, %8
  %10 = icmp ugt i64 %8, %1
  br i1 %10, label %72, label %11

11:                                               ; preds = %4
  %12 = icmp ult i64 %6, 8
  %13 = getelementptr inbounds nuw i8, ptr %2, i64 %3
  %14 = getelementptr inbounds i8, ptr %13, i64 -64
  %15 = tail call i64 @llvm.umax.i64(i64 %7, i64 1)
  br label %16

16:                                               ; preds = %11, %69
  %17 = phi i64 [ 0, %11 ], [ %70, %69 ]
  %18 = mul i64 %17, %8
  %19 = getelementptr inbounds nuw i8, ptr %0, i64 %18
  br i1 %12, label %49, label %20

20:                                               ; preds = %16, %46
  %21 = phi i64 [ %47, %46 ], [ 0, %16 ]
  %22 = shl i64 %21, 6
  %23 = getelementptr inbounds nuw i8, ptr %19, i64 %22
  %24 = shl i64 %21, 3
  %25 = getelementptr inbounds nuw i8, ptr %2, i64 %24
  tail call void @llvm.experimental.noalias.scope.decl(metadata !162)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !165)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !167)
  br label %26

26:                                               ; preds = %20, %26
  %27 = phi i64 [ 0, %20 ], [ %44, %26 ]
  %28 = shl nuw nsw i64 %27, 2
  %29 = getelementptr inbounds nuw i32, ptr %23, i64 %28
  %30 = load <4 x i32>, ptr %29, align 4, !alias.scope !165, !noalias !169
  %31 = getelementptr inbounds nuw i32, ptr %25, i64 %28
  %32 = load <4 x i32>, ptr %31, align 4, !alias.scope !167, !noalias !170
  %33 = xor <4 x i32> %32, %30
  %34 = bitcast <4 x i32> %33 to <2 x i64>
  %35 = trunc <2 x i64> %34 to <2 x i32>
  %36 = lshr <2 x i64> %34, splat (i64 32)
  %37 = trunc nuw <2 x i64> %36 to <2 x i32>
  %38 = getelementptr inbounds nuw <2 x i64>, ptr %5, i64 %27
  %39 = load <2 x i64>, ptr %38, align 16, !tbaa !21, !alias.scope !162, !noalias !171
  %40 = bitcast <4 x i32> %30 to <2 x i64>
  %41 = add <2 x i64> %39, %40
  %42 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %35, <2 x i32> %37)
  %43 = add <2 x i64> %41, %42
  store <2 x i64> %43, ptr %38, align 16, !tbaa !21, !alias.scope !162, !noalias !171
  %44 = add nuw nsw i64 %27, 1
  %45 = icmp eq i64 %44, 4
  br i1 %45, label %46, label %26, !llvm.loop !82

46:                                               ; preds = %26
  %47 = add nuw nsw i64 %21, 1
  %48 = icmp eq i64 %47, %15
  br i1 %48, label %49, label %20, !llvm.loop !83

49:                                               ; preds = %46, %16
  tail call void @llvm.experimental.noalias.scope.decl(metadata !172)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !175)
  br label %50

50:                                               ; preds = %49, %50
  %51 = phi i64 [ 0, %49 ], [ %67, %50 ]
  %52 = getelementptr inbounds nuw <2 x i64>, ptr %5, i64 %51
  %53 = load <2 x i64>, ptr %52, align 16, !tbaa !21, !alias.scope !172, !noalias !175
  %54 = lshr <2 x i64> %53, splat (i64 47)
  %55 = xor <2 x i64> %54, %53
  %56 = shl nuw nsw i64 %51, 4
  %57 = getelementptr inbounds nuw i8, ptr %14, i64 %56
  %58 = load <4 x i32>, ptr %57, align 4, !alias.scope !175, !noalias !172
  %59 = bitcast <2 x i64> %55 to <4 x i32>
  %60 = xor <4 x i32> %58, %59
  %61 = shufflevector <4 x i32> %60, <4 x i32> poison, <2 x i32> <i32 0, i32 2>
  %62 = shufflevector <4 x i32> %60, <4 x i32> poison, <2 x i32> <i32 1, i32 3>
  %63 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %62, <2 x i32> splat (i32 -1640531535))
  %64 = shl <2 x i64> %63, splat (i64 32)
  %65 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %61, <2 x i32> splat (i32 -1640531535))
  %66 = add <2 x i64> %64, %65
  store <2 x i64> %66, ptr %52, align 16, !tbaa !21, !alias.scope !172, !noalias !175
  %67 = add nuw nsw i64 %51, 1
  %68 = icmp eq i64 %67, 4
  br i1 %68, label %69, label %50, !llvm.loop !89

69:                                               ; preds = %50
  %70 = add nuw i64 %17, 1
  %71 = icmp ult i64 %70, %9
  br i1 %71, label %16, label %72, !llvm.loop !90

72:                                               ; preds = %69, %4
  %73 = mul i64 %9, %8
  %74 = sub i64 %1, %73
  %75 = lshr i64 %74, 6
  %76 = getelementptr inbounds nuw i8, ptr %0, i64 %73
  %77 = icmp ult i64 %74, 64
  br i1 %77, label %107, label %78

78:                                               ; preds = %72, %104
  %79 = phi i64 [ %105, %104 ], [ 0, %72 ]
  %80 = shl i64 %79, 6
  %81 = getelementptr inbounds nuw i8, ptr %76, i64 %80
  %82 = shl i64 %79, 3
  %83 = getelementptr inbounds nuw i8, ptr %2, i64 %82
  tail call void @llvm.experimental.noalias.scope.decl(metadata !177)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !180)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !182)
  br label %84

84:                                               ; preds = %78, %84
  %85 = phi i64 [ 0, %78 ], [ %102, %84 ]
  %86 = shl nuw nsw i64 %85, 2
  %87 = getelementptr inbounds nuw i32, ptr %81, i64 %86
  %88 = load <4 x i32>, ptr %87, align 4, !alias.scope !180, !noalias !184
  %89 = getelementptr inbounds nuw i32, ptr %83, i64 %86
  %90 = load <4 x i32>, ptr %89, align 4, !alias.scope !182, !noalias !185
  %91 = xor <4 x i32> %90, %88
  %92 = bitcast <4 x i32> %91 to <2 x i64>
  %93 = trunc <2 x i64> %92 to <2 x i32>
  %94 = lshr <2 x i64> %92, splat (i64 32)
  %95 = trunc nuw <2 x i64> %94 to <2 x i32>
  %96 = getelementptr inbounds nuw <2 x i64>, ptr %5, i64 %85
  %97 = load <2 x i64>, ptr %96, align 16, !tbaa !21, !alias.scope !177, !noalias !186
  %98 = bitcast <4 x i32> %88 to <2 x i64>
  %99 = add <2 x i64> %97, %98
  %100 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %93, <2 x i32> %95)
  %101 = add <2 x i64> %99, %100
  store <2 x i64> %101, ptr %96, align 16, !tbaa !21, !alias.scope !177, !noalias !186
  %102 = add nuw nsw i64 %85, 1
  %103 = icmp eq i64 %102, 4
  br i1 %103, label %104, label %84, !llvm.loop !82

104:                                              ; preds = %84
  %105 = add nuw nsw i64 %79, 1
  %106 = icmp samesign ult i64 %105, %75
  br i1 %106, label %78, label %107, !llvm.loop !83

107:                                              ; preds = %104, %72
  %108 = and i64 %1, 63
  %109 = icmp eq i64 %108, 0
  br i1 %109, label %135, label %110

110:                                              ; preds = %107
  %111 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %112 = getelementptr inbounds i8, ptr %111, i64 -64
  %113 = getelementptr inbounds nuw i8, ptr %2, i64 %3
  %114 = getelementptr inbounds i8, ptr %113, i64 -71
  tail call void @llvm.experimental.noalias.scope.decl(metadata !187)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !190)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !192)
  br label %115

115:                                              ; preds = %110, %115
  %116 = phi i64 [ 0, %110 ], [ %133, %115 ]
  %117 = shl nuw nsw i64 %116, 2
  %118 = getelementptr inbounds nuw i32, ptr %112, i64 %117
  %119 = load <4 x i32>, ptr %118, align 4, !alias.scope !190, !noalias !194
  %120 = getelementptr inbounds nuw i32, ptr %114, i64 %117
  %121 = load <4 x i32>, ptr %120, align 4, !alias.scope !192, !noalias !195
  %122 = xor <4 x i32> %121, %119
  %123 = bitcast <4 x i32> %122 to <2 x i64>
  %124 = trunc <2 x i64> %123 to <2 x i32>
  %125 = lshr <2 x i64> %123, splat (i64 32)
  %126 = trunc nuw <2 x i64> %125 to <2 x i32>
  %127 = getelementptr inbounds nuw <2 x i64>, ptr %5, i64 %116
  %128 = load <2 x i64>, ptr %127, align 16, !tbaa !21, !alias.scope !187, !noalias !196
  %129 = bitcast <4 x i32> %119 to <2 x i64>
  %130 = add <2 x i64> %128, %129
  %131 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %124, <2 x i32> %126)
  %132 = add <2 x i64> %130, %131
  store <2 x i64> %132, ptr %127, align 16, !tbaa !21, !alias.scope !187, !noalias !196
  %133 = add nuw nsw i64 %116, 1
  %134 = icmp eq i64 %133, 4
  br i1 %134, label %135, label %115, !llvm.loop !82

135:                                              ; preds = %115, %107
  %136 = getelementptr inbounds nuw i8, ptr %2, i64 11
  %137 = mul i64 %1, -7046029288634856825
  tail call void @llvm.experimental.noalias.scope.decl(metadata !197)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !200)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !202)
  %138 = load i64, ptr %5, align 16, !tbaa !22, !alias.scope !205, !noalias !206
  %139 = load i64, ptr %136, align 1, !alias.scope !200, !noalias !205
  %140 = xor i64 %139, %138
  %141 = getelementptr inbounds nuw i8, ptr %5, i64 8
  %142 = load i64, ptr %141, align 8, !tbaa !22, !alias.scope !205, !noalias !206
  %143 = getelementptr inbounds nuw i8, ptr %2, i64 19
  %144 = load i64, ptr %143, align 1, !alias.scope !200, !noalias !205
  %145 = xor i64 %144, %142
  %146 = zext i64 %140 to i128
  %147 = zext i64 %145 to i128
  %148 = mul nuw i128 %147, %146
  %149 = lshr i128 %148, 64
  %150 = xor i128 %149, %148
  %151 = trunc i128 %150 to i64
  %152 = add i64 %137, %151
  %153 = getelementptr inbounds nuw i8, ptr %5, i64 16
  %154 = getelementptr inbounds nuw i8, ptr %2, i64 27
  tail call void @llvm.experimental.noalias.scope.decl(metadata !208)
  %155 = load i64, ptr %153, align 16, !tbaa !22, !alias.scope !211, !noalias !212
  %156 = load i64, ptr %154, align 1, !alias.scope !200, !noalias !211
  %157 = xor i64 %156, %155
  %158 = getelementptr inbounds nuw i8, ptr %5, i64 24
  %159 = load i64, ptr %158, align 8, !tbaa !22, !alias.scope !211, !noalias !212
  %160 = getelementptr inbounds nuw i8, ptr %2, i64 35
  %161 = load i64, ptr %160, align 1, !alias.scope !200, !noalias !211
  %162 = xor i64 %161, %159
  %163 = zext i64 %157 to i128
  %164 = zext i64 %162 to i128
  %165 = mul nuw i128 %164, %163
  %166 = lshr i128 %165, 64
  %167 = xor i128 %166, %165
  %168 = trunc i128 %167 to i64
  %169 = add i64 %152, %168
  %170 = getelementptr inbounds nuw i8, ptr %5, i64 32
  %171 = getelementptr inbounds nuw i8, ptr %2, i64 43
  tail call void @llvm.experimental.noalias.scope.decl(metadata !214)
  %172 = load i64, ptr %170, align 16, !tbaa !22, !alias.scope !217, !noalias !218
  %173 = load i64, ptr %171, align 1, !alias.scope !200, !noalias !217
  %174 = xor i64 %173, %172
  %175 = getelementptr inbounds nuw i8, ptr %5, i64 40
  %176 = load i64, ptr %175, align 8, !tbaa !22, !alias.scope !217, !noalias !218
  %177 = getelementptr inbounds nuw i8, ptr %2, i64 51
  %178 = load i64, ptr %177, align 1, !alias.scope !200, !noalias !217
  %179 = xor i64 %178, %176
  %180 = zext i64 %174 to i128
  %181 = zext i64 %179 to i128
  %182 = mul nuw i128 %181, %180
  %183 = lshr i128 %182, 64
  %184 = xor i128 %183, %182
  %185 = trunc i128 %184 to i64
  %186 = add i64 %169, %185
  %187 = getelementptr inbounds nuw i8, ptr %5, i64 48
  %188 = getelementptr inbounds nuw i8, ptr %2, i64 59
  tail call void @llvm.experimental.noalias.scope.decl(metadata !220)
  %189 = load i64, ptr %187, align 16, !tbaa !22, !alias.scope !223, !noalias !224
  %190 = load i64, ptr %188, align 1, !alias.scope !200, !noalias !223
  %191 = xor i64 %190, %189
  %192 = getelementptr inbounds nuw i8, ptr %5, i64 56
  %193 = load i64, ptr %192, align 8, !tbaa !22, !alias.scope !223, !noalias !224
  %194 = getelementptr inbounds nuw i8, ptr %2, i64 67
  %195 = load i64, ptr %194, align 1, !alias.scope !200, !noalias !223
  %196 = xor i64 %195, %193
  %197 = zext i64 %191 to i128
  %198 = zext i64 %196 to i128
  %199 = mul nuw i128 %198, %197
  %200 = lshr i128 %199, 64
  %201 = xor i128 %200, %199
  %202 = trunc i128 %201 to i64
  %203 = add i64 %186, %202
  %204 = lshr i64 %203, 37
  %205 = xor i64 %204, %203
  %206 = mul i64 %205, 1609587929392839161
  %207 = lshr i64 %206, 32
  %208 = xor i64 %207, %206
  call void @llvm.lifetime.end.p0(i64 64, ptr nonnull %5) #24, !noalias !158
  ret i64 %208
}

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync)
define i64 @XXH3_64bits_withSeed(ptr noundef readonly captures(none) %0, i64 noundef %1, i64 noundef %2) local_unnamed_addr #13 {
  %4 = icmp ult i64 %1, 17
  br i1 %4, label %5, label %82

5:                                                ; preds = %3
  %6 = icmp samesign ugt i64 %1, 8
  br i1 %6, label %7, label %30

7:                                                ; preds = %5
  %8 = load i64, ptr %0, align 1
  %9 = add i64 %2, -4734510112055689544
  %10 = xor i64 %8, %9
  %11 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %12 = getelementptr inbounds i8, ptr %11, i64 -8
  %13 = load i64, ptr %12, align 1
  %14 = sub i64 2066345149520216444, %2
  %15 = xor i64 %13, %14
  %16 = zext i64 %10 to i128
  %17 = zext i64 %15 to i128
  %18 = mul nuw i128 %17, %16
  %19 = lshr i128 %18, 64
  %20 = xor i128 %19, %18
  %21 = trunc i128 %20 to i64
  %22 = add i64 %10, %1
  %23 = add i64 %22, %15
  %24 = add i64 %23, %21
  %25 = lshr i64 %24, 37
  %26 = xor i64 %25, %24
  %27 = mul i64 %26, 1609587929392839161
  %28 = lshr i64 %27, 32
  %29 = xor i64 %28, %27
  br label %232

30:                                               ; preds = %5
  %31 = icmp samesign ugt i64 %1, 3
  br i1 %31, label %32, label %55

32:                                               ; preds = %30
  %33 = load i32, ptr %0, align 1
  %34 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %35 = getelementptr inbounds i8, ptr %34, i64 -4
  %36 = load i32, ptr %35, align 1
  %37 = zext i32 %33 to i64
  %38 = zext i32 %36 to i64
  %39 = shl nuw i64 %38, 32
  %40 = or disjoint i64 %39, %37
  %41 = add i64 %2, -4734510112055689544
  %42 = xor i64 %40, %41
  %43 = lshr i64 %42, 51
  %44 = xor i64 %43, %42
  %45 = mul i64 %44, 2654435761
  %46 = add i64 %45, %1
  %47 = lshr i64 %46, 47
  %48 = xor i64 %47, %46
  %49 = mul i64 %48, -4417276706812531889
  %50 = lshr i64 %49, 37
  %51 = xor i64 %50, %49
  %52 = mul i64 %51, 1609587929392839161
  %53 = lshr i64 %52, 32
  %54 = xor i64 %53, %52
  br label %232

55:                                               ; preds = %30
  %56 = icmp eq i64 %1, 0
  br i1 %56, label %232, label %57

57:                                               ; preds = %55
  %58 = load i8, ptr %0, align 1, !tbaa !21
  %59 = lshr i64 %1, 1
  %60 = getelementptr inbounds nuw i8, ptr %0, i64 %59
  %61 = load i8, ptr %60, align 1, !tbaa !21
  %62 = getelementptr i8, ptr %0, i64 %1
  %63 = getelementptr i8, ptr %62, i64 -1
  %64 = load i8, ptr %63, align 1, !tbaa !21
  %65 = zext i8 %58 to i64
  %66 = zext i8 %61 to i64
  %67 = shl nuw nsw i64 %66, 8
  %68 = or disjoint i64 %67, %65
  %69 = zext i8 %64 to i64
  %70 = shl nuw nsw i64 %69, 16
  %71 = or disjoint i64 %68, %70
  %72 = shl nuw nsw i64 %1, 24
  %73 = or disjoint i64 %71, %72
  %74 = add i64 %2, 963444408
  %75 = xor i64 %73, %74
  %76 = mul i64 %75, -7046029288634856825
  %77 = lshr i64 %76, 37
  %78 = xor i64 %77, %76
  %79 = mul i64 %78, 1609587929392839161
  %80 = lshr i64 %79, 32
  %81 = xor i64 %80, %79
  br label %232

82:                                               ; preds = %3
  %83 = icmp ult i64 %1, 129
  br i1 %83, label %84, label %226

84:                                               ; preds = %82
  %85 = mul i64 %1, -7046029288634856825
  %86 = icmp samesign ugt i64 %1, 32
  br i1 %86, label %87, label %189

87:                                               ; preds = %84
  %88 = icmp samesign ugt i64 %1, 64
  br i1 %88, label %89, label %156

89:                                               ; preds = %87
  %90 = icmp samesign ugt i64 %1, 96
  br i1 %90, label %91, label %123

91:                                               ; preds = %89
  %92 = getelementptr inbounds nuw i8, ptr %0, i64 48
  %93 = load i64, ptr %92, align 1, !noalias !226
  %94 = getelementptr inbounds nuw i8, ptr %0, i64 56
  %95 = load i64, ptr %94, align 1, !noalias !226
  %96 = add i64 %2, 4554437623014685352
  %97 = xor i64 %93, %96
  %98 = sub i64 2111919702937427193, %2
  %99 = xor i64 %95, %98
  %100 = zext i64 %97 to i128
  %101 = zext i64 %99 to i128
  %102 = mul nuw i128 %101, %100
  %103 = lshr i128 %102, 64
  %104 = xor i128 %103, %102
  %105 = trunc i128 %104 to i64
  %106 = add i64 %85, %105
  %107 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %108 = getelementptr inbounds i8, ptr %107, i64 -64
  %109 = load i64, ptr %108, align 1, !noalias !229
  %110 = getelementptr inbounds i8, ptr %107, i64 -56
  %111 = load i64, ptr %110, align 1, !noalias !229
  %112 = add i64 %2, 3556072174620004746
  %113 = xor i64 %109, %112
  %114 = sub i64 7238261902898274248, %2
  %115 = xor i64 %111, %114
  %116 = zext i64 %113 to i128
  %117 = zext i64 %115 to i128
  %118 = mul nuw i128 %117, %116
  %119 = lshr i128 %118, 64
  %120 = xor i128 %119, %118
  %121 = trunc i128 %120 to i64
  %122 = add i64 %106, %121
  br label %123

123:                                              ; preds = %91, %89
  %124 = phi i64 [ %122, %91 ], [ %85, %89 ]
  %125 = getelementptr inbounds nuw i8, ptr %0, i64 32
  %126 = load i64, ptr %125, align 1, !noalias !232
  %127 = getelementptr inbounds nuw i8, ptr %0, i64 40
  %128 = load i64, ptr %127, align 1, !noalias !232
  %129 = add i64 %2, -3818837453329782724
  %130 = xor i64 %126, %129
  %131 = sub i64 -6688317018830679928, %2
  %132 = xor i64 %128, %131
  %133 = zext i64 %130 to i128
  %134 = zext i64 %132 to i128
  %135 = mul nuw i128 %134, %133
  %136 = lshr i128 %135, 64
  %137 = xor i128 %136, %135
  %138 = trunc i128 %137 to i64
  %139 = add i64 %124, %138
  %140 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %141 = getelementptr inbounds i8, ptr %140, i64 -48
  %142 = load i64, ptr %141, align 1, !noalias !235
  %143 = getelementptr inbounds i8, ptr %140, i64 -40
  %144 = load i64, ptr %143, align 1, !noalias !235
  %145 = add i64 %2, 5690594596133299313
  %146 = xor i64 %142, %145
  %147 = sub i64 -2833645246901970632, %2
  %148 = xor i64 %144, %147
  %149 = zext i64 %146 to i128
  %150 = zext i64 %148 to i128
  %151 = mul nuw i128 %150, %149
  %152 = lshr i128 %151, 64
  %153 = xor i128 %152, %151
  %154 = trunc i128 %153 to i64
  %155 = add i64 %139, %154
  br label %156

156:                                              ; preds = %123, %87
  %157 = phi i64 [ %155, %123 ], [ %85, %87 ]
  %158 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %159 = load i64, ptr %158, align 1, !noalias !238
  %160 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %161 = load i64, ptr %160, align 1, !noalias !238
  %162 = add i64 %2, 8711581037947681227
  %163 = xor i64 %159, %162
  %164 = sub i64 2410270004345854594, %2
  %165 = xor i64 %161, %164
  %166 = zext i64 %163 to i128
  %167 = zext i64 %165 to i128
  %168 = mul nuw i128 %167, %166
  %169 = lshr i128 %168, 64
  %170 = xor i128 %169, %168
  %171 = trunc i128 %170 to i64
  %172 = add i64 %157, %171
  %173 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %174 = getelementptr inbounds i8, ptr %173, i64 -32
  %175 = load i64, ptr %174, align 1, !noalias !241
  %176 = getelementptr inbounds i8, ptr %173, i64 -24
  %177 = load i64, ptr %176, align 1, !noalias !241
  %178 = add i64 %2, -8204357891075471176
  %179 = xor i64 %175, %178
  %180 = sub i64 5487137525590930912, %2
  %181 = xor i64 %177, %180
  %182 = zext i64 %179 to i128
  %183 = zext i64 %181 to i128
  %184 = mul nuw i128 %183, %182
  %185 = lshr i128 %184, 64
  %186 = xor i128 %185, %184
  %187 = trunc i128 %186 to i64
  %188 = add i64 %172, %187
  br label %189

189:                                              ; preds = %84, %156
  %190 = phi i64 [ %188, %156 ], [ %85, %84 ]
  %191 = load i64, ptr %0, align 1, !noalias !244
  %192 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %193 = load i64, ptr %192, align 1, !noalias !244
  %194 = add i64 %2, -4734510112055689544
  %195 = xor i64 %191, %194
  %196 = sub i64 2066345149520216444, %2
  %197 = xor i64 %193, %196
  %198 = zext i64 %195 to i128
  %199 = zext i64 %197 to i128
  %200 = mul nuw i128 %199, %198
  %201 = lshr i128 %200, 64
  %202 = xor i128 %201, %200
  %203 = trunc i128 %202 to i64
  %204 = add i64 %190, %203
  %205 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %206 = getelementptr inbounds i8, ptr %205, i64 -16
  %207 = load i64, ptr %206, align 1, !noalias !247
  %208 = getelementptr inbounds i8, ptr %205, i64 -8
  %209 = load i64, ptr %208, align 1, !noalias !247
  %210 = add i64 %2, -2623469361688619810
  %211 = xor i64 %207, %210
  %212 = sub i64 2262974939099578482, %2
  %213 = xor i64 %209, %212
  %214 = zext i64 %211 to i128
  %215 = zext i64 %213 to i128
  %216 = mul nuw i128 %215, %214
  %217 = lshr i128 %216, 64
  %218 = xor i128 %217, %216
  %219 = trunc i128 %218 to i64
  %220 = add i64 %204, %219
  %221 = lshr i64 %220, 37
  %222 = xor i64 %221, %220
  %223 = mul i64 %222, 1609587929392839161
  %224 = lshr i64 %223, 32
  %225 = xor i64 %224, %223
  br label %232

226:                                              ; preds = %82
  %227 = icmp ult i64 %1, 241
  br i1 %227, label %228, label %230

228:                                              ; preds = %226
  %229 = tail call fastcc i64 @XXH3_len_129to240_64b(ptr noundef %0, i64 noundef %1, ptr noundef nonnull @kSecret, i64 noundef %2)
  br label %232

230:                                              ; preds = %226
  %231 = tail call fastcc i64 @XXH3_hashLong_64b_withSeed(ptr noundef %0, i64 noundef %1, i64 noundef %2)
  br label %232

232:                                              ; preds = %57, %55, %32, %7, %230, %228, %189
  %233 = phi i64 [ %225, %189 ], [ %229, %228 ], [ %231, %230 ], [ %29, %7 ], [ %54, %32 ], [ %81, %57 ], [ 0, %55 ]
  ret i64 %233
}

; Function Attrs: nofree noinline norecurse nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync)
define internal fastcc i64 @XXH3_hashLong_64b_withSeed(ptr noundef readonly captures(none) %0, i64 noundef range(i64 241, 0) %1, i64 noundef %2) unnamed_addr #14 {
  %4 = alloca [8 x i64], align 16
  %5 = alloca [192 x i8], align 8
  call void @llvm.lifetime.start.p0(i64 192, ptr nonnull %5) #24
  %6 = icmp eq i64 %2, 0
  br i1 %6, label %7, label %9

7:                                                ; preds = %3
  %8 = tail call fastcc i64 @XXH3_hashLong_64b_defaultSecret(ptr noundef %0, i64 noundef %1)
  br label %219

9:                                                ; preds = %3, %9
  %10 = phi i64 [ %20, %9 ], [ 0, %3 ]
  %11 = shl nuw nsw i64 %10, 4
  %12 = getelementptr inbounds nuw i8, ptr %5, i64 %11
  %13 = getelementptr inbounds nuw i8, ptr @kSecret, i64 %11
  %14 = load i64, ptr %13, align 16
  %15 = add i64 %14, %2
  store i64 %15, ptr %12, align 8
  %16 = getelementptr inbounds nuw i8, ptr %12, i64 8
  %17 = getelementptr inbounds nuw i8, ptr %13, i64 8
  %18 = load i64, ptr %17, align 8
  %19 = sub i64 %18, %2
  store i64 %19, ptr %16, align 8
  %20 = add nuw nsw i64 %10, 1
  %21 = icmp eq i64 %20, 12
  br i1 %21, label %22, label %9, !llvm.loop !250

22:                                               ; preds = %9
  call void @llvm.lifetime.start.p0(i64 64, ptr nonnull %4) #24, !noalias !251
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(64) %4, ptr noundef nonnull align 16 dereferenceable(64) @__const.XXH3_hashLong_128b_internal.acc, i64 64, i1 false), !noalias !251
  %23 = lshr i64 %1, 10
  %24 = icmp ult i64 %1, 1024
  br i1 %24, label %83, label %25

25:                                               ; preds = %22
  %26 = getelementptr inbounds nuw i8, ptr %5, i64 128
  br label %27

27:                                               ; preds = %25, %80
  %28 = phi i64 [ 0, %25 ], [ %81, %80 ]
  %29 = shl i64 %28, 10
  %30 = getelementptr inbounds nuw i8, ptr %0, i64 %29
  br label %31

31:                                               ; preds = %27, %57
  %32 = phi i64 [ 0, %27 ], [ %58, %57 ]
  %33 = shl nuw nsw i64 %32, 6
  %34 = getelementptr inbounds nuw i8, ptr %30, i64 %33
  %35 = shl nuw nsw i64 %32, 3
  %36 = getelementptr inbounds nuw i8, ptr %5, i64 %35
  tail call void @llvm.experimental.noalias.scope.decl(metadata !255)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !258)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !260)
  br label %37

37:                                               ; preds = %31, %37
  %38 = phi i64 [ 0, %31 ], [ %55, %37 ]
  %39 = shl nuw nsw i64 %38, 2
  %40 = getelementptr inbounds nuw i32, ptr %34, i64 %39
  %41 = load <4 x i32>, ptr %40, align 4, !alias.scope !258, !noalias !262
  %42 = getelementptr inbounds nuw i32, ptr %36, i64 %39
  %43 = load <4 x i32>, ptr %42, align 8, !alias.scope !260, !noalias !263
  %44 = xor <4 x i32> %43, %41
  %45 = bitcast <4 x i32> %44 to <2 x i64>
  %46 = trunc <2 x i64> %45 to <2 x i32>
  %47 = lshr <2 x i64> %45, splat (i64 32)
  %48 = trunc nuw <2 x i64> %47 to <2 x i32>
  %49 = getelementptr inbounds nuw <2 x i64>, ptr %4, i64 %38
  %50 = load <2 x i64>, ptr %49, align 16, !tbaa !21, !alias.scope !255, !noalias !264
  %51 = bitcast <4 x i32> %41 to <2 x i64>
  %52 = add <2 x i64> %50, %51
  %53 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %46, <2 x i32> %48)
  %54 = add <2 x i64> %52, %53
  store <2 x i64> %54, ptr %49, align 16, !tbaa !21, !alias.scope !255, !noalias !264
  %55 = add nuw nsw i64 %38, 1
  %56 = icmp eq i64 %55, 4
  br i1 %56, label %57, label %37, !llvm.loop !82

57:                                               ; preds = %37
  %58 = add nuw nsw i64 %32, 1
  %59 = icmp eq i64 %58, 16
  br i1 %59, label %60, label %31, !llvm.loop !83

60:                                               ; preds = %57
  tail call void @llvm.experimental.noalias.scope.decl(metadata !265)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !268)
  br label %61

61:                                               ; preds = %60, %61
  %62 = phi i64 [ 0, %60 ], [ %78, %61 ]
  %63 = getelementptr inbounds nuw <2 x i64>, ptr %4, i64 %62
  %64 = load <2 x i64>, ptr %63, align 16, !tbaa !21, !alias.scope !265, !noalias !268
  %65 = lshr <2 x i64> %64, splat (i64 47)
  %66 = xor <2 x i64> %65, %64
  %67 = shl nuw nsw i64 %62, 4
  %68 = getelementptr inbounds nuw i8, ptr %26, i64 %67
  %69 = load <4 x i32>, ptr %68, align 8, !alias.scope !268, !noalias !265
  %70 = bitcast <2 x i64> %66 to <4 x i32>
  %71 = xor <4 x i32> %69, %70
  %72 = shufflevector <4 x i32> %71, <4 x i32> poison, <2 x i32> <i32 0, i32 2>
  %73 = shufflevector <4 x i32> %71, <4 x i32> poison, <2 x i32> <i32 1, i32 3>
  %74 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %73, <2 x i32> splat (i32 -1640531535))
  %75 = shl <2 x i64> %74, splat (i64 32)
  %76 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %72, <2 x i32> splat (i32 -1640531535))
  %77 = add <2 x i64> %75, %76
  store <2 x i64> %77, ptr %63, align 16, !tbaa !21, !alias.scope !265, !noalias !268
  %78 = add nuw nsw i64 %62, 1
  %79 = icmp eq i64 %78, 4
  br i1 %79, label %80, label %61, !llvm.loop !89

80:                                               ; preds = %61
  %81 = add nuw nsw i64 %28, 1
  %82 = icmp eq i64 %81, %23
  br i1 %82, label %83, label %27, !llvm.loop !90

83:                                               ; preds = %80, %22
  %84 = and i64 %1, -1024
  %85 = lshr i64 %1, 6
  %86 = and i64 %85, 15
  %87 = getelementptr inbounds nuw i8, ptr %0, i64 %84
  %88 = icmp eq i64 %86, 0
  br i1 %88, label %118, label %89

89:                                               ; preds = %83, %115
  %90 = phi i64 [ %116, %115 ], [ 0, %83 ]
  %91 = shl i64 %90, 6
  %92 = getelementptr inbounds nuw i8, ptr %87, i64 %91
  %93 = shl i64 %90, 3
  %94 = getelementptr inbounds nuw i8, ptr %5, i64 %93
  tail call void @llvm.experimental.noalias.scope.decl(metadata !270)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !273)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !275)
  br label %95

95:                                               ; preds = %89, %95
  %96 = phi i64 [ 0, %89 ], [ %113, %95 ]
  %97 = shl nuw nsw i64 %96, 2
  %98 = getelementptr inbounds nuw i32, ptr %92, i64 %97
  %99 = load <4 x i32>, ptr %98, align 4, !alias.scope !273, !noalias !277
  %100 = getelementptr inbounds nuw i32, ptr %94, i64 %97
  %101 = load <4 x i32>, ptr %100, align 8, !alias.scope !275, !noalias !278
  %102 = xor <4 x i32> %101, %99
  %103 = bitcast <4 x i32> %102 to <2 x i64>
  %104 = trunc <2 x i64> %103 to <2 x i32>
  %105 = lshr <2 x i64> %103, splat (i64 32)
  %106 = trunc nuw <2 x i64> %105 to <2 x i32>
  %107 = getelementptr inbounds nuw <2 x i64>, ptr %4, i64 %96
  %108 = load <2 x i64>, ptr %107, align 16, !tbaa !21, !alias.scope !270, !noalias !279
  %109 = bitcast <4 x i32> %99 to <2 x i64>
  %110 = add <2 x i64> %108, %109
  %111 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %104, <2 x i32> %106)
  %112 = add <2 x i64> %110, %111
  store <2 x i64> %112, ptr %107, align 16, !tbaa !21, !alias.scope !270, !noalias !279
  %113 = add nuw nsw i64 %96, 1
  %114 = icmp eq i64 %113, 4
  br i1 %114, label %115, label %95, !llvm.loop !82

115:                                              ; preds = %95
  %116 = add nuw nsw i64 %90, 1
  %117 = icmp eq i64 %116, %86
  br i1 %117, label %118, label %89, !llvm.loop !83

118:                                              ; preds = %115, %83
  %119 = and i64 %1, 63
  %120 = icmp eq i64 %119, 0
  br i1 %120, label %145, label %121

121:                                              ; preds = %118
  %122 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %123 = getelementptr inbounds i8, ptr %122, i64 -64
  %124 = getelementptr inbounds nuw i8, ptr %5, i64 121
  tail call void @llvm.experimental.noalias.scope.decl(metadata !280)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !283)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !285)
  br label %125

125:                                              ; preds = %121, %125
  %126 = phi i64 [ 0, %121 ], [ %143, %125 ]
  %127 = shl nuw nsw i64 %126, 2
  %128 = getelementptr inbounds nuw i32, ptr %123, i64 %127
  %129 = load <4 x i32>, ptr %128, align 4, !alias.scope !283, !noalias !287
  %130 = getelementptr inbounds nuw i32, ptr %124, i64 %127
  %131 = load <4 x i32>, ptr %130, align 4, !alias.scope !285, !noalias !288
  %132 = xor <4 x i32> %131, %129
  %133 = bitcast <4 x i32> %132 to <2 x i64>
  %134 = trunc <2 x i64> %133 to <2 x i32>
  %135 = lshr <2 x i64> %133, splat (i64 32)
  %136 = trunc nuw <2 x i64> %135 to <2 x i32>
  %137 = getelementptr inbounds nuw <2 x i64>, ptr %4, i64 %126
  %138 = load <2 x i64>, ptr %137, align 16, !tbaa !21, !alias.scope !280, !noalias !289
  %139 = bitcast <4 x i32> %129 to <2 x i64>
  %140 = add <2 x i64> %138, %139
  %141 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %134, <2 x i32> %136)
  %142 = add <2 x i64> %140, %141
  store <2 x i64> %142, ptr %137, align 16, !tbaa !21, !alias.scope !280, !noalias !289
  %143 = add nuw nsw i64 %126, 1
  %144 = icmp eq i64 %143, 4
  br i1 %144, label %145, label %125, !llvm.loop !82

145:                                              ; preds = %125, %118
  %146 = getelementptr inbounds nuw i8, ptr %5, i64 11
  %147 = mul i64 %1, -7046029288634856825
  tail call void @llvm.experimental.noalias.scope.decl(metadata !290)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !293)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !295)
  %148 = load i64, ptr %4, align 16, !tbaa !22, !alias.scope !298, !noalias !299
  %149 = load i64, ptr %146, align 1, !alias.scope !293, !noalias !298
  %150 = xor i64 %149, %148
  %151 = getelementptr inbounds nuw i8, ptr %4, i64 8
  %152 = load i64, ptr %151, align 8, !tbaa !22, !alias.scope !298, !noalias !299
  %153 = getelementptr inbounds nuw i8, ptr %5, i64 19
  %154 = load i64, ptr %153, align 1, !alias.scope !293, !noalias !298
  %155 = xor i64 %154, %152
  %156 = zext i64 %150 to i128
  %157 = zext i64 %155 to i128
  %158 = mul nuw i128 %157, %156
  %159 = lshr i128 %158, 64
  %160 = xor i128 %159, %158
  %161 = trunc i128 %160 to i64
  %162 = add i64 %147, %161
  %163 = getelementptr inbounds nuw i8, ptr %4, i64 16
  %164 = getelementptr inbounds nuw i8, ptr %5, i64 27
  tail call void @llvm.experimental.noalias.scope.decl(metadata !301)
  %165 = load i64, ptr %163, align 16, !tbaa !22, !alias.scope !304, !noalias !305
  %166 = load i64, ptr %164, align 1, !alias.scope !293, !noalias !304
  %167 = xor i64 %166, %165
  %168 = getelementptr inbounds nuw i8, ptr %4, i64 24
  %169 = load i64, ptr %168, align 8, !tbaa !22, !alias.scope !304, !noalias !305
  %170 = getelementptr inbounds nuw i8, ptr %5, i64 35
  %171 = load i64, ptr %170, align 1, !alias.scope !293, !noalias !304
  %172 = xor i64 %171, %169
  %173 = zext i64 %167 to i128
  %174 = zext i64 %172 to i128
  %175 = mul nuw i128 %174, %173
  %176 = lshr i128 %175, 64
  %177 = xor i128 %176, %175
  %178 = trunc i128 %177 to i64
  %179 = add i64 %162, %178
  %180 = getelementptr inbounds nuw i8, ptr %4, i64 32
  %181 = getelementptr inbounds nuw i8, ptr %5, i64 43
  tail call void @llvm.experimental.noalias.scope.decl(metadata !307)
  %182 = load i64, ptr %180, align 16, !tbaa !22, !alias.scope !310, !noalias !311
  %183 = load i64, ptr %181, align 1, !alias.scope !293, !noalias !310
  %184 = xor i64 %183, %182
  %185 = getelementptr inbounds nuw i8, ptr %4, i64 40
  %186 = load i64, ptr %185, align 8, !tbaa !22, !alias.scope !310, !noalias !311
  %187 = getelementptr inbounds nuw i8, ptr %5, i64 51
  %188 = load i64, ptr %187, align 1, !alias.scope !293, !noalias !310
  %189 = xor i64 %188, %186
  %190 = zext i64 %184 to i128
  %191 = zext i64 %189 to i128
  %192 = mul nuw i128 %191, %190
  %193 = lshr i128 %192, 64
  %194 = xor i128 %193, %192
  %195 = trunc i128 %194 to i64
  %196 = add i64 %179, %195
  %197 = getelementptr inbounds nuw i8, ptr %4, i64 48
  %198 = getelementptr inbounds nuw i8, ptr %5, i64 59
  tail call void @llvm.experimental.noalias.scope.decl(metadata !313)
  %199 = load i64, ptr %197, align 16, !tbaa !22, !alias.scope !316, !noalias !317
  %200 = load i64, ptr %198, align 1, !alias.scope !293, !noalias !316
  %201 = xor i64 %200, %199
  %202 = getelementptr inbounds nuw i8, ptr %4, i64 56
  %203 = load i64, ptr %202, align 8, !tbaa !22, !alias.scope !316, !noalias !317
  %204 = getelementptr inbounds nuw i8, ptr %5, i64 67
  %205 = load i64, ptr %204, align 1, !alias.scope !293, !noalias !316
  %206 = xor i64 %205, %203
  %207 = zext i64 %201 to i128
  %208 = zext i64 %206 to i128
  %209 = mul nuw i128 %208, %207
  %210 = lshr i128 %209, 64
  %211 = xor i128 %210, %209
  %212 = trunc i128 %211 to i64
  %213 = add i64 %196, %212
  %214 = lshr i64 %213, 37
  %215 = xor i64 %214, %213
  %216 = mul i64 %215, 1609587929392839161
  %217 = lshr i64 %216, 32
  %218 = xor i64 %217, %216
  call void @llvm.lifetime.end.p0(i64 64, ptr nonnull %4) #24, !noalias !251
  br label %219

219:                                              ; preds = %145, %7
  %220 = phi i64 [ %8, %7 ], [ %218, %145 ]
  call void @llvm.lifetime.end.p0(i64 192, ptr nonnull %5) #24
  ret i64 %220
}

; Function Attrs: mustprogress nofree nounwind ssp willreturn memory(inaccessiblemem: readwrite) uwtable(sync)
define noalias noundef ptr @XXH3_createState() local_unnamed_addr #2 {
  %1 = tail call noalias noundef dereferenceable_or_null(576) ptr @malloc(i64 noundef 576) #23
  ret ptr %1
}

; Function Attrs: mustprogress nounwind ssp willreturn memory(argmem: readwrite, inaccessiblemem: readwrite) uwtable(sync)
define noundef i32 @XXH3_freeState(ptr noundef captures(none) %0) local_unnamed_addr #3 {
  tail call void @free(ptr noundef %0)
  ret i32 0
}

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define void @XXH3_copyState(ptr noundef %0, ptr noundef readonly captures(none) %1) local_unnamed_addr #4 {
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(576) %0, ptr noundef nonnull align 1 dereferenceable(576) %1, i64 noundef 576, i1 noundef false) #24
  ret void
}

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define range(i32 0, 2) i32 @XXH3_64bits_reset(ptr noundef %0) local_unnamed_addr #4 {
  %2 = icmp eq ptr %0, null
  br i1 %2, label %15, label %3

3:                                                ; preds = %1
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(576) %0, i8 noundef 0, i64 noundef 576, i1 noundef false) #24
  store i64 3266489917, ptr %0, align 16, !tbaa !22
  %4 = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i64 -7046029288634856825, ptr %4, align 8, !tbaa !22
  %5 = getelementptr inbounds nuw i8, ptr %0, i64 16
  store i64 -4417276706812531889, ptr %5, align 16, !tbaa !22
  %6 = getelementptr inbounds nuw i8, ptr %0, i64 24
  store i64 1609587929392839161, ptr %6, align 8, !tbaa !22
  %7 = getelementptr inbounds nuw i8, ptr %0, i64 32
  store i64 -8796714831421723037, ptr %7, align 16, !tbaa !22
  %8 = getelementptr inbounds nuw i8, ptr %0, i64 40
  store i64 2246822519, ptr %8, align 8, !tbaa !22
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 48
  store i64 2870177450012600261, ptr %9, align 16, !tbaa !22
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 56
  store i64 2654435761, ptr %10, align 8, !tbaa !22
  %11 = getelementptr inbounds nuw i8, ptr %0, i64 552
  store i64 0, ptr %11, align 8, !tbaa !319
  %12 = getelementptr inbounds nuw i8, ptr %0, i64 512
  store ptr @kSecret, ptr %12, align 16, !tbaa !322
  %13 = getelementptr inbounds nuw i8, ptr %0, i64 540
  store i32 128, ptr %13, align 4, !tbaa !323
  %14 = getelementptr inbounds nuw i8, ptr %0, i64 524
  store i32 16, ptr %14, align 4, !tbaa !324
  br label %15

15:                                               ; preds = %1, %3
  %16 = phi i32 [ 0, %3 ], [ 1, %1 ]
  ret i32 %16
}

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define range(i32 0, 2) i32 @XXH3_64bits_reset_withSecret(ptr noundef %0, ptr noundef %1, i64 noundef %2) local_unnamed_addr #4 {
  %4 = icmp eq ptr %0, null
  br i1 %4, label %24, label %5

5:                                                ; preds = %3
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(576) %0, i8 noundef 0, i64 noundef 576, i1 noundef false) #24
  store i64 3266489917, ptr %0, align 16, !tbaa !22
  %6 = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i64 -7046029288634856825, ptr %6, align 8, !tbaa !22
  %7 = getelementptr inbounds nuw i8, ptr %0, i64 16
  store i64 -4417276706812531889, ptr %7, align 16, !tbaa !22
  %8 = getelementptr inbounds nuw i8, ptr %0, i64 24
  store i64 1609587929392839161, ptr %8, align 8, !tbaa !22
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 32
  store i64 -8796714831421723037, ptr %9, align 16, !tbaa !22
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 40
  store i64 2246822519, ptr %10, align 8, !tbaa !22
  %11 = getelementptr inbounds nuw i8, ptr %0, i64 48
  store i64 2870177450012600261, ptr %11, align 16, !tbaa !22
  %12 = getelementptr inbounds nuw i8, ptr %0, i64 56
  store i64 2654435761, ptr %12, align 8, !tbaa !22
  %13 = getelementptr inbounds nuw i8, ptr %0, i64 552
  store i64 0, ptr %13, align 8, !tbaa !319
  %14 = getelementptr inbounds nuw i8, ptr %0, i64 512
  store ptr %1, ptr %14, align 16, !tbaa !322
  %15 = trunc i64 %2 to i32
  %16 = add i32 %15, -64
  %17 = getelementptr inbounds nuw i8, ptr %0, i64 540
  store i32 %16, ptr %17, align 4, !tbaa !323
  %18 = lshr i32 %16, 3
  %19 = getelementptr inbounds nuw i8, ptr %0, i64 524
  store i32 %18, ptr %19, align 4, !tbaa !324
  %20 = icmp eq ptr %1, null
  br i1 %20, label %24, label %21

21:                                               ; preds = %5
  %22 = icmp ult i64 %2, 136
  %23 = zext i1 %22 to i32
  br label %24

24:                                               ; preds = %21, %5, %3
  %25 = phi i32 [ 1, %3 ], [ 1, %5 ], [ %23, %21 ]
  ret i32 %25
}

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define range(i32 0, 2) i32 @XXH3_64bits_reset_withSeed(ptr noundef %0, i64 noundef %1) local_unnamed_addr #4 {
  %3 = icmp eq ptr %0, null
  br i1 %3, label %31, label %4

4:                                                ; preds = %2
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(576) %0, i8 noundef 0, i64 noundef 576, i1 noundef false) #24
  store i64 3266489917, ptr %0, align 16, !tbaa !22
  %5 = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i64 -7046029288634856825, ptr %5, align 8, !tbaa !22
  %6 = getelementptr inbounds nuw i8, ptr %0, i64 16
  store i64 -4417276706812531889, ptr %6, align 16, !tbaa !22
  %7 = getelementptr inbounds nuw i8, ptr %0, i64 24
  store i64 1609587929392839161, ptr %7, align 8, !tbaa !22
  %8 = getelementptr inbounds nuw i8, ptr %0, i64 32
  store i64 -8796714831421723037, ptr %8, align 16, !tbaa !22
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 40
  store i64 2246822519, ptr %9, align 8, !tbaa !22
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 48
  store i64 2870177450012600261, ptr %10, align 16, !tbaa !22
  %11 = getelementptr inbounds nuw i8, ptr %0, i64 56
  store i64 2654435761, ptr %11, align 8, !tbaa !22
  %12 = getelementptr inbounds nuw i8, ptr %0, i64 552
  store i64 %1, ptr %12, align 8, !tbaa !319
  %13 = getelementptr inbounds nuw i8, ptr %0, i64 512
  store ptr @kSecret, ptr %13, align 16, !tbaa !322
  %14 = getelementptr inbounds nuw i8, ptr %0, i64 540
  store i32 128, ptr %14, align 4, !tbaa !323
  %15 = getelementptr inbounds nuw i8, ptr %0, i64 524
  store i32 16, ptr %15, align 4, !tbaa !324
  %16 = getelementptr inbounds nuw i8, ptr %0, i64 64
  br label %17

17:                                               ; preds = %4, %17
  %18 = phi i64 [ 0, %4 ], [ %28, %17 ]
  %19 = shl nuw nsw i64 %18, 4
  %20 = getelementptr inbounds nuw i8, ptr %16, i64 %19
  %21 = getelementptr inbounds nuw i8, ptr @kSecret, i64 %19
  %22 = load i64, ptr %21, align 16
  %23 = add i64 %22, %1
  store i64 %23, ptr %20, align 1
  %24 = getelementptr inbounds nuw i8, ptr %20, i64 8
  %25 = getelementptr inbounds nuw i8, ptr %21, i64 8
  %26 = load i64, ptr %25, align 8
  %27 = sub i64 %26, %1
  store i64 %27, ptr %24, align 1
  %28 = add nuw nsw i64 %18, 1
  %29 = icmp eq i64 %28, 12
  br i1 %29, label %30, label %17, !llvm.loop !250

30:                                               ; preds = %17
  store ptr %16, ptr %13, align 16, !tbaa !322
  br label %31

31:                                               ; preds = %2, %30
  %32 = phi i32 [ 0, %30 ], [ 1, %2 ]
  ret i32 %32
}

; Function Attrs: nofree norecurse nounwind ssp memory(read, argmem: readwrite, inaccessiblemem: readwrite) uwtable(sync)
define range(i32 0, 2) i32 @XXH3_64bits_update(ptr noundef %0, ptr noundef %1, i64 noundef %2) local_unnamed_addr #15 {
  %4 = icmp eq ptr %1, null
  br i1 %4, label %324, label %5

5:                                                ; preds = %3
  %6 = getelementptr inbounds nuw i8, ptr %1, i64 %2
  %7 = getelementptr inbounds nuw i8, ptr %0, i64 544
  %8 = load i64, ptr %7, align 16, !tbaa !325
  %9 = add i64 %8, %2
  store i64 %9, ptr %7, align 16, !tbaa !325
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 520
  %11 = load i32, ptr %10, align 8, !tbaa !326
  %12 = zext i32 %11 to i64
  %13 = add i64 %2, %12
  %14 = icmp ult i64 %13, 257
  br i1 %14, label %15, label %21

15:                                               ; preds = %5
  %16 = getelementptr inbounds nuw i8, ptr %0, i64 256
  %17 = getelementptr inbounds nuw i8, ptr %16, i64 %12
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %17, ptr noundef nonnull readonly align 1 %1, i64 noundef %2, i1 noundef false) #24
  %18 = trunc i64 %2 to i32
  %19 = load i32, ptr %10, align 8, !tbaa !326
  %20 = add i32 %19, %18
  br label %322

21:                                               ; preds = %5
  %22 = icmp eq i32 %11, 0
  br i1 %22, label %166, label %23

23:                                               ; preds = %21
  %24 = sub i32 256, %11
  %25 = zext i32 %24 to i64
  %26 = getelementptr inbounds nuw i8, ptr %0, i64 256
  %27 = getelementptr inbounds nuw i8, ptr %26, i64 %12
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %27, ptr noundef nonnull readonly align 1 %1, i64 noundef %25, i1 noundef false) #24
  %28 = getelementptr inbounds nuw i8, ptr %1, i64 %25
  %29 = getelementptr inbounds nuw i8, ptr %0, i64 528
  %30 = getelementptr inbounds nuw i8, ptr %0, i64 524
  %31 = load i32, ptr %30, align 4, !tbaa !324
  %32 = getelementptr inbounds nuw i8, ptr %0, i64 512
  %33 = load ptr, ptr %32, align 16, !tbaa !322
  %34 = getelementptr inbounds nuw i8, ptr %0, i64 540
  %35 = load i32, ptr %34, align 4, !tbaa !323
  %36 = zext i32 %35 to i64
  %37 = load i32, ptr %29, align 4, !tbaa !5
  %38 = sub i32 %31, %37
  %39 = zext i32 %38 to i64
  %40 = icmp ugt i32 %38, 4
  %41 = shl i32 %37, 3
  %42 = zext i32 %41 to i64
  %43 = getelementptr inbounds nuw i8, ptr %33, i64 %42
  br i1 %40, label %132, label %44

44:                                               ; preds = %23
  %45 = icmp eq i32 %31, %37
  br i1 %45, label %75, label %46

46:                                               ; preds = %44, %72
  %47 = phi i64 [ %73, %72 ], [ 0, %44 ]
  %48 = shl i64 %47, 6
  %49 = getelementptr inbounds nuw i8, ptr %26, i64 %48
  %50 = shl i64 %47, 3
  %51 = getelementptr inbounds nuw i8, ptr %43, i64 %50
  tail call void @llvm.experimental.noalias.scope.decl(metadata !327)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !330)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !332)
  br label %52

52:                                               ; preds = %46, %52
  %53 = phi i64 [ 0, %46 ], [ %70, %52 ]
  %54 = shl nuw nsw i64 %53, 2
  %55 = getelementptr inbounds nuw i32, ptr %49, i64 %54
  %56 = load <4 x i32>, ptr %55, align 4, !alias.scope !330, !noalias !334
  %57 = getelementptr inbounds nuw i32, ptr %51, i64 %54
  %58 = load <4 x i32>, ptr %57, align 4, !alias.scope !332, !noalias !335
  %59 = xor <4 x i32> %58, %56
  %60 = bitcast <4 x i32> %59 to <2 x i64>
  %61 = trunc <2 x i64> %60 to <2 x i32>
  %62 = lshr <2 x i64> %60, splat (i64 32)
  %63 = trunc nuw <2 x i64> %62 to <2 x i32>
  %64 = getelementptr inbounds nuw <2 x i64>, ptr %0, i64 %53
  %65 = load <2 x i64>, ptr %64, align 16, !tbaa !21, !alias.scope !327, !noalias !336
  %66 = bitcast <4 x i32> %56 to <2 x i64>
  %67 = add <2 x i64> %65, %66
  %68 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %61, <2 x i32> %63)
  %69 = add <2 x i64> %67, %68
  store <2 x i64> %69, ptr %64, align 16, !tbaa !21, !alias.scope !327, !noalias !336
  %70 = add nuw nsw i64 %53, 1
  %71 = icmp eq i64 %70, 4
  br i1 %71, label %72, label %52, !llvm.loop !82

72:                                               ; preds = %52
  %73 = add nuw nsw i64 %47, 1
  %74 = icmp eq i64 %73, %39
  br i1 %74, label %75, label %46, !llvm.loop !83

75:                                               ; preds = %72, %44
  %76 = getelementptr inbounds nuw i8, ptr %33, i64 %36
  tail call void @llvm.experimental.noalias.scope.decl(metadata !337)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !340)
  br label %77

77:                                               ; preds = %75, %77
  %78 = phi i64 [ 0, %75 ], [ %94, %77 ]
  %79 = getelementptr inbounds nuw <2 x i64>, ptr %0, i64 %78
  %80 = load <2 x i64>, ptr %79, align 16, !tbaa !21, !alias.scope !337, !noalias !340
  %81 = lshr <2 x i64> %80, splat (i64 47)
  %82 = xor <2 x i64> %81, %80
  %83 = shl nuw nsw i64 %78, 4
  %84 = getelementptr inbounds nuw i8, ptr %76, i64 %83
  %85 = load <4 x i32>, ptr %84, align 4, !alias.scope !340, !noalias !337
  %86 = bitcast <2 x i64> %82 to <4 x i32>
  %87 = xor <4 x i32> %85, %86
  %88 = shufflevector <4 x i32> %87, <4 x i32> poison, <2 x i32> <i32 0, i32 2>
  %89 = shufflevector <4 x i32> %87, <4 x i32> poison, <2 x i32> <i32 1, i32 3>
  %90 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %89, <2 x i32> splat (i32 -1640531535))
  %91 = shl <2 x i64> %90, splat (i64 32)
  %92 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %88, <2 x i32> splat (i32 -1640531535))
  %93 = add <2 x i64> %91, %92
  store <2 x i64> %93, ptr %79, align 16, !tbaa !21, !alias.scope !337, !noalias !340
  %94 = add nuw nsw i64 %78, 1
  %95 = icmp eq i64 %94, 4
  br i1 %95, label %96, label %77, !llvm.loop !89

96:                                               ; preds = %77
  %97 = shl nuw nsw i64 %39, 6
  %98 = getelementptr inbounds nuw i8, ptr %26, i64 %97
  %99 = sub nsw i64 4, %39
  %100 = icmp eq i32 %38, 4
  br i1 %100, label %130, label %101

101:                                              ; preds = %96, %127
  %102 = phi i64 [ %128, %127 ], [ 0, %96 ]
  %103 = shl i64 %102, 6
  %104 = getelementptr inbounds nuw i8, ptr %98, i64 %103
  %105 = shl i64 %102, 3
  %106 = getelementptr inbounds nuw i8, ptr %33, i64 %105
  tail call void @llvm.experimental.noalias.scope.decl(metadata !342)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !345)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !347)
  br label %107

107:                                              ; preds = %101, %107
  %108 = phi i64 [ 0, %101 ], [ %125, %107 ]
  %109 = shl nuw nsw i64 %108, 2
  %110 = getelementptr inbounds nuw i32, ptr %104, i64 %109
  %111 = load <4 x i32>, ptr %110, align 4, !alias.scope !345, !noalias !349
  %112 = getelementptr inbounds nuw i32, ptr %106, i64 %109
  %113 = load <4 x i32>, ptr %112, align 4, !alias.scope !347, !noalias !350
  %114 = xor <4 x i32> %113, %111
  %115 = bitcast <4 x i32> %114 to <2 x i64>
  %116 = trunc <2 x i64> %115 to <2 x i32>
  %117 = lshr <2 x i64> %115, splat (i64 32)
  %118 = trunc nuw <2 x i64> %117 to <2 x i32>
  %119 = getelementptr inbounds nuw <2 x i64>, ptr %0, i64 %108
  %120 = load <2 x i64>, ptr %119, align 16, !tbaa !21, !alias.scope !342, !noalias !351
  %121 = bitcast <4 x i32> %111 to <2 x i64>
  %122 = add <2 x i64> %120, %121
  %123 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %116, <2 x i32> %118)
  %124 = add <2 x i64> %122, %123
  store <2 x i64> %124, ptr %119, align 16, !tbaa !21, !alias.scope !342, !noalias !351
  %125 = add nuw nsw i64 %108, 1
  %126 = icmp eq i64 %125, 4
  br i1 %126, label %127, label %107, !llvm.loop !82

127:                                              ; preds = %107
  %128 = add nuw i64 %102, 1
  %129 = icmp eq i64 %128, %99
  br i1 %129, label %130, label %101, !llvm.loop !83

130:                                              ; preds = %127, %96
  %131 = trunc nuw nsw i64 %99 to i32
  br label %164

132:                                              ; preds = %23, %158
  %133 = phi i64 [ %159, %158 ], [ 0, %23 ]
  %134 = shl nuw nsw i64 %133, 6
  %135 = getelementptr inbounds nuw i8, ptr %26, i64 %134
  %136 = shl nuw nsw i64 %133, 3
  %137 = getelementptr inbounds nuw i8, ptr %43, i64 %136
  tail call void @llvm.experimental.noalias.scope.decl(metadata !352)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !355)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !357)
  br label %138

138:                                              ; preds = %132, %138
  %139 = phi i64 [ 0, %132 ], [ %156, %138 ]
  %140 = shl nuw nsw i64 %139, 2
  %141 = getelementptr inbounds nuw i32, ptr %135, i64 %140
  %142 = load <4 x i32>, ptr %141, align 4, !alias.scope !355, !noalias !359
  %143 = getelementptr inbounds nuw i32, ptr %137, i64 %140
  %144 = load <4 x i32>, ptr %143, align 4, !alias.scope !357, !noalias !360
  %145 = xor <4 x i32> %144, %142
  %146 = bitcast <4 x i32> %145 to <2 x i64>
  %147 = trunc <2 x i64> %146 to <2 x i32>
  %148 = lshr <2 x i64> %146, splat (i64 32)
  %149 = trunc nuw <2 x i64> %148 to <2 x i32>
  %150 = getelementptr inbounds nuw <2 x i64>, ptr %0, i64 %139
  %151 = load <2 x i64>, ptr %150, align 16, !tbaa !21, !alias.scope !352, !noalias !361
  %152 = bitcast <4 x i32> %142 to <2 x i64>
  %153 = add <2 x i64> %151, %152
  %154 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %147, <2 x i32> %149)
  %155 = add <2 x i64> %153, %154
  store <2 x i64> %155, ptr %150, align 16, !tbaa !21, !alias.scope !352, !noalias !361
  %156 = add nuw nsw i64 %139, 1
  %157 = icmp eq i64 %156, 4
  br i1 %157, label %158, label %138, !llvm.loop !82

158:                                              ; preds = %138
  %159 = add nuw nsw i64 %133, 1
  %160 = icmp eq i64 %159, 4
  br i1 %160, label %161, label %132, !llvm.loop !83

161:                                              ; preds = %158
  %162 = load i32, ptr %29, align 4, !tbaa !5
  %163 = add i32 %162, 4
  br label %164

164:                                              ; preds = %130, %161
  %165 = phi i32 [ %163, %161 ], [ %131, %130 ]
  store i32 %165, ptr %29, align 4, !tbaa !5
  store i32 0, ptr %10, align 8, !tbaa !326
  br label %166

166:                                              ; preds = %164, %21
  %167 = phi ptr [ %28, %164 ], [ %1, %21 ]
  %168 = getelementptr inbounds nuw i8, ptr %167, i64 256
  %169 = icmp ugt ptr %168, %6
  br i1 %169, label %313, label %170

170:                                              ; preds = %166
  %171 = getelementptr inbounds i8, ptr %6, i64 -256
  %172 = getelementptr inbounds nuw i8, ptr %0, i64 528
  %173 = getelementptr inbounds nuw i8, ptr %0, i64 524
  %174 = getelementptr inbounds nuw i8, ptr %0, i64 512
  %175 = getelementptr inbounds nuw i8, ptr %0, i64 540
  br label %176

176:                                              ; preds = %309, %170
  %177 = phi ptr [ %167, %170 ], [ %311, %309 ]
  %178 = load i32, ptr %173, align 4, !tbaa !324
  %179 = load ptr, ptr %174, align 16, !tbaa !322
  %180 = load i32, ptr %175, align 4, !tbaa !323
  %181 = zext i32 %180 to i64
  %182 = load i32, ptr %172, align 4, !tbaa !5
  %183 = sub i32 %178, %182
  %184 = zext i32 %183 to i64
  %185 = icmp ugt i32 %183, 4
  %186 = shl i32 %182, 3
  %187 = zext i32 %186 to i64
  %188 = getelementptr inbounds nuw i8, ptr %179, i64 %187
  br i1 %185, label %277, label %189

189:                                              ; preds = %176
  %190 = icmp eq i32 %178, %182
  br i1 %190, label %220, label %191

191:                                              ; preds = %189, %217
  %192 = phi i64 [ %218, %217 ], [ 0, %189 ]
  %193 = shl i64 %192, 6
  %194 = getelementptr inbounds nuw i8, ptr %177, i64 %193
  %195 = shl i64 %192, 3
  %196 = getelementptr inbounds nuw i8, ptr %188, i64 %195
  tail call void @llvm.experimental.noalias.scope.decl(metadata !362)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !365)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !367)
  br label %197

197:                                              ; preds = %191, %197
  %198 = phi i64 [ 0, %191 ], [ %215, %197 ]
  %199 = shl nuw nsw i64 %198, 2
  %200 = getelementptr inbounds nuw i32, ptr %194, i64 %199
  %201 = load <4 x i32>, ptr %200, align 4, !alias.scope !365, !noalias !369
  %202 = getelementptr inbounds nuw i32, ptr %196, i64 %199
  %203 = load <4 x i32>, ptr %202, align 4, !alias.scope !367, !noalias !370
  %204 = xor <4 x i32> %203, %201
  %205 = bitcast <4 x i32> %204 to <2 x i64>
  %206 = trunc <2 x i64> %205 to <2 x i32>
  %207 = lshr <2 x i64> %205, splat (i64 32)
  %208 = trunc nuw <2 x i64> %207 to <2 x i32>
  %209 = getelementptr inbounds nuw <2 x i64>, ptr %0, i64 %198
  %210 = load <2 x i64>, ptr %209, align 16, !tbaa !21, !alias.scope !362, !noalias !371
  %211 = bitcast <4 x i32> %201 to <2 x i64>
  %212 = add <2 x i64> %210, %211
  %213 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %206, <2 x i32> %208)
  %214 = add <2 x i64> %212, %213
  store <2 x i64> %214, ptr %209, align 16, !tbaa !21, !alias.scope !362, !noalias !371
  %215 = add nuw nsw i64 %198, 1
  %216 = icmp eq i64 %215, 4
  br i1 %216, label %217, label %197, !llvm.loop !82

217:                                              ; preds = %197
  %218 = add nuw nsw i64 %192, 1
  %219 = icmp eq i64 %218, %184
  br i1 %219, label %220, label %191, !llvm.loop !83

220:                                              ; preds = %217, %189
  %221 = getelementptr inbounds nuw i8, ptr %179, i64 %181
  tail call void @llvm.experimental.noalias.scope.decl(metadata !372)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !375)
  br label %222

222:                                              ; preds = %220, %222
  %223 = phi i64 [ 0, %220 ], [ %239, %222 ]
  %224 = getelementptr inbounds nuw <2 x i64>, ptr %0, i64 %223
  %225 = load <2 x i64>, ptr %224, align 16, !tbaa !21, !alias.scope !372, !noalias !375
  %226 = lshr <2 x i64> %225, splat (i64 47)
  %227 = xor <2 x i64> %226, %225
  %228 = shl nuw nsw i64 %223, 4
  %229 = getelementptr inbounds nuw i8, ptr %221, i64 %228
  %230 = load <4 x i32>, ptr %229, align 4, !alias.scope !375, !noalias !372
  %231 = bitcast <2 x i64> %227 to <4 x i32>
  %232 = xor <4 x i32> %230, %231
  %233 = shufflevector <4 x i32> %232, <4 x i32> poison, <2 x i32> <i32 0, i32 2>
  %234 = shufflevector <4 x i32> %232, <4 x i32> poison, <2 x i32> <i32 1, i32 3>
  %235 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %234, <2 x i32> splat (i32 -1640531535))
  %236 = shl <2 x i64> %235, splat (i64 32)
  %237 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %233, <2 x i32> splat (i32 -1640531535))
  %238 = add <2 x i64> %236, %237
  store <2 x i64> %238, ptr %224, align 16, !tbaa !21, !alias.scope !372, !noalias !375
  %239 = add nuw nsw i64 %223, 1
  %240 = icmp eq i64 %239, 4
  br i1 %240, label %241, label %222, !llvm.loop !89

241:                                              ; preds = %222
  %242 = shl nuw nsw i64 %184, 6
  %243 = getelementptr inbounds nuw i8, ptr %177, i64 %242
  %244 = sub nsw i64 4, %184
  %245 = icmp eq i32 %183, 4
  br i1 %245, label %275, label %246

246:                                              ; preds = %241, %272
  %247 = phi i64 [ %273, %272 ], [ 0, %241 ]
  %248 = shl i64 %247, 6
  %249 = getelementptr inbounds nuw i8, ptr %243, i64 %248
  %250 = shl i64 %247, 3
  %251 = getelementptr inbounds nuw i8, ptr %179, i64 %250
  tail call void @llvm.experimental.noalias.scope.decl(metadata !377)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !380)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !382)
  br label %252

252:                                              ; preds = %246, %252
  %253 = phi i64 [ 0, %246 ], [ %270, %252 ]
  %254 = shl nuw nsw i64 %253, 2
  %255 = getelementptr inbounds nuw i32, ptr %249, i64 %254
  %256 = load <4 x i32>, ptr %255, align 4, !alias.scope !380, !noalias !384
  %257 = getelementptr inbounds nuw i32, ptr %251, i64 %254
  %258 = load <4 x i32>, ptr %257, align 4, !alias.scope !382, !noalias !385
  %259 = xor <4 x i32> %258, %256
  %260 = bitcast <4 x i32> %259 to <2 x i64>
  %261 = trunc <2 x i64> %260 to <2 x i32>
  %262 = lshr <2 x i64> %260, splat (i64 32)
  %263 = trunc nuw <2 x i64> %262 to <2 x i32>
  %264 = getelementptr inbounds nuw <2 x i64>, ptr %0, i64 %253
  %265 = load <2 x i64>, ptr %264, align 16, !tbaa !21, !alias.scope !377, !noalias !386
  %266 = bitcast <4 x i32> %256 to <2 x i64>
  %267 = add <2 x i64> %265, %266
  %268 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %261, <2 x i32> %263)
  %269 = add <2 x i64> %267, %268
  store <2 x i64> %269, ptr %264, align 16, !tbaa !21, !alias.scope !377, !noalias !386
  %270 = add nuw nsw i64 %253, 1
  %271 = icmp eq i64 %270, 4
  br i1 %271, label %272, label %252, !llvm.loop !82

272:                                              ; preds = %252
  %273 = add nuw i64 %247, 1
  %274 = icmp eq i64 %273, %244
  br i1 %274, label %275, label %246, !llvm.loop !83

275:                                              ; preds = %272, %241
  %276 = trunc nuw nsw i64 %244 to i32
  br label %309

277:                                              ; preds = %176, %303
  %278 = phi i64 [ %304, %303 ], [ 0, %176 ]
  %279 = shl nuw nsw i64 %278, 6
  %280 = getelementptr inbounds nuw i8, ptr %177, i64 %279
  %281 = shl nuw nsw i64 %278, 3
  %282 = getelementptr inbounds nuw i8, ptr %188, i64 %281
  tail call void @llvm.experimental.noalias.scope.decl(metadata !387)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !390)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !392)
  br label %283

283:                                              ; preds = %277, %283
  %284 = phi i64 [ 0, %277 ], [ %301, %283 ]
  %285 = shl nuw nsw i64 %284, 2
  %286 = getelementptr inbounds nuw i32, ptr %280, i64 %285
  %287 = load <4 x i32>, ptr %286, align 4, !alias.scope !390, !noalias !394
  %288 = getelementptr inbounds nuw i32, ptr %282, i64 %285
  %289 = load <4 x i32>, ptr %288, align 4, !alias.scope !392, !noalias !395
  %290 = xor <4 x i32> %289, %287
  %291 = bitcast <4 x i32> %290 to <2 x i64>
  %292 = trunc <2 x i64> %291 to <2 x i32>
  %293 = lshr <2 x i64> %291, splat (i64 32)
  %294 = trunc nuw <2 x i64> %293 to <2 x i32>
  %295 = getelementptr inbounds nuw <2 x i64>, ptr %0, i64 %284
  %296 = load <2 x i64>, ptr %295, align 16, !tbaa !21, !alias.scope !387, !noalias !396
  %297 = bitcast <4 x i32> %287 to <2 x i64>
  %298 = add <2 x i64> %296, %297
  %299 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %292, <2 x i32> %294)
  %300 = add <2 x i64> %298, %299
  store <2 x i64> %300, ptr %295, align 16, !tbaa !21, !alias.scope !387, !noalias !396
  %301 = add nuw nsw i64 %284, 1
  %302 = icmp eq i64 %301, 4
  br i1 %302, label %303, label %283, !llvm.loop !82

303:                                              ; preds = %283
  %304 = add nuw nsw i64 %278, 1
  %305 = icmp eq i64 %304, 4
  br i1 %305, label %306, label %277, !llvm.loop !83

306:                                              ; preds = %303
  %307 = load i32, ptr %172, align 4, !tbaa !5
  %308 = add i32 %307, 4
  br label %309

309:                                              ; preds = %275, %306
  %310 = phi i32 [ %308, %306 ], [ %276, %275 ]
  store i32 %310, ptr %172, align 4, !tbaa !5
  %311 = getelementptr inbounds nuw i8, ptr %177, i64 256
  %312 = icmp ugt ptr %311, %171
  br i1 %312, label %313, label %176, !llvm.loop !397

313:                                              ; preds = %309, %166
  %314 = phi ptr [ %167, %166 ], [ %311, %309 ]
  %315 = icmp ult ptr %314, %6
  br i1 %315, label %316, label %324

316:                                              ; preds = %313
  %317 = getelementptr inbounds nuw i8, ptr %0, i64 256
  %318 = ptrtoint ptr %6 to i64
  %319 = ptrtoint ptr %314 to i64
  %320 = sub i64 %318, %319
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %317, ptr noundef nonnull readonly align 1 %314, i64 noundef %320, i1 noundef false) #24
  %321 = trunc i64 %320 to i32
  br label %322

322:                                              ; preds = %316, %15
  %323 = phi i32 [ %20, %15 ], [ %321, %316 ]
  store i32 %323, ptr %10, align 8, !tbaa !326
  br label %324

324:                                              ; preds = %322, %3, %313
  %325 = phi i32 [ 1, %3 ], [ 0, %313 ], [ 0, %322 ]
  ret i32 %325
}

; Function Attrs: nofree norecurse nounwind ssp memory(read, argmem: readwrite, inaccessiblemem: readwrite) uwtable(sync)
define i64 @XXH3_64bits_digest(ptr noundef readonly captures(none) %0) local_unnamed_addr #15 {
  %2 = alloca [64 x i8], align 1
  %3 = alloca [8 x i64], align 16
  %4 = getelementptr inbounds nuw i8, ptr %0, i64 544
  %5 = load i64, ptr %4, align 16, !tbaa !325
  %6 = icmp ugt i64 %5, 240
  br i1 %6, label %7, label %289

7:                                                ; preds = %1
  call void @llvm.lifetime.start.p0(i64 64, ptr nonnull %3) #24
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(64) %3, ptr noundef nonnull align 1 dereferenceable(64) %0, i64 noundef 64, i1 noundef false) #24
  %8 = getelementptr inbounds nuw i8, ptr %0, i64 520
  %9 = load i32, ptr %8, align 8, !tbaa !326
  %10 = icmp ugt i32 %9, 63
  br i1 %10, label %11, label %174

11:                                               ; preds = %7
  %12 = lshr i32 %9, 6
  %13 = zext nneg i32 %12 to i64
  %14 = getelementptr inbounds nuw i8, ptr %0, i64 528
  %15 = load i32, ptr %14, align 16, !tbaa !398
  %16 = getelementptr inbounds nuw i8, ptr %0, i64 524
  %17 = load i32, ptr %16, align 4, !tbaa !324
  %18 = getelementptr inbounds nuw i8, ptr %0, i64 256
  %19 = getelementptr inbounds nuw i8, ptr %0, i64 512
  %20 = load ptr, ptr %19, align 16, !tbaa !322
  %21 = getelementptr inbounds nuw i8, ptr %0, i64 540
  %22 = load i32, ptr %21, align 4, !tbaa !323
  %23 = zext i32 %22 to i64
  %24 = sub i32 %17, %15
  %25 = zext i32 %24 to i64
  %26 = icmp ult i32 %12, %24
  %27 = shl i32 %15, 3
  %28 = zext i32 %27 to i64
  %29 = getelementptr inbounds nuw i8, ptr %20, i64 %28
  br i1 %26, label %116, label %30

30:                                               ; preds = %11
  %31 = icmp eq i32 %17, %15
  br i1 %31, label %61, label %32

32:                                               ; preds = %30, %58
  %33 = phi i64 [ %59, %58 ], [ 0, %30 ]
  %34 = shl i64 %33, 6
  %35 = getelementptr inbounds nuw i8, ptr %18, i64 %34
  %36 = shl i64 %33, 3
  %37 = getelementptr inbounds nuw i8, ptr %29, i64 %36
  tail call void @llvm.experimental.noalias.scope.decl(metadata !399)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !402)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !404)
  br label %38

38:                                               ; preds = %32, %38
  %39 = phi i64 [ 0, %32 ], [ %56, %38 ]
  %40 = shl nuw nsw i64 %39, 2
  %41 = getelementptr inbounds nuw i32, ptr %35, i64 %40
  %42 = load <4 x i32>, ptr %41, align 4, !alias.scope !402, !noalias !406
  %43 = getelementptr inbounds nuw i32, ptr %37, i64 %40
  %44 = load <4 x i32>, ptr %43, align 4, !alias.scope !404, !noalias !407
  %45 = xor <4 x i32> %44, %42
  %46 = bitcast <4 x i32> %45 to <2 x i64>
  %47 = trunc <2 x i64> %46 to <2 x i32>
  %48 = lshr <2 x i64> %46, splat (i64 32)
  %49 = trunc nuw <2 x i64> %48 to <2 x i32>
  %50 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %39
  %51 = load <2 x i64>, ptr %50, align 16, !tbaa !21, !alias.scope !399, !noalias !408
  %52 = bitcast <4 x i32> %42 to <2 x i64>
  %53 = add <2 x i64> %51, %52
  %54 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %47, <2 x i32> %49)
  %55 = add <2 x i64> %53, %54
  store <2 x i64> %55, ptr %50, align 16, !tbaa !21, !alias.scope !399, !noalias !408
  %56 = add nuw nsw i64 %39, 1
  %57 = icmp eq i64 %56, 4
  br i1 %57, label %58, label %38, !llvm.loop !82

58:                                               ; preds = %38
  %59 = add nuw nsw i64 %33, 1
  %60 = icmp eq i64 %59, %25
  br i1 %60, label %61, label %32, !llvm.loop !83

61:                                               ; preds = %58, %30
  %62 = getelementptr inbounds nuw i8, ptr %20, i64 %23
  tail call void @llvm.experimental.noalias.scope.decl(metadata !409)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !412)
  br label %63

63:                                               ; preds = %61, %63
  %64 = phi i64 [ 0, %61 ], [ %80, %63 ]
  %65 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %64
  %66 = load <2 x i64>, ptr %65, align 16, !tbaa !21, !alias.scope !409, !noalias !412
  %67 = lshr <2 x i64> %66, splat (i64 47)
  %68 = xor <2 x i64> %67, %66
  %69 = shl nuw nsw i64 %64, 4
  %70 = getelementptr inbounds nuw i8, ptr %62, i64 %69
  %71 = load <4 x i32>, ptr %70, align 4, !alias.scope !412, !noalias !409
  %72 = bitcast <2 x i64> %68 to <4 x i32>
  %73 = xor <4 x i32> %71, %72
  %74 = shufflevector <4 x i32> %73, <4 x i32> poison, <2 x i32> <i32 0, i32 2>
  %75 = shufflevector <4 x i32> %73, <4 x i32> poison, <2 x i32> <i32 1, i32 3>
  %76 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %75, <2 x i32> splat (i32 -1640531535))
  %77 = shl <2 x i64> %76, splat (i64 32)
  %78 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %74, <2 x i32> splat (i32 -1640531535))
  %79 = add <2 x i64> %77, %78
  store <2 x i64> %79, ptr %65, align 16, !tbaa !21, !alias.scope !409, !noalias !412
  %80 = add nuw nsw i64 %64, 1
  %81 = icmp eq i64 %80, 4
  br i1 %81, label %82, label %63, !llvm.loop !89

82:                                               ; preds = %63
  %83 = shl nuw nsw i64 %25, 6
  %84 = getelementptr inbounds nuw i8, ptr %18, i64 %83
  %85 = sub nsw i64 %13, %25
  %86 = icmp eq i32 %12, %24
  br i1 %86, label %145, label %87

87:                                               ; preds = %82, %113
  %88 = phi i64 [ %114, %113 ], [ 0, %82 ]
  %89 = shl i64 %88, 6
  %90 = getelementptr inbounds nuw i8, ptr %84, i64 %89
  %91 = shl i64 %88, 3
  %92 = getelementptr inbounds nuw i8, ptr %20, i64 %91
  tail call void @llvm.experimental.noalias.scope.decl(metadata !414)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !417)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !419)
  br label %93

93:                                               ; preds = %87, %93
  %94 = phi i64 [ 0, %87 ], [ %111, %93 ]
  %95 = shl nuw nsw i64 %94, 2
  %96 = getelementptr inbounds nuw i32, ptr %90, i64 %95
  %97 = load <4 x i32>, ptr %96, align 4, !alias.scope !417, !noalias !421
  %98 = getelementptr inbounds nuw i32, ptr %92, i64 %95
  %99 = load <4 x i32>, ptr %98, align 4, !alias.scope !419, !noalias !422
  %100 = xor <4 x i32> %99, %97
  %101 = bitcast <4 x i32> %100 to <2 x i64>
  %102 = trunc <2 x i64> %101 to <2 x i32>
  %103 = lshr <2 x i64> %101, splat (i64 32)
  %104 = trunc nuw <2 x i64> %103 to <2 x i32>
  %105 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %94
  %106 = load <2 x i64>, ptr %105, align 16, !tbaa !21, !alias.scope !414, !noalias !423
  %107 = bitcast <4 x i32> %97 to <2 x i64>
  %108 = add <2 x i64> %106, %107
  %109 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %102, <2 x i32> %104)
  %110 = add <2 x i64> %108, %109
  store <2 x i64> %110, ptr %105, align 16, !tbaa !21, !alias.scope !414, !noalias !423
  %111 = add nuw nsw i64 %94, 1
  %112 = icmp eq i64 %111, 4
  br i1 %112, label %113, label %93, !llvm.loop !82

113:                                              ; preds = %93
  %114 = add nuw i64 %88, 1
  %115 = icmp eq i64 %114, %85
  br i1 %115, label %145, label %87, !llvm.loop !83

116:                                              ; preds = %11, %142
  %117 = phi i64 [ %143, %142 ], [ 0, %11 ]
  %118 = shl i64 %117, 6
  %119 = getelementptr inbounds nuw i8, ptr %18, i64 %118
  %120 = shl i64 %117, 3
  %121 = getelementptr inbounds nuw i8, ptr %29, i64 %120
  tail call void @llvm.experimental.noalias.scope.decl(metadata !424)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !427)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !429)
  br label %122

122:                                              ; preds = %116, %122
  %123 = phi i64 [ 0, %116 ], [ %140, %122 ]
  %124 = shl nuw nsw i64 %123, 2
  %125 = getelementptr inbounds nuw i32, ptr %119, i64 %124
  %126 = load <4 x i32>, ptr %125, align 4, !alias.scope !427, !noalias !431
  %127 = getelementptr inbounds nuw i32, ptr %121, i64 %124
  %128 = load <4 x i32>, ptr %127, align 4, !alias.scope !429, !noalias !432
  %129 = xor <4 x i32> %128, %126
  %130 = bitcast <4 x i32> %129 to <2 x i64>
  %131 = trunc <2 x i64> %130 to <2 x i32>
  %132 = lshr <2 x i64> %130, splat (i64 32)
  %133 = trunc nuw <2 x i64> %132 to <2 x i32>
  %134 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %123
  %135 = load <2 x i64>, ptr %134, align 16, !tbaa !21, !alias.scope !424, !noalias !433
  %136 = bitcast <4 x i32> %126 to <2 x i64>
  %137 = add <2 x i64> %135, %136
  %138 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %131, <2 x i32> %133)
  %139 = add <2 x i64> %137, %138
  store <2 x i64> %139, ptr %134, align 16, !tbaa !21, !alias.scope !424, !noalias !433
  %140 = add nuw nsw i64 %123, 1
  %141 = icmp eq i64 %140, 4
  br i1 %141, label %142, label %122, !llvm.loop !82

142:                                              ; preds = %122
  %143 = add nuw nsw i64 %117, 1
  %144 = icmp eq i64 %143, %13
  br i1 %144, label %145, label %116, !llvm.loop !83

145:                                              ; preds = %113, %142, %82
  %146 = and i32 %9, 63
  %147 = icmp eq i32 %146, 0
  br i1 %147, label %213, label %148

148:                                              ; preds = %145
  %149 = zext i32 %9 to i64
  %150 = getelementptr inbounds nuw i8, ptr %18, i64 %149
  %151 = getelementptr inbounds i8, ptr %150, i64 -64
  %152 = getelementptr inbounds nuw i8, ptr %20, i64 %23
  %153 = getelementptr inbounds i8, ptr %152, i64 -7
  tail call void @llvm.experimental.noalias.scope.decl(metadata !434)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !437)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !439)
  br label %154

154:                                              ; preds = %148, %154
  %155 = phi i64 [ 0, %148 ], [ %172, %154 ]
  %156 = shl nuw nsw i64 %155, 2
  %157 = getelementptr inbounds nuw i32, ptr %151, i64 %156
  %158 = load <4 x i32>, ptr %157, align 4, !alias.scope !437, !noalias !441
  %159 = getelementptr inbounds nuw i32, ptr %153, i64 %156
  %160 = load <4 x i32>, ptr %159, align 4, !alias.scope !439, !noalias !442
  %161 = xor <4 x i32> %160, %158
  %162 = bitcast <4 x i32> %161 to <2 x i64>
  %163 = trunc <2 x i64> %162 to <2 x i32>
  %164 = lshr <2 x i64> %162, splat (i64 32)
  %165 = trunc nuw <2 x i64> %164 to <2 x i32>
  %166 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %155
  %167 = load <2 x i64>, ptr %166, align 16, !tbaa !21, !alias.scope !434, !noalias !443
  %168 = bitcast <4 x i32> %158 to <2 x i64>
  %169 = add <2 x i64> %167, %168
  %170 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %163, <2 x i32> %165)
  %171 = add <2 x i64> %169, %170
  store <2 x i64> %171, ptr %166, align 16, !tbaa !21, !alias.scope !434, !noalias !443
  %172 = add nuw nsw i64 %155, 1
  %173 = icmp eq i64 %172, 4
  br i1 %173, label %213, label %154, !llvm.loop !82

174:                                              ; preds = %7
  %175 = icmp eq i32 %9, 0
  br i1 %175, label %213, label %176

176:                                              ; preds = %174
  call void @llvm.lifetime.start.p0(i64 64, ptr nonnull %2) #24
  %177 = sub nuw nsw i32 64, %9
  %178 = zext nneg i32 %177 to i64
  %179 = getelementptr inbounds nuw i8, ptr %0, i64 256
  %180 = getelementptr inbounds nuw i8, ptr %0, i64 512
  %181 = sub nsw i64 0, %178
  %182 = getelementptr inbounds i8, ptr %180, i64 %181
  %183 = call ptr @__memcpy_chk(ptr noundef nonnull %2, ptr noundef nonnull %182, i64 noundef %178, i64 noundef 64) #24
  %184 = getelementptr inbounds nuw i8, ptr %2, i64 %178
  %185 = zext nneg i32 %9 to i64
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %184, ptr noundef nonnull align 1 %179, i64 noundef %185, i1 noundef false) #24
  %186 = load ptr, ptr %180, align 16, !tbaa !322
  %187 = getelementptr inbounds nuw i8, ptr %0, i64 540
  %188 = load i32, ptr %187, align 4, !tbaa !323
  %189 = zext i32 %188 to i64
  %190 = getelementptr inbounds nuw i8, ptr %186, i64 %189
  %191 = getelementptr inbounds i8, ptr %190, i64 -7
  call void @llvm.experimental.noalias.scope.decl(metadata !444)
  call void @llvm.experimental.noalias.scope.decl(metadata !447)
  call void @llvm.experimental.noalias.scope.decl(metadata !449)
  br label %192

192:                                              ; preds = %176, %192
  %193 = phi i64 [ 0, %176 ], [ %210, %192 ]
  %194 = shl nuw nsw i64 %193, 2
  %195 = getelementptr inbounds nuw i32, ptr %2, i64 %194
  %196 = load <4 x i32>, ptr %195, align 4, !alias.scope !447, !noalias !451
  %197 = getelementptr inbounds nuw i32, ptr %191, i64 %194
  %198 = load <4 x i32>, ptr %197, align 4, !alias.scope !449, !noalias !452
  %199 = xor <4 x i32> %198, %196
  %200 = bitcast <4 x i32> %199 to <2 x i64>
  %201 = trunc <2 x i64> %200 to <2 x i32>
  %202 = lshr <2 x i64> %200, splat (i64 32)
  %203 = trunc nuw <2 x i64> %202 to <2 x i32>
  %204 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %193
  %205 = load <2 x i64>, ptr %204, align 16, !tbaa !21, !alias.scope !444, !noalias !453
  %206 = bitcast <4 x i32> %196 to <2 x i64>
  %207 = add <2 x i64> %205, %206
  %208 = call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %201, <2 x i32> %203)
  %209 = add <2 x i64> %207, %208
  store <2 x i64> %209, ptr %204, align 16, !tbaa !21, !alias.scope !444, !noalias !453
  %210 = add nuw nsw i64 %193, 1
  %211 = icmp eq i64 %210, 4
  br i1 %211, label %212, label %192, !llvm.loop !82

212:                                              ; preds = %192
  call void @llvm.lifetime.end.p0(i64 64, ptr nonnull %2) #24
  br label %213

213:                                              ; preds = %154, %145, %174, %212
  %214 = getelementptr inbounds nuw i8, ptr %0, i64 512
  %215 = load ptr, ptr %214, align 16, !tbaa !322
  %216 = getelementptr inbounds nuw i8, ptr %215, i64 11
  %217 = mul i64 %5, -7046029288634856825
  call void @llvm.experimental.noalias.scope.decl(metadata !454)
  call void @llvm.experimental.noalias.scope.decl(metadata !457)
  call void @llvm.experimental.noalias.scope.decl(metadata !459)
  %218 = load i64, ptr %3, align 16, !tbaa !22, !alias.scope !462, !noalias !463
  %219 = load i64, ptr %216, align 1, !alias.scope !457, !noalias !462
  %220 = xor i64 %219, %218
  %221 = getelementptr inbounds nuw i8, ptr %3, i64 8
  %222 = load i64, ptr %221, align 8, !tbaa !22, !alias.scope !462, !noalias !463
  %223 = getelementptr inbounds nuw i8, ptr %215, i64 19
  %224 = load i64, ptr %223, align 1, !alias.scope !457, !noalias !462
  %225 = xor i64 %224, %222
  %226 = zext i64 %220 to i128
  %227 = zext i64 %225 to i128
  %228 = mul nuw i128 %227, %226
  %229 = lshr i128 %228, 64
  %230 = xor i128 %229, %228
  %231 = trunc i128 %230 to i64
  %232 = add i64 %217, %231
  %233 = getelementptr inbounds nuw i8, ptr %3, i64 16
  %234 = getelementptr inbounds nuw i8, ptr %215, i64 27
  call void @llvm.experimental.noalias.scope.decl(metadata !465)
  %235 = load i64, ptr %233, align 16, !tbaa !22, !alias.scope !468, !noalias !469
  %236 = load i64, ptr %234, align 1, !alias.scope !457, !noalias !468
  %237 = xor i64 %236, %235
  %238 = getelementptr inbounds nuw i8, ptr %3, i64 24
  %239 = load i64, ptr %238, align 8, !tbaa !22, !alias.scope !468, !noalias !469
  %240 = getelementptr inbounds nuw i8, ptr %215, i64 35
  %241 = load i64, ptr %240, align 1, !alias.scope !457, !noalias !468
  %242 = xor i64 %241, %239
  %243 = zext i64 %237 to i128
  %244 = zext i64 %242 to i128
  %245 = mul nuw i128 %244, %243
  %246 = lshr i128 %245, 64
  %247 = xor i128 %246, %245
  %248 = trunc i128 %247 to i64
  %249 = add i64 %232, %248
  %250 = getelementptr inbounds nuw i8, ptr %3, i64 32
  %251 = getelementptr inbounds nuw i8, ptr %215, i64 43
  call void @llvm.experimental.noalias.scope.decl(metadata !471)
  %252 = load i64, ptr %250, align 16, !tbaa !22, !alias.scope !474, !noalias !475
  %253 = load i64, ptr %251, align 1, !alias.scope !457, !noalias !474
  %254 = xor i64 %253, %252
  %255 = getelementptr inbounds nuw i8, ptr %3, i64 40
  %256 = load i64, ptr %255, align 8, !tbaa !22, !alias.scope !474, !noalias !475
  %257 = getelementptr inbounds nuw i8, ptr %215, i64 51
  %258 = load i64, ptr %257, align 1, !alias.scope !457, !noalias !474
  %259 = xor i64 %258, %256
  %260 = zext i64 %254 to i128
  %261 = zext i64 %259 to i128
  %262 = mul nuw i128 %261, %260
  %263 = lshr i128 %262, 64
  %264 = xor i128 %263, %262
  %265 = trunc i128 %264 to i64
  %266 = add i64 %249, %265
  %267 = getelementptr inbounds nuw i8, ptr %3, i64 48
  %268 = getelementptr inbounds nuw i8, ptr %215, i64 59
  call void @llvm.experimental.noalias.scope.decl(metadata !477)
  %269 = load i64, ptr %267, align 16, !tbaa !22, !alias.scope !480, !noalias !481
  %270 = load i64, ptr %268, align 1, !alias.scope !457, !noalias !480
  %271 = xor i64 %270, %269
  %272 = getelementptr inbounds nuw i8, ptr %3, i64 56
  %273 = load i64, ptr %272, align 8, !tbaa !22, !alias.scope !480, !noalias !481
  %274 = getelementptr inbounds nuw i8, ptr %215, i64 67
  %275 = load i64, ptr %274, align 1, !alias.scope !457, !noalias !480
  %276 = xor i64 %275, %273
  %277 = zext i64 %271 to i128
  %278 = zext i64 %276 to i128
  %279 = mul nuw i128 %278, %277
  %280 = lshr i128 %279, 64
  %281 = xor i128 %280, %279
  %282 = trunc i128 %281 to i64
  %283 = add i64 %266, %282
  %284 = lshr i64 %283, 37
  %285 = xor i64 %284, %283
  %286 = mul i64 %285, 1609587929392839161
  %287 = lshr i64 %286, 32
  %288 = xor i64 %287, %286
  call void @llvm.lifetime.end.p0(i64 64, ptr nonnull %3) #24
  br label %304

289:                                              ; preds = %1
  %290 = getelementptr inbounds nuw i8, ptr %0, i64 552
  %291 = load i64, ptr %290, align 8, !tbaa !319
  %292 = icmp eq i64 %291, 0
  %293 = getelementptr inbounds nuw i8, ptr %0, i64 256
  br i1 %292, label %296, label %294

294:                                              ; preds = %289
  %295 = tail call i64 @XXH3_64bits_withSeed(ptr noundef nonnull %293, i64 noundef %5, i64 noundef %291)
  br label %304

296:                                              ; preds = %289
  %297 = getelementptr inbounds nuw i8, ptr %0, i64 512
  %298 = load ptr, ptr %297, align 16, !tbaa !322
  %299 = getelementptr inbounds nuw i8, ptr %0, i64 540
  %300 = load i32, ptr %299, align 4, !tbaa !323
  %301 = add i32 %300, 64
  %302 = zext i32 %301 to i64
  %303 = tail call i64 @XXH3_64bits_withSecret(ptr noundef nonnull %293, i64 noundef %5, ptr noundef %298, i64 noundef %302)
  br label %304

304:                                              ; preds = %296, %294, %213
  %305 = phi i64 [ %288, %213 ], [ %295, %294 ], [ %303, %296 ]
  ret i64 %305
}

; Function Attrs: nofree norecurse nosync nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync)
define [2 x i64] @XXH3_128bits(ptr noundef readonly captures(none) %0, i64 noundef %1) local_unnamed_addr #10 {
  %3 = icmp ult i64 %1, 17
  br i1 %3, label %4, label %120

4:                                                ; preds = %2
  %5 = icmp samesign ugt i64 %1, 8
  br i1 %5, label %6, label %40

6:                                                ; preds = %4
  %7 = load i64, ptr %0, align 1
  %8 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %9 = getelementptr inbounds i8, ptr %8, i64 -8
  %10 = load i64, ptr %9, align 1
  %11 = xor i64 %10, 2066345149520216444
  %12 = xor i64 %7, %11
  %13 = xor i64 %12, -4734510112055689544
  %14 = zext i64 %13 to i128
  %15 = mul nuw i128 %14, 11400714785074694791
  %16 = trunc i128 %15 to i64
  %17 = lshr i128 %15, 64
  %18 = trunc nuw i128 %17 to i64
  %19 = mul i64 %11, -7046029288634856825
  %20 = add i64 %19, %18
  %21 = lshr i64 %20, 32
  %22 = xor i64 %21, %16
  %23 = zext i64 %22 to i128
  %24 = mul nuw i128 %23, 14029467366897019727
  %25 = trunc i128 %24 to i64
  %26 = lshr i128 %24, 64
  %27 = trunc nuw i128 %26 to i64
  %28 = mul i64 %20, -4417276706812531889
  %29 = add i64 %28, %27
  %30 = lshr i64 %25, 37
  %31 = xor i64 %30, %25
  %32 = mul i64 %31, 1609587929392839161
  %33 = lshr i64 %32, 32
  %34 = xor i64 %33, %32
  %35 = lshr i64 %29, 37
  %36 = xor i64 %35, %29
  %37 = mul i64 %36, 1609587929392839161
  %38 = lshr i64 %37, 32
  %39 = xor i64 %38, %37
  br label %115

40:                                               ; preds = %4
  %41 = icmp samesign ugt i64 %1, 3
  br i1 %41, label %42, label %78

42:                                               ; preds = %40
  %43 = load i32, ptr %0, align 1
  %44 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %45 = getelementptr inbounds i8, ptr %44, i64 -4
  %46 = load i32, ptr %45, align 1
  %47 = zext i32 %43 to i64
  %48 = zext i32 %46 to i64
  %49 = shl nuw i64 %48, 32
  %50 = or disjoint i64 %49, %47
  %51 = xor i64 %50, -4734510112055689544
  %52 = xor i64 %50, 8935565165804498204
  %53 = tail call i64 @llvm.bswap.i64(i64 %52)
  %54 = lshr i64 %51, 51
  %55 = xor i64 %54, %51
  %56 = mul i64 %55, 2654435761
  %57 = add i64 %56, %1
  %58 = lshr i64 %57, 47
  %59 = xor i64 %58, %57
  %60 = mul i64 %59, -4417276706812531889
  %61 = lshr i64 %53, 47
  %62 = xor i64 %61, %53
  %63 = mul i64 %62, -7046029288634856825
  %64 = sub i64 %63, %1
  %65 = lshr i64 %64, 43
  %66 = xor i64 %65, %64
  %67 = mul i64 %66, -8796714831421723037
  %68 = lshr i64 %60, 37
  %69 = xor i64 %68, %60
  %70 = mul i64 %69, 1609587929392839161
  %71 = lshr i64 %70, 32
  %72 = xor i64 %71, %70
  %73 = lshr i64 %67, 37
  %74 = xor i64 %73, %67
  %75 = mul i64 %74, 1609587929392839161
  %76 = lshr i64 %75, 32
  %77 = xor i64 %76, %75
  br label %115

78:                                               ; preds = %40
  %79 = icmp eq i64 %1, 0
  br i1 %79, label %115, label %80

80:                                               ; preds = %78
  %81 = load i8, ptr %0, align 1, !tbaa !21
  %82 = lshr i64 %1, 1
  %83 = getelementptr inbounds nuw i8, ptr %0, i64 %82
  %84 = load i8, ptr %83, align 1, !tbaa !21
  %85 = getelementptr i8, ptr %0, i64 %1
  %86 = getelementptr i8, ptr %85, i64 -1
  %87 = load i8, ptr %86, align 1, !tbaa !21
  %88 = zext i8 %81 to i32
  %89 = zext i8 %84 to i32
  %90 = shl nuw nsw i32 %89, 8
  %91 = or disjoint i32 %90, %88
  %92 = zext i8 %87 to i32
  %93 = shl nuw nsw i32 %92, 16
  %94 = or disjoint i32 %91, %93
  %95 = trunc nuw nsw i64 %1 to i32
  %96 = shl nuw nsw i32 %95, 24
  %97 = or disjoint i32 %94, %96
  %98 = xor i32 %97, 963444408
  %99 = zext nneg i32 %98 to i64
  %100 = xor i32 %97, 597969854
  %101 = tail call i32 @llvm.bswap.i32(i32 %100)
  %102 = zext i32 %101 to i64
  %103 = mul i64 %99, -7046029288634856825
  %104 = mul i64 %102, -4417276706812531889
  %105 = lshr i64 %103, 37
  %106 = xor i64 %105, %103
  %107 = mul i64 %106, 1609587929392839161
  %108 = lshr i64 %107, 32
  %109 = xor i64 %108, %107
  %110 = lshr i64 %104, 37
  %111 = xor i64 %110, %104
  %112 = mul i64 %111, 1609587929392839161
  %113 = lshr i64 %112, 32
  %114 = xor i64 %113, %112
  br label %115

115:                                              ; preds = %6, %42, %78, %80
  %116 = phi i64 [ %39, %6 ], [ %77, %42 ], [ %114, %80 ], [ 0, %78 ]
  %117 = phi i64 [ %34, %6 ], [ %72, %42 ], [ %109, %80 ], [ 0, %78 ]
  %118 = insertvalue [2 x i64] poison, i64 %117, 0
  %119 = insertvalue [2 x i64] %118, i64 %116, 1
  br label %270

120:                                              ; preds = %2
  %121 = icmp ult i64 %1, 129
  br i1 %121, label %122, label %264

122:                                              ; preds = %120
  %123 = mul i64 %1, -7046029288634856825
  %124 = icmp samesign ugt i64 %1, 32
  br i1 %124, label %125, label %216

125:                                              ; preds = %122
  %126 = icmp samesign ugt i64 %1, 64
  br i1 %126, label %127, label %186

127:                                              ; preds = %125
  %128 = icmp samesign ugt i64 %1, 96
  br i1 %128, label %129, label %156

129:                                              ; preds = %127
  %130 = getelementptr inbounds nuw i8, ptr %0, i64 48
  %131 = load i64, ptr %130, align 1, !noalias !483
  %132 = getelementptr inbounds nuw i8, ptr %0, i64 56
  %133 = load i64, ptr %132, align 1, !noalias !483
  %134 = xor i64 %131, 4554437623014685352
  %135 = xor i64 %133, 2111919702937427193
  %136 = zext i64 %134 to i128
  %137 = zext i64 %135 to i128
  %138 = mul nuw i128 %137, %136
  %139 = lshr i128 %138, 64
  %140 = xor i128 %139, %138
  %141 = trunc i128 %140 to i64
  %142 = add i64 %123, %141
  %143 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %144 = getelementptr inbounds i8, ptr %143, i64 -64
  %145 = load i64, ptr %144, align 1, !noalias !486
  %146 = getelementptr inbounds i8, ptr %143, i64 -56
  %147 = load i64, ptr %146, align 1, !noalias !486
  %148 = xor i64 %145, 3556072174620004746
  %149 = xor i64 %147, 7238261902898274248
  %150 = zext i64 %148 to i128
  %151 = zext i64 %149 to i128
  %152 = mul nuw i128 %151, %150
  %153 = lshr i128 %152, 64
  %154 = xor i128 %153, %152
  %155 = trunc i128 %154 to i64
  br label %156

156:                                              ; preds = %129, %127
  %157 = phi i64 [ %155, %129 ], [ 0, %127 ]
  %158 = phi i64 [ %142, %129 ], [ %123, %127 ]
  %159 = getelementptr inbounds nuw i8, ptr %0, i64 32
  %160 = load i64, ptr %159, align 1, !noalias !489
  %161 = getelementptr inbounds nuw i8, ptr %0, i64 40
  %162 = load i64, ptr %161, align 1, !noalias !489
  %163 = xor i64 %160, -3818837453329782724
  %164 = xor i64 %162, -6688317018830679928
  %165 = zext i64 %163 to i128
  %166 = zext i64 %164 to i128
  %167 = mul nuw i128 %166, %165
  %168 = lshr i128 %167, 64
  %169 = xor i128 %168, %167
  %170 = trunc i128 %169 to i64
  %171 = add i64 %158, %170
  %172 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %173 = getelementptr inbounds i8, ptr %172, i64 -48
  %174 = load i64, ptr %173, align 1, !noalias !492
  %175 = getelementptr inbounds i8, ptr %172, i64 -40
  %176 = load i64, ptr %175, align 1, !noalias !492
  %177 = xor i64 %174, 5690594596133299313
  %178 = xor i64 %176, -2833645246901970632
  %179 = zext i64 %177 to i128
  %180 = zext i64 %178 to i128
  %181 = mul nuw i128 %180, %179
  %182 = lshr i128 %181, 64
  %183 = xor i128 %182, %181
  %184 = trunc i128 %183 to i64
  %185 = add i64 %157, %184
  br label %186

186:                                              ; preds = %156, %125
  %187 = phi i64 [ %185, %156 ], [ 0, %125 ]
  %188 = phi i64 [ %171, %156 ], [ %123, %125 ]
  %189 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %190 = load i64, ptr %189, align 1, !noalias !495
  %191 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %192 = load i64, ptr %191, align 1, !noalias !495
  %193 = xor i64 %190, 8711581037947681227
  %194 = xor i64 %192, 2410270004345854594
  %195 = zext i64 %193 to i128
  %196 = zext i64 %194 to i128
  %197 = mul nuw i128 %196, %195
  %198 = lshr i128 %197, 64
  %199 = xor i128 %198, %197
  %200 = trunc i128 %199 to i64
  %201 = add i64 %188, %200
  %202 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %203 = getelementptr inbounds i8, ptr %202, i64 -32
  %204 = load i64, ptr %203, align 1, !noalias !498
  %205 = getelementptr inbounds i8, ptr %202, i64 -24
  %206 = load i64, ptr %205, align 1, !noalias !498
  %207 = xor i64 %204, -8204357891075471176
  %208 = xor i64 %206, 5487137525590930912
  %209 = zext i64 %207 to i128
  %210 = zext i64 %208 to i128
  %211 = mul nuw i128 %210, %209
  %212 = lshr i128 %211, 64
  %213 = xor i128 %212, %211
  %214 = trunc i128 %213 to i64
  %215 = add i64 %187, %214
  br label %216

216:                                              ; preds = %122, %186
  %217 = phi i64 [ %215, %186 ], [ 0, %122 ]
  %218 = phi i64 [ %201, %186 ], [ %123, %122 ]
  %219 = load i64, ptr %0, align 1, !noalias !501
  %220 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %221 = load i64, ptr %220, align 1, !noalias !501
  %222 = xor i64 %219, -4734510112055689544
  %223 = xor i64 %221, 2066345149520216444
  %224 = zext i64 %222 to i128
  %225 = zext i64 %223 to i128
  %226 = mul nuw i128 %225, %224
  %227 = lshr i128 %226, 64
  %228 = xor i128 %227, %226
  %229 = trunc i128 %228 to i64
  %230 = add i64 %218, %229
  %231 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %232 = getelementptr inbounds i8, ptr %231, i64 -16
  %233 = load i64, ptr %232, align 1, !noalias !504
  %234 = getelementptr inbounds i8, ptr %231, i64 -8
  %235 = load i64, ptr %234, align 1, !noalias !504
  %236 = xor i64 %233, -2623469361688619810
  %237 = xor i64 %235, 2262974939099578482
  %238 = zext i64 %236 to i128
  %239 = zext i64 %237 to i128
  %240 = mul nuw i128 %239, %238
  %241 = lshr i128 %240, 64
  %242 = xor i128 %241, %240
  %243 = trunc i128 %242 to i64
  %244 = add i64 %217, %243
  %245 = add i64 %244, %230
  %246 = mul i64 %230, -7046029288634856825
  %247 = mul i64 %244, -8796714831421723037
  %248 = mul i64 %1, -4417276706812531889
  %249 = add i64 %246, %248
  %250 = add i64 %249, %247
  %251 = lshr i64 %245, 37
  %252 = xor i64 %251, %245
  %253 = mul i64 %252, 1609587929392839161
  %254 = lshr i64 %253, 32
  %255 = xor i64 %254, %253
  %256 = lshr i64 %250, 37
  %257 = xor i64 %256, %250
  %258 = mul i64 %257, 1609587929392839161
  %259 = lshr i64 %258, 32
  %260 = xor i64 %259, %258
  %261 = sub i64 0, %260
  %262 = insertvalue [2 x i64] poison, i64 %255, 0
  %263 = insertvalue [2 x i64] %262, i64 %261, 1
  br label %270

264:                                              ; preds = %120
  %265 = icmp ult i64 %1, 241
  br i1 %265, label %266, label %268

266:                                              ; preds = %264
  %267 = tail call fastcc [2 x i64] @XXH3_len_129to240_128b(ptr noundef %0, i64 noundef %1, ptr noundef nonnull @kSecret, i64 noundef 0)
  br label %270

268:                                              ; preds = %264
  %269 = tail call fastcc [2 x i64] @XXH3_hashLong_128b_defaultSecret(ptr noundef %0, i64 noundef %1)
  br label %270

270:                                              ; preds = %268, %266, %216, %115
  %271 = phi [2 x i64] [ %119, %115 ], [ %263, %216 ], [ %267, %266 ], [ %269, %268 ]
  ret [2 x i64] %271
}

; Function Attrs: nofree noinline norecurse nosync nounwind ssp memory(argmem: read) uwtable(sync)
define internal fastcc [2 x i64] @XXH3_len_129to240_128b(ptr noalias noundef readonly captures(none) %0, i64 noundef range(i64 129, 241) %1, ptr noalias noundef readonly captures(none) %2, i64 noundef %3) unnamed_addr #11 {
  %5 = mul i64 %1, -7046029288634856825
  br label %6

6:                                                ; preds = %4, %6
  %7 = phi i64 [ 0, %4 ], [ %49, %6 ]
  %8 = phi i64 [ %5, %4 ], [ %29, %6 ]
  %9 = phi i64 [ 0, %4 ], [ %48, %6 ]
  %10 = shl nuw nsw i64 %7, 5
  %11 = getelementptr inbounds nuw i8, ptr %0, i64 %10
  %12 = getelementptr inbounds nuw i8, ptr %2, i64 %10
  %13 = load i64, ptr %11, align 1, !noalias !507
  %14 = getelementptr inbounds nuw i8, ptr %11, i64 8
  %15 = load i64, ptr %14, align 1, !noalias !507
  %16 = load i64, ptr %12, align 1
  %17 = add i64 %16, %3
  %18 = xor i64 %17, %13
  %19 = getelementptr inbounds nuw i8, ptr %12, i64 8
  %20 = load i64, ptr %19, align 1
  %21 = sub i64 %20, %3
  %22 = xor i64 %21, %15
  %23 = zext i64 %18 to i128
  %24 = zext i64 %22 to i128
  %25 = mul nuw i128 %24, %23
  %26 = lshr i128 %25, 64
  %27 = xor i128 %26, %25
  %28 = trunc i128 %27 to i64
  %29 = add i64 %8, %28
  %30 = getelementptr inbounds nuw i8, ptr %11, i64 16
  %31 = getelementptr inbounds nuw i8, ptr %12, i64 16
  %32 = load i64, ptr %30, align 1, !noalias !510
  %33 = getelementptr inbounds nuw i8, ptr %11, i64 24
  %34 = load i64, ptr %33, align 1, !noalias !510
  %35 = load i64, ptr %31, align 1
  %36 = sub i64 %35, %3
  %37 = xor i64 %36, %32
  %38 = getelementptr inbounds nuw i8, ptr %12, i64 24
  %39 = load i64, ptr %38, align 1
  %40 = add i64 %39, %3
  %41 = xor i64 %40, %34
  %42 = zext i64 %37 to i128
  %43 = zext i64 %41 to i128
  %44 = mul nuw i128 %43, %42
  %45 = lshr i128 %44, 64
  %46 = xor i128 %45, %44
  %47 = trunc i128 %46 to i64
  %48 = add i64 %9, %47
  %49 = add nuw nsw i64 %7, 1
  %50 = icmp eq i64 %49, 4
  br i1 %50, label %51, label %6, !llvm.loop !513

51:                                               ; preds = %6
  %52 = trunc nuw nsw i64 %1 to i32
  %53 = lshr i32 %52, 5
  %54 = lshr i64 %29, 37
  %55 = xor i64 %54, %29
  %56 = mul i64 %55, 1609587929392839161
  %57 = lshr i64 %56, 32
  %58 = xor i64 %57, %56
  %59 = lshr i64 %48, 37
  %60 = xor i64 %59, %48
  %61 = mul i64 %60, 1609587929392839161
  %62 = lshr i64 %61, 32
  %63 = xor i64 %62, %61
  %64 = icmp eq i32 %53, 4
  br i1 %64, label %113, label %65

65:                                               ; preds = %51
  %66 = zext nneg i32 %53 to i64
  br label %67

67:                                               ; preds = %65, %67
  %68 = phi i64 [ 4, %65 ], [ %111, %67 ]
  %69 = phi i64 [ %58, %65 ], [ %91, %67 ]
  %70 = phi i64 [ %63, %65 ], [ %110, %67 ]
  %71 = shl nsw i64 %68, 5
  %72 = getelementptr inbounds nuw i8, ptr %0, i64 %71
  %73 = getelementptr i8, ptr %2, i64 %71
  %74 = getelementptr i8, ptr %73, i64 -125
  %75 = load i64, ptr %72, align 1, !noalias !514
  %76 = getelementptr inbounds nuw i8, ptr %72, i64 8
  %77 = load i64, ptr %76, align 1, !noalias !514
  %78 = load i64, ptr %74, align 1
  %79 = add i64 %78, %3
  %80 = xor i64 %79, %75
  %81 = getelementptr i8, ptr %73, i64 -117
  %82 = load i64, ptr %81, align 1
  %83 = sub i64 %82, %3
  %84 = xor i64 %83, %77
  %85 = zext i64 %80 to i128
  %86 = zext i64 %84 to i128
  %87 = mul nuw i128 %86, %85
  %88 = lshr i128 %87, 64
  %89 = xor i128 %88, %87
  %90 = trunc i128 %89 to i64
  %91 = add i64 %69, %90
  %92 = getelementptr inbounds nuw i8, ptr %72, i64 16
  %93 = getelementptr i8, ptr %73, i64 -109
  %94 = load i64, ptr %92, align 1, !noalias !517
  %95 = getelementptr inbounds nuw i8, ptr %72, i64 24
  %96 = load i64, ptr %95, align 1, !noalias !517
  %97 = load i64, ptr %93, align 1
  %98 = sub i64 %97, %3
  %99 = xor i64 %98, %94
  %100 = getelementptr i8, ptr %73, i64 -101
  %101 = load i64, ptr %100, align 1
  %102 = add i64 %101, %3
  %103 = xor i64 %102, %96
  %104 = zext i64 %99 to i128
  %105 = zext i64 %103 to i128
  %106 = mul nuw i128 %105, %104
  %107 = lshr i128 %106, 64
  %108 = xor i128 %107, %106
  %109 = trunc i128 %108 to i64
  %110 = add i64 %70, %109
  %111 = add nuw nsw i64 %68, 1
  %112 = icmp eq i64 %111, %66
  br i1 %112, label %113, label %67, !llvm.loop !520

113:                                              ; preds = %67, %51
  %114 = phi i64 [ %63, %51 ], [ %110, %67 ]
  %115 = phi i64 [ %58, %51 ], [ %91, %67 ]
  %116 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %117 = getelementptr inbounds i8, ptr %116, i64 -16
  %118 = getelementptr inbounds nuw i8, ptr %2, i64 119
  %119 = load i64, ptr %117, align 1, !noalias !521
  %120 = getelementptr inbounds i8, ptr %116, i64 -8
  %121 = load i64, ptr %120, align 1, !noalias !521
  %122 = load i64, ptr %118, align 1
  %123 = add i64 %122, %3
  %124 = xor i64 %123, %119
  %125 = getelementptr inbounds nuw i8, ptr %2, i64 127
  %126 = load i64, ptr %125, align 1
  %127 = sub i64 %126, %3
  %128 = xor i64 %127, %121
  %129 = zext i64 %124 to i128
  %130 = zext i64 %128 to i128
  %131 = mul nuw i128 %130, %129
  %132 = lshr i128 %131, 64
  %133 = xor i128 %132, %131
  %134 = trunc i128 %133 to i64
  %135 = add i64 %115, %134
  %136 = getelementptr inbounds i8, ptr %116, i64 -32
  %137 = getelementptr inbounds nuw i8, ptr %2, i64 103
  %138 = load i64, ptr %136, align 1, !noalias !524
  %139 = getelementptr inbounds i8, ptr %116, i64 -24
  %140 = load i64, ptr %139, align 1, !noalias !524
  %141 = load i64, ptr %137, align 1
  %142 = sub i64 %141, %3
  %143 = xor i64 %142, %138
  %144 = getelementptr inbounds nuw i8, ptr %2, i64 111
  %145 = load i64, ptr %144, align 1
  %146 = add i64 %145, %3
  %147 = xor i64 %146, %140
  %148 = zext i64 %143 to i128
  %149 = zext i64 %147 to i128
  %150 = mul nuw i128 %149, %148
  %151 = lshr i128 %150, 64
  %152 = xor i128 %151, %150
  %153 = trunc i128 %152 to i64
  %154 = add i64 %114, %153
  %155 = add i64 %154, %135
  %156 = mul i64 %135, -7046029288634856825
  %157 = mul i64 %154, -8796714831421723037
  %158 = sub i64 %1, %3
  %159 = mul i64 %158, -4417276706812531889
  %160 = add i64 %156, %159
  %161 = add i64 %160, %157
  %162 = lshr i64 %155, 37
  %163 = xor i64 %162, %155
  %164 = mul i64 %163, 1609587929392839161
  %165 = lshr i64 %164, 32
  %166 = xor i64 %165, %164
  %167 = lshr i64 %161, 37
  %168 = xor i64 %167, %161
  %169 = mul i64 %168, 1609587929392839161
  %170 = lshr i64 %169, 32
  %171 = xor i64 %170, %169
  %172 = sub i64 0, %171
  %173 = insertvalue [2 x i64] poison, i64 %166, 0
  %174 = insertvalue [2 x i64] %173, i64 %172, 1
  ret [2 x i64] %174
}

; Function Attrs: nofree noinline norecurse nosync nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync)
define internal fastcc [2 x i64] @XXH3_hashLong_128b_defaultSecret(ptr noundef readonly captures(none) %0, i64 noundef range(i64 241, 0) %1) unnamed_addr #12 {
  %3 = alloca [8 x i64], align 16
  tail call void @llvm.experimental.noalias.scope.decl(metadata !527)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !530)
  call void @llvm.lifetime.start.p0(i64 64, ptr nonnull %3) #24, !noalias !532
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(64) %3, ptr noundef nonnull align 16 dereferenceable(64) @__const.XXH3_hashLong_128b_internal.acc, i64 64, i1 false), !noalias !532
  %4 = lshr i64 %1, 10
  %5 = icmp ult i64 %1, 1024
  br i1 %5, label %63, label %6

6:                                                ; preds = %2, %60
  %7 = phi i64 [ %61, %60 ], [ 0, %2 ]
  %8 = shl i64 %7, 10
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 %8
  br label %10

10:                                               ; preds = %6, %37
  %11 = phi i64 [ 0, %6 ], [ %38, %37 ]
  %12 = shl nuw nsw i64 %11, 6
  %13 = getelementptr inbounds nuw i8, ptr %9, i64 %12
  %14 = shl nuw nsw i64 %11, 3
  %15 = getelementptr inbounds nuw i8, ptr @kSecret, i64 %14
  tail call void @llvm.experimental.noalias.scope.decl(metadata !533)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !536)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !538)
  br label %16

16:                                               ; preds = %10, %16
  %17 = phi i64 [ 0, %10 ], [ %35, %16 ]
  %18 = shl nuw nsw i64 %17, 2
  %19 = getelementptr inbounds nuw i32, ptr %13, i64 %18
  %20 = load <4 x i32>, ptr %19, align 4, !alias.scope !540, !noalias !541
  %21 = getelementptr inbounds nuw i32, ptr %15, i64 %18
  %22 = load <4 x i32>, ptr %21, align 8, !alias.scope !542, !noalias !543
  %23 = xor <4 x i32> %22, %20
  %24 = bitcast <4 x i32> %23 to <2 x i64>
  %25 = trunc <2 x i64> %24 to <2 x i32>
  %26 = lshr <2 x i64> %24, splat (i64 32)
  %27 = trunc nuw <2 x i64> %26 to <2 x i32>
  %28 = bitcast <4 x i32> %20 to <2 x i64>
  %29 = shufflevector <2 x i64> %28, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %30 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %17
  %31 = load <2 x i64>, ptr %30, align 16, !tbaa !21, !alias.scope !533, !noalias !544
  %32 = add <2 x i64> %31, %29
  %33 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %25, <2 x i32> %27)
  %34 = add <2 x i64> %32, %33
  store <2 x i64> %34, ptr %30, align 16, !tbaa !21, !alias.scope !533, !noalias !544
  %35 = add nuw nsw i64 %17, 1
  %36 = icmp eq i64 %35, 4
  br i1 %36, label %37, label %16, !llvm.loop !82

37:                                               ; preds = %16
  %38 = add nuw nsw i64 %11, 1
  %39 = icmp eq i64 %38, 16
  br i1 %39, label %40, label %10, !llvm.loop !83

40:                                               ; preds = %37
  tail call void @llvm.experimental.noalias.scope.decl(metadata !545)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !548)
  br label %41

41:                                               ; preds = %40, %41
  %42 = phi i64 [ 0, %40 ], [ %58, %41 ]
  %43 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %42
  %44 = load <2 x i64>, ptr %43, align 16, !tbaa !21, !alias.scope !545, !noalias !550
  %45 = lshr <2 x i64> %44, splat (i64 47)
  %46 = xor <2 x i64> %45, %44
  %47 = shl nuw nsw i64 %42, 4
  %48 = getelementptr inbounds nuw i8, ptr getelementptr inbounds nuw (i8, ptr @kSecret, i64 128), i64 %47
  %49 = load <4 x i32>, ptr %48, align 16, !alias.scope !551, !noalias !552
  %50 = bitcast <2 x i64> %46 to <4 x i32>
  %51 = xor <4 x i32> %49, %50
  %52 = shufflevector <4 x i32> %51, <4 x i32> poison, <2 x i32> <i32 0, i32 2>
  %53 = shufflevector <4 x i32> %51, <4 x i32> poison, <2 x i32> <i32 1, i32 3>
  %54 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %53, <2 x i32> splat (i32 -1640531535))
  %55 = shl <2 x i64> %54, splat (i64 32)
  %56 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %52, <2 x i32> splat (i32 -1640531535))
  %57 = add <2 x i64> %55, %56
  store <2 x i64> %57, ptr %43, align 16, !tbaa !21, !alias.scope !545, !noalias !550
  %58 = add nuw nsw i64 %42, 1
  %59 = icmp eq i64 %58, 4
  br i1 %59, label %60, label %41, !llvm.loop !89

60:                                               ; preds = %41
  %61 = add nuw nsw i64 %7, 1
  %62 = icmp eq i64 %61, %4
  br i1 %62, label %63, label %6, !llvm.loop !90

63:                                               ; preds = %60, %2
  %64 = and i64 %1, -1024
  %65 = lshr i64 %1, 6
  %66 = and i64 %65, 15
  %67 = getelementptr inbounds nuw i8, ptr %0, i64 %64
  %68 = icmp eq i64 %66, 0
  br i1 %68, label %99, label %69

69:                                               ; preds = %63, %96
  %70 = phi i64 [ %97, %96 ], [ 0, %63 ]
  %71 = shl i64 %70, 6
  %72 = getelementptr inbounds nuw i8, ptr %67, i64 %71
  %73 = shl i64 %70, 3
  %74 = getelementptr inbounds nuw i8, ptr @kSecret, i64 %73
  tail call void @llvm.experimental.noalias.scope.decl(metadata !553)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !556)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !558)
  br label %75

75:                                               ; preds = %69, %75
  %76 = phi i64 [ 0, %69 ], [ %94, %75 ]
  %77 = shl nuw nsw i64 %76, 2
  %78 = getelementptr inbounds nuw i32, ptr %72, i64 %77
  %79 = load <4 x i32>, ptr %78, align 4, !alias.scope !560, !noalias !561
  %80 = getelementptr inbounds nuw i32, ptr %74, i64 %77
  %81 = load <4 x i32>, ptr %80, align 8, !alias.scope !562, !noalias !563
  %82 = xor <4 x i32> %81, %79
  %83 = bitcast <4 x i32> %82 to <2 x i64>
  %84 = trunc <2 x i64> %83 to <2 x i32>
  %85 = lshr <2 x i64> %83, splat (i64 32)
  %86 = trunc nuw <2 x i64> %85 to <2 x i32>
  %87 = bitcast <4 x i32> %79 to <2 x i64>
  %88 = shufflevector <2 x i64> %87, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %89 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %76
  %90 = load <2 x i64>, ptr %89, align 16, !tbaa !21, !alias.scope !553, !noalias !564
  %91 = add <2 x i64> %90, %88
  %92 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %84, <2 x i32> %86)
  %93 = add <2 x i64> %91, %92
  store <2 x i64> %93, ptr %89, align 16, !tbaa !21, !alias.scope !553, !noalias !564
  %94 = add nuw nsw i64 %76, 1
  %95 = icmp eq i64 %94, 4
  br i1 %95, label %96, label %75, !llvm.loop !82

96:                                               ; preds = %75
  %97 = add nuw nsw i64 %70, 1
  %98 = icmp eq i64 %97, %66
  br i1 %98, label %99, label %69, !llvm.loop !83

99:                                               ; preds = %96, %63
  %100 = and i64 %1, 63
  %101 = icmp eq i64 %100, 0
  br i1 %101, label %126, label %102

102:                                              ; preds = %99
  %103 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %104 = getelementptr inbounds i8, ptr %103, i64 -64
  tail call void @llvm.experimental.noalias.scope.decl(metadata !565)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !568)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !570)
  br label %105

105:                                              ; preds = %102, %105
  %106 = phi i64 [ 0, %102 ], [ %124, %105 ]
  %107 = shl nuw nsw i64 %106, 2
  %108 = getelementptr inbounds nuw i32, ptr %104, i64 %107
  %109 = load <4 x i32>, ptr %108, align 4, !alias.scope !572, !noalias !573
  %110 = getelementptr inbounds nuw i32, ptr getelementptr inbounds nuw (i8, ptr @kSecret, i64 121), i64 %107
  %111 = load <4 x i32>, ptr %110, align 4, !alias.scope !574, !noalias !575
  %112 = xor <4 x i32> %111, %109
  %113 = bitcast <4 x i32> %112 to <2 x i64>
  %114 = trunc <2 x i64> %113 to <2 x i32>
  %115 = lshr <2 x i64> %113, splat (i64 32)
  %116 = trunc nuw <2 x i64> %115 to <2 x i32>
  %117 = bitcast <4 x i32> %109 to <2 x i64>
  %118 = shufflevector <2 x i64> %117, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %119 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %106
  %120 = load <2 x i64>, ptr %119, align 16, !tbaa !21, !alias.scope !565, !noalias !576
  %121 = add <2 x i64> %120, %118
  %122 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %114, <2 x i32> %116)
  %123 = add <2 x i64> %121, %122
  store <2 x i64> %123, ptr %119, align 16, !tbaa !21, !alias.scope !565, !noalias !576
  %124 = add nuw nsw i64 %106, 1
  %125 = icmp eq i64 %124, 4
  br i1 %125, label %126, label %105, !llvm.loop !82

126:                                              ; preds = %105, %99
  %127 = mul i64 %1, -7046029288634856825
  %128 = load i64, ptr %3, align 16, !tbaa !22, !alias.scope !577, !noalias !582
  %129 = xor i64 %128, 7914194659941938988
  %130 = getelementptr inbounds nuw i8, ptr %3, i64 8
  %131 = load i64, ptr %130, align 8, !tbaa !22, !alias.scope !577, !noalias !582
  %132 = xor i64 %131, -6611157965513653271
  %133 = zext i64 %129 to i128
  %134 = zext i64 %132 to i128
  %135 = mul nuw i128 %134, %133
  %136 = lshr i128 %135, 64
  %137 = xor i128 %136, %135
  %138 = trunc i128 %137 to i64
  %139 = add i64 %127, %138
  %140 = getelementptr inbounds nuw i8, ptr %3, i64 16
  %141 = load i64, ptr %140, align 16, !tbaa !22, !alias.scope !585, !noalias !588
  %142 = xor i64 %141, -1839215637059881052
  %143 = getelementptr inbounds nuw i8, ptr %3, i64 24
  %144 = load i64, ptr %143, align 8, !tbaa !22, !alias.scope !585, !noalias !588
  %145 = xor i64 %144, -3433288310154277810
  %146 = zext i64 %142 to i128
  %147 = zext i64 %145 to i128
  %148 = mul nuw i128 %147, %146
  %149 = lshr i128 %148, 64
  %150 = xor i128 %149, %148
  %151 = trunc i128 %150 to i64
  %152 = add i64 %139, %151
  %153 = getelementptr inbounds nuw i8, ptr %3, i64 32
  %154 = load i64, ptr %153, align 16, !tbaa !22, !alias.scope !590, !noalias !593
  %155 = xor i64 %154, 5046485836271438973
  %156 = getelementptr inbounds nuw i8, ptr %3, i64 40
  %157 = load i64, ptr %156, align 8, !tbaa !22, !alias.scope !590, !noalias !593
  %158 = xor i64 %157, -8055285457383852172
  %159 = zext i64 %155 to i128
  %160 = zext i64 %158 to i128
  %161 = mul nuw i128 %160, %159
  %162 = lshr i128 %161, 64
  %163 = xor i128 %162, %161
  %164 = trunc i128 %163 to i64
  %165 = add i64 %152, %164
  %166 = getelementptr inbounds nuw i8, ptr %3, i64 48
  %167 = load i64, ptr %166, align 16, !tbaa !22, !alias.scope !595, !noalias !598
  %168 = xor i64 %167, 5920048007935066598
  %169 = getelementptr inbounds nuw i8, ptr %3, i64 56
  %170 = load i64, ptr %169, align 8, !tbaa !22, !alias.scope !595, !noalias !598
  %171 = xor i64 %170, 7336514198459093435
  %172 = zext i64 %168 to i128
  %173 = zext i64 %171 to i128
  %174 = mul nuw i128 %173, %172
  %175 = lshr i128 %174, 64
  %176 = xor i128 %175, %174
  %177 = trunc i128 %176 to i64
  %178 = add i64 %165, %177
  %179 = lshr i64 %178, 37
  %180 = xor i64 %179, %178
  %181 = mul i64 %180, 1609587929392839161
  %182 = lshr i64 %181, 32
  %183 = xor i64 %182, %181
  %184 = mul i64 %1, -4417276706812531889
  %185 = xor i64 %184, -1
  %186 = xor i64 %128, -2753530472436770380
  %187 = xor i64 %131, 3784058077962335096
  %188 = zext i64 %186 to i128
  %189 = zext i64 %187 to i128
  %190 = mul nuw i128 %189, %188
  %191 = lshr i128 %190, 64
  %192 = xor i128 %191, %190
  %193 = trunc i128 %192 to i64
  %194 = add i64 %193, %185
  %195 = xor i64 %141, -360392965937173549
  %196 = xor i64 %144, -5237161843349560557
  %197 = zext i64 %195 to i128
  %198 = zext i64 %196 to i128
  %199 = mul nuw i128 %198, %197
  %200 = lshr i128 %199, 64
  %201 = xor i128 %200, %199
  %202 = trunc i128 %201 to i64
  %203 = add i64 %194, %202
  %204 = xor i64 %154, 2965150961192524528
  %205 = xor i64 %157, 9032178055121889492
  %206 = zext i64 %204 to i128
  %207 = zext i64 %205 to i128
  %208 = mul nuw i128 %207, %206
  %209 = lshr i128 %208, 64
  %210 = xor i128 %209, %208
  %211 = trunc i128 %210 to i64
  %212 = add i64 %203, %211
  %213 = xor i64 %167, 8850058120466833735
  %214 = xor i64 %170, -7669846995664752176
  %215 = zext i64 %213 to i128
  %216 = zext i64 %214 to i128
  %217 = mul nuw i128 %216, %215
  %218 = lshr i128 %217, 64
  %219 = xor i128 %218, %217
  %220 = trunc i128 %219 to i64
  %221 = add i64 %212, %220
  %222 = lshr i64 %221, 37
  %223 = xor i64 %222, %221
  %224 = mul i64 %223, 1609587929392839161
  %225 = lshr i64 %224, 32
  %226 = xor i64 %225, %224
  call void @llvm.lifetime.end.p0(i64 64, ptr nonnull %3) #24, !noalias !532
  %227 = insertvalue [2 x i64] poison, i64 %183, 0
  %228 = insertvalue [2 x i64] %227, i64 %226, 1
  ret [2 x i64] %228
}

; Function Attrs: nofree norecurse nosync nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync)
define [2 x i64] @XXH3_128bits_withSecret(ptr noundef readonly captures(none) %0, i64 noundef %1, ptr noundef readonly captures(none) %2, i64 noundef %3) local_unnamed_addr #10 {
  %5 = icmp ult i64 %1, 17
  br i1 %5, label %6, label %131

6:                                                ; preds = %4
  %7 = icmp samesign ugt i64 %1, 8
  br i1 %7, label %8, label %45

8:                                                ; preds = %6
  %9 = load i64, ptr %0, align 1
  %10 = load i64, ptr %2, align 1
  %11 = xor i64 %10, %9
  %12 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %13 = getelementptr inbounds i8, ptr %12, i64 -8
  %14 = load i64, ptr %13, align 1
  %15 = getelementptr inbounds nuw i8, ptr %2, i64 8
  %16 = load i64, ptr %15, align 1
  %17 = xor i64 %16, %14
  %18 = xor i64 %11, %17
  %19 = zext i64 %18 to i128
  %20 = mul nuw i128 %19, 11400714785074694791
  %21 = trunc i128 %20 to i64
  %22 = lshr i128 %20, 64
  %23 = trunc nuw i128 %22 to i64
  %24 = mul i64 %17, -7046029288634856825
  %25 = add i64 %24, %23
  %26 = lshr i64 %25, 32
  %27 = xor i64 %26, %21
  %28 = zext i64 %27 to i128
  %29 = mul nuw i128 %28, 14029467366897019727
  %30 = trunc i128 %29 to i64
  %31 = lshr i128 %29, 64
  %32 = trunc nuw i128 %31 to i64
  %33 = mul i64 %25, -4417276706812531889
  %34 = add i64 %33, %32
  %35 = lshr i64 %30, 37
  %36 = xor i64 %35, %30
  %37 = mul i64 %36, 1609587929392839161
  %38 = lshr i64 %37, 32
  %39 = xor i64 %38, %37
  %40 = lshr i64 %34, 37
  %41 = xor i64 %40, %34
  %42 = mul i64 %41, 1609587929392839161
  %43 = lshr i64 %42, 32
  %44 = xor i64 %43, %42
  br label %126

45:                                               ; preds = %6
  %46 = icmp samesign ugt i64 %1, 3
  br i1 %46, label %47, label %86

47:                                               ; preds = %45
  %48 = load i32, ptr %0, align 1
  %49 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %50 = getelementptr inbounds i8, ptr %49, i64 -4
  %51 = load i32, ptr %50, align 1
  %52 = zext i32 %48 to i64
  %53 = zext i32 %51 to i64
  %54 = shl nuw i64 %53, 32
  %55 = or disjoint i64 %54, %52
  %56 = tail call noundef i64 @llvm.bswap.i64(i64 %55)
  %57 = load i64, ptr %2, align 1
  %58 = xor i64 %55, %57
  %59 = getelementptr inbounds nuw i8, ptr %2, i64 8
  %60 = load i64, ptr %59, align 1
  %61 = xor i64 %56, %60
  %62 = lshr i64 %58, 51
  %63 = xor i64 %62, %58
  %64 = mul i64 %63, 2654435761
  %65 = add i64 %64, %1
  %66 = lshr i64 %65, 47
  %67 = xor i64 %66, %65
  %68 = mul i64 %67, -4417276706812531889
  %69 = lshr i64 %61, 47
  %70 = xor i64 %69, %61
  %71 = mul i64 %70, -7046029288634856825
  %72 = sub i64 %71, %1
  %73 = lshr i64 %72, 43
  %74 = xor i64 %73, %72
  %75 = mul i64 %74, -8796714831421723037
  %76 = lshr i64 %68, 37
  %77 = xor i64 %76, %68
  %78 = mul i64 %77, 1609587929392839161
  %79 = lshr i64 %78, 32
  %80 = xor i64 %79, %78
  %81 = lshr i64 %75, 37
  %82 = xor i64 %81, %75
  %83 = mul i64 %82, 1609587929392839161
  %84 = lshr i64 %83, 32
  %85 = xor i64 %84, %83
  br label %126

86:                                               ; preds = %45
  %87 = icmp eq i64 %1, 0
  br i1 %87, label %126, label %88

88:                                               ; preds = %86
  %89 = load i8, ptr %0, align 1, !tbaa !21
  %90 = lshr i64 %1, 1
  %91 = getelementptr inbounds nuw i8, ptr %0, i64 %90
  %92 = load i8, ptr %91, align 1, !tbaa !21
  %93 = getelementptr i8, ptr %0, i64 %1
  %94 = getelementptr i8, ptr %93, i64 -1
  %95 = load i8, ptr %94, align 1, !tbaa !21
  %96 = zext i8 %89 to i32
  %97 = zext i8 %92 to i32
  %98 = shl nuw nsw i32 %97, 8
  %99 = or disjoint i32 %98, %96
  %100 = zext i8 %95 to i32
  %101 = shl nuw nsw i32 %100, 16
  %102 = or disjoint i32 %99, %101
  %103 = trunc nuw nsw i64 %1 to i32
  %104 = shl nuw nsw i32 %103, 24
  %105 = or disjoint i32 %102, %104
  %106 = tail call noundef i32 @llvm.bswap.i32(i32 %105)
  %107 = load i32, ptr %2, align 1
  %108 = xor i32 %105, %107
  %109 = zext i32 %108 to i64
  %110 = getelementptr inbounds nuw i8, ptr %2, i64 4
  %111 = load i32, ptr %110, align 1
  %112 = xor i32 %106, %111
  %113 = zext i32 %112 to i64
  %114 = mul i64 %109, -7046029288634856825
  %115 = mul i64 %113, -4417276706812531889
  %116 = lshr i64 %114, 37
  %117 = xor i64 %116, %114
  %118 = mul i64 %117, 1609587929392839161
  %119 = lshr i64 %118, 32
  %120 = xor i64 %119, %118
  %121 = lshr i64 %115, 37
  %122 = xor i64 %121, %115
  %123 = mul i64 %122, 1609587929392839161
  %124 = lshr i64 %123, 32
  %125 = xor i64 %124, %123
  br label %126

126:                                              ; preds = %8, %47, %86, %88
  %127 = phi i64 [ %44, %8 ], [ %85, %47 ], [ %125, %88 ], [ 0, %86 ]
  %128 = phi i64 [ %39, %8 ], [ %80, %47 ], [ %120, %88 ], [ 0, %86 ]
  %129 = insertvalue [2 x i64] poison, i64 %128, 0
  %130 = insertvalue [2 x i64] %129, i64 %127, 1
  br label %312

131:                                              ; preds = %4
  %132 = icmp ult i64 %1, 129
  br i1 %132, label %133, label %306

133:                                              ; preds = %131
  %134 = mul i64 %1, -7046029288634856825
  %135 = icmp samesign ugt i64 %1, 32
  br i1 %135, label %136, label %251

136:                                              ; preds = %133
  %137 = icmp samesign ugt i64 %1, 64
  br i1 %137, label %138, label %213

138:                                              ; preds = %136
  %139 = icmp samesign ugt i64 %1, 96
  br i1 %139, label %140, label %175

140:                                              ; preds = %138
  %141 = getelementptr inbounds nuw i8, ptr %0, i64 48
  %142 = getelementptr inbounds nuw i8, ptr %2, i64 96
  %143 = load i64, ptr %141, align 1, !noalias !600
  %144 = getelementptr inbounds nuw i8, ptr %0, i64 56
  %145 = load i64, ptr %144, align 1, !noalias !600
  %146 = load i64, ptr %142, align 1
  %147 = xor i64 %146, %143
  %148 = getelementptr inbounds nuw i8, ptr %2, i64 104
  %149 = load i64, ptr %148, align 1
  %150 = xor i64 %149, %145
  %151 = zext i64 %147 to i128
  %152 = zext i64 %150 to i128
  %153 = mul nuw i128 %152, %151
  %154 = lshr i128 %153, 64
  %155 = xor i128 %154, %153
  %156 = trunc i128 %155 to i64
  %157 = add i64 %134, %156
  %158 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %159 = getelementptr inbounds i8, ptr %158, i64 -64
  %160 = getelementptr inbounds nuw i8, ptr %2, i64 112
  %161 = load i64, ptr %159, align 1, !noalias !603
  %162 = getelementptr inbounds i8, ptr %158, i64 -56
  %163 = load i64, ptr %162, align 1, !noalias !603
  %164 = load i64, ptr %160, align 1
  %165 = xor i64 %164, %161
  %166 = getelementptr inbounds nuw i8, ptr %2, i64 120
  %167 = load i64, ptr %166, align 1
  %168 = xor i64 %167, %163
  %169 = zext i64 %165 to i128
  %170 = zext i64 %168 to i128
  %171 = mul nuw i128 %170, %169
  %172 = lshr i128 %171, 64
  %173 = xor i128 %172, %171
  %174 = trunc i128 %173 to i64
  br label %175

175:                                              ; preds = %140, %138
  %176 = phi i64 [ %174, %140 ], [ 0, %138 ]
  %177 = phi i64 [ %157, %140 ], [ %134, %138 ]
  %178 = getelementptr inbounds nuw i8, ptr %0, i64 32
  %179 = getelementptr inbounds nuw i8, ptr %2, i64 64
  %180 = load i64, ptr %178, align 1, !noalias !606
  %181 = getelementptr inbounds nuw i8, ptr %0, i64 40
  %182 = load i64, ptr %181, align 1, !noalias !606
  %183 = load i64, ptr %179, align 1
  %184 = xor i64 %183, %180
  %185 = getelementptr inbounds nuw i8, ptr %2, i64 72
  %186 = load i64, ptr %185, align 1
  %187 = xor i64 %186, %182
  %188 = zext i64 %184 to i128
  %189 = zext i64 %187 to i128
  %190 = mul nuw i128 %189, %188
  %191 = lshr i128 %190, 64
  %192 = xor i128 %191, %190
  %193 = trunc i128 %192 to i64
  %194 = add i64 %177, %193
  %195 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %196 = getelementptr inbounds i8, ptr %195, i64 -48
  %197 = getelementptr inbounds nuw i8, ptr %2, i64 80
  %198 = load i64, ptr %196, align 1, !noalias !609
  %199 = getelementptr inbounds i8, ptr %195, i64 -40
  %200 = load i64, ptr %199, align 1, !noalias !609
  %201 = load i64, ptr %197, align 1
  %202 = xor i64 %201, %198
  %203 = getelementptr inbounds nuw i8, ptr %2, i64 88
  %204 = load i64, ptr %203, align 1
  %205 = xor i64 %204, %200
  %206 = zext i64 %202 to i128
  %207 = zext i64 %205 to i128
  %208 = mul nuw i128 %207, %206
  %209 = lshr i128 %208, 64
  %210 = xor i128 %209, %208
  %211 = trunc i128 %210 to i64
  %212 = add i64 %176, %211
  br label %213

213:                                              ; preds = %175, %136
  %214 = phi i64 [ %212, %175 ], [ 0, %136 ]
  %215 = phi i64 [ %194, %175 ], [ %134, %136 ]
  %216 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %217 = getelementptr inbounds nuw i8, ptr %2, i64 32
  %218 = load i64, ptr %216, align 1, !noalias !612
  %219 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %220 = load i64, ptr %219, align 1, !noalias !612
  %221 = load i64, ptr %217, align 1
  %222 = xor i64 %221, %218
  %223 = getelementptr inbounds nuw i8, ptr %2, i64 40
  %224 = load i64, ptr %223, align 1
  %225 = xor i64 %224, %220
  %226 = zext i64 %222 to i128
  %227 = zext i64 %225 to i128
  %228 = mul nuw i128 %227, %226
  %229 = lshr i128 %228, 64
  %230 = xor i128 %229, %228
  %231 = trunc i128 %230 to i64
  %232 = add i64 %215, %231
  %233 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %234 = getelementptr inbounds i8, ptr %233, i64 -32
  %235 = getelementptr inbounds nuw i8, ptr %2, i64 48
  %236 = load i64, ptr %234, align 1, !noalias !615
  %237 = getelementptr inbounds i8, ptr %233, i64 -24
  %238 = load i64, ptr %237, align 1, !noalias !615
  %239 = load i64, ptr %235, align 1
  %240 = xor i64 %239, %236
  %241 = getelementptr inbounds nuw i8, ptr %2, i64 56
  %242 = load i64, ptr %241, align 1
  %243 = xor i64 %242, %238
  %244 = zext i64 %240 to i128
  %245 = zext i64 %243 to i128
  %246 = mul nuw i128 %245, %244
  %247 = lshr i128 %246, 64
  %248 = xor i128 %247, %246
  %249 = trunc i128 %248 to i64
  %250 = add i64 %214, %249
  br label %251

251:                                              ; preds = %133, %213
  %252 = phi i64 [ %250, %213 ], [ 0, %133 ]
  %253 = phi i64 [ %232, %213 ], [ %134, %133 ]
  %254 = load i64, ptr %0, align 1, !noalias !618
  %255 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %256 = load i64, ptr %255, align 1, !noalias !618
  %257 = load i64, ptr %2, align 1
  %258 = xor i64 %257, %254
  %259 = getelementptr inbounds nuw i8, ptr %2, i64 8
  %260 = load i64, ptr %259, align 1
  %261 = xor i64 %260, %256
  %262 = zext i64 %258 to i128
  %263 = zext i64 %261 to i128
  %264 = mul nuw i128 %263, %262
  %265 = lshr i128 %264, 64
  %266 = xor i128 %265, %264
  %267 = trunc i128 %266 to i64
  %268 = add i64 %253, %267
  %269 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %270 = getelementptr inbounds i8, ptr %269, i64 -16
  %271 = getelementptr inbounds nuw i8, ptr %2, i64 16
  %272 = load i64, ptr %270, align 1, !noalias !621
  %273 = getelementptr inbounds i8, ptr %269, i64 -8
  %274 = load i64, ptr %273, align 1, !noalias !621
  %275 = load i64, ptr %271, align 1
  %276 = xor i64 %275, %272
  %277 = getelementptr inbounds nuw i8, ptr %2, i64 24
  %278 = load i64, ptr %277, align 1
  %279 = xor i64 %278, %274
  %280 = zext i64 %276 to i128
  %281 = zext i64 %279 to i128
  %282 = mul nuw i128 %281, %280
  %283 = lshr i128 %282, 64
  %284 = xor i128 %283, %282
  %285 = trunc i128 %284 to i64
  %286 = add i64 %252, %285
  %287 = add i64 %286, %268
  %288 = mul i64 %268, -7046029288634856825
  %289 = mul i64 %286, -8796714831421723037
  %290 = mul i64 %1, -4417276706812531889
  %291 = add i64 %288, %290
  %292 = add i64 %291, %289
  %293 = lshr i64 %287, 37
  %294 = xor i64 %293, %287
  %295 = mul i64 %294, 1609587929392839161
  %296 = lshr i64 %295, 32
  %297 = xor i64 %296, %295
  %298 = lshr i64 %292, 37
  %299 = xor i64 %298, %292
  %300 = mul i64 %299, 1609587929392839161
  %301 = lshr i64 %300, 32
  %302 = xor i64 %301, %300
  %303 = sub i64 0, %302
  %304 = insertvalue [2 x i64] poison, i64 %297, 0
  %305 = insertvalue [2 x i64] %304, i64 %303, 1
  br label %312

306:                                              ; preds = %131
  %307 = icmp ult i64 %1, 241
  br i1 %307, label %308, label %310

308:                                              ; preds = %306
  %309 = tail call fastcc [2 x i64] @XXH3_len_129to240_128b(ptr noundef %0, i64 noundef %1, ptr noundef %2, i64 noundef 0)
  br label %312

310:                                              ; preds = %306
  %311 = tail call fastcc [2 x i64] @XXH3_hashLong_128b_withSecret(ptr noundef %0, i64 noundef %1, ptr noundef %2, i64 noundef %3)
  br label %312

312:                                              ; preds = %310, %308, %251, %126
  %313 = phi [2 x i64] [ %130, %126 ], [ %305, %251 ], [ %309, %308 ], [ %311, %310 ]
  ret [2 x i64] %313
}

; Function Attrs: nofree noinline norecurse nosync nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync)
define internal fastcc [2 x i64] @XXH3_hashLong_128b_withSecret(ptr noundef readonly captures(none) %0, i64 noundef range(i64 241, 0) %1, ptr noundef readonly captures(none) %2, i64 noundef %3) unnamed_addr #12 {
  %5 = alloca [8 x i64], align 16
  tail call void @llvm.experimental.noalias.scope.decl(metadata !624)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !627)
  call void @llvm.lifetime.start.p0(i64 64, ptr nonnull %5) #24, !noalias !629
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(64) %5, ptr noundef nonnull align 16 dereferenceable(64) @__const.XXH3_hashLong_128b_internal.acc, i64 64, i1 false), !noalias !629
  %6 = add i64 %3, -64
  %7 = lshr i64 %6, 3
  %8 = shl i64 %7, 6
  %9 = udiv i64 %1, %8
  %10 = icmp ugt i64 %8, %1
  br i1 %10, label %73, label %11

11:                                               ; preds = %4
  %12 = icmp ult i64 %6, 8
  %13 = getelementptr inbounds nuw i8, ptr %2, i64 %3
  %14 = getelementptr inbounds i8, ptr %13, i64 -64
  %15 = tail call i64 @llvm.umax.i64(i64 %7, i64 1)
  br label %16

16:                                               ; preds = %11, %70
  %17 = phi i64 [ 0, %11 ], [ %71, %70 ]
  %18 = mul i64 %17, %8
  %19 = getelementptr inbounds nuw i8, ptr %0, i64 %18
  br i1 %12, label %50, label %20

20:                                               ; preds = %16, %47
  %21 = phi i64 [ %48, %47 ], [ 0, %16 ]
  %22 = shl i64 %21, 6
  %23 = getelementptr inbounds nuw i8, ptr %19, i64 %22
  %24 = shl i64 %21, 3
  %25 = getelementptr inbounds nuw i8, ptr %2, i64 %24
  tail call void @llvm.experimental.noalias.scope.decl(metadata !630)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !633)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !635)
  br label %26

26:                                               ; preds = %20, %26
  %27 = phi i64 [ 0, %20 ], [ %45, %26 ]
  %28 = shl nuw nsw i64 %27, 2
  %29 = getelementptr inbounds nuw i32, ptr %23, i64 %28
  %30 = load <4 x i32>, ptr %29, align 4, !alias.scope !637, !noalias !638
  %31 = getelementptr inbounds nuw i32, ptr %25, i64 %28
  %32 = load <4 x i32>, ptr %31, align 4, !alias.scope !639, !noalias !640
  %33 = xor <4 x i32> %32, %30
  %34 = bitcast <4 x i32> %33 to <2 x i64>
  %35 = trunc <2 x i64> %34 to <2 x i32>
  %36 = lshr <2 x i64> %34, splat (i64 32)
  %37 = trunc nuw <2 x i64> %36 to <2 x i32>
  %38 = bitcast <4 x i32> %30 to <2 x i64>
  %39 = shufflevector <2 x i64> %38, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %40 = getelementptr inbounds nuw <2 x i64>, ptr %5, i64 %27
  %41 = load <2 x i64>, ptr %40, align 16, !tbaa !21, !alias.scope !630, !noalias !641
  %42 = add <2 x i64> %41, %39
  %43 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %35, <2 x i32> %37)
  %44 = add <2 x i64> %42, %43
  store <2 x i64> %44, ptr %40, align 16, !tbaa !21, !alias.scope !630, !noalias !641
  %45 = add nuw nsw i64 %27, 1
  %46 = icmp eq i64 %45, 4
  br i1 %46, label %47, label %26, !llvm.loop !82

47:                                               ; preds = %26
  %48 = add nuw nsw i64 %21, 1
  %49 = icmp eq i64 %48, %15
  br i1 %49, label %50, label %20, !llvm.loop !83

50:                                               ; preds = %47, %16
  tail call void @llvm.experimental.noalias.scope.decl(metadata !642)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !645)
  br label %51

51:                                               ; preds = %50, %51
  %52 = phi i64 [ 0, %50 ], [ %68, %51 ]
  %53 = getelementptr inbounds nuw <2 x i64>, ptr %5, i64 %52
  %54 = load <2 x i64>, ptr %53, align 16, !tbaa !21, !alias.scope !642, !noalias !647
  %55 = lshr <2 x i64> %54, splat (i64 47)
  %56 = xor <2 x i64> %55, %54
  %57 = shl nuw nsw i64 %52, 4
  %58 = getelementptr inbounds nuw i8, ptr %14, i64 %57
  %59 = load <4 x i32>, ptr %58, align 4, !alias.scope !648, !noalias !649
  %60 = bitcast <2 x i64> %56 to <4 x i32>
  %61 = xor <4 x i32> %59, %60
  %62 = shufflevector <4 x i32> %61, <4 x i32> poison, <2 x i32> <i32 0, i32 2>
  %63 = shufflevector <4 x i32> %61, <4 x i32> poison, <2 x i32> <i32 1, i32 3>
  %64 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %63, <2 x i32> splat (i32 -1640531535))
  %65 = shl <2 x i64> %64, splat (i64 32)
  %66 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %62, <2 x i32> splat (i32 -1640531535))
  %67 = add <2 x i64> %65, %66
  store <2 x i64> %67, ptr %53, align 16, !tbaa !21, !alias.scope !642, !noalias !647
  %68 = add nuw nsw i64 %52, 1
  %69 = icmp eq i64 %68, 4
  br i1 %69, label %70, label %51, !llvm.loop !89

70:                                               ; preds = %51
  %71 = add nuw i64 %17, 1
  %72 = icmp ult i64 %71, %9
  br i1 %72, label %16, label %73, !llvm.loop !90

73:                                               ; preds = %70, %4
  %74 = mul i64 %9, %8
  %75 = sub i64 %1, %74
  %76 = lshr i64 %75, 6
  %77 = getelementptr inbounds nuw i8, ptr %0, i64 %74
  %78 = icmp ult i64 %75, 64
  br i1 %78, label %109, label %79

79:                                               ; preds = %73, %106
  %80 = phi i64 [ %107, %106 ], [ 0, %73 ]
  %81 = shl i64 %80, 6
  %82 = getelementptr inbounds nuw i8, ptr %77, i64 %81
  %83 = shl i64 %80, 3
  %84 = getelementptr inbounds nuw i8, ptr %2, i64 %83
  tail call void @llvm.experimental.noalias.scope.decl(metadata !650)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !653)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !655)
  br label %85

85:                                               ; preds = %79, %85
  %86 = phi i64 [ 0, %79 ], [ %104, %85 ]
  %87 = shl nuw nsw i64 %86, 2
  %88 = getelementptr inbounds nuw i32, ptr %82, i64 %87
  %89 = load <4 x i32>, ptr %88, align 4, !alias.scope !657, !noalias !658
  %90 = getelementptr inbounds nuw i32, ptr %84, i64 %87
  %91 = load <4 x i32>, ptr %90, align 4, !alias.scope !659, !noalias !660
  %92 = xor <4 x i32> %91, %89
  %93 = bitcast <4 x i32> %92 to <2 x i64>
  %94 = trunc <2 x i64> %93 to <2 x i32>
  %95 = lshr <2 x i64> %93, splat (i64 32)
  %96 = trunc nuw <2 x i64> %95 to <2 x i32>
  %97 = bitcast <4 x i32> %89 to <2 x i64>
  %98 = shufflevector <2 x i64> %97, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %99 = getelementptr inbounds nuw <2 x i64>, ptr %5, i64 %86
  %100 = load <2 x i64>, ptr %99, align 16, !tbaa !21, !alias.scope !650, !noalias !661
  %101 = add <2 x i64> %100, %98
  %102 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %94, <2 x i32> %96)
  %103 = add <2 x i64> %101, %102
  store <2 x i64> %103, ptr %99, align 16, !tbaa !21, !alias.scope !650, !noalias !661
  %104 = add nuw nsw i64 %86, 1
  %105 = icmp eq i64 %104, 4
  br i1 %105, label %106, label %85, !llvm.loop !82

106:                                              ; preds = %85
  %107 = add nuw nsw i64 %80, 1
  %108 = icmp samesign ult i64 %107, %76
  br i1 %108, label %79, label %109, !llvm.loop !83

109:                                              ; preds = %106, %73
  %110 = and i64 %1, 63
  %111 = icmp eq i64 %110, 0
  br i1 %111, label %138, label %112

112:                                              ; preds = %109
  %113 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %114 = getelementptr inbounds i8, ptr %113, i64 -64
  %115 = getelementptr inbounds nuw i8, ptr %2, i64 %3
  %116 = getelementptr inbounds i8, ptr %115, i64 -71
  tail call void @llvm.experimental.noalias.scope.decl(metadata !662)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !665)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !667)
  br label %117

117:                                              ; preds = %112, %117
  %118 = phi i64 [ 0, %112 ], [ %136, %117 ]
  %119 = shl nuw nsw i64 %118, 2
  %120 = getelementptr inbounds nuw i32, ptr %114, i64 %119
  %121 = load <4 x i32>, ptr %120, align 4, !alias.scope !669, !noalias !670
  %122 = getelementptr inbounds nuw i32, ptr %116, i64 %119
  %123 = load <4 x i32>, ptr %122, align 4, !alias.scope !671, !noalias !672
  %124 = xor <4 x i32> %123, %121
  %125 = bitcast <4 x i32> %124 to <2 x i64>
  %126 = trunc <2 x i64> %125 to <2 x i32>
  %127 = lshr <2 x i64> %125, splat (i64 32)
  %128 = trunc nuw <2 x i64> %127 to <2 x i32>
  %129 = bitcast <4 x i32> %121 to <2 x i64>
  %130 = shufflevector <2 x i64> %129, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %131 = getelementptr inbounds nuw <2 x i64>, ptr %5, i64 %118
  %132 = load <2 x i64>, ptr %131, align 16, !tbaa !21, !alias.scope !662, !noalias !673
  %133 = add <2 x i64> %132, %130
  %134 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %126, <2 x i32> %128)
  %135 = add <2 x i64> %133, %134
  store <2 x i64> %135, ptr %131, align 16, !tbaa !21, !alias.scope !662, !noalias !673
  %136 = add nuw nsw i64 %118, 1
  %137 = icmp eq i64 %136, 4
  br i1 %137, label %138, label %117, !llvm.loop !82

138:                                              ; preds = %117, %109
  %139 = getelementptr inbounds nuw i8, ptr %2, i64 11
  %140 = mul i64 %1, -7046029288634856825
  tail call void @llvm.experimental.noalias.scope.decl(metadata !674)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !677)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !679), !noalias !624
  %141 = load i64, ptr %5, align 16, !tbaa !22, !alias.scope !682, !noalias !683
  %142 = load i64, ptr %139, align 1, !alias.scope !677, !noalias !685
  %143 = xor i64 %142, %141
  %144 = getelementptr inbounds nuw i8, ptr %5, i64 8
  %145 = load i64, ptr %144, align 8, !tbaa !22, !alias.scope !682, !noalias !683
  %146 = getelementptr inbounds nuw i8, ptr %2, i64 19
  %147 = load i64, ptr %146, align 1, !alias.scope !677, !noalias !685
  %148 = xor i64 %147, %145
  %149 = zext i64 %143 to i128
  %150 = zext i64 %148 to i128
  %151 = mul nuw i128 %150, %149
  %152 = lshr i128 %151, 64
  %153 = xor i128 %152, %151
  %154 = trunc i128 %153 to i64
  %155 = add i64 %140, %154
  %156 = getelementptr inbounds nuw i8, ptr %5, i64 16
  %157 = getelementptr inbounds nuw i8, ptr %2, i64 27
  tail call void @llvm.experimental.noalias.scope.decl(metadata !686), !noalias !624
  %158 = load i64, ptr %156, align 16, !tbaa !22, !alias.scope !689, !noalias !690
  %159 = load i64, ptr %157, align 1, !alias.scope !677, !noalias !692
  %160 = xor i64 %159, %158
  %161 = getelementptr inbounds nuw i8, ptr %5, i64 24
  %162 = load i64, ptr %161, align 8, !tbaa !22, !alias.scope !689, !noalias !690
  %163 = getelementptr inbounds nuw i8, ptr %2, i64 35
  %164 = load i64, ptr %163, align 1, !alias.scope !677, !noalias !692
  %165 = xor i64 %164, %162
  %166 = zext i64 %160 to i128
  %167 = zext i64 %165 to i128
  %168 = mul nuw i128 %167, %166
  %169 = lshr i128 %168, 64
  %170 = xor i128 %169, %168
  %171 = trunc i128 %170 to i64
  %172 = add i64 %155, %171
  %173 = getelementptr inbounds nuw i8, ptr %5, i64 32
  %174 = getelementptr inbounds nuw i8, ptr %2, i64 43
  tail call void @llvm.experimental.noalias.scope.decl(metadata !693), !noalias !624
  %175 = load i64, ptr %173, align 16, !tbaa !22, !alias.scope !696, !noalias !697
  %176 = load i64, ptr %174, align 1, !alias.scope !677, !noalias !699
  %177 = xor i64 %176, %175
  %178 = getelementptr inbounds nuw i8, ptr %5, i64 40
  %179 = load i64, ptr %178, align 8, !tbaa !22, !alias.scope !696, !noalias !697
  %180 = getelementptr inbounds nuw i8, ptr %2, i64 51
  %181 = load i64, ptr %180, align 1, !alias.scope !677, !noalias !699
  %182 = xor i64 %181, %179
  %183 = zext i64 %177 to i128
  %184 = zext i64 %182 to i128
  %185 = mul nuw i128 %184, %183
  %186 = lshr i128 %185, 64
  %187 = xor i128 %186, %185
  %188 = trunc i128 %187 to i64
  %189 = add i64 %172, %188
  %190 = getelementptr inbounds nuw i8, ptr %5, i64 48
  %191 = getelementptr inbounds nuw i8, ptr %2, i64 59
  tail call void @llvm.experimental.noalias.scope.decl(metadata !700), !noalias !624
  %192 = load i64, ptr %190, align 16, !tbaa !22, !alias.scope !703, !noalias !704
  %193 = load i64, ptr %191, align 1, !alias.scope !677, !noalias !706
  %194 = xor i64 %193, %192
  %195 = getelementptr inbounds nuw i8, ptr %5, i64 56
  %196 = load i64, ptr %195, align 8, !tbaa !22, !alias.scope !703, !noalias !704
  %197 = getelementptr inbounds nuw i8, ptr %2, i64 67
  %198 = load i64, ptr %197, align 1, !alias.scope !677, !noalias !706
  %199 = xor i64 %198, %196
  %200 = zext i64 %194 to i128
  %201 = zext i64 %199 to i128
  %202 = mul nuw i128 %201, %200
  %203 = lshr i128 %202, 64
  %204 = xor i128 %203, %202
  %205 = trunc i128 %204 to i64
  %206 = add i64 %189, %205
  %207 = lshr i64 %206, 37
  %208 = xor i64 %207, %206
  %209 = mul i64 %208, 1609587929392839161
  %210 = lshr i64 %209, 32
  %211 = xor i64 %210, %209
  %212 = getelementptr inbounds nuw i8, ptr %2, i64 %3
  %213 = getelementptr inbounds i8, ptr %212, i64 -75
  %214 = mul i64 %1, -4417276706812531889
  %215 = xor i64 %214, -1
  %216 = load i64, ptr %213, align 1, !alias.scope !707, !noalias !710
  %217 = xor i64 %216, %141
  %218 = getelementptr inbounds i8, ptr %212, i64 -67
  %219 = load i64, ptr %218, align 1, !alias.scope !707, !noalias !710
  %220 = xor i64 %219, %145
  %221 = zext i64 %217 to i128
  %222 = zext i64 %220 to i128
  %223 = mul nuw i128 %222, %221
  %224 = lshr i128 %223, 64
  %225 = xor i128 %224, %223
  %226 = trunc i128 %225 to i64
  %227 = add i64 %226, %215
  %228 = getelementptr inbounds i8, ptr %212, i64 -59
  %229 = load i64, ptr %228, align 1, !alias.scope !707, !noalias !714
  %230 = xor i64 %229, %158
  %231 = getelementptr inbounds i8, ptr %212, i64 -51
  %232 = load i64, ptr %231, align 1, !alias.scope !707, !noalias !714
  %233 = xor i64 %232, %162
  %234 = zext i64 %230 to i128
  %235 = zext i64 %233 to i128
  %236 = mul nuw i128 %235, %234
  %237 = lshr i128 %236, 64
  %238 = xor i128 %237, %236
  %239 = trunc i128 %238 to i64
  %240 = add i64 %227, %239
  %241 = getelementptr inbounds i8, ptr %212, i64 -43
  %242 = load i64, ptr %241, align 1, !alias.scope !707, !noalias !717
  %243 = xor i64 %242, %175
  %244 = getelementptr inbounds i8, ptr %212, i64 -35
  %245 = load i64, ptr %244, align 1, !alias.scope !707, !noalias !717
  %246 = xor i64 %245, %179
  %247 = zext i64 %243 to i128
  %248 = zext i64 %246 to i128
  %249 = mul nuw i128 %248, %247
  %250 = lshr i128 %249, 64
  %251 = xor i128 %250, %249
  %252 = trunc i128 %251 to i64
  %253 = add i64 %240, %252
  %254 = getelementptr inbounds i8, ptr %212, i64 -27
  %255 = load i64, ptr %254, align 1, !alias.scope !707, !noalias !720
  %256 = xor i64 %255, %192
  %257 = getelementptr inbounds i8, ptr %212, i64 -19
  %258 = load i64, ptr %257, align 1, !alias.scope !707, !noalias !720
  %259 = xor i64 %258, %196
  %260 = zext i64 %256 to i128
  %261 = zext i64 %259 to i128
  %262 = mul nuw i128 %261, %260
  %263 = lshr i128 %262, 64
  %264 = xor i128 %263, %262
  %265 = trunc i128 %264 to i64
  %266 = add i64 %253, %265
  %267 = lshr i64 %266, 37
  %268 = xor i64 %267, %266
  %269 = mul i64 %268, 1609587929392839161
  %270 = lshr i64 %269, 32
  %271 = xor i64 %270, %269
  call void @llvm.lifetime.end.p0(i64 64, ptr nonnull %5) #24, !noalias !629
  %272 = insertvalue [2 x i64] poison, i64 %211, 0
  %273 = insertvalue [2 x i64] %272, i64 %271, 1
  ret [2 x i64] %273
}

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync)
define [2 x i64] @XXH3_128bits_withSeed(ptr noundef readonly captures(none) %0, i64 noundef %1, i64 noundef %2) local_unnamed_addr #13 {
  %4 = icmp ult i64 %1, 17
  br i1 %4, label %5, label %127

5:                                                ; preds = %3
  %6 = icmp samesign ugt i64 %1, 8
  br i1 %6, label %7, label %43

7:                                                ; preds = %5
  %8 = load i64, ptr %0, align 1
  %9 = add i64 %2, -4734510112055689544
  %10 = xor i64 %8, %9
  %11 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %12 = getelementptr inbounds i8, ptr %11, i64 -8
  %13 = load i64, ptr %12, align 1
  %14 = sub i64 2066345149520216444, %2
  %15 = xor i64 %13, %14
  %16 = xor i64 %10, %15
  %17 = zext i64 %16 to i128
  %18 = mul nuw i128 %17, 11400714785074694791
  %19 = trunc i128 %18 to i64
  %20 = lshr i128 %18, 64
  %21 = trunc nuw i128 %20 to i64
  %22 = mul i64 %15, -7046029288634856825
  %23 = add i64 %22, %21
  %24 = lshr i64 %23, 32
  %25 = xor i64 %24, %19
  %26 = zext i64 %25 to i128
  %27 = mul nuw i128 %26, 14029467366897019727
  %28 = trunc i128 %27 to i64
  %29 = lshr i128 %27, 64
  %30 = trunc nuw i128 %29 to i64
  %31 = mul i64 %23, -4417276706812531889
  %32 = add i64 %31, %30
  %33 = lshr i64 %28, 37
  %34 = xor i64 %33, %28
  %35 = mul i64 %34, 1609587929392839161
  %36 = lshr i64 %35, 32
  %37 = xor i64 %36, %35
  %38 = lshr i64 %32, 37
  %39 = xor i64 %38, %32
  %40 = mul i64 %39, 1609587929392839161
  %41 = lshr i64 %40, 32
  %42 = xor i64 %41, %40
  br label %122

43:                                               ; preds = %5
  %44 = icmp samesign ugt i64 %1, 3
  br i1 %44, label %45, label %83

45:                                               ; preds = %43
  %46 = load i32, ptr %0, align 1
  %47 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %48 = getelementptr inbounds i8, ptr %47, i64 -4
  %49 = load i32, ptr %48, align 1
  %50 = zext i32 %46 to i64
  %51 = zext i32 %49 to i64
  %52 = shl nuw i64 %51, 32
  %53 = or disjoint i64 %52, %50
  %54 = tail call noundef i64 @llvm.bswap.i64(i64 %53)
  %55 = add i64 %2, -4734510112055689544
  %56 = xor i64 %53, %55
  %57 = sub i64 2066345149520216444, %2
  %58 = xor i64 %54, %57
  %59 = lshr i64 %56, 51
  %60 = xor i64 %59, %56
  %61 = mul i64 %60, 2654435761
  %62 = add i64 %61, %1
  %63 = lshr i64 %62, 47
  %64 = xor i64 %63, %62
  %65 = mul i64 %64, -4417276706812531889
  %66 = lshr i64 %58, 47
  %67 = xor i64 %66, %58
  %68 = mul i64 %67, -7046029288634856825
  %69 = sub i64 %68, %1
  %70 = lshr i64 %69, 43
  %71 = xor i64 %70, %69
  %72 = mul i64 %71, -8796714831421723037
  %73 = lshr i64 %65, 37
  %74 = xor i64 %73, %65
  %75 = mul i64 %74, 1609587929392839161
  %76 = lshr i64 %75, 32
  %77 = xor i64 %76, %75
  %78 = lshr i64 %72, 37
  %79 = xor i64 %78, %72
  %80 = mul i64 %79, 1609587929392839161
  %81 = lshr i64 %80, 32
  %82 = xor i64 %81, %80
  br label %122

83:                                               ; preds = %43
  %84 = icmp eq i64 %1, 0
  br i1 %84, label %122, label %85

85:                                               ; preds = %83
  %86 = load i8, ptr %0, align 1, !tbaa !21
  %87 = lshr i64 %1, 1
  %88 = getelementptr inbounds nuw i8, ptr %0, i64 %87
  %89 = load i8, ptr %88, align 1, !tbaa !21
  %90 = getelementptr i8, ptr %0, i64 %1
  %91 = getelementptr i8, ptr %90, i64 -1
  %92 = load i8, ptr %91, align 1, !tbaa !21
  %93 = zext i8 %86 to i32
  %94 = zext i8 %89 to i32
  %95 = shl nuw nsw i32 %94, 8
  %96 = or disjoint i32 %95, %93
  %97 = zext i8 %92 to i32
  %98 = shl nuw nsw i32 %97, 16
  %99 = or disjoint i32 %96, %98
  %100 = trunc nuw nsw i64 %1 to i32
  %101 = shl nuw nsw i32 %100, 24
  %102 = or disjoint i32 %99, %101
  %103 = tail call noundef i32 @llvm.bswap.i32(i32 %102)
  %104 = zext nneg i32 %102 to i64
  %105 = add i64 %2, 963444408
  %106 = xor i64 %105, %104
  %107 = zext i32 %103 to i64
  %108 = sub i64 3192628259, %2
  %109 = xor i64 %108, %107
  %110 = mul i64 %106, -7046029288634856825
  %111 = mul i64 %109, -4417276706812531889
  %112 = lshr i64 %110, 37
  %113 = xor i64 %112, %110
  %114 = mul i64 %113, 1609587929392839161
  %115 = lshr i64 %114, 32
  %116 = xor i64 %115, %114
  %117 = lshr i64 %111, 37
  %118 = xor i64 %117, %111
  %119 = mul i64 %118, 1609587929392839161
  %120 = lshr i64 %119, 32
  %121 = xor i64 %120, %119
  br label %122

122:                                              ; preds = %7, %45, %83, %85
  %123 = phi i64 [ %42, %7 ], [ %82, %45 ], [ %121, %85 ], [ 0, %83 ]
  %124 = phi i64 [ %37, %7 ], [ %77, %45 ], [ %116, %85 ], [ 0, %83 ]
  %125 = insertvalue [2 x i64] poison, i64 %124, 0
  %126 = insertvalue [2 x i64] %125, i64 %123, 1
  br label %294

127:                                              ; preds = %3
  %128 = icmp ult i64 %1, 129
  br i1 %128, label %129, label %288

129:                                              ; preds = %127
  %130 = mul i64 %1, -7046029288634856825
  %131 = icmp samesign ugt i64 %1, 32
  br i1 %131, label %132, label %235

132:                                              ; preds = %129
  %133 = icmp samesign ugt i64 %1, 64
  br i1 %133, label %134, label %201

134:                                              ; preds = %132
  %135 = icmp samesign ugt i64 %1, 96
  br i1 %135, label %136, label %167

136:                                              ; preds = %134
  %137 = getelementptr inbounds nuw i8, ptr %0, i64 48
  %138 = load i64, ptr %137, align 1, !noalias !723
  %139 = getelementptr inbounds nuw i8, ptr %0, i64 56
  %140 = load i64, ptr %139, align 1, !noalias !723
  %141 = add i64 %2, 4554437623014685352
  %142 = xor i64 %138, %141
  %143 = sub i64 2111919702937427193, %2
  %144 = xor i64 %140, %143
  %145 = zext i64 %142 to i128
  %146 = zext i64 %144 to i128
  %147 = mul nuw i128 %146, %145
  %148 = lshr i128 %147, 64
  %149 = xor i128 %148, %147
  %150 = trunc i128 %149 to i64
  %151 = add i64 %130, %150
  %152 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %153 = getelementptr inbounds i8, ptr %152, i64 -64
  %154 = load i64, ptr %153, align 1, !noalias !726
  %155 = getelementptr inbounds i8, ptr %152, i64 -56
  %156 = load i64, ptr %155, align 1, !noalias !726
  %157 = add i64 %2, 3556072174620004746
  %158 = xor i64 %154, %157
  %159 = sub i64 7238261902898274248, %2
  %160 = xor i64 %156, %159
  %161 = zext i64 %158 to i128
  %162 = zext i64 %160 to i128
  %163 = mul nuw i128 %162, %161
  %164 = lshr i128 %163, 64
  %165 = xor i128 %164, %163
  %166 = trunc i128 %165 to i64
  br label %167

167:                                              ; preds = %136, %134
  %168 = phi i64 [ %166, %136 ], [ 0, %134 ]
  %169 = phi i64 [ %151, %136 ], [ %130, %134 ]
  %170 = getelementptr inbounds nuw i8, ptr %0, i64 32
  %171 = load i64, ptr %170, align 1, !noalias !729
  %172 = getelementptr inbounds nuw i8, ptr %0, i64 40
  %173 = load i64, ptr %172, align 1, !noalias !729
  %174 = add i64 %2, -3818837453329782724
  %175 = xor i64 %171, %174
  %176 = sub i64 -6688317018830679928, %2
  %177 = xor i64 %173, %176
  %178 = zext i64 %175 to i128
  %179 = zext i64 %177 to i128
  %180 = mul nuw i128 %179, %178
  %181 = lshr i128 %180, 64
  %182 = xor i128 %181, %180
  %183 = trunc i128 %182 to i64
  %184 = add i64 %169, %183
  %185 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %186 = getelementptr inbounds i8, ptr %185, i64 -48
  %187 = load i64, ptr %186, align 1, !noalias !732
  %188 = getelementptr inbounds i8, ptr %185, i64 -40
  %189 = load i64, ptr %188, align 1, !noalias !732
  %190 = add i64 %2, 5690594596133299313
  %191 = xor i64 %187, %190
  %192 = sub i64 -2833645246901970632, %2
  %193 = xor i64 %189, %192
  %194 = zext i64 %191 to i128
  %195 = zext i64 %193 to i128
  %196 = mul nuw i128 %195, %194
  %197 = lshr i128 %196, 64
  %198 = xor i128 %197, %196
  %199 = trunc i128 %198 to i64
  %200 = add i64 %168, %199
  br label %201

201:                                              ; preds = %167, %132
  %202 = phi i64 [ %200, %167 ], [ 0, %132 ]
  %203 = phi i64 [ %184, %167 ], [ %130, %132 ]
  %204 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %205 = load i64, ptr %204, align 1, !noalias !735
  %206 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %207 = load i64, ptr %206, align 1, !noalias !735
  %208 = add i64 %2, 8711581037947681227
  %209 = xor i64 %205, %208
  %210 = sub i64 2410270004345854594, %2
  %211 = xor i64 %207, %210
  %212 = zext i64 %209 to i128
  %213 = zext i64 %211 to i128
  %214 = mul nuw i128 %213, %212
  %215 = lshr i128 %214, 64
  %216 = xor i128 %215, %214
  %217 = trunc i128 %216 to i64
  %218 = add i64 %203, %217
  %219 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %220 = getelementptr inbounds i8, ptr %219, i64 -32
  %221 = load i64, ptr %220, align 1, !noalias !738
  %222 = getelementptr inbounds i8, ptr %219, i64 -24
  %223 = load i64, ptr %222, align 1, !noalias !738
  %224 = add i64 %2, -8204357891075471176
  %225 = xor i64 %221, %224
  %226 = sub i64 5487137525590930912, %2
  %227 = xor i64 %223, %226
  %228 = zext i64 %225 to i128
  %229 = zext i64 %227 to i128
  %230 = mul nuw i128 %229, %228
  %231 = lshr i128 %230, 64
  %232 = xor i128 %231, %230
  %233 = trunc i128 %232 to i64
  %234 = add i64 %202, %233
  br label %235

235:                                              ; preds = %129, %201
  %236 = phi i64 [ %234, %201 ], [ 0, %129 ]
  %237 = phi i64 [ %218, %201 ], [ %130, %129 ]
  %238 = load i64, ptr %0, align 1, !noalias !741
  %239 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %240 = load i64, ptr %239, align 1, !noalias !741
  %241 = add i64 %2, -4734510112055689544
  %242 = xor i64 %238, %241
  %243 = sub i64 2066345149520216444, %2
  %244 = xor i64 %240, %243
  %245 = zext i64 %242 to i128
  %246 = zext i64 %244 to i128
  %247 = mul nuw i128 %246, %245
  %248 = lshr i128 %247, 64
  %249 = xor i128 %248, %247
  %250 = trunc i128 %249 to i64
  %251 = add i64 %237, %250
  %252 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %253 = getelementptr inbounds i8, ptr %252, i64 -16
  %254 = load i64, ptr %253, align 1, !noalias !744
  %255 = getelementptr inbounds i8, ptr %252, i64 -8
  %256 = load i64, ptr %255, align 1, !noalias !744
  %257 = add i64 %2, -2623469361688619810
  %258 = xor i64 %254, %257
  %259 = sub i64 2262974939099578482, %2
  %260 = xor i64 %256, %259
  %261 = zext i64 %258 to i128
  %262 = zext i64 %260 to i128
  %263 = mul nuw i128 %262, %261
  %264 = lshr i128 %263, 64
  %265 = xor i128 %264, %263
  %266 = trunc i128 %265 to i64
  %267 = add i64 %236, %266
  %268 = add i64 %267, %251
  %269 = mul i64 %251, -7046029288634856825
  %270 = mul i64 %267, -8796714831421723037
  %271 = sub i64 %1, %2
  %272 = mul i64 %271, -4417276706812531889
  %273 = add i64 %269, %272
  %274 = add i64 %273, %270
  %275 = lshr i64 %268, 37
  %276 = xor i64 %275, %268
  %277 = mul i64 %276, 1609587929392839161
  %278 = lshr i64 %277, 32
  %279 = xor i64 %278, %277
  %280 = lshr i64 %274, 37
  %281 = xor i64 %280, %274
  %282 = mul i64 %281, 1609587929392839161
  %283 = lshr i64 %282, 32
  %284 = xor i64 %283, %282
  %285 = sub i64 0, %284
  %286 = insertvalue [2 x i64] poison, i64 %279, 0
  %287 = insertvalue [2 x i64] %286, i64 %285, 1
  br label %294

288:                                              ; preds = %127
  %289 = icmp ult i64 %1, 241
  br i1 %289, label %290, label %292

290:                                              ; preds = %288
  %291 = tail call fastcc [2 x i64] @XXH3_len_129to240_128b(ptr noundef %0, i64 noundef %1, ptr noundef nonnull @kSecret, i64 noundef %2)
  br label %294

292:                                              ; preds = %288
  %293 = tail call fastcc [2 x i64] @XXH3_hashLong_128b_withSeed(ptr noundef %0, i64 noundef %1, i64 noundef %2)
  br label %294

294:                                              ; preds = %292, %290, %235, %122
  %295 = phi [2 x i64] [ %126, %122 ], [ %287, %235 ], [ %291, %290 ], [ %293, %292 ]
  ret [2 x i64] %295
}

; Function Attrs: nofree noinline norecurse nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync)
define internal fastcc [2 x i64] @XXH3_hashLong_128b_withSeed(ptr noundef readonly captures(none) %0, i64 noundef range(i64 241, 0) %1, i64 noundef %2) unnamed_addr #14 {
  %4 = alloca [8 x i64], align 16
  %5 = alloca [192 x i8], align 8
  call void @llvm.lifetime.start.p0(i64 192, ptr nonnull %5) #24
  %6 = icmp eq i64 %2, 0
  br i1 %6, label %7, label %9

7:                                                ; preds = %3
  %8 = tail call fastcc [2 x i64] @XXH3_hashLong_128b_defaultSecret(ptr noundef %0, i64 noundef %1)
  br label %283

9:                                                ; preds = %3, %9
  %10 = phi i64 [ %20, %9 ], [ 0, %3 ]
  %11 = shl nuw nsw i64 %10, 4
  %12 = getelementptr inbounds nuw i8, ptr %5, i64 %11
  %13 = getelementptr inbounds nuw i8, ptr @kSecret, i64 %11
  %14 = load i64, ptr %13, align 16
  %15 = add i64 %14, %2
  store i64 %15, ptr %12, align 8
  %16 = getelementptr inbounds nuw i8, ptr %12, i64 8
  %17 = getelementptr inbounds nuw i8, ptr %13, i64 8
  %18 = load i64, ptr %17, align 8
  %19 = sub i64 %18, %2
  store i64 %19, ptr %16, align 8
  %20 = add nuw nsw i64 %10, 1
  %21 = icmp eq i64 %20, 12
  br i1 %21, label %22, label %9, !llvm.loop !250

22:                                               ; preds = %9
  tail call void @llvm.experimental.noalias.scope.decl(metadata !747)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !750)
  call void @llvm.lifetime.start.p0(i64 64, ptr nonnull %4) #24, !noalias !752
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(64) %4, ptr noundef nonnull align 16 dereferenceable(64) @__const.XXH3_hashLong_128b_internal.acc, i64 64, i1 false), !noalias !752
  %23 = lshr i64 %1, 10
  %24 = icmp ult i64 %1, 1024
  br i1 %24, label %84, label %25

25:                                               ; preds = %22
  %26 = getelementptr inbounds nuw i8, ptr %5, i64 128
  br label %27

27:                                               ; preds = %25, %81
  %28 = phi i64 [ 0, %25 ], [ %82, %81 ]
  %29 = shl i64 %28, 10
  %30 = getelementptr inbounds nuw i8, ptr %0, i64 %29
  br label %31

31:                                               ; preds = %27, %58
  %32 = phi i64 [ 0, %27 ], [ %59, %58 ]
  %33 = shl nuw nsw i64 %32, 6
  %34 = getelementptr inbounds nuw i8, ptr %30, i64 %33
  %35 = shl nuw nsw i64 %32, 3
  %36 = getelementptr inbounds nuw i8, ptr %5, i64 %35
  tail call void @llvm.experimental.noalias.scope.decl(metadata !753)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !756)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !758)
  br label %37

37:                                               ; preds = %31, %37
  %38 = phi i64 [ 0, %31 ], [ %56, %37 ]
  %39 = shl nuw nsw i64 %38, 2
  %40 = getelementptr inbounds nuw i32, ptr %34, i64 %39
  %41 = load <4 x i32>, ptr %40, align 4, !alias.scope !760, !noalias !761
  %42 = getelementptr inbounds nuw i32, ptr %36, i64 %39
  %43 = load <4 x i32>, ptr %42, align 8, !alias.scope !762, !noalias !763
  %44 = xor <4 x i32> %43, %41
  %45 = bitcast <4 x i32> %44 to <2 x i64>
  %46 = trunc <2 x i64> %45 to <2 x i32>
  %47 = lshr <2 x i64> %45, splat (i64 32)
  %48 = trunc nuw <2 x i64> %47 to <2 x i32>
  %49 = bitcast <4 x i32> %41 to <2 x i64>
  %50 = shufflevector <2 x i64> %49, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %51 = getelementptr inbounds nuw <2 x i64>, ptr %4, i64 %38
  %52 = load <2 x i64>, ptr %51, align 16, !tbaa !21, !alias.scope !753, !noalias !764
  %53 = add <2 x i64> %52, %50
  %54 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %46, <2 x i32> %48)
  %55 = add <2 x i64> %53, %54
  store <2 x i64> %55, ptr %51, align 16, !tbaa !21, !alias.scope !753, !noalias !764
  %56 = add nuw nsw i64 %38, 1
  %57 = icmp eq i64 %56, 4
  br i1 %57, label %58, label %37, !llvm.loop !82

58:                                               ; preds = %37
  %59 = add nuw nsw i64 %32, 1
  %60 = icmp eq i64 %59, 16
  br i1 %60, label %61, label %31, !llvm.loop !83

61:                                               ; preds = %58
  tail call void @llvm.experimental.noalias.scope.decl(metadata !765)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !768)
  br label %62

62:                                               ; preds = %61, %62
  %63 = phi i64 [ 0, %61 ], [ %79, %62 ]
  %64 = getelementptr inbounds nuw <2 x i64>, ptr %4, i64 %63
  %65 = load <2 x i64>, ptr %64, align 16, !tbaa !21, !alias.scope !765, !noalias !770
  %66 = lshr <2 x i64> %65, splat (i64 47)
  %67 = xor <2 x i64> %66, %65
  %68 = shl nuw nsw i64 %63, 4
  %69 = getelementptr inbounds nuw i8, ptr %26, i64 %68
  %70 = load <4 x i32>, ptr %69, align 8, !alias.scope !771, !noalias !772
  %71 = bitcast <2 x i64> %67 to <4 x i32>
  %72 = xor <4 x i32> %70, %71
  %73 = shufflevector <4 x i32> %72, <4 x i32> poison, <2 x i32> <i32 0, i32 2>
  %74 = shufflevector <4 x i32> %72, <4 x i32> poison, <2 x i32> <i32 1, i32 3>
  %75 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %74, <2 x i32> splat (i32 -1640531535))
  %76 = shl <2 x i64> %75, splat (i64 32)
  %77 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %73, <2 x i32> splat (i32 -1640531535))
  %78 = add <2 x i64> %76, %77
  store <2 x i64> %78, ptr %64, align 16, !tbaa !21, !alias.scope !765, !noalias !770
  %79 = add nuw nsw i64 %63, 1
  %80 = icmp eq i64 %79, 4
  br i1 %80, label %81, label %62, !llvm.loop !89

81:                                               ; preds = %62
  %82 = add nuw nsw i64 %28, 1
  %83 = icmp eq i64 %82, %23
  br i1 %83, label %84, label %27, !llvm.loop !90

84:                                               ; preds = %81, %22
  %85 = and i64 %1, -1024
  %86 = lshr i64 %1, 6
  %87 = and i64 %86, 15
  %88 = getelementptr inbounds nuw i8, ptr %0, i64 %85
  %89 = icmp eq i64 %87, 0
  br i1 %89, label %120, label %90

90:                                               ; preds = %84, %117
  %91 = phi i64 [ %118, %117 ], [ 0, %84 ]
  %92 = shl i64 %91, 6
  %93 = getelementptr inbounds nuw i8, ptr %88, i64 %92
  %94 = shl i64 %91, 3
  %95 = getelementptr inbounds nuw i8, ptr %5, i64 %94
  tail call void @llvm.experimental.noalias.scope.decl(metadata !773)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !776)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !778)
  br label %96

96:                                               ; preds = %90, %96
  %97 = phi i64 [ 0, %90 ], [ %115, %96 ]
  %98 = shl nuw nsw i64 %97, 2
  %99 = getelementptr inbounds nuw i32, ptr %93, i64 %98
  %100 = load <4 x i32>, ptr %99, align 4, !alias.scope !780, !noalias !781
  %101 = getelementptr inbounds nuw i32, ptr %95, i64 %98
  %102 = load <4 x i32>, ptr %101, align 8, !alias.scope !782, !noalias !783
  %103 = xor <4 x i32> %102, %100
  %104 = bitcast <4 x i32> %103 to <2 x i64>
  %105 = trunc <2 x i64> %104 to <2 x i32>
  %106 = lshr <2 x i64> %104, splat (i64 32)
  %107 = trunc nuw <2 x i64> %106 to <2 x i32>
  %108 = bitcast <4 x i32> %100 to <2 x i64>
  %109 = shufflevector <2 x i64> %108, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %110 = getelementptr inbounds nuw <2 x i64>, ptr %4, i64 %97
  %111 = load <2 x i64>, ptr %110, align 16, !tbaa !21, !alias.scope !773, !noalias !784
  %112 = add <2 x i64> %111, %109
  %113 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %105, <2 x i32> %107)
  %114 = add <2 x i64> %112, %113
  store <2 x i64> %114, ptr %110, align 16, !tbaa !21, !alias.scope !773, !noalias !784
  %115 = add nuw nsw i64 %97, 1
  %116 = icmp eq i64 %115, 4
  br i1 %116, label %117, label %96, !llvm.loop !82

117:                                              ; preds = %96
  %118 = add nuw nsw i64 %91, 1
  %119 = icmp eq i64 %118, %87
  br i1 %119, label %120, label %90, !llvm.loop !83

120:                                              ; preds = %117, %84
  %121 = and i64 %1, 63
  %122 = icmp eq i64 %121, 0
  br i1 %122, label %148, label %123

123:                                              ; preds = %120
  %124 = getelementptr inbounds nuw i8, ptr %0, i64 %1
  %125 = getelementptr inbounds i8, ptr %124, i64 -64
  %126 = getelementptr inbounds nuw i8, ptr %5, i64 121
  tail call void @llvm.experimental.noalias.scope.decl(metadata !785)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !788)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !790)
  br label %127

127:                                              ; preds = %123, %127
  %128 = phi i64 [ 0, %123 ], [ %146, %127 ]
  %129 = shl nuw nsw i64 %128, 2
  %130 = getelementptr inbounds nuw i32, ptr %125, i64 %129
  %131 = load <4 x i32>, ptr %130, align 4, !alias.scope !792, !noalias !793
  %132 = getelementptr inbounds nuw i32, ptr %126, i64 %129
  %133 = load <4 x i32>, ptr %132, align 4, !alias.scope !794, !noalias !795
  %134 = xor <4 x i32> %133, %131
  %135 = bitcast <4 x i32> %134 to <2 x i64>
  %136 = trunc <2 x i64> %135 to <2 x i32>
  %137 = lshr <2 x i64> %135, splat (i64 32)
  %138 = trunc nuw <2 x i64> %137 to <2 x i32>
  %139 = bitcast <4 x i32> %131 to <2 x i64>
  %140 = shufflevector <2 x i64> %139, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %141 = getelementptr inbounds nuw <2 x i64>, ptr %4, i64 %128
  %142 = load <2 x i64>, ptr %141, align 16, !tbaa !21, !alias.scope !785, !noalias !796
  %143 = add <2 x i64> %142, %140
  %144 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %136, <2 x i32> %138)
  %145 = add <2 x i64> %143, %144
  store <2 x i64> %145, ptr %141, align 16, !tbaa !21, !alias.scope !785, !noalias !796
  %146 = add nuw nsw i64 %128, 1
  %147 = icmp eq i64 %146, 4
  br i1 %147, label %148, label %127, !llvm.loop !82

148:                                              ; preds = %127, %120
  %149 = getelementptr inbounds nuw i8, ptr %5, i64 11
  %150 = mul i64 %1, -7046029288634856825
  tail call void @llvm.experimental.noalias.scope.decl(metadata !797)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !800)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !802), !noalias !747
  %151 = load i64, ptr %4, align 16, !tbaa !22, !alias.scope !805, !noalias !806
  %152 = load i64, ptr %149, align 1, !alias.scope !800, !noalias !808
  %153 = xor i64 %152, %151
  %154 = getelementptr inbounds nuw i8, ptr %4, i64 8
  %155 = load i64, ptr %154, align 8, !tbaa !22, !alias.scope !805, !noalias !806
  %156 = getelementptr inbounds nuw i8, ptr %5, i64 19
  %157 = load i64, ptr %156, align 1, !alias.scope !800, !noalias !808
  %158 = xor i64 %157, %155
  %159 = zext i64 %153 to i128
  %160 = zext i64 %158 to i128
  %161 = mul nuw i128 %160, %159
  %162 = lshr i128 %161, 64
  %163 = xor i128 %162, %161
  %164 = trunc i128 %163 to i64
  %165 = add i64 %150, %164
  %166 = getelementptr inbounds nuw i8, ptr %4, i64 16
  %167 = getelementptr inbounds nuw i8, ptr %5, i64 27
  tail call void @llvm.experimental.noalias.scope.decl(metadata !809), !noalias !747
  %168 = load i64, ptr %166, align 16, !tbaa !22, !alias.scope !812, !noalias !813
  %169 = load i64, ptr %167, align 1, !alias.scope !800, !noalias !815
  %170 = xor i64 %169, %168
  %171 = getelementptr inbounds nuw i8, ptr %4, i64 24
  %172 = load i64, ptr %171, align 8, !tbaa !22, !alias.scope !812, !noalias !813
  %173 = getelementptr inbounds nuw i8, ptr %5, i64 35
  %174 = load i64, ptr %173, align 1, !alias.scope !800, !noalias !815
  %175 = xor i64 %174, %172
  %176 = zext i64 %170 to i128
  %177 = zext i64 %175 to i128
  %178 = mul nuw i128 %177, %176
  %179 = lshr i128 %178, 64
  %180 = xor i128 %179, %178
  %181 = trunc i128 %180 to i64
  %182 = add i64 %165, %181
  %183 = getelementptr inbounds nuw i8, ptr %4, i64 32
  %184 = getelementptr inbounds nuw i8, ptr %5, i64 43
  tail call void @llvm.experimental.noalias.scope.decl(metadata !816), !noalias !747
  %185 = load i64, ptr %183, align 16, !tbaa !22, !alias.scope !819, !noalias !820
  %186 = load i64, ptr %184, align 1, !alias.scope !800, !noalias !822
  %187 = xor i64 %186, %185
  %188 = getelementptr inbounds nuw i8, ptr %4, i64 40
  %189 = load i64, ptr %188, align 8, !tbaa !22, !alias.scope !819, !noalias !820
  %190 = getelementptr inbounds nuw i8, ptr %5, i64 51
  %191 = load i64, ptr %190, align 1, !alias.scope !800, !noalias !822
  %192 = xor i64 %191, %189
  %193 = zext i64 %187 to i128
  %194 = zext i64 %192 to i128
  %195 = mul nuw i128 %194, %193
  %196 = lshr i128 %195, 64
  %197 = xor i128 %196, %195
  %198 = trunc i128 %197 to i64
  %199 = add i64 %182, %198
  %200 = getelementptr inbounds nuw i8, ptr %4, i64 48
  %201 = getelementptr inbounds nuw i8, ptr %5, i64 59
  tail call void @llvm.experimental.noalias.scope.decl(metadata !823), !noalias !747
  %202 = load i64, ptr %200, align 16, !tbaa !22, !alias.scope !826, !noalias !827
  %203 = load i64, ptr %201, align 1, !alias.scope !800, !noalias !829
  %204 = xor i64 %203, %202
  %205 = getelementptr inbounds nuw i8, ptr %4, i64 56
  %206 = load i64, ptr %205, align 8, !tbaa !22, !alias.scope !826, !noalias !827
  %207 = getelementptr inbounds nuw i8, ptr %5, i64 67
  %208 = load i64, ptr %207, align 1, !alias.scope !800, !noalias !829
  %209 = xor i64 %208, %206
  %210 = zext i64 %204 to i128
  %211 = zext i64 %209 to i128
  %212 = mul nuw i128 %211, %210
  %213 = lshr i128 %212, 64
  %214 = xor i128 %213, %212
  %215 = trunc i128 %214 to i64
  %216 = add i64 %199, %215
  %217 = lshr i64 %216, 37
  %218 = xor i64 %217, %216
  %219 = mul i64 %218, 1609587929392839161
  %220 = lshr i64 %219, 32
  %221 = xor i64 %220, %219
  %222 = getelementptr inbounds nuw i8, ptr %5, i64 117
  %223 = mul i64 %1, -4417276706812531889
  %224 = xor i64 %223, -1
  %225 = load i64, ptr %222, align 1, !alias.scope !830, !noalias !833
  %226 = xor i64 %225, %151
  %227 = getelementptr inbounds nuw i8, ptr %5, i64 125
  %228 = load i64, ptr %227, align 1, !alias.scope !830, !noalias !833
  %229 = xor i64 %228, %155
  %230 = zext i64 %226 to i128
  %231 = zext i64 %229 to i128
  %232 = mul nuw i128 %231, %230
  %233 = lshr i128 %232, 64
  %234 = xor i128 %233, %232
  %235 = trunc i128 %234 to i64
  %236 = add i64 %235, %224
  %237 = getelementptr inbounds nuw i8, ptr %5, i64 133
  %238 = load i64, ptr %237, align 1, !alias.scope !830, !noalias !837
  %239 = xor i64 %238, %168
  %240 = getelementptr inbounds nuw i8, ptr %5, i64 141
  %241 = load i64, ptr %240, align 1, !alias.scope !830, !noalias !837
  %242 = xor i64 %241, %172
  %243 = zext i64 %239 to i128
  %244 = zext i64 %242 to i128
  %245 = mul nuw i128 %244, %243
  %246 = lshr i128 %245, 64
  %247 = xor i128 %246, %245
  %248 = trunc i128 %247 to i64
  %249 = add i64 %236, %248
  %250 = getelementptr inbounds nuw i8, ptr %5, i64 149
  %251 = load i64, ptr %250, align 1, !alias.scope !830, !noalias !840
  %252 = xor i64 %251, %185
  %253 = getelementptr inbounds nuw i8, ptr %5, i64 157
  %254 = load i64, ptr %253, align 1, !alias.scope !830, !noalias !840
  %255 = xor i64 %254, %189
  %256 = zext i64 %252 to i128
  %257 = zext i64 %255 to i128
  %258 = mul nuw i128 %257, %256
  %259 = lshr i128 %258, 64
  %260 = xor i128 %259, %258
  %261 = trunc i128 %260 to i64
  %262 = add i64 %249, %261
  %263 = getelementptr inbounds nuw i8, ptr %5, i64 165
  %264 = load i64, ptr %263, align 1, !alias.scope !830, !noalias !843
  %265 = xor i64 %264, %202
  %266 = getelementptr inbounds nuw i8, ptr %5, i64 173
  %267 = load i64, ptr %266, align 1, !alias.scope !830, !noalias !843
  %268 = xor i64 %267, %206
  %269 = zext i64 %265 to i128
  %270 = zext i64 %268 to i128
  %271 = mul nuw i128 %270, %269
  %272 = lshr i128 %271, 64
  %273 = xor i128 %272, %271
  %274 = trunc i128 %273 to i64
  %275 = add i64 %262, %274
  %276 = lshr i64 %275, 37
  %277 = xor i64 %276, %275
  %278 = mul i64 %277, 1609587929392839161
  %279 = lshr i64 %278, 32
  %280 = xor i64 %279, %278
  call void @llvm.lifetime.end.p0(i64 64, ptr nonnull %4) #24, !noalias !752
  %281 = insertvalue [2 x i64] poison, i64 %221, 0
  %282 = insertvalue [2 x i64] %281, i64 %280, 1
  br label %283

283:                                              ; preds = %148, %7
  %284 = phi [2 x i64] [ %8, %7 ], [ %282, %148 ]
  call void @llvm.lifetime.end.p0(i64 192, ptr nonnull %5) #24
  ret [2 x i64] %284
}

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync)
define [2 x i64] @XXH128(ptr noundef readonly captures(none) %0, i64 noundef %1, i64 noundef %2) local_unnamed_addr #13 {
  %4 = tail call [2 x i64] @XXH3_128bits_withSeed(ptr noundef %0, i64 noundef %1, i64 noundef %2)
  ret [2 x i64] %4
}

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define range(i32 0, 2) i32 @XXH3_128bits_reset(ptr noundef %0) local_unnamed_addr #4 {
  %2 = icmp eq ptr %0, null
  br i1 %2, label %15, label %3

3:                                                ; preds = %1
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(576) %0, i8 noundef 0, i64 noundef 576, i1 noundef false) #24
  store i64 3266489917, ptr %0, align 16, !tbaa !22
  %4 = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i64 -7046029288634856825, ptr %4, align 8, !tbaa !22
  %5 = getelementptr inbounds nuw i8, ptr %0, i64 16
  store i64 -4417276706812531889, ptr %5, align 16, !tbaa !22
  %6 = getelementptr inbounds nuw i8, ptr %0, i64 24
  store i64 1609587929392839161, ptr %6, align 8, !tbaa !22
  %7 = getelementptr inbounds nuw i8, ptr %0, i64 32
  store i64 -8796714831421723037, ptr %7, align 16, !tbaa !22
  %8 = getelementptr inbounds nuw i8, ptr %0, i64 40
  store i64 2246822519, ptr %8, align 8, !tbaa !22
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 48
  store i64 2870177450012600261, ptr %9, align 16, !tbaa !22
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 56
  store i64 2654435761, ptr %10, align 8, !tbaa !22
  %11 = getelementptr inbounds nuw i8, ptr %0, i64 552
  store i64 0, ptr %11, align 8, !tbaa !319
  %12 = getelementptr inbounds nuw i8, ptr %0, i64 512
  store ptr @kSecret, ptr %12, align 16, !tbaa !322
  %13 = getelementptr inbounds nuw i8, ptr %0, i64 540
  store i32 128, ptr %13, align 4, !tbaa !323
  %14 = getelementptr inbounds nuw i8, ptr %0, i64 524
  store i32 16, ptr %14, align 4, !tbaa !324
  br label %15

15:                                               ; preds = %1, %3
  %16 = phi i32 [ 0, %3 ], [ 1, %1 ]
  ret i32 %16
}

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define range(i32 0, 2) i32 @XXH3_128bits_reset_withSecret(ptr noundef %0, ptr noundef %1, i64 noundef %2) local_unnamed_addr #4 {
  %4 = icmp eq ptr %0, null
  br i1 %4, label %24, label %5

5:                                                ; preds = %3
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(576) %0, i8 noundef 0, i64 noundef 576, i1 noundef false) #24
  store i64 3266489917, ptr %0, align 16, !tbaa !22
  %6 = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i64 -7046029288634856825, ptr %6, align 8, !tbaa !22
  %7 = getelementptr inbounds nuw i8, ptr %0, i64 16
  store i64 -4417276706812531889, ptr %7, align 16, !tbaa !22
  %8 = getelementptr inbounds nuw i8, ptr %0, i64 24
  store i64 1609587929392839161, ptr %8, align 8, !tbaa !22
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 32
  store i64 -8796714831421723037, ptr %9, align 16, !tbaa !22
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 40
  store i64 2246822519, ptr %10, align 8, !tbaa !22
  %11 = getelementptr inbounds nuw i8, ptr %0, i64 48
  store i64 2870177450012600261, ptr %11, align 16, !tbaa !22
  %12 = getelementptr inbounds nuw i8, ptr %0, i64 56
  store i64 2654435761, ptr %12, align 8, !tbaa !22
  %13 = getelementptr inbounds nuw i8, ptr %0, i64 552
  store i64 0, ptr %13, align 8, !tbaa !319
  %14 = getelementptr inbounds nuw i8, ptr %0, i64 512
  store ptr %1, ptr %14, align 16, !tbaa !322
  %15 = trunc i64 %2 to i32
  %16 = add i32 %15, -64
  %17 = getelementptr inbounds nuw i8, ptr %0, i64 540
  store i32 %16, ptr %17, align 4, !tbaa !323
  %18 = lshr i32 %16, 3
  %19 = getelementptr inbounds nuw i8, ptr %0, i64 524
  store i32 %18, ptr %19, align 4, !tbaa !324
  %20 = icmp eq ptr %1, null
  br i1 %20, label %24, label %21

21:                                               ; preds = %5
  %22 = icmp ult i64 %2, 136
  %23 = zext i1 %22 to i32
  br label %24

24:                                               ; preds = %21, %5, %3
  %25 = phi i32 [ 1, %3 ], [ 1, %5 ], [ %23, %21 ]
  ret i32 %25
}

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define range(i32 0, 2) i32 @XXH3_128bits_reset_withSeed(ptr noundef %0, i64 noundef %1) local_unnamed_addr #4 {
  %3 = icmp eq ptr %0, null
  br i1 %3, label %31, label %4

4:                                                ; preds = %2
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(576) %0, i8 noundef 0, i64 noundef 576, i1 noundef false) #24
  store i64 3266489917, ptr %0, align 16, !tbaa !22
  %5 = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i64 -7046029288634856825, ptr %5, align 8, !tbaa !22
  %6 = getelementptr inbounds nuw i8, ptr %0, i64 16
  store i64 -4417276706812531889, ptr %6, align 16, !tbaa !22
  %7 = getelementptr inbounds nuw i8, ptr %0, i64 24
  store i64 1609587929392839161, ptr %7, align 8, !tbaa !22
  %8 = getelementptr inbounds nuw i8, ptr %0, i64 32
  store i64 -8796714831421723037, ptr %8, align 16, !tbaa !22
  %9 = getelementptr inbounds nuw i8, ptr %0, i64 40
  store i64 2246822519, ptr %9, align 8, !tbaa !22
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 48
  store i64 2870177450012600261, ptr %10, align 16, !tbaa !22
  %11 = getelementptr inbounds nuw i8, ptr %0, i64 56
  store i64 2654435761, ptr %11, align 8, !tbaa !22
  %12 = getelementptr inbounds nuw i8, ptr %0, i64 552
  store i64 %1, ptr %12, align 8, !tbaa !319
  %13 = getelementptr inbounds nuw i8, ptr %0, i64 512
  store ptr @kSecret, ptr %13, align 16, !tbaa !322
  %14 = getelementptr inbounds nuw i8, ptr %0, i64 540
  store i32 128, ptr %14, align 4, !tbaa !323
  %15 = getelementptr inbounds nuw i8, ptr %0, i64 524
  store i32 16, ptr %15, align 4, !tbaa !324
  %16 = getelementptr inbounds nuw i8, ptr %0, i64 64
  br label %17

17:                                               ; preds = %4, %17
  %18 = phi i64 [ 0, %4 ], [ %28, %17 ]
  %19 = shl nuw nsw i64 %18, 4
  %20 = getelementptr inbounds nuw i8, ptr %16, i64 %19
  %21 = getelementptr inbounds nuw i8, ptr @kSecret, i64 %19
  %22 = load i64, ptr %21, align 16
  %23 = add i64 %22, %1
  store i64 %23, ptr %20, align 1
  %24 = getelementptr inbounds nuw i8, ptr %20, i64 8
  %25 = getelementptr inbounds nuw i8, ptr %21, i64 8
  %26 = load i64, ptr %25, align 8
  %27 = sub i64 %26, %1
  store i64 %27, ptr %24, align 1
  %28 = add nuw nsw i64 %18, 1
  %29 = icmp eq i64 %28, 12
  br i1 %29, label %30, label %17, !llvm.loop !250

30:                                               ; preds = %17
  store ptr %16, ptr %13, align 16, !tbaa !322
  br label %31

31:                                               ; preds = %2, %30
  %32 = phi i32 [ 0, %30 ], [ 1, %2 ]
  ret i32 %32
}

; Function Attrs: nofree norecurse nounwind ssp memory(read, argmem: readwrite, inaccessiblemem: readwrite) uwtable(sync)
define range(i32 0, 2) i32 @XXH3_128bits_update(ptr noundef %0, ptr noundef %1, i64 noundef %2) local_unnamed_addr #15 {
  %4 = icmp eq ptr %1, null
  br i1 %4, label %330, label %5

5:                                                ; preds = %3
  %6 = getelementptr inbounds nuw i8, ptr %1, i64 %2
  %7 = getelementptr inbounds nuw i8, ptr %0, i64 544
  %8 = load i64, ptr %7, align 16, !tbaa !325
  %9 = add i64 %8, %2
  store i64 %9, ptr %7, align 16, !tbaa !325
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 520
  %11 = load i32, ptr %10, align 8, !tbaa !326
  %12 = zext i32 %11 to i64
  %13 = add i64 %2, %12
  %14 = icmp ult i64 %13, 257
  br i1 %14, label %15, label %21

15:                                               ; preds = %5
  %16 = getelementptr inbounds nuw i8, ptr %0, i64 256
  %17 = getelementptr inbounds nuw i8, ptr %16, i64 %12
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %17, ptr noundef nonnull readonly align 1 %1, i64 noundef %2, i1 noundef false) #24
  %18 = trunc i64 %2 to i32
  %19 = load i32, ptr %10, align 8, !tbaa !326
  %20 = add i32 %19, %18
  br label %328

21:                                               ; preds = %5
  %22 = icmp eq i32 %11, 0
  br i1 %22, label %169, label %23

23:                                               ; preds = %21
  %24 = sub i32 256, %11
  %25 = zext i32 %24 to i64
  %26 = getelementptr inbounds nuw i8, ptr %0, i64 256
  %27 = getelementptr inbounds nuw i8, ptr %26, i64 %12
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %27, ptr noundef nonnull readonly align 1 %1, i64 noundef %25, i1 noundef false) #24
  %28 = getelementptr inbounds nuw i8, ptr %1, i64 %25
  %29 = getelementptr inbounds nuw i8, ptr %0, i64 528
  %30 = getelementptr inbounds nuw i8, ptr %0, i64 524
  %31 = load i32, ptr %30, align 4, !tbaa !324
  %32 = getelementptr inbounds nuw i8, ptr %0, i64 512
  %33 = load ptr, ptr %32, align 16, !tbaa !322
  %34 = getelementptr inbounds nuw i8, ptr %0, i64 540
  %35 = load i32, ptr %34, align 4, !tbaa !323
  %36 = zext i32 %35 to i64
  %37 = load i32, ptr %29, align 4, !tbaa !5
  %38 = sub i32 %31, %37
  %39 = zext i32 %38 to i64
  %40 = icmp ugt i32 %38, 4
  %41 = shl i32 %37, 3
  %42 = zext i32 %41 to i64
  %43 = getelementptr inbounds nuw i8, ptr %33, i64 %42
  br i1 %40, label %134, label %44

44:                                               ; preds = %23
  %45 = icmp eq i32 %31, %37
  br i1 %45, label %76, label %46

46:                                               ; preds = %44, %73
  %47 = phi i64 [ %74, %73 ], [ 0, %44 ]
  %48 = shl i64 %47, 6
  %49 = getelementptr inbounds nuw i8, ptr %26, i64 %48
  %50 = shl i64 %47, 3
  %51 = getelementptr inbounds nuw i8, ptr %43, i64 %50
  tail call void @llvm.experimental.noalias.scope.decl(metadata !846)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !849)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !851)
  br label %52

52:                                               ; preds = %46, %52
  %53 = phi i64 [ 0, %46 ], [ %71, %52 ]
  %54 = shl nuw nsw i64 %53, 2
  %55 = getelementptr inbounds nuw i32, ptr %49, i64 %54
  %56 = load <4 x i32>, ptr %55, align 4, !alias.scope !849, !noalias !853
  %57 = getelementptr inbounds nuw i32, ptr %51, i64 %54
  %58 = load <4 x i32>, ptr %57, align 4, !alias.scope !851, !noalias !854
  %59 = xor <4 x i32> %58, %56
  %60 = bitcast <4 x i32> %59 to <2 x i64>
  %61 = trunc <2 x i64> %60 to <2 x i32>
  %62 = lshr <2 x i64> %60, splat (i64 32)
  %63 = trunc nuw <2 x i64> %62 to <2 x i32>
  %64 = bitcast <4 x i32> %56 to <2 x i64>
  %65 = shufflevector <2 x i64> %64, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %66 = getelementptr inbounds nuw <2 x i64>, ptr %0, i64 %53
  %67 = load <2 x i64>, ptr %66, align 16, !tbaa !21, !alias.scope !846, !noalias !855
  %68 = add <2 x i64> %67, %65
  %69 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %61, <2 x i32> %63)
  %70 = add <2 x i64> %68, %69
  store <2 x i64> %70, ptr %66, align 16, !tbaa !21, !alias.scope !846, !noalias !855
  %71 = add nuw nsw i64 %53, 1
  %72 = icmp eq i64 %71, 4
  br i1 %72, label %73, label %52, !llvm.loop !82

73:                                               ; preds = %52
  %74 = add nuw nsw i64 %47, 1
  %75 = icmp eq i64 %74, %39
  br i1 %75, label %76, label %46, !llvm.loop !83

76:                                               ; preds = %73, %44
  %77 = getelementptr inbounds nuw i8, ptr %33, i64 %36
  tail call void @llvm.experimental.noalias.scope.decl(metadata !856)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !859)
  br label %78

78:                                               ; preds = %76, %78
  %79 = phi i64 [ 0, %76 ], [ %95, %78 ]
  %80 = getelementptr inbounds nuw <2 x i64>, ptr %0, i64 %79
  %81 = load <2 x i64>, ptr %80, align 16, !tbaa !21, !alias.scope !856, !noalias !859
  %82 = lshr <2 x i64> %81, splat (i64 47)
  %83 = xor <2 x i64> %82, %81
  %84 = shl nuw nsw i64 %79, 4
  %85 = getelementptr inbounds nuw i8, ptr %77, i64 %84
  %86 = load <4 x i32>, ptr %85, align 4, !alias.scope !859, !noalias !856
  %87 = bitcast <2 x i64> %83 to <4 x i32>
  %88 = xor <4 x i32> %86, %87
  %89 = shufflevector <4 x i32> %88, <4 x i32> poison, <2 x i32> <i32 0, i32 2>
  %90 = shufflevector <4 x i32> %88, <4 x i32> poison, <2 x i32> <i32 1, i32 3>
  %91 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %90, <2 x i32> splat (i32 -1640531535))
  %92 = shl <2 x i64> %91, splat (i64 32)
  %93 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %89, <2 x i32> splat (i32 -1640531535))
  %94 = add <2 x i64> %92, %93
  store <2 x i64> %94, ptr %80, align 16, !tbaa !21, !alias.scope !856, !noalias !859
  %95 = add nuw nsw i64 %79, 1
  %96 = icmp eq i64 %95, 4
  br i1 %96, label %97, label %78, !llvm.loop !89

97:                                               ; preds = %78
  %98 = shl nuw nsw i64 %39, 6
  %99 = getelementptr inbounds nuw i8, ptr %26, i64 %98
  %100 = sub nsw i64 4, %39
  %101 = icmp eq i32 %38, 4
  br i1 %101, label %132, label %102

102:                                              ; preds = %97, %129
  %103 = phi i64 [ %130, %129 ], [ 0, %97 ]
  %104 = shl i64 %103, 6
  %105 = getelementptr inbounds nuw i8, ptr %99, i64 %104
  %106 = shl i64 %103, 3
  %107 = getelementptr inbounds nuw i8, ptr %33, i64 %106
  tail call void @llvm.experimental.noalias.scope.decl(metadata !861)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !864)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !866)
  br label %108

108:                                              ; preds = %102, %108
  %109 = phi i64 [ 0, %102 ], [ %127, %108 ]
  %110 = shl nuw nsw i64 %109, 2
  %111 = getelementptr inbounds nuw i32, ptr %105, i64 %110
  %112 = load <4 x i32>, ptr %111, align 4, !alias.scope !864, !noalias !868
  %113 = getelementptr inbounds nuw i32, ptr %107, i64 %110
  %114 = load <4 x i32>, ptr %113, align 4, !alias.scope !866, !noalias !869
  %115 = xor <4 x i32> %114, %112
  %116 = bitcast <4 x i32> %115 to <2 x i64>
  %117 = trunc <2 x i64> %116 to <2 x i32>
  %118 = lshr <2 x i64> %116, splat (i64 32)
  %119 = trunc nuw <2 x i64> %118 to <2 x i32>
  %120 = bitcast <4 x i32> %112 to <2 x i64>
  %121 = shufflevector <2 x i64> %120, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %122 = getelementptr inbounds nuw <2 x i64>, ptr %0, i64 %109
  %123 = load <2 x i64>, ptr %122, align 16, !tbaa !21, !alias.scope !861, !noalias !870
  %124 = add <2 x i64> %123, %121
  %125 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %117, <2 x i32> %119)
  %126 = add <2 x i64> %124, %125
  store <2 x i64> %126, ptr %122, align 16, !tbaa !21, !alias.scope !861, !noalias !870
  %127 = add nuw nsw i64 %109, 1
  %128 = icmp eq i64 %127, 4
  br i1 %128, label %129, label %108, !llvm.loop !82

129:                                              ; preds = %108
  %130 = add nuw i64 %103, 1
  %131 = icmp eq i64 %130, %100
  br i1 %131, label %132, label %102, !llvm.loop !83

132:                                              ; preds = %129, %97
  %133 = trunc nuw nsw i64 %100 to i32
  br label %167

134:                                              ; preds = %23, %161
  %135 = phi i64 [ %162, %161 ], [ 0, %23 ]
  %136 = shl nuw nsw i64 %135, 6
  %137 = getelementptr inbounds nuw i8, ptr %26, i64 %136
  %138 = shl nuw nsw i64 %135, 3
  %139 = getelementptr inbounds nuw i8, ptr %43, i64 %138
  tail call void @llvm.experimental.noalias.scope.decl(metadata !871)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !874)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !876)
  br label %140

140:                                              ; preds = %134, %140
  %141 = phi i64 [ 0, %134 ], [ %159, %140 ]
  %142 = shl nuw nsw i64 %141, 2
  %143 = getelementptr inbounds nuw i32, ptr %137, i64 %142
  %144 = load <4 x i32>, ptr %143, align 4, !alias.scope !874, !noalias !878
  %145 = getelementptr inbounds nuw i32, ptr %139, i64 %142
  %146 = load <4 x i32>, ptr %145, align 4, !alias.scope !876, !noalias !879
  %147 = xor <4 x i32> %146, %144
  %148 = bitcast <4 x i32> %147 to <2 x i64>
  %149 = trunc <2 x i64> %148 to <2 x i32>
  %150 = lshr <2 x i64> %148, splat (i64 32)
  %151 = trunc nuw <2 x i64> %150 to <2 x i32>
  %152 = bitcast <4 x i32> %144 to <2 x i64>
  %153 = shufflevector <2 x i64> %152, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %154 = getelementptr inbounds nuw <2 x i64>, ptr %0, i64 %141
  %155 = load <2 x i64>, ptr %154, align 16, !tbaa !21, !alias.scope !871, !noalias !880
  %156 = add <2 x i64> %155, %153
  %157 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %149, <2 x i32> %151)
  %158 = add <2 x i64> %156, %157
  store <2 x i64> %158, ptr %154, align 16, !tbaa !21, !alias.scope !871, !noalias !880
  %159 = add nuw nsw i64 %141, 1
  %160 = icmp eq i64 %159, 4
  br i1 %160, label %161, label %140, !llvm.loop !82

161:                                              ; preds = %140
  %162 = add nuw nsw i64 %135, 1
  %163 = icmp eq i64 %162, 4
  br i1 %163, label %164, label %134, !llvm.loop !83

164:                                              ; preds = %161
  %165 = load i32, ptr %29, align 4, !tbaa !5
  %166 = add i32 %165, 4
  br label %167

167:                                              ; preds = %132, %164
  %168 = phi i32 [ %166, %164 ], [ %133, %132 ]
  store i32 %168, ptr %29, align 4, !tbaa !5
  store i32 0, ptr %10, align 8, !tbaa !326
  br label %169

169:                                              ; preds = %167, %21
  %170 = phi ptr [ %28, %167 ], [ %1, %21 ]
  %171 = getelementptr inbounds nuw i8, ptr %170, i64 256
  %172 = icmp ugt ptr %171, %6
  br i1 %172, label %319, label %173

173:                                              ; preds = %169
  %174 = getelementptr inbounds i8, ptr %6, i64 -256
  %175 = getelementptr inbounds nuw i8, ptr %0, i64 528
  %176 = getelementptr inbounds nuw i8, ptr %0, i64 524
  %177 = getelementptr inbounds nuw i8, ptr %0, i64 512
  %178 = getelementptr inbounds nuw i8, ptr %0, i64 540
  br label %179

179:                                              ; preds = %315, %173
  %180 = phi ptr [ %170, %173 ], [ %317, %315 ]
  %181 = load i32, ptr %176, align 4, !tbaa !324
  %182 = load ptr, ptr %177, align 16, !tbaa !322
  %183 = load i32, ptr %178, align 4, !tbaa !323
  %184 = zext i32 %183 to i64
  %185 = load i32, ptr %175, align 4, !tbaa !5
  %186 = sub i32 %181, %185
  %187 = zext i32 %186 to i64
  %188 = icmp ugt i32 %186, 4
  %189 = shl i32 %185, 3
  %190 = zext i32 %189 to i64
  %191 = getelementptr inbounds nuw i8, ptr %182, i64 %190
  br i1 %188, label %282, label %192

192:                                              ; preds = %179
  %193 = icmp eq i32 %181, %185
  br i1 %193, label %224, label %194

194:                                              ; preds = %192, %221
  %195 = phi i64 [ %222, %221 ], [ 0, %192 ]
  %196 = shl i64 %195, 6
  %197 = getelementptr inbounds nuw i8, ptr %180, i64 %196
  %198 = shl i64 %195, 3
  %199 = getelementptr inbounds nuw i8, ptr %191, i64 %198
  tail call void @llvm.experimental.noalias.scope.decl(metadata !881)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !884)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !886)
  br label %200

200:                                              ; preds = %194, %200
  %201 = phi i64 [ 0, %194 ], [ %219, %200 ]
  %202 = shl nuw nsw i64 %201, 2
  %203 = getelementptr inbounds nuw i32, ptr %197, i64 %202
  %204 = load <4 x i32>, ptr %203, align 4, !alias.scope !884, !noalias !888
  %205 = getelementptr inbounds nuw i32, ptr %199, i64 %202
  %206 = load <4 x i32>, ptr %205, align 4, !alias.scope !886, !noalias !889
  %207 = xor <4 x i32> %206, %204
  %208 = bitcast <4 x i32> %207 to <2 x i64>
  %209 = trunc <2 x i64> %208 to <2 x i32>
  %210 = lshr <2 x i64> %208, splat (i64 32)
  %211 = trunc nuw <2 x i64> %210 to <2 x i32>
  %212 = bitcast <4 x i32> %204 to <2 x i64>
  %213 = shufflevector <2 x i64> %212, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %214 = getelementptr inbounds nuw <2 x i64>, ptr %0, i64 %201
  %215 = load <2 x i64>, ptr %214, align 16, !tbaa !21, !alias.scope !881, !noalias !890
  %216 = add <2 x i64> %215, %213
  %217 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %209, <2 x i32> %211)
  %218 = add <2 x i64> %216, %217
  store <2 x i64> %218, ptr %214, align 16, !tbaa !21, !alias.scope !881, !noalias !890
  %219 = add nuw nsw i64 %201, 1
  %220 = icmp eq i64 %219, 4
  br i1 %220, label %221, label %200, !llvm.loop !82

221:                                              ; preds = %200
  %222 = add nuw nsw i64 %195, 1
  %223 = icmp eq i64 %222, %187
  br i1 %223, label %224, label %194, !llvm.loop !83

224:                                              ; preds = %221, %192
  %225 = getelementptr inbounds nuw i8, ptr %182, i64 %184
  tail call void @llvm.experimental.noalias.scope.decl(metadata !891)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !894)
  br label %226

226:                                              ; preds = %224, %226
  %227 = phi i64 [ 0, %224 ], [ %243, %226 ]
  %228 = getelementptr inbounds nuw <2 x i64>, ptr %0, i64 %227
  %229 = load <2 x i64>, ptr %228, align 16, !tbaa !21, !alias.scope !891, !noalias !894
  %230 = lshr <2 x i64> %229, splat (i64 47)
  %231 = xor <2 x i64> %230, %229
  %232 = shl nuw nsw i64 %227, 4
  %233 = getelementptr inbounds nuw i8, ptr %225, i64 %232
  %234 = load <4 x i32>, ptr %233, align 4, !alias.scope !894, !noalias !891
  %235 = bitcast <2 x i64> %231 to <4 x i32>
  %236 = xor <4 x i32> %234, %235
  %237 = shufflevector <4 x i32> %236, <4 x i32> poison, <2 x i32> <i32 0, i32 2>
  %238 = shufflevector <4 x i32> %236, <4 x i32> poison, <2 x i32> <i32 1, i32 3>
  %239 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %238, <2 x i32> splat (i32 -1640531535))
  %240 = shl <2 x i64> %239, splat (i64 32)
  %241 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %237, <2 x i32> splat (i32 -1640531535))
  %242 = add <2 x i64> %240, %241
  store <2 x i64> %242, ptr %228, align 16, !tbaa !21, !alias.scope !891, !noalias !894
  %243 = add nuw nsw i64 %227, 1
  %244 = icmp eq i64 %243, 4
  br i1 %244, label %245, label %226, !llvm.loop !89

245:                                              ; preds = %226
  %246 = shl nuw nsw i64 %187, 6
  %247 = getelementptr inbounds nuw i8, ptr %180, i64 %246
  %248 = sub nsw i64 4, %187
  %249 = icmp eq i32 %186, 4
  br i1 %249, label %280, label %250

250:                                              ; preds = %245, %277
  %251 = phi i64 [ %278, %277 ], [ 0, %245 ]
  %252 = shl i64 %251, 6
  %253 = getelementptr inbounds nuw i8, ptr %247, i64 %252
  %254 = shl i64 %251, 3
  %255 = getelementptr inbounds nuw i8, ptr %182, i64 %254
  tail call void @llvm.experimental.noalias.scope.decl(metadata !896)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !899)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !901)
  br label %256

256:                                              ; preds = %250, %256
  %257 = phi i64 [ 0, %250 ], [ %275, %256 ]
  %258 = shl nuw nsw i64 %257, 2
  %259 = getelementptr inbounds nuw i32, ptr %253, i64 %258
  %260 = load <4 x i32>, ptr %259, align 4, !alias.scope !899, !noalias !903
  %261 = getelementptr inbounds nuw i32, ptr %255, i64 %258
  %262 = load <4 x i32>, ptr %261, align 4, !alias.scope !901, !noalias !904
  %263 = xor <4 x i32> %262, %260
  %264 = bitcast <4 x i32> %263 to <2 x i64>
  %265 = trunc <2 x i64> %264 to <2 x i32>
  %266 = lshr <2 x i64> %264, splat (i64 32)
  %267 = trunc nuw <2 x i64> %266 to <2 x i32>
  %268 = bitcast <4 x i32> %260 to <2 x i64>
  %269 = shufflevector <2 x i64> %268, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %270 = getelementptr inbounds nuw <2 x i64>, ptr %0, i64 %257
  %271 = load <2 x i64>, ptr %270, align 16, !tbaa !21, !alias.scope !896, !noalias !905
  %272 = add <2 x i64> %271, %269
  %273 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %265, <2 x i32> %267)
  %274 = add <2 x i64> %272, %273
  store <2 x i64> %274, ptr %270, align 16, !tbaa !21, !alias.scope !896, !noalias !905
  %275 = add nuw nsw i64 %257, 1
  %276 = icmp eq i64 %275, 4
  br i1 %276, label %277, label %256, !llvm.loop !82

277:                                              ; preds = %256
  %278 = add nuw i64 %251, 1
  %279 = icmp eq i64 %278, %248
  br i1 %279, label %280, label %250, !llvm.loop !83

280:                                              ; preds = %277, %245
  %281 = trunc nuw nsw i64 %248 to i32
  br label %315

282:                                              ; preds = %179, %309
  %283 = phi i64 [ %310, %309 ], [ 0, %179 ]
  %284 = shl nuw nsw i64 %283, 6
  %285 = getelementptr inbounds nuw i8, ptr %180, i64 %284
  %286 = shl nuw nsw i64 %283, 3
  %287 = getelementptr inbounds nuw i8, ptr %191, i64 %286
  tail call void @llvm.experimental.noalias.scope.decl(metadata !906)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !909)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !911)
  br label %288

288:                                              ; preds = %282, %288
  %289 = phi i64 [ 0, %282 ], [ %307, %288 ]
  %290 = shl nuw nsw i64 %289, 2
  %291 = getelementptr inbounds nuw i32, ptr %285, i64 %290
  %292 = load <4 x i32>, ptr %291, align 4, !alias.scope !909, !noalias !913
  %293 = getelementptr inbounds nuw i32, ptr %287, i64 %290
  %294 = load <4 x i32>, ptr %293, align 4, !alias.scope !911, !noalias !914
  %295 = xor <4 x i32> %294, %292
  %296 = bitcast <4 x i32> %295 to <2 x i64>
  %297 = trunc <2 x i64> %296 to <2 x i32>
  %298 = lshr <2 x i64> %296, splat (i64 32)
  %299 = trunc nuw <2 x i64> %298 to <2 x i32>
  %300 = bitcast <4 x i32> %292 to <2 x i64>
  %301 = shufflevector <2 x i64> %300, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %302 = getelementptr inbounds nuw <2 x i64>, ptr %0, i64 %289
  %303 = load <2 x i64>, ptr %302, align 16, !tbaa !21, !alias.scope !906, !noalias !915
  %304 = add <2 x i64> %303, %301
  %305 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %297, <2 x i32> %299)
  %306 = add <2 x i64> %304, %305
  store <2 x i64> %306, ptr %302, align 16, !tbaa !21, !alias.scope !906, !noalias !915
  %307 = add nuw nsw i64 %289, 1
  %308 = icmp eq i64 %307, 4
  br i1 %308, label %309, label %288, !llvm.loop !82

309:                                              ; preds = %288
  %310 = add nuw nsw i64 %283, 1
  %311 = icmp eq i64 %310, 4
  br i1 %311, label %312, label %282, !llvm.loop !83

312:                                              ; preds = %309
  %313 = load i32, ptr %175, align 4, !tbaa !5
  %314 = add i32 %313, 4
  br label %315

315:                                              ; preds = %280, %312
  %316 = phi i32 [ %314, %312 ], [ %281, %280 ]
  store i32 %316, ptr %175, align 4, !tbaa !5
  %317 = getelementptr inbounds nuw i8, ptr %180, i64 256
  %318 = icmp ugt ptr %317, %174
  br i1 %318, label %319, label %179, !llvm.loop !397

319:                                              ; preds = %315, %169
  %320 = phi ptr [ %170, %169 ], [ %317, %315 ]
  %321 = icmp ult ptr %320, %6
  br i1 %321, label %322, label %330

322:                                              ; preds = %319
  %323 = getelementptr inbounds nuw i8, ptr %0, i64 256
  %324 = ptrtoint ptr %6 to i64
  %325 = ptrtoint ptr %320 to i64
  %326 = sub i64 %324, %325
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %323, ptr noundef nonnull readonly align 1 %320, i64 noundef %326, i1 noundef false) #24
  %327 = trunc i64 %326 to i32
  br label %328

328:                                              ; preds = %322, %15
  %329 = phi i32 [ %20, %15 ], [ %327, %322 ]
  store i32 %329, ptr %10, align 8, !tbaa !326
  br label %330

330:                                              ; preds = %328, %3, %319
  %331 = phi i32 [ 1, %3 ], [ 0, %319 ], [ 0, %328 ]
  ret i32 %331
}

; Function Attrs: nofree norecurse nounwind ssp memory(read, argmem: readwrite, inaccessiblemem: readwrite) uwtable(sync)
define [2 x i64] @XXH3_128bits_digest(ptr noundef readonly captures(none) %0) local_unnamed_addr #15 {
  %2 = alloca [64 x i8], align 1
  %3 = alloca [8 x i64], align 16
  %4 = getelementptr inbounds nuw i8, ptr %0, i64 544
  %5 = load i64, ptr %4, align 16, !tbaa !325
  %6 = icmp ugt i64 %5, 240
  br i1 %6, label %7, label %359

7:                                                ; preds = %1
  call void @llvm.lifetime.start.p0(i64 64, ptr nonnull %3) #24
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 16 dereferenceable(64) %3, ptr noundef nonnull align 1 dereferenceable(64) %0, i64 noundef 64, i1 noundef false) #24
  %8 = getelementptr inbounds nuw i8, ptr %0, i64 520
  %9 = load i32, ptr %8, align 8, !tbaa !326
  %10 = icmp ugt i32 %9, 63
  br i1 %10, label %11, label %178

11:                                               ; preds = %7
  %12 = lshr i32 %9, 6
  %13 = zext nneg i32 %12 to i64
  %14 = getelementptr inbounds nuw i8, ptr %0, i64 528
  %15 = load i32, ptr %14, align 16, !tbaa !398
  %16 = getelementptr inbounds nuw i8, ptr %0, i64 524
  %17 = load i32, ptr %16, align 4, !tbaa !324
  %18 = getelementptr inbounds nuw i8, ptr %0, i64 256
  %19 = getelementptr inbounds nuw i8, ptr %0, i64 512
  %20 = load ptr, ptr %19, align 16, !tbaa !322
  %21 = getelementptr inbounds nuw i8, ptr %0, i64 540
  %22 = load i32, ptr %21, align 4, !tbaa !323
  %23 = zext i32 %22 to i64
  %24 = sub i32 %17, %15
  %25 = zext i32 %24 to i64
  %26 = icmp ult i32 %12, %24
  %27 = shl i32 %15, 3
  %28 = zext i32 %27 to i64
  %29 = getelementptr inbounds nuw i8, ptr %20, i64 %28
  br i1 %26, label %118, label %30

30:                                               ; preds = %11
  %31 = icmp eq i32 %17, %15
  br i1 %31, label %62, label %32

32:                                               ; preds = %30, %59
  %33 = phi i64 [ %60, %59 ], [ 0, %30 ]
  %34 = shl i64 %33, 6
  %35 = getelementptr inbounds nuw i8, ptr %18, i64 %34
  %36 = shl i64 %33, 3
  %37 = getelementptr inbounds nuw i8, ptr %29, i64 %36
  tail call void @llvm.experimental.noalias.scope.decl(metadata !916)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !919)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !921)
  br label %38

38:                                               ; preds = %32, %38
  %39 = phi i64 [ 0, %32 ], [ %57, %38 ]
  %40 = shl nuw nsw i64 %39, 2
  %41 = getelementptr inbounds nuw i32, ptr %35, i64 %40
  %42 = load <4 x i32>, ptr %41, align 4, !alias.scope !919, !noalias !923
  %43 = getelementptr inbounds nuw i32, ptr %37, i64 %40
  %44 = load <4 x i32>, ptr %43, align 4, !alias.scope !921, !noalias !924
  %45 = xor <4 x i32> %44, %42
  %46 = bitcast <4 x i32> %45 to <2 x i64>
  %47 = trunc <2 x i64> %46 to <2 x i32>
  %48 = lshr <2 x i64> %46, splat (i64 32)
  %49 = trunc nuw <2 x i64> %48 to <2 x i32>
  %50 = bitcast <4 x i32> %42 to <2 x i64>
  %51 = shufflevector <2 x i64> %50, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %52 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %39
  %53 = load <2 x i64>, ptr %52, align 16, !tbaa !21, !alias.scope !916, !noalias !925
  %54 = add <2 x i64> %53, %51
  %55 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %47, <2 x i32> %49)
  %56 = add <2 x i64> %54, %55
  store <2 x i64> %56, ptr %52, align 16, !tbaa !21, !alias.scope !916, !noalias !925
  %57 = add nuw nsw i64 %39, 1
  %58 = icmp eq i64 %57, 4
  br i1 %58, label %59, label %38, !llvm.loop !82

59:                                               ; preds = %38
  %60 = add nuw nsw i64 %33, 1
  %61 = icmp eq i64 %60, %25
  br i1 %61, label %62, label %32, !llvm.loop !83

62:                                               ; preds = %59, %30
  %63 = getelementptr inbounds nuw i8, ptr %20, i64 %23
  tail call void @llvm.experimental.noalias.scope.decl(metadata !926)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !929)
  br label %64

64:                                               ; preds = %62, %64
  %65 = phi i64 [ 0, %62 ], [ %81, %64 ]
  %66 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %65
  %67 = load <2 x i64>, ptr %66, align 16, !tbaa !21, !alias.scope !926, !noalias !929
  %68 = lshr <2 x i64> %67, splat (i64 47)
  %69 = xor <2 x i64> %68, %67
  %70 = shl nuw nsw i64 %65, 4
  %71 = getelementptr inbounds nuw i8, ptr %63, i64 %70
  %72 = load <4 x i32>, ptr %71, align 4, !alias.scope !929, !noalias !926
  %73 = bitcast <2 x i64> %69 to <4 x i32>
  %74 = xor <4 x i32> %72, %73
  %75 = shufflevector <4 x i32> %74, <4 x i32> poison, <2 x i32> <i32 0, i32 2>
  %76 = shufflevector <4 x i32> %74, <4 x i32> poison, <2 x i32> <i32 1, i32 3>
  %77 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %76, <2 x i32> splat (i32 -1640531535))
  %78 = shl <2 x i64> %77, splat (i64 32)
  %79 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %75, <2 x i32> splat (i32 -1640531535))
  %80 = add <2 x i64> %78, %79
  store <2 x i64> %80, ptr %66, align 16, !tbaa !21, !alias.scope !926, !noalias !929
  %81 = add nuw nsw i64 %65, 1
  %82 = icmp eq i64 %81, 4
  br i1 %82, label %83, label %64, !llvm.loop !89

83:                                               ; preds = %64
  %84 = shl nuw nsw i64 %25, 6
  %85 = getelementptr inbounds nuw i8, ptr %18, i64 %84
  %86 = sub nsw i64 %13, %25
  %87 = icmp eq i32 %12, %24
  br i1 %87, label %148, label %88

88:                                               ; preds = %83, %115
  %89 = phi i64 [ %116, %115 ], [ 0, %83 ]
  %90 = shl i64 %89, 6
  %91 = getelementptr inbounds nuw i8, ptr %85, i64 %90
  %92 = shl i64 %89, 3
  %93 = getelementptr inbounds nuw i8, ptr %20, i64 %92
  tail call void @llvm.experimental.noalias.scope.decl(metadata !931)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !934)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !936)
  br label %94

94:                                               ; preds = %88, %94
  %95 = phi i64 [ 0, %88 ], [ %113, %94 ]
  %96 = shl nuw nsw i64 %95, 2
  %97 = getelementptr inbounds nuw i32, ptr %91, i64 %96
  %98 = load <4 x i32>, ptr %97, align 4, !alias.scope !934, !noalias !938
  %99 = getelementptr inbounds nuw i32, ptr %93, i64 %96
  %100 = load <4 x i32>, ptr %99, align 4, !alias.scope !936, !noalias !939
  %101 = xor <4 x i32> %100, %98
  %102 = bitcast <4 x i32> %101 to <2 x i64>
  %103 = trunc <2 x i64> %102 to <2 x i32>
  %104 = lshr <2 x i64> %102, splat (i64 32)
  %105 = trunc nuw <2 x i64> %104 to <2 x i32>
  %106 = bitcast <4 x i32> %98 to <2 x i64>
  %107 = shufflevector <2 x i64> %106, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %108 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %95
  %109 = load <2 x i64>, ptr %108, align 16, !tbaa !21, !alias.scope !931, !noalias !940
  %110 = add <2 x i64> %109, %107
  %111 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %103, <2 x i32> %105)
  %112 = add <2 x i64> %110, %111
  store <2 x i64> %112, ptr %108, align 16, !tbaa !21, !alias.scope !931, !noalias !940
  %113 = add nuw nsw i64 %95, 1
  %114 = icmp eq i64 %113, 4
  br i1 %114, label %115, label %94, !llvm.loop !82

115:                                              ; preds = %94
  %116 = add nuw i64 %89, 1
  %117 = icmp eq i64 %116, %86
  br i1 %117, label %148, label %88, !llvm.loop !83

118:                                              ; preds = %11, %145
  %119 = phi i64 [ %146, %145 ], [ 0, %11 ]
  %120 = shl i64 %119, 6
  %121 = getelementptr inbounds nuw i8, ptr %18, i64 %120
  %122 = shl i64 %119, 3
  %123 = getelementptr inbounds nuw i8, ptr %29, i64 %122
  tail call void @llvm.experimental.noalias.scope.decl(metadata !941)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !944)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !946)
  br label %124

124:                                              ; preds = %118, %124
  %125 = phi i64 [ 0, %118 ], [ %143, %124 ]
  %126 = shl nuw nsw i64 %125, 2
  %127 = getelementptr inbounds nuw i32, ptr %121, i64 %126
  %128 = load <4 x i32>, ptr %127, align 4, !alias.scope !944, !noalias !948
  %129 = getelementptr inbounds nuw i32, ptr %123, i64 %126
  %130 = load <4 x i32>, ptr %129, align 4, !alias.scope !946, !noalias !949
  %131 = xor <4 x i32> %130, %128
  %132 = bitcast <4 x i32> %131 to <2 x i64>
  %133 = trunc <2 x i64> %132 to <2 x i32>
  %134 = lshr <2 x i64> %132, splat (i64 32)
  %135 = trunc nuw <2 x i64> %134 to <2 x i32>
  %136 = bitcast <4 x i32> %128 to <2 x i64>
  %137 = shufflevector <2 x i64> %136, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %138 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %125
  %139 = load <2 x i64>, ptr %138, align 16, !tbaa !21, !alias.scope !941, !noalias !950
  %140 = add <2 x i64> %139, %137
  %141 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %133, <2 x i32> %135)
  %142 = add <2 x i64> %140, %141
  store <2 x i64> %142, ptr %138, align 16, !tbaa !21, !alias.scope !941, !noalias !950
  %143 = add nuw nsw i64 %125, 1
  %144 = icmp eq i64 %143, 4
  br i1 %144, label %145, label %124, !llvm.loop !82

145:                                              ; preds = %124
  %146 = add nuw nsw i64 %119, 1
  %147 = icmp eq i64 %146, %13
  br i1 %147, label %148, label %118, !llvm.loop !83

148:                                              ; preds = %115, %145, %83
  %149 = and i32 %9, 63
  %150 = icmp eq i32 %149, 0
  br i1 %150, label %218, label %151

151:                                              ; preds = %148
  %152 = zext i32 %9 to i64
  %153 = getelementptr inbounds nuw i8, ptr %18, i64 %152
  %154 = getelementptr inbounds i8, ptr %153, i64 -64
  %155 = getelementptr inbounds nuw i8, ptr %20, i64 %23
  %156 = getelementptr inbounds i8, ptr %155, i64 -7
  tail call void @llvm.experimental.noalias.scope.decl(metadata !951)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !954)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !956)
  br label %157

157:                                              ; preds = %151, %157
  %158 = phi i64 [ 0, %151 ], [ %176, %157 ]
  %159 = shl nuw nsw i64 %158, 2
  %160 = getelementptr inbounds nuw i32, ptr %154, i64 %159
  %161 = load <4 x i32>, ptr %160, align 4, !alias.scope !954, !noalias !958
  %162 = getelementptr inbounds nuw i32, ptr %156, i64 %159
  %163 = load <4 x i32>, ptr %162, align 4, !alias.scope !956, !noalias !959
  %164 = xor <4 x i32> %163, %161
  %165 = bitcast <4 x i32> %164 to <2 x i64>
  %166 = trunc <2 x i64> %165 to <2 x i32>
  %167 = lshr <2 x i64> %165, splat (i64 32)
  %168 = trunc nuw <2 x i64> %167 to <2 x i32>
  %169 = bitcast <4 x i32> %161 to <2 x i64>
  %170 = shufflevector <2 x i64> %169, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %171 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %158
  %172 = load <2 x i64>, ptr %171, align 16, !tbaa !21, !alias.scope !951, !noalias !960
  %173 = add <2 x i64> %172, %170
  %174 = tail call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %166, <2 x i32> %168)
  %175 = add <2 x i64> %173, %174
  store <2 x i64> %175, ptr %171, align 16, !tbaa !21, !alias.scope !951, !noalias !960
  %176 = add nuw nsw i64 %158, 1
  %177 = icmp eq i64 %176, 4
  br i1 %177, label %218, label %157, !llvm.loop !82

178:                                              ; preds = %7
  %179 = icmp eq i32 %9, 0
  br i1 %179, label %218, label %180

180:                                              ; preds = %178
  call void @llvm.lifetime.start.p0(i64 64, ptr nonnull %2) #24
  %181 = sub nuw nsw i32 64, %9
  %182 = zext nneg i32 %181 to i64
  %183 = getelementptr inbounds nuw i8, ptr %0, i64 256
  %184 = getelementptr inbounds nuw i8, ptr %0, i64 512
  %185 = sub nsw i64 0, %182
  %186 = getelementptr inbounds i8, ptr %184, i64 %185
  %187 = call ptr @__memcpy_chk(ptr noundef nonnull %2, ptr noundef nonnull %186, i64 noundef %182, i64 noundef 64) #24
  %188 = getelementptr inbounds nuw i8, ptr %2, i64 %182
  %189 = zext nneg i32 %9 to i64
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 %188, ptr noundef nonnull align 1 %183, i64 noundef %189, i1 noundef false) #24
  %190 = load ptr, ptr %184, align 16, !tbaa !322
  %191 = getelementptr inbounds nuw i8, ptr %0, i64 540
  %192 = load i32, ptr %191, align 4, !tbaa !323
  %193 = zext i32 %192 to i64
  %194 = getelementptr inbounds nuw i8, ptr %190, i64 %193
  %195 = getelementptr inbounds i8, ptr %194, i64 -7
  call void @llvm.experimental.noalias.scope.decl(metadata !961)
  call void @llvm.experimental.noalias.scope.decl(metadata !964)
  call void @llvm.experimental.noalias.scope.decl(metadata !966)
  br label %196

196:                                              ; preds = %180, %196
  %197 = phi i64 [ 0, %180 ], [ %215, %196 ]
  %198 = shl nuw nsw i64 %197, 2
  %199 = getelementptr inbounds nuw i32, ptr %2, i64 %198
  %200 = load <4 x i32>, ptr %199, align 4, !alias.scope !964, !noalias !968
  %201 = getelementptr inbounds nuw i32, ptr %195, i64 %198
  %202 = load <4 x i32>, ptr %201, align 4, !alias.scope !966, !noalias !969
  %203 = xor <4 x i32> %202, %200
  %204 = bitcast <4 x i32> %203 to <2 x i64>
  %205 = trunc <2 x i64> %204 to <2 x i32>
  %206 = lshr <2 x i64> %204, splat (i64 32)
  %207 = trunc nuw <2 x i64> %206 to <2 x i32>
  %208 = bitcast <4 x i32> %200 to <2 x i64>
  %209 = shufflevector <2 x i64> %208, <2 x i64> poison, <2 x i32> <i32 1, i32 0>
  %210 = getelementptr inbounds nuw <2 x i64>, ptr %3, i64 %197
  %211 = load <2 x i64>, ptr %210, align 16, !tbaa !21, !alias.scope !961, !noalias !970
  %212 = add <2 x i64> %211, %209
  %213 = call <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32> %205, <2 x i32> %207)
  %214 = add <2 x i64> %212, %213
  store <2 x i64> %214, ptr %210, align 16, !tbaa !21, !alias.scope !961, !noalias !970
  %215 = add nuw nsw i64 %197, 1
  %216 = icmp eq i64 %215, 4
  br i1 %216, label %217, label %196, !llvm.loop !82

217:                                              ; preds = %196
  call void @llvm.lifetime.end.p0(i64 64, ptr nonnull %2) #24
  br label %218

218:                                              ; preds = %157, %148, %178, %217
  %219 = getelementptr inbounds nuw i8, ptr %0, i64 512
  %220 = load ptr, ptr %219, align 16, !tbaa !322
  %221 = getelementptr inbounds nuw i8, ptr %220, i64 11
  %222 = mul i64 %5, -7046029288634856825
  call void @llvm.experimental.noalias.scope.decl(metadata !971)
  call void @llvm.experimental.noalias.scope.decl(metadata !974)
  call void @llvm.experimental.noalias.scope.decl(metadata !976)
  %223 = load i64, ptr %3, align 16, !tbaa !22, !alias.scope !979, !noalias !980
  %224 = load i64, ptr %221, align 1, !alias.scope !974, !noalias !979
  %225 = xor i64 %224, %223
  %226 = getelementptr inbounds nuw i8, ptr %3, i64 8
  %227 = load i64, ptr %226, align 8, !tbaa !22, !alias.scope !979, !noalias !980
  %228 = getelementptr inbounds nuw i8, ptr %220, i64 19
  %229 = load i64, ptr %228, align 1, !alias.scope !974, !noalias !979
  %230 = xor i64 %229, %227
  %231 = zext i64 %225 to i128
  %232 = zext i64 %230 to i128
  %233 = mul nuw i128 %232, %231
  %234 = lshr i128 %233, 64
  %235 = xor i128 %234, %233
  %236 = trunc i128 %235 to i64
  %237 = add i64 %222, %236
  %238 = getelementptr inbounds nuw i8, ptr %3, i64 16
  %239 = getelementptr inbounds nuw i8, ptr %220, i64 27
  call void @llvm.experimental.noalias.scope.decl(metadata !982)
  %240 = load i64, ptr %238, align 16, !tbaa !22, !alias.scope !985, !noalias !986
  %241 = load i64, ptr %239, align 1, !alias.scope !974, !noalias !985
  %242 = xor i64 %241, %240
  %243 = getelementptr inbounds nuw i8, ptr %3, i64 24
  %244 = load i64, ptr %243, align 8, !tbaa !22, !alias.scope !985, !noalias !986
  %245 = getelementptr inbounds nuw i8, ptr %220, i64 35
  %246 = load i64, ptr %245, align 1, !alias.scope !974, !noalias !985
  %247 = xor i64 %246, %244
  %248 = zext i64 %242 to i128
  %249 = zext i64 %247 to i128
  %250 = mul nuw i128 %249, %248
  %251 = lshr i128 %250, 64
  %252 = xor i128 %251, %250
  %253 = trunc i128 %252 to i64
  %254 = add i64 %237, %253
  %255 = getelementptr inbounds nuw i8, ptr %3, i64 32
  %256 = getelementptr inbounds nuw i8, ptr %220, i64 43
  call void @llvm.experimental.noalias.scope.decl(metadata !988)
  %257 = load i64, ptr %255, align 16, !tbaa !22, !alias.scope !991, !noalias !992
  %258 = load i64, ptr %256, align 1, !alias.scope !974, !noalias !991
  %259 = xor i64 %258, %257
  %260 = getelementptr inbounds nuw i8, ptr %3, i64 40
  %261 = load i64, ptr %260, align 8, !tbaa !22, !alias.scope !991, !noalias !992
  %262 = getelementptr inbounds nuw i8, ptr %220, i64 51
  %263 = load i64, ptr %262, align 1, !alias.scope !974, !noalias !991
  %264 = xor i64 %263, %261
  %265 = zext i64 %259 to i128
  %266 = zext i64 %264 to i128
  %267 = mul nuw i128 %266, %265
  %268 = lshr i128 %267, 64
  %269 = xor i128 %268, %267
  %270 = trunc i128 %269 to i64
  %271 = add i64 %254, %270
  %272 = getelementptr inbounds nuw i8, ptr %3, i64 48
  %273 = getelementptr inbounds nuw i8, ptr %220, i64 59
  call void @llvm.experimental.noalias.scope.decl(metadata !994)
  %274 = load i64, ptr %272, align 16, !tbaa !22, !alias.scope !997, !noalias !998
  %275 = load i64, ptr %273, align 1, !alias.scope !974, !noalias !997
  %276 = xor i64 %275, %274
  %277 = getelementptr inbounds nuw i8, ptr %3, i64 56
  %278 = load i64, ptr %277, align 8, !tbaa !22, !alias.scope !997, !noalias !998
  %279 = getelementptr inbounds nuw i8, ptr %220, i64 67
  %280 = load i64, ptr %279, align 1, !alias.scope !974, !noalias !997
  %281 = xor i64 %280, %278
  %282 = zext i64 %276 to i128
  %283 = zext i64 %281 to i128
  %284 = mul nuw i128 %283, %282
  %285 = lshr i128 %284, 64
  %286 = xor i128 %285, %284
  %287 = trunc i128 %286 to i64
  %288 = add i64 %271, %287
  %289 = lshr i64 %288, 37
  %290 = xor i64 %289, %288
  %291 = mul i64 %290, 1609587929392839161
  %292 = lshr i64 %291, 32
  %293 = xor i64 %292, %291
  %294 = getelementptr inbounds nuw i8, ptr %0, i64 540
  %295 = load i32, ptr %294, align 4, !tbaa !323
  %296 = zext i32 %295 to i64
  %297 = getelementptr inbounds nuw i8, ptr %220, i64 %296
  %298 = getelementptr inbounds i8, ptr %297, i64 -11
  %299 = mul i64 %5, -4417276706812531889
  %300 = xor i64 %299, -1
  %301 = load i64, ptr %298, align 1, !alias.scope !1000, !noalias !1003
  %302 = xor i64 %301, %223
  %303 = getelementptr inbounds i8, ptr %297, i64 -3
  %304 = load i64, ptr %303, align 1, !alias.scope !1000, !noalias !1003
  %305 = xor i64 %304, %227
  %306 = zext i64 %302 to i128
  %307 = zext i64 %305 to i128
  %308 = mul nuw i128 %307, %306
  %309 = lshr i128 %308, 64
  %310 = xor i128 %309, %308
  %311 = trunc i128 %310 to i64
  %312 = add i64 %311, %300
  %313 = getelementptr inbounds nuw i8, ptr %297, i64 5
  %314 = load i64, ptr %313, align 1, !alias.scope !1000, !noalias !1007
  %315 = xor i64 %314, %240
  %316 = getelementptr inbounds nuw i8, ptr %297, i64 13
  %317 = load i64, ptr %316, align 1, !alias.scope !1000, !noalias !1007
  %318 = xor i64 %317, %244
  %319 = zext i64 %315 to i128
  %320 = zext i64 %318 to i128
  %321 = mul nuw i128 %320, %319
  %322 = lshr i128 %321, 64
  %323 = xor i128 %322, %321
  %324 = trunc i128 %323 to i64
  %325 = add i64 %312, %324
  %326 = getelementptr inbounds nuw i8, ptr %297, i64 21
  %327 = load i64, ptr %326, align 1, !alias.scope !1000, !noalias !1010
  %328 = xor i64 %327, %257
  %329 = getelementptr inbounds nuw i8, ptr %297, i64 29
  %330 = load i64, ptr %329, align 1, !alias.scope !1000, !noalias !1010
  %331 = xor i64 %330, %261
  %332 = zext i64 %328 to i128
  %333 = zext i64 %331 to i128
  %334 = mul nuw i128 %333, %332
  %335 = lshr i128 %334, 64
  %336 = xor i128 %335, %334
  %337 = trunc i128 %336 to i64
  %338 = add i64 %325, %337
  %339 = getelementptr inbounds nuw i8, ptr %297, i64 37
  %340 = load i64, ptr %339, align 1, !alias.scope !1000, !noalias !1013
  %341 = xor i64 %340, %274
  %342 = getelementptr inbounds nuw i8, ptr %297, i64 45
  %343 = load i64, ptr %342, align 1, !alias.scope !1000, !noalias !1013
  %344 = xor i64 %343, %278
  %345 = zext i64 %341 to i128
  %346 = zext i64 %344 to i128
  %347 = mul nuw i128 %346, %345
  %348 = lshr i128 %347, 64
  %349 = xor i128 %348, %347
  %350 = trunc i128 %349 to i64
  %351 = add i64 %338, %350
  %352 = lshr i64 %351, 37
  %353 = xor i64 %352, %351
  %354 = mul i64 %353, 1609587929392839161
  %355 = lshr i64 %354, 32
  %356 = xor i64 %355, %354
  call void @llvm.lifetime.end.p0(i64 64, ptr nonnull %3) #24
  %357 = insertvalue [2 x i64] poison, i64 %293, 0
  %358 = insertvalue [2 x i64] %357, i64 %356, 1
  br label %374

359:                                              ; preds = %1
  %360 = getelementptr inbounds nuw i8, ptr %0, i64 552
  %361 = load i64, ptr %360, align 8, !tbaa !319
  %362 = icmp eq i64 %361, 0
  %363 = getelementptr inbounds nuw i8, ptr %0, i64 256
  br i1 %362, label %366, label %364

364:                                              ; preds = %359
  %365 = tail call [2 x i64] @XXH3_128bits_withSeed(ptr noundef nonnull %363, i64 noundef %5, i64 noundef %361)
  br label %374

366:                                              ; preds = %359
  %367 = getelementptr inbounds nuw i8, ptr %0, i64 512
  %368 = load ptr, ptr %367, align 16, !tbaa !322
  %369 = getelementptr inbounds nuw i8, ptr %0, i64 540
  %370 = load i32, ptr %369, align 4, !tbaa !323
  %371 = add i32 %370, 64
  %372 = zext i32 %371 to i64
  %373 = tail call [2 x i64] @XXH3_128bits_withSecret(ptr noundef nonnull %363, i64 noundef %5, ptr noundef %368, i64 noundef %372)
  br label %374

374:                                              ; preds = %366, %364, %218
  %375 = phi [2 x i64] [ %358, %218 ], [ %365, %364 ], [ %373, %366 ]
  ret [2 x i64] %375
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(none) uwtable(sync)
define range(i32 0, 2) i32 @XXH128_isEqual([2 x i64] %0, [2 x i64] %1) local_unnamed_addr #0 {
  %3 = alloca %struct.XXH128_hash_t, align 8
  %4 = alloca %struct.XXH128_hash_t, align 8
  %5 = extractvalue [2 x i64] %0, 0
  store i64 %5, ptr %3, align 8
  %6 = extractvalue [2 x i64] %0, 1
  %7 = getelementptr inbounds nuw i8, ptr %3, i64 8
  store i64 %6, ptr %7, align 8
  %8 = extractvalue [2 x i64] %1, 0
  store i64 %8, ptr %4, align 8
  %9 = extractvalue [2 x i64] %1, 1
  %10 = getelementptr inbounds nuw i8, ptr %4, i64 8
  store i64 %9, ptr %10, align 8
  %11 = call i32 @memcmp(ptr noundef nonnull dereferenceable(16) %3, ptr noundef nonnull dereferenceable(16) %4, i64 noundef 16)
  %12 = icmp eq i32 %11, 0
  %13 = zext i1 %12 to i32
  ret i32 %13
}

; Function Attrs: mustprogress nocallback nofree nounwind willreturn memory(argmem: read)
declare i32 @memcmp(ptr noundef captures(none), ptr noundef captures(none), i64 noundef) local_unnamed_addr #16

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(argmem: read) uwtable(sync)
define range(i32 -1, 2) i32 @XXH128_cmp(ptr noundef readonly captures(none) %0, ptr noundef readonly captures(none) %1) local_unnamed_addr #8 {
  %3 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %4 = load i64, ptr %3, align 8, !tbaa !22
  %5 = getelementptr inbounds nuw i8, ptr %1, i64 8
  %6 = load i64, ptr %5, align 8, !tbaa !22
  %7 = icmp eq i64 %4, %6
  br i1 %7, label %10, label %8

8:                                                ; preds = %2
  %9 = tail call i32 @llvm.ucmp.i32.i64(i64 %4, i64 %6)
  br label %14

10:                                               ; preds = %2
  %11 = load i64, ptr %1, align 8, !tbaa !22
  %12 = load i64, ptr %0, align 8, !tbaa !22
  %13 = tail call i32 @llvm.ucmp.i32.i64(i64 %12, i64 %11)
  br label %14

14:                                               ; preds = %10, %8
  %15 = phi i32 [ %9, %8 ], [ %13, %10 ]
  ret i32 %15
}

; Function Attrs: mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias writeonly captures(none), ptr noalias readonly captures(none), i64, i1 immarg) #17

; Function Attrs: nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync)
define void @XXH128_canonicalFromHash(ptr noundef %0, [2 x i64] %1) local_unnamed_addr #4 {
  %3 = extractvalue [2 x i64] %1, 0
  %4 = extractvalue [2 x i64] %1, 1
  %5 = tail call noundef i64 @llvm.bswap.i64(i64 %4)
  %6 = tail call noundef i64 @llvm.bswap.i64(i64 %3)
  store i64 %5, ptr %0, align 1
  %7 = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i64 %6, ptr %7, align 1
  ret void
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(argmem: read) uwtable(sync)
define [2 x i64] @XXH128_hashFromCanonical(ptr noundef readonly captures(none) %0) local_unnamed_addr #8 {
  %2 = load i64, ptr %0, align 1
  %3 = tail call noundef i64 @llvm.bswap.i64(i64 %2)
  %4 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %5 = load i64, ptr %4, align 1
  %6 = tail call noundef i64 @llvm.bswap.i64(i64 %5)
  %7 = insertvalue [2 x i64] poison, i64 %6, 0
  %8 = insertvalue [2 x i64] %7, i64 %3, 1
  ret [2 x i64] %8
}

; Function Attrs: mustprogress nofree nounwind willreturn allockind("alloc,uninitialized") allocsize(0) memory(inaccessiblemem: readwrite)
declare noalias noundef ptr @malloc(i64 noundef) local_unnamed_addr #18

; Function Attrs: mustprogress nounwind willreturn allockind("free") memory(argmem: readwrite, inaccessiblemem: readwrite)
declare void @free(ptr allocptr noundef captures(none)) local_unnamed_addr #19

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(none)
declare <2 x i64> @llvm.aarch64.neon.umull.v2i64(<2 x i32>, <2 x i32>) #20

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i32 @llvm.bswap.i32(i32) #21

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.bswap.i64(i64) #21

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare range(i32 -1, 2) i32 @llvm.ucmp.i32.i64(i64, i64) #21

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(inaccessiblemem: readwrite)
declare void @llvm.experimental.noalias.scope.decl(metadata) #22

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.umax.i64(i64, i64) #21

attributes #0 = { mustprogress nofree norecurse nosync nounwind ssp willreturn memory(none) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { nofree norecurse nosync nounwind ssp memory(argmem: read) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { mustprogress nofree nounwind ssp willreturn memory(inaccessiblemem: readwrite) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { mustprogress nounwind ssp willreturn memory(argmem: readwrite, inaccessiblemem: readwrite) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #4 = { nofree norecurse nounwind ssp memory(argmem: readwrite) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #5 = { nocallback nofree nounwind memory(argmem: readwrite) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #6 = { mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #7 = { mustprogress nocallback nofree nounwind willreturn memory(argmem: write) }
attributes #8 = { mustprogress nofree norecurse nosync nounwind ssp willreturn memory(argmem: read) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #9 = { mustprogress nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #10 = { nofree norecurse nosync nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #11 = { nofree noinline norecurse nosync nounwind ssp memory(argmem: read) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #12 = { nofree noinline norecurse nosync nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #13 = { nofree norecurse nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #14 = { nofree noinline norecurse nounwind ssp memory(argmem: read, inaccessiblemem: readwrite) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #15 = { nofree norecurse nounwind ssp memory(read, argmem: readwrite, inaccessiblemem: readwrite) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #16 = { mustprogress nocallback nofree nounwind willreturn memory(argmem: read) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #17 = { mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #18 = { mustprogress nofree nounwind willreturn allockind("alloc,uninitialized") allocsize(0) memory(inaccessiblemem: readwrite) "alloc-family"="malloc" "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #19 = { mustprogress nounwind willreturn allockind("free") memory(argmem: readwrite, inaccessiblemem: readwrite) "alloc-family"="malloc" "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #20 = { mustprogress nocallback nofree nosync nounwind willreturn memory(none) }
attributes #21 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #22 = { nocallback nofree nosync nounwind willreturn memory(inaccessiblemem: readwrite) }
attributes #23 = { allocsize(0) }
attributes #24 = { nounwind }

!llvm.module.flags = !{!0, !1, !2, !3}
!llvm.ident = !{!4}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 8, !"PIC Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 1}
!3 = !{i32 7, !"frame-pointer", i32 1}
!4 = !{!"Homebrew clang version 21.1.8"}
!5 = !{!6, !6, i64 0}
!6 = !{!"int", !7, i64 0}
!7 = !{!"omnipotent char", !8, i64 0}
!8 = !{!"Simple C/C++ TBAA"}
!9 = distinct !{!9, !10, !11}
!10 = !{!"llvm.loop.mustprogress"}
!11 = !{!"llvm.loop.unroll.disable"}
!12 = !{!13, !6, i64 0}
!13 = !{!"XXH32_state_s", !6, i64 0, !6, i64 4, !6, i64 8, !6, i64 12, !6, i64 16, !6, i64 20, !7, i64 24, !6, i64 40, !6, i64 44}
!14 = !{!13, !6, i64 4}
!15 = !{!13, !6, i64 40}
!16 = !{!13, !6, i64 8}
!17 = !{!13, !6, i64 12}
!18 = !{!13, !6, i64 16}
!19 = !{!13, !6, i64 20}
!20 = distinct !{!20, !10, !11}
!21 = !{!7, !7, i64 0}
!22 = !{!23, !23, i64 0}
!23 = !{!"long long", !7, i64 0}
!24 = distinct !{!24, !10, !11}
!25 = !{!26, !23, i64 0}
!26 = !{!"XXH64_state_s", !23, i64 0, !23, i64 8, !23, i64 16, !23, i64 24, !23, i64 32, !7, i64 40, !6, i64 72, !7, i64 76}
!27 = !{!26, !6, i64 72}
!28 = !{!26, !23, i64 8}
!29 = !{!26, !23, i64 16}
!30 = !{!26, !23, i64 24}
!31 = !{!26, !23, i64 32}
!32 = distinct !{!32, !10, !11}
!33 = !{!34}
!34 = distinct !{!34, !35, !"XXH3_mix16B: argument 1"}
!35 = distinct !{!35, !"XXH3_mix16B"}
!36 = !{!37}
!37 = distinct !{!37, !38, !"XXH3_mix16B: argument 1"}
!38 = distinct !{!38, !"XXH3_mix16B"}
!39 = !{!40}
!40 = distinct !{!40, !41, !"XXH3_mix16B: argument 1"}
!41 = distinct !{!41, !"XXH3_mix16B"}
!42 = !{!43}
!43 = distinct !{!43, !44, !"XXH3_mix16B: argument 1"}
!44 = distinct !{!44, !"XXH3_mix16B"}
!45 = !{!46}
!46 = distinct !{!46, !47, !"XXH3_mix16B: argument 1"}
!47 = distinct !{!47, !"XXH3_mix16B"}
!48 = !{!49}
!49 = distinct !{!49, !50, !"XXH3_mix16B: argument 1"}
!50 = distinct !{!50, !"XXH3_mix16B"}
!51 = !{!52}
!52 = distinct !{!52, !53, !"XXH3_mix16B: argument 1"}
!53 = distinct !{!53, !"XXH3_mix16B"}
!54 = !{!55}
!55 = distinct !{!55, !56, !"XXH3_mix16B: argument 1"}
!56 = distinct !{!56, !"XXH3_mix16B"}
!57 = !{!58}
!58 = distinct !{!58, !59, !"XXH3_mix16B: argument 1"}
!59 = distinct !{!59, !"XXH3_mix16B"}
!60 = distinct !{!60, !10, !11}
!61 = !{!62}
!62 = distinct !{!62, !63, !"XXH3_mix16B: argument 1"}
!63 = distinct !{!63, !"XXH3_mix16B"}
!64 = distinct !{!64, !10, !11}
!65 = !{!66}
!66 = distinct !{!66, !67, !"XXH3_mix16B: argument 1"}
!67 = distinct !{!67, !"XXH3_mix16B"}
!68 = !{!69, !71}
!69 = distinct !{!69, !70, !"XXH3_hashLong_internal: argument 0"}
!70 = distinct !{!70, !"XXH3_hashLong_internal"}
!71 = distinct !{!71, !70, !"XXH3_hashLong_internal: argument 1"}
!72 = !{!73}
!73 = distinct !{!73, !74, !"XXH3_accumulate_512: argument 0"}
!74 = distinct !{!74, !"XXH3_accumulate_512"}
!75 = !{!76}
!76 = distinct !{!76, !74, !"XXH3_accumulate_512: argument 1"}
!77 = !{!78}
!78 = distinct !{!78, !74, !"XXH3_accumulate_512: argument 2"}
!79 = !{!73, !78}
!80 = !{!73, !76}
!81 = !{!76, !78}
!82 = distinct !{!82, !10, !11}
!83 = distinct !{!83, !10, !11}
!84 = !{!85}
!85 = distinct !{!85, !86, !"XXH3_scrambleAcc: argument 0"}
!86 = distinct !{!86, !"XXH3_scrambleAcc"}
!87 = !{!88}
!88 = distinct !{!88, !86, !"XXH3_scrambleAcc: argument 1"}
!89 = distinct !{!89, !10, !11}
!90 = distinct !{!90, !10, !11}
!91 = !{!92}
!92 = distinct !{!92, !93, !"XXH3_accumulate_512: argument 0"}
!93 = distinct !{!93, !"XXH3_accumulate_512"}
!94 = !{!95}
!95 = distinct !{!95, !93, !"XXH3_accumulate_512: argument 1"}
!96 = !{!97}
!97 = distinct !{!97, !93, !"XXH3_accumulate_512: argument 2"}
!98 = !{!92, !97}
!99 = !{!92, !95}
!100 = !{!95, !97}
!101 = !{!102}
!102 = distinct !{!102, !103, !"XXH3_accumulate_512: argument 0"}
!103 = distinct !{!103, !"XXH3_accumulate_512"}
!104 = !{!105}
!105 = distinct !{!105, !103, !"XXH3_accumulate_512: argument 1"}
!106 = !{!107}
!107 = distinct !{!107, !103, !"XXH3_accumulate_512: argument 2"}
!108 = !{!102, !107}
!109 = !{!102, !105}
!110 = !{!105, !107}
!111 = !{!112, !114}
!112 = distinct !{!112, !113, !"XXH3_mix2Accs: argument 0"}
!113 = distinct !{!113, !"XXH3_mix2Accs"}
!114 = distinct !{!114, !115, !"XXH3_mergeAccs: argument 0"}
!115 = distinct !{!115, !"XXH3_mergeAccs"}
!116 = !{!117, !118}
!117 = distinct !{!117, !113, !"XXH3_mix2Accs: argument 1"}
!118 = distinct !{!118, !115, !"XXH3_mergeAccs: argument 1"}
!119 = !{!120, !114}
!120 = distinct !{!120, !121, !"XXH3_mix2Accs: argument 0"}
!121 = distinct !{!121, !"XXH3_mix2Accs"}
!122 = !{!123, !118}
!123 = distinct !{!123, !121, !"XXH3_mix2Accs: argument 1"}
!124 = !{!125, !114}
!125 = distinct !{!125, !126, !"XXH3_mix2Accs: argument 0"}
!126 = distinct !{!126, !"XXH3_mix2Accs"}
!127 = !{!128, !118}
!128 = distinct !{!128, !126, !"XXH3_mix2Accs: argument 1"}
!129 = !{!130, !114}
!130 = distinct !{!130, !131, !"XXH3_mix2Accs: argument 0"}
!131 = distinct !{!131, !"XXH3_mix2Accs"}
!132 = !{!133, !118}
!133 = distinct !{!133, !131, !"XXH3_mix2Accs: argument 1"}
!134 = !{!135}
!135 = distinct !{!135, !136, !"XXH3_mix16B: argument 1"}
!136 = distinct !{!136, !"XXH3_mix16B"}
!137 = !{!138}
!138 = distinct !{!138, !139, !"XXH3_mix16B: argument 1"}
!139 = distinct !{!139, !"XXH3_mix16B"}
!140 = !{!141}
!141 = distinct !{!141, !142, !"XXH3_mix16B: argument 1"}
!142 = distinct !{!142, !"XXH3_mix16B"}
!143 = !{!144}
!144 = distinct !{!144, !145, !"XXH3_mix16B: argument 1"}
!145 = distinct !{!145, !"XXH3_mix16B"}
!146 = !{!147}
!147 = distinct !{!147, !148, !"XXH3_mix16B: argument 1"}
!148 = distinct !{!148, !"XXH3_mix16B"}
!149 = !{!150}
!150 = distinct !{!150, !151, !"XXH3_mix16B: argument 1"}
!151 = distinct !{!151, !"XXH3_mix16B"}
!152 = !{!153}
!153 = distinct !{!153, !154, !"XXH3_mix16B: argument 1"}
!154 = distinct !{!154, !"XXH3_mix16B"}
!155 = !{!156}
!156 = distinct !{!156, !157, !"XXH3_mix16B: argument 1"}
!157 = distinct !{!157, !"XXH3_mix16B"}
!158 = !{!159, !161}
!159 = distinct !{!159, !160, !"XXH3_hashLong_internal: argument 0"}
!160 = distinct !{!160, !"XXH3_hashLong_internal"}
!161 = distinct !{!161, !160, !"XXH3_hashLong_internal: argument 1"}
!162 = !{!163}
!163 = distinct !{!163, !164, !"XXH3_accumulate_512: argument 0"}
!164 = distinct !{!164, !"XXH3_accumulate_512"}
!165 = !{!166}
!166 = distinct !{!166, !164, !"XXH3_accumulate_512: argument 1"}
!167 = !{!168}
!168 = distinct !{!168, !164, !"XXH3_accumulate_512: argument 2"}
!169 = !{!163, !168}
!170 = !{!163, !166}
!171 = !{!166, !168}
!172 = !{!173}
!173 = distinct !{!173, !174, !"XXH3_scrambleAcc: argument 0"}
!174 = distinct !{!174, !"XXH3_scrambleAcc"}
!175 = !{!176}
!176 = distinct !{!176, !174, !"XXH3_scrambleAcc: argument 1"}
!177 = !{!178}
!178 = distinct !{!178, !179, !"XXH3_accumulate_512: argument 0"}
!179 = distinct !{!179, !"XXH3_accumulate_512"}
!180 = !{!181}
!181 = distinct !{!181, !179, !"XXH3_accumulate_512: argument 1"}
!182 = !{!183}
!183 = distinct !{!183, !179, !"XXH3_accumulate_512: argument 2"}
!184 = !{!178, !183}
!185 = !{!178, !181}
!186 = !{!181, !183}
!187 = !{!188}
!188 = distinct !{!188, !189, !"XXH3_accumulate_512: argument 0"}
!189 = distinct !{!189, !"XXH3_accumulate_512"}
!190 = !{!191}
!191 = distinct !{!191, !189, !"XXH3_accumulate_512: argument 1"}
!192 = !{!193}
!193 = distinct !{!193, !189, !"XXH3_accumulate_512: argument 2"}
!194 = !{!188, !193}
!195 = !{!188, !191}
!196 = !{!191, !193}
!197 = !{!198}
!198 = distinct !{!198, !199, !"XXH3_mergeAccs: argument 0"}
!199 = distinct !{!199, !"XXH3_mergeAccs"}
!200 = !{!201}
!201 = distinct !{!201, !199, !"XXH3_mergeAccs: argument 1"}
!202 = !{!203}
!203 = distinct !{!203, !204, !"XXH3_mix2Accs: argument 0"}
!204 = distinct !{!204, !"XXH3_mix2Accs"}
!205 = !{!203, !198}
!206 = !{!207, !201}
!207 = distinct !{!207, !204, !"XXH3_mix2Accs: argument 1"}
!208 = !{!209}
!209 = distinct !{!209, !210, !"XXH3_mix2Accs: argument 0"}
!210 = distinct !{!210, !"XXH3_mix2Accs"}
!211 = !{!209, !198}
!212 = !{!213, !201}
!213 = distinct !{!213, !210, !"XXH3_mix2Accs: argument 1"}
!214 = !{!215}
!215 = distinct !{!215, !216, !"XXH3_mix2Accs: argument 0"}
!216 = distinct !{!216, !"XXH3_mix2Accs"}
!217 = !{!215, !198}
!218 = !{!219, !201}
!219 = distinct !{!219, !216, !"XXH3_mix2Accs: argument 1"}
!220 = !{!221}
!221 = distinct !{!221, !222, !"XXH3_mix2Accs: argument 0"}
!222 = distinct !{!222, !"XXH3_mix2Accs"}
!223 = !{!221, !198}
!224 = !{!225, !201}
!225 = distinct !{!225, !222, !"XXH3_mix2Accs: argument 1"}
!226 = !{!227}
!227 = distinct !{!227, !228, !"XXH3_mix16B: argument 1"}
!228 = distinct !{!228, !"XXH3_mix16B"}
!229 = !{!230}
!230 = distinct !{!230, !231, !"XXH3_mix16B: argument 1"}
!231 = distinct !{!231, !"XXH3_mix16B"}
!232 = !{!233}
!233 = distinct !{!233, !234, !"XXH3_mix16B: argument 1"}
!234 = distinct !{!234, !"XXH3_mix16B"}
!235 = !{!236}
!236 = distinct !{!236, !237, !"XXH3_mix16B: argument 1"}
!237 = distinct !{!237, !"XXH3_mix16B"}
!238 = !{!239}
!239 = distinct !{!239, !240, !"XXH3_mix16B: argument 1"}
!240 = distinct !{!240, !"XXH3_mix16B"}
!241 = !{!242}
!242 = distinct !{!242, !243, !"XXH3_mix16B: argument 1"}
!243 = distinct !{!243, !"XXH3_mix16B"}
!244 = !{!245}
!245 = distinct !{!245, !246, !"XXH3_mix16B: argument 1"}
!246 = distinct !{!246, !"XXH3_mix16B"}
!247 = !{!248}
!248 = distinct !{!248, !249, !"XXH3_mix16B: argument 1"}
!249 = distinct !{!249, !"XXH3_mix16B"}
!250 = distinct !{!250, !10, !11}
!251 = !{!252, !254}
!252 = distinct !{!252, !253, !"XXH3_hashLong_internal: argument 0"}
!253 = distinct !{!253, !"XXH3_hashLong_internal"}
!254 = distinct !{!254, !253, !"XXH3_hashLong_internal: argument 1"}
!255 = !{!256}
!256 = distinct !{!256, !257, !"XXH3_accumulate_512: argument 0"}
!257 = distinct !{!257, !"XXH3_accumulate_512"}
!258 = !{!259}
!259 = distinct !{!259, !257, !"XXH3_accumulate_512: argument 1"}
!260 = !{!261}
!261 = distinct !{!261, !257, !"XXH3_accumulate_512: argument 2"}
!262 = !{!256, !261}
!263 = !{!256, !259}
!264 = !{!259, !261}
!265 = !{!266}
!266 = distinct !{!266, !267, !"XXH3_scrambleAcc: argument 0"}
!267 = distinct !{!267, !"XXH3_scrambleAcc"}
!268 = !{!269}
!269 = distinct !{!269, !267, !"XXH3_scrambleAcc: argument 1"}
!270 = !{!271}
!271 = distinct !{!271, !272, !"XXH3_accumulate_512: argument 0"}
!272 = distinct !{!272, !"XXH3_accumulate_512"}
!273 = !{!274}
!274 = distinct !{!274, !272, !"XXH3_accumulate_512: argument 1"}
!275 = !{!276}
!276 = distinct !{!276, !272, !"XXH3_accumulate_512: argument 2"}
!277 = !{!271, !276}
!278 = !{!271, !274}
!279 = !{!274, !276}
!280 = !{!281}
!281 = distinct !{!281, !282, !"XXH3_accumulate_512: argument 0"}
!282 = distinct !{!282, !"XXH3_accumulate_512"}
!283 = !{!284}
!284 = distinct !{!284, !282, !"XXH3_accumulate_512: argument 1"}
!285 = !{!286}
!286 = distinct !{!286, !282, !"XXH3_accumulate_512: argument 2"}
!287 = !{!281, !286}
!288 = !{!281, !284}
!289 = !{!284, !286}
!290 = !{!291}
!291 = distinct !{!291, !292, !"XXH3_mergeAccs: argument 0"}
!292 = distinct !{!292, !"XXH3_mergeAccs"}
!293 = !{!294}
!294 = distinct !{!294, !292, !"XXH3_mergeAccs: argument 1"}
!295 = !{!296}
!296 = distinct !{!296, !297, !"XXH3_mix2Accs: argument 0"}
!297 = distinct !{!297, !"XXH3_mix2Accs"}
!298 = !{!296, !291}
!299 = !{!300, !294}
!300 = distinct !{!300, !297, !"XXH3_mix2Accs: argument 1"}
!301 = !{!302}
!302 = distinct !{!302, !303, !"XXH3_mix2Accs: argument 0"}
!303 = distinct !{!303, !"XXH3_mix2Accs"}
!304 = !{!302, !291}
!305 = !{!306, !294}
!306 = distinct !{!306, !303, !"XXH3_mix2Accs: argument 1"}
!307 = !{!308}
!308 = distinct !{!308, !309, !"XXH3_mix2Accs: argument 0"}
!309 = distinct !{!309, !"XXH3_mix2Accs"}
!310 = !{!308, !291}
!311 = !{!312, !294}
!312 = distinct !{!312, !309, !"XXH3_mix2Accs: argument 1"}
!313 = !{!314}
!314 = distinct !{!314, !315, !"XXH3_mix2Accs: argument 0"}
!315 = distinct !{!315, !"XXH3_mix2Accs"}
!316 = !{!314, !291}
!317 = !{!318, !294}
!318 = distinct !{!318, !315, !"XXH3_mix2Accs: argument 1"}
!319 = !{!320, !23, i64 552}
!320 = !{!"XXH3_state_s", !7, i64 0, !7, i64 64, !7, i64 256, !321, i64 512, !6, i64 520, !6, i64 524, !6, i64 528, !6, i64 532, !6, i64 536, !6, i64 540, !23, i64 544, !23, i64 552, !23, i64 560}
!321 = !{!"any pointer", !7, i64 0}
!322 = !{!320, !321, i64 512}
!323 = !{!320, !6, i64 540}
!324 = !{!320, !6, i64 524}
!325 = !{!320, !23, i64 544}
!326 = !{!320, !6, i64 520}
!327 = !{!328}
!328 = distinct !{!328, !329, !"XXH3_accumulate_512: argument 0"}
!329 = distinct !{!329, !"XXH3_accumulate_512"}
!330 = !{!331}
!331 = distinct !{!331, !329, !"XXH3_accumulate_512: argument 1"}
!332 = !{!333}
!333 = distinct !{!333, !329, !"XXH3_accumulate_512: argument 2"}
!334 = !{!328, !333}
!335 = !{!328, !331}
!336 = !{!331, !333}
!337 = !{!338}
!338 = distinct !{!338, !339, !"XXH3_scrambleAcc: argument 0"}
!339 = distinct !{!339, !"XXH3_scrambleAcc"}
!340 = !{!341}
!341 = distinct !{!341, !339, !"XXH3_scrambleAcc: argument 1"}
!342 = !{!343}
!343 = distinct !{!343, !344, !"XXH3_accumulate_512: argument 0"}
!344 = distinct !{!344, !"XXH3_accumulate_512"}
!345 = !{!346}
!346 = distinct !{!346, !344, !"XXH3_accumulate_512: argument 1"}
!347 = !{!348}
!348 = distinct !{!348, !344, !"XXH3_accumulate_512: argument 2"}
!349 = !{!343, !348}
!350 = !{!343, !346}
!351 = !{!346, !348}
!352 = !{!353}
!353 = distinct !{!353, !354, !"XXH3_accumulate_512: argument 0"}
!354 = distinct !{!354, !"XXH3_accumulate_512"}
!355 = !{!356}
!356 = distinct !{!356, !354, !"XXH3_accumulate_512: argument 1"}
!357 = !{!358}
!358 = distinct !{!358, !354, !"XXH3_accumulate_512: argument 2"}
!359 = !{!353, !358}
!360 = !{!353, !356}
!361 = !{!356, !358}
!362 = !{!363}
!363 = distinct !{!363, !364, !"XXH3_accumulate_512: argument 0"}
!364 = distinct !{!364, !"XXH3_accumulate_512"}
!365 = !{!366}
!366 = distinct !{!366, !364, !"XXH3_accumulate_512: argument 1"}
!367 = !{!368}
!368 = distinct !{!368, !364, !"XXH3_accumulate_512: argument 2"}
!369 = !{!363, !368}
!370 = !{!363, !366}
!371 = !{!366, !368}
!372 = !{!373}
!373 = distinct !{!373, !374, !"XXH3_scrambleAcc: argument 0"}
!374 = distinct !{!374, !"XXH3_scrambleAcc"}
!375 = !{!376}
!376 = distinct !{!376, !374, !"XXH3_scrambleAcc: argument 1"}
!377 = !{!378}
!378 = distinct !{!378, !379, !"XXH3_accumulate_512: argument 0"}
!379 = distinct !{!379, !"XXH3_accumulate_512"}
!380 = !{!381}
!381 = distinct !{!381, !379, !"XXH3_accumulate_512: argument 1"}
!382 = !{!383}
!383 = distinct !{!383, !379, !"XXH3_accumulate_512: argument 2"}
!384 = !{!378, !383}
!385 = !{!378, !381}
!386 = !{!381, !383}
!387 = !{!388}
!388 = distinct !{!388, !389, !"XXH3_accumulate_512: argument 0"}
!389 = distinct !{!389, !"XXH3_accumulate_512"}
!390 = !{!391}
!391 = distinct !{!391, !389, !"XXH3_accumulate_512: argument 1"}
!392 = !{!393}
!393 = distinct !{!393, !389, !"XXH3_accumulate_512: argument 2"}
!394 = !{!388, !393}
!395 = !{!388, !391}
!396 = !{!391, !393}
!397 = distinct !{!397, !10, !11}
!398 = !{!320, !6, i64 528}
!399 = !{!400}
!400 = distinct !{!400, !401, !"XXH3_accumulate_512: argument 0"}
!401 = distinct !{!401, !"XXH3_accumulate_512"}
!402 = !{!403}
!403 = distinct !{!403, !401, !"XXH3_accumulate_512: argument 1"}
!404 = !{!405}
!405 = distinct !{!405, !401, !"XXH3_accumulate_512: argument 2"}
!406 = !{!400, !405}
!407 = !{!400, !403}
!408 = !{!403, !405}
!409 = !{!410}
!410 = distinct !{!410, !411, !"XXH3_scrambleAcc: argument 0"}
!411 = distinct !{!411, !"XXH3_scrambleAcc"}
!412 = !{!413}
!413 = distinct !{!413, !411, !"XXH3_scrambleAcc: argument 1"}
!414 = !{!415}
!415 = distinct !{!415, !416, !"XXH3_accumulate_512: argument 0"}
!416 = distinct !{!416, !"XXH3_accumulate_512"}
!417 = !{!418}
!418 = distinct !{!418, !416, !"XXH3_accumulate_512: argument 1"}
!419 = !{!420}
!420 = distinct !{!420, !416, !"XXH3_accumulate_512: argument 2"}
!421 = !{!415, !420}
!422 = !{!415, !418}
!423 = !{!418, !420}
!424 = !{!425}
!425 = distinct !{!425, !426, !"XXH3_accumulate_512: argument 0"}
!426 = distinct !{!426, !"XXH3_accumulate_512"}
!427 = !{!428}
!428 = distinct !{!428, !426, !"XXH3_accumulate_512: argument 1"}
!429 = !{!430}
!430 = distinct !{!430, !426, !"XXH3_accumulate_512: argument 2"}
!431 = !{!425, !430}
!432 = !{!425, !428}
!433 = !{!428, !430}
!434 = !{!435}
!435 = distinct !{!435, !436, !"XXH3_accumulate_512: argument 0"}
!436 = distinct !{!436, !"XXH3_accumulate_512"}
!437 = !{!438}
!438 = distinct !{!438, !436, !"XXH3_accumulate_512: argument 1"}
!439 = !{!440}
!440 = distinct !{!440, !436, !"XXH3_accumulate_512: argument 2"}
!441 = !{!435, !440}
!442 = !{!435, !438}
!443 = !{!438, !440}
!444 = !{!445}
!445 = distinct !{!445, !446, !"XXH3_accumulate_512: argument 0"}
!446 = distinct !{!446, !"XXH3_accumulate_512"}
!447 = !{!448}
!448 = distinct !{!448, !446, !"XXH3_accumulate_512: argument 1"}
!449 = !{!450}
!450 = distinct !{!450, !446, !"XXH3_accumulate_512: argument 2"}
!451 = !{!445, !450}
!452 = !{!445, !448}
!453 = !{!448, !450}
!454 = !{!455}
!455 = distinct !{!455, !456, !"XXH3_mergeAccs: argument 0"}
!456 = distinct !{!456, !"XXH3_mergeAccs"}
!457 = !{!458}
!458 = distinct !{!458, !456, !"XXH3_mergeAccs: argument 1"}
!459 = !{!460}
!460 = distinct !{!460, !461, !"XXH3_mix2Accs: argument 0"}
!461 = distinct !{!461, !"XXH3_mix2Accs"}
!462 = !{!460, !455}
!463 = !{!464, !458}
!464 = distinct !{!464, !461, !"XXH3_mix2Accs: argument 1"}
!465 = !{!466}
!466 = distinct !{!466, !467, !"XXH3_mix2Accs: argument 0"}
!467 = distinct !{!467, !"XXH3_mix2Accs"}
!468 = !{!466, !455}
!469 = !{!470, !458}
!470 = distinct !{!470, !467, !"XXH3_mix2Accs: argument 1"}
!471 = !{!472}
!472 = distinct !{!472, !473, !"XXH3_mix2Accs: argument 0"}
!473 = distinct !{!473, !"XXH3_mix2Accs"}
!474 = !{!472, !455}
!475 = !{!476, !458}
!476 = distinct !{!476, !473, !"XXH3_mix2Accs: argument 1"}
!477 = !{!478}
!478 = distinct !{!478, !479, !"XXH3_mix2Accs: argument 0"}
!479 = distinct !{!479, !"XXH3_mix2Accs"}
!480 = !{!478, !455}
!481 = !{!482, !458}
!482 = distinct !{!482, !479, !"XXH3_mix2Accs: argument 1"}
!483 = !{!484}
!484 = distinct !{!484, !485, !"XXH3_mix16B: argument 1"}
!485 = distinct !{!485, !"XXH3_mix16B"}
!486 = !{!487}
!487 = distinct !{!487, !488, !"XXH3_mix16B: argument 1"}
!488 = distinct !{!488, !"XXH3_mix16B"}
!489 = !{!490}
!490 = distinct !{!490, !491, !"XXH3_mix16B: argument 1"}
!491 = distinct !{!491, !"XXH3_mix16B"}
!492 = !{!493}
!493 = distinct !{!493, !494, !"XXH3_mix16B: argument 1"}
!494 = distinct !{!494, !"XXH3_mix16B"}
!495 = !{!496}
!496 = distinct !{!496, !497, !"XXH3_mix16B: argument 1"}
!497 = distinct !{!497, !"XXH3_mix16B"}
!498 = !{!499}
!499 = distinct !{!499, !500, !"XXH3_mix16B: argument 1"}
!500 = distinct !{!500, !"XXH3_mix16B"}
!501 = !{!502}
!502 = distinct !{!502, !503, !"XXH3_mix16B: argument 1"}
!503 = distinct !{!503, !"XXH3_mix16B"}
!504 = !{!505}
!505 = distinct !{!505, !506, !"XXH3_mix16B: argument 1"}
!506 = distinct !{!506, !"XXH3_mix16B"}
!507 = !{!508}
!508 = distinct !{!508, !509, !"XXH3_mix16B: argument 1"}
!509 = distinct !{!509, !"XXH3_mix16B"}
!510 = !{!511}
!511 = distinct !{!511, !512, !"XXH3_mix16B: argument 1"}
!512 = distinct !{!512, !"XXH3_mix16B"}
!513 = distinct !{!513, !10, !11}
!514 = !{!515}
!515 = distinct !{!515, !516, !"XXH3_mix16B: argument 1"}
!516 = distinct !{!516, !"XXH3_mix16B"}
!517 = !{!518}
!518 = distinct !{!518, !519, !"XXH3_mix16B: argument 1"}
!519 = distinct !{!519, !"XXH3_mix16B"}
!520 = distinct !{!520, !10, !11}
!521 = !{!522}
!522 = distinct !{!522, !523, !"XXH3_mix16B: argument 1"}
!523 = distinct !{!523, !"XXH3_mix16B"}
!524 = !{!525}
!525 = distinct !{!525, !526, !"XXH3_mix16B: argument 1"}
!526 = distinct !{!526, !"XXH3_mix16B"}
!527 = !{!528}
!528 = distinct !{!528, !529, !"XXH3_hashLong_128b_internal: argument 0"}
!529 = distinct !{!529, !"XXH3_hashLong_128b_internal"}
!530 = !{!531}
!531 = distinct !{!531, !529, !"XXH3_hashLong_128b_internal: argument 1"}
!532 = !{!528, !531}
!533 = !{!534}
!534 = distinct !{!534, !535, !"XXH3_accumulate_512: argument 0"}
!535 = distinct !{!535, !"XXH3_accumulate_512"}
!536 = !{!537}
!537 = distinct !{!537, !535, !"XXH3_accumulate_512: argument 1"}
!538 = !{!539}
!539 = distinct !{!539, !535, !"XXH3_accumulate_512: argument 2"}
!540 = !{!537, !528}
!541 = !{!534, !539, !531}
!542 = !{!539, !531}
!543 = !{!534, !537, !528}
!544 = !{!537, !539, !528, !531}
!545 = !{!546}
!546 = distinct !{!546, !547, !"XXH3_scrambleAcc: argument 0"}
!547 = distinct !{!547, !"XXH3_scrambleAcc"}
!548 = !{!549}
!549 = distinct !{!549, !547, !"XXH3_scrambleAcc: argument 1"}
!550 = !{!549, !528, !531}
!551 = !{!549, !531}
!552 = !{!546, !528}
!553 = !{!554}
!554 = distinct !{!554, !555, !"XXH3_accumulate_512: argument 0"}
!555 = distinct !{!555, !"XXH3_accumulate_512"}
!556 = !{!557}
!557 = distinct !{!557, !555, !"XXH3_accumulate_512: argument 1"}
!558 = !{!559}
!559 = distinct !{!559, !555, !"XXH3_accumulate_512: argument 2"}
!560 = !{!557, !528}
!561 = !{!554, !559, !531}
!562 = !{!559, !531}
!563 = !{!554, !557, !528}
!564 = !{!557, !559, !528, !531}
!565 = !{!566}
!566 = distinct !{!566, !567, !"XXH3_accumulate_512: argument 0"}
!567 = distinct !{!567, !"XXH3_accumulate_512"}
!568 = !{!569}
!569 = distinct !{!569, !567, !"XXH3_accumulate_512: argument 1"}
!570 = !{!571}
!571 = distinct !{!571, !567, !"XXH3_accumulate_512: argument 2"}
!572 = !{!569, !528}
!573 = !{!566, !571, !531}
!574 = !{!571, !531}
!575 = !{!566, !569, !528}
!576 = !{!569, !571, !528, !531}
!577 = !{!578, !580}
!578 = distinct !{!578, !579, !"XXH3_mix2Accs: argument 0"}
!579 = distinct !{!579, !"XXH3_mix2Accs"}
!580 = distinct !{!580, !581, !"XXH3_mergeAccs: argument 0"}
!581 = distinct !{!581, !"XXH3_mergeAccs"}
!582 = !{!583, !584, !528}
!583 = distinct !{!583, !579, !"XXH3_mix2Accs: argument 1"}
!584 = distinct !{!584, !581, !"XXH3_mergeAccs: argument 1"}
!585 = !{!586, !580}
!586 = distinct !{!586, !587, !"XXH3_mix2Accs: argument 0"}
!587 = distinct !{!587, !"XXH3_mix2Accs"}
!588 = !{!589, !584, !528}
!589 = distinct !{!589, !587, !"XXH3_mix2Accs: argument 1"}
!590 = !{!591, !580}
!591 = distinct !{!591, !592, !"XXH3_mix2Accs: argument 0"}
!592 = distinct !{!592, !"XXH3_mix2Accs"}
!593 = !{!594, !584, !528}
!594 = distinct !{!594, !592, !"XXH3_mix2Accs: argument 1"}
!595 = !{!596, !580}
!596 = distinct !{!596, !597, !"XXH3_mix2Accs: argument 0"}
!597 = distinct !{!597, !"XXH3_mix2Accs"}
!598 = !{!599, !584, !528}
!599 = distinct !{!599, !597, !"XXH3_mix2Accs: argument 1"}
!600 = !{!601}
!601 = distinct !{!601, !602, !"XXH3_mix16B: argument 1"}
!602 = distinct !{!602, !"XXH3_mix16B"}
!603 = !{!604}
!604 = distinct !{!604, !605, !"XXH3_mix16B: argument 1"}
!605 = distinct !{!605, !"XXH3_mix16B"}
!606 = !{!607}
!607 = distinct !{!607, !608, !"XXH3_mix16B: argument 1"}
!608 = distinct !{!608, !"XXH3_mix16B"}
!609 = !{!610}
!610 = distinct !{!610, !611, !"XXH3_mix16B: argument 1"}
!611 = distinct !{!611, !"XXH3_mix16B"}
!612 = !{!613}
!613 = distinct !{!613, !614, !"XXH3_mix16B: argument 1"}
!614 = distinct !{!614, !"XXH3_mix16B"}
!615 = !{!616}
!616 = distinct !{!616, !617, !"XXH3_mix16B: argument 1"}
!617 = distinct !{!617, !"XXH3_mix16B"}
!618 = !{!619}
!619 = distinct !{!619, !620, !"XXH3_mix16B: argument 1"}
!620 = distinct !{!620, !"XXH3_mix16B"}
!621 = !{!622}
!622 = distinct !{!622, !623, !"XXH3_mix16B: argument 1"}
!623 = distinct !{!623, !"XXH3_mix16B"}
!624 = !{!625}
!625 = distinct !{!625, !626, !"XXH3_hashLong_128b_internal: argument 0"}
!626 = distinct !{!626, !"XXH3_hashLong_128b_internal"}
!627 = !{!628}
!628 = distinct !{!628, !626, !"XXH3_hashLong_128b_internal: argument 1"}
!629 = !{!625, !628}
!630 = !{!631}
!631 = distinct !{!631, !632, !"XXH3_accumulate_512: argument 0"}
!632 = distinct !{!632, !"XXH3_accumulate_512"}
!633 = !{!634}
!634 = distinct !{!634, !632, !"XXH3_accumulate_512: argument 1"}
!635 = !{!636}
!636 = distinct !{!636, !632, !"XXH3_accumulate_512: argument 2"}
!637 = !{!634, !625}
!638 = !{!631, !636, !628}
!639 = !{!636, !628}
!640 = !{!631, !634, !625}
!641 = !{!634, !636, !625, !628}
!642 = !{!643}
!643 = distinct !{!643, !644, !"XXH3_scrambleAcc: argument 0"}
!644 = distinct !{!644, !"XXH3_scrambleAcc"}
!645 = !{!646}
!646 = distinct !{!646, !644, !"XXH3_scrambleAcc: argument 1"}
!647 = !{!646, !625, !628}
!648 = !{!646, !628}
!649 = !{!643, !625}
!650 = !{!651}
!651 = distinct !{!651, !652, !"XXH3_accumulate_512: argument 0"}
!652 = distinct !{!652, !"XXH3_accumulate_512"}
!653 = !{!654}
!654 = distinct !{!654, !652, !"XXH3_accumulate_512: argument 1"}
!655 = !{!656}
!656 = distinct !{!656, !652, !"XXH3_accumulate_512: argument 2"}
!657 = !{!654, !625}
!658 = !{!651, !656, !628}
!659 = !{!656, !628}
!660 = !{!651, !654, !625}
!661 = !{!654, !656, !625, !628}
!662 = !{!663}
!663 = distinct !{!663, !664, !"XXH3_accumulate_512: argument 0"}
!664 = distinct !{!664, !"XXH3_accumulate_512"}
!665 = !{!666}
!666 = distinct !{!666, !664, !"XXH3_accumulate_512: argument 1"}
!667 = !{!668}
!668 = distinct !{!668, !664, !"XXH3_accumulate_512: argument 2"}
!669 = !{!666, !625}
!670 = !{!663, !668, !628}
!671 = !{!668, !628}
!672 = !{!663, !666, !625}
!673 = !{!666, !668, !625, !628}
!674 = !{!675}
!675 = distinct !{!675, !676, !"XXH3_mergeAccs: argument 0"}
!676 = distinct !{!676, !"XXH3_mergeAccs"}
!677 = !{!678}
!678 = distinct !{!678, !676, !"XXH3_mergeAccs: argument 1"}
!679 = !{!680}
!680 = distinct !{!680, !681, !"XXH3_mix2Accs: argument 0"}
!681 = distinct !{!681, !"XXH3_mix2Accs"}
!682 = !{!680, !675}
!683 = !{!684, !678, !625}
!684 = distinct !{!684, !681, !"XXH3_mix2Accs: argument 1"}
!685 = !{!680, !675, !625}
!686 = !{!687}
!687 = distinct !{!687, !688, !"XXH3_mix2Accs: argument 0"}
!688 = distinct !{!688, !"XXH3_mix2Accs"}
!689 = !{!687, !675}
!690 = !{!691, !678, !625}
!691 = distinct !{!691, !688, !"XXH3_mix2Accs: argument 1"}
!692 = !{!687, !675, !625}
!693 = !{!694}
!694 = distinct !{!694, !695, !"XXH3_mix2Accs: argument 0"}
!695 = distinct !{!695, !"XXH3_mix2Accs"}
!696 = !{!694, !675}
!697 = !{!698, !678, !625}
!698 = distinct !{!698, !695, !"XXH3_mix2Accs: argument 1"}
!699 = !{!694, !675, !625}
!700 = !{!701}
!701 = distinct !{!701, !702, !"XXH3_mix2Accs: argument 0"}
!702 = distinct !{!702, !"XXH3_mix2Accs"}
!703 = !{!701, !675}
!704 = !{!705, !678, !625}
!705 = distinct !{!705, !702, !"XXH3_mix2Accs: argument 1"}
!706 = !{!701, !675, !625}
!707 = !{!708}
!708 = distinct !{!708, !709, !"XXH3_mergeAccs: argument 1"}
!709 = distinct !{!709, !"XXH3_mergeAccs"}
!710 = !{!711, !713, !625}
!711 = distinct !{!711, !712, !"XXH3_mix2Accs: argument 0"}
!712 = distinct !{!712, !"XXH3_mix2Accs"}
!713 = distinct !{!713, !709, !"XXH3_mergeAccs: argument 0"}
!714 = !{!715, !713, !625}
!715 = distinct !{!715, !716, !"XXH3_mix2Accs: argument 0"}
!716 = distinct !{!716, !"XXH3_mix2Accs"}
!717 = !{!718, !713, !625}
!718 = distinct !{!718, !719, !"XXH3_mix2Accs: argument 0"}
!719 = distinct !{!719, !"XXH3_mix2Accs"}
!720 = !{!721, !713, !625}
!721 = distinct !{!721, !722, !"XXH3_mix2Accs: argument 0"}
!722 = distinct !{!722, !"XXH3_mix2Accs"}
!723 = !{!724}
!724 = distinct !{!724, !725, !"XXH3_mix16B: argument 1"}
!725 = distinct !{!725, !"XXH3_mix16B"}
!726 = !{!727}
!727 = distinct !{!727, !728, !"XXH3_mix16B: argument 1"}
!728 = distinct !{!728, !"XXH3_mix16B"}
!729 = !{!730}
!730 = distinct !{!730, !731, !"XXH3_mix16B: argument 1"}
!731 = distinct !{!731, !"XXH3_mix16B"}
!732 = !{!733}
!733 = distinct !{!733, !734, !"XXH3_mix16B: argument 1"}
!734 = distinct !{!734, !"XXH3_mix16B"}
!735 = !{!736}
!736 = distinct !{!736, !737, !"XXH3_mix16B: argument 1"}
!737 = distinct !{!737, !"XXH3_mix16B"}
!738 = !{!739}
!739 = distinct !{!739, !740, !"XXH3_mix16B: argument 1"}
!740 = distinct !{!740, !"XXH3_mix16B"}
!741 = !{!742}
!742 = distinct !{!742, !743, !"XXH3_mix16B: argument 1"}
!743 = distinct !{!743, !"XXH3_mix16B"}
!744 = !{!745}
!745 = distinct !{!745, !746, !"XXH3_mix16B: argument 1"}
!746 = distinct !{!746, !"XXH3_mix16B"}
!747 = !{!748}
!748 = distinct !{!748, !749, !"XXH3_hashLong_128b_internal: argument 0"}
!749 = distinct !{!749, !"XXH3_hashLong_128b_internal"}
!750 = !{!751}
!751 = distinct !{!751, !749, !"XXH3_hashLong_128b_internal: argument 1"}
!752 = !{!748, !751}
!753 = !{!754}
!754 = distinct !{!754, !755, !"XXH3_accumulate_512: argument 0"}
!755 = distinct !{!755, !"XXH3_accumulate_512"}
!756 = !{!757}
!757 = distinct !{!757, !755, !"XXH3_accumulate_512: argument 1"}
!758 = !{!759}
!759 = distinct !{!759, !755, !"XXH3_accumulate_512: argument 2"}
!760 = !{!757, !748}
!761 = !{!754, !759, !751}
!762 = !{!759, !751}
!763 = !{!754, !757, !748}
!764 = !{!757, !759, !748, !751}
!765 = !{!766}
!766 = distinct !{!766, !767, !"XXH3_scrambleAcc: argument 0"}
!767 = distinct !{!767, !"XXH3_scrambleAcc"}
!768 = !{!769}
!769 = distinct !{!769, !767, !"XXH3_scrambleAcc: argument 1"}
!770 = !{!769, !748, !751}
!771 = !{!769, !751}
!772 = !{!766, !748}
!773 = !{!774}
!774 = distinct !{!774, !775, !"XXH3_accumulate_512: argument 0"}
!775 = distinct !{!775, !"XXH3_accumulate_512"}
!776 = !{!777}
!777 = distinct !{!777, !775, !"XXH3_accumulate_512: argument 1"}
!778 = !{!779}
!779 = distinct !{!779, !775, !"XXH3_accumulate_512: argument 2"}
!780 = !{!777, !748}
!781 = !{!774, !779, !751}
!782 = !{!779, !751}
!783 = !{!774, !777, !748}
!784 = !{!777, !779, !748, !751}
!785 = !{!786}
!786 = distinct !{!786, !787, !"XXH3_accumulate_512: argument 0"}
!787 = distinct !{!787, !"XXH3_accumulate_512"}
!788 = !{!789}
!789 = distinct !{!789, !787, !"XXH3_accumulate_512: argument 1"}
!790 = !{!791}
!791 = distinct !{!791, !787, !"XXH3_accumulate_512: argument 2"}
!792 = !{!789, !748}
!793 = !{!786, !791, !751}
!794 = !{!791, !751}
!795 = !{!786, !789, !748}
!796 = !{!789, !791, !748, !751}
!797 = !{!798}
!798 = distinct !{!798, !799, !"XXH3_mergeAccs: argument 0"}
!799 = distinct !{!799, !"XXH3_mergeAccs"}
!800 = !{!801}
!801 = distinct !{!801, !799, !"XXH3_mergeAccs: argument 1"}
!802 = !{!803}
!803 = distinct !{!803, !804, !"XXH3_mix2Accs: argument 0"}
!804 = distinct !{!804, !"XXH3_mix2Accs"}
!805 = !{!803, !798}
!806 = !{!807, !801, !748}
!807 = distinct !{!807, !804, !"XXH3_mix2Accs: argument 1"}
!808 = !{!803, !798, !748}
!809 = !{!810}
!810 = distinct !{!810, !811, !"XXH3_mix2Accs: argument 0"}
!811 = distinct !{!811, !"XXH3_mix2Accs"}
!812 = !{!810, !798}
!813 = !{!814, !801, !748}
!814 = distinct !{!814, !811, !"XXH3_mix2Accs: argument 1"}
!815 = !{!810, !798, !748}
!816 = !{!817}
!817 = distinct !{!817, !818, !"XXH3_mix2Accs: argument 0"}
!818 = distinct !{!818, !"XXH3_mix2Accs"}
!819 = !{!817, !798}
!820 = !{!821, !801, !748}
!821 = distinct !{!821, !818, !"XXH3_mix2Accs: argument 1"}
!822 = !{!817, !798, !748}
!823 = !{!824}
!824 = distinct !{!824, !825, !"XXH3_mix2Accs: argument 0"}
!825 = distinct !{!825, !"XXH3_mix2Accs"}
!826 = !{!824, !798}
!827 = !{!828, !801, !748}
!828 = distinct !{!828, !825, !"XXH3_mix2Accs: argument 1"}
!829 = !{!824, !798, !748}
!830 = !{!831}
!831 = distinct !{!831, !832, !"XXH3_mergeAccs: argument 1"}
!832 = distinct !{!832, !"XXH3_mergeAccs"}
!833 = !{!834, !836, !748}
!834 = distinct !{!834, !835, !"XXH3_mix2Accs: argument 0"}
!835 = distinct !{!835, !"XXH3_mix2Accs"}
!836 = distinct !{!836, !832, !"XXH3_mergeAccs: argument 0"}
!837 = !{!838, !836, !748}
!838 = distinct !{!838, !839, !"XXH3_mix2Accs: argument 0"}
!839 = distinct !{!839, !"XXH3_mix2Accs"}
!840 = !{!841, !836, !748}
!841 = distinct !{!841, !842, !"XXH3_mix2Accs: argument 0"}
!842 = distinct !{!842, !"XXH3_mix2Accs"}
!843 = !{!844, !836, !748}
!844 = distinct !{!844, !845, !"XXH3_mix2Accs: argument 0"}
!845 = distinct !{!845, !"XXH3_mix2Accs"}
!846 = !{!847}
!847 = distinct !{!847, !848, !"XXH3_accumulate_512: argument 0"}
!848 = distinct !{!848, !"XXH3_accumulate_512"}
!849 = !{!850}
!850 = distinct !{!850, !848, !"XXH3_accumulate_512: argument 1"}
!851 = !{!852}
!852 = distinct !{!852, !848, !"XXH3_accumulate_512: argument 2"}
!853 = !{!847, !852}
!854 = !{!847, !850}
!855 = !{!850, !852}
!856 = !{!857}
!857 = distinct !{!857, !858, !"XXH3_scrambleAcc: argument 0"}
!858 = distinct !{!858, !"XXH3_scrambleAcc"}
!859 = !{!860}
!860 = distinct !{!860, !858, !"XXH3_scrambleAcc: argument 1"}
!861 = !{!862}
!862 = distinct !{!862, !863, !"XXH3_accumulate_512: argument 0"}
!863 = distinct !{!863, !"XXH3_accumulate_512"}
!864 = !{!865}
!865 = distinct !{!865, !863, !"XXH3_accumulate_512: argument 1"}
!866 = !{!867}
!867 = distinct !{!867, !863, !"XXH3_accumulate_512: argument 2"}
!868 = !{!862, !867}
!869 = !{!862, !865}
!870 = !{!865, !867}
!871 = !{!872}
!872 = distinct !{!872, !873, !"XXH3_accumulate_512: argument 0"}
!873 = distinct !{!873, !"XXH3_accumulate_512"}
!874 = !{!875}
!875 = distinct !{!875, !873, !"XXH3_accumulate_512: argument 1"}
!876 = !{!877}
!877 = distinct !{!877, !873, !"XXH3_accumulate_512: argument 2"}
!878 = !{!872, !877}
!879 = !{!872, !875}
!880 = !{!875, !877}
!881 = !{!882}
!882 = distinct !{!882, !883, !"XXH3_accumulate_512: argument 0"}
!883 = distinct !{!883, !"XXH3_accumulate_512"}
!884 = !{!885}
!885 = distinct !{!885, !883, !"XXH3_accumulate_512: argument 1"}
!886 = !{!887}
!887 = distinct !{!887, !883, !"XXH3_accumulate_512: argument 2"}
!888 = !{!882, !887}
!889 = !{!882, !885}
!890 = !{!885, !887}
!891 = !{!892}
!892 = distinct !{!892, !893, !"XXH3_scrambleAcc: argument 0"}
!893 = distinct !{!893, !"XXH3_scrambleAcc"}
!894 = !{!895}
!895 = distinct !{!895, !893, !"XXH3_scrambleAcc: argument 1"}
!896 = !{!897}
!897 = distinct !{!897, !898, !"XXH3_accumulate_512: argument 0"}
!898 = distinct !{!898, !"XXH3_accumulate_512"}
!899 = !{!900}
!900 = distinct !{!900, !898, !"XXH3_accumulate_512: argument 1"}
!901 = !{!902}
!902 = distinct !{!902, !898, !"XXH3_accumulate_512: argument 2"}
!903 = !{!897, !902}
!904 = !{!897, !900}
!905 = !{!900, !902}
!906 = !{!907}
!907 = distinct !{!907, !908, !"XXH3_accumulate_512: argument 0"}
!908 = distinct !{!908, !"XXH3_accumulate_512"}
!909 = !{!910}
!910 = distinct !{!910, !908, !"XXH3_accumulate_512: argument 1"}
!911 = !{!912}
!912 = distinct !{!912, !908, !"XXH3_accumulate_512: argument 2"}
!913 = !{!907, !912}
!914 = !{!907, !910}
!915 = !{!910, !912}
!916 = !{!917}
!917 = distinct !{!917, !918, !"XXH3_accumulate_512: argument 0"}
!918 = distinct !{!918, !"XXH3_accumulate_512"}
!919 = !{!920}
!920 = distinct !{!920, !918, !"XXH3_accumulate_512: argument 1"}
!921 = !{!922}
!922 = distinct !{!922, !918, !"XXH3_accumulate_512: argument 2"}
!923 = !{!917, !922}
!924 = !{!917, !920}
!925 = !{!920, !922}
!926 = !{!927}
!927 = distinct !{!927, !928, !"XXH3_scrambleAcc: argument 0"}
!928 = distinct !{!928, !"XXH3_scrambleAcc"}
!929 = !{!930}
!930 = distinct !{!930, !928, !"XXH3_scrambleAcc: argument 1"}
!931 = !{!932}
!932 = distinct !{!932, !933, !"XXH3_accumulate_512: argument 0"}
!933 = distinct !{!933, !"XXH3_accumulate_512"}
!934 = !{!935}
!935 = distinct !{!935, !933, !"XXH3_accumulate_512: argument 1"}
!936 = !{!937}
!937 = distinct !{!937, !933, !"XXH3_accumulate_512: argument 2"}
!938 = !{!932, !937}
!939 = !{!932, !935}
!940 = !{!935, !937}
!941 = !{!942}
!942 = distinct !{!942, !943, !"XXH3_accumulate_512: argument 0"}
!943 = distinct !{!943, !"XXH3_accumulate_512"}
!944 = !{!945}
!945 = distinct !{!945, !943, !"XXH3_accumulate_512: argument 1"}
!946 = !{!947}
!947 = distinct !{!947, !943, !"XXH3_accumulate_512: argument 2"}
!948 = !{!942, !947}
!949 = !{!942, !945}
!950 = !{!945, !947}
!951 = !{!952}
!952 = distinct !{!952, !953, !"XXH3_accumulate_512: argument 0"}
!953 = distinct !{!953, !"XXH3_accumulate_512"}
!954 = !{!955}
!955 = distinct !{!955, !953, !"XXH3_accumulate_512: argument 1"}
!956 = !{!957}
!957 = distinct !{!957, !953, !"XXH3_accumulate_512: argument 2"}
!958 = !{!952, !957}
!959 = !{!952, !955}
!960 = !{!955, !957}
!961 = !{!962}
!962 = distinct !{!962, !963, !"XXH3_accumulate_512: argument 0"}
!963 = distinct !{!963, !"XXH3_accumulate_512"}
!964 = !{!965}
!965 = distinct !{!965, !963, !"XXH3_accumulate_512: argument 1"}
!966 = !{!967}
!967 = distinct !{!967, !963, !"XXH3_accumulate_512: argument 2"}
!968 = !{!962, !967}
!969 = !{!962, !965}
!970 = !{!965, !967}
!971 = !{!972}
!972 = distinct !{!972, !973, !"XXH3_mergeAccs: argument 0"}
!973 = distinct !{!973, !"XXH3_mergeAccs"}
!974 = !{!975}
!975 = distinct !{!975, !973, !"XXH3_mergeAccs: argument 1"}
!976 = !{!977}
!977 = distinct !{!977, !978, !"XXH3_mix2Accs: argument 0"}
!978 = distinct !{!978, !"XXH3_mix2Accs"}
!979 = !{!977, !972}
!980 = !{!981, !975}
!981 = distinct !{!981, !978, !"XXH3_mix2Accs: argument 1"}
!982 = !{!983}
!983 = distinct !{!983, !984, !"XXH3_mix2Accs: argument 0"}
!984 = distinct !{!984, !"XXH3_mix2Accs"}
!985 = !{!983, !972}
!986 = !{!987, !975}
!987 = distinct !{!987, !984, !"XXH3_mix2Accs: argument 1"}
!988 = !{!989}
!989 = distinct !{!989, !990, !"XXH3_mix2Accs: argument 0"}
!990 = distinct !{!990, !"XXH3_mix2Accs"}
!991 = !{!989, !972}
!992 = !{!993, !975}
!993 = distinct !{!993, !990, !"XXH3_mix2Accs: argument 1"}
!994 = !{!995}
!995 = distinct !{!995, !996, !"XXH3_mix2Accs: argument 0"}
!996 = distinct !{!996, !"XXH3_mix2Accs"}
!997 = !{!995, !972}
!998 = !{!999, !975}
!999 = distinct !{!999, !996, !"XXH3_mix2Accs: argument 1"}
!1000 = !{!1001}
!1001 = distinct !{!1001, !1002, !"XXH3_mergeAccs: argument 1"}
!1002 = distinct !{!1002, !"XXH3_mergeAccs"}
!1003 = !{!1004, !1006}
!1004 = distinct !{!1004, !1005, !"XXH3_mix2Accs: argument 0"}
!1005 = distinct !{!1005, !"XXH3_mix2Accs"}
!1006 = distinct !{!1006, !1002, !"XXH3_mergeAccs: argument 0"}
!1007 = !{!1008, !1006}
!1008 = distinct !{!1008, !1009, !"XXH3_mix2Accs: argument 0"}
!1009 = distinct !{!1009, !"XXH3_mix2Accs"}
!1010 = !{!1011, !1006}
!1011 = distinct !{!1011, !1012, !"XXH3_mix2Accs: argument 0"}
!1012 = distinct !{!1012, !"XXH3_mix2Accs"}
!1013 = !{!1014, !1006}
!1014 = distinct !{!1014, !1015, !"XXH3_mix2Accs: argument 0"}
!1015 = distinct !{!1015, !"XXH3_mix2Accs"}
