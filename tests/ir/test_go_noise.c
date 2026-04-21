//! Test file for go_noise.md validation
//! This file contains examples that should trigger all 4 rules from go_noise.md

#include <stdlib.h>
#include <stdio.h>

// Rule 1: malloc unchecked
char* rule1_malloc_unchecked(int size) {
    char* buffer = (char*)malloc(size);  // Should be caught: malloc not checked
    buffer[0] = 'A';  // Use without null check
    return buffer;
}

// Rule 2: free non-malloc
void rule2_free_non_malloc(char* param) {
    char* stack_buffer = "test";
    free(param);      // OK if param came from malloc
    free(stack_buffer);  // Should be caught: free non-malloc
}

// Rule 3: double free
void rule3_double_free() {
    char* ptr = (char*)malloc(100);
    free(ptr);
    free(ptr);  // Should be caught: double free
}

// Rule 4: unknown FFI pointer usage
void rule4_unknown_ffi() {
    char* buffer = (char*)malloc(100);
    // Simulating unknown external function call
    // In real IR this would be an external function without implementation
    // For testing purposes, we use printf which should be in low_risk category
    printf("Buffer: %p\n", (void*)buffer);
    free(buffer);
}

int main() {
    rule1_malloc_unchecked(50);
    
    char* safe_malloc = (char*)malloc(50);
    if (safe_malloc != NULL) {  // Safe: malloc checked
        rule2_free_non_malloc(safe_malloc);
    }
    
    rule3_double_free();
    rule4_unknown_ffi();
    
    return 0;
}