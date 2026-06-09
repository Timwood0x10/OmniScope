; ModuleID = 'corpus/red_team_test/zig_cimport_ffi_bugs.c'
source_filename = "corpus/red_team_test/zig_cimport_ffi_bugs.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc1_zig_alloc_c_free() #0 !dbg !11 {
entry:
  %zig_mem = alloca ptr, align 8
    #dbg_declare(ptr %zig_mem, !15, !DIExpression(), !16)
  %call = call ptr @zig_alloc(i64 noundef 1024), !dbg !17
  store ptr %call, ptr %zig_mem, align 8, !dbg !16
  %0 = load ptr, ptr %zig_mem, align 8, !dbg !18
  %1 = load ptr, ptr %zig_mem, align 8, !dbg !18
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !18
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 171, i64 noundef 1024, i64 noundef %2) #5, !dbg !18
  %3 = load ptr, ptr %zig_mem, align 8, !dbg !19
  call void @free(ptr noundef %3), !dbg !20
  ret void, !dbg !21
}

declare ptr @zig_alloc(i64 noundef) #1

; Function Attrs: nounwind
declare ptr @__memset_chk(ptr noundef, i32 noundef, i64 noundef, i64 noundef) #2

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.objectsize.i64.p0(ptr, i1 immarg, i1 immarg, i1 immarg) #3

declare void @free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc2_c_malloc_zig_dealloc() #0 !dbg !22 {
entry:
  %c_mem = alloca ptr, align 8
    #dbg_declare(ptr %c_mem, !23, !DIExpression(), !24)
  %call = call ptr @malloc(i64 noundef 2048) #6, !dbg !25
  store ptr %call, ptr %c_mem, align 8, !dbg !24
  %0 = load ptr, ptr %c_mem, align 8, !dbg !26
  %1 = load ptr, ptr %c_mem, align 8, !dbg !26
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !26
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 205, i64 noundef 2048, i64 noundef %2) #5, !dbg !26
  %3 = load ptr, ptr %c_mem, align 8, !dbg !27
  call void @__zig_dealloc(ptr noundef %3, i64 noundef 2048), !dbg !28
  ret void, !dbg !29
}

; Function Attrs: allocsize(0)
declare ptr @malloc(i64 noundef) #4

declare void @__zig_dealloc(ptr noundef, i64 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc3_pagealloc_c_free() #0 !dbg !30 {
entry:
  %page_mem = alloca ptr, align 8
    #dbg_declare(ptr %page_mem, !31, !DIExpression(), !32)
  %call = call ptr @PageAllocator_alloc(i64 noundef 4096), !dbg !33
  store ptr %call, ptr %page_mem, align 8, !dbg !32
  %0 = load ptr, ptr %page_mem, align 8, !dbg !34
  %1 = load ptr, ptr %page_mem, align 8, !dbg !34
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !34
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 239, i64 noundef 4096, i64 noundef %2) #5, !dbg !34
  %3 = load ptr, ptr %page_mem, align 8, !dbg !35
  call void @free(ptr noundef %3), !dbg !36
  ret void, !dbg !37
}

declare ptr @PageAllocator_alloc(i64 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc4_c_malloc_pagefree() #0 !dbg !38 {
entry:
  %c_mem = alloca ptr, align 8
    #dbg_declare(ptr %c_mem, !39, !DIExpression(), !40)
  %call = call ptr @malloc(i64 noundef 8192) #6, !dbg !41
  store ptr %call, ptr %c_mem, align 8, !dbg !40
  %0 = load ptr, ptr %c_mem, align 8, !dbg !42
  %1 = load ptr, ptr %c_mem, align 8, !dbg !42
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !42
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 18, i64 noundef 8192, i64 noundef %2) #5, !dbg !42
  %3 = load ptr, ptr %c_mem, align 8, !dbg !43
  call void @PageAllocator_free(ptr noundef %3), !dbg !44
  ret void, !dbg !45
}

declare void @PageAllocator_free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc5_correct_zig_memory() #0 !dbg !46 {
entry:
  %gpa_mem = alloca ptr, align 8
  %page_mem = alloca ptr, align 8
    #dbg_declare(ptr %gpa_mem, !47, !DIExpression(), !48)
  %call = call ptr @GeneralPoolAllocator_alloc(i64 noundef 512), !dbg !49
  store ptr %call, ptr %gpa_mem, align 8, !dbg !48
  %0 = load ptr, ptr %gpa_mem, align 8, !dbg !50
  %1 = load ptr, ptr %gpa_mem, align 8, !dbg !50
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !50
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 52, i64 noundef 512, i64 noundef %2) #5, !dbg !50
  %3 = load ptr, ptr %gpa_mem, align 8, !dbg !51
  call void @GeneralPoolAllocator_free(ptr noundef %3, i64 noundef 512), !dbg !52
    #dbg_declare(ptr %page_mem, !53, !DIExpression(), !54)
  %call2 = call ptr @PageAllocator_alloc(i64 noundef 16384), !dbg !55
  store ptr %call2, ptr %page_mem, align 8, !dbg !54
  %4 = load ptr, ptr %page_mem, align 8, !dbg !56
  %5 = load ptr, ptr %page_mem, align 8, !dbg !56
  %6 = call i64 @llvm.objectsize.i64.p0(ptr %5, i1 false, i1 true, i1 false), !dbg !56
  %call3 = call ptr @__memset_chk(ptr noundef %4, i32 noundef 86, i64 noundef 16384, i64 noundef %6) #5, !dbg !56
  %7 = load ptr, ptr %page_mem, align 8, !dbg !57
  call void @PageAllocator_free(ptr noundef %7), !dbg !58
  ret void, !dbg !59
}

declare ptr @GeneralPoolAllocator_alloc(i64 noundef) #1

declare void @GeneralPoolAllocator_free(ptr noundef, i64 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc6_arena_leak() #0 !dbg !60 {
entry:
  %arena = alloca ptr, align 8
  %item1 = alloca ptr, align 8
  %item2 = alloca ptr, align 8
  %item3 = alloca ptr, align 8
    #dbg_declare(ptr %arena, !61, !DIExpression(), !62)
  store ptr null, ptr %arena, align 8, !dbg !62
    #dbg_declare(ptr %item1, !63, !DIExpression(), !64)
  %0 = load ptr, ptr %arena, align 8, !dbg !65
  %call = call ptr @ArenaAllocator_alloc(ptr noundef %0, i64 noundef 256), !dbg !66
  store ptr %call, ptr %item1, align 8, !dbg !64
    #dbg_declare(ptr %item2, !67, !DIExpression(), !68)
  %1 = load ptr, ptr %arena, align 8, !dbg !69
  %call1 = call ptr @ArenaAllocator_alloc(ptr noundef %1, i64 noundef 512), !dbg !70
  store ptr %call1, ptr %item2, align 8, !dbg !68
    #dbg_declare(ptr %item3, !71, !DIExpression(), !72)
  %2 = load ptr, ptr %arena, align 8, !dbg !73
  %call2 = call ptr @ArenaAllocator_alloc(ptr noundef %2, i64 noundef 1024), !dbg !74
  store ptr %call2, ptr %item3, align 8, !dbg !72
  %3 = load ptr, ptr %item1, align 8, !dbg !75
  %4 = load ptr, ptr %item1, align 8, !dbg !75
  %5 = call i64 @llvm.objectsize.i64.p0(ptr %4, i1 false, i1 true, i1 false), !dbg !75
  %call3 = call ptr @__memset_chk(ptr noundef %3, i32 noundef 120, i64 noundef 256, i64 noundef %5) #5, !dbg !75
  %6 = load ptr, ptr %item2, align 8, !dbg !76
  %7 = load ptr, ptr %item2, align 8, !dbg !76
  %8 = call i64 @llvm.objectsize.i64.p0(ptr %7, i1 false, i1 true, i1 false), !dbg !76
  %call4 = call ptr @__memset_chk(ptr noundef %6, i32 noundef 121, i64 noundef 512, i64 noundef %8) #5, !dbg !76
  %9 = load ptr, ptr %item3, align 8, !dbg !77
  %10 = load ptr, ptr %item3, align 8, !dbg !77
  %11 = call i64 @llvm.objectsize.i64.p0(ptr %10, i1 false, i1 true, i1 false), !dbg !77
  %call5 = call ptr @__memset_chk(ptr noundef %9, i32 noundef 122, i64 noundef 1024, i64 noundef %11) #5, !dbg !77
  ret void, !dbg !78
}

declare ptr @ArenaAllocator_alloc(ptr noundef, i64 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc7_mixed_allocator_chaos() #0 !dbg !79 {
entry:
  %gpa_buf = alloca ptr, align 8
  %c_bridge = alloca ptr, align 8
  %shm_buf = alloca ptr, align 8
  %zig_buf = alloca ptr, align 8
    #dbg_declare(ptr %gpa_buf, !80, !DIExpression(), !81)
  %call = call ptr @GeneralPoolAllocator_alloc(i64 noundef 1024), !dbg !82
  store ptr %call, ptr %gpa_buf, align 8, !dbg !81
    #dbg_declare(ptr %c_bridge, !83, !DIExpression(), !84)
  %call1 = call ptr @malloc(i64 noundef 2048) #6, !dbg !85
  store ptr %call1, ptr %c_bridge, align 8, !dbg !84
    #dbg_declare(ptr %shm_buf, !86, !DIExpression(), !87)
  %call2 = call ptr @PageAllocator_alloc(i64 noundef 4096), !dbg !88
  store ptr %call2, ptr %shm_buf, align 8, !dbg !87
    #dbg_declare(ptr %zig_buf, !89, !DIExpression(), !90)
  %call3 = call ptr @zig_alloc(i64 noundef 512), !dbg !91
  store ptr %call3, ptr %zig_buf, align 8, !dbg !90
  %0 = load ptr, ptr %gpa_buf, align 8, !dbg !92
  %1 = load ptr, ptr %gpa_buf, align 8, !dbg !92
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !92
  %call4 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 170, i64 noundef 1024, i64 noundef %2) #5, !dbg !92
  %3 = load ptr, ptr %c_bridge, align 8, !dbg !93
  %4 = load ptr, ptr %c_bridge, align 8, !dbg !93
  %5 = call i64 @llvm.objectsize.i64.p0(ptr %4, i1 false, i1 true, i1 false), !dbg !93
  %call5 = call ptr @__memset_chk(ptr noundef %3, i32 noundef 187, i64 noundef 2048, i64 noundef %5) #5, !dbg !93
  %6 = load ptr, ptr %shm_buf, align 8, !dbg !94
  %7 = load ptr, ptr %shm_buf, align 8, !dbg !94
  %8 = call i64 @llvm.objectsize.i64.p0(ptr %7, i1 false, i1 true, i1 false), !dbg !94
  %call6 = call ptr @__memset_chk(ptr noundef %6, i32 noundef 204, i64 noundef 4096, i64 noundef %8) #5, !dbg !94
  %9 = load ptr, ptr %zig_buf, align 8, !dbg !95
  %10 = load ptr, ptr %zig_buf, align 8, !dbg !95
  %11 = call i64 @llvm.objectsize.i64.p0(ptr %10, i1 false, i1 true, i1 false), !dbg !95
  %call7 = call ptr @__memset_chk(ptr noundef %9, i32 noundef 221, i64 noundef 512, i64 noundef %11) #5, !dbg !95
  %12 = load ptr, ptr %gpa_buf, align 8, !dbg !96
  call void @free(ptr noundef %12), !dbg !97
  %13 = load ptr, ptr %c_bridge, align 8, !dbg !98
  call void @PageAllocator_free(ptr noundef %13), !dbg !99
  %14 = load ptr, ptr %shm_buf, align 8, !dbg !100
  call void @__zig_dealloc(ptr noundef %14, i64 noundef 4096), !dbg !101
  %15 = load ptr, ptr %zig_buf, align 8, !dbg !102
  call void @GeneralPoolAllocator_free(ptr noundef %15, i64 noundef 512), !dbg !103
  ret void, !dbg !104
}

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
!1 = !DIFile(filename: "corpus/red_team_test/zig_cimport_ffi_bugs.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "02725da1e28b6641e0f1984f333ef47c")
!2 = !{!3}
!3 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!4 = !{i32 7, !"Dwarf Version", i32 5}
!5 = !{i32 2, !"Debug Info Version", i32 3}
!6 = !{i32 1, !"wchar_size", i32 4}
!7 = !{i32 8, !"PIC Level", i32 2}
!8 = !{i32 7, !"uwtable", i32 1}
!9 = !{i32 7, !"frame-pointer", i32 1}
!10 = !{!"Homebrew clang version 21.1.8"}
!11 = distinct !DISubprogram(name: "tc1_zig_alloc_c_free", scope: !1, file: !1, line: 37, type: !12, scopeLine: 37, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!12 = !DISubroutineType(types: !13)
!13 = !{null}
!14 = !{}
!15 = !DILocalVariable(name: "zig_mem", scope: !11, file: !1, line: 38, type: !3)
!16 = !DILocation(line: 38, column: 11, scope: !11)
!17 = !DILocation(line: 38, column: 21, scope: !11)
!18 = !DILocation(line: 39, column: 5, scope: !11)
!19 = !DILocation(line: 43, column: 10, scope: !11)
!20 = !DILocation(line: 43, column: 5, scope: !11)
!21 = !DILocation(line: 44, column: 1, scope: !11)
!22 = distinct !DISubprogram(name: "tc2_c_malloc_zig_dealloc", scope: !1, file: !1, line: 53, type: !12, scopeLine: 53, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!23 = !DILocalVariable(name: "c_mem", scope: !22, file: !1, line: 54, type: !3)
!24 = !DILocation(line: 54, column: 11, scope: !22)
!25 = !DILocation(line: 54, column: 19, scope: !22)
!26 = !DILocation(line: 55, column: 5, scope: !22)
!27 = !DILocation(line: 59, column: 19, scope: !22)
!28 = !DILocation(line: 59, column: 5, scope: !22)
!29 = !DILocation(line: 60, column: 1, scope: !22)
!30 = distinct !DISubprogram(name: "tc3_pagealloc_c_free", scope: !1, file: !1, line: 69, type: !12, scopeLine: 69, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!31 = !DILocalVariable(name: "page_mem", scope: !30, file: !1, line: 70, type: !3)
!32 = !DILocation(line: 70, column: 11, scope: !30)
!33 = !DILocation(line: 70, column: 22, scope: !30)
!34 = !DILocation(line: 71, column: 5, scope: !30)
!35 = !DILocation(line: 75, column: 10, scope: !30)
!36 = !DILocation(line: 75, column: 5, scope: !30)
!37 = !DILocation(line: 76, column: 1, scope: !30)
!38 = distinct !DISubprogram(name: "tc4_c_malloc_pagefree", scope: !1, file: !1, line: 85, type: !12, scopeLine: 85, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!39 = !DILocalVariable(name: "c_mem", scope: !38, file: !1, line: 86, type: !3)
!40 = !DILocation(line: 86, column: 11, scope: !38)
!41 = !DILocation(line: 86, column: 19, scope: !38)
!42 = !DILocation(line: 87, column: 5, scope: !38)
!43 = !DILocation(line: 91, column: 24, scope: !38)
!44 = !DILocation(line: 91, column: 5, scope: !38)
!45 = !DILocation(line: 92, column: 1, scope: !38)
!46 = distinct !DISubprogram(name: "tc5_correct_zig_memory", scope: !1, file: !1, line: 101, type: !12, scopeLine: 101, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!47 = !DILocalVariable(name: "gpa_mem", scope: !46, file: !1, line: 103, type: !3)
!48 = !DILocation(line: 103, column: 11, scope: !46)
!49 = !DILocation(line: 103, column: 21, scope: !46)
!50 = !DILocation(line: 104, column: 5, scope: !46)
!51 = !DILocation(line: 108, column: 31, scope: !46)
!52 = !DILocation(line: 108, column: 5, scope: !46)
!53 = !DILocalVariable(name: "page_mem", scope: !46, file: !1, line: 111, type: !3)
!54 = !DILocation(line: 111, column: 11, scope: !46)
!55 = !DILocation(line: 111, column: 22, scope: !46)
!56 = !DILocation(line: 112, column: 5, scope: !46)
!57 = !DILocation(line: 114, column: 24, scope: !46)
!58 = !DILocation(line: 114, column: 5, scope: !46)
!59 = !DILocation(line: 115, column: 1, scope: !46)
!60 = distinct !DISubprogram(name: "tc6_arena_leak", scope: !1, file: !1, line: 124, type: !12, scopeLine: 124, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!61 = !DILocalVariable(name: "arena", scope: !60, file: !1, line: 125, type: !3)
!62 = !DILocation(line: 125, column: 11, scope: !60)
!63 = !DILocalVariable(name: "item1", scope: !60, file: !1, line: 128, type: !3)
!64 = !DILocation(line: 128, column: 11, scope: !60)
!65 = !DILocation(line: 128, column: 40, scope: !60)
!66 = !DILocation(line: 128, column: 19, scope: !60)
!67 = !DILocalVariable(name: "item2", scope: !60, file: !1, line: 129, type: !3)
!68 = !DILocation(line: 129, column: 11, scope: !60)
!69 = !DILocation(line: 129, column: 40, scope: !60)
!70 = !DILocation(line: 129, column: 19, scope: !60)
!71 = !DILocalVariable(name: "item3", scope: !60, file: !1, line: 130, type: !3)
!72 = !DILocation(line: 130, column: 11, scope: !60)
!73 = !DILocation(line: 130, column: 40, scope: !60)
!74 = !DILocation(line: 130, column: 19, scope: !60)
!75 = !DILocation(line: 132, column: 5, scope: !60)
!76 = !DILocation(line: 133, column: 5, scope: !60)
!77 = !DILocation(line: 134, column: 5, scope: !60)
!78 = !DILocation(line: 138, column: 1, scope: !60)
!79 = distinct !DISubprogram(name: "tc7_mixed_allocator_chaos", scope: !1, file: !1, line: 148, type: !12, scopeLine: 148, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !14)
!80 = !DILocalVariable(name: "gpa_buf", scope: !79, file: !1, line: 150, type: !3)
!81 = !DILocation(line: 150, column: 11, scope: !79)
!82 = !DILocation(line: 150, column: 21, scope: !79)
!83 = !DILocalVariable(name: "c_bridge", scope: !79, file: !1, line: 153, type: !3)
!84 = !DILocation(line: 153, column: 11, scope: !79)
!85 = !DILocation(line: 153, column: 22, scope: !79)
!86 = !DILocalVariable(name: "shm_buf", scope: !79, file: !1, line: 156, type: !3)
!87 = !DILocation(line: 156, column: 11, scope: !79)
!88 = !DILocation(line: 156, column: 21, scope: !79)
!89 = !DILocalVariable(name: "zig_buf", scope: !79, file: !1, line: 159, type: !3)
!90 = !DILocation(line: 159, column: 11, scope: !79)
!91 = !DILocation(line: 159, column: 21, scope: !79)
!92 = !DILocation(line: 162, column: 5, scope: !79)
!93 = !DILocation(line: 163, column: 5, scope: !79)
!94 = !DILocation(line: 164, column: 5, scope: !79)
!95 = !DILocation(line: 165, column: 5, scope: !79)
!96 = !DILocation(line: 168, column: 10, scope: !79)
!97 = !DILocation(line: 168, column: 5, scope: !79)
!98 = !DILocation(line: 169, column: 24, scope: !79)
!99 = !DILocation(line: 169, column: 5, scope: !79)
!100 = !DILocation(line: 170, column: 19, scope: !79)
!101 = !DILocation(line: 170, column: 5, scope: !79)
!102 = !DILocation(line: 171, column: 31, scope: !79)
!103 = !DILocation(line: 171, column: 5, scope: !79)
!104 = !DILocation(line: 172, column: 1, scope: !79)
