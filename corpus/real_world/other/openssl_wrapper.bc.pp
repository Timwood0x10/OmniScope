; ModuleID = '/Users/scc/code/zigcode/OmniScope/corpus/ffi-dense/openssl_wrapper.c'
source_filename = "/Users/scc/code/zigcode/OmniScope/corpus/ffi-dense/openssl_wrapper.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

@__const.weak_random.seed = private unnamed_addr constant [16 x i8] c"\01\02\03\04\05\06\07\08\09\0A\0B\0C\0D\0E\0F\10", align 1
@.str = private unnamed_addr constant [20 x i8] c"Using password: %s\0A\00", align 1, !dbg !0
@.str.1 = private unnamed_addr constant [2 x i8] c"r\00", align 1, !dbg !7
@__stderrp = external global ptr, align 8
@.str.2 = private unnamed_addr constant [5 x i8] c"test\00", align 1, !dbg !12
@.str.3 = private unnamed_addr constant [10 x i8] c"test data\00", align 1, !dbg !17
@.str.4 = private unnamed_addr constant [16 x i8] c"secret_password\00", align 1, !dbg !22

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @encrypt_leak_ctx(ptr noundef %plaintext, i32 noundef %len) #0 !dbg !41 {
entry:
  %retval = alloca i32, align 4
  %plaintext.addr = alloca ptr, align 8
  %len.addr = alloca i32, align 4
  %ctx = alloca ptr, align 8
  store ptr %plaintext, ptr %plaintext.addr, align 8
    #dbg_declare(ptr %plaintext.addr, !48, !DIExpression(), !49)
  store i32 %len, ptr %len.addr, align 4
    #dbg_declare(ptr %len.addr, !50, !DIExpression(), !51)
    #dbg_declare(ptr %ctx, !52, !DIExpression(), !56)
  %call = call ptr @EVP_CIPHER_CTX_new(), !dbg !57
  store ptr %call, ptr %ctx, align 8, !dbg !56
  %0 = load ptr, ptr %ctx, align 8, !dbg !58
  %tobool = icmp ne ptr %0, null, !dbg !58
  br i1 %tobool, label %if.end, label %if.then, !dbg !60

if.then:                                          ; preds = %entry
  store i32 -1, ptr %retval, align 4, !dbg !61
  br label %return, !dbg !61

if.end:                                           ; preds = %entry
  store i32 0, ptr %retval, align 4, !dbg !62
  br label %return, !dbg !62

return:                                           ; preds = %if.end, %if.then
  %1 = load i32, ptr %retval, align 4, !dbg !63
  ret i32 %1, !dbg !63
}

declare ptr @EVP_CIPHER_CTX_new() #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @bio_leak(ptr noundef %data) #0 !dbg !64 {
entry:
  %data.addr = alloca ptr, align 8
  %bio = alloca ptr, align 8
  store ptr %data, ptr %data.addr, align 8
    #dbg_declare(ptr %data.addr, !69, !DIExpression(), !70)
    #dbg_declare(ptr %bio, !71, !DIExpression(), !75)
  %call = call ptr @BIO_s_mem(), !dbg !76
  %call1 = call ptr @BIO_new(ptr noundef %call), !dbg !77
  store ptr %call1, ptr %bio, align 8, !dbg !75
  %0 = load ptr, ptr %bio, align 8, !dbg !78
  %1 = load ptr, ptr %data.addr, align 8, !dbg !79
  %2 = load ptr, ptr %data.addr, align 8, !dbg !80
  %call2 = call i64 @strlen(ptr noundef %2) #5, !dbg !81
  %conv = trunc i64 %call2 to i32, !dbg !81
  %call3 = call i32 @BIO_write(ptr noundef %0, ptr noundef %1, i32 noundef %conv), !dbg !82
  ret i32 0, !dbg !83
}

declare ptr @BIO_new(ptr noundef) #1

declare ptr @BIO_s_mem() #1

declare i32 @BIO_write(ptr noundef, ptr noundef, i32 noundef) #1

; Function Attrs: nounwind
declare i64 @strlen(ptr noundef) #2

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @rsa_key_leak() #0 !dbg !84 {
entry:
  %rsa = alloca ptr, align 8
  %bn = alloca ptr, align 8
    #dbg_declare(ptr %rsa, !87, !DIExpression(), !91)
  %call = call ptr @RSA_new(), !dbg !92
  store ptr %call, ptr %rsa, align 8, !dbg !91
    #dbg_declare(ptr %bn, !93, !DIExpression(), !97)
  %call1 = call ptr @BN_new(), !dbg !98
  store ptr %call1, ptr %bn, align 8, !dbg !97
  %0 = load ptr, ptr %bn, align 8, !dbg !99
  %call2 = call i32 @BN_set_word(ptr noundef %0, i64 noundef 65537), !dbg !100
  %1 = load ptr, ptr %rsa, align 8, !dbg !101
  %2 = load ptr, ptr %bn, align 8, !dbg !102
  %call3 = call i32 @RSA_generate_key_ex(ptr noundef %1, i32 noundef 2048, ptr noundef %2, ptr noundef null), !dbg !103
  %3 = load ptr, ptr %bn, align 8, !dbg !104
  call void @BN_free(ptr noundef %3), !dbg !105
  ret i32 0, !dbg !106
}

declare ptr @RSA_new() #1

declare ptr @BN_new() #1

declare i32 @BN_set_word(ptr noundef, i64 noundef) #1

declare i32 @RSA_generate_key_ex(ptr noundef, i32 noundef, ptr noundef, ptr noundef) #1

declare void @BN_free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @encrypt_unchecked(ptr noundef %ciphertext, ptr noundef %plaintext) #0 !dbg !107 {
entry:
  %ciphertext.addr = alloca ptr, align 8
  %plaintext.addr = alloca ptr, align 8
  %ctx = alloca ptr, align 8
  %key = alloca [16 x i8], align 1
  %iv = alloca [16 x i8], align 1
  %len = alloca i32, align 4
  store ptr %ciphertext, ptr %ciphertext.addr, align 8
    #dbg_declare(ptr %ciphertext.addr, !110, !DIExpression(), !111)
  store ptr %plaintext, ptr %plaintext.addr, align 8
    #dbg_declare(ptr %plaintext.addr, !112, !DIExpression(), !113)
    #dbg_declare(ptr %ctx, !114, !DIExpression(), !115)
  %call = call ptr @EVP_CIPHER_CTX_new(), !dbg !116
  store ptr %call, ptr %ctx, align 8, !dbg !115
    #dbg_declare(ptr %key, !117, !DIExpression(), !119)
  call void @llvm.memset.p0.i64(ptr align 1 %key, i8 0, i64 16, i1 false), !dbg !119
    #dbg_declare(ptr %iv, !120, !DIExpression(), !121)
  call void @llvm.memset.p0.i64(ptr align 1 %iv, i8 0, i64 16, i1 false), !dbg !121
  %0 = load ptr, ptr %ctx, align 8, !dbg !122
  %call1 = call ptr @EVP_aes_128_cbc(), !dbg !123
  %arraydecay = getelementptr inbounds [16 x i8], ptr %key, i64 0, i64 0, !dbg !124
  %arraydecay2 = getelementptr inbounds [16 x i8], ptr %iv, i64 0, i64 0, !dbg !125
  %call3 = call i32 @EVP_EncryptInit_ex(ptr noundef %0, ptr noundef %call1, ptr noundef null, ptr noundef %arraydecay, ptr noundef %arraydecay2), !dbg !126
    #dbg_declare(ptr %len, !127, !DIExpression(), !128)
  %1 = load ptr, ptr %ctx, align 8, !dbg !129
  %2 = load ptr, ptr %ciphertext.addr, align 8, !dbg !130
  %3 = load ptr, ptr %plaintext.addr, align 8, !dbg !131
  %call4 = call i32 @EVP_EncryptUpdate(ptr noundef %1, ptr noundef %2, ptr noundef %len, ptr noundef %3, i32 noundef 16), !dbg !132
  %4 = load ptr, ptr %ctx, align 8, !dbg !133
  call void @EVP_CIPHER_CTX_free(ptr noundef %4), !dbg !134
  ret i32 0, !dbg !135
}

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: write)
declare void @llvm.memset.p0.i64(ptr writeonly captures(none), i8, i64, i1 immarg) #3

declare i32 @EVP_EncryptInit_ex(ptr noundef, ptr noundef, ptr noundef, ptr noundef, ptr noundef) #1

declare ptr @EVP_aes_128_cbc() #1

declare i32 @EVP_EncryptUpdate(ptr noundef, ptr noundef, ptr noundef, ptr noundef, i32 noundef) #1

declare void @EVP_CIPHER_CTX_free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @weak_random(ptr noundef %buf, i32 noundef %len) #0 !dbg !136 {
entry:
  %buf.addr = alloca ptr, align 8
  %len.addr = alloca i32, align 4
  %seed = alloca [16 x i8], align 1
  store ptr %buf, ptr %buf.addr, align 8
    #dbg_declare(ptr %buf.addr, !139, !DIExpression(), !140)
  store i32 %len, ptr %len.addr, align 4
    #dbg_declare(ptr %len.addr, !141, !DIExpression(), !142)
    #dbg_declare(ptr %seed, !143, !DIExpression(), !144)
  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %seed, ptr align 1 @__const.weak_random.seed, i64 16, i1 false), !dbg !144
  %arraydecay = getelementptr inbounds [16 x i8], ptr %seed, i64 0, i64 0, !dbg !145
  call void @RAND_seed(ptr noundef %arraydecay, i32 noundef 16), !dbg !146
  %0 = load ptr, ptr %buf.addr, align 8, !dbg !147
  %1 = load i32, ptr %len.addr, align 4, !dbg !148
  %call = call i32 @RAND_bytes(ptr noundef %0, i32 noundef %1), !dbg !149
  ret i32 0, !dbg !150
}

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias writeonly captures(none), ptr noalias readonly captures(none), i64, i1 immarg) #4

declare void @RAND_seed(ptr noundef, i32 noundef) #1

declare i32 @RAND_bytes(ptr noundef, i32 noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @password_handling(ptr noundef %password) #0 !dbg !151 {
entry:
  %password.addr = alloca ptr, align 8
  %pwd = alloca [64 x i8], align 1
  store ptr %password, ptr %password.addr, align 8
    #dbg_declare(ptr %password.addr, !152, !DIExpression(), !153)
    #dbg_declare(ptr %pwd, !154, !DIExpression(), !158)
  %arraydecay = getelementptr inbounds [64 x i8], ptr %pwd, i64 0, i64 0, !dbg !159
  %0 = load ptr, ptr %password.addr, align 8, !dbg !159
  %call = call ptr @__strncpy_chk(ptr noundef %arraydecay, ptr noundef %0, i64 noundef 63, i64 noundef 64) #5, !dbg !159
  %arrayidx = getelementptr inbounds nuw [64 x i8], ptr %pwd, i64 0, i64 63, !dbg !160
  store i8 0, ptr %arrayidx, align 1, !dbg !161
  %arraydecay1 = getelementptr inbounds [64 x i8], ptr %pwd, i64 0, i64 0, !dbg !162
  %call2 = call i32 (ptr, ...) @printf(ptr noundef @.str, ptr noundef %arraydecay1), !dbg !163
  ret i32 0, !dbg !164
}

; Function Attrs: nounwind
declare ptr @__strncpy_chk(ptr noundef, ptr noundef, i64 noundef, i64 noundef) #2

declare i32 @printf(ptr noundef, ...) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @ssl_ctx_leak() #0 !dbg !165 {
entry:
  %retval = alloca i32, align 4
  %ctx = alloca ptr, align 8
    #dbg_declare(ptr %ctx, !166, !DIExpression(), !170)
  %call = call ptr @TLS_method(), !dbg !171
  %call1 = call ptr @SSL_CTX_new(ptr noundef %call), !dbg !172
  store ptr %call1, ptr %ctx, align 8, !dbg !170
  %0 = load ptr, ptr %ctx, align 8, !dbg !173
  %tobool = icmp ne ptr %0, null, !dbg !173
  br i1 %tobool, label %if.end, label %if.then, !dbg !175

if.then:                                          ; preds = %entry
  store i32 -1, ptr %retval, align 4, !dbg !176
  br label %return, !dbg !176

if.end:                                           ; preds = %entry
  store i32 0, ptr %retval, align 4, !dbg !177
  br label %return, !dbg !177

return:                                           ; preds = %if.end, %if.then
  %1 = load i32, ptr %retval, align 4, !dbg !178
  ret i32 %1, !dbg !178
}

declare ptr @SSL_CTX_new(ptr noundef) #1

declare ptr @TLS_method() #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @x509_leak() #0 !dbg !179 {
entry:
  %retval = alloca i32, align 4
  %cert = alloca ptr, align 8
    #dbg_declare(ptr %cert, !180, !DIExpression(), !184)
  %call = call ptr @X509_new(), !dbg !185
  store ptr %call, ptr %cert, align 8, !dbg !184
  %0 = load ptr, ptr %cert, align 8, !dbg !186
  %tobool = icmp ne ptr %0, null, !dbg !186
  br i1 %tobool, label %if.end, label %if.then, !dbg !188

if.then:                                          ; preds = %entry
  store i32 -1, ptr %retval, align 4, !dbg !189
  br label %return, !dbg !189

if.end:                                           ; preds = %entry
  store i32 0, ptr %retval, align 4, !dbg !190
  br label %return, !dbg !190

return:                                           ; preds = %if.end, %if.then
  %1 = load i32, ptr %retval, align 4, !dbg !191
  ret i32 %1, !dbg !191
}

declare ptr @X509_new() #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @unprotected_key() #0 !dbg !192 {
entry:
  %pkey = alloca ptr, align 8
  %ctx = alloca ptr, align 8
    #dbg_declare(ptr %pkey, !193, !DIExpression(), !197)
  store ptr null, ptr %pkey, align 8, !dbg !197
    #dbg_declare(ptr %ctx, !198, !DIExpression(), !202)
  %call = call ptr @EVP_PKEY_CTX_new_id(i32 noundef 1, ptr noundef null), !dbg !203
  store ptr %call, ptr %ctx, align 8, !dbg !202
  %0 = load ptr, ptr %ctx, align 8, !dbg !204
  %call1 = call i32 @EVP_PKEY_keygen_init(ptr noundef %0), !dbg !205
  %1 = load ptr, ptr %ctx, align 8, !dbg !206
  %call2 = call i32 @EVP_PKEY_CTX_set_rsa_keygen_bits(ptr noundef %1, i32 noundef 2048), !dbg !207
  %2 = load ptr, ptr %ctx, align 8, !dbg !208
  %call3 = call i32 @EVP_PKEY_keygen(ptr noundef %2, ptr noundef %pkey), !dbg !209
  %3 = load ptr, ptr %ctx, align 8, !dbg !210
  call void @EVP_PKEY_CTX_free(ptr noundef %3), !dbg !211
  %4 = load ptr, ptr %pkey, align 8, !dbg !212
  call void @EVP_PKEY_free(ptr noundef %4), !dbg !213
  ret i32 0, !dbg !214
}

declare ptr @EVP_PKEY_CTX_new_id(i32 noundef, ptr noundef) #1

declare i32 @EVP_PKEY_keygen_init(ptr noundef) #1

declare i32 @EVP_PKEY_CTX_set_rsa_keygen_bits(ptr noundef, i32 noundef) #1

declare i32 @EVP_PKEY_keygen(ptr noundef, ptr noundef) #1

declare void @EVP_PKEY_CTX_free(ptr noundef) #1

declare void @EVP_PKEY_free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @error_handling_bug(ptr noundef %cert_path) #0 !dbg !215 {
entry:
  %retval = alloca i32, align 4
  %cert_path.addr = alloca ptr, align 8
  %bio = alloca ptr, align 8
  %cert = alloca ptr, align 8
  store ptr %cert_path, ptr %cert_path.addr, align 8
    #dbg_declare(ptr %cert_path.addr, !216, !DIExpression(), !217)
    #dbg_declare(ptr %bio, !218, !DIExpression(), !219)
  %0 = load ptr, ptr %cert_path.addr, align 8, !dbg !220
  %call = call ptr @BIO_new_file(ptr noundef %0, ptr noundef @.str.1), !dbg !221
  store ptr %call, ptr %bio, align 8, !dbg !219
  %1 = load ptr, ptr %bio, align 8, !dbg !222
  %tobool = icmp ne ptr %1, null, !dbg !222
  br i1 %tobool, label %if.end, label %if.then, !dbg !224

if.then:                                          ; preds = %entry
  %2 = load ptr, ptr @__stderrp, align 8, !dbg !225
  call void @ERR_print_errors_fp(ptr noundef %2), !dbg !227
  store i32 -1, ptr %retval, align 4, !dbg !228
  br label %return, !dbg !228

if.end:                                           ; preds = %entry
    #dbg_declare(ptr %cert, !229, !DIExpression(), !230)
  %3 = load ptr, ptr %bio, align 8, !dbg !231
  %call1 = call ptr @PEM_read_bio_X509(ptr noundef %3, ptr noundef null, ptr noundef null, ptr noundef null), !dbg !232
  store ptr %call1, ptr %cert, align 8, !dbg !230
  %4 = load ptr, ptr %cert, align 8, !dbg !233
  %tobool2 = icmp ne ptr %4, null, !dbg !233
  br i1 %tobool2, label %if.end4, label %if.then3, !dbg !235

if.then3:                                         ; preds = %if.end
  %5 = load ptr, ptr @__stderrp, align 8, !dbg !236
  call void @ERR_print_errors_fp(ptr noundef %5), !dbg !238
  store i32 -1, ptr %retval, align 4, !dbg !239
  br label %return, !dbg !239

if.end4:                                          ; preds = %if.end
  %6 = load ptr, ptr %bio, align 8, !dbg !240
  call void @BIO_free(ptr noundef %6), !dbg !241
  %7 = load ptr, ptr %cert, align 8, !dbg !242
  call void @X509_free(ptr noundef %7), !dbg !243
  store i32 0, ptr %retval, align 4, !dbg !244
  br label %return, !dbg !244

return:                                           ; preds = %if.end4, %if.then3, %if.then
  %8 = load i32, ptr %retval, align 4, !dbg !245
  ret i32 %8, !dbg !245
}

declare ptr @BIO_new_file(ptr noundef, ptr noundef) #1

declare void @ERR_print_errors_fp(ptr noundef) #1

declare ptr @PEM_read_bio_X509(ptr noundef, ptr noundef, ptr noundef, ptr noundef) #1

declare void @BIO_free(ptr noundef) #1

declare void @X509_free(ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @correct_encryption(ptr noundef %plaintext, i32 noundef %len, ptr noundef %ciphertext, ptr noundef %key) #0 !dbg !246 {
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
    #dbg_declare(ptr %plaintext.addr, !249, !DIExpression(), !250)
  store i32 %len, ptr %len.addr, align 4
    #dbg_declare(ptr %len.addr, !251, !DIExpression(), !252)
  store ptr %ciphertext, ptr %ciphertext.addr, align 8
    #dbg_declare(ptr %ciphertext.addr, !253, !DIExpression(), !254)
  store ptr %key, ptr %key.addr, align 8
    #dbg_declare(ptr %key.addr, !255, !DIExpression(), !256)
    #dbg_declare(ptr %ctx, !257, !DIExpression(), !258)
  %call = call ptr @EVP_CIPHER_CTX_new(), !dbg !259
  store ptr %call, ptr %ctx, align 8, !dbg !258
  %0 = load ptr, ptr %ctx, align 8, !dbg !260
  %tobool = icmp ne ptr %0, null, !dbg !260
  br i1 %tobool, label %if.end, label %if.then, !dbg !262

if.then:                                          ; preds = %entry
  store i32 -1, ptr %retval, align 4, !dbg !263
  br label %return, !dbg !263

if.end:                                           ; preds = %entry
    #dbg_declare(ptr %iv, !264, !DIExpression(), !265)
  %arraydecay = getelementptr inbounds [16 x i8], ptr %iv, i64 0, i64 0, !dbg !266
  %call1 = call i32 @RAND_bytes(ptr noundef %arraydecay, i32 noundef 16), !dbg !268
  %cmp = icmp ne i32 %call1, 1, !dbg !269
  br i1 %cmp, label %if.then2, label %if.end3, !dbg !269

if.then2:                                         ; preds = %if.end
  %1 = load ptr, ptr %ctx, align 8, !dbg !270
  call void @EVP_CIPHER_CTX_free(ptr noundef %1), !dbg !272
  store i32 -1, ptr %retval, align 4, !dbg !273
  br label %return, !dbg !273

if.end3:                                          ; preds = %if.end
  %2 = load ptr, ptr %ctx, align 8, !dbg !274
  %call4 = call ptr @EVP_aes_256_cbc(), !dbg !276
  %3 = load ptr, ptr %key.addr, align 8, !dbg !277
  %arraydecay5 = getelementptr inbounds [16 x i8], ptr %iv, i64 0, i64 0, !dbg !278
  %call6 = call i32 @EVP_EncryptInit_ex(ptr noundef %2, ptr noundef %call4, ptr noundef null, ptr noundef %3, ptr noundef %arraydecay5), !dbg !279
  %cmp7 = icmp ne i32 %call6, 1, !dbg !280
  br i1 %cmp7, label %if.then8, label %if.end9, !dbg !280

if.then8:                                         ; preds = %if.end3
  %4 = load ptr, ptr %ctx, align 8, !dbg !281
  call void @EVP_CIPHER_CTX_free(ptr noundef %4), !dbg !283
  store i32 -1, ptr %retval, align 4, !dbg !284
  br label %return, !dbg !284

if.end9:                                          ; preds = %if.end3
    #dbg_declare(ptr %out_len, !285, !DIExpression(), !286)
  %5 = load ptr, ptr %ctx, align 8, !dbg !287
  %6 = load ptr, ptr %ciphertext.addr, align 8, !dbg !289
  %7 = load ptr, ptr %plaintext.addr, align 8, !dbg !290
  %8 = load i32, ptr %len.addr, align 4, !dbg !291
  %call10 = call i32 @EVP_EncryptUpdate(ptr noundef %5, ptr noundef %6, ptr noundef %out_len, ptr noundef %7, i32 noundef %8), !dbg !292
  %cmp11 = icmp ne i32 %call10, 1, !dbg !293
  br i1 %cmp11, label %if.then12, label %if.end13, !dbg !293

if.then12:                                        ; preds = %if.end9
  %9 = load ptr, ptr %ctx, align 8, !dbg !294
  call void @EVP_CIPHER_CTX_free(ptr noundef %9), !dbg !296
  store i32 -1, ptr %retval, align 4, !dbg !297
  br label %return, !dbg !297

if.end13:                                         ; preds = %if.end9
    #dbg_declare(ptr %final_len, !298, !DIExpression(), !299)
  %10 = load ptr, ptr %ctx, align 8, !dbg !300
  %11 = load ptr, ptr %ciphertext.addr, align 8, !dbg !302
  %12 = load i32, ptr %out_len, align 4, !dbg !303
  %idx.ext = sext i32 %12 to i64, !dbg !304
  %add.ptr = getelementptr inbounds i8, ptr %11, i64 %idx.ext, !dbg !304
  %call14 = call i32 @EVP_EncryptFinal_ex(ptr noundef %10, ptr noundef %add.ptr, ptr noundef %final_len), !dbg !305
  %cmp15 = icmp ne i32 %call14, 1, !dbg !306
  br i1 %cmp15, label %if.then16, label %if.end17, !dbg !306

if.then16:                                        ; preds = %if.end13
  %13 = load ptr, ptr %ctx, align 8, !dbg !307
  call void @EVP_CIPHER_CTX_free(ptr noundef %13), !dbg !309
  store i32 -1, ptr %retval, align 4, !dbg !310
  br label %return, !dbg !310

if.end17:                                         ; preds = %if.end13
  %14 = load ptr, ptr %ctx, align 8, !dbg !311
  call void @EVP_CIPHER_CTX_free(ptr noundef %14), !dbg !312
  %15 = load i32, ptr %out_len, align 4, !dbg !313
  %16 = load i32, ptr %final_len, align 4, !dbg !314
  %add = add nsw i32 %15, %16, !dbg !315
  store i32 %add, ptr %retval, align 4, !dbg !316
  br label %return, !dbg !316

return:                                           ; preds = %if.end17, %if.then16, %if.then12, %if.then8, %if.then2, %if.then
  %17 = load i32, ptr %retval, align 4, !dbg !317
  ret i32 %17, !dbg !317
}

declare ptr @EVP_aes_256_cbc() #1

declare i32 @EVP_EncryptFinal_ex(ptr noundef, ptr noundef, ptr noundef) #1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @main() #0 !dbg !318 {
entry:
  %retval = alloca i32, align 4
  %buf = alloca [16 x i8], align 1
  store i32 0, ptr %retval, align 4
  call void @OpenSSL_add_all_algorithms(), !dbg !319
  call void @SSL_load_error_strings(), !dbg !320
  %call = call i32 @encrypt_leak_ctx(ptr noundef @.str.2, i32 noundef 4), !dbg !321
  %call1 = call i32 @bio_leak(ptr noundef @.str.3), !dbg !322
  %call2 = call i32 @rsa_key_leak(), !dbg !323
  %call3 = call i32 @encrypt_unchecked(ptr noundef null, ptr noundef @.str.2), !dbg !324
    #dbg_declare(ptr %buf, !325, !DIExpression(), !326)
  %arraydecay = getelementptr inbounds [16 x i8], ptr %buf, i64 0, i64 0, !dbg !327
  %call4 = call i32 @weak_random(ptr noundef %arraydecay, i32 noundef 16), !dbg !328
  %call5 = call i32 @password_handling(ptr noundef @.str.4), !dbg !329
  call void @EVP_cleanup(), !dbg !330
  call void @ERR_free_strings(), !dbg !331
  ret i32 0, !dbg !332
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

!llvm.dbg.cu = !{!27}
!llvm.module.flags = !{!34, !35, !36, !37, !38, !39}
!llvm.ident = !{!40}

!0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
!1 = distinct !DIGlobalVariable(scope: null, file: !2, line: 158, type: !3, isLocal: true, isDefinition: true)
!2 = !DIFile(filename: "corpus/ffi-dense/openssl_wrapper.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "e57c17b21da3a6efc8cf35f364bd4524")
!3 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 160, elements: !5)
!4 = !DIBasicType(name: "char", size: 8, encoding: DW_ATE_signed_char)
!5 = !{!6}
!6 = !DISubrange(count: 20)
!7 = !DIGlobalVariableExpression(var: !8, expr: !DIExpression())
!8 = distinct !DIGlobalVariable(scope: null, file: !2, line: 205, type: !9, isLocal: true, isDefinition: true)
!9 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 16, elements: !10)
!10 = !{!11}
!11 = !DISubrange(count: 2)
!12 = !DIGlobalVariableExpression(var: !13, expr: !DIExpression())
!13 = distinct !DIGlobalVariable(scope: null, file: !2, line: 262, type: !14, isLocal: true, isDefinition: true)
!14 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 40, elements: !15)
!15 = !{!16}
!16 = !DISubrange(count: 5)
!17 = !DIGlobalVariableExpression(var: !18, expr: !DIExpression())
!18 = distinct !DIGlobalVariable(scope: null, file: !2, line: 263, type: !19, isLocal: true, isDefinition: true)
!19 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 80, elements: !20)
!20 = !{!21}
!21 = !DISubrange(count: 10)
!22 = !DIGlobalVariableExpression(var: !23, expr: !DIExpression())
!23 = distinct !DIGlobalVariable(scope: null, file: !2, line: 269, type: !24, isLocal: true, isDefinition: true)
!24 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 128, elements: !25)
!25 = !{!26}
!26 = !DISubrange(count: 16)
!27 = distinct !DICompileUnit(language: DW_LANG_C11, file: !28, producer: "Homebrew clang version 21.1.8", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, retainedTypes: !29, globals: !33, splitDebugInlining: false, nameTableKind: Apple, sysroot: "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk", sdk: "MacOSX15.sdk")
!28 = !DIFile(filename: "/Users/scc/code/zigcode/OmniScope/corpus/ffi-dense/openssl_wrapper.c", directory: "/Users/scc/code/zigcode/OmniScope", checksumkind: CSK_MD5, checksum: "e57c17b21da3a6efc8cf35f364bd4524")
!29 = !{!30, !31}
!30 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!31 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !32, size: 64)
!32 = !DIBasicType(name: "unsigned char", size: 8, encoding: DW_ATE_unsigned_char)
!33 = !{!0, !7, !12, !17, !22}
!34 = !{i32 7, !"Dwarf Version", i32 5}
!35 = !{i32 2, !"Debug Info Version", i32 3}
!36 = !{i32 1, !"wchar_size", i32 4}
!37 = !{i32 8, !"PIC Level", i32 2}
!38 = !{i32 7, !"uwtable", i32 1}
!39 = !{i32 7, !"frame-pointer", i32 1}
!40 = !{!"Homebrew clang version 21.1.8"}
!41 = distinct !DISubprogram(name: "encrypt_leak_ctx", scope: !2, file: !2, line: 93, type: !42, scopeLine: 93, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !27, retainedNodes: !47)
!42 = !DISubroutineType(types: !43)
!43 = !{!44, !45, !44}
!44 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!45 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !46, size: 64)
!46 = !DIDerivedType(tag: DW_TAG_const_type, baseType: !32)
!47 = !{}
!48 = !DILocalVariable(name: "plaintext", arg: 1, scope: !41, file: !2, line: 93, type: !45)
!49 = !DILocation(line: 93, column: 43, scope: !41)
!50 = !DILocalVariable(name: "len", arg: 2, scope: !41, file: !2, line: 93, type: !44)
!51 = !DILocation(line: 93, column: 58, scope: !41)
!52 = !DILocalVariable(name: "ctx", scope: !41, file: !2, line: 94, type: !53)
!53 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !54, size: 64)
!54 = !DIDerivedType(tag: DW_TAG_typedef, name: "EVP_CIPHER_CTX", file: !2, line: 20, baseType: !55)
!55 = !DICompositeType(tag: DW_TAG_structure_type, name: "EVP_CIPHER_CTX", file: !2, line: 20, flags: DIFlagFwdDecl)
!56 = !DILocation(line: 94, column: 21, scope: !41)
!57 = !DILocation(line: 94, column: 27, scope: !41)
!58 = !DILocation(line: 95, column: 10, scope: !59)
!59 = distinct !DILexicalBlock(scope: !41, file: !2, line: 95, column: 9)
!60 = !DILocation(line: 95, column: 9, scope: !59)
!61 = !DILocation(line: 95, column: 15, scope: !59)
!62 = !DILocation(line: 98, column: 5, scope: !41)
!63 = !DILocation(line: 99, column: 1, scope: !41)
!64 = distinct !DISubprogram(name: "bio_leak", scope: !2, file: !2, line: 102, type: !65, scopeLine: 102, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !27, retainedNodes: !47)
!65 = !DISubroutineType(types: !66)
!66 = !{!44, !67}
!67 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !68, size: 64)
!68 = !DIDerivedType(tag: DW_TAG_const_type, baseType: !4)
!69 = !DILocalVariable(name: "data", arg: 1, scope: !64, file: !2, line: 102, type: !67)
!70 = !DILocation(line: 102, column: 26, scope: !64)
!71 = !DILocalVariable(name: "bio", scope: !64, file: !2, line: 103, type: !72)
!72 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !73, size: 64)
!73 = !DIDerivedType(tag: DW_TAG_typedef, name: "BIO", file: !2, line: 21, baseType: !74)
!74 = !DICompositeType(tag: DW_TAG_structure_type, name: "BIO", file: !2, line: 21, flags: DIFlagFwdDecl)
!75 = !DILocation(line: 103, column: 10, scope: !64)
!76 = !DILocation(line: 103, column: 24, scope: !64)
!77 = !DILocation(line: 103, column: 16, scope: !64)
!78 = !DILocation(line: 104, column: 15, scope: !64)
!79 = !DILocation(line: 104, column: 20, scope: !64)
!80 = !DILocation(line: 104, column: 33, scope: !64)
!81 = !DILocation(line: 104, column: 26, scope: !64)
!82 = !DILocation(line: 104, column: 5, scope: !64)
!83 = !DILocation(line: 107, column: 5, scope: !64)
!84 = distinct !DISubprogram(name: "rsa_key_leak", scope: !2, file: !2, line: 111, type: !85, scopeLine: 111, spFlags: DISPFlagDefinition, unit: !27, retainedNodes: !47)
!85 = !DISubroutineType(types: !86)
!86 = !{!44}
!87 = !DILocalVariable(name: "rsa", scope: !84, file: !2, line: 112, type: !88)
!88 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !89, size: 64)
!89 = !DIDerivedType(tag: DW_TAG_typedef, name: "RSA", file: !2, line: 22, baseType: !90)
!90 = !DICompositeType(tag: DW_TAG_structure_type, name: "RSA", file: !2, line: 22, flags: DIFlagFwdDecl)
!91 = !DILocation(line: 112, column: 10, scope: !84)
!92 = !DILocation(line: 112, column: 16, scope: !84)
!93 = !DILocalVariable(name: "bn", scope: !84, file: !2, line: 113, type: !94)
!94 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !95, size: 64)
!95 = !DIDerivedType(tag: DW_TAG_typedef, name: "BIGNUM", file: !2, line: 23, baseType: !96)
!96 = !DICompositeType(tag: DW_TAG_structure_type, name: "BIGNUM", file: !2, line: 23, flags: DIFlagFwdDecl)
!97 = !DILocation(line: 113, column: 13, scope: !84)
!98 = !DILocation(line: 113, column: 18, scope: !84)
!99 = !DILocation(line: 114, column: 17, scope: !84)
!100 = !DILocation(line: 114, column: 5, scope: !84)
!101 = !DILocation(line: 116, column: 25, scope: !84)
!102 = !DILocation(line: 116, column: 36, scope: !84)
!103 = !DILocation(line: 116, column: 5, scope: !84)
!104 = !DILocation(line: 119, column: 13, scope: !84)
!105 = !DILocation(line: 119, column: 5, scope: !84)
!106 = !DILocation(line: 120, column: 5, scope: !84)
!107 = distinct !DISubprogram(name: "encrypt_unchecked", scope: !2, file: !2, line: 124, type: !108, scopeLine: 124, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !27, retainedNodes: !47)
!108 = !DISubroutineType(types: !109)
!109 = !{!44, !31, !45}
!110 = !DILocalVariable(name: "ciphertext", arg: 1, scope: !107, file: !2, line: 124, type: !31)
!111 = !DILocation(line: 124, column: 38, scope: !107)
!112 = !DILocalVariable(name: "plaintext", arg: 2, scope: !107, file: !2, line: 124, type: !45)
!113 = !DILocation(line: 124, column: 71, scope: !107)
!114 = !DILocalVariable(name: "ctx", scope: !107, file: !2, line: 125, type: !53)
!115 = !DILocation(line: 125, column: 21, scope: !107)
!116 = !DILocation(line: 125, column: 27, scope: !107)
!117 = !DILocalVariable(name: "key", scope: !107, file: !2, line: 127, type: !118)
!118 = !DICompositeType(tag: DW_TAG_array_type, baseType: !32, size: 128, elements: !25)
!119 = !DILocation(line: 127, column: 19, scope: !107)
!120 = !DILocalVariable(name: "iv", scope: !107, file: !2, line: 128, type: !118)
!121 = !DILocation(line: 128, column: 19, scope: !107)
!122 = !DILocation(line: 131, column: 24, scope: !107)
!123 = !DILocation(line: 131, column: 29, scope: !107)
!124 = !DILocation(line: 131, column: 54, scope: !107)
!125 = !DILocation(line: 131, column: 59, scope: !107)
!126 = !DILocation(line: 131, column: 5, scope: !107)
!127 = !DILocalVariable(name: "len", scope: !107, file: !2, line: 133, type: !44)
!128 = !DILocation(line: 133, column: 9, scope: !107)
!129 = !DILocation(line: 134, column: 23, scope: !107)
!130 = !DILocation(line: 134, column: 28, scope: !107)
!131 = !DILocation(line: 134, column: 46, scope: !107)
!132 = !DILocation(line: 134, column: 5, scope: !107)
!133 = !DILocation(line: 136, column: 25, scope: !107)
!134 = !DILocation(line: 136, column: 5, scope: !107)
!135 = !DILocation(line: 137, column: 5, scope: !107)
!136 = distinct !DISubprogram(name: "weak_random", scope: !2, file: !2, line: 141, type: !137, scopeLine: 141, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !27, retainedNodes: !47)
!137 = !DISubroutineType(types: !138)
!138 = !{!44, !31, !44}
!139 = !DILocalVariable(name: "buf", arg: 1, scope: !136, file: !2, line: 141, type: !31)
!140 = !DILocation(line: 141, column: 32, scope: !136)
!141 = !DILocalVariable(name: "len", arg: 2, scope: !136, file: !2, line: 141, type: !44)
!142 = !DILocation(line: 141, column: 41, scope: !136)
!143 = !DILocalVariable(name: "seed", scope: !136, file: !2, line: 143, type: !118)
!144 = !DILocation(line: 143, column: 19, scope: !136)
!145 = !DILocation(line: 145, column: 15, scope: !136)
!146 = !DILocation(line: 145, column: 5, scope: !136)
!147 = !DILocation(line: 147, column: 16, scope: !136)
!148 = !DILocation(line: 147, column: 21, scope: !136)
!149 = !DILocation(line: 147, column: 5, scope: !136)
!150 = !DILocation(line: 148, column: 5, scope: !136)
!151 = distinct !DISubprogram(name: "password_handling", scope: !2, file: !2, line: 152, type: !65, scopeLine: 152, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !27, retainedNodes: !47)
!152 = !DILocalVariable(name: "password", arg: 1, scope: !151, file: !2, line: 152, type: !67)
!153 = !DILocation(line: 152, column: 35, scope: !151)
!154 = !DILocalVariable(name: "pwd", scope: !151, file: !2, line: 153, type: !155)
!155 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 512, elements: !156)
!156 = !{!157}
!157 = !DISubrange(count: 64)
!158 = !DILocation(line: 153, column: 10, scope: !151)
!159 = !DILocation(line: 154, column: 5, scope: !151)
!160 = !DILocation(line: 155, column: 5, scope: !151)
!161 = !DILocation(line: 155, column: 26, scope: !151)
!162 = !DILocation(line: 158, column: 36, scope: !151)
!163 = !DILocation(line: 158, column: 5, scope: !151)
!164 = !DILocation(line: 162, column: 5, scope: !151)
!165 = distinct !DISubprogram(name: "ssl_ctx_leak", scope: !2, file: !2, line: 166, type: !85, scopeLine: 166, spFlags: DISPFlagDefinition, unit: !27, retainedNodes: !47)
!166 = !DILocalVariable(name: "ctx", scope: !165, file: !2, line: 167, type: !167)
!167 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !168, size: 64)
!168 = !DIDerivedType(tag: DW_TAG_typedef, name: "SSL_CTX", file: !2, line: 26, baseType: !169)
!169 = !DICompositeType(tag: DW_TAG_structure_type, name: "SSL_CTX", file: !2, line: 26, flags: DIFlagFwdDecl)
!170 = !DILocation(line: 167, column: 14, scope: !165)
!171 = !DILocation(line: 167, column: 32, scope: !165)
!172 = !DILocation(line: 167, column: 20, scope: !165)
!173 = !DILocation(line: 168, column: 10, scope: !174)
!174 = distinct !DILexicalBlock(scope: !165, file: !2, line: 168, column: 9)
!175 = !DILocation(line: 168, column: 9, scope: !174)
!176 = !DILocation(line: 168, column: 15, scope: !174)
!177 = !DILocation(line: 173, column: 5, scope: !165)
!178 = !DILocation(line: 174, column: 1, scope: !165)
!179 = distinct !DISubprogram(name: "x509_leak", scope: !2, file: !2, line: 177, type: !85, scopeLine: 177, spFlags: DISPFlagDefinition, unit: !27, retainedNodes: !47)
!180 = !DILocalVariable(name: "cert", scope: !179, file: !2, line: 178, type: !181)
!181 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !182, size: 64)
!182 = !DIDerivedType(tag: DW_TAG_typedef, name: "X509", file: !2, line: 27, baseType: !183)
!183 = !DICompositeType(tag: DW_TAG_structure_type, name: "X509", file: !2, line: 27, flags: DIFlagFwdDecl)
!184 = !DILocation(line: 178, column: 11, scope: !179)
!185 = !DILocation(line: 178, column: 18, scope: !179)
!186 = !DILocation(line: 179, column: 10, scope: !187)
!187 = distinct !DILexicalBlock(scope: !179, file: !2, line: 179, column: 9)
!188 = !DILocation(line: 179, column: 9, scope: !187)
!189 = !DILocation(line: 179, column: 16, scope: !187)
!190 = !DILocation(line: 184, column: 5, scope: !179)
!191 = !DILocation(line: 185, column: 1, scope: !179)
!192 = distinct !DISubprogram(name: "unprotected_key", scope: !2, file: !2, line: 188, type: !85, scopeLine: 188, spFlags: DISPFlagDefinition, unit: !27, retainedNodes: !47)
!193 = !DILocalVariable(name: "pkey", scope: !192, file: !2, line: 189, type: !194)
!194 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !195, size: 64)
!195 = !DIDerivedType(tag: DW_TAG_typedef, name: "EVP_PKEY", file: !2, line: 24, baseType: !196)
!196 = !DICompositeType(tag: DW_TAG_structure_type, name: "EVP_PKEY", file: !2, line: 24, flags: DIFlagFwdDecl)
!197 = !DILocation(line: 189, column: 15, scope: !192)
!198 = !DILocalVariable(name: "ctx", scope: !192, file: !2, line: 190, type: !199)
!199 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !200, size: 64)
!200 = !DIDerivedType(tag: DW_TAG_typedef, name: "EVP_PKEY_CTX", file: !2, line: 25, baseType: !201)
!201 = !DICompositeType(tag: DW_TAG_structure_type, name: "EVP_PKEY_CTX", file: !2, line: 25, flags: DIFlagFwdDecl)
!202 = !DILocation(line: 190, column: 19, scope: !192)
!203 = !DILocation(line: 190, column: 25, scope: !192)
!204 = !DILocation(line: 192, column: 26, scope: !192)
!205 = !DILocation(line: 192, column: 5, scope: !192)
!206 = !DILocation(line: 193, column: 38, scope: !192)
!207 = !DILocation(line: 193, column: 5, scope: !192)
!208 = !DILocation(line: 194, column: 21, scope: !192)
!209 = !DILocation(line: 194, column: 5, scope: !192)
!210 = !DILocation(line: 198, column: 23, scope: !192)
!211 = !DILocation(line: 198, column: 5, scope: !192)
!212 = !DILocation(line: 199, column: 19, scope: !192)
!213 = !DILocation(line: 199, column: 5, scope: !192)
!214 = !DILocation(line: 200, column: 5, scope: !192)
!215 = distinct !DISubprogram(name: "error_handling_bug", scope: !2, file: !2, line: 204, type: !65, scopeLine: 204, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !27, retainedNodes: !47)
!216 = !DILocalVariable(name: "cert_path", arg: 1, scope: !215, file: !2, line: 204, type: !67)
!217 = !DILocation(line: 204, column: 36, scope: !215)
!218 = !DILocalVariable(name: "bio", scope: !215, file: !2, line: 205, type: !72)
!219 = !DILocation(line: 205, column: 10, scope: !215)
!220 = !DILocation(line: 205, column: 29, scope: !215)
!221 = !DILocation(line: 205, column: 16, scope: !215)
!222 = !DILocation(line: 206, column: 10, scope: !223)
!223 = distinct !DILexicalBlock(scope: !215, file: !2, line: 206, column: 9)
!224 = !DILocation(line: 206, column: 9, scope: !223)
!225 = !DILocation(line: 208, column: 29, scope: !226)
!226 = distinct !DILexicalBlock(scope: !223, file: !2, line: 206, column: 15)
!227 = !DILocation(line: 208, column: 9, scope: !226)
!228 = !DILocation(line: 209, column: 9, scope: !226)
!229 = !DILocalVariable(name: "cert", scope: !215, file: !2, line: 212, type: !181)
!230 = !DILocation(line: 212, column: 11, scope: !215)
!231 = !DILocation(line: 212, column: 36, scope: !215)
!232 = !DILocation(line: 212, column: 18, scope: !215)
!233 = !DILocation(line: 213, column: 10, scope: !234)
!234 = distinct !DILexicalBlock(scope: !215, file: !2, line: 213, column: 9)
!235 = !DILocation(line: 213, column: 9, scope: !234)
!236 = !DILocation(line: 215, column: 29, scope: !237)
!237 = distinct !DILexicalBlock(scope: !234, file: !2, line: 213, column: 16)
!238 = !DILocation(line: 215, column: 9, scope: !237)
!239 = !DILocation(line: 216, column: 9, scope: !237)
!240 = !DILocation(line: 219, column: 14, scope: !215)
!241 = !DILocation(line: 219, column: 5, scope: !215)
!242 = !DILocation(line: 220, column: 15, scope: !215)
!243 = !DILocation(line: 220, column: 5, scope: !215)
!244 = !DILocation(line: 221, column: 5, scope: !215)
!245 = !DILocation(line: 222, column: 1, scope: !215)
!246 = distinct !DISubprogram(name: "correct_encryption", scope: !2, file: !2, line: 225, type: !247, scopeLine: 226, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !27, retainedNodes: !47)
!247 = !DISubroutineType(types: !248)
!248 = !{!44, !45, !44, !31, !45}
!249 = !DILocalVariable(name: "plaintext", arg: 1, scope: !246, file: !2, line: 225, type: !45)
!250 = !DILocation(line: 225, column: 45, scope: !246)
!251 = !DILocalVariable(name: "len", arg: 2, scope: !246, file: !2, line: 225, type: !44)
!252 = !DILocation(line: 225, column: 60, scope: !246)
!253 = !DILocalVariable(name: "ciphertext", arg: 3, scope: !246, file: !2, line: 226, type: !31)
!254 = !DILocation(line: 226, column: 39, scope: !246)
!255 = !DILocalVariable(name: "key", arg: 4, scope: !246, file: !2, line: 226, type: !45)
!256 = !DILocation(line: 226, column: 72, scope: !246)
!257 = !DILocalVariable(name: "ctx", scope: !246, file: !2, line: 227, type: !53)
!258 = !DILocation(line: 227, column: 21, scope: !246)
!259 = !DILocation(line: 227, column: 27, scope: !246)
!260 = !DILocation(line: 228, column: 10, scope: !261)
!261 = distinct !DILexicalBlock(scope: !246, file: !2, line: 228, column: 9)
!262 = !DILocation(line: 228, column: 9, scope: !261)
!263 = !DILocation(line: 228, column: 15, scope: !261)
!264 = !DILocalVariable(name: "iv", scope: !246, file: !2, line: 230, type: !118)
!265 = !DILocation(line: 230, column: 19, scope: !246)
!266 = !DILocation(line: 231, column: 20, scope: !267)
!267 = distinct !DILexicalBlock(scope: !246, file: !2, line: 231, column: 9)
!268 = !DILocation(line: 231, column: 9, scope: !267)
!269 = !DILocation(line: 231, column: 28, scope: !267)
!270 = !DILocation(line: 232, column: 29, scope: !271)
!271 = distinct !DILexicalBlock(scope: !267, file: !2, line: 231, column: 34)
!272 = !DILocation(line: 232, column: 9, scope: !271)
!273 = !DILocation(line: 233, column: 9, scope: !271)
!274 = !DILocation(line: 236, column: 28, scope: !275)
!275 = distinct !DILexicalBlock(scope: !246, file: !2, line: 236, column: 9)
!276 = !DILocation(line: 236, column: 33, scope: !275)
!277 = !DILocation(line: 236, column: 58, scope: !275)
!278 = !DILocation(line: 236, column: 63, scope: !275)
!279 = !DILocation(line: 236, column: 9, scope: !275)
!280 = !DILocation(line: 236, column: 67, scope: !275)
!281 = !DILocation(line: 237, column: 29, scope: !282)
!282 = distinct !DILexicalBlock(scope: !275, file: !2, line: 236, column: 73)
!283 = !DILocation(line: 237, column: 9, scope: !282)
!284 = !DILocation(line: 238, column: 9, scope: !282)
!285 = !DILocalVariable(name: "out_len", scope: !246, file: !2, line: 241, type: !44)
!286 = !DILocation(line: 241, column: 9, scope: !246)
!287 = !DILocation(line: 242, column: 27, scope: !288)
!288 = distinct !DILexicalBlock(scope: !246, file: !2, line: 242, column: 9)
!289 = !DILocation(line: 242, column: 32, scope: !288)
!290 = !DILocation(line: 242, column: 54, scope: !288)
!291 = !DILocation(line: 242, column: 65, scope: !288)
!292 = !DILocation(line: 242, column: 9, scope: !288)
!293 = !DILocation(line: 242, column: 70, scope: !288)
!294 = !DILocation(line: 243, column: 29, scope: !295)
!295 = distinct !DILexicalBlock(scope: !288, file: !2, line: 242, column: 76)
!296 = !DILocation(line: 243, column: 9, scope: !295)
!297 = !DILocation(line: 244, column: 9, scope: !295)
!298 = !DILocalVariable(name: "final_len", scope: !246, file: !2, line: 247, type: !44)
!299 = !DILocation(line: 247, column: 9, scope: !246)
!300 = !DILocation(line: 248, column: 29, scope: !301)
!301 = distinct !DILexicalBlock(scope: !246, file: !2, line: 248, column: 9)
!302 = !DILocation(line: 248, column: 34, scope: !301)
!303 = !DILocation(line: 248, column: 47, scope: !301)
!304 = !DILocation(line: 248, column: 45, scope: !301)
!305 = !DILocation(line: 248, column: 9, scope: !301)
!306 = !DILocation(line: 248, column: 68, scope: !301)
!307 = !DILocation(line: 249, column: 29, scope: !308)
!308 = distinct !DILexicalBlock(scope: !301, file: !2, line: 248, column: 74)
!309 = !DILocation(line: 249, column: 9, scope: !308)
!310 = !DILocation(line: 250, column: 9, scope: !308)
!311 = !DILocation(line: 253, column: 25, scope: !246)
!312 = !DILocation(line: 253, column: 5, scope: !246)
!313 = !DILocation(line: 254, column: 12, scope: !246)
!314 = !DILocation(line: 254, column: 22, scope: !246)
!315 = !DILocation(line: 254, column: 20, scope: !246)
!316 = !DILocation(line: 254, column: 5, scope: !246)
!317 = !DILocation(line: 255, column: 1, scope: !246)
!318 = distinct !DISubprogram(name: "main", scope: !2, file: !2, line: 257, type: !85, scopeLine: 257, spFlags: DISPFlagDefinition, unit: !27, retainedNodes: !47)
!319 = !DILocation(line: 258, column: 5, scope: !318)
!320 = !DILocation(line: 259, column: 5, scope: !318)
!321 = !DILocation(line: 262, column: 5, scope: !318)
!322 = !DILocation(line: 263, column: 5, scope: !318)
!323 = !DILocation(line: 264, column: 5, scope: !318)
!324 = !DILocation(line: 265, column: 5, scope: !318)
!325 = !DILocalVariable(name: "buf", scope: !318, file: !2, line: 267, type: !118)
!326 = !DILocation(line: 267, column: 19, scope: !318)
!327 = !DILocation(line: 268, column: 17, scope: !318)
!328 = !DILocation(line: 268, column: 5, scope: !318)
!329 = !DILocation(line: 269, column: 5, scope: !318)
!330 = !DILocation(line: 271, column: 5, scope: !318)
!331 = !DILocation(line: 272, column: 5, scope: !318)
!332 = !DILocation(line: 273, column: 5, scope: !318)
