; ModuleID = 'corpus/red_team_test/csharp_win32_ffi_bugs.c'
source_filename = "corpus/red_team_test/csharp_win32_ffi_bugs.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc1_marshal_alloc_c_free() #0 !dbg !11 {
entry:
  %net_mem = alloca ptr, align 8
    #dbg_declare(ptr %net_mem, !15, !DIExpression(), !16)
  %call = call ptr @Marshal_AllocHGlobal(i32 noundef 1024), !dbg !17
  store ptr %call, ptr %net_mem, align 8, !dbg !16
  %0 = load ptr, ptr %net_mem, align 8, !dbg !18
  %1 = load ptr, ptr %net_mem, align 8, !dbg !18
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !18
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 0, i64 noundef 1024, i64 noundef %2) #5, !dbg !18
  %3 = load ptr, ptr %net_mem, align 8, !dbg !19
  call void @free(ptr noundef %3), !dbg !20
  ret void, !dbg !21
}

declare ptr @Marshal_AllocHGlobal(i32 noundef) #1

; Function Attrs: nounwind
declare ptr @__memset_chk(ptr noundef, i32 noundef, i64 noundef, i64 noundef) #2

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.objectsize.i64.p0(ptr, i1 immarg, i1 immarg, i1 immarg) #3

declare void @free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc2_com_alloc_c_free() #0 !dbg !22 {
entry:
  %com_mem = alloca ptr, align 8
    #dbg_declare(ptr %com_mem, !23, !DIExpression(), !24)
  %call = call ptr @CoTaskMemAlloc(i64 noundef 2048), !dbg !25
  store ptr %call, ptr %com_mem, align 8, !dbg !24
  %0 = load ptr, ptr %com_mem, align 8, !dbg !26
  %1 = load ptr, ptr %com_mem, align 8, !dbg !26
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !26
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 255, i64 noundef 2048, i64 noundef %2) #5, !dbg !26
  %3 = load ptr, ptr %com_mem, align 8, !dbg !27
  call void @free(ptr noundef %3), !dbg !28
  ret void, !dbg !29
}

declare ptr @CoTaskMemAlloc(i64 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc3_c_malloc_net_free() #0 !dbg !30 {
entry:
  %c_mem = alloca ptr, align 8
    #dbg_declare(ptr %c_mem, !31, !DIExpression(), !32)
  %call = call ptr @malloc(i64 noundef 4096) #6, !dbg !33
  store ptr %call, ptr %c_mem, align 8, !dbg !32
  %0 = load ptr, ptr %c_mem, align 8, !dbg !34
  %1 = load ptr, ptr %c_mem, align 8, !dbg !34
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !34
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 65, i64 noundef 4096, i64 noundef %2) #5, !dbg !34
  %3 = load ptr, ptr %c_mem, align 8, !dbg !35
  call void @Marshal_FreeHGlobal(ptr noundef %3), !dbg !36
  ret void, !dbg !37
}

; Function Attrs: allocsize(0)
declare ptr @malloc(i64 noundef) #4

declare void @Marshal_FreeHGlobal(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc4_heapalloc_localfree() #0 !dbg !38 {
entry:
  %heap_mem = alloca ptr, align 8
    #dbg_declare(ptr %heap_mem, !39, !DIExpression(), !40)
  %call = call ptr @HeapAlloc(ptr noundef null, i32 noundef 0, i64 noundef 8192), !dbg !41
  store ptr %call, ptr %heap_mem, align 8, !dbg !40
  %0 = load ptr, ptr %heap_mem, align 8, !dbg !42
  %1 = load ptr, ptr %heap_mem, align 8, !dbg !42
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !42
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 66, i64 noundef 8192, i64 noundef %2) #5, !dbg !42
  %3 = load ptr, ptr %heap_mem, align 8, !dbg !43
  call void @LocalFree(ptr noundef %3), !dbg !44
  ret void, !dbg !45
}

declare ptr @HeapAlloc(ptr noundef, i32 noundef, i64 noundef) #1

declare void @LocalFree(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc5_correct_pinvoke() #0 !dbg !46 {
entry:
  %buffer = alloca ptr, align 8
    #dbg_declare(ptr %buffer, !47, !DIExpression(), !48)
  %call = call ptr @Marshal_AllocHGlobal(i32 noundef 512), !dbg !49
  store ptr %call, ptr %buffer, align 8, !dbg !48
  %0 = load ptr, ptr %buffer, align 8, !dbg !50
  %1 = load ptr, ptr %buffer, align 8, !dbg !50
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !50
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 0, i64 noundef 512, i64 noundef %2) #5, !dbg !50
  %3 = load ptr, ptr %buffer, align 8, !dbg !51
  call void @Marshal_FreeHGlobal(ptr noundef %3), !dbg !52
  ret void, !dbg !53
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc6_com_leak() #0 !dbg !54 {
entry:
  %leaked = alloca ptr, align 8
    #dbg_declare(ptr %leaked, !55, !DIExpression(), !56)
  %call = call ptr @CoTaskMemAlloc(i64 noundef 16384), !dbg !57
  store ptr %call, ptr %leaked, align 8, !dbg !56
  %0 = load ptr, ptr %leaked, align 8, !dbg !58
  %1 = load ptr, ptr %leaked, align 8, !dbg !58
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !58
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 204, i64 noundef 16384, i64 noundef %2) #5, !dbg !58
  ret void, !dbg !59
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc7_mixed_win32_com_pinvoke() #0 !dbg !60 {
entry:
  %pinvoke_buf = alloca ptr, align 8
  %com_obj = alloca ptr, align 8
  %local_buf = alloca ptr, align 8
  %std_buf = alloca ptr, align 8
    #dbg_declare(ptr %pinvoke_buf, !61, !DIExpression(), !62)
  %call = call ptr @Marshal_AllocHGlobal(i32 noundef 256), !dbg !63
  store ptr %call, ptr %pinvoke_buf, align 8, !dbg !62
    #dbg_declare(ptr %com_obj, !64, !DIExpression(), !65)
  %call1 = call ptr @CoTaskMemAlloc(i64 noundef 1024), !dbg !66
  store ptr %call1, ptr %com_obj, align 8, !dbg !65
    #dbg_declare(ptr %local_buf, !67, !DIExpression(), !68)
  %call2 = call ptr @LocalAlloc(i32 noundef 0, i64 noundef 512), !dbg !69
  store ptr %call2, ptr %local_buf, align 8, !dbg !68
    #dbg_declare(ptr %std_buf, !70, !DIExpression(), !71)
  %call3 = call ptr @malloc(i64 noundef 2048) #6, !dbg !72
  store ptr %call3, ptr %std_buf, align 8, !dbg !71
  %0 = load ptr, ptr %pinvoke_buf, align 8, !dbg !73
  %1 = load ptr, ptr %pinvoke_buf, align 8, !dbg !73
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !73
  %call4 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 1, i64 noundef 256, i64 noundef %2) #5, !dbg !73
  %3 = load ptr, ptr %com_obj, align 8, !dbg !74
  %4 = load ptr, ptr %com_obj, align 8, !dbg !74
  %5 = call i64 @llvm.objectsize.i64.p0(ptr %4, i1 false, i1 true, i1 false), !dbg !74
  %call5 = call ptr @__memset_chk(ptr noundef %3, i32 noundef 2, i64 noundef 1024, i64 noundef %5) #5, !dbg !74
  %6 = load ptr, ptr %local_buf, align 8, !dbg !75
  %7 = load ptr, ptr %local_buf, align 8, !dbg !75
  %8 = call i64 @llvm.objectsize.i64.p0(ptr %7, i1 false, i1 true, i1 false), !dbg !75
  %call6 = call ptr @__memset_chk(ptr noundef %6, i32 noundef 3, i64 noundef 512, i64 noundef %8) #5, !dbg !75
  %9 = load ptr, ptr %std_buf, align 8, !dbg !76
  %10 = load ptr, ptr %std_buf, align 8, !dbg !76
  %11 = call i64 @llvm.objectsize.i64.p0(ptr %10, i1 false, i1 true, i1 false), !dbg !76
  %call7 = call ptr @__memset_chk(ptr noundef %9, i32 noundef 4, i64 noundef 2048, i64 noundef %11) #5, !dbg !76
  %12 = load ptr, ptr %pinvoke_buf, align 8, !dbg !77
  call void @free(ptr noundef %12), !dbg !78
  %13 = load ptr, ptr %com_obj, align 8, !dbg !79
  call void @Marshal_FreeHGlobal(ptr noundef %13), !dbg !80
  %14 = load ptr, ptr %local_buf, align 8, !dbg !81
  call void @free(ptr noundef %14), !dbg !82
  %15 = load ptr, ptr %std_buf, align 8, !dbg !83
  call void @CoTaskMemFree(ptr noundef %15), !dbg !84
  ret void, !dbg !85
}

declare ptr @LocalAlloc(i32 noundef, i64 noundef) #1

declare void @CoTaskMemFree(ptr noundef) #1

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #4 = { allocsize(0) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #5 = { nounwind }
attributes #6 = { allocsize(0) }

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!4, !5, !6, !7, !8, !9}
!llvm.ident = !{!10}

!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "Homebrew clang version 21.1.8", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, retainedTypes: !2, splitDebugInlining: false, nameTableKind: Apple, sysroot: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk", sdk: "MacOSX15.sdk")
!1 = !DIFile(filename: "corpus/red_team_test/csharp_win32_ffi_bugs.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "5c49be41f7b12bebd9e29f70c6b3f6ec")
!2 = !{!3}
!3 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!4 = !{i32 7, !"Dwarf Version", i32 5}
!5 = !{i32 2, !"Debug Info Version", i32 3}
!6 = !{i32 1, !"wchar_size", i32 4}
!7 = !{i32 8, !"PIC Level", i32 2}
!8 = !{i32 7, !"uwtable", i32 1}
!9 = !{i32 7, !"frame-pointer", i32 1}
!10 = !{!"Homebrew clang version 21.1.8"}
!11 = distinct !DISubprogram(name: "tc1_marshal_alloc_c_free", scope: !1, file: !1, line: 36, type: !12, scopeLine: 36, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!12 = !DISubroutineType(types: !13)
!13 = !{null}
!14 = !{}
!15 = !DILocalVariable(name: "net_mem", scope: !11, file: !1, line: 37, type: !3)
!16 = !DILocation(line: 37, column: 11, scope: !11)
!17 = !DILocation(line: 37, column: 21, scope: !11)
!18 = !DILocation(line: 38, column: 5, scope: !11)
!19 = !DILocation(line: 42, column: 10, scope: !11)
!20 = !DILocation(line: 42, column: 5, scope: !11)
!21 = !DILocation(line: 43, column: 1, scope: !11)
!22 = distinct !DISubprogram(name: "tc2_com_alloc_c_free", scope: !1, file: !1, line: 52, type: !12, scopeLine: 52, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!23 = !DILocalVariable(name: "com_mem", scope: !22, file: !1, line: 53, type: !3)
!24 = !DILocation(line: 53, column: 11, scope: !22)
!25 = !DILocation(line: 53, column: 21, scope: !22)
!26 = !DILocation(line: 54, column: 5, scope: !22)
!27 = !DILocation(line: 58, column: 10, scope: !22)
!28 = !DILocation(line: 58, column: 5, scope: !22)
!29 = !DILocation(line: 59, column: 1, scope: !22)
!30 = distinct !DISubprogram(name: "tc3_c_malloc_net_free", scope: !1, file: !1, line: 68, type: !12, scopeLine: 68, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!31 = !DILocalVariable(name: "c_mem", scope: !30, file: !1, line: 69, type: !3)
!32 = !DILocation(line: 69, column: 11, scope: !30)
!33 = !DILocation(line: 69, column: 19, scope: !30)
!34 = !DILocation(line: 70, column: 5, scope: !30)
!35 = !DILocation(line: 74, column: 25, scope: !30)
!36 = !DILocation(line: 74, column: 5, scope: !30)
!37 = !DILocation(line: 75, column: 1, scope: !30)
!38 = distinct !DISubprogram(name: "tc4_heapalloc_localfree", scope: !1, file: !1, line: 84, type: !12, scopeLine: 84, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!39 = !DILocalVariable(name: "heap_mem", scope: !38, file: !1, line: 85, type: !3)
!40 = !DILocation(line: 85, column: 11, scope: !38)
!41 = !DILocation(line: 85, column: 22, scope: !38)
!42 = !DILocation(line: 86, column: 5, scope: !38)
!43 = !DILocation(line: 90, column: 15, scope: !38)
!44 = !DILocation(line: 90, column: 5, scope: !38)
!45 = !DILocation(line: 91, column: 1, scope: !38)
!46 = distinct !DISubprogram(name: "tc5_correct_pinvoke", scope: !1, file: !1, line: 100, type: !12, scopeLine: 100, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!47 = !DILocalVariable(name: "buffer", scope: !46, file: !1, line: 101, type: !3)
!48 = !DILocation(line: 101, column: 11, scope: !46)
!49 = !DILocation(line: 101, column: 20, scope: !46)
!50 = !DILocation(line: 102, column: 5, scope: !46)
!51 = !DILocation(line: 106, column: 25, scope: !46)
!52 = !DILocation(line: 106, column: 5, scope: !46)
!53 = !DILocation(line: 107, column: 1, scope: !46)
!54 = distinct !DISubprogram(name: "tc6_com_leak", scope: !1, file: !1, line: 116, type: !12, scopeLine: 116, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!55 = !DILocalVariable(name: "leaked", scope: !54, file: !1, line: 117, type: !3)
!56 = !DILocation(line: 117, column: 11, scope: !54)
!57 = !DILocation(line: 117, column: 20, scope: !54)
!58 = !DILocation(line: 118, column: 5, scope: !54)
!59 = !DILocation(line: 122, column: 1, scope: !54)
!60 = distinct !DISubprogram(name: "tc7_mixed_win32_com_pinvoke", scope: !1, file: !1, line: 131, type: !12, scopeLine: 131, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!61 = !DILocalVariable(name: "pinvoke_buf", scope: !60, file: !1, line: 133, type: !3)
!62 = !DILocation(line: 133, column: 11, scope: !60)
!63 = !DILocation(line: 133, column: 25, scope: !60)
!64 = !DILocalVariable(name: "com_obj", scope: !60, file: !1, line: 136, type: !3)
!65 = !DILocation(line: 136, column: 11, scope: !60)
!66 = !DILocation(line: 136, column: 21, scope: !60)
!67 = !DILocalVariable(name: "local_buf", scope: !60, file: !1, line: 139, type: !3)
!68 = !DILocation(line: 139, column: 11, scope: !60)
!69 = !DILocation(line: 139, column: 23, scope: !60)
!70 = !DILocalVariable(name: "std_buf", scope: !60, file: !1, line: 142, type: !3)
!71 = !DILocation(line: 142, column: 11, scope: !60)
!72 = !DILocation(line: 142, column: 21, scope: !60)
!73 = !DILocation(line: 145, column: 5, scope: !60)
!74 = !DILocation(line: 146, column: 5, scope: !60)
!75 = !DILocation(line: 147, column: 5, scope: !60)
!76 = !DILocation(line: 148, column: 5, scope: !60)
!77 = !DILocation(line: 151, column: 10, scope: !60)
!78 = !DILocation(line: 151, column: 5, scope: !60)
!79 = !DILocation(line: 152, column: 25, scope: !60)
!80 = !DILocation(line: 152, column: 5, scope: !60)
!81 = !DILocation(line: 153, column: 10, scope: !60)
!82 = !DILocation(line: 153, column: 5, scope: !60)
!83 = !DILocation(line: 154, column: 19, scope: !60)
!84 = !DILocation(line: 154, column: 5, scope: !60)
!85 = !DILocation(line: 155, column: 1, scope: !60)
