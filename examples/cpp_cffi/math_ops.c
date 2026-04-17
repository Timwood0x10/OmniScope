/**
 * @file math_ops.c
 * @brief C implementation of math operations
 * 
 * Contains intentional vulnerabilities for OmniScope testing:
 * - Buffer overflow in c_unsafe_copy
 * - Memory leak potential in c_unsafe_concat
 * - Command injection in c_process_command
 */

#include "math_ops.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Safe operations
int c_add(int a, int b) {
    return a + b;
}

int c_multiply(int a, int b) {
    return a * b;
}

// Memory operations with ownership semantics
int* c_create_array(size_t size) {
    // Allocates memory - ownership transferred to caller
    int* arr = (int*)malloc(size * sizeof(int));
    if (arr) {
        for (size_t i = 0; i < size; i++) {
            arr[i] = 0;
        }
    }
    return arr;
}

void c_fill_array(int* arr, size_t size, int value) {
    // Borrows array - does not take ownership
    if (arr) {
        for (size_t i = 0; i < size; i++) {
            arr[i] = value;
        }
    }
}

void c_free_array(int* arr) {
    // Takes ownership and frees
    free(arr);
}

// Dangerous operations - intentional vulnerabilities

void c_unsafe_copy(char* dest, const char* src) {
    // VULNERABILITY: No bounds checking!
    // Buffer overflow if src is larger than dest
    strcpy(dest, src);  // Line 52: HIGH risk
}

char* c_unsafe_concat(const char* a, const char* b) {
    size_t len_a = strlen(a);
    size_t len_b = strlen(b);
    
    char* result = (char*)malloc(len_a + len_b + 1);  // Line 59: MEDIUM risk
    if (result) {
        strcpy(result, a);  // Line 61: HIGH risk
        strcat(result, b);  // Line 62: HIGH risk
    }
    return result;  // Ownership transferred to caller
}

void c_process_command(const char* cmd) {
    // VULNERABILITY: Command injection!
    char buffer[256];
    snprintf(buffer, sizeof(buffer), "echo %s", cmd);
    system(buffer);  // Line 72: CRITICAL risk
}
