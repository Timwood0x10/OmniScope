; ModuleID = 'corpus/red_team_test/cross_lang_free_bugs.c'
source_filename = "corpus/red_team_test/cross_lang_free_bugs.c"
target datalayout = "e-m:o-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

%struct.Container = type { ptr, i32 }

@.str = private unnamed_addr constant [37 x i8] c"Cross-Language Free Violation Tests\0A\00", align 1, !dbg !0
@.str.1 = private unnamed_addr constant [39 x i8] c"====================================\0A\0A\00", align 1, !dbg !7
@.str.2 = private unnamed_addr constant [31 x i8] c"Test 1: Rust alloc \E2\86\92 C free\0A\00", align 1, !dbg !12
@.str.3 = private unnamed_addr constant [33 x i8] c"\0ATest 2: C alloc \E2\86\92 C++ delete\0A\00", align 1, !dbg !17
@.str.4 = private unnamed_addr constant [40 x i8] c"\0ATest 3: Safe same-language alloc/free\0A\00", align 1, !dbg !22
@.str.5 = private unnamed_addr constant [37 x i8] c"\0ATest 4: Alias chain cross-language\0A\00", align 1, !dbg !27
@.str.6 = private unnamed_addr constant [42 x i8] c"\0ATest 5: Double cross-language violation\0A\00", align 1, !dbg !29
@.str.7 = private unnamed_addr constant [33 x i8] c"\0ATest 6: Realloc cross-language\0A\00", align 1, !dbg !34
@.str.8 = private unnamed_addr constant [33 x i8] c"\0ATest 7: Null pointer edge case\0A\00", align 1, !dbg !36
@.str.9 = private unnamed_addr constant [36 x i8] c"\0ATest 8: Stack escape + cross-lang\0A\00", align 1, !dbg !38
@.str.10 = private unnamed_addr constant [35 x i8] c"\0ATest 9: Mixed ownership transfer\0A\00", align 1, !dbg !43
@.str.11 = private unnamed_addr constant [29 x i8] c"\0ATest 10: Nested allocation\0A\00", align 1, !dbg !48
@.str.12 = private unnamed_addr constant [39 x i8] c"\0A====================================\0A\00", align 1, !dbg !53
@.str.13 = private unnamed_addr constant [17 x i8] c"Tests completed\0A\00", align 1, !dbg !55

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @bug_rust_alloc_c_free() #0 !dbg !79 {
entry:
  %ptr = alloca ptr, align 8
    #dbg_declare(ptr %ptr, !83, !DIExpression(), !84)
  %call = call ptr @rust_box_new(i32 noundef 42), !dbg !85
  store ptr %call, ptr %ptr, align 8, !dbg !84
  %0 = load ptr, ptr %ptr, align 8, !dbg !86
  call void @free(ptr noundef %0), !dbg !87
  ret void, !dbg !88
}

declare ptr @rust_box_new(i32 noundef) #1

declare void @free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @bug_c_alloc_cpp_delete() #0 !dbg !89 {
entry:
  %ptr = alloca ptr, align 8
    #dbg_declare(ptr %ptr, !90, !DIExpression(), !91)
  %call = call ptr @malloc(i64 noundef 128) #6, !dbg !92
  store ptr %call, ptr %ptr, align 8, !dbg !91
  %0 = load ptr, ptr %ptr, align 8, !dbg !93
  call void @cpp_delete_object(ptr noundef %0), !dbg !94
  ret void, !dbg !95
}

; Function Attrs: allocsize(0)
declare ptr @malloc(i64 noundef) #2

declare void @cpp_delete_object(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @safe_c_alloc_c_free() #0 !dbg !96 {
entry:
  %ptr = alloca ptr, align 8
    #dbg_declare(ptr %ptr, !97, !DIExpression(), !98)
  %call = call ptr @malloc(i64 noundef 64) #6, !dbg !99
  store ptr %call, ptr %ptr, align 8, !dbg !98
  %0 = load ptr, ptr %ptr, align 8, !dbg !100
  call void @free(ptr noundef %0), !dbg !101
  ret void, !dbg !102
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @safe_rust_alloc_rust_free() #0 !dbg !103 {
entry:
  %ptr = alloca ptr, align 8
    #dbg_declare(ptr %ptr, !104, !DIExpression(), !105)
  %call = call ptr @rust_box_new(i32 noundef 100), !dbg !106
  store ptr %call, ptr %ptr, align 8, !dbg !105
  %0 = load ptr, ptr %ptr, align 8, !dbg !107
  call void @rust_box_free(ptr noundef %0), !dbg !108
  ret void, !dbg !109
}

declare void @rust_box_free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @bug_alias_chain_cross_lang() #0 !dbg !110 {
entry:
  %ptr1 = alloca ptr, align 8
  %ptr2 = alloca ptr, align 8
    #dbg_declare(ptr %ptr1, !111, !DIExpression(), !112)
  %call = call ptr @rust_box_new(i32 noundef 999), !dbg !113
  store ptr %call, ptr %ptr1, align 8, !dbg !112
    #dbg_declare(ptr %ptr2, !114, !DIExpression(), !115)
  %0 = load ptr, ptr %ptr1, align 8, !dbg !116
  store ptr %0, ptr %ptr2, align 8, !dbg !115
  %1 = load ptr, ptr %ptr2, align 8, !dbg !117
  call void @free(ptr noundef %1), !dbg !118
  ret void, !dbg !119
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @bug_double_cross_lang() #0 !dbg !120 {
entry:
  %ptr1 = alloca ptr, align 8
  %ptr2 = alloca ptr, align 8
    #dbg_declare(ptr %ptr1, !121, !DIExpression(), !122)
  %call = call ptr @rust_box_new(i32 noundef 1), !dbg !123
  store ptr %call, ptr %ptr1, align 8, !dbg !122
    #dbg_declare(ptr %ptr2, !124, !DIExpression(), !125)
  %call1 = call ptr @cpp_new_object(i32 noundef 256), !dbg !126
  store ptr %call1, ptr %ptr2, align 8, !dbg !125
  %0 = load ptr, ptr %ptr1, align 8, !dbg !127
  call void @free(ptr noundef %0), !dbg !128
  %1 = load ptr, ptr %ptr2, align 8, !dbg !129
  call void @free(ptr noundef %1), !dbg !130
  ret void, !dbg !131
}

declare ptr @cpp_new_object(i32 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @bug_realloc_cross_lang() #0 !dbg !132 {
entry:
  %ptr = alloca ptr, align 8
  %new_ptr = alloca ptr, align 8
    #dbg_declare(ptr %ptr, !133, !DIExpression(), !134)
  %call = call ptr @rust_box_new(i32 noundef 50), !dbg !135
  store ptr %call, ptr %ptr, align 8, !dbg !134
    #dbg_declare(ptr %new_ptr, !136, !DIExpression(), !137)
  %0 = load ptr, ptr %ptr, align 8, !dbg !138
  %call1 = call ptr @realloc(ptr noundef %0, i64 noundef 100) #7, !dbg !139
  store ptr %call1, ptr %new_ptr, align 8, !dbg !137
  %1 = load ptr, ptr %new_ptr, align 8, !dbg !140
  %tobool = icmp ne ptr %1, null, !dbg !140
  br i1 %tobool, label %if.then, label %if.end, !dbg !142

if.then:                                          ; preds = %entry
  %2 = load ptr, ptr %new_ptr, align 8, !dbg !143
  call void @free(ptr noundef %2), !dbg !145
  br label %if.end, !dbg !146

if.end:                                           ; preds = %if.then, %entry
  ret void, !dbg !147
}

; Function Attrs: allocsize(1)
declare ptr @realloc(ptr noundef, i64 noundef) #3

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @edge_case_null_ptr() #0 !dbg !148 {
entry:
  %ptr = alloca ptr, align 8
    #dbg_declare(ptr %ptr, !149, !DIExpression(), !150)
  store ptr null, ptr %ptr, align 8, !dbg !150
  %0 = load ptr, ptr %ptr, align 8, !dbg !151
  call void @free(ptr noundef %0), !dbg !152
  ret void, !dbg !153
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @bug_stack_escape_cross_lang() #0 !dbg !154 {
entry:
  %local = alloca i32, align 4
  %ptr = alloca ptr, align 8
    #dbg_declare(ptr %local, !155, !DIExpression(), !156)
  store i32 42, ptr %local, align 4, !dbg !156
    #dbg_declare(ptr %ptr, !157, !DIExpression(), !159)
  store ptr %local, ptr %ptr, align 8, !dbg !159
  %0 = load ptr, ptr %ptr, align 8, !dbg !160
  call void @free(ptr noundef %0), !dbg !161
  ret void, !dbg !162
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @bug_mixed_ownership() #0 !dbg !163 {
entry:
  %ptr = alloca ptr, align 8
    #dbg_declare(ptr %ptr, !164, !DIExpression(), !165)
  %call = call ptr @rust_box_new(i32 noundef 777), !dbg !166
  store ptr %call, ptr %ptr, align 8, !dbg !165
  %0 = load ptr, ptr %ptr, align 8, !dbg !167
  %1 = load ptr, ptr %ptr, align 8, !dbg !167
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !167
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 0, i64 noundef 4, i64 noundef %2) #8, !dbg !167
  %3 = load ptr, ptr %ptr, align 8, !dbg !168
  call void @free(ptr noundef %3), !dbg !169
  ret void, !dbg !170
}

; Function Attrs: nounwind
declare ptr @__memset_chk(ptr noundef, i32 noundef, i64 noundef, i64 noundef) #4

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.objectsize.i64.p0(ptr, i1 immarg, i1 immarg, i1 immarg) #5

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @bug_nested_cross_lang() #0 !dbg !171 {
entry:
  %c = alloca ptr, align 8
    #dbg_declare(ptr %c, !172, !DIExpression(), !173)
  %call = call ptr @malloc(i64 noundef 16) #6, !dbg !174
  store ptr %call, ptr %c, align 8, !dbg !173
  %call1 = call ptr @rust_box_new(i32 noundef 123), !dbg !175
  %0 = load ptr, ptr %c, align 8, !dbg !176
  %inner_ptr = getelementptr inbounds %struct.Container, ptr %0, i32 0, i32 0, !dbg !177
  store ptr %call1, ptr %inner_ptr, align 8, !dbg !178
  %1 = load ptr, ptr %c, align 8, !dbg !179
  call void @free(ptr noundef %1), !dbg !180
  ret void, !dbg !181
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @main() #0 !dbg !182 {
entry:
  %retval = alloca i32, align 4
  store i32 0, ptr %retval, align 4
  %call = call i32 (ptr, ...) @printf(ptr noundef @.str), !dbg !185
  %call1 = call i32 (ptr, ...) @printf(ptr noundef @.str.1), !dbg !186
  %call2 = call i32 (ptr, ...) @printf(ptr noundef @.str.2), !dbg !187
  call void @bug_rust_alloc_c_free(), !dbg !188
  %call3 = call i32 (ptr, ...) @printf(ptr noundef @.str.3), !dbg !189
  call void @bug_c_alloc_cpp_delete(), !dbg !190
  %call4 = call i32 (ptr, ...) @printf(ptr noundef @.str.4), !dbg !191
  call void @safe_c_alloc_c_free(), !dbg !192
  call void @safe_rust_alloc_rust_free(), !dbg !193
  %call5 = call i32 (ptr, ...) @printf(ptr noundef @.str.5), !dbg !194
  call void @bug_alias_chain_cross_lang(), !dbg !195
  %call6 = call i32 (ptr, ...) @printf(ptr noundef @.str.6), !dbg !196
  call void @bug_double_cross_lang(), !dbg !197
  %call7 = call i32 (ptr, ...) @printf(ptr noundef @.str.7), !dbg !198
  call void @bug_realloc_cross_lang(), !dbg !199
  %call8 = call i32 (ptr, ...) @printf(ptr noundef @.str.8), !dbg !200
  call void @edge_case_null_ptr(), !dbg !201
  %call9 = call i32 (ptr, ...) @printf(ptr noundef @.str.9), !dbg !202
  call void @bug_stack_escape_cross_lang(), !dbg !203
  %call10 = call i32 (ptr, ...) @printf(ptr noundef @.str.10), !dbg !204
  call void @bug_mixed_ownership(), !dbg !205
  %call11 = call i32 (ptr, ...) @printf(ptr noundef @.str.11), !dbg !206
  call void @bug_nested_cross_lang(), !dbg !207
  %call12 = call i32 (ptr, ...) @printf(ptr noundef @.str.12), !dbg !208
  %call13 = call i32 (ptr, ...) @printf(ptr noundef @.str.13), !dbg !209
  ret i32 0, !dbg !210
}

declare i32 @printf(ptr noundef, ...) #1

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a,+zcm,+zcz" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a,+zcm,+zcz" }
attributes #2 = { allocsize(0) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a,+zcm,+zcz" }
attributes #3 = { allocsize(1) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a,+zcm,+zcz" }
attributes #4 = { nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a,+zcm,+zcz" }
attributes #5 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #6 = { allocsize(0) }
attributes #7 = { allocsize(1) }
attributes #8 = { nounwind }

!llvm.module.flags = !{!60, !61, !62, !63, !64, !65, !66}
!llvm.dbg.cu = !{!67}
!llvm.ident = !{!78}

!0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
!1 = distinct !DIGlobalVariable(scope: null, file: !2, line: 179, type: !3, isLocal: true, isDefinition: true)
!2 = !DIFile(filename: "corpus/red_team_test/cross_lang_free_bugs.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "b0aee5079d56d2ecdcafef0c850f5221")
!3 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 296, elements: !5)
!4 = !DIBasicType(name: "char", size: 8, encoding: DW_ATE_signed_char)
!5 = !{!6}
!6 = !DISubrange(count: 37)
!7 = !DIGlobalVariableExpression(var: !8, expr: !DIExpression())
!8 = distinct !DIGlobalVariable(scope: null, file: !2, line: 180, type: !9, isLocal: true, isDefinition: true)
!9 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 312, elements: !10)
!10 = !{!11}
!11 = !DISubrange(count: 39)
!12 = !DIGlobalVariableExpression(var: !13, expr: !DIExpression())
!13 = distinct !DIGlobalVariable(scope: null, file: !2, line: 182, type: !14, isLocal: true, isDefinition: true)
!14 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 248, elements: !15)
!15 = !{!16}
!16 = !DISubrange(count: 31)
!17 = !DIGlobalVariableExpression(var: !18, expr: !DIExpression())
!18 = distinct !DIGlobalVariable(scope: null, file: !2, line: 185, type: !19, isLocal: true, isDefinition: true)
!19 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 264, elements: !20)
!20 = !{!21}
!21 = !DISubrange(count: 33)
!22 = !DIGlobalVariableExpression(var: !23, expr: !DIExpression())
!23 = distinct !DIGlobalVariable(scope: null, file: !2, line: 188, type: !24, isLocal: true, isDefinition: true)
!24 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 320, elements: !25)
!25 = !{!26}
!26 = !DISubrange(count: 40)
!27 = !DIGlobalVariableExpression(var: !28, expr: !DIExpression())
!28 = distinct !DIGlobalVariable(scope: null, file: !2, line: 192, type: !3, isLocal: true, isDefinition: true)
!29 = !DIGlobalVariableExpression(var: !30, expr: !DIExpression())
!30 = distinct !DIGlobalVariable(scope: null, file: !2, line: 195, type: !31, isLocal: true, isDefinition: true)
!31 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 336, elements: !32)
!32 = !{!33}
!33 = !DISubrange(count: 42)
!34 = !DIGlobalVariableExpression(var: !35, expr: !DIExpression())
!35 = distinct !DIGlobalVariable(scope: null, file: !2, line: 198, type: !19, isLocal: true, isDefinition: true)
!36 = !DIGlobalVariableExpression(var: !37, expr: !DIExpression())
!37 = distinct !DIGlobalVariable(scope: null, file: !2, line: 201, type: !19, isLocal: true, isDefinition: true)
!38 = !DIGlobalVariableExpression(var: !39, expr: !DIExpression())
!39 = distinct !DIGlobalVariable(scope: null, file: !2, line: 204, type: !40, isLocal: true, isDefinition: true)
!40 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 288, elements: !41)
!41 = !{!42}
!42 = !DISubrange(count: 36)
!43 = !DIGlobalVariableExpression(var: !44, expr: !DIExpression())
!44 = distinct !DIGlobalVariable(scope: null, file: !2, line: 207, type: !45, isLocal: true, isDefinition: true)
!45 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 280, elements: !46)
!46 = !{!47}
!47 = !DISubrange(count: 35)
!48 = !DIGlobalVariableExpression(var: !49, expr: !DIExpression())
!49 = distinct !DIGlobalVariable(scope: null, file: !2, line: 210, type: !50, isLocal: true, isDefinition: true)
!50 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 232, elements: !51)
!51 = !{!52}
!52 = !DISubrange(count: 29)
!53 = !DIGlobalVariableExpression(var: !54, expr: !DIExpression())
!54 = distinct !DIGlobalVariable(scope: null, file: !2, line: 213, type: !9, isLocal: true, isDefinition: true)
!55 = !DIGlobalVariableExpression(var: !56, expr: !DIExpression())
!56 = distinct !DIGlobalVariable(scope: null, file: !2, line: 214, type: !57, isLocal: true, isDefinition: true)
!57 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 136, elements: !58)
!58 = !{!59}
!59 = !DISubrange(count: 17)
!60 = !{i32 2, !"SDK Version", [2 x i32] [i32 26, i32 2]}
!61 = !{i32 7, !"Dwarf Version", i32 5}
!62 = !{i32 2, !"Debug Info Version", i32 3}
!63 = !{i32 1, !"wchar_size", i32 4}
!64 = !{i32 8, !"PIC Level", i32 2}
!65 = !{i32 7, !"uwtable", i32 1}
!66 = !{i32 7, !"frame-pointer", i32 1}
!67 = distinct !DICompileUnit(language: DW_LANG_C11, file: !2, producer: "Apple clang version 17.0.0 (clang-1700.6.4.2)", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, retainedTypes: !68, globals: !77, splitDebugInlining: false, nameTableKind: Apple, sysroot: "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk", sdk: "MacOSX.sdk")
!68 = !{!69, !70}
!69 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!70 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !71, size: 64)
!71 = !DIDerivedType(tag: DW_TAG_typedef, name: "Container", file: !2, line: 158, baseType: !72)
!72 = distinct !DICompositeType(tag: DW_TAG_structure_type, file: !2, line: 155, size: 128, elements: !73)
!73 = !{!74, !75}
!74 = !DIDerivedType(tag: DW_TAG_member, name: "inner_ptr", scope: !72, file: !2, line: 156, baseType: !69, size: 64)
!75 = !DIDerivedType(tag: DW_TAG_member, name: "value", scope: !72, file: !2, line: 157, baseType: !76, size: 32, offset: 64)
!76 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!77 = !{!0, !7, !12, !17, !22, !27, !29, !34, !36, !38, !43, !48, !53, !55}
!78 = !{!"Apple clang version 17.0.0 (clang-1700.6.4.2)"}
!79 = distinct !DISubprogram(name: "bug_rust_alloc_c_free", scope: !2, file: !2, line: 28, type: !80, scopeLine: 28, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !67, retainedNodes: !82)
!80 = !DISubroutineType(types: !81)
!81 = !{null}
!82 = !{}
!83 = !DILocalVariable(name: "ptr", scope: !79, file: !2, line: 30, type: !69)
!84 = !DILocation(line: 30, column: 11, scope: !79)
!85 = !DILocation(line: 30, column: 17, scope: !79)
!86 = !DILocation(line: 33, column: 10, scope: !79)
!87 = !DILocation(line: 33, column: 5, scope: !79)
!88 = !DILocation(line: 36, column: 1, scope: !79)
!89 = distinct !DISubprogram(name: "bug_c_alloc_cpp_delete", scope: !2, file: !2, line: 41, type: !80, scopeLine: 41, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !67, retainedNodes: !82)
!90 = !DILocalVariable(name: "ptr", scope: !89, file: !2, line: 43, type: !69)
!91 = !DILocation(line: 43, column: 11, scope: !89)
!92 = !DILocation(line: 43, column: 17, scope: !89)
!93 = !DILocation(line: 46, column: 23, scope: !89)
!94 = !DILocation(line: 46, column: 5, scope: !89)
!95 = !DILocation(line: 49, column: 1, scope: !89)
!96 = distinct !DISubprogram(name: "safe_c_alloc_c_free", scope: !2, file: !2, line: 54, type: !80, scopeLine: 54, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !67, retainedNodes: !82)
!97 = !DILocalVariable(name: "ptr", scope: !96, file: !2, line: 55, type: !69)
!98 = !DILocation(line: 55, column: 11, scope: !96)
!99 = !DILocation(line: 55, column: 17, scope: !96)
!100 = !DILocation(line: 56, column: 10, scope: !96)
!101 = !DILocation(line: 56, column: 5, scope: !96)
!102 = !DILocation(line: 59, column: 1, scope: !96)
!103 = distinct !DISubprogram(name: "safe_rust_alloc_rust_free", scope: !2, file: !2, line: 61, type: !80, scopeLine: 61, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !67, retainedNodes: !82)
!104 = !DILocalVariable(name: "ptr", scope: !103, file: !2, line: 62, type: !69)
!105 = !DILocation(line: 62, column: 11, scope: !103)
!106 = !DILocation(line: 62, column: 17, scope: !103)
!107 = !DILocation(line: 63, column: 19, scope: !103)
!108 = !DILocation(line: 63, column: 5, scope: !103)
!109 = !DILocation(line: 66, column: 1, scope: !103)
!110 = distinct !DISubprogram(name: "bug_alias_chain_cross_lang", scope: !2, file: !2, line: 71, type: !80, scopeLine: 71, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !67, retainedNodes: !82)
!111 = !DILocalVariable(name: "ptr1", scope: !110, file: !2, line: 72, type: !69)
!112 = !DILocation(line: 72, column: 11, scope: !110)
!113 = !DILocation(line: 72, column: 18, scope: !110)
!114 = !DILocalVariable(name: "ptr2", scope: !110, file: !2, line: 73, type: !69)
!115 = !DILocation(line: 73, column: 11, scope: !110)
!116 = !DILocation(line: 73, column: 18, scope: !110)
!117 = !DILocation(line: 76, column: 10, scope: !110)
!118 = !DILocation(line: 76, column: 5, scope: !110)
!119 = !DILocation(line: 79, column: 1, scope: !110)
!120 = distinct !DISubprogram(name: "bug_double_cross_lang", scope: !2, file: !2, line: 84, type: !80, scopeLine: 84, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !67, retainedNodes: !82)
!121 = !DILocalVariable(name: "ptr1", scope: !120, file: !2, line: 85, type: !69)
!122 = !DILocation(line: 85, column: 11, scope: !120)
!123 = !DILocation(line: 85, column: 18, scope: !120)
!124 = !DILocalVariable(name: "ptr2", scope: !120, file: !2, line: 86, type: !69)
!125 = !DILocation(line: 86, column: 11, scope: !120)
!126 = !DILocation(line: 86, column: 18, scope: !120)
!127 = !DILocation(line: 89, column: 10, scope: !120)
!128 = !DILocation(line: 89, column: 5, scope: !120)
!129 = !DILocation(line: 92, column: 10, scope: !120)
!130 = !DILocation(line: 92, column: 5, scope: !120)
!131 = !DILocation(line: 95, column: 1, scope: !120)
!132 = distinct !DISubprogram(name: "bug_realloc_cross_lang", scope: !2, file: !2, line: 100, type: !80, scopeLine: 100, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !67, retainedNodes: !82)
!133 = !DILocalVariable(name: "ptr", scope: !132, file: !2, line: 101, type: !69)
!134 = !DILocation(line: 101, column: 11, scope: !132)
!135 = !DILocation(line: 101, column: 17, scope: !132)
!136 = !DILocalVariable(name: "new_ptr", scope: !132, file: !2, line: 104, type: !69)
!137 = !DILocation(line: 104, column: 11, scope: !132)
!138 = !DILocation(line: 104, column: 29, scope: !132)
!139 = !DILocation(line: 104, column: 21, scope: !132)
!140 = !DILocation(line: 106, column: 9, scope: !141)
!141 = distinct !DILexicalBlock(scope: !132, file: !2, line: 106, column: 9)
!142 = !DILocation(line: 106, column: 9, scope: !132)
!143 = !DILocation(line: 107, column: 14, scope: !144)
!144 = distinct !DILexicalBlock(scope: !141, file: !2, line: 106, column: 18)
!145 = !DILocation(line: 107, column: 9, scope: !144)
!146 = !DILocation(line: 108, column: 5, scope: !144)
!147 = !DILocation(line: 111, column: 1, scope: !132)
!148 = distinct !DISubprogram(name: "edge_case_null_ptr", scope: !2, file: !2, line: 116, type: !80, scopeLine: 116, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !67, retainedNodes: !82)
!149 = !DILocalVariable(name: "ptr", scope: !148, file: !2, line: 117, type: !69)
!150 = !DILocation(line: 117, column: 11, scope: !148)
!151 = !DILocation(line: 118, column: 10, scope: !148)
!152 = !DILocation(line: 118, column: 5, scope: !148)
!153 = !DILocation(line: 121, column: 1, scope: !148)
!154 = distinct !DISubprogram(name: "bug_stack_escape_cross_lang", scope: !2, file: !2, line: 126, type: !80, scopeLine: 126, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !67, retainedNodes: !82)
!155 = !DILocalVariable(name: "local", scope: !154, file: !2, line: 127, type: !76)
!156 = !DILocation(line: 127, column: 9, scope: !154)
!157 = !DILocalVariable(name: "ptr", scope: !154, file: !2, line: 128, type: !158)
!158 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !76, size: 64)
!159 = !DILocation(line: 128, column: 10, scope: !154)
!160 = !DILocation(line: 131, column: 10, scope: !154)
!161 = !DILocation(line: 131, column: 5, scope: !154)
!162 = !DILocation(line: 134, column: 1, scope: !154)
!163 = distinct !DISubprogram(name: "bug_mixed_ownership", scope: !2, file: !2, line: 139, type: !80, scopeLine: 139, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !67, retainedNodes: !82)
!164 = !DILocalVariable(name: "ptr", scope: !163, file: !2, line: 141, type: !69)
!165 = !DILocation(line: 141, column: 11, scope: !163)
!166 = !DILocation(line: 141, column: 17, scope: !163)
!167 = !DILocation(line: 144, column: 5, scope: !163)
!168 = !DILocation(line: 147, column: 10, scope: !163)
!169 = !DILocation(line: 147, column: 5, scope: !163)
!170 = !DILocation(line: 150, column: 1, scope: !163)
!171 = distinct !DISubprogram(name: "bug_nested_cross_lang", scope: !2, file: !2, line: 160, type: !80, scopeLine: 160, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !67, retainedNodes: !82)
!172 = !DILocalVariable(name: "c", scope: !171, file: !2, line: 161, type: !70)
!173 = !DILocation(line: 161, column: 16, scope: !171)
!174 = !DILocation(line: 161, column: 32, scope: !171)
!175 = !DILocation(line: 162, column: 20, scope: !171)
!176 = !DILocation(line: 162, column: 5, scope: !171)
!177 = !DILocation(line: 162, column: 8, scope: !171)
!178 = !DILocation(line: 162, column: 18, scope: !171)
!179 = !DILocation(line: 165, column: 10, scope: !171)
!180 = !DILocation(line: 165, column: 5, scope: !171)
!181 = !DILocation(line: 173, column: 1, scope: !171)
!182 = distinct !DISubprogram(name: "main", scope: !2, file: !2, line: 178, type: !183, scopeLine: 178, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !67)
!183 = !DISubroutineType(types: !184)
!184 = !{!76}
!185 = !DILocation(line: 179, column: 5, scope: !182)
!186 = !DILocation(line: 180, column: 5, scope: !182)
!187 = !DILocation(line: 182, column: 5, scope: !182)
!188 = !DILocation(line: 183, column: 5, scope: !182)
!189 = !DILocation(line: 185, column: 5, scope: !182)
!190 = !DILocation(line: 186, column: 5, scope: !182)
!191 = !DILocation(line: 188, column: 5, scope: !182)
!192 = !DILocation(line: 189, column: 5, scope: !182)
!193 = !DILocation(line: 190, column: 5, scope: !182)
!194 = !DILocation(line: 192, column: 5, scope: !182)
!195 = !DILocation(line: 193, column: 5, scope: !182)
!196 = !DILocation(line: 195, column: 5, scope: !182)
!197 = !DILocation(line: 196, column: 5, scope: !182)
!198 = !DILocation(line: 198, column: 5, scope: !182)
!199 = !DILocation(line: 199, column: 5, scope: !182)
!200 = !DILocation(line: 201, column: 5, scope: !182)
!201 = !DILocation(line: 202, column: 5, scope: !182)
!202 = !DILocation(line: 204, column: 5, scope: !182)
!203 = !DILocation(line: 205, column: 5, scope: !182)
!204 = !DILocation(line: 207, column: 5, scope: !182)
!205 = !DILocation(line: 208, column: 5, scope: !182)
!206 = !DILocation(line: 210, column: 5, scope: !182)
!207 = !DILocation(line: 211, column: 5, scope: !182)
!208 = !DILocation(line: 213, column: 5, scope: !182)
!209 = !DILocation(line: 214, column: 5, scope: !182)
!210 = !DILocation(line: 216, column: 5, scope: !182)
