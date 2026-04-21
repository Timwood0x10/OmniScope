// zlib FFI Binding Example
// Demonstrates common zlib API usage patterns with intentional bugs
//
// Expected issues:
// 1. inflateInit without inflateEnd (leak)
// 2. deflateInit without deflateEnd (leak)
// 3. Buffer overflow via unchecked sizes
// 4. Use after free on compressed data
// 5. Double free on z_stream

#include <zlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Bug 1: inflateInit without inflateEnd
int inflate_leak(const unsigned char* compressed, int len) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    
    inflateInit(&strm);
    
    strm.next_in = (Bytef*)compressed;
    strm.avail_in = len;
    
    // Missing: inflateEnd(&strm);
    return 0;  // Leak: inflate state not freed
}

// Bug 2: deflateInit without deflateEnd
int deflate_leak(const unsigned char* data, int len) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    
    deflateInit(&strm, Z_DEFAULT_COMPRESSION);
    
    strm.next_in = (Bytef*)data;
    strm.avail_in = len;
    
    // Missing: deflateEnd(&strm);
    return 0;  // Leak: deflate state not freed
}

// Bug 3: Buffer overflow - unchecked output buffer size
int compress_overflow(unsigned char* output, const unsigned char* input, int input_len) {
    uLongf output_len = 1024;  // Assume output is large enough
    
    // Bug: No check if output buffer is large enough
    // If input_len > output_len, this will overflow
    compress(output, &output_len, input, input_len);
    
    return output_len;
}

// Bug 4: Use after free
int use_after_free_example(const char* data) {
    uLong source_len = strlen(data);
    uLong dest_len = compressBound(source_len);
    
    Bytef* dest = malloc(dest_len);
    compress(dest, &dest_len, (const Bytef*)data, source_len);
    
    // Free the compressed data
    free(dest);
    
    // Bug: Using freed memory
    printf("Compressed size: %lu\n", dest_len);
    // dest is already freed but we might try to use it later
    
    return 0;
}

// Bug 5: Double free on z_stream internal buffer
int double_free_example(const unsigned char* data, int len) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    
    inflateInit(&strm);
    
    // Allocate internal buffer
    strm.next_out = malloc(1024);
    strm.avail_out = 1024;
    
    strm.next_in = (Bytef*)data;
    strm.avail_in = len;
    
    inflate(&strm, Z_NO_FLUSH);
    
    // Bug: Free the buffer manually
    free(strm.next_out);
    
    // Then inflateEnd tries to free it again if it was allocated by zlib
    inflateEnd(&strm);  // Potential double free
    
    return 0;
}

// Bug 6: Uninitialized z_stream
int uninit_stream_example(const unsigned char* data, int len) {
    z_stream strm;
    // Bug: strm not zeroed before use
    // Missing: memset(&strm, 0, sizeof(strm));
    
    // This may crash or behave unexpectedly
    inflateInit(&strm);
    
    strm.next_in = (Bytef*)data;
    strm.avail_in = len;
    
    inflateEnd(&strm);
    return 0;
}

// Bug 7: Memory leak on error path
int error_path_leak(const unsigned char* data, int len) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    
    if (deflateInit(&strm, Z_DEFAULT_COMPRESSION) != Z_OK) {
        return -1;
    }
    
    Bytef* output = malloc(compressBound(len));
    if (!output) {
        // Bug: deflateEnd not called on error path
        return -1;  // Leak: strm not cleaned up
    }
    
    strm.next_in = (Bytef*)data;
    strm.avail_in = len;
    strm.next_out = output;
    strm.avail_out = compressBound(len);
    
    deflate(&strm, Z_FINISH);
    deflateEnd(&strm);
    free(output);
    
    return 0;
}

// Bug 8: gzopen without gzclose
int gzfile_leak(const char* path, const char* data) {
    gzFile file = gzopen(path, "wb");
    if (!file) return -1;
    
    gzwrite(file, data, strlen(data));
    
    // Missing: gzclose(file);
    return 0;  // Leak: file not closed
}

// Bug 9: Unchecked gzread return value
int unchecked_gzread(const char* path) {
    gzFile file = gzopen(path, "rb");
    if (!file) return -1;
    
    char buffer[1024];
    // Bug: return value not checked
    gzread(file, buffer, sizeof(buffer));
    
    // buffer may contain garbage if read failed
    printf("Read: %s\n", buffer);
    
    gzclose(file);
    return 0;
}

// Bug 10: Compression level out of range
int invalid_compression_level(const unsigned char* data, int len) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    
    // Bug: Invalid compression level (valid: 0-9)
    int result = deflateInit(&strm, 100);
    
    if (result != Z_OK) {
        return -1;
    }
    
    deflateEnd(&strm);
    return 0;
}

// Correct pattern for reference
int correct_compress(const unsigned char* input, int input_len,
                     unsigned char* output, int* output_len) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    
    if (deflateInit(&strm, Z_DEFAULT_COMPRESSION) != Z_OK) {
        return -1;
    }
    
    uLong bound = compressBound(input_len);
    strm.next_in = (Bytef*)input;
    strm.avail_in = input_len;
    strm.next_out = output;
    strm.avail_out = bound;
    
    int ret = deflate(&strm, Z_FINISH);
    if (ret != Z_STREAM_END) {
        deflateEnd(&strm);
        return -1;
    }
    
    *output_len = strm.total_out;
    deflateEnd(&strm);
    return 0;
}

int main() {
    const char* test_data = "Hello, World! This is a test string for compression.";
    
    // Run buggy functions
    inflate_leak((const unsigned char*)test_data, strlen(test_data));
    deflate_leak((const unsigned char*)test_data, strlen(test_data));
    use_after_free_example(test_data);
    gzfile_leak("/tmp/test.gz", test_data);
    
    return 0;
}
