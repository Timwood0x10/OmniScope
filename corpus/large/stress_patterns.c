/*
 * Large Test: Generated FFI Patterns
 * This file contains many similar functions to test scalability
 * Expected Issues: 50+
 * - Multiple leaks
 * - Multiple use_after_free
 * - Multiple buffer_overflow
 * - Multiple format_string
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

// Generate repetitive patterns for stress testing

#define GEN_LEAK_FUNC(n) \
    void* leak_func_##n(void) { \
        void* p = malloc(64); \
        return p; \
    }

#define GEN_UAF_FUNC(n) \
    int uaf_func_##n(int* p) { \
        int v = *p; \
        free(p); \
        return *p; \
    }

#define GEN_OVERFLOW_FUNC(n) \
    void overflow_func_##n(const char* s) { \
        char buf[16]; \
        strcpy(buf, s); \
    }

#define GEN_FORMAT_FUNC(n) \
    void format_func_##n(const char* s) { \
        printf(s); \
    }

#define GEN_DOUBLE_FREE_FUNC(n) \
    void double_free_func_##n(void* p) { \
        free(p); \
        free(p); \
    }

#define GEN_SAFE_FUNC(n) \
    void* safe_func_##n(size_t sz) { \
        void* p = malloc(sz); \
        if (p) { \
            memset(p, 0, sz); \
        } \
        return p; \
    }

// Generate 10 of each pattern type
GEN_LEAK_FUNC(01) GEN_LEAK_FUNC(02) GEN_LEAK_FUNC(03) GEN_LEAK_FUNC(04) GEN_LEAK_FUNC(05)
GEN_LEAK_FUNC(06) GEN_LEAK_FUNC(07) GEN_LEAK_FUNC(08) GEN_LEAK_FUNC(09) GEN_LEAK_FUNC(10)

GEN_UAF_FUNC(01) GEN_UAF_FUNC(02) GEN_UAF_FUNC(03) GEN_UAF_FUNC(04) GEN_UAF_FUNC(05)
GEN_UAF_FUNC(06) GEN_UAF_FUNC(07) GEN_UAF_FUNC(08) GEN_UAF_FUNC(09) GEN_UAF_FUNC(10)

GEN_OVERFLOW_FUNC(01) GEN_OVERFLOW_FUNC(02) GEN_OVERFLOW_FUNC(03) GEN_OVERFLOW_FUNC(04) GEN_OVERFLOW_FUNC(05)
GEN_OVERFLOW_FUNC(06) GEN_OVERFLOW_FUNC(07) GEN_OVERFLOW_FUNC(08) GEN_OVERFLOW_FUNC(09) GEN_OVERFLOW_FUNC(10)

GEN_FORMAT_FUNC(01) GEN_FORMAT_FUNC(02) GEN_FORMAT_FUNC(03) GEN_FORMAT_FUNC(04) GEN_FORMAT_FUNC(05)
GEN_FORMAT_FUNC(06) GEN_FORMAT_FUNC(07) GEN_FORMAT_FUNC(08) GEN_FORMAT_FUNC(09) GEN_FORMAT_FUNC(10)

GEN_DOUBLE_FREE_FUNC(01) GEN_DOUBLE_FREE_FUNC(02) GEN_DOUBLE_FREE_FUNC(03) GEN_DOUBLE_FREE_FUNC(04) GEN_DOUBLE_FREE_FUNC(05)
GEN_DOUBLE_FREE_FUNC(06) GEN_DOUBLE_FREE_FUNC(07) GEN_DOUBLE_FREE_FUNC(08) GEN_DOUBLE_FREE_FUNC(09) GEN_DOUBLE_FREE_FUNC(10)

GEN_SAFE_FUNC(01) GEN_SAFE_FUNC(02) GEN_SAFE_FUNC(03) GEN_SAFE_FUNC(04) GEN_SAFE_FUNC(05)
GEN_SAFE_FUNC(06) GEN_SAFE_FUNC(07) GEN_SAFE_FUNC(08) GEN_SAFE_FUNC(09) GEN_SAFE_FUNC(10)

// Complex nested patterns
typedef struct {
    char* name;
    int* values;
    size_t count;
} DataStruct;

DataStruct* create_data_struct_leak(const char* name, size_t count) {
    DataStruct* ds = (DataStruct*)malloc(sizeof(DataStruct));
    if (ds == NULL) return NULL;
    
    ds->name = strdup(name);
    ds->values = (int*)malloc(count * sizeof(int));
    ds->count = count;
    
    // Leak: ds not freed if strdup or malloc fails
    if (ds->name == NULL || ds->values == NULL) {
        if (ds->name) free(ds->name);
        if (ds->values) free(ds->values);
        return NULL;  // ds leaked
    }
    
    return ds;
}

void free_data_struct(DataStruct* ds) {
    if (ds == NULL) return;
    free(ds->name);
    free(ds->values);
    free(ds);
}

// Use after free in nested structure
int access_after_free(DataStruct* ds) {
    free_data_struct(ds);
    return ds->count;  // Use after free
}

// Buffer overflow in nested structure
void copy_to_struct(DataStruct* ds, const char* data) {
    strcpy(ds->name, data);  // Potential overflow
}

// Format string in logging
void log_data_struct(DataStruct* ds) {
    printf("DataStruct: ");  // Safe
    printf(ds->name);         // Format string vulnerability
}

// Command injection via data
int execute_data_command(DataStruct* ds) {
    char cmd[256];
    sprintf(cmd, "process %s", ds->name);  // Potential overflow + injection
    return system(cmd);
}

// Recursive pattern
int recursive_leak(int depth) {
    if (depth <= 0) return 0;
    
    void* p = malloc(1024);
    if (p == NULL) return -1;
    
    int result = recursive_leak(depth - 1);
    // p leaked on every recursion
    return result;
}

// Loop pattern
void loop_leak(int iterations) {
    for (int i = 0; i < iterations; i++) {
        void* p = malloc(64);
        // p leaked every iteration
    }
}

// Conditional leak
int conditional_leak(int condition, const char* data) {
    char* buffer = (char*)malloc(256);
    if (buffer == NULL) return -1;
    
    strcpy(buffer, data);
    
    if (condition) {
        return strlen(buffer);  // buffer leaked
    } else {
        free(buffer);
        return 0;
    }
}

// Error path leak
int error_path_leak(const char* input) {
    char* buffer = (char*)malloc(256);
    if (buffer == NULL) return -1;
    
    if (input == NULL) {
        return -1;  // buffer leaked
    }
    
    strcpy(buffer, input);
    free(buffer);
    return 0;
}
