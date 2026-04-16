// FFI Benchmark Test - C Implementation
// This file contains known vulnerabilities for testing detection accuracy

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// SAFE: Normal function without FFI
void safe_function_c() {
    printf("Safe function\n");
}

// VULNERABILITY 1: Command injection (HIGH)
// Expected: Should be detected as FFI boundary and command injection vulnerability
void vulnerable_system_command(char* user_input) {
    char cmd[100];
    sprintf(cmd, "ls %s", user_input);  // Dangerous: user input in command
    system(cmd);  // VULNERABLE: Command injection
}

// VULNERABILITY 2: Buffer overflow (HIGH)
// Expected: Should be detected as FFI boundary and buffer overflow vulnerability
void vulnerable_buffer_overflow(char* input) {
    char buffer[10];
    strcpy(buffer, input);  // VULNERABILITY: No length check
}

// VULNERABILITY 3: Format string (HIGH)
// Expected: Should be detected as FFI boundary and format string vulnerability
void vulnerable_format_string(char* user_input) {
    printf(user_input);  // VULNERABILITY: User input as format string
}

// SAFE: Function with proper checking
void safe_with_length_check(char* input) {
    char buffer[10];
    if (strlen(input) < 10) {
        strcpy(buffer, input);  // Safe: Length checked
    }
}

// VULNERABILITY 4: Use after free potential (MEDIUM)
// Expected: Should be detected as potential use-after-free
void potential_use_after_free() {
    char* ptr = malloc(100);
    strcpy(ptr, "data");
    free(ptr);
    // ptr is now freed
    // Commented out to prevent actual crash in testing
    // printf("%s\n", ptr);  // VULNERABLE: Use after free
}

// SAFE: Proper memory management
void safe_memory_management() {
    char* ptr = malloc(100);
    if (ptr) {
        strcpy(ptr, "data");
        printf("%s\n", ptr);
        free(ptr);
    }
}

// VULNERABILITY 5: Integer overflow (MEDIUM)
// Expected: Should be detected as potential integer overflow
void potential_integer_overflow(int size) {
    char* buffer = malloc(size * 10);  // VULNERABILITY: Potential overflow
    if (buffer) {
        free(buffer);
    }
}

// SAFE: Function calling external API without vulnerability
void safe_external_call() {
    printf("External data\n");  // Safe: No user input
}

int main() {
    printf("FFI Benchmark Test - C Side\n");

    // Call various functions for testing
    safe_function_c();
    safe_with_length_check("test");
    safe_memory_management();
    safe_external_call();

    return 0;
}