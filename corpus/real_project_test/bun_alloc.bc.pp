; ModuleID = 'bun_alloc.731f47d3fe31a7cb-cgu.0'
source_filename = "bun_alloc.731f47d3fe31a7cb-cgu.0"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx11.0.0"

%"core::sync::atomic::Atomic<usize>" = type { %"core::cell::UnsafeCell<core::sync::atomic::private::Align8<usize>>" }
%"core::cell::UnsafeCell<core::sync::atomic::private::Align8<usize>>" = type { %"core::sync::atomic::private::Align8<usize>" }
%"core::sync::atomic::private::Align8<usize>" = type { i64 }
%"alloc::vec::Vec<u8>" = type { %"alloc::raw_vec::RawVec<u8>", i64 }
%"alloc::raw_vec::RawVec<u8>" = type { %"alloc::raw_vec::RawVecInner", %"core::marker::PhantomData<u8>" }
%"alloc::raw_vec::RawVecInner" = type { i64, ptr, %"alloc::alloc::Global" }
%"alloc::alloc::Global" = type {}
%"core::marker::PhantomData<u8>" = type {}

@alloc_a500d906b91607583596fa15e63c2ada = private unnamed_addr constant [40 x i8] c"internal error: entered unreachable code", align 1
@anon.28345535da2df07a58cab533f3b0e62b.0 = private unnamed_addr constant [64 x i8] c"\A7\AB\AA2\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00", align 8
@_RNvCs9SN9c7tmF9T_9bun_alloc13DEFAULT_ALLOC = local_unnamed_addr constant <{}> zeroinitializer, align 1
@alloc_c3d4ef1887eb968e90d00f2342798f83 = private unnamed_addr constant [21 x i8] c"src/bun_alloc/lib.rs\00", align 1
@alloc_bc84f370ac921b69d785f34e5b94fec6 = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_c3d4ef1887eb968e90d00f2342798f83, [16 x i8] c"\14\00\00\00\00\00\00\00h\02\00\00\09\00\00\00" }>, align 8
@alloc_1b9ff5df04f6621ff32f6d88da3286ac = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_c3d4ef1887eb968e90d00f2342798f83, [16 x i8] c"\14\00\00\00\00\00\00\00d\02\00\00\0C\00\00\00" }>, align 8
@alloc_c02b03e03015a2820836183fdb52f91d = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_c3d4ef1887eb968e90d00f2342798f83, [16 x i8] c"\14\00\00\00\00\00\00\00\\\02\00\00\11\00\00\00" }>, align 8
@alloc_335fd43b3218301c660224cefa72a087 = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_c3d4ef1887eb968e90d00f2342798f83, [16 x i8] c"\14\00\00\00\00\00\00\00^\02\00\00%\00\00\00" }>, align 8
@alloc_11260e5727afc1ada428d1c0a05b9b40 = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_c3d4ef1887eb968e90d00f2342798f83, [16 x i8] c"\14\00\00\00\00\00\00\00[\02\00\00D\00\00\00" }>, align 8
@alloc_83a1d9dd3cc93e7c1c5f44c5309da745 = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_c3d4ef1887eb968e90d00f2342798f83, [16 x i8] c"\14\00\00\00\00\00\00\00[\02\00\00\14\00\00\00" }>, align 8
@_RNvCs9SN9c7tmF9T_9bun_alloc9PAGE_SIZE = local_unnamed_addr global <{ [8 x i8], [8 x i8] }> <{ [8 x i8] c"\03\00\00\00\00\00\00\00", [8 x i8] undef }>, align 8
@vtable.1 = private unnamed_addr constant <{ [24 x i8], ptr, ptr, ptr }> <{ [24 x i8] c"\00\00\00\00\00\00\00\00\18\00\00\00\00\00\00\00\08\00\00\00\00\00\00\00", ptr @_RNvXs6_Cs9SN9c7tmF9T_9bun_allocNtB5_11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_str, ptr @_RNvYNtCs9SN9c7tmF9T_9bun_alloc11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write10write_charB4_, ptr @_RNvYNtCs9SN9c7tmF9T_9bun_alloc11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_fmtB4_ }>, align 8
@alloc_ab8d1f1c46af696573bffc05aea5400e = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_c3d4ef1887eb968e90d00f2342798f83, [16 x i8] c"\14\00\00\00\00\00\00\00\D2\02\00\00\0E\00\00\00" }>, align 8
@_RNvNtNtCsg1bLsEOY8ZL_3std9panicking11panic_count18GLOBAL_PANIC_COUNT = external local_unnamed_addr global %"core::sync::atomic::Atomic<usize>"
@alloc_7395b7fd5052a2200dfc13209d237c6b = private unnamed_addr constant [15 x i8] c"not implemented", align 1
@alloc_19429f0a539d21dd513bed9681670069 = private unnamed_addr constant [34 x i8] c"src/bun_alloc/MaxHeapAllocator.rs\00", align 1
@alloc_563e88b9be90d850f438b69673a057ca = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_19429f0a539d21dd513bed9681670069, [16 x i8] c"!\00\00\00\00\00\00\00@\00\00\00\09\00\00\00" }>, align 8
@_RNvNCNKNvNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc15AST_ALLOC_SPARE0023___RUST_STD_INTERNAL_VAL = thread_local global <{ [9 x i8], [7 x i8] }> <{ [9 x i8] zeroinitializer, [7 x i8] undef }>, align 8
@_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena21HEAP_ALLOCATOR_VTABLE = local_unnamed_addr constant <{ ptr, ptr, ptr, ptr }> <{ ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena12vtable_alloc, ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena13vtable_resize, ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena12vtable_remap, ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena11vtable_free }>, align 8
@_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena22GLOBAL_MIMALLOC_VTABLE = local_unnamed_addr constant <{ ptr, ptr, ptr, ptr }> <{ ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena19global_vtable_alloc, ptr @_RNvMNtCs9SN9c7tmF9T_9bun_alloc5basicNtB2_17MimallocAllocator29resize_with_default_allocator, ptr @_RNvMNtCs9SN9c7tmF9T_9bun_alloc5basicNtB2_17MimallocAllocator28remap_with_default_allocator, ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc5basic22default_allocator_free }>, align 8
@_RNvNtCs9SN9c7tmF9T_9bun_alloc19StringImplAllocator6VTABLE = constant <{ ptr, ptr, ptr, ptr }> <{ ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc19StringImplAllocator5alloc, ptr @_RNvYNCNvMs_Cs9SN9c7tmF9T_9bun_allocNtB9_15AllocatorVTable9NO_RESIZE0INtNtNtCsgXhsEb1m4tm_4core3ops8function6FnOnceTONtNtB1b_3ffi6c_voidQShNtB9_9AlignmentjjEE9call_onceB9_, ptr @_RNvYNCNvMs_Cs9SN9c7tmF9T_9bun_allocNtB9_15AllocatorVTable8NO_REMAP0INtNtNtCsgXhsEb1m4tm_4core3ops8function6FnOnceTONtNtB1a_3ffi6c_voidQShNtB9_9AlignmentjjEE9call_onceB9_, ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc19StringImplAllocator4free }>, align 8
@_RNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator6VTABLE = local_unnamed_addr constant <{ ptr, ptr, ptr, ptr }> <{ ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator5alloc, ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator6resize, ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator5remap, ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator4free }>, align 8
@alloc_e33b96dab46ed5271d4409d2538c17ec = private unnamed_addr constant <{ ptr, ptr, ptr, ptr }> <{ ptr @_RNvMNtCs9SN9c7tmF9T_9bun_alloc5basicNtB2_17MimallocAllocator28alloc_with_default_allocator, ptr @_RNvMNtCs9SN9c7tmF9T_9bun_alloc5basicNtB2_17MimallocAllocator29resize_with_default_allocator, ptr @_RNvMNtCs9SN9c7tmF9T_9bun_alloc5basicNtB2_17MimallocAllocator28remap_with_default_allocator, ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc5basic22default_allocator_free }>, align 8
@_RNvNtCs9SN9c7tmF9T_9bun_alloc5basic11C_ALLOCATOR = local_unnamed_addr constant <{ ptr, [8 x i8] }> <{ ptr @alloc_e33b96dab46ed5271d4409d2538c17ec, [8 x i8] c"\0C\11\FA\EE\0B\00\00\00" }>, align 8
@_RNvNtCs9SN9c7tmF9T_9bun_alloc5basic11Z_ALLOCATOR = local_unnamed_addr constant <{ ptr, [8 x i8] }> <{ ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc5basic18Z_ALLOCATOR_VTABLE, [8 x i8] c"#\01GC\10\A1\02\00" }>, align 8
@_RNvNtCs9SN9c7tmF9T_9bun_alloc5basic18Z_ALLOCATOR_VTABLE = constant <{ ptr, ptr, ptr, ptr }> <{ ptr @_RNvMs_NtCs9SN9c7tmF9T_9bun_alloc5basicNtB4_10ZAllocator22alloc_with_z_allocator, ptr @_RNvMs_NtCs9SN9c7tmF9T_9bun_alloc5basicNtB4_10ZAllocator23resize_with_z_allocator, ptr @_RNvYNCNvMs_Cs9SN9c7tmF9T_9bun_allocNtB9_15AllocatorVTable8NO_REMAP0INtNtNtCsgXhsEb1m4tm_4core3ops8function6FnOnceTONtNtB1a_3ffi6c_voidQShNtB9_9AlignmentjjEE9call_onceB9_, ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc5basic22default_allocator_free }>, align 8
@alloc_af2fbbc7f1af681643fea55c93c29ac9 = private unnamed_addr constant [26 x i8] c"src/bun_alloc/c_thunks.rs\00", align 1
@alloc_0e3300b2a43a173da7f566e00bdaa86b = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_af2fbbc7f1af681643fea55c93c29ac9, [16 x i8] c"\19\00\00\00\00\00\00\00\18\00\00\00\09\00\00\00" }>, align 8
@_RNvNtCs9SN9c7tmF9T_9bun_alloc8fallback11C_ALLOCATOR = local_unnamed_addr constant <{}> zeroinitializer, align 1
@_RNvNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc9AST_ALLOC = thread_local local_unnamed_addr global [8 x i8] zeroinitializer, align 8
@_RNvNtNtCs9SN9c7tmF9T_9bun_alloc8fallback1z9ALLOCATOR = local_unnamed_addr constant <{}> zeroinitializer, align 1
@_RNvNvCs9SN9c7tmF9T_9bun_alloc14bss_arena_bump4BASE = internal global [8 x i8] zeroinitializer, align 8
@_RNvNvCs9SN9c7tmF9T_9bun_alloc14bss_arena_bump6CURSOR = internal global [8 x i8] zeroinitializer, align 8
@_RNvNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone4LOCK = internal global <{ [9 x i8], [7 x i8] }> <{ [9 x i8] zeroinitializer, [7 x i8] undef }>, align 8
@_RNvNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone5ZONES = internal global [24 x i8] c"\00\00\00\00\00\00\00\00\08\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00", align 8
@alloc_fc8cfb579032aab044b502c62a1fa507 = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_c3d4ef1887eb968e90d00f2342798f83, [16 x i8] c"\14\00\00\00\00\00\00\00\C3\02\00\00\11\00\00\00" }>, align 8
@alloc_7389700e92edf4cfbbbb3ad1262599b9 = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_c3d4ef1887eb968e90d00f2342798f83, [16 x i8] c"\14\00\00\00\00\00\00\00\DF\0A\00\00\0C\00\00\00" }>, align 8
@alloc_6e8c82fb888968a428c64f4952af931d = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_c3d4ef1887eb968e90d00f2342798f83, [16 x i8] c"\14\00\00\00\00\00\00\00\F5\0A\00\00\16\00\00\00" }>, align 8

; <std::sys::sync::once_box::OnceBox<std::sys::pal::unix::sync::mutex::Mutex>>::initialize::<<std::sys::sync::mutex::pthread::Mutex>::get::{closure#0}>
; Function Attrs: cold nounwind
define internal fastcc noundef nonnull align 8 ptr @_RINvMNtNtNtCsg1bLsEOY8ZL_3std3sys4sync8once_boxINtB3_7OnceBoxNtNtNtNtNtB7_3pal4unix4sync5mutex5MutexE10initializeNCNvMNtNtB5_5mutex7pthreadNtB1S_5Mutex3get0ECs9SN9c7tmF9T_9bun_alloc() unnamed_addr #0 personality ptr @rust_eh_personality !dbg !6 {
start:
; call __rustc::__rust_no_alloc_shim_is_unstable_v2
  tail call void @_RNvCs3TqXShXgh4d_7___rustc35___rust_no_alloc_shim_is_unstable_v2() #33, !dbg !15, !noalias !47
; call __rustc::__rust_alloc
  %0 = tail call noundef align 8 dereferenceable_or_null(64) ptr @_RNvCs3TqXShXgh4d_7___rustc12___rust_alloc(i64 noundef range(i64 0, -9223372036854775808) 64, i64 noundef 8) #33, !dbg !50, !noalias !47
  %1 = icmp eq ptr %0, null, !dbg !51
  br i1 %1, label %bb2.i.i, label %_RNCNvMNtNtNtNtCsg1bLsEOY8ZL_3std3sys4sync5mutex7pthreadNtB4_5Mutex3get0Cs9SN9c7tmF9T_9bun_alloc.exit, !dbg !52, !prof !53

bb2.i.i:                                          ; preds = %start
; call alloc::alloc::handle_alloc_error
  tail call void @_RNvNtCskhhhlZ4wWGP_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 64) #34, !dbg !54, !noalias !47
  unreachable, !dbg !54

_RNCNvMNtNtNtNtCsg1bLsEOY8ZL_3std3sys4sync5mutex7pthreadNtB4_5Mutex3get0Cs9SN9c7tmF9T_9bun_alloc.exit: ; preds = %start
  tail call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(64) %0, ptr noundef nonnull align 8 dereferenceable(64) @anon.28345535da2df07a58cab533f3b0e62b.0, i64 64, i1 false), !dbg !55
; call <std::sys::pal::unix::sync::mutex::Mutex>::init
  tail call void @_RNvMNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutexNtB2_5Mutex4init(ptr noundef nonnull align 8 %0) #33, !dbg !57
  %2 = cmpxchg ptr @_RNvNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone4LOCK, ptr null, ptr %0 release acquire, align 8, !dbg !59
  %3 = extractvalue { ptr, i1 } %2, 1, !dbg !59
  br i1 %3, label %bb5, label %bb3, !dbg !70

bb3:                                              ; preds = %_RNCNvMNtNtNtNtCsg1bLsEOY8ZL_3std3sys4sync5mutex7pthreadNtB4_5Mutex3get0Cs9SN9c7tmF9T_9bun_alloc.exit
  %4 = extractvalue { ptr, i1 } %2, 0, !dbg !59
; call <std::sys::pal::unix::sync::mutex::Mutex as core::ops::drop::Drop>::drop
  tail call void @_RNvXs2_NtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutexNtB5_5MutexNtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4drop(ptr noundef nonnull align 8 %0) #33, !dbg !71, !noalias !83
; call __rustc::__rust_dealloc
  tail call void @_RNvCs3TqXShXgh4d_7___rustc14___rust_dealloc(ptr noundef nonnull %0, i64 noundef 64, i64 noundef 8) #33, !dbg !86, !noalias !100
  br label %bb5, !dbg !103

bb5:                                              ; preds = %_RNCNvMNtNtNtNtCsg1bLsEOY8ZL_3std3sys4sync5mutex7pthreadNtB4_5Mutex3get0Cs9SN9c7tmF9T_9bun_alloc.exit, %bb3
  %_0.sroa.0.0 = phi ptr [ %4, %bb3 ], [ %0, %_RNCNvMNtNtNtNtCsg1bLsEOY8ZL_3std3sys4sync5mutex7pthreadNtB4_5Mutex3get0Cs9SN9c7tmF9T_9bun_alloc.exit ], !dbg !104
  %5 = icmp ne ptr %_0.sroa.0.0, null
  tail call void @llvm.assume(i1 %5)
  ret ptr %_0.sroa.0.0, !dbg !110
}

; std::sys::thread_local::native::eager::destroy::<core::cell::Cell<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState>>>>
; Function Attrs: nounwind
define internal void @_RINvNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eager7destroyINtNtCsgXhsEb1m4tm_4core4cell4CellINtNtB1a_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEEB2D_(ptr noundef captures(none) initializes((8, 9)) %0) unnamed_addr #1 personality ptr @rust_eh_personality !dbg !111 {
start:
  %_10.i.i = getelementptr inbounds nuw i8, ptr %0, i64 8, !dbg !116
  store i8 2, ptr %_10.i.i, align 1, !dbg !135, !noalias !139
  tail call void @llvm.experimental.noalias.scope.decl(metadata !144), !dbg !147
  tail call void @llvm.experimental.noalias.scope.decl(metadata !148), !dbg !151
  tail call void @llvm.experimental.noalias.scope.decl(metadata !154), !dbg !157
  %1 = load ptr, ptr %0, align 8, !dbg !160, !alias.scope !163, !noalias !139, !align !164, !noundef !14
  %2 = icmp eq ptr %1, null, !dbg !160
  br i1 %2, label %_RINvNtNtCsg1bLsEOY8ZL_3std3sys12thread_local20abort_on_dtor_unwindNCINvNtNtB2_6native5eager7destroyINtNtCsgXhsEb1m4tm_4core4cell4CellINtNtB1E_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEE0EB37_.exit, label %bb2.i.i.i.i.i, !dbg !160

bb2.i.i.i.i.i:                                    ; preds = %start
  tail call void @llvm.experimental.noalias.scope.decl(metadata !165), !dbg !168
  %3 = getelementptr inbounds nuw i8, ptr %1, i64 16400, !dbg !171
  tail call void @llvm.experimental.noalias.scope.decl(metadata !174), !dbg !171
  %4 = getelementptr inbounds nuw i8, ptr %1, i64 16408, !dbg !177
  %5 = load i8, ptr %4, align 8, !dbg !177, !range !180, !alias.scope !181, !noalias !182, !noundef !14
  %6 = icmp eq i8 %5, 2, !dbg !177
  br i1 %6, label %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEB1j_.exit.i.i.i.i.i, label %bb2.i.i.i.i.i.i.i.i, !dbg !177

bb2.i.i.i.i.i.i.i.i:                              ; preds = %bb2.i.i.i.i.i
  tail call void @llvm.experimental.noalias.scope.decl(metadata !185), !dbg !177
  tail call void @llvm.experimental.noalias.scope.decl(metadata !188), !dbg !191
  %_2.i.i.i.i.i.i.i.i.i.i = trunc nuw i8 %5 to i1, !dbg !194
  br i1 %_2.i.i.i.i.i.i.i.i.i.i, label %bb2.i.i.i.i.i.i.i.i.i.i, label %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEB1j_.exit.i.i.i.i.i, !dbg !194

bb2.i.i.i.i.i.i.i.i.i.i:                          ; preds = %bb2.i.i.i.i.i.i.i.i
  %_5.i.i.i.i.i.i.i.i.i.i = load ptr, ptr %3, align 8, !dbg !201, !alias.scope !205, !noalias !182, !nonnull !14, !noundef !14
  tail call void @mi_heap_destroy(ptr noundef nonnull %_5.i.i.i.i.i.i.i.i.i.i) #33, !dbg !206, !noalias !207
  br label %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEB1j_.exit.i.i.i.i.i, !dbg !208

_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEB1j_.exit.i.i.i.i.i: ; preds = %bb2.i.i.i.i.i.i.i.i.i.i, %bb2.i.i.i.i.i.i.i.i, %bb2.i.i.i.i.i
; call __rustc::__rust_dealloc
  tail call void @_RNvCs3TqXShXgh4d_7___rustc14___rust_dealloc(ptr noundef nonnull %1, i64 noundef 16416, i64 noundef 8) #33, !dbg !209, !noalias !218
  br label %_RINvNtNtCsg1bLsEOY8ZL_3std3sys12thread_local20abort_on_dtor_unwindNCINvNtNtB2_6native5eager7destroyINtNtCsgXhsEb1m4tm_4core4cell4CellINtNtB1E_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEE0EB37_.exit, !dbg !160

_RINvNtNtCsg1bLsEOY8ZL_3std3sys12thread_local20abort_on_dtor_unwindNCINvNtNtB2_6native5eager7destroyINtNtCsgXhsEb1m4tm_4core4cell4CellINtNtB1E_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEE0EB37_.exit: ; preds = %start, %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEB1j_.exit.i.i.i.i.i
  ret void, !dbg !221
}

; bun_alloc::realloc_raw
; Function Attrs: nounwind
define { i64, ptr } @_RNvCs9SN9c7tmF9T_9bun_alloc11realloc_raw(ptr noundef %ptr, i64 noundef %new_size) unnamed_addr #1 !dbg !222 {
start:
  %new_ptr = tail call noundef ptr @mi_realloc(ptr noundef %ptr, i64 noundef %new_size) #33, !dbg !224
  %0 = icmp eq ptr %new_ptr, null, !dbg !225
  %. = zext i1 %0 to i64, !dbg !227
  %1 = insertvalue { i64, ptr } poison, i64 %., 0, !dbg !227
  %2 = insertvalue { i64, ptr } %1, ptr %new_ptr, 1, !dbg !227
  ret { i64, ptr } %2, !dbg !227
}

; bun_alloc::default_dupe
; Function Attrs: nounwind
define { ptr, i64 } @_RNvCs9SN9c7tmF9T_9bun_alloc12default_dupe(ptr noalias noundef nonnull readonly captures(none) %src.0, i64 noundef range(i64 0, -9223372036854775808) %src.1) unnamed_addr #1 !dbg !228 {
start:
  %0 = icmp eq i64 %src.1, 0, !dbg !229
  br i1 %0, label %bb3, label %bb2, !dbg !229

bb2:                                              ; preds = %start
  %1 = tail call noundef ptr @mi_malloc(i64 noundef %src.1) #33, !dbg !230
  %2 = icmp eq ptr %1, null, !dbg !249
  br i1 %2, label %bb6, label %bb7, !dbg !249, !prof !53

bb3:                                              ; preds = %start, %bb7
  %_0.sroa.0.0 = phi ptr [ %1, %bb7 ], [ inttoptr (i64 1 to ptr), %start ], !dbg !251
  %3 = insertvalue { ptr, i64 } poison, ptr %_0.sroa.0.0, 0, !dbg !252
  %4 = insertvalue { ptr, i64 } %3, i64 %src.1, 1, !dbg !252
  ret { ptr, i64 } %4, !dbg !252

bb6:                                              ; preds = %bb2
; call bun_alloc::out_of_memory
  tail call void @_RNvCs9SN9c7tmF9T_9bun_alloc13out_of_memory() #35, !dbg !253
  unreachable, !dbg !253

bb7:                                              ; preds = %bb2
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %1, ptr nonnull align 1 %src.0, i64 %src.1, i1 false), !dbg !262
  br label %bb3, !dbg !252
}

; bun_alloc::out_of_memory
; Function Attrs: cold noinline noreturn nounwind
define void @_RNvCs9SN9c7tmF9T_9bun_alloc13out_of_memory() unnamed_addr #2 !dbg !266 {
start:
  tail call void @__bun_crash_handler_out_of_memory() #34, !dbg !267
  unreachable, !dbg !267
}

; bun_alloc::realloc_slice
; Function Attrs: nounwind
define { ptr, i64 } @_RNvCs9SN9c7tmF9T_9bun_alloc13realloc_slice(ptr noalias noundef nonnull %slice.0, i64 noundef range(i64 0, -9223372036854775808) %slice.1, i64 noundef %new_size) unnamed_addr #1 !dbg !268 {
start:
  %new_ptr = tail call noundef ptr @mi_realloc(ptr noundef nonnull %slice.0, i64 noundef %new_size) #33, !dbg !269
  %0 = insertvalue { ptr, i64 } poison, ptr %new_ptr, 0, !dbg !270
  %1 = insertvalue { ptr, i64 } %0, i64 %new_size, 1, !dbg !270
  ret { ptr, i64 } %1, !dbg !270
}

; bun_alloc::bss_arena_bump
; Function Attrs: nounwind
define noundef ptr @_RNvCs9SN9c7tmF9T_9bun_alloc14bss_arena_bump(i64 noundef %size, i64 noundef %align) unnamed_addr #1 !dbg !271 {
start:
  %0 = load atomic ptr, ptr @_RNvNvCs9SN9c7tmF9T_9bun_alloc14bss_arena_bump4BASE acquire, align 8, !dbg !272
  %1 = icmp eq ptr %0, null, !dbg !277
  br i1 %1, label %bb1, label %bb8, !dbg !277, !prof !53

bb1:                                              ; preds = %start
; call bun_alloc::bss_arena_bump::map_arena
  %2 = tail call fastcc noundef ptr @_RNvNvCs9SN9c7tmF9T_9bun_alloc14bss_arena_bump9map_arena() #36, !dbg !279
  %3 = cmpxchg ptr @_RNvNvCs9SN9c7tmF9T_9bun_alloc14bss_arena_bump4BASE, ptr null, ptr %2 acq_rel acquire, align 8, !dbg !280
  %4 = extractvalue { ptr, i1 } %3, 1, !dbg !280
  %5 = extractvalue { ptr, i1 } %3, 0, !dbg !280
  %spec.select = select i1 %4, ptr %2, ptr %5, !dbg !286
  br label %bb8, !dbg !287

bb8:                                              ; preds = %start, %bb1
  %base.sroa.0.1 = phi ptr [ %spec.select, %bb1 ], [ %0, %start ], !dbg !288
  %6 = load atomic i64, ptr @_RNvNvCs9SN9c7tmF9T_9bun_alloc14bss_arena_bump6CURSOR monotonic, align 8, !dbg !289
  %_11 = add i64 %align, -1
  %_13 = sub i64 0, %align
  br label %bb9, !dbg !294

bb9:                                              ; preds = %bb11, %bb8
  %cur.sroa.0.0 = phi i64 [ %6, %bb8 ], [ %9, %bb11 ], !dbg !296
  %_10 = add i64 %_11, %cur.sroa.0.0, !dbg !297
  %aligned = and i64 %_10, %_13, !dbg !297
  %next = add i64 %aligned, %size, !dbg !298
  %_16 = icmp ugt i64 %next, 4194304, !dbg !300
  br i1 %_16, label %bb10, label %bb11, !dbg !300

bb11:                                             ; preds = %bb9
  %7 = cmpxchg weak ptr @_RNvNvCs9SN9c7tmF9T_9bun_alloc14bss_arena_bump6CURSOR, i64 %cur.sroa.0.0, i64 %next acq_rel monotonic, align 8, !dbg !302
  %8 = extractvalue { i64, i1 } %7, 1, !dbg !302
  %9 = extractvalue { i64, i1 } %7, 0, !dbg !302
  br i1 %8, label %bb13, label %bb9, !dbg !307

bb10:                                             ; preds = %bb9
  %_27 = tail call noundef ptr @mmap(ptr noundef null, i64 noundef %size, i32 noundef 3, i32 noundef 4098, i32 noundef -1, i64 noundef 0) #33, !dbg !308
  %_28 = icmp eq ptr %_27, inttoptr (i64 -1 to ptr), !dbg !311
  br i1 %_28, label %bb19, label %bb14, !dbg !311, !prof !53

bb13:                                             ; preds = %bb11
  %10 = getelementptr inbounds nuw i8, ptr %base.sroa.0.1, i64 %aligned, !dbg !313
  br label %bb14, !dbg !319

bb14:                                             ; preds = %bb10, %bb13
  %_0.sroa.0.0 = phi ptr [ %10, %bb13 ], [ %_27, %bb10 ], !dbg !319
  ret ptr %_0.sroa.0.0, !dbg !320

bb19:                                             ; preds = %bb10
; call bun_alloc::out_of_memory
  tail call void @_RNvCs9SN9c7tmF9T_9bun_alloc13out_of_memory() #35, !dbg !321
  unreachable, !dbg !321
}

; bun_alloc::copy_lowercase
; Function Attrs: nounwind
define { ptr, i64 } @_RNvCs9SN9c7tmF9T_9bun_alloc14copy_lowercase(ptr noalias noundef nonnull readonly captures(address) %in_.0, i64 noundef range(i64 0, -9223372036854775808) %in_.1, ptr noalias noundef nonnull %out.0, i64 noundef range(i64 0, -9223372036854775808) %out.1) unnamed_addr #1 personality ptr @rust_eh_personality !dbg !322 {
start:
  br label %bb1, !dbg !323

bb1:                                              ; preds = %bb25, %start
  %in_slice.sroa.0.0 = phi ptr [ %in_.0, %start ], [ %_74, %bb25 ], !dbg !326
  %in_slice.sroa.8.0 = phi i64 [ %in_.1, %start ], [ %_70, %bb25 ], !dbg !326
  %out_off.sroa.0.0 = phi i64 [ 0, %start ], [ %4, %bb25 ], !dbg !327
  %_40 = getelementptr inbounds nuw i8, ptr %in_slice.sroa.0.0, i64 %in_slice.sroa.8.0, !dbg !328
  br label %bb2, !dbg !343

bb2:                                              ; preds = %bb5, %bb1
  %iter.sroa.8.0 = phi i64 [ 0, %bb1 ], [ %_9.0.i, %bb5 ], !dbg !345
  %iter.sroa.0.0 = phi ptr [ %in_slice.sroa.0.0, %bb1 ], [ %_16.i.i, %bb5 ], !dbg !345
  %_6.i.i = icmp eq ptr %iter.sroa.0.0, %_40, !dbg !346
  br i1 %_6.i.i, label %bb6, label %bb5, !dbg !365

bb5:                                              ; preds = %bb2
  %_9.0.i = add i64 %iter.sroa.8.0, 1, !dbg !366
  %_16.i.i = getelementptr inbounds nuw i8, ptr %iter.sroa.0.0, i64 1, !dbg !369
  %c = load i8, ptr %iter.sroa.0.0, align 1, !dbg !373, !noundef !14
  %0 = add i8 %c, -65, !dbg !374
  %or.cond = icmp ult i8 %0, 26, !dbg !374
  br i1 %or.cond, label %bb7, label %bb2, !dbg !374

bb6:                                              ; preds = %bb2
  %_31 = add i64 %out_off.sroa.0.0, %in_slice.sroa.8.0, !dbg !377
  %_81 = icmp ult i64 %_31, %out_off.sroa.0.0, !dbg !378
  %_75.not = icmp ugt i64 %_31, %out.1
  %or.cond15 = or i1 %_81, %_75.not, !dbg !378
  br i1 %or.cond15, label %bb27, label %bb26, !dbg !378, !prof !394

bb27:                                             ; preds = %bb6
; call core::slice::index::slice_index_fail
  tail call void @_RNvNtNtCsgXhsEb1m4tm_4core5slice5index16slice_index_fail(i64 noundef %out_off.sroa.0.0, i64 noundef %_31, i64 noundef %out.1, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_1b9ff5df04f6621ff32f6d88da3286ac) #35, !dbg !395
  unreachable, !dbg !395

bb26:                                             ; preds = %bb6
  %_84 = getelementptr inbounds nuw i8, ptr %out.0, i64 %out_off.sroa.0.0, !dbg !396
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %_84, ptr nonnull readonly align 1 %in_slice.sroa.0.0, i64 range(i64 0, -9223372036854775808) %in_slice.sroa.8.0, i1 false), !dbg !400, !alias.scope !407, !noalias !411
  %_85.not = icmp samesign ugt i64 %in_.1, %out.1
  br i1 %_85.not, label %bb32, label %bb31, !dbg !413, !prof !394

bb32:                                             ; preds = %bb26
; call core::slice::index::slice_index_fail
  tail call void @_RNvNtNtCsgXhsEb1m4tm_4core5slice5index16slice_index_fail(i64 noundef 0, i64 noundef %in_.1, i64 noundef %out.1, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_bc84f370ac921b69d785f34e5b94fec6) #35, !dbg !422
  unreachable, !dbg !422

bb31:                                             ; preds = %bb26
  %1 = insertvalue { ptr, i64 } poison, ptr %out.0, 0, !dbg !423
  %2 = insertvalue { ptr, i64 } %1, i64 %in_.1, 1, !dbg !423
  ret { ptr, i64 } %2, !dbg !423

bb7:                                              ; preds = %bb5
  %_18 = add i64 %iter.sroa.8.0, %out_off.sroa.0.0, !dbg !424
  %_51 = icmp ult i64 %_18, %out_off.sroa.0.0, !dbg !425
  %_45.not = icmp ugt i64 %_18, %out.1
  %or.cond16 = or i1 %_51, %_45.not, !dbg !425
  br i1 %or.cond16, label %bb12, label %bb11, !dbg !425, !prof !394

bb12:                                             ; preds = %bb7
; call core::slice::index::slice_index_fail
  tail call void @_RNvNtNtCsgXhsEb1m4tm_4core5slice5index16slice_index_fail(i64 noundef %out_off.sroa.0.0, i64 noundef %_18, i64 noundef %out.1, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_83a1d9dd3cc93e7c1c5f44c5309da745) #35, !dbg !429
  unreachable, !dbg !429

bb11:                                             ; preds = %bb7
  %_55.not = icmp ugt i64 %iter.sroa.8.0, %in_slice.sroa.8.0
  br i1 %_55.not, label %bb17, label %bb15, !dbg !430, !prof !394

bb15:                                             ; preds = %bb11
  %_54 = getelementptr inbounds nuw i8, ptr %out.0, i64 %out_off.sroa.0.0, !dbg !434
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %_54, ptr nonnull readonly align 1 %in_slice.sroa.0.0, i64 range(i64 0, -9223372036854775808) %iter.sroa.8.0, i1 false), !dbg !437, !alias.scope !441, !noalias !445
  %_25 = icmp ult i64 %_18, %out.1, !dbg !447
  br i1 %_25, label %bb9, label %panic, !dbg !447

bb17:                                             ; preds = %bb11
; call core::slice::index::slice_index_fail
  tail call void @_RNvNtNtCsgXhsEb1m4tm_4core5slice5index16slice_index_fail(i64 noundef 0, i64 noundef %iter.sroa.8.0, i64 noundef %in_slice.sroa.8.0, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_11260e5727afc1ada428d1c0a05b9b40) #35, !dbg !448
  unreachable, !dbg !448

bb9:                                              ; preds = %bb15
  %_22 = or disjoint i8 %c, 32, !dbg !449
  %3 = getelementptr inbounds nuw i8, ptr %out.0, i64 %_18, !dbg !447
  store i8 %_22, ptr %3, align 1, !dbg !447
  %_67.not = icmp ult i64 %iter.sroa.8.0, %in_slice.sroa.8.0, !dbg !454
  br i1 %_67.not, label %bb25, label %bb24, !dbg !454, !prof !462

panic:                                            ; preds = %bb15
; call core::panicking::panic_bounds_check
  tail call void @_RNvNtCsgXhsEb1m4tm_4core9panicking18panic_bounds_check(i64 noundef %_18, i64 noundef %out.1, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_c02b03e03015a2820836183fdb52f91d) #35, !dbg !447
  unreachable, !dbg !447

bb25:                                             ; preds = %bb9
  %_70 = sub nuw nsw i64 %in_slice.sroa.8.0, %_9.0.i, !dbg !463
  %_74 = getelementptr inbounds nuw i8, ptr %in_slice.sroa.0.0, i64 %_9.0.i, !dbg !464
  %4 = add i64 %_9.0.i, %out_off.sroa.0.0, !dbg !469
  br label %bb1, !dbg !470

bb24:                                             ; preds = %bb9
; call core::slice::index::slice_index_fail
  tail call void @_RNvNtNtCsgXhsEb1m4tm_4core5slice5index16slice_index_fail(i64 noundef %_9.0.i, i64 noundef %in_slice.sroa.8.0, i64 noundef %in_slice.sroa.8.0, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_335fd43b3218301c660224cefa72a087) #35, !dbg !471
  unreachable, !dbg !471
}

; bun_alloc::free_sensitive_cstr
; Function Attrs: nounwind
define void @_RNvCs9SN9c7tmF9T_9bun_alloc19free_sensitive_cstr(ptr noundef %p) unnamed_addr #1 !dbg !472 {
start:
  %0 = alloca [8 x i8], align 8, !dbg !473
  %1 = icmp eq ptr %p, null, !dbg !488
  br i1 %1, label %bb4, label %bb2, !dbg !488

bb2:                                              ; preds = %start
  %len = tail call noundef i64 @strlen(ptr noundef nonnull dereferenceable(1) %p) #33, !dbg !489
  tail call void @llvm.memset.p0.i64(ptr nonnull align 1 %p, i8 0, i64 %len, i1 false), !dbg !490
  call void @llvm.lifetime.start.p0(ptr nonnull %0), !dbg !496
  store ptr %p, ptr %0, align 8, !dbg !496
  call void asm sideeffect "", "r,~{memory}"(ptr nonnull %0) #33, !dbg !496, !srcloc !501
  call void @llvm.lifetime.end.p0(ptr nonnull %0), !dbg !496
  fence syncscope("singlethread") seq_cst, !dbg !502
  call void @mi_free(ptr noundef nonnull %p) #33, !dbg !505
  br label %bb4, !dbg !508

bb4:                                              ; preds = %start, %bb2
  ret void, !dbg !508
}

; bun_alloc::copy_lowercase_if_needed
; Function Attrs: nounwind
define { ptr, i64 } @_RNvCs9SN9c7tmF9T_9bun_alloc24copy_lowercase_if_needed(ptr noalias noundef nonnull readonly captures(address, read_provenance) %in_.0, i64 noundef range(i64 0, -9223372036854775808) %in_.1, ptr noalias noundef nonnull %out.0, i64 noundef range(i64 0, -9223372036854775808) %out.1) unnamed_addr #1 personality ptr @rust_eh_personality !dbg !509 {
start:
  %_10 = getelementptr inbounds nuw i8, ptr %in_.0, i64 %in_.1, !dbg !510
  br label %bb1.i, !dbg !519

bb1.i:                                            ; preds = %bb13.i, %start
  %_221.i = phi ptr [ %_22.i, %bb13.i ], [ %in_.0, %start ]
  %_12.not.not.not.i.not = icmp eq ptr %_221.i, %_10, !dbg !522
  br i1 %_12.not.not.not.i.not, label %bb4, label %bb13.i, !dbg !530

bb13.i:                                           ; preds = %bb1.i
  %_22.i = getelementptr inbounds nuw i8, ptr %_221.i, i64 1, !dbg !531
  %0 = load i8, ptr %_221.i, align 1, !dbg !534, !alias.scope !546, !noalias !551, !noundef !14
  %1 = add i8 %0, -65, !dbg !534
  %_0.sroa.0.0.off0.i.i.i = icmp ult i8 %1, 26, !dbg !534
  br i1 %_0.sroa.0.0.off0.i.i.i, label %bb2, label %bb1.i, !dbg !554

bb4:                                              ; preds = %bb1.i
  %2 = insertvalue { ptr, i64 } poison, ptr %in_.0, 0, !dbg !555
  %3 = insertvalue { ptr, i64 } %2, i64 %in_.1, 1, !dbg !555
  br label %bb5, !dbg !555

bb2:                                              ; preds = %bb13.i
; call bun_alloc::copy_lowercase
  %4 = tail call { ptr, i64 } @_RNvCs9SN9c7tmF9T_9bun_alloc14copy_lowercase(ptr noalias noundef nonnull readonly captures(address, read_provenance) %in_.0, i64 noundef %in_.1, ptr noalias noundef nonnull %out.0, i64 noundef %out.1) #33, !dbg !556
  br label %bb5, !dbg !555

bb5:                                              ; preds = %bb2, %bb4
  %.merged = phi { ptr, i64 } [ %4, %bb2 ], [ %3, %bb4 ], !dbg !557
  ret { ptr, i64 } %.merged, !dbg !557
}

; bun_alloc::buf_print
; Function Attrs: nounwind
define { ptr, i64 } @_RNvCs9SN9c7tmF9T_9bun_alloc9buf_print(ptr noalias noundef nonnull %buf.0, i64 noundef range(i64 0, -9223372036854775808) %buf.1, ptr noundef nonnull %args.0, ptr noundef nonnull %args.1) unnamed_addr #1 !dbg !558 {
start:
  %c = alloca [24 x i8], align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %c), !dbg !559
  store ptr %buf.0, ptr %c, align 8, !dbg !560
  %0 = getelementptr inbounds nuw i8, ptr %c, i64 8, !dbg !560
  store i64 %buf.1, ptr %0, align 8, !dbg !560
  %1 = getelementptr inbounds nuw i8, ptr %c, i64 16, !dbg !560
  store i64 0, ptr %1, align 8, !dbg !560
; call core::fmt::write
  %_4 = call noundef zeroext i1 @_RNvNtCsgXhsEb1m4tm_4core3fmt5write(ptr noundef nonnull %c, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(48) @vtable.1, ptr noundef nonnull %args.0, ptr noundef nonnull %args.1) #33, !dbg !561
  br i1 %_4, label %bb3, label %bb5, !dbg !563

bb5:                                              ; preds = %start
  %len = load i64, ptr %1, align 8, !dbg !568, !noundef !14
  %_10.1 = load i64, ptr %0, align 8, !dbg !569, !noundef !14
  %_12.not = icmp ugt i64 %len, %_10.1
  br i1 %_12.not, label %bb8, label %bb6, !dbg !571, !prof !394

bb6:                                              ; preds = %bb5
  %_10.0 = load ptr, ptr %c, align 8, !dbg !569, !nonnull !14, !noundef !14
  br label %bb3, !dbg !581

bb8:                                              ; preds = %bb5
; call core::slice::index::slice_index_fail
  call void @_RNvNtNtCsgXhsEb1m4tm_4core5slice5index16slice_index_fail(i64 noundef 0, i64 noundef %len, i64 noundef %_10.1, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_ab8d1f1c46af696573bffc05aea5400e) #35, !dbg !582
  unreachable, !dbg !582

bb3:                                              ; preds = %start, %bb6
  %_0.sroa.3.0 = phi i64 [ %len, %bb6 ], [ undef, %start ], !dbg !583
  %_0.sroa.0.0 = phi ptr [ %_10.0, %bb6 ], [ null, %start ], !dbg !583
  call void @llvm.lifetime.end.p0(ptr nonnull %c), !dbg !584
  %2 = insertvalue { ptr, i64 } poison, ptr %_0.sroa.0.0, 0, !dbg !581
  %3 = insertvalue { ptr, i64 } %2, i64 %_0.sroa.3.0, 1, !dbg !581
  ret { ptr, i64 } %3, !dbg !581
}

; <bun_alloc::basic::MimallocAllocator>::alloc_with_default_allocator
; Function Attrs: nounwind
define noundef ptr @_RNvMNtCs9SN9c7tmF9T_9bun_alloc5basicNtB2_17MimallocAllocator28alloc_with_default_allocator(ptr readnone captures(none) %_1, i64 noundef %len, i8 noundef %alignment, i64 %_4) unnamed_addr #1 !dbg !244 {
start:
  %0 = and i8 %alignment, 63, !dbg !585
  %_5.i = icmp samesign ugt i8 %0, 4, !dbg !590
  br i1 %_5.i, label %bb1.i, label %bb2.i, !dbg !595

bb2.i:                                            ; preds = %start
  %1 = tail call noundef ptr @mi_malloc(i64 noundef %len) #33, !dbg !596
  br label %_RNvMNtCs9SN9c7tmF9T_9bun_alloc5basicNtB2_17MimallocAllocator13aligned_alloc.exit, !dbg !596

bb1.i:                                            ; preds = %start
  %2 = zext nneg i8 %0 to i64, !dbg !585
  %_4.i = shl nuw i64 1, %2, !dbg !585
  %3 = tail call noundef ptr @mi_malloc_aligned(i64 noundef %len, i64 noundef %_4.i) #33, !dbg !597
  br label %_RNvMNtCs9SN9c7tmF9T_9bun_alloc5basicNtB2_17MimallocAllocator13aligned_alloc.exit, !dbg !597

_RNvMNtCs9SN9c7tmF9T_9bun_alloc5basicNtB2_17MimallocAllocator13aligned_alloc.exit: ; preds = %bb2.i, %bb1.i
  %ptr.sroa.0.0.i = phi ptr [ %3, %bb1.i ], [ %1, %bb2.i ], !dbg !598
  ret ptr %ptr.sroa.0.0.i, !dbg !599
}

; <bun_alloc::basic::MimallocAllocator>::remap_with_default_allocator
; Function Attrs: nounwind
define noundef ptr @_RNvMNtCs9SN9c7tmF9T_9bun_alloc5basicNtB2_17MimallocAllocator28remap_with_default_allocator(ptr readnone captures(none) %_1, ptr noalias noundef nonnull %buf.0, i64 range(i64 0, -9223372036854775808) %buf.1, i8 noundef %alignment, i64 noundef %new_len, i64 %_5) unnamed_addr #1 !dbg !600 {
start:
  %0 = and i8 %alignment, 63, !dbg !601
  %1 = zext nneg i8 %0 to i64, !dbg !601
  %_8 = shl nuw i64 1, %1, !dbg !601
  %_6 = tail call noundef ptr @mi_realloc_aligned(ptr noundef nonnull %buf.0, i64 noundef %new_len, i64 noundef %_8) #33, !dbg !604
  ret ptr %_6, !dbg !607
}

; <bun_alloc::basic::MimallocAllocator>::resize_with_default_allocator
; Function Attrs: nounwind
define noundef zeroext i1 @_RNvMNtCs9SN9c7tmF9T_9bun_alloc5basicNtB2_17MimallocAllocator29resize_with_default_allocator(ptr readnone captures(none) %_1, ptr noalias noundef nonnull %buf.0, i64 range(i64 0, -9223372036854775808) %buf.1, i8 %_3, i64 noundef %new_len, i64 %_5) unnamed_addr #1 !dbg !608 {
start:
  %_7 = tail call noundef ptr @mi_expand(ptr noundef nonnull %buf.0, i64 noundef %new_len) #33, !dbg !609
  %_6 = icmp ne ptr %_7, null, !dbg !610
  ret i1 %_6, !dbg !620
}

; <bun_alloc::ast_alloc::AstAllocState>::new_boxed
; Function Attrs: nounwind
define noalias noundef nonnull align 8 ptr @_RNvMNtCs9SN9c7tmF9T_9bun_alloc9ast_allocNtB2_13AstAllocState9new_boxed() unnamed_addr #1 !dbg !621 {
start:
; call __rustc::__rust_no_alloc_shim_is_unstable_v2
  tail call void @_RNvCs3TqXShXgh4d_7___rustc35___rust_no_alloc_shim_is_unstable_v2() #33, !dbg !625
; call __rustc::__rust_alloc
  %0 = tail call noundef align 8 dereferenceable_or_null(16416) ptr @_RNvCs3TqXShXgh4d_7___rustc12___rust_alloc(i64 noundef range(i64 0, -9223372036854775808) 16416, i64 noundef 8) #33, !dbg !633
  %1 = icmp eq ptr %0, null, !dbg !634
  br i1 %1, label %bb2.i, label %_RNvNtCskhhhlZ4wWGP_5alloc5boxed14box_new_uninit.exit, !dbg !635, !prof !53

bb2.i:                                            ; preds = %start
; call alloc::alloc::handle_alloc_error
  tail call void @_RNvNtCskhhhlZ4wWGP_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 16416) #34, !dbg !636
  unreachable, !dbg !636

_RNvNtCskhhhlZ4wWGP_5alloc5boxed14box_new_uninit.exit: ; preds = %start
  %2 = getelementptr inbounds nuw i8, ptr %0, i64 16384, !dbg !637
  %3 = getelementptr inbounds nuw i8, ptr %0, i64 16408, !dbg !644
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %2, i8 0, i64 16, i1 false), !dbg !650
  store i8 2, ptr %3, align 8, !dbg !644
  ret ptr %0, !dbg !656
}

; <bun_alloc::heap_breakdown::Zone>::is_instance
; Function Attrs: nounwind
define noundef zeroext i1 @_RNvMs0_NtCs9SN9c7tmF9T_9bun_alloc14heap_breakdownNtB5_4Zone11is_instance(ptr noundef nonnull %allocator_.0, ptr noalias noundef readonly align 8 captures(none) dereferenceable(32) %allocator_.1) unnamed_addr #1 !dbg !657 {
start:
  %_2 = alloca [16 x i8], align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %_2), !dbg !661
  %0 = getelementptr inbounds nuw i8, ptr %allocator_.1, i64 24, !dbg !661
  %1 = load ptr, ptr %0, align 8, !dbg !661, !invariant.load !14, !nonnull !14
  call void %1(ptr noalias noundef nonnull sret([16 x i8]) align 8 captures(address) dereferenceable(16) %_2, ptr noundef nonnull %allocator_.0) #37, !dbg !661
  %_3 = load i128, ptr %_2, align 8, !dbg !665, !noundef !14
  %_0 = icmp eq i128 %_3, -127890169279801676490672652203044285816, !dbg !665
  call void @llvm.lifetime.end.p0(ptr nonnull %_2), !dbg !676
  ret i1 %_0, !dbg !677
}

; <bun_alloc::heap_breakdown::Zone>::init
; Function Attrs: nounwind
define noundef nonnull ptr @_RNvMs0_NtCs9SN9c7tmF9T_9bun_alloc14heap_breakdownNtB5_4Zone4init(ptr noundef %name) unnamed_addr #1 !dbg !678 {
start:
  %zone = tail call noundef ptr @malloc_create_zone(i64 noundef 0, i32 noundef 0) #33, !dbg !679
  tail call void @malloc_set_zone_name(ptr noundef %zone, ptr noundef %name) #33, !dbg !680
  ret ptr %zone, !dbg !682
}

; <bun_alloc::heap_breakdown::Zone>::raw_alloc
; Function Attrs: nounwind
define { i64, ptr } @_RNvMs0_NtCs9SN9c7tmF9T_9bun_alloc14heap_breakdownNtB5_4Zone9raw_alloc(ptr noundef nonnull %zone, i64 noundef %len, i64 noundef %alignment, i64 noundef %_ret_addr) unnamed_addr #1 personality ptr @rust_eh_personality !dbg !683 {
start:
  %..i.i = tail call noundef i64 @llvm.umax.i64(i64 %alignment, i64 8), !dbg !684
  %ptr.i = tail call noundef ptr @malloc_zone_memalign(ptr noundef nonnull %zone, i64 noundef %..i.i, i64 noundef %len) #33, !dbg !692
  %0 = icmp ne ptr %ptr.i, null, !dbg !694
  %..i = zext i1 %0 to i64, !dbg !696
  %1 = insertvalue { i64, ptr } poison, i64 %..i, 0, !dbg !697
  %2 = insertvalue { i64, ptr } %1, ptr %ptr.i, 1, !dbg !697
  ret { i64, ptr } %2, !dbg !698
}

; <bun_alloc::max_heap_allocator::MaxHeapAllocator>::is_instance
; Function Attrs: nounwind
define noundef zeroext i1 @_RNvMs0_NtCs9SN9c7tmF9T_9bun_alloc18max_heap_allocatorNtB5_16MaxHeapAllocator11is_instance(ptr noundef nonnull %alloc.0, ptr noalias noundef readonly align 8 captures(none) dereferenceable(32) %alloc.1) unnamed_addr #1 !dbg !699 {
start:
  %_2 = alloca [16 x i8], align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %_2), !dbg !703
  %0 = getelementptr inbounds nuw i8, ptr %alloc.1, i64 24, !dbg !703
  %1 = load ptr, ptr %0, align 8, !dbg !703, !invariant.load !14, !nonnull !14
  call void %1(ptr noalias noundef nonnull sret([16 x i8]) align 8 captures(address) dereferenceable(16) %_2, ptr noundef nonnull %alloc.0) #37, !dbg !703
  %_3 = load i128, ptr %_2, align 8, !dbg !706, !noundef !14
  %_0 = icmp eq i128 %_3, 14378489558447215563515722450413337646, !dbg !706
  call void @llvm.lifetime.end.p0(ptr nonnull %_2), !dbg !713
  ret i1 %_0, !dbg !714
}

; <bun_alloc::max_heap_allocator::MaxHeapAllocator>::alloc
; Function Attrs: nounwind
define { i64, ptr } @_RNvMs0_NtCs9SN9c7tmF9T_9bun_alloc18max_heap_allocatorNtB5_16MaxHeapAllocator5alloc(ptr noalias noundef align 8 captures(none) dereferenceable(24) initializes((16, 24)) %self, i64 noundef %len, i8 noundef %alignment, i64 noundef %_ret_addr) unnamed_addr #1 !dbg !715 {
start:
  %0 = getelementptr inbounds nuw i8, ptr %self, i64 16, !dbg !716
  store i64 0, ptr %0, align 8, !dbg !716
  %1 = getelementptr inbounds nuw i8, ptr %self, i64 8, !dbg !717
  %_6 = load i64, ptr %1, align 8, !dbg !717, !noundef !14
  %_5 = icmp ult i64 %_6, %len, !dbg !717
  br i1 %_5, label %bb1, label %start.bb7_crit_edge, !dbg !717

start.bb7_crit_edge:                              ; preds = %start
  %.pre = load ptr, ptr %self, align 8, !dbg !718
  br label %bb7, !dbg !717

bb1:                                              ; preds = %start
  %_25 = icmp ult i64 %len, 9223372036854775801
  br i1 %_25, label %bb10, label %bb9, !dbg !719

bb7:                                              ; preds = %start.bb7_crit_edge, %bb18
  %2 = phi ptr [ %.pre, %start.bb7_crit_edge ], [ %new_ptr.sroa.0.0, %bb18 ], !dbg !718
  store i64 %len, ptr %0, align 8, !dbg !733
  %.not3 = icmp ne ptr %2, null, !dbg !734
  %.4 = zext i1 %.not3 to i64, !dbg !737
  br label %bb9, !dbg !737

bb10:                                             ; preds = %bb1
  %3 = load ptr, ptr %self, align 8, !dbg !738, !noundef !14
  %.not = icmp eq ptr %3, null, !dbg !738
  br i1 %.not, label %bb3, label %bb4, !dbg !741

bb4:                                              ; preds = %bb10
; call __rustc::__rust_realloc
  %4 = tail call noundef align 8 ptr @_RNvCs3TqXShXgh4d_7___rustc14___rust_realloc(ptr noundef nonnull %3, i64 noundef %_6, i64 noundef 8, i64 noundef %len) #33, !dbg !742
  br label %bb5, !dbg !748

bb3:                                              ; preds = %bb10
; call __rustc::__rust_no_alloc_shim_is_unstable_v2
  tail call void @_RNvCs3TqXShXgh4d_7___rustc35___rust_no_alloc_shim_is_unstable_v2() #33, !dbg !749
; call __rustc::__rust_alloc
  %5 = tail call noundef align 8 ptr @_RNvCs3TqXShXgh4d_7___rustc12___rust_alloc(i64 noundef %len, i64 noundef 8) #33, !dbg !752
  br label %bb5, !dbg !752

bb5:                                              ; preds = %bb3, %bb4
  %new_ptr.sroa.0.0 = phi ptr [ %4, %bb4 ], [ %5, %bb3 ], !dbg !753
  %6 = icmp eq ptr %new_ptr.sroa.0.0, null, !dbg !754
  br i1 %6, label %bb9, label %bb18, !dbg !754

bb18:                                             ; preds = %bb5
  store ptr %new_ptr.sroa.0.0, ptr %self, align 8, !dbg !758
  store i64 %len, ptr %1, align 8, !dbg !760
  br label %bb7, !dbg !761

bb9:                                              ; preds = %bb5, %bb1, %bb7
  %_0.sroa.5.0 = phi ptr [ undef, %bb1 ], [ undef, %bb5 ], [ %2, %bb7 ], !dbg !762
  %_0.sroa.0.0 = phi i64 [ 0, %bb1 ], [ 0, %bb5 ], [ %.4, %bb7 ], !dbg !762
  %7 = insertvalue { i64, ptr } poison, i64 %_0.sroa.0.0, 0, !dbg !763
  %8 = insertvalue { i64, ptr } %7, ptr %_0.sroa.5.0, 1, !dbg !763
  ret { i64, ptr } %8, !dbg !763
}

; <bun_alloc::max_heap_allocator::MaxHeapAllocator>::resize
; Function Attrs: cold noreturn nounwind
define noundef zeroext i1 @_RNvMs0_NtCs9SN9c7tmF9T_9bun_alloc18max_heap_allocatorNtB5_16MaxHeapAllocator6resize(ptr noalias noundef readnone align 8 captures(none) dereferenceable(24) %self, ptr noalias noundef nonnull readnone captures(none) %_buf.0, i64 noundef range(i64 0, -9223372036854775808) %_buf.1, i8 noundef %_alignment, i64 noundef %_new_len, i64 noundef %_ret_addr) unnamed_addr #3 !dbg !764 {
start:
; call core::panicking::panic_fmt
  tail call void @_RNvNtCsgXhsEb1m4tm_4core9panicking9panic_fmt(ptr noundef nonnull @alloc_7395b7fd5052a2200dfc13209d237c6b, ptr noundef nonnull inttoptr (i64 31 to ptr), ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_563e88b9be90d850f438b69673a057ca) #35, !dbg !765
  unreachable, !dbg !765
}

; <bun_alloc::mimalloc_arena::MimallocArena>::allocated_bytes
; Function Attrs: nounwind
define noundef i64 @_RNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB5_13MimallocArena15allocated_bytes(ptr noalias noundef readonly align 8 captures(none) dereferenceable(16) %self) unnamed_addr #1 !dbg !766 {
start:
  %total = alloca [8 x i8], align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %total), !dbg !767
  store i64 0, ptr %total, align 8, !dbg !768
  %_9 = load ptr, ptr %self, align 8, !dbg !769, !nonnull !14, !noundef !14
  %_3 = call noundef zeroext i1 @mi_heap_visit_blocks(ptr noundef nonnull %_9, i1 noundef zeroext false, ptr noundef nonnull @_RNvNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB7_13MimallocArena15allocated_bytes5visit, ptr noundef nonnull %total) #33, !dbg !773
  %_0 = load i64, ptr %total, align 8, !dbg !774, !noundef !14
  call void @llvm.lifetime.end.p0(ptr nonnull %total), !dbg !775
  ret i64 %_0, !dbg !776
}

; <bun_alloc::mimalloc_arena::MimallocArena>::reset
; Function Attrs: cold noinline nounwind
define void @_RNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB5_13MimallocArena5reset(ptr noalias noundef align 8 captures(none) dereferenceable(16) %self) unnamed_addr #4 !dbg !777 {
start:
  %_7 = load ptr, ptr %self, align 8, !dbg !778, !nonnull !14, !noundef !14
  tail call void @mi_heap_destroy(ptr noundef nonnull %_7) #33, !dbg !781
  %heap = tail call noundef ptr @mi_heap_new() #33, !dbg !782
  %0 = icmp eq ptr %heap, null, !dbg !783
  br i1 %0, label %bb3, label %bb4, !dbg !783, !prof !53

bb3:                                              ; preds = %start
; call bun_alloc::out_of_memory
  tail call void @_RNvCs9SN9c7tmF9T_9bun_alloc13out_of_memory() #35, !dbg !787
  unreachable, !dbg !787

bb4:                                              ; preds = %start
  store ptr %heap, ptr %self, align 8, !dbg !794
  ret void, !dbg !795
}

; <alloc::raw_vec::RawVec<(alloc::vec::Vec<u8>, alloc::vec::Vec<u8>, &bun_alloc::heap_breakdown::Zone)>>::grow_one
; Function Attrs: cold noinline nounwind
define void @_RNvMs3_NtCskhhhlZ4wWGP_5alloc7raw_vecINtB5_6RawVecTINtNtB7_3vec3VechEBN_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE8grow_oneB1d_(ptr noalias noundef align 8 captures(none) dereferenceable(16) %self) unnamed_addr #4 personality ptr @rust_eh_personality !dbg !796 {
start:
  %self3.i = alloca [24 x i8], align 8
  %self1 = load i64, ptr %self, align 8, !dbg !800, !range !805, !noundef !14
  tail call void @llvm.experimental.noalias.scope.decl(metadata !806), !dbg !809
  %v16.i = shl nuw i64 %self1, 1, !dbg !810
  %0 = tail call i64 @llvm.umax.i64(i64 %v16.i, i64 4), !dbg !814
  call void @llvm.lifetime.start.p0(ptr nonnull %self3.i), !dbg !819, !noalias !806
; call <alloc::raw_vec::RawVecInner>::finish_grow
  call fastcc void @_RNvMs4_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner11finish_growCs9SN9c7tmF9T_9bun_alloc(ptr noalias noundef sret([24 x i8]) align 8 captures(none) dereferenceable(24) %self3.i, ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(16) %self, i64 noundef %0, i64 noundef 8, i64 noundef 56) #33, !dbg !821
  %_37.i = load i64, ptr %self3.i, align 8, !dbg !822, !range !825, !noalias !806, !noundef !14
  %1 = trunc nuw i64 %_37.i to i1, !dbg !826
  %2 = getelementptr inbounds nuw i8, ptr %self3.i, i64 8, !dbg !827
  br i1 %1, label %bb18.i, label %bb3, !dbg !826

bb18.i:                                           ; preds = %start
  %e.0.i = load i64, ptr %2, align 8, !dbg !828, !range !829, !noalias !806, !noundef !14
  %3 = getelementptr inbounds nuw i8, ptr %self3.i, i64 16, !dbg !828
  %e.1.i = load i64, ptr %3, align 8, !dbg !828, !noalias !806
  call void @llvm.lifetime.end.p0(ptr nonnull %self3.i), !dbg !830, !noalias !806
; call alloc::raw_vec::handle_error
  tail call void @_RNvNtCskhhhlZ4wWGP_5alloc7raw_vec12handle_error(i64 noundef %e.0.i, i64 %e.1.i) #34, !dbg !831
  unreachable, !dbg !831

bb3:                                              ; preds = %start
  %v.0.i = load ptr, ptr %2, align 8, !dbg !832, !noalias !806, !nonnull !14, !noundef !14
  call void @llvm.lifetime.end.p0(ptr nonnull %self3.i), !dbg !830, !noalias !806
  %4 = getelementptr inbounds nuw i8, ptr %self, i64 8, !dbg !833
  store ptr %v.0.i, ptr %4, align 8, !dbg !833, !alias.scope !806
  %5 = icmp sgt i64 %0, -1, !dbg !837
  tail call void @llvm.assume(i1 %5), !dbg !837
  store i64 %0, ptr %self, align 8, !dbg !843, !alias.scope !806
  ret void, !dbg !844
}

; <alloc::raw_vec::RawVecInner>::finish_grow
; Function Attrs: cold nounwind
define internal fastcc void @_RNvMs4_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner11finish_growCs9SN9c7tmF9T_9bun_alloc(ptr dead_on_unwind noalias noundef nonnull writable writeonly sret([24 x i8]) align 8 captures(none) dereferenceable(24) initializes((0, 8)) %_0, ptr noalias noundef nonnull readonly align 8 captures(none) dereferenceable(16) %self, i64 noundef %cap, i64 noundef range(i64 1, 9) %elem_layout.0, i64 noundef range(i64 1, 57) %elem_layout.1) unnamed_addr #0 !dbg !845 {
start:
  %0 = tail call { i64, i1 } @llvm.umul.with.overflow.i64(i64 %elem_layout.1, i64 %cap), !dbg !846
  %_34.0 = extractvalue { i64, i1 } %0, 0, !dbg !846
  %_34.1 = extractvalue { i64, i1 } %0, 1, !dbg !846
  %_41 = sub nuw i64 -9223372036854775808, %elem_layout.0
  %_39.not = icmp ugt i64 %_34.0, %_41
  %or.cond = select i1 %_34.1, i1 true, i1 %_39.not, !dbg !856, !prof !861
  br i1 %or.cond, label %bb11, label %bb15, !dbg !856, !prof !861

bb15:                                             ; preds = %start
  %self1.i = load i64, ptr %self, align 8, !dbg !862, !range !805, !alias.scope !867, !noalias !870, !noundef !14
  %1 = icmp eq i64 %self1.i, 0, !dbg !862
  br i1 %1, label %bb5, label %bb3, !dbg !862

bb3:                                              ; preds = %bb15
  %alloc_size.i = mul nuw i64 %self1.i, %elem_layout.1, !dbg !872
  %2 = getelementptr inbounds nuw i8, ptr %self, i64 8, !dbg !875
  %self3.i = load ptr, ptr %2, align 8, !dbg !875, !alias.scope !867, !noalias !870, !nonnull !14, !noundef !14
  %cond.i.i = icmp uge i64 %_34.0, %alloc_size.i, !dbg !878
  tail call void @llvm.assume(i1 %cond.i.i), !dbg !887
; call __rustc::__rust_realloc
  %raw_ptr.i.i = tail call noundef ptr @_RNvCs3TqXShXgh4d_7___rustc14___rust_realloc(ptr noundef nonnull %self3.i, i64 noundef %alloc_size.i, i64 noundef range(i64 1, 9) %elem_layout.0, i64 noundef range(i64 0, -9223372036854775808) %_34.0) #33, !dbg !890
  br label %bb7, !dbg !893

bb5:                                              ; preds = %bb15
  %3 = icmp eq i64 %_34.0, 0, !dbg !894
  br i1 %3, label %bb7.thread, label %bb4.i.i10, !dbg !894

bb7.thread:                                       ; preds = %bb5
  %data2.i.i = inttoptr i64 %elem_layout.0 to ptr, !dbg !900
  br label %bb9, !dbg !905

bb4.i.i10:                                        ; preds = %bb5
; call __rustc::__rust_no_alloc_shim_is_unstable_v2
  tail call void @_RNvCs3TqXShXgh4d_7___rustc35___rust_no_alloc_shim_is_unstable_v2() #33, !dbg !907
; call __rustc::__rust_alloc
  %4 = tail call noundef ptr @_RNvCs3TqXShXgh4d_7___rustc12___rust_alloc(i64 noundef range(i64 0, -9223372036854775808) %_34.0, i64 noundef range(i64 1, 9) %elem_layout.0) #33, !dbg !909
  br label %bb7, !dbg !910

bb7:                                              ; preds = %bb4.i.i10, %bb3
  %raw_ptr.i.i.pn = phi ptr [ %raw_ptr.i.i, %bb3 ], [ %4, %bb4.i.i10 ]
  %5 = icmp eq ptr %raw_ptr.i.i.pn, null, !dbg !914
  br i1 %5, label %bb8, label %bb9, !dbg !905

bb8:                                              ; preds = %bb7
  %6 = getelementptr inbounds nuw i8, ptr %_0, i64 8, !dbg !915
  store i64 %elem_layout.0, ptr %6, align 8, !dbg !915
  br label %bb11, !dbg !916

bb9:                                              ; preds = %bb7.thread, %bb7
  %raw_ptr.i.i.pn20 = phi ptr [ %data2.i.i, %bb7.thread ], [ %raw_ptr.i.i.pn, %bb7 ]
  %7 = getelementptr inbounds nuw i8, ptr %_0, i64 8, !dbg !917
  store ptr %raw_ptr.i.i.pn20, ptr %7, align 8, !dbg !917
  br label %bb11, !dbg !919

bb11:                                             ; preds = %start, %bb9, %bb8
  %.sink21 = phi i64 [ 16, %bb9 ], [ 16, %bb8 ], [ 8, %start ]
  %_34.0.sink = phi i64 [ %_34.0, %bb9 ], [ %_34.0, %bb8 ], [ 0, %start ]
  %storemerge9 = phi i64 [ 0, %bb9 ], [ 1, %bb8 ], [ 1, %start ], !dbg !920
  %8 = getelementptr inbounds nuw i8, ptr %_0, i64 %.sink21, !dbg !920
  store i64 %_34.0.sink, ptr %8, align 8, !dbg !920
  store i64 %storemerge9, ptr %_0, align 8, !dbg !920
  ret void, !dbg !921
}

; <bun_alloc::nullable_allocator::NullableAllocator>::free
; Function Attrs: nounwind
define void @_RNvMs_NtCs9SN9c7tmF9T_9bun_alloc18nullable_allocatorNtB4_17NullableAllocator4free(ptr noalias noundef readonly align 8 captures(none) dereferenceable(16) %self, ptr noalias noundef nonnull readonly captures(address, read_provenance) %bytes.0, i64 noundef range(i64 0, -9223372036854775808) %bytes.1) unnamed_addr #1 !dbg !922 {
start:
  %_11 = load ptr, ptr %self, align 8, !dbg !926, !noundef !14
  %0 = getelementptr inbounds nuw i8, ptr %self, i64 8, !dbg !930
  %1 = load ptr, ptr %0, align 8, !dbg !930, !align !164, !noundef !14
  %.not = icmp eq ptr %1, null, !dbg !931
  br i1 %.not, label %bb3, label %bb6, !dbg !933

bb6:                                              ; preds = %start
  %_4 = icmp eq ptr %1, @_RNvNtCs9SN9c7tmF9T_9bun_alloc19StringImplAllocator6VTABLE, !dbg !934
  br i1 %_4, label %bb1, label %bb2, !dbg !939

bb3:                                              ; preds = %bb3.i, %bb1, %bb2, %bb10, %start
  ret void, !dbg !940

bb2:                                              ; preds = %bb6
  %2 = icmp eq i64 %bytes.1, 0, !dbg !941
  br i1 %2, label %bb3, label %bb10, !dbg !941

bb1:                                              ; preds = %bb6
  %3 = atomicrmw sub ptr %_11, i32 2 monotonic, align 4, !dbg !944
  %4 = icmp eq i32 %3, 2, !dbg !959
  br i1 %4, label %bb3.i, label %bb3, !dbg !959

bb3.i:                                            ; preds = %bb1
  tail call void @Bun__WTFStringImpl__destroy(ptr noundef %_11) #33, !dbg !961
  br label %bb3, !dbg !962

bb10:                                             ; preds = %bb2
  %5 = getelementptr inbounds nuw i8, ptr %1, i64 24, !dbg !963
  %_35 = load ptr, ptr %5, align 8, !dbg !963, !nonnull !14, !noundef !14
  tail call void %_35(ptr noundef %_11, ptr noalias noundef nonnull %bytes.0, i64 noundef %bytes.1, i8 noundef 0, i64 noundef 0) #33, !dbg !963
  br label %bb3, !dbg !966
}

; <bun_alloc::basic::ZAllocator>::alloc_with_z_allocator
; Function Attrs: nounwind
define noundef ptr @_RNvMs_NtCs9SN9c7tmF9T_9bun_alloc5basicNtB4_10ZAllocator22alloc_with_z_allocator(ptr readnone captures(none) %_1, i64 noundef %len, i8 noundef %alignment, i64 %_4) unnamed_addr #1 !dbg !967 {
start:
  %0 = and i8 %alignment, 63, !dbg !969
  %_5.i = icmp samesign ugt i8 %0, 4, !dbg !974
  br i1 %_5.i, label %bb1.i, label %bb2.i, !dbg !981

bb2.i:                                            ; preds = %start
  %1 = tail call noundef ptr @mi_zalloc(i64 noundef %len) #33, !dbg !982
  br label %_RNvMs_NtCs9SN9c7tmF9T_9bun_alloc5basicNtB4_10ZAllocator13aligned_alloc.exit, !dbg !982

bb1.i:                                            ; preds = %start
  %2 = zext nneg i8 %0 to i64, !dbg !969
  %_4.i = shl nuw i64 1, %2, !dbg !969
  %3 = tail call noundef ptr @mi_zalloc_aligned(i64 noundef %len, i64 noundef %_4.i) #33, !dbg !983
  br label %_RNvMs_NtCs9SN9c7tmF9T_9bun_alloc5basicNtB4_10ZAllocator13aligned_alloc.exit, !dbg !983

_RNvMs_NtCs9SN9c7tmF9T_9bun_alloc5basicNtB4_10ZAllocator13aligned_alloc.exit: ; preds = %bb2.i, %bb1.i
  %ptr.sroa.0.0.i = phi ptr [ %3, %bb1.i ], [ %1, %bb2.i ], !dbg !984
  ret ptr %ptr.sroa.0.0.i, !dbg !985
}

; <bun_alloc::basic::ZAllocator>::resize_with_z_allocator
; Function Attrs: nounwind
define noundef zeroext i1 @_RNvMs_NtCs9SN9c7tmF9T_9bun_alloc5basicNtB4_10ZAllocator23resize_with_z_allocator(ptr readnone captures(none) %_1, ptr noalias noundef nonnull %buf.0, i64 noundef range(i64 0, -9223372036854775808) %buf.1, i8 %_3, i64 noundef %new_len, i64 %_5) unnamed_addr #1 !dbg !986 {
start:
  %_6.not = icmp ugt i64 %new_len, %buf.1, !dbg !987
  br i1 %_6.not, label %bb2, label %bb6, !dbg !987

bb2:                                              ; preds = %start
  %0 = tail call noundef i64 @mi_usable_size(ptr noundef nonnull %buf.0) #33, !dbg !988
  %_10.not = icmp ule i64 %new_len, %0, !dbg !993
  br label %bb6, !dbg !995

bb6:                                              ; preds = %start, %bb2
  %_0.sroa.0.0.off0 = phi i1 [ %_10.not, %bb2 ], [ true, %start ]
  ret i1 %_0.sroa.0.0.off0, !dbg !996
}

; <bun_alloc::fallback::z::Z>::free
; Function Attrs: mustprogress nounwind willreturn memory(argmem: readwrite, inaccessiblemem: readwrite)
define void @_RNvMs_NtNtCs9SN9c7tmF9T_9bun_alloc8fallback1zNtB4_1Z4free(ptr noalias noundef nonnull captures(none) %buf.0, i64 noundef range(i64 0, -9223372036854775808) %buf.1, i8 noundef %alignment, i64 noundef %return_address) unnamed_addr #5 !dbg !997 {
start:
  tail call void @free(ptr noundef nonnull %buf.0) #33, !dbg !1002
  ret void, !dbg !1008
}

; <bun_alloc::fallback::z::Z>::alloc
; Function Attrs: mustprogress nofree nounwind willreturn memory(write, inaccessiblemem: readwrite)
define { i64, ptr } @_RNvMs_NtNtCs9SN9c7tmF9T_9bun_alloc8fallback1zNtB4_1Z5alloc(ptr noalias noundef nonnull readonly captures(none) %self, i64 noundef %len, i8 noundef %alignment, i64 noundef %return_address) unnamed_addr #6 !dbg !1009 {
start:
  %0 = and i8 %alignment, 63, !dbg !1010
  %_12 = icmp samesign ult i8 %0, 4, !dbg !1015
  br i1 %_12, label %bb2, label %bb3, !dbg !1015

bb3:                                              ; preds = %start
  %1 = zext nneg i8 %0 to i64, !dbg !1010
  %_10 = shl nuw i64 1, %1, !dbg !1010
  %2 = tail call noundef ptr @aligned_alloc(i64 noundef %_10, i64 noundef %len) #33, !dbg !1017
  br label %bb4, !dbg !1017

bb2:                                              ; preds = %start
  %3 = tail call noundef ptr @malloc(i64 noundef %len) #33, !dbg !1018
  br label %bb4, !dbg !1018

bb4:                                              ; preds = %bb2, %bb3
  %_11.sroa.0.0 = phi ptr [ %3, %bb2 ], [ %2, %bb3 ], !dbg !1019
  %4 = icmp eq ptr %_11.sroa.0.0, null, !dbg !1020
  br i1 %4, label %bb1, label %bb6, !dbg !1020

bb6:                                              ; preds = %bb4
  tail call void @llvm.memset.p0.i64(ptr nonnull align 1 %_11.sroa.0.0, i8 0, i64 %len, i1 false), !dbg !1022
  br label %bb1, !dbg !1026

bb1:                                              ; preds = %bb4, %bb6
  %_0.sroa.0.0 = phi i64 [ 1, %bb6 ], [ 0, %bb4 ], !dbg !1027
  %5 = insertvalue { i64, ptr } poison, i64 %_0.sroa.0.0, 0, !dbg !1026
  %6 = insertvalue { i64, ptr } %5, ptr %_11.sroa.0.0, 1, !dbg !1026
  ret { i64, ptr } %6, !dbg !1026
}

; <bun_alloc::fallback::z::Z>::resize
; Function Attrs: nounwind
define noundef zeroext i1 @_RNvMs_NtNtCs9SN9c7tmF9T_9bun_alloc8fallback1zNtB4_1Z6resize(ptr noalias noundef nonnull readonly captures(none) %self, ptr noalias noundef nonnull %buf.0, i64 noundef range(i64 0, -9223372036854775808) %buf.1, i8 noundef %alignment, i64 noundef %new_len, i64 noundef %return_address) unnamed_addr #1 !dbg !1028 {
start:
  %_12.not = icmp ugt i64 %new_len, %buf.1, !dbg !1029
  br i1 %_12.not, label %bb7, label %bb5, !dbg !1029

bb7:                                              ; preds = %start
  %_14 = tail call noundef i64 @malloc_size(ptr noundef nonnull %buf.0) #33, !dbg !1032
  %_6.not = icmp ugt i64 %new_len, %_14, !dbg !1033
  br i1 %_6.not, label %bb5, label %bb3, !dbg !1035

bb5:                                              ; preds = %start, %bb3, %bb7
  %_0.sroa.0.0.off0 = phi i1 [ false, %bb7 ], [ true, %bb3 ], [ true, %start ]
  ret i1 %_0.sroa.0.0.off0, !dbg !1036

bb3:                                              ; preds = %bb7
  %_9 = getelementptr inbounds nuw i8, ptr %buf.0, i64 %buf.1, !dbg !1037
  %_11 = sub nuw i64 %new_len, %buf.1, !dbg !1041
  tail call void @llvm.memset.p0.i64(ptr nonnull align 1 %_9, i8 0, i64 %_11, i1 false), !dbg !1042
  br label %bb5, !dbg !1045
}

; <bun_alloc::String>::eql_comptime
; Function Attrs: nofree norecurse nounwind memory(read, inaccessiblemem: write)
define noundef zeroext i1 @_RNvMsd_Cs9SN9c7tmF9T_9bun_allocNtB5_6String12eql_comptime(ptr noalias noundef readonly align 8 captures(none) dereferenceable(24) %self, ptr noalias noundef nonnull readonly captures(none) %other.0, i64 noundef range(i64 0, -9223372036854775808) %other.1) unnamed_addr #7 personality ptr @rust_eh_personality !dbg !1046 {
start:
  %_17 = load i8, ptr %self, align 8, !dbg !1047, !range !1050, !noundef !14
  switch i8 %_17, label %bb18 [
    i8 1, label %bb10
    i8 2, label %bb11
    i8 3, label %bb11
  ], !dbg !1051

bb10:                                             ; preds = %start
  %0 = getelementptr inbounds nuw i8, ptr %self, i64 8, !dbg !1052
  %_19 = load ptr, ptr %0, align 8, !dbg !1052, !noundef !14
  %_5.i = getelementptr inbounds nuw i8, ptr %_19, i64 16, !dbg !1055
  %_3.i = load i32, ptr %_5.i, align 4, !dbg !1064, !noundef !14
  %_2.i = and i32 %_3.i, 4, !dbg !1065
  %1 = icmp eq i32 %_2.i, 0, !dbg !1066
  %2 = getelementptr inbounds nuw i8, ptr %_19, i64 8, !dbg !1067
  %_12.i = load ptr, ptr %2, align 8, !dbg !1067, !noundef !14
  %_19.i = ptrtoint ptr %_12.i to i64, !dbg !1066
  %_18.i = or i64 %_19.i, -9223372036854775808, !dbg !1066
  %3 = inttoptr i64 %_18.i to ptr, !dbg !1066
  %_0.sroa.0.0.i = select i1 %1, ptr %3, ptr %_12.i, !dbg !1066
  %_0.sroa.5.0.in.in.i = getelementptr inbounds nuw i8, ptr %_19, i64 4, !dbg !1067
  %_0.sroa.5.0.in.i = load i32, ptr %_0.sroa.5.0.in.in.i, align 4, !dbg !1067, !noundef !14
  %_0.sroa.5.0.i = zext i32 %_0.sroa.5.0.in.i to i64, !dbg !1067
  br label %bb8, !dbg !1068

bb11:                                             ; preds = %start, %start
  %4 = getelementptr inbounds nuw i8, ptr %self, i64 8, !dbg !1069
  %5 = load ptr, ptr %4, align 8, !dbg !1069, !noundef !14
  %6 = getelementptr inbounds nuw i8, ptr %self, i64 16, !dbg !1069
  %7 = load i64, ptr %6, align 8, !dbg !1069, !noundef !14
  br label %bb8, !dbg !1069

bb8:                                              ; preds = %bb11, %bb10
  %zs.sroa.10.0 = phi i64 [ %_0.sroa.5.0.i, %bb10 ], [ %7, %bb11 ], !dbg !1070
  %zs.sroa.0.0 = phi ptr [ %_0.sroa.0.0.i, %bb10 ], [ %5, %bb11 ], !dbg !1070
  %8 = ptrtoint ptr %zs.sroa.0.0 to i64, !dbg !1071
  %.not = icmp sgt ptr %zs.sroa.0.0, inttoptr (i64 -1 to ptr), !dbg !1071
  %9 = icmp eq i64 %zs.sroa.10.0, 0, !dbg !1076
  br i1 %.not, label %bb5, label %bb1, !dbg !1077

bb5:                                              ; preds = %bb8
  br i1 %9, label %bb18, label %bb20, !dbg !1078

bb1:                                              ; preds = %bb8
  %_25 = and i64 %8, 9007199254740991, !dbg !1081
  %_24 = inttoptr i64 %_25 to ptr, !dbg !1081
  %u16s.sroa.0.0 = select i1 %9, ptr inttoptr (i64 2 to ptr), ptr %_24, !dbg !1081
  %_6.not = icmp eq i64 %zs.sroa.10.0, %other.1, !dbg !1084
  br i1 %_6.not, label %bb3, label %bb7, !dbg !1084

bb20:                                             ; preds = %bb5
  %_52 = and i64 %8, 9007199254740991, !dbg !1086
  %_49 = inttoptr i64 %_52 to ptr, !dbg !1086
  %..i = tail call noundef i64 @llvm.umin.i64(i64 %zs.sroa.10.0, i64 4294967295), !dbg !1089
  br label %bb18, !dbg !1094

bb18:                                             ; preds = %bb5, %start, %bb20
  %_16.sroa.4.0 = phi i64 [ %..i, %bb20 ], [ 0, %start ], [ 0, %bb5 ], !dbg !1095
  %_16.sroa.0.0 = phi ptr [ %_49, %bb20 ], [ inttoptr (i64 1 to ptr), %start ], [ inttoptr (i64 1 to ptr), %bb5 ], !dbg !1095
  %_56 = icmp eq i64 %_16.sroa.4.0, %other.1, !dbg !1096
  br i1 %_56, label %bb22, label %bb7, !dbg !1096

bb22:                                             ; preds = %bb18
  %10 = tail call i32 @memcmp(ptr %_16.sroa.0.0, ptr nonnull %other.0, i64 %other.1), !dbg !1107
  %11 = icmp eq i32 %10, 0, !dbg !1107
  br label %bb7, !dbg !1112

bb3:                                              ; preds = %bb1
  %12 = icmp ne ptr %u16s.sroa.0.0, null, !dbg !1113
  tail call void @llvm.assume(i1 %12), !dbg !1113
  br label %bb1.i, !dbg !1122

bb1.i:                                            ; preds = %_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zipINtB4_3ZipINtNtB6_6copied6CopiedINtNtNtBa_5slice4iter4ItertEEIBW_IB1i_hEEENtNtNtB8_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc.exit.i, %bb3
  %13 = phi i64 [ %14, %_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zipINtB4_3ZipINtNtB6_6copied6CopiedINtNtNtBa_5slice4iter4ItertEEIBW_IB1i_hEEENtNtNtB8_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc.exit.i ], [ 0, %bb3 ]
  %exitcond.not = icmp eq i64 %13, %other.1, !dbg !1132
  br i1 %exitcond.not, label %bb7, label %_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zipINtB4_3ZipINtNtB6_6copied6CopiedINtNtNtBa_5slice4iter4ItertEEIBW_IB1i_hEEENtNtNtB8_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc.exit.i, !dbg !1132

_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zipINtB4_3ZipINtNtB6_6copied6CopiedINtNtNtBa_5slice4iter4ItertEEIBW_IB1i_hEEENtNtNtB8_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc.exit.i: ; preds = %bb1.i
  %14 = add nuw i64 %13, 1, !dbg !1142
  %_3.i.i.i.i.i.i = getelementptr inbounds nuw i16, ptr %u16s.sroa.0.0, i64 %13, !dbg !1144
  %_0.i.i.i.i = load i16, ptr %_3.i.i.i.i.i.i, align 2, !dbg !1159, !noalias !1160, !noundef !14
  %_3.i.i.i2.i.i.i = getelementptr inbounds nuw i8, ptr %other.0, i64 %13, !dbg !1169
  %_0.i3.i.i.i = load i8, ptr %_3.i.i.i2.i.i.i, align 1, !dbg !1180, !noalias !1181, !noundef !14
  %_5.i.i.i = zext i8 %_0.i3.i.i.i to i16
  %_0.i.i.not.i = icmp eq i16 %_0.i.i.i.i, %_5.i.i.i
  br i1 %_0.i.i.not.i, label %bb1.i, label %bb7, !dbg !1184

bb7:                                              ; preds = %_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zipINtB4_3ZipINtNtB6_6copied6CopiedINtNtNtBa_5slice4iter4ItertEEIBW_IB1i_hEEENtNtNtB8_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc.exit.i, %bb1.i, %bb1, %bb22, %bb18
  %_0.sroa.0.1.off0 = phi i1 [ false, %bb18 ], [ false, %bb1 ], [ %11, %bb22 ], [ false, %_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zipINtB4_3ZipINtNtB6_6copied6CopiedINtNtNtBa_5slice4iter4ItertEEIBW_IB1i_hEEENtNtNtB8_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc.exit.i ], [ true, %bb1.i ]
  ret i1 %_0.sroa.0.1.off0, !dbg !1185
}

; bun_alloc::heap_breakdown::get_zone
; Function Attrs: nounwind
define noundef nonnull ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone(ptr noalias noundef nonnull readonly captures(none) %0, i64 noundef range(i64 0, -9223372036854775808) %1) unnamed_addr #1 personality ptr @rust_eh_personality !dbg !1186 {
start:
  %owned = alloca [24 x i8], align 8
  %2 = load atomic ptr, ptr @_RNvNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone4LOCK acquire, align 8, !dbg !1187, !noalias !1209
  %3 = icmp eq ptr %2, null, !dbg !1212
  br i1 %3, label %bb7.i.i, label %_RINvMNtNtNtCsg1bLsEOY8ZL_3std3sys4sync8once_boxINtB3_7OnceBoxNtNtNtNtNtB7_3pal4unix4sync5mutex5MutexE11get_or_initNCNvMNtNtB5_5mutex7pthreadNtB1T_5Mutex3get0ECs9SN9c7tmF9T_9bun_alloc.exit.i, !dbg !1212, !prof !53

bb7.i.i:                                          ; preds = %start
; call <std::sys::sync::once_box::OnceBox<std::sys::pal::unix::sync::mutex::Mutex>>::initialize::<<std::sys::sync::mutex::pthread::Mutex>::get::{closure#0}>
  %4 = tail call fastcc noundef nonnull align 8 ptr @_RINvMNtNtNtCsg1bLsEOY8ZL_3std3sys4sync8once_boxINtB3_7OnceBoxNtNtNtNtNtB7_3pal4unix4sync5mutex5MutexE10initializeNCNvMNtNtB5_5mutex7pthreadNtB1S_5Mutex3get0ECs9SN9c7tmF9T_9bun_alloc() #33, !dbg !1216
  br label %_RINvMNtNtNtCsg1bLsEOY8ZL_3std3sys4sync8once_boxINtB3_7OnceBoxNtNtNtNtNtB7_3pal4unix4sync5mutex5MutexE11get_or_initNCNvMNtNtB5_5mutex7pthreadNtB1T_5Mutex3get0ECs9SN9c7tmF9T_9bun_alloc.exit.i, !dbg !1217

_RINvMNtNtNtCsg1bLsEOY8ZL_3std3sys4sync8once_boxINtB3_7OnceBoxNtNtNtNtNtB7_3pal4unix4sync5mutex5MutexE11get_or_initNCNvMNtNtB5_5mutex7pthreadNtB1T_5Mutex3get0ECs9SN9c7tmF9T_9bun_alloc.exit.i: ; preds = %bb7.i.i, %start
  %_0.sroa.0.0.i.i = phi ptr [ %4, %bb7.i.i ], [ %2, %start ], !dbg !1218
; call <std::sys::pal::unix::sync::mutex::Mutex>::lock
  tail call void @_RNvMNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutexNtB2_5Mutex4lock(ptr noundef nonnull align 8 %_0.sroa.0.0.i.i) #33, !dbg !1219, !noalias !1209
  %5 = load atomic i64, ptr @_RNvNtNtCsg1bLsEOY8ZL_3std9panicking11panic_count18GLOBAL_PANIC_COUNT monotonic, align 8, !dbg !1220, !noalias !1209
  %_6.i.i = and i64 %5, 9223372036854775807, !dbg !1243
  %6 = icmp eq i64 %_6.i.i, 0, !dbg !1243
  br i1 %6, label %_RNvMs5_NtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutexINtB5_5MutexuE4lockCs9SN9c7tmF9T_9bun_alloc.exit, label %bb6.i.i, !dbg !1243, !prof !462

bb6.i.i:                                          ; preds = %_RINvMNtNtNtCsg1bLsEOY8ZL_3std3sys4sync8once_boxINtB3_7OnceBoxNtNtNtNtNtB7_3pal4unix4sync5mutex5MutexE11get_or_initNCNvMNtNtB5_5mutex7pthreadNtB1T_5Mutex3get0ECs9SN9c7tmF9T_9bun_alloc.exit.i
; call std::panicking::panic_count::is_zero_slow_path
  %7 = tail call noundef zeroext i1 @_RNvNtNtCsg1bLsEOY8ZL_3std9panicking11panic_count17is_zero_slow_path() #36, !dbg !1244, !noalias !1209
  %8 = xor i1 %7, true, !dbg !1245
  br label %_RNvMs5_NtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutexINtB5_5MutexuE4lockCs9SN9c7tmF9T_9bun_alloc.exit, !dbg !1244

_RNvMs5_NtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutexINtB5_5MutexuE4lockCs9SN9c7tmF9T_9bun_alloc.exit: ; preds = %_RINvMNtNtNtCsg1bLsEOY8ZL_3std3sys4sync8once_boxINtB3_7OnceBoxNtNtNtNtNtB7_3pal4unix4sync5mutex5MutexE11get_or_initNCNvMNtNtB5_5mutex7pthreadNtB1T_5Mutex3get0ECs9SN9c7tmF9T_9bun_alloc.exit.i, %bb6.i.i
  %_5.sroa.0.0.off0.i.i = phi i1 [ %8, %bb6.i.i ], [ false, %_RINvMNtNtNtCsg1bLsEOY8ZL_3std3sys4sync8once_boxINtB3_7OnceBoxNtNtNtNtNtB7_3pal4unix4sync5mutex5MutexE11get_or_initNCNvMNtNtB5_5mutex7pthreadNtB1T_5Mutex3get0ECs9SN9c7tmF9T_9bun_alloc.exit.i ]
  %9 = load atomic i8, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone4LOCK, i64 8) monotonic, align 1, !dbg !1246, !noalias !1209
  %_32 = load ptr, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone5ZONES, i64 8), align 8, !dbg !1254, !nonnull !14, !noundef !14
  %_31 = load i64, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone5ZONES, i64 16), align 8, !dbg !1274, !noundef !14
  %_36.idx = mul nuw nsw i64 %_31, 56, !dbg !1275
  %_36 = getelementptr inbounds nuw i8, ptr %_32, i64 %_36.idx, !dbg !1275
  %_133.i = icmp eq i64 %_31, 0, !dbg !1284
  br i1 %_133.i, label %bb3, label %bb13.i, !dbg !1294

bb13.i:                                           ; preds = %_RNvMs5_NtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutexINtB5_5MutexuE4lockCs9SN9c7tmF9T_9bun_alloc.exit, %bb4.i
  %_2324.i = phi ptr [ %_23.i, %bb4.i ], [ %_32, %_RNvMs5_NtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutexINtB5_5MutexuE4lockCs9SN9c7tmF9T_9bun_alloc.exit ]
  %_23.i = getelementptr inbounds nuw i8, ptr %_2324.i, i64 56, !dbg !1295
  %10 = getelementptr inbounds nuw i8, ptr %_2324.i, i64 16, !dbg !1298
  %_8.i.i = load i64, ptr %10, align 8, !dbg !1298, !noalias !1305, !noundef !14
  %_11.i.i = icmp eq i64 %_8.i.i, %1, !dbg !1312
  br i1 %_11.i.i, label %_RNCNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone0B5_.exit.i, label %bb4.i, !dbg !1312

_RNCNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone0B5_.exit.i: ; preds = %bb13.i
  %11 = getelementptr inbounds nuw i8, ptr %_2324.i, i64 8, !dbg !1318
  %_9.i.i = load ptr, ptr %11, align 8, !dbg !1318, !noalias !1305, !nonnull !14, !noundef !14
  %12 = tail call i32 @memcmp(ptr nonnull %_9.i.i, ptr nonnull %0, i64 %1), !dbg !1327, !noalias !1305
  %13 = icmp eq i32 %12, 0, !dbg !1327
  br i1 %13, label %bb2, label %bb4.i, !dbg !1331

bb4.i:                                            ; preds = %_RNCNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone0B5_.exit.i, %bb13.i
  %_13.i = icmp eq ptr %_23.i, %_36, !dbg !1284
  br i1 %_13.i, label %bb3, label %bb13.i, !dbg !1294

bb2:                                              ; preds = %_RNCNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone0B5_.exit.i
  %14 = getelementptr inbounds nuw i8, ptr %_2324.i, i64 48, !dbg !1332
  %15 = load ptr, ptr %14, align 8, !dbg !1332, !nonnull !14, !noundef !14
  br i1 %_5.sroa.0.0.off0.i.i, label %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_.exit, label %bb1.i.i.i.i, !dbg !1333

bb1.i.i.i.i:                                      ; preds = %bb2
  %16 = load atomic i64, ptr @_RNvNtNtCsg1bLsEOY8ZL_3std9panicking11panic_count18GLOBAL_PANIC_COUNT monotonic, align 8, !dbg !1343, !noalias !1353
  %_7.i.i.i.i = and i64 %16, 9223372036854775807, !dbg !1362
  %17 = icmp eq i64 %_7.i.i.i.i, 0, !dbg !1362
  br i1 %17, label %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_.exit, label %bb6.i.i.i.i, !dbg !1362, !prof !462

bb6.i.i.i.i:                                      ; preds = %bb1.i.i.i.i
; call std::panicking::panic_count::is_zero_slow_path
  %_6.i.i.i.i = tail call noundef zeroext i1 @_RNvNtNtCsg1bLsEOY8ZL_3std9panicking11panic_count17is_zero_slow_path() #36, !dbg !1363, !noalias !1353
  br i1 %_6.i.i.i.i, label %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_.exit, label %bb2.i.i.i.i, !dbg !1364

bb2.i.i.i.i:                                      ; preds = %bb6.i.i.i.i
  store atomic i8 1, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone4LOCK, i64 8) monotonic, align 1, !dbg !1365, !noalias !1353
  br label %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_.exit, !dbg !1370

_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_.exit: ; preds = %bb2, %bb1.i.i.i.i, %bb6.i.i.i.i, %bb2.i.i.i.i
  %18 = load atomic ptr, ptr @_RNvNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone4LOCK monotonic, align 8, !dbg !1371, !noalias !1379
; call <std::sys::pal::unix::sync::mutex::Mutex>::unlock
  tail call void @_RNvMNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutexNtB2_5Mutex6unlock(ptr noundef nonnull align 8 %18) #33, !dbg !1380, !noalias !1379
  br label %bb7, !dbg !1381

bb3:                                              ; preds = %bb4.i, %_RNvMs5_NtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutexINtB5_5MutexuE4lockCs9SN9c7tmF9T_9bun_alloc.exit
  %_15 = add nuw i64 %1, 1, !dbg !1382
  %_39.i = icmp sgt i64 %_15, -1, !dbg !1383
  br i1 %_39.i, label %bb18.i, label %bb14, !dbg !1403

bb18.i:                                           ; preds = %bb3
; call __rustc::__rust_no_alloc_shim_is_unstable_v2
  tail call void @_RNvCs3TqXShXgh4d_7___rustc35___rust_no_alloc_shim_is_unstable_v2() #33, !dbg !1404, !noalias !1410
; call __rustc::__rust_alloc
  %19 = tail call noundef ptr @_RNvCs3TqXShXgh4d_7___rustc12___rust_alloc(i64 noundef range(i64 0, -9223372036854775808) %_15, i64 noundef range(i64 1, 9) 1) #33, !dbg !1413, !noalias !1410
  %20 = icmp eq ptr %19, null, !dbg !1414
  br i1 %20, label %bb14, label %_RNvMs_NtCskhhhlZ4wWGP_5alloc3vecINtB4_3VechE7reserveCs9SN9c7tmF9T_9bun_alloc.exit.i, !dbg !1416

bb7:                                              ; preds = %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_.exit29, %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_.exit
  %zone.sroa.0.0 = phi ptr [ %15, %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_.exit ], [ %zone.i, %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_.exit29 ], !dbg !1417
  ret ptr %zone.sroa.0.0, !dbg !1381

bb14:                                             ; preds = %bb3, %bb18.i
  %_43.sroa.4.0.ph = phi i64 [ 1, %bb18.i ], [ 0, %bb3 ]
; call alloc::raw_vec::handle_error
  tail call void @_RNvNtCskhhhlZ4wWGP_5alloc7raw_vec12handle_error(i64 noundef %_43.sroa.4.0.ph, i64 %_15) #34, !dbg !1418
  unreachable, !dbg !1418

_RNvMs_NtCskhhhlZ4wWGP_5alloc3vecINtB4_3VechE7reserveCs9SN9c7tmF9T_9bun_alloc.exit.i: ; preds = %bb18.i
  store i64 %_15, ptr %owned, align 8, !dbg !1420
  %21 = getelementptr inbounds nuw i8, ptr %owned, i64 8, !dbg !1420
  store ptr %19, ptr %21, align 8, !dbg !1420
  %22 = getelementptr inbounds nuw i8, ptr %owned, i64 16, !dbg !1420
  %_6.not.i = icmp eq i64 %1, 0, !dbg !1421
  br i1 %_6.not.i, label %_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VechE8push_mutCs9SN9c7tmF9T_9bun_alloc.exit, label %bb2.i, !dbg !1421

bb2.i:                                            ; preds = %_RNvMs_NtCskhhhlZ4wWGP_5alloc3vecINtB4_3VechE7reserveCs9SN9c7tmF9T_9bun_alloc.exit.i
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %19, ptr nonnull readonly align 1 %0, i64 %1, i1 false), !dbg !1435, !noalias !1438
  br label %_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VechE8push_mutCs9SN9c7tmF9T_9bun_alloc.exit, !dbg !1441

_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VechE8push_mutCs9SN9c7tmF9T_9bun_alloc.exit: ; preds = %bb2.i, %_RNvMs_NtCskhhhlZ4wWGP_5alloc3vecINtB4_3VechE7reserveCs9SN9c7tmF9T_9bun_alloc.exit.i
  %end.i = getelementptr inbounds nuw i8, ptr %19, i64 %1, !dbg !1442
  store i8 0, ptr %end.i, align 1, !dbg !1450
  store i64 %_15, ptr %22, align 8, !dbg !1454
  %zone.i = call noundef ptr @malloc_create_zone(i64 noundef 0, i32 noundef 0) #33, !dbg !1455
  call void @malloc_set_zone_name(ptr noundef %zone.i, ptr noundef nonnull %19) #33, !dbg !1458
  br i1 %_6.not.i, label %bb20, label %_RNvXs_NtCskhhhlZ4wWGP_5alloc5allocNtB4_6GlobalNtNtCsgXhsEb1m4tm_4core5alloc9Allocator8allocate.exit.i, !dbg !1459

_RNvXs_NtCskhhhlZ4wWGP_5alloc5allocNtB4_6GlobalNtNtCsgXhsEb1m4tm_4core5alloc9Allocator8allocate.exit.i: ; preds = %_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VechE8push_mutCs9SN9c7tmF9T_9bun_alloc.exit
; call __rustc::__rust_no_alloc_shim_is_unstable_v2
  call void @_RNvCs3TqXShXgh4d_7___rustc35___rust_no_alloc_shim_is_unstable_v2() #33, !dbg !1479, !noalias !1484
; call __rustc::__rust_alloc
  %23 = call noundef ptr @_RNvCs3TqXShXgh4d_7___rustc12___rust_alloc(i64 noundef range(i64 0, -9223372036854775808) %1, i64 noundef range(i64 1, 9) 1) #33, !dbg !1487, !noalias !1484
  %24 = icmp eq ptr %23, null, !dbg !1488
  br i1 %24, label %bb22, label %bb19, !dbg !1489

bb22:                                             ; preds = %_RNvXs_NtCskhhhlZ4wWGP_5alloc5allocNtB4_6GlobalNtNtCsgXhsEb1m4tm_4core5alloc9Allocator8allocate.exit.i
; call alloc::raw_vec::handle_error
  call void @_RNvNtCskhhhlZ4wWGP_5alloc7raw_vec12handle_error(i64 noundef 1, i64 %1) #34, !dbg !1490
  unreachable, !dbg !1490

bb20:                                             ; preds = %_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VechE8push_mutCs9SN9c7tmF9T_9bun_alloc.exit, %bb19
  %25 = phi ptr [ %23, %bb19 ], [ inttoptr (i64 1 to ptr), %_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VechE8push_mutCs9SN9c7tmF9T_9bun_alloc.exit ]
  %len.i13 = load i64, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone5ZONES, i64 16), align 8, !dbg !1492, !noalias !1497, !noundef !14
  %self1.i14 = load i64, ptr @_RNvNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone5ZONES, align 8, !dbg !1500, !range !805, !noalias !1497, !noundef !14
  %_4.i15 = icmp eq i64 %len.i13, %self1.i14, !dbg !1506
  br i1 %_4.i15, label %bb1.i19, label %_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VecTIBw_hEBG_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE8push_mutBU_.exit, !dbg !1506

bb1.i19:                                          ; preds = %bb20
; call <alloc::raw_vec::RawVec<(alloc::vec::Vec<u8>, alloc::vec::Vec<u8>, &bun_alloc::heap_breakdown::Zone)>>::grow_one
  call void @_RNvMs3_NtCskhhhlZ4wWGP_5alloc7raw_vecINtB5_6RawVecTINtNtB7_3vec3VechEBN_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE8grow_oneB1d_(ptr noalias noundef align 8 dereferenceable(16) @_RNvNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone5ZONES) #36, !dbg !1507, !noalias !1497
  br label %_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VecTIBw_hEBG_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE8push_mutBU_.exit, !dbg !1508

_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VecTIBw_hEBG_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE8push_mutBU_.exit: ; preds = %bb20, %bb1.i19
  %_14.i17 = load ptr, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone5ZONES, i64 8), align 8, !dbg !1509, !noalias !1497, !nonnull !14, !noundef !14
  %end.i18 = getelementptr inbounds nuw { %"alloc::vec::Vec<u8>", %"alloc::vec::Vec<u8>", ptr }, ptr %_14.i17, i64 %len.i13, !dbg !1518
  store i64 %1, ptr %end.i18, align 8, !dbg !1521
  %_20.sroa.4.0.end.i18.sroa_idx = getelementptr inbounds nuw i8, ptr %end.i18, i64 8, !dbg !1521
  store ptr %25, ptr %_20.sroa.4.0.end.i18.sroa_idx, align 8, !dbg !1521
  %_20.sroa.5.0.end.i18.sroa_idx = getelementptr inbounds nuw i8, ptr %end.i18, i64 16, !dbg !1521
  store i64 %1, ptr %_20.sroa.5.0.end.i18.sroa_idx, align 8, !dbg !1521
  %_20.sroa.6.0.end.i18.sroa_idx = getelementptr inbounds nuw i8, ptr %end.i18, i64 24, !dbg !1521
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %_20.sroa.6.0.end.i18.sroa_idx, ptr noundef nonnull align 8 dereferenceable(24) %owned, i64 24, i1 false), !dbg !1521
  %_20.sroa.7.0.end.i18.sroa_idx = getelementptr inbounds nuw i8, ptr %end.i18, i64 48, !dbg !1521
  store ptr %zone.i, ptr %_20.sroa.7.0.end.i18.sroa_idx, align 8, !dbg !1521
  %26 = add i64 %len.i13, 1, !dbg !1525
  store i64 %26, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone5ZONES, i64 16), align 8, !dbg !1525, !noalias !1497
  br i1 %_5.sroa.0.0.off0.i.i, label %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_.exit29, label %bb1.i.i.i.i24, !dbg !1526

bb1.i.i.i.i24:                                    ; preds = %_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VecTIBw_hEBG_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE8push_mutBU_.exit
  %27 = load atomic i64, ptr @_RNvNtNtCsg1bLsEOY8ZL_3std9panicking11panic_count18GLOBAL_PANIC_COUNT monotonic, align 8, !dbg !1531, !noalias !1537
  %_7.i.i.i.i25 = and i64 %27, 9223372036854775807, !dbg !1546
  %28 = icmp eq i64 %_7.i.i.i.i25, 0, !dbg !1546
  br i1 %28, label %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_.exit29, label %bb6.i.i.i.i26, !dbg !1546, !prof !462

bb6.i.i.i.i26:                                    ; preds = %bb1.i.i.i.i24
; call std::panicking::panic_count::is_zero_slow_path
  %_6.i.i.i.i27 = call noundef zeroext i1 @_RNvNtNtCsg1bLsEOY8ZL_3std9panicking11panic_count17is_zero_slow_path() #36, !dbg !1547, !noalias !1537
  br i1 %_6.i.i.i.i27, label %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_.exit29, label %bb2.i.i.i.i28, !dbg !1548

bb2.i.i.i.i28:                                    ; preds = %bb6.i.i.i.i26
  store atomic i8 1, ptr getelementptr inbounds nuw (i8, ptr @_RNvNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone4LOCK, i64 8) monotonic, align 1, !dbg !1549, !noalias !1537
  br label %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_.exit29, !dbg !1552

_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_.exit29: ; preds = %_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VecTIBw_hEBG_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE8push_mutBU_.exit, %bb1.i.i.i.i24, %bb6.i.i.i.i26, %bb2.i.i.i.i28
  %29 = load atomic ptr, ptr @_RNvNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone4LOCK monotonic, align 8, !dbg !1553, !noalias !1558
; call <std::sys::pal::unix::sync::mutex::Mutex>::unlock
  call void @_RNvMNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutexNtB2_5Mutex6unlock(ptr noundef nonnull align 8 %29) #33, !dbg !1559, !noalias !1558
  br label %bb7, !dbg !1381

bb19:                                             ; preds = %_RNvXs_NtCskhhhlZ4wWGP_5alloc5allocNtB4_6GlobalNtNtCsgXhsEb1m4tm_4core5alloc9Allocator8allocate.exit.i
  call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %23, ptr nonnull align 1 %0, i64 %1, i1 false), !dbg !1560
  br label %bb20, !dbg !1566
}

; bun_alloc::mimalloc_arena::vtable_free
; Function Attrs: nounwind
define void @_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena11vtable_free(ptr readnone captures(none) %_ctx, ptr noalias noundef nonnull %buf.0, i64 range(i64 0, -9223372036854775808) %buf.1, i8 %a, i64 %_ra) unnamed_addr #1 !dbg !1567 {
start:
  tail call void @mi_free(ptr noundef nonnull %buf.0) #33, !dbg !1568
  ret void, !dbg !1572
}

; bun_alloc::mimalloc_arena::vtable_alloc
; Function Attrs: nounwind
define noundef ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena12vtable_alloc(ptr noundef readonly captures(none) %ctx, i64 noundef %len, i8 noundef %a, i64 %_ra) unnamed_addr #1 !dbg !1573 {
start:
  %0 = and i8 %a, 63, !dbg !1574
  %_8 = load ptr, ptr %ctx, align 8, !dbg !1578, !nonnull !14, !noundef !14
  %_10 = icmp samesign ugt i8 %0, 4, !dbg !1583
  br i1 %_10, label %bb1, label %bb2, !dbg !1585

bb2:                                              ; preds = %start
  %1 = tail call noundef ptr @mi_heap_malloc(ptr noundef nonnull %_8, i64 noundef %len) #33, !dbg !1588
  br label %bb3, !dbg !1588

bb1:                                              ; preds = %start
  %2 = zext nneg i8 %0 to i64, !dbg !1574
  %_6 = shl nuw i64 1, %2, !dbg !1574
  %3 = tail call noundef ptr @mi_heap_malloc_aligned(ptr noundef nonnull %_8, i64 noundef %len, i64 noundef %_6) #33, !dbg !1589
  br label %bb3, !dbg !1589

bb3:                                              ; preds = %bb1, %bb2
  %_9.sroa.0.0 = phi ptr [ %3, %bb1 ], [ %1, %bb2 ], !dbg !1590
  ret ptr %_9.sroa.0.0, !dbg !1591
}

; bun_alloc::mimalloc_arena::vtable_remap
; Function Attrs: nounwind
define noundef ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena12vtable_remap(ptr noundef readonly captures(none) %ctx, ptr noalias noundef nonnull %buf.0, i64 range(i64 0, -9223372036854775808) %buf.1, i8 noundef %a, i64 noundef %new_len, i64 %_ra) unnamed_addr #1 !dbg !1592 {
start:
  %0 = and i8 %a, 63, !dbg !1593
  %1 = zext nneg i8 %0 to i64, !dbg !1593
  %_9 = shl nuw i64 1, %1, !dbg !1593
  %_14 = load ptr, ptr %ctx, align 8, !dbg !1597, !nonnull !14, !noundef !14
  %_11 = tail call noundef ptr @mi_heap_realloc_aligned(ptr noundef nonnull %_14, ptr noundef nonnull %buf.0, i64 noundef %new_len, i64 noundef %_9) #33, !dbg !1602
  ret ptr %_11, !dbg !1603
}

; bun_alloc::mimalloc_arena::vtable_resize
; Function Attrs: nounwind
define noundef zeroext i1 @_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena13vtable_resize(ptr readnone captures(none) %ctx, ptr noalias noundef nonnull %buf.0, i64 range(i64 0, -9223372036854775808) %buf.1, i8 %_a, i64 noundef %new_len, i64 %_ra) unnamed_addr #1 !dbg !1604 {
start:
  %_11 = tail call noundef ptr @mi_expand(ptr noundef nonnull %buf.0, i64 noundef %new_len) #33, !dbg !1605
  %_10 = icmp ne ptr %_11, null, !dbg !1609
  ret i1 %_10, !dbg !1620
}

; bun_alloc::mimalloc_arena::global_vtable_alloc
; Function Attrs: nounwind
define noundef ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena19global_vtable_alloc(ptr readnone captures(none) %_ctx, i64 noundef %len, i8 noundef %a, i64 %_ra) unnamed_addr #1 !dbg !1621 {
start:
  %0 = and i8 %a, 63, !dbg !1622
  %_7 = icmp samesign ugt i8 %0, 4, !dbg !1625
  br i1 %_7, label %bb1, label %bb2, !dbg !1627

bb2:                                              ; preds = %start
  %1 = tail call noundef ptr @mi_malloc(i64 noundef %len) #33, !dbg !1632
  br label %bb3, !dbg !1632

bb1:                                              ; preds = %start
  %2 = zext nneg i8 %0 to i64, !dbg !1622
  %_6 = shl nuw i64 1, %2, !dbg !1622
  %3 = tail call noundef ptr @mi_malloc_aligned(i64 noundef %len, i64 noundef %_6) #33, !dbg !1633
  br label %bb3, !dbg !1633

bb3:                                              ; preds = %bb1, %bb2
  %_5.sroa.0.0 = phi ptr [ %3, %bb1 ], [ %1, %bb2 ], !dbg !1634
  ret ptr %_5.sroa.0.0, !dbg !1635
}

; bun_alloc::StringImplAllocator::free
; Function Attrs: nounwind
define void @_RNvNtCs9SN9c7tmF9T_9bun_alloc19StringImplAllocator4free(ptr noundef %ptr, ptr noalias nonnull readnone captures(none) %buf.0, i64 range(i64 0, -9223372036854775808) %buf.1, i8 %_3, i64 %_4) unnamed_addr #1 !dbg !953 {
start:
  %0 = atomicrmw sub ptr %ptr, i32 2 monotonic, align 4, !dbg !1636
  %1 = icmp eq i32 %0, 2, !dbg !1640
  br i1 %1, label %bb3, label %bb1, !dbg !1640

bb3:                                              ; preds = %start
  tail call void @Bun__WTFStringImpl__destroy(ptr noundef %ptr) #33, !dbg !1641
  br label %bb1, !dbg !1642

bb1:                                              ; preds = %start, %bb3
  ret void, !dbg !1643
}

; bun_alloc::StringImplAllocator::alloc
; Function Attrs: mustprogress nofree norecurse nounwind willreturn memory(argmem: readwrite)
define internal noundef ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc19StringImplAllocator5alloc(ptr noundef captures(none) %ptr, i64 noundef %len, i8 %_3, i64 %_4) unnamed_addr #8 !dbg !1644 {
start:
  %_15 = getelementptr inbounds nuw i8, ptr %ptr, i64 16, !dbg !1645
  %_13 = load i32, ptr %_15, align 4, !dbg !1655, !noundef !14
  %_12 = and i32 %_13, 4, !dbg !1656
  %0 = icmp eq i32 %_12, 0, !dbg !1657
  %1 = getelementptr inbounds nuw i8, ptr %ptr, i64 4, !dbg !1658
  %_11 = load i32, ptr %1, align 4, !dbg !1658, !noundef !14
  %_10 = zext i32 %_11 to i64, !dbg !1658
  %2 = zext i1 %0 to i64, !dbg !1657
  %_7.sroa.0.0 = shl nuw nsw i64 %_10, %2, !dbg !1657
  %_6.not = icmp eq i64 %_7.sroa.0.0, %len, !dbg !1659
  br i1 %_6.not, label %bb2, label %bb3, !dbg !1659

bb2:                                              ; preds = %start
  %3 = atomicrmw add ptr %ptr, i32 2 monotonic, align 4, !dbg !1660
  %4 = getelementptr inbounds nuw i8, ptr %ptr, i64 8, !dbg !1667
  %_8 = load ptr, ptr %4, align 8, !dbg !1667, !noundef !14
  br label %bb3, !dbg !1668

bb3:                                              ; preds = %start, %bb2
  %_0.sroa.0.0 = phi ptr [ %_8, %bb2 ], [ null, %start ], !dbg !1669
  ret ptr %_0.sroa.0.0, !dbg !1668
}

; bun_alloc::buffer_fallback_allocator::free
; Function Attrs: nounwind
define void @_RNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator4free(ptr noundef captures(none) %ctx, ptr noalias noundef nonnull %buf.0, i64 noundef range(i64 0, -9223372036854775808) %buf.1, i8 noundef %alignment, i64 noundef %ra) unnamed_addr #1 !dbg !1670 {
start:
  %0 = getelementptr inbounds nuw i8, ptr %ctx, i64 16, !dbg !1673
  %_15.0 = load ptr, ptr %0, align 8, !dbg !1673, !nonnull !14, !noundef !14
  %1 = getelementptr inbounds nuw i8, ptr %ctx, i64 24, !dbg !1673
  %_15.1 = load i64, ptr %1, align 8, !dbg !1673, !noundef !14
  %_9 = ptrtoint ptr %_15.0 to i64, !dbg !1673
  %_11 = ptrtoint ptr %buf.0 to i64, !dbg !1678
  %_12 = icmp uge ptr %buf.0, %_15.0, !dbg !1680
  %_13 = add i64 %_15.1, %_9
  %_6 = icmp ugt i64 %_13, %_11
  %or.cond = and i1 %_12, %_6, !dbg !1680
  br i1 %or.cond, label %bb1, label %bb2, !dbg !1680

bb2:                                              ; preds = %start
  %_31 = load ptr, ptr %ctx, align 8, !dbg !1682, !nonnull !14, !align !164, !noundef !14
  %2 = getelementptr inbounds nuw i8, ptr %_31, i64 24, !dbg !1682
  %_29 = load ptr, ptr %2, align 8, !dbg !1682, !nonnull !14, !noundef !14
  %3 = getelementptr inbounds nuw i8, ptr %ctx, i64 8, !dbg !1685
  %_30 = load ptr, ptr %3, align 8, !dbg !1685, !noundef !14
  tail call void %_29(ptr noundef %_30, ptr noalias noundef nonnull %buf.0, i64 noundef %buf.1, i8 noundef %alignment, i64 noundef %ra) #33, !dbg !1682
  br label %bb3, !dbg !1686

bb1:                                              ; preds = %start
  %_18 = add i64 %buf.1, %_11, !dbg !1687
  %_17 = sub i64 %_18, %_9, !dbg !1687
  %4 = getelementptr inbounds nuw i8, ptr %ctx, i64 32, !dbg !1690
  %_25 = load i64, ptr %4, align 8, !dbg !1690, !noundef !14
  %_24 = icmp eq i64 %_17, %_25, !dbg !1692
  br i1 %_24, label %bb6, label %bb3, !dbg !1692

bb3:                                              ; preds = %bb6, %bb1, %bb2
  ret void, !dbg !1686

bb6:                                              ; preds = %bb1
  %5 = sub i64 %_17, %buf.1, !dbg !1693
  store i64 %5, ptr %4, align 8, !dbg !1693
  br label %bb3, !dbg !1694
}

; bun_alloc::buffer_fallback_allocator::alloc
; Function Attrs: nounwind
define noundef ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator5alloc(ptr noundef captures(none) %ctx, i64 noundef %0, i8 noundef %1, i64 noundef %2) unnamed_addr #1 personality ptr @rust_eh_personality !dbg !1695 {
start:
  %_8 = getelementptr inbounds nuw i8, ptr %ctx, i64 16, !dbg !1696
  %_23.0.i = load ptr, ptr %_8, align 8, !dbg !1698, !alias.scope !1701, !nonnull !14, !noundef !14
  %base.i = ptrtoint ptr %_23.0.i to i64, !dbg !1698
  %3 = getelementptr inbounds nuw i8, ptr %ctx, i64 32, !dbg !1704
  %_11.i = load i64, ptr %3, align 8, !dbg !1704, !alias.scope !1701, !noundef !14
  %4 = and i8 %1, 63, !dbg !1706
  %5 = zext nneg i8 %4 to i64, !dbg !1706
  %_12.i = shl nuw i64 1, %5, !dbg !1706
  %_10.i = add i64 %_12.i, -1, !dbg !1709
  %_9.i = add i64 %_10.i, %base.i, !dbg !1709
  %_8.i = add i64 %_9.i, %_11.i, !dbg !1710
  %_13.i = sub i64 0, %_12.i, !dbg !1711
  %aligned.i = and i64 %_8.i, %_13.i, !dbg !1710
  %_17.i = sub i64 %aligned.i, %base.i, !dbg !1712
  %_27.0.i = add i64 %_17.i, %0, !dbg !1714
  %_27.1.i = icmp ult i64 %_27.0.i, %_17.i, !dbg !1714
  %6 = getelementptr inbounds nuw i8, ptr %ctx, i64 24
  %_24.1.i = load i64, ptr %6, align 8, !alias.scope !1701
  %_20.i = icmp ugt i64 %_27.0.i, %_24.1.i
  %or.cond.i = select i1 %_27.1.i, i1 true, i1 %_20.i, !dbg !1717, !prof !861
  br i1 %or.cond.i, label %bb2.i2, label %_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator5alloc.exit.thread, !dbg !1717, !prof !861

_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator5alloc.exit.thread: ; preds = %start
  store i64 %_27.0.i, ptr %3, align 8, !dbg !1720, !alias.scope !1701
  %_22.i = inttoptr i64 %aligned.i to ptr, !dbg !1722
  br label %_RINvMNtCsgXhsEb1m4tm_4core6optionINtB3_6OptionOhE7or_elseNCNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator5alloc0EBZ_.exit, !dbg !1723

bb2.i2:                                           ; preds = %start
  %_12.i.i = load ptr, ptr %ctx, align 8, !dbg !1726, !noalias !1732, !nonnull !14, !align !164, !noundef !14
  %_10.i.i = load ptr, ptr %_12.i.i, align 8, !dbg !1726, !noalias !1732, !nonnull !14, !noundef !14
  %7 = getelementptr inbounds nuw i8, ptr %ctx, i64 8, !dbg !1737
  %_11.i.i = load ptr, ptr %7, align 8, !dbg !1737, !noalias !1732, !noundef !14
  %_9.i.i = tail call noundef ptr %_10.i.i(ptr noundef %_11.i.i, i64 noundef %0, i8 noundef %1, i64 noundef %2) #33, !dbg !1726, !noalias !1732
  br label %_RINvMNtCsgXhsEb1m4tm_4core6optionINtB3_6OptionOhE7or_elseNCNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator5alloc0EBZ_.exit, !dbg !1738

_RINvMNtCsgXhsEb1m4tm_4core6optionINtB3_6OptionOhE7or_elseNCNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator5alloc0EBZ_.exit: ; preds = %_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator5alloc.exit.thread, %bb2.i2
  %self.0.pn.i = phi ptr [ %_9.i.i, %bb2.i2 ], [ %_22.i, %_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator5alloc.exit.thread ]
  ret ptr %self.0.pn.i, !dbg !1739
}

; bun_alloc::buffer_fallback_allocator::remap
; Function Attrs: nounwind
define noundef ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator5remap(ptr noundef captures(none) %ctx, ptr noalias noundef nonnull %memory.0, i64 noundef range(i64 0, -9223372036854775808) %memory.1, i8 noundef %alignment, i64 noundef %new_len, i64 noundef %ra) unnamed_addr #1 !dbg !1740 {
start:
  %0 = getelementptr inbounds nuw i8, ptr %ctx, i64 16, !dbg !1741
  %_19.0 = load ptr, ptr %0, align 8, !dbg !1741, !nonnull !14, !noundef !14
  %1 = getelementptr inbounds nuw i8, ptr %ctx, i64 24, !dbg !1741
  %_19.1 = load i64, ptr %1, align 8, !dbg !1741, !noundef !14
  %_13 = ptrtoint ptr %_19.0 to i64, !dbg !1741
  %_15 = ptrtoint ptr %memory.0 to i64, !dbg !1745
  %_16 = icmp uge ptr %memory.0, %_19.0, !dbg !1747
  %_17 = add i64 %_19.1, %_13
  %_7 = icmp ugt i64 %_17, %_15
  %or.cond = and i1 %_16, %_7, !dbg !1747
  br i1 %or.cond, label %bb1, label %bb2, !dbg !1747

bb2:                                              ; preds = %start
  %_27 = load ptr, ptr %ctx, align 8, !dbg !1749, !nonnull !14, !align !164, !noundef !14
  %2 = getelementptr inbounds nuw i8, ptr %_27, i64 16, !dbg !1749
  %_25 = load ptr, ptr %2, align 8, !dbg !1749, !nonnull !14, !noundef !14
  %3 = getelementptr inbounds nuw i8, ptr %ctx, i64 8, !dbg !1752
  %_26 = load ptr, ptr %3, align 8, !dbg !1752, !noundef !14
  %_24 = tail call noundef ptr %_25(ptr noundef %_26, ptr noalias noundef nonnull %memory.0, i64 noundef %memory.1, i8 noundef %alignment, i64 noundef %new_len, i64 noundef %ra) #33, !dbg !1749
  br label %bb3, !dbg !1753

bb1:                                              ; preds = %start
  %_7.i = sub i64 %_15, %_13, !dbg !1754
  %buf_end.i = add i64 %_7.i, %memory.1, !dbg !1754
  %4 = getelementptr inbounds nuw i8, ptr %ctx, i64 32, !dbg !1759
  %_14.i = load i64, ptr %4, align 8, !dbg !1759, !alias.scope !1761, !noalias !1764, !noundef !14
  %_13.not.i = icmp eq i64 %buf_end.i, %_14.i, !dbg !1766
  br i1 %_13.not.i, label %bb2.i, label %_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator6resize.exit, !dbg !1766

bb2.i:                                            ; preds = %bb1
  %new_end.i = add i64 %_7.i, %new_len, !dbg !1767
  %_17.i = icmp ugt i64 %new_end.i, %_19.1, !dbg !1768
  br i1 %_17.i, label %bb3, label %_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator6resize.exit.thread, !dbg !1768

_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator6resize.exit.thread: ; preds = %bb2.i
  store i64 %new_end.i, ptr %4, align 8, !dbg !1770, !alias.scope !1761, !noalias !1764
  br label %5, !dbg !1771

_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator6resize.exit: ; preds = %bb1
  %.not = icmp ugt i64 %new_len, %memory.1, !dbg !1774
  br i1 %.not, label %bb3, label %5, !dbg !1771

5:                                                ; preds = %_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator6resize.exit.thread, %_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator6resize.exit
  br label %bb3, !dbg !1771

bb3:                                              ; preds = %bb2.i, %5, %_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator6resize.exit, %bb2
  %_0.sroa.0.1 = phi ptr [ %_24, %bb2 ], [ %memory.0, %5 ], [ null, %_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator6resize.exit ], [ null, %bb2.i ], !dbg !1775
  ret ptr %_0.sroa.0.1, !dbg !1753
}

; bun_alloc::buffer_fallback_allocator::resize
; Function Attrs: nounwind
define noundef zeroext i1 @_RNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator6resize(ptr noundef captures(none) %ctx, ptr noalias noundef nonnull %buf.0, i64 noundef range(i64 0, -9223372036854775808) %buf.1, i8 noundef %alignment, i64 noundef %new_len, i64 noundef %ra) unnamed_addr #1 !dbg !1777 {
start:
  %0 = getelementptr inbounds nuw i8, ptr %ctx, i64 16, !dbg !1778
  %_17.0 = load ptr, ptr %0, align 8, !dbg !1778, !nonnull !14, !noundef !14
  %1 = getelementptr inbounds nuw i8, ptr %ctx, i64 24, !dbg !1778
  %_17.1 = load i64, ptr %1, align 8, !dbg !1778, !noundef !14
  %_11 = ptrtoint ptr %_17.0 to i64, !dbg !1778
  %_13 = ptrtoint ptr %buf.0 to i64, !dbg !1782
  %_14 = icmp uge ptr %buf.0, %_17.0, !dbg !1784
  %_15 = add i64 %_17.1, %_11
  %_7 = icmp ugt i64 %_15, %_13
  %or.cond = and i1 %_14, %_7, !dbg !1784
  br i1 %or.cond, label %bb1, label %bb3, !dbg !1784

bb3:                                              ; preds = %start
  %_21 = load ptr, ptr %ctx, align 8, !dbg !1786, !nonnull !14, !align !164, !noundef !14
  %2 = getelementptr inbounds nuw i8, ptr %_21, i64 8, !dbg !1786
  %_19 = load ptr, ptr %2, align 8, !dbg !1786, !nonnull !14, !noundef !14
  %3 = getelementptr inbounds nuw i8, ptr %ctx, i64 8, !dbg !1789
  %_20 = load ptr, ptr %3, align 8, !dbg !1789, !noundef !14
  %4 = tail call noundef zeroext i1 %_19(ptr noundef %_20, ptr noalias noundef nonnull %buf.0, i64 noundef %buf.1, i8 noundef %alignment, i64 noundef %new_len, i64 noundef %ra) #33, !dbg !1786
  br label %bb4, !dbg !1790

bb1:                                              ; preds = %start
  %_7.i = sub i64 %_13, %_11, !dbg !1791
  %buf_end.i = add i64 %_7.i, %buf.1, !dbg !1791
  %5 = getelementptr inbounds nuw i8, ptr %ctx, i64 32, !dbg !1793
  %_14.i = load i64, ptr %5, align 8, !dbg !1793, !alias.scope !1794, !noalias !1797, !noundef !14
  %_13.not.i = icmp eq i64 %buf_end.i, %_14.i, !dbg !1799
  br i1 %_13.not.i, label %bb2.i, label %bb1.i, !dbg !1799

bb2.i:                                            ; preds = %bb1
  %new_end.i = add i64 %_7.i, %new_len, !dbg !1800
  %_17.i = icmp ugt i64 %new_end.i, %_17.1, !dbg !1801
  br i1 %_17.i, label %bb4, label %bb4.i, !dbg !1801

bb1.i:                                            ; preds = %bb1
  %6 = icmp ule i64 %new_len, %buf.1, !dbg !1802
  br label %bb4, !dbg !1803

bb4.i:                                            ; preds = %bb2.i
  store i64 %new_end.i, ptr %5, align 8, !dbg !1804, !alias.scope !1794, !noalias !1797
  br label %bb4, !dbg !1805

bb4:                                              ; preds = %bb4.i, %bb1.i, %bb2.i, %bb3
  %_0.sroa.0.0.in = phi i1 [ %4, %bb3 ], [ %6, %bb1.i ], [ true, %bb4.i ], [ false, %bb2.i ]
  ret i1 %_0.sroa.0.0.in, !dbg !1790
}

; bun_alloc::basic::free_without_size
; Function Attrs: nounwind
define void @_RNvNtCs9SN9c7tmF9T_9bun_alloc5basic17free_without_size(ptr noundef %ptr) unnamed_addr #1 !dbg !1806 {
start:
  tail call void @mi_free(ptr noundef %ptr) #33, !dbg !1807
  ret void, !dbg !1808
}

; bun_alloc::basic::default_allocator_free
; Function Attrs: nounwind
define void @_RNvNtCs9SN9c7tmF9T_9bun_alloc5basic22default_allocator_free(ptr readnone captures(none) %_1, ptr noalias noundef nonnull %buf.0, i64 range(i64 0, -9223372036854775808) %buf.1, i8 %_3, i64 %_4) unnamed_addr #1 !dbg !1809 {
start:
  tail call void @mi_free(ptr noundef nonnull %buf.0) #33, !dbg !1810
  ret void, !dbg !1813
}

; bun_alloc::c_thunks::mi_free_bytes
; Function Attrs: nounwind
define void @_RNvNtCs9SN9c7tmF9T_9bun_alloc8c_thunks13mi_free_bytes(ptr noundef %bytes, ptr noundef readnone captures(none) %_ctx) unnamed_addr #1 !dbg !1814 {
start:
  tail call void @mi_free(ptr noundef %bytes) #33, !dbg !1817
  ret void, !dbg !1820
}

; bun_alloc::c_thunks::mi_free_opaque
; Function Attrs: nounwind
define void @_RNvNtCs9SN9c7tmF9T_9bun_alloc8c_thunks14mi_free_opaque(ptr noundef readnone captures(none) %_1, ptr noundef %ptr) unnamed_addr #1 !dbg !1821 {
start:
  tail call void @mi_free(ptr noundef %ptr) #33, !dbg !1822
  ret void, !dbg !1825
}

; bun_alloc::c_thunks::mi_malloc_items
; Function Attrs: nounwind
define noundef nonnull ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc8c_thunks15mi_malloc_items(ptr noundef readnone captures(none) %_1, i32 noundef %items, i32 noundef %size) unnamed_addr #1 !dbg !1826 {
start:
  %_5 = mul i32 %size, %items, !dbg !1827
  %_4 = zext i32 %_5 to i64, !dbg !1827
  %p = tail call noundef ptr @mi_malloc(i64 noundef %_4) #33, !dbg !1828
  %0 = icmp eq ptr %p, null, !dbg !1831
  br i1 %0, label %bb1, label %bb2, !dbg !1831, !prof !53

bb1:                                              ; preds = %start
; call core::panicking::panic
  tail call void @_RNvNtCsgXhsEb1m4tm_4core9panicking5panic(ptr noalias noundef nonnull readonly captures(address, read_provenance) @alloc_a500d906b91607583596fa15e63c2ada, i64 noundef 40, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_0e3300b2a43a173da7f566e00bdaa86b) #35, !dbg !1833
  unreachable, !dbg !1833

bb2:                                              ; preds = %start
  ret ptr %p, !dbg !1834
}

; bun_alloc::fallback::free_without_size
; Function Attrs: mustprogress nounwind willreturn memory(argmem: readwrite, inaccessiblemem: readwrite)
define void @_RNvNtCs9SN9c7tmF9T_9bun_alloc8fallback17free_without_size(ptr noundef captures(none) %ptr) unnamed_addr #5 !dbg !1835 {
start:
  tail call void @free(ptr noundef %ptr) #33, !dbg !1836
  ret void, !dbg !1837
}

; bun_alloc::bss_arena_bump::map_arena
; Function Attrs: cold noinline nounwind
define internal fastcc noundef ptr @_RNvNvCs9SN9c7tmF9T_9bun_alloc14bss_arena_bump9map_arena() unnamed_addr #4 !dbg !1838 {
start:
  %_1 = tail call noundef ptr @mmap(ptr noundef null, i64 noundef 4194304, i32 noundef 3, i32 noundef 4098, i32 noundef -1, i64 noundef 0) #33, !dbg !1840
  %_2 = icmp eq ptr %_1, inttoptr (i64 -1 to ptr), !dbg !1843
  br i1 %_2, label %bb2, label %bb3, !dbg !1843, !prof !53

bb3:                                              ; preds = %start
  ret ptr %_1, !dbg !1845

bb2:                                              ; preds = %start
; call bun_alloc::out_of_memory
  tail call void @_RNvCs9SN9c7tmF9T_9bun_alloc13out_of_memory() #35, !dbg !1846
  unreachable, !dbg !1846
}

; <bun_alloc::mimalloc_arena::MimallocArena>::allocated_bytes::visit
; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: readwrite)
define internal noundef zeroext i1 @_RNvNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB7_13MimallocArena15allocated_bytes5visit(ptr readnone captures(none) %_heap, ptr noundef readonly captures(none) %area, ptr readnone captures(none) %_block, i64 %_block_size, ptr noundef captures(none) %arg) unnamed_addr #9 !dbg !1847 {
start:
  %0 = getelementptr inbounds nuw i8, ptr %area, i64 24, !dbg !1849
  %_7 = load i64, ptr %0, align 8, !dbg !1849, !noundef !14
  %1 = getelementptr inbounds nuw i8, ptr %area, i64 40, !dbg !1851
  %_8 = load i64, ptr %1, align 8, !dbg !1851, !noundef !14
  %2 = tail call { i64, i1 } @llvm.umul.with.overflow.i64(i64 %_7, i64 %_8), !dbg !1852
  %_11.0 = extractvalue { i64, i1 } %2, 0, !dbg !1852
  %_11.1 = extractvalue { i64, i1 } %2, 1, !dbg !1852
  br i1 %_11.1, label %bb2, label %bb1, !dbg !1859, !prof !53

bb2:                                              ; preds = %start
  br label %bb1, !dbg !1863

bb1:                                              ; preds = %start, %bb2
  %_14.sroa.0.0 = phi i64 [ -1, %bb2 ], [ %_11.0, %start ], !dbg !1864
  %3 = load i64, ptr %arg, align 8, !dbg !1865, !noundef !14
  %4 = add i64 %3, %_14.sroa.0.0, !dbg !1865
  store i64 %4, ptr %arg, align 8, !dbg !1865
  ret i1 true, !dbg !1866
}

; <bun_alloc::ast_alloc::ScopedAstAlloc as core::default::Default>::default
; Function Attrs: nounwind
define noundef align 8 ptr @_RNvXs2_NtCs9SN9c7tmF9T_9bun_alloc9ast_allocNtB5_14ScopedAstAllocNtNtCsgXhsEb1m4tm_4core7default7Default7default() unnamed_addr #1 personality ptr @rust_eh_personality !dbg !1867 {
start:
  %_3.i.i.i.i = tail call align 8 ptr @llvm.threadlocal.address.p0(ptr @_RNvNCNKNvNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc15AST_ALLOC_SPARE0023___RUST_STD_INTERNAL_VAL), !dbg !1869
  %_7.i.i.i.i = getelementptr inbounds nuw i8, ptr %_3.i.i.i.i, i64 8, !dbg !1888
  %_4.i.i.i.i = load i8, ptr %_7.i.i.i.i, align 1, !dbg !1896, !range !180, !noundef !14
  switch i8 %_4.i.i.i.i, label %default.unreachable [
    i8 0, label %bb2.i.i.i.i
    i8 1, label %bb10.i
    i8 2, label %bb6.i
  ], !dbg !1897, !prof !1898

default.unreachable:                              ; preds = %start
  unreachable

bb2.i.i.i.i:                                      ; preds = %start
; call std::sys::thread_local::destructors::list::register
  tail call void @_RNvNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local11destructors4list8register(ptr noundef nonnull align 8 %_3.i.i.i.i, ptr noundef nonnull @_RINvNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eager7destroyINtNtCsgXhsEb1m4tm_4core4cell4CellINtNtB1a_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEEB2D_) #33, !dbg !1899
  store i8 1, ptr %_7.i.i.i.i, align 1, !dbg !1902
  br label %bb10.i, !dbg !1910

bb10.i:                                           ; preds = %bb2.i.i.i.i, %start
  %_0.i.i.i.i = load ptr, ptr %_3.i.i.i.i, align 8, !dbg !1911, !align !164, !noundef !14
  store ptr null, ptr %_3.i.i.i.i, align 8, !dbg !1921
  %.not.i = icmp eq ptr %_0.i.i.i.i, null, !dbg !1923
  br i1 %.not.i, label %bb6.i, label %_RNvNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13acquire_state.exit, !dbg !1926

bb6.i:                                            ; preds = %bb10.i, %start
; call __rustc::__rust_no_alloc_shim_is_unstable_v2
  tail call void @_RNvCs3TqXShXgh4d_7___rustc35___rust_no_alloc_shim_is_unstable_v2() #33, !dbg !1927
; call __rustc::__rust_alloc
  %0 = tail call noundef align 8 dereferenceable_or_null(16416) ptr @_RNvCs3TqXShXgh4d_7___rustc12___rust_alloc(i64 noundef range(i64 0, -9223372036854775808) 16416, i64 noundef 8) #33, !dbg !1937
  %1 = icmp eq ptr %0, null, !dbg !1938
  br i1 %1, label %bb2.i.i.i, label %_RNvMNtCs9SN9c7tmF9T_9bun_alloc9ast_allocNtB2_13AstAllocState9new_boxed.exit.i, !dbg !1939, !prof !53

bb2.i.i.i:                                        ; preds = %bb6.i
; call alloc::alloc::handle_alloc_error
  tail call void @_RNvNtCskhhhlZ4wWGP_5alloc5alloc18handle_alloc_error(i64 noundef 8, i64 noundef 16416) #34, !dbg !1940
  unreachable, !dbg !1940

_RNvMNtCs9SN9c7tmF9T_9bun_alloc9ast_allocNtB2_13AstAllocState9new_boxed.exit.i: ; preds = %bb6.i
  %2 = getelementptr inbounds nuw i8, ptr %0, i64 16384, !dbg !1941
  %3 = getelementptr inbounds nuw i8, ptr %0, i64 16408, !dbg !1944
  tail call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %2, i8 0, i64 16, i1 false), !dbg !1947
  store i8 2, ptr %3, align 8, !dbg !1944
  br label %_RNvNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13acquire_state.exit, !dbg !1950

_RNvNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13acquire_state.exit: ; preds = %bb10.i, %_RNvMNtCs9SN9c7tmF9T_9bun_alloc9ast_allocNtB2_13AstAllocState9new_boxed.exit.i
  %_0.sroa.0.0.i = phi ptr [ %0, %_RNvMNtCs9SN9c7tmF9T_9bun_alloc9ast_allocNtB2_13AstAllocState9new_boxed.exit.i ], [ %_0.i.i.i.i, %bb10.i ], !dbg !1951
  %_4 = tail call align 8 ptr @llvm.threadlocal.address.p0(ptr @_RNvNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc9AST_ALLOC), !dbg !1952
  %_1 = load ptr, ptr %_4, align 8, !dbg !1955, !align !164, !noundef !14
  store ptr %_0.sroa.0.0.i, ptr %_4, align 8, !dbg !1960
  ret ptr %_1, !dbg !1962
}

; <bun_alloc::SliceCursor as core::fmt::Write>::write_str
; Function Attrs: inlinehint nounwind
define internal noundef zeroext i1 @_RNvXs6_Cs9SN9c7tmF9T_9bun_allocNtB5_11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_str(ptr noalias noundef align 8 captures(none) dereferenceable(24) %self, ptr noalias noundef nonnull readonly captures(none) %s.0, i64 noundef %s.1) unnamed_addr #10 !dbg !1963 {
start:
  %0 = getelementptr inbounds nuw i8, ptr %self, i64 16, !dbg !1965
  %_5 = load i64, ptr %0, align 8, !dbg !1965, !noundef !14
  %end = add i64 %_5, %s.1, !dbg !1965
  %1 = getelementptr inbounds nuw i8, ptr %self, i64 8, !dbg !1967
  %_12.1 = load i64, ptr %1, align 8, !dbg !1967, !noundef !14
  %_7 = icmp ugt i64 %end, %_12.1, !dbg !1969
  br i1 %_7, label %bb3, label %bb2, !dbg !1969

bb2:                                              ; preds = %start
  %_20 = icmp ult i64 %end, %_5, !dbg !1970
  br i1 %_20, label %bb6, label %bb4, !dbg !1970, !prof !394

bb4:                                              ; preds = %bb2
  %_13.0 = load ptr, ptr %self, align 8, !dbg !1977, !nonnull !14, !noundef !14
  %_23 = getelementptr inbounds nuw i8, ptr %_13.0, i64 %_5, !dbg !1978
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %_23, ptr nonnull readonly align 1 %s.0, i64 range(i64 0, -9223372036854775808) %s.1, i1 false), !dbg !1982, !alias.scope !1987, !noalias !1991
  store i64 %end, ptr %0, align 8, !dbg !1993
  br label %bb3, !dbg !1994

bb6:                                              ; preds = %bb2
; call core::slice::index::slice_index_fail
  tail call void @_RNvNtNtCsgXhsEb1m4tm_4core5slice5index16slice_index_fail(i64 noundef %_5, i64 noundef %end, i64 noundef %_12.1, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_fc8cfb579032aab044b502c62a1fa507) #35, !dbg !1995
  unreachable, !dbg !1995

bb3:                                              ; preds = %start, %bb4
  ret i1 %_7, !dbg !1994
}

; <bun_alloc::max_heap_allocator::MaxHeapAllocator as core::ops::drop::Drop>::drop
; Function Attrs: nounwind
define void @_RNvXs6_NtCs9SN9c7tmF9T_9bun_alloc18max_heap_allocatorNtB5_16MaxHeapAllocatorNtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4drop(ptr noalias noundef align 8 captures(none) dereferenceable(24) %self) unnamed_addr #1 !dbg !1996 {
start:
  %0 = load ptr, ptr %self, align 8, !dbg !1998, !noundef !14
  store ptr null, ptr %self, align 8, !dbg !2004
  %.not = icmp eq ptr %0, null, !dbg !2006
  br i1 %.not, label %bb3, label %bb1, !dbg !2007

bb1:                                              ; preds = %start
  %1 = getelementptr inbounds nuw i8, ptr %self, i64 8, !dbg !2008
  %_6 = load i64, ptr %1, align 8, !dbg !2008, !noundef !14
; call __rustc::__rust_dealloc
  tail call void @_RNvCs3TqXShXgh4d_7___rustc14___rust_dealloc(ptr noundef nonnull %0, i64 noundef %_6, i64 noundef 8) #33, !dbg !2009
  br label %bb3, !dbg !2014

bb3:                                              ; preds = %start, %bb1
  ret void, !dbg !2015
}

; <bun_alloc::String as core::fmt::Display>::fmt
; Function Attrs: nounwind
define noundef zeroext i1 @_RNvXse_Cs9SN9c7tmF9T_9bun_allocNtB5_6StringNtNtCsgXhsEb1m4tm_4core3fmt7Display3fmt(ptr noalias noundef readonly align 8 captures(none) dereferenceable(24) %self, ptr noalias noundef align 8 dereferenceable(24) %f) unnamed_addr #1 personality ptr @rust_eh_personality !dbg !2016 {
start:
  %_18 = alloca [24 x i8], align 8
  %_28 = load i8, ptr %self, align 8, !dbg !2018, !range !1050, !noundef !14
  switch i8 %_28, label %bb22 [
    i8 1, label %bb25
    i8 2, label %bb26
    i8 3, label %bb26
  ], !dbg !2021

bb25:                                             ; preds = %start
  %0 = getelementptr inbounds nuw i8, ptr %self, i64 8, !dbg !2022
  %_30 = load ptr, ptr %0, align 8, !dbg !2022, !noundef !14
  %_5.i = getelementptr inbounds nuw i8, ptr %_30, i64 16, !dbg !2025
  %_3.i = load i32, ptr %_5.i, align 4, !dbg !2030, !noundef !14
  %_2.i = and i32 %_3.i, 4, !dbg !2031
  %1 = icmp eq i32 %_2.i, 0, !dbg !2032
  %2 = getelementptr inbounds nuw i8, ptr %_30, i64 8, !dbg !2033
  %_12.i = load ptr, ptr %2, align 8, !dbg !2033, !noundef !14
  %_19.i = ptrtoint ptr %_12.i to i64, !dbg !2032
  %_18.i = or i64 %_19.i, -9223372036854775808, !dbg !2032
  %3 = inttoptr i64 %_18.i to ptr, !dbg !2032
  %_0.sroa.0.0.i = select i1 %1, ptr %3, ptr %_12.i, !dbg !2032
  %_0.sroa.5.0.in.in.i = getelementptr inbounds nuw i8, ptr %_30, i64 4, !dbg !2033
  %_0.sroa.5.0.in.i = load i32, ptr %_0.sroa.5.0.in.in.i, align 4, !dbg !2033, !noundef !14
  %_0.sroa.5.0.i = zext i32 %_0.sroa.5.0.in.i to i64, !dbg !2033
  br label %bb23, !dbg !2034

bb26:                                             ; preds = %start, %start
  %4 = getelementptr inbounds nuw i8, ptr %self, i64 8, !dbg !2035
  %5 = load ptr, ptr %4, align 8, !dbg !2035, !noundef !14
  %6 = getelementptr inbounds nuw i8, ptr %self, i64 16, !dbg !2035
  %7 = load i64, ptr %6, align 8, !dbg !2035, !noundef !14
  br label %bb23, !dbg !2035

bb23:                                             ; preds = %bb26, %bb25
  %zs.sroa.11.0 = phi i64 [ %7, %bb26 ], [ %_0.sroa.5.0.i, %bb25 ], !dbg !2036
  %zs.sroa.0.0 = phi ptr [ %5, %bb26 ], [ %_0.sroa.0.0.i, %bb25 ], !dbg !2036
  %8 = icmp eq i64 %zs.sroa.11.0, 0, !dbg !2037
  br i1 %8, label %bb22, label %bb2, !dbg !2037

bb2:                                              ; preds = %bb23
  %_32 = ptrtoint ptr %zs.sroa.0.0 to i64, !dbg !2039
  %9 = icmp sgt ptr %zs.sroa.0.0, inttoptr (i64 -1 to ptr), !dbg !2042
  br i1 %9, label %bb10, label %bb28, !dbg !2042

bb10:                                             ; preds = %bb2
  %_53 = and i64 %_32, 2305843009213693952, !dbg !2043
  %10 = icmp eq i64 %_53, 0, !dbg !2046
  br i1 %10, label %bb48.preheader, label %bb11, !dbg !2046

bb11:                                             ; preds = %bb10
  call void @llvm.lifetime.start.p0(ptr nonnull %_18), !dbg !2047
  %..i = tail call noundef i64 @llvm.umin.i64(i64 %zs.sroa.11.0, i64 4294967295), !dbg !2048
  %_60 = and i64 %_32, 9007199254740991, !dbg !2054
  %_57 = inttoptr i64 %_60 to ptr, !dbg !2054
; call <alloc::string::String>::from_utf8_lossy
  call void @_RNvMNtCskhhhlZ4wWGP_5alloc6stringNtB2_6String15from_utf8_lossy(ptr noalias noundef nonnull sret([24 x i8]) align 8 captures(none) dereferenceable(24) %_18, ptr noalias noundef nonnull readonly captures(address, read_provenance) %_57, i64 noundef %..i) #33, !dbg !2047
  %11 = load i64, ptr %_18, align 8, !dbg !2057, !range !2063, !noundef !14
  %12 = getelementptr inbounds nuw i8, ptr %_18, i64 8, !dbg !2064
  %_68 = load ptr, ptr %12, align 8, !dbg !2064, !nonnull !14
  %13 = getelementptr inbounds nuw i8, ptr %_18, i64 16, !dbg !2064
  %_67 = load i64, ptr %13, align 8, !dbg !2064
; call <core::fmt::Formatter>::write_str
  %14 = tail call noundef zeroext i1 @_RNvMsa_NtCsgXhsEb1m4tm_4core3fmtNtB5_9Formatter9write_str(ptr noalias noundef nonnull align 8 dereferenceable(24) %f, ptr noalias noundef nonnull readonly captures(address, read_provenance) %_68, i64 noundef %_67) #33, !dbg !2065
  %15 = icmp sgt i64 %11, 0, !dbg !2066
  br i1 %15, label %_RNvXs_NtCskhhhlZ4wWGP_5alloc5allocNtB4_6GlobalNtNtCsgXhsEb1m4tm_4core5alloc9Allocator10deallocate.exit.i.i.i.i.i.i, label %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc6borrow3CoweEECs9SN9c7tmF9T_9bun_alloc.exit, !dbg !2066

_RNvXs_NtCskhhhlZ4wWGP_5alloc5allocNtB4_6GlobalNtNtCsgXhsEb1m4tm_4core5alloc9Allocator10deallocate.exit.i.i.i.i.i.i: ; preds = %bb11
; call __rustc::__rust_dealloc
  tail call void @_RNvCs3TqXShXgh4d_7___rustc14___rust_dealloc(ptr noundef nonnull %_68, i64 noundef %11, i64 noundef range(i64 1, -9223372036854775807) 1) #33, !dbg !2069, !noalias !2086
  br label %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc6borrow3CoweEECs9SN9c7tmF9T_9bun_alloc.exit, !dbg !2099

_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc6borrow3CoweEECs9SN9c7tmF9T_9bun_alloc.exit: ; preds = %bb11, %_RNvXs_NtCskhhhlZ4wWGP_5alloc5allocNtB4_6GlobalNtNtCsgXhsEb1m4tm_4core5alloc9Allocator10deallocate.exit.i.i.i.i.i.i
  call void @llvm.lifetime.end.p0(ptr nonnull %_18), !dbg !2100
  br label %bb22, !dbg !2101

bb48.preheader:                                   ; preds = %bb10
  %..i11 = tail call noundef i64 @llvm.umin.i64(i64 %zs.sroa.11.0, i64 4294967295), !dbg !2102
  %_73 = and i64 %_32, 9007199254740991, !dbg !2107
  %_70 = inttoptr i64 %_73 to ptr, !dbg !2107
  %16 = icmp ne i64 %_73, 0, !dbg !2109
  tail call void @llvm.assume(i1 %16), !dbg !2109
  %_80 = getelementptr inbounds nuw i8, ptr %_70, i64 %..i11, !dbg !2123
  br label %bb48, !dbg !2126

bb16:                                             ; preds = %bb48
  %_93 = getelementptr inbounds nuw i8, ptr %iter1.sroa.0.034, i64 1, !dbg !2131
  %_87 = icmp eq ptr %_93, %_80, !dbg !2139
  br i1 %_87, label %bb22, label %bb48, !dbg !2141

bb48:                                             ; preds = %bb48.preheader, %bb16
  %iter1.sroa.0.034 = phi ptr [ %_93, %bb16 ], [ %_70, %bb48.preheader ]
  %b = load i8, ptr %iter1.sroa.0.034, align 1, !dbg !2142, !noundef !14
  %_25 = zext i8 %b to i32, !dbg !2143
; call <core::fmt::Formatter as core::fmt::Write>::write_char
  %_24 = tail call noundef zeroext i1 @_RNvXsb_NtCsgXhsEb1m4tm_4core3fmtNtB5_9FormatterNtB5_5Write10write_char(ptr noalias noundef nonnull align 8 dereferenceable(24) %f, i32 noundef %_25) #33, !dbg !2144
  br i1 %_24, label %bb22, label %bb16, !dbg !2126

bb28:                                             ; preds = %bb2
  %_36 = and i64 %_32, 9007199254740991, !dbg !2145
  %_35 = inttoptr i64 %_36 to ptr, !dbg !2145
  %17 = icmp ne i64 %_36, 0, !dbg !2148
  tail call void @llvm.assume(i1 %17), !dbg !2148
  %_44 = getelementptr inbounds nuw i16, ptr %_35, i64 %zs.sroa.11.0, !dbg !2157
  br label %bb4, !dbg !2160

bb4:                                              ; preds = %25, %bb28
  %iter.sroa.11.0.off0 = phi i1 [ false, %bb28 ], [ %iter.sroa.11.1.ph45, %25 ]
  %iter.sroa.15.0 = phi i16 [ undef, %bb28 ], [ %iter.sroa.15.1.ph47, %25 ]
  %iter.sroa.0.0 = phi ptr [ %_35, %bb28 ], [ %iter.sroa.0.2.ph49, %25 ], !dbg !2162
  br i1 %iter.sroa.11.0.off0, label %bb5.i, label %bb2.i12, !dbg !2163

bb2.i12:                                          ; preds = %bb4
  %18 = icmp ne ptr %iter.sroa.0.0, null
  tail call void @llvm.assume(i1 %18)
  %_6.i.i.i = icmp eq ptr %iter.sroa.0.0, %_44, !dbg !2170
  br i1 %_6.i.i.i, label %bb22, label %bb22.i, !dbg !2179

bb22.i:                                           ; preds = %bb2.i12
  %_16.i.i.i = getelementptr inbounds nuw i8, ptr %iter.sroa.0.0, i64 2, !dbg !2180
  %v.i.i = load i16, ptr %iter.sroa.0.0, align 2, !dbg !2183, !noalias !2186, !noundef !14
  br label %bb5.i, !dbg !2191

bb5.i:                                            ; preds = %bb22.i, %bb4
  %iter.sroa.0.1 = phi ptr [ %iter.sroa.0.0, %bb4 ], [ %_16.i.i.i, %bb22.i ], !dbg !2162
  %u.sroa.0.0.i = phi i16 [ %iter.sroa.15.0, %bb4 ], [ %v.i.i, %bb22.i ], !dbg !2192
  %19 = and i16 %u.sroa.0.0.i, -2048, !dbg !2193
  %or.cond.i = icmp eq i16 %19, -10240, !dbg !2193
  br i1 %or.cond.i, label %bb6.i, label %bb7.i, !dbg !2193

bb7.i:                                            ; preds = %bb5.i
  %_11.sroa.4.4.insert.ext.i = zext i16 %u.sroa.0.0.i to i64, !dbg !2200
  br label %bb7, !dbg !2201

bb6.i:                                            ; preds = %bb5.i
  %_14.i = icmp samesign ugt i16 %u.sroa.0.0.i, -9217, !dbg !2202
  br i1 %_14.i, label %25, label %bb9.i, !dbg !2202

bb9.i:                                            ; preds = %bb6.i
  %20 = icmp ne ptr %iter.sroa.0.1, null
  tail call void @llvm.assume(i1 %20)
  %_6.i.i25.i = icmp eq ptr %iter.sroa.0.1, %_44, !dbg !2203
  br i1 %_6.i.i25.i, label %25, label %bb12.i, !dbg !2207

bb12.i:                                           ; preds = %bb9.i
  %_16.i.i27.i = getelementptr inbounds nuw i8, ptr %iter.sroa.0.1, i64 2, !dbg !2208
  %v.i28.i = load i16, ptr %iter.sroa.0.1, align 2, !dbg !2210, !noalias !2212, !noundef !14
  %21 = add i16 %v.i28.i, 8192, !dbg !2215
  %or.cond3.i = icmp ult i16 %21, -1024, !dbg !2215
  br i1 %or.cond3.i, label %25, label %bb14.i, !dbg !2215

bb14.i:                                           ; preds = %bb12.i
  %_32.i = and i16 %u.sroa.0.0.i, 1023, !dbg !2217
  %_31.i = zext nneg i16 %_32.i to i64, !dbg !2218
  %_34.i = and i16 %v.i28.i, 1023, !dbg !2219
  %_33.i = zext nneg i16 %_34.i to i64, !dbg !2219
  %22 = shl nuw nsw i64 %_31.i, 26, !dbg !2220
  %c.i = add nuw nsw i64 %22, 4294967296, !dbg !2220
  %23 = lshr exact i64 %c.i, 16, !dbg !2222
  %24 = or disjoint i64 %23, %_33.i, !dbg !2222
  br label %bb7, !dbg !2223

bb7:                                              ; preds = %bb14.i, %bb7.i
  %iter.sroa.0.2.ph = phi ptr [ %iter.sroa.0.1, %bb7.i ], [ %_16.i.i27.i, %bb14.i ]
  %_0.sroa.7.sroa.0.0.i.ph = phi i64 [ %_11.sroa.4.4.insert.ext.i, %bb7.i ], [ %24, %bb14.i ]
  %.sroa.5.0.extract.trunc24 = trunc nuw nsw i64 %_0.sroa.7.sroa.0.0.i.ph to i32, !dbg !2222
  br label %25, !dbg !2224

25:                                               ; preds = %bb12.i, %bb6.i, %bb9.i, %bb7
  %iter.sroa.0.2.ph49 = phi ptr [ %iter.sroa.0.2.ph, %bb7 ], [ %_16.i.i27.i, %bb12.i ], [ %iter.sroa.0.1, %bb6.i ], [ %_44, %bb9.i ]
  %iter.sroa.15.1.ph47 = phi i16 [ %iter.sroa.15.0, %bb7 ], [ %v.i28.i, %bb12.i ], [ %iter.sroa.15.0, %bb6.i ], [ %iter.sroa.15.0, %bb9.i ]
  %iter.sroa.11.1.ph45 = phi i1 [ false, %bb7 ], [ true, %bb12.i ], [ false, %bb6.i ], [ false, %bb9.i ]
  %26 = phi i32 [ %.sroa.5.0.extract.trunc24, %bb7 ], [ 65533, %bb12.i ], [ 65533, %bb6.i ], [ 65533, %bb9.i ], !dbg !2224
; call <core::fmt::Formatter as core::fmt::Write>::write_char
  %_14 = tail call noundef zeroext i1 @_RNvXsb_NtCsgXhsEb1m4tm_4core3fmtNtB5_9FormatterNtB5_5Write10write_char(ptr noalias noundef nonnull align 8 dereferenceable(24) %f, i32 noundef %26) #33, !dbg !2229
  br i1 %_14, label %bb22, label %bb4, !dbg !2230

bb22:                                             ; preds = %bb2.i12, %25, %bb48, %bb16, %start, %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc6borrow3CoweEECs9SN9c7tmF9T_9bun_alloc.exit, %bb23
  %_0.sroa.0.2.off0 = phi i1 [ %14, %_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc6borrow3CoweEECs9SN9c7tmF9T_9bun_alloc.exit ], [ true, %bb48 ], [ false, %bb23 ], [ false, %start ], [ false, %bb16 ], [ true, %25 ], [ false, %bb2.i12 ]
  ret i1 %_0.sroa.0.2.off0, !dbg !2232
}

; <&[u8] as bun_alloc::BSSAppendable>::copy_into
; Function Attrs: nounwind
define void @_RNvXss_Cs9SN9c7tmF9T_9bun_allocRShNtB5_13BSSAppendable9copy_into(ptr noalias noundef readonly align 8 captures(none) dereferenceable(16) %self, ptr noalias noundef nonnull writeonly captures(none) %dst.0, i64 noundef range(i64 0, -9223372036854775808) %dst.1) unnamed_addr #1 !dbg !2233 {
start:
  %0 = getelementptr inbounds nuw i8, ptr %self, i64 8, !dbg !2235
  %_6.1 = load i64, ptr %0, align 8, !dbg !2235, !noundef !14
  %_8.not = icmp ugt i64 %_6.1, %dst.1
  br i1 %_8.not, label %bb3, label %bb1, !dbg !2236, !prof !394

bb1:                                              ; preds = %start
  %_7.0 = load ptr, ptr %self, align 8, !dbg !2245, !nonnull !14, !noundef !14
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %dst.0, ptr nonnull readonly align 1 %_7.0, i64 range(i64 0, -9223372036854775808) %_6.1, i1 false), !dbg !2246, !alias.scope !2251, !noalias !2255
  ret void, !dbg !2257

bb3:                                              ; preds = %start
; call core::slice::index::slice_index_fail
  tail call void @_RNvNtNtCsgXhsEb1m4tm_4core5slice5index16slice_index_fail(i64 noundef 0, i64 noundef %_6.1, i64 noundef %dst.1, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_7389700e92edf4cfbbbb3ad1262599b9) #35, !dbg !2258
  unreachable, !dbg !2258
}

; <&[&[u8]] as bun_alloc::BSSAppendable>::copy_into
; Function Attrs: nounwind
define void @_RNvXsu_Cs9SN9c7tmF9T_9bun_allocRSRShNtB5_13BSSAppendable9copy_into(ptr noalias noundef readonly align 8 captures(none) dereferenceable(16) %self, ptr noalias noundef nonnull writeonly captures(none) %0, i64 noundef range(i64 0, -9223372036854775808) %1) unnamed_addr #1 !dbg !2259 {
start:
  %_4.0 = load ptr, ptr %self, align 8, !dbg !2261, !nonnull !14, !align !164, !noundef !14
  %2 = getelementptr inbounds nuw i8, ptr %self, i64 8, !dbg !2261
  %_4.1 = load i64, ptr %2, align 8, !dbg !2261, !noundef !14
  %_19.idx = shl nuw nsw i64 %_4.1, 4, !dbg !2263
  %_19 = getelementptr inbounds nuw i8, ptr %_4.0, i64 %_19.idx, !dbg !2263
  %_264 = icmp eq i64 %_4.1, 0, !dbg !2273
  br i1 %_264, label %bb2, label %bb3, !dbg !2275

bb3:                                              ; preds = %start, %bb11
  %dst.sroa.0.07 = phi ptr [ %_49, %bb11 ], [ %0, %start ]
  %dst.sroa.5.06 = phi i64 [ %_45, %bb11 ], [ %1, %start ]
  %iter.sroa.0.05 = phi ptr [ %_32, %bb11 ], [ %_4.0, %start ]
  %3 = getelementptr inbounds nuw i8, ptr %iter.sroa.0.05, i64 8, !dbg !2282
  %_12.1 = load i64, ptr %3, align 8, !dbg !2282, !noundef !14
  %_34.not = icmp ugt i64 %_12.1, %dst.sroa.5.06
  br i1 %_34.not, label %bb6, label %bb11, !dbg !2284, !prof !394

bb2:                                              ; preds = %bb11, %start
  ret void, !dbg !2293

bb6:                                              ; preds = %bb3
; call core::slice::index::slice_index_fail
  tail call void @_RNvNtNtCsgXhsEb1m4tm_4core5slice5index16slice_index_fail(i64 noundef 0, i64 noundef %_12.1, i64 noundef %dst.sroa.5.06, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_6e8c82fb888968a428c64f4952af931d) #35, !dbg !2294
  unreachable, !dbg !2294

bb11:                                             ; preds = %bb3
  %_32 = getelementptr inbounds nuw i8, ptr %iter.sroa.0.05, i64 16, !dbg !2295
  %_13.0 = load ptr, ptr %iter.sroa.0.05, align 8, !dbg !2298, !nonnull !14, !noundef !14
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %dst.sroa.0.07, ptr nonnull readonly align 1 %_13.0, i64 range(i64 0, -9223372036854775808) %_12.1, i1 false), !dbg !2299, !alias.scope !2304, !noalias !2308
  %_45 = sub nuw nsw i64 %dst.sroa.5.06, %_12.1, !dbg !2310
  %_49 = getelementptr inbounds nuw i8, ptr %dst.sroa.0.07, i64 %_12.1, !dbg !2316
  %_26 = icmp eq ptr %_32, %_19, !dbg !2273
  br i1 %_26, label %bb2, label %bb3, !dbg !2275
}

; <&[&[u8]] as bun_alloc::BSSAppendable>::total_len
; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none)
define noundef i64 @_RNvXsu_Cs9SN9c7tmF9T_9bun_allocRSRShNtB5_13BSSAppendable9total_len(ptr noalias noundef readonly align 8 captures(none) dereferenceable(16) %self) unnamed_addr #11 personality ptr @rust_eh_personality !dbg !2321 {
start:
  %_3.0 = load ptr, ptr %self, align 8, !dbg !2322, !nonnull !14, !align !164, !noundef !14
  %0 = getelementptr inbounds nuw i8, ptr %self, i64 8, !dbg !2322
  %_3.1 = load i64, ptr %0, align 8, !dbg !2322, !noundef !14
  %1 = icmp eq i64 %_3.1, 0, !dbg !2323
  br i1 %1, label %_RINvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB7_4IterRShENtNtNtNtBb_4iter6traits8iterator8Iterator4foldjNCINvNtNtB10_8adapters3map8map_foldRBQ_jjNCNvXsu_Cs9SN9c7tmF9T_9bun_allocRSBQ_NtB2s_13BSSAppendable9total_len0NCINvXsK_NtBY_5accumjNtB3A_3Sum3sumINtB1K_3MapBF_B2k_EE0E0EB2s_.exit, label %bb8.i, !dbg !2342

bb8.i:                                            ; preds = %start, %bb8.i
  %i.sroa.0.0.i = phi i64 [ %_27.i, %bb8.i ], [ 0, %start ], !dbg !2343
  %acc.sroa.0.0.i = phi i64 [ %_4.0.i.i.i, %bb8.i ], [ 0, %start ], !dbg !2345
  %_45.i = getelementptr inbounds nuw { ptr, i64 }, ptr %_3.0, i64 %i.sroa.0.0.i, !dbg !2346
  %2 = getelementptr inbounds nuw i8, ptr %_45.i, i64 8, !dbg !2351
  %_3.1.i.i.i = load i64, ptr %2, align 8, !dbg !2351, !alias.scope !2358, !noundef !14
  %_4.0.i.i.i = add i64 %_3.1.i.i.i, %acc.sroa.0.0.i, !dbg !2363
  %_27.i = add nuw i64 %i.sroa.0.0.i, 1, !dbg !2367
  %_28.i = icmp eq i64 %_27.i, %_3.1, !dbg !2370
  br i1 %_28.i, label %_RINvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB7_4IterRShENtNtNtNtBb_4iter6traits8iterator8Iterator4foldjNCINvNtNtB10_8adapters3map8map_foldRBQ_jjNCNvXsu_Cs9SN9c7tmF9T_9bun_allocRSBQ_NtB2s_13BSSAppendable9total_len0NCINvXsK_NtBY_5accumjNtB3A_3Sum3sumINtB1K_3MapBF_B2k_EE0E0EB2s_.exit, label %bb8.i, !dbg !2370

_RINvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB7_4IterRShENtNtNtNtBb_4iter6traits8iterator8Iterator4foldjNCINvNtNtB10_8adapters3map8map_foldRBQ_jjNCNvXsu_Cs9SN9c7tmF9T_9bun_allocRSBQ_NtB2s_13BSSAppendable9total_len0NCINvXsK_NtBY_5accumjNtB3A_3Sum3sumINtB1K_3MapBF_B2k_EE0E0EB2s_.exit: ; preds = %bb8.i, %start
  %_0.sroa.0.0.i = phi i64 [ 0, %start ], [ %_4.0.i.i.i, %bb8.i ], !dbg !2345
  ret i64 %_0.sroa.0.0.i, !dbg !2371
}

; <<bun_alloc::AllocatorVTable>::NO_REMAP::{closure#0} as core::ops::function::FnOnce<(*mut core::ffi::c_void, &mut [u8], bun_alloc::Alignment, usize, usize)>>::call_once
; Function Attrs: inlinehint mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define internal noalias noundef ptr @_RNvYNCNvMs_Cs9SN9c7tmF9T_9bun_allocNtB9_15AllocatorVTable8NO_REMAP0INtNtNtCsgXhsEb1m4tm_4core3ops8function6FnOnceTONtNtB1a_3ffi6c_voidQShNtB9_9AlignmentjjEE9call_onceB9_(ptr readnone captures(none) %0, ptr noalias nonnull readnone captures(none) %1, i64 range(i64 0, -9223372036854775808) %2, i8 %3, i64 %4, i64 %5) unnamed_addr #12 !dbg !2372 {
start:
  ret ptr null, !dbg !2373
}

; <<bun_alloc::AllocatorVTable>::NO_RESIZE::{closure#0} as core::ops::function::FnOnce<(*mut core::ffi::c_void, &mut [u8], bun_alloc::Alignment, usize, usize)>>::call_once
; Function Attrs: inlinehint mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define internal noundef zeroext i1 @_RNvYNCNvMs_Cs9SN9c7tmF9T_9bun_allocNtB9_15AllocatorVTable9NO_RESIZE0INtNtNtCsgXhsEb1m4tm_4core3ops8function6FnOnceTONtNtB1b_3ffi6c_voidQShNtB9_9AlignmentjjEE9call_onceB9_(ptr readnone captures(none) %0, ptr noalias nonnull readnone captures(none) %1, i64 range(i64 0, -9223372036854775808) %2, i8 %3, i64 %4, i64 %5) unnamed_addr #12 !dbg !2374 {
start:
  ret i1 false, !dbg !2375
}

; <bun_alloc::SliceCursor as core::fmt::Write>::write_char
; Function Attrs: nounwind
define internal noundef zeroext i1 @_RNvYNtCs9SN9c7tmF9T_9bun_alloc11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write10write_charB4_(ptr noalias noundef align 8 captures(none) dereferenceable(24) %self, i32 noundef range(i32 0, 1114112) %c) unnamed_addr #1 !dbg !2376 {
start:
  %_6.sroa.0 = alloca i32, align 4
  call void @llvm.lifetime.start.p0(ptr nonnull %_6.sroa.0), !dbg !2380
  store i32 0, ptr %_6.sroa.0, align 4, !dbg !2380
  %_11.i = icmp samesign ult i32 %c, 128, !dbg !2381
  br i1 %_11.i, label %bb13.i.i, label %bb5.i, !dbg !2381

bb5.i:                                            ; preds = %start
  %_12.i = icmp samesign ult i32 %c, 2048, !dbg !2391
  %0 = trunc i32 %c to i8, !dbg !2392
  %_5.i.i = and i8 %0, 63, !dbg !2392
  %last1.i.i = or disjoint i8 %_5.i.i, -128, !dbg !2392
  %_10.i.i = lshr i32 %c, 6, !dbg !2397
  %1 = trunc i32 %_10.i.i to i8, !dbg !2399
  %_8.i.i = and i8 %1, 63, !dbg !2399
  %last2.i.i = or disjoint i8 %_8.i.i, -128, !dbg !2399
  %_14.i.i = lshr i32 %c, 12, !dbg !2400
  %2 = trunc i32 %_14.i.i to i8, !dbg !2402
  %_12.i.i = and i8 %2, 63, !dbg !2402
  %last3.i.i = or disjoint i8 %_12.i.i, -128, !dbg !2402
  %_18.i.i = lshr i32 %c, 18, !dbg !2403
  %_16.i.i = trunc nuw nsw i32 %_18.i.i to i8, !dbg !2405
  %last4.i.i = or disjoint i8 %_16.i.i, -16, !dbg !2405
  br i1 %_12.i, label %bb1.i.i, label %bb2.i.i, !dbg !2406

bb13.i.i:                                         ; preds = %start
  %3 = trunc nuw nsw i32 %c to i8, !dbg !2408
  store i8 %3, ptr %_6.sroa.0, align 4, !dbg !2408, !alias.scope !2409
  br label %_RNvNtNtCsgXhsEb1m4tm_4core4char7methods15encode_utf8_raw.exit, !dbg !2412

bb1.i.i:                                          ; preds = %bb5.i
  %4 = or disjoint i8 %1, -64, !dbg !2414
  store i8 %4, ptr %_6.sroa.0, align 4, !dbg !2414, !alias.scope !2409
  %_6.sroa.0.1._20.i.i.sroa_idx3 = getelementptr inbounds nuw i8, ptr %_6.sroa.0, i64 1, !dbg !2415
  store i8 %last1.i.i, ptr %_6.sroa.0.1._20.i.i.sroa_idx3, align 1, !dbg !2415, !alias.scope !2409
  br label %_RNvNtNtCsgXhsEb1m4tm_4core4char7methods15encode_utf8_raw.exit, !dbg !2416

bb2.i.i:                                          ; preds = %bb5.i
  %_13.i = icmp samesign ult i32 %c, 65536, !dbg !2391
  br i1 %_13.i, label %bb3.i.i, label %bb4.i.i, !dbg !2418

bb3.i.i:                                          ; preds = %bb2.i.i
  %5 = or disjoint i8 %2, -32, !dbg !2419
  store i8 %5, ptr %_6.sroa.0, align 4, !dbg !2419, !alias.scope !2409
  %_6.sroa.0.1._21.i.i.sroa_idx2 = getelementptr inbounds nuw i8, ptr %_6.sroa.0, i64 1, !dbg !2420
  store i8 %last2.i.i, ptr %_6.sroa.0.1._21.i.i.sroa_idx2, align 1, !dbg !2420, !alias.scope !2409
  %_6.sroa.0.2._22.i.i.sroa_idx5 = getelementptr inbounds nuw i8, ptr %_6.sroa.0, i64 2, !dbg !2421
  store i8 %last1.i.i, ptr %_6.sroa.0.2._22.i.i.sroa_idx5, align 2, !dbg !2421, !alias.scope !2409
  br label %_RNvNtNtCsgXhsEb1m4tm_4core4char7methods15encode_utf8_raw.exit, !dbg !2416

bb4.i.i:                                          ; preds = %bb2.i.i
  store i8 %last4.i.i, ptr %_6.sroa.0, align 4, !dbg !2422, !alias.scope !2409
  %_6.sroa.0.1._23.i.i.sroa_idx1 = getelementptr inbounds nuw i8, ptr %_6.sroa.0, i64 1, !dbg !2423
  store i8 %last3.i.i, ptr %_6.sroa.0.1._23.i.i.sroa_idx1, align 1, !dbg !2423, !alias.scope !2409
  %_6.sroa.0.2._24.i.i.sroa_idx4 = getelementptr inbounds nuw i8, ptr %_6.sroa.0, i64 2, !dbg !2424
  store i8 %last2.i.i, ptr %_6.sroa.0.2._24.i.i.sroa_idx4, align 2, !dbg !2424, !alias.scope !2409
  %_6.sroa.0.3._25.i.i.sroa_idx6 = getelementptr inbounds nuw i8, ptr %_6.sroa.0, i64 3, !dbg !2425
  store i8 %last1.i.i, ptr %_6.sroa.0.3._25.i.i.sroa_idx6, align 1, !dbg !2425, !alias.scope !2409
  br label %_RNvNtNtCsgXhsEb1m4tm_4core4char7methods15encode_utf8_raw.exit, !dbg !2426

_RNvNtNtCsgXhsEb1m4tm_4core4char7methods15encode_utf8_raw.exit: ; preds = %bb13.i.i, %bb1.i.i, %bb3.i.i, %bb4.i.i
  %len.sroa.0.04.i = phi i64 [ 1, %bb13.i.i ], [ 2, %bb1.i.i ], [ 3, %bb3.i.i ], [ 4, %bb4.i.i ]
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2427), !dbg !2430
  %6 = getelementptr inbounds nuw i8, ptr %self, i64 16, !dbg !2431
  %_5.i = load i64, ptr %6, align 8, !dbg !2431, !alias.scope !2427, !noalias !2433, !noundef !14
  %end.i = add i64 %_5.i, %len.sroa.0.04.i, !dbg !2431
  %7 = getelementptr inbounds nuw i8, ptr %self, i64 8, !dbg !2435
  %_12.1.i = load i64, ptr %7, align 8, !dbg !2435, !alias.scope !2427, !noalias !2433, !noundef !14
  %_7.i = icmp ugt i64 %end.i, %_12.1.i, !dbg !2436
  br i1 %_7.i, label %_RNvXs6_Cs9SN9c7tmF9T_9bun_allocNtB5_11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_str.exit, label %bb2.i, !dbg !2436

bb2.i:                                            ; preds = %_RNvNtNtCsgXhsEb1m4tm_4core4char7methods15encode_utf8_raw.exit
  %_20.i = icmp ult i64 %end.i, %_5.i, !dbg !2437
  br i1 %_20.i, label %bb6.i, label %bb4.i, !dbg !2437, !prof !394

bb4.i:                                            ; preds = %bb2.i
  %_13.0.i = load ptr, ptr %self, align 8, !dbg !2441, !alias.scope !2427, !noalias !2433, !nonnull !14, !noundef !14
  %_23.i = getelementptr inbounds nuw i8, ptr %_13.0.i, i64 %_5.i, !dbg !2442
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(1) %_23.i, ptr noundef nonnull readonly align 4 dereferenceable(1) %_6.sroa.0, i64 range(i64 0, -9223372036854775808) %len.sroa.0.04.i, i1 false), !dbg !2444, !alias.scope !2448, !noalias !2452
  store i64 %end.i, ptr %6, align 8, !dbg !2454, !alias.scope !2427, !noalias !2433
  br label %_RNvXs6_Cs9SN9c7tmF9T_9bun_allocNtB5_11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_str.exit, !dbg !2455

bb6.i:                                            ; preds = %bb2.i
; call core::slice::index::slice_index_fail
  tail call void @_RNvNtNtCsgXhsEb1m4tm_4core5slice5index16slice_index_fail(i64 noundef %_5.i, i64 noundef %end.i, i64 noundef %_12.1.i, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_fc8cfb579032aab044b502c62a1fa507) #35, !dbg !2456, !noalias !2457
  unreachable, !dbg !2456

_RNvXs6_Cs9SN9c7tmF9T_9bun_allocNtB5_11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_str.exit: ; preds = %_RNvNtNtCsgXhsEb1m4tm_4core4char7methods15encode_utf8_raw.exit, %bb4.i
  call void @llvm.lifetime.end.p0(ptr nonnull %_6.sroa.0), !dbg !2458
  ret i1 %_7.i, !dbg !2459
}

; <bun_alloc::SliceCursor as core::fmt::Write>::write_fmt
; Function Attrs: nounwind
define internal noundef zeroext i1 @_RNvYNtCs9SN9c7tmF9T_9bun_alloc11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_fmtB4_(ptr noalias noundef align 8 dereferenceable(24) %self, ptr noundef nonnull %args.0, ptr noundef nonnull %args.1) unnamed_addr #1 !dbg !2460 {
start:
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2461), !dbg !2464
  %bits.i.i = ptrtoint ptr %args.1 to i64, !dbg !2465
  %_7.i.i = and i64 %bits.i.i, 1, !dbg !2476
  %.not.i.i = icmp ne i64 %_7.i.i, 0, !dbg !2476
  %len.i.i = lshr i64 %bits.i.i, 1, !dbg !2476
  %0 = tail call i1 @llvm.is.constant.i1(i1 %.not.i.i), !dbg !2478
  %1 = and i1 %.not.i.i, %0, !dbg !2478
  br i1 %1, label %bb2.i, label %bb4.i, !dbg !2480

bb2.i:                                            ; preds = %start
  tail call void @llvm.experimental.noalias.scope.decl(metadata !2481), !dbg !2484
  %2 = getelementptr inbounds nuw i8, ptr %self, i64 16, !dbg !2485
  %_5.i.i = load i64, ptr %2, align 8, !dbg !2485, !alias.scope !2487, !noalias !2488, !noundef !14
  %end.i.i = add i64 %_5.i.i, %len.i.i, !dbg !2485
  %3 = getelementptr inbounds nuw i8, ptr %self, i64 8, !dbg !2490
  %_12.1.i.i = load i64, ptr %3, align 8, !dbg !2490, !alias.scope !2487, !noalias !2488, !noundef !14
  %_7.i2.i = icmp ugt i64 %end.i.i, %_12.1.i.i, !dbg !2491
  br i1 %_7.i2.i, label %_RNvXs_NvNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_fmtQNtCs9SN9c7tmF9T_9bun_alloc11SliceCursorNtB4_12SpecWriteFmt14spec_write_fmtBQ_.exit, label %bb2.i.i, !dbg !2491

bb2.i.i:                                          ; preds = %bb2.i
  %_20.i.i = icmp ult i64 %end.i.i, %_5.i.i, !dbg !2492
  br i1 %_20.i.i, label %bb6.i.i, label %bb4.i.i, !dbg !2492, !prof !394

bb4.i.i:                                          ; preds = %bb2.i.i
  %_13.0.i.i = load ptr, ptr %self, align 8, !dbg !2496, !alias.scope !2487, !noalias !2488, !nonnull !14, !noundef !14
  %_23.i.i = getelementptr inbounds nuw i8, ptr %_13.0.i.i, i64 %_5.i.i, !dbg !2497
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %_23.i.i, ptr nonnull readonly align 1 %args.0, i64 range(i64 0, -9223372036854775808) %len.i.i, i1 false), !dbg !2499, !alias.scope !2503, !noalias !2507
  store i64 %end.i.i, ptr %2, align 8, !dbg !2509, !alias.scope !2487, !noalias !2488
  br label %_RNvXs_NvNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_fmtQNtCs9SN9c7tmF9T_9bun_alloc11SliceCursorNtB4_12SpecWriteFmt14spec_write_fmtBQ_.exit, !dbg !2510

bb6.i.i:                                          ; preds = %bb2.i.i
; call core::slice::index::slice_index_fail
  tail call void @_RNvNtNtCsgXhsEb1m4tm_4core5slice5index16slice_index_fail(i64 noundef %_5.i.i, i64 noundef %end.i.i, i64 noundef %_12.1.i.i, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_fc8cfb579032aab044b502c62a1fa507) #35, !dbg !2511, !noalias !2512
  unreachable, !dbg !2511

bb4.i:                                            ; preds = %start
; call core::fmt::write
  %4 = tail call noundef zeroext i1 @_RNvNtCsgXhsEb1m4tm_4core3fmt5write(ptr noundef nonnull align 8 dereferenceable(24) %self, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(48) @vtable.1, ptr noundef nonnull %args.0, ptr noundef nonnull %args.1) #33, !dbg !2513
  br label %_RNvXs_NvNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_fmtQNtCs9SN9c7tmF9T_9bun_alloc11SliceCursorNtB4_12SpecWriteFmt14spec_write_fmtBQ_.exit, !dbg !2514

_RNvXs_NvNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_fmtQNtCs9SN9c7tmF9T_9bun_alloc11SliceCursorNtB4_12SpecWriteFmt14spec_write_fmtBQ_.exit: ; preds = %bb2.i, %bb4.i.i, %bb4.i
  %_0.sroa.0.0.in.i = phi i1 [ %4, %bb4.i ], [ true, %bb2.i ], [ false, %bb4.i.i ]
  ret i1 %_0.sroa.0.0.in.i, !dbg !2515
}

; Function Attrs: nounwind
declare noundef range(i32 0, 10) i32 @rust_eh_personality(i32 noundef, i32 noundef, i64 noundef, ptr noundef, ptr noundef) unnamed_addr #1

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(ptr captures(none)) #13

; Function Attrs: mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias writeonly captures(none), ptr noalias readonly captures(none), i64, i1 immarg) #14

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(ptr captures(none)) #13

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(inaccessiblemem: write)
declare void @llvm.assume(i1 noundef) #15

; core::fmt::write
; Function Attrs: nounwind
declare noundef zeroext i1 @_RNvNtCsgXhsEb1m4tm_4core3fmt5write(ptr noundef nonnull, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(48), ptr noundef nonnull, ptr noundef nonnull) unnamed_addr #1

; core::panicking::panic_fmt
; Function Attrs: cold noinline noreturn nounwind
declare void @_RNvNtCsgXhsEb1m4tm_4core9panicking9panic_fmt(ptr noundef nonnull, ptr noundef nonnull, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24)) unnamed_addr #2

; <std::sys::pal::unix::sync::mutex::Mutex as core::ops::drop::Drop>::drop
; Function Attrs: nounwind
declare void @_RNvXs2_NtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutexNtB5_5MutexNtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4drop(ptr noundef nonnull align 8) unnamed_addr #1

; core::panicking::panic
; Function Attrs: cold noinline noreturn nounwind
declare void @_RNvNtCsgXhsEb1m4tm_4core9panicking5panic(ptr noalias noundef nonnull readonly captures(address, read_provenance), i64 noundef, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24)) unnamed_addr #2

; alloc::raw_vec::handle_error
; Function Attrs: cold minsize noreturn nounwind optsize
declare void @_RNvNtCskhhhlZ4wWGP_5alloc7raw_vec12handle_error(i64 noundef range(i64 0, -9223372036854775807), i64) unnamed_addr #16

; Function Attrs: mustprogress nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare nonnull ptr @llvm.threadlocal.address.p0(ptr nonnull) #17

; <std::sys::pal::unix::sync::mutex::Mutex>::init
; Function Attrs: nounwind
declare void @_RNvMNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutexNtB2_5Mutex4init(ptr noundef nonnull align 8) unnamed_addr #1

; Function Attrs: mustprogress nocallback nofree nounwind willreturn memory(argmem: read)
declare i32 @memcmp(ptr captures(none), ptr captures(none), i64) local_unnamed_addr #18

; Function Attrs: nounwind
declare noundef ptr @mi_realloc(ptr noundef, i64 noundef) unnamed_addr #1

; Function Attrs: noreturn nounwind
declare void @__bun_crash_handler_out_of_memory() unnamed_addr #19

; Function Attrs: nounwind
declare noundef ptr @mmap(ptr noundef, i64 noundef, i32 noundef, i32 noundef, i32 noundef, i64 noundef) unnamed_addr #1

; core::slice::index::slice_index_fail
; Function Attrs: cold noinline noreturn nounwind
declare void @_RNvNtNtCsgXhsEb1m4tm_4core5slice5index16slice_index_fail(i64 noundef, i64 noundef, i64 noundef, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24)) unnamed_addr #2

; core::panicking::panic_bounds_check
; Function Attrs: cold minsize noinline noreturn nounwind optsize
declare void @_RNvNtCsgXhsEb1m4tm_4core9panicking18panic_bounds_check(i64 noundef, i64 noundef, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24)) unnamed_addr #20

; Function Attrs: mustprogress nocallback nofree nounwind willreturn memory(argmem: read)
declare noundef i64 @strlen(ptr noundef captures(none)) unnamed_addr #21

; Function Attrs: mustprogress nocallback nofree nounwind willreturn memory(argmem: write)
declare void @llvm.memset.p0.i64(ptr writeonly captures(none), i8, i64, i1 immarg) #22

; Function Attrs: nounwind
declare void @mi_free(ptr noundef) unnamed_addr #1

; Function Attrs: nounwind
declare noundef ptr @mi_malloc(i64 noundef) unnamed_addr #1

; Function Attrs: nounwind
declare noundef ptr @mi_malloc_aligned(i64 noundef, i64 noundef) unnamed_addr #1

; Function Attrs: nounwind
declare noundef ptr @mi_realloc_aligned(ptr noundef, i64 noundef, i64 noundef) unnamed_addr #1

; Function Attrs: nounwind
declare noundef ptr @mi_expand(ptr noundef, i64 noundef) unnamed_addr #1

; __rustc::__rust_dealloc
; Function Attrs: nounwind allockind("free")
declare void @_RNvCs3TqXShXgh4d_7___rustc14___rust_dealloc(ptr allocptr noundef nonnull captures(address), i64 noundef, i64 noundef range(i64 1, -9223372036854775807)) unnamed_addr #23

; __rustc::__rust_realloc
; Function Attrs: nounwind allockind("realloc,aligned") allocsize(3)
declare noalias noundef ptr @_RNvCs3TqXShXgh4d_7___rustc14___rust_realloc(ptr allocptr noundef nonnull, i64 noundef, i64 allocalign noundef range(i64 1, -9223372036854775807), i64 noundef) unnamed_addr #24

; __rustc::__rust_no_alloc_shim_is_unstable_v2
; Function Attrs: nounwind
declare void @_RNvCs3TqXShXgh4d_7___rustc35___rust_no_alloc_shim_is_unstable_v2() unnamed_addr #1

; __rustc::__rust_alloc
; Function Attrs: nounwind allockind("alloc,uninitialized,aligned") allocsize(0)
declare noalias noundef ptr @_RNvCs3TqXShXgh4d_7___rustc12___rust_alloc(i64 noundef, i64 allocalign noundef range(i64 1, -9223372036854775807)) unnamed_addr #25

; std::panicking::panic_count::is_zero_slow_path
; Function Attrs: cold noinline nounwind
declare noundef zeroext i1 @_RNvNtNtCsg1bLsEOY8ZL_3std9panicking11panic_count17is_zero_slow_path() unnamed_addr #4

; std::sys::thread_local::destructors::list::register
; Function Attrs: nounwind
declare void @_RNvNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local11destructors4list8register(ptr noundef, ptr noundef nonnull) unnamed_addr #1

; Function Attrs: nounwind
declare noundef ptr @malloc_zone_memalign(ptr noundef nonnull, i64 noundef, i64 noundef) unnamed_addr #1

; Function Attrs: nounwind
declare noundef ptr @malloc_create_zone(i64 noundef, i32 noundef) unnamed_addr #1

; Function Attrs: nounwind
declare void @malloc_set_zone_name(ptr noundef, ptr noundef) unnamed_addr #1

; Function Attrs: nounwind
declare noundef zeroext i1 @mi_heap_visit_blocks(ptr noundef, i1 noundef zeroext, ptr noundef, ptr noundef) unnamed_addr #1

; Function Attrs: nounwind
declare void @mi_heap_destroy(ptr noundef) unnamed_addr #1

; Function Attrs: nounwind
declare noundef ptr @mi_heap_new() unnamed_addr #1

; Function Attrs: convergent mustprogress nocallback nofree nosync nounwind willreturn memory(none)
declare i1 @llvm.is.constant.i1(i1) #26

; Function Attrs: mustprogress nocallback  nofree nosync nounwind speculatable willreturn memory(none)
declare { i64, i1 } @llvm.umul.with.overflow.i64(i64, i64) #27

; <std::sys::pal::unix::sync::mutex::Mutex>::lock
; Function Attrs: nounwind
declare void @_RNvMNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutexNtB2_5Mutex4lock(ptr noundef nonnull align 8) unnamed_addr #1

; Function Attrs: nounwind
declare noundef ptr @mi_zalloc(i64 noundef) unnamed_addr #1

; Function Attrs: nounwind
declare noundef ptr @mi_zalloc_aligned(i64 noundef, i64 noundef) unnamed_addr #1

; Function Attrs: nounwind
declare noundef i64 @mi_usable_size(ptr noundef) unnamed_addr #1

; Function Attrs: mustprogress nounwind willreturn allockind("free") memory(argmem: readwrite, inaccessiblemem: readwrite)
declare void @free(ptr allocptr noundef captures(none)) unnamed_addr #28

; Function Attrs: mustprogress nofree nounwind willreturn allockind("alloc,uninitialized,aligned") allocsize(1) memory(inaccessiblemem: readwrite)
declare noalias noundef ptr @aligned_alloc(i64 allocalign noundef, i64 noundef) unnamed_addr #29

; Function Attrs: mustprogress nofree nounwind willreturn allockind("alloc,uninitialized") allocsize(0) memory(inaccessiblemem: readwrite)
declare noalias noundef ptr @malloc(i64 noundef) unnamed_addr #30

; Function Attrs: nounwind
declare noundef i64 @malloc_size(ptr noundef) unnamed_addr #1

; Function Attrs: nounwind
declare noundef ptr @mi_heap_malloc(ptr noundef, i64 noundef) unnamed_addr #1

; Function Attrs: nounwind
declare noundef ptr @mi_heap_malloc_aligned(ptr noundef, i64 noundef, i64 noundef) unnamed_addr #1

; Function Attrs: nounwind
declare noundef ptr @mi_heap_realloc_aligned(ptr noundef, ptr noundef, i64 noundef, i64 noundef) unnamed_addr #1

; Function Attrs: nounwind
declare void @Bun__WTFStringImpl__destroy(ptr noundef) unnamed_addr #1

; alloc::alloc::handle_alloc_error
; Function Attrs: cold minsize noreturn nounwind optsize
declare void @_RNvNtCskhhhlZ4wWGP_5alloc5alloc18handle_alloc_error(i64 noundef range(i64 1, -9223372036854775807), i64 noundef) unnamed_addr #16

; <std::sys::pal::unix::sync::mutex::Mutex>::unlock
; Function Attrs: nounwind
declare void @_RNvMNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutexNtB2_5Mutex6unlock(ptr noundef nonnull align 8) unnamed_addr #1

; <core::fmt::Formatter as core::fmt::Write>::write_char
; Function Attrs: nounwind
declare noundef zeroext i1 @_RNvXsb_NtCsgXhsEb1m4tm_4core3fmtNtB5_9FormatterNtB5_5Write10write_char(ptr noalias noundef align 8 dereferenceable(24), i32 noundef range(i32 0, 1114112)) unnamed_addr #1

; <alloc::string::String>::from_utf8_lossy
; Function Attrs: nounwind
declare void @_RNvMNtCskhhhlZ4wWGP_5alloc6stringNtB2_6String15from_utf8_lossy(ptr dead_on_unwind noalias noundef writable sret([24 x i8]) align 8 captures(none) dereferenceable(24), ptr noalias noundef nonnull readonly captures(address, read_provenance), i64 noundef range(i64 0, -9223372036854775808)) unnamed_addr #1

; <core::fmt::Formatter>::write_str
; Function Attrs: nounwind
declare noundef zeroext i1 @_RNvMsa_NtCsgXhsEb1m4tm_4core3fmtNtB5_9Formatter9write_str(ptr noalias noundef align 8 dereferenceable(24), ptr noalias noundef nonnull readonly captures(address, read_provenance), i64 noundef) unnamed_addr #1

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(inaccessiblemem: readwrite)
declare void @llvm.experimental.noalias.scope.decl(metadata) #31

; Function Attrs: nocallback  nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.umax.i64(i64, i64) #32

; Function Attrs: nocallback  nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.umin.i64(i64, i64) #32

attributes #0 = { cold nounwind "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #1 = { nounwind "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #2 = { cold noinline noreturn nounwind "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #3 = { cold noreturn nounwind "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #4 = { cold noinline nounwind "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #5 = { mustprogress nounwind willreturn memory(argmem: readwrite, inaccessiblemem: readwrite) "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #6 = { mustprogress nofree nounwind willreturn memory(write, inaccessiblemem: readwrite) "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #7 = { nofree norecurse nounwind memory(read, inaccessiblemem: write) "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #8 = { mustprogress nofree norecurse nounwind willreturn memory(argmem: readwrite) "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #9 = { mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: readwrite) "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #10 = { inlinehint nounwind "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #11 = { nofree norecurse nosync nounwind memory(read, inaccessiblemem: none) "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #12 = { inlinehint mustprogress nofree norecurse nosync nounwind willreturn memory(none) "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #13 = { mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #14 = { mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #15 = { mustprogress nocallback nofree nosync nounwind willreturn memory(inaccessiblemem: write) }
attributes #16 = { cold minsize noreturn nounwind optsize "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #17 = { mustprogress nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #18 = { mustprogress nocallback nofree nounwind willreturn memory(argmem: read) }
attributes #19 = { noreturn nounwind "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #20 = { cold minsize noinline noreturn nounwind optsize "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #21 = { mustprogress nocallback nofree nounwind willreturn memory(argmem: read) "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #22 = { mustprogress nocallback nofree nounwind willreturn memory(argmem: write) }
attributes #23 = { nounwind allockind("free") "alloc-family"="__rust_alloc" "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #24 = { nounwind allockind("realloc,aligned") allocsize(3) "alloc-family"="__rust_alloc" "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #25 = { nounwind allockind("alloc,uninitialized,aligned") allocsize(0) "alloc-family"="__rust_alloc" "alloc-variant-zeroed"="_RNvCs3TqXShXgh4d_7___rustc19___rust_alloc_zeroed" "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #26 = { convergent mustprogress nocallback nofree nosync nounwind willreturn memory(none) }
attributes #27 = { mustprogress nocallback  nofree nosync nounwind speculatable willreturn memory(none) }
attributes #28 = { mustprogress nounwind willreturn allockind("free") memory(argmem: readwrite, inaccessiblemem: readwrite) "alloc-family"="malloc" "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #29 = { mustprogress nofree nounwind willreturn allockind("alloc,uninitialized,aligned") allocsize(1) memory(inaccessiblemem: readwrite) "alloc-family"="malloc" "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #30 = { mustprogress nofree nounwind willreturn allockind("alloc,uninitialized") allocsize(0) memory(inaccessiblemem: readwrite) "alloc-family"="malloc" "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #31 = { nocallback nofree nosync nounwind willreturn memory(inaccessiblemem: readwrite) }
attributes #32 = { nocallback  nofree nosync nounwind speculatable willreturn memory(none) }
attributes #33 = { nounwind }
attributes #34 = { noreturn nounwind }
attributes #35 = { noinline noreturn nounwind }
attributes #36 = { noinline nounwind }
attributes #37 = { inlinehint nounwind }

!llvm.module.flags = !{!0, !1, !2}
!llvm.ident = !{!3}
!llvm.dbg.cu = !{!4}

!0 = !{i32 8, !"PIC Level", i32 2}
!1 = !{i32 7, !"Dwarf Version", i32 4}
!2 = !{i32 2, !"Debug Info Version", i32 3}
!3 = !{!"rustc version 1.97.0-nightly (e95e73209 2026-05-05)"}
!4 = distinct !DICompileUnit(language: DW_LANG_Rust, file: !5, producer: "clang LLVM (rustc version 1.97.0-nightly (e95e73209 2026-05-05))", isOptimized: true, runtimeVersion: 0, emissionKind: LineTablesOnly, splitDebugInlining: false, nameTableKind: None)
!5 = !DIFile(filename: "src/bun_alloc/lib.rs/@/bun_alloc.731f47d3fe31a7cb-cgu.0", directory: "/Users/scc/code/researcher/bun")
!6 = distinct !DISubprogram(name: "initialize<std::sys::pal::unix::sync::mutex::Mutex, std::sys::sync::mutex::pthread::{impl#0}::get::{closure_env#0}>", linkageName: "_RINvMNtNtNtCsg1bLsEOY8ZL_3std3sys4sync8once_boxINtB3_7OnceBoxNtNtNtNtNtB7_3pal4unix4sync5mutex5MutexE10initializeNCNvMNtNtB5_5mutex7pthreadNtB1S_5Mutex3get0ECs9SN9c7tmF9T_9bun_alloc", scope: !8, file: !7, line: 62, type: !13, scopeLine: 62, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!7 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/std/src/sys/sync/once_box.rs", directory: "", checksumkind: CSK_MD5, checksum: "f1000a4c21cf79dde92428b81bc214bf")
!8 = !DINamespace(name: "OnceBox", scope: !9)
!9 = !DINamespace(name: "once_box", scope: !10)
!10 = !DINamespace(name: "sync", scope: !11)
!11 = !DINamespace(name: "sys", scope: !12)
!12 = !DINamespace(name: "std", scope: null)
!13 = !DISubroutineType(cc: DW_CC_nocall, types: !14)
!14 = !{}
!15 = !DILocation(line: 99, column: 9, scope: !16, inlinedAt: !21)
!16 = distinct !DISubprogram(name: "alloc", linkageName: "_RNvNtCskhhhlZ4wWGP_5alloc5alloc5alloc", scope: !18, file: !17, line: 95, type: !20, scopeLine: 95, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!17 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/alloc/src/alloc.rs", directory: "", checksumkind: CSK_MD5, checksum: "860ce4ea2346d0773913a27b0b87ad79")
!18 = !DINamespace(name: "alloc", scope: !19)
!19 = !DINamespace(name: "alloc", scope: null)
!20 = !DISubroutineType(types: !14)
!21 = distinct !DILocation(line: 210, column: 73, scope: !22, inlinedAt: !25)
!22 = distinct !DILexicalBlock(scope: !23, file: !17, line: 209, column: 13)
!23 = distinct !DISubprogram(name: "alloc_impl_runtime", linkageName: "_RNvMNtCskhhhlZ4wWGP_5alloc5allocNtB2_6Global18alloc_impl_runtime", scope: !24, file: !17, line: 205, type: !20, scopeLine: 205, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!24 = !DINamespace(name: "Global", scope: !18)
!25 = distinct !DILocation(line: 332, column: 9, scope: !26, inlinedAt: !27)
!26 = distinct !DISubprogram(name: "alloc_impl", linkageName: "_RNvMNtCskhhhlZ4wWGP_5alloc5allocNtB2_6Global10alloc_impl", scope: !24, file: !17, line: 331, type: !20, scopeLine: 331, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!27 = distinct !DILocation(line: 449, column: 14, scope: !28, inlinedAt: !30)
!28 = distinct !DISubprogram(name: "allocate", linkageName: "_RNvXs_NtCskhhhlZ4wWGP_5alloc5allocNtB4_6GlobalNtNtCsgXhsEb1m4tm_4core5alloc9Allocator8allocate", scope: !29, file: !17, line: 448, type: !20, scopeLine: 448, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!29 = !DINamespace(name: "{impl#1}", scope: !18)
!30 = distinct !DILocation(line: 248, column: 18, scope: !31, inlinedAt: !34)
!31 = distinct !DISubprogram(name: "box_new_uninit", linkageName: "_RNvNtCskhhhlZ4wWGP_5alloc5boxed14box_new_uninit", scope: !33, file: !32, line: 247, type: !20, scopeLine: 247, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!32 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/alloc/src/boxed.rs", directory: "", checksumkind: CSK_MD5, checksum: "ab3110edd6f8ce3cea8572ce2a6872f1")
!33 = !DINamespace(name: "boxed", scope: !19)
!34 = distinct !DILocation(line: 286, column: 19, scope: !35, inlinedAt: !37)
!35 = distinct !DISubprogram(name: "new<std::sys::pal::unix::sync::mutex::Mutex>", linkageName: "_RNvMNtCskhhhlZ4wWGP_5alloc5boxedINtB2_3BoxNtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexE3newCs9SN9c7tmF9T_9bun_alloc", scope: !36, file: !32, line: 284, type: !20, scopeLine: 284, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!36 = !DINamespace(name: "{impl#0}", scope: !33)
!37 = distinct !DILocation(line: 356, column: 9, scope: !38, inlinedAt: !39)
!38 = distinct !DISubprogram(name: "pin<std::sys::pal::unix::sync::mutex::Mutex>", linkageName: "_RNvMNtCskhhhlZ4wWGP_5alloc5boxedINtB2_3BoxNtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexE3pinCs9SN9c7tmF9T_9bun_alloc", scope: !36, file: !32, line: 355, type: !20, scopeLine: 355, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!39 = distinct !DILocation(line: 23, column: 27, scope: !40, inlinedAt: !46)
!40 = distinct !DISubprogram(name: "{closure#0}", linkageName: "_RNCNvMNtNtNtNtCsg1bLsEOY8ZL_3std3sys4sync5mutex7pthreadNtB4_5Mutex3get0Cs9SN9c7tmF9T_9bun_alloc", scope: !42, file: !41, line: 22, type: !20, scopeLine: 22, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!41 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/std/src/sys/sync/mutex/pthread.rs", directory: "", checksumkind: CSK_MD5, checksum: "868c5ca80a36ed03df9b889476107b5b")
!42 = !DINamespace(name: "get", scope: !43)
!43 = !DINamespace(name: "{impl#0}", scope: !44)
!44 = !DINamespace(name: "pthread", scope: !45)
!45 = !DINamespace(name: "mutex", scope: !10)
!46 = distinct !DILocation(line: 63, column: 72, scope: !6)
!47 = !{!48}
!48 = distinct !{!48, !49, !"_RNvMNtCskhhhlZ4wWGP_5alloc5boxedINtB2_3BoxNtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexE3newCs9SN9c7tmF9T_9bun_alloc: %x"}
!49 = distinct !{!49, !"_RNvMNtCskhhhlZ4wWGP_5alloc5boxedINtB2_3BoxNtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexE3newCs9SN9c7tmF9T_9bun_alloc"}
!50 = !DILocation(line: 101, column: 9, scope: !16, inlinedAt: !21)
!51 = !DILocation(line: 248, column: 11, scope: !31, inlinedAt: !34)
!52 = !DILocation(line: 248, column: 5, scope: !31, inlinedAt: !34)
!53 = !{!"branch_weights", !"expected", i32 1, i32 2000}
!54 = !DILocation(line: 250, column: 19, scope: !31, inlinedAt: !34)
!55 = !DILocation(line: 289, column: 56, scope: !56, inlinedAt: !37)
!56 = distinct !DILexicalBlock(scope: !35, file: !32, line: 286, column: 9)
!57 = !DILocation(line: 25, column: 35, scope: !58, inlinedAt: !46)
!58 = distinct !DILexicalBlock(scope: !40, file: !41, line: 23, column: 13)
!59 = !DILocation(line: 4001, column: 17, scope: !60, inlinedAt: !65)
!60 = distinct !DISubprogram(name: "atomic_compare_exchange<*mut std::sys::pal::unix::sync::mutex::Mutex>", linkageName: "_RINvNtNtCsgXhsEb1m4tm_4core4sync6atomic23atomic_compare_exchangeONtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexECs9SN9c7tmF9T_9bun_alloc", scope: !62, file: !61, line: 3969, type: !20, scopeLine: 3969, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!61 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/sync/atomic.rs", directory: "", checksumkind: CSK_MD5, checksum: "0fa055d022a09bf85eb4fa0bc0114101")
!62 = !DINamespace(name: "atomic", scope: !63)
!63 = !DINamespace(name: "sync", scope: !64)
!64 = !DINamespace(name: "core", scope: null)
!65 = distinct !DILocation(line: 1920, column: 18, scope: !66, inlinedAt: !68)
!66 = distinct !DISubprogram(name: "compare_exchange<std::sys::pal::unix::sync::mutex::Mutex>", linkageName: "_RNvMs3_NtNtCsgXhsEb1m4tm_4core4sync6atomicINtB5_6AtomicONtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexE16compare_exchangeCs9SN9c7tmF9T_9bun_alloc", scope: !67, file: !61, line: 1912, type: !20, scopeLine: 1912, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!67 = !DINamespace(name: "Atomic", scope: !62)
!68 = !DILocation(line: 64, column: 24, scope: !69)
!69 = distinct !DILexicalBlock(scope: !6, file: !7, line: 63, column: 9)
!70 = !DILocation(line: 64, column: 9, scope: !69)
!71 = !DILocation(line: 809, column: 1, scope: !72, inlinedAt: !75)
!72 = distinct !DISubprogram(name: "drop_in_place<std::sys::pal::unix::sync::mutex::Mutex>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 809, type: !20, scopeLine: 809, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!73 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/ptr/mod.rs", directory: "", checksumkind: CSK_MD5, checksum: "7bf23f23215823f9e375734a49f116af")
!74 = !DINamespace(name: "ptr", scope: !64)
!75 = distinct !DILocation(line: 809, column: 1, scope: !76, inlinedAt: !77)
!76 = distinct !DISubprogram(name: "drop_in_place<alloc::boxed::Box<std::sys::pal::unix::sync::mutex::Mutex, alloc::alloc::Global>>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexEECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 809, type: !20, scopeLine: 809, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!77 = distinct !DILocation(line: 1004, column: 1, scope: !78, inlinedAt: !81)
!78 = distinct !DISubprogram(name: "drop<alloc::boxed::Box<std::sys::pal::unix::sync::mutex::Mutex, alloc::alloc::Global>>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3mem4dropINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexEECs9SN9c7tmF9T_9bun_alloc", scope: !80, file: !79, line: 1000, type: !20, scopeLine: 1000, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!79 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/mem/mod.rs", directory: "", checksumkind: CSK_MD5, checksum: "2440f5bd5e1c52b57f9da57d3a52f836")
!80 = !DINamespace(name: "mem", scope: !64)
!81 = !DILocation(line: 69, column: 17, scope: !82)
!82 = distinct !DILexicalBlock(scope: !69, file: !7, line: 66, column: 13)
!83 = !{!84}
!84 = distinct !{!84, !85, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexEECs9SN9c7tmF9T_9bun_alloc: %_1"}
!85 = distinct !{!85, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexEECs9SN9c7tmF9T_9bun_alloc"}
!86 = !DILocation(line: 128, column: 14, scope: !87, inlinedAt: !88)
!87 = distinct !DISubprogram(name: "dealloc_nonnull", linkageName: "_RNvNtCskhhhlZ4wWGP_5alloc5alloc15dealloc_nonnull", scope: !18, file: !17, line: 127, type: !20, scopeLine: 127, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!88 = distinct !DILocation(line: 229, column: 22, scope: !89, inlinedAt: !90)
!89 = distinct !DISubprogram(name: "deallocate_impl_runtime", linkageName: "_RNvMNtCskhhhlZ4wWGP_5alloc5allocNtB2_6Global23deallocate_impl_runtime", scope: !24, file: !17, line: 219, type: !20, scopeLine: 219, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!90 = distinct !DILocation(line: 344, column: 9, scope: !91, inlinedAt: !92)
!91 = distinct !DISubprogram(name: "deallocate_impl", linkageName: "_RNvMNtCskhhhlZ4wWGP_5alloc5allocNtB2_6Global15deallocate_impl", scope: !24, file: !17, line: 343, type: !20, scopeLine: 343, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!92 = distinct !DILocation(line: 462, column: 23, scope: !93, inlinedAt: !94)
!93 = distinct !DISubprogram(name: "deallocate", linkageName: "_RNvXs_NtCskhhhlZ4wWGP_5alloc5allocNtB4_6GlobalNtNtCsgXhsEb1m4tm_4core5alloc9Allocator10deallocate", scope: !29, file: !17, line: 460, type: !20, scopeLine: 460, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!94 = distinct !DILocation(line: 1956, column: 24, scope: !95, inlinedAt: !99)
!95 = distinct !DILexicalBlock(scope: !96, file: !32, line: 1954, column: 13)
!96 = distinct !DILexicalBlock(scope: !97, file: !32, line: 1951, column: 9)
!97 = distinct !DISubprogram(name: "drop<std::sys::pal::unix::sync::mutex::Mutex, alloc::alloc::Global>", linkageName: "_RNvXs8_NtCskhhhlZ4wWGP_5alloc5boxedINtB5_3BoxNtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexENtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4dropCs9SN9c7tmF9T_9bun_alloc", scope: !98, file: !32, line: 1948, type: !20, scopeLine: 1948, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!98 = !DINamespace(name: "{impl#10}", scope: !33)
!99 = distinct !DILocation(line: 809, column: 1, scope: !76, inlinedAt: !77)
!100 = !{!101, !84}
!101 = distinct !{!101, !102, !"_RNvXs8_NtCskhhhlZ4wWGP_5alloc5boxedINtB5_3BoxNtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexENtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4dropCs9SN9c7tmF9T_9bun_alloc: %self"}
!102 = distinct !{!102, !"_RNvXs8_NtCskhhhlZ4wWGP_5alloc5boxedINtB5_3BoxNtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexENtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4dropCs9SN9c7tmF9T_9bun_alloc"}
!103 = !DILocation(line: 71, column: 13, scope: !69)
!104 = !DILocation(line: 1348, column: 9, scope: !105, inlinedAt: !109)
!105 = distinct !DISubprogram(name: "new_unchecked<&std::sys::pal::unix::sync::mutex::Mutex>", linkageName: "_RNvMs4_NtCsgXhsEb1m4tm_4core3pinINtB5_3PinRNtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexE13new_uncheckedCs9SN9c7tmF9T_9bun_alloc", scope: !107, file: !106, line: 1347, type: !20, scopeLine: 1347, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!106 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/pin.rs", directory: "", checksumkind: CSK_MD5, checksum: "a8b0c75971593b410de0603fd0db00b1")
!107 = !DINamespace(name: "Pin", scope: !108)
!108 = !DINamespace(name: "pin", scope: !64)
!109 = !DILocation(line: 0, scope: !69)
!110 = !DILocation(line: 73, column: 6, scope: !6)
!111 = distinct !DISubprogram(name: "destroy<core::cell::Cell<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>>", linkageName: "_RINvNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eager7destroyINtNtCsgXhsEb1m4tm_4core4cell4CellINtNtB1a_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEEB2D_", scope: !113, file: !112, line: 64, type: !20, scopeLine: 64, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!112 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/std/src/sys/thread_local/native/eager.rs", directory: "", checksumkind: CSK_MD5, checksum: "7edd4c75e397a002b0742eaf008dd7d6")
!113 = !DINamespace(name: "eager", scope: !114)
!114 = !DINamespace(name: "native", scope: !115)
!115 = !DINamespace(name: "thread_local", scope: !11)
!116 = !DILocation(line: 2447, column: 9, scope: !117, inlinedAt: !121)
!117 = distinct !DISubprogram(name: "get<std::sys::thread_local::native::eager::State>", linkageName: "_RNvMsX_NtCsgXhsEb1m4tm_4core4cellINtB5_10UnsafeCellNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eager5StateE3getCs9SN9c7tmF9T_9bun_alloc", scope: !119, file: !118, line: 2443, type: !20, scopeLine: 2443, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!118 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/cell.rs", directory: "", checksumkind: CSK_MD5, checksum: "3b26dc07b7a3365bdb6c33c2b1762988")
!119 = !DINamespace(name: "UnsafeCell", scope: !120)
!120 = !DINamespace(name: "cell", scope: !64)
!121 = distinct !DILocation(line: 513, column: 48, scope: !122, inlinedAt: !124)
!122 = distinct !DISubprogram(name: "replace<std::sys::thread_local::native::eager::State>", linkageName: "_RNvMs7_NtCsgXhsEb1m4tm_4core4cellINtB5_4CellNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eager5StateE7replaceCs9SN9c7tmF9T_9bun_alloc", scope: !123, file: !118, line: 510, type: !20, scopeLine: 510, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!123 = !DINamespace(name: "Cell", scope: !120)
!124 = distinct !DILocation(line: 437, column: 14, scope: !125, inlinedAt: !126)
!125 = distinct !DISubprogram(name: "set<std::sys::thread_local::native::eager::State>", linkageName: "_RNvMs7_NtCsgXhsEb1m4tm_4core4cellINtB5_4CellNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eager5StateE3setCs9SN9c7tmF9T_9bun_alloc", scope: !123, file: !118, line: 433, type: !20, scopeLine: 433, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!126 = distinct !DILocation(line: 70, column: 23, scope: !127, inlinedAt: !130)
!127 = distinct !DILexicalBlock(scope: !128, file: !112, line: 67, column: 9)
!128 = distinct !DISubprogram(name: "{closure#0}<core::cell::Cell<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>>", linkageName: "_RNCINvNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eager7destroyINtNtCsgXhsEb1m4tm_4core4cell4CellINtNtB1c_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEE0B2F_", scope: !129, file: !112, line: 66, type: !20, scopeLine: 66, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!129 = !DINamespace(name: "destroy", scope: !113)
!130 = distinct !DILocation(line: 210, column: 5, scope: !131, inlinedAt: !134)
!131 = distinct !DILexicalBlock(scope: !133, file: !132, line: 209, column: 5)
!132 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/std/src/sys/thread_local/mod.rs", directory: "", checksumkind: CSK_MD5, checksum: "ac77ac405526f4acf270b490680fc271")
!133 = distinct !DISubprogram(name: "abort_on_dtor_unwind<std::sys::thread_local::native::eager::destroy::{closure_env#0}<core::cell::Cell<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>>>", linkageName: "_RINvNtNtCsg1bLsEOY8ZL_3std3sys12thread_local20abort_on_dtor_unwindNCINvNtNtB2_6native5eager7destroyINtNtCsgXhsEb1m4tm_4core4cell4CellINtNtB1E_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEE0EB37_", scope: !115, file: !132, line: 207, type: !20, scopeLine: 207, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!134 = distinct !DILocation(line: 66, column: 5, scope: !111)
!135 = !DILocation(line: 931, column: 49, scope: !136, inlinedAt: !138)
!136 = distinct !DILexicalBlock(scope: !137, file: !79, line: 930, column: 9)
!137 = distinct !DISubprogram(name: "replace<std::sys::thread_local::native::eager::State>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3mem7replaceNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eager5StateECs9SN9c7tmF9T_9bun_alloc", scope: !80, file: !79, line: 916, type: !20, scopeLine: 916, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!138 = distinct !DILocation(line: 513, column: 9, scope: !122, inlinedAt: !124)
!139 = !{!140, !142}
!140 = distinct !{!140, !141, !"_RNCINvNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eager7destroyINtNtCsgXhsEb1m4tm_4core4cell4CellINtNtB1c_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEE0B2F_: %_1"}
!141 = distinct !{!141, !"_RNCINvNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eager7destroyINtNtCsgXhsEb1m4tm_4core4cell4CellINtNtB1c_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEE0B2F_"}
!142 = distinct !{!142, !143, !"_RINvNtNtCsg1bLsEOY8ZL_3std3sys12thread_local20abort_on_dtor_unwindNCINvNtNtB2_6native5eager7destroyINtNtCsgXhsEb1m4tm_4core4cell4CellINtNtB1E_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEE0EB37_: %f"}
!143 = distinct !{!143, !"_RINvNtNtCsg1bLsEOY8ZL_3std3sys12thread_local20abort_on_dtor_unwindNCINvNtNtB2_6native5eager7destroyINtNtCsgXhsEb1m4tm_4core4cell4CellINtNtB1E_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEE0EB37_"}
!144 = !{!145}
!145 = distinct !{!145, !146, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtB4_4cell4CellINtNtB4_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEEB1X_: %_1"}
!146 = distinct !{!146, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtB4_4cell4CellINtNtB4_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEEB1X_"}
!147 = !DILocation(line: 72, column: 13, scope: !127, inlinedAt: !130)
!148 = !{!149}
!149 = distinct !{!149, !150, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtB4_4cell10UnsafeCellINtNtB4_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEEB24_: %_1"}
!150 = distinct !{!150, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtB4_4cell10UnsafeCellINtNtB4_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEEB24_"}
!151 = !DILocation(line: 809, column: 1, scope: !152, inlinedAt: !153)
!152 = distinct !DISubprogram(name: "drop_in_place<core::cell::Cell<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtB4_4cell4CellINtNtB4_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEEB1X_", scope: !74, file: !73, line: 809, type: !20, scopeLine: 809, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!153 = distinct !DILocation(line: 72, column: 13, scope: !127, inlinedAt: !130)
!154 = !{!155}
!155 = distinct !{!155, !156, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtB4_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEB1F_: %_1"}
!156 = distinct !{!156, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtB4_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEB1F_"}
!157 = !DILocation(line: 809, column: 1, scope: !158, inlinedAt: !159)
!158 = distinct !DISubprogram(name: "drop_in_place<core::cell::UnsafeCell<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtB4_4cell10UnsafeCellINtNtB4_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEEB24_", scope: !74, file: !73, line: 809, type: !20, scopeLine: 809, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!159 = distinct !DILocation(line: 809, column: 1, scope: !152, inlinedAt: !153)
!160 = !DILocation(line: 809, column: 1, scope: !161, inlinedAt: !162)
!161 = distinct !DISubprogram(name: "drop_in_place<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtB4_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEB1F_", scope: !74, file: !73, line: 809, type: !20, scopeLine: 809, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!162 = distinct !DILocation(line: 809, column: 1, scope: !158, inlinedAt: !159)
!163 = !{!155, !149, !145}
!164 = !{i64 8}
!165 = !{!166}
!166 = distinct !{!166, !167, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEBK_: %_1"}
!167 = distinct !{!167, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEBK_"}
!168 = !DILocation(line: 809, column: 1, scope: !169, inlinedAt: !170)
!169 = distinct !DISubprogram(name: "drop_in_place<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEB1j_", scope: !74, file: !73, line: 809, type: !20, scopeLine: 809, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!170 = distinct !DILocation(line: 809, column: 1, scope: !161, inlinedAt: !162)
!171 = !DILocation(line: 809, column: 1, scope: !172, inlinedAt: !173)
!172 = distinct !DISubprogram(name: "drop_in_place<bun_alloc::ast_alloc::AstAllocState>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEBK_", scope: !74, file: !73, line: 809, type: !20, scopeLine: 809, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!173 = distinct !DILocation(line: 809, column: 1, scope: !169, inlinedAt: !170)
!174 = !{!175}
!175 = distinct !{!175, !176, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtB4_6option6OptionNtNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena13MimallocArenaEEB16_: %_1"}
!176 = distinct !{!176, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtB4_6option6OptionNtNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena13MimallocArenaEEB16_"}
!177 = !DILocation(line: 809, column: 1, scope: !178, inlinedAt: !179)
!178 = distinct !DISubprogram(name: "drop_in_place<core::option::Option<bun_alloc::mimalloc_arena::MimallocArena>>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtB4_6option6OptionNtNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena13MimallocArenaEEB16_", scope: !74, file: !73, line: 809, type: !20, scopeLine: 809, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!179 = distinct !DILocation(line: 809, column: 1, scope: !172, inlinedAt: !173)
!180 = !{i8 0, i8 3}
!181 = !{!175, !166}
!182 = !{!183, !155, !149, !145, !140, !142}
!183 = distinct !{!183, !184, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEB1j_: %_1"}
!184 = distinct !{!184, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEB1j_"}
!185 = !{!186}
!186 = distinct !{!186, !187, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena13MimallocArenaEBK_: %_1"}
!187 = distinct !{!187, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena13MimallocArenaEBK_"}
!188 = !{!189}
!189 = distinct !{!189, !190, !"_RNvXs2_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB5_13MimallocArenaNtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4drop: %self"}
!190 = distinct !{!190, !"_RNvXs2_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB5_13MimallocArenaNtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4drop"}
!191 = !DILocation(line: 809, column: 1, scope: !192, inlinedAt: !193)
!192 = distinct !DISubprogram(name: "drop_in_place<bun_alloc::mimalloc_arena::MimallocArena>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena13MimallocArenaEBK_", scope: !74, file: !73, line: 809, type: !20, scopeLine: 809, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!193 = distinct !DILocation(line: 809, column: 1, scope: !178, inlinedAt: !179)
!194 = !DILocation(line: 564, column: 13, scope: !195, inlinedAt: !200)
!195 = distinct !DISubprogram(name: "drop", linkageName: "_RNvXs2_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB5_13MimallocArenaNtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4drop", scope: !197, file: !196, line: 563, type: !20, scopeLine: 563, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!196 = !DIFile(filename: "src/bun_alloc/MimallocArena.rs", directory: "/Users/scc/code/researcher/bun", checksumkind: CSK_MD5, checksum: "334c82c12226650e052f76745647378b")
!197 = !DINamespace(name: "{impl#4}", scope: !198)
!198 = !DINamespace(name: "mimalloc_arena", scope: !199)
!199 = !DINamespace(name: "bun_alloc", scope: null)
!200 = distinct !DILocation(line: 809, column: 1, scope: !192, inlinedAt: !193)
!201 = !DILocation(line: 199, column: 9, scope: !202, inlinedAt: !204)
!202 = distinct !DISubprogram(name: "heap_ptr", linkageName: "_RNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB5_13MimallocArena8heap_ptr", scope: !203, file: !196, line: 198, type: !20, scopeLine: 198, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!203 = !DINamespace(name: "MimallocArena", scope: !198)
!204 = distinct !DILocation(line: 575, column: 49, scope: !195, inlinedAt: !200)
!205 = !{!189, !186, !175, !166}
!206 = !DILocation(line: 575, column: 18, scope: !195, inlinedAt: !200)
!207 = !{!189, !186, !175, !166, !183, !155, !149, !145, !140, !142}
!208 = !DILocation(line: 576, column: 6, scope: !195, inlinedAt: !200)
!209 = !DILocation(line: 128, column: 14, scope: !87, inlinedAt: !210)
!210 = distinct !DILocation(line: 229, column: 22, scope: !89, inlinedAt: !211)
!211 = distinct !DILocation(line: 344, column: 9, scope: !91, inlinedAt: !212)
!212 = distinct !DILocation(line: 462, column: 23, scope: !93, inlinedAt: !213)
!213 = distinct !DILocation(line: 1956, column: 24, scope: !214, inlinedAt: !217)
!214 = distinct !DILexicalBlock(scope: !215, file: !32, line: 1954, column: 13)
!215 = distinct !DILexicalBlock(scope: !216, file: !32, line: 1951, column: 9)
!216 = distinct !DISubprogram(name: "drop<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>", linkageName: "_RNvXs8_NtCskhhhlZ4wWGP_5alloc5boxedINtB5_3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateENtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4dropBL_", scope: !98, file: !32, line: 1948, type: !20, scopeLine: 1948, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!217 = distinct !DILocation(line: 809, column: 1, scope: !169, inlinedAt: !170)
!218 = !{!219, !183, !155, !149, !145, !140, !142}
!219 = distinct !{!219, !220, !"_RNvXs8_NtCskhhhlZ4wWGP_5alloc5boxedINtB5_3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateENtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4dropBL_: %self"}
!220 = distinct !{!220, !"_RNvXs8_NtCskhhhlZ4wWGP_5alloc5boxedINtB5_3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateENtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4dropBL_"}
!221 = !DILocation(line: 75, column: 2, scope: !111)
!222 = distinct !DISubprogram(name: "realloc_raw", linkageName: "_RNvCs9SN9c7tmF9T_9bun_alloc11realloc_raw", scope: !199, file: !223, line: 898, type: !20, scopeLine: 898, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!223 = !DIFile(filename: "src/bun_alloc/lib.rs", directory: "/Users/scc/code/researcher/bun", checksumkind: CSK_MD5, checksum: "398d95f08dec4f9d9e9f436ebf1d61ab")
!224 = !DILocation(line: 903, column: 28, scope: !222)
!225 = !DILocation(line: 904, column: 8, scope: !226)
!226 = distinct !DILexicalBlock(scope: !222, file: !223, line: 903, column: 5)
!227 = !DILocation(line: 908, column: 2, scope: !222)
!228 = distinct !DISubprogram(name: "default_dupe", linkageName: "_RNvCs9SN9c7tmF9T_9bun_alloc12default_dupe", scope: !199, file: !223, line: 1676, type: !20, scopeLine: 1676, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!229 = !DILocation(line: 1677, column: 8, scope: !228)
!230 = !DILocation(line: 515, column: 9, scope: !231, inlinedAt: !235)
!231 = distinct !DISubprogram(name: "mi_malloc_auto_align", linkageName: "_RNvNtCsguFFgRZA9Ru_16bun_mimalloc_sys8mimalloc20mi_malloc_auto_align", scope: !233, file: !232, line: 511, type: !20, scopeLine: 511, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!232 = !DIFile(filename: "src/mimalloc_sys/mimalloc.rs", directory: "/Users/scc/code/researcher/bun", checksumkind: CSK_MD5, checksum: "4a2fd558122f353e5321cf01f9ee08ea")
!233 = !DINamespace(name: "mimalloc", scope: !234)
!234 = !DINamespace(name: "bun_mimalloc_sys", scope: null)
!235 = distinct !DILocation(line: 456, column: 9, scope: !236, inlinedAt: !238)
!236 = distinct !DISubprogram(name: "malloc_aligned", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc13default_alloc14malloc_aligned", scope: !237, file: !223, line: 455, type: !20, scopeLine: 455, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!237 = !DINamespace(name: "default_alloc", scope: !199)
!238 = distinct !DILocation(line: 44, column: 32, scope: !239, inlinedAt: !243)
!239 = distinct !DISubprogram(name: "aligned_alloc", linkageName: "_RNvMNtCs9SN9c7tmF9T_9bun_alloc5basicNtB2_17MimallocAllocator13aligned_alloc", scope: !241, file: !240, line: 43, type: !20, scopeLine: 43, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!240 = !DIFile(filename: "src/bun_alloc/basic.rs", directory: "/Users/scc/code/researcher/bun", checksumkind: CSK_MD5, checksum: "e6a4b63b849830093e4a08aaea61161d")
!241 = !DINamespace(name: "MimallocAllocator", scope: !242)
!242 = !DINamespace(name: "basic", scope: !199)
!243 = distinct !DILocation(line: 69, column: 9, scope: !244, inlinedAt: !245)
!244 = distinct !DISubprogram(name: "alloc_with_default_allocator", linkageName: "_RNvMNtCs9SN9c7tmF9T_9bun_alloc5basicNtB2_17MimallocAllocator28alloc_with_default_allocator", scope: !241, file: !240, line: 63, type: !20, scopeLine: 63, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!245 = distinct !DILocation(line: 145, column: 26, scope: !246, inlinedAt: !248)
!246 = distinct !DISubprogram(name: "raw_alloc", linkageName: "_RNvMs3_Cs9SN9c7tmF9T_9bun_allocNtB5_12StdAllocator9raw_alloc", scope: !247, file: !223, line: 143, type: !20, scopeLine: 143, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!247 = !DINamespace(name: "StdAllocator", scope: !199)
!248 = !DILocation(line: 1681, column: 10, scope: !228)
!249 = !DILocation(line: 146, column: 12, scope: !250, inlinedAt: !248)
!250 = distinct !DILexicalBlock(scope: !246, file: !223, line: 145, column: 9)
!251 = !DILocation(line: 0, scope: !228)
!252 = !DILocation(line: 1691, column: 2, scope: !228)
!253 = !DILocation(line: 1682, column: 28, scope: !254, inlinedAt: !256)
!254 = distinct !DISubprogram(name: "{closure#0}", linkageName: "_RNCNvCs9SN9c7tmF9T_9bun_alloc12default_dupe0B3_", scope: !255, file: !223, line: 1682, type: !20, scopeLine: 1682, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!255 = !DINamespace(name: "default_dupe", scope: !199)
!256 = !DILocation(line: 1064, column: 21, scope: !257, inlinedAt: !261)
!257 = distinct !DISubprogram(name: "unwrap_or_else<*mut u8, bun_alloc::default_dupe::{closure_env#0}>", linkageName: "_RINvMNtCsgXhsEb1m4tm_4core6optionINtB3_6OptionOhE14unwrap_or_elseNCNvCs9SN9c7tmF9T_9bun_alloc12default_dupe0EB15_", scope: !259, file: !258, line: 1058, type: !20, scopeLine: 1058, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!258 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/option.rs", directory: "", checksumkind: CSK_MD5, checksum: "e5a1d21d8830df0a398dde87f861de32")
!259 = !DINamespace(name: "Option", scope: !260)
!260 = !DINamespace(name: "option", scope: !64)
!261 = !DILocation(line: 1682, column: 10, scope: !228)
!262 = !DILocation(line: 551, column: 14, scope: !263, inlinedAt: !264)
!263 = distinct !DISubprogram(name: "copy_nonoverlapping<u8>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr19copy_nonoverlappinghECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 530, type: !20, scopeLine: 530, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!264 = !DILocation(line: 1688, column: 9, scope: !265)
!265 = distinct !DILexicalBlock(scope: !228, file: !223, line: 1680, column: 5)
!266 = distinct !DISubprogram(name: "out_of_memory", linkageName: "_RNvCs9SN9c7tmF9T_9bun_alloc13out_of_memory", scope: !199, file: !223, line: 933, type: !20, scopeLine: 933, flags: DIFlagPrototyped | DIFlagNoReturn, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!267 = !DILocation(line: 942, column: 9, scope: !266)
!268 = distinct !DISubprogram(name: "realloc_slice", linkageName: "_RNvCs9SN9c7tmF9T_9bun_alloc13realloc_slice", scope: !199, file: !223, line: 876, type: !20, scopeLine: 876, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!269 = !DILocation(line: 881, column: 28, scope: !268)
!270 = !DILocation(line: 888, column: 2, scope: !268)
!271 = distinct !DISubprogram(name: "bss_arena_bump", linkageName: "_RNvCs9SN9c7tmF9T_9bun_alloc14bss_arena_bump", scope: !199, file: !223, line: 1967, type: !20, scopeLine: 1967, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!272 = !DILocation(line: 3905, column: 24, scope: !273, inlinedAt: !274)
!273 = distinct !DISubprogram(name: "atomic_load<*mut u8>", linkageName: "_RINvNtNtCsgXhsEb1m4tm_4core4sync6atomic11atomic_loadOhECs9SN9c7tmF9T_9bun_alloc", scope: !62, file: !61, line: 3900, type: !20, scopeLine: 3900, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!274 = distinct !DILocation(line: 1732, column: 18, scope: !275, inlinedAt: !276)
!275 = distinct !DISubprogram(name: "load<u8>", linkageName: "_RNvMs3_NtNtCsgXhsEb1m4tm_4core4sync6atomicINtB5_6AtomicOhE4loadCs9SN9c7tmF9T_9bun_alloc", scope: !67, file: !61, line: 1730, type: !20, scopeLine: 1730, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!276 = !DILocation(line: 1977, column: 25, scope: !271)
!277 = !DILocation(line: 1978, column: 8, scope: !278)
!278 = distinct !DILexicalBlock(scope: !271, file: !223, line: 1977, column: 5)
!279 = !DILocation(line: 1984, column: 21, scope: !278)
!280 = !DILocation(line: 4010, column: 17, scope: !281, inlinedAt: !282)
!281 = distinct !DISubprogram(name: "atomic_compare_exchange<*mut u8>", linkageName: "_RINvNtNtCsgXhsEb1m4tm_4core4sync6atomic23atomic_compare_exchangeOhECs9SN9c7tmF9T_9bun_alloc", scope: !62, file: !61, line: 3969, type: !20, scopeLine: 3969, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!282 = distinct !DILocation(line: 1920, column: 18, scope: !283, inlinedAt: !284)
!283 = distinct !DISubprogram(name: "compare_exchange<u8>", linkageName: "_RNvMs3_NtNtCsgXhsEb1m4tm_4core4sync6atomicINtB5_6AtomicOhE16compare_exchangeCs9SN9c7tmF9T_9bun_alloc", scope: !67, file: !61, line: 1912, type: !20, scopeLine: 1912, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!284 = !DILocation(line: 1985, column: 27, scope: !285)
!285 = distinct !DILexicalBlock(scope: !278, file: !223, line: 1984, column: 9)
!286 = !DILocation(line: 1985, column: 16, scope: !285)
!287 = !DILocation(line: 1978, column: 5, scope: !278)
!288 = !DILocation(line: 0, scope: !271)
!289 = !DILocation(line: 3904, column: 24, scope: !290, inlinedAt: !291)
!290 = distinct !DISubprogram(name: "atomic_load<usize>", linkageName: "_RINvNtNtCsgXhsEb1m4tm_4core4sync6atomic11atomic_loadjECs9SN9c7tmF9T_9bun_alloc", scope: !62, file: !61, line: 3900, type: !20, scopeLine: 3900, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!291 = distinct !DILocation(line: 2870, column: 26, scope: !292, inlinedAt: !293)
!292 = distinct !DISubprogram(name: "load", linkageName: "_RNvMs1u_NtNtCsgXhsEb1m4tm_4core4sync6atomicINtB6_6AtomicjE4load", scope: !67, file: !61, line: 2868, type: !20, scopeLine: 2868, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!293 = !DILocation(line: 2000, column: 26, scope: !278)
!294 = !DILocation(line: 2001, column: 5, scope: !295)
!295 = distinct !DILexicalBlock(scope: !278, file: !223, line: 2000, column: 5)
!296 = !DILocation(line: 0, scope: !278)
!297 = !DILocation(line: 2002, column: 23, scope: !295)
!298 = !DILocation(line: 2003, column: 20, scope: !299)
!299 = distinct !DILexicalBlock(scope: !295, file: !223, line: 2002, column: 9)
!300 = !DILocation(line: 2004, column: 12, scope: !301)
!301 = distinct !DILexicalBlock(scope: !299, file: !223, line: 2003, column: 9)
!302 = !DILocation(line: 4072, column: 17, scope: !303, inlinedAt: !304)
!303 = distinct !DISubprogram(name: "atomic_compare_exchange_weak<usize>", linkageName: "_RINvNtNtCsgXhsEb1m4tm_4core4sync6atomic28atomic_compare_exchange_weakjECs9SN9c7tmF9T_9bun_alloc", scope: !62, file: !61, line: 4034, type: !20, scopeLine: 4034, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!304 = distinct !DILocation(line: 3130, column: 21, scope: !305, inlinedAt: !306)
!305 = distinct !DISubprogram(name: "compare_exchange_weak", linkageName: "_RNvMs1u_NtNtCsgXhsEb1m4tm_4core4sync6atomicINtB6_6AtomicjE21compare_exchange_weak", scope: !67, file: !61, line: 3123, type: !20, scopeLine: 3123, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!306 = !DILocation(line: 2010, column: 22, scope: !301)
!307 = !DILocation(line: 2010, column: 9, scope: !301)
!308 = !DILocation(line: 2039, column: 9, scope: !309, inlinedAt: !310)
!309 = distinct !DISubprogram(name: "bss_mmap_noreserve", linkageName: "_RNvCs9SN9c7tmF9T_9bun_alloc18bss_mmap_noreserve", scope: !199, file: !223, line: 2025, type: !20, scopeLine: 2025, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!310 = !DILocation(line: 2008, column: 20, scope: !301)
!311 = !DILocation(line: 2048, column: 8, scope: !312, inlinedAt: !310)
!312 = distinct !DILexicalBlock(scope: !309, file: !223, line: 2038, column: 5)
!313 = !DILocation(line: 961, column: 18, scope: !314, inlinedAt: !318)
!314 = distinct !DISubprogram(name: "add<u8>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrOh3addCs9SN9c7tmF9T_9bun_alloc", scope: !316, file: !315, line: 927, type: !20, scopeLine: 927, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!315 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/ptr/mut_ptr.rs", directory: "", checksumkind: CSK_MD5, checksum: "c557aa644c56bb9d833d79c62b549fbc")
!316 = !DINamespace(name: "{impl#0}", scope: !317)
!317 = !DINamespace(name: "mut_ptr", scope: !74)
!318 = !DILocation(line: 2014, column: 43, scope: !301)
!319 = !DILocation(line: 0, scope: !301)
!320 = !DILocation(line: 2018, column: 2, scope: !271)
!321 = !DILocation(line: 2049, column: 9, scope: !312, inlinedAt: !310)
!322 = distinct !DISubprogram(name: "copy_lowercase", linkageName: "_RNvCs9SN9c7tmF9T_9bun_alloc14copy_lowercase", scope: !199, file: !223, line: 595, type: !20, scopeLine: 595, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!323 = !DILocation(line: 600, column: 5, scope: !324)
!324 = distinct !DILexicalBlock(scope: !325, file: !223, line: 598, column: 5)
!325 = distinct !DILexicalBlock(scope: !322, file: !223, line: 596, column: 5)
!326 = !DILocation(line: 0, scope: !322)
!327 = !DILocation(line: 0, scope: !325)
!328 = !DILocation(line: 961, column: 18, scope: !329, inlinedAt: !330)
!329 = distinct !DISubprogram(name: "add<u8>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrOh3addCs9SN9c7tmF9T_9bun_alloc", scope: !316, file: !315, line: 927, type: !20, scopeLine: 927, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!330 = !DILocation(line: 102, column: 78, scope: !331, inlinedAt: !338)
!331 = distinct !DILexicalBlock(scope: !333, file: !332, line: 98, column: 9)
!332 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/slice/iter.rs", directory: "", checksumkind: CSK_MD5, checksum: "f33ab2e22fe09095bf73c41c52bd166c")
!333 = distinct !DILexicalBlock(scope: !334, file: !332, line: 97, column: 9)
!334 = distinct !DISubprogram(name: "new<u8>", linkageName: "_RNvMs4_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB5_4IterhE3newCs9SN9c7tmF9T_9bun_alloc", scope: !335, file: !332, line: 96, type: !20, scopeLine: 96, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!335 = !DINamespace(name: "Iter", scope: !336)
!336 = !DINamespace(name: "iter", scope: !337)
!337 = !DINamespace(name: "slice", scope: !64)
!338 = !DILocation(line: 1042, column: 9, scope: !339, inlinedAt: !342)
!339 = distinct !DISubprogram(name: "iter<u8>", linkageName: "_RNvMNtCsgXhsEb1m4tm_4core5sliceSh4iterCs9SN9c7tmF9T_9bun_alloc", scope: !341, file: !340, line: 1041, type: !20, scopeLine: 1041, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!340 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/slice/mod.rs", directory: "", checksumkind: CSK_MD5, checksum: "c42bc9ee39086d4d83492511a3bb787e")
!341 = !DINamespace(name: "{impl#0}", scope: !337)
!342 = !DILocation(line: 601, column: 33, scope: !324)
!343 = !DILocation(line: 601, column: 9, scope: !344)
!344 = distinct !DILexicalBlock(scope: !324, file: !223, line: 601, column: 9)
!345 = !DILocation(line: 601, column: 24, scope: !324)
!346 = !DILocation(line: 1714, column: 9, scope: !347, inlinedAt: !351)
!347 = distinct !DISubprogram(name: "eq<u8>", linkageName: "_RNvXsd_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullhENtNtB9_3cmp9PartialEq2eqCs9SN9c7tmF9T_9bun_alloc", scope: !349, file: !348, line: 1713, type: !20, scopeLine: 1713, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!348 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/ptr/non_null.rs", directory: "", checksumkind: CSK_MD5, checksum: "76aea4a9587781a0317e7deb09ec6512")
!349 = !DINamespace(name: "{impl#15}", scope: !350)
!350 = !DINamespace(name: "non_null", scope: !74)
!351 = distinct !DILocation(line: 180, column: 28, scope: !352, inlinedAt: !357)
!352 = distinct !DILexicalBlock(scope: !354, file: !353, line: 162, column: 17)
!353 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/slice/iter/macros.rs", directory: "", checksumkind: CSK_MD5, checksum: "87d1f0c2746f51593d75ddf4c9271f14")
!354 = distinct !DILexicalBlock(scope: !355, file: !353, line: 161, column: 17)
!355 = distinct !DISubprogram(name: "next<u8>", linkageName: "_RNvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB6_4IterhENtNtNtNtBa_4iter6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc", scope: !356, file: !353, line: 157, type: !20, scopeLine: 157, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!356 = !DINamespace(name: "{impl#171}", scope: !336)
!357 = distinct !DILocation(line: 80, column: 27, scope: !358, inlinedAt: !364)
!358 = distinct !DISubprogram(name: "next<core::slice::iter::Iter<u8>>", linkageName: "_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters9enumerateINtB4_9EnumerateINtNtNtBa_5slice4iter4IterhEENtNtNtB8_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc", scope: !360, file: !359, line: 79, type: !20, scopeLine: 79, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!359 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/iter/adapters/enumerate.rs", directory: "", checksumkind: CSK_MD5, checksum: "593117651994d9f54658d086cd09bf97")
!360 = !DINamespace(name: "{impl#1}", scope: !361)
!361 = !DINamespace(name: "enumerate", scope: !362)
!362 = !DINamespace(name: "adapters", scope: !363)
!363 = !DINamespace(name: "iter", scope: !64)
!364 = distinct !DILocation(line: 601, column: 24, scope: !344)
!365 = !DILocation(line: 180, column: 28, scope: !352, inlinedAt: !357)
!366 = !DILocation(line: 82, column: 9, scope: !367, inlinedAt: !364)
!367 = distinct !DILexicalBlock(scope: !368, file: !359, line: 81, column: 9)
!368 = distinct !DILexicalBlock(scope: !358, file: !359, line: 80, column: 9)
!369 = !DILocation(line: 656, column: 28, scope: !370, inlinedAt: !372)
!370 = distinct !DISubprogram(name: "add<u8>", linkageName: "_RNvMs1_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullhE3addCs9SN9c7tmF9T_9bun_alloc", scope: !371, file: !348, line: 648, type: !20, scopeLine: 648, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!371 = !DINamespace(name: "NonNull", scope: !350)
!372 = distinct !DILocation(line: 185, column: 40, scope: !352, inlinedAt: !357)
!373 = !DILocation(line: 601, column: 18, scope: !344)
!374 = !DILocation(line: 602, column: 20, scope: !375)
!375 = distinct !DILexicalBlock(scope: !376, file: !223, line: 602, column: 36)
!376 = distinct !DILexicalBlock(scope: !344, file: !223, line: 601, column: 9)
!377 = !DILocation(line: 612, column: 22, scope: !324)
!378 = !DILocation(line: 1064, column: 16, scope: !379, inlinedAt: !383)
!379 = distinct !DISubprogram(name: "checked_sub", linkageName: "_RNvMs9_NtCsgXhsEb1m4tm_4core3numj11checked_sub", scope: !381, file: !380, line: 1058, type: !20, scopeLine: 1058, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!380 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/num/uint_macros.rs", directory: "", checksumkind: CSK_MD5, checksum: "f8630270bd67146d079feabc45d8cb09")
!381 = !DINamespace(name: "{impl#11}", scope: !382)
!382 = !DINamespace(name: "num", scope: !64)
!383 = !DILocation(line: 450, column: 32, scope: !384, inlinedAt: !389)
!384 = !DILexicalBlockFile(scope: !386, file: !385, discriminator: 2)
!385 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/slice/index.rs", directory: "", checksumkind: CSK_MD5, checksum: "1c2140eb3aebf582efc202f1b7d2d543")
!386 = distinct !DISubprogram(name: "index_mut<u8>", linkageName: "_RNvXs2_NtNtCsgXhsEb1m4tm_4core5slice5indexINtNtNtB9_3ops5range5RangejEINtB5_10SliceIndexShE9index_mutCs9SN9c7tmF9T_9bun_alloc", scope: !387, file: !385, line: 448, type: !20, scopeLine: 448, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!387 = !DINamespace(name: "{impl#4}", scope: !388)
!388 = !DINamespace(name: "index", scope: !337)
!389 = !DILocation(line: 31, column: 15, scope: !390, inlinedAt: !393)
!390 = !DILexicalBlockFile(scope: !391, file: !385, discriminator: 2)
!391 = distinct !DISubprogram(name: "index_mut<u8, core::ops::range::Range<usize>>", linkageName: "_RNvXs_NtNtCsgXhsEb1m4tm_4core5slice5indexShINtNtNtB8_3ops5index8IndexMutINtNtBK_5range5RangejEE9index_mutCs9SN9c7tmF9T_9bun_alloc", scope: !392, file: !385, line: 30, type: !20, scopeLine: 30, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!392 = !DINamespace(name: "{impl#1}", scope: !388)
!393 = !DILocation(line: 612, column: 12, scope: !324)
!394 = !{!"branch_weights", i32 4001, i32 4000000}
!395 = !DILocation(line: 456, column: 13, scope: !386, inlinedAt: !389)
!396 = !DILocation(line: 101, column: 24, scope: !397, inlinedAt: !399)
!397 = distinct !DILexicalBlock(scope: !398, file: !385, line: 99, column: 5)
!398 = distinct !DISubprogram(name: "get_offset_len_mut_noubcheck<u8>", linkageName: "_RINvNtNtCsgXhsEb1m4tm_4core5slice5index28get_offset_len_mut_noubcheckhECs9SN9c7tmF9T_9bun_alloc", scope: !388, file: !385, line: 94, type: !20, scopeLine: 94, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!399 = !DILocation(line: 454, column: 28, scope: !384, inlinedAt: !389)
!400 = !DILocation(line: 551, column: 14, scope: !401, inlinedAt: !402)
!401 = distinct !DISubprogram(name: "copy_nonoverlapping<u8>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr19copy_nonoverlappinghECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 530, type: !20, scopeLine: 530, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!402 = distinct !DILocation(line: 5585, column: 9, scope: !403, inlinedAt: !404)
!403 = distinct !DISubprogram(name: "copy_from_slice_impl<u8>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc", scope: !337, file: !340, line: 5562, type: !20, scopeLine: 5562, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!404 = distinct !DILocation(line: 4326, column: 18, scope: !405, inlinedAt: !406)
!405 = distinct !DISubprogram(name: "copy_from_slice<u8>", linkageName: "_RNvMNtCsgXhsEb1m4tm_4core5sliceSh15copy_from_sliceCs9SN9c7tmF9T_9bun_alloc", scope: !341, file: !340, line: 4321, type: !20, scopeLine: 4321, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!406 = !DILocation(line: 612, column: 48, scope: !324)
!407 = !{!408, !410}
!408 = distinct !{!408, !409, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: %dest.0"}
!409 = distinct !{!409, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc"}
!410 = distinct !{!410, !409, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: %src.0"}
!411 = !{!412}
!412 = distinct !{!412, !409, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: argument 2"}
!413 = !DILocation(line: 1064, column: 16, scope: !379, inlinedAt: !414)
!414 = !DILocation(line: 437, column: 32, scope: !415, inlinedAt: !417)
!415 = !DILexicalBlockFile(scope: !416, file: !385, discriminator: 2)
!416 = distinct !DISubprogram(name: "index<u8>", linkageName: "_RNvXs2_NtNtCsgXhsEb1m4tm_4core5slice5indexINtNtNtB9_3ops5range5RangejEINtB5_10SliceIndexShE5indexCs9SN9c7tmF9T_9bun_alloc", scope: !387, file: !385, line: 435, type: !20, scopeLine: 435, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!417 = !DILocation(line: 19, column: 15, scope: !418, inlinedAt: !421)
!418 = !DILexicalBlockFile(scope: !419, file: !385, discriminator: 4)
!419 = distinct !DISubprogram(name: "index<u8, core::ops::range::Range<usize>>", linkageName: "_RNvXNtNtCsgXhsEb1m4tm_4core5slice5indexShINtNtNtB6_3ops5index5IndexINtNtBI_5range5RangejEE5indexCs9SN9c7tmF9T_9bun_alloc", scope: !420, file: !385, line: 18, type: !20, scopeLine: 18, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!420 = !DINamespace(name: "{impl#0}", scope: !388)
!421 = !DILocation(line: 616, column: 9, scope: !324)
!422 = !DILocation(line: 443, column: 13, scope: !416, inlinedAt: !417)
!423 = !DILocation(line: 617, column: 2, scope: !322)
!424 = !DILocation(line: 603, column: 30, scope: !375)
!425 = !DILocation(line: 1064, column: 16, scope: !379, inlinedAt: !426)
!426 = !DILocation(line: 450, column: 32, scope: !386, inlinedAt: !427)
!427 = !DILocation(line: 31, column: 15, scope: !391, inlinedAt: !428)
!428 = !DILocation(line: 603, column: 20, scope: !375)
!429 = !DILocation(line: 456, column: 13, scope: !386, inlinedAt: !427)
!430 = !DILocation(line: 1064, column: 16, scope: !379, inlinedAt: !431)
!431 = !DILocation(line: 437, column: 32, scope: !416, inlinedAt: !432)
!432 = !DILocation(line: 19, column: 15, scope: !419, inlinedAt: !433)
!433 = !DILocation(line: 603, column: 68, scope: !375)
!434 = !DILocation(line: 101, column: 24, scope: !435, inlinedAt: !436)
!435 = distinct !DILexicalBlock(scope: !398, file: !385, line: 99, column: 5)
!436 = !DILocation(line: 454, column: 28, scope: !386, inlinedAt: !427)
!437 = !DILocation(line: 551, column: 14, scope: !401, inlinedAt: !438)
!438 = distinct !DILocation(line: 5585, column: 9, scope: !403, inlinedAt: !439)
!439 = distinct !DILocation(line: 4326, column: 18, scope: !405, inlinedAt: !440)
!440 = !DILocation(line: 603, column: 43, scope: !375)
!441 = !{!442, !444}
!442 = distinct !{!442, !443, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: %dest.0"}
!443 = distinct !{!443, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc"}
!444 = distinct !{!444, !443, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: %src.0"}
!445 = !{!446}
!446 = distinct !{!446, !443, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: argument 2"}
!447 = !DILocation(line: 604, column: 17, scope: !375)
!448 = !DILocation(line: 443, column: 13, scope: !416, inlinedAt: !432)
!449 = !DILocation(line: 666, column: 9, scope: !450, inlinedAt: !453)
!450 = distinct !DISubprogram(name: "to_ascii_lowercase", linkageName: "_RNvMs4_NtCsgXhsEb1m4tm_4core3numh18to_ascii_lowercase", scope: !452, file: !451, line: 664, type: !20, scopeLine: 664, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!451 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/num/mod.rs", directory: "", checksumkind: CSK_MD5, checksum: "43b236cdab07dec92d93ae24377cb53f")
!452 = !DINamespace(name: "{impl#6}", scope: !382)
!453 = !DILocation(line: 604, column: 38, scope: !375)
!454 = !DILocation(line: 568, column: 12, scope: !455, inlinedAt: !457)
!455 = distinct !DISubprogram(name: "index<u8>", linkageName: "_RNvXs5_NtNtCsgXhsEb1m4tm_4core5slice5indexINtNtNtB9_3ops5range9RangeFromjEINtB5_10SliceIndexShE5indexCs9SN9c7tmF9T_9bun_alloc", scope: !456, file: !385, line: 567, type: !20, scopeLine: 567, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!456 = !DINamespace(name: "{impl#7}", scope: !388)
!457 = !DILocation(line: 19, column: 15, scope: !458, inlinedAt: !460)
!458 = !DILexicalBlockFile(scope: !459, file: !385, discriminator: 2)
!459 = distinct !DISubprogram(name: "index<u8, core::ops::range::RangeFrom<usize>>", linkageName: "_RNvXNtNtCsgXhsEb1m4tm_4core5slice5indexShINtNtNtB6_3ops5index5IndexINtNtBI_5range9RangeFromjEE5indexCs9SN9c7tmF9T_9bun_alloc", scope: !420, file: !385, line: 18, type: !20, scopeLine: 18, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!460 = !DILocation(line: 606, column: 37, scope: !461)
!461 = distinct !DILexicalBlock(scope: !375, file: !223, line: 605, column: 17)
!462 = !{!"branch_weights", !"expected", i32 2000, i32 1}
!463 = !DILocation(line: 573, column: 27, scope: !455, inlinedAt: !457)
!464 = !DILocation(line: 89, column: 24, scope: !465, inlinedAt: !467)
!465 = distinct !DILexicalBlock(scope: !466, file: !385, line: 87, column: 5)
!466 = distinct !DISubprogram(name: "get_offset_len_noubcheck<u8>", linkageName: "_RINvNtNtCsgXhsEb1m4tm_4core5slice5index24get_offset_len_noubcheckhECs9SN9c7tmF9T_9bun_alloc", scope: !388, file: !385, line: 82, type: !20, scopeLine: 82, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!467 = !DILocation(line: 574, column: 15, scope: !468, inlinedAt: !457)
!468 = distinct !DILexicalBlock(scope: !455, file: !385, line: 573, column: 13)
!469 = !DILocation(line: 607, column: 17, scope: !461)
!470 = !DILocation(line: 0, scope: !324)
!471 = !DILocation(line: 569, column: 13, scope: !455, inlinedAt: !457)
!472 = distinct !DISubprogram(name: "free_sensitive_cstr", linkageName: "_RNvCs9SN9c7tmF9T_9bun_alloc19free_sensitive_cstr", scope: !199, file: !223, line: 1738, type: !20, scopeLine: 1738, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!473 = !DILocation(line: 159, column: 18, scope: !474, inlinedAt: !478)
!474 = distinct !DISubprogram(name: "addr<u8>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr9const_ptrPh4addrCs9SN9c7tmF9T_9bun_alloc", scope: !476, file: !475, line: 153, type: !20, scopeLine: 153, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!475 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/ptr/const_ptr.rs", directory: "", checksumkind: CSK_MD5, checksum: "48638a38fe414ca30cde797e4a40b3a9")
!476 = !DINamespace(name: "{impl#0}", scope: !477)
!477 = !DINamespace(name: "const_ptr", scope: !74)
!478 = !DILocation(line: 38, column: 21, scope: !479, inlinedAt: !483)
!479 = !DILexicalBlockFile(scope: !480, file: !475, discriminator: 0)
!480 = distinct !DISubprogram(name: "runtime", linkageName: "_RNvNvMNtNtCsgXhsEb1m4tm_4core3ptr9const_ptrPp7is_null7runtime", scope: !482, file: !481, line: 2437, type: !20, scopeLine: 2437, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!481 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/intrinsics/mod.rs", directory: "", checksumkind: CSK_MD5, checksum: "d4a3767e95cb3a5c140fa04ec58d033d")
!482 = !DINamespace(name: "is_null", scope: !476)
!483 = !DILocation(line: 2450, column: 9, scope: !484, inlinedAt: !487)
!484 = !DILexicalBlockFile(scope: !485, file: !481, discriminator: 0)
!485 = distinct !DILexicalBlock(scope: !486, file: !475, line: 25, column: 9)
!486 = distinct !DISubprogram(name: "is_null<i8>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr9const_ptrPa7is_nullCs9SN9c7tmF9T_9bun_alloc", scope: !476, file: !475, line: 22, type: !20, scopeLine: 22, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!487 = !DILocation(line: 1739, column: 10, scope: !472)
!488 = !DILocation(line: 1739, column: 8, scope: !472)
!489 = !DILocation(line: 1747, column: 19, scope: !472)
!490 = !DILocation(line: 713, column: 9, scope: !491, inlinedAt: !492)
!491 = distinct !DISubprogram(name: "write_bytes<u8>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr11write_byteshECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 701, type: !20, scopeLine: 701, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!492 = !DILocation(line: 1707, column: 14, scope: !493, inlinedAt: !494)
!493 = distinct !DISubprogram(name: "secure_zero", linkageName: "_RNvCs9SN9c7tmF9T_9bun_alloc11secure_zero", scope: !199, file: !223, line: 1705, type: !20, scopeLine: 1705, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!494 = !DILocation(line: 1748, column: 9, scope: !495)
!495 = distinct !DILexicalBlock(scope: !472, file: !223, line: 1747, column: 9)
!496 = !DILocation(line: 491, column: 5, scope: !497, inlinedAt: !500)
!497 = distinct !DISubprogram(name: "black_box<*mut u8>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core4hint9black_boxOhECs9SN9c7tmF9T_9bun_alloc", scope: !499, file: !498, line: 490, type: !20, scopeLine: 490, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!498 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/hint.rs", directory: "", checksumkind: CSK_MD5, checksum: "3bdbac5c7616d584a36b114744411911")
!499 = !DINamespace(name: "hint", scope: !64)
!500 = !DILocation(line: 1709, column: 5, scope: !493, inlinedAt: !494)
!501 = !{i64 15967670502996576}
!502 = !DILocation(line: 4468, column: 23, scope: !503, inlinedAt: !504)
!503 = distinct !DISubprogram(name: "compiler_fence", linkageName: "_RNvNtNtCsgXhsEb1m4tm_4core4sync6atomic14compiler_fence", scope: !62, file: !61, line: 4461, type: !20, scopeLine: 4461, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!504 = distinct !DILocation(line: 1710, column: 5, scope: !493, inlinedAt: !494)
!505 = !DILocation(line: 424, column: 22, scope: !506, inlinedAt: !507)
!506 = distinct !DISubprogram(name: "free", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc13default_alloc4free", scope: !237, file: !223, line: 417, type: !20, scopeLine: 417, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!507 = !DILocation(line: 1749, column: 9, scope: !495)
!508 = !DILocation(line: 1751, column: 2, scope: !472)
!509 = distinct !DISubprogram(name: "copy_lowercase_if_needed", linkageName: "_RNvCs9SN9c7tmF9T_9bun_alloc24copy_lowercase_if_needed", scope: !199, file: !223, line: 624, type: !20, scopeLine: 624, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!510 = !DILocation(line: 961, column: 18, scope: !511, inlinedAt: !512)
!511 = distinct !DISubprogram(name: "add<u8>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrOh3addCs9SN9c7tmF9T_9bun_alloc", scope: !316, file: !315, line: 927, type: !20, scopeLine: 927, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!512 = !DILocation(line: 102, column: 78, scope: !513, inlinedAt: !516)
!513 = distinct !DILexicalBlock(scope: !514, file: !332, line: 98, column: 9)
!514 = distinct !DILexicalBlock(scope: !515, file: !332, line: 97, column: 9)
!515 = distinct !DISubprogram(name: "new<u8>", linkageName: "_RNvMs4_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB5_4IterhE3newCs9SN9c7tmF9T_9bun_alloc", scope: !335, file: !332, line: 96, type: !20, scopeLine: 96, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!516 = !DILocation(line: 1042, column: 9, scope: !517, inlinedAt: !518)
!517 = distinct !DISubprogram(name: "iter<u8>", linkageName: "_RNvMNtCsgXhsEb1m4tm_4core5sliceSh4iterCs9SN9c7tmF9T_9bun_alloc", scope: !341, file: !340, line: 1041, type: !20, scopeLine: 1041, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!518 = !DILocation(line: 625, column: 12, scope: !509)
!519 = !DILocation(line: 331, column: 17, scope: !520, inlinedAt: !521)
!520 = distinct !DISubprogram(name: "any<u8, fn(&u8) -> bool>", linkageName: "_RINvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB7_4IterhENtNtNtNtBb_4iter6traits8iterator8Iterator3anyNvMs4_NtBb_3numh18is_ascii_uppercaseECs9SN9c7tmF9T_9bun_alloc", scope: !356, file: !353, line: 326, type: !20, scopeLine: 326, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!521 = distinct !DILocation(line: 625, column: 19, scope: !509)
!522 = !DILocation(line: 1714, column: 9, scope: !523, inlinedAt: !524)
!523 = distinct !DISubprogram(name: "eq<u8>", linkageName: "_RNvXsd_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullhENtNtB9_3cmp9PartialEq2eqCs9SN9c7tmF9T_9bun_alloc", scope: !349, file: !348, line: 1713, type: !20, scopeLine: 1713, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!524 = distinct !DILocation(line: 180, column: 28, scope: !525, inlinedAt: !528)
!525 = distinct !DILexicalBlock(scope: !526, file: !353, line: 162, column: 17)
!526 = distinct !DILexicalBlock(scope: !527, file: !353, line: 161, column: 17)
!527 = distinct !DISubprogram(name: "next<u8>", linkageName: "_RNvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB6_4IterhENtNtNtNtBa_4iter6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc", scope: !356, file: !353, line: 157, type: !20, scopeLine: 157, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!528 = distinct !DILocation(line: 331, column: 42, scope: !529, inlinedAt: !521)
!529 = distinct !DILexicalBlock(scope: !520, file: !353, line: 331, column: 49)
!530 = !DILocation(line: 180, column: 28, scope: !525, inlinedAt: !528)
!531 = !DILocation(line: 656, column: 28, scope: !532, inlinedAt: !533)
!532 = distinct !DISubprogram(name: "add<u8>", linkageName: "_RNvMs1_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullhE3addCs9SN9c7tmF9T_9bun_alloc", scope: !371, file: !348, line: 648, type: !20, scopeLine: 648, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!533 = distinct !DILocation(line: 185, column: 40, scope: !525, inlinedAt: !528)
!534 = !DILocation(line: 813, column: 25, scope: !535, inlinedAt: !539)
!535 = !DILexicalBlockFile(scope: !536, file: !451, discriminator: 0)
!536 = distinct !DILexicalBlock(scope: !538, file: !537, line: 429, column: 9)
!537 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/macros/mod.rs", directory: "", checksumkind: CSK_MD5, checksum: "ea18ead197484fb49be4775a38f0f346")
!538 = distinct !DISubprogram(name: "is_ascii_uppercase", linkageName: "_RNvMs4_NtCsgXhsEb1m4tm_4core3numh18is_ascii_uppercase", scope: !452, file: !451, line: 812, type: !20, scopeLine: 812, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!539 = distinct !DILocation(line: 166, column: 5, scope: !540, inlinedAt: !545)
!540 = distinct !DISubprogram(name: "call_mut<fn(&u8) -> bool, (&u8)>", linkageName: "_RNvYNvMs4_NtCsgXhsEb1m4tm_4core3numh18is_ascii_uppercaseINtNtNtBa_3ops8function5FnMutTRhEE8call_mutCs9SN9c7tmF9T_9bun_alloc", scope: !542, file: !541, line: 166, type: !20, scopeLine: 166, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!541 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/ops/function.rs", directory: "", checksumkind: CSK_MD5, checksum: "7165aec212fc528edf645f7f5c1c91bb")
!542 = !DINamespace(name: "FnMut", scope: !543)
!543 = !DINamespace(name: "function", scope: !544)
!544 = !DINamespace(name: "ops", scope: !64)
!545 = distinct !DILocation(line: 332, column: 24, scope: !529, inlinedAt: !521)
!546 = !{!547, !549}
!547 = distinct !{!547, !548, !"_RNvMs4_NtCsgXhsEb1m4tm_4core3numh18is_ascii_uppercase: %self"}
!548 = distinct !{!548, !"_RNvMs4_NtCsgXhsEb1m4tm_4core3numh18is_ascii_uppercase"}
!549 = distinct !{!549, !550, !"_RNvYNvMs4_NtCsgXhsEb1m4tm_4core3numh18is_ascii_uppercaseINtNtNtBa_3ops8function5FnMutTRhEE8call_mutCs9SN9c7tmF9T_9bun_alloc: argument 0"}
!550 = distinct !{!550, !"_RNvYNvMs4_NtCsgXhsEb1m4tm_4core3numh18is_ascii_uppercaseINtNtNtBa_3ops8function5FnMutTRhEE8call_mutCs9SN9c7tmF9T_9bun_alloc"}
!551 = !{!552}
!552 = distinct !{!552, !553, !"_RINvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB7_4IterhENtNtNtNtBb_4iter6traits8iterator8Iterator3anyNvMs4_NtBb_3numh18is_ascii_uppercaseECs9SN9c7tmF9T_9bun_alloc: %self"}
!553 = distinct !{!553, !"_RINvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB7_4IterhENtNtNtNtBb_4iter6traits8iterator8Iterator3anyNvMs4_NtBb_3numh18is_ascii_uppercaseECs9SN9c7tmF9T_9bun_alloc"}
!554 = !DILocation(line: 332, column: 24, scope: !529, inlinedAt: !521)
!555 = !DILocation(line: 625, column: 5, scope: !509)
!556 = !DILocation(line: 626, column: 9, scope: !509)
!557 = !DILocation(line: 630, column: 2, scope: !509)
!558 = distinct !DISubprogram(name: "buf_print", linkageName: "_RNvCs9SN9c7tmF9T_9bun_alloc9buf_print", scope: !199, file: !223, line: 715, type: !20, scopeLine: 715, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!559 = !DILocation(line: 719, column: 9, scope: !558)
!560 = !DILocation(line: 719, column: 17, scope: !558)
!561 = !DILocation(line: 720, column: 5, scope: !562)
!562 = distinct !DILexicalBlock(scope: !558, file: !223, line: 719, column: 5)
!563 = !DILocation(line: 2173, column: 9, scope: !564, inlinedAt: !561)
!564 = distinct !DISubprogram(name: "branch<(), core::fmt::Error>", linkageName: "_RNvXsp_NtCsgXhsEb1m4tm_4core6resultINtB5_6ResultuNtNtB7_3fmt5ErrorENtNtNtB7_3ops9try_trait3Try6branchCs9SN9c7tmF9T_9bun_alloc", scope: !566, file: !565, line: 2172, type: !20, scopeLine: 2172, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!565 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/result.rs", directory: "", checksumkind: CSK_MD5, checksum: "7ebc974a4b69a504d7e902d792c422dd")
!566 = !DINamespace(name: "{impl#27}", scope: !567)
!567 = !DINamespace(name: "result", scope: !64)
!568 = !DILocation(line: 721, column: 15, scope: !562)
!569 = !DILocation(line: 722, column: 9, scope: !570)
!570 = distinct !DILexicalBlock(scope: !562, file: !223, line: 721, column: 5)
!571 = !DILocation(line: 1064, column: 16, scope: !572, inlinedAt: !573)
!572 = distinct !DISubprogram(name: "checked_sub", linkageName: "_RNvMs9_NtCsgXhsEb1m4tm_4core3numj11checked_sub", scope: !381, file: !380, line: 1058, type: !20, scopeLine: 1058, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!573 = !DILocation(line: 437, column: 32, scope: !574, inlinedAt: !575)
!574 = distinct !DISubprogram(name: "index<u8>", linkageName: "_RNvXs2_NtNtCsgXhsEb1m4tm_4core5slice5indexINtNtNtB9_3ops5range5RangejEINtB5_10SliceIndexShE5indexCs9SN9c7tmF9T_9bun_alloc", scope: !387, file: !385, line: 435, type: !20, scopeLine: 435, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!575 = !DILocation(line: 529, column: 23, scope: !576, inlinedAt: !578)
!576 = distinct !DISubprogram(name: "index<u8>", linkageName: "_RNvXs4_NtNtCsgXhsEb1m4tm_4core5slice5indexINtNtNtB9_3ops5range7RangeTojEINtB5_10SliceIndexShE5indexCs9SN9c7tmF9T_9bun_alloc", scope: !577, file: !385, line: 528, type: !20, scopeLine: 528, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!577 = !DINamespace(name: "{impl#6}", scope: !388)
!578 = !DILocation(line: 19, column: 15, scope: !579, inlinedAt: !580)
!579 = distinct !DISubprogram(name: "index<u8, core::ops::range::RangeTo<usize>>", linkageName: "_RNvXNtNtCsgXhsEb1m4tm_4core5slice5indexShINtNtNtB6_3ops5index5IndexINtNtBI_5range7RangeTojEE5indexCs9SN9c7tmF9T_9bun_alloc", scope: !420, file: !385, line: 18, type: !20, scopeLine: 18, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!580 = !DILocation(line: 722, column: 14, scope: !570)
!581 = !DILocation(line: 723, column: 2, scope: !558)
!582 = !DILocation(line: 443, column: 13, scope: !574, inlinedAt: !575)
!583 = !DILocation(line: 0, scope: !562)
!584 = !DILocation(line: 723, column: 1, scope: !558)
!585 = !DILocation(line: 39, column: 9, scope: !586, inlinedAt: !588)
!586 = distinct !DISubprogram(name: "to_byte_units", linkageName: "_RNvMCs9SN9c7tmF9T_9bun_allocNtB2_9Alignment13to_byte_units", scope: !587, file: !223, line: 38, type: !20, scopeLine: 38, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!587 = !DINamespace(name: "Alignment", scope: !199)
!588 = distinct !DILocation(line: 44, column: 77, scope: !239, inlinedAt: !589)
!589 = distinct !DILocation(line: 69, column: 9, scope: !244)
!590 = !DILocation(line: 503, column: 5, scope: !591, inlinedAt: !592)
!591 = distinct !DISubprogram(name: "must_use_aligned_alloc", linkageName: "_RNvNtCsguFFgRZA9Ru_16bun_mimalloc_sys8mimalloc22must_use_aligned_alloc", scope: !233, file: !232, line: 502, type: !20, scopeLine: 502, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!592 = distinct !DILocation(line: 512, column: 8, scope: !231, inlinedAt: !593)
!593 = distinct !DILocation(line: 456, column: 9, scope: !236, inlinedAt: !594)
!594 = distinct !DILocation(line: 44, column: 32, scope: !239, inlinedAt: !589)
!595 = !DILocation(line: 512, column: 8, scope: !231, inlinedAt: !593)
!596 = !DILocation(line: 515, column: 9, scope: !231, inlinedAt: !593)
!597 = !DILocation(line: 513, column: 9, scope: !231, inlinedAt: !593)
!598 = !DILocation(line: 0, scope: !231, inlinedAt: !593)
!599 = !DILocation(line: 70, column: 6, scope: !244)
!600 = distinct !DISubprogram(name: "remap_with_default_allocator", linkageName: "_RNvMNtCs9SN9c7tmF9T_9bun_alloc5basicNtB2_17MimallocAllocator28remap_with_default_allocator", scope: !241, file: !240, line: 86, type: !20, scopeLine: 86, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!601 = !DILocation(line: 39, column: 9, scope: !602, inlinedAt: !603)
!602 = distinct !DISubprogram(name: "to_byte_units", linkageName: "_RNvMCs9SN9c7tmF9T_9bun_allocNtB2_9Alignment13to_byte_units", scope: !587, file: !223, line: 38, type: !20, scopeLine: 38, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!603 = !DILocation(line: 98, column: 27, scope: !600)
!604 = !DILocation(line: 499, column: 18, scope: !605, inlinedAt: !606)
!605 = distinct !DISubprogram(name: "realloc_aligned", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc13default_alloc15realloc_aligned", scope: !237, file: !223, line: 496, type: !20, scopeLine: 496, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!606 = !DILocation(line: 95, column: 13, scope: !600)
!607 = !DILocation(line: 102, column: 6, scope: !600)
!608 = distinct !DISubprogram(name: "resize_with_default_allocator", linkageName: "_RNvMNtCs9SN9c7tmF9T_9bun_alloc5basicNtB2_17MimallocAllocator29resize_with_default_allocator", scope: !241, file: !240, line: 72, type: !20, scopeLine: 72, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!609 = !DILocation(line: 83, column: 19, scope: !608)
!610 = !DILocation(line: 38, column: 17, scope: !611, inlinedAt: !613)
!611 = !DILexicalBlockFile(scope: !612, file: !475, discriminator: 0)
!612 = distinct !DISubprogram(name: "runtime", linkageName: "_RNvNvMNtNtCsgXhsEb1m4tm_4core3ptr9const_ptrPp7is_null7runtime", scope: !482, file: !481, line: 2437, type: !20, scopeLine: 2437, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!613 = !DILocation(line: 2450, column: 9, scope: !614, inlinedAt: !617)
!614 = !DILexicalBlockFile(scope: !615, file: !481, discriminator: 0)
!615 = distinct !DILexicalBlock(scope: !616, file: !475, line: 25, column: 9)
!616 = distinct !DISubprogram(name: "is_null<core::ffi::c_void>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr9const_ptrPNtNtB6_3ffi6c_void7is_nullCs9SN9c7tmF9T_9bun_alloc", scope: !476, file: !475, line: 22, type: !20, scopeLine: 22, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!617 = !DILocation(line: 23, column: 27, scope: !618, inlinedAt: !619)
!618 = distinct !DISubprogram(name: "is_null<core::ffi::c_void>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrONtNtB6_3ffi6c_void7is_nullCs9SN9c7tmF9T_9bun_alloc", scope: !316, file: !315, line: 22, type: !20, scopeLine: 22, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!619 = !DILocation(line: 83, column: 73, scope: !608)
!620 = !DILocation(line: 84, column: 6, scope: !608)
!621 = distinct !DISubprogram(name: "new_boxed", linkageName: "_RNvMNtCs9SN9c7tmF9T_9bun_alloc9ast_allocNtB2_13AstAllocState9new_boxed", scope: !623, file: !622, line: 72, type: !20, scopeLine: 72, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!622 = !DIFile(filename: "src/bun_alloc/ast_alloc.rs", directory: "/Users/scc/code/researcher/bun", checksumkind: CSK_MD5, checksum: "d22ca6f9d506f75982da81571c6b0938")
!623 = !DINamespace(name: "AstAllocState", scope: !624)
!624 = !DINamespace(name: "ast_alloc", scope: !199)
!625 = !DILocation(line: 99, column: 9, scope: !16, inlinedAt: !626)
!626 = distinct !DILocation(line: 210, column: 73, scope: !22, inlinedAt: !627)
!627 = distinct !DILocation(line: 332, column: 9, scope: !26, inlinedAt: !628)
!628 = distinct !DILocation(line: 449, column: 14, scope: !28, inlinedAt: !629)
!629 = distinct !DILocation(line: 248, column: 18, scope: !31, inlinedAt: !630)
!630 = distinct !DILocation(line: 317, column: 33, scope: !631, inlinedAt: !632)
!631 = distinct !DISubprogram(name: "new_uninit<bun_alloc::ast_alloc::AstAllocState>", linkageName: "_RNvMNtCskhhhlZ4wWGP_5alloc5boxedINtB2_3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateE10new_uninitBI_", scope: !36, file: !32, line: 311, type: !20, scopeLine: 311, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!632 = !DILocation(line: 73, column: 25, scope: !621)
!633 = !DILocation(line: 101, column: 9, scope: !16, inlinedAt: !626)
!634 = !DILocation(line: 248, column: 11, scope: !31, inlinedAt: !630)
!635 = !DILocation(line: 248, column: 5, scope: !31, inlinedAt: !630)
!636 = !DILocation(line: 250, column: 19, scope: !31, inlinedAt: !630)
!637 = !DILocation(line: 1920, column: 41, scope: !638, inlinedAt: !639)
!638 = distinct !DISubprogram(name: "write<usize>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr5writejECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 1897, type: !20, scopeLine: 1897, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!639 = !DILocation(line: 1418, column: 18, scope: !640, inlinedAt: !641)
!640 = distinct !DISubprogram(name: "write<usize>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrOj5writeCs9SN9c7tmF9T_9bun_alloc", scope: !316, file: !315, line: 1413, type: !20, scopeLine: 1413, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!641 = !DILocation(line: 78, column: 41, scope: !642)
!642 = distinct !DILexicalBlock(scope: !643, file: !622, line: 74, column: 9)
!643 = distinct !DILexicalBlock(scope: !621, file: !622, line: 73, column: 9)
!644 = !DILocation(line: 1920, column: 41, scope: !645, inlinedAt: !646)
!645 = distinct !DISubprogram(name: "write<core::option::Option<bun_alloc::mimalloc_arena::MimallocArena>>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr5writeINtNtB4_6option6OptionNtNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena13MimallocArenaEEBX_", scope: !74, file: !73, line: 1897, type: !20, scopeLine: 1897, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!646 = !DILocation(line: 1418, column: 18, scope: !647, inlinedAt: !649)
!647 = !DILexicalBlockFile(scope: !648, file: !315, discriminator: 4)
!648 = distinct !DISubprogram(name: "write<core::option::Option<bun_alloc::mimalloc_arena::MimallocArena>>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrOINtNtB6_6option6OptionNtNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena13MimallocArenaE5writeB12_", scope: !316, file: !315, line: 1413, type: !20, scopeLine: 1413, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!649 = !DILocation(line: 80, column: 41, scope: !642)
!650 = !DILocation(line: 1920, column: 41, scope: !651, inlinedAt: !652)
!651 = distinct !DISubprogram(name: "write<*mut bun_mimalloc_sys::mimalloc::Heap>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr5writeONtNtCsguFFgRZA9Ru_16bun_mimalloc_sys8mimalloc4HeapECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 1897, type: !20, scopeLine: 1897, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!652 = !DILocation(line: 1418, column: 18, scope: !653, inlinedAt: !655)
!653 = !DILexicalBlockFile(scope: !654, file: !315, discriminator: 2)
!654 = distinct !DISubprogram(name: "write<*mut bun_mimalloc_sys::mimalloc::Heap>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrOONtNtCsguFFgRZA9Ru_16bun_mimalloc_sys8mimalloc4Heap5writeCs9SN9c7tmF9T_9bun_alloc", scope: !316, file: !315, line: 1413, type: !20, scopeLine: 1413, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!655 = !DILocation(line: 79, column: 35, scope: !642)
!656 = !DILocation(line: 83, column: 6, scope: !621)
!657 = distinct !DISubprogram(name: "is_instance", linkageName: "_RNvMs0_NtCs9SN9c7tmF9T_9bun_alloc14heap_breakdownNtB5_4Zone11is_instance", scope: !659, file: !658, line: 209, type: !20, scopeLine: 209, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!658 = !DIFile(filename: "src/bun_alloc/heap_breakdown.rs", directory: "/Users/scc/code/researcher/bun", checksumkind: CSK_MD5, checksum: "9d9dae4ba7513a5b5cd1285701a9808a")
!659 = !DINamespace(name: "Zone", scope: !660)
!660 = !DINamespace(name: "heap_breakdown", scope: !199)
!661 = !DILocation(line: 3606, column: 9, scope: !662, inlinedAt: !664)
!662 = distinct !DISubprogram(name: "is<bun_alloc::heap_breakdown::Zone>", linkageName: "_RINvMsy_Cs9SN9c7tmF9T_9bun_allocDNtB6_9AllocatorEL_2isNtNtB6_14heap_breakdown4ZoneEB6_", scope: !663, file: !223, line: 3605, type: !20, scopeLine: 3605, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!663 = !DINamespace(name: "{impl#36}", scope: !199)
!664 = !DILocation(line: 210, column: 20, scope: !657)
!665 = !DILocation(line: 764, column: 25, scope: !666, inlinedAt: !672)
!666 = !DILexicalBlockFile(scope: !668, file: !667, discriminator: 0)
!667 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/any.rs", directory: "", checksumkind: CSK_MD5, checksum: "7c7fb8b846d573000d2dc45fe41a9669")
!668 = distinct !DISubprogram(name: "runtime", linkageName: "_RNvNvXs7_NtCsgXhsEb1m4tm_4core3anyNtB7_6TypeIdNtNtB9_3cmp9PartialEq2eq7runtime", scope: !669, file: !481, line: 2437, type: !20, scopeLine: 2437, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!669 = !DINamespace(name: "eq", scope: !670)
!670 = !DINamespace(name: "{impl#9}", scope: !671)
!671 = !DINamespace(name: "any", scope: !64)
!672 = !DILocation(line: 2450, column: 9, scope: !673, inlinedAt: !661)
!673 = !DILexicalBlockFile(scope: !674, file: !481, discriminator: 0)
!674 = distinct !DILexicalBlock(scope: !675, file: !667, line: 749, column: 13)
!675 = distinct !DISubprogram(name: "eq", linkageName: "_RNvXs7_NtCsgXhsEb1m4tm_4core3anyNtB5_6TypeIdNtNtB7_3cmp9PartialEq2eq", scope: !670, file: !667, line: 744, type: !20, scopeLine: 744, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!676 = !DILocation(line: 3606, column: 64, scope: !662, inlinedAt: !664)
!677 = !DILocation(line: 211, column: 6, scope: !657)
!678 = distinct !DISubprogram(name: "init", linkageName: "_RNvMs0_NtCs9SN9c7tmF9T_9bun_alloc14heap_breakdownNtB5_4Zone4init", scope: !659, file: !658, line: 94, type: !20, scopeLine: 94, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!679 = !DILocation(line: 99, column: 24, scope: !678)
!680 = !DILocation(line: 100, column: 13, scope: !681)
!681 = distinct !DILexicalBlock(scope: !678, file: !658, line: 99, column: 13)
!682 = !DILocation(line: 103, column: 6, scope: !678)
!683 = distinct !DISubprogram(name: "raw_alloc", linkageName: "_RNvMs0_NtCs9SN9c7tmF9T_9bun_alloc14heap_breakdownNtB5_4Zone9raw_alloc", scope: !659, file: !658, line: 143, type: !20, scopeLine: 143, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!684 = !DILocation(line: 1038, column: 5, scope: !685, inlinedAt: !689)
!685 = distinct !DISubprogram(name: "max<usize>", linkageName: "_RNvYjNtNtCsgXhsEb1m4tm_4core3cmp3Ord3maxCs9SN9c7tmF9T_9bun_alloc", scope: !687, file: !686, line: 1033, type: !20, scopeLine: 1033, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!686 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/cmp.rs", directory: "", checksumkind: CSK_MD5, checksum: "736a93835c8eb09f7e6c373983e20e04")
!687 = !DINamespace(name: "Ord", scope: !688)
!688 = !DINamespace(name: "cmp", scope: !64)
!689 = distinct !DILocation(line: 134, column: 39, scope: !690, inlinedAt: !691)
!690 = distinct !DISubprogram(name: "aligned_alloc", linkageName: "_RNvMs0_NtCs9SN9c7tmF9T_9bun_alloc14heap_breakdownNtB5_4Zone13aligned_alloc", scope: !659, file: !658, line: 131, type: !20, scopeLine: 131, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!691 = distinct !DILocation(line: 150, column: 9, scope: !683)
!692 = !DILocation(line: 135, column: 19, scope: !693, inlinedAt: !691)
!693 = distinct !DILexicalBlock(scope: !690, file: !658, line: 134, column: 9)
!694 = !DILocation(line: 136, column: 12, scope: !695, inlinedAt: !691)
!695 = distinct !DILexicalBlock(scope: !693, file: !658, line: 135, column: 9)
!696 = !DILocation(line: 136, column: 9, scope: !695, inlinedAt: !691)
!697 = !DILocation(line: 141, column: 6, scope: !690, inlinedAt: !691)
!698 = !DILocation(line: 151, column: 6, scope: !683)
!699 = distinct !DISubprogram(name: "is_instance", linkageName: "_RNvMs0_NtCs9SN9c7tmF9T_9bun_alloc18max_heap_allocatorNtB5_16MaxHeapAllocator11is_instance", scope: !701, file: !700, line: 93, type: !20, scopeLine: 93, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!700 = !DIFile(filename: "src/bun_alloc/MaxHeapAllocator.rs", directory: "/Users/scc/code/researcher/bun", checksumkind: CSK_MD5, checksum: "ea603a8f7d8669741b9f8890463c2258")
!701 = !DINamespace(name: "MaxHeapAllocator", scope: !702)
!702 = !DINamespace(name: "max_heap_allocator", scope: !199)
!703 = !DILocation(line: 3606, column: 9, scope: !704, inlinedAt: !705)
!704 = distinct !DISubprogram(name: "is<bun_alloc::max_heap_allocator::MaxHeapAllocator>", linkageName: "_RINvMsy_Cs9SN9c7tmF9T_9bun_allocDNtB6_9AllocatorEL_2isNtNtB6_18max_heap_allocator16MaxHeapAllocatorEB6_", scope: !663, file: !223, line: 3605, type: !20, scopeLine: 3605, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!705 = !DILocation(line: 94, column: 15, scope: !699)
!706 = !DILocation(line: 764, column: 25, scope: !707, inlinedAt: !709)
!707 = !DILexicalBlockFile(scope: !708, file: !667, discriminator: 0)
!708 = distinct !DISubprogram(name: "runtime", linkageName: "_RNvNvXs7_NtCsgXhsEb1m4tm_4core3anyNtB7_6TypeIdNtNtB9_3cmp9PartialEq2eq7runtime", scope: !669, file: !481, line: 2437, type: !20, scopeLine: 2437, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!709 = !DILocation(line: 2450, column: 9, scope: !710, inlinedAt: !703)
!710 = !DILexicalBlockFile(scope: !711, file: !481, discriminator: 0)
!711 = distinct !DILexicalBlock(scope: !712, file: !667, line: 749, column: 13)
!712 = distinct !DISubprogram(name: "eq", linkageName: "_RNvXs7_NtCsgXhsEb1m4tm_4core3anyNtB5_6TypeIdNtNtB7_3cmp9PartialEq2eq", scope: !670, file: !667, line: 744, type: !20, scopeLine: 744, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!713 = !DILocation(line: 3606, column: 64, scope: !704, inlinedAt: !705)
!714 = !DILocation(line: 95, column: 6, scope: !699)
!715 = distinct !DISubprogram(name: "alloc", linkageName: "_RNvMs0_NtCs9SN9c7tmF9T_9bun_alloc18max_heap_allocatorNtB5_16MaxHeapAllocator5alloc", scope: !701, file: !700, line: 29, type: !20, scopeLine: 29, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!716 = !DILocation(line: 32, column: 9, scope: !715)
!717 = !DILocation(line: 34, column: 12, scope: !715)
!718 = !DILocation(line: 53, column: 14, scope: !715)
!719 = !DILocation(line: 137, column: 12, scope: !720, inlinedAt: !724)
!720 = distinct !DISubprogram(name: "new", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3mem9alignmentNtB2_9Alignment3new", scope: !722, file: !721, line: 136, type: !20, scopeLine: 136, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!721 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/mem/alignment.rs", directory: "", checksumkind: CSK_MD5, checksum: "74f3680e73e95347d13db1923bc738f5")
!722 = !DINamespace(name: "Alignment", scope: !723)
!723 = !DINamespace(name: "alignment", scope: !80)
!724 = !DILocation(line: 70, column: 31, scope: !725, inlinedAt: !730)
!725 = distinct !DISubprogram(name: "is_size_align_valid", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core5alloc6layoutNtB2_6Layout19is_size_align_valid", scope: !727, file: !726, line: 69, type: !20, scopeLine: 69, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!726 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/alloc/layout.rs", directory: "", checksumkind: CSK_MD5, checksum: "e9b0fa2b5eccd748fb6b1e11a9156468")
!727 = !DINamespace(name: "Layout", scope: !728)
!728 = !DINamespace(name: "layout", scope: !729)
!729 = !DINamespace(name: "alloc", scope: !64)
!730 = !DILocation(line: 60, column: 12, scope: !731, inlinedAt: !732)
!731 = distinct !DISubprogram(name: "from_size_align", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core5alloc6layoutNtB2_6Layout15from_size_align", scope: !727, file: !726, line: 59, type: !20, scopeLine: 59, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!732 = !DILocation(line: 36, column: 30, scope: !715)
!733 = !DILocation(line: 52, column: 9, scope: !715)
!734 = !DILocation(line: 2775, column: 15, scope: !735, inlinedAt: !718)
!735 = distinct !DISubprogram(name: "branch<core::ptr::non_null::NonNull<u8>>", linkageName: "_RNvXsJ_NtCsgXhsEb1m4tm_4core6optionINtB5_6OptionINtNtNtB7_3ptr8non_null7NonNullhEENtNtNtB7_3ops9try_trait3Try6branchCs9SN9c7tmF9T_9bun_alloc", scope: !736, file: !258, line: 2774, type: !20, scopeLine: 2774, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!736 = !DINamespace(name: "{impl#47}", scope: !260)
!737 = !DILocation(line: 29, scope: !715)
!738 = !DILocation(line: 41, column: 36, scope: !739)
!739 = distinct !DILexicalBlock(scope: !740, file: !700, line: 41, column: 45)
!740 = distinct !DILexicalBlock(scope: !715, file: !700, line: 36, column: 13)
!741 = !DILocation(line: 41, column: 24, scope: !739)
!742 = !DILocation(line: 155, column: 14, scope: !743, inlinedAt: !744)
!743 = distinct !DISubprogram(name: "realloc_nonnull", linkageName: "_RNvNtCskhhhlZ4wWGP_5alloc5alloc15realloc_nonnull", scope: !18, file: !17, line: 154, type: !20, scopeLine: 154, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!744 = !DILocation(line: 148, column: 14, scope: !745, inlinedAt: !746)
!745 = distinct !DISubprogram(name: "realloc", linkageName: "_RNvNtCskhhhlZ4wWGP_5alloc5alloc7realloc", scope: !18, file: !17, line: 147, type: !20, scopeLine: 147, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!746 = !DILocation(line: 43, column: 21, scope: !747)
!747 = distinct !DILexicalBlock(scope: !739, file: !700, line: 42, column: 21)
!748 = !DILocation(line: 41, column: 17, scope: !740)
!749 = !DILocation(line: 99, column: 9, scope: !750, inlinedAt: !751)
!750 = distinct !DISubprogram(name: "alloc", linkageName: "_RNvNtCskhhhlZ4wWGP_5alloc5alloc5alloc", scope: !18, file: !17, line: 95, type: !20, scopeLine: 95, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!751 = !DILocation(line: 45, column: 21, scope: !740)
!752 = !DILocation(line: 101, column: 9, scope: !750, inlinedAt: !751)
!753 = !DILocation(line: 0, scope: !740)
!754 = !DILocation(line: 267, column: 13, scope: !755, inlinedAt: !756)
!755 = distinct !DISubprogram(name: "new<u8>", linkageName: "_RNvMs1_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullhE3newCs9SN9c7tmF9T_9bun_alloc", scope: !371, file: !348, line: 266, type: !20, scopeLine: 266, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!756 = !DILocation(line: 48, column: 27, scope: !757)
!757 = distinct !DILexicalBlock(scope: !740, file: !700, line: 40, column: 13)
!758 = !DILocation(line: 49, column: 13, scope: !759)
!759 = distinct !DILexicalBlock(scope: !757, file: !700, line: 48, column: 13)
!760 = !DILocation(line: 50, column: 13, scope: !759)
!761 = !DILocation(line: 34, column: 9, scope: !715)
!762 = !DILocation(line: 0, scope: !715)
!763 = !DILocation(line: 54, column: 6, scope: !715)
!764 = distinct !DISubprogram(name: "resize", linkageName: "_RNvMs0_NtCs9SN9c7tmF9T_9bun_alloc18max_heap_allocatorNtB5_16MaxHeapAllocator6resize", scope: !701, file: !700, line: 57, type: !20, scopeLine: 57, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!765 = !DILocation(line: 64, column: 9, scope: !764)
!766 = distinct !DISubprogram(name: "allocated_bytes", linkageName: "_RNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB5_13MimallocArena15allocated_bytes", scope: !203, file: !196, line: 333, type: !20, scopeLine: 333, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!767 = !DILocation(line: 349, column: 13, scope: !766)
!768 = !DILocation(line: 349, column: 32, scope: !766)
!769 = !DILocation(line: 199, column: 9, scope: !770, inlinedAt: !771)
!770 = distinct !DISubprogram(name: "heap_ptr", linkageName: "_RNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB5_13MimallocArena8heap_ptr", scope: !203, file: !196, line: 198, type: !20, scopeLine: 198, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!771 = !DILocation(line: 353, column: 22, scope: !772)
!772 = distinct !DILexicalBlock(scope: !766, file: !196, line: 349, column: 9)
!773 = !DILocation(line: 352, column: 13, scope: !772)
!774 = !DILocation(line: 359, column: 9, scope: !772)
!775 = !DILocation(line: 360, column: 5, scope: !766)
!776 = !DILocation(line: 360, column: 6, scope: !766)
!777 = distinct !DISubprogram(name: "reset", linkageName: "_RNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB5_13MimallocArena5reset", scope: !203, file: !196, line: 215, type: !20, scopeLine: 215, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!778 = !DILocation(line: 199, column: 9, scope: !779, inlinedAt: !780)
!779 = distinct !DISubprogram(name: "heap_ptr", linkageName: "_RNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB5_13MimallocArena8heap_ptr", scope: !203, file: !196, line: 198, type: !20, scopeLine: 198, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!780 = !DILocation(line: 229, column: 49, scope: !777)
!781 = !DILocation(line: 229, column: 18, scope: !777)
!782 = !DILocation(line: 231, column: 29, scope: !777)
!783 = !DILocation(line: 267, column: 13, scope: !784, inlinedAt: !785)
!784 = distinct !DISubprogram(name: "new<bun_mimalloc_sys::mimalloc::Heap>", linkageName: "_RNvMs1_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullNtNtCsguFFgRZA9Ru_16bun_mimalloc_sys8mimalloc4HeapE3newCs9SN9c7tmF9T_9bun_alloc", scope: !371, file: !348, line: 266, type: !20, scopeLine: 266, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!785 = !DILocation(line: 232, column: 21, scope: !786)
!786 = distinct !DILexicalBlock(scope: !777, file: !196, line: 231, column: 9)
!787 = !DILocation(line: 232, column: 58, scope: !788, inlinedAt: !791)
!788 = distinct !DISubprogram(name: "{closure#0}", linkageName: "_RNCNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB7_13MimallocArena5reset0B9_", scope: !789, file: !196, line: 232, type: !20, scopeLine: 232, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!789 = !DINamespace(name: "reset", scope: !790)
!790 = !DINamespace(name: "{impl#3}", scope: !198)
!791 = !DILocation(line: 1064, column: 21, scope: !792, inlinedAt: !793)
!792 = distinct !DISubprogram(name: "unwrap_or_else<core::ptr::non_null::NonNull<bun_mimalloc_sys::mimalloc::Heap>, bun_alloc::mimalloc_arena::{impl#3}::reset::{closure_env#0}>", linkageName: "_RINvMNtCsgXhsEb1m4tm_4core6optionINtB3_6OptionINtNtNtB5_3ptr8non_null7NonNullNtNtCsguFFgRZA9Ru_16bun_mimalloc_sys8mimalloc4HeapEE14unwrap_or_elseNCNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB2r_13MimallocArena5reset0EB2t_", scope: !259, file: !258, line: 1058, type: !20, scopeLine: 1058, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!793 = !DILocation(line: 232, column: 40, scope: !786)
!794 = !DILocation(line: 232, column: 9, scope: !786)
!795 = !DILocation(line: 240, column: 6, scope: !777)
!796 = distinct !DISubprogram(name: "grow_one<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone), alloc::alloc::Global>", linkageName: "_RNvMs3_NtCskhhhlZ4wWGP_5alloc7raw_vecINtB5_6RawVecTINtNtB7_3vec3VechEBN_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE8grow_oneB1d_", scope: !798, file: !797, line: 186, type: !20, scopeLine: 186, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!797 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/alloc/src/raw_vec/mod.rs", directory: "", checksumkind: CSK_MD5, checksum: "203bcd00d420565675c5e235defedb8e")
!798 = !DINamespace(name: "RawVec", scope: !799)
!799 = !DINamespace(name: "raw_vec", scope: !19)
!800 = !DILocation(line: 492, column: 56, scope: !801, inlinedAt: !804)
!801 = distinct !DILexicalBlock(scope: !802, file: !797, line: 492, column: 95)
!802 = distinct !DISubprogram(name: "grow_one<alloc::alloc::Global>", linkageName: "_RNvMs4_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner8grow_oneCs9SN9c7tmF9T_9bun_alloc", scope: !803, file: !797, line: 490, type: !20, scopeLine: 490, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!803 = !DINamespace(name: "RawVecInner", scope: !799)
!804 = !DILocation(line: 188, column: 29, scope: !796)
!805 = !{i64 0, i64 -9223372036854775808}
!806 = !{!807}
!807 = distinct !{!807, !808, !"_RNvMs4_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner14grow_amortizedCs9SN9c7tmF9T_9bun_alloc: %self"}
!808 = distinct !{!808, !"_RNvMs4_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner14grow_amortizedCs9SN9c7tmF9T_9bun_alloc"}
!809 = !DILocation(line: 492, column: 41, scope: !801, inlinedAt: !804)
!810 = !DILocation(line: 522, column: 28, scope: !811, inlinedAt: !813)
!811 = distinct !DILexicalBlock(scope: !812, file: !797, line: 518, column: 9)
!812 = distinct !DISubprogram(name: "grow_amortized<alloc::alloc::Global>", linkageName: "_RNvMs4_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner14grow_amortizedCs9SN9c7tmF9T_9bun_alloc", scope: !803, file: !797, line: 502, type: !20, scopeLine: 502, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!813 = distinct !DILocation(line: 492, column: 41, scope: !801, inlinedAt: !804)
!814 = !DILocation(line: 1038, column: 5, scope: !685, inlinedAt: !815)
!815 = distinct !DILocation(line: 1681, column: 8, scope: !816, inlinedAt: !817)
!816 = distinct !DISubprogram(name: "max<usize>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3cmp3maxjECs9SN9c7tmF9T_9bun_alloc", scope: !688, file: !686, line: 1680, type: !20, scopeLine: 1680, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!817 = distinct !DILocation(line: 523, column: 19, scope: !818, inlinedAt: !813)
!818 = distinct !DILexicalBlock(scope: !811, file: !797, line: 522, column: 9)
!819 = !DILocation(line: 528, column: 28, scope: !820, inlinedAt: !813)
!820 = distinct !DILexicalBlock(scope: !818, file: !797, line: 523, column: 9)
!821 = !DILocation(line: 528, column: 33, scope: !820, inlinedAt: !813)
!822 = !DILocation(line: 2173, column: 15, scope: !823, inlinedAt: !824)
!823 = distinct !DISubprogram(name: "branch<core::ptr::non_null::NonNull<[u8]>, alloc::collections::TryReserveError>", linkageName: "_RNvXsp_NtCsgXhsEb1m4tm_4core6resultINtB5_6ResultINtNtNtB7_3ptr8non_null7NonNullShENtNtCskhhhlZ4wWGP_5alloc11collections15TryReserveErrorENtNtNtB7_3ops9try_trait3Try6branchCs9SN9c7tmF9T_9bun_alloc", scope: !566, file: !565, line: 2172, type: !20, scopeLine: 2172, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!824 = distinct !DILocation(line: 528, column: 28, scope: !820, inlinedAt: !813)
!825 = !{i64 0, i64 2}
!826 = !DILocation(line: 2173, column: 9, scope: !823, inlinedAt: !824)
!827 = !DILocation(line: 0, scope: !823, inlinedAt: !824)
!828 = !DILocation(line: 2175, column: 17, scope: !823, inlinedAt: !824)
!829 = !{i64 0, i64 -9223372036854775807}
!830 = !DILocation(line: 528, column: 62, scope: !820, inlinedAt: !813)
!831 = !DILocation(line: 493, column: 13, scope: !801, inlinedAt: !804)
!832 = !DILocation(line: 2174, column: 16, scope: !823, inlinedAt: !824)
!833 = !DILocation(line: 776, column: 9, scope: !834, inlinedAt: !835)
!834 = distinct !DISubprogram(name: "set_ptr_and_cap<alloc::alloc::Global>", linkageName: "_RNvMs2_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner15set_ptr_and_capCs9SN9c7tmF9T_9bun_alloc", scope: !803, file: !797, line: 772, type: !20, scopeLine: 772, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!835 = distinct !DILocation(line: 531, column: 23, scope: !836, inlinedAt: !813)
!836 = distinct !DILexicalBlock(scope: !820, file: !797, line: 528, column: 9)
!837 = !DILocation(line: 42, column: 26, scope: !838, inlinedAt: !842)
!838 = distinct !DISubprogram(name: "new_unchecked", linkageName: "_RNvMs1z_NtNtCsgXhsEb1m4tm_4core3num11niche_typesNtB6_14UsizeNoHighBit13new_unchecked", scope: !840, file: !839, line: 40, type: !20, scopeLine: 40, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!839 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/num/niche_types.rs", directory: "", checksumkind: CSK_MD5, checksum: "b3871eb21e61251a8509e6d07911f9fb")
!840 = !DINamespace(name: "UsizeNoHighBit", scope: !841)
!841 = !DINamespace(name: "niche_types", scope: !382)
!842 = distinct !DILocation(line: 777, column: 29, scope: !834, inlinedAt: !835)
!843 = !DILocation(line: 777, column: 9, scope: !834, inlinedAt: !835)
!844 = !DILocation(line: 189, column: 6, scope: !796)
!845 = distinct !DISubprogram(name: "finish_grow<alloc::alloc::Global>", linkageName: "_RNvMs4_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner11finish_growCs9SN9c7tmF9T_9bun_alloc", scope: !803, file: !797, line: 543, type: !20, scopeLine: 543, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!846 = !DILocation(line: 3192, column: 26, scope: !847, inlinedAt: !848)
!847 = distinct !DISubprogram(name: "overflowing_mul", linkageName: "_RNvMs9_NtCsgXhsEb1m4tm_4core3numj15overflowing_mul", scope: !381, file: !380, line: 3191, type: !20, scopeLine: 3191, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!848 = !DILocation(line: 1302, column: 31, scope: !849, inlinedAt: !850)
!849 = distinct !DISubprogram(name: "checked_mul", linkageName: "_RNvMs9_NtCsgXhsEb1m4tm_4core3numj11checked_mul", scope: !381, file: !380, line: 1301, type: !20, scopeLine: 1301, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!850 = !DILocation(line: 527, column: 39, scope: !851, inlinedAt: !853)
!851 = distinct !DILexicalBlock(scope: !852, file: !726, line: 527, column: 54)
!852 = distinct !DISubprogram(name: "repeat_packed", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core5alloc6layoutNtB2_6Layout13repeat_packed", scope: !727, file: !726, line: 526, type: !20, scopeLine: 526, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!853 = !DILocation(line: 901, column: 17, scope: !854, inlinedAt: !855)
!854 = distinct !DISubprogram(name: "layout_array", linkageName: "_RNvNtCskhhhlZ4wWGP_5alloc7raw_vec12layout_array", scope: !799, file: !797, line: 896, type: !20, scopeLine: 896, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!855 = !DILocation(line: 548, column: 26, scope: !845)
!856 = !DILocation(line: 459, column: 8, scope: !857, inlinedAt: !859)
!857 = distinct !DISubprogram(name: "unlikely", linkageName: "_RNvNtCsgXhsEb1m4tm_4core10intrinsics8unlikely", scope: !858, file: !481, line: 458, type: !20, scopeLine: 458, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!858 = !DINamespace(name: "intrinsics", scope: !64)
!859 = !DILocation(line: 1303, column: 16, scope: !860, inlinedAt: !850)
!860 = distinct !DILexicalBlock(scope: !849, file: !380, line: 1302, column: 13)
!861 = !{!"branch_weights", i32 2002, i32 2000}
!862 = !DILocation(line: 634, column: 39, scope: !863, inlinedAt: !864)
!863 = distinct !DISubprogram(name: "current_memory<alloc::alloc::Global>", linkageName: "_RNvMs2_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner14current_memoryCs9SN9c7tmF9T_9bun_alloc", scope: !803, file: !797, line: 633, type: !20, scopeLine: 633, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!864 = distinct !DILocation(line: 550, column: 69, scope: !865)
!865 = distinct !DILexicalBlock(scope: !866, file: !797, line: 550, column: 99)
!866 = distinct !DILexicalBlock(scope: !845, file: !797, line: 548, column: 9)
!867 = !{!868}
!868 = distinct !{!868, !869, !"_RNvMs2_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner14current_memoryCs9SN9c7tmF9T_9bun_alloc: %self"}
!869 = distinct !{!869, !"_RNvMs2_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner14current_memoryCs9SN9c7tmF9T_9bun_alloc"}
!870 = !{!871}
!871 = distinct !{!871, !869, !"_RNvMs2_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner14current_memoryCs9SN9c7tmF9T_9bun_alloc: %_0"}
!872 = !DILocation(line: 1373, column: 17, scope: !873, inlinedAt: !874)
!873 = distinct !DISubprogram(name: "unchecked_mul", linkageName: "_RNvMs9_NtCsgXhsEb1m4tm_4core3numj13unchecked_mul", scope: !381, file: !380, line: 1361, type: !20, scopeLine: 1361, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!874 = distinct !DILocation(line: 642, column: 53, scope: !863, inlinedAt: !864)
!875 = !DILocation(line: 644, column: 23, scope: !876, inlinedAt: !864)
!876 = distinct !DILexicalBlock(scope: !877, file: !797, line: 643, column: 17)
!877 = distinct !DILexicalBlock(scope: !863, file: !797, line: 642, column: 17)
!878 = !DILocation(line: 257, column: 40, scope: !879, inlinedAt: !882)
!879 = distinct !DILexicalBlock(scope: !880, file: !17, line: 254, column: 17)
!880 = distinct !DILexicalBlock(scope: !881, file: !17, line: 253, column: 13)
!881 = distinct !DISubprogram(name: "grow_impl_runtime", linkageName: "_RNvMNtCskhhhlZ4wWGP_5alloc5allocNtB2_6Global17grow_impl_runtime", scope: !24, file: !17, line: 236, type: !20, scopeLine: 236, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!882 = distinct !DILocation(line: 362, column: 9, scope: !883, inlinedAt: !884)
!883 = distinct !DISubprogram(name: "grow_impl", linkageName: "_RNvMNtCskhhhlZ4wWGP_5alloc5allocNtB2_6Global9grow_impl", scope: !24, file: !17, line: 355, type: !20, scopeLine: 355, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!884 = distinct !DILocation(line: 474, column: 23, scope: !885, inlinedAt: !886)
!885 = distinct !DISubprogram(name: "grow", linkageName: "_RNvXs_NtCskhhhlZ4wWGP_5alloc5allocNtB4_6GlobalNtNtCsgXhsEb1m4tm_4core5alloc9Allocator4grow", scope: !29, file: !17, line: 467, type: !20, scopeLine: 467, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!886 = distinct !DILocation(line: 556, column: 28, scope: !865)
!887 = !DILocation(line: 210, column: 9, scope: !888, inlinedAt: !889)
!888 = distinct !DISubprogram(name: "assert_unchecked", linkageName: "_RNvNtCsgXhsEb1m4tm_4core4hint16assert_unchecked", scope: !499, file: !498, line: 202, type: !20, scopeLine: 202, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!889 = distinct !DILocation(line: 257, column: 17, scope: !879, inlinedAt: !882)
!890 = !DILocation(line: 155, column: 14, scope: !891, inlinedAt: !892)
!891 = distinct !DISubprogram(name: "realloc_nonnull", linkageName: "_RNvNtCskhhhlZ4wWGP_5alloc5alloc15realloc_nonnull", scope: !18, file: !17, line: 154, type: !20, scopeLine: 154, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!892 = distinct !DILocation(line: 259, column: 31, scope: !879, inlinedAt: !882)
!893 = !DILocation(line: 550, column: 22, scope: !866)
!894 = !DILocation(line: 206, column: 9, scope: !23, inlinedAt: !895)
!895 = distinct !DILocation(line: 332, column: 9, scope: !896, inlinedAt: !897)
!896 = distinct !DISubprogram(name: "alloc_impl", linkageName: "_RNvMNtCskhhhlZ4wWGP_5alloc5allocNtB2_6Global10alloc_impl", scope: !24, file: !17, line: 331, type: !20, scopeLine: 331, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!897 = distinct !DILocation(line: 449, column: 14, scope: !898, inlinedAt: !899)
!898 = distinct !DISubprogram(name: "allocate", linkageName: "_RNvXs_NtCskhhhlZ4wWGP_5alloc5allocNtB4_6GlobalNtNtCsgXhsEb1m4tm_4core5alloc9Allocator8allocate", scope: !29, file: !17, line: 448, type: !20, scopeLine: 448, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!899 = distinct !DILocation(line: 559, column: 24, scope: !866)
!900 = !DILocation(line: 404, column: 18, scope: !901, inlinedAt: !902)
!901 = distinct !DISubprogram(name: "as_ptr<u8>", linkageName: "_RNvMs1_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullhE6as_ptrCs9SN9c7tmF9T_9bun_alloc", scope: !371, file: !348, line: 398, type: !20, scopeLine: 398, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!902 = distinct !DILocation(line: 1447, column: 75, scope: !903, inlinedAt: !904)
!903 = distinct !DISubprogram(name: "slice_from_raw_parts<u8>", linkageName: "_RNvMs4_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullShE20slice_from_raw_partsCs9SN9c7tmF9T_9bun_alloc", scope: !371, file: !348, line: 1445, type: !20, scopeLine: 1445, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!904 = distinct !DILocation(line: 207, column: 21, scope: !23, inlinedAt: !895)
!905 = !DILocation(line: 563, column: 9, scope: !906)
!906 = distinct !DILexicalBlock(scope: !866, file: !797, line: 550, column: 9)
!907 = !DILocation(line: 99, column: 9, scope: !16, inlinedAt: !908)
!908 = distinct !DILocation(line: 210, column: 73, scope: !22, inlinedAt: !895)
!909 = !DILocation(line: 101, column: 9, scope: !16, inlinedAt: !908)
!910 = !DILocation(line: 267, column: 13, scope: !911, inlinedAt: !912)
!911 = distinct !DISubprogram(name: "new<u8>", linkageName: "_RNvMs1_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullhE3newCs9SN9c7tmF9T_9bun_alloc", scope: !371, file: !348, line: 266, type: !20, scopeLine: 266, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!912 = distinct !DILocation(line: 211, column: 27, scope: !913, inlinedAt: !895)
!913 = distinct !DILexicalBlock(scope: !22, file: !17, line: 210, column: 17)
!914 = !DILocation(line: 563, column: 15, scope: !906)
!915 = !DILocation(line: 565, column: 23, scope: !906)
!916 = !DILocation(line: 565, column: 87, scope: !906)
!917 = !DILocation(line: 564, column: 27, scope: !918)
!918 = distinct !DILexicalBlock(scope: !906, file: !797, line: 564, column: 13)
!919 = !DILocation(line: 564, column: 36, scope: !906)
!920 = !DILocation(line: 0, scope: !845)
!921 = !DILocation(line: 567, column: 6, scope: !845)
!922 = distinct !DISubprogram(name: "free", linkageName: "_RNvMs_NtCs9SN9c7tmF9T_9bun_alloc18nullable_allocatorNtB4_17NullableAllocator4free", scope: !924, file: !923, line: 84, type: !20, scopeLine: 84, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!923 = !DIFile(filename: "src/bun_alloc/NullableAllocator.rs", directory: "/Users/scc/code/researcher/bun", checksumkind: CSK_MD5, checksum: "f9f558e99b69a1636ff4bc776e137263")
!924 = !DINamespace(name: "NullableAllocator", scope: !925)
!925 = !DINamespace(name: "nullable_allocator", scope: !199)
!926 = !DILocation(line: 79, column: 18, scope: !927, inlinedAt: !928)
!927 = distinct !DISubprogram(name: "get", linkageName: "_RNvMs_NtCs9SN9c7tmF9T_9bun_alloc18nullable_allocatorNtB4_17NullableAllocator3get", scope: !924, file: !923, line: 77, type: !20, scopeLine: 77, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!928 = !DILocation(line: 85, column: 39, scope: !929)
!929 = distinct !DILexicalBlock(scope: !922, file: !923, line: 85, column: 45)
!930 = !DILocation(line: 80, column: 21, scope: !927, inlinedAt: !928)
!931 = !DILocation(line: 2775, column: 15, scope: !932, inlinedAt: !930)
!932 = distinct !DISubprogram(name: "branch<&bun_alloc::AllocatorVTable>", linkageName: "_RNvXsJ_NtCsgXhsEb1m4tm_4core6optionINtB5_6OptionRNtCs9SN9c7tmF9T_9bun_alloc15AllocatorVTableENtNtNtB7_3ops9try_trait3Try6branchBN_", scope: !736, file: !258, line: 2774, type: !20, scopeLine: 2774, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!933 = !DILocation(line: 2775, column: 9, scope: !932, inlinedAt: !930)
!934 = !DILocation(line: 2423, column: 5, scope: !935, inlinedAt: !936)
!935 = distinct !DISubprogram(name: "eq<bun_alloc::AllocatorVTable>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr2eqNtCs9SN9c7tmF9T_9bun_alloc15AllocatorVTableEBw_", scope: !74, file: !73, line: 2422, type: !20, scopeLine: 2422, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!936 = !DILocation(line: 1497, column: 9, scope: !937, inlinedAt: !939)
!937 = distinct !DISubprogram(name: "is_wtf_allocator", linkageName: "_RNvMsd_Cs9SN9c7tmF9T_9bun_allocNtB5_6String16is_wtf_allocator", scope: !938, file: !223, line: 1496, type: !20, scopeLine: 1496, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!938 = !DINamespace(name: "String", scope: !199)
!939 = !DILocation(line: 86, column: 16, scope: !929)
!940 = !DILocation(line: 99, column: 6, scope: !922)
!941 = !DILocation(line: 182, column: 12, scope: !942, inlinedAt: !943)
!942 = distinct !DISubprogram(name: "free", linkageName: "_RNvMs3_Cs9SN9c7tmF9T_9bun_allocNtB5_12StdAllocator4free", scope: !247, file: !223, line: 181, type: !20, scopeLine: 181, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!943 = !DILocation(line: 97, column: 23, scope: !929)
!944 = !DILocation(line: 3954, column: 24, scope: !945, inlinedAt: !946)
!945 = distinct !DISubprogram(name: "atomic_sub<u32, u32>", linkageName: "_RINvNtNtCsgXhsEb1m4tm_4core4sync6atomic10atomic_submmECs9SN9c7tmF9T_9bun_alloc", scope: !62, file: !61, line: 3950, type: !20, scopeLine: 3950, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!946 = distinct !DILocation(line: 3193, column: 26, scope: !947, inlinedAt: !948)
!947 = distinct !DISubprogram(name: "fetch_sub", linkageName: "_RNvMs16_NtNtCsgXhsEb1m4tm_4core4sync6atomicINtB6_6AtomicmE9fetch_sub", scope: !67, file: !61, line: 3191, type: !20, scopeLine: 3191, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!948 = distinct !DILocation(line: 1318, column: 14, scope: !949, inlinedAt: !951)
!949 = distinct !DISubprogram(name: "deref", linkageName: "_RNvMsc_Cs9SN9c7tmF9T_9bun_allocNtB5_19WTFStringImplStruct5deref", scope: !950, file: !223, line: 1315, type: !20, scopeLine: 1315, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!950 = !DINamespace(name: "WTFStringImplStruct", scope: !199)
!951 = distinct !DILocation(line: 1457, column: 14, scope: !952, inlinedAt: !955)
!952 = distinct !DILexicalBlock(scope: !953, file: !223, line: 1452, column: 9)
!953 = distinct !DISubprogram(name: "free", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc19StringImplAllocator4free", scope: !954, file: !223, line: 1449, type: !20, scopeLine: 1449, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!954 = !DINamespace(name: "StringImplAllocator", scope: !199)
!955 = distinct !DILocation(line: 177, column: 18, scope: !956, inlinedAt: !957)
!956 = distinct !DISubprogram(name: "raw_free", linkageName: "_RNvMs3_Cs9SN9c7tmF9T_9bun_allocNtB5_12StdAllocator8raw_free", scope: !247, file: !223, line: 175, type: !20, scopeLine: 175, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!957 = !DILocation(line: 93, column: 27, scope: !958)
!958 = distinct !DILexicalBlock(scope: !929, file: !923, line: 90, column: 17)
!959 = !DILocation(line: 1320, column: 12, scope: !960, inlinedAt: !951)
!960 = distinct !DILexicalBlock(scope: !949, file: !223, line: 1316, column: 9)
!961 = !DILocation(line: 1327, column: 18, scope: !960, inlinedAt: !951)
!962 = !DILocation(line: 1328, column: 6, scope: !949, inlinedAt: !951)
!963 = !DILocation(line: 177, column: 18, scope: !956, inlinedAt: !964)
!964 = !DILocation(line: 189, column: 14, scope: !965, inlinedAt: !943)
!965 = distinct !DILexicalBlock(scope: !942, file: !223, line: 187, column: 9)
!966 = !DILocation(line: 190, column: 6, scope: !942, inlinedAt: !943)
!967 = distinct !DISubprogram(name: "alloc_with_z_allocator", linkageName: "_RNvMs_NtCs9SN9c7tmF9T_9bun_alloc5basicNtB4_10ZAllocator22alloc_with_z_allocator", scope: !968, file: !240, line: 148, type: !20, scopeLine: 148, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!968 = !DINamespace(name: "ZAllocator", scope: !242)
!969 = !DILocation(line: 39, column: 9, scope: !970, inlinedAt: !971)
!970 = distinct !DISubprogram(name: "to_byte_units", linkageName: "_RNvMCs9SN9c7tmF9T_9bun_allocNtB2_9Alignment13to_byte_units", scope: !587, file: !223, line: 38, type: !20, scopeLine: 38, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!971 = distinct !DILocation(line: 124, column: 77, scope: !972, inlinedAt: !973)
!972 = distinct !DISubprogram(name: "aligned_alloc", linkageName: "_RNvMs_NtCs9SN9c7tmF9T_9bun_alloc5basicNtB4_10ZAllocator13aligned_alloc", scope: !968, file: !240, line: 123, type: !20, scopeLine: 123, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!973 = distinct !DILocation(line: 154, column: 9, scope: !967)
!974 = !DILocation(line: 503, column: 5, scope: !975, inlinedAt: !976)
!975 = distinct !DISubprogram(name: "must_use_aligned_alloc", linkageName: "_RNvNtCsguFFgRZA9Ru_16bun_mimalloc_sys8mimalloc22must_use_aligned_alloc", scope: !233, file: !232, line: 502, type: !20, scopeLine: 502, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!976 = distinct !DILocation(line: 522, column: 8, scope: !977, inlinedAt: !978)
!977 = distinct !DISubprogram(name: "mi_zalloc_auto_align", linkageName: "_RNvNtCsguFFgRZA9Ru_16bun_mimalloc_sys8mimalloc20mi_zalloc_auto_align", scope: !233, file: !232, line: 521, type: !20, scopeLine: 521, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!978 = distinct !DILocation(line: 476, column: 9, scope: !979, inlinedAt: !980)
!979 = distinct !DISubprogram(name: "zalloc_aligned", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc13default_alloc14zalloc_aligned", scope: !237, file: !223, line: 475, type: !20, scopeLine: 475, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!980 = distinct !DILocation(line: 124, column: 32, scope: !972, inlinedAt: !973)
!981 = !DILocation(line: 522, column: 8, scope: !977, inlinedAt: !978)
!982 = !DILocation(line: 525, column: 9, scope: !977, inlinedAt: !978)
!983 = !DILocation(line: 523, column: 9, scope: !977, inlinedAt: !978)
!984 = !DILocation(line: 0, scope: !977, inlinedAt: !978)
!985 = !DILocation(line: 155, column: 6, scope: !967)
!986 = distinct !DISubprogram(name: "resize_with_z_allocator", linkageName: "_RNvMs_NtCs9SN9c7tmF9T_9bun_alloc5basicNtB4_10ZAllocator23resize_with_z_allocator", scope: !968, file: !240, line: 157, type: !20, scopeLine: 157, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!987 = !DILocation(line: 164, column: 12, scope: !986)
!988 = !DILocation(line: 447, column: 25, scope: !989, inlinedAt: !990)
!989 = distinct !DISubprogram(name: "usable_size", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc13default_alloc11usable_size", scope: !237, file: !223, line: 431, type: !20, scopeLine: 431, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!990 = distinct !DILocation(line: 145, column: 18, scope: !991, inlinedAt: !992)
!991 = distinct !DISubprogram(name: "aligned_alloc_size", linkageName: "_RNvMs_NtCs9SN9c7tmF9T_9bun_alloc5basicNtB4_10ZAllocator18aligned_alloc_size", scope: !968, file: !240, line: 143, type: !20, scopeLine: 143, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!992 = distinct !DILocation(line: 168, column: 24, scope: !986)
!993 = !DILocation(line: 169, column: 12, scope: !994)
!994 = distinct !DILexicalBlock(scope: !986, file: !240, line: 168, column: 9)
!995 = !DILocation(line: 157, scope: !986)
!996 = !DILocation(line: 174, column: 6, scope: !986)
!997 = distinct !DISubprogram(name: "free", linkageName: "_RNvMs_NtNtCs9SN9c7tmF9T_9bun_alloc8fallback1zNtB4_1Z4free", scope: !999, file: !998, line: 72, type: !20, scopeLine: 72, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!998 = !DIFile(filename: "src/bun_alloc/fallback/z.rs", directory: "/Users/scc/code/researcher/bun", checksumkind: CSK_MD5, checksum: "8002669ff01091eb03fbd3dd85d4c4ba")
!999 = !DINamespace(name: "Z", scope: !1000)
!1000 = !DINamespace(name: "z", scope: !1001)
!1001 = !DINamespace(name: "fallback", scope: !199)
!1002 = !DILocation(line: 112, column: 18, scope: !1003, inlinedAt: !1007)
!1003 = distinct !DILexicalBlock(scope: !1005, file: !1004, line: 110, column: 9)
!1004 = !DIFile(filename: "src/bun_alloc/fallback.rs", directory: "/Users/scc/code/researcher/bun", checksumkind: CSK_MD5, checksum: "dbc88d119a4878ac0fd28a158f649465")
!1005 = distinct !DISubprogram(name: "raw_free", linkageName: "_RNvMNtCs9SN9c7tmF9T_9bun_alloc8fallbackNtB2_10CAllocator8raw_free", scope: !1006, file: !1004, line: 99, type: !20, scopeLine: 99, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1006 = !DINamespace(name: "CAllocator", scope: !1001)
!1007 = !DILocation(line: 78, column: 21, scope: !997)
!1008 = !DILocation(line: 79, column: 6, scope: !997)
!1009 = distinct !DISubprogram(name: "alloc", linkageName: "_RNvMs_NtNtCs9SN9c7tmF9T_9bun_alloc8fallback1zNtB4_1Z5alloc", scope: !999, file: !998, line: 25, type: !20, scopeLine: 25, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1010 = !DILocation(line: 39, column: 9, scope: !1011, inlinedAt: !1012)
!1011 = distinct !DISubprogram(name: "to_byte_units", linkageName: "_RNvMCs9SN9c7tmF9T_9bun_allocNtB2_9Alignment13to_byte_units", scope: !587, file: !223, line: 38, type: !20, scopeLine: 38, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1012 = !DILocation(line: 20, column: 31, scope: !1013, inlinedAt: !1014)
!1013 = distinct !DISubprogram(name: "raw_alloc", linkageName: "_RNvMNtCs9SN9c7tmF9T_9bun_alloc8fallbackNtB2_10CAllocator9raw_alloc", scope: !1006, file: !1004, line: 17, type: !20, scopeLine: 17, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1014 = !DILocation(line: 31, column: 34, scope: !1009)
!1015 = !DILocation(line: 23, column: 16, scope: !1016, inlinedAt: !1014)
!1016 = distinct !DILexicalBlock(scope: !1013, file: !1004, line: 20, column: 9)
!1017 = !DILocation(line: 32, column: 21, scope: !1016, inlinedAt: !1014)
!1018 = !DILocation(line: 24, column: 17, scope: !1016, inlinedAt: !1014)
!1019 = !DILocation(line: 0, scope: !1016, inlinedAt: !1014)
!1020 = !DILocation(line: 36, column: 12, scope: !1021, inlinedAt: !1014)
!1021 = distinct !DILexicalBlock(scope: !1016, file: !1004, line: 22, column: 9)
!1022 = !DILocation(line: 713, column: 9, scope: !1023, inlinedAt: !1024)
!1023 = distinct !DISubprogram(name: "write_bytes<u8>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr11write_byteshECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 701, type: !20, scopeLine: 701, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1024 = !DILocation(line: 33, column: 18, scope: !1025)
!1025 = distinct !DILexicalBlock(scope: !1009, file: !998, line: 31, column: 9)
!1026 = !DILocation(line: 35, column: 6, scope: !1009)
!1027 = !DILocation(line: 0, scope: !1009)
!1028 = distinct !DISubprogram(name: "resize", linkageName: "_RNvMs_NtNtCs9SN9c7tmF9T_9bun_alloc8fallback1zNtB4_1Z6resize", scope: !999, file: !998, line: 37, type: !20, scopeLine: 37, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1029 = !DILocation(line: 53, column: 12, scope: !1030, inlinedAt: !1031)
!1030 = distinct !DISubprogram(name: "raw_resize", linkageName: "_RNvMNtCs9SN9c7tmF9T_9bun_alloc8fallbackNtB2_10CAllocator10raw_resize", scope: !1006, file: !1004, line: 44, type: !20, scopeLine: 44, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1031 = !DILocation(line: 44, column: 25, scope: !1028)
!1032 = !DILocation(line: 59, column: 35, scope: !1030, inlinedAt: !1031)
!1033 = !DILocation(line: 60, column: 20, scope: !1034, inlinedAt: !1031)
!1034 = distinct !DILexicalBlock(scope: !1030, file: !1004, line: 59, column: 13)
!1035 = !DILocation(line: 44, column: 13, scope: !1028)
!1036 = !DILocation(line: 59, column: 6, scope: !1028)
!1037 = !DILocation(line: 961, column: 18, scope: !1038, inlinedAt: !1039)
!1038 = distinct !DISubprogram(name: "add<u8>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrOh3addCs9SN9c7tmF9T_9bun_alloc", scope: !316, file: !315, line: 927, type: !20, scopeLine: 927, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1039 = !DILocation(line: 56, column: 56, scope: !1040)
!1040 = distinct !DILexicalBlock(scope: !1028, file: !998, line: 49, column: 9)
!1041 = !DILocation(line: 56, column: 73, scope: !1040)
!1042 = !DILocation(line: 713, column: 9, scope: !1043, inlinedAt: !1044)
!1043 = distinct !DISubprogram(name: "write_bytes<u8>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr11write_byteshECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 701, type: !20, scopeLine: 701, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1044 = !DILocation(line: 56, column: 22, scope: !1040)
!1045 = !DILocation(line: 53, column: 9, scope: !1040)
!1046 = distinct !DISubprogram(name: "eql_comptime", linkageName: "_RNvMsd_Cs9SN9c7tmF9T_9bun_allocNtB5_6String12eql_comptime", scope: !938, file: !223, line: 1571, type: !20, scopeLine: 1571, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1047 = !DILocation(line: 1529, column: 15, scope: !1048, inlinedAt: !1049)
!1048 = distinct !DISubprogram(name: "to_zig_string", linkageName: "_RNvMsd_Cs9SN9c7tmF9T_9bun_allocNtB5_6String13to_zig_string", scope: !938, file: !223, line: 1528, type: !20, scopeLine: 1528, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1049 = !DILocation(line: 1572, column: 23, scope: !1046)
!1050 = !{i8 0, i8 5}
!1051 = !DILocation(line: 1529, column: 9, scope: !1048, inlinedAt: !1049)
!1052 = !DILocation(line: 1524, column: 18, scope: !1053, inlinedAt: !1054)
!1053 = distinct !DISubprogram(name: "wtf_impl", linkageName: "_RNvMsd_Cs9SN9c7tmF9T_9bun_allocNtB5_6String8wtf_impl", scope: !938, file: !223, line: 1519, type: !20, scopeLine: 1519, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1054 = !DILocation(line: 1535, column: 40, scope: !1048, inlinedAt: !1049)
!1055 = !DILocation(line: 2447, column: 9, scope: !1056, inlinedAt: !1057)
!1056 = distinct !DISubprogram(name: "get<u32>", linkageName: "_RNvMsX_NtCsgXhsEb1m4tm_4core4cellINtB5_10UnsafeCellmE3getCs9SN9c7tmF9T_9bun_alloc", scope: !119, file: !118, line: 2443, type: !20, scopeLine: 2443, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1057 = distinct !DILocation(line: 555, column: 30, scope: !1058, inlinedAt: !1059)
!1058 = distinct !DISubprogram(name: "get<u32>", linkageName: "_RNvMs8_NtCsgXhsEb1m4tm_4core4cellINtB5_4CellmE3getCs9SN9c7tmF9T_9bun_alloc", scope: !123, file: !118, line: 552, type: !20, scopeLine: 552, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1059 = distinct !DILocation(line: 1245, column: 32, scope: !1060, inlinedAt: !1061)
!1060 = distinct !DISubprogram(name: "is_8bit", linkageName: "_RNvMsc_Cs9SN9c7tmF9T_9bun_allocNtB5_19WTFStringImplStruct7is_8bit", scope: !950, file: !223, line: 1244, type: !20, scopeLine: 1244, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1061 = distinct !DILocation(line: 1391, column: 17, scope: !1062, inlinedAt: !1063)
!1062 = distinct !DISubprogram(name: "to_zig_string", linkageName: "_RNvMsc_Cs9SN9c7tmF9T_9bun_allocNtB5_19WTFStringImplStruct13to_zig_string", scope: !950, file: !223, line: 1390, type: !20, scopeLine: 1390, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1063 = distinct !DILocation(line: 1535, column: 51, scope: !1048, inlinedAt: !1049)
!1064 = !DILocation(line: 555, column: 18, scope: !1058, inlinedAt: !1059)
!1065 = !DILocation(line: 1245, column: 9, scope: !1060, inlinedAt: !1061)
!1066 = !DILocation(line: 1391, column: 12, scope: !1062, inlinedAt: !1063)
!1067 = !DILocation(line: 0, scope: !1062, inlinedAt: !1063)
!1068 = !DILocation(line: 1535, column: 65, scope: !1048, inlinedAt: !1049)
!1069 = !DILocation(line: 1533, column: 26, scope: !1048, inlinedAt: !1049)
!1070 = !DILocation(line: 0, scope: !1048, inlinedAt: !1049)
!1071 = !DILocation(line: 1118, column: 9, scope: !1072, inlinedAt: !1074)
!1072 = distinct !DISubprogram(name: "is_16bit", linkageName: "_RNvMsb_Cs9SN9c7tmF9T_9bun_allocNtB5_9ZigString8is_16bit", scope: !1073, file: !223, line: 1117, type: !20, scopeLine: 1117, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1073 = !DINamespace(name: "ZigString", scope: !199)
!1074 = !DILocation(line: 1573, column: 15, scope: !1075)
!1075 = distinct !DILexicalBlock(scope: !1046, file: !223, line: 1572, column: 9)
!1076 = !DILocation(line: 0, scope: !1075)
!1077 = !DILocation(line: 1573, column: 12, scope: !1075)
!1078 = !DILocation(line: 1162, column: 12, scope: !1079, inlinedAt: !1080)
!1079 = distinct !DISubprogram(name: "slice", linkageName: "_RNvMsb_Cs9SN9c7tmF9T_9bun_allocNtB5_9ZigString5slice", scope: !1073, file: !223, line: 1161, type: !20, scopeLine: 1161, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1080 = !DILocation(line: 1583, column: 16, scope: !1075)
!1081 = !DILocation(line: 1183, column: 12, scope: !1082, inlinedAt: !1083)
!1082 = distinct !DISubprogram(name: "utf16_slice_aligned", linkageName: "_RNvMsb_Cs9SN9c7tmF9T_9bun_allocNtB5_9ZigString19utf16_slice_aligned", scope: !1073, file: !223, line: 1182, type: !20, scopeLine: 1182, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1083 = !DILocation(line: 1574, column: 27, scope: !1075)
!1084 = !DILocation(line: 1575, column: 16, scope: !1085)
!1085 = distinct !DILexicalBlock(scope: !1075, file: !223, line: 1574, column: 13)
!1086 = !DILocation(line: 1156, column: 9, scope: !1087, inlinedAt: !1088)
!1087 = distinct !DISubprogram(name: "untagged", linkageName: "_RNvMsb_Cs9SN9c7tmF9T_9bun_allocNtB5_9ZigString8untagged", scope: !1073, file: !223, line: 1155, type: !20, scopeLine: 1155, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1088 = !DILocation(line: 1174, column: 17, scope: !1079, inlinedAt: !1080)
!1089 = !DILocation(line: 1077, column: 5, scope: !1090, inlinedAt: !1091)
!1090 = distinct !DISubprogram(name: "min<usize>", linkageName: "_RNvYjNtNtCsgXhsEb1m4tm_4core3cmp3Ord3minCs9SN9c7tmF9T_9bun_alloc", scope: !687, file: !686, line: 1072, type: !20, scopeLine: 1072, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1091 = distinct !DILocation(line: 1574, column: 8, scope: !1092, inlinedAt: !1093)
!1092 = distinct !DISubprogram(name: "min<usize>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3cmp3minjECs9SN9c7tmF9T_9bun_alloc", scope: !688, file: !686, line: 1573, type: !20, scopeLine: 1573, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1093 = !DILocation(line: 1175, column: 17, scope: !1079, inlinedAt: !1080)
!1094 = !DILocation(line: 1178, column: 6, scope: !1079, inlinedAt: !1080)
!1095 = !DILocation(line: 0, scope: !1079, inlinedAt: !1080)
!1096 = !DILocation(line: 21, column: 12, scope: !1097, inlinedAt: !1102)
!1097 = distinct !DILexicalBlock(scope: !1099, file: !1098, line: 20, column: 9)
!1098 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/slice/cmp.rs", directory: "", checksumkind: CSK_MD5, checksum: "cab080473936f63eabce81e0965c4564")
!1099 = distinct !DISubprogram(name: "eq<u8, u8>", linkageName: "_RNvXNtNtCsgXhsEb1m4tm_4core5slice3cmpShNtNtB6_3cmp9PartialEq2eqCs9SN9c7tmF9T_9bun_alloc", scope: !1100, file: !1098, line: 19, type: !20, scopeLine: 19, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1100 = !DINamespace(name: "{impl#0}", scope: !1101)
!1101 = !DINamespace(name: "cmp", scope: !337)
!1102 = !DILocation(line: 2122, column: 13, scope: !1103, inlinedAt: !1106)
!1103 = distinct !DISubprogram(name: "eq<[u8], [u8]>", linkageName: "_RNvXs7_NtNtCsgXhsEb1m4tm_4core3cmp5implsRShNtB7_9PartialEq2eqCs9SN9c7tmF9T_9bun_alloc", scope: !1104, file: !686, line: 2121, type: !20, scopeLine: 2121, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1104 = !DINamespace(name: "{impl#9}", scope: !1105)
!1105 = !DINamespace(name: "impls", scope: !688)
!1106 = !DILocation(line: 1583, column: 13, scope: !1075)
!1107 = !DILocation(line: 157, column: 13, scope: !1108, inlinedAt: !1111)
!1108 = distinct !DILexicalBlock(scope: !1109, file: !1098, line: 156, column: 13)
!1109 = distinct !DISubprogram(name: "equal_same_length<u8, u8>", linkageName: "_RNvXs3_NtNtCsgXhsEb1m4tm_4core5slice3cmphINtB5_14SlicePartialEqhE17equal_same_lengthCs9SN9c7tmF9T_9bun_alloc", scope: !1110, file: !1098, line: 151, type: !20, scopeLine: 151, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1110 = !DINamespace(name: "{impl#5}", scope: !1101)
!1111 = !DILocation(line: 24, column: 22, scope: !1097, inlinedAt: !1102)
!1112 = !DILocation(line: 21, column: 9, scope: !1097, inlinedAt: !1102)
!1113 = !DILocation(line: 404, column: 18, scope: !1114, inlinedAt: !1115)
!1114 = distinct !DISubprogram(name: "as_ptr<u16>", linkageName: "_RNvMs1_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNulltE6as_ptrCs9SN9c7tmF9T_9bun_alloc", scope: !371, file: !348, line: 398, type: !20, scopeLine: 398, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1115 = !DILocation(line: 102, column: 69, scope: !1116, inlinedAt: !1119)
!1116 = distinct !DILexicalBlock(scope: !1117, file: !332, line: 98, column: 9)
!1117 = distinct !DILexicalBlock(scope: !1118, file: !332, line: 97, column: 9)
!1118 = distinct !DISubprogram(name: "new<u16>", linkageName: "_RNvMs4_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB5_4ItertE3newCs9SN9c7tmF9T_9bun_alloc", scope: !335, file: !332, line: 96, type: !20, scopeLine: 96, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1119 = !DILocation(line: 1042, column: 9, scope: !1120, inlinedAt: !1121)
!1120 = distinct !DISubprogram(name: "iter<u16>", linkageName: "_RNvMNtCsgXhsEb1m4tm_4core5sliceSt4iterCs9SN9c7tmF9T_9bun_alloc", scope: !341, file: !340, line: 1041, type: !20, scopeLine: 1041, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1121 = !DILocation(line: 1578, column: 18, scope: !1085)
!1122 = !DILocation(line: 2493, column: 9, scope: !1123, inlinedAt: !1129)
!1123 = distinct !DILexicalBlock(scope: !1125, file: !1124, line: 2492, column: 9)
!1124 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/iter/traits/iterator.rs", directory: "", checksumkind: CSK_MD5, checksum: "716f5957bf5f5ca4e70d1a53d58ba463")
!1125 = distinct !DISubprogram(name: "try_fold<core::iter::adapters::zip::Zip<core::iter::adapters::copied::Copied<core::slice::iter::Iter<u16>>, core::iter::adapters::copied::Copied<core::slice::iter::Iter<u8>>>, (), core::iter::traits::iterator::Iterator::all::check::{closure_env#0}<(u16, u8), bun_alloc::{impl#15}::eql_comptime::{closure_env#0}>, core::ops::control_flow::ControlFlow<(), ()>>", linkageName: "_RINvYINtNtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zip3ZipINtNtB8_6copied6CopiedINtNtNtBc_5slice4iter4ItertEEIBS_IB1e_hEEENtNtNtBa_6traits8iterator8Iterator8try_folduNCINvNvB1T_3all5checkTthENCNvMsd_Cs9SN9c7tmF9T_9bun_allocNtB38_6String12eql_comptime0E0INtNtNtBc_3ops12control_flow11ControlFlowuEEB38_", scope: !1126, file: !1124, line: 2486, type: !20, scopeLine: 2486, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1126 = !DINamespace(name: "Iterator", scope: !1127)
!1127 = !DINamespace(name: "iterator", scope: !1128)
!1128 = !DINamespace(name: "traits", scope: !363)
!1129 = distinct !DILocation(line: 2842, column: 14, scope: !1130, inlinedAt: !1131)
!1130 = distinct !DISubprogram(name: "all<core::iter::adapters::zip::Zip<core::iter::adapters::copied::Copied<core::slice::iter::Iter<u16>>, core::iter::adapters::copied::Copied<core::slice::iter::Iter<u8>>>, bun_alloc::{impl#15}::eql_comptime::{closure_env#0}>", linkageName: "_RINvYINtNtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zip3ZipINtNtB8_6copied6CopiedINtNtNtBc_5slice4iter4ItertEEIBS_IB1e_hEEENtNtNtBa_6traits8iterator8Iterator3allNCNvMsd_Cs9SN9c7tmF9T_9bun_allocNtB2D_6String12eql_comptime0EB2D_", scope: !1126, file: !1124, line: 2831, type: !20, scopeLine: 2831, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1131 = !DILocation(line: 1581, column: 18, scope: !1085)
!1132 = !DILocation(line: 306, column: 12, scope: !1133, inlinedAt: !1137)
!1133 = distinct !DISubprogram(name: "next<core::iter::adapters::copied::Copied<core::slice::iter::Iter<u16>>, core::iter::adapters::copied::Copied<core::slice::iter::Iter<u8>>>", linkageName: "_RNvXs3_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zipINtB5_3ZipINtNtB7_6copied6CopiedINtNtNtBb_5slice4iter4ItertEEIBX_IB1j_hEEEINtB5_7ZipImplBW_B1L_E4nextCs9SN9c7tmF9T_9bun_alloc", scope: !1135, file: !1134, line: 305, type: !20, scopeLine: 305, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1134 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/iter/adapters/zip.rs", directory: "", checksumkind: CSK_MD5, checksum: "3b799775cfe5a249b4485e2512707a77")
!1135 = !DINamespace(name: "{impl#5}", scope: !1136)
!1136 = !DINamespace(name: "zip", scope: !362)
!1137 = distinct !DILocation(line: 85, column: 9, scope: !1138, inlinedAt: !1140)
!1138 = distinct !DISubprogram(name: "next<core::iter::adapters::copied::Copied<core::slice::iter::Iter<u16>>, core::iter::adapters::copied::Copied<core::slice::iter::Iter<u8>>>", linkageName: "_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zipINtB4_3ZipINtNtB6_6copied6CopiedINtNtNtBa_5slice4iter4ItertEEIBW_IB1i_hEEENtNtNtB8_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc", scope: !1139, file: !1134, line: 84, type: !20, scopeLine: 84, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1139 = !DINamespace(name: "{impl#1}", scope: !1136)
!1140 = distinct !DILocation(line: 2493, column: 34, scope: !1141, inlinedAt: !1129)
!1141 = distinct !DILexicalBlock(scope: !1123, file: !1124, line: 2493, column: 41)
!1142 = !DILocation(line: 310, column: 13, scope: !1143, inlinedAt: !1137)
!1143 = distinct !DILexicalBlock(scope: !1133, file: !1134, line: 307, column: 13)
!1144 = !DILocation(line: 961, column: 18, scope: !1145, inlinedAt: !1146)
!1145 = distinct !DISubprogram(name: "add<u16>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrOt3addCs9SN9c7tmF9T_9bun_alloc", scope: !316, file: !315, line: 927, type: !20, scopeLine: 927, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1146 = distinct !DILocation(line: 429, column: 60, scope: !1147, inlinedAt: !1148)
!1147 = distinct !DISubprogram(name: "__iterator_get_unchecked<u16>", linkageName: "_RNvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB6_4ItertENtNtNtNtBa_4iter6traits8iterator8Iterator24___iterator_get_uncheckedCs9SN9c7tmF9T_9bun_alloc", scope: !356, file: !353, line: 418, type: !20, scopeLine: 418, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1148 = distinct !DILocation(line: 632, column: 23, scope: !1149, inlinedAt: !1151)
!1149 = distinct !DISubprogram(name: "try_get_unchecked<core::slice::iter::Iter<u16>>", linkageName: "_RNvXsh_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zipINtNtNtBb_5slice4iter4ItertENtB5_23SpecTrustedRandomAccess17try_get_uncheckedCs9SN9c7tmF9T_9bun_alloc", scope: !1150, file: !1134, line: 629, type: !20, scopeLine: 629, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1150 = !DINamespace(name: "{impl#19}", scope: !1136)
!1151 = distinct !DILocation(line: 612, column: 17, scope: !1152, inlinedAt: !1153)
!1152 = distinct !DISubprogram(name: "try_get_unchecked<core::slice::iter::Iter<u16>>", linkageName: "_RINvNtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zip17try_get_uncheckedINtNtNtB8_5slice4iter4ItertEECs9SN9c7tmF9T_9bun_alloc", scope: !1136, file: !1134, line: 606, type: !20, scopeLine: 606, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1153 = distinct !DILocation(line: 107, column: 19, scope: !1154, inlinedAt: !1158)
!1154 = distinct !DISubprogram(name: "__iterator_get_unchecked<core::slice::iter::Iter<u16>, u16>", linkageName: "_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters6copiedINtB4_6CopiedINtNtNtBa_5slice4iter4ItertEENtNtNtB8_6traits8iterator8Iterator24___iterator_get_uncheckedCs9SN9c7tmF9T_9bun_alloc", scope: !1156, file: !1155, line: 101, type: !20, scopeLine: 101, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1155 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/iter/adapters/copied.rs", directory: "", checksumkind: CSK_MD5, checksum: "a8d888f8d60ac75eb2c9d5156487ea4d")
!1156 = !DINamespace(name: "{impl#1}", scope: !1157)
!1157 = !DINamespace(name: "copied", scope: !362)
!1158 = distinct !DILocation(line: 313, column: 30, scope: !1143, inlinedAt: !1137)
!1159 = !DILocation(line: 107, column: 9, scope: !1154, inlinedAt: !1158)
!1160 = !{!1161, !1163, !1165, !1167}
!1161 = distinct !{!1161, !1162, !"_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters6copiedINtB4_6CopiedINtNtNtBa_5slice4iter4ItertEENtNtNtB8_6traits8iterator8Iterator24___iterator_get_uncheckedCs9SN9c7tmF9T_9bun_alloc: %self"}
!1162 = distinct !{!1162, !"_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters6copiedINtB4_6CopiedINtNtNtBa_5slice4iter4ItertEENtNtNtB8_6traits8iterator8Iterator24___iterator_get_uncheckedCs9SN9c7tmF9T_9bun_alloc"}
!1163 = distinct !{!1163, !1164, !"_RNvXs3_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zipINtB5_3ZipINtNtB7_6copied6CopiedINtNtNtBb_5slice4iter4ItertEEIBX_IB1j_hEEEINtB5_7ZipImplBW_B1L_E4nextCs9SN9c7tmF9T_9bun_alloc: %self"}
!1164 = distinct !{!1164, !"_RNvXs3_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zipINtB5_3ZipINtNtB7_6copied6CopiedINtNtNtBb_5slice4iter4ItertEEIBX_IB1j_hEEEINtB5_7ZipImplBW_B1L_E4nextCs9SN9c7tmF9T_9bun_alloc"}
!1165 = distinct !{!1165, !1166, !"_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zipINtB4_3ZipINtNtB6_6copied6CopiedINtNtNtBa_5slice4iter4ItertEEIBW_IB1i_hEEENtNtNtB8_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc: %self"}
!1166 = distinct !{!1166, !"_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zipINtB4_3ZipINtNtB6_6copied6CopiedINtNtNtBa_5slice4iter4ItertEEIBW_IB1i_hEEENtNtNtB8_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc"}
!1167 = distinct !{!1167, !1168, !"_RINvYINtNtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zip3ZipINtNtB8_6copied6CopiedINtNtNtBc_5slice4iter4ItertEEIBS_IB1e_hEEENtNtNtBa_6traits8iterator8Iterator8try_folduNCINvNvB1T_3all5checkTthENCNvMsd_Cs9SN9c7tmF9T_9bun_allocNtB38_6String12eql_comptime0E0INtNtNtBc_3ops12control_flow11ControlFlowuEEB38_: %self"}
!1168 = distinct !{!1168, !"_RINvYINtNtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zip3ZipINtNtB8_6copied6CopiedINtNtNtBc_5slice4iter4ItertEEIBS_IB1e_hEEENtNtNtBa_6traits8iterator8Iterator8try_folduNCINvNvB1T_3all5checkTthENCNvMsd_Cs9SN9c7tmF9T_9bun_allocNtB38_6String12eql_comptime0E0INtNtNtBc_3ops12control_flow11ControlFlowuEEB38_"}
!1169 = !DILocation(line: 961, column: 18, scope: !1170, inlinedAt: !1171)
!1170 = distinct !DISubprogram(name: "add<u8>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrOh3addCs9SN9c7tmF9T_9bun_alloc", scope: !316, file: !315, line: 927, type: !20, scopeLine: 927, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1171 = distinct !DILocation(line: 429, column: 60, scope: !1172, inlinedAt: !1173)
!1172 = distinct !DISubprogram(name: "__iterator_get_unchecked<u8>", linkageName: "_RNvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB6_4IterhENtNtNtNtBa_4iter6traits8iterator8Iterator24___iterator_get_uncheckedCs9SN9c7tmF9T_9bun_alloc", scope: !356, file: !353, line: 418, type: !20, scopeLine: 418, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1173 = distinct !DILocation(line: 632, column: 23, scope: !1174, inlinedAt: !1175)
!1174 = distinct !DISubprogram(name: "try_get_unchecked<core::slice::iter::Iter<u8>>", linkageName: "_RNvXsh_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zipINtNtNtBb_5slice4iter4IterhENtB5_23SpecTrustedRandomAccess17try_get_uncheckedCs9SN9c7tmF9T_9bun_alloc", scope: !1150, file: !1134, line: 629, type: !20, scopeLine: 629, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1175 = distinct !DILocation(line: 612, column: 17, scope: !1176, inlinedAt: !1177)
!1176 = distinct !DISubprogram(name: "try_get_unchecked<core::slice::iter::Iter<u8>>", linkageName: "_RINvNtNtNtCsgXhsEb1m4tm_4core4iter8adapters3zip17try_get_uncheckedINtNtNtB8_5slice4iter4IterhEECs9SN9c7tmF9T_9bun_alloc", scope: !1136, file: !1134, line: 606, type: !20, scopeLine: 606, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1177 = distinct !DILocation(line: 107, column: 19, scope: !1178, inlinedAt: !1179)
!1178 = distinct !DISubprogram(name: "__iterator_get_unchecked<core::slice::iter::Iter<u8>, u8>", linkageName: "_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters6copiedINtB4_6CopiedINtNtNtBa_5slice4iter4IterhEENtNtNtB8_6traits8iterator8Iterator24___iterator_get_uncheckedCs9SN9c7tmF9T_9bun_alloc", scope: !1156, file: !1155, line: 101, type: !20, scopeLine: 101, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1179 = distinct !DILocation(line: 313, column: 66, scope: !1143, inlinedAt: !1137)
!1180 = !DILocation(line: 107, column: 9, scope: !1178, inlinedAt: !1179)
!1181 = !{!1182, !1163, !1165, !1167}
!1182 = distinct !{!1182, !1183, !"_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters6copiedINtB4_6CopiedINtNtNtBa_5slice4iter4IterhEENtNtNtB8_6traits8iterator8Iterator24___iterator_get_uncheckedCs9SN9c7tmF9T_9bun_alloc: %self"}
!1183 = distinct !{!1183, !"_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters6copiedINtB4_6CopiedINtNtNtBa_5slice4iter4IterhEENtNtNtB8_6traits8iterator8Iterator24___iterator_get_uncheckedCs9SN9c7tmF9T_9bun_alloc"}
!1184 = !DILocation(line: 2493, column: 19, scope: !1141, inlinedAt: !1129)
!1185 = !DILocation(line: 1585, column: 6, scope: !1046)
!1186 = distinct !DISubprogram(name: "get_zone", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone", scope: !660, file: !658, line: 27, type: !20, scopeLine: 27, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1187 = !DILocation(line: 3905, column: 24, scope: !1188, inlinedAt: !1189)
!1188 = distinct !DISubprogram(name: "atomic_load<*mut std::sys::pal::unix::sync::mutex::Mutex>", linkageName: "_RINvNtNtCsgXhsEb1m4tm_4core4sync6atomic11atomic_loadONtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexECs9SN9c7tmF9T_9bun_alloc", scope: !62, file: !61, line: 3900, type: !20, scopeLine: 3900, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1189 = distinct !DILocation(line: 1732, column: 18, scope: !1190, inlinedAt: !1191)
!1190 = distinct !DISubprogram(name: "load<std::sys::pal::unix::sync::mutex::Mutex>", linkageName: "_RNvMs3_NtNtCsgXhsEb1m4tm_4core4sync6atomicINtB5_6AtomicONtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexE4loadCs9SN9c7tmF9T_9bun_alloc", scope: !67, file: !61, line: 1730, type: !20, scopeLine: 1730, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1191 = distinct !DILocation(line: 48, column: 28, scope: !1192, inlinedAt: !1193)
!1192 = distinct !DISubprogram(name: "get_or_init<std::sys::pal::unix::sync::mutex::Mutex, std::sys::sync::mutex::pthread::{impl#0}::get::{closure_env#0}>", linkageName: "_RINvMNtNtNtCsg1bLsEOY8ZL_3std3sys4sync8once_boxINtB3_7OnceBoxNtNtNtNtNtB7_3pal4unix4sync5mutex5MutexE11get_or_initNCNvMNtNtB5_5mutex7pthreadNtB1T_5Mutex3get0ECs9SN9c7tmF9T_9bun_alloc", scope: !8, file: !7, line: 47, type: !20, scopeLine: 47, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1193 = distinct !DILocation(line: 22, column: 18, scope: !1194, inlinedAt: !1196)
!1194 = distinct !DISubprogram(name: "get", linkageName: "_RNvMNtNtNtNtCsg1bLsEOY8ZL_3std3sys4sync5mutex7pthreadNtB2_5Mutex3get", scope: !1195, file: !41, line: 19, type: !20, scopeLine: 19, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1195 = !DINamespace(name: "Mutex", scope: !44)
!1196 = distinct !DILocation(line: 36, column: 23, scope: !1197, inlinedAt: !1198)
!1197 = distinct !DISubprogram(name: "lock", linkageName: "_RNvMNtNtNtNtCsg1bLsEOY8ZL_3std3sys4sync5mutex7pthreadNtB2_5Mutex4lock", scope: !1195, file: !41, line: 33, type: !20, scopeLine: 33, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1198 = distinct !DILocation(line: 492, column: 24, scope: !1199, inlinedAt: !1205)
!1199 = distinct !DISubprogram(name: "lock<()>", linkageName: "_RNvMs5_NtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutexINtB5_5MutexuE4lockCs9SN9c7tmF9T_9bun_alloc", scope: !1201, file: !1200, line: 490, type: !20, scopeLine: 490, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1200 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/std/src/sync/poison/mutex.rs", directory: "", checksumkind: CSK_MD5, checksum: "78bfced6bc07033bbd081e9ae0e8ed7e")
!1201 = !DINamespace(name: "Mutex", scope: !1202)
!1202 = !DINamespace(name: "mutex", scope: !1203)
!1203 = !DINamespace(name: "poison", scope: !1204)
!1204 = !DINamespace(name: "sync", scope: !12)
!1205 = distinct !DILocation(line: 757, column: 14, scope: !1206, inlinedAt: !1208)
!1206 = distinct !DISubprogram(name: "lock", linkageName: "_RNvMs7_Cs9SN9c7tmF9T_9bun_allocNtB5_5Mutex4lock", scope: !1207, file: !223, line: 754, type: !20, scopeLine: 754, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1207 = !DINamespace(name: "Mutex", scope: !199)
!1208 = !DILocation(line: 43, column: 23, scope: !1186)
!1209 = !{!1210}
!1210 = distinct !{!1210, !1211, !"_RNvMs5_NtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutexINtB5_5MutexuE4lockCs9SN9c7tmF9T_9bun_alloc: %_0"}
!1211 = distinct !{!1211, !"_RNvMs5_NtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutexINtB5_5MutexuE4lockCs9SN9c7tmF9T_9bun_alloc"}
!1212 = !DILocation(line: 265, column: 12, scope: !1213, inlinedAt: !1214)
!1213 = distinct !DISubprogram(name: "as_ref<std::sys::pal::unix::sync::mutex::Mutex>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrONtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5Mutex6as_refCs9SN9c7tmF9T_9bun_alloc", scope: !316, file: !315, line: 262, type: !20, scopeLine: 262, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1214 = distinct !DILocation(line: 49, column: 28, scope: !1215, inlinedAt: !1193)
!1215 = distinct !DILexicalBlock(scope: !1192, file: !7, line: 48, column: 9)
!1216 = !DILocation(line: 51, column: 26, scope: !1215, inlinedAt: !1193)
!1217 = !DILocation(line: 53, column: 5, scope: !1192, inlinedAt: !1193)
!1218 = !DILocation(line: 0, scope: !1215, inlinedAt: !1193)
!1219 = !DILocation(line: 36, column: 29, scope: !1197, inlinedAt: !1198)
!1220 = !DILocation(line: 3904, column: 24, scope: !290, inlinedAt: !1221)
!1221 = distinct !DILocation(line: 2870, column: 26, scope: !1222, inlinedAt: !1223)
!1222 = distinct !DISubprogram(name: "load", linkageName: "_RNvMs1u_NtNtCsgXhsEb1m4tm_4core4sync6atomicINtB6_6AtomicjE4load", scope: !67, file: !61, line: 2868, type: !20, scopeLine: 2868, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1223 = distinct !DILocation(line: 464, column: 31, scope: !1224, inlinedAt: !1228)
!1224 = distinct !DISubprogram(name: "count_is_zero", linkageName: "_RNvNtNtCsg1bLsEOY8ZL_3std9panicking11panic_count13count_is_zero", scope: !1226, file: !1225, line: 463, type: !20, scopeLine: 463, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1225 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/std/src/panicking.rs", directory: "", checksumkind: CSK_MD5, checksum: "0ac2307e599d52afa9e15b3337980dce")
!1226 = !DINamespace(name: "panic_count", scope: !1227)
!1227 = !DINamespace(name: "panicking", scope: !12)
!1228 = distinct !DILocation(line: 616, column: 6, scope: !1229, inlinedAt: !1230)
!1229 = distinct !DISubprogram(name: "panicking", linkageName: "_RNvNtCsg1bLsEOY8ZL_3std9panicking9panicking", scope: !1227, file: !1225, line: 615, type: !20, scopeLine: 615, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1230 = distinct !DILocation(line: 221, column: 5, scope: !1231, inlinedAt: !1235)
!1231 = distinct !DISubprogram(name: "panicking", linkageName: "_RNvNtNtCsg1bLsEOY8ZL_3std6thread9functions9panicking", scope: !1233, file: !1232, line: 220, type: !20, scopeLine: 220, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1232 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/std/src/thread/functions.rs", directory: "", checksumkind: CSK_MD5, checksum: "d7f5d2951993e9138881f2d1e8304c28")
!1233 = !DINamespace(name: "functions", scope: !1234)
!1234 = !DINamespace(name: "thread", scope: !12)
!1235 = distinct !DILocation(line: 121, column: 24, scope: !1236, inlinedAt: !1239)
!1236 = distinct !DISubprogram(name: "guard", linkageName: "_RNvMNtNtCsg1bLsEOY8ZL_3std4sync6poisonNtB2_4Flag5guard", scope: !1238, file: !1237, line: 118, type: !20, scopeLine: 118, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1237 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/std/src/sync/poison.rs", directory: "", checksumkind: CSK_MD5, checksum: "2e3c11b46f6d3701d7040e42c871708c")
!1238 = !DINamespace(name: "Flag", scope: !1203)
!1239 = distinct !DILocation(line: 720, column: 40, scope: !1240, inlinedAt: !1242)
!1240 = distinct !DISubprogram(name: "new<()>", linkageName: "_RNvMs9_NtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutexINtB5_10MutexGuarduE3newCs9SN9c7tmF9T_9bun_alloc", scope: !1241, file: !1200, line: 719, type: !20, scopeLine: 719, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1241 = !DINamespace(name: "MutexGuard", scope: !1202)
!1242 = distinct !DILocation(line: 493, column: 13, scope: !1199, inlinedAt: !1205)
!1243 = !DILocation(line: 464, column: 12, scope: !1224, inlinedAt: !1228)
!1244 = !DILocation(line: 476, column: 13, scope: !1224, inlinedAt: !1228)
!1245 = !DILocation(line: 616, column: 5, scope: !1229, inlinedAt: !1230)
!1246 = !DILocation(line: 3904, column: 24, scope: !1247, inlinedAt: !1248)
!1247 = distinct !DISubprogram(name: "atomic_load<u8>", linkageName: "_RINvNtNtCsgXhsEb1m4tm_4core4sync6atomic11atomic_loadhECs9SN9c7tmF9T_9bun_alloc", scope: !62, file: !61, line: 3900, type: !20, scopeLine: 3900, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1248 = distinct !DILocation(line: 741, column: 18, scope: !1249, inlinedAt: !1250)
!1249 = distinct !DISubprogram(name: "load", linkageName: "_RNvMs2_NtNtCsgXhsEb1m4tm_4core4sync6atomicINtB5_6AtomicbE4load", scope: !67, file: !61, line: 738, type: !20, scopeLine: 738, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1250 = distinct !DILocation(line: 141, column: 21, scope: !1251, inlinedAt: !1252)
!1251 = distinct !DISubprogram(name: "get", linkageName: "_RNvMNtNtCsg1bLsEOY8ZL_3std4sync6poisonNtB2_4Flag3get", scope: !1238, file: !1237, line: 140, type: !20, scopeLine: 140, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1252 = distinct !DILocation(line: 123, column: 17, scope: !1253, inlinedAt: !1239)
!1253 = distinct !DILexicalBlock(scope: !1236, file: !1237, line: 119, column: 9)
!1254 = !DILocation(line: 614, column: 9, scope: !1255, inlinedAt: !1256)
!1255 = distinct !DISubprogram(name: "non_null<alloc::alloc::Global, (alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone)>", linkageName: "_RINvMs2_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB6_11RawVecInner8non_nullTINtNtB8_3vec3VechEB12_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEEB1t_", scope: !803, file: !797, line: 613, type: !20, scopeLine: 613, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1256 = !DILocation(line: 609, column: 14, scope: !1257, inlinedAt: !1258)
!1257 = distinct !DISubprogram(name: "ptr<alloc::alloc::Global, (alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone)>", linkageName: "_RINvMs2_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB6_11RawVecInner3ptrTINtNtB8_3vec3VechEBX_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEEB1n_", scope: !803, file: !797, line: 608, type: !20, scopeLine: 608, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1258 = !DILocation(line: 296, column: 20, scope: !1259, inlinedAt: !1260)
!1259 = distinct !DISubprogram(name: "ptr<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone), alloc::alloc::Global>", linkageName: "_RNvMs0_NtCskhhhlZ4wWGP_5alloc7raw_vecINtB5_6RawVecTINtNtB7_3vec3VechEBN_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE3ptrB1d_", scope: !798, file: !797, line: 295, type: !20, scopeLine: 295, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1260 = !DILocation(line: 1941, column: 18, scope: !1261, inlinedAt: !1265)
!1261 = distinct !DISubprogram(name: "as_ptr<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone), alloc::alloc::Global>", linkageName: "_RNvMs_NtCskhhhlZ4wWGP_5alloc3vecINtB4_3VecTIBv_hEBF_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE6as_ptrBT_", scope: !1263, file: !1262, line: 1938, type: !20, scopeLine: 1938, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1262 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/alloc/src/vec/mod.rs", directory: "", checksumkind: CSK_MD5, checksum: "685b3aad034f5cfc16457d85d2c04ae5")
!1263 = !DINamespace(name: "Vec", scope: !1264)
!1264 = !DINamespace(name: "vec", scope: !19)
!1265 = !DILocation(line: 1840, column: 76, scope: !1266, inlinedAt: !1267)
!1266 = distinct !DISubprogram(name: "as_slice<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone), alloc::alloc::Global>", linkageName: "_RNvMs_NtCskhhhlZ4wWGP_5alloc3vecINtB4_3VecTIBv_hEBF_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE8as_sliceBT_", scope: !1263, file: !1262, line: 1823, type: !20, scopeLine: 1823, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1267 = !DILocation(line: 3760, column: 14, scope: !1268, inlinedAt: !1270)
!1268 = distinct !DISubprogram(name: "deref<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone), alloc::alloc::Global>", linkageName: "_RNvXs7_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VecTIBw_hEBG_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEENtNtNtCsgXhsEb1m4tm_4core3ops5deref5Deref5derefBU_", scope: !1269, file: !1262, line: 3759, type: !20, scopeLine: 3759, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1269 = !DINamespace(name: "{impl#9}", scope: !1264)
!1270 = !DILocation(line: 47, column: 30, scope: !1271)
!1271 = distinct !DILexicalBlock(scope: !1272, file: !658, line: 47, column: 82)
!1272 = distinct !DILexicalBlock(scope: !1273, file: !658, line: 46, column: 5)
!1273 = distinct !DILexicalBlock(scope: !1186, file: !658, line: 43, column: 5)
!1274 = !DILocation(line: 1840, column: 86, scope: !1266, inlinedAt: !1267)
!1275 = !DILocation(line: 961, column: 18, scope: !1276, inlinedAt: !1277)
!1276 = distinct !DISubprogram(name: "add<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone)>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrOTINtNtCskhhhlZ4wWGP_5alloc3vec3VechEBD_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneE3addB1k_", scope: !316, file: !315, line: 927, type: !20, scopeLine: 927, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1277 = !DILocation(line: 102, column: 78, scope: !1278, inlinedAt: !1281)
!1278 = distinct !DILexicalBlock(scope: !1279, file: !332, line: 98, column: 9)
!1279 = distinct !DILexicalBlock(scope: !1280, file: !332, line: 97, column: 9)
!1280 = distinct !DISubprogram(name: "new<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone)>", linkageName: "_RNvMs4_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB5_4IterTINtNtCskhhhlZ4wWGP_5alloc3vec3VechEBP_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE3newB1w_", scope: !335, file: !332, line: 96, type: !20, scopeLine: 96, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1281 = !DILocation(line: 1042, column: 9, scope: !1282, inlinedAt: !1283)
!1282 = distinct !DISubprogram(name: "iter<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone)>", linkageName: "_RNvMNtCsgXhsEb1m4tm_4core5sliceSTINtNtCskhhhlZ4wWGP_5alloc3vec3VechEBv_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneE4iterB1c_", scope: !341, file: !340, line: 1041, type: !20, scopeLine: 1041, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1283 = !DILocation(line: 47, column: 36, scope: !1271)
!1284 = !DILocation(line: 1714, column: 9, scope: !1285, inlinedAt: !1286)
!1285 = distinct !DISubprogram(name: "eq<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone)>", linkageName: "_RNvXsd_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullTINtNtCskhhhlZ4wWGP_5alloc3vec3VechEBU_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEENtNtB9_3cmp9PartialEq2eqB1B_", scope: !349, file: !348, line: 1713, type: !20, scopeLine: 1713, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1286 = distinct !DILocation(line: 180, column: 28, scope: !1287, inlinedAt: !1290)
!1287 = distinct !DILexicalBlock(scope: !1288, file: !353, line: 162, column: 17)
!1288 = distinct !DILexicalBlock(scope: !1289, file: !353, line: 161, column: 17)
!1289 = distinct !DISubprogram(name: "next<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone)>", linkageName: "_RNvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB6_4IterTINtNtCskhhhlZ4wWGP_5alloc3vec3VechEBQ_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEENtNtNtNtBa_4iter6traits8iterator8Iterator4nextB1x_", scope: !356, file: !353, line: 157, type: !20, scopeLine: 157, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1290 = distinct !DILocation(line: 348, column: 42, scope: !1291, inlinedAt: !1293)
!1291 = distinct !DILexicalBlock(scope: !1292, file: !353, line: 348, column: 49)
!1292 = distinct !DISubprogram(name: "find<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone), bun_alloc::heap_breakdown::get_zone::{closure_env#0}>", linkageName: "_RINvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB7_4IterTINtNtCskhhhlZ4wWGP_5alloc3vec3VechEBR_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEENtNtNtNtBb_4iter6traits8iterator8Iterator4findNCNvB1w_8get_zone0EB1y_", scope: !356, file: !353, line: 343, type: !20, scopeLine: 343, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1293 = distinct !DILocation(line: 47, column: 43, scope: !1271)
!1294 = !DILocation(line: 180, column: 28, scope: !1287, inlinedAt: !1290)
!1295 = !DILocation(line: 656, column: 28, scope: !1296, inlinedAt: !1297)
!1296 = distinct !DISubprogram(name: "add<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone)>", linkageName: "_RNvMs1_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullTINtNtCskhhhlZ4wWGP_5alloc3vec3VechEBU_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE3addB1B_", scope: !371, file: !348, line: 648, type: !20, scopeLine: 648, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1297 = distinct !DILocation(line: 185, column: 40, scope: !1287, inlinedAt: !1290)
!1298 = !DILocation(line: 1840, column: 86, scope: !1299, inlinedAt: !1300)
!1299 = distinct !DISubprogram(name: "as_slice<u8, alloc::alloc::Global>", linkageName: "_RNvMs_NtCskhhhlZ4wWGP_5alloc3vecINtB4_3VechE8as_sliceCs9SN9c7tmF9T_9bun_alloc", scope: !1263, file: !1262, line: 1823, type: !20, scopeLine: 1823, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1300 = distinct !DILocation(line: 47, column: 62, scope: !1301, inlinedAt: !1304)
!1301 = distinct !DILexicalBlock(scope: !1302, file: !658, line: 47, column: 60)
!1302 = distinct !DISubprogram(name: "{closure#0}", linkageName: "_RNCNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone0B5_", scope: !1303, file: !658, line: 47, type: !20, scopeLine: 47, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1303 = !DINamespace(name: "get_zone", scope: !660)
!1304 = distinct !DILocation(line: 349, column: 24, scope: !1291, inlinedAt: !1293)
!1305 = !{!1306, !1308, !1309, !1311}
!1306 = distinct !{!1306, !1307, !"_RNCNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone0B5_: %_1"}
!1307 = distinct !{!1307, !"_RNCNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone0B5_"}
!1308 = distinct !{!1308, !1307, !"_RNCNvNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown8get_zone0B5_: %_2"}
!1309 = distinct !{!1309, !1310, !"_RINvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB7_4IterTINtNtCskhhhlZ4wWGP_5alloc3vec3VechEBR_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEENtNtNtNtBb_4iter6traits8iterator8Iterator4findNCNvB1w_8get_zone0EB1y_: %self"}
!1310 = distinct !{!1310, !"_RINvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB7_4IterTINtNtCskhhhlZ4wWGP_5alloc3vec3VechEBR_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEENtNtNtNtBb_4iter6traits8iterator8Iterator4findNCNvB1w_8get_zone0EB1y_"}
!1311 = distinct !{!1311, !1310, !"_RINvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB7_4IterTINtNtCskhhhlZ4wWGP_5alloc3vec3VechEBR_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEENtNtNtNtBb_4iter6traits8iterator8Iterator4findNCNvB1w_8get_zone0EB1y_: argument 1"}
!1312 = !DILocation(line: 21, column: 12, scope: !1313, inlinedAt: !1315)
!1313 = distinct !DILexicalBlock(scope: !1314, file: !1098, line: 20, column: 9)
!1314 = distinct !DISubprogram(name: "eq<u8, u8>", linkageName: "_RNvXNtNtCsgXhsEb1m4tm_4core5slice3cmpShNtNtB6_3cmp9PartialEq2eqCs9SN9c7tmF9T_9bun_alloc", scope: !1100, file: !1098, line: 19, type: !20, scopeLine: 19, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1315 = distinct !DILocation(line: 2122, column: 13, scope: !1316, inlinedAt: !1317)
!1316 = distinct !DISubprogram(name: "eq<[u8], [u8]>", linkageName: "_RNvXs7_NtNtCsgXhsEb1m4tm_4core3cmp5implsRShNtB7_9PartialEq2eqCs9SN9c7tmF9T_9bun_alloc", scope: !1104, file: !686, line: 2121, type: !20, scopeLine: 2121, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1317 = distinct !DILocation(line: 47, column: 60, scope: !1301, inlinedAt: !1304)
!1318 = !DILocation(line: 614, column: 9, scope: !1319, inlinedAt: !1320)
!1319 = distinct !DISubprogram(name: "non_null<alloc::alloc::Global, u8>", linkageName: "_RINvMs2_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB6_11RawVecInner8non_nullhECs9SN9c7tmF9T_9bun_alloc", scope: !803, file: !797, line: 613, type: !20, scopeLine: 613, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1320 = distinct !DILocation(line: 609, column: 14, scope: !1321, inlinedAt: !1322)
!1321 = distinct !DISubprogram(name: "ptr<alloc::alloc::Global, u8>", linkageName: "_RINvMs2_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB6_11RawVecInner3ptrhECs9SN9c7tmF9T_9bun_alloc", scope: !803, file: !797, line: 608, type: !20, scopeLine: 608, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1322 = distinct !DILocation(line: 296, column: 20, scope: !1323, inlinedAt: !1324)
!1323 = distinct !DISubprogram(name: "ptr<u8, alloc::alloc::Global>", linkageName: "_RNvMs0_NtCskhhhlZ4wWGP_5alloc7raw_vecINtB5_6RawVechE3ptrCs9SN9c7tmF9T_9bun_alloc", scope: !798, file: !797, line: 295, type: !20, scopeLine: 295, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1324 = distinct !DILocation(line: 1941, column: 18, scope: !1325, inlinedAt: !1326)
!1325 = distinct !DISubprogram(name: "as_ptr<u8, alloc::alloc::Global>", linkageName: "_RNvMs_NtCskhhhlZ4wWGP_5alloc3vecINtB4_3VechE6as_ptrCs9SN9c7tmF9T_9bun_alloc", scope: !1263, file: !1262, line: 1938, type: !20, scopeLine: 1938, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1326 = distinct !DILocation(line: 1840, column: 76, scope: !1299, inlinedAt: !1300)
!1327 = !DILocation(line: 157, column: 13, scope: !1328, inlinedAt: !1330)
!1328 = distinct !DILexicalBlock(scope: !1329, file: !1098, line: 156, column: 13)
!1329 = distinct !DISubprogram(name: "equal_same_length<u8, u8>", linkageName: "_RNvXs3_NtNtCsgXhsEb1m4tm_4core5slice3cmphINtB5_14SlicePartialEqhE17equal_same_lengthCs9SN9c7tmF9T_9bun_alloc", scope: !1110, file: !1098, line: 151, type: !20, scopeLine: 151, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1330 = distinct !DILocation(line: 24, column: 22, scope: !1313, inlinedAt: !1315)
!1331 = !DILocation(line: 349, column: 24, scope: !1291, inlinedAt: !1293)
!1332 = !DILocation(line: 48, column: 16, scope: !1271)
!1333 = !DILocation(line: 129, column: 13, scope: !1334, inlinedAt: !1335)
!1334 = distinct !DISubprogram(name: "done", linkageName: "_RNvMNtNtCsg1bLsEOY8ZL_3std4sync6poisonNtB2_4Flag4done", scope: !1238, file: !1237, line: 128, type: !20, scopeLine: 128, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1335 = distinct !DILocation(line: 745, column: 30, scope: !1336, inlinedAt: !1338)
!1336 = distinct !DISubprogram(name: "drop<()>", linkageName: "_RNvXsc_NtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutexINtB5_10MutexGuarduENtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4dropCs9SN9c7tmF9T_9bun_alloc", scope: !1337, file: !1200, line: 743, type: !20, scopeLine: 743, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1337 = !DINamespace(name: "{impl#14}", scope: !1202)
!1338 = distinct !DILocation(line: 809, column: 1, scope: !1339, inlinedAt: !1340)
!1339 = distinct !DISubprogram(name: "drop_in_place<std::sync::poison::mutex::MutexGuard<()>>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutex10MutexGuarduEECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 809, type: !20, scopeLine: 809, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1340 = distinct !DILocation(line: 809, column: 1, scope: !1341, inlinedAt: !1342)
!1341 = distinct !DISubprogram(name: "drop_in_place<bun_alloc::MutexGuard>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_", scope: !74, file: !73, line: 809, type: !20, scopeLine: 809, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1342 = distinct !DILocation(line: 63, column: 1, scope: !1186)
!1343 = !DILocation(line: 3904, column: 24, scope: !290, inlinedAt: !1344)
!1344 = distinct !DILocation(line: 2870, column: 26, scope: !1345, inlinedAt: !1346)
!1345 = distinct !DISubprogram(name: "load", linkageName: "_RNvMs1u_NtNtCsgXhsEb1m4tm_4core4sync6atomicINtB6_6AtomicjE4load", scope: !67, file: !61, line: 2868, type: !20, scopeLine: 2868, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1346 = distinct !DILocation(line: 464, column: 31, scope: !1347, inlinedAt: !1348)
!1347 = distinct !DISubprogram(name: "count_is_zero", linkageName: "_RNvNtNtCsg1bLsEOY8ZL_3std9panicking11panic_count13count_is_zero", scope: !1226, file: !1225, line: 463, type: !20, scopeLine: 463, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1348 = distinct !DILocation(line: 616, column: 6, scope: !1349, inlinedAt: !1350)
!1349 = distinct !DISubprogram(name: "panicking", linkageName: "_RNvNtCsg1bLsEOY8ZL_3std9panicking9panicking", scope: !1227, file: !1225, line: 615, type: !20, scopeLine: 615, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1350 = distinct !DILocation(line: 221, column: 5, scope: !1351, inlinedAt: !1352)
!1351 = distinct !DISubprogram(name: "panicking", linkageName: "_RNvNtNtCsg1bLsEOY8ZL_3std6thread9functions9panicking", scope: !1233, file: !1232, line: 220, type: !20, scopeLine: 220, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1352 = distinct !DILocation(line: 129, column: 32, scope: !1334, inlinedAt: !1335)
!1353 = !{!1354, !1356, !1358, !1360}
!1354 = distinct !{!1354, !1355, !"_RNvMNtNtCsg1bLsEOY8ZL_3std4sync6poisonNtB2_4Flag4done: %guard"}
!1355 = distinct !{!1355, !"_RNvMNtNtCsg1bLsEOY8ZL_3std4sync6poisonNtB2_4Flag4done"}
!1356 = distinct !{!1356, !1357, !"_RNvXsc_NtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutexINtB5_10MutexGuarduENtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4dropCs9SN9c7tmF9T_9bun_alloc: %self"}
!1357 = distinct !{!1357, !"_RNvXsc_NtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutexINtB5_10MutexGuarduENtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4dropCs9SN9c7tmF9T_9bun_alloc"}
!1358 = distinct !{!1358, !1359, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutex10MutexGuarduEECs9SN9c7tmF9T_9bun_alloc: %_1"}
!1359 = distinct !{!1359, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutex10MutexGuarduEECs9SN9c7tmF9T_9bun_alloc"}
!1360 = distinct !{!1360, !1361, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_: %_1"}
!1361 = distinct !{!1361, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_"}
!1362 = !DILocation(line: 464, column: 12, scope: !1347, inlinedAt: !1348)
!1363 = !DILocation(line: 476, column: 13, scope: !1347, inlinedAt: !1348)
!1364 = !DILocation(line: 129, column: 32, scope: !1334, inlinedAt: !1335)
!1365 = !DILocation(line: 3889, column: 24, scope: !1366, inlinedAt: !1367)
!1366 = distinct !DISubprogram(name: "atomic_store<u8>", linkageName: "_RINvNtNtCsgXhsEb1m4tm_4core4sync6atomic12atomic_storehECs9SN9c7tmF9T_9bun_alloc", scope: !62, file: !61, line: 3885, type: !20, scopeLine: 3885, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1367 = distinct !DILocation(line: 771, column: 13, scope: !1368, inlinedAt: !1369)
!1368 = distinct !DISubprogram(name: "store", linkageName: "_RNvMs2_NtNtCsgXhsEb1m4tm_4core4sync6atomicINtB5_6AtomicbE5store", scope: !67, file: !61, line: 767, type: !20, scopeLine: 767, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1369 = distinct !DILocation(line: 130, column: 25, scope: !1334, inlinedAt: !1335)
!1370 = !DILocation(line: 129, column: 9, scope: !1334, inlinedAt: !1335)
!1371 = !DILocation(line: 3904, column: 24, scope: !1188, inlinedAt: !1372)
!1372 = distinct !DILocation(line: 1732, column: 18, scope: !1373, inlinedAt: !1374)
!1373 = distinct !DISubprogram(name: "load<std::sys::pal::unix::sync::mutex::Mutex>", linkageName: "_RNvMs3_NtNtCsgXhsEb1m4tm_4core4sync6atomicINtB5_6AtomicONtNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys3pal4unix4sync5mutex5MutexE4loadCs9SN9c7tmF9T_9bun_alloc", scope: !67, file: !61, line: 1730, type: !20, scopeLine: 1730, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1374 = distinct !DILocation(line: 43, column: 48, scope: !1375, inlinedAt: !1376)
!1375 = distinct !DISubprogram(name: "get_unchecked<std::sys::pal::unix::sync::mutex::Mutex>", linkageName: "_RNvMNtNtNtCsg1bLsEOY8ZL_3std3sys4sync8once_boxINtB2_7OnceBoxNtNtNtNtNtB6_3pal4unix4sync5mutex5MutexE13get_uncheckedCs9SN9c7tmF9T_9bun_alloc", scope: !8, file: !7, line: 42, type: !20, scopeLine: 42, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1376 = distinct !DILocation(line: 45, column: 27, scope: !1377, inlinedAt: !1378)
!1377 = distinct !DISubprogram(name: "unlock", linkageName: "_RNvMNtNtNtNtCsg1bLsEOY8ZL_3std3sys4sync5mutex7pthreadNtB2_5Mutex6unlock", scope: !1195, file: !41, line: 42, type: !20, scopeLine: 42, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1378 = distinct !DILocation(line: 746, column: 29, scope: !1336, inlinedAt: !1338)
!1379 = !{!1356, !1358, !1360}
!1380 = !DILocation(line: 45, column: 43, scope: !1377, inlinedAt: !1378)
!1381 = !DILocation(line: 63, column: 2, scope: !1186)
!1382 = !DILocation(line: 51, column: 40, scope: !1272)
!1383 = !DILocation(line: 75, column: 9, scope: !1384, inlinedAt: !1385)
!1384 = distinct !DISubprogram(name: "is_size_alignment_valid", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core5alloc6layoutNtB2_6Layout23is_size_alignment_valid", scope: !727, file: !726, line: 74, type: !20, scopeLine: 74, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1385 = distinct !DILocation(line: 113, column: 12, scope: !1386, inlinedAt: !1387)
!1386 = distinct !DISubprogram(name: "from_size_alignment", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core5alloc6layoutNtB2_6Layout19from_size_alignment", scope: !727, file: !726, line: 109, type: !20, scopeLine: 109, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1387 = distinct !DILocation(line: 529, column: 13, scope: !1388, inlinedAt: !1390)
!1388 = distinct !DILexicalBlock(scope: !1389, file: !726, line: 527, column: 54)
!1389 = distinct !DISubprogram(name: "repeat_packed", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core5alloc6layoutNtB2_6Layout13repeat_packed", scope: !727, file: !726, line: 526, type: !20, scopeLine: 526, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1390 = distinct !DILocation(line: 901, column: 17, scope: !1391, inlinedAt: !1392)
!1391 = distinct !DISubprogram(name: "layout_array", linkageName: "_RNvNtCskhhhlZ4wWGP_5alloc7raw_vec12layout_array", scope: !799, file: !797, line: 896, type: !20, scopeLine: 896, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1392 = distinct !DILocation(line: 454, column: 28, scope: !1393, inlinedAt: !1394)
!1393 = distinct !DISubprogram(name: "try_allocate_in<alloc::alloc::Global>", linkageName: "_RNvMs4_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner15try_allocate_inCs9SN9c7tmF9T_9bun_alloc", scope: !803, file: !797, line: 446, type: !20, scopeLine: 446, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1394 = distinct !DILocation(line: 434, column: 15, scope: !1395, inlinedAt: !1396)
!1395 = distinct !DISubprogram(name: "with_capacity_in<alloc::alloc::Global>", linkageName: "_RNvMs4_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner16with_capacity_inCs9SN9c7tmF9T_9bun_alloc", scope: !803, file: !797, line: 433, type: !20, scopeLine: 433, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1396 = !DILocation(line: 177, column: 20, scope: !1397, inlinedAt: !1398)
!1397 = distinct !DISubprogram(name: "with_capacity_in<u8, alloc::alloc::Global>", linkageName: "_RNvMs3_NtCskhhhlZ4wWGP_5alloc7raw_vecINtB5_6RawVechE16with_capacity_inCs9SN9c7tmF9T_9bun_alloc", scope: !798, file: !797, line: 175, type: !20, scopeLine: 175, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1398 = !DILocation(line: 977, column: 20, scope: !1399, inlinedAt: !1400)
!1399 = distinct !DISubprogram(name: "with_capacity_in<u8, alloc::alloc::Global>", linkageName: "_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VechE16with_capacity_inCs9SN9c7tmF9T_9bun_alloc", scope: !1263, file: !1262, line: 976, type: !20, scopeLine: 976, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1400 = !DILocation(line: 524, column: 9, scope: !1401, inlinedAt: !1402)
!1401 = distinct !DISubprogram(name: "with_capacity<u8>", linkageName: "_RNvMNtCskhhhlZ4wWGP_5alloc3vecINtB2_3VechE13with_capacityCs9SN9c7tmF9T_9bun_alloc", scope: !1263, file: !1262, line: 523, type: !20, scopeLine: 523, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1402 = !DILocation(line: 51, column: 21, scope: !1272)
!1403 = !DILocation(line: 113, column: 12, scope: !1386, inlinedAt: !1387)
!1404 = !DILocation(line: 99, column: 9, scope: !16, inlinedAt: !1405)
!1405 = distinct !DILocation(line: 210, column: 73, scope: !22, inlinedAt: !1406)
!1406 = distinct !DILocation(line: 332, column: 9, scope: !896, inlinedAt: !1407)
!1407 = distinct !DILocation(line: 449, column: 14, scope: !898, inlinedAt: !1408)
!1408 = distinct !DILocation(line: 465, column: 47, scope: !1409, inlinedAt: !1394)
!1409 = distinct !DILexicalBlock(scope: !1393, file: !797, line: 454, column: 9)
!1410 = !{!1411}
!1411 = distinct !{!1411, !1412, !"_RNvMs4_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner15try_allocate_inCs9SN9c7tmF9T_9bun_alloc: %_0"}
!1412 = distinct !{!1412, !"_RNvMs4_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner15try_allocate_inCs9SN9c7tmF9T_9bun_alloc"}
!1413 = !DILocation(line: 101, column: 9, scope: !16, inlinedAt: !1405)
!1414 = !DILocation(line: 469, column: 25, scope: !1415, inlinedAt: !1394)
!1415 = distinct !DILexicalBlock(scope: !1409, file: !797, line: 464, column: 9)
!1416 = !DILocation(line: 469, column: 19, scope: !1415, inlinedAt: !1394)
!1417 = !DILocation(line: 0, scope: !1272)
!1418 = !DILocation(line: 442, column: 25, scope: !1419, inlinedAt: !1396)
!1419 = distinct !DILexicalBlock(scope: !1395, file: !797, line: 442, column: 13)
!1420 = !DILocation(line: 977, column: 9, scope: !1399, inlinedAt: !1400)
!1421 = !DILocation(line: 2907, column: 12, scope: !1422, inlinedAt: !1425)
!1422 = distinct !DILexicalBlock(scope: !1423, file: !1262, line: 2906, column: 9)
!1423 = distinct !DILexicalBlock(scope: !1424, file: !1262, line: 2904, column: 9)
!1424 = distinct !DISubprogram(name: "append_elements<u8, alloc::alloc::Global>", linkageName: "_RNvMs_NtCskhhhlZ4wWGP_5alloc3vecINtB4_3VechE15append_elementsCs9SN9c7tmF9T_9bun_alloc", scope: !1263, file: !1262, line: 2903, type: !20, scopeLine: 2903, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1425 = distinct !DILocation(line: 56, column: 23, scope: !1426, inlinedAt: !1431)
!1426 = distinct !DILexicalBlock(scope: !1428, file: !1427, line: 55, column: 9)
!1427 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/alloc/src/vec/spec_extend.rs", directory: "", checksumkind: CSK_MD5, checksum: "4ca86086df4f92d26bd5516641ae6bb5")
!1428 = distinct !DISubprogram(name: "spec_extend<u8, alloc::alloc::Global>", linkageName: "_RNvXs2_NtNtCskhhhlZ4wWGP_5alloc3vec11spec_extendINtB7_3VechEINtB5_10SpecExtendRhINtNtNtCsgXhsEb1m4tm_4core5slice4iter4IterhEE11spec_extendCs9SN9c7tmF9T_9bun_alloc", scope: !1429, file: !1427, line: 54, type: !20, scopeLine: 54, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1429 = !DINamespace(name: "{impl#4}", scope: !1430)
!1430 = !DINamespace(name: "spec_extend", scope: !1264)
!1431 = !DILocation(line: 3530, column: 14, scope: !1432, inlinedAt: !1433)
!1432 = distinct !DISubprogram(name: "extend_from_slice<u8, alloc::alloc::Global>", linkageName: "_RNvMs1_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VechE17extend_from_sliceCs9SN9c7tmF9T_9bun_alloc", scope: !1263, file: !1262, line: 3529, type: !20, scopeLine: 3529, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1433 = !DILocation(line: 52, column: 11, scope: !1434)
!1434 = distinct !DILexicalBlock(scope: !1272, file: !658, line: 51, column: 5)
!1435 = !DILocation(line: 551, column: 14, scope: !1436, inlinedAt: !1437)
!1436 = distinct !DISubprogram(name: "copy_nonoverlapping<u8>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr19copy_nonoverlappinghECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 530, type: !20, scopeLine: 530, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1437 = distinct !DILocation(line: 2909, column: 17, scope: !1422, inlinedAt: !1425)
!1438 = !{!1439}
!1439 = distinct !{!1439, !1440, !"_RNvMs_NtCskhhhlZ4wWGP_5alloc3vecINtB4_3VechE15append_elementsCs9SN9c7tmF9T_9bun_alloc: %self"}
!1440 = distinct !{!1440, !"_RNvMs_NtCskhhhlZ4wWGP_5alloc3vecINtB4_3VechE15append_elementsCs9SN9c7tmF9T_9bun_alloc"}
!1441 = !DILocation(line: 2907, column: 9, scope: !1422, inlinedAt: !1425)
!1442 = !DILocation(line: 961, column: 18, scope: !1443, inlinedAt: !1444)
!1443 = distinct !DISubprogram(name: "add<u8>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrOh3addCs9SN9c7tmF9T_9bun_alloc", scope: !316, file: !315, line: 927, type: !20, scopeLine: 927, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1444 = distinct !DILocation(line: 1044, column: 41, scope: !1445, inlinedAt: !1447)
!1445 = distinct !DILexicalBlock(scope: !1446, file: !1262, line: 1037, column: 9)
!1446 = distinct !DISubprogram(name: "push_mut<u8, alloc::alloc::Global>", linkageName: "_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VechE8push_mutCs9SN9c7tmF9T_9bun_alloc", scope: !1263, file: !1262, line: 1035, type: !20, scopeLine: 1035, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1447 = distinct !DILocation(line: 1004, column: 22, scope: !1448, inlinedAt: !1449)
!1448 = distinct !DISubprogram(name: "push<u8, alloc::alloc::Global>", linkageName: "_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VechE4pushCs9SN9c7tmF9T_9bun_alloc", scope: !1263, file: !1262, line: 1003, type: !20, scopeLine: 1003, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1449 = !DILocation(line: 53, column: 11, scope: !1434)
!1450 = !DILocation(line: 1920, column: 41, scope: !1451, inlinedAt: !1452)
!1451 = distinct !DISubprogram(name: "write<u8>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr5writehECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 1897, type: !20, scopeLine: 1897, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1452 = distinct !DILocation(line: 1045, column: 13, scope: !1453, inlinedAt: !1447)
!1453 = distinct !DILexicalBlock(scope: !1445, file: !1262, line: 1044, column: 13)
!1454 = !DILocation(line: 1046, column: 13, scope: !1453, inlinedAt: !1447)
!1455 = !DILocation(line: 99, column: 24, scope: !678, inlinedAt: !1456)
!1456 = distinct !DILocation(line: 60, column: 25, scope: !1457)
!1457 = distinct !DILexicalBlock(scope: !1434, file: !658, line: 56, column: 5)
!1458 = !DILocation(line: 100, column: 13, scope: !681, inlinedAt: !1456)
!1459 = !DILocation(line: 460, column: 12, scope: !1409, inlinedAt: !1460)
!1460 = distinct !DILocation(line: 434, column: 15, scope: !1395, inlinedAt: !1461)
!1461 = !DILocation(line: 177, column: 20, scope: !1462, inlinedAt: !1463)
!1462 = !DILexicalBlockFile(scope: !1397, file: !797, discriminator: 2)
!1463 = !DILocation(line: 977, column: 20, scope: !1464, inlinedAt: !1465)
!1464 = !DILexicalBlockFile(scope: !1399, file: !1262, discriminator: 2)
!1465 = !DILocation(line: 448, column: 29, scope: !1466, inlinedAt: !1473)
!1466 = distinct !DILexicalBlock(scope: !1468, file: !1467, line: 447, column: 17)
!1467 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/alloc/src/slice.rs", directory: "", checksumkind: CSK_MD5, checksum: "c354101fc648df7ae7a06556360deeb9")
!1468 = distinct !DISubprogram(name: "to_vec<u8, alloc::alloc::Global>", linkageName: "_RINvXs_NvMNtCskhhhlZ4wWGP_5alloc5sliceSp9to_vec_inhNtB5_10ConvertVec6to_vecNtNtBa_5alloc6GlobalECs9SN9c7tmF9T_9bun_alloc", scope: !1469, file: !1467, line: 446, type: !20, scopeLine: 446, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1469 = !DINamespace(name: "{impl#1}", scope: !1470)
!1470 = !DINamespace(name: "to_vec_in", scope: !1471)
!1471 = !DINamespace(name: "{impl#0}", scope: !1472)
!1472 = !DINamespace(name: "slice", scope: !19)
!1473 = !DILocation(line: 400, column: 16, scope: !1474, inlinedAt: !1475)
!1474 = distinct !DISubprogram(name: "to_vec_in<u8, alloc::alloc::Global>", linkageName: "_RINvMNtCskhhhlZ4wWGP_5alloc5sliceSh9to_vec_inNtNtB5_5alloc6GlobalECs9SN9c7tmF9T_9bun_alloc", scope: !1471, file: !1467, line: 396, type: !20, scopeLine: 396, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1475 = !DILocation(line: 376, column: 14, scope: !1476, inlinedAt: !1477)
!1476 = distinct !DISubprogram(name: "to_vec<u8>", linkageName: "_RNvMNtCskhhhlZ4wWGP_5alloc5sliceSh6to_vecCs9SN9c7tmF9T_9bun_alloc", scope: !1471, file: !1467, line: 372, type: !20, scopeLine: 372, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1477 = !DILocation(line: 61, column: 22, scope: !1478)
!1478 = distinct !DILexicalBlock(scope: !1457, file: !658, line: 60, column: 5)
!1479 = !DILocation(line: 99, column: 9, scope: !16, inlinedAt: !1480)
!1480 = distinct !DILocation(line: 210, column: 73, scope: !22, inlinedAt: !1481)
!1481 = distinct !DILocation(line: 332, column: 9, scope: !896, inlinedAt: !1482)
!1482 = distinct !DILocation(line: 449, column: 14, scope: !898, inlinedAt: !1483)
!1483 = distinct !DILocation(line: 465, column: 47, scope: !1409, inlinedAt: !1460)
!1484 = !{!1485}
!1485 = distinct !{!1485, !1486, !"_RNvMs4_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner15try_allocate_inCs9SN9c7tmF9T_9bun_alloc: %_0"}
!1486 = distinct !{!1486, !"_RNvMs4_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner15try_allocate_inCs9SN9c7tmF9T_9bun_alloc"}
!1487 = !DILocation(line: 101, column: 9, scope: !16, inlinedAt: !1480)
!1488 = !DILocation(line: 469, column: 25, scope: !1415, inlinedAt: !1460)
!1489 = !DILocation(line: 469, column: 19, scope: !1415, inlinedAt: !1460)
!1490 = !DILocation(line: 442, column: 25, scope: !1491, inlinedAt: !1461)
!1491 = distinct !DILexicalBlock(scope: !1395, file: !797, line: 442, column: 13)
!1492 = !DILocation(line: 1037, column: 19, scope: !1493, inlinedAt: !1494)
!1493 = distinct !DISubprogram(name: "push_mut<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone), alloc::alloc::Global>", linkageName: "_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VecTIBw_hEBG_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE8push_mutBU_", scope: !1263, file: !1262, line: 1035, type: !20, scopeLine: 1035, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1494 = distinct !DILocation(line: 1004, column: 22, scope: !1495, inlinedAt: !1496)
!1495 = distinct !DISubprogram(name: "push<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone), alloc::alloc::Global>", linkageName: "_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VecTIBw_hEBG_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE4pushBU_", scope: !1263, file: !1262, line: 1003, type: !20, scopeLine: 1003, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1496 = !DILocation(line: 61, column: 11, scope: !1478)
!1497 = !{!1498}
!1498 = distinct !{!1498, !1499, !"_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VecTIBw_hEBG_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE8push_mutBU_: %value"}
!1499 = distinct !{!1499, !"_RNvMsF_NtCskhhhlZ4wWGP_5alloc3vecINtB5_3VecTIBw_hEBG_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE8push_mutBU_"}
!1500 = !DILocation(line: 619, column: 49, scope: !1501, inlinedAt: !1502)
!1501 = distinct !DISubprogram(name: "capacity<alloc::alloc::Global>", linkageName: "_RNvMs2_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner8capacityCs9SN9c7tmF9T_9bun_alloc", scope: !803, file: !797, line: 618, type: !20, scopeLine: 618, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1502 = distinct !DILocation(line: 309, column: 20, scope: !1503, inlinedAt: !1504)
!1503 = distinct !DISubprogram(name: "capacity<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone), alloc::alloc::Global>", linkageName: "_RNvMs0_NtCskhhhlZ4wWGP_5alloc7raw_vecINtB5_6RawVecTINtNtB7_3vec3VechEBN_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE8capacityB1d_", scope: !798, file: !797, line: 308, type: !20, scopeLine: 308, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1504 = distinct !DILocation(line: 1040, column: 28, scope: !1505, inlinedAt: !1494)
!1505 = distinct !DILexicalBlock(scope: !1493, file: !1262, line: 1037, column: 9)
!1506 = !DILocation(line: 1040, column: 12, scope: !1505, inlinedAt: !1494)
!1507 = !DILocation(line: 1041, column: 22, scope: !1505, inlinedAt: !1494)
!1508 = !DILocation(line: 1040, column: 9, scope: !1505, inlinedAt: !1494)
!1509 = !DILocation(line: 614, column: 9, scope: !1510, inlinedAt: !1511)
!1510 = distinct !DISubprogram(name: "non_null<alloc::alloc::Global, (alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone)>", linkageName: "_RINvMs2_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB6_11RawVecInner8non_nullTINtNtB8_3vec3VechEB12_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEEB1t_", scope: !803, file: !797, line: 613, type: !20, scopeLine: 613, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1511 = distinct !DILocation(line: 609, column: 14, scope: !1512, inlinedAt: !1513)
!1512 = distinct !DISubprogram(name: "ptr<alloc::alloc::Global, (alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone)>", linkageName: "_RINvMs2_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB6_11RawVecInner3ptrTINtNtB8_3vec3VechEBX_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEEB1n_", scope: !803, file: !797, line: 608, type: !20, scopeLine: 608, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1513 = distinct !DILocation(line: 296, column: 20, scope: !1514, inlinedAt: !1515)
!1514 = distinct !DISubprogram(name: "ptr<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone), alloc::alloc::Global>", linkageName: "_RNvMs0_NtCskhhhlZ4wWGP_5alloc7raw_vecINtB5_6RawVecTINtNtB7_3vec3VechEBN_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE3ptrB1d_", scope: !798, file: !797, line: 295, type: !20, scopeLine: 295, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1515 = distinct !DILocation(line: 2025, column: 18, scope: !1516, inlinedAt: !1517)
!1516 = distinct !DISubprogram(name: "as_mut_ptr<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone), alloc::alloc::Global>", linkageName: "_RNvMs_NtCskhhhlZ4wWGP_5alloc3vecINtB4_3VecTIBv_hEBF_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEE10as_mut_ptrBT_", scope: !1263, file: !1262, line: 2022, type: !20, scopeLine: 2022, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1517 = distinct !DILocation(line: 1044, column: 28, scope: !1505, inlinedAt: !1494)
!1518 = !DILocation(line: 961, column: 18, scope: !1519, inlinedAt: !1520)
!1519 = distinct !DISubprogram(name: "add<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone)>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrOTINtNtCskhhhlZ4wWGP_5alloc3vec3VechEBD_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneE3addB1k_", scope: !316, file: !315, line: 927, type: !20, scopeLine: 927, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1520 = distinct !DILocation(line: 1044, column: 41, scope: !1505, inlinedAt: !1494)
!1521 = !DILocation(line: 1920, column: 41, scope: !1522, inlinedAt: !1523)
!1522 = distinct !DISubprogram(name: "write<(alloc::vec::Vec<u8, alloc::alloc::Global>, alloc::vec::Vec<u8, alloc::alloc::Global>, &bun_alloc::heap_breakdown::Zone)>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr5writeTINtNtCskhhhlZ4wWGP_5alloc3vec3VechEBy_RNtNtCs9SN9c7tmF9T_9bun_alloc14heap_breakdown4ZoneEEB1f_", scope: !74, file: !73, line: 1897, type: !20, scopeLine: 1897, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1523 = distinct !DILocation(line: 1045, column: 13, scope: !1524, inlinedAt: !1494)
!1524 = distinct !DILexicalBlock(scope: !1505, file: !1262, line: 1044, column: 13)
!1525 = !DILocation(line: 1046, column: 13, scope: !1524, inlinedAt: !1494)
!1526 = !DILocation(line: 129, column: 13, scope: !1334, inlinedAt: !1527)
!1527 = distinct !DILocation(line: 745, column: 30, scope: !1336, inlinedAt: !1528)
!1528 = distinct !DILocation(line: 809, column: 1, scope: !1339, inlinedAt: !1529)
!1529 = distinct !DILocation(line: 809, column: 1, scope: !1341, inlinedAt: !1530)
!1530 = distinct !DILocation(line: 63, column: 1, scope: !1186)
!1531 = !DILocation(line: 3904, column: 24, scope: !290, inlinedAt: !1532)
!1532 = distinct !DILocation(line: 2870, column: 26, scope: !1345, inlinedAt: !1533)
!1533 = distinct !DILocation(line: 464, column: 31, scope: !1347, inlinedAt: !1534)
!1534 = distinct !DILocation(line: 616, column: 6, scope: !1349, inlinedAt: !1535)
!1535 = distinct !DILocation(line: 221, column: 5, scope: !1351, inlinedAt: !1536)
!1536 = distinct !DILocation(line: 129, column: 32, scope: !1334, inlinedAt: !1527)
!1537 = !{!1538, !1540, !1542, !1544}
!1538 = distinct !{!1538, !1539, !"_RNvMNtNtCsg1bLsEOY8ZL_3std4sync6poisonNtB2_4Flag4done: %guard"}
!1539 = distinct !{!1539, !"_RNvMNtNtCsg1bLsEOY8ZL_3std4sync6poisonNtB2_4Flag4done"}
!1540 = distinct !{!1540, !1541, !"_RNvXsc_NtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutexINtB5_10MutexGuarduENtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4dropCs9SN9c7tmF9T_9bun_alloc: %self"}
!1541 = distinct !{!1541, !"_RNvXsc_NtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutexINtB5_10MutexGuarduENtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4dropCs9SN9c7tmF9T_9bun_alloc"}
!1542 = distinct !{!1542, !1543, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutex10MutexGuarduEECs9SN9c7tmF9T_9bun_alloc: %_1"}
!1543 = distinct !{!1543, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtNtNtCsg1bLsEOY8ZL_3std4sync6poison5mutex10MutexGuarduEECs9SN9c7tmF9T_9bun_alloc"}
!1544 = distinct !{!1544, !1545, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_: %_1"}
!1545 = distinct !{!1545, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtCs9SN9c7tmF9T_9bun_alloc10MutexGuardEBI_"}
!1546 = !DILocation(line: 464, column: 12, scope: !1347, inlinedAt: !1534)
!1547 = !DILocation(line: 476, column: 13, scope: !1347, inlinedAt: !1534)
!1548 = !DILocation(line: 129, column: 32, scope: !1334, inlinedAt: !1527)
!1549 = !DILocation(line: 3889, column: 24, scope: !1366, inlinedAt: !1550)
!1550 = distinct !DILocation(line: 771, column: 13, scope: !1368, inlinedAt: !1551)
!1551 = distinct !DILocation(line: 130, column: 25, scope: !1334, inlinedAt: !1527)
!1552 = !DILocation(line: 129, column: 9, scope: !1334, inlinedAt: !1527)
!1553 = !DILocation(line: 3904, column: 24, scope: !1188, inlinedAt: !1554)
!1554 = distinct !DILocation(line: 1732, column: 18, scope: !1373, inlinedAt: !1555)
!1555 = distinct !DILocation(line: 43, column: 48, scope: !1375, inlinedAt: !1556)
!1556 = distinct !DILocation(line: 45, column: 27, scope: !1377, inlinedAt: !1557)
!1557 = distinct !DILocation(line: 746, column: 29, scope: !1336, inlinedAt: !1528)
!1558 = !{!1540, !1542, !1544}
!1559 = !DILocation(line: 45, column: 43, scope: !1377, inlinedAt: !1557)
!1560 = !DILocation(line: 551, column: 14, scope: !1561, inlinedAt: !1562)
!1561 = distinct !DISubprogram(name: "copy_nonoverlapping<u8>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr19copy_nonoverlappinghECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 530, type: !20, scopeLine: 530, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1562 = !DILocation(line: 1252, column: 18, scope: !1563, inlinedAt: !1564)
!1563 = distinct !DISubprogram(name: "copy_to_nonoverlapping<u8>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr9const_ptrPh22copy_to_nonoverlappingCs9SN9c7tmF9T_9bun_alloc", scope: !476, file: !475, line: 1247, type: !20, scopeLine: 1247, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1564 = !DILocation(line: 454, column: 36, scope: !1565, inlinedAt: !1473)
!1565 = distinct !DILexicalBlock(scope: !1466, file: !1467, line: 448, column: 17)
!1566 = !DILocation(line: 452, column: 17, scope: !1565, inlinedAt: !1473)
!1567 = distinct !DISubprogram(name: "vtable_free", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena11vtable_free", scope: !198, file: !196, line: 743, type: !20, scopeLine: 743, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1568 = !DILocation(line: 31, column: 18, scope: !1569, inlinedAt: !1571)
!1569 = distinct !DILexicalBlock(scope: !1570, file: !240, line: 29, column: 9)
!1570 = distinct !DISubprogram(name: "mi_free_checked", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc5basic15mi_free_checked", scope: !242, file: !240, line: 16, type: !20, scopeLine: 16, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1571 = !DILocation(line: 746, column: 14, scope: !1567)
!1572 = !DILocation(line: 747, column: 2, scope: !1567)
!1573 = distinct !DISubprogram(name: "vtable_alloc", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena12vtable_alloc", scope: !198, file: !196, line: 700, type: !20, scopeLine: 700, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1574 = !DILocation(line: 39, column: 9, scope: !1575, inlinedAt: !1576)
!1575 = distinct !DISubprogram(name: "to_byte_units", linkageName: "_RNvMCs9SN9c7tmF9T_9bun_allocNtB2_9Alignment13to_byte_units", scope: !587, file: !223, line: 38, type: !20, scopeLine: 38, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1576 = !DILocation(line: 705, column: 32, scope: !1577)
!1577 = distinct !DILexicalBlock(scope: !1573, file: !196, line: 704, column: 5)
!1578 = !DILocation(line: 199, column: 9, scope: !1579, inlinedAt: !1580)
!1579 = distinct !DISubprogram(name: "heap_ptr", linkageName: "_RNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB5_13MimallocArena8heap_ptr", scope: !203, file: !196, line: 198, type: !20, scopeLine: 198, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1580 = !DILocation(line: 379, column: 48, scope: !1581, inlinedAt: !1582)
!1581 = distinct !DISubprogram(name: "aligned_alloc", linkageName: "_RNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB5_13MimallocArena13aligned_alloc", scope: !203, file: !196, line: 375, type: !20, scopeLine: 375, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1582 = !DILocation(line: 705, column: 11, scope: !1577)
!1583 = !DILocation(line: 503, column: 5, scope: !1584, inlinedAt: !1585)
!1584 = distinct !DISubprogram(name: "must_use_aligned_alloc", linkageName: "_RNvNtCsguFFgRZA9Ru_16bun_mimalloc_sys8mimalloc22must_use_aligned_alloc", scope: !233, file: !232, line: 502, type: !20, scopeLine: 502, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1585 = !DILocation(line: 680, column: 12, scope: !1586, inlinedAt: !1587)
!1586 = distinct !DISubprogram(name: "heap_alloc_maybe_aligned", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena24heap_alloc_maybe_aligned", scope: !198, file: !196, line: 677, type: !20, scopeLine: 677, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1587 = !DILocation(line: 379, column: 18, scope: !1581, inlinedAt: !1582)
!1588 = !DILocation(line: 683, column: 13, scope: !1586, inlinedAt: !1587)
!1589 = !DILocation(line: 681, column: 13, scope: !1586, inlinedAt: !1587)
!1590 = !DILocation(line: 0, scope: !1586, inlinedAt: !1587)
!1591 = !DILocation(line: 706, column: 2, scope: !1573)
!1592 = distinct !DISubprogram(name: "vtable_remap", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena12vtable_remap", scope: !198, file: !196, line: 725, type: !20, scopeLine: 725, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1593 = !DILocation(line: 39, column: 9, scope: !1594, inlinedAt: !1595)
!1594 = distinct !DISubprogram(name: "to_byte_units", linkageName: "_RNvMCs9SN9c7tmF9T_9bun_allocNtB2_9Alignment13to_byte_units", scope: !587, file: !223, line: 38, type: !20, scopeLine: 38, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1595 = !DILocation(line: 739, column: 11, scope: !1596)
!1596 = distinct !DILexicalBlock(scope: !1592, file: !196, line: 733, column: 5)
!1597 = !DILocation(line: 199, column: 9, scope: !1598, inlinedAt: !1599)
!1598 = distinct !DISubprogram(name: "heap_ptr", linkageName: "_RNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB5_13MimallocArena8heap_ptr", scope: !203, file: !196, line: 198, type: !20, scopeLine: 198, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1599 = !DILocation(line: 399, column: 52, scope: !1600, inlinedAt: !1601)
!1600 = distinct !DISubprogram(name: "remap", linkageName: "_RNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB5_13MimallocArena5remap", scope: !203, file: !196, line: 393, type: !20, scopeLine: 393, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1601 = !DILocation(line: 734, column: 11, scope: !1596)
!1602 = !DILocation(line: 399, column: 13, scope: !1600, inlinedAt: !1601)
!1603 = !DILocation(line: 741, column: 2, scope: !1592)
!1604 = distinct !DISubprogram(name: "vtable_resize", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena13vtable_resize", scope: !198, file: !196, line: 708, type: !20, scopeLine: 708, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1605 = !DILocation(line: 388, column: 19, scope: !1606, inlinedAt: !1607)
!1606 = distinct !DISubprogram(name: "resize_in_place", linkageName: "_RNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB5_13MimallocArena15resize_in_place", scope: !203, file: !196, line: 385, type: !20, scopeLine: 385, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1607 = !DILocation(line: 717, column: 11, scope: !1608)
!1608 = distinct !DILexicalBlock(scope: !1604, file: !196, line: 716, column: 5)
!1609 = !DILocation(line: 38, column: 17, scope: !1610, inlinedAt: !1612)
!1610 = !DILexicalBlockFile(scope: !1611, file: !475, discriminator: 0)
!1611 = distinct !DISubprogram(name: "runtime", linkageName: "_RNvNvMNtNtCsgXhsEb1m4tm_4core3ptr9const_ptrPp7is_null7runtime", scope: !482, file: !481, line: 2437, type: !20, scopeLine: 2437, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1612 = !DILocation(line: 2450, column: 9, scope: !1613, inlinedAt: !1617)
!1613 = !DILexicalBlockFile(scope: !1614, file: !481, discriminator: 2)
!1614 = !DILexicalBlockFile(scope: !1615, file: !481, discriminator: 0)
!1615 = distinct !DILexicalBlock(scope: !1616, file: !475, line: 25, column: 9)
!1616 = distinct !DISubprogram(name: "is_null<core::ffi::c_void>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr9const_ptrPNtNtB6_3ffi6c_void7is_nullCs9SN9c7tmF9T_9bun_alloc", scope: !476, file: !475, line: 22, type: !20, scopeLine: 22, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1617 = !DILocation(line: 23, column: 27, scope: !1618, inlinedAt: !1619)
!1618 = distinct !DISubprogram(name: "is_null<core::ffi::c_void>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrONtNtB6_3ffi6c_void7is_nullCs9SN9c7tmF9T_9bun_alloc", scope: !316, file: !315, line: 22, type: !20, scopeLine: 22, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1619 = !DILocation(line: 388, column: 69, scope: !1606, inlinedAt: !1607)
!1620 = !DILocation(line: 723, column: 2, scope: !1604)
!1621 = distinct !DISubprogram(name: "global_vtable_alloc", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arena19global_vtable_alloc", scope: !198, file: !196, line: 762, type: !20, scopeLine: 762, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1622 = !DILocation(line: 39, column: 9, scope: !1623, inlinedAt: !1624)
!1623 = distinct !DISubprogram(name: "to_byte_units", linkageName: "_RNvMCs9SN9c7tmF9T_9bun_allocNtB2_9Alignment13to_byte_units", scope: !587, file: !223, line: 38, type: !20, scopeLine: 38, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1624 = !DILocation(line: 768, column: 49, scope: !1621)
!1625 = !DILocation(line: 503, column: 5, scope: !1626, inlinedAt: !1627)
!1626 = distinct !DISubprogram(name: "must_use_aligned_alloc", linkageName: "_RNvNtCsguFFgRZA9Ru_16bun_mimalloc_sys8mimalloc22must_use_aligned_alloc", scope: !233, file: !232, line: 502, type: !20, scopeLine: 502, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1627 = !DILocation(line: 512, column: 8, scope: !1628, inlinedAt: !1629)
!1628 = distinct !DISubprogram(name: "mi_malloc_auto_align", linkageName: "_RNvNtCsguFFgRZA9Ru_16bun_mimalloc_sys8mimalloc20mi_malloc_auto_align", scope: !233, file: !232, line: 511, type: !20, scopeLine: 511, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1629 = !DILocation(line: 456, column: 9, scope: !1630, inlinedAt: !1631)
!1630 = distinct !DISubprogram(name: "malloc_aligned", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc13default_alloc14malloc_aligned", scope: !237, file: !223, line: 455, type: !20, scopeLine: 455, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1631 = !DILocation(line: 768, column: 5, scope: !1621)
!1632 = !DILocation(line: 515, column: 9, scope: !1628, inlinedAt: !1629)
!1633 = !DILocation(line: 513, column: 9, scope: !1628, inlinedAt: !1629)
!1634 = !DILocation(line: 0, scope: !1628, inlinedAt: !1629)
!1635 = !DILocation(line: 769, column: 2, scope: !1621)
!1636 = !DILocation(line: 3954, column: 24, scope: !945, inlinedAt: !1637)
!1637 = !DILocation(line: 3193, column: 26, scope: !947, inlinedAt: !1638)
!1638 = !DILocation(line: 1318, column: 14, scope: !949, inlinedAt: !1639)
!1639 = !DILocation(line: 1457, column: 14, scope: !952)
!1640 = !DILocation(line: 1320, column: 12, scope: !960, inlinedAt: !1639)
!1641 = !DILocation(line: 1327, column: 18, scope: !960, inlinedAt: !1639)
!1642 = !DILocation(line: 1328, column: 6, scope: !949, inlinedAt: !1639)
!1643 = !DILocation(line: 1458, column: 6, scope: !953)
!1644 = distinct !DISubprogram(name: "alloc", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc19StringImplAllocator5alloc", scope: !954, file: !223, line: 1432, type: !20, scopeLine: 1432, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1645 = !DILocation(line: 2447, column: 9, scope: !1646, inlinedAt: !1647)
!1646 = distinct !DISubprogram(name: "get<u32>", linkageName: "_RNvMsX_NtCsgXhsEb1m4tm_4core4cellINtB5_10UnsafeCellmE3getCs9SN9c7tmF9T_9bun_alloc", scope: !119, file: !118, line: 2443, type: !20, scopeLine: 2443, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1647 = !DILocation(line: 555, column: 30, scope: !1648, inlinedAt: !1649)
!1648 = distinct !DISubprogram(name: "get<u32>", linkageName: "_RNvMs8_NtCsgXhsEb1m4tm_4core4cellINtB5_4CellmE3getCs9SN9c7tmF9T_9bun_alloc", scope: !123, file: !118, line: 552, type: !20, scopeLine: 552, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1649 = !DILocation(line: 1245, column: 32, scope: !1650, inlinedAt: !1651)
!1650 = distinct !DISubprogram(name: "is_8bit", linkageName: "_RNvMsc_Cs9SN9c7tmF9T_9bun_allocNtB5_19WTFStringImplStruct7is_8bit", scope: !950, file: !223, line: 1244, type: !20, scopeLine: 1244, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1651 = !DILocation(line: 1249, column: 17, scope: !1652, inlinedAt: !1653)
!1652 = distinct !DISubprogram(name: "byte_length", linkageName: "_RNvMsc_Cs9SN9c7tmF9T_9bun_allocNtB5_19WTFStringImplStruct11byte_length", scope: !950, file: !223, line: 1248, type: !20, scopeLine: 1248, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1653 = !DILocation(line: 1438, column: 17, scope: !1654)
!1654 = distinct !DILexicalBlock(scope: !1644, file: !223, line: 1437, column: 9)
!1655 = !DILocation(line: 555, column: 18, scope: !1648, inlinedAt: !1649)
!1656 = !DILocation(line: 1245, column: 9, scope: !1650, inlinedAt: !1651)
!1657 = !DILocation(line: 1249, column: 12, scope: !1652, inlinedAt: !1653)
!1658 = !DILocation(line: 0, scope: !1652, inlinedAt: !1653)
!1659 = !DILocation(line: 1438, column: 12, scope: !1654)
!1660 = !DILocation(line: 3937, column: 24, scope: !1661, inlinedAt: !1662)
!1661 = distinct !DISubprogram(name: "atomic_add<u32, u32>", linkageName: "_RINvNtNtCsgXhsEb1m4tm_4core4sync6atomic10atomic_addmmECs9SN9c7tmF9T_9bun_alloc", scope: !62, file: !61, line: 3933, type: !20, scopeLine: 3933, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1662 = !DILocation(line: 3162, column: 26, scope: !1663, inlinedAt: !1664)
!1663 = distinct !DISubprogram(name: "fetch_add", linkageName: "_RNvMs16_NtNtCsgXhsEb1m4tm_4core4sync6atomicINtB6_6AtomicmE9fetch_add", scope: !67, file: !61, line: 3160, type: !20, scopeLine: 3160, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1664 = !DILocation(line: 1297, column: 14, scope: !1665, inlinedAt: !1666)
!1665 = distinct !DISubprogram(name: "ref", linkageName: "_RNvMsc_Cs9SN9c7tmF9T_9bun_allocNtB5_19WTFStringImplStruct3ref", scope: !950, file: !223, line: 1294, type: !20, scopeLine: 1294, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1666 = !DILocation(line: 1442, column: 14, scope: !1654)
!1667 = !DILocation(line: 1446, column: 18, scope: !1654)
!1668 = !DILocation(line: 1447, column: 6, scope: !1644)
!1669 = !DILocation(line: 0, scope: !1654)
!1670 = distinct !DISubprogram(name: "free", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator4free", scope: !1672, file: !1671, line: 86, type: !20, scopeLine: 86, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1671 = !DIFile(filename: "src/bun_alloc/BufferFallbackAllocator.rs", directory: "/Users/scc/code/researcher/bun", checksumkind: CSK_MD5, checksum: "26a593b98521cf50f0bc52ba12fa3126")
!1672 = !DINamespace(name: "buffer_fallback_allocator", scope: !199)
!1673 = !DILocation(line: 209, column: 20, scope: !1674, inlinedAt: !1676)
!1674 = distinct !DISubprogram(name: "owns_ptr", linkageName: "_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator8owns_ptr", scope: !1675, file: !223, line: 208, type: !20, scopeLine: 208, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1675 = !DINamespace(name: "FixedBufferAllocator", scope: !199)
!1676 = !DILocation(line: 90, column: 20, scope: !1677)
!1677 = distinct !DILexicalBlock(scope: !1670, file: !1671, line: 88, column: 5)
!1678 = !DILocation(line: 210, column: 17, scope: !1679, inlinedAt: !1676)
!1679 = distinct !DILexicalBlock(scope: !1674, file: !223, line: 209, column: 9)
!1680 = !DILocation(line: 211, column: 9, scope: !1681, inlinedAt: !1676)
!1681 = distinct !DILexicalBlock(scope: !1679, file: !223, line: 210, column: 9)
!1682 = !DILocation(line: 177, column: 18, scope: !1683, inlinedAt: !1684)
!1683 = distinct !DISubprogram(name: "raw_free", linkageName: "_RNvMs3_Cs9SN9c7tmF9T_9bun_allocNtB5_12StdAllocator8raw_free", scope: !247, file: !223, line: 175, type: !20, scopeLine: 175, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1684 = !DILocation(line: 93, column: 20, scope: !1677)
!1685 = !DILocation(line: 177, column: 37, scope: !1683, inlinedAt: !1684)
!1686 = !DILocation(line: 94, column: 2, scope: !1670)
!1687 = !DILocation(line: 254, column: 23, scope: !1688, inlinedAt: !1689)
!1688 = distinct !DISubprogram(name: "free", linkageName: "_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator4free", scope: !1675, file: !223, line: 252, type: !20, scopeLine: 252, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1689 = !DILocation(line: 91, column: 16, scope: !1677)
!1690 = !DILocation(line: 255, column: 23, scope: !1691, inlinedAt: !1689)
!1691 = distinct !DILexicalBlock(scope: !1688, file: !223, line: 254, column: 9)
!1692 = !DILocation(line: 255, column: 12, scope: !1691, inlinedAt: !1689)
!1693 = !DILocation(line: 256, column: 13, scope: !1691, inlinedAt: !1689)
!1694 = !DILocation(line: 255, column: 9, scope: !1691, inlinedAt: !1689)
!1695 = distinct !DISubprogram(name: "alloc", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator5alloc", scope: !1672, file: !1671, line: 41, type: !20, scopeLine: 41, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1696 = !DILocation(line: 45, column: 33, scope: !1697)
!1697 = distinct !DILexicalBlock(scope: !1695, file: !1671, line: 43, column: 5)
!1698 = !DILocation(line: 214, column: 20, scope: !1699, inlinedAt: !1700)
!1699 = distinct !DISubprogram(name: "alloc", linkageName: "_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator5alloc", scope: !1675, file: !223, line: 213, type: !20, scopeLine: 213, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1700 = distinct !DILocation(line: 45, column: 5, scope: !1697)
!1701 = !{!1702}
!1702 = distinct !{!1702, !1703, !"_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator5alloc: %self"}
!1703 = distinct !{!1703, !"_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator5alloc"}
!1704 = !DILocation(line: 216, column: 21, scope: !1705, inlinedAt: !1700)
!1705 = distinct !DILexicalBlock(scope: !1699, file: !223, line: 214, column: 9)
!1706 = !DILocation(line: 39, column: 9, scope: !1707, inlinedAt: !1708)
!1707 = distinct !DISubprogram(name: "to_byte_units", linkageName: "_RNvMCs9SN9c7tmF9T_9bun_allocNtB2_9Alignment13to_byte_units", scope: !587, file: !223, line: 38, type: !20, scopeLine: 38, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1708 = distinct !DILocation(line: 216, column: 42, scope: !1705, inlinedAt: !1700)
!1709 = !DILocation(line: 216, column: 14, scope: !1705, inlinedAt: !1700)
!1710 = !DILocation(line: 216, column: 13, scope: !1705, inlinedAt: !1700)
!1711 = !DILocation(line: 216, column: 65, scope: !1705, inlinedAt: !1700)
!1712 = !DILocation(line: 217, column: 23, scope: !1713, inlinedAt: !1700)
!1713 = distinct !DILexicalBlock(scope: !1705, file: !223, line: 215, column: 9)
!1714 = !DILocation(line: 910, column: 37, scope: !1715, inlinedAt: !1716)
!1715 = distinct !DISubprogram(name: "checked_add", linkageName: "_RNvMs9_NtCsgXhsEb1m4tm_4core3numj11checked_add", scope: !381, file: !380, line: 902, type: !20, scopeLine: 902, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1716 = distinct !DILocation(line: 217, column: 40, scope: !1713, inlinedAt: !1700)
!1717 = !DILocation(line: 459, column: 8, scope: !1718, inlinedAt: !1719)
!1718 = distinct !DISubprogram(name: "unlikely", linkageName: "_RNvNtCsgXhsEb1m4tm_4core10intrinsics8unlikely", scope: !858, file: !481, line: 458, type: !20, scopeLine: 458, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1719 = distinct !DILocation(line: 910, column: 16, scope: !1715, inlinedAt: !1716)
!1720 = !DILocation(line: 221, column: 9, scope: !1721, inlinedAt: !1700)
!1721 = distinct !DILexicalBlock(scope: !1713, file: !223, line: 217, column: 9)
!1722 = !DILocation(line: 222, column: 14, scope: !1721, inlinedAt: !1700)
!1723 = !DILocation(line: 1651, column: 9, scope: !1724, inlinedAt: !1725)
!1724 = distinct !DISubprogram(name: "or_else<*mut u8, bun_alloc::buffer_fallback_allocator::alloc::{closure_env#0}>", linkageName: "_RINvMNtCsgXhsEb1m4tm_4core6optionINtB3_6OptionOhE7or_elseNCNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator5alloc0EBZ_", scope: !259, file: !258, line: 1644, type: !20, scopeLine: 1644, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1725 = distinct !DILocation(line: 46, column: 10, scope: !1697)
!1726 = !DILocation(line: 145, column: 26, scope: !1727, inlinedAt: !1728)
!1727 = distinct !DISubprogram(name: "raw_alloc", linkageName: "_RNvMs3_Cs9SN9c7tmF9T_9bun_allocNtB5_12StdAllocator9raw_alloc", scope: !247, file: !223, line: 143, type: !20, scopeLine: 143, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1728 = distinct !DILocation(line: 46, column: 36, scope: !1729, inlinedAt: !1731)
!1729 = distinct !DISubprogram(name: "{closure#0}", linkageName: "_RNCNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator5alloc0B5_", scope: !1730, file: !1671, line: 46, type: !20, scopeLine: 46, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1730 = !DINamespace(name: "alloc", scope: !1672)
!1731 = distinct !DILocation(line: 1653, column: 21, scope: !1724, inlinedAt: !1725)
!1732 = !{!1733, !1735}
!1733 = distinct !{!1733, !1734, !"_RNCNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator5alloc0B5_: %_1"}
!1734 = distinct !{!1734, !"_RNCNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator5alloc0B5_"}
!1735 = distinct !{!1735, !1736, !"_RINvMNtCsgXhsEb1m4tm_4core6optionINtB3_6OptionOhE7or_elseNCNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator5alloc0EBZ_: %f"}
!1736 = distinct !{!1736, !"_RINvMNtCsgXhsEb1m4tm_4core6optionINtB3_6OptionOhE7or_elseNCNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator5alloc0EBZ_"}
!1737 = !DILocation(line: 145, column: 46, scope: !1727, inlinedAt: !1728)
!1738 = !DILocation(line: 1655, column: 5, scope: !1724, inlinedAt: !1725)
!1739 = !DILocation(line: 48, column: 2, scope: !1695)
!1740 = distinct !DISubprogram(name: "remap", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator5remap", scope: !1672, file: !1671, line: 66, type: !20, scopeLine: 66, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1741 = !DILocation(line: 209, column: 20, scope: !1742, inlinedAt: !1743)
!1742 = distinct !DISubprogram(name: "owns_ptr", linkageName: "_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator8owns_ptr", scope: !1675, file: !223, line: 208, type: !20, scopeLine: 208, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1743 = !DILocation(line: 76, column: 20, scope: !1744)
!1744 = distinct !DILexicalBlock(scope: !1740, file: !1671, line: 74, column: 5)
!1745 = !DILocation(line: 210, column: 17, scope: !1746, inlinedAt: !1743)
!1746 = distinct !DILexicalBlock(scope: !1742, file: !223, line: 209, column: 9)
!1747 = !DILocation(line: 211, column: 9, scope: !1748, inlinedAt: !1743)
!1748 = distinct !DILexicalBlock(scope: !1746, file: !223, line: 210, column: 9)
!1749 = !DILocation(line: 170, column: 26, scope: !1750, inlinedAt: !1751)
!1750 = distinct !DISubprogram(name: "raw_remap", linkageName: "_RNvMs3_Cs9SN9c7tmF9T_9bun_allocNtB5_12StdAllocator9raw_remap", scope: !247, file: !223, line: 162, type: !20, scopeLine: 162, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1751 = !DILocation(line: 82, column: 10, scope: !1744)
!1752 = !DILocation(line: 170, column: 46, scope: !1750, inlinedAt: !1751)
!1753 = !DILocation(line: 84, column: 2, scope: !1740)
!1754 = !DILocation(line: 226, column: 23, scope: !1755, inlinedAt: !1756)
!1755 = distinct !DISubprogram(name: "resize", linkageName: "_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator6resize", scope: !1675, file: !223, line: 224, type: !20, scopeLine: 224, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1756 = distinct !DILocation(line: 245, column: 17, scope: !1757, inlinedAt: !1758)
!1757 = distinct !DISubprogram(name: "remap", linkageName: "_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator5remap", scope: !1675, file: !223, line: 238, type: !20, scopeLine: 238, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1758 = !DILocation(line: 77, column: 16, scope: !1744)
!1759 = !DILocation(line: 227, column: 23, scope: !1760, inlinedAt: !1756)
!1760 = distinct !DILexicalBlock(scope: !1755, file: !223, line: 226, column: 9)
!1761 = !{!1762}
!1762 = distinct !{!1762, !1763, !"_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator6resize: %self"}
!1763 = distinct !{!1763, !"_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator6resize"}
!1764 = !{!1765}
!1765 = distinct !{!1765, !1763, !"_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator6resize: %buf.0"}
!1766 = !DILocation(line: 227, column: 12, scope: !1760, inlinedAt: !1756)
!1767 = !DILocation(line: 230, column: 23, scope: !1760, inlinedAt: !1756)
!1768 = !DILocation(line: 231, column: 12, scope: !1769, inlinedAt: !1756)
!1769 = distinct !DILexicalBlock(scope: !1760, file: !223, line: 230, column: 9)
!1770 = !DILocation(line: 234, column: 9, scope: !1769, inlinedAt: !1756)
!1771 = !DILocation(line: 0, scope: !1772, inlinedAt: !1773)
!1772 = distinct !DISubprogram(name: "unwrap_or<*mut u8>", linkageName: "_RNvMNtCsgXhsEb1m4tm_4core6optionINtB2_6OptionOhE9unwrap_orCs9SN9c7tmF9T_9bun_alloc", scope: !259, file: !258, line: 1035, type: !20, scopeLine: 1035, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1773 = !DILocation(line: 78, column: 14, scope: !1744)
!1774 = !DILocation(line: 228, column: 20, scope: !1760, inlinedAt: !1756)
!1775 = !DILocation(line: 0, scope: !1772, inlinedAt: !1776)
!1776 = !DILocation(line: 0, scope: !1744)
!1777 = distinct !DISubprogram(name: "resize", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc25buffer_fallback_allocator6resize", scope: !1672, file: !1671, line: 50, type: !20, scopeLine: 50, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1778 = !DILocation(line: 209, column: 20, scope: !1779, inlinedAt: !1780)
!1779 = distinct !DISubprogram(name: "owns_ptr", linkageName: "_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator8owns_ptr", scope: !1675, file: !223, line: 208, type: !20, scopeLine: 208, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1780 = !DILocation(line: 60, column: 20, scope: !1781)
!1781 = distinct !DILexicalBlock(scope: !1777, file: !1671, line: 58, column: 5)
!1782 = !DILocation(line: 210, column: 17, scope: !1783, inlinedAt: !1780)
!1783 = distinct !DILexicalBlock(scope: !1779, file: !223, line: 209, column: 9)
!1784 = !DILocation(line: 211, column: 9, scope: !1785, inlinedAt: !1780)
!1785 = distinct !DILexicalBlock(scope: !1783, file: !223, line: 210, column: 9)
!1786 = !DILocation(line: 158, column: 18, scope: !1787, inlinedAt: !1788)
!1787 = distinct !DISubprogram(name: "raw_resize", linkageName: "_RNvMs3_Cs9SN9c7tmF9T_9bun_allocNtB5_12StdAllocator10raw_resize", scope: !247, file: !223, line: 150, type: !20, scopeLine: 150, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1788 = !DILocation(line: 63, column: 20, scope: !1781)
!1789 = !DILocation(line: 158, column: 39, scope: !1787, inlinedAt: !1788)
!1790 = !DILocation(line: 64, column: 2, scope: !1777)
!1791 = !DILocation(line: 226, column: 23, scope: !1755, inlinedAt: !1792)
!1792 = distinct !DILocation(line: 61, column: 16, scope: !1781)
!1793 = !DILocation(line: 227, column: 23, scope: !1760, inlinedAt: !1792)
!1794 = !{!1795}
!1795 = distinct !{!1795, !1796, !"_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator6resize: %self"}
!1796 = distinct !{!1796, !"_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator6resize"}
!1797 = !{!1798}
!1798 = distinct !{!1798, !1796, !"_RNvMs4_Cs9SN9c7tmF9T_9bun_allocNtB5_20FixedBufferAllocator6resize: %buf.0"}
!1799 = !DILocation(line: 227, column: 12, scope: !1760, inlinedAt: !1792)
!1800 = !DILocation(line: 230, column: 23, scope: !1760, inlinedAt: !1792)
!1801 = !DILocation(line: 231, column: 12, scope: !1769, inlinedAt: !1792)
!1802 = !DILocation(line: 228, column: 20, scope: !1760, inlinedAt: !1792)
!1803 = !DILocation(line: 0, scope: !1760, inlinedAt: !1792)
!1804 = !DILocation(line: 234, column: 9, scope: !1769, inlinedAt: !1792)
!1805 = !DILocation(line: 236, column: 6, scope: !1755, inlinedAt: !1792)
!1806 = distinct !DISubprogram(name: "free_without_size", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc5basic17free_without_size", scope: !242, file: !240, line: 205, type: !20, scopeLine: 205, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1807 = !DILocation(line: 207, column: 14, scope: !1806)
!1808 = !DILocation(line: 208, column: 2, scope: !1806)
!1809 = distinct !DISubprogram(name: "default_allocator_free", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc5basic22default_allocator_free", scope: !242, file: !240, line: 35, type: !20, scopeLine: 35, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1810 = !DILocation(line: 424, column: 22, scope: !1811, inlinedAt: !1812)
!1811 = distinct !DISubprogram(name: "free", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc13default_alloc4free", scope: !237, file: !223, line: 417, type: !20, scopeLine: 417, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1812 = !DILocation(line: 37, column: 14, scope: !1809)
!1813 = !DILocation(line: 38, column: 2, scope: !1809)
!1814 = distinct !DISubprogram(name: "mi_free_bytes", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc8c_thunks13mi_free_bytes", scope: !1816, file: !1815, line: 39, type: !20, scopeLine: 39, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1815 = !DIFile(filename: "src/bun_alloc/c_thunks.rs", directory: "/Users/scc/code/researcher/bun", checksumkind: CSK_MD5, checksum: "c3e476461eb7f3452a7bd724adf1bc61")
!1816 = !DINamespace(name: "c_thunks", scope: !199)
!1817 = !DILocation(line: 424, column: 22, scope: !1818, inlinedAt: !1819)
!1818 = distinct !DISubprogram(name: "free", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc13default_alloc4free", scope: !237, file: !223, line: 417, type: !20, scopeLine: 417, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1819 = !DILocation(line: 41, column: 14, scope: !1814)
!1820 = !DILocation(line: 42, column: 2, scope: !1814)
!1821 = distinct !DISubprogram(name: "mi_free_opaque", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc8c_thunks14mi_free_opaque", scope: !1816, file: !1815, line: 30, type: !20, scopeLine: 30, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1822 = !DILocation(line: 424, column: 22, scope: !1823, inlinedAt: !1824)
!1823 = distinct !DISubprogram(name: "free", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc13default_alloc4free", scope: !237, file: !223, line: 417, type: !20, scopeLine: 417, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1824 = !DILocation(line: 32, column: 14, scope: !1821)
!1825 = !DILocation(line: 33, column: 2, scope: !1821)
!1826 = distinct !DISubprogram(name: "mi_malloc_items", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc8c_thunks15mi_malloc_items", scope: !1816, file: !1815, line: 21, type: !20, scopeLine: 21, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1827 = !DILocation(line: 22, column: 25, scope: !1826)
!1828 = !DILocation(line: 376, column: 13, scope: !1829, inlinedAt: !1830)
!1829 = distinct !DISubprogram(name: "malloc", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc13default_alloc6malloc", scope: !237, file: !223, line: 371, type: !20, scopeLine: 371, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1830 = !DILocation(line: 22, column: 13, scope: !1826)
!1831 = !DILocation(line: 23, column: 8, scope: !1832)
!1832 = distinct !DILexicalBlock(scope: !1826, file: !1815, line: 22, column: 5)
!1833 = !DILocation(line: 24, column: 9, scope: !1832)
!1834 = !DILocation(line: 27, column: 2, scope: !1826)
!1835 = distinct !DISubprogram(name: "free_without_size", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc8fallback17free_without_size", scope: !1001, file: !1004, line: 128, type: !20, scopeLine: 128, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1836 = !DILocation(line: 131, column: 14, scope: !1835)
!1837 = !DILocation(line: 132, column: 2, scope: !1835)
!1838 = distinct !DISubprogram(name: "map_arena", linkageName: "_RNvNvCs9SN9c7tmF9T_9bun_alloc14bss_arena_bump9map_arena", scope: !1839, file: !223, line: 1981, type: !20, scopeLine: 1981, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1839 = !DINamespace(name: "bss_arena_bump", scope: !199)
!1840 = !DILocation(line: 2039, column: 9, scope: !1841, inlinedAt: !1842)
!1841 = distinct !DISubprogram(name: "bss_mmap_noreserve", linkageName: "_RNvCs9SN9c7tmF9T_9bun_alloc18bss_mmap_noreserve", scope: !199, file: !223, line: 2025, type: !20, scopeLine: 2025, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1842 = !DILocation(line: 1982, column: 13, scope: !1838)
!1843 = !DILocation(line: 2048, column: 8, scope: !1844, inlinedAt: !1842)
!1844 = distinct !DILexicalBlock(scope: !1841, file: !223, line: 2038, column: 5)
!1845 = !DILocation(line: 1983, column: 10, scope: !1838)
!1846 = !DILocation(line: 2049, column: 9, scope: !1844, inlinedAt: !1842)
!1847 = distinct !DISubprogram(name: "visit", linkageName: "_RNvNvMs1_NtCs9SN9c7tmF9T_9bun_alloc14mimalloc_arenaNtB7_13MimallocArena15allocated_bytes5visit", scope: !1848, file: !196, line: 334, type: !20, scopeLine: 334, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1848 = !DINamespace(name: "allocated_bytes", scope: !790)
!1849 = !DILocation(line: 345, column: 27, scope: !1850)
!1850 = distinct !DILexicalBlock(scope: !1847, file: !196, line: 344, column: 17)
!1851 = !DILocation(line: 345, column: 55, scope: !1850)
!1852 = !DILocation(line: 3192, column: 26, scope: !1853, inlinedAt: !1854)
!1853 = distinct !DISubprogram(name: "overflowing_mul", linkageName: "_RNvMs9_NtCsgXhsEb1m4tm_4core3numj15overflowing_mul", scope: !381, file: !380, line: 3191, type: !20, scopeLine: 3191, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1854 = !DILocation(line: 1302, column: 31, scope: !1855, inlinedAt: !1856)
!1855 = distinct !DISubprogram(name: "checked_mul", linkageName: "_RNvMs9_NtCsgXhsEb1m4tm_4core3numj11checked_mul", scope: !381, file: !380, line: 1301, type: !20, scopeLine: 1301, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1856 = !DILocation(line: 2531, column: 24, scope: !1857, inlinedAt: !1858)
!1857 = distinct !DISubprogram(name: "saturating_mul", linkageName: "_RNvMs9_NtCsgXhsEb1m4tm_4core3numj14saturating_mul", scope: !381, file: !380, line: 2530, type: !20, scopeLine: 2530, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1858 = !DILocation(line: 345, column: 40, scope: !1850)
!1859 = !DILocation(line: 459, column: 8, scope: !1860, inlinedAt: !1861)
!1860 = distinct !DISubprogram(name: "unlikely", linkageName: "_RNvNtCsgXhsEb1m4tm_4core10intrinsics8unlikely", scope: !858, file: !481, line: 458, type: !20, scopeLine: 458, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1861 = !DILocation(line: 1303, column: 16, scope: !1862, inlinedAt: !1856)
!1862 = distinct !DILexicalBlock(scope: !1855, file: !380, line: 1302, column: 13)
!1863 = !DILocation(line: 2533, column: 25, scope: !1857, inlinedAt: !1858)
!1864 = !DILocation(line: 0, scope: !1857, inlinedAt: !1858)
!1865 = !DILocation(line: 345, column: 17, scope: !1850)
!1866 = !DILocation(line: 348, column: 10, scope: !1847)
!1867 = distinct !DISubprogram(name: "default", linkageName: "_RNvXs2_NtCs9SN9c7tmF9T_9bun_alloc9ast_allocNtB5_14ScopedAstAllocNtNtCsgXhsEb1m4tm_4core7default7Default7default", scope: !1868, file: !622, line: 302, type: !20, scopeLine: 302, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1868 = !DINamespace(name: "{impl#4}", scope: !624)
!1869 = !DILocation(line: 68, column: 25, scope: !1870, inlinedAt: !1874)
!1870 = distinct !DISubprogram(name: "{closure#0}", linkageName: "_RNCNKNvNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc15AST_ALLOC_SPARE00B7_", scope: !1872, file: !1871, line: 63, type: !20, scopeLine: 63, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1871 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/std/src/sys/thread_local/native/mod.rs", directory: "", checksumkind: CSK_MD5, checksum: "f45b912659b967b327e1af351608d593")
!1872 = !DINamespace(name: "{constant#0}", scope: !1873)
!1873 = !DINamespace(name: "AST_ALLOC_SPARE", scope: !624)
!1874 = distinct !DILocation(line: 250, column: 5, scope: !1875, inlinedAt: !1877)
!1875 = distinct !DISubprogram(name: "call_once<bun_alloc::ast_alloc::AST_ALLOC_SPARE::{constant#0}::{closure_env#0}, (core::option::Option<&mut core::option::Option<core::cell::Cell<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>>>)>", linkageName: "_RNvYNCNKNvNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc15AST_ALLOC_SPARE00INtNtNtCsgXhsEb1m4tm_4core3ops8function6FnOnceTINtNtB18_6option6OptionQIB1N_INtNtB18_4cell4CellIB1N_INtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtB8_13AstAllocStateEEEEEEE9call_onceBa_", scope: !1876, file: !541, line: 250, type: !20, scopeLine: 250, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1876 = !DINamespace(name: "FnOnce", scope: !543)
!1877 = distinct !DILocation(line: 461, column: 37, scope: !1878, inlinedAt: !1882)
!1878 = distinct !DISubprogram(name: "try_with<core::cell::Cell<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>, fn(&core::cell::Cell<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>) -> core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>, core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>", linkageName: "_RINvMs2_NtNtCsg1bLsEOY8ZL_3std6thread5localINtB6_8LocalKeyINtNtCsgXhsEb1m4tm_4core4cell4CellINtNtBZ_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEE8try_withNvMsa_BX_BU_4takeB1s_EB2r_", scope: !1880, file: !1879, line: 457, type: !20, scopeLine: 457, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1879 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/std/src/thread/local.rs", directory: "", checksumkind: CSK_MD5, checksum: "a9256a1d70f734e1147910659b28fa84")
!1880 = !DINamespace(name: "LocalKey", scope: !1881)
!1881 = !DINamespace(name: "local", scope: !1234)
!1882 = distinct !DILocation(line: 184, column: 10, scope: !1883, inlinedAt: !1884)
!1883 = distinct !DISubprogram(name: "acquire_state", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13acquire_state", scope: !624, file: !622, line: 182, type: !20, scopeLine: 182, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1884 = distinct !DILocation(line: 281, column: 35, scope: !1885, inlinedAt: !1887)
!1885 = distinct !DISubprogram(name: "new", linkageName: "_RNvMs1_NtCs9SN9c7tmF9T_9bun_alloc9ast_allocNtB5_14ScopedAstAlloc3new", scope: !1886, file: !622, line: 279, type: !20, scopeLine: 279, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1886 = !DINamespace(name: "ScopedAstAlloc", scope: !624)
!1887 = !DILocation(line: 303, column: 9, scope: !1867)
!1888 = !DILocation(line: 2447, column: 9, scope: !1889, inlinedAt: !1890)
!1889 = distinct !DISubprogram(name: "get<std::sys::thread_local::native::eager::State>", linkageName: "_RNvMsX_NtCsgXhsEb1m4tm_4core4cellINtB5_10UnsafeCellNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eager5StateE3getCs9SN9c7tmF9T_9bun_alloc", scope: !119, file: !118, line: 2443, type: !20, scopeLine: 2443, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1890 = distinct !DILocation(line: 555, column: 30, scope: !1891, inlinedAt: !1892)
!1891 = distinct !DISubprogram(name: "get<std::sys::thread_local::native::eager::State>", linkageName: "_RNvMs8_NtCsgXhsEb1m4tm_4core4cellINtB5_4CellNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eager5StateE3getCs9SN9c7tmF9T_9bun_alloc", scope: !123, file: !118, line: 552, type: !20, scopeLine: 552, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1892 = distinct !DILocation(line: 35, column: 26, scope: !1893, inlinedAt: !1895)
!1893 = distinct !DISubprogram(name: "get<core::cell::Cell<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>>", linkageName: "_RNvMNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eagerINtB2_7StorageINtNtCsgXhsEb1m4tm_4core4cell4CellINtNtB1g_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEE3getB2J_", scope: !1894, file: !112, line: 34, type: !20, scopeLine: 34, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1894 = !DINamespace(name: "Storage", scope: !113)
!1895 = distinct !DILocation(line: 68, column: 49, scope: !1870, inlinedAt: !1874)
!1896 = !DILocation(line: 555, column: 18, scope: !1891, inlinedAt: !1892)
!1897 = !DILocation(line: 35, column: 9, scope: !1893, inlinedAt: !1895)
!1898 = !{!"branch_weights", i32 1, i32 1, i32 2000, i32 2000}
!1899 = !DILocation(line: 49, column: 13, scope: !1900, inlinedAt: !1901)
!1900 = distinct !DISubprogram(name: "initialize<core::cell::Cell<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>>", linkageName: "_RNvMNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eagerINtB2_7StorageINtNtCsgXhsEb1m4tm_4core4cell4CellINtNtB1g_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEE10initializeB2J_", scope: !1894, file: !112, line: 43, type: !20, scopeLine: 43, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1901 = distinct !DILocation(line: 38, column: 45, scope: !1893, inlinedAt: !1895)
!1902 = !DILocation(line: 931, column: 49, scope: !1903, inlinedAt: !1905)
!1903 = distinct !DILexicalBlock(scope: !1904, file: !79, line: 930, column: 9)
!1904 = distinct !DISubprogram(name: "replace<std::sys::thread_local::native::eager::State>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3mem7replaceNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eager5StateECs9SN9c7tmF9T_9bun_alloc", scope: !80, file: !79, line: 916, type: !20, scopeLine: 916, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1905 = distinct !DILocation(line: 513, column: 9, scope: !1906, inlinedAt: !1907)
!1906 = distinct !DISubprogram(name: "replace<std::sys::thread_local::native::eager::State>", linkageName: "_RNvMs7_NtCsgXhsEb1m4tm_4core4cellINtB5_4CellNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eager5StateE7replaceCs9SN9c7tmF9T_9bun_alloc", scope: !123, file: !118, line: 510, type: !20, scopeLine: 510, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1907 = distinct !DILocation(line: 437, column: 14, scope: !1908, inlinedAt: !1909)
!1908 = distinct !DISubprogram(name: "set<std::sys::thread_local::native::eager::State>", linkageName: "_RNvMs7_NtCsgXhsEb1m4tm_4core4cellINtB5_4CellNtNtNtNtNtCsg1bLsEOY8ZL_3std3sys12thread_local6native5eager5StateE3setCs9SN9c7tmF9T_9bun_alloc", scope: !123, file: !118, line: 433, type: !20, scopeLine: 433, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1909 = distinct !DILocation(line: 52, column: 20, scope: !1900, inlinedAt: !1901)
!1910 = !DILocation(line: 38, column: 45, scope: !1893, inlinedAt: !1895)
!1911 = !DILocation(line: 930, column: 22, scope: !1912, inlinedAt: !1913)
!1912 = distinct !DISubprogram(name: "replace<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3mem7replaceINtNtB4_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEB1y_", scope: !80, file: !79, line: 916, type: !20, scopeLine: 916, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1913 = distinct !DILocation(line: 513, column: 9, scope: !1914, inlinedAt: !1915)
!1914 = distinct !DISubprogram(name: "replace<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>", linkageName: "_RNvMs7_NtCsgXhsEb1m4tm_4core4cellINtB5_4CellINtNtB7_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEE7replaceB1F_", scope: !123, file: !118, line: 510, type: !20, scopeLine: 510, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1915 = distinct !DILocation(line: 675, column: 14, scope: !1916, inlinedAt: !1917)
!1916 = distinct !DISubprogram(name: "take<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>", linkageName: "_RNvMsa_NtCsgXhsEb1m4tm_4core4cellINtB5_4CellINtNtB7_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEE4takeB1F_", scope: !123, file: !118, line: 671, type: !20, scopeLine: 671, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1917 = distinct !DILocation(line: 250, column: 5, scope: !1918, inlinedAt: !1919)
!1918 = distinct !DISubprogram(name: "call_once<fn(&core::cell::Cell<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>) -> core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>, (&core::cell::Cell<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>)>", linkageName: "_RNvYNvMsa_NtCsgXhsEb1m4tm_4core4cellINtB8_4CellINtNtBa_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEE4takeINtNtNtBa_3ops8function6FnOnceTRBy_EE9call_onceB1I_", scope: !1876, file: !541, line: 250, type: !20, scopeLine: 250, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1919 = distinct !DILocation(line: 462, column: 12, scope: !1920, inlinedAt: !1882)
!1920 = distinct !DILexicalBlock(scope: !1878, file: !1879, line: 461, column: 9)
!1921 = !DILocation(line: 931, column: 49, scope: !1922, inlinedAt: !1913)
!1922 = distinct !DILexicalBlock(scope: !1912, file: !79, line: 930, column: 9)
!1923 = !DILocation(line: 1062, column: 15, scope: !1924, inlinedAt: !1925)
!1924 = distinct !DISubprogram(name: "unwrap_or_else<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>, fn() -> alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>", linkageName: "_RINvMNtCsgXhsEb1m4tm_4core6optionINtB3_6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEE14unwrap_or_elseNvMB1j_B1h_9new_boxedEB1l_", scope: !259, file: !258, line: 1058, type: !20, scopeLine: 1058, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1925 = distinct !DILocation(line: 187, column: 10, scope: !1883, inlinedAt: !1884)
!1926 = !DILocation(line: 1062, column: 9, scope: !1924, inlinedAt: !1925)
!1927 = !DILocation(line: 99, column: 9, scope: !16, inlinedAt: !1928)
!1928 = distinct !DILocation(line: 210, column: 73, scope: !22, inlinedAt: !1929)
!1929 = distinct !DILocation(line: 332, column: 9, scope: !26, inlinedAt: !1930)
!1930 = distinct !DILocation(line: 449, column: 14, scope: !28, inlinedAt: !1931)
!1931 = distinct !DILocation(line: 248, column: 18, scope: !31, inlinedAt: !1932)
!1932 = distinct !DILocation(line: 317, column: 33, scope: !631, inlinedAt: !1933)
!1933 = distinct !DILocation(line: 73, column: 25, scope: !621, inlinedAt: !1934)
!1934 = distinct !DILocation(line: 250, column: 5, scope: !1935, inlinedAt: !1936)
!1935 = distinct !DISubprogram(name: "call_once<fn() -> alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>, ()>", linkageName: "_RNvYNvMNtCs9SN9c7tmF9T_9bun_alloc9ast_allocNtB5_13AstAllocState9new_boxedINtNtNtCsgXhsEb1m4tm_4core3ops8function6FnOnceuE9call_onceB7_", scope: !1876, file: !541, line: 250, type: !20, scopeLine: 250, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1936 = distinct !DILocation(line: 1064, column: 21, scope: !1924, inlinedAt: !1925)
!1937 = !DILocation(line: 101, column: 9, scope: !16, inlinedAt: !1928)
!1938 = !DILocation(line: 248, column: 11, scope: !31, inlinedAt: !1932)
!1939 = !DILocation(line: 248, column: 5, scope: !31, inlinedAt: !1932)
!1940 = !DILocation(line: 250, column: 19, scope: !31, inlinedAt: !1932)
!1941 = !DILocation(line: 1920, column: 41, scope: !638, inlinedAt: !1942)
!1942 = distinct !DILocation(line: 1418, column: 18, scope: !640, inlinedAt: !1943)
!1943 = distinct !DILocation(line: 78, column: 41, scope: !642, inlinedAt: !1934)
!1944 = !DILocation(line: 1920, column: 41, scope: !645, inlinedAt: !1945)
!1945 = distinct !DILocation(line: 1418, column: 18, scope: !647, inlinedAt: !1946)
!1946 = distinct !DILocation(line: 80, column: 41, scope: !642, inlinedAt: !1934)
!1947 = !DILocation(line: 1920, column: 41, scope: !651, inlinedAt: !1948)
!1948 = distinct !DILocation(line: 1418, column: 18, scope: !653, inlinedAt: !1949)
!1949 = distinct !DILocation(line: 79, column: 35, scope: !642, inlinedAt: !1934)
!1950 = !DILocation(line: 250, column: 5, scope: !1935, inlinedAt: !1936)
!1951 = !DILocation(line: 0, scope: !1924, inlinedAt: !1925)
!1952 = !DILocation(line: 203, column: 5, scope: !1953, inlinedAt: !1954)
!1953 = distinct !DISubprogram(name: "swap_state", linkageName: "_RNvNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc10swap_state", scope: !624, file: !622, line: 202, type: !20, scopeLine: 202, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1954 = !DILocation(line: 281, column: 19, scope: !1885, inlinedAt: !1887)
!1955 = !DILocation(line: 930, column: 22, scope: !1956, inlinedAt: !1957)
!1956 = distinct !DISubprogram(name: "replace<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3mem7replaceINtNtB4_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEEB1y_", scope: !80, file: !79, line: 916, type: !20, scopeLine: 916, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1957 = !DILocation(line: 513, column: 9, scope: !1958, inlinedAt: !1959)
!1958 = distinct !DISubprogram(name: "replace<core::option::Option<alloc::boxed::Box<bun_alloc::ast_alloc::AstAllocState, alloc::alloc::Global>>>", linkageName: "_RNvMs7_NtCsgXhsEb1m4tm_4core4cellINtB5_4CellINtNtB7_6option6OptionINtNtCskhhhlZ4wWGP_5alloc5boxed3BoxNtNtCs9SN9c7tmF9T_9bun_alloc9ast_alloc13AstAllocStateEEE7replaceB1F_", scope: !123, file: !118, line: 510, type: !20, scopeLine: 510, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1959 = !DILocation(line: 203, column: 15, scope: !1953, inlinedAt: !1954)
!1960 = !DILocation(line: 931, column: 49, scope: !1961, inlinedAt: !1957)
!1961 = distinct !DILexicalBlock(scope: !1956, file: !79, line: 930, column: 9)
!1962 = !DILocation(line: 304, column: 6, scope: !1867)
!1963 = distinct !DISubprogram(name: "write_str", linkageName: "_RNvXs6_Cs9SN9c7tmF9T_9bun_allocNtB5_11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_str", scope: !1964, file: !223, line: 701, type: !20, scopeLine: 701, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1964 = !DINamespace(name: "{impl#8}", scope: !199)
!1965 = !DILocation(line: 703, column: 19, scope: !1966)
!1966 = distinct !DILexicalBlock(scope: !1963, file: !223, line: 702, column: 9)
!1967 = !DILocation(line: 704, column: 18, scope: !1968)
!1968 = distinct !DILexicalBlock(scope: !1966, file: !223, line: 703, column: 9)
!1969 = !DILocation(line: 704, column: 12, scope: !1968)
!1970 = !DILocation(line: 1064, column: 16, scope: !1971, inlinedAt: !1972)
!1971 = distinct !DISubprogram(name: "checked_sub", linkageName: "_RNvMs9_NtCsgXhsEb1m4tm_4core3numj11checked_sub", scope: !381, file: !380, line: 1058, type: !20, scopeLine: 1058, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1972 = !DILocation(line: 450, column: 32, scope: !1973, inlinedAt: !1974)
!1973 = distinct !DISubprogram(name: "index_mut<u8>", linkageName: "_RNvXs2_NtNtCsgXhsEb1m4tm_4core5slice5indexINtNtNtB9_3ops5range5RangejEINtB5_10SliceIndexShE9index_mutCs9SN9c7tmF9T_9bun_alloc", scope: !387, file: !385, line: 448, type: !20, scopeLine: 448, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1974 = !DILocation(line: 31, column: 15, scope: !1975, inlinedAt: !1976)
!1975 = distinct !DISubprogram(name: "index_mut<u8, core::ops::range::Range<usize>>", linkageName: "_RNvXs_NtNtCsgXhsEb1m4tm_4core5slice5indexShINtNtNtB8_3ops5index8IndexMutINtNtBK_5range5RangejEE9index_mutCs9SN9c7tmF9T_9bun_alloc", scope: !392, file: !385, line: 30, type: !20, scopeLine: 30, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1976 = !DILocation(line: 707, column: 17, scope: !1968)
!1977 = !DILocation(line: 707, column: 9, scope: !1968)
!1978 = !DILocation(line: 101, column: 24, scope: !1979, inlinedAt: !1981)
!1979 = distinct !DILexicalBlock(scope: !1980, file: !385, line: 99, column: 5)
!1980 = distinct !DISubprogram(name: "get_offset_len_mut_noubcheck<u8>", linkageName: "_RINvNtNtCsgXhsEb1m4tm_4core5slice5index28get_offset_len_mut_noubcheckhECs9SN9c7tmF9T_9bun_alloc", scope: !388, file: !385, line: 94, type: !20, scopeLine: 94, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1981 = !DILocation(line: 454, column: 28, scope: !1973, inlinedAt: !1974)
!1982 = !DILocation(line: 551, column: 14, scope: !401, inlinedAt: !1983)
!1983 = distinct !DILocation(line: 5585, column: 9, scope: !403, inlinedAt: !1984)
!1984 = distinct !DILocation(line: 4326, column: 18, scope: !1985, inlinedAt: !1986)
!1985 = distinct !DISubprogram(name: "copy_from_slice<u8>", linkageName: "_RNvMNtCsgXhsEb1m4tm_4core5sliceSh15copy_from_sliceCs9SN9c7tmF9T_9bun_alloc", scope: !341, file: !340, line: 4321, type: !20, scopeLine: 4321, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1986 = !DILocation(line: 707, column: 32, scope: !1968)
!1987 = !{!1988, !1990}
!1988 = distinct !{!1988, !1989, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: %dest.0"}
!1989 = distinct !{!1989, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc"}
!1990 = distinct !{!1990, !1989, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: %src.0"}
!1991 = !{!1992}
!1992 = distinct !{!1992, !1989, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: argument 2"}
!1993 = !DILocation(line: 708, column: 9, scope: !1968)
!1994 = !DILocation(line: 710, column: 6, scope: !1963)
!1995 = !DILocation(line: 456, column: 13, scope: !1973, inlinedAt: !1974)
!1996 = distinct !DISubprogram(name: "drop", linkageName: "_RNvXs6_NtCs9SN9c7tmF9T_9bun_alloc18max_heap_allocatorNtB5_16MaxHeapAllocatorNtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4drop", scope: !1997, file: !700, line: 135, type: !20, scopeLine: 135, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!1997 = !DINamespace(name: "{impl#8}", scope: !702)
!1998 = !DILocation(line: 930, column: 22, scope: !1999, inlinedAt: !2000)
!1999 = distinct !DISubprogram(name: "replace<core::option::Option<core::ptr::non_null::NonNull<u8>>>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3mem7replaceINtNtB4_6option6OptionINtNtNtB4_3ptr8non_null7NonNullhEEECs9SN9c7tmF9T_9bun_alloc", scope: !80, file: !79, line: 916, type: !20, scopeLine: 916, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2000 = !DILocation(line: 1898, column: 9, scope: !2001, inlinedAt: !2002)
!2001 = distinct !DISubprogram(name: "take<core::ptr::non_null::NonNull<u8>>", linkageName: "_RNvMNtCsgXhsEb1m4tm_4core6optionINtB2_6OptionINtNtNtB4_3ptr8non_null7NonNullhEE4takeCs9SN9c7tmF9T_9bun_alloc", scope: !259, file: !258, line: 1896, type: !20, scopeLine: 1896, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2002 = !DILocation(line: 137, column: 37, scope: !2003)
!2003 = distinct !DILexicalBlock(scope: !1996, file: !700, line: 137, column: 44)
!2004 = !DILocation(line: 931, column: 49, scope: !2005, inlinedAt: !2000)
!2005 = distinct !DILexicalBlock(scope: !1999, file: !79, line: 930, column: 9)
!2006 = !DILocation(line: 137, column: 28, scope: !2003)
!2007 = !DILocation(line: 137, column: 16, scope: !2003)
!2008 = !DILocation(line: 143, column: 55, scope: !2003)
!2009 = !DILocation(line: 128, column: 14, scope: !2010, inlinedAt: !2011)
!2010 = distinct !DISubprogram(name: "dealloc_nonnull", linkageName: "_RNvNtCskhhhlZ4wWGP_5alloc5alloc15dealloc_nonnull", scope: !18, file: !17, line: 127, type: !20, scopeLine: 127, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2011 = !DILocation(line: 121, column: 14, scope: !2012, inlinedAt: !2013)
!2012 = distinct !DISubprogram(name: "dealloc", linkageName: "_RNvNtCskhhhlZ4wWGP_5alloc5alloc7dealloc", scope: !18, file: !17, line: 120, type: !20, scopeLine: 120, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2013 = !DILocation(line: 141, column: 17, scope: !2003)
!2014 = !DILocation(line: 137, column: 9, scope: !1996)
!2015 = !DILocation(line: 147, column: 6, scope: !1996)
!2016 = distinct !DISubprogram(name: "fmt", linkageName: "_RNvXse_Cs9SN9c7tmF9T_9bun_allocNtB5_6StringNtNtCsgXhsEb1m4tm_4core3fmt7Display3fmt", scope: !2017, file: !223, line: 1589, type: !20, scopeLine: 1589, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2017 = !DINamespace(name: "{impl#16}", scope: !199)
!2018 = !DILocation(line: 1529, column: 15, scope: !2019, inlinedAt: !2020)
!2019 = distinct !DISubprogram(name: "to_zig_string", linkageName: "_RNvMsd_Cs9SN9c7tmF9T_9bun_allocNtB5_6String13to_zig_string", scope: !938, file: !223, line: 1528, type: !20, scopeLine: 1528, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2020 = !DILocation(line: 1593, column: 23, scope: !2016)
!2021 = !DILocation(line: 1529, column: 9, scope: !2019, inlinedAt: !2020)
!2022 = !DILocation(line: 1524, column: 18, scope: !2023, inlinedAt: !2024)
!2023 = distinct !DISubprogram(name: "wtf_impl", linkageName: "_RNvMsd_Cs9SN9c7tmF9T_9bun_allocNtB5_6String8wtf_impl", scope: !938, file: !223, line: 1519, type: !20, scopeLine: 1519, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2024 = !DILocation(line: 1535, column: 40, scope: !2019, inlinedAt: !2020)
!2025 = !DILocation(line: 2447, column: 9, scope: !1056, inlinedAt: !2026)
!2026 = distinct !DILocation(line: 555, column: 30, scope: !1058, inlinedAt: !2027)
!2027 = distinct !DILocation(line: 1245, column: 32, scope: !1060, inlinedAt: !2028)
!2028 = distinct !DILocation(line: 1391, column: 17, scope: !1062, inlinedAt: !2029)
!2029 = distinct !DILocation(line: 1535, column: 51, scope: !2019, inlinedAt: !2020)
!2030 = !DILocation(line: 555, column: 18, scope: !1058, inlinedAt: !2027)
!2031 = !DILocation(line: 1245, column: 9, scope: !1060, inlinedAt: !2028)
!2032 = !DILocation(line: 1391, column: 12, scope: !1062, inlinedAt: !2029)
!2033 = !DILocation(line: 0, scope: !1062, inlinedAt: !2029)
!2034 = !DILocation(line: 1535, column: 65, scope: !2019, inlinedAt: !2020)
!2035 = !DILocation(line: 1533, column: 26, scope: !2019, inlinedAt: !2020)
!2036 = !DILocation(line: 0, scope: !2019, inlinedAt: !2020)
!2037 = !DILocation(line: 1594, column: 12, scope: !2038)
!2038 = distinct !DILexicalBlock(scope: !2016, file: !223, line: 1593, column: 9)
!2039 = !DILocation(line: 1118, column: 9, scope: !2040, inlinedAt: !2041)
!2040 = distinct !DISubprogram(name: "is_16bit", linkageName: "_RNvMsb_Cs9SN9c7tmF9T_9bun_allocNtB5_9ZigString8is_16bit", scope: !1073, file: !223, line: 1117, type: !20, scopeLine: 1117, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2041 = !DILocation(line: 1597, column: 15, scope: !2038)
!2042 = !DILocation(line: 1597, column: 12, scope: !2038)
!2043 = !DILocation(line: 1122, column: 9, scope: !2044, inlinedAt: !2045)
!2044 = distinct !DISubprogram(name: "is_utf8", linkageName: "_RNvMsb_Cs9SN9c7tmF9T_9bun_allocNtB5_9ZigString7is_utf8", scope: !1073, file: !223, line: 1121, type: !20, scopeLine: 1121, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2045 = !DILocation(line: 1602, column: 22, scope: !2038)
!2046 = !DILocation(line: 1602, column: 19, scope: !2038)
!2047 = !DILocation(line: 1604, column: 26, scope: !2038)
!2048 = !DILocation(line: 1077, column: 5, scope: !1090, inlinedAt: !2049)
!2049 = distinct !DILocation(line: 1574, column: 8, scope: !2050, inlinedAt: !2051)
!2050 = distinct !DISubprogram(name: "min<usize>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3cmp3minjECs9SN9c7tmF9T_9bun_alloc", scope: !688, file: !686, line: 1573, type: !20, scopeLine: 1573, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2051 = !DILocation(line: 1175, column: 17, scope: !2052, inlinedAt: !2053)
!2052 = distinct !DISubprogram(name: "slice", linkageName: "_RNvMsb_Cs9SN9c7tmF9T_9bun_allocNtB5_9ZigString5slice", scope: !1073, file: !223, line: 1161, type: !20, scopeLine: 1161, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2053 = !DILocation(line: 1604, column: 66, scope: !2038)
!2054 = !DILocation(line: 1156, column: 9, scope: !2055, inlinedAt: !2056)
!2055 = distinct !DISubprogram(name: "untagged", linkageName: "_RNvMsb_Cs9SN9c7tmF9T_9bun_allocNtB5_9ZigString8untagged", scope: !1073, file: !223, line: 1155, type: !20, scopeLine: 1155, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2056 = !DILocation(line: 1174, column: 17, scope: !2052, inlinedAt: !2053)
!2057 = !DILocation(line: 350, column: 15, scope: !2058, inlinedAt: !2062)
!2058 = distinct !DISubprogram(name: "deref<str>", linkageName: "_RNvXs2_NtCskhhhlZ4wWGP_5alloc6borrowINtB5_3CoweENtNtNtCsgXhsEb1m4tm_4core3ops5deref5Deref5derefCs9SN9c7tmF9T_9bun_alloc", scope: !2060, file: !2059, line: 349, type: !20, scopeLine: 349, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2059 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/alloc/src/borrow.rs", directory: "", checksumkind: CSK_MD5, checksum: "51fe27f1151c44bdbc8f0d9c1cf10699")
!2060 = !DINamespace(name: "{impl#4}", scope: !2061)
!2061 = !DINamespace(name: "borrow", scope: !19)
!2062 = !DILocation(line: 1604, column: 25, scope: !2038)
!2063 = !{i64 -1, i64 -9223372036854775808}
!2064 = !DILocation(line: 350, column: 9, scope: !2058, inlinedAt: !2062)
!2065 = !DILocation(line: 1604, column: 15, scope: !2038)
!2066 = !DILocation(line: 809, column: 1, scope: !2067, inlinedAt: !2068)
!2067 = distinct !DISubprogram(name: "drop_in_place<alloc::borrow::Cow<str>>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc6borrow3CoweEECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 809, type: !20, scopeLine: 809, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2068 = distinct !DILocation(line: 1604, column: 74, scope: !2038)
!2069 = !DILocation(line: 128, column: 14, scope: !87, inlinedAt: !2070)
!2070 = distinct !DILocation(line: 229, column: 22, scope: !89, inlinedAt: !2071)
!2071 = distinct !DILocation(line: 344, column: 9, scope: !91, inlinedAt: !2072)
!2072 = distinct !DILocation(line: 462, column: 23, scope: !93, inlinedAt: !2073)
!2073 = distinct !DILocation(line: 876, column: 28, scope: !2074, inlinedAt: !2076)
!2074 = distinct !DILexicalBlock(scope: !2075, file: !797, line: 874, column: 82)
!2075 = distinct !DISubprogram(name: "deallocate<alloc::alloc::Global>", linkageName: "_RNvMs2_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner10deallocateCs9SN9c7tmF9T_9bun_alloc", scope: !803, file: !797, line: 872, type: !20, scopeLine: 872, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2076 = distinct !DILocation(line: 424, column: 29, scope: !2077, inlinedAt: !2079)
!2077 = distinct !DISubprogram(name: "drop<u8, alloc::alloc::Global>", linkageName: "_RNvXs1_NtCskhhhlZ4wWGP_5alloc7raw_vecINtB5_6RawVechENtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4dropCs9SN9c7tmF9T_9bun_alloc", scope: !2078, file: !797, line: 422, type: !20, scopeLine: 422, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2078 = !DINamespace(name: "{impl#3}", scope: !799)
!2079 = distinct !DILocation(line: 809, column: 1, scope: !2080, inlinedAt: !2081)
!2080 = distinct !DISubprogram(name: "drop_in_place<alloc::raw_vec::RawVec<u8, alloc::alloc::Global>>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc7raw_vec6RawVechEECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 809, type: !20, scopeLine: 809, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2081 = distinct !DILocation(line: 809, column: 1, scope: !2082, inlinedAt: !2083)
!2082 = distinct !DISubprogram(name: "drop_in_place<alloc::vec::Vec<u8, alloc::alloc::Global>>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc3vec3VechEECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 809, type: !20, scopeLine: 809, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2083 = distinct !DILocation(line: 809, column: 1, scope: !2084, inlinedAt: !2085)
!2084 = distinct !DISubprogram(name: "drop_in_place<alloc::string::String>", linkageName: "_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtNtCskhhhlZ4wWGP_5alloc6string6StringECs9SN9c7tmF9T_9bun_alloc", scope: !74, file: !73, line: 809, type: !20, scopeLine: 809, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2085 = distinct !DILocation(line: 809, column: 1, scope: !2067, inlinedAt: !2068)
!2086 = !{!2087, !2089, !2091, !2093, !2095, !2097}
!2087 = distinct !{!2087, !2088, !"_RNvMs2_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner10deallocateCs9SN9c7tmF9T_9bun_alloc: %self"}
!2088 = distinct !{!2088, !"_RNvMs2_NtCskhhhlZ4wWGP_5alloc7raw_vecNtB5_11RawVecInner10deallocateCs9SN9c7tmF9T_9bun_alloc"}
!2089 = distinct !{!2089, !2090, !"_RNvXs1_NtCskhhhlZ4wWGP_5alloc7raw_vecINtB5_6RawVechENtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4dropCs9SN9c7tmF9T_9bun_alloc: %self"}
!2090 = distinct !{!2090, !"_RNvXs1_NtCskhhhlZ4wWGP_5alloc7raw_vecINtB5_6RawVechENtNtNtCsgXhsEb1m4tm_4core3ops4drop4Drop4dropCs9SN9c7tmF9T_9bun_alloc"}
!2091 = distinct !{!2091, !2092, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc7raw_vec6RawVechEECs9SN9c7tmF9T_9bun_alloc: %_1"}
!2092 = distinct !{!2092, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc7raw_vec6RawVechEECs9SN9c7tmF9T_9bun_alloc"}
!2093 = distinct !{!2093, !2094, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc3vec3VechEECs9SN9c7tmF9T_9bun_alloc: %_1"}
!2094 = distinct !{!2094, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc3vec3VechEECs9SN9c7tmF9T_9bun_alloc"}
!2095 = distinct !{!2095, !2096, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtNtCskhhhlZ4wWGP_5alloc6string6StringECs9SN9c7tmF9T_9bun_alloc: %_1"}
!2096 = distinct !{!2096, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeNtNtCskhhhlZ4wWGP_5alloc6string6StringECs9SN9c7tmF9T_9bun_alloc"}
!2097 = distinct !{!2097, !2098, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc6borrow3CoweEECs9SN9c7tmF9T_9bun_alloc: %_1"}
!2098 = distinct !{!2098, !"_RINvNtCsgXhsEb1m4tm_4core3ptr13drop_in_placeINtNtCskhhhlZ4wWGP_5alloc6borrow3CoweEECs9SN9c7tmF9T_9bun_alloc"}
!2099 = !DILocation(line: 874, column: 9, scope: !2075, inlinedAt: !2076)
!2100 = !DILocation(line: 1604, column: 74, scope: !2038)
!2101 = !DILocation(line: 1602, column: 16, scope: !2038)
!2102 = !DILocation(line: 1077, column: 5, scope: !1090, inlinedAt: !2103)
!2103 = distinct !DILocation(line: 1574, column: 8, scope: !2050, inlinedAt: !2104)
!2104 = !DILocation(line: 1175, column: 17, scope: !2105, inlinedAt: !2106)
!2105 = !DILexicalBlockFile(scope: !2052, file: !223, discriminator: 2)
!2106 = !DILocation(line: 1606, column: 26, scope: !2038)
!2107 = !DILocation(line: 1156, column: 9, scope: !2055, inlinedAt: !2108)
!2108 = !DILocation(line: 1174, column: 17, scope: !2105, inlinedAt: !2106)
!2109 = !DILocation(line: 404, column: 18, scope: !2110, inlinedAt: !2111)
!2110 = distinct !DISubprogram(name: "as_ptr<u8>", linkageName: "_RNvMs1_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullhE6as_ptrCs9SN9c7tmF9T_9bun_alloc", scope: !371, file: !348, line: 398, type: !20, scopeLine: 398, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2111 = !DILocation(line: 102, column: 69, scope: !2112, inlinedAt: !2116)
!2112 = !DILexicalBlockFile(scope: !2113, file: !332, discriminator: 2)
!2113 = distinct !DILexicalBlock(scope: !2114, file: !332, line: 98, column: 9)
!2114 = distinct !DILexicalBlock(scope: !2115, file: !332, line: 97, column: 9)
!2115 = distinct !DISubprogram(name: "new<u8>", linkageName: "_RNvMs4_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB5_4IterhE3newCs9SN9c7tmF9T_9bun_alloc", scope: !335, file: !332, line: 96, type: !20, scopeLine: 96, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2116 = !DILocation(line: 1042, column: 9, scope: !2117, inlinedAt: !2119)
!2117 = !DILexicalBlockFile(scope: !2118, file: !340, discriminator: 2)
!2118 = distinct !DISubprogram(name: "iter<u8>", linkageName: "_RNvMNtCsgXhsEb1m4tm_4core5sliceSh4iterCs9SN9c7tmF9T_9bun_alloc", scope: !341, file: !340, line: 1041, type: !20, scopeLine: 1041, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2119 = !DILocation(line: 26, column: 14, scope: !2120, inlinedAt: !2122)
!2120 = distinct !DISubprogram(name: "into_iter<u8>", linkageName: "_RNvXs_NtNtCsgXhsEb1m4tm_4core5slice4iterRShNtNtNtNtB8_4iter6traits7collect12IntoIterator9into_iterCs9SN9c7tmF9T_9bun_alloc", scope: !2121, file: !332, line: 25, type: !20, scopeLine: 25, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2121 = !DINamespace(name: "{impl#1}", scope: !336)
!2122 = !DILocation(line: 1606, column: 23, scope: !2038)
!2123 = !DILocation(line: 961, column: 18, scope: !2124, inlinedAt: !2125)
!2124 = distinct !DISubprogram(name: "add<u8>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrOh3addCs9SN9c7tmF9T_9bun_alloc", scope: !316, file: !315, line: 927, type: !20, scopeLine: 927, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2125 = !DILocation(line: 102, column: 78, scope: !2112, inlinedAt: !2116)
!2126 = !DILocation(line: 2173, column: 9, scope: !2127, inlinedAt: !2128)
!2127 = distinct !DISubprogram(name: "branch<(), core::fmt::Error>", linkageName: "_RNvXsp_NtCsgXhsEb1m4tm_4core6resultINtB5_6ResultuNtNtB7_3fmt5ErrorENtNtNtB7_3ops9try_trait3Try6branchCs9SN9c7tmF9T_9bun_alloc", scope: !566, file: !565, line: 2172, type: !20, scopeLine: 2172, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2128 = !DILocation(line: 1608, column: 17, scope: !2129)
!2129 = distinct !DILexicalBlock(scope: !2130, file: !223, line: 1606, column: 13)
!2130 = distinct !DILexicalBlock(scope: !2038, file: !223, line: 1606, column: 13)
!2131 = !DILocation(line: 656, column: 28, scope: !2132, inlinedAt: !2133)
!2132 = distinct !DISubprogram(name: "add<u8>", linkageName: "_RNvMs1_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullhE3addCs9SN9c7tmF9T_9bun_alloc", scope: !371, file: !348, line: 648, type: !20, scopeLine: 648, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2133 = !DILocation(line: 185, column: 40, scope: !2134, inlinedAt: !2137)
!2134 = distinct !DILexicalBlock(scope: !2135, file: !353, line: 162, column: 17)
!2135 = distinct !DILexicalBlock(scope: !2136, file: !353, line: 161, column: 17)
!2136 = distinct !DISubprogram(name: "next<u8>", linkageName: "_RNvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB6_4IterhENtNtNtNtBa_4iter6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc", scope: !356, file: !353, line: 157, type: !20, scopeLine: 157, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2137 = !DILocation(line: 1606, column: 23, scope: !2138)
!2138 = !DILexicalBlockFile(scope: !2130, file: !223, discriminator: 2)
!2139 = !DILocation(line: 1714, column: 9, scope: !2140, inlinedAt: !2141)
!2140 = distinct !DISubprogram(name: "eq<u8>", linkageName: "_RNvXsd_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullhENtNtB9_3cmp9PartialEq2eqCs9SN9c7tmF9T_9bun_alloc", scope: !349, file: !348, line: 1713, type: !20, scopeLine: 1713, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2141 = !DILocation(line: 180, column: 28, scope: !2134, inlinedAt: !2137)
!2142 = !DILocation(line: 1606, column: 18, scope: !2130)
!2143 = !DILocation(line: 1608, column: 30, scope: !2129)
!2144 = !DILocation(line: 1608, column: 19, scope: !2129)
!2145 = !DILocation(line: 1193, column: 17, scope: !2146, inlinedAt: !2147)
!2146 = distinct !DISubprogram(name: "utf16_slice_aligned", linkageName: "_RNvMsb_Cs9SN9c7tmF9T_9bun_allocNtB5_9ZigString19utf16_slice_aligned", scope: !1073, file: !223, line: 1182, type: !20, scopeLine: 1182, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2147 = !DILocation(line: 1598, column: 50, scope: !2038)
!2148 = !DILocation(line: 404, column: 18, scope: !2149, inlinedAt: !2150)
!2149 = distinct !DISubprogram(name: "as_ptr<u16>", linkageName: "_RNvMs1_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNulltE6as_ptrCs9SN9c7tmF9T_9bun_alloc", scope: !371, file: !348, line: 398, type: !20, scopeLine: 398, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2150 = !DILocation(line: 102, column: 69, scope: !2151, inlinedAt: !2154)
!2151 = distinct !DILexicalBlock(scope: !2152, file: !332, line: 98, column: 9)
!2152 = distinct !DILexicalBlock(scope: !2153, file: !332, line: 97, column: 9)
!2153 = distinct !DISubprogram(name: "new<u16>", linkageName: "_RNvMs4_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB5_4ItertE3newCs9SN9c7tmF9T_9bun_alloc", scope: !335, file: !332, line: 96, type: !20, scopeLine: 96, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2154 = !DILocation(line: 1042, column: 9, scope: !2155, inlinedAt: !2156)
!2155 = distinct !DISubprogram(name: "iter<u16>", linkageName: "_RNvMNtCsgXhsEb1m4tm_4core5sliceSt4iterCs9SN9c7tmF9T_9bun_alloc", scope: !341, file: !340, line: 1041, type: !20, scopeLine: 1041, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2156 = !DILocation(line: 1598, column: 72, scope: !2038)
!2157 = !DILocation(line: 961, column: 18, scope: !2158, inlinedAt: !2159)
!2158 = distinct !DISubprogram(name: "add<u16>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrOt3addCs9SN9c7tmF9T_9bun_alloc", scope: !316, file: !315, line: 927, type: !20, scopeLine: 927, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2159 = !DILocation(line: 102, column: 78, scope: !2151, inlinedAt: !2154)
!2160 = !DILocation(line: 1598, column: 13, scope: !2161)
!2161 = distinct !DILexicalBlock(scope: !2038, file: !223, line: 1598, column: 13)
!2162 = !DILocation(line: 1598, column: 22, scope: !2038)
!2163 = !DILocation(line: 44, column: 17, scope: !2164, inlinedAt: !2169)
!2164 = distinct !DISubprogram(name: "next<core::iter::adapters::copied::Copied<core::slice::iter::Iter<u16>>>", linkageName: "_RNvXNtNtCsgXhsEb1m4tm_4core4char6decodeINtB2_11DecodeUtf16INtNtNtNtB6_4iter8adapters6copied6CopiedINtNtNtB6_5slice4iter4ItertEEENtNtNtB11_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc", scope: !2166, file: !2165, line: 43, type: !20, scopeLine: 43, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2165 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/char/decode.rs", directory: "", checksumkind: CSK_MD5, checksum: "9cbf85c61f55436af0d7fcad7ddc8993")
!2166 = !DINamespace(name: "{impl#0}", scope: !2167)
!2167 = !DINamespace(name: "decode", scope: !2168)
!2168 = !DINamespace(name: "char", scope: !64)
!2169 = distinct !DILocation(line: 1598, column: 22, scope: !2161)
!2170 = !DILocation(line: 1714, column: 9, scope: !2171, inlinedAt: !2172)
!2171 = distinct !DISubprogram(name: "eq<u16>", linkageName: "_RNvXsd_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNulltENtNtB9_3cmp9PartialEq2eqCs9SN9c7tmF9T_9bun_alloc", scope: !349, file: !348, line: 1713, type: !20, scopeLine: 1713, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2172 = distinct !DILocation(line: 180, column: 28, scope: !2173, inlinedAt: !2176)
!2173 = distinct !DILexicalBlock(scope: !2174, file: !353, line: 162, column: 17)
!2174 = distinct !DILexicalBlock(scope: !2175, file: !353, line: 161, column: 17)
!2175 = distinct !DISubprogram(name: "next<u16>", linkageName: "_RNvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB6_4ItertENtNtNtNtBa_4iter6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc", scope: !356, file: !353, line: 157, type: !20, scopeLine: 157, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2176 = distinct !DILocation(line: 52, column: 17, scope: !2177, inlinedAt: !2178)
!2177 = distinct !DISubprogram(name: "next<core::slice::iter::Iter<u16>, u16>", linkageName: "_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters6copiedINtB4_6CopiedINtNtNtBa_5slice4iter4ItertEENtNtNtB8_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc", scope: !1156, file: !1155, line: 51, type: !20, scopeLine: 51, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2178 = distinct !DILocation(line: 46, column: 31, scope: !2164, inlinedAt: !2169)
!2179 = !DILocation(line: 180, column: 28, scope: !2173, inlinedAt: !2176)
!2180 = !DILocation(line: 656, column: 28, scope: !2181, inlinedAt: !2182)
!2181 = distinct !DISubprogram(name: "add<u16>", linkageName: "_RNvMs1_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNulltE3addCs9SN9c7tmF9T_9bun_alloc", scope: !371, file: !348, line: 648, type: !20, scopeLine: 648, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2182 = distinct !DILocation(line: 185, column: 40, scope: !2173, inlinedAt: !2176)
!2183 = !DILocation(line: 2138, column: 19, scope: !2184, inlinedAt: !2185)
!2184 = distinct !DISubprogram(name: "copied<u16>", linkageName: "_RNvMs1_NtCsgXhsEb1m4tm_4core6optionINtB5_6OptionRtE6copiedCs9SN9c7tmF9T_9bun_alloc", scope: !259, file: !258, line: 2131, type: !20, scopeLine: 2131, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2185 = distinct !DILocation(line: 52, column: 24, scope: !2177, inlinedAt: !2178)
!2186 = !{!2187, !2189}
!2187 = distinct !{!2187, !2188, !"_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters6copiedINtB4_6CopiedINtNtNtBa_5slice4iter4ItertEENtNtNtB8_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc: %self"}
!2188 = distinct !{!2188, !"_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters6copiedINtB4_6CopiedINtNtNtBa_5slice4iter4ItertEENtNtNtB8_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc"}
!2189 = distinct !{!2189, !2190, !"_RNvXNtNtCsgXhsEb1m4tm_4core4char6decodeINtB2_11DecodeUtf16INtNtNtNtB6_4iter8adapters6copied6CopiedINtNtNtB6_5slice4iter4ItertEEENtNtNtB11_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc: %self"}
!2190 = distinct !{!2190, !"_RNvXNtNtCsgXhsEb1m4tm_4core4char6decodeINtB2_11DecodeUtf16INtNtNtNtB6_4iter8adapters6copied6CopiedINtNtNtB6_5slice4iter4ItertEEENtNtNtB11_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc"}
!2191 = !DILocation(line: 46, column: 37, scope: !2164, inlinedAt: !2169)
!2192 = !DILocation(line: 0, scope: !2164, inlinedAt: !2169)
!2193 = !DILocation(line: 1239, column: 24, scope: !2194, inlinedAt: !2198)
!2194 = !DILexicalBlockFile(scope: !2195, file: !451, discriminator: 0)
!2195 = distinct !DILexicalBlock(scope: !2196, file: !537, line: 429, column: 9)
!2196 = distinct !DISubprogram(name: "is_utf16_surrogate", linkageName: "_RNvMs5_NtCsgXhsEb1m4tm_4core3numt18is_utf16_surrogate", scope: !2197, file: !451, line: 1238, type: !20, scopeLine: 1238, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2197 = !DINamespace(name: "{impl#7}", scope: !382)
!2198 = distinct !DILocation(line: 49, column: 15, scope: !2199, inlinedAt: !2169)
!2199 = distinct !DILexicalBlock(scope: !2164, file: !2165, line: 44, column: 9)
!2200 = !DILocation(line: 51, column: 18, scope: !2199, inlinedAt: !2169)
!2201 = !DILocation(line: 49, column: 9, scope: !2199, inlinedAt: !2169)
!2202 = !DILocation(line: 52, column: 19, scope: !2199, inlinedAt: !2169)
!2203 = !DILocation(line: 1714, column: 9, scope: !2171, inlinedAt: !2204)
!2204 = distinct !DILocation(line: 180, column: 28, scope: !2173, inlinedAt: !2205)
!2205 = distinct !DILocation(line: 52, column: 17, scope: !2177, inlinedAt: !2206)
!2206 = distinct !DILocation(line: 56, column: 38, scope: !2199, inlinedAt: !2169)
!2207 = !DILocation(line: 180, column: 28, scope: !2173, inlinedAt: !2205)
!2208 = !DILocation(line: 656, column: 28, scope: !2181, inlinedAt: !2209)
!2209 = distinct !DILocation(line: 185, column: 40, scope: !2173, inlinedAt: !2205)
!2210 = !DILocation(line: 2138, column: 19, scope: !2184, inlinedAt: !2211)
!2211 = distinct !DILocation(line: 52, column: 24, scope: !2177, inlinedAt: !2206)
!2212 = !{!2213, !2189}
!2213 = distinct !{!2213, !2214, !"_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters6copiedINtB4_6CopiedINtNtNtBa_5slice4iter4ItertEENtNtNtB8_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc: %self"}
!2214 = distinct !{!2214, !"_RNvXs_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters6copiedINtB4_6CopiedINtNtNtBa_5slice4iter4ItertEENtNtNtB8_6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc"}
!2215 = !DILocation(line: 61, column: 16, scope: !2216, inlinedAt: !2169)
!2216 = distinct !DILexicalBlock(scope: !2199, file: !2165, line: 56, column: 13)
!2217 = !DILocation(line: 69, column: 23, scope: !2216, inlinedAt: !2169)
!2218 = !DILocation(line: 69, column: 22, scope: !2216, inlinedAt: !2169)
!2219 = !DILocation(line: 69, column: 51, scope: !2216, inlinedAt: !2169)
!2220 = !DILocation(line: 71, column: 18, scope: !2221, inlinedAt: !2169)
!2221 = distinct !DILexicalBlock(scope: !2216, file: !2165, line: 69, column: 13)
!2222 = !DILocation(line: 1598, column: 22, scope: !2161)
!2223 = !DILocation(line: 52, column: 16, scope: !2199, inlinedAt: !2169)
!2224 = !DILocation(line: 0, scope: !2225, inlinedAt: !2227)
!2225 = distinct !DISubprogram(name: "unwrap_or<char, core::char::decode::DecodeUtf16Error>", linkageName: "_RNvMNtCsgXhsEb1m4tm_4core6resultINtB2_6ResultcNtNtNtB4_4char6decode16DecodeUtf16ErrorE9unwrap_orCs9SN9c7tmF9T_9bun_alloc", scope: !2226, file: !565, line: 1590, type: !20, scopeLine: 1590, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2226 = !DINamespace(name: "Result", scope: !567)
!2227 = !DILocation(line: 1599, column: 32, scope: !2228)
!2228 = distinct !DILexicalBlock(scope: !2161, file: !223, line: 1598, column: 13)
!2229 = !DILocation(line: 1599, column: 19, scope: !2228)
!2230 = !DILocation(line: 2173, column: 9, scope: !2127, inlinedAt: !2231)
!2231 = !DILocation(line: 1599, column: 17, scope: !2228)
!2232 = !DILocation(line: 1612, column: 6, scope: !2016)
!2233 = distinct !DISubprogram(name: "copy_into", linkageName: "_RNvXss_Cs9SN9c7tmF9T_9bun_allocRShNtB5_13BSSAppendable9copy_into", scope: !2234, file: !223, line: 2782, type: !20, scopeLine: 2782, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2234 = !DINamespace(name: "{impl#30}", scope: !199)
!2235 = !DILocation(line: 2783, column: 15, scope: !2233)
!2236 = !DILocation(line: 1064, column: 16, scope: !2237, inlinedAt: !2238)
!2237 = distinct !DISubprogram(name: "checked_sub", linkageName: "_RNvMs9_NtCsgXhsEb1m4tm_4core3numj11checked_sub", scope: !381, file: !380, line: 1058, type: !20, scopeLine: 1058, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2238 = !DILocation(line: 450, column: 32, scope: !2239, inlinedAt: !2240)
!2239 = distinct !DISubprogram(name: "index_mut<u8>", linkageName: "_RNvXs2_NtNtCsgXhsEb1m4tm_4core5slice5indexINtNtNtB9_3ops5range5RangejEINtB5_10SliceIndexShE9index_mutCs9SN9c7tmF9T_9bun_alloc", scope: !387, file: !385, line: 448, type: !20, scopeLine: 448, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2240 = !DILocation(line: 534, column: 23, scope: !2241, inlinedAt: !2242)
!2241 = distinct !DISubprogram(name: "index_mut<u8>", linkageName: "_RNvXs4_NtNtCsgXhsEb1m4tm_4core5slice5indexINtNtNtB9_3ops5range7RangeTojEINtB5_10SliceIndexShE9index_mutCs9SN9c7tmF9T_9bun_alloc", scope: !577, file: !385, line: 533, type: !20, scopeLine: 533, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2242 = !DILocation(line: 31, column: 15, scope: !2243, inlinedAt: !2244)
!2243 = distinct !DISubprogram(name: "index_mut<u8, core::ops::range::RangeTo<usize>>", linkageName: "_RNvXs_NtNtCsgXhsEb1m4tm_4core5slice5indexShINtNtNtB8_3ops5index8IndexMutINtNtBK_5range7RangeTojEE9index_mutCs9SN9c7tmF9T_9bun_alloc", scope: !392, file: !385, line: 30, type: !20, scopeLine: 30, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2244 = !DILocation(line: 2783, column: 12, scope: !2233)
!2245 = !DILocation(line: 2783, column: 43, scope: !2233)
!2246 = !DILocation(line: 551, column: 14, scope: !401, inlinedAt: !2247)
!2247 = distinct !DILocation(line: 5585, column: 9, scope: !403, inlinedAt: !2248)
!2248 = distinct !DILocation(line: 4326, column: 18, scope: !2249, inlinedAt: !2250)
!2249 = distinct !DISubprogram(name: "copy_from_slice<u8>", linkageName: "_RNvMNtCsgXhsEb1m4tm_4core5sliceSh15copy_from_sliceCs9SN9c7tmF9T_9bun_alloc", scope: !341, file: !340, line: 4321, type: !20, scopeLine: 4321, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2250 = !DILocation(line: 2783, column: 27, scope: !2233)
!2251 = !{!2252, !2254}
!2252 = distinct !{!2252, !2253, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: %dest.0"}
!2253 = distinct !{!2253, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc"}
!2254 = distinct !{!2254, !2253, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: %src.0"}
!2255 = !{!2256}
!2256 = distinct !{!2256, !2253, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: argument 2"}
!2257 = !DILocation(line: 2784, column: 6, scope: !2233)
!2258 = !DILocation(line: 456, column: 13, scope: !2239, inlinedAt: !2240)
!2259 = distinct !DISubprogram(name: "copy_into", linkageName: "_RNvXsu_Cs9SN9c7tmF9T_9bun_allocRSRShNtB5_13BSSAppendable9copy_into", scope: !2260, file: !223, line: 2802, type: !20, scopeLine: 2802, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2260 = !DINamespace(name: "{impl#32}", scope: !199)
!2261 = !DILocation(line: 2804, column: 20, scope: !2262)
!2262 = distinct !DILexicalBlock(scope: !2259, file: !223, line: 2803, column: 9)
!2263 = !DILocation(line: 961, column: 18, scope: !2264, inlinedAt: !2265)
!2264 = distinct !DISubprogram(name: "add<&[u8]>", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core3ptr7mut_ptrORSh3addCs9SN9c7tmF9T_9bun_alloc", scope: !316, file: !315, line: 927, type: !20, scopeLine: 927, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2265 = !DILocation(line: 102, column: 78, scope: !2266, inlinedAt: !2269)
!2266 = distinct !DILexicalBlock(scope: !2267, file: !332, line: 98, column: 9)
!2267 = distinct !DILexicalBlock(scope: !2268, file: !332, line: 97, column: 9)
!2268 = distinct !DISubprogram(name: "new<&[u8]>", linkageName: "_RNvMs4_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB5_4IterRShE3newCs9SN9c7tmF9T_9bun_alloc", scope: !335, file: !332, line: 96, type: !20, scopeLine: 96, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2269 = !DILocation(line: 1042, column: 9, scope: !2270, inlinedAt: !2271)
!2270 = distinct !DISubprogram(name: "iter<&[u8]>", linkageName: "_RNvMNtCsgXhsEb1m4tm_4core5sliceSRSh4iterCs9SN9c7tmF9T_9bun_alloc", scope: !341, file: !340, line: 1041, type: !20, scopeLine: 1041, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2271 = !DILocation(line: 26, column: 14, scope: !2272, inlinedAt: !2261)
!2272 = distinct !DISubprogram(name: "into_iter<&[u8]>", linkageName: "_RNvXs_NtNtCsgXhsEb1m4tm_4core5slice4iterRSRShNtNtNtNtB8_4iter6traits7collect12IntoIterator9into_iterCs9SN9c7tmF9T_9bun_alloc", scope: !2121, file: !332, line: 25, type: !20, scopeLine: 25, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2273 = !DILocation(line: 1714, column: 9, scope: !2274, inlinedAt: !2275)
!2274 = distinct !DISubprogram(name: "eq<&[u8]>", linkageName: "_RNvXsd_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullRShENtNtB9_3cmp9PartialEq2eqCs9SN9c7tmF9T_9bun_alloc", scope: !349, file: !348, line: 1713, type: !20, scopeLine: 1713, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2275 = !DILocation(line: 180, column: 28, scope: !2276, inlinedAt: !2279)
!2276 = distinct !DILexicalBlock(scope: !2277, file: !353, line: 162, column: 17)
!2277 = distinct !DILexicalBlock(scope: !2278, file: !353, line: 161, column: 17)
!2278 = distinct !DISubprogram(name: "next<&[u8]>", linkageName: "_RNvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB6_4IterRShENtNtNtNtBa_4iter6traits8iterator8Iterator4nextCs9SN9c7tmF9T_9bun_alloc", scope: !356, file: !353, line: 157, type: !20, scopeLine: 157, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2279 = !DILocation(line: 2804, column: 20, scope: !2280)
!2280 = !DILexicalBlockFile(scope: !2281, file: !223, discriminator: 2)
!2281 = distinct !DILexicalBlock(scope: !2262, file: !223, line: 2804, column: 9)
!2282 = !DILocation(line: 2805, column: 25, scope: !2283)
!2283 = distinct !DILexicalBlock(scope: !2281, file: !223, line: 2804, column: 9)
!2284 = !DILocation(line: 1064, column: 16, scope: !2285, inlinedAt: !2286)
!2285 = distinct !DISubprogram(name: "checked_sub", linkageName: "_RNvMs9_NtCsgXhsEb1m4tm_4core3numj11checked_sub", scope: !381, file: !380, line: 1058, type: !20, scopeLine: 1058, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2286 = !DILocation(line: 450, column: 32, scope: !2287, inlinedAt: !2288)
!2287 = distinct !DISubprogram(name: "index_mut<u8>", linkageName: "_RNvXs2_NtNtCsgXhsEb1m4tm_4core5slice5indexINtNtNtB9_3ops5range5RangejEINtB5_10SliceIndexShE9index_mutCs9SN9c7tmF9T_9bun_alloc", scope: !387, file: !385, line: 448, type: !20, scopeLine: 448, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2288 = !DILocation(line: 534, column: 23, scope: !2289, inlinedAt: !2290)
!2289 = distinct !DISubprogram(name: "index_mut<u8>", linkageName: "_RNvXs4_NtNtCsgXhsEb1m4tm_4core5slice5indexINtNtNtB9_3ops5range7RangeTojEINtB5_10SliceIndexShE9index_mutCs9SN9c7tmF9T_9bun_alloc", scope: !577, file: !385, line: 533, type: !20, scopeLine: 533, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2290 = !DILocation(line: 31, column: 15, scope: !2291, inlinedAt: !2292)
!2291 = distinct !DISubprogram(name: "index_mut<u8, core::ops::range::RangeTo<usize>>", linkageName: "_RNvXs_NtNtCsgXhsEb1m4tm_4core5slice5indexShINtNtNtB8_3ops5index8IndexMutINtNtBK_5range7RangeTojEE9index_mutCs9SN9c7tmF9T_9bun_alloc", scope: !392, file: !385, line: 30, type: !20, scopeLine: 30, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2292 = !DILocation(line: 2805, column: 22, scope: !2283)
!2293 = !DILocation(line: 2808, column: 6, scope: !2259)
!2294 = !DILocation(line: 456, column: 13, scope: !2287, inlinedAt: !2288)
!2295 = !DILocation(line: 656, column: 28, scope: !2296, inlinedAt: !2297)
!2296 = distinct !DISubprogram(name: "add<&[u8]>", linkageName: "_RNvMs1_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullRShE3addCs9SN9c7tmF9T_9bun_alloc", scope: !371, file: !348, line: 648, type: !20, scopeLine: 648, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2297 = !DILocation(line: 185, column: 40, scope: !2276, inlinedAt: !2279)
!2298 = !DILocation(line: 2805, column: 52, scope: !2283)
!2299 = !DILocation(line: 551, column: 14, scope: !401, inlinedAt: !2300)
!2300 = distinct !DILocation(line: 5585, column: 9, scope: !403, inlinedAt: !2301)
!2301 = distinct !DILocation(line: 4326, column: 18, scope: !2302, inlinedAt: !2303)
!2302 = distinct !DISubprogram(name: "copy_from_slice<u8>", linkageName: "_RNvMNtCsgXhsEb1m4tm_4core5sliceSh15copy_from_sliceCs9SN9c7tmF9T_9bun_alloc", scope: !341, file: !340, line: 4321, type: !20, scopeLine: 4321, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2303 = !DILocation(line: 2805, column: 36, scope: !2283)
!2304 = !{!2305, !2307}
!2305 = distinct !{!2305, !2306, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: %dest.0"}
!2306 = distinct !{!2306, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc"}
!2307 = distinct !{!2307, !2306, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: %src.0"}
!2308 = !{!2309}
!2309 = distinct !{!2309, !2306, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: argument 2"}
!2310 = !DILocation(line: 585, column: 27, scope: !2311, inlinedAt: !2312)
!2311 = distinct !DISubprogram(name: "index_mut<u8>", linkageName: "_RNvXs5_NtNtCsgXhsEb1m4tm_4core5slice5indexINtNtNtB9_3ops5range9RangeFromjEINtB5_10SliceIndexShE9index_mutCs9SN9c7tmF9T_9bun_alloc", scope: !456, file: !385, line: 579, type: !20, scopeLine: 579, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2312 = !DILocation(line: 31, column: 15, scope: !2313, inlinedAt: !2315)
!2313 = !DILexicalBlockFile(scope: !2314, file: !385, discriminator: 2)
!2314 = distinct !DISubprogram(name: "index_mut<u8, core::ops::range::RangeFrom<usize>>", linkageName: "_RNvXs_NtNtCsgXhsEb1m4tm_4core5slice5indexShINtNtNtB8_3ops5index8IndexMutINtNtBK_5range9RangeFromjEE9index_mutCs9SN9c7tmF9T_9bun_alloc", scope: !392, file: !385, line: 30, type: !20, scopeLine: 30, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2315 = !DILocation(line: 2806, column: 39, scope: !2283)
!2316 = !DILocation(line: 101, column: 24, scope: !2317, inlinedAt: !2319)
!2317 = distinct !DILexicalBlock(scope: !2318, file: !385, line: 99, column: 5)
!2318 = distinct !DISubprogram(name: "get_offset_len_mut_noubcheck<u8>", linkageName: "_RINvNtNtCsgXhsEb1m4tm_4core5slice5index28get_offset_len_mut_noubcheckhECs9SN9c7tmF9T_9bun_alloc", scope: !388, file: !385, line: 94, type: !20, scopeLine: 94, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2319 = !DILocation(line: 586, column: 19, scope: !2320, inlinedAt: !2312)
!2320 = distinct !DILexicalBlock(scope: !2311, file: !385, line: 585, column: 13)
!2321 = distinct !DISubprogram(name: "total_len", linkageName: "_RNvXsu_Cs9SN9c7tmF9T_9bun_allocRSRShNtB5_13BSSAppendable9total_len", scope: !2260, file: !223, line: 2799, type: !20, scopeLine: 2799, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2322 = !DILocation(line: 2800, column: 9, scope: !2321)
!2323 = !DILocation(line: 1714, column: 9, scope: !2324, inlinedAt: !2325)
!2324 = distinct !DISubprogram(name: "eq<&[u8]>", linkageName: "_RNvXsd_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullRShENtNtB9_3cmp9PartialEq2eqCs9SN9c7tmF9T_9bun_alloc", scope: !349, file: !348, line: 1713, type: !20, scopeLine: 1713, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2325 = distinct !DILocation(line: 44, column: 20, scope: !2326, inlinedAt: !2329)
!2326 = distinct !DILexicalBlock(scope: !2327, file: !353, line: 33, column: 13)
!2327 = distinct !DILexicalBlock(scope: !2328, file: !353, line: 25, column: 86)
!2328 = distinct !DISubprogram(name: "fold<&[u8], usize, core::iter::adapters::map::map_fold::{closure_env#0}<&&[u8], usize, usize, bun_alloc::{impl#32}::total_len::{closure_env#0}, core::iter::traits::accum::{impl#48}::sum::{closure_env#0}<core::iter::adapters::map::Map<core::slice::iter::Iter<&[u8]>, bun_alloc::{impl#32}::total_len::{closure_env#0}>>>>", linkageName: "_RINvXs2J_NtNtCsgXhsEb1m4tm_4core5slice4iterINtB7_4IterRShENtNtNtNtBb_4iter6traits8iterator8Iterator4foldjNCINvNtNtB10_8adapters3map8map_foldRBQ_jjNCNvXsu_Cs9SN9c7tmF9T_9bun_allocRSBQ_NtB2s_13BSSAppendable9total_len0NCINvXsK_NtBY_5accumjNtB3A_3Sum3sumINtB1K_3MapBF_B2k_EE0E0EB2s_", scope: !356, file: !353, line: 259, type: !20, scopeLine: 259, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2329 = distinct !DILocation(line: 128, column: 19, scope: !2330, inlinedAt: !2334)
!2330 = distinct !DISubprogram(name: "fold<usize, core::slice::iter::Iter<&[u8]>, bun_alloc::{impl#32}::total_len::{closure_env#0}, usize, core::iter::traits::accum::{impl#48}::sum::{closure_env#0}<core::iter::adapters::map::Map<core::slice::iter::Iter<&[u8]>, bun_alloc::{impl#32}::total_len::{closure_env#0}>>>", linkageName: "_RINvXs0_NtNtNtCsgXhsEb1m4tm_4core4iter8adapters3mapINtB6_3MapINtNtNtBc_5slice4iter4IterRShENCNvXsu_Cs9SN9c7tmF9T_9bun_allocRSB1n_NtB1z_13BSSAppendable9total_len0ENtNtNtBa_6traits8iterator8Iterator4foldjNCINvXsK_NtB2E_5accumjNtB3n_3Sum3sumBN_E0EB1z_", scope: !2332, file: !2331, line: 124, type: !20, scopeLine: 124, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2331 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/iter/adapters/map.rs", directory: "", checksumkind: CSK_MD5, checksum: "5ce513be6246907d9f12b589637a5bf6")
!2332 = !DINamespace(name: "{impl#2}", scope: !2333)
!2333 = !DINamespace(name: "map", scope: !362)
!2334 = !DILocation(line: 52, column: 22, scope: !2335, inlinedAt: !2339)
!2335 = distinct !DISubprogram(name: "sum<core::iter::adapters::map::Map<core::slice::iter::Iter<&[u8]>, bun_alloc::{impl#32}::total_len::{closure_env#0}>>", linkageName: "_RINvXsK_NtNtNtCsgXhsEb1m4tm_4core4iter6traits5accumjNtB6_3Sum3sumINtNtNtBa_8adapters3map3MapINtNtNtBc_5slice4iter4IterRShENCNvXsu_Cs9SN9c7tmF9T_9bun_allocRSB1S_NtB24_13BSSAppendable9total_len0EEB24_", scope: !2337, file: !2336, line: 51, type: !20, scopeLine: 51, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2336 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/iter/traits/accum.rs", directory: "", checksumkind: CSK_MD5, checksum: "feb1ff9fb1952daa0ee55a4414e2f66e")
!2337 = !DINamespace(name: "{impl#48}", scope: !2338)
!2338 = !DINamespace(name: "accum", scope: !1128)
!2339 = !DILocation(line: 3674, column: 9, scope: !2340, inlinedAt: !2341)
!2340 = distinct !DISubprogram(name: "sum<core::iter::adapters::map::Map<core::slice::iter::Iter<&[u8]>, bun_alloc::{impl#32}::total_len::{closure_env#0}>, usize>", linkageName: "_RINvYINtNtNtNtCsgXhsEb1m4tm_4core4iter8adapters3map3MapINtNtNtBc_5slice4iter4IterRShENCNvXsu_Cs9SN9c7tmF9T_9bun_allocRSB1h_NtB1t_13BSSAppendable9total_len0ENtNtNtBa_6traits8iterator8Iterator3sumjEB1t_", scope: !1126, file: !1124, line: 3669, type: !20, scopeLine: 3669, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2341 = !DILocation(line: 2800, column: 38, scope: !2321)
!2342 = !DILocation(line: 25, column: 86, scope: !2327, inlinedAt: !2329)
!2343 = !DILocation(line: 0, scope: !2344, inlinedAt: !2329)
!2344 = distinct !DILexicalBlock(scope: !2328, file: !353, line: 273, column: 17)
!2345 = !DILocation(line: 0, scope: !2328, inlinedAt: !2329)
!2346 = !DILocation(line: 656, column: 28, scope: !2347, inlinedAt: !2348)
!2347 = distinct !DISubprogram(name: "add<&[u8]>", linkageName: "_RNvMs1_NtNtCsgXhsEb1m4tm_4core3ptr8non_nullINtB5_7NonNullRShE3addCs9SN9c7tmF9T_9bun_alloc", scope: !371, file: !348, line: 648, type: !20, scopeLine: 648, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2348 = distinct !DILocation(line: 279, column: 67, scope: !2349, inlinedAt: !2329)
!2349 = distinct !DILexicalBlock(scope: !2350, file: !353, line: 275, column: 17)
!2350 = distinct !DILexicalBlock(scope: !2344, file: !353, line: 274, column: 17)
!2351 = !DILocation(line: 2800, column: 29, scope: !2352, inlinedAt: !2354)
!2352 = distinct !DISubprogram(name: "{closure#0}", linkageName: "_RNCNvXsu_Cs9SN9c7tmF9T_9bun_allocRSRShNtB7_13BSSAppendable9total_len0B7_", scope: !2353, file: !223, line: 2800, type: !20, scopeLine: 2800, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2353 = !DINamespace(name: "total_len", scope: !2260)
!2354 = distinct !DILocation(line: 88, column: 28, scope: !2355, inlinedAt: !2357)
!2355 = distinct !DISubprogram(name: "{closure#0}<&&[u8], usize, usize, bun_alloc::{impl#32}::total_len::{closure_env#0}, core::iter::traits::accum::{impl#48}::sum::{closure_env#0}<core::iter::adapters::map::Map<core::slice::iter::Iter<&[u8]>, bun_alloc::{impl#32}::total_len::{closure_env#0}>>>", linkageName: "_RNCINvNtNtNtCsgXhsEb1m4tm_4core4iter8adapters3map8map_foldRRShjjNCNvXsu_Cs9SN9c7tmF9T_9bun_allocRSBV_NtB18_13BSSAppendable9total_len0NCINvXsK_NtNtB8_6traits5accumjNtB2g_3Sum3sumINtB4_3MapINtNtNtBa_5slice4iter4IterBV_EB10_EE0E0B18_", scope: !2356, file: !2331, line: 88, type: !20, scopeLine: 88, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2356 = !DINamespace(name: "map_fold", scope: !2333)
!2357 = distinct !DILocation(line: 279, column: 27, scope: !2349, inlinedAt: !2329)
!2358 = !{!2359, !2361}
!2359 = distinct !{!2359, !2360, !"_RNCNvXsu_Cs9SN9c7tmF9T_9bun_allocRSRShNtB7_13BSSAppendable9total_len0B7_: %s"}
!2360 = distinct !{!2360, !"_RNCNvXsu_Cs9SN9c7tmF9T_9bun_allocRSRShNtB7_13BSSAppendable9total_len0B7_"}
!2361 = distinct !{!2361, !2362, !"_RNCINvNtNtNtCsgXhsEb1m4tm_4core4iter8adapters3map8map_foldRRShjjNCNvXsu_Cs9SN9c7tmF9T_9bun_allocRSBV_NtB18_13BSSAppendable9total_len0NCINvXsK_NtNtB8_6traits5accumjNtB2g_3Sum3sumINtB4_3MapINtNtNtBa_5slice4iter4IterBV_EB10_EE0E0B18_: %elt"}
!2362 = distinct !{!2362, !"_RNCINvNtNtNtCsgXhsEb1m4tm_4core4iter8adapters3map8map_foldRRShjjNCNvXsu_Cs9SN9c7tmF9T_9bun_allocRSBV_NtB18_13BSSAppendable9total_len0NCINvXsK_NtNtB8_6traits5accumjNtB2g_3Sum3sumINtB4_3MapINtNtNtBa_5slice4iter4IterBV_EB10_EE0E0B18_"}
!2363 = !DILocation(line: 55, column: 28, scope: !2364, inlinedAt: !2366)
!2364 = distinct !DISubprogram(name: "{closure#0}<core::iter::adapters::map::Map<core::slice::iter::Iter<&[u8]>, bun_alloc::{impl#32}::total_len::{closure_env#0}>>", linkageName: "_RNCINvXsK_NtNtNtCsgXhsEb1m4tm_4core4iter6traits5accumjNtB8_3Sum3sumINtNtNtBc_8adapters3map3MapINtNtNtBe_5slice4iter4IterRShENCNvXsu_Cs9SN9c7tmF9T_9bun_allocRSB1U_NtB26_13BSSAppendable9total_len0EE0B26_", scope: !2365, file: !2336, line: 55, type: !20, scopeLine: 55, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2365 = !DINamespace(name: "sum", scope: !2337)
!2366 = distinct !DILocation(line: 88, column: 21, scope: !2355, inlinedAt: !2357)
!2367 = !DILocation(line: 985, column: 17, scope: !2368, inlinedAt: !2369)
!2368 = distinct !DISubprogram(name: "unchecked_add", linkageName: "_RNvMs9_NtCsgXhsEb1m4tm_4core3numj13unchecked_add", scope: !381, file: !380, line: 973, type: !20, scopeLine: 973, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2369 = distinct !DILocation(line: 283, column: 36, scope: !2349, inlinedAt: !2329)
!2370 = !DILocation(line: 284, column: 24, scope: !2349, inlinedAt: !2329)
!2371 = !DILocation(line: 2801, column: 6, scope: !2321)
!2372 = distinct !DISubprogram(name: "call_once<bun_alloc::{impl#1}::NO_REMAP::{closure_env#0}, (*mut core::ffi::c_void, &mut [u8], bun_alloc::Alignment, usize, usize)>", linkageName: "_RNvYNCNvMs_Cs9SN9c7tmF9T_9bun_allocNtB9_15AllocatorVTable8NO_REMAP0INtNtNtCsgXhsEb1m4tm_4core3ops8function6FnOnceTONtNtB1a_3ffi6c_voidQShNtB9_9AlignmentjjEE9call_onceB9_", scope: !1876, file: !541, line: 250, type: !20, scopeLine: 250, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2373 = !DILocation(line: 250, column: 5, scope: !2372)
!2374 = distinct !DISubprogram(name: "call_once<bun_alloc::{impl#1}::NO_RESIZE::{closure_env#0}, (*mut core::ffi::c_void, &mut [u8], bun_alloc::Alignment, usize, usize)>", linkageName: "_RNvYNCNvMs_Cs9SN9c7tmF9T_9bun_allocNtB9_15AllocatorVTable9NO_RESIZE0INtNtNtCsgXhsEb1m4tm_4core3ops8function6FnOnceTONtNtB1b_3ffi6c_voidQShNtB9_9AlignmentjjEE9call_onceB9_", scope: !1876, file: !541, line: 250, type: !20, scopeLine: 250, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2375 = !DILocation(line: 250, column: 5, scope: !2374)
!2376 = distinct !DISubprogram(name: "write_char<bun_alloc::SliceCursor>", linkageName: "_RNvYNtCs9SN9c7tmF9T_9bun_alloc11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write10write_charB4_", scope: !2378, file: !2377, line: 183, type: !20, scopeLine: 183, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2377 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/fmt/mod.rs", directory: "", checksumkind: CSK_MD5, checksum: "216ce1117d6bd95546799c99d28aa534")
!2378 = !DINamespace(name: "Write", scope: !2379)
!2379 = !DINamespace(name: "fmt", scope: !64)
!2380 = !DILocation(line: 184, column: 43, scope: !2376)
!2381 = !DILocation(line: 2179, column: 9, scope: !2382, inlinedAt: !2385)
!2382 = distinct !DISubprogram(name: "len_utf8", linkageName: "_RNvNtNtCsgXhsEb1m4tm_4core4char7methods8len_utf8", scope: !2384, file: !2383, line: 2177, type: !20, scopeLine: 2177, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2383 = !DIFile(filename: "/Users/scc/.rustup/toolchains/nightly-2026-05-06-aarch64-apple-darwin/lib/rustlib/src/rust/library/core/src/char/methods.rs", directory: "", checksumkind: CSK_MD5, checksum: "afabc631e12c2dcf148a2b7253fad251")
!2384 = !DINamespace(name: "methods", scope: !2168)
!2385 = distinct !DILocation(line: 2209, column: 15, scope: !2386, inlinedAt: !2387)
!2386 = distinct !DISubprogram(name: "encode_utf8_raw", linkageName: "_RNvNtNtCsgXhsEb1m4tm_4core4char7methods15encode_utf8_raw", scope: !2384, file: !2383, line: 2208, type: !20, scopeLine: 2208, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2387 = distinct !DILocation(line: 716, column: 42, scope: !2388, inlinedAt: !2390)
!2388 = distinct !DISubprogram(name: "encode_utf8", linkageName: "_RNvMNtNtCsgXhsEb1m4tm_4core4char7methodsc11encode_utf8", scope: !2389, file: !2383, line: 714, type: !20, scopeLine: 714, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2389 = !DINamespace(name: "{impl#0}", scope: !2384)
!2390 = !DILocation(line: 184, column: 26, scope: !2376)
!2391 = !DILocation(line: 2180, column: 9, scope: !2382, inlinedAt: !2385)
!2392 = !DILocation(line: 2255, column: 21, scope: !2393, inlinedAt: !2395)
!2393 = distinct !DILexicalBlock(scope: !2394, file: !2383, line: 2246, column: 5)
!2394 = distinct !DISubprogram(name: "encode_utf8_raw_unchecked", linkageName: "_RNvNtNtCsgXhsEb1m4tm_4core4char7methods25encode_utf8_raw_unchecked", scope: !2384, file: !2383, line: 2245, type: !20, scopeLine: 2245, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2395 = distinct !DILocation(line: 2221, column: 14, scope: !2396, inlinedAt: !2387)
!2396 = distinct !DILexicalBlock(scope: !2386, file: !2383, line: 2209, column: 5)
!2397 = !DILocation(line: 2256, column: 22, scope: !2398, inlinedAt: !2395)
!2398 = distinct !DILexicalBlock(scope: !2393, file: !2383, line: 2255, column: 9)
!2399 = !DILocation(line: 2256, column: 21, scope: !2398, inlinedAt: !2395)
!2400 = !DILocation(line: 2257, column: 22, scope: !2401, inlinedAt: !2395)
!2401 = distinct !DILexicalBlock(scope: !2398, file: !2383, line: 2256, column: 9)
!2402 = !DILocation(line: 2257, column: 21, scope: !2401, inlinedAt: !2395)
!2403 = !DILocation(line: 2258, column: 22, scope: !2404, inlinedAt: !2395)
!2404 = distinct !DILexicalBlock(scope: !2401, file: !2383, line: 2257, column: 9)
!2405 = !DILocation(line: 2258, column: 21, scope: !2404, inlinedAt: !2395)
!2406 = !DILocation(line: 2260, column: 12, scope: !2407, inlinedAt: !2395)
!2407 = distinct !DILexicalBlock(scope: !2404, file: !2383, line: 2258, column: 9)
!2408 = !DILocation(line: 2251, column: 13, scope: !2393, inlinedAt: !2395)
!2409 = !{!2410}
!2410 = distinct !{!2410, !2411, !"_RNvNtNtCsgXhsEb1m4tm_4core4char7methods15encode_utf8_raw: %dst.0"}
!2411 = distinct !{!2411, !"_RNvNtNtCsgXhsEb1m4tm_4core4char7methods15encode_utf8_raw"}
!2412 = !DILocation(line: 0, scope: !2413, inlinedAt: !2395)
!2413 = !DILexicalBlockFile(scope: !2393, file: !223, discriminator: 0)
!2414 = !DILocation(line: 2261, column: 13, scope: !2407, inlinedAt: !2395)
!2415 = !DILocation(line: 2262, column: 13, scope: !2407, inlinedAt: !2395)
!2416 = !DILocation(line: 0, scope: !2417, inlinedAt: !2395)
!2417 = !DILexicalBlockFile(scope: !2407, file: !223, discriminator: 0)
!2418 = !DILocation(line: 2266, column: 12, scope: !2407, inlinedAt: !2395)
!2419 = !DILocation(line: 2267, column: 13, scope: !2407, inlinedAt: !2395)
!2420 = !DILocation(line: 2268, column: 13, scope: !2407, inlinedAt: !2395)
!2421 = !DILocation(line: 2269, column: 13, scope: !2407, inlinedAt: !2395)
!2422 = !DILocation(line: 2273, column: 9, scope: !2407, inlinedAt: !2395)
!2423 = !DILocation(line: 2274, column: 9, scope: !2407, inlinedAt: !2395)
!2424 = !DILocation(line: 2275, column: 9, scope: !2407, inlinedAt: !2395)
!2425 = !DILocation(line: 2276, column: 9, scope: !2407, inlinedAt: !2395)
!2426 = !DILocation(line: 2278, column: 2, scope: !2394, inlinedAt: !2395)
!2427 = !{!2428}
!2428 = distinct !{!2428, !2429, !"_RNvXs6_Cs9SN9c7tmF9T_9bun_allocNtB5_11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_str: %self"}
!2429 = distinct !{!2429, !"_RNvXs6_Cs9SN9c7tmF9T_9bun_allocNtB5_11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_str"}
!2430 = !DILocation(line: 184, column: 14, scope: !2376)
!2431 = !DILocation(line: 703, column: 19, scope: !1966, inlinedAt: !2432)
!2432 = distinct !DILocation(line: 184, column: 14, scope: !2376)
!2433 = !{!2434}
!2434 = distinct !{!2434, !2429, !"_RNvXs6_Cs9SN9c7tmF9T_9bun_allocNtB5_11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_str: %s.0"}
!2435 = !DILocation(line: 704, column: 18, scope: !1968, inlinedAt: !2432)
!2436 = !DILocation(line: 704, column: 12, scope: !1968, inlinedAt: !2432)
!2437 = !DILocation(line: 1064, column: 16, scope: !1971, inlinedAt: !2438)
!2438 = distinct !DILocation(line: 450, column: 32, scope: !1973, inlinedAt: !2439)
!2439 = distinct !DILocation(line: 31, column: 15, scope: !1975, inlinedAt: !2440)
!2440 = distinct !DILocation(line: 707, column: 17, scope: !1968, inlinedAt: !2432)
!2441 = !DILocation(line: 707, column: 9, scope: !1968, inlinedAt: !2432)
!2442 = !DILocation(line: 101, column: 24, scope: !1979, inlinedAt: !2443)
!2443 = distinct !DILocation(line: 454, column: 28, scope: !1973, inlinedAt: !2439)
!2444 = !DILocation(line: 551, column: 14, scope: !401, inlinedAt: !2445)
!2445 = distinct !DILocation(line: 5585, column: 9, scope: !403, inlinedAt: !2446)
!2446 = distinct !DILocation(line: 4326, column: 18, scope: !1985, inlinedAt: !2447)
!2447 = distinct !DILocation(line: 707, column: 32, scope: !1968, inlinedAt: !2432)
!2448 = !{!2449, !2451}
!2449 = distinct !{!2449, !2450, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: %dest.0"}
!2450 = distinct !{!2450, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc"}
!2451 = distinct !{!2451, !2450, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: %src.0"}
!2452 = !{!2453, !2428}
!2453 = distinct !{!2453, !2450, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: argument 2"}
!2454 = !DILocation(line: 708, column: 9, scope: !1968, inlinedAt: !2432)
!2455 = !DILocation(line: 710, column: 6, scope: !1963, inlinedAt: !2432)
!2456 = !DILocation(line: 456, column: 13, scope: !1973, inlinedAt: !2439)
!2457 = !{!2428, !2434}
!2458 = !DILocation(line: 184, column: 67, scope: !2376)
!2459 = !DILocation(line: 185, column: 6, scope: !2376)
!2460 = distinct !DISubprogram(name: "write_fmt<bun_alloc::SliceCursor>", linkageName: "_RNvYNtCs9SN9c7tmF9T_9bun_alloc11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_fmtB4_", scope: !2378, file: !2377, line: 212, type: !20, scopeLine: 212, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2461 = !{!2462}
!2462 = distinct !{!2462, !2463, !"_RNvXs_NvNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_fmtQNtCs9SN9c7tmF9T_9bun_alloc11SliceCursorNtB4_12SpecWriteFmt14spec_write_fmtBQ_: %self"}
!2463 = distinct !{!2463, !"_RNvXs_NvNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_fmtQNtCs9SN9c7tmF9T_9bun_alloc11SliceCursorNtB4_12SpecWriteFmt14spec_write_fmtBQ_"}
!2464 = !DILocation(line: 241, column: 14, scope: !2460)
!2465 = !DILocation(line: 877, column: 36, scope: !2466, inlinedAt: !2468)
!2466 = distinct !DISubprogram(name: "as_str", linkageName: "_RNvMs4_NtCsgXhsEb1m4tm_4core3fmtNtB5_9Arguments6as_str", scope: !2467, file: !2377, line: 871, type: !20, scopeLine: 871, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2467 = !DINamespace(name: "Arguments", scope: !2379)
!2468 = distinct !DILocation(line: 897, column: 22, scope: !2469, inlinedAt: !2470)
!2469 = distinct !DISubprogram(name: "as_statically_known_str", linkageName: "_RNvMs4_NtCsgXhsEb1m4tm_4core3fmtNtB5_9Arguments23as_statically_known_str", scope: !2467, file: !2377, line: 896, type: !20, scopeLine: 896, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2470 = distinct !DILocation(line: 233, column: 39, scope: !2471, inlinedAt: !2475)
!2471 = distinct !DILexicalBlock(scope: !2472, file: !2377, line: 233, column: 65)
!2472 = distinct !DISubprogram(name: "spec_write_fmt<bun_alloc::SliceCursor>", linkageName: "_RNvXs_NvNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_fmtQNtCs9SN9c7tmF9T_9bun_alloc11SliceCursorNtB4_12SpecWriteFmt14spec_write_fmtBQ_", scope: !2473, file: !2377, line: 232, type: !20, scopeLine: 232, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition | DISPFlagOptimized, unit: !4, templateParams: !14)
!2473 = !DINamespace(name: "{impl#1}", scope: !2474)
!2474 = !DINamespace(name: "write_fmt", scope: !2378)
!2475 = distinct !DILocation(line: 241, column: 14, scope: !2460)
!2476 = !DILocation(line: 878, column: 12, scope: !2477, inlinedAt: !2468)
!2477 = distinct !DILexicalBlock(scope: !2466, file: !2377, line: 877, column: 9)
!2478 = !DILocation(line: 898, column: 12, scope: !2479, inlinedAt: !2470)
!2479 = distinct !DILexicalBlock(scope: !2469, file: !2377, line: 897, column: 9)
!2480 = !DILocation(line: 233, column: 24, scope: !2471, inlinedAt: !2475)
!2481 = !{!2482}
!2482 = distinct !{!2482, !2483, !"_RNvXs6_Cs9SN9c7tmF9T_9bun_allocNtB5_11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_str: %self"}
!2483 = distinct !{!2483, !"_RNvXs6_Cs9SN9c7tmF9T_9bun_allocNtB5_11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_str"}
!2484 = !DILocation(line: 234, column: 26, scope: !2471, inlinedAt: !2475)
!2485 = !DILocation(line: 703, column: 19, scope: !1966, inlinedAt: !2486)
!2486 = distinct !DILocation(line: 234, column: 26, scope: !2471, inlinedAt: !2475)
!2487 = !{!2482, !2462}
!2488 = !{!2489}
!2489 = distinct !{!2489, !2483, !"_RNvXs6_Cs9SN9c7tmF9T_9bun_allocNtB5_11SliceCursorNtNtCsgXhsEb1m4tm_4core3fmt5Write9write_str: %s.0"}
!2490 = !DILocation(line: 704, column: 18, scope: !1968, inlinedAt: !2486)
!2491 = !DILocation(line: 704, column: 12, scope: !1968, inlinedAt: !2486)
!2492 = !DILocation(line: 1064, column: 16, scope: !1971, inlinedAt: !2493)
!2493 = distinct !DILocation(line: 450, column: 32, scope: !1973, inlinedAt: !2494)
!2494 = distinct !DILocation(line: 31, column: 15, scope: !1975, inlinedAt: !2495)
!2495 = distinct !DILocation(line: 707, column: 17, scope: !1968, inlinedAt: !2486)
!2496 = !DILocation(line: 707, column: 9, scope: !1968, inlinedAt: !2486)
!2497 = !DILocation(line: 101, column: 24, scope: !1979, inlinedAt: !2498)
!2498 = distinct !DILocation(line: 454, column: 28, scope: !1973, inlinedAt: !2494)
!2499 = !DILocation(line: 551, column: 14, scope: !401, inlinedAt: !2500)
!2500 = distinct !DILocation(line: 5585, column: 9, scope: !403, inlinedAt: !2501)
!2501 = distinct !DILocation(line: 4326, column: 18, scope: !1985, inlinedAt: !2502)
!2502 = distinct !DILocation(line: 707, column: 32, scope: !1968, inlinedAt: !2486)
!2503 = !{!2504, !2506}
!2504 = distinct !{!2504, !2505, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: %dest.0"}
!2505 = distinct !{!2505, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc"}
!2506 = distinct !{!2506, !2505, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: %src.0"}
!2507 = !{!2508, !2482, !2462}
!2508 = distinct !{!2508, !2505, !"_RINvNtCsgXhsEb1m4tm_4core5slice20copy_from_slice_implhECs9SN9c7tmF9T_9bun_alloc: argument 2"}
!2509 = !DILocation(line: 708, column: 9, scope: !1968, inlinedAt: !2486)
!2510 = !DILocation(line: 710, column: 6, scope: !1963, inlinedAt: !2486)
!2511 = !DILocation(line: 456, column: 13, scope: !1973, inlinedAt: !2494)
!2512 = !{!2482, !2489, !2462}
!2513 = !DILocation(line: 236, column: 21, scope: !2472, inlinedAt: !2475)
!2514 = !DILocation(line: 233, column: 17, scope: !2472, inlinedAt: !2475)
!2515 = !DILocation(line: 242, column: 6, scope: !2460)
