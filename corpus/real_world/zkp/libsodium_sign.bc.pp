; ModuleID = 'src/libsodium/crypto_sign/ed25519/sign_ed25519.c'
source_filename = "src/libsodium/crypto_sign/ed25519/sign_ed25519.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

%struct.crypto_sign_ed25519ph_state = type { %struct.crypto_hash_sha512_state }
%struct.crypto_hash_sha512_state = type { [8 x i64], [2 x i64], [128 x i8] }

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i64 @crypto_sign_ed25519ph_statebytes() #0 {
  ret i64 208
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i64 @crypto_sign_ed25519_bytes() #0 {
  ret i64 64
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i64 @crypto_sign_ed25519_seedbytes() #0 {
  ret i64 32
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i64 @crypto_sign_ed25519_publickeybytes() #0 {
  ret i64 32
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i64 @crypto_sign_ed25519_secretkeybytes() #0 {
  ret i64 64
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i64 @crypto_sign_ed25519_messagebytes_max() #0 {
  ret i64 -65
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @crypto_sign_ed25519_sk_to_seed(ptr noundef nonnull %0, ptr noundef nonnull %1) #0 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  %6 = load ptr, ptr %4, align 8
  %7 = load ptr, ptr %3, align 8
  %8 = call i64 @llvm.objectsize.i64.p0(ptr %7, i1 false, i1 true, i1 false)
  %9 = call ptr @__memmove_chk(ptr noundef %5, ptr noundef %6, i64 noundef 32, i64 noundef %8) #4
  ret i32 0
}

; Function Attrs: nounwind
declare ptr @__memmove_chk(ptr noundef, ptr noundef, i64 noundef, i64 noundef) #1

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.objectsize.i64.p0(ptr, i1 immarg, i1 immarg, i1 immarg) #2

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @crypto_sign_ed25519_sk_to_pk(ptr noundef nonnull %0, ptr noundef nonnull %1) #0 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  store ptr %0, ptr %3, align 8
  store ptr %1, ptr %4, align 8
  %5 = load ptr, ptr %3, align 8
  %6 = load ptr, ptr %4, align 8
  %7 = getelementptr inbounds nuw i8, ptr %6, i64 32
  %8 = load ptr, ptr %3, align 8
  %9 = call i64 @llvm.objectsize.i64.p0(ptr %8, i1 false, i1 true, i1 false)
  %10 = call ptr @__memmove_chk(ptr noundef %5, ptr noundef %7, i64 noundef 32, i64 noundef %9) #4
  ret i32 0
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @crypto_sign_ed25519ph_init(ptr noundef nonnull %0) #0 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = load ptr, ptr %2, align 8
  %4 = getelementptr inbounds nuw %struct.crypto_sign_ed25519ph_state, ptr %3, i32 0, i32 0
  %5 = call i32 @crypto_hash_sha512_init(ptr noundef %4)
  ret i32 0
}

declare i32 @crypto_hash_sha512_init(ptr noundef) #3

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @crypto_sign_ed25519ph_update(ptr noundef nonnull %0, ptr noundef %1, i64 noundef %2) #0 {
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  %6 = alloca i64, align 8
  store ptr %0, ptr %4, align 8
  store ptr %1, ptr %5, align 8
  store i64 %2, ptr %6, align 8
  %7 = load ptr, ptr %4, align 8
  %8 = getelementptr inbounds nuw %struct.crypto_sign_ed25519ph_state, ptr %7, i32 0, i32 0
  %9 = load ptr, ptr %5, align 8
  %10 = load i64, ptr %6, align 8
  %11 = call i32 @crypto_hash_sha512_update(ptr noundef %8, ptr noundef %9, i64 noundef %10)
  ret i32 %11
}

declare i32 @crypto_hash_sha512_update(ptr noundef, ptr noundef, i64 noundef) #3

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @crypto_sign_ed25519ph_final_create(ptr noundef nonnull %0, ptr noundef nonnull %1, ptr noundef %2, ptr noundef nonnull %3) #0 {
  %5 = alloca ptr, align 8
  %6 = alloca ptr, align 8
  %7 = alloca ptr, align 8
  %8 = alloca ptr, align 8
  %9 = alloca [64 x i8], align 1
  store ptr %0, ptr %5, align 8
  store ptr %1, ptr %6, align 8
  store ptr %2, ptr %7, align 8
  store ptr %3, ptr %8, align 8
  %10 = load ptr, ptr %5, align 8
  %11 = getelementptr inbounds nuw %struct.crypto_sign_ed25519ph_state, ptr %10, i32 0, i32 0
  %12 = getelementptr inbounds [64 x i8], ptr %9, i64 0, i64 0
  %13 = call i32 @crypto_hash_sha512_final(ptr noundef %11, ptr noundef %12)
  %14 = load ptr, ptr %6, align 8
  %15 = load ptr, ptr %7, align 8
  %16 = getelementptr inbounds [64 x i8], ptr %9, i64 0, i64 0
  %17 = load ptr, ptr %8, align 8
  %18 = call i32 @_crypto_sign_ed25519_detached(ptr noundef %14, ptr noundef %15, ptr noundef %16, i64 noundef 64, ptr noundef %17, i32 noundef 1)
  ret i32 %18
}

declare i32 @crypto_hash_sha512_final(ptr noundef, ptr noundef) #3

declare i32 @_crypto_sign_ed25519_detached(ptr noundef, ptr noundef, ptr noundef, i64 noundef, ptr noundef, i32 noundef) #3

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @crypto_sign_ed25519ph_final_verify(ptr noundef nonnull %0, ptr noundef nonnull %1, ptr noundef nonnull %2) #0 {
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  %6 = alloca ptr, align 8
  %7 = alloca [64 x i8], align 1
  store ptr %0, ptr %4, align 8
  store ptr %1, ptr %5, align 8
  store ptr %2, ptr %6, align 8
  %8 = load ptr, ptr %4, align 8
  %9 = getelementptr inbounds nuw %struct.crypto_sign_ed25519ph_state, ptr %8, i32 0, i32 0
  %10 = getelementptr inbounds [64 x i8], ptr %7, i64 0, i64 0
  %11 = call i32 @crypto_hash_sha512_final(ptr noundef %9, ptr noundef %10)
  %12 = load ptr, ptr %5, align 8
  %13 = getelementptr inbounds [64 x i8], ptr %7, i64 0, i64 0
  %14 = load ptr, ptr %6, align 8
  %15 = call i32 @_crypto_sign_ed25519_verify_detached(ptr noundef %12, ptr noundef %13, i64 noundef 64, ptr noundef %14, i32 noundef 1)
  ret i32 %15
}

declare i32 @_crypto_sign_ed25519_verify_detached(ptr noundef, ptr noundef, i64 noundef, ptr noundef, i32 noundef) #3

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #3 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #4 = { nounwind }

!llvm.module.flags = !{!0, !1, !2, !3}
!llvm.ident = !{!4}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 8, !"PIC Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 1}
!3 = !{i32 7, !"frame-pointer", i32 1}
!4 = !{!"Homebrew clang version 21.1.8"}
