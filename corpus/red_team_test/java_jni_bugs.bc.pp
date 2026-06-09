; ModuleID = './corpus/red_team_test/java_jni_bugs.c'
source_filename = "./corpus/red_team_test/java_jni_bugs.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

@.str = private unnamed_addr constant [18 x i8] c"global ref at %p\0A\00", align 1, !dbg !0
@.str.1 = private unnamed_addr constant [16 x i8] c"hello from Java\00", align 1, !dbg !7
@.str.2 = private unnamed_addr constant [12 x i8] c"string: %s\0A\00", align 1, !dbg !12
@.str.3 = private unnamed_addr constant [10 x i8] c"temporary\00", align 1, !dbg !17
@.str.4 = private unnamed_addr constant [14 x i8] c"released: %s\0A\00", align 1, !dbg !22
@.str.5 = private unnamed_addr constant [18 x i8] c"this may deadlock\00", align 1, !dbg !27
@g_c_struct_for_java = internal global ptr null, align 8, !dbg !29
@.str.6 = private unnamed_addr constant [5 x i8] c"test\00", align 1, !dbg !45

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @jni_01_global_ref_leak(ptr noundef %env) #0 !dbg !57 {
entry:
  %env.addr = alloca ptr, align 8
  %local_obj = alloca ptr, align 8
  %global = alloca ptr, align 8
  store ptr %env, ptr %env.addr, align 8
    #dbg_declare(ptr %env.addr, !65, !DIExpression(), !66)
    #dbg_declare(ptr %local_obj, !67, !DIExpression(), !69)
  store ptr null, ptr %local_obj, align 8, !dbg !69
    #dbg_declare(ptr %global, !70, !DIExpression(), !71)
  %0 = load ptr, ptr %env.addr, align 8, !dbg !72
  %1 = load ptr, ptr %local_obj, align 8, !dbg !73
  %call = call ptr @NewGlobalRef(ptr noundef %0, ptr noundef %1), !dbg !74
  store ptr %call, ptr %global, align 8, !dbg !71
  %2 = load ptr, ptr %global, align 8, !dbg !75
  %call1 = call i32 (ptr, ...) @printf(ptr noundef @.str, ptr noundef %2), !dbg !76
  ret void, !dbg !77
}

declare ptr @NewGlobalRef(ptr noundef, ptr noundef) #1

declare i32 @printf(ptr noundef, ...) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @jni_02_string_not_released(ptr noundef %env) #0 !dbg !78 {
entry:
  %env.addr = alloca ptr, align 8
  %jstr = alloca ptr, align 8
  %native_str = alloca ptr, align 8
  store ptr %env, ptr %env.addr, align 8
    #dbg_declare(ptr %env.addr, !79, !DIExpression(), !80)
    #dbg_declare(ptr %jstr, !81, !DIExpression(), !83)
  %0 = load ptr, ptr %env.addr, align 8, !dbg !84
  %call = call ptr @NewStringUTF(ptr noundef %0, ptr noundef @.str.1), !dbg !85
  store ptr %call, ptr %jstr, align 8, !dbg !83
    #dbg_declare(ptr %native_str, !86, !DIExpression(), !89)
  %1 = load ptr, ptr %env.addr, align 8, !dbg !90
  %2 = load ptr, ptr %jstr, align 8, !dbg !91
  %call1 = call ptr @GetStringUTFChars(ptr noundef %1, ptr noundef %2), !dbg !92
  store ptr %call1, ptr %native_str, align 8, !dbg !89
  %3 = load ptr, ptr %native_str, align 8, !dbg !93
  %call2 = call i32 (ptr, ...) @printf(ptr noundef @.str.2, ptr noundef %3), !dbg !94
  ret void, !dbg !95
}

declare ptr @NewStringUTF(ptr noundef, ptr noundef) #1

declare ptr @GetStringUTFChars(ptr noundef, ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @jni_03_use_after_release(ptr noundef %env) #0 !dbg !96 {
entry:
  %env.addr = alloca ptr, align 8
  %jstr = alloca ptr, align 8
  %native_str = alloca ptr, align 8
  %buf = alloca [64 x i8], align 1
  store ptr %env, ptr %env.addr, align 8
    #dbg_declare(ptr %env.addr, !97, !DIExpression(), !98)
    #dbg_declare(ptr %jstr, !99, !DIExpression(), !100)
  %0 = load ptr, ptr %env.addr, align 8, !dbg !101
  %call = call ptr @NewStringUTF(ptr noundef %0, ptr noundef @.str.3), !dbg !102
  store ptr %call, ptr %jstr, align 8, !dbg !100
    #dbg_declare(ptr %native_str, !103, !DIExpression(), !104)
  %1 = load ptr, ptr %env.addr, align 8, !dbg !105
  %2 = load ptr, ptr %jstr, align 8, !dbg !106
  %call1 = call ptr @GetStringUTFChars(ptr noundef %1, ptr noundef %2), !dbg !107
  store ptr %call1, ptr %native_str, align 8, !dbg !104
    #dbg_declare(ptr %buf, !108, !DIExpression(), !112)
  %arraydecay = getelementptr inbounds [64 x i8], ptr %buf, i64 0, i64 0, !dbg !113
  %3 = load ptr, ptr %native_str, align 8, !dbg !113
  %call2 = call ptr @__strcpy_chk(ptr noundef %arraydecay, ptr noundef %3, i64 noundef 64) #5, !dbg !113
  %4 = load ptr, ptr %env.addr, align 8, !dbg !114
  %5 = load ptr, ptr %jstr, align 8, !dbg !115
  %6 = load ptr, ptr %native_str, align 8, !dbg !116
  call void @ReleaseStringUTFChars(ptr noundef %4, ptr noundef %5, ptr noundef %6), !dbg !117
  %7 = load ptr, ptr %native_str, align 8, !dbg !118
  %call3 = call i32 (ptr, ...) @printf(ptr noundef @.str.4, ptr noundef %7), !dbg !119
  ret void, !dbg !120
}

; Function Attrs: nounwind
declare ptr @__strcpy_chk(ptr noundef, ptr noundef, i64 noundef) #2

declare void @ReleaseStringUTFChars(ptr noundef, ptr noundef, ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @jni_04_critical_section_violation(ptr noundef %env) #0 !dbg !121 {
entry:
  %env.addr = alloca ptr, align 8
  %arr = alloca ptr, align 8
  %pinned = alloca ptr, align 8
  %jstr = alloca ptr, align 8
  store ptr %env, ptr %env.addr, align 8
    #dbg_declare(ptr %env.addr, !122, !DIExpression(), !123)
    #dbg_declare(ptr %arr, !124, !DIExpression(), !126)
  store ptr null, ptr %arr, align 8, !dbg !126
    #dbg_declare(ptr %pinned, !127, !DIExpression(), !128)
  %0 = load ptr, ptr %env.addr, align 8, !dbg !129
  %1 = load ptr, ptr %arr, align 8, !dbg !130
  %call = call ptr @GetPrimitiveArrayCritical(ptr noundef %0, ptr noundef %1), !dbg !131
  store ptr %call, ptr %pinned, align 8, !dbg !128
    #dbg_declare(ptr %jstr, !132, !DIExpression(), !133)
  %2 = load ptr, ptr %env.addr, align 8, !dbg !134
  %call1 = call ptr @NewStringUTF(ptr noundef %2, ptr noundef @.str.5), !dbg !135
  store ptr %call1, ptr %jstr, align 8, !dbg !133
  %3 = load ptr, ptr %jstr, align 8, !dbg !136
  %4 = load ptr, ptr %env.addr, align 8, !dbg !137
  %5 = load ptr, ptr %arr, align 8, !dbg !138
  %6 = load ptr, ptr %pinned, align 8, !dbg !139
  call void @ReleasePrimitiveArrayCritical(ptr noundef %4, ptr noundef %5, ptr noundef %6), !dbg !140
  ret void, !dbg !141
}

declare ptr @GetPrimitiveArrayCritical(ptr noundef, ptr noundef) #1

declare void @ReleasePrimitiveArrayCritical(ptr noundef, ptr noundef, ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @jni_05_type_confusion(ptr noundef %env) #0 !dbg !142 {
entry:
  %env.addr = alloca ptr, align 8
  %byte_arr = alloca ptr, align 8
  %int_view = alloca ptr, align 8
  store ptr %env, ptr %env.addr, align 8
    #dbg_declare(ptr %env.addr, !143, !DIExpression(), !144)
    #dbg_declare(ptr %byte_arr, !145, !DIExpression(), !147)
  %0 = load ptr, ptr %env.addr, align 8, !dbg !148
  %call = call ptr @NewByteArray(ptr noundef %0, i32 noundef 16), !dbg !149
  store ptr %call, ptr %byte_arr, align 8, !dbg !147
    #dbg_declare(ptr %int_view, !150, !DIExpression(), !151)
  %1 = load ptr, ptr %env.addr, align 8, !dbg !152
  %2 = load ptr, ptr %byte_arr, align 8, !dbg !153
  %call1 = call ptr @GetByteArrayElements(ptr noundef %1, ptr noundef %2), !dbg !154
  store ptr %call1, ptr %int_view, align 8, !dbg !151
  %3 = load ptr, ptr %int_view, align 8, !dbg !155
  %arrayidx = getelementptr inbounds i32, ptr %3, i64 0, !dbg !155
  store i32 -559038737, ptr %arrayidx, align 4, !dbg !156
  %4 = load ptr, ptr %int_view, align 8, !dbg !157
  %arrayidx2 = getelementptr inbounds i32, ptr %4, i64 3, !dbg !157
  store i32 -889275714, ptr %arrayidx2, align 4, !dbg !158
  %5 = load ptr, ptr %env.addr, align 8, !dbg !159
  %6 = load ptr, ptr %byte_arr, align 8, !dbg !160
  %7 = load ptr, ptr %int_view, align 8, !dbg !161
  call void @ReleaseByteArrayElements(ptr noundef %5, ptr noundef %6, ptr noundef %7), !dbg !162
  ret void, !dbg !163
}

declare ptr @NewByteArray(ptr noundef, i32 noundef) #1

declare ptr @GetByteArrayElements(ptr noundef, ptr noundef) #1

declare void @ReleaseByteArrayElements(ptr noundef, ptr noundef, ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @jni_06_init_struct() #0 !dbg !164 {
entry:
  %call = call ptr @malloc(i64 noundef 256) #6, !dbg !167
  store ptr %call, ptr @g_c_struct_for_java, align 8, !dbg !168
  %0 = load ptr, ptr @g_c_struct_for_java, align 8, !dbg !169
  %1 = load ptr, ptr @g_c_struct_for_java, align 8, !dbg !169
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !169
  %call1 = call ptr @__memset_chk(ptr noundef %0, i32 noundef 0, i64 noundef 256, i64 noundef %2) #5, !dbg !169
  ret void, !dbg !170
}

; Function Attrs: allocsize(0)
declare ptr @malloc(i64 noundef) #3

; Function Attrs: nounwind
declare ptr @__memset_chk(ptr noundef, i32 noundef, i64 noundef, i64 noundef) #2

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.objectsize.i64.p0(ptr, i1 immarg, i1 immarg, i1 immarg) #4

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i64 @jni_06_get_handle() #0 !dbg !171 {
entry:
  %0 = load ptr, ptr @g_c_struct_for_java, align 8, !dbg !174
  %1 = ptrtoint ptr %0 to i64, !dbg !175
  ret i64 %1, !dbg !176
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @jni_06_cleanup_struct() #0 !dbg !177 {
entry:
  %0 = load ptr, ptr @g_c_struct_for_java, align 8, !dbg !178
  call void @free(ptr noundef %0), !dbg !179
  store ptr null, ptr @g_c_struct_for_java, align 8, !dbg !180
  ret void, !dbg !181
}

declare void @free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @jni_06_use_handle(i64 noundef %handle) #0 !dbg !182 {
entry:
  %handle.addr = alloca i64, align 8
  %ptr = alloca ptr, align 8
  store i64 %handle, ptr %handle.addr, align 8
    #dbg_declare(ptr %handle.addr, !185, !DIExpression(), !186)
    #dbg_declare(ptr %ptr, !187, !DIExpression(), !188)
  %0 = load i64, ptr %handle.addr, align 8, !dbg !189
  %1 = inttoptr i64 %0 to ptr, !dbg !190
  store ptr %1, ptr %ptr, align 8, !dbg !188
  %2 = load ptr, ptr %ptr, align 8, !dbg !191
  %3 = load ptr, ptr %ptr, align 8, !dbg !191
  %4 = call i64 @llvm.objectsize.i64.p0(ptr %3, i1 false, i1 true, i1 false), !dbg !191
  %call = call ptr @__memset_chk(ptr noundef %2, i32 noundef 255, i64 noundef 64, i64 noundef %4) #5, !dbg !191
  ret void, !dbg !192
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @jni_07_no_exception_check(ptr noundef %env) #0 !dbg !193 {
entry:
  %env.addr = alloca ptr, align 8
  %jstr = alloca ptr, align 8
  %chars = alloca ptr, align 8
  %buf = alloca [32 x i8], align 1
  store ptr %env, ptr %env.addr, align 8
    #dbg_declare(ptr %env.addr, !194, !DIExpression(), !195)
    #dbg_declare(ptr %jstr, !196, !DIExpression(), !197)
  %0 = load ptr, ptr %env.addr, align 8, !dbg !198
  %call = call ptr @NewStringUTF(ptr noundef %0, ptr noundef @.str.6), !dbg !199
  store ptr %call, ptr %jstr, align 8, !dbg !197
    #dbg_declare(ptr %chars, !200, !DIExpression(), !201)
  %1 = load ptr, ptr %env.addr, align 8, !dbg !202
  %2 = load ptr, ptr %jstr, align 8, !dbg !203
  %call1 = call ptr @GetStringUTFChars(ptr noundef %1, ptr noundef %2), !dbg !204
  store ptr %call1, ptr %chars, align 8, !dbg !201
    #dbg_declare(ptr %buf, !205, !DIExpression(), !209)
  %arraydecay = getelementptr inbounds [32 x i8], ptr %buf, i64 0, i64 0, !dbg !210
  %3 = load ptr, ptr %chars, align 8, !dbg !210
  %call2 = call ptr @__strcpy_chk(ptr noundef %arraydecay, ptr noundef %3, i64 noundef 32) #5, !dbg !210
  %4 = load ptr, ptr %env.addr, align 8, !dbg !211
  %5 = load ptr, ptr %jstr, align 8, !dbg !212
  %6 = load ptr, ptr %chars, align 8, !dbg !213
  call void @ReleaseStringUTFChars(ptr noundef %4, ptr noundef %5, ptr noundef %6), !dbg !214
  ret void, !dbg !215
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @jni_08_wrong_free(ptr noundef %env) #0 !dbg !216 {
entry:
  %env.addr = alloca ptr, align 8
  %arr = alloca ptr, align 8
  %elems = alloca ptr, align 8
  store ptr %env, ptr %env.addr, align 8
    #dbg_declare(ptr %env.addr, !217, !DIExpression(), !218)
    #dbg_declare(ptr %arr, !219, !DIExpression(), !220)
  %0 = load ptr, ptr %env.addr, align 8, !dbg !221
  %call = call ptr @NewByteArray(ptr noundef %0, i32 noundef 256), !dbg !222
  store ptr %call, ptr %arr, align 8, !dbg !220
    #dbg_declare(ptr %elems, !223, !DIExpression(), !224)
  %1 = load ptr, ptr %env.addr, align 8, !dbg !225
  %2 = load ptr, ptr %arr, align 8, !dbg !226
  %call1 = call ptr @GetByteArrayElements(ptr noundef %1, ptr noundef %2), !dbg !227
  store ptr %call1, ptr %elems, align 8, !dbg !224
  %3 = load ptr, ptr %elems, align 8, !dbg !228
  %4 = load ptr, ptr %elems, align 8, !dbg !228
  %5 = call i64 @llvm.objectsize.i64.p0(ptr %4, i1 false, i1 true, i1 false), !dbg !228
  %call2 = call ptr @__memset_chk(ptr noundef %3, i32 noundef 0, i64 noundef 256, i64 noundef %5) #5, !dbg !228
  %6 = load ptr, ptr %elems, align 8, !dbg !229
  call void @free(ptr noundef %6), !dbg !230
  ret void, !dbg !231
}

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { allocsize(0) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #4 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #5 = { nounwind }
attributes #6 = { allocsize(0) }

!llvm.dbg.cu = !{!31}
!llvm.module.flags = !{!50, !51, !52, !53, !54, !55}
!llvm.ident = !{!56}

!0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
!1 = distinct !DIGlobalVariable(scope: null, file: !2, line: 47, type: !3, isLocal: true, isDefinition: true)
!2 = !DIFile(filename: "./corpus/red_team_test/java_jni_bugs.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "f368b3450261bfc5dedba6d58efe59f8")
!3 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 144, elements: !5)
!4 = !DIBasicType(name: "char", size: 8, encoding: DW_ATE_signed_char)
!5 = !{!6}
!6 = !DISubrange(count: 18)
!7 = !DIGlobalVariableExpression(var: !8, expr: !DIExpression())
!8 = distinct !DIGlobalVariable(scope: null, file: !2, line: 56, type: !9, isLocal: true, isDefinition: true)
!9 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 128, elements: !10)
!10 = !{!11}
!11 = !DISubrange(count: 16)
!12 = !DIGlobalVariableExpression(var: !13, expr: !DIExpression())
!13 = distinct !DIGlobalVariable(scope: null, file: !2, line: 58, type: !14, isLocal: true, isDefinition: true)
!14 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 96, elements: !15)
!15 = !{!16}
!16 = !DISubrange(count: 12)
!17 = !DIGlobalVariableExpression(var: !18, expr: !DIExpression())
!18 = distinct !DIGlobalVariable(scope: null, file: !2, line: 68, type: !19, isLocal: true, isDefinition: true)
!19 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 80, elements: !20)
!20 = !{!21}
!21 = !DISubrange(count: 10)
!22 = !DIGlobalVariableExpression(var: !23, expr: !DIExpression())
!23 = distinct !DIGlobalVariable(scope: null, file: !2, line: 76, type: !24, isLocal: true, isDefinition: true)
!24 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 112, elements: !25)
!25 = !{!26}
!26 = !DISubrange(count: 14)
!27 = !DIGlobalVariableExpression(var: !28, expr: !DIExpression())
!28 = distinct !DIGlobalVariable(scope: null, file: !2, line: 90, type: !3, isLocal: true, isDefinition: true)
!29 = !DIGlobalVariableExpression(var: !30, expr: !DIExpression())
!30 = distinct !DIGlobalVariable(name: "g_c_struct_for_java", scope: !31, file: !2, line: 116, type: !34, isLocal: true, isDefinition: true)
!31 = distinct !DICompileUnit(language: DW_LANG_C11, file: !32, producer: "Homebrew clang version 21.1.8", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, retainedTypes: !33, globals: !44, splitDebugInlining: false, nameTableKind: Apple, sysroot: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk", sdk: "MacOSX15.sdk")
!32 = !DIFile(filename: "corpus/red_team_test/java_jni_bugs.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "f368b3450261bfc5dedba6d58efe59f8")
!33 = !{!34, !35, !38, !40}
!34 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!35 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !36, size: 64)
!36 = !DIDerivedType(tag: DW_TAG_typedef, name: "jint", file: !2, line: 20, baseType: !37)
!37 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!38 = !DIDerivedType(tag: DW_TAG_typedef, name: "jlong", file: !2, line: 21, baseType: !39)
!39 = !DIBasicType(name: "long", size: 64, encoding: DW_ATE_signed)
!40 = !DIDerivedType(tag: DW_TAG_typedef, name: "intptr_t", file: !41, line: 32, baseType: !42)
!41 = !DIFile(filename: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk/usr/include/sys/_types/_intptr_t.h", directory: "", checksumkind: CSK_MD5, checksum: "e478ba47270923b1cca6659f19f02db1")
!42 = !DIDerivedType(tag: DW_TAG_typedef, name: "__darwin_intptr_t", file: !43, line: 40, baseType: !39)
!43 = !DIFile(filename: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk/usr/include/arm/_types.h", directory: "", checksumkind: CSK_MD5, checksum: "b270144f57ae258d0ce80b8f87be068c")
!44 = !{!0, !7, !12, !17, !22, !27, !45, !29}
!45 = !DIGlobalVariableExpression(var: !46, expr: !DIExpression())
!46 = distinct !DIGlobalVariable(scope: null, file: !2, line: 145, type: !47, isLocal: true, isDefinition: true)
!47 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 40, elements: !48)
!48 = !{!49}
!49 = !DISubrange(count: 5)
!50 = !{i32 7, !"Dwarf Version", i32 5}
!51 = !{i32 2, !"Debug Info Version", i32 3}
!52 = !{i32 1, !"wchar_size", i32 4}
!53 = !{i32 8, !"PIC Level", i32 2}
!54 = !{i32 7, !"uwtable", i32 1}
!55 = !{i32 7, !"frame-pointer", i32 1}
!56 = !{!"Homebrew clang version 21.1.8"}
!57 = distinct !DISubprogram(name: "jni_01_global_ref_leak", scope: !2, file: !2, line: 43, type: !58, scopeLine: 43, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !31, retainedNodes: !64)
!58 = !DISubroutineType(types: !59)
!59 = !{null, !60}
!60 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !61, size: 64)
!61 = !DIDerivedType(tag: DW_TAG_typedef, name: "JNIEnv", file: !2, line: 23, baseType: !62)
!62 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !63, size: 64)
!63 = !DICompositeType(tag: DW_TAG_structure_type, name: "JNINativeInterface_", file: !2, line: 23, flags: DIFlagFwdDecl)
!64 = !{}
!65 = !DILocalVariable(name: "env", arg: 1, scope: !57, file: !2, line: 43, type: !60)
!66 = !DILocation(line: 43, column: 37, scope: !57)
!67 = !DILocalVariable(name: "local_obj", scope: !57, file: !2, line: 44, type: !68)
!68 = !DIDerivedType(tag: DW_TAG_typedef, name: "jobject", file: !2, line: 16, baseType: !34)
!69 = !DILocation(line: 44, column: 13, scope: !57)
!70 = !DILocalVariable(name: "global", scope: !57, file: !2, line: 45, type: !68)
!71 = !DILocation(line: 45, column: 13, scope: !57)
!72 = !DILocation(line: 45, column: 35, scope: !57)
!73 = !DILocation(line: 45, column: 40, scope: !57)
!74 = !DILocation(line: 45, column: 22, scope: !57)
!75 = !DILocation(line: 47, column: 34, scope: !57)
!76 = !DILocation(line: 47, column: 5, scope: !57)
!77 = !DILocation(line: 48, column: 1, scope: !57)
!78 = distinct !DISubprogram(name: "jni_02_string_not_released", scope: !2, file: !2, line: 55, type: !58, scopeLine: 55, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !31, retainedNodes: !64)
!79 = !DILocalVariable(name: "env", arg: 1, scope: !78, file: !2, line: 55, type: !60)
!80 = !DILocation(line: 55, column: 41, scope: !78)
!81 = !DILocalVariable(name: "jstr", scope: !78, file: !2, line: 56, type: !82)
!82 = !DIDerivedType(tag: DW_TAG_typedef, name: "jstring", file: !2, line: 17, baseType: !34)
!83 = !DILocation(line: 56, column: 13, scope: !78)
!84 = !DILocation(line: 56, column: 33, scope: !78)
!85 = !DILocation(line: 56, column: 20, scope: !78)
!86 = !DILocalVariable(name: "native_str", scope: !78, file: !2, line: 57, type: !87)
!87 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !88, size: 64)
!88 = !DIDerivedType(tag: DW_TAG_const_type, baseType: !4)
!89 = !DILocation(line: 57, column: 17, scope: !78)
!90 = !DILocation(line: 57, column: 48, scope: !78)
!91 = !DILocation(line: 57, column: 53, scope: !78)
!92 = !DILocation(line: 57, column: 30, scope: !78)
!93 = !DILocation(line: 58, column: 28, scope: !78)
!94 = !DILocation(line: 58, column: 5, scope: !78)
!95 = !DILocation(line: 60, column: 1, scope: !78)
!96 = distinct !DISubprogram(name: "jni_03_use_after_release", scope: !2, file: !2, line: 67, type: !58, scopeLine: 67, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !31, retainedNodes: !64)
!97 = !DILocalVariable(name: "env", arg: 1, scope: !96, file: !2, line: 67, type: !60)
!98 = !DILocation(line: 67, column: 39, scope: !96)
!99 = !DILocalVariable(name: "jstr", scope: !96, file: !2, line: 68, type: !82)
!100 = !DILocation(line: 68, column: 13, scope: !96)
!101 = !DILocation(line: 68, column: 33, scope: !96)
!102 = !DILocation(line: 68, column: 20, scope: !96)
!103 = !DILocalVariable(name: "native_str", scope: !96, file: !2, line: 69, type: !87)
!104 = !DILocation(line: 69, column: 17, scope: !96)
!105 = !DILocation(line: 69, column: 48, scope: !96)
!106 = !DILocation(line: 69, column: 53, scope: !96)
!107 = !DILocation(line: 69, column: 30, scope: !96)
!108 = !DILocalVariable(name: "buf", scope: !96, file: !2, line: 70, type: !109)
!109 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 512, elements: !110)
!110 = !{!111}
!111 = !DISubrange(count: 64)
!112 = !DILocation(line: 70, column: 10, scope: !96)
!113 = !DILocation(line: 71, column: 5, scope: !96)
!114 = !DILocation(line: 73, column: 27, scope: !96)
!115 = !DILocation(line: 73, column: 32, scope: !96)
!116 = !DILocation(line: 73, column: 38, scope: !96)
!117 = !DILocation(line: 73, column: 5, scope: !96)
!118 = !DILocation(line: 76, column: 30, scope: !96)
!119 = !DILocation(line: 76, column: 5, scope: !96)
!120 = !DILocation(line: 77, column: 1, scope: !96)
!121 = distinct !DISubprogram(name: "jni_04_critical_section_violation", scope: !2, file: !2, line: 85, type: !58, scopeLine: 85, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !31, retainedNodes: !64)
!122 = !DILocalVariable(name: "env", arg: 1, scope: !121, file: !2, line: 85, type: !60)
!123 = !DILocation(line: 85, column: 48, scope: !121)
!124 = !DILocalVariable(name: "arr", scope: !121, file: !2, line: 86, type: !125)
!125 = !DIDerivedType(tag: DW_TAG_typedef, name: "jarray", file: !2, line: 18, baseType: !34)
!126 = !DILocation(line: 86, column: 12, scope: !121)
!127 = !DILocalVariable(name: "pinned", scope: !121, file: !2, line: 87, type: !34)
!128 = !DILocation(line: 87, column: 11, scope: !121)
!129 = !DILocation(line: 87, column: 46, scope: !121)
!130 = !DILocation(line: 87, column: 51, scope: !121)
!131 = !DILocation(line: 87, column: 20, scope: !121)
!132 = !DILocalVariable(name: "jstr", scope: !121, file: !2, line: 90, type: !82)
!133 = !DILocation(line: 90, column: 13, scope: !121)
!134 = !DILocation(line: 90, column: 33, scope: !121)
!135 = !DILocation(line: 90, column: 20, scope: !121)
!136 = !DILocation(line: 91, column: 11, scope: !121)
!137 = !DILocation(line: 93, column: 35, scope: !121)
!138 = !DILocation(line: 93, column: 40, scope: !121)
!139 = !DILocation(line: 93, column: 45, scope: !121)
!140 = !DILocation(line: 93, column: 5, scope: !121)
!141 = !DILocation(line: 94, column: 1, scope: !121)
!142 = distinct !DISubprogram(name: "jni_05_type_confusion", scope: !2, file: !2, line: 101, type: !58, scopeLine: 101, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !31, retainedNodes: !64)
!143 = !DILocalVariable(name: "env", arg: 1, scope: !142, file: !2, line: 101, type: !60)
!144 = !DILocation(line: 101, column: 36, scope: !142)
!145 = !DILocalVariable(name: "byte_arr", scope: !142, file: !2, line: 102, type: !146)
!146 = !DIDerivedType(tag: DW_TAG_typedef, name: "jbyteArray", file: !2, line: 19, baseType: !34)
!147 = !DILocation(line: 102, column: 16, scope: !142)
!148 = !DILocation(line: 102, column: 40, scope: !142)
!149 = !DILocation(line: 102, column: 27, scope: !142)
!150 = !DILocalVariable(name: "int_view", scope: !142, file: !2, line: 104, type: !35)
!151 = !DILocation(line: 104, column: 11, scope: !142)
!152 = !DILocation(line: 104, column: 50, scope: !142)
!153 = !DILocation(line: 104, column: 55, scope: !142)
!154 = !DILocation(line: 104, column: 29, scope: !142)
!155 = !DILocation(line: 105, column: 5, scope: !142)
!156 = !DILocation(line: 105, column: 17, scope: !142)
!157 = !DILocation(line: 106, column: 5, scope: !142)
!158 = !DILocation(line: 106, column: 17, scope: !142)
!159 = !DILocation(line: 107, column: 30, scope: !142)
!160 = !DILocation(line: 107, column: 35, scope: !142)
!161 = !DILocation(line: 107, column: 45, scope: !142)
!162 = !DILocation(line: 107, column: 5, scope: !142)
!163 = !DILocation(line: 108, column: 1, scope: !142)
!164 = distinct !DISubprogram(name: "jni_06_init_struct", scope: !2, file: !2, line: 118, type: !165, scopeLine: 118, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !31)
!165 = !DISubroutineType(types: !166)
!166 = !{null}
!167 = !DILocation(line: 119, column: 27, scope: !164)
!168 = !DILocation(line: 119, column: 25, scope: !164)
!169 = !DILocation(line: 120, column: 5, scope: !164)
!170 = !DILocation(line: 121, column: 1, scope: !164)
!171 = distinct !DISubprogram(name: "jni_06_get_handle", scope: !2, file: !2, line: 123, type: !172, scopeLine: 123, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !31)
!172 = !DISubroutineType(types: !173)
!173 = !{!38}
!174 = !DILocation(line: 124, column: 29, scope: !171)
!175 = !DILocation(line: 124, column: 19, scope: !171)
!176 = !DILocation(line: 124, column: 5, scope: !171)
!177 = distinct !DISubprogram(name: "jni_06_cleanup_struct", scope: !2, file: !2, line: 127, type: !165, scopeLine: 127, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !31)
!178 = !DILocation(line: 128, column: 10, scope: !177)
!179 = !DILocation(line: 128, column: 5, scope: !177)
!180 = !DILocation(line: 129, column: 25, scope: !177)
!181 = !DILocation(line: 130, column: 1, scope: !177)
!182 = distinct !DISubprogram(name: "jni_06_use_handle", scope: !2, file: !2, line: 132, type: !183, scopeLine: 132, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !31, retainedNodes: !64)
!183 = !DISubroutineType(types: !184)
!184 = !{null, !38}
!185 = !DILocalVariable(name: "handle", arg: 1, scope: !182, file: !2, line: 132, type: !38)
!186 = !DILocation(line: 132, column: 30, scope: !182)
!187 = !DILocalVariable(name: "ptr", scope: !182, file: !2, line: 134, type: !34)
!188 = !DILocation(line: 134, column: 11, scope: !182)
!189 = !DILocation(line: 134, column: 34, scope: !182)
!190 = !DILocation(line: 134, column: 17, scope: !182)
!191 = !DILocation(line: 135, column: 5, scope: !182)
!192 = !DILocation(line: 136, column: 1, scope: !182)
!193 = distinct !DISubprogram(name: "jni_07_no_exception_check", scope: !2, file: !2, line: 144, type: !58, scopeLine: 144, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !31, retainedNodes: !64)
!194 = !DILocalVariable(name: "env", arg: 1, scope: !193, file: !2, line: 144, type: !60)
!195 = !DILocation(line: 144, column: 40, scope: !193)
!196 = !DILocalVariable(name: "jstr", scope: !193, file: !2, line: 145, type: !82)
!197 = !DILocation(line: 145, column: 13, scope: !193)
!198 = !DILocation(line: 145, column: 33, scope: !193)
!199 = !DILocation(line: 145, column: 20, scope: !193)
!200 = !DILocalVariable(name: "chars", scope: !193, file: !2, line: 146, type: !87)
!201 = !DILocation(line: 146, column: 17, scope: !193)
!202 = !DILocation(line: 146, column: 43, scope: !193)
!203 = !DILocation(line: 146, column: 48, scope: !193)
!204 = !DILocation(line: 146, column: 25, scope: !193)
!205 = !DILocalVariable(name: "buf", scope: !193, file: !2, line: 149, type: !206)
!206 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 256, elements: !207)
!207 = !{!208}
!208 = !DISubrange(count: 32)
!209 = !DILocation(line: 149, column: 10, scope: !193)
!210 = !DILocation(line: 150, column: 5, scope: !193)
!211 = !DILocation(line: 151, column: 27, scope: !193)
!212 = !DILocation(line: 151, column: 32, scope: !193)
!213 = !DILocation(line: 151, column: 38, scope: !193)
!214 = !DILocation(line: 151, column: 5, scope: !193)
!215 = !DILocation(line: 152, column: 1, scope: !193)
!216 = distinct !DISubprogram(name: "jni_08_wrong_free", scope: !2, file: !2, line: 160, type: !58, scopeLine: 160, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !31, retainedNodes: !64)
!217 = !DILocalVariable(name: "env", arg: 1, scope: !216, file: !2, line: 160, type: !60)
!218 = !DILocation(line: 160, column: 32, scope: !216)
!219 = !DILocalVariable(name: "arr", scope: !216, file: !2, line: 161, type: !146)
!220 = !DILocation(line: 161, column: 16, scope: !216)
!221 = !DILocation(line: 161, column: 35, scope: !216)
!222 = !DILocation(line: 161, column: 22, scope: !216)
!223 = !DILocalVariable(name: "elems", scope: !216, file: !2, line: 162, type: !34)
!224 = !DILocation(line: 162, column: 11, scope: !216)
!225 = !DILocation(line: 162, column: 40, scope: !216)
!226 = !DILocation(line: 162, column: 45, scope: !216)
!227 = !DILocation(line: 162, column: 19, scope: !216)
!228 = !DILocation(line: 163, column: 5, scope: !216)
!229 = !DILocation(line: 165, column: 10, scope: !216)
!230 = !DILocation(line: 165, column: 5, scope: !216)
!231 = !DILocation(line: 166, column: 1, scope: !216)
