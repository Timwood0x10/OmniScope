/**
 * @file clib.c
 * @brief C implementation for Zig FFI testing
 */

#include "clib.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

int c_add(int a, int b) {
    return a + b;
}

int c_multiply(int a, int b) {
    return a * b;
}

void* c_alloc(size_t size) {
    return malloc(size);  // Line 18: MEDIUM risk
}

void c_free(void* ptr) {
    free(ptr);  // Line 22: HIGH risk
}

char* c_strdup(const char* s) {
    if (!s) return NULL;
    size_t len = strlen(s);
    char* result = malloc(len + 1);  // Line 28: MEDIUM risk
    if (result) {
        strcpy(result, s);  // Line 30: HIGH risk
    }
    return result;
}

void c_free_string(char* s) {
    free(s);  // Line 36: HIGH risk
}

void c_unsafe_copy(char* dest, const char* src) {
    strcpy(dest, src);  // Line 40: HIGH risk
}

void c_system_call(const char* cmd) {
    system(cmd);  // Line 44: CRITICAL risk
}
