; ModuleID = 'corpus/red_team_test/rust_ffi_bugs.c'
source_filename = "corpus/red_team_test/rust_ffi_bugs.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

@.str = private unnamed_addr constant [18 x i8] c"allocated in Rust\00", align 1, !dbg !0
@.str.1 = private unnamed_addr constant [15 x i8] c"allocated in C\00", align 1, !dbg !7
@g_stored_rust_ref = internal global ptr null, align 8, !dbg !12
@.str.2 = private unnamed_addr constant [14 x i8] c"string at %p\0A\00", align 1, !dbg !19
@.str.3 = private unnamed_addr constant [13 x i8] c"via original\00", align 1, !dbg !24
@.str.4 = private unnamed_addr constant [10 x i8] c"via alias\00", align 1, !dbg !29
@.str.5 = private unnamed_addr constant [6 x i8] c"small\00", align 1, !dbg !34
@.str.6 = private unnamed_addr constant [10 x i8] c" extended\00", align 1, !dbg !39

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @rust_01_alloc_c_free() #0 !dbg !48 {
entry:
  %ptr = alloca ptr, align 8
    #dbg_declare(ptr %ptr, !52, !DIExpression(), !53)
  %call = call ptr @_RZN4alloc5alloc17h_allocate(i64 noundef 128), !dbg !54
  store ptr %call, ptr %ptr, align 8, !dbg !53
  %0 = load ptr, ptr %ptr, align 8, !dbg !55
  %1 = load ptr, ptr %ptr, align 8, !dbg !55
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !55
  %call1 = call ptr @__strcpy_chk(ptr noundef %0, ptr noundef @.str, i64 noundef %2) #6, !dbg !55
  %3 = load ptr, ptr %ptr, align 8, !dbg !56
  call void @free(ptr noundef %3), !dbg !57
  ret void, !dbg !58
}

declare ptr @_RZN4alloc5alloc17h_allocate(i64 noundef) #1

; Function Attrs: nounwind
declare ptr @__strcpy_chk(ptr noundef, ptr noundef, i64 noundef) #2

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.objectsize.i64.p0(ptr, i1 immarg, i1 immarg, i1 immarg) #3

declare void @free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @rust_02_c_alloc_rust_free() #0 !dbg !59 {
entry:
  %ptr = alloca ptr, align 8
    #dbg_declare(ptr %ptr, !60, !DIExpression(), !61)
  %call = call ptr @malloc(i64 noundef 256) #7, !dbg !62
  store ptr %call, ptr %ptr, align 8, !dbg !61
  %0 = load ptr, ptr %ptr, align 8, !dbg !63
  %1 = load ptr, ptr %ptr, align 8, !dbg !63
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !63
  %call1 = call ptr @__strcpy_chk(ptr noundef %0, ptr noundef @.str.1, i64 noundef %2) #6, !dbg !63
  %3 = load ptr, ptr %ptr, align 8, !dbg !64
  call void @_RZN4alloc5alloc17h_deallocate(ptr noundef %3), !dbg !65
  ret void, !dbg !66
}

; Function Attrs: allocsize(0)
declare ptr @malloc(i64 noundef) #4

declare void @_RZN4alloc5alloc17h_deallocate(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @rust_03_box_raw_c_free() #0 !dbg !67 {
entry:
  %boxed = alloca ptr, align 8
    #dbg_declare(ptr %boxed, !68, !DIExpression(), !69)
  %call = call ptr @_RZN3std3box8into_rawE(ptr noundef null), !dbg !70
  store ptr %call, ptr %boxed, align 8, !dbg !69
  %0 = load ptr, ptr %boxed, align 8, !dbg !71
  call void @free(ptr noundef %0), !dbg !72
  ret void, !dbg !73
}

declare ptr @_RZN3std3box8into_rawE(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @rust_04_store_rust_ref() #0 !dbg !74 {
entry:
  %rust_obj = alloca ptr, align 8
    #dbg_declare(ptr %rust_obj, !75, !DIExpression(), !76)
  %call = call ptr @_RZN4alloc5alloc17h_allocate(i64 noundef 64), !dbg !77
  store ptr %call, ptr %rust_obj, align 8, !dbg !76
  %0 = load ptr, ptr %rust_obj, align 8, !dbg !78
  store ptr %0, ptr @g_stored_rust_ref, align 8, !dbg !79
  %1 = load ptr, ptr %rust_obj, align 8, !dbg !80
  call void @_RZN4alloc5alloc17h_deallocate(ptr noundef %1), !dbg !81
  %2 = load ptr, ptr @g_stored_rust_ref, align 8, !dbg !82
  %3 = load ptr, ptr @g_stored_rust_ref, align 8, !dbg !82
  %4 = call i64 @llvm.objectsize.i64.p0(ptr %3, i1 false, i1 true, i1 false), !dbg !82
  %call1 = call ptr @__memset_chk(ptr noundef %2, i32 noundef 0, i64 noundef 64, i64 noundef %4) #6, !dbg !82
  ret void, !dbg !83
}

; Function Attrs: nounwind
declare ptr @__memset_chk(ptr noundef, i32 noundef, i64 noundef, i64 noundef) #2

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @rust_05_string_leak() #0 !dbg !84 {
entry:
  %rust_string = alloca ptr, align 8
    #dbg_declare(ptr %rust_string, !85, !DIExpression(), !86)
  %call = call ptr @_RZN3std3string10into_rawEv(ptr noundef null), !dbg !87
  store ptr %call, ptr %rust_string, align 8, !dbg !86
  %0 = load ptr, ptr %rust_string, align 8, !dbg !88
  %call1 = call i32 (ptr, ...) @printf(ptr noundef @.str.2, ptr noundef %0), !dbg !89
  ret void, !dbg !90
}

declare ptr @_RZN3std3string10into_rawEv(ptr noundef) #1

declare i32 @printf(ptr noundef, ...) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @rust_06_double_free_cross() #0 !dbg !91 {
entry:
  %ptr = alloca ptr, align 8
    #dbg_declare(ptr %ptr, !92, !DIExpression(), !93)
  %call = call ptr @_RZN4alloc5alloc17h_allocate(i64 noundef 64), !dbg !94
  store ptr %call, ptr %ptr, align 8, !dbg !93
  %0 = load ptr, ptr %ptr, align 8, !dbg !95
  call void @_RZN4alloc5alloc17h_deallocate(ptr noundef %0), !dbg !96
  %1 = load ptr, ptr %ptr, align 8, !dbg !97
  call void @free(ptr noundef %1), !dbg !98
  ret void, !dbg !99
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @rust_07_mut_alias_escape() #0 !dbg !100 {
entry:
  %rust_mut_ref = alloca ptr, align 8
  %alias = alloca ptr, align 8
    #dbg_declare(ptr %rust_mut_ref, !101, !DIExpression(), !102)
  %call = call ptr @_RZN4alloc5alloc17h_allocate(i64 noundef 128), !dbg !103
  store ptr %call, ptr %rust_mut_ref, align 8, !dbg !102
    #dbg_declare(ptr %alias, !104, !DIExpression(), !105)
  %0 = load ptr, ptr %rust_mut_ref, align 8, !dbg !106
  store ptr %0, ptr %alias, align 8, !dbg !105
  %1 = load ptr, ptr %rust_mut_ref, align 8, !dbg !107
  %2 = load ptr, ptr %rust_mut_ref, align 8, !dbg !107
  %3 = call i64 @llvm.objectsize.i64.p0(ptr %2, i1 false, i1 true, i1 false), !dbg !107
  %call1 = call ptr @__strcpy_chk(ptr noundef %1, ptr noundef @.str.3, i64 noundef %3) #6, !dbg !107
  %4 = load ptr, ptr %alias, align 8, !dbg !108
  %5 = load ptr, ptr %alias, align 8, !dbg !108
  %6 = call i64 @llvm.objectsize.i64.p0(ptr %5, i1 false, i1 true, i1 false), !dbg !108
  %call2 = call ptr @__strcpy_chk(ptr noundef %4, ptr noundef @.str.4, i64 noundef %6) #6, !dbg !108
  %7 = load ptr, ptr %rust_mut_ref, align 8, !dbg !109
  call void @_RZN4alloc5alloc17h_deallocate(ptr noundef %7), !dbg !110
  ret void, !dbg !111
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @rust_08_realloc_cross() #0 !dbg !112 {
entry:
  %ptr = alloca ptr, align 8
    #dbg_declare(ptr %ptr, !113, !DIExpression(), !114)
  %call = call ptr @_RZN4alloc5alloc17h_allocate(i64 noundef 64), !dbg !115
  store ptr %call, ptr %ptr, align 8, !dbg !114
  %0 = load ptr, ptr %ptr, align 8, !dbg !116
  %1 = load ptr, ptr %ptr, align 8, !dbg !116
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !116
  %call1 = call ptr @__strcpy_chk(ptr noundef %0, ptr noundef @.str.5, i64 noundef %2) #6, !dbg !116
  %3 = load ptr, ptr %ptr, align 8, !dbg !117
  %call2 = call ptr @realloc(ptr noundef %3, i64 noundef 4096) #8, !dbg !118
  store ptr %call2, ptr %ptr, align 8, !dbg !119
  %4 = load ptr, ptr %ptr, align 8, !dbg !120
  %5 = load ptr, ptr %ptr, align 8, !dbg !120
  %6 = call i64 @llvm.objectsize.i64.p0(ptr %5, i1 false, i1 true, i1 false), !dbg !120
  %call3 = call ptr @__strcat_chk(ptr noundef %4, ptr noundef @.str.6, i64 noundef %6) #6, !dbg !120
  %7 = load ptr, ptr %ptr, align 8, !dbg !121
  call void @_RZN4alloc5alloc17h_deallocate(ptr noundef %7), !dbg !122
  ret void, !dbg !123
}

; Function Attrs: allocsize(1)
declare ptr @realloc(ptr noundef, i64 noundef) #5

; Function Attrs: nounwind
declare ptr @__strcat_chk(ptr noundef, ptr noundef, i64 noundef) #2

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #4 = { allocsize(0) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #5 = { allocsize(1) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #6 = { nounwind }
attributes #7 = { allocsize(0) }
attributes #8 = { allocsize(1) }

!llvm.dbg.cu = !{!14}
!llvm.module.flags = !{!41, !42, !43, !44, !45, !46}
!llvm.ident = !{!47}

!0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
!1 = distinct !DIGlobalVariable(scope: null, file: !2, line: 35, type: !3, isLocal: true, isDefinition: true)
!2 = !DIFile(filename: "corpus/red_team_test/rust_ffi_bugs.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "3df185038646c4e2624d74735323e421")
!3 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 144, elements: !5)
!4 = !DIBasicType(name: "char", size: 8, encoding: DW_ATE_signed_char)
!5 = !{!6}
!6 = !DISubrange(count: 18)
!7 = !DIGlobalVariableExpression(var: !8, expr: !DIExpression())
!8 = distinct !DIGlobalVariable(scope: null, file: !2, line: 46, type: !9, isLocal: true, isDefinition: true)
!9 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 120, elements: !10)
!10 = !{!11}
!11 = !DISubrange(count: 15)
!12 = !DIGlobalVariableExpression(var: !13, expr: !DIExpression())
!13 = distinct !DIGlobalVariable(name: "g_stored_rust_ref", scope: !14, file: !2, line: 68, type: !17, isLocal: true, isDefinition: true)
!14 = distinct !DICompileUnit(language: DW_LANG_C11, file: !2, producer: "Homebrew clang version 21.1.8", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, retainedTypes: !15, globals: !18, splitDebugInlining: false, nameTableKind: Apple, sysroot: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk", sdk: "MacOSX15.sdk")
!15 = !{!16, !17}
!16 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !4, size: 64)
!17 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!18 = !{!0, !7, !19, !24, !29, !34, !39, !12}
!19 = !DIGlobalVariableExpression(var: !20, expr: !DIExpression())
!20 = distinct !DIGlobalVariable(scope: null, file: !2, line: 91, type: !21, isLocal: true, isDefinition: true)
!21 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 112, elements: !22)
!22 = !{!23}
!23 = !DISubrange(count: 14)
!24 = !DIGlobalVariableExpression(var: !25, expr: !DIExpression())
!25 = distinct !DIGlobalVariable(scope: null, file: !2, line: 117, type: !26, isLocal: true, isDefinition: true)
!26 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 104, elements: !27)
!27 = !{!28}
!28 = !DISubrange(count: 13)
!29 = !DIGlobalVariableExpression(var: !30, expr: !DIExpression())
!30 = distinct !DIGlobalVariable(scope: null, file: !2, line: 118, type: !31, isLocal: true, isDefinition: true)
!31 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 80, elements: !32)
!32 = !{!33}
!33 = !DISubrange(count: 10)
!34 = !DIGlobalVariableExpression(var: !35, expr: !DIExpression())
!35 = distinct !DIGlobalVariable(scope: null, file: !2, line: 131, type: !36, isLocal: true, isDefinition: true)
!36 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 48, elements: !37)
!37 = !{!38}
!38 = !DISubrange(count: 6)
!39 = !DIGlobalVariableExpression(var: !40, expr: !DIExpression())
!40 = distinct !DIGlobalVariable(scope: null, file: !2, line: 135, type: !31, isLocal: true, isDefinition: true)
!41 = !{i32 7, !"Dwarf Version", i32 5}
!42 = !{i32 2, !"Debug Info Version", i32 3}
!43 = !{i32 1, !"wchar_size", i32 4}
!44 = !{i32 8, !"PIC Level", i32 2}
!45 = !{i32 7, !"uwtable", i32 1}
!46 = !{i32 7, !"frame-pointer", i32 1}
!47 = !{!"Homebrew clang version 21.1.8"}
!48 = distinct !DISubprogram(name: "rust_01_alloc_c_free", scope: !2, file: !2, line: 33, type: !49, scopeLine: 33, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !51)
!49 = !DISubroutineType(types: !50)
!50 = !{null}
!51 = !{}
!52 = !DILocalVariable(name: "ptr", scope: !48, file: !2, line: 34, type: !17)
!53 = !DILocation(line: 34, column: 11, scope: !48)
!54 = !DILocation(line: 34, column: 17, scope: !48)
!55 = !DILocation(line: 35, column: 5, scope: !48)
!56 = !DILocation(line: 36, column: 10, scope: !48)
!57 = !DILocation(line: 36, column: 5, scope: !48)
!58 = !DILocation(line: 37, column: 1, scope: !48)
!59 = distinct !DISubprogram(name: "rust_02_c_alloc_rust_free", scope: !2, file: !2, line: 44, type: !49, scopeLine: 44, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !51)
!60 = !DILocalVariable(name: "ptr", scope: !59, file: !2, line: 45, type: !17)
!61 = !DILocation(line: 45, column: 11, scope: !59)
!62 = !DILocation(line: 45, column: 17, scope: !59)
!63 = !DILocation(line: 46, column: 5, scope: !59)
!64 = !DILocation(line: 47, column: 36, scope: !59)
!65 = !DILocation(line: 47, column: 5, scope: !59)
!66 = !DILocation(line: 48, column: 1, scope: !59)
!67 = distinct !DISubprogram(name: "rust_03_box_raw_c_free", scope: !2, file: !2, line: 56, type: !49, scopeLine: 56, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !51)
!68 = !DILocalVariable(name: "boxed", scope: !67, file: !2, line: 57, type: !17)
!69 = !DILocation(line: 57, column: 11, scope: !67)
!70 = !DILocation(line: 57, column: 19, scope: !67)
!71 = !DILocation(line: 59, column: 10, scope: !67)
!72 = !DILocation(line: 59, column: 5, scope: !67)
!73 = !DILocation(line: 60, column: 1, scope: !67)
!74 = distinct !DISubprogram(name: "rust_04_store_rust_ref", scope: !2, file: !2, line: 70, type: !49, scopeLine: 70, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !51)
!75 = !DILocalVariable(name: "rust_obj", scope: !74, file: !2, line: 71, type: !17)
!76 = !DILocation(line: 71, column: 11, scope: !74)
!77 = !DILocation(line: 71, column: 22, scope: !74)
!78 = !DILocation(line: 72, column: 25, scope: !74)
!79 = !DILocation(line: 72, column: 23, scope: !74)
!80 = !DILocation(line: 75, column: 36, scope: !74)
!81 = !DILocation(line: 75, column: 5, scope: !74)
!82 = !DILocation(line: 79, column: 5, scope: !74)
!83 = !DILocation(line: 80, column: 1, scope: !74)
!84 = distinct !DISubprogram(name: "rust_05_string_leak", scope: !2, file: !2, line: 88, type: !49, scopeLine: 88, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !51)
!85 = !DILocalVariable(name: "rust_string", scope: !84, file: !2, line: 89, type: !17)
!86 = !DILocation(line: 89, column: 11, scope: !84)
!87 = !DILocation(line: 89, column: 25, scope: !84)
!88 = !DILocation(line: 91, column: 30, scope: !84)
!89 = !DILocation(line: 91, column: 5, scope: !84)
!90 = !DILocation(line: 93, column: 1, scope: !84)
!91 = distinct !DISubprogram(name: "rust_06_double_free_cross", scope: !2, file: !2, line: 100, type: !49, scopeLine: 100, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !51)
!92 = !DILocalVariable(name: "ptr", scope: !91, file: !2, line: 101, type: !17)
!93 = !DILocation(line: 101, column: 11, scope: !91)
!94 = !DILocation(line: 101, column: 17, scope: !91)
!95 = !DILocation(line: 102, column: 36, scope: !91)
!96 = !DILocation(line: 102, column: 5, scope: !91)
!97 = !DILocation(line: 103, column: 10, scope: !91)
!98 = !DILocation(line: 103, column: 5, scope: !91)
!99 = !DILocation(line: 104, column: 1, scope: !91)
!100 = distinct !DISubprogram(name: "rust_07_mut_alias_escape", scope: !2, file: !2, line: 112, type: !49, scopeLine: 112, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !51)
!101 = !DILocalVariable(name: "rust_mut_ref", scope: !100, file: !2, line: 113, type: !17)
!102 = !DILocation(line: 113, column: 11, scope: !100)
!103 = !DILocation(line: 113, column: 26, scope: !100)
!104 = !DILocalVariable(name: "alias", scope: !100, file: !2, line: 114, type: !17)
!105 = !DILocation(line: 114, column: 11, scope: !100)
!106 = !DILocation(line: 114, column: 19, scope: !100)
!107 = !DILocation(line: 117, column: 5, scope: !100)
!108 = !DILocation(line: 118, column: 5, scope: !100)
!109 = !DILocation(line: 120, column: 36, scope: !100)
!110 = !DILocation(line: 120, column: 5, scope: !100)
!111 = !DILocation(line: 121, column: 1, scope: !100)
!112 = distinct !DISubprogram(name: "rust_08_realloc_cross", scope: !2, file: !2, line: 129, type: !49, scopeLine: 129, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !51)
!113 = !DILocalVariable(name: "ptr", scope: !112, file: !2, line: 130, type: !17)
!114 = !DILocation(line: 130, column: 11, scope: !112)
!115 = !DILocation(line: 130, column: 17, scope: !112)
!116 = !DILocation(line: 131, column: 5, scope: !112)
!117 = !DILocation(line: 134, column: 19, scope: !112)
!118 = !DILocation(line: 134, column: 11, scope: !112)
!119 = !DILocation(line: 134, column: 9, scope: !112)
!120 = !DILocation(line: 135, column: 5, scope: !112)
!121 = !DILocation(line: 138, column: 36, scope: !112)
!122 = !DILocation(line: 138, column: 5, scope: !112)
!123 = !DILocation(line: 139, column: 1, scope: !112)
