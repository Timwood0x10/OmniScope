; ModuleID = 'corpus/red_team_test/python_capi_edge_cases.c'
source_filename = "corpus/red_team_test/python_capi_edge_cases.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

@.str = private unnamed_addr constant [7 x i8] c"hello\0A\00", align 1, !dbg !0
@.str.1 = private unnamed_addr constant [5 x i8] c"attr\00", align 1, !dbg !7
@.str.2 = private unnamed_addr constant [8 x i8] c"data: \0A\00", align 1, !dbg !12
@.str.3 = private unnamed_addr constant [7 x i8] c"utf8s\0A\00", align 1, !dbg !17
@.str.4 = private unnamed_addr constant [5 x i8] c"caps\00", align 1, !dbg !22
@.str.5 = private unnamed_addr constant [12 x i8] c"val: %p %s\0A\00", align 1, !dbg !27
@.str.6 = private unnamed_addr constant [11 x i8] c"threadbuf\0A\00", align 1, !dbg !32
@.str.7 = private unnamed_addr constant [6 x i8] c"init\0A\00", align 1, !dbg !37
@.str.8 = private unnamed_addr constant [14 x i8] c"after reinit\0A\00", align 1, !dbg !42
@.str.9 = private unnamed_addr constant [6 x i8] c"dict\0A\00", align 1, !dbg !47
@g_py_buffer_data = internal global ptr null, align 8, !dbg !52
@g_old_interp_ptr = internal global ptr null, align 8, !dbg !59
@g_capsule_mem = internal global ptr null, align 8, !dbg !66

; --- Test 1: Borrowed reference decref ---
; PyList_GetItem returns a borrowed ref; calling Py_DECREF on it causes
; refcount underflow, leading to use-after-free when the list later accesses it.
define void @py_01_borrowed_ref_decref(ptr noundef %list) #0 !dbg !73 {
entry:
  %list.addr = alloca ptr, align 8
  %item = alloca ptr, align 8
  store ptr %list, ptr %list.addr, align 8
    #dbg_declare(ptr %list.addr, !78, !DIExpression(), !79)
    #dbg_declare(ptr %item, !80, !DIExpression(), !81)
  %0 = load ptr, ptr %list.addr, align 8, !dbg !82
  %call = call ptr @PyList_GetItem(ptr noundef %0, i64 noundef 0), !dbg !83
  store ptr %call, ptr %item, align 8, !dbg !81
  ; BUG: decref a borrowed reference from PyList_GetItem
  %1 = load ptr, ptr %item, align 8, !dbg !84
  call void @Py_DECREF(ptr noundef %1), !dbg !85
  ; Now re-read item from the list -- use-after-free
  %2 = load ptr, ptr %list.addr, align 8, !dbg !86
  %call1 = call ptr @PyList_GetItem(ptr noundef %2, i64 noundef 0), !dbg !87
  %3 = load i64, ptr %call1, align 8, !dbg !88
  ret void, !dbg !89
}

; --- Test 2: New reference leak ---
; PyObject_GetAttrString returns a new reference; code never calls Py_DECREF,
; leaking the attribute object and everything it references.
define void @py_02_new_ref_leak(ptr noundef %obj) #0 !dbg !90 {
entry:
  %obj.addr = alloca ptr, align 8
  %attr = alloca ptr, align 8
  store ptr %obj, ptr %obj.addr, align 8
    #dbg_declare(ptr %obj.addr, !94, !DIExpression(), !95)
    #dbg_declare(ptr %attr, !96, !DIExpression(), !97)
  %0 = load ptr, ptr %obj.addr, align 8, !dbg !98
  %call = call ptr @PyObject_GetAttrString(ptr noundef %0, ptr noundef @.str.1), !dbg !99
  store ptr %call, ptr %attr, align 8, !dbg !97
  ; Use the attr, then return without Py_DECREF -> memory leak
  %1 = load ptr, ptr %attr, align 8, !dbg !100
  %tobool = icmp ne ptr %1, null, !dbg !100
  br i1 %tobool, label %if.then, label %if.end, !dbg !100

if.then:
  ; Use attr value
  %2 = load ptr, ptr %attr, align 8, !dbg !101
  %call1 = call i32 @PyLong_AsLong(ptr noundef %2), !dbg !102
  br label %if.end, !dbg !103

if.end:
  ; Missing: Py_DECREF(attr) -- new reference leaked
  ret void, !dbg !104
}

; --- Test 3: Stolen reference double decref ---
; PyList_SetItem steals the reference to val. After the call, the list owns val.
; Code then also decrefs val, causing a double free.
define void @py_03_stolen_ref_double_decref(ptr noundef %list) #0 !dbg !105 {
entry:
  %list.addr = alloca ptr, align 8
  %val = alloca ptr, align 8
  store ptr %list, ptr %list.addr, align 8
    #dbg_declare(ptr %list.addr, !109, !DIExpression(), !110)
    #dbg_declare(ptr %val, !111, !DIExpression(), !112)
  %call = call ptr @PyLong_FromLong(i64 noundef 42), !dbg !113
  store ptr %call, ptr %val, align 8, !dbg !112
  ; PyList_SetItem steals the ref to val -- list now owns it
  %0 = load ptr, ptr %list.addr, align 8, !dbg !114
  %1 = load ptr, ptr %val, align 8, !dbg !115
  %call1 = call i32 @PyList_SetItem(ptr noundef %0, i64 noundef 0, ptr noundef %1), !dbg !116
  ; BUG: also decref val -> double free (list will also decref it later)
  %2 = load ptr, ptr %val, align 8, !dbg !117
  call void @Py_DECREF(ptr noundef %2), !dbg !118
  ret void, !dbg !119
}

; --- Test 4: GIL release + Python API call ---
; Py_BEGIN_ALLOW_THREADS releases the GIL. Calling PyList_GetItem (or any
; Python C API) without re-acquiring the GIL is undefined behavior / crash.
define void @py_04_gil_release_py_call(ptr noundef %list) #0 !dbg !120 {
entry:
  %list.addr = alloca ptr, align 8
  %save = alloca i32, align 4
  %item = alloca ptr, align 8
  store ptr %list, ptr %list.addr, align 8
    #dbg_declare(ptr %list.addr, !124, !DIExpression(), !125)
    #dbg_declare(ptr %save, !126, !DIExpression(), !127)
  ; Py_BEGIN_ALLOW_THREADS: save GIL state and release
  %call = call i32 @PyEval_SaveThread(), !dbg !128
  store i32 %call, ptr %save, align 4, !dbg !127
  ; BUG: calling Python C API without holding the GIL
    #dbg_declare(ptr %item, !129, !DIExpression(), !130)
  %0 = load ptr, ptr %list.addr, align 8, !dbg !131
  %call1 = call ptr @PyList_GetItem(ptr noundef %0, i64 noundef 0), !dbg !132
  store ptr %call1, ptr %item, align 8, !dbg !130
  ; Py_END_ALLOW_THREADS: re-acquire GIL
  %1 = load i32, ptr %save, align 4, !dbg !133
  call void @PyEval_RestoreThread(i32 noundef %1), !dbg !133
  ret void, !dbg !134
}

; --- Test 5: PyObject_Call + exception not checked ---
; PyObject_CallObject returns NULL on failure. Code uses the return value
; without checking PyErr_Occurred, leading to null pointer dereference.
define void @py_05_call_null_no_exc_check(ptr noundef %callable, ptr noundef %args) #0 !dbg !135 {
entry:
  %callable.addr = alloca ptr, align 8
  %args.addr = alloca ptr, align 8
  %result = alloca ptr, align 8
  store ptr %callable, ptr %callable.addr, align 8
  store ptr %args, ptr %args.addr, align 8
    #dbg_declare(ptr %callable.addr, !139, !DIExpression(), !140)
    #dbg_declare(ptr %args.addr, !141, !DIExpression(), !142)
    #dbg_declare(ptr %result, !143, !DIExpression(), !144)
  %0 = load ptr, ptr %callable.addr, align 8, !dbg !145
  %1 = load ptr, ptr %args.addr, align 8, !dbg !146
  %call = call ptr @PyObject_CallObject(ptr noundef %0, ptr noundef %1), !dbg !147
  store ptr %call, ptr %result, align 8, !dbg !144
  ; BUG: result may be NULL (exception set), but we deref without checking
  %2 = load ptr, ptr %result, align 8, !dbg !148
  %call1 = call i64 @PyObject_Hash(ptr noundef %2), !dbg !149
  ; Missing: check PyErr_Occurred() and handle NULL result
  %3 = load ptr, ptr %result, align 8, !dbg !150
  call void @Py_XDECREF(ptr noundef %3), !dbg !151
  ret void, !dbg !152
}

; --- Test 6: Py_buffer not released ---
; PyObject_GetBuffer acquires a buffer. Forgetting PyBuffer_Release causes
; the object to remain locked and prevents memory reclamation.
define void @py_06_buffer_not_released(ptr noundef %obj) #0 !dbg !153 {
entry:
  %obj.addr = alloca ptr, align 8
  %view = alloca [16 x i8], align 8
  store ptr %obj, ptr %obj.addr, align 8
    #dbg_declare(ptr %obj.addr, !157, !DIExpression(), !158)
    #dbg_declare(ptr %view, !159, !DIExpression(), !160)
  ; PyObject_GetBuffer fills in the Py_buffer struct
  %0 = load ptr, ptr %obj.addr, align 8, !dbg !161
  %view_ptr = getelementptr inbounds [16 x i8], ptr %view, i64 0, i64 0, !dbg !161
  %call = call i32 @PyObject_GetBuffer(ptr noundef %0, ptr noundef %view_ptr, i32 noundef 0), !dbg !161
  ; Use the buffer data
  %buf_field = getelementptr inbounds [16 x i8], ptr %view, i64 0, i64 0, !dbg !162
  %1 = load ptr, ptr %buf_field, align 8, !dbg !162
  store ptr %1, ptr @g_py_buffer_data, align 8, !dbg !163
  ; BUG: missing PyBuffer_Release(&view) -- buffer leak
  ret void, !dbg !164
}

; --- Test 7: PyUnicode_AsUTF8 + temporary string ---
; PyUnicode_AsUTF8 returns a pointer into the Python object's internal storage.
; If the object is decref'd, the pointer becomes dangling.
define void @py_07_unicode_utf8_dangling(ptr noundef %unicode_obj) #0 !dbg !165 {
entry:
  %unicode_obj.addr = alloca ptr, align 8
  %utf8 = alloca ptr, align 8
  %buf = alloca [128 x i8], align 1
  store ptr %unicode_obj, ptr %unicode_obj.addr, align 8
    #dbg_declare(ptr %unicode_obj.addr, !169, !DIExpression(), !170)
    #dbg_declare(ptr %utf8, !171, !DIExpression(), !172)
  %0 = load ptr, ptr %unicode_obj.addr, align 8, !dbg !173
  %call = call ptr @PyUnicode_AsUTF8(ptr noundef %0), !dbg !174
  store ptr %call, ptr %utf8, align 8, !dbg !172
  ; Decrease refcount -- may free the unicode object
  %1 = load ptr, ptr %unicode_obj.addr, align 8, !dbg !175
  call void @Py_DECREF(ptr noundef %1), !dbg !176
  ; BUG: utf8 now points to freed internal storage -> dangling pointer
    #dbg_declare(ptr %buf, !177, !DIExpression(), !178)
  %arraydecay = getelementptr inbounds [128 x i8], ptr %buf, i64 0, i64 0, !dbg !179
  %2 = load ptr, ptr %utf8, align 8, !dbg !179
  %call1 = call ptr @__strcpy_chk(ptr noundef %arraydecay, ptr noundef %2, i64 noundef 128) #3, !dbg !179
  ret void, !dbg !180
}

; Function Attrs: nounwind
declare ptr @__strcpy_chk(ptr noundef, ptr noundef, i64 noundef) #2

; --- Test 8: Capsule destructor double free ---
; PyCapsule_New registers a destructor that frees the underlying memory.
; Code then also frees the same memory explicitly -> double free.
define void @py_08_capsule_destructor_double_free() #0 !dbg !181 {
entry:
  %mem = alloca ptr, align 8
  %capsule = alloca ptr, align 8
    #dbg_declare(ptr %mem, !184, !DIExpression(), !185)
  %call = call ptr @malloc(i64 noundef 256) #4, !dbg !186
  store ptr %call, ptr %mem, align 8, !dbg !185
  ; Also store in global so destructor can access it
  %0 = load ptr, ptr %mem, align 8, !dbg !187
  store ptr %0, ptr @g_capsule_mem, align 8, !dbg !188
    #dbg_declare(ptr %capsule, !189, !DIExpression(), !190)
  %1 = load ptr, ptr %mem, align 8, !dbg !191
  %call1 = call ptr @PyCapsule_New(ptr noundef %1, ptr noundef @.str.4, ptr noundef @capsule_destructor), !dbg !192
  store ptr %call1, ptr %capsule, align 8, !dbg !190
  ; Decref capsule -> triggers destructor -> frees mem
  %2 = load ptr, ptr %capsule, align 8, !dbg !193
  call void @Py_DECREF(ptr noundef %2), !dbg !194
  ; BUG: also free the same memory explicitly -> double free
  %3 = load ptr, ptr %mem, align 8, !dbg !195
  call void @free(ptr noundef %3), !dbg !196
  ret void, !dbg !197
}

; Capsule destructor -- frees the memory that was put into the capsule
define internal void @capsule_destructor(ptr noundef %capsule) #0 !dbg !198 {
entry:
  %capsule.addr = alloca ptr, align 8
  store ptr %capsule, ptr %capsule.addr, align 8
    #dbg_declare(ptr %capsule.addr, !202, !DIExpression(), !203)
  %0 = load ptr, ptr @g_capsule_mem, align 8, !dbg !204
  call void @free(ptr noundef %0), !dbg !205
  store ptr null, ptr @g_capsule_mem, align 8, !dbg !206
  ret void, !dbg !207
}

; --- Test 9: Subinterpreter + shared state ---
; Two PyInterpreterState instances share a C global pointer. When one
; interpreter is finalized, it may free objects the other still references.
define void @py_09_subinterpreter_shared_state() #0 !dbg !208 {
entry:
  %main_interp = alloca ptr, align 8
  %sub_interp = alloca ptr, align 8
  %shared_obj = alloca ptr, align 8
    #dbg_declare(ptr %main_interp, !211, !DIExpression(), !212)
  %call = call ptr @PyInterpreterState_Main(), !dbg !213
  store ptr %call, ptr %main_interp, align 8, !dbg !212
    #dbg_declare(ptr %sub_interp, !214, !DIExpression(), !215)
  %call1 = call ptr @Py_NewInterpreter(), !dbg !216
  store ptr %call1, ptr %sub_interp, align 8, !dbg !215
    #dbg_declare(ptr %shared_obj, !217, !DIExpression(), !218)
  ; Create an object in the main interpreter's context
  %call2 = call ptr @PyLong_FromLong(i64 noundef 999), !dbg !219
  store ptr %call2, ptr %shared_obj, align 8, !dbg !218
  ; Store in global shared between interpreters
  %0 = load ptr, ptr %shared_obj, align 8, !dbg !220
  store ptr %0, ptr @g_old_interp_ptr, align 8, !dbg !221
  ; BUG: finalize the sub-interpreter -- may free objects reachable from globals
  %1 = load ptr, ptr %sub_interp, align 8, !dbg !222
  call void @Py_EndInterpreter(ptr noundef %1), !dbg !223
  ; Now use the global that was set up above -> dangling
  %2 = load ptr, ptr @g_old_interp_ptr, align 8, !dbg !224
  %call3 = call i32 @PyLong_AsLong(ptr noundef %2), !dbg !225
  ret void, !dbg !226
}

; --- Test 10: Py_Finalize + init cycle ---
; Py_FinalizeEx frees interpreter state. Py_Initialize re-creates it.
; Old C pointers that were cached before finalize still point to freed memory.
define void @py_10_finalize_reinit_stale_ptr() #0 !dbg !227 {
entry:
  %bytes = alloca ptr, align 8
  %data = alloca ptr, align 8
    #dbg_declare(ptr %bytes, !230, !DIExpression(), !231)
  ; Create a Python object while interpreter is live
  %call = call ptr @PyBytes_FromStringAndSize(ptr noundef @.str.7, i64 noundef 5), !dbg !232
  store ptr %call, ptr %bytes, align 8, !dbg !231
    #dbg_declare(ptr %data, !233, !DIExpression(), !234)
  %0 = load ptr, ptr %bytes, align 8, !dbg !235
  %call1 = call ptr @PyBytes_AsString(ptr noundef %0), !dbg !236
  store ptr %call1, ptr %data, align 8, !dbg !234
  ; Finalize Python -- frees all interpreter state, including the bytes object
  %call2 = call i32 @Py_FinalizeEx(), !dbg !237
  ; Re-initialize Python -- new interpreter, new state
  call void @Py_Initialize(), !dbg !238
  ; BUG: 'data' still points to memory from the old interpreter -> dangling
  %1 = load ptr, ptr %data, align 8, !dbg !239
  %call3 = call i32 (ptr, ...) @printf(ptr noundef @.str.8, ptr noundef %1), !dbg !240
  ; Also, 'bytes' is a stale PyObject pointer
  %2 = load ptr, ptr %bytes, align 8, !dbg !241
  call void @Py_DECREF(ptr noundef %2), !dbg !242
  ret void, !dbg !243
}

; --- Declarations ---

declare ptr @PyList_GetItem(ptr noundef, i64 noundef) #1
declare void @Py_DECREF(ptr noundef) #1
declare void @Py_XDECREF(ptr noundef) #1
declare ptr @PyObject_GetAttrString(ptr noundef, ptr noundef) #1
declare i32 @PyLong_AsLong(ptr noundef) #1
declare ptr @PyLong_FromLong(i64 noundef) #1
declare i32 @PyList_SetItem(ptr noundef, i64 noundef, ptr noundef) #1
declare i32 @PyEval_SaveThread() #1
declare void @PyEval_RestoreThread(i32 noundef) #1
declare ptr @PyObject_CallObject(ptr noundef, ptr noundef) #1
declare i64 @PyObject_Hash(ptr noundef) #1
declare i32 @PyObject_GetBuffer(ptr noundef, ptr noundef, i32 noundef) #1
declare ptr @PyUnicode_AsUTF8(ptr noundef) #1
declare ptr @PyCapsule_New(ptr noundef, ptr noundef, ptr noundef) #1
declare ptr @PyInterpreterState_Main() #1
declare ptr @Py_NewInterpreter() #1
declare void @Py_EndInterpreter(ptr noundef) #1
declare i32 @Py_FinalizeEx() #1
declare void @Py_Initialize() #1
declare ptr @PyBytes_FromStringAndSize(ptr noundef, i64 noundef) #1
declare ptr @PyBytes_AsString(ptr noundef) #1
declare i32 @printf(ptr noundef, ...) #1

; Function Attrs: allocsize(0)
declare ptr @malloc(i64 noundef) #4

declare void @free(ptr noundef) #1

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { nounwind }
attributes #4 = { allocsize(0) }

!llvm.dbg.cu = !{!54}
!llvm.module.flags = !{!67, !68, !69, !70, !71, !72}
!llvm.ident = !{!244}

!0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
!1 = distinct !DIGlobalVariable(scope: null, file: !2, line: 10, type: !3, isLocal: true, isDefinition: true)
!2 = !DIFile(filename: "corpus/red_team_test/python_capi_edge_cases.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4")
!3 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 56, elements: !5)
!4 = !DIBasicType(name: "char", size: 8, encoding: DW_ATE_signed_char)
!5 = !{!6}
!6 = !DISubrange(count: 7)
!7 = !DIGlobalVariableExpression(var: !8, expr: !DIExpression())
!8 = distinct !DIGlobalVariable(scope: null, file: !2, line: 30, type: !9, isLocal: true, isDefinition: true)
!9 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 40, elements: !10)
!10 = !{!11}
!11 = !DISubrange(count: 5)
!12 = !DIGlobalVariableExpression(var: !13, expr: !DIExpression())
!13 = distinct !DIGlobalVariable(scope: null, file: !2, line: 70, type: !14, isLocal: true, isDefinition: true)
!14 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 64, elements: !15)
!15 = !{!16}
!16 = !DISubrange(count: 8)
!17 = !DIGlobalVariableExpression(var: !18, expr: !DIExpression())
!18 = distinct !DIGlobalVariable(scope: null, file: !2, line: 95, type: !19, isLocal: true, isDefinition: true)
!19 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 56, elements: !20)
!20 = !{!21}
!21 = !DISubrange(count: 7)
!22 = !DIGlobalVariableExpression(var: !23, expr: !DIExpression())
!23 = distinct !DIGlobalVariable(scope: null, file: !2, line: 110, type: !9, isLocal: true, isDefinition: true)
!24 = !DIGlobalVariableExpression(var: !25, expr: !DIExpression())
!25 = distinct !DIGlobalVariable(scope: null, file: !2, line: 130, type: !26, isLocal: true, isDefinition: true)
!26 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 112, elements: !27)
!27 = !{!28}
!28 = !DISubrange(count: 14)
!29 = !DIGlobalVariableExpression(var: !30, expr: !DIExpression())
!30 = distinct !DIGlobalVariable(scope: null, file: !2, line: 160, type: !31, isLocal: true, isDefinition: true)
!31 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 88, elements: !32)
!32 = !{!33}
!33 = !DISubrange(count: 11)
!34 = !DIGlobalVariableExpression(var: !35, expr: !DIExpression())
!35 = distinct !DIGlobalVariable(scope: null, file: !2, line: 180, type: !36, isLocal: true, isDefinition: true)
!36 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 48, elements: !37)
!37 = !{!38}
!38 = !DISubrange(count: 6)
!39 = !DIGlobalVariableExpression(var: !40, expr: !DIExpression())
!40 = distinct !DIGlobalVariable(scope: null, file: !2, line: 200, type: !41, isLocal: true, isDefinition: true)
!41 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 112, elements: !42)
!42 = !{!43}
!43 = !DISubrange(count: 14)
!44 = !DIGlobalVariableExpression(var: !45, expr: !DIExpression())
!45 = distinct !DIGlobalVariable(scope: null, file: !2, line: 220, type: !46, isLocal: true, isDefinition: true)
!46 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 48, elements: !47)
!47 = !{!48}
!48 = !DISubrange(count: 6)
!49 = !DIGlobalVariableExpression(var: !50, expr: !DIExpression())
!50 = distinct !DIGlobalVariable(name: "g_py_buffer_data", scope: !54, file: !2, line: 12, type: !58, isLocal: true, isDefinition: true)
!51 = !DIGlobalVariableExpression(var: !52, expr: !DIExpression())
!52 = distinct !DIGlobalVariable(name: "g_old_interp_ptr", scope: !54, file: !2, line: 13, type: !58, isLocal: true, isDefinition: true)
!53 = !DIGlobalVariableExpression(var: !54, expr: !DIExpression())
!54 = distinct !DIGlobalVariable(name: "g_capsule_mem", scope: !55, file: !2, line: 14, type: !58, isLocal: true, isDefinition: true)
!55 = distinct !DICompileUnit(language: DW_LANG_C11, file: !56, producer: "Homebrew clang version 21.1.8", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, retainedTypes: !57, globals: !60, splitDebugInlining: false, nameTableKind: Apple, sysroot: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk", sdk: "MacOSX15.sdk")
!56 = !DIFile(filename: "corpus/red_team_test/python_capi_edge_cases.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4")
!57 = !{!58}
!58 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!59 = !DIGlobalVariableExpression(var: !60, expr: !DIExpression())
!60 = distinct !DIGlobalVariable(name: "g_py_buffer_data_dummy", scope: null, file: !2, line: 0, type: !58, isLocal: true, isDefinition: true)
!61 = !DIGlobalVariableExpression(var: !62, expr: !DIExpression())
!62 = distinct !DIGlobalVariable(name: "g_old_interp_ptr_dummy", scope: null, file: !2, line: 0, type: !58, isLocal: true, isDefinition: true)
!63 = !DIGlobalVariableExpression(var: !64, expr: !DIExpression())
!64 = distinct !DIGlobalVariable(name: "g_capsule_mem_dummy", scope: null, file: !2, line: 0, type: !58, isLocal: true, isDefinition: true)
!65 = !{!0, !7, !12, !17, !22, !25, !29, !34, !39, !44, !49, !51, !53, !59, !61, !63}
!66 = !{i32 7, !"Dwarf Version", i32 5}
!67 = !{i32 2, !"Debug Info Version", i32 3}
!68 = !{i32 1, !"wchar_size", i32 4}
!69 = !{i32 8, !"PIC Level", i32 2}
!70 = !{i32 7, !"uwtable", i32 1}
!71 = !{i32 7, !"frame-pointer", i32 1}
!72 = !{i32 7, !"Dwarf Version", i32 5}

; --- Debug info for functions ---

!73 = distinct !DISubprogram(name: "py_01_borrowed_ref_decref", scope: !2, file: !2, line: 18, type: !74, scopeLine: 18, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !55, retainedNodes: !77)
!74 = !DISubroutineType(types: !75)
!75 = !{null, !76}
!76 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!77 = !{}
!78 = !DILocalVariable(name: "list", arg: 1, scope: !73, file: !2, line: 18, type: !76)
!79 = !DILocation(line: 18, column: 42, scope: !73)
!80 = !DILocalVariable(name: "item", scope: !73, file: !2, line: 20, type: !76)
!81 = !DILocation(line: 20, column: 15, scope: !73)
!82 = !DILocation(line: 20, column: 37, scope: !73)
!83 = !DILocation(line: 20, column: 22, scope: !73)
!84 = !DILocation(line: 22, column: 15, scope: !73)
!85 = !DILocation(line: 22, column: 5, scope: !73)
!86 = !DILocation(line: 24, column: 37, scope: !73)
!87 = !DILocation(line: 24, column: 15, scope: !73)
!88 = !DILocation(line: 25, column: 5, scope: !73)
!89 = !DILocation(line: 26, column: 1, scope: !73)

!90 = distinct !DISubprogram(name: "py_02_new_ref_leak", scope: !2, file: !2, line: 29, type: !91, scopeLine: 29, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !55, retainedNodes: !93)
!91 = !DISubroutineType(types: !92)
!92 = !{null, !76}
!93 = !{}
!94 = !DILocalVariable(name: "obj", arg: 1, scope: !90, file: !2, line: 29, type: !76)
!95 = !DILocation(line: 29, column: 36, scope: !90)
!96 = !DILocalVariable(name: "attr", scope: !90, file: !2, line: 31, type: !76)
!97 = !DILocation(line: 31, column: 15, scope: !90)
!98 = !DILocation(line: 31, column: 48, scope: !90)
!99 = !DILocation(line: 31, column: 22, scope: !90)
!100 = !DILocation(line: 33, column: 9, scope: !90)
!101 = !DILocation(line: 34, column: 22, scope: !90)
!102 = !DILocation(line: 34, column: 16, scope: !90)
!103 = !DILocation(line: 35, column: 5, scope: !90)
!104 = !DILocation(line: 37, column: 1, scope: !90)

!105 = distinct !DISubprogram(name: "py_03_stolen_ref_double_decref", scope: !2, file: !2, line: 41, type: !106, scopeLine: 41, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !55, retainedNodes: !108)
!106 = !DISubroutineType(types: !107)
!107 = !{null, !76}
!108 = !{}
!109 = !DILocalVariable(name: "list", arg: 1, scope: !105, file: !2, line: 41, type: !76)
!110 = !DILocation(line: 41, column: 47, scope: !105)
!111 = !DILocalVariable(name: "val", scope: !105, file: !2, line: 43, type: !76)
!112 = !DILocation(line: 43, column: 15, scope: !105)
!113 = !DILocation(line: 43, column: 21, scope: !105)
!114 = !DILocation(line: 45, column: 28, scope: !105)
!115 = !DILocation(line: 45, column: 34, scope: !105)
!116 = !DILocation(line: 45, column: 5, scope: !105)
!117 = !DILocation(line: 47, column: 15, scope: !105)
!118 = !DILocation(line: 47, column: 5, scope: !105)
!119 = !DILocation(line: 48, column: 1, scope: !105)

!120 = distinct !DISubprogram(name: "py_04_gil_release_py_call", scope: !2, file: !2, line: 52, type: !121, scopeLine: 52, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !55, retainedNodes: !123)
!121 = !DISubroutineType(types: !122)
!122 = !{null, !76}
!123 = !{}
!124 = !DILocalVariable(name: "list", arg: 1, scope: !120, file: !2, line: 52, type: !76)
!125 = !DILocation(line: 52, column: 42, scope: !120)
!126 = !DILocalVariable(name: "save", scope: !120, file: !2, line: 54, type: !127)
!127 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!128 = !DILocation(line: 55, column: 17, scope: !120)
!129 = !DILocalVariable(name: "item", scope: !120, file: !2, line: 58, type: !76)
!130 = !DILocation(line: 58, column: 15, scope: !120)
!131 = !DILocation(line: 58, column: 37, scope: !120)
!132 = !DILocation(line: 58, column: 22, scope: !120)
!133 = !DILocation(line: 60, column: 5, scope: !120)
!134 = !DILocation(line: 61, column: 1, scope: !120)

!135 = distinct !DISubprogram(name: "py_05_call_null_no_exc_check", scope: !2, file: !2, line: 65, type: !136, scopeLine: 65, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !55, retainedNodes: !138)
!136 = !DISubroutineType(types: !137)
!137 = !{null, !76, !76}
!138 = !{}
!139 = !DILocalVariable(name: "callable", arg: 1, scope: !135, file: !2, line: 65, type: !76)
!140 = !DILocation(line: 65, column: 45, scope: !135)
!141 = !DILocalVariable(name: "args", arg: 2, scope: !135, file: !2, line: 65, type: !76)
!142 = !DILocation(line: 65, column: 62, scope: !135)
!143 = !DILocalVariable(name: "result", scope: !135, file: !2, line: 67, type: !76)
!144 = !DILocation(line: 67, column: 15, scope: !135)
!145 = !DILocation(line: 67, column: 46, scope: !135)
!146 = !DILocation(line: 67, column: 56, scope: !135)
!147 = !DILocation(line: 67, column: 24, scope: !135)
!148 = !DILocation(line: 70, column: 25, scope: !135)
!149 = !DILocation(line: 70, column: 17, scope: !135)
!150 = !DILocation(line: 72, column: 16, scope: !135)
!151 = !DILocation(line: 72, column: 5, scope: !135)
!152 = !DILocation(line: 73, column: 1, scope: !135)

!153 = distinct !DISubprogram(name: "py_06_buffer_not_released", scope: !2, file: !2, line: 77, type: !154, scopeLine: 77, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !55, retainedNodes: !156)
!154 = !DISubroutineType(types: !155)
!155 = !{null, !76}
!156 = !{}
!157 = !DILocalVariable(name: "obj", arg: 1, scope: !153, file: !2, line: 77, type: !76)
!158 = !DILocation(line: 77, column: 42, scope: !153)
!159 = !DILocalVariable(name: "view", scope: !153, file: !2, line: 79, type: !76)
!160 = !DILocation(line: 79, column: 10, scope: !153)
!161 = !DILocation(line: 81, column: 5, scope: !153)
!162 = !DILocation(line: 83, column: 20, scope: !153)
!163 = !DILocation(line: 83, column: 18, scope: !153)
!164 = !DILocation(line: 85, column: 1, scope: !153)

!165 = distinct !DISubprogram(name: "py_07_unicode_utf8_dangling", scope: !2, file: !2, line: 89, type: !166, scopeLine: 89, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !55, retainedNodes: !168)
!166 = !DISubroutineType(types: !167)
!167 = !{null, !76}
!168 = !{}
!169 = !DILocalVariable(name: "unicode_obj", arg: 1, scope: !165, file: !2, line: 89, type: !76)
!170 = !DILocation(line: 89, column: 44, scope: !165)
!171 = !DILocalVariable(name: "utf8", scope: !165, file: !2, line: 91, type: !76)
!172 = !DILocation(line: 91, column: 17, scope: !165)
!173 = !DILocation(line: 91, column: 42, scope: !165)
!174 = !DILocation(line: 91, column: 24, scope: !165)
!175 = !DILocation(line: 93, column: 15, scope: !165)
!176 = !DILocation(line: 93, column: 5, scope: !165)
!177 = !DILocalVariable(name: "buf", scope: !165, file: !2, line: 96, type: !76)
!178 = !DILocation(line: 96, column: 10, scope: !165)
!179 = !DILocation(line: 97, column: 5, scope: !165)
!180 = !DILocation(line: 98, column: 1, scope: !165)

!181 = distinct !DISubprogram(name: "py_08_capsule_destructor_double_free", scope: !2, file: !2, line: 102, type: !182, scopeLine: 102, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !55, retainedNodes: !183)
!182 = !DISubroutineType(types: !77)
!183 = !{}
!184 = !DILocalVariable(name: "mem", scope: !181, file: !2, line: 103, type: !76)
!185 = !DILocation(line: 103, column: 11, scope: !181)
!186 = !DILocation(line: 103, column: 17, scope: !181)
!187 = !DILocation(line: 104, column: 25, scope: !181)
!188 = !DILocation(line: 104, column: 23, scope: !181)
!189 = !DILocalVariable(name: "capsule", scope: !181, file: !2, line: 105, type: !76)
!190 = !DILocation(line: 105, column: 15, scope: !181)
!191 = !DILocation(line: 106, column: 33, scope: !181)
!192 = !DILocation(line: 106, column: 17, scope: !181)
!193 = !DILocation(line: 108, column: 15, scope: !181)
!194 = !DILocation(line: 108, column: 5, scope: !181)
!195 = !DILocation(line: 110, column: 10, scope: !181)
!196 = !DILocation(line: 110, column: 5, scope: !181)
!197 = !DILocation(line: 111, column: 1, scope: !181)

!198 = distinct !DISubprogram(name: "capsule_destructor", scope: !2, file: !2, line: 114, type: !199, scopeLine: 114, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !55, retainedNodes: !201)
!199 = !DISubroutineType(types: !200)
!200 = !{null, !76}
!201 = !{}
!202 = !DILocalVariable(name: "capsule", arg: 1, scope: !198, file: !2, line: 114, type: !76)
!203 = !DILocation(line: 114, column: 36, scope: !198)
!204 = !DILocation(line: 115, column: 10, scope: !198)
!205 = !DILocation(line: 115, column: 5, scope: !198)
!206 = !DILocation(line: 116, column: 23, scope: !198)
!207 = !DILocation(line: 117, column: 1, scope: !198)

!208 = distinct !DISubprogram(name: "py_09_subinterpreter_shared_state", scope: !2, file: !2, line: 121, type: !182, scopeLine: 121, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !55, retainedNodes: !209)
!209 = !{}
!210 = !DILocalVariable(name: "main_interp", scope: !208, file: !2, line: 122, type: !76)
!211 = !DILocation(line: 122, column: 15, scope: !208)
!212 = !DILocation(line: 122, column: 28, scope: !208)
!213 = !DILocation(line: 122, column: 42, scope: !208)
!214 = !DILocalVariable(name: "sub_interp", scope: !208, file: !2, line: 123, type: !76)
!215 = !DILocation(line: 123, column: 15, scope: !208)
!216 = !DILocation(line: 123, column: 28, scope: !208)
!217 = !DILocalVariable(name: "shared_obj", scope: !208, file: !2, line: 124, type: !76)
!218 = !DILocation(line: 124, column: 15, scope: !208)
!219 = !DILocation(line: 124, column: 28, scope: !208)
!220 = !DILocation(line: 126, column: 31, scope: !208)
!221 = !DILocation(line: 126, column: 29, scope: !208)
!222 = !DILocation(line: 128, column: 25, scope: !208)
!223 = !DILocation(line: 128, column: 5, scope: !208)
!224 = !DILocation(line: 130, column: 30, scope: !208)
!225 = !DILocation(line: 130, column: 17, scope: !208)
!226 = !DILocation(line: 131, column: 1, scope: !208)

!227 = distinct !DISubprogram(name: "py_10_finalize_reinit_stale_ptr", scope: !2, file: !2, line: 135, type: !182, scopeLine: 135, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !55, retainedNodes: !228)
!228 = !{}
!229 = !DILocalVariable(name: "bytes", scope: !227, file: !2, line: 136, type: !76)
!230 = !DILocation(line: 136, column: 15, scope: !227)
!231 = !DILocation(line: 136, column: 22, scope: !227)
!232 = !DILocation(line: 136, column: 58, scope: !227)
!233 = !DILocalVariable(name: "data", scope: !227, file: !2, line: 137, type: !76)
!234 = !DILocation(line: 137, column: 11, scope: !227)
!235 = !DILocation(line: 137, column: 36, scope: !227)
!236 = !DILocation(line: 137, column: 18, scope: !227)
!237 = !DILocation(line: 139, column: 5, scope: !227)
!238 = !DILocation(line: 141, column: 5, scope: !227)
!239 = !DILocation(line: 143, column: 42, scope: !227)
!240 = !DILocation(line: 143, column: 5, scope: !227)
!241 = !DILocation(line: 145, column: 15, scope: !227)
!242 = !DILocation(line: 145, column: 5, scope: !227)
!243 = !DILocation(line: 146, column: 1, scope: !227)

!244 = !{!"Homebrew clang version 21.1.8"}
