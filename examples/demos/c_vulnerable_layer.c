// Vulnerable C Library
//
// This is the C library that C++ calls via extern "C".
// Despite C++ validation, this C code contains critical vulnerabilities.
//
// VULNERABILITIES:
// 1. c_process_input() - Buffer overflow in output buffer
// 2. c_execute_command() - Command injection via command parameter
// 3. c_parse_config() - Buffer overflow in config parsing

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Process user input
// VULNERABILITY: Buffer overflow in output buffer
int c_process_input(const char* input, char* output, int output_size) {
    printf("[C] c_process_input() called\n");
    printf("[C] Input: %s\n", input);

    // VULNERABILITY: No bounds checking on input length!
    // If input is very long, this will overflow output buffer
    strcpy(output, "Processed: ");
    strcat(output, input);  // Buffer overflow!

    printf("[C] Output: %s\n", output);
    printf("[C] WARNING: Output buffer may overflow!\n");

    return 0;
}

// Execute command
// VULNERABILITY: Command injection via command parameter
int c_execute_command(const char* command) {
    printf("[C] c_execute_command() called\n");
    printf("[C] Command: %s\n", command);

    // Build shell command
    char shell_command[512];

    // VULNERABILITY: Command parameter is not sanitized!
    // If command contains shell metacharacters, command injection occurs
    snprintf(shell_command, sizeof(shell_command),
             "/usr/bin/%s --execute 2>/dev/null",
             command);

    printf("[C] Executing: %s\n", shell_command);

    // Execute command - COMMAND INJECTION!
    int result = system(shell_command);

    printf("[C] Command completed with status: %d\n", result);
    return result;
}

// Parse configuration
// VULNERABILITY: Buffer overflow in config parsing
int c_parse_config(const char* config_data, char* parsed_result, int result_size) {
    printf("[C] c_parse_config() called\n");
    printf("[C] Config data length: %zu\n", strlen(config_data));

    // Parse key-value pairs
    const char* key = config_data;
    const char* value = strchr(config_data, '=');

    if (value) {
        value++; // Skip '='

        // VULNERABILITY: No bounds checking on key or value lengths!
        // If key or value is very long, this will overflow parsed_result buffer
        strcpy(parsed_result, "Key: ");
        strcat(parsed_result, key);
        strcat(parsed_result, ", Value: ");
        strcat(parsed_result, value);  // Buffer overflow!
    } else {
        strcpy(parsed_result, "Invalid config format");
    }

    printf("[C] Parsed result: %s\n", parsed_result);
    printf("[C] WARNING: Result buffer may overflow!\n");

    return 0;
}

// Format string vulnerability
// VULNERABILITY: Format string injection
int c_format_string(const char* user_data) {
    printf("[C] c_format_string() called\n");
    
    // VULNERABILITY: User input used as format string
    printf(user_data);  // Format string vulnerability!
    
    return 0;
}

// Integer overflow
// VULNERABILITY: Integer overflow in size calculation
void c_integer_overflow(int count, int element_size) {
    printf("[C] c_integer_overflow() called\n");
    
    // VULNERABILITY: No overflow check before multiplication
    int total_size = count * element_size;  // Integer overflow!
    char* buffer = malloc(total_size);
    
    if (buffer) {
        free(buffer);
    }
}

// Double free
// VULNERABILITY: Potential double free
void c_double_free(char* ptr) {
    printf("[C] c_double_free() called\n");
    
    if (ptr) {
        free(ptr);
        // In some conditions, ptr might be freed again
        // This is a simplified demonstration
    }
}

// Use after free
// VULNERABILITY: Use after free
void c_use_after_free() {
    printf("[C] c_use_after_free() called\n");
    
    char* ptr = malloc(100);
    strcpy(ptr, "sensitive data");
    
    free(ptr);
    
    // VULNERABILITY: Using freed pointer
    printf("[C] Data: %s\n", ptr);  // Use after free!
}