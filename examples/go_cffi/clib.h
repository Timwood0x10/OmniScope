/**
 * @file clib.h
 * @brief C library for Go FFI testing
 */

#ifndef CLIB_H
#define CLIB_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Safe operations
int c_add(int a, int b);
int c_multiply(int a, int b);

// Memory operations
void* c_alloc(size_t size);
void c_free(void* ptr);
void* c_realloc(void* ptr, size_t size);

// String operations
char* c_strdup(const char* s);
void c_free_string(char* s);

// Dangerous operations
void c_unsafe_copy(char* dest, const char* src);
void c_system_call(const char* cmd);

#ifdef __cplusplus
}
#endif

#endif // CLIB_H
