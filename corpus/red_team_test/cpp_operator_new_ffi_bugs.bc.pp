; ModuleID = 'corpus/red_team_test/cpp_operator_new_ffi_bugs.c'
source_filename = "corpus/red_team_test/cpp_operator_new_ffi_bugs.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc1_cpp_new_c_free() #0 !dbg !9 {
entry:
  %cpp_obj = alloca ptr, align 8
    #dbg_declare(ptr %cpp_obj, !13, !DIExpression(), !15)
  %call = call ptr @operator_new(i64 noundef 400), !dbg !16
  store ptr %call, ptr %cpp_obj, align 8, !dbg !15
  %0 = load ptr, ptr %cpp_obj, align 8, !dbg !17
  %1 = load ptr, ptr %cpp_obj, align 8, !dbg !17
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !17
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 0, i64 noundef 400, i64 noundef %2) #6, !dbg !17
  %3 = load ptr, ptr %cpp_obj, align 8, !dbg !18
  call void @free(ptr noundef %3), !dbg !19
  ret void, !dbg !20
}

declare ptr @operator_new(i64 noundef) #1

; Function Attrs: nounwind
declare ptr @__memset_chk(ptr noundef, i32 noundef, i64 noundef, i64 noundef) #2

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.objectsize.i64.p0(ptr, i1 immarg, i1 immarg, i1 immarg) #3

declare void @free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc2_c_malloc_cpp_delete() #0 !dbg !21 {
entry:
  %c_mem = alloca ptr, align 8
    #dbg_declare(ptr %c_mem, !22, !DIExpression(), !23)
  %call = call ptr @malloc(i64 noundef 2048) #7, !dbg !24
  store ptr %call, ptr %c_mem, align 8, !dbg !23
  %0 = load ptr, ptr %c_mem, align 8, !dbg !25
  %1 = load ptr, ptr %c_mem, align 8, !dbg !25
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !25
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 88, i64 noundef 2048, i64 noundef %2) #6, !dbg !25
  %3 = load ptr, ptr %c_mem, align 8, !dbg !26
  call void @operator_delete(ptr noundef %3), !dbg !27
  ret void, !dbg !28
}

; Function Attrs: allocsize(0)
declare ptr @malloc(i64 noundef) #4

declare void @operator_delete(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc3_array_new_scalar_delete() #0 !dbg !29 {
entry:
  %arr = alloca ptr, align 8
    #dbg_declare(ptr %arr, !30, !DIExpression(), !31)
  %call = call ptr @operator_new_array(i64 noundef 400), !dbg !32
  store ptr %call, ptr %arr, align 8, !dbg !31
  %0 = load ptr, ptr %arr, align 8, !dbg !33
  %1 = load ptr, ptr %arr, align 8, !dbg !33
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !33
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 0, i64 noundef 400, i64 noundef %2) #6, !dbg !33
  %3 = load ptr, ptr %arr, align 8, !dbg !34
  call void @operator_delete(ptr noundef %3), !dbg !35
  ret void, !dbg !36
}

declare ptr @operator_new_array(i64 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc4_scalar_new_array_delete() #0 !dbg !37 {
entry:
  %scalar = alloca ptr, align 8
    #dbg_declare(ptr %scalar, !38, !DIExpression(), !39)
  %call = call ptr @operator_new(i64 noundef 256), !dbg !40
  store ptr %call, ptr %scalar, align 8, !dbg !39
  %0 = load ptr, ptr %scalar, align 8, !dbg !41
  %1 = load ptr, ptr %scalar, align 8, !dbg !41
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !41
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 171, i64 noundef 256, i64 noundef %2) #6, !dbg !41
  %3 = load ptr, ptr %scalar, align 8, !dbg !42
  call void @operator_delete_array(ptr noundef %3), !dbg !43
  ret void, !dbg !44
}

declare void @operator_delete_array(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc5_correct_cpp_memory() #0 !dbg !45 {
entry:
  %obj = alloca ptr, align 8
  %arr = alloca ptr, align 8
    #dbg_declare(ptr %obj, !46, !DIExpression(), !47)
  %call = call ptr @operator_new(i64 noundef 512), !dbg !48
  store ptr %call, ptr %obj, align 8, !dbg !47
  %0 = load ptr, ptr %obj, align 8, !dbg !49
  %1 = load ptr, ptr %obj, align 8, !dbg !49
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !49
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 1, i64 noundef 512, i64 noundef %2) #6, !dbg !49
  %3 = load ptr, ptr %obj, align 8, !dbg !50
  call void @operator_delete(ptr noundef %3), !dbg !51
    #dbg_declare(ptr %arr, !52, !DIExpression(), !53)
  %call2 = call ptr @operator_new_array(i64 noundef 400), !dbg !54
  store ptr %call2, ptr %arr, align 8, !dbg !53
  %4 = load ptr, ptr %arr, align 8, !dbg !55
  %5 = load ptr, ptr %arr, align 8, !dbg !55
  %6 = call i64 @llvm.objectsize.i64.p0(ptr %5, i1 false, i1 true, i1 false), !dbg !55
  %call3 = call ptr @__memset_chk(ptr noundef %4, i32 noundef 0, i64 noundef 400, i64 noundef %6) #6, !dbg !55
  %7 = load ptr, ptr %arr, align 8, !dbg !56
  call void @operator_delete_array(ptr noundef %7), !dbg !57
  ret void, !dbg !58
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc6_internal_cpp_leak() #0 !dbg !59 {
entry:
  %cache = alloca ptr, align 8
    #dbg_declare(ptr %cache, !60, !DIExpression(), !61)
  %call = call ptr @operator_new(i64 noundef 4096), !dbg !62
  store ptr %call, ptr %cache, align 8, !dbg !61
  %0 = load ptr, ptr %cache, align 8, !dbg !63
  %1 = load ptr, ptr %cache, align 8, !dbg !63
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !63
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 204, i64 noundef 4096, i64 noundef %2) #6, !dbg !63
  ret void, !dbg !64
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc7_mixed_ccpp_ffi() #0 !dbg !65 {
entry:
  %cpp_obj = alloca ptr, align 8
  %c_buf = alloca ptr, align 8
  %cpp_arr = alloca ptr, align 8
  %c_tmp = alloca ptr, align 8
    #dbg_declare(ptr %cpp_obj, !66, !DIExpression(), !67)
  %call = call ptr @operator_new(i64 noundef 1024), !dbg !68
  store ptr %call, ptr %cpp_obj, align 8, !dbg !67
    #dbg_declare(ptr %c_buf, !69, !DIExpression(), !70)
  %call1 = call ptr @malloc(i64 noundef 2048) #7, !dbg !71
  store ptr %call1, ptr %c_buf, align 8, !dbg !70
    #dbg_declare(ptr %cpp_arr, !72, !DIExpression(), !73)
  %call2 = call ptr @operator_new_array(i64 noundef 800), !dbg !74
  store ptr %call2, ptr %cpp_arr, align 8, !dbg !73
    #dbg_declare(ptr %c_tmp, !75, !DIExpression(), !76)
  %call3 = call ptr @calloc(i64 noundef 50, i64 noundef 1) #8, !dbg !77
  store ptr %call3, ptr %c_tmp, align 8, !dbg !76
  %0 = load ptr, ptr %cpp_obj, align 8, !dbg !78
  %1 = load ptr, ptr %cpp_obj, align 8, !dbg !78
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !78
  %call4 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 170, i64 noundef 1024, i64 noundef %2) #6, !dbg !78
  %3 = load ptr, ptr %c_buf, align 8, !dbg !79
  %4 = load ptr, ptr %c_buf, align 8, !dbg !79
  %5 = call i64 @llvm.objectsize.i64.p0(ptr %4, i1 false, i1 true, i1 false), !dbg !79
  %call5 = call ptr @__memset_chk(ptr noundef %3, i32 noundef 187, i64 noundef 2048, i64 noundef %5) #6, !dbg !79
  %6 = load ptr, ptr %cpp_arr, align 8, !dbg !80
  %7 = load ptr, ptr %cpp_arr, align 8, !dbg !80
  %8 = call i64 @llvm.objectsize.i64.p0(ptr %7, i1 false, i1 true, i1 false), !dbg !80
  %call6 = call ptr @__memset_chk(ptr noundef %6, i32 noundef 0, i64 noundef 800, i64 noundef %8) #6, !dbg !80
  %9 = load ptr, ptr %cpp_obj, align 8, !dbg !81
  call void @free(ptr noundef %9), !dbg !82
  %10 = load ptr, ptr %c_buf, align 8, !dbg !83
  call void @operator_delete(ptr noundef %10), !dbg !84
  %11 = load ptr, ptr %cpp_arr, align 8, !dbg !85
  call void @free(ptr noundef %11), !dbg !86
  %12 = load ptr, ptr %c_tmp, align 8, !dbg !87
  call void @operator_delete_array(ptr noundef %12), !dbg !88
  ret void, !dbg !89
}

; Function Attrs: allocsize(0,1)
declare ptr @calloc(i64 noundef, i64 noundef) #5

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #4 = { allocsize(0) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #5 = { allocsize(0,1) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #6 = { nounwind }
attributes #7 = { allocsize(0) }
attributes #8 = { allocsize(0,1) }

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!2, !3, !4, !5, !6, !7}
!llvm.ident = !{!8}

!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "Homebrew clang version 21.1.8", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, splitDebugInlining: false, nameTableKind: Apple, sysroot: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk", sdk: "MacOSX15.sdk")
!1 = !DIFile(filename: "corpus/red_team_test/cpp_operator_new_ffi_bugs.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "d91691d06874231e2f0426f9a0f21514")
!2 = !{i32 7, !"Dwarf Version", i32 5}
!3 = !{i32 2, !"Debug Info Version", i32 3}
!4 = !{i32 1, !"wchar_size", i32 4}
!5 = !{i32 8, !"PIC Level", i32 2}
!6 = !{i32 7, !"uwtable", i32 1}
!7 = !{i32 7, !"frame-pointer", i32 1}
!8 = !{!"Homebrew clang version 21.1.8"}
!9 = distinct !DISubprogram(name: "tc1_cpp_new_c_free", scope: !1, file: !1, line: 32, type: !10, scopeLine: 32, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !12)
!10 = !DISubroutineType(types: !11)
!11 = !{null}
!12 = !{}
!13 = !DILocalVariable(name: "cpp_obj", scope: !9, file: !1, line: 33, type: !14)
!14 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!15 = !DILocation(line: 33, column: 11, scope: !9)
!16 = !DILocation(line: 33, column: 21, scope: !9)
!17 = !DILocation(line: 34, column: 5, scope: !9)
!18 = !DILocation(line: 38, column: 10, scope: !9)
!19 = !DILocation(line: 38, column: 5, scope: !9)
!20 = !DILocation(line: 39, column: 1, scope: !9)
!21 = distinct !DISubprogram(name: "tc2_c_malloc_cpp_delete", scope: !1, file: !1, line: 48, type: !10, scopeLine: 48, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !12)
!22 = !DILocalVariable(name: "c_mem", scope: !21, file: !1, line: 49, type: !14)
!23 = !DILocation(line: 49, column: 11, scope: !21)
!24 = !DILocation(line: 49, column: 19, scope: !21)
!25 = !DILocation(line: 50, column: 5, scope: !21)
!26 = !DILocation(line: 54, column: 21, scope: !21)
!27 = !DILocation(line: 54, column: 5, scope: !21)
!28 = !DILocation(line: 55, column: 1, scope: !21)
!29 = distinct !DISubprogram(name: "tc3_array_new_scalar_delete", scope: !1, file: !1, line: 65, type: !10, scopeLine: 65, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !12)
!30 = !DILocalVariable(name: "arr", scope: !29, file: !1, line: 66, type: !14)
!31 = !DILocation(line: 66, column: 11, scope: !29)
!32 = !DILocation(line: 66, column: 17, scope: !29)
!33 = !DILocation(line: 67, column: 5, scope: !29)
!34 = !DILocation(line: 71, column: 21, scope: !29)
!35 = !DILocation(line: 71, column: 5, scope: !29)
!36 = !DILocation(line: 72, column: 1, scope: !29)
!37 = distinct !DISubprogram(name: "tc4_scalar_new_array_delete", scope: !1, file: !1, line: 81, type: !10, scopeLine: 81, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !12)
!38 = !DILocalVariable(name: "scalar", scope: !37, file: !1, line: 82, type: !14)
!39 = !DILocation(line: 82, column: 11, scope: !37)
!40 = !DILocation(line: 82, column: 20, scope: !37)
!41 = !DILocation(line: 83, column: 5, scope: !37)
!42 = !DILocation(line: 87, column: 27, scope: !37)
!43 = !DILocation(line: 87, column: 5, scope: !37)
!44 = !DILocation(line: 88, column: 1, scope: !37)
!45 = distinct !DISubprogram(name: "tc5_correct_cpp_memory", scope: !1, file: !1, line: 96, type: !10, scopeLine: 96, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !12)
!46 = !DILocalVariable(name: "obj", scope: !45, file: !1, line: 98, type: !14)
!47 = !DILocation(line: 98, column: 11, scope: !45)
!48 = !DILocation(line: 98, column: 17, scope: !45)
!49 = !DILocation(line: 99, column: 5, scope: !45)
!50 = !DILocation(line: 100, column: 21, scope: !45)
!51 = !DILocation(line: 100, column: 5, scope: !45)
!52 = !DILocalVariable(name: "arr", scope: !45, file: !1, line: 103, type: !14)
!53 = !DILocation(line: 103, column: 11, scope: !45)
!54 = !DILocation(line: 103, column: 17, scope: !45)
!55 = !DILocation(line: 104, column: 5, scope: !45)
!56 = !DILocation(line: 105, column: 27, scope: !45)
!57 = !DILocation(line: 105, column: 5, scope: !45)
!58 = !DILocation(line: 106, column: 1, scope: !45)
!59 = distinct !DISubprogram(name: "tc6_internal_cpp_leak", scope: !1, file: !1, line: 116, type: !10, scopeLine: 116, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !12)
!60 = !DILocalVariable(name: "cache", scope: !59, file: !1, line: 118, type: !14)
!61 = !DILocation(line: 118, column: 11, scope: !59)
!62 = !DILocation(line: 118, column: 19, scope: !59)
!63 = !DILocation(line: 119, column: 5, scope: !59)
!64 = !DILocation(line: 124, column: 1, scope: !59)
!65 = distinct !DISubprogram(name: "tc7_mixed_ccpp_ffi", scope: !1, file: !1, line: 133, type: !10, scopeLine: 133, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !12)
!66 = !DILocalVariable(name: "cpp_obj", scope: !65, file: !1, line: 135, type: !14)
!67 = !DILocation(line: 135, column: 11, scope: !65)
!68 = !DILocation(line: 135, column: 21, scope: !65)
!69 = !DILocalVariable(name: "c_buf", scope: !65, file: !1, line: 138, type: !14)
!70 = !DILocation(line: 138, column: 11, scope: !65)
!71 = !DILocation(line: 138, column: 19, scope: !65)
!72 = !DILocalVariable(name: "cpp_arr", scope: !65, file: !1, line: 141, type: !14)
!73 = !DILocation(line: 141, column: 11, scope: !65)
!74 = !DILocation(line: 141, column: 21, scope: !65)
!75 = !DILocalVariable(name: "c_tmp", scope: !65, file: !1, line: 144, type: !14)
!76 = !DILocation(line: 144, column: 11, scope: !65)
!77 = !DILocation(line: 144, column: 19, scope: !65)
!78 = !DILocation(line: 147, column: 5, scope: !65)
!79 = !DILocation(line: 148, column: 5, scope: !65)
!80 = !DILocation(line: 149, column: 5, scope: !65)
!81 = !DILocation(line: 153, column: 10, scope: !65)
!82 = !DILocation(line: 153, column: 5, scope: !65)
!83 = !DILocation(line: 154, column: 21, scope: !65)
!84 = !DILocation(line: 154, column: 5, scope: !65)
!85 = !DILocation(line: 155, column: 10, scope: !65)
!86 = !DILocation(line: 155, column: 5, scope: !65)
!87 = !DILocation(line: 156, column: 27, scope: !65)
!88 = !DILocation(line: 156, column: 5, scope: !65)
!89 = !DILocation(line: 157, column: 1, scope: !65)
