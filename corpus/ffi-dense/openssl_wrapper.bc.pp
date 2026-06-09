; ModuleID = 'openssl_wrapper.c'
source_filename = "openssl_wrapper.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

@__const.weak_random.seed = private unnamed_addr constant [16 x i8] c"\01\02\03\04\05\06\07\08\09\0A\0B\0C\0D\0E\0F\10", align 1
@.str = private unnamed_addr constant [20 x i8] c"Using password: %s\0A\00", align 1
@.str.1 = private unnamed_addr constant [2 x i8] c"r\00", align 1
@__stderrp = external global ptr, align 8
@.str.2 = private unnamed_addr constant [5 x i8] c"test\00", align 1
@.str.3 = private unnamed_addr constant [10 x i8] c"test data\00", align 1
@.str.4 = private unnamed_addr constant [16 x i8] c"secret_password\00", align 1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @encrypt_leak_ctx(ptr noundef %plaintext, i32 noundef %len) #0 {
entry:
  %retval = alloca i32, align 4
  %plaintext.addr = alloca ptr, align 8
  %len.addr = alloca i32, align 4
  %ctx = alloca ptr, align 8
  store ptr %plaintext, ptr %plaintext.addr, align 8
  store i32 %len, ptr %len.addr, align 4
  %call = call ptr @EVP_CIPHER_CTX_new()
  store ptr %call, ptr %ctx, align 8
  %0 = load ptr, ptr %ctx, align 8
  %tobool = icmp ne ptr %0, null
  br i1 %tobool, label %if.end, label %if.then

if.then:                                          ; preds = %entry
  store i32 -1, ptr %retval, align 4
  br label %return

if.end:                                           ; preds = %entry
  store i32 0, ptr %retval, align 4
  br label %return

return:                                           ; preds = %if.end, %if.then
  %1 = load i32, ptr %retval, align 4
  ret i32 %1
}

declare ptr @EVP_CIPHER_CTX_new() #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @bio_leak(ptr noundef %data) #0 {
entry:
  %data.addr = alloca ptr, align 8
  %bio = alloca ptr, align 8
  store ptr %data, ptr %data.addr, align 8
  %call = call ptr @BIO_s_mem()
  %call1 = call ptr @BIO_new(ptr noundef %call)
  store ptr %call1, ptr %bio, align 8
  %0 = load ptr, ptr %bio, align 8
  %1 = load ptr, ptr %data.addr, align 8
  %2 = load ptr, ptr %data.addr, align 8
  %call2 = call i64 @strlen(ptr noundef %2) #5
  %conv = trunc i64 %call2 to i32
  %call3 = call i32 @BIO_write(ptr noundef %0, ptr noundef %1, i32 noundef %conv)
  ret i32 0
}

declare ptr @BIO_new(ptr noundef) #1

declare ptr @BIO_s_mem() #1

declare i32 @BIO_write(ptr noundef, ptr noundef, i32 noundef) #1

; Function Attrs: nounwind
declare i64 @strlen(ptr noundef) #2

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @rsa_key_leak() #0 {
entry:
  %rsa = alloca ptr, align 8
  %bn = alloca ptr, align 8
  %call = call ptr @RSA_new()
  store ptr %call, ptr %rsa, align 8
  %call1 = call ptr @BN_new()
  store ptr %call1, ptr %bn, align 8
  %0 = load ptr, ptr %bn, align 8
  %call2 = call i32 @BN_set_word(ptr noundef %0, i64 noundef 65537)
  %1 = load ptr, ptr %rsa, align 8
  %2 = load ptr, ptr %bn, align 8
  %call3 = call i32 @RSA_generate_key_ex(ptr noundef %1, i32 noundef 2048, ptr noundef %2, ptr noundef null)
  %3 = load ptr, ptr %bn, align 8
  call void @BN_free(ptr noundef %3)
  ret i32 0
}

declare ptr @RSA_new() #1

declare ptr @BN_new() #1

declare i32 @BN_set_word(ptr noundef, i64 noundef) #1

declare i32 @RSA_generate_key_ex(ptr noundef, i32 noundef, ptr noundef, ptr noundef) #1

declare void @BN_free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @encrypt_unchecked(ptr noundef %ciphertext, ptr noundef %plaintext) #0 {
entry:
  %ciphertext.addr = alloca ptr, align 8
  %plaintext.addr = alloca ptr, align 8
  %ctx = alloca ptr, align 8
  %key = alloca [16 x i8], align 1
  %iv = alloca [16 x i8], align 1
  %len = alloca i32, align 4
  store ptr %ciphertext, ptr %ciphertext.addr, align 8
  store ptr %plaintext, ptr %plaintext.addr, align 8
  %call = call ptr @EVP_CIPHER_CTX_new()
  store ptr %call, ptr %ctx, align 8
  call void @llvm.memset.p0.i64(ptr align 1 %key, i8 0, i64 16, i1 false)
  call void @llvm.memset.p0.i64(ptr align 1 %iv, i8 0, i64 16, i1 false)
  %0 = load ptr, ptr %ctx, align 8
  %call1 = call ptr @EVP_aes_128_cbc()
  %arraydecay = getelementptr inbounds [16 x i8], ptr %key, i64 0, i64 0
  %arraydecay2 = getelementptr inbounds [16 x i8], ptr %iv, i64 0, i64 0
  %call3 = call i32 @EVP_EncryptInit_ex(ptr noundef %0, ptr noundef %call1, ptr noundef null, ptr noundef %arraydecay, ptr noundef %arraydecay2)
  %1 = load ptr, ptr %ctx, align 8
  %2 = load ptr, ptr %ciphertext.addr, align 8
  %3 = load ptr, ptr %plaintext.addr, align 8
  %call4 = call i32 @EVP_EncryptUpdate(ptr noundef %1, ptr noundef %2, ptr noundef %len, ptr noundef %3, i32 noundef 16)
  %4 = load ptr, ptr %ctx, align 8
  call void @EVP_CIPHER_CTX_free(ptr noundef %4)
  ret i32 0
}

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: write)
declare void @llvm.memset.p0.i64(ptr writeonly captures(none), i8, i64, i1 immarg) #3

declare i32 @EVP_EncryptInit_ex(ptr noundef, ptr noundef, ptr noundef, ptr noundef, ptr noundef) #1

declare ptr @EVP_aes_128_cbc() #1

declare i32 @EVP_EncryptUpdate(ptr noundef, ptr noundef, ptr noundef, ptr noundef, i32 noundef) #1

declare void @EVP_CIPHER_CTX_free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @weak_random(ptr noundef %buf, i32 noundef %len) #0 {
entry:
  %buf.addr = alloca ptr, align 8
  %len.addr = alloca i32, align 4
  %seed = alloca [16 x i8], align 1
  store ptr %buf, ptr %buf.addr, align 8
  store i32 %len, ptr %len.addr, align 4
  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %seed, ptr align 1 @__const.weak_random.seed, i64 16, i1 false)
  %arraydecay = getelementptr inbounds [16 x i8], ptr %seed, i64 0, i64 0
  call void @RAND_seed(ptr noundef %arraydecay, i32 noundef 16)
  %0 = load ptr, ptr %buf.addr, align 8
  %1 = load i32, ptr %len.addr, align 4
  %call = call i32 @RAND_bytes(ptr noundef %0, i32 noundef %1)
  ret i32 0
}

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias writeonly captures(none), ptr noalias readonly captures(none), i64, i1 immarg) #4

declare void @RAND_seed(ptr noundef, i32 noundef) #1

declare i32 @RAND_bytes(ptr noundef, i32 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @password_handling(ptr noundef %password) #0 {
entry:
  %password.addr = alloca ptr, align 8
  %pwd = alloca [64 x i8], align 1
  store ptr %password, ptr %password.addr, align 8
  %arraydecay = getelementptr inbounds [64 x i8], ptr %pwd, i64 0, i64 0
  %0 = load ptr, ptr %password.addr, align 8
  %call = call ptr @__strncpy_chk(ptr noundef %arraydecay, ptr noundef %0, i64 noundef 63, i64 noundef 64) #5
  %arrayidx = getelementptr inbounds nuw [64 x i8], ptr %pwd, i64 0, i64 63
  store i8 0, ptr %arrayidx, align 1
  %arraydecay1 = getelementptr inbounds [64 x i8], ptr %pwd, i64 0, i64 0
  %call2 = call i32 (ptr, ...) @printf(ptr noundef @.str, ptr noundef %arraydecay1)
  ret i32 0
}

; Function Attrs: nounwind
declare ptr @__strncpy_chk(ptr noundef, ptr noundef, i64 noundef, i64 noundef) #2

declare i32 @printf(ptr noundef, ...) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @ssl_ctx_leak() #0 {
entry:
  %retval = alloca i32, align 4
  %ctx = alloca ptr, align 8
  %call = call ptr @TLS_method()
  %call1 = call ptr @SSL_CTX_new(ptr noundef %call)
  store ptr %call1, ptr %ctx, align 8
  %0 = load ptr, ptr %ctx, align 8
  %tobool = icmp ne ptr %0, null
  br i1 %tobool, label %if.end, label %if.then

if.then:                                          ; preds = %entry
  store i32 -1, ptr %retval, align 4
  br label %return

if.end:                                           ; preds = %entry
  store i32 0, ptr %retval, align 4
  br label %return

return:                                           ; preds = %if.end, %if.then
  %1 = load i32, ptr %retval, align 4
  ret i32 %1
}

declare ptr @SSL_CTX_new(ptr noundef) #1

declare ptr @TLS_method() #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @x509_leak() #0 {
entry:
  %retval = alloca i32, align 4
  %cert = alloca ptr, align 8
  %call = call ptr @X509_new()
  store ptr %call, ptr %cert, align 8
  %0 = load ptr, ptr %cert, align 8
  %tobool = icmp ne ptr %0, null
  br i1 %tobool, label %if.end, label %if.then

if.then:                                          ; preds = %entry
  store i32 -1, ptr %retval, align 4
  br label %return

if.end:                                           ; preds = %entry
  store i32 0, ptr %retval, align 4
  br label %return

return:                                           ; preds = %if.end, %if.then
  %1 = load i32, ptr %retval, align 4
  ret i32 %1
}

declare ptr @X509_new() #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @unprotected_key() #0 {
entry:
  %pkey = alloca ptr, align 8
  %ctx = alloca ptr, align 8
  store ptr null, ptr %pkey, align 8
  %call = call ptr @EVP_PKEY_CTX_new_id(i32 noundef 1, ptr noundef null)
  store ptr %call, ptr %ctx, align 8
  %0 = load ptr, ptr %ctx, align 8
  %call1 = call i32 @EVP_PKEY_keygen_init(ptr noundef %0)
  %1 = load ptr, ptr %ctx, align 8
  %call2 = call i32 @EVP_PKEY_CTX_set_rsa_keygen_bits(ptr noundef %1, i32 noundef 2048)
  %2 = load ptr, ptr %ctx, align 8
  %call3 = call i32 @EVP_PKEY_keygen(ptr noundef %2, ptr noundef %pkey)
  %3 = load ptr, ptr %ctx, align 8
  call void @EVP_PKEY_CTX_free(ptr noundef %3)
  %4 = load ptr, ptr %pkey, align 8
  call void @EVP_PKEY_free(ptr noundef %4)
  ret i32 0
}

declare ptr @EVP_PKEY_CTX_new_id(i32 noundef, ptr noundef) #1

declare i32 @EVP_PKEY_keygen_init(ptr noundef) #1

declare i32 @EVP_PKEY_CTX_set_rsa_keygen_bits(ptr noundef, i32 noundef) #1

declare i32 @EVP_PKEY_keygen(ptr noundef, ptr noundef) #1

declare void @EVP_PKEY_CTX_free(ptr noundef) #1

declare void @EVP_PKEY_free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @error_handling_bug(ptr noundef %cert_path) #0 {
entry:
  %retval = alloca i32, align 4
  %cert_path.addr = alloca ptr, align 8
  %bio = alloca ptr, align 8
  %cert = alloca ptr, align 8
  store ptr %cert_path, ptr %cert_path.addr, align 8
  %0 = load ptr, ptr %cert_path.addr, align 8
  %call = call ptr @BIO_new_file(ptr noundef %0, ptr noundef @.str.1)
  store ptr %call, ptr %bio, align 8
  %1 = load ptr, ptr %bio, align 8
  %tobool = icmp ne ptr %1, null
  br i1 %tobool, label %if.end, label %if.then

if.then:                                          ; preds = %entry
  %2 = load ptr, ptr @__stderrp, align 8
  call void @ERR_print_errors_fp(ptr noundef %2)
  store i32 -1, ptr %retval, align 4
  br label %return

if.end:                                           ; preds = %entry
  %3 = load ptr, ptr %bio, align 8
  %call1 = call ptr @PEM_read_bio_X509(ptr noundef %3, ptr noundef null, ptr noundef null, ptr noundef null)
  store ptr %call1, ptr %cert, align 8
  %4 = load ptr, ptr %cert, align 8
  %tobool2 = icmp ne ptr %4, null
  br i1 %tobool2, label %if.end4, label %if.then3

if.then3:                                         ; preds = %if.end
  %5 = load ptr, ptr @__stderrp, align 8
  call void @ERR_print_errors_fp(ptr noundef %5)
  store i32 -1, ptr %retval, align 4
  br label %return

if.end4:                                          ; preds = %if.end
  %6 = load ptr, ptr %bio, align 8
  call void @BIO_free(ptr noundef %6)
  %7 = load ptr, ptr %cert, align 8
  call void @X509_free(ptr noundef %7)
  store i32 0, ptr %retval, align 4
  br label %return

return:                                           ; preds = %if.end4, %if.then3, %if.then
  %8 = load i32, ptr %retval, align 4
  ret i32 %8
}

declare ptr @BIO_new_file(ptr noundef, ptr noundef) #1

declare void @ERR_print_errors_fp(ptr noundef) #1

declare ptr @PEM_read_bio_X509(ptr noundef, ptr noundef, ptr noundef, ptr noundef) #1

declare void @BIO_free(ptr noundef) #1

declare void @X509_free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @correct_encryption(ptr noundef %plaintext, i32 noundef %len, ptr noundef %ciphertext, ptr noundef %key) #0 {
entry:
  %retval = alloca i32, align 4
  %plaintext.addr = alloca ptr, align 8
  %len.addr = alloca i32, align 4
  %ciphertext.addr = alloca ptr, align 8
  %key.addr = alloca ptr, align 8
  %ctx = alloca ptr, align 8
  %iv = alloca [16 x i8], align 1
  %out_len = alloca i32, align 4
  %final_len = alloca i32, align 4
  store ptr %plaintext, ptr %plaintext.addr, align 8
  store i32 %len, ptr %len.addr, align 4
  store ptr %ciphertext, ptr %ciphertext.addr, align 8
  store ptr %key, ptr %key.addr, align 8
  %call = call ptr @EVP_CIPHER_CTX_new()
  store ptr %call, ptr %ctx, align 8
  %0 = load ptr, ptr %ctx, align 8
  %tobool = icmp ne ptr %0, null
  br i1 %tobool, label %if.end, label %if.then

if.then:                                          ; preds = %entry
  store i32 -1, ptr %retval, align 4
  br label %return

if.end:                                           ; preds = %entry
  %arraydecay = getelementptr inbounds [16 x i8], ptr %iv, i64 0, i64 0
  %call1 = call i32 @RAND_bytes(ptr noundef %arraydecay, i32 noundef 16)
  %cmp = icmp ne i32 %call1, 1
  br i1 %cmp, label %if.then2, label %if.end3

if.then2:                                         ; preds = %if.end
  %1 = load ptr, ptr %ctx, align 8
  call void @EVP_CIPHER_CTX_free(ptr noundef %1)
  store i32 -1, ptr %retval, align 4
  br label %return

if.end3:                                          ; preds = %if.end
  %2 = load ptr, ptr %ctx, align 8
  %call4 = call ptr @EVP_aes_256_cbc()
  %3 = load ptr, ptr %key.addr, align 8
  %arraydecay5 = getelementptr inbounds [16 x i8], ptr %iv, i64 0, i64 0
  %call6 = call i32 @EVP_EncryptInit_ex(ptr noundef %2, ptr noundef %call4, ptr noundef null, ptr noundef %3, ptr noundef %arraydecay5)
  %cmp7 = icmp ne i32 %call6, 1
  br i1 %cmp7, label %if.then8, label %if.end9

if.then8:                                         ; preds = %if.end3
  %4 = load ptr, ptr %ctx, align 8
  call void @EVP_CIPHER_CTX_free(ptr noundef %4)
  store i32 -1, ptr %retval, align 4
  br label %return

if.end9:                                          ; preds = %if.end3
  %5 = load ptr, ptr %ctx, align 8
  %6 = load ptr, ptr %ciphertext.addr, align 8
  %7 = load ptr, ptr %plaintext.addr, align 8
  %8 = load i32, ptr %len.addr, align 4
  %call10 = call i32 @EVP_EncryptUpdate(ptr noundef %5, ptr noundef %6, ptr noundef %out_len, ptr noundef %7, i32 noundef %8)
  %cmp11 = icmp ne i32 %call10, 1
  br i1 %cmp11, label %if.then12, label %if.end13

if.then12:                                        ; preds = %if.end9
  %9 = load ptr, ptr %ctx, align 8
  call void @EVP_CIPHER_CTX_free(ptr noundef %9)
  store i32 -1, ptr %retval, align 4
  br label %return

if.end13:                                         ; preds = %if.end9
  %10 = load ptr, ptr %ctx, align 8
  %11 = load ptr, ptr %ciphertext.addr, align 8
  %12 = load i32, ptr %out_len, align 4
  %idx.ext = sext i32 %12 to i64
  %add.ptr = getelementptr inbounds i8, ptr %11, i64 %idx.ext
  %call14 = call i32 @EVP_EncryptFinal_ex(ptr noundef %10, ptr noundef %add.ptr, ptr noundef %final_len)
  %cmp15 = icmp ne i32 %call14, 1
  br i1 %cmp15, label %if.then16, label %if.end17

if.then16:                                        ; preds = %if.end13
  %13 = load ptr, ptr %ctx, align 8
  call void @EVP_CIPHER_CTX_free(ptr noundef %13)
  store i32 -1, ptr %retval, align 4
  br label %return

if.end17:                                         ; preds = %if.end13
  %14 = load ptr, ptr %ctx, align 8
  call void @EVP_CIPHER_CTX_free(ptr noundef %14)
  %15 = load i32, ptr %out_len, align 4
  %16 = load i32, ptr %final_len, align 4
  %add = add nsw i32 %15, %16
  store i32 %add, ptr %retval, align 4
  br label %return

return:                                           ; preds = %if.end17, %if.then16, %if.then12, %if.then8, %if.then2, %if.then
  %17 = load i32, ptr %retval, align 4
  ret i32 %17
}

declare ptr @EVP_aes_256_cbc() #1

declare i32 @EVP_EncryptFinal_ex(ptr noundef, ptr noundef, ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @main() #0 {
entry:
  %retval = alloca i32, align 4
  %buf = alloca [16 x i8], align 1
  store i32 0, ptr %retval, align 4
  call void @OpenSSL_add_all_algorithms()
  call void @SSL_load_error_strings()
  %call = call i32 @encrypt_leak_ctx(ptr noundef @.str.2, i32 noundef 4)
  %call1 = call i32 @bio_leak(ptr noundef @.str.3)
  %call2 = call i32 @rsa_key_leak()
  %call3 = call i32 @encrypt_unchecked(ptr noundef null, ptr noundef @.str.2)
  %arraydecay = getelementptr inbounds [16 x i8], ptr %buf, i64 0, i64 0
  %call4 = call i32 @weak_random(ptr noundef %arraydecay, i32 noundef 16)
  %call5 = call i32 @password_handling(ptr noundef @.str.4)
  call void @EVP_cleanup()
  call void @ERR_free_strings()
  ret i32 0
}

declare void @OpenSSL_add_all_algorithms() #1

declare void @SSL_load_error_strings() #1

declare void @EVP_cleanup() #1

declare void @ERR_free_strings() #1

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #2 = { nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { nocallback nofree nounwind willreturn memory(argmem: write) }
attributes #4 = { nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #5 = { nounwind }

!llvm.module.flags = !{!0, !1, !2, !3}
!llvm.ident = !{!4}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 8, !"PIC Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 1}
!3 = !{i32 7, !"frame-pointer", i32 1}
!4 = !{!"Homebrew clang version 21.1.8"}
