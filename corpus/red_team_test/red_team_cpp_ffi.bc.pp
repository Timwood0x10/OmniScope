; ModuleID = '/Users/scc/code/zigcode/OmniScope/corpus/red_team_test/red_team_cpp_ffi.cpp'
source_filename = "/Users/scc/code/zigcode/OmniScope/corpus/red_team_test/red_team_cpp_ffi.cpp"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

%"class.std::__1::unique_ptr" = type { %struct.anon }
%struct.anon = type { ptr }
%"class.std::__1::shared_ptr" = type { ptr, ptr }
%struct.Node = type <{ %"class.std::__1::shared_ptr", i32, [4 x i8] }>
%"class.std::__1::allocator" = type { i8 }
%struct.LeakyConstructor = type { ptr, ptr }
%class.Derived = type { %class.Base, ptr }
%class.Base = type { i32 }
%"class.std::__1::__shared_count" = type { ptr, i64 }
%"struct.std::__1::__allocation_guard" = type { [8 x i8], i64, ptr }
%"struct.std::__1::__shared_ptr_emplace" = type { %"class.std::__1::__shared_weak_count", %"struct.std::__1::__shared_ptr_emplace<Node, std::__1::allocator<Node>>::_Storage" }
%"class.std::__1::__shared_weak_count" = type { %"class.std::__1::__shared_count", i64 }
%"struct.std::__1::__shared_ptr_emplace<Node, std::__1::allocator<Node>>::_Storage" = type { [24 x i8] }
%"class.std::__1::allocator.1" = type { i8 }
%"struct.std::__1::__shared_ptr_emplace<Node, std::__1::allocator<Node>>::_Storage::_Data" = type { %struct.anon.2 }
%struct.anon.2 = type { %struct.Node.base, %"class.std::__1::__compressed_pair_padding.3" }
%struct.Node.base = type <{ %"class.std::__1::shared_ptr", i32 }>
%"class.std::__1::__compressed_pair_padding.3" = type { [4 x i8] }

@.str = private unnamed_addr constant [26 x i8] c"CPP-BUG-01: arr[50] = %d\0A\00", align 1
@_ZTISt9bad_alloc = external constant ptr
@.str.1 = private unnamed_addr constant [30 x i8] c"CPP-BUG-02: caught exception\0A\00", align 1
@.str.2 = private unnamed_addr constant [29 x i8] c"negative value in C callback\00", align 1
@_ZTISt13runtime_error = external constant ptr
@.str.3 = private unnamed_addr constant [35 x i8] c"CPP-BUG-06 callback: %s, value=%d\0A\00", align 1
@.str.4 = private unnamed_addr constant [17 x i8] c"callback context\00", align 1
@.str.5 = private unnamed_addr constant [50 x i8] c"CPP-BUG-08: caught bad_alloc, but buffer1 leaked\0A\00", align 1
@.str.6 = private unnamed_addr constant [19 x i8] c"derived allocation\00", align 1
@.str.7 = private unnamed_addr constant [15 x i8] c"Base::~Base()\0A\00", align 1
@_ZTISt20bad_array_new_length = external constant ptr
@_ZTVNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEEE = linkonce_odr unnamed_addr constant { [7 x ptr] } { [7 x ptr] [ptr null, ptr @_ZTINSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEEE, ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEED1Ev, ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEED0Ev, ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE16__on_zero_sharedEv, ptr @_ZNKSt3__119__shared_weak_count13__get_deleterERKSt9type_info, ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE21__on_zero_shared_weakEv] }, align 8
@_ZTINSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEEE = linkonce_odr hidden constant { ptr, ptr, ptr } { ptr getelementptr inbounds (ptr, ptr @_ZTVN10__cxxabiv120__si_class_type_infoE, i64 2), ptr inttoptr (i64 add (i64 ptrtoint (ptr @_ZTSNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEEE to i64), i64 -9223372036854775808) to ptr), ptr @_ZTINSt3__119__shared_weak_countE }, align 8
@_ZTVN10__cxxabiv120__si_class_type_infoE = external global [0 x ptr]
@_ZTSNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEEE = linkonce_odr hidden constant [57 x i8] c"NSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEEE\00", align 1
@_ZTINSt3__119__shared_weak_countE = external constant ptr
@_ZTVNSt3__119__shared_weak_countE = external unnamed_addr constant { [7 x ptr] }, align 8
@_ZTVNSt3__114__shared_countE = external unnamed_addr constant { [5 x ptr] }, align 8
@.str.8 = private unnamed_addr constant [20 x i8] c"Node(%d) destroyed\0A\00", align 1

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define void @_Z36cpp_bug_01_new_array_delete_mismatchv() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca i32, align 4
  %3 = call noalias noundef nonnull ptr @_Znam(i64 noundef 400) #11
  store ptr %3, ptr %1, align 8
  store i32 0, ptr %2, align 4
  br label %4

4:                                                ; preds = %13, %0
  %5 = load i32, ptr %2, align 4
  %6 = icmp slt i32 %5, 100
  br i1 %6, label %7, label %16

7:                                                ; preds = %4
  %8 = load i32, ptr %2, align 4
  %9 = load ptr, ptr %1, align 8
  %10 = load i32, ptr %2, align 4
  %11 = sext i32 %10 to i64
  %12 = getelementptr inbounds i32, ptr %9, i64 %11
  store i32 %8, ptr %12, align 4
  br label %13

13:                                               ; preds = %7
  %14 = load i32, ptr %2, align 4
  %15 = add nsw i32 %14, 1
  store i32 %15, ptr %2, align 4
  br label %4, !llvm.loop !5

16:                                               ; preds = %4
  %17 = load ptr, ptr %1, align 8
  %18 = getelementptr inbounds i32, ptr %17, i64 50
  %19 = load i32, ptr %18, align 4
  %20 = call i32 (ptr, ...) @printf(ptr noundef @.str, i32 noundef %19)
  %21 = load ptr, ptr %1, align 8
  %22 = icmp eq ptr %21, null
  br i1 %22, label %24, label %23

23:                                               ; preds = %16
  call void @_ZdlPvm(ptr noundef %21, i64 noundef 4) #12
  br label %24

24:                                               ; preds = %23, %16
  ret void
}

; Function Attrs: nobuiltin allocsize(0)
declare noundef nonnull ptr @_Znam(i64 noundef) #1

declare i32 @printf(ptr noundef, ...) #2

; Function Attrs: nobuiltin nounwind
declare void @_ZdlPvm(ptr noundef, i64 noundef) #3

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define void @_Z26cpp_bug_02_throw_through_cv() #0 personality ptr @__gxx_personality_v0 {
  %1 = alloca ptr, align 8
  %2 = alloca ptr, align 8
  %3 = alloca i32, align 4
  %4 = invoke ptr @c_ffi_alloc(i32 noundef 4)
          to label %5 unwind label %11

5:                                                ; preds = %0
  store ptr %4, ptr %1, align 8
  %6 = load ptr, ptr %1, align 8
  %7 = icmp ne ptr %6, null
  br i1 %7, label %21, label %8

8:                                                ; preds = %5
  %9 = call ptr @__cxa_allocate_exception(i64 8) #13
  %10 = call noundef ptr @_ZNSt9bad_allocC1Ev(ptr noundef nonnull align 8 dereferenceable(8) %9) #13
  invoke void @__cxa_throw(ptr %9, ptr @_ZTISt9bad_alloc, ptr @_ZNSt9bad_allocD1Ev) #14
          to label %38 unwind label %11

11:                                               ; preds = %21, %8, %0
  %12 = landingpad { ptr, i32 }
          catch ptr null
  %13 = extractvalue { ptr, i32 } %12, 0
  store ptr %13, ptr %2, align 8
  %14 = extractvalue { ptr, i32 } %12, 1
  store i32 %14, ptr %3, align 4
  br label %15

15:                                               ; preds = %11
  %16 = load ptr, ptr %2, align 8
  %17 = call ptr @__cxa_begin_catch(ptr %16) #13
  %18 = invoke i32 (ptr, ...) @printf(ptr noundef @.str.1)
          to label %19 unwind label %25

19:                                               ; preds = %15
  call void @__cxa_end_catch()
  br label %20

20:                                               ; preds = %19, %24
  ret void

21:                                               ; preds = %5
  %22 = load ptr, ptr %1, align 8
  store i32 42, ptr %22, align 4
  %23 = load ptr, ptr %1, align 8
  invoke void @c_ffi_free(ptr noundef %23)
          to label %24 unwind label %11

24:                                               ; preds = %21
  br label %20

25:                                               ; preds = %15
  %26 = landingpad { ptr, i32 }
          cleanup
  %27 = extractvalue { ptr, i32 } %26, 0
  store ptr %27, ptr %2, align 8
  %28 = extractvalue { ptr, i32 } %26, 1
  store i32 %28, ptr %3, align 4
  invoke void @__cxa_end_catch()
          to label %29 unwind label %35

29:                                               ; preds = %25
  br label %30

30:                                               ; preds = %29
  %31 = load ptr, ptr %2, align 8
  %32 = load i32, ptr %3, align 4
  %33 = insertvalue { ptr, i32 } poison, ptr %31, 0
  %34 = insertvalue { ptr, i32 } %33, i32 %32, 1
  resume { ptr, i32 } %34

35:                                               ; preds = %25
  %36 = landingpad { ptr, i32 }
          catch ptr null
  %37 = extractvalue { ptr, i32 } %36, 0
  call void @__clang_call_terminate(ptr %37) #15
  unreachable

38:                                               ; preds = %8
  unreachable
}

declare ptr @c_ffi_alloc(i32 noundef) #2

declare i32 @__gxx_personality_v0(...)

declare ptr @__cxa_allocate_exception(i64)

; Function Attrs: nounwind
declare noundef ptr @_ZNSt9bad_allocC1Ev(ptr noundef nonnull returned align 8 dereferenceable(8)) unnamed_addr #4

; Function Attrs: nounwind
declare noundef ptr @_ZNSt9bad_allocD1Ev(ptr noundef nonnull returned align 8 dereferenceable(8)) unnamed_addr #4

declare void @__cxa_throw(ptr, ptr, ptr)

declare void @c_ffi_free(ptr noundef) #2

declare ptr @__cxa_begin_catch(ptr)

declare void @__cxa_end_catch()

; Function Attrs: noinline noreturn nounwind ssp uwtable(sync)
define linkonce_odr hidden void @__clang_call_terminate(ptr noundef %0) #5 {
  %2 = call ptr @__cxa_begin_catch(ptr %0) #13
  call void @_ZSt9terminatev() #15
  unreachable
}

declare void @_ZSt9terminatev()

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define void @_Z24cpp_bug_03_wrong_deleterv() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca %"class.std::__1::unique_ptr", align 8
  %3 = call ptr @c_ffi_alloc(i32 noundef 128)
  store ptr %3, ptr %1, align 8
  %4 = load ptr, ptr %1, align 8
  %5 = call noundef ptr @_ZNSt3__110unique_ptrIcNS_14default_deleteIcEEEC1B9nqe220105ILb1EvEEPc(ptr noundef nonnull align 8 dereferenceable(8) %2, ptr noundef %4) #13
  %6 = call noundef ptr @_ZNSt3__110unique_ptrIcNS_14default_deleteIcEEED1B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(8) %2) #13
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZNSt3__110unique_ptrIcNS_14default_deleteIcEEEC1B9nqe220105ILb1EvEEPc(ptr noundef nonnull returned align 8 dereferenceable(8) %0, ptr noundef %1) unnamed_addr #6 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  %6 = load ptr, ptr %4, align 8
  %7 = call noundef ptr @_ZNSt3__110unique_ptrIcNS_14default_deleteIcEEEC2B9nqe220105ILb1EvEEPc(ptr noundef nonnull align 8 dereferenceable(8) %5, ptr noundef %6) #13
  ret ptr %5
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__110unique_ptrIcNS_14default_deleteIcEEED1B9nqe220105Ev(ptr noundef nonnull returned align 8 dereferenceable(8) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call noundef ptr @_ZNSt3__110unique_ptrIcNS_14default_deleteIcEEED2B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(8) %3) #13
  ret ptr %3
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define void @_Z37cpp_bug_04_missing_virtual_destructorv() #0 personality ptr @__gxx_personality_v0 {
  %1 = alloca ptr, align 8
  %2 = alloca ptr, align 8
  %3 = alloca i32, align 4
  %4 = call noalias noundef nonnull ptr @_Znwm(i64 noundef 16) #11
  %5 = invoke noundef ptr @_ZN7DerivedC1Ev(ptr noundef nonnull align 8 dereferenceable(16) %4)
          to label %6 unwind label %12

6:                                                ; preds = %0
  store ptr %4, ptr %1, align 8
  %7 = load ptr, ptr %1, align 8
  %8 = icmp eq ptr %7, null
  br i1 %8, label %11, label %9

9:                                                ; preds = %6
  %10 = call noundef ptr @_ZN4BaseD1Ev(ptr noundef nonnull align 4 dereferenceable(4) %7) #13
  call void @_ZdlPvm(ptr noundef %7, i64 noundef 4) #12
  br label %11

11:                                               ; preds = %9, %6
  ret void

12:                                               ; preds = %0
  %13 = landingpad { ptr, i32 }
          cleanup
  %14 = extractvalue { ptr, i32 } %13, 0
  store ptr %14, ptr %2, align 8
  %15 = extractvalue { ptr, i32 } %13, 1
  store i32 %15, ptr %3, align 4
  call void @_ZdlPvm(ptr noundef %4, i64 noundef 16) #12
  br label %16

16:                                               ; preds = %12
  %17 = load ptr, ptr %2, align 8
  %18 = load i32, ptr %3, align 4
  %19 = insertvalue { ptr, i32 } poison, ptr %17, 0
  %20 = insertvalue { ptr, i32 } %19, i32 %18, 1
  resume { ptr, i32 } %20
}

; Function Attrs: nobuiltin allocsize(0)
declare noundef nonnull ptr @_Znwm(i64 noundef) #1

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZN7DerivedC1Ev(ptr noundef nonnull returned align 8 dereferenceable(16) %0) unnamed_addr #0 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call noundef ptr @_ZN7DerivedC2Ev(ptr noundef nonnull align 8 dereferenceable(16) %3)
  ret ptr %3
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZN4BaseD1Ev(ptr noundef nonnull returned align 4 dereferenceable(4) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call noundef ptr @_ZN4BaseD2Ev(ptr noundef nonnull align 4 dereferenceable(4) %3) #13
  ret ptr %3
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define void @_Z27cpp_bug_05_shared_ptr_cyclev() #0 personality ptr @__gxx_personality_v0 {
  %1 = alloca %"class.std::__1::shared_ptr", align 8
  %2 = alloca i32, align 4
  %3 = alloca %"class.std::__1::shared_ptr", align 8
  %4 = alloca i32, align 4
  %5 = alloca ptr, align 8
  %6 = alloca i32, align 4
  store i32 1, ptr %2, align 4
  call void @_ZNSt3__111make_sharedB9nqe220105I4NodeJiETnNS_9enable_ifIXntsr8is_arrayIT_EE5valueEiE4typeELi0EEENS_10shared_ptrIS3_EEDpOT0_(ptr dead_on_unwind writable sret(%"class.std::__1::shared_ptr") align 8 %1, ptr noundef nonnull align 4 dereferenceable(4) %2)
  store i32 2, ptr %4, align 4
  invoke void @_ZNSt3__111make_sharedB9nqe220105I4NodeJiETnNS_9enable_ifIXntsr8is_arrayIT_EE5valueEiE4typeELi0EEENS_10shared_ptrIS3_EEDpOT0_(ptr dead_on_unwind writable sret(%"class.std::__1::shared_ptr") align 8 %3, ptr noundef nonnull align 4 dereferenceable(4) %4)
          to label %7 unwind label %16

7:                                                ; preds = %0
  %8 = call noundef ptr @_ZNKSt3__110shared_ptrI4NodeEptB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(16) %1) #13
  %9 = getelementptr inbounds nuw %struct.Node, ptr %8, i32 0, i32 0
  %10 = call noundef nonnull align 8 dereferenceable(16) ptr @_ZNSt3__110shared_ptrI4NodeEaSB9nqe220105ERKS2_(ptr noundef nonnull align 8 dereferenceable(16) %9, ptr noundef nonnull align 8 dereferenceable(16) %3) #13
  %11 = call noundef ptr @_ZNKSt3__110shared_ptrI4NodeEptB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(16) %3) #13
  %12 = getelementptr inbounds nuw %struct.Node, ptr %11, i32 0, i32 0
  %13 = call noundef nonnull align 8 dereferenceable(16) ptr @_ZNSt3__110shared_ptrI4NodeEaSB9nqe220105ERKS2_(ptr noundef nonnull align 8 dereferenceable(16) %12, ptr noundef nonnull align 8 dereferenceable(16) %1) #13
  %14 = call noundef ptr @_ZNSt3__110shared_ptrI4NodeED1B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(16) %3) #13
  %15 = call noundef ptr @_ZNSt3__110shared_ptrI4NodeED1B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(16) %1) #13
  ret void

16:                                               ; preds = %0
  %17 = landingpad { ptr, i32 }
          cleanup
  %18 = extractvalue { ptr, i32 } %17, 0
  store ptr %18, ptr %5, align 8
  %19 = extractvalue { ptr, i32 } %17, 1
  store i32 %19, ptr %6, align 4
  %20 = call noundef ptr @_ZNSt3__110shared_ptrI4NodeED1B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(16) %1) #13
  br label %21

21:                                               ; preds = %16
  %22 = load ptr, ptr %5, align 8
  %23 = load i32, ptr %6, align 4
  %24 = insertvalue { ptr, i32 } poison, ptr %22, 0
  %25 = insertvalue { ptr, i32 } %24, i32 %23, 1
  resume { ptr, i32 } %25
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__111make_sharedB9nqe220105I4NodeJiETnNS_9enable_ifIXntsr8is_arrayIT_EE5valueEiE4typeELi0EEENS_10shared_ptrIS3_EEDpOT0_(ptr dead_on_unwind noalias writable sret(%"class.std::__1::shared_ptr") align 8 %0, ptr noundef nonnull align 4 dereferenceable(4) %1) #0 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca %"class.std::__1::allocator", align 1
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %6 = load ptr, ptr %4, align 8, !nonnull !7, !align !8
  call void @_ZNSt3__115allocate_sharedB9nqe220105I4NodeNS_9allocatorIS1_EEJiETnNS_9enable_ifIXntsr8is_arrayIT_EE5valueEiE4typeELi0EEENS_10shared_ptrIS5_EERKT0_DpOT1_(ptr dead_on_unwind writable sret(%"class.std::__1::shared_ptr") align 8 %0, ptr noundef nonnull align 1 dereferenceable(1) %5, ptr noundef nonnull align 4 dereferenceable(4) %6)
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNKSt3__110shared_ptrI4NodeEptB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(16) %0) #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %3, i32 0, i32 0
  %5 = load ptr, ptr %4, align 8
  ret ptr %5
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef nonnull align 8 dereferenceable(16) ptr @_ZNSt3__110shared_ptrI4NodeEaSB9nqe220105ERKS2_(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %1) #6 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca %"class.std::__1::shared_ptr", align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %6 = load ptr, ptr %3, align 8
  %7 = load ptr, ptr %4, align 8, !nonnull !7, !align !9
  %8 = call noundef ptr @_ZNSt3__110shared_ptrI4NodeEC1B9nqe220105ERKS2_(ptr noundef nonnull align 8 dereferenceable(16) %5, ptr noundef nonnull align 8 dereferenceable(16) %7) #13
  call void @_ZNSt3__110shared_ptrI4NodeE4swapB9nqe220105ERS2_(ptr noundef nonnull align 8 dereferenceable(16) %5, ptr noundef nonnull align 8 dereferenceable(16) %6) #13
  %9 = call noundef ptr @_ZNSt3__110shared_ptrI4NodeED1B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(16) %5) #13
  ret ptr %6
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__110shared_ptrI4NodeED1B9nqe220105Ev(ptr noundef nonnull returned align 8 dereferenceable(16) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call noundef ptr @_ZNSt3__110shared_ptrI4NodeED2B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(16) %3) #13
  ret ptr %3
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define void @_Z12cpp_callbackPvi(ptr noundef %0, i32 noundef %1) #0 personality ptr @__gxx_personality_v0 {
  %3 = alloca ptr, align 8
  %4 = alloca i32, align 4
  %5 = alloca ptr, align 8
  %6 = alloca ptr, align 8
  %7 = alloca i32, align 4
  store ptr %0, ptr %3, align 8
  store i32 %1, ptr %4, align 4
  %8 = load ptr, ptr %3, align 8
  store ptr %8, ptr %5, align 8
  %9 = load i32, ptr %4, align 4
  %10 = icmp slt i32 %9, 0
  br i1 %10, label %11, label %19

11:                                               ; preds = %2
  %12 = call ptr @__cxa_allocate_exception(i64 16) #13
  %13 = invoke noundef ptr @_ZNSt13runtime_errorC1EPKc(ptr noundef nonnull align 8 dereferenceable(16) %12, ptr noundef @.str.2)
          to label %14 unwind label %15

14:                                               ; preds = %11
  call void @__cxa_throw(ptr %12, ptr @_ZTISt13runtime_error, ptr @_ZNSt13runtime_errorD1Ev) #14
  unreachable

15:                                               ; preds = %11
  %16 = landingpad { ptr, i32 }
          cleanup
  %17 = extractvalue { ptr, i32 } %16, 0
  store ptr %17, ptr %6, align 8
  %18 = extractvalue { ptr, i32 } %16, 1
  store i32 %18, ptr %7, align 4
  call void @__cxa_free_exception(ptr %12) #13
  br label %23

19:                                               ; preds = %2
  %20 = load ptr, ptr %5, align 8
  %21 = load i32, ptr %4, align 4
  %22 = call i32 (ptr, ...) @printf(ptr noundef @.str.3, ptr noundef %20, i32 noundef %21)
  ret void

23:                                               ; preds = %15
  %24 = load ptr, ptr %6, align 8
  %25 = load i32, ptr %7, align 4
  %26 = insertvalue { ptr, i32 } poison, ptr %24, 0
  %27 = insertvalue { ptr, i32 } %26, i32 %25, 1
  resume { ptr, i32 } %27
}

declare noundef ptr @_ZNSt13runtime_errorC1EPKc(ptr noundef nonnull returned align 8 dereferenceable(16), ptr noundef) unnamed_addr #2

declare void @__cxa_free_exception(ptr)

; Function Attrs: nounwind
declare noundef ptr @_ZNSt13runtime_errorD1Ev(ptr noundef nonnull returned align 8 dereferenceable(16)) unnamed_addr #4

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define void @_Z32cpp_bug_06_exception_in_callbackv() #0 {
  %1 = alloca ptr, align 8
  %2 = call noalias noundef nonnull ptr @_Znam(i64 noundef 64) #11
  store ptr %2, ptr %1, align 8
  %3 = load ptr, ptr %1, align 8
  %4 = call ptr @strcpy(ptr noundef %3, ptr noundef @.str.4) #13
  %5 = load ptr, ptr %1, align 8
  call void @c_ffi_register_callback(ptr noundef @_Z12cpp_callbackPvi, ptr noundef %5)
  call void @c_ffi_trigger_callback()
  %6 = load ptr, ptr %1, align 8
  %7 = icmp eq ptr %6, null
  br i1 %7, label %9, label %8

8:                                                ; preds = %0
  call void @_ZdaPv(ptr noundef %6) #12
  br label %9

9:                                                ; preds = %8, %0
  ret void
}

; Function Attrs: nounwind
declare ptr @strcpy(ptr noundef, ptr noundef) #4

declare void @c_ffi_register_callback(ptr noundef, ptr noundef) #2

declare void @c_ffi_trigger_callback() #2

; Function Attrs: nobuiltin nounwind
declare void @_ZdaPv(ptr noundef) #3

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define void @_Z29cpp_bug_07_placement_new_leakv() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca ptr, align 8
  %3 = call ptr @c_ffi_alloc(i32 noundef 16)
  store ptr %3, ptr %1, align 8
  %4 = load ptr, ptr %1, align 8
  %5 = call noundef ptr @_ZN7DerivedC1Ev(ptr noundef nonnull align 8 dereferenceable(16) %4)
  store ptr %4, ptr %2, align 8
  %6 = load ptr, ptr %1, align 8
  call void @c_ffi_free(ptr noundef %6)
  ret void
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define void @_Z28cpp_bug_08_constructor_throwv() #0 personality ptr @__gxx_personality_v0 {
  %1 = alloca %struct.LeakyConstructor, align 8
  %2 = alloca ptr, align 8
  %3 = alloca i32, align 4
  %4 = alloca ptr, align 8
  %5 = invoke noundef ptr @_ZN16LeakyConstructorC1Ev(ptr noundef nonnull align 8 dereferenceable(16) %1)
          to label %6 unwind label %8

6:                                                ; preds = %0
  %7 = call noundef ptr @_ZN16LeakyConstructorD1Ev(ptr noundef nonnull align 8 dereferenceable(16) %1) #13
  br label %21

8:                                                ; preds = %0
  %9 = landingpad { ptr, i32 }
          catch ptr @_ZTISt9bad_alloc
  %10 = extractvalue { ptr, i32 } %9, 0
  store ptr %10, ptr %2, align 8
  %11 = extractvalue { ptr, i32 } %9, 1
  store i32 %11, ptr %3, align 4
  br label %12

12:                                               ; preds = %8
  %13 = load i32, ptr %3, align 4
  %14 = call i32 @llvm.eh.typeid.for.p0(ptr @_ZTISt9bad_alloc) #13
  %15 = icmp eq i32 %13, %14
  br i1 %15, label %16, label %27

16:                                               ; preds = %12
  %17 = load ptr, ptr %2, align 8
  %18 = call ptr @__cxa_begin_catch(ptr %17) #13
  store ptr %18, ptr %4, align 8
  %19 = invoke i32 (ptr, ...) @printf(ptr noundef @.str.5)
          to label %20 unwind label %22

20:                                               ; preds = %16
  call void @__cxa_end_catch()
  br label %21

21:                                               ; preds = %20, %6
  ret void

22:                                               ; preds = %16
  %23 = landingpad { ptr, i32 }
          cleanup
  %24 = extractvalue { ptr, i32 } %23, 0
  store ptr %24, ptr %2, align 8
  %25 = extractvalue { ptr, i32 } %23, 1
  store i32 %25, ptr %3, align 4
  invoke void @__cxa_end_catch()
          to label %26 unwind label %32

26:                                               ; preds = %22
  br label %27

27:                                               ; preds = %26, %12
  %28 = load ptr, ptr %2, align 8
  %29 = load i32, ptr %3, align 4
  %30 = insertvalue { ptr, i32 } poison, ptr %28, 0
  %31 = insertvalue { ptr, i32 } %30, i32 %29, 1
  resume { ptr, i32 } %31

32:                                               ; preds = %22
  %33 = landingpad { ptr, i32 }
          catch ptr null
  %34 = extractvalue { ptr, i32 } %33, 0
  call void @__clang_call_terminate(ptr %34) #15
  unreachable
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZN16LeakyConstructorC1Ev(ptr noundef nonnull returned align 8 dereferenceable(16) %0) unnamed_addr #0 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call noundef ptr @_ZN16LeakyConstructorC2Ev(ptr noundef nonnull align 8 dereferenceable(16) %3)
  ret ptr %3
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZN16LeakyConstructorD1Ev(ptr noundef nonnull returned align 8 dereferenceable(16) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call noundef ptr @_ZN16LeakyConstructorD2Ev(ptr noundef nonnull align 8 dereferenceable(16) %3) #13
  ret ptr %3
}

; Function Attrs: nounwind memory(none)
declare i32 @llvm.eh.typeid.for.p0(ptr) #7

; Function Attrs: mustprogress noinline norecurse optnone ssp uwtable(sync)
define noundef i32 @main() #8 {
  %1 = alloca i32, align 4
  store i32 0, ptr %1, align 4
  call void @_Z36cpp_bug_01_new_array_delete_mismatchv()
  call void @_Z26cpp_bug_02_throw_through_cv()
  call void @_Z24cpp_bug_03_wrong_deleterv()
  call void @_Z37cpp_bug_04_missing_virtual_destructorv()
  call void @_Z27cpp_bug_05_shared_ptr_cyclev()
  call void @_Z32cpp_bug_06_exception_in_callbackv()
  call void @_Z29cpp_bug_07_placement_new_leakv()
  call void @_Z28cpp_bug_08_constructor_throwv()
  ret i32 0
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZN7DerivedC2Ev(ptr noundef nonnull returned align 8 dereferenceable(16) %0) unnamed_addr #0 personality ptr @__gxx_personality_v0 {
  %2 = alloca ptr, align 8
  %3 = alloca ptr, align 8
  %4 = alloca i32, align 4
  store ptr %0, ptr %2, align 8
  %5 = load ptr, ptr %2, align 8
  %6 = invoke noalias noundef nonnull ptr @_Znam(i64 noundef 256) #11
          to label %7 unwind label %12

7:                                                ; preds = %1
  %8 = getelementptr inbounds nuw %class.Derived, ptr %5, i32 0, i32 1
  store ptr %6, ptr %8, align 8
  %9 = getelementptr inbounds nuw %class.Derived, ptr %5, i32 0, i32 1
  %10 = load ptr, ptr %9, align 8
  %11 = call ptr @strcpy(ptr noundef %10, ptr noundef @.str.6) #13
  ret ptr %5

12:                                               ; preds = %1
  %13 = landingpad { ptr, i32 }
          cleanup
  %14 = extractvalue { ptr, i32 } %13, 0
  store ptr %14, ptr %3, align 8
  %15 = extractvalue { ptr, i32 } %13, 1
  store i32 %15, ptr %4, align 4
  %16 = call noundef ptr @_ZN4BaseD2Ev(ptr noundef nonnull align 4 dereferenceable(4) %5) #13
  br label %17

17:                                               ; preds = %12
  %18 = load ptr, ptr %3, align 8
  %19 = load i32, ptr %4, align 4
  %20 = insertvalue { ptr, i32 } poison, ptr %18, 0
  %21 = insertvalue { ptr, i32 } %20, i32 %19, 1
  resume { ptr, i32 } %21
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZN4BaseD2Ev(ptr noundef nonnull returned align 4 dereferenceable(4) %0) unnamed_addr #6 personality ptr @__gxx_personality_v0 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = invoke i32 (ptr, ...) @printf(ptr noundef @.str.7)
          to label %5 unwind label %6

5:                                                ; preds = %1
  ret ptr %3

6:                                                ; preds = %1
  %7 = landingpad { ptr, i32 }
          catch ptr null
  %8 = extractvalue { ptr, i32 } %7, 0
  call void @__clang_call_terminate(ptr %8) #15
  unreachable
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZN16LeakyConstructorC2Ev(ptr noundef nonnull returned align 8 dereferenceable(16) %0) unnamed_addr #0 {
  %2 = alloca ptr, align 8
  %3 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  %4 = load ptr, ptr %3, align 8
  store ptr %4, ptr %2, align 8
  %5 = call noalias noundef nonnull ptr @_Znam(i64 noundef 128) #11
  %6 = getelementptr inbounds nuw %struct.LeakyConstructor, ptr %4, i32 0, i32 0
  store ptr %5, ptr %6, align 8
  %7 = call ptr @__cxa_allocate_exception(i64 8) #13
  %8 = call noundef ptr @_ZNSt9bad_allocC1Ev(ptr noundef nonnull align 8 dereferenceable(8) %7) #13
  call void @__cxa_throw(ptr %7, ptr @_ZTISt9bad_alloc, ptr @_ZNSt9bad_allocD1Ev) #14
  unreachable
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZN16LeakyConstructorD2Ev(ptr noundef nonnull returned align 8 dereferenceable(16) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  %3 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  %4 = load ptr, ptr %3, align 8
  store ptr %4, ptr %2, align 8
  %5 = getelementptr inbounds nuw %struct.LeakyConstructor, ptr %4, i32 0, i32 0
  %6 = load ptr, ptr %5, align 8
  %7 = icmp eq ptr %6, null
  br i1 %7, label %9, label %8

8:                                                ; preds = %1
  call void @_ZdaPv(ptr noundef %6) #12
  br label %9

9:                                                ; preds = %8, %1
  %10 = getelementptr inbounds nuw %struct.LeakyConstructor, ptr %4, i32 0, i32 1
  %11 = load ptr, ptr %10, align 8
  %12 = icmp eq ptr %11, null
  br i1 %12, label %14, label %13

13:                                               ; preds = %9
  call void @_ZdaPv(ptr noundef %11) #12
  br label %14

14:                                               ; preds = %13, %9
  %15 = load ptr, ptr %2, align 8
  ret ptr %15
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZNSt3__110unique_ptrIcNS_14default_deleteIcEEEC2B9nqe220105ILb1EvEEPc(ptr noundef nonnull returned align 8 dereferenceable(8) %0, ptr noundef %1) unnamed_addr #6 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  %6 = getelementptr inbounds nuw %"class.std::__1::unique_ptr", ptr %5, i32 0, i32 0
  %7 = getelementptr inbounds nuw %struct.anon, ptr %6, i32 0, i32 0
  %8 = load ptr, ptr %4, align 8
  store ptr %8, ptr %7, align 8
  %9 = getelementptr inbounds nuw %"class.std::__1::unique_ptr", ptr %5, i32 0, i32 0
  %10 = getelementptr inbounds nuw %"class.std::__1::unique_ptr", ptr %5, i32 0, i32 0
  %11 = getelementptr inbounds nuw %"class.std::__1::unique_ptr", ptr %5, i32 0, i32 0
  ret ptr %5
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__110unique_ptrIcNS_14default_deleteIcEEED2B9nqe220105Ev(ptr noundef nonnull returned align 8 dereferenceable(8) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  call void @_ZNSt3__110unique_ptrIcNS_14default_deleteIcEEE5resetB9nqe220105EPc(ptr noundef nonnull align 8 dereferenceable(8) %3, ptr noundef null) #13
  ret ptr %3
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__110unique_ptrIcNS_14default_deleteIcEEE5resetB9nqe220105EPc(ptr noundef nonnull align 8 dereferenceable(8) %0, ptr noundef %1) #6 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %6 = load ptr, ptr %3, align 8
  %7 = getelementptr inbounds nuw %"class.std::__1::unique_ptr", ptr %6, i32 0, i32 0
  %8 = getelementptr inbounds nuw %struct.anon, ptr %7, i32 0, i32 0
  %9 = load ptr, ptr %8, align 8
  store ptr %9, ptr %5, align 8
  %10 = load ptr, ptr %4, align 8
  %11 = getelementptr inbounds nuw %"class.std::__1::unique_ptr", ptr %6, i32 0, i32 0
  %12 = getelementptr inbounds nuw %struct.anon, ptr %11, i32 0, i32 0
  store ptr %10, ptr %12, align 8
  %13 = load ptr, ptr %5, align 8
  %14 = icmp ne ptr %13, null
  br i1 %14, label %15, label %18

15:                                               ; preds = %2
  %16 = getelementptr inbounds nuw %"class.std::__1::unique_ptr", ptr %6, i32 0, i32 0
  %17 = load ptr, ptr %5, align 8
  call void @_ZNKSt3__114default_deleteIcEclB9nqe220105EPc(ptr noundef nonnull align 1 dereferenceable(1) %16, ptr noundef %17) #13
  br label %18

18:                                               ; preds = %15, %2
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNKSt3__114default_deleteIcEclB9nqe220105EPc(ptr noundef nonnull align 1 dereferenceable(1) %0, ptr noundef %1) #6 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  %6 = load ptr, ptr %4, align 8
  %7 = icmp eq ptr %6, null
  br i1 %7, label %9, label %8

8:                                                ; preds = %2
  call void @_ZdlPvm(ptr noundef %6, i64 noundef 1) #12
  br label %9

9:                                                ; preds = %8, %2
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__110shared_ptrI4NodeED2B9nqe220105Ev(ptr noundef nonnull returned align 8 dereferenceable(16) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  %3 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  %4 = load ptr, ptr %3, align 8
  store ptr %4, ptr %2, align 8
  %5 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %4, i32 0, i32 1
  %6 = load ptr, ptr %5, align 8
  %7 = icmp ne ptr %6, null
  br i1 %7, label %8, label %11

8:                                                ; preds = %1
  %9 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %4, i32 0, i32 1
  %10 = load ptr, ptr %9, align 8
  call void @_ZNSt3__119__shared_weak_count16__release_sharedB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %10) #13
  br label %11

11:                                               ; preds = %8, %1
  %12 = load ptr, ptr %2, align 8
  ret ptr %12
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__119__shared_weak_count16__release_sharedB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %0) #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call noundef zeroext i1 @_ZNSt3__114__shared_count16__release_sharedB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(16) %3) #13
  br i1 %4, label %5, label %6

5:                                                ; preds = %1
  call void @_ZNSt3__119__shared_weak_count14__release_weakEv(ptr noundef nonnull align 8 dereferenceable(24) %3) #13
  br label %6

6:                                                ; preds = %5, %1
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef zeroext i1 @_ZNSt3__114__shared_count16__release_sharedB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(16) %0) #6 {
  %2 = alloca i1, align 1
  %3 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  %4 = load ptr, ptr %3, align 8
  %5 = getelementptr inbounds nuw %"class.std::__1::__shared_count", ptr %4, i32 0, i32 1
  %6 = call noundef i64 @_ZNSt3__134__libcpp_atomic_refcount_decrementB9nqe220105IlEET_RS1_(ptr noundef nonnull align 8 dereferenceable(8) %5) #13
  %7 = icmp eq i64 %6, -1
  br i1 %7, label %8, label %12

8:                                                ; preds = %1
  %9 = load ptr, ptr %4, align 8
  %10 = getelementptr inbounds ptr, ptr %9, i64 2
  %11 = load ptr, ptr %10, align 8
  call void %11(ptr noundef nonnull align 8 dereferenceable(16) %4) #13
  store i1 true, ptr %2, align 1
  br label %13

12:                                               ; preds = %1
  store i1 false, ptr %2, align 1
  br label %13

13:                                               ; preds = %12, %8
  %14 = load i1, ptr %2, align 1
  ret i1 %14
}

; Function Attrs: nounwind
declare void @_ZNSt3__119__shared_weak_count14__release_weakEv(ptr noundef nonnull align 8 dereferenceable(24)) #4

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef i64 @_ZNSt3__134__libcpp_atomic_refcount_decrementB9nqe220105IlEET_RS1_(ptr noundef nonnull align 8 dereferenceable(8) %0) #6 {
  %2 = alloca ptr, align 8
  %3 = alloca i64, align 8
  %4 = alloca i64, align 8
  store ptr %0, ptr %2, align 8
  %5 = load ptr, ptr %2, align 8, !nonnull !7, !align !9
  store i64 -1, ptr %3, align 8
  %6 = load i64, ptr %3, align 8
  %7 = atomicrmw add ptr %5, i64 %6 acq_rel, align 8
  %8 = add i64 %7, %6
  store i64 %8, ptr %4, align 8
  %9 = load i64, ptr %4, align 8
  ret i64 %9
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__115allocate_sharedB9nqe220105I4NodeNS_9allocatorIS1_EEJiETnNS_9enable_ifIXntsr8is_arrayIT_EE5valueEiE4typeELi0EEENS_10shared_ptrIS5_EERKT0_DpOT1_(ptr dead_on_unwind noalias writable sret(%"class.std::__1::shared_ptr") align 8 %0, ptr noundef nonnull align 1 dereferenceable(1) %1, ptr noundef nonnull align 4 dereferenceable(4) %2) #0 personality ptr @__gxx_personality_v0 {
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  %6 = alloca ptr, align 8
  %7 = alloca %"struct.std::__1::__allocation_guard", align 8
  %8 = alloca %"class.std::__1::allocator", align 1
  %9 = alloca %"class.std::__1::allocator", align 1
  %10 = alloca ptr, align 8
  %11 = alloca i32, align 4
  %12 = alloca ptr, align 8
  store ptr %0, ptr %4, align 8
  store ptr %1, ptr %5, align 8
  store ptr %2, ptr %6, align 8
  %13 = load ptr, ptr %5, align 8, !nonnull !7
  %14 = call noundef ptr @_ZNSt3__118__allocation_guardINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEEC1B9nqe220105IS4_EET_m(ptr noundef nonnull align 8 dereferenceable(24) %7, i64 noundef 1)
  %15 = call noundef ptr @_ZNKSt3__118__allocation_guardINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEE5__getB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %7) #13
  %16 = load ptr, ptr %5, align 8, !nonnull !7
  %17 = load ptr, ptr %6, align 8, !nonnull !7, !align !8
  %18 = invoke noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEEC1B9nqe220105IJiES3_TnNS_9enable_ifIXntsr7is_sameINT0_10value_typeENS_19__for_overwrite_tagEEE5valueEiE4typeELi0EEES3_DpOT_(ptr noundef nonnull align 8 dereferenceable(48) %15, ptr noundef nonnull align 4 dereferenceable(4) %17)
          to label %19 unwind label %25

19:                                               ; preds = %3
  %20 = call noundef ptr @_ZNSt3__118__allocation_guardINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEE13__release_ptrB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %7) #13
  store ptr %20, ptr %12, align 8
  %21 = load ptr, ptr %12, align 8
  %22 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE10__get_elemB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(48) %21) #13
  %23 = load ptr, ptr %12, align 8
  call void @_ZNSt3__110shared_ptrI4NodeE27__create_with_control_blockB9nqe220105IS1_NS_20__shared_ptr_emplaceIS1_NS_9allocatorIS1_EEEEEES2_PT_PT0_(ptr dead_on_unwind writable sret(%"class.std::__1::shared_ptr") align 8 %0, ptr noundef %22, ptr noundef %23) #13
  %24 = call noundef ptr @_ZNSt3__118__allocation_guardINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEED1B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %7) #13
  ret void

25:                                               ; preds = %3
  %26 = landingpad { ptr, i32 }
          cleanup
  %27 = extractvalue { ptr, i32 } %26, 0
  store ptr %27, ptr %10, align 8
  %28 = extractvalue { ptr, i32 } %26, 1
  store i32 %28, ptr %11, align 4
  %29 = call noundef ptr @_ZNSt3__118__allocation_guardINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEED1B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %7) #13
  br label %30

30:                                               ; preds = %25
  %31 = load ptr, ptr %10, align 8
  %32 = load i32, ptr %11, align 4
  %33 = insertvalue { ptr, i32 } poison, ptr %31, 0
  %34 = insertvalue { ptr, i32 } %33, i32 %32, 1
  resume { ptr, i32 } %34
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZNSt3__118__allocation_guardINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEEC1B9nqe220105IS4_EET_m(ptr noundef nonnull returned align 8 dereferenceable(24) %0, i64 noundef %1) unnamed_addr #0 {
  %3 = alloca %"class.std::__1::allocator", align 1
  %4 = alloca ptr, align 8
  %5 = alloca i64, align 8
  store ptr %0, ptr %4, align 8
  store i64 %1, ptr %5, align 8
  %6 = load ptr, ptr %4, align 8
  %7 = load i64, ptr %5, align 8
  %8 = call noundef ptr @_ZNSt3__118__allocation_guardINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEEC2B9nqe220105IS4_EET_m(ptr noundef nonnull align 8 dereferenceable(24) %6, i64 noundef %7)
  ret ptr %6
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNKSt3__118__allocation_guardINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEE5__getB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %0) #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = getelementptr inbounds nuw %"struct.std::__1::__allocation_guard", ptr %3, i32 0, i32 2
  %5 = load ptr, ptr %4, align 8
  ret ptr %5
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEEC1B9nqe220105IJiES3_TnNS_9enable_ifIXntsr7is_sameINT0_10value_typeENS_19__for_overwrite_tagEEE5valueEiE4typeELi0EEES3_DpOT_(ptr noundef nonnull returned align 8 dereferenceable(48) %0, ptr noundef nonnull align 4 dereferenceable(4) %1) unnamed_addr #0 {
  %3 = alloca %"class.std::__1::allocator", align 1
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  store ptr %0, ptr %4, align 8
  store ptr %1, ptr %5, align 8
  %6 = load ptr, ptr %4, align 8
  %7 = load ptr, ptr %5, align 8
  %8 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEEC2B9nqe220105IJiES3_TnNS_9enable_ifIXntsr7is_sameINT0_10value_typeENS_19__for_overwrite_tagEEE5valueEiE4typeELi0EEES3_DpOT_(ptr noundef nonnull align 8 dereferenceable(48) %6, ptr noundef nonnull align 4 dereferenceable(4) %7)
  ret ptr %6
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__118__allocation_guardINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEE13__release_ptrB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %0) #6 {
  %2 = alloca ptr, align 8
  %3 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %4 = load ptr, ptr %2, align 8
  %5 = getelementptr inbounds nuw %"struct.std::__1::__allocation_guard", ptr %4, i32 0, i32 2
  %6 = load ptr, ptr %5, align 8
  store ptr %6, ptr %3, align 8
  %7 = getelementptr inbounds nuw %"struct.std::__1::__allocation_guard", ptr %4, i32 0, i32 2
  store ptr null, ptr %7, align 8
  %8 = load ptr, ptr %3, align 8
  ret ptr %8
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__110shared_ptrI4NodeE27__create_with_control_blockB9nqe220105IS1_NS_20__shared_ptr_emplaceIS1_NS_9allocatorIS1_EEEEEES2_PT_PT0_(ptr dead_on_unwind noalias writable sret(%"class.std::__1::shared_ptr") align 8 %0, ptr noundef %1, ptr noundef %2) #6 {
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  %6 = alloca ptr, align 8
  %7 = alloca i1, align 1
  store ptr %0, ptr %4, align 8
  store ptr %1, ptr %5, align 8
  store ptr %2, ptr %6, align 8
  store i1 false, ptr %7, align 1
  %8 = call noundef ptr @_ZNSt3__110shared_ptrI4NodeEC1B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(16) %0) #13
  %9 = load ptr, ptr %5, align 8
  %10 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %0, i32 0, i32 0
  store ptr %9, ptr %10, align 8
  %11 = load ptr, ptr %6, align 8
  %12 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %0, i32 0, i32 1
  store ptr %11, ptr %12, align 8
  %13 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %0, i32 0, i32 0
  %14 = load ptr, ptr %13, align 8
  %15 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %0, i32 0, i32 0
  %16 = load ptr, ptr %15, align 8
  call void (ptr, ...) @_ZNSt3__110shared_ptrI4NodeE18__enable_weak_thisB9nqe220105Ez(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef %14, ptr noundef %16) #13
  store i1 true, ptr %7, align 1
  %17 = load i1, ptr %7, align 1
  br i1 %17, label %20, label %18

18:                                               ; preds = %3
  %19 = call noundef ptr @_ZNSt3__110shared_ptrI4NodeED1B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(16) %0) #13
  br label %20

20:                                               ; preds = %18, %3
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE10__get_elemB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(48) %0) #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = getelementptr inbounds nuw %"struct.std::__1::__shared_ptr_emplace", ptr %3, i32 0, i32 1
  %5 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE8_Storage10__get_elemB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %4) #13
  ret ptr %5
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__118__allocation_guardINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEED1B9nqe220105Ev(ptr noundef nonnull returned align 8 dereferenceable(24) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call noundef ptr @_ZNSt3__118__allocation_guardINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEED2B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %3) #13
  ret ptr %3
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZNSt3__118__allocation_guardINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEEC2B9nqe220105IS4_EET_m(ptr noundef nonnull returned align 8 dereferenceable(24) %0, i64 noundef %1) unnamed_addr #0 {
  %3 = alloca %"class.std::__1::allocator", align 1
  %4 = alloca ptr, align 8
  %5 = alloca i64, align 8
  store ptr %0, ptr %4, align 8
  store i64 %1, ptr %5, align 8
  %6 = load ptr, ptr %4, align 8
  %7 = call noundef ptr @_ZNSt3__19allocatorINS_20__shared_ptr_emplaceI4NodeNS0_IS2_EEEEEC1B9nqe220105IS2_EERKNS0_IT_EE(ptr noundef nonnull align 1 dereferenceable(1) %6, ptr noundef nonnull align 1 dereferenceable(1) %3) #13
  %8 = getelementptr inbounds nuw %"struct.std::__1::__allocation_guard", ptr %6, i32 0, i32 1
  %9 = load i64, ptr %5, align 8
  store i64 %9, ptr %8, align 8
  %10 = getelementptr inbounds nuw %"struct.std::__1::__allocation_guard", ptr %6, i32 0, i32 2
  %11 = getelementptr inbounds nuw %"struct.std::__1::__allocation_guard", ptr %6, i32 0, i32 1
  %12 = load i64, ptr %11, align 8
  %13 = call noundef ptr @_ZNSt3__116allocator_traitsINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEE8allocateB9nqe220105ERS6_m(ptr noundef nonnull align 1 dereferenceable(1) %6, i64 noundef %12)
  store ptr %13, ptr %10, align 8
  ret ptr %6
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZNSt3__19allocatorINS_20__shared_ptr_emplaceI4NodeNS0_IS2_EEEEEC1B9nqe220105IS2_EERKNS0_IT_EE(ptr noundef nonnull returned align 1 dereferenceable(1) %0, ptr noundef nonnull align 1 dereferenceable(1) %1) unnamed_addr #6 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  %6 = load ptr, ptr %4, align 8
  %7 = call noundef ptr @_ZNSt3__19allocatorINS_20__shared_ptr_emplaceI4NodeNS0_IS2_EEEEEC2B9nqe220105IS2_EERKNS0_IT_EE(ptr noundef nonnull align 1 dereferenceable(1) %5, ptr noundef nonnull align 1 dereferenceable(1) %6) #13
  ret ptr %5
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__116allocator_traitsINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEE8allocateB9nqe220105ERS6_m(ptr noundef nonnull align 1 dereferenceable(1) %0, i64 noundef %1) #0 {
  %3 = alloca ptr, align 8
  %4 = alloca i64, align 8
  store ptr %0, ptr %3, align 8
  store i64 %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8, !nonnull !7
  %6 = load i64, ptr %4, align 8
  %7 = call noundef ptr @_ZNSt3__19allocatorINS_20__shared_ptr_emplaceI4NodeNS0_IS2_EEEEE8allocateB9nqe220105Em(ptr noundef nonnull align 1 dereferenceable(1) %5, i64 noundef %6)
  ret ptr %7
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZNSt3__19allocatorINS_20__shared_ptr_emplaceI4NodeNS0_IS2_EEEEEC2B9nqe220105IS2_EERKNS0_IT_EE(ptr noundef nonnull returned align 1 dereferenceable(1) %0, ptr noundef nonnull align 1 dereferenceable(1) %1) unnamed_addr #6 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  ret ptr %5
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__19allocatorINS_20__shared_ptr_emplaceI4NodeNS0_IS2_EEEEE8allocateB9nqe220105Em(ptr noundef nonnull align 1 dereferenceable(1) %0, i64 noundef %1) #0 {
  %3 = alloca ptr, align 8
  %4 = alloca i64, align 8
  store ptr %0, ptr %3, align 8
  store i64 %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  %6 = load i64, ptr %4, align 8
  %7 = call noundef i64 @_ZNSt3__116allocator_traitsINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEE8max_sizeB9nqe220105IS6_TnNS_9enable_ifIX16__has_max_size_vIKT_EEiE4typeELi0EEEmRKS6_(ptr noundef nonnull align 1 dereferenceable(1) %5) #13
  %8 = icmp ugt i64 %6, %7
  br i1 %8, label %9, label %10

9:                                                ; preds = %2
  call void @_ZSt28__throw_bad_array_new_lengthB9nqe220105v() #14
  unreachable

10:                                               ; preds = %2
  %11 = load i64, ptr %4, align 8
  %12 = call noundef ptr @_ZNSt3__117__libcpp_allocateB9nqe220105INS_20__shared_ptr_emplaceI4NodeNS_9allocatorIS2_EEEEEEPT_NS_15__element_countEm(i64 noundef %11, i64 noundef 8)
  ret ptr %12
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr noundef i64 @_ZNSt3__116allocator_traitsINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEE8max_sizeB9nqe220105IS6_TnNS_9enable_ifIX16__has_max_size_vIKT_EEiE4typeELi0EEEmRKS6_(ptr noundef nonnull align 1 dereferenceable(1) %0) #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8, !nonnull !7
  %4 = call noundef i64 @_ZNKSt3__19allocatorINS_20__shared_ptr_emplaceI4NodeNS0_IS2_EEEEE8max_sizeB9nqe220105Ev(ptr noundef nonnull align 1 dereferenceable(1) %3) #13
  ret i64 %4
}

; Function Attrs: mustprogress noinline noreturn optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZSt28__throw_bad_array_new_lengthB9nqe220105v() #9 {
  %1 = call ptr @__cxa_allocate_exception(i64 8) #13
  %2 = call noundef ptr @_ZNSt20bad_array_new_lengthC1Ev(ptr noundef nonnull align 8 dereferenceable(8) %1) #13
  call void @__cxa_throw(ptr %1, ptr @_ZTISt20bad_array_new_length, ptr @_ZNSt20bad_array_new_lengthD1Ev) #14
  unreachable
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__117__libcpp_allocateB9nqe220105INS_20__shared_ptr_emplaceI4NodeNS_9allocatorIS2_EEEEEEPT_NS_15__element_countEm(i64 noundef %0, i64 noundef %1) #0 {
  %3 = alloca ptr, align 8
  %4 = alloca i64, align 8
  %5 = alloca i64, align 8
  %6 = alloca i64, align 8
  store i64 %0, ptr %4, align 8
  store i64 %1, ptr %5, align 8
  %7 = load i64, ptr %4, align 8
  %8 = mul i64 %7, 48
  store i64 %8, ptr %6, align 8
  %9 = load i64, ptr %5, align 8
  %10 = call noundef zeroext i1 @_ZNSt3__124__is_overaligned_for_newB9nqe220105Em(i64 noundef %9) #13
  br i1 %10, label %11, label %15

11:                                               ; preds = %2
  %12 = load i64, ptr %6, align 8
  %13 = load i64, ptr %5, align 8
  %14 = call noalias noundef nonnull ptr @_ZnwmSt11align_val_t(i64 noundef %12, i64 noundef %13) #11
  call void @llvm.assume(i1 true) [ "align"(ptr %14, i64 %13) ]
  store ptr %14, ptr %3, align 8
  br label %18

15:                                               ; preds = %2
  %16 = load i64, ptr %6, align 8
  %17 = call noalias noundef nonnull ptr @_Znwm(i64 noundef %16) #11
  store ptr %17, ptr %3, align 8
  br label %18

18:                                               ; preds = %15, %11
  %19 = load ptr, ptr %3, align 8
  ret ptr %19
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef i64 @_ZNKSt3__19allocatorINS_20__shared_ptr_emplaceI4NodeNS0_IS2_EEEEE8max_sizeB9nqe220105Ev(ptr noundef nonnull align 1 dereferenceable(1) %0) #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  ret i64 384307168202282325
}

; Function Attrs: nounwind
declare noundef ptr @_ZNSt20bad_array_new_lengthC1Ev(ptr noundef nonnull returned align 8 dereferenceable(8)) unnamed_addr #4

; Function Attrs: nounwind
declare noundef ptr @_ZNSt20bad_array_new_lengthD1Ev(ptr noundef nonnull returned align 8 dereferenceable(8)) unnamed_addr #4

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef zeroext i1 @_ZNSt3__124__is_overaligned_for_newB9nqe220105Em(i64 noundef %0) #6 {
  %2 = alloca i64, align 8
  store i64 %0, ptr %2, align 8
  %3 = load i64, ptr %2, align 8
  %4 = icmp ugt i64 %3, 16
  ret i1 %4
}

; Function Attrs: nobuiltin allocsize(0)
declare noundef nonnull ptr @_ZnwmSt11align_val_t(i64 noundef, i64 noundef) #1

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(inaccessiblemem: write)
declare void @llvm.assume(i1 noundef) #10

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEEC2B9nqe220105IJiES3_TnNS_9enable_ifIXntsr7is_sameINT0_10value_typeENS_19__for_overwrite_tagEEE5valueEiE4typeELi0EEES3_DpOT_(ptr noundef nonnull returned align 8 dereferenceable(48) %0, ptr noundef nonnull align 4 dereferenceable(4) %1) unnamed_addr #0 personality ptr @__gxx_personality_v0 {
  %3 = alloca %"class.std::__1::allocator", align 1
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  %6 = alloca ptr, align 8
  %7 = alloca i32, align 4
  %8 = alloca %"class.std::__1::allocator", align 1
  store ptr %0, ptr %4, align 8
  store ptr %1, ptr %5, align 8
  %9 = load ptr, ptr %4, align 8
  %10 = call noundef ptr @_ZNSt3__119__shared_weak_countC2B9nqe220105El(ptr noundef nonnull align 8 dereferenceable(24) %9, i64 noundef 0) #13
  store ptr getelementptr inbounds inrange(-16, 40) ({ [7 x ptr] }, ptr @_ZTVNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEEE, i32 0, i32 0, i32 2), ptr %9, align 8
  %11 = getelementptr inbounds nuw %"struct.std::__1::__shared_ptr_emplace", ptr %9, i32 0, i32 1
  %12 = invoke noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE8_StorageC1B9nqe220105EOS3_(ptr noundef nonnull align 8 dereferenceable(24) %11, ptr noundef nonnull align 1 dereferenceable(1) %3)
          to label %13 unwind label %18

13:                                               ; preds = %2
  %14 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE11__get_allocB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(48) %9) #13
  %15 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE10__get_elemB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(48) %9) #13
  %16 = load ptr, ptr %5, align 8, !nonnull !7, !align !8
  invoke void @_ZNSt3__116allocator_traitsINS_9allocatorI4NodeEEE9constructB9nqe220105IS2_JiETnNS_9enable_ifIX17__has_construct_vIS3_PT_DpT0_EEiE4typeELi0EEEvRS3_S8_DpOS9_(ptr noundef nonnull align 1 dereferenceable(1) %8, ptr noundef %15, ptr noundef nonnull align 4 dereferenceable(4) %16)
          to label %17 unwind label %22

17:                                               ; preds = %13
  ret ptr %9

18:                                               ; preds = %2
  %19 = landingpad { ptr, i32 }
          cleanup
  %20 = extractvalue { ptr, i32 } %19, 0
  store ptr %20, ptr %6, align 8
  %21 = extractvalue { ptr, i32 } %19, 1
  store i32 %21, ptr %7, align 4
  br label %27

22:                                               ; preds = %13
  %23 = landingpad { ptr, i32 }
          cleanup
  %24 = extractvalue { ptr, i32 } %23, 0
  store ptr %24, ptr %6, align 8
  %25 = extractvalue { ptr, i32 } %23, 1
  store i32 %25, ptr %7, align 4
  %26 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE8_StorageD1B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %11) #13
  br label %27

27:                                               ; preds = %22, %18
  %28 = call noundef ptr @_ZNSt3__119__shared_weak_countD2Ev(ptr noundef nonnull align 8 dereferenceable(24) %9) #13
  br label %29

29:                                               ; preds = %27
  %30 = load ptr, ptr %6, align 8
  %31 = load i32, ptr %7, align 4
  %32 = insertvalue { ptr, i32 } poison, ptr %30, 0
  %33 = insertvalue { ptr, i32 } %32, i32 %31, 1
  resume { ptr, i32 } %33
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__119__shared_weak_countC2B9nqe220105El(ptr noundef nonnull returned align 8 dereferenceable(24) %0, i64 noundef %1) unnamed_addr #6 {
  %3 = alloca ptr, align 8
  %4 = alloca i64, align 8
  store ptr %0, ptr %3, align 8
  store i64 %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  %6 = load i64, ptr %4, align 8
  %7 = call noundef ptr @_ZNSt3__114__shared_countC2B9nqe220105El(ptr noundef nonnull align 8 dereferenceable(16) %5, i64 noundef %6) #13
  store ptr getelementptr inbounds inrange(-16, 40) ({ [7 x ptr] }, ptr @_ZTVNSt3__119__shared_weak_countE, i32 0, i32 0, i32 2), ptr %5, align 8
  %8 = getelementptr inbounds nuw %"class.std::__1::__shared_weak_count", ptr %5, i32 0, i32 1
  %9 = load i64, ptr %4, align 8
  store i64 %9, ptr %8, align 8
  ret ptr %5
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE8_StorageC1B9nqe220105EOS3_(ptr noundef nonnull returned align 8 dereferenceable(24) %0, ptr noundef nonnull align 1 dereferenceable(1) %1) unnamed_addr #0 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  %6 = load ptr, ptr %4, align 8
  %7 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE8_StorageC2B9nqe220105EOS3_(ptr noundef nonnull align 8 dereferenceable(24) %5, ptr noundef nonnull align 1 dereferenceable(1) %6)
  ret ptr %5
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE11__get_allocB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(48) %0) #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = getelementptr inbounds nuw %"struct.std::__1::__shared_ptr_emplace", ptr %3, i32 0, i32 1
  %5 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE8_Storage11__get_allocB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %4) #13
  ret ptr %5
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr void @_ZNSt3__116allocator_traitsINS_9allocatorI4NodeEEE9constructB9nqe220105IS2_JiETnNS_9enable_ifIX17__has_construct_vIS3_PT_DpT0_EEiE4typeELi0EEEvRS3_S8_DpOS9_(ptr noundef nonnull align 1 dereferenceable(1) %0, ptr noundef %1, ptr noundef nonnull align 4 dereferenceable(4) %2) #0 {
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  %6 = alloca ptr, align 8
  store ptr %0, ptr %4, align 8
  store ptr %1, ptr %5, align 8
  store ptr %2, ptr %6, align 8
  %7 = load ptr, ptr %4, align 8, !nonnull !7
  %8 = load ptr, ptr %5, align 8
  %9 = load ptr, ptr %6, align 8, !nonnull !7, !align !8
  call void @_ZNSt3__19allocatorI4NodeE9constructB9nqe220105IS1_JiEEEvPT_DpOT0_(ptr noundef nonnull align 1 dereferenceable(1) %7, ptr noundef %8, ptr noundef nonnull align 4 dereferenceable(4) %9)
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE8_StorageD1B9nqe220105Ev(ptr noundef nonnull returned align 8 dereferenceable(24) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE8_StorageD2B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %3) #13
  ret ptr %3
}

; Function Attrs: nounwind
declare noundef ptr @_ZNSt3__119__shared_weak_countD2Ev(ptr noundef nonnull returned align 8 dereferenceable(24)) unnamed_addr #4

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEED1Ev(ptr noundef nonnull returned align 8 dereferenceable(48) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEED2Ev(ptr noundef nonnull align 8 dereferenceable(48) %3) #13
  ret ptr %3
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr void @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEED0Ev(ptr noundef nonnull align 8 dereferenceable(48) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEED1Ev(ptr noundef nonnull align 8 dereferenceable(48) %3) #13
  call void @_ZdlPvm(ptr noundef %3, i64 noundef 48) #12
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE16__on_zero_sharedEv(ptr noundef nonnull align 8 dereferenceable(48) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  call void @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE21__on_zero_shared_implB9nqe220105IS3_TnNS_9enable_ifIXntsr7is_sameINT_10value_typeENS_19__for_overwrite_tagEEE5valueEiE4typeELi0EEEvv(ptr noundef nonnull align 8 dereferenceable(48) %3) #13
  ret void
}

; Function Attrs: nounwind
declare noundef ptr @_ZNKSt3__119__shared_weak_count13__get_deleterERKSt9type_info(ptr noundef nonnull align 8 dereferenceable(24), ptr noundef nonnull align 8 dereferenceable(16)) unnamed_addr #4

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE21__on_zero_shared_weakEv(ptr noundef nonnull align 8 dereferenceable(48) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  %3 = alloca %"class.std::__1::allocator.1", align 1
  store ptr %0, ptr %2, align 8
  %4 = load ptr, ptr %2, align 8
  %5 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE11__get_allocB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(48) %4) #13
  %6 = call noundef ptr @_ZNSt3__19allocatorINS_20__shared_ptr_emplaceI4NodeNS0_IS2_EEEEEC1B9nqe220105IS2_EERKNS0_IT_EE(ptr noundef nonnull align 1 dereferenceable(1) %3, ptr noundef nonnull align 1 dereferenceable(1) %5) #13
  %7 = getelementptr inbounds nuw %"struct.std::__1::__shared_ptr_emplace", ptr %4, i32 0, i32 1
  %8 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE8_StorageD1B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %7) #13
  %9 = call noundef ptr @_ZNSt3__114pointer_traitsIPNS_20__shared_ptr_emplaceI4NodeNS_9allocatorIS2_EEEEE10pointer_toB9nqe220105ERS5_(ptr noundef nonnull align 8 dereferenceable(48) %4) #13
  call void @_ZNSt3__116allocator_traitsINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEE10deallocateB9nqe220105ERS6_PS5_m(ptr noundef nonnull align 1 dereferenceable(1) %3, ptr noundef %9, i64 noundef 1) #13
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__114__shared_countC2B9nqe220105El(ptr noundef nonnull returned align 8 dereferenceable(16) %0, i64 noundef %1) unnamed_addr #6 {
  %3 = alloca ptr, align 8
  %4 = alloca i64, align 8
  store ptr %0, ptr %3, align 8
  store i64 %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  store ptr getelementptr inbounds inrange(-16, 24) ({ [5 x ptr] }, ptr @_ZTVNSt3__114__shared_countE, i32 0, i32 0, i32 2), ptr %5, align 8
  %6 = getelementptr inbounds nuw %"class.std::__1::__shared_count", ptr %5, i32 0, i32 1
  %7 = load i64, ptr %4, align 8
  store i64 %7, ptr %6, align 8
  ret ptr %5
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE8_StorageC2B9nqe220105EOS3_(ptr noundef nonnull returned align 8 dereferenceable(24) %0, ptr noundef nonnull align 1 dereferenceable(1) %1) unnamed_addr #6 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  %6 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE8_Storage11__get_allocB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %5) #13
  %7 = load ptr, ptr %4, align 8, !nonnull !7
  ret ptr %5
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE8_Storage11__get_allocB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %0) #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = getelementptr inbounds nuw %"struct.std::__1::__shared_ptr_emplace<Node, std::__1::allocator<Node>>::_Storage", ptr %3, i32 0, i32 0
  %5 = getelementptr inbounds [24 x i8], ptr %4, i64 0, i64 0
  %6 = getelementptr inbounds nuw %"struct.std::__1::__shared_ptr_emplace<Node, std::__1::allocator<Node>>::_Storage::_Data", ptr %5, i32 0, i32 0
  ret ptr %6
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__19allocatorI4NodeE9constructB9nqe220105IS1_JiEEEvPT_DpOT0_(ptr noundef nonnull align 1 dereferenceable(1) %0, ptr noundef %1, ptr noundef nonnull align 4 dereferenceable(4) %2) #0 {
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  %6 = alloca ptr, align 8
  store ptr %0, ptr %4, align 8
  store ptr %1, ptr %5, align 8
  store ptr %2, ptr %6, align 8
  %7 = load ptr, ptr %4, align 8
  %8 = load ptr, ptr %5, align 8
  %9 = load ptr, ptr %6, align 8, !nonnull !7, !align !8
  %10 = load i32, ptr %9, align 4
  %11 = call noundef ptr @_ZN4NodeC1Ei(ptr noundef nonnull align 8 dereferenceable(20) %8, i32 noundef %10)
  ret void
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZN4NodeC1Ei(ptr noundef nonnull returned align 8 dereferenceable(20) %0, i32 noundef %1) unnamed_addr #0 {
  %3 = alloca ptr, align 8
  %4 = alloca i32, align 4
  store ptr %0, ptr %3, align 8
  store i32 %1, ptr %4, align 4
  %5 = load ptr, ptr %3, align 8
  %6 = load i32, ptr %4, align 4
  %7 = call noundef ptr @_ZN4NodeC2Ei(ptr noundef nonnull align 8 dereferenceable(20) %5, i32 noundef %6)
  ret ptr %5
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZN4NodeC2Ei(ptr noundef nonnull returned align 8 dereferenceable(20) %0, i32 noundef %1) unnamed_addr #6 {
  %3 = alloca ptr, align 8
  %4 = alloca i32, align 4
  store ptr %0, ptr %3, align 8
  store i32 %1, ptr %4, align 4
  %5 = load ptr, ptr %3, align 8
  %6 = getelementptr inbounds nuw %struct.Node, ptr %5, i32 0, i32 0
  %7 = call noundef ptr @_ZNSt3__110shared_ptrI4NodeEC1B9nqe220105EDn(ptr noundef nonnull align 8 dereferenceable(16) %6, ptr null) #13
  %8 = getelementptr inbounds nuw %struct.Node, ptr %5, i32 0, i32 1
  %9 = load i32, ptr %4, align 4
  store i32 %9, ptr %8, align 8
  ret ptr %5
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__110shared_ptrI4NodeEC1B9nqe220105EDn(ptr noundef nonnull returned align 8 dereferenceable(16) %0, ptr %1) unnamed_addr #6 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  %6 = load ptr, ptr %4, align 8
  %7 = call noundef ptr @_ZNSt3__110shared_ptrI4NodeEC2B9nqe220105EDn(ptr noundef nonnull align 8 dereferenceable(16) %5, ptr %6) #13
  ret ptr %5
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__110shared_ptrI4NodeEC2B9nqe220105EDn(ptr noundef nonnull returned align 8 dereferenceable(16) %0, ptr %1) unnamed_addr #6 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  %6 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %5, i32 0, i32 0
  store ptr null, ptr %6, align 8
  %7 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %5, i32 0, i32 1
  store ptr null, ptr %7, align 8
  ret ptr %5
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE8_StorageD2B9nqe220105Ev(ptr noundef nonnull returned align 8 dereferenceable(24) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE8_Storage11__get_allocB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %3) #13
  ret ptr %3
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEED2Ev(ptr noundef nonnull returned align 8 dereferenceable(48) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  store ptr getelementptr inbounds inrange(-16, 40) ({ [7 x ptr] }, ptr @_ZTVNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEEE, i32 0, i32 0, i32 2), ptr %3, align 8
  %4 = getelementptr inbounds nuw %"struct.std::__1::__shared_ptr_emplace", ptr %3, i32 0, i32 1
  %5 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE8_StorageD1B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %4) #13
  %6 = call noundef ptr @_ZNSt3__119__shared_weak_countD2Ev(ptr noundef nonnull align 8 dereferenceable(24) %3) #13
  ret ptr %3
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr void @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE21__on_zero_shared_implB9nqe220105IS3_TnNS_9enable_ifIXntsr7is_sameINT_10value_typeENS_19__for_overwrite_tagEEE5valueEiE4typeELi0EEEvv(ptr noundef nonnull align 8 dereferenceable(48) %0) #6 personality ptr @__gxx_personality_v0 {
  %2 = alloca ptr, align 8
  %3 = alloca %"class.std::__1::allocator", align 1
  store ptr %0, ptr %2, align 8
  %4 = load ptr, ptr %2, align 8
  %5 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE11__get_allocB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(48) %4) #13
  %6 = call noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE10__get_elemB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(48) %4) #13
  invoke void @_ZNSt3__116allocator_traitsINS_9allocatorI4NodeEEE7destroyB9nqe220105IS2_TnNS_9enable_ifIX15__has_destroy_vIS3_PT_EEiE4typeELi0EEEvRS3_S8_(ptr noundef nonnull align 1 dereferenceable(1) %3, ptr noundef %6)
          to label %7 unwind label %8

7:                                                ; preds = %1
  ret void

8:                                                ; preds = %1
  %9 = landingpad { ptr, i32 }
          catch ptr null
  %10 = extractvalue { ptr, i32 } %9, 0
  call void @__clang_call_terminate(ptr %10) #15
  unreachable
}

; Function Attrs: mustprogress noinline optnone ssp uwtable(sync)
define linkonce_odr void @_ZNSt3__116allocator_traitsINS_9allocatorI4NodeEEE7destroyB9nqe220105IS2_TnNS_9enable_ifIX15__has_destroy_vIS3_PT_EEiE4typeELi0EEEvRS3_S8_(ptr noundef nonnull align 1 dereferenceable(1) %0, ptr noundef %1) #0 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8, !nonnull !7
  %6 = load ptr, ptr %4, align 8
  call void @_ZNSt3__19allocatorI4NodeE7destroyB9nqe220105EPS1_(ptr noundef nonnull align 1 dereferenceable(1) %5, ptr noundef %6)
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__19allocatorI4NodeE7destroyB9nqe220105EPS1_(ptr noundef nonnull align 1 dereferenceable(1) %0, ptr noundef %1) #6 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  %6 = load ptr, ptr %4, align 8
  %7 = call noundef ptr @_ZN4NodeD1Ev(ptr noundef nonnull align 8 dereferenceable(20) %6) #13
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZN4NodeD1Ev(ptr noundef nonnull returned align 8 dereferenceable(20) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call noundef ptr @_ZN4NodeD2Ev(ptr noundef nonnull align 8 dereferenceable(20) %3) #13
  ret ptr %3
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr noundef ptr @_ZN4NodeD2Ev(ptr noundef nonnull returned align 8 dereferenceable(20) %0) unnamed_addr #6 personality ptr @__gxx_personality_v0 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = getelementptr inbounds nuw %struct.Node, ptr %3, i32 0, i32 1
  %5 = load i32, ptr %4, align 8
  %6 = invoke i32 (ptr, ...) @printf(ptr noundef @.str.8, i32 noundef %5)
          to label %7 unwind label %10

7:                                                ; preds = %1
  %8 = getelementptr inbounds nuw %struct.Node, ptr %3, i32 0, i32 0
  %9 = call noundef ptr @_ZNSt3__110shared_ptrI4NodeED1B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(16) %8) #13
  ret ptr %3

10:                                               ; preds = %1
  %11 = landingpad { ptr, i32 }
          catch ptr null
  %12 = extractvalue { ptr, i32 } %11, 0
  call void @__clang_call_terminate(ptr %12) #15
  unreachable
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__116allocator_traitsINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEE10deallocateB9nqe220105ERS6_PS5_m(ptr noundef nonnull align 1 dereferenceable(1) %0, ptr noundef %1, i64 noundef %2) #6 {
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  %6 = alloca i64, align 8
  store ptr %0, ptr %4, align 8
  store ptr %1, ptr %5, align 8
  store i64 %2, ptr %6, align 8
  %7 = load ptr, ptr %4, align 8, !nonnull !7
  %8 = load ptr, ptr %5, align 8
  %9 = load i64, ptr %6, align 8
  call void @_ZNSt3__19allocatorINS_20__shared_ptr_emplaceI4NodeNS0_IS2_EEEEE10deallocateB9nqe220105EPS4_m(ptr noundef nonnull align 1 dereferenceable(1) %7, ptr noundef %8, i64 noundef %9) #13
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__114pointer_traitsIPNS_20__shared_ptr_emplaceI4NodeNS_9allocatorIS2_EEEEE10pointer_toB9nqe220105ERS5_(ptr noundef nonnull align 8 dereferenceable(48) %0) #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8, !nonnull !7, !align !9
  ret ptr %3
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__19allocatorINS_20__shared_ptr_emplaceI4NodeNS0_IS2_EEEEE10deallocateB9nqe220105EPS4_m(ptr noundef nonnull align 1 dereferenceable(1) %0, ptr noundef %1, i64 noundef %2) #6 {
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  %6 = alloca i64, align 8
  store ptr %0, ptr %4, align 8
  store ptr %1, ptr %5, align 8
  store i64 %2, ptr %6, align 8
  %7 = load ptr, ptr %4, align 8
  %8 = load ptr, ptr %5, align 8
  %9 = load i64, ptr %6, align 8
  call void @_ZNSt3__119__libcpp_deallocateB9nqe220105INS_20__shared_ptr_emplaceI4NodeNS_9allocatorIS2_EEEEEEvPNS_15__type_identityIT_E4typeENS_15__element_countEm(ptr noundef %8, i64 noundef %9, i64 noundef 8) #13
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__119__libcpp_deallocateB9nqe220105INS_20__shared_ptr_emplaceI4NodeNS_9allocatorIS2_EEEEEEvPNS_15__type_identityIT_E4typeENS_15__element_countEm(ptr noundef %0, i64 noundef %1, i64 noundef %2) #6 {
  %4 = alloca ptr, align 8
  %5 = alloca i64, align 8
  %6 = alloca i64, align 8
  %7 = alloca i64, align 8
  store ptr %0, ptr %4, align 8
  store i64 %1, ptr %5, align 8
  store i64 %2, ptr %6, align 8
  %8 = load i64, ptr %5, align 8
  %9 = mul i64 %8, 48
  store i64 %9, ptr %7, align 8
  %10 = load i64, ptr %6, align 8
  %11 = call noundef zeroext i1 @_ZNSt3__124__is_overaligned_for_newB9nqe220105Em(i64 noundef %10) #13
  br i1 %11, label %12, label %16

12:                                               ; preds = %3
  %13 = load ptr, ptr %4, align 8
  %14 = load i64, ptr %7, align 8
  %15 = load i64, ptr %6, align 8
  call void @_ZdlPvmSt11align_val_t(ptr noundef %13, i64 noundef %14, i64 noundef %15) #12
  br label %19

16:                                               ; preds = %3
  %17 = load ptr, ptr %4, align 8
  %18 = load i64, ptr %7, align 8
  call void @_ZdlPvm(ptr noundef %17, i64 noundef %18) #12
  br label %19

19:                                               ; preds = %16, %12
  ret void
}

; Function Attrs: nobuiltin nounwind
declare void @_ZdlPvmSt11align_val_t(ptr noundef, i64 noundef, i64 noundef) #3

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__110shared_ptrI4NodeEC1B9nqe220105Ev(ptr noundef nonnull returned align 8 dereferenceable(16) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call noundef ptr @_ZNSt3__110shared_ptrI4NodeEC2B9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(16) %3) #13
  ret ptr %3
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__110shared_ptrI4NodeE18__enable_weak_thisB9nqe220105Ez(ptr noundef nonnull align 8 dereferenceable(16) %0, ...) #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__110shared_ptrI4NodeEC2B9nqe220105Ev(ptr noundef nonnull returned align 8 dereferenceable(16) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %3, i32 0, i32 0
  store ptr null, ptr %4, align 8
  %5 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %3, i32 0, i32 1
  store ptr null, ptr %5, align 8
  ret ptr %3
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__120__shared_ptr_emplaceI4NodeNS_9allocatorIS1_EEE8_Storage10__get_elemB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %0) #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = getelementptr inbounds nuw %"struct.std::__1::__shared_ptr_emplace<Node, std::__1::allocator<Node>>::_Storage", ptr %3, i32 0, i32 0
  %5 = getelementptr inbounds [24 x i8], ptr %4, i64 0, i64 0
  %6 = getelementptr inbounds nuw %"struct.std::__1::__shared_ptr_emplace<Node, std::__1::allocator<Node>>::_Storage::_Data", ptr %5, i32 0, i32 0
  %7 = getelementptr inbounds nuw %struct.anon.2, ptr %6, i32 0, i32 0
  ret ptr %7
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__118__allocation_guardINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEED2B9nqe220105Ev(ptr noundef nonnull returned align 8 dereferenceable(24) %0) unnamed_addr #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  call void @_ZNSt3__118__allocation_guardINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEE9__destroyB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %3) #13
  ret ptr %3
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__118__allocation_guardINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEE9__destroyB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %0) #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = getelementptr inbounds nuw %"struct.std::__1::__allocation_guard", ptr %3, i32 0, i32 2
  %5 = load ptr, ptr %4, align 8
  %6 = icmp ne ptr %5, null
  br i1 %6, label %7, label %12

7:                                                ; preds = %1
  %8 = getelementptr inbounds nuw %"struct.std::__1::__allocation_guard", ptr %3, i32 0, i32 2
  %9 = load ptr, ptr %8, align 8
  %10 = getelementptr inbounds nuw %"struct.std::__1::__allocation_guard", ptr %3, i32 0, i32 1
  %11 = load i64, ptr %10, align 8
  call void @_ZNSt3__116allocator_traitsINS_9allocatorINS_20__shared_ptr_emplaceI4NodeNS1_IS3_EEEEEEE10deallocateB9nqe220105ERS6_PS5_m(ptr noundef nonnull align 1 dereferenceable(1) %3, ptr noundef %9, i64 noundef %11) #13
  br label %12

12:                                               ; preds = %7, %1
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__110shared_ptrI4NodeEC1B9nqe220105ERKS2_(ptr noundef nonnull returned align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %1) unnamed_addr #6 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  %6 = load ptr, ptr %4, align 8
  %7 = call noundef ptr @_ZNSt3__110shared_ptrI4NodeEC2B9nqe220105ERKS2_(ptr noundef nonnull align 8 dereferenceable(16) %5, ptr noundef nonnull align 8 dereferenceable(16) %6) #13
  ret ptr %5
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__110shared_ptrI4NodeE4swapB9nqe220105ERS2_(ptr noundef nonnull align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %1) #6 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  %6 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %5, i32 0, i32 0
  %7 = load ptr, ptr %4, align 8, !nonnull !7, !align !9
  %8 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %7, i32 0, i32 0
  call void @_ZNSt3__14swapB9nqe220105IP4NodeEENS_9enable_ifIXaasr21is_move_constructibleIT_EE5valuesr18is_move_assignableIS4_EE5valueEvE4typeERS4_S7_(ptr noundef nonnull align 8 dereferenceable(8) %6, ptr noundef nonnull align 8 dereferenceable(8) %8) #13
  %9 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %5, i32 0, i32 1
  %10 = load ptr, ptr %4, align 8, !nonnull !7, !align !9
  %11 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %10, i32 0, i32 1
  call void @_ZNSt3__14swapB9nqe220105IPNS_19__shared_weak_countEEENS_9enable_ifIXaasr21is_move_constructibleIT_EE5valuesr18is_move_assignableIS4_EE5valueEvE4typeERS4_S7_(ptr noundef nonnull align 8 dereferenceable(8) %9, ptr noundef nonnull align 8 dereferenceable(8) %11) #13
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef ptr @_ZNSt3__110shared_ptrI4NodeEC2B9nqe220105ERKS2_(ptr noundef nonnull returned align 8 dereferenceable(16) %0, ptr noundef nonnull align 8 dereferenceable(16) %1) unnamed_addr #6 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  store ptr %0, ptr %4, align 8
  store ptr %1, ptr %5, align 8
  %6 = load ptr, ptr %4, align 8
  store ptr %6, ptr %3, align 8
  %7 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %6, i32 0, i32 0
  %8 = load ptr, ptr %5, align 8, !nonnull !7, !align !9
  %9 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %8, i32 0, i32 0
  %10 = load ptr, ptr %9, align 8
  store ptr %10, ptr %7, align 8
  %11 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %6, i32 0, i32 1
  %12 = load ptr, ptr %5, align 8, !nonnull !7, !align !9
  %13 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %12, i32 0, i32 1
  %14 = load ptr, ptr %13, align 8
  store ptr %14, ptr %11, align 8
  %15 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %6, i32 0, i32 1
  %16 = load ptr, ptr %15, align 8
  %17 = icmp ne ptr %16, null
  br i1 %17, label %18, label %21

18:                                               ; preds = %2
  %19 = getelementptr inbounds nuw %"class.std::__1::shared_ptr", ptr %6, i32 0, i32 1
  %20 = load ptr, ptr %19, align 8
  call void @_ZNSt3__119__shared_weak_count12__add_sharedB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %20) #13
  br label %21

21:                                               ; preds = %18, %2
  %22 = load ptr, ptr %3, align 8
  ret ptr %22
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__119__shared_weak_count12__add_sharedB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(24) %0) #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  call void @_ZNSt3__114__shared_count12__add_sharedB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(16) %3) #13
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__114__shared_count12__add_sharedB9nqe220105Ev(ptr noundef nonnull align 8 dereferenceable(16) %0) #6 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = getelementptr inbounds nuw %"class.std::__1::__shared_count", ptr %3, i32 0, i32 1
  %5 = call noundef i64 @_ZNSt3__134__libcpp_atomic_refcount_incrementB9nqe220105IlEET_RS1_(ptr noundef nonnull align 8 dereferenceable(8) %4) #13
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden noundef i64 @_ZNSt3__134__libcpp_atomic_refcount_incrementB9nqe220105IlEET_RS1_(ptr noundef nonnull align 8 dereferenceable(8) %0) #6 {
  %2 = alloca ptr, align 8
  %3 = alloca i64, align 8
  %4 = alloca i64, align 8
  store ptr %0, ptr %2, align 8
  %5 = load ptr, ptr %2, align 8, !nonnull !7, !align !9
  store i64 1, ptr %3, align 8
  %6 = load i64, ptr %3, align 8
  %7 = atomicrmw add ptr %5, i64 %6 monotonic, align 8
  %8 = add i64 %7, %6
  store i64 %8, ptr %4, align 8
  %9 = load i64, ptr %4, align 8
  ret i64 %9
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__14swapB9nqe220105IP4NodeEENS_9enable_ifIXaasr21is_move_constructibleIT_EE5valuesr18is_move_assignableIS4_EE5valueEvE4typeERS4_S7_(ptr noundef nonnull align 8 dereferenceable(8) %0, ptr noundef nonnull align 8 dereferenceable(8) %1) #6 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %6 = load ptr, ptr %3, align 8, !nonnull !7, !align !9
  %7 = load ptr, ptr %6, align 8
  store ptr %7, ptr %5, align 8
  %8 = load ptr, ptr %4, align 8, !nonnull !7, !align !9
  %9 = load ptr, ptr %8, align 8
  %10 = load ptr, ptr %3, align 8, !nonnull !7, !align !9
  store ptr %9, ptr %10, align 8
  %11 = load ptr, ptr %5, align 8
  %12 = load ptr, ptr %4, align 8, !nonnull !7, !align !9
  store ptr %11, ptr %12, align 8
  ret void
}

; Function Attrs: mustprogress noinline nounwind optnone ssp uwtable(sync)
define linkonce_odr hidden void @_ZNSt3__14swapB9nqe220105IPNS_19__shared_weak_countEEENS_9enable_ifIXaasr21is_move_constructibleIT_EE5valuesr18is_move_assignableIS4_EE5valueEvE4typeERS4_S7_(ptr noundef nonnull align 8 dereferenceable(8) %0, ptr noundef nonnull align 8 dereferenceable(8) %1) #6 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %6 = load ptr, ptr %3, align 8, !nonnull !7, !align !9
  %7 = load ptr, ptr %6, align 8
  store ptr %7, ptr %5, align 8
  %8 = load ptr, ptr %4, align 8, !nonnull !7, !align !9
  %9 = load ptr, ptr %8, align 8
  %10 = load ptr, ptr %3, align 8, !nonnull !7, !align !9
  store ptr %9, ptr %10, align 8
  %11 = load ptr, ptr %5, align 8
  %12 = load ptr, ptr %4, align 8, !nonnull !7, !align !9
  store ptr %11, ptr %12, align 8
  ret void
}

attributes #0 = { mustprogress noinline optnone ssp uwtable(sync) "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { nobuiltin allocsize(0) "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { nobuiltin nounwind "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #4 = { nounwind "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #5 = { noinline noreturn nounwind ssp uwtable(sync) "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #6 = { mustprogress noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #7 = { nounwind memory(none) }
attributes #8 = { mustprogress noinline norecurse optnone ssp uwtable(sync) "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #9 = { mustprogress noinline noreturn optnone ssp uwtable(sync) "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #10 = { nocallback nofree nosync nounwind willreturn memory(inaccessiblemem: write) }
attributes #11 = { builtin allocsize(0) }
attributes #12 = { builtin nounwind }
attributes #13 = { nounwind }
attributes #14 = { noreturn }
attributes #15 = { noreturn nounwind }

!llvm.module.flags = !{!0, !1, !2, !3}
!llvm.ident = !{!4}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 8, !"PIC Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 1}
!3 = !{i32 7, !"frame-pointer", i32 4}
!4 = !{!"Homebrew clang version 22.1.5"}
!5 = distinct !{!5, !6}
!6 = !{!"llvm.loop.mustprogress"}
!7 = !{}
!8 = !{i64 4}
!9 = !{i64 8}
