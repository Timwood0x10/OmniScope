/**
 * @file math_ops.h
 * @brief C library for math operations - called from C++
 */

#ifndef MATH_OPS_H
#define MATH_OPS_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Safe operations
int c_add(int a, int b);
int c_multiply(int a, int b);

// Memory operations - for testing ownership tracking
int* c_create_array(size_t size);
void c_fill_array(int* arr, size_t size, int value);
void c_free_array(int* arr);

// Dangerous operations - for testing vulnerability detection
void c_unsafe_copy(char* dest, const char* src);
char* c_unsafe_concat(const char* a, const char* b);
void c_process_command(const char* cmd);

#ifdef __cplusplus
}
#endif

#endif // MATH_OPS_H
