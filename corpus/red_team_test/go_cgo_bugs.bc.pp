; ModuleID = 'corpus/red_team_test/go_cgo_bugs.c'
source_filename = "corpus/red_team_test/go_cgo_bugs.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

%struct.GoSlice = type { ptr, i32, i32 }
%struct.GoString = type { ptr, i32 }

@.str = private unnamed_addr constant [24 x i8] c"allocated by Go runtime\00", align 1, !dbg !0
@.str.1 = private unnamed_addr constant [15 x i8] c"allocated by C\00", align 1, !dbg !7
@g_go_slice_data = internal global ptr null, align 8, !dbg !12
@g_shared_counter = internal global i32 0, align 4, !dbg !24
@g_stored_callback = internal global ptr null, align 8, !dbg !28
@.str.2 = private unnamed_addr constant [21 x i8] c"Go allocated via cgo\00", align 1, !dbg !19

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @go_01_go_alloc_c_free() #0 !dbg !41 {
entry:
  %ptr = alloca ptr, align 8
    #dbg_declare(ptr %ptr, !45, !DIExpression(), !46)
  %call = call ptr @_cgo_allocate(i32 noundef 128), !dbg !47
  store ptr %call, ptr %ptr, align 8, !dbg !46
  %0 = load ptr, ptr %ptr, align 8, !dbg !48
  %1 = load ptr, ptr %ptr, align 8, !dbg !48
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !48
  %call1 = call ptr @__strcpy_chk(ptr noundef %0, ptr noundef @.str, i64 noundef %2) #5, !dbg !48
  %3 = load ptr, ptr %ptr, align 8, !dbg !49
  call void @free(ptr noundef %3), !dbg !50
  ret void, !dbg !51
}

declare ptr @_cgo_allocate(i32 noundef) #1

; Function Attrs: nounwind
declare ptr @__strcpy_chk(ptr noundef, ptr noundef, i64 noundef) #2

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.objectsize.i64.p0(ptr, i1 immarg, i1 immarg, i1 immarg) #3

declare void @free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @go_02_c_alloc_go_free() #0 !dbg !52 {
entry:
  %ptr = alloca ptr, align 8
    #dbg_declare(ptr %ptr, !53, !DIExpression(), !54)
  %call = call ptr @malloc(i64 noundef 256) #6, !dbg !55
  store ptr %call, ptr %ptr, align 8, !dbg !54
  %0 = load ptr, ptr %ptr, align 8, !dbg !56
  %1 = load ptr, ptr %ptr, align 8, !dbg !56
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !56
  %call1 = call ptr @__strcpy_chk(ptr noundef %0, ptr noundef @.str.1, i64 noundef %2) #5, !dbg !56
  %3 = load ptr, ptr %ptr, align 8, !dbg !57
  call void @_cgo_free(ptr noundef %3), !dbg !58
  ret void, !dbg !59
}

; Function Attrs: allocsize(0)
declare ptr @malloc(i64 noundef) #4

declare void @_cgo_free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @go_03_slice_escape() #0 !dbg !60 {
entry:
  %slice = alloca %struct.GoSlice, align 8
    #dbg_declare(ptr %slice, !61, !DIExpression(), !68)
  %call = call ptr @_cgo_allocate(i32 noundef 1024), !dbg !69
  %data = getelementptr inbounds nuw %struct.GoSlice, ptr %slice, i32 0, i32 0, !dbg !70
  store ptr %call, ptr %data, align 8, !dbg !71
  %len = getelementptr inbounds nuw %struct.GoSlice, ptr %slice, i32 0, i32 1, !dbg !72
  store i32 1024, ptr %len, align 8, !dbg !73
  %cap = getelementptr inbounds nuw %struct.GoSlice, ptr %slice, i32 0, i32 2, !dbg !74
  store i32 1024, ptr %cap, align 4, !dbg !75
  %data1 = getelementptr inbounds nuw %struct.GoSlice, ptr %slice, i32 0, i32 0, !dbg !76
  %0 = load ptr, ptr %data1, align 8, !dbg !76
  store ptr %0, ptr @g_go_slice_data, align 8, !dbg !77
  %data2 = getelementptr inbounds nuw %struct.GoSlice, ptr %slice, i32 0, i32 0, !dbg !78
  %1 = load ptr, ptr %data2, align 8, !dbg !78
  call void @_cgo_free(ptr noundef %1), !dbg !79
  %2 = load ptr, ptr @g_go_slice_data, align 8, !dbg !80
  %3 = load ptr, ptr @g_go_slice_data, align 8, !dbg !80
  %4 = call i64 @llvm.objectsize.i64.p0(ptr %3, i1 false, i1 true, i1 false), !dbg !80
  %call3 = call ptr @__memset_chk(ptr noundef %2, i32 noundef 0, i64 noundef 64, i64 noundef %4) #5, !dbg !80
  ret void, !dbg !81
}

; Function Attrs: nounwind
declare ptr @__memset_chk(ptr noundef, i32 noundef, i64 noundef, i64 noundef) #2

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define ptr @go_04_c_thread_func(ptr noundef %arg) #0 !dbg !82 {
entry:
  %arg.addr = alloca ptr, align 8
  %i = alloca i32, align 4
  %val = alloca i32, align 4
  store ptr %arg, ptr %arg.addr, align 8
    #dbg_declare(ptr %arg.addr, !85, !DIExpression(), !86)
    #dbg_declare(ptr %i, !87, !DIExpression(), !89)
  store i32 0, ptr %i, align 4, !dbg !89
  br label %for.cond, !dbg !90

for.cond:                                         ; preds = %for.inc, %entry
  %0 = load i32, ptr %i, align 4, !dbg !91
  %cmp = icmp slt i32 %0, 1000, !dbg !93
  br i1 %cmp, label %for.body, label %for.end, !dbg !94

for.body:                                         ; preds = %for.cond
    #dbg_declare(ptr %val, !95, !DIExpression(), !97)
  %1 = load volatile i32, ptr @g_shared_counter, align 4, !dbg !98
  store i32 %1, ptr %val, align 4, !dbg !97
  %2 = load i32, ptr %val, align 4, !dbg !99
  br label %for.inc, !dbg !100

for.inc:                                          ; preds = %for.body
  %3 = load i32, ptr %i, align 4, !dbg !101
  %inc = add nsw i32 %3, 1, !dbg !101
  store i32 %inc, ptr %i, align 4, !dbg !101
  br label %for.cond, !dbg !102, !llvm.loop !103

for.end:                                          ; preds = %for.cond
  ret ptr null, !dbg !106
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @go_04_race_test() #0 !dbg !107 {
entry:
  %tid = alloca ptr, align 8
  %i = alloca i32, align 4
    #dbg_declare(ptr %tid, !108, !DIExpression(), !132)
  %call = call i32 @pthread_create(ptr noundef %tid, ptr noundef null, ptr noundef @go_04_c_thread_func, ptr noundef null), !dbg !133
    #dbg_declare(ptr %i, !134, !DIExpression(), !136)
  store i32 0, ptr %i, align 4, !dbg !136
  br label %for.cond, !dbg !137

for.cond:                                         ; preds = %for.inc, %entry
  %0 = load i32, ptr %i, align 4, !dbg !138
  %cmp = icmp slt i32 %0, 1000, !dbg !140
  br i1 %cmp, label %for.body, label %for.end, !dbg !141

for.body:                                         ; preds = %for.cond
  %1 = load volatile i32, ptr @g_shared_counter, align 4, !dbg !142
  %inc = add nsw i32 %1, 1, !dbg !142
  store volatile i32 %inc, ptr @g_shared_counter, align 4, !dbg !142
  br label %for.inc, !dbg !144

for.inc:                                          ; preds = %for.body
  %2 = load i32, ptr %i, align 4, !dbg !145
  %inc1 = add nsw i32 %2, 1, !dbg !145
  store i32 %inc1, ptr %i, align 4, !dbg !145
  br label %for.cond, !dbg !146, !llvm.loop !147

for.end:                                          ; preds = %for.cond
  %3 = load ptr, ptr %tid, align 8, !dbg !149
  %call2 = call i32 @"\01_pthread_join"(ptr noundef %3, ptr noundef null), !dbg !150
  ret void, !dbg !151
}

declare i32 @pthread_create(ptr noundef, ptr noundef, ptr noundef, ptr noundef) #1

declare i32 @"\01_pthread_join"(ptr noundef, ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @go_05_register_callback(ptr noundef %cb) #0 !dbg !152 {
entry:
  %cb.addr = alloca ptr, align 8
  store ptr %cb, ptr %cb.addr, align 8
    #dbg_declare(ptr %cb.addr, !155, !DIExpression(), !156)
  %0 = load ptr, ptr %cb.addr, align 8, !dbg !157
  store ptr %0, ptr @g_stored_callback, align 8, !dbg !158
  ret void, !dbg !159
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @go_05_invoke_stored() #0 !dbg !160 {
entry:
  %0 = load ptr, ptr @g_stored_callback, align 8, !dbg !161
  %tobool = icmp ne ptr %0, null, !dbg !161
  br i1 %tobool, label %if.then, label %if.end, !dbg !161

if.then:                                          ; preds = %entry
  %1 = load ptr, ptr @g_stored_callback, align 8, !dbg !163
  call void %1(i32 noundef 42), !dbg !163
  br label %if.end, !dbg !165

if.end:                                           ; preds = %if.then, %entry
  ret void, !dbg !166
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @go_06_double_free_cgo() #0 !dbg !167 {
entry:
  %ptr = alloca ptr, align 8
    #dbg_declare(ptr %ptr, !168, !DIExpression(), !169)
  %call = call ptr @_Cfunc_GoMalloc(i32 noundef 128), !dbg !170
  store ptr %call, ptr %ptr, align 8, !dbg !169
  %0 = load ptr, ptr %ptr, align 8, !dbg !171
  %1 = load ptr, ptr %ptr, align 8, !dbg !171
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !171
  %call1 = call ptr @__strcpy_chk(ptr noundef %0, ptr noundef @.str.2, i64 noundef %2) #5, !dbg !171
  %3 = load ptr, ptr %ptr, align 8, !dbg !172
  call void @free(ptr noundef %3), !dbg !173
  %4 = load ptr, ptr %ptr, align 8, !dbg !174
  call void @_Cfunc_GoFree(ptr noundef %4), !dbg !175
  ret void, !dbg !176
}

declare ptr @_Cfunc_GoMalloc(i32 noundef) #1

declare void @_Cfunc_GoFree(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @go_07_mutate_go_string(ptr noundef %s) #0 !dbg !177 {
entry:
  %s.addr = alloca ptr, align 8
  %mutable = alloca ptr, align 8
  store ptr %s, ptr %s.addr, align 8
    #dbg_declare(ptr %s.addr, !188, !DIExpression(), !189)
    #dbg_declare(ptr %mutable, !190, !DIExpression(), !191)
  %0 = load ptr, ptr %s.addr, align 8, !dbg !192
  %data = getelementptr inbounds nuw %struct.GoString, ptr %0, i32 0, i32 0, !dbg !193
  %1 = load ptr, ptr %data, align 8, !dbg !193
  store ptr %1, ptr %mutable, align 8, !dbg !191
  %2 = load ptr, ptr %mutable, align 8, !dbg !194
  %arrayidx = getelementptr inbounds i8, ptr %2, i64 0, !dbg !194
  store i8 88, ptr %arrayidx, align 1, !dbg !195
  ret void, !dbg !196
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @go_08_c_ptr_in_go_struct() #0 !dbg !197 {
entry:
  %c_mem = alloca ptr, align 8
  %slice = alloca %struct.GoSlice, align 8
    #dbg_declare(ptr %c_mem, !198, !DIExpression(), !199)
  %call = call ptr @malloc(i64 noundef 4096) #6, !dbg !200
  store ptr %call, ptr %c_mem, align 8, !dbg !199
  %0 = load ptr, ptr %c_mem, align 8, !dbg !201
  %1 = load ptr, ptr %c_mem, align 8, !dbg !201
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !201
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 0, i64 noundef 4096, i64 noundef %2) #5, !dbg !201
    #dbg_declare(ptr %slice, !202, !DIExpression(), !203)
  %3 = load ptr, ptr %c_mem, align 8, !dbg !204
  %data = getelementptr inbounds nuw %struct.GoSlice, ptr %slice, i32 0, i32 0, !dbg !205
  store ptr %3, ptr %data, align 8, !dbg !206
  %len = getelementptr inbounds nuw %struct.GoSlice, ptr %slice, i32 0, i32 1, !dbg !207
  store i32 4096, ptr %len, align 8, !dbg !208
  %cap = getelementptr inbounds nuw %struct.GoSlice, ptr %slice, i32 0, i32 2, !dbg !209
  store i32 4096, ptr %cap, align 4, !dbg !210
  %data2 = getelementptr inbounds nuw %struct.GoSlice, ptr %slice, i32 0, i32 0, !dbg !211
  store ptr null, ptr %data2, align 8, !dbg !212
  %len3 = getelementptr inbounds nuw %struct.GoSlice, ptr %slice, i32 0, i32 1, !dbg !213
  store i32 0, ptr %len3, align 8, !dbg !214
  ret void, !dbg !215
}

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #4 = { allocsize(0) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #5 = { nounwind }
attributes #6 = { allocsize(0) }

!llvm.dbg.cu = !{!14}
!llvm.module.flags = !{!34, !35, !36, !37, !38, !39}
!llvm.ident = !{!40}

!0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
!1 = distinct !DIGlobalVariable(scope: null, file: !2, line: 44, type: !3, isLocal: true, isDefinition: true)
!2 = !DIFile(filename: "corpus/red_team_test/go_cgo_bugs.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "4a2119cb564a6b6299b1dd90d9ce1753")
!3 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 192, elements: !5)
!4 = !DIBasicType(name: "char", size: 8, encoding: DW_ATE_signed_char)
!5 = !{!6}
!6 = !DISubrange(count: 24)
!7 = !DIGlobalVariableExpression(var: !8, expr: !DIExpression())
!8 = distinct !DIGlobalVariable(scope: null, file: !2, line: 55, type: !9, isLocal: true, isDefinition: true)
!9 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 120, elements: !10)
!10 = !{!11}
!11 = !DISubrange(count: 15)
!12 = !DIGlobalVariableExpression(var: !13, expr: !DIExpression())
!13 = distinct !DIGlobalVariable(name: "g_go_slice_data", scope: !14, file: !2, line: 65, type: !17, isLocal: true, isDefinition: true)
!14 = distinct !DICompileUnit(language: DW_LANG_C11, file: !2, producer: "Homebrew clang version 21.1.8", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, retainedTypes: !15, globals: !18, splitDebugInlining: false, nameTableKind: Apple, sysroot: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk", sdk: "MacOSX15.sdk")
!15 = !{!16, !17}
!16 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !4, size: 64)
!17 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!18 = !{!0, !7, !19, !12, !24, !28}
!19 = !DIGlobalVariableExpression(var: !20, expr: !DIExpression())
!20 = distinct !DIGlobalVariable(scope: null, file: !2, line: 141, type: !21, isLocal: true, isDefinition: true)
!21 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 168, elements: !22)
!22 = !{!23}
!23 = !DISubrange(count: 21)
!24 = !DIGlobalVariableExpression(var: !25, expr: !DIExpression())
!25 = distinct !DIGlobalVariable(name: "g_shared_counter", scope: !14, file: !2, line: 89, type: !26, isLocal: true, isDefinition: true)
!26 = !DIDerivedType(tag: DW_TAG_volatile_type, baseType: !27)
!27 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!28 = !DIGlobalVariableExpression(var: !29, expr: !DIExpression())
!29 = distinct !DIGlobalVariable(name: "g_stored_callback", scope: !14, file: !2, line: 120, type: !30, isLocal: true, isDefinition: true)
!30 = !DIDerivedType(tag: DW_TAG_typedef, name: "GoCallback", file: !2, line: 118, baseType: !31)
!31 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !32, size: 64)
!32 = !DISubroutineType(types: !33)
!33 = !{null, !27}
!34 = !{i32 7, !"Dwarf Version", i32 5}
!35 = !{i32 2, !"Debug Info Version", i32 3}
!36 = !{i32 1, !"wchar_size", i32 4}
!37 = !{i32 8, !"PIC Level", i32 2}
!38 = !{i32 7, !"uwtable", i32 1}
!39 = !{i32 7, !"frame-pointer", i32 1}
!40 = !{!"Homebrew clang version 21.1.8"}
!41 = distinct !DISubprogram(name: "go_01_go_alloc_c_free", scope: !2, file: !2, line: 42, type: !42, scopeLine: 42, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !44)
!42 = !DISubroutineType(types: !43)
!43 = !{null}
!44 = !{}
!45 = !DILocalVariable(name: "ptr", scope: !41, file: !2, line: 43, type: !17)
!46 = !DILocation(line: 43, column: 11, scope: !41)
!47 = !DILocation(line: 43, column: 17, scope: !41)
!48 = !DILocation(line: 44, column: 5, scope: !41)
!49 = !DILocation(line: 45, column: 10, scope: !41)
!50 = !DILocation(line: 45, column: 5, scope: !41)
!51 = !DILocation(line: 46, column: 1, scope: !41)
!52 = distinct !DISubprogram(name: "go_02_c_alloc_go_free", scope: !2, file: !2, line: 53, type: !42, scopeLine: 53, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !44)
!53 = !DILocalVariable(name: "ptr", scope: !52, file: !2, line: 54, type: !17)
!54 = !DILocation(line: 54, column: 11, scope: !52)
!55 = !DILocation(line: 54, column: 17, scope: !52)
!56 = !DILocation(line: 55, column: 5, scope: !52)
!57 = !DILocation(line: 56, column: 15, scope: !52)
!58 = !DILocation(line: 56, column: 5, scope: !52)
!59 = !DILocation(line: 57, column: 1, scope: !52)
!60 = distinct !DISubprogram(name: "go_03_slice_escape", scope: !2, file: !2, line: 67, type: !42, scopeLine: 67, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !44)
!61 = !DILocalVariable(name: "slice", scope: !60, file: !2, line: 68, type: !62)
!62 = !DIDerivedType(tag: DW_TAG_typedef, name: "GoSlice", file: !2, line: 28, baseType: !63)
!63 = distinct !DICompositeType(tag: DW_TAG_structure_type, file: !2, line: 24, size: 128, elements: !64)
!64 = !{!65, !66, !67}
!65 = !DIDerivedType(tag: DW_TAG_member, name: "data", scope: !63, file: !2, line: 25, baseType: !17, size: 64)
!66 = !DIDerivedType(tag: DW_TAG_member, name: "len", scope: !63, file: !2, line: 26, baseType: !27, size: 32, offset: 64)
!67 = !DIDerivedType(tag: DW_TAG_member, name: "cap", scope: !63, file: !2, line: 27, baseType: !27, size: 32, offset: 96)
!68 = !DILocation(line: 68, column: 13, scope: !60)
!69 = !DILocation(line: 69, column: 18, scope: !60)
!70 = !DILocation(line: 69, column: 11, scope: !60)
!71 = !DILocation(line: 69, column: 16, scope: !60)
!72 = !DILocation(line: 70, column: 11, scope: !60)
!73 = !DILocation(line: 70, column: 15, scope: !60)
!74 = !DILocation(line: 71, column: 11, scope: !60)
!75 = !DILocation(line: 71, column: 15, scope: !60)
!76 = !DILocation(line: 74, column: 29, scope: !60)
!77 = !DILocation(line: 74, column: 21, scope: !60)
!78 = !DILocation(line: 77, column: 21, scope: !60)
!79 = !DILocation(line: 77, column: 5, scope: !60)
!80 = !DILocation(line: 80, column: 5, scope: !60)
!81 = !DILocation(line: 81, column: 1, scope: !60)
!82 = distinct !DISubprogram(name: "go_04_c_thread_func", scope: !2, file: !2, line: 91, type: !83, scopeLine: 91, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !44)
!83 = !DISubroutineType(types: !84)
!84 = !{!17, !17}
!85 = !DILocalVariable(name: "arg", arg: 1, scope: !82, file: !2, line: 91, type: !17)
!86 = !DILocation(line: 91, column: 33, scope: !82)
!87 = !DILocalVariable(name: "i", scope: !88, file: !2, line: 93, type: !27)
!88 = distinct !DILexicalBlock(scope: !82, file: !2, line: 93, column: 5)
!89 = !DILocation(line: 93, column: 14, scope: !88)
!90 = !DILocation(line: 93, column: 10, scope: !88)
!91 = !DILocation(line: 93, column: 21, scope: !92)
!92 = distinct !DILexicalBlock(scope: !88, file: !2, line: 93, column: 5)
!93 = !DILocation(line: 93, column: 23, scope: !92)
!94 = !DILocation(line: 93, column: 5, scope: !88)
!95 = !DILocalVariable(name: "val", scope: !96, file: !2, line: 94, type: !27)
!96 = distinct !DILexicalBlock(scope: !92, file: !2, line: 93, column: 36)
!97 = !DILocation(line: 94, column: 13, scope: !96)
!98 = !DILocation(line: 94, column: 19, scope: !96)
!99 = !DILocation(line: 95, column: 15, scope: !96)
!100 = !DILocation(line: 96, column: 5, scope: !96)
!101 = !DILocation(line: 93, column: 32, scope: !92)
!102 = !DILocation(line: 93, column: 5, scope: !92)
!103 = distinct !{!103, !94, !104, !105}
!104 = !DILocation(line: 96, column: 5, scope: !88)
!105 = !{!"llvm.loop.mustprogress"}
!106 = !DILocation(line: 97, column: 5, scope: !82)
!107 = distinct !DISubprogram(name: "go_04_race_test", scope: !2, file: !2, line: 100, type: !42, scopeLine: 100, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !44)
!108 = !DILocalVariable(name: "tid", scope: !107, file: !2, line: 101, type: !109)
!109 = !DIDerivedType(tag: DW_TAG_typedef, name: "pthread_t", file: !110, line: 31, baseType: !111)
!110 = !DIFile(filename: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk/usr/include/sys/_pthread/_pthread_t.h", directory: "", checksumkind: CSK_MD5, checksum: "086fc6d7dc3c67fdb87e7376555dcfd7")
!111 = !DIDerivedType(tag: DW_TAG_typedef, name: "__darwin_pthread_t", file: !112, line: 118, baseType: !113)
!112 = !DIFile(filename: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk/usr/include/sys/_pthread/_pthread_types.h", directory: "", checksumkind: CSK_MD5, checksum: "4e2ea0e1af95894da0a6030a21a8ebee")
!113 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !114, size: 64)
!114 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "_opaque_pthread_t", file: !112, line: 103, size: 65536, elements: !115)
!115 = !{!116, !118, !128}
!116 = !DIDerivedType(tag: DW_TAG_member, name: "__sig", scope: !114, file: !112, line: 104, baseType: !117, size: 64)
!117 = !DIBasicType(name: "long", size: 64, encoding: DW_ATE_signed)
!118 = !DIDerivedType(tag: DW_TAG_member, name: "__cleanup_stack", scope: !114, file: !112, line: 105, baseType: !119, size: 64, offset: 64)
!119 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !120, size: 64)
!120 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "__darwin_pthread_handler_rec", file: !112, line: 57, size: 192, elements: !121)
!121 = !{!122, !126, !127}
!122 = !DIDerivedType(tag: DW_TAG_member, name: "__routine", scope: !120, file: !112, line: 58, baseType: !123, size: 64)
!123 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !124, size: 64)
!124 = !DISubroutineType(types: !125)
!125 = !{null, !17}
!126 = !DIDerivedType(tag: DW_TAG_member, name: "__arg", scope: !120, file: !112, line: 59, baseType: !17, size: 64, offset: 64)
!127 = !DIDerivedType(tag: DW_TAG_member, name: "__next", scope: !120, file: !112, line: 60, baseType: !119, size: 64, offset: 128)
!128 = !DIDerivedType(tag: DW_TAG_member, name: "__opaque", scope: !114, file: !112, line: 106, baseType: !129, size: 65408, offset: 128)
!129 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 65408, elements: !130)
!130 = !{!131}
!131 = !DISubrange(count: 8176)
!132 = !DILocation(line: 101, column: 15, scope: !107)
!133 = !DILocation(line: 102, column: 5, scope: !107)
!134 = !DILocalVariable(name: "i", scope: !135, file: !2, line: 105, type: !27)
!135 = distinct !DILexicalBlock(scope: !107, file: !2, line: 105, column: 5)
!136 = !DILocation(line: 105, column: 14, scope: !135)
!137 = !DILocation(line: 105, column: 10, scope: !135)
!138 = !DILocation(line: 105, column: 21, scope: !139)
!139 = distinct !DILexicalBlock(scope: !135, file: !2, line: 105, column: 5)
!140 = !DILocation(line: 105, column: 23, scope: !139)
!141 = !DILocation(line: 105, column: 5, scope: !135)
!142 = !DILocation(line: 106, column: 25, scope: !143)
!143 = distinct !DILexicalBlock(scope: !139, file: !2, line: 105, column: 36)
!144 = !DILocation(line: 107, column: 5, scope: !143)
!145 = !DILocation(line: 105, column: 32, scope: !139)
!146 = !DILocation(line: 105, column: 5, scope: !139)
!147 = distinct !{!147, !141, !148, !105}
!148 = !DILocation(line: 107, column: 5, scope: !135)
!149 = !DILocation(line: 109, column: 18, scope: !107)
!150 = !DILocation(line: 109, column: 5, scope: !107)
!151 = !DILocation(line: 110, column: 1, scope: !107)
!152 = distinct !DISubprogram(name: "go_05_register_callback", scope: !2, file: !2, line: 122, type: !153, scopeLine: 122, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !44)
!153 = !DISubroutineType(types: !154)
!154 = !{null, !30}
!155 = !DILocalVariable(name: "cb", arg: 1, scope: !152, file: !2, line: 122, type: !30)
!156 = !DILocation(line: 122, column: 41, scope: !152)
!157 = !DILocation(line: 123, column: 25, scope: !152)
!158 = !DILocation(line: 123, column: 23, scope: !152)
!159 = !DILocation(line: 124, column: 1, scope: !152)
!160 = distinct !DISubprogram(name: "go_05_invoke_stored", scope: !2, file: !2, line: 126, type: !42, scopeLine: 126, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14)
!161 = !DILocation(line: 128, column: 9, scope: !162)
!162 = distinct !DILexicalBlock(scope: !160, file: !2, line: 128, column: 9)
!163 = !DILocation(line: 129, column: 9, scope: !164)
!164 = distinct !DILexicalBlock(scope: !162, file: !2, line: 128, column: 28)
!165 = !DILocation(line: 130, column: 5, scope: !164)
!166 = !DILocation(line: 131, column: 1, scope: !160)
!167 = distinct !DISubprogram(name: "go_06_double_free_cgo", scope: !2, file: !2, line: 139, type: !42, scopeLine: 139, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !44)
!168 = !DILocalVariable(name: "ptr", scope: !167, file: !2, line: 140, type: !17)
!169 = !DILocation(line: 140, column: 11, scope: !167)
!170 = !DILocation(line: 140, column: 17, scope: !167)
!171 = !DILocation(line: 141, column: 5, scope: !167)
!172 = !DILocation(line: 143, column: 10, scope: !167)
!173 = !DILocation(line: 143, column: 5, scope: !167)
!174 = !DILocation(line: 144, column: 19, scope: !167)
!175 = !DILocation(line: 144, column: 5, scope: !167)
!176 = !DILocation(line: 145, column: 1, scope: !167)
!177 = distinct !DISubprogram(name: "go_07_mutate_go_string", scope: !2, file: !2, line: 153, type: !178, scopeLine: 153, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !44)
!178 = !DISubroutineType(types: !179)
!179 = !{null, !180}
!180 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !181, size: 64)
!181 = !DIDerivedType(tag: DW_TAG_typedef, name: "GoString", file: !2, line: 34, baseType: !182)
!182 = distinct !DICompositeType(tag: DW_TAG_structure_type, file: !2, line: 31, size: 128, elements: !183)
!183 = !{!184, !187}
!184 = !DIDerivedType(tag: DW_TAG_member, name: "data", scope: !182, file: !2, line: 32, baseType: !185, size: 64)
!185 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !186, size: 64)
!186 = !DIDerivedType(tag: DW_TAG_const_type, baseType: !4)
!187 = !DIDerivedType(tag: DW_TAG_member, name: "len", scope: !182, file: !2, line: 33, baseType: !27, size: 32, offset: 64)
!188 = !DILocalVariable(name: "s", arg: 1, scope: !177, file: !2, line: 153, type: !180)
!189 = !DILocation(line: 153, column: 39, scope: !177)
!190 = !DILocalVariable(name: "mutable", scope: !177, file: !2, line: 155, type: !16)
!191 = !DILocation(line: 155, column: 11, scope: !177)
!192 = !DILocation(line: 155, column: 28, scope: !177)
!193 = !DILocation(line: 155, column: 31, scope: !177)
!194 = !DILocation(line: 156, column: 5, scope: !177)
!195 = !DILocation(line: 156, column: 16, scope: !177)
!196 = !DILocation(line: 157, column: 1, scope: !177)
!197 = distinct !DISubprogram(name: "go_08_c_ptr_in_go_struct", scope: !2, file: !2, line: 165, type: !42, scopeLine: 165, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !14, retainedNodes: !44)
!198 = !DILocalVariable(name: "c_mem", scope: !197, file: !2, line: 166, type: !17)
!199 = !DILocation(line: 166, column: 11, scope: !197)
!200 = !DILocation(line: 166, column: 19, scope: !197)
!201 = !DILocation(line: 167, column: 5, scope: !197)
!202 = !DILocalVariable(name: "slice", scope: !197, file: !2, line: 170, type: !62)
!203 = !DILocation(line: 170, column: 13, scope: !197)
!204 = !DILocation(line: 171, column: 18, scope: !197)
!205 = !DILocation(line: 171, column: 11, scope: !197)
!206 = !DILocation(line: 171, column: 16, scope: !197)
!207 = !DILocation(line: 172, column: 11, scope: !197)
!208 = !DILocation(line: 172, column: 15, scope: !197)
!209 = !DILocation(line: 173, column: 11, scope: !197)
!210 = !DILocation(line: 173, column: 15, scope: !197)
!211 = !DILocation(line: 176, column: 11, scope: !197)
!212 = !DILocation(line: 176, column: 16, scope: !197)
!213 = !DILocation(line: 177, column: 11, scope: !197)
!214 = !DILocation(line: 177, column: 15, scope: !197)
!215 = !DILocation(line: 181, column: 1, scope: !197)
