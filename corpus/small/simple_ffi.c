/*
 * Small Test: Simple FFI Patterns
 * Expected Issues: 4
 * - 1 leak (malloc without free)
 * - 1 use_after_free
 * - 1 buffer_overflow
 * - 1 format_string
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

// Issue 1: leak - malloc without free
char* leak_example(const char* input) {
    char* buffer = (char*)malloc(256);
    if (buffer == NULL) return NULL;
    strcpy(buffer, input);
    return buffer;  // Caller may not free
}

// Issue 2: use_after_free
int use_after_free_example(int* ptr) {
    int value = *ptr;
    free(ptr);
    return *ptr;  // Use after free
}

// Issue 3: buffer_overflow
void buffer_overflow_example(const char* input) {
    char buffer[16];
    strcpy(buffer, input);  // Potential overflow
    printf("%s\n", buffer);
}

// Issue 4: format_string
void format_string_example(const char* user_input) {
    printf(user_input);  // Format string vulnerability
}

// Safe example for comparison
void safe_example(const char* input) {
    if (input == NULL) return;
    char* buffer = (char*)malloc(strlen(input) + 1);
    if (buffer != NULL) {
        strcpy(buffer, input);
        printf("%s\n", buffer);
        free(buffer);
    }
}
