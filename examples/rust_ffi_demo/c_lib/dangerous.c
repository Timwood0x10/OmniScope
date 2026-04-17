/**
 * @file dangerous.c
 * @brief C library with intentional vulnerabilities for OmniScope demo
 * 
 * SECURITY WARNING: This code contains INTENTIONAL vulnerabilities!
 * DO NOT use this code in production!
 * 
 * This file demonstrates security issues that OmniScope is designed to detect:
 * - Command injection
 * - Buffer overflow
 * - Missing null checks
 * - Double free
 * 
 * The key insight: Rust code may "sanitize" input, but C code assumes
 * it's safe. OmniScope detects this cross-language security gap.
 */

#include "dangerous.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Track freed pointers for double-free demo
static char* last_freed = NULL;

/**
 * Process input - COMMAND INJECTION VULNERABILITY
 * 
 * VULNERABILITY: Calls system() with user input
 * 
 * Attack vector:
 *   Input: "ls && rm -rf /"
 *   Result: Executes "ls" then "rm -rf /"
 * 
 * Why Rust "sanitization" doesn't help:
 *   - Rust removes semicolons: "ls; rm" -> "ls rm"
 *   - But attacker uses &&: "ls && rm" -> "ls && rm" (unchanged!)
 * 
 * OmniScope detection:
 *   - Tracks data flow from Rust stdin to C system()
 *   - Identifies FFI boundary as security-critical
 *   - Reports command injection vulnerability
 */
void dangerous_process(const char* input) {
    char command[256];
    
    // VULNERABILITY: No bounds checking!
    // If input > 256 chars, buffer overflow
    sprintf(command, "echo 'Processing: %s'", input);
    
    // VULNERABILITY: Command injection!
    // Attacker input flows directly to system()
    // This is the critical security flaw
    system(command);
    
    // Additional vulnerability: format string
    // If input contains %s, %x, etc., could leak memory
    printf(input);  // Format string vulnerability
    printf("\n");
}

/**
 * Copy data - BUFFER OVERFLOW VULNERABILITY
 * 
 * VULNERABILITY: Uses strcpy() without bounds checking
 * 
 * Attack vector:
 *   Input: 100+ character string
 *   Result: Buffer overflow, potential code execution
 * 
 * Why this is dangerous:
 *   - Rust allocates 64-byte buffer
 *   - C uses strcpy() which copies until null terminator
 *   - No size validation!
 * 
 * OmniScope detection:
 *   - Tracks buffer size from Rust (64 bytes)
 *   - Detects unbounded strcpy() in C
 *   - Reports buffer overflow vulnerability
 */
void dangerous_copy(char* dest, const char* src) {
    // VULNERABILITY: No bounds checking!
    // If src > dest buffer, overflow occurs
    strcpy(dest, src);
    
    // This looks "safe" because we trust Rust
    // But Rust doesn't know C is using strcpy!
}

/**
 * Allocate buffer - NULL DEREFERENCE VULNERABILITY
 * 
 * VULNERABILITY: malloc() result not checked
 * 
 * Attack vector:
 *   - Trigger out-of-memory condition
 *   - malloc() returns NULL
 *   - Code crashes on null pointer access
 * 
 * OmniScope detection:
 *   - Detects malloc() call
 *   - No null check before use
 *   - Reports missing null check vulnerability
 */
char* dangerous_alloc(size_t size) {
    // VULNERABILITY: No null check!
    char* buffer = malloc(size);
    
    // Using buffer without checking if malloc succeeded
    // This will crash if malloc returns NULL
    buffer[0] = '\0';  // CRASH if buffer == NULL
    
    return buffer;
}

/**
 * Free memory - DOUBLE FREE VULNERABILITY
 * 
 * VULNERABILITY: No tracking of freed pointers
 * 
 * Attack vector:
 *   - Call dangerous_free() twice on same pointer
 *   - Double free causes undefined behavior
 *   - Potential for exploitation
 * 
 * OmniScope detection:
 *   - Tracks free() calls
 *   - Detects multiple frees of same pointer
 *   - Reports double free vulnerability
 */
void dangerous_free(char* ptr) {
    // VULNERABILITY: No tracking of freed pointers
    // Could be called twice on same pointer
    
    if (ptr == last_freed) {
        // Double free detected - but too late!
        // This check is AFTER the free, not before
        // Still vulnerable!
    }
    
    free(ptr);
    last_freed = ptr;  // Track for demo (but doesn't prevent double-free)
}

/**
 * Helper function for demo
 * Shows what "safe" code would look like
 */
void safe_process(const char* input) {
    // This is what SAFE code would look like:
    
    // 1. Check for null input
    if (input == NULL) {
        fprintf(stderr, "Error: null input\n");
        return;
    }
    
    // 2. Validate input length
    size_t len = strlen(input);
    if (len > 200) {
        fprintf(stderr, "Error: input too long\n");
        return;
    }
    
    // 3. Validate input characters (whitelist approach)
    for (size_t i = 0; i < len; i++) {
        char c = input[i];
        if (!((c >= 'a' && c <= 'z') || 
              (c >= 'A' && c <= 'Z') || 
              (c >= '0' && c <= '9') || 
              c == ' ' || c == '-' || c == '_')) {
            fprintf(stderr, "Error: invalid character in input\n");
            return;
        }
    }
    
    // 4. Use safe string functions
    char command[256];
    snprintf(command, sizeof(command), "echo '%s'", input);
    
    // 5. Still not recommended to call system() with user input!
    // Use execve() with argument array instead
    printf("Would execute: %s\n", command);
}
