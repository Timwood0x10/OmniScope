; ModuleID = 'zlib_binding.c'
source_filename = "zlib_binding.c"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx15.0.0"

%struct.z_stream_s = type { ptr, i32, i64, ptr, i32, i64, ptr, ptr, ptr, ptr, ptr, i32, i64, i64 }

@.str = private unnamed_addr constant [7 x i8] c"1.2.12\00", align 1
@.str.1 = private unnamed_addr constant [22 x i8] c"Compressed size: %lu\0A\00", align 1
@.str.2 = private unnamed_addr constant [3 x i8] c"wb\00", align 1
@.str.3 = private unnamed_addr constant [3 x i8] c"rb\00", align 1
@.str.4 = private unnamed_addr constant [10 x i8] c"Read: %s\0A\00", align 1
@.str.5 = private unnamed_addr constant [53 x i8] c"Hello, World! This is a test string for compression.\00", align 1
@.str.6 = private unnamed_addr constant [13 x i8] c"/tmp/test.gz\00", align 1

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @inflate_leak(ptr noundef %compressed, i32 noundef %len) #0 {
entry:
  %compressed.addr = alloca ptr, align 8
  %len.addr = alloca i32, align 4
  %strm = alloca %struct.z_stream_s, align 8
  store ptr %compressed, ptr %compressed.addr, align 8
  store i32 %len, ptr %len.addr, align 4
  call void @llvm.memset.p0.i64(ptr align 8 %strm, i8 0, i64 112, i1 false)
  %call = call i32 @inflateInit_(ptr noundef %strm, ptr noundef @.str, i32 noundef 112)
  %0 = load ptr, ptr %compressed.addr, align 8
  %next_in = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 0
  store ptr %0, ptr %next_in, align 8
  %1 = load i32, ptr %len.addr, align 4
  %avail_in = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 1
  store i32 %1, ptr %avail_in, align 8
  ret i32 0
}

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: write)
declare void @llvm.memset.p0.i64(ptr writeonly captures(none), i8, i64, i1 immarg) #1

declare i32 @inflateInit_(ptr noundef, ptr noundef, i32 noundef) #2

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @deflate_leak(ptr noundef %data, i32 noundef %len) #0 {
entry:
  %data.addr = alloca ptr, align 8
  %len.addr = alloca i32, align 4
  %strm = alloca %struct.z_stream_s, align 8
  store ptr %data, ptr %data.addr, align 8
  store i32 %len, ptr %len.addr, align 4
  call void @llvm.memset.p0.i64(ptr align 8 %strm, i8 0, i64 112, i1 false)
  %call = call i32 @deflateInit_(ptr noundef %strm, i32 noundef -1, ptr noundef @.str, i32 noundef 112)
  %0 = load ptr, ptr %data.addr, align 8
  %next_in = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 0
  store ptr %0, ptr %next_in, align 8
  %1 = load i32, ptr %len.addr, align 4
  %avail_in = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 1
  store i32 %1, ptr %avail_in, align 8
  ret i32 0
}

declare i32 @deflateInit_(ptr noundef, i32 noundef, ptr noundef, i32 noundef) #2

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @compress_overflow(ptr noundef %output, ptr noundef %input, i32 noundef %input_len) #0 {
entry:
  %output.addr = alloca ptr, align 8
  %input.addr = alloca ptr, align 8
  %input_len.addr = alloca i32, align 4
  %output_len = alloca i64, align 8
  store ptr %output, ptr %output.addr, align 8
  store ptr %input, ptr %input.addr, align 8
  store i32 %input_len, ptr %input_len.addr, align 4
  store i64 1024, ptr %output_len, align 8
  %0 = load ptr, ptr %output.addr, align 8
  %1 = load ptr, ptr %input.addr, align 8
  %2 = load i32, ptr %input_len.addr, align 4
  %conv = sext i32 %2 to i64
  %call = call i32 @compress(ptr noundef %0, ptr noundef %output_len, ptr noundef %1, i64 noundef %conv)
  %3 = load i64, ptr %output_len, align 8
  %conv1 = trunc i64 %3 to i32
  ret i32 %conv1
}

declare i32 @compress(ptr noundef, ptr noundef, ptr noundef, i64 noundef) #2

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @use_after_free_example(ptr noundef %data) #0 {
entry:
  %data.addr = alloca ptr, align 8
  %source_len = alloca i64, align 8
  %dest_len = alloca i64, align 8
  %dest = alloca ptr, align 8
  store ptr %data, ptr %data.addr, align 8
  %0 = load ptr, ptr %data.addr, align 8
  %call = call i64 @strlen(ptr noundef %0) #5
  store i64 %call, ptr %source_len, align 8
  %1 = load i64, ptr %source_len, align 8
  %call1 = call i64 @compressBound(i64 noundef %1)
  store i64 %call1, ptr %dest_len, align 8
  %2 = load i64, ptr %dest_len, align 8
  %call2 = call ptr @malloc(i64 noundef %2) #6
  store ptr %call2, ptr %dest, align 8
  %3 = load ptr, ptr %dest, align 8
  %4 = load ptr, ptr %data.addr, align 8
  %5 = load i64, ptr %source_len, align 8
  %call3 = call i32 @compress(ptr noundef %3, ptr noundef %dest_len, ptr noundef %4, i64 noundef %5)
  %6 = load ptr, ptr %dest, align 8
  call void @free(ptr noundef %6)
  %7 = load i64, ptr %dest_len, align 8
  %call4 = call i32 (ptr, ...) @printf(ptr noundef @.str.1, i64 noundef %7)
  ret i32 0
}

; Function Attrs: nounwind
declare i64 @strlen(ptr noundef) #3

declare i64 @compressBound(i64 noundef) #2

; Function Attrs: allocsize(0)
declare ptr @malloc(i64 noundef) #4

declare void @free(ptr noundef) #2

declare i32 @printf(ptr noundef, ...) #2

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @double_free_example(ptr noundef %data, i32 noundef %len) #0 {
entry:
  %data.addr = alloca ptr, align 8
  %len.addr = alloca i32, align 4
  %strm = alloca %struct.z_stream_s, align 8
  store ptr %data, ptr %data.addr, align 8
  store i32 %len, ptr %len.addr, align 4
  call void @llvm.memset.p0.i64(ptr align 8 %strm, i8 0, i64 112, i1 false)
  %call = call i32 @inflateInit_(ptr noundef %strm, ptr noundef @.str, i32 noundef 112)
  %call1 = call ptr @malloc(i64 noundef 1024) #6
  %next_out = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 3
  store ptr %call1, ptr %next_out, align 8
  %avail_out = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 4
  store i32 1024, ptr %avail_out, align 8
  %0 = load ptr, ptr %data.addr, align 8
  %next_in = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 0
  store ptr %0, ptr %next_in, align 8
  %1 = load i32, ptr %len.addr, align 4
  %avail_in = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 1
  store i32 %1, ptr %avail_in, align 8
  %call2 = call i32 @inflate(ptr noundef %strm, i32 noundef 0)
  %next_out3 = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 3
  %2 = load ptr, ptr %next_out3, align 8
  call void @free(ptr noundef %2)
  %call4 = call i32 @inflateEnd(ptr noundef %strm)
  ret i32 0
}

declare i32 @inflate(ptr noundef, i32 noundef) #2

declare i32 @inflateEnd(ptr noundef) #2

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @uninit_stream_example(ptr noundef %data, i32 noundef %len) #0 {
entry:
  %data.addr = alloca ptr, align 8
  %len.addr = alloca i32, align 4
  %strm = alloca %struct.z_stream_s, align 8
  store ptr %data, ptr %data.addr, align 8
  store i32 %len, ptr %len.addr, align 4
  %call = call i32 @inflateInit_(ptr noundef %strm, ptr noundef @.str, i32 noundef 112)
  %0 = load ptr, ptr %data.addr, align 8
  %next_in = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 0
  store ptr %0, ptr %next_in, align 8
  %1 = load i32, ptr %len.addr, align 4
  %avail_in = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 1
  store i32 %1, ptr %avail_in, align 8
  %call1 = call i32 @inflateEnd(ptr noundef %strm)
  ret i32 0
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @error_path_leak(ptr noundef %data, i32 noundef %len) #0 {
entry:
  %retval = alloca i32, align 4
  %data.addr = alloca ptr, align 8
  %len.addr = alloca i32, align 4
  %strm = alloca %struct.z_stream_s, align 8
  %output = alloca ptr, align 8
  store ptr %data, ptr %data.addr, align 8
  store i32 %len, ptr %len.addr, align 4
  call void @llvm.memset.p0.i64(ptr align 8 %strm, i8 0, i64 112, i1 false)
  %call = call i32 @deflateInit_(ptr noundef %strm, i32 noundef -1, ptr noundef @.str, i32 noundef 112)
  %cmp = icmp ne i32 %call, 0
  br i1 %cmp, label %if.then, label %if.end

if.then:                                          ; preds = %entry
  store i32 -1, ptr %retval, align 4
  br label %return

if.end:                                           ; preds = %entry
  %0 = load i32, ptr %len.addr, align 4
  %conv = sext i32 %0 to i64
  %call1 = call i64 @compressBound(i64 noundef %conv)
  %call2 = call ptr @malloc(i64 noundef %call1) #6
  store ptr %call2, ptr %output, align 8
  %1 = load ptr, ptr %output, align 8
  %tobool = icmp ne ptr %1, null
  br i1 %tobool, label %if.end4, label %if.then3

if.then3:                                         ; preds = %if.end
  store i32 -1, ptr %retval, align 4
  br label %return

if.end4:                                          ; preds = %if.end
  %2 = load ptr, ptr %data.addr, align 8
  %next_in = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 0
  store ptr %2, ptr %next_in, align 8
  %3 = load i32, ptr %len.addr, align 4
  %avail_in = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 1
  store i32 %3, ptr %avail_in, align 8
  %4 = load ptr, ptr %output, align 8
  %next_out = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 3
  store ptr %4, ptr %next_out, align 8
  %5 = load i32, ptr %len.addr, align 4
  %conv5 = sext i32 %5 to i64
  %call6 = call i64 @compressBound(i64 noundef %conv5)
  %conv7 = trunc i64 %call6 to i32
  %avail_out = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 4
  store i32 %conv7, ptr %avail_out, align 8
  %call8 = call i32 @deflate(ptr noundef %strm, i32 noundef 4)
  %call9 = call i32 @deflateEnd(ptr noundef %strm)
  %6 = load ptr, ptr %output, align 8
  call void @free(ptr noundef %6)
  store i32 0, ptr %retval, align 4
  br label %return

return:                                           ; preds = %if.end4, %if.then3, %if.then
  %7 = load i32, ptr %retval, align 4
  ret i32 %7
}

declare i32 @deflate(ptr noundef, i32 noundef) #2

declare i32 @deflateEnd(ptr noundef) #2

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @gzfile_leak(ptr noundef %path, ptr noundef %data) #0 {
entry:
  %retval = alloca i32, align 4
  %path.addr = alloca ptr, align 8
  %data.addr = alloca ptr, align 8
  %file = alloca ptr, align 8
  store ptr %path, ptr %path.addr, align 8
  store ptr %data, ptr %data.addr, align 8
  %0 = load ptr, ptr %path.addr, align 8
  %call = call ptr @gzopen(ptr noundef %0, ptr noundef @.str.2)
  store ptr %call, ptr %file, align 8
  %1 = load ptr, ptr %file, align 8
  %tobool = icmp ne ptr %1, null
  br i1 %tobool, label %if.end, label %if.then

if.then:                                          ; preds = %entry
  store i32 -1, ptr %retval, align 4
  br label %return

if.end:                                           ; preds = %entry
  %2 = load ptr, ptr %file, align 8
  %3 = load ptr, ptr %data.addr, align 8
  %4 = load ptr, ptr %data.addr, align 8
  %call1 = call i64 @strlen(ptr noundef %4) #5
  %conv = trunc i64 %call1 to i32
  %call2 = call i32 @gzwrite(ptr noundef %2, ptr noundef %3, i32 noundef %conv)
  store i32 0, ptr %retval, align 4
  br label %return

return:                                           ; preds = %if.end, %if.then
  %5 = load i32, ptr %retval, align 4
  ret i32 %5
}

declare ptr @gzopen(ptr noundef, ptr noundef) #2

declare i32 @gzwrite(ptr noundef, ptr noundef, i32 noundef) #2

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @unchecked_gzread(ptr noundef %path) #0 {
entry:
  %retval = alloca i32, align 4
  %path.addr = alloca ptr, align 8
  %file = alloca ptr, align 8
  %buffer = alloca [1024 x i8], align 1
  store ptr %path, ptr %path.addr, align 8
  %0 = load ptr, ptr %path.addr, align 8
  %call = call ptr @gzopen(ptr noundef %0, ptr noundef @.str.3)
  store ptr %call, ptr %file, align 8
  %1 = load ptr, ptr %file, align 8
  %tobool = icmp ne ptr %1, null
  br i1 %tobool, label %if.end, label %if.then

if.then:                                          ; preds = %entry
  store i32 -1, ptr %retval, align 4
  br label %return

if.end:                                           ; preds = %entry
  %2 = load ptr, ptr %file, align 8
  %arraydecay = getelementptr inbounds [1024 x i8], ptr %buffer, i64 0, i64 0
  %call1 = call i32 @gzread(ptr noundef %2, ptr noundef %arraydecay, i32 noundef 1024)
  %arraydecay2 = getelementptr inbounds [1024 x i8], ptr %buffer, i64 0, i64 0
  %call3 = call i32 (ptr, ...) @printf(ptr noundef @.str.4, ptr noundef %arraydecay2)
  %3 = load ptr, ptr %file, align 8
  %call4 = call i32 @gzclose(ptr noundef %3)
  store i32 0, ptr %retval, align 4
  br label %return

return:                                           ; preds = %if.end, %if.then
  %4 = load i32, ptr %retval, align 4
  ret i32 %4
}

declare i32 @gzread(ptr noundef, ptr noundef, i32 noundef) #2

declare i32 @gzclose(ptr noundef) #2

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @invalid_compression_level(ptr noundef %data, i32 noundef %len) #0 {
entry:
  %retval = alloca i32, align 4
  %data.addr = alloca ptr, align 8
  %len.addr = alloca i32, align 4
  %strm = alloca %struct.z_stream_s, align 8
  %result = alloca i32, align 4
  store ptr %data, ptr %data.addr, align 8
  store i32 %len, ptr %len.addr, align 4
  call void @llvm.memset.p0.i64(ptr align 8 %strm, i8 0, i64 112, i1 false)
  %call = call i32 @deflateInit_(ptr noundef %strm, i32 noundef 100, ptr noundef @.str, i32 noundef 112)
  store i32 %call, ptr %result, align 4
  %0 = load i32, ptr %result, align 4
  %cmp = icmp ne i32 %0, 0
  br i1 %cmp, label %if.then, label %if.end

if.then:                                          ; preds = %entry
  store i32 -1, ptr %retval, align 4
  br label %return

if.end:                                           ; preds = %entry
  %call1 = call i32 @deflateEnd(ptr noundef %strm)
  store i32 0, ptr %retval, align 4
  br label %return

return:                                           ; preds = %if.end, %if.then
  %1 = load i32, ptr %retval, align 4
  ret i32 %1
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @correct_compress(ptr noundef %input, i32 noundef %input_len, ptr noundef %output, ptr noundef %output_len) #0 {
entry:
  %retval = alloca i32, align 4
  %input.addr = alloca ptr, align 8
  %input_len.addr = alloca i32, align 4
  %output.addr = alloca ptr, align 8
  %output_len.addr = alloca ptr, align 8
  %strm = alloca %struct.z_stream_s, align 8
  %bound = alloca i64, align 8
  %ret = alloca i32, align 4
  store ptr %input, ptr %input.addr, align 8
  store i32 %input_len, ptr %input_len.addr, align 4
  store ptr %output, ptr %output.addr, align 8
  store ptr %output_len, ptr %output_len.addr, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %strm, i8 0, i64 112, i1 false)
  %call = call i32 @deflateInit_(ptr noundef %strm, i32 noundef -1, ptr noundef @.str, i32 noundef 112)
  %cmp = icmp ne i32 %call, 0
  br i1 %cmp, label %if.then, label %if.end

if.then:                                          ; preds = %entry
  store i32 -1, ptr %retval, align 4
  br label %return

if.end:                                           ; preds = %entry
  %0 = load i32, ptr %input_len.addr, align 4
  %conv = sext i32 %0 to i64
  %call1 = call i64 @compressBound(i64 noundef %conv)
  store i64 %call1, ptr %bound, align 8
  %1 = load ptr, ptr %input.addr, align 8
  %next_in = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 0
  store ptr %1, ptr %next_in, align 8
  %2 = load i32, ptr %input_len.addr, align 4
  %avail_in = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 1
  store i32 %2, ptr %avail_in, align 8
  %3 = load ptr, ptr %output.addr, align 8
  %next_out = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 3
  store ptr %3, ptr %next_out, align 8
  %4 = load i64, ptr %bound, align 8
  %conv2 = trunc i64 %4 to i32
  %avail_out = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 4
  store i32 %conv2, ptr %avail_out, align 8
  %call3 = call i32 @deflate(ptr noundef %strm, i32 noundef 4)
  store i32 %call3, ptr %ret, align 4
  %5 = load i32, ptr %ret, align 4
  %cmp4 = icmp ne i32 %5, 1
  br i1 %cmp4, label %if.then6, label %if.end8

if.then6:                                         ; preds = %if.end
  %call7 = call i32 @deflateEnd(ptr noundef %strm)
  store i32 -1, ptr %retval, align 4
  br label %return

if.end8:                                          ; preds = %if.end
  %total_out = getelementptr inbounds nuw %struct.z_stream_s, ptr %strm, i32 0, i32 5
  %6 = load i64, ptr %total_out, align 8
  %conv9 = trunc i64 %6 to i32
  %7 = load ptr, ptr %output_len.addr, align 8
  store i32 %conv9, ptr %7, align 4
  %call10 = call i32 @deflateEnd(ptr noundef %strm)
  store i32 0, ptr %retval, align 4
  br label %return

return:                                           ; preds = %if.end8, %if.then6, %if.then
  %8 = load i32, ptr %retval, align 4
  ret i32 %8
}

; Function Attrs: noinline nounwind optnone ssp uwtable(sync)
define i32 @main() #0 {
entry:
  %retval = alloca i32, align 4
  %test_data = alloca ptr, align 8
  store i32 0, ptr %retval, align 4
  store ptr @.str.5, ptr %test_data, align 8
  %0 = load ptr, ptr %test_data, align 8
  %1 = load ptr, ptr %test_data, align 8
  %call = call i64 @strlen(ptr noundef %1) #5
  %conv = trunc i64 %call to i32
  %call1 = call i32 @inflate_leak(ptr noundef %0, i32 noundef %conv)
  %2 = load ptr, ptr %test_data, align 8
  %3 = load ptr, ptr %test_data, align 8
  %call2 = call i64 @strlen(ptr noundef %3) #5
  %conv3 = trunc i64 %call2 to i32
  %call4 = call i32 @deflate_leak(ptr noundef %2, i32 noundef %conv3)
  %4 = load ptr, ptr %test_data, align 8
  %call5 = call i32 @use_after_free_example(ptr noundef %4)
  %5 = load ptr, ptr %test_data, align 8
  %call6 = call i32 @gzfile_leak(ptr noundef @.str.6, ptr noundef %5)
  ret i32 0
}

attributes #0 = { noinline nounwind optnone ssp uwtable(sync) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #1 = { nocallback nofree nounwind willreturn memory(argmem: write) }
attributes #2 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #3 = { nounwind "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #4 = { allocsize(0) "frame-pointer"="non-leaf" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8a" }
attributes #5 = { nounwind }
attributes #6 = { allocsize(0) }

!llvm.module.flags = !{!0, !1, !2, !3}
!llvm.ident = !{!4}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 8, !"PIC Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 1}
!3 = !{i32 7, !"frame-pointer", i32 1}
!4 = !{!"Homebrew clang version 21.1.8"}
