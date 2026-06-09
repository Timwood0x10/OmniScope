; ModuleID = 'corpus/red_team_test/rust_ffi_edge_cases.c'
source_filename = "corpus/red_team_test/rust_ffi_edge_cases.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

%struct.CWrapper = type { ptr, i64 }
%struct.PinBox = type { ptr, i64 }
%struct.PhantomRef = type { ptr, ptr }
%struct.ArcInner = type { i64, ptr }

@g_c_wrapper = internal global %struct.CWrapper zeroinitializer, align 8, !dbg !0
@g_pin_box_alias = internal global ptr null, align 8, !dbg !12
@g_phantom_raw = internal global ptr null, align 8, !dbg !16
@g_arc_shared = internal global ptr null, align 8, !dbg !20
@g_je_ptr = internal global ptr null, align 8, !dbg !24

@.str.box_data = private unnamed_addr constant [15 x i8] c"Box owned data\00", align 1, !dbg !28
@.str.vec_data = private unnamed_addr constant [18 x i8] c"original vec data\00", align 1, !dbg !35
@.str.cstring_src = private unnamed_addr constant [25 x i8] c"CString from Rust custom\00", align 1, !dbg !40
@.str.pin_data = private unnamed_addr constant [14 x i8] c"Pinned object\00", align 1, !dbg !45
@.str.phantom_data = private unnamed_addr constant [17 x i8] c"phantom ref data\00", align 1, !dbg !50
@.str.mutex_inner = private unnamed_addr constant [16 x i8] c"mutex protected\00", align 1, !dbg !55
@.str.arc_data = private unnamed_addr constant [11 x i8] c"Arc shared\00", align 1, !dbg !60
@.str.transmuted = private unnamed_addr constant [19 x i8] c"transmuted pointer\00", align 1, !dbg !65

; TC-RUST-09: Box::into_raw + double free via alias
; Bug: Rust Box gives ptr to C, C stores in struct field, both Drop and free() run on same pointer
; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @rust_09_box_raw_alias_double_free() #0 !dbg !75 {
entry:
  %boxed = alloca ptr, align 8
    #dbg_declare(ptr %boxed, !79, !DIExpression(), !80)
  %call = call ptr @_RNvCsiI7Gbpq5_17box_into_raw_alloc(i64 noundef 64), !dbg !81
  store ptr %call, ptr %boxed, align 8, !dbg !80
  %0 = load ptr, ptr %boxed, align 8, !dbg !82
  %1 = load ptr, ptr %boxed, align 8, !dbg !82
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !82
  %call1 = call ptr @__strcpy_chk(ptr noundef %0, ptr noundef @.str.box_data, i64 noundef %2) #6, !dbg !82
  ; C side stores pointer into global struct wrapper
  %3 = load ptr, ptr %boxed, align 8, !dbg !83
  store ptr %3, ptr @g_c_wrapper, align 8, !dbg !84
  %4 = load ptr, ptr %boxed, align 8, !dbg !85
  %len_gep = getelementptr inbounds nuw %struct.CWrapper, ptr @g_c_wrapper, i32 0, i32 1, !dbg !86
  store i64 64, ptr %len_gep, align 8, !dbg !87
  ; C free path runs on the wrapper
  %5 = load ptr, ptr @g_c_wrapper, align 8, !dbg !88
  call void @free(ptr noundef %5), !dbg !89
  ; Rust Drop path also runs -- double free
  %6 = load ptr, ptr %boxed, align 8, !dbg !90
  call void @_RNvCsiI7Gbpq5_17box_drop_dealloc(ptr noundef %6, i64 noundef 64), !dbg !91
  ret void, !dbg !92
}

; TC-RUST-10: Vec::leak + realloc mismatch
; Bug: Rust Vec leaks buffer to C, C uses C realloc, then Rust allocator tries to free C-reallocated memory
; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @rust_10_vec_leak_realloc_mismatch() #0 !dbg !100 {
entry:
  %vec_ptr = alloca ptr, align 8
    #dbg_declare(ptr %vec_ptr, !102, !DIExpression(), !103)
  %call = call ptr @_RNvCsiI7Gbpq5_14vec_leak_alloc(i64 noundef 32), !dbg !104
  store ptr %call, ptr %vec_ptr, align 8, !dbg !103
  %0 = load ptr, ptr %vec_ptr, align 8, !dbg !105
  %1 = load ptr, ptr %vec_ptr, align 8, !dbg !105
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !105
  %call1 = call ptr @__strcpy_chk(ptr noundef %0, ptr noundef @.str.vec_data, i64 noundef %2) #6, !dbg !105
  ; C side reallocs with C allocator -- now owned by libc heap
  %3 = load ptr, ptr %vec_ptr, align 8, !dbg !106
  %call2 = call ptr @realloc(ptr noundef %3, i64 noundef 4096) #7, !dbg !107
  store ptr %call2, ptr %vec_ptr, align 8, !dbg !108
  ; Rust Drop runs rust_dealloc on the C-reallocated pointer -- allocator mismatch
  %4 = load ptr, ptr %vec_ptr, align 8, !dbg !109
  call void @_RNvCsiI7Gbpq5_14vec_drop_dealloc(ptr noundef %4, i64 noundef 4096), !dbg !110
  ret void, !dbg !111
}

; TC-RUST-11: CString into_raw + C free with wrong allocator
; Bug: CString::into_raw gives ownership to C, C calls free() but Rust used a custom allocator
; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @rust_11_cstring_wrong_allocator() #0 !dbg !120 {
entry:
  %raw = alloca ptr, align 8
    #dbg_declare(ptr %raw, !122, !DIExpression(), !123)
  %call = call ptr @_RNvCsiI7Gbpq5_16cstring_into_raw(ptr noundef @.str.cstring_src, i64 noundef 25), !dbg !124
  store ptr %call, ptr %raw, align 8, !dbg !123
  ; C side calls libc free(), but memory was allocated by Rust custom allocator
  %0 = load ptr, ptr %raw, align 8, !dbg !125
  call void @free(ptr noundef %0), !dbg !126
  ret void, !dbg !127
}

; TC-RUST-12: Pin + use-after-move across FFI
; Bug: Rust Pin<Box<T>> passed to C, Rust moves/drops the Box while C still holds pointer
; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @rust_12_pin_use_after_move() #0 !dbg !135 {
entry:
  %pinned = alloca ptr, align 8
    #dbg_declare(ptr %pinned, !137, !DIExpression(), !138)
  %call = call ptr @_RNvCsiI7Gbpq5_15pin_box_new_alloc(i64 noundef 48), !dbg !139
  store ptr %call, ptr %pinned, align 8, !dbg !138
  %0 = load ptr, ptr %pinned, align 8, !dbg !140
  %1 = load ptr, ptr %pinned, align 8, !dbg !140
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !140
  %call1 = call ptr @__strcpy_chk(ptr noundef %0, ptr noundef @.str.pin_data, i64 noundef %2) #6, !dbg !140
  ; C side stores the pinned pointer globally
  %3 = load ptr, ptr %pinned, align 8, !dbg !141
  store ptr %3, ptr @g_pin_box_alias, align 8, !dbg !142
  ; Rust moves/drops the Pin -- violates Pin contract
  %4 = load ptr, ptr %pinned, align 8, !dbg !143
  call void @_RNvCsiI7Gbpq5_15pin_box_drop(ptr noundef %4, i64 noundef 48), !dbg !144
  ; C code later reads through the alias -- use after free
  %5 = load ptr, ptr @g_pin_box_alias, align 8, !dbg !145
  %6 = load i8, ptr %5, align 1, !dbg !146
  ret void, !dbg !147
}

; TC-RUST-13: PhantomData lifetime trick + dangling pointer
; Bug: Rust struct with PhantomData<'a> passes raw ptr to C, the reference 'a goes out of scope
; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @rust_13_phantom_dangling() #0 !dbg !155 {
entry:
  %buf = alloca ptr, align 8
  %phantom = alloca %struct.PhantomRef, align 8
    #dbg_declare(ptr %buf, !157, !DIExpression(), !158)
  %call = call ptr @_RZN4alloc5alloc17h_allocate(i64 noundef 64), !dbg !159
  store ptr %call, ptr %buf, align 8, !dbg !158
  %0 = load ptr, ptr %buf, align 8, !dbg !160
  %1 = load ptr, ptr %buf, align 8, !dbg !160
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !160
  %call1 = call ptr @__strcpy_chk(ptr noundef %0, ptr noundef @.str.phantom_data, i64 noundef %2) #6, !dbg !160
    #dbg_declare(ptr %phantom, !161, !DIExpression(), !162)
  ; PhantomRef stores raw pointer derived from the borrow
  %3 = load ptr, ptr %buf, align 8, !dbg !163
  %raw_gep = getelementptr inbounds nuw %struct.PhantomRef, ptr %phantom, i32 0, i32 0, !dbg !164
  store ptr %3, ptr %raw_gep, align 8, !dbg !165
  %phantom_gep = getelementptr inbounds nuw %struct.PhantomRef, ptr %phantom, i32 0, i32 1, !dbg !166
  store ptr null, ptr %phantom_gep, align 8, !dbg !167
  ; Pass the raw pointer to C via the struct
  %raw_extract = getelementptr inbounds nuw %struct.PhantomRef, ptr %phantom, i32 0, i32 0, !dbg !168
  %4 = load ptr, ptr %raw_extract, align 8, !dbg !168
  store ptr %4, ptr @g_phantom_raw, align 8, !dbg !169
  ; The borrow ends -- deallocate
  %5 = load ptr, ptr %buf, align 8, !dbg !170
  call void @_RZN4alloc5alloc17h_deallocate(ptr noundef %5), !dbg !171
  ; C code later dereferences the dangling raw pointer
  %6 = load ptr, ptr @g_phantom_raw, align 8, !dbg !172
  %7 = load i8, ptr %6, align 1, !dbg !173
  ret void, !dbg !174
}

; TC-RUST-14: Mutex poisoned + FFI data access
; Bug: Rust Mutex is poisoned after a panic, FFI code accesses inner data without checking is_poisoned
; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @rust_14_mutex_poisoned_ffi() #0 !dbg !180 {
entry:
  %mutex_data = alloca ptr, align 8
  %is_poisoned = alloca i32, align 4
    #dbg_declare(ptr %mutex_data, !182, !DIExpression(), !183)
  %call = call ptr @_RZN4alloc5alloc17h_allocate(i64 noundef 48), !dbg !184
  store ptr %call, ptr %mutex_data, align 8, !dbg !183
  %0 = load ptr, ptr %mutex_data, align 8, !dbg !185
  %1 = load ptr, ptr %mutex_data, align 8, !dbg !185
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !185
  %call1 = call ptr @__strcpy_chk(ptr noundef %0, ptr noundef @.str.mutex_inner, i64 noundef %2) #6, !dbg !185
  ; Simulate: Rust panic causes mutex poisoning
    #dbg_declare(ptr %is_poisoned, !186, !DIExpression(), !187)
  store i32 1, ptr %is_poisoned, align 4, !dbg !187
  ; FFI code calls into Rust without checking if mutex is poisoned
  %3 = load i32, ptr %is_poisoned, align 4, !dbg !188
  %tobool = icmp ne i32 %3, 0, !dbg !188
  br i1 %tobool, label %poisoned_path, label %clean_path, !dbg !189

poisoned_path:                                    ; preds = %entry
  ; FFI ignores the poison flag and accesses inner data anyway
  %4 = load ptr, ptr %mutex_data, align 8, !dbg !190
  %5 = load i8, ptr %4, align 1, !dbg !191
  br label %merge, !dbg !192

clean_path:                                       ; preds = %entry
  br label %merge, !dbg !193

merge:                                            ; preds = %clean_path, %poisoned_path
  ; Cleanup -- but inner data may be in inconsistent state
  %6 = load ptr, ptr %mutex_data, align 8, !dbg !194
  call void @_RZN4alloc5alloc17h_deallocate(ptr noundef %6), !dbg !195
  ret void, !dbg !196
}

; TC-RUST-15: Arc::try_unwrap failure + double drop
; Bug: Arc shared between Rust and C callback, try_unwrap fails, both paths try to clean up
; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @rust_15_arc_try_unwrap_double_drop() #0 !dbg !200 {
entry:
  %arc_ptr = alloca ptr, align 8
  %unwrap_ok = alloca i32, align 4
    #dbg_declare(ptr %arc_ptr, !202, !DIExpression(), !203)
  %call = call ptr @_RNvCsiI7Gbpq5_13arc_new_alloc(i64 noundef 32), !dbg !204
  store ptr %call, ptr %arc_ptr, align 8, !dbg !203
  ; Write data into Arc payload
  %0 = load ptr, ptr %arc_ptr, align 8, !dbg !205
  %1 = load ptr, ptr %arc_ptr, align 8, !dbg !205
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !205
  %call1 = call ptr @__strcpy_chk(ptr noundef %0, ptr noundef @.str.arc_data, i64 noundef %2) #6, !dbg !205
  ; Share Arc pointer with C via global
  %3 = load ptr, ptr %arc_ptr, align 8, !dbg !206
  store ptr %3, ptr @g_arc_shared, align 8, !dbg !207
  ; C side increments refcount (simulated: refcount = 2)
  %4 = load ptr, ptr @g_arc_shared, align 8, !dbg !208
  call void @c_increment_refcount(ptr noundef %4), !dbg !209
  ; Rust tries try_unwrap -- fails because refcount > 1
    #dbg_declare(ptr %unwrap_ok, !210, !DIExpression(), !211)
  %5 = load ptr, ptr %arc_ptr, align 8, !dbg !212
  %call2 = call i32 @_RNvCsiI7Gbpq5_16arc_try_unwrap(ptr noundef %5), !dbg !213
  store i32 %call2, ptr %unwrap_ok, align 4, !dbg !211
  ; Rust side drops its Arc handle anyway (decrements refcount to 1, does not free)
  %6 = load ptr, ptr %arc_ptr, align 8, !dbg !214
  call void @_RNvCsiI7Gbpq5_10arc_drop(ptr noundef %6), !dbg !215
  ; C side frees the shared pointer directly -- double drop / use after free
  %7 = load ptr, ptr @g_arc_shared, align 8, !dbg !216
  call void @free(ptr noundef %7), !dbg !217
  ret void, !dbg !218
}

; TC-RUST-16: Transmute between allocators (global vs jemalloc)
; Bug: Pointer allocated with jemalloc is transmuted to look like global allocator ptr, then freed by global allocator
; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @rust_16_transmute_allocators() #0 !dbg !225 {
entry:
  %je_ptr = alloca ptr, align 8
  %global_ptr = alloca ptr, align 8
    #dbg_declare(ptr %je_ptr, !227, !DIExpression(), !228)
  ; Allocate with jemalloc
  %call = call ptr @je_malloc(i64 noundef 128), !dbg !229
  store ptr %call, ptr %je_ptr, align 8, !dbg !228
  %0 = load ptr, ptr %je_ptr, align 8, !dbg !230
  %1 = load ptr, ptr %je_ptr, align 8, !dbg !230
  %2 = call i64 @llvm.objectsize.i64.p0(ptr %1, i1 false, i1 true, i1 false), !dbg !230
  %call1 = call ptr @__strcpy_chk(ptr noundef %0, ptr noundef @.str.transmuted, i64 noundef %2) #6, !dbg !230
  ; Store jemalloc pointer in global, pretending it is a Rust global allocator pointer
  %3 = load ptr, ptr %je_ptr, align 8, !dbg !231
  store ptr %3, ptr @g_je_ptr, align 8, !dbg !232
    #dbg_declare(ptr %global_ptr, !233, !DIExpression(), !234)
  %4 = load ptr, ptr @g_je_ptr, align 8, !dbg !235
  store ptr %4, ptr %global_ptr, align 8, !dbg !234
  ; Rust global allocator frees the jemalloc pointer -- allocator mismatch crash
  %5 = load ptr, ptr %global_ptr, align 8, !dbg !236
  call void @_RZN4alloc5alloc17h_deallocate(ptr noundef %5), !dbg !237
  ret void, !dbg !238
}

; --- External declarations ---

declare ptr @_RNvCsiI7Gbpq5_17box_into_raw_alloc(i64 noundef) #1
declare void @_RNvCsiI7Gbpq5_17box_drop_dealloc(ptr noundef, i64 noundef) #1
declare ptr @_RNvCsiI7Gbpq5_14vec_leak_alloc(i64 noundef) #1
declare void @_RNvCsiI7Gbpq5_14vec_drop_dealloc(ptr noundef, i64 noundef) #1
declare ptr @_RNvCsiI7Gbpq5_16cstring_into_raw(ptr noundef, i64 noundef) #1
declare ptr @_RNvCsiI7Gbpq5_15pin_box_new_alloc(i64 noundef) #1
declare void @_RNvCsiI7Gbpq5_15pin_box_drop(ptr noundef, i64 noundef) #1
declare ptr @_RNvCsiI7Gbpq5_13arc_new_alloc(i64 noundef) #1
declare i32 @_RNvCsiI7Gbpq5_16arc_try_unwrap(ptr noundef) #1
declare void @_RNvCsiI7Gbpq5_10arc_drop(ptr noundef) #1
declare ptr @_RZN4alloc5alloc17h_allocate(i64 noundef) #1
declare void @_RZN4alloc5alloc17h_deallocate(ptr noundef) #1

declare void @c_increment_refcount(ptr noundef) #1
declare void @free(ptr noundef) #1

; Function Attrs: nounwind
declare ptr @__strcpy_chk(ptr noundef, ptr noundef, i64 noundef) #2

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.objectsize.i64.p0(ptr, i1 immarg, i1 immarg, i1 immarg) #3

; Function Attrs: allocsize(1)
declare ptr @realloc(ptr noundef, i64 noundef) #4

declare ptr @je_malloc(i64 noundef) #5

; --- Attributes ---
attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #4 = { allocsize(1) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #5 = { allocsize(0) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #6 = { nounwind }
attributes #7 = { allocsize(1) }

!llvm.dbg.cu = !{!70}
!llvm.module.flags = !{!67, !68, !69, !71, !72, !73}
!llvm.ident = !{!74}

!0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
!1 = distinct !DIGlobalVariable(name: "g_c_wrapper", scope: !70, file: !2, line: 14, type: !3, isLocal: true, isDefinition: true)
!2 = !DIFile(filename: "corpus/red_team_test/rust_ffi_edge_cases.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6")
!3 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "CWrapper", file: !2, line: 6, size: 128, elements: !4)
!4 = !{!5, !8}
!5 = !DIDerivedType(tag: DW_TAG_member, name: "ptr", scope: !3, file: !2, line: 7, baseType: !6, size: 64)
!6 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !7, size: 64)
!7 = !DIBasicType(name: "char", size: 8, encoding: DW_ATE_signed_char)
!8 = !DIDerivedType(tag: DW_TAG_member, name: "len", scope: !3, file: !2, line: 8, baseType: !9, size: 64, offset: 64)
!9 = !DIBasicType(name: "long", size: 64, encoding: DW_ATE_signed)
!10 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !7, size: 64)
!11 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!12 = !DIGlobalVariableExpression(var: !13, expr: !DIExpression())
!13 = distinct !DIGlobalVariable(name: "g_pin_box_alias", scope: !70, file: !2, line: 15, type: !11, isLocal: true, isDefinition: true)
!14 = !DICompositeType(tag: DW_TAG_array_type, baseType: !7, size: 120, elements: !15)
!15 = !{!16}
!16 = !DIGlobalVariableExpression(var: !17, expr: !DIExpression())
!17 = distinct !DIGlobalVariable(name: "g_phantom_raw", scope: !70, file: !2, line: 16, type: !11, isLocal: true, isDefinition: true)
!18 = !DISubrange(count: 15)
!20 = !DIGlobalVariableExpression(var: !21, expr: !DIExpression())
!21 = distinct !DIGlobalVariable(name: "g_arc_shared", scope: !70, file: !2, line: 17, type: !11, isLocal: true, isDefinition: true)
!24 = !DIGlobalVariableExpression(var: !25, expr: !DIExpression())
!25 = distinct !DIGlobalVariable(name: "g_je_ptr", scope: !70, file: !2, line: 18, type: !11, isLocal: true, isDefinition: true)
!28 = !DIGlobalVariableExpression(var: !29, expr: !DIExpression())
!29 = distinct !DIGlobalVariable(scope: null, file: !2, line: 35, type: !30, isLocal: true, isDefinition: true)
!30 = !DICompositeType(tag: DW_TAG_array_type, baseType: !7, size: 120, elements: !31)
!31 = !{!32}
!32 = !DISubrange(count: 15)
!33 = !DICompositeType(tag: DW_TAG_array_type, baseType: !7, size: 152, elements: !34)
!34 = !{!35}
!35 = !DIGlobalVariableExpression(var: !36, expr: !DIExpression())
!36 = distinct !DIGlobalVariable(scope: null, file: !2, line: 55, type: !37, isLocal: true, isDefinition: true)
!37 = !DICompositeType(tag: DW_TAG_array_type, baseType: !7, size: 152, elements: !38)
!38 = !{!39}
!39 = !DISubrange(count: 19)
!40 = !DIGlobalVariableExpression(var: !41, expr: !DIExpression())
!41 = distinct !DIGlobalVariable(scope: null, file: !2, line: 75, type: !42, isLocal: true, isDefinition: true)
!42 = !DICompositeType(tag: DW_TAG_array_type, baseType: !7, size: 200, elements: !43)
!43 = !{!44}
!44 = !DISubrange(count: 25)
!45 = !DIGlobalVariableExpression(var: !46, expr: !DIExpression())
!46 = distinct !DIGlobalVariable(scope: null, file: !2, line: 95, type: !47, isLocal: true, isDefinition: true)
!47 = !DICompositeType(tag: DW_TAG_array_type, baseType: !7, size: 112, elements: !48)
!48 = !{!49}
!49 = !DISubrange(count: 14)
!50 = !DIGlobalVariableExpression(var: !51, expr: !DIExpression())
!51 = distinct !DIGlobalVariable(scope: null, file: !2, line: 115, type: !52, isLocal: true, isDefinition: true)
!52 = !DICompositeType(tag: DW_TAG_array_type, baseType: !7, size: 144, elements: !53)
!53 = !{!54}
!54 = !DISubrange(count: 18)
!55 = !DIGlobalVariableExpression(var: !56, expr: !DIExpression())
!56 = distinct !DIGlobalVariable(scope: null, file: !2, line: 138, type: !57, isLocal: true, isDefinition: true)
!57 = !DICompositeType(tag: DW_TAG_array_type, baseType: !7, size: 136, elements: !58)
!58 = !{!59}
!59 = !DISubrange(count: 17)
!60 = !DIGlobalVariableExpression(var: !61, expr: !DIExpression())
!61 = distinct !DIGlobalVariable(scope: null, file: !2, line: 162, type: !62, isLocal: true, isDefinition: true)
!62 = !DICompositeType(tag: DW_TAG_array_type, baseType: !7, size: 96, elements: !63)
!63 = !{!64}
!64 = !DISubrange(count: 12)
!65 = !DIGlobalVariableExpression(var: !66, expr: !DIExpression())
!66 = distinct !DIGlobalVariable(scope: null, file: !2, line: 188, type: !37, isLocal: true, isDefinition: true)
!67 = !{i32 7, !"Dwarf Version", i32 5}
!68 = !{i32 2, !"Debug Info Version", i32 3}
!69 = !{i32 1, !"wchar_size", i32 4}
!70 = distinct !DICompileUnit(language: DW_LANG_C11, file: !2, producer: "Homebrew clang version 21.1.8", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, retainedTypes: !19, globals: !27, splitDebugInlining: false, nameTableKind: Apple, sysroot: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk", sdk: "MacOSX15.sdk")
!71 = !{i32 8, !"PIC Level", i32 2}
!72 = !{i32 7, !"uwtable", i32 1}
!73 = !{i32 7, !"frame-pointer", i32 1}
!74 = !{!"Homebrew clang version 21.1.8"}
!19 = !{!11}
!27 = !{!0, !12, !16, !20, !24, !28, !35, !40, !45, !50, !55, !60, !65}
!75 = distinct !DISubprogram(name: "rust_09_box_raw_alias_double_free", scope: !2, file: !2, line: 33, type: !76, scopeLine: 33, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !70, retainedNodes: !78)
!76 = !DISubroutineType(types: !77)
!77 = !{null}
!78 = !{}
!79 = !DILocalVariable(name: "boxed", scope: !75, file: !2, line: 34, type: !11)
!80 = !DILocation(line: 34, column: 11, scope: !75)
!81 = !DILocation(line: 34, column: 19, scope: !75)
!82 = !DILocation(line: 35, column: 5, scope: !75)
!83 = !DILocation(line: 38, column: 27, scope: !75)
!84 = !DILocation(line: 38, column: 19, scope: !75)
!85 = !DILocation(line: 39, column: 19, scope: !75)
!86 = !DILocation(line: 39, column: 5, scope: !75)
!87 = !DILocation(line: 39, column: 23, scope: !75)
!88 = !DILocation(line: 41, column: 10, scope: !75)
!89 = !DILocation(line: 41, column: 5, scope: !75)
!90 = !DILocation(line: 43, column: 36, scope: !75)
!91 = !DILocation(line: 43, column: 5, scope: !75)
!92 = !DILocation(line: 44, column: 1, scope: !75)
!100 = distinct !DISubprogram(name: "rust_10_vec_leak_realloc_mismatch", scope: !2, file: !2, line: 52, type: !76, scopeLine: 52, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !70, retainedNodes: !78)
!102 = !DILocalVariable(name: "vec_ptr", scope: !100, file: !2, line: 53, type: !11)
!103 = !DILocation(line: 53, column: 11, scope: !100)
!104 = !DILocation(line: 53, column: 21, scope: !100)
!105 = !DILocation(line: 54, column: 5, scope: !100)
!106 = !DILocation(line: 57, column: 24, scope: !100)
!107 = !DILocation(line: 57, column: 17, scope: !100)
!108 = !DILocation(line: 57, column: 15, scope: !100)
!109 = !DILocation(line: 59, column: 36, scope: !100)
!110 = !DILocation(line: 59, column: 5, scope: !100)
!111 = !DILocation(line: 60, column: 1, scope: !100)
!120 = distinct !DISubprogram(name: "rust_11_cstring_wrong_allocator", scope: !2, file: !2, line: 68, type: !76, scopeLine: 68, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !70, retainedNodes: !78)
!122 = !DILocalVariable(name: "raw", scope: !120, file: !2, line: 69, type: !11)
!123 = !DILocation(line: 69, column: 11, scope: !120)
!124 = !DILocation(line: 69, column: 17, scope: !120)
!125 = !DILocation(line: 71, column: 10, scope: !120)
!126 = !DILocation(line: 71, column: 5, scope: !120)
!127 = !DILocation(line: 72, column: 1, scope: !120)
!135 = distinct !DISubprogram(name: "rust_12_pin_use_after_move", scope: !2, file: !2, line: 80, type: !76, scopeLine: 80, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !70, retainedNodes: !78)
!137 = !DILocalVariable(name: "pinned", scope: !135, file: !2, line: 81, type: !11)
!138 = !DILocation(line: 81, column: 11, scope: !135)
!139 = !DILocation(line: 81, column: 20, scope: !135)
!140 = !DILocation(line: 82, column: 5, scope: !135)
!141 = !DILocation(line: 84, column: 29, scope: !135)
!142 = !DILocation(line: 84, column: 19, scope: !135)
!143 = !DILocation(line: 86, column: 36, scope: !135)
!144 = !DILocation(line: 86, column: 5, scope: !135)
!145 = !DILocation(line: 88, column: 17, scope: !135)
!146 = !DILocation(line: 88, column: 5, scope: !135)
!147 = !DILocation(line: 89, column: 1, scope: !135)
!155 = distinct !DISubprogram(name: "rust_13_phantom_dangling", scope: !2, file: !2, line: 97, type: !76, scopeLine: 97, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !70, retainedNodes: !78)
!157 = !DILocalVariable(name: "buf", scope: !155, file: !2, line: 98, type: !11)
!158 = !DILocation(line: 98, column: 11, scope: !155)
!159 = !DILocation(line: 98, column: 17, scope: !155)
!160 = !DILocation(line: 99, column: 5, scope: !155)
!161 = !DILocalVariable(name: "phantom", scope: !155, file: !2, line: 101, type: !3)
!162 = !DILocation(line: 101, column: 17, scope: !155)
!163 = !DILocation(line: 103, column: 28, scope: !155)
!164 = !DILocation(line: 103, column: 5, scope: !155)
!165 = !DILocation(line: 103, column: 22, scope: !155)
!166 = !DILocation(line: 104, column: 5, scope: !155)
!167 = !DILocation(line: 104, column: 22, scope: !155)
!168 = !DILocation(line: 106, column: 27, scope: !155)
!169 = !DILocation(line: 106, column: 19, scope: !155)
!170 = !DILocation(line: 108, column: 36, scope: !155)
!171 = !DILocation(line: 108, column: 5, scope: !155)
!172 = !DILocation(line: 110, column: 17, scope: !155)
!173 = !DILocation(line: 110, column: 5, scope: !155)
!174 = !DILocation(line: 111, column: 1, scope: !155)
!180 = distinct !DISubprogram(name: "rust_14_mutex_poisoned_ffi", scope: !2, file: !2, line: 119, type: !76, scopeLine: 119, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !70, retainedNodes: !78)
!182 = !DILocalVariable(name: "mutex_data", scope: !180, file: !2, line: 120, type: !11)
!183 = !DILocation(line: 120, column: 11, scope: !180)
!184 = !DILocation(line: 120, column: 24, scope: !180)
!185 = !DILocation(line: 121, column: 5, scope: !180)
!186 = !DILocalVariable(name: "is_poisoned", scope: !180, file: !2, line: 124, type: !9)
!187 = !DILocation(line: 124, column: 9, scope: !180)
!188 = !DILocation(line: 126, column: 9, scope: !180)
!189 = !DILocation(line: 126, column: 5, scope: !180)
!190 = !DILocation(line: 128, column: 17, scope: !180)
!191 = !DILocation(line: 128, column: 9, scope: !180)
!192 = !DILocation(line: 129, column: 5, scope: !180)
!193 = !DILocation(line: 130, column: 5, scope: !180)
!194 = !DILocation(line: 132, column: 36, scope: !180)
!195 = !DILocation(line: 132, column: 5, scope: !180)
!196 = !DILocation(line: 133, column: 1, scope: !180)
!200 = distinct !DISubprogram(name: "rust_15_arc_try_unwrap_double_drop", scope: !2, file: !2, line: 141, type: !76, scopeLine: 141, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !70, retainedNodes: !78)
!202 = !DILocalVariable(name: "arc_ptr", scope: !200, file: !2, line: 142, type: !11)
!203 = !DILocation(line: 142, column: 11, scope: !200)
!204 = !DILocation(line: 142, column: 21, scope: !200)
!205 = !DILocation(line: 144, column: 5, scope: !200)
!206 = !DILocation(line: 146, column: 27, scope: !200)
!207 = !DILocation(line: 146, column: 19, scope: !200)
!208 = !DILocation(line: 148, column: 33, scope: !200)
!209 = !DILocation(line: 148, column: 5, scope: !200)
!210 = !DILocalVariable(name: "unwrap_ok", scope: !200, file: !2, line: 150, type: !9)
!211 = !DILocation(line: 150, column: 9, scope: !200)
!212 = !DILocation(line: 150, column: 22, scope: !200)
!213 = !DILocation(line: 150, column: 22, scope: !200)
!214 = !DILocation(line: 152, column: 36, scope: !200)
!215 = !DILocation(line: 152, column: 5, scope: !200)
!216 = !DILocation(line: 154, column: 10, scope: !200)
!217 = !DILocation(line: 154, column: 5, scope: !200)
!218 = !DILocation(line: 155, column: 1, scope: !200)
!225 = distinct !DISubprogram(name: "rust_16_transmute_allocators", scope: !2, file: !2, line: 163, type: !76, scopeLine: 163, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !70, retainedNodes: !78)
!227 = !DILocalVariable(name: "je_ptr", scope: !225, file: !2, line: 164, type: !11)
!228 = !DILocation(line: 164, column: 11, scope: !225)
!229 = !DILocation(line: 164, column: 20, scope: !225)
!230 = !DILocation(line: 165, column: 5, scope: !225)
!231 = !DILocation(line: 167, column: 25, scope: !225)
!232 = !DILocation(line: 167, column: 17, scope: !225)
!233 = !DILocalVariable(name: "global_ptr", scope: !225, file: !2, line: 168, type: !11)
!234 = !DILocation(line: 168, column: 11, scope: !225)
!235 = !DILocation(line: 168, column: 24, scope: !225)
!236 = !DILocation(line: 170, column: 36, scope: !225)
!237 = !DILocation(line: 170, column: 5, scope: !225)
!238 = !DILocation(line: 171, column: 1, scope: !225)
