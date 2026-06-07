; ModuleID = 'corpus/red_team_test/rust_multi_lang_ffi_bugs.c'
source_filename = "corpus/red_team_test/rust_multi_lang_ffi_bugs.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc1_rust_alloc_c_free() #0 !dbg !9 {
entry:
  %rust_mem = alloca ptr, align 8
    #dbg_declare(ptr %rust_mem, !13, !DIExpression(), !15)
  %call = call ptr @__rust_alloc(i64 noundef 1024, i64 noundef 8), !dbg !16
  store ptr %call, ptr %rust_mem, align 8, !dbg !15
  %0 = load ptr, ptr %rust_mem, align 8, !dbg !17
  %1 = load ptr, ptr %rust_mem, align 8, !dbg !17
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !17
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 222, i64 noundef 1024, i64 noundef %2) #5, !dbg !17
  %3 = load ptr, ptr %rust_mem, align 8, !dbg !18
  call void @free(ptr noundef %3), !dbg !19
  ret void, !dbg !20
}

declare ptr @__rust_alloc(i64 noundef, i64 noundef) #1

; Function Attrs: nounwind
declare ptr @__memset_chk(ptr noundef, i32 noundef, i64 noundef, i64 noundef) #2

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.objectsize.i64.p0(ptr, i1 immarg, i1 immarg, i1 immarg) #3

declare void @free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc2_c_malloc_rust_dealloc() #0 !dbg !21 {
entry:
  %c_mem = alloca ptr, align 8
    #dbg_declare(ptr %c_mem, !22, !DIExpression(), !23)
  %call = call ptr @malloc(i64 noundef 2048) #6, !dbg !24
  store ptr %call, ptr %c_mem, align 8, !dbg !23
  %0 = load ptr, ptr %c_mem, align 8, !dbg !25
  %1 = load ptr, ptr %c_mem, align 8, !dbg !25
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !25
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 173, i64 noundef 2048, i64 noundef %2) #5, !dbg !25
  %3 = load ptr, ptr %c_mem, align 8, !dbg !26
  call void @__rust_dealloc(ptr noundef %3, i64 noundef 2048, i64 noundef 1), !dbg !27
  ret void, !dbg !28
}

; Function Attrs: allocsize(0)
declare ptr @malloc(i64 noundef) #4

declare void @__rust_dealloc(ptr noundef, i64 noundef, i64 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc3_rust_alloc_csharp_free() #0 !dbg !29 {
entry:
  %rust_obj = alloca ptr, align 8
    #dbg_declare(ptr %rust_obj, !30, !DIExpression(), !31)
  %call = call ptr @__rust_alloc(i64 noundef 4096, i64 noundef 16), !dbg !32
  store ptr %call, ptr %rust_obj, align 8, !dbg !31
  %0 = load ptr, ptr %rust_obj, align 8, !dbg !33
  %1 = load ptr, ptr %rust_obj, align 8, !dbg !33
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !33
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 66, i64 noundef 4096, i64 noundef %2) #5, !dbg !33
  %3 = load ptr, ptr %rust_obj, align 8, !dbg !34
  call void @Marshal_FreeHGlobal(ptr noundef %3), !dbg !35
  ret void, !dbg !36
}

declare void @Marshal_FreeHGlobal(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc4_csharp_alloc_rust_free() #0 !dbg !37 {
entry:
  %com_mem = alloca ptr, align 8
    #dbg_declare(ptr %com_mem, !38, !DIExpression(), !39)
  %call = call ptr @Marshal_AllocHGlobal(i32 noundef 8192), !dbg !40
  store ptr %call, ptr %com_mem, align 8, !dbg !39
  %0 = load ptr, ptr %com_mem, align 8, !dbg !41
  %1 = load ptr, ptr %com_mem, align 8, !dbg !41
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !41
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 119, i64 noundef 8192, i64 noundef %2) #5, !dbg !41
  %3 = load ptr, ptr %com_mem, align 8, !dbg !42
  call void @__rust_dealloc(ptr noundef %3, i64 noundef 8192, i64 noundef 16), !dbg !43
  ret void, !dbg !44
}

declare ptr @Marshal_AllocHGlobal(i32 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc5_correct_rust_memory() #0 !dbg !45 {
entry:
  %data = alloca ptr, align 8
  %aligned = alloca ptr, align 8
    #dbg_declare(ptr %data, !46, !DIExpression(), !47)
  %call = call ptr @__rust_alloc(i64 noundef 512, i64 noundef 8), !dbg !48
  store ptr %call, ptr %data, align 8, !dbg !47
  %0 = load ptr, ptr %data, align 8, !dbg !49
  %1 = load ptr, ptr %data, align 8, !dbg !49
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !49
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 82, i64 noundef 512, i64 noundef %2) #5, !dbg !49
  %3 = load ptr, ptr %data, align 8, !dbg !50
  call void @__rust_dealloc(ptr noundef %3, i64 noundef 512, i64 noundef 8), !dbg !51
    #dbg_declare(ptr %aligned, !52, !DIExpression(), !53)
  %call2 = call ptr @__rust_alloc(i64 noundef 1024, i64 noundef 32), !dbg !54
  store ptr %call2, ptr %aligned, align 8, !dbg !53
  %4 = load ptr, ptr %aligned, align 8, !dbg !55
  %5 = load ptr, ptr %aligned, align 8, !dbg !55
  %6 = call i64 @llvm.objectsize.i64.p0(ptr %5, i1 false, i1 true, i1 false), !dbg !55
  %call3 = call ptr @__memset_chk(ptr noundef %4, i32 noundef 0, i64 noundef 1024, i64 noundef %6) #5, !dbg !55
  %7 = load ptr, ptr %aligned, align 8, !dbg !56
  call void @__rust_dealloc(ptr noundef %7, i64 noundef 1024, i64 noundef 32), !dbg !57
  ret void, !dbg !58
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc6_box_leak_ownership_transfer() #0 !dbg !59 {
entry:
  %leaked = alloca ptr, align 8
    #dbg_declare(ptr %leaked, !60, !DIExpression(), !61)
  %call = call ptr @__rust_alloc(i64 noundef 256, i64 noundef 8), !dbg !62
  store ptr %call, ptr %leaked, align 8, !dbg !61
  %0 = load ptr, ptr %leaked, align 8, !dbg !63
  %1 = load ptr, ptr %leaked, align 8, !dbg !63
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !63
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 255, i64 noundef 256, i64 noundef %2) #5, !dbg !63
  %3 = load ptr, ptr %leaked, align 8, !dbg !64
  call void @free(ptr noundef %3), !dbg !65
  ret void, !dbg !66
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @tc7_triple_lang_chaos() #0 !dbg !67 {
entry:
  %rust_core = alloca ptr, align 8
  %c_io_buf = alloca ptr, align 8
  %net_ui = alloca ptr, align 8
  %rust_cache = alloca ptr, align 8
    #dbg_declare(ptr %rust_core, !68, !DIExpression(), !69)
  %call = call ptr @__rust_alloc(i64 noundef 16384, i64 noundef 16), !dbg !70
  store ptr %call, ptr %rust_core, align 8, !dbg !69
    #dbg_declare(ptr %c_io_buf, !71, !DIExpression(), !72)
  %call1 = call ptr @malloc(i64 noundef 8192) #6, !dbg !73
  store ptr %call1, ptr %c_io_buf, align 8, !dbg !72
    #dbg_declare(ptr %net_ui, !74, !DIExpression(), !75)
  %call2 = call ptr @Marshal_AllocHGlobal(i32 noundef 4096), !dbg !76
  store ptr %call2, ptr %net_ui, align 8, !dbg !75
    #dbg_declare(ptr %rust_cache, !77, !DIExpression(), !78)
  %call3 = call ptr @__rust_alloc(i64 noundef 32768, i64 noundef 64), !dbg !79
  store ptr %call3, ptr %rust_cache, align 8, !dbg !78
  %0 = load ptr, ptr %rust_core, align 8, !dbg !80
  %1 = load ptr, ptr %rust_core, align 8, !dbg !80
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !80
  %call4 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 17, i64 noundef 16384, i64 noundef %2) #5, !dbg !80
  %3 = load ptr, ptr %c_io_buf, align 8, !dbg !81
  %4 = load ptr, ptr %c_io_buf, align 8, !dbg !81
  %5 = call i64 @llvm.objectsize.i64.p0(ptr %4, i1 false, i1 true, i1 false), !dbg !81
  %call5 = call ptr @__memset_chk(ptr noundef %3, i32 noundef 34, i64 noundef 8192, i64 noundef %5) #5, !dbg !81
  %6 = load ptr, ptr %net_ui, align 8, !dbg !82
  %7 = load ptr, ptr %net_ui, align 8, !dbg !82
  %8 = call i64 @llvm.objectsize.i64.p0(ptr %7, i1 false, i1 true, i1 false), !dbg !82
  %call6 = call ptr @__memset_chk(ptr noundef %6, i32 noundef 51, i64 noundef 4096, i64 noundef %8) #5, !dbg !82
  %9 = load ptr, ptr %rust_cache, align 8, !dbg !83
  %10 = load ptr, ptr %rust_cache, align 8, !dbg !83
  %11 = call i64 @llvm.objectsize.i64.p0(ptr %10, i1 false, i1 true, i1 false), !dbg !83
  %call7 = call ptr @__memset_chk(ptr noundef %9, i32 noundef 68, i64 noundef 32768, i64 noundef %11) #5, !dbg !83
  %12 = load ptr, ptr %rust_core, align 8, !dbg !84
  call void @free(ptr noundef %12), !dbg !85
  %13 = load ptr, ptr %c_io_buf, align 8, !dbg !86
  call void @__rust_dealloc(ptr noundef %13, i64 noundef 8192, i64 noundef 1), !dbg !87
  %14 = load ptr, ptr %net_ui, align 8, !dbg !88
  call void @__rust_dealloc(ptr noundef %14, i64 noundef 4096, i64 noundef 16), !dbg !89
  %15 = load ptr, ptr %rust_cache, align 8, !dbg !90
  call void @Marshal_FreeHGlobal(ptr noundef %15), !dbg !91
  ret void, !dbg !92
}

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #4 = { allocsize(0) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #5 = { nounwind }
attributes #6 = { allocsize(0) }

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!2, !3, !4, !5, !6, !7}
!llvm.ident = !{!8}

!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "Homebrew clang version 21.1.8", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, splitDebugInlining: false, nameTableKind: Apple, sysroot: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk", sdk: "MacOSX15.sdk")
!1 = !DIFile(filename: "corpus/red_team_test/rust_multi_lang_ffi_bugs.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "9ab1351b9ed0c64c0dcefbb2c40c969b")
!2 = !{i32 7, !"Dwarf Version", i32 5}
!3 = !{i32 2, !"Debug Info Version", i32 3}
!4 = !{i32 1, !"wchar_size", i32 4}
!5 = !{i32 8, !"PIC Level", i32 2}
!6 = !{i32 7, !"uwtable", i32 1}
!7 = !{i32 7, !"frame-pointer", i32 1}
!8 = !{!"Homebrew clang version 21.1.8"}
!9 = distinct !DISubprogram(name: "tc1_rust_alloc_c_free", scope: !1, file: !1, line: 36, type: !10, scopeLine: 36, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !12)
!10 = !DISubroutineType(types: !11)
!11 = !{null}
!12 = !{}
!13 = !DILocalVariable(name: "rust_mem", scope: !9, file: !1, line: 37, type: !14)
!14 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!15 = !DILocation(line: 37, column: 11, scope: !9)
!16 = !DILocation(line: 37, column: 22, scope: !9)
!17 = !DILocation(line: 38, column: 5, scope: !9)
!18 = !DILocation(line: 42, column: 10, scope: !9)
!19 = !DILocation(line: 42, column: 5, scope: !9)
!20 = !DILocation(line: 43, column: 1, scope: !9)
!21 = distinct !DISubprogram(name: "tc2_c_malloc_rust_dealloc", scope: !1, file: !1, line: 52, type: !10, scopeLine: 52, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !12)
!22 = !DILocalVariable(name: "c_mem", scope: !21, file: !1, line: 53, type: !14)
!23 = !DILocation(line: 53, column: 11, scope: !21)
!24 = !DILocation(line: 53, column: 19, scope: !21)
!25 = !DILocation(line: 54, column: 5, scope: !21)
!26 = !DILocation(line: 58, column: 20, scope: !21)
!27 = !DILocation(line: 58, column: 5, scope: !21)
!28 = !DILocation(line: 59, column: 1, scope: !21)
!29 = distinct !DISubprogram(name: "tc3_rust_alloc_csharp_free", scope: !1, file: !1, line: 68, type: !10, scopeLine: 68, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !12)
!30 = !DILocalVariable(name: "rust_obj", scope: !29, file: !1, line: 69, type: !14)
!31 = !DILocation(line: 69, column: 11, scope: !29)
!32 = !DILocation(line: 69, column: 22, scope: !29)
!33 = !DILocation(line: 70, column: 5, scope: !29)
!34 = !DILocation(line: 74, column: 25, scope: !29)
!35 = !DILocation(line: 74, column: 5, scope: !29)
!36 = !DILocation(line: 75, column: 1, scope: !29)
!37 = distinct !DISubprogram(name: "tc4_csharp_alloc_rust_free", scope: !1, file: !1, line: 84, type: !10, scopeLine: 84, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !12)
!38 = !DILocalVariable(name: "com_mem", scope: !37, file: !1, line: 85, type: !14)
!39 = !DILocation(line: 85, column: 11, scope: !37)
!40 = !DILocation(line: 85, column: 21, scope: !37)
!41 = !DILocation(line: 86, column: 5, scope: !37)
!42 = !DILocation(line: 90, column: 20, scope: !37)
!43 = !DILocation(line: 90, column: 5, scope: !37)
!44 = !DILocation(line: 91, column: 1, scope: !37)
!45 = distinct !DISubprogram(name: "tc5_correct_rust_memory", scope: !1, file: !1, line: 100, type: !10, scopeLine: 100, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !12)
!46 = !DILocalVariable(name: "data", scope: !45, file: !1, line: 102, type: !14)
!47 = !DILocation(line: 102, column: 11, scope: !45)
!48 = !DILocation(line: 102, column: 18, scope: !45)
!49 = !DILocation(line: 103, column: 5, scope: !45)
!50 = !DILocation(line: 107, column: 20, scope: !45)
!51 = !DILocation(line: 107, column: 5, scope: !45)
!52 = !DILocalVariable(name: "aligned", scope: !45, file: !1, line: 110, type: !14)
!53 = !DILocation(line: 110, column: 11, scope: !45)
!54 = !DILocation(line: 110, column: 21, scope: !45)
!55 = !DILocation(line: 111, column: 5, scope: !45)
!56 = !DILocation(line: 113, column: 20, scope: !45)
!57 = !DILocation(line: 113, column: 5, scope: !45)
!58 = !DILocation(line: 114, column: 1, scope: !45)
!59 = distinct !DISubprogram(name: "tc6_box_leak_ownership_transfer", scope: !1, file: !1, line: 124, type: !10, scopeLine: 124, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !12)
!60 = !DILocalVariable(name: "leaked", scope: !59, file: !1, line: 127, type: !14)
!61 = !DILocation(line: 127, column: 11, scope: !59)
!62 = !DILocation(line: 127, column: 20, scope: !59)
!63 = !DILocation(line: 128, column: 5, scope: !59)
!64 = !DILocation(line: 131, column: 10, scope: !59)
!65 = !DILocation(line: 131, column: 5, scope: !59)
!66 = !DILocation(line: 133, column: 1, scope: !59)
!67 = distinct !DISubprogram(name: "tc7_triple_lang_chaos", scope: !1, file: !1, line: 142, type: !10, scopeLine: 142, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !12)
!68 = !DILocalVariable(name: "rust_core", scope: !67, file: !1, line: 144, type: !14)
!69 = !DILocation(line: 144, column: 11, scope: !67)
!70 = !DILocation(line: 144, column: 23, scope: !67)
!71 = !DILocalVariable(name: "c_io_buf", scope: !67, file: !1, line: 147, type: !14)
!72 = !DILocation(line: 147, column: 11, scope: !67)
!73 = !DILocation(line: 147, column: 22, scope: !67)
!74 = !DILocalVariable(name: "net_ui", scope: !67, file: !1, line: 150, type: !14)
!75 = !DILocation(line: 150, column: 11, scope: !67)
!76 = !DILocation(line: 150, column: 20, scope: !67)
!77 = !DILocalVariable(name: "rust_cache", scope: !67, file: !1, line: 153, type: !14)
!78 = !DILocation(line: 153, column: 11, scope: !67)
!79 = !DILocation(line: 153, column: 24, scope: !67)
!80 = !DILocation(line: 156, column: 5, scope: !67)
!81 = !DILocation(line: 157, column: 5, scope: !67)
!82 = !DILocation(line: 158, column: 5, scope: !67)
!83 = !DILocation(line: 159, column: 5, scope: !67)
!84 = !DILocation(line: 162, column: 10, scope: !67)
!85 = !DILocation(line: 162, column: 5, scope: !67)
!86 = !DILocation(line: 163, column: 20, scope: !67)
!87 = !DILocation(line: 163, column: 5, scope: !67)
!88 = !DILocation(line: 164, column: 20, scope: !67)
!89 = !DILocation(line: 164, column: 5, scope: !67)
!90 = !DILocation(line: 165, column: 25, scope: !67)
!91 = !DILocation(line: 165, column: 5, scope: !67)
!92 = !DILocation(line: 166, column: 1, scope: !67)
