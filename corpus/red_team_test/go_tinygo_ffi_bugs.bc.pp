; ModuleID = 'corpus/red_team_test/go_tinygo_ffi_bugs.c'
source_filename = "corpus/red_team_test/go_tinygo_ffi_bugs.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc1_go_alloc_c_free() #0 !dbg !11 {
entry:
  %go_mem = alloca ptr, align 8
    #dbg_declare(ptr %go_mem, !15, !DIExpression(), !16)
  %call = call ptr @runtime_alloc(i64 noundef 1024, i64 noundef 0), !dbg !17
  store ptr %call, ptr %go_mem, align 8, !dbg !16
  %0 = load ptr, ptr %go_mem, align 8, !dbg !18
  call void @free(ptr noundef %0), !dbg !19
  ret void, !dbg !20
}

declare ptr @runtime_alloc(i64 noundef, i64 noundef) #1

declare void @free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc2_c_malloc_go_free() #0 !dbg !21 {
entry:
  %c_mem = alloca ptr, align 8
    #dbg_declare(ptr %c_mem, !22, !DIExpression(), !23)
  %call = call ptr @malloc(i64 noundef 2048) #4, !dbg !24
  store ptr %call, ptr %c_mem, align 8, !dbg !23
  %0 = load ptr, ptr %c_mem, align 8, !dbg !25
  call void @runtime_free(ptr noundef %0), !dbg !26
  ret void, !dbg !27
}

; Function Attrs: allocsize(0)
declare ptr @malloc(i64 noundef) #2

declare void @runtime_free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc3_go_alloc_go_free() #0 !dbg !28 {
entry:
  %go_mem = alloca ptr, align 8
    #dbg_declare(ptr %go_mem, !29, !DIExpression(), !30)
  %call = call ptr @runtime_alloc(i64 noundef 512, i64 noundef 0), !dbg !31
  store ptr %call, ptr %go_mem, align 8, !dbg !30
  %0 = load ptr, ptr %go_mem, align 8, !dbg !32
  call void @runtime_free(ptr noundef %0), !dbg !33
  ret void, !dbg !34
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc4_cgo_bridge_safe() #0 !dbg !35 {
entry:
  %cgo_mem = alloca ptr, align 8
    #dbg_declare(ptr %cgo_mem, !36, !DIExpression(), !37)
  %call = call ptr @_Cgo_malloc(i64 noundef 256), !dbg !38
  store ptr %call, ptr %cgo_mem, align 8, !dbg !37
  %0 = load ptr, ptr %cgo_mem, align 8, !dbg !39
  call void @free(ptr noundef %0), !dbg !40
  ret void, !dbg !41
}

declare ptr @_Cgo_malloc(i64 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc5_go_alloc_leak() #0 !dbg !42 {
entry:
  %leaked = alloca ptr, align 8
    #dbg_declare(ptr %leaked, !43, !DIExpression(), !44)
  %call = call ptr @runtime_alloc(i64 noundef 4096, i64 noundef 0), !dbg !45
  store ptr %call, ptr %leaked, align 8, !dbg !44
  ret void, !dbg !46
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc6_go_realloc_c_free() #0 !dbg !47 {
entry:
  %original = alloca ptr, align 8
  %grown = alloca ptr, align 8
    #dbg_declare(ptr %original, !48, !DIExpression(), !49)
  %call = call ptr @malloc(i64 noundef 128) #4, !dbg !50
  store ptr %call, ptr %original, align 8, !dbg !49
    #dbg_declare(ptr %grown, !51, !DIExpression(), !52)
  %0 = load ptr, ptr %original, align 8, !dbg !53
  %call1 = call ptr @runtime_realloc(ptr noundef %0, i64 noundef 1024), !dbg !54
  store ptr %call1, ptr %grown, align 8, !dbg !52
  %1 = load ptr, ptr %grown, align 8, !dbg !55
  call void @free(ptr noundef %1), !dbg !56
  ret void, !dbg !57
}

declare ptr @runtime_realloc(ptr noundef, i64 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc7_c_calloc_tinygo_free() #0 !dbg !58 {
entry:
  %zeroed = alloca ptr, align 8
    #dbg_declare(ptr %zeroed, !59, !DIExpression(), !60)
  %call = call ptr @calloc(i64 noundef 100, i64 noundef 4) #5, !dbg !61
  store ptr %call, ptr %zeroed, align 8, !dbg !60
  %0 = load ptr, ptr %zeroed, align 8, !dbg !62
  call void @tinygo_free(ptr noundef %0), !dbg !63
  ret void, !dbg !64
}

; Function Attrs: allocsize(0,1)
declare ptr @calloc(i64 noundef, i64 noundef) #3

declare void @tinygo_free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc8_mixed_ffi_bugs() #0 !dbg !65 {
entry:
  %go_ptr = alloca ptr, align 8
  %c_ptr = alloca ptr, align 8
  %tg_ptr = alloca ptr, align 8
    #dbg_declare(ptr %go_ptr, !66, !DIExpression(), !67)
  %call = call ptr @runtime_alloc(i64 noundef 256, i64 noundef 0), !dbg !68
  store ptr %call, ptr %go_ptr, align 8, !dbg !67
    #dbg_declare(ptr %c_ptr, !69, !DIExpression(), !70)
  %call1 = call ptr @malloc(i64 noundef 512) #4, !dbg !71
  store ptr %call1, ptr %c_ptr, align 8, !dbg !70
    #dbg_declare(ptr %tg_ptr, !72, !DIExpression(), !73)
  %call2 = call ptr @tinygo_alloc(i64 noundef 128), !dbg !74
  store ptr %call2, ptr %tg_ptr, align 8, !dbg !73
  %0 = load ptr, ptr %go_ptr, align 8, !dbg !75
  call void @free(ptr noundef %0), !dbg !76
  %1 = load ptr, ptr %c_ptr, align 8, !dbg !77
  call void @runtime_free(ptr noundef %1), !dbg !78
  %2 = load ptr, ptr %tg_ptr, align 8, !dbg !79
  call void @free(ptr noundef %2), !dbg !80
  ret void, !dbg !81
}

declare ptr @tinygo_alloc(i64 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc9_gc_track_pointer(ptr noundef %user_ptr) #0 !dbg !82 {
entry:
  %user_ptr.addr = alloca ptr, align 8
  %go_mem = alloca ptr, align 8
  store ptr %user_ptr, ptr %user_ptr.addr, align 8
    #dbg_declare(ptr %user_ptr.addr, !85, !DIExpression(), !86)
    #dbg_declare(ptr %go_mem, !87, !DIExpression(), !88)
  %call = call ptr @runtime_alloc(i64 noundef 64, i64 noundef 0), !dbg !89
  store ptr %call, ptr %go_mem, align 8, !dbg !88
  %0 = load ptr, ptr %go_mem, align 8, !dbg !90
  call void @runtime_trackPointer(ptr noundef %0, ptr noundef null), !dbg !91
  %1 = load ptr, ptr %go_mem, align 8, !dbg !92
  call void @runtime_free(ptr noundef %1), !dbg !93
  ret void, !dbg !94
}

declare void @runtime_trackPointer(ptr noundef, ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc10_correct_nested_ffi() #0 !dbg !95 {
entry:
  %go_data = alloca ptr, align 8
  %go_buffer = alloca ptr, align 8
  %c_data = alloca ptr, align 8
  %c_temp = alloca ptr, align 8
    #dbg_declare(ptr %go_data, !96, !DIExpression(), !97)
  %call = call ptr @runtime_alloc(i64 noundef 1024, i64 noundef 0), !dbg !98
  store ptr %call, ptr %go_data, align 8, !dbg !97
    #dbg_declare(ptr %go_buffer, !99, !DIExpression(), !100)
  %call1 = call ptr @runtime_alloc(i64 noundef 4096, i64 noundef 0), !dbg !101
  store ptr %call1, ptr %go_buffer, align 8, !dbg !100
    #dbg_declare(ptr %c_data, !102, !DIExpression(), !103)
  %call2 = call ptr @malloc(i64 noundef 2048) #4, !dbg !104
  store ptr %call2, ptr %c_data, align 8, !dbg !103
    #dbg_declare(ptr %c_temp, !105, !DIExpression(), !106)
  %call3 = call ptr @calloc(i64 noundef 50, i64 noundef 8) #5, !dbg !107
  store ptr %call3, ptr %c_temp, align 8, !dbg !106
  %0 = load ptr, ptr %go_data, align 8, !dbg !108
  call void @runtime_free(ptr noundef %0), !dbg !109
  %1 = load ptr, ptr %go_buffer, align 8, !dbg !110
  call void @runtime_free(ptr noundef %1), !dbg !111
  %2 = load ptr, ptr %c_data, align 8, !dbg !112
  call void @free(ptr noundef %2), !dbg !113
  %3 = load ptr, ptr %c_temp, align 8, !dbg !114
  call void @free(ptr noundef %3), !dbg !115
  ret void, !dbg !116
}

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { allocsize(0) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { allocsize(0,1) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #4 = { allocsize(0) }
attributes #5 = { allocsize(0,1) }

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!4, !5, !6, !7, !8, !9}
!llvm.ident = !{!10}

!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "Homebrew clang version 21.1.8", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, retainedTypes: !2, splitDebugInlining: false, nameTableKind: Apple, sysroot: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk", sdk: "MacOSX15.sdk")
!1 = !DIFile(filename: "corpus/red_team_test/go_tinygo_ffi_bugs.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "b46ad52c4fa611da68d2b0e2ddb36870")
!2 = !{!3}
!3 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!4 = !{i32 7, !"Dwarf Version", i32 5}
!5 = !{i32 2, !"Debug Info Version", i32 3}
!6 = !{i32 1, !"wchar_size", i32 4}
!7 = !{i32 8, !"PIC Level", i32 2}
!8 = !{i32 7, !"uwtable", i32 1}
!9 = !{i32 7, !"frame-pointer", i32 1}
!10 = !{!"Homebrew clang version 21.1.8"}
!11 = distinct !DISubprogram(name: "tc1_go_alloc_c_free", scope: !1, file: !1, line: 39, type: !12, scopeLine: 39, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!12 = !DISubroutineType(types: !13)
!13 = !{null}
!14 = !{}
!15 = !DILocalVariable(name: "go_mem", scope: !11, file: !1, line: 40, type: !3)
!16 = !DILocation(line: 40, column: 11, scope: !11)
!17 = !DILocation(line: 40, column: 20, scope: !11)
!18 = !DILocation(line: 42, column: 10, scope: !11)
!19 = !DILocation(line: 42, column: 5, scope: !11)
!20 = !DILocation(line: 43, column: 1, scope: !11)
!21 = distinct !DISubprogram(name: "tc2_c_malloc_go_free", scope: !1, file: !1, line: 52, type: !12, scopeLine: 52, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!22 = !DILocalVariable(name: "c_mem", scope: !21, file: !1, line: 53, type: !3)
!23 = !DILocation(line: 53, column: 11, scope: !21)
!24 = !DILocation(line: 53, column: 19, scope: !21)
!25 = !DILocation(line: 55, column: 18, scope: !21)
!26 = !DILocation(line: 55, column: 5, scope: !21)
!27 = !DILocation(line: 56, column: 1, scope: !21)
!28 = distinct !DISubprogram(name: "tc3_go_alloc_go_free", scope: !1, file: !1, line: 65, type: !12, scopeLine: 65, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!29 = !DILocalVariable(name: "go_mem", scope: !28, file: !1, line: 66, type: !3)
!30 = !DILocation(line: 66, column: 11, scope: !28)
!31 = !DILocation(line: 66, column: 20, scope: !28)
!32 = !DILocation(line: 68, column: 18, scope: !28)
!33 = !DILocation(line: 68, column: 5, scope: !28)
!34 = !DILocation(line: 69, column: 1, scope: !28)
!35 = distinct !DISubprogram(name: "tc4_cgo_bridge_safe", scope: !1, file: !1, line: 78, type: !12, scopeLine: 78, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!36 = !DILocalVariable(name: "cgo_mem", scope: !35, file: !1, line: 79, type: !3)
!37 = !DILocation(line: 79, column: 11, scope: !35)
!38 = !DILocation(line: 79, column: 21, scope: !35)
!39 = !DILocation(line: 81, column: 10, scope: !35)
!40 = !DILocation(line: 81, column: 5, scope: !35)
!41 = !DILocation(line: 82, column: 1, scope: !35)
!42 = distinct !DISubprogram(name: "tc5_go_alloc_leak", scope: !1, file: !1, line: 91, type: !12, scopeLine: 91, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!43 = !DILocalVariable(name: "leaked", scope: !42, file: !1, line: 92, type: !3)
!44 = !DILocation(line: 92, column: 11, scope: !42)
!45 = !DILocation(line: 92, column: 20, scope: !42)
!46 = !DILocation(line: 95, column: 1, scope: !42)
!47 = distinct !DISubprogram(name: "tc6_go_realloc_c_free", scope: !1, file: !1, line: 103, type: !12, scopeLine: 103, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!48 = !DILocalVariable(name: "original", scope: !47, file: !1, line: 104, type: !3)
!49 = !DILocation(line: 104, column: 11, scope: !47)
!50 = !DILocation(line: 104, column: 22, scope: !47)
!51 = !DILocalVariable(name: "grown", scope: !47, file: !1, line: 105, type: !3)
!52 = !DILocation(line: 105, column: 11, scope: !47)
!53 = !DILocation(line: 105, column: 35, scope: !47)
!54 = !DILocation(line: 105, column: 19, scope: !47)
!55 = !DILocation(line: 107, column: 10, scope: !47)
!56 = !DILocation(line: 107, column: 5, scope: !47)
!57 = !DILocation(line: 108, column: 1, scope: !47)
!58 = distinct !DISubprogram(name: "tc7_c_calloc_tinygo_free", scope: !1, file: !1, line: 117, type: !12, scopeLine: 117, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!59 = !DILocalVariable(name: "zeroed", scope: !58, file: !1, line: 118, type: !3)
!60 = !DILocation(line: 118, column: 11, scope: !58)
!61 = !DILocation(line: 118, column: 20, scope: !58)
!62 = !DILocation(line: 120, column: 17, scope: !58)
!63 = !DILocation(line: 120, column: 5, scope: !58)
!64 = !DILocation(line: 121, column: 1, scope: !58)
!65 = distinct !DISubprogram(name: "tc8_mixed_ffi_bugs", scope: !1, file: !1, line: 130, type: !12, scopeLine: 130, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!66 = !DILocalVariable(name: "go_ptr", scope: !65, file: !1, line: 131, type: !3)
!67 = !DILocation(line: 131, column: 11, scope: !65)
!68 = !DILocation(line: 131, column: 20, scope: !65)
!69 = !DILocalVariable(name: "c_ptr", scope: !65, file: !1, line: 132, type: !3)
!70 = !DILocation(line: 132, column: 11, scope: !65)
!71 = !DILocation(line: 132, column: 19, scope: !65)
!72 = !DILocalVariable(name: "tg_ptr", scope: !65, file: !1, line: 133, type: !3)
!73 = !DILocation(line: 133, column: 11, scope: !65)
!74 = !DILocation(line: 133, column: 20, scope: !65)
!75 = !DILocation(line: 136, column: 10, scope: !65)
!76 = !DILocation(line: 136, column: 5, scope: !65)
!77 = !DILocation(line: 137, column: 18, scope: !65)
!78 = !DILocation(line: 137, column: 5, scope: !65)
!79 = !DILocation(line: 138, column: 10, scope: !65)
!80 = !DILocation(line: 138, column: 5, scope: !65)
!81 = !DILocation(line: 139, column: 1, scope: !65)
!82 = distinct !DISubprogram(name: "tc9_gc_track_pointer", scope: !1, file: !1, line: 148, type: !83, scopeLine: 148, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!83 = !DISubroutineType(types: !84)
!84 = !{null, !3}
!85 = !DILocalVariable(name: "user_ptr", arg: 1, scope: !82, file: !1, line: 148, type: !3)
!86 = !DILocation(line: 148, column: 33, scope: !82)
!87 = !DILocalVariable(name: "go_mem", scope: !82, file: !1, line: 149, type: !3)
!88 = !DILocation(line: 149, column: 11, scope: !82)
!89 = !DILocation(line: 149, column: 20, scope: !82)
!90 = !DILocation(line: 150, column: 26, scope: !82)
!91 = !DILocation(line: 150, column: 5, scope: !82)
!92 = !DILocation(line: 151, column: 18, scope: !82)
!93 = !DILocation(line: 151, column: 5, scope: !82)
!94 = !DILocation(line: 152, column: 1, scope: !82)
!95 = distinct !DISubprogram(name: "tc10_correct_nested_ffi", scope: !1, file: !1, line: 161, type: !12, scopeLine: 161, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!96 = !DILocalVariable(name: "go_data", scope: !95, file: !1, line: 163, type: !3)
!97 = !DILocation(line: 163, column: 11, scope: !95)
!98 = !DILocation(line: 163, column: 21, scope: !95)
!99 = !DILocalVariable(name: "go_buffer", scope: !95, file: !1, line: 164, type: !3)
!100 = !DILocation(line: 164, column: 11, scope: !95)
!101 = !DILocation(line: 164, column: 23, scope: !95)
!102 = !DILocalVariable(name: "c_data", scope: !95, file: !1, line: 167, type: !3)
!103 = !DILocation(line: 167, column: 11, scope: !95)
!104 = !DILocation(line: 167, column: 20, scope: !95)
!105 = !DILocalVariable(name: "c_temp", scope: !95, file: !1, line: 168, type: !3)
!106 = !DILocation(line: 168, column: 11, scope: !95)
!107 = !DILocation(line: 168, column: 20, scope: !95)
!108 = !DILocation(line: 173, column: 18, scope: !95)
!109 = !DILocation(line: 173, column: 5, scope: !95)
!110 = !DILocation(line: 174, column: 18, scope: !95)
!111 = !DILocation(line: 174, column: 5, scope: !95)
!112 = !DILocation(line: 175, column: 10, scope: !95)
!113 = !DILocation(line: 175, column: 5, scope: !95)
!114 = !DILocation(line: 176, column: 10, scope: !95)
!115 = !DILocation(line: 176, column: 5, scope: !95)
!116 = !DILocation(line: 177, column: 1, scope: !95)
