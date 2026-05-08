/**
 * Cross-Language Free Violation Test Cases
 * 
 * Tests OmniScope's ability to detect alloc_lang != free_lang bugs
 * These are CWE-763 violations - releasing memory with wrong allocator
 * 
 * Test scenarios:
 * 1. Rust alloc → C free (classic FFI bug)
 * 2. C alloc → C++ delete (wrong allocator)
 * 3. malloc → free in same language (should NOT trigger)
 * 4. realloc chain across languages
 * 5. Alias chains: ptr1 = rust_alloc; ptr2 = ptr1; c_free(ptr2)
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

// Mock FFI boundary declarations
extern void* rust_box_new(int value);  // Allocates in Rust
extern void rust_box_free(void* ptr);  // Frees in Rust
extern void* cpp_new_object(int size); // Allocates in C++
extern void cpp_delete_object(void* ptr); // Frees in C++

// ============================================================================
// Case 1: Rust alloc → C free (CRITICAL BUG)
// ============================================================================
void bug_rust_alloc_c_free(void) {
    // Rust allocates via Box::into_raw()
    void* ptr = rust_box_new(42);  // alloc_lang = .rust
    
    // BUG: C's free() used on Rust-allocated memory
    free(ptr);  // free_lang = .c  → SHOULD DETECT cross_language_free
    
    // Expected: OmniScope reports cross_language_free violation
}

// ============================================================================
// Case 2: C alloc → C++ delete (CRITICAL BUG)
// ============================================================================
void bug_c_alloc_cpp_delete(void) {
    // C allocates
    void* ptr = malloc(128);  // alloc_lang = .c
    
    // BUG: C++ delete used on malloc'd memory
    cpp_delete_object(ptr);  // free_lang = .cpp  → SHOULD DETECT
    
    // Expected: cross_language_free
}

// ============================================================================
// Case 3: Same language - SHOULD NOT TRIGGER (happy path)
// ============================================================================
void safe_c_alloc_c_free(void) {
    void* ptr = malloc(64);  // alloc_lang = .c
    free(ptr);               // free_lang = .c
    
    // Expected: NO VIOLATION (same language)
}

void safe_rust_alloc_rust_free(void) {
    void* ptr = rust_box_new(100);  // alloc_lang = .rust
    rust_box_free(ptr);              // free_lang = .rust
    
    // Expected: NO VIOLATION
}

// ============================================================================
// Case 4: Alias chain with cross-language free
// ============================================================================
void bug_alias_chain_cross_lang(void) {
    void* ptr1 = rust_box_new(999);  // alloc_lang = .rust
    void* ptr2 = ptr1;                // alias: same AllocNode
    
    // BUG: Freeing alias with C free
    free(ptr2);  // free_lang = .c  → SHOULD DETECT via alias tracking
    
    // Expected: cross_language_free detected through alias chain
}

// ============================================================================
// Case 5: Double cross-language violation
// ============================================================================
void bug_double_cross_lang(void) {
    void* ptr1 = rust_box_new(1);
    void* ptr2 = cpp_new_object(256);
    
    // BUG 1: Rust alloc → C free
    free(ptr1);
    
    // BUG 2: C++ alloc → C free
    free(ptr2);
    
    // Expected: TWO cross_language_free reports
}

// ============================================================================
// Case 6: Realloc chain across languages
// ============================================================================
void bug_realloc_cross_lang(void) {
    void* ptr = rust_box_new(50);  // alloc_lang = .rust
    
    // BUG: C realloc on Rust memory
    void* new_ptr = realloc(ptr, 100);  // free_lang = .c (realloc frees old)
    
    if (new_ptr) {
        free(new_ptr);  // Additional free
    }
    
    // Expected: cross_language_free (realloc triggers free with wrong allocator)
}

// ============================================================================
// Case 7: Null pointer edge case (should not crash)
// ============================================================================
void edge_case_null_ptr(void) {
    void* ptr = NULL;
    free(ptr);  // Freeing null - should handle gracefully
    
    // Expected: NO CRASH, no false positive
}

// ============================================================================
// Case 8: Stack escape + cross-language free
// ============================================================================
void bug_stack_escape_cross_lang(void) {
    int local = 42;
    int* ptr = &local;  // Stack pointer
    
    // BUG: Freeing stack memory (invalid_free, NOT cross_language_free)
    free(ptr);
    
    // Expected: invalid_free (stack), NOT cross_language_free
}

// ============================================================================
// Case 9: Mixed ownership transfer
// ============================================================================
void bug_mixed_ownership(void) {
    // Rust allocates, transfers to C
    void* ptr = rust_box_new(777);  // alloc_lang = .rust
    
    // Some code uses ptr...
    memset(ptr, 0, sizeof(int));
    
    // BUG: C assumes ownership and frees
    free(ptr);  // free_lang = .c  → SHOULD DETECT
    
    // This is a real-world FFI ownership contract violation
}

// ============================================================================
// Case 10: Nested allocation with cross-lang free
// ============================================================================
typedef struct {
    void* inner_ptr;
    int value;
} Container;

void bug_nested_cross_lang(void) {
    Container* c = (Container*)malloc(sizeof(Container));  // alloc_lang = .c (outer)
    c->inner_ptr = rust_box_new(123);                      // alloc_lang = .rust (inner)
    
    // Free outer (correct)
    free(c);  // OK
    
    // BUG: Inner was Rust-allocated but now leaked
    // Then if someone tries to free inner_ptr:
    // free(c->inner_ptr);  // Would trigger cross_language_free
    
    // Expected: memory_leak for inner_ptr (not freed)
    // If freed: cross_language_free
}

// ============================================================================
// Main test runner
// ============================================================================
int main(void) {
    printf("Cross-Language Free Violation Tests\n");
    printf("====================================\n\n");
    
    printf("Test 1: Rust alloc → C free\n");
    bug_rust_alloc_c_free();
    
    printf("\nTest 2: C alloc → C++ delete\n");
    bug_c_alloc_cpp_delete();
    
    printf("\nTest 3: Safe same-language alloc/free\n");
    safe_c_alloc_c_free();
    safe_rust_alloc_rust_free();
    
    printf("\nTest 4: Alias chain cross-language\n");
    bug_alias_chain_cross_lang();
    
    printf("\nTest 5: Double cross-language violation\n");
    bug_double_cross_lang();
    
    printf("\nTest 6: Realloc cross-language\n");
    bug_realloc_cross_lang();
    
    printf("\nTest 7: Null pointer edge case\n");
    edge_case_null_ptr();
    
    printf("\nTest 8: Stack escape + cross-lang\n");
    bug_stack_escape_cross_lang();
    
    printf("\nTest 9: Mixed ownership transfer\n");
    bug_mixed_ownership();
    
    printf("\nTest 10: Nested allocation\n");
    bug_nested_cross_lang();
    
    printf("\n====================================\n");
    printf("Tests completed\n");
    
    return 0;
}
