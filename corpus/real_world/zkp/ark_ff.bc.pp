; ModuleID = '2rovt6hiwg4ufmu3kspx9ja6y'
source_filename = "2rovt6hiwg4ufmu3kspx9ja6y"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx11.0.0"

@_ZN6ark_ff6fields13field_hashers8expander5Z_PAD17h429cf4cd47cb14c5E = local_unnamed_addr constant [256 x i8] zeroinitializer, align 1
@anon.6a88fb9413c64201b246cbfc94acc414.0 = private unnamed_addr constant [24 x i8] c"\00\00\00\00\00\00\00\00\08\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00", align 8
@alloc_5bd1ef6667dbdbecff436d9509a4d052 = private unnamed_addr constant [25 x i8] c"attempt to divide by zero", align 1
@alloc_cb1b5e0d8bde5c631b6fbaedfa80be7c = private unnamed_addr constant [105 x i8] c"/Users/scc/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/num-bigint-0.4.6/src/biguint/division.rs\00", align 1
@alloc_e3d07c9a456e140e9ef6adfe3c5410bd = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_cb1b5e0d8bde5c631b6fbaedfa80be7c, [16 x i8] c"h\00\00\00\00\00\00\00p\00\00\00\09\00\00\00" }>, align 8
@alloc_11fd33a4cffadb0d1fc9cf8d055eec57 = private unnamed_addr constant [32 x i8] c"ff/src/biginteger/arithmetic.rs\00", align 1
@alloc_7d834dc979dd7e6c505371ff41ed382a = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_11fd33a4cffadb0d1fc9cf8d055eec57, [16 x i8] c"\1F\00\00\00\00\00\00\00\BA\00\00\00\0B\00\00\00" }>, align 8
@alloc_4daf50f339ef7b3a002c046235714f6a = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_11fd33a4cffadb0d1fc9cf8d055eec57, [16 x i8] c"\1F\00\00\00\00\00\00\00\BA\00\00\00 \00\00\00" }>, align 8
@alloc_bc673ea3c3ad96065ec8bb1deafe00d9 = private unnamed_addr constant [44 x i8] c"ff/src/fields/field_hashers/expander/mod.rs\00", align 1
@alloc_8499ff2c1595e9316e5a0a3b791b0542 = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_bc673ea3c3ad96065ec8bb1deafe00d9, [16 x i8] c"+\00\00\00\00\00\00\00@\00\00\00\10\00\00\00" }>, align 8
@alloc_d84795fc96f9353575c5dc0c3a873e06 = private unnamed_addr constant [23 x i8] c"ff/src/fields/utils.rs\00", align 1
@alloc_4ae90411e11a4480270944339e0507fa = private unnamed_addr constant <{ ptr, [16 x i8] }> <{ ptr @alloc_d84795fc96f9353575c5dc0c3a873e06, [16 x i8] c"\16\00\00\00\00\00\00\00\0B\00\00\00\0B\00\00\00" }>, align 8

; alloc::raw_vec::RawVec<T,A>::grow_one
; Function Attrs: cold noinline nounwind
define void @"_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17hfa9f949b2c7017f8E"(ptr noalias noundef align 8 captures(none) dereferenceable(16) %self) unnamed_addr #0 personality ptr @rust_eh_personality {
start:
  %self3.i = alloca [24 x i8], align 8
  %self1 = load i64, ptr %self, align 8, !range !2, !noundef !3
  tail call void @llvm.experimental.noalias.scope.decl(metadata !4)
  %v16.i = shl nuw i64 %self1, 1
  %0 = tail call i64 @llvm.umax.i64(i64 %v16.i, i64 8)
  call void @llvm.lifetime.start.p0(ptr nonnull %self3.i), !noalias !4
  %1 = getelementptr inbounds nuw i8, ptr %self, i64 8
  %self.val15.i = load ptr, ptr %1, align 8, !alias.scope !4
; call alloc::raw_vec::RawVecInner<A>::finish_grow
  call fastcc void @"_ZN5alloc7raw_vec20RawVecInner$LT$A$GT$11finish_grow17h855eb00d3b28eec9E"(ptr noalias noundef align 8 captures(address) dereferenceable(24) %self3.i, i64 %self1, ptr %self.val15.i, i64 noundef %0) #20
  %_37.i = load i64, ptr %self3.i, align 8, !range !7, !noalias !4, !noundef !3
  %2 = trunc nuw i64 %_37.i to i1
  %3 = getelementptr inbounds nuw i8, ptr %self3.i, i64 8
  br i1 %2, label %bb18.i, label %bb3

bb18.i:                                           ; preds = %start
  %e.0.i = load i64, ptr %3, align 8, !range !8, !noalias !4, !noundef !3
  %4 = getelementptr inbounds nuw i8, ptr %self3.i, i64 16
  %e.1.i = load i64, ptr %4, align 8, !noalias !4
  call void @llvm.lifetime.end.p0(ptr nonnull %self3.i), !noalias !4
; call alloc::raw_vec::handle_error
  tail call void @_RNvNtCs1OjIl8oxbrv_5alloc7raw_vec12handle_error(i64 noundef %e.0.i, i64 %e.1.i) #21
  unreachable

bb3:                                              ; preds = %start
  %v.0.i = load ptr, ptr %3, align 8, !noalias !4, !nonnull !3, !noundef !3
  call void @llvm.lifetime.end.p0(ptr nonnull %self3.i), !noalias !4
  store ptr %v.0.i, ptr %1, align 8, !alias.scope !4
  %5 = icmp sgt i64 %0, -1
  tail call void @llvm.assume(i1 %5)
  store i64 %0, ptr %self, align 8, !alias.scope !4
  ret void
}

; alloc::raw_vec::RawVecInner<A>::finish_grow
; Function Attrs: cold nounwind
define internal fastcc void @"_ZN5alloc7raw_vec20RawVecInner$LT$A$GT$11finish_grow17h855eb00d3b28eec9E"(ptr dead_on_unwind noalias noundef nonnull writable writeonly align 8 captures(none) dereferenceable(24) initializes((0, 8)) %_0, i64 %self.0.val, ptr %self.8.val, i64 noundef %cap) unnamed_addr #1 {
start:
  %_38 = icmp sgt i64 %cap, -1
  br i1 %_38, label %bb15, label %bb11

bb15:                                             ; preds = %start
  %0 = icmp eq i64 %self.0.val, 0
  br i1 %0, label %bb5, label %_RNvXs_NtCs1OjIl8oxbrv_5alloc5allocNtB4_6GlobalNtNtCsl8K0bEFm1U0_4core5alloc9Allocator4grow.exit

_RNvXs_NtCs1OjIl8oxbrv_5alloc5allocNtB4_6GlobalNtNtCsl8K0bEFm1U0_4core5alloc9Allocator4grow.exit: ; preds = %bb15
  %1 = icmp ne ptr %self.8.val, null
  tail call void @llvm.assume(i1 %1)
  %cond.i.i = icmp uge i64 %cap, %self.0.val
  tail call void @llvm.assume(i1 %cond.i.i)
; call __rustc::__rust_realloc
  %raw_ptr.i.i = tail call noundef ptr @_RNvCsfLfy6EI15iL_7___rustc14___rust_realloc(ptr noundef nonnull %self.8.val, i64 noundef %self.0.val, i64 noundef 1, i64 noundef range(i64 0, -9223372036854775808) %cap) #20
  br label %bb7

bb5:                                              ; preds = %bb15
  %2 = icmp eq i64 %cap, 0
  br i1 %2, label %bb9, label %bb4.i.i

bb4.i.i:                                          ; preds = %bb5
; call __rustc::__rust_no_alloc_shim_is_unstable_v2
  tail call void @_RNvCsfLfy6EI15iL_7___rustc35___rust_no_alloc_shim_is_unstable_v2() #20
; call __rustc::__rust_alloc
  %3 = tail call noundef ptr @_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc(i64 noundef range(i64 0, -9223372036854775808) %cap, i64 noundef range(i64 1, 9) 1) #20
  br label %bb7

bb7:                                              ; preds = %bb4.i.i, %_RNvXs_NtCs1OjIl8oxbrv_5alloc5allocNtB4_6GlobalNtNtCsl8K0bEFm1U0_4core5alloc9Allocator4grow.exit
  %raw_ptr.i.i.pn = phi ptr [ %raw_ptr.i.i, %_RNvXs_NtCs1OjIl8oxbrv_5alloc5allocNtB4_6GlobalNtNtCsl8K0bEFm1U0_4core5alloc9Allocator4grow.exit ], [ %3, %bb4.i.i ]
  %4 = icmp eq ptr %raw_ptr.i.i.pn, null
  br i1 %4, label %bb8, label %bb9

bb8:                                              ; preds = %bb7
  %5 = getelementptr inbounds nuw i8, ptr %_0, i64 8
  store i64 1, ptr %5, align 8
  br label %bb11

bb9:                                              ; preds = %bb5, %bb7
  %raw_ptr.i.i.pn7 = phi ptr [ %raw_ptr.i.i.pn, %bb7 ], [ inttoptr (i64 1 to ptr), %bb5 ]
  %6 = getelementptr inbounds nuw i8, ptr %_0, i64 8
  store ptr %raw_ptr.i.i.pn7, ptr %6, align 8
  br label %bb11

bb11:                                             ; preds = %start, %bb9, %bb8
  %.sink8 = phi i64 [ 16, %bb9 ], [ 16, %bb8 ], [ 8, %start ]
  %cap.sink = phi i64 [ %cap, %bb9 ], [ %cap, %bb8 ], [ 0, %start ]
  %storemerge8 = phi i64 [ 0, %bb9 ], [ 1, %bb8 ], [ 1, %start ]
  %7 = getelementptr inbounds nuw i8, ptr %_0, i64 %.sink8
  store i64 %cap.sink, ptr %7, align 8
  store i64 %storemerge8, ptr %_0, align 8
  ret void
}

; ark_ff::biginteger::arithmetic::find_relaxed_naf
; Function Attrs: nounwind
define void @_ZN6ark_ff10biginteger10arithmetic16find_relaxed_naf17h84ddcc088a1711edE(ptr dead_on_unwind noalias noundef writable writeonly sret([24 x i8]) align 8 captures(none) dereferenceable(24) %_0, ptr noalias noundef nonnull readonly align 8 captures(none) %num.0, i64 noundef range(i64 0, 1152921504606846976) %num.1) unnamed_addr #2 personality ptr @rust_eh_personality {
start:
  %res = alloca [24 x i8], align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %res)
; call ark_ff::biginteger::arithmetic::find_naf
  call void @_ZN6ark_ff10biginteger10arithmetic8find_naf17hb5df30b7e88862beE(ptr noalias noundef nonnull sret([24 x i8]) align 8 captures(address) dereferenceable(24) %res, ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) %num.0, i64 noundef %num.1) #20
  %0 = getelementptr inbounds nuw i8, ptr %res, i64 16
  %res.val = load i64, ptr %0, align 8, !noundef !3
  %_2.i = icmp sgt i64 %res.val, -1
  tail call void @llvm.assume(i1 %_2.i)
  %_8 = add nsw i64 %res.val, -2
  %1 = getelementptr inbounds nuw i8, ptr %res, i64 8
  %res.val3 = load ptr, ptr %1, align 8, !nonnull !3, !noundef !3
  %_4.i.i = icmp samesign ugt i64 %res.val, 1
  br i1 %_4.i.i, label %"_ZN81_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..Index$LT$I$GT$$GT$5index17h2703f0e553bae577E.exit", label %panic.i.i

panic.i.i:                                        ; preds = %start
; call core::panicking::panic_bounds_check
  tail call void @_RNvNtCsl8K0bEFm1U0_4core9panicking18panic_bounds_check(i64 noundef range(i64 -3, 9223372036854775806) %_8, i64 noundef range(i64 0, -9223372036854775808) %res.val, ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_7d834dc979dd7e6c505371ff41ed382a) #22, !noalias !9
  unreachable

"_ZN81_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..Index$LT$I$GT$$GT$5index17h2703f0e553bae577E.exit": ; preds = %start
  %_0.i.i = getelementptr inbounds nuw i8, ptr %res.val3, i64 %_8
  %_5 = load i8, ptr %_0.i.i, align 1, !noundef !3
  %2 = icmp eq i8 %_5, 0
  br i1 %2, label %bb4, label %bb12

bb4:                                              ; preds = %"_ZN81_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..Index$LT$I$GT$$GT$5index17h2703f0e553bae577E.exit"
  %_12 = add nsw i64 %res.val, -3
  %_4.i.i9.not = icmp eq i64 %res.val, 2
  br i1 %_4.i.i9.not, label %panic.i.i10, label %"_ZN81_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..Index$LT$I$GT$$GT$5index17h2703f0e553bae577E.exit12"

panic.i.i10:                                      ; preds = %bb4
; call core::panicking::panic_bounds_check
  tail call void @_RNvNtCsl8K0bEFm1U0_4core9panicking18panic_bounds_check(i64 noundef range(i64 -3, 9223372036854775806) %_12, i64 noundef range(i64 0, -9223372036854775808) 2, ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_4daf50f339ef7b3a002c046235714f6a) #22, !noalias !12
  unreachable

"_ZN81_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..Index$LT$I$GT$$GT$5index17h2703f0e553bae577E.exit12": ; preds = %bb4
  %_0.i.i11 = getelementptr inbounds nuw i8, ptr %res.val3, i64 %_12
  %_9 = load i8, ptr %_0.i.i11, align 1, !noundef !3
  %3 = icmp eq i8 %_9, -1
  br i1 %3, label %"_ZN84_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..IndexMut$LT$I$GT$$GT$9index_mut17h1fd31c350ef9be37E.exit19", label %bb12

"_ZN84_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..IndexMut$LT$I$GT$$GT$9index_mut17h1fd31c350ef9be37E.exit19": ; preds = %"_ZN81_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..Index$LT$I$GT$$GT$5index17h2703f0e553bae577E.exit12"
  store i8 1, ptr %_0.i.i11, align 1
  store i8 1, ptr %_0.i.i, align 1
  %_19 = add nsw i64 %res.val, -1
  store i64 %_19, ptr %0, align 8, !alias.scope !15
  br label %bb12

bb12:                                             ; preds = %"_ZN81_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..Index$LT$I$GT$$GT$5index17h2703f0e553bae577E.exit12", %"_ZN81_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..Index$LT$I$GT$$GT$5index17h2703f0e553bae577E.exit", %"_ZN84_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..IndexMut$LT$I$GT$$GT$9index_mut17h1fd31c350ef9be37E.exit19"
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %_0, ptr noundef nonnull align 8 dereferenceable(24) %res, i64 24, i1 false)
  call void @llvm.lifetime.end.p0(ptr nonnull %res)
  ret void
}

; ark_ff::biginteger::arithmetic::find_naf
; Function Attrs: nounwind
define void @_ZN6ark_ff10biginteger10arithmetic8find_naf17hb5df30b7e88862beE(ptr dead_on_unwind noalias noundef writable writeonly sret([24 x i8]) align 8 captures(none) dereferenceable(24) %_0, ptr noalias noundef nonnull readonly align 8 captures(none) %num.0, i64 noundef range(i64 0, 1152921504606846976) %num.1) unnamed_addr #2 personality ptr @rust_eh_personality {
start:
  %res = alloca [24 x i8], align 8
  %0 = shl nuw nsw i64 %num.1, 3
  %1 = icmp eq i64 %num.1, 0
  br i1 %1, label %"_ZN5alloc5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$6to_vec17h3b347af2562b6b4fE.exit", label %_RNvXs_NtCs1OjIl8oxbrv_5alloc5allocNtB4_6GlobalNtNtCsl8K0bEFm1U0_4core5alloc9Allocator8allocate.exit.i.i.i.i

_RNvXs_NtCs1OjIl8oxbrv_5alloc5allocNtB4_6GlobalNtNtCsl8K0bEFm1U0_4core5alloc9Allocator8allocate.exit.i.i.i.i: ; preds = %start
; call __rustc::__rust_no_alloc_shim_is_unstable_v2
  tail call void @_RNvCsfLfy6EI15iL_7___rustc35___rust_no_alloc_shim_is_unstable_v2() #20, !noalias !18
; call __rustc::__rust_alloc
  %2 = tail call noundef align 8 ptr @_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc(i64 noundef range(i64 0, -9223372036854775808) %0, i64 noundef range(i64 1, 9) 8) #20, !noalias !18
  %3 = icmp eq ptr %2, null
  br i1 %3, label %bb3.i.i.i, label %bb1.i.i

bb3.i.i.i:                                        ; preds = %_RNvXs_NtCs1OjIl8oxbrv_5alloc5allocNtB4_6GlobalNtNtCsl8K0bEFm1U0_4core5alloc9Allocator8allocate.exit.i.i.i.i
; call alloc::raw_vec::handle_error
  tail call void @_RNvNtCs1OjIl8oxbrv_5alloc7raw_vec12handle_error(i64 noundef 8, i64 %0) #21, !noalias !27
  unreachable

bb1.i.i:                                          ; preds = %_RNvXs_NtCs1OjIl8oxbrv_5alloc5allocNtB4_6GlobalNtNtCsl8K0bEFm1U0_4core5alloc9Allocator8allocate.exit.i.i.i.i
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 8 %2, ptr nonnull readonly align 8 %num.0, i64 %0, i1 false), !noalias !28
  br label %"_ZN5alloc5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$6to_vec17h3b347af2562b6b4fE.exit"

"_ZN5alloc5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$6to_vec17h3b347af2562b6b4fE.exit": ; preds = %start, %bb1.i.i
  %num.sroa.5.0 = phi ptr [ %2, %bb1.i.i ], [ inttoptr (i64 8 to ptr), %start ]
  call void @llvm.lifetime.start.p0(ptr nonnull %res)
  store i64 0, ptr %res, align 8, !alias.scope !29
  %4 = getelementptr inbounds nuw i8, ptr %res, i64 8
  store ptr inttoptr (i64 1 to ptr), ptr %4, align 8, !alias.scope !29
  %5 = getelementptr inbounds nuw i8, ptr %res, i64 16
  store i64 0, ptr %5, align 8, !alias.scope !29
  %_6.i.i.i = getelementptr inbounds nuw i64, ptr %num.sroa.5.0, i64 %num.1
  %6 = getelementptr inbounds nuw i8, ptr %num.sroa.5.0, i64 %0
  br label %bb2

bb2:                                              ; preds = %bb3.i.i.i19, %"_ZN5alloc5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$6to_vec17h3b347af2562b6b4fE.exit"
  br label %bb1.i.i17

bb1.i.i17:                                        ; preds = %bb13.i.i, %bb2
  %_221.i.i = phi ptr [ %_22.i.i, %bb13.i.i ], [ %num.sroa.5.0, %bb2 ]
  %_12.not.not.not.i.not.not.not.i.not = icmp eq ptr %_221.i.i, %_6.i.i.i
  br i1 %_12.not.not.not.i.not.not.not.i.not, label %bb22, label %bb13.i.i

bb13.i.i:                                         ; preds = %bb1.i.i17
  %_22.i.i = getelementptr inbounds nuw i8, ptr %_221.i.i, i64 8
  %ptr.val.i.i = load i64, ptr %_221.i.i, align 8, !alias.scope !32, !noalias !35, !noundef !3
  %_0.i.not.i.i = icmp eq i64 %ptr.val.i.i, 0
  br i1 %_0.i.not.i.i, label %bb1.i.i17, label %bb5

bb22:                                             ; preds = %bb1.i.i17
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %_0, ptr noundef nonnull align 8 dereferenceable(24) %res, i64 24, i1 false)
  call void @llvm.lifetime.end.p0(ptr nonnull %res)
  br i1 %1, label %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$u64$GT$$GT$17hf6fe82517f9993d1E.exit", label %bb2.i.i.i.i

bb2.i.i.i.i:                                      ; preds = %bb22
; call __rustc::__rust_dealloc
  tail call void @_RNvCsfLfy6EI15iL_7___rustc14___rust_dealloc(ptr noundef nonnull %num.sroa.5.0, i64 noundef %0, i64 noundef range(i64 1, -9223372036854775807) 8) #20
  br label %"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$u64$GT$$GT$17hf6fe82517f9993d1E.exit"

"_ZN4core3ptr47drop_in_place$LT$alloc..vec..Vec$LT$u64$GT$$GT$17hf6fe82517f9993d1E.exit": ; preds = %bb22, %bb2.i.i.i.i
  ret void

bb5:                                              ; preds = %bb13.i.i
  %_4.i = load i64, ptr %num.sroa.5.0, align 8, !alias.scope !38, !noundef !3
  %_3.i = and i64 %_4.i, 1
  %_0.i.not = icmp eq i64 %_3.i, 0
  br i1 %_0.i.not, label %bb18, label %"_ZN81_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..Index$LT$I$GT$$GT$5index17hd135ae0287503048E.exit"

"_ZN81_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..Index$LT$I$GT$$GT$5index17hd135ae0287503048E.exit": ; preds = %bb5
  %7 = trunc i64 %_4.i to i8
  %_20 = and i8 %7, 3
  %8 = sub nsw i8 2, %_20
  %_25.not = icmp eq i8 %_20, 3
  br i1 %_25.not, label %bb20.us.i.i.i.i, label %bb10

bb18:                                             ; preds = %bb20.us.i.i.i.i21, %bb20.us.i.i.i.i, %bb5
  %z.sroa.0.0 = phi i8 [ -1, %bb20.us.i.i.i.i ], [ 0, %bb5 ], [ %8, %bb20.us.i.i.i.i21 ]
  tail call void @llvm.experimental.noalias.scope.decl(metadata !41)
  tail call void @llvm.experimental.noalias.scope.decl(metadata !44)
  %len.i.i = load i64, ptr %5, align 8, !alias.scope !47, !noundef !3
  %self1.i.i = load i64, ptr %res, align 8, !range !2, !alias.scope !47, !noundef !3
  %_4.i.i = icmp eq i64 %len.i.i, %self1.i.i
  br i1 %_4.i.i, label %bb1.i.i18, label %bb3.i.i.preheader.i

bb1.i.i18:                                        ; preds = %bb18
; call alloc::raw_vec::RawVec<T,A>::grow_one
  call void @"_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17hfa9f949b2c7017f8E"(ptr noalias noundef nonnull align 8 dereferenceable(24) %res) #23
  br label %bb3.i.i.preheader.i

bb3.i.i.preheader.i:                              ; preds = %bb1.i.i18, %bb18
  %_14.i.i = load ptr, ptr %4, align 8, !alias.scope !47, !nonnull !3, !noundef !3
  %end.i.i = getelementptr inbounds nuw i8, ptr %_14.i.i, i64 %len.i.i
  store i8 %z.sroa.0.0, ptr %end.i.i, align 1, !noalias !47
  %9 = add i64 %len.i.i, 1
  store i64 %9, ptr %5, align 8, !alias.scope !47
  br label %bb3.i.i.i19

bb3.i.i.i19:                                      ; preds = %bb3.i.i.i19, %bb3.i.i.preheader.i
  %accum.sroa.0.06.i.i.i = phi i64 [ %next_carry.i.i.i.i, %bb3.i.i.i19 ], [ 0, %bb3.i.i.preheader.i ]
  %self.sroa.2.05.i.i.i = phi ptr [ %_23.i.i.i.i, %bb3.i.i.i19 ], [ %6, %bb3.i.i.preheader.i ]
  %_23.i.i.i.i = getelementptr inbounds i8, ptr %self.sroa.2.05.i.i.i, i64 -8
  %_4.i.i.i.i = load i64, ptr %_23.i.i.i.i, align 8, !alias.scope !48, !noundef !3
  %next_carry.i.i.i.i = shl i64 %_4.i.i.i.i, 63
  %_5.i.i.i.i = lshr i64 %_4.i.i.i.i, 1
  %10 = or disjoint i64 %_5.i.i.i.i, %accum.sroa.0.06.i.i.i
  store i64 %10, ptr %_23.i.i.i.i, align 8, !alias.scope !48
  %11 = icmp eq ptr %num.sroa.5.0, %_23.i.i.i.i
  br i1 %11, label %bb2, label %bb3.i.i.i19

bb20.us.i.i.i.i:                                  ; preds = %"_ZN81_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..Index$LT$I$GT$$GT$5index17hd135ae0287503048E.exit", %bb20.us.i.i.i.i
  %accum.sroa.0.114.us.i.i.i.i = phi i64 [ %_0.i.i.us.i.i.i.i, %bb20.us.i.i.i.i ], [ 0, %"_ZN81_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..Index$LT$I$GT$$GT$5index17hd135ae0287503048E.exit" ]
  %iter.sroa.0.013.us.i.i.i.i = phi i64 [ %_27.us.i.i.i.i, %bb20.us.i.i.i.i ], [ 0, %"_ZN81_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..Index$LT$I$GT$$GT$5index17hd135ae0287503048E.exit" ]
  %ptr.i1012.us.i.i.i.i = phi ptr [ %spec.select.i.i.i, %bb20.us.i.i.i.i ], [ %num.sroa.5.0, %"_ZN81_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..Index$LT$I$GT$$GT$5index17hd135ae0287503048E.exit" ]
  %_18.not.i.i.us.i.i.i.i = phi i64 [ 0, %bb20.us.i.i.i.i ], [ 1, %"_ZN81_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..Index$LT$I$GT$$GT$5index17hd135ae0287503048E.exit" ]
  %_27.us.i.i.i.i = add nuw nsw i64 %iter.sroa.0.013.us.i.i.i.i, 1
  %_7.i.us.i.i.i.i = icmp ne ptr %ptr.i1012.us.i.i.i.i, %_6.i.i.i
  %spec.select.i.i.i = getelementptr inbounds nuw i8, ptr %ptr.i1012.us.i.i.i.i, i64 8
  tail call void @llvm.assume(i1 %_7.i.us.i.i.i.i)
  %_7.i.i.us.i.i.i.i = load i64, ptr %ptr.i1012.us.i.i.i.i, align 8, !alias.scope !53, !noalias !60, !noundef !3
  %_6.i.i.us.i.i.i.i = zext i64 %_7.i.i.us.i.i.i.i to i128
  %_8.i.i.us.i.i.i.i = zext nneg i64 %_18.not.i.i.us.i.i.i.i to i128
  %_9.i.i.us.i.i.i.i = zext nneg i64 %accum.sroa.0.114.us.i.i.i.i to i128
  %_5.i.i.us.i.i.i.i = add nuw nsw i128 %_6.i.i.us.i.i.i.i, %_9.i.i.us.i.i.i.i
  %tmp.i.i.us.i.i.i.i = add nuw nsw i128 %_5.i.i.us.i.i.i.i, %_8.i.i.us.i.i.i.i
  %12 = trunc i128 %tmp.i.i.us.i.i.i.i to i64
  store i64 %12, ptr %ptr.i1012.us.i.i.i.i, align 8, !alias.scope !53, !noalias !60
  %_10.i.i.us.i.i.i.i = lshr i128 %tmp.i.i.us.i.i.i.i, 64
  %_0.i.i.us.i.i.i.i = trunc nuw nsw i128 %_10.i.i.us.i.i.i.i to i64
  %exitcond16.not.i.i.i.i = icmp eq i64 %_27.us.i.i.i.i, %num.1
  br i1 %exitcond16.not.i.i.i.i, label %bb18, label %bb20.us.i.i.i.i

bb10:                                             ; preds = %"_ZN81_$LT$alloc..vec..Vec$LT$T$C$A$GT$$u20$as$u20$core..ops..index..Index$LT$I$GT$$GT$5index17hd135ae0287503048E.exit"
  %_31 = zext nneg i8 %8 to i64
  br label %bb20.us.i.i.i.i21

bb20.us.i.i.i.i21:                                ; preds = %bb10, %bb20.us.i.i.i.i21
  %accum.sroa.0.114.us.i.i.i.i22 = phi i64 [ %_0.i.i.us.i.i.i.i36, %bb20.us.i.i.i.i21 ], [ 0, %bb10 ]
  %iter.sroa.0.013.us.i.i.i.i23 = phi i64 [ %_27.us.i.i.i.i25, %bb20.us.i.i.i.i21 ], [ 0, %bb10 ]
  %ptr.i1012.us.i.i.i.i24 = phi ptr [ %spec.select.i.i.i27, %bb20.us.i.i.i.i21 ], [ %num.sroa.5.0, %bb10 ]
  %13 = phi i64 [ %spec.store.select.i.i.us.i.i.i.i30, %bb20.us.i.i.i.i21 ], [ 1, %bb10 ]
  %_27.us.i.i.i.i25 = add nuw nsw i64 %iter.sroa.0.013.us.i.i.i.i23, 1
  %_7.i.us.i.i.i.i26 = icmp ne ptr %ptr.i1012.us.i.i.i.i24, %_6.i.i.i
  %spec.select.i.i.i27 = getelementptr inbounds nuw i8, ptr %ptr.i1012.us.i.i.i.i24, i64 8
  tail call void @llvm.assume(i1 %_7.i.us.i.i.i.i26)
  %.not.i.i7.us.i.i.i.i28 = icmp eq i64 %13, 2
  %_18.not.i.i.us.i.i.i.i29 = icmp eq i64 %13, 1
  %spec.store.select.i.i.us.i.i.i.i30 = select i1 %_18.not.i.i.us.i.i.i.i29, i64 0, i64 2
  %spec.select14.i.us.i.i.i.i31 = select i1 %_18.not.i.i.us.i.i.i.i29, i64 %_31, i64 0
  %14 = select i1 %.not.i.i7.us.i.i.i.i28, i64 0, i64 %spec.select14.i.us.i.i.i.i31
  %_8.i.i.us.i.i.i.i32 = load i64, ptr %ptr.i1012.us.i.i.i.i24, align 8, !alias.scope !67, !noalias !74, !noundef !3
  %_7.i.i.us.i.i.i.i33 = zext i64 %_8.i.i.us.i.i.i.i32 to i128
  %_6.i.i.us.i.i.i.i34 = or disjoint i128 %_7.i.i.us.i.i.i.i33, 18446744073709551616
  %narrow.i = add nuw nsw i64 %14, %accum.sroa.0.114.us.i.i.i.i22
  %15 = zext nneg i64 %narrow.i to i128
  %tmp.i.i.us.i.i.i.i35 = sub nuw nsw i128 %_6.i.i.us.i.i.i.i34, %15
  %16 = trunc i128 %tmp.i.i.us.i.i.i.i35 to i64
  store i64 %16, ptr %ptr.i1012.us.i.i.i.i24, align 8, !alias.scope !67, !noalias !74
  %_11.i.i.us.i.i.i.i = icmp samesign ult i128 %tmp.i.i.us.i.i.i.i35, 18446744073709551616
  %_0.i.i.us.i.i.i.i36 = zext i1 %_11.i.i.us.i.i.i.i to i64
  %exitcond16.not.i.i.i.i37 = icmp eq i64 %_27.us.i.i.i.i25, %num.1
  br i1 %exitcond16.not.i.i.i.i37, label %bb18, label %bb20.us.i.i.i.i21
}

; ark_ff::fields::field_hashers::expander::DST::copy_bytes
; Function Attrs: nounwind
define noundef range(i64 0, 256) i64 @_ZN6ark_ff6fields13field_hashers8expander3DST10copy_bytes17h2aa6e6e874a78b33E(ptr noalias noundef writeonly align 1 captures(none) dereferenceable(255) %new_dst, ptr noalias noundef nonnull readonly align 1 captures(none) %data.0, i64 noundef returned range(i64 0, -9223372036854775808) %data.1) unnamed_addr #2 {
start:
  %_7.i.i.i = icmp samesign ult i64 %data.1, 256
  br i1 %_7.i.i.i, label %"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$15copy_from_slice17h0144fe076e94ca57E.exit", label %bb3.i.i.i, !prof !81

bb3.i.i.i:                                        ; preds = %start
; call core::slice::index::slice_index_fail
  tail call void @_RNvNtNtCsl8K0bEFm1U0_4core5slice5index16slice_index_fail(i64 noundef 0, i64 noundef range(i64 0, -9223372036854775808) %data.1, i64 noundef 255, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_8499ff2c1595e9316e5a0a3b791b0542) #22, !noalias !82
  unreachable

"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$15copy_from_slice17h0144fe076e94ca57E.exit": ; preds = %start
  tail call void @llvm.memcpy.p0.p0.i64(ptr nonnull align 1 %new_dst, ptr nonnull readonly align 1 %data.0, i64 range(i64 0, -9223372036854775808) %data.1, i1 false), !alias.scope !89
  ret i64 %data.1
}

; ark_ff::fields::field_hashers::expander::DST::slice
; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: read)
define { ptr, i64 } @_ZN6ark_ff6fields13field_hashers8expander3DST5slice17hfe198f086ae7fd2eE(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(264) %self) unnamed_addr #3 {
start:
  %_4 = getelementptr inbounds nuw i8, ptr %self, i64 8
  %_6 = load i64, ptr %self, align 8, !noundef !3
  %_7.i.i.i = icmp ugt i64 %_6, 255
  %spec.select.i = select i1 %_7.i.i.i, ptr inttoptr (i64 1 to ptr), ptr %_4
  %spec.select3.i = select i1 %_7.i.i.i, i64 0, i64 %_6
  %0 = insertvalue { ptr, i64 } poison, ptr %spec.select.i, 0
  %1 = insertvalue { ptr, i64 } %0, i64 %spec.select3.i, 1
  ret { ptr, i64 } %1
}

; ark_ff::fields::sqrt::LegendreSymbol::is_qr
; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: read)
define noundef zeroext i1 @_ZN6ark_ff6fields4sqrt14LegendreSymbol5is_qr17h5fe9e0c2d6610697E(ptr noalias noundef readonly align 1 captures(none) dereferenceable(1) %self) unnamed_addr #3 {
start:
  %self.val = load i8, ptr %self, align 1, !range !96, !noundef !3
  %_0.i = icmp eq i8 %self.val, 1
  ret i1 %_0.i
}

; ark_ff::fields::sqrt::LegendreSymbol::is_qnr
; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: read)
define noundef zeroext i1 @_ZN6ark_ff6fields4sqrt14LegendreSymbol6is_qnr17h58a2e000841edb22E(ptr noalias noundef readonly align 1 captures(none) dereferenceable(1) %self) unnamed_addr #3 {
start:
  %self.val = load i8, ptr %self, align 1, !range !96, !noundef !3
  %_0.i = icmp eq i8 %self.val, -1
  ret i1 %_0.i
}

; ark_ff::fields::sqrt::LegendreSymbol::is_zero
; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: read)
define noundef zeroext i1 @_ZN6ark_ff6fields4sqrt14LegendreSymbol7is_zero17h5484778ce4720405E(ptr noalias noundef readonly align 1 captures(none) dereferenceable(1) %self) unnamed_addr #3 {
start:
  %self.val = load i8, ptr %self, align 1, !range !96, !noundef !3
  %_0.i = icmp eq i8 %self.val, 0
  ret i1 %_0.i
}

; ark_ff::fields::utils::k_adicity_big_int
; Function Attrs: nounwind
define noundef i32 @_ZN6ark_ff6fields5utils17k_adicity_big_int17h6a0086abe5b008abE(ptr dead_on_return noalias noundef align 8 captures(address) dereferenceable(24) %k, ptr dead_on_return noalias noundef align 8 captures(address) dereferenceable(24) %n) unnamed_addr #2 personality ptr @rust_eh_personality {
start:
  %_5.i30 = alloca [48 x i8], align 8
  %_3.i31 = alloca [24 x i8], align 8
  %_13.i = alloca [24 x i8], align 8
  %_5.i = alloca [48 x i8], align 8
  %0 = getelementptr inbounds nuw i8, ptr %n, i64 16
  %n.val = load i64, ptr %0, align 8, !noundef !3
  %_3.i = icmp ult i64 %n.val, 1152921504606846976
  tail call void @llvm.assume(i1 %_3.i)
  %_0.i = icmp eq i64 %n.val, 0
  br i1 %_0.i, label %bb2, label %bb4.preheader

bb4.preheader:                                    ; preds = %start
  %1 = getelementptr inbounds nuw i8, ptr %k, i64 16
  %other.val6.i41 = load i64, ptr %1, align 8, !alias.scope !97, !noalias !100, !noundef !3
  %_261.i.i42 = icmp eq i64 %other.val6.i41, 0
  br i1 %_261.i.i42, label %bb1.i.i, label %"_ZN10num_bigint7biguint7convert88_$LT$impl$u20$num_traits..cast..ToPrimitive$u20$for$u20$num_bigint..biguint..BigUint$GT$6to_u6417h042965af5f65a8fbE.exit.i.lr.ph"

"_ZN10num_bigint7biguint7convert88_$LT$impl$u20$num_traits..cast..ToPrimitive$u20$for$u20$num_bigint..biguint..BigUint$GT$6to_u6417h042965af5f65a8fbE.exit.i.lr.ph": ; preds = %bb4.preheader
  %2 = getelementptr inbounds nuw i8, ptr %k, i64 8
  %3 = getelementptr inbounds nuw i8, ptr %_5.i, i64 24
  %_7.sroa.7.0..sroa_idx = getelementptr inbounds nuw i8, ptr %_5.i, i64 32
  %_7.sroa.9.0..sroa_idx = getelementptr inbounds nuw i8, ptr %_5.i, i64 40
  %4 = getelementptr inbounds nuw i8, ptr %_5.i, i64 8
  %5 = getelementptr inbounds nuw i8, ptr %n, i64 8
  %6 = getelementptr inbounds nuw i8, ptr %_13.i, i64 8
  %7 = getelementptr inbounds nuw i8, ptr %_5.i30, i64 24
  %8 = getelementptr inbounds nuw i8, ptr %_5.i30, i64 32
  br label %"_ZN10num_bigint7biguint7convert88_$LT$impl$u20$num_traits..cast..ToPrimitive$u20$for$u20$num_bigint..biguint..BigUint$GT$6to_u6417h042965af5f65a8fbE.exit.i"

bb2:                                              ; preds = %start
  %n.val3 = load i64, ptr %n, align 8, !range !2, !noundef !3
  %9 = icmp eq i64 %n.val3, 0
  br i1 %9, label %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit", label %bb2.i.i.i.i.i

bb2.i.i.i.i.i:                                    ; preds = %bb2
  %10 = getelementptr inbounds nuw i8, ptr %n, i64 8
  %n.val4 = load ptr, ptr %10, align 8, !nonnull !3, !noundef !3
  %alloc_size.i.i.i.i.i.i = shl nuw i64 %n.val3, 3
; call __rustc::__rust_dealloc
  tail call void @_RNvCsfLfy6EI15iL_7___rustc14___rust_dealloc(ptr noundef nonnull %n.val4, i64 noundef %alloc_size.i.i.i.i.i.i, i64 noundef range(i64 1, -9223372036854775807) 8) #20
  br label %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit"

"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit": ; preds = %bb2, %bb2.i.i.i.i.i
  %k.val = load i64, ptr %k, align 8, !range !2, !noundef !3
  %11 = icmp eq i64 %k.val, 0
  br i1 %11, label %bb14, label %bb2.i.i.i.i.i13

bb2.i.i.i.i.i13:                                  ; preds = %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit"
  %12 = getelementptr inbounds nuw i8, ptr %k, i64 8
  %k.val2 = load ptr, ptr %12, align 8, !nonnull !3, !noundef !3
  %alloc_size.i.i.i.i.i.i14 = shl nuw i64 %k.val, 3
; call __rustc::__rust_dealloc
  tail call void @_RNvCsfLfy6EI15iL_7___rustc14___rust_dealloc(ptr noundef nonnull %k.val2, i64 noundef %alloc_size.i.i.i.i.i.i14, i64 noundef range(i64 1, -9223372036854775807) 8) #20
  br label %bb14

"_ZN10num_bigint7biguint7convert88_$LT$impl$u20$num_traits..cast..ToPrimitive$u20$for$u20$num_bigint..biguint..BigUint$GT$6to_u6417h042965af5f65a8fbE.exit.i": ; preds = %"_ZN10num_bigint7biguint7convert88_$LT$impl$u20$num_traits..cast..ToPrimitive$u20$for$u20$num_bigint..biguint..BigUint$GT$6to_u6417h042965af5f65a8fbE.exit.i.lr.ph", %"_ZN10num_bigint7biguint8division126_$LT$impl$u20$core..ops..arith..DivAssign$LT$$RF$num_bigint..biguint..BigUint$GT$$u20$for$u20$num_bigint..biguint..BigUint$GT$10div_assign17hb98d4276a2df0d37E.exit"
  %other.val6.i44 = phi i64 [ %other.val6.i41, %"_ZN10num_bigint7biguint7convert88_$LT$impl$u20$num_traits..cast..ToPrimitive$u20$for$u20$num_bigint..biguint..BigUint$GT$6to_u6417h042965af5f65a8fbE.exit.i.lr.ph" ], [ %other.val6.i, %"_ZN10num_bigint7biguint8division126_$LT$impl$u20$core..ops..arith..DivAssign$LT$$RF$num_bigint..biguint..BigUint$GT$$u20$for$u20$num_bigint..biguint..BigUint$GT$10div_assign17hb98d4276a2df0d37E.exit" ]
  %r.sroa.0.043 = phi i32 [ 0, %"_ZN10num_bigint7biguint7convert88_$LT$impl$u20$num_traits..cast..ToPrimitive$u20$for$u20$num_bigint..biguint..BigUint$GT$6to_u6417h042965af5f65a8fbE.exit.i.lr.ph" ], [ %24, %"_ZN10num_bigint7biguint8division126_$LT$impl$u20$core..ops..arith..DivAssign$LT$$RF$num_bigint..biguint..BigUint$GT$$u20$for$u20$num_bigint..biguint..BigUint$GT$10div_assign17hb98d4276a2df0d37E.exit" ]
  call void @llvm.experimental.noalias.scope.decl(metadata !103)
  call void @llvm.experimental.noalias.scope.decl(metadata !105)
  %other.val.i = load ptr, ptr %2, align 8, !alias.scope !105, !noalias !107, !nonnull !3, !noundef !3
  %_10.i.i = load i64, ptr %other.val.i, align 8, !noalias !108, !noundef !3
  %_26.i.i = icmp eq i64 %other.val6.i44, 1
  %_8.i = icmp ult i64 %_10.i.i, 4294967296
  %or.cond.i = and i1 %_26.i.i, %_8.i
  br i1 %or.cond.i, label %bb7.i, label %bb15.i

bb15.i:                                           ; preds = %"_ZN10num_bigint7biguint7convert88_$LT$impl$u20$num_traits..cast..ToPrimitive$u20$for$u20$num_bigint..biguint..BigUint$GT$6to_u6417h042965af5f65a8fbE.exit.i"
  call void @llvm.lifetime.start.p0(ptr nonnull %_5.i), !noalias !108
; call num_bigint::biguint::division::div_rem_ref
  call void @_ZN10num_bigint7biguint8division11div_rem_ref17h2b53e1b7a07d4de7E(ptr noalias noundef nonnull sret([48 x i8]) align 8 captures(address) dereferenceable(48) %_5.i, ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(24) %n, ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(24) %k) #20, !noalias !109
  %_7.sroa.0.0.copyload = load i64, ptr %3, align 8, !noalias !110
  %_7.sroa.7.0.copyload = load ptr, ptr %_7.sroa.7.0..sroa_idx, align 8, !noalias !110
  %_7.sroa.9.0.copyload = load i64, ptr %_7.sroa.9.0..sroa_idx, align 8, !noalias !110
  %_5.val.i = load i64, ptr %_5.i, align 8, !range !2, !noalias !108, !noundef !3
  %13 = icmp eq i64 %_5.val.i, 0
  br i1 %13, label %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit.i", label %bb2.i.i.i.i.i.i

bb2.i.i.i.i.i.i:                                  ; preds = %bb15.i
  %_5.val5.i = load ptr, ptr %4, align 8, !noalias !108, !nonnull !3, !noundef !3
  %alloc_size.i.i.i.i.i.i.i = shl nuw i64 %_5.val.i, 3
; call __rustc::__rust_dealloc
  call void @_RNvCsfLfy6EI15iL_7___rustc14___rust_dealloc(ptr noundef nonnull %_5.val5.i, i64 noundef %alloc_size.i.i.i.i.i.i.i, i64 noundef range(i64 1, -9223372036854775807) 8) #20, !noalias !109
  br label %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit.i"

"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit.i": ; preds = %bb2.i.i.i.i.i.i, %bb15.i
  call void @llvm.lifetime.end.p0(ptr nonnull %_5.i), !noalias !108
  br label %"_ZN10num_bigint7biguint8division84_$LT$impl$u20$core..ops..arith..Rem$u20$for$u20$$RF$num_bigint..biguint..BigUint$GT$3rem17h5a401e798c8e41cbE.exit"

bb7.i:                                            ; preds = %"_ZN10num_bigint7biguint7convert88_$LT$impl$u20$num_traits..cast..ToPrimitive$u20$for$u20$num_bigint..biguint..BigUint$GT$6to_u6417h042965af5f65a8fbE.exit.i"
  %self.val.i = load ptr, ptr %5, align 8, !alias.scope !103, !noalias !111
  %self.val7.i = load i64, ptr %0, align 8, !alias.scope !103, !noalias !111
  %14 = icmp eq i64 %_10.i.i, 0
  br i1 %14, label %bb1.i.i, label %bb3.i.i, !prof !112

bb1.i.i:                                          ; preds = %"_ZN10num_bigint7biguint8division126_$LT$impl$u20$core..ops..arith..DivAssign$LT$$RF$num_bigint..biguint..BigUint$GT$$u20$for$u20$num_bigint..biguint..BigUint$GT$10div_assign17hb98d4276a2df0d37E.exit", %bb7.i, %bb4.preheader
; call core::panicking::panic_fmt
  call void @_RNvNtCsl8K0bEFm1U0_4core9panicking9panic_fmt(ptr noundef nonnull @alloc_5bd1ef6667dbdbecff436d9509a4d052, ptr noundef nonnull inttoptr (i64 51 to ptr), ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_e3d07c9a456e140e9ef6adfe3c5410bd) #22, !noalias !108
  unreachable

bb3.i.i:                                          ; preds = %bb7.i
  %15 = icmp ne ptr %self.val.i, null
  call void @llvm.assume(i1 %15)
  %_391.i.i = icmp eq i64 %self.val7.i, 0
  br i1 %_391.i.i, label %_ZN10num_bigint7biguint8division9rem_digit17h0edb96927141e2d3E.exit.thread.i, label %bb9.preheader.i.i

_ZN10num_bigint7biguint8division9rem_digit17h0edb96927141e2d3E.exit.thread.i: ; preds = %bb3.i.i
  call void @llvm.lifetime.start.p0(ptr nonnull %_13.i), !noalias !108
  br label %bb12.i

bb9.preheader.i.i:                                ; preds = %bb3.i.i
  %_34.idx.i.i = shl nuw nsw i64 %self.val7.i, 3
  %_34.i.i = getelementptr inbounds nuw i8, ptr %self.val.i, i64 %_34.idx.i.i
  br label %bb9.i.i

bb9.i.i:                                          ; preds = %bb9.i.i, %bb9.preheader.i.i
  %rem.sroa.0.23.i.i = phi i64 [ %16, %bb9.i.i ], [ 0, %bb9.preheader.i.i ]
  %iter.sroa.4.02.i.i = phi ptr [ %_50.i.i, %bb9.i.i ], [ %_34.i.i, %bb9.preheader.i.i ]
  %_50.i.i = getelementptr inbounds i8, ptr %iter.sroa.4.02.i.i, i64 -8
  %digit2.i.i = load i64, ptr %_50.i.i, align 8, !noalias !108, !noundef !3
  %_53.i.i = call i64 @llvm.fshl.i64(i64 %rem.sroa.0.23.i.i, i64 %digit2.i.i, i64 32)
  %_59.i.i = urem i64 %_53.i.i, %_10.i.i
  %_57.i.i = shl nuw i64 %_59.i.i, 32
  %_58.i.i = and i64 %digit2.i.i, 4294967295
  %_56.i.i = or disjoint i64 %_57.i.i, %_58.i.i
  %16 = urem i64 %_56.i.i, %_10.i.i
  %_39.i.i = icmp eq ptr %self.val.i, %_50.i.i
  br i1 %_39.i.i, label %_ZN10num_bigint7biguint8division9rem_digit17h0edb96927141e2d3E.exit.i, label %bb9.i.i

_ZN10num_bigint7biguint8division9rem_digit17h0edb96927141e2d3E.exit.i: ; preds = %bb9.i.i
  call void @llvm.lifetime.start.p0(ptr nonnull %_13.i), !noalias !108
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %_13.i, ptr noundef nonnull align 8 dereferenceable(24) @anon.6a88fb9413c64201b246cbfc94acc414.0, i64 24, i1 false), !noalias !108
  %17 = icmp eq i64 %16, 0
  br i1 %17, label %bb12.i, label %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h56fe8203bedfe7efE.exit.us.i"

"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h56fe8203bedfe7efE.exit.us.i": ; preds = %_ZN10num_bigint7biguint8division9rem_digit17h0edb96927141e2d3E.exit.i
; call alloc::raw_vec::RawVec<T,A>::grow_one
  call void @"_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17hc642f46280975b0eE"(ptr noalias noundef nonnull align 8 dereferenceable(24) %_13.i) #23, !noalias !108
  %_14.i.us.pre.i = load ptr, ptr %6, align 8, !alias.scope !113, !noalias !108
  store i64 %16, ptr %_14.i.us.pre.i, align 8, !noalias !108
  %_7.sroa.0.0.copyload36.pre = load i64, ptr %_13.i, align 8, !noalias !110
  %_7.sroa.7.0.copyload37.pre = load ptr, ptr %6, align 8, !noalias !110
  br label %bb12.i

bb12.i:                                           ; preds = %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h56fe8203bedfe7efE.exit.us.i", %_ZN10num_bigint7biguint8division9rem_digit17h0edb96927141e2d3E.exit.i, %_ZN10num_bigint7biguint8division9rem_digit17h0edb96927141e2d3E.exit.thread.i
  %_7.sroa.9.0.copyload38 = phi i64 [ 1, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h56fe8203bedfe7efE.exit.us.i" ], [ 0, %_ZN10num_bigint7biguint8division9rem_digit17h0edb96927141e2d3E.exit.i ], [ 0, %_ZN10num_bigint7biguint8division9rem_digit17h0edb96927141e2d3E.exit.thread.i ]
  %_7.sroa.7.0.copyload37 = phi ptr [ %_7.sroa.7.0.copyload37.pre, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h56fe8203bedfe7efE.exit.us.i" ], [ inttoptr (i64 8 to ptr), %_ZN10num_bigint7biguint8division9rem_digit17h0edb96927141e2d3E.exit.i ], [ inttoptr (i64 8 to ptr), %_ZN10num_bigint7biguint8division9rem_digit17h0edb96927141e2d3E.exit.thread.i ]
  %_7.sroa.0.0.copyload36 = phi i64 [ %_7.sroa.0.0.copyload36.pre, %"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h56fe8203bedfe7efE.exit.us.i" ], [ 0, %_ZN10num_bigint7biguint8division9rem_digit17h0edb96927141e2d3E.exit.i ], [ 0, %_ZN10num_bigint7biguint8division9rem_digit17h0edb96927141e2d3E.exit.thread.i ]
  call void @llvm.lifetime.end.p0(ptr nonnull %_13.i), !noalias !108
  br label %"_ZN10num_bigint7biguint8division84_$LT$impl$u20$core..ops..arith..Rem$u20$for$u20$$RF$num_bigint..biguint..BigUint$GT$3rem17h5a401e798c8e41cbE.exit"

"_ZN10num_bigint7biguint8division84_$LT$impl$u20$core..ops..arith..Rem$u20$for$u20$$RF$num_bigint..biguint..BigUint$GT$3rem17h5a401e798c8e41cbE.exit": ; preds = %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit.i", %bb12.i
  %_7.sroa.9.0 = phi i64 [ %_7.sroa.9.0.copyload38, %bb12.i ], [ %_7.sroa.9.0.copyload, %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit.i" ]
  %_7.sroa.7.0 = phi ptr [ %_7.sroa.7.0.copyload37, %bb12.i ], [ %_7.sroa.7.0.copyload, %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit.i" ]
  %_7.sroa.0.0 = phi i64 [ %_7.sroa.0.0.copyload36, %bb12.i ], [ %_7.sroa.0.0.copyload, %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit.i" ]
  %_3.i16 = icmp ult i64 %_7.sroa.9.0, 1152921504606846976
  call void @llvm.assume(i1 %_3.i16)
  %_0.i17 = icmp eq i64 %_7.sroa.9.0, 0
  br i1 %_0.i17, label %bb7, label %bb10

bb10:                                             ; preds = %"_ZN10num_bigint7biguint8division84_$LT$impl$u20$core..ops..arith..Rem$u20$for$u20$$RF$num_bigint..biguint..BigUint$GT$3rem17h5a401e798c8e41cbE.exit"
  %18 = icmp eq i64 %_7.sroa.0.0, 0
  br i1 %18, label %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit20", label %bb2.i.i.i.i.i18

bb2.i.i.i.i.i18:                                  ; preds = %bb10
  %alloc_size.i.i.i.i.i.i19 = shl nuw i64 %_7.sroa.0.0, 3
  %19 = icmp ne ptr %_7.sroa.7.0, null
  call void @llvm.assume(i1 %19)
; call __rustc::__rust_dealloc
  call void @_RNvCsfLfy6EI15iL_7___rustc14___rust_dealloc(ptr noundef nonnull %_7.sroa.7.0, i64 noundef %alloc_size.i.i.i.i.i.i19, i64 noundef range(i64 1, -9223372036854775807) 8) #20
  br label %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit20"

"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit20": ; preds = %bb10, %bb2.i.i.i.i.i18
  %n.val9 = load i64, ptr %n, align 8, !range !2, !noundef !3
  %20 = icmp eq i64 %n.val9, 0
  br i1 %20, label %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit23", label %bb2.i.i.i.i.i21

bb2.i.i.i.i.i21:                                  ; preds = %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit20"
  %n.val10 = load ptr, ptr %5, align 8, !nonnull !3, !noundef !3
  %alloc_size.i.i.i.i.i.i22 = shl nuw i64 %n.val9, 3
; call __rustc::__rust_dealloc
  call void @_RNvCsfLfy6EI15iL_7___rustc14___rust_dealloc(ptr noundef nonnull %n.val10, i64 noundef %alloc_size.i.i.i.i.i.i22, i64 noundef range(i64 1, -9223372036854775807) 8) #20
  br label %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit23"

"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit23": ; preds = %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit20", %bb2.i.i.i.i.i21
  %k.val7 = load i64, ptr %k, align 8, !range !2, !noundef !3
  %21 = icmp eq i64 %k.val7, 0
  br i1 %21, label %bb14, label %bb2.i.i.i.i.i24

bb2.i.i.i.i.i24:                                  ; preds = %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit23"
  %k.val8 = load ptr, ptr %2, align 8, !nonnull !3, !noundef !3
  %alloc_size.i.i.i.i.i.i25 = shl nuw i64 %k.val7, 3
; call __rustc::__rust_dealloc
  call void @_RNvCsfLfy6EI15iL_7___rustc14___rust_dealloc(ptr noundef nonnull %k.val8, i64 noundef %alloc_size.i.i.i.i.i.i25, i64 noundef range(i64 1, -9223372036854775807) 8) #20
  br label %bb14

bb7:                                              ; preds = %"_ZN10num_bigint7biguint8division84_$LT$impl$u20$core..ops..arith..Rem$u20$for$u20$$RF$num_bigint..biguint..BigUint$GT$3rem17h5a401e798c8e41cbE.exit"
  %22 = icmp eq i64 %_7.sroa.0.0, 0
  br i1 %22, label %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit29", label %bb2.i.i.i.i.i27

bb2.i.i.i.i.i27:                                  ; preds = %bb7
  %alloc_size.i.i.i.i.i.i28 = shl nuw i64 %_7.sroa.0.0, 3
  %23 = icmp ne ptr %_7.sroa.7.0, null
  call void @llvm.assume(i1 %23)
; call __rustc::__rust_dealloc
  call void @_RNvCsfLfy6EI15iL_7___rustc14___rust_dealloc(ptr noundef nonnull %_7.sroa.7.0, i64 noundef %alloc_size.i.i.i.i.i.i28, i64 noundef range(i64 1, -9223372036854775807) 8) #20
  br label %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit29"

"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit29": ; preds = %bb7, %bb2.i.i.i.i.i27
  %24 = add i32 %r.sroa.0.043, 1
  call void @llvm.experimental.noalias.scope.decl(metadata !116)
  call void @llvm.lifetime.start.p0(ptr nonnull %_3.i31)
  call void @llvm.lifetime.start.p0(ptr nonnull %_5.i30), !noalias !119
; call num_bigint::biguint::division::div_rem_ref
  call void @_ZN10num_bigint7biguint8division11div_rem_ref17h2b53e1b7a07d4de7E(ptr noalias noundef nonnull sret([48 x i8]) align 8 captures(address) dereferenceable(48) %_5.i30, ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(24) %n, ptr noalias noundef nonnull readonly align 8 captures(address, read_provenance) dereferenceable(24) %k) #20
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %_3.i31, ptr noundef nonnull align 8 dereferenceable(24) %_5.i30, i64 24, i1 false), !noalias !119
  %.val.i = load i64, ptr %7, align 8, !range !2, !noalias !119, !noundef !3
  %25 = icmp eq i64 %.val.i, 0
  br i1 %25, label %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit.i34", label %bb2.i.i.i.i.i.i32

bb2.i.i.i.i.i.i32:                                ; preds = %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit29"
  %.val2.i = load ptr, ptr %8, align 8, !noalias !119, !nonnull !3, !noundef !3
  %alloc_size.i.i.i.i.i.i.i33 = shl nuw i64 %.val.i, 3
; call __rustc::__rust_dealloc
  call void @_RNvCsfLfy6EI15iL_7___rustc14___rust_dealloc(ptr noundef nonnull %.val2.i, i64 noundef %alloc_size.i.i.i.i.i.i.i33, i64 noundef range(i64 1, -9223372036854775807) 8) #20
  br label %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit.i34"

"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit.i34": ; preds = %bb2.i.i.i.i.i.i32, %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit29"
  call void @llvm.lifetime.end.p0(ptr nonnull %_5.i30), !noalias !119
  %self.val.i35 = load i64, ptr %n, align 8, !range !2, !alias.scope !116, !noalias !121, !noundef !3
  %26 = icmp eq i64 %self.val.i35, 0
  br i1 %26, label %"_ZN10num_bigint7biguint8division126_$LT$impl$u20$core..ops..arith..DivAssign$LT$$RF$num_bigint..biguint..BigUint$GT$$u20$for$u20$num_bigint..biguint..BigUint$GT$10div_assign17hb98d4276a2df0d37E.exit", label %bb2.i.i.i.i.i3.i

bb2.i.i.i.i.i3.i:                                 ; preds = %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit.i34"
  %self.val1.i = load ptr, ptr %5, align 8, !alias.scope !116, !noalias !121, !nonnull !3, !noundef !3
  %alloc_size.i.i.i.i.i.i4.i = shl nuw i64 %self.val.i35, 3
; call __rustc::__rust_dealloc
  call void @_RNvCsfLfy6EI15iL_7___rustc14___rust_dealloc(ptr noundef nonnull %self.val1.i, i64 noundef %alloc_size.i.i.i.i.i.i4.i, i64 noundef range(i64 1, -9223372036854775807) 8) #20
  br label %"_ZN10num_bigint7biguint8division126_$LT$impl$u20$core..ops..arith..DivAssign$LT$$RF$num_bigint..biguint..BigUint$GT$$u20$for$u20$num_bigint..biguint..BigUint$GT$10div_assign17hb98d4276a2df0d37E.exit"

"_ZN10num_bigint7biguint8division126_$LT$impl$u20$core..ops..arith..DivAssign$LT$$RF$num_bigint..biguint..BigUint$GT$$u20$for$u20$num_bigint..biguint..BigUint$GT$10div_assign17hb98d4276a2df0d37E.exit": ; preds = %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit.i34", %bb2.i.i.i.i.i3.i
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(24) %n, ptr noundef nonnull align 8 dereferenceable(24) %_3.i31, i64 24, i1 false), !noalias !121
  call void @llvm.lifetime.end.p0(ptr nonnull %_3.i31)
  %other.val6.i = load i64, ptr %1, align 8, !alias.scope !122, !noalias !124, !noundef !3
  %_261.i.i = icmp eq i64 %other.val6.i, 0
  br i1 %_261.i.i, label %bb1.i.i, label %"_ZN10num_bigint7biguint7convert88_$LT$impl$u20$num_traits..cast..ToPrimitive$u20$for$u20$num_bigint..biguint..BigUint$GT$6to_u6417h042965af5f65a8fbE.exit.i"

bb14:                                             ; preds = %bb2.i.i.i.i.i24, %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit23", %bb2.i.i.i.i.i13, %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit"
  %r.sroa.0.1 = phi i32 [ 0, %bb2.i.i.i.i.i13 ], [ 0, %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit" ], [ %r.sroa.0.043, %"_ZN4core3ptr49drop_in_place$LT$num_bigint..biguint..BigUint$GT$17hbddbc353ea535dc3E.exit23" ], [ %r.sroa.0.043, %bb2.i.i.i.i.i24 ]
  ret i32 %r.sroa.0.1
}

; ark_ff::fields::utils::k_adicity
; Function Attrs: nounwind
define noundef i32 @_ZN6ark_ff6fields5utils9k_adicity17h328c89b837868a54E(i64 noundef %k, i64 noundef %0) unnamed_addr #2 {
start:
  %1 = icmp eq i64 %0, 0
  br i1 %1, label %bb7, label %bb3.preheader

bb3.preheader:                                    ; preds = %start
  %_6 = icmp eq i64 %k, 0
  br i1 %_6, label %panic, label %bb4.lr.ph.split

bb4.lr.ph.split:                                  ; preds = %bb3.preheader
  %_47 = urem i64 %0, %k
  %2 = icmp eq i64 %_47, 0
  br i1 %2, label %bb5, label %bb7

bb7:                                              ; preds = %bb5, %bb4.lr.ph.split, %start
  %r.sroa.0.0 = phi i32 [ 0, %start ], [ 0, %bb4.lr.ph.split ], [ %3, %bb5 ]
  ret i32 %r.sroa.0.0

panic:                                            ; preds = %bb3.preheader
; call core::panicking::panic_const::panic_const_rem_by_zero
  tail call void @_RNvNtNtCsl8K0bEFm1U0_4core9panicking11panic_const23panic_const_rem_by_zero(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24) @alloc_4ae90411e11a4480270944339e0507fa) #22
  unreachable

bb5:                                              ; preds = %bb4.lr.ph.split, %bb5
  %r.sroa.0.159 = phi i32 [ %3, %bb5 ], [ 0, %bb4.lr.ph.split ]
  %n.sroa.0.068 = phi i64 [ %4, %bb5 ], [ %0, %bb4.lr.ph.split ]
  %3 = add i32 %r.sroa.0.159, 1
  %4 = udiv i64 %n.sroa.0.068, %k
  %_4 = urem i64 %4, %k
  %5 = icmp eq i64 %_4, 0
  br i1 %5, label %bb5, label %bb7
}

; ark_ff::fields::models::fp12_2over3over2::characteristic_square_mod_6_is_one
; Function Attrs: nofree norecurse nosync nounwind memory(argmem: read)
define noundef zeroext i1 @_ZN6ark_ff6fields6models16fp12_2over3over234characteristic_square_mod_6_is_one17hdb2819c10acc2405E(ptr noalias noundef nonnull readonly align 8 captures(none) %characteristic.0, i64 noundef range(i64 0, 1152921504606846976) %characteristic.1) unnamed_addr #4 {
start:
  %_48.not = icmp eq i64 %characteristic.1, 0
  br i1 %_48.not, label %bb8, label %bb7.peel

bb7.peel:                                         ; preds = %start
  %_9.peel = load i64, ptr %characteristic.0, align 8, !noundef !3
  %_7.sroa.0.0.peel = urem i64 %_9.peel, 6
  %exitcond.peel.not = icmp eq i64 %characteristic.1, 1
  br i1 %exitcond.peel.not, label %bb8.loopexit, label %bb7

bb8.loopexit:                                     ; preds = %bb7, %bb7.peel
  %.lcssa = phi i64 [ %_7.sroa.0.0.peel, %bb7.peel ], [ %4, %bb7 ]
  %0 = mul i64 %.lcssa, %.lcssa
  %1 = urem i64 %0, 6
  %2 = icmp eq i64 %1, 1
  br label %bb8

bb8:                                              ; preds = %bb8.loopexit, %start
  %char_mod_6.sroa.0.0.lcssa = phi i1 [ false, %start ], [ %2, %bb8.loopexit ]
  ret i1 %char_mod_6.sroa.0.0.lcssa

bb7:                                              ; preds = %bb7.peel, %bb7
  %char_mod_6.sroa.0.010 = phi i64 [ %4, %bb7 ], [ %_7.sroa.0.0.peel, %bb7.peel ]
  %i.sroa.0.09 = phi i64 [ %5, %bb7 ], [ 1, %bb7.peel ]
  %3 = getelementptr inbounds nuw i64, ptr %characteristic.0, i64 %i.sroa.0.09
  %_14 = load i64, ptr %3, align 8, !noundef !3
  %_13 = urem i64 %_14, 6
  %_13.tr = trunc nuw nsw i64 %_13 to i8
  %_7.sroa.0.0.lhs.trunc = shl nuw nsw i8 %_13.tr, 2
  %_7.sroa.0.012 = urem i8 %_7.sroa.0.0.lhs.trunc, 6
  %_7.sroa.0.0.zext = zext nneg i8 %_7.sroa.0.012 to i64
  %4 = add i64 %char_mod_6.sroa.0.010, %_7.sroa.0.0.zext
  %5 = add nuw nsw i64 %i.sroa.0.09, 1
  %exitcond.not = icmp eq i64 %5, %characteristic.1
  br i1 %exitcond.not, label %bb8.loopexit, label %bb7, !llvm.loop !126
}

; ark_ff::fields::models::small_fp::small_fp_backend::const_to_bigint
; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @_ZN6ark_ff6fields6models8small_fp16small_fp_backend15const_to_bigint17hb024cf6604231c29E(i128 noundef %value) unnamed_addr #5 {
start:
  %_3 = trunc i128 %value to i64
  ret i64 %_3
}

; ark_ff::fields::models::small_fp::small_fp_backend::const_num_bits_u128
; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef range(i32 0, 129) i32 @_ZN6ark_ff6fields6models8small_fp16small_fp_backend19const_num_bits_u12817h8c1792a24c968431E(i128 noundef %value) unnamed_addr #5 {
start:
  %0 = icmp eq i128 %value, 0
  %1 = tail call range(i128 0, 129) i128 @llvm.ctlz.i128(i128 range(i128 1, 0) %value, i1 true)
  %2 = trunc nuw nsw i128 %1 to i32
  %3 = sub nuw nsw i32 128, %2
  %_0.sroa.0.0 = select i1 %0, i32 0, i32 %3
  ret i32 %_0.sroa.0.0
}

; ark_ff::fields::models::small_fp::small_fp_backend::primitive_type_bit_size
; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef range(i64 8, 65) i64 @_ZN6ark_ff6fields6models8small_fp16small_fp_backend23primitive_type_bit_size17h859fb51e2bddbe22E(i128 noundef %modulus_u128) unnamed_addr #5 {
start:
  %_3 = icmp ult i128 %modulus_u128, 256
  br i1 %_3, label %bb7, label %bb2

bb2:                                              ; preds = %start
  %_5 = icmp ult i128 %modulus_u128, 65536
  br i1 %_5, label %bb7, label %bb4

bb4:                                              ; preds = %bb2
  %_7 = icmp ult i128 %modulus_u128, 4294967296
  %. = select i1 %_7, i64 32, i64 64
  br label %bb7

bb7:                                              ; preds = %bb2, %bb4, %start
  %_0.sroa.0.0 = phi i64 [ 16, %bb2 ], [ %., %bb4 ], [ 8, %start ]
  ret i64 %_0.sroa.0.0
}

; <ark_ff::fields::sqrt::LegendreSymbol as core::cmp::Eq>::assert_fields_are_eq
; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define void @"_ZN70_$LT$ark_ff..fields..sqrt..LegendreSymbol$u20$as$u20$core..cmp..Eq$GT$20assert_fields_are_eq17h2dcee772bc23442aE"(ptr noalias noundef readonly align 1 captures(none) dereferenceable(1) %self) unnamed_addr #5 {
start:
  ret void
}

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(inaccessiblemem: write)
declare void @llvm.assume(i1 noundef) #6

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(ptr captures(none)) #7

; Function Attrs: mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(ptr captures(none)) #7

; Function Attrs: mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias writeonly captures(none), ptr noalias readonly captures(none), i64, i1 immarg) #8

; __rustc::__rust_dealloc
; Function Attrs: nounwind allockind("free")
declare void @_RNvCsfLfy6EI15iL_7___rustc14___rust_dealloc(ptr allocptr noundef captures(address), i64 noundef, i64 noundef range(i64 1, -9223372036854775807)) unnamed_addr #9

; __rustc::__rust_realloc
; Function Attrs: nounwind allockind("realloc,aligned") allocsize(3)
declare noalias noundef ptr @_RNvCsfLfy6EI15iL_7___rustc14___rust_realloc(ptr allocptr noundef, i64 noundef, i64 allocalign noundef range(i64 1, -9223372036854775807), i64 noundef) unnamed_addr #10

; __rustc::__rust_no_alloc_shim_is_unstable_v2
; Function Attrs: nounwind
declare void @_RNvCsfLfy6EI15iL_7___rustc35___rust_no_alloc_shim_is_unstable_v2() unnamed_addr #2

; __rustc::__rust_alloc
; Function Attrs: nounwind allockind("alloc,uninitialized,aligned") allocsize(0)
declare noalias noundef ptr @_RNvCsfLfy6EI15iL_7___rustc12___rust_alloc(i64 noundef, i64 allocalign noundef range(i64 1, -9223372036854775807)) unnamed_addr #11

; Function Attrs: mustprogress nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i128 @llvm.ctlz.i128(i128, i1 immarg) #12

; core::slice::index::slice_index_fail
; Function Attrs: cold noinline noreturn nounwind
declare void @_RNvNtNtCsl8K0bEFm1U0_4core5slice5index16slice_index_fail(i64 noundef, i64 noundef, i64 noundef, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24)) unnamed_addr #13

; num_bigint::biguint::division::div_rem_ref
; Function Attrs: nounwind
declare void @_ZN10num_bigint7biguint8division11div_rem_ref17h2b53e1b7a07d4de7E(ptr dead_on_unwind noalias noundef writable sret([48 x i8]) align 8 captures(address) dereferenceable(48), ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24), ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24)) unnamed_addr #2

; core::panicking::panic_fmt
; Function Attrs: cold noinline noreturn nounwind
declare void @_RNvNtCsl8K0bEFm1U0_4core9panicking9panic_fmt(ptr noundef nonnull, ptr noundef nonnull, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24)) unnamed_addr #13

declare i32 @rust_eh_personality(...) unnamed_addr #14

; alloc::raw_vec::RawVec<T,A>::grow_one
; Function Attrs: noinline nounwind
declare void @"_ZN5alloc7raw_vec19RawVec$LT$T$C$A$GT$8grow_one17hc642f46280975b0eE"(ptr noalias noundef align 8 dereferenceable(16)) unnamed_addr #15

; alloc::raw_vec::handle_error
; Function Attrs: cold minsize noreturn nounwind optsize
declare void @_RNvNtCs1OjIl8oxbrv_5alloc7raw_vec12handle_error(i64 noundef range(i64 0, -9223372036854775807), i64) unnamed_addr #16

; core::panicking::panic_bounds_check
; Function Attrs: cold minsize noinline noreturn nounwind optsize
declare void @_RNvNtCsl8K0bEFm1U0_4core9panicking18panic_bounds_check(i64 noundef, i64 noundef, ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24)) unnamed_addr #17

; core::panicking::panic_const::panic_const_rem_by_zero
; Function Attrs: cold noinline noreturn nounwind
declare void @_RNvNtNtCsl8K0bEFm1U0_4core9panicking11panic_const23panic_const_rem_by_zero(ptr noalias noundef readonly align 8 captures(address, read_provenance) dereferenceable(24)) unnamed_addr #13

; Function Attrs: nocallback  nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.fshl.i64(i64, i64, i64) #18

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(inaccessiblemem: readwrite)
declare void @llvm.experimental.noalias.scope.decl(metadata) #19

; Function Attrs: nocallback  nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.umax.i64(i64, i64) #18

attributes #0 = { cold noinline nounwind "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #1 = { cold nounwind "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #2 = { nounwind "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #3 = { mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: read) "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #4 = { nofree norecurse nosync nounwind memory(argmem: read) "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #5 = { mustprogress nofree norecurse nosync nounwind willreturn memory(none) "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #6 = { mustprogress nocallback nofree nosync nounwind willreturn memory(inaccessiblemem: write) }
attributes #7 = { mustprogress nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #8 = { mustprogress nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #9 = { nounwind allockind("free") "alloc-family"="__rust_alloc" "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #10 = { nounwind allockind("realloc,aligned") allocsize(3) "alloc-family"="__rust_alloc" "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #11 = { nounwind allockind("alloc,uninitialized,aligned") allocsize(0) "alloc-family"="__rust_alloc" "alloc-variant-zeroed"="_RNvCsfLfy6EI15iL_7___rustc19___rust_alloc_zeroed" "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #12 = { mustprogress nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #13 = { cold noinline noreturn nounwind "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #14 = { "target-cpu"="apple-m1" }
attributes #15 = { noinline nounwind "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #16 = { cold minsize noreturn nounwind optsize "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #17 = { cold minsize noinline noreturn nounwind optsize "frame-pointer"="non-leaf" "probe-stack"="inline-asm" "target-cpu"="apple-m1" }
attributes #18 = { nocallback  nofree nosync nounwind speculatable willreturn memory(none) }
attributes #19 = { nocallback nofree nosync nounwind willreturn memory(inaccessiblemem: readwrite) }
attributes #20 = { nounwind }
attributes #21 = { noreturn nounwind }
attributes #22 = { noinline noreturn nounwind }
attributes #23 = { noinline nounwind }

!llvm.module.flags = !{!0}
!llvm.ident = !{!1}

!0 = !{i32 8, !"PIC Level", i32 2}
!1 = !{!"rustc version 1.95.0 (59807616e 2026-04-14)"}
!2 = !{i64 0, i64 -9223372036854775808}
!3 = !{}
!4 = !{!5}
!5 = distinct !{!5, !6, !"_ZN5alloc7raw_vec20RawVecInner$LT$A$GT$14grow_amortized17h255d626ea21a1ddaE: %self"}
!6 = distinct !{!6, !"_ZN5alloc7raw_vec20RawVecInner$LT$A$GT$14grow_amortized17h255d626ea21a1ddaE"}
!7 = !{i64 0, i64 2}
!8 = !{i64 0, i64 -9223372036854775807}
!9 = !{!10}
!10 = distinct !{!10, !11, !"_ZN75_$LT$usize$u20$as$u20$core..slice..index..SliceIndex$LT$$u5b$T$u5d$$GT$$GT$5index17h32a349e275638b2aE: %slice.0"}
!11 = distinct !{!11, !"_ZN75_$LT$usize$u20$as$u20$core..slice..index..SliceIndex$LT$$u5b$T$u5d$$GT$$GT$5index17h32a349e275638b2aE"}
!12 = !{!13}
!13 = distinct !{!13, !14, !"_ZN75_$LT$usize$u20$as$u20$core..slice..index..SliceIndex$LT$$u5b$T$u5d$$GT$$GT$5index17h32a349e275638b2aE: %slice.0"}
!14 = distinct !{!14, !"_ZN75_$LT$usize$u20$as$u20$core..slice..index..SliceIndex$LT$$u5b$T$u5d$$GT$$GT$5index17h32a349e275638b2aE"}
!15 = !{!16}
!16 = distinct !{!16, !17, !"_ZN5alloc3vec16Vec$LT$T$C$A$GT$6resize17h2b2fd27330828120E: %self"}
!17 = distinct !{!17, !"_ZN5alloc3vec16Vec$LT$T$C$A$GT$6resize17h2b2fd27330828120E"}
!18 = !{!19, !21, !23, !24, !26}
!19 = distinct !{!19, !20, !"_ZN5alloc7raw_vec20RawVecInner$LT$A$GT$15try_allocate_in17h32824433495cd182E: %_0"}
!20 = distinct !{!20, !"_ZN5alloc7raw_vec20RawVecInner$LT$A$GT$15try_allocate_in17h32824433495cd182E"}
!21 = distinct !{!21, !22, !"_ZN87_$LT$T$u20$as$u20$alloc..slice..$LT$impl$u20$$u5b$T$u5d$$GT$..to_vec_in..ConvertVec$GT$6to_vec17h91ac162eaa8a66e4E: %v"}
!22 = distinct !{!22, !"_ZN87_$LT$T$u20$as$u20$alloc..slice..$LT$impl$u20$$u5b$T$u5d$$GT$..to_vec_in..ConvertVec$GT$6to_vec17h91ac162eaa8a66e4E"}
!23 = distinct !{!23, !22, !"_ZN87_$LT$T$u20$as$u20$alloc..slice..$LT$impl$u20$$u5b$T$u5d$$GT$..to_vec_in..ConvertVec$GT$6to_vec17h91ac162eaa8a66e4E: %s.0"}
!24 = distinct !{!24, !25, !"_ZN5alloc5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$6to_vec17h3b347af2562b6b4fE: %_0"}
!25 = distinct !{!25, !"_ZN5alloc5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$6to_vec17h3b347af2562b6b4fE"}
!26 = distinct !{!26, !25, !"_ZN5alloc5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$6to_vec17h3b347af2562b6b4fE: %self.0"}
!27 = !{!21, !23, !24, !26}
!28 = !{!21, !24}
!29 = !{!30}
!30 = distinct !{!30, !31, !"_ZN5alloc3vec12Vec$LT$T$GT$3new17h641e75d08de5eab5E: %_0"}
!31 = distinct !{!31, !"_ZN5alloc3vec12Vec$LT$T$GT$3new17h641e75d08de5eab5E"}
!32 = !{!33}
!33 = distinct !{!33, !34, !"_ZN6ark_ff10biginteger10arithmetic8find_naf28_$u7b$$u7b$closure$u7d$$u7d$17hdd184fdcb73408baE: %num.0"}
!34 = distinct !{!34, !"_ZN6ark_ff10biginteger10arithmetic8find_naf28_$u7b$$u7b$closure$u7d$$u7d$17hdd184fdcb73408baE"}
!35 = !{!36}
!36 = distinct !{!36, !37, !"_ZN91_$LT$core..slice..iter..Iter$LT$T$GT$$u20$as$u20$core..iter..traits..iterator..Iterator$GT$3any17h18e391a5ada70125E: %self"}
!37 = distinct !{!37, !"_ZN91_$LT$core..slice..iter..Iter$LT$T$GT$$u20$as$u20$core..iter..traits..iterator..Iterator$GT$3any17h18e391a5ada70125E"}
!38 = !{!39}
!39 = distinct !{!39, !40, !"_ZN6ark_ff10biginteger10arithmetic8find_naf28_$u7b$$u7b$closure$u7d$$u7d$17h31463ed4086046c2E: %num.0"}
!40 = distinct !{!40, !"_ZN6ark_ff10biginteger10arithmetic8find_naf28_$u7b$$u7b$closure$u7d$$u7d$17h31463ed4086046c2E"}
!41 = !{!42}
!42 = distinct !{!42, !43, !"_ZN5alloc3vec16Vec$LT$T$C$A$GT$4push17h3bea4fe874a1efadE: %self"}
!43 = distinct !{!43, !"_ZN5alloc3vec16Vec$LT$T$C$A$GT$4push17h3bea4fe874a1efadE"}
!44 = !{!45}
!45 = distinct !{!45, !46, !"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h1d27c71b99021a71E: %self"}
!46 = distinct !{!46, !"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h1d27c71b99021a71E"}
!47 = !{!45, !42}
!48 = !{!49, !51}
!49 = distinct !{!49, !50, !"_ZN6ark_ff10biginteger10arithmetic8find_naf28_$u7b$$u7b$closure$u7d$$u7d$28_$u7b$$u7b$closure$u7d$$u7d$17h30e37e3b0a46303fE: %x"}
!50 = distinct !{!50, !"_ZN6ark_ff10biginteger10arithmetic8find_naf28_$u7b$$u7b$closure$u7d$$u7d$28_$u7b$$u7b$closure$u7d$$u7d$17h30e37e3b0a46303fE"}
!51 = distinct !{!51, !52, !"_ZN6ark_ff10biginteger10arithmetic8find_naf28_$u7b$$u7b$closure$u7d$$u7d$17h1d0f9d4137556c00E: %num.0"}
!52 = distinct !{!52, !"_ZN6ark_ff10biginteger10arithmetic8find_naf28_$u7b$$u7b$closure$u7d$$u7d$17h1d0f9d4137556c00E"}
!53 = !{!54, !56, !58}
!54 = distinct !{!54, !55, !"_ZN6ark_ff10biginteger10arithmetic3adc17h8bfac79896473cd8E: %a"}
!55 = distinct !{!55, !"_ZN6ark_ff10biginteger10arithmetic3adc17h8bfac79896473cd8E"}
!56 = distinct !{!56, !57, !"_ZN6ark_ff10biginteger10arithmetic8find_naf28_$u7b$$u7b$closure$u7d$$u7d$28_$u7b$$u7b$closure$u7d$$u7d$17hafef397fdecda6d4E: %_3.0"}
!57 = distinct !{!57, !"_ZN6ark_ff10biginteger10arithmetic8find_naf28_$u7b$$u7b$closure$u7d$$u7d$28_$u7b$$u7b$closure$u7d$$u7d$17hafef397fdecda6d4E"}
!58 = distinct !{!58, !59, !"_ZN6ark_ff10biginteger10arithmetic8find_naf28_$u7b$$u7b$closure$u7d$$u7d$17ha864c974777eae84E: %num.0"}
!59 = distinct !{!59, !"_ZN6ark_ff10biginteger10arithmetic8find_naf28_$u7b$$u7b$closure$u7d$$u7d$17ha864c974777eae84E"}
!60 = !{!61, !63, !65}
!61 = distinct !{!61, !62, !"_ZN99_$LT$core..iter..adapters..zip..Zip$LT$A$C$B$GT$$u20$as$u20$core..iter..adapters..zip..SpecFold$GT$9spec_fold17h18fd56d5ea4ab2b8E: %self"}
!62 = distinct !{!62, !"_ZN99_$LT$core..iter..adapters..zip..Zip$LT$A$C$B$GT$$u20$as$u20$core..iter..adapters..zip..SpecFold$GT$9spec_fold17h18fd56d5ea4ab2b8E"}
!63 = distinct !{!63, !64, !"_ZN111_$LT$core..iter..adapters..zip..Zip$LT$A$C$B$GT$$u20$as$u20$core..iter..adapters..zip..ZipImpl$LT$A$C$B$GT$$GT$4fold17h4433eaeab5012d67E: %self"}
!64 = distinct !{!64, !"_ZN111_$LT$core..iter..adapters..zip..Zip$LT$A$C$B$GT$$u20$as$u20$core..iter..adapters..zip..ZipImpl$LT$A$C$B$GT$$GT$4fold17h4433eaeab5012d67E"}
!65 = distinct !{!65, !66, !"_ZN102_$LT$core..iter..adapters..zip..Zip$LT$A$C$B$GT$$u20$as$u20$core..iter..traits..iterator..Iterator$GT$4fold17hef93e992003c02c2E: %self"}
!66 = distinct !{!66, !"_ZN102_$LT$core..iter..adapters..zip..Zip$LT$A$C$B$GT$$u20$as$u20$core..iter..traits..iterator..Iterator$GT$4fold17hef93e992003c02c2E"}
!67 = !{!68, !70, !72}
!68 = distinct !{!68, !69, !"_ZN6ark_ff10biginteger10arithmetic3sbb17hb741f409be17e120E: %a"}
!69 = distinct !{!69, !"_ZN6ark_ff10biginteger10arithmetic3sbb17hb741f409be17e120E"}
!70 = distinct !{!70, !71, !"_ZN6ark_ff10biginteger10arithmetic8find_naf28_$u7b$$u7b$closure$u7d$$u7d$28_$u7b$$u7b$closure$u7d$$u7d$17hc74a6602aa6933cdE: %_3.0"}
!71 = distinct !{!71, !"_ZN6ark_ff10biginteger10arithmetic8find_naf28_$u7b$$u7b$closure$u7d$$u7d$28_$u7b$$u7b$closure$u7d$$u7d$17hc74a6602aa6933cdE"}
!72 = distinct !{!72, !73, !"_ZN6ark_ff10biginteger10arithmetic8find_naf28_$u7b$$u7b$closure$u7d$$u7d$17h5353e5983a10e818E: %num.0"}
!73 = distinct !{!73, !"_ZN6ark_ff10biginteger10arithmetic8find_naf28_$u7b$$u7b$closure$u7d$$u7d$17h5353e5983a10e818E"}
!74 = !{!75, !77, !79}
!75 = distinct !{!75, !76, !"_ZN99_$LT$core..iter..adapters..zip..Zip$LT$A$C$B$GT$$u20$as$u20$core..iter..adapters..zip..SpecFold$GT$9spec_fold17h60c961b3b4ef3be9E: %self"}
!76 = distinct !{!76, !"_ZN99_$LT$core..iter..adapters..zip..Zip$LT$A$C$B$GT$$u20$as$u20$core..iter..adapters..zip..SpecFold$GT$9spec_fold17h60c961b3b4ef3be9E"}
!77 = distinct !{!77, !78, !"_ZN111_$LT$core..iter..adapters..zip..Zip$LT$A$C$B$GT$$u20$as$u20$core..iter..adapters..zip..ZipImpl$LT$A$C$B$GT$$GT$4fold17h3d798a58772063a7E: %self"}
!78 = distinct !{!78, !"_ZN111_$LT$core..iter..adapters..zip..Zip$LT$A$C$B$GT$$u20$as$u20$core..iter..adapters..zip..ZipImpl$LT$A$C$B$GT$$GT$4fold17h3d798a58772063a7E"}
!79 = distinct !{!79, !80, !"_ZN102_$LT$core..iter..adapters..zip..Zip$LT$A$C$B$GT$$u20$as$u20$core..iter..traits..iterator..Iterator$GT$4fold17h0159a4bfe5ca9419E: %self"}
!80 = distinct !{!80, !"_ZN102_$LT$core..iter..adapters..zip..Zip$LT$A$C$B$GT$$u20$as$u20$core..iter..traits..iterator..Iterator$GT$4fold17h0159a4bfe5ca9419E"}
!81 = !{!"branch_weights", !"expected", i32 2000, i32 1}
!82 = !{!83, !85, !87}
!83 = distinct !{!83, !84, !"_ZN106_$LT$core..ops..range..Range$LT$usize$GT$$u20$as$u20$core..slice..index..SliceIndex$LT$$u5b$T$u5d$$GT$$GT$9index_mut17hcd922df1f4864c4cE: %slice.0"}
!84 = distinct !{!84, !"_ZN106_$LT$core..ops..range..Range$LT$usize$GT$$u20$as$u20$core..slice..index..SliceIndex$LT$$u5b$T$u5d$$GT$$GT$9index_mut17hcd922df1f4864c4cE"}
!85 = distinct !{!85, !86, !"_ZN108_$LT$core..ops..range..RangeTo$LT$usize$GT$$u20$as$u20$core..slice..index..SliceIndex$LT$$u5b$T$u5d$$GT$$GT$9index_mut17h5375ef5a1bbee36aE: %slice.0"}
!86 = distinct !{!86, !"_ZN108_$LT$core..ops..range..RangeTo$LT$usize$GT$$u20$as$u20$core..slice..index..SliceIndex$LT$$u5b$T$u5d$$GT$$GT$9index_mut17h5375ef5a1bbee36aE"}
!87 = distinct !{!87, !88, !"_ZN4core5array88_$LT$impl$u20$core..ops..index..IndexMut$LT$I$GT$$u20$for$u20$$u5b$T$u3b$$u20$N$u5d$$GT$9index_mut17hfce6b426728cb4ceE: %self"}
!88 = distinct !{!88, !"_ZN4core5array88_$LT$impl$u20$core..ops..index..IndexMut$LT$I$GT$$u20$for$u20$$u5b$T$u3b$$u20$N$u5d$$GT$9index_mut17hfce6b426728cb4ceE"}
!89 = !{!90, !92, !93, !95}
!90 = distinct !{!90, !91, !"_ZN4core5slice20copy_from_slice_impl17h3f690865aca33cefE: %dest.0"}
!91 = distinct !{!91, !"_ZN4core5slice20copy_from_slice_impl17h3f690865aca33cefE"}
!92 = distinct !{!92, !91, !"_ZN4core5slice20copy_from_slice_impl17h3f690865aca33cefE: %src.0"}
!93 = distinct !{!93, !94, !"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$15copy_from_slice17h0144fe076e94ca57E: %self.0"}
!94 = distinct !{!94, !"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$15copy_from_slice17h0144fe076e94ca57E"}
!95 = distinct !{!95, !94, !"_ZN4core5slice29_$LT$impl$u20$$u5b$T$u5d$$GT$15copy_from_slice17h0144fe076e94ca57E: %src.0"}
!96 = !{i8 -1, i8 2}
!97 = !{!98}
!98 = distinct !{!98, !99, !"_ZN10num_bigint7biguint8division84_$LT$impl$u20$core..ops..arith..Rem$u20$for$u20$$RF$num_bigint..biguint..BigUint$GT$3rem17h5a401e798c8e41cbE: %other:pre.rot"}
!99 = distinct !{!99, !"_ZN10num_bigint7biguint8division84_$LT$impl$u20$core..ops..arith..Rem$u20$for$u20$$RF$num_bigint..biguint..BigUint$GT$3rem17h5a401e798c8e41cbE"}
!100 = !{!101, !102}
!101 = distinct !{!101, !99, !"_ZN10num_bigint7biguint8division84_$LT$impl$u20$core..ops..arith..Rem$u20$for$u20$$RF$num_bigint..biguint..BigUint$GT$3rem17h5a401e798c8e41cbE: %r"}
!102 = distinct !{!102, !99, !"_ZN10num_bigint7biguint8division84_$LT$impl$u20$core..ops..arith..Rem$u20$for$u20$$RF$num_bigint..biguint..BigUint$GT$3rem17h5a401e798c8e41cbE: %self:pre.rot"}
!103 = !{!104}
!104 = distinct !{!104, !99, !"_ZN10num_bigint7biguint8division84_$LT$impl$u20$core..ops..arith..Rem$u20$for$u20$$RF$num_bigint..biguint..BigUint$GT$3rem17h5a401e798c8e41cbE: %self"}
!105 = !{!106}
!106 = distinct !{!106, !99, !"_ZN10num_bigint7biguint8division84_$LT$impl$u20$core..ops..arith..Rem$u20$for$u20$$RF$num_bigint..biguint..BigUint$GT$3rem17h5a401e798c8e41cbE: %other"}
!107 = !{!101, !104}
!108 = !{!101, !104, !106}
!109 = !{!101}
!110 = !{!104, !106}
!111 = !{!101, !106}
!112 = !{!"branch_weights", !"expected", i32 0, i32 -2147483648}
!113 = !{!114}
!114 = distinct !{!114, !115, !"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h56fe8203bedfe7efE: %self"}
!115 = distinct !{!115, !"_ZN5alloc3vec16Vec$LT$T$C$A$GT$8push_mut17h56fe8203bedfe7efE"}
!116 = !{!117}
!117 = distinct !{!117, !118, !"_ZN10num_bigint7biguint8division126_$LT$impl$u20$core..ops..arith..DivAssign$LT$$RF$num_bigint..biguint..BigUint$GT$$u20$for$u20$num_bigint..biguint..BigUint$GT$10div_assign17hb98d4276a2df0d37E: %self"}
!118 = distinct !{!118, !"_ZN10num_bigint7biguint8division126_$LT$impl$u20$core..ops..arith..DivAssign$LT$$RF$num_bigint..biguint..BigUint$GT$$u20$for$u20$num_bigint..biguint..BigUint$GT$10div_assign17hb98d4276a2df0d37E"}
!119 = !{!117, !120}
!120 = distinct !{!120, !118, !"_ZN10num_bigint7biguint8division126_$LT$impl$u20$core..ops..arith..DivAssign$LT$$RF$num_bigint..biguint..BigUint$GT$$u20$for$u20$num_bigint..biguint..BigUint$GT$10div_assign17hb98d4276a2df0d37E: %other"}
!121 = !{!120}
!122 = !{!123}
!123 = distinct !{!123, !99, !"_ZN10num_bigint7biguint8division84_$LT$impl$u20$core..ops..arith..Rem$u20$for$u20$$RF$num_bigint..biguint..BigUint$GT$3rem17h5a401e798c8e41cbE: %other:h.rot"}
!124 = !{!101, !125}
!125 = distinct !{!125, !99, !"_ZN10num_bigint7biguint8division84_$LT$impl$u20$core..ops..arith..Rem$u20$for$u20$$RF$num_bigint..biguint..BigUint$GT$3rem17h5a401e798c8e41cbE: %self:h.rot"}
!126 = distinct !{!126, !127}
!127 = !{!"llvm.loop.peeled.count", i32 1}
