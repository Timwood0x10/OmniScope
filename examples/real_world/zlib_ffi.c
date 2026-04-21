// Real-world FFI Test: zlib Compression Patterns
// Simplified version without external headers for testing

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Mock zlib types
typedef struct { char data[256]; } z_stream;

// Mock functions simulating zlib API
int deflateInit(z_stream *strm, int level) { return 0; }
int deflateEnd(z_stream *strm) { return 0; }
int inflateInit(z_stream *strm) { return 0; }
int inflateEnd(z_stream *strm) { return 0; }
int deflate(z_stream *strm, int flush) { return 0; }
int inflate(z_stream *strm, int flush) { return 0; }
void* gzopen(const char *path, const char *mode) { return malloc(100); }
int gzclose(void *file) { free(file); return 0; }
int gzwrite(void *file, const void *buf, unsigned int len) { return len; }
int gzread(void *file, void *buf, unsigned int len) { return len; }

// Issue: deflateInit requires deflateEnd
int compress_data(const unsigned char *input, size_t input_len,
                  unsigned char *output, size_t *output_len) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));

    int ret = deflateInit(&strm, 6);
    if (ret != 0) {
        return ret;
    }

    // Process...

    deflateEnd(&strm);
    return 0;
}

// Issue: inflateInit requires inflateEnd
int decompress_data(const unsigned char *input, size_t input_len,
                    unsigned char *output, size_t *output_len) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));

    int ret = inflateInit(&strm);
    if (ret != 0) {
        return ret;
    }

    // Process...

    inflateEnd(&strm);
    return 0;
}

// Issue: gzopen requires gzclose
int compress_file(const char *src_filename, const char *dest_filename) {
    FILE *src = fopen(src_filename, "rb");
    if (!src) return -1;

    void *dest = gzopen(dest_filename, "wb");
    if (!dest) {
        fclose(src);
        return -1;
    }

    unsigned char buffer[8192];
    size_t bytes_read;

    while ((bytes_read = fread(buffer, 1, sizeof(buffer), src)) > 0) {
        int written = gzwrite(dest, buffer, bytes_read);
        if (written == 0) {
            fclose(src);
            gzclose(dest);
            return -1;
        }
    }

    fclose(src);
    gzclose(dest);
    return 0;
}

// Issue: Resource leak in error path
int process_with_zlib_leak(const unsigned char *data, size_t len) {
    z_stream strm1;
    z_stream strm2;

    memset(&strm1, 0, sizeof(strm1));
    int ret = deflateInit(&strm1, 6);
    if (ret != 0) return -1;

    memset(&strm2, 0, sizeof(strm2));
    ret = deflateInit(&strm2, 6);
    if (ret != 0) {
        // Issue: strm1 not cleaned up
        return -1;
    }

    // Process...

    deflateEnd(&strm1);
    deflateEnd(&strm2);
    return 0;
}

// Issue: Double free potential
void double_free_zlib(void *file) {
    gzclose(file);

    // Issue: Double free
    gzclose(file);
}

// Issue: Memory leak - allocated but never freed
void* allocate_compression_buffer(size_t size) {
    void *buf = malloc(size);
    if (!buf) return NULL;

    // Issue: Never freed
    return buf;
}

// Correct pattern: proper cleanup
int correct_zlib_pattern(const unsigned char *input, size_t len) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));

    int ret = deflateInit(&strm, 6);
    if (ret != 0) return -1;

    // Process...

    deflateEnd(&strm);
    return 0;
}

// Issue: Use after free
int use_after_free_zlib(void *file) {
    gzclose(file);

    // Issue: Use after free
    gzwrite(file, "test", 4);

    return 0;
}
