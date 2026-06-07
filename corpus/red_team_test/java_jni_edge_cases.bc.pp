; ModuleID = 'corpus/red_team_test/java_jni_edge_cases.c'
source_filename = "corpus/red_team_test/java_jni_edge_cases.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

@.str = private unnamed_addr constant [16 x i8] c"com/example/Foo\00", align 1, !dbg !0
@.str.1 = private unnamed_addr constant [6 x i8] c"value\00", align 1, !dbg !7
@.str.2 = private unnamed_addr constant [12 x i8] c"string: %s\0A\00", align 1, !dbg !12
@.str.3 = private unnamed_addr constant [10 x i8] c"critical\0A\00", align 1, !dbg !17
@.str.4 = private unnamed_addr constant [12 x i8] c"monitor %d\0A\00", align 1, !dbg !22
@.str.5 = private unnamed_addr constant [14 x i8] c"after detach\0A\00", align 1, !dbg !27
@.str.6 = private unnamed_addr constant [10 x i8] c"weak_ref\0A\00", align 1, !dbg !32
@.str.7 = private unnamed_addr constant [8 x i8] c"Thread\0A\00", align 1, !dbg !37
@.str.8 = private unnamed_addr constant [10 x i8] c"callback\0A\00", align 1, !dbg !42
@.str.9 = private unnamed_addr constant [12 x i8] c"post-exc %d\0A\00", align 1, !dbg !47
@g_cached_local_ref = internal global ptr null, align 8, !dbg !52
@g_native_weak = internal global ptr null, align 8, !dbg !59

; --- Test 1: Local ref overflow ---
; Loop creates local refs via NewStringUTF without DeleteLocalRef.
; JNI local ref table has a ~512 entry limit; loop exceeds it -> crash.
define void @jni_01_local_ref_overflow(ptr noundef %env) #0 !dbg !66 {
entry:
  %env.addr = alloca ptr, align 8
  %i = alloca i32, align 4
  %jstr = alloca ptr, align 8
  store ptr %env, ptr %env.addr, align 8
    #dbg_declare(ptr %env.addr, !74, !DIExpression(), !75)
    #dbg_declare(ptr %i, !76, !DIExpression(), !77)
  store i32 0, ptr %i, align 4, !dbg !77
  br label %for.cond, !dbg !78

for.cond:
  %0 = load i32, ptr %i, align 4, !dbg !79
  %cmp = icmp slt i32 %0, 1024, !dbg !80
  br i1 %cmp, label %for.body, label %for.end, !dbg !81

for.body:
    #dbg_declare(ptr %jstr, !82, !DIExpression(), !83)
  %1 = load ptr, ptr %env.addr, align 8, !dbg !84
  %call = call ptr @NewStringUTF(ptr noundef %1, ptr noundef @.str), !dbg !85
  store ptr %call, ptr %jstr, align 8, !dbg !83
  ; BUG: missing DeleteLocalRef(env, jstr) -> local ref table overflow
  %2 = load i32, ptr %i, align 4, !dbg !86
  %add = add nsw i32 %2, 1, !dbg !86
  store i32 %add, ptr %i, align 4, !dbg !86
  br label %for.cond, !dbg !87

for.end:
  ret void, !dbg !88
}

; --- Test 2: Global ref leak ---
; NewGlobalRef in initialization, never calls DeleteGlobalRef.
; The global ref permanently prevents GC of the Java object.
define void @jni_02_global_ref_leak(ptr noundef %env) #0 !dbg !89 {
entry:
  %env.addr = alloca ptr, align 8
  %cls = alloca ptr, align 8
  %local_obj = alloca ptr, align 8
  %global_obj = alloca ptr, align 8
  store ptr %env, ptr %env.addr, align 8
    #dbg_declare(ptr %env.addr, !93, !DIExpression(), !94)
    #dbg_declare(ptr %cls, !95, !DIExpression(), !96)
  %0 = load ptr, ptr %env.addr, align 8, !dbg !97
  %call = call ptr @FindClass(ptr noundef %0, ptr noundef @.str), !dbg !98
  store ptr %call, ptr %cls, align 8, !dbg !96
    #dbg_declare(ptr %local_obj, !99, !DIExpression(), !100)
  %1 = load ptr, ptr %env.addr, align 8, !dbg !101
  %2 = load ptr, ptr %cls, align 8, !dbg !102
  %call1 = call ptr @AllocObject(ptr noundef %1, ptr noundef %2), !dbg !103
  store ptr %call1, ptr %local_obj, align 8, !dbg !100
    #dbg_declare(ptr %global_obj, !104, !DIExpression(), !105)
  %3 = load ptr, ptr %env.addr, align 8, !dbg !106
  %4 = load ptr, ptr %local_obj, align 8, !dbg !107
  %call2 = call ptr @NewGlobalRef(ptr noundef %3, ptr noundef %4), !dbg !108
  store ptr %call2, ptr %global_obj, align 8, !dbg !105
  ; BUG: global_obj is never freed with DeleteGlobalRef -> permanent leak
  ret void, !dbg !109
}

; --- Test 3: GetStringUTFChars not released ---
; GetStringUTFChars pins native memory. Without ReleaseStringUTFChars,
; the JVM cannot reclaim the native copy -> native string leak.
define void @jni_03_string_not_released(ptr noundef %env) #0 !dbg !110 {
entry:
  %env.addr = alloca ptr, align 8
  %jstr = alloca ptr, align 8
  %native = alloca ptr, align 8
  store ptr %env, ptr %env.addr, align 8
    #dbg_declare(ptr %env.addr, !114, !DIExpression(), !115)
    #dbg_declare(ptr %jstr, !116, !DIExpression(), !117)
  %0 = load ptr, ptr %env.addr, align 8, !dbg !118
  %call = call ptr @NewStringUTF(ptr noundef %0, ptr noundef @.str.1), !dbg !119
  store ptr %call, ptr %jstr, align 8, !dbg !117
    #dbg_declare(ptr %native, !120, !DIExpression(), !121)
  %1 = load ptr, ptr %env.addr, align 8, !dbg !122
  %2 = load ptr, ptr %jstr, align 8, !dbg !123
  %call1 = call ptr @GetStringUTFChars(ptr noundef %1, ptr noundef %2), !dbg !124
  store ptr %call1, ptr %native, align 8, !dbg !121
  ; Use the native string
  %3 = load ptr, ptr %native, align 8, !dbg !125
  %call2 = call i32 (ptr, ...) @printf(ptr noundef @.str.2, ptr noundef %3), !dbg !126
  ; BUG: missing ReleaseStringUTFChars(env, jstr, native) -> native string leak
  ret void, !dbg !127
}

; --- Test 4: Critical section + JNI call ---
; GetPrimitiveArrayCritical enters a critical section (may block GC).
; Calling NewStringUTF while holding the critical section can deadlock
; the JVM since the GC cannot proceed.
define void @jni_04_critical_section_jni_call(ptr noundef %env) #0 !dbg !128 {
entry:
  %env.addr = alloca ptr, align 8
  %arr = alloca ptr, align 8
  %pinned = alloca ptr, align 8
  %jstr = alloca ptr, align 8
  store ptr %env, ptr %env.addr, align 8
    #dbg_declare(ptr %env.addr, !132, !DIExpression(), !133)
    #dbg_declare(ptr %arr, !134, !DIExpression(), !135)
  %0 = load ptr, ptr %env.addr, align 8, !dbg !136
  %call = call ptr @NewByteArray(ptr noundef %0, i32 noundef 64), !dbg !137
  store ptr %call, ptr %arr, align 8, !dbg !135
    #dbg_declare(ptr %pinned, !138, !DIExpression(), !139)
  %1 = load ptr, ptr %env.addr, align 8, !dbg !140
  %2 = load ptr, ptr %arr, align 8, !dbg !141
  %call1 = call ptr @GetPrimitiveArrayCritical(ptr noundef %1, ptr noundef %2), !dbg !142
  store ptr %call1, ptr %pinned, align 8, !dbg !139
  ; BUG: calling JNI function while holding critical section -> potential deadlock
    #dbg_declare(ptr %jstr, !143, !DIExpression(), !144)
  %3 = load ptr, ptr %env.addr, align 8, !dbg !145
  %call2 = call ptr @NewStringUTF(ptr noundef %3, ptr noundef @.str.3), !dbg !146
  store ptr %call2, ptr %jstr, align 8, !dbg !144
  ; Release critical section
  %4 = load ptr, ptr %env.addr, align 8, !dbg !147
  %5 = load ptr, ptr %arr, align 8, !dbg !148
  %6 = load ptr, ptr %pinned, align 8, !dbg !149
  call void @ReleasePrimitiveArrayCritical(ptr noundef %4, ptr noundef %5, ptr noundef %6), !dbg !150
  ret void, !dbg !151
}

; --- Test 5: MonitorEnter + exception ---
; MonitorEnter can fail (returns non-zero on error). Code proceeds to
; access shared state without checking the return value -> race condition.
define void @jni_05_monitor_enter_exception(ptr noundef %env, ptr noundef %lock_obj) #0 !dbg !152 {
entry:
  %env.addr = alloca ptr, align 8
  %lock_obj.addr = alloca ptr, align 8
  %rc = alloca i32, align 4
  store ptr %env, ptr %env.addr, align 8
  store ptr %lock_obj, ptr %lock_obj.addr, align 8
    #dbg_declare(ptr %env.addr, !156, !DIExpression(), !157)
    #dbg_declare(ptr %lock_obj.addr, !158, !DIExpression(), !159)
    #dbg_declare(ptr %rc, !160, !DIExpression(), !161)
  %0 = load ptr, ptr %env.addr, align 8, !dbg !162
  %1 = load ptr, ptr %lock_obj.addr, align 8, !dbg !163
  %call = call i32 @MonitorEnter(ptr noundef %0, ptr noundef %1), !dbg !164
  store i32 %call, ptr %rc, align 4, !dbg !161
  ; BUG: no check of rc != 0. If MonitorEnter failed, we proceed without lock.
  ; Access shared state without valid lock
  %2 = load i32, ptr %rc, align 4, !dbg !165
  %call1 = call i32 (ptr, ...) @printf(ptr noundef @.str.4, i32 noundef %2), !dbg !166
  ; MonitorExit -- may also fail or be invalid
  %3 = load ptr, ptr %env.addr, align 8, !dbg !167
  %4 = load ptr, ptr %lock_obj.addr, align 8, !dbg !168
  %call2 = call i32 @MonitorExit(ptr noundef %3, ptr noundef %4), !dbg !169
  ret void, !dbg !170
}

; --- Test 6: FindClass after thread detach ---
; Thread calls DetachCurrentThread, then tries FindClass. JNIEnv is
; invalidated after detach -> crash / undefined behavior.
define void @jni_06_findclass_after_detach(ptr noundef %env) #0 !dbg !171 {
entry:
  %env.addr = alloca ptr, align 8
  %cls = alloca ptr, align 8
  store ptr %env, ptr %env.addr, align 8
    #dbg_declare(ptr %env.addr, !175, !DIExpression(), !176)
  ; Detach thread from JVM
  %0 = load ptr, ptr %env.addr, align 8, !dbg !177
  %call = call i32 @DetachCurrentThread(ptr noundef %0), !dbg !178
  ; BUG: using env after detach -- env is invalid
    #dbg_declare(ptr %cls, !179, !DIExpression(), !180)
  %1 = load ptr, ptr %env.addr, align 8, !dbg !181
  %call1 = call ptr @FindClass(ptr noundef %1, ptr noundef @.str), !dbg !182
  store ptr %call1, ptr %cls, align 8, !dbg !180
  %2 = load ptr, ptr %env.addr, align 8, !dbg !183
  %call2 = call i32 (ptr, ...) @printf(ptr noundef @.str.5), !dbg !184
  ret void, !dbg !185
}

; --- Test 7: Weak global ref use-after-GC ---
; NewWeakGlobalRef creates a weak reference. After GC, the referent may be
; collected. Code uses GetObjectRefElement without NULL check -> crash.
define void @jni_07_weak_global_ref_use_after_gc(ptr noundef %env, ptr noundef %obj) #0 !dbg !186 {
entry:
  %env.addr = alloca ptr, align 8
  %obj.addr = alloca ptr, align 8
  %weak_ref = alloca ptr, align 8
  %local_ref = alloca ptr, align 8
  store ptr %env, ptr %env.addr, align 8
  store ptr %obj, ptr %obj.addr, align 8
    #dbg_declare(ptr %env.addr, !190, !DIExpression(), !191)
    #dbg_declare(ptr %obj.addr, !192, !DIExpression(), !193)
    #dbg_declare(ptr %weak_ref, !194, !DIExpression(), !195)
  %0 = load ptr, ptr %env.addr, align 8, !dbg !196
  %1 = load ptr, ptr %obj.addr, align 8, !dbg !197
  %call = call ptr @NewWeakGlobalRef(ptr noundef %0, ptr noundef %1), !dbg !198
  store ptr %call, ptr %weak_ref, align 8, !dbg !195
  ; Store in global for later use
  %2 = load ptr, ptr %weak_ref, align 8, !dbg !199
  store ptr %2, ptr @g_native_weak, align 8, !dbg !200
  ; Force GC -- may collect the weakly-referenced object
  %3 = load ptr, ptr %env.addr, align 8, !dbg !201
  call void @JNI_GC(ptr noundef %3), !dbg !202
  ; BUG: use weak ref without checking if referent was collected
    #dbg_declare(ptr %local_ref, !203, !DIExpression(), !204)
  %4 = load ptr, ptr %env.addr, align 8, !dbg !205
  %5 = load ptr, ptr @g_native_weak, align 8, !dbg !206
  %call1 = call ptr @GetObjectRefElement(ptr noundef %4, ptr noundef %5), !dbg !207
  store ptr %call1, ptr %local_ref, align 8, !dbg !204
  ; Use the local_ref -- may be NULL if object was GC'd
  %6 = load ptr, ptr %local_ref, align 8, !dbg !208
  %call2 = call i32 (ptr, ...) @printf(ptr noundef @.str.6, ptr noundef %6), !dbg !209
  ; Cleanup
  %7 = load ptr, ptr %env.addr, align 8, !dbg !210
  %8 = load ptr, ptr %weak_ref, align 8, !dbg !211
  call void @DeleteWeakGlobalRef(ptr noundef %7, ptr noundef %8), !dbg !212
  ret void, !dbg !213
}

; --- Test 8: JNI on_attach callback + wrong thread ---
; A native callback fires on a pthread that was never attached to the JVM.
; The callback uses a stale or null JNIEnv -> crash.
define void @jni_08_native_callback_wrong_thread(ptr noundef %env, ptr noundef %callback_obj) #0 !dbg !214 {
entry:
  %env.addr = alloca ptr, align 8
  %callback_obj.addr = alloca ptr, align 8
  %cached_env = alloca ptr, align 8
  store ptr %env, ptr %env.addr, align 8
  store ptr %callback_obj, ptr %callback_obj.addr, align 8
    #dbg_declare(ptr %env.addr, !218, !DIExpression(), !219)
    #dbg_declare(ptr %callback_obj.addr, !220, !DIExpression(), !221)
  ; Cache the env pointer for later use in a callback
    #dbg_declare(ptr %cached_env, !222, !DIExpression(), !223)
  %0 = load ptr, ptr %env.addr, align 8, !dbg !224
  store ptr %0, ptr %cached_env, align 8, !dbg !223
  ; Simulate: native callback fires on a different native thread.
  ; The cached env is from a different thread -> invalid.
  ; BUG: using env from wrong thread
  %1 = load ptr, ptr %cached_env, align 8, !dbg !225
  %call = call ptr @FindClass(ptr noundef %1, ptr noundef @.str.7), !dbg !226
  ; Call a method using the wrong thread's env
  %2 = load ptr, ptr %cached_env, align 8, !dbg !227
  %3 = load ptr, ptr %callback_obj.addr, align 8, !dbg !228
  %4 = load ptr, ptr %cached_env, align 8, !dbg !228
  %5 = load ptr, ptr %4, align 8, !dbg !228
  %6 = getelementptr ptr, ptr %5, i64 0, !dbg !228
  %7 = load ptr, ptr %6, align 8, !dbg !228
  call void @CallVoidMethodV(ptr noundef %2, ptr noundef %3, ptr noundef %7), !dbg !228
  ret void, !dbg !229
}

; --- Test 9: DeleteGlobalRef on local ref ---
; Code calls DeleteGlobalRef on a local reference. DeleteGlobalRef expects
; a global ref. This corrupts the JNI ref table / causes undefined behavior.
define void @jni_09_delete_global_on_local(ptr noundef %env) #0 !dbg !230 {
entry:
  %env.addr = alloca ptr, align 8
  %local_obj = alloca ptr, align 8
  store ptr %env, ptr %env.addr, align 8
    #dbg_declare(ptr %env.addr, !234, !DIExpression(), !235)
    #dbg_declare(ptr %local_obj, !236, !DIExpression(), !237)
  %0 = load ptr, ptr %env.addr, align 8, !dbg !238
  %call = call ptr @FindClass(ptr noundef %0, ptr noundef @.str), !dbg !239
  store ptr %call, ptr %local_obj, align 8, !dbg !237
  ; BUG: using DeleteGlobalRef on a local reference -> corruption
  %1 = load ptr, ptr %env.addr, align 8, !dbg !240
  %2 = load ptr, ptr %local_obj, align 8, !dbg !241
  call void @DeleteGlobalRef(ptr noundef %1, ptr noundef %2), !dbg !242
  ret void, !dbg !243
}

; --- Test 10: ExceptionCheck + continued JNI calls ---
; A JNI call throws an exception. Code checks ExceptionCheck but does not
; call ExceptionClear. Subsequent JNI calls with a pending exception -> UB.
define void @jni_10_exception_continued_calls(ptr noundef %env, ptr noundef %obj) #0 !dbg !244 {
entry:
  %env.addr = alloca ptr, align 8
  %obj.addr = alloca ptr, align 8
  %cls = alloca ptr, align 8
  %mid = alloca ptr, align 8
  %has_exc = alloca i32, align 4
  store ptr %env, ptr %env.addr, align 8
  store ptr %obj, ptr %obj.addr, align 8
    #dbg_declare(ptr %env.addr, !248, !DIExpression(), !249)
    #dbg_declare(ptr %obj.addr, !250, !DIExpression(), !251)
    #dbg_declare(ptr %cls, !252, !DIExpression(), !253)
  %0 = load ptr, ptr %env.addr, align 8, !dbg !254
  %call = call ptr @GetObjectClass(ptr noundef %0, ptr noundef %1), !dbg !255
  store ptr %call, ptr %cls, align 8, !dbg !253
    #dbg_declare(ptr %mid, !256, !DIExpression(), !257)
  %2 = load ptr, ptr %env.addr, align 8, !dbg !258
  %3 = load ptr, ptr %cls, align 8, !dbg !259
  %call1 = call ptr @GetMethodID(ptr noundef %2, ptr noundef %3, ptr noundef @.str.1), !dbg !260
  store ptr %call1, ptr %mid, align 8, !dbg !257
  ; Call a method that may throw
  %4 = load ptr, ptr %env.addr, align 8, !dbg !261
  %5 = load ptr, ptr %obj.addr, align 8, !dbg !262
  %6 = load ptr, ptr %mid, align 8, !dbg !263
  call void @CallVoidMethodV(ptr noundef %4, ptr noundef %5, ptr noundef %6), !dbg !264
  ; Check for exception
    #dbg_declare(ptr %has_exc, !265, !DIExpression(), !266)
  %7 = load ptr, ptr %env.addr, align 8, !dbg !267
  %call2 = call i32 @ExceptionCheck(ptr noundef %7), !dbg !268
  store i32 %call2, ptr %has_exc, align 4, !dbg !266
  ; BUG: has_exc is non-zero but we continue calling JNI without ExceptionClear
  %8 = load ptr, ptr %env.addr, align 8, !dbg !269
  %9 = load ptr, ptr %obj.addr, align 8, !dbg !270
  %10 = load ptr, ptr %mid, align 8, !dbg !271
  call void @CallVoidMethodV(ptr noundef %8, ptr noundef %9, ptr noundef %10), !dbg !272
  ; More JNI calls with pending exception -> undefined behavior
  %11 = load ptr, ptr %env.addr, align 8, !dbg !273
  %12 = load i32, ptr %has_exc, align 4, !dbg !274
  %call3 = call i32 (ptr, ...) @printf(ptr noundef @.str.9, i32 noundef %12), !dbg !275
  ret void, !dbg !276
}

; --- Declarations ---

declare ptr @NewStringUTF(ptr noundef, ptr noundef) #1
declare ptr @GetStringUTFChars(ptr noundef, ptr noundef) #1
declare void @ReleaseStringUTFChars(ptr noundef, ptr noundef, ptr noundef) #1
declare ptr @FindClass(ptr noundef, ptr noundef) #1
declare ptr @AllocObject(ptr noundef, ptr noundef) #1
declare ptr @NewGlobalRef(ptr noundef, ptr noundef) #1
declare void @DeleteGlobalRef(ptr noundef, ptr noundef) #1
declare void @DeleteLocalRef(ptr noundef, ptr noundef) #1
declare ptr @NewByteArray(ptr noundef, i32 noundef) #1
declare ptr @GetPrimitiveArrayCritical(ptr noundef, ptr noundef) #1
declare void @ReleasePrimitiveArrayCritical(ptr noundef, ptr noundef, ptr noundef) #1
declare i32 @MonitorEnter(ptr noundef, ptr noundef) #1
declare i32 @MonitorExit(ptr noundef, ptr noundef) #1
declare i32 @DetachCurrentThread(ptr noundef) #1
declare ptr @NewWeakGlobalRef(ptr noundef, ptr noundef) #1
declare void @DeleteWeakGlobalRef(ptr noundef, ptr noundef) #1
declare void @JNI_GC(ptr noundef) #1
declare ptr @GetObjectRefElement(ptr noundef, ptr noundef) #1
declare ptr @GetObjectClass(ptr noundef, ptr noundef) #1
declare ptr @GetMethodID(ptr noundef, ptr noundef, ptr noundef) #1
declare void @CallVoidMethodV(ptr noundef, ptr noundef, ptr noundef) #1
declare i32 @ExceptionCheck(ptr noundef) #1
declare void @ExceptionClear(ptr noundef) #1
declare i32 @printf(ptr noundef, ...) #1

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }

!llvm.dbg.cu = !{!54}
!llvm.module.flags = !{!60, !61, !62, !63, !64, !65}
!llvm.ident = !{!277}

!0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
!1 = distinct !DIGlobalVariable(scope: null, file: !2, line: 10, type: !3, isLocal: true, isDefinition: true)
!2 = !DIFile(filename: "corpus/red_team_test/java_jni_edge_cases.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5")
!3 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 128, elements: !5)
!4 = !DIBasicType(name: "char", size: 8, encoding: DW_ATE_signed_char)
!5 = !{!6}
!6 = !DISubrange(count: 16)
!7 = !DIGlobalVariableExpression(var: !8, expr: !DIExpression())
!8 = distinct !DIGlobalVariable(scope: null, file: !2, line: 30, type: !9, isLocal: true, isDefinition: true)
!9 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 48, elements: !10)
!10 = !{!11}
!11 = !DISubrange(count: 6)
!12 = !DIGlobalVariableExpression(var: !13, expr: !DIExpression())
!13 = distinct !DIGlobalVariable(scope: null, file: !2, line: 48, type: !14, isLocal: true, isDefinition: true)
!14 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 96, elements: !15)
!15 = !{!16}
!16 = !DISubrange(count: 12)
!17 = !DIGlobalVariableExpression(var: !18, expr: !DIExpression())
!18 = distinct !DIGlobalVariable(scope: null, file: !2, line: 68, type: !19, isLocal: true, isDefinition: true)
!19 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 80, elements: !20)
!20 = !{!21}
!21 = !DISubrange(count: 10)
!22 = !DIGlobalVariableExpression(var: !23, expr: !DIExpression())
!23 = distinct !DIGlobalVariable(scope: null, file: !2, line: 90, type: !24, isLocal: true, isDefinition: true)
!24 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 96, elements: !25)
!25 = !{!26}
!26 = !DISubrange(count: 12)
!27 = !DIGlobalVariableExpression(var: !28, expr: !DIExpression())
!28 = distinct !DIGlobalVariable(scope: null, file: !2, line: 108, type: !29, isLocal: true, isDefinition: true)
!29 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 112, elements: !30)
!30 = !{!31}
!31 = !DISubrange(count: 14)
!32 = !DIGlobalVariableExpression(var: !33, expr: !DIExpression())
!33 = distinct !DIGlobalVariable(scope: null, file: !2, line: 128, type: !34, isLocal: true, isDefinition: true)
!34 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 80, elements: !35)
!35 = !{!36}
!36 = !DISubrange(count: 10)
!37 = !DIGlobalVariableExpression(var: !38, expr: !DIExpression())
!38 = distinct !DIGlobalVariable(scope: null, file: !2, line: 148, type: !39, isLocal: true, isDefinition: true)
!39 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 64, elements: !40)
!40 = !{!41}
!41 = !DISubrange(count: 8)
!42 = !DIGlobalVariableExpression(var: !43, expr: !DIExpression())
!43 = distinct !DIGlobalVariable(scope: null, file: !2, line: 168, type: !44, isLocal: true, isDefinition: true)
!44 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 80, elements: !45)
!45 = !{!46}
!46 = !DISubrange(count: 10)
!47 = !DIGlobalVariableExpression(var: !48, expr: !DIExpression())
!48 = distinct !DIGlobalVariable(scope: null, file: !2, line: 190, type: !49, isLocal: true, isDefinition: true)
!49 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 96, elements: !50)
!50 = !{!51}
!51 = !DISubrange(count: 12)
!52 = !DIGlobalVariableExpression(var: !53, expr: !DIExpression())
!53 = distinct !DIGlobalVariable(name: "g_cached_local_ref", scope: !54, file: !2, line: 12, type: !58, isLocal: true, isDefinition: true)
!54 = distinct !DICompileUnit(language: DW_LANG_C11, file: !55, producer: "Homebrew clang version 21.1.8", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, retainedTypes: !56, globals: !57, splitDebugInlining: false, nameTableKind: Apple, sysroot: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk", sdk: "MacOSX15.sdk")
!55 = !DIFile(filename: "corpus/red_team_test/java_jni_edge_cases.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5")
!56 = !{!58}
!57 = !{!0, !7, !12, !17, !22, !27, !32, !37, !42, !47, !52, !59}
!58 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!59 = !DIGlobalVariableExpression(var: !60, expr: !DIExpression())
!60 = distinct !DIGlobalVariable(name: "g_native_weak", scope: !54, file: !2, line: 13, type: !58, isLocal: true, isDefinition: true)
!61 = !{i32 7, !"Dwarf Version", i32 5}
!62 = !{i32 2, !"Debug Info Version", i32 3}
!63 = !{i32 1, !"wchar_size", i32 4}
!64 = !{i32 8, !"PIC Level", i32 2}
!65 = !{i32 7, !"uwtable", i32 1}
!66 = !{i32 7, !"frame-pointer", i32 1}

; --- Debug info for functions ---

!66 = distinct !DISubprogram(name: "jni_01_local_ref_overflow", scope: !2, file: !2, line: 17, type: !67, scopeLine: 17, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !54, retainedNodes: !73)
!67 = !DISubroutineType(types: !68)
!68 = !{null, !69}
!69 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !70, size: 64)
!70 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !71, size: 64)
!71 = !DICompositeType(tag: DW_TAG_structure_type, name: "JNINativeInterface_", file: !2, line: 17, flags: DIFlagFwdDecl)
!72 = !{}
!73 = !{}
!74 = !DILocalVariable(name: "env", arg: 1, scope: !66, file: !2, line: 17, type: !69)
!75 = !DILocation(line: 17, column: 41, scope: !66)
!76 = !DILocalVariable(name: "i", scope: !66, file: !2, line: 19, type: !77)
!77 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!78 = !DILocation(line: 20, column: 12, scope: !66)
!79 = !DILocation(line: 20, column: 19, scope: !66)
!80 = !DILocation(line: 20, column: 21, scope: !66)
!81 = !DILocation(line: 20, column: 5, scope: !66)
!82 = !DILocalVariable(name: "jstr", scope: !66, file: !2, line: 21, type: !58)
!83 = !DILocation(line: 21, column: 17, scope: !66)
!84 = !DILocation(line: 21, column: 38, scope: !66)
!85 = !DILocation(line: 21, column: 24, scope: !66)
!86 = !DILocation(line: 20, column: 30, scope: !66)
!87 = !DILocation(line: 20, column: 5, scope: !66)
!88 = !DILocation(line: 24, column: 1, scope: !66)

!89 = distinct !DISubprogram(name: "jni_02_global_ref_leak", scope: !2, file: !2, line: 28, type: !67, scopeLine: 28, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !54, retainedNodes: !72)
!90 = !DILocalVariable(name: "env", arg: 1, scope: !89, file: !2, line: 28, type: !69)
!91 = !DILocation(line: 28, column: 39, scope: !89)
!92 = !DILocalVariable(name: "cls", scope: !89, file: !2, line: 29, type: !58)
!93 = !DILocation(line: 29, column: 11, scope: !89)
!94 = !DILocation(line: 29, column: 31, scope: !89)
!95 = !DILocalVariable(name: "local_obj", scope: !89, file: !2, line: 30, type: !58)
!96 = !DILocation(line: 30, column: 13, scope: !89)
!97 = !DILocation(line: 30, column: 40, scope: !89)
!98 = !DILocation(line: 30, column: 25, scope: !89)
!99 = !DILocalVariable(name: "local_obj", scope: !89, file: !2, line: 31, type: !58)
!100 = !DILocation(line: 31, column: 13, scope: !89)
!101 = !DILocation(line: 31, column: 40, scope: !89)
!102 = !DILocation(line: 31, column: 45, scope: !89)
!103 = !DILocation(line: 31, column: 25, scope: !89)
!104 = !DILocalVariable(name: "global_obj", scope: !89, file: !2, line: 32, type: !58)
!105 = !DILocation(line: 32, column: 13, scope: !89)
!106 = !DILocation(line: 32, column: 41, scope: !89)
!107 = !DILocation(line: 32, column: 46, scope: !89)
!108 = !DILocation(line: 32, column: 26, scope: !89)
!109 = !DILocation(line: 35, column: 1, scope: !89)

!110 = distinct !DISubprogram(name: "jni_03_string_not_released", scope: !2, file: !2, line: 39, type: !67, scopeLine: 39, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !54, retainedNodes: !72)
!111 = !DILocalVariable(name: "env", arg: 1, scope: !110, file: !2, line: 39, type: !69)
!112 = !DILocation(line: 39, column: 43, scope: !110)
!113 = !DILocalVariable(name: "jstr", scope: !110, file: !2, line: 40, type: !58)
!114 = !DILocation(line: 40, column: 13, scope: !110)
!115 = !DILocation(line: 40, column: 33, scope: !110)
!116 = !DILocalVariable(name: "jstr", scope: !110, file: !2, line: 40, type: !58)
!117 = !DILocation(line: 40, column: 13, scope: !110)
!118 = !DILocation(line: 40, column: 33, scope: !110)
!119 = !DILocation(line: 40, column: 20, scope: !110)
!120 = !DILocalVariable(name: "native", scope: !110, file: !2, line: 41, type: !58)
!121 = !DILocation(line: 41, column: 17, scope: !110)
!122 = !DILocation(line: 41, column: 48, scope: !110)
!123 = !DILocation(line: 41, column: 53, scope: !110)
!124 = !DILocation(line: 41, column: 26, scope: !110)
!125 = !DILocation(line: 43, column: 28, scope: !110)
!126 = !DILocation(line: 43, column: 5, scope: !110)
!127 = !DILocation(line: 45, column: 1, scope: !110)

!128 = distinct !DISubprogram(name: "jni_04_critical_section_jni_call", scope: !2, file: !2, line: 50, type: !67, scopeLine: 50, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !54, retainedNodes: !72)
!129 = !DILocalVariable(name: "env", arg: 1, scope: !128, file: !2, line: 50, type: !69)
!130 = !DILocation(line: 50, column: 49, scope: !128)
!131 = !DILocalVariable(name: "arr", scope: !128, file: !2, line: 51, type: !58)
!132 = !DILocation(line: 51, column: 11, scope: !128)
!133 = !DILocation(line: 51, column: 31, scope: !128)
!134 = !DILocalVariable(name: "arr", scope: !128, file: !2, line: 51, type: !58)
!135 = !DILocation(line: 51, column: 11, scope: !128)
!136 = !DILocation(line: 51, column: 31, scope: !128)
!137 = !DILocation(line: 51, column: 17, scope: !128)
!138 = !DILocalVariable(name: "pinned", scope: !128, file: !2, line: 52, type: !58)
!139 = !DILocation(line: 52, column: 11, scope: !128)
!140 = !DILocation(line: 52, column: 42, scope: !128)
!141 = !DILocation(line: 52, column: 47, scope: !128)
!142 = !DILocation(line: 52, column: 19, scope: !128)
!143 = !DILocalVariable(name: "jstr", scope: !128, file: !2, line: 55, type: !58)
!144 = !DILocation(line: 55, column: 13, scope: !128)
!145 = !DILocation(line: 55, column: 33, scope: !128)
!146 = !DILocation(line: 55, column: 20, scope: !128)
!147 = !DILocation(line: 58, column: 35, scope: !128)
!148 = !DILocation(line: 58, column: 40, scope: !128)
!149 = !DILocation(line: 58, column: 45, scope: !128)
!150 = !DILocation(line: 58, column: 5, scope: !128)
!151 = !DILocation(line: 59, column: 1, scope: !128)

!152 = distinct !DISubprogram(name: "jni_05_monitor_enter_exception", scope: !2, file: !2, line: 64, type: !153, scopeLine: 64, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !54, retainedNodes: !72)
!153 = !DISubroutineType(types: !154)
!154 = !{null, !69, !58}
!155 = !DILocalVariable(name: "env", arg: 1, scope: !152, file: !2, line: 64, type: !69)
!156 = !DILocation(line: 64, column: 47, scope: !152)
!157 = !DILocation(line: 64, column: 52, scope: !152)
!158 = !DILocalVariable(name: "lock_obj", arg: 2, scope: !152, file: !2, line: 64, type: !58)
!159 = !DILocation(line: 64, column: 65, scope: !152)
!160 = !DILocalVariable(name: "rc", scope: !152, file: !2, line: 66, type: !77)
!161 = !DILocation(line: 66, column: 9, scope: !152)
!162 = !DILocation(line: 67, column: 25, scope: !152)
!163 = !DILocation(line: 67, column: 30, scope: !152)
!164 = !DILocation(line: 67, column: 10, scope: !152)
!165 = !DILocation(line: 70, column: 30, scope: !152)
!166 = !DILocation(line: 70, column: 5, scope: !152)
!167 = !DILocation(line: 72, column: 25, scope: !152)
!168 = !DILocation(line: 72, column: 30, scope: !152)
!169 = !DILocation(line: 72, column: 12, scope: !152)
!170 = !DILocation(line: 73, column: 1, scope: !152)

!171 = distinct !DISubprogram(name: "jni_06_findclass_after_detach", scope: !2, file: !2, line: 77, type: !67, scopeLine: 77, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !54, retainedNodes: !72)
!172 = !DILocalVariable(name: "env", arg: 1, scope: !171, file: !2, line: 77, type: !69)
!173 = !DILocation(line: 77, column: 46, scope: !171)
!174 = !DILocalVariable(name: "cls", scope: !171, file: !2, line: 79, type: !58)
!175 = !DILocation(line: 79, column: 11, scope: !171)
!176 = !DILocation(line: 79, column: 31, scope: !171)
!177 = !DILocation(line: 81, column: 30, scope: !171)
!178 = !DILocation(line: 81, column: 5, scope: !171)
!179 = !DILocalVariable(name: "cls", scope: !171, file: !2, line: 83, type: !58)
!180 = !DILocation(line: 83, column: 11, scope: !171)
!181 = !DILocation(line: 83, column: 31, scope: !171)
!182 = !DILocation(line: 83, column: 17, scope: !171)
!183 = !DILocation(line: 85, column: 17, scope: !171)
!184 = !DILocation(line: 85, column: 5, scope: !171)
!185 = !DILocation(line: 86, column: 1, scope: !171)

!186 = distinct !DISubprogram(name: "jni_07_weak_global_ref_use_after_gc", scope: !2, file: !2, line: 90, type: !153, scopeLine: 90, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !54, retainedNodes: !72)
!187 = !DILocalVariable(name: "env", arg: 1, scope: !186, file: !2, line: 90, type: !69)
!188 = !DILocation(line: 90, column: 51, scope: !186)
!189 = !DILocalVariable(name: "obj", arg: 2, scope: !186, file: !2, line: 90, type: !58)
!190 = !DILocation(line: 90, column: 63, scope: !186)
!191 = !DILocation(line: 90, column: 68, scope: !186)
!192 = !DILocalVariable(name: "obj", arg: 2, scope: !186, file: !2, line: 90, type: !58)
!193 = !DILocation(line: 90, column: 63, scope: !186)
!194 = !DILocalVariable(name: "weak_ref", scope: !186, file: !2, line: 92, type: !58)
!195 = !DILocation(line: 92, column: 11, scope: !186)
!196 = !DILocation(line: 92, column: 37, scope: !186)
!197 = !DILocation(line: 92, column: 42, scope: !186)
!198 = !DILocation(line: 92, column: 22, scope: !186)
!199 = !DILocation(line: 94, column: 25, scope: !186)
!200 = !DILocation(line: 94, column: 23, scope: !186)
!201 = !DILocation(line: 96, column: 14, scope: !186)
!202 = !DILocation(line: 96, column: 5, scope: !186)
!203 = !DILocalVariable(name: "local_ref", scope: !186, file: !2, line: 99, type: !58)
!204 = !DILocation(line: 99, column: 13, scope: !186)
!205 = !DILocation(line: 99, column: 40, scope: !186)
!206 = !DILocation(line: 99, column: 45, scope: !186)
!207 = !DILocation(line: 99, column: 25, scope: !186)
!208 = !DILocation(line: 101, column: 26, scope: !186)
!209 = !DILocation(line: 101, column: 5, scope: !186)
!210 = !DILocation(line: 103, column: 25, scope: !186)
!211 = !DILocation(line: 103, column: 30, scope: !186)
!212 = !DILocation(line: 103, column: 5, scope: !186)
!213 = !DILocation(line: 104, column: 1, scope: !186)

!214 = distinct !DISubprogram(name: "jni_08_native_callback_wrong_thread", scope: !2, file: !2, line: 108, type: !153, scopeLine: 108, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !54, retainedNodes: !72)
!215 = !DILocalVariable(name: "env", arg: 1, scope: !214, file: !2, line: 108, type: !69)
!216 = !DILocation(line: 108, column: 52, scope: !214)
!217 = !DILocalVariable(name: "callback_obj", arg: 2, scope: !214, file: !2, line: 108, type: !58)
!218 = !DILocation(line: 108, column: 64, scope: !214)
!219 = !DILocation(line: 108, column: 78, scope: !214)
!220 = !DILocalVariable(name: "callback_obj", arg: 2, scope: !214, file: !2, line: 108, type: !58)
!221 = !DILocation(line: 108, column: 64, scope: !214)
!222 = !DILocalVariable(name: "cached_env", scope: !214, file: !2, line: 110, type: !69)
!223 = !DILocation(line: 110, column: 13, scope: !214)
!224 = !DILocation(line: 110, column: 26, scope: !214)
!225 = !DILocation(line: 115, column: 25, scope: !214)
!226 = !DILocation(line: 115, column: 17, scope: !214)
!227 = !DILocation(line: 118, column: 25, scope: !214)
!228 = !DILocation(line: 118, column: 5, scope: !214)
!229 = !DILocation(line: 119, column: 1, scope: !214)

!230 = distinct !DISubprogram(name: "jni_09_delete_global_on_local", scope: !2, file: !2, line: 123, type: !67, scopeLine: 123, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !54, retainedNodes: !72)
!231 = !DILocalVariable(name: "env", arg: 1, scope: !230, file: !2, line: 123, type: !69)
!232 = !DILocation(line: 123, column: 46, scope: !230)
!233 = !DILocalVariable(name: "local_obj", scope: !230, file: !2, line: 125, type: !58)
!234 = !DILocation(line: 125, column: 13, scope: !230)
!235 = !DILocation(line: 125, column: 40, scope: !230)
!236 = !DILocalVariable(name: "local_obj", scope: !230, file: !2, line: 125, type: !58)
!237 = !DILocation(line: 125, column: 13, scope: !230)
!238 = !DILocation(line: 125, column: 40, scope: !230)
!239 = !DILocation(line: 125, column: 25, scope: !230)
!240 = !DILocation(line: 128, column: 22, scope: !230)
!241 = !DILocation(line: 128, column: 27, scope: !230)
!242 = !DILocation(line: 128, column: 5, scope: !230)
!243 = !DILocation(line: 129, column: 1, scope: !230)

!244 = distinct !DISubprogram(name: "jni_10_exception_continued_calls", scope: !2, file: !2, line: 133, type: !153, scopeLine: 133, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !54, retainedNodes: !72)
!245 = !DILocalVariable(name: "env", arg: 1, scope: !244, file: !2, line: 133, type: !69)
!246 = !DILocation(line: 133, column: 49, scope: !244)
!247 = !DILocalVariable(name: "obj", arg: 2, scope: !244, file: !2, line: 133, type: !58)
!248 = !DILocation(line: 133, column: 61, scope: !244)
!249 = !DILocation(line: 133, column: 66, scope: !244)
!250 = !DILocalVariable(name: "obj", arg: 2, scope: !244, file: !2, line: 133, type: !58)
!251 = !DILocation(line: 133, column: 61, scope: !244)
!252 = !DILocalVariable(name: "cls", scope: !244, file: !2, line: 135, type: !58)
!253 = !DILocation(line: 135, column: 11, scope: !244)
!254 = !DILocation(line: 135, column: 31, scope: !244)
!255 = !DILocation(line: 135, column: 17, scope: !244)
!256 = !DILocalVariable(name: "mid", scope: !244, file: !2, line: 136, type: !58)
!257 = !DILocation(line: 136, column: 11, scope: !244)
!258 = !DILocation(line: 136, column: 31, scope: !244)
!259 = !DILocation(line: 136, column: 36, scope: !244)
!260 = !DILocation(line: 136, column: 17, scope: !244)
!261 = !DILocation(line: 138, column: 24, scope: !244)
!262 = !DILocation(line: 138, column: 29, scope: !244)
!263 = !DILocation(line: 138, column: 34, scope: !244)
!264 = !DILocation(line: 138, column: 5, scope: !244)
!265 = !DILocalVariable(name: "has_exc", scope: !244, file: !2, line: 140, type: !77)
!266 = !DILocation(line: 140, column: 9, scope: !244)
!267 = !DILocation(line: 140, column: 28, scope: !244)
!268 = !DILocation(line: 140, column: 18, scope: !244)
!269 = !DILocation(line: 143, column: 24, scope: !244)
!270 = !DILocation(line: 143, column: 29, scope: !244)
!271 = !DILocation(line: 143, column: 34, scope: !244)
!272 = !DILocation(line: 143, column: 5, scope: !244)
!273 = !DILocation(line: 145, column: 28, scope: !244)
!274 = !DILocation(line: 145, column: 33, scope: !244)
!275 = !DILocation(line: 145, column: 5, scope: !244)
!276 = !DILocation(line: 146, column: 1, scope: !244)

!277 = !{!"Homebrew clang version 21.1.8"}
