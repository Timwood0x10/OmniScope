; ModuleID = 'corpus/red_team_test/csharp_ffi_bugs.c'
source_filename = "corpus/red_team_test/csharp_ffi_bugs.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

@.str = private unnamed_addr constant [9 x i8] c"FFI data\00", align 1, !dbg !0
@.str.1 = private unnamed_addr constant [15 x i8] c"sensitive data\00", align 1, !dbg !7
@.str.2 = private unnamed_addr constant [10 x i8] c"test data\00", align 1, !dbg !12

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @cs_01_csharp_alloc_c_free() #0 !dbg !28 {
entry:
  %ptr = alloca ptr, align 8
    #dbg_declare(ptr %ptr, !32, !DIExpression(), !34)
  %call = call ptr @Marshal_AllocHGlobal(i32 noundef 256), !dbg !35
  store ptr %call, ptr %ptr, align 8, !dbg !34
  %0 = load ptr, ptr %ptr, align 8, !dbg !36
  %tobool = icmp ne ptr %0, null, !dbg !36
  br i1 %tobool, label %if.end, label %if.then, !dbg !38

if.then:                                          ; preds = %entry
  br label %return, !dbg !39

if.end:                                           ; preds = %entry
  %1 = load ptr, ptr %ptr, align 8, !dbg !40
  %2 = load ptr, ptr %ptr, align 8, !dbg !40
  %3 = call i64 @llvm.objectsize.i64.p0(ptr %2, i1 false, i1 true, i1 false), !dbg !40
  %call1 = call ptr @__memset_chk(ptr noundef %1, i32 noundef 171, i64 noundef 256, i64 noundef %3) #5, !dbg !40
  %4 = load ptr, ptr %ptr, align 8, !dbg !41
  call void @free(ptr noundef %4), !dbg !42
  br label %return, !dbg !43

return:                                           ; preds = %if.end, %if.then
  ret void, !dbg !43
}

declare ptr @Marshal_AllocHGlobal(i32 noundef) #1

; Function Attrs: nounwind
declare ptr @__memset_chk(ptr noundef, i32 noundef, i64 noundef, i64 noundef) #2

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.objectsize.i64.p0(ptr, i1 immarg, i1 immarg, i1 immarg) #3

declare void @free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @cs_02_c_alloc_csharp_free() #0 !dbg !44 {
entry:
  %ptr = alloca ptr, align 8
    #dbg_declare(ptr %ptr, !45, !DIExpression(), !46)
  %call = call ptr @malloc(i64 noundef 1024) #6, !dbg !47
  store ptr %call, ptr %ptr, align 8, !dbg !46
  %0 = load ptr, ptr %ptr, align 8, !dbg !48
  %tobool = icmp ne ptr %0, null, !dbg !48
  br i1 %tobool, label %if.end, label %if.then, !dbg !50

if.then:                                          ; preds = %entry
  br label %return, !dbg !51

if.end:                                           ; preds = %entry
  %1 = load ptr, ptr %ptr, align 8, !dbg !52
  %2 = load ptr, ptr %ptr, align 8, !dbg !52
  %3 = call i64 @llvm.objectsize.i64.p0(ptr %2, i1 false, i1 true, i1 false), !dbg !52
  %call1 = call ptr @__memcpy_chk(ptr noundef %1, ptr noundef @.str, i64 noundef 8, i64 noundef %3) #5, !dbg !52
  %4 = load ptr, ptr %ptr, align 8, !dbg !53
  call void @Marshal_FreeHGlobal(ptr noundef %4), !dbg !54
  br label %return, !dbg !55

return:                                           ; preds = %if.end, %if.then
  ret void, !dbg !55
}

; Function Attrs: allocsize(0)
declare ptr @malloc(i64 noundef) #4

; Function Attrs: nounwind
declare ptr @__memcpy_chk(ptr noundef, ptr noundef, i64 noundef, i64 noundef) #2

declare void @Marshal_FreeHGlobal(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @cs_03_com_alloc_leak() #0 !dbg !56 {
entry:
  %com_data = alloca ptr, align 8
    #dbg_declare(ptr %com_data, !57, !DIExpression(), !58)
  %call = call ptr @CoTaskMemAlloc(i64 noundef 512), !dbg !59
  store ptr %call, ptr %com_data, align 8, !dbg !58
  %0 = load ptr, ptr %com_data, align 8, !dbg !60
  %tobool = icmp ne ptr %0, null, !dbg !60
  br i1 %tobool, label %if.end, label %if.then, !dbg !62

if.then:                                          ; preds = %entry
  br label %return, !dbg !63

if.end:                                           ; preds = %entry
  %1 = load ptr, ptr %com_data, align 8, !dbg !64
  %2 = load ptr, ptr %com_data, align 8, !dbg !64
  %3 = call i64 @llvm.objectsize.i64.p0(ptr %2, i1 false, i1 true, i1 false), !dbg !64
  %call1 = call ptr @__memset_chk(ptr noundef %1, i32 noundef 0, i64 noundef 512, i64 noundef %3) #5, !dbg !64
  br label %return, !dbg !65

return:                                           ; preds = %if.end, %if.then
  ret void, !dbg !65
}

declare ptr @CoTaskMemAlloc(i64 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @cs_04_double_free_global() #0 !dbg !66 {
entry:
  %buf = alloca ptr, align 8
    #dbg_declare(ptr %buf, !67, !DIExpression(), !68)
  %call = call ptr @Marshal_AllocHGlobal(i32 noundef 64), !dbg !69
  store ptr %call, ptr %buf, align 8, !dbg !68
  %0 = load ptr, ptr %buf, align 8, !dbg !70
  %tobool = icmp ne ptr %0, null, !dbg !70
  br i1 %tobool, label %if.end, label %if.then, !dbg !72

if.then:                                          ; preds = %entry
  br label %return, !dbg !73

if.end:                                           ; preds = %entry
  %1 = load ptr, ptr %buf, align 8, !dbg !74
  %2 = load ptr, ptr %buf, align 8, !dbg !74
  %3 = call i64 @llvm.objectsize.i64.p0(ptr %2, i1 false, i1 true, i1 false), !dbg !74
  %call1 = call ptr @__strcpy_chk(ptr noundef %1, ptr noundef @.str.1, i64 noundef %3) #5, !dbg !74
  %4 = load ptr, ptr %buf, align 8, !dbg !75
  call void @Marshal_FreeHGlobal(ptr noundef %4), !dbg !76
  %5 = load ptr, ptr %buf, align 8, !dbg !77
  call void @Marshal_FreeHGlobal(ptr noundef %5), !dbg !78
  br label %return, !dbg !79

return:                                           ; preds = %if.end, %if.then
  ret void, !dbg !79
}

; Function Attrs: nounwind
declare ptr @__strcpy_chk(ptr noundef, ptr noundef, i64 noundef) #2

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @cs_05_com_alloc_c_free() #0 !dbg !80 {
entry:
  %com_ptr = alloca ptr, align 8
    #dbg_declare(ptr %com_ptr, !81, !DIExpression(), !82)
  %call = call ptr @CoTaskMemAlloc(i64 noundef 2048), !dbg !83
  store ptr %call, ptr %com_ptr, align 8, !dbg !82
  %0 = load ptr, ptr %com_ptr, align 8, !dbg !84
  %tobool = icmp ne ptr %0, null, !dbg !84
  br i1 %tobool, label %if.end, label %if.then, !dbg !86

if.then:                                          ; preds = %entry
  br label %return, !dbg !87

if.end:                                           ; preds = %entry
  %1 = load ptr, ptr %com_ptr, align 8, !dbg !88
  %2 = load ptr, ptr %com_ptr, align 8, !dbg !88
  %3 = call i64 @llvm.objectsize.i64.p0(ptr %2, i1 false, i1 true, i1 false), !dbg !88
  %call1 = call ptr @__memset_chk(ptr noundef %1, i32 noundef 255, i64 noundef 2048, i64 noundef %3) #5, !dbg !88
  %4 = load ptr, ptr %com_ptr, align 8, !dbg !89
  call void @free(ptr noundef %4), !dbg !90
  br label %return, !dbg !91

return:                                           ; preds = %if.end, %if.then
  ret void, !dbg !91
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @cs_06_runtime_alloc_c_free() #0 !dbg !92 {
entry:
  %obj = alloca ptr, align 8
    #dbg_declare(ptr %obj, !93, !DIExpression(), !94)
  %call = call ptr @RhpNewFast(i32 noundef 128), !dbg !95
  store ptr %call, ptr %obj, align 8, !dbg !94
  %0 = load ptr, ptr %obj, align 8, !dbg !96
  %tobool = icmp ne ptr %0, null, !dbg !96
  br i1 %tobool, label %if.end, label %if.then, !dbg !98

if.then:                                          ; preds = %entry
  br label %return, !dbg !99

if.end:                                           ; preds = %entry
  %1 = load ptr, ptr %obj, align 8, !dbg !100
  %2 = load ptr, ptr %obj, align 8, !dbg !100
  %3 = call i64 @llvm.objectsize.i64.p0(ptr %2, i1 false, i1 true, i1 false), !dbg !100
  %call1 = call ptr @__memset_chk(ptr noundef %1, i32 noundef 66, i64 noundef 128, i64 noundef %3) #5, !dbg !100
  %4 = load ptr, ptr %obj, align 8, !dbg !101
  call void @free(ptr noundef %4), !dbg !102
  br label %return, !dbg !103

return:                                           ; preds = %if.end, %if.then
  ret void, !dbg !103
}

declare ptr @RhpNewFast(i32 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @cs_safe_correct_pair() #0 !dbg !104 {
entry:
  %buf = alloca ptr, align 8
    #dbg_declare(ptr %buf, !105, !DIExpression(), !106)
  %call = call ptr @Marshal_AllocHGlobal(i32 noundef 320), !dbg !107
  store ptr %call, ptr %buf, align 8, !dbg !106
  %0 = load ptr, ptr %buf, align 8, !dbg !108
  %tobool = icmp ne ptr %0, null, !dbg !108
  br i1 %tobool, label %if.end, label %if.then, !dbg !110

if.then:                                          ; preds = %entry
  br label %return, !dbg !111

if.end:                                           ; preds = %entry
  %1 = load ptr, ptr %buf, align 8, !dbg !112
  %2 = load ptr, ptr %buf, align 8, !dbg !112
  %3 = call i64 @llvm.objectsize.i64.p0(ptr %2, i1 false, i1 true, i1 false), !dbg !112
  %call1 = call ptr @__memcpy_chk(ptr noundef %1, ptr noundef @.str.2, i64 noundef 9, i64 noundef %3) #5, !dbg !112
  %4 = load ptr, ptr %buf, align 8, !dbg !113
  call void @Marshal_FreeHGlobal(ptr noundef %4), !dbg !114
  br label %return, !dbg !115

return:                                           ; preds = %if.end, %if.then
  ret void, !dbg !115
}

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #4 = { allocsize(0) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #5 = { nounwind }
attributes #6 = { allocsize(0) }

!llvm.dbg.cu = !{!17}
!llvm.module.flags = !{!21, !22, !23, !24, !25, !26}
!llvm.ident = !{!27}

!0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
!1 = distinct !DIGlobalVariable(scope: null, file: !2, line: 62, type: !3, isLocal: true, isDefinition: true)
!2 = !DIFile(filename: "corpus/red_team_test/csharp_ffi_bugs.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "d295d139fafc212fb5924954cf16c27c")
!3 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 72, elements: !5)
!4 = !DIBasicType(name: "char", size: 8, encoding: DW_ATE_signed_char)
!5 = !{!6}
!6 = !DISubrange(count: 9)
!7 = !DIGlobalVariableExpression(var: !8, expr: !DIExpression())
!8 = distinct !DIGlobalVariable(scope: null, file: !2, line: 96, type: !9, isLocal: true, isDefinition: true)
!9 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 120, elements: !10)
!10 = !{!11}
!11 = !DISubrange(count: 15)
!12 = !DIGlobalVariableExpression(var: !13, expr: !DIExpression())
!13 = distinct !DIGlobalVariable(scope: null, file: !2, line: 149, type: !14, isLocal: true, isDefinition: true)
!14 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 80, elements: !15)
!15 = !{!16}
!16 = !DISubrange(count: 10)
!17 = distinct !DICompileUnit(language: DW_LANG_C11, file: !2, producer: "Homebrew clang version 21.1.8", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, retainedTypes: !18, globals: !20, splitDebugInlining: false, nameTableKind: Apple, sysroot: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk", sdk: "MacOSX15.sdk")
!18 = !{!19}
!19 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !4, size: 64)
!20 = !{!0, !7, !12}
!21 = !{i32 7, !"Dwarf Version", i32 5}
!22 = !{i32 2, !"Debug Info Version", i32 3}
!23 = !{i32 1, !"wchar_size", i32 4}
!24 = !{i32 8, !"PIC Level", i32 2}
!25 = !{i32 7, !"uwtable", i32 1}
!26 = !{i32 7, !"frame-pointer", i32 1}
!27 = !{!"Homebrew clang version 21.1.8"}
!28 = distinct !DISubprogram(name: "cs_01_csharp_alloc_c_free", scope: !2, file: !2, line: 40, type: !29, scopeLine: 40, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !17, retainedNodes: !31)
!29 = !DISubroutineType(types: !30)
!30 = !{null}
!31 = !{}
!32 = !DILocalVariable(name: "ptr", scope: !28, file: !2, line: 41, type: !33)
!33 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!34 = !DILocation(line: 41, column: 11, scope: !28)
!35 = !DILocation(line: 41, column: 17, scope: !28)
!36 = !DILocation(line: 42, column: 10, scope: !37)
!37 = distinct !DILexicalBlock(scope: !28, file: !2, line: 42, column: 9)
!38 = !DILocation(line: 42, column: 9, scope: !37)
!39 = !DILocation(line: 42, column: 15, scope: !37)
!40 = !DILocation(line: 45, column: 5, scope: !28)
!41 = !DILocation(line: 48, column: 10, scope: !28)
!42 = !DILocation(line: 48, column: 5, scope: !28)
!43 = !DILocation(line: 49, column: 1, scope: !28)
!44 = distinct !DISubprogram(name: "cs_02_c_alloc_csharp_free", scope: !2, file: !2, line: 57, type: !29, scopeLine: 57, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !17, retainedNodes: !31)
!45 = !DILocalVariable(name: "ptr", scope: !44, file: !2, line: 58, type: !33)
!46 = !DILocation(line: 58, column: 11, scope: !44)
!47 = !DILocation(line: 58, column: 17, scope: !44)
!48 = !DILocation(line: 59, column: 10, scope: !49)
!49 = distinct !DILexicalBlock(scope: !44, file: !2, line: 59, column: 9)
!50 = !DILocation(line: 59, column: 9, scope: !49)
!51 = !DILocation(line: 59, column: 15, scope: !49)
!52 = !DILocation(line: 62, column: 5, scope: !44)
!53 = !DILocation(line: 65, column: 25, scope: !44)
!54 = !DILocation(line: 65, column: 5, scope: !44)
!55 = !DILocation(line: 66, column: 1, scope: !44)
!56 = distinct !DISubprogram(name: "cs_03_com_alloc_leak", scope: !2, file: !2, line: 74, type: !29, scopeLine: 74, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !17, retainedNodes: !31)
!57 = !DILocalVariable(name: "com_data", scope: !56, file: !2, line: 76, type: !33)
!58 = !DILocation(line: 76, column: 11, scope: !56)
!59 = !DILocation(line: 76, column: 22, scope: !56)
!60 = !DILocation(line: 77, column: 10, scope: !61)
!61 = distinct !DILexicalBlock(scope: !56, file: !2, line: 77, column: 9)
!62 = !DILocation(line: 77, column: 9, scope: !61)
!63 = !DILocation(line: 77, column: 20, scope: !61)
!64 = !DILocation(line: 80, column: 5, scope: !56)
!65 = !DILocation(line: 84, column: 1, scope: !56)
!66 = distinct !DISubprogram(name: "cs_04_double_free_global", scope: !2, file: !2, line: 92, type: !29, scopeLine: 92, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !17, retainedNodes: !31)
!67 = !DILocalVariable(name: "buf", scope: !66, file: !2, line: 93, type: !33)
!68 = !DILocation(line: 93, column: 11, scope: !66)
!69 = !DILocation(line: 93, column: 17, scope: !66)
!70 = !DILocation(line: 94, column: 10, scope: !71)
!71 = distinct !DILexicalBlock(scope: !66, file: !2, line: 94, column: 9)
!72 = !DILocation(line: 94, column: 9, scope: !71)
!73 = !DILocation(line: 94, column: 15, scope: !71)
!74 = !DILocation(line: 96, column: 5, scope: !66)
!75 = !DILocation(line: 99, column: 25, scope: !66)
!76 = !DILocation(line: 99, column: 5, scope: !66)
!77 = !DILocation(line: 102, column: 25, scope: !66)
!78 = !DILocation(line: 102, column: 5, scope: !66)
!79 = !DILocation(line: 103, column: 1, scope: !66)
!80 = distinct !DISubprogram(name: "cs_05_com_alloc_c_free", scope: !2, file: !2, line: 111, type: !29, scopeLine: 111, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !17, retainedNodes: !31)
!81 = !DILocalVariable(name: "com_ptr", scope: !80, file: !2, line: 112, type: !33)
!82 = !DILocation(line: 112, column: 11, scope: !80)
!83 = !DILocation(line: 112, column: 21, scope: !80)
!84 = !DILocation(line: 113, column: 10, scope: !85)
!85 = distinct !DILexicalBlock(scope: !80, file: !2, line: 113, column: 9)
!86 = !DILocation(line: 113, column: 9, scope: !85)
!87 = !DILocation(line: 113, column: 19, scope: !85)
!88 = !DILocation(line: 116, column: 5, scope: !80)
!89 = !DILocation(line: 119, column: 10, scope: !80)
!90 = !DILocation(line: 119, column: 5, scope: !80)
!91 = !DILocation(line: 120, column: 1, scope: !80)
!92 = distinct !DISubprogram(name: "cs_06_runtime_alloc_c_free", scope: !2, file: !2, line: 128, type: !29, scopeLine: 128, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !17, retainedNodes: !31)
!93 = !DILocalVariable(name: "obj", scope: !92, file: !2, line: 129, type: !33)
!94 = !DILocation(line: 129, column: 11, scope: !92)
!95 = !DILocation(line: 129, column: 17, scope: !92)
!96 = !DILocation(line: 130, column: 10, scope: !97)
!97 = distinct !DILexicalBlock(scope: !92, file: !2, line: 130, column: 9)
!98 = !DILocation(line: 130, column: 9, scope: !97)
!99 = !DILocation(line: 130, column: 15, scope: !97)
!100 = !DILocation(line: 133, column: 5, scope: !92)
!101 = !DILocation(line: 136, column: 10, scope: !92)
!102 = !DILocation(line: 136, column: 5, scope: !92)
!103 = !DILocation(line: 137, column: 1, scope: !92)
!104 = distinct !DISubprogram(name: "cs_safe_correct_pair", scope: !2, file: !2, line: 144, type: !29, scopeLine: 144, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !17, retainedNodes: !31)
!105 = !DILocalVariable(name: "buf", scope: !104, file: !2, line: 145, type: !33)
!106 = !DILocation(line: 145, column: 11, scope: !104)
!107 = !DILocation(line: 145, column: 17, scope: !104)
!108 = !DILocation(line: 146, column: 10, scope: !109)
!109 = distinct !DILexicalBlock(scope: !104, file: !2, line: 146, column: 9)
!110 = !DILocation(line: 146, column: 9, scope: !109)
!111 = !DILocation(line: 146, column: 15, scope: !109)
!112 = !DILocation(line: 149, column: 5, scope: !104)
!113 = !DILocation(line: 150, column: 25, scope: !104)
!114 = !DILocation(line: 150, column: 5, scope: !104)
!115 = !DILocation(line: 151, column: 1, scope: !104)
