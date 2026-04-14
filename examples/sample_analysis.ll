; ModuleID = 'sample_analysis.c'
source_filename = "sample_analysis.c"
target datalayout = "e-m:o-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

@.str = private unnamed_addr constant [10 x i8] c"Data: %s\0A\00", align 1, !dbg !0
@.str.1 = private unnamed_addr constant [5 x i8] c"Test\00", align 1, !dbg !7
@.str.2 = private unnamed_addr constant [19 x i8] c"Usage: %s <input>\0A\00", align 1, !dbg !12
@.str.3 = private unnamed_addr constant [10 x i8] c"Name: %s\0A\00", align 1, !dbg !17

; Function Attrs: nofree nounwind ssp uwtable(sync)
define void @process_data(ptr noundef %0) local_unnamed_addr #0 !dbg !29 {
  %2 = alloca [64 x i8], align 1
    #dbg_value(ptr %0, !34, !DIExpression(), !39)
  call void @llvm.lifetime.start.p0(i64 64, ptr nonnull %2) #11, !dbg !40
    #dbg_declare(ptr %2, !35, !DIExpression(), !41)
  %3 = call ptr @__strcpy_chk(ptr noundef nonnull %2, ptr noundef %0, i64 noundef 64) #11, !dbg !42
  %4 = call i32 (ptr, ...) @printf(ptr noundef nonnull dereferenceable(1) @.str, ptr noundef nonnull %2), !dbg !43
  call void @llvm.lifetime.end.p0(i64 64, ptr nonnull %2) #11, !dbg !44
  ret void, !dbg !44
}

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #1

; Function Attrs: nofree nounwind
declare !dbg !45 ptr @__strcpy_chk(ptr noundef, ptr noundef, i64 noundef) local_unnamed_addr #2

; Function Attrs: nofree nounwind
declare !dbg !51 noundef i32 @printf(ptr nocapture noundef readonly, ...) local_unnamed_addr #2

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #1

; Function Attrs: mustprogress nofree nounwind ssp willreturn memory(inaccessiblemem: readwrite) uwtable(sync)
define noalias noundef ptr @allocate_array(i32 noundef %0) local_unnamed_addr #3 !dbg !57 {
    #dbg_value(i32 %0, !62, !DIExpression(), !64)
  %2 = sext i32 %0 to i64, !dbg !65
  %3 = shl nsw i64 %2, 2, !dbg !66
  %4 = tail call ptr @malloc(i64 noundef %3) #12, !dbg !67
    #dbg_value(ptr %4, !63, !DIExpression(), !64)
  ret ptr %4, !dbg !68
}

; Function Attrs: mustprogress nofree nounwind willreturn allockind("alloc,uninitialized") allocsize(0) memory(inaccessiblemem: readwrite)
declare !dbg !69 noalias noundef ptr @malloc(i64 noundef) local_unnamed_addr #4

; Function Attrs: mustprogress nounwind ssp willreturn memory(readwrite, argmem: none) uwtable(sync)
define noalias noundef ptr @get_name() local_unnamed_addr #5 !dbg !78 {
  %1 = tail call dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #12, !dbg !83
    #dbg_value(ptr %1, !82, !DIExpression(), !84)
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(5) %1, ptr noundef nonnull align 1 dereferenceable(5) @.str.1, i64 5, i1 false), !dbg !85
  tail call void @free(ptr noundef %1), !dbg !86
  ret ptr %1, !dbg !87
}

; Function Attrs: mustprogress nounwind willreturn allockind("free") memory(argmem: readwrite, inaccessiblemem: readwrite)
declare !dbg !88 void @free(ptr allocptr nocapture noundef) local_unnamed_addr #6

; Function Attrs: mustprogress nofree norecurse nosync nounwind ssp willreturn memory(argmem: read) uwtable(sync)
define i32 @handle_null(ptr nocapture noundef readonly %0) local_unnamed_addr #7 !dbg !91 {
    #dbg_value(ptr %0, !95, !DIExpression(), !96)
  %2 = load i32, ptr %0, align 4, !dbg !97, !tbaa !98
  ret i32 %2, !dbg !102
}

; Function Attrs: mustprogress nounwind ssp willreturn memory(argmem: readwrite, inaccessiblemem: readwrite) uwtable(sync)
define void @free_twice(ptr nocapture noundef %0) local_unnamed_addr #8 !dbg !103 {
    #dbg_value(ptr %0, !105, !DIExpression(), !106)
  tail call void @free(ptr noundef %0), !dbg !107
  tail call void @free(ptr noundef %0), !dbg !108
  ret void, !dbg !109
}

; Function Attrs: nounwind ssp uwtable(sync)
define range(i32 0, 2) i32 @main(i32 noundef %0, ptr nocapture noundef readonly %1) local_unnamed_addr #9 !dbg !110 {
  %3 = alloca [64 x i8], align 1
    #dbg_value(i32 %0, !115, !DIExpression(), !121)
    #dbg_value(ptr %1, !116, !DIExpression(), !121)
  %4 = icmp slt i32 %0, 2, !dbg !122
  br i1 %4, label %5, label %8, !dbg !124

5:                                                ; preds = %2
  %6 = load ptr, ptr %1, align 8, !dbg !125, !tbaa !127
  %7 = tail call i32 (ptr, ...) @printf(ptr noundef nonnull dereferenceable(1) @.str.2, ptr noundef %6), !dbg !129
  br label %15, !dbg !130

8:                                                ; preds = %2
  %9 = getelementptr inbounds i8, ptr %1, i64 8, !dbg !131
  %10 = load ptr, ptr %9, align 8, !dbg !131, !tbaa !127
    #dbg_value(ptr %10, !34, !DIExpression(), !132)
  call void @llvm.lifetime.start.p0(i64 64, ptr nonnull %3) #11, !dbg !134
    #dbg_declare(ptr %3, !35, !DIExpression(), !135)
  %11 = call ptr @__strcpy_chk(ptr noundef nonnull %3, ptr noundef %10, i64 noundef 64) #11, !dbg !136
  %12 = call i32 (ptr, ...) @printf(ptr noundef nonnull dereferenceable(1) @.str, ptr noundef nonnull %3), !dbg !137
  call void @llvm.lifetime.end.p0(i64 64, ptr nonnull %3) #11, !dbg !138
    #dbg_value(ptr poison, !117, !DIExpression(), !121)
    #dbg_value(i32 0, !118, !DIExpression(), !139)
    #dbg_value(i32 poison, !118, !DIExpression(), !139)
  %13 = call noalias noundef dereferenceable_or_null(32) ptr @malloc(i64 noundef 32) #12, !dbg !140
    #dbg_value(ptr %13, !82, !DIExpression(), !142)
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(5) %13, ptr noundef nonnull align 1 dereferenceable(5) @.str.1, i64 5, i1 false), !dbg !143
  call void @free(ptr noundef %13), !dbg !144
    #dbg_value(ptr %13, !120, !DIExpression(), !121)
  %14 = call i32 (ptr, ...) @printf(ptr noundef nonnull dereferenceable(1) @.str.3, ptr noundef %13), !dbg !145
  br label %15

15:                                               ; preds = %8, %5
  %16 = phi i32 [ 1, %5 ], [ 0, %8 ], !dbg !121
  ret i32 %16, !dbg !146
}

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias nocapture writeonly, ptr noalias nocapture readonly, i64, i1 immarg) #10

attributes #0 = { nofree nounwind ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a,+zcm,+zcz" }
attributes #1 = { mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #2 = { nofree nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a,+zcm,+zcz" }
attributes #3 = { mustprogress nofree nounwind ssp willreturn memory(inaccessiblemem: readwrite) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a,+zcm,+zcz" }
attributes #4 = { mustprogress nofree nounwind willreturn allockind("alloc,uninitialized") allocsize(0) memory(inaccessiblemem: readwrite) "alloc-family"="malloc" "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a,+zcm,+zcz" }
attributes #5 = { mustprogress nounwind ssp willreturn memory(readwrite, argmem: none) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a,+zcm,+zcz" }
attributes #6 = { mustprogress nounwind willreturn allockind("free") memory(argmem: readwrite, inaccessiblemem: readwrite) "alloc-family"="malloc" "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a,+zcm,+zcz" }
attributes #7 = { mustprogress nofree norecurse nosync nounwind ssp willreturn memory(argmem: read) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a,+zcm,+zcz" }
attributes #8 = { mustprogress nounwind ssp willreturn memory(argmem: readwrite, inaccessiblemem: readwrite) uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a,+zcm,+zcz" }
attributes #9 = { nounwind ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a,+zcm,+zcz" }
attributes #10 = { nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #11 = { nounwind }
attributes #12 = { allocsize(0) }

!llvm.module.flags = !{!19, !20, !21, !22, !23, !24, !25}
!llvm.dbg.cu = !{!26}
!llvm.ident = !{!28}

!0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
!1 = distinct !DIGlobalVariable(scope: null, file: !2, line: 10, type: !3, isLocal: true, isDefinition: true)
!2 = !DIFile(filename: "sample_analysis.c", directory: "/Users/scc/code/zigcode/OmniSope/examples", checksumkind: CSK_MD5, checksum: "7145ff456e4e3728f671261bbf0c1669")
!3 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 80, elements: !5)
!4 = !DIBasicType(name: "char", size: 8, encoding: DW_ATE_signed_char)
!5 = !{!6}
!6 = !DISubrange(count: 10)
!7 = !DIGlobalVariableExpression(var: !8, expr: !DIExpression())
!8 = distinct !DIGlobalVariable(scope: null, file: !2, line: 23, type: !9, isLocal: true, isDefinition: true)
!9 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 40, elements: !10)
!10 = !{!11}
!11 = !DISubrange(count: 5)
!12 = !DIGlobalVariableExpression(var: !13, expr: !DIExpression())
!13 = distinct !DIGlobalVariable(scope: null, file: !2, line: 41, type: !14, isLocal: true, isDefinition: true)
!14 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 152, elements: !15)
!15 = !{!16}
!16 = !DISubrange(count: 19)
!17 = !DIGlobalVariableExpression(var: !18, expr: !DIExpression())
!18 = distinct !DIGlobalVariable(scope: null, file: !2, line: 54, type: !3, isLocal: true, isDefinition: true)
!19 = !{i32 2, !"SDK Version", [2 x i32] [i32 26, i32 2]}
!20 = !{i32 7, !"Dwarf Version", i32 5}
!21 = !{i32 2, !"Debug Info Version", i32 3}
!22 = !{i32 1, !"wchar_size", i32 4}
!23 = !{i32 8, !"PIC Level", i32 2}
!24 = !{i32 7, !"uwtable", i32 1}
!25 = !{i32 7, !"frame-pointer", i32 1}
!26 = distinct !DICompileUnit(language: DW_LANG_C11, file: !2, producer: "Apple clang version 17.0.0 (clang-1700.6.4.2)", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug, globals: !27, splitDebugInlining: false, nameTableKind: Apple, sysroot: "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk", sdk: "MacOSX.sdk")
!27 = !{!0, !7, !12, !17}
!28 = !{!"Apple clang version 17.0.0 (clang-1700.6.4.2)"}
!29 = distinct !DISubprogram(name: "process_data", scope: !2, file: !2, line: 7, type: !30, scopeLine: 7, flags: DIFlagPrototyped | DIFlagAllCallsDescribed, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !26, retainedNodes: !33)
!30 = !DISubroutineType(types: !31)
!31 = !{null, !32}
!32 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !4, size: 64)
!33 = !{!34, !35}
!34 = !DILocalVariable(name: "input", arg: 1, scope: !29, file: !2, line: 7, type: !32)
!35 = !DILocalVariable(name: "buffer", scope: !29, file: !2, line: 8, type: !36)
!36 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 512, elements: !37)
!37 = !{!38}
!38 = !DISubrange(count: 64)
!39 = !DILocation(line: 0, scope: !29)
!40 = !DILocation(line: 8, column: 5, scope: !29)
!41 = !DILocation(line: 8, column: 10, scope: !29)
!42 = !DILocation(line: 9, column: 5, scope: !29)
!43 = !DILocation(line: 10, column: 5, scope: !29)
!44 = !DILocation(line: 11, column: 1, scope: !29)
!45 = !DISubprogram(name: "__builtin___strcpy_chk", scope: !2, file: !2, line: 9, type: !46, flags: DIFlagArtificial | DIFlagPrototyped, spFlags: DISPFlagOptimized)
!46 = !DISubroutineType(types: !47)
!47 = !{!32, !32, !48, !50}
!48 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !49, size: 64)
!49 = !DIDerivedType(tag: DW_TAG_const_type, baseType: !4)
!50 = !DIBasicType(name: "unsigned long", size: 64, encoding: DW_ATE_unsigned)
!51 = !DISubprogram(name: "printf", scope: !52, file: !52, line: 34, type: !53, flags: DIFlagPrototyped, spFlags: DISPFlagOptimized)
!52 = !DIFile(filename: "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/_printf.h", directory: "", checksumkind: CSK_MD5, checksum: "2d37517bd0342aa326aa1d3660ad4ab4")
!53 = !DISubroutineType(types: !54)
!54 = !{!55, !56, null}
!55 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!56 = !DIDerivedType(tag: DW_TAG_restrict_type, baseType: !48)
!57 = distinct !DISubprogram(name: "allocate_array", scope: !2, file: !2, line: 14, type: !58, scopeLine: 14, flags: DIFlagPrototyped | DIFlagAllCallsDescribed, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !26, retainedNodes: !61)
!58 = !DISubroutineType(types: !59)
!59 = !{!60, !55}
!60 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !55, size: 64)
!61 = !{!62, !63}
!62 = !DILocalVariable(name: "size", arg: 1, scope: !57, file: !2, line: 14, type: !55)
!63 = !DILocalVariable(name: "arr", scope: !57, file: !2, line: 15, type: !60)
!64 = !DILocation(line: 0, scope: !57)
!65 = !DILocation(line: 15, column: 23, scope: !57)
!66 = !DILocation(line: 15, column: 28, scope: !57)
!67 = !DILocation(line: 15, column: 16, scope: !57)
!68 = !DILocation(line: 17, column: 5, scope: !57)
!69 = !DISubprogram(name: "malloc", scope: !70, file: !70, line: 54, type: !71, flags: DIFlagPrototyped, spFlags: DISPFlagOptimized)
!70 = !DIFile(filename: "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/malloc/_malloc.h", directory: "", checksumkind: CSK_MD5, checksum: "1ff1e04bc418b1c4bb5edfe9e395b8c0")
!71 = !DISubroutineType(types: !72)
!72 = !{!73, !74}
!73 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!74 = !DIDerivedType(tag: DW_TAG_typedef, name: "size_t", file: !75, line: 50, baseType: !76)
!75 = !DIFile(filename: "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/sys/_types/_size_t.h", directory: "", checksumkind: CSK_MD5, checksum: "f7981334d28e0c246f35cd24042aa2a4")
!76 = !DIDerivedType(tag: DW_TAG_typedef, name: "__darwin_size_t", file: !77, line: 87, baseType: !50)
!77 = !DIFile(filename: "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/arm/_types.h", directory: "", checksumkind: CSK_MD5, checksum: "b270144f57ae258d0ce80b8f87be068c")
!78 = distinct !DISubprogram(name: "get_name", scope: !2, file: !2, line: 21, type: !79, scopeLine: 21, flags: DIFlagAllCallsDescribed, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !26, retainedNodes: !81)
!79 = !DISubroutineType(types: !80)
!80 = !{!32}
!81 = !{!82}
!82 = !DILocalVariable(name: "name", scope: !78, file: !2, line: 22, type: !32)
!83 = !DILocation(line: 22, column: 18, scope: !78)
!84 = !DILocation(line: 0, scope: !78)
!85 = !DILocation(line: 23, column: 5, scope: !78)
!86 = !DILocation(line: 24, column: 5, scope: !78)
!87 = !DILocation(line: 25, column: 5, scope: !78)
!88 = !DISubprogram(name: "free", scope: !70, file: !70, line: 56, type: !89, flags: DIFlagPrototyped, spFlags: DISPFlagOptimized)
!89 = !DISubroutineType(types: !90)
!90 = !{null, !73}
!91 = distinct !DISubprogram(name: "handle_null", scope: !2, file: !2, line: 29, type: !92, scopeLine: 29, flags: DIFlagPrototyped | DIFlagAllCallsDescribed, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !26, retainedNodes: !94)
!92 = !DISubroutineType(types: !93)
!93 = !{!55, !60}
!94 = !{!95}
!95 = !DILocalVariable(name: "ptr", arg: 1, scope: !91, file: !2, line: 29, type: !60)
!96 = !DILocation(line: 0, scope: !91)
!97 = !DILocation(line: 30, column: 12, scope: !91)
!98 = !{!99, !99, i64 0}
!99 = !{!"int", !100, i64 0}
!100 = !{!"omnipotent char", !101, i64 0}
!101 = !{!"Simple C/C++ TBAA"}
!102 = !DILocation(line: 30, column: 5, scope: !91)
!103 = distinct !DISubprogram(name: "free_twice", scope: !2, file: !2, line: 34, type: !30, scopeLine: 34, flags: DIFlagPrototyped | DIFlagAllCallsDescribed, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !26, retainedNodes: !104)
!104 = !{!105}
!105 = !DILocalVariable(name: "data", arg: 1, scope: !103, file: !2, line: 34, type: !32)
!106 = !DILocation(line: 0, scope: !103)
!107 = !DILocation(line: 35, column: 5, scope: !103)
!108 = !DILocation(line: 36, column: 5, scope: !103)
!109 = !DILocation(line: 37, column: 1, scope: !103)
!110 = distinct !DISubprogram(name: "main", scope: !2, file: !2, line: 39, type: !111, scopeLine: 39, flags: DIFlagPrototyped | DIFlagAllCallsDescribed, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !26, retainedNodes: !114)
!111 = !DISubroutineType(types: !112)
!112 = !{!55, !55, !113}
!113 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !32, size: 64)
!114 = !{!115, !116, !117, !118, !120}
!115 = !DILocalVariable(name: "argc", arg: 1, scope: !110, file: !2, line: 39, type: !55)
!116 = !DILocalVariable(name: "argv", arg: 2, scope: !110, file: !2, line: 39, type: !113)
!117 = !DILocalVariable(name: "arr", scope: !110, file: !2, line: 47, type: !60)
!118 = !DILocalVariable(name: "i", scope: !119, file: !2, line: 48, type: !55)
!119 = distinct !DILexicalBlock(scope: !110, file: !2, line: 48, column: 5)
!120 = !DILocalVariable(name: "name", scope: !110, file: !2, line: 53, type: !32)
!121 = !DILocation(line: 0, scope: !110)
!122 = !DILocation(line: 40, column: 14, scope: !123)
!123 = distinct !DILexicalBlock(scope: !110, file: !2, line: 40, column: 9)
!124 = !DILocation(line: 40, column: 9, scope: !110)
!125 = !DILocation(line: 41, column: 39, scope: !126)
!126 = distinct !DILexicalBlock(scope: !123, file: !2, line: 40, column: 19)
!127 = !{!128, !128, i64 0}
!128 = !{!"any pointer", !100, i64 0}
!129 = !DILocation(line: 41, column: 9, scope: !126)
!130 = !DILocation(line: 42, column: 9, scope: !126)
!131 = !DILocation(line: 45, column: 18, scope: !110)
!132 = !DILocation(line: 0, scope: !29, inlinedAt: !133)
!133 = distinct !DILocation(line: 45, column: 5, scope: !110)
!134 = !DILocation(line: 8, column: 5, scope: !29, inlinedAt: !133)
!135 = !DILocation(line: 8, column: 10, scope: !29, inlinedAt: !133)
!136 = !DILocation(line: 9, column: 5, scope: !29, inlinedAt: !133)
!137 = !DILocation(line: 10, column: 5, scope: !29, inlinedAt: !133)
!138 = !DILocation(line: 11, column: 1, scope: !29, inlinedAt: !133)
!139 = !DILocation(line: 0, scope: !119)
!140 = !DILocation(line: 22, column: 18, scope: !78, inlinedAt: !141)
!141 = distinct !DILocation(line: 53, column: 18, scope: !110)
!142 = !DILocation(line: 0, scope: !78, inlinedAt: !141)
!143 = !DILocation(line: 23, column: 5, scope: !78, inlinedAt: !141)
!144 = !DILocation(line: 24, column: 5, scope: !78, inlinedAt: !141)
!145 = !DILocation(line: 54, column: 5, scope: !110)
!146 = !DILocation(line: 59, column: 1, scope: !110)
