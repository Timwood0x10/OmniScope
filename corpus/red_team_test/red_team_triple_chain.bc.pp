; ModuleID = '/Users/scc/code/zigcode/OmniScope/corpus/red_team_test/red_team_triple_chain.c'
source_filename = "/Users/scc/code/zigcode/OmniScope/corpus/red_team_test/red_team_triple_chain.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

%struct.GoSlice = type { ptr, i32, i32 }

@.str = private unnamed_addr constant [40 x i8] c"\0A=== CHAIN-01: Go alloc \E2\86\92 C free ===\0A\00", align 1
@.str.1 = private unnamed_addr constant [16 x i8] c"Go-managed data\00", align 1
@.str.2 = private unnamed_addr constant [41 x i8] c"\0A=== CHAIN-02: Rust Box \E2\86\92 Go free ===\0A\00", align 1
@.str.3 = private unnamed_addr constant [20 x i8] c"Rust-owned Box data\00", align 1
@.str.4 = private unnamed_addr constant [26 x i8] c"[Go] Received from C: %p\0A\00", align 1
@.str.5 = private unnamed_addr constant [32 x i8] c"[C] Received Rust &mut ref: %p\0A\00", align 1
@g_c_stored_rust_ref = internal global ptr null, align 8
@.str.6 = private unnamed_addr constant [47 x i8] c"\0A=== CHAIN-03: Rust &mut ref \E2\86\92 C stores ===\0A\00", align 1
@.str.7 = private unnamed_addr constant [22 x i8] c"Rust mutable ref data\00", align 1
@.str.8 = private unnamed_addr constant [24 x i8] c"[Rust] Still using: %s\0A\00", align 1
@.str.9 = private unnamed_addr constant [14 x i8] c"C wrote this!\00", align 1
@.str.10 = private unnamed_addr constant [38 x i8] c"[Rust] Data changed unexpectedly: %s\0A\00", align 1
@.str.11 = private unnamed_addr constant [54 x i8] c"\0A=== CHAIN-04: Ownership lost across 3 languages ===\0A\00", align 1
@.str.12 = private unnamed_addr constant [21 x i8] c"Ownership chain data\00", align 1
@.str.13 = private unnamed_addr constant [21 x i8] c"[Rust] Received: %p\0A\00", align 1
@.str.14 = private unnamed_addr constant [65 x i8] c"[CHAIN-04] Memory at %p leaked \E2\80\94 no language claims ownership\0A\00", align 1
@.str.15 = private unnamed_addr constant [51 x i8] c"\0A=== CHAIN-05: Dangling pointer through chain ===\0A\00", align 1
@.str.16 = private unnamed_addr constant [22 x i8] c"data that will dangle\00", align 1
@.str.17 = private unnamed_addr constant [23 x i8] c"[C] C still holds: %s\0A\00", align 1
@.str.18 = private unnamed_addr constant [25 x i8] c"[Go] Go still holds: %s\0A\00", align 1
@.str.19 = private unnamed_addr constant [47 x i8] c"\0A=== CHAIN-06: Double free in Go and Rust ===\0A\00", align 1
@.str.20 = private unnamed_addr constant [22 x i8] c"shared ownership data\00", align 1
@.str.21 = private unnamed_addr constant [19 x i8] c"[C] Allocated: %p\0A\00", align 1
@.str.22 = private unnamed_addr constant [36 x i8] c"[Go] Got pointer from C path 1: %p\0A\00", align 1
@.str.23 = private unnamed_addr constant [38 x i8] c"[Rust] Got pointer from C path 2: %p\0A\00", align 1
@.str.24 = private unnamed_addr constant [15 x i8] c"[Go] Freed %p\0A\00", align 1
@.str.25 = private unnamed_addr constant [38 x i8] c"[Rust] Also freed %p \E2\80\94 DOUBLE FREE\0A\00", align 1
@g_race_running = internal global i32 1, align 4
@g_shared_race_buffer = internal global ptr null, align 8
@.str.26 = private unnamed_addr constant [24 x i8] c"[Rust thread] read: %d\0A\00", align 1
@.str.27 = private unnamed_addr constant [48 x i8] c"\0A=== CHAIN-07: Data race Go \E2\86\94 Rust via C ===\0A\00", align 1
@.str.28 = private unnamed_addr constant [54 x i8] c"\0A=== CHAIN-08: Full Go\E2\86\92C\E2\86\92Rust\E2\86\92C\E2\86\92Go chain ===\0A\00", align 1
@.str.29 = private unnamed_addr constant [26 x i8] c"Go data through the chain\00", align 1
@.str.30 = private unnamed_addr constant [20 x i8] c"[Go] Allocated: %p\0A\00", align 1
@.str.31 = private unnamed_addr constant [26 x i8] c"[C] Received from Go: %p\0A\00", align 1
@g_rust_kept_copy = internal global ptr null, align 8
@.str.32 = private unnamed_addr constant [40 x i8] c"[Rust] Processing, but kept copy at %p\0A\00", align 1
@.str.33 = private unnamed_addr constant [21 x i8] c"[C] Rust result: %d\0A\00", align 1
@.str.34 = private unnamed_addr constant [12 x i8] c"C modified!\00", align 1
@.str.35 = private unnamed_addr constant [23 x i8] c"[C] Modified data: %s\0A\00", align 1
@.str.36 = private unnamed_addr constant [19 x i8] c"[Go] Got back: %s\0A\00", align 1
@.str.37 = private unnamed_addr constant [37 x i8] c"[Rust] Trying to read kept copy: %s\0A\00", align 1
@.str.38 = private unnamed_addr constant [182 x i8] c"\E2\95\94\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\97\0A\00", align 1
@.str.39 = private unnamed_addr constant [68 x i8] c"\E2\95\91  OmniScope Red Team \E2\80\94 Triple Language Chain Test Suite   \E2\95\91\0A\00", align 1
@.str.40 = private unnamed_addr constant [69 x i8] c"\E2\95\91  Go \E2\86\94 C \E2\86\94 Rust boundary bugs                            \E2\95\91\0A\00", align 1
@.str.41 = private unnamed_addr constant [182 x i8] c"\E2\95\9A\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\9D\0A\00", align 1
@.str.42 = private unnamed_addr constant [177 x i8] c"\0A\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\0A\00", align 1
@.str.43 = private unnamed_addr constant [57 x i8] c"All chain tests completed. Expected OmniScope findings:\0A\00", align 1
@.str.44 = private unnamed_addr constant [27 x i8] c"  - 4 cross_language_free\0A\00", align 1
@.str.45 = private unnamed_addr constant [21 x i8] c"  - 2 borrow_escape\0A\00", align 1
@.str.46 = private unnamed_addr constant [22 x i8] c"  - 3 use_after_free\0A\00", align 1
@.str.47 = private unnamed_addr constant [19 x i8] c"  - 1 memory_leak\0A\00", align 1
@.str.48 = private unnamed_addr constant [17 x i8] c"  - 1 data_race\0A\00", align 1
@.str.49 = private unnamed_addr constant [19 x i8] c"  - 1 double_free\0A\00", align 1
@.str.50 = private unnamed_addr constant [39 x i8] c"Total: ~12 issues across 8 test cases\0A\00", align 1
@.str.51 = private unnamed_addr constant [176 x i8] c"\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\E2\95\90\0A\00", align 1
@.str.52 = private unnamed_addr constant [31 x i8] c"[Go] runtime.alloc(%d) \E2\86\92 %p\0A\00", align 1
@.str.53 = private unnamed_addr constant [40 x i8] c"[C] Received Go slice: data=%p, len=%d\0A\00", align 1
@.str.54 = private unnamed_addr constant [23 x i8] c"[C] Rust returned: %d\0A\00", align 1
@.str.55 = private unnamed_addr constant [20 x i8] c"[Go] GC collect %p\0A\00", align 1
@.str.56 = private unnamed_addr constant [34 x i8] c"[C] Forwarding Rust ptr %p to Go\0A\00", align 1
@.str.57 = private unnamed_addr constant [23 x i8] c"[Rust] Drop::drop(%p)\0A\00", align 1
@.str.58 = private unnamed_addr constant [32 x i8] c"[Rust] __rust_alloc(%d) \E2\86\92 %p\0A\00", align 1
@.str.59 = private unnamed_addr constant [31 x i8] c"[Rust] __rust_dealloc(%p, %d)\0A\00", align 1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @chain_01_go_alloc_c_free() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca %struct.GoSlice, align 8
  %3 = call i32 (ptr, ...) @printf(ptr noundef @.str)
  %4 = call ptr @go_alloc(i32 noundef 256)
  store ptr %4, ptr %1, align 8
  %5 = load ptr, ptr %1, align 8
  %6 = load ptr, ptr %1, align 8
  %7 = call i64 @llvm.objectsize.i64.p0(ptr %6, i1 false, i1 true, i1 false)
  %8 = call ptr @__strcpy_chk(ptr noundef %5, ptr noundef @.str.1, i64 noundef %7) #5
  %9 = getelementptr inbounds nuw %struct.GoSlice, ptr %2, i32 0, i32 0
  %10 = load ptr, ptr %1, align 8
  store ptr %10, ptr %9, align 8
  %11 = getelementptr inbounds nuw %struct.GoSlice, ptr %2, i32 0, i32 1
  store i32 15, ptr %11, align 8
  %12 = getelementptr inbounds nuw %struct.GoSlice, ptr %2, i32 0, i32 2
  store i32 256, ptr %12, align 4
  %13 = load [2 x i64], ptr %2, align 8
  %14 = call i32 @c_bridge_process_go_data([2 x i64] %13)
  %15 = load ptr, ptr %1, align 8
  call void @free(ptr noundef %15)
  %16 = load ptr, ptr %1, align 8
  call void @go_free(ptr noundef %16)
  ret void
}

declare i32 @printf(ptr noundef, ...) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define internal ptr @go_alloc(i32 noundef %0) #0 {
  %2 = alloca i32, align 4
  %3 = alloca ptr, align 8
  store i32 %0, ptr %2, align 4
  %4 = load i32, ptr %2, align 4
  %5 = sext i32 %4 to i64
  %6 = call ptr @malloc(i64 noundef %5) #6
  store ptr %6, ptr %3, align 8
  %7 = load i32, ptr %2, align 4
  %8 = load ptr, ptr %3, align 8
  %9 = call i32 (ptr, ...) @printf(ptr noundef @.str.52, i32 noundef %7, ptr noundef %8)
  %10 = load ptr, ptr %3, align 8
  ret ptr %10
}

; Function Attrs: nounwind
declare ptr @__strcpy_chk(ptr noundef, ptr noundef, i64 noundef) #2

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.objectsize.i64.p0(ptr, i1 immarg, i1 immarg, i1 immarg) #3

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define internal i32 @c_bridge_process_go_data([2 x i64] %0) #0 {
  %2 = alloca %struct.GoSlice, align 8
  %3 = alloca i32, align 4
  store [2 x i64] %0, ptr %2, align 8
  %4 = getelementptr inbounds nuw %struct.GoSlice, ptr %2, i32 0, i32 0
  %5 = load ptr, ptr %4, align 8
  %6 = getelementptr inbounds nuw %struct.GoSlice, ptr %2, i32 0, i32 1
  %7 = load i32, ptr %6, align 8
  %8 = call i32 (ptr, ...) @printf(ptr noundef @.str.53, ptr noundef %5, i32 noundef %7)
  %9 = getelementptr inbounds nuw %struct.GoSlice, ptr %2, i32 0, i32 1
  %10 = load i32, ptr %9, align 8
  store i32 %10, ptr %3, align 4
  %11 = load i32, ptr %3, align 4
  %12 = call i32 (ptr, ...) @printf(ptr noundef @.str.54, i32 noundef %11)
  %13 = load i32, ptr %3, align 4
  ret i32 %13
}

declare void @free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define internal void @go_free(ptr noundef %0) #0 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call i32 (ptr, ...) @printf(ptr noundef @.str.55, ptr noundef %3)
  %5 = load ptr, ptr %2, align 8
  call void @free(ptr noundef %5)
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @chain_02_rust_alloc_go_free() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca ptr, align 8
  %3 = call i32 (ptr, ...) @printf(ptr noundef @.str.2)
  %4 = call ptr @rust_box_new(i32 noundef 128)
  store ptr %4, ptr %1, align 8
  %5 = load ptr, ptr %1, align 8
  %6 = load ptr, ptr %1, align 8
  %7 = call i64 @llvm.objectsize.i64.p0(ptr %6, i1 false, i1 true, i1 false)
  %8 = call ptr @__strcpy_chk(ptr noundef %5, ptr noundef @.str.3, i64 noundef %7) #5
  %9 = load ptr, ptr %1, align 8
  %10 = call ptr @c_bridge_pass_rust_to_go(ptr noundef %9)
  store ptr %10, ptr %2, align 8
  %11 = load ptr, ptr %2, align 8
  %12 = call i32 (ptr, ...) @printf(ptr noundef @.str.4, ptr noundef %11)
  %13 = load ptr, ptr %2, align 8
  call void @go_free(ptr noundef %13)
  %14 = load ptr, ptr %1, align 8
  call void @rust_box_drop(ptr noundef %14, i32 noundef 128)
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define internal ptr @rust_box_new(i32 noundef %0) #0 {
  %2 = alloca i32, align 4
  store i32 %0, ptr %2, align 4
  %3 = load i32, ptr %2, align 4
  %4 = call ptr @rust_alloc(i32 noundef %3)
  ret ptr %4
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define internal ptr @c_bridge_pass_rust_to_go(ptr noundef %0) #0 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call i32 (ptr, ...) @printf(ptr noundef @.str.56, ptr noundef %3)
  %5 = load ptr, ptr %2, align 8
  ret ptr %5
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define internal void @rust_box_drop(ptr noundef %0, i32 noundef %1) #0 {
  %3 = alloca ptr, align 8
  %4 = alloca i32, align 4
  store ptr %0, ptr %3, align 8
  store i32 %1, ptr %4, align 4
  %5 = load ptr, ptr %3, align 8
  %6 = call i32 (ptr, ...) @printf(ptr noundef @.str.57, ptr noundef %5)
  %7 = load ptr, ptr %3, align 8
  %8 = load i32, ptr %4, align 4
  call void @rust_dealloc(ptr noundef %7, i32 noundef %8)
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @c_takes_rust_ref(ptr noundef %0) #0 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = call i32 (ptr, ...) @printf(ptr noundef @.str.5, ptr noundef %3)
  %5 = load ptr, ptr %2, align 8
  store ptr %5, ptr @g_c_stored_rust_ref, align 8
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @chain_03_rust_ref_escape() #0 {
  %1 = alloca ptr, align 8
  %2 = call i32 (ptr, ...) @printf(ptr noundef @.str.6)
  %3 = call ptr @rust_alloc(i32 noundef 64)
  store ptr %3, ptr %1, align 8
  %4 = load ptr, ptr %1, align 8
  %5 = load ptr, ptr %1, align 8
  %6 = call i64 @llvm.objectsize.i64.p0(ptr %5, i1 false, i1 true, i1 false)
  %7 = call ptr @__strcpy_chk(ptr noundef %4, ptr noundef @.str.7, i64 noundef %6) #5
  %8 = load ptr, ptr %1, align 8
  call void @c_takes_rust_ref(ptr noundef %8)
  %9 = load ptr, ptr %1, align 8
  %10 = call i32 (ptr, ...) @printf(ptr noundef @.str.8, ptr noundef %9)
  %11 = load ptr, ptr @g_c_stored_rust_ref, align 8
  %12 = load ptr, ptr @g_c_stored_rust_ref, align 8
  %13 = call i64 @llvm.objectsize.i64.p0(ptr %12, i1 false, i1 true, i1 false)
  %14 = call ptr @__strcpy_chk(ptr noundef %11, ptr noundef @.str.9, i64 noundef %13) #5
  %15 = load ptr, ptr %1, align 8
  %16 = call i32 (ptr, ...) @printf(ptr noundef @.str.10, ptr noundef %15)
  %17 = load ptr, ptr %1, align 8
  call void @rust_dealloc(ptr noundef %17, i32 noundef 64)
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define internal ptr @rust_alloc(i32 noundef %0) #0 {
  %2 = alloca i32, align 4
  %3 = alloca ptr, align 8
  store i32 %0, ptr %2, align 4
  %4 = load i32, ptr %2, align 4
  %5 = sext i32 %4 to i64
  %6 = call ptr @malloc(i64 noundef %5) #6
  store ptr %6, ptr %3, align 8
  %7 = load i32, ptr %2, align 4
  %8 = load ptr, ptr %3, align 8
  %9 = call i32 (ptr, ...) @printf(ptr noundef @.str.58, i32 noundef %7, ptr noundef %8)
  %10 = load ptr, ptr %3, align 8
  ret ptr %10
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define internal void @rust_dealloc(ptr noundef %0, i32 noundef %1) #0 {
  %3 = alloca ptr, align 8
  %4 = alloca i32, align 4
  store ptr %0, ptr %3, align 8
  store i32 %1, ptr %4, align 4
  %5 = load ptr, ptr %3, align 8
  %6 = load i32, ptr %4, align 4
  %7 = call i32 (ptr, ...) @printf(ptr noundef @.str.59, ptr noundef %5, i32 noundef %6)
  %8 = load ptr, ptr %3, align 8
  call void @free(ptr noundef %8)
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @chain_04_ownership_lost() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca %struct.GoSlice, align 8
  %3 = alloca ptr, align 8
  %4 = call i32 (ptr, ...) @printf(ptr noundef @.str.11)
  %5 = call ptr @go_alloc(i32 noundef 512)
  store ptr %5, ptr %1, align 8
  %6 = load ptr, ptr %1, align 8
  %7 = load ptr, ptr %1, align 8
  %8 = call i64 @llvm.objectsize.i64.p0(ptr %7, i1 false, i1 true, i1 false)
  %9 = call ptr @__strcpy_chk(ptr noundef %6, ptr noundef @.str.12, i64 noundef %8) #5
  %10 = getelementptr inbounds nuw %struct.GoSlice, ptr %2, i32 0, i32 0
  %11 = load ptr, ptr %1, align 8
  store ptr %11, ptr %10, align 8
  %12 = getelementptr inbounds nuw %struct.GoSlice, ptr %2, i32 0, i32 1
  store i32 18, ptr %12, align 8
  %13 = getelementptr inbounds nuw %struct.GoSlice, ptr %2, i32 0, i32 2
  store i32 512, ptr %13, align 4
  %14 = load [2 x i64], ptr %2, align 8
  %15 = call i32 @c_bridge_process_go_data([2 x i64] %14)
  %16 = load ptr, ptr %1, align 8
  %17 = call ptr @c_bridge_pass_rust_to_go(ptr noundef %16)
  store ptr %17, ptr %3, align 8
  %18 = load ptr, ptr %3, align 8
  %19 = call i32 (ptr, ...) @printf(ptr noundef @.str.13, ptr noundef %18)
  %20 = load ptr, ptr %1, align 8
  %21 = call i32 (ptr, ...) @printf(ptr noundef @.str.14, ptr noundef %20)
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @chain_05_dangling_through_chain() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca ptr, align 8
  %3 = alloca ptr, align 8
  %4 = call i32 (ptr, ...) @printf(ptr noundef @.str.15)
  %5 = call ptr @rust_alloc(i32 noundef 128)
  store ptr %5, ptr %1, align 8
  %6 = load ptr, ptr %1, align 8
  %7 = load ptr, ptr %1, align 8
  %8 = call i64 @llvm.objectsize.i64.p0(ptr %7, i1 false, i1 true, i1 false)
  %9 = call ptr @__strcpy_chk(ptr noundef %6, ptr noundef @.str.16, i64 noundef %8) #5
  %10 = load ptr, ptr %1, align 8
  %11 = call ptr @c_bridge_pass_rust_to_go(ptr noundef %10)
  store ptr %11, ptr %2, align 8
  %12 = load ptr, ptr %2, align 8
  store ptr %12, ptr %3, align 8
  %13 = load ptr, ptr %1, align 8
  call void @rust_box_drop(ptr noundef %13, i32 noundef 128)
  %14 = load ptr, ptr %2, align 8
  %15 = call i32 (ptr, ...) @printf(ptr noundef @.str.17, ptr noundef %14)
  %16 = load ptr, ptr %3, align 8
  %17 = call i32 (ptr, ...) @printf(ptr noundef @.str.18, ptr noundef %16)
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @chain_06_double_free_two_langs() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca ptr, align 8
  %3 = alloca ptr, align 8
  %4 = call i32 (ptr, ...) @printf(ptr noundef @.str.19)
  %5 = call ptr @malloc(i64 noundef 128) #6
  store ptr %5, ptr %1, align 8
  %6 = load ptr, ptr %1, align 8
  %7 = load ptr, ptr %1, align 8
  %8 = call i64 @llvm.objectsize.i64.p0(ptr %7, i1 false, i1 true, i1 false)
  %9 = call ptr @__strcpy_chk(ptr noundef %6, ptr noundef @.str.20, i64 noundef %8) #5
  %10 = load ptr, ptr %1, align 8
  %11 = call i32 (ptr, ...) @printf(ptr noundef @.str.21, ptr noundef %10)
  %12 = load ptr, ptr %1, align 8
  store ptr %12, ptr %2, align 8
  %13 = load ptr, ptr %2, align 8
  %14 = call i32 (ptr, ...) @printf(ptr noundef @.str.22, ptr noundef %13)
  %15 = load ptr, ptr %1, align 8
  %16 = call ptr @c_bridge_pass_rust_to_go(ptr noundef %15)
  store ptr %16, ptr %3, align 8
  %17 = load ptr, ptr %3, align 8
  %18 = call i32 (ptr, ...) @printf(ptr noundef @.str.23, ptr noundef %17)
  %19 = load ptr, ptr %2, align 8
  call void @go_free(ptr noundef %19)
  %20 = load ptr, ptr %2, align 8
  %21 = call i32 (ptr, ...) @printf(ptr noundef @.str.24, ptr noundef %20)
  %22 = load ptr, ptr %3, align 8
  call void @rust_dealloc(ptr noundef %22, i32 noundef 128)
  %23 = load ptr, ptr %3, align 8
  %24 = call i32 (ptr, ...) @printf(ptr noundef @.str.25, ptr noundef %23)
  ret void
}

; Function Attrs: allocsize(0)
declare ptr @malloc(i64 noundef) #4

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define ptr @rust_thread_func(ptr noundef %0) #0 {
  %2 = alloca ptr, align 8
  %3 = alloca i32, align 4
  %4 = alloca i32, align 4
  store ptr %0, ptr %2, align 8
  store i32 0, ptr %3, align 4
  br label %5

5:                                                ; preds = %19, %1
  %6 = load i32, ptr %3, align 4
  %7 = icmp slt i32 %6, 100
  br i1 %7, label %8, label %11

8:                                                ; preds = %5
  %9 = load i32, ptr @g_race_running, align 4
  %10 = icmp ne i32 %9, 0
  br label %11

11:                                               ; preds = %8, %5
  %12 = phi i1 [ false, %5 ], [ %10, %8 ]
  br i1 %12, label %13, label %22

13:                                               ; preds = %11
  %14 = load ptr, ptr @g_shared_race_buffer, align 8
  %15 = getelementptr inbounds i32, ptr %14, i64 0
  %16 = load i32, ptr %15, align 4
  store i32 %16, ptr %4, align 4
  %17 = load i32, ptr %4, align 4
  %18 = call i32 (ptr, ...) @printf(ptr noundef @.str.26, i32 noundef %17)
  br label %19

19:                                               ; preds = %13
  %20 = load i32, ptr %3, align 4
  %21 = add nsw i32 %20, 1
  store i32 %21, ptr %3, align 4
  br label %5, !llvm.loop !5

22:                                               ; preds = %11
  ret ptr null
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @chain_07_data_race() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca i32, align 4
  %3 = call i32 (ptr, ...) @printf(ptr noundef @.str.27)
  %4 = call ptr @malloc(i64 noundef 40) #6
  store ptr %4, ptr @g_shared_race_buffer, align 8
  %5 = load ptr, ptr @g_shared_race_buffer, align 8
  %6 = getelementptr inbounds i32, ptr %5, i64 0
  store i32 0, ptr %6, align 4
  %7 = call i32 @pthread_create(ptr noundef %1, ptr noundef null, ptr noundef @rust_thread_func, ptr noundef null)
  store i32 0, ptr %2, align 4
  br label %8

8:                                                ; preds = %15, %0
  %9 = load i32, ptr %2, align 4
  %10 = icmp slt i32 %9, 100
  br i1 %10, label %11, label %18

11:                                               ; preds = %8
  %12 = load i32, ptr %2, align 4
  %13 = load ptr, ptr @g_shared_race_buffer, align 8
  %14 = getelementptr inbounds i32, ptr %13, i64 0
  store i32 %12, ptr %14, align 4
  br label %15

15:                                               ; preds = %11
  %16 = load i32, ptr %2, align 4
  %17 = add nsw i32 %16, 1
  store i32 %17, ptr %2, align 4
  br label %8, !llvm.loop !7

18:                                               ; preds = %8
  store i32 0, ptr @g_race_running, align 4
  %19 = load ptr, ptr %1, align 8
  %20 = call i32 @"\01_pthread_join"(ptr noundef %19, ptr noundef null)
  %21 = load ptr, ptr @g_shared_race_buffer, align 8
  call void @free(ptr noundef %21)
  ret void
}

declare i32 @pthread_create(ptr noundef, ptr noundef, ptr noundef, ptr noundef) #1

declare i32 @"\01_pthread_join"(ptr noundef, ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define void @chain_08_full_chain_triple_bug() #0 {
  %1 = alloca ptr, align 8
  %2 = alloca %struct.GoSlice, align 8
  %3 = alloca i32, align 4
  %4 = call i32 (ptr, ...) @printf(ptr noundef @.str.28)
  %5 = call ptr @go_alloc(i32 noundef 256)
  store ptr %5, ptr %1, align 8
  %6 = load ptr, ptr %1, align 8
  %7 = load ptr, ptr %1, align 8
  %8 = call i64 @llvm.objectsize.i64.p0(ptr %7, i1 false, i1 true, i1 false)
  %9 = call ptr @__strcpy_chk(ptr noundef %6, ptr noundef @.str.29, i64 noundef %8) #5
  %10 = load ptr, ptr %1, align 8
  %11 = call i32 (ptr, ...) @printf(ptr noundef @.str.30, ptr noundef %10)
  %12 = getelementptr inbounds nuw %struct.GoSlice, ptr %2, i32 0, i32 0
  %13 = load ptr, ptr %1, align 8
  store ptr %13, ptr %12, align 8
  %14 = getelementptr inbounds nuw %struct.GoSlice, ptr %2, i32 0, i32 1
  store i32 25, ptr %14, align 8
  %15 = getelementptr inbounds nuw %struct.GoSlice, ptr %2, i32 0, i32 2
  store i32 256, ptr %15, align 4
  %16 = load [2 x i64], ptr %2, align 8
  %17 = call i32 @c_bridge_process_go_data([2 x i64] %16)
  %18 = load ptr, ptr %1, align 8
  %19 = call i32 (ptr, ...) @printf(ptr noundef @.str.31, ptr noundef %18)
  %20 = load ptr, ptr %1, align 8
  store ptr %20, ptr @g_rust_kept_copy, align 8
  %21 = load ptr, ptr @g_rust_kept_copy, align 8
  %22 = call i32 (ptr, ...) @printf(ptr noundef @.str.32, ptr noundef %21)
  store i32 42, ptr %3, align 4
  %23 = load i32, ptr %3, align 4
  %24 = call i32 (ptr, ...) @printf(ptr noundef @.str.33, i32 noundef %23)
  %25 = load ptr, ptr %1, align 8
  %26 = load ptr, ptr %1, align 8
  %27 = call i64 @llvm.objectsize.i64.p0(ptr %26, i1 false, i1 true, i1 false)
  %28 = call ptr @__strcpy_chk(ptr noundef %25, ptr noundef @.str.34, i64 noundef %27) #5
  %29 = load ptr, ptr %1, align 8
  %30 = call i32 (ptr, ...) @printf(ptr noundef @.str.35, ptr noundef %29)
  %31 = load ptr, ptr %1, align 8
  %32 = call i32 (ptr, ...) @printf(ptr noundef @.str.36, ptr noundef %31)
  %33 = load ptr, ptr %1, align 8
  call void @go_free(ptr noundef %33)
  %34 = load ptr, ptr @g_rust_kept_copy, align 8
  %35 = call i32 (ptr, ...) @printf(ptr noundef @.str.37, ptr noundef %34)
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @main() #0 {
  %1 = alloca i32, align 4
  store i32 0, ptr %1, align 4
  %2 = call i32 (ptr, ...) @printf(ptr noundef @.str.38)
  %3 = call i32 (ptr, ...) @printf(ptr noundef @.str.39)
  %4 = call i32 (ptr, ...) @printf(ptr noundef @.str.40)
  %5 = call i32 (ptr, ...) @printf(ptr noundef @.str.41)
  call void @chain_01_go_alloc_c_free()
  call void @chain_02_rust_alloc_go_free()
  call void @chain_03_rust_ref_escape()
  call void @chain_04_ownership_lost()
  call void @chain_05_dangling_through_chain()
  call void @chain_06_double_free_two_langs()
  call void @chain_07_data_race()
  call void @chain_08_full_chain_triple_bug()
  %6 = call i32 (ptr, ...) @printf(ptr noundef @.str.42)
  %7 = call i32 (ptr, ...) @printf(ptr noundef @.str.43)
  %8 = call i32 (ptr, ...) @printf(ptr noundef @.str.44)
  %9 = call i32 (ptr, ...) @printf(ptr noundef @.str.45)
  %10 = call i32 (ptr, ...) @printf(ptr noundef @.str.46)
  %11 = call i32 (ptr, ...) @printf(ptr noundef @.str.47)
  %12 = call i32 (ptr, ...) @printf(ptr noundef @.str.48)
  %13 = call i32 (ptr, ...) @printf(ptr noundef @.str.49)
  %14 = call i32 (ptr, ...) @printf(ptr noundef @.str.50)
  %15 = call i32 (ptr, ...) @printf(ptr noundef @.str.51)
  ret i32 0
}

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { nounwind "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #4 = { allocsize(0) "frame-pointer"="non-leaf-no-reserve" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #5 = { nounwind }
attributes #6 = { allocsize(0) }

!llvm.module.flags = !{!0, !1, !2, !3}
!llvm.ident = !{!4}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 8, !"PIC Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 1}
!3 = !{i32 7, !"frame-pointer", i32 4}
!4 = !{!"Homebrew clang version 22.1.5"}
!5 = distinct !{!5, !6}
!6 = !{!"llvm.loop.mustprogress"}
!7 = distinct !{!7, !6}
