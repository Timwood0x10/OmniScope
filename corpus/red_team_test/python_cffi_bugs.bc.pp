; ModuleID = './corpus/red_team_test/python_cffi_bugs.c'
source_filename = "./corpus/red_team_test/python_cffi_bugs.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

@.str = private unnamed_addr constant [6 x i8] c"hello\00", align 1, !dbg !0
@.str.1 = private unnamed_addr constant [11 x i8] c"bytes: %s\0A\00", align 1, !dbg !7
@.str.2 = private unnamed_addr constant [10 x i8] c"temporary\00", align 1, !dbg !12
@.str.3 = private unnamed_addr constant [11 x i8] c"freed: %s\0A\00", align 1, !dbg !17
@.str.4 = private unnamed_addr constant [12 x i8] c"val1 = %ld\0A\00", align 1, !dbg !19
@g_cached_py_obj = internal global ptr null, align 8, !dbg !24
@.str.5 = private unnamed_addr constant [13 x i8] c"cached: %ld\0A\00", align 1, !dbg !31
@.str.6 = private unnamed_addr constant [5 x i8] c"data\00", align 1, !dbg !36
@.str.7 = private unnamed_addr constant [9 x i8] c"__call__\00", align 1, !dbg !41

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @py_01_borrowed_ref_decref(ptr noundef %list) #0 !dbg !60 {
entry:
  %list.addr = alloca ptr, align 8
  %item = alloca ptr, align 8
  store ptr %list, ptr %list.addr, align 8
    #dbg_declare(ptr %list.addr, !64, !DIExpression(), !65)
    #dbg_declare(ptr %item, !66, !DIExpression(), !67)
  %0 = load ptr, ptr %list.addr, align 8, !dbg !68
  %call = call ptr @PyList_GetItem(ptr noundef %0, i32 noundef 0), !dbg !69
  store ptr %call, ptr %item, align 8, !dbg !67
  %1 = load ptr, ptr %item, align 8, !dbg !70
  call void @Py_DECREF(ptr noundef %1), !dbg !71
  ret void, !dbg !72
}

declare ptr @PyList_GetItem(ptr noundef, i32 noundef) #1

declare void @Py_DECREF(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @py_02_new_ref_leak() #0 !dbg !73 {
entry:
  %bytes = alloca ptr, align 8
  %data = alloca ptr, align 8
    #dbg_declare(ptr %bytes, !76, !DIExpression(), !77)
  %call = call ptr @PyBytes_FromStringAndSize(ptr noundef @.str, i32 noundef 5), !dbg !78
  store ptr %call, ptr %bytes, align 8, !dbg !77
    #dbg_declare(ptr %data, !79, !DIExpression(), !81)
  %0 = load ptr, ptr %bytes, align 8, !dbg !82
  %call1 = call ptr @PyBytes_AsString(ptr noundef %0), !dbg !83
  store ptr %call1, ptr %data, align 8, !dbg !81
  %1 = load ptr, ptr %data, align 8, !dbg !84
  %call2 = call i32 (ptr, ...) @printf(ptr noundef @.str.1, ptr noundef %1), !dbg !85
  ret void, !dbg !86
}

declare ptr @PyBytes_FromStringAndSize(ptr noundef, i32 noundef) #1

declare ptr @PyBytes_AsString(ptr noundef) #1

declare i32 @printf(ptr noundef, ...) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @py_03_use_after_decref() #0 !dbg !87 {
entry:
  %bytes = alloca ptr, align 8
  %data = alloca ptr, align 8
    #dbg_declare(ptr %bytes, !88, !DIExpression(), !89)
  %call = call ptr @PyBytes_FromStringAndSize(ptr noundef @.str.2, i32 noundef 9), !dbg !90
  store ptr %call, ptr %bytes, align 8, !dbg !89
    #dbg_declare(ptr %data, !91, !DIExpression(), !92)
  %0 = load ptr, ptr %bytes, align 8, !dbg !93
  %call1 = call ptr @PyBytes_AsString(ptr noundef %0), !dbg !94
  store ptr %call1, ptr %data, align 8, !dbg !92
  %1 = load ptr, ptr %bytes, align 8, !dbg !95
  call void @Py_DECREF(ptr noundef %1), !dbg !96
  %2 = load ptr, ptr %data, align 8, !dbg !97
  %call2 = call i32 (ptr, ...) @printf(ptr noundef @.str.3, ptr noundef %2), !dbg !98
  ret void, !dbg !99
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @py_04_steal_ref_misuse() #0 !dbg !100 {
entry:
  %tuple = alloca ptr, align 8
  %val1 = alloca ptr, align 8
  %val2 = alloca ptr, align 8
  %v = alloca i64, align 8
    #dbg_declare(ptr %tuple, !101, !DIExpression(), !102)
  %call = call ptr @PyTuple_New(i32 noundef 2), !dbg !103
  store ptr %call, ptr %tuple, align 8, !dbg !102
    #dbg_declare(ptr %val1, !104, !DIExpression(), !105)
  %call1 = call ptr @PyLong_FromLong(i64 noundef 42), !dbg !106
  store ptr %call1, ptr %val1, align 8, !dbg !105
    #dbg_declare(ptr %val2, !107, !DIExpression(), !108)
  %call2 = call ptr @PyLong_FromLong(i64 noundef 99), !dbg !109
  store ptr %call2, ptr %val2, align 8, !dbg !108
  %0 = load ptr, ptr %tuple, align 8, !dbg !110
  %1 = load ptr, ptr %val1, align 8, !dbg !111
  %call3 = call i32 @PyTuple_SetItem(ptr noundef %0, i32 noundef 0, ptr noundef %1), !dbg !112
  %2 = load ptr, ptr %tuple, align 8, !dbg !113
  %3 = load ptr, ptr %val2, align 8, !dbg !114
  %call4 = call i32 @PyTuple_SetItem(ptr noundef %2, i32 noundef 1, ptr noundef %3), !dbg !115
    #dbg_declare(ptr %v, !116, !DIExpression(), !118)
  %4 = load ptr, ptr %val1, align 8, !dbg !119
  %call5 = call i32 @PyLong_AsLong(ptr noundef %4), !dbg !120
  %conv = sext i32 %call5 to i64, !dbg !120
  store i64 %conv, ptr %v, align 8, !dbg !118
  %5 = load i64, ptr %v, align 8, !dbg !121
  %call6 = call i32 (ptr, ...) @printf(ptr noundef @.str.4, i64 noundef %5), !dbg !122
  ret void, !dbg !123
}

declare ptr @PyTuple_New(i32 noundef) #1

declare ptr @PyLong_FromLong(i64 noundef) #1

declare i32 @PyTuple_SetItem(ptr noundef, i32 noundef, ptr noundef) #1

declare i32 @PyLong_AsLong(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @py_05_cache_no_incref(ptr noundef %obj) #0 !dbg !124 {
entry:
  %obj.addr = alloca ptr, align 8
  store ptr %obj, ptr %obj.addr, align 8
    #dbg_declare(ptr %obj.addr, !125, !DIExpression(), !126)
  %0 = load ptr, ptr %obj.addr, align 8, !dbg !127
  store ptr %0, ptr @g_cached_py_obj, align 8, !dbg !128
  ret void, !dbg !129
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @py_05_use_cached() #0 !dbg !130 {
entry:
  %val = alloca i64, align 8
  %0 = load ptr, ptr @g_cached_py_obj, align 8, !dbg !131
  %tobool = icmp ne ptr %0, null, !dbg !131
  br i1 %tobool, label %if.then, label %if.end, !dbg !131

if.then:                                          ; preds = %entry
    #dbg_declare(ptr %val, !133, !DIExpression(), !135)
  %1 = load ptr, ptr @g_cached_py_obj, align 8, !dbg !136
  %call = call i32 @PyLong_AsLong(ptr noundef %1), !dbg !137
  %conv = sext i32 %call to i64, !dbg !137
  store i64 %conv, ptr %val, align 8, !dbg !135
  %2 = load i64, ptr %val, align 8, !dbg !138
  %call1 = call i32 (ptr, ...) @printf(ptr noundef @.str.5, i64 noundef %2), !dbg !139
  br label %if.end, !dbg !140

if.end:                                           ; preds = %if.then, %entry
  ret void, !dbg !141
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @py_06_free_python_memory() #0 !dbg !142 {
entry:
  %bytes = alloca ptr, align 8
  %buf = alloca ptr, align 8
    #dbg_declare(ptr %bytes, !143, !DIExpression(), !144)
  %call = call ptr @PyBytes_FromStringAndSize(ptr noundef @.str.6, i32 noundef 4), !dbg !145
  store ptr %call, ptr %bytes, align 8, !dbg !144
    #dbg_declare(ptr %buf, !146, !DIExpression(), !147)
  %0 = load ptr, ptr %bytes, align 8, !dbg !148
  %call1 = call ptr @PyBytes_AsString(ptr noundef %0), !dbg !149
  store ptr %call1, ptr %buf, align 8, !dbg !147
  %1 = load ptr, ptr %buf, align 8, !dbg !150
  call void @free(ptr noundef %1), !dbg !151
  ret void, !dbg !152
}

declare void @free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @py_07_callback_no_gil(ptr noundef %callback) #0 !dbg !153 {
entry:
  %callback.addr = alloca ptr, align 8
  %result = alloca ptr, align 8
  store ptr %callback, ptr %callback.addr, align 8
    #dbg_declare(ptr %callback.addr, !154, !DIExpression(), !155)
    #dbg_declare(ptr %result, !156, !DIExpression(), !157)
  %0 = load ptr, ptr %callback.addr, align 8, !dbg !158
  %call = call ptr @PyObject_GetAttrString(ptr noundef %0, ptr noundef @.str.7), !dbg !159
  store ptr %call, ptr %result, align 8, !dbg !157
  %1 = load ptr, ptr %result, align 8, !dbg !160
  call void @Py_DECREF(ptr noundef %1), !dbg !161
  ret void, !dbg !162
}

declare ptr @PyObject_GetAttrString(ptr noundef, ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @py_08_ctypes_wrong_free() #0 !dbg !163 {
entry:
  %buf = alloca ptr, align 8
    #dbg_declare(ptr %buf, !164, !DIExpression(), !165)
  %call = call ptr @ctypes_alloc(i32 noundef 512), !dbg !166
  store ptr %call, ptr %buf, align 8, !dbg !165
  %0 = load ptr, ptr %buf, align 8, !dbg !167
  %1 = load ptr, ptr %buf, align 8, !dbg !167
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !167
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 0, i64 noundef 512, i64 noundef %2) #4, !dbg !167
  %3 = load ptr, ptr %buf, align 8, !dbg !168
  call void @free(ptr noundef %3), !dbg !169
  ret void, !dbg !170
}

declare ptr @ctypes_alloc(i32 noundef) #1

; Function Attrs: nounwind
declare ptr @__memset_chk(ptr noundef, i32 noundef, i64 noundef, i64 noundef) #2

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.objectsize.i64.p0(ptr, i1 immarg, i1 immarg, i1 immarg) #3

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #4 = { nounwind }

!llvm.dbg.cu = !{!26}
!llvm.module.flags = !{!53, !54, !55, !56, !57, !58}
!llvm.ident = !{!59}

!0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
!1 = distinct !DIGlobalVariable(scope: null, file: !2, line: 54, type: !3, isLocal: true, isDefinition: true)
!2 = !DIFile(filename: "./corpus/red_team_test/python_cffi_bugs.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "1356c36a71561bc08695f55b6314a1fe")
!3 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 48, elements: !5)
!4 = !DIBasicType(name: "char", size: 8, encoding: DW_ATE_signed_char)
!5 = !{!6}
!6 = !DISubrange(count: 6)
!7 = !DIGlobalVariableExpression(var: !8, expr: !DIExpression())
!8 = distinct !DIGlobalVariable(scope: null, file: !2, line: 56, type: !9, isLocal: true, isDefinition: true)
!9 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 88, elements: !10)
!10 = !{!11}
!11 = !DISubrange(count: 11)
!12 = !DIGlobalVariableExpression(var: !13, expr: !DIExpression())
!13 = distinct !DIGlobalVariable(scope: null, file: !2, line: 67, type: !14, isLocal: true, isDefinition: true)
!14 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 80, elements: !15)
!15 = !{!16}
!16 = !DISubrange(count: 10)
!17 = !DIGlobalVariableExpression(var: !18, expr: !DIExpression())
!18 = distinct !DIGlobalVariable(scope: null, file: !2, line: 73, type: !9, isLocal: true, isDefinition: true)
!19 = !DIGlobalVariableExpression(var: !20, expr: !DIExpression())
!20 = distinct !DIGlobalVariable(scope: null, file: !2, line: 93, type: !21, isLocal: true, isDefinition: true)
!21 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 96, elements: !22)
!22 = !{!23}
!23 = !DISubrange(count: 12)
!24 = !DIGlobalVariableExpression(var: !25, expr: !DIExpression())
!25 = distinct !DIGlobalVariable(name: "g_cached_py_obj", scope: !26, file: !2, line: 102, type: !46, isLocal: true, isDefinition: true)
!26 = distinct !DICompileUnit(language: DW_LANG_C11, file: !27, producer: "Homebrew clang version 21.1.8", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, retainedTypes: !28, globals: !30, splitDebugInlining: false, nameTableKind: Apple, sysroot: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk", sdk: "MacOSX15.sdk")
!27 = !DIFile(filename: "corpus/red_team_test/python_cffi_bugs.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "1356c36a71561bc08695f55b6314a1fe")
!28 = !{!29}
!29 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!30 = !{!0, !7, !12, !17, !19, !31, !36, !41, !24}
!31 = !DIGlobalVariableExpression(var: !32, expr: !DIExpression())
!32 = distinct !DIGlobalVariable(scope: null, file: !2, line: 113, type: !33, isLocal: true, isDefinition: true)
!33 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 104, elements: !34)
!34 = !{!35}
!35 = !DISubrange(count: 13)
!36 = !DIGlobalVariableExpression(var: !37, expr: !DIExpression())
!37 = distinct !DIGlobalVariable(scope: null, file: !2, line: 124, type: !38, isLocal: true, isDefinition: true)
!38 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 40, elements: !39)
!39 = !{!40}
!40 = !DISubrange(count: 5)
!41 = !DIGlobalVariableExpression(var: !42, expr: !DIExpression())
!42 = distinct !DIGlobalVariable(scope: null, file: !2, line: 144, type: !43, isLocal: true, isDefinition: true)
!43 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 72, elements: !44)
!44 = !{!45}
!45 = !DISubrange(count: 9)
!46 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !47, size: 64)
!47 = !DIDerivedType(tag: DW_TAG_typedef, name: "PyObject", file: !2, line: 16, baseType: !48)
!48 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "_object", file: !2, line: 16, size: 128, elements: !49)
!49 = !{!50, !52}
!50 = !DIDerivedType(tag: DW_TAG_member, name: "ob_refcnt", scope: !48, file: !2, line: 16, baseType: !51, size: 32)
!51 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!52 = !DIDerivedType(tag: DW_TAG_member, name: "ob_type", scope: !48, file: !2, line: 16, baseType: !29, size: 64, offset: 64)
!53 = !{i32 7, !"Dwarf Version", i32 5}
!54 = !{i32 2, !"Debug Info Version", i32 3}
!55 = !{i32 1, !"wchar_size", i32 4}
!56 = !{i32 8, !"PIC Level", i32 2}
!57 = !{i32 7, !"uwtable", i32 1}
!58 = !{i32 7, !"frame-pointer", i32 1}
!59 = !{!"Homebrew clang version 21.1.8"}
!60 = distinct !DISubprogram(name: "py_01_borrowed_ref_decref", scope: !2, file: !2, line: 40, type: !61, scopeLine: 40, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !26, retainedNodes: !63)
!61 = !DISubroutineType(types: !62)
!62 = !{null, !46}
!63 = !{}
!64 = !DILocalVariable(name: "list", arg: 1, scope: !60, file: !2, line: 40, type: !46)
!65 = !DILocation(line: 40, column: 42, scope: !60)
!66 = !DILocalVariable(name: "item", scope: !60, file: !2, line: 42, type: !46)
!67 = !DILocation(line: 42, column: 15, scope: !60)
!68 = !DILocation(line: 42, column: 37, scope: !60)
!69 = !DILocation(line: 42, column: 22, scope: !60)
!70 = !DILocation(line: 44, column: 15, scope: !60)
!71 = !DILocation(line: 44, column: 5, scope: !60)
!72 = !DILocation(line: 45, column: 1, scope: !60)
!73 = distinct !DISubprogram(name: "py_02_new_ref_leak", scope: !2, file: !2, line: 53, type: !74, scopeLine: 53, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !26, retainedNodes: !63)
!74 = !DISubroutineType(types: !75)
!75 = !{null}
!76 = !DILocalVariable(name: "bytes", scope: !73, file: !2, line: 54, type: !46)
!77 = !DILocation(line: 54, column: 15, scope: !73)
!78 = !DILocation(line: 54, column: 23, scope: !73)
!79 = !DILocalVariable(name: "data", scope: !73, file: !2, line: 55, type: !80)
!80 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !4, size: 64)
!81 = !DILocation(line: 55, column: 11, scope: !73)
!82 = !DILocation(line: 55, column: 35, scope: !73)
!83 = !DILocation(line: 55, column: 18, scope: !73)
!84 = !DILocation(line: 56, column: 27, scope: !73)
!85 = !DILocation(line: 56, column: 5, scope: !73)
!86 = !DILocation(line: 58, column: 1, scope: !73)
!87 = distinct !DISubprogram(name: "py_03_use_after_decref", scope: !2, file: !2, line: 66, type: !74, scopeLine: 66, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !26, retainedNodes: !63)
!88 = !DILocalVariable(name: "bytes", scope: !87, file: !2, line: 67, type: !46)
!89 = !DILocation(line: 67, column: 15, scope: !87)
!90 = !DILocation(line: 67, column: 23, scope: !87)
!91 = !DILocalVariable(name: "data", scope: !87, file: !2, line: 68, type: !80)
!92 = !DILocation(line: 68, column: 11, scope: !87)
!93 = !DILocation(line: 68, column: 35, scope: !87)
!94 = !DILocation(line: 68, column: 18, scope: !87)
!95 = !DILocation(line: 70, column: 15, scope: !87)
!96 = !DILocation(line: 70, column: 5, scope: !87)
!97 = !DILocation(line: 73, column: 27, scope: !87)
!98 = !DILocation(line: 73, column: 5, scope: !87)
!99 = !DILocation(line: 74, column: 1, scope: !87)
!100 = distinct !DISubprogram(name: "py_04_steal_ref_misuse", scope: !2, file: !2, line: 82, type: !74, scopeLine: 82, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !26, retainedNodes: !63)
!101 = !DILocalVariable(name: "tuple", scope: !100, file: !2, line: 83, type: !46)
!102 = !DILocation(line: 83, column: 15, scope: !100)
!103 = !DILocation(line: 83, column: 23, scope: !100)
!104 = !DILocalVariable(name: "val1", scope: !100, file: !2, line: 84, type: !46)
!105 = !DILocation(line: 84, column: 15, scope: !100)
!106 = !DILocation(line: 84, column: 22, scope: !100)
!107 = !DILocalVariable(name: "val2", scope: !100, file: !2, line: 85, type: !46)
!108 = !DILocation(line: 85, column: 15, scope: !100)
!109 = !DILocation(line: 85, column: 22, scope: !100)
!110 = !DILocation(line: 87, column: 21, scope: !100)
!111 = !DILocation(line: 87, column: 31, scope: !100)
!112 = !DILocation(line: 87, column: 5, scope: !100)
!113 = !DILocation(line: 88, column: 21, scope: !100)
!114 = !DILocation(line: 88, column: 31, scope: !100)
!115 = !DILocation(line: 88, column: 5, scope: !100)
!116 = !DILocalVariable(name: "v", scope: !100, file: !2, line: 92, type: !117)
!117 = !DIBasicType(name: "long", size: 64, encoding: DW_ATE_signed)
!118 = !DILocation(line: 92, column: 10, scope: !100)
!119 = !DILocation(line: 92, column: 28, scope: !100)
!120 = !DILocation(line: 92, column: 14, scope: !100)
!121 = !DILocation(line: 93, column: 28, scope: !100)
!122 = !DILocation(line: 93, column: 5, scope: !100)
!123 = !DILocation(line: 94, column: 1, scope: !100)
!124 = distinct !DISubprogram(name: "py_05_cache_no_incref", scope: !2, file: !2, line: 104, type: !61, scopeLine: 104, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !26, retainedNodes: !63)
!125 = !DILocalVariable(name: "obj", arg: 1, scope: !124, file: !2, line: 104, type: !46)
!126 = !DILocation(line: 104, column: 38, scope: !124)
!127 = !DILocation(line: 106, column: 23, scope: !124)
!128 = !DILocation(line: 106, column: 21, scope: !124)
!129 = !DILocation(line: 107, column: 1, scope: !124)
!130 = distinct !DISubprogram(name: "py_05_use_cached", scope: !2, file: !2, line: 109, type: !74, scopeLine: 109, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !26, retainedNodes: !63)
!131 = !DILocation(line: 111, column: 9, scope: !132)
!132 = distinct !DILexicalBlock(scope: !130, file: !2, line: 111, column: 9)
!133 = !DILocalVariable(name: "val", scope: !134, file: !2, line: 112, type: !117)
!134 = distinct !DILexicalBlock(scope: !132, file: !2, line: 111, column: 26)
!135 = !DILocation(line: 112, column: 14, scope: !134)
!136 = !DILocation(line: 112, column: 34, scope: !134)
!137 = !DILocation(line: 112, column: 20, scope: !134)
!138 = !DILocation(line: 113, column: 33, scope: !134)
!139 = !DILocation(line: 113, column: 9, scope: !134)
!140 = !DILocation(line: 114, column: 5, scope: !134)
!141 = !DILocation(line: 115, column: 1, scope: !130)
!142 = distinct !DISubprogram(name: "py_06_free_python_memory", scope: !2, file: !2, line: 123, type: !74, scopeLine: 123, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !26, retainedNodes: !63)
!143 = !DILocalVariable(name: "bytes", scope: !142, file: !2, line: 124, type: !46)
!144 = !DILocation(line: 124, column: 15, scope: !142)
!145 = !DILocation(line: 124, column: 23, scope: !142)
!146 = !DILocalVariable(name: "buf", scope: !142, file: !2, line: 125, type: !80)
!147 = !DILocation(line: 125, column: 11, scope: !142)
!148 = !DILocation(line: 125, column: 34, scope: !142)
!149 = !DILocation(line: 125, column: 17, scope: !142)
!150 = !DILocation(line: 128, column: 10, scope: !142)
!151 = !DILocation(line: 128, column: 5, scope: !142)
!152 = !DILocation(line: 130, column: 1, scope: !142)
!153 = distinct !DISubprogram(name: "py_07_callback_no_gil", scope: !2, file: !2, line: 141, type: !61, scopeLine: 141, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !26, retainedNodes: !63)
!154 = !DILocalVariable(name: "callback", arg: 1, scope: !153, file: !2, line: 141, type: !46)
!155 = !DILocation(line: 141, column: 38, scope: !153)
!156 = !DILocalVariable(name: "result", scope: !153, file: !2, line: 144, type: !46)
!157 = !DILocation(line: 144, column: 15, scope: !153)
!158 = !DILocation(line: 144, column: 47, scope: !153)
!159 = !DILocation(line: 144, column: 24, scope: !153)
!160 = !DILocation(line: 145, column: 15, scope: !153)
!161 = !DILocation(line: 145, column: 5, scope: !153)
!162 = !DILocation(line: 146, column: 1, scope: !153)
!163 = distinct !DISubprogram(name: "py_08_ctypes_wrong_free", scope: !2, file: !2, line: 157, type: !74, scopeLine: 157, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !26, retainedNodes: !63)
!164 = !DILocalVariable(name: "buf", scope: !163, file: !2, line: 158, type: !29)
!165 = !DILocation(line: 158, column: 11, scope: !163)
!166 = !DILocation(line: 158, column: 17, scope: !163)
!167 = !DILocation(line: 159, column: 5, scope: !163)
!168 = !DILocation(line: 161, column: 10, scope: !163)
!169 = !DILocation(line: 161, column: 5, scope: !163)
!170 = !DILocation(line: 162, column: 1, scope: !163)
