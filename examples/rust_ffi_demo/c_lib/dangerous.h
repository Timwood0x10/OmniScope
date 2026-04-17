/**
 * @file dangerous.h
 * @brief C library with intentional vulnerabilities for OmniScope demo
 * 
 * SECURITY WARNING: This code contains INTENTIONAL vulnerabilities!
 * DO NOT use this code in production!
 * 
 * Purpose: Demonstrate cross-language security issues that OmniScope can detect:
 * 1. Command injection via system()
 * 2. Buffer overflow via strcpy()
 * 3. Missing null checks after malloc()
 */

#ifndef DANGEROUS_H
#define DANGEROUS_H

#include <stddef.h>

/**
 * Process input string - VULNERABLE TO COMMAND INJECTION
 * 
 * SECURITY FLAW:
 * - Calls system() with user input
 * - No validation or sanitization
 * - Attacker can execute arbitrary commands
 * 
 * OmniScope should detect:
 * - External input flows to system() call
 * - Cross-language FFI boundary (Rust -> C)
 */
void dangerous_process(const char* input);

/**
 * Copy data - VULNERABLE TO BUFFER OVERFLOW
 * 
 * SECURITY FLAW:
 * - Uses strcpy() without bounds checking
 * - No size validation
 * - Attacker can overflow buffer
 * 
 * OmniScope should detect:
 * - Unbounded copy to fixed-size buffer
 * - Cross-language memory safety issue
 */
void dangerous_copy(char* dest, const char* src);

/**
 * Allocate buffer - VULNERABLE TO NULL DEREFERENCE
 * 
 * SECURITY FLAW:
 * - malloc() return not checked for NULL
 * - Could crash on out-of-memory
 * 
 * OmniScope should detect:
 * - malloc() result used without null check
 */
char* dangerous_alloc(size_t size);

/**
 * Free memory - POTENTIAL DOUBLE FREE
 * 
 * SECURITY FLAW:
 * - No tracking of freed pointers
 * - Could be called twice on same pointer
 * 
 * OmniScope should detect:
 * - Potential double free vulnerability
 */
void dangerous_free(char* ptr);

#endif /* DANGEROUS_H */
